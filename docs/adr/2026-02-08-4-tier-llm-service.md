# ADR 03: 4-Tier LLM Service

**ADR ID:** 2026-02-03
**Status:** ACCEPTED
**Date:** 2026-02-08
**Author(s):** Chris Miller
**Reviewers:** —

---

## Context

**Category:** FEATURES

The SOP Engine uses AI for classification, content drafting, decision-making, and analysis. Not every task requires AI, and when it does, the required capability varies dramatically:

- Classifying an email as "spam" vs "new lead" is trivial (Haiku)
- Drafting a personalized reactivation email needs more nuance (Haiku or Sonnet)
- Deciding how to handle an angry customer complaint requires judgment (Sonnet)
- Handling a completely unexpected situation needs the best model available (Opus)

Using a single expensive model for everything would cost 10-50x more with minimal quality improvement for routine tasks. We need a system that routes each request to the cheapest model capable of handling it, with automatic escalation when confidence is low.

---

## Decision

**Decision:** We will build a 4-tier LLM routing service with confidence-based automatic escalation from cheaper to more expensive models, culminating in human escalation via Slack when AI confidence remains insufficient.

### Tier Definitions

| Tier  | Model             | Model ID                     | Use Cases                                                          | Approx Cost     |
| ----- | ----------------- | ---------------------------- | ------------------------------------------------------------------ | --------------- |
| 0     | None (pure Ruby)  | —                            | DB queries, conditionals, time checks, API calls                   | Free            |
| 1     | Claude Haiku 4.5  | `claude-haiku-4-5-20251001`  | Classification, templated drafting, simple yes/no, data extraction | ~$0.001/call    |
| 2     | Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` | Personalized content, nuanced decisions, multi-step reasoning      | ~$0.01/call     |
| 3     | Claude Opus 4.6   | `claude-opus-4-6`            | Escalation only — unexpected situations, complex judgment          | ~$0.10/call     |
| Human | Slack             | —                            | Final escalation — post to #escalations for Chris to decide        | Free (but slow) |

### Escalation Chain

```
Step declares: min_tier: 1, max_tier: 3

1. Call Haiku -> response includes confidence_score
2. If confidence < CONFIDENCE_THRESHOLD (0.7) -> escalate to Sonnet
3. If Sonnet confidence < CONFIDENCE_THRESHOLD -> escalate to Opus
4. If Opus confidence < CONFIDENCE_THRESHOLD -> escalate to Human (Slack)
5. If tier already at max_tier for this step -> escalate to Human
```

### LlmService Interface

```ruby
class LlmService
  TIER_MODELS = {
    1 => 'claude-haiku-4-5-20251001',
    2 => 'claude-sonnet-4-5-20250929',
    3 => 'claude-opus-4-6'
  }.freeze

  CONFIDENCE_THRESHOLD = 0.7

  # Main entry point
  def self.call(prompt:, context:, min_tier:, max_tier:, step: nil, task: nil)
    # Returns:
    # {
    #   response: String or Hash (parsed JSON),
    #   confidence: Float (0.0-1.0),
    #   tier_used: Integer (1-3),
    #   model: String (actual model ID),
    #   tokens_in: Integer,
    #   tokens_out: Integer,
    #   escalated: Boolean (did we escalate from min_tier?),
    #   escalation_chain: Array (tiers attempted, e.g., [1, 2])
    # }
  end
end
```

### Prompt Structure

Every LLM call includes these components in order:

1. **System prompt** — Agent role definition + SOP context
2. **Step prompt template** — From step.config, with `{{variable}}` placeholders interpolated from task.context
3. **Agent memory** — Relevant memories loaded by importance and recency
4. **Response format instruction** — Always request structured JSON with a confidence field

Example assembled prompt:

```
System: You are the Lead Response Agent for Snowmass, a lawn care and
snow removal company in the Twin Cities, MN. Your job is to classify
incoming communications and route them appropriately.

Context: You have handled 47 similar classifications this week with
98% accuracy. Common categories are: new_lead (40%), existing_customer
(30%), scheduling (15%), spam (10%), other (5%).

Task: Classify the following email into one of these categories:
new_lead, existing_customer_request, complaint, scheduling_change,
spam, other.

Email:
---
Subject: Lawn care estimate
Hi, I found your company on Google. We just moved to Eagan and need
someone for fertilizer and weed control this spring. Can you give us
a quote for our yard? It's about 8,000 sq ft. Thanks, Jane
---

