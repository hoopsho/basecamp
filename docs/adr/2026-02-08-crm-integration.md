# ADR 10: CRM Integration

**ADR ID:** 2026-02-10
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES | FOUNDATION

The SOP Engine needs customer data to execute its SOPs:

- **SOP 1 (Reactivation):** Query past fertilizer/weed control customers not yet signed for the current season
- **SOP 2 (Lead Response):** Create/update lead records when new inquiries arrive
- **SOP 3 (Quote Follow-Up):** Check if a customer has responded since a quote was sent
- **SOP 5 (Collections):** Query overdue invoices and customer contact info

The SOP Engine is a **process orchestrator**, not a CRM. Customer data belongs in a separate CRM system that is currently being built. The SOP Engine accesses customer data via API — it never stores it locally.

This creates a key architectural boundary: the SOP Engine depends on an external service for its most critical data. We need a clean integration pattern that handles this dependency gracefully.

---

## Decision

**Decision:** We will build a CrmService that wraps the external CRM API behind a consistent Ruby interface, with response caching for the duration of a task, mock support for development/testing, and graceful failure handling when the CRM is unreachable.

### Service Boundary

```
┌──────────────────┐         ┌──────────────────┐
│   SOP Engine     │         │   CRM (External)  │
│                  │  HTTP   │                    │
│  CrmService ────────────> │  REST API          │
│                  │  JSON   │                    │
│  task.context    │ <────── │  Customer data     │
│  (temporary)     │         │  (source of truth) │
└──────────────────┘         └──────────────────┘
```

Rules:

- **CRM is the source of truth** for all customer data
- **SOP Engine never persists customer data** in its own database
- **task.context carries customer references** for the duration of a task (IDs, names, emails cached temporarily)
- **CrmService is the only way to access customer data** — no direct database queries, no shared database

### CrmService Interface

```ruby
class CrmService
  # Query customers matching criteria
  def self.query(filters = {})
    # filters: { status: 'past', services: ['fertilizer'], not_signed_for_season: 2026 }
    # Returns: Array of customer hashes
    # [{ id: 'uuid', name: 'Jane Smith', email: 'jane@...', phone: '...',
    #    address: '...', services: [...], status: 'past', last_service_date: '...' }]
  end

  # Get a single customer by ID
  def self.find(customer_id)
    # Returns: Customer hash or nil
  end

  # Update a customer record
  def self.update(customer_id, attributes)
    # attributes: { status: 'active', notes: 'Re-signed for 2026 season' }
    # Returns: { success: true/false, customer: updated_hash }
  end

  # Create a new customer (from a new lead)
  def self.create(attributes)
    # attributes: { name: 'Jane Smith', email: 'jane@...', source: 'google', status: 'lead' }
    # Returns: { success: true/false, customer: new_hash, id: 'uuid' }
  end

  # Search customers (for fuzzy matching incoming emails to existing customers)
  def self.search(query)
    # query: 'jane smith' or 'jane@example.com'
    # Returns: Array of matching customer hashes
  end
end
```

### CRM API Contract

The CRM must expose these endpoints (to be implemented by the CRM project):

```
GET    /api/v1/customers          # List/filter customers
GET    /api/v1/customers/:id      # Get single customer
POST   /api/v1/customers          # Create customer
PATCH  /api/v1/customers/:id      # Update customer
GET    /api/v1/customers/search   # Fuzzy search
```

Query parameters for filtering:

- `status` — active, past, lead, cold
- `services` — filter by service type (fertilizer, mowing, snow_removal)
- `not_signed_for_season` — exclude customers already signed for a season year
- `last_service_before` — customers whose last service was before a date
- `city` — filter by city

Response format:

```json
{
  "customers": [
    {
      "id": "uuid",
      "name": "Jane Smith",
      "email": "jane@example.com",
      "phone": "612-555-1234",
      "address": "123 Elm St",
      "city": "Eagan",
      "state": "MN",
      "zip": "55122",
      "services": ["fertilizer", "weed_control"],
      "status": "past",
      "last_service_date": "2025-09-15",
      "notes": "Prefers email communication",
      "source": "referral",
      "created_at": "2024-03-10T..."
    }
  ],
  "meta": {
    "total": 47,
    "page": 1,
    "per_page": 25
  }
}
```

### Task Context Caching

When a task fetches customer data, it caches the relevant fields in task.context:

```ruby
# In a query step handler:
customer = CrmService.find(task.context['crm_customer_id'])
task.context.merge!(
  'customer_name' => customer['name'],
  'customer_email' => customer['email'],
  'customer_phone' => customer['phone'],
  'customer_city' => customer['city'],
  'customer_services' => customer['services'],
  'customer_last_service' => customer['last_service_date']
)
```

This cached data is used by subsequent steps (drafting emails, posting to Slack) without re-fetching from the CRM. The data is temporary — it lives only in the task's context for the duration of that task.

Convention: All customer data keys in task.context are prefixed with `customer_` for clarity.

### Failure Handling

| Scenario                             | Behavior                                                                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| CRM unreachable (timeout)            | Retry 3 times with exponential backoff (2s, 4s, 8s). If still unreachable, fail the step. Follow on_failure path.        |
| CRM returns 404 (customer not found) | Log warning. Set customer data to nil in context. Step can decide how to handle (skip, escalate).                        |
| CRM returns 500 (server error)       | Treat as unreachable. Retry, then fail.                                                                                  |
| CRM returns 401/403 (auth failure)   | Log error. Post to #escalations ("CRM authentication failed — check credentials"). Do not retry (auth won't fix itself). |
| CRM returns stale data               | Not detectable. Task works with whatever the CRM returns. CRM is the source of truth.                                    |
| CRM rate limited (429)               | Respect Retry-After header. Queue retries.                                                                               |

