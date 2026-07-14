---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.1.0
  rendered: 2026-07-02
---
# TESTING

Operational tests for `bash-ol-aws-ami-builder`. These are maintainer-facing
checks, not part of the build pipeline itself.

> **Governance note.** This is a subproject-local maintenance document. Since
> B1 it carries the standard doc-provenance front-matter pin and **is part of
> the reconstructed doc-set** verified by `doc_gate --reconstructed` (derived
> from the manifest project registry per ADR 0031). A dedicated **bash**
> TESTING template is still not extracted into the governance canon (only a
> PowerShell one exists, `template.powershell.testing`), so the section
> structure below remains subproject-local content under the pin; if a bash
> TESTING template is later canonised, this file can be reconstructed to it.

## 0. Test model (top-down baseline)

This project is the repository's first bash consumer, so the bash testing
discipline is **built up incrementally and documented here as the de-facto bash
test reference** (the same standing as this SPEC's Part A). It is derived
top-down so that future tests slot into named cells rather than accreting
ad hoc. The harness is **self-contained** (no bats / shunit2 / ShellSpec): the
methodology of those frameworks is adopted, the implementation is our own, in
keeping with the repository's single-file / stdlib-only tooling policy and to
avoid an unmaintained third-party dependency.

The model has three structuring axes plus a coverage ledger.

### Axis 1 - test pyramid (scope / cost)

| Layer | What it checks | Execution | Tiers here |
|:--|:--|:--|:--|
| L0 Static | syntax / lint | no execution | B-T1 parse, B-T2 ShellCheck |
| L1 Unit (hermetic) | a function's output / exit code from injected inputs | executed, isolated | B-T3 pure-function |
| L2 Component / Contract | CLI contract, data-set invariants, artifact conformance | executed | B-T5 env parity, B-T6 idempotency, B-T4 kickstart |
| L3 Integration | interaction with real external tools / filesystem | executed, real deps | B-T7 offline image inspection |
| L4 E2E | real build + real Nitro boot | builder host + AWS | B-T8 |

### Axis 2 - dependency-injection matrix

A bash unit's "inputs" are broader than its arguments. Every dependency class
has a defined injection / simulation technique; a hermetic L1 unit MUST control
the classes it touches rather than depend on the host.

| Dependency class | Injection / simulation technique |
|:--|:--|
| arguments (`$1..$@`) | pass directly in the test |
| environment vars / env file | export in the test / `source` a fixture env file |
| shell global state, `set -euo pipefail` | subshell isolation + explicit setup |
| external commands (`aws`, `git`, `virsh`, `guestfish`, `dnf`, `osinfo-query`, ...) | mock via PATH-shadow + call-log spy (implemented in `tests/lib/mock.sh`; see `tests/t004_cmdmock.sh`) or function override |
| filesystem (`${WORKSPACE}`, generated files) | temp dirs / fixtures |
| OS / distro identity (`/etc/os-release`, `uname`) | inject a fake so the same test is deterministic on any host |
| network / cloud (AWS APIs, ISO / checksum URLs) | fake CLI / local fixtures, or push to L3 / L4 |
| stdin / tty | feed via heredoc / pipe |

### Axis 3 - data variation

Bash has no rich objects, so input coverage is **table-driven**: a table of
input rows (valid / invalid / boundary) x expected output. Structured data
(arrays, associative arrays, structured text) is asserted by normalising to a
canonical serialized form (e.g. sorted `key=value`) and diffing.

### Hermeticity rule

L1 unit results MUST NOT depend on the host's real distro or tools; host- and
cloud-dependent behaviour is mocked (Axis 2) or moved explicitly to L3 / L4.
This is what keeps the suite simultaneously **comprehensive and deterministic**
on the pinned Linux container substrate.

## Running the suite

```sh
bash tests/run-all.sh
```

The single runner executes every tier (`tests/tN_*.sh`) as an isolated
subprocess, aggregates pass / fail / skip, prints one summary, and exits
non-zero if any tier fails. It records the resolved tool versions at run time.
**Wire `tests/run-all.sh` into the project gate battery.**

Current fixed pass count (full toolchain present — ShellCheck (pin 0.10.0;
re-measured green on 0.11.0 at the 2026-07-14 restamp), `ksvalidator`,
`modinfo` (kmod), and `python3`): **512 passed, 0 skipped, 0 failed** across
**21 tiers** (B-T1 parse = 50, B-T2 ShellCheck = 45, B-T3 unit = 59,
command-mock = 9, B-T4 kickstart = 1, env-parity = 55, idempotency = 12,
hook-timing = 19, log-format = 12, ena-uek-detect = 16, ena-reporting = 31,
build-visibility = 17, ena-ledger-guard = 5, ena-check-2 = 6, ena-verify = 12,
ena-verify-results = 19, ena-bundle = 13, ssm-verdict = 32,
awscli-verdict = 43, register-validation = 23, ena-express = 33).
Optional-tool degradations are the only way to see a skip: without
`ksvalidator` B-T4 contributes a skip (-> 511/1); without `modinfo` the
ena-uek-detect inbox-report assertions fold into one skip (-> 509/1); without
ShellCheck B-T2 skips; the B-T (ena-bundle) initramfs fixture builds via cpio
**or** a self-contained `python3` newc fallback, so it no longer skips. The
B-T1 / B-T2 counts include the six `tests/cleancore/` clean-core builders (see
"Container clean-core test base" below) and the AWS CLI v2 install-test scripts
(`install-awscli.sh`, `tests/awscli/`): B-T1 and B-T2 parse- and lint-check
**every** `.sh` in the project, so adding a script raises both counts by one. The
host-runnable tiers (L0-L2) are complete; B-T7/B-T8 (L3/L4) were **executed for
real on the 2026-07-13 generation** (all five majors: real 7 GB builds, Phase 6
offline inspection, and real EC2 boots — see the "Boot-E2E evidence note
(2026-07-13)" below). They remain manual / on-demand (builder host + AWS), not
run by `run-all.sh`. A tier SKIPs cleanly when its optional dependency is absent.

## Environment & version dependencies

The harness is host-distro-agnostic but depends on a few tools; pin / record
them so a run is reproducible:

- **bash** >= 4 (arrays, `${var,,}`); developed and run on bash 5.x in the
  Claude Linux container substrate.
- **ShellCheck** (B-T2): obtained as the self-contained static binary from the
  upstream GitHub release (no runtime deps); **pinned to 0.10.0** - record the
  version (`run-all.sh` prints the resolved one). The canonical severity is
  **`style`** (the strictest), set on the command line by `tests/t002_shellcheck.sh`;
  `.shellcheckrc` carries `external-sources=true` + `source-path=SCRIPTDIR` only
  (no global `disable=`). Determinism comes from three documented inline
  exemptions, each a single code on a single statement with a rationale comment:
  `SC2016` at the SELinux-relabel sed injection and at the `bash -c '...$1...'`
  secure idiom in `build-ol-aws-ami.sh`, and `source=/dev/null` at the runtime
  `. /etc/os-release` in `install-ena-driver.sh`. Every other code stays active
  everywhere. B-T2 SKIPs if shellcheck is absent (the CI gate requires it).
- **pykickstart / `ksvalidator`** (B-T4): optional; B-T4 SKIPs if absent.
- **kmod / `modinfo`** (ena-uek-detect inbox-report assertions): optional;
  those assertions fold into a single SKIP if absent.
- **awk / sed / grep / find** (coreutils + gawk): present in the container.
- **python3** (stdlib only): used by the pure-logic tiers that drive matrix /
  verifier python (B-T ena-ledger-guard) and, in `tests/t017_enabundle.sh` +
  `preserve_bundle()`, as a self-contained newc-cpio writer/reader so the
  initramfs-listing fixture and its assertions run even on a host **without**
  `cpio` (the real builder hosts have `cpio`/`lsinitrd` and never reach it).
  Effectively universal, so the B-T (ena-bundle) initramfs assertions no longer
  SKIP for a missing `cpio`.
- **clean-core builders** (`tests/cleancore/`, see below): these standalone
  builders are NOT run by `run-all.sh`; B-T1/B-T2 only parse- and lint-check
  them. To actually *run* one needs `root` plus `curl`, `tar`, `xz`, `gzip`,
  `unshare`, `chroot`, `mknod`, `truncate`, `find` (and, optionally, a `podman`
  / `docker` runtime for the readiness probe). Each builder SKIP-degrades its own
  network-dependent readiness test when offline; its build pass/fail is governed
  by the unconditional self-test section.

Host-only tiers (B-T1, B-T2, B-T3, B-T5, B-T6, B-T9, log-format) run entirely in
the container.
**B-T7 / B-T8 are integration / E2E** and require a real KVM builder host and an
AWS account; they are documented, not run by `run-all.sh`.

> **Boot-E2E evidence note (2026-07-11).** The 2026-06-16 build generation
> (pre-self-build for OL8-10) was boot-verified on real EC2 (ap-northeast-1)
> across ALL five majors; sosreports were collected on every instance. What it
> proves: OL6-10 AMIs from this pipeline boot and run cleanly (0 failed units
> on OL7-10); the OL6 self-built ENA 2.9.1g actually drives the NIC
> (`ethtool -i` = 2.9.1g, on an ENA-capable Xen-generation instance — the
> OL6 Nitro/NVMe path remains untraveled); the OL7 DKMS-signed self-built
> 2.17.0g is the loaded `/extra` module. What it does NOT prove: the OL8-10
> self-build generation (`ethtool -i` showed the in-tree driver), the baked-in
> SSM Agent / AWS CLI v2 (both were absent from that generation; the SSM Agent
> found running was hand-installed minutes before the sosreports), and the
> 7 GB `DISK_SIZE_GB` (that generation was built at 10 GB). Those remain the
> open [C]3 / B-T8 items for the current tree.

> **Boot-E2E evidence note (2026-07-13) — closes the 2026-07-11 open items.**
> The 2026-07-13 build generation (self-built ENA on ALL five majors, baked-in
> SSM `/latest/`, `DISK_SIZE_GB=7`) completed **real builds + registrations**
> (AMI IDs: OL6 `ami-01724bfd463dede0e`, OL7 `ami-0661c712ffbab6e0b`, OL8
> `ami-0e06117c48124c634`, OL9 `ami-02408b9ed351ae526`, OL10
> `ami-05c3164c73ce94eca`; ap-northeast-1) and **real EC2 boots with SSH login
> on all five majors**; sosreports were collected on every instance
> (`r5dn.large` / `r6id.large` / `r7iz.large` / `r8i-flex.large` ×2 — Nitro
> generations through v6). What it proves, per the sosreports: (1) the
> **AMI-name = driving-driver invariant held on all five majors** — `ethtool
> -i` (dmesg ENA probe line on OL7, whose sos build predates the ethtool
> capture) shows the self-built `2.9.1g` (OL6) / `2.17.2g` (OL7-OL10),
> closing the OL8-10 self-build gap; (2) **the initramfs carries `ena` +
> `nvme` on all five majors** (D.28 real-machine confirmation), and the OL6
> Nitro/NVMe path is now traveled (NVMe root on r5dn.large); (3) the
> **baked-in SSM Agent `3.3.4793.0` is installed AND running on all five**
> (upstart on OL6, systemd active on OL7-10) — the first real-boot proof of
> the all-majors-`/latest/` policy; (4) UUID-based fstab / NVMe root, serial
> console (getty ttyS0 on OL7-10, GRUB cmdline on OL6), and **zero ena/nvme
> error lines in dmesg** (the only warning is the expected unsigned-DKMS
> module taint on OL6). Also observed: every booted image carries
> `linux-firmware` + `kernel-uek-modules` for the target kernel (see SPEC
> B.3.4 — the `LINUX_FIRMWARE=no` knob is build-time headroom, not final
> content). NOT observable from sosreports: the AWS CLI v2 install (sos does
> not collect `/usr/local`; verified at build time via the AMI
> identity/report). Remaining open: SSM Run Command round-trip and
> `--skip-*` build variants.

## Coverage ledger

Tracks which tiers exist so gaps are visible top-down (the bash analogue of the
PowerShell canon's `tested` + fixed pass count). New tests register a row.

| Tier | Layer | Status | Notes |
|:--|:--|:--|:--|
| B-T1 parse | L0 | implemented | `bash -n` every `.sh` in the project (incl. `tests/cleancore/`, `tests/ena/`, `tests/ssm/`, `tests/awscli/`) + 5 shell-bodied heredoc bodies; 47 asserts |
| B-T2 ShellCheck | L0 | implemented | canonical `-S style` over every `.sh` in the project (incl. `tests/cleancore/`, `tests/ena/`, `tests/ssm/`, `tests/awscli/`) via `.shellcheckrc`; 3 documented inline exemptions in the wrapper/helpers + per-script inline exemptions in the clean-core builders (SC2086 mknod word-split, SC2016 literal yum-variable text); SKIPs if shellcheck absent; 42 asserts |
| B-T3 pure-function unit | L1 | implemented | sources the wrapper (tail `main` is guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so sourcing has no side effects); table-driven `parse_ol_version_from_iso` + `parse_args` contract (incl. the opt-in `--enable-amazon-time-sync` flag) + `_ks_add_sos_package` behavioural unit (insert-once / idempotent second call / marker position / missing-`%packages` dies with the file untouched) + shape-guarded `_ena_pin_for_major`/`_ena_fallback_pin` extraction (fixture: concrete pin / empty default / non-`:-` form / garbage / empty fallback all safe; real-file shape regression: OL6/OL7 concrete `x.y.z`, OL8-10 exactly empty — the AMI-name leak class) + the Phase-3 exit-gate validators `_p3_validate_ks` / `_p3_validate_provision` (finding-count contract on fixtures: sound patched ks passes in BOTH real shapes — the OL7-era static-`part` shape and the EL8-family shape mirroring upstream `ol8-ks.cfg` (`%addon` section + `%pre`-generated `%include /tmp/partitions-ks.cfg` partitioning, the 2026-07-13 OL8-E2E false-FAIL regression pin) — and hook-injected provision.sh passes; missing `%packages`, duplicated `sos`, lost `%include`, `%include` target not generated in `%pre`, unbalanced sections with `%addon` counted, and unpaired hook brackets are caught); 59 asserts |
| B-T (command mock) | L1 | implemented | `tests/t004_cmdmock.sh` via `tests/lib/mock.sh` (PATH-shadow + call-log spy); `detect_qemu_user` (mocks `id`), `detect_os_variant` (mocks `osinfo-query`); 9 asserts |
| B-T (IMDS rejection) | L1 | implemented | `normalize_imds_support` extracted (behaviour-neutral) + table-driven unit in `tests/t003_unit.sh`: normalisation, invalid->die, OL6 v2.0->die; 10 asserts |
| B-T5 env parity | L2 | implemented | `tests/t006_envparity.sh`: 20 common-core keys, OL6/OL7-only KERNEL/UEK_RELEASE extras, S3_BUCKET/AWS_REGION/UPDATE_TO_LATEST/CLOUD invariants, per-OS DISTR; plus release-agnostic maintenance invariants (every template sets `ISO_URL` — a required key with no wrapper-side default; OL9/OL10 carry the `SINGLE-TOUCH MAINTENANCE POINT` marker and no release-pinned checksum comments; the wrapper has no `DEFAULT_ISO_URL` and `load_env` rejects an unset `ISO_URL`); plus the uniform `DISK_SIZE_GB="7"` and opt-in `AMAZON_TIME_SYNC="no"` values (21 common-core keys) and the sos-in-every-kickstart wiring (OL6 heredoc lists `sos`; phase3 wires `_ks_add_sos_package` for OL7-10); 54 asserts |
| B-T6 idempotency | L2 | implemented | `tests/t007_idempotency.sh` (structural): each of the 11 `[ol-aws-ami-builder PATCH ...]` markers (incl. the `sos-package` kickstart patch and the opt-in `amazon-time-sync` hook) is fronted by a `grep -Fq` guard; runtime apply-twice is B-T7/B-T8 |
| B-T4 kickstart | L2 | implemented | `tests/validate-kickstart.sh`, **wired into the runner** via `tests/t005_kickstart.sh` (SKIPs without `ksvalidator`); see below |
| B-T9 hook timing | L1/L2 | implemented | `tests/t008_hooktiming.sh`: hooks appended to `cloud/aws/provision.sh` run at source time, so anything stage-dependent must be staged explicitly. (1) The OL6 cloud-user hook must run *after* `cloud::cloud_init` (configs exist), never at source time; static wrapper-wiring + no-top-level-`sh` guards, plus a behavioural order/edit check. (2) The nitro-initramfs hook must be presence-aware (SPEC D.28): only drivers whose `.ko` exists enter the dracut drop-in at its stage, `ena` is deferred to the ENA hook (whose emitted, idempotent drop-in append must precede the installer invoke); static pins + behavioural runs of the extracted body against mock `/lib/modules` trees with/without `ena`; 19 asserts |
| B-T (log format) | L1 | implemented | `tests/t009_logformat.sh`: every timestamped channel emits **date-first** (`YYYY-MM-DD HH:MM:SS` leads, `[SEVERITY]`/source tag follows; SPEC E.1); colour-stripped match across info/warn/error/build/debug/external + a negative guard against the old tag-first order; 12 asserts |
| B-T (ena uek-detect) | L1/L2 | implemented | `tests/t010_enaukedetect.sh`: the OL6 ENA self-build retargets the amzn-drivers Makefile UEK detection (`IS_UEK`/`ENA_KERNEL_SUBVERSION_*`) from `uname -r` to `BUILD_KERNEL` (the DKMS target), so the `kcompat.h` `page_ref_count` guard evaluates against the build target rather than the libguestfs appliance kernel; structural (present, OL6-gated, idempotency-guarded, pipe-anchored) + behavioural fixture transform + `report_inbox_ena` errexit/pipefail-survival regression (the shipped function text is extracted and run under `set -euo pipefail` against an absent in-box module - the real-guest condition that silently killed the first OL8 AMI build; skips when kmod/modinfo is absent, which is also exactly why the container matrix never caught it); 12 asserts. Compile/boot proof is B-T7/B-T8 |
| B-T (ena reporting) | L1/L2 | implemented | `tests/t011_enareporting.sh`: the Phase 6 readiness report prints aligned, fixed-width `ENA Driver (Kernel in-box)` / `ENA Driver (Self-Build)` lines with an explicit in-tree no-version fallback; `install-ena-driver.sh` logs the in-box ENA identity before the self-build; the auto AMI name/description gain a self-built-ENA marker and the final summary prints the description + an ENA driver line; the `[OLAWS-ENA01]` hook log and the marker read the pin from `install-ena-driver.sh`'s `ENA_VERSION_OL<major>` default (no hardcoded `OL6 2.5.0` drift). Structural presence checks grep files directly (avoiding a `printf\|grep -q` SIGPIPE race under `pipefail` on the large wrapper) + behavioural pin-reader fixture; plus OL6-10 production-wiring asserts ([OLAWS-ENA02] resolver + hook gates), matrix-fidelity track pins (installer `bt_uek_repo` defaults AND the update-gate `uekr_for()` map, per-major, OL8=UEKR7 — the pair that silently diverged from real AMIs) and the `ENA_DRIVER_VERSION` user-pin wiring (x.y.z validation die, [OLAWS-ENA02] log, hook pass on every major); 31 asserts (count corrected: the previous "15" predated the production-wiring additions). AMI naming/boot proof is B-T7/B-T8 |
| B-T (build visibility) | L1/L2 | implemented | `tests/t012_buildvisibility.sh`: OL7 build-log visibility (handoff B.1.5 feedback 4). `install-ena-driver.sh` emits greppable `[ena-driver][stage]` breadcrumbs at the phase boundaries (esp. dkms add/build/install) and `record_make_log()` preserves the DKMS make.log to `/var/log/ol-aws-ami-builder-ena-make.log` on a successful build (guest output is swallowed by virt-customize on success); the wrapper records the latest LIVE orchestrator line to `BUILD_STAGE_FILE` in `log_external` and the Phase-5 heartbeat shows it as `stage: …` (assembled into one atomic `log_progress` write); `HEARTBEAT_INTERVAL_SEC` default is 10s. Structural greps (file-direct) + a behavioural `log_external`→stage-file fixture; 17 asserts. Real OL7 build/boot proof is B-T7/B-T8 |
| B-T (ena ledger guard) | L1 | implemented | `tests/t013_enaledgerguard.sh`: the matrix ledger-writer keeps an INDEPENDENT version-mismatch guard — an `ok` whose installed `ko_version` does not match the requested `ena_version` (e.g. a stale installer that fell back to the stock in-tree `ena.ko` 1.1.2) is downgraded to `fail` before it can enter the ledger, so it cannot poison the report or the kver-primary dedup gate. Extracts the real ledger-writer python out of the matrix and drives it with a synthetic results TSV; python3 only, no container/dkms/build; 5 asserts |
| B-T (ena check-2 provenance) | L0/L1 | implemented | `tests/t014_enacheck2.sh`: Phase-6 CHECK 2 (offline image inspection) must gate its PASS on provenance, not mere module presence — the pure `_ena_check2_ok` requires the self-built `/updates`\|`/extra` module when a self-build was requested (OL6/OL7 default); the stock `/kernel` copy alone is a FAIL, while no-self-build paths (`--skip-ena-driver`, OL8+ in-distro, OL9+) accept any present module. Loads ONLY that function out of the (guarded) wrapper; 6 asserts |
| B-T (ena verify verdict) | L0/L1 | implemented | `tests/t015_enaverify.sh`: guards the false-ok regression where EL6 `dkms` (2.4.0) returns exit 0 even on a failed in-guest compile while a stock in-tree `ena.ko` is present — success is decided from the installed MODULE VERSION via the pure `ena_buildtest_verdict`. Loads ONLY that function; no container/dkms/build; 12 asserts |
| B-T (ena verify-results) | L1 | implemented | `tests/t016_enaverifyresults.sh`: the standalone READ-ONLY `tests/ena/verify-ena-buildresults.sh` judges, after the fact, whether each ok build's module is load-ready WITHOUT touching the production path; this tier loads ONLY its two pure verdict functions — `lc_vermagic_verdict` (L4a gate) and `lc_symbols_verdict` (L4b gate) — and asserts them across the verifier's shapes (no I/O/kmod/bundle), plus a black-box ledger-reader regression pin: a fixture `entries`-keyed ledger (one ok + one fail row) against an empty bundle must extract exactly the ok row (`"ok_rows":1` — the schema key the harness writes; the verifier once read a nonexistent `results` key and silently judged 0 rows with rc 0), FAIL it loudly for the missing module, and exit non-zero (python3 only; the missing-module fail fires before any kmod use); 19 asserts |
| B-T (ena bundle producer) | L1 | implemented | `tests/t017_enabundle.sh`: the matrix's `preserve_bundle()` is a DUMB copy that lifts each build's artifacts into the exact layout the read-only verifier consumes (per-version `ena.ko`, shared per-kver `Module.symvers` / `kernel.vermagic` / `initramfs.list`); loads ONLY that function and drives it against a fabricated image tree. The initramfs fixture builds via cpio **or** a self-contained `python3` newc writer/reader, so the listing assertions RUN on any host with cpio+gzip or python3 (rather than skipping); 13 asserts |
| B-T (ssm verdict) | L0/L1 | implemented | `tests/t018_ssmverdict.sh`: loads the four pure helpers of `tests/ssm/run-ssm-installtest-matrix.sh` — `ssm_ge` (dotted 4-part compare), `go_min_kernel` (go.mod `go` directive → min-kernel proxy), `ssm_in_scope` (default `>=min` vs `--full` filter), `ssm_compliance` (headline verdict vs AWS min `>= 3.3.3598.0`) — and asserts them across the matrix's shapes; no container/network/clean-core; 32 asserts |
| B-T (awscli verdict) | L0/L1 | implemented | `tests/t019_awscliverdict.sh`: loads the five pure helpers of `tests/awscli/run-awscli-installtest-matrix.sh` — `awscli_ge` (dotted compare, versions + glibc), `awscli_min_glibc` (documented manylinux floor 2.17/2.5), `awscli_in_scope` (v2-major filter), `awscli_verdict` (`runs`/`glibc-too-old`/`unexpected-fail`), `python_eol` (bundled CPython minor → documented EOL date) — and verifies the reuse-by-copy consistency of `awscli_min_glibc` with `tests/awscli/list-awscli-releases.sh`; no container/network/clean-core; 43 asserts |
| B-T (register validation) | L1 | implemented | `tests/t020_register.sh`: sources the wrapper (guarded `main`) and exercises the two pure validators that guard `aws ec2 register-image` — `validate_ami_name` (`--name`: length 3-128 + allowed set alphanumerics and `()[]` space `. / - ' @ _`) and `validate_ami_description` (`--description`: length 0-255) — across length boundaries (2/3/128/129/0), realistic auto names (ENA/SSM markers), the full allowed special set, and a battery of disallowed characters (`# * , : + = % !`, braces, tab, multibyte); argument-only, no network; 23 asserts. The Phase-9 `--dry-run` pre-flight that also gates the real call is a live AWS interaction, proved by B-T8 (E2E) |
| B-T (ena express) | L0/L1 | implemented | `tests/t021_enaexpress.sh`: the ENA Express readiness classification `ena_express_verdict` (`< 2.2.9` not-ready, `>= 2.2.9` bandwidth-only, `>= 2.8.0` express-ready; AWS ena-express.html floors) is a reuse-by-copy family of three — `install-ena-driver.sh` (the source of truth), `tests/ena/list-ena-releases.sh`, and the matrix's ledger-merge Python duplicate — kept in behavioural agreement across a boundary-version set (both floor edges, mid-range members, the stock 1.1.2, a far-future major proving numeric compare); also asserts the release-list 1.2 schema invariants (`min_version` + per-entry `ge_min`/`express_verdict`, mutually consistent) and the matrix's default-scope plumbing (`--full`, `min_version` floor, `--report-only`); python3-only, no container/network/build; 33 asserts |
| B-T7 offline image inspection | L3 | deferred | builder host |
| B-T8 E2E build + boot | L4 | deferred | builder host + AWS |
| clean-core builders | (test base) | implemented | `tests/cleancore/build-cleancore-ol{5,6,7,8,9,10}.sh` — general-purpose container test-base builders (see "Container clean-core test base" below), plus `tests/cleancore/build-cleancore.sh` (the `--all`/`--ol` orchestrator wrapping them). **Not** run by `run-all.sh` (heavy: needs root + network + a multi-hundred-MB build); covered by B-T1 (parse) + B-T2 (lint) like every `.sh`; each builder self-tests a fresh unpack of its own `.tar.gz` |
| awscli install-test | (test base) | implemented | `install-awscli.sh` + `tests/awscli/run-awscli-installtest-matrix.sh` + `tests/awscli/list-awscli-releases.sh` — the AWS CLI v2 install+run matrix (glibc axis) and its release-list resolver (see "AWS CLI v2 install+run test matrix" below). **Not** run by `run-all.sh` (heavy: needs root + network + clean-core); the pure verdict/lifecycle helpers are unit-tested host-only by `tests/t019_awscliverdict.sh`; all are covered by B-T1 (parse) + B-T2 (lint) |

## Container clean-core test base (`tests/cleancore/`)

The `tests/cleancore/` directory holds six self-contained builders —
`build-cleancore-ol5.sh` / `-ol6.sh` / `-ol7.sh` / `-ol8.sh` / `-ol9.sh` / `-ol10.sh`
(naming convention: `build-cleancore-ol<MAJOR>.sh`) — that produce a **clean-core
Oracle Linux container rootfs** per OL major as a reusable test base for the
project's container-level checks (repo-availability, guest provisioning shell
logic, ENA driver compile-tests, upstream-drift structural checks). They are
developer/CI-side tooling: **not part of the AMI build pipeline** and **not run
by `run-all.sh`**. The canonical reference for this test base lives in `SPEC.md`
**B.8**; this section is the operational note.

Each builder uses three tagged execution environments:

- **[A] HOST** — the machine running the script (the Claude sandbox / CI =
  Ubuntu 24.04 / end-user = RHEL 10|9, Fedora 44). It only orchestrates:
  download, extract, edit, pack, self-test.
- **[B] BUILDER** — a **throwaway** Oracle-distributed image, driven via
  `unshare`+`chroot`, used build-use only (its contents are never shipped). It
  is **EL-native** so the in-guest rpm can read the rpmdb it writes — mandatory
  for OL6, whose rpm stays 4.8 / BerkeleyDB-4 forever (an EL7 rpm 4.11 / db5
  builder yields a db an EL6 rpm reads as 0 packages). OL6 additionally needs a
  TLS-stack modernization before it can reach modern `yum.oracle.com`. **OL6-OL10
  acquire this image by its floating `N-slim` tag** from the Oracle container
  registry (`container-registry.oracle.com`, OCI v2 / `curl`, or a container
  runtime as a fast path) so the builder tracks the latest N.x slim, and **fall
  back** to the byte-stable pinned `N-slim` git-raw rootfs (OL6 then to the OL6.6
  image) if the registry is unreachable — the same `oci_pull_rootfs` model the OL5
  builder uses for `oraclelinux:10`.
- **[C] CLEAN-CORE** — the deliverable rootfs from the `yum`/`dnf
  --installroot` transaction, finalized (device nodes, OCI yum-variable rewrite,
  build-time repo dropped, logs zero-filled, machine-id / ssh host keys cleared)
  and packed as a `.tar.gz`.

Per-OL specifics: OL6/OL7 build with `yum`; OL8/OL9/OL10 install the full `dnf`
into the slim builder (`microdnf install dnf`) first. OL7's manifest no longer
mirrors the upstream `distr/ol7-slim` kickstart, and OL6 builds from the `6-slim`
container rootfs (OL6.10; fallback the OL6.6 public-yum image) as a fresh curated
`yum --installroot` install rather than from a VM kickstart. **OL5 through OL10 have all been trimmed** to a
slim-aligned, container-
appropriate set: `@core` dropped (no kernel/boot/firewall/cron/syslog), explicit
test-base essentials, `git-core` instead of `git` (avoiding ~60 `perl-*`), no
`net-tools`, and the Oracle EPEL repo wired in but **shipped disabled** (enabled
on demand by the ENA/SSM harnesses for e.g. `dkms`). `systemd` stays present (a
hard dependency of full `dnf`, plus `pam`/`sudo` on EL8/EL10; pulled by
`iputils`/`procps-ng` on EL7) but is never PID 1 in
container/chroot use. On EL8 the builder additionally pins `glibc-minimal-langpack`
and excludes `glibc-all-langpacks` (~416 MB), which a raw EL8 `dnf` would otherwise
pull but the official `ol8-slim` does not ship. On EL7 (no `git-core` split) OL7
carries plain `git` (~30 `perl-*`); `git-lfs`/`zstd` are EPEL-only/absent in the
EL7 base so they are omitted, and the base `oraclelinux-release` is listed
explicitly (EL7's `oraclelinux-release-el7` does not pull it). On EL6 (like EL7,
no `git-core` split) OL6 carries plain `git`, plus `procps`/`nc` (not
`procps-ng`/`nmap-ncat`), and — uniquely — **includes `net-tools`** (EL6 has no
standalone `hostname` package; the command ships in `net-tools`). EPEL 6 is EOL
and unhosted by Oracle, so the OL6 build (C) **conditionally** enables the NSS
dynamic CA trust — a workaround for the Claude build sandbox's intercepting (MITM)
egress proxy, run **only in the sandbox** (auto-detected via `IS_SANDBOX` / the
egress-gateway CA; override `CLEANCORE_CATRUST=on|off`) and **skipped on a real
host** where the shipped `ca-certificates` bundle already verifies standard CAs
(the self-test row asserts in the sandbox, SKIPs off it) — then (B) fetches the
EPEL 6 release RPM from the Fedora archive with the clean-core's own `curl` and
installs it with its own `rpm` (EL6 `yum` cannot fetch a direct https package
URL), shipping the repo
repointed to the archive and `enabled=0`. **OL5** is the deepest EOL member and
is built by a distinct model: its rpm stays 4.4 / BerkeleyDB-4.3 forever and its
in-OS `openssl` 0.9.8e tops out at TLS 1.0, so it can neither write a modern rpmdb
nor reach the TLS-1.2-only `yum.oracle.com`, and no distributed OL5 image carries a
usable EL5 rpm over the normal channel. So OL5 uses the **latest distributed
`oraclelinux:10` image (floating `:10`) as a throwaway work environment** — pulled
anonymously over the OCI registry v2 API with `curl` only (no container runtime, no
host package installs) — which does all the TLS-1.2 work: fetch the OL5 metadata +
RPMs, resolve the closure (**dnf first**, with an embedded checksum-agnostic Python
resolver as the fallback that EL5's directory-`provide` semantics, e.g.
`libxml2-python` needing `/usr/lib64/python2.4`, force in practice), and bootstrap
an **EL5-native builder** (`rpm2cpio | cpio`) from the OL5 RPMs. The host then runs
a single-level EL5 `chroot` in which the **EL5-native `createrepo` 0.4.11** emits
the sha1/gzip repodata that EL5 `yum` 3.2.22 can read (OL10's `createrepo_c` only
emits sha256, which EL5 yum cannot checksum), and `yum --installroot` installs the
clean-core from the `file://` mirror — no in-OS TLS, rpmdb db4.3. EL5 `yum` has no
`--releasever` / `--setopt`, so `tsflags=nodocs` is carried in the builder's
`yum.conf`, and install success is verified by the rpmdb package count (EL5 yum
exits non-zero on a successful `Complete!` under chroot). The sandbox egress CA is
seeded into the OL10 work env's trust store (a no-op on a real host). EL5 deltas:
`git` and `jq` are **omitted** (no EL5 build exists for either — `jq` not even in
the EPEL 5 archive; `git` is EPEL-only and drags a `perl` chain), versionlock is
`yum-versionlock`, the release package is `oraclelinux-release`, and `procps`/`nc`
(not `procps-ng`/`nmap-ncat`) plus `net-tools` (for `hostname`) mirror OL6.
**`jq`** is a curated test-base essential on every clean-core: on OL7–OL10 it is
part of the enabled standard OL
repo (a plain `INCLUDE` member), and on OL6 — where `jq` is an EPEL package and
absent from the base — it is installed from that EPEL archive by enabling EPEL
**transiently for the one install**, leaving the shipped EPEL `enabled=0` (OL5 is
the exception: no EL5 `jq` build exists anywhere, so it is omitted there). The
unconditional self-test asserts `jq --version` runs in the finalized image (on OL5
it instead asserts `jq`'s intentional absence).
The **versionlock plugin** (`yum-versionlock` on OL5, `yum-plugin-versionlock` on
OL6/OL7, `python3-dnf-plugin-versionlock` on OL8–OL10) is likewise a default
`INCLUDE`
member on every clean-core — present in each OS's standard repo (OL6/OL7
`latest`, OL8–OL10 `baseos`), so it is a plain add with no extra repo — giving the
base package-pinning out of the box (parallel to `install-awscli.sh`'s versionlock
v1 block). Its only dependency is already in the base set, so it is a clean `+1`
to each SBOM.
Two static snapshots accompany the base: `cleancore-ol<MAJOR>.sbom.json` (each
finalized image's package set, names-only, reusable JSON) and
`REFERENCE-oracle-official-images.md` (each official container image's sources -
the container-registry.oracle.com floating tag and the pinned `oracle/container-images`
rootfs - and their name-version RPM manifests). Neither is a `.sh`, so both are outside
B-T1/B-T2 and are not drift-checked gates.

Run one with `bash tests/cleancore/build-cleancore-ol<MAJOR>.sh [output.tar.gz]`
(see "Environment & version dependencies" for the required tools; `INSECURE_TLS=0`
drops the build-time `sslverify=0` on a trusted host). The script exits 0 only if
the build and the unconditional self-test section pass; the network-dependent
readiness probe SKIPs (never fails the build) when offline.

### OL5 background & base facts

> Relocated from `REFERENCE-oracle-official-images.md` (which is now a pure
> container-image report). This is the OL5 investigation record that explains
> *why* the OL5 clean-core uses the OL10 work-env model rather than an EL5 image.

OL5 base facts (from `OracleLinux/OL5/latest/x86_64`), contrasted with OL6.10:

| Component | OL5 | OL6.10 (contrast) | Note |
|-----------|-----|--------------------|------|
| `rpm` / BerkeleyDB | **4.4.2.3 / db4 4.3.29** | 4.8 / db4 4.7.25 | rpmdb format |
| `glibc` | **2.5** | 2.12 | runtime floor |
| `openssl` | **0.9.8e** (TLS 1.0 ceiling) | 1.0.1e (TLS 1.2) | the TLS problem |
| `nss` / `curl` | 3.21.3 / 7.15.5 (openssl-linked) | 3.36 / 7.19 (NSS-linked) | in-OS HTTPS client |
| `yum` / `python` | 3.2.22 / 2.4.3 | 3.2.29 / 2.6.6 | package manager |
| kernel / UEK | 2.6.18 / **UEK R2** 2.6.32 | 2.6.32 / UEK R4 | - |
| `ca-certificates` | **no separate package** (ships with openssl) | present | trust store |
| `jq` | **absent** (EPEL 5 EOL/archived) | EPEL-transient | test-base essential |

**Why the OL5 repos are still usable even though OL5's own TLS can't reach them.**
`yum.oracle.com` requires **TLS 1.2** (an `http` request is redirected to `https`,
so there is no plain-HTTP path), and OL5's in-OS client (`curl 7.15.5` +
`openssl 0.9.8e`) tops out at **TLS 1.0** - so a legacy OL5 box cannot fetch
directly. That is expected: the OL5 channels exist as the authoritative *source*
that **modern tooling mirrors from**. The standard way to service EOL systems is to
`reposync`/mirror on a modern host and serve the legacy boxes from that mirror
(LAN, `file://`, or NFS) - exactly the pattern `build-cleancore-ol5.sh` uses (the
modern host/build container does the TLS-1.2 fetch; the EL5-native rpm only ever
touches `file://` local paths).

**Feasibility (proven in-sandbox).** The two OL5 blockers - no in-OS TLS 1.2, and
needing an EL5-native rpm so the rpmdb is db4.3-native - are both solved without any
EL5 container image: (1) the host fetches the OL5 package closure over TLS 1.2 from
`OracleLinux/OL5/latest`; (2) the EL5 `rpm` 4.4 binary + libs are extracted from
those RPMs with `bsdtar` (no rpm needed on the host); (3) EL5 `rpm` 4.4 runs inside
an `unshare -m` + `chroot` of a minimal EL5 rootfs (`rpm --version` -> 4.4.2.3);
(4) `rpm --initdb` creates a native **db4.3** rpmdb; (5) `rpm -Uvh` installs the
staged local RPMs and `rpm -qa` reads them all back - so the rpmdb-compat question is
moot (no cross-rpm db is ever written). The shipped builder generalizes this from
"just the TLS stack" to "the whole curated package set", installed from a `file://`
local mirror. See SPEC.md B.8 ("EL5 specific") for the operational model.

### Orchestrator (`build-cleancore.sh`)

`tests/cleancore/build-cleancore.sh` is a self-contained wrapper (inline helpers,
no shared library — repo policy for user-run scripts) that drives the per-OL
builders in one call. It **invokes them as separate executables** (never sources
them), so each `build-cleancore-ol<MAJOR>.sh` stays the single source of truth
for its own OL; the wrapper only adds a "build every supported OL" mode, a
host-OS sanity check, and a hard prerequisite gate:

```sh
bash tests/cleancore/build-cleancore.sh --ol 6                  # one OL major
bash tests/cleancore/build-cleancore.sh --all --out-dir ./cc    # OL 5,6,7,8,9,10
bash tests/cleancore/build-cleancore.sh --all --continue        # don't stop on a failing OL
```

Each OL `N` writes `<out-dir>/cleancore-ol<N>.tar.gz` (default out-dir
`./cleancore-out`); `--ol <N>` builds one, `--all` builds every OL that has a
builder, ascending, stopping at the first failure unless `--continue`. It
**recognises** the SPEC B.6 build-host matrix (RHEL-family 10|9, Fedora 44|43,
Ubuntu 26.04|24.04, Debian 13|12 — the AMI pipeline's supported execution
environments, and the `ubuntu-latest` CI target) and only **warns** on a host
outside it (a clean-core build is userland-only, so far more host-agnostic than
the AMI pipeline); it **hard-fails** only on a genuinely missing prerequisite —
not root, or a missing `unshare`/`chroot`/`mknod`/`curl`/`tar`/`xz`/`gzip`/
`truncate`/`find`. Like the builders it is **manual / on-demand** (root +
network + a multi-hundred-MB build) and **not** a `run-all.sh` tier; B-T1/B-T2
parse- and lint-check it like any `.sh`.

## ENA driver release list (`tests/ena/`)

`tests/ena/list-ena-releases.sh` collects the Amazon ENA Linux driver release
list from the `amzn-drivers` GitHub repository and writes the static snapshot
`tests/ena/ena-driver-releases.json` (schema 1.2). This snapshot is the **input** to the ENA
self-build test matrix: the matrix's default sweep iterates the `versions[]`
entries whose `ge_min` is true (the ENA Express scope; `--full` sweeps all),
and each entry carries the deterministic source `tarball_url`
(`…/archive/refs/tags/ena_linux_<ver>.tar.gz`) that `install-ena-driver.sh`
fetches. The snapshot's top-level `min_version` (default `2.8.0`, the ENA
Express express-ready floor; `ENA_MIN_VERSION` overrides at generation time)
is what the matrix reads as its default floor, and each entry also carries
`express_verdict` (the `ena_express_verdict()` classification — a
reuse-by-copy of the installer's source-of-truth helper, agreement-tested by
B-T21). Each entry ALSO carries an explicit availability pre-check of that
tarball URL — `tarball_available` (bool) + `tarball_http_status` — so the matrix
can gate on whether a given version is actually fetchable before it tries to
build it. The probe is a self-contained `url_check_status()` function **inlined**
in the script (repo policy: user-run scripts are self-contained — no shared
library / no config externalization; reuse is **by copy**), written so the same
existence/fetchability check can be copied as-is into other download-gated tests
(e.g. the AWS SSM Agent RPM on `s3.amazonaws.com`). It probes with HEAD,
following the `github.com`→`codeload` 302 to a real `200`/`404`, and honors
`INSECURE_TLS=1` (curl `-k`) + `URL_CHECK_TIMEOUT`; top-level `available_count` /
`unavailable_count` summarise the probe. `SKIP_TARBALL_CHECK=1` runs list-only
(availability fields → `null` / `"unchecked"`).

The authoritative version source is the set of git tags
`ena_linux_<MAJOR>.<MINOR>.<PATCH>`, read with **`git ls-remote --tags`** (the
git protocol), NOT the GitHub REST API. `ls-remote` needs no auth and is not
subject to the REST API's 60-request/hour unauthenticated rate limit, which is
shared-IP-exhausted on CI runners and the sandbox (the REST `/tags` endpoint
returns `403 rate limit exceeded` there). The JSON embeds **no timestamp**, so
re-running changes it only when the upstream tag set changes — `git diff` after
a refresh shows exactly the newly released ENA versions (the "test the diff"
signal). Run it manually / on demand (it is network-dependent and **not** a
`run-all.sh` tier; B-T1/B-T2 parse- and lint-check the script like any other):

```sh
bash tests/ena/list-ena-releases.sh                      # -> tests/ena/ena-driver-releases.json
SKIP_TARBALL_CHECK=1 bash tests/ena/list-ena-releases.sh # fast, list only (no probes)
bash tests/ena/list-ena-releases.sh out.json             # explicit output path
```

## ENA driver container compile-test (`ENA_BUILDTEST`)

Proves the pinned ENA driver actually **compiles + installs** for a given OL
major / UEK kernel without a full AMI build or a live Nitro instance, by running
`install-ena-driver.sh` with `ENA_BUILDTEST=1` inside a disposable clean-core
container (above). SPEC A.13 "Container compile-test (`ENA_BUILDTEST`)" defines
the switch and the result contract; this is the operator recipe.

Because a container is kernel-less, the test mode installs a full `kernel-uek` +
headers up front (per-OS repo wiring), after which the production build path runs
unchanged. Like the clean-core base, it is **manual / on-demand** — it needs
root, network, and a few-minute compile — and is **not** part of
`tests/run-all.sh`.

### Run

```sh
# 1. build (or reuse) a clean-core rootfs for the target OL major
bash tests/cleancore/build-cleancore-ol7.sh /tmp/cc-ol7.tar.gz

# 2. unpack into a throwaway dir and run the script under unshare + chroot
img=$(mktemp -d); tar -C "$img" -xzf /tmp/cc-ol7.tar.gz
cp /etc/resolv.conf "$img/etc/resolv.conf"; cp install-ena-driver.sh "$img/"
unshare --fork --pid --mount --uts --ipc -- bash -c "
  mount --bind /dev   '$img/dev';  mount -t proc  proc '$img/proc'
  mount -t sysfs sys   '$img/sys'
  chroot '$img' env ENA_BUILDTEST=1 INSECURE_TLS=1 bash /install-ena-driver.sh"
# (unshare --mount keeps the binds private; the throwaway dir is rm -rf'd after)
```

`INSECURE_TLS=1` is only needed behind a MITM proxy or where EL6 NSS cannot
verify the GitHub chain (curl error 77); omit it on a trusted host. Mounting
`/sys` (and `/run`) quiets the cosmetic `depmod`/`dracut` warnings.

### Result

The run prints one JSON line tagged `[ena-driver][buildtest][result]`; the exit
code agrees with `status` (`0` = ok, non-zero = fail):

```
[ena-driver][buildtest][result] {"status":"ok","osmajor":"7","ena_version":"2.17.0","kver":"5.4.17-2136.338.4.2.el7uek.x86_64","dkms":1,"ko":".../extra/ena.ko.xz","ko_version":"2.17.0g"}
```

Validated: OL6 (`ena.ko` 2.9.1g, UEK4 `4.1.12-124.48.6.el6uek`), OL7
(`ena.ko.xz` 2.17.0g, UEK6 `5.4.17-2136.338.4.2.el7uek`), and OL8 (`ena.ko.xz`
2.17.0g, UEK6 `5.4.17-2136.356.4.2.el8uek`). The AMI pipeline now self-builds
ENA on **OL6-OL10 by default** (ENA Express generation; see SPEC "ENA driver
self-build"): OL8/9/10 receive the host-resolved amzn-drivers latest via
`ENA_DRIVER_VERSION` (`[OLAWS-ENA02]`), and real AMI boot with an OL8/9/10
self-built driver remains to be E2E-verified. OL9 (UEKR8,
`gcc-toolset-14` compiler requirement) and OL10 (UEKR8) were additionally
validated 2026-07-03 building amzn-drivers latest (`2.17.0`) — see SPEC B.9
"OL9/OL10 evaluation findings" for the full writeup, including why the ENA
Express metrics floor (`2.8.0`) is confirmed to fail on both.

## ENA self-build test matrix (`tests/ena/run-ena-buildtest-matrix.sh`)

`run-ena-buildtest-matrix.sh` runs `ENA_BUILDTEST` across an **OS × ENA-version ×
kernel** matrix and records the outcomes in a machine-readable **ledger** that is
both the evidence store and the dedup state (SPEC B.9). It is self-contained
(inline helpers, no shared library) and drives the existing pieces as separate
executables — `tests/cleancore/build-cleancore.sh` for the per-OL rootfs and
`install-ena-driver.sh ENA_BUILDTEST=1` for each version. Targets **OL6/7/8**
(production-track self-build) **plus OL9/OL10** (evaluation-track; wired for
`ENA_BUILDTEST` but not yet wired into `build-ol-aws-ami.sh`'s AMI pipeline);
like the builders it is **manual / on-demand** (root + network + multi-hundred-MB
builds) and **not** a `run-all.sh` tier. A new `--ena-min-version <x.y.z>` floor
filters the version set (from `--ena-versions`, `--pinned-only`, or the release
list) to only releases at/above it, regardless of source — e.g.
`--ena-min-version 2.8.0` for AWS's documented ENA Express metrics-reporting
threshold.

Two evidence layers, both committed so the state persists across runs:

- `tests/ena/buildtest-ledger.json` — one entry per `(osmajor, ena_version,
  kver)` with `status` (`ok`/`fail`), `dkms`, `ko`, `ko_version`, `reason`,
  `tested_at`. This is the **dedup key**: kver is the primary discriminator, so a
  combo already present (pass **or** fail) is skipped, a **new kernel** re-tests
  everything (no key matches the new kver), and a **new ENA release** tests only
  the diff. The live kver per OL is read from the build result — the first build
  of a run establishes it, so the pinned version is tried first as that per-run
  canary.
- `tests/ena/RESULTS-ol<N>.md` — a per-OS human report regenerated from the
  ledger, **newest kernel first**, opening with a `## Latest kernel <kver>`
  summary of the ENA versions that build on the newest kernel tested (kept
  visible as kernels accumulate); each kernel a section with an `ok`/total
  count and a per-version table. A `fail` row is recorded evidence (e.g. an ENA
  release too old for that kernel), not a harness error, so the run still exits
  0. A build that emits no `[result]` line at all (its `install-ena-driver.sh`
  died before the result, or `unshare`/`chroot` failed) is recorded as a
  synthetic `fail` and the run continues to the next version/OL — one build never
  aborts the matrix. Any non-`ok` build's full log is preserved to
  `<cleancore-dir>/buildtest-ol<N>-ena_<ver>.log` for diagnosis.
- `tests/ena/verify-ena-buildresults.sh` — a standalone, **read-only**
  load-readiness verifier (the layer above `ENA_BUILDTEST`: "would the built
  module actually load on its target kernel?"). It runs as a SEPARATE pass
  (build → verify → build), never touching the build path: it reads the ledger
  plus a small bundle the build preserved and judges each `ok` row (L4a vermagic
  + L4b symbol-CRC are gates; L3 initramfs-inclusion is informational; L5 real
  load is the B-T8 ceiling). A missing bundle artifact for an `ok` row is a fail,
  not a silent skip. The pure verdict logic is unit-tested by
  `tests/t016_enaverifyresults.sh`.
- **The matrix emits that bundle** (the producer for the verifier above). After
  each build, `run-ena-buildtest-matrix.sh` does a dumb `cp` — no load-readiness
  judgement, no branch on ok/fail — of the DKMS `ena.ko` to
  `<bundle>/modules/ol<N>-ena_<ver>-<kver>.ko` and the shared per-kver
  `Module.symvers` + `kernel.vermagic` (a **stock** module's vermagic) +
  `initramfs.list` to `<bundle>/kver/<kver>/`. The bundle dir defaults to
  `<cleancore-dir>/verify-bundle` (`--bundle-dir` overrides) and accumulates like
  the ledger. The `cp` layout is contract-tested against the verifier's
  read-paths by `tests/t017_enabundle.sh` — a host-only unit test with a fabricated
  image tree, so it needs no real build, kernel, or kmod.

By default each OL is first **update-gated** (turn off with `--force`): before any
build, the matrix probes the latest `kernel-uek` for the OL (`yum.oracle.com`
`repomd.xml` → `primary.xml.gz`, python3 stdlib parse, fixed `OL → UEKR` map:
OL6→`UEKR4`, OL7/8→`UEKR6`, OL9/10→`UEKR8`) and
the latest upstream ENA (`git ls-remote`), and runs the OL only if either is newer
than what the ledger covers (or the OL has no ledger entry); otherwise it is
skipped with no build. A probe that cannot determine the latest is fail-open (the
OL runs) by default, or fail-closed (skipped) under `--strict`. `--force` bypasses
both the gate (every OL runs) and the per-combo dedup (every version re-tests).

Before the matrix, each OL runs a **mandatory QA preflight**: a smoke build of
only the pinned ENA version, to confirm the clean-core rootfs and
`install-ena-driver.sh` are healthy before the (expensive) full sweep. It is
**QA-only — not recorded in the ledger** and uses its own debug namespace; a clear
failure **early-exits that OL** (the matrix is skipped, the ledger untouched),
emitting a self-contained diagnostic bundle
`<cleancore-dir>/preflight-ol<N>-FAILED.log` (header + result + host context + the
full `install-ena-driver.sh` output) for human / LLM analysis. Transient-looking
failures (mirror / `kernel-uek` provision / network hiccups) are retried up to
`--preflight-retries` (default 2); a clear build/compile failure is treated as
real and not retried. The matrix then re-builds the pin as the recorded canary,
so the pin is built twice by design.

The run log frames each OL with a `===` banner, separates the QA-preflight and
build-matrix phases with `----` lines, tags every build with an `[i/N]` progress
counter, and prints a per-OL `matrix done -- X ok, Y fail, Z skipped (of N)` line
plus a final `ENA matrix complete -- ...` summary (the clean-core builder's
result + summary style).

```sh
# a few cases locally (the full in-scope sweep is for the user's env / CI):
bash tests/ena/run-ena-buildtest-matrix.sh --ol 6 --ena-versions "2.9.1 2.8.6"
bash tests/ena/run-ena-buildtest-matrix.sh --ol 6 --pinned-only   # just the pin
bash tests/ena/run-ena-buildtest-matrix.sh          # OL6-10 x ENA Express scope (>= min_version)
bash tests/ena/run-ena-buildtest-matrix.sh --full   # OL6-10 x ALL releases (pre-express included)
bash tests/ena/run-ena-buildtest-matrix.sh --report-only  # no builds: regenerate reports from the ledger
```

The committed `buildtest-ledger.json` / `RESULTS-ol{6,7,8,9,10}.md` are the
**first express-scoped five-major sweep** on the maintainer's host (2026-07-05;
145 rows = 29 in-scope versions x OL6-OL10): OL6 UEK4 builds 6/29 (the known
`[2.8.6, 2.9.1]` window), OL7 UEK6 builds 12/29 (`[2.12.2, 2.17.0]`,
byte-reproducing the retired run's `>= 2.8.0` subset on the same kernel), OL8
UEK6 (new kernel `.4.3`; full re-test via the kver-primary dedup) builds 12/29
(same window), and OL9/OL10 UEKR8 build 8/29 each (`[2.13.2, 2.17.0]` — the
precise UEKR8 floor). The retired pre-express evidence (210 rows = 70 versions
x OL6/7/8) lives in git history only. An `ok` is compile + DKMS-install
(necessary, not sufficient; real load/device is B-T7/B-T8). A later run in the
user's environment / CI grows the ledger (the dedup makes that a clean append).

## SSM Agent install+run test matrix (`tests/ssm/`)

Structurally the same as the ENA matrix, but for the AWS SSM Agent (a Go binary,
not a kernel module). `run-ssm-installtest-matrix.sh` determines per OL which SSM
versions **install AND run** in a clean-core container and evaluates them against
the AWS minimum `>= 3.3.3598.0` (the 2026-06-16 Run Command `ec2messages`
deprecation). `install-ssm-agent.sh SSM_INSTALLTEST=1` provisions the OL UEK into
the kernel-less container (`yum --enablerepo=<UEKR> install kernel-uek`, the same
install-at-test-time path as the ENA matrix, so `rpm -q kernel-uek` records the OL
kernel like `rpm -q glibc` records glibc), installs the agent RPM with `rpm -Uvh`
(local file, no repo — only glibc is required, and the EL6 yum-over-HTTPS quirk is
avoided) and runs `amazon-ssm-agent -version` locally (no AWS/IMDS) to prove the
Go runtime loads. `status=ok` requires install + run.

The compatibility surface is `(kernel, glibc) x version`; the ledger dedups on
`(osmajor, ssm_version, kver)` kver-PRIMARY (`kver` = the OL UEK, `rpm -q
kernel-uek`, mirroring ENA) with `test_host_kernel` (the runner kernel the binary
ran on), `glibc`, `go_version`, and the derived `min_kernel` per entry.
**Fidelity:** the glibc axis is faithful (the container's real OL glibc gates a
dynamic version), but the **kernel axis is not** in a container — the binary runs
on the host (runner) kernel, recorded as `test_host_kernel`, while `kver` records
the OL UEK from the rpm db; the matrix surfaces a static kernel-axis proxy from
each release's go.mod `go` directive. `list-ssm-releases.sh` records `go_version` plus `go_version_available`
+ `go_mod_http_status` (so a null `go_version` is self-explaining: `404` = a
pre-go-modules tag with no go.mod) and the `min_kernel` proxy; the `go_min_kernel`
mapping is reuse-by-copy across the lister and the matrix, kept in lock-step by
`tests/t018_ssmverdict.sh`. A faithful kernel verdict needs a kernel-matched runner
or a real instance.

Default mode tests only versions `>= 3.3.3598.0` (the question "is remediation
possible?"); `--full` tests every version (for the all-NG case). `RESULTS-ol<N>.md`
opens with a paraphrased summary of the AWS Run Command ec2messages deprecation
(with doc links), then a test-environment block (`env_kernel` / `env_glibc` /
`test_host_kernel`) and a per-version table with category-prefixed columns
(`agent_go_version`, `compat_min_kernel`); it gives, per kver, the max install+run
version and the verdict (`compliant-capable` / `ec2messages-only` / `none`). The pure verdict/proxy/filter logic (`ssm_ge`,
`go_min_kernel`, `ssm_in_scope`, `ssm_compliance`) is unit-tested by
`tests/t018_ssmverdict.sh` (host-only, no container/network). Run examples:

```
bash tests/ssm/list-ssm-releases.sh                                  # version list + go_version
bash tests/ssm/run-ssm-installtest-matrix.sh --ol 6                  # OL6, versions >= 3.3.3598.0
bash tests/ssm/run-ssm-installtest-matrix.sh --ol 6 --full           # OL6, every version
```

The matrix is manual / on-demand (root + container; NOT a `run-all.sh` tier). The
release list (`ssm-agent-releases.json`) and the ledger
(`ssm-installtest-ledger.json`) + `RESULTS-ol{6,7,8,9,10}.md` are committed. The
committed ledger and reports are a **real** default-mode (`>= 3.3.3598.0`) run
(55 rows = 11 versions x OL6/OL7/OL8/OL9/OL10; the 2026-07-13 five-major sweep):
each OL is 9/11 ok, with
`3.3.3883.0` / `3.3.4364.0` the only fails (their RPMs return HTTP 403 at the
S3 URL -- an upstream availability gap, not an install/run incompatibility), so
every OL's verdict is `compliant-capable` (max install+run `3.3.4793.0`).
`kver` is each OL's provisioned UEK
(OL6 `4.1.12-124.48.6.el6uek`, OL7/OL8 the UEK6 `5.4.17-*` kernels, OL9 UEK7
`5.15.0-322.203.3.3.el9uek` / glibc 2.34, OL10 UEK8 `6.12.0-204.92.4.2.el10uek` /
glibc 2.39). All five majors ran on the maintainer's host (uniform
`test_host_kernel` `6.12.0-211.28.1.el10_2`); since the agent runs on the host
kernel in a container the run does not exercise the OL kernel axis, but each
install+run is real and the recorded `kver` is the provisioned OL UEK in
each case. A later run in the maintainer's env / CI (a kernel-matched runner for
the kernel axis) grows the ledger via the kver-PRIMARY dedup append. Production
integration into `build-ol-aws-ami.sh` is deferred (decided from the report).

## AWS CLI v2 install+run test matrix (`tests/awscli/`)

Structurally the same as the SSM matrix, but for AWS CLI v2 and on the **glibc**
axis. `run-awscli-installtest-matrix.sh` determines per OL (**OL6/OL7/OL8**) which
v2 versions **install AND run** in a clean-core container.
`install-awscli.sh AWSCLI_INSTALLTEST=1` provisions the OL UEK (so `rpm -q
kernel-uek` records the OL kernel, mirroring SSM), unzips the self-contained v2
bundle (`awscli-exe-linux-x86_64[-<ver>].zip`), installs it with `aws/install`,
and runs **`aws --version` + `aws configure list`** locally (no AWS creds / no
IMDS) to prove the bundled interpreter + glibc-linked `.so`s load. `status=ok`
requires install + both run checks. (`aws sts get-caller-identity` needs creds +
network — a real-instance confirmation, not run here.)

**Why glibc.** v2 BUNDLES its own Python, so it does not use the OS Python — but
the bundled interpreter + C-extension `.so`s are built against a manylinux glibc,
so the OS glibc gates install/run. Per AWS's *Linux Support Updates for AWS CLI
v2* (2024-09-16), current v2 is manylinux2014 (glibc 2.17); glibc ≤ 2.16 must pin
v2 ≤ 2.17.49. The container's real OL glibc (`rpm -q glibc`) is what the bundle
links against, so unlike the SSM/ENA kernel axis this install-test is **faithful**
for glibc.

**Bundled Python + empirical glibc (recorded per entry).** Because the matrix
already unzips each bundle, two facts are read for free and survive the
glibc-too-old case (the binary need not execute): `bundled_python` (the bundled
CPython, from `aws/dist/libpython3.X.so*`, refined to the full patch from
`aws --version` when it runs) and `min_glibc_measured` (the bundle's empirical
floor — the max `GLIBC_x.y` symbol required across its `.so`s, read with a
dependency-free grep that matches `readelf`). The documented heuristic floor
`min_glibc` (≥2.17.50 → 2.17, else 2.5) is also recorded as a cross-check, and
`python_eol` records the bundled Python's documented end-of-life. The ledger
dedups on `(osmajor, awscli_version, kver)` kver-PRIMARY.

**Lifecycle (the bundled Python is frozen).** The bundled interpreter is not
independently patchable; moving to a newer (supported) Python means moving to a
newer v2 — and a glibc-capped OS caps the v2 version, so it caps the Python too.
`RESULTS-ol<N>.md` therefore opens with the glibc rationale, a **static**
Python-EOL table and the **OS's own EOL/EOS** (both provenance-stamped with the
verified date + sources, Q2 option b), then per kver a verdict (`current` /
`capped at <ver>` / `none`) and a per-version table with `bundled_python`,
`python_eol`, and `compat_min_glibc (measured / heuristic)`. The pure
verdict/lifecycle logic (`awscli_ge`, `awscli_min_glibc`, `awscli_in_scope`,
`awscli_verdict`, `python_eol`) is unit-tested by `tests/t019_awscliverdict.sh`
(host-only, no container/network), which also locks the reuse-by-copy
`awscli_min_glibc` in `list-awscli-releases.sh` to the matrix. Run examples:

```
bash tests/awscli/list-awscli-releases.sh                            # v2 version list + zip availability + min_glibc
bash tests/awscli/run-awscli-installtest-matrix.sh --ol 6            # OL6, every v2 version
bash tests/awscli/run-awscli-installtest-matrix.sh --ol "6 7 8"      # the full OL6/7/8 sweep
```

The matrix is manual / on-demand (root + container; NOT a `run-all.sh` tier). The
release list (`awscli-releases.json`), the ledger
(`awscli-installtest-ledger.json`) and `RESULTS-ol{6,7,8}.md` are produced by a
**real** matrix run / network probe in the maintainer's env (a long-running
clean-core + network task) and are not generated in this authoring environment;
they append to the ledger via the kver-PRIMARY dedup. Production integration into
`build-ol-aws-ami.sh` is deferred (install-test tooling only, mirroring SSM).

## B-T4 - Kickstart syntax conformance (`tests/validate-kickstart.sh`)

Upstream `oracle-linux-image-tools` ships no `distr/ol6-slim`, so this wrapper
**synthesizes** the OL6 kickstart (the `EOF_OL6_KS` heredoc in
`build-ol-aws-ami.sh`). Because that kickstart is the wrapper's own artifact, we
validate its **syntax** against the anaconda generation that OL6 actually ships
(anaconda-13) using [`pykickstart`](https://pykickstart.readthedocs.io/)'s
per-release command set:

- **OL6 → `ksvalidator -v RHEL6`**

OL7 and later consume upstream-shipped kickstarts and are validated upstream.

### Run

```sh
pip install pykickstart          # provides the 'ksvalidator' CLI
bash tests/validate-kickstart.sh
```

Expected output:

```
== kickstart syntax conformance ==
PASS: OL6 synthesized kickstart (ksvalidator -v RHEL6, ... lines)
RESULT: PASS
```

The script exits non-zero if any directive is rejected by the target command
set, and SKIPs (exit 0) if `ksvalidator` is not installed.

### What this catches

Directives/options that exist only on a later anaconda but leaked into the OL6
kickstart (the "OL7-ism" class — see SPEC Part D pitfall **D.18**). For example
it rejects `bootloader --boot-drive=...` and a bare `rootpw --lock`, both of
which are RHEL7+/anaconda-19+ only and halt OL6/anaconda-13 at parse time.

### What this does NOT catch (limitation)

`ksvalidator` checks **syntax only**. It does **not** verify:

- **Runtime filesystem support** — e.g. whether OL6/anaconda-13 can actually
  create an **xfs** root (`ROOT_FS=xfs`). A directive like `part / --fstype=xfs`
  is syntactically valid yet may fail at install time.
- **Package availability** — e.g. `iptables-services` does not exist in the OL6
  repositories (only `iptables` does); a missing package is a runtime package-
  selection failure, not a syntax error.

These are confirmed only by a **live build** — for a runtime failure, reproduce
the install in isolation with a bare `virt-install` (text mode, explicit
`console=ttyS0`) so the anaconda output is fully visible. (`SERIAL_CONSOLE=yes`
can stream the OL6/7 install too, but it is a debug-only opt-in that can hang
the build at install-VM end — the default is `no`; see SPEC A.13 / D.18.)

## Serial console verification (CHECK 5 + on-instance)

The AWS serial-console fix (SPEC **D.25**) spans the boot path, so it has two
verification layers: an in-build advisory check and an on-instance confirmation
after launch.

### In-build: CHECK 5 (Phase 6, advisory, BLS-aware)

CHECK 5 confirms `console=ttyS0` reached the kernel cmdline of the built image
*in the same build*. It is **BLS-aware**: OL8+ enable the GRUB BootLoaderSpec, so
the cmdline lives in `/boot/loader/entries/*.conf` (`options` line), **not** in
`grub.cfg`. The check therefore inspects **both**:

- the located bootloader menuentries (`virt-cat` of the `grub.cfg`/`grub.conf`,
  grepping `kernel`/`linux16`/`linuxefi`/`linux` lines), and
- every BLS entry (`virt-ls /boot/loader/entries` → `virt-cat` each `*.conf`,
  grepping the `options` line),

and PASSes if `console=ttyS0` is present in **either**. It is **advisory** (warn
only, never fails the gate): a missing serial console costs observability, not
bootability. A warning here is a real signal that the Phase-3 serial-console hook
did not take effect — investigate before relying on `Get System Log`.

### On-instance (after launch) — the maintainer's VM-path check

CHECK 5 reads the *image*; only a launched instance proves the running cmdline.
On each OL6–OL10 instance:

```sh
cat /proc/cmdline                                   # all: console=ttyS0 present, last
sudo grubby --info=ALL | grep args                  # OL7-10: args carry console=ttyS0
cat /boot/loader/entries/*.conf | grep '^options'   # OL8-10 (BLS): options carry console=ttyS0
sudo grep -E 'serial|terminal' /boot/grub2/grub.cfg # OL7-10: GRUB-over-serial (GRUB_TERMINAL/SERIAL)
sudo grep -E '^serial|^terminal' /boot/grub/grub.conf  # OL6: serial/terminal directives
systemctl is-enabled serial-getty@ttyS0.service     # OL7-10: enabled
systemctl is-active  serial-getty@ttyS0.service     # OL7-10: active
```

And from the AWS side: `aws ec2 get-console-output` (or the console's **Get System
Log**) should now show the kernel ring buffer and boot messages; the EC2 **Serial
Console** should reach a login prompt (and the GRUB menu, via layer 2). These are
the maintainer's checks — the sandbox has no KVM/AWS path.
