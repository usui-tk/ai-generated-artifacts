---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.1.0
  rendered: 2026-07-02
---
# TESTING - bash-rhel-container-testsuite

> How this suite is tested, how to run it, and the contract every tier obeys.
> The tier taxonomy and the per-tool framework are specified in
> [`SPEC.md`](./SPEC.md) sections 6-7; this document is the operational guide.

---

## Test model (top-down baseline)

The harness is **framework-free** (no bats/shunit2/ShellSpec), single-file and
stdlib-only, matching the repository-wide policy. The shared surface lives in
`tests/lib/`:

* `assert.sh` - `assert_rc` / `assert_eq` / `assert_match`, pass/fail/skip
  counters, and `t_done`, which prints the machine-readable
  `## RESULT pass=.. fail=.. skip=..` line and returns non-zero on any failure.
* `mock.sh` - PATH-shadow command mocks with call spying (`mock_setup`,
  `mock_cmd`, `mock_calls`). The primary mocked surfaces in this suite are
  `podman`/`curl`/`tar` (acquisition) and `dnf`/`yum`/`microdnf`/`rpm`/`repoquery`
  (package-manager + entitlement detection).
* `heredoc.sh` - extracts a single-quoted heredoc body so L0 can `bash -n` any
  shell-bodied provisioning snippet shipped into a container (used from Phase 3).

Each tier file is a standalone `bash` script that sources `assert.sh`, runs its
assertions, and ends with `t_done`. `tests/run-all.sh` runs each tier in its own
subprocess (isolation), parses the `## RESULT` line, aggregates, and exits
non-zero if any tier fails or produces no result line.

---

## Tiers (L0-L4)

See [`SPEC.md`](./SPEC.md) B.9 for the authoritative table. In short:

| Tier | What | Run by | Network |
|:--|:--|:--|:--|
| **L0 Static** | `bash -n` (`t001`), ShellCheck `-S style` (`t002`) | `run-all.sh` | none |
| **L1 Unit (hermetic)** | pure verdict helpers, table-driven, no I/O | `run-all.sh` | none |
| **L2 Component** | ledger guards, RESULTS-from-fixtures, env parity | `run-all.sh` | none |
| **L3 Integration** | real pull + install/build, both init modes | `tests/aws_*/run-*-matrix.sh` | `*.quay.io`, `*.amazonaws.com`, RHEL repos |
| **L4 E2E** | module **load**, real ENA/SSM on a genuine RHEL host | manual | full |

**L0-L2 are hermetic** and run on any host (Fedora/Ubuntu/Debian/macOS/RHEL) or
in CI. **L3 needs container egress**; **L4 needs a real RHEL instance** and is
deferred.

---

## Test-environment provisioning (L2, r33/r36)

The vendor base image is a *starting point*, not a ready-made test platform.
Between acquisition (L1) and the test (L3), the harness provisions a per-OS
"test-ready" image: `lib/provision-test-env.sh` installs a **common package
manifest** (`PROVISION_PKGS`, default `gawk`) onto the base and commits ONE image
per OS major, reused across the sweep (idempotent - the image tag embeds a
fingerprint of the manifest, so a changed manifest rebuilds and an unchanged one
reuses the commit). The manifest is common to every tool - one image per OS, not
one per test - so the three L3 matrices resolve their base ref, then run against
the provisioned ref.

