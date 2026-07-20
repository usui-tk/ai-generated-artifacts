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

This project's canonical revision identifier is currently the repository commit
hash (the script embeds no revision number; see SPEC A.16); numbered `rNN`
releases will be recorded here when the first formal release is cut.

This CHANGELOG is **English only** per the repository-wide
[documentation language policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md).

## [Unreleased]

### Fixed (2026-07-20 — record #6: /.build-info was structurally empty on OL5; upstream's post-provision mv could never succeed)
- **Sixth run failed at `mv ${VM_DIR}/.build-info/*`** — upstream
  unconditionally moves the build-info files out after provisioning; on
  OL6+ they are written by `common::distr_cleanup`, which the OL5 distr
  deliberately skips (EL5-unsafe) — with no replacement, `/.build-info`
  was ALWAYS empty and the failure was deterministic even for a fully
  successful provisioning (SPEC D.32 record #6).
- **Fix:** `distr::write_build_info` (called from `distr::cleanup`)
  writes the four contract files EL5-safely: static repolist note,
  `rpm -qa` pkglist, `%{EPOCH}`-based csv (EL5 rpm 4.4 lacks
  `%{EPOCHNUM}`), and kernel.txt from grub.conf's `default=` entry with
  a newest-el5uek fallback and a loud FATAL when underivable. Verified
  by executing the real template function on fixtures incl. the exact
  upstream `mv`+`rmdir` sequence; permanent t025 behaviorals added
  (four-files / mv-contract / fallback / FATAL).
- **Open item (evidence pending):** the same run's provisioning window
  (~16 s, no visible disk growth) is too fast for the in-guest ENA
  build; `${VM_DIR}/builder.log` (copied out by upstream before the
  failed mv) will show exactly what executed — requested from the
  operator before drawing further conclusions.
- Tests: t025 143 → 148 asserts; suite baseline 778 → **783**.
  TESTING.md counts + rows and SPEC D.32 (record #6) in lock-step.


### Fixed (2026-07-20 — record #5: guest rpm transaction — gdisk needs libicu; glibc-devel/-headers must match the U11 GA guest base; closure now gated host-side)
- **Fifth run reached the `[OLAWS-OL5S1]` rpm transaction** (serial v2
  held) and failed on four lines: gdisk's `libicu*.so.36` requires
  (libicu was not staged) and the staged glibc-devel/-headers' exact
  `glibc = 2.5-123.0.2.el5_11.3` against the ISO guest's **U11 GA
  `2.5-123.0.1`** (machine-derived from the U11 base repodata). The
  matrix container base is the latest errata, which masked the class:
  exact-`glibc =` requires must match the RUNTIME TARGET (SPEC D.32
  record #5).
- **Manifest fixes:** glibc-devel/-headers → GA `2.5-123.0.1` (single
  URL base retained; ENA 2.12.3 build boundary unaffected);
  `libicu-3.6-5.16.1` staged. Matrix-identity contract updated to
  "9 byte-identical + exactly the documented 3-entry divergence"
  (comm-based set equality in t025; the matrix file itself is
  untouched).
- **New host-side closure gate:** `_ol5_stage_closure_gate` + the
  measured 101-cap `OL5_GUEST_BASE_CAPS` table run right after staging —
  every staged requirement must resolve within (staged ∪ measured
  guest-base), any `glibc = X` must equal the pinned guest NVR; gaps die
  in seconds pre-install. Verified in-sandbox against the real corrected
  25-RPM set (PASS / libicu-removed FAIL / old-NVR FAIL), and all three
  cases are permanent t025 behaviorals (real fn + real table, rpm
  stubbed).
- Tests: t025 135 → 143 asserts; suite baseline 770 → **778**.
  TESTING.md counts + rows and SPEC D.32 (record #5) in lock-step.


### Fixed (2026-07-20 — record #4: the v1 serial file backend died on DAC/SELinux at domain creation; v2 = pty + virtlogd log capture)
- **Fourth run failed instantly at domain creation**: v1's
  `--serial file,path=${WORKSPACE}/…` requires QEMU (the `qemu` user) /
  the confined libvirt daemon to CREATE a file in a root-owned arbitrary
  directory — denied by DAC (no `w` on the dir) and by SELinux
  (`default_t` on custom paths like `/data`); even virt-install's
  rollback deletion of the never-created file was denied. Disks are
  immune because they are storage-pool volumes; chardev files are
  outside that machinery (SPEC D.32 record #4).
- **Fix (v2):** libvirt-native chardev logging — the device stays `pty`
  (`virsh console` from a second terminal works again) and
  `log.file=/var/log/libvirt/qemu/<vm>-install-serial.log,log.append=on`
  routes the complete serial output through **virtlogd**, whose
  policy-native log directory that is. v1→v2 upgrade handling removes
  stale v1 lines on reused workspaces. Verified pre-landing with the
  real toolchain: virt-install 4.1 `--print-xml` XML shape, the v1 DAC
  failure reproduction, and the REAL apply block executed in all three
  states (fresh / v1-upgrade / idempotent) — now permanent t025
  behaviorals.
- Tests: t025 129 → 135 asserts (v2 pins incl. a v1-form-absent guard +
  the 3-state behavioral apply); suite baseline 764 → **770**.
  TESTING.md counts + rows and SPEC D.32 (record #4) in lock-step.


### Fixed (2026-07-20 — record #3: SERIAL_CONSOLE=yes hung after install under the wrapper; now non-interactive with file-backed serial capture)
- **Third real run: install completed again in ~1 min, then 75+ min of
  dead-wait** — upstream attaches the console in the `SERIAL_CONSOLE=yes`
  branch (`--wait/--noautoconsole` exist only in the `no` branch; the
  attach is designed for a human pressing Ctrl+]), and under the
  wrapper's piped stdio the attached client never exits after the domain
  shuts down (SPEC D.32 record #3).
- **Fix: `serial-noninteractive` marker patch** (all majors; behavior
  changes only when `SERIAL_CONSOLE=yes`): the yes branch keeps the
  serial boot args, gains `--wait ${INSTALL_WAIT_TIME} --noautoconsole`
  (returns on shutdown exactly like `no`), and backs ttyS0 with a FILE —
  `${WORKSPACE}/<vm>-install-serial.log` — so the complete anaconda
  serial output is captured persistently (strictly better for diagnosis
  than an attach the wrapper cannot offer). Phase 5 prints the capture
  path + a `tail -f` hint. The sed was verified against the real
  upstream file (parse + branch shape) before landing.
- Tests: t007 marker pin 12 → 13 (+1); t025 +2 wiring pins (127 → 129);
  suite baseline 761 → **764**. TESTING.md counts + rows and SPEC D.32
  (record #3) in lock-step.


### Fixed (2026-07-20 — record #2: the record-#1 fix tripped its own channel gate; patch×gate now integration-tested)
- **Second real run failed at P3GATE on the fix itself:** the channel scan
  token-matched the guard line the env-defaults patch writes (it contains
  `declare -gA`), so the build died at the gate. The gate behaved as
  designed (seconds, pre-install); the root cause was ours — the patch
  and the gate were unit-pinned separately but **never executed
  together** before shipping (SPEC D.32 record #2).
- **Fix:** both sides refactored into extractable functions
  (`_ol5_patch_env_defaults` / `_ol5_scan_bash32_hostile`, shared by
  P3GATE and the Phase-4 local-env check); the scan gained a PRINCIPLED
  exemption — only the version-guard safe shape
  `[ "${BASH_VERSINFO[0]}" -ge 4 ] && … || true` is exempt (safe by
  construction on bash 3.2); an incomplete guard or any other hostile
  line still fails. The failure composition was reproduced in-sandbox,
  proven fixed against the real upstream defaults, and the integration is
  now PERMANENT in t025 (behavioral: patched→0 findings; raw
  `declare -gA` caught; shape-strict exemption; idempotent re-apply).
- Tests: t025 121 → 127 asserts; suite baseline 755 → **761**.
  TESTING.md counts + tier row and SPEC D.32 (record #2) in lock-step.


### Fixed (2026-07-20 — OL5 first-contact E2E: guest-bound env concat carried `declare -gA` into bash 3.2)
- **First contact result (real KVM, `--build-only`):** EL5 anaconda
  ACCEPTED the synthesized kickstart verbatim and completed the install —
  the largest unknown of the OL5 target is now proven — but provisioning
  died at source time: upstream `env.properties.defaults` line 69
  (`declare -gA REPO`, bash 4.2+) is concatenated VERBATIM into
  `provision.d/env.properties`, which the EL5 guest's bash 3.2 sources
  (`declare: -g: invalid option`). Full record: SPEC D.32 first-contact
  record #1.
- **Fix:** OL5 Phase-3 marker patch guards the declaration
  (`[ "${BASH_VERSINFO[0]}" -ge 4 ] && declare -gA REPO || true`) —
  host-side semantics unchanged (modern bash still declares the
  associative array; `REPO` is verified host-only), EL5 guest skips it,
  `set -e`-safe. Applied via a `~`-delimited sed (the replacement itself
  contains `||` — caught by the local apply-simulation before landing).
- **Channel gated (gate-maturity lesson):** P3GATE now scans every
  guest-bound env-concat member (defaults + distr + cloud, non-comment
  lines) for bash-4-only constructs, and Phase 4 scans the
  wrapper-generated `env.properties.local` right after writing — a future
  upstream reintroduction dies in seconds, pre-install, instead of ~20
  minutes into the build.
- Tests: t025 +4 pins (patch marker, guard shape, both channel scans):
  117 → 121 asserts; suite baseline 751 → **755**. TESTING.md counts +
  tier row and SPEC D.32 updated in lock-step.


### Changed (2026-07-19 — OL5 ISO SHA256 baked from the operator's measurement)
- **`env.properties.aws-ol5`: `ISO_CHECKSUM` is now baked** with the
  operator-measured value
  `b098bda92990134ea3bc8052a43b314eaffe93790a4bf872ae555b5cb467d421`,
  recorded with its full provenance chain (mirror-MD5 cross-check
  `8af2121088c7e6f5ebdb6d5900403240` matched; size 4222615552 bytes;
  measured on the operator's KVM host 2026-07-19). The 5.11 media is
  terminal/frozen, so the value is permanent; the wrapper's fail-fast on
  an empty `ISO_CHECKSUM` remains as the safety net. t025's env pin
  updated from ships-empty to the exact baked value (count unchanged);
  README EN/JA rows updated in lock-step.


### Changed (2026-07-19 — OL5 kickstart grammar re-verified against the REAL RHEL5 parser; user-requested)
- **Investigation:** the authoritative EL5 kickstart parser —
  **pykickstart-0.43.9-1.el5** (what anaconda-11.1 loads) — was fetched
  from the OL5 repository, its per-command option tables machine-derived,
  and EVERY option on every directive line of the synthesized OL5
  kickstart checked against them: **zero invalid options** (record: SPEC
  D.32). `firewall --enabled --ssh` is confirmed VALID (a 0.43 port-map
  option, `ssh → 22:tcp`); `part --label`, `key --skip`, bare `zerombr`,
  and the rest are all in the real tables; `auth` is a raw pass-through.
- **Single modern-tool divergence found and absorbed:** `%packages
  --nobase` is valid in real 0.43 but falsely rejected by modern
  pykickstart's RHEL5 profile. B-T4 (`tests/validate-kickstart.sh`) now
  validates the OL5 heredoc with exactly that construct normalized away
  (rationale + evidence pointer in-file); the normalized file passes
  `ksvalidator -v RHEL5` cleanly, so B-T4 is green with ksvalidator
  installed instead of failing on the tool's modeling gap.
- **Correction:** `%post --log` IS parseable in 0.43 (the earlier "no
  --log on EL5" note was wrong — fixed in the ks comments and SPEC
  B.15.3). Behavior unchanged: the exec redirect remains the chosen
  logging mechanism (single mechanism; also captures `set -x`).
- **Fixed (pipefail-hygiene recurrence, caught by this work):** the new
  B-T4 OL5 branch's `ksvalidator -l | grep -qw RHEL5` probe SIGPIPEd
  under `set -o pipefail` (the documented `grep -q`-on-a-pipe lesson
  class) and flaked to the no-RHEL5-profile SKIP; combined with t005's
  over-broad `^SKIP:` detection (ANY per-heredoc SKIP degraded the whole
  tier), B-T4 could falsely skip with ksvalidator installed. Fixed both:
  the profile list is captured first (`grep -c` on a variable), and t005
  now keys on the exact tool-missing message (`^SKIP: ksvalidator`) so a
  per-heredoc SKIP can never mask the OL6 result. t005 re-verified stable
  across repeated runs.
- Tests: t025 gains the grammar pins (grounded `firewall --ssh` label,
  corrected `--log` label, and two B-T4-normalization pins): 115 → 117
  asserts; suite baseline 749 → **751** (measured 751/0/0 with the full
  toolchain incl. ksvalidator). TESTING.md counts + tier row and SPEC
  (B.15.3 correction + D.32 grammar-verification record) updated in
  lock-step.


### Changed (2026-07-19 — growroot refined to the growpart decision model; user adjudication)
- **`ol-aws-growroot` (OL5 kickstart-baked one-shot): the execution
  criterion is now the ACTUAL DISK/PARTITION STATE (primary), with the
  flag file demoted to a secondary, reboot-loop-breaker-only role** — per
  the user's adjudication, grounded in a source-level read of real
  cloud-utils growpart (itself markerless and geometry-primary:
  `NOCHANGE` on at-max / sub-`FUDGE` growable deltas). Concretely:
  geometry (sysfs + `sfdisk -d`) is re-evaluated EVERY boot; the marker is
  consulted only after a growth-needed decision (previous-attempt-failed →
  loud, no retry-reboot) and **self-heals on success** — so a later EBS
  enlargement grows again (real growpart semantics; the marker-primary
  first implementation could not do this). The write mechanism switches
  from fdisk keystrokes to the growpart model: dump → single size-field
  edit → `sfdisk --no-reread --force` apply, with a dump backup/restore
  vehicle and a **post-write verify** re-dump. New guards: `Id=83`-only
  (refuses `ee`=GPT and anything else), extended-partition refusal, and
  **start-sector addressing** of the table entry (util-linux 2.13's sfdisk
  composes NVMe partition names without the `p` separator — name matching
  would break exactly on Nitro). The one-reboot requirement is retained
  and now grounded: `BLKPG_RESIZE_PARTITION` is kernel 3.6+, UEK R2 is
  3.0.36 (the same wall behind the RHEL6-era initramfs-time growroot).
- Tests: t025 growroot section rewritten for the new model — structural
  pins (dump-edit-apply, start-sector anchor, guards, backup/verify,
  BLKPG grounding, PRIMARY-before-SECONDARY ordering by position, legacy
  fdisk pipeline absent) plus a **behavioral harness** (fake sysfs +
  mocked df/sfdisk/reboot driving the REAL extracted script through five
  paths: grow/apply/verify/reboot; post-grow NOCHANGE + marker self-heal;
  marker-as-secondary loud no-retry; sub-fudge NOCHANGE; Id-guard
  refusal). t025 97 → 115 asserts; suite baseline 731 → **749**.
  TESTING.md §0 + tier table, SPEC B.15.4 (rewritten) + D.32 (follow-up
  adjudication + growpart research record), README EN/JA updated in
  lock-step.

### Added (2026-07-19 — OL5 AWS AMI builder support: runtime-synthesized distr + full host-supply model)
- **`build-ol-aws-ami.sh`: Oracle Linux 5 (U11 / UEK R2) build target** —
  the deepest legacy target, gated by the completed OL5 investigation
  (in-box nvme in the UEK R2 payload = the Nitro precondition; ENA
  self-build boundary; awscli ceiling; SSM measured exclusion; EPEL5
  cloud-init 0.6.3 closure). Design decisions and evidence records land in
  SPEC Part B/D in this series. Key mechanics, all OL5-branched
  (OS-separation; OL6-10 paths untouched):
  - `Enterprise-R5-U11` ISO naming accepted (kernel.org mirror of the
    original Enterprise Linux tree); OL5 requires an operator-computed
    SHA256 `ISO_CHECKSUM` (upstream accepts SHA1/SHA256 only; the mirror
    publishes MD5SUMS — the documented mirror MD5 is the cross-check).
  - `distr/ol5-slim/` runtime synthesis (OL6 precedent): EL5
    anaconda-11.1 kickstart (NO `%end`, `key --skip`, `cdrom`, ext3,
    LABEL-based partitions, no `--ondisk`), `%post` creates `ec2-user`
    (cloud-init 0.6.3 is getpwnam-only — it cannot create users), bakes
    GRUB-Legacy serial console, `modprobe.conf` nvme/ena/xen aliases and
    the one-shot `ol-aws-growroot` SysV script (fdisk MBR delete/recreate
    at the same start sector + single reboot; cloud-init `resizefs` then
    grows ext3 online — the MBR adaptation of the RHEL6-HVM gdisk
    workaround; gdisk is staged as a tool but never used on the MBR disk).
  - **Full host-supply model** (`[OLAWS-OL5S1]`): EL5 has no TLS 1.2 path,
    so the host stages every guest artifact into `distr/ol5-slim/files/`
    (the standard provision.d channel): the frozen 11-RPM ENA build
    toolchain (byte-identical to the matrix's proven list), kernel-uek +
    -devel + -firmware (live-resolved from the frozen UEK/latest channel
    with a pinned fallback), the 9-RPM EPEL5 cloud-init closure + gdisk
    (frozen immutable-archive NVRs), the ENA source tarball and the AWS
    CLI v2 bundle zip. The guest-side executor orders modprobe aliases →
    DEFAULTKERNEL → one rpm transaction → /usr/src staging → hard asserts
    (el5uek kernel present, initrd contains nvme.ko with one mkinitrd
    remediation retry, grub default boots el5uek, cloud-init installed).
  - `[OLAWS-OL5S2]`: EL5-safe function overrides of the upstream
    yum/dracut-based `cloud::install_aws_packages` / `cloud::cloud_init`
    (bash last-definition-wins; guest code is bash-3.2/POSIX clean).
  - OL5 virt-install disk-bus patch (`bus=scsi` → `bus=virtio`; the EL5
    installer has no virtio-scsi), Nitro-initramfs (dracut) hook not
    injected on OL5, ENA hook's dracut drop-in lines omitted on OL5,
    IMDSv2-only rejected (cloud-init 0.6.3 is plain IMDSv1; D.27-class
    guard), SSM Agent FORCED OFF (measured exclusion, SPEC B.10/D.31),
    `CLOUD_USER` pinned to `ec2-user`, awscli identity/hook wiring extended
    to OL5 (pre-staged zip contract; ceiling pin).
  - P3GATE: OL5 branch added (EL5 shape = ZERO `%end` + exactly 2 section
    openers; the balanced-`%end` rule keeps guarding OL6-10) and the
    ksvalidator advisory gains the RHEL5 profile.
- **`env.properties.aws-ol5`** — new template (kernel.org mirror ISO_URL +
  recorded mirror MD5, ext3, `UPDATE_TO_LATEST=no` mandatory,
  `DISK_SIZE_GB=10`, SELinux permissive with rationale, UEK_RELEASE=2).
- Tests: `tests/t007_idempotency.sh` marker-count pin 11 → 12 (the new
  `ol5-host-supply` marker; +1 assertion — suite baseline 631 → 632).
  TESTING.md §0 counts updated in lock-step. Dedicated OL5-synthesis
  tiers and SPEC/README documentation land later in this same series.

- **Tests: `tests/t025_ol5build.sh`** — dedicated OL5-synthesis tier (97
  asserts; L1/L2). Extracts the embedded `distr/ol5-slim` templates + the
  `[OLAWS-OL5S1]` executor and asserts the EL5 kickstart shape (zero
  `%end`, `key --skip`, `cdrom`, ext3/LABEL, RHEL6+ tokens absent,
  ec2-user pre-creation, the fdisk growroot one-shot), the mechanical
  bash-3.2 safety scan of every guest-side block, the OL5S1 load-bearing
  order + hard asserts, the provision EL5 discipline, the host-supply
  manifests (toolchain list BYTE-IDENTICAL to the matrix's
  `OL5_TOOLCHAIN_RPMS`; 10 frozen EPEL5 NVRs), the wrapper wiring
  (behavioral `Enterprise-R` parse; behavioral P3GATE: the real extracted
  gate passes the real extracted kickstart and fails `%end`-injected /
  sos-dropped mutations), and the `env.properties.aws-ol5` invariants.
  `tests/validate-kickstart.sh` (B-T4) additionally validates the OL5
  kickstart under pykickstart's RHEL5 profile when this ksvalidator still
  ships it (explicit SKIP otherwise — never a silent false PASS). Suite
  baseline 632 → **731 across 25 tiers** (t025 = 97; B-T1/B-T2 +1 each
  for the new script); TESTING.md §0 counts, degradation table, and the
  tier table updated in lock-step.

- **Docs: SPEC B.15 + D.32, README (EN/JA) OL5 sections** — SPEC gains
  **B.15** (the OL5 build target: model, enforcement table for every hard
  constraint, the EL5 kickstart shape, the growroot design, the operator
  E2E protocol) and **D.32** (the frozen design record: the machine-grounded
  evidence — in-box nvme with the class-match PCI alias, the 9-RPM EPEL5
  closure and getpwnam-only key injection, the upstream transport
  mechanics, the guest bash-3.2 constraint — plus the six binding
  adjudications and the explicit first-contact-unproven surface list).
  README.md / README.ja.md updated in lock-step: intro paragraph, the
  `env.properties.aws-ol5` table row, installer-table OL5 wiring notes,
  the `--skip-*` / `--imds-support` / `DISK_SIZE_GB` rows, a new section
  9.8 (mechanism) and section 10 item 9 (limitations, led by the
  E2E-unproven warning).

### Changed (2026-07-19 — OL5 pinned versions aligned to the merged sweep evidence)
- **`install-ena-driver.sh`: `ENA_VERSION_OL5` raised `2.9.1` -> `2.12.3`** —
  the canonical ledger's full 71-version OL5 sweep (kernel-uek-devel
  `2.6.39-400.297.3.el5uek`; 56/71 ok) measured the buildable boundary at
  exactly `2.12.3` / `2.13.0` (every 2.13.0+ build produces no `ena.ko`), so
  the pin now sits on the highest proven-buildable release instead of the
  initial-investigation ceiling. `tests/ena/run-ena-buildtest-matrix.sh`
  `pin_for(5)` and the t023 regression pins move in lock-step (assertion
  count unchanged). OL6 stays at `2.9.1` (different kernel, different
  boundary — see SPEC B.3.2).
- **`install-awscli.sh`: the OL5 ceiling-pin comment now cites the FULL
  merged sweep** (all 921 fetchable v2 releases, 493 ok / 428 fail,
  boundary exactly `2.17.51` / `2.17.52`) instead of the 12-version
  boundary investigation. The pin VALUE is unchanged: the full sweep
  confirmed `2.17.51` as already correct.

### Added (2026-07-19 — OL5 AWS CLI v2 full-sweep evidence merged into the ledger)
- **`tests/awscli/awscli-installtest-ledger.json` + `RESULTS-ol5.md`: the
  user-run OL5 full sweep (`--ol 5 --full`, real host, all 921 fetchable v2
  releases × the probed terminal el5uek kver) merged via the designed
  `--merge-from` path** — MERGED adopted=921, same-status-kept=2763, total
  3684 rows. The 2763 OL6-8 rows of the external ledger matched the
  committed ledger key-for-key AND status-for-status (the largest
  determinism cross-check yet), and the regenerated RESULTS-ol6..8 came out
  byte-identical.
- Findings recorded by the sweep (**493 ok / 428 fail**): the boundary lands
  **exactly at the investigated 2.17.51 / 2.17.52 line** — every release up
  to 2.17.51 runs on glibc 2.5 (all 7 investigation-proven versions
  reproduce; zero ok above the ceiling), and every 2.17.52+ release fails
  as `installs-but-wont-run` (the Python 3.12 rebase glibc wall; 427 rows).
  The report generator derives "capped at `2.17.51`" for OL5 unaided —
  empirically the same cap as OL6, per D.30. The single remaining fail,
  **2.0.32, is an upstream distribution hole**: awscli.amazonaws.com has no
  versioned zip for it (HTTP 404, verified live during review), so the
  staging failed and the pre-stage contract recorded the fail honestly.
  Ledger rows are as generated; no hand edits.

### Fixed (2026-07-19 — host TMPDIR leaked into chroot guests; guest env hygiene across all container entry points)
- **The three matrices (ENA / AWS CLI / SSM): the guest chroot env now pins
  `TMPDIR=/tmp`** — second field failure of the OL5 AWS CLI run: the
  recommended `/data/temp` invocation exported `TMPDIR` (to move the
  transient container rootfs off `/tmp`), the variable propagated through
  `sudo env` → `unshare` → `chroot`, and the installer's own `mktemp -d`
  inside the guest died on a path that exists only on the HOST
  (`mktemp: cannot make temp dir /data/temp/.../tmp.XXXX`). A/B in-sandbox:
  the unpatched matrix reproduces the exact field error under a leaked
  TMPDIR; the patched ENA and awscli matrices both pass preflight and record
  ok under the same leak. Host-side mktemps still honor the caller's TMPDIR
  by design (that is the point of the recommendation).
- **Similar-processing survey (user-required)** across all 59 chroot entry
  points in 10 files, by failure class: the three matrix unshare blocks
  (fixed above); the six builders' self-test `t_run` (same
  guest-general-execution class — now `/usr/bin/env TMPDIR=/tmp`); the ENA
  OL5 provisioning rpm and the OL5 builder's EPEL rpm (scriptlet exposure —
  same env guard). The builders' internal build phases were measured
  tolerant (the field run built 19/0/1 under the leaked TMPDIR; fail-loud
  path) and are left unchanged.
- Regression pins added to `tests/t023_ol5ena.sh` and
  `tests/t024_ol5awscli.sh` (+1 assert each; suite 629 → 631 full-toolchain,
  TESTING.md §0 re-tallied).

### Fixed (2026-07-19 — clean-core self-test false negative on `nodev` work volumes, all six builders)
- **`tests/cleancore/build-cleancore-ol{5..10}.sh`: the self-test chroot now
  bind-mounts the HOST `/dev` (+ `/proc`), matching the matrix execution
  model** — field failure on the first OL5 AWS CLI run: the user placed
  `--work-dir` on a `nodev`-mounted data volume and the self-test failed
  exactly one check (`package manager runs (yum --version)`) while bash/rpm
  passed. Reproduced in-sandbox on a `nodev` tmpfs: a plain chroot inherits
  the unpack volume's mount flags, the image's own device nodes are inert
  (`/dev/null`: Permission denied), and python/yum dies at startup — a false
  negative about the HOST mount, not the image. All six per-OL builders
  shared the plain-chroot `t_run` (sibling sweep). The binds are explicitly
  torn down BEFORE the `rm -rf` of the unpacked tree (an rm descending into
  a live `/dev` bind would delete host devices — ordering is load-bearing).
  FT: a full OL5 build with WORK on a `nodev` tmpfs now passes 19/0/1;
  builder phases and matrix containers were already bind-mounted and are
  unaffected.

### Added (2026-07-18 — OL5 ENA full-sweep evidence merged into the ledger)
- **`tests/ena/buildtest-ledger.json` + `RESULTS-ol5.md`: the user-run OL5
  full sweep (`--ol 5 --full`, real host, all 71 in-scope releases × the
  frozen `2.6.39-400.297.3.el5uek` devel kernel) merged via the designed
  `--merge-from` path** — MERGED adopted=71, same-status-kept=150, total 221
  rows. The 150 OL6-10 rows of the external ledger matched the committed
  ledger key-for-key AND status-for-status (a large-scale determinism
  cross-check of the verdicts), and the regenerated RESULTS-ol6..10 came out
  byte-identical.
- Findings recorded by the sweep: **56/71 ok** — every investigation-proven
  version reproduced, and the real buildable boundary lands at **2.12.3**
  (three minors past the sampled 2.9.1); 2.13.0+ (11 versions) fail with no
  module produced (genuine UEK R2 incompatibility). Early-band holes
  2.2.0-2.2.2 fail the same way. **2.2.12 is an upstream tag/source version
  mismatch caught by the identity invariant**: the build SUCCEEDS but the
  module self-reports `2.12.2g` because the `ena_linux_2.2.12` tag's own
  `ena_netdev.h` declares `DRV_MODULE_GEN 2.12.2` (verified against the
  upstream tarball) — the "installed module version is authoritative" check
  recorded the vendor discrepancy verbatim, exactly as designed. Ledger rows
  are as generated; no hand edits.

### Changed (2026-07-18 — docs: OL5 SSM Agent recorded as a measured exclusion)
- **SPEC: new D.31 + a B.10 pointer** — the AWS-supported SSM Agent band
  (`>= 3.3.3598.0`; 11 versions, 9 fetchable) was investigated for the same
  OL5 opt-in wiring ENA and AWS CLI v2 received, and adjudicated as a
  **measured exclusion** (no `--ol 5` wiring): every band RPM is
  xz-payload/sha256-digest (EL5 rpm 4.4 refuses with two rpmlib capability
  errors, captured verbatim) AND the band's kernel floor of 3.2 is attested
  three independent ways (ELF note `for GNU/Linux 3.2.0`, the `%pretrans`
  kernel guard, the committed release list's `min_kernel`) against the
  terminal el5uek 2.6.39 / 3.0.36-base line. The binaries themselves are
  static-pie with zero GLIBC references and all 9 ran `-version` in the
  OL5.11 chroot — a userland-only result that cannot translate to a real
  instance, which is exactly why a ledger row would mislead. README rows
  updated in both languages.

### Added (2026-07-18 — OL5 clean-core carries the archived-EPEL-5 repo configuration)
- **`tests/cleancore/build-cleancore-ol5.sh`: archived EPEL 5 wired into the
  image** (user requirement, OL6-flow parity — the OL6 path gets the archived
  EPEL 6 at test time from `install-ena-driver.sh`). A new `[A->C] (3b)` step
  fetches `epel-release-5-4` host-side, installs it via the EL5 builder rpm
  against the deliverable root (db4.3 rpmdb), rewires the repo files to the
  canonical Fedora archive (`https://dl.fedoraproject.org/pub/archive/epel/5/`),
  comments the dead mirrorlist, and ships **every section `enabled=0`**.
  Service model measured during implementation: the Fedora archive hosts
  **302-force plain http to https**, and EL5 openssl 0.9.8e is TLS 1.0 max —
  so the guest can never fetch the archive directly (either scheme); the
  config is a canonical, gpg-keyed reference served host-mediated
  (mirror / staging), the same doctrine as the OL5 base channel. `enabled=0`
  is deliberate: epel*.repo are the image's ONLY repo files, and a lone
  unreachable enabled repo would break every in-guest yum operation. Package
  count 125 → 126; self-test grows four EPEL assertions (19 passed on a full
  fresh build). SPEC B.6 EL5 paragraph updated in lock-step.

### Fixed (2026-07-18 — OL5 ENA host provisioning: rsyslog5 Conflicts aborted the toolchain transaction on a fresh clean-core)
- **`tests/ena/run-ena-buildtest-matrix.sh`: the frozen OL5 toolchain closure
  drops `rsyslog5` (12 → 11 RPMs)** — first real-host run (RHEL 10 KVM,
  2026-07-18) failed preflight with `OL5: 'gcc' not found`. Root cause
  (reproduced in-sandbox on a freshly built clean-core, then confirmed by
  the raw rpm error): the investigation-era RPM list carried a stray
  `rsyslog5` — a dependency-resolver artifact, not a build tool — which
  `Conflicts: rsyslog` against the clean-core's own `rsyslog`, aborting the
  ENTIRE `rpm -Uvh` transaction, so no toolchain (gcc included) was ever
  installed and the installer's pre-provision contract check fired. The
  session-era FT could not see it: its clean-core tarball predated the
  builder revision that ships `rsyslog`. The 11-seed dependency closure is
  re-verified mechanically complete against the clean-core package set
  (resolver: 29 names, zero missing, `rsyslog5` required by nothing).
  Regression pin updated in `tests/t023_ol5ena.sh` (count + rationale).
- **run_one output truncation fixed in BOTH matrices (ENA + awscli)** — the
  chroot step redirected with `>` and silently WIPED the OL5 host-side
  provisioning/staging output that the hook had just appended to the same
  outlog, which is exactly why the preflight diagnostic bundle showed no
  provisioning lines and made the field failure needlessly opaque. Now `>>`
  (behaviour identical for OL6-10: the outlog is a fresh mktemp).

### Added (2026-07-18 — OL5 opt-in AWS CLI v2 install-test support + awscli ledger merge mode)
- **`install-awscli.sh`: OL5 (glibc 2.5) branch** — install-test / PoC scoped,
  after a same-day 12-version boundary sweep measured **7/7 "runs"** for the
  ≤ 2.17.51 band on the OL5.11 clean-core and a hard glibc-too-old wall from
  2.17.52 (Python 3.12 rebase; `.so` floor 2.5 → 2.17 — **empirically
  explaining the pre-existing OL6 pin for the first time**). Ceiling pin
  `AWSCLI_VERSION_OL5=2.17.51` (= the OL6 pin). The bundle zip must be
  host-pre-staged (EL5 has no in-OS TLS 1.2 path); nothing else needs
  provisioning (unzip 5.52 ships in the clean-core, asserted not installed);
  the kver record travels via the `AWSCLI_OL5_KVER` contract (probed, not
  provisioned). **No W1 launch wrapper ships** — the mid-band symlink
  failures in the first ad-hoc sweep were a harness artifact (chroot without
  `/proc`; that bootloader generation self-resolves via `/proc/self/exe`),
  proven by an A/B on the identical binary and re-adjudicated out; the full
  story is SPEC D.30. Shared-code EL5 hardening found by container FT
  (behaviour identical on OL6-8): `detect_bundled_python` `sed -E` → pure
  bash; the kver `sort -V` stderr silenced.
- **`tests/awscli/run-awscli-installtest-matrix.sh`: opt-in OL5 wiring +
  merge mode** — default OL set stays 6-8; `--ol 5` opt-in; `pin_for(5)` =
  2.17.51; `ol5_stage_zip` (cached, `unzip -t`-verified host staging) +
  `probe_ol5_uek_kver` (ENA-probe reuse-by-copy, pinned fallback);
  `--merge-from`/`--merge-prefer` ported from the ENA matrix on this ledger
  dedup key (same adjudicated conflict policy). Ledger schema stays 1.0; the
  existing report generator derives the OL5 "capped at 2.17.51" verdict with
  zero changes; RESULTS-ol5.md opens with a scope paragraph.
- **`tests/t024_ol5awscli.sh` (new tier, 25 asserts)** — pins the installer
  OL5 branch, the W1 absence, the EL5 shared-code safety, the matrix wiring,
  and the three merge-policy cases (hermetic). Suite totals move 602 →
  **629 passed / 24 tiers** (B-T1 53, B-T2 48); TESTING.md §0 re-tallied.

### Added (2026-07-18 — OL5/UEK R2 opt-in ENA build-test support + ledger merge mode)
- **`install-ena-driver.sh`: OL5 (`el5uek`) branch** — build-test / PoC scoped,
  user-adjudicated after a same-day feasibility investigation proved **20/20**
  sampled ENA releases (1.1.2–2.9.1) build against `kernel-uek-devel`
  2.6.39-400.297.3.el5uek with plain gcc 4.1.2 **with** the shim set (vanilla
  source: 0/20). Pin `ENA_VERSION_OL5=2.9.1` (OL6 parity). EL5 has no in-OS
  TLS 1.2 path (openssl 0.9.8e), so the toolchain/headers are verified as
  host-pre-provisioned (`ol5_verify_preprovisioned`) and the driver source
  must be pre-staged; DKMS is out of scope (always plain make); initramfs
  regeneration is skipped (devel-only provision). `apply_el5uek_shims`
  carries the proven exact-string transform set (S1 kconfig.h stub, S2
  netdev_features_t, S3a deterministic IS_UEK-unset, S3b UEK3-only `$(error)`
  neutralization, P1–P7 collision renames / perf-hint degradations /
  `dma_zalloc_coherent` re-implementation — full taxonomy in SPEC D.29);
  the applied list travels in the new result-JSON `shims` field. EL5-guest
  hardening found by container FT: `_ena_ver_ge` is now a pure-bash numeric
  compare (`sort -V` does not exist on EL5 coreutils 5.97;
  behaviour-identical for x.y.z inputs, t021 green).
- **`tests/ena/run-ena-buildtest-matrix.sh`: opt-in OL5 wiring** — the default
  `--ol` set stays 6–10 and the floor semantics stay uniform (the OL5
  all-release evaluation is the separate `--ol 5 --full` run);
  `ol5_host_provision` (frozen 12-RPM OL5/latest toolchain closure +
  live-probed `kernel-uek-devel` with pinned fallback + guest `rpm -Uvh` +
  `/lib/modules/<kver>/build` wiring + source staging, cached under the work
  dir); `pin_for(5)=2.9.1`, `uekr_for(5)=UEK/latest` (pre-UEKR channel
  naming); the update-gate OL5 probe strips `.x86_64` (EL5 modules dirs carry
  no arch suffix — without this the gate saw a perpetually "new" kernel);
  the preflight transient set gains the "pre-provision" phrase. Ledger
  **schema 1.1 → 1.2**: rows gain `shims` (null on OL6–10); RESULTS notes
  render it and RESULTS-ol5.md opens with an OL5 scope paragraph. OL5
  load-readiness attestation is not claimable by design (L4a not-ready is the
  honest verdict; the missing bundle Module.symvers shares the tracked
  el7–10 host-side build-symlink issue).
- **Ledger merge mode `--merge-from <path>` (+ `--merge-prefer ours|theirs`)**
  — python3-only union of an externally produced ledger into the committed
  one; same-key same-status keeps the incumbent row, same-key
  different-status is a hard error naming every conflicting key unless
  `--merge-prefer` resolves it (base ledger untouched on the error path).
  Completes the adjudicated operating model: zero-base rebuild / incremental
  append (both already native) / merge (new). SPEC B.9 documents all three.
- **`tests/t023_ol5ena.sh` (new tier, 39 asserts)** — pins the installer OL5
  branch + every proven shim pattern + EL5 safety, the matrix OL5 wiring and
  schema 1.2, and the three merge-policy cases (hermetic). Suite totals move
  561 → **602 passed / 23 tiers** (B-T1 52, B-T2 47 — the new tier is itself
  parse/lint-counted); TESTING.md §0 re-tallied.
- **Gate restoration** — `tests/t002_shellcheck.sh` was red at HEAD on a
  single SC2015 (info) at the `osminor` os-release fallback introduced by the
  OL10-EPEL session (pinned ShellCheck 0.10.0 reproduces); restated as an
  explicit if-then with identical semantics. B-T2 green again.

### Changed (2026-07-18 — docs: Boot-E2E evidence note for the 07-18 generation; OL6 instance-generation boundary)
- **TESTING.md: new "Boot-E2E evidence note (2026-07-18)"** — the 07-18 build
  generation (OL9.8 + the first OL10.2-ISO build, the live-verified OL10
  developer-EPEL discovery, the ssm-identity fix) built, registered, and
  booted on real EC2 across all five majors (OL7-10 on current-generation
  `c8a.large`, OL6 on `c5a.large`; sosreports on every instance).
  Highlights recorded: the AMI-name = artifact invariant held for every
  marker **including the baked SSM Agent** (first-load `v3.3.4793.0` =
  the AMI-name version); the first OL10.2 boot doubles as the first
  production-path run of the OL10 EPEL discovery; DKMS autoinstall proven
  for UEK respins never swept in the container matrix; and a
  **verification-protocol rule** — an account-level SSM agent auto-update
  replaced the baked agent with `3.3.4851.0` minutes after boot (from a
  channel other than the image's install channel, ETag-verified), so the
  SSM name=artifact check must compare the first-load version, never
  sos-time `rpm -qa`.
- **OL6 instance-generation boundary documented (measured)**: the frozen
  OL6/UEK4 kernel panics at early boot on AMD Zen3+ (`c6a`/`c7a`/`c8a` —
  `kernel BUG at arch/x86/kernel/alternative.c:708`, pre-module, so no
  pipeline artifact is in the failure path) while Intel (through
  `r8i-flex`, 07-13) and AMD ≤ Zen2 (`c5a`) boot. Terminal kernel —
  documentation-only response: SPEC B.1 constraints gained the boundary
  bullet (and the OL7-10 scoping of the "boots on all Nitro types" claim,
  with a dated scoping note on the D.4 consequence), README EN/JA gained
  the OL6 table-row note and a section-10 item-8 bullet.
- **SPEC B.11 validation-status paragraph refreshed** — the stale
  "OL9/OL10 SSM not yet boot-validated" text is superseded by the
  07-13/07-18 real-boot record, with the auto-update caveat and the
  first-load comparison rule. Housekeeping recorded in the TESTING note:
  the 07-13-generation AMIs and the interim `-ssmlatest` pair were
  deregistered after the 07-18 run superseded them.

### Fixed (2026-07-18 — AMI identity: '-ssmlatest' degradation; SSM version resolution re-grounded on the S3 /latest/ channel)
- **The 2026-07-18 OL9.8/OL10.2 real E2E registered AMI names carrying
  `-ssmlatest`** — a degradation of the "AMI identity always carries concrete
  versions, never the word latest" invariant (earlier builds stamped e.g.
  `-ssm3.3.4793.0`). Root cause, reproduced live: `_ssm_resolve_latest()` was
  GitHub-first (releases/latest tag, then an S3 HEAD verification) and failed
  closed exactly when the GitHub tag led S3 publication — at fix time GitHub
  said `3.3.4851.0` with its RPM 403 on S3 — and the failure fallback then
  printed the literal `latest` into the persistent identity, contradicting
  the awscli marker's established omit-on-failure contract one block below.
- Fix, two-part:
  - `_ssm_resolve_latest()` is now layered with the **S3 release channel's
    own `latest/VERSION` file as layer 1** — the exact content of the
    `/latest/` alias the guest installs, which by construction can neither
    lead nor lag the install (live-measured `3.3.4793.0`, matching the
    version proven running on the 2026-07-13 real-boot E2E); the GitHub
    tag + S3-HEAD route stays as layer 2 fallback.
  - **Marker conformance (awscli parity)**: on total resolution failure
    `SSM_AGENT_RESOLVED` stays empty and the ssm marker is omitted from the
    AMI name/description entirely — the word `latest` can no longer reach
    the persistent identity; the final report line states the unresolved
    case explicitly instead of printing a bare `latest`. Guest install
    behavior is unchanged (the hook still installs the `/latest/` alias).
- Tests: command-mock tier +6 (mocked-curl scenarios pinning the layer order,
  the layer-1-success/no-GitHub-call spy, the tag-leads-S3 fail-closed shape,
  and full-offline → empty); register-validation tier +4 identity-invariant
  pins (the `-ssmlatest` branch can never regrow, the marker is gated on a
  non-empty resolved version, layer 1 reads `latest/VERSION`, failure empties
  rather than stores `latest`) and the realistic-name fixture updated to the
  2026-07-18 E2E shape with a concrete version. Suite: 551 -> 561
  full-toolchain, 22 tiers.
- Docs lock-step: SPEC AMI_NAME table row + B.11 naming/resolution paragraph
  rewritten to the layered resolver and omit-on-failure contract, with the
  2026-07-18 regression record. READMEs untouched (they do not document the
  marker mechanics).

### Changed (2026-07-16 — ENA buildtest ledger: full re-sweep on refreshed UEK kernels)
- **ENA buildtest ledger + RESULTS-ol6..10 replaced with the 2026-07-16 full
  sweep** (user-host matrix run, single-sweep replacement per the pre-release
  ledger operation; 150 combos = 30 in-scope releases ≥ the 2.8.0 express
  floor × OL6–10). Trigger: a UEK point update on OL9/OL10
  (`6.12.0-204.92.4.2` → `…4.3.el9uek/el10uek`); OL6/7/8 kernels unchanged.
  **Verdicts are fully deterministic against the previous sweep: 0 of 150
  status changes, 0 ko_version changes on the same-kernel majors** —
  OL6 6/30, OL7 13/30, OL8 17/30, OL9 9/30, OL10 9/30 ok, with the OL9/OL10
  buildable floor unchanged at 2.13.2 across the kernel refresh. 27 fail rows
  differ only in the `[make.log first error: …]` annotation (22 on OL9/10
  from the header changes of the new kernel; 5 on OL6/OL8 at identical
  kernels — the first-error capture is ordering-sensitive under parallel
  make; note-level nondeterminism only, verdicts stable).
- Verifier run against the sweep's load-readiness bundle
  (`verify-ena-buildresults.sh`, kmod present): ledger ↔ bundle fully
  consistent — 54 ok rows ↔ 54 captured `ena.ko` modules, vermagic (L4a)
  54/54 pass; L4b fails only with "no Module.symvers in bundle" on
  el7/8/9/10 (the KNOWN open producer-side capture gap — OL6, which does
  capture Module.symvers, passes 6/6), no new findings.
- This sweep is also the first real-host E2E of the OL10 developer-EPEL
  discover→verify→finalize path through the ENA_BUILDTEST route (QA
  preflight + 30-version matrix on OL10 all resolved dkms via the discovery;
  the shipped `ol10_u1_developer_EPEL` was the expected live winner —
  Oracle's u2 EPEL is still unpublished).
- `ena-driver-releases.json` unchanged (byte-identical to the tree); reports
  verified byte-identical to a `--report-only` regeneration from the ledger.

### Changed (2026-07-16 — OL10 template moved to Oracle Linux 10.2)
- **OL10 template moved to Oracle Linux 10.2**
  (`OracleLinux-R10-U2-x86_64-dvd.iso`, released 2026-07): by design a
  one-line `ISO_URL` diff in `env.properties.aws-ol10` (the SINGLE-TOUCH
  MAINTENANCE POINT). Pre-verified: the route-#3 checksum URL
  (`.../OracleLinux-R10-U2-Server-x86_64.checksum`) is live (HTTP 200) and
  carries the dvd-ISO hash, so the automatic checksum resolution holds
  unchanged.
- **SPEC's OL11 porting recipe de-versioned** (docs-only): the `sed` example
  carried the then-current `R10-U1` pin literal and silently went stale on
  every OL10 update release; it now uses the `R10-U<N>`/`R11-U<M>`
  placeholder form with a note that the literal is whatever the OL10
  template pins at copy time. This closes the last living release-bound
  literal outside the designed single-touch point (full-inventory sweep,
  2026-07-16: everything else is historical record, frozen-major permanent
  fact, or shape-example/fixture text that needs no per-release
  maintenance).

### Fixed (2026-07-16 — OL10 developer-EPEL: live-verified discovery replaces the fixed section name)
- **OL10's DKMS-from-EPEL wiring no longer hard-codes
  `ol10_u1_developer_EPEL`** — the section name churns on every OL10 update
  release (measured from the `oracle-epel-release-el10` package history:
  1.0-2 shipped `u0` → `.../OL10/0/`, 1.0-5..1.0-6 ship `u1` →
  `.../OL10/1/`; with OL10.2 released, `.../OL10/2/developer/EPEL/` was
  still HTTP 404, so a 10.2 system runs on the 10.1 EPEL today and a `u2`
  rename is the expected next step), and any fixed name breaks SILENTLY at
  the rename — the exact "No match for argument: dkms" failure mode of the
  original unversioned-name guess. `install-ena-driver.sh` now runs a
  discover → verify → finalize pass on OL10 only (user adjudications
  D1/D2/D3): candidates from BOTH the shipped `oracle-epel-ol10.repo`
  sections AND a constructed URL for the running minor
  (`/etc/oracle-release` → new `osminor` detection); each candidate is
  verified against the LIVE yum server through core dnf
  (`--repofrompath`, `skip_if_unavailable=0`) requiring reachability AND an
  actually-available `dkms` package (D1 — repomd reachability alone is not
  enough); selection prefers the running minor's own repo, else the highest
  verified `u<N>`; a live shipped section is enabled in place with dead
  shipped sections explicitly disabled (D2), while a constructed-only winner
  is materialized as a DISPOSABLE gpg-checked repo file removed right after
  the dkms provisioning step (D2). Every candidate verdict is logged — no
  silent no-match failures. The `setup_epel` enabled-only early return is
  bypassed on OL10 (an enabled shipped section can still be dead there);
  the ENA_BUILDTEST container path routes through the same mechanism and
  dies loudly on a verification miss; production keeps the existing
  plain-make degradation. OL6–OL9 paths are untouched (OS isolation;
  unversioned EPEL paths do not churn — the OL9 case split out of the old
  shared `9|10` branch verbatim). FT 2026-07-16 in an OL10 chroot against
  the live server (dnf 4.20 measured): four scenarios green, including a
  real `dkms 3.4.1-1.el10_1` install through a materialized disposable and
  its cleanup. EPEL usage inventory: `install-ena-driver.sh` is the only
  script with EPEL processing (the one mention elsewhere is a "no EPEL
  needed" comment), so the hardening scope closes there.
- Tests: new `tests/t022_ol10epel.sh` (37 asserts — structural pins incl.
  never-regrow regression pins on the fixed-u1 wiring, plus behavioural
  fixtures copied from the real repo-file shapes and a stubbed-probe
  orchestrator run over the shipped-enable / dead-disable /
  disposable-lifecycle / all-dead paths; one real bug caught pre-commit:
  the sole-survivor unversioned selection needed a `best_n=-2` sentinel).
  Suite: 512 -> 551 measured full-toolchain (t022 +37, B-T1/B-T2 +1 each
  for the new file), 22 tiers.

### Fixed (2026-07-14 — TESTING.md §0 fixed-count reconciliation)
- **TESTING.md fixed pass count re-grounded on a full-toolchain measurement**:
  the documented `389 passed / 20 tiers` (with its per-tier breakdown)
  pre-dated several suite expansions and drifted from reality. Re-measured on
  a fresh clone with the FULL toolchain (ShellCheck 0.11.0 — pin 0.10.0 also
  green, `ksvalidator`, `modinfo`/kmod, `python3`): **512 passed, 0 skipped,
  0 failed across 21 tiers**; the per-tier breakdown and the optional-tool
  degradation arithmetic (511/1 without `ksvalidator`, 509/1 without
  `modinfo`) were rewritten from that run, and kmod/`modinfo` was added to
  the environment dependency list (it silently gated three ena-uek-detect
  inbox-report assertions). Docs-only; no script or test changes, suite
  count unchanged at 512.

### Verified (2026-07-13 real-boot E2E — B-T7/B-T8 executed on all five majors) / Changed (firmware narrative re-grounded on booted-image observations)
- **B-T7/B-T8 executed for real**: the 2026-07-13 generation completed real
  7 GB builds + registrations on ALL five majors (OL6 `ami-01724bfd463dede0e`,
  OL7 `ami-0661c712ffbab6e0b`, OL8 `ami-0e06117c48124c634`, OL9
  `ami-02408b9ed351ae526`, OL10 `ami-05c3164c73ce94eca`; ap-northeast-1) and
  real EC2 boots with SSH login; sosreports collected on every instance
  (r5dn.large / r6id.large / r7iz.large / r8i-flex.large ×2 — Nitro through
  v6). Sosreport-verified: `ethtool -i` = self-built `2.9.1g`/`2.17.2g` on
  every major (AMI-name = driving-driver invariant; closes the OL8-10
  self-build gap), initramfs carries ena+nvme on all five (D.28 real-machine
  confirmation; OL6 Nitro/NVMe path now traveled), baked-in SSM `3.3.4793.0`
  installed AND running on all five (first real-boot proof of the
  all-majors-`/latest/` policy), UUID fstab / NVMe root / serial console, zero
  ena/nvme dmesg errors (only the expected OL6 unsigned-DKMS taint). AWS CLI
  is not observable from sosreports (no `/usr/local` collection; build-time
  verified). Status docs updated: TESTING.md "Boot-E2E evidence note
  (2026-07-13)" + B-T7/B-T8 status, SPEC B.3.4 validation status, README.md /
  README.ja.md (ENA row, OL6 Phase A/B/C note, development-history
  supersession notes).
- **Firmware narrative corrected to observed reality (user adjudication,
  2026-07-13)**: the booted images of ALL five majors carry `linux-firmware`
  and `kernel-uek-modules` for the target kernel — contradicting the earlier
  entries' claims that OL9/OL10 ship without firmware, that
  `LINUX_FIRMWARE="no"` converges OL8 with OL9/OL10 content, and that
  kernel-uek-modules stays removed (those claims were derived from upstream
  defaults, not from booted images; this entry supersedes them). What stands,
  measured: EL8's uniquely uncompressed firmware (~1.88 GB installed) made the
  OL8 `UPDATE_TO_LATEST` peak overflow 7 GB, and the `LINUX_FIRMWARE="no"`
  pre-update removal created the headroom that let the 2026-07-13 OL8 rebuild
  complete at 7 GB — the knob is a **build-time transaction-headroom knob, not
  a final-content guarantee**; the packages re-enter via the later
  provisioning flow (mechanism deliberately not investigated — user
  adjudication; the build host was terminated; functionally benign per the
  real-boot E2E). Reworded lock-step: SPEC B.3 key-table row + B.3.4 exception
  paragraph, the ENA/initramfs paragraph + D.28 mechanism attribution (in-box
  ena absence at hook stage is now stated as the direct log observation),
  `env.properties.aws-ol8` comment, README.md / README.ja.md
  `LINUX_FIRMWARE` rows, the nitro-body comment in `build-ol-aws-ami.sh`, and
  comment/message wording in t006/t008. No assert-count change; suite stays
  508.

### Fixed (nitro-initramfs hook: presence-aware drop-in — no more `dracut` FAIL on slim OL8/9/10; latent `--skip-ena-driver` drop-in breakage closed) — SPEC D.28
- **Symptom (2026-07-13 OL8 real-build log)**: the nitro-initramfs hook's
  `dracut -f` failed on every slim OL8/9/10 build with `Failed to find module
  'ena'`. Default builds were rescued by the ENA hook's post-DKMS regen, but
  the hook's own regen never took effect at its stage, and on
  `--skip-ena-driver` builds of OL8/9/10 the persistent drop-in kept naming
  the absent `ena` — breaking every future in-instance `dracut` run (kernel
  updates) and never forcing `nvme` into the initramfs. Root cause: the hook
  runs at source time (before the ENA DKMS build), and on slim OL8/9/10 the
  in-box `ena` ships in `kernel-uek-modules`, removed by the upstream
  `KERNEL_MODULES="no"` default (RPM-payload verified at
  `5.15.0-322.203.3.3.el8uek`: `nvme`/`nvme-core` in kernel-uek-core, `ena`
  in kernel-uek-modules) — there is nothing to force at that stage by design.
- **Fix (two-stage, presence-aware)**: the hook now probes each candidate
  (`nvme`, `nvme-core`, `ena`) with `find /lib/modules/<kver> -name '<drv>.ko*'`
  and writes only present drivers into `02-ol-aws-nitro.conf`, logging absent
  ones as deferred; the ENA hook appends `ena` to the same drop-in
  (idempotent `grep -qsw` gate) **before** invoking the installer, whose own
  post-DKMS `dracut -f` bakes it in. Final image unchanged on default builds
  (nvme+ena); `--skip-ena-driver` OL8/9/10 builds now get a working nvme-only
  drop-in; OL6/OL7 (in-box `ena`) behave as before. `[OLAWS-NVM01]` log line
  updated.
- Tests: `t008` gains static pins (presence probe present, unconditional
  3-driver literal absent, emitted `ena` append precedes the installer invoke)
  and behavioural runs of the extracted hook body against mock `/lib/modules`
  trees with/without `ena` (+11 asserts; suite 497 -> 508). Docs lock-step:
  SPEC ENA/initramfs requirement paragraph, B.4 injection-matrix nitro row,
  D.22 Fix/Prevention, new D.28, Part-E marker table; TESTING.md B-T9 row.

### Fixed (OL8 real-build failure: 7 GB root overflow during UPDATE_TO_LATEST — LINUX_FIRMWARE="no")
- **Root cause (2026-07-13 real AMI build generation, measured)**: the OL8
  build failed in guest provisioning — the `UPDATE_TO_LATEST` dnf transaction
  aborted with "installing package linux-firmware-… needs 631MB on the /
  filesystem". EL8 is the only major whose `linux-firmware` ships uncompressed
  (repodata: ≈ 695 MB package / ≈ 1.88 GB installed, vs ≈ 0.93 GB installed
  xz-compressed on EL9/EL10), and upstream defaults compound it: `ol9-slim`/
  `ol10-slim` remove kernel-modules **and linux-firmware** under
  `KERNEL_MODULES="no"`, while `ol8-slim` keeps firmware behind a separate
  `LINUX_FIRMWARE` knob defaulting `"yes"` — so only OL8 carried and upgraded
  the bulk firmware, overflowing the 7 GB root. OL6/OL7/OL9/OL10 built and
  registered successfully at 7 GB in the same generation.
- **Fix**: `env.properties.aws-ol8` sets `LINUX_FIRMWARE="no"` (upstream-native
  distr knob; the wrapper passthrough already existed with "No recommended for
  cloud VMs"). Removal runs in `distr::kernel_config` before the update, so
  both the GA firmware and the upgrade peak disappear; the uniform
  `DISK_SIZE_GB=7` decision (2026-07-11) stands, and OL8 converges with the
  OL9/OL10 image content. **No dependency cascade** (verified): the failed
  build's log shows `kernel-uek-modules` — the only `linux-firmware` requirer
  on UEK7 — was already erased by the `KERNEL_MODULES="no"` default;
  `kernel-uek-core` needs only the small `linux-firmware-core` (untouched).
  RPM-payload verification: `nvme`/`nvme-core` live in kernel-uek-core; the
  in-box `ena` lives in the removed kernel-uek-modules (the AMI's ENA is the
  DKMS self-build either way).
- Docs lock-step: SPEC B.3 key table + B.3.4 (validation status now records
  the empirical 2026-07-13 result and the OL8 firmware exception); README.md /
  README.ja.md env-key tables. Tests: t006 env parity now allows exactly
  `LINUX_FIRMWARE` as the OL8 extra key and pins its value to `"no"`
  (+1 assert).

### Changed (SSM Agent version policy: OL6 pin lifted — every OL major now follows `/latest/`; QA-preflight pins moved to the verified 3.3.4793.0)
- **Design change (user adjudication, 2026-07-13): `install-ssm-agent.sh`'s
  production default for OL6 moves from the pin `3.3.4624.0` to the `/latest/`
  S3 alias**, unifying every OL major (OL6-OL10) on `latest`. Rationale: the
  OL6 pin existed as a hedge against EL6 NSS/glibc fragility, but the B.10
  install+run sweeps have shown 11 consecutive releases (through `3.3.4793.0`)
  ok on OL6 glibc 2.12 with no fragility materializing. **Re-pin policy** (now
  in SPEC B.11): if an OL6 breakage ever materializes, OL6 reverts to a pin on
  the newest install+run-verified version from the B.10 ledger.
- No wrapper code change: `_ssm_pin_for_major()` now returns `latest` for OL6
  and the existing `_ssm_resolve_latest()` path (GitHub tag + S3 HEAD
  verification) resolves it to a concrete version for the AMI name/description
  and report, exactly as it already did for OL7-OL10 — the "AMI identity never
  says latest" behavior is unchanged. Wrapper/installer comments updated.
- **QA-preflight pins (`pin_for()` in `tests/ssm/run-ssm-installtest-matrix.sh`)
  move to `3.3.4793.0` on every OL major** (was OL6 `3.0.1479.0` / OL7-OL10
  `3.3.3598.0`): the newest install+run-verified version from the committed
  ledger, ok on all five majors in the 2026-07-13 sweep. The old OL6 pin
  `3.0.1479.0` was a below-minimum legacy build and its fetch showed a
  transient timeout in the 2026-07-13 sweep preflight (recovered on retry).
- Docs lock-step: SPEC B.4 injection-matrix SSM row + B.11 "Per-OL version"
  paragraph rewritten; README.md / README.ja.md `install-ssm-agent.sh` rows
  updated in sync. `tests/t018_ssmverdict.sh` is untouched — its
  `3.3.4624.0` / `3.0.1479.0` literals are pure version-comparison fixture
  values, not pins. No test-count change.
- **Committed the real 2026-07-13 five-major SSM install+run sweep**: the ledger
  (`tests/ssm/ssm-installtest-ledger.json`) and `RESULTS-ol{6,7,8,9,10}.md` now
  record 55 rows = 11 in-scope versions (`>= 3.3.3598.0`) x OL6-OL10, all run on
  the maintainer's host (uniform `test_host_kernel` `6.12.0-211.28.1.el10_2`).
  Each OL is **9/11 ok** with max install+run **`3.3.4793.0`** (new upstream
  release, ok on every major incl. OL6 glibc 2.12); the only fails remain
  `3.3.3883.0` / `3.3.4364.0`, whose RPMs return HTTP 403 at the S3 URL (the
  same upstream availability gap as the previous run, not an install/run
  incompatibility) — every OL's verdict stays **compliant-capable**.
- The release list (`tests/ssm/ssm-agent-releases.json`) grows to 207 versions
  (adds `3.3.4793.0`, `rpm_available` 200/ok; no availability flag of any
  existing version changed).
- **Single-sweep replacement (user adjudication, mirroring the 2026-07-13 ENA
  ledger reset)**: the ledger is replaced wholesale rather than grown via the
  kver-PRIMARY dedup append — OL8/9/10 were provisioned with newer UEKs
  (`5.4.17-2136.357.3.2.el8uek` / `5.15.0-322.203.3.3.el9uek` /
  `6.12.0-204.92.4.2.el10uek`), and the superseded rows for the older kernels
  remain recoverable from git history. The dedup-append growth model itself is
  unchanged (SPEC B.10).
- SPEC B.10 and TESTING.md committed-run paragraphs updated lock-step (row
  count, per-OL kver, host kernel, max version, release-list count). No script
  or test change; suite counts unchanged.

### Fixed (Phase-3 exit gate: false FAIL on every sound OL8/9/10 kickstart — %addon uncounted + dynamic partitioning unrecognized)
- **First real firing of the 2026-07-11 exit gate against an EL8-family build
  (OL8 E2E, 2026-07-13) failed a SOUND patched kickstart with 2 findings.**
  Both were gate bugs, not artifact bugs: `_p3_validate_ks` modeled the
  OL7-era kickstart shape only. (1) The section-opener count matched
  `%(packages|pre|post)` and missed the `%addon com_redhat_kdump --disable`
  section that OL8/9/10 upstream kickstarts carry -> "unbalanced kickstart
  sections: 3 openers vs 4 '%end'". (2) It required static `^part ` lines,
  but OL8/9/10 carry none by design: their `%pre` partitions the disk with
  parted and writes the generated `part` commands to
  `/tmp/partitions-ks.cfg`, pulled in by `%include` -> "no 'part' lines
  found (partitioning missing)".
- **Not an upstream regression**: upstream `ol8-ks.cfg` last changed at
  dab64a5 (2025-02-20); re-cloned upstream HEAD cb0a65d3 matches the
  provenance record of the failing build byte-for-byte on this shape. The
  prior OL9/OL10 E2E successes predate the gate itself; OL6 (synthesized)
  and OL7 keep the static-`part` shape and passed all along — this was the
  gate's first contact with the EL8-family shape.
- Fix: the opener regex now counts ALL pykickstart sections (`%pre`,
  `%pre-install`, `%post`, `%packages`, `%addon`, `%anaconda`, `%onerror`,
  `%traceback`; `%include`/`%ksappend` are non-sections and stay uncounted),
  and the partitioning check accepts EITHER static `part` lines OR the
  dynamic pair — a `%include` line whose exact target path also appears
  inside a `%pre` body. Requiring the pair keeps the gate loud when an
  injection eats either half (verified against the real upstream OL8 file:
  removing the `%include`, retargeting the `%pre` write, or dropping one
  `%end` each still yield a finding).
- Verified against reality: the real upstream OL7/8/9/10 kickstarts, with
  the real `_ks_add_sos_package` injection applied, all validate at
  0 findings under the fixed gate.
- Tests: t003 (B-T3) +4 asserts (55 -> 59) — an EL8-family-shaped fixture
  mirroring the real upstream `ol8-ks.cfg` passes as the regression pin,
  and its three broken derivatives (lost `%include`, `%pre` not generating
  the target, missing `%end` with `%addon` present) stay caught. TESTING.md
  B-T3 row and the SPEC `OLAWS-P3GATE01` marker row updated lock-step
  (TESTING.md §0 totals remain deferred per the standing decision).

### Changed (ENA buildtest ledger + RESULTS: 2026-07-12 five-major express sweep recorded; single-sweep reset)
- The deferred ledger/RESULTS refresh (see the pin-refresh entry below) has
  landed: the 2026-07-12 five-major express-scoped sweep (5 majors x 30
  versions = 150 cells, floor `min_version` 2.8.0) is now the working-tree
  ledger, and every `RESULTS-ol<N>.md` is the harness-generated report of that
  run. Headline per major (latest kernel, ok/30, max buildable):
  OL6 UEK4 `4.1.12-124.48.6` 6/30 max **2.9.1** (ceiling unchanged);
  OL7 UEK6 `5.4.17-2136.338.4.2` 13/30 max **2.17.2**;
  OL8 **UEKR7 `5.15.0-322.203.3.3`** 17/30 max **2.17.2** — the first
  harness-recorded proof of the gcc-toolset-11 + UEK-detection-retarget fixes
  below (previously container-FT evidence only);
  OL9 UEKR8 `6.12.0-204.92.4.2` 9/30 max **2.17.2**;
  OL10 UEKR8 `6.12.0-204.92.4.2` 9/30 max **2.17.2**.
  All 58 cells re-tested on an unchanged kernel (OL6/OL7) are
  status-identical to the prior ledger — zero regressions.
- **Single-sweep reset (operator decision, 2026-07-13)**: the committed ledger
  is the 150-row sweep output verbatim; the 87 prior-kernel history rows
  (OL8 UEK6-era `5.4.17-2136.356.4.3`, OL9/OL10 `6.12.0-203.76.7.6`) are
  intentionally dropped from the working tree. The kernel-primary
  keep-history design stays the norm for the post-release era; pre-release,
  superseded-kernel evidence is not worth carrying, and it remains
  recoverable from git history (same recovery route as the retired 210-row
  pre-express ledger).
- Pin cross-check against this evidence: **no pin moves** — the sweep confirms
  every current pin (`ENA_VERSION_OL6` 2.9.1 = the OL6 ceiling;
  `ENA_VERSION_OL7` / `ENA_LATEST_FALLBACK_PIN` 2.17.2 = the OL7-10 max;
  matrix `pin_for()` OL6 2.9.1 / OL7-10 2.17.2; catalog latest 2.17.2).
  The 2026-07-12 pin refresh below is now backed by harness-ledger evidence
  on all five majors.

### Fixed (verify-ena-buildresults.sh: ledger reader used a wrong top-level key — verified 0 rows silently)
- **Found by running the harness-recommended verify command against the real
  2026-07-12 sweep evidence**: `verify-ena-buildresults.sh` printed
  `no OK rows in the ledger` and exited 0 against a ledger holding 54 ok
  rows. The row extractor read `d.get("results", [])` while the ledger
  schema (written and merged by `run-ena-buildtest-matrix.sh`) has always
  keyed the rows as `entries`. Every standalone verification to date was a
  silent no-op with a success rc — the exact false-ok class the verifier
  exists to prevent. Fixed to `entries`.
- With the fix, the verifier judges the real bundle: L4a vermagic-match
  passes 54/54; L4b is load-ready on OL6 (Module.symvers present,
  CRC-matched) and correctly FAILS the other majors because the preserved
  bundle carries `Module.symvers` only for the el6uek kver — a bundle
  producer gap (tracked as a follow-up investigation; the verifier's
  missing-artifact-is-FAIL discipline is working as designed there).
- Regression pin: t016 gains a black-box section — a fixture `entries`
  ledger (one ok + one fail row) against an empty bundle must yield
  `"ok_rows":1` (schema key + status filter), a loud missing-module FAIL,
  rc 1, and must NOT print `no OK rows`; 15 -> 19 asserts.
  Suite: 492 -> 496 (with pykickstart + kmod present).

### Fixed (chore: unify every tracked `.sh` at git mode 100755, 2026-07-12)
- 4 `.sh` files were still tracked at `100644`: the sourced test helpers
  `tests/lib/{assert,heredoc,mock}.sh` and `tests/t016_enaverifyresults.sh`.
  All are now `100755`. Mode-only change; no content diff.
- This applies the repository-wide convention adopted 2026-07-05: **every
  tracked `*.sh` is committed executable (`100755`), sourced-only libraries
  included, no exceptions** - superseding the earlier note (the 2026-06
  exec-bit normalization below) that sourced libraries stay `100644`.
  Machine check before commit: `git ls-files -s -- '*.sh'` must report zero
  `100644` entries.

### Fixed (OL8/UEKR7 self-build: kernel-matching gcc-toolset-11 + UEK-detection retarget)
- **Found by the first UEKR7 QA preflight (2026-07-11)**, immediately after
  the OL8 matrix fidelity fix moved the default track from UEKR6 to UEKR7:
  the preflight died with `no ena.ko found ... [make.log first error:
  unrecognized command line option '-ftrivial-auto-var-init=zero']`. Two
  independent defects, both reproduced and fix-verified in a container FT
  against `kernel-uek-devel-5.15.0-322.203.3.3.el8uek` (2026-07-12):
  1. **Toolchain mismatch**: UEKR7's kernel is built with gcc `11.5.0` while
     OL8's base gcc is `8.5.0`, which rejects the kernel's hardening flags
     (`-ftrivial-auto-var-init=zero`, `-fzero-call-used-regs=used-gpr`).
     `kernel-uek-devel` for UEKR7 declares `Requires: gcc-toolset-11`
     (verified with `rpm -qR`), so the installer now PATH-prepends
     `/opt/rh/gcc-toolset-11/root/usr/bin` whenever `osmajor=8` and the
     target kernel is `5.15.x` — the exact shape of the existing
     OL9/UEKR8 `gcc-toolset-14` block. OL8/UEKR6 (5.4) is untouched;
     `/usr/bin/gcc` is never modified.
  2. **IS_UEK detection miss**: with the toolchain fixed, the build then died
     on `bpf_warn_invalid_xdp_action` — upstream `kcompat.h` collapses the
     call to the pre-5.17 1-arg form unless `IS_UEK >= 5.15.0-100.96.32`,
     and the amzn Makefile derives `IS_UEK` from `uname -r` (the non-UEK
     host/appliance kernel in a chroot/appliance build). The existing
     `patch_ena_uek_detection()` retarget (previously OL6-only, for
     `page_ref_count`) now also applies on OL8. OL7/UEK6 is proven
     unaffected (`2.17.2` built ok with `IS_UEK` unset, 2026-07-11 run);
     OL9/OL10 UEKR8 (`6.12 >= 5.17`) version-exclude the guard.
  - With both fixes, ENA `2.17.2` builds and DKMS-installs as `2.17.2g`
    against `5.15.0-322.203.3.3.el8uek` (container FT; the harness-recorded
    proof lands with the post-fix E2E re-run).
- **`ensure_kernel_devel()` OL8 repo glob was still `*UEKR6*`** — a leftover
  of the pre-UEKR7 default that the 2026-07-11 matrix fidelity fix missed on
  the real-guest header-resolution path. OL8 now enables `*UEKR7*` alongside
  `*UEKR6*`, so the exact `-devel` for a UEKR7 target resolves without
  depending on the guest's own repo config.
- Tests: t010 re-scoped to the OL6|OL8 gate, gains structural pins for BOTH
  gcc-toolset PATH blocks (12 -> 16 asserts); t011 follows the OL7 pin bump
  below. Suite: 488 -> 492 (with pykickstart + kmod present).

### Changed (ENA pins refreshed to 2.17.2 on the 2026-07-11 evidence run)
- 30-version matrix run, 2026-07-11 (kernels: OL6 UEK4 `4.1.12-124.48.6`,
  OL7 UEK6 `5.4.17-2136.338.4.2`, OL9/OL10 UEKR8 `6.12.0-204.92.4.2`; OL8
  produced no rows — its preflight failure is the finding fixed above):
  `2.17.2` builds ok on OL7/OL9/OL10 and still fails on OL6 (`2.9.1` ceiling
  unchanged). Ledger/RESULTS refresh is deliberately deferred to the
  post-fix E2E re-run (operator decision, 2026-07-12).
- `install-ena-driver.sh`: `ENA_VERSION_OL7` 2.17.0 -> **2.17.2**;
  `ENA_LATEST_FALLBACK_PIN` 2.17.0 -> **2.17.2** (operator decision,
  2026-07-12). OL8/9/10 stay latest-resolving (unchanged).
- QA-preflight canary `pin_for()` (matrix): OL7/OL8/OL9/OL10 2.17.0 ->
  **2.17.2** (OL8 on the container-FT evidence pending its harness re-run);
  OL6 stays `2.9.1`.
- `tests/ena/ena-driver-releases.json`: regenerated catalog gains `2.17.2`
  (70 -> 71 releases; upstream ships no `2.17.1`). This is the release-list
  input, not the results ledger — the ledger itself is unchanged by design.

### Added (upstream provenance on every build + Phase-3 exit gate over the patched artifacts)
- Commissioned from the OL7 2026-07-11 investigation: a build died ~30
  minutes in with an opaque "no operating systems were found" and left no
  record of which upstream state or patched-artifact bytes it had built
  from. Upstream stays tracked at HEAD by design (user decision: always
  latest, never pinned); these are the compensating controls.
- **`[OLAWS-UPSTREAM01]` upstream provenance (every build, success or
  failure)**: the exact upstream HEAD (full SHA + commit date/subject) is
  logged right after the Phase-3 clone AND written to
  `${WORKSPACE}/upstream-provenance.txt`; after patching, the file gains the
  applied wrapper patch-marker list and the sha256 of every patched artifact
  (kickstart, cloud/aws/provision.sh, image-scripts.sh). A failing build now
  always leaves behind exactly what it built from, byte-for-byte.
- **`[OLAWS-P3GATE01]` Phase-3 exit gate (real host, pre-install,
  fail=die)**: validates the ACTUALLY patched artifacts at the end of
  Phase 3 - kickstart structure (exactly one `%packages`; exactly one `sos`
  and inside the section; marker uniqueness on OL7-10; `%end` balance;
  bootloader/part shape; NUL scan) and provisioning scripts (hook `>>>`/`<<<`
  bracket pairing per marker, `OLAWS_*` heredoc termination, `bash -n`, also
  on image-scripts.sh). Any finding dies in seconds with the provenance file
  cited - a wrong artifact must cost seconds, not ~30 opaque minutes in
  anaconda. Verified live against the real upstream (OL7 patched ks: PASS;
  %packages removed: 3 findings + die; unpaired hook bracket: caught).
- **ksvalidator is ADVISORY-only** (logged, never gates): it exits 1 even on
  the pristine upstream kickstart (the pre-existing `--nobase` deprecation is
  counted), so its rc cannot gate without failing every build. Phase 1
  best-effort installs pykickstart (dnf/apt); absence degrades the gate to
  structural-only with an explicit log line.
- Tests: t003 gains fixture units for the gate validators (finding-count
  contract; sound artifacts pass, corrupted ones are caught); 50 -> 55
  asserts. Suite: 482 -> 487 (488 with 0 skips where pykickstart is
  installed: the previously-skipped ksvalidator-dependent t005 assert now
  runs too - and R3 makes Phase 1 install pykickstart on build hosts).

### Fixed (OL8 matrix fidelity: the container tests and the update gate targeted UEKR6 while real AMIs run UEKR7)
- **Reliability finding (three-source audit)**: the buildtest ledger (all OL8
  rows = 5.4.17 UEK6-era kvers), the installer code (hardcoded
  `bt_uek_repo="ol8_UEKR6"`), and live yum.oracle.com repomd.xml probes
  (OL8 ships UEKR6 AND UEKR7; UEKR7 is the latest) agree: the OL8 matrix
  validated, and the update-gate `uekr_for()` map watched, a kernel track
  the produced AMIs do not ship (every booted/built OL8 guest runs
  UEKR7 5.15). The other four majors are on their latest available track
  (OL6=UEKR4 only, OL7=UEKR6, OL9=UEKR8, OL10=UEKR8 only). This is why the
  single-cell buildtest "(8, 2.17.2) ok" did not contradict the real build:
  it was a different kernel (kver 5.4.17 vs 5.15.0-322) - the ledger's
  kernel-primary design kept the results honest.
- **Fix**: OL8 buildtest default moves to `ol8_UEKR7` with
  `BT_UEK_REPO_OVERRIDE=ol8_UEKR6` for legacy regression checks (mirrors the
  OL9 two-track pattern), and the update-gate `uekr_for()` map moves OL8 to
  UEKR7 in lock-step. Prior UEK6-era OL8 ledger rows remain as history;
  every (8, x, UEKR7-kver) key is a fresh, untested combination.
- **NEW: identity-consistent user pin `ENA_DRIVER_VERSION`** (env-file key,
  optional, unset by default - the adjudicated pin lever). A concrete x.y.z
  becomes the HIGHEST-priority source in the wrapper chain (user pin ->
  installer pin -> latest -> fallback): it enters the AMI name/description
  AND is passed into the guest hook on EVERY major (pinned-installer majors
  included), so identity and artifact cannot drift. Non-x.y.z values die in
  load_env with a pointed message. Documented (commented) in all five env
  templates; the active common core stays at 21 keys.
- **Guards**: t011 now pins the per-major installer tracks AND the uekr_for()
  map (a track change must be a conscious, test-visible decision) and the
  user-pin wiring; t011 is 31 asserts (count in TESTING.md corrected - the
  stale "15" predated the production-wiring additions). Suite: 472 -> 482.
- **Maintenance rule (SPEC B.9)**: when Oracle ships a new UEK track for a
  major, verify on yum.oracle.com, then update the installer default, the
  uekr_for() map, the t011 pins, and the SPEC track table together.

### Fixed (in-guest install died silently before dkms add - second first-real-build catch)
- **`report_inbox_ena()` (install-ena-driver.sh) could abort the whole guest
  provisioning.** On a guest kernel with NO in-box ena module (observed on the
  first real OL8 build: fresh UEK7 5.15.0-322 before kernel-uek-modules lands;
  the nitro-initramfs hook's "dracut-install: Failed to find module 'ena'" in
  the same log was the visible symptom of the same absence), the three
  unguarded `modinfo | head -1` substitutions failed under the installer's
  `set -euo pipefail` and killed provisioning SILENTLY - after the "Building &
  installing ENA 2.17.2 via DKMS" line, before `dkms add` (image forensics:
  `/usr/src/amzn-drivers-2.17.2` staged, `/var/lib/dkms/` untouched, no
  make.log). Every other such pipeline in the file already carried `|| true`;
  these three were the omission (introduced with the reporting improvements in
  8d08286). Fix: `|| true` on all three - the function is purely informational
  and can now never abort a build. Root cause reproduced and the fix verified
  mechanically in isolation (old form rc=1 + no output; fixed form rc=0 +
  report line).
- **Why the container matrix (B.9) never caught it**: clean-core lacks
  kmod/modinfo, so the function's `command -v modinfo` guard took the skip
  branch in every matrix cell. The new t010 regression runs the SHIPPED
  function text under the real-guest condition (modinfo present, module
  absent) and fails on the old form (negative control verified).
- Same-class hardening (one token): the build heartbeat's
  `virsh domstate | head` gains `|| true` so a domain disappearing between
  polls (normal at install end) can no longer silently kill the background
  progress reporter.
- NOTE: this fix removes the silent death only. Whether ENA 2.17.2 actually
  COMPILES against UEK7 5.15.0-322 on OL8 is a separate, still-open question -
  the (8, x, UEK7) ledger keys are all untested (prior OL8 rows are UEK6-era);
  the running single-cell buildtest answers it.
- Tests: t010 9 -> 12 asserts. Suite: 469 -> 472.

### Fixed (AMI name leaked the raw installer pin line on OL8-10 - first-real-build catch)
- **`_ena_pin_for_major()` / `_ena_fallback_pin()` are now shape-guarded.**
  The original sed pattern (`[^}"]+`, one-or-more) did not match the EMPTY
  default of the latest-resolving majors' pins
  (`ENA_VERSION_OL8/9/10="${...:-}"`), so sed passed the whole assignment
  line through: the raw text leaked into `AMI_NAME`
  (`...-enaENA_VERSION_OL10="${ENA_VERSION_OL10:-}"-...` -> register-image
  charset validation correctly refused), and - the silent half of the bug -
  the non-empty return also suppressed the `[OLAWS-ENA02]` host-side latest
  resolution branch AND the `ENA_DRIVER_VERSION` guest passing on OL8-10.
  Caught by the very first real OL8/9/10 build attempt (2026-07-11); the
  container/static tiers never exercised the extractor against the real
  installer's empty-default form. Fix: `[^}"]*` (zero-or-more) + `sed -n..p`
  + an x.y.z shape guard, so ONLY a concrete version is ever emitted - empty
  defaults and any unrecognized pin form yield "" (= resolve latest / use
  fallback); a parser miss can never reach the AMI identity again. Verified
  live: pins now extract 2.9.1 / 2.17.0 / "" / "" / "" for OL6-10, the
  host-side resolver returns a concrete latest (2.17.2 at fix time), and the
  resulting name passes `validate_ami_name` (62 chars).
- Deliberately NOT touched: the sibling `_ssm_pin_for_major` /
  `_awscli_pin_for_major` extractors share the old pattern but their pin
  maps structurally never use an empty default (the "latest" sentinel fills
  that role), so they are not affected; hardening them would need different
  accepted shapes (`latest` | 4-component SSM versions) and is out of this
  fix's scope.
- Tests: t003 43 -> 50 asserts (fixture-driven extractor matrix via a
  symlinked-wrapper SCRIPT_DIR redirect, plus a real-file shape regression
  that pins OL8-10 extraction to EXACTLY empty - the line the leak rode in
  on). Suite: 462 -> 469.

### Changed (boot-E2E feedback: 7 GB disks, sos baked in, opt-in Amazon Time Sync)
- **`DISK_SIZE_GB` 10 -> 7, uniform across OL6-10** (user decision 2026-07-11,
  aligned with Oracle's own AWS AMIs). Safe by construction: every root
  partition is `--grow` and `cloud-utils-growpart` is baked into the image,
  so the value is a floor, not a ceiling (larger launch volumes auto-expand);
  AWS forbids launching below the AMI's registered size, so smaller strictly
  widens the launch envelope. Measured post-build root usage from the
  2026-06-16 E2E generation: OL6 1.4G / OL7 3.4G / OL8 3.6G / OL9 2.3G /
  OL10 2.0G - 7 GB keeps >= 2.4G headroom on the heaviest major. No runtime
  floor guard (same philosophy as the rejected ENA installer guard); the
  knowledge lives in SPEC B.3.4 and the t006 parity pin. The wrapper-side
  `load_env` fallback moves 10 -> 7 in lock-step. First real build at 7 GB
  is part of the next [C]3 / B-T8 cycle.
- **`sos` (sosreport tooling) baked into every AMI via kickstart.** OL6: the
  wrapper-synthesized kickstart lists `sos` directly. OL7-10: new
  `_ks_add_sos_package()` inserts `sos` under the first `%packages` line of
  the upstream `distr/ol{N}-slim/ol{N}-ks.cfg` (marker
  `[ol-aws-ami-builder PATCH sos-package]`, logged `[OLAWS-SOS01]`;
  idempotent; dies on a missing `%packages` section with the file untouched
  - assert-then-write). Verified against the real upstream kickstarts of all
  four majors (insert-once + idempotent second run + die path). Package name
  confirmed from the E2E sosreports: plain `sos` (noarch) on every major.
- **NEW opt-in switch `--enable-amazon-time-sync` / env key
  `AMAZON_TIME_SYNC` (default `"no"`).** DEFAULT OFF by user decision: time
  configuration belongs to the AMI's end user, so distribution defaults are
  never changed unless explicitly asked. When enabled, phase3 appends a
  guest-side block (`[ol-aws-ami-builder PATCH amazon-time-sync]`, logged
  `[OLAWS-TIMESYNC01]`) that adds the link-local Amazon Time Sync Service
  (169.254.169.123) as the PREFERRED source - /etc/chrony.conf on OL7-10,
  /etc/ntp.conf on OL6, guest-side file detection, distro pool kept as
  fallback, idempotent on both sides. Origin: the E2E sosreports showed the
  public NTP pool as the only time source. AMI name/description unaffected.
  The env key joins the common core (20 -> 21 keys, all five templates in
  lock-step).
- **Boot-E2E evidence recorded (TESTING.md note, 2026-07-11)**: the
  2026-06-16 generation booted on real EC2 across ALL five majors (0 failed
  units on OL7-10; OL6 self-built ENA 2.9.1g actually driving the NIC on an
  ENA-capable Xen-generation instance - OL6 Nitro path still untraveled;
  OL7 DKMS 2.17.0g loaded). Explicitly NOT proven by that generation:
  OL8-10 self-build, baked SSM/CLI, and the 7 GB disks - these remain the
  open [C]3 / B-T8 items.
- Tests: t003 25 -> 43 asserts (`--enable-amazon-time-sync` contract +
  `_ks_add_sos_package` behavioural unit), t006 42 -> 54 (21 core keys,
  `DISK_SIZE_GB="7"`, `AMAZON_TIME_SYNC="no"`, sos wiring invariants),
  t007 marker pin 9 -> 11. Suite: 440 -> 462 (measured).

### Changed (release-agnostic maintenance: ISO_URL becomes the single touch point)
- **OL9 template moved to Oracle Linux 9.8** (`OracleLinux-R9-U8-x86_64-dvd.iso`,
  released 2026-07). With the changes below, this is - by design - a
  one-line diff in `env.properties.aws-ol9`.
- **All release-bound example text removed from the living templates
  (OL9/OL10)**: the ISO section heading, the checksum route #3 URL example,
  the `# OS_VARIANT` / `# AMI_NAME` / `# AMI_DESCRIPTION` examples, and the
  `DISTR` annotation now use the release-agnostic `<N>` placeholder form.
  The stale-prone "Verified-good SHA256 (as of ...)" pinned-hash comments
  are dropped in favor of the existing automatic checksum resolution
  (route #3, `derive_oracle_checksum_url`). The `ISO_URL` line is now
  marked `>>> SINGLE-TOUCH MAINTENANCE POINT <<<` in both templates.
- **`DEFAULT_ISO_URL` removed; `ISO_URL` is now a required env key**
  (`load_env` dies with a pointed message when unset). The built-in
  fallback was a hard-coded OL10 release URL that would go stale on every
  Oracle update release; every documented invocation path already supplies
  `--env` with a template that sets `ISO_URL`, so no supported workflow
  changes behavior.
- **Docs de-versioned in lock-step** (README.md / README.ja.md tables and
  section-7 examples, SPEC A.9.3 / A.9.x constants list / B.3 required-keys
  and per-template tables): OL9/OL10 rows no longer name a concrete update
  release; OL6/OL7/OL8 rows are explicitly marked frozen at their terminal
  releases (U10 / U9 / U10). The B.3 maintenance rule now reads "update the
  `ISO_URL` line; that is the only change".
- Historical records (this CHANGELOG, README development-history notes) and
  parser test fixtures (`t003`) intentionally keep their concrete versions;
  they describe past states, not the current release.

### Added (first express-scoped five-major ENA sweep - E2E evidence)
- **`tests/ena/buildtest-ledger.json` + `RESULTS-ol{6,7,8,9,10}.md`**: the
  first ENA-Express-era sweep on the maintainer's host (2026-07-05), 145 rows
  = 29 in-scope versions x OL6-OL10. Integrity checks performed before
  commit: zero cells below the `2.8.0` floor, all rows `express-ready`, zero
  `ko_version` mismatches (the false-ok guard clean), all five RESULTS
  byte-reproduced from the ledger by the committed `--report-only` path, and
  the run used byte-identical committed scripts + release snapshot.
- Windows established: OL6 UEK4 `4.1.12-124.48.6` -> 6/29 (`[2.8.6, 2.9.1]`,
  the known window; `2.8.0`-`2.8.5` fail on the UEK-detect patch site); OL7
  UEK6 `.338.4.2` -> 12/29 (`[2.12.2, 2.17.0]`, byte-reproducing the retired
  run's `>= 2.8.0` subset on the same kernel - UEK6 has a `2.8.0`-`2.12.1`
  kcompat gap); OL8 UEK6 `.356.4.3` (kernel advanced from `.4.2`; the
  kver-primary dedup re-tested the full set as designed) -> 12/29 (same
  window as OL7); OL9/OL10 UEKR8 `6.12.0-203.76.7.6` -> 8/29 each
  (`[2.13.2, 2.17.0]` - consistent with the 2026-07-03 evaluation on the same
  kernel and now precise: the UEKR8 buildable floor is `2.13.2`).
- The r61 reporting ports are confirmed working in production: fail reasons
  carry the make.log first compiler error, and the per-kernel Fail pattern
  analysis tables group the failures by root cause.
- Clean-core SBOMs verified byte-identical to the committed six (the
  clean-core rootfs excludes the kernel, so the OL8/OL9/OL10 kernel updates
  do not touch them) - no SBOM change needed.
- Docs lock-step: SPEC B.9 and TESTING.md sweep-evidence paragraphs updated
  from "reset skeleton awaiting the first sweep" to the recorded results.

### Changed (ENA self-build goes production on OL6-OL10)
- **`build-ol-aws-ami.sh` injects the ENA self-build hook on all five majors
  by default** (`--skip-ena-driver` still opts out to a pure OL AMI). The
  former OL6/OL7-only gates — hook injection, `-ena<ver>` AMI naming, and the
  final-summary ENA line — are retired; the driving requirement is the AWS
  ENA generation update (the produced AMI must ship an ENA-Express-capable
  driver).
- **Host-side latest resolution (`[OLAWS-ENA02]`, new log marker).** For the
  latest-resolving majors (OL8/9/10, empty installer pins) `load_env` resolves
  amzn-drivers latest on the build host via `_ena_resolve_latest_host()`
  (mirrors `_awscli_resolve_latest`: `git ls-remote --tags` newest-first +
  tarball HEAD verification; live-verified in-session -> `2.17.0`) and falls
  back to the installer's concrete `ENA_LATEST_FALLBACK_PIN`
  (`_ena_fallback_pin()`) when offline — the AMI identity always carries a
  concrete x.y.z, never the word "latest". The resolved version is passed
  into the guest hook as `ENA_DRIVER_VERSION`, so the AMI name/description
  and the actually-built module can never drift (the installer's own runtime
  resolution remains the standalone / container-test path). OL6/OL7 keep
  reading the installer pins (`_ena_pin_for_major`, unchanged).
- **Caveat carried in the docs (SSM-integration precedent):** real AMI boot
  with an OL8/9/10 self-built driver is not yet E2E-verified — container
  compile + DKMS-install proof only. The `[C]3` real-build E2E remains the
  standing follow-up.
- **`tests/t011_enareporting.sh` grows an OL6-10 wiring section** (+6
  asserts): host resolver + fallback reader defined, `[OLAWS-ENA02]` marker
  present, `ENA_DRIVER_VERSION` pass-through line present, the old "hook not
  injected for OL" branch gone, and no residual OL6/OL7-only
  `ENA_DRIVER_BUILD` gate anywhere in the wrapper.
- Docs lock-step: SPEC (installer self-gating + validated-E2E paragraphs, the
  Phase-3 hook table, the log-marker table, B.9's follow-up paragraph),
  TESTING.md, README.md/README.ja.md (installer + `--skip-ena-driver` rows),
  installer header/variable comments.

### Changed (ENA Express era: matrix scope + reporting migrate to the RHEL-sibling v2 spec)
- **The ENA build-test evidence is RESET for the ENA Express era.** The AWS ENA
  generation update makes ENA Express support a hard requirement for the
  produced AMIs, so express-incapable driver releases no longer inform the
  product: `tests/ena/buildtest-ledger.json` is reset to an empty schema-1.1
  skeleton and `RESULTS-ol{6,7,8}.md` are removed. The retired pre-express
  evidence (a real 210-row all-release run, 70 versions x OL6/7/8) remains in
  git history only. OL6's known buildable window `[2.8.6, 2.9.1]` sits inside
  the express scope, so no OL6-relevant signal is lost.
- **Default sweep scope = the ENA Express floor (v2 parity).**
  `list-ena-releases.sh` now emits schema 1.2: top-level `min_version`
  (default `2.8.0`, the express-ready / `ena_srd_*` metrics floor) plus
  per-entry `ge_min` and `express_verdict`; the snapshot was regenerated for
  real (live `git ls-remote` + 70 tarball HEAD probes; 29 of 70 releases in
  scope, `2.8.0`..`2.17.0` — identical to the RHEL sibling's scope). The
  matrix reads `min_version` as its default floor (hard filter over every
  version source), `--full` lifts it, and the explicit `--ena-min-version`
  override is retained.
- **All five OL majors are first-class matrix targets.** `--ol` defaults to
  `6,7,8,9,10` and OL9/OL10 results are recorded in the ledger like any other
  major (the former "evaluation only" framing is retired; the pipeline-side
  wiring is the next change).
- **`ena_express_verdict()` lands as a reuse-by-copy family (RHEL-sibling r31
  port).** The source of truth lives in `install-ena-driver.sh` (production
  log line states the readiness next to the installed `ena.ko`; both
  `ENA_BUILDTEST` result JSONs carry `ena_express`), copied into
  `list-ena-releases.sh` and duplicated in the matrix's ledger-merge Python
  (which back-fills `ena_express` across every ledger entry on each write).
  `tests/t021_enaexpress.sh` (new, 33 asserts) keeps the three
  implementations in behavioural agreement over a boundary set and asserts
  the 1.2 schema + scope plumbing.
- **Reporting upgrades (RHEL-sibling r61 port).** `install-ena-driver.sh`
  embeds the DKMS make.log's FIRST compiler error in both build-failure
  reasons (the plain-failure die and the false-ok verdict path), so ledger
  reasons carry the specific kernel-API root cause; each per-kernel report
  section gains an automatic **Fail pattern analysis** table grouping
  consecutive fail versions by recorded reason (omitted when a kernel has no
  fails); the latest-kernel summary gains a standing ENA Express readiness
  note. Report `notes` cells now escape `|`.
- **`--report-only` mode (v2 report-mode parity).** Regenerates
  `RESULTS-ol<N>.md` and the ledger's derived fields from the existing ledger
  with no builds — python3 only, no root / containers / network (rehearsed
  in-session against a synthetic ledger; grouping, note, and enrichment all
  verified).

### Changed (B1 - docs only, zero script change)
- **SPEC Part A migrated to the vendored model.** The inline Part A (old A.1-A.11,
  the pre-extraction de-facto family reference) is replaced by the **8 canonical
  regions vendored from the bash spec home** `governance/spec/bash.md` (marker+hash,
  verified by the document-conformance gate) plus project-specific extensions
  **A.9-A.17** carrying the content observed only in this project (reference assets,
  script layout, 9-phase pipeline registry, extended log markers, env-property
  conventions, OL version auto-detection, libguestfs caller pattern + diagnostics,
  documentation/revision specifics, parameter inventory). Old->new section map:
  A.1->A.9, A.2->A.2(common)+A.10, A.3->A.11, A.4->A.3(common)+A.12,
  A.5->A.5(common)+A.15, A.6->A.4(common)+A.17, A.7->A.13, A.8->A.14,
  A.9->A.5(common)+A.15, A.10->A.7(common)+A.16, A.11->A.8(common)+A.16.
  Cross-references in Parts B-E and TESTING.md updated to the map (historical
  CHANGELOG entries keep their as-of-then numbering); SPEC front-matter re-pinned
  to template canon 1.1.0. TESTING.md gains its doc-provenance pin (was the one
  doc-set member without one). This CHANGELOG's revision-identifier note corrected
  to the ground truth (commit hash; no in-script `rNN` banner exists).

### Added

- **ENA driver self-build test infrastructure extended to OL9/OL10 (evaluation
  only; `tests/ena/run-ena-buildtest-matrix.sh`, `install-ena-driver.sh`).**
  In support of an ENA Express readiness investigation, `ENA_BUILDTEST` is now
  wired for OL9/OL10 in addition to OL6/7/8, and the matrix gained a new
  `--ena-min-version <x.y.z>` floor (e.g. `2.8.0`, the AWS-documented ENA
  Express metrics-reporting threshold) applied as a hard filter regardless of
  version source. `install-ena-driver.sh` gained `_ena_resolve_latest()`
  (mirrors `_awscli_resolve_latest()`: `git ls-remote --tags` against
  `amzn/amzn-drivers`, HEAD-verifies the tarball, falls back to
  `ENA_LATEST_FALLBACK_PIN` on failure) so `ENA_VERSION_OL8/OL9/OL10` default
  to **latest** rather than a fixed pin, overridable via `ENA_DRIVER_VERSION`
  or the per-OS `ENA_VERSION_OL<N>` variables. **Real buildtest-matrix runs
  (2026-07-03) against clean-core OL9/OL10 containers established:**
  - **OL9 and OL10 both build successfully with amzn-drivers latest (2.17.0)
    against UEKR8 (6.12 kernel)** — the confirmed-working QA-preflight canary
    for both (`pin_for()` updated accordingly).
  - **ENA 2.8.0 (the ENA Express metrics floor) fails to compile against
    UEKR8 on BOTH OL9 and OL10** with an identical error: `ena_netdev.c`
    calls `xdp_do_flush_map()`, which upstream Linux renamed to
    `xdp_do_flush()` before the 6.12 baseline; 2.8.0's `kcompat.h` predates
    the rename. So "use the minimum version that meets ENA Express's stated
    driver-version floor" is the wrong strategy on UEKR8 -- latest is
    required there regardless of the nominal floor.
  - **OL9/UEKR8 also needs a newer build-time gcc.** OL9's base-OS gcc
    (11.5.0) cannot compile against UEKR8's `kernel-uek-devel` (built with gcc
    14.2.1): DKMS aborts on an unrecognized flag
    (`-fmin-function-alignment=16`) before any driver-code issue is reached.
    Oracle's `kernel-uek-devel` package for UEKR8 already declares an RPM
    dependency on `gcc-toolset-14` (confirmed via a real `yum install`
    transaction), so `install-ena-driver.sh` now prepends
    `/opt/rh/gcc-toolset-14/root/usr/bin` to `PATH` when
    `osmajor=9 && kver=6.*uek*` -- no separate package install needed, and
    OL9/UEKR7, OL10, and OL6/7/8 are untouched.
  - **OL9 defaults to UEKR8, not UEKR7** (`uekr_for()`, `bt_uek_repo`,
    `ensure_kernel_devel()`'s `--enablerepo` pattern) -- OL9 ships both tracks
    (UEKR7 enabled by default, UEKR8 present but disabled, per a real
    `uek-ol9.repo`), and there is no reason to keep testing the older track
    now that UEKR8 builds successfully. Override via
    `BT_UEK_REPO_OVERRIDE=ol9_UEKR7` for a UEKR7-specific regression check.
  - **OL10's EPEL section name is `ol10_u1_developer_EPEL`, not
    `ol10_developer_EPEL`** (confirmed from a real `oracle-epel-ol10.repo`):
    OL10's developer/EPEL path is versioned per OL10 update point release
    (`.../OL10/1/developer/EPEL/...`), unlike OL8/OL9's unversioned path.
  - All of the above findings are load-bearing for -- but do **not** yet
    change -- the **production** AMI pipeline: `build-ol-aws-ami.sh` still
    gates the self-build hook to OL6/OL7 only; OL8/9/10 remain on their
    in-distro ENA driver. Wiring OL9/OL10's confirmed-working `latest`
    combination into the production pipeline (name/description marker,
    `--skip-ena-driver` interaction, Phase 3 hook) is tracked as follow-up
    work, alongside a full (non-`--ena-min-version`-narrowed) matrix run in
    the maintainer's own environment.

- **AWS CLI v2 production install integrated into `build-ol-aws-ami.sh` (OL6/OL7/OL8; default ON).**
  By default (`AWSCLI_INSTALL=1`) the wrapper now installs **AWS CLI v2** into the
  guest on **OL6/OL7/OL8**, so a built AMI ships v2 as the standard CLI (AWS CLI v1
  is increasingly unsupported). Phase 3 appends a marker-bracketed hook
  `[ol-aws-ami-builder PATCH awscli-install]` to `cloud/aws/provision.sh` that writes
  `install-awscli.sh` verbatim into the guest and runs it (install the per-OL bundle
  + exclude the OL-repo v1 `awscli` via versionlock), mirroring the SSM hook.
  **NON-FATAL** (utility tooling, not Nitro-critical): a transient failure warns and
  provisioning continues. `--skip-awscli` opts out. **OL9/OL10 are out of scope** —
  they install AWS CLI v2 from their default package manager, so the hook is not
  injected there (an info line is logged) and `--skip-awscli` has no effect on them.
  **AMI identity:** when enabled, the AUTO-default `AMI_NAME` appends `-awscli${ver}`
  and the description `, AWS CLI v2 ${ver}` — always a **concrete `x.y.z`**: OL6 the
  pin `2.17.51`, OL7/OL8 the `latest` bundle resolved to a concrete published version
  by `_awscli_resolve_latest()` (enumerate v2 tags via `git ls-remote --tags`, walk
  newest-first, return the highest whose CDN zip is published via a HEAD — the newest
  tag can lead CDN publication). Display/identity only: the guest still installs the
  OL7/OL8 `latest` bundle. If resolution fails (e.g. an offline `--build-only`), the
  identity **omits the awscli marker** rather than ever printing `latest`. Per-OL pin
  read from `install-awscli.sh`'s `AWSCLI_VERSION_OL<major>` via `_awscli_pin_for_major()`
  (single source of truth, mirroring `_ssm_pin_for_major()`). The final report gains
  an `AWS CLI:` line. `--skip-awscli` + knobs log + usage added. New SPEC **B.13**
  (+ B.4 marker row, B.1 `AMI_NAME`/`AMI_DESCRIPTION` rows, switch table) + README
  pair (flag row + script-inventory row, bilingual lock-step) + TESTING.md.
  `tests/t007_idempotency.sh` marker count **8 -> 9**; suite **388 -> 389**.

- **awscli matrix: QA-preflight pin aligned to 2.17.51.** `tests/awscli/run-awscli-installtest-matrix.sh`'s
  `pin_for()` smoke version moves `2.17.49` -> `2.17.51` to match the OL6 production
  pin (`install-awscli.sh` `AWSCLI_VERSION_OL6`). 2.17.51 is the empirically highest
  install+run build on OL6 (glibc 2.12) -- the last GLIBC_2.5 / Python-3.11.9 build --
  so it remains a safe cross-OL (6/7/8) preflight health-check. Smoke-only: the value
  does not appear in the committed ledger/RESULTS (those carry one row per real
  attempt) and is not unit-tested, so the suite is unchanged at **388/0/0**. The
  documented manylinux heuristic boundary (`>= 2.17.50 -> 2.17`) and the AWS-documented
  `<= 2.17.49` citation in the report header are unchanged.

- **AWS CLI v2 install+run E2E results committed; OL6 production pin 2.17.49 -> 2.17.51.**
  Landed the maintainer's real OL6/OL7/OL8 install+run matrix run (a clean-core +
  network task not reproducible in the authoring env): `tests/awscli/awscli-installtest-ledger.json`
  (2763 entries = 3 OL x 921 v2 versions, dedup `(osmajor, awscli_version, kver)`
  kver-PRIMARY, one uniform `test_host_kernel`), `tests/awscli/awscli-releases.json`
  (921 versions; one unavailable = `2.0.32`, HTTP 404 at the CDN), and
  `tests/awscli/RESULTS-ol{6,7,8}.md` (which regenerate byte-identically from the
  ledger via the matrix's own generator; every fail reason verified verbatim against
  its per-version log). **Empirical glibc axis result:** OL6 (glibc 2.12) installs+runs
  through **`2.17.51`** -- the last build whose bundled `.so`s need only `GLIBC_2.5`,
  and the last bundled-Python-3.11.9 build; `2.17.52` is the first to require
  `GLIBC_2.17` (and the first Python-3.12 bundle) and fails on OL6. OL7 (glibc 2.17)
  and OL8 (glibc 2.28) install+run current (`latest` = `2.35.6`, Python 3.14.5); the
  only non-cap fail on either is the same `2.0.32` upstream 404, not an
  incompatibility. **Ground-truth correction (AGENTS §4):** the documented `<= 2.17.49`
  boundary (which AWS commits to) understates OL6 by 2 patches, so `install-awscli.sh`
  `AWSCLI_VERSION_OL6` is bumped **`2.17.49` -> `2.17.51`** (the highest version proven
  to run; same bundled Python 3.11.9 / security-support end 2027-10-31, so a newer
  CLI/botocore at no Python-EOL cost). OL7/OL8 stay `latest`. SPEC **B.12**'s three
  OL6 behavioral/empirical claims are corrected to `2.17.51` (the AWS-documented
  `<= 2.17.49` citation and the documented manylinux heuristic boundary at `2.17.50`
  are both unchanged -- the *measured* floor is the separate field that moves at
  `2.17.52`). Data only on the test side: the deliverables are `.json` / `.md`, so the
  suite is unchanged at **388/0/0**; production integration into `build-ol-aws-ami.sh`
  remains deferred (install-test tooling), mirroring SSM.

- **OL6-OL10 clean-core builders: floating-tag builder image with pinned fallback.**
  Adopted the OL5 builder's tag-based container-image acquisition across
  `tests/cleancore/build-cleancore-ol{6,7,8,9,10}.sh`. Each now **pulls its `N-slim`
  image by its floating tag** from the Oracle container registry
  (`container-registry.oracle.com/os/oraclelinux:N-slim`) over the OCI registry v2
  API as the **primary** source (shared, self-contained `oci_pull_rootfs()`:
  anonymous token -> manifest/multi-arch index -> amd64 sub-manifest -> gzip layer
  blobs via `curl`, or a `podman`/`docker` `pull`+`export` fast path if present),
  so the builder always tracks the latest N.x slim. If the registry is unreachable
  it **falls back** to the byte-stable **pinned `N-slim` git-raw rootfs**
  (`oracle/container-images` at `CI_COMMIT`); OL6 keeps the OL6.6 public-yum image
  as a third fallback. Verified all five `N-slim` tags pull anonymously with the
  expected tooling (OL6/OL7 -> `yum`, OL8/OL9/OL10 -> `microdnf` + `rpm`). Robustness
  only: the acquisition is build-use, so the deliverable (curated `--installroot`
  set against `yum.oracle.com/latest`) is unchanged; OL6's `BUILDER_KIND` keeps the
  TLS-modernization on the OL6.6 path only. Host `curl` uses `-k` only under
  `INSECURE_TLS=1`. Docs: SPEC.md **B.8** (Per-OL table + acquisition bullet),
  TESTING.md ([B] BUILDER note). Suite unchanged **388/0/0** (lint-only delta).
  Added a live `build-cleancore-ol5.sh` (= OL5.11) clean-core test-base builder and
  wired it into the `build-cleancore.sh` orchestrator (`--all` now spans
  `5,6,7,8,9,10`), motivated by quasi-validation of legacy OL5 systems still running
  in the Japanese market. End-to-end verified in-sandbox: **125 packages, self-test
  15 passed / 0 failed / 1 skipped (PASSED)**, with a names-only SBOM
  `cleancore-ol5.sbom.json`. OL5 is the deepest EOL member — its `rpm` stays 4.4 /
  BerkeleyDB-4.3 forever and its in-OS `openssl` 0.9.8e tops out at TLS 1.0, so it
  can neither write a modern rpmdb nor reach the TLS-1.2-only `yum.oracle.com`, and
  no distributed OL5 image carries a usable EL5 rpm over the normal channel.
  **Architecture (OL10 work-env model):** the HOST installs nothing and pulls the
  latest distributed `oraclelinux:10` image (floating `:10`) over the **OCI registry
  v2 API with `curl`** (anonymous token -> index -> amd64 manifest -> single ~94 MB
  layer; no container runtime) as a throwaway work environment; that OL10 env does
  the TLS-1.2 work — fetch the OL5 metadata + RPMs, resolve the closure (**dnf
  first**, empty installroot + `--releasever=5`; an embedded checksum-agnostic
  **Python resolver** is the fallback that EL5's directory-`provide` semantics, e.g.
  `libxml2-python` needing `/usr/lib64/python2.4`, force in practice), and bootstrap
  an **EL5-native builder** (`rpm2cpio | cpio` from the OL5 RPMs). The HOST then does
  a single-level EL5 `chroot` in which the EL5-native **`createrepo` 0.4.11** writes
  the sha1/gzip repodata EL5 `yum` 3.2.22 can read (OL10's `createrepo_c` emits only
  sha256, uncheckable by EL5 yum) and `yum --installroot` installs the clean-core
  from a `file://` mirror — no in-OS TLS, rpmdb db4.3 written by EL5-native rpm. EL5
  yum lacks `--releasever`/`--setopt` (so `tsflags=nodocs` lives in the builder
  `yum.conf`) and exits non-zero on a successful `Complete!` under chroot (so install
  success is gated on the rpmdb package count, not the exit code); the sandbox egress
  CA is seeded into the OL10 work-env trust store (no-op on a real host). EL5 deltas:
  **`git` and `jq` omitted** (no EL5 build of either — `jq` not even in the EPEL 5
  archive), versionlock = `yum-versionlock`, release = `oraclelinux-release`,
  `procps`/`nc` + `net-tools`. Docs updated: SPEC.md **B.8** (OL5 row + "EL5
  specific" note), the REFERENCE "Oracle Linux 5" section flipped from feasibility to
  shipped, TESTING.md. Suite **386/0/0 -> 388/0/0** (+2: the new builder is walked by
  B-T1 parse + B-T2 ShellCheck).

- **`register-image` input validation + `--dry-run` pre-flight (Phase 9).**
  Hardened the AMI registration in `build-ol-aws-ami.sh` against the documented
  AWS EC2 `register-image` constraints. (1) Two new pure validators —
  `validate_ami_name` (`--name`: length **3-128**, allowed set = alphanumerics
  and the literals `()[]` space `. / - ' @ _`) and `validate_ami_description`
  (`--description`: length **0-255**) — are called in `load_env` right after the
  AMI name/description are resolved, so an out-of-range or mis-charactered value
  (typically an explicit override, or an unexpectedly long auto name) fails fast
  with a clear `die` **before** the Phases 1-8 build rather than at the very end.
  (2) Phase 9 now runs a `register-image --dry-run` pre-flight with the real
  argument set before the actual registration: per the AWS API a dry run that
  *would* succeed returns the error `DryRunOperation`, so the real call is gated
  on detecting `DryRunOperation` and is aborted (no AMI created) on anything else
  (e.g. `UnauthorizedOperation` for a missing IAM permission, or a parameter
  error). New unit tier `tests/t020_register.sh` (23 asserts) covers the
  validators across length boundaries, realistic auto names, the full allowed
  special set, and disallowed characters; the live dry-run remains E2E (B-T8).
  Suite **361 -> 386** (20 tiers): +23 (t020) and +1/+1 to B-T1/B-T2 (the new
  `.sh` is parse- and lint-checked). Docs: SPEC.md (Phase 9 + register-image
  input validation) + TESTING.md.

- **versionlock plugin in the clean-core default package set (OL6-OL10).** The
  package-pinning plugin is now a default `INCLUDE` member of every clean-core
  test-base builder: `yum-plugin-versionlock` on OL6/OL7 and
  `python3-dnf-plugin-versionlock` on OL8/OL9/OL10. Repository survey: the package
  is in each OS's **standard** repo already enabled by the builder (OL6/OL7
  `latest`, OL8-OL10 `baseos`), so it is a plain `INCLUDE` add with **no extra
  repo** (unlike OL6 `jq`) — including on OL6, the version of concern. This gives
  the base package-hold/exclude capability out of the box, parallel to the
  install-test/production versionlock usage (e.g. `install-awscli.sh`'s v1 block).
  The plugin's only named dependency is already in the base set (`yum` on OL6/OL7;
  `python3-dnf-plugins-core` on OL8-OL10), so each `cleancore-ol<N>.sbom.json` is
  a clean `+1` (OL6 165->166, OL7 198->199, OL8 206->207, OL9 186->187, OL10
  177->178); the authoritative package set is re-confirmed on the next clean-core
  rebuild. Docs: SPEC.md (B.1 clean-core package set) + TESTING.md. The builders
  are not run by `run-all.sh` (root + network + multi-hundred-MB build), so the
  suite is unchanged at 361/0/0.

- **AWS CLI v2 install+run test matrix (install-test tooling; `tests/awscli/`).**
  New `install-awscli.sh` (modes: production / `AWSCLI_INSTALLTEST=1`) plus
  `tests/awscli/run-awscli-installtest-matrix.sh`,
  `tests/awscli/list-awscli-releases.sh`, and the pure-logic tier
  `tests/t019_awscliverdict.sh`. The matrix characterizes, per **OL6/OL7/OL8**,
  which AWS CLI v2 versions install AND run on the **glibc** axis: v2 bundles its
  own Python built against a manylinux glibc, so the OS glibc gates install/run
  (OL6 glibc 2.12 caps at v2 `<= 2.17.51` empirically — see the E2E entry above;
  OL7/OL8 run current). Each ledger entry
  records the **bundled CPython** (`bundled_python`, read offline from the bundle
  so a glibc-too-old result still carries it), the **empirical glibc floor**
  (`min_glibc_measured` — the max `GLIBC_x.y` symbol required across the bundle's
  `.so`s, a dependency-free grep matching `readelf`) with the documented heuristic
  `min_glibc` as a cross-check, and the bundled Python's documented end-of-life
  (`python_eol`). `RESULTS-ol<N>.md` carries a provenance-stamped (verified date +
  sources) **static** Python-EOL table and the **OS's own EOL/EOS**, surfacing the
  frozen-bundled-Python lifecycle risk (the bundle's Python is not independently
  patchable; a glibc-capped OS caps the Python too). The v1 OL-repo `awscli` is
  blocked in the production path via versionlock. Suite **310 -> 361** (19 tiers;
  new `t019` = 43 asserts, B-T1 47 / B-T2 42). The release list / ledger / RESULTS
  are produced by a real maintainer-env run (NOT committed from this authoring
  environment). Production integration into `build-ol-aws-ami.sh` is deferred,
  mirroring SSM.

- **SSM Agent production install in `build-ol-aws-ami.sh` (default ON; OL6-OL10;
  `--skip-ssm-agent` to opt out).** Phase 3 now appends a marker-bracketed hook
  (`[ol-aws-ami-builder PATCH ssm-agent-install]`) to `cloud/aws/provision.sh`,
  mirroring the ENA self-build hook: it writes `install-ssm-agent.sh` verbatim
  into the guest and runs it, so the AMI boots with an installed, **boot-enabled**
  Amazon SSM Agent and is AWS Run Command compliant out of the box (agents
  `>= 3.3.3598.0`; the legacy `ec2messages` endpoints retire 2026-06-16).
  `install-ssm-agent.sh` gains a per-OL version map (`SSM_AGENT_VERSION_OL<major>`:
  **OL6 pinned `3.3.4624.0`, OL7-OL10 `latest`**) and a production-only
  service boot-enable (systemd on OL7+, SysV/upstart on OL6) — the install-test
  path (`SSM_INSTALLTEST=1`) is unchanged, so the B.10 matrix + ledger are
  untouched. The wrapper adds `SSM_AGENT_INSTALL=1` / `--skip-ssm-agent`,
  `_ssm_pin_for_major()`, and an `-ssm<ver>` / `-ssmlatest` AMI name/description
  suffix. The hook is **non-fatal** (unlike the Nitro-critical ENA hook): the SSM
  Agent is management tooling, so a transient fetch failure warns and lets
  provisioning continue. The in-guest RPM fetch uses a plain `curl -fsSL` (the same
  TLS model as the ENA hook). New PATCH marker count is pinned at 8 (`t007`). SPEC
  B.11 + the B.4 marker table + README pair documented. **Validation:** OL6-OL8
  install+run is matrix-verified and OL6/OL7 boot-validated on Nitro; OL9/OL10
  install+run is matrix-verified but the SSM-enabled AMI is not yet boot-validated
  on a real instance (shipped enabled with that caveat).

- **Committed the SSM release list + a provisional sample ledger/report
  (`tests/ssm/`).** Now that the harness generates them in-sandbox (it could not at
  first), `ssm-agent-releases.json` (the deterministic matrix INPUT: 206 upstream
  versions with RPM availability and the go.mod `go_version`) and a provisional
  `ssm-installtest-ledger.json` + `RESULTS-ol6.md` are committed, mirroring the ENA
  release-list + sample precedent (B.9). The sample is an OL6 run of three
  representative versions (`3.0.1479.0` below the minimum, the `3.3.3598.0`
  boundary, the latest `3.3.4624.0`); all install+run on the sandbox's modern
  kernel (verdict compliant-capable), and a real run in the maintainer's env / CI
  grows the ledger via the kver-PRIMARY dedup append. Also fixed
  `list-ssm-releases.sh` to not abort under `set -e` on pre-go-modules tags (which
  have no go.mod, so the `go_version` grep matched nothing): the lookup now yields
  an empty `go_version` (recorded as null) instead of failing the whole run. SPEC
  B.10 + TESTING updated to reflect the committed artifacts.

- **AWS SSM Agent install+run test harness (`tests/ssm/`, `install-ssm-agent.sh`).**
  A dev/CI harness structurally mirroring the ENA matrix (B.9): per OL major it
  determines, in a disposable clean-core container, which SSM Agent versions
  **install and run** on this `(kernel, glibc)`, and evaluates them against the
  AWS minimum `>= 3.3.3598.0` (the 2026-06-16 Run Command `ec2messages`
  deprecation). New `install-ssm-agent.sh` (`SSM_INSTALLTEST` mode) installs the
  RPM with `rpm -Uvh` (local file, no repo — only glibc is required, avoiding the
  EL6 yum-over-HTTPS NSS quirk; the NOKEY warning and the container's missing init
  system are benign) and runs `amazon-ssm-agent -version` locally (no AWS/IMDS) to
  prove the Go runtime loads; `status=ok` requires install + run + version match.
  `tests/ssm/list-ssm-releases.sh` collects the version list (`git ls-remote`) with
  per-version RPM availability and the **go.mod `go_version`** (fetched from
  raw.githubusercontent.com — the kernel-axis build signal; the spec's `golang`
  BuildRequires is stale). `tests/ssm/run-ssm-installtest-matrix.sh` runs the
  matrix: ledger dedup `(osmajor, ssm_version, kver)` kver-PRIMARY with `glibc` +
  `go_version` per entry; a default (`>= 3.3.3598.0`) vs `--full` version filter;
  an SSM-version update gate; and per-OS `RESULTS-ol<N>.md` with the max-install+run
  verdict (`compliant-capable` / `ec2messages-only` / `none`) plus a
  `min_kernel(proxy)` column derived from `go_version`. **Fidelity:** the glibc
  axis is faithful in a container; the kernel axis is not (`kver` is the runner's
  kernel), so the go.mod-derived proxy is the static kernel-axis signal and a
  faithful kernel verdict needs a kernel-matched runner / real instance. The pure
  verdict/proxy/filter logic is unit-tested by the new `tests/t018_ssmverdict.sh`
  (23 cases, host-only — no container/network). Manual / on-demand (NOT a
  `run-all.sh` tier); the ledger + RESULTS are generated on the first real run
  (not committed); production integration into `build-ol-aws-ami.sh` is deferred.
  Feasibility verified end-to-end in-sandbox (OL6 clean-core; `3.0.1479.0` dynamic
  and `3.3.4624.0` static both install + run). SPEC B.10 + TESTING added.

- **Load-readiness bundle PRODUCER in the ENA matrix
  (`tests/ena/run-ena-buildtest-matrix.sh`).** Completes the pair with the 0016
  verifier: after each build, a dumb `cp` (no load-readiness judgement, no branch
  on the build's ok/fail status) preserves the artifacts the build already
  produced into the exact layout `verify-ena-buildresults.sh` reads -- the
  DKMS-built `ena.ko` to `<bundle>/modules/ol<N>-ena_<ver>-<kver>.ko`, and the
  shared per-kver `Module.symvers` + `kernel.vermagic` (sourced from a **stock**
  in-tree module, so the verifier's L4a vermagic compare stays independent of the
  freshly built module) + an `initramfs.list` (`lsinitrd`, else `cpio -t`) to
  `<bundle>/kver/<kver>/`. New `--bundle-dir` flag; defaults to
  `<cleancore-dir>/verify-bundle`. The bundle accumulates like the ledger
  (per-version module added, shared per-kver files overwritten idempotently); a
  failed build leaves no DKMS module to copy, so none is fabricated (the verifier
  flags a missing ok-row artifact itself). The `cp` layout is contract-tested
  against the verifier's read-paths by the new `tests/t017_enabundle.sh` (13 cases,
  a host-only unit test over a fabricated image tree -- no real build/kernel/kmod).
  SPEC B.9 and TESTING updated. End-to-end against a real matrix run remains the
  user's-env / CI step.

- **External, read-only ENA build-result verifier
  (`tests/ena/verify-ena-buildresults.sh`).** Answers the layer above
  `ENA_BUILDTEST` -- "would the built module actually load on its target
  kernel?" -- as a SEPARATE pass that never touches the production build path
  (composes as build -> verify -> build). It reads the matrix ledger plus a
  small verification bundle the build preserved (per-version `ena.ko`; shared
  per-kver `Module.symvers` + kernel `vermagic` + initramfs listing) and emits
  its own report. Per ok row: L4a vermagic-match and L4b symbol-CRC vs
  `Module.symvers` are gates (a fail = would not `insmod`); L3 initramfs-
  inclusion is informational (DKMS/dracut territory; ena-absent is not a
  defect); L5 real load is skipped (needs real Nitro, B-T8). A missing bundle
  artifact for an ok row is a fail, never a silent skip. The pure verdict logic
  is unit-tested by `tests/t016_enaverifyresults.sh` (15 cases). Module
  integration stays delegated to DKMS; no judgement is added to the build script.

### Changed

- **`tests/cleancore/REFERENCE-oracle-official-images.md` renewed into a pure
  container-image report.** Each OL6-OL10 section now records BOTH builder-image
  acquisition sources separately: the **① `container-registry.oracle.com/os/oraclelinux:N-slim`**
  floating-tag image (the new primary; captured RPM manifest, 2026-06-18) and the
  **② pinned `oracle/container-images@0218ab4` `N-slim`** rootfs (the fallback; its
  own manifest). The two are NVRA-identical today but are kept distinct because the
  floating tag advances while the pin is frozen. OL6 additionally keeps the **③
  legacy `oraclelinux:6.6`** manifest as a third-fallback reference. The **OL6 and
  OL5 sections were rebuilt on the OL10 template**: the OL6 "Availability
  investigation" / "OL6 optimization" memo and the OL5 feasibility-study / PoC memo
  were removed; OL5 now documents the official **`oraclelinux:5` (5.11)** full image
  (123 packages; OL5 predates `*-slim`, so no `5-slim`, no git-raw rootfs, no
  public-yum docker image). The registry channel is standardized on
  `container-registry.oracle.com` (what the builders pull) instead of GHCR. The OL5
  base-facts, the TLS-1.2 / mirror rationale, and the EL5 PoC record were relocated
  to TESTING.md ("OL5 background & base facts"). Reference-only; no code or gate change.

- **OL6 clean-core builder now uses the `6-slim` (OL6.10) rootfs as the primary
  base, with the OL6.6 image as a fallback.** `tests/cleancore/build-cleancore-ol6.sh`
  acquired its EL6-native *builder* from the legacy OL6.6 public-yum docker image,
  whose 2014-era NSS/curl cannot TLS-handshake modern `yum.oracle.com` — so it
  host-fetched the `el6_10` NSS/curl/ca-certs/openssl RPMs and rpm-installed them to
  modernize the builder before it could resolve packages. Investigation (2026-06-17)
  found an `ol6-slim` **does** exist: `ghcr.io/oracle/oraclelinux:6-slim` (OL6.10,
  digest `sha256:dbae3e47…`) and, crucially, the same OL6.10 rootfs is pinned in
  `oracle/container-images` at commit `0218ab4` — the **same channel and pin the
  OL7/OL8 builders already use** — as a plain `FROM scratch + ADD rootfs.tar.xz`
  tarball (`oraclelinux-6-slim-amd64-rootfs.tar.xz`, HTTP 200; permanent at the
  pinned commit even though OL6 was dropped from the repo's `main`). The builder now
  fetches that 6-slim rootfs first (a direct `curl` + extract, like OL7/OL8) and
  falls back to the OL6.6 docker image only if the fetch fails. **Optimization:** the
  6.10-slim rootfs already ships the `el6_10` stack (verified: OpenSSL 1.0.1e, NSS
  3.36 line, `libcurl.so.4`), so the entire TLS-modernization fetch + `rpm -Uvh` is
  **skipped on the primary path** and runs only on the 6.6 fallback — removing the
  OL6 path's single most fragile step and aligning its acquisition shape with
  OL7/OL8. The clean-core deliverable is a fresh `yum --installroot` install with the
  **same `INCLUDE`**, so `cleancore-ol6.sbom.json` (names-only) is unchanged; only
  finalized package *versions* move forward (re-confirmed on the next clean-core
  rebuild). The builder is lint-only in `run-all.sh` (root + network + multi-hundred-MB
  build), so the suite is unchanged at 386/0/0. Docs: `REFERENCE-oracle-official-images.md`
  (availability investigation + OL6 optimization) + SPEC.md + TESTING.md.

- **SSM Agent: persistent AMI identity + final report now show a concrete
  version, not `latest`.** "latest" is unsuitable for a persistent artifact, so
  `build-ol-aws-ami.sh` resolves the `/latest/` alias (for OL7-OL10) to a concrete
  S3-published version via `_ssm_resolve_latest()` (GitHub `releases/latest` tag +
  an S3 HEAD verify, since the tag can lead S3 publication; logged as
  `[OLAWS-SSM02]`) and uses it in the `-ssm<ver>` AMI name, the AMI description,
  the `[OLAWS-SSM01]` injection log, and a new `SSM Agent:` line in the final
  build report. This is **display/identity only** — the in-guest install path is
  unchanged (the hook still installs the `/latest/` alias), so install behaviour
  does not depend on the build host. Resolution is best-effort: an offline build
  (or a GitHub tag that leads S3) falls back to the literal `latest`.

- **SSM ledger: OL9/OL10 re-run on the maintainer's host (uniform OL6-OL10
  `test_host_kernel`).** A maintainer End-to-End run executed the full OL6-OL10
  matrix on one host, so OL9/OL10's `test_host_kernel` moves from the in-sandbox
  clean-core build's `6.18.5` to the maintainer's `6.12.0-211.22.1.el10_2` --
  the same runner as OL6/7/8. The run independently reproduces the committed
  OL9/OL10 result rows exactly (same `kver`, `glibc`, `status`, and the two
  `3.3.3883.0` / `3.3.4364.0` HTTP-403 fails), so only the `test_host_kernel`
  field changes (20 ledger rows) and `RESULTS-ol9/ol10.md` re-render with the new
  environment line; OL6/7/8 rows + reports are byte-unchanged, RESULTS stay
  byte-reproducible from the ledger, and every fail reason still matches its run
  log. `ssm-agent-releases.json` unchanged. SPEC B.10 + TESTING updated.

- **SSM install+run matrix: extended to OL9 and OL10; committed the real
  OL6-OL10 ledger + reports (`tests/ssm/`).** The matrix now wires OL9 and OL10
  alongside OL6/7/8: `install-ssm-agent.sh` provisions the OL UEK via
  `ol9_UEKR7` / `ol10_UEKR8` (each with the OL8-style dnf->yum bootstrap, since
  the 9-slim/10-slim bases ship dnf only), and `run-ssm-installtest-matrix.sh`
  gains OL9/OL10 in its per-OL guard, QA-preflight pin, default OL list, and
  usage. The committed `ssm-installtest-ledger.json` grows from 30 to **50 rows**
  (10 versions x OL6/OL7/OL8/OL9/OL10) and `RESULTS-ol9.md` / `RESULTS-ol10.md`
  are added. OL9 is UEK7 `5.15.0-321.202.5.1.el9uek` (glibc 2.34) and OL10 is
  UEK8 `6.12.0-203.76.7.3.el10uek` (glibc 2.39), each **8/10 ok** with the same
  two fails as the other majors -- `3.3.3883.0` / `3.3.4364.0`, whose RPMs return
  HTTP 403 at the S3 URL (an upstream availability gap, not an install/run
  incompatibility) -- so every OL's verdict stays `compliant-capable` (max
  install+run `3.3.4624.0` >= `3.3.3598.0`). OL9/OL10 were run from a separate
  clean-core build (`test_host_kernel` `6.18.5`); the OL6/7/8 rows are byte
  unchanged, the reports regenerate byte-identically from the merged ledger, and
  every fail's recorded reason matches its run log. `ssm-agent-releases.json` is
  unchanged. SPEC B.10 + TESTING updated. Tooling-doc only (dev/CI evidence); the
  AMI build path is unchanged.

- **SSM report now records the OL kernel from the rpm db (not the runner's), and
  its columns are category-labelled.** Per the review: the install+run test now
  provisions the OL UEK into the kernel-less container
  (`yum --enablerepo=<UEKR> install kernel-uek`) the same install-at-test-time way
  the ENA matrix does, so `kver` is read authoritatively from the rpm db
  (`rpm -q kernel-uek`, e.g. `4.1.12-124.48.6.el6uek.x86_64`) exactly as `glibc` is
  -- instead of `uname -r`, which in a container is the runner's kernel, not the
  OL's. The runner kernel the binary actually executed on is still recorded, now as
  a separate `test_host_kernel` field, and the report's fidelity note keeps the
  honesty that the run does not exercise the OL kernel axis (a container shares the
  host kernel). The ledger dedup key `(osmajor, ssm_version, kver)` is therefore
  now keyed on the OL UEK, mirroring ENA. `RESULTS-ol<N>.md` was restructured for
  clarity: it opens with a paraphrased summary of the AWS Systems Manager Run
  Command `ec2messages` deprecation (with AWS doc links) so a third-party reader
  sees why versions below `3.3.3598.0` matter; the constant test environment moves
  into a `env_kernel` / `env_glibc` / `test_host_kernel` block; and the per-version
  table uses category-prefixed columns (`agent_go_version` = the agent's Go build,
  `compat_min_kernel` = the Go-derived compatibility floor) so the three distinct
  meanings are no longer conflated. `install-ssm-agent.sh`,
  `run-ssm-installtest-matrix.sh`, the sample ledger + `RESULTS-ol6.md`, and SPEC
  B.10 + TESTING were updated together.


  review: `tests/ssm/list-ssm-releases.sh` records, alongside `go_version`, a
  `go_version_available` (bool) and `go_mod_http_status` (mirroring the rpm fields)
  so a null `go_version` explains itself -- `404` is a pre-go-modules tag with no
  go.mod (distinct from a `200` carrying no `go` directive); the data also makes the
  Go-modules adoption boundary (at SSM `3.0.1390.0`) self-evident. Both the release
  list and the ledger now store the `min_kernel` kernel-axis proxy as explicit data
  (previously derived only at report time), so the (Go, kernel) relationship is
  legible without running code. The `go_min_kernel` mapping is one logic,
  reuse-by-copy in the lister and the matrix, kept in lock-step by a new
  `tests/t018_ssmverdict.sh` consistency check (t018: 23 -> 32 cases). The committed
  `ssm-agent-releases.json` and sample `ssm-installtest-ledger.json` + `RESULTS-ol6.md`
  were regenerated with the new fields. SPEC B.10 + TESTING updated.

- **Both clean-core matrices now set an explicit, per-driver build work-dir
  (`--work-dir`), so concurrent ENA + SSM runs never collide.**
  `run-ena-buildtest-matrix.sh` and `run-ssm-installtest-matrix.sh` previously let
  `build-cleancore.sh` fall back to its fixed `/tmp/cleancore-ol<N>` scratch, which
  two concurrent runs of the same OL would share (and the builder `rm -rf`'s it).
  Each matrix now passes `--work-dir` explicitly, defaulting to a distinct,
  outside-the-source-tree base (`${TMPDIR:-/tmp}/cleancore-work-ena-buildtest` /
  `...-ssm-installtest`) and overridable per run. Added an irregular-placement
  safety guard: each matrix refuses to run if its script dir or the resolved
  work-dir is `/` (or empty), since the builder's `rm -rf` on the scratch could
  otherwise reach the OS root. (No source-tree pollution, so the lint tiers are
  unaffected.)

- **ENA build-test matrix: committed the real OL6/OL7/OL8 E2E ledger + reports,
  replacing the in-environment sample (`tests/ena/`).** The previous
  `buildtest-ledger.json` / `RESULTS-ol6.md` were a 2-row OL6 sample; they are
  replaced by the maintainer's real full-release-list run (210 rows = 70 ENA
  versions x OL6/OL7/OL8, one kernel per OL). OL6 UEK4
  `4.1.12-124.48.6.el6uek` builds 6/70 -- exactly the documented `[2.8.6, 2.9.1]`
  window (`2.10.0`+ fail on the ECC build-time autodetect); OL7 UEK6 and OL8 UEK6
  build 35/70 each. `RESULTS-ol7.md` / `RESULTS-ol8.md` are added. The ledger was
  verified well-formed, the reports regenerate byte-identically from it (no
  hand-edits), every fail is a real compile/install failure (no synthetic/infra
  rows), and there are no false-ok rows (the kver-mismatch ledger guard correctly
  downgraded the OL7/OL8 `2.2.12` row). The generated `RESULTS-ol<N>.md` preamble
  and SPEC B.9 / TESTING now state explicitly that an `ok` is "compiled +
  DKMS-installed" -- necessary, not sufficient; real module load and device
  attach remain B-T7/B-T8 (and the read-only load-readiness verifier).
  Tooling-doc only (dev/CI evidence); the AMI build path is unchanged.

- **SSM install+run matrix: committed the real OL6/OL7/OL8 E2E ledger + reports,
  replacing the provisional sample (`tests/ssm/`).** The previous
  `ssm-installtest-ledger.json` / `RESULTS-ol6.md` were a 3-version OL6 sample;
  they are replaced by the maintainer's real default-mode (`>= 3.3.3598.0`) run
  (30 rows = 10 versions x OL6/OL7/OL8, one UEK per OL: OL6 UEK4
  `4.1.12-124.48.6.el6uek`, OL7 UEK6 `5.4.17-2136.338.4.2.el7uek`, OL8 UEK6
  `5.4.17-2136.356.4.2.el8uek`; `test_host_kernel` = the runner's OL10 kernel).
  Each OL is 8/10 ok: `3.3.3883.0` and `3.3.4364.0` are the only fails -- their
  RPMs are not published at the S3 URL (HTTP 403), an upstream availability gap,
  not an install/run incompatibility -- so every OL's verdict is
  `compliant-capable` (max install+run `3.3.4624.0` >= `3.3.3598.0`).
  `RESULTS-ol7.md` / `RESULTS-ol8.md` are added. The ledger was verified
  well-formed, the reports regenerate byte-identically from it (no hand-edits),
  and every fail's recorded reason matches its run log. `ssm-agent-releases.json`
  is unchanged. SPEC B.10 + TESTING updated to describe the real run.
  Tooling-doc only (dev/CI evidence); the AMI build path is unchanged.

- **Test tier rename: `tests/t12_enaverify.sh` -> `tests/t015_enaverify.sh`
  (resolve a tier-number collision).** The ENA self-build verify tier was
  introduced as `t12_*` alongside the pre-existing `tests/t012_buildvisibility.sh`
  -- two `t12_*` tiers. Both ran (the runner globs `tests/t[0-9]*.sh`), so the
  suite was correct, but the duplicate number bent the "tiers named by execution
  order" convention. Renamed to the next free number; no logic change (still 12
  cases). Doc references updated.

- **ENA matrix harness: clearer, more user-friendly run logging
  (`tests/ena/run-ena-buildtest-matrix.sh`).** Each OL is now framed by a `===`
  banner, the QA-preflight and build-matrix phases by `----` separators, every
  build line carries an `[i/N]` progress counter, and each OL closes with a
  `matrix done -- X ok, Y fail, Z skipped (of N)` line plus a final
  `ENA matrix complete -- ...` summary (mirroring the clean-core builder's
  result + summary style). Log presentation only -- no behaviour change; the
  ledger and reports are byte-identical.

### Fixed

- **OL6 clean-core SBOM under-reported `jq` and its EL6 dependencies
  (`tests/cleancore/cleancore-ol6.sbom.json`).** A real OL6 clean-core build
  (the `6-slim` OL6.10 primary builder) was run and its deliverable `rpm -qa`
  name set compared against the committed SBOM: the build installs **169**
  packages but the SBOM listed **166**. The three missing names are `jq` plus
  its EL6 runtime dependencies `libjq1` and `oniguruma`, which OL6 pulls in when
  `jq` is installed transiently from the EPEL archive in finalize (SPEC B.8 — on
  OL6 `jq` is an EPEL package, not a base-repo `INCLUDE` member, so it is sourced
  outside the main transaction). The drift dates to the commit that added `jq` to
  every clean-core builder (`install jq in every OL clean-core builder`): the
  SBOMs were not refreshed for it, and the later `versionlock` `+1` (165->166)
  carried the omission forward. Corrected the drifted fields **names-only**:
  added `jq`, `libjq1`, `oniguruma` in sorted position and bumped
  `package_count` **166 -> 169**; `versions_included` stays `false`. The SBOM is a
  static, hand-refreshed snapshot (not a `.sh`, so outside B-T1/B-T2 and not a
  gated artifact), the builders are not run by `run-all.sh`, and no `.sh` changed,
  so the suite is unchanged at **386/0/0**. NOTE: the same `jq` omission very
  likely affects the OL7-OL10 SBOMs (the adding commit touched every builder), but
  those clean-cores were not rebuilt this session, so their SBOMs are left
  unchanged pending their own real builds (ground-truth over inference).

- **OL7/OL8/OL9/OL10 clean-core SBOMs under-reported `jq` and its dependencies
  (`tests/cleancore/cleancore-ol{7,8,9,10}.sbom.json`).** Completes the cross-OL
  correction flagged in the preceding OL6 entry: each of the remaining four
  clean-cores was really rebuilt (its `N-slim` builder) and its deliverable
  `rpm -qa` name set compared against the committed SBOM. On OL7-OL10 `jq` is a
  base-repo `INCLUDE` member (installed in the main transaction, not EPEL-transient
  like OL6), but it was added to the builders after the SBOMs were last snapshotted,
  so every SBOM still omitted it. The missing names, taken **per-OS from the real
  build (ground-truth, not inferred — the dependency set differs by EL major)**:
  OL7 `jq`, `libjq1`, `oniguruma` (199 -> 202); OL8 `jq`, `oniguruma` (207 -> 209);
  OL9 `jq`, `oniguruma` (187 -> 189); OL10 `jq`, `oniguruma` (178 -> 180). EL8/EL9/EL10 package `jq` without a separate `libjq1`, so only
  `jq` + `oniguruma` are added there, whereas EL6/EL7 also carry `libjq1`.
  Corrected **names-only** (added the missing names in sorted position; bumped each
  `package_count`; `versions_included` stays `false`). As with OL6 these are static
  hand-refreshed snapshots (not `.sh`; outside B-T1/B-T2; builders not run by
  `run-all.sh`) and no `.sh` changed, so the suite is unchanged at **386/0/0**. All
  five clean-core SBOMs now match their real builds.

- **`TESTING.md` drift corrected to the live suite (`TESTING.md`).** The "Running
  the suite" headline still claimed **206 passed / 1 skipped** with an 11-tier
  breakdown, and the coverage ledger stopped at `t012`. Updated to the verified live
  result: **310 passed / 0 skipped / 0 failed across 18 tiers**, with the full
  per-tier breakdown and the drifted B-T1 / B-T2 assert counts refreshed (33->43,
  28->38, from added project scripts). Added coverage-ledger rows for
  `t013_enaledgerguard`, `t014_enacheck2`, `t015_enaverify`, `t016_enaverifyresults`,
  `t017_enabundle`, and `t018_ssmverdict`, and a `python3` entry under "Environment &
  version dependencies" documenting the cpio-free initramfs fallback. Documentation
  only; no behaviour change.

- **The ENA-bundle initramfs fixture is now cpio-independent, so its assertions
  RUN instead of SKIPping where `cpio` is absent (`tests/t017_enabundle.sh`,
  `tests/ena/run-ena-buildtest-matrix.sh`).** `tests/t017_enabundle.sh` builds a
  gzipped-newc-cpio initramfs and `preserve_bundle()` lists it; both required
  `cpio`, so a host without it (a minimal CI container) deterministically skipped
  two assertions. Both sides gain a self-contained `python3` newc fallback: the
  fixture builder writes the gzipped newc archive, and `preserve_bundle()`'s listing
  chain appends a `python3` reader after `lsinitrd` / `zcat|cpio -t`. Real builder
  hosts always have `lsinitrd`/`cpio` and never reach the fallback (behaviour there
  is byte-identical); `python3` is effectively universal, so the two skips are now
  passes. The matrix's "no sourced module" design is preserved (the reader is inline
  in `preserve_bundle()`, so `tests/t017`'s single-function `sed` extraction still
  carries it). Full suite: 308 passed / 2 skipped -> **310 passed / 0 skipped**.

- **Intermittent suite false-negative eliminated: `assert_match` no longer trips a
  SIGPIPE-under-`pipefail` race (`tests/lib/assert.sh`).** `assert_match` matched
  with `printf '%s' "$1" | grep -Eq -- "$2"`. `grep -q` exits at the first match
  and closes its stdin; on a large haystack (e.g. the ~28 KB `install-ena-driver.sh`
  read whole by `tests/t010_enaukedetect.sh`) the upstream `printf` is still writing
  and takes SIGPIPE, exiting 141. Under the tiers' `set -o pipefail` that 141 became
  the pipeline status, so a genuine match was reported as "no match" -- a
  load-dependent flake (~1/12-1/17 in the full suite, ~0 in isolation) that surfaced
  on a *different* assertion each time as the early match landed at a different file
  offset. The matcher now feeds the haystack via a here-string
  (`grep -Eq -- "$2" <<<"$1"`): no upstream writer process exists, so the command
  status is grep's alone and the race cannot occur. Verified: 0 flakes in 26 full-suite
  runs (was 2/25 + 1/12); suite pass count unchanged. (`t011`/`t012` had previously
  worked around the *symptom* with file-direct greps; the source is now fixed.)

- **ENA build-test verdict reason no longer hardcodes "EL6" for every OS.** The
  `ena_buildtest_verdict()` failure message in `install-ena-driver.sh` attributed a
  failed build to "the EL6 dkms exit 0" masking -- but the function is OS-agnostic
  and runs for all majors, so the committed `RESULTS-ol7.md` / `RESULTS-ol8.md` (and
  OL6) carried the EL6-specific claim even on OL7/OL8, where it is inaccurate (the
  exit-0 quirk is the old EL6 dkms 2.4.0; newer dkms returns non-zero). The reason
  is rewritten to the OS-agnostic observable fact: the dkms build did not produce a
  module matching the request, the installed module version (not the build exit
  status) is authoritative, and only the stock in-tree module remains. The
  EL6-specific rationale is retained where it belongs -- the code comments
  explaining WHY the version-based check exists. The committed
  `buildtest-ledger.json` reason fields (88 rows: 18 OL6, 35 OL7, 35 OL8) were
  corrected and `RESULTS-ol{6,7,8}.md` regenerated from it (the maintainer's real
  results are unchanged -- only the explanatory wording). `tests/t015_enaverify.sh`
  still passes unchanged (it asserts the surviving "stock in-tree module remains").

- **Phase 6 CHECK 2: a self-build that did not take effect is now a `FAIL`
  (`build-ol-aws-ami.sh`).** Layer 3 of the false-ok remediation. CHECK 2 passed
  on mere ENA module presence, so an AMI that requested the self-built pin but
  ended up with only the stock in-tree `ena.ko` would still pass. The check now
  gates the PASS on provenance via the pure `_ena_check2_ok`: when a self-build
  ran (`ENA_BUILD_VERSION` set -- OL6/OL7 default) the effective module must be
  the DKMS `/updates|/extra` copy, else `FAIL`; when no self-build was requested
  (`--skip-ena-driver`, OL8+ in-distro, OL9+) any present module still passes.
  With `install-ena-driver.sh` now aborting on a failed build, this is a
  defense-in-depth image guard (manual builds, other installers, regressions).
  SPEC D.23 updated; tested by `tests/t014_enacheck2.sh`.

- **ENA test-matrix ledger: a version-mismatched `ok` is recorded as `fail`
  (`tests/ena/run-ena-buildtest-matrix.sh`).** Defense-in-depth on top of the
  installer fix: the ledger writer trusted `install-ena-driver.sh`'s `status`
  verbatim. It now independently checks the recorded `ko_version` against the
  requested `ena_version` and downgrades an `ok` to `fail` (with an explanatory
  reason) when they do not match — so a masked build failure (or a row produced
  by an older installer that fell back to the stock in-tree `ena.ko`) cannot
  enter the ledger as `ok` and silence the kver-primary dedup gate. SPEC B.9
  updated; tested by `tests/t013_enaledgerguard.sh`.

- **ENA self-build: a failed driver compile is no longer reported as success
  (`install-ena-driver.sh`).** The verify asserted only that *some* `ena.ko`
  existed and downgraded a version mismatch to a non-fatal warning. But EL6
  `dkms` (2.4.0) returns exit `0` even when the in-guest compile fails (so
  `set -euo pipefail` did not catch it), and `kernel-uek` ships a stock in-tree
  `ena.ko` (`1.1.2`); together these made a failed build (e.g. ENA `2.12.0`,
  whose ECC build-time autodetect false-positives on UEK4 and emits the absent
  `irq_update_affinity_hint`) report `status:ok` with the stock module's version.
  The verify now decides success from the installed module *version*: it walks
  every `ena.ko` under the tree and requires one whose `modinfo` version matches
  the requested `ena_version` (prefix match; the pin installs as e.g. `2.9.1g`),
  failing fatally otherwise via the new pure `ena_buildtest_verdict`. This fixes
  false `ok` rows in the ENA test-matrix ledger AND makes a production AMI build
  abort on a non-building pin instead of silently shipping the stock driver.
  Unit-tested by `tests/t015_enaverify.sh` (12 cases: pin/exact/above-window
  builds pass; stock-only, none-found, and wrong-version fail).

- **ENA matrix harness: run the ENA build by absolute `/bin/bash` under an
  explicit PATH (fixes `env: bash: No such file or directory` on usrmerge
  hosts).** `run_one_buildtest` entered the clean-core with
  `chroot "$img" env … bash /install-ena-driver.sh`; the `chroot` inherits the
  host's PATH, but the EL6 clean-core ships bash only at `/bin/bash` (no
  usrmerge). On a usrmerge host whose PATH omits `/bin`, `env` could not find
  `bash` and every ENA build failed in ~2 s with `env: bash: No such file or
  directory` before `install-ena-driver.sh` ran (it worked only where the host
  PATH happened to include `/bin`). The harness now exports an explicit
  `PATH=/usr/sbin:/usr/bin:/sbin:/bin` and execs `/bin/bash` by absolute path, so
  both bash and `install-ena-driver.sh`'s own tools (`yum`/`rpm`/`curl`/…) resolve
  regardless of the host PATH. Verified in-env on a real OL6 run: `2.9.1` now
  builds to `ok` (~3 min, kernel module produced) and `2.2.0` fails with its real
  build reason (UEK Makefile patch did not apply) rather than the exec error.

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
  `<cleancore-dir>/buildtest-ol<N>-ena_<ver>.log` (and the path is logged) so the
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

- **ENA matrix per-OL update gate (`tests/ena/run-ena-buildtest-matrix.sh`,
  `--strict`; `--force` now also bypasses it).** Before building anything for an
  OL, the matrix probes whether the live upstream has something the ledger has not
  covered, so a no-change OL costs only the probes (no clean-core build). Two
  probes, compared to the ledger with the existing `vkey` order: the latest
  `kernel-uek` (x86_64) for the OL from `yum.oracle.com` (`repomd.xml` →
  `primary.xml.gz`, parsed with the python3 standard library only — `gzip` +
  `xml.etree`, no extra package — under the fixed `OL → UEKR` map OL6=`UEKR4`,
  OL7/8=`UEKR6`; source RPMs ignored), and the latest upstream `ena_linux` tag
  (`git ls-remote`, rate-limit-immune, falling back to the release-list JSON).
  A new kernel **or** a new ENA (latest only — releases are incremental) **or** no
  ledger entry runs the OL; otherwise it is skipped with the ledger untouched. A
  probe that cannot determine the latest is fail-open (the OL runs) by default, or
  fail-closed (skipped) under `--strict`. `--force` now bypasses the gate (every OL
  runs) in addition to the per-combo dedup; the mandatory QA preflight is
  unaffected. Network is `curl` (bounded by `--max-time` / `--max-filesize`); the
  dynamic "follow the latest UEKR" refinement is deferred to a whole-project
  cleanup (D.11/D.12 fix the map). SPEC B.9 + TESTING.md document it; no new `.sh`
  (logic lives in the matrix script) so the B-T1/B-T2 per-`.sh` counts hold.
  Second of the ENA matrix preflight/gate pieces.

- **ENA matrix mandatory QA preflight (`tests/ena/run-ena-buildtest-matrix.sh`,
  `--preflight-retries`).** Before the version matrix, each OL first builds only
  its pinned ENA version as a smoke test that the clean-core rootfs +
  `install-ena-driver.sh` are healthy. It is QA-only — **not recorded in the
  ledger** — and a clear failure early-exits that OL (the matrix is skipped, the
  ledger left untouched), writing a self-contained diagnostic bundle
  `<cleancore-dir>/preflight-ol<N>-FAILED.log` (header with OL / pin / kver /
  reason / host context, then the full `install-ena-driver.sh` output) for human
  / LLM analysis. Transient-looking failures (mirror / `kernel-uek` provision /
  network hiccups) retry up to `--preflight-retries` (default 2); a clear
  build/compile failure is treated as real and not retried. Mandatory in **every**
  mode (incl. `--force`); the matrix then re-builds the pin as the recorded
  per-run canary, so the pin is built twice by design. SPEC B.9 + TESTING.md
  document it; no new `.sh` (logic lives in the matrix script) so the B-T1/B-T2
  per-`.sh` counts are unchanged. First of the ENA matrix preflight/gate pieces.

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
  `tests/ena/RESULTS-ol<N>.md` reports regenerated newest-kernel-first — each
  opening with a `## Latest kernel <kver> - N/M ok` summary of the ENA versions
  that build on the newest kernel tested, so the latest result stays visible as
  kernels accumulate below (a `fail` is recorded evidence, not a harness error →
  the run still exits 0). Ships an
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
  - New regression tier `tests/t012_buildvisibility.sh` (17 asserts) guards all of
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
  Guarded by a new host-runnable tier `tests/t011_enareporting.sh`. `bash -n` +
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
  `build-ol-aws-ami.sh`, `setup-vmimport-role.sh`, and the test tiers `tests/t009_logformat.sh`,
  `tests/t010_enaukedetect.sh`, `tests/t011_enareporting.sh`. The sourced libraries
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
  `tests/t007_idempotency.sh` already enumerates all 7 named markers.

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
  tier (`tests/t010_enaukedetect.sh`) guards the retarget. `bash -n` +
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
  regression tier **B-T9** (`tests/t008_hooktiming.sh`) now guards this class: it
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
  (`tests/t009_logformat.sh`) asserts every channel is date-first (and guards
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
  unchanged) so it can be unit tested; `tests/t003_unit.sh` now drives it
  table-driven (normalisation of `default`/`v1+v2`/`V2.0`/`v2only`, `OL6+default`
  allowed, `OL7+v2.0` allowed, invalid value -> `die`, **`OL6+v2.0` -> `die`**;
  10 asserts). Added `tests/t007_idempotency.sh` (B-T6, L2, structural): asserts
  each of the 7 `[ol-aws-ami-builder PATCH ...]` injection markers is fronted by
  a `grep -Fq` idempotency guard (runtime apply-twice remains B-T7/B-T8). Suite
  now **118 passed, 1 skipped, 0 failed**; the host-runnable tiers (L0-L2) are
  complete. New/changed scripts are shellcheck `-S style` clean.

- Added **B-T5 env-template parity** (`tests/t006_envparity.sh`, test increment 5,
  L2): data-driven checks over `env.properties.aws-ol{6,7,8,9,10}` - a 20-key
  common core in all five, the documented `KERNEL`/`UEK_RELEASE` extras present
  only in OL6/OL7, the cross-file invariants (`S3_BUCKET`, `AWS_REGION=""`,
  `UPDATE_TO_LATEST=yes`, `CLOUD=aws`), and the per-OS `DISTR=olN-slim` (31
  asserts). Also **wired B-T4 kickstart conformance into the single runner**
  (`tests/t005_kickstart.sh` wraps `tests/validate-kickstart.sh`; SKIPs without
  `ksvalidator`) - previously it was only runnable standalone. Suite now **98
  passed, 1 skipped, 0 failed** (B-T1 19 + B-T2 14 + B-T3 25 + command-mock 9 +
  env-parity 31, B-T4 kickstart skipped without ksvalidator). No change to
  `build-ol-aws-ami.sh`; new tiers are shellcheck `-S style` clean.

- Added a **command-mock + spy layer** for dependency-injection class "external
  commands" (`tests/lib/mock.sh`, `tests/t004_cmdmock.sh`, test increment 4, L1
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

- Added **B-T3 pure-function unit** tests (`tests/t003_unit.sh`, test increment 3,
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

- Added **B-T2 ShellCheck** as a deterministic static gate (`tests/t002_shellcheck.sh`,
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
  first tier **B-T1 parse** (`tests/t001_parse.sh`): `bash -n` on every `.sh` plus
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
