# frozen_string_literal: true

class Agent < ApplicationRecord
  has_many :sops, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :watchers, dependent: :destroy
  has_many :agent_memories, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :slack_channel, presence: true
  validates :loop_interval_minutes, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  enum :status, [ :active, :paused, :disabled ], default: :active

  scope :active, -> { where(status: :active) }
  scope :enabled, -> { where.not(status: :disabled) }
  scope :with_loop, -> { where.not(loop_interval_minutes: nil) }

  def to_param
    slug
  end

  def enabled?
    !disabled?
  end

  def has_loop?
    loop_interval_minutes.present?
  end
end
