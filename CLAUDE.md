# CLAUDE.md — SOP Engine

## Project Overview

This is a Rails 8 business process engine for a small lawn care/snow removal company (Eighty Eight Services LLC, dba Snowmass) in the Twin Cities, MN. It automates back-office operations by defining Standard Operating Procedures (SOPs) and executing them via background jobs with AI-powered decision making.

**Read `docs/SPEC.md` before doing any implementation work.** It contains the complete system design, data models, architecture decisions, and implementation order. ADRs in `docs/adr/` document every major architectural decision.

## Key Architecture Decisions

- **Full-stack Rails 8** with admin UI (Tailwind 4, Stimulus, Turbo). NOT API-only.
- **Two interfaces:** Slack = operations hub (approvals, notifications, agent comms). Admin UI = management plane (SOP builder, task monitor, dashboard, agent mgmt).
- **No customer data.** CRM is external. CrmService wraps the CRM API. MockCrmData for dev/test.
- **Agents are not persistent.** They are Solid Queue jobs that run, do work, and exit.
- **4-tier LLM system:** Tier 0 (no LLM), Tier 1 (Haiku), Tier 2 (Sonnet), Tier 3 (Opus/escalation only)
- **Solid Queue** for all background processing — recurring jobs, watchers, task workers.
- **PostgreSQL** for everything including job queue (Solid Queue) and agent memory.
- **Amazon SES** for transactional email.
- **Rails 8 native auth** + Pundit (admin/viewer roles). No Devise.
- **UUID primary keys** on all tables.

## Tech Stack

- Rails 8 (full-stack with views)
- PostgreSQL
- Solid Queue (built-in)
- Tailwind CSS 4, Stimulus, Turbo (Frames + Streams), Importmaps
- Anthropic Claude API (all tiers)
- Slack API (Bot + Interactive Components)
- Amazon SES (transactional email)
- Pundit (authorization)
- External CRM via CrmService API

## Development Commands

```bash
bin/rails db:create db:migrate db:seed
bin/dev  # Procfile.dev with foreman
```

## Project Structure

```
app/
├── models/          # Agent, Sop, Step, Task, TaskEvent, Watcher, AgentMemory, Credential, User
├── jobs/            # AgentLoopJob, WatcherJob, TaskWorkerJob, HumanResponseJob, MemoryMaintenanceJob, DailySummaryJob
├── services/        # LlmService, SlackService, EmailService, CrmService, CredentialService
├── controllers/
│   ├── admin/       # Dashboard, SOPs, Tasks, Agents, Credentials
│   └── api/v1/     # Webhooks (Slack, email)
├── views/admin/     # ERB templates with Tailwind 4
├── policies/        # Pundit authorization policies
docs/
├── SPEC.md          # Full system specification (THE source of truth)
├── PRODUCT-BRIEF-sop-engine.md
├── adr/             # 10 Architecture Decision Records
config/
├── recurring.yml    # Solid Queue recurring job schedules
```

## Implementation Order (Waves)

Follow this order strictly:
1. **Wave A:** Scaffold app + migrations (8 tables + users)
2. **Wave B:** Services (LlmService, SlackService, EmailService, CrmService, CredentialService)
3. **Wave C:** Jobs (TaskWorkerJob, WatcherJob, AgentLoopJob, supporting jobs, recurring.yml)
4. **Wave D:** Admin UI (auth, layout, dashboard, SOP builder, task monitor, agent mgmt)
5. **Wave E:** SOPs (seed data, Slack bot wiring, SOP 1 + SOP 2 end-to-end)
6. **Wave F:** Deploy (Heroku setup, end-to-end tests, production deploy)

## Critical Rules

- Every LLM call MUST be logged to TaskEvents with token counts
- Every external action MUST be logged to TaskEvents
- Task.context (jsonb) is the data pipeline between steps — customer data keys prefixed with `customer_`
- Steps MUST NOT delete keys from context — append or overwrite only
- Start with all customer-facing actions requiring human approval via Slack
- The escalation chain is: Haiku -> Sonnet -> Opus -> Human (Slack)
- Use Slack threads (thread_ts) to group task updates
- Agent memories must be pruned — use the MemoryMaintenanceJob
- All tables use UUID primary keys — enable pgcrypto extension
- All foreign keys must be indexed

## Model Strings

```ruby
TIER_MODELS = {
  1 => 'claude-haiku-4-5-20251001',
  2 => 'claude-sonnet-4-5-20250929',
  3 => 'claude-opus-4-6'
}.freeze
```
