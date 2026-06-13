# AI / LLM domain pack

AI / LLM domain pack. Layers on the spine ([`../PHILOSOPHY.md`](../PHILOSOPHY.md));
applies to any product with AI features. It builds on the web pack
([`web.md`](web.md)) for the Postgres `api_calls` cost-tracking table — §27 references
§5 (Postgres only), §11 (API integration primitives), and §22 (background jobs).
§ numbers match the spine's Section index.

---

## §27. AI / LLM integration

**Rule.** Integrating an LLM into a product brings its own slice of the
philosophy: **non-deterministic outputs**, **per-request cost**, **provider
risk**, and **eval discipline as the load-bearing tool**. Treat an LLM call as a
§11 API integration with these concerns layered on top.

### Evals are the load-bearing tool

Deterministic tests can't tell you whether the system *actually does the thing*
when the model itself is non-deterministic. Evals can.

**Fixtures + accuracy thresholds**, not pass/fail. An eval suite is a set of
`(input, expected_or_acceptable_output)` fixtures, run through the actual model,
scored against a target threshold (e.g. *≥ 80% match*, *false-positive rate
≤ 5%*, *ranking agreement ≥ 0.7 with the human gold*). The pass/fail is on the
**threshold**, not on any individual fixture — the model is allowed to miss any
particular case as long as the aggregate behaves.

**Prefer fixtures over LLM-as-judge** wherever the output is binary,
multi-choice, or otherwise scoreable by a deterministic comparison. LLM-as-judge
has its place (open-ended generation where no fixed answer exists), but every
judge call is its own non-determinism and its own bill. Use it sparingly.

**Evals run on every PR but are not always required to pass.** Especially in the
inception phase of an AI feature — when you're still figuring out the model,
the prompt, and the eval suite itself — a red eval is a signal, not a blocker.
Locking the threshold in on day one teaches the team to game the threshold
instead of building the feature.

As the system stabilizes, **promote evals to blocking** with a regression
threshold (new PR's score must be ≥ baseline − N%). Until then, the score is
visible on every PR but not enforced. This is the carve-out in §24's "green CI
is non-negotiable" rule.

**Eval improvement is itself a system.** You start with a small fixture set and
you improve it as you ship — adversarial cases, user-flagged outputs, sampled
production traffic. Two viable strategies:

1. **Manual labelling** — recurring review of recent outputs, tagged for
   correctness, added to the eval set.
2. **Self-healing** — production traffic sampled and auto-labelled (by another
   model, by heuristics, by explicit thumbs-up/down in the UI), fed back into
   the eval set.

Manual is the safe default; self-healing earns its keep when volume makes manual
infeasible and the auto-labelling is reliable. Either way, there *is* a system —
not a static suite that ages out of relevance.

**Eval improvement informs model improvement.** When the eval bar moves, the
prompt / RAG retrieval / fine-tune improves to clear it — either manually
(a human reads the failing cases and edits the prompt) or self-healing (a
tuning loop optimises against the eval set). The cycle — eval → model
improvement → eval again — is the actual product loop for AI features.

### Provider choice

**Default: Anthropic and OpenAI**, accessed via **OpenRouter** as the unified
surface. Same logic as §13: managed APIs absorb the operational cost of running
large models; self-hosted earns its keep only on a named cost or compliance
reason.

**OpenRouter specifically** because: a single SDK fronts dozens of providers,
easy switching without code rewrites, single billing across providers, and
pay-with-crypto. Reduces vendor lock-in along the §13 own-the-data axis — you
can leave any single provider without changing your code.

**Self-hosted models earn their keep** on:

- **Regulatory or data-protection** constraints that genuinely forbid sending
  data to a third party. The most common real reason.
- **Cost** at very high volume — bar is high; operating a model at production
  quality is expensive in its own ways (GPUs, ops, security patches, model
  upkeep).
- **Latency** in a specific geo where managed providers don't serve well — rare.

### Cost discipline — track every metered call

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
certain Maps APIs, transaction-fee processors). The §11 in-flight map / rate
limiter is about *not making* expensive calls; the cost-tracking table is about
*knowing what you did make* once you let them through.

**Earn-its-keep — when cost tracking can be relaxed:**

- **Non-commercial / personal projects** with a known small footprint and a
  single user. The provider's billing page is fine.
- **Multi-tenant where each user gets their own deployment / self-hosts.** Cost
  is naturally segregated by deployment; internal tracking is redundant.
- **Non-metered APIs** (a flat-rate SaaS, an internal service). No per-call cost
  to attribute.

### Provider fallback

**Default: if the provider is down, that feature is down.** Accept the §26 trade
— consistency over availability — and let the request fail loud (with the §11
breaker open, the §12 error tracker firing). Most products survive an AI
provider being down for an hour; few products survive an auto-failover that
silently produces wrong answers from a fallback model.

**When the product must stay available** (commercial-ready, customer-facing,
contractually guaranteed), declare an **ordered fallback chain** in code — try
the primary, on §11 breaker-open or provider error fall through to the
secondary, etc. The chain is observable per §12 so you know when you're
degraded. The cost-tracking table (above) records which provider actually
served each request so the bill stays attributable.

### Prompt as code vs prompt as data

**Case by case.** The eval strategy is the strongest constraint: if your evals
are stable and prompts change rarely, **code** is fine (versioned with the
codebase, simple to ship, branches under git). If your prompts iterate
per-customer or per-experiment, **data** is fine (a `prompts` table with
versions, A/B-tested, possibly self-healed by the eval loop).

Pick based on how the prompt actually evolves in your product. Both can be
right; neither has a default.
