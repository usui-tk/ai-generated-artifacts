<#
.SYNOPSIS
    Self-contained PoC: download PDFs for known "_undated" decks and parse their metadata.

.DESCRIPTION
    This is a Proof of Concept (PoC) that validates the PDF-metadata
    parsing logic against the SPECIFIC decks that were classified as
    "_undated" by Download-SpeakerDeck.ps1 in past runs.

    Repository: https://github.com/usui-tk/ai-generated-artifacts
    Location  : scripts/powershell/download-speakerdeck-oracle4engineer/Test-PdfMetadata.ps1
    License   : MIT (see LICENSE at the repository root)

    Prerequisites:
      - Windows PowerShell 5.1+ (also runs on PowerShell 7+)
      - 64-bit process
      - Internet access to speakerdeck.com and files.speakerdeck.com
      - TLS 1.2 capable runtime (the script forces TLS 1.2)

    Known limitations:
      - Hardcoded to two specific deck URLs from a past oracle4engineer run;
        not a general-purpose tool
      - Read-only: does not modify the main Download-SpeakerDeck.ps1
        downloads/ directory; uses its own poc-temp/ scratch space
      - Disposable: kept in the repo for reference / regression testing
        of the Phase 8 metadata parsing logic

    AI tool: Generated with Anthropic Claude during r15 development of
            Download-SpeakerDeck.ps1.

    No parameters are required. Just run the script.

    The two target decks are hardcoded near the top of this file
    (see `$KnownUndatedDecks`). They were identified from prior
    P04_filename_plan.csv runs as the only decks for which the main
    script's Get-DeckYear logic could not derive a year:

      Index 732 : oracle-cloud-hangout-cafe-seitaininshounoiroha
                  (filename: ochacafe_04_01_v1.0.pdf)
      Index 739 : lets-dive-serverless-world
                  (filename: Serverless...public.pdf)

    Both fall back to "_undated" because their Speaker Deck pages
    return no usable og:meta - so neither PublishDate nor a title
    with a year is available. They are therefore the ideal test
    cases for the proposed "post-download PDF-metadata classification"
    feature.

    Workflow for each hardcoded deck:
      1. Fetch the deck PAGE HTML
      2. Extract the files.speakerdeck.com PDF download URL
         (the same extraction the main script does in Phase 3)
      3. Download the PDF
      4. Parse PDF metadata via pure-PowerShell regex
      5. Display the extracted fields and the derived year (if any)

    This script makes NO modifications to any other file or directory.

.PARAMETER TempDir
    Where to download PDFs for parsing. Default: ".\poc-temp"
    relative to the script. Files are kept after the run so they
    can be inspected in a PDF viewer.

.PARAMETER DeleteAfter
    Delete the downloaded PDF after parsing. Off by default.

.EXAMPLE
    .\Test-PdfMetadata.ps1
    Runs the PoC against the hardcoded list of known _undated decks.

.NOTES
    PowerShell 5.1+ on Windows 10/11 or Windows Server 2016+.
#>

[CmdletBinding()]
param(
    [string]$TempDir     = (Join-Path $PSScriptRoot 'poc-temp'),
    [switch]$DeleteAfter
)

# ============================================================
# Hardcoded targets - the known _undated decks from prior P04 runs
# ============================================================
$KnownUndatedDecks = @(
    [PSCustomObject]@{
        Index            = 732
        DeckPageUrl      = 'https://speakerdeck.com/oracle4engineer/oracle-cloud-hangout-cafe-seitaininshounoiroha'
        ExpectedFilename = 'ochacafe_04_01_v1.0.pdf'
        Note             = 'Title=slug fallback case; og:meta missing, so PublishDate is empty.'
    },
    [PSCustomObject]@{
        Index            = 739
        DeckPageUrl      = 'https://speakerdeck.com/oracle4engineer/lets-dive-serverless-world'
        ExpectedFilename = 'Serverless...public.pdf'
        Note             = 'Title=slug fallback case; og:meta missing, so PublishDate is empty.'
    }
)

