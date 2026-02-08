# frozen_string_literal: true

class WatcherJob < ApplicationJob
  queue_as :default

  def perform(watcher_id = nil)
    if watcher_id
      # Run specific watcher
      watcher = Watcher.find(watcher_id)
      run_watcher(watcher)
    else
      # Run all ready watchers
      Watcher.ready_to_check.find_each do |watcher|
        run_watcher(watcher)
      end
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Watcher not found: #{watcher_id}"
  end

  private

  def run_watcher(watcher)
    return unless watcher.ready_to_check?

    watcher.mark_checked!

    case watcher.check_type
    when 'email_inbox'
      check_email_inbox(watcher)
    when 'schedule'
      check_schedule(watcher)
    when 'database_condition'
      check_database_condition(watcher)
    when 'api_poll'
      check_api_poll(watcher)
    else
      Rails.logger.warn "Unknown watcher check type: #{watcher.check_type}"
    end
  rescue StandardError => e
    Rails.logger.error "WatcherJob error for watcher #{watcher.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def check_email_inbox(watcher)
    config = watcher.check_config
    inbox_address = config['inbox_address']

    # This would integrate with an email service to check for new messages
    # For now, mock implementation
    new_messages = mock_check_email_inbox(inbox_address)

    new_messages.each do |message|
      # Create a task for each new message
      task = Task.create!(
        sop: watcher.sop,
        agent: watcher.agent,
        context: {
          email_subject: message[:subject],
          email_from: message[:from],
          email_body: message[:body],
          received_at: message[:received_at]
        },
        priority: config['priority'] || 5
      )

      # Start the task
      TaskWorkerJob.perform_later(task.id)

      # Notify Slack
      SlackService.post_message(
        channel: watcher.agent.slack_channel || '#ops-log',
        text: ":email: New email triggered task for #{watcher.sop.name}: #{message[:subject]}"
      )
    end
  end

  def check_schedule(watcher)
    config = watcher.check_config
    cron_expression = config['cron']
    timezone = config['timezone'] || 'America/Chicago'

    # Check if it's time to run based on cron
    return unless cron_should_run?(cron_expression, timezone, watcher.last_checked_at)

    # Create task
    task = Task.create!(
      sop: watcher.sop,
      agent: watcher.agent,
      context: {
        triggered_by: 'schedule',
        triggered_at: Time.current.iso8601
      },
      priority: config['priority'] || 5
    )

    # Start the task
    TaskWorkerJob.perform_later(task.id)

    # Notify Slack
    SlackService.post_message(
      channel: watcher.agent.slack_channel || '#ops-log',
      text: ":clock1: Scheduled task created for #{watcher.sop.name}"
    )
  end

  def check_database_condition(watcher)
    config = watcher.check_config
    condition = config['condition']

    # Check condition (this is simplified - real implementation would be more sophisticated)
    condition_met = case condition
    when 'overdue_invoices'
      check_overdue_invoices(watcher)
    when 'unresponded_leads'
      check_unresponded_leads(watcher)
    else
      false
    end

    return unless condition_met

    # Create task
    task = Task.create!(
      sop: watcher.sop,
      agent: watcher.agent,
      context: {
        triggered_by: 'database_condition',
        condition: condition,
        triggered_at: Time.current.iso8601
      },
      priority: config['priority'] || 5
    )

    # Start the task
    TaskWorkerJob.perform_later(task.id)
  end

  def check_api_poll(watcher)
    config = watcher.check_config
    api_endpoint = config['api_endpoint']

    # This would poll an external API
    # For now, just log that we checked
    Rails.logger.info "API poll check for watcher #{watcher.id}: #{api_endpoint}"
  end

  def cron_should_run?(cron_expression, timezone, last_checked_at)
    require 'fugit' rescue return false

    cron = Fugit::Cron.parse(cron_expression)
    return false unless cron

    # Check if cron matches current time and we haven't run it yet
    now = Time.current.in_time_zone(timezone)
    last_checked = last_checked_at&.in_time_zone(timezone)

    # Get previous time this cron should have run
    previous_time = cron.previous_time(now)

    # If we haven't checked since the previous run time, we should run
    return false if last_checked && last_checked > previous_time

    # Check if we're within the grace period (1 minute) of the scheduled time
    (now - previous_time).abs < 1.minute
  rescue StandardError => e
    Rails.logger.error "Cron parsing error: #{e.message}"
    false
  end

  def check_overdue_invoices(watcher)
    config = watcher.check_config
    days_overdue = config['days_overdue'] || 7

    # Query CRM for overdue invoices
    result = CrmService.overdue_invoices(days_overdue: days_overdue)

    result.any?
  end

  def check_unresponded_leads(watcher)
    # Check for leads that haven't been responded to in X hours
    config = watcher.check_config
    hours = config['hours'] || 24

    # This would check the database for unresponded leads
    # For now, return false
    false
  end

  def mock_check_email_inbox(inbox_address)
    # Mock implementation - return empty array
    # In production, this would integrate with email service
    []
  end
end
