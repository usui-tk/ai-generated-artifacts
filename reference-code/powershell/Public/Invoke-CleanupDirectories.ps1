# >>> CANONICAL unit_id=pwsh.helper.invoke-cleanupdirectories version=1.0.0 hash=54e92fb426d23d2b policy=canonical binding=follow-latest >>>
function Invoke-CleanupDirectories { # psa-disable-line PSA6003 -- "Directories" is plural by design; takes multiple directory args
    # Wipe $OutputDir and $WorkDir trees. Idempotent (missing dirs are
    # silently skipped). Throws if either path looks dangerous.
    param(
        [Parameter(Mandatory)] [string]$OutputDir,
        [Parameter(Mandatory)] [string]$WorkDir
    )
    foreach ($pair in @(
            @{ Name = 'OutputDir'; Path = $OutputDir },
            @{ Name = 'WorkDir';   Path = $WorkDir   })) {

        $name = $pair.Name
        $path = $pair.Path

        if (Test-DangerousPath -Path $path) {
            throw "Refusing to clean $name : path looks unsafe to remove: $path"
        }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Skip ("  {0,-10} not present (skipped): {1}" -f $name, $path)
            continue
        }

        # Report what we're about to remove.
        $sizeMb   = 0.0
        $fileCnt  = 0
        try {
            $items   = Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue
            $bytes   = ($items | Measure-Object -Property Length -Sum).Sum
            if ($bytes) { $sizeMb = $bytes / 1MB }
            $fileCnt = if ($items) { $items.Count } else { 0 }
        } catch { } # psa-disable-line PSA3004 -- best-effort size/count reporting only; do not block cleanup on stat errors

        Write-Skip ("  removing: {0,-10} ({1,7:N1} MB / {2,5} files): {3}" -f `
            $name, $sizeMb, $fileCnt, $path)
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Skip ("  removed:  {0,-10} {1}" -f $name, $path)
        } catch {
            Write-Fail "Failed to remove $path : $($_.Exception.Message)"
            throw
        }
    }
    Write-Ok "cleanup completed"
}
# <<< CANONICAL unit_id=pwsh.helper.invoke-cleanupdirectories <<<
