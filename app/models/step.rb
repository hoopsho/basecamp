# frozen_string_literal: true

class Step < ApplicationRecord
  belongs_to :sop
  has_many :task_events, dependent: :nullify

  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :name, presence: true
  validates :llm_tier, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 3, only_integer: true }
  validates :max_llm_tier, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 3, only_integer: true }
  validates :max_retries, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :timeout_seconds, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validate :max_llm_tier_not_less_than_llm_tier

  enum :step_type, [
    :query,
    :api_call,
    :llm_classify,
    :llm_draft,
    :llm_decide,
    :llm_analyze,
    :slack_notify,
    :slack_ask_human,
    :enqueue_next,
    :wait
  ], default: :query

  scope :ordered, -> { order(:position) }
  scope :by_sop, ->(sop) { where(sop: sop) }
  scope :llm_required, -> { where(step_type: [ :llm_classify, :llm_draft, :llm_decide, :llm_analyze ]) }
  scope :no_llm_required, -> { where.not(step_type: [ :llm_classify, :llm_draft, :llm_decide, :llm_analyze ]) }
  scope :requires_approval, -> { where(step_type: :slack_ask_human) }

  def llm_required?
    %w[llm_classify llm_draft llm_decide llm_analyze].include?(step_type)
  end

  def requires_tier_approval?
    llm_tier > 0
  end

  def tier_range
    llm_tier..max_llm_tier
  end

  def next_step_on_success
    return nil if on_success == 'complete'

    sop.step_at_position(on_success.to_i)
  end

  def next_step_on_failure
    return nil if on_failure.in?(%w[retry escalate fail])

    sop.step_at_position(on_failure.to_i)
  end

  def next_step_on_uncertain
    return nil if on_uncertain == 'escalate_tier'

    sop.step_at_position(on_uncertain.to_i)
  end

  def human_action_name(action)
    case action
    when 'complete'
      'Complete task'
    when 'retry'
      'Retry current step'
    when 'escalate'
      'Escalate to human'
    when 'fail'
      'Mark task as failed'
    when 'escalate_tier'
      'Escalate to higher tier LLM'
    else
      "Go to step #{action}"
    end
  end

  def config_hash
    config || {}
  end

  def prompt_template
    config_hash['prompt_template'] || ''
  end

  def config_prompt_template
    prompt_template
  end

  def config_output_format
    config_hash['output_format'] || ''
  end

  def config_categories
    Array(config_hash['categories']).join(', ')
  end

  def config_channel
    config_hash['channel'] || ''
  end

  def config_message_template
    config_hash['message_template'] || config_hash['message'] || ''
  end

  def config_prompt
    config_hash['prompt'] || ''
  end

  def config_options
    Array(config_hash['options']).join(', ')
  end

  def config_query_type
    config_hash['query_type'] || ''
  end

  def config_api
    config_hash['api'] || ''
  end

  def config_action
    config_hash['action'] || ''
  end

  def config_sop_slug
    config_hash['sop_slug'] || ''
  end

  def config_wait_duration
    config_hash['wait_duration'] || ''
  end

  def config_duration_minutes
    config_hash['duration_minutes'] || ''
  end

  def config_follow_up_action
    config_hash['follow_up_action'] || ''
  end

  # Keys surfaced as dedicated form fields (excluded from Advanced JSON)
  FORM_CONFIG_KEYS = %w[
    prompt_template output_format categories channel
    message_template message prompt options query_type
    api action sop_slug wait_duration duration_minutes
    follow_up_action
  ].freeze

  def advanced_config_json
    remaining = config_hash.except(*FORM_CONFIG_KEYS)
    remaining.any? ? JSON.pretty_generate(remaining) : ''
  end

  def min_tier
    llm_tier
  end

  def next_step_position
    return nil if on_success.blank? || on_success == 'complete'

    if on_success == 'next'
      position + 1
    else
      on_success.to_i
    end
  end

  private

  def max_llm_tier_not_less_than_llm_tier
    return if max_llm_tier.nil? || llm_tier.nil?
    return if max_llm_tier >= llm_tier

    errors.add(:max_llm_tier, 'cannot be less than minimum llm_tier')
  end
end
