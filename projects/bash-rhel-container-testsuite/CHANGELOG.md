# Changelog

All notable changes to **bash-rhel-container-testsuite** are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project versions by **revision tag (`rNN`)** to match the sibling projects
in `ai-generated-artifacts`.

## [Unreleased]

### Planned (per the design plan sec 16)
- **Phase 2 - Acquisition:** `lib/acquire-rootfs.sh` (podman + curl-only OCI v2
  anonymous fallback, 3-step entitlement detection, init-mode invocation, RHEL 7
  fixed-tag), `lib/ubi-pkgmgr.sh`, `lib/epel.sh`, and the hermetic unit tiers
  `t003`-`t007`.
- **Phase 3 - AWS CLI:** `tests/aws_awscli-v2/*`, glibc ledger, RESULTS, verdict tier.
- **Phase 4 - SSM:** `tests/aws_ssm-agent/*`, glibc + init_mode, S3 RPM, RESULTS.
- **Phase 5 - ENA (E2'):** `tests/aws_ena-driver/*`, UEK-removed installer,
  entitlement-gated plain-make build, `needs-entitlement` recording.
- **Phase 6 - EOL/constrained:** RHEL 7 (frozen, yum, fixed-tag) and RHEL 6
  (no anon repo; entitled `rhel-6-server`; EPEL archive-only) specifics.
- **Phase 7 - Generalization:** tool-agnostic contract + classification for tool #2.

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
