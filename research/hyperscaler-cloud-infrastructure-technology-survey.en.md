# Hyperscaler Cloud Computing Infrastructure Technology Survey

---

## 1. Executive Summary

### 1.1 Document Overview

This document provides a comprehensive survey and analysis of the IaaS infrastructure technologies of the four major hyperscalers (Amazon Web Services, Microsoft Azure, Google Cloud, and Oracle Cloud Infrastructure). It covers comparative analysis and detailed technical information across the following four key areas.

| Area | Content |
|:---|:---|
| **Hypervisor & Hardware Offload** | Virtualization platforms, dedicated offload processors, network & storage acceleration |
| **ARM-based CPUs** | Proprietary Arm processors developed by each provider (Graviton, Cobalt, Axion, Ampere) |
| **AI Acceleration** | Dedicated AI chips (TPU, Trainium), GPUs, large-scale cluster configurations |
| **Storage & Device Drivers** | Block storage, local storage, guest OS drivers |

### 1.2 Key Technology Trends Summary

#### Hypervisor & Offload Technology

Each provider is improving performance and security by offloading network, storage, and security functions from traditional hypervisors to dedicated hardware.

| Provider | Offload Technology | Max Network | Characteristics |
|:---|:---|:---|:---|
| **AWS** | Nitro System v6 | 400 Gbps | Most mature (2017~6 generations), ASIC-based |
| **Azure** | Azure Boost | 400 Gbps | FPGA + MANA, leading in Confidential Computing |
| **Google Cloud** | Titanium | 200 Gbps | 2-tier offload (IPU + TOP), TPU integration |
| **Oracle Cloud** | Acceleron | 200+ Gbps | Complete off-box separation, 100% physical cores provided |

#### ARM-based CPUs

All four providers are deploying proprietary or partnered Arm processors, achieving price-performance and energy efficiency advantages over x86.

| Provider | Latest CPU | Architecture | Max Cores | Availability |
|:---|:---|:---|:---|:---|
| **AWS** | Graviton5 | Neoverse V3 | 192 | December 2025 GA |
| **Azure** | Cobalt 200 | Neoverse V3 | 132 | 2026 GA planned |
| **Google Cloud** | Axion N4A | Neoverse N3 | 64 | November 2025 Preview |
| **Oracle Cloud** | Ampere A2 | Armv8.6+ | 156 | August 2024 GA |

#### AI Acceleration

Competition is intensifying in both dedicated ASICs and GPUs, with superclusters being built at scales of hundreds of thousands to millions of chips.

| Provider | Dedicated ASIC | Max GPU Scale | Characteristics |
|:---|:---|:---|:---|
| **AWS** | Trainium3 | 20,000+ GPU | UltraServers/UltraClusters, AI Factories |
| **Azure** | Maia 100 | Large-scale IB | Cross-region RDMA support |
| **Google Cloud** | TPU v7 Ironwood | 9,216/Pod | 42.5 ExaFLOPS/Pod, Anthropic Claude running |
| **Oracle Cloud** | - | 800,000 GPU | Zettascale10, OpenAI Stargate foundation |

### 1.3 Provider-Specific Differentiators

#### AWS (Amazon Web Services)

- **Nitro System**: Industry's most mature offload architecture (2017~6 generations deployed)
- **Graviton5**: First PCIe 6.0 support, single-socket 192-core design eliminates NUMA
- **Vertical Integration**: Annapurna Labs in-house development + Nitro System integration
- **AI Factories**: New service deploying AWS infrastructure within customer data centers
- **Market Share**: Over 50% of AWS new CPU capacity is Graviton

#### Microsoft Azure

- **Azure Boost**: Next generation (November 2025) with 1M IOPS, 20GB/s, 400Gbps network
- **Cobalt 200**: AI-driven design (evaluated 350,000 configuration candidates), Arm CCA support
- **OpenHCL**: Rust-based paravisor open-sourced in 2024
- **Enterprise Integration**: Deep integration with Windows environment, Azure Stack HCI support
- **Confidential Computing**: Advanced TEE support (SGX/SEV/TDX) (GA 2019)

#### Google Cloud

- **Titanium**: 2-tier offload architecture (on-host IPU + off-host TOP)
- **TPU Ironwood**: Up to 9,216 chips per Pod, 42.5 ExaFLOPS
- **AI Hypercomputer**: Integrated AI infrastructure combining TPU, GPU, CPU, storage, and network
- **Caliptra RTM**: OCP standard-compliant silicon-level Root of Trust
- **Open Source Contributions**: OpenTitan, Caliptra, BoringSSL, PSP

#### Oracle Cloud Infrastructure