# ============================================================
# Script identification
# ============================================================
$Script:ScriptVersion = 'pdf-metadata-poc-2026.05.11-r03'
$Script:ScriptTag     = 'hardcoded-undated-decks'
$Script:ScriptHash    = '(unknown)'
try {
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
        $hashFull = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $Script:ScriptHash = $hashFull.Substring(0, 12).ToLower()
    }
} catch {
    $Script:ScriptHash = '(hash-error)'
}
$Script:ScriptShortTag  = ('v{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)

# ============================================================
# Initial setup
# ============================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    Write-Warning "Could not set console encoding to UTF-8 (continuing anyway)"
}

# Force TLS 1.2 (PS 5.1 default is TLS 1.0; speakerdeck.com requires 1.2+).
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor `
        [Net.SecurityProtocolType]::Tls
} catch { } # psa-disable-line PSA3004 -- older PS hosts may lack newer enum values; ignore silently

# ============================================================
# Compatibility check
# ============================================================
function Assert-PowerShellCompatibility {
    $pv    = $PSVersionTable.PSVersion
    $minPs = [Version]'5.1'
    if ($pv -lt $minPs) {
        throw ("PowerShell $minPs or later required (detected $pv).")
    }
    if (-not [Environment]::Is64BitProcess) {
        throw 'A 64-bit PowerShell process is required.'
    }
}

# ============================================================
# Logging helpers
# ============================================================
function _LogLine {
    param([string]$Marker, [string]$Msg, [string]$Color)
    Write-Host ("    {0} {1}" -f $Marker, $Msg) -ForegroundColor $Color
}

function Write-Ok   { param([string]$m) _LogLine '[+]' $m 'Green'    }
function Write-Warn { param([string]$m) _LogLine '[!]' $m 'Yellow'   }
function Write-Fail { param([string]$m) _LogLine '[X]' $m 'Red'      }

# ============================================================
# PDF metadata reader
# ============================================================
function Get-PdfMetadata {
    <#
    .SYNOPSIS
        Read identification metadata from a PDF file (read-only).

    .DESCRIPTION
        Reads up to the first 1MB and the last 512KB of the file
        (PDF metadata is conventionally near the start in the Info
        Dictionary or near the end in the XMP packet). Decodes as
        Latin-1 so binary stream portions do not raise decode errors
        while ASCII metadata regions remain byte-accurate.
    #>
    param([Parameter(Mandatory)][string]$PdfPath)

    $r = [ordered]@{
        FileSize              = 0
        BytesScanned          = 0
        InfoDict_CreationDate = ''
        InfoDict_ModDate      = ''
        InfoDict_Producer     = ''
        InfoDict_Creator      = ''
        InfoDict_Title        = ''
        InfoDict_Author       = ''
        Xmp_CreateDate        = ''
        Xmp_ModifyDate        = ''
        Xmp_xap_CreateDate    = ''
        Xmp_pdf_CreationDate  = ''
        ExtractedYear         = ''
        ExtractedYearSource   = ''
        ExtractedYearValid    = $false
        ErrorMessage          = ''
    }

    try {
        $fi = Get-Item -LiteralPath $PdfPath -ErrorAction Stop
        $r.FileSize = $fi.Length

        $headSize = [Math]::Min([int64]$fi.Length, [int64]1MB)
        $tailSize = [Math]::Min([int64]$fi.Length, [int64]512KB)

        $fs = [System.IO.File]::OpenRead($PdfPath)
        try {
            $headBuf = New-Object byte[] $headSize
            [void]$fs.Read($headBuf, 0, $headSize)

            $tailBuf = $null
            if ($fi.Length -gt 1MB) {
                $tailBuf = New-Object byte[] $tailSize
                $fs.Seek(-$tailSize, [IO.SeekOrigin]::End) | Out-Null
                [void]$fs.Read($tailBuf, 0, $tailSize)
            }
        } finally {
            $fs.Close()
        }

        $r.BytesScanned = $headSize
        if ($tailBuf) { $r.BytesScanned += $tailSize }

        $enc      = [System.Text.Encoding]::GetEncoding('iso-8859-1')
        $headText = $enc.GetString($headBuf)
        $tailText = if ($tailBuf) { $enc.GetString($tailBuf) } else { '' }
        $text     = $headText + "`n----TAIL-BOUNDARY----`n" + $tailText

        $dateRegex = '/{0}\s*\(\s*D:(\d{{4}})'
        $strRegex  = '/{0}\s*\(([^)]{{0,200}})\)'

        $tryDate = {
            param([string]$Key)
            $m = [regex]::Match($text, ($dateRegex -f $Key))
            if ($m.Success) { return $m.Groups[1].Value }
            return ''
        }

        $tryStr = {
            param([string]$Key)
            $m = [regex]::Match($text, ($strRegex -f $Key))
            if ($m.Success) {
                $s = ($m.Groups[1].Value -replace '\s+', ' ').Trim()
                if ($s.Length -gt 100) { $s = $s.Substring(0, 97) + '...' }
                return $s
            }
            return ''
        }

        $tryXml = {
            param([string]$Tag)
            $pattern = '<' + [regex]::Escape($Tag) + '>\s*([^<\s]{1,80})\s*</' + [regex]::Escape($Tag) + '>'
            $m = [regex]::Match($text, $pattern)
            if ($m.Success) { return $m.Groups[1].Value }
            return ''
        }

        $r.InfoDict_CreationDate = & $tryDate 'CreationDate'
        $r.InfoDict_ModDate      = & $tryDate 'ModDate'
        $r.InfoDict_Producer     = & $tryStr  'Producer'
        $r.InfoDict_Creator      = & $tryStr  'Creator'
        $r.InfoDict_Title        = & $tryStr  'Title'
        $r.InfoDict_Author       = & $tryStr  'Author'

        $r.Xmp_CreateDate        = & $tryXml 'xmp:CreateDate'
        $r.Xmp_ModifyDate        = & $tryXml 'xmp:ModifyDate'
        $r.Xmp_xap_CreateDate    = & $tryXml 'xap:CreateDate'
        $r.Xmp_pdf_CreationDate  = & $tryXml 'pdf:CreationDate'

        # Year derivation - prefer CreationDate over ModDate;
        # Info Dict over XMP.
        $candidates = @(
            @{ Value = $r.InfoDict_CreationDate; Source = 'InfoDict_CreationDate' },
            @{ Value = $r.Xmp_CreateDate;        Source = 'Xmp_CreateDate'        },
            @{ Value = $r.Xmp_xap_CreateDate;    Source = 'Xmp_xap_CreateDate'    },
            @{ Value = $r.Xmp_pdf_CreationDate;  Source = 'Xmp_pdf_CreationDate'  },
            @{ Value = $r.InfoDict_ModDate;      Source = 'InfoDict_ModDate (fallback)' },
            @{ Value = $r.Xmp_ModifyDate;        Source = 'Xmp_ModifyDate (fallback)'   }
        )

        $minYear = 2010
        $maxYear = (Get-Date).Year + 1

        foreach ($c in $candidates) {
            if ([string]::IsNullOrWhiteSpace($c.Value)) { continue }
            $m = [regex]::Match($c.Value, '^(\d{4})')
            if (-not $m.Success) { continue }
            $yStr = $m.Groups[1].Value
            $yInt = [int]$yStr
            $r.ExtractedYear       = $yStr
            $r.ExtractedYearSource = $c.Source
            $r.ExtractedYearValid  = ($yInt -ge $minYear -and $yInt -le $maxYear)
            if ($r.ExtractedYearValid) { break }
        }
    } catch {
        $r.ErrorMessage = $_.Exception.Message
    }

    return [PSCustomObject]$r
}

# ============================================================
# Display
# ============================================================
function Show-PdfMetadataResult {
    param([Parameter(Mandatory)]$Meta)

    if (-not [string]::IsNullOrEmpty($Meta.ErrorMessage)) {
        Write-Fail ("Parse error: {0}" -f $Meta.ErrorMessage)
        return
    }

    Write-Host ''
    Write-Host '    PDF metadata extracted:'

    $fmt = '      {0,-28}: {1}'
    $orEmpty = {
        param($s)
        if ([string]::IsNullOrEmpty($s)) { return '(not present)' }
        return $s
    }

    Write-Host ($fmt -f '/CreationDate (Info Dict)', (& $orEmpty $Meta.InfoDict_CreationDate))
    Write-Host ($fmt -f '/ModDate      (Info Dict)', (& $orEmpty $Meta.InfoDict_ModDate))
    Write-Host ($fmt -f '/Producer     (Info Dict)', (& $orEmpty $Meta.InfoDict_Producer))
    Write-Host ($fmt -f '/Creator      (Info Dict)', (& $orEmpty $Meta.InfoDict_Creator))
    Write-Host ($fmt -f '/Title        (Info Dict)', (& $orEmpty $Meta.InfoDict_Title))
    Write-Host ($fmt -f '/Author       (Info Dict)', (& $orEmpty $Meta.InfoDict_Author))
    Write-Host ($fmt -f 'xmp:CreateDate',            (& $orEmpty $Meta.Xmp_CreateDate))
    Write-Host ($fmt -f 'xmp:ModifyDate',            (& $orEmpty $Meta.Xmp_ModifyDate))
    Write-Host ($fmt -f 'xap:CreateDate (legacy)',   (& $orEmpty $Meta.Xmp_xap_CreateDate))
    Write-Host ($fmt -f 'pdf:CreationDate',          (& $orEmpty $Meta.Xmp_pdf_CreationDate))

    Write-Host ''
    Write-Host '    Year extraction:'
    if ([string]::IsNullOrEmpty($Meta.ExtractedYear)) {
        Write-Fail 'No year could be extracted from any metadata field.'
    } else {
        $minYear = 2010
        $maxYear = (Get-Date).Year + 1
        Write-Host ($fmt -f 'Selected year', $Meta.ExtractedYear)
        Write-Host ($fmt -f 'Source field',  $Meta.ExtractedYearSource)
        $rangeText = ('{0} <= {1} <= {2}' -f $minYear, $Meta.ExtractedYear, $maxYear)
        if ($Meta.ExtractedYearValid) {
            Write-Ok   ("In valid range : YES  ({0})" -f $rangeText)
        } else {
            Write-Warn ("In valid range : NO   (extracted year out of [{0}, {1}])" -f $minYear, $maxYear)
        }
    }
}

# ============================================================
# Deck page -> PDF download URL resolution
# ============================================================
function Resolve-PdfDownloadUrl {
    <#
    .SYNOPSIS
        Given a Speaker Deck page URL, find the direct PDF download URL.

    .DESCRIPTION
        Fetches the deck page HTML and scans for the standard
        files.speakerdeck.com/presentations/<uuid>/<filename>.pdf URL.
        Replicates what the main Download-SpeakerDeck.ps1 does in
        Phase 3 (Get-DeckDetailFromPage), but simplified - we only
        need the PDF URL here.
    #>
    param([Parameter(Mandatory)][string]$DeckPageUrl)

    $resp = Invoke-WebRequest -Uri $DeckPageUrl `
                              -UseBasicParsing `
                              -TimeoutSec 30 `
                              -ErrorAction Stop
    $html = $resp.Content

    # Speaker Deck PDF URLs look like:
    #   https://files.speakerdeck.com/presentations/<32hex>/<filename>.pdf
    # The presentations segment can be a 32-char hex string or a UUID-
    # style hyphenated form; we accept both.
    $pattern = 'https://files\.speakerdeck\.com/presentations/[a-fA-F0-9\-]+/[^"''<>\s]+\.pdf'
    $m = [regex]::Match($html, $pattern)
    if (-not $m.Success) {
        throw "Could not find a PDF download URL in the page HTML."
    }
    return $m.Value
}

