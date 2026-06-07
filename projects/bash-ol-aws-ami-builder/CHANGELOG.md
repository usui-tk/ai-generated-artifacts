---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-06
---
# Changelog

All notable changes to `build-ol-aws-ami.sh` are documented in this file.

The format is based on
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

This project's revision identifier is the `rNN` linear counter encoded in the
script banner.

This CHANGELOG is **English only** per the repository-wide
[documentation language policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md).

## [Unreleased]

### Added

- Added an **in-guest Amazon ENA driver self-build** (`install-ena-driver.sh`),
  enabled by default and disabled with the new `--skip-ena-driver` switch — the
  default yields an **AWS-optimized AMI** (Nitro v4+/ENAv3 capable) while
  `--skip-ena-driver` yields a **pure, unmodified OL AMI**. Phase 3 appends a
  hook to the upstream `cloud/aws/provision.sh` that embeds and runs the
  installer during guest provisioning. The installer self-gates by OS major
  (builds on OL6 → pinned `ena_linux_2.5.0`, OL7 → pinned `ena_linux_2.17.0`;
  no-op on OL8+), detects the installed UEK kernel from `/lib/modules` (rather
  than the libguestfs appliance's `uname -r`) and builds explicitly against it
  via **DKMS** (`REMAKE_INITRD`/`AUTOINSTALL`, so it survives kernel upgrades),
  sourcing DKMS from Oracle's `ol7_developer_EPEL` on OL7 and the Fedora EPEL 6
  archive on OL6 (with a plain-`make` fallback), then regenerates the initramfs.
  Pins are the newest release supporting each target OS; override with
  `ENA_DRIVER_VERSION`. See SPEC A.7. Source: amzn/amzn-drivers.

- Added a **Phase 6 Nitro readiness pre-check** (`NITRO_PRECHECK`,
  `enforce` | `warn` | `off`, default `enforce`; a wrapper key). After the VMDK
  is built and before the upload/snapshot/register phases, it inspects the image
  **offline and read-only** (libguestfs, `LIBGUESTFS_BACKEND=direct`, targeting
  the UEK kernel) for the AWS Nitro boot essentials, adapting the logic of AWS's
  NitroInstanceChecks to a built image rather than a running instance:
  (1) the NVMe **host** driver `nvme.ko` is built in or in the kernel's
  initramfs; (2) the ENA driver is present; (3) `/etc/fstab` uses `UUID=`/
  `LABEL=` (not `/dev/sd*`|`/dev/xvd*`, which Nitro renames to `/dev/nvme*`);
  and (4) the bootloader `root=` is UUID/LABEL/LVM based (GRUB2 and OL6 GRUB-
  legacy). `enforce` `die`s on a blocking finding before the wasted upload
  phases; `warn` reports only; `off` skips. Indeterminate results (inspection
  tools absent, initramfs not extractable) are fail-open (warn + continue), so a
  missing tool never aborts an otherwise-good build. Detection only — no
  remediation. Validated against a known-good OL10 image (all four checks PASS).
  See SPEC A.7 and Part C.

- Phase 6 also emits an **advisory Nitro instance assurance report**: it
  classifies each Nitro generation (v2–v6) as `ASSURED` / `SUPPORTED` /
  `DEGRADED` / `NOT-ASSURED` and lists representative instance families per
  generation. The signal is ENA **ENAv3** support, per the amzn/amzn-drivers ENA
  driver docs (ENAv3 is on the majority of Nitro v4+ types; Nitro v2/v3 use
  ENAv1/v2 and are unaffected): a standalone driver `MODULE_VERSION` `< 1.2.0`
  fails to attach an ENAv3 ENI (Nitro v4+ `NOT-ASSURED`; the only
  fatal-under-`enforce` case), `1.2.0`–`< 2.2.9` is ENAv3 performance
  degradation (`DEGRADED`, a warning — *not* a failure), `≥ 2.2.9` is full
  support; the driver supports kernels `>= 3.10`. Because UEK ships ENA in-tree
  with no `MODULE_VERSION`, the report falls back to the kernel version vs the
  ENAv3-introduction kernel for OL/RHEL (RHEL 8.3, `4.18.0-240`); a lower kernel
  is reported `SUPPORTED` (ENAv2 mode; verify with `ethtool -i`), never a
  failure. Source: amzn/amzn-drivers `ENA_Linux_Best_Practices.rst` /
  `RELEASENOTES.md`.

- Added a Phase-5 progress heartbeat: `HEARTBEAT_INTERVAL_SEC` (seconds,
  default `20`; `0` disables — a wrapper key) logs an elapsed-time + build-disk
  growth (`du`, *actual* on-disk clusters, not the preallocated apparent size)
  + best-effort domain-state line during the build. This makes a headless
  build's liveness/progress visible independent of the install console (OL6
  streams to the serial console, but OL8+ anaconda runs in tmux and is
  near-silent there), without changing completion detection. The default is
  short because the script is usually run interactively. See SPEC A.7.
  conformance test for the wrapper-synthesized OL6 kickstart, using
  `pykickstart` (`ksvalidator -v RHEL6`). It rejects OL7-syntax directives that
  are invalid on OL6/anaconda-13 before they can halt the install. Syntax-only:
  it does not verify runtime filesystem support (e.g. xfs root) or package
  availability — those are confirmed by a live build (e.g. an isolated
  `virt-install` with the installer console visible). See
  SPEC D.18. (Subproject-local; the bash TESTING doc-template stays deferred in
  the canon per the rule-of-two, so `TESTING.md` carries no doc-provenance pin.)

