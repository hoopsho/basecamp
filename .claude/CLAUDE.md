# Basecamp

Rails 8 application scaffolded with full conventions.

## Tech Stack
- Rails 8 + PostgreSQL + Hotwire (Turbo + Stimulus) + Tailwind CSS 4
- Minitest + Fixtures (NOT RSpec, NOT FactoryBot)
- Auth: Rails 8 native (NOT Devise)
- Pundit + Pagy + Ransack + Bullet + letter_opener
- Background Jobs: Solid Queue | Cache: Solid Cache | WebSockets: Solid Cable
- Deployment: Heroku with PostgreSQL addon

## Database
- UUID primary keys on all tables
- Always index foreign keys
- Always use `references` with `foreign_key: true`

## Domain
SOP Engine for a lawn care/snow removal company (Eighty Eight Services LLC, dba Snowmass) in the Twin Cities, MN. Automates back-office operations by defining Standard Operating Procedures (SOPs) and executing them via background jobs with AI-powered decision making.

Key entities:
- **SOP** (Standard Operating Procedure) - Business process definitions
- **Step** - Individual steps within an SOP
- **Task** - Execution instances of SOPs
- **Agent** - Background job workers that execute tasks
- **Watcher** - Recurring jobs that monitor conditions

## API
- Slack webhook endpoints for bot integration
- Email webhook endpoints for processing inbound emails

## Project-Specific Notes
- Two interfaces: Slack (operations) + Admin UI (management)
- 4-tier LLM system: Tier 0 (no LLM), Tier 1 (Haiku), Tier 2 (Sonnet), Tier 3 (Opus)
- All customer-facing actions start with human approval via Slack
- Task.context (jsonb) is the data pipeline between steps
- Every LLM call and external action must be logged to TaskEvents
