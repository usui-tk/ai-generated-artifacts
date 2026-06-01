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
        # ------------------------------------------------------------------
        # Multi-version x multi-OS compatibility matrix (ADR 0013).
        # The canon supports Windows PowerShell 5.1 AND PowerShell 7.x, on
        # Windows AND Linux. These rules verify that statically. Three
        # meaningful cells (5.1 is Windows-only, so "5.1 x Linux" does not
        # exist), using the REAL bundled profile filenames (the short aliases
        # like 'desktop-5.1...' do not resolve from a settings .psd1):
        #   - win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework
        #       = Windows PowerShell 5.1 on Windows Server 2016 (.NET 4.x)
        #   - win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core
        #       = PowerShell 7.0 on Windows Server 2019
        #   - ubuntu_x64_18.04_7.0.0_x64_3.1.2_core
        #       = PowerShell 7.0 on Ubuntu 18.04 (Linux)
        # LIMITATION (ADR 0013): a profile DB is not exhaustive - e.g. it does
        # not catch that RuntimeInformation::FrameworkDescription needs .NET
        # Framework 4.7.1+. A 0-finding result here is NECESSARY but NOT
        # SUFFICIENT for compatibility; real-host / CI verification is the
        # eventual complement. Windows-enhanced units (platform_scope, ADR 0013)
        # suppress these rules at function scope with a recorded justification.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework',
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core',
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleTypes = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework',
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core',
                'ubuntu_x64_18.04_7.0.0_x64_3.1.2_core'
            )
        }
    }
}
