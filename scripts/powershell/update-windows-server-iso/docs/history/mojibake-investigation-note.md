# Investigation note: P05 WIM edition name mojibake on PS 5.1 ConsoleHost

**Status**: deferred. To be investigated AFTER current
script-functionality verification work is complete (Step 16
P10 progress logging and download progress utility).

**Logged in**: r07.0 Step 16 (2026-05-26)
**Logged from**: live PrepareBuildVerify run on
Windows Server 2025 / PowerShell 5.1.26100.32860 / ja-JP locale,
Server 2016 EVAL ISO ja-jp as source media.

## Observation

In P05 ExpandIso, the WIM enumeration step prints one line per
install.wim and boot.wim index. The user reported, and the
captured log confirms, that some edition-name strings appear
with **each Japanese character doubled** while others on the
same run render correctly:

```
[18:21:45] [*]   install.wim idx 1: Windows Server 2016 Standard Evaluation (8.86 GB)
[18:21:45] [*]   install.wim idx 2: Windows Server 2016 Standard Evaluation (デデススククトトッッププ エエククススペペリリエエンンスス) (14.53 GB)
[18:21:45] [*]   install.wim idx 3: Windows Server 2016 Datacenter Evaluation (8.85 GB)
[18:21:45] [*]   install.wim idx 4: Windows Server 2016 Datacenter Evaluation (デスクトップ エクスペリエンス) (14.54 GB)
```

The expected string is `デスクトップ エクスペリエンス`
(13 characters); the observed render on idx 2 is
`デデススククトトッッププ エエククススペペリリエエンンスス`
(each non-ASCII codepoint repeated). Idx 4 prints the same
underlying string correctly on the same run, so the issue is
**not** in the WIM metadata itself.

The earlier Step 15 run shows the same pattern; this is
reproducible across runs.

Additionally, the very next log line under idx 2 (the
`install.wim idx 3` line) appears with its timestamp / indent
prefix overlapping the idx 2 line tail, suggesting a
carriage-return / line-wrap interaction in the console at the
same time as the doubled-character output.

## What this is NOT

- It is **not** a data corruption issue. P05 writes the raw
  edition name into the on-disk CSV
  (`D:\UpdateWsi\logs\P04_wim_inventory.csv`) which can be
  inspected separately; if the CSV contains the doubled
  characters too, the hypothesis below is wrong. The
  investigation must check the CSV first.
- It is **not** a bug in Get-WindowsImage. The same cmdlet
  call produces a correct string for idx 4 and a corrupt
  one for idx 2 within the same process.
- It is **not** a script ASCII-only violation. The script
  itself is BOM + CRLF + ASCII (verified by quality gates);
  the Japanese strings come from the WIM metadata at runtime.

## Hypothesis (to be confirmed)

PowerShell 5.1's `ConsoleHost` renders strings through the
legacy Win32 console subsystem, which has known issues
handling UTF-16 surrogate pairs and code-page transitions on
mixed-script lines. The OutputEncoding in the run was
`utf-8 (cp65001)` while the system default `OutputEncoding`
was `shift_jis (cp932)` (visible at the top of every run's
"Step 0: PowerShell environment" dump).

The doubling pattern (each char becomes two of the same char)
is characteristic of:

1. A string being written **twice** to the console with the
   second write landing on top of the first via an embedded
   `\r` or similar carriage control - but this would not
   double *each individual character*, it would produce
   overprint artifacts.
2. UTF-16 code unit being misinterpreted: a Japanese char in
   UTF-16 is a single 16-bit code unit (mostly), but the
   console may be reading each *byte* of that code unit as
   a separate codepoint to render. This would produce
   gibberish, not the same character doubled.
3. **Most likely**: a `String.Normalize()` interaction where
   the WIM metadata stores the edition name in NFD
   (decomposed) form for some indexes and NFC (composed) for
   others. Japanese voiced consonants in NFD render as base
   character + combining mark, and a console that doesn't
   support combining marks may show them as separate
   characters - but the visible pattern is exact-duplicate,
   not base+mark, so this is also unlikely.

The strongest lead is to compare the byte sequences directly:

```powershell
$wim = Get-WindowsImage -ImagePath 'D:\UpdateWsi\source\extracted\sources\install.wim' -Index 2
$bytes = [System.Text.Encoding]::UTF8.GetBytes($wim.ImageName)
$bytes | ForEach-Object { '{0:X2}' -f $_ } | Join-String -Separator ' '
```

vs. idx 4 of the same WIM, and look for whether idx 2 has
duplicated UTF-8 sequences in the underlying byte array, or
whether they differ only in the rendering pipeline.

## Investigation plan (when picked up)

1. **Verify the CSV is intact**. `Get-Content
   D:\UpdateWsi\logs\P04_wim_inventory.csv -Encoding UTF8`
   and check the idx 2 column. If the CSV is correct,
   the issue is purely a console-render bug and the fix is
   localised to the `Write-Step` call site.

2. **Capture the raw bytes** of the edition name strings
   for all four install.wim indexes via the diagnostic
   one-liner above, write them to a side-by-side file,
   and inspect.

3. **Reproduce in isolation**. Write a 10-line PS1 that just
   does `Get-WindowsImage -ImagePath ... -Index N | Select
   ImageName` for each N and prints via `Write-Host` with
   different `-Encoding` settings. If the doubling reproduces
   without any of this script's helpers, the issue is
   upstream of us.

