---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Changelog

All notable changes to `Download-SpeakerDeck.ps1` (the Speaker Deck
bulk downloader in this directory) are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project uses an `rNN` linear revision counter encoded in
`$Script:ScriptVersion` (the AI-generation date stamp + revision tag).
Each revision number is announced in the script banner, in the phase
header lines, and (from r23 onwards) in the Debug Trace Facility's
JSONL stream (`work/logs/debugtrace.jsonl`).

This CHANGELOG is **English only** per the
[repository-wide documentation language policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md#language-policy).

## [Unreleased]

### Changed -- CI: bump actions/checkout v5 -> v7 and actions/upload-artifact v5 -> v7 across the three stage workflows (workflows-only, no script version bump)

Live-verified against the upstream repositories on 2026-07-02 during a
repo-wide pin audit: actions/checkout's latest major is v7.0.0
(2026-06-17) and actions/upload-artifact's is v7. Both jumps are
non-breaking for these workflows: the upload steps use only `name` /
`path` (unchanged inputs; v7's new `archive` input defaults to the old
zipping behavior), and checkout v7's fork-PR refusal under
`pull_request_target` / `workflow_run` triggers does not affect this
repository's same-repo push/PR flow (stage 2 is `workflow_run`-chained
from stage 1, but the refusal targets fork pull requests only -- a
desirable supply-chain guardrail here). The remaining pins are already
current (setup-python v6, codeql-action upload-sarif v4,
microsoft/psscriptanalyzer-action v1.1 -- the newest upstream tag).

### CI / build — Complete the scripts -> projects migration for this project's workflows

The `scripts/powershell/download-speakerdeck-oracle4engineer/` -> `projects/powershell-download-speakerdeck-oracle4engineer/` migration moved the project tree but left this project's three CI workflows pointing at the old path (the same omission fixed earlier for `update-windows-server-iso`). No script change.

