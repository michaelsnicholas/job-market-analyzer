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

The durable corpus foundation is implemented. It contains the `JobMarket` context, a `Job` source schema, SQLite migrations, LiveView intake/list and detail screens, and confirmed hard deletion. A deterministic Work Arrangement extraction and gate-evaluation experiment is implemented with one durable local preference and derived evaluation displayed on the detail screen. URL intake has guarded public-source fetching, structured/generic/plain-text extraction into transient reviewable drafts, a trusted context contract for persisting reviewed drafts with provenance, and a LiveView review/save workflow. The application does not contain generalized gate infrastructure, persisted extracted facts or evaluations, semantic analysis, AI integration, content hashing, or duplicate detection.

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

### Accepted URL-first intake architecture

URL-first intake will coexist with manual source capture. Retrieval is a pre-persistence acquisition layer:

```text
source URL
→ guarded acquisition
→ extraction
→ reviewable intake draft
→ user review or correction
→ Job creation
```

Retrieval must never directly create a Job. It proposes available Company, Role, final URL, source text, acquisition details, and warnings for review. The user may correct Company, Role, and source text before saving. If retrieval fails or is inadequate, manual paste remains immediately available.

The user may supply any public job-posting URL and is not expected to find a canonical employer or ATS source. V1 will prefer usable `JobPosting` structured data, fall back to conservative generic HTML extraction, and rely on human review as the final completeness boundary. Source-specific handling remains internal. Initial ATS-specific adapters, a generic adapter framework, canonical-source discovery, headless-browser rendering, authenticated scraping, and anti-bot circumvention are deferred.

Manual and URL-derived intake converge on the same durable source record. Downstream deterministic and semantic analysis must not depend on how source text was acquired. See [ADR-002](adr/002-use-reviewed-url-acquisition-and-pin-outbound-destinations.md) for the decision and tradeoffs.

### Raw source preservation

`raw_description` is the exact textual evidence approved by the user when the Job is saved. For manual intake it is the submitted text. For URL-derived intake it is the retrieved and extracted text after any user correction, so it is not necessarily a verbatim copy of the upstream webpage. Derived analysis must remain separate and must never silently overwrite or progressively decorate this source evidence.

The accepted principle is:

> Never silently overwrite the evidence on which an analysis was based.

Raw descriptions have not been declared literally immutable forever. A future editing feature might create a source revision, invalidate analyses, supersede an earlier source, or require reanalysis. Exact editing and revision behavior is deferred until a real need exists. The first product slice may avoid editing and use delete/re-enter.

V1 does not retain fetched raw HTML or full HTTP response bodies. Lightweight acquisition provenance is stored directly on the Job as `source_url`, `final_source_url`, `source_acquired_at`, `source_acquisition_method`, `source_extractor_version`, and `source_text_modified`. Acquired methods distinguish structured `JobPosting`, structured `JobPosting` reconciled conservatively with a uniquely anchored server-rendered DOM continuation, generic HTML, and plain-text extraction. Manual creation always records the manual method and empty acquisition details even when the user supplies a source URL. URL-acquired creation accepts provenance only from a trusted transient Draft, while Company, Role, and the final approved source remain user-controlled. `source_text_modified` is calculated through exact comparison with the originally extracted text. Raw response history, arbitrary persisted warning prose, generic provenance documents, source revisions, and Company/Role suggestion provenance are not part of v1. A separate source-capture model remains deferred until multiple sources, recapture, comparison, history, or monitoring creates a concrete lifecycle need.

### Guarded outbound acquisition

URL retrieval introduces an SSRF and resource-safety boundary that must be present from its first implementation. Every outbound hop must validate the logical URL, resolve and classify all returned IPv4 and IPv6 destinations, reject any destination that violates public-address policy, select an approved public address, and connect to that exact address without a second uncontrolled DNS resolution. The original hostname is retained only for TLS certificate verification, SNI, and HTTP identity.

V1 permits HTTPS on port 443 and HTTP on port 80, preferring HTTPS. Redirects must be bounded and repeat the complete URL, DNS, and address validation process. Retrieval must also enforce request and connection timeouts, bounded network and decompressed sizes, accepted content types, safe URL logging, and untrusted-content handling. It sends no browser credentials or cookies, fetches no subresources, executes no scripts, and never renders fetched HTML as active content.

The application-owned guarded acquisition primitive uses the existing Req/Finch/Mint stack and `inet_cidr` for CIDR containment math. It validates both address families, rejects a hostname if any resolved address violates the public-address policy, pins each request to a selected numeric address, handles redirects itself, and bounds time, network bytes, decompressed bytes, media types, and content encodings. It returns transient application-owned result or error data and does not create or update a Job. SafeURL and Paraxial are not adopted for this boundary.

Bounded fetch results may now be converted into transient application-owned drafts. Extraction uses Floki to prefer usable `JobPosting` JSON-LD from HTML or direct JSON, conservatively reconciles a uniquely anchored structured description with a coherent substantive DOM continuation when one is unambiguous, and otherwise falls back to conservative generic HTML content selection. Draft text is readable rather than raw HTML; metadata remains a suggestion with deterministic provenance; warnings and inadequate/ambiguous failures use stable application codes. The initial editable source and retained original extracted text are identical. Fetching and extraction do not persist a draft or create a Job. A separate context operation can persist user-approved values with trusted Draft provenance, and human review remains the completeness boundary.

