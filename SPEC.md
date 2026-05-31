# Repository-Level Specification

> This document captures repository-wide policies that span more than one
> sub-project. Sub-project specifications live in each sub-project's own
> `SPEC.md` (for example,
> `quality-tools/powershell-static-analyzer/SPEC.md` and
> `scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`).
>
> This file is **English only**, per the repository-wide documentation
> language policy declared in [`README.md`](./README.md#language-policy).

## Conventions (RFC 2119)

This document uses the keywords MUST, MUST NOT, SHOULD, SHOULD NOT, and
MAY as defined in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174). When the keywords
appear in lowercase or in plain English (e.g., "should", "must"), they
carry the same normative meaning.

## For AI / LLM agents reading this file

You are reading the repository-level specification. If you are about to
make a change to any continuous-integration (CI) artifact in this
repository (anything under `.github/workflows/`, the
`PSScriptAnalyzerSettings.psd1` files, or this `SPEC.md` itself), you
MUST first:

1. Read this entire `SPEC.md`, in particular §2 (Design Principles), §3
   (Naming Conventions), §4 (Timeout Policy), and §9 (CI Change History
   Location).
2. Locate the change history. CI workflow changes MUST be recorded in
   the CI-target script's own `CHANGELOG.md` — never in a separate
   `.github/workflows/CHANGELOG.md` file (none exists, and creating one
   is forbidden; see §9).
3. Check whether the change crosses a `[SPEC-CI-NNN]` policy boundary.
   If it does, update the relevant `[SPEC-CI-NNN]` section in this file
   in the same change set so the policy text stays in sync with the
   workflow it describes.

If your task is unrelated to CI, you do not need to read further; this
specification governs CI only.

A machine-readable summary of every policy is available in §10 (Quick
reference for AI agents).

## Policy Index (Quick reference)

| Policy ID | Title | Section |
|:---:|:---|:---|
| SPEC-CI-001 | VM-based aggregation principle | §2.1 |
| SPEC-CI-002 | Workflow boundaries by VM | §2.2 |
| SPEC-CI-003 | Serial execution as default | §2.3 |
| SPEC-CI-004 | Manual override via `workflow_dispatch` | §2.4 |
| SPEC-CI-005 | Quality gate semantics | §2.5 |
| SPEC-CI-010 | Filename convention (`__` separator) | §3.1 |
| SPEC-CI-011 | STAGE terminology | §3.2 |
| SPEC-CI-020 | 3-tier timeout policy | §4 |
| SPEC-CI-030 | Fork PR handling | §5 |
| SPEC-CI-040 | Branch protection (future) | §6 |
| SPEC-CI-050 | `workflow_run` depth limit (3 hops) | §7 |
| SPEC-CI-060 | Supply chain security (future, 7 candidates) | §8 |
| SPEC-CI-070 | CI change history location | §9 |
| SPEC-CI-080 | Repository security baseline | §11 |
| SPEC-CI-081 | Artifact content minimization | §12 |

## §1. Scope

This specification covers:

- CI workflow design across all sub-projects in this repository.
- Naming conventions for workflow files, jobs, and steps.
- Timeout discipline.
- Fork PR handling and review protocol.
- The location of CI-related change history.
- Future security considerations that are out of scope of the initial
  CI implementation but documented here as a roadmap.

The specification does NOT cover:

- Per-rule semantics of any static analyzer used by CI. Those live in
  each tool's own `SPEC.md` (for example, `psa.py`'s rule catalog is in
  `quality-tools/powershell-static-analyzer/SPEC.md` §4).
- Behaviour of the scripts that CI exercises. Those live in each
  script's own `SPEC.md` (for example, Speaker Deck downloader
  invariants are in
  `scripts/powershell/download-speakerdeck-oracle4engineer/SPEC.md`).
- Non-CI policies such as the repository-wide language policy or
  revision-history conventions, which are anchored in the root
  `README.md`.

## §2. CI Design Principles

### §2.1 [SPEC-CI-001] VM-based aggregation

Each operating system / runner family (Linux, Windows, macOS) MUST be
treated as a single execution context. A set of checks that all run on
the **same** OS / runner family MUST be aggregated into a **single
workflow file with serial steps**, not split across multiple workflows.

