# ADR 09: Admin Interface & Authentication

**ADR ID:** 2026-02-09
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES

The original SPEC called for an API-only Rails app with Slack as the sole interface. After further analysis (see ADR #01), we determined that several management tasks require a proper web interface:

- **SOP building and editing** — SOPs have complex nested structures (steps with JSON configs, prompt templates, branching logic, tier assignments). Defining these via seed files or Rails console is error-prone and non-reviewable.
- **Task monitoring** — Slack is great for push notifications, but pull queries ("show me all failed tasks this week") need a filterable, sortable table view.
- **Dashboard metrics** — Aggregated views of costs, throughput, agent health, and campaign performance.
- **Agent management** — Enable/disable agents, adjust intervals, view memories. Quick actions need to be one click, not a console command.

Slack remains the operational hub (approvals, notifications, real-time communication). The admin UI is the configuration and monitoring plane.

---

## Decision

**Decision:** We will build an admin web interface using Rails 8 native authentication, Pundit for authorization, Tailwind 4 for styling (with dark mode), Turbo Frames/Streams for interactivity, and Stimulus controllers for client-side behavior. Importmaps for JavaScript — no Node.js.

### Authentication

Rails 8 ships with a built-in authentication generator (`rails generate authentication`). We will use this directly:

- **Session-based auth** — Cookie-based sessions, no JWT
- **Password authentication** — bcrypt via `has_secure_password`
- **Password reset** — Email-based reset flow via SES
- **Session management** — Configurable session timeout (default: 8 hours)

No Devise. No OAuth for admin login. Simple email + password.

Initial users: Chris (admin) and Steven (admin). Created via seeds or Rails console. No self-registration.

### Authorization

Pundit for role-based access:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password
  enum :role, [:admin, :viewer]
end

# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def admin?
    user.role == 'admin'
  end
end
```

Roles for v0.1:

- **admin** — Full access: create/edit/delete SOPs, manage agents, view all data
- **viewer** — Read-only: view dashboard, task history, agent status. Cannot modify SOPs or agent settings.

Start simple. Two users, two roles. Expand if needed.

### Admin UI Sections

#### 1. Dashboard (Home)

The landing page after login. Four panels (see ADR #07 for metric details):

- **Operations** — Active tasks by agent/status, completions today, tasks waiting on human
- **Performance** — Lead response time, SOP success rate, human response time
- **Cost** — Today's LLM cost by tier, month-to-date, trend sparkline
- **Campaigns** — Reactivation stats, lead pipeline, collections summary

Built with Turbo Frames for auto-refresh (poll every 60 seconds or use Turbo Streams via Solid Cable).

#### 2. SOP Builder / Editor

The most complex admin view. Allows Chris to:

- **List all SOPs** — Table with name, agent, status, step count, last triggered
- **View SOP detail** — Full step list with config summaries
- **Edit SOP** — Update name, description, trigger type, status, max_tier
- **Edit Steps** — Reorder, add, remove, edit individual steps
- **Step editor** — Form for step_type, config (JSON editor or structured form), tier settings, branching (on_success, on_failure, on_uncertain)
- **Preview prompt** — Show the assembled prompt template with sample data interpolated
- **Enable/disable** — Toggle SOP status (draft -> active, active -> disabled)

Step editing UI:

- Turbo Frame for each step (inline editing)
- Drag-and-drop reordering via Stimulus controller (sortable)
- Step type selector changes the config form dynamically
- JSON config editor for power users, structured form for common fields

SOP status flow: `draft` -> `active` -> `disabled` (reversible)

#### 3. Task Monitor

- **Task list** — Filterable by agent, SOP, status, date range. Paginated (Pagy).
- **Task detail** — Full TaskEvent timeline (see ADR #07 debugging section). Shows task.context at each step.
- **Bulk actions** — Retry failed tasks, cancel pending tasks (admin only)
- **Real-time updates** — Turbo Streams for live task status changes

Filters:

- Status: pending, in_progress, waiting_on_human, waiting_on_timer, completed, failed, escalated
- Agent: dropdown of all agents
- SOP: dropdown of all SOPs
- Date: today, this week, this month, custom range

#### 4. Agent Management

- **Agent list** — Name, status, last heartbeat, active tasks, loop interval
- **Agent detail** — Current memories, active tasks, recent events, configuration
- **Quick actions** — Pause/resume agent (one click), adjust loop interval
- **Memory viewer** — List of agent memories with importance, type, expiration. Manual prune option.

#### 5. Credential Management

- **List credentials** — Service name, type, status, expiration
- **Status indicators** — Green (active), yellow (expiring soon), red (expired/revoked)
- **Refresh OAuth** — Trigger manual refresh for OAuth tokens
- **No credential values shown** — The UI never displays decrypted credential values. Only status and metadata.

### Frontend Stack

| Technology        | Purpose                                                                        |
| ----------------- | ------------------------------------------------------------------------------ |
| **Tailwind 4**    | Utility-first CSS, dark mode via `dark:` variant                               |
| **Stimulus**      | Client-side interactivity (sortable lists, JSON editor, toggles, auto-refresh) |
| **Turbo Drive**   | SPA-like navigation without full page reloads                                  |
| **Turbo Frames**  | Scoped updates (inline step editing, filter changes, live task status)         |
| **Turbo Streams** | Real-time updates (task status changes, dashboard metrics, new events)         |
| **Importmaps**    | JavaScript delivery — no Node.js, no npm, no bundler                           |
| **Heroicons**     | All iconography                                                                |

### Dark Mode

Three-way toggle: dark / light / system preference.

- User preference stored in database (`users.theme_preference`)
- `dark:` Tailwind variant for all styling
- Stimulus controller handles toggle and persists preference
- Default: system preference

### Responsive Design

Mobile-first with Tailwind responsive classes. The admin UI should be usable on a phone for:

- Dashboard glance
- Task status checks
- Agent pause/resume
- Approval review (though this mainly happens in Slack)

Desktop for:

- SOP builder (needs screen real estate)
- Task event timeline (detailed view)
- Cost analysis

### Layout

```
┌─────────────────────────────────────────────┐
│  [Logo] SOP Engine    [Dark Mode] [User ▼]  │
├──────────┬──────────────────────────────────┤
│          │                                   │
│ Dashboard│   [Main Content Area]             │
│ SOPs     │                                   │
│ Tasks    │   Turbo Frame: page_content       │
│ Agents   │                                   │
│ Creds    │                                   │
│          │                                   │
│          │                                   │
└──────────┴──────────────────────────────────┘
```

Sidebar navigation on desktop, hamburger menu on mobile.

### Routes

```ruby
# config/routes.rb

# Authentication (Rails 8 generated)
resource :session
resource :password_reset
resource :password

# Admin namespace
namespace :admin do
  root to: 'dashboards#show'

  resources :sops do
    resources :steps, shallow: true
  end

  resources :tasks, only: [:index, :show] do
    member do
      post :retry
      post :cancel
    end
  end

  resources :agents, only: [:index, :show, :edit, :update] do
    member do
      post :pause
      post :resume
    end
    resources :agent_memories, only: [:index, :destroy], shallow: true
  end

  resources :credentials, only: [:index, :show] do
    member do
      post :refresh
    end
  end

  resource :dashboard, only: [:show]
end
```

All routes are RESTful. Custom actions (pause, resume, retry, cancel) are member routes, not non-RESTful actions. These are acceptable because they represent state transitions on the resource, not separate concerns.

### Stimulus Controllers

Following the reuse-first philosophy from CLAUDE.md:

| Controller        | Behavior                           | Used By                                 |
| ----------------- | ---------------------------------- | --------------------------------------- |
| `toggle`          | Show/hide elements, toggle classes | Sidebar, step details, memory expansion |
| `sortable`        | Drag-and-drop reordering           | Step reordering in SOP editor           |
| `auto-refresh`    | Poll for updates on an interval    | Dashboard panels, task list             |
| `form-validation` | Client-side validation             | SOP editor, step editor                 |
| `clipboard`       | Copy to clipboard                  | Task IDs, API responses                 |
| `theme`           | Dark/light/system mode toggle      | Global header                           |
| `json-editor`     | Structured JSON editing            | Step config editor                      |
| `filter`          | Dynamic filtering with Turbo Frame | Task list, agent list                   |

Generic, behavioral controllers. Not feature-specific. Reusable across the app.

---

## Consequences

### Positive Consequences

- **SOP quality control** — Chris reviews and approves SOPs visually before agents execute them. No blind trust in seed data.
- **Debugging without console** — Task timelines, agent memories, and metrics are all accessible through the UI.
- **Quick responses** — Pause an agent with one click when something goes wrong. No deploy needed.
- **Cost visibility** — Dashboard makes LLM spending visible at a glance.
- **Familiar stack** — Standard Rails conventions (Tailwind, Stimulus, Turbo) per CLAUDE.md. No surprises.

### Negative Consequences / Trade-offs

- **Development scope** — Admin UI is significant additional code. 5 major views, Stimulus controllers, Turbo integration.
- **Two interfaces to maintain** — Slack for operations, web for management. Features must be correctly distributed.
- **Auth complexity** — Authentication, authorization, password reset, session management — all need to work correctly.
- **Testing surface** — System tests needed for UI flows in addition to unit and integration tests.

### Resource Impact

- Development effort: HIGH (5 major view sections, authentication, authorization)
- Ongoing maintenance: MEDIUM (UI may need updates as features evolve)
- Infrastructure cost: NONE (served by the same Rails app)

---

## Alternatives Considered

### Alternative 1: No Admin UI (Original SPEC)

- Slack only, manage SOPs via seed files and Rails console
- Why rejected: SOPs are too complex for seed files. Monitoring via Slack alone is insufficient. Configuration changes shouldn't require a deploy. See ADR #01.

### Alternative 2: Separate Admin App (React/Vue SPA)

- Separate frontend app consuming the Rails API
- Why rejected: Two apps to deploy and maintain. CLAUDE.md forbids Node.js in the Rails stack. Hotwire (Turbo + Stimulus) handles every admin UI need without a separate frontend framework.

### Alternative 3: Rails Admin Gem (Administrate, ActiveAdmin)

- Auto-generated admin interface from model definitions
- Why rejected: Too generic. The SOP builder needs custom UX (step reordering, prompt preview, config forms). Task timeline needs a custom view. Dashboard needs custom panels. We'd spend more time fighting the gem than building from scratch.

### Alternative 4: Retool / Internal Tool Builder

- Low-code admin panel builder connected to the database
- Why rejected: External dependency, monthly cost, can't customize deeply enough (SOP step editor, task timeline). The Rails views are more maintainable long-term.

---

## Implementation

### Phase 1: Authentication & Layout

- Run `rails generate authentication`
- Add Pundit with User roles
- Build admin layout (sidebar, header, dark mode toggle)
- Create User seeds (Chris, Steven)

### Phase 2: Dashboard

- Build dashboard controller and view
- Implement 4 panels with aggregation queries
- Add auto-refresh via Stimulus/Turbo

### Phase 3: SOP Builder

- SOP list, show, new, edit views
- Step management (add, edit, reorder, remove)
- Step config forms (per step_type)
- Prompt preview

### Phase 4: Task Monitor

- Task list with filters and pagination (Pagy)
- Task detail with event timeline
- Bulk actions (retry, cancel)
- Real-time status updates via Turbo Streams

### Phase 5: Agent & Credential Management

- Agent list and detail views
- Pause/resume actions
- Memory viewer
- Credential status display

### Testing Strategy

- System tests: Authentication flow (login, logout, password reset)
- System tests: SOP creation and step management
- System tests: Task list filtering and detail view
- Unit tests: Pundit policies
- Unit tests: Dashboard aggregation queries
- Controller tests: Authorization (viewer can't edit SOPs)
- Fixtures: Users with different roles, SOPs with steps, tasks with events

---

## Related ADRs

- [ADR 01] Foundation Architecture — Full-stack Rails, not API-only
- [ADR 04] SOP Execution Engine — SOPs and steps the builder creates
- [ADR 06] Slack Integration — Complementary operational interface
- [ADR 07] Observability — Dashboard metrics and task timeline
- [ADR 08] Credential Management — Credential status display
