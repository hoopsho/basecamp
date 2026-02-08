# SOP Engine — System Specification

> **Last updated:** 2026-02-08
> **Status:** Aligned with ADRs #01-#10

## Context & Background

This document captures the complete design for a Rails 8 application that serves as an AI-powered business process engine for Eighty Eight Services LLC (dba Snowmass), a small snow removal and landscaping company operating in the Twin Cities metro area. The company is co-owned 50/50 by Chris and Steven Bishop.

The owner (Chris) currently runs all back-office operations himself with no documented processes, no dedicated software stack, and no employees handling administrative work. The business needs to grow its customer base — particularly for fertilizer and weed control services during the mid-February through end-of-May sales window.

The core problem: you can't delegate work (to humans or AI) that you haven't defined. This system solves that by providing a structured way to define Standard Operating Procedures (SOPs) and an automated runtime that executes them.

---

## Design Philosophy

### Key Principles

1. **The system serves the humans and the agents.** The admin UI handles SOP management and monitoring. Slack handles real-time operations. Neither should feel like work.
2. **Agents are not persistent processes.** They are jobs that spin up, pull their SOP, do the work, report the result, and die. No long-running agent processes.
3. **SOPs are the single source of truth.** Every automated action traces back to a defined SOP. This makes the system auditable, debuggable, and transferable.
4. **Tiered intelligence minimizes cost.** Most work requires no LLM at all. When AI is needed, use the cheapest model that can handle the task, with automatic escalation to more capable models when needed.
5. **Start with revenue-generating SOPs.** The first workflows should directly generate leads and close sales, not optimize back-office operations.
6. **The SOP Engine does not own customer data.** Customer data lives in a separate CRM, accessed via API. The engine orchestrates processes — it is not a data store.

### What This Is NOT

- This is NOT a general-purpose AI assistant
- This is NOT a chatbot or conversational agent
- This is NOT a CRM — customer data lives elsewhere
- This is a **business process engine** with AI capabilities — think workflow automation where the workers happen to be AI

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              SLACK (Operations Hub)                       │
│  #leads-incoming  #billing  #marketing  #ops-log         │
│  #scheduling  #escalations                               │
│  Approvals | Notifications | Agent Comms | Commands      │
└──────────────┬──────────────────────────┬───────────────┘
               │                          │
               ▼                          ▼
┌─────────────────────────────────────────────────────────┐
│                  RAILS 8 APPLICATION                     │
│                  (Full-Stack)                             │
│                                                          │
│  ┌────────────┐  ┌──────────┐  ┌─────────────────────┐  │
│  │  Admin UI  │  │ Services │  │    Solid Queue       │  │
│  │            │  │  Layer   │  │                      │  │
│  │ Dashboard  │  │          │  │  ┌────────────────┐  │  │
│  │ SOP Builder│  │ LlmSvc   │  │  │ Agent Loops    │  │  │
│  │ Task Mon.  │  │ SlackSvc │  │  │ (recurring)    │  │  │
│  │ Agent Mgmt │  │ EmailSvc │  │  ├────────────────┤  │  │
│  │            │  │ CrmSvc   │  │  │ Watchers       │  │  │
│  ├────────────┤  │ CredSvc  │  │  │ (recurring)    │  │  │
│  │  API Layer │  │          │  │  ├────────────────┤  │  │
│  │  REST +    │  │          │  │  │ Task Workers   │  │  │
│  │  Webhooks  │  │          │  │  │ (enqueued)     │  │  │
│  └────────────┘  └──────────┘  │  └────────────────┘  │  │
│                                 └─────────────────────┘  │
│  ┌────────────────────────────────────────────────────┐  │
│  │               PostgreSQL Database                   │  │
│  │  Agents, SOPs, Steps, Tasks, TaskEvents,            │  │
│  │  Watchers, AgentMemories, Credentials, Users        │  │
│  └────────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP/JSON
                         ▼
              ┌──────────────────────┐
              │   CRM (External)     │
              │   Customer data      │
              │   Source of truth     │
              └──────────────────────┘