**Rationale.** Splitting same-VM checks across multiple workflows wastes
runner cold-start time (multiple minutes per workflow on Windows),
inflates the workflow_run dependency graph, and makes it harder to
correlate failures across logically-related checks. Aggregation keeps
the chain shallow (see §2.2 and §7) and the artifacts contiguous.

### §2.2 [SPEC-CI-002] Workflow boundaries by VM

The boundary between two workflows MUST coincide with a change of
runner family or with a fundamental change of trigger event (for
example, `release/published` vs `push`).

**Practical consequence.** The
`scripts/powershell/download-speakerdeck-oracle4engineer/` sub-project
has three logical checks: Linux static analysis, Windows static
analysis, and Windows release verification. These are realised as three
workflows (`stage1__linux`, `stage2__windows`, `stage3__windows-release`)
because they cross either a runner boundary (Linux → Windows) or a
trigger boundary (push → release/published).

### §2.3 [SPEC-CI-003] Serial execution as default

Within a single workflow, steps SHOULD execute serially unless there is
a measurable benefit to parallelism (independent tool groups, no shared
state). Serial execution makes failure attribution unambiguous and
keeps Step Summary output linear.

### §2.4 [SPEC-CI-004] Manual override via `workflow_dispatch`

Every workflow MUST expose a `workflow_dispatch` trigger so that an
operator can re-run the checks on demand without pushing a commit. For
workflows whose normal trigger is `release/published` or `workflow_run`,
`workflow_dispatch` is the only way to test the workflow against an
arbitrary ref during development.

When a workflow exposes optional scope inputs via `workflow_dispatch`
(e.g., a `scope` choice input that selects which tool group to run),
the default value MUST execute the full set of checks; selective
execution is opt-in for the operator.

### §2.5 [SPEC-CI-005] Quality gate semantics

CI checks in this repository MUST be **blocking** (non-zero exit on any
finding) once they are wired in. Soft warnings that are ignored degrade
the signal value of the gate over time. If a finding is by-design, it
MUST be suppressed deliberately — either project-wide (e.g.,
`ExcludeRules` in `PSScriptAnalyzerSettings.psd1`, `disable` in
`.psa.config.json`) with rationale, or per-occurrence
(`SuppressMessageAttribute` for PSScriptAnalyzer,
`# psa-disable-line` for psa.py) with a justification comment.

## §3. Naming Conventions

### §3.1 [SPEC-CI-010] Filename convention

Workflow files under `.github/workflows/` MUST follow a flat,
hierarchy-encoded naming scheme that uses `__` (double underscore) as a
path-segment separator. The general form is:

```
<path-segment>__<path-segment>__<...>__<descriptor>.yml
```

Examples (mapped to their target sub-project):

| Workflow filename | Target |
|:---|:---|
| `scripts__python__powershell-static-analyzer.yml` | `quality-tools/powershell-static-analyzer/` |
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml` | `scripts/powershell/download-speakerdeck-oracle4engineer/` (STAGE 1) |
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml` | `scripts/powershell/download-speakerdeck-oracle4engineer/` (STAGE 2) |
| `scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml` | `scripts/powershell/download-speakerdeck-oracle4engineer/` (STAGE 3) |

**Rationale.** GitHub Actions does not support nested directories under
`.github/workflows/`. Folding the path into the filename keeps the
target-to-file mapping unambiguous and grep-friendly.

The `name:` field inside each workflow MUST use the form
`<project-path> — STAGE <N>: <description>` (em-dash, single space on
each side) so the GitHub Actions UI displays a human-readable label
that mirrors the filename.

### §3.2 [SPEC-CI-011] STAGE terminology

GitHub Actions' native nouns are **Workflow**, **Job**, and **Step**.
This repository uses the additional concept **STAGE** to refer to a
distinct point in the `workflow_run` chain for a single sub-project.

For `scripts/powershell/download-speakerdeck-oracle4engineer/`:

- **STAGE 1** = Linux checks (psa.py + PSScriptAnalyzer on pwsh 7).
- **STAGE 2** = Windows checks (PSScriptAnalyzer on Windows PS 5.1 +
  `-EnvironmentInfoOnly` smoke test). Triggered by STAGE 1 success via
  `workflow_run`.
