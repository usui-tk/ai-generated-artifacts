# >>> CANONICAL unit_id=pwsh.helper.wait-withjitter version=r01 hash=15aba6cbcbfa9966 policy=canonical binding=follow-latest >>>
function Wait-WithJitter {
    param(
        [double]$BaseSeconds,
        [double]$JitterRange
    )
    $jitter = Get-Random -Minimum (-$JitterRange) -Maximum $JitterRange
    $actualSleep = [Math]::Max(0.1, $BaseSeconds + $jitter)
    Start-Sleep -Milliseconds ([int]($actualSleep * 1000))
}
# <<< CANONICAL unit_id=pwsh.helper.wait-withjitter <<<
