# ADR 07: Observability & Cost Tracking

**ADR ID:** 2026-02-07
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES | INFRASTRUCTURE

The SOP Engine makes autonomous decisions, calls external APIs, sends customer-facing emails, and spends money on LLM calls. Without comprehensive observability, the system is a black box. We need to answer these questions at any time:

- **What happened?** — Full trace of every action for any task
- **What went wrong?** — When a task fails, exactly which step, why, and what the system tried
- **How much does it cost?** — LLM token usage by tier, agent, SOP, and time period
- **Is it working?** — Agent health, task throughput, response times, success rates
- **Is it worth it?** — ROI: emails sent vs responses received vs customers signed

This is a cross-cutting concern that affects every service and job in the system.

---

## Decision

**Decision:** We will use TaskEvents as the unified audit log for all system activity, with Slack (#ops-log, #escalations) for real-time alerting, and the admin dashboard for aggregated metrics and cost tracking. No external observability tools in v0.1 — the system monitors itself.

### TaskEvent as the Unified Audit Log

Every significant action in the system creates a TaskEvent record. This is not optional — services and jobs MUST log events.

#### Event Types and What They Capture

| event_type        | When Created                           | Key Data                                                            |
| ----------------- | -------------------------------------- | ------------------------------------------------------------------- |
| `step_started`    | TaskWorkerJob begins a step            | step_id, input_data (from task.context)                             |
| `step_completed`  | Step finishes successfully             | output_data, duration_ms, confidence_score                          |
| `step_failed`     | Step fails                             | error message, retry count, failure reason                          |
| `llm_call`        | LlmService makes an API call           | tier_used, model, tokens_in, tokens_out, confidence, prompt summary |
| `llm_escalated`   | LlmService escalates to a higher tier  | from_tier, to_tier, reason (low confidence)                         |
| `human_requested` | slack_ask_human posts approval request | Slack message_ts, options presented                                 |
| `human_responded` | Human clicks a button/makes a decision | decision, response time, user_id                                    |
| `api_called`      | External API call (email, CRM, etc.)   | service, endpoint, success/failure, response summary                |
| `error`           | Unhandled error or exception           | error class, message, backtrace (truncated)                         |
| `note`            | Agent observation or system note       | Free-form text, importance level                                    |

#### Logging Convention

Every service call follows this pattern:

```ruby
# In TaskWorkerJob or AgentLoopJob:
event = TaskEvent.create!(
  task: task,
  step: current_step,
  event_type: :llm_call,
  llm_tier_used: result[:tier_used],
  llm_model: result[:model],
  llm_tokens_in: result[:tokens_in],
  llm_tokens_out: result[:tokens_out],
  confidence_score: result[:confidence],
  input_data: { prompt_summary: prompt.truncate(500) },
  output_data: { response_summary: response.truncate(500) },
  duration_ms: elapsed_ms
)
```

Rules:

- **Every LLM call MUST be logged** — No exceptions. This is the primary cost tracking mechanism.
- **Every external API call MUST be logged** — Email sends, Slack posts, CRM queries.
- **Input/output data should be summarized** — Don't store full prompts or full email bodies in events. Truncate to 500 chars. The full data lives in task.context.
- **Duration is always tracked** — Wrap every external call in a timer.

### Cost Tracking

#### LLM Cost Calculation

Costs are calculated from TaskEvent data using token counts and per-model pricing:

```ruby
# Approximate per-token costs (input/output)
LLM_COSTS = {
  'claude-haiku-4-5-20251001'   => { input: 0.80, output: 4.00 },   # per million tokens
  'claude-sonnet-4-5-20250929'  => { input: 3.00, output: 15.00 },
  'claude-opus-4-6'             => { input: 15.00, output: 75.00 }
}.freeze

# Cost for a single call:
cost = (tokens_in * rate[:input] + tokens_out * rate[:output]) / 1_000_000.0
```

#### Cost Aggregation Queries

The admin dashboard surfaces these metrics from TaskEvents:

| Metric               | Query Pattern                                                     |
| -------------------- | ----------------------------------------------------------------- |
| Daily LLM cost       | Sum token costs for all `llm_call` events today, grouped by model |
| Cost per agent       | Sum token costs grouped by task.agent_id                          |
| Cost per SOP         | Sum token costs grouped by task.sop_id                            |
| Cost trend (30 days) | Daily cost sums for the last 30 days                              |
| Escalation rate      | Count of `llm_escalated` events / count of `llm_call` events      |
| Avg cost per task    | Total LLM cost / completed tasks                                  |

#### Budget Alerting

DailySummaryJob checks daily costs against thresholds:

- **Warning** ($10/day): Post to #ops-log
- **Alert** ($25/day): Post to #escalations
- **Critical** ($50/day): Post to #escalations + pause all non-essential agent loops

Thresholds are configurable. Start conservative and adjust.

### Real-Time Monitoring via Slack

#### #ops-log (System Heartbeat)

- Agent loop heartbeats (every cycle)
- Task completion notifications
- Daily summary (DailySummaryJob at 7 PM)
- Memory pruning stats (MemoryMaintenanceJob at 2 AM)

#### #escalations (Attention Required)

- Task failures after retry exhaustion
- Human approval timeouts
- LLM escalation to Opus (unusual — worth noting)
- Budget threshold breaches
- Agent heartbeat missing (health check failure)

### Admin Dashboard Metrics

The admin UI dashboard (see ADR #09) displays:

#### Operations Panel

- Active tasks by agent and status
- Tasks completed today / this week
- Average task completion time
- Tasks currently waiting on human

#### Performance Panel

- Lead response time (time from email received to acknowledgment sent)
- SOP success rate (completed / total by SOP)
- Step failure rate (failures by step type)
- Human response time (time from Slack post to button click)

#### Cost Panel

- Today's LLM cost (by tier)
- Month-to-date LLM cost
- Cost per agent
- Cost per SOP
- Cost trend chart (30 days)
- Escalation rate

#### Campaign Panel (SOP-specific)

- Reactivation: emails sent, responses, sign-ups
- Lead response: leads received, responded, quoted, closed
- Collections: reminders sent, payments received
- Review requests: sent, reviews posted

### Debugging Failed Tasks

When a task fails, the TaskEvent timeline provides full traceability:

```
Task #312 — SOP: New Lead Response — Status: FAILED

Timeline:
  10:05:03  step_started    Step 1: Classify email
  10:05:04  llm_call        Haiku | 142 in / 87 out | confidence: 0.92 | $0.0004
  10:05:04  step_completed  Classification: new_lead (0.92) | 1,200ms
  10:05:04  step_started    Step 2: Draft acknowledgment
  10:05:05  llm_call        Haiku | 356 in / 245 out | confidence: 0.78 | $0.001
  10:05:05  step_completed  Draft ready | 1,800ms
  10:05:05  step_started    Step 3: Send email
  10:05:06  api_called      EmailService.send -> SES | FAILED
  10:05:06  error           SES rejected: "Email address is on suppression list"
  10:05:06  step_failed     Retry 1/3 scheduled
  10:05:08  step_started    Step 3: Send email (retry 1)
  10:05:09  api_called      EmailService.send -> SES | FAILED (same error)
  10:05:09  step_failed     Retry 2/3 scheduled
  ... (retry 3 also fails)
  10:05:14  step_failed     Max retries exceeded. Task failed.
  10:05:14  note            Posted to #escalations: SES suppression list issue
```

This timeline is visible in the admin UI task detail view and can be accessed via the API.

---

## Consequences

### Positive Consequences

- **Complete traceability** — Every action, decision, and error is logged. No blind spots.
- **Built-in cost tracking** — LLM costs calculated from actual token usage, not estimates.
- **Self-monitoring** — Slack alerts for anomalies. No external monitoring tools needed for v0.1.
- **Debugging without guessing** — Failed tasks have a complete timeline. Trace any outcome to a specific step and LLM call.
- **ROI measurement** — Campaign metrics (emails sent, responses, conversions) are derivable from TaskEvents.

### Negative Consequences / Trade-offs

- **TaskEvent volume** — This table will grow faster than any other. A single task might generate 10-20 events. Need to consider archival strategy for future.
- **Storage cost** — JSONB columns (input_data, output_data) add size. Truncation helps but doesn't eliminate growth.
- **Logging overhead** — Every action has a database write. Minor performance impact but worth monitoring.
- **No external APM** — No Datadog, New Relic, or similar. If Heroku/PostgreSQL itself has issues, we may miss them.
- **Cost calculations are approximate** — Token-based cost estimates depend on accurate pricing constants. These must be updated when Anthropic changes pricing.

### Resource Impact

- Development effort: MEDIUM (logging is woven into every service and job)
- Ongoing maintenance: LOW (archival strategy may be needed later)
- Infrastructure cost: NONE (PostgreSQL storage, minimal)

---

## Alternatives Considered

### Alternative 1: External APM (Datadog, New Relic)

- Full application monitoring, error tracking, performance metrics
- Why rejected: Adds cost ($20-100+/month), external dependency, and complexity for a system that can effectively monitor itself via TaskEvents and Slack. Reconsider if the system grows beyond what self-monitoring can handle.

### Alternative 2: Structured Logging (JSON logs to stdout)

- Log everything as structured JSON, aggregate with a log service
- Why rejected: Heroku log drains add cost and complexity. TaskEvents in PostgreSQL are queryable, aggregatable, and directly accessible from the admin UI. Structured logging is useful as a complement but not a replacement.

### Alternative 3: Separate Analytics Database

- Write events to a separate analytics DB or data warehouse
- Why rejected: Premature for v0.1 volume. PostgreSQL handles this scale. Revisit if event volume exceeds millions of rows and query performance degrades.

---

## Implementation

### Phase 1: TaskEvent Logging

- Ensure all services (LlmService, SlackService, EmailService, CrmService) log to TaskEvents
- Implement logging helpers for consistent event creation
- Add duration tracking wrappers

### Phase 2: Cost Calculation

- Implement token cost calculation from TaskEvent data
- Build daily/monthly/per-agent/per-SOP aggregation queries
- Add cost constants (update when pricing changes)

### Phase 3: Slack Alerting

- Budget threshold checking in DailySummaryJob
- Missing heartbeat detection
- Failure rate alerting

### Phase 4: Admin Dashboard

- Operations, Performance, Cost, and Campaign panels
- Task detail timeline view
- Cost trend charts

### Testing Strategy

- Unit tests: Cost calculation from token counts
- Unit tests: Budget threshold logic
- Integration tests: TaskEvent creation during job execution
- Integration tests: DailySummaryJob generates correct metrics
- Fixtures: TaskEvents with various event types and token counts

---

## Related ADRs

- [ADR 02] Data Model — TaskEvent schema
- [ADR 03] 4-Tier LLM — Token logging per call
- [ADR 04] SOP Execution Engine — Step event logging
- [ADR 05] Agent Loop System — Heartbeat and memory stats logging
- [ADR 06] Slack Integration — Alert channels and daily summary format
- [ADR 09] Admin Interface — Dashboard panels
