# frozen_string_literal: true

module Admin
  class TasksController < BaseController
    before_action :set_task, only: [ :show, :retry, :cancel ]

    def index
      @tasks = policy_scope(Task).includes(:sop, :agent).order(created_at: :desc)
      @sops = Sop.order(:name)
      @agents = Agent.order(:name)

      # Filtering
      @tasks = @tasks.where(status: params[:status]) if params[:status].present?
      @tasks = @tasks.where(sop_id: params[:sop_id]) if params[:sop_id].present?
      @tasks = @tasks.where(agent_id: params[:agent_id]) if params[:agent_id].present?

      @pagy, @tasks = pagy(@tasks)
    end

    def show
      authorize @task
      @task_events = @task.task_events.ordered
      @sop = @task.sop
    end

    def retry
      authorize @task

      if @task.failed? || @task.escalated?
        @task.update!(status: :pending, error_message: nil)
        TaskWorkerJob.perform_later(@task.id)
        redirect_to admin_task_path(@task), notice: 'Task has been queued for retry.'
      else
        redirect_to admin_task_path(@task), alert: 'Only failed or escalated tasks can be retried.'
      end
    end

    def cancel
      authorize @task

      if @task.active?
        @task.mark_failed!('Cancelled by admin')
        redirect_to admin_task_path(@task), notice: 'Task has been cancelled.'
      else
        redirect_to admin_task_path(@task), alert: 'Only active tasks can be cancelled.'
      end
    end

    private

    def set_task
      @task = Task.find(params[:id])
    end
  end
end
