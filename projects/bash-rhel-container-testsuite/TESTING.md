---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-07-01
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

See [`SPEC.md`](./SPEC.md) section 6 for the authoritative table. In short:

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

## Running the suite

```bash
# from the project root
bash tests/run-all.sh
```

A green run ends with, e.g.:

```
SUITE: 129 passed, 0 skipped, 0 failed  (7 tiers, 0 tier-failure(s))
```

Run a single tier directly (its exit status reflects pass/fail):

```bash
bash tests/t001_parse.sh        # L0 parse
bash tests/t003_acquireunit.sh  # L1 acquisition unit
bash tests/t007_epelresolve.sh  # L1 EPEL resolution unit
```

The L3 integration matrices are **not** invoked by `run-all.sh`; run them
explicitly when container egress is available (added in Phases 3-5):

```bash
# example shape (Phase 3+)
bash tests/aws_awscli-v2/run-awscli-installtest-matrix.sh
```

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
* **`t010_enaverdict.sh`** (Phase 5) - the ENA build-test matrix's pure helpers
  (`ena_ge`, `ena_kdevel_repo`, `ena_in_scope`, `ena_build_plan`, `ena_verdict`,
  `ena_load_tier`) and the matrix/lister `ena_ge` reuse-by-copy. Covers the E2'
  entitlement verdict (entitled -> ok/build-fail; anonymous -> needs-entitlement;
  load -> L4).
* **`t011_enaverify.sh`** (Phase 5) - the read-only verifier's load-readiness
  gates `ena_vermagic_verdict` (L4a) and `ena_symbols_verdict` (L4b CRC/kABI),
  loaded with `ENA_LIB_ONLY=1` so only the pure helpers run.
* **`t012_osprofile.sh`** (Phase 6) - every `lib/os-profile.sh` helper across all
  five majors, plus the cross-consistency invariants that make the profile a
  single source of truth: `osp_image == acq_image_for_major`,
  `osp_pull_tag == acq_tag_for_major`, `osp_epel_is_live` inverse of
  `epel_is_archive`, and `osp_kdevel_repo == ena_kdevel_repo`.
* **`t013_toolcontract.sh`** (Phase 7) - L2: loads `contract_dir_missing` from
  `tests/conformance/check-tool-contract.sh` (`CONTRACT_LIB_ONLY=1`), asserts the
  three shipped tools conform to the §10 (a-e) contract, that a synthetic
  incomplete dir reports its gaps, and that the checker exits 0.
* **`t014_pkgavail.sh`** (Phase 7) - the `lib/pkg-availability.sh` classification
  canon (`pkgavail_class`, `pkgavail_needs_entitlement`, `pkgavail_anonymous_status`,
  `pkgavail_over_network`, `pkgavail_tool_source`) incl. the end-to-end
  source -> class -> anonymous-status chain per tool.

---

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

## Recorded baseline (Phase 7, r07)

The full suite is green in the planning sandbox:

```
== bash-rhel-container-testsuite test suite ==
  bash:       GNU bash, version 5.2.21(1)-release
  shellcheck: 0.9.0
  podman:     (not installed - L3 uses the curl-only OCI fallback or SKIP)
---- t001_parse.sh ----            ## RESULT pass=32 fail=0 skip=0
---- t002_shellcheck.sh ----       ## RESULT pass=32 fail=0 skip=0
---- t003_acquireunit.sh ----      ## RESULT pass=33 fail=0 skip=0
---- t004_pkgmgrdetect.sh ----     ## RESULT pass=19 fail=0 skip=0
---- t005_entitlementdetect.sh ----## RESULT pass=8  fail=0 skip=0
---- t006_initmodemap.sh ----      ## RESULT pass=7  fail=0 skip=0
---- t007_epelresolve.sh ----      ## RESULT pass=34 fail=0 skip=0
---- t008_awscliverdict.sh ----    ## RESULT pass=45 fail=0 skip=0
---- t009_ssmverdict.sh ----       ## RESULT pass=27 fail=0 skip=0
---- t010_enaverdict.sh ----       ## RESULT pass=27 fail=0 skip=0
---- t011_enaverify.sh ----        ## RESULT pass=17 fail=0 skip=0
---- t012_osprofile.sh ----        ## RESULT pass=58 fail=0 skip=0
---- t013_toolcontract.sh ----     ## RESULT pass=13 fail=0 skip=0
---- t014_pkgavail.sh ----         ## RESULT pass=33 fail=0 skip=0
SUITE: 385 passed, 0 skipped, 0 failed  (14 tiers, 0 tier-failure(s))
```

**L0 fixed count = 32 shell files**, each `bash -n`-clean and
ShellCheck-`style`-clean: the 6 Phase-1 files, the 5 libraries
(`lib/{acquire-rootfs,ubi-pkgmgr,epel,os-profile,pkg-availability}.sh`), the 5
Phase-2 unit tiers (`tests/t003`-`t007`), the seven verdict/verify/profile/contract
tiers (`tests/t008`-`t014`), the two Phase-3 AWS CLI scripts, the two Phase-4 SSM
scripts, the three Phase-5 ENA scripts, the Phase-6 coverage generator, and the
Phase-7 contract checker (`tests/conformance/check-tool-contract.sh`).

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
