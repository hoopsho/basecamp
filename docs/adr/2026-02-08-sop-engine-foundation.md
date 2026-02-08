# ADR 01: SOP Engine Foundation Architecture

**ADR ID:** 2026-02-01
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FOUNDATION

Eighty Eight Services LLC (dba Snowmass) is a small Twin Cities lawn care / snow removal company with zero documented processes, no CRM, and no back-office software. The co-owner (Chris) handles all administrative operations manually. The fertilizer/weed control sales window opens mid-February 2026, creating an urgent need for automated lead response and customer reactivation.

We need a system that:
- Defines repeatable business processes (SOPs) as structured data
- Executes them automatically via background jobs
- Uses AI (Claude API) for classification, drafting, and decision-making
- Keeps costs low via tiered model usage (Haiku -> Sonnet -> Opus)
- Uses Slack as the operational communication hub (approvals, notifications, agent coordination)
- Provides an admin interface for SOP management, monitoring, and configuration
- Integrates with an external CRM for customer data (does NOT own customer data)
- Provides a full audit trail of every action

---

## Decision

**Decision:** We will build a full-stack Rails 8 application using PostgreSQL, Solid Queue, Anthropic Claude API (4-tier), Slack for operational communication, and an admin web interface for system management.

### Key Architectural Decisions

1. **Full-stack Rails 8** — Admin views with Tailwind 4, Stimulus, Turbo Frames/Streams, Importmaps. Dark mode. Mobile-first. No Node.js.
2. **Rails 8 native authentication** — No Devise. Pundit for authorization.
3. **Solid Queue** for all background processing — Recurring agent loops, watchers, and task workers. No Redis, no Sidekiq.
4. **PostgreSQL** as the single data store — Application data, job queue (via Solid Queue), and agent memory.
5. **4-tier LLM system** — Tier 0 (no LLM / pure Ruby), Tier 1 (Haiku), Tier 2 (Sonnet), Tier 3 (Opus / escalation only). Automatic confidence-based escalation.
6. **Agents as jobs, not processes** — Agents are role definitions in the database. AgentLoopJob runs on a schedule, surveys the domain, executes work, and exits. No long-running processes.
7. **SOP -> Steps -> Tasks -> TaskEvents** — SOPs define processes, Steps define individual actions, Tasks are running instances, TaskEvents are the audit log.
8. **UUID primary keys** on all tables.
9. **No customer data** — The SOP Engine does NOT store customers. A CrmService wraps the external CRM API. Task.context carries customer references for the duration of a task.
10. **Two interfaces, two purposes:**
    - **Slack** = Operations (approvals, notifications, agent-to-human and agent-to-agent communication)
    - **Admin UI** = Configuration & Monitoring (SOP builder, task monitor, dashboard, agent management)
11. **Human-in-the-loop by default** — All customer-facing actions require Slack approval initially. Autonomy expands as trust builds.
12. **Amazon SES** for transactional email.

### 8-Table Schema

| Table | Purpose |
|-------|---------|
| agents | AI worker role definitions |
| sops | Standard Operating Procedure definitions |
| steps | Individual actions within an SOP |
| tasks | Running instances of SOPs |
| task_events | Audit log of everything that happens |
| watchers | Recurring trigger condition checks |
| agent_memories | Persistent working memory for agents |
| credentials | Encrypted service credentials |

---

## Consequences

### Positive Consequences
- **Single-stack simplicity** — PostgreSQL + Rails + Solid Queue. No Redis, no message broker, no separate frontend framework.
- **Full audit trail** — Every LLM call, email, and decision logged to TaskEvents with token counts and confidence scores.
- **Cost-controlled AI** — 80%+ of operations at Tier 0 (free) or Tier 1 (pennies). Only edge cases escalate.
- **Slack-native operations** — Zero onboarding friction for day-to-day operations. Chris works where he already is.
- **Admin UI for management** — SOP definition, monitoring, and configuration through proper forms and dashboards, not console commands.
- **Clean data boundary** — SOP Engine orchestrates processes. CRM owns customer data. No data duplication or sync issues.
- **Process-first** — SOPs are debuggable and auditable. Trace any outcome to a specific step.
- **Generalizable** — The SOP framework could serve any small service business.

### Negative Consequences / Trade-offs
- **CRM dependency** — Agents cannot operate on customer data if the CRM is unreachable. Tasks pause and retry.
- **Solid Queue maturity** — Newer than Sidekiq/GoodJob. Less community tooling, fewer monitoring options.
- **Slack dependency** — If Slack is down, the human-in-the-loop approval path is blocked. Tasks queue but don't progress past approval steps.
- **Single-tenant** — Built for one company. Multi-tenant would require significant refactoring.
- **Admin UI adds development scope** — More code to build and maintain than a pure API app.