- **STAGE 3** = Release verification (full `-DryRun` on Windows).
  Triggered by `release/published` or manual dispatch; not part of the
  STAGE 1 → STAGE 2 chain.

STAGE numbers MUST be incremental starting from 1.

Job names within a workflow use kebab-case (e.g., `linux-checks`,
`windows-checks`, `windows-release`). Step names use the form
`[<tool-group>] <action>` (e.g., `[psa.py] Run text analysis`,
`[PSSA-pwsh51] Run microsoft/psscriptanalyzer-action`).

## §4. [SPEC-CI-020] Timeout Policy

Every job MUST specify an explicit `timeout-minutes` value chosen from
one of the three tiers below.

### §4.1 Tier T1 — Light

- **Value**: `timeout-minutes: 30`.
- **When to use**: Linux runner with no large external module install,
  expected wall-clock under five minutes at the 95th percentile.
- **Current consumers**: psa.py CI workflow.

### §4.2 Tier T2 — Medium

- **Value baseline**: `timeout-minutes: 60`.
- **Allowed extension**: any value in the range 61–180, but every value
  above 60 MUST carry an inline rationale comment in the workflow YAML
  immediately above the `timeout-minutes` key, of the form:

  ```yaml
  # T2 — Medium (extended): <N> minutes
  # Rationale: <specific bottleneck and time budget>
  timeout-minutes: <N>
  ```

- **When to use**: PSGallery or apt module install required, or a
  mid-size analysis that runs longer than five minutes but well under
  three hours.
- **Current consumers**:
  - STAGE 1 Linux checks (90 minutes; rationale: psscriptanalyzer-action
    PSGallery install + 5000-LOC analysis).
  - STAGE 2 Windows checks (120 minutes; rationale: Windows runner
    cold-start + PS 5.1 PSScriptAnalyzer install + smoke test).

### §4.3 Tier T3 — Heavy

- **Value**: `timeout-minutes: 240` (policy maximum).
- **When to use**: Long-running verification with unpredictable external
  dependencies (network round-trips, third-party rate limits).
- **Current consumers**: STAGE 3 Windows release verification.
- **Why 240 and not 360?** GitHub Actions' built-in job ceiling is 360
  minutes. The policy reserves a third of that as headroom for retries
  and post-mortem inspection after an abnormal termination.

### §4.4 Anti-patterns

- Using a value between 181 and 239 silently. If a job genuinely needs
  more than 180 minutes, raise it to 240 (T3) and document why.
- T2 extension without a rationale comment.
- Setting T3 on a job that does not require it just because the
  operator forgot to lower it after a one-off test run.

## §5. [SPEC-CI-030] Fork PR Handling

### §5.1 Job-level guard (current policy)

Every job in every workflow under `.github/workflows/` MUST carry the
following guard expression:

```yaml
jobs:
  <job-id>:
    if: >-
      github.event_name != 'pull_request' ||
      github.event.pull_request.head.repo.full_name == github.repository
    runs-on: <runner>
```

The guard causes the job to **skip** when the trigger is a pull request
that originated from a fork (i.e., when the PR HEAD repository is
different from the repository hosting the workflow). Same-repo PRs,
push events, scheduled runs, and `workflow_dispatch` events proceed
normally.

`workflow_run`-triggered jobs (STAGE 2) carry the additional guard
clause `github.event.workflow_run.conclusion == 'success'` so that they
fire only when the upstream STAGE succeeded.

### §5.2 Pre-merge review protocol (human + AI-assisted)

Because fork PRs do not get an automated CI signal under this policy,
the merge gate is a two-stage human review protocol:

**Stage 1 — Maintainer triage** (within 24-72 hours of PR open):

1. Read the PR description.
2. Inspect the number of changed files and total changed line count.
3. Escalate to Stage 2 if any of the following hold:
   - Total changed lines exceed 50.
   - Any change touches CI files: `.github/workflows/*`,
     `PSScriptAnalyzerSettings.psd1`, `/SPEC.md`.
   - The change includes binary files, or any file the maintainer
     suspects might be obfuscated.
   - The change introduces external URL references, API keys, or
     credentials.
