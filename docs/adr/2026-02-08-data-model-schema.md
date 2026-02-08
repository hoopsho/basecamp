# ADR 02: Data Model & Schema Design

**ADR ID:** 2026-02-02
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FOUNDATION

The SOP Engine requires a database schema that supports:

- Defining business processes (SOPs) with ordered steps
- Tracking running instances of those processes (tasks) with full audit trails
- Storing agent role definitions and persistent memory
- Managing encrypted credentials for external services
- Flexible configuration via JSONB columns (prompt templates, trigger configs, step configs)
- Watcher definitions for automated trigger detection

The schema must be clean, well-indexed, and designed for the job execution patterns described in ADR #04 and #05.

---

## Decision

**Decision:** We will use 8 PostgreSQL tables with UUID primary keys, JSONB for all flexible configuration, Rails 7+ enum syntax, and encrypted attributes for credentials. No customers table — customer data lives in the external CRM (see ADR #10).

### Schema Overview

```
agents ──< sops ──< steps
  │          │
  │          └──< tasks ──< task_events
  │                 │
  │                 └── parent_task (self-referential)
  │
  ├──< watchers
  ├──< agent_memories
  │
credentials (standalone)
```

### Table Definitions

#### agents

| Column                | Type     | Notes                                             |
| --------------------- | -------- | ------------------------------------------------- |
| id                    | uuid     | PK                                                |
| name                  | string   | e.g., "Lead Response Agent"                       |
| slug                  | string   | Unique, used in code references and recurring.yml |
| description           | text     | Role definition — included in LLM system prompts  |
| status                | enum     | active, paused, disabled                          |
| slack_channel         | string   | Primary channel this agent posts to               |
| loop_interval_minutes | integer  | Nullable. How often AgentLoopJob runs.            |
| capabilities          | jsonb    | What services/actions this agent can use          |
| created_at            | datetime |                                                   |
| updated_at            | datetime |                                                   |

Indexes: `slug` (unique)

#### sops

| Column            | Type     | Notes                                             |
| ----------------- | -------- | ------------------------------------------------- |
| id                | uuid     | PK                                                |
| agent_id          | uuid     | FK -> agents                                      |
| name              | string   | e.g., "Past Customer Reactivation Outreach"       |
| slug              | string   | Unique                                            |
| description       | text     |                                                   |
| trigger_type      | enum     | manual, watcher, event, agent_loop                |
| trigger_config    | jsonb    | Conditions for automatic triggering               |
| required_services | string[] | e.g., ["email:send", "llm:tier1", "slack:post"]   |
| status            | enum     | active, draft, disabled                           |
| version           | integer  | For SOP versioning                                |
| max_tier          | integer  | Highest LLM tier this SOP is allowed to use (0-3) |
| created_at        | datetime |                                                   |
| updated_at        | datetime |                                                   |

Indexes: `slug` (unique), `agent_id`, `status`

#### steps

| Column          | Type     | Notes                                                                                                                |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| id              | uuid     | PK                                                                                                                   |
| sop_id          | uuid     | FK -> sops                                                                                                           |
| position        | integer  | Ordering within the SOP                                                                                              |
| name            | string   | e.g., "Classify incoming email"                                                                                      |
| description     | text     |                                                                                                                      |
| step_type       | enum     | query, api_call, llm_classify, llm_draft, llm_decide, llm_analyze, slack_notify, slack_ask_human, enqueue_next, wait |
| config          | jsonb    | Type-specific config: prompt templates, API params, etc.                                                             |
| llm_tier        | integer  | Minimum tier for this step (0-3)                                                                                     |
| max_llm_tier    | integer  | Maximum tier for escalation (0-3)                                                                                    |
| on_success      | string   | Next step position or "complete"                                                                                     |
| on_failure      | string   | Next step position, "retry", "escalate", or "fail"                                                                   |
| on_uncertain    | string   | Next step position or "escalate_tier"                                                                                |
| max_retries     | integer  | Default 3                                                                                                            |
| timeout_seconds | integer  | How long before step is considered hung                                                                              |
| created_at      | datetime |                                                                                                                      |
| updated_at      | datetime |                                                                                                                      |

Indexes: `sop_id`, `[sop_id, position]` (unique)

#### tasks

| Column                | Type     | Notes                                                                                  |
| --------------------- | -------- | -------------------------------------------------------------------------------------- |
| id                    | uuid     | PK                                                                                     |
| sop_id                | uuid     | FK -> sops                                                                             |
| agent_id              | uuid     | FK -> agents                                                                           |
| status                | enum     | pending, in_progress, waiting_on_human, waiting_on_timer, completed, failed, escalated |
| current_step_position | integer  |                                                                                        |
| context               | jsonb    | Working data passed between steps — the pipeline payload                               |
| priority              | integer  | For queue ordering                                                                     |
| started_at            | datetime |                                                                                        |
| completed_at          | datetime |                                                                                        |
| error_message         | text     |                                                                                        |
| parent_task_id        | uuid     | FK -> tasks (nullable, for sub-tasks)                                                  |
| slack_thread_ts       | string   | Slack thread for this task's updates                                                   |
| created_at            | datetime |                                                                                        |
| updated_at            | datetime |                                                                                        |

Indexes: `sop_id`, `agent_id`, `status`, `parent_task_id`, `[agent_id, status]` (composite for agent loop queries)

#### task_events

| Column           | Type     | Notes                                                                                                                         |
| ---------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| id               | uuid     | PK                                                                                                                            |
| task_id          | uuid     | FK -> tasks                                                                                                                   |
| step_id          | uuid     | FK -> steps (nullable)                                                                                                        |
| event_type       | enum     | step_started, step_completed, step_failed, llm_call, llm_escalated, human_requested, human_responded, api_called, error, note |
| llm_tier_used    | integer  | 0-3, which tier was actually used                                                                                             |
| llm_model        | string   | Actual model string used                                                                                                      |
| llm_tokens_in    | integer  |                                                                                                                               |
| llm_tokens_out   | integer  |                                                                                                                               |
| input_data       | jsonb    | What was sent to the step                                                                                                     |
| output_data      | jsonb    | What the step produced                                                                                                        |
| confidence_score | float    | For LLM steps                                                                                                                 |
| duration_ms      | integer  |                                                                                                                               |
| created_at       | datetime | No updated_at — events are immutable                                                                                          |

Indexes: `task_id`, `step_id`, `event_type`, `created_at`, `[task_id, created_at]` (composite for timeline queries)

#### watchers

| Column           | Type     | Notes                                                              |
| ---------------- | -------- | ------------------------------------------------------------------ |
| id               | uuid     | PK                                                                 |
| agent_id         | uuid     | FK -> agents                                                       |
| sop_id           | uuid     | FK -> sops (which SOP to trigger)                                  |
| name             | string   | e.g., "Check for new lead emails"                                  |
| check_type       | enum     | email_inbox, webhook_queue, schedule, database_condition, api_poll |
| check_config     | jsonb    | Type-specific config                                               |
| interval_minutes | integer  | How often to run this check                                        |
| last_checked_at  | datetime |                                                                    |
| status           | enum     | active, paused, disabled                                           |
| created_at       | datetime |                                                                    |
| updated_at       | datetime |                                                                    |

Indexes: `agent_id`, `sop_id`, `status`

#### agent_memories

| Column          | Type     | Notes                                            |
| --------------- | -------- | ------------------------------------------------ |
| id              | uuid     | PK                                               |
| agent_id        | uuid     | FK -> agents                                     |
| memory_type     | enum     | observation, context, working_note, decision_log |
| content         | text     |                                                  |
| importance      | integer  | 1-10, for summarization/pruning                  |
| expires_at      | datetime | Nullable — some memories age out                 |
| related_task_id | uuid     | FK -> tasks (nullable)                           |
| created_at      | datetime |                                                  |
| updated_at      | datetime |                                                  |

Indexes: `agent_id`, `[agent_id, importance]` (composite for memory loading), `expires_at`, `related_task_id`

#### credentials

| Column          | Type     | Notes                                    |
| --------------- | -------- | ---------------------------------------- |
| id              | uuid     | PK                                       |
| service_name    | string   | e.g., "slack", "anthropic", "ses", "crm" |
| credential_type | enum     | api_key, oauth_token, webhook_secret     |
| encrypted_value | text     | Rails encrypted attributes               |
| scopes          | string[] | What this credential allows              |
| expires_at      | datetime | Nullable, for OAuth tokens               |
| refresh_token   | text     | Encrypted, for OAuth refresh             |
| status          | enum     | active, expired, revoked                 |
| created_at      | datetime |                                          |
| updated_at      | datetime |                                          |

Indexes: `[service_name, status]` (composite for credential lookup)

---

## Consequences

### Positive Consequences

- **UUID PKs everywhere** — Safe to expose in URLs/APIs, no sequential ID enumeration, future-proof for distributed systems or CRM cross-references
- **JSONB flexibility** — Step configs, task context, trigger configs, and agent capabilities can evolve without migrations. PostgreSQL GIN indexes available if query performance matters.
- **Immutable audit log** — task_events has no updated_at. Events are append-only. Full traceability.
- **Composite indexes** — Optimized for the most common query patterns: agent loop queries (`[agent_id, status]`), timeline views (`[task_id, created_at]`), memory loading (`[agent_id, importance]`)
- **Clean separation** — No customer data in this schema. Process execution data only.

### Negative Consequences / Trade-offs

- **UUID storage cost** — 16 bytes per PK vs 8 bytes for bigint. Negligible at this scale.
- **JSONB querying** — Complex queries on JSONB require careful indexing. Step configs and task context should be accessed via Ruby, not complex SQL.
- **No foreign key to customers** — Task.context carries customer references as data, not as FK relationships. No referential integrity for CRM data.
- **task_events growth** — This table will grow the fastest. May need partitioning or archival strategy in the future.

### Resource Impact

- Development effort: MEDIUM
- Ongoing maintenance: LOW (schema is stable once defined)
- Infrastructure cost: NONE (PostgreSQL handles this scale easily)

---

## Alternatives Considered

### Alternative 1: Bigint Primary Keys

- Standard Rails default, slightly more storage-efficient
- Why rejected: UUIDs are safer for external exposure, better for future API integrations, and align with project conventions (CLAUDE.md requires UUID PKs)

### Alternative 2: Separate Config Tables Instead of JSONB

- Normalize step configs, trigger configs, etc. into dedicated tables with typed columns
- Why rejected: Over-normalization for data that varies by type. JSONB with application-level validation is more flexible. Step config for an `llm_classify` step is completely different from a `wait` step — a single typed table can't represent both cleanly.

### Alternative 3: Include Customers Table

- Store customer data locally for faster queries and offline capability
- Why rejected: Customer data belongs in the CRM. Duplicating it creates sync problems and data ownership ambiguity. See ADR #10.

---

## Implementation

### Phase 1: Migrations

- Generate all 8 migrations with UUID PKs, proper column types, indexes, and foreign keys
- Enable `pgcrypto` extension for UUID generation
- Run `db:migrate` and verify schema

### Phase 2: Models

- Define all associations (`has_many`, `belongs_to`)
- Add validations (presence, uniqueness, inclusion)
- Define enums using Rails 7+ syntax: `enum :status, [:active, :paused, :disabled]`
- Add encrypted attributes to Credential model
- Define scopes for common queries (e.g., `Task.active`, `AgentMemory.important`, `Credential.for_service`)

### Testing Strategy

- Unit tests for all model validations and associations
- Test enum values and transitions
- Test scopes return correct results
- Test encrypted attributes on Credential
- Fixtures for all 8 models with realistic data

---

## JSONB Schema Conventions

To maintain consistency across JSONB columns, these conventions apply:

**step.config** — Always includes:

```json
{
  "system": "System prompt for LLM steps (nullable for Tier 0)",
  "prompt_template": "Prompt with {{variable}} placeholders",
  "response_format": "json | text",
  "api_endpoint": "For api_call steps",
  "api_method": "GET | POST",
  "wait_duration": "For wait steps (ISO 8601 duration)",
  "slack_channel": "For slack_notify/slack_ask_human steps",
  "slack_message_template": "Message with {{variable}} placeholders"
}
```

**task.context** — Accumulates as steps execute:

```json
{
  "crm_customer_id": "uuid-from-crm",
  "customer_name": "Jane Smith",
  "customer_email": "jane@example.com",
  "classification": "new_lead",
  "confidence": 0.92,
  "draft_email_subject": "...",
  "draft_email_body": "...",
  "email_sent_at": "2026-02-15T10:30:00Z",
  "email_message_id": "ses-message-id"
}
```

**agent.capabilities** — Declares what the agent can do:

```json
{
  "services": [
    "email:send",
    "slack:post",
    "llm:tier1",
    "llm:tier2",
    "crm:read",
    "crm:write"
  ],
  "max_concurrent_tasks": 5,
  "allowed_sop_slugs": ["lead-response", "quote-follow-up"]
}
```

---

## Related ADRs

- [ADR 01] Foundation Architecture — Overall system design
- [ADR 04] SOP Execution Engine — How tasks and steps execute
- [ADR 05] Agent Loop System — How agents query and use this data
- [ADR 07] Observability & Cost Tracking — TaskEvent logging patterns
- [ADR 08] Credential Management — Encrypted credential storage
- [ADR 10] CRM Integration — Why no customers table
