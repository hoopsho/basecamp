# frozen_string_literal: true

class TaskEvent < ApplicationRecord
  belongs_to :task
  belongs_to :step, optional: true

  validates :event_type, presence: true
  validates :llm_tier_used, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 3, only_integer: true }, allow_nil: true
  validates :llm_tokens_in, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :llm_tokens_out, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }, allow_nil: true
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :llm_model, presence: true, allow_nil: true

  enum :event_type, [
    :step_started,
    :step_completed,
    :step_failed,
    :llm_call,
    :llm_escalated,
    :human_requested,
    :human_responded,
    :api_called,
    :error,
    :note
  ], default: :note

  scope :for_task, ->(task) { where(task: task) }
  scope :for_step, ->(step) { where(step: step) }
  scope :llm_events, -> { where(event_type: [ :llm_call, :llm_escalated ]) }
  scope :errors, -> { where(event_type: :error) }
  scope :human_interactions, -> { where(event_type: [ :human_requested, :human_responded ]) }
  scope :ordered, -> { order(:created_at) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(:created_at) }

  def llm_call?
    event_type.in?(%w[llm_call llm_escalated])
  end

  def human_interaction?
    event_type.in?(%w[human_requested human_responded])
  end

  def error?
    event_type == 'error'
  end

  def step_event?
    event_type.in?(%w[step_started step_completed step_failed])
  end

  def total_llm_tokens
    return nil if llm_tokens_in.nil? && llm_tokens_out.nil?

    (llm_tokens_in || 0) + (llm_tokens_out || 0)
  end

  def duration_seconds
    return nil if duration_ms.nil?

    duration_ms / 1000.0
  end

  def input_data_key(key)
    input_data&.dig(key)
  end

  def output_data_key(key)
    output_data&.dig(key)
  end

  def has_input_data?
    input_data.present?
  end

  def has_output_data?
    output_data.present?
  end

  def self.total_tokens_for_task(task)
    for_task(task).llm_events.sum do |event|
      (event.llm_tokens_in || 0) + (event.llm_tokens_out || 0)
    end
  end

  def self.cost_estimate_for_task(task)
    events = for_task(task).llm_events

    tier_costs = {
      1 => 0.001,
      2 => 0.01,
      3 => 0.10
    }

    events.sum do |event|
      next 0 if event.llm_tier_used.nil? || event.llm_tier_used == 0

      tier_costs[event.llm_tier_used] || 0
    end
  end
end
