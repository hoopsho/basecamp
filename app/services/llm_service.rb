# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class LlmService
  TIER_MODELS = {
    1 => 'claude-haiku-4-5-20251001',
    2 => 'claude-sonnet-4-5-20250929',
    3 => 'claude-opus-4-6'
  }.freeze

  CONFIDENCE_THRESHOLD = 0.7

  class LlmError < StandardError; end
  class MaxTierReachedError < LlmError; end
  class ApiError < LlmError; end

  # Main entry point - handles tier routing and escalation
  def self.call(prompt:, context: {}, min_tier: 1, max_tier: 3, step: nil, task: nil)
    new.call(prompt, context, min_tier, max_tier, step, task)
  end

  def call(prompt, context, min_tier, max_tier, step, task)
    current_tier = min_tier
    escalation_chain = []

    while current_tier <= max_tier
      result = call_tier(current_tier, prompt, context)
      escalation_chain << current_tier

      # Log the LLM call to TaskEvent
      log_llm_call(step, task, result, current_tier) if step && task

      if result[:success]
        if result[:confidence] >= CONFIDENCE_THRESHOLD || current_tier >= max_tier
          return build_response(result, current_tier, escalation_chain)
        end

        # Confidence too low, escalate to next tier
        log_escalation(step, task, current_tier, current_tier + 1) if step && task
        current_tier += 1
      else
        # API error, try next tier if available
        if current_tier < max_tier
          log_escalation(step, task, current_tier, current_tier + 1, "API error: #{result[:error]}") if step && task
          current_tier += 1
        else
          raise ApiError, "LLM API error at tier #{current_tier}: #{result[:error]}"
        end
      end
    end

    # Reached max tier but confidence still below threshold
    build_response(result, current_tier, escalation_chain, escalated: true)
  end

  private

  def call_tier(tier, prompt, context)
    model = TIER_MODELS[tier]

    unless model
      return { success: false, error: "Unknown tier: #{tier}" }
    end

    # Check if we have Anthropic API credentials
    cred = Credential.find_usable('anthropic', :api_key)
    unless cred
      return { success: false, error: 'No Anthropic API credentials found' }
    end

    # Build the full prompt with system context
    full_prompt = build_full_prompt(prompt, context)

    # Make the API call
    response = make_anthropic_call(model, full_prompt, cred)

    if response[:success]
      parse_response(response[:body])
    else
      { success: false, error: response[:error] }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def build_full_prompt(prompt, context)
    system_context = context[:system] || default_system_prompt
    task_context = context[:task] || {}

    {
      system: system_context,
      prompt: interpolate_prompt(prompt, task_context),
      context: task_context
    }
  end

  def interpolate_prompt(template, variables)
    return template unless template.is_a?(String)

    result = template.dup
    variables.each do |key, value|
      result.gsub!("{{#{key}}}", value.to_s)
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  def default_system_prompt
    'You are an AI assistant helping with business process automation. ' \
    "Respond with structured JSON including a 'response' field and a 'confidence' score between 0.0 and 1.0."
  end

  def make_anthropic_call(model, full_prompt, credential)
    # Use mock responses only in test, or in dev when credential is a placeholder
    if Rails.env.test? || (Rails.env.development? && credential.value.start_with?('sk-ant-dev-placeholder'))
      return mock_anthropic_response(model, full_prompt)
    end

    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = credential.value
    request['anthropic-version'] = '2023-06-01'

    request.body = {
      model: model,
      max_tokens: 4096,
      system: full_prompt[:system],
      messages: [
        { role: 'user', content: full_prompt[:prompt] }
      ]
    }.to_json

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      { success: true, body: JSON.parse(response.body) }
    else
      { success: false, error: "HTTP #{response.code}: #{response.body}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def mock_anthropic_response(model, full_prompt)
    # Mock response for development/testing
    {
      success: true,
      body: {
        'content' => [
          {
            'text' => {
              'response' => 'Mock LLM response for testing',
              'confidence' => 0.85,
              'reasoning' => 'This is a mock response for development'
            }.to_json
          }
        ],
        'usage' => {
          'input_tokens' => 100,
          'output_tokens' => 50
        }
      }
    }
  end

  def parse_response(body)
    content = body.dig('content', 0, 'text')
    usage = body['usage'] || {}

    # Strip markdown code fences if present
    cleaned = content&.gsub(/\A\s*```(?:json)?\s*\n?/, '')&.gsub(/\n?\s*```\s*\z/, '')&.strip || content

    begin
      parsed = JSON.parse(cleaned)
      {
        success: true,
        response: parsed['response'] || parsed,
        confidence: parsed['confidence'] || 0.5,
        reasoning: parsed['reasoning'],
        tokens_in: usage['input_tokens'] || 0,
        tokens_out: usage['output_tokens'] || 0
      }
    rescue JSON::ParserError
      {
        success: true,
        response: content,
        confidence: 0.5,
        tokens_in: usage['input_tokens'] || 0,
        tokens_out: usage['output_tokens'] || 0
      }
    end
  end

  def build_response(result, tier, escalation_chain, escalated: false)
    {
      response: result[:response],
      confidence: result[:confidence],
      tier_used: tier,
      model: TIER_MODELS[tier],
      tokens_in: result[:tokens_in],
      tokens_out: result[:tokens_out],
      escalated: escalated,
      escalation_chain: escalation_chain,
      reasoning: result[:reasoning]
    }
  end

  def log_llm_call(step, task, result, tier)
    TaskEvent.create!(
      task: task,
      step: step,
      event_type: :llm_call,
      llm_tier_used: tier,
      llm_model: TIER_MODELS[tier],
      llm_tokens_in: result[:tokens_in],
      llm_tokens_out: result[:tokens_out],
      confidence_score: result[:confidence],
      input_data: { prompt: step.prompt_template },
      output_data: { response: result[:response] },
      created_at: Time.current
    )
  end

  def log_escalation(step, task, from_tier, to_tier, reason = nil)
    TaskEvent.create!(
      task: task,
      step: step,
      event_type: :llm_escalated,
      llm_tier_used: from_tier,
      input_data: { from_tier: from_tier, to_tier: to_tier, reason: reason },
      created_at: Time.current
    )
  end
end
