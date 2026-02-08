# ADR 04: SOP Execution Engine

**ADR ID:** 2026-02-04
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES

The SOP Engine's core purpose is executing defined business processes automatically. An SOP (Standard Operating Procedure) is a sequence of steps. A Task is a running instance of an SOP. The execution engine is responsible for:

- Running each step in sequence
- Passing data between steps via task.context
- Handling success, failure, and uncertainty at each step
- Logging everything to TaskEvents
- Integrating with LlmService, SlackService, EmailService, and CrmService
- Managing retries, timeouts, and escalation
- Pausing for human input and resuming when it arrives

This is the most critical component of the system. If the execution engine is unreliable, nothing works.

---

## Decision

**Decision:** We will build a step-by-step execution engine using Solid Queue jobs, where each step is executed by a TaskWorkerJob that processes one step, updates task.context, logs events, and enqueues the next step. Tasks are sequential with simple branching via on_success/on_failure/on_uncertain directives.

### Execution Model

```
TaskWorkerJob receives: (task_id, step_position)

1. Load task and current step
2. Validate task status (must be in_progress or pending)
3. Log step_started event
4. Execute step based on step_type (dispatch to handler)
5. Receive result: { success:, output:, confidence: }
6. Log step_completed or step_failed event
7. Merge output into task.context
8. Determine next action:
   - success -> follow on_success (next position or "complete")
   - failure -> follow on_failure ("retry", "escalate", "fail", or position)
   - uncertain -> follow on_uncertain ("escalate_tier" or position)
9. Enqueue next TaskWorkerJob or mark task complete/failed
```

### Step Type Handlers

Each step_type maps to a handler method that knows how to execute it:

| step_type         | Handler                  | What It Does                                                                                |
| ----------------- | ------------------------ | ------------------------------------------------------------------------------------------- |
| `query`           | `handle_query`           | Execute a database query or CRM API call. Evaluate a condition. Pure Ruby, no LLM.          |
| `api_call`        | `handle_api_call`        | Call an external API (CRM, weather, etc.) using config from step.config.                    |
| `llm_classify`    | `handle_llm_classify`    | Send prompt to LlmService. Classify input into categories. Returns category + confidence.   |
| `llm_draft`       | `handle_llm_draft`       | Send prompt to LlmService. Draft text content (email, message). Returns draft text.         |
| `llm_decide`      | `handle_llm_decide`      | Send prompt to LlmService. Make a judgment call. Returns decision + reasoning + confidence. |
| `llm_analyze`     | `handle_llm_analyze`     | Send prompt to LlmService. Complex analysis. Returns structured analysis + confidence.      |
| `slack_notify`    | `handle_slack_notify`    | Post a message to a Slack channel. No response expected.                                    |
| `slack_ask_human` | `handle_slack_ask_human` | Post to Slack with interactive buttons. Task status -> waiting_on_human. Execution pauses.  |
| `enqueue_next`    | `handle_enqueue_next`    | Trigger another SOP (create a child task) or schedule a follow-up task with a delay.        |
| `wait`            | `handle_wait`            | Task status -> waiting_on_timer. Schedule a delayed job to resume after duration.           |

### Task Context as Data Pipeline

`task.context` (JSONB) is the primary way data flows between steps. Each step reads from context and writes back to it:

```
Step 1 (query CRM):
  reads: nothing (initial step)
  writes: { crm_customer_id, customer_name, customer_email, last_service, services }

Step 2 (llm_draft email):
  reads: { customer_name, last_service, services }
  writes: { draft_subject, draft_body, draft_confidence }

Step 3 (slack_ask_human):
  reads: { customer_name, draft_subject, draft_body }
  writes: { human_approved: true/false, human_notes: "..." }

Step 4 (api_call send email):
  reads: { customer_email, draft_subject, draft_body, human_approved }
  writes: { email_sent_at, email_message_id }
```

Convention: Steps MUST NOT delete keys from context. They append or overwrite. This preserves the full data trail.

### Prompt Template Interpolation

Step configs contain prompt templates with `{{variable}}` placeholders. Before calling LlmService, the engine interpolates these from task.context:

```ruby
# step.config["prompt_template"]
"Draft a reactivation email for {{customer_name}} who last used our
{{last_service}} service. They are located in {{customer_city}}."

# After interpolation from task.context
"Draft a reactivation email for Jane Smith who last used our
fertilizer service. They are located in Eagan."
```

Missing variables render as empty strings and log a warning. The step does NOT fail for missing variables — the LLM can often work around them.

### Branching Logic

Each step defines three paths:

- **on_success** — Step completed successfully. Value is either a step position (integer) or `"complete"`.
- **on_failure** — Step failed. Value is a step position, `"retry"`, `"escalate"`, or `"fail"`.
- **on_uncertain** — LLM confidence below threshold. Value is a step position or `"escalate_tier"`.

For v0.1, most SOPs are linear: `on_success` points to the next position, `on_failure` is `"retry"` or `"fail"`, and `on_uncertain` is `"escalate_tier"`.

```
Step 1 (classify) -> on_success: 2, on_failure: "retry", on_uncertain: "escalate_tier"
Step 2 (draft)    -> on_success: 3, on_failure: "retry", on_uncertain: "escalate_tier"
Step 3 (approve)  -> on_success: 4, on_failure: "fail"
Step 4 (send)     -> on_success: "complete", on_failure: "fail"
```

### Retry Strategy

When `on_failure` is `"retry"`:

1. Increment retry count (stored in task.context as `_retries_step_{position}`)
2. If retry count < step.max_retries (default 3):
   - Wait with exponential backoff: `2^retry_count` seconds (2s, 4s, 8s)
   - Re-enqueue TaskWorkerJob for the same step
3. If retry count >= max_retries:
   - Log step_failed event
   - Escalate to human via Slack (#escalations channel)
   - Task status -> failed

### Timeout Handling

Each step has a `timeout_seconds` value. The TaskWorkerJob tracks execution time:

1. If step execution exceeds timeout:
   - Log timeout event
   - Treat as failure (follow on_failure path)
2. Solid Queue has its own job timeout. Set job timeout to `step.timeout_seconds + 30` (buffer for logging/cleanup).

### Human-in-the-Loop (slack_ask_human)

This step type pauses execution and waits for a human response:

1. TaskWorkerJob posts to Slack with interactive buttons/options
2. Task status -> `waiting_on_human`
3. Task stores the Slack message_ts in context for reference
4. Job exits. No more steps execute.
5. When human clicks a button:
   - Slack sends webhook to Rails endpoint
   - HumanResponseJob enqueues with the response data
   - HumanResponseJob merges response into task.context
   - Task status -> `in_progress`
   - Enqueues TaskWorkerJob for the next step

Timeout for human response: configurable per step (default 24 hours). If no response:

- Post reminder to #escalations
- After second timeout (48 hours), follow on_failure path

### Sub-Tasks (enqueue_next)

The `enqueue_next` step can:

1. **Trigger another SOP** — Creates a new Task with `parent_task_id` set. The parent task continues independently.
2. **Schedule a follow-up** — Creates a new Task with a `scheduled_for` time. Solid Queue delayed job handles the timing.

Sub-tasks run independently. The parent task does NOT wait for sub-tasks to complete (fire-and-forget).

---

## Consequences

### Positive Consequences

- **One step per job** — If a job crashes, only one step is lost. The task can resume from the last completed step.
- **Full traceability** — Every step start, completion, failure, and retry is logged to TaskEvents.
- **Composable** — SOPs can trigger other SOPs via enqueue_next. Complex workflows are built from simple pieces.
- **Human-friendly pauses** — Tasks naturally pause for human input and resume asynchronously.
- **Context accumulation** — task.context grows as the task progresses, creating a full record of all data.

### Negative Consequences / Trade-offs

- **Job overhead** — Each step is a separate job enqueue/dequeue. Minor overhead for Solid Queue, but acceptable.
- **Sequential execution** — Steps within a task run one at a time. No parallel step execution in v0.1.
- **Context size** — task.context JSONB can grow large if steps produce verbose output. May need cleanup conventions.
- **Template interpolation is simple** — `{{variable}}` replacement only. No conditionals, no loops in templates. Complex logic must live in step handlers.

### Resource Impact

- Development effort: HIGH (core of the system)
- Ongoing maintenance: MEDIUM (new step types may need new handlers)
- Infrastructure cost: NONE (Solid Queue + PostgreSQL)

---

## Alternatives Considered

### Alternative 1: Execute All Steps in a Single Job

- One long-running job executes the entire SOP from start to finish
- Why rejected: If the job crashes at step 5 of 8, all progress is lost. No clean pause point for human-in-the-loop. Job timeout becomes problematic for multi-step SOPs. Harder to debug.

### Alternative 2: State Machine (AASM)

- Use a state machine gem to manage task transitions
- Why rejected: Adds a dependency for something the simple on_success/on_failure/on_uncertain branching handles. State machines add complexity for representing step-to-step transitions. The current approach is a state machine — it just uses step positions instead of named states.

### Alternative 3: Parallel Step Execution

- Allow some steps to run concurrently (e.g., send email AND post to Slack simultaneously)
- Why rejected: Adds significant complexity (fan-out, fan-in, partial failure handling) for minimal benefit in v0.1. All current SOPs are sequential. Can be added later if needed.

---

## Implementation

### Phase 1: TaskWorkerJob Core

- Job accepts (task_id, step_position)
- Load task and step, validate state
- Dispatch to handler based on step_type
- Log step_started and step_completed/step_failed events
- Merge output into task.context
- Determine and enqueue next step

### Phase 2: Step Type Handlers

- Implement all 10 handler methods
- Each handler returns `{ success:, output:, confidence: }`
- LLM handlers call LlmService with prompt interpolation
- Slack handlers call SlackService
- API handlers call the appropriate service

### Phase 3: Retry, Timeout, and Human-in-the-Loop

- Implement retry logic with exponential backoff
- Implement timeout detection
- Implement slack_ask_human pause/resume flow
- Build HumanResponseJob for webhook processing

### Testing Strategy

- Unit tests: Each step type handler with mocked services
- Unit tests: Branching logic (on_success, on_failure, on_uncertain)
- Unit tests: Retry counting and backoff calculation
- Integration tests: Full SOP execution from start to complete
- Integration tests: Human-in-the-loop pause and resume
- Fixtures: SOPs with steps, tasks with various statuses

---

## Related ADRs

- [ADR 01] Foundation Architecture — Solid Queue for job processing
- [ADR 02] Data Model — Task, Step, TaskEvent schemas
- [ADR 03] 4-Tier LLM Service — Called by LLM step handlers
- [ADR 05] Agent Loop System — Creates tasks that this engine executes
- [ADR 06] Slack Integration — slack_notify and slack_ask_human handlers
- [ADR 07] Observability — TaskEvent logging patterns
- [ADR 10] CRM Integration — query and api_call handlers access CRM