It exists because the minimal images are not complete for every major: RHEL 6
(`rhel6/rhel`) ships without `awk`, which the amazon-ssm-agent rpm's `%pretrans`
guard calls, so a bare EL6 install fails before it starts. The manifest install
is **repo-access-agnostic** (r36): it neutralizes the RHSM plugins when anonymous
and installs with `*.skip_if_unavailable=1`, so the mounted host `redhat.repo`
(the HOST major's entitled repos - wrong-major / unregistered inside a container)
is skipped instead of failing the transaction; the package resolves from any
working repo (public UBI / entitled `rhel-*` / RHUI). Leaving that fatal was the
r33 defect that skipped RHEL 8/9/10 on an entitled host.

**Provisioning is a test prerequisite (r36).** Each matrix prepares every
requested major's image *before* any test runs (a pre-flight). If a major cannot
be prepared, the prerequisite is not met and the run **fails fast** - it aborts
(non-zero) without running any test. The exception is `PROVISION_OPTIONAL_MAJORS`
(RHEL 6 by default): EL6 needs its own `rhel-6` entitlement the host cannot
supply, so an unprovisionable EL6 is skipped (no EL6 tests) and the run continues
for 7-10.

This is the base point for **future test expansion**: a new test that needs
another base package extends `PROVISION_PKGS`, not a production installer.
Hermetically unit-covered by `tests/t021_provisionenv.sh` (a PATH-mock `podman`:
tag/fingerprint determinism, idempotent reuse, build+commit, real stderr on
failure); the real `podman commit` flow runs in the L3 matrices on an entitled
host. Spec: SPEC.md B.6.1 / B.9.

---

## Running the suite

```bash
# from the project root
bash tests/run-all.sh
```

A green run ends with, e.g.:

```
SUITE: 546 passed, 0 skipped, 0 failed  (22 tiers, 0 tier-failure(s))
```

Run a single tier directly (its exit status reflects pass/fail):

```bash
bash tests/t001_parse.sh        # L0 parse
bash tests/t003_acquireunit.sh  # L1 acquisition unit
bash tests/t007_epelresolve.sh  # L1 EPEL resolution unit
bash tests/t021_provisionenv.sh # L1 test-env provisioning unit
```

The L3 integration matrices are **not** invoked by `run-all.sh`. Run them per
target with the one-script workflow below when container egress is available.

---

## Running the end-to-end tests (per target)

Each tool is a self-contained target under `tests/aws_<tool>/`. After clearing the
generated files and rebuilding the release baseline, a **single no-arg invocation**
of the matrix does everything: run the live matrix, persist the ledger, and
regenerate the `RESULTS-rhel<N>.md` reports (this mirrors the OL model project).

**Prerequisites (shared).** The live run (L3) needs `podman` + network egress to
the AWS endpoints and the RHEL/UBI registries. If `podman` is absent the run step
is skipped with a clear message and the reports are still regenerated (all cells
`pending`). For a MITM/dev TLS proxy, add `INSECURE_TLS=1`. Module **load** is
always **L4** (a real Nitro/Graviton host) and is never attempted here.

**Sub-actions (all three matrices).** No argument = the full E2E (run + persist +
generate). `--run` runs the matrix and persists the ledger only (no report).
`--generate-results` (re)generates the reports only - hermetic, no containers,
empirical cells read from the ledger if a run has populated it.

**Evidence produced.** `RESULTS-rhel{6,7,8,9,10}.md` (human-readable, per major) +
the tool's `*-ledger.json` (the durable machine record, `results[]`). A cell reads
`pending` until a live run fills it; `ran/installed` (or `built`) once it has.

### Quick reference

| Target | From `tests/<dir>/` | Live axes swept by one run |
|:--|:--|:--|
| AWS SSM Agent | `aws_ssm-agent` | all majors x **min->latest (11 versions)** x init_mode {none, systemd} |
| ENA driver | `aws_ena-driver` | all majors x entitlement {entitled, anonymous}; then `verify` |
| AWS CLI v2 | `aws_awscli-v2` | all majors x every in-scope v2 version (glibc axis) |

### AWS SSM Agent (install + service)

```bash
cd tests/aws_ssm-agent
rm -rf ./*.md ./*.json          # clear generated reports + ledger + releases
./list-ssm-releases.sh          # rebuild the release baseline (ssm-releases.json)
./run-ssm-installtest-matrix.sh # E2E: sweep + persist ledger + regenerate RESULTS
```

One run sweeps every in-scope version (min `3.3.3598.0` -> latest) x all majors x
both init modes, installs the RPM, runs `amazon-ssm-agent -version`, and (systemd)
enables the unit. Knobs: `OSMAJORS="9 8"`, `INITMODES="systemd"`,
`SSM_VERSIONS="3.3.3598.0 3.3.4793.0"` (narrow the sweep).

### ENA driver (self-build; verify is a separate step)

```bash
cd tests/aws_ena-driver
rm -rf ./*.md ./*.json
./list-ena-releases.sh
./run-ena-buildtest-matrix.sh   # E2E build matrix + persist ledger + regenerate RESULTS
./verify-ena-buildresults.sh    # read-only load-readiness (vermagic + symbol/CRC)
```

The build is **entitlement-gated**: `kernel-devel`/`gcc`/`make` come only from the
entitled repos, so the `entitled` column needs a **subscribed** host; `anonymous`
records `needs-entitlement`. `verify` reads the ledger + `./build-bundle` (the ko +
`Module.symvers` + vermagic the build side preserved); with no bundle yet it reports
load-readiness **pending** and exits 0. Knobs: `OSMAJORS`, `ENTITLEMENTS="entitled"`.

### AWS CLI v2 (install)

```bash
cd tests/aws_awscli-v2
rm -rf ./*.md ./*.json
./list-awscli-releases.sh
./run-awscli-installtest-matrix.sh  # E2E: sweep all in-scope versions + ledger + RESULTS
```

One run acquires each RHEL major, installs the v2 bundle for every in-scope version,
smokes `aws --version`, and records the empirical min glibc + bundled Python. The
single axis is **glibc** (the bundle's manylinux floor). Knob: `OSMAJORS`.

---

## L0 contract (current)

* **`t001_parse.sh`** - `bash -n` every `.sh` in the project tree (harness
  dogfooded), then `bash -n` each shell-bodied heredoc body on an allowlist. The
  Phase-1 allowlist is empty; entries are added with the install/build matrices.
* **`t002_shellcheck.sh`** - ShellCheck at the **canonical severity `style`**
  (the strictest) over every `.sh`, honouring `.shellcheckrc`, asserting **zero
  findings per file**. SKIPs cleanly if `shellcheck` is absent; the canonical
  gate requires it in CI.

**Exemption policy:** `.shellcheckrc` declares no global `disable=`. Any
suppression must be a narrow, documented inline
`# shellcheck disable=`/`source=` directive at the relevant statement, decided
once in the diff with a rationale. `external-sources=true` +
`source-path=SCRIPTDIR` make ShellCheck follow the `# shellcheck source=lib/...`
directives rather than suppress SC1091. As of r02 the **only** functional
exemptions are: `# shellcheck disable=SC2016` on PATH-shadow mock behaviour
strings (literal `$1`, expanded at the fake's runtime) and
`# shellcheck disable=SC2317` on the two indirectly-invoked `epel_head_ok` test
stubs in `t007`.

---

## L1 contract (current, r02)

The Phase-2 unit tiers are hermetic: each sources the library under test (sourcing
is side-effect-free) and drives every external command with a PATH-shadow mock,
so results are host-independent and deterministic.

* **`t003_acquireunit.sh`** - acquisition pure helpers (image/tag/ref maps,
  `acq_select_amd64_digest`, OCI URL builders, init-mode args, secrets presence,
  entitlement classification) plus one end-to-end curl-only pull with curl/tar
  mocked (sequencing + spying).
* **`t004_pkgmgrdetect.sh`** - the `dnf -> microdnf -> yum -> none` ladder driven
  under a PATH restricted to the mock bin, the command-string builders, and
  `pkgmgr_is_available` (asserts `dnf list --available`, never a bare repoquery).
* **`t005_entitlementdetect.sh`** - the 3-step entitlement flow, including the
  invariant that no classification grep runs before the makecache trigger.
* **`t006_initmodemap.sh`** - the `none | systemd` invocation-arg mapping.
* **`t007_epelresolve.sh`** - EPEL baseurl/gpgkey/repo-body resolution across all
  majors, the EPEL 10 minor HEAD-probe branch (stubbed), and the RHEL 6 archive
  special-case.
* **`t008_awscliverdict.sh`** (Phase 3) - the AWS CLI v2 matrix's pure helpers
  (`awscli_ge`, `awscli_min_glibc`, `awscli_in_scope`, `awscli_verdict`,
  `python_eol`, `rhel_glibc`, `awscli_band`, `awscli_expected`), loaded by
  extracting each function body from `run-awscli-installtest-matrix.sh`, plus the
  reuse-by-copy consistency between the matrix and `list-awscli-releases.sh`.
* **`t009_ssmverdict.sh`** (Phase 4) - the SSM matrix's pure helpers (`ssm_ge`,
  `rhel_glibc`, `ssm_in_scope`, `ssm_compliance`, `ssm_init_outcome`,
  `ssm_verdict`) and the matrix/lister `ssm_ge` reuse-by-copy. Covers the
  init_mode axis (none -> version-only, systemd -> service-capable).
* **`t010_enaverdict.sh`** (Phase 5, r31) - the ENA build-test matrix's pure
  helpers (`ena_ge`, `ena_kdevel_repo`, `ena_in_scope`, `ena_build_plan`,
  `ena_verdict`, `ena_load_tier`, `ena_express_verdict`) and the reuse-by-copy
  consistency of `ena_ge` (matrix/lister) and `ena_express_verdict`
  (matrix/lister/installer). Covers the E2' entitlement verdict (entitled ->
  ok/build-fail; anonymous -> needs-entitlement; load -> L4) and the ENA
  Express driver-version-floor readiness (`< 2.2.9` -> not-ready, `>= 2.2.9`
  -> bandwidth-only, `>= 2.8.0` -> express-ready; AWS ena-express.html - a
  driver-capability signal only, independent of the entitlement axis).
* **`t011_enaverify.sh`** (Phase 5) - the read-only verifier's load-readiness
  gates `ena_vermagic_verdict` (L4a) and `ena_symbols_verdict` (L4b CRC/kABI),
  loaded with `ENA_LIB_ONLY=1` so only the pure helpers run.
* **`t012_osprofile.sh`** (Phase 6) - every `lib/os-profile.sh` helper across all
  five majors, plus the cross-consistency invariants that make the profile a
  single source of truth: `osp_image == acq_image_for_major`,
  `osp_pull_tag == acq_tag_for_major`, `osp_epel_is_live` inverse of
  `epel_is_archive`, and `osp_kdevel_repo == ena_kdevel_repo`.
* **`t013_toolcontract.sh`** (Phase 7) - L2: loads `contract_dir_missing` and
  `contract_install_missing` from `tests/conformance/check-tool-contract.sh`
  (`CONTRACT_LIB_ONLY=1`), asserts the three shipped tools conform to the B.10
  (0)+(a-e) contract - including the **root `install-<tool>.sh` exists and the
  matrix kicks it** - that synthetic incomplete cases report their gaps, and that
  the checker exits 0.
* **`t014_pkgavail.sh`** (Phase 7) - the `lib/pkg-availability.sh` classification
  canon (`pkgavail_class`, `pkgavail_needs_entitlement`, `pkgavail_anonymous_status`,
  `pkgavail_over_network`, `pkgavail_tool_source`) incl. the end-to-end
  source -> class -> anonymous-status chain per tool.
* **`t015_installpins.sh`** (r08) - the per-RHEL-major version pins in the root
  install scripts. Sources each `install-aws_<tool>.sh` with `<TOOL>_LIB_ONLY=1`
  (defines helpers + pins, installs nothing), fakes the OS major, and asserts
  `resolve_version` resolves to the validated pin (RHEL 6: awscli `2.17.49`, ssm
  `3.3.3598.0`, ena `2.9.1`; RHEL 7-10 latest/`2.17.0`) and that an explicit
  `<TOOL>_VERSION` overrides it.
* **`t016_installintrospect.sh`** (r09) - the install scripts' introspection +
  structured-result machinery: `measure_min_glibc`, `detect_bundled_python`,
  `ko_module_version`, and that `die` emits exactly one `status:fail` `[result]`
  (with the reason) in test mode and is silent in production.

* **`t017_probeverdict.sh`** (r10) - `tests/probe-env.sh` verdict derivation:
  the platform / engine / egress / entitlement facts fold into the documented
  `ready | degraded | not-ready` classification, including the reasoned
  degraded states for partial egress.

* **`t018_repoaccess.sh`** (r12) - the per-(major, entitlement) repo-access
  model: anonymous-UBI vs entitled repo-id sets, the RHEL 6 Tier-C anonymous
  gap, and the EPEL 6/7 archive-only endpoints (`lib/epel.sh` +
  `lib/pkg-availability.sh` cross-checks).

* **`t019_enabuilddeps.sh`** (r22-r24) - the ENA build-dep hot path pinned
  hermetically: plain `kernel-devel` (never `kernel-devel-$(uname -r)` - the
  host-kernel tie regression guard), the designed non-zero `ensure_build_deps`
  rc contract at the call site, and the `needs-entitlement` verdict wiring.

* **`t020_helperidentity.sh`** (r27) - the duplicated-helper identity
  discipline (SPEC Part A A.10): the four self-contained-installer helpers
  (`entitlement_certs_present`, `pm_neutralize_rhsm_if_anonymous`, `run_pm`,
  `os_major`) are byte-identical across all three install scripts, so a fix
  applied to one copy that drifts from the others fails the suite.

* **`t021_provisionenv.sh`** (r33, r36) - the test-env provisioning helper
  `lib/provision-test-env.sh` under a PATH-mock `podman`: the `PROVISION_PKGS`
  default, manifest-tag determinism + per-major / per-manifest fingerprinting,
  idempotent reuse, build+commit, the repo tolerance (`skip_if_unavailable`), the
  real package-manager stderr surfaced on failure (`PROVISION_LAST_ERR`), and the
  PRE-FLIGHT policy (`provision_prepare_majors`: all majors prepared; a
  non-optional major aborts the run; EL6 tolerated and absent from the sweep).

* **`t022_ssmunavailable.sh`** (r34) - the SSM "unpublished at S3" status: the
  403/404 classifier `ssm_rpm_unavailable` (000/5xx stay transient), the
  version-global `ssm_rpm_url`, the `unavailable` ledger row shape (valid JSON),
  and end-to-end report rendering of the `unavailable` cells via the hermetic
  `--generate-results` path.

* **`t023_probeentitlement.sh`** (r37, r39) - the unified probe's pure layer
  (`lib/probe-common.sh` + the collector emitted by
  `tests/probe-env.sh --facts`): the per-major manager map, the yum
  `repolist enabled` SUBCOMMAND form (yum has no `--enabled`), the EL6 form
  dropping `-q` (EL6's `-q` suppresses the whole repolist table), the
  variable-tolerant repo-id pattern (expanded id vs a literal-`$basearch`
  section header), product-cert tag/id extraction from OID
  `1.3.6.1.4.1.2312.9.1.<id>.4` (mocked `openssl`), the deep-resolve
  (`--downloadonly`) command forms, the 5-column `facts.tsv` row shape, that
  the emitted collector keeps subscription-manager plugins ENABLED, that no
  collector step pipes its exit code into `tail`, `bash -n` validity for all
  three emitted collectors, and that `probe_verdict` still loads.

---

## Suite smoke: `tests/probe-env.sh --smoke`

One command, every major, one sample per tool - the quick health signal
between full matrix sweeps: provisions each target major once, runs the
LATEST version of each install script (awscli / ssm / ena; subset with
`SMOKE_TOOLS="awscli ssm"`) in its test mode, one `--rm` container per
(major, tool), and prints a major x tool verdict table. Ledgers and
RESULTS files are never touched. `ok`, `unsupported` and `unavailable`
are EXPECTED statuses (ENA's anonymous needs-entitlement rides on `ok`);
exit 0 means no unexpected cell. Non-expected cells preserve their full
output under `tests/SMOKE-LOGS-<timestamp>/`. Provisioned test-env images
are removed on every exit path (trap; `KEEP_TEST_IMAGES=1` keeps them) -
this also applies to the three matrix sweeps. Without podman, a
root+chroot fallback (curl-pulled rootfs, best-effort anonymous
provisioning) runs the same samples for sandbox self-verification.

## Entitlement fact-probe (Phase A): `tests/probe-env.sh --facts`

The reproducible collector behind the entitlement re-investigation (a
standalone `tests/probe-entitlement.sh` in r37, unified into the probe as
`--facts` in r39): one run gathers, per major x condition, the
repo/entitlement facts (enabled repos and their defining files,
`/run/secrets` contents, `redhat.repo` pre/post a `makecache` trigger,
product-cert tags, build/install package resolution via a real
`--downloadonly` fetch, CRB/optional enablement attempts, and the
installed subscription-manager package set):

```
tests/probe-env.sh --facts                        # majors 10 9 8 7 6, conds auto+mounts
tests/probe-env.sh --facts --majors "9" --conds auto
tests/probe-env.sh --facts --outdir /tmp/probe --shallow
```

Conditions: `auto` = a PLAIN run (whatever the runtime injects by itself);
`mounts` = the suite's legacy passthrough as the A/B comparison arm - the
`docmounts` arm (added by default on RHUI hosts) probes the whole-directory
recipe from a user-provided AWS-RHUI article (`/etc/yum.repos.d`,
`/etc/pki/rhui`, plugin config dirs) as a hypothesis under test; the
mount set follows the host's repo-access classification (rhsm on
subscription-manager hosts, the RHUI file/cert set on AWS/Azure RHUI hosts;
`MANIFEST.txt` records `repo_access=`). A host-side inventory lands in
`OUTDIR/host/` (repo files, installed RHUI/subscription-manager packages,
certificate metadata only - never private keys), rendered by the analyzer as
`RF0`; on AWS RHUI hosts a read-only cross-major authorization check
(`host/rhui-crossmajor.txt`) probes per-major content URLs with the host's
client certificate used in place, following the mirrorlist body to the
first mirror's `repodata/repomd.xml` (the mirrorlist status alone is
meaningless - it answers 200 even for invalid paths), and `rct cat-cert`
dumps each certificate's content sets (`host/content-sets.txt`). Engine: podman preferred (required for
`mounts` and entitled hosts); on a rootful sandbox without podman it falls
back to a curl-pulled rootfs + chroot (anonymous facts only). On completion
the output directory is auto-packed as `<outdir>.tar.gz` for the analysis
round-trip. Read-only by design: containers are
`--rm` and the only host writes land under the output directory
(`tests/ENTITLEMENT-PROBE-<ts>/`, never committed). Analysis is a separate,
artifact-only step - `tools/analyze-entitlement.sh <outdir>` rebuilds
`ANALYSIS.md` (F1-F7 tables) from the collected raw logs, so any conclusion is
reproducible from the run itself. Known reading notes: EL6 `yum install`
exits 0 on "No package X available" ("Nothing to do"), so resolution verdicts
come from the transaction content, not the step's rc alone; and no collector
step pipes its exit code into `tail` (the r37 collector masked the s06/s12
rc that way - `| tail` findings from that run are unreliable).

