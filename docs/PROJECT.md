# Job Market Analyzer: Product and Architecture Decisions

This document is the durable project memory for human and coding-agent collaboration. It records accepted product and architectural decisions, future possibilities, deferred decisions, and explicit scope boundaries. It contains no personal job-search data, credentials, secrets, private company information, or API keys.

> **Agent continuity rule:** Accepted product and architectural decisions must not be changed implicitly during implementation. If an implementation appears to require changing an accepted decision, stop and propose the change before modifying either the decision or code that depends on it.

> **Future Codex sessions should read `docs/PROJECT.md` before proposing or implementing project changes.**

## Documentation Map

### `STATUS.md` — Current state and next step

Start here. This is a short, continuously updated snapshot of what is currently implemented, the latest completed slice, repository state, next intended work, open questions, and blockers.

### `PROJECT.md` — Current product and architecture source of truth

This document is the canonical description of the product as it currently exists: its purpose, scope, accepted decisions, architecture boundaries, principles, and explicitly deferred work. Update it when the current truth changes; do not use it as a historical diary.

### `adr/` — History and rationale for significant decisions

ADRs preserve important product or architectural decisions whose rationale and consequences will be valuable later. When a significant accepted decision changes, create a new ADR that supersedes the earlier one instead of rewriting history. Routine implementation choices do not require ADRs, and existing decisions need not be converted into retroactive ADRs merely for completeness.

### Git history — Implementation history

Git is the factual record of what changed in the repository and when. Commits support this documentation but are not a substitute for understanding current product state.

Keep `STATUS.md` concise and update it after every meaningful completed slice. Keep `PROJECT.md` accurate whenever accepted product or architecture truth changes. Documentation made inaccurate by an implementation change should be updated in the same commit as that implementation.

## Project identity and current implementation

- Phoenix application and OTP name: `job_market_analyzer`
- Base Elixir module: `JobMarketAnalyzer`
- GitHub repository: `job-market-analyzer`
- Primary future domain context: `JobMarket`
- Repository visibility: public
- Default branch: `main`
- Architecture: conventional single Phoenix application, not an umbrella
- UI: server-rendered Phoenix LiveView
- Local persistence: SQLite through Ecto

The application name and the future domain context name are intentionally distinct. `JobMarket` describes the domain as a growing body of job-market evidence rather than a generic job board.

The durable corpus foundation is implemented. It contains the `JobMarket` context, a `Job` source schema, SQLite migration, LiveView intake/list and detail screens, and confirmed hard deletion. It does not contain analysis, AI integration, URL fetching, content hashing, or duplicate detection.

## Product purpose

Job Market Analyzer is a local-first tool for accumulating and eventually analyzing job descriptions. Its long-term purpose is to help someone understand what employers in a target field are actually buying by examining multiple real postings over time and identifying recurring:

- capabilities;
- must-have requirements;
- nice-to-have requirements;
- technologies and tools;
- specialized or domain knowledge;
- experience patterns;
- functional domains;
- industries;
- evidence employers expect candidates to demonstrate;
- ambiguities and other useful job-market signals.

One example is a person trying to enter a technical field who wants evidence about which skills recur across actual postings rather than relying on impressions from a few jobs.

## Local-first product

The initial application runs locally on the user's computer. Captured jobs must eventually use durable persistence: records saved today must remain after the Phoenix process stops and restarts. Temporary LiveView or other in-memory state does not satisfy this requirement.

Someone cloning the public repository must be able to run an independent local copy and accumulate an independent collection. Personal job data must not be committed to or distributed through Git. Migrations, schemas, application code, and setup documentation belong in the repository; local database files and runtime artifacts do not.

## Persistence decision: SQLite

SQLite is the accepted database for the local-first application because it provides:

- durable relational storage;
- no separate database server requirement;
- natural independence between local clones;
- Ecto migrations and schemas;
- a reasonable future path to PostgreSQL.

SQLite and PostgreSQL are not interchangeable. A future hosted migration will require real implementation work and testing. Use conventional Ecto patterns and avoid unnecessary SQLite-specific assumptions where practical, without pretending that all database behavior is portable.

## Future hosted possibility

If the local application proves useful, it may eventually become a hosted multi-user application. That future version might include:

- user accounts and authentication;
- per-user private job collections;
- PostgreSQL or another production database;
- import/export and migration of locally accumulated data;
- aggregate analysis across each user's corpus.

