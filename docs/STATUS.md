# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can capture a job with optional Company, Role, and Source URL plus a required raw description; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The staged gate/analysis architecture is accepted: preserved source, deterministic facts, mutable preferences, gate evaluation, semantic verification, and full analysis have distinct responsibilities and lifecycles. Screened Out will be derived from current evaluations rather than stored as permanent job state.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- No fact extraction, gate configuration/evaluation, screening, semantic analysis, content hashing, duplicate detection, or URL fetching has been implemented.

## Latest Completed Slice

The durable intake foundation adds the `jobs` migration and schema, the `JobMarket` context, LiveView intake/list and detail screens, confirmed hard deletion, and context/LiveView coverage. Submitted raw descriptions are stored without trimming or normalization; trimming is used only to reject blank input. Persistence was verified across a Phoenix server restart with a temporary synthetic record that was removed afterward.

## Next Intended Slice

Implement a focused deterministic Work Arrangement experiment: recompute a versioned plain Elixir result from each saved `raw_description`, distinguish known arrangements from unknown, preserve exact evidence and rule identity, and display the result on the existing job detail view. The candidate modes are fully remote, hybrid, and on-site; hybrid remains its own mode. The experiment adds no persistence, gate settings/evaluation, Screened Out UI, semantic verification, overrides, generalized gate infrastructure, or model integration.

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

No blocker prevents the scoped Work Arrangement experiment once implementation is explicitly authorized. Final extraction rules remain experimental. General gate design, deterministic `UNKNOWN` behavior during future screening, empty accepted-value behavior, semantic result combination, override semantics, fact persistence, and model/runtime selection remain deferred.

## Repository State

- Branch: `main`.
- Working tree: clean after the gate/analysis architecture documentation is committed.
- Local `main` and `origin/main`: synchronized after the documentation commit is pushed.
