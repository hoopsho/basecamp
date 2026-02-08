# frozen_string_literal: true

class AgentLoopJob < ApplicationJob
  queue_as :default

  # Prevent overlapping runs for the same agent
  lock_strategy :until_executed
  lock_ttl 10.minutes

  def perform(agent_slug)
    agent = Agent.find_by(slug: agent_slug)

    unless agent
      Rails.logger.error "Agent not found: #{agent_slug}"
      return
    end

    return unless agent.active?
    return unless agent.has_loop?

    Rails.logger.info "AgentLoopJob starting for #{agent.name}"

    # 1. SURVEY DOMAIN
    survey = survey_domain(agent)

    # 2. ASSESS
    assessment = assess(agent, survey)

    # 3. PRIORITIZE
    priority_action = prioritize(agent, assessment)

    # 4. EXECUTE (one major action per loop)
    if priority_action
      execute_action(agent, priority_action)
    end

    # 5. REPORT
    report(agent, survey, assessment, priority_action)

    Rails.logger.info "AgentLoopJob completed for #{agent.name}"
  rescue StandardError => e
    Rails.logger.error "AgentLoopJob error for #{agent_slug}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")

    # Post error to Slack
    SlackService.post_message(
      channel: '#escalations',
      text: ":rotating_light: Agent loop failed for #{agent.name}: #{e.message}"
    )

    raise
  end

  private

  def survey_domain(agent)
    {
      active_tasks: agent.tasks.active.count,
      pending_tasks: agent.tasks.pending.count,
      waiting_on_human: agent.tasks.where(status: :waiting_on_human).count,
      failed_tasks: agent.tasks.failed.where('updated_at > ?', 1.hour.ago).count,
      watchers_ready: agent.watchers.ready_to_check.count,
      recent_memories: load_recent_memories(agent),
      high_importance_memories: load_high_importance_memories(agent)
    }
  end

  def load_recent_memories(agent)
    agent.agent_memories
         .active
         .where('created_at > ?', 24.hours.ago)
         .order(importance: :desc)
         .limit(10)
         .pluck(:content)
  end

  def load_high_importance_memories(agent)
    agent.agent_memories
         .active
         .important
         .order(created_at: :desc)
         .limit(5)
         .pluck(:content)
  end

  def assess(agent, survey)
    assessment = {
      needs_attention: false,
      concerns: [],
      opportunities: []
    }

    # Check for failed tasks
    if survey[:failed_tasks] > 0
      assessment[:needs_attention] = true
      assessment[:concerns] << "#{survey[:failed_tasks]} failed tasks in the last hour"
    end

    # Check for tasks waiting on human too long
    long_waiting = agent.tasks.where(status: :waiting_on_human)
                               .where('updated_at < ?', 2.hours.ago)
                               .count
    if long_waiting > 0
      assessment[:needs_attention] = true
      assessment[:concerns] << "#{long_waiting} tasks waiting on human for > 2 hours"
    end

    # Check for high-priority pending tasks
    high_priority_pending = agent.tasks.pending.where('priority > ?', 7).count
    if high_priority_pending > 0
      assessment[:needs_attention] = true
      assessment[:opportunities] << "#{high_priority_pending} high-priority pending tasks"
    end

    # Check for ready watchers
    if survey[:watchers_ready] > 0
      assessment[:opportunities] << "#{survey[:watchers_ready]} watchers ready to check"
    end

    assessment
  end

  def prioritize(agent, assessment)
    # Priority order:
    1. Failed tasks (most urgent)
    # 2. High-priority pending tasks
    # 3. Ready watchers (proactive)
    # 4. Regular pending tasks

    if agent.tasks.failed.where('updated_at > ?', 1.hour.ago).any?
      return {
        type: :escalate_failed_tasks,
        description: 'Escalate failed tasks'
      }
    end

    high_priority = agent.tasks.pending.by_priority.first
    if high_priority
      return {
        type: :process_task,
        task: high_priority,
        description: "Process high-priority task: #{high_priority.sop.name}"
      }
    end

    ready_watcher = agent.watchers.ready_to_check.first
    if ready_watcher
      return {
        type: :run_watcher,
        watcher: ready_watcher,
        description: "Run watcher: #{ready_watcher.name}"
      }
    end

    pending_task = agent.tasks.pending.by_priority.first
    if pending_task
      return {
        type: :process_task,
        task: pending_task,
        description: "Process pending task: #{pending_task.sop.name}"
      }
    end

    # Nothing needs doing
    nil
  end

  def execute_action(agent, action)
    case action[:type]
    when :process_task
      task = action[:task]
      task.mark_started!
      TaskWorkerJob.perform_later(task.id)

      create_memory(agent, "Processed task #{task.id} for #{task.sop.name}", 7)

    when :run_watcher
      watcher = action[:watcher]
      WatcherJob.perform_later(watcher.id)

      create_memory(agent, "Ran watcher: #{watcher.name}", 5)

    when :escalate_failed_tasks
      failed_tasks = agent.tasks.failed.where('updated_at > ?', 1.hour.ago)

      failed_tasks.each do |task|
        SlackService.post_escalation(task, 'Task failed and needs attention')
      end

      create_memory(agent, "Escalated #{failed_tasks.count} failed tasks", 8)
    end
  end

  def report(agent, survey, assessment, action)
    # Post heartbeat to ops-log
    status_emoji = assessment[:needs_attention] ? ':warning:' : ':white_check_mark:'

    message = <<~MSG
      #{status_emoji} *#{agent.name}* - Loop Complete

      Survey:
      • Active tasks: #{survey[:active_tasks]}
      • Pending: #{survey[:pending_tasks]}
      • Waiting on human: #{survey[:waiting_on_human]}
      • Failed (1h): #{survey[:failed_tasks]}
      • Watchers ready: #{survey[:watchers_ready]}

      Action: #{action ? action[:description] : 'No action needed'}
    MSG

    SlackService.post_message(
      channel: '#ops-log',
      text: message,
      username: agent.name,
      icon_emoji: ':robot_face:'
    )

    # Post to agent's channel if there are concerns
    if assessment[:needs_attention] && agent.slack_channel
      concerns_message = assessment[:concerns].join("\n• ")

      SlackService.post_message(
        channel: agent.slack_channel,
        text: ":warning: Attention needed:\n• #{concerns_message}",
        username: agent.name,
        icon_emoji: ':robot_face:'
      )
    end
  end

  def create_memory(agent, content, importance = 5)
    AgentMemory.create!(
      agent: agent,
      memory_type: :observation,
      content: content,
      importance: importance,
      expires_at: importance >= 8 ? nil : 7.days.from_now
    )
  end
end
