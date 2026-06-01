# Canon behavioral tests - buckets F-state (multi-function lifecycle) and
# F-env (external resource: filesystem / network / process / CIM).
# Part of P2a.2 batch 2 (ADR 0007 full-set; ADR 0010 taxonomy). Canon code is
# UNCHANGED; the driver supplies preconditions via Initialize-CanonSessionState
# and supplies external-resource behaviour via Pester Mock / a per-test tmpdir
# (D-generated + D-mock; never committed fixtures).
BeforeAll {
    $here = $PSScriptRoot
    . (Join-Path $here 'CanonSessionState.ps1')
    $modulePath = Join-Path (Split-Path $here -Parent) 'powershell.psd1'
    Import-Module -Name $modulePath -Force
    Initialize-CanonSessionState -Module 'powershell'
    $script:M = Get-Module powershell
}

# =====================================================================
# F-state - multi-function lifecycle over $Script: state (D-generated)
# =====================================================================

Describe 'F-state Start-DebugTrace -> Set-DebugStep -> Stop-DebugTrace lifecycle' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'push, step, and pop balance the stack' {
        $depths = & $script:M {
            Start-DebugTrace -Context 'life.cycle'
            $afterPush = $Script:DebugTraceStack.Count
            Set-DebugStep -Step 'mid'
            Stop-DebugTrace -Outcome 'success'
            $afterPop = $Script:DebugTraceStack.Count
            [pscustomobject]@{ push = $afterPush; pop = $afterPop }
        }
        $depths.push | Should -Be 1
        $depths.pop  | Should -Be 0
    }
    It 'retires a completed frame into the completed list' {
        $n = & $script:M {
            Start-DebugTrace -Context 'life.retire'
            Stop-DebugTrace -Outcome 'success'
            $Script:DebugTraceCompletedFrames.Count
        }
        $n | Should -Be 1
    }
    It 'marks a phase outcome in the registry across the lifecycle' {
        $outcome = & $script:M {
            Start-DebugTrace -Context 'life.phase' -PhaseId 'P77'
            Stop-DebugTrace -Outcome 'failure'
            $Script:DebugTracePhaseRegistry['P77'].Outcome
        }
        $outcome | Should -Be 'failure'
    }
}

Describe 'F-state Write-DebugFailureReport (consumes stack + phase registry)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'produces a report string from an active trace and an error record' {
        $report = & $script:M {
            Start-DebugTrace -Context 'fail.ctx' -PhaseId 'P88'
            Set-DebugStep -Step 'before-boom'
            $er = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('kaboom'), 'id', 'NotSpecified', $null)
            Write-DebugFailureReport -ErrorRecord $er -IncludeStepHistory 6>&1
        }
        (($report | ForEach-Object { $_.ToString() }) -join "`n") | Should -Match 'kaboom'
    }
    It 'does not auto-export when AutoExport is off (no file written)' {
        & $script:M {
            $er = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('x'), 'id', 'NotSpecified', $null)
            # AutoExport switch omitted -> the Export-DebugTraceJson branch is skipped
            { Write-DebugFailureReport -ErrorRecord $er } | Should -Not -Throw
        }
    }
}

# =====================================================================
# F-env - filesystem (tmpdir real writes via $TestDrive)
# =====================================================================

Describe 'F-env Save-CanonicalJsonFile (filesystem)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'writes canonical JSON bytes (UTF-8 no BOM) to the target path' {
        $path = Join-Path $TestDrive 'out.json'
        Save-CanonicalJsonFile -InputObject ([ordered]@{ a = 1; b = 'x' }) -Path $path
        Test-Path $path | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($path)
        # no UTF-8 BOM
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
        ([System.Text.Encoding]::UTF8.GetString($bytes)) | Should -Match '"a"'
    }
}

