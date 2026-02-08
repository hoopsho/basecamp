# ADR 05: Agent Loop System

**ADR ID:** 2026-02-05
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES

The SOP Engine needs agents that behave like employees — they periodically check their domain, notice things that need attention, prioritize work, and take action. This is fundamentally different from event-driven systems where work only happens in response to triggers.

An agent loop transforms a "fancy cron system" into something with awareness. The Lead Response Agent doesn't just react to new emails — it also notices that a quote follow-up is overdue, that a lead has gone cold, or that response times are trending slower this week.

Agents also need persistent memory across loop cycles. Without memory, every loop iteration starts from scratch — the agent can't build context about patterns, learn from past decisions, or maintain situational awareness.

---

## Decision

**Decision:** We will implement agents as recurring Solid Queue jobs (AgentLoopJob) that follow a Survey -> Assess -> Prioritize -> Execute -> Report cycle, with persistent memory stored in the agent_memories table and pruned by a daily MemoryMaintenanceJob.

### Agent-as-Job Pattern

Agents are NOT persistent processes. They are:

1. **Role definitions** in the `agents` table (name, slug, capabilities, slack_channel)
2. **Recurring jobs** scheduled via `config/recurring.yml`
3. **Stateless between runs** — All state lives in the database (tasks, memories, task_events)

Each loop iteration: spin up, do work, report, die. The next iteration starts fresh with only the database for context.

### Agent Loop Cycle

```
AgentLoopJob.perform(agent_slug)

1. SURVEY DOMAIN
   - Load agent by slug
   - Query active tasks assigned to this agent (status: in_progress, pending)
   - Query watchers for this agent, run their checks
   - Load relevant agent memories (high importance + recent + task-related)

2. ASSESS (Tier 0 or Tier 1)
   - Is anything new requiring attention?
   - Are any active tasks stalled or overdue?
   - Are there patterns worth noting? (optional Tier 1 call)
   - Build a situation summary

3. PRIORITIZE (Tier 0)
   - Rank pending work by urgency/importance
   - If nothing needs doing -> log heartbeat to #ops-log, exit

4. EXECUTE
   - Pick highest-priority item
   - If new trigger detected -> create Task from appropriate SOP
   - If existing task needs advancing -> enqueue TaskWorkerJob for next step
   - Execute ONE major action per loop cycle (prevent runaway loops)

5. REPORT
   - Post summary to agent's Slack channel
   - Post heartbeat to #ops-log (even if nothing happened)
   - Update agent memories with observations
   - Log all events to TaskEvents

6. EXIT (job completes, runs again in loop_interval_minutes)
```

### One Action Per Loop

Critical constraint: each agent loop iteration executes at most ONE major action (create a task, advance a step, trigger a watcher). This prevents:

- Runaway loops that consume resources
- Race conditions with concurrent loop iterations
- Unpredictable execution order
- Difficulty debugging what happened in a cycle

If an agent has 10 pending items, it handles the highest priority one. The next iteration handles the next. At 5-minute intervals, this means all 10 items are addressed within an hour — fast enough for this business.

Exception: Watchers are checked every loop cycle regardless. A watcher detecting 5 new leads creates 5 tasks (which are then prioritized and executed one per loop).

### Recurring Job Configuration

```yaml
# config/recurring.yml
lead_response_agent_loop:
  class: AgentLoopJob
  args: ["lead_response"]
  schedule: "every 5 minutes"

marketing_agent_loop:
  class: AgentLoopJob
  args: ["marketing"]
  schedule: "every 15 minutes"

ar_agent_loop:
  class: AgentLoopJob
  args: ["ar"]
  schedule: "every 30 minutes"
```

Intervals are conservative to start. Tighten as the system proves stable.

### Watcher Integration

Watchers are checked during the Survey phase of the agent loop:

```ruby
# During SURVEY:
agent.watchers.active.each do |watcher|
  next if watcher.last_checked_at && watcher.last_checked_at > watcher.interval_minutes.minutes.ago

  results = WatcherJob.check(watcher)
  results.each do |trigger_data|
    Task.create!(
      sop: watcher.sop,
      agent: agent,
      status: :pending,
      context: trigger_data,
      priority: calculate_priority(watcher, trigger_data)
    )
  end

  watcher.update!(last_checked_at: Time.current)
end
```

Watchers can also run as standalone recurring jobs (WatcherJob) for time-sensitive checks that can't wait for the agent loop. For example, the email inbox watcher runs every 5 minutes independently, creating tasks that the agent loop picks up.

### Agent Memory System

#### Memory Types

| Type           | Purpose                                    | Example                                                               | Default Importance |
| -------------- | ------------------------------------------ | --------------------------------------------------------------------- | ------------------ |
| `observation`  | Something the agent noticed                | "Lead response times trending slower — avg 2.3 hours this week"       | 5                  |
| `context`      | Background information for decision-making | "Jane Smith prefers email over phone"                                 | 6                  |
| `working_note` | In-progress work tracking                  | "Reactivation campaign batch 2 sent, waiting for responses"           | 4                  |
| `decision_log` | Record of a judgment call and reasoning    | "Classified edge-case email as new_lead because it mentioned pricing" | 7                  |

#### Memory Loading for Prompts

When building the agent loop prompt, include:

1. **High-importance memories (8+)** — Always included regardless of age
2. **Recent memories (last 24 hours)** — All types, any importance
3. **Active task memories** — Memories linked to currently active tasks via `related_task_id`
4. **Summarized older context** — A periodic summary of older memories (generated by MemoryMaintenanceJob)

Maximum memory tokens per prompt: ~2,000 tokens. If memories exceed this, truncate lowest-importance first.