4. For trivial changes (e.g., typo fixes, documentation-only edits) the
   maintainer MAY skip Stage 2.

**Stage 2 — AI-assisted diff review** (when escalated from Stage 1):

1. The maintainer opens a fresh chat session with Claude.
2. The maintainer retrieves the PR diff:
   `https://github.com/<owner>/<repo>/pull/<n>.diff`.
3. The maintainer pastes the diff into the session and asks Claude to
   review with explicit focus on: obfuscated or encoded payloads,
   suspicious imports / external URLs / network calls, exfiltration
   patterns, supply-chain attack vectors, and any CI privilege
   escalation.
4. The maintainer transcribes the AI's findings (verbatim) into a PR
   comment for audit transparency.
5. The maintainer makes the final merge / reject call. The AI review
   is advisory; the maintainer is authoritative.

### §5.3 Acknowledged limitations

- AI review is not a defence against sufficiently sophisticated
  obfuscation.
- The review is point-in-time. A force-push after review invalidates
  the prior review and requires a fresh pass.
- Static analysis cannot catch payloads that activate only under
  specific runtime conditions (date, environment variable, host).
- The protocol does not verify the contributor's identity or commit
  signature; those are separate concerns.

Candidates for future hardening are recorded in §8.

## §6. [SPEC-CI-040] Branch Protection (currently not enforced)

Branch protection rules on `main` are **NOT enforced** at the time of
writing. This is a deliberate choice for a single-maintainer repository
where the maintainer is also the sole reviewer; protection rules would
add ceremony without adding security.

When the contributor base broadens (multiple regular committers, or
any external contributors beyond ad-hoc one-off PRs), the maintainer
SHOULD revisit the policy and consider:

- Requiring all four CI workflow conclusions before merge (W1 psa.py,
  W2 STAGE 1, W3 STAGE 2 — W4 is release-time and does not gate merge).
- Requiring a pull request before any commit to `main`.
- Requiring at least one approving review.
- Enabling "Restrict who can push to matching branches" once the
  maintainer set is finite.
- Considering `CODEOWNERS`-based mandatory reviewers (see §8.1.C).

Technical considerations when enabling these:

- `workflow_run`-triggered workflows (STAGE 2) cannot themselves be set
  as "required status checks"; only the upstream-triggered workflows
  (push / pull_request) qualify. STAGE 2 still runs as a downstream
  signal but its conclusion is observed asynchronously.
- Branch protection rules interact with `if:` guards: a skipped job
  produces a `skipped` conclusion, not `success`. Required checks that
  may legitimately skip (e.g., the fork PR guard) need either a
  follow-on aggregating job or explicit allow-skipped configuration.

## §7. [SPEC-CI-050] `workflow_run` Depth Limit

GitHub Actions enforces a maximum chain depth of **three hops** for
`workflow_run` triggers. A workflow that runs because another workflow
finished may itself trigger a third workflow; a fourth hop is
suppressed.

The current chain for `scripts/powershell/download-speakerdeck-oracle4engineer/`
is:

```
push / PR  →  STAGE 1 (Linux)  →[workflow_run]→  STAGE 2 (Windows)
                                                       │
                                                    [no further hop]
```

Depth: one hop. Margin: two hops.

When adding any new STAGE to this chain (or to a future
sub-project chain), the author MUST verify that the resulting depth
does not exceed three. If a hypothetical STAGE 4 would push the chain
to four hops, the design MUST be revised — typically by collapsing two
adjacent STAGEs into a single workflow with serial jobs, or by changing
the downstream trigger to `workflow_dispatch` issued by the upstream
job.

## §8. [SPEC-CI-060] Future Security Considerations

The current Fork PR policy (§5) and Branch Protection policy (§6) are
deliberately minimal for a single-maintainer repository. Seven
candidate hardening measures are listed below for future reference.
None are implemented at the time of writing; the section exists so the
maintainer (and any AI agent helping them) has a pre-thought roadmap
when the threat model changes.

### §8.1.A Maintainer approval gate for fork PR workflow runs

GitHub provides a setting under **Settings → Actions → General →
Fork pull request workflows from outside collaborators** that requires
explicit maintainer approval before any workflow runs on a first-time
contributor's fork PR. Combined with a per-workflow manual approval
gate (the `environments` feature with required reviewers), this gives
the maintainer a two-step opt-in for fork-origin runs.

