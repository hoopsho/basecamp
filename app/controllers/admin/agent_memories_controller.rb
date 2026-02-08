# frozen_string_literal: true

module Admin
  class AgentMemoriesController < BaseController
    before_action :set_agent
    before_action :set_memory, only: [ :destroy ]

    def index
      @memories = policy_scope(@agent.agent_memories).by_importance
      @pagy, @memories = pagy(@memories)
    end

    def destroy
      authorize @memory
      @memory.destroy
      redirect_to admin_agent_agent_memories_path(@agent), notice: 'Memory was successfully deleted.'
    end

    private

    def set_agent
      @agent = Agent.find_by!(slug: params[:agent_id])
    end

    def set_memory
      @memory = @agent.agent_memories.find(params[:id])
    end
  end
end
