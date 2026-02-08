# frozen_string_literal: true

class HumanResponseJob < ApplicationJob
  queue_as :default

  def perform(task_id, response_data)
    task = Task.find(task_id)

    unless task.waiting_on_human?
      Rails.logger.warn "Task #{task_id} is not waiting on human (status: #{task.status})"
      return
    end

    # Parse response data
    action = response_data['action'] || response_data[:action]
    response_text = response_data['text'] || response_data[:text]
    user_id = response_data['user_id'] || response_data[:user_id]

    # Log the human response
    TaskEvent.create!(
      task: task,
      step: task.current_step,
      event_type: :human_responded,
      input_data: {
        action: action,
        response_text: response_text,
        responded_by: user_id
      },
      created_at: Time.current
    )

    # Update task context with human response
    task.set_context_key('human_response', {
      action: action,
      text: response_text,
      responded_at: Time.current.iso8601,
      responded_by: user_id
    })

    # Handle the action
    case action
    when 'approve', 'send'
      handle_approval(task)
    when 'reject', 'cancel'
      handle_rejection(task, response_text)
    when 'edit'
      handle_edit_request(task, response_text)
    when 'escalate'
      handle_escalation(task, response_text)
    else
      handle_custom_action(task, action, response_text)
    end

    # Post confirmation to Slack thread
    SlackService.reply_in_thread(
      channel: task.agent&.slack_channel || '#ops-log',
      thread_ts: task.slack_thread_ts,
      text: ":white_check_mark: Human responded: #{action}"
    ) if task.slack_thread_ts

  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Task not found: #{task_id}"
  rescue StandardError => e
    Rails.logger.error "HumanResponseJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end

  private

  def handle_approval(task)
    # Resume task execution
    task.update!(status: :in_progress)

    # Enqueue next step
    current_step = task.current_step
    next_position = current_step&.next_step_position || task.current_step_position + 1

    TaskWorkerJob.perform_later(task.id, next_position)
  end

  def handle_rejection(task, reason)
    # Mark task as failed
    task.mark_failed!(reason || 'Rejected by human')

    # Notify
    SlackService.post_message(
      channel: task.agent&.slack_channel || '#ops-log',
      text: ":x: Task rejected: #{task.sop.name} - #{reason}",
      thread_ts: task.slack_thread_ts
    ) if task.slack_thread_ts
  end

  def handle_edit_request(task, edit_text)
    # Store edit in context
    task.set_context_key('human_edit', edit_text)

    # Resume with edited content
    task.update!(status: :in_progress)

    # Enqueue next step
    current_step = task.current_step
    next_position = current_step&.next_step_position || task.current_step_position + 1

    TaskWorkerJob.perform_later(task.id, next_position)
  end

  def handle_escalation(task, reason)
    task.mark_escalated!

    SlackService.post_escalation(task, reason || 'Manual escalation by human')
  end

  def handle_custom_action(task, action, response_text)
    # Store custom action in context
    task.set_context_key('custom_action', {
      action: action,
      text: response_text
    })

    # Resume task
    task.update!(status: :in_progress)

    # Enqueue next step
    current_step = task.current_step
    next_position = current_step&.next_step_position || task.current_step_position + 1

    TaskWorkerJob.perform_later(task.id, next_position)
  end
end
