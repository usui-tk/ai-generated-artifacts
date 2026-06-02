---
id: 0015
title: canonical-normalized-hash-contract
status: accepted
date: 2026-06-02
supersedes: []
superseded_by: null
governs: ["governance/SPEC.md §machinery", "governance/schema/observation.schema.json", "governance/state/manifest.jsonl"]
---

<!-- AI read-contract: authoritative for the CANONICAL NORMALIZED-HASH CONTRACT — the
     single, computable definition of the `hash=` carried on canonical markers and the
     `*_hash_norm` fields on observations. Fixes (1) the normalization + algorithm + width
     (strip comments/strings -> collapse whitespace -> sha256, 16 hex) so the hash is
     reproducible by any conformant tool; (2) a read-side validator check (G) that recomputes
     and compares, catching a stale/hand-edited/mis-stamped hash regardless of origin; (3) a
     write-side re-stamp tool as the tool-mediated edit path for marker hashes during the
     interim before the ADR 0011 CRUD tool (P3a); and (4) the interim metadata guardrail:
     marker/manifest edits do not land unless the validator (incl. G) is green at the
     §Y dry-run, BEFORE the patch is cut. Promotes baseline §4.5 (gate=normalized,
     raw=forensic, forked=frozen) into the in-repo SPEC. Another worked example of the ADR
     0011 process under its transitional clause (decision = this ADR; in-conversation [AUTH];
     canon marker metadata corrected by a tool before the P3a CRUD tool exists). The P3
     canonical-drift scanner consumes this contract. Read on-demand. If reversing, supersede
     via a new ADR. -->

# 0015 - Canonical normalized-hash contract

## Status

Accepted. Promotes the baseline §4.5 hash-policy decision into the in-repo SPEC and makes it
computable. Follows the [ADR 0011](./0011-canon-change-management-governance.md)
change-management process under its transitional clause (the canon marker metadata is
corrected by a tool, walked by hand, before the P3a CRUD tool exists). Read alongside
[ADR 0003](./0003-standalone-tool-principle.md) (standalone tools / no-cross-reference) and
[ADR 0008](./0008-canon-release-model.md) (SemVer release model).

## Context

The cross-repo governance model gates a vendored copy against the canon by comparing a
**normalized hash**: baseline §4.5 [DECIDED] that the gate judgement is *normalized* (apply
the PSA8001 technique — strip comments/strings to whitespace, collapse whitespace runs to a
single space — identically to the canonical and the inlined region, so the comparison is
encoding-neutral under BOM+CRLF inlining), with a *raw* verbatim-byte hash recorded as
forensic-only metadata, and `forked` regions frozen (`forked-frozen`), not compared.

That decision was never carried into the in-repo SPEC, and three gaps remained:

1. **No computable definition.** §4.5 fixed the normalization *rule* but not the **hash
   algorithm or its width**. The canonical markers stamped at P2.6 carry a 16-hex value, but
   no recorded procedure reproduces it. `psa.py`'s PSA8001 uses `sha256[:12]` for a *different*
   purpose (relative cross-file function-body comparison), which both differs in width and was
   never the marker contract.
2. **No verification.** The governance-state validator parsed the marker's `hash=` but never
   recomputed it; no gate checked it. As a result a **stale marker hash went undetected**: at
   the canon-creation commit (`5d5f0b1`) 20 of the 58 units were stamped with a hash that does
   not match their own region body, and every standing gate has been green over that
   inconsistency ever since. The P2.6 SemVer amend (`e76279f`) rewrote only `version=`, never
   `hash=`, so the drift persisted. The bodies were never edited after creation — the markers
   were simply mis-stamped at birth.
3. **No guardrail until P3a.** ADR 0011 makes the eventual write path tool-only, but its CRUD
   tool is a later phase (P3a). In the interim, marker/manifest edits are done by hand or by
   ad-hoc script, exactly the conditions that produced the mis-stamp — and a *tool-only* rule
   would not have caught it, because the mis-stamp came **from a tool**.

The drift gate is meaningless until the thing it compares against is pinned, so this is the
opening sub-step of P3 (it precedes the P3 consumer-drift scanner, which consumes the contract).

## Decision

We will fix the **canonical normalized-hash contract** as the single computable definition,
and enforce it with a read-side check plus a tool-mediated write path.

1. **The contract.** For a marker region (the lines strictly between the `>>> CANONICAL`
   BEGIN line and the `<<< CANONICAL` END line, LF-joined, BOM-stripped): normalize by
   `strip_strings_and_comments` (the PSA8001 tokenizer: comments and string contents become
   whitespace, `$variables` inside double-quoted strings preserved) then collapse all
   whitespace runs to a single space and strip the ends; the hash is
   **`sha256(normalized).hexdigest()[:16]`** (16 lowercase hex). This is the value of marker
   `hash=`, of observation `canonical_hash_norm` / `observed_hash_norm`, and the gate
   comparison. The verbatim-byte (raw) hash remains **forensic-only** (`observed_hash_raw`),
   never the gate. `forked` regions are **frozen, not compared** (`drift=forked-frozen`);
   whole-tool records carry null hashes and `drift=n/a` (baseline §4.4). `hash_what` records
   the procedure in words.
