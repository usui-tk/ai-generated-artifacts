---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.1.0
  rendered: 2026-07-02
---
# Changelog

All notable changes to **bash-rhel-container-testsuite** are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project versions by **revision tag (`rNN`)** to match the sibling projects
in `ai-generated-artifacts`.

## [Unreleased]

## [r50] - 2026-07-04 - fix: measure %posttrans outcomes + EL6 SSM track-record pin

### Fixed
- **The EL6 SSM "unsupported" classification (r48/r49) was an
  over-classification** - superseded by measurement. The %posttrans
  scriptlet failure is an artifact of init-LESS containers/chroots (it only
  registers the service); the rpm's files land and the binaries RUN on EL6
  (measured: 3.0.1479.0 installed+ran; the 3.3.4793.0 binary also runs).
  `install_rpm` now MEASURES instead of assuming: on a
  POSTTRANS/"Nothing to do" failure it checks whether the requested version
  actually installed - if yes, it continues with a tolerated warning
  (recorded in the ok-result's `reason`) and lets the run check judge; only
  a landed-but-not-running EL6 binary or a genuinely absent package
  classifies as `unsupported`. (yum prints "does not update installed
  package" on STDOUT, so the stderr signature match includes
  "Nothing to do"; the rpm version check is the real guard.)

### Added
- **Smoke track-record pin** (`pe_smoke_pin`, unit-tested; user decision):
  ssm/EL6 samples **3.0.1479.0** - the version the user verified on real
  RHEL 6 (with a live upstart, i.e. including service registration). It is
  below the in-scope/compliance floor (3.3.3598.0), so the verdict table
  marks pinned cells with `*` and a footnote. Pins affect ONLY smoke
  sampling, never the matrices' in-scope filtering.

## [r49] - 2026-07-04 - fix: ENA source-locate bug + awscli glibc gate + per-major smoke sampling

### Fixed
- **Every real ENA build failed on a latent source-LOCATE bug, not make**:
  the tarball root is `amzn-drivers-<tag>/`, putting `kernel/linux/ena` at
  depth 4, and `fetch_src`'s `find -maxdepth 3` never found it (verified by
  reproducing the tarball layout). The legacy mounts had kept entitled
  builds from ever running, so the bug stayed hidden until the second smoke
  E2E. Depth fixed (5, with headroom) and fetch/extract/locate failures now
  report distinctly instead of masquerading as
  "build failed (make ...)".
- **awscli gained the missing glibc gate**: the bundle's measured minimum
  is compared against the OS glibc BEFORE installing; below-minimum is
  `unsupported` (measured platform incompatibility). This was the EL6
  "unexpected error (line 227)" - `aws --version` failing under
  `pipefail` into the ERR trap because no gate existed. Verified in an el6
  chroot: 2.35.14 -> `unsupported`, 2.17.49 -> `ok` (installs and runs).

### Changed
- **Smoke samples a per-major COMPATIBLE version** (`pe_smoke_pick`,
  unit-tested; user requirement - the smoke goal is script health, so each
  cell should be able to complete normally): the newest version whose
  per-version constraints the major satisfies (today: `min_glibc` vs the
  measured per-major glibc). RHEL6 therefore samples awscli 2.17.49 (ok)
  instead of the latest (unsupported). SSM has no per-version constraint
  data and EL6 was measured incompatible across the in-scope range (floor
  3.3.3598.0 shows the same installs-but-does-not-update pattern as
  3.3.4793.0), so its EL6 cell correctly reports `unsupported`.
- **Smoke packs its failure logs** as `SMOKE-LOGS-<ts>.tar.gz` on
  completion (user requirement, mirroring `--facts`).

## [r48] - 2026-07-04 - fix: first smoke E2E findings + guaranteed test-image cleanup + smoke hardening

### Fixed
- **awscli failed on every major because the provisioning manifest lacked
  unzip** (the image tag `...-970560763` is the fingerprint of the old
  `gawk`-only manifest). `PROVISION_PKGS` now defaults to `gawk unzip tar`;
  the fingerprint change auto-rebuilds stale images. Verified in a ubi9
  chroot: awscli 2.35.14 reaches `status=ok`.
- **ENA build deps gained `elfutils-libelf-devel`** - EL8+ kbuild
  (objtool/resolve_btfids) needs libelf for external module builds; the
  probe's measured build set already included it. (Entitled-build
  confirmation needs the Step 5 rerun; smoke now preserves make logs.)
- **EL6 x latest SSM agent is now classified `unsupported`, not `fail`**:
  measured (smoke E2E + el6 chroot repro) - the 3.3.x rpm installs its files
  but its `%posttrans` scriptlet requires systemd, impossible on
  EL6/upstart. First-ever empirical EL6 SSM data point (RESULTS-rhel6 was
  "not yet run").

### Added
- **Guaranteed test-image cleanup** (user requirement):
  `provision_cleanup_images` removes every `rhel-testsuite-provisioned:*`
  image, wired via `trap ... EXIT` into the three matrices and `--smoke`,
  so normal completion, failures and interrupts all clean up. Base images
  (UBI/RHEL) are untouched; `KEEP_TEST_IMAGES=1` opts out.
- **Smoke hardening**: non-expected cells save the full container/chroot
  output under `SMOKE-LOGS-<ts>/`; `unsupported` / `unavailable` (and
  ENA's needs-entitlement, which rides on `ok`) count as EXPECTED, not
  failures; and a root+chroot fallback engine lets a podman-less sandbox
  self-verify smoke behavior before user evaluation (used for this
  release: RHEL9 all-ok and EL6 ssm=unsupported were verified in-sandbox).

## [r47] - 2026-07-04 - feat: `--smoke` - one command, every major, one sample per tool

### Added
- **`tests/probe-env.sh --smoke`** (user requirement): a quick suite-health
  signal - provision every target major once, then run the LATEST version of
  each tool's install script (awscli / ssm / ena, override with
  `SMOKE_TOOLS`) in test mode, one `--rm` container per (major, tool),
  and print a major x tool verdict table. Reuses the tested pipeline
  (`provision_prepare_majors` + the install scripts' `[result]` contract)
  and never touches ledgers/RESULTS files. Exit 0 only if every cell is
  `ok`. ENA's entitlement declaration follows the host mode (rhsm ->
  entitled, otherwise anonymous -> the needs-entitlement path). Helpers
  (`pe_smoke_latest`, `pe_result_field`) are unit-covered in t023.

## [r46] - 2026-07-04 - fix: containers run PLAIN - the harmful rhsm mounts are gone (Step 4, D-S1..S6)

