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

    CONFIG_FIELD_PARAMS = %i[
      config_prompt_template config_output_format config_categories
      config_channel config_message_template config_prompt config_options
      config_query_type config_api config_action
      config_sop_slug config_wait_duration
      config_duration_minutes config_follow_up_action
    ].freeze

    ARRAY_CONFIG_FIELDS = %w[categories options].freeze

    def step_params
      permitted = params.require(:step).permit(
        :name, :description, :position, :step_type,
        :llm_tier, :max_llm_tier, :max_retries, :timeout_seconds,
        :on_success, :on_failure, :on_uncertain,
        :config,
        *CONFIG_FIELD_PARAMS
      )

      # Start with advanced JSON textarea (if provided), or empty hash
      config = {}
      if permitted[:config].is_a?(String) && permitted[:config].present?
        config = JSON.parse(permitted[:config]) rescue {}
      end
      permitted.delete(:config)

      # Merge individual form fields into config
      CONFIG_FIELD_PARAMS.each do |param|
        value = permitted.delete(param)
        next if value.blank?

        key = param.to_s.delete_prefix('config_')

        if ARRAY_CONFIG_FIELDS.include?(key)
          config[key] = value.split(',').map(&:strip).reject(&:blank?)
        elsif value.to_s =~ /\A\d+\z/
          config[key] = value.to_i
        else
          config[key] = value
        end
      end

      permitted[:config] = config
      permitted
    end
  end
end