---

## Environment probe (opt-in): `--probe-env`

Before a full `--run`, you can probe whether the host + container runtime can
actually exercise each RHEL major:

```
tests/probe-env.sh                 # probes 10 9 8 7 6 (override with OSMAJORS)
tests/probe-env.sh --majors "6"    # just RHEL 6
```

It runs one short-lived container per major and reports common checks - does the
image run here (`exec`; covers pull, arch, and old-userspace glibc/vsyscall),
package manager present, and whether that manager can reach repositories
(`repos`: reachable / no-access [command ran, repos unreachable] / no-cmd /
unknown) - with the subscription-manager plugins ENABLED and no manual mounts,
so the observed state is the auto-injected one (r39 correction; the pre-r39
probe disabled the very plugin that materializes entitled repos) - plus egress
to S3 and EPEL and the per-container `entitlement` observation
(auto-injected = `/run/secrets/redhat.repo` present / anonymous), then a
`verdict` of **ready** / **degraded** (runs but
an egress/repo gap) / **blocked** (image
won't run here). Output goes to the log, a readiness table, and `ENV-PROBE.json`
(git-ignored). The probe never modifies the host.

## RHEL 6 assumptions, and why yum can stall

RHEL 7-10 use public UBI images; **RHEL 6 uses the bare `rhel6/rhel` image**
(non-UBI, amd64-only, on an EOL/ELS-ended distro). For RHEL 6 to be testable the
host must run amd64 and be able to execute glibc-2.12 userspace, and the container
must reach `s3.amazonaws.com` (SSM RPM) and `dl.fedoraproject.org` (EPEL, archive
tree). The bare image also ships the `subscription-manager`/`product-id` yum
plugins: **without an entitlement they try to reach RHSM and hang indefinitely**.
The install scripts therefore disable those two plugins for the container run when
no entitlement certs are present (kept ON when certs are present, since entitled
repos need them) - so `yum` works normally against the pinned EPEL repo and other
reachable repos. The host is never changed.

## Entitlement passthrough (RHSM / RHUI) and platform classification

`--run` can pass the host's repo access into each container so entitled content
(e.g. `kernel-devel`, or DKMS from a base repo) is reachable. The decision lives
in one place - `lib/acquire-rootfs.sh` - and the sweep consumes it (the probe
stopped consuming the mount decision in r39; its readiness checks observe the
plain, auto-injected state instead), so there is no duplicated logic.

`acq_repo_access` classifies the host (multi-signal, `>= 2` cues agree where
possible) into one of:

- **rhsm** - subscription-manager entitlement certs at `/etc/pki/entitlement/*.pem`
  (physical/VM registered, or cloud BYOS). Passthrough is *feasible*.
- **rhui:aws | rhui:azure | rhui:gcp | rhui:other** - cloud Red Hat Update
  Infrastructure, detected from the client RPM (`rh-amazon-rhui-client`,
  `rhui-azure-rhel*`, `google-rhui-client-*`), the repo baseurl host
  (`aws.ce.redhat.com`, `*.microsoft.com`, `googlecloud`), and the platform
  (DMI). Passthrough is *conditional* - RHUI endpoints are reachable only from
  the cloud instance's network, so the run shares host networking and degrades
  with a clear reason if unreachable.
- **oci-ol** - Oracle Cloud's Oracle Linux regional yum (`ociregion`/`ocidomain`,
  `oci.oraclecloud.com`). This is Oracle Linux content, not RHEL, so RHEL
  entitled passthrough is *n/a* (reported for visibility only). OCI does not
  offer a Red Hat RHUI for RHEL; RHEL on OCI is BYOS -> rhsm.
