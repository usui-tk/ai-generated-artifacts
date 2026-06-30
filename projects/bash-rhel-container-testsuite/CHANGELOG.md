# Changelog

All notable changes to **bash-rhel-container-testsuite** are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project versions by **revision tag (`rNN`)** to match the sibling projects
in `ai-generated-artifacts`.

## [Unreleased]

### Planned (per the design plan sec 16)
- **Phase 7 - Generalization:** tool-agnostic contract + classification for tool #2.

## [r06] - 2026-07-01 - Phase 6: EOL / constrained majors

Phase 6 makes the EOL/constrained-major dimension first-class. The facts the
design plan measured for RHEL 7 (frozen; `ubi7/ubi-init` pulled by **fixed tag
`7.9-88`** because the floating-tag signature is rejected; yum; anon repos incl
RHSCL) and RHEL 6 (Tier C: **no anonymous repo**; entitled `rhel-6-server-rpms`
passes through; EPEL **archive-only**, OL6-style) - previously scattered across
the acquisition libraries and the ENA matrix - are consolidated into one canon.

### Added
- `lib/os-profile.sh` - the canonical per-major OS profile (pure, sourceable):
  `osp_tier`, `osp_image`, `osp_pkgmgr`, `osp_pull_tag`, `osp_pull_constraint`,
  `osp_anon_repos`, `osp_has_anon_repo`, `osp_entitled_repo`, `osp_kdevel_repo`,
  `osp_lifecycle`, `osp_epel_status`, `osp_epel_is_live`. Tiers A (10/9/8) /
  B (7) / C (6).
- `tests/t012_osprofile.sh` - L1 unit over every profile helper **and** the
  cross-consistency invariants that make it a single source of truth:
  `osp_image == acq_image_for_major`, `osp_pull_tag == acq_tag_for_major`,
  `osp_epel_is_live` is the inverse of `epel_is_archive`, and
  `osp_kdevel_repo == ena_kdevel_repo`. 58 assertions.
- `tests/os-coverage/generate-os-coverage.sh` + `RESULTS-coverage.md` - a
  deterministic, hermetic render of the design plan sec 6 coverage matrix,
  derived purely from the profile canon (never hand-edited).

### Verified
- Full suite green: **12 tiers, 331 passed, 0 skipped, 0 failed**. L0 covers
  **28 shell files**; `lib/os-profile.sh`, the tier, and the generator are
  ShellCheck-`style`-clean.
- The cross-consistency asserts guarantee the scattered per-fact maps cannot
  drift from `lib/os-profile.sh`; this canon is the basis for Phase 7
  generalization.

## [r05] - 2026-07-01 - Phase 5: AWS ENA driver (E2')

The third per-tool matrix, `aws_ena-driver` - the **entitlement-gated build** tool.
Unlike AWS CLI (glibc) and SSM (glibc + init_mode), the ENA gate is **entitlement**:
building `ena.ko` needs kernel-devel + gcc + make, available only from the entitled
repos. The driver is compiled out of tree against the installed kernel-devel headers
(`make -C /usr/src/kernels/<kver> M=<src> modules`), independent of the host kernel,
with all Oracle UEK handling removed. Module load is always **L4**.

### Added
- `tests/aws_ena-driver/list-ena-releases.sh` (a) - `git ls-remote --tags
  amzn/amzn-drivers`, filters `ena_linux_<X.Y.Z>`, emits a deterministic
  `ena-driver-releases.json` (**70** versions; newest 2.17.0).
- `tests/aws_ena-driver/run-ena-buildtest-matrix.sh` (b, d) - pure helpers
  (`ena_ge`, `ena_kdevel_repo`, `ena_in_scope`, `ena_build_plan`, `ena_verdict`,
  `ena_load_tier`), a `--run` L3 build loop (acquire entitled rootfs ->
  kernel-devel/gcc/make -> fetch source -> build -> record), and
  `--generate-results`. The E2' verdict: entitled -> `ok`/`build-fail`;
  anonymous -> `needs-entitlement`; load -> `L4`.