### Changed
- **`acq_entitlement_mount_args` returns nothing for every mode (D-S1/D-S2).**
  rhsm: the host-file mounts were measured actively harmful on 2026-07-04
  (wrong-major repos in 8/9, sslclientcert Permission denied even same-major,
  per-container generation blocked, EL7's auto-entitled repo lost) while
  plain containers get correct per-major entitled repos on every major 6-10
  via podman's auto-injection. rhui: the legacy mounts were measured
  non-functional; the entitled RHUI container path is PENDING (user
  decision) and RHUI hosts run containers plain (needs-entitlement). The
  three matrices now log the host's repo-access mode instead of mount args.
- **Provisioning no longer masks repo failures (D-S3)**: r36's
  `*.skip_if_unavailable=1` papered over the wrong-major mounts and is
  removed with them; `t021` pins its absence.
- **Plugin neutralization is kept as a DEFENSIVE measure (D-S4)** with its
  rationale corrected in-code: the historically observed RHSM-contact hang
  did not reproduce in the probe runs (EL6 included).
- **`acq_entitlement_feasible` removed (D-S6)** - its mounting premise was
  disproved; host classification lives in `acq_repo_access`.
  `acq_detect_entitlement` stays unit-covered but is marked as not wired
  into the run flow (kept for the pending RHUI per-container work).

## [r45] - 2026-07-04 - fix: cross-major check sends the RHUI identity headers (403 mystery solved)

### Fixed
- **The 403-for-everything mystery is solved by the captured plugin source.**
  `amazon-id.py` (r43 capture) shows AWS RHUI authorization is TLS client
  cert AND the SIGNED EC2 instance-identity document, attached to every
  request as `X-RHUI-ID` / `X-RHUI-SIGNATURE` (urlsafe base64); the plugin
  also substitutes the literal `REGION` in repo URLs from that document.
  The cross-major check now replicates exactly that (`pc_b64url`,
  unit-tested against python's `urlsafe_b64encode`), and records whether
  the identity headers were obtainable. Fourth-round verdicts recorded in
  passing: the article-recipe `docmounts` arm does NOT work as written
  (plugin CODE is not under `/etc/dnf/plugins`, so REGION stays literal),
  and `/etc/dnf/plugins` carries config only.

## [r44] - 2026-07-04 - feat: `docmounts` condition - the AWS-RHUI article recipe as an A/B/C arm

### Added
- **`docmounts` probe condition**: the mount set from a user-provided
  AWS-RHUI article (whole `/etc/yum.repos.d` + `/etc/pki/rhui` + the
  `/etc/dnf/plugins` and `/etc/yum/pluginconf.d` CONFIG dirs, all `:ro`) as
  its own `--facts` arm. The article claims this makes RHUI repos usable
  inside UBI containers; our r41/r42 measurements saw literal-`REGION` DNS
  failures and repomd 403 with a narrower mount set - so the claim is
  treated as a hypothesis and probed side by side. On RHUI hosts the
  DEFAULT condition set expands to `auto mounts docmounts` (an explicit
  `--conds` always wins); the chroot fallback reports `requires-podman`
  for every non-`auto` condition.

## [r43] - 2026-07-04 - feat: capture the RHUI client implementation (authorization is server-side)

### Added
- **RHUI client implementation capture** (`host/rhui-client-files-*.txt`,
  `host/rhui-client-src/`, `host/dnf-vars.txt`): the client package's file
  list, its dnf plugin / config / repo / vars sources, and the host's dnf
  vars. Code and config only - no secrets. Motivation, from the 2026-07-04
  third AWS round: `rct cat-cert` shows the AWS RHUI client certificates are
  content-set-LESS identity certificates (authorization is SERVER-side, not
  in-cert), and the repomd-layer check returned 403 for every path
  INCLUDING the host's own major - so whatever dnf sends beyond the bare
  TLS client certificate must live in this client machinery, and reading it
  is the prerequisite for a correct authorization probe.

## [r42] - 2026-07-04 - fix: RHUI authorization probed at the repomd layer + certificate content sets

### Fixed
- **The r41 cross-major check measured the wrong layer.** The AWS RHUI
  mirrorlist endpoint answers 200 regardless of path validity or
  authorization (measured 2026-07-04: even the `rhel99` control got 200), so
  its status proves nothing. The check now follows the mirrorlist BODY to
  the first real mirror and GETs `repodata/repomd.xml` with the client
  certificate - the layer where authorization is enforced. Both statuses
  and the first mirror URL are recorded per major.

### Added
- **Certificate content sets** (`host/content-sets.txt`): `rct cat-cert`
  (ships with subscription-manager) decodes each RHUI product / entitlement
  certificate's content-set extension into readable authorized paths - the
  AUTHORITATIVE authorization list, independent of any network probe. Text
  only; no key material. Rendered inside `RF0`.

## [r41] - 2026-07-04 - feat: RHUI cross-major authorization check + auto-packed probe output

### Added
- **RHUI cross-major authorization fact** (`host/rhui-crossmajor.txt`, AWS
  RHUI hosts only): read-only HTTPS status checks of per-major RHUI content
  URLs synthesized from the host's own `redhat-rhui.repo` baseos template
  (`pc_rhui_major_url`, unit-tested), using the host's client cert/key IN
  PLACE (never copied), REGION resolved via IMDS(v2 with v1 fallback), and
  `rhel99` as the expected-non-200 control. This answers the Step 4 design
  question: does one host's RHUI client certificate authorize OTHER majors'
  content paths? The analyzer renders it inside `RF0`. Background fact from
  the 2026-07-04 AWS run: the mirrorlist hostname carries a LITERAL `REGION`
  token that only the host-side RHUI client machinery resolves, so mounted
  host repo files cannot work in containers as-is (DNS failure) even before
  any major or certificate question.
- **`--facts` auto-packs its output**: on completion the probe creates
  `<outdir>.tar.gz` next to the output directory and logs it, so the
  round-trip attachment no longer needs manual zipping.

## [r40] - 2026-07-04 - feat: RHUI-aware fact probe (support-matrix grounding)

### Changed
- **`--facts` probes RHUI hosts as a first-class environment.** The `mounts`
  A/B arm now selects the legacy mount set by the host's repo-access
  classification (`acq_repo_access`): rhsm on subscription-manager hosts,
  the RHUI repo-file/cert set on AWS/Azure RHUI hosts (previously hardcoded
  to rhsm). `MANIFEST.txt` records the classification (`repo_access=`).

### Added
- **Host-side inventory** (`OUTDIR/host/`): repo-access classification, OS,
  installed subscription-manager / RHUI client packages, the host's
  `/etc/yum.repos.d/*.repo` files, and certificate METADATA only
  (subject/issuer/dates; private keys and PEM bodies are deliberately not
  collected - the output directory travels between machines). The analyzer
  renders it as a new `RF0` section. The in-container collector additionally
  records `/etc/pki/rhui` visibility (s03).

## [r39] - 2026-07-04 - feat: unified probe (readiness + --facts) and observation fixes

### Changed
- **`tests/probe-env.sh` is now the single probe entry point.** The default
  (`--probe-env`) readiness mode keeps the exec/pkgmgr/repos/egress checks and
  the `probe_verdict` classifier, with two corrections: the repolist check
  runs with the subscription-manager plugins ENABLED and no manual mounts
  (the pre-r39 probe disabled the very plugin that materializes entitled
  repos, and premised entitlement on host-side mounts), and the per-major
  `entitlement` field is now OBSERVED inside each container
  (auto-injected = `/run/secrets/redhat.repo` present / anonymous).
  `--facts` absorbs the r37 `tests/probe-entitlement.sh` fact collection
  unchanged in output format; that file is removed.

### Fixed
- **Collector steps no longer pipe their exit code into `tail`** (the r37
  collector masked the s06 makecache and s12 CRB-enable rc behind `| tail`,
  so those rc values from the 2026-07-04 runs are unreliable; the raw logs
  remain valid). `t023` now pins that no emitted step contains `| tail`.
- **EL6 repolist is now observable**: EL6's `yum -q repolist` suppresses the
  entire table (observed on the entitled run: an empty capture while
  `rhel-6-server-rpms` was enabled and resolving), so `pc_repolist_cmd` is
  major-aware and drops `-q` for EL6; the analyzer already filters the
  resulting noise by only accepting count-bearing table rows.
- Analyzer polish: probe references updated to `probe-env.sh --facts`; the
  F2 product-tags cell no longer carries a trailing separator.

## [r38] - 2026-07-04 - chore: executable bit on the r37 probe scripts

### Fixed
- `tests/probe-entitlement.sh`, `tests/t023_probeentitlement.sh` and
  `tools/analyze-entitlement.sh` were committed `100644` in r37; executables
  with shebangs are `100755` in this repository (sourced libraries such as
  `lib/probe-common.sh` stay `100644`). Mode-only change; no content diff.

## [r37] - 2026-07-04 - feat: reproducible entitlement fact-probe (Phase A) + ubi10 curl-pull fix

### Added
- **Entitlement fact-probe** (`tests/probe-entitlement.sh` +
  `lib/probe-common.sh` + `tools/analyze-entitlement.sh`): the reproducible
  collector/analyzer pair behind the Phase A entitlement re-investigation. One
  run collects, per major (10/9/8/7/6) x condition (`auto` = plain run /
  `mounts` = the current rhsm passthrough as the A/B arm), the F1-F7 facts:
  enabled repos + defining files, `/run/secrets`, `redhat.repo` pre/post a
  `makecache` trigger, product-cert tags (OID `...2312.9.1.<id>.4` via
  asn1parse), real `--downloadonly` resolution of the build/install package
  sets, CRB/optional enablement, and the installed subscription-manager
  package set. Collection and analysis are separated: `ANALYSIS.md` is rebuilt
  from the run's artifacts only. The collector keeps subscription-manager
  plugins ENABLED - `tests/probe-env.sh`'s `--disableplugin` repolist cannot
  observe entitled repos by construction (defect recorded for the Phase C
  redesign). Engine: podman preferred; rootful curl+chroot fallback for
  anonymous sandboxes.
- **`tests/t023_probeentitlement.sh`** - hermetic unit tier pinning the syntax
  pitfalls that corrupted the prior ad-hoc investigation: yum's
  `repolist enabled` subcommand form (no `--enabled`), literal-`$basearch`
  section-id matching, mocked-openssl tag extraction, downloadonly command
  forms, `facts.tsv` shape, and `bash -n` validity of both emitted collectors.

### Fixed
- **`acq_pull_curl` fetched a non-layer blob on ubi10 and failed.** ubi10
  10.2's platform manifest carries an `annotations` object AFTER the
  `layers` array (`org.opencontainers.image.base.digest`, a sha256 that is
  not a layer); the extraction cut only at the `"layers"` key, so the
  annotation digest was fetched as a layer and the gzip/tar extraction
  failed. The digest scan now stops at the array's closing bracket.
  (Measured directly against `registry.access.redhat.com` on 2026-07-04.)

## [r36] - 2026-07-04 - fix: provisioning is repo-access-agnostic + a fail-fast test prerequisite

### Fixed
- **Test-env provisioning no longer fails RHEL 8/9/10 on an entitled host.** A
  real SSM run on an entitled RHEL 10 host skipped RHEL 10/9/8 with "test-env
  provisioning failed" (RHEL 7 happened to pass). Root cause: the r33 install ran
  `dnf/yum install gawk` with ALL repos enabled, and the entitlement passthrough
  mounts the HOST major's `redhat.repo` into every container - wrong-major inside
  a RHEL 8/9 container and unusable from a cert-only (unregistered) container, so
  dnf failed the whole transaction on its metadata refresh (the same class of
  failure r32 fixed for the SSM local-rpm install). The provisioning install is
  now **repo-access-agnostic**: it neutralizes the RHSM / product-id plugins when
  anonymous (mirroring the install scripts) and installs with
  `*.skip_if_unavailable=1` so a mismatched / unreachable enabled repo is skipped,
  not fatal - the package resolves from any working repo (public UBI / entitled
  `rhel-*` / RHUI) with no hardcoded repo ids. Verified genchi-genbutsu on a ubi8
  image carrying a broken wrong-major repo: the fixed helper installs `gawk` and
  commits (rc 0), where the old path failed. The provisioning error is now also
  captured from combined stdout+stderr (the old path lost dnf's stdout errors,
  leaving an empty reason).

### Changed
- **Provisioning is a PRE-FLIGHT test prerequisite (fail-fast).** Each matrix now
  prepares the test-ready image for every requested major *before* any test
  (`provision_prepare_majors`); a major that cannot be prepared aborts the whole
  run (non-zero, no tests) instead of silently skipping and running a partial
  sweep. The exception is `PROVISION_OPTIONAL_MAJORS` (**RHEL 6** by default): EL6
  is non-UBI and needs its own `rhel-6` entitlement the host cannot supply, so an
  unprovisionable EL6 is skipped (no EL6 tests) and the run continues for 7-10.
- **`tests/t021_provisionenv.sh`** gains coverage for the repo tolerance
  (`skip_if_unavailable`) and the pre-flight policy (all-prepared; a non-optional
  major aborts; EL6 tolerated and absent from the sweep). Suite: 22 tiers, 546.

### Notes
- EL6 provisioning itself (a real `rhel-6` entitlement path) remains a separate,
  tracked item; with this change EL6 now fails cleanly (skipped, run continues)
  with a real surfaced reason instead of an empty one.

## [r35] - 2026-07-03 - docs: document the test-env provisioning foundation in SPEC + TESTING

### Documentation
- **SPEC.md now specifies the test-env provisioning step (r33) as a first-class
  part of the environment contract.** New **B.6.1** (acquisition -> provision ->
  test; the common per-OS "test-ready" image; `PROVISION_PKGS`; EL6 needs the
  entitled `rhel-6` repos). **B.9** is corrected: the OL clean-core idea is not
  simply dropped - L2 now adds a minimal provisioning step
  (`lib/provision-test-env.sh`) on top of the L1 pull, a targeted port rather
  than a from-scratch rootfs build. **B.13** records the growth path - a tool
  needing a base package the vendor image lacks extends the common
  `PROVISION_PKGS` manifest, not a production installer.
- **SPEC.md B.11 documents the r34 `unavailable` status** for versions whose S3
  rpm is unpublished (403/404) - a distinct terminal state, not `install-fail`.
- **TESTING.md gains a "Test-environment provisioning" section** (the L2
  methodology + why EL6 needs it) and adds the two new tiers `t021` (provisioning)
  and `t022` (unavailable) to the L1/L2 contract. The recorded baseline is
  refreshed to the current suite (22 tiers, 539 passed; 45 shell files, 6
  libraries).

No code or test change; suite unchanged at 22 tiers / 539 passed.

## [r34] - 2026-07-03 - feat: SSM Agent "unavailable" status for versions whose rpm is unpublished at S3

### Added
- **A version whose agent rpm is UNPUBLISHED at S3 is now recorded as a distinct
  `unavailable` status, not `install-fail`.** A real E2E run found versions
  (e.g. 3.3.3883.0, 3.3.4364.0) whose git tag exists but whose
  `.../SSMAgent/<ver>/linux_amd64/amazon-ssm-agent.rpm` returns HTTP 403 on every
  RHEL major - the artifact was never distributed. Recording that as an install
  failure is wrong: the correct terminal status is "the rpm is not available",
  matching how the Oracle-Linux sibling records undistributed versions. The
  `--run` sweep now HEAD-checks each in-scope version's rpm once (the artifact is
  version-global, so one check covers every major) and, on a 403/404, writes an
  `unavailable` ledger row (`status` / `verdict` = `unavailable`, `installed` /
  `ran` = false, the reason carrying the HTTP status) WITHOUT running the doomed
  container. New helpers: `ssm_rpm_url`, `ssm_rpm_unavailable` (403/404 only -
  000/5xx stay transient errors to surface, not "unavailable"),
  `ssm_rpm_http_status` (network HEAD, `--run` only), `ssm_unavail_row`, and
  `ledger_verdict`.
- **`tests/t022_ssmunavailable.sh`: L1/L2 coverage** - the 403/404 classifier,
  the version-global rpm URL, the `unavailable` ledger row shape (valid JSON),
  and end-to-end report rendering via the hermetic `--generate-results` path.
  Suite: 22 tiers, 539 passed.

### Changed
- **The hermetic RESULTS report renders `unavailable` cells.** The report reads
  the stored verdict from the ledger (`ledger_verdict`) and, for an `unavailable`
  version, shows `unavailable` in the init_mode grid and the E2E sweep table
  rather than recomputing `install-fail` from installed/ran - so an unpublished
  version is visibly distinct from one that genuinely failed to install.

## [r33] - 2026-07-03 - feat: test-env provisioning step (per-OS "test-ready" image; mirrors the OL clean-core approach)

### Added
- **`lib/provision-test-env.sh`: a test-environment provisioning step, run
  BETWEEN image acquisition and test execution across every L3 matrix.** A real
  E2E run on an entitled host showed every SSM version failing on RHEL 6: the
  minimal `rhel6/rhel` base image ships without `awk`, and the amazon-ssm-agent
  rpm's `%pretrans` kernel-version guard calls `awk`, so the guard dies and the
  install fails - a test-ENVIRONMENT gap, not a defect in the production
  installer. Rather than patch the installer, the harness now prepares the
  environment first, exactly like the Oracle-Linux sibling's clean-core pipeline
  (build a curated image, then run the tests on it). `provision_test_image
  <major> <base_ref> <ent_mounts>` installs a COMMON package manifest
  (`PROVISION_PKGS`, default `gawk`) onto the base image and commits ONE
  "test-ready" image per OS major
  (`localhost/rhel-testsuite-provisioned:rhel<N>-<fingerprint>`), reused across
  the whole version sweep. Idempotent: the tag embeds a fingerprint of the
  manifest, so changing `PROVISION_PKGS` rebuilds automatically while an
  unchanged manifest reuses the committed image. On failure the caller skips that
  OS major with the real package-manager stderr (`PROVISION_LAST_ERR`), never a
  masked one. Verified genchi-genbutsu on an OL6 base (an EL6 proxy): base ->
  install `gawk` -> commit -> the SSM install then returns
  `{"status":"ok","osmajor":"6","installed":true,"ran":true}`, where the bare
  base died at the `%pretrans` awk guard.
- **`tests/t021_provisionenv.sh`: L1 unit coverage** for the provisioning helper
  (manifest-tag determinism + per-major / per-manifest fingerprinting, idempotent
  reuse of an existing image, build+commit success, and real-stderr surfacing on
  failure) via a hermetic PATH-mock `podman`. Suite: 21 tiers, 520 passed.

### Changed
- **All three L3 matrices (SSM Agent / AWS CLI v2 / ENA driver) now run against
  the provisioned "test-ready" image**, not the raw vendor base: each resolves
  its base ref via `acq_ref_for_major`, then swaps in `provision_test_image`
  before its sweep. One COMMON image per OS serves every test case (not one image
  per test), so a package any test needs is provisioned once and shared - and the
  step is in place for RHEL 10/9/8/7/6 uniformly, ready for future manifest
  additions (e.g. ENA build tooling) without touching a production installer.

## [r32] - 2026-07-03 - fix: SSM Agent install robustness (offline-first local rpm; real error surfacing)

### Fixed
- **`install-aws_ssm-agent.sh`: the local-rpm install no longer hinges on a full
  enabled-repo metadata refresh.** A real E2E run on an entitled RHEL 10.2 KVM
  host had every SSM version across RHEL 9/10 fail as `install-fail` with reason
  "rpm install failed (dependency closure) via dnf". Root cause: the SSM Agent
  rpm is dependency-free (`rpm -qpR` shows only `/bin/sh`, `rtld(GNU_HASH)`,
  rpmlib features, and its own `config(...)`), yet the installer ran
  `dnf -y install <local.rpm>` with repos enabled - and dnf refreshes EVERY
  enabled repo's metadata before even a local transaction. A single unreachable
  or major-mismatched repo (a host `redhat.repo` bind-mounted into a
  different-major UBI container, an unentitled anonymous base, or a transient CDN
  error) therefore failed the transaction for reasons unrelated to the package.
  The new `pm_install_local_rpm` helper installs OFFLINE first
  (`--disablerepo='*'`, which needs no repo metadata for a dep-free rpm) and only
  falls back to a repo-enabled resolve if that genuinely fails (a future rpm
  growing a real dependency). Verified genchi-genbutsu: the fixed installer
  returns `{"status":"ok","installed":true,"ran":true}` inside `ubi9/ubi`, where
  the unfixed path failed at repo-metadata download.
- **The failure reason is now the real package-manager stderr, not a guess.** The
  old path masked the pm output with `>/dev/null 2>&1` and hardcoded
  "dependency closure" regardless of the actual error. `pm_install_local_rpm`
  captures pm stderr into `PM_INSTALL_ERR` and `die` surfaces its last ~200
  characters, so a failing row in the ledger / `RESULTS-rhel<N>.md` now records
  why it failed (the `rpm -i` no-dnf/yum fallback captures its stderr likewise).
- **RHEL 6/7 `set -u` safety.** The package-manager argument list is built as a
  never-empty array (`("${mgr}" -y)`), so `"${cmd[@]}"` cannot trip the empty
  `"${arr[@]}"` unbound-variable behaviour of bash 4.1/4.2 (RHEL 6/7).

### Changed
- Suite green: 20 tiers, **504 passed** (up from 499; +5 in
  `t016_installintrospect.sh` B7: offline-first strategy + real-error surfacing,
  hermetic via a `run_pm` override so no real dnf/yum/network is touched).
  `README.md` / `README.ja.md` counts updated in lock-step.

## [r31] - 2026-07-03 - feat: ENA Express driver-version-floor readiness (aws_ena-driver)

### Added
- **`ena_express_verdict()` - ENA Express driver-version-floor classification.**
  A new pure, entitlement-independent verdict helper classifying a given ENA
  driver version against AWS's documented ENA Express driver-version floors
  (`ena-express.html`): `< 2.2.9` -> `not-ready`, `>= 2.2.9` -> `bandwidth-only`
  (full bandwidth, no `ena_srd_*` metrics), `>= 2.8.0` -> `express-ready` (both).
  REUSE-BY-COPY, kept identical across the three producers (verified by an
  extended `tests/t010_enaverdict.sh`, now covering the matrix/lister/installer
  triple, not just matrix/lister as before):
  - `tests/aws_ena-driver/run-ena-buildtest-matrix.sh` (source of truth) - the
    matrix computes the verdict itself from the requested version (never
    trusting a container's self-report); the ledger row gains an `ena_express`
    field, and `RESULTS-rhel<N>.md` gains a header field and a per-version
    expectation column (regenerated for real via `--generate-results`; all
    five reports currently show `express-ready` at each major's pinned/newest
    version).
  - `tests/aws_ena-driver/list-ena-releases.sh` - each entry in
    `ena-driver-releases.json` gains `express_verdict` alongside the existing
    `ge_min` (regenerated for real via a live `git ls-remote`; the 70-version,
    `ge_min`-only content is otherwise byte-identical to the prior commit).
  - `install-aws_ena-driver.sh` (production script) - the same helper is
    carried into the production installer itself, so a real build (or its
    `[result]` JSON in test mode, across the ok / anonymous / `die` fail
    paths) reports `ena_express` directly, and the production-mode install
    log line states the readiness alongside the installed `ena.ko` version.
- **Explicit necessary-not-sufficient caveat.** `ena_express_verdict` is a
  driver-capability signal only: ENA Express itself is enabled per
  network-interface attachment via the AWS API `EnaSrdEnabled` attribute
  (unrelated to the guest OS or this repository) and gated by instance type;
  "meets the floor" does not guarantee a given kernel actually compiles
  against that driver version (the OL sibling project's UEKR8 findings -
  `2.8.0` failing to compile against a newer kernel baseline - are cited in
  both `SPEC.md` and the generated `RESULTS-rhel<N>.md` as the cautionary
  precedent). Applies uniformly across all five RHEL majors (6-10): the
  verdict is a pure function of the version only and does not gate on OS
  major, since ENA Express eligibility is an instance-type property, not a
  RHEL-major property.

### Changed
- Suite green: 20 tiers, **499 passed** (up from 478; +21 in `t010_enaverdict.sh`
  for the new boundary-value and reuse-by-copy-triple coverage), 0 failed.
  `README.md`/`README.ja.md` counts updated in lock-step.

## [r30] - 2026-07-02 - docs: doc-set reconstruction to the template canon (B2 docs pass)

Docs half of the B2 canon-alignment arc (code half: r28; the CWD fix: r29).
Zero script change.

### Changed
- **SPEC.md reconstructed to the repository template canon (1.1.0).** Part A is
  now the **8 canonical regions vendored from the bash spec home**
  `governance/spec/bash.md` (marker+hash, verified by the document-conformance
  gate) plus two project extensions: **A.9** result-JSON machine channel and
  **A.10** duplicated-helper identity discipline. The former sections 1-10 are
  re-homed as **Part B** (B.1 identification, B.2 inputs, B.3 outputs, B.4
  phase map, B.5 locked decisions, B.6 acquisition, B.7 axes, B.8 tiers, B.9
  architecture, B.10 framework, B.11 packages/EPEL, B.12 naming, B.13 adding a
  tool); the quality gates + **open items** move to **Part C** (R5-R8 kept
  verbatim as the live empirical fill; **Q1/Q2** added for the pending hermetic
  coverage of `acquire-rootfs` internals via an `ACQ_ROOT` refactor; **Q3**
  recorded as superseded by the r28 errexit conversion); and the forensic
  lessons become **Part D** (D.1-D.8, incl. the r29 CWD-dependent SC1091
  finding). Old->new section references remapped across README/TESTING.
- **ADDING-A-TOOL.md / ADDING-A-TOOL.ja.md folded into the READMEs** as the
  bilingual "Adding a tool" section (files deleted; all references updated;
  SPEC B.13 points at the README section). This also removes the SPEC's only
  Japanese navigation label (English-only policy).
- **README.md / README.ja.md**: stale status corrected (16 tiers / 430 ->
  **20 tiers / 478**, r29 state), SPEC section references updated to Part
  B/C, and **Known limitations** + **Provenance** sections added (bilingual
  lock-step preserved: matching heading counts).
- **TESTING.md**: t017-t020 tier documentation added, the run-example block
  and the L0 fixed count (37 -> **42** files) brought to ground truth, and the
  front-matter re-pinned to template canon 1.1.0.
- **CHANGELOG.md**: doc-provenance pin added (the last doc-set member without
  one).

### Governance
- Manifest: `consumers[]` on `spec.bash.part-a` += `bash-rhel-container-testsuite`.

## [r29] - 2026-07-02 - fix: t002 ShellCheck source-path is CWD-independent

### Fixed
- **t002 failed with exactly 2 findings when the suite was invoked from the
  repository root** (e.g. `bash projects/.../tests/run-all.sh`) and passed from
  the project directory - masquerading as a rare flake because the two
  invocation habits were split across environments. Root cause: ShellCheck
  resolves `# shellcheck source=` paths against the CWD and the file's own
  directory, so `source=lib/os-profile.sh` (t012) and
  `source=lib/pkg-availability.sh` (t014) - the only two directives that point
  at the PROJECT lib/ rather than tests/lib/ - raised SC1091 (info, counted at
  `-S style`) whenever the CWD was not the project root. t002 now passes
  `-P "${PROJ}"` so directives resolve identically from any CWD.
  **Pre-existing since the tiers were added** (reproduced verbatim on the r27
  base); surfaced by the B2 fresh-clone verification which runs from the repo
  root. Verified 3x green from the repo root AND 3x from the project dir.

## [r28] - 2026-07-02 - canon alignment: errexit on production scripts + Layer-1 headers (B2 code pass)

Code half of the B2 canon-alignment arc (docs reconstruction follows as its own
revision). Aligns the suite with the bash spec home (`governance/spec/bash.md`)
extracted at B0.

### Changed
- **`set -euo pipefail` on all production/operational scripts** (spec home A.5
  two-tier scope): the 3 install scripts, the 3 matrix runners,
  `generate-os-coverage.sh`, and `check-tool-contract.sh` (8 files; the 3
  list scripts were already `-euo`). The self-test harness (`run-all.sh`,
  `tNNN_*` tiers, `probe-env.sh`, `verify-ena-buildresults.sh`) deliberately
  stays `-uo` - assertions/probes count failures and continue - now with an
  explicit rationale comment on the kept files.
- **3 tolerated-empty probe guards** (`|| true`) on the result-line extraction
  in each matrix's kick function: `pipefail` is inherited into command
  substitutions while `errexit` is not (spec home A.5 asymmetry), so a
  container that crashes before emitting its result line must yield the
  reasoned `harness-error` ledger row, not abort the matrix. Grounded by the
  empirical `-e` audit (statement-level, all 8 files; the substitution-invoked
  probes - `result_field`, `kdevel_kver`, `ko_module_version`, `host_glibc` -
  were proven inert under default bash and left untouched).
- **Layer-1 five-section header banners on all 42 `.sh` files** (Purpose /
  Prerequisites / Usage examples / Known limitations / AI generation info),
  per `scripts/README.md` "Required Header Convention" and spec home A.2.
  Existing header prose is preserved below the banner; sourced libraries
  (no shebang) carry the banner at file top.

### Notes
- Logging intentionally NOT changed: at ground truth the OL reference's
  auxiliary scripts (installers/matrices) use the same minimal tagged `log()`
  shape this suite uses; the spec home A.3 gained an explicit role-scoping
  paragraph in the same patch series, so the minimal form is canon-conformant
  (stdout here is the machine channel, so human logs stay on stderr).

### Verified
- Suite green (20 tiers / 478 passed), 3/3 consecutive; ShellCheck clean at
  default severity and -S style; all report-mode entry paths green
  (3 matrices, conformance, os-coverage, verify); LF-only.

All seven implementation phases are complete. The remaining work is the live
empirical fill (R5-R8) on a container-egress / entitled / Nitro host; the models,
generators, verifiers, and the tool contract are hermetic and green in-sandbox.

## [r27] - 2026-07-02 - quality pass: unit coverage for the ENA build-dep hot path + cross-script helper drift guard

### Added (test-only; zero production change)
- **`tests/t019_enabuilddeps.sh`** - hermetic unit for `ensure_build_deps`, the
  function that regressed three times (r22 host-kernel `kernel-devel-$(uname -r)`,
  r23 ERR-trap masking, r24 same host-kernel tie). Loads only that function with
  `run_pm`/`ena_pm`/`log` stubbed and pins: rc 0 on success, rc 1 on toolchain
  failure, rc 3 on kernel-devel unavailable, dkms failure stays best-effort (rc 0),
  and - the key regression guard - it installs **plain `kernel-devel`, never a
  host-kernel-versioned `kernel-devel-<kver>`**. Verified this guard fails when the
  r22/r24 bug is re-injected.
- **`tests/t020_helperidentity.sh`** - pins the four copy-pasted helpers
  (`entitlement_certs_present`, `pm_neutralize_rhsm_if_anonymous`, `run_pm`,
  `os_major`) byte-identical across all three install scripts, so a fix applied to
  one copy that drifts from the others fails the suite instead of shipping.

### Notes
- Part of an explicit suite-wide UT/FT quality pass (audit results and the remaining
  gaps - hermetic coverage of `acq_entitlement_mount_args`, `acq_platform`,
  `acq_repo_access` - are tracked in the handoff plan). Suite audit confirmed no
  latent r23-class ERR-trap bugs, no helper drift, ShellCheck-clean at default
  severity, and flaky-free (30/30).

### Verified
- Suite green (**20 tiers, 478 passed**), 20/20 consecutive runs; ShellCheck-style
  clean across all scripts; LF-only.

## [r26] - 2026-07-02 - probe egress: retry the whole request in-shell (version-agnostic), replacing curl --retry

### Fixed
- **Intermittent `s3=fail` flipping a single major to `degraded`** (seen on RHEL 8,
  then RHEL 10 - not major-specific, always transient). `curl --retry` only retries
  errors curl classifies as transient, so a TLS/DNS/connection blip slipped through;
  `--retry-all-errors` would cover it but is curl 7.71+ and RHEL 6/7 ship 7.19/7.29
  (the same old-curl trap as r19/r20). The S3/EPEL checks now retry the *whole* curl
  in a small POSIX shell loop (up to 3 tries, 1s apart, retrying on ANY failure),
  which is curl-version-agnostic and robust to transient egress blips. Supersedes
  the `--retry 2 --retry-delay 1` flags from r19/r20.

### Verified
- Suite green (**18 tiers, 458 passed**); ShellCheck-style-clean; LF-only. egress
  retry loop unit-checked in POSIX sh (fail-twice-then-succeed -> ok in 3 tries;
  always-fail -> fail after 3).

## [r25] - 2026-07-02 - test infra: make mock argv-spy recording a single atomic append (fixes flaky spy counts)

### Fixed
- **Intermittent `extracted 2 layers via tar (expected 2, got 1)` in t003.** The
  mock recorded each invocation with several `printf`s sharing one `>>` redirect,
  so two mocks running concurrently in a pipeline (`acq_curl ... | tar -xz`)
  interleaved their writes and occasionally corrupted a spy line. The mock now
  builds the whole line first and appends it with a single `printf` (one write,
  atomic under O_APPEND for these short lines), eliminating the race for every
  mock-based test. Test-infra only; no production code affected.

### Verified
- `run-all.sh` green 20/20 consecutive runs (**18 tiers, 458 passed**);
  ShellCheck-style-clean; LF-only.

## [r24] - 2026-07-02 - ENA entitled: build against the container's OWN kernel-devel, not the host kernel

### Fixed
- **The entitled ENA build was tied to the host kernel.** r22 installed
  `kernel-devel-$(uname -r)`; since containers share the host kernel, on a RHEL 10
  host every non-10 container asked for an el10 kernel-devel that its own repos do
  not carry, so RHEL 6/7/8/9 always failed - an artificial "same-major only"
  limitation. The ENA build test is a *compile* test (module LOAD is L4, never in a
  container), and the script is designed to build against the installed kernel-devel
  headers "independent of the running host kernel".
- **Fix:** `ensure_build_deps` now installs plain `kernel-devel` (plus `gcc`/`make`)
  from the container's own entitled repos; `build_ko` compiles against the newest
  installed `/usr/src/kernels/<kver>`. Each RHEL major builds against its own kernel
  headers, so a single RHEL 10 host can build-test RHEL 6, 7, 8, 9, and 10. A major
  reports `build-fail` only if its repos cannot provide kernel-devel or the pinned
  driver does not compile there. Comments, the rc-3 reason, and TESTING.md updated
  to drop the incorrect host-kernel/cross-major framing introduced in r22.

### Verified
- Suite green (**18 tiers, 458 passed**); ShellCheck-style-clean; LF-only.

## [r23] - 2026-07-02 - ENA entitled: stop the ERR trap from masking the real dep-install reason + surface pm log

### Fixed
- **`unexpected error (line 216)` on every entitled ENA run.** r22 called
  `ensure_build_deps` as a bare command, so its non-zero return (rc 1/3) tripped
  the script's `trap ... ERR`, which fired *before* the `case` could emit the real
  reason - both same-major and cross-major runs collapsed to the generic
  "unexpected error". The call is now guarded (`edc=0; ensure_build_deps || edc=$?`),
  which suppresses the ERR trap on a handled non-zero return, so the intended
  reason (`kernel-devel ... not available` for cross-major, or toolchain failure)
  is reported.
- **Diagnosis.** `ensure_build_deps` now tees the package-manager output to a log
  and `dump_pm_diag` prints its tail on failure (captured into the per-run
  buildtest log), so a failed entitled dep install shows *why* - missing NVR,
  disabled repo, or a TLS/entitlement error - instead of an opaque rc.

### Verified
- Suite green (**18 tiers, 458 passed**); ShellCheck-style-clean; LF-only.
  ERR-trap suppression semantics confirmed (`|| edc=$?` does not fire the trap;
  a bare call does).

## [r22] - 2026-07-02 - entitled path: complete the rhsm mount set + build ENA deps from entitled repos

Makes the entitlement passthrough actually functional end to end for every test
case across every OS. r19 wired the mounts and r18 gated the RHSM plugins, but two
pieces were missing: the entitled repo *definitions* were not passed in, and the
ENA build assumed kernel-devel/gcc/make were already present.

### Fixed / Added
- **rhsm mount set completed** (`acq_entitlement_mount_args`): now also mounts
  `/etc/yum.repos.d/redhat.repo` and `/etc/pki/product` alongside the entitlement
  certs and `/etc/rhsm`. Without `redhat.repo` the container had no entitled
  baseurls (UBI ships only the public ubi repos), so entitled-only packages were
  unreachable.
- **ENA entitled build now installs its dependencies** (`ensure_build_deps`):
  installs `gcc`, `make`, and `kernel-devel-$(uname -r)` from the entitled repos
  before building `ena.ko`. rc-mapped: toolchain-fail and "no matching kernel-devel"
  (cross-major, where the container major differs from the host kernel) each die
  with a clear reason. Same-major builds succeed; cross-major reports `build-fail`
  with a kernel-devel reason - a real, recorded finding, since a loadable module
  must match the running (host) kernel and containers share it.

### Unchanged (already entitlement-correct)
- **SSM** installs a local RPM with an empty non-rpmlib Requires (repo-free) and
  **AWS CLI v2** installs from the self-contained S3 zip; both are
  entitlement-independent on every major and needed no change. The passthrough is
  still applied harmlessly and helps only where a repo op is actually needed.

### Verified
- Suite green (**18 tiers, 458 passed**); ShellCheck-style-clean; LF-only.
  `ensure_build_deps` rc paths (0/1/3 + dkms best-effort) unit-checked; ENA matrix
  plumbing exercised via stub (entitled build emits, schema unchanged).

## [r21] - 2026-07-02 - probe: rename the repolist column/field (repos) + clearer states

Cosmetic/reporting only - no behavioural change to the sweep or classification.

### Changed
- The `--probe-env` column that used to read `yum` (and JSON field `yum_ok`) is
  renamed to **`repos`** so it is no longer confused with the `pkgmgr` value
  `yum`. It reports whether the in-container package manager can reach
  repositories (`<mgr> ... repolist`).
- Values are no longer `yes`/`no`; they now name what was observed:
  **`reachable`** (repolist succeeded), **`no-access`** (command ran but repos
  unreachable), **`no-cmd`** (no package manager), **`unknown`** (undetermined /
  probe timed out). The banner key changes `yum=` -> `repos=`, and the readiness
  legend now says "egress/repo gap".
- `probe_verdict` consumes the new token (`no-access` triggers `degraded`, as
  `no` did before); t017 updated and extended (adds the `no-cmd -> ready` case).

### Verified
- Suite green (**18 tiers, 458 passed**); ShellCheck-style-clean; LF-only.
  Table/banner/JSON reviewed on a stub run.

## [r20] - 2026-07-02 - probe: old-curl compatibility (drop --retry-connrefused)

### Fixed
- **RHEL 7/6 probe false `s3=fail` + `epel=fail`.** r19 added
  `--retry-connrefused` to the `--probe-env` egress checks, but that option
  requires curl >= 7.52.0. RHEL 7 (curl 7.29) and RHEL 6 (curl 7.19) reject it,
  so curl aborted immediately and both S3 and EPEL reported `fail` (flipping
  those targets to `degraded`) even though the endpoints were reachable. The
  egress checks now use `--retry 2 --retry-delay 1` only (both supported since
  curl 7.12.3), which keeps the transient-blip protection while working on the
  old images. RHEL 10/9/8 are unaffected. A compat note is inlined at the check.

### Verified
- Suite green (**18 tiers, 457 passed**); ShellCheck-style-clean; LF-only.
  Delta is `tests/probe-env.sh` + `CHANGELOG.md` only.

## [r19] - 2026-07-02 - probe egress retry + centralized RHSM/RHUI entitlement passthrough

Adds a deterministic egress check to the probe (fixes a flaky `s3=fail`) and a
single, centralized entitlement-passthrough layer covering RHSM and all major
cloud RHUI providers, consumed identically by the sweep and the probe.

### Fixed
- **Probe egress retry.** The `--probe-env` S3/EPEL checks now use
  `curl --retry 2 --retry-connrefused --retry-delay 1`, so a transient blip no
  longer flips a target to `degraded` (as RHEL 8 `s3=fail` did on one run).

### Added (all in lib/acquire-rootfs.sh - one source of truth)
- **`acq_platform`** - `physical` / `vm:<hv>` / `cloud:aws|azure|gcp|oci` (DMI +
  systemd-detect-virt).
- **`acq_repo_access`** - multi-signal classifier -> `rhsm` | `rhui:aws|azure|gcp|other`
  | `oci-ol` | `none`, with confidence and matched signals. RHUI providers are
  distinguished by client RPM + repo baseurl host + platform DMI (>= 2 agree).
  OCI is classified as rhsm (BYOS) or the distinct `oci-ol` (Oracle Linux yum,
  not RHEL RHUI); OCI has no Red Hat RHUI for RHEL.
- **`acq_entitlement_mount_args`** - emits the `-v`/`--network` set, DERIVED from
  the RHUI repo files' `sslclientcert/sslclientkey/sslcacert/gpgkey` paths (plus
  `/etc/pki/rhui`, the `amazon-id` plugin, and `--network host`). Provider-agnostic:
  an unknown RHUI works as `rhui:other` with no code change. rhsm mounts
  `/etc/pki/entitlement` + `/etc/rhsm`. Empty for oci-ol/none.
- **`acq_entitlement_feasible`** - feasible (rhsm) / conditional (rhui) / na.
- Pure helpers `acq_classify_repo_access` + `acq_entitlement_feasible` unit-tested
  in **t018**.

### Changed (thin consumers, no duplicated logic)
- The three matrices inject `$(acq_entitlement_mount_args "")` into the container
  run (computed once per sweep). On an anonymous host the args are empty, so the
  run is unchanged.
- `--probe-env` reports platform + repo_access (mode/confidence/signals) +
  entitled-passthrough feasibility in the banner and ENV-PROBE.json; the per-target
  `entitlement` field now carries the classified mode.

### Verified
- Suite green (**18 tiers, 457 passed**); ShellCheck-style-clean; LF-only. Stub:
  anonymous host adds no entitlement args (sweep unchanged); probe emits the new
  fields; repo ssl*/gpgkey/baseurl extraction validated on AWS+Azure samples.

## [r18] - 2026-07-02 - permanent yum fix (RHSM plugin gating) + timeouts + --probe-env

Supersedes the unreleased interim r17. Fixes the RHEL 6 live-host hang *properly*
(so yum actually works, which the ENA dkms/EPEL path needs) instead of bypassing
repos, and adds an opt-in environment probe.

### Root cause (recap)
RHEL 7-10 use UBI images (public repos); RHEL 6 uses the bare rhel6/rhel image,
whose subscription-manager/product-id yum plugins reach out to RHSM and hang with
no entitlement/route. r17's stopgap (`--disablerepo='*'`) unblocked SSM only
because the SSM RPM has no deps - but it would break ENA's dkms plan, which must
install DKMS from EPEL via yum. So the permanent fix must keep yum working.

### Fixed (permanent)
- **RHSM plugin gating (all install scripts).** When NO entitlement certs are
  present in the container, the subscription-manager/product-id yum|dnf plugins
  are disabled for that run (they only stall); when certs ARE present (entitled)
  they are left on, since entitled repos need them. yum/dnf then work normally
  against the pinned EPEL repo and any reachable repos - including RHEL 6. Entirely
  script + container-local; the host is never modified.
- **Two nested timeouts.** `RUN_TIMEOUT` (default 600s) wraps each `podman run`
  (a stall becomes a harness-error row + preserved log, sweep continues);
  `PKG_TIMEOUT` (default 300s) bounds each in-container yum/dnf op. Both overridable.

### Added
- **`tests/probe-env.sh` (opt-in `--probe-env`).** Probes all five majors with a
  common check set - image runs here (exec/glibc/vsyscall), pkgmgr, yum usable
  without the RHSM stall, S3 + EPEL egress, entitlement - and prints a readiness
  table (ready/degraded/blocked) + ENV-PROBE.json (git-ignored). Never modifies
  the host. Pure classifier `probe_verdict` is unit-tested (t017).
- TESTING.md: `--probe-env`, RHEL 6 assumptions, and the timeout knobs.

### Verified
- Suite green (**17 tiers, 441 passed**); ShellCheck-style-clean; LF-only.
  Stub: RUN_TIMEOUT path -> harness-error+reason+log; probe -> ready/degraded per
  egress; install-script wiring (plugin gating + run_pm) present in all three.

## [r16] - 2026-07-02 - host banner, SSM init_mode Case A, fail/error logs

Three operator-driven improvements, agreed as a spec before implementation.

### Added
- **Host environment banner (all three tools).** Each `--run` collects host basics
  once - OS (`PRETTY_NAME`/`ID`/`VERSION_ID`), kernel + arch, SELinux mode (or
  `absent` + an AppArmor note on non-RHEL), and the container runtime
  (`podman --version`, rootful/rootless, cgroup v1/v2) - and emits them to (1) the
  run log banner, (2) the ledger `host` meta object, and (3) a `Collected on:` line
  in each RESULTS. No timestamp (by spec). Makes SELinux/runtime issues diagnosable
  on any distro. (`host_json`/`host_banner`/`record_host_meta` in lib.)
- **Per-case fail/error logs (all three tools).** On a non-`ok` case the container's
  stdout+stderr is preserved to `./logs/` (fail/error only; `ok` clears any stale
  log). Names: `installtest-rhel<N>-ssm_<ver>_<mode>.log`,
  `buildtest-rhel<N>-ena_<ver>_<ent>.log`, `installtest-rhel<N>-awscli_<ver>.log`.
  `logs/` is git-ignored.
- **Ledger `reason` (all three tools).** Every row carries a `reason` (the OL-model
  "simple analysis"): the install script's own reason on `fail`, the podman/SELinux
  reason on `error`, empty on `ok`.

### Changed
- **SSM init_mode = Case A** (110 -> 60 cases). `install`/`ran` do not depend on
  init_mode, only `service_enabled` does; so `none` is swept for every in-scope
  version and `systemd` is verified on a representative version per major (latest;
  override via `SSM_SYSTEMD_VERSIONS`). The RESULTS E2E table shows `n/a` for the
  non-representative `systemd` cells. AWS CLI and ENA case counts are unchanged.

### Verified
- Stub-driven: Case A row counts (none=all, systemd=1/major), host meta + banner,
  fail/error log capture, `reason` propagation. Suite green (**16 tiers, 430
  passed**); contract ok; ShellCheck-`style`-clean; generate idempotent.

## [r15] - 2026-07-02 - fix: SELinux bind-mount + surfaced harness errors (--run)

A live `--run` on a real RHEL/KVM host failed **every** case (`status:"unknown"`,
`verdict:"install-fail"`, ~0.3s each) - a systemic harness bug, not a per-version
result.

### Fixed
- **SELinux bind-mount (root cause).** The matrices bind-mounted the install script
  with `:ro` and **no relabel**, so on an SELinux-enforcing host (the RHEL-family
  default - exactly this suite's target) the container could not read it and
  `/bin/bash /install-...sh` failed instantly, emitting no `[result]`. All three
  matrices now mount with **`:ro,z`** (shared relabel; a no-op where SELinux is off).
- **Errors are surfaced, not hidden.** The `podman run` stderr was sent to
  `/dev/null`; a container/pull/SELinux/auth failure was indistinguishable from a
  genuine tool failure and was mis-recorded as `install-fail`. Now stderr is
  captured; when no `[result]` is emitted the row is recorded as
  `status:"error"`, `verdict:"harness-error"` with the real `reason`, so the
  operator sees *why*.
- **Preflight.** Before a sweep, `acq_preflight` (lib/acquire-rootfs.sh) runs the
  ubi9 canary with the script bind-mounted and confirms a container can read it;
  on failure it prints the podman error + SELinux/pull/subscription hints and the
  run aborts cleanly (no misleading rows) instead of writing a whole failed sweep.

### Verified
- All three matrices: error path records `harness-error` + reason; success path
  records the real verdict; preflight aborts with hints. Suite green
  (**16 tiers, 430 passed**); ShellCheck-`style`-clean.

## [r14] - 2026-07-01 - docs: consolidated per-target run guide (TESTING.md)

### Added
- **TESTING.md gains "Running the end-to-end tests (per target)"** - a single,
  consolidated operational guide (not scattered) with a quick-reference table and
  per-tool subsections (AWS SSM Agent / ENA driver / AWS CLI v2). Each documents the
  one-script flow (`rm -rf *.md *.json; ./list-...; ./run-...`, plus `./verify-...`
  for ENA), the shared prerequisites (podman + egress; ENA needs an entitled host;
  load is L4), the sub-actions (`--run` / `--generate-results`), the evidence
  produced (RESULTS + ledger; `pending` semantics), and the per-tool knobs
  (`OSMAJORS`, `INITMODES`/`ENTITLEMENTS`, `SSM_VERSIONS`, `INSECURE_TLS`).
- README.md / README.ja.md now point to that section (single source; no duplication).

## [r13] - 2026-07-01 - ENA + AWS CLI: one-shot E2E (parity with r12/SSM)

Extends the r12 one-script model to the other two tools, so all three follow the
OL model's `rm -rf *.md *.json; ./list-...; ./run-...` workflow.

### Changed
- **ENA + AWS CLI `run-...-matrix.sh` no-arg default is now the full E2E**
  (`ACTION=all`): run the matrix, persist the ledger, then regenerate RESULTS in
  one invocation. `--run` (matrix + ledger only) and `--generate-results`
  (hermetic reports only) remain as explicit sub-actions.
- **Ledger auto-create + persist** (`ensure_ledger` / `persist_ledger`): a skeleton
  is written if the ledger is missing (so a from-scratch `list -> run` works after
  `rm *.json`); each run's rows are folded into `results[]` (ENA dedup key
  osmajor+ena_version+entitlement; AWS CLI osmajor+awscli_version; atomic write).
  If podman is absent, the run step is skipped with a clear message and the reports
  are still regenerated.
- **ENA `verify-ena-buildresults.sh` runs with no args**: `--ledger` defaults to the
  local `buildtest-ledger.json`, `--bundle` to `./build-bundle`; when no bundle is
  present yet it reports load-readiness *pending* and exits 0 (instead of a hard
  error), so `./run-... ; ./verify-...` composes cleanly. Verify stays a separate
  step (module load is L4 / real Nitro).

### Verified
- Each flow (`rm; list; run` [+ `verify` for ENA]) produces the ledger skeleton +
  all five reports; suite green (**16 tiers, 430 passed**); ShellCheck-`style`-clean;
  no-arg run and `--generate-results` idempotent.

## [r12] - 2026-07-01 - SSM: one-shot E2E (no-arg run + version sweep + evidence)

Makes the SSM matrix a single-command E2E, matching the OL model's workflow:
`rm -rf *.md *.json; ./list-ssm-releases.sh; ./run-ssm-installtest-matrix.sh`.

### Changed
- **No-arg default is now the full E2E** (`ACTION=all`): run the sweep, persist the
  ledger, then regenerate the RESULTS - one invocation, no flags. `--run`
  (sweep+ledger only) and `--generate-results` (hermetic reports only) remain as
  explicit sub-actions.
- **Version sweep**: `run_matrix` now iterates every in-scope version (min
  `3.3.3598.0` -> latest, 11 versions) x major x init_mode, instead of only the
  latest. Override with `SSM_VERSIONS="..."`; `OSMAJORS` / `INITMODES` still apply.
- **Ledger auto-create + persist**: `ensure_ledger` writes a skeleton if the ledger
  is missing (so a from-scratch `list -> run` works after `rm *.json`); the sweep's
  rows are folded into `results[]` (dedup by osmajor+version+init_mode, atomic
  write) - the durable evidence the report reads.
- **RESULTS**: the informational 3-row table is replaced by a full
  **E2E sweep evidence** table (every in-scope version x both init modes, empirical
  cells from the ledger, `pending` until run). If podman is absent, the run step is
  skipped with a clear message and the reports are still regenerated (pending).

### Verified
- The exact flow (`rm; list; run`) produces the ledger skeleton + all five reports;
  suite green (**16 tiers, 430 passed**); ShellCheck-`style`-clean; no-arg run and
  `--generate-results` both idempotent.

## [r11] - 2026-07-01 - RESULTS message-level parity (awscli + ena rationale)

Comprehensive sweep for the same class of omission as r10 (model rationale prose
absent from the RHEL reports), across all three tools' generators.

### Fixed
- **AWS CLI** `RESULTS-rhel<N>.md` gained the three rationale sections the model's
  awscli reports carry and the RHEL ones lacked: **"Why this matters - AWS CLI v2
  glibc support"** (the manylinux glibc gate, the 2024-09-16 AWS policy, the pin
  `<= 2.17.49` for glibc `<= 2.16`, doc references); **"Bundled Python runtime
  support"** (the frozen bundled CPython, no in-place remediation, the static
  Python EOL table - tying the r09 `bundled_python` / `min_glibc_measured` fields
  to a support horizon); and **"RHEL <N> support (the OS itself)"** (per-major OS
  lifecycle, verified 2026-07-01 against the Red Hat Customer Portal Life Cycle).