```

### Two Interfaces, Two Purposes

| Interface | Purpose | Used For |
|-----------|---------|----------|
| **Slack** | Operations hub | Approvals, notifications, agent-to-human comms, agent-to-agent coordination, slash commands, daily summaries |
| **Admin UI** | Management plane | SOP building/editing, task monitoring, dashboard metrics, agent management, credential status |

These are complementary, not competing. Slack handles the live operational loop. The admin UI handles configuration and oversight.

### Tech Stack

- **Framework:** Rails 8 (full-stack with views)
- **Database:** PostgreSQL
- **Job Queue:** Solid Queue (built into Rails 8, runs in PostgreSQL)
- **Frontend:** Tailwind CSS 4, Stimulus, Turbo (Frames + Streams), Importmaps — no Node.js
- **Authentication:** Rails 8 native (`has_secure_password`, session-based)
- **Authorization:** Pundit
- **Communication:** Slack API (Bot Token + Webhooks)
- **AI:** Anthropic Claude API (tiered model usage)
- **Email:** Amazon SES (transactional)
- **Customer Data:** External CRM via CrmService API
- **Deployment:** Heroku (app dyno + worker dyno + PostgreSQL addon)

---

## Data Models

All tables use **UUID primary keys**. All foreign keys are indexed. All associations use `references` with `foreign_key: true`.

### Agent

Represents a defined AI worker role in the system. Not a running process — a role definition.

```ruby
# agents
# - id: uuid (PK)
# - name: string (e.g., "AR Agent", "Lead Response Agent", "Marketing Agent")
# - slug: string (unique, used in code references and recurring.yml)
# - description: text (what this agent is responsible for — included in LLM system prompts)
# - status: enum (active, paused, disabled)
# - slack_channel: string (primary channel this agent posts to)
# - loop_interval_minutes: integer (how often the agent loop runs, null if no loop)
# - capabilities: jsonb (what services/actions this agent can use)
# - created_at, updated_at
```

### Sop (Standard Operating Procedure)

A defined, repeatable business process.

```ruby
# sops
# - id: uuid (PK)
# - agent_id: uuid (FK -> agents)
# - name: string (e.g., "Past Customer Reactivation Outreach")
# - slug: string (unique)
# - description: text
# - trigger_type: enum (manual, watcher, event, agent_loop)
# - trigger_config: jsonb (conditions for automatic triggering)
# - required_services: string[] (e.g., ["email:send", "llm:tier1", "slack:post"])
# - status: enum (active, draft, disabled)
# - version: integer (for SOP versioning)
# - max_tier: integer (highest LLM tier this SOP is allowed to use, 0-3)
# - created_at, updated_at
```

### Step

An individual action within an SOP. Ordered sequentially with optional branching.

```ruby
# steps
# - id: uuid (PK)
# - sop_id: uuid (FK -> sops)
# - position: integer (ordering within the SOP)
# - name: string (e.g., "Classify incoming email")
# - description: text
# - step_type: enum (see Step Types below)
# - config: jsonb (type-specific configuration — prompt templates, API params, etc.)
# - llm_tier: integer (0-3, minimum tier for this step)
# - max_llm_tier: integer (0-3, maximum tier for escalation)
# - on_success: string (next step position or "complete")
# - on_failure: string (next step position, "retry", "escalate", or "fail")
# - on_uncertain: string (next step position or "escalate_tier")
# - max_retries: integer (default 3)
# - timeout_seconds: integer (how long before step is considered hung)
# - created_at, updated_at
```

**Step Types:**

| step_type | Description | LLM Required? |
|-----------|-------------|---------------|
| `query` | CRM API query / check condition | No (Tier 0) |
| `api_call` | Call external API (email, CRM, etc.) | No (Tier 0) |
| `llm_classify` | Classify input into categories | Yes (Tier 1+) |
| `llm_draft` | Draft text content (email, message) | Yes (Tier 1+) |
| `llm_decide` | Make a judgment call with reasoning | Yes (Tier 2+) |
| `llm_analyze` | Complex analysis of data/situation | Yes (Tier 2+) |
| `slack_notify` | Post update to Slack channel | No (Tier 0) |
| `slack_ask_human` | Post to Slack and wait for response | No (Tier 0) |
| `enqueue_next` | Trigger another SOP or schedule follow-up | No (Tier 0) |
| `wait` | Pause for a duration before continuing | No (Tier 0) |

### Task

A running instance of an SOP. Created when an SOP is triggered.

```ruby
# tasks
# - id: uuid (PK)
# - sop_id: uuid (FK -> sops)
# - agent_id: uuid (FK -> agents)
# - status: enum (pending, in_progress, waiting_on_human, waiting_on_timer, completed, failed, escalated)
# - current_step_position: integer
# - context: jsonb (working data passed between steps — the "payload")
# - priority: integer (for queue ordering)
# - started_at: datetime
# - completed_at: datetime
# - error_message: text
# - parent_task_id: uuid (FK -> tasks, nullable — for sub-tasks)
# - slack_thread_ts: string (Slack thread for this task's updates)
# - created_at, updated_at
```

### TaskEvent

Audit log of everything that happens during task execution. Immutable — no `updated_at`.

```ruby
# task_events
# - id: uuid (PK)
# - task_id: uuid (FK -> tasks)
# - step_id: uuid (FK -> steps, nullable)
# - event_type: enum (step_started, step_completed, step_failed, llm_call, llm_escalated,
#                      human_requested, human_responded, api_called, error, note)
# - llm_tier_used: integer (0-3, which tier was actually used)
# - llm_model: string (actual model string used)
# - llm_tokens_in: integer
# - llm_tokens_out: integer
# - input_data: jsonb (what was sent to the step)
# - output_data: jsonb (what the step produced)
# - confidence_score: float (for LLM steps, how confident the response was)
# - duration_ms: integer
# - created_at
```

### Watcher

A recurring check that looks for trigger conditions and creates Tasks.

```ruby
# watchers
# - id: uuid (PK)
# - agent_id: uuid (FK -> agents)
# - sop_id: uuid (FK -> sops — which SOP to trigger when condition is met)
# - name: string (e.g., "Check for new lead emails")
# - check_type: enum (email_inbox, webhook_queue, schedule, database_condition, api_poll)
# - check_config: jsonb (type-specific config — inbox address, query, cron expression, etc.)
# - interval_minutes: integer (how often to run this check)
# - last_checked_at: datetime
# - status: enum (active, paused, disabled)
# - created_at, updated_at
```

### AgentMemory

Persistent working memory for each agent. Gives agents continuity between loop cycles.

```ruby
# agent_memories
# - id: uuid (PK)
# - agent_id: uuid (FK -> agents)
# - memory_type: enum (observation, context, working_note, decision_log)
# - content: text
# - importance: integer (1-10, for summarization/pruning)
# - expires_at: datetime (nullable — some memories should age out)
# - related_task_id: uuid (FK -> tasks, nullable)
# - created_at, updated_at
```

### Credential

Encrypted storage for service credentials that need runtime management.

```ruby
# credentials
# - id: uuid (PK)
# - service_name: string (e.g., "slack", "anthropic", "ses", "crm")
# - credential_type: enum (api_key, oauth_token, webhook_secret)
# - encrypted_value: text (using Rails encrypted attributes)
# - scopes: string[] (what this credential allows)
# - expires_at: datetime (nullable, for OAuth tokens)
# - refresh_token: text (encrypted, for OAuth refresh)
# - status: enum (active, expired, revoked)
# - created_at, updated_at
```

### User (Admin Interface)

Authentication for the admin UI. Not a customer or agent — these are system administrators.

```ruby
# users
# - id: uuid (PK)
# - email_address: string (unique)
# - password_digest: string (bcrypt via has_secure_password)
# - role: enum (admin, viewer)
# - theme_preference: enum (dark, light, system) — default: system
# - created_at, updated_at
```

---

## LLM Service — 4-Tier Architecture

The LLM service is the core intelligence layer. It routes requests to the appropriate model based on the step's tier configuration, and handles automatic escalation. See **ADR #03** for full details.

### Tier Definitions

| Tier | Model | Model ID | Use Cases | Cost |
|------|-------|----------|-----------|------|
| **0** | None (pure Ruby) | — | CRM queries, conditionals, time checks, API calls | Free |
| **1** | Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | Classification, templated drafting, simple yes/no, data extraction | ~$0.001/call |
| **2** | Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` | Personalized content, nuanced decisions, multi-step reasoning | ~$0.01/call |
| **3** | Claude Opus 4.6 | `claude-opus-4-6` | Escalation only — unexpected situations, low-confidence handling | ~$0.10/call |
| **Human** | Slack | — | Final escalation — post to #escalations for Chris to decide | Free (but slow) |