- `.github/workflows/`: renamed the three `scripts__powershell__download-speakerdeck-oracle4engineer__*.yml` to `projects__powershell-download-speakerdeck-oracle4engineer__*.yml` (path-encoded filenames per the dotfile convention). Repointed all in-file paths (project directory, `paths:` trigger filters, `working-directory`, SARIF/artifact paths, header comments, `name:` fields, and stage1's `paths:` self-reference), and corrected the psa.py invocation to `../../quality-tools/powershell-static-analyzer/psa.py` (psa.py now lives under `quality-tools/`; the old `scripts/python/powershell-static-analyzer/` copy is being removed).
- The stage2 `workflow_run` chain (it triggers on completion of stage1, matched by stage1's `name:`) stays in sync: both ends now carry the renamed `projects/...` workflow name.
- README.md / README.ja.md: CI badge URLs repointed (bilingual lock-step preserved). TESTING.md: the three workflow-file references renamed to match.

Note: renaming the workflow files changes their GitHub workflow identity (run history detaches; required-check names change). Any branch-protection rule that requires these checks by the old file name must be updated in repository settings after this lands.

### Fixed — Documentation/implementation reconciliation (parameter table, `.PARAMETER DryRun` note, AI-tool note)

A doc-only update that closes three documentation/implementation
divergences found by grounding the docs against the live script body
(`AGENTS.md` §4). The running script is authoritative; the docs and the
in-script comment-based help are brought in line with it. No phase
logic, parameter contract, or output format changed.

#### Drifts reconciled

- **`-EnvironmentInfoOnly` was undocumented.** The switch is fully
  implemented (param declaration, `.PARAMETER` help, the mutual-exclusion
  guard with `-SkipEnvCheck`, and the Phase 1 Step 0 environment dump
  that exits with status 0 for CI smoke testing) but was absent from the
  `README.md` / `README.ja.md` Parameters tables. Added the row to both,
  in bilingual lock-step.
- **`.PARAMETER DryRun` omitted Phase 8.** The header comment listed only
  Phase 6 and Phase 7 as SKIPPED under `-DryRun`, but Phase 8 (PDF
  reclassification) is also skipped in DryRun mode (the
  `Invoke-Phase8UndatedReclassify` `IsDryRun` guard). Corrected the
  comment to include Phase 8. `README.md` / `README.ja.md` already
  documented 6/7/8 correctly and were not changed for this item.
- **Stale AI-tool note.** The header AI-tool note named
  `latest revision r20 on 2026-05-13`, while `$Script:ScriptVersion` is
  `speakerdeck-2026.05.27-r29`. Synced the note to `r29 on 2026-05-27`
  and refreshed the model era to include `Opus 4.8`.

#### Not touched

- No source logic. Only the comment-based help header (outside any
  canonical region) was edited in `Download-SpeakerDeck.ps1`; the 39
  vendored canon code-regions are unchanged. This remains an
  `Unreleased`-bucket doc-only entry; no `rNN` revision bump.
- `SPEC.md`, `TESTING.md`. `SPEC.md` `B.2 Inputs` documents input
  sources, not a full parameter table, and the Phase Map (`B.4`) already
  matches the script, so neither needed an edit.
- The 14 vendored Part A doc-regions (canon-owned; out of scope).

### Documentation — Bilingual lock-step compliance for README

A doc-only update that brings the Japanese `README.ja.md` in line
with the English `README.md` formatting style. Closes a pre-existing
bilingual divergence (`AGENTS.md` §9 AP-6) that has been carried for
several revisions and that was identified during the Step 7 → 8
governance cycle but deferred for separate handling.

#### Quantitative result

| Metric | Before | After |
|---|--:|--:|
| `README.md` line count | 781 | 781 (no change) |
| `README.ja.md` line count | 669 | 761 |
| Line-count delta | 112 lines (14.3%) | 20 lines (2.5%) |
| H2 / H3 heading count match | 19 / 19 (already correct) | 19 / 19 (preserved) |

The new 2.5% line-count delta sits comfortably within the
~5% guideline recorded in `AGENTS.md` §8 Post-flight gate 10
for bilingual companion files.

#### What was actually changed

This is a **formatting-only** update. No translated content was
added, removed, or semantically altered; no new sections were
introduced; no existing sections were renamed; no English text was
modified.

The pre-existing divergence root cause was a stylistic mismatch:
the English `README.md` writes prose paragraphs and bullet items
with line breaks at sentence / phrase boundaries (one statement per
line), while the Japanese `README.ja.md` was authored in a long-line
style (one paragraph or bullet collapsed onto a single line). The
two styles communicate the same content but produce wildly different
line counts.

The fix re-flows nine high-delta sections of `README.ja.md` to match
the English line-break style, preserving every word of the existing
Japanese translation. Sections re-flowed:

- `## ⚠️ 免責事項` (Disclaimer; was +11 lines short)
- `## 開発者向け仕様` (Developer specification; was +16 lines short)
- `### プロジェクト固有設定` (Project-local configuration; was +10 lines short)
- `### CSV カラム共通規約` (CSV column conventions; was +8 lines short)
- `### Phase 6（ダウンロード）で失敗が発生した場合` (Phase 6 download failures; was +6 lines short)
- `### Phase 2 で 0 件しか取得できない` (Phase 2 zero-decks diagnosis; was +6 lines short)
- `### ルールカバレッジ (psa.py — latest mainline)` (Rule coverage; was +6 lines short)
- `### 無効化について` (Disabling the facility; was +6 lines short)
- `### この機能が役立つ場面` (When this helps; was +6 lines short)

Remaining ~20 lines of delta across the other 29 sections are
natural compression of Japanese vs English prose and are within
the 5% guideline.

#### Why this was deferred from the Step 7 ③ cycle

When subproject ③ was brought into AGENTS.md compliance in Step 7
(commit `06c0b14`), the pre-existing 15.5% bilingual divergence was
identified but explicitly held over: that cycle's scope was to add
the new AGENTS.md cross-references and `Why this script exists`
section without expanding into broader doc-quality improvements.
This entry closes that explicitly-deferred item.

#### Not touched

- `Download-SpeakerDeck.ps1` source. No phase logic, parameter
  contract, or output format is affected. This remains an
  `Unreleased`-bucket doc-only entry; no `rNN` revision bump.
- `README.md` (English). The English source-of-truth was already
  in its canonical line-break style; no edits were made.
- `SPEC.md`, `TESTING.md`. Both were already in the English-only
  single-master style and unaffected by this fix.
- Heading structure (`## ` / `### `). All 19 + 19 headings on both
  sides are unchanged; only their bodies were re-flowed.

#### Rationale

The repository-wide bilingual lock-step rule (`AGENTS.md` §5)
specifies that `README.md` and `README.ja.md` should match in
structure, with section count and order required to match exactly
and line-count delta expected to stay within ~5%. The 14.3%
delta on ③ was a known violation of the line-count expectation
and a candidate for the `AP-6 Bilingual divergence` catalogue.
This entry brings ③ into compliance without altering any other
artifact in this subproject.

### Documentation — Add `Why this script exists` section and repository-wide `AGENTS.md` cross-references

A doc-only update that adds the SHOULD-level `Why this script exists`
section recommended by [`scripts/README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md) Recommended
Additional Section (L125–L135), and surfaces the newly-introduced
repository-wide [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) from this subproject's
documentation. In particular, `SPEC.md` Part A — which is the
canonical inheritance source for sibling Layer 3 SPECs — now carries
an explicit Status banner clarifying its role and pointing to
[`AGENTS.md` §6](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#6-part-a-inheritance-rule-absolute)
for the inheritance rule and to
[`AGENTS.md` §9 AP-1](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md#9-anti-patterns-forensically-documented)
for the forensic record of past violations.

#### Changes

- **`README.md`**: New `## Why this script exists` section inserted
  between the existing `## License` and `## Folder layout` sections.
  Includes a one-paragraph problem statement, "Suitable for" /
  "Out of scope" subsections, and a "Reader's roadmap" subsection
  that points to `SPEC.md`, `TESTING.md`, `CHANGELOG.md`, and the
  repository-root `AGENTS.md`.
- **`README.ja.md`**: New `## なぜこのスクリプトが必要か` section in
  lock-step Japanese (per `AGENTS.md` §5 Bilingual lock-step rule).
- **`SPEC.md`**: New `> Status: Canonical inheritance source.`
  blockquote at the top of `Part A`, clarifying that this Part A is
  the source of truth that sibling Layer 3 SPECs inherit by reference
  rather than by restating, and pointing to `AGENTS.md` §6 / §9 AP-1.
- **`CHANGELOG.md`**: This entry.

#### Why this update

The Step 6 governance cycle introduced `AGENTS.md` at the repository
root and codified the Part A inheritance rule. As the canonical
inheritance source, this subproject's `SPEC.md` Part A is the most
important place to surface that role: LLM agents inheriting from it
need to know (a) that it IS canonical, and (b) where the rule and
the forensic record of past violations live. Adding the Status
banner makes those facts discoverable from the SPEC itself rather
than only from external documents.

#### Not touched

- `Download-SpeakerDeck.ps1` source. No phase logic, parameter
  contract, or output format is affected. This remains an
  `Unreleased`-bucket doc-only entry; no `rNN` revision bump.
- `TESTING.md` is unchanged. It already references `SPEC.md`
  Part C; the `AGENTS.md` link is reachable transitively through
  the SPEC.
- `Part A` body (A.1 through A.14). The Status blockquote is
  metadata about Part A's role; the inherited contract itself is
  unchanged. Sibling SPECs that inherit by reference will see no
  semantic change.

## [r29] — 2026-05-27 — `cross-repo-canon-rename-misleading-helpers`

This is a **focused naming-cleanup release** matching the corresponding
release in the sibling repo. It renames two helpers in the 5-way
cross-repo shared utility canon where the function names had drifted
from what the implementations actually do. Both renames are mechanical
(function bodies unchanged); the entire release is a callsite-only
rewrite plus the script-identity bump.

### Cross-repo coordination

The matching AMD release is **Chipset r87 / Graphics r53 / BthPan r35 /
NPU r31** (same `cross-repo-canon-rename-misleading-helpers` tag),
committed to the sibling repo separately.

### Function renames

- **`Set-Tls12` → `Set-TlsSecurityProtocol`**
  The pre-rename name suggested "set TLS 1.2", but since the r28
  hybrid uplift the implementation has been negotiating TLS 1.3 +
  1.2 + best-effort 1.1 + 1.0 fallback. The new name reflects what
  the function actually does: it assigns the
  `[Net.ServicePointManager]::SecurityProtocol` bitmask for outbound
  HTTPS calls.

- **`Set-ConsoleUtf8` → `Set-Utf8PipelineEncoding`**
  The pre-rename name suggested "set Console to UTF-8", but the
  implementation sets three distinct things: `[Console]::OutputEncoding`,
  `[Console]::InputEncoding`, AND the PowerShell-internal
  `$OutputEncoding` global variable. The third is **not** a Console
  property — it controls how PowerShell writes piped data to external
  tools (such as the curl invocation this script uses for retries when
  `Invoke-WebRequest` is rate-limited). The new name captures the
  broader pipeline-encoding scope.

### Callsite rewrites

Both renames are precise `\bName\b` word-boundary replacements:

| Script                   | Set-Tls12 → Set-TlsSecurityProtocol | Set-ConsoleUtf8 → Set-Utf8PipelineEncoding |
|--------------------------|-------------------------------------|--------------------------------------------|
| Download-SpeakerDeck.ps1 | 3 (def + 2 calls)                   | 3 (def + 2 calls)                          |

### Release-wide changes

- `$Script:ScriptVersion`: `speakerdeck-2026.05.27-r28` → `speakerdeck-2026.05.27-r29`.
- `$Script:ScriptTag`: `cross-repo-shared-utility-canon-write-caution` → `cross-repo-canon-rename-misleading-helpers`.

### Verification

5-way byte-identity across the 28 canon functions is preserved (the
two renamed function bodies are unchanged; only the function name and
callsites changed). The script passes `psa.py 4.1.0` with `0 errors /
0 warnings / 0 info` using the project `.psa.config.json`.

### Why this is a separate release from r28

The r28 release established the hybrid `Set-Tls12` body (TLS 1.3 +
1.2 + 1.1 + 1.0) and the hybrid `Set-ConsoleUtf8` body (Console +
pipeline encoding both). The name-vs-implementation drift this release
addresses was introduced by r28's hybrid uplift. r28 was correct to
focus on the **implementation** of the cross-repo canon (best-of-both
selection per function); r29 corrects the **naming** that should have
been updated alongside. Splitting these into two commits keeps each
release's "what changed" reviewable independently.

## [r28] — 2026-05-27 — `cross-repo-shared-utility-canon-write-caution`

This release adopts the **5-way cross-repo shared utility canon** that
spans this script and the four AMD-family scripts in the sibling
repository [`usui-tk/Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer).
28 helper functions are now byte-identical between the SpeakerDeck
script and all four AMD scripts (up from 5 prior to the release). The
bidirectional best-of-both pass also renamed `Write-Warn` (this script)
and `Write-Warn2` (AMD canon) to a unified `Write-Caution`.

### Cross-repo coordination

The matching AMD release is **Chipset r86 / Graphics r52 / BthPan r34 /
NPU r30** (same `cross-repo-shared-utility-canon-write-caution` tag),
committed to the sibling repo separately.

### Function changes

**Function rename: `Write-Warn` → `Write-Caution`** (47 callsites + 1
definition rewritten). The new name avoids the visual / autocomplete
collision with the PowerShell built-in `Write-Warning` cmdlet that the
old name had, matches the noun-form convention of the other one-line
helpers (`Write-Ok` / `Write-Fail` / `Write-Skip` / `Write-Step`), and
semantically matches the `[!]` marker's "operator must take notice,
processing continues" intent.

**`Write-Detail` added** (1 definition, 0 callsites at this release).
The 5-way canon includes `Write-Detail` as a no-marker continuation-line
helper that the AMD scripts use heavily for the multi-row
`Show-PowerShellEnvironment` / `Show-OperatingSystemDetail` /
`Show-SecureBootBaselineSnapshot` tables. The SpeakerDeck script does
not currently emit table-style output, but the helper is added as a
5-way byte-identical placeholder so a future SpeakerDeck change that
adopts table-style output can immediately use it without re-importing.

**Best-of-both function uplifts** — 18 functions changed:

- **SpeakerDeck-canon retained / promoted to the AMD repo** (where the
  SpeakerDeck implementation was the better one): `Get-PhaseElapsedTag`
  (single-quote comment convention), `_LogLine` (column-12 width with
  format reused on the empty-tag branch), `Format-Elapsed` (zero-padded
  `'{0}h{1:D2}m{2:D2}s'` form with usage-example comment),
  `Write-PhaseHeader` (Mandatory + typed param block + format width),
  `Assert-PowerShellCompatibility` (richer `.SYNOPSIS` / `.DESCRIPTION`
  docstring), `Start-DebugTrace` (extended Context example),
  `Format-DebugFailure` (added `ElapsedMs` + `PhaseId` fields).
- **AMD-canon adopted into this script**: `Set-ConsoleUtf8` (richer
  SPEC cross-reference comments), `Enable-AutoExportOnPhaseFailure`
  (multi-line param block per SPEC §A.x convention),
  `Enable-DebugTraceFileOutput` (minor comment polish),
  `Export-DebugTraceJson` (richer error handling),
  `Stop-DebugTrace`, `_DebugTrace_RetireFrame`,
  `_DebugTrace_WriteJsonlLine`, `Write-DebugFailureReport`.
- **Hybrid (best-of-both merged)**:
  - `Set-Tls12` — TLS 1.2 baseline + best-effort TLS 1.3 / 1.1 / 1.0
    additions wrapped in individual `try/catch` blocks. Combines the
    SpeakerDeck canon's "tolerate legacy hosts" posture with the AMD
    canon's "prefer modern TLS" posture.
  - `Write-PhaseFooter` — adopts the AMD canon's four-state status
    ValidateSet (`'done','cached','skipped','failed'`) while keeping
    the SpeakerDeck-side Mandatory + typed param block + format-width
    specifier. The four-state set adds the `'cached'` status (used by
    the AMD scripts for phases that are no-ops because the target state
    is already met); this script does not currently emit `'cached'`
    but the ValidateSet now accepts it.
- **One-line helpers (`Write-Ok` / `Write-Fail` / `Write-Skip` /
  `Write-Step` / `Write-Caution`)** — `[string]$m` param replaced
  with `$Msg` for AMD-convention alignment.

### Per-repo carve-out (NOT 5-way)

**`Show-PowerShellEnvironment` is intentionally NOT 5-way byte-identical.**
The AMD canon implementation references AMD-driver-specific helpers
(`Get-BootSigningEnvironment`, `Show-BootSigningEnvironment`,
`Show-DriverInstallationOrderNotice`) that do not exist in this script.
This script keeps its own simpler `Show-PowerShellEnvironment`
implementation that omits the driver-specific sections; the two
implementations are semantically equivalent for the parts they share.
This decision is documented in the sibling repo's SPEC §A.11.7
"Per-repo differences explicitly carved out".

### Release-wide changes

- `$Script:ScriptVersion`: `speakerdeck-2026.05.25-r27` → `speakerdeck-2026.05.27-r28`.
- `$Script:ScriptTag`: `psa-py-v4-llm-governance-baseline` → `cross-repo-shared-utility-canon-write-caution`.

### Verification

The script passes `psa.py 4.1.0` with `0 errors / 0 warnings / 0 info`
using the project `.psa.config.json` (PSAP0003 / PSAP0004 / PSAP0005
strict mode enabled, PSA6003 disabled per the documented plural-noun
exception).

## [r27] — 2026-05-25 — `psa-py-v4-llm-governance-baseline`

This release is the **LLM-governance baseline adoption** for the
Speaker Deck downloader. It aligns the project with the
`usui-tk/Deploy-Drivers-For-WindowsServer` sister repository's
r76 / r42 / r24 / r20 release line by adopting `psa.py` 4.0.x as
the verification gate and opting in to the new `PSAP0005` rule
(revision reference in comment body).

The script has no functional behaviour change beyond a cosmetic
consistency tweak in the Phase 4 hashtable init. The release also
bundles two pre-existing CI workflow fixes that had been queued in
`[Unreleased]`; those workflow files are not part of
`Download-SpeakerDeck.ps1` itself but ship alongside it in this
sub-project.

### Added

- **`PSAP0005` opt-in (strict mode).** `.psa.config.json` now lists
  `PSAP0005` in its `enable` array alongside `PSAP0003` and
  `PSAP0004`. `psap0005_relaxed_mode` is intentionally NOT set
  (defaults to `false`, i.e., strict mode) because the r21 cleanup
  commit already removed every `rNN` reference from the script
  body; `psa.py 4.0.1 --include PSAP0005` reports **0 findings** at
  the r27 baseline, so the strict baseline is the verified
  end-state. This differs from the sister
  `usui-tk/Deploy-Drivers-For-WindowsServer` repository, which
  uses `psap0005_relaxed_mode: true` as a migration baseline; that
  repository is mid-migration, this one is already at end-state.

### Changed

- **Phase 4 reaper-loop hashtable init: added `Collected = $false`**
  for consistency with Phase 6's init. The Phase 4 `$jobs.Add(@{
  PS = $ps; Handle = $handle; Deck = $deck })` is updated to
  `$jobs.Add(@{ PS = $ps; Handle = $handle; Deck = $deck;
  Collected = $false })`. This is purely cosmetic — PowerShell
  hashtables tolerate dynamic key addition at runtime, so the
  previous form was correct — but the explicit declaration aids
  reader comprehension and matches Phase 6's pattern. The change
  also helps static-analysis tools (`psa.py 4.0.x`) reason about
  the hashtable element shape more uniformly across the two
  reaper loops.

- **`$Script:ScriptVersion`**: `speakerdeck-2026.05.20-r26` →
  `speakerdeck-2026.05.25-r27`.

- **`$Script:ScriptTag`**: `add-environmentinfoonly-switch` →
  `psa-py-v4-llm-governance-baseline`. The new tag aligns with the
  sister `usui-tk/Deploy-Drivers-For-WindowsServer` repository's
  release line of the same name.

- **Validation tool**: `psa.py 4.0.1` (was `3.9.0`-and-later
  mainline at r26 release time). The 4.0.x line adds the `PSAP0005`
  rule (4.0.0) and the `PSA2009` Step 2c2 indirect-binding defence
  (4.0.1) that resolves the false positive described in **Fixed**
  below.

### Fixed

- **`PSA2009` false positives on `$job.Collected = $true` in Phase 4
  and Phase 6 reaper loops** (a pre-existing latent issue that
  surfaced when `psa.py 4.0.0` was first applied to this script —
  the same warnings would have appeared on `psa.py 3.8.0+` mainline
  had a verification been run there). The root cause was file-level
  variable-name conflation between (a) `$job = [PSCustomObject]@{...}`
  in `Invoke-Phase05_PreparePlan` (sealed object, no `Collected`
  field) and (b) `foreach ($job in $newlyDone)` in the Phase 4 /
  Phase 6 reaper loops where `$newlyDone = $jobs | Where-Object {...}`
  yields hashtable elements (which DO accept dynamic property
  addition).

  The fix is **two-sided**:
  1. `psa.py 4.0.1` adds **Step 2c2** to the `PSA2009` walk: any
     foreach loop-variable bound through `$Coll.Add(@{...})` +
     `foreach (...) in $Coll` is treated as a hashtable element and
     excluded from PSCustomObject tracking. Pipeline / method
     derivations (`$X = $jobs | Where-Object`, `$X = $jobs.Where(...)`)
     are followed to a fixed point.
  2. `Download-SpeakerDeck.ps1` Phase 4 hashtable init is updated
     to include `Collected = $false` (see **Changed** above).

  After both sides land, `psa.py 4.0.1 --config .psa.config.json
  Download-SpeakerDeck.ps1` reports `0 errors / 0 warnings / 0 info`,
  restoring the documented quality gate. See `SPEC.md` §D.7 for
  the full root-cause analysis.

- **CI: Updated `microsoft/psscriptanalyzer-action` reference from
  `@v1` (which does not exist as a tag) to `@v1.1` (latest stable
  release).** The `@v1` floating major tag never existed in the
  upstream repository; only `@v1.0` and `@v1.1` are real release
  tags. CI runs would have failed at the
  `[PSSA-pwsh7] Run microsoft/psscriptanalyzer-action` and
  `[PSSA-pwsh51] Run microsoft/psscriptanalyzer-action` steps with
  `Unable to resolve action ... unable to find version 'v1'`.
  Affected workflows:
  - `.github/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml`
    (STAGE 1 — Linux checks)
  - `.github/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml`
    (STAGE 2 — Windows checks)

  The repository-level Actions allowlist accepts
  `microsoft/psscriptanalyzer-action@*`, so the `@v1.1` tag is
  authorized without further configuration. This change was queued
  in `[Unreleased]` after r26 and is now landed as part of r27.

### Documentation

- **`SPEC.md` §A.11 "Rule coverage / Project-local suppression policy"**
  — updated to reflect `PSAP0001..PSAP0005` (was `PSAP0001..PSAP0004`)
  and to document the strict-mode opt-in of `PSAP0005` with the
  rationale why this project does not need the relaxed-mode
  migration aid that the sister repo uses.

- **`SPEC.md` §D.7 (new)** — "r27 — `psa.py` 4.0.0 `PSA2009`
  false positive on `$Coll.Add(@{...})` + `foreach` pattern": full
  symptom / root-cause / fix / lesson-learned write-up codifying
  the issue for future contributors.

- **`README.md` and `README.ja.md`** — rule-count text updated from
  `42` to `46`; PSAP table extended with `PSAP0005`; "Current
  verification result" line-count corrected from `5152` to `5205`;
  added rationale for strict-mode `PSAP0005` opt-in.

- **`TESTING.md`**
  - §0 verification-status table updated to "r27 build (`psa.py 4.0.1`)";
    added a row for the `PSAP0005` strict-mode baseline (0 findings).
  - §1 expected output line-count corrected from `5152` to `5205`;
    rule-count narrative updated from `42` to `46`.
  - §6 discovered-bugs table adds the **r27** row covering the
    PSA2009 false-positive root cause and the two-sided fix.

- **CI: Added inline rationale comments to the `[Artifacts] Upload
  logs` steps in STAGE 1 and STAGE 2 workflows**, referencing the
  artifact content minimization policy in repository-root
  `/SPEC.md` §12 [SPEC-CI-081]. No functional CI change; the
  comments ensure future maintainers and AI agents encounter the
  policy at the point of edit. (This change was queued in
  `[Unreleased]` after r26 and is now landed as part of r27.)

### Known limitations

- This release has no functional behaviour change in
  `Download-SpeakerDeck.ps1` itself. The r17 functional baseline
  (TESTING.md §3, real run with 804/804 success) remains the
  most recent end-to-end verification; r27 does not re-run it
  because no functional change was introduced.

## [r26] — 2026-05-20 — `add-environmentinfoonly-switch`

### Added

- **`-EnvironmentInfoOnly` switch parameter** for CI smoke testing.
  When specified, the script runs only Phase 1 Step 0
  (`Show-PowerShellEnvironment`) and exits with status 0. Skips
  Step A (registry check for `LongPathsEnabled`), Step B (real-world
  filesystem long-path tests), and Phases 2 through 8. Intended for
  fast, side-effect-free verification that the script loads and the
  PowerShell runtime can be inspected on the target host. Cannot be
  combined with `-SkipEnvCheck` (mutually exclusive — rejected at
  startup with a clear error message). Can be combined safely with
  `-DryRun`. See [`SPEC.md`](./SPEC.md) §A.7 for the parameter contract
  and the early-exit semantics.
- **`PSScriptAnalyzerSettings.psd1`** (sibling file) — project-local
  PSScriptAnalyzer configuration documenting six rules excluded
  project-wide with rationale for each (`PSAvoidUsingWriteHost`,
  `PSUseSingularNouns`, `PSProvideCommentHelp`,
  `PSUseShouldProcessForStateChangingFunctions`,
  `PSAvoidUsingEmptyCatchBlock`, `PSAvoidUsingPositionalParameters`).
  Per-occurrence exemptions are inline via
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]` with a
  Justification string.
- **Three GitHub Actions CI workflows** under `.github/workflows/`
  at the repository root:
  - STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on PowerShell 7.x).
  - STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 +
    `-EnvironmentInfoOnly` smoke). Triggered by STAGE 1 success.
  - STAGE 3 — Windows release verification (full `-DryRun` execution).
    Triggered by `release/published`.

  Both stages 1 and 2 upload SARIF output to GitHub Code Scanning.
  CI governance (timeout tiers, naming, fork-PR handling) is documented
  in the repository-root `/SPEC.md`. See [`SPEC.md`](./SPEC.md) §A.11
  *Continuous Integration* and [`TESTING.md`](./TESTING.md) §7 for the
  consumer-facing description.
- **`SPEC.md` updates**: §A.7 now lists `-EnvironmentInfoOnly` in the
  standard-switch table and adds its mutual-exclusion rule against
  `-SkipEnvCheck`; §A.11 gains a new *Continuous Integration*
  subsection; Part C — Quality Gates gains a new *CI gates* checklist.
- **`TESTING.md` §7** rewritten from *Outlook on CI/CD automation* to
  *Implemented CI*, documenting each STAGE, the `-EnvironmentInfoOnly`
  contract, how to read workflow output (badges / Actions tab / Code
  Scanning), and what CI does not cover.
- **CI status badges** (STAGE 1 / STAGE 2 / STAGE 3) in `README.md`
  and `README.ja.md` immediately after the title.

### Changed

- **Internal: `_DebugTrace_WriteJsonlLine` parameter renamed from
  `$Event` to `$EventObject`.** `$Event` is a PowerShell automatic
  variable populated inside event-subscriber action blocks
  (`Register-ObjectEvent`, etc.); reusing the name shadowed the
  built-in and would have silently misbehaved if the function were
  ever called from inside such a block. Five usage sites inside the
  function updated; callers are unaffected because every call site
  passes the argument positionally. Flagged by PSScriptAnalyzer rule
  `PSAvoidAssignmentToAutomaticVariable`.
- **Internal: `Export-DebugTraceJson`** gains `[OutputType([string])]`
  to document the return type (the function returns the output file
  path) and satisfy PSScriptAnalyzer's `PSUseOutputTypeCorrectly`.
- **Internal: `Show-PowerShellEnvironment`** carries a
  `SuppressMessageAttribute` for `PSAvoidUsingWMICmdlet` against the
  intentional `Get-WmiObject` fallback path used when CIM is
  constrained on the target host. The fallback is required for PS 5.1
  parity on some Server Core / container images.
- **Internal: `Show-FinalReport`** carries a `SuppressMessageAttribute`
  for `PSReviewUnusedParameter` against the `-LogPath` parameter,
  which is preserved as part of the function's stable signature
  even though the current body does not yet emit it.

## [r25] — 2026-05-18 — `strip-v-prefix-from-shorttag`

### Changed

- `$Script:ScriptShortTag` no longer prepends a literal `v` to the
  version string. The previous format `'v{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash`
  produced strings such as `vspeakerdeck-2026.05.18-r24/<hash>` in every
  phase header, banner, DebugTrace event, and run summary. Because
  `$Script:ScriptVersion` already starts with `speakerdeck-`, the `v`
  glued to it read as the meaningless token `vspeakerdeck` to a human
  eye. The format string is now `'{0}/{1}'`, producing
  `speakerdeck-2026.05.18-r25/<hash>`.
- `SPEC.md` A.3 (Banner & Version Identification) updated: the
  pseudo-code example for `$Script:ScriptShortTag` and the Banner block
  layout example no longer show the `v` literal.
- `README.md`, `README.ja.md`, `SPEC.md`, and `TESTING.md` phase-header
  examples updated to match the new format.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r25`,
  `$Script:ScriptTag` set to `strip-v-prefix-from-shorttag`.

### Verified

- `psa.py` v3.3.0 with `PSAP0003` / `PSAP0004` opt-ins:
  **0 errors / 0 warnings / 0 info** against the updated script.

### Notes

- This is a presentation-only fix; the only runtime difference is a
  one-character-shorter string emitted at every banner / phase header
  / debug trace event. No CSV / JSONL / output-file format changes.

## [r24] — 2026-05-18 — `remove-upstream-repo-references`

### Changed

- All references to the upstream repository
  `usui-tk/Deploy-Drivers-For-WindowsServer` have been removed from the
  in-script comments, `README.md`, `README.ja.md`, `SPEC.md`,
  `CHANGELOG.md` (this file), and `TESTING.md`. The Debug Trace Facility
  and the host-configuration helpers introduced in r23 are now
  documented as self-contained features of `Download-SpeakerDeck.ps1`;
  the script is the single source of truth in this repo.
- `SPEC.md` Part A.1 reorganised: the former `A.1.1 Reference PowerShell
  scripts` section (which pointed at the upstream repo) has been
  removed, and the remaining sub-sections renumbered:
  - `A.1.2 Static analyzer` -> `A.1.1`
  - `A.1.3 Companion specifications (this folder)` -> `A.1.2`
  - `A.1.4 Companion in-house script (latest reference)` -> `A.1.3`
    (and updated to list all reusable assets exposed by the in-house
    script, including the logging helpers and `Set-ConsoleUtf8` /
    `Set-Tls12`, so it stands alone without the upstream cross-reference)
  - `A.1.5 Folder naming convention for target-specific scripts` -> `A.1.4`
- `A.13 Reuse before invention` simplified from a three-step procedure
  (in-house -> upstream URL -> first principles) to a two-step procedure
  (in-house -> first principles).
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r24`,
  `$Script:ScriptTag` set to `remove-upstream-repo-references`.

### Verified

- `psa.py` v3.3.0 with `PSAP0003` / `PSAP0004` opt-ins:
  **0 errors / 0 warnings / 0 info** against the updated script.

### Notes

- This release contains no functional changes; behaviour is identical
  to r23. It is a documentation-cleanup release that consolidates the
  story around the in-house implementation as the sole canonical
  reference within this repo.

## [r23] — 2026-05-18 — `debugtrace-facility-and-pdfmeta-poc-removal`

### Added

- **Debug Trace Facility** (Section 1b, ~700 lines). Three integrated
  subsystems share one set of trace primitives:
  - **Trace primitives** (`Start-DebugTrace` / `Set-DebugStep` /
    `Stop-DebugTrace` / `Format-DebugFailure` /
    `Write-DebugFailureReport`) record per-step checkpoints inside
    complex function bodies so a failure can be localised to a single
    step name rather than just a function name.
  - **JSONL file output** (`Enable-DebugTraceFileOutput` /
    `Disable-DebugTraceFileOutput` /
    `Get-DebugTraceFileOutputStatus`) streams every trace event in
    real time to `work/logs/debugtrace.jsonl` as a UTF-8-with-BOM
    append-only log; events emitted before file activation are
    buffered in memory and flushed in one go when activation
    succeeds.
  - **JSON point-in-time export + auto-export-on-failure**
    (`Export-DebugTraceJson` / `Enable-AutoExportOnPhaseFailure`)
    writes a self-contained snapshot of the active stack, completed
    frames, and per-phase registry to
    `work/diag/debugtrace_export_<phaseId>_<timestamp>.json`; the
    top-level catch handler triggers this automatically when a phase
    throws.
- Each of `Test-Environment`, `Get-TotalDeckCount`, `Get-AllDeckList`,
  `Invoke-Phase4Evaluation`, `Invoke-Phase5FilenamePlan`,
  `Invoke-Phase6Download`, `Invoke-Phase7Reconciliation`, and
  `Invoke-Phase8UndatedReclassify` is now wrapped in
  `Start-DebugTrace -PhaseId 'PNN'` / `Stop-DebugTrace`, with
  `Set-DebugStep` checkpoints at the major operational boundaries
  (HTTP fetches, CSV writes, parallel pool start/stop, etc.).
- Helper functions `Set-ConsoleUtf8` (sets all three encoding sources:
  `Console.OutputEncoding`, `Console.InputEncoding`, `$OutputEncoding`)
  and `Set-Tls12` (TLS 1.2/1.1/1.0 fallback bitmask) extracted from the
  original inline `try { }` blocks for reuse and clearer call-site
  intent.

### Changed

- The top-level `catch` handler now calls
  `Write-DebugFailureReport $_ -IncludeStepHistory -AutoExport` in
  addition to its existing `Write-Host` output, so an unhandled
  exception produces a JSON snapshot under `work/diag/` even when
  the user did not invoke any explicit diagnostic command.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r23`,
  `$Script:ScriptTag` set to
  `debugtrace-facility-and-pdfmeta-poc-removal`.

### Removed

- **`Test-PdfMetadata.ps1`** (the read-only PoC that validated the
  PDF-metadata parsing logic before Phase 8 was productionised) has
  been deleted. The same parsing path now lives in
  `Get-PdfMetadata` inside `Download-SpeakerDeck.ps1`, exercised on
  every real run in Phase 8, so the standalone PoC no longer earned
  its keep. Documentation references to the file have been removed
  from `README.md`, `README.ja.md`, `SPEC.md`, and `TESTING.md` in
  the same revision.

### Verified

- `psa.py` v3.3.0 with `PSAP0003` / `PSAP0004` opt-ins:
  **0 errors / 0 warnings / 0 info** against the 5,156-line script.

### Notes

- This is a feature release that significantly enlarges the script
  (4,107 -> 5,156 lines; +1,049). The added facility is dormant
  unless a function actively calls `Set-DebugStep`; the runtime cost
  on the happy path is bounded by one frame open / one frame close
  per phase plus a handful of `Set-DebugStep` calls inside each
  phase.
- The existing Phase 6 per-deck failure diagnostics
  (`Write-FailureDiagnostic`, `Add-ErrorJsonlEntry`,
  `P06_errors.jsonl`, `work/diag/failed/`) are preserved unchanged.
  DebugTrace is a complementary cross-phase mechanism that operates
  at operation-level granularity, not a replacement for the
  download-specific diagnostics.

## [r22] — 2026-05-18 — `psa-header-comment-sync`

### Changed

- Script header comment block updated to reflect current static-analysis
  toolchain: `psa.py` v3.3.0 (36-rule check set `PSA1001..PSA9002` plus
  opt-in `PSAP0001..PSAP0004`), replacing the previous stale reference
  to `v3.1.0 (28-rule check set PSA1001..PSA7001)`.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r22`,
  `$Script:ScriptTag` set to `psa-header-comment-sync`.

### Notes

- This release contains no functional changes; behaviour is identical
  to r21. It is a pure documentation cleanup release synchronising the
  in-script reference to the current `psa.py` toolchain.

## [r21] — 2026-05-18 — `changelog-md-policy-cleanup`

### Changed

- All inline `# rNN:`, `(rNN)`, and prose references to past revisions
  (`# before r13`, `# In r06 and earlier`, `# As of r08:`, etc.) have
  been removed from `Download-SpeakerDeck.ps1`. The descriptive prose
  has been rewritten to describe current behaviour in revision-neutral
  terms. Per-release history now lives exclusively in this `CHANGELOG.md`.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r21`,
  `$Script:ScriptTag` set to `changelog-md-policy-cleanup`.
- Verified clean against `psa.py` 3.3.0 with PSAP0003 and PSAP0004
  enabled: 0 errors, 0 warnings, 0 info.

### Added

- This `CHANGELOG.md` file. Future revisions will be appended here in
  Keep a Changelog 1.1.0 format rather than being recorded in inline
  comments.

### Notes

- This release contains no functional changes; behaviour is identical
  to r20. It is a pure source-code cleanup release applying the
  repository-wide revision-history policy.

## [r20] — Earlier — `upstream-spec-style-alignment`

### Changed

- SPEC.md content and structure aligned with the upstream SPEC pattern
  used in other `scripts/powershell/*` sub-projects.

## [Pre-r20]

The per-revision history for r1 through r19 is not formally recorded
in this CHANGELOG file. Earlier releases tracked changes via inline
`# rNN:` comments in the script body. Those comments were removed in
r21 (see above) per the repository-wide revision-history policy
([root README, "Revision History Policy"](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md#revision-history-policy)),
which centralises per-release notes in `CHANGELOG.md`.

For the historical context that prior revisions encoded, refer to the
Git history of `Download-SpeakerDeck.ps1` in the
[`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r25]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r24]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r23]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r22]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r21]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
[r20]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/powershell-download-speakerdeck-oracle4engineer
