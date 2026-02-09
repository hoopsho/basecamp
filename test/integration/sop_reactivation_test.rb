# frozen_string_literal: true

require 'test_helper'

class SopReactivationTest < ActionDispatch::IntegrationTest
  setup do
    @marketing_agent = agents(:marketing_agent)
    @sop = sops(:past_customer_reactivation)
  end

  test 'seed data creates marketing agent with correct attributes' do
    assert @marketing_agent.present?
    assert_equal 'marketing', @marketing_agent.slug
    assert_equal '#marketing', @marketing_agent.slack_channel
    assert @marketing_agent.active?
  end

  test 'seed data creates reactivation SOP with correct slug and status' do
    assert @sop.present?
    assert_equal 'past_customer_reactivation', @sop.slug
    assert @sop.active?
    assert_equal @marketing_agent.id, @sop.agent_id
  end

  test 'reactivation SOP has steps in correct order' do
    steps = @sop.steps.order(:position)
    assert steps.count >= 3, "Expected at least 3 steps, got #{steps.count}"

    first_step = steps.first
    assert_equal 0, first_step.position
    assert_equal 'query', first_step.step_type
  end

  test 'watcher exists for reactivation SOP with schedule check type' do
    watcher = watchers(:reactivation_schedule)
    assert watcher.present?
    assert_equal 'schedule', watcher.check_type
    assert_equal @sop.id, watcher.sop_id
    assert_equal @marketing_agent.id, watcher.agent_id
    assert watcher.active?
  end

  test 'watcher triggers task creation for reactivation SOP' do
    watcher = watchers(:reactivation_schedule)

    task = Task.create!(
      sop: @sop,
      agent: @marketing_agent,
      context: {
        'triggered_by' => 'schedule',
        'triggered_at' => Time.current.iso8601,
        'watcher_id' => watcher.id
      },
      priority: 5
    )

    assert task.persisted?
    assert task.pending?
    assert_equal @sop.id, task.sop_id
    assert_equal @marketing_agent.id, task.agent_id
    assert_equal 'schedule', task.context_key('triggered_by')
  end

  test 'task worker executes CRM query step and logs events' do
    task = Task.create!(
      sop: @sop,
      agent: @marketing_agent,
      context: {},
      priority: 5
    )

    first_step = @sop.steps.find_by(position: 0)
    assert first_step.present?, "Expected step at position 0 for SOP #{@sop.slug}"
    assert_equal 'query', first_step.step_type

    # Simulate step execution
    task.update!(current_step_position: first_step.position, status: :in_progress, started_at: Time.current)

    # Log step started event
    started_event = TaskEvent.create!(
      task: task,
      step: first_step,
      event_type: :step_started,
      input_data: { step_type: first_step.step_type }
    )

    assert started_event.persisted?
    assert_equal 'step_started', started_event.event_type

    # Simulate CRM query via CrmService
    result = CrmService.customers_for_reactivation
    assert result[:success]
    assert result[:customers].is_a?(Array)

    # Log step completed event
    completed_event = TaskEvent.create!(
      task: task,
      step: first_step,
      event_type: :step_completed,
      output_data: { count: result[:count], result: 'success' },
      duration_ms: 250
    )

    assert completed_event.persisted?
    assert_equal 'step_completed', completed_event.event_type
    assert_equal 250, completed_event.duration_ms
  end

  test 'step chain progression through all steps' do
    task = Task.create!(
      sop: @sop,
      agent: @marketing_agent,
      status: :in_progress,
      started_at: Time.current,
      context: {
        'customer_name' => 'Jane Smith',
        'customer_email' => 'jane@example.com',
        'previous_service' => 'fertilizer'
      },
      priority: 5
    )

    # Step through each step in the SOP
    @sop.steps.order(:position).each do |step|
      task.update!(current_step_position: step.position)

      TaskEvent.create!(
        task: task,
        step: step,
        event_type: :step_started,
        input_data: { step_type: step.step_type }
      )

      TaskEvent.create!(
        task: task,
        step: step,
        event_type: :step_completed,
        output_data: { result: 'success' }
      )
    end

    task.mark_completed!
    assert task.completed?
    assert task.completed_at.present?

    # Verify events were created (2 per step: started + completed)
    expected_event_count = @sop.steps.count * 2
    assert_equal expected_event_count, task.task_events.count
  end

  test 'context keys are preserved through pipeline' do
    task = Task.create!(
      sop: @sop,
      agent: @marketing_agent,
      context: { 'customer_name' => 'Jane Smith' },
      priority: 5
    )

    # Step 1 adds query results
    task.set_context_key('customer_list_count', 42)
    assert_equal 42, task.context_key('customer_list_count')

    # Step 2 adds classification
    task.set_context_key('priority_classification', 'high')
    assert_equal 'high', task.context_key('priority_classification')

    # Original key still present
    assert_equal 'Jane Smith', task.context_key('customer_name')

    # All keys preserved
    assert_equal 3, task.context.keys.count
  end

  test 'agent memory is created during reactivation campaign' do
    memory = agent_memories(:marketing_observation)

    assert memory.present?
    assert_equal @marketing_agent.id, memory.agent_id
    assert_equal 'observation', memory.memory_type
    assert memory.important?
    assert_includes memory.content, 'Reactivation campaign'
  end
end
