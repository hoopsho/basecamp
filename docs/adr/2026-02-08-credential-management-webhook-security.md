# ADR 08: Credential Management & Webhook Security

**ADR ID:** 2026-02-08
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** SECURITY

The SOP Engine integrates with multiple external services, each requiring credentials:

- **Anthropic Claude API** — API key for LLM calls
- **Slack** — Bot token for posting, webhook secret for verifying incoming requests
- **Amazon SES** — Access key + secret for sending email
- **CRM** — API key or OAuth token for customer data access

These credentials must be stored securely, rotated when needed, and never exposed in logs, task context, or error messages. Additionally, incoming webhooks (Slack interactive components, email inbound) must be verified to prevent spoofing.

---

## Decision

**Decision:** We will use a two-layer credential strategy: Rails encrypted credentials (`config/credentials.yml.enc`) for infrastructure secrets that rarely change, and the `credentials` database table with Rails encrypted attributes for service tokens that may need rotation, expiration tracking, or OAuth refresh.

### Layer 1: Rails Encrypted Credentials

For secrets that are set once and rarely change:

```yaml
# config/credentials.yml.enc (edited via rails credentials:edit)
anthropic:
  api_key: sk-ant-...

slack:
  bot_token: xoxb-...
  signing_secret: abc123...
  app_id: A0...

ses:
  access_key_id: AKIA...
  secret_access_key: ...
  region: us-east-1
  from_address: noreply@snowmass.com

secret_key_base: ...
```

Accessed via `Rails.application.credentials.dig(:slack, :bot_token)`.

### Layer 2: Credential Model (Database)

For tokens that expire, need refresh, or are managed at runtime:

```ruby
class Credential < ApplicationRecord
  encrypts :encrypted_value
  encrypts :refresh_token

  enum :credential_type, [:api_key, :oauth_token, :webhook_secret]
  enum :status, [:active, :expired, :revoked]

  scope :for_service, ->(name) { where(service_name: name).active }
  scope :active, -> { where(status: :active) }
end
```

Use cases for the database layer:

- **OAuth tokens** with expiration and refresh (e.g., if the CRM uses OAuth)
- **Rotatable API keys** where the old key needs to remain active during rotation
- **Per-service credential status** tracking (active, expired, revoked)

### CredentialService Interface

```ruby
class CredentialService
  # Get the active credential for a service
  def self.get(service_name)
    # 1. Check database for active credential
    # 2. If OAuth and expired, attempt refresh
    # 3. If no DB credential, fall back to Rails encrypted credentials
    # Returns: decrypted credential value
  end

  # Refresh an OAuth token
  def self.refresh(credential)
    # 1. Use refresh_token to get new access token
    # 2. Update credential record with new token and expiration
    # 3. Log refresh event
  end

  # Revoke a credential (mark as revoked, don't delete)
  def self.revoke(credential)
    credential.update!(status: :revoked)
  end
end
```

### Webhook Verification

All incoming webhooks MUST be verified before processing.

#### Slack Webhook Verification

Slack signs every request with HMAC-SHA256 using the app's signing secret:

```ruby
class Api::V1::WebhooksController < ApplicationController
  before_action :verify_slack_signature, only: [:slack]

  private

  def verify_slack_signature
    timestamp = request.headers['X-Slack-Request-Timestamp']
    signature = request.headers['X-Slack-Signature']

    # Reject requests older than 5 minutes (replay protection)
    if (Time.now.to_i - timestamp.to_i).abs > 300
      head :unauthorized
      return
    end

    # Compute expected signature
    sig_basestring = "v0:#{timestamp}:#{request.raw_post}"
    signing_secret = Rails.application.credentials.dig(:slack, :signing_secret)
    expected = 'v0=' + OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)

    unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
      head :unauthorized
    end
  end
end
```

#### Email Webhook Verification (SES)

If using SES inbound email via SNS:

- Verify SNS message signature using the signing certificate
- Validate the `TopicArn` matches the expected SNS topic
- Confirm subscription requests only for expected topics

#### Generic Webhook Security

For any future webhook integrations:

1. **Always verify signatures** — Never process unverified webhooks
2. **Reject stale requests** — Timestamp must be within 5 minutes
3. **Use constant-time comparison** — `ActiveSupport::SecurityUtils.secure_compare`
4. **Log all webhook attempts** — Including rejected ones (for security monitoring)
5. **Rate limit** — Rack::Attack or similar for webhook endpoints

