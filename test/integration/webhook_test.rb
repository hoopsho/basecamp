# frozen_string_literal: true

require 'test_helper'

class WebhookTest < ActionDispatch::IntegrationTest
  include SlackSignatureHelper

  test 'slack webhook URL verification challenge' do
    post api_v1_webhooks_slack_path,
      params: { type: 'url_verification', challenge: 'test_challenge_123' },
      as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 'test_challenge_123', json['challenge']
  end

  test 'slack webhook rejects request without signature headers' do
    post api_v1_webhooks_slack_path,
      params: { payload: '{}' },
      headers: {}

    assert_response :unauthorized
  end

  test 'slack webhook rejects request with stale timestamp' do
    post api_v1_webhooks_slack_path,
      params: { payload: '{}' },
      headers: {
        'X-Slack-Request-Timestamp' => (Time.now.to_i - 600).to_s,
        'X-Slack-Signature' => 'v0=invalid'
      }

    assert_response :unauthorized
  end

  test 'slack webhook processes interactive payload and enqueues HumanResponseJob' do
    task = tasks(:waiting_on_human_task)
    action_value = { task_id: task.id, action: 'approve' }.to_json

    payload_json = {
      type: 'interactive_message',
      callback_id: "task_#{task.id}_approval",
      actions: [ { value: action_value } ],
      user: { id: 'U12345', name: 'Chris' },
      message_ts: '1234567890.123456'
    }.to_json

    assert_enqueued_with(job: HumanResponseJob) do
      post api_v1_webhooks_slack_path,
        params: { payload: payload_json },
        headers: slack_test_headers
    end

    assert_response :success
  end

  test 'email webhook returns 200 for SNS subscription confirmation' do
    post api_v1_webhooks_email_path,
      params: {
        'Type' => 'SubscriptionConfirmation',
        'TopicArn' => 'arn:aws:sns:us-east-1:123456789:ses-inbound',
        'SubscribeURL' => 'https://sns.example.com/confirm'
      },
      as: :json

    assert_response :success
  end

  test 'email webhook returns 200 for SNS notification and creates task' do
    # Ensure we have an active email inbox watcher
    watcher = watchers(:email_inbox)
    assert watcher.active?
    assert watcher.sop.active?

    notification = {
      'Type' => 'Notification',
      'TopicArn' => 'arn:aws:sns:us-east-1:123456789:ses-inbound',
      'Message' => {
        'mail' => {
          'source' => 'prospect@example.com',
          'messageId' => 'msg-12345',
          'timestamp' => Time.current.iso8601,
          'commonHeaders' => {
            'from' => [ 'prospect@example.com' ],
            'subject' => 'Need a quote for lawn care'
          },
          'destination' => [ 'leads@eightyeightservices.com' ]
        },
        'receipt' => {
          'recipients' => [ 'leads@eightyeightservices.com' ]
        },
        'content' => 'I need a lawn care quote for my residential property.'
      }.to_json
    }

    assert_difference('Task.count', 1) do
      post api_v1_webhooks_email_path,
        params: notification,
        as: :json
    end

    assert_response :success

    # Verify the created task
    new_task = Task.order(created_at: :desc).first
    assert_equal watcher.sop_id, new_task.sop_id
    assert_equal watcher.agent_id, new_task.agent_id
    assert_equal 'email_webhook', new_task.context_key('trigger')
    assert_equal 'prospect@example.com', new_task.context_key('email_from')
    assert_includes new_task.context_key('email_subject'), 'lawn care'
  end

  test 'email webhook handles unknown SNS message type gracefully' do
    post api_v1_webhooks_email_path,
      params: {
        'Type' => 'UnsubscribeConfirmation',
        'TopicArn' => 'arn:aws:sns:us-east-1:123:ses'
      },
      as: :json

    assert_response :success
  end

  test 'email webhook handles malformed JSON gracefully' do
    post api_v1_webhooks_email_path,
      params: 'not-valid-json',
      headers: { 'Content-Type' => 'application/json' }

    # The controller parses the raw body; malformed JSON returns bad_request
    assert_includes [ 200, 400 ], response.status
  end
end
