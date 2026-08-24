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
- No URL intake UI, source extraction, or persistence integration has been implemented. No gate configuration/evaluation, screening, persisted extracted facts, semantic analysis, content hashing, or duplicate detection exists.

## Latest Completed Slice

The guarded public-source fetch primitive implements the first security and resource-safety boundary required by ADR-002. It accepts only approved public HTTP/HTTPS destinations, connects to a validated numeric address while preserving logical host identity, revalidates manual redirects, and enforces time, media-type, encoding, network-size, and decompressed-size limits. It does not parse or persist retrieved content.

## Next Intended Slice

Decide the next separately approved URL-intake slice. Source extraction, review UI, and provenance persistence remain unimplemented and must not be inferred from the guarded-fetch primitive.

## Accepted Next Architecture, Not Yet Implemented

URL-first intake will coexist with manual paste. Beyond the implemented guarded-fetch primitive, its accepted boundary includes structured or generic extraction, a transient user-reviewable draft, and explicit Job creation using the exact approved text. Those later stages remain future work.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- Gate configuration/evaluation and Screened Out navigation.
- Persisted extracted facts and generalized gate infrastructure.
- URL intake UI, source extraction, and persistence integration.
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
- Working tree: contains the approved guarded-fetch implementation and documentation changes pending review; no commit or push has been made for this slice.
