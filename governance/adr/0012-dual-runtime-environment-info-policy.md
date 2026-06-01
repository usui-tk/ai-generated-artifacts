---
id: 0012
title: dual-runtime-environment-info-policy
status: accepted
date: 2026-06-01
supersedes: []
superseded_by: null
governs: ["reference-code/powershell/Public/Show-PowerShellEnvironment.ps1", "reference-code/powershell/Public/Export-DebugTraceJson.ps1"]
---

<!-- AI read-contract: authoritative for HOW the canon's debug/environment-reporting
     functions behave across the two supported PowerShell runtimes (Windows PowerShell 5.1
     and PowerShell 7.x / Core). Fixes the policy that a dual-runtime canon function must
     produce equivalent-quality information on BOTH runtimes - it may not silently degrade
     (omit data) on one of them - and that runtime-version reporting uses a value that
     carries the same MEANING on both (the executing .NET runtime version), not a key that
     exists on only one runtime. This is the first worked example of the ADR 0011
     change-management process (decision gate -> code -> quality gate), run under the
     transitional clause: principles applied by hand, no CRUD tool yet, decision recorded as
     this ADR with in-conversation [AUTH] in place of the not-yet-built gate machinery.
     Complements ADR 0007/0010 (the canon tests that surfaced the defect) and ADR 0011 (the
     process this follows). Read on-demand. If reversing, supersede via a new ADR. -->

# 0012 - Dual-runtime environment-info policy for canon debug functions

## Status

Accepted. First worked example of the [ADR 0011](./0011-canon-change-management-governance.md)
change-management process. Surfaced by the canon behavioral tests added under
[ADR 0007](./0007-canon-code-functional-quality-assurance.md) /
[ADR 0010](./0010-canon-test-taxonomy-and-data.md) (P2a.2).

## Context

The canon advertises support for **both** Windows PowerShell 5.1 and PowerShell 7.x
(Core). Two debug/reporting functions read `$PSVersionTable.CLRVersion`:

- `Show-PowerShellEnvironment` - prints a `CLR / .NET` line; it *attempts* to guard with
  `if ($pv.CLRVersion)`, but under `Set-StrictMode -Version Latest` the property access
  **throws on PS 7** because `CLRVersion` is not a member of `$PSVersionTable` there (the
  key is absent, not merely null). The guard is therefore ineffective on the very runtime
  it was meant to handle.
- `Export-DebugTraceJson` - composes `clrVersion = $PSVersionTable.CLRVersion.ToString()`
  with no guard at all; this throws on PS 7 (null/absent `.ToString()`).

The canon behavioral tests (P2a.2) exercised both off-Windows on PS 7 and exposed the
throw. The two tests were recorded as skipped with a pointer to this decision.

The defect is **not** "a missing null-check". The deeper question - the one that makes this
a decision rather than a one-line patch - is: **what information quality does a
dual-runtime canon function guarantee on each runtime?** Two framings were considered:

1. *Suppress-only (bug-fix / patch).* Guard the access so PS 7 does not throw; on PS 7 the
   CLR/.NET line is simply omitted or shown as "not available". The function stops crashing.
2. *Suppress + enhance (bug-fix + enhancement / minor).* On PS 7, report the **equivalent**
   information from a source that exists there, so the function is informative on both
   runtimes - matching the dual-runtime promise.

Framing 1, if codified as the canon's accepted behaviour, would **bake a degraded PS-7 path
into the reference implementation** that every future consumer vendors. Because the canon's
explicit contract is "PS 5.1 + PS 7.x", shipping a reference function that silently drops
information on PS 7 would set a half-implemented pattern as the canonical answer - a hazard
for future dual-runtime script development, not just for these two functions.

A second, narrower question: **which PS-7 value is the right substitute for `CLRVersion`?**
On PS 5.1, `CLRVersion` is a `[Version]` (e.g. `4.0.30319`) meaning "the executing .NET
runtime version". Candidates on PS 7:

- `[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription` -> a *string*
  like `.NET 8.0.10` (label + version; human-friendly, but not a version value).
- `[System.Environment]::Version` -> a `[Version]` like `8.0.10` (a version **value**, same
  type and meaning as `CLRVersion`).

Since `CLRVersion`'s meaning is "the runtime version as a value", the meaning-preserving
substitute is `[System.Environment]::Version`. `FrameworkDescription` is the better
*human-readable label* (it names the runtime family). Both APIs exist on .NET Framework and
.NET Core, so either is safe to call on both runtimes.

## Decision