These are possibilities, not current requirements. Do not implement them now. In particular, do not add speculative `user_id`, tenant, organization, team, role, permission, or authentication fields merely because they may eventually exist. Preserve a reasonable evolution path through sound current boundaries rather than simulating a hosted SaaS prematurely.

## Job source record

The durable job record distinguishes source data from future derived analysis. Its source inputs are:

- `raw_description` — required;
- company — optional;
- role — optional;
- source URL — optional.

Company and role must not be required merely because they are useful. A job must remain capturable when they are unknown or omitted. Source URL belongs in the first intake slice because it provides useful provenance.

Users can hard-delete an accidentally captured job with confirmation. Editing and soft-delete/archive infrastructure are not part of the current implementation.

### Possible future URL intake

A later version may accept a source URL instead of manually pasted text, fetch and extract the description, and store the resulting source text in `raw_description`. URL fetching is not currently authorized.

Multiple future intake mechanisms should converge on the same durable source record. Downstream domain and analysis logic should not need to know whether source text was pasted or acquired from a URL.

### Raw source preservation

The original description is durable source evidence. Derived analysis must remain separate and must never silently overwrite or progressively decorate the source record.

The accepted principle is:

> Never silently overwrite the evidence on which an analysis was based.

Raw descriptions have not been declared literally immutable forever. A future editing feature might create a source revision, invalidate analyses, supersede an earlier source, or require reanalysis. Exact editing and revision behavior is deferred until a real need exists. The first product slice may avoid editing and use delete/re-enter.

## Application architecture

Use a conventional single Phoenix application with server-rendered LiveView. The intended flow is:

```text
LiveView UI
→ domain/context layer
→ Ecto schemas / Repo
→ SQLite
```

The primary domain context for job-market functionality is `JobMarket`.

LiveViews should call the `JobMarket` context and should not access `Repo` directly. `Repo` is responsible for persistence. Domain decisions belong in the context and supporting domain modules.

Do not introduce a generic service layer, command bus, event system, dependency-injection framework, umbrella architecture, or ceremonial interfaces solely for abstraction. Prefer ordinary Phoenix contexts, modules, Ecto transactions, and explicit function calls until actual requirements justify more.

## Source and analysis architecture

The central architectural principle is:

> Preserve durable source separately from evolving derived analysis.

The intended evolution is:

```text
preserved source
→ versioned structured analysis
→ evidence-driven relational normalization
```

Historical source underlying an analysis must remain recoverable. This principle does not impose a specific future editing UX.

The accepted conceptual pipeline separates artifacts and decisions with different meanings and lifecycles:

```text
raw job source
→ deterministic fact extraction
→ user-configured gate evaluation
→ semantic verification
→ full analysis
```

Extracted facts describe the posting, not the user's preferences, and useful facts may be extracted whether or not a corresponding gate is enabled. Gate configuration represents mutable user preferences. Gate evaluation compares facts with current preferences using the conceptual states `PASS`, `FAIL`, `UNKNOWN`, and `NOT_APPLICABLE`, where `NOT_APPLICABLE` means the gate is disabled.

Deterministic extraction must be conservative and inspectable: assert a fact only from sufficiently explicit evidence, otherwise return unknown. It must not manufacture pseudo-confidence scores. Ambiguous or contradictory evidence should normally remain unknown unless a narrow, transparent, tested precedence rule resolves it. All enabled deterministic gates should eventually run so their complete results can be inspected rather than stopping evaluation at the first failure.

Under the current architectural direction, a deterministic failure prevents automatic progression to semantic processing, but it does not delete or permanently classify the job. Screened Out is a derived view over current effective evaluations, not an authoritative status stored on the source. Preference changes may change current eligibility without modifying source-derived facts or destroying existing semantic/full analysis. Human reconsideration and override are intended but not yet designed.

Semantic verification is distinct from deterministic extraction. Deterministic `PASS` and `UNKNOWN` may both require contextual verification. Semantic verification should add separate contextual judgments where practical rather than rewrite a correct deterministic fact. The exact policy for combining semantic results remains deferred.

Full analysis is a later, richer stage than narrow semantic verification. The architecture may eventually use progressively different computational tiers while the current phase remains zero-cost and local. Stable boundaries should be application-owned capability and input/output contracts, not provider assumptions. Do not add generic provider behaviours, registries, adapters, or switching infrastructure before concrete implementations justify them. See [ADR-001](adr/001-separate-analysis-stages-and-derive-screening.md) for the rationale and consequences of these boundaries.

