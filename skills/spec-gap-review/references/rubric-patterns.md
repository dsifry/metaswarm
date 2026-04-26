# Rubric Patterns

Always run the fixed core rubric from `SKILL.md` first. Do not replace it with a doc-specific scorecard.

Use the material below to choose `2-4` doc-type focus checks that deepen the review without breaking score comparability across runs.

## Cross-Cutting Patterns

Use these patterns across doc types when the document introduces new contracts, new commands, or multi-round revisions.

### Intra-Doc Consistency

Suggested focus checks:

- CLI flags and examples agree with the declared contract
- Type snippets agree with later pseudocode and tests
- Validation steps use the same filenames, paths, and commands named earlier
- Revision-log claims agree with the body of the document

Common failure modes:

- One section says `--seed`, later commands use `--seed-doi`
- A renderer example emits fields never added to the schema/type snippet
- A later work unit relies on a field the earlier type contract never introduced
- A revision log says a gap is fixed, but the body still contains the old contract

Typical path-to-100 upgrades:

- Pick one canonical flag/path/type spelling and use it everywhere
- Update all snippets when a contract changes, not just the prose summary
- Treat doc-vs-doc contradictions as real blockers when they would mislead implementation

### Producer → Carrier → Consumer Trace

Suggested focus checks:

- New counters have a producer
- New fields have a declared storage or return location
- Intermediate configs/types thread the value through every hop
- Final output/tests/renderers actually consume the value

Common failure modes:

- A field appears in `pipeline_health` output examples but has no producer
- A counter exists in initialization defaults but not in the type definition
- A state populates only a subset of the fields later rendered or asserted
- The final renderer or writer is never updated, so the field cannot surface

Typical path-to-100 upgrades:

- For every new field, name the producer, carrier, and consumer explicitly
- Use one canonical stats object instead of scattering related fields
- Verify output examples only mention values that the proposed code path can actually produce

### Command And Artifact Operability

Suggested focus checks:

- Commands match the current or newly declared CLI contract
- Artifact paths are writable, visible, and committable as claimed
- Validation steps can run in the repo as written
- Commit steps only reference repo-tracked artifacts

Common failure modes:

- Examples use renamed flags before the CLI contract is updated
- The document calls a path "repo-tracked" even though `.gitignore` excludes it
- Validation steps write to `/tmp` and later tell the implementer to `git add` the output
- Manual smoke tests use different commands than the earlier work-unit contract

Typical path-to-100 upgrades:

- Normalize all commands to one CLI shape
- Check `.gitignore` before calling any output path "tracked"
- Move summaries or reduced artifacts into real repo paths before commit steps

### Upstream Status Truthfulness

Suggested focus checks:

- Referenced design/spec/gate status matches the current source
- Companion-review conclusions are not silently overridden by the target doc
- Prerequisite beads/issues/PRs are in the state the doc claims

Common failure modes:

- A plan says a design is approved when the design still says "pending re-review"
- A revision log dismisses a prior finding without actually fixing the contract
- A prerequisite is described as complete when the tracker still says `open` or `in_progress`

Typical path-to-100 upgrades:

- Check the current status line of every upstream doc the plan relies on
- Check the latest sibling `-codexreview.md` when status claims are disputed
- Rewrite status language to match current repo truth, not a prior intention

### Critical-Only Reviews

Use when the user asks for blockers, correctness issues, or "not nitpicks."

Guidance:

- Prefer open `P0` and `P1` only
- Include `P2` only when it is factually wrong or blocks execution
- Compress praise and closed-gap recap
- Keep the scorecard, but let the findings stay short

### Coherent Design Choice Handling

Guidance:

- Do not keep re-raising a deliberate design tradeoff as an "open gap" if it is internally consistent, repo-aligned, and operationally workable
- Distinguish:
  - unsupported or contradictory design
  - consistent but arguable design choice
- If you disagree with the choice, note the tradeoff once and move on unless it creates a concrete implementation risk

## Implementation / Migration Docs

Suggested focus checks:

