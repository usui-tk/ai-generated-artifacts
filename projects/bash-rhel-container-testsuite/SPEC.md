---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-07-01
---
# SPEC - bash-rhel-container-testsuite

> **Developer specification (English only).** Authoritative contract for the
> project's structure, axes, test tiers, tool-compatibility framework, and the
> phase plan. The narrative rationale and the measured Phase-0 findings are kept
> in the maintainer's design notes (out of repo); this document is the stable
> contract those findings justify. End-user instructions live in
> [`README.md`](./README.md) / [`README.ja.md`](./README.ja.md).

> ⚠️ **AI-generated content** - review the source before executing. See the
> repository's `scripts/README.md` policy for the full disclaimer.

---

## 1. Purpose & scope

A **container-based compatibility test suite for the RHEL family**. For each RHEL
major (**v10 / v9 / v8 / v7 / v6**) it evaluates which versions of a tool
**install** and **run** on Red Hat's container images, and emits a per-OS report.
It is the tool-centric, RHEL-family-centric generalization of the AWS CLI v2 /
SSM Agent / ENA matrices proven in the sibling project
`projects/bash-ol-aws-ami-builder`.

**Initial tool scope:** AWS CLI v2, AWS SSM Agent, AWS ENA Driver. Further tools
are added under the naming taxonomy in section 9.

**Out of scope (deferred):** authenticated `registry.redhat.io`; for any
kernel-module tool, the in-container module **load** test (impossible in a
container that shares the host kernel - that is always an L4 concern).

---

## 2. Locked decisions (contract)

| # | Decision | Resolution |
|:--|:--|:--|
| A1 | Project name | `bash-rhel-container-testsuite` |
| A2 | Install-script placement & test-folder naming | install scripts at **project root**; test folders carry a **`<vendor>_`** prefix (`aws_…`) from day one (section 9). |
| A3 | Image variant | **`ubi-init` is the single baseline.** Init-dependence is an invocation axis (`env_init_mode`), not a second image (section 4b). Standard `ubi` is not carried. |
| A4/A5 | Initial tool scope | AWS CLI v2 + SSM Agent + ENA Driver. |
| ACQ | Acquisition premise | **Anonymous UBI by default + auto-detected `entitled` mode** when the harness runs on a subscription-registered RHEL host. |
| ENA | Kernel-module range | **E2'**: run the ENA **build** test when entitled (kernel-devel available); record `needs-entitlement` when anonymous. Module **load** is always L4. |
| EPEL | Community repo handling | **Pin to `dl.fedoraproject.org`** (no metalink/mirrorlist); default = transient baseurl-pinned repo; EPEL 10 minor-versioned; RHEL 6 archive-only special case (section 8). |

These decisions are settled. Changing one is a SPEC revision, not an
implementation detail.

---

## 3. Acquisition & environment contract

1. Acquisition source = `registry.access.redhat.com`, **anonymous by default**.
   Package set = the UBI subset unless the host passes entitlement through.
2. **Baseline image = `ubi-init`** for RHEL 7/8/9/10; RHEL 6 = legacy
   `rhel6/rhel` (non-UBI). The init variant is an invocation axis, not a second
   image.
3. Acquisition engine = **podman preferred**, with a **curl-only OCI v2 anonymous
   pull as the fallback** (manifest `GET` returns HTTP 200 with no token step;
   blobs `302 -> cdn01.quay.io -> 200`). RHEL 7 `ubi-init` must be pulled by a
   **fixed tag/digest** (`:7.9-88` proven; the floating `latest` is rejected by
   the host signature policy).
4. The harness is **host-distro-agnostic**, self-contained, stdlib-only, with no
   `bats`/`shunit2`; it reuses `tests/lib/*` + `tests/run-all.sh`.
5. Tool-centric and multi-tool; the initial set is the three AWS tools.

### 3.1 Per-major base facts (measured Phase 0, anonymous)