### Resource Impact
- Development effort: HIGH (full system build from scratch, including admin UI)
- Ongoing maintenance: MEDIUM (SOPs may need tuning, agent memories need pruning)
- Infrastructure cost: LOW (~$55-110/month — Heroku dynos + Anthropic API + SES)

---

## Alternatives Considered

### Alternative 1: API-Only Rails (Original SPEC Design)
- No views, Slack as the only interface, everything managed via seed data and console
- Why rejected: SOPs are too complex to define via seed files. Chris needs to see, edit, and approve SOPs before agents execute them. Task monitoring through Slack alone is insufficient for debugging. Configuration changes shouldn't require a deploy.
- Reconsider if: Admin overhead becomes a maintenance burden

### Alternative 2: Off-the-Shelf Field Service Software (Jobber, ServiceTitan)
- Pre-built CRM, scheduling, invoicing, and basic automation
- Why rejected: Expensive ($50-200+/month), rigid workflows, no AI capabilities, designed for larger operations
- Reconsider if: Snowmass grows to 5+ employees and needs scheduling/dispatch

### Alternative 3: No-Code Automation (Zapier + ChatGPT + Google Sheets)
- Quick to set up, no coding required
- Why rejected: Fragile, no unified audit trail, no confidence-based escalation, hard to debug, costly at volume
- Reconsider if: The Rails app proves too complex to maintain

### Alternative 4: Sidekiq Instead of Solid Queue
- More mature, better monitoring tools, larger community
- Why rejected: Requires Redis as additional dependency. Solid Queue runs in PostgreSQL. Rails 8 default. Simplicity wins.
- Reconsider if: Solid Queue causes production issues

### Alternative 5: Store Customer Data Locally
- Customers table in the SOP Engine database, CSV import
- Why rejected: Duplicates data that belongs in the CRM. Creates sync problems. The SOP Engine is a process orchestrator, not a data store.
- Reconsider if: CRM integration proves unreliable and local caching is needed

---

## Implementation

See ADRs #02-#10 for detailed implementation decisions.

### Phase 1: Core Infrastructure
- Scaffold Rails 8 app with PostgreSQL, Solid Queue, Tailwind 4, Importmaps
- Create all migrations (8 tables)
- Build model layer
- Build service layer (LlmService, SlackService, EmailService, CrmService, CredentialService)

### Phase 2: Execution Engine
- TaskWorkerJob, WatcherJob, AgentLoopJob
- Supporting jobs (HumanResponseJob, MemoryMaintenanceJob, DailySummaryJob)
- Configure recurring.yml

### Phase 3: Admin Interface
- Rails 8 authentication
- SOP builder/editor
- Task monitor
- Dashboard
- Agent management

### Phase 4: SOPs & Integration
- Seed data (agents, SOPs with steps)
- Wire Slack bot (channels, webhooks, interactive components)
- Wire CRM integration
- Implement SOP 1 (Past Customer Reactivation) end-to-end
- Implement SOP 2 (New Lead Response) end-to-end

### Phase 5: Deploy & Validate
- Heroku deployment
- End-to-end testing
- Go live

### Risks & Mitigations
| Risk | Severity | Mitigation |
|------|----------|-----------|
| CRM not ready when SOP Engine is | HIGH | Design CrmService with interface contract now. Mock responses for development/testing. |
| Haiku classification accuracy too low | MEDIUM | Test with 50 real emails before go-live. Escalation chain catches errors. |
| Slack rate limits during bulk operations | LOW | Batch messages. Queue delays between posts. |
| Solid Queue failures in production | MEDIUM | TaskEvents log all failures. #escalations channel for errors. |
| LLM costs higher than expected | LOW | Monitor via TaskEvents. Set budget alerts. |

### Testing Strategy
- Unit tests: Models, services (Minitest with fixtures)
- Integration tests: Job execution flows, SOP step chains
- System tests: Admin UI flows (SOP creation, task monitoring)
- Deployment validation: Staging environment, test SOPs against mock CRM data

---

## Decisions Locked

- **Email provider:** Amazon SES
- **Customer data:** External CRM (TBD). SOP Engine accesses via CrmService API.
- **Slack workspace:** Existing. Channels and bot integration created during implementation.
- **Heroku:** Existing account. Chris provisions infrastructure as needed.

---

## Related ADRs

| ADR | Title |
|-----|-------|
| 02 | Data Model & Schema Design |
| 03 | 4-Tier LLM Service |
| 04 | SOP Execution Engine |
| 05 | Agent Loop System |
| 06 | Slack Integration |
| 07 | Observability & Cost Tracking |
| 08 | Credential Management & Webhook Security |
| 09 | Admin Interface & Authentication |
| 10 | CRM Integration |
