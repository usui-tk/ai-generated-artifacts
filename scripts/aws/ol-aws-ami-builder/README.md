# Oracle Linux AWS AMI Builder

English | [日本語](./README.ja.md)

> 📂 Part of [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) → [`scripts/aws/ol-aws-ami-builder/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/aws/ol-aws-ami-builder)
> ⚠️ **AI-generated content** — review the source before executing. See the [scripts directory policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md) for the full disclaimer.
> 📐 **Developer specification**: [SPEC.md](./SPEC.md) ([日本語](./SPEC.ja.md)) — phase contract, log conventions, env property keys, and the historical pitfalls already accounted for in the current implementation.

A set of wrapper scripts that build AWS AMIs for **Oracle Linux 8, 9, or 10** (x86_64) using the official Oracle [`oracle-linux-image-tools`](https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools) project.

Experimental support is also provided for **Oracle Linux 7** (x86_64) — see the OL7 note at the end of [section 1](#1-repository-layout) and the dedicated warnings in [section 10](#10-known-limitations-and-caveats).

Even more experimental support is provided for **Oracle Linux 6** (x86_64). The upstream tooling does not ship a `distr/ol6-slim/` directory at all, so this wrapper synthesizes one at runtime in addition to applying two `sed` patches. See [section 9.7](#97-oracle-linux-6-support-experimental) for the mechanism and [section 10](#10-known-limitations-and-caveats) item 8 for the caveats.

Created in response to the discontinuation of Oracle's official AMI offerings (owner ID `131827586825`) on the AWS Marketplace, with the goal of establishing an independent build and operations workflow for Oracle Linux AMIs.

> **Aligned with the AWS feature released in February 2026**
> Now that AWS supports nested virtualization on C8i / M8i / R8i instances, this guide **recommends building on M8i-class instances as the primary path**. This removes the need for bare-metal instances (`.metal`) and brings the cost down to **approximately 1/15 of the previous approach**.

---

## ⚠️ Disclaimer (read before running)

**USE AT YOUR OWN RISK.** These scripts are provided "AS IS" without warranty of any kind, express or implied. The authors and contributors are not liable for any damages, data loss, unintended cloud spend, account suspension, or any other problems — direct or indirect — that may arise from using, modifying, or distributing these scripts.

By running these scripts, you acknowledge that:

* You are solely responsible for verifying that your use complies with **Oracle's End User License Agreement** for Oracle Linux, **AWS's Service Terms** (especially for VM Import/Export and EC2), and any applicable laws or regulations.
* The scripts will **invoke `sudo`** on the build host to install KVM/libvirt and modify ACLs on directories under `${WORKSPACE}`. You will review what is installed (Phase 1) and consent to those changes.
* The scripts will **incur AWS charges**: EC2 instance hours on the builder, EBS snapshot storage for the imported image, and S3 storage for the staged VMDK. **You are responsible for monitoring and cleaning up these resources.**
* `import-snapshot` and `register-image` calls will create **persistent AWS resources** (EBS snapshots and AMIs). Deletion is your responsibility — orphaned snapshots are a common source of unexpected AWS bills.
* You will review the script source code (or the [SPEC.md](./SPEC.md) specification) before running it in any environment.
* The build process modifies kernel-level features on the **temporary inner VM** only — your build host is not modified beyond the package installation in Phase 1 and the ACL adjustments in Phase 2. Even so, the build host is best treated as **ephemeral** (a dedicated EC2 instance is ideal).

Operate these tools considerately. **Always prefer official Oracle-distributed AMIs when they exist.** This repository targets the narrow case where Oracle does not publish AMIs for the desired release on the AWS Marketplace and you are willing to operate self-built AMIs on your own AWS account.

---

## 1. Repository Layout

| File | Purpose |
|------|---------|
| `build-ol-aws-ami.sh` | Main build orchestrator. Runs the entire pipeline (prep through AMI registration) in nine phases. Version-agnostic — pick the target OL version via `--env`. |
| `env.properties.aws-ol10` | Build parameters for **Oracle Linux 10 Update 1** (x86_64). |
| `env.properties.aws-ol9` | Build parameters for **Oracle Linux 9 Update 7** (x86_64). |
| `env.properties.aws-ol8` | Build parameters for **Oracle Linux 8 Update 10** (x86_64). |
| `env.properties.aws-ol7` | Build parameters for **Oracle Linux 7 Update 9** (x86_64) — **experimental / deprecated upstream**. See sections 9.6 and 10 for important caveats. |
| `env.properties.aws-ol6` | Build parameters for **Oracle Linux 6 Update 10** (x86_64) — **experimental / not shipped upstream**. See sections 9.7 and 10 for important caveats. |
| `setup-vmimport-role.sh` | One-time setup script that creates the `vmimport` IAM service role for AWS VM Import/Export. |
| `README.md` | End-user documentation (English, baseline). |
| `README.ja.md` | End-user documentation (Japanese). |
| `SPEC.md` | Developer specification (English) — phase contract, log conventions, design decisions. |
| `SPEC.ja.md` | Developer specification (Japanese). |

---

## 2. End-to-End Flow

```
[Builder EC2 (M8i family, nested-virt enabled)]    [AWS]
      │                                              │
      │ (1) Download ISO                             │
      │ (2) Install OS via virt-install              │
      │     (run OL10 as L2 inside KVM L1)           │
      │ (3) Provision via virt-customize             │
      │ (4) Produce VMDK                             │
      │                                              │
      ├─── (5) aws s3 cp ─────────────────────►   S3 Bucket
      │                                              │
      ├─── (6) import-snapshot ───────────────►   EBS Snapshot
      │                                              │
      └─── (7) register-image ────────────────►   AMI ready
```

---

## 3. Choosing a Builder Environment

`oracle-linux-image-tools` relies on KVM/libvirt, so the build host must expose CPU virtualization extensions (Intel VT-x / AMD-V). You have **three options**.

### 3.1 Recommended: AWS EC2 M8i / C8i / R8i family (nested virtualization enabled)

Since February 2026, AWS supports **nested virtualization** on regular (non-bare-metal) EC2 instances. This lets you run the builder on inexpensive instances like `m8i.xlarge`.

| Item | Detail |
|------|--------|
| Supported instances | C8i, C8i-flex, C8id / M8i, M8i-flex, M8id / R8i, R8i-flex, R8id |
| Sizes | `.large` through `.96xlarge` (all sizes supported) |
| Architecture | x86_64 (Intel Xeon 6, Sapphire Rapids generation) |
| Regions | All commercial regions (including Tokyo `ap-northeast-1`) |
| Extra cost | **None** — same price as the regular instance |
| Recommended size | `m8i.xlarge` (4 vCPU / 16 GB) — meets `oracle-linux-image-tools` defaults |

**Launch example:**
```bash
aws ec2 run-instances \
  --image-id <Oracle Linux 9-based AMI ID> \
  --instance-type m8i.xlarge \
  --cpu-options "NestedVirtualization=enabled" \
  --key-name your-keypair \
  --security-group-ids sg-xxxxx \
  --subnet-id subnet-xxxxx \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":60,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ol10-builder}]' \
  --region ap-northeast-1
```

> Important: You must specify `--cpu-options "NestedVirtualization=enabled"` **at launch time**, or stop the instance later and enable it via `modify-instance-cpu-options`.

### 3.2 Alternative 1: AWS EC2 `.metal` instances

The legacy approach without using nested virtualization. More expensive than M8i but a reliable fallback.

| Item | Detail |
|------|--------|
| Supported instances | `c5n.metal`, `m5.metal`, `c6i.metal`, `m6i.metal`, `i3.metal`, etc. |
| Price | Roughly $4–$5 / hour (Tokyo region, on-demand) |
| Pros | KVM works out of the box, no configuration needed |
| Cons | Expensive, unsuitable for frequent builds |

### 3.3 Alternative 2: On-premises KVM host

If you already have a KVM-capable Linux host on premises, the build runs there with no AWS compute cost. Be mindful of bandwidth when uploading the resulting VMDK to AWS.

### 3.4 Common Requirements

| Item | Requirement |
|------|-------------|
| OS | **Oracle Linux 9 / RHEL 9 / Ubuntu 22.04 or newer** recommended |
| Architecture | **x86_64** (must match the target AMI architecture) |
| Memory | 8 GB or more (allocated to the build VM) |
| Disk | At least **30 GB free** in the workspace |
| Network | HTTPS reachability to `yum.oracle.com` and `github.com` |
| Privileges | A regular user with sudo. Direct execution as `root` is not allowed. |

---

## 4. Enabling Nested Virtualization (M8i family only)

### 4.1 Enable at launch

```bash
aws ec2 run-instances \
  --instance-type m8i.xlarge \
  --cpu-options "NestedVirtualization=enabled" \
  ...(other options)
```

### 4.2 Enable on an existing (stopped) instance

```bash
INSTANCE_ID=i-xxxxxxxxxxxxx
REGION=ap-northeast-1

# Stop the instance
aws ec2 stop-instances --instance-ids ${INSTANCE_ID} --region ${REGION}
aws ec2 wait instance-stopped --instance-ids ${INSTANCE_ID} --region ${REGION}

# Enable nested virtualization
aws ec2 modify-instance-cpu-options \
  --instance-id ${INSTANCE_ID} \
  --region ${REGION} \
  --nested-virtualization enabled

# Start the instance
aws ec2 start-instances --instance-ids ${INSTANCE_ID} --region ${REGION}
```

### 4.3 Verify nested virtualization

After SSH'ing into the builder EC2 instance:

```bash
# Check CPU virtualization flags (should include "vmx")
grep -E '(vmx|svm)' /proc/cpuinfo | head -n 1

# Confirm /dev/kvm exists
ls -l /dev/kvm

# Verify from the AWS side (requires ec2:DescribeInstances)
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --region ${REGION} \
  --query 'Reservations[0].Instances[0].CpuOptions.NestedVirtualization'
# -> Returns "enabled" if successfully configured
```

### 4.4 List supported instance types in your region

```bash
aws ec2 describe-instance-types \
  --filters "Name=processor-info.supported-features,Values=nested-virtualization" \
  --query "sort(InstanceTypes[].InstanceType)" \
  --region ap-northeast-1
```

---

## 5. Initial Setup

### 5.1 Obtain the repository

```bash
git clone <your repository hosting these scripts> ol-aws-ami-builder
cd ol-aws-ami-builder
chmod +x build-ol-aws-ami.sh setup-vmimport-role.sh
```

### 5.2 Configure the AWS CLI

```bash
aws configure
aws sts get-caller-identity
```

Minimum IAM permissions required:
- `s3:CreateBucket`, `s3:PutObject`, `s3:GetObject`, `s3:HeadBucket`
- `iam:CreateRole`, `iam:PutRolePolicy`, `iam:GetRole`
- `ec2:ImportSnapshot`, `ec2:DescribeImportSnapshotTasks`, `ec2:RegisterImage`
- `ec2:CreateTags`, `ec2:DescribeImages`, `ec2:DescribeSnapshots`

### 5.3 Create the vmimport IAM role (one-time)

```bash
./setup-vmimport-role.sh my-ol10-ami-import-bucket
```

This role is required by AWS VM Import/Export to read the staged VMDK from S3. Run this **only once per AWS account**.

### 5.4 Edit the environment file

Pick the env template that matches your target Oracle Linux version:

```bash
# Oracle Linux 10 Update 1
cp env.properties.aws-ol10 env.properties.local

# Oracle Linux 9 Update 7
cp env.properties.aws-ol9 env.properties.local

# Oracle Linux 8 Update 10
cp env.properties.aws-ol8 env.properties.local

# Oracle Linux 7 Update 9 (experimental — see 9.6 and section 10)
cp env.properties.aws-ol7 env.properties.local

# Oracle Linux 6 Update 10 (experimental — see 9.7 and section 10)
cp env.properties.aws-ol6 env.properties.local

vi env.properties.local
```

The script auto-detects the OL major and update version from `ISO_URL`, so switching versions is just a matter of using a different env file (or editing `ISO_URL` to point at a different release).

**Minimum settings to update:**

| Parameter | Example |
|-----------|---------|
| `WORKSPACE` | `/tmp/ol10-build-ws` (default — universally accessible by the qemu user; switch to `/var/tmp/ol10-build-ws` if `/tmp` is tmpfs and too small) |
| `S3_BUCKET` | `my-ol10-ami-import-bucket` (must match `setup-vmimport-role.sh`) |
| `AWS_REGION` | `ap-northeast-1` |
| `AMI_NAME` | Optional; auto-generates with timestamp if unset |

---

## 6. Running a Build

### 6.1 Standard run (full pipeline)

```bash
./build-ol-aws-ami.sh --env env.properties.local
```

Expected total time: **40–90 minutes** (depends on bandwidth and instance performance).

| Phase | Description | Approximate time |
|-------|-------------|------------------|
| 0 | Preflight checks | A few seconds |
| 1 | Install KVM and other prerequisites | 2–5 min (first run only) |
| 2 | Grant qemu user traverse ACL on the workspace path | A few seconds |
| 3 | Clone the repository | A few seconds |
| 4 | Resolve ISO checksum / generate env file | A few seconds |
| 5 | Build the VMDK (`virt-install` runs the OS installer) | **20–40 min** |
| 6 | Upload to S3 | 2–10 min |
| 7 | `import-snapshot` (creates EBS snapshot) | **10–30 min** |
| 8 | `register-image` (registers the AMI) | Less than 1 min |

### 6.2 Execution modes

| Option | Use case |
|--------|----------|
| `--skip-prereq` | Skip KVM package installation (Phase 1). Useful for re-runs. |
| `--build-only` | Stop after VMDK is built (Phase 5). Run the AWS import separately. |
| `--skip-aws-import` | Skip Phases 6–8 (equivalent to `--build-only`). |

### 6.3 Phase 0 self-diagnosis

Phase 0 inspects the runtime environment and emits targeted guidance when something is wrong.

**Case A: An M8i-family instance with nested virtualization currently disabled**
```
[ERROR] CPU virtualization extensions are NOT exposed on this EC2 host
[INFO]  Detected instance type: m8i.xlarge
[WARN]  [Case A] m8i supports nested virtualization, but the feature is currently disabled.
[INFO]  Action: enable nested virtualization on this instance.
[INFO]    aws ec2 stop-instances --instance-ids i-xxxxx --region ap-northeast-1
[INFO]    aws ec2 modify-instance-cpu-options ...
```

**Case B: Running on an instance family that does not support nested virtualization**
```
[WARN]  [Case B] m5 does NOT support nested virtualization.
[INFO]  Option 1 (recommended): Use a nested-virtualization-capable C8i / M8i / R8i instance
[INFO]  Option 2: Switch to a bare-metal instance
```

**Case C: A bare-metal instance that has /dev/kvm missing**
```
[WARN]  [Case C] m5.metal is bare metal but /dev/kvm is unavailable.
[INFO]  Action:
[INFO]    1) Check whether the kvm module is loaded: lsmod | grep kvm
[INFO]    2) If not loaded, load it manually: sudo modprobe kvm-intel
```

This automation **minimizes the trial-and-error of first-time setup**.

---

## 7. Cost Comparison

Tokyo region pricing, assuming roughly one hour per build.

| Approach | Builder | Hourly | Per build | 4 builds/mo | 30 builds/mo |
|----------|---------|--------|-----------|-------------|--------------|
| **Recommended: M8i + nested virt** | `m8i.xlarge` | $0.30/h | **$0.30** | $1.20 | **$9.00** |
| Recommended: C8i (compute-heavy) | `c8i.2xlarge` | $0.50/h | $0.50 | $2.00 | $15.00 |
| Legacy: bare metal | `c5n.metal` | $4.50/h | $4.50 | $18.00 | $135.00 |
| Legacy: bare metal | `m5.metal` | $5.50/h | $5.50 | $22.00 | $165.00 |

**At 30 builds per month, you save approximately $126/month** compared to the bare-metal approach. The pricing easily supports CI/CD pipeline integration.

---

## 8. Verifying the AMI

### 8.1 List your AMIs

```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:OS,Values=OracleLinux10U1" \
  --query 'Images[*].[ImageId,Name,CreationDate,BootMode]' \
  --output table