# ============================================================
# Download helper
# ============================================================
function Invoke-PdfDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutPath
    )
    try {
        $startTime = Get-Date
        Invoke-WebRequest -Uri $Url `
                          -OutFile $OutPath `
                          -UseBasicParsing `
                          -TimeoutSec 60 `
                          -ErrorAction Stop | Out-Null
        $size    = (Get-Item -LiteralPath $OutPath).Length
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        Write-Ok ("Downloaded {0:N2} MB in {1:F1}s -> {2}" -f ($size / 1MB), $elapsed, $OutPath)
        return $true
    } catch {
        Write-Fail ("Download failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

# ============================================================
# Main
# ============================================================
try {
    Assert-PowerShellCompatibility

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host '  PDF Metadata PoC - Hardcoded _undated decks' -ForegroundColor Magenta
    Write-Host ('  ' + $Script:ScriptShortTag) -ForegroundColor DarkGray
    Write-Host ('=' * 72) -ForegroundColor Magenta
    $pv      = $PSVersionTable.PSVersion
    $bitness = if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }
    Write-Host ('  PowerShell : {0} ({1}, {2})' -f $pv, $PSVersionTable.PSEdition, $bitness)
    Write-Host ('  Temp dir   : {0}' -f $TempDir)
    Write-Host ('  Targets    : {0} hardcoded _undated decks' -f $KnownUndatedDecks.Count)
    Write-Host ('=' * 72) -ForegroundColor Magenta

    if (-not (Test-Path -LiteralPath $TempDir)) {
        New-Item -Path $TempDir -ItemType Directory -Force | Out-Null
    }

    $i = 0
    $okCount = 0
    foreach ($deck in $KnownUndatedDecks) {
        $i++
        Write-Host ''
        Write-Host ('-' * 72)
        Write-Host ("  [{0}/{1}] Index #{2}" -f $i, $KnownUndatedDecks.Count, $deck.Index) -ForegroundColor White
        Write-Host ("         Deck page : {0}" -f $deck.DeckPageUrl)
        Write-Host ("         Expected  : {0}" -f $deck.ExpectedFilename)
        Write-Host ("         Note      : {0}" -f $deck.Note) -ForegroundColor DarkGray
        Write-Host ('-' * 72)

        # Step 1: resolve PDF download URL from the deck page
        Write-Host '    Resolving PDF download URL from deck page...'
        $pdfUrl = $null
        try {
            $pdfUrl = Resolve-PdfDownloadUrl -DeckPageUrl $deck.DeckPageUrl
            Write-Ok ("Resolved -> {0}" -f $pdfUrl)
        } catch {
            Write-Fail ("URL resolution failed: {0}" -f $_.Exception.Message)
            continue
        }

        # Step 2: derive a local filename
        $localName = [System.IO.Path]::GetFileName(([Uri]$pdfUrl).AbsolutePath)
        if ([string]::IsNullOrEmpty($localName)) { $localName = ('poc_{0}.pdf' -f $i) }
        $outPath = Join-Path $TempDir $localName

        # Step 3: download
        Write-Host '    Downloading PDF...'
        if (-not (Invoke-PdfDownload -Url $pdfUrl -OutPath $outPath)) {
            continue
        }

        # Step 4: parse metadata
        $meta = Get-PdfMetadata -PdfPath $outPath
        Show-PdfMetadataResult -Meta $meta

        if ($meta.ExtractedYearValid) { $okCount++ }

        if ($DeleteAfter) {
            Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ("  Done. {0} / {1} decks produced a valid year." -f $okCount, $KnownUndatedDecks.Count) -ForegroundColor Cyan
    if ($okCount -eq $KnownUndatedDecks.Count) {
        Write-Host '  VERDICT: All targets yielded a usable year - PDF metadata path is viable.' -ForegroundColor Green
    } elseif ($okCount -gt 0) {
        Write-Host '  VERDICT: Some targets yielded a year - partial viability; review per-deck output.' -ForegroundColor Yellow
    } else {
        Write-Host '  VERDICT: No targets yielded a year - PDF metadata path would NOT rescue these decks.' -ForegroundColor Red
    }
    if (-not $DeleteAfter) {
        Write-Host ("  Downloaded files kept in: {0}" -f $TempDir) -ForegroundColor DarkGray
    }
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ''

} catch {
    Write-Host ''
    Write-Fail ("Fatal: {0}" -f $_.Exception.Message)
    Write-Host ''
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