Describe 'F-env Initialize-RuntimeDirectories (filesystem)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'creates the requested directories' {
        $d1 = Join-Path $TestDrive 'rt1'
        $d2 = Join-Path $TestDrive 'rt2'
        Initialize-RuntimeDirectories -Directory @($d1, $d2)
        Test-Path $d1 | Should -BeTrue
        Test-Path $d2 | Should -BeTrue
    }
}

Describe 'F-env Invoke-CleanupDirectories (filesystem)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'removes stale entries under the work dir without throwing' {
        $work = Join-Path $TestDrive 'work'; New-Item -ItemType Directory -Path $work -Force | Out-Null
        $out  = Join-Path $TestDrive 'outp'; New-Item -ItemType Directory -Path $out  -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $work 'stale.tmp') -Force | Out-Null
        { Invoke-CleanupDirectories -WorkDir $work -OutputDir $out } | Should -Not -Throw
    }
}

Describe 'F-env Add-ErrorJsonlEntry (filesystem, $Script:ErrorsJsonlPath)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'appends a JSONL line to the configured error log' {
        $log = Join-Path $TestDrive 'errors.jsonl'
        & $script:M { param($p) $Script:ErrorsJsonlPath = $p } $log
        Add-ErrorJsonlEntry -Phase 'P10' -Kind 'TestError'
        Test-Path $log | Should -BeTrue
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'TestError'
    }
    It 'is a no-op when no error-log path is configured' {
        & $script:M { $Script:ErrorsJsonlPath = $null }
        { Add-ErrorJsonlEntry -Phase 'P10' -Kind 'X' } | Should -Not -Throw
    }
}

Describe 'F-env Enable-DebugTraceFileOutput + Export-DebugTraceJson (filesystem)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'enables JSONL output to a tmpdir path' {
        Enable-DebugTraceFileOutput -Directory $TestDrive
        (& $script:M { $Script:DebugTraceJsonlEnabled }) | Should -BeTrue
    }
    It 'Export-DebugTraceJson writes a JSON file and returns its path' {
        # Fixed under ADR 0012 (dual-runtime policy): clrVersion now uses
        # [System.Environment]::Version, runtime-safe on PS 7.
        $path = Join-Path $TestDrive 'export.json'
        $ret = & $script:M {
            param($p)
            Start-DebugTrace -Context 'export.ctx'
            Stop-DebugTrace -Outcome 'success'
            Export-DebugTraceJson -Path $p -IncludeEvents:$false
        } $path
        $ret | Should -Be $path
        Test-Path $path | Should -BeTrue
    }
}

Describe 'F-env _DebugTrace_WriteJsonlLine (filesystem, Private)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'appends a line when JSONL output is enabled' {
        $jsonl = Join-Path $TestDrive 'wl.jsonl'
        & $script:M {
            param($p)
            $Script:DebugTraceJsonlEnabled = $true
            $Script:DebugTraceJsonlPath = $p
            _DebugTrace_WriteJsonlLine -EventObject ([pscustomobject]@{ k = 'v' })
        } $jsonl
        Test-Path $jsonl | Should -BeTrue
    }
}

# =====================================================================
# F-env - network (Invoke-WebRequest / Invoke-RestMethod mocked)
# =====================================================================

Describe 'F-env Set-TlsSecurityProtocol (no I/O - .NET property)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'enables Tls12 in the security-protocol bitmask' {
        Set-TlsSecurityProtocol
        ([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) |
            Should -Be ([Net.SecurityProtocolType]::Tls12)
    }
}

Describe 'F-env Invoke-WebRequestWithRetry (network mocked)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'returns the mocked response on first success' {
        $r = & $script:M {
            Mock -CommandName Invoke-WebRequest -MockWith { [pscustomobject]@{ StatusCode = 200; Content = 'ok' } }
            Invoke-WebRequestWithRetry -Uri 'https://example.invalid/x'
        }
        $r.StatusCode | Should -Be 200
    }
    It 'retries then succeeds (Start-Sleep + Invoke-WebRequest mocked)' {
        $invoked = & $script:M {
            $script:n = 0
            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Invoke-WebRequest -MockWith {
                $script:n++
                if ($script:n -lt 2) { throw 'transient' }
                [pscustomobject]@{ StatusCode = 200 }
            }
            $null = Invoke-WebRequestWithRetry -Uri 'https://example.invalid/y' -MaxRetries 3
            $script:n
        }
        $invoked | Should -BeGreaterOrEqual 2
    }
}