- **none** - anonymous (no mounts added; behaviour unchanged).

For **rhsm** the mount set is the entitlement certs, `/etc/rhsm`, the product
certs, and the subscription-manager-generated `redhat.repo` - the last is what
gives the container the entitled baseurls (UBI ships only the public ubi repos),
so entitled-only packages such as `kernel-devel` become reachable.

With that passthrough in place, the **ENA** build test's entitled path installs
`gcc`, `make`, and `kernel-devel` from the container's own entitled repos, then
compiles `ena.ko` out of tree against that installed kernel-devel tree. This is a
*compile* test: each RHEL major builds against its own kernel headers, independent
of the running host kernel (module LOAD is never attempted in a container - L4), so
the same RHEL 10 host can build-test RHEL 6/7/8/9/10 by running each major's image.
A major reports `build-fail` only if its entitled repos cannot provide kernel-devel
or the pinned driver does not compile on that kernel. SSM (local RPM, repo-free) and
AWS CLI v2 (self-contained S3 zip) are entitlement-independent and unaffected.

`acq_entitlement_mount_args` emits the `-v`/`--network` set. For RHUI it is
*derived from the repo files* (the `sslclientcert`/`sslclientkey`/`sslcacert`/
`gpgkey` paths plus the repo files themselves, `/etc/pki/rhui`, the `amazon-id`
plugin config, and `--network host`), so a new or unknown RHUI provider works as
`rhui:other` with no code change. On an anonymous host the args are empty, so the
sweep is byte-for-byte unchanged. The host is never modified.