Respond with JSON:
{
  "category": "one of: new_lead, existing_customer_request, complaint, scheduling_change, spam, other",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation",
  "suggested_action": "what should happen next",
  "extracted_data": {
    "name": "if available",
    "address": "if available",
    "service_requested": "if available",
    "source": "how they found us, if mentioned"
  }
}
```

### Confidence Score Convention

The LLM is asked to self-assess confidence on every call. The prompt always includes:

```
Include a "confidence" field (0.0 to 1.0) in your response:
- 0.9-1.0: Very certain, clear-cut case
- 0.7-0.89: Fairly confident, some minor ambiguity
- 0.5-0.69: Uncertain, could go either way (will trigger escalation)
- Below 0.5: Very uncertain, likely needs human review
```

This is a heuristic, not a calibrated probability. The threshold (0.7) is deliberately conservative — better to escalate unnecessarily than to act on a wrong classification.

### Error Handling

| Error                      | Behavior                                                                        |
| -------------------------- | ------------------------------------------------------------------------------- |
| API timeout                | Retry once with same tier. If still fails, log error and escalate to next tier. |
| Rate limit (429)           | Back off with exponential delay (1s, 2s, 4s). Max 3 retries. Then escalate.     |
| Invalid JSON response      | Retry once with explicit JSON formatting instruction. Then escalate.            |
| API error (500)            | Log error, escalate to next tier. If Opus also fails, escalate to human.        |
| Confidence below threshold | Escalate to next tier. If at max_tier, escalate to human.                       |

### Cost Controls

1. **Step-level tier caps** — Each step declares `max_llm_tier`. A classification step capped at Tier 1 will never call Sonnet or Opus — it escalates directly to human if Haiku is uncertain.
2. **SOP-level tier cap** — Each SOP declares `max_tier`. Even if a step allows Tier 3, the SOP cap takes precedence.
3. **Token logging** — Every call logs `tokens_in` and `tokens_out` to TaskEvents. Cost tracking is built in.
4. **No speculative calls** — Never call a higher tier "just to compare." Only escalate when confidence is below threshold.
5. **Tier 0 first** — If a step can be handled without AI (database query, API call, conditional), it runs at Tier 0. LLM is only invoked when classification, drafting, or judgment is needed.

---

## Consequences

### Positive Consequences

- **80%+ of operations cost pennies or nothing** — Most steps are Tier 0 (free) or Tier 1 (~$0.001/call)
- **Graceful degradation** — If a cheap model is uncertain, a better model handles it automatically. If all models are uncertain, a human decides.
- **Full cost visibility** — Every token logged. Monthly cost calculable from TaskEvents.
- **No over-spending** — Tier caps prevent expensive models from being used where they're not needed.
- **Consistent interface** — Services and jobs call `LlmService.call()` with tier parameters. They don't need to know which model actually ran.

### Negative Consequences / Trade-offs

- **Self-reported confidence is imperfect** — LLMs can be confidently wrong. The confidence score is a heuristic, not a calibrated probability.
- **Escalation adds latency** — A call that escalates from Haiku to Sonnet takes ~2x the time (sequential calls, not parallel).
- **Prompt engineering burden** — Each step needs a well-crafted prompt template that produces consistent structured JSON. Poor prompts produce poor confidence scores.
- **Model ID maintenance** — When Anthropic releases new model versions, the TIER_MODELS hash needs updating.

### Resource Impact

- Development effort: MEDIUM (service + escalation logic + error handling)
- Ongoing maintenance: LOW (model IDs may need periodic updates)
- Infrastructure cost: LOW ($20-50/month estimated for normal operations)

---

## Alternatives Considered

### Alternative 1: Single Model for Everything (Sonnet Only)

- Simpler code, no escalation logic, consistent quality
- Why rejected: 10-50x more expensive. Sonnet for spam classification is wasteful. The whole point of tiered routing is cost control.

### Alternative 2: OpenAI Instead of Anthropic

- GPT-4o-mini as cheap tier, GPT-4o as expensive tier
- Why rejected: Anthropic Claude is the established choice for this project (per CLAUDE.md). Structured JSON output with confidence scoring works well with Claude. No compelling reason to switch.

### Alternative 3: Parallel Tier Calls (Call All Tiers, Use Best)

- Call Haiku and Sonnet simultaneously, use whichever response is better
- Why rejected: Doubles or triples cost with minimal benefit. Sequential escalation only adds cost when the cheap model is actually uncertain. Parallel calls are wasteful for the 80%+ of cases where Haiku is sufficient.

### Alternative 4: Fine-Tuned Models

- Train custom models for classification and drafting tasks
- Why rejected: Premature optimization. Volume is too low to justify fine-tuning costs. General-purpose models with good prompts are sufficient for v0.1. Revisit if volume exceeds thousands of calls per day.

---

## Implementation

### Phase 1: Core Service

- Build `LlmService` with `self.call()` method
- Implement tier routing based on `min_tier` and `max_tier`
- Implement Anthropic API client (direct HTTP or `anthropic` gem)
- Parse structured JSON responses
- Return standardized result hash

### Phase 2: Escalation Logic

- Implement confidence threshold checking
- Build escalation chain (try next tier, log escalation event)
- Handle max_tier cap (escalate to human when AI can't decide)
- Log full escalation chain to TaskEvents

### Phase 3: Error Handling

- Retry logic for timeouts and rate limits
- Invalid JSON recovery (re-prompt with stricter formatting)
- API error escalation
- Fallback to human for all unrecoverable errors

### Testing Strategy

- Unit tests: Tier routing returns correct model for given min/max
- Unit tests: Escalation triggers when confidence below threshold
- Unit tests: Error handling retries correctly
- Integration tests: Full escalation chain (mock API responses at different confidence levels)
- Fixtures: Step configs with various tier configurations

---

## Related ADRs

- [ADR 01] Foundation Architecture — Why Anthropic Claude
- [ADR 02] Data Model — Step.llm_tier, Step.max_llm_tier, TaskEvent token fields
- [ADR 04] SOP Execution Engine — How TaskWorkerJob calls LlmService
- [ADR 07] Observability — Token logging and cost tracking