Trade-off: introduces friction for every legitimate first-time
contributor. Suited to repositories that accept occasional external
PRs but are not actively soliciting them.

### §8.1.B Pin third-party actions by full commit SHA

Today the workflows in this repository pin third-party actions to
major version tags (`@v4`, `@v5`). Tags are mutable in principle: a
compromised action publisher could push a malicious commit and re-tag
the major version. Pinning to a full 40-character commit SHA
(`actions/checkout@<sha>`) eliminates that vector.

Trade-off: SHA pins do not auto-update for security fixes. Dependabot
(`.github/dependabot.yml`) can be configured to open PRs that update
the SHA pins; the maintainer reviews each update.

### §8.1.C `CODEOWNERS`-based pre-merge review enforcement

A `.github/CODEOWNERS` file can declare per-directory mandatory
reviewers. Combined with the "Require review from Code Owners"
branch-protection rule, this forces a designated owner to approve
every change to a designated path. For a single-maintainer
repository this is currently redundant; it becomes useful when the
contributor base grows.

### §8.1.D Delayed-execution window for `workflow_run` on fork-origin events

Even with §5's fork-PR guard, defence-in-depth could add a deliberate
delay between the upstream event and the downstream `workflow_run`
firing, giving the maintainer a window to inspect the upstream output.
This can be approximated by inserting a `workflow_dispatch`-only
intermediate stage that the maintainer triggers manually.

Trade-off: slows the feedback loop for legitimate same-repo PRs too,
unless the delay is conditional on event origin.

### §8.1.E Automated diff analysis via Anthropic API in a separate workflow

The Stage-2 AI review described in §5.2 could be automated: a dedicated
workflow could fetch the PR diff and call the Anthropic API to produce
a structured review, posting the result as a PR comment. **This is out
of scope for the current implementation** because it would require
storing an `ANTHROPIC_API_KEY` secret in the repository, expanding the
secret blast radius beyond what a single-maintainer hobby repository
needs.

### §8.1.F Pre-upload artifact secret scanning

`actions/upload-artifact` does not scan its inputs for credentials.
A defence-in-depth step inserted just before each upload — either an
inline `grep` for known credential prefixes (`gh[ps]_`, `AKIA`, `-----BEGIN`,
etc.) or a dedicated tool such as `gitleaks-action` configured against
the staging directory — would block credential patterns in analyzer
outputs at the source.

The current scope assumes that the combination of upstream prevention
(push protection per §11.2) and content minimization (§12) is
sufficient for a repository whose workflows do not consume secrets.
This candidate becomes relevant when the repository later starts using
secrets in workflows or when analyzer outputs begin to incorporate
content from external sources that could surface tokens.

### §8.1.G Migrate CodeQL to Advanced setup with explicit query pack pinning

CodeQL Analysis is currently configured via GitHub's **Default setup**
(see §11.2). Migrating to **Advanced setup** would mean replacing the
UI-managed default with a `.github/workflows/codeql.yml` pinned to a
commit SHA, using query suites such as `security-extended` and
`security-and-quality`, with explicit `matrix.language` entries for
`python` and `actions`.

Trade-offs:

- **Pro**: explicit control over which query packs run, and over which
  commit SHA of the CodeQL action is used (Dependabot can then manage
  SHA updates).
- **Con**: maintenance overhead, and a configuration error stops
  CodeQL silently — whereas Default setup is auto-managed by GitHub
  and stays green by construction.

Triggers for revisiting: discovery of a relevant CodeQL query not
enabled by Default setup (e.g., a project-specific custom query
requirement), or requirement to disable specific noisy queries that
cannot be dismissed individually via the UI. Migrating from Default
setup to Advanced setup discards the UI-managed state, so the
maintainer SHOULD consult the current GitHub Docs procedure before
attempting the switch.

### §8.2 Trigger conditions for revisiting this section

The maintainer SHOULD revisit this section when any of the following
become true:

- The repository accepts external contributions on a regular basis
  (more than a handful per quarter).
- The repository starts handling secrets beyond what is needed for
  public CI (e.g., release signing keys, deployment credentials).
