---
id: 0013
title: multi-platform-multi-version-quality-assurance
status: accepted
date: 2026-06-01
supersedes: []
superseded_by: null
governs: ["reference-code/powershell/PSScriptAnalyzerSettings.psd1", "governance/state/manifest.jsonl", "governance/schema/manifest.schema.json"]
---

<!-- AI read-contract: authoritative for HOW the canon's multi-version (Windows
     PowerShell 5.1 + PowerShell 7.x) and multi-OS (Windows + Linux) support is assured and
     classified. Fixes (1) a compatibility static-analysis gate - a three-cell profile matrix
     in the canon's PSScriptAnalyzer settings; (2) a per-unit platform_scope classification in
     the manifest (cross-platform / windows-enhanced / windows-only) so the canon's
     "multi-platform" claim is precise per unit rather than blanket; (3) the rule that
     windows-enhanced/-only units suppress the compatibility gate's OS-specific findings at
     function scope with a recorded justification; and (4) the explicit limitation that the
     profile DB is not exhaustive, so a 0-finding gate is necessary-but-not-sufficient.
     Builds on ADR 0012 (which fixed the CLRVersion dual-runtime defect and, via this gate,
     surfaced the FrameworkDescription follow-on defect). Another worked example of the ADR
     0011 process under the transitional clause (decision recorded as this ADR; in-
     conversation [AUTH]; manifest field added by hand before the P3a CRUD tool exists).
     Read on-demand. If reversing, supersede via a new ADR. -->

# 0013 - Multi-platform / multi-version quality assurance

## Status

Accepted. Builds on [ADR 0012](./0012-dual-runtime-environment-info-policy.md) (dual-runtime
env-info policy). Follows the [ADR 0011](./0011-canon-change-management-governance.md)
change-management process under its transitional clause.

## Context

The canon advertises support for Windows PowerShell 5.1 and PowerShell 7.x, on Windows and
Linux. Three gaps in how that was assured:

1. **No compatibility static analysis.** The canon's `PSScriptAnalyzerSettings.psd1` had an
   empty `Rules` block; the compatibility rules (`PSUseCompatibleSyntax/Commands/Types`)
   were never configured, so multi-version / multi-OS issues were not caught statically.
   Fixing ADR 0012's CLRVersion defect and then enabling these rules immediately surfaced a
   follow-on defect (`RuntimeInformation::FrameworkDescription` needs .NET Framework 4.7.1+,
   so it would throw on older PS 5.1 hosts) that Pester on a single PS 7 host could never
   have found. This is the concrete proof the gate was missing and is needed.

2. **"Multi-platform" was a blanket claim, not a per-unit fact.** The canon mixes genuinely
   cross-platform units (e.g. `Get-SevenZipPath`, which probes both Windows `7z.exe` and
   Linux `7z`/`7za`) with units that have a Windows-specific section (e.g.
   `Show-PowerShellEnvironment`'s CIM/WMI OS-info path, which degrades to "(CIM/WMI
   unavailable)" off Windows). Calling the whole canon "multi-platform" without saying which
   units are which is imprecise and risks baking half-implemented Windows-only behaviour
   into the reference implementation that consumers vendor. A per-unit classification is
   needed so the claim is accountable before distribution.

3. **No defined treatment for intentional OS-specific code.** When the compatibility gate
   flags a deliberately Windows-specific path (CIM/WMI), there was no rule for whether/why to
   suppress it. Silent suppression hides the unit's nature; the gate finding must be tied to
   an explicit classification.

## Decision

**1. Compatibility static-analysis gate (three-cell matrix).** The canon's PSScriptAnalyzer
settings enable `PSUseCompatibleSyntax` (TargetVersions 5.1 + 7.0) and
`PSUseCompatibleCommands` / `PSUseCompatibleTypes` over a three-cell profile matrix - the
meaningful cells, since 5.1 is Windows-only (no "5.1 x Linux"):

- `win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework` - Windows PowerShell
  5.1 on Windows Server 2016;
- `win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core` - PowerShell 7.0 on Windows Server 2019;
- `ubuntu_x64_18.04_7.0.0_x64_3.1.2_core` - PowerShell 7.0 on Ubuntu 18.04 (Linux).

These are the REAL bundled profile filenames (the short aliases such as
`desktop-5.1.14393.206-windows` do not resolve from a settings `.psd1`). Including a 7.x
**Windows** cell is deliberate: it catches Windows-vs-Linux command/type differences (CIM,
WMI) that a Linux-only 7.x cell would conflate, and it covers the realistic case where 5.1
is retired and 7.x Windows becomes the Windows runtime. The gate runs over the unit home
(`Public/`, `Private/`) only; `tests/` is not a managed unit (ADR 0011 sec.1) and is excluded.

**2. Per-unit `platform_scope` classification (manifest).** Every manifest record carries a
required `platform_scope` (schema enum):

- **`cross-platform`** - full function on all supported OSes (the default; 57/58 units).
- **`windows-enhanced`** - runs on all OSes but provides extra information on Windows and
  degrades gracefully elsewhere (currently `Show-PowerShellEnvironment`: 4 of its 5 sections
  are cross-platform; only the CIM/WMI OS-detail section is Windows-specific and falls back
  to "(CIM/WMI unavailable)").
- **`windows-only`** - does not function (or is meaningless) off Windows (currently none;
  defined so a future genuinely-Windows-only unit is classified honestly rather than
  mislabelled).