- `tests/aws_ena-driver/verify-ena-buildresults.sh` - a standalone READ-ONLY
  load-readiness verifier (build -> verify pass) with pure gates
  `ena_vermagic_verdict` (L4a) and `ena_symbols_verdict` (L4b, CRC/kABI).
- `tests/aws_ena-driver/buildtest-ledger.json` (c) - schema'd empirical ledger
  (`results: []` until a live `--run`).
- `tests/aws_ena-driver/RESULTS-rhel{6,7,8,9,10}.md` (d) - generated: the
  entitlement grid + the per-major kernel-devel repo (7/6 server, 8 baseos, 9/10
  appstream) + per-version expectation. Empirical = pending (L3).
- `tests/t010_enaverdict.sh` (e) - L1 unit over the matrix pure helpers + the
  matrix/lister `ena_ge` reuse-by-copy. 27 assertions.
- `tests/t011_enaverify.sh` (e) - L1 unit over the verifier's `ena_vermagic_verdict`
  and `ena_symbols_verdict` gates. 17 assertions.

### Removed
- `tests/aws_ena-driver/.gitkeep` (directory now carries the matrix artifacts).

### Verified
- Full suite green: **11 tiers, 267 passed, 0 skipped, 0 failed**. L0 covers
  **25 shell files**; every ENA script and tier is ShellCheck-`style`-clean.
- `ena-driver-releases.json` and the five `RESULTS-rhel<N>.md` were produced by
  the real tools this session (`git ls-remote` to github.com).

### Notes
- **Live build (L3) needs an entitled container-egress host** (no podman /
  entitlement in the sandbox); module load is **L4** (Nitro hardware). Tracked as
  R8. The optional DKMS path is EPEL-only (`lib/epel.sh`).

## [r04] - 2026-07-01 - Phase 4: AWS SSM Agent

The second per-tool matrix, `aws_ssm-agent` - the **init-sensitive** tool. Its two
axes are **glibc** (install) and **init_mode** (service). This is where Phase 2's
`acq_init_run_args` (none/systemd) is first wired into a matrix. Pure logic and
report generation are hermetic; the live container install is L3 (CI / egress host).

### Added
- `tests/aws_ssm-agent/list-ssm-releases.sh` (a) - `git ls-remote --tags
  aws/amazon-ssm-agent`, deterministic `ssm-releases.json` (**207** versions; the
  S3 RPM URL per version; `ge_min` against the AWS floor 3.3.3598.0). The go.mod
  -> min-kernel proxy is dropped (a container shares the host kernel).
- `tests/aws_ssm-agent/run-ssm-installtest-matrix.sh` (b, d) - pure helpers
  (`ssm_ge`, `rhel_glibc`, `ssm_in_scope`, `ssm_compliance`, `ssm_init_outcome`,
  `ssm_verdict`), a `--run` L3 loop that acquires init-mode-aware refs via
  `acq_init_run_args` then installs the RPM / smokes `-version` / (systemd)
  enables+starts the unit, and `--generate-results`.
- `tests/aws_ssm-agent/ssm-installtest-ledger.json` (c) - schema'd empirical
  ledger (`results: []` until a live `--run`).
- `tests/aws_ssm-agent/RESULTS-rhel{6,7,8,9,10}.md` (d) - generated: the
  init_mode grid (none -> version-only; systemd -> service-capable) and the
  feature-compliance headline (newest 3.3.4793.0 -> **compliant-capable** on every
  major; 11 in-scope versions >= the floor). Empirical = pending (L3).
- `tests/t009_ssmverdict.sh` (e) - L1 unit over every pure helper plus the
  matrix/lister `ssm_ge` reuse-by-copy. 27 assertions.

### Removed
- `tests/aws_ssm-agent/.gitkeep` (directory now carries the matrix artifacts).

### Verified
- Full suite green: **9 tiers, 213 passed, 0 skipped, 0 failed**. L0 covers
  **20 shell files**; the SSM lister, matrix, and tier are ShellCheck-`style`-clean.
- `ssm-releases.json` and the five `RESULTS-rhel<N>.md` were produced by the real
  tools this session (`git ls-remote` to github.com).

### Notes
- **Live install (L3) deferred to CI / a container-egress host** (no podman; the
  S3 RPM host and quay are off-allowlist in the sandbox). Tracked as R7.

