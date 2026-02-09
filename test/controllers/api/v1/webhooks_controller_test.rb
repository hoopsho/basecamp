# frozen_string_literal: true

require 'test_helper'

module Api
  module V1
    class WebhooksControllerTest < ActionDispatch::IntegrationTest
      include SlackSignatureHelper

      test 'slack endpoint responds to URL verification' do
        post api_v1_webhooks_slack_path,
          params: { type: 'url_verification', challenge: 'abc123' },
          as: :json

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 'abc123', json['challenge']
      end

      test 'slack endpoint returns unauthorized without signature headers' do
        post api_v1_webhooks_slack_path,
          params: { payload: '{}' }

        assert_response :unauthorized
      end

      test 'slack endpoint returns unauthorized with expired timestamp' do
        post api_v1_webhooks_slack_path,
          params: { payload: '{}' },
          headers: {
            'X-Slack-Request-Timestamp' => (Time.now.to_i - 400).to_s,
            'X-Slack-Signature' => 'v0=invalid'
          }

        assert_response :unauthorized
      end

      test 'slack endpoint processes valid interactive payload' do
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

      test 'slack endpoint returns bad_request for missing payload' do
        post api_v1_webhooks_slack_path,
          params: {},
          headers: slack_test_headers

        assert_response :bad_request
      end

      test 'email endpoint handles subscription confirmation' do
        post api_v1_webhooks_email_path,
          params: {
            'Type' => 'SubscriptionConfirmation',
            'TopicArn' => 'arn:aws:sns:us-east-1:123:ses-inbound',
            'SubscribeURL' => 'https://example.com/confirm'
          },
          as: :json

        assert_response :success
      end

      test 'email endpoint handles SNS notification and triggers watcher' do
        watcher = watchers(:email_inbox)

        notification = {
          'Type' => 'Notification',
          'TopicArn' => 'arn:aws:sns:us-east-1:123:ses',
          'Message' => {
            'mail' => {
              'source' => 'test@example.com',
              'messageId' => 'msg-test-001',
              'timestamp' => Time.current.iso8601,
              'commonHeaders' => {
                'from' => [ 'test@example.com' ],
                'subject' => 'Test inquiry'
              },
              'destination' => [ 'leads@eightyeightservices.com' ]
            },
            'receipt' => {
              'recipients' => [ 'leads@eightyeightservices.com' ]
            },
            'content' => 'Test body content'
          }.to_json
        }

        assert_difference('Task.count', 1) do
          post api_v1_webhooks_email_path,
            params: notification,
            as: :json
        end

        assert_response :success

        created_task = Task.order(created_at: :desc).first
        assert_equal 'email_webhook', created_task.context_key('trigger')
        assert_equal 'test@example.com', created_task.context_key('email_from')
        assert_equal watcher.id, created_task.context_key('watcher_id')
      end

      test 'email endpoint handles unknown message type' do
        post api_v1_webhooks_email_path,
          params: {
            'Type' => 'UnsubscribeConfirmation',
            'TopicArn' => 'arn:aws:sns:us-east-1:123:ses'
          },
          as: :json

        assert_response :success
      end

      test 'email endpoint does not create tasks when no active watchers exist' do
        # Disable all email watchers
        Watcher.where(check_type: :email_inbox).update_all(status: :disabled)

        notification = {
          'Type' => 'Notification',
          'TopicArn' => 'arn:aws:sns:us-east-1:123:ses',
          'Message' => {
            'mail' => {
              'source' => 'test@example.com',
              'commonHeaders' => {
                'from' => [ 'test@example.com' ],
                'subject' => 'Test'
              }
            },
            'content' => 'Test body'
          }.to_json
        }

        assert_no_difference('Task.count') do
          post api_v1_webhooks_email_path,
            params: notification,
            as: :json
        end

        assert_response :success
      end
    end
  end
end
