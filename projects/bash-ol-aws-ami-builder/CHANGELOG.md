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

### Fixed

- **ENA matrix harness: a single build emitting no `[result]` line no longer
  aborts the whole run.** In `run-ena-buildtest-matrix.sh`, `run_one_buildtest`
  ended with a `grep … [result]` whose no-match exit (under `set -o pipefail`)
  propagated through the `rjson="$(…)"` command substitution and, under `set -e`,
  silently terminated the entire matrix — so a build whose `install-ena-driver.sh`
  exited before its `die` handler (or whose `unshare`/`chroot` failed) killed the
  run instead of being recorded. The result grep is now no-match-tolerant and the
  call site is `… || true`, so an empty result falls through to the existing
  synthetic-`fail` path and the matrix continues to the next version/OL. In
  addition, any non-`ok` build's full log is now preserved to
  `<cleancore-dir>/buildtest-ol<N>-ena<ver>.log` (and the path is logged) so the
  cause is diagnosable. Verified in-env: a no-result build is recorded as a
  synthetic fail and the run continues; a real OL6 run (`2.9.1` ok + `2.2.0` fail)
  completes with `MATRIX_EXIT=0`, the fail log preserved.

- **OL6 clean-core: gate the NSS dynamic CA trust workaround to the sandbox.**
  `build-cleancore-ol6.sh` step (C) (`update-ca-trust enable`/`extract`) and its
  `NSS dynamic CA trust enabled (TLS verifiable)` self-test row are a workaround
  for the Claude build sandbox's intercepting (MITM) egress proxy. On a real host
  (physical / VM) there is no such proxy, EL6 `update-ca-trust` aborts internally
  (`rpm: command not found` in the chroot) so the dynamic-trust symlink is never
  created, and the self-test row FAILed — failing the whole clean-core build (and
  with it the ENA matrix). The step + row are now gated on a sandbox check
  (auto-detected via `IS_SANDBOX` or the egress-gateway CA on the build host;
  explicit override `CLEANCORE_CATRUST=on|off`): in the sandbox they run and
  assert exactly as before (self-test still 20/0/0); on a real host the step is
  skipped and the row records a SKIP (self-test 19/0/1) so the build succeeds and
  uses the clean-core's standard `ca-certificates` bundle for standard-CA TLS.
  OL7–OL10 builders are unaffected (only OL6 carries this EL6-specific step).

### Added

- **ENA self-build test matrix (`tests/ena/run-ena-buildtest-matrix.sh`).** A
  self-contained harness (inline helpers, no shared library — repo policy for
  user-run scripts) that runs `ENA_BUILDTEST` across an **OS major × ENA version
  × kernel** grid for OL6/7/8, driving the existing pieces as separate
  executables (`tests/cleancore/build-cleancore.sh` for the rootfs,
  `install-ena-driver.sh ENA_BUILDTEST=1` for each version). The ENA set defaults
  to the full release list and is narrowable (`--ena-versions`, `--pinned-only`)
  so a few cases run locally while the full matrix is for the user's env / CI.
  Two committed evidence layers double as the **dedup state**:
  `tests/ena/buildtest-ledger.json` keyed on `(osmajor, ena_version, kver)` with
  kver primary (a combo already present — pass **or** fail — is skipped; a new
  kernel re-tests all; a new ENA release tests only the diff), and per-OS
  `tests/ena/RESULTS-ol<N>.md` reports regenerated newest-kernel-first (a `fail`
  is recorded evidence, not a harness error → the run still exits 0). Ships an
  in-environment sample ledger / `RESULTS-ol6.md` (OL6: `2.9.1` ok + `2.2.0` fail
  on UEK4 `4.1.12-124.48.6.el6uek`). Manual / on-demand and **not** a
  `run-all.sh` tier; B-T1/B-T2 parse/lint it, so the host suite goes 204/0 →
  **206/0** (B-T1 32→33, B-T2 27→28). `SPEC.md` B.9 and `TESTING.md` document it.
  Third / last of the ENA self-build test-matrix pieces.

- **Clean-core build orchestrator (`tests/cleancore/build-cleancore.sh`).** A
  self-contained wrapper (inline helpers, no shared library — repo policy for
  user-run scripts) over the per-OL clean-core builders: `--ol <N>` builds one,
  `--all` builds every OL that has a `build-cleancore-ol<N>.sh` (ascending;
  `--continue` to keep going past a failing OL), writing
  `<out-dir>/cleancore-ol<N>.tar.gz` (default out-dir `./cleancore-out`). It
  **invokes each builder as a separate executable** (never sources it), so a
  builder stays the single source of truth for its own OL. It recognises the
  SPEC B.6 build-host matrix (RHEL-family 10|9, Fedora 44|43, Ubuntu 26.04|24.04,
  Debian 13|12 — the AMI pipeline's supported execution environments and the
  `ubuntu-latest` CI target) and only **warns** on a host outside it (a
  clean-core build is userland-only, hence host-agnostic), while it
  **hard-fails** on a missing prerequisite (root + the
  `unshare`/`chroot`/`mknod`/`curl`/`tar`/`xz`/`gzip`/`truncate`/`find`
  toolchain). Like the builders it is manual / on-demand and **not** a
  `run-all.sh` tier; B-T1/B-T2 parse/lint it like any `.sh`, so the host suite
  goes 202/0 → **204/0** (B-T1 31→32, B-T2 26→27). `SPEC.md` B.8 and `TESTING.md`
  document it. Second of the ENA self-build test-matrix pieces (the matrix
  harness follows).

- **ENA driver release-list collector (`tests/ena/list-ena-releases.sh`).** Reads
  the Amazon ENA Linux driver version list from the `amzn-drivers` GitHub repo and
  writes the static snapshot `tests/ena/ena-driver-releases.json` (70 versions at
  capture: `1.1.2` … `2.17.0`), each with its deterministic source `tarball_url`
  **and an explicit availability pre-check of that URL** (`tarball_available` +
  `tarball_http_status`; all 70 verified `200` at capture). The probe is a
  self-contained `url_check_status()` function inlined in the script (repo policy:
  user-run scripts are self-contained; reuse is by copy) so the same
  existence/fetchability check can be copied into other download-gated tests
  (e.g. the AWS SSM Agent RPM). `SKIP_TARBALL_CHECK=1` runs list-only.
  This is the **input** to the forthcoming ENA self-build test matrix (the
  `{OS major × ENA version × kernel}` ledger consumes the `versions[]` array).
  The authoritative source is the `ena_linux_<ver>` git tags read via
  **`git ls-remote --tags`** (git protocol) — NOT the GitHub REST API, which is
  rate-limited to 60 req/h unauthenticated and shared-IP-exhausted on CI / the
  sandbox (`403`). The JSON embeds **no timestamp**, so re-running changes it only
  when the upstream tag set changes (`git diff` then shows exactly the new ENA
  releases — the "test the diff" signal). Network-dependent and **not** a
  `run-all.sh` tier; B-T1/B-T2 parse/lint it like any `.sh`, so the host suite
  goes 200/0 → **202/0** (B-T1 30→31, B-T2 25→26). `TESTING.md` documents the
  tool. First of the ENA self-build test-matrix pieces (clean-core build
  orchestrator and the matrix harness follow).