```

### 8.2 Smoke test by launching an instance

```bash
AMI_ID=ami-xxxxxxxxxxxxx
KEY_PAIR=your-keypair
SG_ID=sg-xxxxxxxx
SUBNET_ID=subnet-xxxxxxxx

aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type t3.small \
  --key-name "${KEY_PAIR}" \
  --security-group-ids "${SG_ID}" \
  --subnet-id "${SUBNET_ID}" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ol10-test}]'
```

SSH login:
```bash
ssh -i your-keypair.pem ec2-user@<public-ip>
```

cloud-init deploys your public key under the `ec2-user` account on first boot.

---

## 9. Key Design Decisions (summary)

> **Full rationale** for every design choice — phase numbering, log conventions, env property auto-detection, AWS quirks — lives in [SPEC.md](./SPEC.md) ([日本語](./SPEC.ja.md)). The summary below highlights the points most relevant to operators; refer to SPEC for the historical context (Part C) behind each.

### 9.1 `import-snapshot` + `register-image` over `import-image`

The two-step flow (`import-snapshot` to create the EBS snapshot, then `register-image` to attach AMI attributes) gives explicit control over `BootMode`, ENA, NitroTPM, and IMDS settings. `import-image` is convenient but relies on AWS auto-detecting the OS, and newer Oracle Linux releases may not yet appear in AWS's supported-OS list. See SPEC §B.1 for which `register-image` flags are unconditional vs. conditional.

### 9.2 ENA / NVMe drivers in the resulting AMI

The `cloud=aws` target of `oracle-linux-image-tools` bundles the Amazon ENA driver and `cloud-init` into the image. The OL8/9/10 kernels (UEK or RHCK) ship `ena` and `nvme` modules natively, so no extra driver injection is required for full Nitro-instance compatibility.

### 9.3 `BOOT_MODE_BUILD = "bios"` (mandatory for AWS)

Oracle's upstream `bin/build-image.sh` enforces `BOOT_MODE=bios` for AWS targets and rejects `uefi` or `hybrid`. The resulting AMI is registered as `legacy-bios`. This is the **only** working combination today — see SPEC §C.4 for the discovery history. The AMI boots on every Nitro instance type; the trade-off is that NitroTPM and UEFI Secure Boot cannot be enabled.

### 9.4 cloud-init / ec2-user

Setting `CLOUD_INIT="Yes"` and `CLOUD_USER="ec2-user"` aligns with the AWS convention of first-login via SSH key on the `ec2-user` account. This is the default in all three env templates.

### 9.5 Why nested virtualization is the primary recommendation

Now that AWS officially supports nested virtualization on C8i / M8i / R8i (since February 2026), this approach delivers:

1. **Compatibility with the official Oracle tooling** at a **dramatically lower cost** (≈$0.30/build on `m8i.xlarge` vs. ≈$5/build on `c5n.metal`).
2. **Realistic CI/CD integration** thanks to the pricing.
3. Faster end-to-end time, avoiding the multi-minute startup latency typical of bare-metal instances.
4. Compatibility with Spot Instances and Auto Scaling for further cost optimization.

### 9.6 Oracle Linux 7 support (experimental)

OL7 is supported on a best-effort basis with the following key behaviors:

- **Runtime patch.** The upstream `cloud/aws/image-scripts.sh` hard-codes a check that rejects OL7 (`AWS images builder only supports OL8 and above`). Phase 3 of `build-ol-aws-ami.sh` detects `OL_MAJOR_VERSION == 7` after the repository clone and rewrites that single line to a no-op (a backup file `image-scripts.sh.ol7-patch.bak` is left next to the patched file for reference).
- **No upstream commits.** The patch is applied only to the local working clone in `${WORKSPACE}/oracle-linux/`. No changes are pushed back to `oracle/oracle-linux`.
- **Why this works.** OL7 is otherwise still a complete distribution in the upstream tooling (`distr/ol7-slim/` is intact, and the AWS provisioning step installs `kernel-uek-modules` which OL7's UEK6 provides). The OL7 rejection is purely a policy guard, not a technical incompatibility.
- **Forced settings.** `BOOT_MODE_BUILD=bios` is mandatory on two grounds: the AWS target enforces it, **and** OL7 itself enforces it (`bin/build-image.sh`: `OL7 only supports bios BOOT_MODE`). Setting anything else aborts the build immediately.
- **Recommended kernel.** Leave `KERNEL=uek` for OL7. The RHCK path requires a separate `kernel-modules` package that OL7 does not split out, so the upstream `cloud/aws/provision.sh` invocation will fail with `KERNEL=rhck` on OL7. UEK6 includes the Amazon ENA driver and is the upstream OL7 default.
- **Boot startup banner.** When `OL_MAJOR_VERSION == 7` is detected at `load_env` time, the script emits a prominent multi-line warning summarizing the EOL status, the runtime patch behavior, and the production-use prohibition.

See [section 10](#10-known-limitations-and-caveats) item 7 for the full list of OL7 caveats.

### 9.7 Oracle Linux 6 support (experimental)

OL6 is supported as a deeper workaround than OL7. The upstream tooling does **not** ship a `distr/ol6-slim/` directory at all, so this wrapper synthesizes it at runtime from embedded templates. In addition, a second runtime patch is required against `cloud/aws/provision.sh`.

- **Runtime patch #1 (shared with OL7).** `cloud/aws/image-scripts.sh` rejects any release below OL8 with `AWS images builder only supports OL8 and above`. Phase 3 of `build-ol-aws-ami.sh` rewrites that line to a no-op when `OL_MAJOR_VERSION <= 7`. A backup `image-scripts.sh.ol6-patch.bak` is left in place.
- **Runtime patch #2 (OL6-specific).** `cloud/aws/provision.sh` unconditionally runs `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` for `KERNEL=uek`. This package **does not exist** in the OL6 UEKR4 repository (all ENA/NVMe/virtio modules are bundled directly inside the `kernel-uek` RPM). Phase 3 gates that install behind `ORACLE_RELEASE >= 7`. A backup `provision.sh.ol6-patch-uek-modules.bak` is left in place. The patch is idempotent (a marker grep skips a second application).
- **Runtime-generated `distr/ol6-slim/`.** Four files (`env.properties`, `image-scripts.sh`, `ol6-ks.cfg`, `provision.sh`) are written under `${WORKSPACE}/oracle-linux/oracle-linux-image-tools/distr/ol6-slim/` from heredocs embedded in `build-ol-aws-ami.sh`. They mirror `distr/ol7-slim/`'s structure with OL6-specific adjustments: Upstart instead of systemd (`service`/`chkconfig` calls), GRUB Legacy instead of GRUB2 (`/boot/grub/grub.conf` edits), Anaconda 13.x kickstart syntax (no `inst.` prefix), and ext4/xfs only (no lvm/btrfs at this layer).
- **No upstream commits.** All three artifacts (two patches plus the synthesized `distr/ol6-slim/`) are local to `${WORKSPACE}/oracle-linux/`. Nothing is pushed back to `oracle/oracle-linux`.
- **Forced settings.** `BOOT_MODE_BUILD=bios` is mandatory on three independent grounds: the AWS target enforces it, the upstream OL7 path enforces it (and the OL6 templates inherit that constraint), and OL6 anaconda 13.x predates UEFI entirely.
- **Kernel constraint.** `KERNEL=uek` with `UEK_RELEASE=4` is the only valid combination for OL6+AWS. UEK2/3 lack the ENA driver. UEK5/6/7 are not available for OL6. RHCK 2.6.32 also lacks ENA. The OL6 `image-scripts.sh` `distr::validate` enforces `UEK_RELEASE=4`.
- **`linux-firmware` is sticky.** `kernel-uek` on OL6 declares a hard install dependency on `linux-firmware`. Setting `LINUX_FIRMWARE="No"` removes it, but any subsequent `yum install kernel-uek` will pull it back in.
- **Boot startup banner.** When `OL_MAJOR_VERSION == 6` is detected at `load_env` time, the script emits a prominent multi-line warning summarizing EOL status, the two runtime patches, the runtime-generated `distr/ol6-slim/`, and the production-use prohibition.

See [section 10](#10-known-limitations-and-caveats) item 8 for the full list of OL6 caveats.

---

## 10. Known Limitations and Caveats

1. **aarch64 (Graviton) AMIs are not supported.**
   `oracle-linux-image-tools` only targets x86_64 for AWS, and AWS nested virtualization is not available on Graviton. Building aarch64 AMIs requires a separate path.

2. **Build host architecture must match the target.**
   You need an x86_64 host to build x86_64 AMIs. Cross-architecture builds via libguestfs/virt-install are impractical.

3. **AWS service quotas.**
   `import-snapshot` is rate-limited per AWS account (default: 5 concurrent tasks). If you build at high volume, check AWS Service Quotas.

4. **Official VM Import support for OL10.**
   As of May 2026, OL10 may not appear in the AWS VM Import/Export supported-OS matrix. Using `import-snapshot` + `register-image` (as this script does) sidesteps that limitation.

5. **License and support.**
   If you need an Oracle Linux support contract, purchase Oracle Linux Premier Support separately.

6. **Performance of nested virtualization.**
   AWS still recommends bare-metal for workloads with strict performance/latency requirements. The build process here is I/O bound, so the overhead of nested virtualization is not a practical concern.

7. **Oracle Linux 7 specific limitations.**
   - **EOL.** Premier Support ended on 2024-12-31. Oracle marks OL7 as deprecated in the upstream `oracle-linux-image-tools` README.
   - **Not supported upstream for AWS.** The upstream tool explicitly rejects OL7 for `cloud=aws`. This wrapper patches the rejection at runtime in Phase 3 (see [9.6](#96-oracle-linux-7-support-experimental)). Future upstream refactors may break the patch.
   - **x86_64 only.** OL7 has no aarch64 AMI path. The OL8/9/10 `_aarch64` directories under `distr/` have no OL7 counterpart.
   - **BIOS only.** UEFI / hybrid boot modes are unavailable; NitroTPM and UEFI Secure Boot cannot be enabled on the resulting AMI.
   - **UEK kernel mandatory in practice.** Although `KERNEL=rhck` is theoretically accepted, the upstream AWS provisioning step requires the `kernel-modules` package which OL7's RHCK does not split out. Stay with `KERNEL=uek` (the default in the OL7 env template).
   - **No `lvm` root filesystem.** OL7 supports only `xfs` and `btrfs` at this layer; the `lvm` option (added in OL8) is not available.
   - **Production prohibited.** Use the resulting AMI strictly for verification, learning, or legacy-migration scenarios.

8. **Oracle Linux 6 specific limitations.**
   - **EOL.** Premier Support ended on 2021-03-31. Extended Life Support (ELS) ended in 2024. Oracle has shipped no security updates for OL6 since then.
   - **Not shipped upstream at all.** The upstream `oracle-linux-image-tools` repo has no `distr/ol6-slim/` directory. This wrapper synthesizes the four required files (`env.properties`, `image-scripts.sh`, `ol6-ks.cfg`, `provision.sh`) at runtime in Phase 3 (see [9.7](#97-oracle-linux-6-support-experimental)). The AWS `image-scripts.sh` guard is patched the same way as for OL7.
   - **Extra runtime patch.** `cloud/aws/provision.sh` is patched at runtime to skip `yum install kernel-uek-modules` on OL6 — this package does not exist in OL6/UEKR4 (modules are bundled inside `kernel-uek` itself).
   - **x86_64 only.** OL6 has no aarch64 release on any media; there is no aarch64 AMI path.
   - **BIOS only.** OL6 anaconda 13.x predates UEFI install support entirely. NitroTPM and UEFI Secure Boot cannot be enabled.
   - **UEK4 mandatory.** `KERNEL=uek` with `UEK_RELEASE=4` is the only valid combination. UEK2/3 lack the ENA driver; UEK5/6/7 do not have OL6 builds; RHCK 2.6.32 also lacks ENA.
   - **Filesystem: ext4 or xfs only.** No lvm/btrfs at this layer.
   - **`linux-firmware` cannot be removed permanently.** `kernel-uek` declares a hard install dependency on it; any `yum install kernel-uek` reinstall will pull it back in.
   - **AWS VM Import/Export marks OL6 as EOL.** This wrapper bypasses the policy by using `import-snapshot` + `register-image`. AWS may tighten this policy in the future.
   - **Phase A/B verified, Phase C not yet validated.** Static checks (osinfo-db entries, ISO checksum, repo HTTPS, dracut flags, cloud-init availability, upstream OL-version branches) and the OL6 ISO boot test (virt-install + isolinux + Anaconda 13.21.263 TUI) have been verified. End-to-end kickstart completion, provision.sh execution on OL6, cloud-init `ec2-user` creation, and AMI launch on AWS Nitro have **not** been verified by the author.
   - **Production prohibited.** Even more strongly than OL7: use the resulting AMI only for verification, learning, or legacy-migration scenarios.

---

## 11. Troubleshooting

### Phase 0 reports "CPU virtualization extensions are NOT exposed"

→ Follow the targeted guidance from the Phase 0 self-diagnosis. In most cases, nested virtualization simply has not been enabled. See section 4.2 to apply `modify-instance-cpu-options`.

### Phase 1: `qemu-kvm` install fails

→ EPEL or CodeReady Builder repositories may need to be enabled.
```bash
sudo dnf config-manager --set-enabled crb  # Oracle Linux 9 / RHEL 9
sudo dnf install -y epel-release
```

### Phase 5: `KVM acceleration not available, using 'qemu'` warning

→ Either nested virtualization is off, or `/dev/kvm` permissions are wrong.
```bash
ls -l /dev/kvm
sudo modprobe kvm-intel
sudo usermod -aG kvm,libvirt $USER
# Log out and back in for the new groups to take effect
```

### Phase 7: `ClientError: Unsupported kernel version`

→ AWS VM Import does not recognize the OL10 kernel. This is the typical failure with `import-image`, but **should not occur** with this script since it uses `import-snapshot`. If it does occur, file a support request asking AWS to extend OL10 support.

### cloud-init hangs on first boot of the new AMI

→ Confirm `SERIAL_CONSOLE_RUNTIME="Yes"` is set. You can inspect the boot log via the EC2 Serial Console:
```bash
aws ec2 get-console-output --instance-id i-xxxxx --region <region>
```

---

## 12. References

- [oracle/oracle-linux/oracle-linux-image-tools](https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools) — The Oracle official tool used internally
- [Use nested virtualization to run hypervisors in Amazon EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html) — AWS nested virtualization documentation
- [Amazon EC2 supports nested virtualization on virtual Amazon EC2 instances (What's New)](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/) — February 2026 release announcement
- [Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html) — ISO downloads and checksums
- [AWS VM Import/Export User Guide](https://docs.aws.amazon.com/vm-import/latest/userguide/) — Detailed documentation for `import-snapshot` / `register-image`
- [Boot modes in EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ami-boot.html) — Behavior of `uefi-preferred` and friends

---

## 13. Provenance and License

### AI generation

This wrapper was **iteratively developed with Anthropic Claude (Sonnet 4.5)** in 2026-05, then refined based on real build runs against Oracle Linux 8 / 9 / 10 on AWS until all three versions completed end-to-end successfully. Oracle Linux 7 experimental support was added in a subsequent 2026-05 revision using Anthropic Claude (Opus 4.7); the OL7 patch mechanism has been verified (sed substitution, syntax integrity, idempotency) but **end-to-end OL7 AMI builds have not been validated by the author**. Oracle Linux 6 experimental support was added in a further 2026-05 revision using Anthropic Claude (Opus 4.7) after a two-phase verification session (Phase A: 9 static checks against osinfo-db, ISO/checksum, repo HTTPS, dracut, cloud-init; Phase B: virt-install + Anaconda 13.21.263 TUI boot test on libvirt 11.5 / qemu 10.0). The two OL6 runtime patches and the runtime-generated `distr/ol6-slim/` have been syntactically validated, but **end-to-end OL6 AMI builds (kickstart completion through AWS Nitro launch) have not been validated by the author**.

The upstream `oracle-linux-image-tools` project that this wrapper drives is independent and produced by Oracle.

### License and warranty

Provided **AS IS, without warranty of any kind**. The author and AI tool are not liable for any damages arising from use. See the [repository-level disclaimer](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md) for full terms.

### Feedback / corrections / contributing

If you encounter a problem, want to suggest an improvement, or have used these scripts on a new Oracle Linux release we should add a template for, please open an issue at:

https://github.com/usui-tk/ai-generated-artifacts/issues

When filing a bug, please include:

- **Build host**: OS / version / instance type (if EC2) / whether nested-virt is enabled
- **Target**: which `env.properties.aws-ol{N}` you used, plus any keys you customized
- **Phase that failed**: the `========== Phase N: ...` banner just before the error
- **Log excerpt**: 10–50 lines around the failure (not the whole 1000+ line log)
- **What you already tried**: e.g. cleaned `${WORKSPACE}`, switched WORKSPACE filesystem, etc.

For code-level changes, please consult [SPEC.md](./SPEC.md) first — Part C ("Known Pitfalls & Lessons Learned") documents bugs the current implementation already handles, and Part A defines the conventions any new code must follow.
