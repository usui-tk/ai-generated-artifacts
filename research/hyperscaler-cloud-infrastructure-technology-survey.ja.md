# ハイパースケーラーのクラウドコンピューティング基盤技術調査

---

## 1. エグゼクティブサマリ

### 1.1 本ドキュメントの概要

本ドキュメントは、主要ハイパースケーラー4社（Amazon Web Services、Microsoft Azure、Google Cloud、Oracle Cloud Infrastructure）のIaaS基盤技術を包括的に調査・整理したものです。以下の4つの主要領域について、比較分析と詳細技術情報を提供します。

| 領域 | 内容 |
|:---|:---|
| **ハイパーバイザー・ハードウェアオフロード** | 仮想化基盤、専用オフロードプロセッサ、ネットワーク・ストレージアクセラレーション |
| **ARMベースCPU** | 各社独自開発のArmプロセッサ（Graviton、Cobalt、Axion、Ampere） |
| **AIアクセラレーション** | 専用AIチップ（TPU、Trainium）、GPU、大規模クラスタ構成 |
| **ストレージ・デバイスドライバ** | ブロックストレージ、ローカルストレージ、ゲストOSドライバ |

### 1.2 主要技術動向サマリ

#### ハイパーバイザー・オフロード技術

各社は従来のハイパーバイザーからネットワーク・ストレージ・セキュリティ機能を専用ハードウェアにオフロードすることで、パフォーマンスとセキュリティを向上させています。

| プロバイダー | オフロード技術 | 最大ネットワーク | 特徴 |
|:---|:---|:---|:---|
| **AWS** | Nitro System v6 | 400 Gbps | 最も成熟（2017年〜6世代）、ASIC採用 |
| **Azure** | Azure Boost | 400 Gbps | FPGA + MANA、Confidential Computing先進 |
| **Google Cloud** | Titanium | 200 Gbps | 2層オフロード（IPU + TOP）、TPU統合 |
| **Oracle Cloud** | Acceleron | 200+ Gbps | Off-box完全分離、物理コア100%提供 |

#### ARMベースCPU

全4社が独自開発またはパートナーシップによるArmプロセッサを展開し、x86に対する価格性能・エネルギー効率優位を実現しています。

| プロバイダー | 最新CPU | アーキテクチャ | 最大コア数 | 提供状況 |
|:---|:---|:---|:---|:---|
| **AWS** | Graviton5 | Neoverse V3 | 192 | 2025年12月GA |
| **Azure** | Cobalt 200 | Neoverse V3 | 132 | 2026年GA予定 |
| **Google Cloud** | Axion N4A | Neoverse N3 | 64 | 2025年11月プレビュー |
| **Oracle Cloud** | Ampere A2 | Armv8.6+ | 156 | 2024年8月GA |

#### AIアクセラレーション

専用ASICとGPUの両面で競争が激化しており、数十万〜数百万チップ規模のスーパークラスタが構築されています。

| プロバイダー | 専用ASIC | 最大GPUスケール | 特徴 |
|:---|:---|:---|:---|
| **AWS** | Trainium3 | 20,000+ GPU | UltraServers/UltraClusters、AI Factories |
| **Azure** | Maia 100 | 大規模IB接続 | クロスリージョンRDMA対応 |
| **Google Cloud** | TPU v7 Ironwood | 9,216/Pod | 42.5 ExaFLOPS/Pod、Anthropic Claude稼働 |
| **Oracle Cloud** | - | 800,000 GPU | Zettascale10、OpenAI Stargate基盤 |

### 1.3 プロバイダー別の差別化ポイント

#### AWS（Amazon Web Services）

- **Nitro System**: 業界最も成熟したオフロードアーキテクチャ（2017年〜6世代展開）
- **Graviton5**: PCIe 6.0初対応、シングルソケット192コア設計でNUMA排除
- **垂直統合**: Annapurna Labs自社開発 + Nitroシステム連携
- **AI Factories**: 顧客データセンター内にAWSインフラを展開する新サービス
- **市場シェア**: AWS新規CPU容量の50%以上がGraviton

#### Microsoft Azure

- **Azure Boost**: 次世代（2025年11月）で1M IOPS、20GB/s、400Gbpsネットワーク
- **Cobalt 200**: AI駆動設計（350,000構成候補を評価）、Arm CCA対応
- **OpenHCL**: 2024年オープンソース化されたRust製パラバイザー
- **エンタープライズ統合**: Windows環境との深い統合、Azure Stack HCI対応
- **Confidential Computing**: TEE（SGX/SEV/TDX）の先進的サポート（2019年GA）

#### Google Cloud

- **Titanium**: 2層オフロード（オンホストIPU + オフホストTOP）アーキテクチャ
- **TPU Ironwood**: 単一Pod最大9,216チップ、42.5 ExaFLOPS
- **AI Hypercomputer**: TPU、GPU、CPU、ストレージ、ネットワークの統合AIインフラ
- **Caliptra RTM**: OCP標準準拠のシリコンレベルRoot of Trust
- **オープンソース貢献**: OpenTitan、Caliptra、BoringSSL、PSP

#### Oracle Cloud Infrastructure

- **Off-box Network Virtualization**: 業界初（2016年〜）、物理コア100%を顧客に提供
- **Zettascale10**: 最大800,000 GPU、OpenAI Stargateプロジェクト基盤
- **価格競争力**: A1は$0.01/OCPU/時間（業界初のペニーコア）
- **Always Free Tier**: 4 OCPU + 24GB RAMを無料提供
- **BYOハイパーバイザー**: 最も柔軟な対応（Oracle VM, Hyper-V, KVM, VMware）

### 1.4 技術トレンド概観

| トレンド | 概要 |
|:---|:---|
| **ハードウェアオフロードの高度化** | 専用ASIC/FPGA/DPUによるネットワーク・ストレージ処理のCPUからの完全分離 |
| **Armプロセッサの主流化** | 各社独自設計ARM CPUの本格展開、新規容量の20-50%がArm |
| **AIインフラの超大規模化** | 数十万〜数百万チップ規模のスーパークラスタ構築 |
| **Confidential Computingの普及** | TEE（SGX/SEV/TDX/CCA）による使用中データ保護の標準化 |
| **シリコンレベルRoot of Trust** | Caliptra/OpenTitan等によるハードウェアセキュリティの強化 |
| **NVMeインターフェースの標準化** | 第3世代以降のVMでNVMeが必須化（Google Cloud C3/C4等） |

---


## 2. クラウドサービスプロバイダー比較

本セクションでは、4社のハイパースケーラーを横断的に比較します。各技術領域における比較表を整理し、プロバイダー選定の参考情報を提供します。

### 2.1 ハイパーバイザー・オフロードアーキテクチャ比較

#### 2.1.1 ハイパーバイザーアーキテクチャ概要

| プロバイダー | オフロード技術名 | ベース技術 | ハイパーバイザー | オフロード方式 | 主な特徴 |
|:---|:---|:---|:---|:---|:---|
| **AWS** | Nitro System | **Linux KVM** | Nitro Hypervisor（軽量KVM） | 専用ASICカード（オンホスト） | CPU 100%近くを顧客に提供、ベアメタル同等性能 |
| **Microsoft Azure** | Azure Boost | **Microsoft Hypervisor (MSHV)** | x86-64: Hyper-V、ARM64: MSHV + OpenHCL | FPGA + ソフトウェア | エンタープライズ統合、Windows/Linux両対応 |
| **Google Cloud** | Titanium | **Linux KVM** | カスタムKVM | 2層オフロード（オンホスト+オフホスト） | IPU/TOPによる分散オフロード、AI最適化 |
| **Oracle Cloud** | Oracle Acceleron | **Oracle Linux KVM** | UEKベースKVM | Off-box（ホスト外分離） | 物理コア単位提供、オーバーサブスクリプションなし |

**注意：** Microsoft Azureの仮想化基盤はCPUアーキテクチャによって異なります。x86-64環境ではHyper-V（Windows Host OS上）、ARM64環境ではMicrosoft Hypervisor (MSHV) + OpenHCLパラバイザーが使用されます。

#### 2.1.2 ハイパーバイザー詳細比較

| 比較項目 | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **ベースカーネル** | Linux | Windows（x86-64）/ Linux（ARM64/パラバイザー） | Linux | Oracle Linux (UEK) |
| **仮想化技術（x86-64）** | KVM | Hyper-V | KVM | KVM |
| **仮想化技術（ARM64）** | KVM（Graviton） | **MSHV + OpenHCL**（非Hyper-V） | KVM | KVM |
| **ハイパーバイザー名** | Nitro Hypervisor | x86-64: Hyper-V / ARM64: MSHV | カスタムKVM | Oracle Linux KVM |
| **パラバイザー** | - | OpenHCL（Rust製、2024年OSS化） | - | - |
| **ハイパーバイザー役割** | メモリ/CPU割り当てのみ | フル機能 + オフロード | メモリ/CPU + 一部I/O | メモリ/CPU割り当てのみ |
| **ネットワーク仮想化** | Nitro Card（オンホスト） | MANA/FPGA | IPU + TOP | SmartNIC（Off-box） |
| **ベアメタル対応** | ✅ 多数のシェイプ | ✅ 限定的 | ✅ Bare Metal Solution | ✅ 多数のシェイプ |
| **BYOハイパーバイザー** | ✅ ベアメタル上で対応 | ✅ 専用ホスト/AVS | ✅ Bare Metal/GCVE | ✅ ベアメタル上で対応 |
| **対応ハイパーバイザー** | VMware, Nutanix, Hyper-V, KVM等 | VMware (AVS), Hyper-V | VMware (GCVE), その他 | Oracle VM, Hyper-V, KVM, VMware |
| **VMwareサービス** | Amazon Elastic VMware Service (EVS)、VMware Cloud on AWS | Azure VMware Solution (AVS) | Google Cloud VMware Engine (GCVE) | Oracle Cloud VMware Solution (OCVS) |
| **オープンソース公開** | Firecracker、Bottlerocket | OpenHCL/OpenVMM (2024年)、mshv_vtlドライバ | - | - |

#### 2.1.3 オフロードアーキテクチャ機能比較

| 機能カテゴリ | AWS Nitro | Azure Boost | Google Titanium | Oracle Acceleron |
|:---|:---|:---|:---|:---|
| **最大ネットワーク帯域幅** | 400 Gbps | 400 Gbps | 200 Gbps | 200+ Gbps |
| **HPC/AIネットワーク** | 3,200 Gbps (EFA) | 3,200 Gbps (IB) | 3,200 Gbps (ML Adapter) | 3,200 Gbps (RDMA) |
| **ストレージIOPS（リモート）** | 260K IOPS | 1M IOPS | 500K IOPS | 2倍向上（従来比） |
| **ストレージスループット（リモート）** | - | 20 GB/s | - | - |
| **ストレージIOPS（ローカル）** | 7.5M IOPS | 3.8M IOPS | 高IOPS | - |
| **Root of Trust** | Nitro Security Chip | Pluton + Azure HSM | Titan | Hardware Root-of-Trust |
| **Confidential Computing** | Nitro Enclaves | TEE (SGX/SEV) + ABCD | Confidential VMs | - |
| **ゼロトラスト** | セキュリティグループ | NSG | VPC Firewall | ZPR |
| **オフロード方式** | オンホストASIC | FPGA + ソフトウェア | 2層（IPU+TOP） | Off-box（ホスト外） |
| **RDMA対応** | ✅ EFA v4 | ✅ クロスリージョン対応 | ✅ | ✅ RoCEv2 |
| **ベアメタル提供** | ✅ 多数 | ✅ 限定的 | ✅ Bare Metal Solution | ✅ 多数 |
| **BYOハイパーバイザー** | ✅ ベアメタル上 | ✅ AVS/Dedicated Host | ✅ BMS/GCVE | ✅ ベアメタル上 |
| **マネージドVMware** | Amazon Elastic VMware Service (EVS)、VMware Cloud on AWS | Azure VMware Solution | GCVE | OCVS |

### 2.2 BYOハイパーバイザー対応比較

#### 2.2.1 ハイパーバイザーのCPUアーキテクチャ対応状況

ハイパーバイザーはCPUアーキテクチャに依存するため、x86-64（Intel/AMD）とARM64（Arm）で対応状況が大きく異なります。

**重要な前提知識：**
- ハイパーバイザーは特権命令やCPU仮想化拡張機能（Intel VT-x、AMD-V、Arm VHE）を直接利用するため、**異なるCPUアーキテクチャ間での仮想化は不可能**（エミュレーションのみ可能）
- x86-64ホスト上でARM64ゲストを「仮想化」することはできない（QEMUによるエミュレーションは可能だが低速）

| ハイパーバイザー | x86-64 (Intel/AMD) | ARM64 (Arm) | 備考 |
|:---|:---|:---|:---|
| **Microsoft Hyper-V** | ✅ 本番サポート（Windows Server 2008〜2025） | ⚠️ クライアントのみ（Windows 11 22H2+） | Windows Server ARM64版は未リリース |
| **VMware ESXi** | ✅ 本番サポート（ESXi 8.0 U3e最新） | ⚠️ Tech Preview（ESXi-Arm Fling） | ARM64は実験版のみ |
| **Linux KVM** | ✅ 本番サポート | ✅ 本番サポート（Linux 3.10〜、2013年） | 両アーキテクチャで完全サポート |
| **Xen** | ✅ 本番サポート（最大12 TiBホスト） | ✅ 本番サポート（最大2 TiBホスト、Xen 4.4〜） | 両アーキテクチャで完全サポート |
| **Nutanix AHV** | ✅ 本番サポート（KVMベース） | ❌ 未サポート | x86-64専用 |
| **Oracle VM** | ✅ 本番サポート（Xen/KVMベース） | ❌ 未サポート | x86-64専用 |
| **Oracle Linux KVM** | ✅ 本番サポート | ✅ 本番サポート（aarch64対応） | Oracle Linux 8/9でARM64サポート |
| **Proxmox VE** | ✅ 本番サポート（KVM/LXC） | ⚠️ コミュニティサポート | ARM64はコミュニティ提供 |

**凡例：** ✅ 本番サポート（商用利用可） / ⚠️ 制限付き・実験的 / ❌ 未サポート

#### 2.2.2 クラウドプロバイダー別BYOハイパーバイザー対応状況

| 項目 | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **ベアメタルインスタンス（x86-64）** | i3.metal, i4i.metal, i7i.metal, m5.metal, c5.metal等多数 | Dedicated Host（限定的） | Bare Metal Solution（Z3、C4等） | BM.Standard, BM.DenseIO, BM.GPU, BM.HPC等多数 |
| **ベアメタルインスタンス（ARM64）** | mac2-m2.metal（Apple Silicon）※Hyper-V/ESXi不可 | なし | Bare Metal Solution（C4A） | BM.Standard.A1（Ampere Altra）※Hyper-V/ESXi不可 |
| **VMware対応** | ✅ EVS/VMC on AWS（**x86-64のみ**） | ✅ AVS（**x86-64のみ**） | ✅ GCVE（**x86-64のみ**） | ✅ OCVS（**x86-64のみ**） |
| **Nutanix対応** | ✅ NC2 on AWS（**x86-64のみ**、AHV） | ✅ NC2 on Azure（**x86-64のみ**） | ✅ NC2 on GCP（**x86-64のみ**） | セルフ管理（**x86-64のみ**） |
| **Hyper-V対応** | ✅ ベアメタル上（**x86-64のみ**） | ネイティブ（**x86-64のみ**） | ✅ BMS上（**x86-64のみ**） | ✅ BYOH（**x86-64のみ**） |
| **KVM対応** | ✅ ベアメタル上（**x86-64/ARM64両対応**） | ✅ ネステッド仮想化（**x86-64のみ**） | ✅ BMS上（**x86-64/ARM64両対応**） | ✅ Oracle Linux KVM（**x86-64/ARM64両対応**） |
| **Xen対応** | ベアメタル上で可能（**x86-64/ARM64両対応**） | - | ベアメタル上で可能（**x86-64/ARM64両対応**） | - |
| **ライセンス持ち込み** | ✅ BYOL対応 | ✅ Azure Hybrid Benefit | ✅ BYOL対応 | ✅ BYOL対応 |
| **ハードパーティショニング** | - | - | - | ✅ Oracle Linux KVM/Oracle VM |

**重要：** VMware ESXi、Hyper-V、Nutanix AHVは**x86-64専用**です。ARM64環境でBYOハイパーバイザーを利用する場合は**KVMまたはXen**を選択してください。

#### 2.2.3 VMwareサービス比較

**注意：VMwareサービスは全て x86-64 専用です。ARM64インスタンスではVMwareを利用できません。**

| 項目 | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **サービス名** | **Amazon Elastic VMware Service (EVS)** (新)、VMware Cloud on AWS | Azure VMware Solution (AVS) | Google Cloud VMware Engine (GCVE) | Oracle Cloud VMware Solution (OCVS) |
| **CPUアーキテクチャ** | **x86-64のみ** | **x86-64のみ** | **x86-64のみ** | **x86-64のみ** |
| **提供形態** | EVS: AWSネイティブ（セルフ管理）、VMC on AWS: Broadcom管理 | Microsoftマネージド | Googleマネージド | Oracleマネージド |
| **VMware製品** | VMware Cloud Foundation (VCF) 5.2.1 | VMware vSphere, vSAN, NSX-T | VMware vSphere, vSAN, NSX-T | VMware vSphere, vSAN, NSX-T |
| **VPC統合** | ✅ Amazon VPC内で直接実行（EVS） | ✅ Azure VNet統合 | ✅ VPC統合 | ✅ VCN統合 |
| **管理コンソール** | EVS: AWSマネジメントコンソール | Azure Portal | Google Cloud Console | OCI Console |
| **ライセンスポータビリティ** | ✅ VCFライセンス持ち込み可（EVS） | ✅ 対応 | ✅ 対応 | ✅ 対応 |
| **最小構成** | EVS: 4ホスト | 3ホスト | 3ホスト | 3ホスト |
| **ステータス** | EVS: **GA（2025年8月〜、6リージョン）** | GA | GA | GA |

#### 2.2.4 Nutanix Cloud Clusters (NC2) 詳細比較

| 項目 | NC2 on AWS | NC2 on Azure | NC2 on Google Cloud |
|:---|:---|:---|:---|
| **ステータス** | GA | GA | GA（2025年12月） |
| **CPUアーキテクチャ** | **x86-64のみ** | **x86-64のみ** | **x86-64のみ** |
| **ベアメタルインスタンス** | i3.metal, i4i.metal, i7i.metal（7種類以上） | AN36P等 | Z3-metal, C4-metal |
| **ハイパーバイザー** | Nutanix AHV（KVMベース、x86-64専用） | Nutanix AHV | Nutanix AHV |
| **ストレージ** | ローカルNVMe + EBS（追加可能） | ローカルNVMe + Elastic SAN | ローカルNVMe |
| **ネットワーク統合** | VPC内直接デプロイ、Flow Virtual Networking | VNet統合、Flow Virtual Networking | VPC内直接デプロイ、Flow Virtual Networking |
| **ライセンス** | BYOL（ポータブル）、PAYG、AWS Marketplace | BYOL（ポータブル）、PAYG、Azure Marketplace、MACC対応 | BYOL（ポータブル）、PAYG、Google Cloud Marketplace |
| **最小構成** | 3ノード | 3ノード | 3ノード |
| **デプロイ時間** | 1時間未満 | 1時間未満 | 2時間未満 |
| **リージョン数** | グローバル多数 | グローバル多数（UAE North、Qatar Central等追加） | 17リージョン（2026年拡大予定） |
| **主なユースケース** | VMware移行、DR、クラウドバースト | VMware移行、DR、クラウドバースト | VMware移行、DR、AI/ML連携、BigQuery/Vertex AI統合 |

### 2.3 ARMベースCPU比較

#### 2.3.1 ARMベースCPU一覧

| プロバイダー | CPU名 | アーキテクチャ | 最大コア数 | 最大メモリ | 特徴 | 対応インスタンス | リリース時期 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **AWS** | Graviton5 | Arm Neoverse V2+ | 192コア | TBD（R9g 2026年予定） | PCIe 6.0対応、Nitro v6連携、5倍L3キャッシュ、25%性能向上 | M9g, C9g, R9g | 2025年12月（GA） |
| **AWS** | Graviton4 | Arm Neoverse V2 | 96コア | 3 TiB（X8g） | x86比で最大40%価格性能向上、DDR5 | R8g, M8g, C8g, X8g | 2023年11月 |
| **AWS** | Graviton3 | Arm Neoverse V1 | 64コア | 512 GB（R7g） | DDR5、PCIe 5.0対応 | C7g, M7g, R7g | 2021年5月 |
| **Microsoft Azure** | Cobalt 200 | Arm Neoverse CSS V3 | 132コア | TBD | 3nmプロセス、50%性能向上、Azure HSM統合、FIPS 140-3 Level 3 | 2026年GA予定 | 2025年11月（プレビュー） |
| **Microsoft Azure** | Cobalt 100 | Arm Neoverse N2 | 128コア | 672 GiB（Epsv6） | x86比で最大50%価格性能向上、32リージョン展開 | Dpsv6, Dplsv6, Epsv6 | 2024年10月（GA） |
| **Google Cloud** | Axion (N4A) | Arm Neoverse N3 | 64コア | 512 GB | N-series最高コスト効率、x86比2x価格性能、80%性能/ワット向上 | N4A | 2025年11月（プレビュー） |
| **Google Cloud** | Axion (C4A) | Arm Neoverse V2 | 96コア（metal） | 768 GB（metal） | Titanium SSD連携、最大100Gbpsネットワーク | C4A, C4A-metal | 2025年1月（GA） |
| **Oracle Cloud** | Ampere AmpereOne (A2) | Armv8.6+（カスタム） | 156コア | 946 GB | DDR5、2MB L2/コア、A1比28%性能向上 | VM.Standard.A2.Flex | 2024年8月 |
| **Oracle Cloud** | Ampere Altra (A1) | Arm Neoverse N1 | 160コア | 1 TB（BM） | シングルスレッド設計、1MB L2/コア、3.0GHz | BM.Standard.A1.160, VM.Standard.A1.Flex | 2021年5月 |

#### 2.3.2 性能・コスト比較（参考値）

