---
paths:
  - "**/ai/**"
  - "**/llm/**"
  - "**/prompts/**"
  - "**/*prompt*"
---

# AI / LLM domain pack

AI / LLM domain pack. Layers on the spine ([`../PHILOSOPHY.md`](../PHILOSOPHY.md)).
Applies to any product with AI features. It builds on the web pack
([`web.md`](web.md)) for the Postgres `api_calls` cost-tracking table. §27 references
§5 (Postgres only), §11 (API integration primitives), and §22 (background jobs).
§ numbers match the spine's Section index.

---

## §27. AI / LLM integration

**Rule.** An LLM in a product brings its own slice of the philosophy. Four parts:
**non-deterministic outputs**, **per-request cost**, **provider risk**, and
**eval discipline as the load-bearing tool**. Treat an LLM call as a
§11 API integration with these concerns layered on top.

### Evals are the load-bearing tool

Deterministic tests can't tell you whether the system *actually does the thing*
when the model itself is non-deterministic. Evals can.

**Fixtures + accuracy thresholds**, not pass/fail. An eval suite is a set of
`(input, expected_or_acceptable_output)` fixtures, run through the actual model,
scored against a target threshold (e.g. *≥ 80% match*, *false-positive rate
≤ 5%*, *ranking agreement ≥ 0.7 with the human gold*). The pass/fail is on the
**threshold**, not on any individual fixture. The model may miss any particular
case, as long as the aggregate behaves.

**Prefer fixtures over LLM-as-judge** wherever the output is binary,
multi-choice, or otherwise scoreable by a deterministic comparison. LLM-as-judge
has its place, in open-ended generation where no fixed answer exists. But every
judge call is its own non-determinism and its own bill. Use it sparingly.

**Evals run on every PR but are not always required to pass.** In an AI feature's
inception phase, a red eval is a signal. It is not a blocker. You are still
working out the model, the prompt, and the eval suite itself. To lock the
threshold in on day one teaches the team to game the threshold instead of
building the feature.

As the system stabilizes, **promote evals to blocking** with a regression
threshold (new PR's score must be ≥ baseline − N%). Until then, the score is
visible on every PR but not enforced. This is the carve-out in §24's "green CI
is non-negotiable" rule.

**Eval improvement is itself a system.** You start with a small fixture set and
improve it as you ship. It grows with adversarial cases, user-flagged outputs,
and sampled production traffic. Two viable strategies:

1. **Manual labelling**: a recurring review of recent outputs, tagged for
   correctness and added to the eval set.
2. **Self-healing**: production traffic sampled and auto-labelled, then fed back
   into the eval set. Another model, a heuristic, or a thumbs-up/down in the UI
   does the labelling.

Manual is the safe default. Self-healing earns its keep when volume makes manual
infeasible and the auto-labelling is reliable. Either way there *is* a system,
not a static suite that ages out of relevance.

**Eval improvement informs model improvement.** When the eval bar moves, the
prompt, the RAG retrieval, or the fine-tune improves to clear it. That happens two ways.
Manually, where a human reads the failing cases and edits the prompt. Or through
self-healing, where a tuning loop optimises against the eval set. The cycle runs
eval, then model improvement, then eval again. That is the product loop for AI
features.

### Provider choice

**Default: Anthropic and OpenAI**, accessed via **OpenRouter** as the unified
surface. Same logic as §13. A managed API absorbs the operational cost of a large
model. Self-hosted earns its keep only on a named cost or compliance reason.

**OpenRouter specifically** because: a single SDK fronts dozens of providers,
easy switching without code rewrites, single billing across providers, and
pay-with-crypto. It reduces vendor lock-in along the §13 own-the-data axis. You
can leave any single provider without a code change.

**Self-hosted models earn their keep** on:

- **Regulatory or data-protection** constraints that genuinely forbid sending
  data to a third party. The most common real reason.
- **Cost** at very high volume. The bar is high. To run a model at production
  quality is expensive in its own ways: GPUs, ops, security patches, and model
  upkeep.
- **Latency** in a specific geo that managed providers serve badly. Rare.

### Cost discipline: track every metered call

**Hard line: every metered API call is logged in Postgres** with enough fields
to attribute cost per user, per request, per model, per time window. This is
non-negotiable for any project that ships AI features.

Shape (adapt to the project):

```
api_calls (
  id, user_id, request_id, provider, model, endpoint,
  input_tokens, output_tokens, cost_estimate_cents,
  latency_ms, status, started_at, finished_at
)
```

**Why this is non-negotiable.** AI costs scale per-request, not per-user-month.
A bug, an abusive user, or a hot loop can rack up four-digit bills in hours.
Without per-request tracking, you find out from the provider's billing page
weeks after the fact. With it, you alert at the first $10/hour anomaly and you
know exactly which user / request / model / time window did it.

**The rule extends to any per-request metered API**, not only LLMs (Twilio SMS,
certain Maps APIs, transaction-fee processors). The §11 in-flight map and rate
limiter stop you making expensive calls. The cost-tracking table tells you what
you did make, once you let them through.

**Earn-its-keep, when cost tracking can be relaxed:**

- **Non-commercial / personal projects** with a known small footprint and a
  single user. The provider's billing page is fine.
- **Multi-tenant where each user gets their own deployment / self-hosts.** Cost
  is naturally segregated by deployment; internal tracking is redundant.
- **Non-metered APIs** (a flat-rate SaaS, an internal service). No per-call cost
  to attribute.

### Provider fallback

**Default: if the provider is down, that feature is down.** Accept the §26 trade,
consistency over availability, and let the request fail loud. The §11 breaker
opens and the §12 error tracker fires. Most products survive an hour of AI
provider downtime. Few survive an auto-failover that silently produces wrong
answers from a fallback model.

**When the product must stay available**, declare an **ordered fallback chain** in
code. That covers commercial-ready, customer-facing, and contractually
guaranteed. Try the primary. On §11 breaker-open or a provider error, fall
through to the secondary. The chain is observable per §12, so you know when you
are degraded. The cost-tracking table (above) records which provider actually
served each request so the bill stays attributable.

### Prompt as code vs prompt as data

**Case by case.** The eval strategy is the strongest constraint. When evals are
stable and prompts change rarely, **code** is fine: versioned with the codebase,
simple to ship, and branched under git. When prompts iterate per-customer or
per-experiment, **data** is fine: a `prompts` table with versions, A/B-tested,
and possibly self-healed by the eval loop.

Pick based on how the prompt actually evolves in your product. Both can be
right; neither has a default.