`--probe-env` reports `platform` (`physical` / `vm:<hv>` / `cloud:aws|azure|gcp|oci`),
the `repo_access` mode + confidence + matched signals, and the entitled-passthrough
feasibility, in the banner and in `ENV-PROBE.json`.

## Timeouts

Two nested guards (both overridable) keep a stall from ever hanging a run:

- `RUN_TIMEOUT` (default 600s) wraps each whole `podman run`; on expiry the case
  is recorded as a `harness-error` (`reason: "timed out after Ns ..."`) with a
  preserved log, and the sweep continues.
- `PKG_TIMEOUT` (default 300s) bounds each in-container `yum`/`dnf` operation.

Raise both on slow-mirror links (e.g. `PKG_TIMEOUT=360 RUN_TIMEOUT=900`).

## Environment & version dependencies

| Component | Role | Notes |
|:--|:--|:--|
| `bash` | harness + tiers | 4.4+ (developed against 5.2). |
| `shellcheck` | L0 lint gate | pin in CI; `t002` SKIPs if absent. CI severity is `style`. |
| `podman` | L3 acquisition engine (preferred) | not exercised by L0-L2; the curl-only OCI v2 path is the fallback. |
| `curl` + `tar` | L3 acquisition fallback | anonymous OCI v2 pull (no token step). |
| `INSECURE_TLS` | sandbox switch | `1` in a TLS-intercepting sandbox (`--setopt=sslverify=0`); `0` on a trusted host. |

