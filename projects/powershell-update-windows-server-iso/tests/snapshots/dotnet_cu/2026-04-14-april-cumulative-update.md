---
layout: Conceptual
title: April 2026 cumulative update - .NET Framework | Microsoft Learn
canonicalUrl: https://learn.microsoft.com/en-us/dotnet/framework/release-notes/2026/04-14-april-cumulative-update
apiPlatform: dotnet
author: gewarren
breadcrumb_path: /dotnet/breadcrumb/toc.json
feedback_system: OpenSource
feedback_product_url: https://aka.ms/feedback/report?space=61
ms.author: dotnetcontent
ms.devlang: dotnet
ms.service: dotnet-framework
ms.topic: release-notes
show_latex: true
uhfHeaderId: MSDocsHeader-DotNet
ms.update-cycle: 3650-days
description: Learn about the improvements in the .NET Framework April 2026 cumulative update.
ms.date: 2026-04-28T00:00:00.0000000Z
locale: en-us
document_id: 8638d816-74e6-315d-5eb4-debbea74c8be
document_version_independent_id: b75e83d2-ad8f-07b6-e6da-8170c59ca30b
updated_at: 2026-05-15T16:34:00.0000000Z
original_content_git_url: https://github.com/dotnet/docs/blob/live/docs/framework/release-notes/2026/04-14-april-cumulative-update.md
gitcommit: https://github.com/dotnet/docs/blob/73fac5fd8b4588a4dfbdfdf3e7421824cec0dd6c/docs/framework/release-notes/2026/04-14-april-cumulative-update.md
git_commit_id: 73fac5fd8b4588a4dfbdfdf3e7421824cec0dd6c
site_name: Docs
depot_name: VS.core-docs
page_type: conceptual
toc_rel: ../../toc.json
pdf_url_template: https://learn.microsoft.com/pdfstore/en-us/VS.core-docs/{branchName}{pdfName}
feedback_help_link_type: ''
feedback_help_link_url: ''
search.mshattr.devlang: csharp
word_count: 639
asset_id: framework/release-notes/2026/04-14-april-cumulative-update
moniker_range_name: 
monikers: []
item_type: Content
source_path: docs/framework/release-notes/2026/04-14-april-cumulative-update.md
cmProducts:
- https://authoring-docs-microsoft.poolparty.biz/devrel/7696cda6-0510-47f6-8302-71bb5d2e28cf
spProducts:
- https://authoring-docs-microsoft.poolparty.biz/devrel/69c76c32-967e-4c65-b89a-74cc527db725
platformId: e5a760a0-96c8-4f6c-b24b-fd1e75ef4ea1
---

# April 2026 cumulative update - .NET Framework | Microsoft Learn

*Released April 14, 2026* *Updated April 28, 2026, to include a known issue.*

## Summary of what's new in this release

- Security improvements
- Quality and reliability improvements

### Security improvements

#### CVE-2026-32178 – Remote Code Execution vulnerability

This security update addresses a remote code execution vulnerability detailed in [CVE-2026-32178](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-32178).

#### CVE-2026-32203 – Denial of Service vulnerability

This security update addresses a denial-of-service vulnerability detailed in [CVE-2026-32203](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-32203).

#### CVE-2026-32226 – Denial of Service vulnerability

This security update addresses a denial-of-service vulnerability detailed in [CVE-2026-32226](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-32226).

#### CVE-2026-23666 – Denial of Service vulnerability

This security update addresses a denial-of-service vulnerability detailed in [CVE-2026-23666](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-23666).

#### CVE-2026-26171 – Security Feature Bypass vulnerability

This security update addresses a security feature bypass vulnerability detailed in [CVE-2026-26171](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-26171).

#### CVE-2026-33116 – Information Disclosure vulnerability

This security update addresses an information disclosure vulnerability detailed in [CVE-2026-33116](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2026-33116).

### Quality and reliability improvements

#### .NET Runtime

Addresses an issue to add verification logic for ClickOnce to support SHA384 and SHA512. (*Applies to: .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2, 4.8, 4.8.1*)

Addresses an issue in cases where the Arm64 CLR could crash when code generates and catches a NullReferenceException within the same function. (*Applies to: .NET Framework 4.8.1*)

Addresses an issue to update operating system calls for compliance with current standards. (*Applies to: .NET Framework 4.8.1*)

#### WCF

Addresses an issue with running a WCF NamedPipe service inside a Win32 app container when running on Windows 11 or Windows Server 2025. (*Applies to: .NET Framework 4.8.1*)

## Known issues in this release

