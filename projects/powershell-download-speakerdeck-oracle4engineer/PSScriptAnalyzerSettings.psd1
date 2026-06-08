# ============================================================================
# PSScriptAnalyzer settings for Download-SpeakerDeck.ps1
#
# CI governance: see repository-level /SPEC.md (top of repo).
# Project SPEC: see ./SPEC.md §A.11 (Static Analysis with psa.py)
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
#     are inline via [Diagnostics.CodeAnalysis.SuppressMessageAttribute(...)]
#     with a Justification string
#
# Coverage expectation:
#   Running on Download-SpeakerDeck.ps1 with these settings MUST produce
#   0 errors / 0 warnings / 0 information findings.
# ============================================================================
@{
    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # 105 intentional operator-facing Write-Host calls drive the
        # colored progress output described in README "Console output
        # format" section. PSScriptAnalyzer's preference for Write-Output
        # is unsuitable for an interactive CLI whose primary purpose is
        # human-readable progress display.
        'PSAvoidUsingWriteHost',

        # The plural-noun functions in this script describe operations
        # over collections, mirroring the disabled PSA6003 in
        # ./.psa.config.json. Current plural-noun functions:
        #   - Initialize-RuntimeDirectories
        #   - Invoke-CleanupDirectories
        #   - Get-PdfMetadata
        #   - Initialize-YearOverrides
        # Renaming to singular would either misrepresent the behaviour
        # or require breaking changes to call sites.
        'PSUseSingularNouns',

        # The script provides a single top-level comment-based help block
        # documenting the public CLI. Each of the ~60 internal helper
        # functions is an implementation detail and does not warrant a
        # per-function CBH block. This policy is documented in SPEC.md.
        'PSProvideCommentHelp',

        # Internal Set-* / Start-* / Stop-* helpers (Set-ConsoleUtf8,
        # Set-Tls12, Start-DebugTrace, Set-DebugStep, Stop-DebugTrace)
        # adjust per-script-invocation state, not persistent system state.
        # Wrapping them in SupportsShouldProcess would add UX noise
        # (-WhatIf / -Confirm prompts) to internal helpers that the
        # user never calls directly.
        'PSUseShouldProcessForStateChangingFunctions',

        # The ~21 empty catch blocks across this script are intentional
        # best-effort diagnostic captures, foreach-pattern retry loops,
        # and cross-host compatibility shims. Each is also flagged by
        # psa.py's PSA3004 rule, which requires per-occurrence inline
        # `# psa-disable-line PSA3004 -- <reason>` suppression with a
        # justification comment. The psa.py inline suppressions are the
        # authoritative documentation; this exclusion avoids requiring
        # duplicated PSScriptAnalyzer-specific attribute suppressions
        # on every site.
        'PSAvoidUsingEmptyCatchBlock',

        # The 7 positional-parameter calls flagged by this rule all
        # target the internal helper `_LogLine`, which is structured for
        # idiomatic, terse log-line composition. Forcing named-parameter
        # invocation everywhere would harm readability of the logging
        # sites with no observable benefit. The rule fires at the
        # Information severity only.
        'PSAvoidUsingPositionalParameters'
    )

    # Per-rule fine-tuning is currently empty; revisit when adding a new
    # rule that needs configuration (e.g., PSUseConsistentIndentation).
    Rules = @{
    }
}