- **ENA** `RESULTS-rhel<N>.md` entitlement-grid note now states a build verdict of
  **ok** means the version compiled out of tree (necessary, not sufficient) and
  that real module load + device attach are proven separately on real Nitro -
  matching the model's framing.
- Regenerated all ten reports (awscli + ena, RHEL 6/7/8/9/10); regeneration is
  idempotent. SSM reports unchanged (covered by r10).

### Verified
- Suite green: **16 tiers, 430 passed**. ShellCheck-`style`-clean. All LF.

## [r10] - 2026-07-01 - SSM RESULTS: restore the Run Command deprecation rationale

### Fixed
- The SSM `RESULTS-rhel<N>.md` reports omitted the **"Why this matters - AWS
  Systems Manager Run Command deprecation"** rationale that the model project's SSM
  reports carry - the very context that justifies the `3.3.3598.0` compliance floor
  (and the r08 SSM pin). `generate_results_for` now emits it: the 2026-06-16
  ec2messages cutoff, the ssmmessages remediation (update to >= 3.3.3598.0 + grant
  the ssmmessages channel IAM actions), the AWS Health Dashboard, and the AWS doc
  references. Regenerated all five reports (RHEL 6/7/8/9/10); regeneration is
  idempotent. Suite still **16 tiers, 430 passed**.