The LiveView intake begins with URL acquisition plus a secondary manual-entry path while the saved corpus remains visible. URL fetching runs asynchronously. A successful Draft is retained only in server-side LiveView state and populates an editable review form; its requested URL is read-only, and the user explicitly saves through the acquired context contract. Browser parameters cannot choose or override trusted acquisition provenance. A failed acquisition creates no Job and reveals manual entry with the attempted URL as an ordinary reference. Cancel/start over discards transient state, and unsaved Drafts are not persisted or restored after a process restart.

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

Extracted facts describe the posting, not the user's preferences, and useful facts may be extracted whether or not a corresponding gate is active. Gate configuration represents mutable user preferences. Deterministic gate evaluation does not guess: `PASS` means explicit evidence establishes a fact matching an accepted mode, `FAIL` means explicit evidence establishes a fact matching none of the accepted modes, `UNKNOWN` means explicit evidence is insufficient to establish the fact reliably, and `NOT_APPLICABLE` means no accepted modes are currently active. `UNKNOWN` is a routing state intended for future semantic verification, not an invitation to make deterministic extraction increasingly inferential.

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

### Implemented experiment: deterministic Work Arrangement extraction and evaluation

The first pre-analysis experiment establishes one narrow path:

```text
saved raw job description
→ deterministic Work Arrangement extraction
→ known or unknown result
→ normalized explicitly available arrangement mode(s)
→ supporting evidence
→ saved local Work Arrangement preference
→ derived PASS / FAIL / UNKNOWN / NOT_APPLICABLE evaluation
→ display on the existing job detail view
```

Work Arrangement represents distinct employment modes explicitly available for the role: `fully_remote`, `hybrid`, and `on_site`. A posting may offer more than one mode, but hybrid is itself a mode; language describing hybrid as a combination of office and remote work does not imply that fully remote and fully on-site employment are separately available.

The implementation uses a versioned plain Elixir domain result recomputed from `raw_description`, not a persisted entity. Known and unknown are distinct result states; unknown is not an arrangement value. Positive results preserve exact supporting evidence, rule identity, and exclusive-end UTF-8 byte offsets into the original source. Arrangement sets use stable ordering at display boundaries. Sanitized regression examples based on representative posting language define the executable behavior.

Narrow deterministic scope or precedence rules are acceptable when transparent and testable, such as explicit structured role metadata or explicit role-directed statements. General document-level semantic interpretation is outside deterministic v1. Contradictory evidence normally produces unknown unless a narrow tested rule safely resolves it.

Work Arrangement preference is stored as one dedicated singleton SQLite record with a disclosure-visibility flag and explicit booleans for fully remote, hybrid, and on-site. A missing record behaves as hidden with no modes selected. The disclosure control only shows or hides the subordinate options; screening becomes applicable only when the control is open and at least one mode is selected. Opening it with no modes is valid and remains `NOT_APPLICABLE`. Hiding it preserves subordinate selections while making them inactive. Preference changes persist immediately without a separate save action. This is a focused local preference, not a generic settings or gate framework.

The extracted fact and evaluation are recomputed rather than persisted. A known fact passes when at least one explicitly offered mode is accepted and fails when none is accepted. An unknown fact remains `UNKNOWN`; no active modes produces `NOT_APPLICABLE`. The Saved jobs list is a derived projection that hides only current deterministic failures while retaining `PASS`, `UNKNOWN`, and `NOT_APPLICABLE` jobs. Preference changes immediately recompute that projection; hidden jobs are not deleted, modified, archived, or permanently classified. The detail page displays the evaluation, fact, active accepted modes, and existing deterministic evidence. The experiment does not include a separate Screened Out view, semantic verification, overrides, additional gates, generalized gate infrastructure, or model/runtime integration.

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
- résumé matching;
- cross-job recommendations.

The following URL-acquisition capabilities also remain deferred:

- dedicated ATS adapters or a generic adapter/plugin framework;
- headless-browser rendering, authenticated scraping, and CAPTCHA or anti-bot circumvention;
- canonical employer-source discovery;
- source recapture, history, comparison, monitoring, and post-save source editing.

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
- behavior that routes deterministic `UNKNOWN` results into an implemented semantic stage.

Import/export is a plausible future bridge from local to hosted usage, but its format is deferred until the data schema stabilizes.

## Repository practices

The public repository is both application source and durable project memory. Use `main` because it is the contemporary convention for new GitHub repositories and reduces surprise; no material technical distinction from `master` is claimed.

Work should proceed in small, meaningful vertical slices. After each working increment, run appropriate verification and make a focused Git commit rather than accumulating a large unreviewed change.

Never commit personal job data, credentials, tokens, private company information, API keys, or other material that should not be public.

## Current implementation boundary

The current application includes the generated Phoenix foundation, the durable source corpus, the deterministic Work Arrangement extraction and derived gate-evaluation experiment with one dedicated durable local preference and FAIL-only Saved jobs filtering, guarded public-source fetching, transient structured/generic/plain-text source-draft construction, trusted context-level persistence of reviewed drafts with Job provenance, and the LiveView URL acquisition/review/save workflow alongside manual capture. The application has no generalized gate infrastructure, persisted facts or evaluations, separate Screened Out view, semantic verification, or full analysis. Do not expand these boundaries into deferred functionality without explicit approval.