### Escalation Logic

```
Step declares min_tier: 1, max_tier: 3

1. Try Haiku -> response includes confidence_score
2. If confidence < threshold (0.7) -> escalate to Sonnet
3. If Sonnet confidence < threshold -> escalate to Opus
4. If Opus still uncertain -> post to Slack for human decision
5. If tier already at max_tier for this step -> escalate to Human
```

### LlmService Interface

```ruby
class LlmService
  TIER_MODELS = {
    1 => 'claude-haiku-4-5-20251001',
    2 => 'claude-sonnet-4-5-20250929',
    3 => 'claude-opus-4-6'
  }.freeze

  CONFIDENCE_THRESHOLD = 0.7

  # Main entry point — handles tier routing and escalation
  def self.call(prompt:, context:, min_tier:, max_tier:, step: nil, task: nil)
    # Returns:
    # {
    #   response: String or Hash (parsed JSON),
    #   confidence: Float (0.0-1.0),
    #   tier_used: Integer (1-3),
    #   model: String (actual model ID),
    #   tokens_in: Integer,
    #   tokens_out: Integer,
    #   escalated: Boolean,
    #   escalation_chain: Array (tiers attempted)
    # }
  end
end
```

### Prompt Structure

Every LLM call includes:
1. **System prompt** with the agent's role definition and the SOP context
2. **The step's specific prompt template** (from step.config) with `{{variable}}` placeholders interpolated from task.context
3. **The task's working context** (from task.context)
4. **Agent memory** relevant to this task (from agent_memories)
5. **Instruction to return structured JSON** with a confidence score

