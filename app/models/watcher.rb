# frozen_string_literal: true

class Watcher < ApplicationRecord
  belongs_to :agent
  belongs_to :sop

  validates :name, presence: true
  validates :interval_minutes, presence: true, numericality: { greater_than: 0, only_integer: true }
  validates :check_config, presence: true, allow_empty: true

  enum :check_type, [
    :email_inbox,
    :webhook_queue,
    :schedule,
    :database_condition,
    :api_poll
  ], default: :schedule

  enum :status, [ :active, :paused, :disabled ], default: :active

  scope :active, -> { where(status: :active) }
  scope :enabled, -> { where.not(status: :disabled) }
  scope :ready_to_check, -> { active.where('last_checked_at IS NULL OR last_checked_at < ?', Time.current - 1.minute) }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :for_sop, ->(sop) { where(sop: sop) }
  scope :overdue, -> { active.where('last_checked_at < ?', Time.current - 1.hour) }

  def active?
    status == 'active'
  end

  def enabled?
    !disabled?
  end

  def ready_to_check?
    return false unless active?
    return true if last_checked_at.nil?

    last_checked_at < (Time.current - interval_minutes.minutes)
  end

  def seconds_since_last_check
    return nil if last_checked_at.nil?

    (Time.current - last_checked_at).round
  end

  def next_check_due_at
    return Time.current if last_checked_at.nil?

    last_checked_at + interval_minutes.minutes
  end

  def check_overdue?
    return false if last_checked_at.nil?

    next_check_due_at < Time.current
  end

  def mark_checked!
    touch(:last_checked_at)
  end

  def check_config_key(key)
    check_config&.dig(key)
  end

  def set_check_config_key(key, value)
    self.check_config ||= {}
    check_config[key] = value
    save!
  end

  def human_readable_check_type
    case check_type
    when 'email_inbox'
      'Email Inbox'
    when 'webhook_queue'
      'Webhook Queue'
    when 'schedule'
      'Schedule'
    when 'database_condition'
      'Database Condition'
    when 'api_poll'
      'API Poll'
    end
  end
end
