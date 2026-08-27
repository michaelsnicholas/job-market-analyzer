# Repository Instructions

These are standing instructions for Codex and other coding agents working in this repository.

## Required project orientation

Before proposing or modifying project code:

1. Read `docs/STATUS.md`.
2. Read `docs/PROJECT.md`.
3. Review ADRs under `docs/adr/` that are relevant to the area being changed.
4. Treat accepted decisions in those documents as the current project source of truth.
5. Do not rely on prior conversational memory when repository documentation provides the answer.

## Decision discipline

- Do not silently change an accepted product or architectural decision.
- If implementation appears to require changing an accepted decision, stop and explain the existing decision, why it appears inadequate or incompatible, the proposed change, and its consequences and tradeoffs.
- Wait for explicit approval before changing the decision or code that depends on it.
- Record significant accepted product or architectural decisions as ADRs when preserving their rationale and consequences will be useful.
- Do not create ADRs for routine implementation details.

## Documentation maintenance

- `docs/STATUS.md` is the concise snapshot of current project state, durable repository baseline, next intended work, open questions, and blockers. Keep it current and brief.
- `docs/PROJECT.md` is the canonical source of current product and architecture truth. Update it whenever an accepted change makes it inaccurate.
- Update current-state documentation in the same commit as the implementation change that makes it inaccurate.
- At the end of every meaningful completed development slice, update `docs/STATUS.md`.
- Do not turn `STATUS.md` or `PROJECT.md` into chronological diaries. Git history is the implementation history.

### Slice-completion documentation gate

Before a development slice is considered complete:

- Reconcile `docs/STATUS.md` with the final implementation so that it describes the durable project state expected after the commit.
- Reconcile `docs/PROJECT.md` whenever the slice changes current product or architecture truth.
- Review relevant ADRs for continued applicability or the need for a separately approved superseding ADR.
- Remove temporary implementation-plan, review, staging, pre-commit, and other transient process language from continuity documentation.
- Do not describe only the temporary state immediately before the commit; documentation included with the slice must remain accurate once that commit exists.

Ephemeral Git state belongs in verification and handoff reporting, not in version-controlled `STATUS.md`. Verify and report working-tree cleanliness, pending commit or push state, exact HEAD, ahead/behind counts, and remote synchronization when relevant, but do not store those mutable facts as project status.

After committing and, when authorized, pushing, check the continuity documentation once more against HEAD. Do not report a slice complete while a known continuity-document discrepancy remains.

## ADR discipline

- ADRs live in `docs/adr/`.
- Use them for significant decisions whose rationale and consequences will matter later.
- Once accepted, do not rewrite an ADR merely because the project changes direction.
- Record a reversal or material change in a new ADR that explicitly supersedes the earlier one.
- Do not retroactively create ADRs for every decision already recorded in `PROJECT.md` merely for completeness.

## Git and privacy discipline

- Keep commits focused and meaningful.
- Documentation associated with a change should normally be committed with that change.
- Do not commit personal job-description data, SQLite development databases, secrets, credentials, generated build output, or other local/private artifacts.
- Do not push implementation that contradicts documented accepted decisions.

## Project verification

- Follow the Phoenix and Elixir conventions already established by the generated application and its dependencies.
- Use the generated `mix precommit` alias at the end of implementation changes and fix failures before committing.
- For documentation-only changes, use proportionate lightweight checks rather than performing unnecessary environment changes.
