# Pester scaffold for the reference-code/powershell canon (P2a.1).
#
# Demonstrates the ADR 0010 hybrid test model with the canon UNCHANGED:
#   - Import the canon module.
#   - Initialize-CanonSessionState reproduces the consumer's $Script: init
#     OUTSIDE the helper bodies (CanonSessionState.ps1), so helpers that read
#     caller-owned session state run under their real usage-model preconditions.
#   - Exercise representative units across buckets, including one (Start-DebugTrace,
#     F-state) that depends on the reproduced session state.
# The full per-unit suite for all 58 canonical units is authored in P2a.2.
BeforeAll {
    $here = $PSScriptRoot
    . (Join-Path $here 'CanonSessionState.ps1')
    $modulePath = Join-Path (Split-Path $here -Parent) 'powershell.psd1'
    Import-Module -Name $modulePath -Force
    Initialize-CanonSessionState -Module 'powershell'
}

Describe 'Canon module' {
    It 'exports the full canon function surface' {
        (Get-Command -Module powershell -CommandType Function | Measure-Object).Count | Should -Be 39
    }
}

Describe 'U0 pure-data unit: Format-Elapsed' {
    It 'renders sub-minute durations as F2 seconds' {
        Format-Elapsed ([TimeSpan]::FromSeconds(1.5)) | Should -BeExactly '1.50s'
    }
    It 'renders minute-scale durations with an m segment' {
        Format-Elapsed ([TimeSpan]::FromSeconds(123)) | Should -Match '^2m'
    }
    It 'renders a zero span as 0.00s' {
        Format-Elapsed ([TimeSpan]::Zero) | Should -BeExactly '0.00s'
    }
}

Describe 'U1 state-fixture unit: Test-DangerousPath' {
    It 'flags a root-length path as dangerous' {
        Test-DangerousPath -Path '/' | Should -BeTrue
    }
    It 'permits a normal deep path' {
        Test-DangerousPath -Path '/home/user/work/project/sub/deep' | Should -BeFalse
    }
}

Describe 'U2 module-load unit: Write-Ok' {
    It 'emits the marker and message on the information stream' {
        $records = Write-Ok -Msg 'hello-canon' 6>&1
        $text = ($records | ForEach-Object { $_.ToString() }) -join "`n"
        $text | Should -Match '\[\+\]'
        $text | Should -Match 'hello-canon'
    }
}

Describe 'F-state lifecycle unit: Start-DebugTrace (fixture reproduces consumer init)' {
    It 'pushes a frame onto the caller-owned DebugTraceStack' {
        Start-DebugTrace -Context 'unit.test'
        $depth = & (Get-Module powershell) { $Script:DebugTraceStack.Count }
        $depth | Should -BeGreaterThan 0
    }
    It 'registers a phase frame when -PhaseId is supplied' {
        Start-DebugTrace -Context 'phase.test' -PhaseId 'P99'
        $hasPhase = & (Get-Module powershell) { $Script:DebugTracePhaseRegistry.ContainsKey('P99') }
        $hasPhase | Should -BeTrue
    }
}
