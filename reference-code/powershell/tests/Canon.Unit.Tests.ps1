# Canon behavioral tests - buckets U0 (pure), U1 (state-fixture), U2 (module-load).
# Part of P2a.2 (ADR 0007 full-set; ADR 0010 taxonomy). The F-state / F-env
# buckets are authored in a separate file. Canon code is UNCHANGED; the driver
# supplies preconditions via Initialize-CanonSessionState (consumer usage model).
#
# Helper note: Private (non-exported) units are exercised inside the module scope
# via `& (Get-Module powershell) { ... }` (InModuleScope-equivalent), since they
# are not part of the exported surface.
BeforeAll {
    $here = $PSScriptRoot
    . (Join-Path $here 'CanonSessionState.ps1')
    $modulePath = Join-Path (Split-Path $here -Parent) 'powershell.psd1'
    Import-Module -Name $modulePath -Force
    Initialize-CanonSessionState -Module 'powershell'
    $script:M = Get-Module powershell
}

# =====================================================================
# U0 - pure units (no $Script: state, deterministic in/out; D-inline)
# =====================================================================

Describe 'U0 Format-Elapsed' {
    It 'renders sub-minute as F2 seconds' {
        Format-Elapsed ([TimeSpan]::FromSeconds(1.5)) | Should -BeExactly '1.50s'
    }
    It 'renders zero as 0.00s' {
        Format-Elapsed ([TimeSpan]::Zero) | Should -BeExactly '0.00s'
    }
    It 'includes a minute segment at/above 60s' {
        Format-Elapsed ([TimeSpan]::FromSeconds(123)) | Should -Match '^2m'
    }
}