`run-all.sh` prints the live `bash` / `shellcheck` / `podman` versions in its
banner so each run records the environment it ran under.

---

## Recorded baseline (r35)

The full suite is green in the planning sandbox:

```
== bash-rhel-container-testsuite test suite ==
  bash:       GNU bash, version 5.2.21(1)-release
  shellcheck: 0.9.0
  podman:     (hermetic L0-L2 need none; t021 uses a PATH-mock podman)
---- t001_parse.sh ----            ## RESULT pass=45 fail=0 skip=0
---- t002_shellcheck.sh ----       ## RESULT pass=45 fail=0 skip=0
---- t003_acquireunit.sh ----      ## RESULT pass=33 fail=0 skip=0
---- t004_pkgmgrdetect.sh ----     ## RESULT pass=19 fail=0 skip=0
---- t005_entitlementdetect.sh ----## RESULT pass=8  fail=0 skip=0
---- t006_initmodemap.sh ----      ## RESULT pass=7  fail=0 skip=0
---- t007_epelresolve.sh ----      ## RESULT pass=34 fail=0 skip=0
---- t008_awscliverdict.sh ----    ## RESULT pass=45 fail=0 skip=0
---- t009_ssmverdict.sh ----       ## RESULT pass=27 fail=0 skip=0
---- t010_enaverdict.sh ----       ## RESULT pass=48 fail=0 skip=0
---- t011_enaverify.sh ----        ## RESULT pass=17 fail=0 skip=0
---- t012_osprofile.sh ----        ## RESULT pass=58 fail=0 skip=0
---- t013_toolcontract.sh ----     ## RESULT pass=18 fail=0 skip=0
---- t014_pkgavail.sh ----         ## RESULT pass=33 fail=0 skip=0
---- t015_installpins.sh ----      ## RESULT pass=17 fail=0 skip=0
---- t016_installintrospect.sh ----## RESULT pass=18 fail=0 skip=0
---- t017_probeverdict.sh ----     ## RESULT pass=8  fail=0 skip=0
---- t018_repoaccess.sh ----       ## RESULT pass=14 fail=0 skip=0
---- t019_enabuilddeps.sh ----     ## RESULT pass=8  fail=0 skip=0
---- t020_helperidentity.sh ----   ## RESULT pass=8  fail=0 skip=0
---- t021_provisionenv.sh ----     ## RESULT pass=19 fail=0 skip=0
---- t022_ssmunavailable.sh ----   ## RESULT pass=17 fail=0 skip=0
SUITE: 546 passed, 0 skipped, 0 failed  (22 tiers, 0 tier-failure(s))
```