- **Off-box Network Virtualization**: Industry first (2016~), 100% physical cores provided to customers
- **Zettascale10**: Up to 800,000 GPUs, OpenAI Stargate project foundation
- **Price Competitiveness**: A1 at $0.01/OCPU/hour (industry's first penny core)
- **Always Free Tier**: 4 OCPU + 24GB RAM free
- **BYO Hypervisor**: Most flexible support (Oracle VM, Hyper-V, KVM, VMware)

### 1.4 Technology Trends Overview

| Trend | Overview |
|:---|:---|
| **Advanced Hardware Offload** | Complete separation of network/storage processing from CPU via dedicated ASIC/FPGA/DPU |
| **Mainstream Arm Processors** | Full deployment of proprietary ARM CPUs, 20-50% of new capacity is Arm |
| **Ultra-Scale AI Infrastructure** | Supercluster construction at scales of hundreds of thousands to millions of chips |
| **Confidential Computing Adoption** | Standardization of data-in-use protection via TEE (SGX/SEV/TDX/CCA) |
| **Silicon-Level Root of Trust** | Hardware security enhancement via Caliptra/OpenTitan etc. |
| **NVMe Interface Standardization** | NVMe required for 3rd generation and later VMs (Google Cloud C3/C4 etc.) |

---


## 2. Cloud Service Provider Comparison

This section provides cross-cutting comparisons of the four hyperscalers. Comparison tables for each technology area are organized to provide reference information for provider selection.

### 2.1 Hypervisor & Offload Architecture Comparison

#### 2.1.1 Hypervisor Architecture Overview

| Provider | Offload Technology Name | Base Technology | Hypervisor | Offload Method | Key Features |
|:---|:---|:---|:---|:---|:---|
| **AWS** | Nitro System | **Linux KVM** | Nitro Hypervisor (lightweight KVM) | Dedicated ASIC cards (on-host) | Nearly 100% CPU to customers, bare-metal equivalent performance |
| **Microsoft Azure** | Azure Boost | **Microsoft Hypervisor (MSHV)** | x86-64: Hyper-V, ARM64: MSHV + OpenHCL | FPGA + Software | Enterprise integration, Windows/Linux support |
| **Google Cloud** | Titanium | **Linux KVM** | Custom KVM | 2-tier offload (on-host + off-host) | IPU/TOP distributed offload, AI optimization |
| **Oracle Cloud** | Oracle Acceleron | **Oracle Linux KVM** | UEK-based KVM | Off-box (host-external separation) | Physical core units, no oversubscription |

**Note:** Microsoft Azure's virtualization platform varies by CPU architecture. x86-64 environments use Hyper-V (on Windows Host OS), while ARM64 environments use Microsoft Hypervisor (MSHV) + OpenHCL paravisor.

#### 2.1.2 Detailed Hypervisor Comparison

| Comparison Item | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **Base Kernel** | Linux | Windows (x86-64) / Linux (ARM64/paravisor) | Linux | Oracle Linux (UEK) |
| **Virtualization Technology (x86-64)** | KVM | Hyper-V | KVM | KVM |
| **Virtualization Technology (ARM64)** | KVM (Graviton) | **MSHV + OpenHCL** (non-Hyper-V) | KVM | KVM |
| **Hypervisor Name** | Nitro Hypervisor | x86-64: Hyper-V / ARM64: MSHV | Custom KVM | Oracle Linux KVM |
| **Paravisor** | - | OpenHCL (Rust-based, OSS 2024) | - | - |
| **Hypervisor Role** | Memory/CPU allocation only | Full function + offload | Memory/CPU + partial I/O | Memory/CPU allocation only |
| **Network Virtualization** | Nitro Card (on-host) | MANA/FPGA | IPU + TOP | SmartNIC (Off-box) |
| **Bare Metal Support** | ✅ Many shapes | ✅ Limited | ✅ Bare Metal Solution | ✅ Many shapes |
| **BYO Hypervisor** | ✅ On bare metal | ✅ Dedicated Host/AVS | ✅ Bare Metal/GCVE | ✅ On bare metal |
| **Supported Hypervisors** | VMware, Nutanix, Hyper-V, KVM etc. | VMware (AVS), Hyper-V | VMware (GCVE), others | Oracle VM, Hyper-V, KVM, VMware |
| **VMware Service** | Amazon Elastic VMware Service (EVS), VMware Cloud on AWS | Azure VMware Solution (AVS) | Google Cloud VMware Engine (GCVE) | Oracle Cloud VMware Solution (OCVS) |
| **Open Source** | Firecracker, Bottlerocket | OpenHCL/OpenVMM (2024), mshv_vtl driver | - | - |

#### 2.1.3 Offload Architecture Feature Comparison

| Feature Category | AWS Nitro | Azure Boost | Google Titanium | Oracle Acceleron |
|:---|:---|:---|:---|:---|
| **Max Network Bandwidth** | 400 Gbps | 400 Gbps | 200 Gbps | 200+ Gbps |
| **HPC/AI Network** | 3,200 Gbps (EFA) | 3,200 Gbps (IB) | 3,200 Gbps (ML Adapter) | 3,200 Gbps (RDMA) |
| **Storage IOPS (Remote)** | 260K IOPS | 1M IOPS | 500K IOPS | 2x improvement (vs. previous) |
| **Storage Throughput (Remote)** | - | 20 GB/s | - | - |
| **Storage IOPS (Local)** | 7.5M IOPS | 3.8M IOPS | High IOPS | - |
| **Root of Trust** | Nitro Security Chip | Pluton + Azure HSM | Titan | Hardware Root-of-Trust |
| **Confidential Computing** | Nitro Enclaves | TEE (SGX/SEV) + ABCD | Confidential VMs | - |
| **Zero Trust** | Security Groups | NSG | VPC Firewall | ZPR |
| **Offload Method** | On-host ASIC | FPGA + Software | 2-tier (IPU+TOP) | Off-box (host-external) |
| **RDMA Support** | ✅ EFA v4 | ✅ Cross-region support | ✅ | ✅ RoCEv2 |
| **Bare Metal Offering** | ✅ Many | ✅ Limited | ✅ Bare Metal Solution | ✅ Many |
| **BYO Hypervisor** | ✅ On bare metal | ✅ AVS/Dedicated Host | ✅ BMS/GCVE | ✅ On bare metal |
| **Managed VMware** | Amazon Elastic VMware Service (EVS), VMware Cloud on AWS | Azure VMware Solution | GCVE | OCVS |

### 2.2 BYO Hypervisor Support Comparison

#### 2.2.1 Hypervisor CPU Architecture Support Status

Hypervisors depend on CPU architecture, so support status differs significantly between x86-64 (Intel/AMD) and ARM64 (Arm).

**Important Background:**
- Hypervisors directly use privileged instructions and CPU virtualization extensions (Intel VT-x, AMD-V, Arm VHE), making **virtualization across different CPU architectures impossible** (only emulation is possible)
- ARM64 guests cannot be "virtualized" on x86-64 hosts (QEMU emulation is possible but slow)

| Hypervisor | x86-64 (Intel/AMD) | ARM64 (Arm) | Notes |
|:---|:---|:---|:---|
| **Microsoft Hyper-V** | ✅ Production support (Windows Server 2008~2025) | ⚠️ Client only (Windows 11 22H2+) | Windows Server ARM64 not released |
| **VMware ESXi** | ✅ Production support (ESXi 8.0 U3e latest) | ⚠️ Tech Preview (ESXi-Arm Fling) | ARM64 experimental only |
| **Linux KVM** | ✅ Production support | ✅ Production support (Linux 3.10~, 2013) | Full support for both architectures |
| **Xen** | ✅ Production support (max 12 TiB host) | ✅ Production support (max 2 TiB host, Xen 4.4~) | Full support for both architectures |
| **Nutanix AHV** | ✅ Production support (KVM-based) | ❌ Not supported | x86-64 only |
| **Oracle VM** | ✅ Production support (Xen/KVM-based) | ❌ Not supported | x86-64 only |
| **Oracle Linux KVM** | ✅ Production support | ✅ Production support (aarch64 support) | ARM64 support in Oracle Linux 8/9 |
| **Proxmox VE** | ✅ Production support (KVM/LXC) | ⚠️ Community support | ARM64 community-provided |

**Legend:** ✅ Production support (commercial use) / ⚠️ Limited/experimental / ❌ Not supported

#### 2.2.2 BYO Hypervisor Support by Cloud Provider

| Item | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **Bare Metal Instances (x86-64)** | i3.metal, i4i.metal, i7i.metal, m5.metal, c5.metal etc. many | Dedicated Host (limited) | Bare Metal Solution (Z3, C4 etc.) | BM.Standard, BM.DenseIO, BM.GPU, BM.HPC etc. many |
| **Bare Metal Instances (ARM64)** | mac2-m2.metal (Apple Silicon) *Hyper-V/ESXi not possible | None | Bare Metal Solution (C4A) | BM.Standard.A1 (Ampere Altra) *Hyper-V/ESXi not possible |
| **VMware Support** | ✅ EVS/VMC on AWS (**x86-64 only**) | ✅ AVS (**x86-64 only**) | ✅ GCVE (**x86-64 only**) | ✅ OCVS (**x86-64 only**) |
| **Nutanix Support** | ✅ NC2 on AWS (**x86-64 only**, AHV) | ✅ NC2 on Azure (**x86-64 only**) | ✅ NC2 on GCP (**x86-64 only**) | Self-managed (**x86-64 only**) |
| **Hyper-V Support** | ✅ On bare metal (**x86-64 only**) | Native (**x86-64 only**) | ✅ On BMS (**x86-64 only**) | ✅ BYOH (**x86-64 only**) |
| **KVM Support** | ✅ On bare metal (**x86-64/ARM64 both**) | ✅ Nested virtualization (**x86-64 only**) | ✅ On BMS (**x86-64/ARM64 both**) | ✅ Oracle Linux KVM (**x86-64/ARM64 both**) |
| **Xen Support** | Possible on bare metal (**x86-64/ARM64 both**) | - | Possible on bare metal (**x86-64/ARM64 both**) | - |
| **License Portability** | ✅ BYOL support | ✅ Azure Hybrid Benefit | ✅ BYOL support | ✅ BYOL support |
| **Hard Partitioning** | - | - | - | ✅ Oracle Linux KVM/Oracle VM |

**Important:** VMware ESXi, Hyper-V, and Nutanix AHV are **x86-64 only**. For BYO hypervisor on ARM64 environments, choose **KVM or Xen**.

#### 2.2.3 VMware Service Comparison

**Note: All VMware services are x86-64 only. VMware cannot be used on ARM64 instances.**

| Item | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **Service Name** | **Amazon Elastic VMware Service (EVS)** (new), VMware Cloud on AWS | Azure VMware Solution (AVS) | Google Cloud VMware Engine (GCVE) | Oracle Cloud VMware Solution (OCVS) |
| **CPU Architecture** | **x86-64 only** | **x86-64 only** | **x86-64 only** | **x86-64 only** |
| **Delivery Model** | EVS: AWS Native (self-managed), VMC on AWS: Broadcom managed | Microsoft Managed | Google Managed | Oracle Managed |
| **VMware Products** | VMware Cloud Foundation (VCF) 5.2.1 | VMware vSphere, vSAN, NSX-T | VMware vSphere, vSAN, NSX-T | VMware vSphere, vSAN, NSX-T |
| **VPC Integration** | ✅ Runs directly in Amazon VPC (EVS) | ✅ Azure VNet integration | ✅ VPC integration | ✅ VCN integration |
| **Management Console** | EVS: AWS Management Console | Azure Portal | Google Cloud Console | OCI Console |
| **License Portability** | ✅ VCF license bring-your-own (EVS) | ✅ Supported | ✅ Supported | ✅ Supported |
| **Minimum Configuration** | EVS: 4 hosts | 3 hosts | 3 hosts | 3 hosts |
| **Status** | EVS: **GA (August 2025~, 6 regions)** | GA | GA | GA |

#### 2.2.4 Nutanix Cloud Clusters (NC2) Detailed Comparison

| Item | NC2 on AWS | NC2 on Azure | NC2 on Google Cloud |
|:---|:---|:---|:---|
| **Status** | GA | GA | GA (December 2025) |
| **CPU Architecture** | **x86-64 only** | **x86-64 only** | **x86-64 only** |
| **Bare Metal Instances** | i3.metal, i4i.metal, i7i.metal (7+ types) | AN36P etc. | Z3-metal, C4-metal |
| **Hypervisor** | Nutanix AHV (KVM-based, x86-64 only) | Nutanix AHV | Nutanix AHV |
| **Storage** | Local NVMe + EBS (additional possible) | Local NVMe + Elastic SAN | Local NVMe |
| **Network Integration** | Direct deploy in VPC, Flow Virtual Networking | VNet integration, Flow Virtual Networking | Direct deploy in VPC, Flow Virtual Networking |
| **License** | BYOL (portable), PAYG, AWS Marketplace | BYOL (portable), PAYG, Azure Marketplace, MACC support | BYOL (portable), PAYG, Google Cloud Marketplace |
| **Minimum Configuration** | 3 nodes | 3 nodes | 3 nodes |
| **Deployment Time** | Less than 1 hour | Less than 1 hour | Less than 2 hours |
| **Regions** | Many globally | Many globally (UAE North, Qatar Central etc. added) | 17 regions (expansion planned 2026) |
| **Primary Use Cases** | VMware migration, DR, cloud bursting | VMware migration, DR, cloud bursting | VMware migration, DR, AI/ML integration, BigQuery/Vertex AI integration |

### 2.3 ARM-based CPU Comparison

#### 2.3.1 ARM-based CPU List

| Provider | CPU Name | Architecture | Max Cores | Max Memory | Features | Supported Instances | Release Date |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **AWS** | Graviton5 | Arm Neoverse V2+ | 192 cores | TBD (R9g 2026 planned) | PCIe 6.0 support, Nitro v6 integration, 5x L3 cache, 25% performance improvement | M9g, C9g, R9g | December 2025 (GA) |
| **AWS** | Graviton4 | Arm Neoverse V2 | 96 cores | 3 TiB (X8g) | Up to 40% price-performance vs x86, DDR5 | R8g, M8g, C8g, X8g | November 2023 |
| **AWS** | Graviton3 | Arm Neoverse V1 | 64 cores | 512 GB (R7g) | DDR5, PCIe 5.0 support | C7g, M7g, R7g | May 2021 |
| **Microsoft Azure** | Cobalt 200 | Arm Neoverse CSS V3 | 132 cores | TBD | 3nm process, 50% performance improvement, Azure HSM integration, FIPS 140-3 Level 3 | 2026 GA planned | November 2025 (Preview) |
| **Microsoft Azure** | Cobalt 100 | Arm Neoverse N2 | 128 cores | 672 GiB (Epsv6) | Up to 50% price-performance vs x86, 32 region deployment | Dpsv6, Dplsv6, Epsv6 | October 2024 (GA) |
| **Google Cloud** | Axion (N4A) | Arm Neoverse N3 | 64 cores | 512 GB | Best cost efficiency in N-series, 2x price-performance vs x86, 80% perf/watt improvement | N4A | November 2025 (Preview) |
| **Google Cloud** | Axion (C4A) | Arm Neoverse V2 | 96 cores (metal) | 768 GB (metal) | Titanium SSD integration, up to 100Gbps network | C4A, C4A-metal | January 2025 (GA) |
| **Oracle Cloud** | Ampere AmpereOne (A2) | Armv8.6+ (custom) | 156 cores | 946 GB | DDR5, 2MB L2/core, 28% performance improvement vs A1 | VM.Standard.A2.Flex | August 2024 |
| **Oracle Cloud** | Ampere Altra (A1) | Arm Neoverse N1 | 160 cores | 1 TB (BM) | Single-thread design, 1MB L2/core, 3.0GHz | BM.Standard.A1.160, VM.Standard.A1.Flex | May 2021 |

#### 2.3.2 Performance & Cost Comparison (Reference Values)

| Item | Graviton5 | Graviton4 | Cobalt 200 | Cobalt 100 | Axion C4A | Axion N4A | Ampere A2 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **Architecture** | Neoverse V3 | Neoverse V2 | Neoverse V3 | Neoverse N2 | Neoverse V2 | Neoverse N3 | Custom Arm |
| **Manufacturing Process** | 3nm | 4nm | 3nm | 5nm | 3nm | Undisclosed | 5nm |
| **Max Cores** | 192 | 96 (192 vCPU) | 132 (264) | 128 | 72 (96 metal) | 64 | 156 |
| **L2 Cache/Core** | Improved | 2MB | 3MB | 1MB | 2MB | Undisclosed | 2MB |
| **L3 Cache** | 5x increase | Shared | 192MB | Shared | 80MB | Undisclosed | Shared |
| **Memory Channels** | 12 DDR5 | 12 DDR5 | 12 DDR5 | 8 DDR5 | 6 DDR5 | Undisclosed | DDR5 |
| **Max Memory** | Undisclosed | 3 TiB | Undisclosed | 672 GiB | 768 GB | 512 GB | 946 GB |
| **PCIe** | 6.0 | 5.0 | 5.0 | 4.0 | 5.0 | Undisclosed | 5.0 |
| **Availability** | Preview | GA | Datacenter running | GA | GA | Preview | GA |

#### 2.3.3 Market Trends & Adoption Results

| Metric | Value | Source Date |
|:---|:---|:---|
| Graviton share of AWS new CPU capacity | Over 50% | 2024 |
| Arm share of Azure new CPUs | 32.9% | 2024 Q4 |
| Axion share of GCP new instances | 21.2% | 2024 Q4 |
| OCI ARM service support count | 100+ OCI services | 2024 |

| Provider | Customer Adoption & Results |
|:---|:---|
| **AWS Graviton** | Airbnb (25% performance improvement), Epic Games (fastest test results), SmugMug/Flickr (20-40% improvement) |
| **Azure Cobalt** | Microsoft Teams (45% performance improvement, 35% core reduction), Databricks, Snowflake |
| **Google Axion** | Databricks (40% efficiency improvement), Elastic (40% throughput improvement), ClickHouse (40% efficiency improvement) |
| **OCI Ampere** | Red Bull Racing (25% speed improvement), Zoom, Adobe |

### 2.4 AI Accelerator Comparison

#### 2.4.1 Dedicated ASIC Comparison

| Provider | Product Name | Type | Peak Performance | Memory | Use Case |
|:---|:---|:---|:---|:---|:---|
| **AWS** | Trainium3 | ASIC | 2.52 PFLOPs FP8/chip | 144 GB HBM3e | Training/Inference |
| **AWS** | Trainium2 | ASIC | 1.3 PFLOPs FP8/chip | 96 GB | Training |
| **AWS** | Inferentia2 | ASIC | - | - | Inference |
| **Google Cloud** | TPU v7 Ironwood | ASIC | 4,614 TFLOPS FP8 | 192 GB HBM3e | Training/Inference |
| **Google Cloud** | TPU v6e Trillium | ASIC | 918 TFLOPS FP8 | 32 GB HBM3 | Training/Inference |
| **Microsoft Azure** | Maia 100 | ASIC | - | - | General AI tasks |

#### 2.4.2 Large-Scale AI Cluster Comparison

| Provider | Configuration Name | Max GPU/Chip Count | Performance | Features |
|:---|:---|:---|:---|:---|
| **AWS** | EC2 UltraClusters | 20,000+ GPU | 20+ ExaFLOPS | P6e-GB200, Trn3 UltraServers support |
| **AWS** | P6e-GB200 UltraServer | 72 GPU/Server | 360 PFLOPS | NVIDIA Grace Blackwell Superchip |
| **AWS** | Trn3 UltraServer | 144 Trainium3 | 362 PFLOPS | NeuronSwitch-v1 connectivity |
| **Google Cloud** | TPU v7 Ironwood Pod | 9,216 chips/Pod | 42.5 ExaFLOPS | ICI interconnect |
| **Oracle Cloud** | Zettascale | 131,072 GPU | 2.4 ZettaFLOPS | Acceleron RoCE |
| **Oracle Cloud** | Zettascale10 | 800,000 GPU | 16 ZettaFLOPS | OpenAI Stargate foundation |

### 2.5 Storage Performance Comparison

#### 2.5.1 Remote Block Storage (Maximum Performance)

| Metric | AWS (io2 Block Express) | Azure (Ultra Disk) | Google Cloud (Hyperdisk Extreme) | OCI (UHP) |
|:---|:---|:---|:---|:---|
| **Max IOPS/Volume** | 256,000 | 400,000 | 350,000 | 300,000 |
| **Max Throughput/Volume** | 4,000 MB/s | 10,000 MB/s | 5,000 MB/s | 2,680 MB/s |
| **Max Capacity** | 64 TiB | 65,536 GiB | 64 TiB | 32 TiB |
| **Latency** | < 500μs (avg) | Sub-millisecond | Sub-millisecond | Sub-millisecond |

### 2.6 Hardware Component Comparison

| Component | AWS | Azure | Google Cloud | Oracle Cloud |
|:---|:---|:---|:---|:---|
| **DPU/SmartNIC** | Nitro Cards (in-house developed) | FPGA + DPU | Titanium Adapter/IPU | AMD Pensando / NVIDIA BlueField-3 |
| **ARM64 Support** | Graviton2-4 | Ampere Altra / Cobalt 100-200 | Axion (in-house developed) | Ampere Altra / AmpereOne |
| **Confidential Computing** | Nitro Enclaves | AMD SEV-SNP / Intel TDX | Confidential VMs | AMD SEV |

**Generation-Specific Major Instance Support Quick Reference:**

| Generation Features | AWS | Azure | Google Cloud | OCI |
|:---|:---|:---|:---|:---|
| **Latest Generation (Nitro v6 etc.)** | M8a, M8i, C8a, C8i, C8gn, R8a, R8i, I8ge, P6-B200 | Dv6, Easv6, Fasv6, Dpsv6 | C4, C4A, C4D, N4, N4D, H4D | E5.Flex, A2.Flex, GPU.H100 |
| **Previous Generation (Nitro v5 etc.)** | M8g, C8g, C7gn, R8g, I7ie, I8g, P5en, Trn2 | Dv5, Ev5, Fav5, Dpsv5 | C3, C3D, H3, A3 | E4.Flex, A1.Flex, GPU.B4 |
| **Older Generation (Nitro v4 etc.)** | M6i, M7i, C6i, C7i, R6i, R7i, P5, Trn1 | Dv4, Ev4, Fsv2 | N2, N2D, E2, C2 | E3.Flex, Standard3 |
| **Legacy (Nitro v2/v3 etc.)** | M5, C5, R5, M6g, C6g, R6g | Dv3, Ev3 | N1 | Standard2 |

---

## 3. Provider-Specific Detailed Information

This section provides detailed technical information for each hyperscaler individually.

### 3.1 Amazon Web Services (AWS)

#### 3.1.1 AWS Nitro System

The AWS Nitro System is a hardware offload architecture that AWS has been deploying since 2017. Through dedicated ASICs, it offloads network, storage, and security functions, providing nearly 100% of CPU resources to customer workloads.

**Nitro Generation Release History:**

| Generation | Release Date | Example Instances | Max Network | Key Features |
|:---|:---|:---|:---|:---|
| **Nitro v2** | November 2017 | C5, M5, R5, A1, M6g, T3, C6g, R6g | Instance dependent | First Nitro, ENA support, KVM-based |
| **Nitro v3** | 2019 | C5n, M5n, R5n, I3en, G4dn, G5, P4d | 100 Gbps | In-transit encryption added |
| **Nitro v4** | 2021 | C6i, M6i, R6i, C7g, M7g, I4i, P5, Trn1 | 170 Gbps | ENA Express support, RDMA read/write (partial) |
| **Nitro v5** | 2022~2024 | C7gn, M8g, R8g, C8g, I7ie, I8g, P5en, Trn2, Hpc7g | 200 Gbps | High PPS, low latency |
| **Nitro v6** | 2024~2025 | M8a, M8i, C8a, C8i, C8gn, R8a, R8i, I8ge, P6-B200 | 400 Gbps | Latest generation, RDMA Read/Write support |

**Component Details:**

| Category | Component | Release Date | Generation/Version | Function Description | Performance Metrics |
|:---|:---|:---|:---|:---|:---|
| **Network** | Nitro Card for VPC | 2017 | v2~v6 | Packet processing, security groups, routing | Up to 400 Gbps (v6) |
| **Network** | ENA (Elastic Network Adapter) | 2016 | v2~v6 | High-bandwidth network interface, SR-IOV | Up to 100 Gbps (standard) |
| **Network** | ENA Express | 2022 | Nitro v4+ | SRD-based congestion control, 25Gbps single flow | P99 latency 50% improvement |
| **Network** | EFA (Elastic Fabric Adapter) | 2019 | Gen 1~2 | HPC/AI RDMA, GPUDirect, libfabric | Up to 3,200 Gbps |
| **Storage** | Nitro Card for EBS | 2017 | v2~v6 | EBS access, encryption offload | Up to 260K IOPS |
| **Storage** | Nitro Card for Local NVMe | 2017 | v2~v6 | Local SSD access, AES-256 encryption | Up to 7.5M IOPS |
| **Security** | Nitro Security Chip | 2017 | - | Hardware Root of Trust, secure boot | - |
| **Security** | Nitro Enclaves | 2020 | - | Isolated confidential computing environment | - |
| **Security** | NitroTPM | 2022 | TPM 2.0 compliant | Virtual TPM, cryptographic key management | - |
| **Security** | Instance-to-Instance Encryption | 2019 (v3~) | AES-256-GCM | Automatic encryption (in-transit) | Line rate |
| **Management** | Nitro Controller | 2017 | v2~v6 | Unified management of all Nitro cards, instance monitoring | - |
| **Management** | Nitro Hypervisor | 2017 | KVM-based | Lightweight hypervisor (memory/CPU allocation) | Overhead <1% |

**AWS Nitro System Virtualization Stack:**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Guest OS (Linux/Windows)                      │
│              ┌─────────────────────────────────────┐            │
│              │        Guest Drivers                 │            │
│              │   ENA (Network) / NVMe (Storage)     │            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│                    Nitro Hypervisor                              │
│         (Lightweight KVM-based, memory/CPU allocation only)      │
│              No network stack, no filesystem                     │
├─────────────────────────────────────────────────────────────────┤
│                    SR-IOV Virtual Functions                      │
│              (Direct assignment from Nitro Card to VM)           │
├─────────────┬─────────────┬─────────────┬───────────────────────┤
│  Nitro Card │  Nitro Card │  Nitro Card │   Nitro Security      │
│  for VPC    │  for EBS    │  for NVMe   │      Chip             │
│ (Network)   │ (Remote SSD)│ (Local SSD) │  (Root of Trust)      │
├─────────────┴─────────────┴─────────────┴───────────────────────┤
│                    Nitro Controller                              │
│           (Unified Nitro card management, EC2 control plane)     │
├─────────────────────────────────────────────────────────────────┤
│           Host CPU (Graviton / Intel Xeon / AMD EPYC)           │
└─────────────────────────────────────────────────────────────────┘
```

**Architecture Characteristics:**
- **Offload Method**: On-host (dedicated ASIC cards)
- **Hypervisor**: Nitro Hypervisor (KVM-based, minimized design)
- **I/O Virtualization**: Direct VM assignment of Nitro Cards via SR-IOV
- **Security Model**: Passive communication (Nitro Hypervisor only waits for commands from Nitro Controller)
- **Admin Access**: Physically and logically eliminated (including AWS employees)

**Important Limitations:**
- **Nested Virtualization Support**: x86-64 (Intel VT-x/AMD-V) only. KVM in VM not supported on Graviton (ARM64)
- **Bare Metal Instances**: Direct Nitro Card control, no hypervisor

#### 3.1.2 AWS Graviton

AWS develops the Graviton series in-house through Annapurna Labs (acquired in 2015). Since 2024, Graviton accounts for over 50% of AWS's new CPU capacity.

**AWS Graviton5 (December 2025 Preview, 2026 GA planned):**

| Item | Specifications |
|:---|:---|
| **Processor** | AWS Graviton5 |
| **Architecture** | Arm Neoverse V3 (ARMv9.2-A) |
| **Manufacturing Process** | TSMC 3nm |
| **Core Count** | 192 cores (single socket) |
| **L3 Cache** | 5x increase (vs Graviton4), 2.67x increase per core |
| **Memory Channels** | 12-channel DDR5-7200 (DDR5-8400 support planned) |
| **Memory Bandwidth** | 691.2 GB/s (DDR5-7200), 806.4 GB/s (DDR5-8400) |
| **PCIe** | PCIe 6.0 (96 lanes, 2.84 TB/s bidirectional) |
| **Network** | Nitro 6 integration, up to 100 Gbps (2x improvement) |
| **Supported Instances** | M9g (preview), C9g/R9g (2026 planned) |
| **Performance vs Graviton4** | 25% improvement |
| **Features** | Single-socket design (no NUMA), 1/3 core-to-core latency reduction |

**AWS Graviton4 (November 2023 announced, 2024 GA):**

| Item | Specifications |
|:---|:---|
| **Processor** | AWS Graviton4 |
| **Architecture** | Arm Neoverse V2 (ARMv9.0-A + SVE2) |
| **Manufacturing Process** | TSMC 4nm (7 chiplet configuration) |
| **Core Count** | 96 cores/socket (dual-socket support for up to 192 vCPU) |
| **L2 Cache** | 2MB/core (192MB total) |
| **Memory Channels** | 12-channel DDR5-5600 |
| **Memory Bandwidth** | 536.7 GB/s/socket |
| **Max Memory** | 3 TiB (X8g instances) |
| **PCIe** | PCIe 5.0 (96 lanes) |
| **Supported Instances** | R8g, M8g, C8g, X8g, I8g |
| **Performance vs Graviton3** | Database 40%, Web apps 30%, Large Java 45% improvement |

**AWS Graviton3/3E (May 2021 announced):**

| Item | Specifications |
|:---|:---|
| **Processor** | AWS Graviton3 / Graviton3E |
| **Architecture** | Arm Neoverse V1 (ARMv8.4-A) |
| **Core Count** | 64 cores |
| **Frequency** | 2.6 GHz |
| **SIMD** | 4×128bit Neon + 2×256bit SVE |
| **Memory Channels** | 8-channel DDR5-4800 |
| **Memory Bandwidth** | 307.2 GB/s |
| **PCIe** | PCIe 5.0 (industry first support) |
| **Supported Instances** | C7g, M7g, R7g (Graviton3), C7gn, HPC7g (Graviton3E) |
| **Performance vs Graviton2** | Compute 25%, floating point 2x, crypto 2x, ML 3x improvement |
| **Energy Efficiency** | 60% power reduction at equivalent performance |

#### 3.1.3 AWS Trainium & Inferentia

**Trainium3 Chip Specifications:**

| Item | Specifications |
|:---|:---|
| **Manufacturing Process** | TSMC 3nm |
| **FP8 Compute Performance** | 2.52 PFLOPS/chip |
| **HBM3e Memory** | 144 GB/chip |
| **Memory Bandwidth** | 4.9 TB/s/chip |
| **Supported Precision** | FP32, BF16, MXFP8, MXFP4 |

**Trn3 UltraServer Specifications:**

| Item | Gen1 UltraServer | Gen2 UltraServer |
|:---|:---|:---|
| **Trainium3 Chip Count** | 64 (estimated) | 144 |
| **Total FP8 Compute** | ~161 PFLOPS | 362 PFLOPS |
| **HBM3e Total** | ~9.2 TB | 20.7 TB |
| **Memory Bandwidth Total** | ~314 TB/s | 706 TB/s |
| **Switch** | NeuronSwitch-v1 | NeuronSwitch-v1 |

**Trainium2 Chip Specifications:**

| Item | Specifications |
|:---|:---|
| **NeuronCore Count** | 8/chip |
| **HBM Memory** | 96 GB/chip |
| **Memory Bandwidth** | 2.9 TB/s/chip |
| **FP8 Compute (Dense)** | 1.3 PFLOPS/chip |
| **FP8 Compute (Sparse)** | 5.2 PFLOPS/chip |

#### 3.1.4 AWS EC2 UltraClusters & UltraServers

**EC2 UltraCluster Components:**

| Component | Description |
|:---|:---|
| **Accelerated Instances** | P6e-GB200, P6-B200, P5en, P5e, P5, P4d, Trn2, Trn3, Trn1 instances |
| **Network** | Petabit-scale non-blocking network via Elastic Fabric Adapter (EFA) |
| **Storage** | Amazon FSx for Lustre (high-performance parallel file system), Amazon S3 |
| **Placement** | Co-located in specific AWS Availability Zones |

**P6e-GB200 UltraServers Specifications:**

| Item | u-p6e-gb200x72 | u-p6e-gb200x36 |
|:---|:---|:---|
| **GPU Architecture** | NVIDIA Grace Blackwell Superchip | NVIDIA Grace Blackwell Superchip |
| **GPU Count (within NVLink)** | 72 | 36 |
| **FP8 Compute** | 360 PFLOPS | 180 PFLOPS |
| **HBM3e Memory Total** | 13.4 TB | 6.7 TB |
| **NVLink Bandwidth** | 130 TB/s | 65 TB/s |
| **EFA Network** | 28.8 Tbps (EFAv4) | 14.4 Tbps (EFAv4) |
| **CPU Architecture** | NVIDIA Grace (Arm) | NVIDIA Grace (Arm) |

#### 3.1.5 AWS AI Factories

AWS AI Factories is a service that deploys AWS infrastructure within customer data centers (announced December 2025).

**Key Components:**

| Component | Description |
|:---|:---|
| **AI Accelerators** | NVIDIA GPU (Blackwell B200/GB200, future Vera Rubin) or AWS Trainium (Trainium2/Trainium3) |
| **Network** | AWS high-speed, low-latency network, EC2 UltraClusters support |
| **Storage** | Amazon FSx for Lustre, Amazon S3 Express One Zone (hundreds of GB/s throughput, millions of IOPS) |
| **AI Services** | Amazon Bedrock, Amazon SageMaker AI |
| **Security** | AWS Nitro System (hardware-level isolation, inaccessible to anyone including AWS) |

**Features:**

| Feature | Description |
|:---|:---|
| **Data Sovereignty** | Sensitive data never leaves customer data center |
| **Regulatory Compliance** | Compliant with strict regulatory requirements (government, financial, healthcare, etc.) |
| **Rapid Deployment** | Significantly reduced from years of construction time |
| **Fully Managed** | AWS-operated maintenance and updates |
| **Leverage Existing Investment** | Utilizes customer's data center space, power, and network connections |

#### 3.1.6 AWS GPU Instance List

**High-End (Training/Large-Scale Inference):**

| Instance | GPU | GPU Count | GPU Memory Total | vCPU | System Memory | Network | Release Date | Primary Use |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **p6e-gb300.48xlarge** | GB300 NVL72 | 72 | 20 TB+ | 192 | 2,048 GB | 3,200 Gbps EFA | December 2025 announced | Latest inference/trillion parameter models |
| **p5en.48xlarge** | H200 | 8 | 1,128 GB | 192 | 2,048 GB | 3,200 Gbps EFA | December 2024 GA | Latest LLM training |
| **p5e.48xlarge** | H200 | 8 | 1,128 GB | 192 | 2,048 GB | 3,200 Gbps EFA | September 2024 GA | LLM training/inference |
| **p5.48xlarge** | H100 | 8 | 640 GB | 192 | 2,048 GB | 3,200 Gbps EFA | August 2023 GA | Large-scale AI training |
| **p4de.24xlarge** | A100 80GB | 8 | 640 GB | 96 | 1,152 GB | 400 Gbps EFA | 2022 GA | AI training |
| **p4d.24xlarge** | A100 40GB | 8 | 320 GB | 96 | 1,152 GB | 400 Gbps EFA | November 2020 GA | AI training |

**Mid-Range (Inference/Medium-Scale Training):**

| Instance | GPU | GPU Count | GPU Memory Total | vCPU | System Memory | Network | Release Date | Primary Use |
|:---|:---|:---|:---|:---|:---|:---|:---|:---|
| **g6e.xlarge~48xlarge** | L40S | 1-8 | 48-384 GB | 4-192 | 16-768 GB | Up to 100 Gbps | August 2024 GA | LLM inference/fine-tuning |
| **g6.xlarge~48xlarge** | L4 | 1-8 | 24-192 GB | 4-192 | 16-768 GB | Up to 100 Gbps | April 2024 GA | Inference/video processing |
| **g5.xlarge~48xlarge** | A10G | 1-8 | 24-192 GB | 4-192 | 16-768 GB | Up to 100 Gbps | November 2021 GA | Inference/graphics |

#### 3.1.7 AWS Storage Architecture

**Remote Block Storage (Amazon EBS):**

| Volume Type | API Name | Use Case | Max IOPS/Volume | Max Throughput/Volume | Max Capacity | Latency | Durability |
|:---|:---|:---|:---|:---|:---|:---|:---|
| **io2 Block Express** | io2 | Mission-critical DB (SAP HANA, SQL Server) | 256,000 IOPS | 4,000 MB/s | 64 TiB | < 500μs (avg) | 99.999% |
| **gp3** | gp3 | General purpose (virtual desktops, medium DB) | 80,000 IOPS | 2,000 MB/s | 64 TiB | Single-digit ms | 99.8-99.9% |
| **gp2** | gp2 | General purpose (legacy) | 16,000 IOPS | 250 MB/s | 16 TiB | Single-digit ms | 99.8-99.9% |
| **io1** | io1 | High IOPS (legacy) | 64,000 IOPS | 1,000 MB/s | 16 TiB | Single-digit ms | 99.9% |
| **st1 (HDD)** | st1 | Throughput-oriented (log processing, DWH) | 500 IOPS | 500 MB/s | 16 TiB | - | 99.8-99.9% |
| **sc1 (HDD)** | sc1 | Cold data | 250 IOPS | 250 MB/s | 16 TiB | - | 99.8-99.9% |

**Maximum Performance per Instance:**
- Max IOPS: 260,000 IOPS
- Max Throughput: 12,500 MB/s (12.5 GB/s)

**Local Instance Storage (NVMe SSD):**

| Instance Type | Local Storage | Disk Configuration | Max IOPS | Max Throughput | Use Case |
|:---|:---|:---|:---|:---|:---|
| **i4i.metal** | 30 TB | 8x 3,750 GB NVMe SSD | 2,400,000 IOPS (read) | 16 GB/s | Storage optimized |
| **i3en.metal** | 60 TB | 8x 7,500 GB NVMe SSD | 2,000,000 IOPS (read) | 16 GB/s | High-density storage |
| **d3en.12xlarge** | 336 TB | 24x 14 TB HDD | - | 6.2 GB/s | Large capacity HDD |
| **c5d.24xlarge** | 3.6 TB | 4x 900 GB NVMe SSD | 1,200,000 IOPS | 6.6 GB/s | Compute + local SSD |


### 3.2 Microsoft Azure

#### 3.2.1 Azure Boost

Azure Boost is a hardware offload suite that Microsoft has been providing since 2023.

**Azure Boost/SmartNIC Generation History:**

| Generation | Release Date | Technology | Features |
|:---|:---|:---|:---|
| **1st Generation** | 2015~ | FPGA SmartNIC | Project Catapult, SDN acceleration |
| **2nd Generation** | 2020~ | FPGA + Mellanox NIC | 80G NIC, for HBv4 |
| **Azure Boost** | July 2023 (Preview), November 2023 (GA) | MANA + FPGA | Integrated offload suite |
| **Azure Boost Next Gen** | November 2025 (Preview) | MANA + FPGA + HSM | 1M IOPS, 20GB/s, 400Gbps, RDMA support, ABCD (Confidential Device) |

**Component Details:**

| Category | Component | Release Date | Function Description | Performance Metrics |
|:---|:---|:---|:---|:---|
| **Network** | MANA (Microsoft Azure Network Adapter) | 2023 | Network acceleration, SR-IOV, FPGA-equipped | Up to 200 Gbps |
| **Network** | FPGA SmartNIC | 2015~ | Programmable network processing, Project Catapult | Low latency |
| **Network** | InfiniBand (NVIDIA Quantum-2) | 2020~ | HPC/AI RDMA (ND series) | Up to 3,200 Gbps |
| **Storage** | Azure Boost NVMe Offload | 2023 | Storage I/O processing FPGA offload | Remote: 14 GB/s, 750K IOPS |
| **Storage** | Azure Boost SSD | 2023 | Local SSD access, encryption | 36 GB/s, 6.6M IOPS |
| **Security** | Pluton Security Processor | 2020/2022 | Hardware Root of Trust | - |
| **Security** | Cerberus | 2023 | Azure Boost HW Root of Trust | NIST 800-193 |
| **Security** | Azure Confidential Computing | 2019 (GA) | TEE (Intel SGX/AMD SEV-SNP/Intel TDX) | Memory encryption |
| **Management** | OpenHCL | 2024 (OSS) | Linux/Rust-based paravirtualizer | Improved guest compatibility |

#### 3.2.2 Azure Virtualization Architecture Details

Microsoft Azure employs different virtualization platforms depending on CPU architecture.

**What is Microsoft Hypervisor (MSHV):**

| Item | Description |
|:---|:---|
| **Type** | Type 1 (bare-metal) hypervisor |
| **Supported Architectures** | x86-64, ARM64 |
| **Relationship** | Foundation component of Hyper-V virtualization stack |
| **Linux Support** | mshv_vtl driver (/dev/mshv) enables Linux as root partition |
| **Open Source** | Linux kernel driver, Rust bindings etc. OSS (2020~) |
| **Features** | Nested virtualization, Confidential Computing via AMD SEV-SNP/Intel TDX |

**Virtualization Configuration by CPU Architecture:**

| Item | x86-64 Environment | ARM64 Environment |
|:---|:---|:---|
| **Host OS** | Azure Host OS (minimal Windows-derived OS) | Azure Host OS (Linux/MSHV) |
| **Hypervisor** | Hyper-V (on MSHV) | Microsoft Hypervisor (MSHV) |
| **Paravisor** | OpenHCL (Azure Boost SKU) | OpenHCL (required) |
| **Guest OS** | Windows Server, various Linux | Various Linux, Windows 11 (client) |
| **Nested Virtualization** | ✅ Supported (Dv3/Ev3 etc.) | ❌ Not supported |
| **Confidential VM** | ✅ AMD SEV-SNP, Intel TDX | ✅ Arm CCA (Cobalt 200~) |
| **Primary VM Series** | Dv5, Ev5, NC series etc. | Dpsv5/6, Epsv5/6 (Ampere/Cobalt) |

**OpenHCL Paravisor Role:**

OpenHCL (Open Hardware Compatibility Layer) is a Rust-based paravisor developed by Microsoft, open-sourced in October 2024.

| Function | Description |
|:---|:---|
| **Device Emulation** | Provides virtual devices like vTPM, serial ports |
| **Device Translation** | Bridges guest access to Azure Boost NVMe/MANA |
| **Azure Boost Integration** | Enables 200Gbps network, high-performance storage I/O |
| **Confidential Computing** | Secure service delivery within trust boundary |
| **Guest Compatibility** | Enables latest features on older Windows/Linux kernels |
| **Supported Platforms** | x86-64, ARM64, Intel TDX, AMD SEV-SNP |

#### 3.2.3 Azure Cobalt

**Azure Cobalt 200 (November 2025 announced, 2026 GA planned):**

| Item | Specifications |
|:---|:---|
| **Processor** | Azure Cobalt 200 |
| **Architecture** | Arm Neoverse CSS V3 (Neoverse V3 core) |
| **Manufacturing Process** | TSMC 3nm |
| **Chiplet Configuration** | 2 chiplets (66 cores each) |
| **Core Count** | 132 cores/SoC (up to 264 cores with dual-socket) |
| **L2 Cache** | 3MB/core (396MB total) |
| **L3 Cache** | 192MB (system cache) |
| **Memory Channels** | 12 channels DDR5/socket |
| **Dedicated Accelerators** | Data movement accelerator, encryption/compression accelerator |
| **Security** | Default memory encryption, Arm CCA (Confidential Compute Architecture) |
| **Performance vs Cobalt 100** | 50% improvement |

**Azure Cobalt 100 (November 2024 GA):**

| Item | Specifications |
|:---|:---|
| **Processor** | Azure Cobalt 100 |
| **Architecture** | Arm Neoverse N2 |
| **Core Count** | 128 cores |
| **Frequency** | 3.4 GHz |
| **Memory** | Up to 672 GiB (Epsv6 instances) |
| **Max vCPU** | 96 vCPU |
| **Supported Instances** | Dpsv6, Dplsv6, Epsv6 |
| **Deployment Regions** | 32 regions |
| **Price-Performance vs x86** | Up to 99% improvement |


### 3.3 Google Cloud

#### 3.3.1 Google Cloud Titanium

Google Cloud Titanium is a hardware security platform employing a 2-tier offload architecture.

**Titanium Hardware Security Architecture Components:**

| Component | Function | Security Benefits |
|:---|:---|:---|
| **Caliptra RTM (Root of Trust for Measurement)** | Silicon-level RoT on SoC like CPU/GPU/TPU | Cryptographic services, attestation, unique ID, physical supply chain attack mitigation |
| **Titan Chip RoT** | Placed between platform boot flash and BMC/PCH/CPU | Physical tamper protection, strong ID establishment, code authentication & revocation |
| **Titanium Offload Processor (TOP)** | Cryptographic control for data at rest and in transit | Data confidentiality/integrity protection, crypto offload |
| **Custom Motherboard** | Custom design, unnecessary connectors removed | DoS attack resistance, physical attack protection, full system recovery support |
| **Confidential Computing Enclave** | TEE (Trusted Execution Environment) provision | Isolation from admin privileges, tenant isolation, DRAM encryption |

**Titanium/IPU Generation History:**

| Generation | Release Date | Technology | Supported Instances | Features |
|:---|:---|:---|:---|:---|
| **Titan** | 2017 | Security chip | All instances | Hardware Root of Trust |
| **Intel IPU (E2000/Mount Evans)** | October 2022 (Preview), May 2023 (GA) | Intel co-developed ASIC | C3 | 200Gbps, programmable packet processing |
| **Titanium** | August 2023 | 2-tier offload architecture | C3, N2+ | IPU + TOP (scale-out offload) |
| **Titanium (5th Gen)** | April 2024 | 5th Gen Intel Xeon integration | C4, N4 | Latest processor integration |
| **Titanium SSD** | January 2025 (GA) | Custom-designed SSD | C4A | Axion integration, storage offload optimization |

#### 3.3.2 Google Cloud Axion

**Google Axion C4A (October 2024 GA):**

| Item | Specifications |
|:---|:---|
| **Processor** | Google Axion (1st generation) |
| **Architecture** | Arm Neoverse V2 (ARMv9.0-A) |
| **Manufacturing Process** | TSMC 3nm (reported) |
| **Core Count** | Up to 72 vCPU (VM), 96 vCPU (metal) |
| **L2 Cache** | 2MB/core (private) |
| **L3 Cache** | 80MB |
| **Memory** | DDR5-5600, up to 576 GB (VM), 768 GB (metal) |
| **Memory Access** | UMA (Uniform Memory Access) |
| **Local Storage** | Up to 6 TiB Titanium SSD |
| **Network** | Up to 50 Gbps standard, 100 Gbps Tier_1 |
| **Price-Performance vs x86** | Up to 65% improvement |
| **Energy Efficiency vs x86** | Up to 60% improvement |

**Google Axion N4A (November 2025 Preview):**

| Item | Specifications |
|:---|:---|
| **Processor** | Google Axion (2nd generation) |
| **Architecture** | Arm Neoverse N3 |
| **Core Count** | Up to 64 vCPU |
| **Memory** | DDR5, up to 512 GB |
| **Memory Access** | UMA (Uniform Memory Access) |
| **Network** | Up to 50 Gbps (gVNIC required) |
| **Use Case** | Price-performance focused, scale-out workloads |
| **Price-Performance vs x86** | Compute 105%, Web server 90%, Java 85%, DB 20% improvement |

#### 3.3.3 Google Cloud TPU

**TPU v7 Ironwood (2025 GA) Details:**

| Item | Specifications | vs Previous Gen (Trillium) |
|:---|:---|:---|
| **Manufacturing Process** | TSMC N3P | Evolved from N5 |
| **TensorCore Count** | 2 cores/chip | Changed from 1 core/chip |
| **SparseCore** | Included (for ultra-large embedding models) | Enhanced |
| **Peak Performance (FP8)** | 4,614 TFLOPS | 5x improvement |
| **Peak Performance (BF16)** | 2,307 TFLOPS | 5x improvement |
| **HBM Memory** | 192 GB HBM3e (8 stacks) | 6x increase (32GB→192GB) |
| **HBM Bandwidth** | 7.37 TB/s | 4.5x improvement |
| **ICI Bandwidth** | 1.2 TB/s (bidirectional, 4 links) | 1.5x improvement |
| **TDP** | ~1kW (liquid cooling required) | ~5x increase |
| **Power Efficiency (perf/watt)** | 2x improvement (vs Trillium) | 30x improvement (vs v2) |

**Ironwood Pod Configuration:**

| Configuration | Chip Count | Performance (FP8) | Performance (BF16) | Use Case |
|:---|:---|:---|:---|:---|
| **Minimum Pod** | 256 | 1.18 ExaFLOPS | 0.59 ExaFLOPS | Medium-scale models |
| **Maximum Pod (Superpod)** | 9,216 | 42.52 ExaFLOPS | 21.26 ExaFLOPS | Ultra-large models |
| **Theoretical Max (Jupiter network)** | ~400,000 | ~1.8 ZettaFLOPS | ~0.9 ZettaFLOPS | 43 Pods connected |

**Ironwood Technical Features:**
- **Chiplet Architecture**: Composed of 2 independent chiplets
- **Dual TPU Device**: Transition from traditional single logical core to 2-device model
- **Liquid Cooling Required**: Can sustain 2x performance of standard air cooling
- **OCS (Optical Circuit Switching) Support**: 100,000 chip connection within data center
- **JAX Framework Support**: TensorFlow not supported (JAX recommended)

**Major Customers & Use Cases:**
- Anthropic: Training and inference for Claude models on up to 1 million TPUs
- Google Gemini: Internal model development
- vLLM/SGLang: Beta support started on TPU v5p/v6e


### 3.4 Oracle Cloud Infrastructure (OCI)

#### 3.4.1 OCI Virtualization Architecture

OCI is the industry pioneer in Off-box Network Virtualization, providing this architecture since 2016.

**Component Details:**

| Category | Component | Release Date | Function Description | Performance Metrics |
|:---|:---|:---|:---|:---|
| **Network** | Off-box Network Virtualization | 2016 | Network virtualization completely separated from host | 100% physical cores to customers |
| **Network** | AMD Pensando DSC SmartNIC | 2016~ | P4-programmable network processing, NVMe over TCP offload | Low latency |
| **Network** | NVIDIA BlueField-3 DPU | 2024~ | GPUDirect RDMA support (GPU instances) | 3,200 Gbps RoCE |
| **Network** | Oracle Acceleron | October 2024~ | High-performance network fabric | 2x throughput/IOPS vs previous |
| **Network** | Zettascale10 Network | October 2025 (announced), 2026 H2 (GA) | Up to 800,000 GPU connection | Multi-gigawatt scale |
| **Storage** | OCI Block Volumes | 2016~ | Ultra High Performance tier | 300,000 IOPS, 2,680 MB/s |
| **Security** | Hardware Root-of-Trust | 2016~ | Hardware-based security | Firmware complete wipe between tenants |
| **Security** | Zero Trust Packet Routing (ZPR) | 2023 (initial), October 2024 (enhanced) | Host-level zero trust, least privilege | Enforced from first packet |
| **Management** | Oracle Linux KVM | 2016~ | UEK kernel-based hypervisor | - |
| **Management** | Off-box Virtualization | 2016 | Network virtualization completely separated from host | 100% physical cores provided |

**Oracle Cloud Infrastructure Virtualization Stack (Off-box Virtualization):**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Guest OS (Linux/Windows)                      │
│              ┌─────────────────────────────────────┐            │
│              │        Guest Drivers                 │            │
│              │   VirtIO-Net / NVMe / iSCSI         │            │
│              │   SR-IOV VF (high-performance config)│            │
│              └─────────────────────────────────────┘            │
├─────────────────────────────────────────────────────────────────┤
│              Oracle Linux KVM Hypervisor                         │
│           (UEK kernel-based, CPU/memory allocation only)         │
│              No network virtualization (completely Off-box)      │
├─────────────────────────────────────────────────────────────────┤
│           Host CPU (AMD EPYC / Intel Xeon / Ampere Altra)       │
│           1 OCPU = 1 physical core (no oversubscription)        │
└───────────────────────────────────────────────┬─────────────────┘
              Hardware Isolation │ PCIe connection
┌───────────────────────────────────────────────┴─────────────────┐
│                  SmartNIC / Converged NIC                        │
│  ┌─────────────────────────┐  ┌───────────────────────────┐    │
│  │  AMD Pensando DPU       │  │   NVIDIA BlueField-3 DPU   │    │
│  │  (general instances)    │  │   (GPU instances)          │    │
│  ├─────────────────────────┤  ├───────────────────────────┤    │
│  │ • Network virtualization│  │ • GPUDirect RDMA          │    │
│  │ • NVMe over TCP offload │  │ • AI/ML workload optimized│    │
│  │ • Line-rate encryption  │  │                           │    │
│  │ • Zero Trust Packet     │  │                           │    │
│  │   Routing (ZPR)         │  │                           │    │
│  └─────────────────────────┘  └───────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │            Hardware Root-of-Trust                        │    │
│  │   (Complete firmware wipe, complete tenant isolation)    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ Physical Network (ACL enforced)
┌─────────────────────────────────────────────────────────────────┐
│                   OCI Physical Network Architecture              │
│  ┌─────────────────────────┐  ┌───────────────────────────┐    │
│  │   Top-of-Rack Switch    │  │   Control Plane           │    │
│  │   (ACL enforced, isolated)│ │   (ILOM-only communication)│   │
│  └─────────────────────────┘  └───────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │    Oracle Acceleron RoCE Network Fabric                  │    │
│  │    (Dedicated fabric, multi-planar, ultra-low latency)   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

**Architecture Characteristics:**
- **Offload Method**: Off-box (completely host-external separation) - industry first (2016~)
- **Hypervisor**: Oracle Linux KVM (UEK kernel-based)
- **Network Virtualization**: Completely executed on SmartNIC (not included in hypervisor at all)
- **Security Model**: Network reconfiguration impossible even if hypervisor is compromised
- **Physical Core Delivery**: 1 OCPU = 1 physical core (no oversubscription)

**Gen1 Cloud vs OCI Gen2 Comparison:**

| Item | Gen1 Cloud (Traditional) | OCI Gen2 (Off-box) |
|:---|:---|:---|
| **Network Virtualization** | Within hypervisor | SmartNIC (host-external) |
| **When Hypervisor Compromised** | Network reconfigurable (lateral movement risk) | Network change impossible (lateral movement prevention) |
| **CPU Overhead** | CPU consumed by network processing | 100% delivered to customer workloads |
| **Noisy Neighbor** | Possible | Eliminated by resource isolation |

**Important Limitations:**
- **Nested Virtualization Support**: x86-64 only. KVM in VM not supported on ARM64 (Ampere)
- **Bare Metal Instances**: Network virtualization on SmartNIC, seamless patching support (Converged NIC)
- **Confidential Computing**: AMD SEV support (E5.DenseIO.128 shape etc.)

**OCI Differentiators:**
- Industry's first Off-box Network Virtualization (2016~)
- 1 OCPU = 1 physical core (no hyperthreading, no oversubscription)
- Oracle Acceleron (October 2024) delivers 2x throughput/IOPS improvement at no additional cost
- BYO hypervisor support (Oracle VM, Hyper-V, KVM, VMware)
- OCI Zettascale10 with up to 800,000 GPUs (industry's largest scale, OpenAI Stargate foundation)
- NVIDIA GB200 NVL72 support (September 2025~), AMD Instinct MI355X/MI450X support

#### 3.4.2 OCI Ampere Arm CPU Details

Oracle Cloud provides industry-leading ARM Compute through strategic partnership with Ampere.

**OCI Ampere A1 Compute (May 2021 GA):**

| Item | Specifications |
|:---|:---|
| **Processor** | Ampere Altra Q80-30 |
| **Architecture** | Arm Neoverse N1 |
| **Max Core Count** | 160 cores (bare metal: 2×80 cores), VM: up to 80 cores |
| **Frequency** | Up to 3.0 GHz (constant across all cores) |
| **L1 Cache** | 64KB I-cache + 64KB D-cache / core |
| **L2 Cache** | 1MB / core |
| **Memory** | Up to 1TB (bare metal) |
| **Supported Shapes** | BM.Standard.A1.160 (bare metal), VM.Standard.A1.Flex (VM) |
| **Price** | $0.01/OCPU/hour (industry's first "penny core") |
| **Features** | Single-thread core design for predictable performance, no noisy neighbor issues |

**OCI Ampere A2 Compute (August 2024 GA):**

| Item | Specifications |
|:---|:---|
| **Processor** | AmpereOne A160-30 |
| **Architecture** | Armv8.6+ (Ampere custom design) |
| **Max Core Count** | 156 cores (78 OCPU, 1 OCPU = 2 cores) |
| **Frequency** | Up to 3.0 GHz |
| **L2 Cache** | 2MB / core (2x A1) |
| **Memory** | DDR5, up to 946GB (25% bandwidth improvement vs A1) |
| **Network** | Up to 78 Gbps, up to 24 VNIC |
| **Supported Shapes** | VM.Standard.A2.Flex |
| **Price** | $0.014/OCPU/hour, $0.002/GB/hour |
| **Performance vs A1** | Average 28% (Cassandra, PostgreSQL, MySQL etc.) |
| **Price-Performance vs x86** | Up to 2x |

**Oracle Cloud ARM Differentiators:**
- **Industry-lowest pricing**: A1 at $0.01/OCPU/hour (penny core), A2 also competitively priced
- **Predictable performance**: Single-thread core design eliminates noisy neighbor issues
- **Linear scaling**: Performance scales proportionally with core additions
- **Always Free Tier**: 4 OCPU + 24GB RAM free on A1 (3,000 OCPU hours/month)
- **100+ OCI services support**: Running on Oracle Database, HeatWave MySQL, Fusion Apps etc.
- **Red Bull Racing adoption**: 25% speed improvement for Monte Carlo simulations on Kubernetes

#### 3.4.3 OCI Zettascale (Large-Scale AI Infrastructure)

OCI announced Zettascale AI supercomputer in 2024 and Zettascale10 in 2025, providing the industry's largest GPU cluster.

**OCI Supercluster Generations:**

| Generation | Release Date | Max GPU Count | Network | Features |
|:---|:---|:---|:---|:---|
| **OCI Supercluster** | 2023~ | 16,384 H100 | RDMA | Initial large-scale GPU cluster |
| **OCI Zettascale** | September 2024 | 131,072 GPU | Acceleron RoCE | 2.4 ZettaFLOPS |
| **OCI Zettascale10** | October 2025 (announced), 2026 H2 (GA planned) | 800,000 GPU | Acceleron RoCE v2 | 16 ZettaFLOPS, multi-gigawatt scale, OpenAI Stargate foundation |

**GPU/AI Accelerator Support:**

| Configuration | Max GPU Count | Performance | Network Bandwidth |
|:---|:---|:---|:---|
| NVIDIA GB200 NVL72 | 800,000 (Zettascale10) | 16 ZettaFLOPS | Acceleron RoCE v2 |
| NVIDIA Blackwell B200 | 131,072 | 2.4 ZettaFLOPS | - |
| NVIDIA GB200 NVL72 | 131,072 | 2.4 ZettaFLOPS | 129.6 TB/s (NVLink) |
| NVIDIA H200 | 65,536 | 260 ExaFLOPS | 52 Pb/s |
| NVIDIA H100 | 16,384 | 65 ExaFLOPS | 13 Pb/s |
| NVIDIA A100 | 32,768 | - | - |
| AMD MI300X | 16,384 | - | 192GB HBM3 memory |
| AMD MI355X | 131,072 (GA) | - | 288GB HBM3E memory |

**OCI Zettascale10 Features (October 2025 announced, 2026 H2 GA planned):**
- Up to 800,000 NVIDIA GPUs connected in a single cluster
- Ultra-low latency via Oracle Acceleron RoCE v2 networking
- Multi-gigawatt scale spanning multiple data centers
- Adopted as foundation for OpenAI Stargate project (Abilene, Texas)
- High availability and automatic failure avoidance via independent network planes

---

## 4. Reference Information and Supplementary Materials

This section organizes detailed technical information, migration guides, management Linux distributions, and reference links for each cloud provider.

### 4.1 Hyperscaler Management Linux Distributions

Each hyperscaler develops and maintains proprietary Linux distributions to support virtualization environments and container platforms based on Linux KVM. This section organizes the open source publication status, information disclosure sites, and issue management systems for each provider's distributions.

#### 4.1.1 Comparison Table: Management Linux Distributions

| Item | Amazon Linux 2023 | AWS Bottlerocket | Azure Linux 3.0 | Oracle Linux 9/10 | Google Cloud COS |
|:---|:---|:---|:---|:---|:---|
| **Provider** | AWS | AWS | Microsoft | Oracle | Google |
| **Upstream** | Fedora / CentOS Stream | Custom design | Custom (Photon OS reference) | RHEL compatible | Chromium OS |
| **Latest Version** | 2023.9.20251117 | 1.51.0 (December 2025) | 3.0 (August 2024 GA) | OL 10.1 (2025 GA) | LTS 121 (milestone) |
| **Kernel** | 6.1 LTS / 6.12 LTS | 6.1 LTS | 6.6 / 6.12 LTS | UEK 8 (6.12 based) / RHCK | 5.15 / 6.1 LTS |
| **Support Period** | Until June 30, 2029 (5 years) | Linked to orchestrator version | 3 years (2027 summer EOL planned) | Premier Support + Extended | LTS: 2 years |
| **Supported Architectures** | x86-64, ARM64 | x86-64, ARM64 | x86-64, ARM64 | x86-64, ARM64 (UEK only) | x86-64, ARM64 |
| **Package Manager** | dnf | API config-based | tdnf / dnf | dnf | None (via containers) |
| **Primary Use** | EC2, ECS/EKS | EKS/ECS container host | AKS, WSL2, Azure IoT Edge | OCI, on-premises, Exadata | GKE, Compute Engine |
| **License** | Free | Apache 2.0 + MIT (OSS) | MIT License (OSS) | Free (support is paid) | Apache 2.0 (OSS) |

#### 4.1.2 Open Source Publication Status Comparison

| Item | Amazon Linux 2023 | AWS Bottlerocket | Azure Linux | Oracle Linux UEK | Google Cloud COS |
|:---|:---|:---|:---|:---|:---|
| **Open Source** | Partial | ✅ Fully OSS | ✅ Fully OSS | ✅ Kernel only OSS | ✅ Fully OSS |
| **License** | Proprietary (free) | Apache 2.0 / MIT | MIT License | UPL 1.0 / GPL | Apache 2.0 |
| **Source Code Repository** | GitHub (documentation-focused) | GitHub (full source) | GitHub (full source) | GitHub (kernel only) | cos.googlesource.com |
| **Issue Management** | ✅ GitHub Issues | ✅ GitHub Issues | ✅ GitHub Issues | Oracle Developer Community | ❌ No external Issues |
| **External PR Acceptance** | ❌ | ✅ | ✅ | ❌ (upstream commit pointers welcome) | ❌ |
| **Public Roadmap** | ❌ | ✅ GitHub Roadmap | ❌ | ❌ | ❌ |
| **Community Calls** | ❌ | ✅ Meetup | ✅ Regular | ❌ | ❌ |

### 4.2 BYO Hypervisor Support Details

#### 4.2.1 Hypervisor CPU Architecture Dependencies

Major enterprise hypervisors depend on specific CPU architectures due to their architectural constraints.

| Hypervisor | x86-64 | ARM64 | Notes |
|:---|:---|:---|:---|
| **VMware ESXi** | ✅ | ❌ | x86-64 only (ARM64 version future plan only) |
| **Microsoft Hyper-V** | ✅ | ❌ | Windows Server dependent, x86-64 only |
| **Nutanix AHV** | ✅ | ❌ | KVM-based but x86-64 only certified |
| **Oracle VM (OLVM)** | ✅ | ❌ | KVM + oVirt, x86-64 only |
| **KVM (Linux Kernel-based)** | ✅ | ✅ | Both architectures supported |
| **Xen** | ✅ | ✅ | Both architectures supported (ARM has limitations) |

**Important:** VMware ESXi, Microsoft Hyper-V, and Nutanix AHV are all **x86-64 only**. To run BYO hypervisor on ARM64 environments (Graviton, Cobalt, Axion, Ampere), you are limited to **KVM or Xen**.

#### 4.2.2 BYO Hypervisor Support by Cloud Provider

| Provider | x86-64 BYO Hypervisor | ARM64 BYO Hypervisor | Managed VMware | Nutanix NC2 |
|:---|:---|:---|:---|:---|
| **AWS** | VMware (EVS), Hyper-V, KVM, Xen | KVM only | Amazon EVS | ✅ |
| **Azure** | Hyper-V (nested), KVM | KVM only | AVS | ✅ |
| **Google Cloud** | VMware (GCVE), KVM, Xen | KVM/Xen only | GCVE | ✅ |
| **OCI** | Oracle VM, Hyper-V, KVM, VMware | Oracle Linux KVM only | OCVS | ❌ |

### 4.3 Guest OS Driver Support Version Details

#### 4.3.1 AWS ENA/NVMe Driver Supported OS

**Linux Supported Versions:**

| Distribution | Minimum Kernel Version | Recommended ENA Driver | Notes |
|:---|:---|:---|:---|
| **Linux Upstream** | Kernel 5.9+ | 2.2.9g+ | Required for Nitro v4+ |
| **Amazon Linux 2023** | Default support | Kernel built-in | Optimized for Nitro v4/v5 |
| **Amazon Linux 2** | Kernel 4.14.186+ | 2.2.9g+ | - |
| **RHEL 8.4+** | Kernel 4.18.0-305+ | 2.2.9g+ | NVMe support from RHEL 7.4+ |
| **RHEL 6** | - | - | **NVMe not supported** (upgrade to RHEL 7.4+ required) |
| **SUSE SLES 15 SP2+** | Kernel 5.3.18-24.15.1+ | 2.2.9g+ | - |
| **Ubuntu 20.04** | Kernel 5.4.0-1025-aws+ | 2.2.9g+ | linux-aws package recommended |
| **Debian 11 (Bullseye)** | Kernel 5.10.0+ | 2.2.9g+ | - |
| **FreeBSD** | - | 2.3.1+ | Versions below 2.3.1 fail to connect |

**ENA Driver Version Restrictions (Important):**

| Nitro Version | Linux ENA Minimum Version | Notes |
|:---|:---|:---|
| **Nitro v5+** | 2.2.9g+ (**required**) | ENI connection fails below this version |
| **Nitro v4** | 2.2.9g+ (recommended) | Older versions may have performance degradation |
| **Nitro v2/v3** | 1.2.0+ | Connection fails below 1.2.0 |

**Windows Supported Versions:**

| Windows Server Version | ENA Support | NVMe Support | AWS PV Support | Notes |
|:---|:---|:---|:---|:---|
| **Windows Server 2025** | ✅ | ✅ | - | Included in latest AMI |
| **Windows Server 2022** | ✅ | ✅ | ✅ | EC2Launch v2 support |
| **Windows Server 2019** | ✅ | ✅ | ✅ | EC2Launch v1 support |
| **Windows Server 2016** | ✅ | ✅ | ✅ | SCSI persistent reservation support (NVMe 1.5.0+) |
| **Windows Server 2012 R2** | ✅ | ✅ | ✅ | EC2Config support |
| **Windows Server 2008 R2** | ✅ (limited) | ❌ | ✅ (8.3.4 or earlier) | **Nitro not recommended** |

### 4.4 Cross-Cloud VM Migration Guide

When migrating VMs between different clouds, appropriate drivers must be installed in the guest OS.

#### 4.4.1 Required Drivers for Linux Migration

| Source → Target | Required Drivers to Add | initramfs Update |
|:---|:---|:---|
| VMware → AWS | `ena`, `nvme` | Required |
| VMware → Azure | `hv_vmbus`, `hv_storvsc`, `hv_netvsc` | Required |
| VMware → GCP | `virtio_*` or `gve`, `nvme` | Required |
| VMware → OCI | `virtio_*` | Required |
| AWS → Azure | `hv_vmbus`, `hv_storvsc`, `hv_netvsc` | Required |
| Azure → AWS | `ena`, `nvme` | Required |

#### 4.4.2 Required Drivers for Windows Migration

| Source → Target | Required Drivers to Add | Notes |
|:---|:---|:---|
| VMware → AWS | AWS PV Drivers, ENA, AWS NVMe | AWSSupport-UpgradeWindowsAWSDrivers recommended |
| VMware → Azure | Hyper-V Integration Services (OS standard) | Supported by Windows standard |
| VMware → GCP | VirtIO Drivers (netkvm, vioscsi) or gVNIC | Google-provided drivers |
| VMware → OCI | Oracle VirtIO Drivers | Obtain from Oracle Software Delivery Cloud |
| Hyper-V → AWS | ENA, AWS NVMe | Add ENA/NVMe |
| Hyper-V → OCI | Oracle VirtIO Drivers | Add VirtIO |

#### 4.4.3 initramfs/initrd Update Commands (Linux)

**RHEL/CentOS/Oracle Linux:**
```bash
$ echo 'add_drivers+=" hv_vmbus hv_netvsc hv_storvsc "' >> /etc/dracut.conf.d/hyperv.conf
$ dracut -f -v
```

**Ubuntu/Debian:**
```bash
$ echo "hv_vmbus" >> /etc/initramfs-tools/modules
$ echo "hv_netvsc" >> /etc/initramfs-tools/modules
$ echo "hv_storvsc" >> /etc/initramfs-tools/modules
$ update-initramfs -u
```

**SUSE:**
```bash
$ echo 'force_drivers+=" hv_vmbus hv_netvsc hv_storvsc "' >> /etc/dracut.conf.d/hyperv.conf
$ dracut -f
```

---

### 4.5 References & Links

#### 4.5.1 Amazon Web Services (AWS)

**Official Documentation & Announcements:**

*Infrastructure Foundation:*
- AWS Nitro System: https://aws.amazon.com/ec2/nitro/
- AWS Graviton Processors: https://aws.amazon.com/ec2/graviton/
- AWS Graviton5 Announcement (December 2025): https://www.aboutamazon.com/news/aws/aws-graviton-5-cpu-amazon-ec2
- Amazon EBS: https://aws.amazon.com/ebs/
- EC2 X8g Graviton4 Instances: https://aws.amazon.com/blogs/aws/now-available-graviton4-powered-memory-optimized-amazon-ec2-x8g-instances/

*Nitro System Architecture (Virtualization Stack):*
- The Security Design of the AWS Nitro System (AWS Whitepaper): https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/security-design-of-aws-nitro-system.html
- Nitro System Component Details: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-components-of-the-nitro-system.html
- Nitro System Evolution History: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-nitro-system-journey.html
- Reinventing virtualization with the AWS Nitro System (Werner Vogels): https://www.allthingsdistributed.com/2020/09/reinventing-virtualization-with-nitro.html
- Nitro System Supported Instance List: https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-nitro-instances.html

*EC2 UltraClusters & UltraServers:*
- Amazon EC2 UltraClusters Overview: https://aws.amazon.com/ec2/ultraclusters/
- Amazon EC2 UltraServers Overview: https://aws.amazon.com/ec2/ultraservers/
- EC2 P6e-GB200 UltraServers Announcement: https://aws.amazon.com/blogs/aws/new-amazon-ec2-p6e-gb200-ultraservers-powered-by-nvidia-grace-blackwell-gpus-for-the-highest-ai-performance/
- EC2 P6 Instance Types: https://aws.amazon.com/ec2/instance-types/p6/
- EC2 Trn2 Instance Types: https://aws.amazon.com/ec2/instance-types/trn2/
- EC2 Trn3 UltraServers: https://aws.amazon.com/ec2/instance-types/trn3/

*Amazon Elastic VMware Service (EVS):*
- Amazon EVS Overview: https://aws.amazon.com/evs/
- Amazon EVS GA Announcement (August 2025): https://aws.amazon.com/jp/blogs/news/run-vmware-your-way-amazon-elastic-vmware-service-is-now-generally-available/
- Amazon EVS Technical Documentation: https://docs.aws.amazon.com/evs/latest/userguide/getting-started.html
- AWS News Blog - EVS Announcement: https://aws.amazon.com/blogs/aws/introducing-amazon-elastic-vmware-service-for-running-vmware-cloud-foundation-on-aws

*AWS Trainium:*
- AWS Trainium Chip Overview: https://aws.amazon.com/ai/machine-learning/trainium/
- AWS Trainium3 UltraServers Announcement: https://www.aboutamazon.com/news/aws/trainium-3-ultraserver-faster-ai-training-lower-cost

*AWS AI Factories:*
- AWS AI Factories Overview: https://aws.amazon.com/about-aws/global-infrastructure/ai-factories/
- AWS AI Factories Announcement: https://www.aboutamazon.com/news/aws/aws-data-centers-ai-factories

#### 4.5.2 Microsoft Azure

**Official Documentation & Announcements:**

*Infrastructure Foundation:*
- Azure Boost: https://techcommunity.microsoft.com/blog/azureinfrastructureblog/introducing-microsoft-azure-boost-preview/3876742
- Azure Cobalt 200 Announcement (November 2025): https://techcommunity.microsoft.com/blog/AzureInfrastructureBlog/announcing-cobalt-200-azure%E2%80%99s-next-cloud-native-cpu/4469807
- Azure Cobalt Processor Overview: https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/cobalt-overview
- Azure Managed Disks: https://learn.microsoft.com/en-us/azure/virtual-machines/managed-disks-overview

*Virtualization Architecture (OpenHCL/MSHV):*
- OpenHCL (Open Source Paravisor): https://github.com/microsoft/openvmm/tree/main/openhcl
- OpenVMM (Rust-based Reference Monitor): https://github.com/microsoft/openvmm
- OpenHCL: Evolving Azure's virtualization model: https://techcommunity.microsoft.com/blog/windowsosplatform/openhcl-evolving-azure%E2%80%99s-virtualization-model/4248345
- Azure Boost DPU Announcement (Ignite 2024): https://techcommunity.microsoft.com/blog/azureinfrastructureblog/enhancing-infrastructure-efficiency-with-azure-boost-dpu/4298901
- Nested Virtualization: https://learn.microsoft.com/en-us/azure/virtual-machines/windows/nested-virtualization

#### 4.5.3 Google Cloud

**Official Documentation & Announcements:**

*Titanium & Security:*
- Google Cloud Titanium: https://cloud.google.com/titanium
- Titanium Hardware Security Architecture: https://cloud.google.com/docs/security/titanium-hardware-security-architecture
- Titan Security Chip: https://cloud.google.com/docs/security/titan-hardware-chip
- Confidential Computing: https://cloud.google.com/security/products/confidential-computing

*TPU (Tensor Processing Unit):*
- TPU v7 Ironwood Official Documentation: https://cloud.google.com/tpu/docs/tpu7x
- TPU v6e Trillium Official Documentation: https://cloud.google.com/tpu/docs/v6e
- TPU Overview: https://cloud.google.com/tpu/docs/intro-to-tpu
- Ironwood Announcement Blog (April 2025): https://blog.google/products/google-cloud/ironwood-tpu-age-of-inference/
- TPU Ironwood & Axion Announcement: https://cloud.google.com/blog/products/compute/ironwood-tpus-and-new-axion-based-vms-for-your-ai-workloads

*Axion & Compute:*
- Google Axion Processors: https://cloud.google.com/products/axion
- Axion C4A GA Announcement (January 2025): https://cloud.google.com/blog/products/compute/first-google-axion-processor-c4a-now-ga-with-titanium-ssd
- Axion N4A Preview Announcement (November 2025): https://cloud.google.com/blog/products/compute/axion-based-n4a-vms-now-in-preview
- Axion C4A-metal Announcement (November 2025): https://cloud.google.com/blog/products/compute/new-axion-c4a-metal-offers-bare-metal-performance-on-arm
- Arm VMs on Compute: https://cloud.google.com/compute/docs/instances/arm-on-compute

**Open Source Projects (Titanium-related):**
- Caliptra (Silicon-level RoT): https://www.opencompute.org/documents/caliptra-silicon-rot-services-09012022-pdf
- OpenTitan (Chip RoT): https://opentitan.org/
- BoringSSL (Cryptography Library): https://boringssl.googlesource.com/boringssl
- PSP Security Protocol: https://cloud.google.com/blog/products/identity-security/announcing-psp-security-protocol-is-now-open-source
- Syzkaller (Kernel Fuzzing): https://github.com/google/syzkaller/tree/master

#### 4.5.4 Oracle Cloud Infrastructure (OCI)

**Official Documentation & Announcements:**

*Infrastructure Foundation:*
- OCI Security Architecture: https://www.oracle.com/security/cloud-security/
- Oracle Acceleron: https://www.oracle.com/cloud/networking/acceleron/
- Oracle Acceleron Announcement (October 2025): https://www.oracle.com/news/announcement/ai-world-oracle-introduces-new-cloud-networking-capabilities-for-any-workload-2025-10-14/
- OCI Zettascale10 (October 2025 announcement): https://www.oracle.com/news/announcement/ai-world-oracle-unveils-next-generation-oci-zettascale10-cluster-for-ai-2025-10-14/
- OCI GPU Compute: https://www.oracle.com/cloud/compute/gpu/
- OCI Block Volume: https://docs.oracle.com/en-us/iaas/Content/Block/Concepts/blockvolumeperformance.htm
- OCI Ampere Compute: https://www.oracle.com/cloud/compute/arm/
- OCI DenseIO Compute: https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm

*Virtualization Architecture (Off-box Virtualization):*
- OCI Isolated Network Virtualization: https://www.oracle.com/security/cloud-security/isolated-network-virtualization/
- OCI Security Architecture (Technical Brief): https://www.oracle.com/a/ocom/docs/oracle-cloud-infrastructure-security-architecture.pdf
- OCI Bare Metal Servers: https://www.oracle.com/cloud/compute/bare-metal/
- Zero Trust Packet Routing (ZPR): https://docs.oracle.com/en-us/iaas/Content/zero-trust-packet-routing/overview.htm

#### 4.5.5 Industry Analysis & Comparison Information

**Cloud Infrastructure Comparison:**
- Nevsemi - Google TPU Ironwood Explanation: https://www.nevsemi.com/blog/google-tpu-chip-ironwood-technology-explained
- TrendForce - Google Axion TSMC 3nm Report: https://www.trendforce.com/news/2025/10/21/news-googles-axion-cpu-reportedly-built-on-tsmcs-3nm-set-to-drive-foundrys-data-center-revenue-growth/

**Security-related:**
- CISA - Software Supply Chain Security: https://www.cisa.gov/sites/default/files/publications/defending_against_software_supply_chain_attacks_508.pdf
- NIST FIPS 140-3: https://csrc.nist.gov/projects/cryptographic-module-validation-program/

---

*This document is updated based on publicly available information as of December 2025. Specifications and pricing for each cloud provider are subject to change. Please refer to each provider's official documentation for the latest information.*
