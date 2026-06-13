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

Current fixed pass count: **205 passed, 1 skipped, 0 failed** (B-T1 = 33,
B-T2 = 28, B-T3 = 35, command-mock = 9, env-parity = 31, idempotency = 8,
hook-timing = 8, log-format = 12, ena-uek-detect = 9, ena-reporting = 15,
build-visibility = 17; plus
B-T4 kickstart which is **1 pass with `ksvalidator`, 1 skip without** -> 206/0
with it). The B-T1 / B-T2 counts include the five `tests/cleancore/` clean-core
builders (see "Container clean-core test base" below): B-T1 and B-T2 parse- and
lint-check **every** `.sh` in the project, so adding a script raises both counts
by one. The host-runnable tiers
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

## Coverage ledger

Tracks which tiers exist so gaps are visible top-down (the bash analogue of the
PowerShell canon's `tested` + fixed pass count). New tests register a row.

| Tier | Layer | Status | Notes |
|:--|:--|:--|:--|
| B-T1 parse | L0 | implemented | `bash -n` every `.sh` in the project (incl. `tests/cleancore/` and `tests/ena/`) + 5 shell-bodied heredoc bodies; 33 asserts |
| B-T2 ShellCheck | L0 | implemented | canonical `-S style` over every `.sh` in the project (incl. `tests/cleancore/` and `tests/ena/`) via `.shellcheckrc`; 3 documented inline exemptions in the wrapper/helpers + per-script inline exemptions in the clean-core builders (SC2086 mknod word-split, SC2016 literal yum-variable text); SKIPs if shellcheck absent; 28 asserts |
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
| clean-core builders | (test base) | implemented | `tests/cleancore/build-cleancore-ol{6,7,8,9,10}.sh` — general-purpose container test-base builders (see "Container clean-core test base" below), plus `tests/cleancore/build-cleancore.sh` (the `--all`/`--ol` orchestrator wrapping them). **Not** run by `run-all.sh` (heavy: needs root + network + a multi-hundred-MB build); covered by B-T1 (parse) + B-T2 (lint) like every `.sh`; each builder self-tests a fresh unpack of its own `.tar.gz` |

## Container clean-core test base (`tests/cleancore/`)

The `tests/cleancore/` directory holds five self-contained builders —
`build-cleancore-ol6.sh` / `-ol7.sh` / `-ol8.sh` / `-ol9.sh` / `-ol10.sh`
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
  TLS-stack modernization before it can reach modern `yum.oracle.com`.
- **[C] CLEAN-CORE** — the deliverable rootfs from the `yum`/`dnf
  --installroot` transaction, finalized (device nodes, OCI yum-variable rewrite,
  build-time repo dropped, logs zero-filled, machine-id / ssh host keys cleared)
  and packed as a `.tar.gz`.

Per-OL specifics: OL6/OL7 build with `yum`; OL8/OL9/OL10 install the full `dnf`
into the slim builder (`microdnf install dnf`) first. OL7's manifest no longer
mirrors the upstream `distr/ol7-slim` kickstart, and OL6 (which has no upstream
`ol6-slim`) is built as a fresh curated `yum --installroot` install rather than
from the VM kickstart. **OL6 through OL10 have all been trimmed** to a
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
repointed to the archive and `enabled=0`. **`jq`** is a curated test-base
essential on every clean-core: on OL7–OL10 it is part of the enabled standard OL
repo (a plain `INCLUDE` member), and on OL6 — where `jq` is an EPEL package and
absent from the base — it is installed from that EPEL archive by enabling EPEL
**transiently for the one install**, leaving the shipped EPEL `enabled=0`. The
unconditional self-test asserts `jq --version` runs in the finalized image.
Two static snapshots accompany the base: `cleancore-ol<MAJOR>.sbom.json` (each
finalized image's package set, names-only, reusable JSON) and
`REFERENCE-oracle-official-images.md` (the official slim images' sources, pinned
commits, and name-version manifests). Neither is a `.sh`, so both are outside
B-T1/B-T2 and are not drift-checked gates.

Run one with `bash tests/cleancore/build-cleancore-ol<MAJOR>.sh [output.tar.gz]`
(see "Environment & version dependencies" for the required tools; `INSECURE_TLS=0`
drops the build-time `sslverify=0` on a trusted host). The script exits 0 only if
the build and the unconditional self-test section pass; the network-dependent
readiness probe SKIPs (never fails the build) when offline.

### Orchestrator (`build-cleancore.sh`)

`tests/cleancore/build-cleancore.sh` is a self-contained wrapper (inline helpers,
no shared library — repo policy for user-run scripts) that drives the per-OL
builders in one call. It **invokes them as separate executables** (never sources
them), so each `build-cleancore-ol<MAJOR>.sh` stays the single source of truth
for its own OL; the wrapper only adds a "build every supported OL" mode, a
host-OS sanity check, and a hard prerequisite gate:

```sh
bash tests/cleancore/build-cleancore.sh --ol 6                  # one OL major
bash tests/cleancore/build-cleancore.sh --all --out-dir ./cc    # OL 6,7,8,9,10
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
`tests/ena/ena-driver-releases.json`. This snapshot is the **input** to the ENA
self-build test matrix: "test every ENA version" iterates the `versions[]`
array, and each entry carries the deterministic source `tarball_url`
(`…/archive/refs/tags/ena_linux_<ver>.tar.gz`) that `install-ena-driver.sh`
fetches. Each entry ALSO carries an explicit availability pre-check of that
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
container (above). SPEC A.7 "Container compile-test (`ENA_BUILDTEST`)" defines
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
2.17.0g, UEK6 `5.4.17-2136.356.4.2.el8uek`). OL8 self-build is standalone-only;
the AMI pipeline keeps OL8 on its in-distro ENA driver. OL9+ no-op.

## ENA self-build test matrix (`tests/ena/run-ena-buildtest-matrix.sh`)

`run-ena-buildtest-matrix.sh` runs `ENA_BUILDTEST` across an **OS × ENA-version ×
kernel** matrix and records the outcomes in a machine-readable **ledger** that is
both the evidence store and the dedup state (SPEC B.9). It is self-contained
(inline helpers, no shared library) and drives the existing pieces as separate
executables — `tests/cleancore/build-cleancore.sh` for the per-OL rootfs and
`install-ena-driver.sh ENA_BUILDTEST=1` for each version. Targets **OL6/7/8**
(where `ENA_BUILDTEST` is wired); like the builders it is **manual / on-demand**
(root + network + multi-hundred-MB builds) and **not** a `run-all.sh` tier.

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
  ledger, **newest kernel first**, each kernel a section with an `ok`/total
  count and a per-version table. A `fail` row is recorded evidence (e.g. an ENA
  release too old for that kernel), not a harness error, so the run still exits
  0.

```sh
# a few cases locally (the full matrix is for the user's env / CI):
bash tests/ena/run-ena-buildtest-matrix.sh --ol 6 --ena-versions "2.9.1 2.2.0"
bash tests/ena/run-ena-buildtest-matrix.sh --ol 6 --pinned-only   # just the pin
bash tests/ena/run-ena-buildtest-matrix.sh                        # OL6/7/8 x all releases
```

The committed `buildtest-ledger.json` / `RESULTS-ol6.md` are an in-environment
**sample** (OL6, `2.9.1` ok + `2.2.0` fail on UEK4 `4.1.12-124.48.6.el6uek`); a
full run in the user's environment / CI grows the ledger (the dedup makes that a
clean append).

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
