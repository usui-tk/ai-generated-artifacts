# BootVerification.Common.ps1
# Shared, judgment-light building blocks for the ISO boot-verification
# tool set (dot-sourced by the harness / rig-state / collector
# scripts, and by the offline test T39). No script-scope state; every
# function here is either pure or a thin, single-purpose I/O wrapper.
#
# Design basis: DESIGN-boot-verification-arc (adjudicated 2026-07-08).

Set-StrictMode -Version 3.0

# ---- Well-known Secure Boot identities --------------------------------

$Script:EfiCertX509Guid = [guid]'a5c059a1-94e4-4aa7-87b5-ab155c2bf072'

function Get-KnownSecureBootSubjectPattern {
    <#
    .SYNOPSIS
        The two certificate subjects this project's verdicts hinge on.
        Regex fragments, matched against the X.509 Subject string.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        Pca2011 = 'Microsoft Windows Production PCA 2011'
        Ca2023  = 'Windows UEFI CA 2023'
    }
}

# ---- EFI_SIGNATURE_LIST parsing (pure) --------------------------------

function ConvertFrom-EfiSignatureList {
    <#
    .SYNOPSIS
        Pure parser: raw db/dbx variable bytes -> signature entries.
    .DESCRIPTION
        The UEFI spec lays the variable out as a sequence of
        EFI_SIGNATURE_LIST structures:
          SignatureType   GUID    (16 bytes)
          SignatureListSize UINT32
          SignatureHeaderSize UINT32
          SignatureSize   UINT32
          ...header..., then (SignatureListSize - 28 - header) /
          SignatureSize entries of { SignatureOwner GUID (16) | data }.
        Returns one record per signature: TypeGuid + Data (bytes after
        the owner GUID). Truncated/garbage tails stop the walk instead
        of throwing -- a damaged variable should degrade to "fewer
        entries", not kill the rig check.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [byte[]]$Bytes
    )
    $entries = New-Object System.Collections.Generic.List[object]
    if (-not $Bytes -or $Bytes.Length -lt 28) { return $entries.ToArray() }
    $pos = 0
    while (($pos + 28) -le $Bytes.Length) {
        $typeGuid = [guid][byte[]]$Bytes[$pos..($pos + 15)]
        $listSize = [BitConverter]::ToUInt32($Bytes, $pos + 16)
        $hdrSize  = [BitConverter]::ToUInt32($Bytes, $pos + 20)
        $sigSize  = [BitConverter]::ToUInt32($Bytes, $pos + 24)
        if ($listSize -lt 28 -or ($pos + $listSize) -gt $Bytes.Length -or $sigSize -lt 16) { break }
        $sigArea = $pos + 28 + $hdrSize
        $sigEnd  = $pos + $listSize
        while (($sigArea + $sigSize) -le $sigEnd) {
            $dataLen = $sigSize - 16
            $data = if ($dataLen -gt 0) { [byte[]]$Bytes[($sigArea + 16)..($sigArea + $sigSize - 1)] } else { @() }
            $entries.Add([pscustomobject]@{
                TypeGuid = $typeGuid
                Data     = $data
            }) | Out-Null
            $sigArea += $sigSize
        }
        $pos += $listSize
    }
    return $entries.ToArray()
}

function Get-SecureBootCertSubject {
    <#
    .SYNOPSIS
        Pure: extract the X.509 subjects of every certificate entry in
        a parsed signature list (non-cert entry types are skipped;
        unparsable certificate bytes are skipped, never fatal).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [object[]]$Entries
    )
    $subjects = New-Object System.Collections.Generic.List[string]
    foreach ($e in @($Entries)) {
        if ($null -eq $e -or $e.TypeGuid -ne $Script:EfiCertX509Guid) { continue }
        try {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$e.Data)
            $subjects.Add([string]$cert.Subject) | Out-Null
        } catch { $null = $_ }
    }
    return $subjects.ToArray()
}