### Changed

- The Phase 6 Nitro **instance-assurance report** is now **purely advisory and
  never aborts the build** — only the four boot-readiness checks (CHECK 1–4:
  NVMe host / ENA present / fstab / bootloader) feed the gate verdict. A
  measurable ENA driver version `< 1.2.0` (e.g. OL6's default ENA `1.1.2`)
  previously failed the gate under `enforce`; it is now reported as a Nitro v4+
  ENAv3 attach risk (`NOT-ASSURED`, with a "refresh the driver" hint) but no
  longer stops the build, so OL images with an old in-distro ENA driver still
  reach S3 upload / snapshot import / AMI registration. Boot-blocking findings
  (CHECK 1–4) remain fatal under `enforce` as before. See SPEC A.7.

- Phase-5 logging now clearly separates this wrapper's output from the external
  tool's. The wrapper's own lines keep our defined format (`[INFO]`/`[WARN]`/
  `[ERROR]`, the `==========` step banners, and a new `[BUILD]` progress tag for
  the heartbeat), while **every line of the external oracle-linux-image-tools
  output** (the `build-image.sh` orchestrator plus the libguestfs / virt-* sub-
  tools it runs) is re-emitted as
  `[EXTERNAL] HH:MM:SS [build-image.sh] <line>` — an external-call tag, a
  per-line timestamp, the script name, then the original message. Output is
  merged (`2>&1`) and attributed line-by-line by a small `log_external` helper;
  `pipefail` preserves the build's real exit status. Also corrected the build-
  watchdog log line, which previously claimed "upstream applies no install
  timeout when the serial console is enabled" — inaccurate under the default
  `SERIAL_CONSOLE=no`, where upstream applies its own install wait. (Note: the
  external `virt-sparsify` progress bar, which redraws via carriage returns,
  appears at completion rather than animating, because attribution is
  line-based.)

- Install-time `SERIAL_CONSOLE` is now **wired through** to the upstream
  `env.properties.local` (previously it was not passed through at all, so
  setting it had no effect). The default remains `no` (headless), which is the
  reliable path: upstream detects install completion via the domain lifecycle
  and applies its own install timeout. `yes` is available as a **debug-only
  opt-in** to stream the OL6/7 install live, but it makes upstream wait on
  `virsh console`, which does not cleanly return when the install VM ends and
  can hang the build until the watchdog (observed even on otherwise-successful
  builds) — so it is not the default. Set explicitly in all five
  `env.properties.aws-ol{6,7,8,9,10}` templates. Does **not** change the
  produced AMI: the generated image's console is governed by the independent
  `SERIAL_CONSOLE_RUNTIME` (unchanged). See SPEC A.7 / D.18.
- Added a Phase-5 build watchdog: `BUILD_TIMEOUT_MIN` (minutes, default `120`,
  a wrapper key) is an outer safety bound on the upstream `bin/build-image.sh`
  run (in addition to upstream's own headless install timeout). On expiry the
  wrapper reaps the leftover transient libvirt domain (`virt-install
  --transient`, which survives a killed `build-image.sh`) and aborts. See SPEC
  A.7.
- Documented the guest Oracle Linux package-manager split (OL6/7 use `yum`,
  OL8/9/10 use `dnf`) and the per-OL kernel / security-update / config-manager
  conventions as SPEC B.7 'Guest OS package-manager matrix'; added a rationale
  comment in `phase3_clone_repository`. All of OL6-10 remain supported. No
  functional change: the OL6 kickstart `%packages` already ships `yum-utils`
  and `yum-plugin-security`, so no extra install step was required.
- Made `phase1_install_prerequisites` (build host provisioning) version-aware:
  detection now reads `ID` + `VERSION_ID` from `/etc/os-release` and selects a
  per-OS/version KVM + libguestfs package set. Supported build hosts are the
  latest two generations only - OL/RHEL/Rocky/Alma/CentOS Stream 10/9,
  Fedora 44/43, Ubuntu 26.04/24.04, Debian 13/12; older releases are refused
  with a clear `die`. Ubuntu 26.04 uses `qemu-system` (the `qemu-kvm`
  transitional package was dropped); `bridge-utils` is not installed (libvirt
  default NAT). See SPEC B.6.
- Migrated the subproject from `scripts/aws/ol-aws-ami-builder/` to
  `projects/bash-ol-aws-ami-builder/` and reconstructed the doc-set (README,
  README.ja, SPEC, this CHANGELOG) from the repository template canon
  (template-canon v1.0.0). Added the doc-provenance front-matter pin and rebased
  governance links to absolute URLs. No script behavior changed.

### Fixed

- **OL6 SSH was unreachable (`Connection refused`)** because sshd refused to
  start: the wrapper wrote `PermitRootLogin prohibit-password` into
  `sshd_config`, but that token (OpenSSH 6.7+) is a **fatal parse error** on
  OL6's OpenSSH 5.3, which accepts only
  `yes|no|without-password|forced-commands-only`. The OL6-only `provision.sh`
  now maps `prohibit-password` → `without-password` (its identical pre-6.7
  alias) before editing `sshd_config`, and then **validates the result with
  `sshd -t`** (using an ephemeral host key) and aborts the build on any parse
  error — turning a silent first-boot failure into a deterministic build-time
  one. OL7+ are untouched (per-OS isolation). See SPEC D.24.

- Phase 6 **CHECK 2 (ENA driver) and the assurance report now scan the full
  `/lib/modules/<kver>` tree** (`/kernel` + `/extra` + `/updates`) instead of
  only `/kernel`. The in-guest ENA self-build installs `ena.ko` via DKMS into
  `/extra` (or `/updates/dkms`), which depmod ranks above the stock `/kernel`
  copy; the old `/kernel`-only scan missed it, so a default (self-build) OL7
  build hit a false `CHECK 2 FAIL (no ENA driver)`. CHECK 2 now selects the
  *effective* `ena.ko` by depmod precedence (`updates` > `extra` > `kernel`),
  and the assurance report's `modinfo` copy-out prepends the real
  `/lib/modules/<kver>` base rather than a hardcoded `/kernel`. The report also
  annotates driver **provenance** (`stock in-tree` vs `self-built, DKMS …`) so
  the self-build's effect — and the absence of any CHECK 1-4 regression — is
  visible. Feature-aware and OL-version-independent (stock or DKMS, any OL). See
  SPEC D.23 and A.7.

- Force **nvme + ena into the initramfs** so OL AMIs actually boot on Nitro. The
  image is built in a VM with a virtio root disk, so dracut's hostonly mode omits
  nvme from the initramfs; an OL7 build's initramfs had `nvme.ko` on disk but not
  in the initramfs, so it could not mount its NVMe-backed root on Nitro (Phase 6
  CHECK 1 correctly FAILed). Phase 3 now **always** (even with
  `--skip-ena-driver`, since booting is not optional) appends a hook to
  `cloud/aws/provision.sh` that drops `/etc/dracut.conf.d/02-ol-aws-nitro.conf`
  (`add_drivers+=" nvme nvme-core ena "`, persisting across kernel updates) and
  regenerates the initramfs for the installed kernel. It targets the highest UEK
  under `/lib/modules` (not the appliance `uname -r`) and is best-effort. CHECK 1
  is unchanged — its OL7 FAIL was a true positive, not a detection bug. See SPEC
  A.7 ("Nitro initramfs drivers") and D.22.

- `install-ena-driver.sh` is now **self-contained and runnable standalone**, and
  resolves the `kernel-uek-devel` gap that aborted the DKMS build. The stock OL
  ISO ships an older `kernel-uek` whose `-devel` is often pruned from the repos
  (`No package kernel-uek-devel-<ver> available`); because `yum` does not fail on
  a missing package, DKMS aborted with "kernel headers ... cannot be found". The
  installer now enables the UEK repo (`*UEKR4*`/`*UEKR6*`), tries the exact
  `-devel`, and if the headers are still absent installs the latest `kernel-uek`
  + matching `-devel` and retargets the build to that kernel. It also installs
  all build prerequisites itself (EPEL, `gcc`/`make`, `dkms`, headers) and, when
  run on a live instance, targets the running kernel (falling back to the highest
  UEK under `/lib/modules` only under the provisioning appliance). This lets the
  driver build be validated by running the script directly on a stock OL6/OL7
  instance, independently of the end-to-end image build. See SPEC A.7.

- Phase 6 **CHECK 1 (NVMe host driver)** no longer reports a false `FAIL` when
  the guest's dracut initramfs cannot be read on the build host. dracut images
  vary by compression (gzip/xz/zstd/lz4) and may carry a leading microcode cpio;
  an OL7 (UEK R6, 5.4) image was unreadable by the host's `unmkinitramfs` while
  OL6 was readable, so the old logic mistook "could not inspect" for "driver
  absent" and aborted the build. CHECK 1 now tries several listing methods
  (`unmkinitramfs`, then `lsinitrd`/`lsinitramfs`, then a manual decompress +
  `cpio -t`); when nvme.ko is present on disk but no method can read the
  initramfs, it reports `INDETERMINATE` (fail-open) rather than `FAIL`. A hard
  `FAIL` remains only when nvme.ko is absent from both the kernel and an
  inspectable initramfs. Also recorded the measured baseline in-distro ENA
  drivers (OL6 `1.1.2` on `kernel-uek-4.1.12-124.48.6.el6uek`, OL7 `2.1.0K` on
  `kernel-uek-5.4.17-2136.338.4.2.el7uek`) in SPEC A.7 as the rationale for the
  ENA self-build. See SPEC A.7 and D.21.

- OL6 build no longer aborts at the Cleanup stage on
  `virt-sysprep ... --truncate /etc/machine-id: No such file or directory`.
  Upstream `build-image.sh::image_cleanup()` unconditionally truncates
  `/etc/machine-id` (a systemd artifact); OL6 uses Upstart and has no such file,
  so the truncate aborted the whole build after a successful install and
  provisioning. The synthesized OL6 kickstart `%post` now creates an empty
  `/etc/machine-id` (and `/etc/resolv.conf` if absent), so OL6 reaches the same
  state OL7+ are already in when `virt-sysprep` runs — upstream-agnostic, no
  patch to `build-image.sh`, and harmless (an empty `/etc/machine-id` is the
  standard regenerate-on-first-boot marker). OL7/8/9/10 were never affected.
  See SPEC D.20.

- OL6 build no longer aborts at provisioning on `declare: -g: invalid option`.
  Upstream `env.properties.defaults` ends with `declare -gA REPO`; the `-g`
  (global) flag is bash 4.2+, but that file is concatenated first into the
  in-guest `provision.d/env.properties` and sourced inside the OL6 guest, which
  runs bash 4.1 — so the install succeeded but provisioning died, and
  `build-image.sh` exited 1. A Phase-3 patch (OL6 only) rewrites the line to
  `declare -gA REPO 2>/dev/null || declare -A REPO`: the host keeps the
  intended global associative array (bash 5.x), while the OL6 guest falls back
  to a 4.1-compatible form (`REPO` is unused by guest provisioning). OL7/8/9/10
  guests (bash 4.2+) were never affected. Grep-guarded for idempotency; keeps a
  `.declare-g-guard.bak` backup. See SPEC D.19.

- OL6 root filesystem is now `ext4` (was `xfs`). The OL6.10 installer
  (anaconda-13) **refuses** to place the root partition on XFS and aborts at
  partitioning, so no AMI was ever produced — a runtime policy that
  `ksvalidator` cannot see (`part / --fstype=xfs` is valid RHEL6 *syntax*).
  Confirmed by a bare `virt-install` against the OL6.10 DVD: an xfs root is
  rejected at partitioning, whereas an ext4 root installs cleanly through the
  full 217-package set (ext4 `/boot` + `/`, UEK4, `linux-firmware`). Changes:
  `env.properties.aws-ol6` now sets `ROOT_FS="ext4"`; `distr::validate()`
  rejects any non-ext4 OL6 root at preflight (before ISO download); and the
  former `distr::kickstart` ext4->xfs root rewrite (which only ever produced an
  install-failing config) was removed. OL7/8/9/10 keep `xfs` (newer anaconda
  supports it). See SPEC D.16/D.18.
- README (EN + JA) "Common Requirements" build-host OS row corrected to match
  the version-aware `phase1_install_prerequisites` and SPEC B.6: it had said
  "Oracle Linux 9 / RHEL 9 / Ubuntu 22.04 or newer (recommended)", but the
  script supports only the latest two generations and **refuses** older hosts
  (e.g. Ubuntu 22.04, OL/RHEL 8) with a `die`. Now states OL/RHEL/Rocky/Alma/
  CentOS Stream 10 or 9, Fedora 44 or 43, Ubuntu 26.04/24.04 LTS, Debian 13/12,
  and points to SPEC B.6. Documentation only.
- OL6 kickstart (`EOF_OL6_KS`) now validates cleanly against the OL6
  anaconda-13 command set (`ksvalidator -v RHEL6`). It previously carried
  OL7-only syntax inherited from the `ol7-ks.cfg` mirror, which halted the OL6
  install at kickstart parse time — before any disk write, and invisibly under
  the old headless default (the build just waited out its 30-minute timeout).
  Removed `bootloader --boot-drive=sda` (`--boot-drive` is RHEL7+/anaconda-19+
  only) and changed the bare `rootpw --lock` to `rootpw --lock --iscrypted '*'`
  (RHEL6 requires a password argument). Also removed `iptables-services` from
  `%packages`: it is a RHEL7+ package absent on OL6 (the `iptables` package
  itself provides the service) — a runtime package-selection fix that syntax
  validation cannot catch. `timezone --isUtc`, `part --label`, and `cmdline`
  were verified valid on RHEL6 and left unchanged. (The OL6 root filesystem was
  subsequently pinned to `ext4` — see the OL6 ext4 entry below — after a live
  install proved anaconda-13 refuses an xfs root; the xfs-root question raised
  here is now settled. See SPEC D.16/D.18.)
- Phase 5 no longer aborts on a non-SELinux build host. On Debian / Ubuntu the
  `libguestfs` build omits the `selinuxrelabel` optgroup (compiled out of
  `guestfsd`; no host package enables it), so upstream `bin/build-image.sh`'s
  host-side `guestfish selinux-relabel` failed with `selinuxrelabel: group not
  available`. `phase3_clone_repository` now patches upstream (host-OS- and
  OL-version-independent, grep-guarded, idempotent): it probes the optgroup with
  a standalone `guestfish` and, when it is unavailable, schedules a guest
  first-boot relabel (`touch /.autorelabel` via a standalone `guestfish -i`
  session) and skips the entire upstream relabel block, including the
  `--selinux --listen` session. The standalone sessions are required because
  that listening session is torn down on optgroup-less hosts and cannot be
  reused. The resulting AMI is still `SELINUX=enforcing`. On SELinux-capable
  hosts (RHEL / OL / Fedora) the optgroup is present and the original relabel
  runs unchanged (the patch is a no-op there). See SPEC D.17 and B.6.
- OL7 builds no longer abort in the cloud provisioner at "Install amazon/ena
  module". The upstream `cloud/aws/provision.sh` runs `yum install
  kernel-uek-modules`, but the separate `kernel-uek-modules` package exists
  only from UEK R7 (OL8+); OL7's UEK R6 (and OL6's UEK R4) bundle all modules,
  including `amazon/ena`, in `kernel-uek`, so the install failed with "Error:
  Nothing to do". The `phase3_clone_repository` guard that skipped this install
  is now applied for OL6 **and** OL7 (previously OL6 only) and gates on
  `ORACLE_RELEASE >= 8` (previously the boundary was mistakenly `>= 7`). OL8+ is
  unaffected. `ena.ko` is already present from `kernel-uek` on OL6/OL7, so no
  driver is lost. See SPEC D.11.