| 項目 | Graviton5 | Graviton4 | Cobalt 200 | Cobalt 100 | Axion C4A | Axion N4A | Ampere A2 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **アーキテクチャ** | Neoverse V3 | Neoverse V2 | Neoverse V3 | Neoverse N2 | Neoverse V2 | Neoverse N3 | カスタムArm |
| **製造プロセス** | 3nm | 4nm | 3nm | 5nm | 3nm | 未公開 | 5nm |
| **最大コア数** | 192 | 96（192 vCPU） | 132（264） | 128 | 72（96 metal） | 64 | 156 |
| **L2キャッシュ/コア** | 向上 | 2MB | 3MB | 1MB | 2MB | 未公開 | 2MB |
| **L3キャッシュ** | 5x増加 | 共有 | 192MB | 共有 | 80MB | 未公開 | 共有 |
| **メモリチャネル** | 12 DDR5 | 12 DDR5 | 12 DDR5 | 8 DDR5 | 6 DDR5 | 未公開 | DDR5 |
| **最大メモリ** | 未公開 | 3 TiB | 未公開 | 672 GiB | 768 GB | 512 GB | 946 GB |
| **PCIe** | 6.0 | 5.0 | 5.0 | 4.0 | 5.0 | 未公開 | 5.0 |
| **提供状況** | プレビュー | GA | データセンター稼働 | GA | GA | プレビュー | GA |

#### 2.3.3 市場動向・採用実績

| 指標 | 数値 | 出典時期 |
|:---|:---|:---|
| AWS新規CPU容量のGraviton比率 | 50%以上 | 2024年 |
| Azure新規CPUのArm比率 | 32.9% | 2024年Q4 |
| GCP新規インスタンスのAxion比率 | 21.2% | 2024年Q4 |
| OCI ARMサービス対応数 | 100以上のOCIサービス | 2024年 |

| プロバイダー | 採用企業・実績 |
|:---|:---|
| **AWS Graviton** | Airbnb（25%性能向上）、Epic Games（最速テスト結果）、SmugMug/Flickr（20-40%改善） |
| **Azure Cobalt** | Microsoft Teams（45%性能向上、35%コア削減）、Databricks、Snowflake |
| **Google Axion** | Databricks（40%効率向上）、Elastic（40%スループット向上）、ClickHouse（40%効率向上） |
| **OCI Ampere** | Red Bull Racing（25%高速化）、Zoom、Adobe |

### 2.4 AIアクセラレーター比較

#### 2.4.1 専用ASIC比較

| プロバイダー | 製品名 | タイプ | ピーク性能 | メモリ | 用途 |
|:---|:---|:---|:---|:---|:---|
| **AWS** | Trainium3 | ASIC | 2.52 PFLOPs FP8/chip | 144 GB HBM3e | トレーニング/推論 |
| **AWS** | Trainium2 | ASIC | 1.3 PFLOPs FP8/chip | 96 GB | トレーニング |
| **AWS** | Inferentia2 | ASIC | - | - | 推論 |
| **Google Cloud** | TPU v7 Ironwood | ASIC | 4,614 TFLOPS FP8 | 192 GB HBM3e | トレーニング/推論 |
| **Google Cloud** | TPU v6e Trillium | ASIC | 918 TFLOPS FP8 | 32 GB HBM3 | トレーニング/推論 |
| **Microsoft Azure** | Maia 100 | ASIC | - | - | AIタスク全般 |

#### 2.4.2 大規模AIクラスタ比較

| プロバイダー | 構成名 | 最大GPU/チップ数 | 性能 | 特徴 |
|:---|:---|:---|:---|:---|
| **AWS** | EC2 UltraClusters | 20,000+ GPU | 20+ ExaFLOPS | P6e-GB200、Trn3 UltraServers対応 |
| **AWS** | P6e-GB200 UltraServer | 72 GPU/Server | 360 PFLOPS | NVIDIA Grace Blackwell Superchip |
| **AWS** | Trn3 UltraServer | 144 Trainium3 | 362 PFLOPS | NeuronSwitch-v1による接続 |
| **Google Cloud** | TPU v7 Ironwood Pod | 9,216チップ/Pod | 42.5 ExaFLOPS | ICI相互接続 |
| **Oracle Cloud** | Zettascale | 131,072 GPU | 2.4 ZettaFLOPS | Acceleron RoCE |
| **Oracle Cloud** | Zettascale10 | 800,000 GPU | 16 ZettaFLOPS | OpenAI Stargate基盤 |

### 2.5 ストレージ性能比較

#### 2.5.1 リモートブロックストレージ（最大性能）

| 指標 | AWS（io2 Block Express） | Azure（Ultra Disk） | Google Cloud（Hyperdisk Extreme） | OCI（UHP） |
|:---|:---|:---|:---|:---|
| **最大IOPS/ボリューム** | 256,000 | 400,000 | 350,000 | 300,000 |
| **最大スループット/ボリューム** | 4,000 MB/s | 10,000 MB/s | 5,000 MB/s | 2,680 MB/s |
| **最大IOPS/インスタンス** | 260,000 | 400,000 | 350,000 | 1,300,000 |
| **最大スループット/インスタンス** | 12,500 MB/s | 10,000 MB/s | 5,000 MB/s | 12,000 MB/s |
| **最大容量/ボリューム** | 64 TiB | 64 TiB | 64 TiB | 32 TiB |
| **レイテンシ（平均）** | < 500μs | サブミリ秒 | サブミリ秒 | サブミリ秒 |

#### 2.5.2 ローカルインスタンスストレージ（最大性能）

| 指標 | AWS（i4i.metal） | Azure（Lsv3） | Google Cloud（Local SSD） | OCI（DenseIO） |
|:---|:---|:---|:---|:---|
| **最大容量** | 30 TB | 11.52 TB | 9 TB | 54.4 TB |
| **最大IOPS** | 2,400,000 | 3,800,000 | 2,400,000 | 3,000,000+ |
| **最大スループット** | 16 GB/s | 36 GB/s | 9.4 GB/s | 30+ GB/s |

### 2.6 ゲストOSデバイスドライバ比較

| プロバイダー | ネットワーク（標準） | ネットワーク（高速化） | ストレージ（標準） | ストレージ（高性能） |
|:---|:---|:---|:---|:---|
| **AWS** | ENA | ENA Express / EFA | NVMe | NVMe (io2 Block Express) |
| **Azure** | NetVSC (hv_netvsc) | MANA | StorVSC (hv_storvsc) / SCSI | NVMe |
| **Google Cloud** | VirtIO-Net | gVNIC | VirtIO-SCSI | NVMe |
| **Oracle Cloud** | VirtIO-Net | SR-IOV | VirtIO-blk/SCSI / iSCSI | NVMe |

### 2.7 総合比較サマリー

| 項目 | AWS | Microsoft Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **オフロード技術** | Nitro System（ASIC） | Azure Boost（FPGA + MANA） | Titanium（IPU + TOP） | Oracle Acceleron（DPU） |
| **ARMプロセッサ** | Graviton5（V3/192コア） | Cobalt 200（V3/132コア） | Axion C4A/N4A | Ampere A1/A2 |
| **専用AI ASIC** | Trainium3/4、Inferentia | Maia 100 | TPU v7 Ironwood | - |
| **最大GPUスケール** | 20,000+ GPU（UltraClusters） | 大規模IB接続 | 9,216チップ/Pod | 800,000 GPU（Zettascale10） |
| **主な強み** | 最も成熟したオフロード、垂直統合、AI Factories | エンタープライズ統合、Confidential Computing | TPUエコシステム、AI Hypercomputer | 最大GPUスケール、物理コア100%提供 |


### 2.8 ハイパースケーラー間比較サマリー

**ハードウェアアクセラレーション世代対応表：**

| 機能 | AWS | Azure | Google Cloud | OCI |
|:---|:---|:---|:---|:---|
| **オフロード技術名** | Nitro System | Azure Boost | Titanium | Off-box Virtualization |
| **最新世代** | Nitro v6 (2024-2025) | v6 + OpenHCL (2024) | 第4/5世代 (2024-2025) | Gen3 (2025-2026) |
| **最大ネットワーク帯域** | 400 Gbps | 400 Gbps (InfiniBand) | 200 Gbps | 3,200 Gbps (RoCE) |
| **DPU/SmartNIC** | Nitro Cards (自社開発) | FPGA + DPU | Titanium Adapter/IPU | AMD Pensando / NVIDIA BlueField-3 |
| **ARM64対応** | Graviton2-4 | Ampere Altra / Cobalt 100-200 | Axion (自社開発) | Ampere Altra / AmpereOne |
| **Confidential Computing** | Nitro Enclaves | AMD SEV-SNP / Intel TDX | Confidential VMs | AMD SEV |

**世代別主要インスタンス対応早見表：**

| 世代特徴 | AWS | Azure | Google Cloud | OCI |
|:---|:---|:---|:---|:---|
| **最新世代（Nitro v6等）** | M8a, M8i, C8a, C8i, C8gn, R8a, R8i, I8ge, P6-B200 | Dv6, Easv6, Fasv6, Dpsv6 | C4, C4A, C4D, N4, N4D, H4D | E5.Flex, A2.Flex, GPU.H100 |
| **前世代（Nitro v5等）** | M8g, C8g, C7gn, R8g, I7ie, I8g, P5en, Trn2 | Dv5, Ev5, Fav5, Dpsv5 | C3, C3D, H3, A3 | E4.Flex, A1.Flex, GPU.B4 |
| **旧世代（Nitro v4等）** | M6i, M7i, C6i, C7i, R6i, R7i, P5, Trn1 | Dv4, Ev4, Fsv2 | N2, N2D, E2, C2 | E3.Flex, Standard3 |
| **レガシー（Nitro v2/v3等）** | M5, C5, R5, M6g, C6g, R6g | Dv3, Ev3 | N1 | Standard2 |

---

## 3. クラウドサービスプロバイダー別詳細情報

本セクションでは、各ハイパースケーラーの技術詳細を個別に解説します。

### 3.1 Amazon Web Services (AWS)

#### 3.1.1 AWS Nitro System

AWS Nitro Systemは、AWSが2017年から展開しているハードウェアオフロードアーキテクチャです。専用ASICにより、ネットワーク・ストレージ・セキュリティ機能をオフロードし、ほぼ100%のCPUリソースを顧客ワークロードに提供します。

**Nitro世代別リリース履歴：**

| 世代 | リリース時期 | 対応インスタンス例 | 最大ネットワーク | 主な特徴 |
|:---|:---|:---|:---|:---|
| **Nitro v2** | 2017年11月 | C5, M5, R5, A1, M6g, T3, C6g, R6g | インスタンス依存 | 初代Nitro、ENA対応、KVMベース |
| **Nitro v3** | 2019年 | C5n, M5n, R5n, I3en, G4dn, G5, P4d | 100 Gbps | 通信時暗号化（in-transit encryption）追加 |
| **Nitro v4** | 2021年 | C6i, M6i, R6i, C7g, M7g, I4i, P5, Trn1 | 170 Gbps | ENA Express対応、RDMA read/write（一部） |
| **Nitro v5** | 2022年〜2024年 | C7gn, M8g, R8g, C8g, I7ie, I8g, P5en, Trn2, Hpc7g | 200 Gbps | 高PPS、低レイテンシ |
| **Nitro v6** | 2024年〜2025年 | M8a, M8i, C8a, C8i, C8gn, R8a, R8i, I8ge, P6-B200 | 400 Gbps | 最新世代、RDMA Read/Write対応 |

**コンポーネント詳細：**

| カテゴリ | コンポーネント | リリース時期 | 世代/バージョン | 機能説明 | 性能指標 |
|:---|:---|:---|:---|:---|:---|
| **ネットワーク** | Nitro Card for VPC | 2017年 | v2〜v6 | パケット処理、セキュリティグループ、ルーティング | 最大400 Gbps (v6) |
| **ネットワーク** | ENA (Elastic Network Adapter) | 2016年 | v2〜v6 | 高帯域ネットワークインターフェース、SR-IOV | 最大100 Gbps（標準） |
| **ネットワーク** | ENA Express | 2022年 | Nitro v4以降 | SRDベース輻輳制御、単一フロー25Gbps | P99レイテンシ50%改善 |
| **ネットワーク** | EFA (Elastic Fabric Adapter) | 2019年 | 第1〜第2世代 | HPC/AI向けRDMA、GPUDirect、libfabric | 最大3,200 Gbps |
| **ストレージ** | Nitro Card for EBS | 2017年 | v2〜v6 | EBSアクセス、暗号化オフロード | 最大260K IOPS |
| **ストレージ** | Nitro Card for Local NVMe | 2017年 | v2〜v6 | ローカルSSDアクセス、AES-256暗号化 | 最大7.5M IOPS |
| **セキュリティ** | Nitro Security Chip | 2017年 | - | ハードウェアRoot of Trust、セキュアブート | - |
| **セキュリティ** | Nitro Enclaves | 2020年 | - | 分離された機密コンピューティング環境 | - |
| **セキュリティ** | NitroTPM | 2022年 | TPM 2.0準拠 | 仮想TPM、暗号鍵管理 | - |
| **セキュリティ** | インスタンス間暗号化 | 2019年 (v3〜) | AES-256-GCM | 自動暗号化（in-transit） | ラインレート |
| **管理** | Nitro Controller | 2017年 | v2〜v6 | 全Nitroカード統合管理、インスタンス監視 | - |
| **管理** | Nitro Hypervisor | 2017年 | KVMベース | 軽量ハイパーバイザー（メモリ/CPU割り当て） | オーバーヘッド<1% |

**AWS Nitro System仮想化スタック：**