- Intra-doc consistency
- Producer → carrier → consumer trace for new fields
- CLI and command operability
- Artifact and git-tracking realism
- Upstream gate/status truthfulness
- Migration usefulness from the actual repo baseline

Common failure modes:

- Type snippets, pseudocode, and tests disagree on the same contract
- New telemetry fields lack a full thread-through path
- Validation commands use different flags than the stated CLI contract
- Commit steps reference ignored or non-repo artifacts
- The document starts from a richer baseline than the repo actually has

Typical path-to-100 upgrades:

- Add one canonical contract section and keep all examples aligned to it
- Trace each new field from producer to final consumer
- Make validation commands executable and committable as written
- Verify every upstream readiness claim against the referenced source
- Start migration steps from the current code and explicitly name prerequisites

## Strategy Docs

Suggested focus checks:

- API and data-source strategy
- Architecture realism
- Domain and search strategy
- Output and quality contract
- Phase plan and decision usefulness

Common failure modes:

- Future-state architecture written as current plan
- Volatile vendor facts treated as fixed design constants
- Domain tables assumed current but not maintained
- Phase plan starts from capabilities the repo does not have

Typical path-to-100 upgrades:

- Separate current state from target state explicitly
- Tie every phase to code or infra that already exists, or call out prerequisite work
- Replace static vendor claims with dated sources

## Memory / Knowledge-System Docs

Suggested focus checks:

- Memory model and taxonomy
- Schema and query correctness
- Multi-tenant and privacy design
- Operational feasibility
- Phase planning

Common failure modes:

- `user_id` missing on user-scoped tables
- SQL examples invalid for stated backend
- Privacy promises unsupported by schema
- “Same schema, different backend” claims that are not actually true

Typical path-to-100 upgrades:

- Make ownership, isolation, and retention rules explicit
- Validate sample queries against the real backend
- Show how migration and backfill work in the current system

## UX / API Contract Docs

Suggested focus checks:

- CLI UX realism
- Web API contract readiness
- Output schema alignment
- Graph/data contract realism
- Memory-informed UX realism
- Error, resume, and iteration model

Common failure modes:

- Unimplemented REST or SSE surface presented as current
- Canonical schema in docs diverges from `src/types`
- Optional exports or interactions promised but unsupported
- Resume, cancellation, or timeout claims assume persistence that does not exist

Typical path-to-100 upgrades:

- Point every contract claim to a canonical schema or type location
- Specify failure and retry behavior, not just happy paths
- Separate aspirational UX from supported UX

## Infrastructure / Deployment Docs

Suggested focus checks:

- Repo and project-structure alignment
- Storage and database realism
- Auth and deployment readiness
- Observability and operations planning
- Cost and external dependency accuracy

Common failure modes:

- Fictional directories, scripts, or deploy assets
- Database or auth plan depends on missing runtime layers
- Pricing and quotas stale
- Local and production behavior conflated

Typical path-to-100 upgrades:

- Validate every named script, directory, and deploy artifact in the repo
- Describe missing runtime layers as prerequisites instead of assuming them
- Date-stamp vendor cost and quota claims

## Long-Lived / Background-Agent Docs

Suggested focus checks:

- Durable execution design
- Background-agent architecture
- Self-improvement loop
- Prerequisite and schema realism
- Migration usefulness

Common failure modes:

- Migration starts from a richer imagined baseline than the actual code
- Checkpointing or job plans assume missing primitives
- Self-improvement claims have no instrumentation or prompt/runtime hooks
- Cross-doc schema assumptions are already false

Typical path-to-100 upgrades:

- Anchor long-running claims to actual persistence and recovery primitives
- Show what instrumentation exists versus what must be added
- Break “self-improvement” into concrete measurable loops

## Report Skeleton

Use this structure unless the user requests something else:

1. `Round status`
2. `Executive summary`
3. `Rollups`
4. `Core scorecard`
5. `Gap tracker`
6. `Detailed findings by rubric area`
7. `Prioritized issue list` (`P0`-`P3`)
8. `Path to 100`
9. `Recommended next actions`

Keep the tone critical and implementation-facing.
