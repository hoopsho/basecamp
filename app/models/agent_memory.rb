# frozen_string_literal: true

class AgentMemory < ApplicationRecord
  belongs_to :agent
  belongs_to :task, optional: true, foreign_key: 'related_task_id'

  validates :content, presence: true
  validates :importance, presence: true, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 10, only_integer: true }

  enum :memory_type, [
    :observation,
    :context,
    :working_note,
    :decision_log
  ], default: :observation

  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :for_task, ->(task) { where(task: task) }
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }
  scope :by_importance, -> { order(importance: :desc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(memory_type: type) }
  scope :important, -> { where('importance >= ?', 7) }
  scope :observations, -> { where(memory_type: :observation) }
  scope :contexts, -> { where(memory_type: :context) }
  scope :working_notes, -> { where(memory_type: :working_note) }
  scope :decision_logs, -> { where(memory_type: :decision_log) }

  def expired?
    return false if expires_at.nil?

    expires_at <= Time.current
  end

  def active?
    !expired?
  end

  def important?
    importance >= 7
  end

  def mark_expired!
    update!(expires_at: Time.current) if expires_at.nil? || expires_at > Time.current
  end

  def related_to_task?
    task_id.present?
  end

  def self.prune_expired!(batch_size: 1000)
    expired.limit(batch_size).destroy_all
  end

  def self.summarize_for_agent(agent, limit: 10)
    for_agent(agent).active.by_importance.limit(limit).pluck(:content)
  end

  def self.recent_context_for_agent(agent, hours: 24, limit: 20)
    for_agent(agent)
      .where('created_at > ?', hours.hours.ago)
      .active
      .by_importance
      .limit(limit)
  end

  def human_readable_memory_type
    case memory_type
    when 'observation'
      'Observation'
    when 'context'
      'Context'
    when 'working_note'
      'Working Note'
    when 'decision_log'
      'Decision Log'
    end
  end
end
