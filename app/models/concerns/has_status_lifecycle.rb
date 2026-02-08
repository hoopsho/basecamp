# frozen_string_literal: true

# Shared concern for models that have a status enum with active/paused/disabled states
module HasStatusLifecycle
  extend ActiveSupport::Concern

  included do
    scope :enabled, -> { where.not(status: :disabled) }
    scope :disabled, -> { where(status: :disabled) }
  end

  def enabled?
    !disabled?
  end

  def disabled?
    status == 'disabled'
  end

  def can_activate?
    !disabled?
  end

  def pause!
    update!(status: :paused) if respond_to?(:paused?) && active?
  end

  def activate!
    update!(status: :active) if respond_to?(:active?) && can_activate?
  end

  def disable!
    update!(status: :disabled)
  end
end
