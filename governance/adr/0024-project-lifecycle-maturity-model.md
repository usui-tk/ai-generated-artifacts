---
id: 0024
title: project-lifecycle-maturity-model
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §execution-framework"]
---

<!-- AI read-contract: authoritative for the project-lifecycle maturity model - the stage
     set (sandbox / incubating / governed / archived), the stage-scoped governance
     obligations, the promotion triggers, and the kind=project manifest lifecycle record
     that carries the maturity value. Applies at project/tool granularity ONLY;
     asset-level release readiness stays SemVer (ADR 0008/0018). Read SPEC
     §execution-framework for the current-truth view and AGENTS.md §10 for the operating
     procedure. Do not re-decide; supersede via a new ADR if reversing. -->

# 0024 — Project-lifecycle maturity model (stage-scoped governance obligations)

## Context

Two proven gaps motivated this model. **(1) Bootstrap was undefined:** nothing said which
governance obligations apply to a project from birth, and full governance from day one is
not feasible. The live evidence is `projects/bash-rhel-container-testsuite`: it was **born
with the template canon** (its r01 doc-set carries doc-provenance pins), yet it ran
**r01–r27 outside the governance tracker** — no manifest registration, no STATUS tracking —
and then needed a 3-revision retrofit (r28–r30 + the B0–B2 arc) to become conformant. The
path worked, but it was exceptional and implicit rather than official. **(2) The maturity
axis existed but was dormant:** the template-formalization arc (TF.1) had already
**\[DECIDED\]** a CNCF-aligned maturity axis (field `maturity`, placement top-level
OPTIONAL on the manifest schema, decoupled from physical placement) and then deferred the
schema property and value assignment. Meanwhile the 2026-07-03 program re-anchor made
maturity-scoped governance the primary execution axis (the G-program), so the deferral no
longer holds.

## Decision

1. **Stage set (project/tool granularity only — F2).** Every project under `projects/`
   carries exactly one lifecycle stage: **`sandbox` → `incubating` → `governed`**, plus
   **`archived`** (terminal, reachable from any stage). **Graduation (separate-repo
   spin-out) remains a distinct physical event, orthogonal to maturity**, with
   `maturity=governed` as its prerequisite. Asset-level units (helpers, spec-regions,
   templates, tools) keep their existing SemVer release-readiness machinery (ADR
   0008/0018); the maturity axis never applies below project/tool granularity.
2. **Domain supersession (recorded, per M2/M4(C)).** The TF.1 pin named the third stage
   **`graduated`** (CNCF-verbatim). This ADR **supersedes that domain label with
   `governed`**: the top stage means "full governance obligations in place", and reusing
   "graduated" would collide with the physically distinct graduation event. The TF.1
   axis itself (CNCF-aligned, decoupled from placement, top-level OPTIONAL) is honored
   unchanged; its "apply the schema property at graduation" **timing deferral is also
   superseded** — the property lands now, with the G-program.
3. **Stage × obligation table (the normative core).** Obligations accumulate monotonically;
   `archived` freezes the doc-set (disclaimer retained) and leaves all gates.

   | Obligation | sandbox | incubating | governed |
   |---|:---:|:---:|:---:|
   | Template-canon doc-set + doc-provenance pins (README/README.ja/SPEC/CHANGELOG; TESTING when tests exist) | REQUIRED | REQUIRED | REQUIRED |
   | AI disclaimer + language policy (English/ASCII code + commits; bilingual README pair) | REQUIRED | REQUIRED | REQUIRED |
   | Encoding contract + syntax gates (e.g. `bash -n`, `Parser::ParseFile`) | REQUIRED | REQUIRED | REQUIRED |
   | Full static analysis 0/0/0 (shellcheck / PSScriptAnalyzer + psa.py) | exempt | REQUIRED | REQUIRED |
   | Manifest lifecycle record (`kind=project` row with `maturity`) | exempt | REQUIRED | REQUIRED |
   | STATUS tracking (governance tracker) | exempt | REQUIRED | REQUIRED |
   | `doc_gate --reconstructed` in the battery lists + bilingual lock-step ENFORCEMENT | exempt | REQUIRED | REQUIRED |
   | Vendored Part A (where a family spec home exists; rule-of-two still governs whether one exists) | exempt | exempt | REQUIRED |
   | `consumers[]` registration on vendored units + offline tests + CI workflows | exempt | recommended | REQUIRED |
   | Per-phase loop for governance-relevant changes (functional maintenance stays stream-owned, two-speed) | exempt (exploration default, ADR 0025) | exempt (stream-style) | REQUIRED |

