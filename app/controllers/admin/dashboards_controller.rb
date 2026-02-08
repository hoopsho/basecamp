# frozen_string_literal: true

module Admin
  class DashboardsController < BaseController
    def show
      @metrics = gather_metrics
      @recent_tasks = Task.recent.limit(10)
      @active_agents = Agent.active
      @todays_cost = calculate_todays_cost
      authorize :dashboard, :show?
    end

    private

    def gather_metrics
      today = Time.current.beginning_of_day

      {
        tasks_created_today: Task.where('created_at >= ?', today).count,
        tasks_completed_today: Task.where(status: :completed).where('completed_at >= ?', today).count,
        tasks_pending: Task.pending.count,
        tasks_waiting_human: Task.where(status: :waiting_on_human).count,
        tasks_failed: Task.where(status: [ :failed, :escalated ]).where('updated_at >= ?', today).count,
        active_agents: Agent.active.count,
        total_sops: Sop.active.count,
        active_watchers: Watcher.active.count,
        llm_calls_today: TaskEvent.where(event_type: [ :llm_call, :llm_escalated ]).where('created_at >= ?', today).count
      }
    end

    def calculate_todays_cost
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
  end
end
