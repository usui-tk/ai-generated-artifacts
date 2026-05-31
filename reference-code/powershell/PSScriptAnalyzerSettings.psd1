# ============================================================================
# PSScriptAnalyzer settings for the reference-code/powershell canon module.
#
# This canon is the reference implementation of the shared helper functions
# used by the consumer scripts (download-speakerdeck, update-windows-server-iso,
# Deploy-* drivers). The by-design exclusions below mirror those consumers'
# settings, because the canon holds the same code and the same intentional
# patterns. Companion psa.py configuration: ./.psa.config.json.
#
# Coverage expectation:
#   Invoke-ScriptAnalyzer on reference-code/powershell with these settings
#   MUST produce 0 errors / 0 warnings / 0 information findings, on both
#   PowerShell 7.x and Windows PowerShell 5.1.
# ============================================================================
@{
    Severity            = @('Error', 'Warning', 'Information')
    IncludeDefaultRules = $true

    ExcludeRules = @(
        # Operator-facing colored progress output is the purpose of the
        # logging helpers (Write-Detail/Ok/Fail/Skip/Step/Caution and the
        # internal _LogLine). Write-Output is unsuitable for an interactive
        # CLI's human-readable progress display.
        'PSAvoidUsingWriteHost',

        # Plural-noun functions describe operations over collections:
        #   - Initialize-RuntimeDirectories
        #   - Invoke-CleanupDirectories
        # Renaming to singular would misrepresent the behaviour. Mirrors the
        # disabled PSA6003 in ./.psa.config.json.
        'PSUseSingularNouns',

        # Comment-based help policy: the public surface is documented at the
        # module / SPEC level, not per internal helper. Matches the consumers.
        'PSProvideCommentHelp',

        # Internal Set-* / Start-* / Stop-* helpers adjust per-invocation
        # state (TLS, console encoding, debug-trace), not persistent system
        # state; SupportsShouldProcess would add -WhatIf/-Confirm UX noise to
        # helpers the user never calls directly.
        'PSUseShouldProcessForStateChangingFunctions',

        # Intentional best-effort diagnostic captures and cross-host shims use
        # empty catch blocks. psa.py's PSA3004 requires per-occurrence inline
        # justification, which is the authoritative documentation; this
        # exclusion avoids duplicated attribute suppressions on every site.
        'PSAvoidUsingEmptyCatchBlock',

        # Positional-parameter calls target the internal helper _LogLine,
        # structured for terse, idiomatic log-line composition. Forcing named
        # parameters would harm readability with no observable benefit.
        # (Information severity only.)
        'PSAvoidUsingPositionalParameters'
    )

    Rules = @{
    }
}