```
┌─────────────────────────────────────────────────────────────────┐
│                    ゲストOS (Linux/Windows)                      │
│              ┌─────────────────────────────────────┐            │
│              │        ゲストドライバ                 │            │
│              │   ENA (ネットワーク) / NVMe (ストレージ)│            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│                    Nitro Hypervisor                              │
│         (軽量KVMベース、メモリ/CPU割り当てのみ)                    │
│              ネットワークスタックなし、ファイルシステムなし           │
├─────────────────────────────────────────────────────────────────┤
│                    SR-IOV Virtual Functions                      │
│              (Nitro CardからVMへの直接割り当て)                    │
├─────────────┬─────────────┬─────────────┬───────────────────────┤
│  Nitro Card │  Nitro Card │  Nitro Card │   Nitro Security      │
│  for VPC    │  for EBS    │  for NVMe   │      Chip             │
│ (ネットワーク) │ (リモートSSD) │ (ローカルSSD) │  (Root of Trust)      │
├─────────────┴─────────────┴─────────────┴───────────────────────┤
│                    Nitro Controller                              │
│           (全Nitroカード統合管理、EC2コントロールプレーン通信)        │
├─────────────────────────────────────────────────────────────────┤
│           ホストCPU (Graviton / Intel Xeon / AMD EPYC)           │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴：**
- **オフロード方式**: オンホスト（専用ASICカード）
- **ハイパーバイザー**: Nitro Hypervisor（KVMベース、極小化設計）
- **I/O仮想化**: SR-IOVによるNitro Cardの直接VM割り当て
- **セキュリティモデル**: パッシブ通信（Nitro HypervisorはNitro Controllerからの命令待ちのみ）
- **管理者アクセス**: 物理的・論理的に排除（AWS従業員を含む）

**重要な制約事項：**
- **ネステッド仮想化対応**：x86-64（Intel VT-x/AMD-V）のみ。Graviton（ARM64）ではKVM in VM未サポート
- **ベアメタルインスタンス**: Nitro Cards直接制御、ハイパーバイザーなし

#### 3.1.2 AWS Graviton

AWSはAnnapurna Labs（2015年買収）により、Gravitonシリーズを自社開発しています。2024年以降、AWS新規CPU容量の50%以上をGravitonが占めています。

**AWS Graviton5（2025年12月プレビュー、2026年GA予定）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | AWS Graviton5 |
| **アーキテクチャ** | Arm Neoverse V3（ARMv9.2-A） |
| **製造プロセス** | TSMC 3nm |
| **コア数** | 192コア（シングルソケット） |
| **L3キャッシュ** | 5x増加（Graviton4比）、コア当たり2.67x増加 |
| **メモリチャネル** | 12チャネル DDR5-7200（DDR5-8400対応予定） |
| **メモリ帯域幅** | 691.2 GB/s（DDR5-7200時）、806.4 GB/s（DDR5-8400時） |
| **PCIe** | PCIe 6.0（96レーン、2.84 TB/s双方向） |
| **ネットワーク** | Nitro 6連携、最大100 Gbps（2倍向上） |
| **対応インスタンス** | M9g（プレビュー）、C9g/R9g（2026年予定） |
| **Graviton4比性能** | 25%向上 |
| **特徴** | シングルソケット設計（NUMA排除）、コア間レイテンシ1/3削減 |

**AWS Graviton4（2023年11月発表、2024年GA）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | AWS Graviton4 |
| **アーキテクチャ** | Arm Neoverse V2（ARMv9.0-A + SVE2） |
| **製造プロセス** | TSMC 4nm（7チップレット構成） |
| **コア数** | 96コア/ソケット（デュアルソケット対応で最大192 vCPU） |
| **L2キャッシュ** | 2MB/コア（192MB総計） |
| **メモリチャネル** | 12チャネル DDR5-5600 |
| **メモリ帯域幅** | 536.7 GB/s/ソケット |
| **最大メモリ** | 3 TiB（X8gインスタンス） |
| **PCIe** | PCIe 5.0（96レーン） |
| **対応インスタンス** | R8g, M8g, C8g, X8g, I8g |
| **Graviton3比性能** | データベース40%、Webアプリ30%、大規模Java45%向上 |

**AWS Graviton3/3E（2021年5月発表）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | AWS Graviton3 / Graviton3E |
| **アーキテクチャ** | Arm Neoverse V1（ARMv8.4-A） |
| **コア数** | 64コア |
| **周波数** | 2.6 GHz |
| **SIMD** | 4×128bit Neon + 2×256bit SVE |
| **メモリチャネル** | 8チャネル DDR5-4800 |
| **メモリ帯域幅** | 307.2 GB/s |
| **PCIe** | PCIe 5.0（業界初サポート） |
| **対応インスタンス** | C7g, M7g, R7g（Graviton3）、C7gn, HPC7g（Graviton3E） |
| **Graviton2比性能** | 計算25%、浮動小数点2x、暗号2x、ML3x向上 |
| **エネルギー効率** | 同等性能で60%省電力 |

#### 3.1.3 AWS Trainium・Inferentia

**Trainium3チップ仕様：**

| 項目 | 仕様 |
|:---|:---|
| **製造プロセス** | TSMC 3nm |
| **FP8演算性能** | 2.52 PFLOPS/chip |
| **HBM3eメモリ** | 144 GB/chip |
| **メモリ帯域幅** | 4.9 TB/s/chip |
| **対応精度** | FP32、BF16、MXFP8、MXFP4 |

**Trn3 UltraServer仕様：**

| 項目 | Gen1 UltraServer | Gen2 UltraServer |
|:---|:---|:---|
| **Trainium3チップ数** | 64（推定） | 144 |
| **合計FP8演算性能** | 約161 PFLOPS | 362 PFLOPS |
| **HBM3e合計** | 約9.2 TB | 20.7 TB |
| **メモリ帯域幅合計** | 約314 TB/s | 706 TB/s |
| **スイッチ** | NeuronSwitch-v1 | NeuronSwitch-v1 |

**Trainium2チップ仕様：**

| 項目 | 仕様 |
|:---|:---|
| **NeuronCore数** | 8/chip |
| **HBMメモリ** | 96 GB/chip |
| **メモリ帯域幅** | 2.9 TB/s/chip |
| **FP8演算性能（Dense）** | 1.3 PFLOPS/chip |
| **FP8演算性能（Sparse）** | 5.2 PFLOPS/chip |

#### 3.1.4 AWS EC2 UltraClusters・UltraServers

**EC2 UltraClustersの構成要素：**

| 構成要素 | 説明 |
|:---|:---|
| **アクセラレーテッドインスタンス** | P6e-GB200、P6-B200、P5en、P5e、P5、P4d、Trn2、Trn3、Trn1インスタンス |
| **ネットワーク** | Elastic Fabric Adapter (EFA)によるペタビット規模のノンブロッキングネットワーク |
| **ストレージ** | Amazon FSx for Lustre（高性能並列ファイルシステム）、Amazon S3 |
| **配置** | 特定のAWSアベイラビリティーゾーンに共同配置 |

**P6e-GB200 UltraServers仕様：**

| 項目 | u-p6e-gb200x72 | u-p6e-gb200x36 |
|:---|:---|:---|
| **GPUアーキテクチャ** | NVIDIA Grace Blackwell Superchip | NVIDIA Grace Blackwell Superchip |
| **GPU数（NVLink内）** | 72 | 36 |
| **FP8演算性能** | 360 PFLOPS | 180 PFLOPS |
| **HBM3eメモリ合計** | 13.4 TB | 6.7 TB |
| **NVLink帯域幅** | 130 TB/s | 65 TB/s |
| **EFAネットワーク** | 28.8 Tbps（EFAv4） | 14.4 Tbps（EFAv4） |
| **CPUアーキテクチャ** | NVIDIA Grace（Arm） | NVIDIA Grace（Arm） |

#### 3.1.5 AWS AI Factories

AWS AI Factoriesは、顧客データセンター内にAWSインフラストラクチャを展開するサービスです（2025年12月発表）。

**主な構成要素：**

| 構成要素 | 説明 |
|:---|:---|
| **AIアクセラレータ** | NVIDIA GPU（Blackwell B200/GB200、将来のVera Rubin）またはAWS Trainium（Trainium2/Trainium3） |
| **ネットワーク** | AWS高速・低レイテンシネットワーク、EC2 UltraClusters対応 |
| **ストレージ** | Amazon FSx for Lustre、Amazon S3 Express One Zone（数百GB/sスループット、数百万IOPS） |
| **AIサービス** | Amazon Bedrock、Amazon SageMaker AI |
| **セキュリティ** | AWS Nitro System（ハードウェアレベルの分離、AWSを含む誰もアクセス不可） |

**特徴：**

| 特徴 | 説明 |
|:---|:---|
| **データ主権** | 機密データが顧客のデータセンター外に出ない |
| **規制対応** | 厳格な規制要件（政府、金融、医療等）に準拠 |
| **迅速な展開** | 数年の構築期間を大幅短縮 |
| **フルマネージド** | AWS運用による保守・アップデート |
| **既存投資活用** | 顧客のデータセンタースペース・電力・ネットワーク接続を活用 |

#### 3.1.6 AWS GPUインスタンス一覧

**ハイエンド（トレーニング/大規模推論）：**

| インスタンス | GPU | GPU数 | GPUメモリ合計 | vCPU | システムメモリ | ネットワーク | リリース時期 | 主な用途 |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **p6e-gb300.48xlarge** | GB300 NVL72 | 72 | 20 TB+ | 192 | 2,048 GB | 3,200 Gbps EFA | 2025年12月発表 | 最新推論/トリリオンパラメータモデル |
| **p5en.48xlarge** | H200 | 8 | 1,128 GB | 192 | 2,048 GB | 3,200 Gbps EFA | 2024年12月GA | 最新LLMトレーニング |
| **p5e.48xlarge** | H200 | 8 | 1,128 GB | 192 | 2,048 GB | 3,200 Gbps EFA | 2024年9月GA | LLMトレーニング/推論 |
| **p5.48xlarge** | H100 | 8 | 640 GB | 192 | 2,048 GB | 3,200 Gbps EFA | 2023年8月GA | 大規模AIトレーニング |
| **p4de.24xlarge** | A100 80GB | 8 | 640 GB | 96 | 1,152 GB | 400 Gbps EFA | 2022年GA | AIトレーニング |
| **p4d.24xlarge** | A100 40GB | 8 | 320 GB | 96 | 1,152 GB | 400 Gbps EFA | 2020年11月GA | AIトレーニング |

**ミッドレンジ（推論/中規模トレーニング）：**

| インスタンス | GPU | GPU数 | GPUメモリ合計 | vCPU | システムメモリ | ネットワーク | リリース時期 | 主な用途 |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **g6e.xlarge〜48xlarge** | L40S | 1-8 | 48-384 GB | 4-192 | 16-768 GB | 最大100 Gbps | 2024年8月GA | LLM推論/ファインチューニング |
| **g6.xlarge〜48xlarge** | L4 | 1-8 | 24-192 GB | 4-192 | 16-768 GB | 最大100 Gbps | 2024年4月GA | 推論/ビデオ処理 |
| **g5.xlarge〜48xlarge** | A10G | 1-8 | 24-192 GB | 4-192 | 16-768 GB | 最大100 Gbps | 2021年11月GA | 推論/グラフィックス |

#### 3.1.7 AWS ストレージアーキテクチャ

**リモートブロックストレージ（Amazon EBS）：**

| ボリュームタイプ | API名 | 用途 | 最大IOPS/ボリューム | 最大スループット/ボリューム | 最大容量 | レイテンシ | 耐久性 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **io2 Block Express** | io2 | ミッションクリティカルDB（SAP HANA, SQL Server） | 256,000 IOPS | 4,000 MB/s | 64 TiB | < 500μs（平均） | 99.999% |
| **gp3** | gp3 | 汎用（仮想デスクトップ、中規模DB） | 80,000 IOPS | 2,000 MB/s | 64 TiB | 1桁ms | 99.8-99.9% |
| **gp2** | gp2 | 汎用（レガシー） | 16,000 IOPS | 250 MB/s | 16 TiB | 1桁ms | 99.8-99.9% |
| **io1** | io1 | 高IOPS（レガシー） | 64,000 IOPS | 1,000 MB/s | 16 TiB | 1桁ms | 99.9% |
| **st1（HDD）** | st1 | スループット重視（ログ処理、DWH） | 500 IOPS | 500 MB/s | 16 TiB | - | 99.8-99.9% |
| **sc1（HDD）** | sc1 | コールドデータ | 250 IOPS | 250 MB/s | 16 TiB | - | 99.8-99.9% |

**インスタンスあたりの最大性能：**
- 最大IOPS：260,000 IOPS
- 最大スループット：12,500 MB/s（12.5 GB/s）

**ローカルインスタンスストレージ（NVMe SSD）：**

| インスタンスタイプ | ローカルストレージ | ディスク構成 | 最大IOPS | 最大スループット | 用途 |
|:---|:---|:---|:---|:---|:---|
| **i4i.metal** | 30 TB | 8x 3,750 GB NVMe SSD | 2,400,000 IOPS（読取） | 16 GB/s | ストレージ最適化 |
| **i3en.metal** | 60 TB | 8x 7,500 GB NVMe SSD | 2,000,000 IOPS（読取） | 16 GB/s | 高密度ストレージ |
| **d3en.12xlarge** | 336 TB | 24x 14 TB HDD | - | 6.2 GB/s | 大容量HDD |
| **c5d.24xlarge** | 3.6 TB | 4x 900 GB NVMe SSD | 1,200,000 IOPS | 6.6 GB/s | コンピュート+ローカルSSD |


#### 3.1.8 AWS Nitro System世代別インスタンスタイプ

**Nitro世代とネットワーク性能：**

| Nitro世代 | 最大帯域幅 | 主な機能 | ENA Express | Traffic Mirroring | RDMA |
|:---|:---|:---|:---|:---|:---|
| **v2** | インスタンスタイプ依存 | 初代Nitro、ENA対応 | ❌ | ✅ | ❌ |
| **v3** | 100 Gbps | 通信時暗号化（in-transit encryption） | ❌ | ✅ | ❌ |
| **v4** | 170 Gbps（GPU/Trainiumは100Gbps） | ENA Express対応、RDMA read/write（一部） | ✅ | ✅ | 一部対応 |
| **v5** | 200 Gbps | 性能向上 | ✅ | ❌ | 対応 |
| **v6** | 400 Gbps | 最新世代 | ✅ | ❌ | 対応 |

※機能は累積的であり、新しい世代は以前の世代の機能をサポート（明示的に除外されている場合を除く）

**Nitro v6対応インスタンス（最新世代）：**

| カテゴリ | インスタンスタイプ |
|:---|:---|
| **汎用（General Purpose）** | M8a, M8i, M8i-flex |
| **コンピューティング最適化（Compute Optimized）** | C8a, C8gn, C8i, C8i-flex |
| **メモリ最適化（Memory Optimized）** | R8a, R8gb, R8gn, R8i, R8i-flex, X8aedz |
| **ストレージ最適化（Storage Optimized）** | I8ge |
| **アクセラレーテッドコンピューティング（Accelerated Computing）** | P6-B200, P6-B300 |

**Nitro v5対応インスタンス：**

| カテゴリ | インスタンスタイプ |
|:---|:---|
| **汎用（General Purpose）** | M8g, M8gd |
| **コンピューティング最適化（Compute Optimized）** | C7gn, C8g, C8gd |
| **メモリ最適化（Memory Optimized）** | R8g, R8gd, X8g |
| **ストレージ最適化（Storage Optimized）** | I7ie, I8g |
| **アクセラレーテッドコンピューティング（Accelerated Computing）** | P5en, P6e-GB200, Trn2, Trn2u |
| **HPC（High Performance Computing）** | Hpc7g |

**Nitro v4対応インスタンス：**

| カテゴリ | インスタンスタイプ |
|:---|:---|
| **汎用（General Purpose）** | M6a, M6i, M6id, M6idn, M6in, M7a, M7g, M7gd, M7i, M7i-flex |
| **コンピューティング最適化（Compute Optimized）** | C6a, C6gn, C6i, C6id, C6in, C7a, C7g, C7gd, C7i, C7i-flex |
| **メモリ最適化（Memory Optimized）** | R6a, R6i, R6id, R6idn, R6in, R7a, R7g, R7gd, R7i, R7iz, U7i-6tb, U7i-8tb, U7i-12tb, U7in-16tb, U7in-24tb, U7in-32tb, U7inh-32tb, X2idn, X2iedn |
| **ストレージ最適化（Storage Optimized）** | I4g, I4i, I7i, Im4gn, Is4gen |
| **アクセラレーテッドコンピューティング（Accelerated Computing）** | F2, G6, G6e, G6f, Gr6, Gr6f, Inf2, P5, P5e, Trn1, Trn1n |
| **HPC（High Performance Computing）** | Hpc6a, Hpc6id, Hpc7a |

**Nitro v3対応インスタンス：**

| カテゴリ | インスタンスタイプ |
|:---|:---|
| **汎用（General Purpose）** | M5dn, M5n, M5zn |
| **コンピューティング最適化（Compute Optimized）** | C5n |
| **メモリ最適化（Memory Optimized）** | R5dn, R5n, U-3tb1, U-6tb1, U-9tb1, U-12tb1, U-18tb1, U-24tb1, X2iezn |
| **ストレージ最適化（Storage Optimized）** | D3, D3en, I3en |
| **アクセラレーテッドコンピューティング（Accelerated Computing）** | DL1, DL2q, G4ad, G4dn, G5, Inf1, P3dn, P4d, P4de, VT1 |

**Nitro v2対応インスタンス：**

| カテゴリ | インスタンスタイプ |
|:---|:---|
| **汎用（General Purpose）** | A1, M5, M5a, M5ad, M5d, M6g, M6gd, T3, T3a, T4g |
| **コンピューティング最適化（Compute Optimized）** | C5, C5a, C5ad, C5d, C6g, C6gd |
| **メモリ最適化（Memory Optimized）** | R5, R5a, R5ad, R5b, R5d, R6g, R6gd, X2gd, z1d |
| **アクセラレーテッドコンピューティング（Accelerated Computing）** | G5g |

**汎用インスタンス（General Purpose）詳細：**

| インスタンス | Nitro世代 | CPU | アーキテクチャ | 備考 |
|:---|:---|:---|:---|:---|
| **A1** | v2 | AWS Graviton | ARM64 | 初代Graviton |
| **T3/T3a** | v2 | Intel Xeon / AMD EPYC | x86-64 | バースト可能 |
| **T4g** | v2 | AWS Graviton2 | ARM64 | バースト可能 |
| **M5/M5d** | v2 | Intel Xeon (Skylake/Cascade Lake) | x86-64 | - |
| **M5a/M5ad** | v2 | AMD EPYC (Rome) | x86-64 | - |
| **M5n/M5dn** | v3 | Intel Xeon (Cascade Lake) | x86-64 | 高帯域ネットワーク |
| **M5zn** | v3 | Intel Xeon (Cascade Lake) | x86-64 | 高周波数 |
| **M6g/M6gd** | v2 | AWS Graviton2 | ARM64 | - |
| **M6i/M6id** | v4 | Intel Xeon (Ice Lake) | x86-64 | - |
| **M6in/M6idn** | v4 | Intel Xeon (Ice Lake) | x86-64 | 高帯域ネットワーク |
| **M6a** | v4 | AMD EPYC (Milan) | x86-64 | - |
| **M7g/M7gd** | v4 | AWS Graviton3 | ARM64 | - |
| **M7i/M7i-flex** | v4 | Intel Xeon (Sapphire Rapids) | x86-64 | - |
| **M7a** | v4 | AMD EPYC (Genoa) | x86-64 | - |
| **M8g/M8gd** | v5 | AWS Graviton4 | ARM64 | - |
| **M8a** | v6 | AMD EPYC | x86-64 | 最新世代 |
| **M8i/M8i-flex** | v6 | Intel Xeon (Emerald Rapids) | x86-64 | 最新世代 |

**コンピューティング最適化インスタンス（Compute Optimized）詳細：**

| インスタンス | Nitro世代 | CPU | アーキテクチャ | 備考 |
|:---|:---|:---|:---|:---|
| **C5/C5d** | v2 | Intel Xeon (Skylake/Cascade Lake) | x86-64 | - |
| **C5a/C5ad** | v2 | AMD EPYC (Rome) | x86-64 | - |
| **C5n** | v3 | Intel Xeon (Skylake) | x86-64 | 高帯域ネットワーク（100Gbps） |
| **C6g/C6gd** | v2 | AWS Graviton2 | ARM64 | - |
| **C6gn** | v4 | AWS Graviton2 | ARM64 | 高帯域ネットワーク（100Gbps） |
| **C6i/C6id** | v4 | Intel Xeon (Ice Lake) | x86-64 | - |
| **C6in** | v4 | Intel Xeon (Ice Lake) | x86-64 | 高帯域ネットワーク（200Gbps） |
| **C6a** | v4 | AMD EPYC (Milan) | x86-64 | - |
| **C7g/C7gd** | v4 | AWS Graviton3 | ARM64 | - |
| **C7gn** | v5 | AWS Graviton3E | ARM64 | 高帯域ネットワーク（200Gbps） |
| **C7i/C7i-flex** | v4 | Intel Xeon (Sapphire Rapids) | x86-64 | - |
| **C7a** | v4 | AMD EPYC (Genoa) | x86-64 | - |
| **C8g/C8gd** | v5 | AWS Graviton4 | ARM64 | - |
| **C8gn** | v6 | AWS Graviton4 | ARM64 | 高帯域ネットワーク（400Gbps）、最新世代 |
| **C8a** | v6 | AMD EPYC | x86-64 | 最新世代 |
| **C8i/C8i-flex** | v6 | Intel Xeon (Emerald Rapids) | x86-64 | 最新世代 |

**メモリ最適化インスタンス（Memory Optimized）詳細：**

| インスタンス | Nitro世代 | CPU | アーキテクチャ | 備考 |
|:---|:---|:---|:---|:---|
| **R5/R5d** | v2 | Intel Xeon (Skylake/Cascade Lake) | x86-64 | - |
| **R5a/R5ad** | v2 | AMD EPYC (Rome) | x86-64 | - |
| **R5b** | v2 | Intel Xeon (Cascade Lake) | x86-64 | 高EBS帯域幅 |
| **R5n/R5dn** | v3 | Intel Xeon (Cascade Lake) | x86-64 | 高帯域ネットワーク |
| **R6g/R6gd** | v2 | AWS Graviton2 | ARM64 | - |
| **R6i/R6id** | v4 | Intel Xeon (Ice Lake) | x86-64 | - |
| **R6in/R6idn** | v4 | Intel Xeon (Ice Lake) | x86-64 | 高帯域ネットワーク |
| **R6a** | v4 | AMD EPYC (Milan) | x86-64 | - |
| **R7g/R7gd** | v4 | AWS Graviton3 | ARM64 | - |
| **R7i** | v4 | Intel Xeon (Sapphire Rapids) | x86-64 | - |
| **R7iz** | v4 | Intel Xeon (Sapphire Rapids) | x86-64 | 高周波数 |
| **R7a** | v4 | AMD EPYC (Genoa) | x86-64 | - |
| **R8g/R8gd** | v5 | AWS Graviton4 | ARM64 | - |
| **X8g** | v5 | AWS Graviton4 | ARM64 | 大容量メモリ |
| **R8gb** | v6 | AWS Graviton4 | ARM64 | 最新世代 |
| **R8gn** | v6 | AWS Graviton4 | ARM64 | 高帯域ネットワーク、最新世代 |
| **R8a** | v6 | AMD EPYC | x86-64 | 最新世代 |
| **R8i/R8i-flex** | v6 | Intel Xeon (Emerald Rapids) | x86-64 | 最新世代 |
| **X8aedz** | v6 | AMD EPYC | x86-64 | 大容量メモリ、最新世代 |
| **U7i/U7in/U7inh** | v4 | Intel Xeon | x86-64 | 高メモリ（6TB-32TB） |
| **X2gd** | v2 | AWS Graviton2 | ARM64 | 大容量メモリ |
| **X2idn/X2iedn** | v4 | Intel Xeon (Ice Lake) | x86-64 | 大容量メモリ |
| **X2iezn** | v3 | Intel Xeon (Cascade Lake) | x86-64 | 大容量メモリ |
| **z1d** | v2 | Intel Xeon (Skylake) | x86-64 | 高周波数 |

**ストレージ最適化インスタンス（Storage Optimized）詳細：**

| インスタンス | Nitro世代 | CPU | アーキテクチャ | ローカルストレージ | 備考 |
|:---|:---|:---|:---|:---|:---|
| **D3/D3en** | v3 | Intel Xeon (Cascade Lake) | x86-64 | HDD | 高密度HDD |
| **I3en** | v3 | Intel Xeon (Cascade Lake) | x86-64 | NVMe SSD | - |
| **I4g** | v4 | AWS Graviton2 | ARM64 | NVMe SSD | - |
| **I4i** | v4 | Intel Xeon (Ice Lake) | x86-64 | NVMe SSD | - |
| **Im4gn** | v4 | AWS Graviton2 | ARM64 | NVMe SSD | - |
| **Is4gen** | v4 | AWS Graviton2 | ARM64 | NVMe SSD | - |
| **I7i** | v4 | Intel Xeon (Sapphire Rapids) | x86-64 | NVMe SSD | - |
| **I7ie** | v5 | Intel Xeon (Emerald Rapids) | x86-64 | NVMe SSD | - |
| **I8g** | v5 | AWS Graviton4 | ARM64 | NVMe SSD | - |
| **I8ge** | v6 | AWS Graviton4 | ARM64 | NVMe SSD | 最新世代 |

**アクセラレーテッドコンピューティングインスタンス（Accelerated Computing）詳細：**

| インスタンス | Nitro世代 | GPU/アクセラレータ | 備考 |
|:---|:---|:---|:---|
| **G4ad** | v3 | AMD Radeon Pro V520 | グラフィクス |
| **G4dn** | v3 | NVIDIA T4 | 推論向け |
| **G5** | v3 | NVIDIA A10G | 推論/グラフィクス |
| **G5g** | v2 | NVIDIA T4G | ARM64推論 |
| **G6/G6e/G6f** | v4 | NVIDIA L4 | 推論/グラフィクス |
| **Gr6/Gr6f** | v4 | NVIDIA L4 | グラフィクス |
| **F2** | v4 | AMD Alveo U55C FPGA | FPGA |
| **Inf1** | v3 | AWS Inferentia | 推論向け |
| **Inf2** | v4 | AWS Inferentia2 | 推論向け |
| **DL1** | v3 | Habana Gaudi | 学習向け |
| **DL2q** | v3 | Qualcomm AI 100 | 推論向け |
| **VT1** | v3 | Xilinx Alveo U30 | ビデオトランスコード |
| **P3dn** | v3 | NVIDIA V100 (32GB) | 学習向け |
| **P4d/P4de** | v3 | NVIDIA A100 (40/80GB) | 学習向け |
| **P5/P5e** | v4 | NVIDIA H100 (80GB) | 学習向け |
| **P5en** | v5 | NVIDIA H200 | 学習向け、RDMA対応 |
| **P6e-GB200** | v5 | NVIDIA GB200 | 学習向け |
| **P6-B200/P6-B300** | v6 | NVIDIA B200/B300 | 学習向け、最新世代 |
| **Trn1/Trn1n** | v4 | AWS Trainium | 学習向け |
| **Trn2/Trn2u** | v5 | AWS Trainium2 | 学習向け |

**HPC（High Performance Computing）インスタンス詳細：**

| インスタンス | Nitro世代 | CPU | 備考 |
|:---|:---|:---|:---|
| **Hpc6a** | v4 | AMD EPYC (Milan) | HPC向け |
| **Hpc6id** | v4 | Intel Xeon (Ice Lake) | HPC向け |
| **Hpc7a** | v4 | AMD EPYC (Genoa) | HPC向け |
| **Hpc7g** | v5 | AWS Graviton3E | HPC向け、ARM64 |

**ベアメタルインスタンス対応Nitro世代：**

| Nitro世代 | 対応ベアメタルインスタンス |
|:---|:---|
| **v6** | M8a, M8i, C8a, C8gn, C8i, R8a, R8gb, R8gn, R8i, X8aedz, I8ge |
| **v5** | M8g, M8gd, Mac-m4, Mac-m4pro, C7gn, C8g, C8gd, R8g, R8gd, X8g, I7ie, I8g |
| **v4** | M6a, M6i, M6id, M6idn, M6in, M7a, M7g, M7gd, M7i, C6a, C6i, C6id, C6in, C7a, C7g, C7gd, C7i, R6a, R6i, R6id, R6idn, R6in, R7a, R7g, R7gd, R7i, R7iz, X2idn, X2iedn, I4i, I7i |
| **v3** | M5dn, M5n, M5zn, C5n, R5dn, R5n, U-6tb1〜U-24tb1, X2iezn, I3en, G4dn |
| **v2** | A1, M5, M5d, M6g, M6gd, Mac1, Mac2, Mac2-m1ultra, Mac2-m2, Mac2-m2pro, C5, C5d, C6g, C6gd, R5, R5b, R5d, R6g, R6gd, X2gd, z1d, I3, G5g |


### 3.2 Microsoft Azure

#### 3.2.1 Azure Boost

Azure Boostは、Microsoftが2023年から提供しているハードウェアオフロードスイートです。

**Azure Boost/SmartNIC世代別履歴：**

| 世代 | リリース時期 | 技術 | 特徴 |
|:---|:---|:---|:---|
| **第1世代** | 2015年〜 | FPGA SmartNIC | Project Catapult、SDNアクセラレーション |
| **第2世代** | 2020年〜 | FPGA + Mellanox NIC | 80G NIC、HBv4向け |
| **Azure Boost** | 2023年7月（プレビュー）、2023年11月（GA） | MANA + FPGA | 統合オフロードスイート |
| **Azure Boost 次世代** | 2025年11月（プレビュー） | MANA + FPGA + HSM | 1M IOPS、20GB/s、400Gbps、RDMA対応、ABCD（Confidential Device） |

**コンポーネント詳細：**

| カテゴリ | コンポーネント | リリース時期 | 機能説明 | 性能指標 |
|:---|:---|:---|:---|:---|
| **ネットワーク** | MANA (Microsoft Azure Network Adapter) | 2023年 | ネットワークアクセラレーション、SR-IOV、FPGA搭載 | 最大200 Gbps |
| **ネットワーク** | FPGA SmartNIC | 2015年〜 | プログラマブルネットワーク処理、Project Catapult | 低レイテンシ |
| **ネットワーク** | InfiniBand (NVIDIA Quantum-2) | 2020年〜 | HPC/AI向けRDMA（NDシリーズ） | 最大3,200 Gbps |
| **ストレージ** | Azure Boost NVMeオフロード | 2023年 | ストレージI/O処理のFPGAオフロード | リモート: 14 GB/s、750K IOPS |
| **ストレージ** | Azure Boost SSD | 2023年 | ローカルSSDアクセス、暗号化 | 36 GB/s、6.6M IOPS |
| **セキュリティ** | Pluton Security Processor | 2020年/2022年 | ハードウェアRoot of Trust | - |
| **セキュリティ** | Cerberus | 2023年 | Azure Boost HW Root of Trust | NIST 800-193 |
| **セキュリティ** | Azure Confidential Computing | 2019年（GA） | TEE（Intel SGX/AMD SEV-SNP/Intel TDX） | メモリ暗号化 |
| **管理** | OpenHCL | 2024年（OSS化） | Linux/Rustベースパラバーチャライザー | ゲスト互換性向上 |

#### 3.2.2 Azure仮想化アーキテクチャ詳細

Microsoft Azureは、CPUアーキテクチャによって異なる仮想化基盤を採用しています。

**Microsoft Hypervisor (MSHV) とは：**

| 項目 | 説明 |
|:---|:---|
| **タイプ** | Type 1（ベアメタル）ハイパーバイザー |
| **対応アーキテクチャ** | x86-64、ARM64 |
| **関係性** | Hyper-V仮想化スタックの基盤コンポーネント |
| **Linux対応** | mshv_vtlドライバ（/dev/mshv）でLinuxをルートパーティションとして実行可能 |
| **オープンソース** | Linuxカーネルドライバ、Rust bindings等をOSS化（2020年〜） |
| **特徴** | ネステッド仮想化、AMD SEV-SNP/Intel TDXによるConfidential Computing対応 |

**CPUアーキテクチャ別仮想化構成：**

| 項目 | x86-64環境 | ARM64環境 |
|:---|:---|:---|
| **ホストOS** | Azure Host OS（Windows派生の最小構成OS） | Azure Host OS（Linux/MSHV） |
| **ハイパーバイザー** | Hyper-V（MSHV上） | Microsoft Hypervisor (MSHV) |
| **パラバイザー** | OpenHCL（Azure Boost SKU） | OpenHCL（必須） |
| **ゲストOS** | Windows Server、Linux各種 | Linux各種、Windows 11（クライアント） |
| **ネステッド仮想化** | ✅ 対応（Dv3/Ev3等） | ❌ 未対応 |
| **Confidential VM** | ✅ AMD SEV-SNP、Intel TDX | ✅ Arm CCA（Cobalt 200〜） |
| **主なVMシリーズ** | Dv5、Ev5、NCシリーズ等 | Dpsv5/6、Epsv5/6（Ampere/Cobalt） |

**OpenHCLパラバイザーの役割：**

OpenHCL（Open Hardware Compatibility Layer）は、Microsoftが開発したRust製のパラバイザーで、2024年10月にオープンソース化されました。

| 機能 | 説明 |
|:---|:---|
| **デバイスエミュレーション** | vTPM、シリアルポート等の仮想デバイス提供 |
| **デバイストランスレーション** | Azure Boost NVMe/MANAへのゲストアクセス橋渡し |
| **Azure Boost連携** | 200Gbpsネットワーク、高性能ストレージI/Oの実現 |
| **Confidential Computing** | 信頼境界内でのセキュアなサービス提供 |
| **ゲスト互換性** | 古いWindows/Linuxカーネルでも最新機能を利用可能 |
| **対応プラットフォーム** | x86-64、ARM64、Intel TDX、AMD SEV-SNP |

**Azure x86-64 VMの仮想化スタック（v6世代以降、Azure Boost搭載）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                ゲストOS (Windows/Linux)                          │
│              ┌─────────────────────────────────────┐            │
│              │        ゲストドライバ                 │            │
│              │  MANA (ネットワーク) / NVMe (ストレージ) │           │
│              │  hv_vmbus / hv_storvsc / hv_netvsc   │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│                    VTL0 (Virtual Trust Level 0)                  │
│                      通常のゲスト実行環境                          │
├─────────────────────────────────────────────────────────────────┤
│                    VTL2 (Virtual Trust Level 2)                  │
│                    OpenHCL パラバイザー                           │
│  ┌─────────────────────┐  ┌───────────────────────────────┐    │
│  │     OpenVMM          │  │     最小Linux カーネル          │    │
│  │   (Rust VMM)         │  │   デバイスエミュレーション        │    │
│  │   vTPM、シリアル      │  │   I/Oトランスレーション          │    │
│  └─────────────────────┘  └───────────────────────────────┘    │
├─────────────────────────────────────────────────────────────────┤
│           Microsoft Hypervisor (MSHV)                            │
│    (Type 1 ハイパーバイザー、VSM対応、Intel VT-x/AMD-V)            │
├─────────────────────────────────────────────────────────────────┤
│                    Azure Host OS                                 │
│           (VMライフサイクル管理、Azure Fabric連携)                  │
├─────────────────────────────────────────────────────────────────┤
│   Azure Boost Hardware (FPGA + MANA NIC、NVMe SSD)               │
│              ネットワーク/ストレージオフロード                       │
├─────────────────────────────────────────────────────────────────┤
│        Intel Xeon (Sapphire Rapids/Emerald Rapids)               │
│        AMD EPYC (Genoa/Bergamo/Turin)                            │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴（x86-64 Azure Boost搭載VM）：**
- **VSM技術**: Virtual Secure Mode（VTL0/VTL2分離）でパラバイザーをゲスト内高特権領域に配置
- **OpenHCL**: Rustベースの安全なパラバイザー（メモリ安全性保証）
- **テナント分離**: 各VMが独自のパラバイザーを持ち、ホストや他VMと共有なし
- **直接デバイスアクセス**: Enlightened VM（MANA/NVMeドライバ搭載）はAzure Boostハードウェアと直接通信

**Azure x86-64 VMの仮想化スタック（v5世代以前、従来型）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                ゲストOS (Windows/Linux)                          │
│              ┌─────────────────────────────────────┐            │
│              │        ゲストドライバ                 │            │
│              │  hv_vmbus / hv_storvsc / hv_netvsc   │            │
│              │       (Hyper-V統合サービス)           │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│           Microsoft Hypervisor (Hyper-V)                         │
│       (Type 1 ハイパーバイザー、Intel VT-x/AMD-V)                  │
├─────────────────────────────────────────────────────────────────┤
│                    Azure Host OS                                 │
│       ┌───────────────────────────────────────────────┐         │
│       │  VMBus / VSP (Virtualization Service Provider) │         │
│       │  ストレージVSP、ネットワークVSP、合成デバイス    │         │
│       └───────────────────────────────────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│                    物理ハードウェア                               │
│           NIC (SR-IOV対応) / SSD / ネットワークスイッチ            │
├─────────────────────────────────────────────────────────────────┤
│        Intel Xeon (Skylake/Cascade Lake/Ice Lake)                │
│        AMD EPYC (Rome/Milan)                                     │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴（x86-64 従来型VM）：**
- **VMBus**: ホストOSとゲストOS間の高速通信チャネル
- **VSP/VSC**: Virtualization Service Provider（ホスト側）とVirtualization Service Client（ゲスト側）の連携
- **合成デバイス**: ソフトウェアエミュレーションによる仮想デバイス

**Azure Confidential VMの仮想化スタック（AMD SEV-SNP/Intel TDX）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                ゲストOS (Windows/Linux)                          │
│              ┌─────────────────────────────────────┐            │
│              │   暗号化されたゲストメモリ空間          │            │
│              │   (ホスト・ハイパーバイザーからも不可視)  │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│                    OpenHCL パラバイザー (VTL2)                    │
│         TEE（Trusted Execution Environment）内で動作              │
│              vTPM、構成証明（Attestation）サポート                  │
├─────────────────────────────────────────────────────────────────┤
│           Microsoft Hypervisor (MSHV)                            │
│              ゲストメモリへのアクセス不可                           │
├─────────────────────────────────────────────────────────────────┤
│                    Azure Host OS                                 │
│              ゲストメモリへのアクセス不可                           │
├─────────────────────────────────────────────────────────────────┤
│   Azure Boost + Confidential Device (ABCD)                       │
│              セキュアI/Oオフロード                                │
├─────────────────────────────────────────────────────────────────┤
│   AMD EPYC (SEV-SNP対応: Milan/Genoa)                            │
│   Intel Xeon (TDX対応: Sapphire Rapids以降)                       │
│        ハードウェアメモリ暗号化エンジン内蔵                         │
└─────────────────────────────────────────────────────────────────┘
```