## [r09] - 2026-07-01 - install-script parity with the model project (B1-B6)

Closes six robustness/feature gaps between the root install scripts and the model
project's installers - found in a follow-up audit, not yet visible to the matrices.

### Changed
- **B1 structured-fail emitter (`die`)** - all three install scripts now switch to
  `set -uo pipefail` + an `ERR` trap, and every failure path emits a single
  `[<tool>][installtest][result] {"status":"fail",...,"reason":...}` line (once,
  guarded by `RESULT_EMITTED`) before exiting, so an unexpected failure still
  yields a parseable, reasoned ledger row instead of an empty default.
- **B2 `status` field** - the `[result]` JSON now carries `"status":"ok"|"fail"`;
  the matrices parse and record it alongside the verdict.
- **B3 AWS CLI bundle introspection + landed-version check** - offline
  `detect_bundled_python` (from the libpython filename) and `measure_min_glibc`
  (max `GLIBC_x.y` symbol across the bundle .so's, dependency-free) are recorded as
  `bundled_python` / `min_glibc_measured`; install verifies the landed version
  matches the request (dies on mismatch unless `latest`).
- **B4 AWS CLI versionlock** - production path blocks the repo `awscli` (v1) via
  dnf/yum versionlock exclude so it never shadows the v2 bundle (best-effort).
- **B5 SSM init integration** - `enable_for_boot` enables `amazon-ssm-agent` via
  whichever init system is present: systemd -> chkconfig/SysV -> upstart (so
  RHEL 6's SysV/upstart is handled, not just systemd).
- **B6 ENA build diagnostics + false-success guard** - the build captures a
  `make.log` (surfaced by `dump_build_diag` on failure), and the built `ena.ko`'s
  modinfo version is verified to match the request (`ko_version`); a build that
  silently produced no/old module now fails instead of reporting success.
- The three matrices' `run_matrix` parse and record the new fields (`status`,
  `bundled_python`, `min_glibc_measured`, `ko_version`).

### Added
- `tests/t016_installintrospect.sh` - L1: hermetically tests `measure_min_glibc`,
  `detect_bundled_python`, `ko_module_version`, that `die` emits exactly one
  `status:fail` result (with the reason) in test mode and is silent in production,
  and that the B4/B5/B6 helpers are defined. 13 assertions.

### Verified
- Full suite green: **16 tiers, 430 passed, 0 skipped, 0 failed**. L0 covers
  **37 shell files**, all ShellCheck-`style`-clean. All LF. Contract: 3 tools, 3 ok.

## [r08] - 2026-07-01 - root install-script layer with per-OS version pins (matrices kick parameterized installers)

Restores the model project's two-layer structure, which r01-r07 had diverged from:
the **install logic now lives in project-root `install-<vendor>_<tool>.sh` scripts**
(real-host usable, with a test mode), and each matrix is a thin driver that **kicks
the install script with parameters** and records the `[installtest][result]` it
emits - instead of inlining the install in the matrix. Verdict logic stays
single-source in the matrices (the install scripts emit raw facts only).

### Added
- `install-aws_awscli-v2.sh` - install AWS CLI v2 (production + `AWSCLI_INSTALLTEST`).
  Env: `AWSCLI_VERSION`, `INSECURE_TLS`. Emits `[aws_awscli-v2][installtest][result]`.
- `install-aws_ssm-agent.sh` - install the SSM S3 RPM (production + `SSM_INSTALLTEST`),
  init-mode aware. Env: `SSM_VERSION`, `SSM_INIT_MODE`, `INSECURE_TLS`. Emits
  `[aws_ssm-agent][installtest][result]`.
- `install-aws_ena-driver.sh` - E2' entitlement-gated `ena.ko` build (production
  `modules_install`/`depmod` + `ENA_INSTALLTEST`). UEK removed; stock kernel;
  load never attempted (L4). Env: `ENA_VERSION`, `ENA_ENTITLEMENT`,
  `ENA_BUILD_PLAN`, `INSECURE_TLS`. Emits `[aws_ena-driver][installtest][result]`.
