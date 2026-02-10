# frozen_string_literal: true

module Admin
  class SopsController < BaseController
    before_action :set_sop, only: [ :show, :edit, :update, :destroy, :run ]

    def index
      @sops = policy_scope(Sop).includes(:agent, :steps).order(:name)
      @pagy, @sops = pagy(@sops)
    end

    def show
      authorize @sop
      @steps = @sop.steps.ordered
    end

    def new
      @sop = Sop.new
      authorize @sop
    end

    def create
      @sop = Sop.new(sop_params)
      authorize @sop

      if @sop.save
        redirect_to admin_sop_path(@sop), notice: 'SOP was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @sop
    end

    def update
      authorize @sop

      if @sop.update(sop_params)
        redirect_to admin_sop_path(@sop), notice: 'SOP was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @sop
      @sop.destroy
      redirect_to admin_sops_path, notice: 'SOP was successfully deleted.'
    end

    def run
      authorize @sop

      task = Task.create!(
        sop: @sop,
        agent: @sop.agent,
        status: :pending,
        current_step_position: 0,
        priority: 5,
        context: {}
      )

      TaskWorkerJob.perform_later(task.id)

      redirect_to admin_task_path(task), notice: "Task created and queued for SOP: #{@sop.name}"
    end

    def ai_builder
      authorize Sop, :ai_builder?
      @messages = []
    end

    def ai_builder_chat
      authorize Sop, :ai_builder_chat?

      @messages = parse_messages_param
      user_message = params[:user_message].to_s.strip
      return head(:unprocessable_entity) if user_message.blank?

      @messages << { 'role' => 'user', 'content' => user_message }

      service = SopBuilderService.new
      result = service.chat(@messages)

      if result[:success]
        @assistant_message = result[:message]
        @messages << { 'role' => 'assistant', 'content' => @assistant_message }
        @sop_spec = result[:sop_spec]
      else
        @error = result[:message]
      end

      @user_message = user_message

      respond_to do |format|
        format.turbo_stream
      end
    end

    def ai_builder_create
      authorize Sop, :ai_builder_create?

      spec = JSON.parse(params[:sop_spec])

      ActiveRecord::Base.transaction do
        agent = Agent.find_by(slug: spec['agent_slug'])
        agent ||= Agent.create!(
          name: spec['agent_slug'].titleize,
          slug: spec['agent_slug'],
          slack_channel: "##{spec['agent_slug'].tr('_', '-')}"
        )

        @sop = Sop.create!(
          name: spec['name'],
          slug: spec['slug'],
          description: spec['description'],
          agent: agent,
          trigger_type: spec['trigger_type'],
          max_tier: spec['max_tier'] || 2,
          required_services: spec['required_services'] || [],
          status: :draft
        )

        (spec['steps'] || []).each do |step_data|
          @sop.steps.create!(
            position: step_data['position'],
            name: step_data['name'],
            step_type: step_data['step_type'],
            llm_tier: step_data['llm_tier'] || 0,
            max_llm_tier: step_data['max_llm_tier'] || 0,
            config: step_data['config'] || {},
            on_success: step_data['on_success'] || 'next',
            on_failure: step_data['on_failure'] || 'fail',
            on_uncertain: step_data['on_uncertain'] || 'escalate_tier',
            max_retries: step_data['max_retries'] || 1,
            timeout_seconds: step_data['timeout_seconds'] || 300
          )
        end
      end

      redirect_to admin_sop_path(@sop), notice: "SOP '#{@sop.name}' created with #{@sop.steps.count} steps."
    rescue JSON::ParserError
      redirect_to ai_builder_admin_sops_path, alert: 'Invalid SOP specification. Please try again.'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to ai_builder_admin_sops_path, alert: "Failed to create SOP: #{e.message}"
    end

    private

    def set_sop
      @sop = Sop.find_by!(slug: params[:id])
    end

    def sop_params
      params.require(:sop).permit(
        :name, :slug, :description, :agent_id, :trigger_type,
        :status, :max_tier, required_services: [], trigger_config: {}
      )
    end

    def parse_messages_param
      return [] if params[:messages].blank?

      JSON.parse(params[:messages]).map { |m| m.slice('role', 'content') }
    rescue JSON::ParserError
      []
    end
  end
end