**Confidential VMの特徴：**
- **ハードウェアベース分離**: AMD SEV-SNP / Intel TDXによるメモリ暗号化
- **ゼロトラスト**: ホストOS、ハイパーバイザー、Azureオペレーターからもデータ保護
- **リモート構成証明**: TPM 2.0ベースの構成証明でVM完全性検証可能
- **ABCD（Azure Boost Confidential Device）**: Confidential VM専用I/Oオフロード

**重要な制約事項（x86-64）：**
- **ネステッド仮想化対応**：Dv3/Ev3/Fsv2/Dv4/Ev4以降のシリーズで対応（Hyper-V in VM）
- **Confidential VM**: DCasv5/DCadsv5（AMD SEV-SNP）、DCesv5/DCedsv5（Intel TDX）で対応

**Azure ARM64 VMの仮想化スタック：**

```
┌─────────────────────────────────────────────────────┐
│              ゲストOS (Linux/Windows 11)            │
├─────────────────────────────────────────────────────┤
│                    OpenHCL パラバイザー              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  OpenVMM    │  │  デバイス   │  │ Confidential │  │
│  │  (Rust VMM) │  │ エミュレーション │  │  Computing  │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
├─────────────────────────────────────────────────────┤
│           Microsoft Hypervisor (MSHV)               │
│        (Type 1 ハイパーバイザー、ARM64対応)          │
├─────────────────────────────────────────────────────┤
│                  Azure Host OS                      │
├─────────────────────────────────────────────────────┤
│    Azure Boost Hardware (MANA NIC、NVMe SSD)        │
├─────────────────────────────────────────────────────┤
│   Ampere Altra / Azure Cobalt 100/200 (ARM64 CPU)   │
└─────────────────────────────────────────────────────┘
```

**重要な制約事項：**
- **ネステッド仮想化未対応**：Azure ARM64 VMではネステッド仮想化（KVM in VM等）は未サポート
- **Windows Server未対応**：Windows Server ARM64版は存在しないため、ARM64 VMではLinuxまたはWindows 11クライアントのみ
- **Hyper-Vではない**：ARM64 VMはHyper-V ARM64ではなく、MSHV + OpenHCLで動作

#### 3.2.3 Azure Cobalt

**Azure Cobalt 200（2025年11月発表、2026年GA予定）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | Azure Cobalt 200 |
| **アーキテクチャ** | Arm Neoverse CSS V3（Neoverse V3コア） |
| **製造プロセス** | TSMC 3nm |
| **チップレット構成** | 2チップレット（各66コア） |
| **コア数** | 132コア/SoC（デュアルソケットで最大264コア） |
| **L2キャッシュ** | 3MB/コア（396MB総計） |
| **L3キャッシュ** | 192MB（システムキャッシュ） |
| **メモリチャネル** | 12チャネル DDR5/ソケット |
| **専用アクセラレータ** | データ移動アクセラレータ、暗号化/圧縮アクセラレータ |
| **セキュリティ** | デフォルトメモリ暗号化、Arm CCA（Confidential Compute Architecture） |
| **Cobalt 100比性能** | 50%向上 |

**Azure Cobalt 100（2024年11月GA）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | Azure Cobalt 100 |
| **アーキテクチャ** | Arm Neoverse N2 |
| **コア数** | 128コア |
| **周波数** | 3.4 GHz |
| **メモリ** | 最大672 GiB（Epsv6インスタンス） |
| **最大vCPU** | 96 vCPU |
| **対応インスタンス** | Dpsv6, Dplsv6, Epsv6 |
| **展開リージョン** | 32リージョン |
| **x86比価格性能** | 最大99%向上 |

**Azure Cobalt VMシリーズ：**

| VMシリーズ | CPU | 仮想化基盤 | 最大vCPU | 最大メモリ | 特徴 |
|:---|:---|:---|:---|:---|:---|
| **Dpsv5** | Ampere Altra | MSHV + OpenHCL | 64 | 208 GiB | 汎用（4 GiB/vCPU） |
| **Dplsv5** | Ampere Altra | MSHV + OpenHCL | 64 | 128 GiB | 汎用（2 GiB/vCPU） |
| **Epsv5** | Ampere Altra | MSHV + OpenHCL | 32 | 208 GiB | メモリ最適化（8 GiB/vCPU） |
| **Dpsv6** | Azure Cobalt 100 | MSHV + OpenHCL | 96 | 384 GiB | 汎用（4 GiB/vCPU）、1.4x性能向上 |
| **Dplsv6** | Azure Cobalt 100 | MSHV + OpenHCL | 96 | 192 GiB | 汎用（2 GiB/vCPU） |
| **Epsv6** | Azure Cobalt 100 | MSHV + OpenHCL | 96 | 672 GiB | メモリ最適化（7 GiB/vCPU） |

**Azure Cobalt プロセッサロードマップ：**

| プロセッサ | ステータス | コア数 | アーキテクチャ | 特徴 |
|:---|:---|:---|:---|:---|
| **Cobalt 100** | GA（2024年10月） | 128コア | Arm Neoverse N2 | Azure初のカスタムARM CPU |
| **Cobalt 200** | 2026年予定 | 132コア | Arm Neoverse V3 | 50%性能向上、Arm CCA対応、カスタム暗号アクセラレータ |

#### 3.2.4 Azure ストレージアーキテクチャ

**リモートブロックストレージ（Azure Managed Disks）：**

| ディスクタイプ | 用途 | 最大IOPS/ディスク | 最大スループット/ディスク | 最大容量 | レイテンシ |
|:---|:---|:---|:---|:---|:---|
| **Ultra Disk** | SAP HANA、トップティアDB | 400,000 IOPS | 10,000 MB/s | 64 TiB | サブミリ秒 |
| **Premium SSD v2** | SQL Server、Oracle、汎用高性能 | 80,000 IOPS | 1,200 MB/s | 64 TiB | サブミリ秒 |
| **Premium SSD** | 本番DB、Webサーバー | 20,000 IOPS | 900 MB/s | 32 TiB | 1桁ms |
| **Standard SSD** | 開発/テスト、Webサーバー | 6,000 IOPS | 750 MB/s | 32 TiB | 1桁ms |
| **Standard HDD** | バックアップ、アーカイブ | 2,000 IOPS | 500 MB/s | 32 TiB | - |

**ローカルインスタンスストレージ（NVMe SSD）：**

| VMシリーズ | ローカルストレージ | ディスク構成 | 最大IOPS | 最大スループット | 用途 |
|:---|:---|:---|:---|:---|:---|
| **Lsv3** | 最大11.52 TB | NVMe SSD | 3,800,000 IOPS | 36 GB/s | ストレージ最適化 |
| **Lasv3** | 最大11.52 TB | NVMe SSD（AMD） | 3,800,000 IOPS | 36 GB/s | AMD版ストレージ最適化 |
| **Ddsv5** | 最大3.6 TB | NVMe SSD | 1,200,000 IOPS | 6.6 GB/s | 汎用+ローカルSSD |

**Azure Boost ストレージオフロード性能（2025年次世代）：**
- リモートストレージ：1,000,000 IOPS、20 GB/s
- ローカルSSD：6,600,000 IOPS、36 GB/s
- Azure Boost Confidential Device（ABCD）：CVM向けセキュアI/Oオフロード

#### 3.2.5 Azure GPUインスタンス一覧

**NDシリーズ（ハイエンドトレーニング）：**

| インスタンス | GPU | GPU数 | GPUメモリ合計 | vCPU | システムメモリ | ネットワーク | リリース時期 | 主な用途 |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **ND H200 v5** | H200 | 8 | 1,128 GB | 96 | 900 GB | 3,200 Gbps IB | 2024年11月GA | 最新LLMトレーニング |
| **ND H100 v5** | H100 SXM | 8 | 640 GB | 96 | 900 GB | 3,200 Gbps IB | 2024年1月GA | 大規模AIトレーニング |
| **ND A100 v4** | A100 40GB | 8 | 320 GB | 96 | 900 GB | 1,600 Gbps IB | 2021年8月GA | AIトレーニング/HPC |
| **NDm A100 v4** | A100 80GB | 8 | 640 GB | 96 | 1,900 GB | 1,600 Gbps IB | 2022年GA | 大規模メモリワークロード |

**NDシリーズの特徴：**
- NVIDIA Quantum-2 InfiniBand (400 Gb/s/GPU)
- NVLink 4.0によるGPU間通信


#### 3.2.6 Microsoft Azure世代別インスタンスタイプ

**Azure VMシリーズ世代と仮想化基盤：**

| 世代 | 仮想化基盤 | ハードウェア特徴 | ストレージ接続 | 主な機能 |
|:---|:---|:---|:---|:---|
| **v4以前** | Hyper-V | 従来型VMBus | SCSI | SR-IOV対応 |
| **v5** | MSHV + Azure Boost | FPGA + MANA NIC | SCSI/NVMe | Azure Boost有効 |
| **v6** | MSHV + OpenHCL + Azure Boost | DPU + MANA NIC | NVMe必須 | VSM分離、NVMe必須 |
| **ARM64 (p)** | MSHV + OpenHCL | Ampere/Cobalt | NVMe | ARM64専用仮想化 |

**汎用インスタンス（General Purpose - Dシリーズ）：**

| VMシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Azure Boost | NVMe |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Dv4/Dsv4** | v4 | Intel Xeon (Cascade Lake) | x86-64 | 64 | 256 GiB | ❌ | ❌ |
| **Dav4/Dasv4** | v4 | AMD EPYC (Rome) | x86-64 | 96 | 384 GiB | ❌ | ❌ |
| **Dv5/Dsv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 96 | 384 GiB | ✅ | ❌ |
| **Dav5/Dasv5** | v5 | AMD EPYC (Milan) | x86-64 | 96 | 384 GiB | ✅ | ❌ |
| **Ddv5/Ddsv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 96 | 384 GiB | ✅ | ❌ |
| **Dadv5/Dadsv5** | v5 | AMD EPYC (Milan) | x86-64 | 96 | 384 GiB | ✅ | ❌ |
| **Dlsv5/Dldsv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 96 | 192 GiB | ✅ | ❌ |
| **Dalsv5/Daldsv5** | v5 | AMD EPYC (Milan) | x86-64 | 96 | 192 GiB | ✅ | ❌ |
| **Dv6/Dsv6** | v6 | Intel Xeon (Emerald Rapids) | x86-64 | 128 | 512 GiB | ✅ | ✅ |
| **Dav6/Dasv6** | v6 | AMD EPYC (Genoa) | x86-64 | 96 | 384 GiB | ✅ | ✅ |
| **Dalsv6** | v6 | AMD EPYC (Genoa) | x86-64 | 96 | 192 GiB | ✅ | ✅ |
| **Dpsv5** | ARM64 | Ampere Altra | ARM64 | 64 | 208 GiB | ✅ | ✅ |
| **Dplsv5** | ARM64 | Ampere Altra | ARM64 | 64 | 128 GiB | ✅ | ✅ |
| **Dpsv6** | ARM64 | Azure Cobalt 100 | ARM64 | 96 | 384 GiB | ✅ | ✅ |
| **Dplsv6** | ARM64 | Azure Cobalt 100 | ARM64 | 96 | 192 GiB | ✅ | ✅ |

**メモリ最適化インスタンス（Memory Optimized - Eシリーズ）：**

| VMシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Azure Boost | NVMe |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Ev4/Esv4** | v4 | Intel Xeon (Cascade Lake) | x86-64 | 64 | 504 GiB | ❌ | ❌ |
| **Eav4/Easv4** | v4 | AMD EPYC (Rome) | x86-64 | 96 | 672 GiB | ❌ | ❌ |
| **Ev5/Esv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 104 | 672 GiB | ✅ | ❌ |
| **Eav5/Easv5** | v5 | AMD EPYC (Milan) | x86-64 | 96 | 672 GiB | ✅ | ❌ |
| **Edv5/Edsv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 104 | 672 GiB | ✅ | ❌ |
| **Eadv5/Eadsv5** | v5 | AMD EPYC (Milan) | x86-64 | 96 | 672 GiB | ✅ | ❌ |
| **Ebsv5/Ebdsv5** | v5 | Intel Xeon (Ice Lake) | x86-64 | 120 | 672 GiB | ✅ | ❌ |
| **Easv6** | v6 | AMD EPYC (Genoa) | x86-64 | 96 | 672 GiB | ✅ | ✅ |
| **Epsv5** | ARM64 | Ampere Altra | ARM64 | 32 | 208 GiB | ✅ | ✅ |
| **Epsv6** | ARM64 | Azure Cobalt 100 | ARM64 | 96 | 672 GiB | ✅ | ✅ |

**コンピューティング最適化インスタンス（Compute Optimized - Fシリーズ）：**

| VMシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Azure Boost | NVMe |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Fsv2** | v2 | Intel Xeon (Skylake/Cascade Lake) | x86-64 | 72 | 144 GiB | ❌ | ❌ |
| **Fasv5** | v5 | AMD EPYC (Milan) | x86-64 | 64 | 128 GiB | ✅ | ❌ |
| **Falsv6/Fasv6/Famsv6** | v6 | AMD EPYC (Genoa) | x86-64 | 96 | 384 GiB | ✅ | ✅ |

**HPC/GPUインスタンス：**

| VMシリーズ | 世代 | CPU | GPU/アクセラレータ | 最大GPU数 | ネットワーク | 備考 |
|:---|:---|:---|:---|:---|:---|:---|
| **HBv3** | v3 | AMD EPYC (Milan-X) | - | - | 200 Gbps (InfiniBand) | HPC向け |
| **HBv4** | v4 | AMD EPYC (Genoa-X) | - | - | 400 Gbps (InfiniBand) | HPC向け |
| **HX** | v4 | AMD EPYC (Genoa-X) | - | - | 400 Gbps (InfiniBand) | メモリ最適化HPC |
| **NCv3** | v3 | Intel Xeon | NVIDIA V100 | 4 | 32 Gbps | 学習向け |
| **NCasT4_v3** | v3 | AMD EPYC | NVIDIA T4 | 4 | 32 Gbps | 推論向け |
| **NVv4** | v4 | AMD EPYC | AMD Radeon Instinct MI25 | 1 | 32 Gbps | グラフィクス |
| **NCads_A100_v4** | v4 | AMD EPYC | NVIDIA A100 (80GB) | 4 | 800 Gbps (InfiniBand) | 学習向け |
| **ND_A100_v4** | v4 | AMD EPYC | NVIDIA A100 (80GB) | 8 | 1,600 Gbps (InfiniBand) | 学習向け |
| **ND_H100_v5** | v5 | Intel Xeon | NVIDIA H100 (80GB) | 8 | 3,200 Gbps (InfiniBand) | 学習向け |
| **ND_H200_v5** | v5 | Intel Xeon | NVIDIA H200 | 8 | 3,200 Gbps (InfiniBand) | 学習向け |
| **ND_GB200_v6** | v6 | - | NVIDIA GB200 | 72 | 3,200 Gbps (InfiniBand) | 学習向け |

