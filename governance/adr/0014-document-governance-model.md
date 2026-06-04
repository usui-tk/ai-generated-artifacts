---
id: 0014
title: document-governance-model
status: accepted
date: 2026-06-02
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery"]
---

<!-- AI read-contract: authoritative for HOW project documents are governed across the
     repo boundary - the three cross-repo document classes (reference / own-and-reconstruct
     / vendored-copy), the document-template canon and its release/conformance discipline,
     the class-(reconstruct) reconstruction procedure including the graduation structural
     transform, and the rule that each reconstruction/sync point is also a quality gate.
     This ADR is the DOCUMENT analog of ADR 0007 (canon code QA) + ADR 0008 (canon release
     model): it fixes the PRINCIPLES; the implementing template bodies, the conformance
     gate, and the reconstruction procedure are frozen at Template Finalization (TF, before
     P5) and applied at P4-P7 / at graduation. It introduces NO new phase and NO renumbering.
     Builds on baseline §2.10 (the cross-repo axis), the M5 template-requirements register,
     and the Q3 per-phase exit checklist. Read on-demand. If reversing a point, supersede
     via a new ADR (one decision = one ADR). -->

# 0014 - Document governance model (cross-repo, template-canon, graduation-aware)

## Status

Accepted. The DOCUMENT analog of [ADR 0007](./0007-canon-code-functional-quality-assurance.md)
(canon functional QA) + [ADR 0008](./0008-canon-release-model.md) (canon release model);
complements [ADR 0005](./0005-session-handoff-protocol.md) (session-handoff / Tier-P) and
[ADR 0011](./0011-canon-change-management-governance.md) (change-management governance).
Builds on baseline §2.10 (the cross-repo axis), the M5 template-requirements register, and
Template Finalization (TF).

## Context

The code side now has a maturing cross-repo governance model: a manifest master + canonical
markers + normalized hash + a drift gate + a SemVer release gate (`version >= 1.0.0`,
ADR 0008). The organizing purpose of the whole effort is **graduation** - a subproject
spins out to its own dedicated repo (baseline §1.1; `update-windows-server-iso` is the
DECIDED first trigger). Baseline §2.10 already classifies documents on the cross-repo axis
(classes A/B/C below), and the plan already folds a class-(B)/advancement checklist into the
P5-P7 exit criteria (Q3) and requires doc-set conformance facts at TF.1.

But that classification is **design-substrate only**: from the in-repo decision layer,
document governance is effectively unrecorded. Three gaps follow:

1. **No recorded model.** The cross-repo document classes live in the baseline, not in any
   ADR; there is no authoritative decision an AI agent can read on-demand the way it reads
   ADR 0007/0008 for code.
2. **The document-template canon has no code-parity governance.** `governance/templates/`
   will hold the template bodies (TF.2), but with no version, no release gate, and no
   conformance gate - whereas the code canon is registered, versioned, tested, and gated.
