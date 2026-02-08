# frozen_string_literal: true

class DailySummaryJob < ApplicationJob
  queue_as :default

  BUDGET_WARNING_THRESHOLD = 10.0
  BUDGET_ALERT_THRESHOLD = 25.0
  BUDGET_CRITICAL_THRESHOLD = 50.0

  def perform
    Rails.logger.info "DailySummaryJob starting at #{Time.current}"

    # Gather metrics
    metrics = gather_metrics

    # Calculate costs
    daily_cost = calculate_daily_cost

    # Generate summary
    summary = build_summary(metrics, daily_cost)

    # Post to ops-log
    SlackService.post_message(
      channel: '#ops-log',
      text: summary,
      username: 'SOP Engine',
      icon_emoji: ':chart_with_upwards_trend:'
    )

    # Check budget thresholds
    check_budget_thresholds(daily_cost)

    Rails.logger.info 'DailySummaryJob completed'
  rescue StandardError => e
    Rails.logger.error "DailySummaryJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    raise
  end

  private

  def gather_metrics
    today = Time.current.beginning_of_day

    {
      tasks_created: Task.where('created_at >= ?', today).count,
      tasks_completed: Task.where(status: :completed).where('completed_at >= ?', today).count,
      tasks_failed: Task.where(status: [ :failed, :escalated ]).where('updated_at >= ?', today).count,
      tasks_waiting_human: Task.where(status: :waiting_on_human).count,
      llm_calls: TaskEvent.where(event_type: [ :llm_call, :llm_escalated ]).where('created_at >= ?', today).count,
      human_interactions: TaskEvent.where(event_type: [ :human_requested, :human_responded ]).where('created_at >= ?', today).count,
      active_agents: Agent.active.count,
      active_watchers: Watcher.active.count
    }
  end

  def calculate_daily_cost
    today = Time.current.beginning_of_day

    llm_events = TaskEvent.where(event_type: [ :llm_call, :llm_escalated ])
                          .where('created_at >= ?', today)

    tier_costs = {
      1 => 0.001,
      2 => 0.01,
      3 => 0.10
    }

    llm_events.sum do |event|
      next 0 if event.llm_tier_used.nil? || event.llm_tier_used == 0

      tier_costs[event.llm_tier_used] || 0
    end
  end

  def calculate_monthly_cost
    beginning_of_month = Time.current.beginning_of_month

    llm_events = TaskEvent.where(event_type: [ :llm_call, :llm_escalated ])
                          .where('created_at >= ?', beginning_of_month)

    tier_costs = {
      1 => 0.001,
      2 => 0.01,
      3 => 0.10
    }

    llm_events.sum do |event|
      next 0 if event.llm_tier_used.nil? || event.llm_tier_used == 0

      tier_costs[event.llm_tier_used] || 0
    end
  end

  def build_summary(metrics, daily_cost)
    monthly_cost = calculate_monthly_cost

    <<~SUMMARY
      :chart_with_upwards_trend: *Daily Operations Summary* - #{Time.current.strftime('%B %d, %Y')}

      *Task Activity:*
      • Created today: #{metrics[:tasks_created]}
      • Completed today: #{metrics[:tasks_completed]}
      • Failed today: #{metrics[:tasks_failed]}
      • Waiting on human: #{metrics[:tasks_waiting_human]}

      *Interactions:*
      • LLM calls today: #{metrics[:llm_calls]}
      • Human interactions today: #{metrics[:human_interactions]}

      *System Status:*
      • Active agents: #{metrics[:active_agents]}
      • Active watchers: #{metrics[:active_watchers]}

      *Costs:*
      • Today: $#{daily_cost.round(4)}
      • Month to date: $#{monthly_cost.round(2)}
    SUMMARY
  end

  def check_budget_thresholds(daily_cost)
    return if daily_cost < BUDGET_WARNING_THRESHOLD

    if daily_cost >= BUDGET_CRITICAL_THRESHOLD
      post_budget_alert(:critical, daily_cost)
      pause_non_essential_agents
    elsif daily_cost >= BUDGET_ALERT_THRESHOLD
      post_budget_alert(:alert, daily_cost)
    elsif daily_cost >= BUDGET_WARNING_THRESHOLD
      post_budget_alert(:warning, daily_cost)
    end
  end

  def post_budget_alert(level, cost)
    emoji = case level
    when :warning then ':warning:'
    when :alert then ':rotating_light:'
    when :critical then ':fire:'
    end

    message = case level
    when :warning
      "#{emoji} Budget Warning: Daily LLM cost ($#{cost.round(2)}) exceeded warning threshold ($#{BUDGET_WARNING_THRESHOLD})"
    when :alert
      "#{emoji} Budget Alert: Daily LLM cost ($#{cost.round(2)}) exceeded alert threshold ($#{BUDGET_ALERT_THRESHOLD})"
    when :critical
      "#{emoji} Budget Critical: Daily LLM cost ($#{cost.round(2)}) exceeded critical threshold ($#{BUDGET_CRITICAL_THRESHOLD}). Non-essential agents have been paused."
    end

    channel = level == :warning ? '#ops-log' : '#escalations'

    SlackService.post_message(
      channel: channel,
      text: message,
      username: 'SOP Engine',
      icon_emoji: emoji
    )
  end

  def pause_non_essential_agents
    # Pause agents that aren't critical
    # Keep lead response active, but pause marketing, etc.
    non_essential_slugs = %w[marketing ar]

    Agent.where(slug: non_essential_slugs).active.find_each do |agent|
      agent.update!(status: :paused)

      SlackService.post_message(
        channel: '#escalations',
        text: ":pause_button: Agent #{agent.name} has been paused due to budget constraints"
      )
    end
  end
end