**L0 fixed count = 45 shell files** (every `.sh` in the project, incl. the 3 root
`install-aws_*.sh`), each `bash -n`-clean and ShellCheck-clean at **default
severity and `-S style`** (t002 passes `-P` so the gate is CWD-independent,
r29): the 6 libraries, the 22 `tests/t001`-`t022` tiers, the harness
(`run-all.sh`, `probe-env.sh`, `tests/lib/*`), the three per-tool folders
(lister + matrix each, plus the ENA verifier), the coverage generator, and the
contract checker. Since r28 every file carries the Layer-1 five-section header
banner and the production scripts run `set -euo pipefail` (the self-test
harness stays `-uo` by design; SPEC Part A A.5 / D.8).

**Residuals (run on CI / a container-egress / entitled / Nitro host):**
- the live pull (L3) is not exercisable in the sandbox (no podman; the quay blob
  CDN is off-allowlist); the curl-only pull *sequence* is unit-tested in `t003`.
- the live AWS CLI install matrix (`--run`) fills its empirical column; the glibc
  model and `--generate-results` are hermetic and were run this session.
- the live SSM install matrix (`--run`, both init modes) fills its empirical
  column; the init-mode grid + compliance model are hermetic.
- the live ENA build (`--run`) needs an **entitled** host; module load is **L4**.
  The E2' grid, the verifier gates, and `--generate-results` are hermetic.

All seven implementation phases are complete; the tool contract is a suite-failing
gate, so a non-conformant tool #2 cannot land silently.