3. **The graduation structural transform for documents is scattered.** The prefix-strip
   (§4.9), the relative->absolute link rebinding (§2.11), the ADRs-travel rule, and the
   doc-set recomputation (#4) are defined in separate places, never unified as one
   reconstruction procedure. "Graduation changes the structure, so a template cannot be
   applied verbatim" has no single home.

## Decision

Document governance is fixed by five principles.

### 1. Three cross-repo document classes are the model (baseline §2.10, now decided)

- **(A) reference** - central holds the canonical; other repos REFERENCE it via absolute
  URL + vendoring markers (shared Part A / `common.<family>.md`, shared helpers, whole-tool
  `psa.py`). Governed EXACTLY like code (markers / hash / drift gate). This ADR only NAMES
  it; the mechanism is the existing code mechanism, unchanged.
- **(B) own-and-reconstruct** - each repo holds its OWN `{README, README.ja, SPEC, TESTING,
  CHANGELOG}` + dotfiles, RECONSTRUCTED from the template canon (not vendored as a shared
  region, because these files are per-repo-unique). The document apparatus defined in this
  ADR is for class (B).
- **(C) vendored-copy** - central is canonical but a copy is embedded in the other repo
  because its local CI/tooling must read it (`AGENTS.md`-class governance). Named here;
  applied at P7 only.

### 2. `governance/templates/` is the document-template canon, at code parity

Per-repo-unique docs CANNOT be shared vendored regions, so class (B) uses template
RECONSTRUCTION, not region vendoring - a DIFFERENT mechanism, but the SAME governance grade
as code:

- templates are registered in the manifest (`kind=template`);
- each template carries a SemVer version with an ADR-0008-style release gate: `< 1.0.0` =
  not reconstructable into a graduated / cross-repo target; `>= 1.0.0` = reconstructable;
- a **conformance gate** checks the machine-checkable register requirements over a rendered
  doc-set: `.md` = LF encoding, governance-class cross-refs = absolute URL, README bilingual
  lock-step, role-of-document boundaries (history->CHANGELOG, future->SPEC), and doc-set
  membership (#4). This is the document analog of the canon-test gate; it is deliberately
  LIGHTER than the code drift gate (no per-file hash/marker on rendered docs).

**Scope boundary (clarification, 2026-06-04, from the ADR 0019 redesign).** The template
canon governs **documents** (human/AI-facing prose - README/README.ja/SPEC/TESTING/CHANGELOG,
community-health, the `.github` PR template) plus **repo-structural dotfiles that have no
master elsewhere** (`.gitattributes`/`.gitignore`/workflows). It does **NOT** govern
**tool-owned configuration** (e.g. `.psa.config.json`): that file's master is the owning tool
canon and consumers **follow-latest** from it ([ADR 0009](./0009-psa-canonical-lifecycle.md)),
not a reconstructed template - registering it here would create a second, competing master.
The discriminator is **master-ownership**: an artifact whose master another canon already owns
is referenced/followed, never re-mastered here. (A tool's own doc-set, e.g. psa.py's
README/SPEC, may be FORMAT-conformance-checked against the canon yet stays content-owned by
the tool.) This boundary is stated in full in the Layer-1 document-format definition.

### 3. Class-(B) reconstruction is structure-parameterized; graduation is a transform

The same template renders to a subproject path OR a repo root. **Graduation is a
reconstruction WITH a structural transform, not a copy** - this is why class (B) is named
"reconstruct". The unified procedure (consolidating §4.9 / §2.11 / Q3):

- §4.9 prefix-strip (`projects/<lang>-<name>/` -> repo `<name>`);
- relative -> absolute governance-ref rebinding (§2.11);
- ADRs travel with the graduating folder;
- doc-set membership (#4) recomputed for the target structure.

### 4. Every reconstruction/sync point is also a quality gate (conformance pass)

At migration (P4-P7), at graduation, or at ANY later sync, the same governed, RE-RUNNABLE
event applies per subproject: conform docs to the templates -> run the full gate battery ->
clear dispositioned deviations (e.g. the `$ks` finding - located by SYMBOL/context, never a
fixed line number, since the script evolves) -> land needed bug/feature fixes -> re-stamp
CHANGELOG. "Deploy the governed document structure" and "ensure quality" become ONE event,
not a one-shot migration step.

### 5. TF scope extension; the checklist stays in exit criteria; no renumbering

Template Finalization (TF, before P5) freezes the template BODIES **and** the reconstruction
procedure **and** the conformance-gate definition (plus the `kind=template` manifest
registration + version/release gate of principle 2). The Q3 per-phase exit checklist (§8.1)
gains the class-(B)/(C) reconstruction + conformance-pass items. CNCF `maturity` (esp.
`graduated`) stays deferred to TF.1 as an instance-level pin, unchanged. **No new phase and
no phase renumbering** - the existing TF and P4-P7 exit criteria absorb this decision.

## Consequences

- Document governance reaches code parity (registered / versioned / gated), giving AI-driven
  development a machine-checkable document contract and reducing judgment drift - the
  motivating problem.
- **Phase impact is enhancement, not restructuring** (acyclic DAG preserved; no renumbering):
  - **TF** absorbs the largest change - its bodies-output is extended with the reconstruction
    procedure, the conformance-gate definition, and the `kind=template` registration +
    version/release gate. The TF.1->TF.2 ordering and the TF<-P1-P3 / TF->P4-P7 dependency
    are unchanged.
  - **P3** (current) is not blocked; only its exit register front-load gains the ADR-0014
    template rows (template version/release columns, conformance-check items, reconstruction
    requirements) so the register is ready for TF.1.
  - **P4/P5/P6/P7** exit acceptance-checks gain "conformance gate passes"; P5/P6 already
    carry the Q3 class-(B) checklist, now explicitly coupled to the quality gate.
  - **P6** resolves the `$ks` seam: the dispositioned deviation is located by symbol/context,
    ending the line-8095 fragility.
  - **Graduation** (`update-windows-server-iso`, the §1.1 trigger) gets its document
    reconstruction procedure (principle 3) - the structural transform is now defined.
- Cost / negative: TF scope grows; templates must be authored structure-parameterized; a
  conformance-gate tool must be built (folds into TF / `quality-tools/`). Instance-level
  pins (template `kind` token wiring, version-gate granularity, the concrete conformance
  checks, CNCF `maturity` field/values) remain open until TF.1 per the existing register
  discipline.

## Alternatives considered

- **Make README/TESTING/CHANGELOG vendored regions like code helpers.** Rejected: these
  files are per-repo-unique; they cannot be a single shared region. Reconstruction is the
  necessary mechanism (this is the class-(A) vs class-(B) split).
- **Keep documents at register + TF only, with no ADR and no canon-parity.** Rejected: that
  is the status-quo gap - no recorded model, no version/release/conformance discipline, and
  the graduation transform left unhandled.
- **Author a standalone promotion/graduation checklist document.** Rejected per Q3 (the
  checklist is folded into per-phase exit criteria); this ADR records the MODEL, while the
  checklist items stay in the exit criteria.
- **Introduce a new document-governance phase.** Rejected: the existing TF and P4-P7 exit
  criteria already carry class-(B)/checklist hooks; an enhancement avoids renumbering and a
  fresh DAG-integrity proof.
