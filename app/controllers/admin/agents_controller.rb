# frozen_string_literal: true

module Admin
  class AgentsController < BaseController
    before_action :set_agent, only: [ :show, :edit, :update, :pause, :resume ]

    def index
      @agents = policy_scope(Agent).order(:name)
    end

    def show
      authorize @agent
      @recent_tasks = @agent.tasks.recent.limit(10)
      @memories_count = @agent.agent_memories.active.count
      @watchers_count = @agent.watchers.active.count
    end

    def edit
      authorize @agent
    end

    def update
      authorize @agent

      if @agent.update(agent_params)
        redirect_to admin_agent_path(@agent), notice: 'Agent was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def pause
      authorize @agent
      @agent.update!(status: :paused)
      redirect_to admin_agent_path(@agent), notice: 'Agent has been paused.'
    end

    def resume
      authorize @agent
      @agent.update!(status: :active)
      redirect_to admin_agent_path(@agent), notice: 'Agent has been resumed.'
    end

    private

    def set_agent
      @agent = Agent.find_by!(slug: params[:id])
    end

    def agent_params
      permitted = params.require(:agent).permit(
        :name, :description, :status, :slack_channel,
        :loop_interval_minutes, capabilities: {}
      )

      # Convert checkbox "true" strings to boolean true, and ensure
      # unchecked capabilities are set to false
      all_capability_keys = %w[email_send slack_post crm_query crm_update llm_tier1 llm_tier2 llm_tier3]
      submitted = permitted[:capabilities] || {}
      permitted[:capabilities] = all_capability_keys.each_with_object({}) do |key, hash|
        hash[key] = submitted[key] == 'true'
      end

      permitted
    end
  end
end