| RHEL | Baseline image | Release | glibc | pkg mgr | Anonymous repos | Anon fetch |
|:--|:--|:--|:--|:--|:--|:--|
| 10 | `ubi10/ubi-init` | 10.2 | 2.39 | dnf | `ubi-10-{baseos,appstream,codeready-builder}` | yes |
| 9 | `ubi9/ubi-init` | 9.8 | 2.34 | dnf | `ubi-9-{baseos,appstream,codeready-builder}` | yes |
| 8 | `ubi8/ubi-init` | 8.10 | 2.28 | dnf | `ubi-8-{baseos,appstream,codeready-builder}` | yes |
| 7 | `ubi7/ubi-init` (fixed tag) | 7.9 | 2.17 | yum | `ubi-7`, `-optional`, `-extras`, `ubi-server-rhscl-7` | yes (GPG-verified) |
| 6 | `rhel6/rhel` | 6.10 | 2.12 | yum | none (`redhat.repo` empty) | no (subscription required) |

The TLS-interception caveat (`INSECURE_TLS=1` -> `--setopt=sslverify=0`) is
**sandbox-specific** and unnecessary on a real host; the helpers expose it as a
switch (sandbox = 1, trusted host = 0).

---

## 4. The two first-class axes

### 4a. Entitlement axis - `env_entitlement = anonymous | entitled`

| Mode | Condition | Repos in container | kernel-devel / ENA build | AWS CLI / SSM |
|:--|:--|:--|:--|:--|
| `anonymous` | Fedora/Ubuntu/Debian/unregistered RHEL host | `ubi-N-*` only | no -> `needs-entitlement` | yes (both) |
| `entitled` | subscription-registered RHEL host, secrets bind-mounted | `rhel-N-*` passthrough (+ `ubi-N-*`) | yes (build feasible, all majors) | yes (both) |

**Detection is three steps** (the suite handles no secrets itself):

1. **Secrets check** - is `/run/secrets/etc-pki-entitlement/*.pem` present?
2. **Trigger** - run one `dnf/yum makecache` (or any repoquery) so the
   subscription-manager plugin generates `redhat.repo`. `redhat.repo` is
   generated **lazily** and is empty until then; never judge by a bare `grep`
   before this trigger.
3. **Classify** - is any **`rhel-*`** repo now enabled, and does
   `dnf list --available kernel-devel` / `repoquery --latest-limit=1` resolve?
   Match entitled repos by the **`rhel-*` prefix** (IDs differ by generation:
   `rhel-7-server-rpms` vs `rhel-9-for-x86_64-appstream-rpms`); never hard-code
   the owning repo per major. RHEL 6 `repolist` formatting differs - judge by the
   repoquery result, not a repolist string match.

The passthrough mechanism is **identical across all five majors and both image
variants**; it does not depend on the init variant. `dkms` is **EPEL-only** in
every major (anonymous and entitled). The AWS packages
(`awscli`/`awscli2`/`amazon-ssm-agent`) are absent from every repo, which is why
bundle / S3-RPM acquisition is the correct path.

### 4b. Init-mode axis - `env_init_mode = none | systemd`

`ubi-init` is a **strict superset** of standard `ubi`: run it with an explicit
command and systemd is not PID 1 (equivalent to `ubi` for install/binary tests);
run it as `/sbin/init` (booted, `podman run -d`) and systemd is PID 1 for
service/unit tests. A single `ubi-init` image therefore covers both modes by
invocation:

| `env_init_mode` | How | What it tests |
|:--|:--|:--|
| `none` | `podman run ubi-init <cmd>` | install + run a binary (init-agnostic) |
| `systemd` | `podman run -d ubi-init` (boots `/sbin/init`) then `podman exec` | `systemctl enable`/`start`, unit activation, boot order |

---

## 5. OS / image coverage tiers

| RHEL | Baseline image | Tier | Anonymous | Entitled |
|:--|:--|:--|:--|:--|
| 10 / 9 / 8 | `ubiN/ubi-init` | A - current | `ubi-N-*`; pull is ready-made | `rhel-N-for-x86_64-*`; kernel-devel yes |
| 7 | `ubi7/ubi-init` (fixed tag/digest) | B - settled | `yum`; anon fetch yes (incl. RHSCL) | `rhel-7-server-rpms`; kernel-devel yes |
| 6 | `rhel6/rhel` (non-UBI) | C - constrained | no anon repo (base image only) | `rhel-6-server-rpms`; kernel-devel yes |