#### Memory Creation

Agents create memories at the end of each loop cycle:

```ruby
# During REPORT:
if significant_action_taken
  AgentMemory.create!(
    agent: agent,
    memory_type: :observation,
    content: "Processed new lead from Jane Smith (Eagan). Classified as high-priority — mentioned fertilizer service.",
    importance: 6,
    related_task_id: task.id,
    expires_at: 30.days.from_now
  )
end
```

#### Memory Pruning (MemoryMaintenanceJob)

Runs daily at 2 AM:

1. **Delete expired memories** — Where `expires_at < Time.current`
2. **Summarize old low-importance memories** — Memories older than 7 days with importance < 5:
   - Group by agent
   - Call LlmService (Tier 1) to summarize each agent's old memories into a single context memory
   - Delete the originals, keep the summary
3. **Cap total memories per agent** — If an agent has > 100 memories, delete lowest-importance ones until at 100
4. **Log pruning stats** — Post to #ops-log: "Memory maintenance: pruned 47 memories, created 3 summaries"

### Heartbeat and Health Monitoring

Every agent loop posts a heartbeat, even if nothing happened:

```
[#ops-log] Lead Response Agent: Loop completed.
  Active tasks: 3 | New triggers: 0 | Action taken: Advanced Task #412 to step 3
  Next run: 5 minutes
```

If an agent fails to post a heartbeat for 2x its interval, the DailySummaryJob flags it:

```
[#escalations] WARNING: Marketing Agent has not posted a heartbeat in 45 minutes
  (expected every 15 min). Check worker health.
```

---

## Consequences

### Positive Consequences

- **Employee-like behavior** — Agents proactively survey their domain, not just react to events
- **Predictable execution** — One action per loop, fixed intervals, clear logging
- **Memory continuity** — Agents build context across cycles without unbounded growth
- **Self-monitoring** — Heartbeats make agent health visible. Missing heartbeats trigger alerts.
- **Debuggable** — Every loop cycle is a discrete event with logged inputs, actions, and outputs

### Negative Consequences / Trade-offs

- **Latency** — An agent on a 15-minute loop may take up to 15 minutes to notice something new. Watchers mitigate this for time-sensitive triggers.
- **One action per loop** — High-volume situations (50 new leads) take many loop cycles to process. Acceptable for this business volume.
- **Memory is imperfect** — Summarization loses detail. Important nuances may be pruned. High-importance memories are preserved but the system can't keep everything.
- **LLM cost for assessment** — The Assess phase may use a Tier 1 call each cycle. At 5-minute intervals, that's 288 calls/day per agent. At ~$0.001/call, this is ~$0.29/day — acceptable.

### Resource Impact

- Development effort: HIGH
- Ongoing maintenance: MEDIUM (memory pruning thresholds may need tuning)
- Infrastructure cost: LOW (LLM cost for assessment calls is negligible)

---

## Alternatives Considered

### Alternative 1: Pure Event-Driven (No Agent Loop)

- Agents only act when triggered by watchers or webhooks. No periodic survey.
- Why rejected: Loses the "employee awareness" behavior. Agents can't notice patterns, stale tasks, or emerging issues. The system becomes purely reactive.

### Alternative 2: Persistent Agent Processes

- Long-running processes that maintain state in memory, wake on events
- Why rejected: Fragile on PaaS (Heroku restarts dynos). Complex process management. State lost on crash. The job-based approach is simpler and more resilient.

### Alternative 3: No Agent Memory (Stateless Loops)

- Each loop iteration only looks at current database state, no memory
- Why rejected: Agents can't learn, notice patterns, or maintain context about ongoing situations. Each loop is amnesiac. Memory is what makes agents useful beyond simple cron jobs.

### Alternative 4: Multiple Actions Per Loop

- Process all pending items in a single loop iteration
- Why rejected: Unpredictable execution time. A loop processing 50 items could run for minutes, conflicting with the next scheduled iteration. One action per loop is predictable and debuggable.

---

## Implementation

### Phase 1: AgentLoopJob Core

- Job accepts agent_slug
- Implement Survey phase (load tasks, check watchers, load memories)
- Implement Prioritize phase (rank work items)
- Implement Execute phase (create task or advance existing)
- Implement Report phase (Slack post, heartbeat)

### Phase 2: Memory System

- Memory creation during Report phase
- Memory loading for prompt building (importance + recency + task-relation)
- Token budget enforcement (truncate lowest importance first)

### Phase 3: MemoryMaintenanceJob

- Expired memory deletion
- Old memory summarization (Tier 1 LLM call)
- Per-agent memory cap enforcement
- Pruning stats logging

### Phase 4: Health Monitoring

- Heartbeat posting to #ops-log
- Missing heartbeat detection in DailySummaryJob
- Alert posting to #escalations

### Testing Strategy

- Unit tests: Survey phase loads correct data
- Unit tests: Prioritization ranks correctly
- Unit tests: One-action-per-loop constraint
- Unit tests: Memory loading respects importance and token budget
- Integration tests: Full loop cycle with mocked services
- Integration tests: Memory pruning and summarization
- Fixtures: Agents with memories at various importance levels, tasks at various statuses

---

## Related ADRs

- [ADR 01] Foundation Architecture — Agent-as-job pattern
- [ADR 02] Data Model — Agent, AgentMemory, Watcher schemas
- [ADR 03] 4-Tier LLM — Assessment calls during loop
- [ADR 04] SOP Execution Engine — TaskWorkerJob enqueued by agent loop
- [ADR 06] Slack Integration — Heartbeats and reporting
- [ADR 07] Observability — Loop cycle logging
