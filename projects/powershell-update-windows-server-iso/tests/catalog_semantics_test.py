#!/usr/bin/env python3
"""T50: Catalog boundary & collection-shape contract (behavioral, offline).

Behavioral coverage of the r12.52 -> r12.67 Catalog hardening arc: the
typed semantic-validation transport, validated caching, same-response
legacy parsing, scalar identity boundaries, flat collection shapes, and
collision-resistant cache identity. The functions under test are
extracted from the script's own AST and exercised against fixtures whose
values are measured Catalog shapes (including the user-observed Server
2016 four-row Setup DU query and the KB4132216 HTTP-200 page shape).

Specification source: the r12.75 distribution's required suite, axes
R1252 / R1265 / R1266 / R1267 (input-only per the standing ruling; logic
re-authored, code not copied). Ledger: TEST-REIMPL-LEDGER.csv rows for
those axes. The real-environment-validated r12.75 script is the
specification baseline (code-anchored testing); the script is untouched.
The distribution's revision-floor rows are DROP (T40 pins the exact
ScriptVersion). The R1252 servicing-contract component-hash rows are
ADOPT-D in T45 (declaration-anchored), not here.

Class: B (behaviour pins). Justification: semantic retry, validator
scope, scalar boundaries and collection shapes live in script code; no
declared data surface expresses them.

What this asserts:

  1. **Function inventory.** The merged R1252 + R1265 + R1267
     catalog/collection function set (48 functions) exists exactly once
     -- this also feeds the refactoring plan's static
     duplicate-function check later.
  2. **Horizontal static invariants (r12.66/r12.67).** No GetNewClosure
     validator, no scriptblock ContentValidator parameter or call site,
     no nested sorted-collection return, the three typed semantic modes
     plus ExactKbSearch declared, transport evidence carries the
     validation context (catalog-transport-event/1.2), the unused
     unvalidated POST cache helper is gone, and the collision-resistant
     cache-identity and flat-PatchBaseline contracts are present.
  3. **Typed validator wiring (r12.66).** Get-UpdateIdFromCatalog and
     Search-Catalog select the typed exact-KB contract; cache and
     transport validation both flow through the centralized semantic
     validator; local validator execution failure is distinguished
     (CATALOG_VALIDATOR_EXECUTION_FAILED) and excluded from transient
     retries.
  4. **Legacy helper containment (r12.52).** The legacy search/download
     helpers contain no direct Invoke-WebRequest -Uri and reuse
     supplied validated HTML before any networking.
  5. **Setup-DU scalar identity (r12.65).** The selector emits flat
     candidate collections; Resolve-CatalogDownload validates UpdateId
     cardinality/format BEFORE constructing the POST body;
     Resolve-SetupDu rejects nested candidate rows and validates the
     selected row's uid.
  6. **Semantic retry runtime (r12.52).** An invalid HTTP-200 body is
     classified a transient failure, retried, and the valid response
     returned, with exactly two transport events (Failure/transient/200
     then Success); invalid cached content is discarded and replaced
     only after exactly one revalidated fetch; supplied validated HTML
     is parsed with no network request.
  7. **Typed endpoint semantics runtime (r12.66/r12.67).** Every active
     endpoint mode accepts its parseable measured shape and rejects the
     mismatched one; a malformed exact-KB validation context fails the
     contract; validator execution failure is not transient while a
     genuine HTTP-200 semantic mismatch remains retryable.
  8. **Cache identity runtime (r12.67).** Distinct search identities
     produce distinct digest-bearing tags; download / legacy-download /
     scoped tags embed the full UpdateId.
  9. **Scalar boundary runtime (r12.65/r12.67).** Arrays, Generic.List
     values and space-joined multi-GUID strings are rejected at the
     UpdateId / KbId / query boundaries before Catalog transport.
 10. **Flat collection runtime (r12.65/r12.67).** The measured Server
     2016 four-row Setup DU shape yields four flat candidates and the
     newest-at-or-before selection returns the single KB5068794 row;
     Select-SetupDuCandidate / Get-X64Rows / ConvertTo-ConfigLines emit
     flat sequences; the language-pack template and WIM inventory
     materialize Generic.List values before exposure.

Run:  python3 tests/catalog_semantics_test.py
Deps: pwsh on PATH (same dependency class as T40/T47/T48/T52).
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

SUBPROJECT_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT_PATH = SUBPROJECT_ROOT / "Update-WindowsServerIso.ps1"

# Merged R1252 + R1265 + R1267 catalog/collection inventory: each defined
# exactly once. Also the extraction set for the behavioral driver.
CATALOG_TRANSPORT_FUNCTIONS = [
    "Get-CatalogRequestHeaders",
    "Get-CatalogRawEvidenceDirectory",
    "Get-CatalogResponseShapeSummary",
    "Get-CatalogTextSha256",
    "Write-CatalogRawEvidence",
    "Update-CatalogRawEvidenceMetadata",
    "Get-CatalogTransportEvidencePath",
    "Get-CatalogHttpStatusCodeFromError",
    "Test-CatalogTransientFailure",
    "Write-CatalogTransportEvidence",
    "Invoke-CatalogWebRequest",
    "Get-CatalogText",
]
CATALOG_PARSER_FUNCTIONS = [
    "Convert-HtmlToText",
    "Get-CatalogSearchCandidatesFromHtml",
    "ConvertFrom-CatalogJavaScriptEscapes",
    "Get-CatalogDownloadFilesFromHtml",
    "Test-CatalogContentSemantics",
    "Get-UpdateIdFromCatalog",
    "Get-DownloadLinkFromCatalog",
]
CATALOG_BOUNDARY_FUNCTIONS = [
    "ConvertTo-CatalogBoundaryArray",
    "Assert-CatalogScalarKbId",
    "Assert-CatalogScalarUpdateId",
    "Get-CatalogCacheIdentityTag",
    "Search-Catalog",
]
SETUP_DU_SELECTION_FUNCTIONS = [
    "Select-SetupDuCandidate",
    "Get-Newest",
    "Get-UpdateMonthFromTitle",
    "Get-NewestAtOrBeforeMonth",
    "Resolve-CatalogDownload",
    "Resolve-SetupDu",
]
COLLECTION_SHAPE_FUNCTIONS = [
    "ConvertTo-ConfigLines",
    "Get-LanguagePackQueryTemplate",
    "Get-X64Rows",
    "Get-WimIndexInventory",
]
CANONICAL_CONTRACT_FUNCTIONS = [
    "_CanonicalJson_WriteString",
    "_CanonicalJson_WriteNumber",
    "_CanonicalJson_WriteObject",
    "_CanonicalJson_WriteArray",
    "_CanonicalJson_WriteValue",
    "ConvertTo-CanonicalJson",
    "Get-CanonicalObjectSha256",
    "New-Server2016ServicingContract",
    "New-Server2019ServicingContract",
    "New-Server2022ServicingContract",
    "New-Server2025ServicingContract",
    "Get-ServicingContract",
    "Get-ServicingContractHash",
    "Get-ServicingContractComponentHashes",
]
INVENTORY = (CATALOG_TRANSPORT_FUNCTIONS + CATALOG_PARSER_FUNCTIONS
             + CATALOG_BOUNDARY_FUNCTIONS + SETUP_DU_SELECTION_FUNCTIONS
             + COLLECTION_SHAPE_FUNCTIONS + CANONICAL_CONTRACT_FUNCTIONS)
# Driver extraction set: everything behavioral needs; the servicing
# contract constructors stay out (their behavior is T45's subject).
DRIVER_FUNCTIONS = (CATALOG_TRANSPORT_FUNCTIONS + CATALOG_PARSER_FUNCTIONS
                    + CATALOG_BOUNDARY_FUNCTIONS
                    + SETUP_DU_SELECTION_FUNCTIONS[:4]
                    + COLLECTION_SHAPE_FUNCTIONS)

# Horizontal static pins. Needles are facts of the artifact under test.
STATIC_PRESENT_PINS = [
    ("SearchRows typed semantic mode declared", "'SearchRows'"),
    ("DownloadAssetRows typed semantic mode declared", "'DownloadAssetRows'"),
    ("ScopedUpdateDetails typed semantic mode declared", "'ScopedUpdateDetails'"),
    ("flat PatchBaseline line invariant present", "PATCHLINE_COLLECTION_SHAPE_INVALID"),
    ("transport evidence carries the validation context",
     "catalog-transport-event/1.2"),
    ("collision-resistant cache identity contract present",
     "CATALOG_CACHE_IDENTITY_INVALID"),
]
STATIC_ABSENT_PINS = [
    ("no GetNewClosure-based validator remains", ".GetNewClosure()"),
    ("no scriptblock ContentValidator parameter remains",
     "[scriptblock]$ContentValidator"),
    ("unused unvalidated Catalog POST cache helper is gone",
     "function Invoke-CatalogPost"),
]

DRIVER = r'''
param([Parameter(Mandatory)][string]$ScriptPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$FunctionNames = @(__FUNCTION_NAMES__)
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Name,[bool]$Ok,[string]$Detail='') {
    $results.Add([pscustomobject]@{Name=$Name;Ok=$Ok;Detail=$Detail}) | Out-Null
}
function Run-Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; Add-Result $Name $true }
    catch { Add-Result $Name $false ([string]$_.Exception.Message) }
}
function Expect([bool]$Cond,[string]$Why) { if (-not $Cond) { throw $Why } }
function Expect-Eq($Actual,$Expected,[string]$Why) {
    if ($Actual -ne $Expected) { throw "$Why expected=[$Expected] actual=[$Actual]" }
}

$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
if (@($errors).Count -gt 0) { throw 'script parse errors' }
foreach ($n in $FunctionNames) {
    $defs=@($ast.FindAll({param($x)$x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true))
    if ($defs.Count -ne 1) { throw "function $n definition count $($defs.Count)" }
    Invoke-Expression $defs[0].Extent.Text
}
function Write-Caution([string]$Message){}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('t50-' + [guid]::NewGuid().ToString('N'))
$Script:LogsDir = Join-Path $testRoot 'logs'
$script:CatCache = Join-Path $testRoot 'cache'
New-Item -ItemType Directory -Path $Script:LogsDir,$script:CatCache -Force | Out-Null
$script:CatTimeoutScheduleSec = [int[]]@(1,2,3)
$script:CatRetryDelayScheduleSec = [int[]]@(0,0)
$script:CatUA = 't50-fixture'
$script:CatAcceptLanguage = 'en-US'

try {

# ---- 1. Semantic retry, transport evidence, validated cache (r12.52) ----
$retryGuid = '174c2d93-e9ca-4f9e-a3fd-fa5c91ef6bab'
$q = [string][char]39
$validSearchHtml = '<html><a onclick=' + $q + 'goToDetails("' + $retryGuid + '");' + $q + '>2026-07 Safe OS Dynamic Update (KB5099546)</a></html>'
$invalidSearchHtml = '<html><title>Microsoft Update Catalog</title><body>temporary landing page</body></html>'
$script:attempt = 0
function Invoke-WebRequest {
    param($Uri,$Headers,$UseBasicParsing,$TimeoutSec,$ErrorAction,$Method,$Body,$ContentType)
    $script:attempt++
    if ($script:attempt -eq 1) { return [pscustomobject]@{Content=$invalidSearchHtml;StatusCode=200} }
    return [pscustomobject]@{Content=$validSearchHtml;StatusCode=200}
}
$response = Invoke-CatalogWebRequest -Url 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB5099546' `
    -Method GET -Tag 'semantic.retry' -ContentValidationMode ExactKbSearch `
    -ContentValidationExpectedKbId 'KB5099546' -ContentValidationDescription 'exact KB row'
Run-Check 'invalid HTTP-200 body is retried and the validated response returned' {
    Expect-Eq $script:attempt 2 'network attempts'
    Expect-Eq ([string]$response.Content) $validSearchHtml 'returned content'
}
Run-Check 'transport evidence records the semantic failure then the success' {
    $events = @(Get-Content -LiteralPath (Get-CatalogTransportEvidencePath) -Encoding UTF8 |
        ForEach-Object { $_ | ConvertFrom-Json })
    Expect-Eq $events.Count 2 'transport event count'
    Expect-Eq ([string]$events[0].Outcome) 'Failure' 'first outcome'
    Expect ([bool]$events[0].Transient) 'semantic HTTP-200 failure not transient'
    Expect-Eq ([int]$events[0].StatusCode) 200 'semantic failure status code'
    Expect-Eq ([string]$events[1].Outcome) 'Success' 'second outcome'
}
Run-Check 'invalid cached content triggers exactly one revalidated fetch and is replaced' {
    $cacheTag = 'search.KB5099546.raw.r1219.html'
    $cachePath = Join-Path $script:CatCache $cacheTag
    [IO.File]::WriteAllText($cachePath,$invalidSearchHtml,[Text.UTF8Encoding]::new($false))
    $script:attempt = 1
    $before = $script:attempt
    $html = Get-CatalogText -Url 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB5099546' `
        -Tag $cacheTag -ContentValidationMode ExactKbSearch `
        -ContentValidationExpectedKbId 'KB5099546' -ContentValidationDescription 'exact KB row'
    Expect-Eq ($script:attempt - $before) 1 'revalidation request count'
    Expect-Eq ([string]$html) $validSearchHtml 'validated content'
    Expect-Eq (Get-Content -LiteralPath $cachePath -Raw) $validSearchHtml 'replaced cache content'
}
function Invoke-WebRequest { throw 'Unexpected network request while parsing supplied HTML.' }
Run-Check 'supplied validated search HTML is parsed with no network request' {
    $parsed = @(Get-UpdateIdFromCatalog -KbId KB5099546 -Html $validSearchHtml)
    Expect-Eq $parsed.Count 1 'parsed row count'
    Expect-Eq ([string]$parsed[0].UpdateId) $retryGuid 'parsed UpdateId'
}
Run-Check 'supplied validated download HTML is parsed with no network request' {
    $downloadHtml = "downloadInformation[0].files[0].url = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2026/07/windows-kb.cab';"
    $links = @(Get-DownloadLinkFromCatalog -UpdateId $retryGuid -Html $downloadHtml)
    Expect-Eq $links.Count 1 'download row count'
    Expect-Eq ([string]$links[0].FileName) 'windows-kb.cab' 'download file name'
}

# ---- 2. Typed endpoint semantics (measured shapes, r12.66/r12.67) ----
$uid1 = '035de820-3292-4169-99fa-520b541bfe0d'
$uid2 = '35b44e6d-d341-475f-820c-382b5ad63aa3'
$searchHtml = '<html><body><table>' +
    '<a id="' + $uid1 + '_link" onclick="goToDetails(' + $q + $uid1 + $q + ');">2018-05 Servicing Stack Update for Windows Server 2016 for x64-based Systems (KB4132216)</a>' +
    '<a id="' + $uid2 + '_link" onclick="goToDetails(' + $q + $uid2 + $q + ');">2025-11 Setup Dynamic Update for Windows 10 Version 1607 and Windows Server 2016 for x64-based Systems (KB5068794)</a>' +
    '</table></body></html>'
Run-Check 'SearchRows accepts a parseable generic search response' {
    Expect (Test-CatalogContentSemantics -Content $searchHtml -Mode SearchRows) 'SearchRows rejected'
}
Run-Check 'ExactKbSearch accepts the measured KB4132216 page shape' {
    Expect (Test-CatalogContentSemantics -Content $searchHtml -Mode ExactKbSearch -ExpectedKbId 'KB4132216') 'exact KB rejected'
    # The exact-KB row filter is a context-window heuristic (measured:
    # +/-1800 chars around each anchor), so the single-row parse pin uses
    # a page containing only the KB4132216 anchor, as the measured
    # KB4132216 page shape does.
    $exactHtml = '<html><body><table>' +
        '<a id="' + $uid1 + '_link" onclick="goToDetails(' + $q + $uid1 + $q + ');">2018-05 Servicing Stack Update for Windows Server 2016 for x64-based Systems (KB4132216)</a>' +
        '</table></body></html>'
    $rows = @(Get-CatalogSearchCandidatesFromHtml -Html $exactHtml -ExactKbId 'KB4132216')
    Expect-Eq $rows.Count 1 'exact-KB row count'
    Expect-Eq ([string]$rows[0].UpdateId) $uid1 'exact-KB UpdateId'
}
Run-Check 'ExactKbSearch rejects a different KB' {
    Expect (-not (Test-CatalogContentSemantics -Content $searchHtml -Mode ExactKbSearch -ExpectedKbId 'KB9999999')) 'different KB accepted'
}
Run-Check 'a malformed exact-KB validation context fails the contract' {
    $rejected = $false
    try { $null = Test-CatalogContentSemantics -Content $searchHtml -Mode ExactKbSearch -ExpectedKbId '4132216' }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_VALIDATION_CONTRACT_INVALID' }
    Expect $rejected 'malformed context not rejected'
}
$downloadAssetHtml = "downloadInformation[0].files[0].fileName = 'windows10.0-kb5068794-x64.cab';`n" +
    "downloadInformation[0].files[0].url = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/updt/2025/11/windows10.0-kb5068794-x64.cab';"
Run-Check 'DownloadAssetRows accepts a parseable DownloadDialog response' {
    Expect (Test-CatalogContentSemantics -Content $downloadAssetHtml -Mode DownloadAssetRows -ExpectedUpdateId $uid2) 'DownloadAssetRows rejected'
}
Run-Check 'DownloadAssetRows rejects a body without package URLs' {
    Expect (-not (Test-CatalogContentSemantics -Content '<html>Error</html>' -Mode DownloadAssetRows -ExpectedUpdateId $uid2)) 'no-URL body accepted'
}
$scopedHtml = '<html><body><div id="labelUpdateID">' + $uid2 + '</div><div id="labelSupportedProducts">Windows Server 2016</div><div id="labelKbArticleNumbers">5068794</div><h1>Update Details</h1></body></html>'
Run-Check 'ScopedUpdateDetails accepts a matching details response' {
    Expect (Test-CatalogContentSemantics -Content $scopedHtml -Mode ScopedUpdateDetails -ExpectedUpdateId $uid2) 'matching details rejected'
}
Run-Check 'ScopedUpdateDetails rejects a different UpdateId' {
    Expect (-not (Test-CatalogContentSemantics -Content $scopedHtml -Mode ScopedUpdateDetails -ExpectedUpdateId $uid1)) 'different UpdateId accepted'
}
Run-Check 'local validator execution failure is excluded from transient retries' {
    $failure = $null
    try { throw [InvalidOperationException]::new('CATALOG_VALIDATOR_EXECUTION_FAILED: fixture') } catch { $failure = $_ }
    Expect (-not (Test-CatalogTransientFailure -ErrorRecord $failure)) 'validator failure classified transient'
}
Run-Check 'a genuine HTTP-200 semantic mismatch remains retryable' {
    $mismatch = $null
    try { throw [IO.InvalidDataException]::new('CATALOG_SEMANTIC_RESPONSE_INVALID: fixture') } catch { $mismatch = $_ }
    Expect (Test-CatalogTransientFailure -ErrorRecord $mismatch) 'semantic mismatch not retryable'
}

# ---- 3. Collision-resistant cache identity (r12.67) ----
Run-Check 'distinct search identities produce distinct digest-bearing cache tags' {
    $tag1 = Get-CatalogCacheIdentityTag -Kind Search -Identity 'Dynamic Update Windows Server 2016 x64 alpha'
    $tag2 = Get-CatalogCacheIdentityTag -Kind Search -Identity 'Dynamic Update Windows Server 2016 x64 beta'
    Expect ($tag1 -ne $tag2) 'distinct identities collided'
    Expect ($tag1 -match '^search\..+\.[0-9a-f]{16}\.raw\.r1267\.html$') ('search tag format: ' + $tag1)
}
Run-Check 'download, legacy-download and scoped cache tags embed the full UpdateId' {
    Expect-Eq (Get-CatalogCacheIdentityTag -Kind Download -Identity $uid2) ('dl.' + $uid2 + '.raw.r1267.html') 'download tag'
    Expect-Eq (Get-CatalogCacheIdentityTag -Kind LegacyDownload -Identity $uid2) ('legacy.dl.' + $uid2 + '.raw.r1267.html') 'legacy download tag'
    Expect-Eq (Get-CatalogCacheIdentityTag -Kind Scoped -Identity $uid2) ('scoped.' + $uid2 + '.raw.r1267.html') 'scoped tag'
}

# ---- 4. Scalar identity boundaries (r12.65/r12.67) ----
Run-Check 'an UpdateId array is rejected for cardinality before transport' {
    $rejected = $false
    try { $null = Assert-CatalogScalarUpdateId -Value @($uid1,$uid2) -Context 'fixture' }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_UPDATEID_CARDINALITY_INVALID' }
    Expect $rejected 'array UpdateId not rejected'
}
Run-Check 'Generic.List UpdateIds are materialized and rejected for cardinality' {
    $ids = [System.Collections.Generic.List[object]]::new()
    $ids.Add($uid1) | Out-Null
    $ids.Add($uid2) | Out-Null
    $rejected = $false
    try { $null = Assert-CatalogScalarUpdateId -Value $ids -Context 'generic-list-fixture' }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_UPDATEID_CARDINALITY_INVALID' }
    Expect $rejected 'Generic.List UpdateIds not rejected'
}
Run-Check 'a space-joined multi-GUID string is rejected for format' {
    $rejected = $false
    try { $null = Assert-CatalogScalarUpdateId -Value ($uid1 + ' ' + $uid2) -Context 'joined-fixture' }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_UPDATEID_FORMAT_INVALID' }
    Expect $rejected 'joined multi-GUID string not rejected'
}
Run-Check 'a KB identifier array is rejected for cardinality' {
    $rejected = $false
    try { $null = Assert-CatalogScalarKbId -Value @('KB4132216','KB5068794') -Context 'fixture' }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_KBID_CARDINALITY_INVALID' }
    Expect $rejected 'KB array not rejected'
}
Run-Check 'Search-Catalog rejects multiple query values' {
    $rejected = $false
    try { $null = Search-Catalog -Query @('KB4132216','KB5068794') }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_QUERY_CARDINALITY_INVALID' }
    Expect $rejected 'multi-query not rejected'
}
Run-Check 'the legacy DownloadDialog helper rejects multiple UpdateIds' {
    $rejected = $false
    try { $null = Get-DownloadLinkFromCatalog -UpdateId @($uid1,$uid2) -Html $downloadAssetHtml }
    catch { $rejected = $_.Exception.Message -match 'CATALOG_UPDATEID_CARDINALITY_INVALID' }
    Expect $rejected 'legacy multi-UpdateId not rejected'
}

# ---- 5. Setup DU selection (measured Server 2016 four-row shape) ----
$server2016Rows = @(
    [pscustomobject]@{ uid='35b44e6d-d341-475f-820c-382b5ad63aa3'
        title='2025-11 Dynamic Update for Windows 10 Version 1607 for x64-based Systems (KB5068794)'
        products='Windows 10 and later Dynamic Update'; classification='Critical Updates'
        lastUpdated='11/11/2025'; version=''; sizeText='5.6 MB' },
    [pscustomobject]@{ uid='560b5f9d-20b1-460a-94ae-d09871da1f89'
        title='2025-07 Dynamic Update for Windows 10 Version 1607 for x64-based Systems (KB5062786)'
        products='Windows 10 and later Dynamic Update'; classification='Critical Updates'
        lastUpdated='7/8/2025'; version=''; sizeText='5.6 MB' },
    [pscustomobject]@{ uid='6b4e2661-a1d4-4d22-810a-f055f4c38d09'
        title='2024-10 Dynamic Update for Windows 10 Version 1607 for x64-based Systems (KB5045521)'
        products='Windows 10 and later Dynamic Update'; classification='Critical Updates'
        lastUpdated='10/8/2024'; version=''; sizeText='5.1 MB' },
    [pscustomobject]@{ uid='45799add-ee18-4f90-9636-a5088112e64b'
        title='2020-02 Dynamic Update for Windows 10 Version 1607 for x64-based Systems (KB4532820)'
        products='Windows 10 Dynamic Update'; classification='Critical Updates'
        lastUpdated='2/11/2020'; version=''; sizeText='2.1 MB' }
)
Run-Check 'the measured Server 2016 broad query yields four flat Setup DU candidates' {
    $candidates = @(Select-SetupDuCandidate -Rows $server2016Rows -VersionToken 'Version 1607')
    Expect-Eq $candidates.Count 4 'candidate count'
    Expect (@($candidates | Where-Object { $_ -is [System.Array] }).Count -eq 0) 'nested candidate present'
}
Run-Check 'newest-at-or-before selects the single KB5068794 row and its scalar identity survives' {
    $candidates = @(Select-SetupDuCandidate -Rows $server2016Rows -VersionToken 'Version 1607')
    $selected = Get-NewestAtOrBeforeMonth -Rows $candidates -BaselineMonth '2026-07'
    Expect ($null -ne $selected) 'no candidate selected'
    Expect (-not ($selected -is [System.Array])) 'selected row is an array'
    Expect-Eq ([string]$selected.uid) '35b44e6d-d341-475f-820c-382b5ad63aa3' 'selected UpdateId'
    $scalar = Assert-CatalogScalarUpdateId -Value $selected.uid -Context 'runtime-fixture'
    Expect-Eq ([string]$scalar) '35b44e6d-d341-475f-820c-382b5ad63aa3' 'scalar validation changed identity'
}

# ---- 6. Flat collection shapes (r12.65/r12.67) ----
Run-Check 'Select-SetupDuCandidate emits a flat sequence for the generic shape' {
    $duRows = @(
        [pscustomobject]@{ title='2025-11 Setup Dynamic Update for Windows 10 Version 1607 x64'; products='Dynamic Update'; uid=$uid2 },
        [pscustomobject]@{ title='2025-07 Setup Dynamic Update for Windows 10 Version 1607 x64'; products='Dynamic Update'; uid=$uid1 }
    )
    $selected = @(Select-SetupDuCandidate -Rows $duRows -VersionToken 'Version 1607')
    Expect-Eq $selected.Count 2 'flat candidate count'
    Expect (@($selected | Where-Object { $_ -is [System.Array] }).Count -eq 0) 'nested element present'
}
Run-Check 'Get-X64Rows emits a flat filtered sequence' {
    $x64 = @(Get-X64Rows -Rows @(
        [pscustomobject]@{ title='Package x64' },
        [pscustomobject]@{ title='Package arm64' }
    ))
    Expect-Eq $x64.Count 1 'x64 row count'
    Expect (-not ($x64[0] -is [System.Array])) 'x64 element nested'
}
Run-Check 'ConvertTo-ConfigLines emits a flat line sequence' {
    function Get-ServicingContract { param([string]$OsKey) return [pscustomobject]@{ PatchModel='separate-ssu' } }
    function Get-ServicingContractRoleTargets { param([string]$Role,$Contract) return @('Install') }
    $raw = [pscustomobject]@{
        os='Server2016'
        lines=@(
            [pscustomobject]@{kind='SSU';kb='KB4132216';catalogUid=$uid1;title='SSU';products='Windows Server 2016';files=@([pscustomobject]@{fileName='ssu.msu';url='https://example/ssu.msu';digest='';sha256=''});inScope=$null;note='fixture'},
            [pscustomobject]@{kind='LCU';kb='KB5099535';catalogUid=$uid2;title='LCU';products='Windows Server 2016';files=@([pscustomobject]@{fileName='lcu.msu';url='https://example/lcu.msu';digest='';sha256=''});inScope=[pscustomobject]@{build='14393.9339'};note='fixture'}
        )
    }
    $lines = @(ConvertTo-ConfigLines -OsResolved $raw -PatchModel 'separate-ssu')
    Expect-Eq $lines.Count 2 'config line count'
    Expect (@($lines | Where-Object { $_ -is [System.Array] }).Count -eq 0) 'nested line present'
}
Run-Check 'the language-pack query template materializes its Generic.List' {
    $template = Get-LanguagePackQueryTemplate -OsVersion Server2016 -OsLanguage ja-jp -PatchMonth 2026-07
    Expect ($template.Queries -is [System.Array]) 'Queries exposed Generic.List'
    Expect-Eq (@($template.Queries).Count) 3 'query count'
}
Run-Check 'the WIM index inventory materializes its Generic.List (mock DISM)' {
    function Invoke-DismCmdlet {
        param([string]$CommandName,[hashtable]$Parameters)
        return @(
            [pscustomobject]@{ImageIndex=1;ImageName='One';ImageDescription='One';ImageSize=1},
            [pscustomobject]@{ImageIndex=2;ImageName='Two';ImageDescription='Two';ImageSize=2}
        )
    }
    $tempWim = Join-Path $testRoot 'inventory.wim'
    [IO.File]::WriteAllBytes($tempWim,[byte[]](0))
    $inventory = @(Get-WimIndexInventory -WimPath $tempWim)
    Expect-Eq $inventory.Count 2 'inventory count'
    Expect (-not ($inventory -is [System.Collections.Generic.List[object]])) 'inventory exposed Generic.List'
}

} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$results | ConvertTo-Json -Depth 4
'''


def extract_function(text: str, name: str) -> str:
    """Return the full text of a top-level function by brace matching."""
    m = re.search(r"(?m)^function %s\b" % re.escape(name), text)
    if m is None:
        return ""
    i = text.index("{", m.start())
    depth = 0
    j = i
    while j < len(text):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    return text[m.start():j + 1]


def check(name, cond, detail, passed, failed):
    if cond:
        print(f"  PASS  {name}")
        return passed + 1, failed
    print(f"  FAIL  {name}: {detail}")
    return passed, failed + 1


def main() -> int:
    passed = failed = 0

    print("=" * 72)
    print("T50 Catalog boundary & collection-shape contract")
    print("=" * 72)

    text = SCRIPT_PATH.read_text(encoding="utf-8-sig")

    for fn in INVENTORY:
        n = len(re.findall(r"(?m)^\s*function\s+" + re.escape(fn) + r"\b", text))
        passed, failed = check(
            f"catalog/collection function defined exactly once: {fn}",
            n == 1, f"definition count = {n}", passed, failed)

    for name, needle in STATIC_PRESENT_PINS:
        passed, failed = check(name, needle in text,
                               f"marker missing: {needle}", passed, failed)
    for name, needle in STATIC_ABSENT_PINS:
        passed, failed = check(name, needle not in text,
                               f"forbidden marker present: {needle}", passed, failed)
    passed, failed = check(
        "no production ContentValidator call site remains",
        not re.search(r"-ContentValidator\s", text),
        "call site found", passed, failed)
    passed, failed = check(
        "no nested sorted-collection return remains",
        not re.search(r"(?m)^\s*return\s+,\$sorted\s*$", text),
        "nested sorted return found", passed, failed)

    gu = extract_function(text, "Get-UpdateIdFromCatalog")
    gd = extract_function(text, "Get-DownloadLinkFromCatalog")
    passed, failed = check(
        "legacy search helper contains no direct Invoke-WebRequest -Uri",
        gu and not re.search(r"Invoke-WebRequest\s+-Uri", gu),
        "direct request found", passed, failed)
    passed, failed = check(
        "legacy download helper contains no direct Invoke-WebRequest -Uri",
        gd and not re.search(r"Invoke-WebRequest\s+-Uri", gd),
        "direct request found", passed, failed)
    passed, failed = check(
        "legacy search helper reuses supplied validated HTML before networking",
        "$content=$Html" in gu and "if($null -eq $content)" in gu,
        "reuse wiring missing", passed, failed)
    passed, failed = check(
        "legacy download helper reuses supplied validated HTML before networking",
        "$content=$Html" in gd and "if($null -eq $content)" in gd,
        "reuse wiring missing", passed, failed)
    passed, failed = check(
        "legacy search helper uses the typed exact-KB validation contract",
        "-ContentValidationMode ExactKbSearch" in gu,
        "typed contract missing", passed, failed)

    sc = extract_function(text, "Search-Catalog")
    gt = extract_function(text, "Get-CatalogText")
    iw = extract_function(text, "Invoke-CatalogWebRequest")
    ts = extract_function(text, "Test-CatalogContentSemantics")
    tt = extract_function(text, "Test-CatalogTransientFailure")
    passed, failed = check(
        "Search-Catalog selects the typed exact-KB validation contract",
        "$validationMode='ExactKbSearch'" in sc,
        "typed selection missing", passed, failed)
    passed, failed = check(
        "cache validation flows through the centralized semantic validator",
        "Test-CatalogContentSemantics" in gt,
        "centralized validator missing from Get-CatalogText", passed, failed)
    passed, failed = check(
        "transport validation flows through the centralized semantic validator",
        "Test-CatalogContentSemantics" in iw,
        "centralized validator missing from Invoke-CatalogWebRequest",
        passed, failed)
    passed, failed = check(
        "transport distinguishes local validator execution failure",
        "CATALOG_VALIDATOR_EXECUTION_FAILED" in iw,
        "distinguishing marker missing", passed, failed)
    passed, failed = check(
        "transient classification excludes local validator execution failure",
        "CATALOG_VALIDATOR_EXECUTION_FAILED" in tt,
        "exclusion marker missing", passed, failed)
    passed, failed = check(
        "the typed exact-KB semantic mode is declared by the validator",
        "'ExactKbSearch'" in ts,
        "ExactKbSearch declaration missing", passed, failed)

    sel = extract_function(text, "Select-SetupDuCandidate")
    passed, failed = check(
        "the Setup DU selector emits flat candidate collections",
        "return [object[]]$explicit" in sel and "return [object[]]$cands" in sel
        and "return ,$" not in sel,
        "flat return contract missing", passed, failed)
    rcd = extract_function(text, "Resolve-CatalogDownload")
    guard_idx = rcd.find("Assert-CatalogScalarUpdateId")
    body_idx = rcd.find("$body=")
    passed, failed = check(
        "Resolve-CatalogDownload validates UpdateId before POST body construction",
        0 <= guard_idx < body_idx,
        f"guard index {guard_idx}, body index {body_idx}", passed, failed)
    rsd = extract_function(text, "Resolve-SetupDu")
    passed, failed = check(
        "Resolve-SetupDu rejects nested candidate rows",
        "SETUPDU_CANDIDATE_SHAPE_INVALID" in rsd,
        "shape guard missing", passed, failed)
    passed, failed = check(
        "Resolve-SetupDu validates the selected row UpdateId before download",
        "Assert-CatalogScalarUpdateId -Value $row.uid" in rsd,
        "uid guard missing", passed, failed)

    pwsh = shutil.which("pwsh")
    if pwsh is None:
        passed, failed = check("behavioral driver", False,
                               "pwsh not on PATH (required, as for T40)",
                               passed, failed)
    else:
        with tempfile.TemporaryDirectory() as td:
            driver = pathlib.Path(td) / "t50_driver.ps1"
            names = ",".join(f"'{n}'" for n in DRIVER_FUNCTIONS)
            driver.write_text(DRIVER.replace("__FUNCTION_NAMES__", names),
                              encoding="utf-8")
            proc = subprocess.run(
                [pwsh, "-NoProfile", "-File", str(driver),
                 "-ScriptPath", str(SCRIPT_PATH)],
                capture_output=True, text=True, timeout=300)
        if proc.returncode != 0:
            passed, failed = check(
                "behavioral driver", False,
                f"rc={proc.returncode} stderr={proc.stderr.strip()[:300]!r}",
                passed, failed)
        else:
            try:
                rows = json.loads(proc.stdout)
            except json.JSONDecodeError:
                rows = None
            if rows is None:
                passed, failed = check(
                    "behavioral driver", False,
                    f"non-JSON output: {proc.stdout.strip()[:200]!r}",
                    passed, failed)
            else:
                if isinstance(rows, dict):
                    rows = [rows]
                for row in rows:
                    passed, failed = check(
                        row.get("Name", "<unnamed>"),
                        bool(row.get("Ok")),
                        str(row.get("Detail", ""))[:300],
                        passed, failed)

    print(f"\n  Summary: {passed} passed, {failed} failed, "
          f"{passed + failed} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