function Test-SecureBootSubjectPresence {
    <#
    .SYNOPSIS
        Pure verdict helper: does a subject list contain the PCA2011 /
        the 2023 CA? Returns @{ Has2011; Has2023 }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()] [AllowEmptyCollection()] [string[]]$Subjects
    )
    $pat = Get-KnownSecureBootSubjectPattern
    $has2011 = $false; $has2023 = $false
    foreach ($s in @($Subjects)) {
        if ([string]::IsNullOrEmpty($s)) { continue }
        if ($s -match [regex]::Escape($pat.Pca2011)) { $has2011 = $true }
        if ($s -match [regex]::Escape($pat.Ca2023))  { $has2023 = $true }
    }
    return @{ Has2011 = $has2011; Has2023 = $has2023 }
}

# ---- Hyper-V console screenshot (RGB565 -> BMP; pure converter) ------

function Convert-Rgb565ToBmpByte {
    <#
    .SYNOPSIS
        Pure: RGB565 raw pixel bytes (top-down, little-endian, as
        returned by Msvm GetVirtualSystemThumbnailImage) -> a complete
        16bpp BI_BITFIELDS .bmp file as bytes. No GDI dependency, so
        it runs identically on Windows PowerShell hosts and in the
        Linux offline test (T39).
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)] [byte[]]$PixelData,
        [Parameter(Mandatory)] [int]$Width,
        [Parameter(Mandatory)] [int]$Height
    )
    if ($PixelData.Length -lt ($Width * $Height * 2)) {
        throw ('Convert-Rgb565ToBmpByte: pixel buffer {0} bytes is smaller than {1}x{2}x2.' -f $PixelData.Length, $Width, $Height)
    }
    $rowBytes = $Width * 2
    $stride   = [int]([math]::Ceiling($rowBytes / 4.0) * 4)
    $imgSize  = $stride * $Height
    $headerSize = 14 + 40 + 12          # BITMAPFILEHEADER + BITMAPINFOHEADER + 3 masks
    $ms = New-Object System.IO.MemoryStream
    $w  = New-Object System.IO.BinaryWriter($ms)
    # BITMAPFILEHEADER
    $w.Write([byte[]](0x42, 0x4D))                       # 'BM'
    $w.Write([uint32]($headerSize + $imgSize))           # file size
    $w.Write([uint32]0)                                   # reserved
    $w.Write([uint32]$headerSize)                         # pixel offset
    # BITMAPINFOHEADER (BI_BITFIELDS)
    $w.Write([uint32]40)
    $w.Write([int32]$Width)
    $w.Write([int32]$Height)                              # positive = bottom-up
    $w.Write([uint16]1)
    $w.Write([uint16]16)
    $w.Write([uint32]3)                                   # BI_BITFIELDS
    $w.Write([uint32]$imgSize)
    $w.Write([int32]2835); $w.Write([int32]2835)
    $w.Write([uint32]0); $w.Write([uint32]0)
    # 565 channel masks
    $w.Write([uint32]0xF800); $w.Write([uint32]0x07E0); $w.Write([uint32]0x001F)
    # Pixel rows: source is top-down, BMP wants bottom-up.
    $pad = New-Object byte[] ($stride - $rowBytes)
    for ($y = $Height - 1; $y -ge 0; $y--) {
        $w.Write($PixelData, $y * $rowBytes, $rowBytes)
        if ($pad.Length -gt 0) { $w.Write($pad) }
    }
    $w.Flush()
    return $ms.ToArray()
}