This update might fail to install when [applied through DISM](/en-us/windows-hardware/manufacture/desktop/dism---deployment-image-servicing-and-management-technical-reference-for-windows) to an offline Windows 10 IoT Enterprise LTSC 21H2 image. A fix for this issue will be included in an upcoming .NET Framework update.

## Summary tables

The following table outlines the updates in this release.

| Product version | Cumulative update |
| --- | --- |
| **Windows 11, version 26H1** |  |
| .NET Framework 4.8.1 | [5082421](https://support.microsoft.com/kb/5082421) |
| **Windows 11, version 25H2** |  |
| .NET Framework 3.5, 4.8.1 | [5082417](https://support.microsoft.com/kb/5082417) |
| **Windows 11, version 24H2** |  |
| .NET Framework 3.5, 4.8.1 | [5082420](https://support.microsoft.com/kb/5082420) |
| **Microsoft server operating system, version 24H2** |  |
| .NET Framework 3.5, 4.8.1 | [5082417](https://support.microsoft.com/kb/5082417) |
| **Microsoft server operating system, version 23H2** |  |
| .NET Framework 3.5, 4.8.1 | [5082418](https://support.microsoft.com/kb/5082418) |
| **Windows 11, version 22H2 and Windows 11, version 23H2** |  |
| .NET Framework 3.5, 4.8.1 | [5082424](https://support.microsoft.com/kb/5082424) |
| **Windows Server 2022** | **[5084071](https://support.microsoft.com/kb/5084071)** |
| .NET Framework 3.5, 4.8 | [5082427](https://support.microsoft.com/kb/5082427) |
| .NET Framework 3.5, 4.8.1 | [5082425](https://support.microsoft.com/kb/5082425) |
| **Windows 10, version 22H2** | **[5084068](https://support.microsoft.com/kb/5084068)** |
| .NET Framework 3.5, 4.8 | [5082426](https://support.microsoft.com/kb/5082426) |
| .NET Framework 3.5, 4.8.1 | [5082419](https://support.microsoft.com/kb/5082419) |
| **Windows 10, version 21H2** | **[5084067](https://support.microsoft.com/kb/5084067)** |
| .NET Framework 3.5, 4.8 | [5082426](https://support.microsoft.com/kb/5082426) |
| .NET Framework 3.5, 4.8.1 | [5082419](https://support.microsoft.com/kb/5082419) |
| **Windows 10 1809 and Windows Server 2019** | **[5084066](https://support.microsoft.com/kb/5084066)** |
| .NET Framework 3.5, 4.7.2 | [5082413](https://support.microsoft.com/kb/5082413) |
| .NET Framework 3.5, 4.8 | [5082414](https://support.microsoft.com/kb/5082414) |
| **Windows 10 1607 and Windows Server 2016** |  |
| .NET Framework 3.5, 4.6.2, 4.7, 4.7.1, 4.7.2 | [5082198](https://support.microsoft.com/kb/5082198) |
| .NET Framework 4.8 | [5082411](https://support.microsoft.com/kb/5082411) |

The following table is for earlier Windows and Windows Server versions for Security and Quality Rollup updates.

| Product version | Security and quality rollup |
| --- | --- |
| **Windows Server 2012 R2** | **[5084070](https://support.microsoft.com/kb/5084070)** |
| .NET Framework 3.5 | [5082406](https://support.microsoft.com/kb/5082406) |
| .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2 | [5082402](https://support.microsoft.com/kb/5082402) |
| .NET Framework 4.8 | [5082404](https://support.microsoft.com/kb/5082404) |
| **Windows Server 2012** | **[5084069](https://support.microsoft.com/kb/5084069)** |
| .NET Framework 3.5 | [5082398](https://support.microsoft.com/kb/5082398) |
| .NET Framework 4.6.2, 4.7, 4.7.1, 4.7.2 | [5082400](https://support.microsoft.com/kb/5082400) |
| .NET Framework 4.8 | [5082403](https://support.microsoft.com/kb/5082403) |

The operating system rows list a KB that's used for update-offering purposes. When the operating system KB is offered, the applicability logic determines the specific .NET Framework updates that will be installed. Updates for individual .NET Framework versions are installed based on the version of .NET Framework that's already present on the device. Because of this, the operating system KB is not expected to be listed as an installed update on the device. The expected updates to be installed are the .NET Framework specific version updates listed in the preceding table.

This update installs the complete .NET Framework 3.5 product for Windows 11, version 26H1 (build version 28000) and newer. Unlike traditional cumulative updates that patch individual components, this delivers the full .NET Framework 3.5 product as a standalone installer. It replaces any previously installed version.

| Product version | .NET Framework 3.5 product update |
| --- | --- |
| **Windows 11, version 26H1** | [5084165](https://support.microsoft.com/kb/5084165) |