# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can capture a job with optional Company, Role, and Source URL plus a required raw description; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The staged gate/analysis architecture is accepted: preserved source, deterministic facts, mutable preferences, gate evaluation, semantic verification, and full analysis have distinct responsibilities and lifecycles. Screened Out will be derived from current evaluations rather than stored as permanent job state.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- Deterministic Work Arrangement extraction is implemented as an experimental, versioned plain Elixir domain result recomputed from each saved raw description. It returns known explicitly offered modes or unknown, preserves exact byte-indexed evidence and rule identity, and appears on the job detail page.
- No gate configuration/evaluation, screening, persisted extracted facts, semantic analysis, content hashing, duplicate detection, or URL fetching has been implemented.

## Latest Completed Slice

The deterministic Work Arrangement experiment identifies explicit fully remote, hybrid, and on-site modes conservatively, including explicit alternatives. It preserves exact supporting source evidence with UTF-8 byte offsets, rule identity, and extractor version 1; unknown remains a distinct result. Results are recomputed rather than persisted and are displayed beside the preserved source. Focused domain/context/LiveView coverage and the full project verification pass.

## Next Intended Slice

Evaluate the Work Arrangement experiment against representative local postings and decide what product slice should follow. In particular, do not assume that gate configuration, persisted facts, or semantic verification comes next until the extractor's usefulness and failure modes have been reviewed.

## Future Possibility Already Identified

A later version may accept a source URL instead of pasted text, retrieve the job description from that page, and store the retrieved source text in `raw_description`. URL retrieval remains future scope and has not been designed or implemented.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- Gate configuration/evaluation and Screened Out navigation.
- Persisted extracted facts and generalized gate infrastructure.
- URL fetching.
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
- Working tree: clean after the Work Arrangement experiment is committed.
- Local `main` and `origin/main`: synchronized after the implementation commit is pushed.