function Save-VmConsoleScreenshot {
    <#
    .SYNOPSIS
        I/O wrapper: capture a Hyper-V VM's console thumbnail via WMI
        (root\virtualization\v2) and write it as .bmp. Returns the
        output path, or $null when capture is unavailable (VM off,
        WMI denied) -- callers record the gap, never crash.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$VmName,
        [Parameter(Mandatory)] [string]$OutPath,
        [int]$Width = 640,
        [int]$Height = 480
    )
    try {
        $ns = 'root\virtualization\v2'
        $vm = Get-CimInstance -Namespace $ns -ClassName Msvm_ComputerSystem -Filter ("ElementName='{0}'" -f ($VmName -replace "'", "''"))
        if (-not $vm) { return $null }
        $svc = Get-CimInstance -Namespace $ns -ClassName Msvm_VirtualSystemManagementService
        $r = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{
            HeightPixels = [uint16]$Height; WidthPixels = [uint16]$Width; TargetSystem = $vm
        }
        if ($null -eq $r -or $r.ReturnValue -ne 0 -or -not $r.ImageData) { return $null }
        $bmp = Convert-Rgb565ToBmpByte -PixelData ([byte[]]$r.ImageData) -Width $Width -Height $Height
        [System.IO.File]::WriteAllBytes($OutPath, $bmp)
        return $OutPath
    } catch {
        Write-Warning ('Save-VmConsoleScreenshot: {0}' -f $_.Exception.Message)
        return $null
    }
}

# ---- Test matrix vocabulary (pure) ------------------------------------

function Get-BootVerificationCellMap {
    <#
    .SYNOPSIS
        Pure: the adjudicated T1..T12 matrix -- rig, depth, and the
        EXPECTED outcome per cell (DESIGN-boot-verification-arc SS2).
        The ledger stores expectation next to observation so a later
        reader never has to reconstruct intent.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        'T1'  = @{ Rig = 'STD'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'regression: converted 2016' }
        'T2'  = @{ Rig = 'STD'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'regression: 2019 mixed config (2023 bootmgr + 1809 WinPE) -- first-ever boot of this combination' }
        'T3'  = @{ Rig = 'STD'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'regression: converted 2022' }
        'T4'  = @{ Rig = 'STD'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'regression: unconverted 2025 (current default)' }
        'T5'  = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'target proof: converted 2016 on revoked firmware' }
        'T6'  = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'target proof + adjudication #1 (Healthy upgrade): 2019 fallback media on revoked firmware' }
        'T7'  = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'target proof: converted 2022 on revoked firmware' }
        'T8'  = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'boot-failure';  Note = 'adjudication #2b basis: unconverted 2025 must FAIL on revoked firmware' }
        'T9'  = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'boot-failure';  Note = 'negative control: pristine EVAL ISO must FAIL (validates the rig itself)' }
        'T10' = @{ Rig = 'REV'; Depth = 'install'; Expected = 'install-completes'; Note = 'end-to-end: 2019 fallback media unattended install + evidence collection' }
        'T11' = @{ Rig = 'REV'; Depth = 'install'; Expected = 'install-completes'; Note = 'optional: additional OS full installs' }
        'T12' = @{ Rig = 'REV'; Depth = 'boot';    Expected = 'reaches-setup'; Note = 'optional: rig with Mitigation 4 (SVN) additionally applied' }
    }
}

function New-BootVerificationLedgerEntry {
    <#
    .SYNOPSIS
        Pure: assemble one ledger record (expectation + observation
        slots). Outcome starts as 'pending-operator' for boot-depth
        cells (screenshot review) and is set by the harness for the
        automated install-depth cells.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string]$Cell,
        [Parameter(Mandatory)] [string]$IsoPath,
        [Parameter(Mandatory)] [string]$VmName,
        [AllowEmptyCollection()] [string[]]$Screenshots = @(),
        [string]$Outcome = 'pending-operator',
        [string]$Detail = ''
    )
    $map = Get-BootVerificationCellMap
    if (-not $map.ContainsKey($Cell)) {
        throw ('New-BootVerificationLedgerEntry: unknown cell {0} (expected T1..T12).' -f $Cell)
    }
    $c = $map[$Cell]
    return [pscustomobject]@{
        Timestamp   = (Get-Date).ToString('o')
        Cell        = $Cell
        Rig         = $c.Rig
        Depth       = $c.Depth
        Expected    = $c.Expected
        Note        = $c.Note
        IsoPath     = $IsoPath
        VmName      = $VmName
        Screenshots = @($Screenshots)
        Outcome     = $Outcome
        Detail      = $Detail
    }
}
