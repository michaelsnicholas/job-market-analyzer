# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can fetch a public posting into a transient review form or enter a job manually; explicitly save approved source text with provenance appropriate to its path; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The staged gate/analysis architecture is accepted: preserved source, deterministic facts, mutable preferences, gate evaluation, semantic verification, and full analysis have distinct responsibilities and lifecycles. Screened Out will be derived from current evaluations rather than stored as permanent job state.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- Deterministic Work Arrangement extraction is implemented as an experimental, versioned plain Elixir domain result recomputed from each saved raw description. It returns known explicitly offered modes or unknown, preserves exact byte-indexed evidence and rule identity, and appears on the job detail page.
- URL-first intake architecture is accepted in ADR-002: guarded retrieval will produce a reviewable draft that converges with manual capture on user-approved canonical text, with lightweight Job provenance and human review before persistence.
- The first URL-intake implementation slice provides a guarded, bounded public-source fetch primitive. It validates every URL/DNS/IP hop, pins each request to a selected public address, handles redirects itself, and returns transient response or stable error data.
- Structured `JobPosting`, conservatively DOM-reconciled structured descriptions, generic HTML, or plain-text extraction and transient reviewable Draft construction are implemented behind the guarded fetcher. Drafts retain source URLs and acquisition time, preserve the initial extracted text for later edit detection, and carry deterministic metadata suggestions, method/version information, and stable warnings without persistence.
- Job provenance persistence and separate manual/URL-acquired context creation contracts are implemented. Manual attributes cannot forge acquisition history; reviewed URL-derived Jobs take provenance from a trusted Draft and record exact source-text modification status.
- The URL-first LiveView workflow is implemented. It performs guarded acquisition asynchronously, keeps trusted Draft provenance in server-side LiveView state, presents suggestions and warnings for review, and saves only after explicit approval through the acquired persistence contract. Failure falls back to manual entry without creating a Job, and manual capture remains available as a distinct path.
- No gate configuration/evaluation, screening, persisted extracted facts, semantic analysis, content hashing, or duplicate detection exists.

## Latest Completed Slice

The fourth URL-intake slice adds the LiveView acquisition, review, and explicit-save workflow. The saved-jobs corpus remains visible throughout intake, URL fetching runs asynchronously, trusted Draft state remains server-side and transient, and manual intake remains distinct.

## Next Intended Slice

Evaluate the completed URL-first workflow through local browser use and decide the next product slice separately. No later URL-acquisition or analysis work is authorized yet.

## Accepted URL-Intake Architecture

URL-first intake coexists with manual paste. Guarded acquisition, structured/generic/plain-text extraction, transient draft construction, browser review, and trusted persistence of the exact user-approved text with acquisition provenance are implemented.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- Gate configuration/evaluation and Screened Out navigation.
- Persisted extracted facts and generalized gate infrastructure.
- User accounts, authentication, or hosted multi-user architecture.
- Cross-job analytics.
- Embeddings or vector search.
- Résumé matching.
- Background queues or distributed workers.

See `docs/PROJECT.md` for the complete scope boundaries and deferred concerns.

## Open Questions / Blockers

Final Work Arrangement rules remain experimental. General gate design, deterministic `UNKNOWN` behavior during future screening, empty accepted-value behavior, semantic result combination, override semantics, fact persistence, and model/runtime selection remain deferred.

## Repository State

- Branch: `main`.
- Working tree: contains the approved Slice 4 LiveView implementation, tests, and current-state documentation changes pending review; no commit or push has been made for this slice.
