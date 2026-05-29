# Windows Server ISO Update Mechanics: A Practitioner's Knowledge Base

> 🇺🇸 English version
> Japanese version: [`windows-server-iso-update-mechanics.ja.md`](./windows-server-iso-update-mechanics.ja.md)

## Abstract

Building a fully-patched Windows Server installation medium ("a slipstreamed ISO") from a Microsoft Evaluation ISO and a stack of cumulative updates is a deceptively layered exercise. The high-level recipe — mount the WIM, apply MSU packages, optionally rebuild boot binaries, repackage — has been documented for over a decade. What is not documented in any single Microsoft source is the cross-cutting concern matrix that a practitioner actually has to navigate to ship a Server 2016 / 2019 / 2022 / 2025 ISO that will boot cleanly on a 2024-or-later Secure Boot environment: where to discover patch metadata without authenticating to a Microsoft Account, how to interpret the Authenticode chain of `bootmgfw.efi` and its `_EX` sibling, how to reconcile a Servicing Stack Update (SSU) dependency before applying a Latest Cumulative Update (LCU), and how to verify the result without unboxing a physical server.

This article is a synthesis of the technical findings accumulated over several months of revision cycles on a real-world ISO update pipeline. It is **not** a how-to for any specific tool; the goal is to record the knowledge surface that any future implementer (human or LLM) will need to navigate, regardless of the language or framework they choose. The provenance section at the end of the article identifies the original repository whose investigation logs were synthesized into this document.

**Scope of applicability.** This article focuses specifically on offline servicing and rebuild workflows for Windows Server LTSC installation media. Client Windows editions, Windows Update for Business policy orchestration, and live in-place servicing are intentionally out of scope. The findings should not be generalized to those domains without independent verification.

### Methodology

The findings in this article were derived empirically, not from documentation alone. The investigation that produced them combined the following methods, repeated across multiple monthly Patch Tuesday cycles:

- **Live-cab inspection** against successive `wsusscn2.cab` snapshots, parsing the Master XML to observe real dependency, bundle, and payload structure rather than assuming a schema.
- **WIM inspection** across Server 2016 / 2019 / 2022 / 2025 Evaluation media, comparing the `\Windows\Boot\` layout and the presence or absence of `_EX` boot binaries per version.
- **Authenticode chain verification** via `X509Chain.Build()`, traversing each boot binary's chain to its trust anchor rather than trusting the immediate signer's display name.
- **Microsoft Update Catalog cross-reference validation**, confirming KB-to-build mappings and the combined LCU/SSU download behavior observed in the Catalog.
- **Comparison against WSUS and Microsoft Learn documentation** for the facts that are officially published (Classification GUIDs, release-info build/KB tables).
- **Repeated rebuild validation across monthly Patch Tuesday cycles**, re-running the end-to-end build against fresh updates to confirm that observations held over time rather than reflecting a single snapshot.

Where a claim rests on only one of these methods, the Confidence Levels section (§10) marks it accordingly.

---

## 1. Background and Audience

Microsoft ships Windows Server in two install-ready forms: the **Evaluation ISO** (downloadable from the Microsoft Evaluation Center; 180-day timed expiry; freely available without licensing) and the **retail / volume-licensed ISO** (acquired through the Microsoft 365 admin center, Volume Licensing Service Center, or an Open Value agreement). For implementer-driven ISO automation, the Evaluation ISO is often the most practical input, but redistribution and storage of the media must still comply with Microsoft's licensing terms (for example, before checking media into a CI artifact store, confirm the Evaluation Center terms permit it).

A practitioner approaching the task of building a "fully patched" ISO from such an Evaluation media usually starts from a question like: *what is the minimum set of MSU and CAB packages I need to apply to the install.wim so that, when this image is deployed and booted, it will be at the latest Patch Tuesday level and will be accepted by a Secure Boot environment that no longer trusts PCA2011?* The naive answer — "apply this month's LCU" — is incomplete. The full answer touches at least the following:

- Which **patch metadata surface** (release-info Markdown, .NET CU release notes, Microsoft Update Catalog, `wsusscn2.cab`) actually publishes what you need
- Whether the LCU you found requires a **Servicing Stack Update** to be applied first
- Whether the install.wim already ships the **PCA2023-signed boot binaries** or whether you must synthesise them via Microsoft's `Make2023BootableMedia.ps1` reference script
- How to verify, **post-build**, that the boot binaries actually carry the expected Authenticode chain — given that PowerShell's own `Get-AuthenticodeSignature` cmdlet has a presentation pitfall that has misled at least one investigation in the synthesised corpus

This article walks through each of those topics in order, with concrete examples drawn from the 2024-Q4 to 2026-Q2 Patch Tuesday cycle. The reader is assumed to be comfortable with Windows servicing terminology (LCU, SSU, MSU, CAB, WIM, DISM) at a definitional level; section 5 and Appendix A reinforce the terms that are used in non-trivial ways.

The article does NOT cover: bootable USB creation, OEM image customisation, Windows Update for Business policy authoring, or the corresponding Linux distribution servicing topics. Those are well-trodden elsewhere.

At a high level, the end-to-end workflow this article maps out has the following shape. Each stage is the subject of one or more later sections; the diagram is included here only to orient the reader before the detail begins:

```text
 release-info / .NET release notes        (§2.1, §2.2  — discovery)
            |
            v
     KB discovery layer                   (§2.1–§2.3  — what to fetch)
            |
            v
   Microsoft Update Catalog               (§2.3       — authoritative artifacts)
            |
            v
     Artifact retrieval (.msu / .cab)      (§2.3, §5.2 — LCU + SSU)
            |
            v
      wsusscn2 parsing (Master XML)        (§2.4       — offline discovery)
            |
            v
 Dependency / supersedence DB             (§5.5, §5.6 — pre-flight data)
            |
            v
     Pre-flight validation                (§5.5, §8.1 — fail closed)
            |
            v
        WIM servicing (LCU apply)          (§3.3, §4   — patch level)
            |
            v
   PCA2023 media synthesis (_EX)           (§3.2–§3.6  — Secure Boot)
            |
            v
     Verification pipeline                 (§3.7, §8   — signer chain + layout)
            |
            v
  Hyper-V / physical boot testing          (§3.7, §8.4 — firmware trust)