Analysis must not become dozens of nullable columns on the `jobs` table. When analysis is implemented, the likely design is separate, versioned analysis records or runs associated with the source job. A future run may need information resembling:

- job/source reference;
- status;
- analyzer implementation;
- analyzer, model, or prompt version;
- analysis schema version;
- validated structured result;
- generation timestamp;
- failure or error information.

No `analysis_runs` implementation is authorized yet. The design is recorded to prevent source and evolving analysis from being casually merged into one mutable record.

### Analysis history

Preserving analysis history is valuable because schemas, prompts, models, and deterministic analyzers will change, and because this project may itself become an experiment in model behavior. Reanalysis should eventually be capable of creating a new run without destructively overwriting earlier results.

### Early analysis representation

Early structured results may reasonably use versioned JSON/maps while the useful schema is being discovered. Do not create relational tables for every tentative field or concept. Once usage demonstrates that technologies, capabilities, requirements, aliases, or other concepts are stable and need cross-job queries, promote them into normalized relational structures through migrations.

The accepted progression is:

```text
source
→ versioned structured JSON
→ normalization justified by actual usage
```

## Zero-cost semantic analysis

The project must initially remain zero-cost to operate locally. Do not assume access to OpenAI, Anthropic, another paid model API, paid cloud infrastructure, or any other paid service.

Semantic analysis is expected eventually, but no model or runtime has been selected. Ollama is one plausible local runner that has been discussed; it has not been chosen. Before selecting a local model/runtime, evaluate:

- quality on real job descriptions;
- structured-output reliability;
- Apple Silicon memory requirements;
- latency;
- installation burden;
- model and license implications.

Do not install a local LLM in the baseline or foundation slice.

## Semantic reasoning versus deterministic logic

Maintain a deliberate separation between semantic inference and work that ordinary Elixir or SQL can perform reliably.

### Appropriate for semantic reasoning later

- Inferring the core capability an employer is buying.
- Distinguishing must-have from nice-to-have when prose is ambiguous.
- Classifying functional domain or industry from context.
- Identifying implicit domain knowledge.
- Interpreting what evidence or experience the employer expects.
- Explaining ambiguities or unusual signals.
- Proposing equivalence between differently worded requirements.
- Extracting company or role when formatting is inconsistent and the user did not supply it.

Semantic outputs are evidence-backed candidates and inferences, not unquestionable facts.

### Appropriate for deterministic Elixir and SQL

- Counting jobs containing a normalized concept.
- Percentages, rankings, trends, and co-occurrence.
- Hashing and deduplication, if later approved.
- Explicit numeric, date, and URL parsing.
- Explicit salary-range parsing.
- Filtering and sorting.
- Selecting the latest successful analysis.
- Comparing analysis versions.
- Validation.
- Casing and whitespace normalization.
- Applying aliases that have already been approved.

For example, if RTOS appears in 37 of 50 jobs, application/database logic should calculate that; an AI model should not count it again.

### Hybrid concept normalization

A likely future workflow is:

1. Semantic analysis proposes a concept with supporting source evidence.
2. Deterministic code maps known aliases to canonical concepts.
3. Unknown concepts remain reviewable candidates.
4. User-confirmed mappings may become deterministic rules.

This avoids repeatedly spending semantic reasoning on a normalization problem already solved while avoiding a premature ontology.

## Evidence and epistemic discipline

Semantic analysis should preserve supporting source evidence wherever practical. An extracted requirement or inferred capability should be able to carry an excerpt, source span, or other traceable evidence. The system should distinguish what the employer actually said from what the analyzer inferred.

Application code must validate AI output before treating it as a successful structured analysis. Invalid model output must not be silently accepted.

## Planned implementation slices

### Completed foundation slice: durable corpus

The first product implementation is complete:

```text
capture → persist → list → view → delete
```

It includes:

- optional company;
- optional role;
- optional source URL;
- required raw description;
- durable SQLite persistence;
- delete confirmation;
- personal database exclusion from Git;
- tests;
- persistence verification across a server restart.

This is a durable corpus foundation, not the semantic-analysis product. Move through it relatively quickly rather than spending days polishing generic CRUD before testing the core analysis idea.

### Next slice: deterministic Work Arrangement experiment

The first pre-analysis experiment establishes one narrow path:

```text
saved raw job description
→ deterministic Work Arrangement extraction
→ known or unknown result
→ normalized explicitly available arrangement mode(s)
→ supporting evidence
→ display on the existing job detail view
```

