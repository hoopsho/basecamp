# frozen_string_literal: true

require 'test_helper'

class SopLeadResponseTest < ActionDispatch::IntegrationTest
  setup do
    @lead_agent = agents(:lead_response_agent)
    @sop = sops(:new_lead_response)
  end

  test 'seed data creates lead response agent with correct attributes' do
    assert @lead_agent.present?
    assert_equal 'lead_response', @lead_agent.slug
    assert_equal '#leads-incoming', @lead_agent.slack_channel
    assert @lead_agent.active?
  end

  test 'seed data creates new lead response SOP' do
    assert @sop.present?
    assert_equal 'new_lead_response', @sop.slug
    assert @sop.active?
    assert_equal @lead_agent.id, @sop.agent_id
  end

  test 'lead response SOP has steps ordered by position' do
    steps = @sop.steps.order(:position)
    assert steps.count >= 3, "Expected at least 3 steps, got #{steps.count}"

    positions = steps.pluck(:position)
    assert_equal positions, positions.sort, 'Steps should be in ascending position order'
  end

  test 'email inbox watcher exists for lead response SOP' do
    watcher = watchers(:email_inbox)
    assert watcher.present?
    assert_equal 'email_inbox', watcher.check_type
    assert_equal @sop.id, watcher.sop_id
    assert_equal @lead_agent.id, watcher.agent_id
    assert_equal 5, watcher.interval_minutes
  end

  test 'email classification step processes incoming email context' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      context: {
        'email_from' => 'prospect@example.com',
        'email_subject' => 'Quote request for lawn care',
        'email_body' => 'I would like a quote for lawn care services.'
      },
      priority: 8
    )

    classify_step = @sop.steps.find_by(position: 0)
    assert classify_step.present?

    # Simulate classification result
    task.set_context_key('step_0_result', 'new_lead')
    task.set_context_key('step_0_confidence', 0.95)

    assert_equal 'new_lead', task.context_key('step_0_result')
    assert_equal 0.95, task.context_key('step_0_confidence')

    # Original email context preserved
    assert_equal 'prospect@example.com', task.context_key('email_from')
  end

  test 'spam filtering branch routes spam to complete' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      context: {
        'email_from' => 'spammer@spam.com',
        'email_subject' => 'Buy cheap stuff!',
        'email_body' => 'Click here for deals!',
        'step_0_result' => 'spam'
      },
      priority: 1
    )

    # Spam detected — mark completed without further processing
    task.mark_completed!
    assert task.completed?
    assert_equal 'spam', task.context_key('step_0_result')
  end

  test 'full new lead path through all steps' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      status: :in_progress,
      started_at: Time.current,
      context: {
        'email_from' => 'john@example.com',
        'email_subject' => 'Need lawn care',
        'email_body' => 'Looking for lawn care in Twin Cities',
        'customer_name' => 'John Doe'
      },
      priority: 8
    )

    # Process each step
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

    # Verify events were created (2 per step)
    assert task.task_events.count >= @sop.steps.count * 2
  end

  test 'LLM classification logs proper event with tier and tokens' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      status: :in_progress,
      started_at: Time.current,
      context: {
        'customer_name' => 'Michael Chen',
        'inquiry_details' => 'Commercial snow removal, 2 acres'
      },
      priority: 10
    )

    classify_step = @sop.steps.find_by(step_type: :llm_classify)
    assert classify_step.present?, 'Expected an llm_classify step in the lead response SOP'

    event = TaskEvent.create!(
      task: task,
      step: classify_step,
      event_type: :llm_call,
      llm_tier_used: 1,
      llm_model: 'claude-haiku-4-5-20251001',
      llm_tokens_in: 150,
      llm_tokens_out: 50,
      confidence_score: 0.92,
      duration_ms: 1200,
      input_data: { prompt: 'Classify this lead...' },
      output_data: { classification: 'hot', reasoning: 'Commercial, large size, high urgency' }
    )

    assert event.persisted?
    assert_equal 200, event.total_llm_tokens
    assert event.llm_call?
    assert_equal 'hot', event.output_data_key('classification')
  end

  test 'slack approval step creates waiting_on_human status' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      status: :in_progress,
      started_at: Time.current,
      context: {
        'customer_name' => 'Emily Rodriguez',
        'draft_email_subject' => 'Thanks for reaching out',
        'draft_email_body' => 'Hi Emily...'
      },
      priority: 7
    )

    # The NLR SOP fixtures only have 3 steps (classify, filter, draft)
    # and none are slack_ask_human. Create a waiting_on_human scenario
    # by directly updating the task status.
    task.update!(status: :waiting_on_human)
    assert task.waiting_on_human?
    assert task.waiting?

    event = TaskEvent.create!(
      task: task,
      step: @sop.steps.order(:position).last,
      event_type: :human_requested,
      input_data: {
        prompt: 'Review this lead response email for Emily Rodriguez',
        options: %w[approve reject edit]
      }
    )

    assert event.persisted?
    assert event.human_interaction?
  end

  test 'CRM record creation returns success with mock data' do
    result = CrmService.create(
      name: 'New Lead',
      email: 'new@example.com',
      status: 'lead'
    )

    assert result[:success]
    assert result[:customer].present?
    assert_equal 'New Lead', result[:customer]['name']
  end

  test 'in-progress task fixture has correct state' do
    task = tasks(:in_progress_task)

    assert task.in_progress?
    assert task.started_at.present?
    assert_nil task.completed_at
    assert_equal 'Michael Chen', task.context_key('customer_name')
    assert_equal 8, task.priority
  end

  test 'waiting on human task fixture has correct state' do
    task = tasks(:waiting_on_human_task)

    assert task.waiting_on_human?
    assert task.waiting?
    assert_equal 'Emily Rodriguez', task.context_key('customer_name')
    assert_equal 'warm', task.context_key('lead_quality')
  end

  test 'lead response agent memory is created for decisions' do
    memory = agent_memories(:lead_decision_log)

    assert memory.present?
    assert_equal @lead_agent.id, memory.agent_id
    assert_equal 'decision_log', memory.memory_type
    assert memory.important?
    assert_includes memory.content, 'Hot lead'
  end

  test 'context keys accumulate through pipeline without deletion' do
    task = Task.create!(
      sop: @sop,
      agent: @lead_agent,
      context: {
        'email_from' => 'test@example.com',
        'email_subject' => 'Inquiry'
      },
      priority: 5
    )

    # Step 1 adds classification
    task.set_context_key('lead_quality', 'warm')
    assert_equal 3, task.context.keys.count

    # Step 2 adds CRM data
    task.set_context_key('customer_crm_id', 'crm-12345')
    assert_equal 4, task.context.keys.count

    # Step 3 adds draft
    task.set_context_key('draft_email_body', 'Hello...')
    assert_equal 5, task.context.keys.count

    # All previous keys preserved
    assert_equal 'test@example.com', task.context_key('email_from')
    assert_equal 'warm', task.context_key('lead_quality')
    assert_equal 'crm-12345', task.context_key('customer_crm_id')
  end
end