Describe 'U0 Write-SubSection' {
    It 'emits the title on the information stream' {
        $out = (Write-SubSection -Title 'MySection' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        $out | Should -Match 'MySection'
    }
}

Describe 'U0 Write-Detail' {
    It 'emits the message text' {
        $out = (Write-Detail -Msg 'detail-line' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        $out | Should -Match 'detail-line'
    }
}

Describe 'U0 Set-Utf8PipelineEncoding' {
    It 'runs without throwing and sets UTF-8 output encoding' {
        { Set-Utf8PipelineEncoding } | Should -Not -Throw
        [Console]::OutputEncoding.WebName | Should -Be 'utf-8'
    }
}

Describe 'U0 Wait-WithJitter' {
    # Wait-WithJitter calls Start-Sleep; mock it so the test is deterministic
    # and does not actually sleep. (Inventory note: this unit has a time/env
    # touch via Start-Sleep; the driver mocks it - it stays a unit test.)
    It 'computes a positive sleep and calls Start-Sleep once' {
        & $script:M {
            Mock -CommandName Start-Sleep -MockWith { }
            Wait-WithJitter -BaseSeconds 1 -JitterRange 0.5
            Should -Invoke Start-Sleep -Times 1 -Exactly
        }
    }
    It 'floors the sleep at 0.1s (never negative)' {
        $capMs = & $script:M {
            Mock -CommandName Start-Sleep -MockWith { $script:seenMs = $Milliseconds }
            $script:seenMs = -1
            Wait-WithJitter -BaseSeconds 0 -JitterRange 0.01
            $script:seenMs
        }
        $capMs | Should -BeGreaterOrEqual 100
    }
}

Describe 'U0 _DebugTrace_Now (Private)' {
    It 'returns an ISO-8601 millisecond Z timestamp' {
        $ts = & $script:M { _DebugTrace_Now }
        $ts | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
    }
}

Describe 'U0 _CanonicalJson parse primitives (Private)' {
    It '_CanonicalJson_SkipWs advances past leading whitespace' {
        $i = & $script:M {
            $st = @{ s = "   x"; i = 0; n = 4 }
            _CanonicalJson_SkipWs $st
            $st.i
        }
        $i | Should -Be 3
    }
    It '_CanonicalJson_ParseBool reads true and advances 4' {
        $r = & $script:M {
            $st = @{ s = 'true'; i = 0; n = 4 }
            $v = _CanonicalJson_ParseBool $st
            [pscustomobject]@{ v = $v; i = $st.i }
        }
        $r.v | Should -BeTrue
        $r.i | Should -Be 4
    }
    It '_CanonicalJson_ParseBool reads false and advances 5' {
        $r = & $script:M {
            $st = @{ s = 'false'; i = 0; n = 5 }
            $v = _CanonicalJson_ParseBool $st
            [pscustomobject]@{ v = $v; i = $st.i }
        }
        $r.v | Should -BeFalse
        $r.i | Should -Be 5
    }
    It '_CanonicalJson_ParseNull reads null' {
        $r = & $script:M {
            $st = @{ s = 'null'; i = 0; n = 4 }
            $v = _CanonicalJson_ParseNull $st
            [pscustomobject]@{ isNull = ($null -eq $v); i = $st.i }
        }
        $r.isNull | Should -BeTrue
        $r.i | Should -Be 4
    }
    It '_CanonicalJson_ParseNumber reads an integer as [long]' {
        $r = & $script:M {
            $st = @{ s = '42'; i = 0; n = 2 }
            _CanonicalJson_ParseNumber $st
        }
        $r | Should -Be 42
        $r | Should -BeOfType [long]
    }
    It '_CanonicalJson_ParseString reads a quoted string with an escape' {
        $r = & $script:M {
            $st = @{ s = '"a\"b"'; i = 0; n = 6 }
            _CanonicalJson_ParseString $st
        }
        $r | Should -BeExactly 'a"b'
    }
}

Describe 'U0 _CanonicalJson write primitives (Private)' {
    It '_CanonicalJson_WriteNumber appends an integer' {
        $s = & $script:M {
            $sb = [System.Text.StringBuilder]::new()
            _CanonicalJson_WriteNumber 7 $sb
            $sb.ToString()
        }
        $s | Should -BeExactly '7'
    }
    It '_CanonicalJson_WriteString quotes and escapes' {
        $s = & $script:M {
            $sb = [System.Text.StringBuilder]::new()
            _CanonicalJson_WriteString 'a"b' $sb
            $sb.ToString()
        }
        $s | Should -BeExactly '"a\"b"'
    }
}

# =====================================================================
# U1 - unit + state fixture (reads $Script: session state)
# =====================================================================

Describe 'U1 Test-DangerousPath' {
    It 'flags a root path' { Test-DangerousPath -Path '/' | Should -BeTrue }
    It 'permits a deep path' { Test-DangerousPath -Path '/a/b/c/d/e/f' | Should -BeFalse }
}

Describe 'U1 Resolve-RelativeToScript' {
    It 'joins a relative path under the script root' {
        $p = Resolve-RelativeToScript -Path 'sub/file.txt'
        $p | Should -Match 'sub'
    }
}

Describe 'U1 Get-PhaseElapsedTag' {
    It 'returns a string tag from the current phase start' {
        & $script:M { $Script:CurrentPhaseStart = (Get-Date).AddSeconds(-5) }
        (Get-PhaseElapsedTag) | Should -BeOfType [string]
    }
}

Describe 'U1 _DebugTrace_NextSeq (Private)' {
    It 'increments and returns the event sequence' {
        $r = & $script:M {
            $Script:DebugTraceEventSeq = 0
            $a = _DebugTrace_NextSeq
            $b = _DebugTrace_NextSeq
            [pscustomobject]@{ a = $a; b = $b }
        }
        $r.a | Should -Be 1
        $r.b | Should -Be 2
    }
}

Describe 'U1 Set-DebugStep' {
    It 'records a step on the active frame without throwing' {
        { Start-DebugTrace -Context 'u1.setstep'; Set-DebugStep -Step 'step-A' } | Should -Not -Throw
    }
}

Describe 'U1 Format-DebugFailure' {
    It 'produces a failure string referencing the stack' {
        $s = & $script:M {
            Start-DebugTrace -Context 'u1.fmtfail'
            Format-DebugFailure -ErrorRecord ([System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('boom'), 'id', 'NotSpecified', $null))
        }
        $s | Should -Match 'boom'
    }
}

Describe 'U1 Get-DebugTraceFileOutputStatus' {
    It 'returns a status object reflecting fixture state' {
        $st = Get-DebugTraceFileOutputStatus
        $st | Should -Not -BeNullOrEmpty
    }
}

Describe 'U1 Show-PhaseSummary' {
    It 'runs without throwing on seeded timing state' {
        { Show-PhaseSummary } | Should -Not -Throw
    }
}

# NOTE: Show-PowerShellEnvironment was inventory-classified U1 but calls
# Get-CimInstance (Win32_OperatingSystem) - an OS/environment dependency that
# hangs/throws off-Windows. Reclassified to F-env (env-dependency); its test lives in the
# F-env file with the CIM call mocked. (Inventory correction.)

Describe 'U1 Write-PhaseHeader / Write-PhaseFooter' {
    It 'header sets the current phase and footer records timing' {
        { Write-PhaseHeader -Id 'P50' -Name 'Test phase' -Group 'TestGroup' } | Should -Not -Throw
        $cur = & $script:M { $Script:CurrentPhaseId }
        $cur | Should -Be 'P50'
        { Write-PhaseFooter -Id 'P50' -Status 'done' } | Should -Not -Throw
    }
}

Describe 'U1 _DebugTrace_RetireFrame (Private)' {
    It 'moves a completed frame into the completed list under the cap' {
        $n = & $script:M {
            $Script:DebugTraceCompletedFrames = New-Object 'System.Collections.Generic.List[object]'
            $Script:DebugTraceCompletedCap = 1024
            $frame = [pscustomobject]@{ context = 'x'; StartTime = (Get-Date).AddSeconds(-1) }
            _DebugTrace_RetireFrame -Frame $frame -Outcome 'ok'
            $Script:DebugTraceCompletedFrames.Count
        }
        $n | Should -Be 1
    }
}

# =====================================================================
# U2 - unit + function dependency (resolved by module load; no fixture
# beyond what Import-Module provides). Canonical-JSON value matrix is
# D-inline, byte-checked against the Python oracle in canonical_json_test.py.
# =====================================================================

Describe 'U2 host writers' {
    It 'Write-Ok emits marker + message' {
        ((Write-Ok -Msg 'ok-msg' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'ok-msg'
    }
    It 'Write-Step emits message' {
        ((Write-Step -Msg 'step-msg' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'step-msg'
    }
    It 'Write-Fail emits message' {
        ((Write-Fail -Msg 'fail-msg' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'fail-msg'
    }
    It 'Write-Skip emits message' {
        ((Write-Skip -Msg 'skip-msg' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'skip-msg'
    }
    It 'Write-Caution emits message' {
        ((Write-Caution -Msg 'caution-msg' 6>&1 | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'caution-msg'
    }
}

Describe 'U2 _LogLine (Private)' {
    It 'formats a marker + message line' {
        $out = & $script:M { _LogLine -Marker '[+]' -Msg 'logged' -Color 'Green' 6>&1 }
        (($out | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'logged'
    }
}

Describe 'U2 Assert-PowerShellCompatibility' {
    It 'returns without throwing on the supported runtime (pwsh 7.x, 64-bit)' {
        { Assert-PowerShellCompatibility } | Should -Not -Throw
    }
}

Describe 'U2 ConvertTo-CanonicalJson / ConvertFrom-CanonicalJson' {
    It 'round-trips a simple object preserving key order' {
        $json = ConvertTo-CanonicalJson -InputObject ([ordered]@{ b = 1; a = 'x' })
        $json | Should -BeOfType [string]
        $obj = ConvertFrom-CanonicalJson -Json $json
        $obj.b | Should -Be 1
        $obj.a | Should -BeExactly 'x'
    }
    It 'ConvertFrom-CanonicalJson keeps a date-like value as a string' {
        $obj = ConvertFrom-CanonicalJson -Json '{"d":"2026-01-01T00:00:00Z"}'
        $obj.d | Should -BeOfType [string]
    }
}

Describe 'U2 _CanonicalJson recursive writers/parsers (Private)' {
    It '_CanonicalJson_WriteValue serializes a nested structure' {
        $s = & $script:M {
            $sb = [System.Text.StringBuilder]::new()
            _CanonicalJson_WriteValue -Value @(1,2) -Depth 0 -MaxDepth 100 -IndentUnit '' -Sb $sb
            $sb.ToString()
        }
        $s | Should -Match '^\['
    }
    It '_CanonicalJson_ParseValue parses an array' {
        $r = & $script:M {
            $st = @{ s = '[1,2]'; i = 0; n = 5 }
            _CanonicalJson_ParseValue $st
        }
        $r.Count | Should -Be 2
    }
}

Describe 'U2 trace-output toggles' {
    It 'Disable-DebugTraceFileOutput clears the enabled flag' {
        & $script:M { $Script:DebugTraceJsonlEnabled = $true }
        Disable-DebugTraceFileOutput
        (& $script:M { $Script:DebugTraceJsonlEnabled }) | Should -BeFalse
    }
    It 'Enable-AutoExportOnPhaseFailure sets the auto-export flag' {
        Enable-AutoExportOnPhaseFailure -OutputDirectory $TestDrive
        (& $script:M { $Script:DebugTraceAutoExportEnabled }) | Should -BeTrue
    }
}