4. **Test a workaround**. If the issue is console-only,
   options include:
   - Force ConsoleHost output to UTF-16 LE via
     `[Console]::OutputEncoding = [System.Text.Encoding]::Unicode`
     at the start of the run (changes the rendering path).
   - Route the WIM enumeration output through
     `[System.Text.Encoding]::UTF8.GetString(
       [System.Text.Encoding]::UTF8.GetBytes($name))` to
     forcibly normalise.
   - Write Japanese strings only to the CSV (which is fine)
     and emit a romanised or English-fallback rendering to
     the console.

5. **Check whether this also happens** on PS 7 / pwsh.exe on
   the same Windows Server 2025 host. If PS 7 renders both
   indexes correctly, that confirms the issue is in PS 5.1
   ConsoleHost specifically and gives the user a clean
   workaround (switch host shell for inspection).

## Pointers into the codebase

- WIM enumeration call site that produces the affected lines:
  `Update-WindowsServerIso.ps1` `Invoke-BuildPhase05_ExpandIso`,
  around the `install.wim idx N: ... ` Write-Step calls. Search
  for `install.wim idx` in the file.
- CSV writer: `P04_wim_inventory.csv` is written at the end of
  the same function.
- Console encoding setup: `Set-ConsoleUtf8` (search for the
  function name) runs at process start and is responsible for
  the `OutputEncoding = utf-8 (cp65001)` line in the
  environment dump.

## Priority

**LOW**. The data is correct, the CSV is intact, and downstream
processing (P06-P13) does not depend on console rendering of
the edition name. This is purely a cosmetic issue on the
operator's screen.

Investigate only after the higher-priority items are clear:

1. (P0) P10 ConvertPca2023BootManager runs to completion or
   skips cleanly via the Step 16 skip-with-warn path.
2. (P0) P11 StaticVerify / P12 VerifyPca2023Readiness / P13
   FinalReport all run cleanly to the end after a P10 skip.
3. (P1) End-to-end `-Execute` run produces a valid output ISO.

## NEW FINDING from Step 17 run (2026-05-26 evening)

The mojibake **did not reproduce** when the user re-ran the
exact same command with one change:

- Original run (Step 16 verification, mojibake observed):
  `-WorkRoot 'D:\UpdateWsi'`
- New run (Step 17 verification, mojibake absent):
  `-WorkRoot 'D:\UpdateWsi_2016'`

idx 2 now renders correctly as
`Windows Server 2016 Standard Evaluation (デスクトップ エクスペリエンス)`.

Everything else was identical: same source ISO file, same
Server 2016 EVAL ja-jp media, same PS 5.1.26100.32860 on
Windows Server 2025 Datacenter, same ja-JP culture, same
`Default Encoding shift_jis (cp932)` / `Console OutputEnc.
utf-8 (cp65001)`.

This strongly narrows the suspect surface. The mojibake was
NOT in:

- The WIM metadata (the source ISO is byte-identical and was
  produced correctly on the second run)
- The Get-WindowsImage cmdlet's serialisation (same cmdlet,
  same input)
- The console host's character rendering (same host, same
  output encoding)
- The script's logging pipeline (no PS1 changes between the
  two runs)

It WAS most likely in:

- **Something about the WIM mount path used by
  `Mount-WindowsImage`**, which is derived from `$WorkRoot`.
  The original `D:\UpdateWsi` had been used for many prior
  runs with mounted, dismounted, and partially-cleaned-up
  WIMs in nested directories. The new `D:\UpdateWsi_2016` was
  a fresh tree. A stale mount, an orphaned hard link, or a
  filesystem entry with corrupted name encoding could have
  influenced how the WIM provider reads back the edition
  name on subsequent enumerations.
- **Or**: a WIM-provider cache (DISM keeps per-WIM scratch
  state under `%TEMP%`, `%WINDIR%\Logs\DISM`, or
  `WimMountedImageInfo` registry hives). If a prior aborted
  P10 run left a stale entry mapping the same WIM path to
  cached metadata in a corrupted state, the same WIM
  re-enumerated through a different mount would still serve
  the cached corruption.

### Updated investigation plan

Higher-confidence next steps:

1. **Compare `Get-WindowsImageInfo` byte-by-byte** between
   `D:\UpdateWsi\source\iso\WS2016_ja-jp.iso` (the original
   WorkRoot's cached ISO) and the same file copied into the
   new `D:\UpdateWsi_2016\source\iso\` tree. Confirm SHA-256
   matches (the Step 17 log already shows
   `ceb4e1f78614...` for both runs - they ARE identical).

2. **List current DISM state**: run
   `Get-WindowsImage -Mounted` and `dism /Get-MountedImageInfo`
   on the user's host to see whether stale mounts are still
   registered for the old `D:\UpdateWsi` paths. If so, this
   is direct evidence of the cache-poisoning hypothesis.

3. **Test the DISM cleanup workaround**: re-run the original
   `-WorkRoot 'D:\UpdateWsi'` command and observe whether
   mojibake reproduces. If yes, then run `dism /Cleanup-Wim`
   and rerun - if mojibake goes away, the cause is confirmed
   as DISM-state-related.

4. **Capture both the CSV and the raw .ImageName bytes** for
   the mojibake-affected indexes when reproducing. The CSV
   write happens AFTER `Get-WindowsImage` returns, so if the
   CSV is also corrupted the issue is at WIM-read time; if
   the CSV is clean the issue is in `Write-Step`'s
   formatting / console output specifically.

The mojibake is no longer blocking and no longer reliably
reproducible, which makes this even more deserving of
"investigate when there's time" status. The DISM-cache
hypothesis is also actionable: if the user wants a quick
workaround in the meantime, **always use a fresh WorkRoot
per OS family** (which is what `D:\UpdateWsi_2016` is doing)
already side-steps the problem entirely.

