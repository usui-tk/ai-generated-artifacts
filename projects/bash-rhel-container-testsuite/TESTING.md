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
SUITE: 12 passed, 0 skipped, 0 failed  (2 tiers, 0 tier-failure(s))
```

Run a single tier directly (its exit status reflects pass/fail):

```bash
bash tests/t001_parse.sh
bash tests/t002_shellcheck.sh
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
directives rather than suppress SC1091.

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

## Phase-1 recorded baseline

The Phase-1 scaffold's L0 gate is green in the planning sandbox:

```
== bash-rhel-container-testsuite test suite ==
  bash:       GNU bash, version 5.2.21(1)-release
  shellcheck: 0.9.0
---- t001_parse.sh ----      ## RESULT pass=6 fail=0 skip=0
---- t002_shellcheck.sh ---- ## RESULT pass=6 fail=0 skip=0
SUITE: 12 passed, 0 skipped, 0 failed  (2 tiers, 0 tier-failure(s))
```

**Fixed count = 6 shell files**, each `bash -n`-clean and ShellCheck-`style`-clean
(`tests/lib/{assert,mock,heredoc}.sh`, `tests/run-all.sh`,
`tests/t001_parse.sh`, `tests/t002_shellcheck.sh`).