- Script names **match the test folders** (`tests/aws_awscli-v2/` ->
  `install-aws_awscli-v2.sh`, etc.).
- **Per-RHEL-major version pins** (mirrors the model project): each install script
  pins the version the matrix validated for each major as the **production
  default** (an explicit `<TOOL>_VERSION`, which the matrix passes in test mode,
  overrides it), resolved against the running OS in `resolve_version`:
  - AWS CLI v2: RHEL 6 -> `2.17.49` (last build below the v2 glibc-2.17 floor;
    RHEL 6 glibc 2.12); RHEL 7-10 -> `latest`.
  - SSM Agent: RHEL 6 -> `3.3.3598.0` (full-feature compliance floor; EL6 known-
    good); RHEL 7-10 -> `latest`.
  - ENA driver: RHEL 6 -> `2.9.1` (builds on the old EL6 kernel/toolchain);
    RHEL 7-10 -> `2.17.0`.
- `tests/t015_installpins.sh` - L1: sources each install script with
  `<TOOL>_LIB_ONLY=1` (defines helpers + pins, installs nothing), fakes the OS
  major, and asserts `resolve_version` picks the right pin and that an explicit
  version overrides it. A dropped/wrong pin fails the suite. 17 assertions.

### Changed
- The three matrices' `run_matrix` (`--run`, L3) now bind-mount and **kick the
  install script** in the rootfs (`podman run -v ... -e <TOOL>_INSTALLTEST=1 ...`),
  parse the `[result]` line with a new pure `result_field` helper, apply the
  unchanged verdict helper, and record. The pure helpers and `--generate-results`
  are untouched (t008-t010 still green).