When the CRM is down, tasks that need customer data pause. Tasks that don't need customer data (e.g., memory maintenance, Slack notifications) continue normally.

### Development & Testing Without CRM

Since the CRM is still being built, we need to work without it:

#### Mock CRM for Development

```ruby
class CrmService
  def self.query(filters = {})
    if Rails.env.development? || Rails.env.test?
      MockCrmData.query(filters)
    else
      # Real API call
    end
  end
end

class MockCrmData
  CUSTOMERS = [
    { 'id' => 'mock-uuid-1', 'name' => 'Jane Smith', 'email' => 'jane@example.com',
      'city' => 'Eagan', 'services' => ['fertilizer', 'weed_control'],
      'status' => 'past', 'last_service_date' => '2025-09-15' },
    # ... more mock customers
  ].freeze

  def self.query(filters = {})
    results = CUSTOMERS.dup
    results.select! { |c| c['status'] == filters[:status] } if filters[:status]
    results.select! { |c| (c['services'] & Array(filters[:services])).any? } if filters[:services]
    results
  end
end
```

#### Test Fixtures

Minitest fixtures include mock CRM response data for consistent testing:

```yaml
# test/fixtures/crm_responses.yml
past_fertilizer_customers:
  response_body: '[{"id": "uuid-1", "name": "Jane Smith", ...}]'
  status_code: 200
```

### Authentication with CRM

CRM authentication depends on what the CRM implements:

- **API Key** — Simplest. Store in Rails encrypted credentials under `crm.api_key`.
- **OAuth** — Store tokens in Credential model with refresh support (see ADR #08).
- **Shared secret / HMAC** — Sign requests with a shared key.

For v0.1, assume API key authentication. Upgrade to OAuth if the CRM requires it.

```ruby
# In CrmService:
def self.headers
  {
    'Authorization' => "Bearer #{Rails.application.credentials.dig(:crm, :api_key)}",
    'Content-Type' => 'application/json',
    'Accept' => 'application/json'
  }
end
```

---

## Consequences

### Positive Consequences

- **Clean separation of concerns** — SOP Engine orchestrates processes. CRM owns customer data. No duplication.
- **Independent development** — SOP Engine and CRM can be built in parallel. Mock data unblocks development.
- **No sync issues** — Single source of truth (CRM). No stale local copies to manage.
- **CRM-agnostic** — CrmService wraps the API. If the CRM changes or is replaced, only CrmService needs updating.
- **Testable without CRM** — Mock data makes development and testing independent.

### Negative Consequences / Trade-offs

- **Runtime dependency** — If the CRM is down, customer-facing SOPs can't execute. Tasks pause.
- **Network latency** — Every customer data access is an HTTP call. Adds ~50-200ms per request.
- **No offline capability** — Can't process customers if the network connection to CRM is lost.
- **API contract coordination** — Both projects must agree on the API shape. Changes require coordination.
- **No referential integrity** — task.context stores customer IDs as data, not foreign keys. A deleted CRM customer won't cascade to SOP Engine tasks.

### Resource Impact

- Development effort: MEDIUM (service + mock data + error handling)
- Ongoing maintenance: LOW (API contract is stable once defined)
- Infrastructure cost: NONE (HTTP calls between Heroku apps are free)

---

## Alternatives Considered

### Alternative 1: Customers Table in SOP Engine (Original SPEC)

- Store customer data locally with CSV import
- Why rejected: Duplicates data, creates sync problems, blurs responsibility. The SOP Engine shouldn't own customer data.
- Reconsider if: CRM integration proves too unreliable for production

### Alternative 2: Shared Database

- Both SOP Engine and CRM read/write the same PostgreSQL database
- Why rejected: Tight coupling. Schema changes in one app can break the other. No clear data ownership. Database becomes a shared dependency. API boundaries are cleaner.
- Reconsider if: Latency of HTTP calls becomes a problem and both apps are on the same Heroku instance

### Alternative 3: Event-Driven Sync (Webhooks)

- CRM pushes customer updates to SOP Engine via webhooks. SOP Engine maintains a local cache.
- Why rejected: Adds complexity (webhook handling, cache invalidation, eventual consistency). Direct API calls are simpler and always return fresh data. The slight latency penalty is acceptable for this volume.
- Reconsider if: CRM query volume is high and latency matters

---

## Implementation

### Phase 1: CrmService with Mock Data

- Build CrmService with full interface (query, find, update, create, search)
- Implement MockCrmData for development and testing
- Toggle between mock and real via Rails environment

### Phase 2: Real API Integration

- When CRM API is ready, implement HTTP client in CrmService
- Configure authentication (API key initially)
- Error handling (retries, timeouts, auth failures)
- Log all CRM calls to TaskEvents

### Phase 3: Task Context Integration

- Wire CRM data into task.context in step handlers
- Ensure customer\_ prefix convention is followed
- Test full SOP execution with CRM data

### Testing Strategy

- Unit tests: CrmService.query with mock data returns correct results
- Unit tests: CrmService.query with filters works correctly
- Unit tests: Error handling (timeouts, 404s, 500s)
- Integration tests: Full SOP execution with mock CRM data
- Integration tests: Task.context carries customer data correctly between steps
- Fixtures: Mock CRM response data for various scenarios

---

## Related ADRs

- [ADR 01] Foundation Architecture — No customers table, CRM integration
- [ADR 02] Data Model — No customers in schema, task.context carries references
- [ADR 04] SOP Execution Engine — Step handlers call CrmService
- [ADR 08] Credential Management — CRM API key/OAuth token storage
