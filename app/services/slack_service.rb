# frozen_string_literal: true

class SlackService
  class SlackError < StandardError; end
  class ApiError < SlackError; end
  class ChannelNotFoundError < SlackError; end

  def self.post_message(channel:, text:, thread_ts: nil, blocks: nil, username: nil, icon_emoji: nil)
    new.post_message(channel, text, thread_ts, blocks, username, icon_emoji)
  end

  def self.post_interactive_message(channel:, text:, actions:, thread_ts: nil, callback_id: nil)
    new.post_interactive_message(channel, text, actions, thread_ts, callback_id)
  end

  def self.reply_in_thread(channel:, thread_ts:, text:, blocks: nil)
    new.post_message(channel, text, thread_ts, blocks)
  end

  def self.update_message(channel:, ts:, text:, blocks: nil)
    new.update_message(channel, ts, text, blocks)
  end

  def post_message(channel, text, thread_ts = nil, blocks = nil, username = nil, icon_emoji = nil)
    payload = {
      channel: channel,
      text: text,
      thread_ts: thread_ts
    }.compact

    payload[:blocks] = blocks if blocks
    payload[:username] = username if username
    payload[:icon_emoji] = icon_emoji if icon_emoji

    make_api_call('chat.postMessage', payload)
  end

  def post_interactive_message(channel, text, actions, thread_ts = nil, callback_id = nil)
    blocks = [
      {
        type: 'section',
        text: {
          type: 'mrkdwn',
          text: text
        }
      },
      {
        type: 'actions',
        elements: actions.map { |action| format_action(action, callback_id) }
      }
    ]

    post_message(channel: channel, text: text, thread_ts: thread_ts, blocks: blocks)
  end

  def update_message(channel, ts, text, blocks = nil)
    payload = {
      channel: channel,
      ts: ts,
      text: text
    }

    payload[:blocks] = blocks if blocks

    make_api_call('chat.update', payload)
  end

  def create_task_thread(task, channel:, initial_message:)
    return nil if task.slack_thread_ts.present?

    response = post_message(
      channel: channel,
      text: initial_message,
      username: task.agent&.name || 'SOP Engine',
      icon_emoji: ':robot_face:'
    )

    if response[:success]
      task.update!(slack_thread_ts: response[:ts])
      response[:ts]
    else
      nil
    end
  end

  def post_task_update(task, message)
    return false unless task.slack_thread_ts

    channel = task.agent&.slack_channel || '#ops-log'

    response = reply_in_thread(
      channel: channel,
      thread_ts: task.slack_thread_ts,
      text: message
    )

    response[:success]
  end

  def request_human_approval(task, prompt, options)
    return false unless task.agent&.slack_channel

    channel = task.agent.slack_channel

    actions = options.map do |option|
      {
        text: option[:label],
        value: option[:value],
        style: option[:style] || 'default',
        action_id: "approval_#{option[:value]}"
      }
    end

    callback_id = "task_#{task.id}_approval"

    response = post_interactive_message(
      channel: channel,
      text: prompt,
      actions: actions,
      thread_ts: task.slack_thread_ts,
      callback_id: callback_id
    )

    if response[:success]
      # Log the human request
      TaskEvent.create!(
        task: task,
        step: task.current_step,
        event_type: :human_requested,
        input_data: { prompt: prompt, options: options.map { |o| o[:value] } },
        created_at: Time.current
      )

      # Update task status
      task.update!(status: :waiting_on_human)

      true
    else
      false
    end
  end

  def post_heartbeat(agent, message)
    post_message(
      channel: '#ops-log',
      text: "[#{agent.name}] #{message}",
      username: 'SOP Engine',
      icon_emoji: ':heartbeat:'
    )
  end

  def post_escalation(task, reason)
    message = <<~MSG
      :rotating_light: *Escalation Required*

      Task: #{task.id}
      Agent: #{task.agent&.name || 'Unknown'}
      SOP: #{task.sop&.name || 'Unknown'}

      Reason: #{reason}

      Context: #{task.context.inspect}
    MSG

    post_message(
      channel: '#escalations',
      text: message,
      username: 'SOP Engine',
      icon_emoji: ':rotating_light:'
    )
  end

  def verify_webhook_signature(request_body, signature, timestamp)
    # Verify Slack webhook signature
    # See: https://api.slack.com/authentication/verifying-requests-from-slack

    cred = Credential.find_usable('slack', :webhook_secret)
    return false unless cred

    # Check if request is too old (> 5 minutes)
    request_time = Time.at(timestamp.to_i)
    return false if Time.current - request_time > 5.minutes

    # Build the signature base string
    base_string = "v0:#{timestamp}:#{request_body}"

    # Compute the signature
    computed_signature = 'v0=' + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('sha256'),
      cred.value,
      base_string
    )

    # Constant-time comparison to prevent timing attacks
    Rack::Utils.secure_compare(computed_signature, signature)
  end

  private

  def format_action(action, callback_id)
    {
      type: 'button',
      text: {
        type: 'plain_text',
        text: action[:text],
        emoji: true
      },
      value: action[:value],
      action_id: action[:action_id],
      style: action[:style] == 'primary' ? 'primary' : nil
    }.compact
  end

  def make_api_call(method, payload)
    if Rails.env.test? || Rails.env.development?
      return mock_slack_response(method, payload)
    end

    cred = Credential.find_usable('slack', :api_key)
    unless cred
      return { success: false, error: 'No Slack API credentials found' }
    end

    uri = URI("https://slack.com/api/#{method}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Authorization'] = "Bearer #{cred.value}"
    request['Content-Type'] = 'application/json; charset=utf-8'
    request.body = payload.to_json

    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      body = JSON.parse(response.body)

      if body['ok']
        { success: true, ts: body['ts'], channel: body['channel'] }
      else
        { success: false, error: body['error'] }
      end
    else
      { success: false, error: "HTTP #{response.code}" }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def mock_slack_response(method, payload)
    # Mock response for development/testing
    {
      success: true,
      ts: "#{Time.current.to_i}.#{rand(1000000)}",
      channel: payload[:channel]
    }
  end
end
