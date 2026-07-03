---
id: 0031
title: derived-governance-battery-lists
status: accepted
date: 2026-07-03
supersedes: []
superseded_by: null
governs: ["quality-tools/document-conformance-gate/doc_gate.py §--reconstructed", "quality-tools/reference-health-gate/refcheck.py §R6"]
---

<!-- AI read-contract: authoritative for HOW the governance battery's
     project-scoped inputs are OBTAINED. Load-bearing decisions: the manifest
     kind=project rows are the SINGLE project registry (no second list
     anywhere); doc_gate --reconstructed with no FILE args DERIVES its file
     set from that registry (maturity incubating+, doc-provenance-pinned
     *.md discovery; a covered project with zero pinned docs is a FINDING);
     refcheck gains R6 (STATUS kind-breakdown / project-maturity claims ==
     the actual manifest); NO hand-kept stream table is ever created - the
     derived views (canon-manifest-tool `list`, the derived doc_gate scan)
     are the table. -->

# ADR 0031 — derived governance battery lists (the manifest is the single project registry)

## Status

Accepted (2026-07-03). Implements the derivability consequence announced by
ADR 0024 ("The governance battery lists ... become derivable from the
manifest's project rows ... instead of being hand-maintained conventions").

## Context

Two project-scoped battery inputs were hand-maintained conventions:

1. **The `doc_gate --reconstructed` file lists.** The gate itself took only
   explicit FILE arguments; the per-project lists lived as prose in
   `governance/gate-coverage.md`. Two defects were PROVEN in the field:
   - The prose list had **already drifted from reality**: it said "ol-aws 4
     files (TESTING intentionally out)" while `TESTING.md` had gained its
     doc-provenance pin at B1 - the live doc-set is 5 files, and the file's
     own governance note still claimed it carried no pin (a self-
     contradiction fixed alongside this ADR).
   - The **no-argument footgun**: `--reconstructed` with zero FILE args
     scanned zero files and printed PASS (a named limitation since P5).
2. **The "STATUS stream table".** Announced as derivable by ADR 0024, it was
   never actually created - but the same staleness class it would have
   suffered was hit twice on 2026-07-03 in STATUS's hand-written manifest
   breakdowns (a stale Gates paragraph and a truncated ADR index), i.e. the
   problem is real even without the table.

The registry that both inputs derive from already exists and is validated:
the manifest `kind=project` rows (ADR 0024) carrying `canonical_location`
and `maturity`.

## Decision

1. **Single registry.** The manifest `kind=project` rows are the ONLY
   project registry. No second list - not in gate prose, not as a STATUS
   table, not in tool configs - may be introduced for battery scoping.
2. **doc_gate derived mode.** `doc_gate --reconstructed` with **no FILE
   arguments** derives its file set from the registry:
   - scope = rows with `maturity` in {`incubating`, `governed`} (the
     ADR 0024 gate table: the L3 doc-set gate is REQUIRED from incubating
     up; `sandbox` is exempt; `archived` is out);
   - a covered project's set = every `*.md` under its `canonical_location`
     (hidden directories skipped) whose YAML front matter carries the
     ADR 0019 `doc-provenance` pin - the pin IS the membership predicate,
     so stream-local unpinned artifacts (e.g. test RESULTS files) stay out
     without any exclusion list;
   - a covered project with **zero** pinned docs is a FINDING (its REQUIRED
     doc-set is missing). The old zero-file-PASS footgun is thereby
     structurally impossible in derived mode.
   Explicit FILE arguments keep their existing spot-check semantics.
3. **refcheck R6.** The reference-health gate additionally verifies, inside
   STATUS's current-truth zones (the R5 zones), that every backticked
   manifest **kind-breakdown claim** (`N \`<kind>\``) and every **project
   maturity claim** (`N \`project\` [<maturity>]`) equals the actual
   manifest. Claims that do not appear are not required (same philosophy as
   R5: probe what is written, do not dictate what must be written).
4. **No stream table.** The human-readable views of the registry are the
   existing `canon-manifest-tool list` output and the derived doc_gate scan
   header. A hand-kept table would recreate the exact staleness class this
   ADR removes.

## Consequences

- The battery instruction shrinks to `doc_gate --reconstructed` (no
  arguments); adding, promoting, or archiving a project re-scopes the gate
  automatically through its manifest row - one CRUD write, zero prose edits.
- gate-coverage's hand-kept per-project list is retired; the footgun note is
  replaced by the derived-mode contract.
- STATUS may keep its narrative breakdowns - R6 makes them machine-checked
  claims instead of trusted prose.
- The L3 mode no longer incidentally requires `governance/doc-format/`
  (main() enters the L3 branch before loading L1) - it depends on exactly
  what it uses: the manifest and the named/derived files.

## Considered options

- **Registered file lists** (a `reconstructed_docs` field on project rows):
  rejected - a second hand-fed list with schema/CRUD surface; the
  doc-provenance pin already IS the ground-truth membership marker.
- **No-arg = refuse** (keep lists, close only the footgun): rejected - keeps
  the proven-stale hand-kept lists alive.
- **A generated STATUS stream table** (renderer + checker): rejected as a
  new artifact to keep in sync; the registry views already exist.