### API Authentication (REST Endpoints)

The admin REST API uses session-based authentication (Rails 8 auth):

- Authenticated users get a session cookie
- API requests from the admin UI include the session cookie
- No separate API tokens for v0.1

If external API access is needed in the future:

- Bearer token authentication
- Tokens stored in credentials table
- Rate limiting per token

### Security Rules

1. **Never log credentials** — No API keys, tokens, or secrets in TaskEvents, Rails logs, or error messages
2. **Never store credentials in task.context** — Task context is visible in the admin UI and logged in events
3. **Credential values are encrypted at rest** — Rails encrypted attributes handle this
4. **Webhook secrets are not in the database** — Kept in Rails encrypted credentials only (they don't need rotation)
5. **OAuth refresh tokens are encrypted** — Same encryption as credential values
6. **Revoke, don't delete** — When a credential is compromised, mark it revoked for audit trail. Never delete.
7. **Rotate on breach** — If any credential is exposed, immediately revoke and issue a new one

---

## Consequences

### Positive Consequences

- **Defense in depth** — Two layers: Rails encrypted credentials for infrastructure, encrypted database for rotatable tokens
- **Audit trail** — Credential status changes (active -> revoked) are tracked
- **OAuth support** — Built-in refresh mechanism for services that use OAuth
- **Webhook security** — All incoming requests verified. Replay attacks blocked.
- **No secrets in logs** — Explicit rules prevent credential leakage

### Negative Consequences / Trade-offs

- **Credential management complexity** — Two layers (file + database) means two places to check
- **Rails credentials require master key** — The master key must be securely shared (Heroku config var) and backed up
- **OAuth refresh adds failure modes** — If refresh fails, the service is unavailable until manually re-authenticated
- **No secrets management service** — No AWS Secrets Manager, HashiCorp Vault, etc. Rails encrypted credentials are sufficient for this scale.

### Resource Impact

- Development effort: LOW (Rails encrypted credentials are built-in, Credential model is simple)
- Ongoing maintenance: LOW (credential rotation is rare)
- Infrastructure cost: NONE

---

## Alternatives Considered

### Alternative 1: Environment Variables Only

- Store all secrets as ENV vars on Heroku
- Why rejected: ENV vars are visible to anyone with Heroku access, harder to manage in development, and don't support structured grouping. Rails encrypted credentials are more secure and portable. CLAUDE.md requires credentials, not ENV vars.

### Alternative 2: AWS Secrets Manager / HashiCorp Vault

- Enterprise-grade secrets management with automatic rotation
- Why rejected: Overkill for a single-tenant app with 4-5 service integrations. Adds cost and complexity. Rails encrypted credentials handle this scale.

### Alternative 3: All Credentials in Database Only

- No Rails encrypted credentials file, everything in the credentials table
- Why rejected: Infrastructure secrets (master signing secrets, API keys that never change) are simpler in the encrypted file. The database layer is for tokens that need runtime management (expiration, refresh, rotation).

---

## Implementation

### Phase 1: Rails Encrypted Credentials

- Set up `config/credentials.yml.enc` with Anthropic, Slack, and SES credentials
- Configure Heroku with `RAILS_MASTER_KEY`
- Verify services can access credentials

### Phase 2: Credential Model

- Migration and model (already in ADR #02 schema)
- CredentialService with `get`, `refresh`, `revoke` methods
- Seed initial credentials (or create via Rails console)

### Phase 3: Webhook Verification

- Slack signature verification middleware
- SES/SNS verification (if using inbound email)
- Rejected webhook logging
- Rate limiting on webhook endpoints

### Testing Strategy

- Unit tests: CredentialService.get returns correct credential
- Unit tests: OAuth refresh updates token and expiration
- Unit tests: Slack signature verification (valid, invalid, stale)
- Integration tests: Webhook endpoint rejects unsigned requests
- Integration tests: Webhook endpoint processes valid signed requests
- Fixtures: Credentials with various statuses (active, expired, revoked)

---

## Related ADRs

- [ADR 01] Foundation Architecture — Rails encrypted credentials, not ENV vars
- [ADR 02] Data Model — Credential table schema
- [ADR 03] 4-Tier LLM — Anthropic API key access
- [ADR 06] Slack Integration — Bot token and webhook signature verification
- [ADR 10] CRM Integration — CRM API credential management
