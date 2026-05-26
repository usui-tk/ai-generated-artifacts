---
layout: Conceptual
title: Windows Server release information | Microsoft Learn
canonicalUrl: https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info
breadcrumb_path: /windows/release-health/breadcrumb/toc.json
uhfHeaderId: MSDocsHeader-Windows
feedback_system: None
adobe-target: true
description: Release information about Windows Server
ms.topic: release-notes
ms.date: 2026-05-12T00:00:00.0000000Z
author: direek
ms.author: direek
ms.service: windows-server
ms.localizationpriority: medium
locale: en-us
document_id: e8f023d4-8c21-a54e-413c-8e0cbe5962c8
document_version_independent_id: e8f023d4-8c21-a54e-413c-8e0cbe5962c8
updated_at: 2026-05-13T02:11:00.0000000Z
original_content_git_url: https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md
gitcommit: https://github.com/MicrosoftDocs/windows-release-pr/blob/a6d7092416badcdff27c219f3884a89685f7c50e/windows/release-information/windows-server-release-info.md
git_commit_id: a6d7092416badcdff27c219f3884a89685f7c50e
site_name: Docs
depot_name: TechNet.rel-info
page_type: conceptual
toc_rel: toc.json
feedback_product_url: ''
feedback_help_link_type: ''
feedback_help_link_url: ''
word_count: 3902
asset_id: windows-server-release-info
moniker_range_name: 
monikers: []
item_type: Content
source_path: windows/release-information/windows-server-release-info.md
cmProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/fc3f72c2-fb6f-4cea-95ee-b444e52254ee
spProducts:
- https://microsoft-devrel.poolparty.biz/DevRelOfferingOntology/f12cf087-582d-48ac-a085-0c19adf1e391
platformId: ae6f24aa-ee2a-e121-7af5-8fe0aad613a1
---

# Windows Server release information | Microsoft Learn

Windows Server has two primary [release channels](/en-us/windows-server/get-started/servicing-channels-comparison): the Long-Term Servicing Channel (LTSC) and the Annual Channel (AC). The LTSC provides a longer-term option focusing on a traditional lifecycle of security and quality updates. The AC provides more frequent releases, focusing on containers and microservices, so you can take advantage of innovation more quickly.

Windows Server 2025 is the current LTSC release. Windows Server, version 23H2 is the latest AC release. The focus on virtualization, container, and microservice innovation continues with [Azure Stack HCI](/en-us/azure-stack/hci/), [Windows containers](/en-us/virtualization/windowscontainers/), and [AKS on Azure Stack HCI](/en-us/azure-stack/aks-hci/).

If you are an IT administrator and want to programmatically get information from this page, use the [Windows Updates API in Microsoft Graph](/en-us/graph/api/resources/windowsupdates-product?view=graph-rest-beta).

## Windows Server major versions by servicing option

(All dates are listed in ISO 8601 format: YYYY-MM-DD)

