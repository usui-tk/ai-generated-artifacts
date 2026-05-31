# >>> CANONICAL unit_id=pwsh.helper.assert-powershellcompatibility version=0.1.0 hash=b2061e25acaa873c policy=canonical binding=follow-latest >>>
function Assert-PowerShellCompatibility {
    <#
    .SYNOPSIS
        Hard-fail the script early when running on an unsupported host.

    .DESCRIPTION
        Refuses to proceed when:
          - PowerShell version is below 5.1, or
          - The current process is 32-bit.

        Both conditions are categorical incompatibilities (not soft
        warnings): the script's runspace-based concurrency, .NET regex
        Unicode escapes, and large-file handling have all been validated
        only on 5.1+ / 64-bit hosts. Running on a 32-bit host or a
        pre-5.1 engine will produce silent miscompilations or hangs
        rather than honest errors, so we stop here with a clear message.

        Throws a terminating error so the script exits with non-zero
        status; downstream phases never run.
    #>
    param()

    $pv    = $PSVersionTable.PSVersion
    $minPs = [Version]'5.1'
    if ($pv -lt $minPs) {
        throw @"
This script requires PowerShell $minPs or later.
Detected: $pv

This script targets the default PowerShell included with Windows 10 /
11 and Windows Server 2016 / 2019 / 2022 / 2025, which is
PowerShell 5.1. PowerShell 7+ is NOT required, but PowerShell 5.1 is
the minimum.

If you are on Windows 7 / Windows Server 2012 R2 or earlier, install
the Windows Management Framework 5.1 update: https://aka.ms/wmf51
"@
    }
    if (-not [Environment]::Is64BitProcess) {
        throw @'
This script requires a 64-bit PowerShell process. Detected 32-bit.

On a 64-bit Windows, launch from "Windows PowerShell" (NOT "Windows
PowerShell (x86)"). 32-bit hosts may hit issues with concurrent
runspace pools and large file path operations that have only been
validated under 64-bit PowerShell.
'@
    }
}
# <<< CANONICAL unit_id=pwsh.helper.assert-powershellcompatibility <<<
