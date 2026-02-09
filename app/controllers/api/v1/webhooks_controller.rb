# frozen_string_literal: true

module Api
  module V1
    class WebhooksController < BaseController
      before_action :verify_slack_signature, only: :slack, unless: -> { url_verification_request? }

      # POST /api/v1/webhooks/slack
      #
      # Handles Slack interactive message callbacks and URL verification.
      # Must respond within 3 seconds — enqueue work and return 200 immediately.
      def slack
        # Handle Slack URL verification challenge (used during app setup)
        if params[:type] == 'url_verification'
          render json: { challenge: params[:challenge] }
          return
        end

        # Slack sends interactive payloads as form-encoded with a `payload` param
        payload = parse_slack_payload
        return head(:bad_request) if payload.nil?

        action_value = extract_action_value(payload)
        return head(:bad_request) if action_value.nil?

        task_id = action_value['task_id']
        action = action_value['action']

        return head(:bad_request) if task_id.blank? || action.blank?

        response_data = {
          'action' => action,
          'user_id' => payload.dig('user', 'id'),
          'user_name' => payload.dig('user', 'name'),
          'channel' => payload.dig('channel', 'id'),
          'timestamp' => Time.current.iso8601,
          'callback_id' => payload['callback_id'],
          'text' => action_value['text']
        }

        HumanResponseJob.perform_later(task_id, response_data)

        Rails.logger.info(
          "Slack webhook received: task=#{task_id} action=#{action} " \
          "user=#{response_data['user_name']}"
        )

        head :ok
      end

      # POST /api/v1/webhooks/email
      #
      # Handles AWS SNS notifications for SES inbound email.
      # Supports subscription confirmation and notification message types.
      def email
        body = parse_sns_body
        return head(:bad_request) if body.nil?

        message_type = body['Type']

        case message_type
        when 'SubscriptionConfirmation'
          handle_sns_subscription(body)
        when 'Notification'
          handle_sns_notification(body)
        else
          Rails.logger.warn("Unknown SNS message type: #{message_type}")
          head :ok
        end
      end

      private

      def url_verification_request?
        # Slack URL verification challenges bypass signature verification.
        # The challenge response is safe — it echoes back a token Slack already knows.
        params[:type] == 'url_verification' && params[:challenge].present?
      end

      # --- Slack helpers ---

      def parse_slack_payload
        raw = params[:payload]
        return nil if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse Slack payload: #{e.message}")
        nil
      end

      def extract_action_value(payload)
        raw_value = payload.dig('actions', 0, 'value')
        return nil if raw_value.blank?

        JSON.parse(raw_value)
      rescue JSON::ParserError
        # Fall back to treating the value as a simple action string
        { 'action' => raw_value, 'task_id' => payload['callback_id']&.gsub(/^task_/, '')&.split('_step_')&.first }
      end

      def verify_slack_signature
        timestamp = request.headers['X-Slack-Request-Timestamp']
        signature = request.headers['X-Slack-Signature']

        return head(:unauthorized) if timestamp.blank? || signature.blank?
        return head(:unauthorized) if (Time.now.to_i - timestamp.to_i).abs > 300

        body = request.body.read
        request.body.rewind

        signing_secret = credential_value('slack', :webhook_secret)

        # Allow missing secret in dev/test for easier local development
        return if signing_secret.nil? && (Rails.env.development? || Rails.env.test?)
        return head(:unauthorized) if signing_secret.nil?

        sig_basestring = "v0:#{timestamp}:#{body}"
        expected = "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}"

        head(:unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      rescue StandardError => e
        Rails.logger.error("Slack signature verification failed: #{e.message}")
        head(:unauthorized)
      end

      # --- SNS / SES helpers ---

      def parse_sns_body
        raw = request.body.read
        request.body.rewind

        JSON.parse(raw)
      rescue JSON::ParserError => e
        Rails.logger.error("Failed to parse SNS body: #{e.message}")
        nil
      end

      def handle_sns_subscription(body)
        topic_arn = body['TopicArn'].to_s

        unless topic_arn.include?('ses')
          Rails.logger.warn("Ignoring SNS subscription for non-SES topic: #{topic_arn}")
          head :ok
          return
        end

        subscribe_url = body['SubscribeURL']

        if subscribe_url.present?
          Rails.logger.info("Confirming SNS subscription for topic: #{topic_arn}")

          # Confirm the subscription by hitting the SubscribeURL
          require 'net/http'
          uri = URI.parse(subscribe_url)
          Net::HTTP.get(uri)

          Rails.logger.info('SNS subscription confirmed')
        end

        head :ok
      rescue StandardError => e
        Rails.logger.error("SNS subscription confirmation failed: #{e.message}")
        head :ok
      end

      def handle_sns_notification(body)
        message = parse_sns_message(body)
        return head(:ok) if message.nil?

        email_data = extract_email_data(message)

        Rails.logger.info(
          "Inbound email received: from=#{email_data[:from]} " \
          "subject=#{email_data[:subject]}"
        )

        trigger_email_watcher(email_data)

        head :ok
      end

      def parse_sns_message(body)
        raw_message = body['Message']
        return nil if raw_message.blank?

        JSON.parse(raw_message)
      rescue JSON::ParserError
        # Message may be a plain string from SES
        { 'content' => raw_message }
      end

      def extract_email_data(message)
        mail_obj = message.dig('mail') || {}
        receipt = message.dig('receipt') || {}

        {
          from: mail_obj.dig('source') || mail_obj.dig('commonHeaders', 'from', 0),
          to: mail_obj.dig('destination', 0) || mail_obj.dig('commonHeaders', 'to', 0),
          subject: mail_obj.dig('commonHeaders', 'subject'),
          message_id: mail_obj.dig('messageId'),
          timestamp: mail_obj.dig('timestamp'),
          body: message.dig('content'),
          recipients: receipt.dig('recipients') || [],
          raw: message
        }
      end

      def trigger_email_watcher(email_data)
        # Find active email inbox watchers
        watchers = Watcher.active.where(check_type: :email_inbox)

        if watchers.empty?
          Rails.logger.warn('No active email inbox watchers found for inbound email')
          return
        end

        watchers.find_each do |watcher|
          sop = watcher.sop
          next unless sop&.active?

          task = Task.create!(
            sop: sop,
            agent: watcher.agent,
            context: {
              'trigger' => 'email_webhook',
              'email_from' => email_data[:from],
              'email_to' => email_data[:to],
              'email_subject' => email_data[:subject],
              'email_body' => email_data[:body],
              'email_message_id' => email_data[:message_id],
              'email_timestamp' => email_data[:timestamp],
              'email_recipients' => email_data[:recipients],
              'watcher_id' => watcher.id
            },
            priority: 5
          )

          TaskWorkerJob.perform_later(task.id)

          Rails.logger.info(
            "Email watcher triggered: watcher=#{watcher.name} " \
            "sop=#{sop.slug} task=#{task.id}"
          )
        end
      end

      # --- Shared helpers ---

      def credential_value(service_name, credential_type)
        Credential.find_usable(service_name, credential_type)&.value ||
          Rails.application.credentials.dig(service_name.to_sym, :signing_secret)
      end
    end
  end
end
