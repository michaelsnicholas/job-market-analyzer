# Separate Analysis Stages and Derive Screening

- Status: Accepted

## Context

Job source, facts about a posting, a user's mutable screening preferences, and judgments produced by different forms of analysis have different meanings and lifecycles. Combining them would make a preference change appear to change source evidence, allow a current screening decision to overwrite historical work, or make later semantic reasoning obscure what deterministic logic actually established.

The application also needs to conserve computation. Explicit facts can often be extracted and evaluated deterministically, while contextual eligibility and richer job analysis may require progressively more capable semantic mechanisms. The current phase must remain local and zero-cost.

## Decision

The intended pipeline has distinct conceptual stages:

```text
raw job source
→ deterministic fact extraction
→ user-configured gate evaluation
→ semantic verification
→ full analysis
```

- Preserved source is the evidence from which other artifacts are derived.
- Extracted facts describe the posting and are independent of user preferences or whether a related gate is enabled.
- Gate configuration represents mutable user preferences.
- Gate evaluations compare facts with current preferences. Their conceptual results are `PASS`, `FAIL`, `UNKNOWN`, and `NOT_APPLICABLE`; the last means the gate is disabled.
- Semantic verification adds contextual judgments without rewriting correct deterministic facts. Full analysis is a later, richer capability.

Deterministic extraction and screening must be conservative and inspectable. Explicit evidence can produce a fact; insufficient, ambiguous, or contradictory evidence should normally produce `UNKNOWN`. Deterministic rules do not use pseudo-confidence scores. All enabled deterministic gates should eventually run so every failure reason can be inspected. Under the current direction, any deterministic `FAIL` stops automatic progression to semantic processing, while retaining the job for inspection and future reconsideration.

Screened Out is a derived view of current effective evaluations, not an authoritative permanent property of a job. Preference changes can therefore change current eligibility without modifying source, destroying extracted facts, or deleting completed analysis. Existing analysis remains available even if a job later becomes screened out.

Semantic verification may inspect deterministic `PASS` as well as `UNKNOWN`. Contextual constraints should be represented separately where practical—for example, a correct fully-remote fact may pass Work Arrangement while geographic eligibility fails—so provenance remains clear.

Application-owned capability and result contracts will isolate future semantic mechanisms from LiveView and domain callers. This decision does not authorize generic provider behaviours, registries, adapters, or runtime-switching infrastructure.

## Consequences

- Source, facts, preferences, evaluations, semantic judgments, and full analyses can evolve without silently overwriting one another.
- Current screening can be recomputed when preferences change, and screened-out jobs remain part of the durable corpus.
- Conservative deterministic failures reduce unnecessary semantic work but create false-negative risk; evidence, regression cases, inspection, and future human reconsideration are therefore important.
- The application must eventually define how semantic results combine and how human overrides work, but those policies remain deferred.
- No generalized gate framework, fact-persistence model, preference/evaluation history, materialized screening projection, or model-provider infrastructure is implied by this decision.