## [r03] - 2026-07-01 - Phase 3: AWS CLI v2

The first per-tool matrix (framework steps a-e) for `aws_awscli-v2`. The dominant
axis is **glibc** only (self-contained bundle). Pure logic and report generation
are verified hermetically; the live container install is L3 (CI / egress host).

### Added
- `tests/aws_awscli-v2/list-awscli-releases.sh` (a) - collects the AWS CLI v2
  release list via `git ls-remote --tags aws/aws-cli` (auth-free), computes each
  version's `min_glibc` (reuse-by-copy of the matrix helpers), emits a
  deterministic `awscli-releases.json`. Optional per-zip HEAD probe.
- `tests/aws_awscli-v2/awscli-releases.json` - generated snapshot (**927** v2
  versions; boundary 2.17.49->2.5, 2.17.50->2.17).
- `tests/aws_awscli-v2/run-awscli-installtest-matrix.sh` (b, d) - the matrix:
  pure helpers (`awscli_ge`, `awscli_min_glibc`, `awscli_in_scope`,
  `awscli_verdict`, `python_eol`, `rhel_glibc`, `awscli_band`, `awscli_expected`),
  a `--run` L3 install-test loop (acquire -> install bundle -> smoke -> ledger),
  and `--generate-results` that writes `RESULTS-rhel<N>.md` from the release list
  and the measured per-major glibc.
- `tests/aws_awscli-v2/awscli-installtest-ledger.json` (c) - schema'd empirical
  ledger; `results: []` until a live `--run` populates it.
- `tests/aws_awscli-v2/RESULTS-rhel{6,7,8,9,10}.md` (d) - generated. The glibc
  model resolves: RHEL 6 (2.12) -> current band **glibc-too-old**, legacy band
  runs; RHEL 7 (2.17, at the floor) / 8 / 9 / 10 -> **runs** for both bands
  (435 current + 492 legacy = 927). Empirical column = pending (filled by L3).
- `tests/t008_awscliverdict.sh` (e) - L1 unit over every pure helper plus the
  reuse-by-copy consistency (lister vs matrix). 45 assertions.

### Removed
- `tests/aws_awscli-v2/.gitkeep` (directory now carries the matrix artifacts).

### Verified
- Full suite green: **8 tiers, 180 passed, 0 skipped, 0 failed**. L0 now covers
  **17 shell files**; the lister and matrix are ShellCheck-`style`-clean (markdown
  backticks emitted as `\140` in printf formats to keep the gate strict, no
  blanket SC2016 disable).
- `awscli-releases.json` and the five `RESULTS-rhel<N>.md` were produced by the
  real tools in this session (network: `git ls-remote` to github.com).

### Notes
- **Live install (L3) deferred to CI / a container-egress host** (no podman; the
  AWS bundle CDN and quay are off-allowlist in the sandbox). `--generate-results`
  is fully hermetic; `--run` records the empirical column where egress exists.
  Tracked as the Phase-3 tail (analogous to the Phase-2 live-pull tail).

## [r02] - 2026-07-01 - Phase 2: Acquisition

Acquisition libraries and their hermetic unit tiers. All logic is unit-tested
off-network; the actual live pulls (podman and curl-only OCI) are L3 and run in
CI / on a container-egress host (see *Notes*).

### Added
- `lib/ubi-pkgmgr.sh` - package-manager detection (`dnf -> microdnf -> yum ->
  none`), the makecache trigger / repolist / availability command builders, and
  `pkgmgr_is_available` using `dnf list --available` / `repoquery
  --latest-limit=1` (never a bare `repoquery`, per the sec 3.4 artifact).
- `lib/acquire-rootfs.sh` - pure helpers (image/tag/ref maps with the RHEL 7
  fixed-tag `7.9-88`, `acq_select_amd64_digest`, OCI v2 URL builders, init-mode
  invocation args, entitlement classification by the `rhel-*` prefix) plus the
  I/O wrappers: podman pull, the curl-only anonymous OCI v2 fallback (no token
  step; `INSECURE_TLS` switch), and the 3-step entitlement detector. Sources
  `ubi-pkgmgr.sh`.
