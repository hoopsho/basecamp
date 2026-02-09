# frozen_string_literal: true

module Admin
  class StepsController < BaseController
    before_action :set_step, only: [ :edit, :update, :destroy ]
    before_action :set_sop

    def new
      @step = @sop.steps.build
      authorize @step
    end

    def create
      @step = @sop.steps.build(step_params)
      authorize @step

      # Set position to end if not specified
      @step.position ||= (@sop.steps.maximum(:position) || 0) + 1

      if @step.save
        redirect_to admin_sop_path(@sop), notice: 'Step was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @step
    end

    def update
      authorize @step

      if @step.update(step_params)
        redirect_to admin_sop_path(@sop), notice: 'Step was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @step
      @step.destroy
      redirect_to admin_sop_path(@sop), notice: 'Step was successfully deleted.'
    end

    private

    def set_sop
      @sop = @step&.sop || Sop.find_by!(slug: params[:sop_id])
    end

    def set_step
      @step = Step.find(params[:id])
    end

    def step_params
      permitted = params.require(:step).permit(
        :name, :description, :position, :step_type,
        :llm_tier, :max_llm_tier, :max_retries, :timeout_seconds,
        :on_success, :on_failure, :on_uncertain,
        :config
      )

      # Parse config from JSON string (textarea) into a hash
      if permitted[:config].is_a?(String) && permitted[:config].present?
        permitted[:config] = JSON.parse(permitted[:config])
      end

      permitted
    end
  end
end
