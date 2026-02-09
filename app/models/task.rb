# frozen_string_literal: true

class Task < ApplicationRecord
  belongs_to :sop
  belongs_to :agent
  belongs_to :parent_task, class_name: 'Task', optional: true, inverse_of: :sub_tasks
  has_many :sub_tasks, class_name: 'Task', foreign_key: 'parent_task_id', dependent: :nullify, inverse_of: :parent_task
  has_many :task_events, dependent: :destroy
  has_many :agent_memories, foreign_key: 'related_task_id', dependent: :nullify

  validates :current_step_position, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :priority, numericality: { only_integer: true }
  validates :slack_thread_ts, presence: true, allow_nil: true

  enum :status, [
    :pending,
    :in_progress,
    :waiting_on_human,
    :waiting_on_timer,
    :completed,
    :failed,
    :escalated
  ], default: :pending

  scope :pending, -> { where(status: :pending) }
  scope :in_progress, -> { where(status: [ :in_progress, :waiting_on_human, :waiting_on_timer ]) }
  scope :active, -> { where(status: [ :pending, :in_progress, :waiting_on_human, :waiting_on_timer ]) }
  scope :completed, -> { where(status: :completed) }
  scope :failed, -> { where(status: [ :failed, :escalated ]) }
  scope :requires_attention, -> { where(status: [ :failed, :escalated, :waiting_on_human ]) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_sop, ->(sop) { where(sop: sop) }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :with_slack_thread, -> { where.not(slack_thread_ts: nil) }

  def active?
    status.in?(%w[pending in_progress waiting_on_human waiting_on_timer])
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status.in?(%w[failed escalated])
  end

  def waiting?
    status.in?(%w[waiting_on_human waiting_on_timer])
  end

  def current_step
    return nil if current_step_position.nil?

    sop.step_at_position(current_step_position)
  end

  def mark_started!
    update!(status: :in_progress, started_at: Time.current) if pending?
  end

  def mark_completed!
    update!(status: :completed, completed_at: Time.current) unless completed?
  end

  def mark_failed!(message = nil)
    update!(status: :failed, error_message: message, completed_at: Time.current) unless failed?
  end

  def mark_escalated!
    update!(status: :escalated, completed_at: Time.current) unless escalated?
  end

  def human_readable_status
    case status
    when 'pending'
      'Pending'
    when 'in_progress'
      'In Progress'
    when 'waiting_on_human'
      'Waiting on Human'
    when 'waiting_on_timer'
      'Waiting on Timer'
    when 'completed'
      'Completed'
    when 'failed'
      'Failed'
    when 'escalated'
      'Escalated to Human'
    end
  end

  def duration
    return nil if started_at.nil?
    return nil if completed_at.nil? && !completed? && !failed?

    ((completed_at || Time.current) - started_at).round(2)
  end

  def context_key(key)
    context&.dig(key)
  end

  def set_context_key(key, value)
    self.context ||= {}
    context[key] = value
    save!
  end

  def append_to_context(key, value)
    self.context ||= {}
    context[key] ||= []
    context[key] << value
    save!
  end
end
