# ADR 06: Slack Integration

**ADR ID:** 2026-02-06
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES

Slack is the operational hub of the SOP Engine. While the admin UI handles configuration and monitoring (see ADR #09), Slack handles all real-time communication:

- **Agent -> Human:** Notifications, approval requests, escalations, status updates
- **Human -> Agent:** Decisions, commands, button responses
- **Agent -> Agent:** Cross-agent coordination via shared channels
- **System -> Human:** Heartbeats, daily summaries, error alerts

Chris lives in Slack. The system needs to meet him there — not in a dashboard, not in email. When an agent needs a decision, it posts to Slack with interactive buttons. When a lead comes in, Slack shows it immediately. When something breaks, Slack alerts.

The admin UI complements this by providing the management plane (building SOPs, reviewing task history, checking costs). But the operational loop runs through Slack.

---

## Decision

**Decision:** We will build a comprehensive Slack integration using a Slack Bot with interactive components (buttons, menus), organized channels for domain separation, threaded conversations for task tracking, and webhook-based response handling for human-in-the-loop workflows.

### Channel Architecture

| Channel           | Purpose                                                              | Who Posts                 | Notification Level         |
| ----------------- | -------------------------------------------------------------------- | ------------------------- | -------------------------- |
| `#leads-incoming` | New inquiries, quote requests, lead status updates                   | Lead Response Agent       | All messages               |
| `#billing`        | Invoices, payments, overdue accounts, dunning updates                | AR Agent                  | All messages               |
| `#scheduling`     | Daily routes, weather changes, crew updates                          | Scheduling Agent (future) | All messages               |
| `#marketing`      | Campaign status, review requests, social posts, reactivation updates | Marketing Agent           | All messages               |
| `#ops-log`        | Heartbeats from all agents, system events, daily summaries           | All Agents                | Muted (check as needed)    |
| `#escalations`    | Human decisions needed, errors, unusual situations                   | All Agents (urgent)       | All messages + mobile push |

Design principles:

- **One primary channel per agent domain.** Agents post to their domain channel for routine updates.
- **#ops-log is the system heartbeat.** Every agent posts here every loop cycle. High volume, low urgency. Mute it but check if something feels off.
- **#escalations is sacred.** Only posts here when a human decision is genuinely needed or something is broken. If this channel is noisy, something is wrong with the escalation thresholds.

### Message Patterns

#### Notification (Agent -> Human, informational)

```
[#marketing] Marketing Agent
Reactivation campaign batch 1 complete:
  - Emails sent: 23
  - Delivery confirmed: 22
  - Bounced: 1 (mike.johnson@old-email.com — flagged in CRM)
Next batch scheduled for Thursday.
Task #247 | View in admin
```

No response expected. Chris reads at his convenience.

#### Approval Request (Agent -> Human, blocking)

```
[#leads-incoming] Lead Response Agent needs approval on Task #312:

New lead from Jane Smith (Eagan, MN)
Requested: Fertilizer & weed control quote
Source: Google search

Proposed response:
> Hi Jane, thanks for reaching out to Snowmass! I'd be happy to put
> together a fertilizer and weed control quote for your property. Could
> you confirm your address so I can look up your lot size? We typically
> have estimates ready within 24 hours.

[✅ Send as-is]  [✏️ Edit first]  [❌ Don't send]
```

Task pauses until Chris taps a button. The button click fires a webhook.

#### Escalation (Agent -> Human, urgent)

```
[#escalations] ⚠️ AR Agent needs help on Task #456:

Customer Mike Johnson ($450 overdue, 45 days) responded:
"I already paid this. Check your records."

I checked and found no payment matching this amount in the last 60 days.
Confidence: 0.85 that payment was not received.

Recommended action: Send payment history showing balance due.

[📄 Send payment history]  [⏸️ Pause and investigate]  [📞 Flag for phone call]
```

#### Heartbeat (Agent -> System, routine)

```
[#ops-log] 🤖 Lead Response Agent | Loop 2026-02-15 10:05:03
  Active tasks: 3 | Pending: 1 | Completed today: 7
  Action: Created Task #413 (new lead from website form)
  Memory: 24 active memories (12 high-importance)
  Next run: 5 min
```

#### Daily Summary (System -> Human)

```
[#ops-log] 📊 Daily Summary — February 15, 2026

Lead Response Agent:
  New leads: 4 | Responded: 4 (avg 3.2 min) | Quotes sent: 2

Marketing Agent:
  Reactivation emails: 23 sent | 3 responses received
  Review requests: 2 sent | 1 review posted

AR Agent:
  Reminders sent: 5 | Payments received: 2 ($380)
  Overdue 30+: 3 accounts ($1,240 total)

LLM Costs: $1.47 (Haiku: $0.34, Sonnet: $0.98, Opus: $0.15)
Total tasks completed: 14 | Failed: 0 | Waiting on human: 2
```

### Interactive Components

#### Buttons

Used for approval/decision flows. Each button includes:

- `action_id`: Maps to a handler (e.g., `approve_email`, `reject_email`, `edit_email`)
- `value`: JSON payload with task_id, step_position, and the decision
- `style`: `primary` (green) for recommended action, `danger` (red) for destructive actions

#### Menus (Select)

Used when there are more than 3 options:

- Dropdown select for choosing from a list
- Value includes the selection and task context

### Thread Management

All updates for a single task are grouped in a Slack thread:

1. When a task is created, the first message is posted to the appropriate channel. The `message_ts` is stored in `task.slack_thread_ts`.
2. All subsequent updates for that task are posted as replies to that thread.
3. This keeps channels clean — each task is one top-level message with a thread of updates.

```ruby
# First message (creates thread)
response = SlackService.post(
  channel: agent.slack_channel,
  text: "New lead from Jane Smith (Task #312)"
)
task.update!(slack_thread_ts: response[:ts])

# Subsequent updates (in thread)
SlackService.post(
  channel: agent.slack_channel,
  text: "Email classified as new_lead (confidence: 0.94)",
  thread_ts: task.slack_thread_ts
)
```

### Webhook Flow (Human Response -> System)

```
1. Human clicks button in Slack
2. Slack sends POST to /api/v1/webhooks/slack (interactive payload)
3. Rails controller verifies Slack signature
4. Controller extracts: action_id, value (JSON), user_id, message_ts
5. Enqueues HumanResponseJob(task_id:, response_data:)
6. Returns 200 OK to Slack immediately (< 3 seconds)
7. HumanResponseJob:
   a. Loads task
   b. Merges response into task.context
   c. Updates task.status -> in_progress
   d. Posts acknowledgment to thread ("Got it — sending email now")
   e. Enqueues TaskWorkerJob for next step
```

### Slash Commands

Optional convenience commands for Chris:

| Command                | Action                                          |
| ---------------------- | ----------------------------------------------- |
| `/sop list`            | List all active SOPs with status                |
| `/sop run <slug>`      | Manually trigger an SOP                         |
| `/sop status`          | Quick health check (active tasks, agent status) |
| `/agent pause <slug>`  | Pause an agent's loop                           |
| `/agent resume <slug>` | Resume a paused agent                           |

These are shortcuts — everything they do is also available in the admin UI.

### SlackService Interface

```ruby
class SlackService
  # Post a message to a channel
  def self.post(channel:, text:, blocks: nil, thread_ts: nil)
    # Returns: { ok: true, ts: "message_ts", channel: "channel_id" }
  end

  # Post a message with interactive buttons
  def self.ask(channel:, text:, actions:, thread_ts: nil)
    # actions: [{ text: "Send", action_id: "approve", value: {}, style: "primary" }]
    # Returns: { ok: true, ts: "message_ts" }
  end

  # Update an existing message (e.g., replace buttons with "Approved ✓")
  def self.update(channel:, ts:, text:, blocks: nil)
    # Returns: { ok: true }
  end

  # Verify incoming webhook signature
  def self.verify_signature(request)
    # Returns: true/false
  end
end
```

### Slack Bot Scopes Required

- `chat:write` — Post messages to channels
- `chat:write.customize` — Post with custom username/icon per agent
- `reactions:read` — Detect emoji reactions (future)
- `commands` — Slash commands
- `channels:history` — Read channel messages for context
- `channels:join` — Join channels programmatically
- `users:read` — Identify who clicked a button

Event subscriptions:

- `message.channels` — For monitoring (future)

Interactive components:

- Request URL: `https://app-domain.herokuapp.com/api/v1/webhooks/slack`

### Rate Limiting

Slack API rate limits: ~1 message per second per channel.

Mitigation:

- Batch operations (e.g., reactivation campaign) spread messages over time
- Use threads to keep channel-level message count low
- Queue Slack posts with small delays between them (SlackService handles this internally)
- Bulk operations post a summary message, not individual messages per item

---

## Consequences

### Positive Consequences

- **Zero onboarding** — Chris already uses Slack. No new tool to learn.
- **Real-time awareness** — Important events surface immediately. Approvals are one tap.
- **Thread organization** — Each task is a self-contained thread. Easy to find history.
- **Mobile-friendly** — Slack mobile app means Chris can approve emails from anywhere.
- **Agent personality** — Custom usernames/icons per agent make the system feel like a team.
- **Bidirectional** — Not just push notifications. Chris can command, approve, and override.

### Negative Consequences / Trade-offs

- **Slack dependency** — If Slack is down, approval workflows stall. Tasks queue but don't progress.
- **Message noise** — Without careful channel design, Slack becomes overwhelming. #ops-log must be muted.
- **Button limitations** — Slack buttons are simple. Complex decisions may need the admin UI.
- **3-second webhook deadline** — Slack expects a response within 3 seconds. All processing must be async (enqueue job, return 200).
- **No offline access** — Slack history is searchable but not the same as a proper audit UI. The admin task monitor complements this.

### Resource Impact

- Development effort: MEDIUM
- Ongoing maintenance: LOW (Slack API is stable)
- Infrastructure cost: NONE (Slack free tier or existing paid plan)

---

## Alternatives Considered

### Alternative 1: Email-Only Communication

- Send all notifications and approvals via email
- Why rejected: Email is slow, doesn't support interactive buttons natively, and Chris checks Slack more often. Email is a communication channel the system uses for customers, not for operator interaction.

### Alternative 2: SMS for Approvals

- Send approval requests via SMS with reply codes
- Why rejected: Limited formatting, no threading, no interactive components. Good for customer communication (future), bad for system management.

### Alternative 3: Discord Instead of Slack

- Similar features, free for unlimited history
- Why rejected: Chris already uses Slack. Switching would add friction for zero benefit.

### Alternative 4: Admin UI Only (No Slack)

- Push all notifications and approvals to the web admin interface
- Why rejected: Requires Chris to check a dashboard. Push notifications (Slack) beat pull interfaces (dashboard) for time-sensitive approvals. The admin UI complements Slack for management tasks.

---

## Implementation

### Phase 1: SlackService Core

- Implement `post`, `ask`, `update` methods
- Implement webhook signature verification
- Configure Slack Bot with required scopes
- Create channels

### Phase 2: Webhook Handler

- Build `/api/v1/webhooks/slack` endpoint
- Parse interactive component payloads
- Enqueue HumanResponseJob
- Return 200 within 3 seconds

### Phase 3: Agent Integration

- Connect agent loop heartbeats to #ops-log
- Connect task step notifications to domain channels
- Implement thread management (slack_thread_ts)
- Build DailySummaryJob Slack output

### Phase 4: Slash Commands

- Register commands with Slack
- Build command endpoint
- Implement `/sop` and `/agent` command handlers

### Testing Strategy

- Unit tests: SlackService message formatting, signature verification
- Unit tests: Webhook payload parsing
- Integration tests: Full approval flow (post buttons -> webhook -> resume task)
- Integration tests: Thread management (first message creates thread, updates go to thread)
- Fixtures: Slack webhook payloads for different interaction types

---

## Related ADRs

- [ADR 01] Foundation Architecture — Slack as operational hub
- [ADR 04] SOP Execution Engine — slack_notify and slack_ask_human step types
- [ADR 05] Agent Loop System — Heartbeat posting and reporting
- [ADR 07] Observability — Daily summary format
- [ADR 08] Credential Management — Slack bot token storage and webhook secret verification
- [ADR 09] Admin Interface — Complementary management plane