| Windows Server version | Servicing option | Editions | Availability date | Mainstream support end date | Extended support end date | Latest update for ESU | Latest revision date | Latest build |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Windows Server 2025 | Long-Term Servicing Channel (LTSC) | Datacenter, Standard | 2024-11-01 | 2029-11-13 | 2034-11-14 | [2026-05 B](https://support.microsoft.com/help/5087539) | 2026-05-12 | 26100.32860 |
| Windows Server 2022 | Long-Term Servicing Channel (LTSC) | Datacenter, Standard | 2021-08-18 | 2026-10-13 | 2031-10-14 | [2026-05 B](https://support.microsoft.com/help/5087545) | 2026-05-12 | 20348.5139 |
| Windows Server 2019 (version 1809) | Long-Term Servicing Channel (LTSC) | Datacenter, Standard | 2018-11-13 | End of updates | 2029-01-09 | [2026-05 B](https://support.microsoft.com/help/5087538) | 2026-05-12 | 17763.8755 |
| Windows Server 2016 (version 1607) | Long-Term Servicing Branch (LTSB) | Datacenter, Essentials, Standard | 2016-08-02 | End of updates | 2027-01-12 | [2026-05 B](https://support.microsoft.com/help/5087537) | 2026-05-12 | 14393.9140 |

Note

Windows Server is governed by the [Fixed Lifecycle Policy](/en-us/lifecycle/policies/fixed). See the [Windows Lifecycle FAQ](https://support.microsoft.com/help/18581/lifecycle-faq-windows-products) and [Comparison of servicing channels](/en-us/windows-server/get-started/servicing-channels-comparison) for details regarding servicing requirements and other important information. To learn more about Windows Server’s Lifecycle Policy, see a [Windows Server Releases](/en-us/lifecycle/products/windows-server).

## Windows Server release history

The table below shows the history of all monthly security and non-security preview updates released for supported versions of Windows Server in the Long-Term Servicing Channel. Note that the Update type column references each monthly update by the year and the month of its release, followed by a letter indicating the week of the month (B is the second week of the month; D is the fourth week of the month). Out-of-band updates are referenced as OOB. This shorthand notation aligns with what you see in Microsoft Intune. For more information, see [Type of update releases](/en-us/windows/deployment/update/release-cycle#types-of-update-releases).Release notes for Windows Server are available on [Windows Server 2025 update history](https://support.microsoft.com/topic/windows-server-2025-update-history-10f58da7-e57b-4a9d-9c16-9f1dcd72d7d7), [Windows Server 2022 update history](https://support.microsoft.com/topic/windows-server-2022-update-history-e1caa597-00c5-4ab9-9f3e-8212fe80b2ee), [Windows Server 2019 update history](https://support.microsoft.com/topic/windows-10-and-windows-server-2019-update-history-725fc2e1-4443-6831-a5ca-51ff5cbcb059), and [Windows Server 2016 update history](https://support.microsoft.com/topic/windows-10-and-windows-server-2016-update-history-4acfbc84-a290-1b54-536a-1c0430e9f3fd).
**Windows Server 2025 (OS build 26100)**

| Servicing option | Update type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- |
| LTSC | 2026-05 B | 2026-05-12 | 26100.32860 | [KB5087539](https://support.microsoft.com/help/5087539) |
| LTSC | 2026-04 OOB | 2026-04-19 | 26100.32698 | [KB5091157](https://support.microsoft.com/help/5091157) |
| LTSC | 2026-04 B | 2026-04-14 | 26100.32690 | [KB5082063](https://support.microsoft.com/help/5082063) |
| LTSC | 2026-03 B | 2026-03-10 | 26100.32522 | [KB5078740](https://support.microsoft.com/help/5078740) |
| LTSC | 2026-02 B | 2026-02-10 | 26100.32370 | [KB5075899](https://support.microsoft.com/help/5075899) |
| LTSC | 2026-01 OOB | 2026-01-24 | 26100.32236 | [KB5078135](https://support.microsoft.com/help/5078135) |
| LTSC | 2026-01 OOB | 2026-01-17 | 26100.32234 | [KB5077793](https://support.microsoft.com/help/5077793) |
| LTSC | 2026-01 B | 2026-01-13 | 26100.32230 | [KB5073379](https://support.microsoft.com/help/5073379) |
| LTSC | 2025-12 B | 2025-12-09 | 26100.7462 | [KB5072033](https://support.microsoft.com/topic/december-9-2025-kb5072033-os-build-26100-7462-fca31d8d-5fe8-4b5e-9591-6641ef1d26a1) |
| LTSC | 2025-11 OOB | 2025-11-18 | 26100.7178 | [KB5072359](https://support.microsoft.com/topic/november-18-2025-kb5072359-os-build-26100-7178-out-of-band-4c7a1771-0a7d-4652-a5fa-c24b1828faf2) |
| LTSC | 2025-11 B | 2025-11-11 | 26100.7171 | [KB5068861](https://support.microsoft.com/topic/november-11-2025-kb5068861-os-build-26100-7171-24e553d1-2338-433e-9cc3-61733148530c) |
| LTSC | 2025-10 OOB | 2025-10-23 | 26100.6905 | [KB5070881](https://support.microsoft.com/help/5070881) |
| LTSC | 2025-10 OOB | 2025-10-20 | 26100.6901 | [KB5070773](https://support.microsoft.com/topic/october-20-2025-kb5070773-os-build-26100-6901-out-of-band-f8effaa1-1c73-41e5-bcb3-e58a46c7601e) |
| LTSC | 2025-10 B | 2025-10-14 | 26100.6899 | [KB5066835](https://support.microsoft.com/topic/october-14-2025-kb5066835-os-build-26100-6899-6cdcc1c3-cfbf-41a3-8f0d-0c4a9d2b7d1e) |
| LTSC | 2025-09 OOB | 2025-09-22 | 26100.6588 | [KB5068221](https://support.microsoft.com/topic/september-22-2025-kb5068221-os-build-26100-6588-out-of-band-b6d4bce9-2976-4b1d-979b-d41967aca840) |
| LTSC | 2025-09 B | 2025-09-09 | 26100.6584 | [KB5065426](https://support.microsoft.com/topic/september-9-2025-kb5065426-update-for-windows-server-2025-os-build-26100-6584-6a59dc6a-1ff2-48f4-b375-81e93deee5dd) |
| LTSC | 2025-08 B | 2025-08-12 | 26100.4946 | [KB5063878](https://support.microsoft.com/en-us/topic/august-12-2025-kb5063878-update-for-windows-server-2025-os-build-26100-4946-69b2de20-e07d-404a-a19f-fd8c4ae27e0f) |
| LTSC | 2025-07 OOB | 2025-07-13 | 26100.4656 | [KB5064489](https://support.microsoft.com/topic/july-13-2025-kb5064489-os-build-26100-4656-out-of-band-6d701323-0247-482a-98ae-6b23032fa45f) |
| LTSC | 2025-07 B | 2025-07-08 | 26100.4652 | [KB5062553](https://support.microsoft.com/topic/july-8-2025-kb5062553-os-build-26100-4652-0e8c636a-7712-4936-9c76-ece21a38cf9a) |
| LTSC | 2025-06 B | 2025-06-10 | 26100.4349 | [KB5060842](https://support.microsoft.com/topic/june-10-2025-kb5060842-os-build-26100-4349-d7d4793c-bb41-4e4a-bfbd-a0dbdb2f6055) |
| LTSC | 2025-05 OOB | 2025-05-27 | 26100.4066 | [KB5061977](https://support.microsoft.com/topic/may-27-2025-kb5061977-os-build-26100-4066-out-of-band-80725b43-c0a1-48a4-9b82-058efffb6228) |
| LTSC | 2025-05 B | 2025-05-13 | 26100.4061 | [KB5058411](https://support.microsoft.com/topic/may-13-2025-kb5058411-os-build-26100-4061-57181688-a692-49e5-b6cd-6e3919da12ca) |
| LTSC | 2025-04 OOB | 2025-04-16 | 26100.3781 | [KB5059087](https://support.microsoft.com/topic/april-16-2025-kb5059087-os-build-26100-3781-out-of-band-28af76fc-36e5-49bc-9447-201cfadd9d97) |
| LTSC | 2025-04 B | 2025-04-08 | 26100.3775 | [KB5055523](https://support.microsoft.com/topic/april-8-2025-kb5055523-os-build-26100-3775-348facce-4988-4c6a-8cb9-50cab59fd385) |
| LTSC | 2025-03 B | 2025-03-11 | 26100.3476 | [KB5053598](https://support.microsoft.com/topic/march-11-2025-kb5053598-os-build-26100-3476-183947b8-4a0c-429a-8c6a-3f0d1b4f02f3) |
| LTSC | 2025-02 B | 2025-02-11 | 26100.3194 | [KB5051987](https://support.microsoft.com/topic/february-11-2025-kb5051987-os-build-26100-3194-6cc1a435-9c1a-42b8-8c4d-b34253784452) |
| LTSC | 2025-01 B | 2025-01-14 | 26100.2894 | [KB5050009](https://support.microsoft.com/topic/january-14-2025-kb5050009-os-build-26100-2894-d78f27bc-6405-461f-a525-2d1dc4e45759) |
| LTSC | 2024-12 B | 2024-12-10 | 26100.2605 | [KB5048667](https://support.microsoft.com/topic/december-10-2024-kb5048667-os-build-26100-2605-eb529853-d3a2-4c8d-bd0b-5fc6becb629c) |
| LTSC | 2024-11 B | 2024-11-12 | 26100.2314 | [KB5046617](https://support.microsoft.com/topic/november-12-2024-kb5046617-os-build-26100-2314-701f76d0-1127-43f5-a554-f562a940bc17) |
| LTSC | 2024-10 A | 2024-11-01 | 26100.1742 |  |

**Windows Server 2022 (OS build 20348)**

| Servicing option | Update type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- |
| LTSC | 2026-05 B | 2026-05-12 | 20348.5139 | [KB5087545](https://support.microsoft.com/topic/may-12-2026-kb5087545-os-build-20348-5139-6aed2a73-37f9-468c-8bdc-4bae674797cf) |
| LTSC | 2026-04 OOB | 2026-04-19 | 20348.5024 | [KB5091575](https://support.microsoft.com/help/5091575) |
| LTSC | 2026-04 B | 2026-04-14 | 20348.5020 | [KB5082142](https://support.microsoft.com/help/5082142) |
| LTSC | 2026-03 B | 2026-03-10 | 20348.4893 | [KB5078766](https://support.microsoft.com/help/5078766) |
| LTSC | 2026-02 OOB | 2026-03-02 | 20348.4776 | [KB5082314](https://support.microsoft.com/help/5082314) |
| LTSC | 2026-02 B | 2026-02-10 | 20348.4773 | [KB5075906](https://support.microsoft.com/help/5075906) |
| LTSC | 2026-01 OOB | 2026-01-24 | 20348.4651 | [KB5078136](https://support.microsoft.com/help/5078136) |
| LTSC | 2026-01 OOB | 2026-01-17 | 20348.4650 | [KB5077800](https://support.microsoft.com/help/5077800) |
| LTSC | 2026-01 B | 2026-01-13 | 20348.4648 | [KB5073457](https://support.microsoft.com/help/5073457) |
| LTSC | 2025-12 B | 2025-12-09 | 20348.4529 | [KB5071547](https://support.microsoft.com/help/5071547) |
| LTSC | 2025-11 B | 2025-11-11 | 20348.4405 | [KB5068787](https://support.microsoft.com/help/5068787) |
| LTSC | 2025-10 OOB | 2025-10-23 | 20348.4297 | [KB5070884](https://support.microsoft.com/help/5070884) |
| LTSC | 2025-10 B | 2025-10-14 | 20348.4294 | [KB5066782](https://support.microsoft.com/help/5066782) |
| LTSC | 2025-09 B | 2025-09-09 | 20348.4171 | [KB5065432](https://support.microsoft.com/help/5065432) |
| LTSC | 2025-08 B | 2025-08-12 | 20348.4052 | [KB5063880](https://support.microsoft.com/help/5063880) |
| LTSC | 2025-07 B | 2025-07-08 | 20348.3932 | [KB5062572](https://support.microsoft.com/help/5062572) |
| LTSC | 2025-06 B | 2025-06-10 | 20348.3807 | [KB5060526](https://support.microsoft.com/help/5060526) |
| LTSC | 2025-05 OOB | 2025-05-23 | 20348.3695 | [KB5061906](https://support.microsoft.com/help/5061906) |
| LTSC | 2025-05 B | 2025-05-13 | 20348.3692 | [KB5058385](https://support.microsoft.com/help/5058385) |
| LTSC | 2025-04 OOB | 2025-04-16 | 20348.3566 | [KB5059092](https://support.microsoft.com/help/5059092) |
| LTSC | 2025-04 OOB | 2025-04-11 | 20348.3561 | [KB5058920](https://support.microsoft.com/help/5058920) |
| LTSC | 2025-04 B | 2025-04-08 | 20348.3453 | [KB5055526](https://support.microsoft.com/help/5055526) |
| LTSC | 2025-03 B | 2025-03-11 | 20348.3328 | [KB5053603](https://support.microsoft.com/help/5053603) |
| LTSC | 2025-02 B | 2025-02-11 | 20348.3207 | [KB5051979](https://support.microsoft.com/help/5051979) |
| LTSC | 2025-01 OOB | 2025-01-18 | 20348.3095 | [KB5052819](https://support.microsoft.com/help/5052819) |
| LTSC | 2025-01 B | 2025-01-14 | 20348.3091 | [KB5049983](https://support.microsoft.com/help/5049983) |
| LTSC | 2024-12 B | 2024-12-10 | 20348.2966 | [KB5048654](https://support.microsoft.com/help/5048654) |
| LTSC | 2024-11 B | 2024-11-12 | 20348.2849 | [KB5046616](https://support.microsoft.com/help/5046616) |
| LTSC | 2024-10 B | 2024-10-08 | 20348.2762 | [KB5044281](https://support.microsoft.com/help/5044281) |
| LTSC | 2024-09 B | 2024-09-10 | 20348.2700 | [KB5042881](https://support.microsoft.com/help/5042881) |
| LTSC | 2024-08 B | 2024-08-13 | 20348.2655 | [KB5041160](https://support.microsoft.com/help/5041160) |
| LTSC | 2024-07 B | 2024-07-09 | 20348.2582 | [KB5040437](https://support.microsoft.com/help/5040437) |
| LTSC | 2024-06 OOB | 2024-06-20 | 20348.2529 | [KB5041054](https://support.microsoft.com/help/5041054) |
| LTSC | 2024-06 B | 2024-06-11 | 20348.2527 | [KB5039227](https://support.microsoft.com/help/5039227) |
| LTSC | 2024-05 B | 2024-05-14 | 20348.2461 | [KB5037782](https://support.microsoft.com/help/5037782) |
| LTSC | 2024-04 B | 2024-04-09 | 20348.2402 | [KB5036909](https://support.microsoft.com/help/5036909) |
| LTSC | 2024-03 OOB | 2024-03-22 | 20348.2342 | [KB5037422](https://support.microsoft.com/help/5037422) |
| LTSC | 2024-03 B | 2024-03-12 | 20348.2340 | [KB5035857](https://support.microsoft.com/help/5035857) |
| LTSC | 2024-02 B | 2024-02-13 | 20348.2322 | [KB5034770](https://support.microsoft.com/help/5034770) |
| LTSC | 2024-01 B | 2024-01-09 | 20348.2227 | [KB5034129](https://support.microsoft.com/help/5034129) |
| LTSC | 2023-12 B | 2023-12-12 | 20348.2159 | [KB5033118](https://support.microsoft.com/help/5033118) |
| LTSC | 2023-11 B | 2023-11-14 | 20348.2113 | [KB5032198](https://support.microsoft.com/help/5032198) |
| LTSC | 2023-10 B | 2023-10-10 | 20348.2031 | [KB5031364](https://support.microsoft.com/help/5031364) |
| LTSC | 2023-09 B | 2023-09-12 | 20348.1970 | [KB5030216](https://support.microsoft.com/help/5030216) |
| LTSC | 2023-08 B | 2023-08-08 | 20348.1906 | [KB5029250](https://support.microsoft.com/help/5029250) |
| LTSC | 2023-07 B | 2023-07-11 | 20348.1850 | [KB5028171](https://support.microsoft.com/help/5028171) |
| LTSC | 2023-06 B | 2023-06-13 | 20348.1787 | [KB5027225](https://support.microsoft.com/help/5027225) |
| LTSC | 2023-05 B | 2023-05-09 | 20348.1726 | [KB5026370](https://support.microsoft.com/help/5026370) |
| LTSC | 2023-04 B | 2023-04-11 | 20348.1668 | [KB5025230](https://support.microsoft.com/help/5025230) |
| LTSC | 2023-03 B | 2023-03-14 | 20348.1607 | [KB5023705](https://support.microsoft.com/help/5023705) |
| LTSC | 2023-02 B | 2023-02-14 | 20348.1547 | [KB5022842](https://support.microsoft.com/help/5022842) |
| LTSC | 2023-01 B | 2023-01-10 | 20348.1487 | [KB5022291](https://support.microsoft.com/help/5022291) |
| LTSC | 2022-12 OOB | 2022-12-20 | 20348.1368 | [KB5022553](https://support.microsoft.com/help/5022553) |
| LTSC | 2022-12 B | 2022-12-13 | 20348.1366 | [KB5021249](https://support.microsoft.com/help/5021249) |
| LTSC | 2022-11 C | 2022-11-22 | 20348.1311 | [KB5020032](https://support.microsoft.com/help/5020032) |
| LTSC | 2022-11 OOB | 2022-11-17 | 20348.1251 | [KB5021656](https://support.microsoft.com/help/5021656) |
| LTSC | 2022-11 B | 2022-11-08 | 20348.1249 | [KB5019081](https://support.microsoft.com/help/5019081) |
| LTSC | 2022-10 C | 2022-10-25 | 20348.1194 | [KB5018485](https://support.microsoft.com/help/5018485) |
| LTSC | 2022-10 OOB | 2022-10-17 | 20348.1131 | [KB5020436](https://support.microsoft.com/help/5020436) |
| LTSC | 2022-10 B | 2022-10-11 | 20348.1129 | [KB5018421](https://support.microsoft.com/help/5018421) |
| LTSC | 2022-09 C | 2022-09-20 | 20348.1070 | [KB5017381](https://support.microsoft.com/help/5017381) |
| LTSC | 2022-09 B | 2022-09-13 | 20348.1006 | [KB5017316](https://support.microsoft.com/help/5017316) |
| LTSC | 2022-08 C | 2022-08-16 | 20348.946 | [KB5016693](https://support.microsoft.com/help/5016693) |
| LTSC | 2022-08 B | 2022-08-09 | 20348.887 | [KB5016627](https://support.microsoft.com/help/5016627) |
| LTSC | 2022-07 C | 2022-07-19 | 20348.859 | [KB5015879](https://support.microsoft.com/help/5015879) |
| LTSC | 2022-07 B | 2022-07-12 | 20348.825 | [KB5015827](https://support.microsoft.com/help/5015827) |
| LTSC | 2022-06 C | 2022-06-23 | 20348.803 | [KB5014665](https://support.microsoft.com/help/5014665) |
| LTSC | 2022-06 B | 2022-06-14 | 20348.768 | [KB5014678](https://support.microsoft.com/help/5014678) |
| LTSC | 2022-05 C | 2022-05-24 | 20348.740 | [KB5014021](https://support.microsoft.com/help/5014021) |
| LTSC | 2022-05 OOB | 2022-05-19 | 20348.709 | [KB5015013](https://support.microsoft.com/help/5015013) |
| LTSC | 2022-05 B | 2022-05-10 | 20348.707 | [KB5013944](https://support.microsoft.com/help/5013944) |
| LTSC | 2022-04 C | 2022-04-25 | 20348.681 | [KB5012637](https://support.microsoft.com/help/5012637) |
| LTSC | 2022-04 B | 2022-04-12 | 20348.643 | [KB5012604](https://support.microsoft.com/help/5012604) |
| LTSC | 2022-03 C | 2022-03-22 | 20348.617 | [KB5011558](https://support.microsoft.com/help/5011558) |
| LTSC | 2022-03 B | 2022-03-08 | 20348.587 | [KB5011497](https://support.microsoft.com/help/5011497) |
| LTSC | 2022-02 C | 2022-02-15 | 20348.558 | [KB5010421](https://support.microsoft.com/help/5010421) |
| LTSC | 2022-02 B | 2022-02-08 | 20348.524 | [KB5010354](https://support.microsoft.com/help/5010354) |
| LTSC | 2022-01 C | 2022-01-25 | 20348.502 | [KB5009608](https://support.microsoft.com/help/5009608) |
| LTSC | 2022-01 OOB | 2022-01-17 | 20348.473 | [KB5010796](https://support.microsoft.com/help/5010796) |
| LTSC | 2022-01 B | 2022-01-11 | 20348.469 | [KB5009555](https://support.microsoft.com/help/5009555) |
| LTSC | 2022-01 OOB | 2022-01-05 | 20348.407 | [KB5010197](https://support.microsoft.com/help/5010197) |
| LTSC | 2021-12 B | 2021-12-14 | 20348.405 | [KB5008223](https://support.microsoft.com/help/5008223) |
| LTSC | 2021-11 C | 2021-11-22 | 20348.380 | [KB5007254](https://support.microsoft.com/help/5007254) |
| LTSC | 2021-11 B | 2021-11-09 | 20348.350 | [KB5007205](https://support.microsoft.com/help/5007205) |
| LTSC | 2021-10 C | 2021-10-26 | 20348.320 | [KB5006745](https://support.microsoft.com/help/5006745) |
| LTSC | 2021-10 B | 2021-10-12 | 20348.288 | [KB5006699](https://support.microsoft.com/help/5006699) |
| LTSC | 2021-09 C | 2021-09-27 | 20348.261 | [KB5005619](https://support.microsoft.com/help/5005619) |
| LTSC | 2021-09 B | 2021-09-14 | 20348.230 | [KB5005575](https://support.microsoft.com/help/5005575) |
| LTSC | 2021-08 C | 2021-08-26 | 20348.202 | [KB5005104](https://support.microsoft.com/help/5005104) |

**Windows Server 2019 (OS build 17763)**

| Servicing option | Update type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- |
| LTSC | 2026-05 B | 2026-05-12 | 17763.8755 | [KB5087538](https://support.microsoft.com/help/5087538) |
| LTSC | 2026-04 OOB | 2026-04-19 | 17763.8647 | [KB5091573](https://support.microsoft.com/help/5091573) |
| LTSC | 2026-04 B | 2026-04-14 | 17763.8644 | [KB5082123](https://support.microsoft.com/help/5082123) |
| LTSC | 2026-03 B | 2026-03-10 | 17763.8511 | [KB5078752](https://support.microsoft.com/help/5078752) |
| LTSC | 2026-02 B | 2026-02-10 | 17763.8389 | [KB5075904](https://support.microsoft.com/help/5075904) |
| LTSC | 2026-01 OOB | 2026-01-24 | 17763.8281 | [KB5078131](https://support.microsoft.com/help/5078131) |
| LTSC | 2026-01 OOB | 2026-01-17 | 17763.8280 | [KB5077795](https://support.microsoft.com/help/5077795) |
| LTSC | 2026-01 B | 2026-01-13 | 17763.8276 | [KB5073723](https://support.microsoft.com/help/5073723) |
| LTSC | 2025-12 OOB | 2025-12-18 | 17763.8148 | [KB5074975](https://support.microsoft.com/help/5074975) |
| LTSC | 2025-12 B | 2025-12-09 | 17763.8146 | [KB5071544](https://support.microsoft.com/help/5071544) |
| LTSC | 2025-11 B | 2025-11-11 | 17763.8027 | [KB5068791](https://support.microsoft.com/help/5068791) |
| LTSC | 2025-10 OOB | 2025-10-23 | 17763.7922 | [KB5070883](https://support.microsoft.com/help/5070883) |
| LTSC | 2025-10 B | 2025-10-14 | 17763.7919 | [KB5066586](https://support.microsoft.com/help/5066586) |
| LTSC | 2025-09 B | 2025-09-09 | 17763.7792 | [KB5065428](https://support.microsoft.com/help/5065428) |
| LTSC | 2025-08 OOB | 2025-08-19 | 17763.7683 | [KB5066187](https://support.microsoft.com/help/5066187) |
| LTSC | 2025-08 B | 2025-08-12 | 17763.7678 | [KB5063877](https://support.microsoft.com/help/5063877) |
| LTSC | 2025-07 B | 2025-07-08 | 17763.7558 | [KB5062557](https://support.microsoft.com/help/5062557) |
| LTSC | 2025-06 B | 2025-06-10 | 17763.7434 | [KB5060531](https://support.microsoft.com/help/5060531) |
| LTSC | 2025-05 OOB | 2025-05-27 | 17763.7322 | [KB5061978](https://support.microsoft.com/help/5061978) |
| LTSC | 2025-05 B | 2025-05-13 | 17763.7314 | [KB5058392](https://support.microsoft.com/help/5058392) |
| LTSC | 2025-04 OOB | 2025-04-16 | 17763.7249 | [KB5059091](https://support.microsoft.com/help/5059091) |
| LTSC | 2025-04 OOB | 2025-04-11 | 17763.7240 | [KB5058922](https://support.microsoft.com/help/5058922) |
| LTSC | 2025-04 B | 2025-04-08 | 17763.7136 | [KB5055519](https://support.microsoft.com/help/5055519) |
| LTSC | 2025-03 B | 2025-03-11 | 17763.7009 | [KB5053596](https://support.microsoft.com/help/5053596) |
| LTSC | 2025-02 B | 2025-02-11 | 17763.6893 | [KB5052000](https://support.microsoft.com/help/5052000) |
| LTSC | 2025-01 B | 2025-01-14 | 17763.6775 | [KB5050008](https://support.microsoft.com/help/5050008) |
| LTSC | 2024-12 B | 2024-12-10 | 17763.6659 | [KB5048661](https://support.microsoft.com/help/5048661) |
| LTSC | 2024-11 B | 2024-11-12 | 17763.6532 | [KB5046615](https://support.microsoft.com/help/5046615) |
| LTSC | 2024-10 B | 2024-10-08 | 17763.6414 | [KB5044277](https://support.microsoft.com/help/5044277) |
| LTSC | 2024-09 B | 2024-09-10 | 17763.6293 | [KB5043050](https://support.microsoft.com/help/5043050) |
| LTSC | 2024-08 B | 2024-08-13 | 17763.6189 | [KB5041578](https://support.microsoft.com/help/5041578) |
| LTSC | 2024-07 B | 2024-07-09 | 17763.6054 | [KB5040430](https://support.microsoft.com/help/5040430) |
| LTSC | 2024-06 B | 2024-06-11 | 17763.5936 | [KB5039217](https://support.microsoft.com/help/5039217) |
| LTSC | 2024-05 OOB | 2024-05-23 | 17763.5830 | [KB5039705](https://support.microsoft.com/help/5039705) |
| LTSC | 2024-05 B | 2024-05-14 | 17763.5820 | [KB5037765](https://support.microsoft.com/help/5037765) |
| LTSC | 2024-04 B | 2024-04-09 | 17763.5696 | [KB5036896](https://support.microsoft.com/help/5036896) |
| LTSC | 2024-03 OOB | 2024-03-25 | 17763.5579 | [KB5037425](https://support.microsoft.com/help/5037425) |
| LTSC | 2024-03 B | 2024-03-12 | 17763.5576 | [KB5035849](https://support.microsoft.com/help/5035849) |
| LTSC | 2024-02 B | 2024-02-13 | 17763.5458 | [KB5034768](https://support.microsoft.com/help/5034768) |
| LTSC | 2024-01 B | 2024-01-09 | 17763.5329 | [KB5034127](https://support.microsoft.com/help/5034127) |
| LTSC | 2023-12 B | 2023-12-12 | 17763.5206 | [KB5033371](https://support.microsoft.com/help/5033371) |
| LTSC | 2023-11 B | 2023-11-14 | 17763.5122 | [KB5032196](https://support.microsoft.com/help/5032196) |
| LTSC | 2023-10 B | 2023-10-10 | 17763.4974 | [KB5031361](https://support.microsoft.com/help/5031361) |
| LTSC | 2023-09 B | 2023-09-12 | 17763.4851 | [KB5030214](https://support.microsoft.com/help/5030214) |
| LTSC | 2023-08 B | 2023-08-08 | 17763.4737 | [KB5029247](https://support.microsoft.com/help/5029247) |
| LTSC | 2023-07 B | 2023-07-11 | 17763.4645 | [KB5028168](https://support.microsoft.com/help/5028168) |
| LTSC | 2023-06 B | 2023-06-13 | 17763.4499 | [KB5027222](https://support.microsoft.com/help/5027222) |
| LTSC | 2023-05 B | 2023-05-09 | 17763.4377 | [KB5026362](https://support.microsoft.com/help/5026362) |
| LTSC | 2023-04 B | 2023-04-11 | 17763.4252 | [KB5025229](https://support.microsoft.com/help/5025229) |
| LTSC | 2023-03 B | 2023-03-14 | 17763.4131 | [KB5023702](https://support.microsoft.com/help/5023702) |
| LTSC | 2023-02 B | 2023-02-14 | 17763.4010 | [KB5022840](https://support.microsoft.com/help/5022840) |
| LTSC | 2023-01 B | 2023-01-10 | 17763.3887 | [KB5022286](https://support.microsoft.com/help/5022286) |
| LTSC | 2022-12 OOB | 2022-12-20 | 17763.3772 | [KB5022554](https://support.microsoft.com/help/5022554) |
| LTSC | 2022-12 B | 2022-12-13 | 17763.3770 | [KB5021237](https://support.microsoft.com/help/5021237) |
| LTSC | 2022-11 OOB | 2022-11-17 | 17763.3653 | [KB5021655](https://support.microsoft.com/help/5021655) |
| LTSC | 2022-11 B | 2022-11-08 | 17763.3650 | [KB5019966](https://support.microsoft.com/help/5019966) |
| LTSC | 2022-10 OOB | 2022-10-17 | 17763.3534 | [KB5020438](https://support.microsoft.com/help/5020438) |
| LTSC | 2022-10 B | 2022-10-11 | 17763.3532 | [KB5018419](https://support.microsoft.com/help/5018419) |
| LTSC | 2022-09 C | 2022-09-20 | 17763.3469 | [KB5017379](https://support.microsoft.com/help/5017379) |
| LTSC | 2022-09 B | 2022-09-13 | 17763.3406 | [KB5017315](https://support.microsoft.com/help/5017315) |
| LTSC | 2022-08 C | 2022-08-23 | 17763.3346 | [KB5016690](https://support.microsoft.com/help/5016690) |
| LTSC | 2022-08 B | 2022-08-09 | 17763.3287 | [KB5016623](https://support.microsoft.com/help/5016623) |
| LTSC | 2022-07 C | 2022-07-21 | 17763.3232 | [KB5015880](https://support.microsoft.com/help/5015880) |
| LTSC | 2022-07 B | 2022-07-12 | 17763.3165 | [KB5015811](https://support.microsoft.com/help/5015811) |
| LTSC | 2022-06 C | 2022-06-23 | 17763.3113 | [KB5014669](https://support.microsoft.com/help/5014669) |
| LTSC | 2022-06 B | 2022-06-14 | 17763.3046 | [KB5014692](https://support.microsoft.com/help/5014692) |
| LTSC | 2022-05 C | 2022-05-24 | 17763.2989 | [KB5014022](https://support.microsoft.com/help/5014022) |
| LTSC | 2022-05 OOB | 2022-05-19 | 17763.2931 | [KB5015018](https://support.microsoft.com/help/5015018) |
| LTSC | 2022-05 B | 2022-05-10 | 17763.2928 | [KB5013941](https://support.microsoft.com/help/5013941) |
| LTSC | 2022-04 C | 2022-04-21 | 17763.2867 | [KB5012636](https://support.microsoft.com/help/5012636) |
| LTSC | 2022-04 B | 2022-04-12 | 17763.2803 | [KB5012647](https://support.microsoft.com/help/5012647) |
| LTSC | 2022-03 C | 2022-03-22 | 17763.2746 | [KB5011551](https://support.microsoft.com/help/5011551) |
| LTSC | 2022-03 B | 2022-03-08 | 17763.2686 | [KB5011503](https://support.microsoft.com/help/5011503) |
| LTSC | 2022-02 C | 2022-02-15 | 17763.2628 | [KB5010427](https://support.microsoft.com/help/5010427) |
| LTSC | 2022-02 B | 2022-02-08 | 17763.2565 | [KB5010351](https://support.microsoft.com/help/5010351) |
| LTSC | 2022-01 C | 2022-01-25 | 17763.2510 | [KB5009616](https://support.microsoft.com/help/5009616) |
| LTSC | 2022-01 OOB | 2022-01-18 | 17763.2458 | [KB5010791](https://support.microsoft.com/help/5010791) |
| LTSC | 2022-01 B | 2022-01-11 | 17763.2452 | [KB5009557](https://support.microsoft.com/help/5009557) |
| LTSC | 2022-01 OOB | 2022-01-04 | 17763.2369 | [KB5010196](https://support.microsoft.com/help/5010196) |
| LTSC | 2021-12 B | 2021-12-14 | 17763.2366 | [KB5008218](https://support.microsoft.com/help/5008218) |
| LTSC | 2021-11 C | 2021-11-22 | 17763.2330 | [KB5007266](https://support.microsoft.com/help/5007266) |
| LTSC | 2021-11 OOB | 2021-11-14 | 17763.2305 | [KB5008602](https://support.microsoft.com/help/5008602) |
| LTSC | 2021-11 B | 2021-11-09 | 17763.2300 | [KB5007206](https://support.microsoft.com/help/5007206) |
| LTSC | 2021-10 C | 2021-10-19 | 17763.2268 | [KB5006744](https://support.microsoft.com/help/5006744) |
| LTSC | 2021-10 B | 2021-10-12 | 17763.2237 | [KB5006672](https://support.microsoft.com/help/5006672) |
| LTSC | 2021-09 C | 2021-09-21 | 17763.2213 | [KB5005625](https://support.microsoft.com/help/5005625) |
| LTSC | 2021-09 B | 2021-09-14 | 17763.2183 | [KB5005568](https://support.microsoft.com/help/5005568) |
| LTSC | 2021-08 C | 2021-08-26 | 17763.2145 | [KB5005102](https://support.microsoft.com/help/5005102) |
| LTSC | 2021-08 B | 2021-08-10 | 17763.2114 | [KB5005030](https://support.microsoft.com/help/5005030) |
| LTSC | 2021-07 OOB | 2021-07-27 | 17763.2091 | [KB5005394](https://support.microsoft.com/help/5005394) |
| LTSC | 2021-07 C | 2021-07-20 | 17763.2090 | [KB5004308](https://support.microsoft.com/help/5004308) |
| LTSC | 2021-07 B | 2021-07-13 | 17763.2061 | [KB5004244](https://support.microsoft.com/help/5004244) |
| LTSC | 2021-07 OOB | 2021-07-06 | 17763.2029 | [KB5004947](https://support.microsoft.com/help/5004947) |
| LTSC | 2021-06 C | 2021-06-15 | 17763.2028 | [KB5003703](https://support.microsoft.com/help/5003703) |
| LTSC | 2021-06 B | 2021-06-08 | 17763.1999 | [KB5003646](https://support.microsoft.com/help/5003646) |
| LTSC | 2021-05 C | 2021-05-20 | 17763.1971 | [KB5003217](https://support.microsoft.com/help/5003217) |
| LTSC | 2021-05 B | 2021-05-11 | 17763.1935 | [KB5003171](https://support.microsoft.com/help/5003171) |
| LTSC | 2021-04 C | 2021-04-22 | 17763.1911 | [KB5001384](https://support.microsoft.com/help/5001384) |
| LTSC | 2021-04 B | 2021-04-13 | 17763.1879 | [KB5001342](https://support.microsoft.com/help/5001342) |
| LTSC | 2021-03 C | 2021-03-25 | 17763.1852 | [KB5000854](https://support.microsoft.com/help/5000854) |
| LTSC | 2021-03 OOB | 2021-03-18 | 17763.1823 | [KB5001638](https://support.microsoft.com/help/5001638) |
| LTSC | 2021-03 OOB | 2021-03-15 | 17763.1821 | [KB5001568](https://support.microsoft.com/help/5001568) |
| LTSC | 2021-03 B | 2021-03-09 | 17763.1817 | [KB5000822](https://support.microsoft.com/help/5000822) |
| LTSC | 2021-02 C | 2021-02-16 | 17763.1790 | [KB4601383](https://support.microsoft.com/help/4601383) |
| LTSC | 2021-02 B | 2021-02-09 | 17763.1757 | [KB4601345](https://support.microsoft.com/help/4601345) |
| LTSC | 2021-01 C | 2021-01-21 | 17763.1728 | [KB4598296](https://support.microsoft.com/help/4598296) |
| LTSC | 2021-01 B | 2021-01-12 | 17763.1697 | [KB4598230](https://support.microsoft.com/help/4598230) |
| LTSC | 2020-12 B | 2020-12-08 | 17763.1637 | [KB4592440](https://support.microsoft.com/help/4592440) |
| LTSC | 2020-11 C | 2020-11-19 | 17763.1613 | [KB4586839](https://support.microsoft.com/help/4586839) |
| LTSC | 2020-11 OOB | 2020-11-17 | 17763.1579 | [KB4594442](https://support.microsoft.com/help/4594442) |
| LTSC | 2020-11 B | 2020-11-10 | 17763.1577 | [KB4586793](https://support.microsoft.com/help/4586793) |
| LTSC | 2020-10 C | 2020-10-20 | 17763.1554 | [KB4580390](https://support.microsoft.com/help/4580390) |
| LTSC | 2020-10 B | 2020-10-13 | 17763.1518 | [KB4577668](https://support.microsoft.com/help/4577668) |
| LTSC | 2020-09 C | 2020-09-16 | 17763.1490 | [KB4577069](https://support.microsoft.com/help/4577069) |
| LTSC | 2020-09 B | 2020-09-08 | 17763.1457 | [KB4570333](https://support.microsoft.com/help/4570333) |
| LTSC | 2020-08 C | 2020-08-20 | 17763.1432 | [KB4571748](https://support.microsoft.com/help/4571748) |
| LTSC | 2020-08 B | 2020-08-11 | 17763.1397 | [KB4565349](https://support.microsoft.com/help/4565349) |
| LTSC | 2020-07 C | 2020-07-21 | 17763.1369 | [KB4559003](https://support.microsoft.com/help/4559003) |
| LTSC | 2020-07 B | 2020-07-14 | 17763.1339 | [KB4558998](https://support.microsoft.com/help/4558998) |
| LTSC | 2020-06 OOB | 2020-06-16 | 17763.1294 | [KB4567513](https://support.microsoft.com/help/4567513) |
| LTSC | 2020-06 B | 2020-06-09 | 17763.1282 | [KB4561608](https://support.microsoft.com/help/4561608) |
| LTSC | 2020-05 B | 2020-05-12 | 17763.1217 | [KB4551853](https://support.microsoft.com/help/4551853) |
| LTSC | 2020-04 C | 2020-04-21 | 17763.1192 | [KB4550969](https://support.microsoft.com/help/4550969) |
| LTSC | 2020-04 B | 2020-04-14 | 17763.1158 | [KB4549949](https://support.microsoft.com/help/4549949) |
| LTSC | 2020-03 OOB | 2020-03-30 | 17763.1132 | [KB4554354](https://support.microsoft.com/help/4554354) |
| LTSC | 2020-03 C | 2020-03-17 | 17763.1131 | [KB4541331](https://support.microsoft.com/help/4541331) |
| LTSC | 2020-03 B | 2020-03-10 | 17763.1098 | [KB4538461](https://support.microsoft.com/help/4538461) |
| LTSC | 2020-02 C | 2020-02-25 | 17763.1075 | [KB4537818](https://support.microsoft.com/help/4537818) |
| LTSC | 2020-02 B | 2020-02-11 | 17763.1039 | [KB4532691](https://support.microsoft.com/help/4532691) |
| LTSC | 2020-01 C | 2020-01-23 | 17763.1012 | [KB4534321](https://support.microsoft.com/help/4534321) |
| LTSC | 2020-01 B | 2020-01-14 | 17763.973 | [KB4534273](https://support.microsoft.com/help/4534273) |
| LTSC | 2019-12 B | 2019-12-10 | 17763.914 | [KB4530715](https://support.microsoft.com/help/4530715) |
| LTSC | 2019-11 B | 2019-11-12 | 17763.864 | [KB4523205](https://support.microsoft.com/help/4523205) |
| LTSC | 2019-10 C | 2019-10-15 | 17763.832 | [KB4520062](https://support.microsoft.com/help/4520062) |
| LTSC | 2019-10 B | 2019-10-08 | 17763.805 | [KB4519338](https://support.microsoft.com/help/4519338) |
| LTSC | 2019-09 OOB | 2019-10-03 | 17763.775 | [KB4524148](https://support.microsoft.com/help/4524148) |
| LTSC | 2019-09 C | 2019-09-24 | 17763.774 | [KB4516077](https://support.microsoft.com/help/4516077) |
| LTSC | 2019-09 OOB | 2019-09-23 | 17763.740 | [KB4522015](https://support.microsoft.com/help/4522015) |
| LTSC | 2019-09 B | 2019-09-10 | 17763.737 | [KB4512578](https://support.microsoft.com/help/4512578) |
| LTSC | 2019-08 C | 2019-08-17 | 17763.720 | [KB4512534](https://support.microsoft.com/help/4512534) |
| LTSC | 2019-08 B | 2019-08-13 | 17763.678 | [KB4511553](https://support.microsoft.com/help/4511553) |
| LTSC | 2019-07 C | 2019-07-22 | 17763.652 | [KB4505658](https://support.microsoft.com/help/4505658) |
| LTSC | 2019-07 B | 2019-07-09 | 17763.615 | [KB4507469](https://support.microsoft.com/help/4507469) |
| LTSC | 2019-06 OOB | 2019-06-26 | 17763.593 | [KB4509479](https://support.microsoft.com/help/4509479) |
| LTSC | 2019-06 C | 2019-06-18 | 17763.592 | [KB4501371](https://support.microsoft.com/help/4501371) |
| LTSC | 2019-06 B | 2019-06-11 | 17763.557 | [KB4503327](https://support.microsoft.com/help/4503327) |
| LTSC | 2019-05 C | 2019-05-21 | 17763.529 | [KB4497934](https://support.microsoft.com/help/4497934) |
| LTSC | 2019-05 OOB | 2019-05-19 | 17763.504 | [KB4505056](https://support.microsoft.com/help/4505056) |
| LTSC | 2019-05 B | 2019-05-14 | 17763.503 | [KB4494441](https://support.microsoft.com/help/4494441) |
| LTSC | 2019-04 C | 2019-05-03 | 17763.475 | [KB4495667](https://support.microsoft.com/help/4495667) |
| LTSC | 2019-04 OOB | 2019-05-01 | 17763.439 | [KB4501835](https://support.microsoft.com/help/4501835) |
| LTSC | 2019-04 B | 2019-04-09 | 17763.437 | [KB4493509](https://support.microsoft.com/help/4493509) |
| LTSC | 2019-03 D | 2019-04-02 | 17763.404 | [KB4490481](https://support.microsoft.com/help/4490481) |
| LTSC | 2019-03 B | 2019-03-12 | 17763.379 | [KB4489899](https://support.microsoft.com/help/4489899) |
| LTSC | 2019-02 D | 2019-03-01 | 17763.348 | [KB4482887](https://support.microsoft.com/help/4482887) |
| LTSC | 2019-02 B | 2019-02-12 | 17763.316 | [KB4487044](https://support.microsoft.com/help/4487044) |
| LTSC | 2019-01 D | 2019-01-22 | 17763.292 | [KB4476976](https://support.microsoft.com/help/4476976) |
| LTSC | 2019-01 B | 2019-01-08 | 17763.253 | [KB4480116](https://support.microsoft.com/help/4480116) |
| LTSC | 2018-12 OOB | 2018-12-19 | 17763.195 | [KB4483235](https://support.microsoft.com/help/4483235) |
| LTSC | 2018-12 B | 2018-12-11 | 17763.194 | [KB4471332](https://support.microsoft.com/help/4471332) |
| LTSC | 2018-11 D | 2018-12-05 | 17763.168 | [KB4469342](https://support.microsoft.com/help/4469342) |
| LTSC | 2018-11 B | 2018-11-13 | 17763.134 | [KB4467708](https://support.microsoft.com/help/4467708) |
| LTSC | 2018-10 D | 2018-11-13 | 17763.107 | [KB4464455](https://support.microsoft.com/help/4464455) |
| LTSC | 2018-10 B | 2018-10-09 | 17763.55 | [KB4464330](https://support.microsoft.com/help/4464330) |
| LTSC | 2018-10 A | 2018-10-02 | 17763.1 |  |

**Windows Server 2016 (OS build 14393)**

| Servicing option | Update type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- |
| LTSB | 2026-05 B | 2026-05-12 | 14393.9140 | [KB5087537](https://support.microsoft.com/topic/may-12-2026-kb5087537-os-build-14393-9140-2ef98591-73f0-4517-9fa0-12764b51858f) |
| LTSB | 2026-04 OOB | 2026-04-19 | 14393.9062 | [KB5091572](https://support.microsoft.com/help/5091572) |
| LTSB | 2026-04 OOB | 2026-04-19 | 14393.9062 | [KB5091572](https://support.microsoft.com/help/5091572) |
| LTSB | 2026-04 B | 2026-04-14 | 14393.9060 | [KB5082198](https://support.microsoft.com/help/5082198) |
| LTSB | 2026-03 B | 2026-03-10 | 14393.8957 | [KB5078938](https://support.microsoft.com/help/5078938) |
| LTSB | 2026-02 B | 2026-02-10 | 14393.8868 | [KB5075999](https://support.microsoft.com/help/5075999) |
| LTSB | 2026-01 B | 2026-01-13 | 14393.8783 | [KB5073722](https://support.microsoft.com/help/5073722) |
| LTSB | 2025-12 OOB | 2025-12-18 | 14393.8692 | [KB5074974](https://support.microsoft.com/help/5074974) |
| LTSB | 2025-12 B | 2025-12-09 | 14393.8688 | [KB5071543](https://support.microsoft.com/help/5071543) |
| LTSB | 2025-11 B | 2025-11-11 | 14393.8594 | [KB5068864](https://support.microsoft.com/help/5068864) |
| LTSB | 2025-10 OOB | 2025-10-23 | 14393.8524 | [KB5070882](https://support.microsoft.com/help/5070882) |
| LTSB | 2025-10 B | 2025-10-14 | 14393.8519 | [KB5066836](https://support.microsoft.com/help/5066836) |
| LTSB | 2025-09 B | 2025-09-09 | 14393.8422 | [KB5065427](https://support.microsoft.com/help/5065427) |
| LTSB | 2025-08 B | 2025-08-12 | 14393.8330 | [KB5063871](https://support.microsoft.com/help/5063871) |
| LTSB | 2025-07 B | 2025-07-08 | 14393.8246 | [KB5062560](https://support.microsoft.com/help/5062560) |
| LTSB | 2025-06 B | 2025-06-10 | 14393.8148 | [KB5061010](https://support.microsoft.com/help/5061010) |
| LTSB | 2025-05 B | 2025-05-13 | 14393.8066 | [KB5058383](https://support.microsoft.com/help/5058383) |
| LTSB | 2025-04 OOB | 2025-04-11 | 14393.7973 | [KB5058921](https://support.microsoft.com/help/5058921) |
| LTSB | 2025-04 B | 2025-04-08 | 14393.7969 | [KB5055521](https://support.microsoft.com/help/5055521) |
| LTSB | 2025-03 B | 2025-03-11 | 14393.7876 | [KB5053594](https://support.microsoft.com/help/5053594) |
| LTSB | 2025-02 B | 2025-02-11 | 14393.7785 | [KB5052006](https://support.microsoft.com/help/5052006) |
| LTSB | 2025-01 B | 2025-01-14 | 14393.7699 | [KB5049993](https://support.microsoft.com/help/5049993) |
| LTSB | 2024-12 B | 2024-12-10 | 14393.7606 | [KB5048671](https://support.microsoft.com/help/5048671) |
| LTSB | 2024-11 B | 2024-11-12 | 14393.7515 | [KB5046612](https://support.microsoft.com/help/5046612) |
| LTSB | 2024-10 B | 2024-10-08 | 14393.7428 | [KB5044293](https://support.microsoft.com/help/5044293) |
| LTSB | 2024-09 B | 2024-09-10 | 14393.7336 | [KB5043051](https://support.microsoft.com/help/5043051) |
| LTSB | 2024-08 B | 2024-08-13 | 14393.7259 | [KB5041773](https://support.microsoft.com/help/5041773) |
| LTSB | 2024-07 B | 2024-07-09 | 14393.7159 | [KB5040434](https://support.microsoft.com/help/5040434) |
| LTSB | 2024-06 B | 2024-06-11 | 14393.7070 | [KB5039214](https://support.microsoft.com/help/5039214) |
| LTSB | 2024-05 B | 2024-05-14 | 14393.6981 | [KB5037763](https://support.microsoft.com/help/5037763) |
| LTSB | 2024-04 B | 2024-04-09 | 14393.6897 | [KB5036899](https://support.microsoft.com/help/5036899) |
| LTSB | 2024-03 OOB | 2024-03-22 | 14393.6800 | [KB5037423](https://support.microsoft.com/help/5037423) |
| LTSB | 2024-03 B | 2024-03-12 | 14393.6796 | [KB5035855](https://support.microsoft.com/help/5035855) |
| LTSB | 2024-02 B | 2024-02-13 | 14393.6709 | [KB5034767](https://support.microsoft.com/help/5034767) |
| LTSB | 2024-01 B | 2024-01-09 | 14393.6614 | [KB5034119](https://support.microsoft.com/help/5034119) |
| LTSB | 2023-12 B | 2023-12-12 | 14393.6529 | [KB5033373](https://support.microsoft.com/help/5033373) |
| LTSB | 2023-11 B | 2023-11-14 | 14393.6452 | [KB5032197](https://support.microsoft.com/help/5032197) |
| LTSB | 2023-10 B | 2023-10-10 | 14393.6351 | [KB5031362](https://support.microsoft.com/help/5031362) |
| LTSB | 2023-09 B | 2023-09-12 | 14393.6252 | [KB5030213](https://support.microsoft.com/help/5030213) |
| LTSB | 2023-08 B | 2023-08-08 | 14393.6167 | [KB5029242](https://support.microsoft.com/help/5029242) |
| LTSB | 2023-07 B | 2023-07-11 | 14393.6085 | [KB5028169](https://support.microsoft.com/help/5028169) |
| LTSB | 2023-06 OOB | 2023-06-23 | 14393.5996 | [KB5028623](https://support.microsoft.com/help/5028623) |
| LTSB | 2023-06 B | 2023-06-13 | 14393.5989 | [KB5027219](https://support.microsoft.com/help/5027219) |
| LTSB | 2023-05 B | 2023-05-09 | 14393.5921 | [KB5026363](https://support.microsoft.com/help/5026363) |
| LTSB | 2023-04 B | 2023-04-11 | 14393.5850 | [KB5025228](https://support.microsoft.com/help/5025228) |
| LTSB | 2023-03 B | 2023-03-14 | 14393.5786 | [KB5023697](https://support.microsoft.com/help/5023697) |
| LTSB | 2023-02 B | 2023-02-14 | 14393.5717 | [KB5022838](https://support.microsoft.com/help/5022838) |
| LTSB | 2023-01 B | 2023-01-10 | 14393.5648 | [KB5022289](https://support.microsoft.com/help/5022289) |
| LTSB | 2022-12 B | 2022-12-13 | 14393.5582 | [KB5021235](https://support.microsoft.com/help/5021235) |
| LTSB | 2022-11 OOB | 2022-11-17 | 14393.5502 | [KB5021654](https://support.microsoft.com/help/5021654) |
| LTSB | 2022-11 B | 2022-11-08 | 14393.5501 | [KB5019964](https://support.microsoft.com/help/5019964) |
| LTSB | 2022-10 OOB | 2022-10-18 | 14393.5429 | [KB5020439](https://support.microsoft.com/help/5020439) |
| LTSB | 2022-10 B | 2022-10-11 | 14393.5427 | [KB5018411](https://support.microsoft.com/help/5018411) |
| LTSB | 2022-09 B | 2022-09-13 | 14393.5356 | [KB5017305](https://support.microsoft.com/help/5017305) |
| LTSB | 2022-08 B | 2022-08-09 | 14393.5291 | [KB5016622](https://support.microsoft.com/help/5016622) |
| LTSB | 2022-07 B | 2022-07-12 | 14393.5246 | [KB5015808](https://support.microsoft.com/help/5015808) |
| LTSB | 2022-06 B | 2022-06-14 | 14393.5192 | [KB5014702](https://support.microsoft.com/help/5014702) |
| LTSB | 2022-05 OOB | 2022-05-19 | 14393.5127 | [KB5015019](https://support.microsoft.com/help/5015019) |
| LTSB | 2022-05 B | 2022-05-10 | 14393.5125 | [KB5013952](https://support.microsoft.com/help/5013952) |
| LTSB | 2022-04 B | 2022-04-12 | 14393.5066 | [KB5012596](https://support.microsoft.com/help/5012596) |
| LTSB | 2022-03 B | 2022-03-08 | 14393.5006 | [KB5011495](https://support.microsoft.com/help/5011495) |
| LTSB | 2022-02 B | 2022-02-08 | 14393.4946 | [KB5010359](https://support.microsoft.com/help/5010359) |
| LTSB | 2022-01 OOB | 2022-01-17 | 14393.4889 | [KB5010790](https://support.microsoft.com/help/5010790) |
| LTSB | 2022-01 B | 2022-01-11 | 14393.4886 | [KB5009546](https://support.microsoft.com/help/5009546) |
| LTSB | 2022-01 OOB | 2022-01-05 | 14393.4827 | [KB5010195](https://support.microsoft.com/help/5010195) |
| LTSB | 2021-12 B | 2021-12-14 | 14393.4825 | [KB5008207](https://support.microsoft.com/help/5008207) |
| LTSB | 2021-11 OOB | 2021-11-14 | 14393.4771 | [KB5008601](https://support.microsoft.com/help/5008601) |
| LTSB | 2021-11 B | 2021-11-09 | 14393.4770 | [KB5007192](https://support.microsoft.com/help/5007192) |
| LTSB | 2021-10 B | 2021-10-12 | 14393.4704 | [KB5006669](https://support.microsoft.com/help/5006669) |
| LTSB | 2021-09 B | 2021-09-14 | 14393.4651 | [KB5005573](https://support.microsoft.com/help/5005573) |
| LTSB | 2021-08 B | 2021-08-10 | 14393.4583 | [KB5005043](https://support.microsoft.com/help/5005043) |
| LTSB | 2021-07 OOB | 2021-07-29 | 14393.4532 | [KB5005393](https://support.microsoft.com/help/5005393) |
| LTSB | 2021-07 B | 2021-07-13 | 14393.4530 | [KB5004238](https://support.microsoft.com/help/5004238) |
| LTSB | 2021-07 OOB | 2021-07-07 | 14393.4470 | [KB5004948](https://support.microsoft.com/help/5004948) |
| LTSB | 2021-06 B | 2021-06-08 | 14393.4467 | [KB5003638](https://support.microsoft.com/help/5003638) |
| LTSB | 2021-05 B | 2021-05-11 | 14393.4402 | [KB5003197](https://support.microsoft.com/help/5003197) |
| LTSB | 2021-04 B | 2021-04-13 | 14393.4350 | [KB5001347](https://support.microsoft.com/help/5001347) |
| LTSB | 2021-03 OOB | 2021-03-18 | 14393.4288 | [KB5001633](https://support.microsoft.com/help/5001633) |
| LTSB | 2021-03 B | 2021-03-09 | 14393.4283 | [KB5000803](https://support.microsoft.com/help/5000803) |
| LTSB | 2021-02 B | 2021-02-09 | 14393.4225 | [KB4601318](https://support.microsoft.com/help/4601318) |
| LTSB | 2021-01 B | 2021-01-12 | 14393.4169 | [KB4598243](https://support.microsoft.com/help/4598243) |
| LTSB | 2020-12 B | 2020-12-08 | 14393.4104 | [KB4593226](https://support.microsoft.com/help/4593226) |
| LTSB | 2020-11 OOB | 2020-11-19 | 14393.4048 | [KB4594441](https://support.microsoft.com/help/4594441) |
| LTSB | 2020-11 B | 2020-11-10 | 14393.4046 | [KB4586830](https://support.microsoft.com/help/4586830) |
| LTSB | 2020-10 B | 2020-10-13 | 14393.3986 | [KB4580346](https://support.microsoft.com/help/4580346) |
| LTSB | 2020-09 B | 2020-09-08 | 14393.3930 | [KB4577015](https://support.microsoft.com/help/4577015) |
| LTSB | 2020-08 B | 2020-08-11 | 14393.3866 | [KB4571694](https://support.microsoft.com/help/4571694) |
| LTSB | 2020-07 B | 2020-07-14 | 14393.3808 | [KB4565511](https://support.microsoft.com/help/4565511) |
| LTSB | 2020-06 OOB | 2020-06-18 | 14393.3755 | [KB4567517](https://support.microsoft.com/help/4567517) |
| LTSB | 2020-06 B | 2020-06-09 | 14393.3750 | [KB4561616](https://support.microsoft.com/help/4561616) |
| LTSB | 2020-05 B | 2020-05-12 | 14393.3686 | [KB4556813](https://support.microsoft.com/help/4556813) |
| LTSB | 2020-04 C | 2020-04-21 | 14393.3659 | [KB4550947](https://support.microsoft.com/help/4550947) |
| LTSB | 2020-04 B | 2020-04-14 | 14393.3630 | [KB4550929](https://support.microsoft.com/help/4550929) |
| LTSB | 2020-03 C | 2020-03-17 | 14393.3595 | [KB4541329](https://support.microsoft.com/help/4541329) |
| LTSB | 2020-03 B | 2020-03-10 | 14393.3564 | [KB4540670](https://support.microsoft.com/help/4540670) |
| LTSB | 2020-02 C | 2020-02-25 | 14393.3542 | [KB4537806](https://support.microsoft.com/help/4537806) |
| LTSB | 2020-02 B | 2020-02-11 | 14393.3504 | [KB4537764](https://support.microsoft.com/help/4537764) |
| LTSB | 2020-01 C | 2020-01-23 | 14393.3474 | [KB4534307](https://support.microsoft.com/help/4534307) |
| LTSB | 2020-01 B | 2020-01-14 | 14393.3443 | [KB4534271](https://support.microsoft.com/help/4534271) |
| LTSB | 2019-12 B | 2019-12-10 | 14393.3384 | [KB4530689](https://support.microsoft.com/help/4530689) |
| LTSB | 2019-11 B | 2019-11-12 | 14393.3326 | [KB4525236](https://support.microsoft.com/help/4525236) |
| LTSB | 2019-10 C | 2019-10-15 | 14393.3300 | [KB4519979](https://support.microsoft.com/help/4519979) |
| LTSB | 2019-10 B | 2019-10-08 | 14393.3274 | [KB4519998](https://support.microsoft.com/help/4519998) |
| LTSB | 2019-09 OOB | 2019-10-03 | 14393.3243 | [KB4524152](https://support.microsoft.com/help/4524152) |
| LTSB | 2019-09 C | 2019-09-24 | 14393.3242 | [KB4516061](https://support.microsoft.com/help/4516061) |
| LTSB | 2019-09 OOB | 2019-09-23 | 14393.3206 | [KB4522010](https://support.microsoft.com/help/4522010) |
| LTSB | 2019-09 B | 2019-09-10 | 14393.3204 | [KB4516044](https://support.microsoft.com/help/4516044) |
| LTSB | 2019-08 C | 2019-08-17 | 14393.3181 | [KB4512495](https://support.microsoft.com/help/4512495) |
| LTSB | 2019-08 B | 2019-08-13 | 14393.3144 | [KB4512517](https://support.microsoft.com/help/4512517) |
| LTSB | 2019-07 C | 2019-07-16 | 14393.3115 | [KB4507459](https://support.microsoft.com/help/4507459) |
| LTSB | 2019-07 B | 2019-07-09 | 14393.3085 | [KB4507460](https://support.microsoft.com/help/4507460) |
| LTSB | 2019-06 OOB | 2019-06-27 | 14393.3056 | [KB4509475](https://support.microsoft.com/help/4509475) |
| LTSB | 2019-06 C | 2019-06-18 | 14393.3053 | [KB4503294](https://support.microsoft.com/help/4503294) |
| LTSB | 2019-06 B | 2019-06-11 | 14393.3025 | [KB4503267](https://support.microsoft.com/help/4503267) |
| LTSB | 2019-05 C | 2019-05-23 | 14393.2999 | [KB4499177](https://support.microsoft.com/help/4499177) |
| LTSB | 2019-05 OOB | 2019-05-19 | 14393.2972 | [KB4505052](https://support.microsoft.com/help/4505052) |
| LTSB | 2019-05 B | 2019-05-14 | 14393.2969 | [KB4494440](https://support.microsoft.com/help/4494440) |
| LTSB | 2019-04 C | 2019-04-25 | 14393.2941 | [KB4493473](https://support.microsoft.com/help/4493473) |
| LTSB | 2019-04 OOB | 2019-04-25 | 14393.2908 | [KB4499418](https://support.microsoft.com/help/4499418) |
| LTSB | 2019-04 B | 2019-04-09 | 14393.2906 | [KB4493470](https://support.microsoft.com/help/4493470) |
| LTSB | 2019-03 C | 2019-03-19 | 14393.2879 | [KB4489889](https://support.microsoft.com/help/4489889) |
| LTSB | 2019-03 B | 2019-03-12 | 14393.2848 | [KB4489882](https://support.microsoft.com/help/4489882) |
| LTSB | 2019-02 C | 2019-02-19 | 14393.2828 | [KB4487006](https://support.microsoft.com/help/4487006) |
| LTSB | 2019-02 B | 2019-02-12 | 14393.2791 | [KB4487026](https://support.microsoft.com/help/4487026) |
| LTSB | 2019-01 C | 2019-01-17 | 14393.2759 | [KB4480977](https://support.microsoft.com/help/4480977) |
| LTSB | 2019-01 B | 2019-01-08 | 14393.2724 | [KB4480961](https://support.microsoft.com/help/4480961) |
| LTSB | 2018-12 OOB | 2018-12-19 | 14393.2670 | [KB4483229](https://support.microsoft.com/help/4483229) |
| LTSB | 2018-12 B | 2018-12-11 | 14393.2665 | [KB4471321](https://support.microsoft.com/help/4471321) |
| LTSB | 2018-11 OOB | 2018-12-03 | 14393.2641 | [KB4478877](https://support.microsoft.com/help/4478877) |
| LTSB | 2018-11 C | 2018-11-27 | 14393.2639 | [KB4467684](https://support.microsoft.com/help/4467684) |
| LTSB | 2018-11 B | 2018-11-13 | 14393.2608 | [KB4467691](https://support.microsoft.com/help/4467691) |
| LTSB | 2018-10 C | 2018-10-18 | 14393.2580 | [KB4462928](https://support.microsoft.com/help/4462928) |
| LTSB | 2018-10 B | 2018-10-09 | 14393.2551 | [KB4462917](https://support.microsoft.com/help/4462917) |
| LTSB | 2018-09 C | 2018-09-20 | 14393.2515 | [KB4457127](https://support.microsoft.com/help/4457127) |
| LTSB | 2018-09 B | 2018-09-11 | 14393.2485 | [KB4457131](https://support.microsoft.com/help/4457131) |
| LTSB | 2018-08 C | 2018-08-30 | 14393.2457 | [KB4343884](https://support.microsoft.com/help/4343884) |
| LTSB | 2018-08 B | 2018-08-14 | 14393.2430 | [KB4343887](https://support.microsoft.com/help/4343887) |
| LTSB | 2018-07 OOB | 2018-07-30 | 14393.2396 | [KB4346877](https://support.microsoft.com/help/4346877) |
| LTSB | 2018-07 C | 2018-07-24 | 14393.2395 | [KB4338822](https://support.microsoft.com/help/4338822) |
| LTSB | 2018-07 OOB | 2018-07-16 | 14393.2368 | [KB4345418](https://support.microsoft.com/help/4345418) |
| LTSB | 2018-07 B | 2018-07-10 | 14393.2363 | [KB4338814](https://support.microsoft.com/help/4338814) |
| LTSB | 2018-06 C | 2018-06-21 | 14393.2339 | [KB4284833](https://support.microsoft.com/help/4284833) |
| LTSB | 2018-06 B | 2018-06-12 | 14393.2312 | [KB4284880](https://support.microsoft.com/help/4284880) |
| LTSB | 2018-05 C | 2018-05-17 | 14393.2273 | [KB4103720](https://support.microsoft.com/help/4103720) |
| LTSB | 2018-05 B | 2018-05-08 | 14393.2248 | [KB4103723](https://support.microsoft.com/help/4103723) |
| LTSB | 2018-04 C | 2018-04-17 | 14393.2214 | [KB4093120](https://support.microsoft.com/help/4093120) |
| LTSB | 2018-04 B | 2018-04-10 | 14393.2189 | [KB4093119](https://support.microsoft.com/help/4093119) |
| LTSB | 2018-03 OOB | 2018-03-29 | 14393.2156 | [KB4096309](https://support.microsoft.com/help/4096309) |
| LTSB | 2018-03 C | 2018-03-22 | 14393.2155 | [KB4088889](https://support.microsoft.com/help/4088889) |
| LTSB | 2018-03 B | 2018-03-13 | 14393.2125 | [KB4088787](https://support.microsoft.com/help/4088787) |
| LTSB | 2018-02 C | 2018-02-22 | 14393.2097 | [KB4077525](https://support.microsoft.com/help/4077525) |
| LTSB | 2018-02 B | 2018-02-13 | 14393.2068 | [KB4074590](https://support.microsoft.com/help/4074590) |
| LTSB | 2018-01 C | 2018-01-17 | 14393.2035 | [KB4057142](https://support.microsoft.com/help/4057142) |
| LTSB | 2018-01 B | 2018-01-03 | 14393.2007 | [KB4056890](https://support.microsoft.com/help/4056890) |
| LTSB | 2017-12 B | 2017-12-12 | 14393.1944 | [KB4053579](https://support.microsoft.com/help/4053579) |
| LTSB | 2017-11 C | 2017-11-27 | 14393.1914 | [KB4051033](https://support.microsoft.com/help/4051033) |
| LTSB | 2017-11 B | 2017-11-14 | 14393.1884 | [KB4048953](https://support.microsoft.com/help/4048953) |
| LTSB | 2017-10 OOB | 2017-11-02 | 14393.1797 | [KB4052231](https://support.microsoft.com/help/4052231) |
| LTSB | 2017-10 C | 2017-10-17 | 14393.1794 | [KB4041688](https://support.microsoft.com/help/4041688) |
| LTSB | 2017-10 B | 2017-10-10 | 14393.1770 | [KB4041691](https://support.microsoft.com/help/4041691) |
| LTSB | 2017-09 C | 2017-09-28 | 14393.1737 | [KB4038801](https://support.microsoft.com/help/4038801) |
| LTSB | 2017-09 B | 2017-09-12 | 14393.1715 | [KB4038782](https://support.microsoft.com/help/4038782) |
| LTSB | 2017-08 OOB | 2017-08-28 | 14393.1670 | [KB4039396](https://support.microsoft.com/help/4039396) |
| LTSB | 2017-08 C | 2017-08-16 | 14393.1613 | [KB4034661](https://support.microsoft.com/help/4034661) |
| LTSB | 2017-08 B | 2017-08-08 | 14393.1593 | [KB4034658](https://support.microsoft.com/help/4034658) |
| LTSB | 2017-08 OOB | 2017-08-07 | 14393.1537 | [KB4038220](https://support.microsoft.com/help/4038220) |
| LTSB | 2017-07 C | 2017-07-18 | 14393.1532 | [KB4025334](https://support.microsoft.com/help/4025334) |
| LTSB | 2017-07 B | 2017-07-11 | 14393.1480 | [KB4025339](https://support.microsoft.com/help/4025339) |
| LTSB | 2017-06 C | 2017-06-27 | 14393.1378 | [KB4022723](https://support.microsoft.com/help/4022723) |
| LTSB | 2017-06 B | 2017-06-13 | 14393.1358 | [KB4022715](https://support.microsoft.com/help/4022715) |
| LTSB | 2017-05 B | 2017-05-09 | 14393.1198 | [KB4019472](https://support.microsoft.com/help/4019472) |
| LTSB | 2017-04 B | 2017-04-11 | 14393.1066 | [KB4015217](https://support.microsoft.com/help/4015217) |
| LTSB | 2017-03 OOB | 2017-03-20 | 14393.969 | [KB4015438](https://support.microsoft.com/help/4015438) |
| LTSB | 2017-03 B | 2017-03-14 | 14393.953 | [KB4013429](https://support.microsoft.com/help/4013429) |
| LTSB | 2017-01 B | 2017-01-10 | 14393.693 | [KB3213986](https://support.microsoft.com/help/3213986) |
| LTSB | 2016-12 B | 2016-12-13 | 14393.576 | [KB3206632](https://support.microsoft.com/help/3206632) |
| LTSB | 2016-11 C | 2016-12-09 | 14393.479 | [KB3201845](https://support.microsoft.com/help/3201845) |
| LTSB | 2016-11 B | 2016-11-08 | 14393.447 | [KB3200970](https://support.microsoft.com/help/3200970) |
| LTSB | 2016-10 D | 2016-10-27 | 14393.351 | [KB3197954](https://support.microsoft.com/help/3197954) |
| LTSB | 2016-10 B | 2016-10-11 | 14393.321 | [KB3194798](https://support.microsoft.com/help/3194798) |
| LTSB | 2016-09 D | 2016-09-29 | 14393.222 | [KB3194496](https://support.microsoft.com/help/3194496) |
| LTSB | 2016-09 B | 2016-09-20 | 14393.187 | [KB3193494](https://support.microsoft.com/help/3193494) |
| LTSB | 2016-09 B | 2016-09-13 | 14393.187 | [KB3189866](https://support.microsoft.com/help/3189866) |
| LTSB | 2016-08 E | 2016-08-31 | 14393.105 | [KB3176938](https://support.microsoft.com/help/3176938) |
| LTSB | 2016-08 D | 2016-08-23 | 14393.82 | [KB3176934](https://support.microsoft.com/help/3176934) |
| LTSB | 2016-08 B | 2016-08-09 | 14393.51 | [KB3176495](https://support.microsoft.com/help/3176495) |
| LTSB | 2016-08 A | 2016-08-02 | 14393.10 | [KB3176929](https://support.microsoft.com/help/3176929) |

## Windows Server hotpatch calendar

View a calendar of hotpatch updates for Windows Server 2025 and Windows Server 2022. With [hotpatching](/en-us/windows-server/get-started/hotpatch), devices receive a baseline cumulative update the first month of each quarter in the calendar year. A restart is required to install that baseline update. During the next two months, devices receive a hotpatch update, which includes only security updates and can be installed without a restart. 
**Windows Server 2025 (OS build 26100)**
For details on what is included in each update, see [Release notes for Hotpatch on Windows Server 2025 Datacenter Azure Edition](https://support.microsoft.com/en-us/topic/release-notes-for-hotpatch-on-windows-server-2025-datacenter-azure-edition-c548437e-8c7a-4e27-99f4-e8746f97f8fa).
**Calendar year 2026**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| January | 2026.01 B | Baseline (Restart) | 2026-01-13 | 26100.32230 | [KB5073379](https://support.microsoft.com/topic/january-13-2026-baseline-07d1ed4c-f570-492e-a8e0-ab807a5bc296) |
| February | 2026.02 B | Hotpatch | 2026-02-10 | 26100.32313 | [KB5075942](https://support.microsoft.com/topic/february-10-2026-hotpatch-kb5075942-os-build-26100-32313-8c766fc4-ff6a-4ab5-be2f-0c57888bf8dc) |  |
| March | 2026.03 B | Hotpatch | 2026-03-10 | 26100.32463 | [KB5078736](https://support.microsoft.com/topic/march-10-2026-hotpatch-kb5078736-os-build-26100-32463-d62230e0-d4fb-4597-8df4-81410e827f79) |
| April | 2026.04 B | Baseline (Restart) | 2026-04-14 | 26100.32690 | [KB5082063](https://support.microsoft.com/topic/april-14-2026-baseline-3ed94012-763a-4ebe-86f4-32b01390a11a) |
| May | 2026.05 B | Hotpatch | 2026-05-12 | 26100.32772 | [KB5087423](https://support.microsoft.com/topic/may-12-2026-hotpatch-kb5087423-os-build-26100-32772-6a3275dd-3206-42b4-ab09-515421b3f142) |
| June | 2026.06 B | Hotpatch |  |  |  |
| July | 2026.07 B | Baseline (Restart) |  |  |  |
| August | 2026.08 B | Hotpatch |  |  |  |
| September | 2026.09 B | Hotpatch |  |  |  |
| October | 2026.10 B | Baseline (Restart) |  |  |  |
| November | 2026.11 B | Hotpatch |  |  |  |
| December | 2026.12 B | Hotpatch |  |  |  |

**Calendar year 2025**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| January | 2025.01 B | Baseline (Restart) | 2025-01-14 | 26100.2894 | [KB5050009](https://support.microsoft.com/topic/january-14-2025-baseline-cf62e135-183f-4e03-8f3f-1965484f767d) |
| February | 2025.02 B | Hotpatch | 2025-02-11 | 26100.3107 | [KB5052105](https://support.microsoft.com/topic/february-11-2025-hotpatch-kb5052105-os-build-26100-3107-6dda7015-f0c5-40d9-8de2-941ff9b7e3fc) |
| March | 2025.03 B | Hotpatch | 2025-03-11 | 26100.3403 | [KB5053636](https://support.microsoft.com/topic/march-11-2025-hotpatch-kb5053636-os-build-26100-3403-d3053ceb-88e9-41a3-b6a5-040f8f9935e4) |
| April | 2025.04 B | Baseline (Restart) | 2025-04-08 | 26100.3775 | [KB5055523](https://support.microsoft.com/topic/april-8-2025-baseline-ae7a2b2e-3048-4e53-b18f-9b5225592eae) |
| May | 2025.05 B | Hotpatch | 2025-05-13 | 26100.3981 | [KB5058497](https://support.microsoft.com/topic/may-13-2025-hotpatch-kb5058497-os-build-26100-3981-23bc4731-d39a-4478-8b4f-b64737fc2371) |
| June | 2025.06 B | Hotpatch | 2025-06-10 | 26100.4270 | [KB5060841](https://support.microsoft.com/topic/june-10-2025-hotpatch-kb5060841-os-build-26100-4270-b0911159-9564-44bf-80ae-a5d03013715d) |
| July | 2025.07 B | Baseline (Restart) | 2025-07-08 | 26100.4652 | [KB5062553](https://support.microsoft.com/topic/july-8-2025-baseline-a4881a11-02c5-424a-a26b-a14d4201e405) |
| August | 2025.08 B | Hotpatch | 2025-08-12 | 26100.4851 | [KB5064010](https://support.microsoft.com/help/5064010) |
| September | 2025.09 B | Hotpatch | 2025-09-09 | 26100.6508 | [KB5065474](https://support.microsoft.com/help/5065474) |
| October | 2025.10 B | Baseline (Restart) | 2025-10-14 | 26100.6899 | [KB5066835](https://support.microsoft.com/topic/october-14-2025-baseline-58e80013-ba94-46ad-a56c-b6691d2405ad) |
| November | 2025.11 B | Hotpatch | 2025-11-11 | 26100.7092 | [KB5068966](https://support.microsoft.com/topic/november-11-2025-hotpatch-kb5068966-os-build-26100-7092-e923cc54-3b4c-4df1-be42-92ae06d12984) |
| December | 2025.12 B | Hotpatch | 2025-12-09 | 26100.7392 | [KB5072014](https://support.microsoft.com/help/5072014) |

**Calendar year 2024**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| November | 2024.11 B | Hotpatch | 2024-11-12 | 26100.2240 | [KB5046696](https://support.microsoft.com/topic/november-12-2024-hotpatch-kb5046696-os-build-26100-2240-8807348d-14d6-4d28-9c4b-c006ff748d44) |
| December | 2024.12 B | Hotpatch | 2024-12-10 | 26100.2528 | [KB5048794](https://support.microsoft.com/topic/december-10-2024-hotpatch-kb5048794-os-build-26100-2528-b03075b9-0573-43c4-9d16-73822ce6cefa) |

**Windows Server 2022 (OS build 20348)**

For details on what is included in each update, see [Release notes for Hotpatch in Azure Automanage for Windows Server 2022](https://support.microsoft.com/en-us/topic/release-notes-for-hotpatch-in-azure-automanage-for-windows-server-2022-4e234525-5bd5-4171-9886-b475dabe0ce8).
**Calendar year 2026**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| January | 2026.01 B | Baseline (Restart) | 2026-01-13 | 20348.4648 | [KB5073457](https://support.microsoft.com/topic/january-13-2026-baseline-1be577b2-9a83-4eb7-9840-289ce599f40e) |
| February | 2026.02 B | Hotpatch | 2026-02-10 | 20348.4711 | [KB5075943](https://support.microsoft.com/topic/february-10-2026-hotpatch-kb5075943-os-build-20348-4711-88a3a172-3ef2-4027-b978-83861df746e7) |  |
| March | 2026.03 B | Hotpatch | 2026-03-10 | 20348.4830 | [KB5078737](https://support.microsoft.com/topic/march-10-2026-hotpatch-kb5078737-os-build-20348-4830-c3e0f4b0-62ac-4f92-9a7c-1831d02dc155) |
| April | 2026.04 B | Baseline (Restart) | 2026-04-14 | 20348.5020 | [KB5082142](https://support.microsoft.com/topic/april-14-2026-baseline-5d0db586-d5a5-4ba2-b3c8-a4536db17225) |
| May | 2026.05 B | Hotpatch | 2026-05-12 | 20348.5074 | [KB5087424](https://support.microsoft.com/topic/may-12-2026-hotpatch-kb5087424-os-build-20348-5074-2984f4af-5751-411c-9a0b-78f05dc8d5d0) |
| June | 2026.06 B | Hotpatch |  |  |  |
| July | 2026.07 B | Baseline (Restart) |  |  |  |
| August | 2026.08 B | Hotpatch |  |  |  |
| September | 2026.09 B | Hotpatch |  |  |  |
| October | 2026.10 B | Baseline (Restart) |  |  |  |
| November | 2026.11 B | Hotpatch |  |  |  |
| December | 2026.12 B | Hotpatch |  |  |  |

**Calendar year 2025**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| January | 2025.01 B | Baseline (Restart) | 2025-01-14 | 20348.3091 | [KB5049983](https://support.microsoft.com/help/5049983) |
| February | 2025.02 B | Hotpatch | 2025-02-11 | 20348.3148 | [KB5052106](https://support.microsoft.com/help/5052106) |
| March | 2025.03 B | Hotpatch | 2025-03-11 | 20348.3270 | [KB5053638](https://support.microsoft.com/help/5053638) |
| April | 2025.04 B | Baseline (Restart) | 2025-04-08 | 20348.3453 | [KB5055526](https://support.microsoft.com/help/5055526) |
| May | 2025.05 B | Hotpatch | 2025-05-13 | 20348.3630 | [KB5058500](https://support.microsoft.com/help/5058500) |
| June | 2025.06 B | Hotpatch | 2025-06-10 | 20348.3745 | [KB5060525](https://support.microsoft.com/help/5060525) |
| July | 2025.07 B | Baseline (Restart) | 2025-07-08 | 20348.3932 | [KB5062572](https://support.microsoft.com/help/5062572) |
| August | 2025.08 B | Hotpatch | 2025-08-12 | 20348.3989 | [KB5063812](https://support.microsoft.com/help/5063812) |
| September | 2025.09 B | Hotpatch | 2025-09-09 | 20348.4106 | [KB5065306](https://support.microsoft.com/help/5065306) |
| October | 2025.10 B | Baseline (Restart) | 2025-10-14 | 20348.4294 | [KB5066782](https://support.microsoft.com/help/5066782) |
| November | 2025.11 B | Hotpatch | 2025-11-11 | 20348.4346 | [KB5068840](https://support.microsoft.com/help/5068840) |
| December | 2025.12 B | Hotpatch | 2025-12-09 | 20348.4467 | [KB5071413](https://support.microsoft.com/help/5071413) |

**Calendar year 2024**

| Month | Update type | Type | Availability date | Build | KB article |
| --- | --- | --- | --- | --- | --- |
| January | 2024.01 B | Baseline (Restart) | 2024-01-09 | 20348.2227 | [KB5034129](https://support.microsoft.com/help/5034129) |
| February | 2024.02 B | Hotpatch | 2024-02-13 | 20348.2277 | [KB5034860](https://support.microsoft.com/help/5034860) |
| March | 2024.03 B | Hotpatch | 2024-03-12 | 20348.2333 | [KB5035959](https://support.microsoft.com/help/5035959) |
| April | 2024.04 B | Baseline (Restart) | 2024-04-09 | 20348.2402 | [KB5036909](https://support.microsoft.com/help/5036909) |
| May | 2024.05 B | Hotpatch | 2024-05-14 | 20348.2458 | [KB5037848](https://support.microsoft.com/help/5037848) |
| June | 2024.06 B | Hotpatch | 2024-06-11 | 20348.2522 | [KB5039330](https://support.microsoft.com/help/5039330) |
| July | 2024.07 B | Baseline (Restart) | 2024-07-09 | 20348.2582 | [KB5040437](https://support.microsoft.com/help/5040437) |
| August | 2024.08 B^\*^ | Baseline (Restart) | 2024-08-13 | 20348.2655 | [KB5041160](https://support.microsoft.com/help/5041160) |
| September | 2024.09 B | Hotpatch | 2024-09-10 | 20348.2695 | [KB5042880](https://support.microsoft.com/help/5042880) |
| October | 2024.10 B | Baseline (Restart) | 2024-10-08 | 20348.2762 | [KB5044281](https://support.microsoft.com/help/5044281) |
| November | 2024.11 B | Hotpatch | 2024-11-12 | 20348.2819 | [KB5046698](https://support.microsoft.com/help/5046698) |
| December | 2024.12 B | Hotpatch | 2024-12-10 | 20348.2908 | [KB5048800](https://support.microsoft.com/help/5048800) |

The releases marked with an ^\*^ were initially planned as hotpatch updates.