- The tool contract now **gates the install-script layer**: a new pure
  `contract_install_missing` in `check-tool-contract.sh` requires
  `install-<tool>.sh` to exist, be executable, and be referenced (kicked) by the
  matrix. `t013_toolcontract.sh` asserts it; a non-conformant tool fails the suite.

### Verified
- Full suite green: **15 tiers, 415 passed, 0 skipped, 0 failed**. L0 covers
  **36 shell files** (the 3 install scripts auto-globbed and ShellCheck-`style`-clean).
  All LF. `check-tool-contract.sh`: 3 tools, 3 ok.

## [r07] - 2026-07-01 - Phase 7: generalization (tool-agnostic contract + classification)

Phase 7 makes the framework **tool-agnostic** and ready for a non-AWS tool #2: the
SPEC §10 (a-e) contract is now machine-enforced, and the SPEC §12 package
classification is a queryable canon. No new AWS tool - this phase generalizes.

### Added
- `lib/pkg-availability.sh` - the canonical package-availability taxonomy (pure):
  `pkgavail_class`, `pkgavail_known`, `pkgavail_needs_entitlement`,
  `pkgavail_anonymous_status`, `pkgavail_over_network`, `pkgavail_tool_source`.
  Classes: anonymous-ubi / entitled-only / epel / vendor-hosted / base-image. A
  tool's anonymous story is one call:
  `pkgavail_anonymous_status "$(pkgavail_class "$(pkgavail_tool_source <name>)")"`.