RHEL 6 is Tier C because it has **no anonymous repo**, not because it is
unbuildable when entitled. EPEL on RHEL 6 is archive-only and special-cased
(section 8).

---

## 6. Layered architecture & test tiers

```
L1  RHEL-family base image (baseline: ubi-init)   <- podman (preferred) /
        (Red Hat maintained)                          curl-only OCI v2 anon (fallback)
        |                                              Tier A: ready-made; L1 is a pull
L2  Common test platform                          <- toolchain via the image's pkg mgr
        (tools + runtime + libs)                      (UBI subset) or rhel-* (entitled)
        |
L3  Tool under test                               <- AWS CLI v2 / SSM Agent / ENA
        |                                              per (OS major, version[, init_mode])
    Compatibility matrix runner                   <- ledger (JSON) + RESULTS-rhel<N>.md
```

Red Hat ships the curated base, so **L1 is a pull, not a build**: the model
project's `tests/cleancore/` does not port; it is replaced by
`lib/acquire-rootfs.sh`.

| Tier | Checks | Where | Run by |
|:--|:--|:--|:--|
| **L0 Static** | `bash -n`, ShellCheck `-S style` | any host / CI | `run-all.sh` |
| **L1 Unit (hermetic)** | pure verdict helpers (glibc compare, version scope, EOL, entitlement classify, init-mode map) | any host / CI | `run-all.sh` |
| **L2 Component** | ledger guards, RESULTS generator on fixtures, env parity | any host / CI | `run-all.sh` |
| **L3 Integration** | real pull + install/run (podman or curl-only+chroot), both init modes where relevant | host/CI with `*.quay.io` reachable | `tests/aws_*/run-*-matrix.sh` (manual/CI) |
| **L4 E2E** | genuine RHEL instance: kernel-module **load**, real ENA, real SSM register | real RHEL host | deferred |

`tests/run-all.sh` aggregates **L0-L2** plus each tool's host-runnable verdict
units and prints one `## RESULT pass/fail/skip` summary. **L3 is manual / CI.**

---

## 7. Tool-compatibility matrix framework (generalized, a-e)

Each tool folder `tests/<vendor>_<tool>/` implements the same five-part contract:

* **(0)** a project-root `install-<vendor>_<tool>.sh` - real-host-usable installer
  with a test mode (`<TOOL>_INSTALLTEST=1`) that installs/builds in a disposable
  rootfs, smoke-checks, and emits one `[<vendor>_<tool>][installtest][result] {json}`
  line of raw facts. The matrix **kicks this script with parameters**; install
  logic is never inlined in the matrix. (Name matches the test folder.) It also
  carries **per-RHEL-major version pins** - the version validated for each major,
  used as the production default and resolved in `resolve_version` (an explicit
  `<TOOL>_VERSION` wins; the matrix passes one in test mode). Initial pins: AWS CLI
  RHEL 6 `2.17.49` (below the v2 glibc-2.17 floor) else latest; SSM RHEL 6
  `3.3.3598.0` (compliance floor) else latest; ENA RHEL 6 `2.9.1` else `2.17.0`.
* **(a)** `list-<tool>-releases.sh` -> `<tool>-releases.json`.
* **(b)** `run-<tool>-{install,build}test-matrix.sh` - per `(OS major, version[, init_mode])`
  acquire/reuse, **kick the install script** in its test mode, parse the `[result]`,
  apply the verdict, record.
* **(c)** `<tool>-…-ledger.json` - append/dedup; `env_*` measured fields (glibc,
  kernel, **entitlement**, **init_mode**) kept separate from `compat_*` derived
  fields.
* **(d)** `RESULTS-rhel<N>.md` per OS - regenerated each run, never hand-edited.
* **(e)** pure verdict helpers + table-driven unit tests (no I/O), `tNNN`-style.