---

## Agent Loop System

See **ADR #05** for full details.

### Overview

Each Agent with a `loop_interval_minutes` gets a recurring Solid Queue job. The agent loop transforms this from a "fancy cron system" into something that behaves like an employee.

### Agent Loop Flow

```
AgentLoopJob.perform(agent_slug)

1. SURVEY DOMAIN
   - Query for active tasks assigned to this agent
   - Check watchers for new triggers
   - Load relevant agent memories (high importance + recent + task-related)

2. ASSESS (Tier 0 or Tier 1)
   - Is there anything new requiring attention?
   - Are any active tasks stalled or overdue?
   - Are there patterns worth noting?

3. PRIORITIZE (Tier 0)
   - Rank pending work by urgency/importance
   - If nothing needs doing -> log heartbeat, exit

4. EXECUTE (one major action per loop)
   - Pick highest-priority item
   - If new trigger -> create Task from appropriate SOP
   - If existing task -> enqueue TaskWorkerJob for next step

5. REPORT
   - Post summary to agent's Slack channel
   - Post heartbeat to #ops-log
   - Update agent memory with observations
   - Log all events to TaskEvents

6. EXIT (job completes, runs again in loop_interval_minutes)
```

### Agent Memory Management

Agent memory accumulates over time. To prevent context windows from growing unbounded:

- Each memory has an `importance` score (1-10)
- Memories can have an `expires_at` for time-sensitive context
- MemoryMaintenanceJob runs daily at 2 AM: prunes expired memories, summarizes old low-importance memories, caps total memories per agent at 100
- When building prompts, include: high-importance (8+) always, recent (24h), active-task-related, summarized older context
- Maximum ~2,000 tokens of memory per prompt

---

## Slack Integration

See **ADR #06** for full details. Slack is the **operational hub** — not a secondary notification channel.

### Channel Structure

| Channel | Purpose | Who Posts |
|---------|---------|-----------|
| `#leads-incoming` | New inquiries, quote requests, lead status | Lead Response Agent |
| `#billing` | Invoices, payments, overdue accounts | AR Agent |
| `#scheduling` | Daily routes, weather changes, crew updates | Scheduling Agent (future) |
| `#marketing` | Campaign status, review requests, reactivation updates | Marketing Agent |
| `#ops-log` | Heartbeats from all agents, system events, daily summaries | All Agents |
| `#escalations` | Human decisions needed, errors, unusual situations | All Agents (urgent) |

### Interaction Patterns

**Agent -> Human (notification):**
Informational updates posted to domain channels. No response needed.

**Agent -> Human (approval request):**
Interactive buttons in Slack. Task pauses (`waiting_on_human`) until Chris taps a button. Webhook fires -> HumanResponseJob resumes the task.

**Agent -> Human (escalation):**
Urgent requests posted to #escalations when AI confidence is low or something unexpected happens.

**Human -> Agent (via buttons/slash commands):**
Chris taps a button or uses a slash command -> webhook -> Rails endpoint -> task resumes or command executes.