Work Arrangement represents distinct employment modes explicitly available for the role: `fully_remote`, `hybrid`, and `on_site`. A posting may offer more than one mode, but hybrid is itself a mode; language describing hybrid as a combination of office and remote work does not imply that fully remote and fully on-site employment are separately available.

The experiment will use a versioned plain Elixir domain result recomputed from `raw_description`, not a persisted entity. Known and unknown are distinct result states; unknown is not an arrangement value. Positive results preserve exact supporting evidence and rule identity, with source offsets when they remain straightforward and proportionate. Arrangement sets use stable ordering at display or serialization boundaries. Representative sanitized regression examples based on real posting language will test the extractor.

Narrow deterministic scope or precedence rules are acceptable when transparent and testable, such as explicit structured role metadata or explicit role-directed statements. General document-level semantic interpretation is outside deterministic v1. Contradictory evidence normally produces unknown unless a narrow tested rule safely resolves it.

This slice does not include persistence, migrations, gate settings or evaluation, Screened Out navigation, semantic verification, overrides, generalized gate infrastructure, or model/runtime integration. Its purpose is to test whether conservative deterministic Work Arrangement extraction is useful and reliable enough to justify further architecture.

### Later semantic analysis

After the deterministic experiment and separately approved screening work, establish a zero-cost semantic path with application-owned structured contracts, validation, versioned persisted results, and display alongside source. Choose the exact schema, model, and runtime using representative source examples rather than bootstrap assumptions.

## Deferred duplicate detection

A SHA-256 content fingerprint has been proposed for duplicate detection, integrity, and identifying repeated source text. It has not been approved for the first schema. Do not add it merely because it is inexpensive or theoretically useful; duplicate detection and hashing remain deferred until explicitly approved.

## Boundaries that matter now

- Use Phoenix contexts as domain boundaries.
- Keep LiveViews away from direct `Repo` access.
- Retain source independently of analysis.
- Use Ecto migrations.
- Keep database configuration environment-specific.
- Keep personal database files out of Git.
- Use ordinary IDs and timestamps compatible with future migration.
- Keep semantic analysis behind an application/module boundary.
- Validate semantic output before persistence.
- Preserve supporting source evidence.
- Test domain behavior rather than SQLite implementation details.
- Do not assume that a job is owned by a user yet.

These boundaries preserve options; they do not simulate the hosted product before it exists.

## Explicitly deferred and out of scope

Do not design or implement the following until separately approved:

- user accounts, authentication, or authorization;
- organizations, teams, roles, permissions, tenancy, or speculative `user_id`;
- PostgreSQL deployment topology or cloud hosting;
- queues or distributed workers;
- APIs;
- subscriptions or billing;
- encrypted multi-user storage;
- collaboration or mobile clients;
- embeddings or vector databases;
- model-provider switching infrastructure;
- prompt-management platforms;
- automatic taxonomies or elaborate skill/technology ontologies;
- model fine-tuning or agentic tool use;
- high-volume scaling or audit/compliance systems;
- URL scraping or fetching;
- résumé matching;
- cross-job recommendations.

The following gate and analysis details also remain provisional or deferred:

- a generalized gate catalog or framework;
- the final Work Arrangement phrase and rule catalog;
- generalized extracted-fact persistence;
- gate preference and evaluation history;
- human override semantics;
- semantic result-combination policy;
- Salary screening and currency handling;
- geographic eligibility and visa/work-authorization verification;
- materialized workflow or Screened Out projections;
- deterministic `UNKNOWN` behavior after screening exists but before semantic verification exists;
- the meaning or validity of an enabled gate with no accepted values.

Import/export is a plausible future bridge from local to hosted usage, but its format is deferred until the data schema stabilizes.

## Repository practices

The public repository is both application source and durable project memory. Use `main` because it is the contemporary convention for new GitHub repositories and reduces surprise; no material technical distinction from `master` is claimed.

Work should proceed in small, meaningful vertical slices. After each working increment, run appropriate verification and make a focused Git commit rather than accumulating a large unreviewed change.

Never commit personal job data, credentials, tokens, private company information, API keys, or other material that should not be public.

## Current implementation boundary

The current application is limited to the generated Phoenix foundation and the durable source corpus: capture, persist, list, view, and confirmed hard delete. The staged gate/analysis architecture is documented but no extraction, gate, screening, semantic, or full-analysis functionality exists. The next implementation boundary is the separately approved deterministic Work Arrangement extraction/display experiment; do not expand it into deferred gate or analysis functionality without explicit approval.