Describe 'F-env Get-LatestSevenZipUrl (network mocked)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'returns a descriptor object when the download page is mocked' {
        $r = & $script:M {
            Mock -CommandName Invoke-WebRequest -MockWith {
                [pscustomobject]@{ Links = @([pscustomobject]@{ href = 'a/7z2400-x64.msi' }); Content = '7z2400' }
            } -ParameterFilter { $true }
            Mock -CommandName Invoke-RestMethod -MockWith {
                [pscustomobject]@{ tag_name = '24.00'; assets = @([pscustomobject]@{ name = '7z.msi'; browser_download_url = 'http://x/7z.msi' }) }
            }
            Get-LatestSevenZipUrl
        }
        $r | Should -Not -BeNullOrEmpty
    }
}

# =====================================================================
# F-env - process (Get-Command / Start-Process / web mocked)
# =====================================================================

Describe 'F-env Get-SevenZipPath (process discovery)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'returns a string path or $null (deterministic on this host)' {
        $p = Get-SevenZipPath
        ($null -eq $p -or $p -is [string]) | Should -BeTrue
    }
    It 'returns the mocked 7z path when Get-Command finds it' {
        $p = & $script:M {
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Source = '/usr/bin/7z' } } -ParameterFilter { $Name -in @('7z','7za','7z.exe') }
            Mock -CommandName Test-Path -MockWith { $false }
            Get-SevenZipPath
        }
        $p | Should -Match '7z'
    }
}

Describe 'F-env Install-SevenZipFallback (process + network mocked)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'attempts download + install without touching the real system' {
        $dir = $TestDrive
        & $script:M {
            param($d)
            $downloadDir = $d
            Mock -CommandName Invoke-WebRequest -MockWith { }
            Mock -CommandName Start-Process -MockWith { [pscustomobject]@{ ExitCode = 0 } }
            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Get-LatestSevenZipUrl -MockWith { [pscustomobject]@{ MsiUrl = 'http://x/7z.msi'; Version = '24.00'; Source = 'test-mock' } }
            { Install-SevenZipFallback -DownloadDir $downloadDir } | Should -Not -Throw
        } $dir
    }
}

Describe 'F-env Invoke-DownloadWithProgress (network mocked, tmpdir, Private)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'writes the out-file via the mocked web request' -Skip {
        # SKIP (test-strategy limitation, recorded): Invoke-DownloadWithProgress
        # runs the actual transfer in a Start-Job worker (separate PowerShell
        # process), which Pester Mock / module scope cannot reach. Deterministic
        # unit verification would need a job-aware harness or real network;
        # deferred. Not a canon defect - the job design is intentional (PS 5.1
        # progress-bar O(N^2) avoidance).
        $true | Should -BeTrue
    }
}

# =====================================================================
# F-env - CIM (Show-PowerShellEnvironment; reclassified from U1)
# =====================================================================

Describe 'F-env Show-PowerShellEnvironment (CIM mocked)' {
    BeforeEach { Initialize-CanonSessionState -Module 'powershell' }
    It 'emits environment info without throwing' {
        # Fixed under ADR 0012 (dual-runtime policy): CLR/.NET line uses
        # [System.Environment]::Version only (FrameworkDescription removed -
        # needs .NET Framework 4.7.1+, unsafe on older PS 5.1; ADR 0013).
        # StrictMode-safe on PS 7. Get-CimInstance is absent here; the canon
        # guards it in try/catch ($os=$null fallback), so the function still runs.
        { Show-PowerShellEnvironment 6>&1 | Out-Null } | Should -Not -Throw
    }
}