**Confidential Computing インスタンス：**

| VMシリーズ | 世代 | CPU | TEE技術 | 最大vCPU | 最大メモリ | 備考 |
|:---|:---|:---|:---|:---|:---|:---|
| **DCasv5/DCadsv5** | v5 | AMD EPYC (Milan) | AMD SEV-SNP | 96 | 384 GiB | Confidential VM |
| **DCesv5/DCedsv5** | v5 | Intel Xeon (Ice Lake) | Intel TDX | 96 | 384 GiB | Confidential VM |
| **ECasv5/ECadsv5** | v5 | AMD EPYC (Milan) | AMD SEV-SNP | 96 | 672 GiB | Confidential メモリ最適化 |
| **ECesv5/ECedsv5** | v5 | Intel Xeon (Ice Lake) | Intel TDX | 96 | 672 GiB | Confidential メモリ最適化 |


### 3.3 Google Cloud

#### 3.3.1 Google Cloud Titanium

Google Cloud Titaniumは、2層オフロードアーキテクチャを採用したハードウェアセキュリティプラットフォームです。

**Titaniumハードウェアセキュリティアーキテクチャコンポーネント：**

| コンポーネント | 機能 | セキュリティ上のメリット |
|:---|:---|:---|
| **Caliptra RTM（Root of Trust for Measurement）** | CPU/GPU/TPUなどSoC上のシリコンレベルRoT | 暗号サービス提供、構成証明、一意ID、物理サプライチェーン攻撃軽減 |
| **Titan チップ RoT** | プラットフォームブートフラッシュとBMC/PCH/CPU間に配置 | 物理改ざん防止、強力なID確立、コード認証・取り消し |
| **Titanium Offload Processor（TOP）** | 保存中・転送中データの暗号制御 | データ機密性・整合性保護、暗号オフロード |
| **カスタムマザーボード** | 専用設計、不要コネクタ削除 | DoS攻撃耐性、物理攻撃保護、フルシステム復元サポート |
| **Confidential Computing エンクレーブ** | TEE（高信頼実行環境）提供 | 管理者権限からの分離、テナント間分離、DRAM暗号化 |

**Titanium/IPU世代別履歴：**

| 世代 | リリース時期 | 技術 | 対応インスタンス | 特徴 |
|:---|:---|:---|:---|:---|
| **Titan** | 2017年 | セキュリティチップ | 全インスタンス | ハードウェアRoot of Trust |
| **Intel IPU (E2000/Mount Evans)** | 2022年10月（プレビュー）、2023年5月（GA） | Intel共同開発ASIC | C3 | 200Gbps、プログラマブルパケット処理 |
| **Titanium** | 2023年8月 | 2層オフロードアーキテクチャ | C3, N2以降 | IPU + TOP（スケールアウトオフロード） |
| **Titanium (5th Gen)** | 2024年4月 | 5th Gen Intel Xeon連携 | C4, N4 | 最新プロセッサ統合 |
| **Titanium SSD** | 2025年1月（GA） | カスタム設計SSD | C4A | Axion連携、ストレージオフロード最適化 |

**コンポーネント詳細：**

| カテゴリ | コンポーネント | 機能説明 | 性能指標 |
|:---|:---|:---|:---|
| **ネットワーク** | Titanium Adapter (IPU) | Intel共同開発、ネットワーク/ストレージオフロード | 200 Gbps、3倍PPS |
| **ネットワーク** | Titanium Offload Processor (TOP) | データセンター分散オフロード（Hoverboard） | オフホスト処理 |
| **ネットワーク** | gVNIC | 高性能仮想NIC | 最大200 Gbps |
| **ネットワーク** | Titanium ML Adapter | AI/ML向けRDMA | 最大3,200 Gbps |
| **ストレージ** | Titanium SSD | カスタム設計ローカルSSD | 高IOPS |
| **ストレージ** | Hyperdisk | 高性能ブロックストレージ（Titaniumオフロード） | 最大500K IOPS |
| **セキュリティ** | Caliptra RTM | シリコンパッケージ内RoT、暗号ID、構成証明 | OCP標準 |
| **セキュリティ** | Titan Security Chip | ハードウェアRoot of Trust、セキュアブート | マシンID確立 |
| **セキュリティ** | Confidential VMs | AMD SEV/Intel TDX対応、TEE | メモリ暗号化 |

**Google Cloud仮想化スタック（Titaniumアーキテクチャ）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                    ゲストOS (Linux/Windows)                      │
│              ┌─────────────────────────────────────┐            │
│              │        ゲストドライバ                 │            │
│              │   gVNIC (ネットワーク) / NVMe (ストレージ)│           │
│              │   VirtIO-Net / VirtIO-SCSI          │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│                    KVMハイパーバイザー                            │
│           (セキュリティ強化KVM、ネステッド仮想化対応)                │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Tier 1: オンホストオフロード              │  │
│  │  ┌─────────────────────┐  ┌─────────────────────────┐    │  │
│  │  │   Titanium Adapter   │  │   Titan Security Chip   │    │  │
│  │  │  (Intel IPU/ASIC)    │  │   (Root of Trust)       │    │  │
│  │  │  200Gbps ネットワーク  │  │   セキュアブート、ID確立   │    │  │
│  │  └─────────────────────┘  └─────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                    Caliptra RTM（シリコン内RoT）                  │
│              (OCP標準、構成証明、暗号サービス提供)                   │
├─────────────────────────────────────────────────────────────────┤
│        ホストCPU (Intel Xeon / AMD EPYC / Google Axion)          │
└───────────────────────────────────────────────────────┬─────────┘
                                                        │
                    データセンターネットワーク                │
                                                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Tier 2: スケールアウトオフロード               │
│  ┌─────────────────────────┐  ┌───────────────────────────┐  │
│  │  Titanium Offload       │  │   Hoverboard              │  │
│  │  Processor (TOP)        │  │   (仮想ネットワークルーティング) │  │
│  │  暗号化、ストレージI/O     │  │   動的フロー最適化           │  │
│  └─────────────────────────┘  └───────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │        Colossus (Exabyte-scale 分散ファイルシステム)       │  │
│  │              Hyperdisk Block Storage バックエンド          │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴：**
- **オフロード方式**: 2層構造（Tier 1: オンホスト + Tier 2: オフホスト/スケールアウト）
- **ハイパーバイザー**: セキュリティ強化KVM
- **ネットワーク仮想化**: Andromeda仮想ネットワークスタック（IPU上で動作）
- **ストレージスケール**: ColossusによるExabyteスケールの分散ストレージ
- **独自設計**: Titanium SSD、カスタムマザーボード

**重要な制約事項：**
- **ネステッド仮想化対応**：x86-64（Intel VT-x）のみ。ARM64（Axion）では未サポート
- **L1ハイパーバイザー**: Linux KVMのみ対応（Hyper-V非対応）
- **ベアメタルインスタンス**: Titaniumオフロードシステムを直接利用

**Titaniumによる脅威軽減：**

| 脅威カテゴリ | 攻撃例 | Titaniumによる軽減策 |
|:---|:---|:---|
| **物理アクセス攻撃** | ストレージメディア持ち出し | 保存時暗号化、鍵はマシンに永続保存されない、Caliptra RTMによる構成証明 |
| **ネットワーク盗聴** | ケーブル傍受 | TOPによる転送中データ暗号化、PSPハードウェアオフロード（FIPS準拠） |
| **ファームウェア改ざん** | フラッシュチップ交換 | Titan RoTによるコード測定・報告、不正ファームウェア拒否 |
| **不正デバイス挿入** | USBスクリーマー、PCIeインターポーザ | カスタムマザーボード（不要インターフェース削除）、IOMMU設定 |
| **コールドブート攻撃** | RAM凍結・持ち出し | Confidential Computingメモリ内暗号化、DRAM暗号化 |

#### 3.3.2 Google Cloud Axion

**Google Axion C4A（2024年10月GA）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | Google Axion（第1世代） |
| **アーキテクチャ** | Arm Neoverse V2（ARMv9.0-A） |
| **製造プロセス** | TSMC 3nm（報告あり） |
| **コア数** | 最大72 vCPU（VM）、96 vCPU（metal） |
| **L2キャッシュ** | 2MB/コア（プライベート） |
| **L3キャッシュ** | 80MB |
| **メモリ** | DDR5-5600、最大576 GB（VM）、768 GB（metal） |
| **メモリアクセス** | UMA（Uniform Memory Access） |
| **ローカルストレージ** | 最大6 TiB Titanium SSD |
| **ネットワーク** | 最大50 Gbps標準、100 Gbps Tier_1 |
| **x86比価格性能** | 最大65%向上 |
| **x86比エネルギー効率** | 最大60%向上 |

**Google Axion N4A（2025年11月プレビュー）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | Google Axion（第2世代） |
| **アーキテクチャ** | Arm Neoverse N3 |
| **コア数** | 最大64 vCPU |
| **メモリ** | DDR5、最大512 GB |
| **メモリアクセス** | UMA（Uniform Memory Access） |
| **ネットワーク** | 最大50 Gbps（gVNIC必須） |
| **用途** | 価格性能重視、スケールアウトワークロード |
| **x86比価格性能** | 計算105%、Webサーバー90%、Java85%、DB20%向上 |

**Google Axion VM比較：**

| 項目 | C4A | N4A | C4A-metal |
|:---|:---|:---|:---|
| **アーキテクチャ** | Neoverse V2 | Neoverse N3 | Neoverse V2 |
| **最大vCPU** | 72 | 64 | 96 |
| **最大メモリ** | 576 GB | 512 GB | 768 GB |
| **最大ネットワーク** | 100 Gbps | 50 Gbps | 100 Gbps |
| **ローカルSSD** | 6 TiB Titanium | なし | なし |
| **用途** | 高性能、予測可能性 | コスト最適化、柔軟性 | ベアメタル、特殊用途 |
| **提供状況** | GA | プレビュー | プレビュー |

#### 3.3.3 Google Cloud TPU

**TPU v7 Ironwood（2025年GA）詳細：**

| 項目 | 仕様 | 前世代比（Trillium） |
|:---|:---|:---|
| **製造プロセス** | TSMC N3P | N5から進化 |
| **TensorCore数** | 2コア/チップ | 1コア/チップから変更 |
| **SparseCore** | 搭載（超大規模埋め込みモデル向け） | 強化 |
| **ピーク性能（FP8）** | 4,614 TFLOPS | 5x向上 |
| **ピーク性能（BF16）** | 2,307 TFLOPS | 5x向上 |
| **HBMメモリ** | 192 GB HBM3e（8スタック） | 6x増加（32GB→192GB） |
| **HBM帯域幅** | 7.37 TB/s | 4.5x向上 |
| **ICI帯域幅** | 1.2 TB/s（双方向、4リンク） | 1.5x向上 |
| **TDP** | ~1kW（液冷必須） | ~5x増加 |
| **電力効率（perf/watt）** | 2x向上（Trillium比） | 30x向上（v2比） |

**Ironwood Pod構成：**

| 構成 | チップ数 | 性能（FP8） | 性能（BF16） | 用途 |
|:---|:---|:---|:---|:---|
| **最小Pod** | 256 | 1.18 ExaFLOPS | 0.59 ExaFLOPS | 中規模モデル |
| **最大Pod（Superpod）** | 9,216 | 42.52 ExaFLOPS | 21.26 ExaFLOPS | 超大規模モデル |
| **理論最大（Jupiterネットワーク）** | ~400,000 | ~1.8 ZettaFLOPS | ~0.9 ZettaFLOPS | 43 Pod接続時 |

**Ironwoodの技術的特徴：**
- **チップレットアーキテクチャ**：2つの独立したチップレットで構成
- **デュアルTPUデバイス**：従来の単一論理コアから2デバイスモデルへ移行
- **液冷必須**：標準空冷の2倍の性能を持続可能
- **OCS（Optical Circuit Switching）対応**：データセンター内100,000チップ接続
- **JAXフレームワーク対応**：TensorFlowは非対応（JAX推奨）

**主要顧客・採用事例：**
- Anthropic：最大100万TPUでClaudeモデルのトレーニング・推論
- Google Gemini：内部モデル開発
- vLLM/SGLang：TPU v5p/v6eでベータサポート開始

#### 3.3.4 Google Cloud ストレージアーキテクチャ

**リモートブロックストレージ（Persistent Disk / Hyperdisk）：**

| ディスクタイプ | 用途 | 最大IOPS/ディスク | 最大スループット/ディスク | 最大容量 | レイテンシ |
|:---|:---|:---|:---|:---|:---|
| **Hyperdisk Extreme** | 高性能DB（SAP HANA） | 350,000 IOPS | 5,000 MB/s | 64 TiB | サブミリ秒 |
| **Hyperdisk Balanced** | 汎用高性能 | 160,000 IOPS | 2,400 MB/s | 64 TiB | サブミリ秒 |
| **Hyperdisk Throughput** | ストリーミング、分析 | - | 2,400 MB/s | 32 TiB | - |
| **Hyperdisk ML** | AI/MLデータローディング | - | 1,200 MB/s | 64 TiB | 低レイテンシ |
| **Extreme PD** | 高IOPS DB | 120,000 IOPS | - | 64 TiB | サブミリ秒 |
| **SSD PD** | 汎用SSD | 100,000 IOPS | 1,200 MB/s | 64 TiB | 1桁ms |
| **Balanced PD** | コスト効率 | 80,000 IOPS | 1,200 MB/s | 64 TiB | 1桁ms |
| **Standard PD（HDD）** | アーカイブ、バックアップ | 7,500 IOPS | 400 MB/s | 64 TiB | - |

**ローカルインスタンスストレージ（Local SSD / Titanium SSD）：**

| タイプ | 対応シリーズ | 単位容量 | 最大容量 | 最大IOPS（読取） | 最大スループット |
|:---|:---|:---|:---|:---|:---|
| **Titanium SSD** | C4A | 3,000 GiB | 9,000 GiB | 1,200,000 IOPS | 7.2 GB/s |
| **Local SSD** | C2/C3/N2 | 375 GiB | 9,000 GiB | 2,400,000 IOPS | 9.4 GB/s |
| **Local SSD（SCSI）** | N1/E2 | 375 GiB | 9,000 GiB | 900,000 IOPS | 6.5 GB/s |

**マシンシリーズ別インターフェース要件：**

| マシンシリーズ | 世代 | ネットワーク | ストレージ |
|:---|:---|:---|:---|
| N1, E2 | 第1世代 | VirtIO-Net / gVNIC | VirtIO-SCSI / NVMe |
| N2, N2D, C2, C2D | 第2世代 | VirtIO-Net / gVNIC | VirtIO-SCSI / NVMe |
| C3, C3D, M3 | 第3世代 | **gVNIC（必須）** | **NVMe（必須）** |
| C4, C4A, N4, N4A | 第4世代 | **gVNIC（必須）** | **NVMe（必須）** |
| Tau T2A（ARM） | 第2世代 | **gVNIC（必須）** | NVMe |

---

#### 3.3.5 Google Cloud Titanium世代別インスタンスタイプ

**Google Cloud VMシリーズ世代と特徴：**

| 世代 | Titanium対応 | 主なマシンシリーズ | ストレージ | ネットワーク | gVNIC |
|:---|:---|:---|:---|:---|:---|
| **第1世代** | ❌ | N1 | Persistent Disk | 最大32 Gbps | ❌（VirtIO-Net） |
| **第2世代** | ❌ | E2, N2, N2D, T2A, T2D | Persistent Disk | 最大100 Gbps | オプション |
| **第3世代** | ✅ | C3, C3D, H3 | Hyperdisk/PD | 最大200 Gbps | ✅（必須） |
| **第4/5世代** | ✅ | C4, C4A, C4D, N4, N4D, N4A, H4D, X4, Z3 | Hyperdisk | 最大200 Gbps | ✅（必須） |

**汎用マシンタイプ（General Purpose）：**

| マシンシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Titanium | ネットワーク |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **N1** | 第1世代 | Intel Xeon (Skylake/Broadwell) | x86-64 | 96 | 624 GiB | ❌ | 32 Gbps |
| **E2** | 第2世代 | Intel Xeon/AMD EPYC (混合) | x86-64 | 32 | 128 GiB | ❌ | 16 Gbps |
| **N2** | 第2世代 | Intel Xeon (Ice Lake/Cascade Lake) | x86-64 | 128 | 864 GiB | ❌ | 100 Gbps |
| **N2D** | 第2世代 | AMD EPYC (Milan) | x86-64 | 224 | 896 GiB | ❌ | 100 Gbps |
| **T2A** | 第2世代 | Ampere Altra | ARM64 | 48 | 192 GiB | ❌ | 32 Gbps |
| **T2D** | 第2世代 | AMD EPYC (Milan) | x86-64 | 60 | 240 GiB | ❌ | 32 Gbps |
| **C3** | 第3世代 | Intel Xeon (Sapphire Rapids) | x86-64 | 176 | 1,408 GiB | ✅ | 200 Gbps |
| **C3D** | 第3世代 | AMD EPYC (Genoa) | x86-64 | 360 | 2,880 GiB | ✅ | 200 Gbps |
| **N4** | 第4/5世代 | Intel Xeon (Emerald Rapids) | x86-64 | 80 | 640 GiB | ✅ | 50 Gbps |
| **N4D** | 第4/5世代 | AMD EPYC (Turin) | x86-64 | 96 | 768 GiB | ✅ | 50 Gbps |
| **N4A** | 第4/5世代 | Google Axion (Arm N3) | ARM64 | 64 | 512 GiB | ✅ | 50 Gbps |
| **C4** | 第4/5世代 | Intel Xeon (Emerald Rapids) | x86-64 | 192 | 1,536 GiB | ✅ | 200 Gbps |
| **C4A** | 第4/5世代 | Google Axion (Arm V2) | ARM64 | 72 | 576 GiB | ✅ | 100 Gbps |
| **C4D** | 第4/5世代 | AMD EPYC (Turin) | x86-64 | 384 | 3,072 GiB | ✅ | 200 Gbps |

**コンピューティング最適化マシンタイプ（Compute Optimized）：**

| マシンシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Titanium | ネットワーク |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **H3** | 第3世代 | Intel Xeon (Sapphire Rapids) | x86-64 | 88 | 352 GiB | ✅ | 200 Gbps |
| **H4D** | 第4/5世代 | AMD EPYC (Turin) | x86-64 | 192 | 576 GiB | ✅ | 200 Gbps |
| **C2** | 第2世代 | Intel Xeon (Cascade Lake) | x86-64 | 60 | 240 GiB | ❌ | 32 Gbps |
| **C2D** | 第2世代 | AMD EPYC (Milan) | x86-64 | 112 | 896 GiB | ❌ | 32 Gbps |

**メモリ最適化マシンタイプ（Memory Optimized）：**

| マシンシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | 最大メモリ | Titanium | 用途 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **M1/M2** | 第1世代 | Intel Xeon (Skylake/Cascade Lake) | x86-64 | 160 | 12 TiB | ❌ | SAP HANA |
| **M3** | 第2世代 | Intel Xeon (Ice Lake) | x86-64 | 128 | 4 TiB | ❌ | SAP HANA |
| **X4** | 第4/5世代 | Intel Xeon (Sapphire Rapids) | x86-64 | 1,920 | 32 TiB | ✅ | SAP HANA/大規模DB |

**ストレージ最適化マシンタイプ（Storage Optimized）：**

| マシンシリーズ | 世代 | CPU | アーキテクチャ | 最大vCPU | ローカルSSD | Titanium | ネットワーク |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Z3** | 第4/5世代 | Intel Xeon (Sapphire Rapids) | x86-64 | 176 | 350 GiB/vCPU | ✅ | 200 Gbps |

**GPU/アクセラレーテッドマシンタイプ（Accelerator Optimized）：**

| マシンシリーズ | 世代 | CPU | GPU/TPU | 最大GPU数 | Titanium | ネットワーク |
|:---|:---|:---|:---|:---|:---|:---|
| **A2** | 第2世代 | AMD EPYC (Rome) | NVIDIA A100 (40/80GB) | 16 | ❌ | 100 Gbps |
| **A3 High** | 第3世代 | Intel Xeon (Sapphire Rapids) | NVIDIA H100 (80GB) | 8 | ✅ | 200 Gbps |
| **A3 Mega** | 第3世代 | Intel Xeon (Sapphire Rapids) | NVIDIA H100 (80GB) | 8 | ✅ | 1,800 Gbps (GPUDirect) |
| **A3 Ultra** | 第3世代 | Intel Xeon (Sapphire Rapids) | NVIDIA H200 | 8 | ✅ | 3,200 Gbps (GPUDirect) |
| **A4 High** | 第4/5世代 | Intel Xeon (Emerald Rapids) | NVIDIA B200 | 8 | ✅ | 3,200 Gbps (GPUDirect) |
| **G2** | 第2世代 | Intel Xeon (Cascade Lake) | NVIDIA L4 | 8 | ❌ | 100 Gbps |
| **TPU v4** | 第3世代 | - | TPU v4 | - | ✅ | 専用ファブリック |
| **TPU v5e** | 第4/5世代 | - | TPU v5e | - | ✅ | 専用ファブリック |
| **TPU v5p** | 第4/5世代 | - | TPU v5p | - | ✅ | 専用ファブリック |
| **TPU v6e (Trillium)** | 第4/5世代 | - | TPU v6e | - | ✅ | 専用ファブリック |
| **TPU Ironwood** | 第4/5世代 | - | TPU Ironwood | - | ✅ | 専用ファブリック |


### 3.4 Oracle Cloud Infrastructure 詳細

#### 3.4.1 Oracle Acceleron（ハードウェアオフロード）

**Acceleron世代別履歴：**

| 世代 | リリース時期 | 技術 | 特徴 |
|:---|:---|:---|:---|
| **OCI Gen2** | 2016年末 | Off-box Network Virtualization、SmartNIC | 業界初のオフボックスネットワーク仮想化 |
| **AMD Pensando DPU統合** | 2022年〜 | AMD Pensando DSC-200 | DPUベースオフロード |
| **Oracle Acceleron** | 2024年10月 | 統合オフロードスイート | Converged NIC、ZPR、マルチプレーナー |
| **Converged NIC** | 2025年初（予定） | AMD Pensando DPU新世代 | 2倍スループット向上 |

**コンポーネント詳細：**