**Dominant axis per tool:** AWS CLI -> glibc; SSM -> glibc (+ init_mode);
ENA -> kernel + entitlement.

**Contract enforcement (Phase 7).** The five-part contract is machine-checked:
`tests/conformance/check-tool-contract.sh` walks every `tests/<vendor>_<tool>/`
and verifies (0)-(e) are present (the **root `install-<vendor>_<tool>.sh` exists,
is executable, and is kicked by the matrix**; lister + `*-releases.json`; a matrix
with `--generate-results` and a `*_verdict()` helper; a `"results"` ledger; the
five `RESULTS-rhel<N>.md`; and a tier that sources the matrix).
`tests/t013_toolcontract.sh` fails the suite if any tool is non-conformant. Adding
a non-AWS tool #2 is then a fill-in-the-blanks exercise - see
[`ADDING-A-TOOL.md`](./ADDING-A-TOOL.md) ([日本語](./ADDING-A-TOOL.ja.md)).

### 7.1 Per-tool notes (initial three)

* **`aws_awscli-v2`** - self-contained bundle, not repo-installed, so the only
  gate is **glibc**. AWS rule (2024-09-16): glibc <= 2.16 pins v2 <= 2.17.49;
  else current. `env_init_mode=none`. Works in both entitlement modes; fine on
  Tier C (no repo needed).
* **`aws_ssm-agent`** - acquired from the AWS **S3 RPM**. Axis = glibc +
  init_mode: `none` installs and runs `amazon-ssm-agent -version`; `systemd`
  boots `ubi-init` and verifies the unit activates (real registration needs
  creds -> L4).
* **`aws_ena-driver`** - **E2'**, entitlement-gated **build** test (compile
  `ena.ko`), never a load test. Build needs `kernel-devel` (obtainable in every
  major when entitled). Default is the plain-`make` fallback
  (`make -C /usr/src/kernels/<kver> M=$PWD modules`); DKMS is an optional EPEL
  path. All Oracle **UEK** detection is removed; target is the stock RHEL kernel.
  Anonymous -> `needs-entitlement`; load/runtime -> L4.

---

## 8. Package-availability classification & EPEL handling

Every repo-installed input is classified:

* **Anonymous UBI repos** (`ubi-N-*`; RHEL 7 also `optional`/`extras`/RHSCL) -> installable anywhere.
* **Entitled-only** (`rhel-N-*`, e.g. `kernel`, `kernel-devel`) -> entitled mode only; else `needs-entitlement`.
* **EPEL** (e.g. `dkms`) -> out of base; pinned, transient, OFF by default.
* **Vendor-hosted** (AWS CLI bundle, SSM S3 RPM) -> outside repos; over `*.amazonaws.com`.

**Classification canon (Phase 7).** `lib/pkg-availability.sh` encodes this taxonomy
as pure helpers (`pkgavail_class`, `pkgavail_needs_entitlement`,
`pkgavail_anonymous_status`, `pkgavail_over_network`, `pkgavail_tool_source`), so a
tool declares its acquisition source and the suite derives its anonymous story in
one call - e.g. `aws_ena-driver` -> `kernel-devel` -> `entitled-only` ->
`needs-entitlement` (matching `ena_verdict`); `aws_awscli-v2` -> `awscli-bundle`
-> `vendor-hosted` -> `installable`. Covered by `tests/t014_pkgavail.sh`.

**EPEL (`lib/epel.sh`).** RHEL has no vendor EPEL, and Fedora's default metalink
is non-deterministic (returns off-allow-list mirrors). Therefore pin to
`dl.fedoraproject.org` with an explicit `baseurl`, metalink/mirrorlist disabled,
and use a transient pinned repo (method B), not the `epel-release` package
(method A). Per-major baseurls (measured): 8/9 current
(`/pub/epel/<N>/Everything/x86_64/`); 10 minor-versioned with a rolling fallback;
7 and 6 archive (`/pub/archive/epel/<N>/x86_64/`). GPG keys for all majors live
under `/pub/epel/RPM-GPG-KEY-EPEL-<N>` (live tree) even where content is
archived. RHEL 6 EPEL is archive-only and OL6-style special-cased; practically
moot since ENA defaults to plain-make.

