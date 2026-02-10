# frozen_string_literal: true

module Admin
  class WatchersController < BaseController
    before_action :set_watcher, only: [ :show, :edit, :update, :destroy, :pause, :resume, :run_now ]

    def index
      @pagy, @watchers = pagy(
        policy_scope(Watcher).includes(:agent, :sop).order(:name)
      )
    end

    def show
      authorize @watcher
      @recent_tasks = Task.where(sop: @watcher.sop, agent: @watcher.agent).order(created_at: :desc).limit(10)
    end

    def new
      @watcher = Watcher.new
      authorize @watcher
    end

    def create
      @watcher = Watcher.new(watcher_params)
      authorize @watcher

      if @watcher.save
        redirect_to admin_watcher_path(@watcher), notice: 'Watcher was successfully created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @watcher
    end

    def update
      authorize @watcher

      if @watcher.update(watcher_params)
        redirect_to admin_watcher_path(@watcher), notice: 'Watcher was successfully updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @watcher
      @watcher.destroy!
      redirect_to admin_watchers_path, notice: 'Watcher was successfully deleted.'
    end

    def pause
      authorize @watcher
      @watcher.update!(status: :paused)
      redirect_to admin_watcher_path(@watcher), notice: 'Watcher has been paused.'
    end

    def resume
      authorize @watcher
      @watcher.update!(status: :active)
      redirect_to admin_watcher_path(@watcher), notice: 'Watcher has been resumed.'
    end

    def run_now
      authorize @watcher
      WatcherJob.perform_later(@watcher.id)
      redirect_to admin_watcher_path(@watcher), notice: 'Watcher check has been queued.'
    end

    private

    def set_watcher
      @watcher = Watcher.find(params[:id])
    end

    def watcher_params
      permitted = params.require(:watcher).permit(
        :name, :agent_id, :sop_id, :check_type,
        :interval_minutes, :status, :check_config_json
      )

      if permitted[:check_config_json].present?
        permitted[:check_config] = JSON.parse(permitted.delete(:check_config_json))
      else
        permitted.delete(:check_config_json)
      end

      permitted
    rescue JSON::ParserError
      permitted.delete(:check_config_json)
      @watcher&.errors&.add(:check_config, 'must be valid JSON')
      permitted
    end
  end
end