**1. Dual-runtime equivalence (the policy).** A canon function that advertises dual-runtime
support MUST produce equivalent-quality information on both Windows PowerShell 5.1 and
PowerShell 7.x. It MUST NOT silently degrade (omit data, or crash) on one runtime. Where a
runtime lacks a specific datum, the function reports the **meaning-equivalent** datum
available on that runtime. This policy generalises beyond the two functions here: it is the
standard for any future environment-dependent canon function.

**2. Runtime-version reporting (the substitution).** For "executing .NET runtime version",
use a value that carries that meaning on each runtime:

- Primary value (version semantics): `[System.Environment]::Version` - works on both;
  equals `CLRVersion` on PS 5.1 and the .NET Core version on PS 7.
- Human label (runtime family): `[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription`
  - e.g. `.NET Framework 4.8...` on 5.1, `.NET 8.0.10` on PS 7.

Functions report the version value and MAY annotate it with the framework description. The
access is guarded with the Hashtable membership test (`$PSVersionTable.ContainsKey('CLRVersion')`
- `$PSVersionTable` is a `PSVersionHashTable`, so `.ContainsKey()` is the StrictMode-safe
test; `.PSObject.Properties[...]` does not work on it) or by using `[System.Environment]::Version`
directly (preferred - it does not depend on a runtime-specific key), so it is StrictMode-safe
on both runtimes.

**3. Applies to both call sites.** `Show-PowerShellEnvironment` (host print) and
`Export-DebugTraceJson` (the `clrVersion` JSON field) both adopt the policy. The JSON field
keeps its name for backward compatibility of the export schema but is populated from the
runtime-safe source.

**4. Change classification (ADR 0011 §4).** kind = **bug-fix + enhancement**; impact range
= **minor** (backward-compatible: PS 5.1 output is unchanged in meaning; PS 7 gains correct
output where it previously crashed; the export field name is unchanged). Decision weight is
therefore **medium**, recorded as this ADR. This exceeds a "patch" precisely because
choosing framing 2 over framing 1 sets a forward policy, not because the code is large.

## Process note (ADR 0011 transitional)

This is the first execution of the ADR 0011 process, run under its transitional clause:

- **Trigger:** AI-development finding (the P2a.2 canon tests surfaced the throw).
- **Decision gate (§4):** this ADR records the should-we decision and its kind/impact. Per
  the transitional clause, the decision gate is the existing `[AUTH]` discipline; the user
  granted `[AUTH]` for "Claude fixes the code" in-conversation, with the formal approval
  flow (and the not-yet-built gate machinery, P3a/P7a) waived for this medium change.
- **Quality gate:** the canon behavioral tests (the two skips are re-enabled and must pass
  on PS 7), plus the standing lint/validator gates.
- **Audit trail (§5):** this ADR + the fix commit + the per-unit `canonical_version` record
  in the manifest (the canon has no separate CHANGELOG file; the manifest's version field
  and Git history are its change log). The two affected units' `canonical_version` is bumped
  when the fix lands; this is coordinated with the P2a.3 `0.1.0 -> 1.0.0` promotion rather
  than done as an isolated bump.

A pure ADR was deliberately chosen over a CHANGELOG-only record because the change embeds a
**forward policy** (dual-runtime equivalence) that future functions must follow - which is
ADR-shaped, not a routine bug-fix log entry. Routine suppress-only fixes would have been
CHANGELOG/commit-only per ADR 0011 §5; this one is not routine.

## Consequences

- The two functions become StrictMode-safe and informative on PS 7; the two recorded test
  skips (P2a.2) are re-enabled and become passing assertions.
- A reusable policy exists for every future environment-dependent canon function: dual-
  runtime equivalence, meaning-preserving substitution, StrictMode-safe access.
- The `clrVersion` export field keeps its name (schema-stable) but is runtime-safe.
- Demonstrates the ADR 0011 process end-to-end by hand before the P3a/P7a machinery exists.

## Alternatives considered

- **Suppress-only (framing 1).** Rejected: codifies a degraded PS-7 path as canonical,
  contradicting the dual-runtime contract and setting a half-implemented pattern for future
  consumers.
- **Use `FrameworkDescription` as the value.** Rejected as the *value*: it is a label
  string, not a version. Adopted instead as an optional human-readable annotation alongside
  the `[System.Environment]::Version` value.
- **CHANGELOG/commit-only, no ADR.** Rejected: the change sets a forward policy, which is an
  architectural decision (ADR), not a routine fix (CHANGELOG). Routine suppress-only fixes
  would not warrant an ADR.