This makes the multi-platform claim precise per unit. A `windows-enhanced` unit is NOT
mislabelled `windows-only` - that would wrongly tell a reader it cannot run on Linux.

**3. Suppression is classification-backed, not silent.** A unit whose `platform_scope` is
`windows-enhanced` / `windows-only` suppresses the compatibility gate's OS-specific findings
**at function scope** via `[Diagnostics.CodeAnalysis.SuppressMessageAttribute]` with a
justification that names the `platform_scope` and the graceful-degradation behaviour. The
suppression's legitimacy derives from the classification (the unit is declared
Windows-enhanced), not from merely wanting the warning gone.

**4. Limitation - necessary but not sufficient.** A profile DB is not exhaustive: it can
miss real incompatibilities (it did NOT flag `FrameworkDescription`'s .NET 4.7.1+
requirement). Therefore a 0-finding compatibility gate is a NECESSARY but NOT SUFFICIENT
condition for multi-platform/version correctness. Real-host or CI matrix verification (the
guide's third layer) is the eventual complement; until it exists, the gate plus
classification plus human review is the assurance, with this limitation recorded so the
0-finding result is not over-trusted.

**Real-host verification performed (the complement, applied once).** The container runs only
PowerShell 7.x on Linux, so the other matrix cells were initially assured by static analysis
+ logic simulation only. To close part of that gap, the FrameworkDescription-removal fix was
verified on real hosts where available:

- **PS 7.4.6 / Linux** (container): `Show-PowerShellEnvironment` prints
  `CLR / .NET : 8.0.10` without throwing - confirmed live.
- **Windows PowerShell 5.1** (user's real host): `[System.Environment]::Version` returns
  `4.0.30319.42000` without throwing - confirmed live. This is the SAME value the removed
  `$PSVersionTable.CLRVersion` returned on 5.1, empirically confirming the substitution is
  meaning-preserving (ADR 0012), and that the runtime-safe access does not throw on 5.1.
- **PS 7.x / Windows**: not executed on a real host (lowest-risk cell - the same
  `[System.Environment]::Version` runs on PS 7 Linux; no reason it would differ on PS 7
  Windows). Remains static-analysis-assured pending the future CI matrix.

So the multi-version endpoints (5.1 and 7.x) are now BOTH real-host-confirmed for the
runtime-version access; only the 7.x-Windows cell remains static-only. This is the model
ADR 0013 anticipated: static gate as the always-on necessary check, real-host/CI as the
sufficient complement, applied here as user-supplied real-host evidence.

## Change classification (ADR 0011 sec.4)

kind = **enhancement** (a new quality gate + a new manifest field + one bug-fix follow-on:
the FrameworkDescription removal); impact = **minor** (backward-compatible: existing unit
behaviour preserved; the new field defaults to cross-platform; the new gate must pass at
0/0/0). Decision weight **medium**, recorded as this ADR. The FrameworkDescription removal
itself is a `bug-fix` carried under ADR 0012's policy (dual-runtime equivalence) and this
ADR's gate which surfaced it.

## Process note (ADR 0011 transitional)

- **Trigger:** AI-development finding + user direction (the compatibility-coverage concern).
- **Decision gate:** this ADR; in-conversation `[AUTH]` (Claude makes the code/manifest
  changes; formal approval flow waived for this medium change, as for ADR 0012).
- **Quality gate:** the new compatibility gate at 0/0/0 over Public/Private; the standing
  psa.py / PSScriptAnalyzer / validator / Pester / T11 gates; the canon behavioral tests.
- **Manifest CRUD:** `platform_scope` added to all 58 records BY HAND (transitional clause -
  the P3a CRUD tool does not yet exist), coordinated as a single edit. The
  `canonical_version` bump and `tested=true` flip are deliberately NOT done here: they belong
  to the SemVer-promotion step (P2a.3), which is kept to version/tested only so the release
  operation stays atomic. This ADR + the fix complete all code and non-version manifest
  changes BEFORE promotion, so 1.0.0 can be claimed with the multi-platform story already
  accountable.
- **Audit trail:** this ADR + the fix commit + the manifest records.

## Consequences

- Multi-version x multi-OS issues are caught statically going forward; the gate already paid
  for itself by surfacing the FrameworkDescription defect.
- The canon's platform support is precise per unit; consumers can see which units are
  cross-platform vs windows-enhanced before vendoring.
- Intentional Windows-specific paths are suppressed with a classification-backed reason, not
  silently.
- The profile DB's limitation is on record, so the gate is not over-trusted; CI/real-host
  verification remains the future complement.
- `platform_scope` becomes a field the P3a CRUD tool manages; it is introduced here (by hand)
  so the SemVer promotion need only touch version + tested.

## Alternatives considered

- **Keep FrameworkDescription with a guard.** Rejected: it needs .NET 4.7.1+ and the profile
  DB does not even flag it reliably; `Environment.Version` alone is safe on every supported
  runtime and meaning-preserving.
- **Two-value platform_scope (cross-platform / windows-only).** Rejected: it would force
  `Show-PowerShellEnvironment` into `windows-only`, falsely implying it cannot run on Linux.
  The three-value scheme classifies it honestly as `windows-enhanced`.
- **6.1.0 "core" profiles as the 7.x approximation.** Rejected once the real bundled 7.0
  profiles (Server 2019 / Ubuntu 18.04) were found; they are closer to the supported runtime
  than PS 6.1.
- **Silent suppression of the CIM/WMI findings.** Rejected: suppression must be backed by the
  `platform_scope` classification and a recorded justification, not merely silence the gate.
