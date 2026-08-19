# Project Status

## Current State

- The Phoenix application `job_market_analyzer` has been generated as a conventional Phoenix 1.8 application using server-rendered LiveView and SQLite through Ecto.
- The first product slice is implemented: a durable local job-description corpus backed by SQLite.
- Users can capture a job with optional Company, Role, and Source URL plus a required raw description; list saved jobs; view complete preserved source text; and hard-delete an accidental entry with confirmation.
- Product LiveViews use the `JobMarket` context rather than accessing `Repo` directly.
- The public repository is [michaelsnicholas/job-market-analyzer](https://github.com/michaelsnicholas/job-market-analyzer), with `main` as its default branch.
- No analysis, content hashing, duplicate detection, or URL fetching has been implemented.

## Latest Completed Slice

The durable intake foundation adds the `jobs` migration and schema, the `JobMarket` context, LiveView intake/list and detail screens, confirmed hard deletion, and context/LiveView coverage. Submitted raw descriptions are stored without trimming or normalization; trimming is used only to reject blank input. Persistence was verified across a Phoenix server restart with a temporary synthetic record that was removed afterward.

## Next Intended Slice

Decide and plan the first genuine analysis slice using representative job descriptions. The accepted direction is an end-to-end, zero-cost path from saved source to validated, versioned, persisted analysis displayed beside the source. Whether transparent deterministic extraction precedes or accompanies a local semantic mechanism remains deliberately unresolved.

## Future Possibility Already Identified

A later version may accept a source URL instead of pasted text, retrieve the job description from that page, and store the retrieved source text in `raw_description`. URL retrieval remains future scope and has not been designed or implemented.

## Explicitly Not Implementing Yet

- Semantic or AI analysis and local LLM integration.
- URL fetching.
- User accounts, authentication, or hosted multi-user architecture.
- Cross-job analytics.
- Embeddings or vector search.
- Résumé matching.
- Background queues or distributed workers.

See `docs/PROJECT.md` for the complete scope boundaries and deferred concerns.

## Open Questions / Blockers

- Which initial structured analysis fields prove useful on representative job descriptions?
- Should the next experiment begin with deterministic extraction, a local semantic mechanism, or a deliberately combined comparison?

These are product decisions for the next slice, not blockers in the completed intake foundation.

## Repository State

- Branch: `main`.
- Working tree: clean after the durable intake slice is committed.
- Local `main` and `origin/main`: synchronized after the durable intake slice is pushed.
