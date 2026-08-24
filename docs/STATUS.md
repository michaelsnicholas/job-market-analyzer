# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can capture a job with optional Company, Role, and Source URL plus a required raw description; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The staged gate/analysis architecture is accepted: preserved source, deterministic facts, mutable preferences, gate evaluation, semantic verification, and full analysis have distinct responsibilities and lifecycles. Screened Out will be derived from current evaluations rather than stored as permanent job state.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- Deterministic Work Arrangement extraction is implemented as an experimental, versioned plain Elixir domain result recomputed from each saved raw description. It returns known explicitly offered modes or unknown, preserves exact byte-indexed evidence and rule identity, and appears on the job detail page.
- URL-first intake architecture is accepted in ADR-002: guarded retrieval will produce a reviewable draft that converges with manual capture on user-approved canonical text, with lightweight Job provenance and human review before persistence.
- The first URL-intake implementation slice provides a guarded, bounded public-source fetch primitive. It validates every URL/DNS/IP hop, pins each request to a selected public address, handles redirects itself, and returns transient response or stable error data.
- Structured `JobPosting`/generic HTML extraction and transient reviewable Draft construction are implemented behind the guarded fetcher. Drafts retain source URLs and acquisition time, preserve the initial extracted text for later edit detection, and carry deterministic metadata suggestions, method/version information, and stable warnings without persistence.
- No URL intake UI, Job creation from fetched sources, or provenance persistence integration has been implemented. No gate configuration/evaluation, screening, persisted extracted facts, semantic analysis, content hashing, or duplicate detection exists.

## Latest Completed Slice

The second URL-intake slice converts bounded fetch results into transient drafts. It prefers usable `JobPosting` JSON-LD, falls back to conservative generic HTML extraction, preserves readable structural text, and returns stable inadequate/ambiguous extraction failures rather than fabricating source. Nothing is persisted.

## Next Intended Slice

Run real-source QA through IEx/manual calls, then decide the next separately approved URL-intake slice. Review UI, Job creation, and provenance persistence remain unimplemented.

## Accepted Next Architecture, Not Yet Implemented

URL-first intake will coexist with manual paste. Guarded acquisition, structured/generic extraction, and transient draft construction are implemented. A user-reviewable UI and explicit Job creation using the exact approved text remain future work.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- Gate configuration/evaluation and Screened Out navigation.
- Persisted extracted facts and generalized gate infrastructure.
- URL intake UI, Job creation from drafts, and provenance persistence integration.
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
- Working tree: contains the approved Slice 2 extraction implementation and documentation changes pending review; no commit or push has been made for this slice.