- A reported supply-chain incident in the broader GitHub ecosystem
  changes the risk calculus.
- The maintainer set expands beyond one person.

## §9. [SPEC-CI-070] CI Change History Location

CI workflow changes MUST be recorded in the CI-target script's own
`CHANGELOG.md`. There is no separate CI changelog. Specifically:

- A change to
  `.github/workflows/scripts__python__powershell-static-analyzer.yml`
  is recorded in
  `quality-tools/powershell-static-analyzer/CHANGELOG.md`.
- A change to any of the three Download-SpeakerDeck STAGE workflows is
  recorded in
  `scripts/powershell/download-speakerdeck-oracle4engineer/CHANGELOG.md`.
- A change to this `SPEC.md` is recorded in the CHANGELOG of whichever
  sub-project the change primarily affects. If a `SPEC.md` change is
  cross-cutting (e.g., adjusting the Timeout Policy across all
  workflows), it MUST be recorded in every affected sub-project's
  CHANGELOG.

**Forbidden.** The following files MUST NOT be created:

- `.github/workflows/CHANGELOG.md`
- `.github/workflows/README.md`
- `.github/workflows/SPEC.md`
- Any analogous "central CI history" or "central CI governance" file
  outside this `SPEC.md`.

**Rationale.** Centralising CI history in a separate file makes it
likely to drift from the actual workflows. Pinning the history next
to the script the workflow validates keeps the change record adjacent
to the change's purpose.

## §10. Quick reference for AI agents

This section is a machine-readable summary of the policies above.
Treat it as an index, not a substitute for the prose definitions.

```
SPEC-CI-001: VM-based aggregation        — one workflow per OS family.
SPEC-CI-002: Workflow boundaries         — boundary on OS or trigger change only.
SPEC-CI-003: Serial execution            — default; parallel requires justification.
SPEC-CI-004: Manual dispatch             — every workflow exposes workflow_dispatch.
SPEC-CI-005: Quality gate semantics      — non-zero on findings; suppress with rationale.
SPEC-CI-010: Filename convention         — '__' separator, flat under .github/workflows.
SPEC-CI-011: STAGE terminology           — incremental; STAGE != Workflow/Job/Step.
SPEC-CI-020: Timeout tiers               — T1=30, T2=60..180 with rationale, T3=240.
SPEC-CI-030: Fork PR handling            — job-level if-guard skips fork PRs.
SPEC-CI-040: Branch protection           — currently NOT enforced; see §6 for trigger conditions.
SPEC-CI-050: workflow_run depth          — max 3 hops; current chain is 1 hop.
SPEC-CI-060: Future security             — 7 candidates documented in §8.1.A..G.
SPEC-CI-070: CI change history           — recorded per-sub-project CHANGELOG.md.
SPEC-CI-080: Repository security baseline — Dependabot / secret scanning / push protection / CodeQL Default setup / Actions allowlist; configured in GitHub UI; see §11.
SPEC-CI-081: Artifact content minimization — explicit path enumeration only; allowlisted basenames per §12.2; no wildcards in '[Artifacts] Upload logs'.
```

When implementing or modifying CI workflows:

1. Pick the OS family of the new work. If it matches an existing
   workflow, add steps to that workflow rather than creating a new one
   (SPEC-CI-001 / SPEC-CI-002).
2. Pick a timeout tier (SPEC-CI-020). If the value is in T2's extended
   range, write the rationale comment.
3. Add the Fork PR guard expression to every job (SPEC-CI-030).
4. Add the standard workflow-header comment block (this is enforced by
   review, not by lint). The header MUST reference `/SPEC.md` and the
   target sub-project's `CHANGELOG.md`.
5. Record the change in the target sub-project's `CHANGELOG.md`
   (SPEC-CI-070).

If the change crosses any of the `[SPEC-CI-NNN]` policies above, update
this file in the same change set.

## §11. [SPEC-CI-080] Repository Security Baseline

### §11.1 Scope

This policy defines the baseline of GitHub repository-level security
settings that MUST be enabled for this repository. These settings are
configured via the GitHub web UI (Settings → Code security and
analysis, and Settings → Actions → General) and are not visible in the
repository contents, but are part of the repository's effective
security posture. Without this section, a future maintainer (or any AI
agent helping them) inspecting the working tree alone would have no
way to discover that these settings are deliberately enabled and MUST
remain so.

