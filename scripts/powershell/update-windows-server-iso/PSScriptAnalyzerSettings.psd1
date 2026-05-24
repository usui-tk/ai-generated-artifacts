# ============================================================================
# PSScriptAnalyzer settings for Update-WindowsServerIso.ps1
#
# CI governance: see repository-level /SPEC.md (top of repo).
# Project SPEC: see ./SPEC.md (Part A.11 - Static Analysis with psa.py)
#               for the companion psa.py configuration philosophy.
#
# Reference:
#   https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/
#
# Rule selection philosophy:
#   - Include all default rules at all severities (Error / Warning / Information)
#   - Exclude only rules whose findings are by-design for this CLI tool,
#     with explicit rationale for each exclusion
#   - Project-wide exclusions are documented here; per-occurrence exemptions
#     are inline via `# psa-disable-line` comments (mirrored from psa.py)
#
# Coverage expectation:
#   Running on Update-WindowsServerIso.ps1 with these settings MUST
#   produce 0 errors / 0 warnings / 0 information findings on both
#   Windows PowerShell 5.1 (Stage 2) and PowerShell 7.x (Stage 1).
# ============================================================================
@{
    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # Intentional operator-facing Write-Host calls drive the colored
        # phase headers / footers and the [P0x:NN:SS] log lines described
        # in README "Phase reference" section. PSScriptAnalyzer's preference
        # for Write-Output is unsuitable for an interactive CLI whose primary
        # purpose is human-readable progress display through Write-Step /
        # Write-Ok / Write-Warn / Write-Fail / Write-Skip wrappers.
        'PSAvoidUsingWriteHost',

        # The plural-noun functions in this script describe operations
        # over collections. They carry inline `# psa-disable-line PSA6003`
        # justifications and are documented in SPEC.md Part D.
        # Currently plural-noun functions:
        #   - Initialize-RuntimeDirectories
        #   - Invoke-CleanupDirectories
        #   - Invoke-SetupPhase02_ResolveInputs ("Inputs": collection of
        #     ISO + patches resolved by the phase)
        #   - Invoke-FetchPhase03_FetchAssets ("Assets": ISO + patches set)
        #   - Resolve-InstallWimTargetIndexes
        # Renaming to singular would either misrepresent the behaviour
        # or require breaking changes to the phase registry dispatcher.
        'PSUseSingularNouns',

        # The script provides a single top-level comment-based help block
        # documenting the public CLI parameters. Each internal helper
        # function carries a short `<#... .SYNOPSIS ...#>` block where it
        # adds value; mandating CBH on every internal helper would add
        # noise without operator benefit. This policy is documented in
        # SPEC.md (Part A).
        'PSProvideCommentHelp',

        # Internal Set-* / Start-* / Stop-* helpers (Set-ConsoleUtf8,
        # Set-Tls12, Start-DebugTrace, Set-DebugStep, Stop-DebugTrace)
        # adjust per-script-invocation state, not persistent system state.
        # Wrapping them in SupportsShouldProcess would add UX noise
        # (-WhatIf / -Confirm prompts) to internal helpers that the
        # user never calls directly. DISM writes (the actual destructive
        # operations) are gated behind the explicit -Execute switch
        # in P05 / P06 / P07 instead.
        'PSUseShouldProcessForStateChangingFunctions',

        # The empty catch blocks in this script are intentional
        # best-effort diagnostic captures, OSDBuilder-pattern retry
        # silencing, and cross-host compatibility shims. Each site
        # carries `# psa-disable-line PSA3004 -- <reason>` (the psa.py
        # equivalent rule); the psa.py inline suppressions are the
        # authoritative documentation, so we suppress the PSScriptAnalyzer
        # rule globally instead of duplicating suppressions.
        'PSAvoidUsingEmptyCatchBlock',

        # The positional-parameter call sites in this script target
        # the internal _LogLine / Set-DebugStep helpers, which are
        # structured for idiomatic, terse log-line composition. Forcing
        # named-parameter invocation everywhere would harm readability
        # of the logging sites with no observable benefit. The rule
        # fires at Information severity only.
        'PSAvoidUsingPositionalParameters'
    )

    # Per-rule fine-tuning is currently empty; revisit when adding a new
    # rule that needs configuration (e.g., PSUseConsistentIndentation).
    Rules = @{
    }
}
