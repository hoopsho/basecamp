# frozen_string_literal: true

class TaskWorkerJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(task_id, step_position = nil)
    task = Task.find(task_id)

    # If step_position not provided, use current from task
    step_position ||= task.current_step_position

    # If task is not in an active state, don't process
    return unless task.active?

    # Get the step to execute
    step = task.sop.step_at_position(step_position)

    unless step
      # No more steps, mark task as completed
      task.mark_completed!
      log_event(task, nil, :step_completed, { message: 'Task completed - no more steps' })
      return
    end

    # Update task current step
    task.update!(current_step_position: step_position)

    # Execute the step
    execute_step(task, step)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Task not found: #{task_id}"
  rescue StandardError => e
    Rails.logger.error "TaskWorkerJob error for task #{task_id}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")

    # Try to log the error if we have the task
    if defined?(task) && task
      task.update!(status: :failed, error_message: e.message)
      log_event(task, step, :error, {
        error: e.message,
        backtrace: e.backtrace.first(5)
      })
    end

    raise
  end

  private

  def execute_step(task, step)
    start_time = Time.current

    # Log step started
    log_event(task, step, :step_started, { step_type: step.step_type })

    # Execute based on step type
    result = case step.step_type
    when 'query'
      execute_query_step(task, step)
    when 'api_call'
      execute_api_call_step(task, step)
    when 'llm_classify', 'llm_draft', 'llm_decide', 'llm_analyze'
      execute_llm_step(task, step)
    when 'slack_notify'
      execute_slack_notify_step(task, step)
    when 'slack_ask_human'
      execute_slack_ask_human_step(task, step)
    when 'enqueue_next'
      execute_enqueue_next_step(task, step)
    when 'wait'
      execute_wait_step(task, step)
    else
      { success: false, error: "Unknown step type: #{step.step_type}" }
    end

    duration = ((Time.current - start_time) * 1000).round

    # Handle result
    if result[:success]
      handle_success(task, step, result, duration)
    else
      handle_failure(task, step, result, duration)
    end
  end

  def execute_query_step(task, step)
    config = step.config_hash
    query_type = config['query_type']

    case query_type
    when 'crm_customer'
      customer_id = task.context_key('customer_id')
      result = CrmService.find(customer_id)

      if result[:success]
        task.set_context_key('customer_data', result[:customer])
        { success: true, data: result[:customer] }
      else
        { success: false, error: result[:error] }
      end
    when 'crm_search'
      filters = config['filters'] || {}
      result = CrmService.query(filters)

      if result[:success]
        task.set_context_key('query_results', result[:customers])
        { success: true, count: result[:count] }
      else
        { success: false, error: result[:error] }
      end
    else
      { success: false, error: "Unknown query type: #{query_type}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_api_call_step(task, step)
    config = step.config_hash
    api_name = config['api']
    action = config['action']

    case api_name
    when 'email'
      if action == 'send'
        send_email(task, config)
      else
        { success: false, error: "Unknown email action: #{action}" }
      end
    when 'crm'
      if action == 'update_customer'
        update_customer(task, config)
      elsif action == 'record_interaction'
        record_interaction(task, config)
      else
        { success: false, error: "Unknown CRM action: #{action}" }
      end
    else
      { success: false, error: "Unknown API: #{api_name}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_llm_step(task, step)
    config = step.config_hash
    prompt_template = step.prompt_template

    # Build context from task
    context = {
      system: config['system_prompt'] || default_system_prompt(step),
      task: task.context || {}
    }

    # Call LLM service
    result = LlmService.call(
      prompt: prompt_template,
      context: context,
      min_tier: step.min_tier,
      max_tier: step.max_llm_tier,
      step: step,
      task: task
    )

    # Store result in task context
    task.set_context_key("step_#{step.position}_result", result[:response])
    task.set_context_key("step_#{step.position}_confidence", result[:confidence])

    if result[:escalated] && result[:confidence] < LlmService::CONFIDENCE_THRESHOLD
      # Still not confident after max tier
      handle_low_confidence(task, step, result)
    end

    {
      success: true,
      response: result[:response],
      confidence: result[:confidence],
      tier_used: result[:tier_used]
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_slack_notify_step(task, step)
    config = step.config_hash
    message = interpolate_template(config['message'], task.context)
    channel = config['channel'] || task.agent&.slack_channel || '#ops-log'

    result = SlackService.post_message(
      channel: channel,
      text: message,
      thread_ts: task.slack_thread_ts
    )

    if result[:success] && task.slack_thread_ts.nil?
      task.update!(slack_thread_ts: result[:ts])
    end

    { success: result[:success], error: result[:error] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_slack_ask_human_step(task, step)
    config = step.config_hash
    prompt = interpolate_template(config['prompt'], task.context)

    options = config['options'] || [
      { value: 'approve', label: 'Approve', style: 'primary' },
      { value: 'reject', label: 'Reject', style: 'default' }
    ]

    result = SlackService.post_interactive_message(
      channel: task.agent&.slack_channel || '#ops-log',
      text: prompt,
      actions: options,
      thread_ts: task.slack_thread_ts,
      callback_id: "task_#{task.id}_step_#{step.position}"
    )

    if result[:success]
      task.update!(status: :waiting_on_human)

      # Log the human request
      TaskEvent.create!(
        task: task,
        step: step,
        event_type: :human_requested,
        input_data: { prompt: prompt, options: options.map { |o| o[:value] } },
        created_at: Time.current
      )

      { success: true, status: :waiting }
    else
      { success: false, error: result[:error] }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_enqueue_next_step(task, step)
    config = step.config_hash

    if config['sop_slug']
      # Enqueue a different SOP
      sop = Sop.active.find_by(slug: config['sop_slug'])

      unless sop
        return { success: false, error: "SOP not found: #{config['sop_slug']}" }
      end

      new_task = Task.create!(
        sop: sop,
        agent: sop.agent,
        parent_task: task,
        context: task.context.merge(config['context_override'] || {}),
        priority: config['priority'] || task.priority
      )

      TaskWorkerJob.perform_later(new_task.id)

      { success: true, enqueued_task_id: new_task.id }
    elsif config['wait_duration']
      # Schedule this task to continue after a delay
      next_position = step.position + 1

      TaskWorkerJob.set(wait: config['wait_duration'].to_i.minutes)
                   .perform_later(task.id, next_position)

      task.update!(status: :waiting_on_timer)

      { success: true, status: :scheduled }
    else
      { success: false, error: 'No action specified in enqueue_next step' }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def execute_wait_step(task, step)
    config = step.config_hash
    duration = config['duration_minutes'] || 5

    next_position = step.position + 1

    TaskWorkerJob.set(wait: duration.to_i.minutes)
                 .perform_later(task.id, next_position)

    task.update!(status: :waiting_on_timer)

    { success: true, status: :waiting, duration: duration }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def handle_success(task, step, result, duration)
    # Log completion
    log_event(task, step, :step_completed, {
      result: result,
      duration_ms: duration
    })

    # Determine next step
    next_position = step.next_step_position

    if next_position
      # Enqueue next step
      TaskWorkerJob.perform_later(task.id, next_position)
    else
      # Task complete
      task.mark_completed!

      # Final Slack notification
      SlackService.post_message(
        channel: task.agent&.slack_channel || '#ops-log',
        text: ":white_check_mark: Task completed: #{task.sop.name}",
        thread_ts: task.slack_thread_ts
      ) if task.slack_thread_ts
    end
  end

  def handle_failure(task, step, result, duration)
    # Log failure
    log_event(task, step, :step_failed, {
      error: result[:error],
      duration_ms: duration
    })

    # Handle based on on_failure setting
    case step.on_failure
    when 'retry'
      # Will be retried by job retry mechanism
      raise StandardError, result[:error]
    when 'escalate'
      task.mark_escalated!
      SlackService.post_escalation(task, result[:error])
    when 'fail'
      task.mark_failed!(result[:error])
    else
      # Try to go to specified step
      if step.on_failure.match?(/^\d+$/)
        TaskWorkerJob.perform_later(task.id, step.on_failure.to_i)
      else
        task.mark_failed!(result[:error])
      end
    end
  end

  def handle_low_confidence(task, step, result)
    # Post to escalations channel
    SlackService.post_escalation(
      task,
      "Low confidence (#{result[:confidence].round(2)}) after max tier (#{result[:tier_used]})"
    )
  end

  def send_email(task, config)
    to = interpolate_template(config['to'], task.context)
    subject = interpolate_template(config['subject'], task.context)
    template = config['template']

    variables = task.context.merge(config['variables'] || {})

    result = EmailService.send_template(
      to: to,
      template_name: template,
      variables: variables
    )

    if result[:success]
      task.set_context_key('email_sent', true)
      task.set_context_key('email_message_id', result[:message_id])
    end

    { success: result[:success], error: result[:error] }
  end

  def update_customer(task, config)
    customer_id = task.context_key('customer_id')
    attributes = config['attributes'] || {}

    # Interpolate any template values
    interpolated = attributes.transform_values do |value|
      value.is_a?(String) ? interpolate_template(value, task.context) : value
    end

    result = CrmService.update(customer_id, interpolated)

    { success: result[:success], error: result[:error] }
  end

  def record_interaction(task, config)
    customer_id = task.context_key('customer_id')
    interaction_type = config['interaction_type']
    details = config['details'] || {}

    result = CrmService.record_interaction(customer_id, interaction_type, details)

    { success: result[:success], error: result[:error] }
  end

  def default_system_prompt(step)
    "You are assisting with: #{step.name}. Respond with JSON including 'response' and 'confidence' (0.0-1.0)."
  end

  def interpolate_template(template, variables)
    return template unless template.is_a?(String)

    result = template.dup
    (variables || {}).each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  def log_event(task, step, event_type, data)
    TaskEvent.create!(
      task: task,
      step: step,
      event_type: event_type,
      input_data: data,
      created_at: Time.current
    )
  end
end