2. **Width is deliberate and not unified with PSA8001.** The canonical hash is 16 hex; PSA8001
   keeps its 12-hex relative-comparison hash for its own rule. They share the *normalization*
   but not the *width or purpose*.
3. **Conformance by golden vectors, not shared code.** Tools stay single-file, stdlib-only,
   no-cross-reference (ADR 0003): the normalizer travels as a **reuse-by-copy** block, and each
   copy's conformance to this one contract is pinned by a fixed set of **golden vectors**
   (GV-1..GV-5) in the validator self-test — a shared *test contract*, not a shared import.
4. **Read-side check G (verification).** The governance-state validator recomputes each
   marker's hash from its region body and fails on mismatch (check G). It also extends check D
   to verify the marker's `policy=`/`binding=` against the manifest defaults. Check G is
   input-agnostic: it catches a stale hash no matter how it arose — hand-edit, script, or a
   mis-stamping tool (it is what catches this ADR's own 20-unit defect). Per ADR 0011 principle
   1 (read-side correction may precede the write tool), G lands now.
5. **Write-side re-stamp tool (tool-mediated edit).** A single-file `quality-tools/
   canon-hash-restamp/` tool recomputes and (on `--write`) rewrites only the marker `hash=`
   token in place, leaving body / version / policy / binding / BOM / CRLF byte-identical.
   Re-stamping is **metadata-only and never a code change**. It is the tool-mediated write path
   for marker hashes in the interim, paired with check G which independently re-verifies its
   output.
6. **Interim metadata guardrail (until P3a).** Until the ADR 0011 CRUD tool exists, any change
   touching `manifest.jsonl` or a canonical marker MUST pass the governance-state validator
   (including G) **at the §Y dry-run, on the working tree, before `git format-patch`** — not
   only in the post-`git am` battery. Verification-before-patch is the guardrail; tool-mediated
   writes (the re-stamp tool now, the CRUD tool at P3a) are the complementary write-path
   restriction. This guardrail is the bridge to, and is superseded by, the ADR 0011 CRUD tool.
7. **The 20 mis-stamped hashes are corrected without a version bump.** The bodies are
   unchanged, so no code was released; correcting marker metadata MUST NOT move
   `canonical_version` (SemVer signals code release, not a metadata fix). The correction is
   recorded in the commit + CHANGELOG audit trail (ADR 0011).

`governs: governance/SPEC.md §machinery` (a bidirectional back-ref is added in the same commit).

## Consequences

- The drift gate now has a pinned, reproducible reference; the P3 consumer-drift scanner can
  be authored against a real contract (it reuse-by-copies the normalizer and passes GV-1..5).
- A whole class of latent defect — a marker hash that silently disagrees with its body — is now
  a hard gate failure, not an invisible inconsistency. The standing gate battery gains check G
  and grows the validator self-test from 7 to 15 cases.
- Marker-hash edits become tool-mediated immediately (re-stamp tool) and verification-gated
  immediately (check G at §Y), well before the full CRUD tool, narrowing the transitional
  window's risk without pulling P3a forward.
- The 16-vs-12 hex split is now explicit, preventing a future "unify the hashes" mistake.
- Negative: a second reuse-by-copy of the tokenizer now exists (validator + restamp, soon the
  scanner). This is accepted because golden vectors pin all copies; the alternative (a shared
  import) violates ADR 0003.

## Alternatives considered

- **(a) Reverse-engineer and freeze the existing 16-hex values.** Rejected: 20 of them are not
  reproducible by any candidate procedure (they were mis-stamped), so freezing them would
  enshrine a defect and leave the contract un-recomputable.
- **Tool-only write restriction as the guardrail (no verification gate).** Rejected as
  insufficient: the defect this ADR fixes was produced *by a tool*. Restricting the write path
  cannot catch a misbehaving producer; only recompute-and-compare (check G) can. Tool-mediation
  is kept as the complement, not the primary guardrail.
- **Unify the canonical hash with PSA8001's 12-hex.** Rejected: different purpose (relative
  duplicate-detection vs persisted sync claim) and width; coupling them would make one rule's
  change silently alter the other.
- **A shared imported hashing module.** Rejected: violates ADR 0003 (tools are single-file,
  no-cross-reference). Conformance is instead pinned by golden vectors.
- **Bump `canonical_version` on the 20 corrected units.** Rejected: no code changed; a SemVer
  bump would misrepresent a metadata fix as a release.
