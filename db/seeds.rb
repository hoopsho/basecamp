# frozen_string_literal: true

# =============================================================================
# Production defaults (always run)
# =============================================================================

puts '--- Seeding production defaults ---'

admin = User.find_or_initialize_by(email_address: 'admin@eightyeightservices.com')
admin.update!(
  password: 'password123!',
  password_confirmation: 'password123!',
  role: :admin,
  theme_preference: :system
)
puts "  Admin user: #{admin.email_address} (role: #{admin.role})"

# =============================================================================
# Development seeds
# =============================================================================

if Rails.env.development?
  puts "\n--- Seeding development data ---"

  # ---------------------------------------------------------------------------
  # Viewer user
  # ---------------------------------------------------------------------------
  viewer = User.find_or_initialize_by(email_address: 'viewer@eightyeightservices.com')
  viewer.update!(
    password: 'password123!',
    password_confirmation: 'password123!',
    role: :viewer,
    theme_preference: :system
  )
  puts "  Viewer user: #{viewer.email_address} (role: #{viewer.role})"

  # ---------------------------------------------------------------------------
  # Agents
  # ---------------------------------------------------------------------------
  puts "\n  Creating agents..."

  marketing_agent = Agent.find_or_initialize_by(slug: 'marketing')
  marketing_agent.update!(
    name: 'Marketing Agent',
    slack_channel: '#marketing',
    loop_interval_minutes: 15,
    status: :active,
    capabilities: {
      email_send: true,
      llm_tier1: true,
      slack_post: true,
      crm_query: true
    }
  )
  puts "    Agent: #{marketing_agent.name} (#{marketing_agent.slug})"

  lead_response_agent = Agent.find_or_initialize_by(slug: 'lead_response')
  lead_response_agent.update!(
    name: 'Lead Response Agent',
    slack_channel: '#leads-incoming',
    loop_interval_minutes: 5,
    status: :active,
    capabilities: {
      email_send: true,
      llm_tier1: true,
      slack_post: true,
      crm_query: true,
      crm_update: true
    }
  )
  puts "    Agent: #{lead_response_agent.name} (#{lead_response_agent.slug})"

  ar_agent = Agent.find_or_initialize_by(slug: 'ar')
  ar_agent.update!(
    name: 'AR Agent',
    slack_channel: '#billing',
    loop_interval_minutes: 30,
    status: :active,
    capabilities: {
      email_send: true,
      llm_tier1: true,
      llm_tier2: true,
      slack_post: true
    }
  )
  puts "    Agent: #{ar_agent.name} (#{ar_agent.slug})"

  # ---------------------------------------------------------------------------
  # SOP 1: Past Customer Reactivation
  # ---------------------------------------------------------------------------
  puts "\n  Creating SOP 1: Past Customer Reactivation..."

  sop1 = Sop.find_or_initialize_by(slug: 'past_customer_reactivation')
  sop1.update!(
    name: 'Past Customer Reactivation',
    agent: marketing_agent,
    trigger_type: :watcher,
    status: :active,
    max_tier: 2,
    version: 1,
    description: 'Reactivate past customers who have not signed up for the current season.',
    required_services: [ 'email:send', 'llm:tier1', 'slack:post', 'crm:query' ]
  )
  puts "    SOP: #{sop1.name} (#{sop1.slug})"

  # Clear existing steps to avoid unique constraint violations on re-seed
  sop1.steps.destroy_all

  sop1_steps = [
    {
      position: 0,
      name: 'Query CRM for past customers',
      step_type: :query,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        query_type: 'crm_search',
        filters: {
          status: 'past_customer',
          services: [ 'fertilizer', 'weed_control' ],
          signed_up_for_season: false
        }
      }
    },
    {
      position: 1,
      name: 'Draft reactivation email',
      step_type: :llm_draft,
      llm_tier: 1,
      max_llm_tier: 2,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        prompt_template: 'You are a friendly marketing assistant for Eighty Eight Services LLC (dba Snowmass), a lawn care and snow removal company in the Twin Cities, MN. Draft a personalized reactivation email for {{customer_name}} who previously used our {{previous_service}} service. Be warm, mention the upcoming season, and include a call-to-action to sign up again. Keep it concise and professional.',
        output_format: 'email'
      }
    },
    {
      position: 2,
      name: 'Submit draft for approval',
      step_type: :slack_ask_human,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'fail',
      on_uncertain: 'fail',
      config: {
        prompt: 'Review this reactivation email draft for {{customer_name}}:',
        options: [ 'Send as-is', 'Edit first', "Don't send" ],
        channel: '#marketing'
      }
    },
    {
      position: 3,
      name: 'Send reactivation email',
      step_type: :api_call,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        api: 'email',
        action: 'send_template',
        template_name: 'customer_reactivation'
      }
    },
    {
      position: 4,
      name: 'Log outreach and schedule follow-up',
      step_type: :enqueue_next,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        record_interaction: true,
        interaction_type: 'reactivation_email',
        schedule_follow_up: true,
        follow_up_days: 5
      }
    },
    {
      position: 5,
      name: 'Post summary to marketing channel',
      step_type: :slack_notify,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'fail',
      config: {
        channel: '#marketing',
        message_template: 'Reactivation email sent to {{customer_name}} ({{customer_email}}). Previous service: {{previous_service}}.'
      }
    },
    {
      position: 6,
      name: 'Schedule response follow-up',
      step_type: :enqueue_next,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'complete',
      on_failure: 'fail',
      config: {
        wait_duration: 7200,
        follow_up_action: 'check_responses',
        description: 'Check for customer response after 5 days'
      }
    }
  ]

  sop1_steps.each do |step_attrs|
    step = sop1.steps.create!(step_attrs)
    puts "      Step #{step.position}: #{step.name} (#{step.step_type})"
  end

  # ---------------------------------------------------------------------------
  # SOP 2: New Lead Response
  # ---------------------------------------------------------------------------
  puts "\n  Creating SOP 2: New Lead Response..."

  sop2 = Sop.find_or_initialize_by(slug: 'new_lead_response')
  sop2.update!(
    name: 'New Lead Response',
    agent: lead_response_agent,
    trigger_type: :watcher,
    status: :active,
    max_tier: 2,
    version: 1,
    description: 'Automatically classify and respond to incoming lead emails.',
    required_services: [ 'email:send', 'llm:tier1', 'slack:post', 'crm:query', 'crm:update' ]
  )
  puts "    SOP: #{sop2.name} (#{sop2.slug})"

  # Clear existing steps to avoid unique constraint violations on re-seed
  sop2.steps.destroy_all

  sop2_steps = [
    {
      position: 0,
      name: 'Classify incoming email',
      step_type: :llm_classify,
      llm_tier: 1,
      max_llm_tier: 2,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        prompt_template: "Classify this incoming email into one of these categories: new_lead, existing_customer, complaint, scheduling, spam.\n\nFrom: {{email_from}}\nSubject: {{email_subject}}\nBody: {{email_body}}\n\nRespond with the category and your confidence.",
        categories: [ 'new_lead', 'existing_customer', 'complaint', 'scheduling', 'spam' ]
      }
    },
    {
      position: 1,
      name: 'Filter spam and route',
      step_type: :query,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'complete',
      config: {
        query_type: 'branch',
        branch_field: 'step_1_result',
        branches: {
          spam: 'complete',
          complaint: 'escalate',
          existing_customer: 'escalate'
        },
        default: 'next'
      }
    },
    {
      position: 2,
      name: 'Draft acknowledgment email',
      step_type: :llm_draft,
      llm_tier: 1,
      max_llm_tier: 2,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        prompt_template: 'You are a friendly customer service representative for Eighty Eight Services LLC (dba Snowmass), a lawn care and snow removal company in the Twin Cities, MN. Draft a brief acknowledgment email for a new lead named {{customer_name}} who reached out about our services. Reference their original message: {{email_body}}. Let them know we received their inquiry and will follow up with a quote within 24 hours. Be warm and professional.',
        output_format: 'email'
      }
    },
    {
      position: 3,
      name: 'Submit draft for approval',
      step_type: :slack_ask_human,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'fail',
      on_uncertain: 'fail',
      config: {
        prompt: 'Review this acknowledgment email for new lead {{customer_name}} ({{email_from}}):',
        options: [ 'Send as-is', 'Edit first', "Don't send" ],
        channel: '#leads-incoming'
      }
    },
    {
      position: 4,
      name: 'Send acknowledgment email',
      step_type: :api_call,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        api: 'email',
        action: 'send_template',
        template_name: 'lead_acknowledgment'
      }
    },
    {
      position: 5,
      name: 'Create/update CRM record',
      step_type: :api_call,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'escalate_tier',
      config: {
        api: 'crm',
        action: 'create_or_update',
        record_type: 'lead'
      }
    },
    {
      position: 6,
      name: 'Post lead details to channel',
      step_type: :slack_notify,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'fail',
      config: {
        channel: '#leads-incoming',
        message_template: 'New lead: {{customer_name}} ({{email_from}}). Subject: {{email_subject}}. Acknowledgment sent. Quote due within 24h.'
      }
    },
    {
      position: 7,
      name: 'Create follow-up task for quote',
      step_type: :enqueue_next,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'next',
      on_failure: 'fail',
      config: {
        create_sub_task: true,
        sub_task_description: 'Send quote to new lead',
        follow_up_hours: 24
      }
    },
    {
      position: 8,
      name: 'Schedule 24h escalation check',
      step_type: :enqueue_next,
      llm_tier: 0,
      max_llm_tier: 0,
      on_success: 'complete',
      on_failure: 'fail',
      config: {
        wait_duration: 1440,
        follow_up_action: 'check_quote_sent',
        escalation_channel: '#escalations',
        description: 'Escalate if quote not sent within 24h'
      }
    }
  ]

  sop2_steps.each do |step_attrs|
    step = sop2.steps.create!(step_attrs)
    puts "      Step #{step.position}: #{step.name} (#{step.step_type})"
  end

  # ---------------------------------------------------------------------------
  # Watchers
  # ---------------------------------------------------------------------------
  puts "\n  Creating watchers..."

  watcher1 = Watcher.find_or_initialize_by(name: 'Reactivation Schedule Watcher')
  watcher1.update!(
    agent: marketing_agent,
    sop: sop1,
    check_type: :schedule,
    status: :active,
    interval_minutes: 10_080,
    check_config: {
      cron: '0 9 * * 1',
      timezone: 'America/Chicago',
      description: 'Weekly Monday 9 AM CT'
    }
  )
  puts "    Watcher: #{watcher1.name} (#{watcher1.check_type}, every #{watcher1.interval_minutes} min)"

  watcher2 = Watcher.find_or_initialize_by(name: 'Email Inbox Watcher')
  watcher2.update!(
    agent: lead_response_agent,
    sop: sop2,
    check_type: :email_inbox,
    status: :active,
    interval_minutes: 5,
    check_config: {
      inbox_address: 'leads@eightyeightservices.com',
      provider: 'ses',
      description: 'Check for new lead emails every 5 minutes'
    }
  )
  puts "    Watcher: #{watcher2.name} (#{watcher2.check_type}, every #{watcher2.interval_minutes} min)"

  # ---------------------------------------------------------------------------
  # Credentials (development placeholders)
  # ---------------------------------------------------------------------------
  puts "\n  Creating development credentials..."

  cred_anthropic = Credential.find_or_initialize_by(service_name: 'anthropic', credential_type: :api_key)
  cred_anthropic.update!(value: 'sk-ant-dev-placeholder', status: :active, scopes: [ 'messages:create' ])
  puts "    Credential: #{cred_anthropic.service_name} (#{cred_anthropic.credential_type})"

  cred_slack_api = Credential.find_or_initialize_by(service_name: 'slack', credential_type: :api_key)
  cred_slack_api.update!(value: 'xoxb-dev-placeholder', status: :active, scopes: [ 'chat:write', 'reactions:read' ])
  puts "    Credential: #{cred_slack_api.service_name} (#{cred_slack_api.credential_type})"

  cred_slack_webhook = Credential.find_or_initialize_by(service_name: 'slack', credential_type: :webhook_secret)
  cred_slack_webhook.update!(value: 'dev-signing-secret-placeholder', status: :active, scopes: [])
  puts "    Credential: #{cred_slack_webhook.service_name} (#{cred_slack_webhook.credential_type})"

  cred_ses = Credential.find_or_initialize_by(service_name: 'ses', credential_type: :api_key)
  cred_ses.update!(value: 'ses-dev-placeholder', status: :active, scopes: [ 'ses:SendEmail' ])
  puts "    Credential: #{cred_ses.service_name} (#{cred_ses.credential_type})"

  puts "\n--- Development seeding complete ---"
end
