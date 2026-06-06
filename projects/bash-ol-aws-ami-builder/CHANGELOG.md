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

### Changed

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
