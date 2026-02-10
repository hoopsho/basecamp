# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class SopBuilderService
  MODEL = LlmService::TIER_MODELS[2] # Sonnet for good reasoning at reasonable cost

  class BuilderError < StandardError; end

  # Chat with the AI to build an SOP spec
  # messages: Array of { role: 'user'|'assistant', content: String }
  # Returns { success: Boolean, message: String, sop_spec: Hash|nil }
  def chat(messages)
    cred = Credential.find_usable('anthropic', :api_key)
    unless cred
      return { success: false, message: 'No Anthropic API credentials configured. Please add credentials first.', sop_spec: nil }
    end

    if Rails.env.test? || (Rails.env.development? && cred.value.start_with?('sk-ant-dev-placeholder'))
      return mock_chat_response(messages)
    end

    response = make_api_call(messages, cred)

    if response[:success]
      text = response[:body].dig('content', 0, 'text') || ''
      spec = extract_sop_spec(text)
      { success: true, message: text, sop_spec: spec }
    else
      { success: false, message: "AI service error: #{response[:error]}", sop_spec: nil }
    end
  rescue StandardError => e
    { success: false, message: "Unexpected error: #{e.message}", sop_spec: nil }
  end

  private

  def make_api_call(messages, credential)
    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 90

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = credential.value
    request['anthropic-version'] = '2023-06-01'

    request.body = {
      model: MODEL,
      max_tokens: 4096,
      system: system_prompt,
      messages: messages.map { |m| { role: m['role'] || m[:role], content: m['content'] || m[:content] } }
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

  def system_prompt
    agents = Agent.all.map { |a| "- #{a.name} (slug: #{a.slug}, channel: #{a.slack_channel})" }.join("\n")

    <<~PROMPT
      You are an SOP (Standard Operating Procedure) builder for Eighty Eight Services LLC (dba Snowmass), a lawn care and snow removal company in the Twin Cities, MN. You help the admin create automated business workflows through conversation.

      ## Available Agents
      #{agents.presence || '- No agents configured yet'}

      You may use an existing agent or suggest a new one. For new agents, use a snake_case slug (e.g., "operations_manager"). The agent will be created automatically when the SOP is built.

      ## Step Types and Their Config Keys
      1. **query** - Fetches data from CRM. Config: { query_type: "customer_details|service_history|account_status" }
      2. **api_call** - Calls an external API. Config: { api: "crm|ses|slack", action: "description of what to do" }
      3. **llm_classify** - AI classifies/categorizes data. Config: { prompt_template: "...", categories: ["cat1", "cat2"], output_format: "category" }
      4. **llm_draft** - AI drafts content (emails, messages). Config: { prompt_template: "...", output_format: "text|html" }
      5. **llm_decide** - AI makes a yes/no or routing decision. Config: { prompt_template: "...", options: ["option1", "option2"] }
      6. **llm_analyze** - AI analyzes data for insights. Config: { prompt_template: "...", output_format: "json|text" }
      7. **slack_notify** - Posts a notification to Slack. Config: { channel: "#channel-name", message_template: "..." }
      8. **slack_ask_human** - Pauses for human approval via Slack. Config: { channel: "#channel-name", message_template: "...", options: ["approve", "reject"] }
      9. **enqueue_next** - Schedules a follow-up SOP. Config: { sop_slug: "sop-to-run" }
      10. **wait** - Pauses execution. Config: { duration_minutes: 60, follow_up_action: "continue|check_again" }

      ## Trigger Types
      - **manual** - Triggered by a human clicking "Run" in the admin UI
      - **watcher** - Triggered by a recurring background job that monitors a condition
      - **event** - Triggered by an external event (webhook, email, etc.)
      - **agent_loop** - Triggered periodically by an agent's loop cycle

      ## Required Services Options
      Available services: slack, anthropic, ses, crm

      ## Conversation Rules
      1. Ask clarifying questions to understand the business process. Don't generate a spec on the first message.
      2. Suggest the best agent for the job based on available agents.
      3. For any step that sends communications to customers, ALWAYS include a `slack_ask_human` step before it so a human can approve the message.
      4. Use `{{variable}}` syntax in prompt_template and message_template fields to reference context data (e.g., `{{customer_name}}`, `{{service_type}}`).
      5. When you have enough information, generate the complete SOP spec.

      ## Output Format
      When you're ready to produce the SOP spec, include it as a fenced JSON block like this:

      ```json
      {
        "sop_spec": {
          "name": "Human-readable SOP name",
          "slug": "snake_case_slug",
          "description": "What this SOP does",
          "agent_slug": "slug-of-agent",
          "trigger_type": "manual|watcher|event|agent_loop",
          "max_tier": 2,
          "required_services": ["slack", "anthropic"],
          "steps": [
            {
              "position": 1,
              "name": "Step name",
              "step_type": "query|api_call|llm_classify|llm_draft|llm_decide|llm_analyze|slack_notify|slack_ask_human|enqueue_next|wait",
              "llm_tier": 0,
              "max_llm_tier": 0,
              "config": { },
              "on_success": "next",
              "on_failure": "fail",
              "on_uncertain": "escalate_tier",
              "max_retries": 1,
              "timeout_seconds": 300
            }
          ]
        }
      }
      ```

      For `on_success`, use "next" to advance to the next step by position, "complete" to end the task, or a step position number to jump to a specific step.
      For `on_failure`, use "retry", "fail", "escalate", or a step position number.
      For `on_uncertain`, use "escalate_tier" or a step position number.
      For LLM step types, set llm_tier to the minimum tier (1=Haiku, 2=Sonnet) and max_llm_tier to the maximum allowed.
      For non-LLM step types, set both llm_tier and max_llm_tier to 0.

      Keep your responses concise and focused. Ask one or two questions at a time, not a long list.
    PROMPT
  end

  def extract_sop_spec(text)
    # Match fenced code blocks with or without language tag
    match = text.match(/```(?:json)?\s*\n(.*?)\n\s*```/mi)
    return nil unless match

    parsed = JSON.parse(match[1])
    parsed['sop_spec']
  rescue JSON::ParserError
    nil
  end

  def mock_chat_response(messages)
    turn = messages.count { |m| (m['role'] || m[:role]) == 'user' }

    case turn
    when 1
      {
        success: true,
        message: "That sounds like a great process to automate! Let me ask a few questions:\n\n1. Which agent should handle this SOP? (e.g., operations, customer service)\n2. Should this be triggered manually, or automatically by a watcher/event?",
        sop_spec: nil
      }
    when 2
      {
        success: true,
        message: "Got it! A couple more questions:\n\n1. Does this process involve contacting customers? If so, we'll add a human approval step.\n2. What data do you need to pull from the CRM at the start?",
        sop_spec: nil
      }
    else
      agent = Agent.first
      agent_slug = agent&.slug || 'operations_agent'
      {
        success: true,
        message: "Here's the SOP spec based on our conversation:\n\n```json\n#{mock_sop_spec_json(agent_slug)}\n```\n\nReview the spec above and click **Create SOP** if it looks good, or tell me what you'd like to change.",
        sop_spec: mock_sop_spec(agent_slug)
      }
    end
  end

  def mock_sop_spec(agent_slug)
    {
      'name' => 'New Customer Welcome',
      'slug' => 'new_customer_welcome',
      'description' => 'Welcomes new customers with a personalized message and service overview.',
      'agent_slug' => agent_slug,
      'trigger_type' => 'manual',
      'max_tier' => 2,
      'required_services' => %w[slack anthropic crm],
      'steps' => [
        {
          'position' => 1,
          'name' => 'Fetch customer details',
          'step_type' => 'query',
          'llm_tier' => 0,
          'max_llm_tier' => 0,
          'config' => { 'query_type' => 'customer_details' },
          'on_success' => 'next',
          'on_failure' => 'fail',
          'on_uncertain' => 'escalate_tier',
          'max_retries' => 2,
          'timeout_seconds' => 30
        },
        {
          'position' => 2,
          'name' => 'Draft welcome message',
          'step_type' => 'llm_draft',
          'llm_tier' => 1,
          'max_llm_tier' => 2,
          'config' => {
            'prompt_template' => 'Draft a friendly welcome email for {{customer_name}} who signed up for {{service_type}} service.',
            'output_format' => 'html'
          },
          'on_success' => 'next',
          'on_failure' => 'retry',
          'on_uncertain' => 'escalate_tier',
          'max_retries' => 2,
          'timeout_seconds' => 60
        },
        {
          'position' => 3,
          'name' => 'Approve welcome message',
          'step_type' => 'slack_ask_human',
          'llm_tier' => 0,
          'max_llm_tier' => 0,
          'config' => {
            'channel' => '#operations',
            'message_template' => 'Please review the welcome email for {{customer_name}}',
            'options' => %w[approve reject]
          },
          'on_success' => 'next',
          'on_failure' => 'fail',
          'on_uncertain' => 'escalate_tier',
          'max_retries' => 0,
          'timeout_seconds' => 3600
        },
        {
          'position' => 4,
          'name' => 'Notify team',
          'step_type' => 'slack_notify',
          'llm_tier' => 0,
          'max_llm_tier' => 0,
          'config' => {
            'channel' => '#operations',
            'message_template' => 'Welcome email sent to {{customer_name}}.'
          },
          'on_success' => 'complete',
          'on_failure' => 'fail',
          'on_uncertain' => 'escalate_tier',
          'max_retries' => 1,
          'timeout_seconds' => 30
        }
      ]
    }
  end

  def mock_sop_spec_json(agent_slug)
    JSON.pretty_generate({ 'sop_spec' => mock_sop_spec(agent_slug) })
  end
end