4. **Promotion triggers.** `sandbox → incubating`: the user's **continue/publish
   decision** (a declaration, not a gate). `incubating → governed`: a **conformance pass**
   — one reconciliation pass that turns every governed-column obligation green at once
   (full static gates + doc_gate + Part A vendoring where a home exists); the
   rhel-testsuite r28–r30 / B2 pass is the procedural precedent. `→ archived`: user
   declaration; the manifest row's `maturity` is updated, the project leaves the battery
   lists, the doc-set is frozen as-is.
5. **The lifecycle record.** A `kind=project` manifest row (`unit_id =
   project.<directory-name>`, `canonical_location = projects/<directory-name>`,
   `maturity`, `consumers: []`) is the machine-readable stage carrier. It is a
   **lifecycle record, not a region unit**: the region fields (`canonical_version`,
   `change_policy`, `binding_mode`, `tested`, `platform_scope`) are absent by contract
   (`manifest.schema.json` allOf branch; the CRUD tool enforces the same shape —
   TF-d2 tool/schema synchronization honored). Registration happens at the
   sandbox→incubating promotion; a sandbox project deliberately has **no** manifest row.
6. **Retroactive values.** The four live projects are all past a P6/B2-class conformance
   pass and are registered `maturity=governed`: `powershell-update-windows-server-iso`,
   `powershell-download-speakerdeck-oracle4engineer`, `bash-ol-aws-ami-builder`,
   `bash-rhel-container-testsuite`. The lower stages are first exercised by the next real
   new project.
7. **Bootstrap kit.** The sandbox birth-kit is operationalized by AGENTS.md §10 (the
   procedure) and the `governance/templates/scaffold-project-bootstrap-prompt.template.md`
   scaffold (the session-start prompt for a new project). Sandbox default working
   discipline is **exploration mode** (ADR 0025).

## Consequences

- New projects have an official, low-friction birth path: render the doc-set from the
  template canon, satisfy the three always-on obligations, and develop freely in
  exploration mode — with a defined, machine-recorded ladder to full governance instead
  of an implicit retrofit.
- The governance battery lists (doc_gate `--reconstructed` sets, STATUS stream table)
  become derivable from the manifest's project rows (incubating+ only) instead of being
  hand-maintained conventions; gates MAY scope themselves by stage.
- The manifest becomes the single index for projects as well as units (baseline §4.1
  preserved; no second registry file).
- A future stage change is a one-flag CRUD-tool update (`update --unit-id project.X
  --maturity Y`), transactionally validated like every manifest write.

## Considered options

- **Registry placement:** (a) manifest `kind=project` rows with a schema allOf branch
  (**chosen** — single index, honest shape); (b) ADR 0021-style sentinel values in the
  region fields (rejected — sentinel abuse for a shape that is genuinely different);
  (c) a separate `projects.jsonl` (rejected — second registry surface); (d) per-project
  SPEC front-matter (rejected — no central machine-readable index for gates).
- **Domain label:** `graduated` (TF.1-verbatim) vs `governed` (**chosen**; supersession
  recorded in §2 above).
- **Timing:** keep the TF.1 "at graduation" deferral (rejected — the G-program makes the
  axis the primary execution spine now).
