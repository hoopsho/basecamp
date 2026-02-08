# frozen_string_literal: true

module Admin
  class SopsController < BaseController
    before_action :set_sop, only: [ :show, :edit, :update, :destroy ]

    def index
      @sops = policy_scope(Sop).includes(:agent).order(:name)
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
  end
end