| カテゴリ | コンポーネント | リリース時期 | 機能説明 | 性能指標 |
|:---|:---|:---|:---|:---|
| **ネットワーク** | SmartNIC | 2016年 | ネットワーク仮想化のOff-box処理 | ホスト外分離 |
| **ネットワーク** | AMD Pensando DPU | 2022年〜 | プログラマブルDPU | - |
| **ネットワーク** | Converged NIC | 2024年10月（発表）、2025年初（提供） | 顧客/プロバイダープレーン分離 | 2倍スループット向上 |
| **ネットワーク** | Acceleron RoCE | 2024年10月 | RDMA over Converged Ethernet | 超低レイテンシ |
| **ネットワーク** | マルチプレーナーネットワーク | 2024年10月 | 複数ネットワークプレーンによる冗長性 | 高可用性 |
| **ネットワーク** | NVIDIA BlueField-3 DPU | 2023年〜 | データセンタータスクオフロード（GPUインスタンス） | 最新GPU向け |
| **ストレージ** | NVMe over TCP | 2024年10月 | ストレージアクセラレーション | 2倍IOPS向上 |
| **ストレージ** | ラインレート暗号化 | 2024年10月 | ストレージ暗号化のハードウェアオフロード | 性能劣化なし |
| **セキュリティ** | Hardware Root-of-Trust | 2016年〜 | ファームウェアセキュリティ、完全ワイプ | - |
| **セキュリティ** | Zero Trust Packet Routing (ZPR) | 2023年（初期）、2024年10月（強化） | ホストレベルゼロトラスト、最小権限 | 最初のパケットから強制 |
| **管理** | Oracle Linux KVM | 2016年〜 | UEKカーネルベースハイパーバイザー | - |
| **管理** | Off-box Virtualization | 2016年 | ネットワーク仮想化をホスト外に完全分離 | 物理コア100%提供 |

**Oracle Cloud Infrastructure仮想化スタック（Off-box Virtualization）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                    ゲストOS (Linux/Windows)                      │
│              ┌─────────────────────────────────────┐            │
│              │        ゲストドライバ                 │            │
│              │   VirtIO-Net / NVMe / iSCSI         │            │
│              │   SR-IOV VF (高性能構成)              │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│              Oracle Linux KVM ハイパーバイザー                    │
│           (UEKカーネルベース、CPU/メモリ割り当てのみ)               │
│              ネットワーク仮想化なし（Off-boxへ完全分離）             │
├─────────────────────────────────────────────────────────────────┤
│           ホストCPU (AMD EPYC / Intel Xeon / Ampere Altra)       │
│           1 OCPU = 1物理コア（オーバーサブスクリプションなし）        │
└───────────────────────────────────────────────┬─────────────────┘
              ハードウェア分離 │ PCIe接続
┌───────────────────────────────────────────────┴─────────────────┐
│                  SmartNIC / Converged NIC                        │
│  ┌─────────────────────────┐  ┌───────────────────────────┐    │
│  │  AMD Pensando DPU       │  │   NVIDIA BlueField-3 DPU   │    │
│  │  (汎用インスタンス)        │  │   (GPUインスタンス)         │    │
│  ├─────────────────────────┤  ├───────────────────────────┤    │
│  │ ・ネットワーク仮想化       │  │ ・GPUDirect RDMA          │    │
│  │ ・NVMe over TCP オフロード│  │ ・AI/MLワークロード最適化   │    │
│  │ ・ラインレート暗号化       │  │                           │    │
│  │ ・Zero Trust Packet     │  │                           │    │
│  │   Routing (ZPR)         │  │                           │    │
│  └─────────────────────────┘  └───────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │            Hardware Root-of-Trust                        │    │
│  │   (ファームウェア完全ワイプ、テナント間完全分離)               │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ 物理ネットワーク（ACL強制）
┌─────────────────────────────────────────────────────────────────┐
│                   OCI物理ネットワークアーキテクチャ                │
│  ┌─────────────────────────┐  ┌───────────────────────────┐    │
│  │   Top-of-Rack Switch    │  │   コントロールプレーン       │    │
│  │   (ACL強制、分離)        │  │   (ILOM経由のみ通信)       │    │
│  └─────────────────────────┘  └───────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │    Oracle Acceleron RoCE Network Fabric                  │    │
│  │    (専用ファブリック、マルチプレーナー、超低レイテンシ)          │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴：**
- **オフロード方式**: Off-box（ホスト外完全分離）- 業界初（2016年〜）
- **ハイパーバイザー**: Oracle Linux KVM（UEKカーネルベース）
- **ネットワーク仮想化**: SmartNIC上で完全実行（ハイパーバイザーに一切含まない）
- **セキュリティモデル**: ハイパーバイザー侵害時でもネットワーク再構成不可
- **物理コア提供**: 1 OCPU = 1物理コア（オーバーサブスクリプションなし）

**Gen1クラウドとOCI Gen2の比較：**

| 項目 | Gen1クラウド（従来型） | OCI Gen2（Off-box） |
|:---|:---|:---|
| **ネットワーク仮想化** | ハイパーバイザー内 | SmartNIC（ホスト外） |
| **ハイパーバイザー侵害時** | ネットワーク再構成可能（横移動リスク） | ネットワーク変更不可（横移動防止） |
| **CPUオーバーヘッド** | ネットワーク処理でCPU消費 | 100%顧客ワークロードに提供 |
| **ノイジーネイバー** | 発生する可能性あり | リソース分離で排除 |

**重要な制約事項：**
- **ネステッド仮想化対応**：x86-64のみ。ARM64（Ampere）ではKVM in VM未サポート
- **ベアメタルインスタンス**: SmartNICでネットワーク仮想化、シームレスパッチ対応（Converged NIC）
- **Confidential Computing**: AMD SEV対応（E5.DenseIO.128シェイプ等）

**OCIの差別化ポイント：**
- 業界初のOff-box Network Virtualization（2016年〜）
- 1 OCPU = 1物理コア（ハイパースレッディングなし、オーバーサブスクリプションなし）
- Oracle Acceleron（2024年10月）で2倍のスループット/IOPS向上、追加コストなし
- BYOハイパーバイザー対応（Oracle VM, Hyper-V, KVM, VMware）
- OCI Zettascale10で最大800,000 GPU（業界最大規模、OpenAI Stargate基盤）
- NVIDIA GB200 NVL72対応（2025年9月〜）、AMD Instinct MI355X/MI450対応

#### 3.4.2 OCI Ampere Arm CPU詳細

Oracle CloudはAmpere社との戦略的パートナーシップにより、業界最高水準のARM Computeを提供しています。

**OCI Ampere A1 Compute（2021年5月GA）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | Ampere Altra Q80-30 |
| **アーキテクチャ** | Arm Neoverse N1 |
| **最大コア数** | 160コア（ベアメタル: 2×80コア）、VM: 最大80コア |
| **周波数** | 最大3.0 GHz（全コア一定） |
| **L1キャッシュ** | 64KB I-cache + 64KB D-cache / コア |
| **L2キャッシュ** | 1MB / コア |
| **メモリ** | 最大1TB（ベアメタル） |
| **対応シェイプ** | BM.Standard.A1.160（ベアメタル）、VM.Standard.A1.Flex（VM） |
| **価格** | $0.01/OCPU/時間（業界初の「ペニーコア」） |
| **特徴** | シングルスレッドコア設計による予測可能な性能、ノイジーネイバー問題なし |

**OCI Ampere A2 Compute（2024年8月GA）：**

| 項目 | 仕様 |
|:---|:---|
| **プロセッサ** | AmpereOne A160-30 |
| **アーキテクチャ** | Armv8.6+（Ampereカスタム設計） |
| **最大コア数** | 156コア（78 OCPU、1 OCPU = 2コア） |
| **周波数** | 最大3.0 GHz |
| **L2キャッシュ** | 2MB / コア（A1の2倍） |
| **メモリ** | DDR5、最大946GB（A1比25%帯域向上） |
| **ネットワーク** | 最大78 Gbps、最大24 VNIC |
| **対応シェイプ** | VM.Standard.A2.Flex |
| **価格** | $0.014/OCPU/時間、$0.002/GB/時間 |
| **A1比性能向上** | 平均28%（Cassandra、PostgreSQL、MySQL等） |
| **x86比価格性能** | 最大2倍 |

**Oracle Cloud ARMの差別化ポイント：**
- **業界最安値水準**: A1は$0.01/OCPU/時間（ペニーコア）、A2も競争力ある価格
- **予測可能な性能**: シングルスレッドコア設計でノイジーネイバー問題を排除
- **線形スケーリング**: コア追加に比例した性能向上
- **Always Free Tier**: A1で4 OCPU + 24GB RAMを無料提供（3,000 OCPU時間/月）
- **100以上のOCIサービス対応**: Oracle Database、HeatWave MySQL、Fusion Apps等で稼働
- **Red Bull Racing採用**: Kubernetes上でモンテカルロシミュレーションを25%高速化

#### 3.4.3 OCI Zettascale（大規模AI基盤）

OCIは2024年にZettascale AIスーパーコンピューターを発表し、2025年にはZettascale10を発表して業界最大規模のGPUクラスタを提供しています。

**OCI Supercluster世代：**

| 世代 | リリース時期 | 最大GPU数 | ネットワーク | 特徴 |
|:---|:---|:---|:---|:---|
| **OCI Supercluster** | 2023年〜 | 16,384 H100 | RDMA | 初期大規模GPUクラスタ |
| **OCI Zettascale** | 2024年9月 | 131,072 GPU | Acceleron RoCE | 2.4 ZettaFLOPS |
| **OCI Zettascale10** | 2025年10月（発表）、2026年下半期（GA予定） | 800,000 GPU | Acceleron RoCE v2 | 16 ZettaFLOPS、マルチギガワット級、OpenAI Stargate基盤 |

**GPU/AIアクセラレーター対応：**

| 構成 | 最大GPU数 | 性能 | ネットワーク帯域幅 |
|:---|:---|:---|:---|
| NVIDIA GB200 NVL72 | 800,000（Zettascale10） | 16 ZettaFLOPS | Acceleron RoCE v2 |
| NVIDIA Blackwell B200 | 131,072 | 2.4 ZettaFLOPS | - |
| NVIDIA GB200 NVL72 | 131,072 | 2.4 ZettaFLOPS | 129.6 TB/s (NVLink) |
| NVIDIA H200 | 65,536 | 260 ExaFLOPS | 52 Pb/s |
| NVIDIA H100 | 16,384 | 65 ExaFLOPS | 13 Pb/s |
| NVIDIA A100 | 32,768 | - | - |
| AMD MI300X | 16,384 | - | 192GB HBM3メモリ |
| AMD MI355X | 131,072（GA） | - | 288GB HBM3Eメモリ |

**OCI Zettascale10の特徴（2025年10月発表、2026年下半期GA予定）：**
- 最大800,000 NVIDIA GPUを単一クラスタで接続
- Oracle Acceleron RoCE v2ネットワーキングによる超低レイテンシ
- 複数データセンターにまたがるマルチギガワット規模
- OpenAI Stargateプロジェクトの基盤として採用（テキサス州アビリーン）
- 独立したネットワークプレーンによる高可用性・障害自動回避

#### 3.4.4 OCI ストレージアーキテクチャ

**リモートブロックストレージ（OCI Block Volume）：**

| パフォーマンスレベル | VPU/GB | 最大IOPS/ボリューム | 最大スループット/ボリューム | 最大容量 | レイテンシ | 用途 |
|:---|:---|:---|:---|:---|:---|:---|
| **Ultra High Performance** | 30-120 | 300,000 IOPS | 2,680 MB/s | 32 TiB | サブミリ秒 | 最高性能DB、AI/ML |
| **Higher Performance** | 20 | 50,000 IOPS | 680 MB/s | 32 TiB | サブミリ秒 | 高I/O要求ワークロード |
| **Balanced** | 10 | 25,000 IOPS | 480 MB/s | 32 TiB | サブミリ秒 | 汎用（デフォルト） |
| **Lower Cost** | 0 | 3,000 IOPS | 480 MB/s | 32 TiB | - | スループット重視、ログ処理 |

**インスタンスあたりの最大性能：**
- 最大IOPS：1,300,000 IOPS（32ボリューム接続時）
- 最大スループット：12 GB/s
- 最大接続ボリューム数：32

**ボリューム接続方式：**

| 接続方式 | プロトコル | 最大IOPS | 用途 | 対応インスタンス |
|:---|:---|:---|:---|:---|
| **iSCSI** | iSCSI over TCP | 300,000 IOPS | 高性能（推奨） | ベアメタル、VM |
| **Paravirtualized** | 準仮想化 | 150,000 IOPS | 簡易接続 | VM（E4シェイプ） |
| **NVMe（ローカル）** | NVMe | - | ローカルストレージ | DenseIO、HPC |

**ローカルインスタンスストレージ（NVMe SSD）：**

| シェイプ | ローカルストレージ | ディスク構成 | 最大IOPS | 最大スループット | 用途 |
|:---|:---|:---|:---|:---|:---|
| **BM.DenseIO2.52** | 51.2 TB | 8x 6.4 TB NVMe SSD | 3,000,000+ IOPS | 30+ GB/s | 高密度ストレージ |
| **BM.DenseIO.E5.128** | 54.4 TB | 8x 6.8 TB NVMe SSD | 3,000,000+ IOPS | 30+ GB/s | 最新DenseIO |
| **BM.HPC2.36** | 6.7 TB | NVMe SSD | - | - | HPC |
| **VM.DenseIO2.24** | 25.6 TB | 4x 6.4 TB NVMe SSD | 1,500,000 IOPS | 15 GB/s | DenseIO VM |

**OCIストレージの特徴：**
- 全NVMe SSDベース（HDDオプションなし）
- VPU（Volume Performance Units）による柔軟な性能調整
- 動的性能スケーリング：AutoTuneで自動調整可能
- Off-box Virtualization：ストレージI/Oをホスト外で処理
- Oracle Acceleron（2024年10月）：従来比2倍のスループット/IOPS


#### 3.4.5 Oracle Cloud Infrastructure世代別インスタンスタイプ

**OCI DPU/SmartNIC世代と特徴：**

| 世代 | DPU/SmartNIC | 対象シェイプ | 主な特徴 | ネットワーク仮想化 |
|:---|:---|:---|:---|:---|
| **Gen1** | AMD Pensando DSC-100/200 | 全VMシェイプ（基本） | Off-box Virtualization | 完全ホスト外分離 |
| **Gen2 (AI)** | NVIDIA BlueField-3 | GPUシェイプ（BM.GPU.B4/H100/L40S） | RDMA/RoCE対応 | Off-box + GPUDirect |
| **Gen3 (2025〜)** | AMD Pensando "Vulcano" AI-NIC | 次世代AIシェイプ | 800Gbps/NIC、UEC対応 | Off-box + NVMe over TCP |

**汎用インスタンス（Standard Shapes）：**

| シェイプ名 | DPU世代 | CPU | アーキテクチャ | 最大OCPU | 最大メモリ | ネットワーク | 備考 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **VM.Standard2.x** | Gen1 | Intel Xeon (Skylake) | x86-64 | 24 | 320 GiB | 24.6 Gbps | 旧世代 |
| **VM.Standard3.Flex** | Gen1 | Intel Xeon (Ice Lake) | x86-64 | 32 | 512 GiB | 32 Gbps | フレキシブル |
| **VM.Standard.E3.Flex** | Gen1 | AMD EPYC (Rome) | x86-64 | 64 | 1,024 GiB | 40 Gbps | フレキシブル |
| **VM.Standard.E4.Flex** | Gen1 | AMD EPYC (Milan) | x86-64 | 64 | 1,024 GiB | 40 Gbps | フレキシブル |
| **VM.Standard.E5.Flex** | Gen1 | AMD EPYC (Genoa) | x86-64 | 94 | 1,048 GiB | 40 Gbps | フレキシブル |
| **VM.Standard.A1.Flex** | Gen1 | Ampere Altra | ARM64 | 80 | 512 GiB | 40 Gbps | ARM64フレキシブル |
| **VM.Standard.A2.Flex** | Gen1 | Ampere AmpereOne | ARM64 | 78 | 946 GiB | 40 Gbps | ARM64フレキシブル |
| **BM.Standard2.52** | Gen1 | Intel Xeon (Skylake) | x86-64 | 52 | 768 GiB | 2x25 Gbps | ベアメタル |
| **BM.Standard3.64** | Gen1 | Intel Xeon (Ice Lake) | x86-64 | 64 | 1,024 GiB | 2x50 Gbps | ベアメタル |
| **BM.Standard.E4.128** | Gen1 | AMD EPYC (Milan) | x86-64 | 128 | 2,048 GiB | 2x50 Gbps | ベアメタル |
| **BM.Standard.E5.192** | Gen1 | AMD EPYC (Genoa) | x86-64 | 192 | 2,304 GiB | 2x100 Gbps | ベアメタル |
| **BM.Standard.A1.160** | Gen1 | Ampere Altra | ARM64 | 160 | 1,024 GiB | 2x50 Gbps | ARM64ベアメタル |
| **BM.Standard.A2.192** | Gen1 | Ampere AmpereOne | ARM64 | 192 | 1,536 GiB | 2x100 Gbps | ARM64ベアメタル |

**高密度I/Oインスタンス（DenseIO Shapes）：**

| シェイプ名 | DPU世代 | CPU | ローカルNVMe | 最大OCPU | 最大メモリ | ネットワーク |
|:---|:---|:---|:---|:---|:---|:---|
| **VM.DenseIO2.x** | Gen1 | Intel Xeon (Skylake) | 6.4-51.2 TB | 24 | 320 GiB | 24.6 Gbps |
| **BM.DenseIO2.52** | Gen1 | Intel Xeon (Skylake) | 51.2 TB | 52 | 768 GiB | 2x25 Gbps |
| **BM.DenseIO.E4.128** | Gen1 | AMD EPYC (Milan) | 54.4 TB | 128 | 2,048 GiB | 2x50 Gbps |
| **BM.DenseIO.E5.128** | Gen1 | AMD EPYC (Genoa) | 54.4 TB | 128 | 2,048 GiB | 2x100 Gbps |

**HPC/GPUインスタンス：**

| シェイプ名 | DPU世代 | CPU | GPU/アクセラレータ | 最大GPU数 | ネットワーク | 備考 |
|:---|:---|:---|:---|:---|:---|:---|
| **BM.GPU2.2** | Gen1 | Intel Xeon | NVIDIA P100 | 2 | 2x25 Gbps | 旧世代 |
| **BM.GPU3.8** | Gen1 | Intel Xeon | NVIDIA V100 | 8 | 8x25 Gbps | 旧世代 |
| **BM.GPU4.8** | Gen1 | AMD EPYC | NVIDIA A100 (40GB) | 8 | 8x50 Gbps | 旧世代 |
| **BM.GPU.A10.4** | Gen1 | AMD EPYC (Milan) | NVIDIA A10 | 4 | 2x50 Gbps | 推論向け |
| **BM.GPU.L40S.4** | Gen2 | AMD EPYC | NVIDIA L40S | 4 | 100 Gbps | BlueField-3搭載 |
| **BM.GPU.B4.8** | Gen2 | AMD EPYC | NVIDIA A100 (80GB) | 8 | 800 Gbps (RoCE) | BlueField-3搭載 |
| **BM.GPU.H100.8** | Gen2 | AMD EPYC | NVIDIA H100 (80GB) | 8 | 3,200 Gbps (RoCE) | BlueField-3搭載 |
| **BM.GPU.MI300X.8** | Gen2 | AMD EPYC | AMD Instinct MI300X | 8 | 3,200 Gbps (RoCE) | AMD GPU |

**OCI Supercluster構成（2025年〜）：**

| クラスター名 | DPU世代 | GPU | 最大GPU数 | ネットワーク | 備考 |
|:---|:---|:---|:---|:---|:---|
| **OCI Supercluster (H100)** | Gen2 | NVIDIA H100 | 32,768 | 3,200 Gbps/GPU | BlueField-3 |
| **OCI Zettascale10 (GB200)** | Gen3 | NVIDIA GB200 | 131,072 | 12.8 Tbps/node | 2025年発表 |
| **AMD MI450X Supercluster** | Gen3 | AMD MI450X | 50,000+ | 800 Gbps/NIC | 2026年Q3予定 |


---

## 4. 参考情報および補足情報

本セクションでは、各クラウドプロバイダーの詳細な技術情報、移行ガイド、管理用Linuxディストリビューション、参考文献リンクを整理しています。

### 4.1 ハイパースケーラー管理Linuxディストリビューション

各ハイパースケーラーは、Linux KVMを基盤とした仮想化環境やコンテナプラットフォームを支えるため、独自のLinuxディストリビューションを開発・保守しています。本セクションでは、各社のディストリビューションのオープンソース公開状況、情報公開サイト、Issue管理体制について整理します。

#### 4.1.1 比較表：管理Linuxディストリビューション

| 項目 | Amazon Linux 2023 | AWS Bottlerocket | Azure Linux 3.0 | Oracle Linux 9/10 | Google Cloud COS |
|:---|:---|:---|:---|:---|:---|
| **提供元** | AWS | AWS | Microsoft | Oracle | Google |
| **アップストリーム** | Fedora / CentOS Stream | 独自設計 | 独自（Photon OS参考） | RHEL互換 | Chromium OS |
| **最新バージョン** | 2023.9.20251117 | 1.51.0（2025年12月） | 3.0（2024年8月GA） | OL 10.1（2025年GA） | LTS 121（milestone） |
| **カーネル** | 6.1 LTS / 6.12 LTS | 6.1 LTS | 6.6 / 6.12 LTS | UEK 8（6.12ベース）/ RHCK | 5.15 / 6.1 LTS |
| **サポート期間** | 2029年6月30日まで（5年間） | オーケストレーター版連動 | 3年（2027年夏EOL予定） | Premier Support + Extended | LTS: 2年 |
| **対応アーキテクチャ** | x86-64、ARM64 | x86-64、ARM64 | x86-64、ARM64 | x86-64、ARM64（UEKのみ） | x86-64、ARM64 |
| **パッケージマネージャー** | dnf | API設定ベース | tdnf / dnf | dnf | なし（コンテナ経由） |
| **主な用途** | EC2、ECS/EKS | EKS/ECS コンテナホスト | AKS、WSL2、Azure IoT Edge | OCI、オンプレミス、Exadata | GKE、Compute Engine |
| **ライセンス** | 無償 | Apache 2.0 + MIT（OSS） | MIT License（OSS） | 無償（サポートは有償） | Apache 2.0（OSS） |