- **ENA driver container compile-test mode (`ENA_BUILDTEST=1`, OL6/OL7/OL8).** Runs
  `install-ena-driver.sh` inside a disposable, kernel-less clean-core container
  by provisioning a full `kernel-uek` + headers up front, after which the
  production build path (kver detection, `kernel-uek-devel` resolve, DKMS
  build+install, `ena.ko` verify) runs unchanged — the driver actually compiles
  and installs. Validated end-to-end: `ena.ko` 2.9.1g on OL6/UEK4
  `4.1.12-124.48.6.el6uek`, `ena.ko.xz` 2.17.0g on OL7/UEK6
  `5.4.17-2136.338.4.2.el7uek`, and `ena.ko.xz` 2.17.0g on OL8/UEK6
  `5.4.17-2136.356.4.2.el8uek`. The kernel-provision step is per-OS (literal):
  OL6 enables the Fedora-archive EPEL + `ol6_UEKR4`; OL7 enables
  `ol7_developer_EPEL` + `ol7_UEKR6`; OL8 (slim base ships `dnf` only)
  bootstraps the `yum` compat via `dnf`, then `ol8_developer_EPEL` + `ol8_UEKR6`.
  Production is unaffected: the switch defaults off and the log/build paths are
  byte-identical when it is. Includes environment-tagged logging
  (`[ena-driver][buildtest]…`), an `INSECURE_TLS=1` knob (default 0; relaxes TLS
  only for the test-mode network commands — e.g. behind a MITM dev proxy or EL6
  NSS trust gaps), and a machine-parseable result line
  `[ena-driver][buildtest][result] {…}` (JSON: `status=ok|fail` plus
  `osmajor`/`ena_version`/`kver`/`ko`/`ko_version`, agreeing with the exit code)
  for a test harness / build ledger. A host test tier follows.