The settings recorded here form the **upstream prevention layer** of a
defence-in-depth model: secrets and supply-chain risks are caught
before they enter the repository or before a workflow accidentally
exposes them. The downstream layers — fork-PR `if`-guards (§5),
allowlisted action references in workflow YAML (§11.3), and artifact
content minimization (§12) — are documented elsewhere in this
specification.

### §11.2 Required Security Features (Settings → Code security and analysis)

The following features MUST remain enabled:

| Feature | Status |
|:---|:---|
| Private vulnerability reporting | Enabled |
| Dependency graph | Enabled |
| Dependabot alerts | Enabled |
| Dependabot security updates | Enabled |
| Dependabot malware alerts | Enabled |
| Grouped security updates | Enabled |
| Secret Protection (secret scanning) | Enabled |
| Push protection | Enabled |
| Code scanning (CodeQL, Default setup minimum) | Enabled |
| Copilot Autofix | On |

**Rationale.** These features are free for public repositories, have
no operational downside, and together implement Layers 1–4 of the
industry-standard 5-layer secret-protection model (prevention,
detection at push time, alerting, automated remediation). The fifth
layer — manual incident response — is the maintainer's responsibility
and is not subject to a configuration toggle.

Code scanning is currently configured using GitHub's **Default
setup**. This decision is recorded explicitly because the alternative
(Advanced setup with a hand-authored `.github/workflows/codeql.yml`)
is a known migration path and is documented as a Future Consideration
in §8.1.G.

### §11.3 Required Actions Configuration (Settings → Actions → General)

| Setting | Required value |
|:---|:---|
| Actions permissions | "Allow `usui-tk`, and select non-`usui-tk`, actions and reusable workflows" |
| Allow actions created by GitHub | Checked |
| Allow actions by Marketplace verified creators | Unchecked |
| Allowlist contents | `actions/*, github/codeql-action/*, microsoft/psscriptanalyzer-action@*` |
| Require actions to be pinned to a full-length commit SHA | Unchecked (future candidate, see §8.1.B) |
| Artifact and log retention | 14 days |
| Fork PR approval | "Require approval for all external contributors" |
| Workflow permissions | "Read repository contents and packages permissions" |
| Allow GitHub Actions to create and approve pull requests | Unchecked |

**Rationale.** This configuration enforces, at the repository level
rather than per-workflow:

- **Third-party action allowlisting** matching only the actions
  actually used by this repository's CI. New external actions cannot
  be added by a workflow change alone; the allowlist must be amended
  via the UI by a maintainer first.
- **Minimum GITHUB_TOKEN scope** — the default token granted to every
  job is read-only. Workflows that need write access (for example,
  `security-events: write` for `upload-sarif`) must declare it
  explicitly via the per-job `permissions:` key, which is auditable.
- **Approval requirement for external contributors** — a first-time
  external contributor's workflow run is held pending maintainer
  approval. Combined with the per-job fork-PR `if`-guard from §5, a
  fork-origin PR cannot accidentally execute CI even if a future
  workflow forgets the guard.
- **Short artifact retention** (14 days) — limits the historical
  exposure window of any analyzer output (see §12). Anyone with read
  access to the repository can see artifact contents; capping the
  retention reduces the consequence of an accidental upload of
  sensitive content.

### §11.4 Verification

The current effective configuration can be verified non-interactively
via the GitHub CLI:

```bash
REPO="usui-tk/ai-generated-artifacts"

# Code security and analysis features
gh api "repos/$REPO" --jq '.security_and_analysis'

# Actions permissions (allowlist, marketplace creators, etc.)
gh api "repos/$REPO/actions/permissions"

# Default workflow permissions (read vs write GITHUB_TOKEN scope)
gh api "repos/$REPO/actions/permissions/workflow"
```

Any divergence between the output and the tables above MUST be
investigated. The settings under §11.2 and §11.3 are the
authoritative target state; the UI reflects it.

### §11.5 Future Considerations

The following hardening steps are deferred and tracked in §8 (Future
Security Considerations):

