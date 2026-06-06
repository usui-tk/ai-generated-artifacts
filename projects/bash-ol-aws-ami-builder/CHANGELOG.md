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
