# TESTING

Operational tests for `bash-ol-aws-ami-builder`. These are maintainer-facing
checks, not part of the build pipeline itself.

> **Governance note.** This is a subproject-local maintenance document. The
> bash documentation-template family (including a TESTING template) is not yet
> extracted into the governance canon — by the rule-of-two it stays deferred
> until a second bash consumer exists. So this file intentionally carries **no
> canon doc-provenance front-matter** and is **not** part of the reconstructed
> doc-set verified by `doc_gate --reconstructed`. When a bash TESTING template
> is later canonised, this file can be reconstructed/pinned to it.

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
| external commands (`aws`, `git`, `virsh`, `guestfish`, `dnf`, `osinfo-query`, ...) | mock via PATH-shadow + call-log spy (implemented in `tests/lib/mock.sh`; see `tests/t4_cmdmock.sh`) or function override |
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

Current fixed pass count: **189 passed, 1 skipped, 0 failed** (B-T1 = 25,
B-T2 = 20, B-T3 = 35, command-mock = 9, env-parity = 31, idempotency = 8,
hook-timing = 8, log-format = 12, ena-uek-detect = 9, ena-reporting = 15,
build-visibility = 17; plus
B-T4 kickstart which is **1 pass with `ksvalidator`, 1 skip without** -> 190/0
with it). The host-runnable tiers
(L0-L2) are complete; B-T7/B-T8 (L3/L4) remain deferred (builder host + AWS). A
tier SKIPs cleanly when its optional dependency is absent.

## Environment & version dependencies

The harness is host-distro-agnostic but depends on a few tools; pin / record
them so a run is reproducible:

- **bash** >= 4 (arrays, `${var,,}`); developed and run on bash 5.x in the
  Claude Linux container substrate.
- **ShellCheck** (B-T2): obtained as the self-contained static binary from the
  upstream GitHub release (no runtime deps); **pinned to 0.10.0** - record the
  version (`run-all.sh` prints the resolved one). The canonical severity is
  **`style`** (the strictest), set on the command line by `tests/t2_shellcheck.sh`;
  `.shellcheckrc` carries `external-sources=true` + `source-path=SCRIPTDIR` only
  (no global `disable=`). Determinism comes from three documented inline
  exemptions, each a single code on a single statement with a rationale comment:
  `SC2016` at the SELinux-relabel sed injection and at the `bash -c '...$1...'`
  secure idiom in `build-ol-aws-ami.sh`, and `source=/dev/null` at the runtime
  `. /etc/os-release` in `install-ena-driver.sh`. Every other code stays active
  everywhere. B-T2 SKIPs if shellcheck is absent (the CI gate requires it).
- **pykickstart / `ksvalidator`** (B-T4): optional; B-T4 SKIPs if absent.
- **awk / sed / grep / find** (coreutils + gawk): present in the container.

Host-only tiers (B-T1, B-T2, B-T3, B-T5, B-T6, B-T9, log-format) run entirely in
the container.
**B-T7 / B-T8 are integration / E2E** and require a real KVM builder host and an
AWS account; they are documented, not run by `run-all.sh`.

## Coverage ledger