```

The crucial architectural distinction running through this whole chain is that the upper stages (discovery and dependency analysis) lean on reverse-engineered, offline metadata for speed, while the lower stages (applicability, servicing, and boot acceptance) defer to Microsoft's own authoritative logic. Keeping that boundary in mind makes the rest of the article easier to follow.

---

## 2. Microsoft's Patch Metadata Surfaces

A complete Patch Tuesday's worth of Windows Server updates is scattered across at least four distinct Microsoft-operated surfaces. None of them is a complete index of the others, and the relationships between them have changed over the past few years in ways that any working pipeline must accommodate.

### 2.1 The release-info Markdown source

The single most under-utilised Microsoft surface for this work is the **Windows Server release-info page** at `learn.microsoft.com/en-us/windows/release-health/windows-server-release-info`. When the same URL is requested with `?accept=text/markdown` appended, Microsoft Learn's content-negotiation layer returns the page as raw GitHub-flavoured Markdown rather than rendered HTML. The body is the actual source Markdown table verbatim — no wrappers, no JavaScript, no authentication, no rate-limit headers under casual use.

The page is GitHub-backed: its YAML front-matter exposes `gitcommit` and `git_commit_id` fields pointing to `https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md`. This means a careful implementer can pin to a specific commit hash for reproducibility and could in principle watch the `/commits` endpoint for structural changes.

What the page contains, broken down:

| Content | Coverage |
|---|---|
| Monthly LCU + OOB + preview rollup table per OS | Server 2016 from 2016-08, Server 2019 from 2018-10, Server 2022 from 2021-08, Server 2025 from 2024-10 — gaps are rare (Server 2016's GA month has one) |
| Hotpatch calendar for Server 2025 and Server 2022 | Full year of baseline-vs-hotpatch month assignments, including forward-looking entries Microsoft has scheduled but not yet released |
| Update type letters | "B" = Patch Tuesday, "C"/"D" = preview rollups, "OOB" = out-of-band, "A"/"E" = historical anomalies |

The page **does not** contain:

- .NET Framework cumulative updates (these have their own release-notes pages — section 2.2)
- Dynamic Update.Setup or Dynamic Update.SafeOs (Catalog-only — section 2.3)
- Language packs (Catalog-only)
- Standalone Servicing Stack Updates as a distinct row (they are bundled with the LCU on the Catalog, not listed separately on release-info)

The Hotpatch calendar deserves a specific note. Calendar years 2024 / 2025 / 2026 are all published. Server 2022's CY2024 has one anomaly — August was labelled "Baseline (Restart)" rather than the expected "Hotpatch" — likely because Microsoft adjusted the Server 2022 baseline cadence between CY2024 and CY2025 to align with the canonical Jan / Apr / Jul / Oct pattern. The practical implication is: **the authoritative baseline-month list is the per-row `Type` field on the calendar**, not a hard-coded `{1, 4, 7, 10}` rule. An implementer who needs the Jan / Apr / Jul / Oct heuristic will get the right answer for CY2025 and CY2026 but the wrong answer for one cell in CY2024.

A parser for this page can be small. Two table layouts cover the entire content: the monthly release table with a 5-column header `| Servicing option | Update type | Availability date | Build | KB article |` and the hotpatch calendar with a 6-column header `| Month | Update type | Type | Availability date | Build | KB article |`. A 300-line standard-library Python parser is enough to extract both into JSON; the parser should validate header text exactly and refuse to continue if Microsoft renames a column, so that any structural drift triggers a human review. Implementations should additionally persist the retrieved commit ID, the retrieval timestamp, and the raw markdown SHA-256 alongside the parsed JSON, so that upstream structural drift is detectable and parsing remains reproducible against a known input.

### 2.2 .NET Framework cumulative update release notes

The companion surface for .NET Framework cumulative updates is the release-notes index at `learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes`. The same `?accept=text/markdown` switch works here as well. Each monthly page (e.g., `release-notes/2026/04-14-april-cumulative-update`) returns Markdown with a "## Summary tables" section. The table layout is consistent month over month:

| Row type | Column 1 | Column 2 |
|---|---|---|
| OS row | Bold OS name | Optional bold "umbrella" KB |
| Per-runtime row | Plain ".NET Framework `<versions>`" | `[KB######](url)` link |

For a representative month (2026-04), the per-OS row count is:

| OS | OS title in upstream | Umbrella KB | Per-runtime rows |
|---|---|---|:-:|
| Server 2025 | Microsoft server operating system, version 24H2 | (none) | 1 |
| Server 23H2 | Microsoft server operating system, version 23H2 | (none) | 1 |
| Server 2022 | Windows Server 2022 | present | 2 |
| Server 2019 | Windows 10 1809 and Windows Server 2019 | present | 2 |
| Server 2016 | Windows 10 1607 and Windows Server 2016 | (none) | **2** |
| Server 2012 R2 | Windows Server 2012 R2 | present | 3 (out of scope for the LTSC ISO use case) |

The Server 2016 row count of **2** is worth flagging. A Catalog-scrape implementation that uses the "umbrella KB title contains 'for Microsoft .NET Framework'" heuristic will see **only one** .NET CU KB for Server 2016 — the .NET 4.8 sibling — because the .NET 3.5 / 4.6.2 / 4.7.x sibling is published under a different umbrella title that the heuristic does not match. The release-notes page exposes both rows directly and is therefore the authoritative source. Server 2016 images that boot with .NET 4.8 enabled will not visibly miss the sibling, but images that retain 4.7.x will.

The .NET release-notes pages are also GitHub-backed (`dotnet/docs` repo), so commit-pinning is symmetric with release-info.

### 2.3 The Microsoft Update Catalog

The Microsoft Update Catalog at `catalog.update.microsoft.com` is the only surface that publishes the actual `.msu` and `.cab` download URLs. It is what a practitioner must use to resolve a KB number into a downloadable artifact. The Catalog is HTML-rendered, JavaScript-driven, and notoriously hostile to scraping; the production-grade approach is to use it strictly as a URL resolver (given a KB, fetch the download) rather than as a discovery surface (given a month, find titled strings that look like LCUs).

The Catalog interaction has two well-documented gotchas:

**OS naming changed between Server 2019 and Server 2022.** Older OSes use the user-facing brand name in update titles: "Windows Server 2019", "Windows Server 2016". Starting with Server 2022, Microsoft switched to the "Microsoft server operating system, version `<NNHN>`" naming where `<NNHN>` is the codename version: `21H2` for Server 2022 and `24H2` for Server 2025. A Catalog query for "Windows Server 2025 2026-04" returns nothing useful; a query for "Microsoft server operating system version 24H2 2026-04" returns the LCU and its dependencies. Any title-string heuristic must maintain both naming conventions and dispatch by OS version.

**Server 2025 LCUs currently resolve to a 2-file download set.** Every Server 2025 LCU resolution returns *two* download URLs: the LCU itself plus a fixed KB (currently `KB5043080`) that is the Servicing Stack baseline. This is the same Servicing Stack package every time, regardless of which LCU month is requested. Operationally, this strongly suggests that Server 2025 has no standalone SSU — Microsoft serves the SSU dependency alongside every LCU as a two-file bundle through the Catalog's `DownloadDialog.aspx`. A pipeline that downloads only the "LCU" URL and ignores the second will produce a WIM that fails to apply the LCU with `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED`. The correct pattern is: download both `.msu` files and let `Add-WindowsPackage` figure out the dependency order — it handles SSU ordering automatically. The observed two-file LCU+SSU behavior for Server 2025 should be treated as current Catalog behavior rather than a formal Microsoft servicing guarantee.

When a release-info KB can be turned directly into download URLs via the Catalog (KB-only input, no title-string heuristics), the success rate across a representative 8-sample test is 8/8. The Catalog is therefore a viable URL resolver, but a poor discovery surface. The architectural lesson, derived from extensive trial-and-error, is: **release-info / .NET release-notes is the discoverer; the Catalog is the resolver**. This minimises the title-string heuristic surface and the brittleness it introduces.

### 2.4 The wsusscn2.cab offline servicing database

For any question of the form "does update KB-A require KB-B to be installed first?" the most authoritative offline metadata source is the **Windows Update Standalone Scan** database (`wsusscn2.cab`), distributed as a single multi-gigabyte CAB file at `https://catalog.s.download.windowsupdate.com/d/msdownload/update/v3/static/trusted/.../wsusscn2.cab`. This file is published roughly twice a month, and a fresh download is required to see updates released since the last publication.

`wsusscn2.cab` is a nested CAB with the following high-level structure:

```
wsusscn2.cab
├── (75-ish top-level files)
├── package.cab
│   └── package.xml          ← "Master XML" — global dependency graph
└── packageN.cab               (one per update bundle, N = 1, 2, 3 ...)
    ├── update.mum
    ├── update.cat
    └── (per-update detail XML)
```

For offline dependency analysis, the Master XML (`package.xml`, ~108 MB extracted) is typically the most useful artifact in the CAB. It records, for each update revision in the Windows Update universe:

- `<Categories>` — the OS family GUID (Product) and the Classification GUID
- `<Prerequisites>` — flat list of UpdateId GUIDs that must be present before this update can apply
- `<SupersededBy>` — reverse list of `<Revision Id>` entries (14,000+ in a recent snapshot); helps detect "is this LCU already superseded?"
- `<PayloadFiles>` — `<File Id="<digest>">` references to the actual payload files (on leaf updates)
- `<FileLocation>` — `Id="<digest>" Url="...">` entries that resolve a payload digest to a download URL (a KB-number regex can be applied to the URL)
- `<BundledBy>` — `<Revision Id>` parent links; used to detect Combined LCU+SSU packages and to roll a leaf's payload up to its bundle

> **Empirical correction (2026-05-12 live-cab verification).** The Master
> XML carries **no** `<KBArticleID>` element — the KB number is *not* in
> package.xml at all. KB numbers live only in the per-package CAB metadata
> and the Microsoft Update Catalog (see the table below). Updates in the
> Master XML are therefore identified by `UpdateId` / `RevisionId`, and a
> KB number can only be *inferred* from the `kb(\d+)` token that sometimes
> appears in a `<FileLocation>` URL.

The Master XML and the individual `packageN.cab` fragments record **overlapping dependency metadata from different perspectives** — they are not semantically equivalent. The Master XML is a flattened, repository-wide summary; each `packageN.cab` preserves richer per-update applicability semantics:

| Information | Master XML | Per-package CAB |
|:---|:-:|:-:|
| `<Prerequisites>` | ✓ flat GUID list | ✓ full `<AtLeastOne>` decision trees |
| `<SupersededUpdates>` (forward) | ✗ | ✓ |
| `<SupersededBy>` (reverse) | ✓ (14,059 in 2026-05 snapshot) | ✗ |
| `<BundledUpdates>` (children) | ✗ | ✓ |
| `<BundledBy>` (parents) | ✓ | ✗ |
| `<PayloadFiles>` & `<FileLocations>` | ✓ | ✗ |
| `<KBArticleID>` element | ✗ | ✓ (under Metadata) |
| `<Categories>` (OS family GUID) | ✓ | ✗ |
| `<ApplicabilityRules>` | ✗ | ✓ |

For straightforward prerequisite discovery (e.g. "what does KB5087537 depend on?"), the Master XML is usually sufficient. For full applicability evaluation and branch-resolution logic (e.g. "which dependency-or-bundle decision tree branch matches this OS revision?"), the per-package CAB metadata — or, more authoritatively, Windows Update Agent applicability evaluation — may still be required.

Parsing the Master XML deserves attention to its scale. A representative timing on commodity hardware:

| Operation | Time | Memory peak |
|---|---:|---:|
| 7-Zip: `wsusscn2.cab` → 75 top-level files | 4.3 s | (low) |
| 7-Zip: `package.cab` → `package.xml` (108 MB) | < 1 s | — |
| `XmlDocument.Load` of `package.xml` | 4.2 s | +536 MB |
| Master XML string-search for 10 tags | 1.9 s | +113 MB |
| Per-package CAB scan (`packageN.cab` with 12,500 inner files) | 6.7 s extract + 127.9 s scan | < 50 MB |
| Hypothetical full per-package scan (all 75 CABs) | ≈ 2.5 hours | 15–20 GB disk peak |

The full per-package scan is impractical for routine refresh. A streaming `XmlReader` parser of the Master XML alone is the practical compromise: tens of seconds to extract every `<Prerequisites>`, `<SupersededBy>`, `<BundledBy>`, `<PayloadFiles>`, and `<FileLocation>`, producing a small JSON dependency database (~0.2 MB at the in-scope-bundle granularity used by this project) that can answer most pre-flight questions. A full offline WUA applicability evaluation is significantly slower than direct Master XML parsing — this is expected, because WUA evaluates full applicability rules, supersedence chains, and component state rather than performing direct metadata extraction — and is therefore better suited for validation workflows than for discovery workflows, which is the reason this pipeline uses Master XML parsing for discovery and reserves WUA for final applicability validation.

> **Note on support status.** Direct parsing of `package.xml` is an implementation technique based on observed metadata structure, not a Microsoft-supported API contract. The schema can change without notice. Final applicability and installability decisions should still be validated through the Windows Update Agent servicing logic (an offline WUA scan against the mounted image), which is the authoritative applicability evaluator. Despite the unsupported nature of the schema, the Master XML remains operationally valuable because it exposes dependency relationships in a repository-wide form that is dramatically faster to query than a full offline WUA applicability scan — which is why it is used for discovery while WUA is reserved for final validation. Despite its complexity, `wsusscn2.cab` remains uniquely valuable because it is the only broadly accessible offline metadata corpus that exposes prerequisite and supersedence relationships across the Windows servicing ecosystem at repository scale. That said, no compatibility guarantee should be assumed across future wsusscn2 schema revisions.

**Design philosophy.** The guiding principle throughout this workflow is to use reverse-engineered metadata for discovery and acceleration, but to defer final applicability and installability decisions to Microsoft's own servicing logic (WUA) wherever possible. Unsupported metadata is therefore treated as advisory rather than authoritative. The pipeline intentionally adopts a fail-closed design philosophy for unsupported or structurally ambiguous metadata: a parser that encounters unexpected structure aborts and requests human review rather than guessing, missing prerequisites stop the pipeline, and signature ambiguity is treated as failure rather than as a benign edge case. Any schema drift is treated as a compatibility event requiring human review, not a parsing edge case to absorb silently.

#### 2.4.1 The Category hierarchy embedded in package.xml

§2.4 introduced the main Master XML elements (`<Update>`, `<Prerequisites>`, `<SupersededBy>`, `<FileLocation>`). One more important observation: **the WSUS Product category hierarchy itself is implicitly embedded in the Master XML as `<Update>` elements**.

WSUS Categories (Company, ProductFamily, Product, UpdateClassification) appear in regular Updates as GUID references inside the `<Categories>` block, but those same GUID values **also appear as `UpdateId` of standalone `<Update>` elements** in package.xml. In other words, each Category is itself recorded as an "Update that represents a Category".

Identifying attributes of a Category Update:

| Attribute | Value | Meaning |
|:---|:---|:---|
| `DeploymentAction` | `"Evaluate"` | This entry is for evaluation, not for application |
| `IsSoftware` | `"false"` | This entry is not a software (real payload) package |
| `<Title>` / `<Description>` | (absent) | Category Updates in Master XML carry no human-readable property |
| `<Prerequisites><UpdateId>` | GUID of parent Category | Back-link that lets you reconstruct the hierarchy |

Concrete example — the Category Update for Windows Server 2016:

```xml
<Update CreationDate="2017-05-31T01:22:24Z"
        DefaultLanguage="en"
        UpdateId="569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5"
        RevisionNumber="204"
        RevisionId="21923899"
        DeploymentAction="Evaluate"
        IsSoftware="false">
  <Prerequisites>
    <UpdateId Id="6964aab4-c5b5-43bd-a17d-ffb4346a8e1d" />
  </Prerequisites>
</Update>
```

`UpdateId="569e8e8f-..."` is the GUID of the "Windows Server 2016" Product, and `Prerequisites/UpdateId Id="6964aab4-..."` is the GUID of the parent ProductFamily "Windows".

Counts observed in the wsusscn2 fetched on 2026-05-12:

| Category | Count |
|:---|---:|
| All `<Update>` | 136,102 |
| Category Updates (`DeploymentAction="Evaluate"` AND `IsSoftware="false"`) | 4,199 |
| Categories directly under Windows ProductFamily (`6964aab4-...`) | 154 |

Because Master XML carries no Title/Description, **the display name of a Category cannot be obtained from package.xml alone**. This is consistent with the Microsoft-prose exclusion rule discussed in §B.19.8. To map names to GUIDs you need an external reference (WSUS official documentation, adjacent OSS such as kbupdate-library or OSDBuilder, or `Get-WsusProduct -TitleIncludes` against a live WSUS server). For automated processing like the scope filter, however, **the GUID alone is sufficient and name resolution is unnecessary**.

The concrete technique for identifying Server LTSC Product GUIDs via Category-hierarchy reverse-lookup, and the finalised GUID inventory, are covered in §5.7 and §6.4.

### 2.5 CAB extraction methods compared

A practical note that has cost real time in the original investigation: the choice of CAB extraction tool matters.

| Method | Verdict | Notes |
|---|---|---|
| `expand.exe -F:` | **Avoid for `wsusscn2.cab`** | Self-overwrite bug when output directory overlaps any path that exists inside the CAB; throws `ERROR_FILE_EXISTS` mid-extraction even when `/Y` is passed |
| `Shell.Application` COM | Workable fallback | Slower than 7-Zip; non-deterministic file-by-file timing; sometimes hangs on antivirus interaction |
| `7-Zip` (CLI or library) | **Recommended** | Fast (sub-5-second for top-level), exit codes 0/1/≥2 (ok/warn/fatal) are clean to interpret, deterministic |

The cleanest pattern is: `7za x -y -bd -bso0 wsusscn2.cab` into a fresh staging directory, then walk the produced tree.

---

## 3. PCA2023 Secure Boot Migration

The 2024 Patch Tuesday cycle marks the most disruptive Secure Boot change since the introduction of Secure Boot itself. Microsoft is rotating the Production Certificate Authority used to sign Windows boot binaries from **PCA2011** (`Microsoft Windows Production PCA 2011`, used since Windows 8) to **PCA2023** (`Windows UEFI CA 2023`). For an ISO-building practitioner, this is not a "the LCU updates a registry key" change; it is a "the boot manager binary on the install medium itself must be re-signed" change. This matters because Secure Boot trust decisions occur at firmware time, not during Authenticode validation: tooling that operates only on the ISO can confirm the signer chain, but it cannot confirm what the target firmware will accept.

### 3.1 What PCA2023 is and what it replaces

Every signed Windows boot binary (`bootmgfw.efi`, `bootmgr.efi`, the OS loader, etc.) carries an Authenticode signature that traces back through a certificate chain to one of Microsoft's well-known root authorities. The relevant chain for boot binaries has been:

- **PCA2011 chain (legacy)**: leaf → `Microsoft Windows Production PCA 2011` → `Microsoft Root Certificate Authority 2010`
- **PCA2023 trust chain (new)**: leaf → `Windows UEFI CA 2023` → `Microsoft Root Certificate Authority 2010` (or 2023 root, depending on the platform's trust anchors)

The shift is being rolled out in two stages on real hardware:

(For readers less familiar with Secure Boot internals: DB contains allowed signing authorities, while DBX contains explicitly revoked signatures or authorities.)

1. **Stage 1 (2024-2026, current)**: Microsoft ships boot binaries signed under PCA2023, but firmware updates (delivered via Windows Update or vendor-specific channels) provision the PCA2023 certificate into the platform's DB (allowed signatures) on a rolling basis. PCA2011 remains in DB. Both chains are accepted.
2. **Stage 2 (announced for late 2026 or beyond)**: PCA2011 is moved from DB to DBX (revoked signatures) on platforms that have received the firmware update. At that point, an installation medium whose boot manager is signed only under PCA2011 will fail to boot on updated platforms.

A pipeline that wants to produce forward-compatible installation media (media intended to remain bootable after PCA2011 retirement) must ship boot binaries that carry the PCA2023 trust chain, even if PCA2011 is still accepted today. Microsoft's reference for how to do this is the `Make2023BootableMedia.ps1` script (current version at the time of writing: v1.4, dated 2026-03-13), distributed via Microsoft Support article KB5053484.

### 3.2 The staging directories: EFI_EX, Fonts_EX, DVD_EX

The mechanism Microsoft chose for the PCA2023 rollout is **dual-staging within the install.wim**. Alongside the familiar `\Windows\Boot\EFI\`, `\Windows\Boot\Fonts\`, and `\Windows\Boot\DVD\` directories, an updated install.wim carries `EFI_EX\`, `Fonts_EX\`, and `DVD_EX\` siblings. The `_EX` directories contain the same boot binaries (and font and DVD-boot resources) but signed under PCA2023.

For an ISO build, the role of the `_EX` directories is:

- **Build time**: the `Make2023BootableMedia.ps1` reference logic copies the `_EX` siblings from inside the mounted install.wim into the output media's root (replacing or supplementing the existing `\boot\` and `\efi\` directories at the ISO root level)
- **Runtime**: a Secure Boot platform that has been provisioned with PCA2023 trusts the resulting media

### 3.3 install.wim shape per Server version

Direct inspection of the install.wim of an Evaluation ISO for each Server version reveals a critical asymmetry that must be planned for:

| OS | EFI present | EFI_EX present | Total `*.efi` in `\Windows\Boot\` | Mechanism |
|---|:-:|:-:|:-:|---|
| Server 2016 EVAL ja-jp | ✓ | ✗ | 3 | `EFI_EX` must be **synthesised** during build by applying a recent LCU that adds the `_EX` binaries via WinSxS |
| Server 2019 EVAL ja-jp | ✓ | ✗ | 3 | Same as 2016 |
| Server 2022 EVAL ja-jp | ✓ | ✗ | 3 | Same as 2016 |
| Server 2025 EVAL ja-jp | ✓ | ✓ | **6** | `EFI_EX` **ships in install.wim** at GA; no synthesis needed |

For Server 2016 / 2019 / 2022, the `EnableInstallWimUpdate=true` workflow (apply LCU into install.wim, then extract `_EX` from the patched WIM into output media) is required. For Server 2025, EFI_EX synthesis is **not** required for PCA2023 boot-binary extraction because EFI_EX already exists in the install.wim. However, install.wim servicing (applying the LCU) is still required for patch-level compliance — only the `_EX`-synthesis step is skippable, not the patching step itself.

The 2025 install.wim has one additional file in EFI: **`SecureBootRecovery.efi`** (PCA2011-signed). Servers 2016 / 2019 / 2022 don't have it. The file is related to Secure Boot recovery procedures and its presence on 2025 is informational only — the file is not relevant to the build-time `_EX` synthesis question.

### 3.4 Authenticode chain verification: the Get-AuthenticodeSignature pitfall

When the PowerShell cmdlet `Get-AuthenticodeSignature` is run against an EFI binary, the returned object exposes a `SignerCertificate` property and the conventional thinking is that this property's `Issuer` field tells you which CA signed the binary. **This is misleading in a subtle but important way.**

The `Issuer` of the `SignerCertificate` is the **immediate signer** in the chain — i.e., it returns the leaf's parent. But the question that matters for the PCA2023 migration is not "who is the immediate signer of the leaf" — it is "which certificate authority is the trust anchor of the certificate chain that the firmware will validate against DB / DBX". To answer that correctly, the chain must be rebuilt with `X509Chain.Build()` and traversed. This matters because the failure mode appears late: a binary that looks correctly signed by its immediate issuer can still fail to boot on a firmware that only trusts a different trust anchor.

A concrete example, observed on Server 2025's `EFI_EX\bootmgfw_EX.efi`:

```
Status         : Valid
Signer Subject : CN=Microsoft Windows, O=Microsoft Corporation, ...
Signer Issuer  : CN=Windows UEFI CA 2023            ← from Get-AuthenticodeSignature
Cert Thumbprint: (some thumbprint)

Chain (via X509Chain.Build()):
  CN=Microsoft Windows
   └─ CN=Windows UEFI CA 2023
       └─ CN=Microsoft Root Certificate Authority 2010

=> PCA 2023 in chain: True
   PCA 2011 in chain: False
```

For `\Windows\Boot\EFI\bootmgfw.efi` on the same Server 2025 install.wim, the same code returns:

```
Signer Issuer  : CN=Microsoft Windows Production PCA 2011
=> PCA 2011 in chain: True
   PCA 2023 in chain: False
```

A natural first-glance reading is that the PCA2011 file is "broken" and the PCA2023 file is "the new one". The full chain inspection confirms this. But the converse mistake — assuming a binary is PCA2011 because the immediate signer's *display name* contains the string "PCA 2011" without verifying the chain — has appeared in real investigations. The defensive coding pattern is: never trust the `SignerCertificate.Issuer` display string for chain-authority detection; always rebuild the chain and check for the expected root or intermediate by thumbprint.

### 3.5 Dual-sign vs single-sign and signtool /ds verification

A separate question, distinct from the chain-authority one, is whether a single binary carries multiple Authenticode signatures (a so-called "dual-signed" binary). This is a real Microsoft pattern in other contexts (driver packages routinely carry both SHA-1 and SHA-256 signatures), so it is reasonable to wonder whether boot binaries might dual-sign PCA2011 + PCA2023 during the transition.

`Get-AuthenticodeSignature` returns only the **primary** signature. To detect a secondary signature, the canonical tool is `signtool.exe verify /pa /all /v <file>`, where `/all` enumerates all embedded signatures and `/v` produces verbose output. To probe a specific signature index, `signtool verify /ds 0`, `/ds 1`, `/ds 2`, etc. retrieves each one explicitly.

Empirically, neither `\Windows\Boot\EFI\bootmgfw.efi` nor `\Windows\Boot\EFI_EX\bootmgfw_EX.efi` on Server 2025 carries more than one signature. The pattern is single-sign: either PCA2011 (for `EFI\bootmgfw.efi`) or PCA2023 (for `EFI_EX\bootmgfw_EX.efi`), never both on the same file. Whether this remains true on future Server versions is unknown.

A practical hazard: when running signtool in PowerShell with `$ErrorActionPreference = 'Stop'`, a `signtool verify /ds 1` call against a file that has only one signature will exit with code 1 and "No signature found" on stderr, which PowerShell treats as a terminating error. The script aborts mid-loop. The fix is to wrap signtool in a helper that temporarily switches `ErrorActionPreference` to `'Continue'`, captures the exit code and output explicitly, and returns a custom object — never let signtool's normal-case exit-code-1 behaviour propagate as a terminating error.

### 3.6 File hash vs Authenticode hash

When comparing `\Windows\Boot\EFI\bootmgfw.efi` and `\Windows\Boot\EFI_EX\bootmgfw_EX.efi` on Server 2025, a small but conceptually important detail emerges:

```
\Windows\Boot\EFI\bootmgfw.efi       : SHA256 47C12C1F26...    (full file)
\Windows\Boot\EFI_EX\bootmgfw_EX.efi : SHA256 47C12C1F26...    (full file)
```

The two binaries are byte-identical in PE image content excluding the Authenticode signature region (i.e. identical in Authenticode-measured PE content). But the Authenticode signatures embedded in the two files differ:

```
\Windows\Boot\EFI\bootmgfw.efi       : signed under PCA2011
\Windows\Boot\EFI_EX\bootmgfw_EX.efi : signed under PCA2023
```

This distinction matters operationally. Authenticode hashing is defined to **exclude** the bytes of the Authenticode signature itself (specifically, the `IMAGE_DIRECTORY_ENTRY_SECURITY` region and the checksum field in the PE header). What signtool reports as "Hash of file (sha256)" is the *Authenticode hash*, not the *file hash*. Both binaries have the same Authenticode hash (their PE body is identical) but different file hashes if you measure with `Get-FileHash` directly — because the signature blobs at the end of each file differ.

Microsoft's approach is therefore: take the existing `bootmgfw.efi` PE body, re-sign it with PCA2023, save the result as `bootmgfw_EX.efi`. The PE code is unchanged; only the signature is new. This is a reasonable interpretation of the goal — the executable PE sections appear unchanged, with the observable difference limited to the Authenticode signature chain; only the trust anchor changes.

The same is not always true of the other `_EX` files. Server 2025's `bootmgr_EX.efi` is byte-for-byte identical to `bootmgr.efi` *including* its signature — it carries the PCA2011 signature, despite the `_EX` suffix. This was observed in inspected Server 2025 media and is consistent with a comment in Microsoft's `Make2023BootableMedia.ps1` v1.4 indicating bootmgr_EX is a PCA2011-signed copy. Treat this as implementation-observed behavior unless Microsoft publishes a formal servicing specification; whether it is a transitional artifact or a permanent design choice is not yet documented publicly.

### 3.7 Verifying a built ISO's PCA2023 readiness

Once an ISO has been built with the `_EX` substitution applied to the boot root, the build-pipeline author has a verification problem: how to confirm, without a hardware boot test, that the output ISO will pass on a Secure Boot environment with PCA2011 removed from DB.

Microsoft's `Make2023BootableMedia.ps1` v1.4 itself does **not** perform any verification — it is purely a file-copy operation. The script references no Authenticode-related code. The output verification is, by Microsoft's design, the caller's responsibility.

A workable post-build verification approach is the "file presence + signer chain" pattern: for each of a small fixed set of boot binaries that the spec says must carry the PCA2023 trust chain, verify both that the file exists at the expected path on the output ISO and that its Authenticode chain includes a PCA2023 intermediate. Server 2025's full set is five targets:

| Target on output media root | Expected chain |
|---|---|
| `\boot\bootmgr.efi` | PCA2011 (intentional, per `Make2023BootableMedia.ps1` comment) |
| `\boot\bootmgr` | PCA2011 (BIOS boot file, unchanged) |
| `\efi\boot\bootx64.efi` | **PCA2023** |
| `\sources\boot.wim` contains updated `bootmgfw.efi` | **PCA2023** |
| `\setup.exe` | PCA2011 (signed installer; not a boot binary; PCA2023 not required) |

A verification function that walks these targets, attempts `Get-AuthenticodeSignature` followed by `X509Chain.Build()` for each, and aggregates to a four-state outcome (`Pass`, `PassWithNotes`, `Warning`, `Fail`) gives a deterministic pre-deployment signal. The function MUST attach a SCOPE clarifier to every report — something like:

> SCOPE: file presence + signer-chain only. Actual boot behaviour on firmware with PCA2011 revoked from DBX is NOT verified here. Manual boot test on hardware or a Hyper-V Gen2 VM with a PCA2023 Secure Boot template is required before production deployment.

From a pipeline-design perspective, the SCOPE clarifier sets correct operator expectations: a `Pass` from the verification function is necessary but not sufficient. The only thing it actually proves is that the file-system structure and Authenticode chain are correct. Whether the firmware on the deployment target actually accepts the chain depends on whether that target has received Microsoft's PCA2023 DB provisioning update, which is out of scope for any tooling that operates only on the ISO.

Making the verification's reach explicit helps set operator expectations. Each layer of validation proves a strictly different thing:

| Verification | What it proves | What it does NOT prove |
|:---|:---|:---|
| Authenticode chain inspection | The file carries the expected signer chain (e.g. terminates at PCA2023) | That any firmware will accept it |
| File-presence check | The media layout is structurally correct (`_EX` binaries present at the expected paths) | That the binaries are correctly signed |
| Hyper-V Gen2 boot test | The boot manager is accepted by Hyper-V's virtual firmware | That physical OEM firmware will accept it (DB/DBX state may differ) |
| Physical hardware boot test | The specific OEM firmware's trust DB/DBX state is compatible | That a *different* OEM/firmware generation is compatible |

No single row is sufficient on its own; the rows are cumulative, and only the bottom row exercises the real DB/DBX trust decision on a representative target.

---

## 4. install.wim Structure: A Cross-Version Survey

The previous section discussed `EFI_EX` and friends in the context of PCA2023. This section enumerates the structural facts about `install.wim` itself across Server versions, which any builder must accommodate.

### 4.1 Top-level `\Windows\Boot\` layout

Every Windows Server install.wim contains a `\Windows\Boot\` tree. The directories observed across the four LTSC versions in scope (using each version's English EVAL Index 4 as the reference):

```
\Windows\Boot\
├── DVD\         (always present — DVD boot resources)
├── EFI\         (always present — PCA2011-signed EFI boot binaries)
├── Fonts\       (always present — boot-time font files)
├── Misc\        (always present, one file)
├── PCAT\        (always present — BIOS boot resources)
└── Resources\   (always present)
```

For Server 2025 only, three additional sibling directories appear:

```
├── DVD_EX\      (only on Server 2025 install.wim)
├── EFI_EX\      (only on Server 2025 install.wim)
└── Fonts_EX\    (only on Server 2025 install.wim)
```

The `EFI_EX` directory on Server 2025 contains 72 files in total when counted with `Get-ChildItem -Recurse -File`. Of those, 2 are `*.efi` (`bootmgfw_EX.efi`, `bootmgr_EX.efi`) and 70 are `.mui` localisation resources and language subdirectory files. A bare directory listing reports `EFI_EX (72 files)` while a `*.efi`-filtered listing reports `2 files` — both are correct, they count different things.

### 4.2 Per-version `*.efi` inventory

A complete recursive `*.efi` enumeration under `\Windows\Boot\` for each Server version's install.wim:

| OS | Total `*.efi` | Files |
|---|:-:|---|
| Server 2016 | 3 | `EFI\bootmgfw.efi`, `EFI\bootmgr.efi`, `EFI\memtest.efi` |
| Server 2019 | 3 | same 3 files |
| Server 2022 | 3 | same 3 files |
| Server 2025 | 6 | adds `EFI\SecureBootRecovery.efi`, `EFI_EX\bootmgfw_EX.efi`, `EFI_EX\bootmgr_EX.efi` |

All files in this list have valid Authenticode signatures. The trust chain of each — specifically its trust-anchor path, the root/intermediate hierarchy the chain terminates at, as distinct from the immediate signer certificate — is the relevant question for PCA2023 work (section 3.7); the file-presence question is answered by the table above.

### 4.3 Indexing and edition coverage

`install.wim` is typically a multi-index WIM (`dism /Get-ImageInfo /WimFile:install.wim` enumerates them). The conventional layout is:

| Index | Edition |
|:-:|---|
| 1 | Standard (Server Core) |
| 2 | Standard (Desktop Experience) |
| 3 | Datacenter (Server Core) |
| 4 | Datacenter (Desktop Experience) |

Some EVAL ISOs add an "Evaluation" suffix to the edition name (e.g., `Windows Server 2016 Standard Evaluation (Desktop Experience)`). The boot binary structure is the same across all indexes within a single install.wim, so most analysis can be done by mounting only one index — by convention Index 4, which is the most feature-complete edition.

### 4.4 SecureBootRecovery.efi: a Server 2025 novelty

`SecureBootRecovery.efi` first appears in Server 2025's install.wim, PCA2011-signed. It does not appear in Server 2016 / 2019 / 2022. Its role is related to Secure Boot recovery procedures (presumably re-establishing trust when a firmware update has revoked an active signer), but the canonical documentation of its runtime behaviour was not located during the original investigation. Treat it as a Server-2025-only file that should be carried through any boot-binary copy operation; do not attempt to substitute or re-sign it without explicit Microsoft guidance. No conclusion is drawn here about whether `SecureBootRecovery.efi` participates in the normal boot flow during a standard installation.

---

## 5. Servicing Stack Dependencies

The single most consequential class of failure for a slipstreaming pipeline is **Servicing Stack mismatch**. Knowing how to detect and resolve it before applying the LCU is, in practical terms, the difference between a 5-minute build and an afternoon of forensic log-reading.

### 5.1 What a Servicing Stack Update is

The **Servicing Stack** is the component of Windows responsible for installing other components. It is itself an installable component. Microsoft ships a Servicing Stack Update (SSU) periodically to fix bugs in the servicer or to enable the servicer to understand newer package formats. An LCU produced after a given date may require an SSU that postdates the install.wim's current servicer.

When the requirement is not met, `Add-WindowsPackage` (or DISM directly) returns:

```
HRESULT 0x800f0823 = CBS_E_NEW_SERVICING_STACK_REQUIRED
```

The associated log line in `addpkg.log` (or `dism.log`) reads:

```
Package "Package_for_RollupFix~31bf3856ad364e35~amd64~~14393.9140.1.19"
  requires Servicing Stack v10.0.14393.7692
  but current Servicing Stack is v10.0.14393.693.
```

The required and current versions are explicit, which simplifies the resolution: identify the SSU that bumps the servicer to ≥ 14393.7692 and apply it first.

### 5.2 Standalone LCU vs Combined LCU+SSU

Microsoft has, over the years, oscillated between two distribution shapes:

- **Standalone LCU**: the LCU MSU contains only the LCU; the SSU is a separate MSU published in parallel with its own KB number. The pipeline must apply both, SSU first. Server 2016, Server 2019, Server 2022 (mostly) follow this pattern.
- **Combined LCU+SSU**: a single MSU contains both the LCU and the SSU as bundled packages. `Add-WindowsPackage` handles the ordering automatically. The pipeline only needs to download one MSU. Server 2025 follows this pattern (the SSU is bundled with every LCU as a two-file Catalog download — see section 2.3).

A reliable implementation-level indicator of a Combined MSU is the presence of an `update.ses` file alongside `update.mum` and the `.cab` payload. A standalone LCU lacks `update.ses`. A pipeline that looks inside the MSU (via `expand.exe -F:* msu_file destination`) can detect this:

```
Combined:    update.mum, update.ses, Windows10.0-KBXXXXXXX-x64.CAB
Standalone:  update.mum,             Windows10.0-KBXXXXXXX-x64.CAB
```

Detection of the bundle type at config-load time avoids the SSU-required failure at WIM-mount time, where the failure is expensive (the WIM mount must be undone and restarted with the SSU applied first). Operationally, this distinction determines whether the build fails cheaply before WIM servicing begins or expensively after it is already under way.

### 5.3 The SSU-LCU pairing problem: how the dependency is actually expressed

Outside the Combined-MSU world, the operator needs to know, for any given LCU, which SSU pairs with it. Microsoft publishes this in plain prose on the LCU's KB page (the "Improvements" section often opens with "This update introduces the following dependency: KB`<NNNNNNN>` Servicing Stack Update"). Third-party sites routinely repeat the pairing.

For automation, the natural instinct is to look in `wsusscn2.cab` for an LCU-to-SSU edge expressed as a KB-number prerequisite. **A 2026-05-12 reverse-engineering of a real `wsusscn2.cab` showed that no such edge exists, in either the Master XML or the per-package detail CABs.** This correction is important enough to state precisely, because an earlier draft of this section described the dependency the wrong way:

- The LCU's Master XML `<Prerequisites>` block holds **applicability / detectoid `UpdateId` GUIDs** (`DeploymentAction="Evaluate"` nodes, plus the Product-category and Classification-category GUIDs). These are *evaluation* relationships ("is this update applicable to this machine?"), **not install-order dependencies**. They do not name the SSU. Empirically, when the in-scope updates' prerequisite edges are resolved against the in-scope set, they yield zero in-scope SSU KBs.
- There is therefore **no KB-prerequisite "closure" to compute** for the SSU dependency. A pipeline cannot answer "which SSU KB does this LCU require?" by walking `<Prerequisites>`, because the data is not there.

The dependency that actually causes `0x800f0823` is expressed instead as a **minimum servicing-stack version**, found in the LCU's per-package CBS metadata (`c/<RevisionId>` inside `packageNN.cab`):

```
<CbsPackageApplicabilityMetadata>
  ...
  <installerAssembly name="Microsoft-Windows-ServicingStack"
                     version="10.0.14393.7692" .../>   <-- minimum SS version
```

At install time, CBS compares the machine's current servicing-stack version against this `installerAssembly` version; if current is below required, it returns `CBS_E_NEW_SERVICING_STACK_REQUIRED` (`0x800f0823`). The dependency is therefore a **numeric version comparison**, not a KB match. The correct pre-flight check is: extract the LCU's required SS version from its per-package metadata, and verify that the SSU in the same patch set provides a servicing-stack version greater than or equal to that value.

A concrete example, from Server 2016 in 2026-05 (verified against the real cab):

```
LCU for Windows Server 2016, 2026-05 (KB5087537)
  leaf RevisionId 45255701 (one of three; x86/x64/edition variants)
  per-package metadata c/45255701:
    Package_for_RollupFix version="14393.9140.1.19"   <-- the LCU build
    installerAssembly Microsoft-Windows-ServicingStack
                      version="10.0.14393.7692"        <-- required SS floor

  The matching SSU KB5088064 (a separate update) raises the servicing
  stack to >= 14393.7692. The Master XML never states "5088064" as a KB
  element, and KB5087537's prerequisites never reference KB5088064.
```

So a pipeline that pre-loads its config from `wsusscn2.cab` derivative data can detect, at config-load time, that the Server 2016 LCU needs a servicing stack of at least `10.0.14393.7692`, and that the SSU the operator listed must provide a version greater than or equal to that. The human-readable SSU KB number itself is still only available heuristically (the `kb(\d+)` token in the SSU update's payload URL, or a Catalog cross-reference); but the *dependency decision* does not depend on knowing that KB number -- it depends on the version comparison. An operator who hand-edits a config without the right SSU gets the `0x800f0823` failure at WIM-apply time; the pre-flight version check turns that 20-minute failure into a 1-second one.

### 5.4 SSU model per Server version (verified against the 2026-05-12 cab)

A 2026-05-12 reverse-engineering exercise resolved the same monthly LCU for each OS across three consecutive months (2026-03/04/05) and read the per-package CBS metadata each time. The four OS fall into four structurally distinct families, and the family is **stable month-over-month**:

| OS | SSU family | Where the SS requirement lives | Value observed (2026-05) |
|---|---|---|---|
| Server 2016 | SSU fully separate | LCU `installerAssembly` carries the **real** minimum SS version | required SS = `10.0.14393.7692` (constant across all three months) |
| Server 2019 | SSU separate, plus an embedded reference | LCU `installerAssembly` (real value) **and** an embedded `Package_for_ServicingStack_<nnnn>` | required SS = `10.0.17763.2090`; embedded SSU `17763.8754` |
| Server 2022 | Combined (SSU folded into the LCU) | `installerAssembly` is the placeholder `6.0.0.0`; the real SS info is the embedded `Package_for_ServicingStack_<nnnn>` | embedded SSU `20348.5120` (advances every month) |
| Server 2025 | Checkpoint cumulative update (`.msu`) | leaf has **no** `CbsPackageApplicabilityMetadata`; the `.msu` payload bundles multiple KBs | payload = LCU KB5087539 + baseline KB5043080 + SafeOS DU KB5087588 |

Two practical consequences follow:

1. **Server 2016 and 2019 are the OSes where `0x800f0823` is a live risk**, because their SSU is a separate package the operator must apply first. Their `installerAssembly` version is the authoritative floor to check against. The value is a real build number (e.g. `10.0.14393.7692`), constant for a given LCU build.
2. **Server 2022 and 2025 carry the SSU inside the LCU.** Server 2022's `installerAssembly` reads `6.0.0.0` -- a nominal placeholder, *not* a real build number -- and the real servicing-stack build is only visible as the embedded `Package_for_ServicingStack_<nnnn>` sub-package (e.g. `5120` -> build `20348.5120.1.0`), which advances every month. Server 2025's checkpoint `.msu` is self-contained, so an external SSU pairing check is not meaningful for it.

The earlier "Server 2022 is mostly standalone; inspect `update.ses`" advice (previous draft) is superseded by this finding: in the 2026-03/04/05 cab the Server 2022 LCU was Combined every month, with the embedded `Package_for_ServicingStack_<nnnn>` present each time. The `update.ses` test from §5.2 remains a valid *runtime* indicator when inspecting an MSU on disk, but the cab metadata already tells the pipeline the SS build without opening the MSU. As always, treat this as observed behaviour over a three-month window, not a contractual guarantee; a pipeline should still read the per-package metadata each month rather than hard-coding a family per OS.

### 5.5 Dependency validation as a pre-flight gate (corrected model)

A useful design pattern, derived from a real-world iteration of this work, is to treat dependency validation as a **pre-flight gate** rather than a build-time discovery. The pipeline operates against a configuration that lists, for each OS, the patches to apply. Before any DISM mount, the pipeline validates the patch set against the `wsusscn2.cab`-derived dependency database.

The earlier draft of this section described the gate as a KB-prerequisite **closure** ("look up the LCU's prerequisites, verify every prerequisite KB is in the config"). §5.3 corrected the underlying model: there is no SSU KB-prerequisite to walk. The pre-flight gate is therefore re-stated as **three independent checks**, none of which is a KB closure:

1. **Presence** -- each KB the operator listed resolves to an in-scope update in Layer 2 (the LCU is actually present in the current cab for that OS). A KB that does not resolve is either superseded (see §5.9) or out of scope (see §5.8), and the gate reports which.
2. **Servicing-stack version comparison** -- for the SSU-separate OSes (2016/2019), read the LCU's required SS version from its per-package metadata (`installerAssembly`), and verify the SSU in the same patch set provides a servicing-stack version greater than or equal to that floor. This is the check that actually prevents `0x800f0823`.
3. **Supersession / identity** -- confirm the chosen LCU is the newest non-superseded one for that OS (via the `<SupersededBy>` chain), so the operator is not slipstreaming a stale build.

This shifts failure detection from "after 20+ minutes of WIM mount and copy work" to "1 second after config load". A 1-second failure can be diagnosed and fixed in the same operator session; a 20-minute failure usually means the operator has wandered off. Crucially, the gate consumes **static metadata only** -- it never mounts a WIM (SPEC B.19.13 hard rule).

### 5.6 Three-layer database design

Implementing the pre-flight gate above with `wsusscn2.cab` as the source of truth raises a Git-management question: where does the parsed dependency data live? A workable three-layer design:

- **Layer 1 — `config/<os>.json`**: human-authored, declares the KBs to apply this month
- **Layer 2 — `data/wsusscn2-database.json`**: the parsed Master XML dependency graph, Git-committed (2-5 MB), regenerated by a periodic `RefreshDependencyDatabase` action
- **Layer 3 — `workspace/cache/wsusscn2/`**: the raw extracted CAB, NOT Git-committed (extracted at refresh time, deleted afterward to save space)

The advantage of this layering is reproducibility: Git history of Layer 2 shows when each dependency was introduced upstream by Microsoft, which lets an operator audit "did this prerequisite already exist when I authored the config last month, or has Microsoft added a new dependency in the meantime?" The Layer 3 raw CAB has no archival value once Layer 2 is regenerated, so its presence outside Git is by design.

### 5.7 Product GUID inventory backing the scope filter

§5.5 and §5.6 designed the SSU-LCU/CU dependency validation pipeline. The first filtering stage of that pipeline (the scope filter) uses the `Categories.Product` GUID and `Categories.UpdateClassification` GUID as decision keys to **select only the Server LTSC family** from the ~136,000 `<Update>` entries in `wsusscn2.cab`'s Master XML.

This section records the **finalised GUID inventory** used by the scope filter. Because GUIDs are WSUS global identifiers that do not change over time, this approach avoids the brittleness of title-string heuristics (the fragility surface discussed in §6.2). GUID-based filtering survives display-name changes and localization differences, making it substantially more stable than title-string heuristics — this is one of the key architectural insights of the entire workflow.

**Update Classification GUIDs** (WSUS-official, 5 of the 12 are observed in real wsusscn2):

| Classification | GUID | Observed count | Mapping to this task |
|:---|:---|---:|:---|
| SecurityUpdates | `0FA1201D-4330-4FA8-8AE9-B877473B6441` | 19,361 | Primary classification for LCUs |
| UpdateRollups | `28BC880E-0592-4CBF-8F95-C79B17911D5F` | 1,421 | Primary classification for .NET CUs |
| ServicePacks | `68C5B0A3-D1A6-4553-AE49-01D3A7827828` | 341 | Contains SSUs |
| CriticalUpdates | `E6CF1350-C01B-414D-A61F-263D14D133B4` | 11 | Some critical patches |
| Updates | `CD5FFD1E-E932-4E3A-BF74-18BF0B1BBD83` | 1 | Contains Dynamic Updates |

Source: Microsoft Learn "WSUS Classification GUIDs" (`learn.microsoft.com/ja-jp/previous-versions/windows/desktop/ff357803`). Counts are from the wsusscn2.cab fetched on 2026-05-12.

**Server LTSC Product GUIDs** (the targets of the scope filter, 4 entries):

| Server version | WSUS Catalog display name | Product GUID | Evidence basis |
|:---|:---|:---|:---|
| Windows Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` | Microsoft-adjacent code (`ansible/ansible` Issue 60785 Categories dump, `dsccommunity/UpdateServicesDsc` Issue 65) + reverse-lookup from real wsusscn2 Category Updates |
| Windows Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` | WSUSOffline forum + real wsusscn2 Category Update created 2018-10-13 (matches GA timing) |
| Windows Server 2022 LTSC | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` | Real wsusscn2 Category Update created 2021-08-09 (right before LTSC GA); the observed payload URLs reference ndp481-related (.NET Framework 4.8.1) packages. The in-box runtime is not inferred solely from payload names |
| Windows Server 2025 LTSC | Microsoft server operating system-24H2 | `b256987d-4693-4c87-955d-dbb9341205eb` | **Corrected 2026-05** (was `ca006cfb-...`): the b256987d Category's newest SecurityUpdate bundle (2026-05-11) carries the current Server 2025 LCU **KB5087539** (build 26100.32860), but NOT the Windows 11 24H2 *client* LCU KB5089549, so it is server-specific. The old `ca006cfb-...` stalls at 2025-09-08 and never carries KB5087539 (see note below) |

Reference (not Server LTSC, so excluded from the scope filter):

| Name | Product GUID | Notes |
|:---|:---|:---|
| Microsoft Server Operating System-22H2 | `2c7888b6-f9e9-4ee9-87af-a77705193893` | Azure Stack HCI 22H2 family (SAC) |
| Microsoft Server Operating System-23H2 | `607efb8d-feed-48a0-930e-14d0cf2da71f` | Azure Stack HCI 23H2 family (SAC); payload URLs confirm build 25398 |

**Mapping SSU / LCU / .NET CU / Dynamic Update to Classification** (the Update type expression in SPEC §B.19.7). Note: the classification GUIDs themselves are Microsoft-defined identifiers, but the mapping below between update *categories* and classification *usage* is based on observed wsusscn2 metadata patterns and should be treated as heuristic rather than contractual:

- **SSU**: Classification = ServicePacks (`68C5B0A3-...`). On Windows 6.x and earlier, some SSUs were classified as `Updates`, but on Windows 10 / Server 2016 and later they are consistently under ServicePacks.
- **LCU**: Classification = SecurityUpdates (`0FA1201D-...`). The monthly Cumulative Update with security content.
- **.NET CU**: Classification = UpdateRollups (`28BC880E-...`) mainly, with a few in SecurityUpdates (when they carry security content). Cumulative Update for .NET Framework 3.5 / 4.7.x / 4.8 / 4.8.1.
- **Dynamic Update**: Classification = Updates (`CD5FFD1E-...`) or CriticalUpdates (`E6CF1350-...`). Setup DU and SafeOS DU. Publication cadence on LTSC OSes is sporadic (see §6.3).

**Deny-list: EOS / ESU Server OS Product GUIDs (explicit exclusion).** A 2026-05-12 investigation confirmed that end-of-support and ESU-only Server OS product categories are NOT removed from `wsusscn2.cab` when the OS leaves support; they persist with live, payload-bearing updates (including ESU monthly rollups) indefinitely. They must therefore be **actively excluded**, not assumed absent. These four GUIDs are recorded as a deny-list (cross-referenced with the WSUS Offline community product-GUID list and confirmed present in the real cab):

| Server version | Product GUID | Support state |
|:---|:---|:---|
| Windows Server 2008 | `ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf` | EOS (ESU ended) |
| Windows Server 2008 R2 | `fdfe8200-9d98-44ba-a12a-772282bf60ef` | EOS (ESU ended) |
| Windows Server 2012 | `a105a108-7c9b-4518-bbbe-73f0fe30012b` | ESU (through 2026-10) |
| Windows Server 2012 R2 | `d31bd4c3-d872-41c9-a2e7-231f372588cb` | ESU (through 2026-10) |

**Allow-overrides, not deny-overrides.** Some updates legitimately apply to *both* a deny-listed OS and an allow-listed OS -- the multi-OS Malicious Software Removal Tool bundle (KB890830) is the canonical example, carrying both the 2012 R2 GUID and the 2016/2019 GUIDs. In the real cab, 33 such "overlap" updates exist. The scope rule must therefore admit an update if it carries *any* allow-list GUID, even when it also carries a deny-list GUID; a deny-overrides rule would wrongly drop these valid in-scope updates. The deny-list's job is to exclude updates that carry **only** deny-listed GUIDs (the ESU-specific rollups such as KB5087471 / KB5063950 / KB5063906, which carry the 2012 / 2012 R2 GUID and nothing in the allow-list).

The canonical scope-filter rule (revised):

> An Update is admitted into scope if and only if:
> 1. it is a bundle, AND
> 2. `Categories.Product` matches at least one of the 4 allow-list Server LTSC Product GUIDs (allow-overrides: this holds even if a deny-list GUID is also present), AND
> 3. `Categories.UpdateClassification` matches one of the 5 Classification GUIDs above, AND
> 4. `CreationDate` is within the RecencyMonths window relative to the parser invocation date.
>
> The deny-list is defence-in-depth: an update carrying only deny-list GUIDs (no allow-list GUID) is excluded and may be surfaced as a warning so the operator can see that an ESU/EOS patch was detected and deliberately dropped.

Only Updates satisfying these conditions are emitted into the Layer 2 JSON. The `RecencyMonths` window is the parser's `-RecencyMonths` parameter: default 24, 36 settable, `-1` disables the clause entirely (see §5.9). For the wsusscn2 fetched on 2026-05-12 this reduces the ~136,000 Master XML entries to a Layer 2 of 138 in-scope bundles (155 distinct payload KBs), comfortably inside the 2-5 MB target.

### 5.8 EOS / ESU data persistence and the deny-list

The central EOS question for a long-lived pipeline is: *when an OS leaves support, does its data disappear from `wsusscn2.cab`?* The 2026-05-12 investigation answers it empirically by aggregating every Master XML update that carries each OS's Product GUID:

| OS | Support state | updates in cab | payload-bearing | distinct KB | newest payload CreationDate |
|:---|:---|---:|---:|---:|:---|
| Server 2008 | EOS (ESU ended) | 6577 | 4080 | 1078 | 2026-05-08 |
| Server 2008 R2 | EOS (ESU ended) | 3540 | 2227 | 1018 | 2026-05-08 |
| Server 2012 | ESU (to 2026-10) | 1659 | 979 | 803 | 2026-05-11 |
| Server 2012 R2 | ESU (to 2026-10) | 1498 | 830 | 806 | 2026-05-11 |
| Server 2016 | Mainstream ending soon | 284 | 132 | 119 | 2026-05-11 |
| Server 2019 | Supported | 213 | 118 | 102 | 2026-05-11 |
| Server 2022 | Supported | 184 | 98 | 95 | 2026-05-11 |
| Server 2025 | Supported | 63 | 31 | 47 | 2026-05-11 |

Three findings:

1. **EOS does not remove data.** Even fully-EOS Server 2008 / 2008 R2 retain over a thousand payload-bearing KBs, with a newest CreationDate only weeks before the cab snapshot. (These are largely Defender definition updates and the ESU-era security rollups still served to entitled customers.) Nothing is purged on EOS.
2. **Older OSes carry *more* data, not less.** Server 2008 has 6577 updates; Server 2025 has 63. The pre-cumulative servicing era left many years of individual monthly patches accumulated under the old GUIDs, whereas the cumulative-update OSes (2016+) have far fewer entries. This is why the RecencyMonths window matters as a data-volume control if a deny-listed OS were ever brought into scope.
3. **Server 2016's coming ESU transition is a non-event for retrieval.** Since the fully-EOS 2008/2008 R2 still persist with payloads under an unchanged GUID, Server 2016's GUID (`569e8e8f-...`) will keep resolving after its mainstream support ends and it moves to ESU. The OS does not get a new GUID on ESU transition; keeping `569e8e8f-...` on the allow-list keeps "the newest Server 2016 rollup" retrievable.

This is the rationale for treating EOS/ESU exclusion as a Product-GUID deny-list rather than relying on the data disappearing: the data never disappears, so the exclusion has to be explicit.

### 5.9 Recency window and fallback depth

The `RecencyMonths` clause (default 24) is a `CreationDate` window: a bundle whose `CreationDate` is older than `Now - RecencyMonths` is rejected; `-1` disables the clause. A 2026-05-12 robustness test traced 36 months of per-OS LCU KB numbers (collected from community Patch-Tuesday archives) against the current cab's in-scope set, asking "how far back can the search logic actually reach?":

| OS | Oldest in-scope LCU | Effective reach | Shape |
|:---|:---|:---|:---|
| Server 2022 | 2024-06 (KB5039227) | ~12-13 months | deepest |
| Server 2016 | 2024-11 (KB5046612) | ~7 months | moderate |
| Server 2025 | 2025-04 (KB5055523) | ~8 months (since 2024-11 GA) | full since GA |
| Server 2019 | 2025-08 (KB5063877) | ~3-4 months | shallowest |

The key insight is that the **effective reach is much shorter than the 24-month window**, and it varies by OS. The window is a `CreationDate` ceiling, but supersession shortens the practical depth: once a newer LCU supersedes an older one, the older one stops being a payload-bearing in-scope bundle. A "miss" when looking up an older month is therefore **supersession (a newer build exists), not missing data** -- and the pipeline should report it that way.

For the pipeline this yields a precise, implementable guarantee:

- The **newest** LCU per supported OS is always retrievable (the monthly cycle is fully deterministic).
- If a specific older month is requested and not in scope, fall back to the newest in-scope LCU for that OS, treating the miss as supersession.
- The fallback ceiling is the `RecencyMonths` setting (currently 24; 36 also supported), bounding how far the `CreationDate` window admits older builds. Beyond the window, even non-superseded old builds are excluded by design -- which is also what keeps a deny-listed EOS OS (with its thousands of historical KBs) from flooding the scope if it were ever admitted.

---

## 6. Microsoft Update Catalog Naming Quirks

Section 2.3 introduced the Catalog naming change. This section drills into the implications.

### 6.1 The 21H2 / 24H2 rename

Microsoft's product naming convention for Windows Server changed between Server 2019 and Server 2022. Older OSes are addressed by their user-facing brand name in Catalog update titles:

```
Title: 2026-04 Cumulative Update for Windows Server 2016 for x64-based Systems (KB...)
Title: 2026-04 Cumulative Update for Windows Server 2019 for x64-based Systems (KB...)
```

Newer OSes are addressed by their codename version:

```
Title: 2026-04 Cumulative Update for Microsoft server operating system, version 21H2 for x64-based Systems (KB...)
Title: 2026-04 Cumulative Update for Microsoft server operating system, version 24H2 for x64-based Systems (KB...)
```

`21H2` is the codename for Server 2022; `24H2` is the codename for Server 2025. (The user-facing brand "Server 2025" does not appear in any Catalog update title.)

For any title-string heuristic, the implication is: the OS-token list must be per-OS-version, not a single regex. Treating "Windows Server" as a substring will silently exclude Server 2022 and 2025 results. Treating "Microsoft server operating system" as a substring will exclude 2016 and 2019.

### 6.2 Title-string heuristics as a fragility surface

Any pipeline that consumes Catalog results by matching strings in update titles is committed to maintaining a list of heuristics that look like:

- "title contains 'Cumulative Update for'" — matches LCU titles
- "title contains 'Safe OS Dynamic Update for'" — matches SafeOS DU titles
- "title contains 'Setup Dynamic Update for'" — matches Setup DU titles
- "title contains 'Servicing Stack Update for'" — matches standalone SSU titles
- "title contains 'for Microsoft .NET Framework'" — matches .NET CU umbrella titles

Each of these has been observed to break or behave unexpectedly at some point:

- The ".NET Framework" heuristic catches the .NET 4.8 sibling for Server 2016 but misses the .NET 3.5 / 4.7.x sibling, which uses a different umbrella title (section 2.2).
- The "Dynamic Update for" heuristic returns 0 hits for Server 2019 and Server 2016, because those OS versions don't ship monthly DUs at all. A pipeline that treats "0 hits" as a failure rather than a normal-case outcome will block on these OSes.

The structural fix, derived from the original investigation's Phase 3 architecture recommendation, is to use the release-info / .NET release-notes Markdown sources for **discovery** (which KBs exist this month) and use the Catalog only for **URL resolution** (given a KB number, find the download URL). This removes most title-string heuristics from the pipeline's critical path.

### 6.3 Dynamic Update cadence by OS version

The empirical Dynamic Update cadence picture:

| OS | DU.Setup | DU.SafeOs | Notes |
|---|---|---|---|
| Server 2016 | Not published monthly | Not published monthly | DU only ships on feature-update windows; for LTSC OSes this is rare |
| Server 2019 | Not published monthly | Not published monthly | Same as 2016 |
| Server 2022 | Optional, monthly when published | Optional, monthly when published | Catalog usually returns 1 hit each |
| Server 2025 | **Discontinued or sporadic** (no publications observed for many consecutive months in the 2025-12 to 2026-04 window) | Monthly | Microsoft has not formally announced the cadence change |

A pipeline must therefore treat "DU.Setup absent for this month on Server 2025" as a soft signal, not an error. The Refresher logs "no Setup DU published" and proceeds. This matches what Server 2016 and 2019 have always done.

### 6.4 WSUS Product Category GUIDs and the Server LTSC mapping

§6.1 covered how the Catalog title naming convention changed between Server 2019 and Server 2022 ("Windows Server 2019" → "Microsoft server operating system-21H2" / "Microsoft Server Operating System-24H2"). **These display-name renames are a surface phenomenon**; the underlying GUID hierarchy is unchanged. This section records the WSUS Product Category hierarchy and the correspondence to the four Server LTSC GUIDs, so the reference table remains valid across future naming churn.

#### Hierarchical structure of Product Categories

WSUS Categories form a four-level hierarchy, expressed in `wsusscn2.cab` through the `<Update>` Prerequisites (see §2.4.1):

```
Microsoft (Company)
└─ Windows (ProductFamily)
   ├─ Windows Server 2016                            (Product, LTSC)
   ├─ Windows Server 2019                            (Product, LTSC)
   ├─ Windows Server 2022 LTSC                       (Product, LTSC;
   │     display name "Microsoft server operating system-21H2")
   ├─ Windows Server 2025 LTSC                       (Product, LTSC;
   │     display name "Microsoft Server Operating System-24H2")
   ├─ Windows 10, version 1903 and later             (Product, Client)
   ├─ Windows Server, version 1903 and later         (Product, Server SAC)
   ├─ Microsoft Server Operating System-22H2         (Product, Azure SAC)
   ├─ Microsoft Server Operating System-23H2         (Product, Azure SAC;
   │     build 25398 family)
   └─ ... (older LTSC variants: Server 2008, 2008 R2, 2012, 2012 R2, etc.)
```

The wsusscn2 fetched on 2026-05-12 contains **154 Product Categories** directly under the Windows ProductFamily. Other ProductFamilies (SQL Server, Office, Exchange, Forefront, etc.) coexist as siblings, but the scope filter for this task targets only the 4 Server LTSC entries under Windows.

#### Display-name renames and GUID invariance

As shown in §6.1, Microsoft switched to a codename-based naming convention starting with Server 2022 ("Microsoft server operating system-21H2" / "Microsoft Server Operating System-24H2"). Title-string heuristics (§6.2) break under this change; **GUIDs remain invariant**:

| Server version | Historical display name | Current display name | Product GUID |
|:---|:---|:---|:---|
| Server 2016 | Windows Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` |
| Server 2019 | Windows Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` |
| Server 2022 LTSC | (new) | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` |
| Server 2025 LTSC | (new) | Microsoft server operating system-24H2 | `b256987d-4693-4c87-955d-dbb9341205eb` |

This table is kept in sync with the scope-filter reference in §5.7.

A subtle point: the Catalog display names for Server 2022 and Server 2025 both contain "Microsoft" but **with inconsistent letter-casing conventions** (`Microsoft server operating system-21H2` has lowercase `o`, while `Microsoft Server Operating System-24H2` is title-cased). This is a Microsoft-internal naming inconsistency that does not affect GUID-based lookups.

#### Canonical sources for name-to-GUID resolution

The available means to resolve a display name to its GUID, in decreasing order of authoritativeness:

1. **A live WSUS environment**: `Get-WsusServer | Get-WsusProduct -TitleIncludes "21H2"`. Requires a WSUS server but uses the Microsoft-official API, so this is the most reliable path.
2. **Windows Update Agent API**: on the target OS, enumerate `update.Categories[].CategoryID` from a `Microsoft.Update.Session` COM search result. Requires reference environments such as a Server 2022 VM or Server 2025 VM.
3. **Reverse lookup from real `wsusscn2.cab`**: the technique described in §2.4.1 of this document. Works offline, but because the name itself is not in package.xml you identify the Product by combining the Category Update's `CreationDate` with the build number in the payload URL (Server 2022 LTSC = 20348, Server 2025 LTSC = 26100, Server 23H2 = 25398, Server 2019 = 17763, Server 2016 = 14393).
4. **Cross-reference against community OSS**: [kbupdate-library](https://github.com/potatoqualitee/kbupdate-library), [OSDBuilder](https://github.com/OSDeploy/OSD), [WSUSOffline](https://forums.wsusoffline.net/). Not official, but useful as confirmation against observed values.
5. **Microsoft Learn "WSUS Classification GUIDs"** page (`learn.microsoft.com/ja-jp/previous-versions/windows/desktop/ff357803`): a complete official table exists for the Classification side. An equivalent official table is not published for the Product side, so a combination of the above is required.

The `$Script:WsusScnOsCategoryGuids` table in `Update-WindowsServerIso.ps1` adopts the values cross-referenced via 1–5 above (with §5.7's table as the canonical record).

---

## 7. Operational Hazards

This section catalogues operational hazards encountered during the original investigation that are not covered by the main topical sections. Each has cost real time and is worth a short note for anyone building similar tooling.

### 7.1 PowerShell 5.1 ConsoleHost mojibake on Japanese strings

Symptom: in a `Write-Host` or `Write-Output` call that prints a Japanese string read from a WIM's `ImageName` field (e.g., `Windows Server 2016 Standard Evaluation (デスクトップ エクスペリエンス)`), each non-ASCII codepoint is rendered twice (`デデススククトトッッププ`...) on some lines but not others within the same run.

Properties of the failure:

- Does not corrupt the underlying data — the CSV that the same run also writes contains the correct string
- Is not reproducible across re-runs in a deterministic way
- The follow-up investigation in the original corpus narrowed the cause to **DISM mount-cache state**: a stale mount, an orphaned hard link, or a partially-cleaned `WimMountedImageInfo` entry from a prior aborted run can cause the WIM provider to serve a corrupted edition name on subsequent enumerations
- The simplest workaround is to use a **fresh WorkRoot per OS family** — i.e., don't reuse `D:\UpdateWsi` for both a Server 2016 and a Server 2025 build; partition by OS into `D:\UpdateWsi_2016`, `D:\UpdateWsi_2025`, etc.

Underlying root cause has not been formally established. Compatible hypotheses:

- DISM caches per-mount metadata in `%TEMP%`, `%WINDIR%\Logs\DISM`, or the `WimMountedImageInfo` registry key; corruption in any of these can poison a later mount of the same WIM
- PowerShell 5.1's `ConsoleHost` uses the legacy Win32 console subsystem, which has known issues handling UTF-16 surrogate pairs and code-page transitions on lines that mix Japanese with ASCII

Diagnostic step: when the issue reproduces, dump `dism /Get-MountedImageInfo` and `Get-WindowsImage -Mounted` to a side file; stale mount entries provide direct evidence of the cache-poisoning hypothesis.

### 7.2 `expand.exe -F:` self-overwrite on nested CABs

Symptom: `expand.exe -F:* wsusscn2.cab destination_dir` fails partway through with `ERROR_FILE_EXISTS` even when `/Y` is specified, when `destination_dir` overlaps any path that exists inside the CAB.

Root cause: `expand.exe` does not deduplicate when files appear in multiple positions inside the CAB's logical tree. A nested CAB whose inner files share names with files in the outer CAB can cause expand to overwrite a file it has just written.

Workaround: use 7-Zip (`7za x -y -bd -bso0`) or extract to a fresh staging directory and tolerate the disk cost. `Shell.Application` COM-based extraction also avoids the bug but is slower and has its own non-determinism issues.

### 7.3 `List[object]` + `@()` expansion in PowerShell 7.4

Symptom: building a list of `[pscustomobject]` instances via `System.Collections.Generic.List[object]` and then array-wrapping the list with `@($list)` throws `System.ArgumentException: Argument types do not match`. The same code with `List[string]` works.

```powershell
$list = [System.Collections.Generic.List[object]]::new()
$list.Add([pscustomobject]@{Label = 'a'}) | Out-Null
$list.Add([pscustomobject]@{Label = 'b'}) | Out-Null

@($list)            # FAILS in PS 7.4: Argument types do not match
[object[]]@($list)  # FAILS for the same reason
$list.ToArray()     # OK
foreach ($x in $list) { $arr += $x }   # OK
```

Workaround: use `$list.ToArray()` at the function output boundary. This is observed in PowerShell 7.4.x; behaviour on later versions has not been re-tested.

The deeper issue is in PowerShell's handling of strongly-typed generic collections when wrapped in the `@()` subexpression operator; the operator performs an array-coercion that does not always succeed for `List[object]` containing `pscustomobject` elements.

### 7.4 signtool exit-code-1 as a terminating error

Section 3.5 already mentioned this. The expanded version: `signtool verify /ds N` returns exit code 1 when the requested signature index does not exist, writing "No signature found" to stderr. Under `$ErrorActionPreference = 'Stop'`, PowerShell treats this as a terminating error and aborts whatever script is calling signtool, even when the caller was expecting and prepared to handle the 1 (it was probing for additional signatures, and "no more" is normal).

Workaround: wrap signtool in a helper function that switches `$ErrorActionPreference = 'Continue'` for the duration of the call, captures the exit code and output explicitly, and returns a structured result object.

---

## 8. Verification Strategies

The original investigation's experience with verification can be summarised as: each layer of automated verification catches a different class of regression, but no automated verification catches the class of "the binary boots on the firmware".

### 8.1 Pre-flight gates

The cheapest verification is at config-load time, before any I/O-heavy work begins. The questions worth asking at this stage:

- **Patch-set consistency**: do the KB numbers in the config form a self-consistent set? (Section 5.5 — pre-flight dependency-graph validation using `wsusscn2.cab`-derived data.)
- **File-system presence**: does every MSU referenced by the config actually exist on disk and have the expected SHA-256? (A simple checksum table catches half-finished downloads.)
- **OS-version match**: does the config's declared OS match the install.wim's embedded version? (`Get-WindowsImage` returns `ImageVersion`; the config can declare an expected `BuildNumberMin` and abort if the WIM is older.)
- **Servicing-stack-already-present**: if the config declares the LCU is standalone, is the SSU also in the config? (Section 5.3.)

These checks complete in milliseconds and produce errors that an operator can act on immediately, in the same session.

### 8.2 Mount-time and apply-time gates

Once the WIM is mounted, `Add-WindowsPackage` will reject inapplicable packages with detailed HRESULTs. The two most common are:

- `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED` — the SSU dependency was not satisfied (section 5.1)
- `0x800f0922 CBS_E_INSTALLERS_FAILED_TO_LOAD` — a corrupted SSU or incompatible architecture

Neither failure is "the script's fault" in the conventional sense; they reflect a config error that should have been caught at pre-flight. The remediation is to fail loudly, leave the WIM unmounted in a clean state, and tell the operator which config line needs attention.

### 8.3 Post-build verification

Once the output ISO is produced, a final verification layer can confirm:

- **File-system structure**: the expected `\boot\`, `\efi\`, `\sources\` trees are present
- **Boot-binary identity**: the binaries at the expected paths have the expected file or Authenticode hash (section 3.6)
- **Authenticode chain**: the boot binaries that the spec says must carry the PCA2023 trust chain do in fact rebuild to a chain that includes a PCA2023 intermediate (section 3.7)

The Microsoft reference `Make2023BootableMedia.ps1` v1.4 does none of this. A verification function that performs these checks is therefore an upward-compatible quality improvement, not a deviation from the Microsoft pattern. The output of the verification function should carry the SCOPE clarifier from section 3.7 — automated verification cannot replace a hardware boot test.

### 8.4 The verification boundary

The line that no automated tool can cross: **whether a Secure Boot platform actually boots the produced ISO**. This depends on whether the target firmware has been provisioned with PCA2023 in DB (or, in the post-revocation world, whether the target firmware still has PCA2011 in DB at all). That is per-machine, per-firmware-version state. The only definitive test is to boot the ISO on a representative target — physical hardware that has received the firmware update for the deployment generation, or a Hyper-V Gen2 VM created from a recent Microsoft-published Secure Boot template (which itself was created with PCA2023 in mind). A Hyper-V Gen2 validation is useful for pre-deployment smoke testing, but firmware trust-anchor provisioning can differ significantly from physical OEM hardware: the DB/DBX provisioning state of a Hyper-V virtual firmware may differ from a given physical platform's, so a Hyper-V pass does not guarantee a physical-platform pass.

A pipeline that lacks a boot test is not "broken"; it is operating with a known and bounded limitation that the SCOPE clarifier makes visible to the human operator.

---

## 9. Open Questions

This article synthesises the state of knowledge as of mid-2026. Several questions remain open in the original corpus and would be appropriate starting points for follow-up investigation:

1. **PCA2011 DBX rollout timing**: Microsoft has announced that PCA2011 will be moved to DBX on a future timeline, but the exact date has not been published. Any pipeline that builds long-supported ISOs (5+ years of supported deployment) needs an answer here; the conservative assumption is "sometime in 2026-2027".

2. **`bootmgr_EX.efi` permanence**: Server 2025's `bootmgr_EX.efi` is byte-for-byte identical to `bootmgr.efi`, including the PCA2011 signature. Whether this is a transitional artifact (eventually `bootmgr_EX.efi` will be re-signed under PCA2023) or a permanent design choice (BIOS boot does not require PCA2023, so the file is intentionally PCA2011 even with the `_EX` suffix) is unclear. Microsoft's `Make2023BootableMedia.ps1` v1.4 comment suggests the latter, but the file's future state cannot be predicted.

3. **`.NET Framework` page index parsing**: the `.NET Framework release-notes` index page is served as Markdown but its entry list uses a syntax variation that simple regex-based parsers miss. A Markdown library or a more robust parser would close this gap and give the pipeline a self-bootstrap from "what was the most recent .NET CU month?".

4. **Hotpatch ISO integration**: the Hotpatch calendar (section 2.1) is queryable, but nothing in the data suggests that hotpatch packages can be `Add-WindowsPackage`'d into a mounted offline WIM. The Hotpatch model is a runtime in-memory patching mechanism that requires the running OS to be enrolled. A pipeline that builds from a Hotpatch baseline-month LCU (so that a fresh deployment can enrol in hotpatching without an immediate baseline-update reboot) is conceivable; whether Microsoft formally supports this pattern is not known.

5. **Server 2025 DU.Setup cadence**: as noted in section 6.3, Microsoft has not formally announced whether Server 2025's Setup Dynamic Update has been discontinued, moved to a quarterly cadence, or merely been absent for an extended period for unrelated reasons.

6. **DISM mount-cache mojibake root cause**: section 7.1's hypothesis (mount-cache state corruption) is consistent with the symptom but has not been definitively isolated. A clean-room reproduction on a fresh Windows install, with controlled mount/unmount sequences and explicit cache inspection, would either confirm the hypothesis or eliminate it.

### Known Unknowns

Distinct from the open questions above (which are concrete investigation gaps), the following are forward-looking uncertainties whose resolution depends on Microsoft's future decisions rather than on further analysis of current data:

- Whether Microsoft will eventually PCA2023-sign `bootmgr.efi` (the BIOS/`_EX` boot file that currently remains PCA2011-signed).
- Whether the Server 2025 DU.Setup cadence change is an intentional policy shift or an incidental gap.
- Whether future `wsusscn2.cab` revisions will expose KB identifiers differently (e.g. reintroducing a KB element, or changing the payload-URL naming pattern that KB inference currently depends on).
- Whether Server vNext continues the `_EX` dual-tree model or replaces it with a different PCA2023 delivery mechanism.
- Whether the PCA2011 DBX revocation timing will vary across OEM firmware ecosystems rather than following a single Microsoft-announced date.
- Whether Microsoft will eventually publish the Server LTSC Product Category GUID mappings officially, rather than leaving them to be reverse-looked-up from wsusscn2 and community sources (see §5.7).
- Whether the GitHub-backed release-info Markdown source (§2.1) will remain stable in format, or be retired / restructured in a way that breaks the table-layout parser.

These are listed not because the article can answer them, but because a long-lived pipeline should budget for the possibility that any of them changes.

---

## 10. Confidence Levels

Because this article mixes Microsoft-documented facts with behavior that was inferred or observed empirically, it is worth stating explicitly which claims rest on which class of evidence. Readers building long-lived tooling should treat the lower-confidence classes as subject to change and re-validate them against their own environment.

### Official / Microsoft-documented

These rest on Microsoft's own published documentation or shipped tooling and are the most stable:

- WSUS Classification GUIDs (the five identifiers themselves), per the Microsoft Learn "WSUS Classification GUIDs" page.
- Windows Server release-info pages (build numbers, KB numbers, availability dates) as published on Microsoft Learn.
- Windows Update Agent (WUA) offline-scan usage as the authoritative applicability evaluator.
- The purpose of `Make2023BootableMedia.ps1` as the PCA2023 boot-media migration tool.

### High-confidence inferred

These are not formally documented as such, but the supporting evidence (reverse-lookup from real wsusscn2 data, cross-referenced against multiple independent sources) is strong:

- The Server LTSC Product GUID mapping (Server 2016 / 2019 / 2022 / 2025), verified by reverse-lookup against live wsusscn2 metadata and cross-referenced with community OSS and observed LCU KB numbers.
- The `package.xml` dependency-graph relationships (`Prerequisites`, `SupersededBy`, `BundledBy`, payload roll-up from leaf to bundle).
- The observed Server 2025 LCU bundle behavior (combined LCU + SSU-dependency resolution metadata) in current Catalog snapshots.

### Observed but not contractual

These describe behavior seen in specific metadata snapshots or media at a point in time. They are useful, but Microsoft has not committed to them and they may change without notice:

- Catalog title heuristics (the 21H2 / 24H2 display-name conventions and casing).
- Dynamic Update cadence by OS version.
- EFI_EX / bootmgr_EX implementation details (which `_EX` binaries ship, and their signing chains).
- Payload URL naming conventions (the `windows10.0-kb<digits>-<arch>` filename pattern from which KB numbers are parsed).
- `package.xml` schema assumptions (element names, attribute placement, the absence of a KB element).

When in doubt, the WUA offline scan is the authoritative arbiter for applicability, and the Microsoft Update Catalog plus the release-info pages are authoritative for KB-to-build mapping.

---

## Appendix A: Glossary of Microsoft Servicing Terms

| Term | Definition |
|---|---|
| **Applicability evaluation** | The decision of whether a given update is installable on a given image, made authoritatively by the Windows Update Agent servicing logic (see WUA). Distinct from metadata-level dependency discovery. |
| **Authenticode hash** | The PE-image hash defined to exclude the signature region (`IMAGE_DIRECTORY_ENTRY_SECURITY`) and the PE-header checksum. Two binaries with identical code but different signatures share an Authenticode hash but differ by file hash. See PE image hash. |
| **Bundle** | In wsusscn2 terms, an update marked `IsBundle="true"` that carries Product and Classification categories but no payload of its own; its payload is rolled up from the leaf updates that name it in `<BundledBy>`. |
| **CAB** | Cabinet file (`.cab`). Microsoft's compressed archive format. The format of payload archives inside an MSU, and of `wsusscn2.cab` and its inner packages. |
| **CBS** | Component-Based Servicing. The Windows servicing model since Vista. The error codes prefixed `CBS_E_*` originate here. |
| **Classification GUID** | A WSUS-defined identifier for an update's classification (SecurityUpdates, UpdateRollups, ServicePacks, etc.). The GUIDs are Microsoft-defined; the mapping of update *categories* to classification *usage* is heuristic (see §5.7). |
| **DBX** | Secure Boot's revocation database. A list of certificates and image hashes that the firmware will refuse to load regardless of DB. |
| **DB** | Secure Boot's allowed-signatures database. A list of certificates that the firmware accepts. PCA2011 and PCA2023 are both DB entries on platforms that have received the relevant provisioning. |
| **DISM** | Deployment Image Servicing and Management. The Windows tool/API for operating on offline (mounted) Windows images. |
| **DU** | Dynamic Update. Updates Microsoft injects into the Windows Setup environment during installation. **DU.Setup** updates the Setup itself; **DU.SafeOs** updates the WinPE / WinRE recovery environment. |
| **SafeOS DU** | The DU.SafeOs variant: a Dynamic Update targeting the WinPE / WinRE (SafeOS) recovery environment rather than the main Setup binaries. |
| **EFI / EFI_EX** | Directory names inside `install.wim` and on installation media. `EFI` holds traditional PCA2011-signed boot binaries; `EFI_EX` holds the same binaries re-signed under PCA2023. |
| **HRESULT** | A 32-bit return code used throughout Windows APIs. `0x800f0823` is the SSU-required error. |
| **LCU** | Latest Cumulative Update. The monthly Patch Tuesday rollup for the OS itself. |
| **MSU** | Microsoft Update Standalone Installer file (`.msu`). The package format Microsoft uses for downloadable updates. An MSU is structurally a CAB containing a `.cab` payload and metadata files. |
| **PCA2011** | `Microsoft Windows Production PCA 2011`. The certificate authority that has signed Windows boot binaries since Windows 8 era. Being phased out. |
| **PCA2023** | `Windows UEFI CA 2023`. The replacement CA. |
| **PE image hash** | The hash of the full on-disk PE file (what `Get-FileHash` measures), including the signature region — as opposed to the Authenticode hash, which excludes it. |
| **Product Category** | A WSUS Category representing a product (e.g. a Server LTSC edition), identified by a Product GUID. In wsusscn2 it appears both as a `<Category>` reference and as a standalone Category Update (see §2.4.1). |
| **SSU** | Servicing Stack Update. Updates the servicer itself, which is what installs LCUs. May be standalone (separate MSU) or Combined (bundled into the LCU's MSU). |
| **Supersedence** | The relationship in which a newer update replaces an older one. wsusscn2's Master XML exposes the reverse direction (`<SupersededBy>`); the forward direction lives only in per-package CABs. |
| **Slipstreaming** | The practice of integrating updates into an installation medium so that the installed OS is already patched at first boot. |
| **WIM** | Windows Imaging Format. The file format of `install.wim` and `boot.wim`. Conceptually a deduplicated multi-image archive. |
| **WSUS** | Windows Server Update Services. Microsoft's enterprise update management server. `wsusscn2.cab` is the offline scan catalogue used by WSUS clients to determine update applicability without contacting Microsoft's online services. |
| **WUA** | Windows Update Agent. The on-machine servicing component whose applicability logic is the authoritative evaluator for whether an update is installable; an offline WUA scan validates against a mounted image. |

---

## Appendix B: Source URLs Reference

| Resource | URL |
|---|---|
| Windows Server release-info page (Markdown) | `https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown` |
| Windows Server release-info source on GitHub | `https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md` |
| .NET Framework release-notes index (Markdown) | `https://learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown` |
| Microsoft Update Catalog | `https://catalog.update.microsoft.com/` |
| Microsoft Update Catalog: ScopedView (per-update detail) | `https://catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=<GUID>` |
| `wsusscn2.cab` download (current static URL) | `https://catalog.s.download.windowsupdate.com/d/msdownload/update/v3/static/trusted/.../wsusscn2.cab` |
| Microsoft Support: `Make2023BootableMedia.ps1` reference | KB5053484 (search the Microsoft Support site for the article number) |

URLs are subject to Microsoft's discretion and may change without notice. The release-info page's GitHub-backed nature gives the strongest stability guarantee of the set.

---

## Appendix C: Provenance and Source Material

This article synthesises technical findings accumulated during the multi-revision development of a real Windows Server ISO update pipeline. The underlying investigation logs — which mixed revision-specific debugging records with the general technical findings extracted here — were originally maintained alongside that pipeline as living documents.

The original repository is [`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) under `scripts/powershell/update-windows-server-iso/`. The investigation cycles that produced this material spanned the cycle revisions tagged in the repository's CHANGELOG; the findings below were extracted from the now-retired `docs/history/` subdirectory.

What this article is and is not:

- **Is**: a portable, project-independent reference to the technical surface area that Windows Server ISO slipstreaming touches, including the patch metadata sources, the PCA2023 migration semantics, the install.wim cross-version asymmetries, the SSU dependency model, the Catalog naming quirks, and the operational hazards encountered.
- **Is not**: documentation for any particular implementation. Phase numbers, function names, configuration file schemas, and revision identifiers from the original pipeline have been deliberately removed. The article is intended to be useful to anyone building similar tooling in any language or framework, not just to consumers of the original pipeline.

For implementers building on the original repository's PowerShell pipeline, the source-of-truth for tool-specific behaviour is the pipeline's own `SPEC.md` and `README.md`; this article is the cross-cutting concern map, not the user manual.

The article was prepared by Anthropic Claude (Opus 4.7) under the direction of the repository maintainer, by reading and synthesising the original `docs/history/` content. It synthesizes findings from the repository investigation logs and cross-references Microsoft public documentation where noted.

---

## Appendix D: Operational Guarantees vs Observations

This table consolidates the epistemic status of the major claims in the article, so a future maintainer can see at a glance which facts are safe to depend on and which should be re-validated. "Officially announced" means Microsoft has published it; "Operationally stable" means it has held across every observation but carries no formal guarantee; "Observed" means it was seen in specific snapshots/media and may change without notice.

| Topic | Status |
|:---|:---|
| PCA2023 rollout (the migration itself) | Officially announced |
| PCA2011 → DBX revocation *timing* | Announced in principle; exact date NOT guaranteed |
| WSUS Classification GUIDs (the identifiers) | Officially documented |
| Server LTSC Product GUID persistence | Operationally stable (not officially published) |
| Product-category → name resolution | Requires reverse-lookup (no official offline table) |
| wsusscn2 schema stability | NOT guaranteed |
| `package.xml` as a parse target | Unsupported implementation detail |
| KB inference from FileLocation URL | Heuristic (URL structure not contractual) |
| `_EX` dual-tree directory structure | Observed (Server 2025 media) |
| Server 2025 dual-file LCU+SSU Catalog behavior | Observed (current Catalog) |
| `bootmgr_EX.efi` PCA2011 signing | Observed / implementation-consistent |
| Dynamic Update cadence on LTSC | Observed only |
| Final applicability / installability | Authoritative only via WUA servicing logic |

When a row says anything other than "Officially announced" or "Officially documented", treat it as advisory: useful for discovery and acceleration, but not a substitute for Microsoft's own servicing validation.