**Agent -> Agent (via shared channels):**
Agents post to shared channels (#ops-log) and can observe each other's activity. Cross-agent coordination happens through Slack.

### Thread Management

All updates for a single task are grouped in a Slack thread. The first message creates the thread (stored as `task.slack_thread_ts`). All subsequent updates for that task are replies.

### Slack Bot Scopes

- `chat:write` — post messages
- `chat:write.customize` — custom username/icon per agent
- `reactions:read` — detect emoji reactions (future)
- `commands` — slash commands (`/sop`, `/agent`)
- `channels:history` — read channel messages for context
- `channels:join` — join channels programmatically
- `users:read` — identify who clicked a button
- Webhook endpoint for interactive components

---

## CRM Integration

See **ADR #10** for full details. The SOP Engine does **NOT** own customer data.

### Service Boundary

```
SOP Engine (CrmService) --HTTP/JSON--> CRM (REST API) --> Customer Data
```

- **CRM is the source of truth** for all customer data
- **CrmService** wraps the CRM API behind a consistent Ruby interface
- **task.context** carries customer references temporarily (IDs, names, emails cached for the task's duration)
- All customer data keys in task.context are prefixed with `customer_`

### CrmService Interface

```ruby
class CrmService
  def self.query(filters = {})    # List/filter customers
  def self.find(customer_id)       # Get single customer
  def self.update(id, attributes)  # Update customer record
  def self.create(attributes)      # Create new customer (from lead)
  def self.search(query)           # Fuzzy search
end
```

### Development Without CRM

The CRM is still being built. Use `MockCrmData` in development/test environments:

```ruby
class MockCrmData
  CUSTOMERS = [
    { 'id' => 'mock-uuid-1', 'name' => 'Jane Smith', ... },
    # ... more mock customers
  ].freeze
end
```

Toggle between mock and real via Rails environment. Design the CrmService interface now so both projects can build in parallel.

---

## Service Layer

Thin wrappers around external services. Each service handles auth, error handling, and logging to TaskEvents.

```ruby
# app/services/
├── llm_service.rb          # Tiered Claude API calls with escalation (ADR #03)
├── slack_service.rb         # Post messages, interactive components, threads (ADR #06)
├── email_service.rb         # Send emails via Amazon SES
├── crm_service.rb           # Customer data access via CRM API (ADR #10)
├── credential_service.rb    # Manage encrypted credentials, OAuth refresh (ADR #08)
```

### Service Interface Pattern

Every service follows the same pattern:

```ruby
class EmailService
  def self.send(to:, subject:, body:, from: nil)
    # ... make the API call to Amazon SES
    # ... return { success: true/false, message_id: "...", error: nil }
  end
end
```

**All service calls MUST be logged to TaskEvents** with duration, success/failure, and relevant metadata.

---

## Job Structure (Solid Queue)

See **ADR #04** and **ADR #05** for full details.

### Recurring Jobs

```yaml
# config/recurring.yml
lead_response_agent_loop:
  class: AgentLoopJob
  args: ["lead_response"]
  schedule: "every 5 minutes"

ar_agent_loop:
  class: AgentLoopJob
  args: ["ar"]
  schedule: "every 30 minutes"

marketing_agent_loop:
  class: AgentLoopJob
  args: ["marketing"]
  schedule: "every 15 minutes"

email_inbox_watcher:
  class: WatcherJob
  args: ["check_email_inbox"]
  schedule: "every 5 minutes"

overdue_invoice_watcher:
  class: WatcherJob
  args: ["check_overdue_invoices"]
  schedule: "every day at 8am"

memory_pruning:
  class: MemoryMaintenanceJob
  schedule: "every day at 2am"

daily_summary:
  class: DailySummaryJob
  schedule: "every day at 7pm"
```

### Job Classes

```ruby
# app/jobs/
├── agent_loop_job.rb         # Agent loop: survey -> assess -> execute -> report
├── watcher_job.rb            # Check trigger condition, create tasks if met
├── task_worker_job.rb        # Execute a single step of a task
├── human_response_job.rb     # Process Slack response, resume waiting task
├── memory_maintenance_job.rb # Prune/summarize agent memories
├── daily_summary_job.rb      # Generate and post daily ops summary
```

### Task Execution Flow

```
WatcherJob detects new email
  -> Creates Task (status: pending)
  -> Enqueues TaskWorkerJob(task_id, step_position: 1)

TaskWorkerJob runs step 1 (classify email via CrmService + LlmService)
  -> Calls LlmService at Tier 1 (Haiku)
  -> Logs TaskEvent (llm_call with tokens)
  -> Updates task.context with classification
  -> Enqueues TaskWorkerJob(task_id, step_position: 2)

TaskWorkerJob runs step 2 (draft response)
  -> Calls LlmService at Tier 1
  -> Logs TaskEvent
  -> Updates task.context with draft
  -> Enqueues TaskWorkerJob(task_id, step_position: 3)

TaskWorkerJob runs step 3 (ask human to approve)
  -> Posts draft to Slack with [Send] [Edit] [Reject] buttons
  -> Task status -> waiting_on_human
  -> Job exits

Human clicks [Send] in Slack
  -> Webhook fires -> HumanResponseJob
  -> Merges response into task.context
  -> Task status -> in_progress
  -> Enqueues TaskWorkerJob(task_id, step_position: 4)

TaskWorkerJob runs step 4 (send email via SES)
  -> Calls EmailService.send(...)
  -> Logs TaskEvent (api_called)
  -> Enqueues TaskWorkerJob(task_id, step_position: 5)

TaskWorkerJob runs step 5 (notify Slack)
  -> Posts to domain channel in task thread
  -> Marks task as completed
  -> Logs TaskEvent (step_completed)
```

---

## Admin Interface

See **ADR #09** for full details. Built with Rails 8 native auth, Pundit, Tailwind 4, Turbo, Stimulus.

### Sections

| Section | Purpose |
|---------|---------|
| **Dashboard** | Operations, performance, cost, and campaign metrics. Auto-refreshes. |
| **SOP Builder** | Create, edit, reorder steps, preview prompts. Enable/disable SOPs. |
| **Task Monitor** | Filterable task list with TaskEvent timeline drill-down. Retry/cancel. |
| **Agent Management** | View status, pause/resume, adjust intervals, view/prune memories. |
| **Credential Management** | View credential status, trigger OAuth refresh. Never shows values. |

### Routes

```ruby
# Admin namespace
namespace :admin do
  root to: 'dashboards#show'
  resources :sops do
    resources :steps, shallow: true
  end
  resources :tasks, only: [:index, :show] do
    member { post :retry; post :cancel }
  end
  resources :agents, only: [:index, :show, :edit, :update] do
    member { post :pause; post :resume }
    resources :agent_memories, only: [:index, :destroy], shallow: true
  end
  resources :credentials, only: [:index, :show] do
    member { post :refresh }
  end
  resource :dashboard, only: [:show]
end

# Webhooks (no auth — verified via signatures)
namespace :api do
  namespace :v1 do
    post 'webhooks/slack', to: 'webhooks#slack'
    post 'webhooks/email', to: 'webhooks#email'
  end
end
```

### Authentication & Authorization

- **Rails 8 native auth** — `has_secure_password`, session-based, password reset via SES
- **Pundit** — `admin` (full access) and `viewer` (read-only) roles
- **No self-registration** — Users created via seeds or Rails console
- **Dark mode** — Three-way toggle (dark / light / system), persisted per user

---

## Observability & Cost Tracking

See **ADR #07** for full details.

### TaskEvent as Unified Audit Log

Every significant action creates a TaskEvent. Every LLM call logs tokens. Every external API call logs success/failure and duration. This is the primary mechanism for:

- **Cost tracking** — Calculate LLM costs from token counts per model
- **Debugging** — Trace any task failure to a specific step, LLM call, or API error
- **Performance** — Response times, SOP success rates, human response latency
- **ROI** — Emails sent vs responses received vs customers signed

### Budget Alerting

DailySummaryJob checks daily LLM costs:
- Warning ($10/day): Post to #ops-log
- Alert ($25/day): Post to #escalations
- Critical ($50/day): Post to #escalations + pause non-essential agents

### Dashboard Metrics

- Active tasks by agent and status
- LLM cost today / month-to-date / 30-day trend (by tier)
- Lead response time, SOP success rate, escalation rate
- Campaign stats (reactivation, lead pipeline, collections)

---

## First SOPs to Implement (Priority Order)

These are ordered by immediate business impact. The fertilizer/weed control sales window opens mid-February 2026 and closes end of May 2026.

### SOP 1: Past Customer Reactivation

**Agent:** Marketing Agent
**Trigger:** Watcher on schedule (run once in mid-February, then weekly through March)
**Purpose:** Contact past fertilizer/weed control customers to re-sign for the new season

**Steps:**
1. (Tier 0) Query CRM for past fert/weed control customers not yet signed for current season
2. (Tier 1) For each customer, draft personalized reactivation email using template + customer history
3. (Tier 0) Post draft to Slack for approval (slack_ask_human)
4. (Tier 0) Send email via Amazon SES
5. (Tier 0) Log outreach in task context, schedule follow-up
6. (Tier 0) Post summary to #marketing
7. (Tier 0) After 5 days, check for responses — enqueue follow-up SOP for non-responders

### SOP 2: New Lead Response

**Agent:** Lead Response Agent
**Trigger:** Watcher on email inbox (every 5 minutes)
**Purpose:** Respond to new inquiries immediately

**Steps:**
1. (Tier 1) Classify incoming email: new_lead, existing_customer, complaint, scheduling, spam
2. (Tier 0) If spam -> archive, done
3. (Tier 1) If new_lead -> draft acknowledgment email
4. (Tier 0) Post draft to Slack for approval (slack_ask_human)
5. (Tier 0) Send acknowledgment via SES
6. (Tier 0) Create/update lead in CRM via CrmService
7. (Tier 0) Post to #leads-incoming with customer details
8. (Tier 0) Create follow-up task: generate quote within 24 hours
9. (Tier 0) If no quote sent in 24h -> post reminder to #escalations

### SOP 3: Quote Follow-Up

**Agent:** Lead Response Agent
**Trigger:** Event (quote sent but no response after 3 days)
**Purpose:** Follow up on outstanding quotes

**Steps:**
1. (Tier 0) Check CRM if customer has responded or signed up since quote was sent
2. (Tier 1) If no response -> draft follow-up email
3. (Tier 0) Post draft to Slack for approval
4. (Tier 0) Send follow-up
5. (Tier 0) Schedule second follow-up in 5 more days
6. (Tier 1) Second follow-up with slightly different angle
7. (Tier 0) If still no response after second follow-up -> update lead status to cold in CRM, post to #leads-incoming

### SOP 4: Review Request

**Agent:** Marketing Agent
**Trigger:** Event (service completed for customer)
**Purpose:** Ask satisfied customers for Google reviews

**Steps:**
1. (Tier 0) Wait 2 days after service completion
2. (Tier 1) Draft review request email
3. (Tier 0) Send via email (SES)
4. (Tier 0) Log request sent
5. (Tier 0) Post to #marketing

### SOP 5: Invoice Follow-Up / Collections

**Agent:** AR Agent
**Trigger:** Watcher (daily check for overdue invoices via CRM)
**Purpose:** Automated dunning sequence

**Steps:**
1. (Tier 0) Query CRM for invoices where due_date < today and status != paid
2. (Tier 0) Group by days overdue: 7-day, 14-day, 21-day, 30-day+
3. (Tier 1) 7-day: draft friendly reminder
4. (Tier 1) 14-day: draft firmer reminder
5. (Tier 2) 21-day: draft firm final notice
6. (Tier 0) 30-day+: post to #escalations for Chris to decide next steps
7. (Tier 0) Post draft to Slack for approval
8. (Tier 0) Send appropriate message via SES, log event
9. (Tier 0) Post summary to #billing

---

## Credential Management & Security

See **ADR #08** for full details.

### Two-Layer Strategy

1. **Rails encrypted credentials** (`config/credentials.yml.enc`) — Infrastructure secrets that rarely change (Anthropic API key, Slack bot token, SES keys, signing secrets)
2. **Credential model** (database) — Tokens that expire, need refresh, or are managed at runtime (OAuth tokens, rotatable keys)

### Webhook Verification

All incoming webhooks MUST be verified:
- **Slack:** HMAC-SHA256 signature verification using signing secret. Reject requests older than 5 minutes.
- **Email (SES/SNS):** Verify SNS message signature. Validate TopicArn.
- **All webhooks:** Constant-time comparison, stale request rejection, rejected attempt logging.

### Security Rules

- Never log credentials in TaskEvents, Rails logs, or error messages
- Never store credentials in task.context
- Credential values encrypted at rest (Rails encrypted attributes)
- Revoke, don't delete (audit trail)

---

## Future Integrations (Not v0.1)

- Stripe/payment processor for invoice tracking
- Google Business Profile API for review monitoring
- Weather API for scheduling
- Google Maps/GIS for property data and route optimization
- Website contact form webhook
- Twilio for SMS

---

## Deployment Considerations

- **Heroku** — App dyno (web) + Worker dyno (Solid Queue) + PostgreSQL addon
- **Solid Queue** requires a persistent worker process (worker dyno)
- **PostgreSQL** handles concurrent job execution via advisory locks (Solid Queue built-in)
- **Credentials** stored via Rails encrypted credentials. `RAILS_MASTER_KEY` set as Heroku config var.
- **Slack Bot** needs a publicly accessible webhook URL for interactive components
- **Monitoring:** #ops-log channel for heartbeats, #escalations for errors, admin dashboard for metrics

---

## v0.1 Scope

### In Scope

- 8 core models (Agent, Sop, Step, Task, TaskEvent, Watcher, AgentMemory, Credential) + User
- UUID primary keys on all tables
- Full-stack Rails 8 with Tailwind 4, Stimulus, Turbo, Importmaps, dark mode
- Rails 8 native authentication + Pundit authorization
- Admin UI: Dashboard, SOP Builder, Task Monitor, Agent Management, Credential Status
- Solid Queue setup with recurring jobs
- 4-tier LLM service with confidence-based escalation
- Slack integration (post messages, interactive buttons, threads, slash commands, webhooks)
- Amazon SES email service
- CrmService with MockCrmData for development/testing
- Agent loop job framework (survey -> assess -> execute -> report)
- Watcher job framework
- Task worker job with step execution engine
- Full TaskEvent audit trail with cost tracking
- SOP 1 (Past Customer Reactivation) fully working
- SOP 2 (New Lead Response) fully working
- Seed data for agents and SOPs
- Human-in-the-loop approval for all customer-facing actions

### Out of Scope for v0.1

- Complex branching logic in SOPs (keep it sequential with simple on_success/on_failure)
- SMS integration (email first)
- Payment/invoice integration (manual tracking first)
- Multi-tenant support
- Automated testing of SOPs (beyond Minitest)
- SOP versioning/rollback UI
- Real CRM integration (mock data until CRM is ready)

---

## Getting Started (Implementation Order)

### Wave A: Scaffold & Database
1. Scaffold Rails 8 app with PostgreSQL, Solid Queue, Tailwind 4, Importmaps
2. Create all migrations (8 tables + users)
3. Build model layer (associations, validations, enums, scopes, encrypted attrs)

### Wave B: Service Layer
4. Build LlmService with 4-tier routing and escalation
5. Build SlackService with posting, interactive components, thread management
6. Build EmailService with Amazon SES
7. Build CrmService with MockCrmData
8. Build CredentialService

### Wave C: Execution Engine
9. Build TaskWorkerJob — core step execution engine (all 10 step type handlers)
10. Build WatcherJob — trigger detection engine
11. Build AgentLoopJob — agent awareness loop (survey -> assess -> execute -> report)
12. Build HumanResponseJob, MemoryMaintenanceJob, DailySummaryJob
13. Configure recurring.yml

### Wave D: Admin Interface
14. Rails 8 authentication + Pundit setup
15. Admin layout (sidebar, dark mode, responsive)
16. Dashboard with 4 metric panels
17. SOP Builder/Editor with step management
18. Task Monitor with event timeline
19. Agent Management with pause/resume
20. Credential status display

### Wave E: SOPs & Integration
21. Create seed data (agents, SOPs with steps, mock customers)
22. Wire Slack bot (channels, webhook endpoint, interactive components)
23. Implement SOP 1 (Past Customer Reactivation) end-to-end
24. Implement SOP 2 (New Lead Response) end-to-end

### Wave F: Deploy & Validate
25. Heroku setup (app + worker + PostgreSQL)
26. End-to-end test SOP 1 against mock data
27. End-to-end test SOP 2 against mock data
28. Deploy to production

---

## Important Notes for Implementation

- **All tables use UUID primary keys** — enable `pgcrypto` extension
- **All foreign keys must be indexed** — use `references` with `foreign_key: true`
- Use `config/recurring.yml` for Solid Queue recurring job definitions
- Every LLM call must be logged to TaskEvents with token counts for cost tracking
- Every external action (email sent, Slack posted, CRM queried) must be logged to TaskEvents
- Task.context is the primary way data flows between steps — treat it like a pipeline payload
- Customer data keys in task.context use `customer_` prefix
- Steps MUST NOT delete keys from context — append or overwrite only
- Agent memories should be pruned aggressively — the system generates many observations
- Start with all customer-facing actions requiring Slack approval (slack_ask_human step before send), loosen as trust builds
- The escalation chain (Haiku -> Sonnet -> Opus -> Human) should be the default for any step involving customer communication
- Slack thread_ts should be used to keep all updates for a single task in one thread

---

## Architecture Decision Records

All major decisions are documented in `docs/adr/`:

| ADR | Title | Status |
|-----|-------|--------|
| 01 | Foundation Architecture | ACCEPTED |
| 02 | Data Model & Schema Design | PROPOSED |
| 03 | 4-Tier LLM Service | PROPOSED |
| 04 | SOP Execution Engine | PROPOSED |
| 05 | Agent Loop System | PROPOSED |
| 06 | Slack Integration | PROPOSED |
| 07 | Observability & Cost Tracking | PROPOSED |
| 08 | Credential Management & Webhook Security | PROPOSED |
| 09 | Admin Interface & Authentication | PROPOSED |
| 10 | CRM Integration | PROPOSED |

---

## Company-Specific Context

- **Company:** Eighty Eight Services LLC, dba Snowmass
- **Location:** Twin Cities metro area, Minnesota
- **Services:** Snow removal (winter), lawn care and landscaping (spring/summer/fall), fertilizer & weed control (seasonal)
- **Sales Window:** Fertilizer/weed control customers need to be signed up between mid-February and end of May
- **Co-owners:** Chris and Steven Bishop (50/50)
- **Current State:** No documented SOPs, CRM being built separately, no dedicated back-office software. Chris handles everything manually.
- **Primary Need:** Lead generation and customer acquisition, not operational efficiency
- **Website:** lawnworksmn.com (being migrated to Rails 8)
