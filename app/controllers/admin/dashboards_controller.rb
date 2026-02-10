# frozen_string_literal: true

module Admin
  class DashboardsController < BaseController
    def show
      @metrics = gather_metrics
      @recent_tasks = Task.recent.includes({ sop: :steps }, :agent).limit(10)
      @active_agents = Agent.active
      @todays_cost = calculate_todays_cost
      @setup_checks = gather_setup_checks
      @setup_complete = @setup_checks.all? { |c| c[:passed] }
      @setup_progress = "#{@setup_checks.count { |c| c[:passed] }}/#{@setup_checks.size}"
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

    def gather_setup_checks
      [
        {
          label: 'Anthropic API Key',
          description: 'Required for AI-powered steps (classification, drafting, analysis)',
          passed: Credential.find_usable('anthropic', 'api_key').present?,
          path: admin_credentials_path
        },
        {
          label: 'Slack Bot Token',
          description: 'Required for sending notifications and approval requests',
          passed: Credential.find_usable('slack', 'api_key').present?,
          path: admin_credentials_path
        },
        {
          label: 'Slack Webhook Secret',
          description: 'Required for receiving Slack interactions (approvals, commands)',
          passed: Credential.find_usable('slack', 'webhook_secret').present?,
          path: admin_credentials_path
        },
        {
          label: 'Amazon SES Credentials',
          description: 'Required for sending transactional emails to customers',
          passed: Credential.find_usable('ses', 'api_key').present?,
          path: admin_credentials_path
        },
        {
          label: 'Active Agent',
          description: 'At least one agent must be active to process tasks',
          passed: Agent.active.exists?,
          path: admin_agents_path
        },
        {
          label: 'Active SOP',
          description: 'At least one SOP must be active to automate workflows',
          passed: Sop.active.exists?,
          path: admin_sops_path
        },
        {
          label: 'Active Watcher',
          description: 'Watchers monitor conditions and trigger SOPs automatically',
          passed: Watcher.active.exists?,
          path: admin_agents_path
        }
      ]
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