---

## 9. Naming taxonomy (`<vendor>_<tool>`)

* Vendor boundary = underscore `_`; within-tool words = hyphen `-`.
* Initial: `aws_awscli-v2`, `aws_ssm-agent`, `aws_ena-driver` (mild redundancy
  accepted for an explicit prefix from day one).
* Future: `azure_az-cli`, `gcp_gcloud-cli`, `hashicorp_terraform`, …; non-vendor
  utilities use a category prefix in the same grammar (`util_jq`, `k8s_kubectl`).
* Root install scripts keep the model's short names (`install-<tool>.sh`).
* Vocabulary is recorded here and extended per addition.

---

## 10. Phase contract

| Phase | Deliverable | Exit criterion | Status |
|:--|:--|:--|:--|
| 0 - Feasibility | measured base facts, anon pull, entitled passthrough, signatures, EPEL endpoints | findings measured in Phase 0 | **done** (tail: one real `ena.ko` plain-make build, R1) |
| 1 - Scaffolding | dir skeleton, ported `tests/lib/*`, `run-all.sh`, `.shellcheckrc`, L0 green, bilingual README | L0 passes; fixed count recorded | **done (r01)** |
| 2 - Acquisition | `lib/acquire-rootfs.sh` (+`t003`), `lib/ubi-pkgmgr.sh` (+`t004`), `t005_entitlementdetect`, `t006_initmodemap`, `lib/epel.sh` (+`t007`) | unit tiers green; live pull both paths; classify unit-tested | **done (r02)** (tail: live pull is L3/CI) |
| 3 - AWS CLI | `tests/aws_awscli-v2/*`, glibc ledger, RESULTS, verdict tier | matrix runs (Tier A); reports generated | **done (r03)** (tail: live install is L3/CI) |
| 4 - SSM | `tests/aws_ssm-agent/*`, glibc + init_mode, S3 RPM, RESULTS | both init modes exercised; reports generated | **done (r04)** (tail: live install is L3/CI) |
| 5 - ENA (E2') | `tests/aws_ena-driver/*`, UEK-removed installer, entitlement-gated build | build on entitled host; anon -> `needs-entitlement`; load -> L4 | **done (r05)** (tail: live build L3, load L4) |
| 6 - EOL/constrained | RHEL 7 (frozen, yum, fixed-tag) + RHEL 6 (no anon repo; entitled `rhel-6-server`; EPEL archive-only) | reports generated or formally deferred | **done (r06)** (canon `lib/os-profile.sh` + coverage matrix) |
| 7 - Generalization | tool-agnostic contract (sec 7) + classification (sec 8) ready for tool #2 | SPEC/TESTING coverage complete; docs bilingual | **done (r07)** (contract checker + pkg-availability canon + ADDING-A-TOOL) |

### Open items

| # | Item | Disposition |
|:--|:--|:--|
| R1 | One real `ena.ko` plain-make build in an entitled container | Phase 5 / Phase 0 tail |
| R2 | EPEL/DKMS-managed ENA vs plain-make only | Phase 5; default plain-make, EPEL optional |
| R3 | RHEL 6 SSM S3-RPM dependency closure vs base-image-only contents | Phase 6 probe |
| R4 | Naming vocabulary for future non-AWS tools | this SPEC, Phase 7 |
| R5 | Live pull both paths (podman + curl-only OCI) on a container-egress host | L3/CI; the hermetic sequence is unit-tested in `t003` (Phase 2 tail) |
| R6 | Live AWS CLI v2 install-test matrix (`--run`) -> empirical RESULTS column | L3/CI; the glibc model + report generation are hermetic (Phase 3 tail) |
| R7 | Live SSM install-test matrix (`--run`, both init modes) -> empirical RESULTS | L3/CI; the init-mode grid + compliance model are hermetic (Phase 4 tail) |
| R8 | Live ENA build on an entitled host (`--run`) -> empirical RESULTS; module load | L3 build / L4 load; the E2' grid + verifier gates are hermetic (Phase 5 tail) |