Tracks which tiers exist so gaps are visible top-down (the bash analogue of the
PowerShell canon's `tested` + fixed pass count). New tests register a row.

| Tier | Layer | Status | Notes |
|:--|:--|:--|:--|
| B-T1 parse | L0 | implemented | `bash -n` all `.sh` + 5 shell-bodied heredoc bodies; 13 asserts |
| B-T2 ShellCheck | L0 | implemented | canonical `-S style` over every `.sh` via `.shellcheckrc`; 3 documented inline exemptions; SKIPs if shellcheck absent |
| B-T3 pure-function unit | L1 | implemented | sources the wrapper (tail `main` is guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so sourcing has no side effects); table-driven `parse_ol_version_from_iso` + `parse_args` contract; 25 asserts |
| B-T (command mock) | L1 | implemented | `tests/t4_cmdmock.sh` via `tests/lib/mock.sh` (PATH-shadow + call-log spy); `detect_qemu_user` (mocks `id`), `detect_os_variant` (mocks `osinfo-query`); 9 asserts |
| B-T (IMDS rejection) | L1 | implemented | `normalize_imds_support` extracted (behaviour-neutral) + table-driven unit in `tests/t3_unit.sh`: normalisation, invalid->die, OL6 v2.0->die; 10 asserts |
| B-T5 env parity | L2 | implemented | `tests/t6_envparity.sh`: 20 common-core keys, OL6/OL7-only KERNEL/UEK_RELEASE extras, S3_BUCKET/AWS_REGION/UPDATE_TO_LATEST/CLOUD invariants, per-OS DISTR; 31 asserts |
| B-T6 idempotency | L2 | implemented | `tests/t7_idempotency.sh` (structural): each of the 7 `[ol-aws-ami-builder PATCH ...]` markers is fronted by a `grep -Fq` guard; runtime apply-twice is B-T7/B-T8 |
| B-T4 kickstart | L2 | implemented | `tests/validate-kickstart.sh`, **wired into the runner** via `tests/t5_kickstart.sh` (SKIPs without `ksvalidator`); see below |
| B-T9 hook timing | L1/L2 | implemented | `tests/t8_hooktiming.sh`: the OL6 cloud-user hook must run *after* `cloud::cloud_init` (configs exist), never at source time; static wrapper-wiring + no-top-level-`sh` guards, plus a behavioural order/edit check; 8 asserts |
| B-T (log format) | L1 | implemented | `tests/t9_logformat.sh`: every timestamped channel emits **date-first** (`YYYY-MM-DD HH:MM:SS` leads, `[SEVERITY]`/source tag follows; SPEC E.1); colour-stripped match across info/warn/error/build/debug/external + a negative guard against the old tag-first order; 12 asserts |
| B-T (ena uek-detect) | L1/L2 | implemented | `tests/t10_enaukedetect.sh`: the OL6 ENA self-build retargets the amzn-drivers Makefile UEK detection (`IS_UEK`/`ENA_KERNEL_SUBVERSION_*`) from `uname -r` to `BUILD_KERNEL` (the DKMS target), so the `kcompat.h` `page_ref_count` guard evaluates against the build target rather than the libguestfs appliance kernel; structural (present, OL6-gated, idempotency-guarded, pipe-anchored) + behavioural fixture transform; 9 asserts. Compile/boot proof is B-T7/B-T8 |
| B-T (ena reporting) | L1/L2 | implemented | `tests/t11_enareporting.sh`: the Phase 6 readiness report prints aligned, fixed-width `ENA Driver (Kernel in-box)` / `ENA Driver (Self-Build)` lines with an explicit in-tree no-version fallback; `install-ena-driver.sh` logs the in-box ENA identity before the self-build; the auto AMI name/description gain a self-built-ENA marker and the final summary prints the description + an ENA driver line; the `[OLAWS-ENA01]` hook log and the marker read the pin from `install-ena-driver.sh`'s `ENA_VERSION_OL<major>` default (no hardcoded `OL6 2.5.0` drift). Structural presence checks grep files directly (avoiding a `printf\|grep -q` SIGPIPE race under `pipefail` on the large wrapper) + behavioural pin-reader fixture; 15 asserts. AMI naming/boot proof is B-T7/B-T8 |
| B-T (build visibility) | L1/L2 | implemented | `tests/t12_buildvisibility.sh`: OL7 build-log visibility (handoff B.1.5 feedback 4). `install-ena-driver.sh` emits greppable `[ena-driver][stage]` breadcrumbs at the phase boundaries (esp. dkms add/build/install) and `record_make_log()` preserves the DKMS make.log to `/var/log/ol-aws-ami-builder-ena-make.log` on a successful build (guest output is swallowed by virt-customize on success); the wrapper records the latest LIVE orchestrator line to `BUILD_STAGE_FILE` in `log_external` and the Phase-5 heartbeat shows it as `stage: …` (assembled into one atomic `log_progress` write); `HEARTBEAT_INTERVAL_SEC` default is 10s. Structural greps (file-direct) + a behavioural `log_external`→stage-file fixture; 17 asserts. Real OL7 build/boot proof is B-T7/B-T8 |
| B-T7 offline image inspection | L3 | deferred | builder host |
| B-T8 E2E build + boot | L4 | deferred | builder host + AWS |

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
the build at install-VM end — the default is `no`; see SPEC A.7 / D.18.)