- `lib/epel.sh` - `dl.fedoraproject.org`-pinned EPEL (method B): baseurl / gpgkey
  resolvers per major, EPEL 10 minor resolution with a rolling fallback, the
  RHEL 6 archive special-case, the pinned `.repo` body emitter, and mockable
  import/write/cleanup wrappers.
- Unit tiers: `t003_acquireunit.sh` (acquisition pure helpers + a fully mocked
  curl-only pull sequence), `t004_pkgmgrdetect.sh` (detection ladder via a
  PATH-restricted shadow bin + availability mocks), `t005_entitlementdetect.sh`
  (the 3-step flow, incl. the "no premature grep before the trigger" invariant),
  `t006_initmodemap.sh` (init-mode arg mapping), `t007_epelresolve.sh` (EPEL
  resolution incl. the 10-minor HEAD-probe branch, stubbed).

### Removed
- `lib/.gitkeep` (the directory now carries real libraries).

### Verified
- Full suite green in the planning sandbox: **7 tiers, 129 passed, 0 skipped,
  0 failed**. L0 now covers **14 shell files** (6 + 3 libs + 5 tiers), each
  `bash -n`-clean and ShellCheck-`style`-clean.
- New L1 coverage: t003=33, t004=19, t005=8, t006=7, t007=34 assertions.

### Notes
- **Live pull (L3) is deferred to CI / a container-egress host.** The sandbox has
  no podman and cannot reach the quay blob CDN, so both pull paths are validated
  *hermetically* (the curl-only path end-to-end with curl/tar mocked); the real
  pulls run where `*.quay.io` is reachable. This is the only residual of the
  Phase-2 exit criterion and is tracked as the live-pull tail.
- One documented inline exemption was added: `# shellcheck disable=SC2317` on the
  two `epel_head_ok` test stubs in `t007` (indirectly invoked; SC2317's
  reachability heuristic can't see the indirection).

## [r01] - 2026-07-01 - Phase 1: Scaffolding

Initial project scaffold. Phase 0 (feasibility) was completed in the planning
session and is recorded in the design plan; this revision lands the
directory skeleton, the ported test harness, and the L0 gate.

### Added
- Project skeleton under `projects/bash-rhel-container-testsuite/` matching the
  directory layout in the design plan sec 13 (`lib/`, `tests/lib/`,
  `tests/aws_awscli-v2/`, `tests/aws_ssm-agent/`, `tests/aws_ena-driver/`).
- Test harness ported unchanged from `bash-ol-aws-ami-builder`
  (the design plan sec 15): `tests/lib/assert.sh`, `tests/lib/mock.sh`,
  `tests/lib/heredoc.sh`.
- `tests/run-all.sh` - single-entry L0-L2 aggregating runner; banner reports
  `bash` / `shellcheck` / `podman` (acquisition engine) versions.
- L0 tiers: `tests/t001_parse.sh` (`bash -n` over every `.sh`; heredoc-body
  sweep scaffolded with an empty allowlist) and `tests/t002_shellcheck.sh`
  (ShellCheck at canonical severity `style`, asserting zero findings per file).
- `.shellcheckrc` - `external-sources=true`, `source-path=SCRIPTDIR`, no global
  `disable=`.
- Documentation: `README.md` / `README.ja.md` (bilingual, kept in sync),
  `SPEC.md`, `TESTING.md`, this `CHANGELOG.md`, and the finalized
  the design plan.

### Verified
- L0 gate green in the planning sandbox: **2 tiers, 12 passed, 0 skipped,
  0 failed** (6 shell files, each `bash -n`-clean and ShellCheck-`style`-clean).
  This is the recorded Phase-1 fixed count.

### Notes
- The acquisition libraries (`lib/acquire-rootfs.sh`, `lib/ubi-pkgmgr.sh`,
  `lib/epel.sh`), the root install scripts (`install-awscli.sh`,
  `install-ssm-agent.sh`, `install-ena-driver.sh`), and the per-tool test
  folders are intentionally **not** present yet - they arrive in Phases 2-5. The
  `lib/` and `tests/aws_*/` directories carry a `.gitkeep` so the planned layout
  is visible.
