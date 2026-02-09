# frozen_string_literal: true

class Sop < ApplicationRecord
  belongs_to :agent
  has_many :steps, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :watchers, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :version, numericality: { greater_than: 0, only_integer: true }
  validates :max_tier, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 3, only_integer: true }
  validates :required_services, presence: true, allow_blank: true

  enum :trigger_type, [ :manual, :watcher, :event, :agent_loop ], default: :manual
  enum :status, [ :active, :draft, :disabled ], default: :draft

  scope :active, -> { where(status: :active) }
  scope :ready_to_run, -> { where(status: :active) }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :with_trigger, ->(trigger_type) { where(trigger_type: trigger_type) }

  def to_param
    slug
  end

  def draft?
    status == 'draft'
  end

  def active?
    status == 'active'
  end

  def ordered_steps
    steps.order(:position)
  end

  def first_step
    ordered_steps.first
  end

  def step_at_position(position)
    steps.find_by(position: position)
  end

  def allows_tier?(tier)
    tier <= max_tier
  end
end
