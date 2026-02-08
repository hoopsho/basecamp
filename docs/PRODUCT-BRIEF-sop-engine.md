# Product Brief — SOP Engine

---

## The Idea (One Sentence)

**An AI-powered business process engine that automates back-office operations for a small lawn care / snow removal company by defining SOPs and executing them via background jobs with tiered LLM decision-making, using Slack as the sole human interface.**

---

## Problem

- **User Frustration:** Chris (co-owner of Snowmass) runs all back-office operations solo — lead response, customer reactivation, invoicing follow-ups, review requests — with zero documented processes, no CRM, and no dedicated software. Everything is manual and reactive.
- **Current Solution Gap:** There is no system. Leads sit in an email inbox until Chris sees them. Past customers don't get reactivated unless Chris remembers. Follow-ups depend entirely on his availability and memory. There's no delegation because there's nothing documented to delegate.
- **Frequency:** Daily. Every business day involves manually handling inquiries, chasing overdue invoices, and missing opportunities because there's no systematic outreach.
- **Cost of Not Solving:** Lost revenue. The fertilizer/weed control sales window (mid-February to end of May) is finite. Every day a past customer isn't contacted or a new lead isn't responded to is money left on the table. At ~$300-500 per seasonal fert/weed control contract, losing even 20 customers to slow follow-up is $6,000-$10,000 in missed recurring revenue per season.

---

## Target User

- **Role:** Small service business owner-operator (specifically Chris Miller, co-owner of Eighty Eight Services LLC / Snowmass)
- **Company/Segment:** 2-person ownership, no administrative staff, Twin Cities metro lawn care / snow removal company. Revenue likely in the $100k-$500k range.
- **How they currently work:** Chris checks email sporadically, responds to leads when he has time (often hours or days later), tracks customers in his head or spreadsheets, sends invoices manually, and has no outbound marketing automation.
- **Why they'd care:** More signed customers with less manual effort. The system should feel like having a back-office team — handling routine communications, following up on leads, chasing overdue invoices — while Chris focuses on operations and service delivery.

---

## Proposed Solution

A headless Rails 8 application (no UI — Slack is the only interface) that defines business processes as SOPs with sequential steps, then executes them automatically using background jobs. AI (Claude API, tiered from Haiku to Opus) handles classification, drafting, and decision-making. Every customer-facing action starts with human approval via Slack, relaxing to autonomous as trust builds. Agents run on recurring loops, survey their domain, and act like employees who check in every few minutes.

---

## Key Features

1. **SOP Definition & Execution Engine** — Define multi-step business processes (reactivation campaigns, lead response, invoice follow-up) as data, then run them automatically with a step-by-step job pipeline
2. **4-Tier LLM Intelligence** — Route AI work to the cheapest capable model (no LLM → Haiku → Sonnet → Opus → human escalation) with automatic confidence-based escalation, keeping costs low while handling edge cases
3. **Slack-Only Human Interface** — All notifications, approvals, and decisions happen in Slack channels and threads. Chris never logs into the app. Agents post updates, ask for approvals, and escalate via interactive buttons
4. **Agent Loop System** — Recurring background jobs that survey, assess, prioritize, and execute work in their domain — behaving like employees who autonomously check their inbox and take action
5. **Full Audit Trail** — Every LLM call, email sent, Slack message, and human decision logged to TaskEvents with token counts, confidence scores, and duration — enabling cost tracking and debugging
6. **Watcher-Driven Triggers** — Automated detection of actionable events (new emails, overdue invoices, schedule triggers) that create tasks and kick off the right SOP without manual intervention

---

## Revenue Model

This is an **internal tool**, not a SaaS product. It doesn't generate revenue directly — it protects and grows revenue by automating lead response and customer retention for Snowmass.

- **Value Model:** Revenue preservation and growth. If the system reactivates 30 past fert/weed control customers at $400 avg contract, that's $12,000 in recovered revenue per season. If it responds to leads within 5 minutes instead of 5 hours, close rate likely improves 20-40%.
- **Cost:** Heroku hosting (~$25-50/month for app + worker dynos), Anthropic API usage (~$20-50/month assuming mostly Haiku with occasional Sonnet), transactional email service (~$10/month), Slack (free tier or existing workspace). Total: ~$55-110/month.
- **ROI:** If it saves Chris 10 hours/week of admin time AND recovers even $5,000 in revenue from faster lead response and customer reactivation, the ROI is massive against a $100/month operating cost.
- **Future Potential:** If the engine proves effective, the SOP framework could be generalized into a SaaS product for other small service businesses. But that's not the current goal.

