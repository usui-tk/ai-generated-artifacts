---
id: 0025
title: exploration-mode
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §execution-framework"]
---

<!-- AI read-contract: authoritative for exploration/RE mode - the light-discipline
     working mode for empirical, genchi-genbutsu, reverse-engineering, or spike work. It
     is the DEFAULT discipline of a sandbox-stage project (ADR 0024) and a declarable,
     time-boxed mode inside an incubating/governed project. Per-phase loop NOT applied;
     gates = syntax + encoding only; canon / vendored regions / governance/ are
     UNTOUCHABLE from inside the mode; exit = a conformance pass. By-products: knowledge
     -> documents/research/, runnable tools -> projects/ at sandbox stage. Read SPEC
     §execution-framework for the current-truth view. Do not re-decide; supersede via a
     new ADR if reversing. -->

# 0025 — Exploration/RE mode (the official light-discipline lane)

## Context

Empirical exploration — live-probe experiments, reverse engineering, spikes — conflicts
structurally with the per-phase loop (author → dry-run → sign-off → patch → battery):
the loop assumes the destination is known, while exploration exists to discover it.
The conflict is proven, not hypothetical: the `bash-rhel-container-testsuite` had to run
its genchi-genbutsu development (r01–r27) **outside the tracker entirely**, and the
Windows-servicing reverse-engineering arc produced knowledge that landed in
`documents/research/` while its working tool (a wsusscn2 analyzer) **never entered the
repository at all** — there was no defined receptacle. Forcing full governance onto
exploration had slowed real projects badly; the activity needs an official lane with
explicit boundaries, not ad-hoc exemption.

## Decision

1. **Two entry forms.** Exploration mode is **(a)** the **default working discipline of
   every `sandbox`-stage project** (ADR 0024), and **(b)** a **declarable, time-boxed
   mode inside an `incubating`/`governed` project** for a spike. Form (b) is declared in
   the project's `CHANGELOG.md` as an `[EXPLORATION]` entry stating scope, goal, and
   timebox; its working artifacts stay quarantined (a clearly-named subfolder, e.g.
   `spike/`, or out-of-repo Tier-P notes) until exit.
2. **Discipline while in the mode.** The per-phase loop is **not applied**; commits may
   land stream-style (subproject-scoped). Gates are **light**: the three always-on
   sandbox obligations only (template-canon doc-set presence for the project itself, AI
   disclaimer + language policy, encoding + syntax checks). Full static analysis,
   doc_gate battery membership, and vendoring obligations are suspended for the
   exploration artifacts.
3. **Hard boundary (non-negotiable).** From inside exploration mode, the following are
   **untouchable**: `reference-code/` canon bodies, any vendored region (code or doc),
   `governance/` (state, schema, spec homes, templates, ADRs), and Layer-0 root docs.
   If exploration reveals a needed canon/governance change, that change exits the mode
   and goes through the normal `[AUTH]` per-phase loop. Exploration never becomes a side
   door around the write-path gates.
4. **Empirical-record split.** Genchi-genbutsu narrative (probe logs, dead ends, raw
   findings) MAY stay in out-of-repo Tier-P design notes (ADR 0005); the project SPEC
   carries only the stable contract distilled from them. This makes the
   rhel-testsuite r01 pattern ("narrative rationale kept in the maintainer's design
   notes") official.
5. **Exit = a conformance pass.** Form (a) exits via the ADR 0024 promotion triggers
   (the incubating→governed conformance pass being the full-gate reconciliation). Form
   (b) exits when the spike's keepers are folded into the project mainline **through the
   project's normal full gates** (static analysis + doc_gate + tests), and the
   `[EXPLORATION]` entry is closed with the outcome; discards are deleted, not left as
   quarantine residue.
6. **By-product homing (F3).** Knowledge artifacts (research writeups, protocol maps,
   findings) → `documents/research/<topic>/`. **Runnable** tools/scripts with plausible
   re-use or maintenance → a new `projects/` entry at **sandbox** stage (the ADR 0024
   birth-kit applies — this is deliberately cheap). Discriminator for the border case: an
   artifact whose value is **frozen evidence** (a one-shot analyzer kept only so the
   findings are reproducible) MAY instead be filed under the research topic as a marked,
   unmaintained adjunct; anything expected to be **run again** goes to `projects/`
   sandbox. When in doubt: `projects/` sandbox.

## Consequences

- Exploration is inside the model, not an exception to it: a future rhel-style project
  is *born conformant-for-its-stage* instead of retroactively legitimized, and a future
  wsusscn2-style tool has a defined home from day one.
- The per-phase loop's authority is sharpened, not weakened: the hard boundary (§3)
  keeps every canon/governance write on the gated path, and C9/validator would catch a
  violation mechanically.
- Spikes inside governed projects gain an audit trail ([EXPLORATION] CHANGELOG entries
  with declared scope and a recorded outcome) at near-zero process cost.

## Considered options

- **Status quo (implicit out-of-tracker work).** Rejected: proven to produce retrofit
  cost (r28–r30 + B0–B2) and lost artifacts (the analyzer).
- **Declare spikes in STATUS instead of the project CHANGELOG.** Rejected: STATUS is the
  governance tracker; a spike inside a project is stream-scoped, and its CHANGELOG is
  already the stream's audit surface.
- **A dedicated `sandbox/` top-level directory.** Rejected: physical placement is
  decoupled from maturity (the TF.1 axis pin); a second project root would re-couple
  them and complicate graduation of the directory layout.