- **SHA pinning of third-party actions** (§8.1.B): the current
  allowlist accepts tag references like `@v1.1` and the major-tag
  pattern `@v4`. A future migration to full 40-character commit SHA
  pinning, combined with Dependabot updates for the `github-actions`
  ecosystem, is documented as §8.1.B.
- **Branch protection rules on `main`** (§6): currently not enforced.
- **CodeQL migration to Advanced setup** (§8.1.G): currently using
  Default setup, which is correct for the present scope.
- **Pre-upload artifact secret scanning** (§8.1.F): currently relying
  on push protection (§11.2) and content minimization (§12).

## §12. [SPEC-CI-081] Artifact Content Minimization

### §12.1 Principle

GitHub Actions artifacts uploaded via `actions/upload-artifact` are
visible to anyone with read access to the repository for up to the
configured retention period (14 days per §11.3). Artifact content is
not scanned for credentials by GitHub. Therefore, this repository
applies a strict allowlist approach: only files explicitly designated
as analyzer output may be uploaded.

### §12.2 Allowed Artifact Contents

The following files MAY appear in uploaded artifacts:

| File pattern (basename) | Source |
|:---|:---|
| `psa.log` | psa.py text output |
| `psa.sarif` | psa.py SARIF output |
| `pssa.log` | PSScriptAnalyzer-action derived log |
| `pssa.sarif` | PSScriptAnalyzer-action SARIF output |
| `pillar1.log` / `pillar2.log` / `pillar3.log` | psa.py self-quality gate output (W1 only) |

Any other content requires this section to be amended **in the same
change set** as the workflow modification.

### §12.3 Prohibited Artifact Contents

Workflows MUST NOT include any of the following in any uploaded
artifact:

- Environment variable dumps (`printenv`, `set`, `Get-ChildItem env:`)
- Shell trace output (`set -x` in bash, `Set-PSDebug -Trace` in
  PowerShell)
- The `.git/` directory or any of its contents
- Files matching `.env*`, `*.pem`, `*.key`, `credentials.json`,
  `.aws/`, `.azure/`, `id_rsa*`, or similar credential-bearing
  patterns
- Full runner home directories
- Build or test output containing secrets injected via `env:` in the
  workflow
- Source tree dumps (e.g., the entire checkout) — always use a narrow
  `path:` enumeration instead

### §12.4 Workflow-Level Enforcement

Workflows enforce this policy structurally:

- The `[Artifacts] Upload logs` step in each workflow uses an explicit
  `path:` list naming only the files in §12.2. **Wildcard paths such
  as `path: .` or `path: ./**` are forbidden** at this step.
- `actions/upload-artifact@v4` excludes hidden files (entries
  beginning with `.`, such as `.git/`) by default since v4.4.0,
  providing a secondary safeguard against accidental upload of the
  Git directory or hidden credential files.
- Each `[Artifacts] Upload logs` step in this repository carries an
  inline comment referencing this policy, so a future maintainer
  modifying the upload step encounters the rule without needing to
  search for it.

### §12.5 Future Hardening

A pre-upload secret-scanning step (inline `grep` for known token
prefixes such as `gh[ps]_`, `AKIA`, `-----BEGIN`, or a dedicated tool
such as `gitleaks-action` against the staging directory) is a
candidate Future enhancement, tracked as §8.1.F. It is not enabled
today because the upstream prevention layer (§11.2 push protection)
combined with the strict allowlist in §12.2 is judged sufficient for
a repository whose workflows do not currently consume secrets.

### §12.6 Workflow Author Checklist

Before adding a new artifact upload to any workflow, the author MUST:

1. Confirm the file is listed in §12.2. If not, propose an amendment
   to §12.2 in the same change set as the workflow modification.
2. Confirm the workflow does not run `printenv`, `set -x`, or
   equivalent commands that could populate logs (and thus the
   artifact) with the contents of secrets or environment variables.
3. Confirm the `path:` directive is an explicit file enumeration, not
   a directory path or wildcard.
4. Confirm the artifact `retention-days` does not exceed the
   repository default (14 days, per §11.3).
5. Confirm the inline comment referencing this policy is present
   immediately above the `[Artifacts] Upload logs` step.

