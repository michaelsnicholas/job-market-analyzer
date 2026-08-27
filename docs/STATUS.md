# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can fetch a public posting into a transient review form or enter a job manually; explicitly save approved source text with provenance appropriate to its path; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The staged gate/analysis architecture is accepted: preserved source, deterministic facts, mutable preferences, gate evaluation, semantic verification, and full analysis have distinct responsibilities and lifecycles. Screened Out will be derived from current evaluations rather than stored as permanent job state.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- Deterministic Work Arrangement extraction is implemented as an experimental, versioned plain Elixir domain result recomputed from each saved raw description. It returns known explicitly offered modes or unknown, preserves exact byte-indexed evidence and rule identity, and appears on the job detail page.
- A dedicated singleton SQLite preference stores Work Arrangement filter disclosure state and explicit accepted modes. The compact control belongs to Saved jobs and persists every toggle immediately. Opening it with no modes is valid and instructional; hiding it preserves selections but makes them inactive.
- Work Arrangement evaluation is derived on demand rather than persisted. No active modes is not applicable; explicit matching facts pass, explicit nonmatching facts fail, and insufficient deterministic evidence remains unknown for future semantic routing. The Saved jobs projection hides only failures, while preference changes can immediately restore them without modifying the corpus. The detail page displays the evaluation with the extracted fact, active accepted modes, and evidence.
- URL-first intake architecture is accepted in ADR-002: guarded retrieval produces a reviewable draft that converges with manual capture on user-approved canonical text, with lightweight Job provenance and human review before persistence.
- The first URL-intake implementation slice provides a guarded, bounded public-source fetch primitive. It validates every URL/DNS/IP hop, pins each request to a selected public address, handles redirects itself, and returns transient response or stable error data.
- Structured `JobPosting`, conservatively DOM-reconciled structured descriptions, generic HTML, or plain-text extraction and transient reviewable Draft construction are implemented behind the guarded fetcher. Drafts retain source URLs and acquisition time, preserve the initial extracted text for later edit detection, and carry deterministic metadata suggestions, method/version information, and stable warnings without persistence.
- Job provenance persistence and separate manual/URL-acquired context creation contracts are implemented. Manual attributes cannot forge acquisition history; reviewed URL-derived Jobs take provenance from a trusted Draft and record exact source-text modification status.
- The URL-first LiveView workflow is implemented. It performs guarded acquisition asynchronously, keeps trusted Draft provenance in server-side LiveView state, presents suggestions and warnings for review, and saves only after explicit approval through the acquired persistence contract. Failure falls back to manual entry without creating a Job, and manual capture remains available as a distinct path.
- No additional gates, generalized gate infrastructure, separate Screened Out view, persisted facts or evaluations, semantic analysis, content hashing, or duplicate detection exists.

## Latest Completed Slice

Slice 5 adds an immediately persisted Work Arrangement filter for Saved jobs and deterministic `PASS`, `FAIL`, `UNKNOWN`, and `NOT_APPLICABLE` evaluation while keeping facts, evaluations, and filtering derived.

## Next Intended Slice

Evaluate the completed Work Arrangement screening experiment and decide the next product slice separately. Semantic verification, a separate Screened Out view, and further gates remain unapproved.

## Accepted URL-Intake Architecture

URL-first intake coexists with manual paste. Guarded acquisition, structured/generic/plain-text extraction, transient draft construction, browser review, and trusted persistence of the exact user-approved text with acquisition provenance are implemented.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- Additional gate configuration/evaluation and Screened Out navigation.
- Persisted extracted facts and generalized gate infrastructure.
- User accounts, authentication, or hosted multi-user architecture.
- Cross-job analytics.
- Embeddings or vector search.
- Résumé matching.
- Background queues or distributed workers.

See `docs/PROJECT.md` for the complete scope boundaries and deferred concerns.

## Open Questions / Blockers

Final Work Arrangement extraction rules remain experimental. General gate design, implemented semantic routing for `UNKNOWN`, semantic result combination, override semantics, fact persistence, and model/runtime selection remain deferred.

## Repository State

- Primary branch: `main`.
- Slice 5 Work Arrangement preference and deterministic evaluation is the current development baseline.