#### 4.1.2 オープンソース公開状況比較

| 項目 | Amazon Linux 2023 | AWS Bottlerocket | Azure Linux | Oracle Linux UEK | Google Cloud COS |
|:---|:---|:---|:---|:---|:---|
| **オープンソース** | 部分的 | ✅ 完全OSS | ✅ 完全OSS | ✅ カーネルのみOSS | ✅ 完全OSS |
| **ライセンス** | 独自（無償） | Apache 2.0 / MIT | MIT License | UPL 1.0 / GPL | Apache 2.0 |
| **ソースコードリポジトリ** | GitHub（ドキュメント中心） | GitHub（フルソース） | GitHub（フルソース） | GitHub（カーネルのみ） | cos.googlesource.com |
| **Issue管理** | ✅ GitHub Issues | ✅ GitHub Issues | ✅ GitHub Issues | Oracle Developer Community | ❌ 外部Issue非対応 |
| **外部PR受付** | ❌ | ✅ | ✅ | ❌（上流コミット参照歓迎） | ❌ |
| **公開ロードマップ** | ❌ | ✅ GitHub Roadmap | ❌ | ❌ | ❌ |
| **コミュニティコール** | ❌ | ✅ Meetup | ✅ 定期開催 | ❌ | ❌ |

#### 4.1.3 Amazon Linux 2023（AL2023）

Amazon Linux 2023（AL2023）は、AWSが開発・保守する次世代のクラウド最適化Linuxディストリビューションです。Amazon Linux 2（AL2）の後継として、セキュア・安定・高性能な実行環境を提供し、Gravitonプロセッサへの最適化や決定論的アップデート機能を備えています。AL2023は追加料金なしで利用可能です。

**主要特徴：**

| 項目 | 仕様 |
|:---|:---|
| **リリース日** | 2023年3月15日（GA） |
| **最新バージョン** | 2023.9.20251117（2025年11月時点） |
| **アップストリーム** | Fedora Linux（+ CentOS Stream、kernel.org LTS） |
| **カーネルバージョン** | 6.1 LTS（FIPS認証済）、6.12 LTS（2025年3月追加） |
| **サポート終了日** | 2029年6月30日 |
| **対応アーキテクチャ** | x86-64（x86-64v2以降）、ARM64（ARMv8.2+crypto、Graviton2以降） |
| **パッケージマネージャー** | dnf（yumシンボリックリンク提供） |
| **提供リージョン** | 全AWSリージョン（GovCloud、中国リージョン含む） |

**リリースケイデンスとサポートライフサイクル：**

AL2023は予測可能なリリースサイクルを採用しており、2年ごとに新しいメジャーバージョンがリリースされます（次期バージョンは2025年予定）。

| フェーズ | 期間 | 内容 |
|:---|:---|:---|
| **標準サポート** | 2023年3月〜2027年6月30日 | 四半期ごとのマイナーバージョンアップデート（セキュリティ修正、バグ修正、新機能・パッケージ追加） |
| **メンテナンス** | 2027年7月〜2029年6月30日 | セキュリティアップデートと重大なバグ修正のみ（利用可能次第即時提供） |

**バージョンロッキング機能：**

AL2023では、パッケージリポジトリのバージョンをロックする機能を提供しています。これにより、同じAMIから作成されたインスタンスで`dnf upgrade`を実行しても、数ヶ月・数年後でも同じパッケージセットが適用されることが保証されます。

| 項目 | 説明 |
|:---|:---|
| **デフォルト動作** | AMIビルド時のリポジトリバージョンにロック |
| **バージョン確認** | `dnf check-release-update` |
| **バージョン変更** | `dnf --releasever=<version> update` |
| **最新追従モード** | `--releasever=latest`で常に最新リポジトリを参照 |

**カーネルオプションとFIPS認証：**

| カーネル | FIPS 140-3 | 用途 |
|:---|:---|:---|
| **6.1 LTS** | ✅ Level 1認証済（Certificate #4808） | FIPS準拠が必要な環境（推奨） |
| **6.12 LTS** | 検証中（2025年7月申請、2026年7月〜2027年1月認証見込み） | FIPS要件がない環境向け最新機能 |

**カーネル6.12の新機能：**
- EEVDF（Earliest Eligible Virtual Deadline First）スケジューリング
- FUSEパススルーI/Oサポート
- 新Futex API
- eBPF拡張機能
- ユーザースペースシャドウスタック
- メモリシーリング

**公式ドキュメント・リソース：**

| 項目 | URL |
|:---|:---|
| **ユーザーガイド** | https://docs.aws.amazon.com/linux/al2023/ug/what-is-amazon-linux.html |
| **リリースノート** | https://docs.aws.amazon.com/linux/al2023/release-notes/relnotes.html |
| **FAQ** | https://aws.amazon.com/linux/amazon-linux-2023/faqs/ |
| **機能一覧** | https://aws.amazon.com/linux/amazon-linux-2023/features/ |
| **セキュリティセンター** | https://alas.aws.amazon.com/ |
| **AL2との比較** | https://docs.aws.amazon.com/linux/al2023/ug/compare-with-al2.html |

**オープンソース・コミュニティ情報：**

| 項目 | 情報 |
|:---|:---|
| **GitHubリポジトリ** | https://github.com/amazonlinux/amazon-linux-2023 |
| **GitHub Organization** | https://github.com/amazonlinux |
| **Issue管理** | ✅ GitHub Issues（バグ報告・機能リクエスト対応） |
| **Discussions** | ✅ GitHub Discussions（Q&A対応） |
| **外部PR受付** | ❌ 非対応（セキュリティ問題は専用チーム連絡） |
| **関連リポジトリ** | amazon-ec2-utils、dnf-plugin-support-info |
| **フィードバック方法** | GitHub Issue、AWS担当者、AWS re:Post |

**SPAL（Supplementary Packages for Amazon Linux）：**

SPALは、EPEL9から派生した数千のビルド済みパッケージを提供する追加リポジトリです。AL2からAL2023への移行を支援し、ソースからのビルドなしでワークロード移行を可能にします。

| 項目 | 説明 |
|:---|:---|
| **提供パッケージ数** | 数千パッケージ（EPEL9派生） |
| **サポート** | ベストエフォート（AWS Enterprise Support対象外） |
| **CVEトラッキング** | AWS CVEセキュリティトラッキング対象外 |
| **セキュリティパッチ** | 上流EPEL9から提供次第、AWSがベストエフォートで提供 |
| **パッケージリクエスト** | AL2023 GitHubリポジトリで「Package Request」Issueを作成 |

**セキュリティ機能：**

| 機能 | 説明 |
|:---|:---|
| **SELinux** | デフォルトでPermissiveモード（Enforcingモード対応、起動時設定可能） |
| **FIPS 140-3** | カーネル6.1はLevel 1認証取得（Certificate #4808） |
| **IMDSv2** | デフォルトで必須（セキュリティ強化） |
| **Kernel Live Patching** | x86-64/ARM64両対応、重大・重要な脆弱性を再起動なしで適用 |
| **セキュアブート** | 対応（カーネルモジュール署名、カーネルロックダウン） |
| **システム暗号ポリシー** | FUTURE/LEGACYポリシー設定対応、起動時または実行時に設定可能 |

**コアパッケージサポート：**

以下のコアパッケージはAL2023のライフサイクル全体（2029年6月30日まで）を通じてサポートされます：
- glibc（Cライブラリ）
- OpenSSL（暗号化ライブラリ）
- OpenSSH（SSHサーバー/クライアント）
- DNF（パッケージマネージャー）

コア以外のパッケージは、上流ソースのサポートポリシーに従います。個別パッケージのサポート状況は`dnf supportinfo <packagename>`で確認可能です。

#### 4.1.4 AWS Bottlerocket

Bottlerocketは、AWSがスポンサー・サポートするコンテナホスト専用のLinuxディストリビューションです。完全オープンソースとしてGitHub上で開発されており、公開ロードマップを持つ点が特徴的です。

**主要特徴：**

| 項目 | 仕様 |
|:---|:---|
| **初期リリース** | 2020年8月（GA） |
| **最新バージョン** | 1.51.0（2025年12月時点） |
| **カーネルバージョン** | 6.1 LTS |
| **対応プラットフォーム** | Amazon EKS、Amazon ECS、VMware vSphere、オンプレミスKubernetes |
| **対応アーキテクチャ** | x86-64、ARM64（aarch64） |
| **更新方式** | イメージベース（A/Bパーティション自動ロールバック対応） |
| **セキュリティ認証** | CIS Bottlerocket Benchmark v1.0.0認定 |

**オープンソース・コミュニティ情報：**

| 項目 | 情報 |
|:---|:---|
| **公式ドキュメント** | https://bottlerocket.dev/ |
| **公式サイト** | https://aws.amazon.com/bottlerocket/ |
| **GitHub Organization** | https://github.com/bottlerocket-os |
| **メインリポジトリ** | https://github.com/bottlerocket-os/bottlerocket |
| **ロードマップ** | https://github.com/aws/containers-roadmap（Bottlerocketラベル） |
| **Issue管理** | ✅ GitHub Issues（バグ報告・機能リクエスト対応） |
| **外部PR受付** | ✅ 対応（コントリビューターガイドあり） |
| **コミュニティ** | Meetup（コミュニティミーティング）、GitHub Discussions |

**関連GitHubリポジトリ：**

| リポジトリ | 説明 |
|:---|:---|
| **bottlerocket-os/bottlerocket** | OSイメージ・ツール（メインリポジトリ） |
| **bottlerocket-os/bottlerocket-core-kit** | コアOSパッケージ |
| **bottlerocket-os/bottlerocket-kernel-kit** | Linuxカーネル、ブートローダー、ファームウェア |
| **bottlerocket-os/bottlerocket-update-operator** | Kubernetes用自動更新オペレーター |
| **bottlerocket-os/bottlerocket-ecs-updater** | ECS用自動更新サービス |
| **bottlerocket-os/bottlerocket-admin-container** | 管理用ホストコンテナ |
| **bottlerocket-os/bottlerocket-control-container** | コントロール用ホストコンテナ |

**Bottlerocket Variants（ビルドバリアント）：**

| バリアント | 用途 |
|:---|:---|
| **aws-k8s-1.32〜1.34** | Amazon EKS Kubernetes |
| **aws-k8s-1.xx-nvidia** | NVIDIA GPU対応EKS |
| **aws-k8s-1.xx-fips** | FIPS準拠EKS |
| **aws-ecs-2/3** | Amazon ECS |
| **vmware-k8s-1.xx** | VMware vSphere Kubernetes |

#### 4.1.5 Azure Linux（旧CBL-Mariner）

Azure Linuxは、MicrosoftがAzureインフラストラクチャおよびエッジサービス向けに開発した軽量Linuxディストリビューションです。2024年3月にCBL-Mariner（Common Base Linux Mariner）からAzure Linuxにリブランドされました。MIT Licenseで完全オープンソース公開されています。

**主要特徴：**

| 項目 | 仕様 |
|:---|:---|
| **初期リリース** | 2020年4月（CBL-Mariner 1.0） |
| **最新バージョン** | Azure Linux 3.0（2024年8月GA） |
| **カーネルバージョン** | 2.0: 5.15 / 3.0: 6.6、6.12 LTS |
| **サポート期間** | 各メジャーバージョン3年（3.0は2027年夏EOL予定） |
| **対応アーキテクチャ** | x86-64、ARM64 |
| **パッケージマネージャー** | tdnf（Tiny DNF）/ dnf |
| **ライセンス** | MIT License（オープンソース） |
| **設計参考** | VMware Photon OS |

**オープンソース・コミュニティ情報：**

| 項目 | 情報 |
|:---|:---|
| **GitHubリポジトリ（3.0）** | https://github.com/microsoft/azurelinux |
| **GitHubリポジトリ（2.0）** | https://github.com/microsoft/CBL-Mariner |
| **カーネルリポジトリ** | https://github.com/microsoft/CBL-Mariner-Linux-Kernel |
| **チュートリアル** | https://github.com/microsoft/azurelinux-tutorials |
| **Issue管理** | ✅ GitHub Issues（バグ報告・機能リクエスト対応） |
| **外部PR受付** | ✅ 対応 |
| **コミュニティコール** | 定期開催（新機能デモ、フィードバック収集） |
| **ISOダウンロード** | x86_64 / aarch64 ISO提供 |

**Azure Linuxの用途：**

| 用途 | 説明 |
|:---|:---|
| **Azure Kubernetes Service (AKS)** | コンテナホストOSとして提供（AKS v1.32以降のデフォルト） |
| **WSL 2** | WSLg（GUI）のバックエンドディストリビューション |
| **Azure IoT Edge** | EFLOW（Edge for Linux on Windows）の基盤VM |
| **Azure Stack HCI** | AKSコンテナホスト |
| **Azure内部サービス** | Microsoftファーストパーティサービスの基盤 |
| **SONiC** | ネットワークスイッチOS |

**Azure Linux 3.0の主要アップデート（2.0比）：**

| コンポーネント | Azure Linux 2.0 | Azure Linux 3.0 |
|:---|:---|:---|
| **Linuxカーネル** | 5.15 | 6.6 / 6.12 LTS |
| **containerd** | 1.6.26 | 1.7.13+ |
| **systemd** | 250 | 255 |
| **OpenSSL** | 1.1.1k | 3.3.0 |
| **GCC** | 11.x | 13.x |
| **glibc** | 2.35 | 2.38 |

#### 4.1.6 Google Cloud: Container-Optimized OS（COS）

Google Cloudは汎用Linuxディストリビューションではなく、コンテナ実行に特化したContainer-Optimized OS（COS）を提供しています。Chromium OSをベースにしており、ソースコードは公開されていますが、外部からの直接的な貢献は受け付けていません。

**主要特徴：**

| 項目 | Container-Optimized OS |
|:---|:---|
| **ベース** | Chromium OS |
| **用途** | GKEノードOS、Compute Engineコンテナホスト |
| **特徴** | 最小フットプリント、読み取り専用ルートFS、自動更新 |
| **コンテナランタイム** | Docker、containerd（プリインストール） |
| **サポート期間** | LTSマイルストーン: 2年 |
| **パッケージマネージャー** | なし（コンテナ経由で追加） |
| **リリースチャネル** | dev → beta → stable → LTS |

**オープンソース・コミュニティ情報：**

| 項目 | 情報 |
|:---|:---|
| **公式ドキュメント** | https://cloud.google.com/container-optimized-os/docs |
| **ソースコードリポジトリ** | https://cos.googlesource.com/ |
| **カーネルソース** | https://cos.googlesource.com/third_party/kernel/+/cos-5.15 |
| **ビルドレシピ** | https://cos.googlesource.com/cos/overlays/board-overlays/+/master/project-lakitu/ |
| **ビルドアーティファクト** | gs://cos-tools/<build-number>/ |
| **Issue管理** | ❌ 外部Issue非対応 |
| **外部PR受付** | ❌ 非対応 |
| **ライセンス** | Apache 2.0 |

**関連GitHubツール（GoogleCloudPlatform）：**

| リポジトリ | 説明 |
|:---|:---|
| **GoogleCloudPlatform/cos-customizer** | COSイメージカスタマイズツール |
| **GoogleCloudPlatform/cos-toolbox** | COS用デバッグツールコンテナ |

**COSソースコードアクセス方法：**

1. **depot_tools経由**: `repo`ツールを使用してソースコード取得
2. **カーネルヘッダー・ソース**: Cloud Storageバケット（gs://cos-tools/）で提供
3. **パッケージミラー**: Chromium OS Build System経由でアクセス
4. **ライセンス情報**: /opt/google/chrome/resources/about_os_credits.html

**注意：** COSは汎用OSではなく、コンテナワークロード専用です。Google CloudではUbuntu、Debian、RHEL等のサードパーティLinuxも選択可能です。外部からの直接的な貢献は受け付けていないため、問題報告はGoogle Cloud Supportを通じて行う必要があります。

#### 4.1.7 Oracle Linux

Oracle Linuxは、OracleがRed Hat Enterprise Linux（RHEL）とのバイナリ互換性を維持しながら開発・保守するエンタープライズLinuxディストリビューションです。独自のUnbreakable Enterprise Kernel（UEK）を提供し、Oracle DatabaseやOracle Cloud Infrastructure（OCI）に最適化されています。UEKカーネルはGitHub上でオープンソース公開されています。

**主要特徴：**

| 項目 | 仕様 |
|:---|:---|
| **初期リリース** | 2006年（Oracle Enterprise Linux） |
| **最新バージョン** | Oracle Linux 10.1（2025年GA） |
| **カーネルオプション** | UEK 8（6.12ベース）/ RHCK（RHEL互換） |
| **サポート期間** | Premier Support（10年）+ Extended Support |
| **対応アーキテクチャ** | x86-64、ARM64（UEKのみ） |
| **パッケージマネージャー** | dnf（yum互換） |
| **ライセンス** | 無償（サポートは有償オプション） |
| **RHEL互換性** | 100%アプリケーションバイナリ互換 |

**オープンソース・コミュニティ情報：**

| 項目 | 情報 |
|:---|:---|
| **公式サイト** | https://www.oracle.com/linux/ |
| **ダウンロード** | https://linux.oracle.com/ |
| **YUMリポジトリ** | https://yum.oracle.com/ |
| **UEK GitHubリポジトリ** | https://github.com/oracle/linux-uek |
| **DTrace GitHubリポジトリ** | https://github.com/oracle/dtrace-utils |
| **カーネルブログ** | https://blogs.oracle.com/linuxkernel |
| **Issue管理** | Oracle Developer Community（Oracle Linux and UEK Preview） |
| **外部PR受付** | ❌ 非対応（上流コミットへのポインタ歓迎） |
| **更新頻度** | 週次（開発版） |

**UEK GitHubリポジトリの特徴：**

- **週次更新**: 開発版ソースコードが週次でリフレッシュ
- **ブランチ構成**: 各UEKバージョン（UEK7、UEK8等）に対応するブランチ
- **ueknext/latest**: 上流Linuxツリーに継続的にマージされる次期変更をプレビュー可能
- **ビルド要件**: libdtrace-ctf、dtrace-utils等の追加依存関係が必要
- **ライセンス**: UPL 1.0（Universal Permissive License）

**Unbreakable Enterprise Kernel（UEK）バージョン：**

| UEKバージョン | ベースカーネル | 対応OL | 主な特徴 |
|:---|:---|:---|:---|
| **UEK 8** | 6.12 LTS | OL 9.5+ | メモリfolios、Maple Tree、Intel SGX2、最新 |
| **UEK 7** | 5.15 LTS | OL 8/9 | 安定版、広く利用 |
| **UEK 6** | 5.4 LTS | OL 7/8 | Extended Support対象 |
| **UEK 5** | 4.14 LTS | OL 7 | ARM64初対応 |

**Oracle Linux独自機能：**

| 機能 | 説明 |
|:---|:---|
| **Ksplice** | ダウンタイムなしのカーネルライブパッチ（Oracle Linux Premierサポート含む） |
| **DTrace** | 動的トレーシングフレームワーク（Oracleが移植、GitHub OSS） |
| **Btrfs** | エンタープライズサポート（RHELは2017年にサポート終了） |
| **Oracle Linux Automation Manager** | Ansible互換の自動化ツール |
| **Autonomous Linux** | OCI上での自動パッチ適用・監視サービス |

#### 4.1.8 オープンソース公開状況サマリ

| プロバイダー | ディストリビューション | OSS公開レベル | コミュニティ参加 | 推奨連絡方法 |
|:---|:---|:---|:---|:---|
| **AWS** | Amazon Linux 2023 | 部分的（ドキュメント中心） | GitHub Issues/Discussions | GitHub Issue |
| **AWS** | Bottlerocket | 完全OSS | GitHub PR/Issues/Roadmap | GitHub PR/Issue |
| **Microsoft** | Azure Linux | 完全OSS | GitHub PR/Issues + コミュニティコール | GitHub Issue |
| **Oracle** | Oracle Linux (UEK) | カーネルOSS | Oracle Developer Community | Oracle Community |
| **Google** | Container-Optimized OS | 完全OSS（貢献は非対応） | なし | Google Cloud Support |

---

### 4.2 BYOハイパーバイザー対応詳細

#### 4.2.1 ハイパーバイザーのCPUアーキテクチャ依存性

主要なエンタープライズハイパーバイザーは、そのアーキテクチャ上の制約から特定のCPUアーキテクチャに依存しています。

| ハイパーバイザー | x86-64 | ARM64 | 備考 |
|:---|:---|:---|:---|
| **VMware ESXi** | ✅ | ❌ | x86-64専用（ARM64版は将来計画のみ） |
| **Microsoft Hyper-V** | ✅ | ❌ | Windows Server依存でx86-64専用 |
| **Nutanix AHV** | ✅ | ❌ | KVMベースだがx86-64のみ認定 |
| **Oracle VM (OLVM)** | ✅ | ❌ | KVM + oVirt、x86-64専用 |
| **KVM (Linux Kernel-based)** | ✅ | ✅ | 両アーキテクチャ対応 |
| **Xen** | ✅ | ✅ | 両アーキテクチャ対応（ARM版は制限あり） |

**重要：** VMware ESXi、Microsoft Hyper-V、Nutanix AHVはいずれも**x86-64専用**です。ARM64環境（Graviton、Cobalt、Axion、Ampere）でBYOハイパーバイザーを実行する場合は、**KVMまたはXen**に限定されます。

#### 4.2.2 クラウドプロバイダー別BYOハイパーバイザー対応

| プロバイダー | x86-64 BYOハイパーバイザー | ARM64 BYOハイパーバイザー | マネージドVMware | Nutanix NC2 |
|:---|:---|:---|:---|:---|
| **AWS** | VMware (EVS)、Hyper-V、KVM、Xen | KVMのみ | Amazon EVS | ✅ |
| **Azure** | Hyper-V (ネステッド)、KVM | KVMのみ | AVS | ✅ |
| **Google Cloud** | VMware (GCVE)、KVM、Xen | KVM/Xenのみ | GCVE | ✅ |
| **OCI** | Oracle VM、Hyper-V、KVM、VMware | Oracle Linux KVMのみ | OCVS | ❌ |

#### 4.2.3 マネージドVMwareサービス比較

