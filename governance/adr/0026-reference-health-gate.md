---
id: 0026
title: reference-health-gate
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for the reference-health gate (refcheck.py) - the
     offline reference-integrity gate over the Layer-0 root docs: R1 relative link
     targets exist, R2 referenced GitHub Actions workflow filenames exist, R5 STATUS
     current-truth row-count claims equal the actual manifest count. Scope = repo-root
     *.md + .github/*.md ONLY. Hypothetical workflow filenames must not be written as
     contiguous `.github/workflows/<name>.yml` paths (prose-shape rule). Read SPEC
     §machinery for the current-truth view and governance/gate-coverage.md for the
     scope/limitation inventory. Do not re-decide; supersede via a new ADR if
     reversing. -->

# 0026 — Reference-health gate (Layer-0 reference integrity, offline)

## Context

Restructurings had accumulated **silent residue in the Layer-0 root documents**,
because every existing gate scopes itself elsewhere: doc_gate to manifest-registered
md units and consumer doc-sets, the governance-state validator and the drift scanner
to reference-code. The 2026-07-03 grounding survey found, at Layer-0: README.md and
README.ja.md each carrying **8 dead CI-badge references** (the `scripts__*` workflow
files were renamed `projects__*` / `quality-tools__*` when the subprojects migrated,
and the badge table was never rewired), SPEC.md carrying stale workflow names and
retired `scripts/powershell/` paths, and AGENTS.md carrying **1 broken relative link**
plus a §2 Layers table still describing the retired topology. This is the same failure
class the 2026-06-11 session named ("a documented claim and its actual verification
scope diverge silently"), now on the reference plane. A companion single-fact failure
existed inside STATUS.md itself: on 2026-07-02 the Current-phase table claimed 83
manifest rows while the header narrative said 84 (index==body divergence inside one
file).

## Decision

1. **A new whole-tool gate owns Layer-0 reference integrity:**
   `quality-tools/reference-health-gate/refcheck.py` (stdlib-only, offline, exit 0/1),
   registered as `tool.reference-health-gate` @ 1.0.0 (ADR 0021 whole-tool convention;
   self-test shipped and green — D10).
2. **Scope (D7): the repo-root `*.md` files + `.github/*.md`, nothing else.**
   Project-level docs are owned by doc_gate (`--path` / `--reconstructed`) and the
   per-project streams; all-md scanning was rejected as a false-positive source
   (forensic/history text legitimately cites retired paths).
3. **Checks.** **R1** — every relative Markdown link/image target resolves to an
   existing repo path (fragments stripped; absolute http(s)/mailto out of scope).
   **R2** — every referenced workflow filename (in `.github/workflows/<name>.yml`
   paths and in `actions/workflows/<name>.yml` badge/action URLs, which are absolute
   but offline-decidable by filename) exists under `.github/workflows/`. **R5** —
   inside STATUS.md's two current-truth zones (the `| Current phase |` table row and
   the `Gates green` paragraph), every "N rows" / "N manifest rows" claim equals the
   actual `manifest.jsonl` row count (D8); historical zones are deliberately not
   probed, and "N helper rows"-style phrasings do not match.
4. **Gate-then-fix, demonstrated.** The gate landed first and detected **19 findings
   across 9 scoped files** on the live tree (R1 x1 AGENTS broken link; R2 x18 dead
   workflow references — including one NEW discovery beyond the known residue: SPEC's
   hypothetical-CodeQL text written as a resolvable path). The residue was then fixed
   in the same arc and closure proven by the gate returning **0 findings**.
5. **Prose-shape rule (the hypothetical-reference limitation).** R2 cannot
   distinguish a hypothetical workflow from a dead reference. Rather than adding a
   suppression mechanism, prose describing a *non-existent-by-design* workflow MUST
   NOT write it as a contiguous `.github/workflows/<name>.yml` path — name the file
   and the directory separately (SPEC's CodeQL future-consideration text was reworded
   accordingly). Named, with the other limitations (bare workflow-name tokens without
   a path prefix are not matched; prose path staleness is review-owned), in
   `governance/gate-coverage.md`.
6. **Battery placement.** refcheck (self-test + real run) joins the governance
   grounding scope and the per-phase gate battery alongside the validator and
   doc_gate.

## Consequences

- Layer-0 restructuring residue can no longer accumulate silently: a directory move
  or workflow rename that misses the root-doc rewiring fails the next battery.
- The 2026-07-02 index==body single-fact divergence class is machine-caught (R5).
- Two small authoring constraints exist: hypothetical workflow paths follow the
  prose-shape rule, and STATUS current-truth zones must carry the true manifest count
  (which is the point).

## Considered options

- **Extend doc_gate.** Rejected: doc_gate's scope contract is manifest-registered md
  units + consumer doc-sets (ADR 0020); Layer-0 root docs are neither, and mixing
  scopes would blur both boundaries (the same reasoning that kept validator D/G
  reference-code-scoped in ADR 0022).
- **All-md scanning.** Rejected (D7): false positives on forensic/history text;
  project docs are stream-owned.
- **An R2 suppression syntax** (inline ignore markers). Rejected: more machinery for
  exactly two prose sentences; the prose-shape rule is cheaper and self-documenting.
- **Skip R5.** Rejected (D8): the index==body failure class had already occurred and
  is cheaply machine-decidable when scoped to the two current-truth zones.