- **Standalone OL8 ENA self-build (`install-ena-driver.sh`).** OL8 now builds the
  pinned ENA driver (`ena_linux 2.17.0`, same as OL7's UEK6) when the installer is
  run on its own (VM or container test). The AMI pipeline is **not** affected:
  `build-ol-aws-ami.sh` gates the provision.sh self-build hook *and* the
  `-ena<ver>` AMI name/description suffix to OL6/OL7, so OL8+ AMIs are produced
  with their current in-distro ENA driver (unmodified). This also corrects the
  prior OL8 AMI naming, which appended an empty `-ena` suffix while the installer
  no-op'd. OL9+ remain a no-op in the installer.
- **Container clean-core test base (`tests/cleancore/`).** Five self-contained
  builders — `build-cleancore-ol6.sh` / `-ol7.sh` / `-ol8.sh` / `-ol9.sh` /
  `-ol10.sh` — each producing a clean-core Oracle Linux container rootfs for one
  OL major, as a reusable developer/CI test base (repo-availability, guest
  provisioning shell logic, ENA compile-tests, upstream-drift structural checks).
  Tagged `[A] HOST` / `[B] BUILDER` (throwaway, EL-native, build-use only) /
  `[C] CLEAN-CORE` (the `.tar.gz` deliverable from a `yum`/`dnf --installroot`
  transaction against `yum.oracle.com`). The builder is EL-native so the
  in-guest rpm reads the rpmdb (OL6 stays rpm 4.8 / db4 forever, so an EL6-native
  builder is mandatory; the OL6.6 builder is TLS-modernized first). Package set
  is the upstream `distr/ol{7,8,9,10}-slim` kickstart for OL7-OL10 and the
  project's own `EOF_OL6_KS` heredoc for OL6.
  - **Not** part of the AMI build pipeline and **not** run by `tests/run-all.sh`
    (a run needs root + network + a large build); covered by B-T1 (parse) +
    B-T2 (`shellcheck -S style`) like every `.sh`, raising those tiers to
    **30** and **25** asserts respectively. Suite 190/0/0 → **200/0/0** (with
    `ksvalidator`; 199/1/0 without).
  - Documented in `SPEC.md` **B.8** (canonical reference) + Part C static-checks
    pointer, and `TESTING.md` ("Container clean-core test base" + coverage-ledger
    row + environment dependencies). The container shares the host kernel (no
    `/dev/kvm`), so this base covers the guest userland only — not the VM
    build/boot, which stays on the Fedora KVM host (B-T7/B-T8).
  - The package set is kickstart-derived (faithful to the VM image) and so
    over-includes for a pure container; trimming it to a container-appropriate
    set is tracked as separate follow-on work.
  - Doc drift corrected in passing: the B-T1 coverage-ledger note read a stale
    `13 asserts` (the live count was 25); set to the accurate **30**.

- **OL7 build-log visibility (feedback ④).** A long, near-silent in-guest ENA
  DKMS compile made OL7 builds look stalled. The wrapper now surfaces live
  progress and preserves a build record:
  - *Live heartbeat stage (B):* `log_external` records the latest `build-image.sh`
    orchestrator line to a `BUILD_STAGE_FILE` (`${WORKSPACE}/.build-stage`), and
    the Phase-5 heartbeat appends a `stage: …` field. During the quiet compile the
    heartbeat shows the customize step + growing elapsed time + disk `+0MB`, i.e.
    "alive but quiet" rather than a suspected hang. (The in-guest provision.sh
    output is swallowed by virt-customize on success, so the orchestrator stream —
    not the guest's own lines — is the only live signal.)
  - *In-guest stage breadcrumbs (C):* `install-ena-driver.sh` gains a `stage()`
    helper emitting `[ena-driver][stage]` markers at the phase boundaries
    (prereqs, kernel-devel, EPEL+dkms, download, dkms add/build/install). On a
    failed build these pin which sub-step broke.
  - *Preserved make.log (D):* `record_make_log()` copies the DKMS make.log to
    `/var/log/ol-aws-ami-builder-ena-make.log` on a successful build, so the
    compile record ships inside the AMI for post-hoc inspection (guest output is
    otherwise discarded on success; on failure `dump_build_diag` still surfaces it).
  - New regression tier `tests/t12_buildvisibility.sh` (17 asserts) guards all of
    the above. Suite 171/0/0 → **190/0/0** (with `ksvalidator`).

- **OL9/OL10 clean-core package SBOMs + official-image reference memo.** Static
  snapshots under `tests/cleancore/`: `cleancore-ol9.sbom.json` (186 packages)
  and `cleancore-ol10.sbom.json` (177 packages) record each finalized
  clean-core's package set names-only as reusable JSON, and
  `REFERENCE-oracle-official-images.md` documents the official `ol9-slim` /
  `ol10-slim` images' sources, pinned `container-images` commit, and
  name-version manifests (107 / 96 packages — the reference footprints the
  clean-cores derive from). Neither is a `.sh`, so both sit outside B-T1/B-T2
  and are not drift-checked gates.

- **OL8 clean-core package SBOM + official-image reference (OL8 section).** Static
  snapshot `tests/cleancore/cleancore-ol8.sbom.json` (206 packages) records the
  finalized OL8 clean-core's package set names-only as reusable JSON, and an
  Oracle Linux 8 section is added to `REFERENCE-oracle-official-images.md` (the
  official `ol8-slim` image's sources, pinned `container-images` commit, and
  103-package name-version manifest — the reference footprint the clean-core
  derives from). Neither is a `.sh`, so both sit outside B-T1/B-T2 and are not
  drift-checked gates.

- **OL7 clean-core package SBOM + official-image reference (OL7 section).** Static
  snapshot `tests/cleancore/cleancore-ol7.sbom.json` (198 packages) records the
  finalized OL7 clean-core's package set names-only as reusable JSON, and an
  Oracle Linux 7 section is added to `REFERENCE-oracle-official-images.md` (the
  official `ol7-slim` image's sources, pinned `container-images` commit, and
  108-package name-version manifest — the reference footprint the clean-core
  derives from). Neither is a `.sh`, so both sit outside B-T1/B-T2 and are not
  drift-checked gates.

- **OL6 clean-core package SBOM + official-image reference (OL6 section).** Static
  snapshot `tests/cleancore/cleancore-ol6.sbom.json` (165 packages) records the
  finalized OL6 clean-core's package set names-only as reusable JSON, and an
  Oracle Linux 6 section is added to `REFERENCE-oracle-official-images.md`. Unlike
  the slim variants there is no upstream `ol6-slim`, so the reference records the
  official `oraclelinux:6.6` image's sources and its 165-package name-version
  manifest — the base footprint the EL6-native builder runs from (the clean-core
  is a fresh curated install, not a trim of that image). Neither is a `.sh`, so
  both sit outside B-T1/B-T2 and are not drift-checked gates.

### Changed

- **`jq` added to every clean-core container builder (`tests/cleancore/`).** Each
  `build-cleancore-ol{6,7,8,9,10}.sh` now installs `jq` as a curated test-base
  essential. Per-OS repo routing (per the maintainer's instruction): OL7/OL8/OL9/
  OL10 take it from the **standard OL repo** (already enabled — `latest` on OL7,
  `appstream` on OL8/9/10), so it is simply added to the `INCLUDE` set; OL6 — where
  `jq` is not in the base repo but is an **EPEL** package — installs it from the
  **EPEL archive** in finalize by enabling EPEL **transiently for that one
  transaction** (`--enablerepo=epel`), so the shipped EPEL repo stays `enabled=0`
  (unchanged from the documented OL6 EPEL handling). Each builder's unconditional
  self-test now asserts `jq --version` runs in the finalized image. Builders are
  parse/lint-only under B-T1/B-T2 (not run by `run-all.sh`), so the host suite stays
  **200/0/0**. SPEC **B.8** (Package set) and `TESTING.md` (clean-core section)
  updated. **NOTE:** the names-only SBOM snapshots
  `tests/cleancore/cleancore-ol<MAJOR>.sbom.json` are produced from a real build's
  `rpm -qa` (SPEC B.8: "refreshed by hand when the package set changes"; static
  snapshots, not drift-checked gates) and are **regenerated on the next real
  clean-core build**, which captures `jq` plus its transitive closure
  (e.g. `oniguruma`); they are intentionally not hand-edited here.
- **OL9 and OL10 clean-core trimmed to a slim-aligned set (was kickstart-derived).**
  `build-cleancore-ol{9,10}.sh` now drop `@core` (so no kernel/boot/firewall/cron/
  syslog) and install a minimal userland plus explicit test-base essentials:
  `git-core` instead of `git` (avoiding ~60 `perl-*` packages), no `net-tools`,
  archive/network/troubleshooting tools, and `dnf-plugins-core` + `yum-utils`
  (EL9/EL10 have no standalone `dnf-utils`; `yum-utils` provides it). The Oracle
  EPEL repo is installed but **finalized to `enabled=0`** so the ENA/SSM
  harnesses enable it explicitly (e.g. for `dkms`). `systemd` is a hard
  dependency of full `dnf` (plus `pam`/`sudo` on EL10) and is therefore present,
  but never PID 1 in container/chroot use. Result: OL10 245 → **177 pkgs**
  (445M → **316M**); OL9 `@core`-set → **186 pkgs / 313M**. Each self-test's
  `sshd present` assertion is flipped to `sshd absent` (the slim-aligned base
  ships no `openssh-server`). OL6 remains kickstart-derived pending its own
  pass.

- **OL8 clean-core trimmed to a slim-aligned set (was kickstart-derived).**
  `build-cleancore-ol8.sh` now drops `@core` and installs a minimal userland plus
  explicit test-base essentials, matching the OL9/OL10 pass: `git-core` instead of
  `git` (avoiding ~60 `perl-*` packages), no `net-tools`, archive/network/
  troubleshooting tools, and `dnf-plugins-core` + `yum-utils` (EL8 has no standalone
  `dnf-utils`; `yum-utils` provides it). The Oracle EPEL repo is installed but
  **finalized to `enabled=0`**. `systemd` is a hard dependency of full `dnf` (plus
  `pam`/`sudo` on EL8) and is therefore present, but never PID 1 in container/chroot
  use. **EL8-specific:** a raw EL8 `dnf` with no langpack selection defaults to
  `glibc-all-langpacks` (~416 MB of world locales), which the official `ol8-slim`
  does not ship — the builder pins `glibc-minimal-langpack` and excludes
  `glibc-all-langpacks` to match the slim reference. Result: `@core`-set 278 pkgs /
  697M → **206 pkgs / 346M** (tarball 120M). The self-test `sshd present` assertion
  is flipped to `sshd absent`. OL6 and OL7 remain kickstart-derived pending their own
  passes.

- **OL7 clean-core trimmed to a slim-aligned set (was kickstart-derived).**
  `build-cleancore-ol7.sh` now drops `@core` and installs a minimal userland plus
  explicit test-base essentials, matching the OL8-OL10 pass. EL7-specific
  differences (vs the dnf-based OL8-OL10): the manager is `yum` (no `dnf`, so no
  `dnf-plugins-core` — `yum-utils` only); there is no `glibc` langpack split, so no
  langpack pin; `git` is plain `git` (EL7 has no `git-core` split; it pulls ~30
  `perl-*` packages — kept for tool parity with the other OLs, per maintainer
  choice); `git-lfs` and the `zstd` CLI are EPEL-only/absent in the EL7 base repos
  so they are not installed (available on demand from the shipped-disabled EPEL
  repo); and the base `oraclelinux-release` (which provides `/etc/oracle-release`)
  is listed explicitly because EL7's `oraclelinux-release-el7` does not pull it.
  The Oracle EPEL repo is installed but **finalized to `enabled=0`**. `systemd` is
  pulled transitively by `iputils`/`procps-ng` and is therefore present, but never
  PID 1 in container/chroot use. Result: `@core`-set 261 pkgs / 556M → **198 pkgs /
  448M** (tarball 137M). The self-test `sshd present` assertion is flipped to
  `sshd absent`. OL6 remains kickstart-derived pending its own pass.

- **OL6 clean-core trimmed to a slim-aligned set (was kickstart-derived); completes
  the OL6-OL10 pass.** `build-cleancore-ol6.sh` now drops `@core` and installs a
  minimal userland plus explicit test-base essentials. EL6-specific differences:
  the manager is `yum`; `git` is plain `git` (EL6 has no `git-core` split);
  `procps`/`nc` replace `procps-ng`/`nmap-ncat`; and — uniquely among the
  clean-cores — `net-tools` is **included**, because EL6 has no standalone
  `hostname` package (the command ships in `net-tools`). EPEL 6 is EOL and Oracle
  hosts none, so finalize (C) enables the NSS dynamic CA trust — EL6's `curl`/`yum`
  are NSS-backed and verify no TLS until `update-ca-trust enable` is run, so no
  https repo (EPEL or the OL6 base on `yum.oracle.com`) is usable on a real host
  without it — then (B) fetches the EPEL 6 release RPM from the Fedora community
  archive with the clean-core's own `curl` and installs it with its own `rpm`
  (EL6 `yum` cannot fetch a direct https package URL), and the repo is repointed to
  the archive and **`enabled=0`**. `systemd` does not apply (EL6 is upstart).
  Result: the former `@core`/kickstart-derived set → **165 pkgs / 383M**. The
  self-test gains `EPEL present` / `EPEL enabled=0` / `EPEL baseurl→archive` and
  `NSS dynamic CA trust enabled` rows and flips `sshd present` to `sshd absent`
  (**19** checks total).

- **`HEARTBEAT_INTERVAL_SEC` default `20` → `10` seconds** (feedback ④; `0` still
  disables). A shorter interval makes the live `stage:` field and elapsed/disk
  deltas more responsive during a quiet in-guest compile; matches the runtime
  disambiguation recommended in the prior session's diagnosis.

- **OL7/OL8 E2E feedback — ENA driver reporting, AMI identification, pin-log accuracy.**
  - *Phase 6 ENA report (feedback ①②):* the two driver lines are now aligned,
    fixed-width headers — `ENA Driver (Kernel in-box) - ...` and
    `ENA Driver (Self-Build)    - ...` — so the in-box vs self-built version delta
    is legible at a glance. When the in-tree module exposes no `modinfo` version
    field (OL7/OL8 in-tree ENA), the in-box line now reads
    `in-tree, no version field (kernel-bundled)` instead of a bare `none`.
    `install-ena-driver.sh` additionally logs the in-box ENA identity
    (`version`/`srcversion`/`file`) for the target kernel BEFORE the self-build
    replaces it.
  - *AMI identification (feedback ③):* when the ENA self-build is enabled
    (default), the auto `AMI_NAME` gains an `-ena${ENA_BUILD_VERSION}` suffix and
    `AMI_DESCRIPTION` a self-built-ENA clause, so a self-built AMI is
    distinguishable from a pure OL AMI before launch; the final summary now prints
    `AMI Description:` and an `ENA driver:` line. An explicitly set
    name/description is left untouched.
  - *Pin-log accuracy (drift):* the Phase-3 `[OLAWS-ENA01]` hook-injection log no
    longer hardcodes `OL6 2.5.0` (stale since the OL6 pin moved to `2.9.1`); it now
    reports `pin: OL<major> <version>` read from `install-ena-driver.sh`'s
    `ENA_VERSION_OL<major>` default (single source of truth), so it cannot drift
    again. The AMI name/description share this reader (`ENA_BUILD_VERSION`).
  Guarded by a new host-runnable tier `tests/t11_enareporting.sh`. `bash -n` +
  `shellcheck -S style` clean.

### Fixed

- **Final-summary "ENA driver:" line now reports stock in-box for OL8+ pure-OL builds.** The completion summary computed its ENA line from `ENA_DRIVER_BUILD` alone, so an OL8/9/10 build (where the self-build hook is gated off — OL8+ keep their in-distro ENA) still printed `self-built … (DKMS, AWS-optimized)`, contradicting the Phase-3 "hook not injected" log, the Phase-6 "stock in-tree" provenance, and the AMI description's `(pure OL; ENA self-build skipped)`. The summary now mirrors the AMI-description gate (`ENA_DRIVER_BUILD=1` **and** OL6/OL7), so OL8+ correctly report `stock in-box (pure OL AMI)`; OL6/OL7 self-builds and `--skip-ena-driver` are unchanged. Summary-text only — no gate, build, or AMI behaviour change.

- **CHECK 4 & CHECK 5 now resolve the OL8 `$kernelopts` indirection — fixes false INDETERMINATE/ADVISORY.** The OL8 E2E showed CHECK 4 INDETERMINATE and CHECK 5 ADVISORY even though the image was correct: on OL8 the BLS entry's cmdline line is `options $kernelopts` (a reference), and the real `root=`/`console=ttyS0` live in `/boot/grub2/grubenv` (`kernelopts=`). The checks read only the literal `options` line, so they saw neither value. Both checks now also read grubenv `kernelopts` (falling back to the `grub.cfg` `set kernelopts=` default) as a cmdline source. Verified against the live OL8 image data: `kernelopts=root=UUID=… console=tty0 console=ttyS0,115200n8` → CHECK 4 PASS (UUID), CHECK 5 PASS (console=ttyS0). OL6 (`grub.conf` `kernel`) and OL7 (`grub.cfg` `linux16`) have no grubenv `kernelopts` and are unaffected. Advisory/INDETERMINATE classification only — no gate or boot behaviour change. The serial-console fix itself was already correct on OL8 (grubby wrote `console=ttyS0` into `kernelopts`; GRUB_TERMINAL/SERIAL and `serial-getty@ttyS0` all applied); this only stops the checks from crying wolf. See SPEC D.25 / Part-A CHECK 4.

- **Nitro assurance report no longer lists ARM/Graviton example instance types.** The advisory
  report's per-generation "e.g." families included Graviton (ARM) types — `T4g M6g C6g R6g` (v2),
  `M7g C7g R7g` (v4), `M8g C8g R8g C7gn` and `Trn2` (v5) — which **cannot launch an x86-64 AMI**,
  so listing them as ASSURED was misleading. This builder produces x86-64 AMIs; the example lists
  now show x86-64 families only (v2 `M5 C5 R5 T3`; v4 `M6i M7i C6i C7i R6i R7i I4i`; v5 `I7ie P5en`;
  v3/v6 unchanged). Advisory-text only — no boot-check or gate behaviour changes. See SPEC Part-A
  (Nitro instance assurance report).

- **CHECK 4 (bootloader `root=`) is now BLS-aware — closes a silent false-PASS on OL8/9/10.** The
  Phase-6 assurance check scanned only `grub.cfg` menuentries (`linux`/`linux16`/`kernel`) for
  `root=`. On OL8+ (BLS) the kernel cmdline — including `root=` — lives in
  `/boot/loader/entries/*.conf` (`options`), not in `grub.cfg`, so the scan found nothing and
  reported PASS **without inspecting the real cmdline** (a device-name `root=/dev/xvda1` would have
  slipped through). CHECK 4 now also reads the BLS `options` lines, and reports INDETERMINATE
  (not a vacuous PASS) when no `root=` is found in either source. OL6/OL7 behaviour is unchanged.
  Extraction + device-name detection validated in isolation (BLS LVM/UUID/device-name, OL7
  `linux16`, OL6 `kernel`); VM-path re-validation is the maintainer's. See SPEC Part-A CHECK 4.

- **Serial console now persists on OL8/9/10 (BLS), plus the full AWS-recommended config.** The
  OL6–OL10 E2E run found `console=ttyS0` missing from the kernel cmdline on OL8/9/10 (CHECK 5
  ADVISORY; AWS `Get System Log` empty). Root cause: OL8+ enable the GRUB BootLoaderSpec, so the
  kernel cmdline lives in `/boot/loader/entries/*.conf`, which a plain `grub2-mkconfig` does not
  rewrite (the OL7-era hook only edited `GRUB_CMDLINE_LINUX` + ran `grub2-mkconfig`). The
  serial-console hook now applies the AWS-recommended config in three layers across OL6–OL10:
  (1) cmdline `console=tty0 console=ttyS0,115200n8` on every entry — OL7–10 via
  `grubby --update-kernel=ALL` (BLS-aware, version-stable; avoids the `--update-bls-cmdline` 8.x/9.2+
  matrix) plus `GRUB_CMDLINE_LINUX` for future kernels; OL6 via its existing kickstart append;
  (2) GRUB-over-serial — OL7–10 `GRUB_TERMINAL="console serial"` + `GRUB_SERIAL_COMMAND` (+
  `grub2-mkconfig`), OL6 `serial`/`terminal` directives in `grub.conf`; (3) `serial-getty@ttyS0`
  enabled on OL7–10 (symlink fallback for the offline build). CHECK 5 is now **BLS-aware**: it
  inspects both `grub.cfg` menuentries and `/boot/loader/entries/*.conf` `options`. OL6 cmdline and
  OL7 behaviour are unchanged (per-OS isolation); VM-path re-validation across OL6–OL10 is the
  maintainer's. See SPEC D.25.

- **Executable bit normalized on directly-runnable scripts (no content change).** Git tracks the
  POSIX exec bit per file; several scripts had been committed `100644`, so a fresh clone left them
  non-executable while `install-ena-driver.sh` and most test tiers were `100755`. Set mode `100755`
  on the scripts that carry a `#!/usr/bin/env bash` shebang and are invoked directly:
  `build-ol-aws-ami.sh`, `setup-vmimport-role.sh`, and the test tiers `tests/t9_logformat.sh`,
  `tests/t10_enaukedetect.sh`, `tests/t11_enareporting.sh`. The sourced libraries
  `tests/lib/{assert,heredoc,mock}.sh` (loaded via `.`, no shebang, `# shellcheck shell=bash`)
  deliberately stay `100644`. The suite is unaffected (`tests/run-all.sh` invokes tiers via
  `bash "${tier}"`); this only fixes `./script` / `git clone` ergonomics.

- **Docs (no behaviour change):** the **English README intro** had drifted from
  its `README.ja.md` twin and from SPEC. (D3) The OL7 sentence linked only to
  section 1 and section 10, omitting the **section 9.6** cross-reference its
  Japanese twin carries (and that the OL6 sentence carries for 9.7); the EN now
  links section 9.6 too. (D4) The OL6 sentence said the wrapper "synthesizes
  **one** `distr/ol6-slim/`" whereas the Japanese twin and SPEC B.4 say it
  synthesizes the directory's **four files** (`env.properties`, `image-scripts.sh`,
  `ol6-ks.cfg`, `provision.sh`); the EN now states "the entire `distr/ol6-slim/`
  directory (four files)". The Japanese twin already had the correct content, so
  this brings the pair back into lock-step (heading counts unchanged: 16 `##` /
  37 `###`).

- **Docs (no behaviour change):** SPEC **B.4 (Wrapper-patch marker convention)**
  had drifted behind the implementation. The "Current markers" table listed only
  3 of the 8 marker-guarded patches the script actually applies in
  `phase3_clone_repository` — it was missing `declare-g-ol6`, `ol6-cloud-user`,
  `nitro-initramfs`, `serial-console`, `ena-driver-build`, and
  `selinux-relabel-fallback` (the first three had **no** marker-tag mention
  anywhere in the SPEC). The "canonical marker format" line described a single
  `[ol-aws-ami-builder OL{N} PATCH {short-tag}]` shape that no marker actually
  uses, and "Each patch leaves a `.bak` backup" was true only for the `sed`-based
  patches, not the `>>`-appended hook injections. The table now lists all 8
  markers with file-patched / trigger / purpose (cross-referencing D.17/D.25/D.26
  and A.7), documents the two real marker shapes, and states the `.bak` vs
  append distinction. SPEC-only: the README does not restate the marker tags and
  `tests/t7_idempotency.sh` already enumerates all 7 named markers.

- **Docs (no behaviour change):** SPEC **B.5.2 (Phase A static check #9)**
  contradicted the rest of the document on the OL6 cloud-init version. Check #9
  presented `cloud-init-18.4-2.0.9.el6.x86_64` (the `ol6_addons` build) as the
  OL6 cloud-init, but the **operative** version everywhere else — the IMDSv2
  rejection (D.27), the `ec2-user` fix verified against `cloud-init-0.7.5-8.el6_9.2`
  (D.26), the `cloud.cfg.d` merge semantics (B.5), and the README pair — is the
  stock base-repo **0.7.5**. Check #9 now leads with the operative 0.7.5 (the
  version every OL6 hook targets) and reframes the `ol6_addons` 18.4 as available
  but not relied upon, removing the internal contradiction. SPEC-only.

- **OL6: the in-guest ENA self-build failed with `kcompat.h: ... redefinition of
  'page_ref_count'`** even at the pinned `2.9.1`, so an AWS-optimized OL6 AMI
  could not be built (a pure `--skip-ena-driver` AMI was unaffected). The
  amzn-drivers ENA `Makefile` derives `IS_UEK` and `ENA_KERNEL_SUBVERSION_*` from
  `uname -r` (the *running* kernel), and those gate the `kcompat.h` guard that
  skips redefining `page_ref_count` on UEK4 kernels carrying Oracle's backport
  (`>= 4.1.12-124.43.1`). During provisioning the DKMS build runs under the
  libguestfs appliance, whose `uname -r` is the non-UEK appliance kernel, so the
  macros were unset and the driver redefined `page_ref_count` against the
  backported `4.1.12-124.48.6.el6uek` target — a collision the version pin cannot
  avoid. (This is why the self-build succeeded **standalone** on a live OL6
  instance, where `uname -r` is the real UEK kernel, yet failed in the image
  build.) `install-ena-driver.sh` now patches the amzn-drivers `Makefile`
  (OL6-only, per-OS isolation) to derive that detection from `BUILD_KERNEL` (the
  DKMS target the build already passes) instead of `uname -r`, so the guard
  evaluates against the target kernel; the patch is fronted by a `grep -Fq`
  idempotency guard and leaves a `.uek-detect.bak` backup. OL7/UEKR6 (`>= 4.6`)
  compiles the `page_ref_count` block out regardless and its Makefile is left
  untouched. Verified at the logic level (preprocessor: the guard flips
  define→skip once the target-kernel UEK macros are supplied; the version pin is
  not the cause); end-to-end build/boot confirmation is the build-host E2E
  (B-T7/B-T8). **Doc drift corrected:** SPEC A.7's "OL6/UEK4 buildable window"
  *Floor* note said the `>= 2.8.6` driver-side fix resolves the redefinition, but
  omitted that the fix is conditional on the build detecting UEK (`IS_UEK`), which
  fails under the libguestfs `uname -r`; A.7 now records that condition and the
  cross-kernel retarget. Pin unchanged (`2.9.1`). A new host-runnable regression
  tier (`tests/t10_enaukedetect.sh`) guards the retarget. `bash -n` +
  `shellcheck -S style` clean.

- **OL6: the `ec2-user` cloud-init hook never actually applied (it ran too
  early).** A rebuilt OL6 AMI was still unreachable over SSH after the fix above:
  a launched instance showed `ec2-user` absent (`id: ec2-user: No such user`),
  `90_ol.cfg` still carrying `groups: [adm, systemd-journal]`, and the stock
  `cloud.cfg` still reading `name: cloud-user` — i.e. neither edit had been made.
  Root cause: the hook was wired by appending a **top-level** `sh …` invocation to
  `cloud/aws/provision.sh`, but `bin/provision.sh` **sources** that file (running
  top-level statements) during `load_env`, *before* it calls `cloud::provision` →
  `cloud::cloud_init`. The invocation therefore ran at source time — before
  cloud-init was installed and `cloud.cfg`/`90_ol.cfg` existed — and silently
  skipped (`no cloud-init config found`). The hook is now wired by **wrapping**
  `cloud::cloud_init` (capture via `declare -f`, redefine to call the original
  then the hook), so it fires immediately after the configs are written. Verified
  locally: the wrapped `cloud_init` runs original-then-hook (late binding), and
  the hook applies both edits against real-shaped `cloud.cfg`/`90_ol.cfg`
  (idempotent); the emitted `provision.sh` passes `bash -n`. OL6-only; OL7-10
  untouched. SPEC D.26 gains a *Wiring (timing)* note. A new host-runnable
  regression tier **B-T9** (`tests/t8_hooktiming.sh`) now guards this class: it
  asserts the injection wraps `cloud::cloud_init` (and emits no top-level
  `sh <hook>`), and behaviourally that the hook fires after `cloud_init` and
  produces `groups: [adm]` / name `ec2-user`. `bash -n` +
  `shellcheck -S style` clean; suite 128/1/0.

- **OL6: cloud-init failed to create `ec2-user`, breaking SSH access.** A
  launched OL6 AMI was unreachable over SSH; cloud-init 0.7.5 failed with
  `Failed to create user ec2-user` → `Running users-groups (cc_users_groups)
  failed` → `Applying ssh credentials failed!` (reproducible across instances).
  Root cause (verified against the `cloud-init-0.7.5-8.el6_9.2` RPM, not upstream
  inference): the upstream `cloud/aws` provisioning writes
  `/etc/cloud/cloud.cfg.d/90_ol.cfg` with `default_user.groups: [adm,
  systemd-journal]` for every OL version, and cloud-init 0.7.5 merges
  `cloud.cfg.d` over the main `cloud.cfg` with the drop-in winning — so that is
  the effective `default_user` on OL6. **OL6 has no systemd, so the
  `systemd-journal` group does not exist**, and `useradd --groups
  adm,systemd-journal ec2-user` aborts; the user (and the EC2 SSH key) is never
  created. The OL6-only Phase-3 hook `[ol-aws-ami-builder PATCH ol6-cloud-user]`
  now (1) strips `systemd-journal` from the `default_user.groups` list in
  `cloud.cfg`/`90_ol.cfg` (effective `groups` becomes `[adm]`, so `useradd`
  succeeds and `ec2-user` is created with the key), and (2) aligns
  `default_user.name` to `ec2-user` in the stock `cloud.cfg` as well. (2) is a
  verified no-op functionally — `90_ol.cfg` already sets the name and wins the
  merge, so `cloud-user` is never instantiated — but it removes the misleading
  `name: cloud-user` an operator would otherwise see when inspecting the built
  image's `cloud.cfg`. OL6-only (per-OS isolation); OL7-10 untouched (their
  `systemd-journal` group exists). SPEC D.26 rewritten to the verified root
  cause. README §9.4 and SPEC §A.7 now document the EC2 login user (`ec2-user`)
  and the authority/precedence that decides the name (OS package default
  `cloud-user` → upstream `90_ol.cfg` `name: ${CLOUD_USER}` → this builder's
  `CLOUD_USER="ec2-user"`), plus the premise that the default user is unified to
  `ec2-user` across OL6-10. `bash -n` + `shellcheck -S style` clean (incl. the
  B-T1 heredoc-body parse of the hook); suite 118/1/0.

### Changed

- **OL6 ENA self-build pin bumped `2.5.0` → `2.9.1`** (`install-ena-driver.sh`).
  The previous `2.5.0` pin does **not** build on the updated OL6 UEK4 kernel
  (`4.1.12-124.48.6.el6uek`): its `kcompat.h` redefines `page_ref_count`, which
  Oracle backported into UEK4 `>= 124.43.1` (amzn/amzn-drivers issue #210). The
  buildable window on that kernel (gcc 4.4.7) is `ena_linux` ≈ `[2.8.6, 2.9.1]`,
  validated standalone on a real Nitro OL6.10 instance (build + boot + `ena`
  module load + `eth0` up + SSH). `2.10.0`+ fail to compile: `2.10.0` introduced
  the ECC build-time API autodetect, which false-positives on this old
  kernel/toolchain and pulls in newer-kernel symbols absent here (`pci_dev_id`,
  `irq_update_affinity_hint`, `ethtool_puts`, `netif_napi_add_config`). `2.9.1`
  is the last pre-ECC release (the ceiling) and is `>= 2.2.9` (full ENAv3);
  `2.8.6` is a proven fallback. OL7 (`2.17.0`) is unchanged. SPEC A.7 ENA
  self-build section and the README script tables (both languages) updated to
  `2.9.1`; the `install-ena-driver.sh` header rationale rewritten to document the
  buildable window. `ENA_DRIVER_VERSION` still overrides per run.

- **Log line format reordered to date-first** (`build-ol-aws-ami.sh`). Every
  timestamped channel now emits the unified `YYYY-MM-DD HH:MM:SS` timestamp
  **first**, followed by the `[SEVERITY]` / source tag, then the optional
  `[OLAWS-CODE]`, then the message (previously the `[SEVERITY]` tag came first,
  then the timestamp). This applies to `log_info` / `log_warn` / `log_error` /
  `log_progress` (`[BUILD]`) / `log_debug` / `log_external` (`[EXTERNAL]`); the
  phase banner (`log_step`) remains timestamp-less. ANSI colour on the tag and
  the ANSI-stripped file mirror are unchanged, as are the stdout/stderr
  destinations. The new order lets a plain `sort` and a visual time-scan line up
  by the leading column. SPEC E.1 (and the A.4 summary) "Line format" updated to
  `YYYY-MM-DD HH:MM:SS  [SEVERITY]  [OLAWS-CODE]  <message>`; README section 6.3
  log examples (both languages) and the SPEC examples re-rendered in the new
  order. A new host-runnable regression tier **log-format**
  (`tests/t9_logformat.sh`) asserts every channel is date-first (and guards
  against a return to tag-first). `bash -n` + `shellcheck -S style` clean; suite
  142/1/0 (143/0 with `ksvalidator`).

- **Phase 6 now reports the in-box and self-built ENA driver versions on
  separate lines** (`build-ol-aws-ami.sh`). The Nitro assurance report prints an
  `in-box ENA driver` line (stock in-tree `/kernel`, or `built into the kernel
  (=y)`) and a `self-built ENA driver` line (the DKMS `/extra`|`/updates` module,
  or `not present` for a `--skip-ena-driver` / pure-OL build), each with its
  `modinfo` version. This makes the effect of the in-guest self-build explicit
  in the build log even though successful guest provisioning is otherwise silent
  (libguestfs echoes a provisioning script's output only on failure). A new
  internal helper `_ena_module_version` copies each candidate module into its own
  temp subdir (so the stock and self-built copies — same basename — do not
  collide) and `modinfo`s it. The ENAv3-tier `signal` line is unchanged and still
  reflects the effective module (depmod precedence `updates` > `extra` >
  `kernel`); the gate verdict (CHECK 1-4) is unaffected. SPEC A.7 updated. New
  code is shellcheck `-S style` clean; suite 118/1/0.

- **ENA self-build now surfaces the in-guest compiler error on failure**
  (`install-ena-driver.sh`). When the DKMS module build fails, the script now
  dumps `dkms status` and every `make.log` found under
  `/var/lib/dkms/amzn-drivers/<version>/` to stderr (each line prefixed
  `[ena-driver][ERROR]`) before `die`. `oracle-linux-image-tools` (libguestfs
  `virt-customize`) only echoes a guest provisioning script's output to the host
  log when the script fails, so previously a module-build failure left only the
  opaque "Bad return status for module build" line plus an in-guest make.log
  path the operator never saw — making a forwarded build log untriageable. The
  dump is best-effort and runs only on the failure path; the success path and
  direct execution are unchanged. New code is shellcheck `-S style` clean.

### Added

- Added the **OL6 + IMDSv2-only rejection unit** and a **B-T6 idempotency-guard
  check** (test increment 6). Extracted the inline IMDS normalisation + OL6
  rejection out of `load_env` into a new `normalize_imds_support()`
  (behaviour-neutral refactor of `build-ol-aws-ami.sh`; direct execution
  unchanged) so it can be unit tested; `tests/t3_unit.sh` now drives it
  table-driven (normalisation of `default`/`v1+v2`/`V2.0`/`v2only`, `OL6+default`
  allowed, `OL7+v2.0` allowed, invalid value -> `die`, **`OL6+v2.0` -> `die`**;
  10 asserts). Added `tests/t7_idempotency.sh` (B-T6, L2, structural): asserts
  each of the 7 `[ol-aws-ami-builder PATCH ...]` injection markers is fronted by
  a `grep -Fq` idempotency guard (runtime apply-twice remains B-T7/B-T8). Suite
  now **118 passed, 1 skipped, 0 failed**; the host-runnable tiers (L0-L2) are
  complete. New/changed scripts are shellcheck `-S style` clean.

- Added **B-T5 env-template parity** (`tests/t6_envparity.sh`, test increment 5,
  L2): data-driven checks over `env.properties.aws-ol{6,7,8,9,10}` - a 20-key
  common core in all five, the documented `KERNEL`/`UEK_RELEASE` extras present
  only in OL6/OL7, the cross-file invariants (`S3_BUCKET`, `AWS_REGION=""`,
  `UPDATE_TO_LATEST=yes`, `CLOUD=aws`), and the per-OS `DISTR=olN-slim` (31
  asserts). Also **wired B-T4 kickstart conformance into the single runner**
  (`tests/t5_kickstart.sh` wraps `tests/validate-kickstart.sh`; SKIPs without
  `ksvalidator`) - previously it was only runnable standalone. Suite now **98
  passed, 1 skipped, 0 failed** (B-T1 19 + B-T2 14 + B-T3 25 + command-mock 9 +
  env-parity 31, B-T4 kickstart skipped without ksvalidator). No change to
  `build-ol-aws-ami.sh`; new tiers are shellcheck `-S style` clean.

- Added a **command-mock + spy layer** for dependency-injection class "external
  commands" (`tests/lib/mock.sh`, `tests/t4_cmdmock.sh`, test increment 4, L1
  hermetic; self-contained PATH-shadow mocks - no bats/shellmock). `mock_setup`
  prepends a shadow bin to PATH and starts a call log; `mock_cmd NAME BEHAVIOUR`
  installs a fake that records its argv then runs the behaviour; `mock_calls`
  exposes the log for spying. Driven against `detect_qemu_user` (mocks `id`:
  qemu-present, libvirt-qemu fallback, neither-present, with call spying) and
  `detect_os_variant` (mocks `osinfo-query`: exact `ol9.6` short-id, graceful
  degradation to `rhel9.0`, and the absent-tool branch which SKIPs if the host
  has a real `osinfo-query`). Suite now **63 passed, 0 failed** (B-T1 17 +
  B-T2 12 + B-T3 25 + command-mock 9). TESTING.md ledger + dependency-injection
  matrix updated with the implementation. No change to `build-ol-aws-ami.sh`;
  new scripts are shellcheck `-S style` clean (two documented `SC2016` exemptions
  on literal mock-behaviour strings).

- Added **B-T3 pure-function unit** tests (`tests/t3_unit.sh`, test increment 3,
  test pyramid layer L1, hermetic): table-driven `parse_ol_version_from_iso`
  (OL6-OL10 + a malformed name + a full URL path) and the `parse_args` contract
  (unknown flag -> `usage 1`; missing `--env` -> `die`; valid `--env` -> rc 0 with
  `ENV_FILE` set), each exercised in an isolated subshell. To allow sourcing the
  wrapper for unit tests without running the pipeline, the tail `main "$@"` is now
  guarded by `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` - a
  2-line, **behaviour-neutral** change (direct execution is unchanged; sourcing
  defines functions with no side effects, the bash analogue of importing a
  `.psm1`). Suite now **50 passed, 0 failed** (B-T1 15 + B-T2 10 + B-T3 25). The
  `load_env` IMDS `v2.0` OL6 rejection is ledgered as a planned L1 test (needs a
  small extraction or fixture-driven run). New test script is shellcheck `-S
  style` clean.

- Added **B-T2 ShellCheck** as a deterministic static gate (`tests/t2_shellcheck.sh`,
  test increment 2): runs ShellCheck at the **canonical `-S style`** (strictest)
  over every `.sh` and asserts zero findings per file, turning ShellCheck into a
  reproducible pass/fail summary with no per-run judgement. A checked-in
  `.shellcheckrc` enables `external-sources=true` + `source-path=SCRIPTDIR` (to
  *follow* the harness's sourced libs - strengthening, not relaxing) and declares
  **no** global `disable=`. Three narrow, documented inline exemptions remain
  (each one code on one statement, with a rationale): `SC2016` at the
  SELinux-relabel sed injection and at the `bash -c '...$1...'` secure idiom in
  `build-ol-aws-ami.sh`, and `source=/dev/null` at the runtime `. /etc/os-release`
  in `install-ena-driver.sh`. Reconciled the previously split ShellCheck severity
  references in SPEC (A.11 iteration cycle, Part C checklist `--severity=error`,
  Part D, Part E `--severity=warning`) to the canonical `style` gate run via
  `tests/run-all.sh`. Suite now **23 passed, 0 failed** (B-T1 14 + B-T2 9);
  B-T2 SKIPs if shellcheck is absent. Script changes are comment-only
  (no behaviour change). ShellCheck pinned to 0.10.0 (recorded in TESTING.md).

- Added a **self-contained bash test harness** under `tests/` (the bash-idiom
  analogue of the PowerShell canon's test discipline, framework-free by policy):
  a single entry runner `tests/run-all.sh` that runs every tier, aggregates
  pass/fail/skip and exits non-zero on failure; an assertion library
  `tests/lib/assert.sh`; a heredoc-body extractor `tests/lib/heredoc.sh`; and the
  first tier **B-T1 parse** (`tests/t1_parse.sh`): `bash -n` on every `.sh` plus
  `bash -n` on each shell-bodied heredoc that ships into the guest / into
  `distr/ol6-slim/` (`OLAWS_NITRO_BODY`, `OLAWS_SERIAL_BODY`,
  `OLAWS_OL6_CLOUD_USER_BODY`, `EOF_OL6_IMG`, `EOF_OL6_PROV`) - which the outer
  parse does not cover. Current suite: **13 passed, 0 failed**. `TESTING.md`
  documents the top-down test model (5-layer pyramid + dependency-injection
  matrix + data-variation + hermeticity + coverage ledger) as the de-facto bash
  test reference, the run command, and the environment/version dependencies.
  Built incrementally; subsequent tiers (B-T2 ShellCheck gate, B-T3 unit, env
  parity, idempotency) follow. No change to `build-ol-aws-ami.sh`.

- Added a **persistent build log** (N3): the full run is mirrored to
  `${WORKSPACE}/build-ol-aws-ami-YYYYMMDD-hhmmss.log` by default while the
  console is preserved; **`--log-file <path>`** (env `LOG_FILE`) overrides the
  location. The file is ANSI-stripped so it stays grep-friendly. See SPEC E.5.
- Added a **`[DEBUG]` severity** and a **`--debug`** switch (F4): `[DEBUG]`
  lines are always written to the log file and mirrored to the console only
  with `--debug`. See SPEC E.2.
- Added **`[OLAWS-<AREA><NN>]` logic-code tags** on curated decision points and
  the Phase-6 assurance checks, so a log can be grepped by concern (with an OS
  suffix such as `/OL6` where generation-specific). Catalogue in SPEC E.4.

- Added an **`--imds-support` option** (env `IMDS_SUPPORT`) to choose the AMI's
  baked-in IMDS support: `default` (IMDSv1+v2, `HttpTokens=optional`) or `v2.0`
  (IMDSv2-required, OL7+ only). Default is `default`. See SPEC D.27.

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

- **Unified the log timestamp** to `YYYY-MM-DD HH:MM:SS` across every channel
  (N2). The `[BUILD]` heartbeat and the `[EXTERNAL]` re-emission previously used
  a bare `HH:MM:SS`; they now match `[INFO]`/`[WARN]`/`[ERROR]`. See SPEC E.1.

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

- **Docs (no behaviour change):** SPEC **A.3 (Pipeline Architecture)** had two
  drifts. (1) The Phase-3 registry row said the upstream-guard rewrite is "**For
  OL7 only**" with an `.ol7-patch.bak` backup, but Phase 3 patches when
  `OL_MAJOR_VERSION <= 7` — i.e. **OL6 and OL7** — and the backup is
  `.ol${N}-patch.bak`; OL6 additionally gets a second patch plus a synthesized
  `distr/ol6-slim/`. (2) The "Phase groups (semantic)" summary listed
  `Validation (0)` and `AWS (6, 7, 8)`, contradicting its own registry: Phase 6 is
  the **offline** Nitro readiness check (Validation) and Phase 9 is the AWS
  register step. Corrected to `Validation (0, 6)` and `AWS (7, 8, 9)`, and the
  Phase-3 row to OL6/OL7 (`<= 7`) with the generalized backup name. README phase
  text unchanged: the README has no phase-grouping table, and its Phase-3 patch
  description already documents the OL6 share (`<= 7`, shared with OL7) in 9.7.

- **Docs (no behaviour change):** SPEC **A.4 (Logging Conventions)** had drifted
  behind the logging framework that Part E documents. A.4 listed only
  `[STEP]/[INFO]/[WARN]/[ERROR]` (missing `[BUILD]`, `[DEBUG]`, `[EXTERNAL]`),
  forbade "new markers (`[DEBUG]`, ...)" even though `[DEBUG]` now exists, omitted
  the optional `[OLAWS-CODE]` from the line format, and stated "INFO/WARN/STEP go
  to stdout" when `log_warn` (like `log_error`) writes to **stderr**. A.4 now lists
  the full marker set with destinations, notes `log_step` is a banner with no
  literal `[STEP]` tag, records the unified `YYYY-MM-DD HH:MM:SS` timestamp and the
  optional logic-code, corrects the stderr routing (`[WARN]`/`[ERROR]`), and defers
  the authoritative axis detail to Part E (no duplication). README log text
  unchanged: the README defers logging conventions to SPEC and carries no
  marker/routing table to mirror.

- **Docs/comments (no behaviour change):** `--build-only` and `--skip-aws-import`
  were described three different ways. The script header said `--skip-aws-import`
  "Skip Phases 6-8" and `--build-only` "Run through Phase 5 only", and the README
  pair said `--build-only` stops "after VMDK is built (Phase 5)" — all inaccurate.
  In `main()` Phase 6 (the Nitro readiness check) always runs, and **both** flags
  then skip the AWS import phases (7-9) and exit, so the two are equivalent. The
  header (printed by `usage()`/`--help`) and `README.md` / `README.ja.md` now state
  "run through Phase 6, then skip Phases 7-9; equivalent to the other flag",
  matching SPEC A.3 (already correct). Bilingual README pair updated in lock-step.

- **Docs/comments (no behaviour change):** the script header's supported-version
  banner listed only `8 / 9 / 10` with `Experimental: 7`, **omitting OL6**, and
  the example env-file list and the AI-generation note likewise predated OL6
  support. OL6 has in fact been a supported (experimental) target since the OL6
  layer was added — the body validates it, warns on it, rejects `IMDS_SUPPORT=v2.0`
  for it, and synthesizes `distr/ol6-slim/` at runtime. The header (which
  `usage()`/`--help` prints verbatim) now lists OL6 alongside OL7 as experimental,
  adds `env.properties.aws-ol6` to the examples, carries a "Note on OL6", and the
  AI-generation note records OL6's static + boot-test verification status — matching
  the README (`9.7`, AI-generation note) and SPEC B.5.3 (OL6/OL7 both *not* yet
  end-to-end validated).

- **`register-image` no longer hardcodes `--imds-support v2.0` for every AMI**,
  which baked IMDSv2-required into OL6 AMIs whose cloud-init (0.7.5) cannot use
  IMDSv2 — so a default launch got no metadata and no SSH key. `--imds-support`
  is now conditional (`IMDS_SUPPORT`, default `default` = IMDSv1+v2, omitted from
  the register call); `v2.0` is opt-in and OL7+ only (OL6+v2.0 is rejected at
  validation). See SPEC D.27.

- **OL6 logged in as `cloud-user` instead of `ec2-user`** even though every env
  template sets `CLOUD_USER="ec2-user"`. OL6's cloud-init 0.7.5 ships
  `system_info.default_user.name: cloud-user` and the upstream `CLOUD_USER`
  mechanism does not override it there, so the EC2 metadata SSH key was injected
  into `cloud-user`. A new **OL6-only** `cloud/aws/provision.sh` hook (guarded on
  `/etc/oracle-release`) rewrites `default_user.name` in `/etc/cloud/cloud.cfg`
  to `CLOUD_USER`; cloud-init then creates `ec2-user` and lands the key on it.
  OL7+ are untouched (per-OS isolation). See SPEC D.26.

- **AWS `Get System Log` was empty** because the serial console (`ttyS0`) was
  not on the kernel cmdline, so boot/kernel output never reached the EC2 console
  — which is what made the OL6 SSH failure (above) so hard to diagnose. Both
  tiers now set `console=tty0 console=ttyS0,115200n8`, each via its own
  mechanism (per-OS isolation): **OL6** appends `ttyS0` in the GRUB-Legacy
  `/boot/grub/grub.conf` (the old kickstart line that *stripped* it is gone);
  **OL7+** get a new `cloud/aws/provision.sh` hook that adds `ttyS0` to
  `GRUB_CMDLINE_LINUX` and runs `grub2-mkconfig`, guarded on `/etc/default/grub`
  so it no-ops on OL6. Phase 6 gains an **advisory CHECK 5** that verifies
  `console=ttyS0` is present (warn only — observability, not bootability). See
  SPEC D.25.

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