| サービス | プロバイダー | 基盤 | 最小構成 | ステータス | ネイティブサービス統合 |
|:---|:---|:---|:---|:---|:---|
| **Amazon EVS** | AWS | EC2 i7i.metal + Nitro | 4ホスト | **GA（2025年8月〜）** | VPC、S3、IAM、CloudWatch |
| **VMware Cloud on AWS** | VMware + AWS | 専用ラック | 2ホスト | GA | S3、VPC |
| **Azure VMware Solution** | Microsoft | AVS専用ハードウェア | 3ホスト | GA | Azure AD、Monitor、Defender |
| **Google Cloud VMware Engine** | Google Cloud | Bare Metal Solution | 3ホスト | GA | BigQuery、Looker、Cloud Logging |
| **Oracle Cloud VMware Solution** | Oracle | OCI Bare Metal | 3ホスト | GA | OCI IAM、Object Storage |

**Amazon EVS 対応リージョン（2025年8月GA時点）：**
- 米国東部（バージニア北部）
- 米国東部（オハイオ）
- 米国西部（オレゴン）
- アジアパシフィック（東京）
- 欧州（フランクフルト）
- 欧州（アイルランド）

---

### 4.3 ゲストOSドライバ対応バージョン詳細

#### 4.3.1 AWS ENA/NVMeドライバ対応OS

**Linux対応バージョン：**

| ディストリビューション | 最小カーネルバージョン | 推奨ENAドライバ | 備考 |
|:---|:---|:---|:---|
| **Linux Upstream** | カーネル 5.9以降 | 2.2.9g以降 | Nitro v4以降に必須 |
| **Amazon Linux 2023** | デフォルト対応 | カーネル内蔵 | Nitro v4/v5最適化済み |
| **Amazon Linux 2** | カーネル 4.14.186以降 | 2.2.9g以降 | - |
| **RHEL 8.4以降** | カーネル 4.18.0-305以降 | 2.2.9g以降 | RHEL 7.4以降でNVMe対応 |
| **RHEL 6** | - | - | **NVMe非対応**（RHEL 7.4以降へ要アップグレード） |
| **SUSE SLES 15 SP2以降** | カーネル 5.3.18-24.15.1以降 | 2.2.9g以降 | - |
| **Ubuntu 20.04** | カーネル 5.4.0-1025-aws以降 | 2.2.9g以降 | linux-awsパッケージ推奨 |
| **Debian 11 (Bullseye)** | カーネル 5.10.0以降 | 2.2.9g以降 | - |
| **FreeBSD** | - | 2.3.1以降 | v2.3.1未満は接続失敗 |

**ENAドライババージョン制限（重要）：**

| Nitroバージョン | Linux ENA最小バージョン | 備考 |
|:---|:---|:---|
| **Nitro v5以降** | 2.2.9g以降（**必須**） | バージョン未満はENI接続失敗 |
| **Nitro v4** | 2.2.9g以降（推奨） | 旧バージョンは性能低下の可能性 |
| **Nitro v2/v3** | 1.2.0以降 | 1.2.0未満は接続失敗 |

**Windows対応バージョン：**

| Windows Server バージョン | ENA対応 | NVMe対応 | AWS PV対応 | 備考 |
|:---|:---|:---|:---|:---|
| **Windows Server 2025** | ✅ | ✅ | - | 最新AMIに含有 |
| **Windows Server 2022** | ✅ | ✅ | ✅ | EC2Launch v2対応 |
| **Windows Server 2019** | ✅ | ✅ | ✅ | EC2Launch v1対応 |
| **Windows Server 2016** | ✅ | ✅ | ✅ | SCSI永続予約対応（NVMe 1.5.0以降） |
| **Windows Server 2012 R2** | ✅ | ✅ | ✅ | EC2Config対応 |
| **Windows Server 2008 R2** | ✅（制限あり） | ❌ | ✅（8.3.4以前） | **Nitro非推奨** |

#### 4.3.2 Azure MANA/Hyper-Vドライバ対応OS

**Linux対応バージョン：**

| ディストリビューション | Hyper-V LIS対応 | MANA対応（カーネル要件） | NVMe対応 |
|:---|:---|:---|:---|
| **RHEL 9.0以降** | ✅（カーネル内蔵） | ✅（5.15以降、6.2推奨） | ✅ |
| **RHEL 8.6以降** | ✅（カーネル内蔵） | ✅（5.15以降、6.2推奨） | ✅ |
| **RHEL 7.9** | ✅（カーネル内蔵） | - | ✅ |
| **Oracle Linux 9.0以降** | ✅ | ✅ | ✅ |
| **Oracle Linux 8.5以降** | ✅ | ✅ | ✅ |
| **Ubuntu 22.04** | ✅ | ✅（6.2以降推奨） | ✅ |
| **Ubuntu 20.04** | ✅ | ✅ | ✅ |
| **Debian 12** | ✅ | ✅ | ✅ |
| **SLES 15 SP4以降** | ✅ | ✅ | ✅ |
| **AlmaLinux 9.x** | ✅ | ✅ | ✅ |

**MANAドライバ カーネル要件：**
- **基本機能**: Linux カーネル 5.15以降
- **RDMA/DPDK対応**: Linux カーネル 6.2以降
- **バックポート対応**: 5.15/6.1の一部でバックポート版利用可

**Windows対応バージョン：**

| Windows Server バージョン | Hyper-V対応 | MANA対応 | NVMe対応 | Shared Disks on NVMe |
|:---|:---|:---|:---|:---|
| **Windows Server 2025** | ✅（OS標準） | ✅ | ✅ | ✅ |
| **Windows Server 2022** | ✅（OS標準） | ✅ | ✅ | ✅ |
| **Windows Server 2019** | ✅（OS標準） | ✅ | ✅ | **❌（非互換）** |
| **Windows Server 2016** | ✅（OS標準） | - | ✅（一部） | - |
| **Windows Server 2012 R2** | ✅（OS標準） | - | - | - |

#### 4.3.3 Google Cloud gVNIC/VirtIOドライバ対応OS

**Linux対応バージョン：**

| ディストリビューション | VirtIO-Net | gVNIC | NVMe | 備考 |
|:---|:---|:---|:---|:---|
| **RHEL 9.x** | ✅ | ✅ | ✅ | gve.koカーネル内蔵 |
| **RHEL 8.x** | ✅ | ✅ | ✅ | gve.ko要インストール |
| **Ubuntu 22.04** | ✅ | ✅ | ✅ | google-compute-engine-oslogin推奨 |
| **Ubuntu 20.04** | ✅ | ✅ | ✅ | - |
| **Debian 11/12** | ✅ | ✅ | ✅ | - |
| **SLES 15 SP3以降** | ✅ | ✅ | ✅ | - |
| **Container-Optimized OS** | - | ✅ | ✅ | gVNIC必須 |

**gVNICカーネル要件：**
- **基本機能**: Linux カーネル 5.3以降
- **推奨**: Linux カーネル 5.10以降
- **第3世代以降（C3/C4/N4）**: gVNIC必須（VirtIO-Net非対応）

#### 4.3.4 Oracle Cloud VirtIO/SR-IOVドライバ対応OS

**Linux対応バージョン：**

| ディストリビューション | VirtIO-Net | SR-IOV | iSCSI | NVMe | 備考 |
|:---|:---|:---|:---|:---|:---|
| **Oracle Linux 9.x** | ✅ | ✅ | ✅ | ✅ | 推奨OS |
| **Oracle Linux 8.x** | ✅ | ✅ | ✅ | ✅ | UEK推奨 |
| **RHEL 9.x** | ✅ | ✅ | ✅ | ✅ | - |
| **RHEL 8.x** | ✅ | ✅ | ✅ | ✅ | - |
| **Ubuntu 22.04** | ✅ | ✅ | ✅ | ✅ | - |
| **Ubuntu 20.04** | ✅ | ✅ | ✅ | ✅ | - |
| **SLES 15 SP3以降** | ✅ | ✅ | ✅ | ✅ | - |

---

### 4.4 クラウド間VM移行ガイド

異なるクラウド間でVMを移行する場合、ゲストOSに適切なドライバをインストールする必要があります。

#### 4.4.1 Linux移行時の必須ドライバ

| 移行元 → 移行先 | 追加が必要なドライバ | initramfs更新 |
|:---|:---|:---|
| VMware → AWS | `ena`, `nvme` | 必要 |
| VMware → Azure | `hv_vmbus`, `hv_storvsc`, `hv_netvsc` | 必要 |
| VMware → GCP | `virtio_*` または `gve`, `nvme` | 必要 |
| VMware → OCI | `virtio_*` | 必要 |
| AWS → Azure | `hv_vmbus`, `hv_storvsc`, `hv_netvsc` | 必要 |
| Azure → AWS | `ena`, `nvme` | 必要 |

#### 4.4.2 Windows移行時の必須ドライバ

| 移行元 → 移行先 | 追加が必要なドライバ | 備考 |
|:---|:---|:---|
| VMware → AWS | AWS PV Drivers, ENA, AWS NVMe | AWSSupport-UpgradeWindowsAWSDrivers使用推奨 |
| VMware → Azure | Hyper-V統合サービス（OS標準） | Windows標準で対応 |
| VMware → GCP | VirtIO Drivers (netkvm, vioscsi) または gVNIC | Google提供ドライバ |
| VMware → OCI | Oracle VirtIO Drivers | Oracle Software Delivery Cloudから取得 |
| Hyper-V → AWS | ENA, AWS NVMe | ENA/NVMe追加 |
| Hyper-V → OCI | Oracle VirtIO Drivers | VirtIO追加 |

#### 4.4.3 initramfs/initrd更新コマンド（Linux）

**RHEL/CentOS/Oracle Linux：**
```bash
$ echo 'add_drivers+=" hv_vmbus hv_netvsc hv_storvsc "' >> /etc/dracut.conf.d/hyperv.conf
$ dracut -f -v
```

**Ubuntu/Debian：**
```bash
$ echo "hv_vmbus" >> /etc/initramfs-tools/modules
$ echo "hv_netvsc" >> /etc/initramfs-tools/modules
$ echo "hv_storvsc" >> /etc/initramfs-tools/modules
$ update-initramfs -u
```

**SUSE：**
```bash
$ echo 'force_drivers+=" hv_vmbus hv_netvsc hv_storvsc "' >> /etc/dracut.conf.d/hyperv.conf
$ dracut -f
```

---

### 4.5 参考文献・リンク集

#### 4.5.1 Amazon Web Services (AWS)

**公式ドキュメント・発表：**

*インフラストラクチャ基盤：*
- AWS Nitro System: https://aws.amazon.com/ec2/nitro/
- AWS Graviton Processors: https://aws.amazon.com/ec2/graviton/
- AWS Graviton5発表（2025年12月）: https://www.aboutamazon.com/news/aws/aws-graviton-5-cpu-amazon-ec2
- Amazon EBS: https://aws.amazon.com/ebs/
- EC2 X8g Graviton4インスタンス: https://aws.amazon.com/blogs/aws/now-available-graviton4-powered-memory-optimized-amazon-ec2-x8g-instances/

*Nitro Systemアーキテクチャ（仮想化スタック）：*
- The Security Design of the AWS Nitro System（AWS Whitepaper）: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/security-design-of-aws-nitro-system.html
- Nitro Systemコンポーネント詳細: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-components-of-the-nitro-system.html
- Nitro System進化の歴史: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-nitro-system-journey.html
- Reinventing virtualization with the AWS Nitro System（Werner Vogels）: https://www.allthingsdistributed.com/2020/09/reinventing-virtualization-with-nitro.html
- Nitro System対応インスタンス一覧: https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-nitro-instances.html

*EC2 UltraClusters & UltraServers：*
- Amazon EC2 UltraClusters概要: https://aws.amazon.com/ec2/ultraclusters/
- Amazon EC2 UltraServers概要: https://aws.amazon.com/ec2/ultraservers/
- EC2 P6e-GB200 UltraServers発表: https://aws.amazon.com/blogs/aws/new-amazon-ec2-p6e-gb200-ultraservers-powered-by-nvidia-grace-blackwell-gpus-for-the-highest-ai-performance/
- EC2 P6インスタンスタイプ: https://aws.amazon.com/ec2/instance-types/p6/
- EC2 Trn2インスタンスタイプ: https://aws.amazon.com/ec2/instance-types/trn2/
- EC2 Trn3 UltraServers: https://aws.amazon.com/ec2/instance-types/trn3/

*Amazon Elastic VMware Service (EVS)：*
- Amazon EVS概要: https://aws.amazon.com/evs/
- Amazon EVS GA発表（2025年8月）: https://aws.amazon.com/jp/blogs/news/run-vmware-your-way-amazon-elastic-vmware-service-is-now-generally-available/
- Amazon EVS技術ドキュメント: https://docs.aws.amazon.com/evs/latest/userguide/getting-started.html
- AWS News Blog - EVS発表: https://aws.amazon.com/blogs/aws/introducing-amazon-elastic-vmware-service-for-running-vmware-cloud-foundation-on-aws

*AWS Trainium：*
- AWS Trainiumチップ概要: https://aws.amazon.com/ai/machine-learning/trainium/
- AWS Trainium3 UltraServers発表: https://www.aboutamazon.com/news/aws/trainium-3-ultraserver-faster-ai-training-lower-cost

*AWS AI Factories：*
- AWS AI Factories概要: https://aws.amazon.com/about-aws/global-infrastructure/ai-factories/
- AWS AI Factories発表: https://www.aboutamazon.com/news/aws/aws-data-centers-ai-factories

**技術分析・レビュー：**
- AWS Graviton5アーキテクチャ分析（NextPlatform）: https://www.nextplatform.com/2025/12/04/aws-graviton5-strikes-a-different-balance-for-server-cpus/
- AWS Graviton5発表（The Register）: https://www.theregister.com/2025/12/04/amazon_graviton_5/
- AWS Graviton5発表（Phoronix）: https://www.phoronix.com/news/AWS-Graviton5-Announced
- AWS Graviton4仕様（WikiChip）: https://en.wikichip.org/wiki/annapurna_labs/graviton/graviton4
- AWS Trainium3詳細分析（SemiAnalysis）: https://newsletter.semianalysis.com/p/aws-trainium3-deep-dive-a-potential

#### 4.5.2 Microsoft Azure

**公式ドキュメント・発表：**

*インフラストラクチャ基盤：*
- Azure Boost: https://techcommunity.microsoft.com/blog/azureinfrastructureblog/introducing-microsoft-azure-boost-preview/3876742
- Azure Cobalt 200発表（2025年11月）: https://techcommunity.microsoft.com/blog/AzureInfrastructureBlog/announcing-cobalt-200-azure%E2%80%99s-next-cloud-native-cpu/4469807
- Azure Cobaltプロセッサ概要: https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/cobalt-overview
- Azure Managed Disks: https://learn.microsoft.com/en-us/azure/virtual-machines/managed-disks-overview

*仮想化アーキテクチャ（OpenHCL/MSHV）：*
- OpenHCL（オープンソースパラバイザー）: https://github.com/microsoft/openvmm/tree/main/openhcl
- OpenVMM（Rustベースリファレンスモニター）: https://github.com/microsoft/openvmm
- OpenHCL: Evolving Azure's virtualization model: https://techcommunity.microsoft.com/blog/windowsosplatform/openhcl-evolving-azure%E2%80%99s-virtualization-model/4248345
- Azure Boost DPU発表（Ignite 2024）: https://techcommunity.microsoft.com/blog/azureinfrastructureblog/enhancing-infrastructure-efficiency-with-azure-boost-dpu/4298901
- ネステッド仮想化: https://learn.microsoft.com/en-us/azure/virtual-machines/windows/nested-virtualization
- Hyper-Vシステム要件: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/host-hardware-requirements

*Confidential Computing（x86-64）：*
- Azure Confidential VMs概要: https://learn.microsoft.com/en-us/azure/confidential-computing/confidential-vm-overview
- AMD SEV-SNP対応VM: https://learn.microsoft.com/en-us/azure/confidential-computing/virtual-machine-options
- Intel TDX対応VM: https://learn.microsoft.com/en-us/azure/confidential-computing/tdx-confidential-vm-overview
- Virtual Secure Mode (VSM): https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/tlfs/vsm

**技術分析・レビュー：**
- Azure Cobalt 200（Phoronix）: https://www.phoronix.com/news/Microsoft-Azure-Cobalt-200
- Azure Cobalt 200（TechPowerUp）: https://www.techpowerup.com/343062/microsoft-rolls-out-cobalt-200-cpu-with-132-arm-cores
- Azure Cobalt 200（Tom's Hardware）: https://www.tomshardware.com/tech-industry/semiconductors/microsoft-unveils-azure-cobalt-200-cpu
- Azure Cobalt 200（ServeTheHome）: https://www.servethehome.com/microsoft-azure-cobalt-200-launched-with-132-arm-neoverse-v3-cores/
- Azure Cobalt 200（Data Center Dynamics）: https://www.datacenterdynamics.com/en/news/microsoft-reveals-next-generation-cobalt-cpu-and-azure-boost/

#### 4.5.3 Google Cloud

**公式ドキュメント・発表：**

*Titanium & セキュリティ：*
- Google Cloud Titanium: https://cloud.google.com/titanium
- Titaniumハードウェアセキュリティアーキテクチャ: https://cloud.google.com/docs/security/titanium-hardware-security-architecture
- Titan Security Chip: https://cloud.google.com/docs/security/titan-hardware-chip
- Confidential Computing: https://cloud.google.com/security/products/confidential-computing

*仮想化アーキテクチャ：*
- Titaniumワークロード最適化インフラストラクチャ: https://cloud.google.com/blog/products/compute/titanium-underpins-googles-workload-optimized-infrastructure
- ネステッド仮想化: https://cloud.google.com/compute/docs/instances/nested-virtualization/overview
- Compute Engine VMセキュリティモデル: https://cloud.google.com/docs/security/infrastructure/design

*TPU（Tensor Processing Unit）：*
- TPU v7 Ironwood公式ドキュメント: https://cloud.google.com/tpu/docs/tpu7x
- TPU v6e Trillium公式ドキュメント: https://cloud.google.com/tpu/docs/v6e
- TPU概要: https://cloud.google.com/tpu/docs/intro-to-tpu
- Ironwood発表ブログ（2025年4月）: https://blog.google/products/google-cloud/ironwood-tpu-age-of-inference/
- TPU Ironwood & Axion発表: https://cloud.google.com/blog/products/compute/ironwood-tpus-and-new-axion-based-vms-for-your-ai-workloads

*Axion & Compute：*
- Google Axion Processors: https://cloud.google.com/products/axion
- Axion C4A GA発表（2025年1月）: https://cloud.google.com/blog/products/compute/first-google-axion-processor-c4a-now-ga-with-titanium-ssd
- Axion N4Aプレビュー発表（2025年11月）: https://cloud.google.com/blog/products/compute/axion-based-n4a-vms-now-in-preview
- Axion C4A-metal発表（2025年11月）: https://cloud.google.com/blog/products/compute/new-axion-c4a-metal-offers-bare-metal-performance-on-arm
- Arm VMs on Compute: https://cloud.google.com/compute/docs/instances/arm-on-compute

**技術分析・レビュー：**
- TPU Ironwood分析（The Register）: https://www.theregister.com/2025/11/06/googles_ironwood_tpus_ai/
- TPU Ironwood詳細（NextPlatform）: https://www.nextplatform.com/2025/04/09/with-ironwood-tpu-google-pushes-the-ai-accelerator-to-the-floor/
- TPU v7分析（SemiAnalysis）: https://newsletter.semianalysis.com/p/tpuv7-google-takes-a-swing-at-the
- Google Axionベンチマーク（Phoronix）: https://www.phoronix.com/review/google-axion-c4a

**オープンソースプロジェクト（Titanium関連）：**
- Caliptra（シリコンレベルRoT）: https://www.opencompute.org/documents/caliptra-silicon-rot-services-09012022-pdf
- OpenTitan（チップRoT）: https://opentitan.org/
- BoringSSL（暗号ライブラリ）: https://boringssl.googlesource.com/boringssl
- PSP Security Protocol: https://cloud.google.com/blog/products/identity-security/announcing-psp-security-protocol-is-now-open-source
- Syzkaller（カーネルファジング）: https://github.com/google/syzkaller/tree/master

#### 4.5.4 Oracle Cloud Infrastructure (OCI)

**公式ドキュメント・発表：**

*インフラストラクチャ基盤：*
- OCI Security Architecture: https://www.oracle.com/security/cloud-security/
- Oracle Acceleron: https://www.oracle.com/cloud/networking/acceleron/
- Oracle Acceleron発表（2025年10月）: https://www.oracle.com/news/announcement/ai-world-oracle-introduces-new-cloud-networking-capabilities-for-any-workload-2025-10-14/
- OCI Zettascale10（2025年10月発表）: https://www.oracle.com/news/announcement/ai-world-oracle-unveils-next-generation-oci-zettascale10-cluster-for-ai-2025-10-14/
- OCI GPU Compute: https://www.oracle.com/cloud/compute/gpu/
- OCI Block Volume: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/blockvolumeperformance.htm
- OCI Ampere Compute: https://www.oracle.com/cloud/compute/arm/
- OCI DenseIO Compute: https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm

*仮想化アーキテクチャ（Off-box Virtualization）：*
- OCI Isolated Network Virtualization: https://www.oracle.com/security/cloud-security/isolated-network-virtualization/
- OCI Security Architecture（Technical Brief）: https://www.oracle.com/a/ocom/docs/oracle-cloud-infrastructure-security-architecture.pdf
- OCI Bare Metal Servers: https://www.oracle.com/cloud/compute/bare-metal/
- Zero Trust Packet Routing (ZPR): https://docs.oracle.com/en-us/iaas/Content/zero-trust-packet-routing/overview.htm

#### 4.5.5 業界分析・比較情報

**クラウドインフラ比較：**
- Nevsemi - Google TPU Ironwood解説: https://www.nevsemi.com/blog/google-tpu-chip-ironwood-technology-explained
- TrendForce - Google Axion TSMC 3nm報道: https://www.trendforce.com/news/2025/10/21/news-googles-axion-cpu-reportedly-built-on-tsmcs-3nm-set-to-drive-foundrys-data-center-revenue-growth/

**セキュリティ関連：**
- CISA - ソフトウェアサプライチェーンセキュリティ: https://www.cisa.gov/sites/default/files/publications/defending_against_software_supply_chain_attacks_508.pdf
- NIST FIPS 140-3: https://csrc.nist.gov/projects/cryptographic-module-validation-program/

---

*本ドキュメントは2025年12月時点の公開情報に基づいて更新されています。各クラウドプロバイダーの仕様・価格は変更される可能性があります。最新情報は各社公式ドキュメントをご確認ください。*