- `tests/conformance/check-tool-contract.sh` - a standalone read-only conformance
  checker that walks every `tests/<vendor>_<tool>/` and asserts the (a)-(e)
  contract (lister + releases.json; matrix with `--generate-results` and a
  `*_verdict()`; a `"results"` ledger; the five `RESULTS-rhel<N>.md`; a tier that
  sources the matrix). `CONTRACT_LIB_ONLY=1` exposes the pure `contract_dir_missing`.
- `tests/t013_toolcontract.sh` - L2: the three shipped tools conform, a synthetic
  incomplete dir reports its gaps, and the checker exits 0. 13 assertions.
- `tests/t014_pkgavail.sh` - L1 over the classification canon, incl. the
  end-to-end source->class->anonymous-status chain per tool. 33 assertions.
- `ADDING-A-TOOL.md` / `ADDING-A-TOOL.ja.md` - bilingual "add tool #2" guide
  (name -> classify -> implement (a)-(e) -> verify).

### Docs
- SPEC §7 documents contract enforcement; §8 documents the classification canon;
  the Phase contract marks Phase 7 done. README(.ja) status -> all 7 phases done.

### Verified
- Full suite green: **14 tiers, 385 passed, 0 skipped, 0 failed**. L0 covers
  **32 shell files**; every Phase-7 file is ShellCheck-`style`-clean. All LF.
- `check-tool-contract.sh` reports all three tools `ok`; the contract is now a
  suite-failing gate, so a non-conformant tool #2 cannot land silently.

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