---

## Competitive Landscape

### Existing Competitors

- **Jobber / ServiceTitan / Housecall Pro:** Field service management platforms with CRM, scheduling, invoicing, and some automation. Weakness: expensive ($50-200+/month), heavy onboarding, designed for larger operations, limited AI capabilities, rigid workflows that don't adapt to how a 2-person operation actually works.
- **GoHighLevel / HubSpot:** Marketing automation and CRM platforms with email sequences and lead management. Weakness: generic (not built for service businesses), require significant setup and ongoing management, monthly costs of $97-$300+, and the automation is template-based — no AI judgment or escalation.
- **Zapier / Make + ChatGPT:** DIY automation stacks. Weakness: fragile, no unified audit trail, no confidence-based escalation, hard to debug, becomes a mess of disconnected automations, and ChatGPT API calls lack the structured tiered approach.
- **Custom GPTs / AI Assistants:** Conversational AI tools. Weakness: they're chatbots, not process engines. They respond to prompts, they don't autonomously survey a domain, detect triggers, and execute multi-step workflows.

### Our Advantage

- **Built for one business.** No compromise. The SOPs encode exactly how Snowmass operates, not a generic "lawn care company" template.
- **Headless + Slack.** Zero friction for the operator. No new app to learn, no dashboard to check. Work shows up where Chris already is.
- **Tiered AI cost control.** Most competitors either don't use AI or use expensive models for everything. The 4-tier escalation keeps 80%+ of operations at Tier 0 (free) or Tier 1 (pennies).
- **Process-first, AI-second.** The SOP structure means the system is auditable and debuggable. When something goes wrong, you can trace it to a specific step, not a black-box AI decision.

---

## Validation Questions

1. **Can Haiku reliably classify incoming emails and draft acceptable customer communications?** — How to test: Process 50 real past emails through the classification pipeline, measure accuracy. Draft 20 reactivation emails and have Chris rate them pass/fail.
2. **Will Chris actually respond to Slack approval requests promptly enough to not bottleneck the system?** — How to test: Simulate the approval flow for one week using manual Slack messages. Track response times. If avg response > 2 hours, the system needs more autonomy from day one.
3. **Is the customer data clean enough to run automated outreach without embarrassing errors (wrong names, outdated addresses, deceased customers)?** — How to test: Export the current customer list (however it exists), run a data quality audit, identify gaps and errors before any outreach goes live.
4. **Does the 5-minute lead response window actually improve conversion for this business?** — How to test: Track lead response times and close rates for 30 days before and after deployment. Target: measurable improvement in close rate with faster response.

---

## Next Steps

1. **Data Audit (Week 1):** Export and clean customer data. Identify past fert/weed control customers for reactivation. Establish a clean customers table with accurate contact info.
2. **Core Infrastructure (Week 1-2):** Scaffold Rails 8 app, migrations, LlmService with 4-tier routing, SlackService, and EmailService. Get the plumbing working.
3. **SOP 1 Live Test (Week 2-3):** Build and test the Past Customer Reactivation SOP end-to-end. Start with all emails requiring Slack approval. Send reactivation emails to a small batch (10 customers) and measure response.
4. **SOP 2 Live Test (Week 3-4):** Build and test New Lead Response. Wire up the email inbox watcher. Verify classification accuracy on real incoming mail. Go live with human-in-the-loop approval.

---

## Owner & Timeline

- **Product Owner:** Chris Miller — sole operator, decision-maker, and the person this system serves
- **Target Decision Date:** Already committed. The sales window opens mid-February 2026.
- **Estimated MVP Timeline:** 2-3 weeks to SOP 1 live, 3-4 weeks to SOP 2 live. System should be actively working leads by early March 2026.

---

## Notes

- The fertilizer/weed control sales window is the forcing function. Mid-February to end of May 2026. This system needs to be reactivating past customers and responding to leads by early March at the latest.
- The SOP engine design is deliberately over-engineered for a lawn care company — and that's intentional. The framework generalizes to any small business with repeatable processes. If it works for Snowmass, the architecture could serve hundreds of similar businesses.
- Start conservative: every customer-facing email requires Slack approval. As confidence in the AI drafting builds, remove the approval step for routine communications.
- The tiered LLM approach is critical for cost management. A system that sends everything to Sonnet or Opus would cost 10-50x more per month with minimal quality improvement for routine tasks.
- No UI is a feature, not a limitation. Building a dashboard would triple the development time and Chris wouldn't use it. Slack is where he lives.
