---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-07-01
---
# RHEL-family Container Test Suite

English | [日本語](./README.ja.md)

> 📂 Part of [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) → [`projects/bash-rhel-container-testsuite/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-rhel-container-testsuite)
> ⚠️ **AI-generated content** — review the source before executing. See the [scripts directory policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md) for the full disclaimer.
> 📐 **Developer specification**: [SPEC.md](./SPEC.md) (English only) — locked decisions, the two axes, test tiers, the tool-compatibility framework, and the phase contract.
> ➕ **Adding a tool**: [ADDING-A-TOOL.md](./ADDING-A-TOOL.md) ([日本語](./ADDING-A-TOOL.ja.md)) — the tool-agnostic contract, fill-in-the-blanks for tool #2.

A **container-based compatibility test suite for the RHEL family**. For each RHEL
major (**10 / 9 / 8 / 7 / 6**) it measures which versions of a tool **install** and
**run** on Red Hat's container images, then emits a per-OS report. It is the
tool-centric, RHEL-family-centric generalization of the AWS CLI v2 / SSM Agent /
ENA matrices proven in the sibling project
[`bash-ol-aws-ami-builder`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-ol-aws-ami-builder).

**Initial tool scope:** AWS CLI v2, AWS SSM Agent, AWS ENA Driver.

---

## ⚠️ Disclaimer (read before running)

**USE AT YOUR OWN RISK.** This software is provided "AS IS" without warranty of
any kind. The authors and contributors are not liable for any damages, data loss,
unintended cloud spend, account or subscription issues, or any other problems —
direct or indirect — arising from using, modifying, or distributing it.

By running this suite you acknowledge that:

* You are solely responsible for complying with **Red Hat's subscription terms**
  (especially for entitlement passthrough and `registry.redhat.io`), **AWS's
  Service Terms**, and any applicable laws.
* L3 integration runs **pull container images** and **download tool artifacts**
  (AWS CLI bundle, SSM S3 RPM) over the network and may incur transfer costs.
* **Entitled mode** uses your host's Red Hat entitlement (bind-mounted secrets);
  the suite never handles your secrets itself — it only detects whether your host
  is passing them through.
* You will review the source (or [SPEC.md](./SPEC.md)) before running it in any
  environment.

Prefer official, supported channels for production work. This suite targets
**compatibility measurement and reporting**, not production provisioning.

---

## Why this suite exists

Operators who run RHEL-family containers repeatedly hit the same question: *does
version X of this tool actually install and run on RHEL N?* The answer varies by
glibc, by package manager (dnf vs yum), by init model (plain shell vs systemd
PID 1), and by whether the host passes Red Hat entitlement through to the
container. This suite turns that question into a **reproducible matrix**: for each
RHEL major and each tool version it records the measured environment
(glibc / kernel / entitlement / init-mode) and the derived verdict, and
regenerates a per-OS report you can read at a glance.

It is built on two facts established by direct measurement (Phase 0):

1. Red Hat's UBI images can be pulled **anonymously** (no token step) and used
   for install/run tests across RHEL 7-10; RHEL 6 uses the legacy `rhel6/rhel`
   base.
2. When the suite runs on a **subscription-registered RHEL host**, entitlement
   passes through to the container, the `rhel-*` repos enable, and `kernel-devel`
   becomes obtainable — enabling the ENA kernel-module **build** test. The suite
   **auto-detects** this and otherwise records `needs-entitlement`.

---

## Two axes you will see throughout

* **Entitlement** — `env_entitlement = anonymous | entitled`. Auto-detected via a
  three-step probe (secrets present → trigger `redhat.repo` generation →
  classify by the `rhel-*` repo prefix). See [SPEC.md](./SPEC.md) §4a.
* **Init mode** — `env_init_mode = none | systemd`. A single `ubi-init` image
  covers both: run it with a command (no PID-1 systemd) for install/binary tests,
  or boot it (`podman run -d`) for `systemctl` service tests. See
  [SPEC.md](./SPEC.md) §4b.

---

## Repository layout

```
bash-rhel-container-testsuite/
  README.md  README.ja.md          # bilingual, kept in sync
  SPEC.md  TESTING.md              # developer spec + testing guide
  CHANGELOG.md  .shellcheckrc
  lib/                             # acquisition libraries        (Phase 2 ✅)
    acquire-rootfs.sh  ubi-pkgmgr.sh  epel.sh
    os-profile.sh                    # canonical per-major OS profile (Phase 6 ✅)
    pkg-availability.sh              # package-availability classification (Phase 7 ✅)
  install-aws_awscli-v2.sh         # root install scripts: real-host usable +    (r08 ✅)
  install-aws_ssm-agent.sh         #   a test mode; named to match the test folders;
  install-aws_ena-driver.sh        #   the matrices kick these with parameters;
                                   #   each pins the per-RHEL-major validated version
  tests/
    lib/{assert,mock,heredoc}.sh   # ported harness
    run-all.sh                     # single-entry L0-L2 runner
    t001_parse.sh  t002_shellcheck.sh             # L0 (present)
    t003_acquireunit.sh … t007_epelresolve.sh     # L1/L2 (Phase 2 ✅)
    t008_awscliverdict.sh  t009_ssmverdict.sh    # L1 AWS CLI + SSM verdicts (Phase 3-4 ✅)
    t010_enaverdict.sh  t011_enaverify.sh         # L1 ENA verdict + verifier (Phase 5 ✅)
    t012_osprofile.sh                             # L1 OS profile + cross-checks (Phase 6 ✅)
    t013_toolcontract.sh  t014_pkgavail.sh        # contract + classification (Phase 7 ✅)
    aws_awscli-v2/                                # AWS CLI matrix (Phase 3 ✅)
      list-awscli-releases.sh  awscli-releases.json
      run-awscli-installtest-matrix.sh  awscli-installtest-ledger.json
      RESULTS-rhel{6,7,8,9,10}.md
    aws_ssm-agent/                                # SSM matrix (Phase 4 ✅)
      list-ssm-releases.sh  ssm-releases.json
      run-ssm-installtest-matrix.sh  ssm-installtest-ledger.json
      RESULTS-rhel{6,7,8,9,10}.md
    aws_ena-driver/                               # ENA buildtest matrix (Phase 5 ✅)
      list-ena-releases.sh  ena-driver-releases.json
      run-ena-buildtest-matrix.sh  buildtest-ledger.json
      verify-ena-buildresults.sh  RESULTS-rhel{6,7,8,9,10}.md
    os-coverage/                                  # OS coverage matrix (Phase 6 ✅)
      generate-os-coverage.sh  RESULTS-coverage.md
    conformance/                                  # tool-contract checker (Phase 7 ✅)
      check-tool-contract.sh
```

Files marked *(Phase N)* are **not present yet** — see *Status* below. The
`lib/` and `tests/aws_*/` directories ship with a `.gitkeep` so the planned
structure is visible.

---

## Running the suite

The static + hermetic-unit tiers (L0-L2) run on any host with no network:

```bash
bash tests/run-all.sh
```

The L3 integration matrices (real pulls and installs) are run explicitly, on a
host with container egress, once they land in Phases 3-5. See
[TESTING.md](./TESTING.md) for the full tier model and environment dependencies.

---

## Status

This is the final **Phase 7 (generalization)** drop — all seven phases complete:

* ✅ **Phase 0 — feasibility** — measured base facts (per-major glibc, anon repo
  sets, anon pull, entitled passthrough across all five majors, RHEL 7 fixed-tag
  signature, EPEL endpoints). measured during Phase 0.
* ✅ **Phase 1 — scaffolding** — directory skeleton, ported `tests/lib/*`,
  `run-all.sh`, `.shellcheckrc`, bilingual docs, and a green L0 gate.
* ✅ **Phase 2 — acquisition** — `lib/acquire-rootfs.sh`, `lib/ubi-pkgmgr.sh`,
  `lib/epel.sh` and their hermetic unit tiers `t003`-`t007`.
* ✅ **Phase 3 — AWS CLI v2** — the first per-tool matrix `tests/aws_awscli-v2/*`
  (release lister + `awscli-releases.json` of 927 versions, install-test matrix,
  glibc ledger, generated `RESULTS-rhel{6,7,8,9,10}.md`) and the verdict tier `t008`.
* ✅ **Phase 4 — AWS SSM Agent** — the init-sensitive matrix `tests/aws_ssm-agent/*`
  (`ssm-releases.json` of 207 versions, the **glibc + init_mode** install-test
  matrix wiring Phase 2's `acq_init_run_args`, generated `RESULTS`) and the verdict
  tier `t009`.
* ✅ **Phase 5 — AWS ENA driver** — the entitlement-gated **buildtest** matrix
  `tests/aws_ena-driver/*` (`ena-driver-releases.json` of 70 versions, the E2'
  build matrix, a read-only load-readiness `verify-ena-buildresults.sh`, generated
  `RESULTS`) and the tiers `t010`/`t011`.
* ✅ **Phase 6 — EOL / constrained majors** — `lib/os-profile.sh`, the canonical
  per-major OS profile, the cross-consistency tier `t012`, and a generated
  `tests/os-coverage/RESULTS-coverage.md`.
* ✅ **Phase 7 — generalization** — the framework is now **tool-agnostic**:
  `tests/conformance/check-tool-contract.sh` machine-enforces the SPEC §10 (a–e)
  contract (tier `t013`), `lib/pkg-availability.sh` is the §12 classification
  canon (tier `t014`), and [ADDING-A-TOOL.md](./ADDING-A-TOOL.md) is the bilingual
  guide for tool #2. **Suite green: 15 tiers, 415 passed, 0 failed.**

**All seven implementation phases are complete** (plus r08, which restored the
model's two-layer structure: project-root `install-aws_*.sh` installers - each with
per-RHEL-major validated version pins - that the matrices kick with parameters). What remains is the live
empirical fill — R5 (live pull), R6 (AWS CLI install), R7 (SSM install, both init
modes), R8 (ENA build on an entitled host; load is L4) — which runs on a
container-egress / entitled / Nitro host. The models, generators, verifiers, and
the tool contract are hermetic and green in-sandbox. See [SPEC.md](./SPEC.md) §10.

---

## License

See the repository [LICENSE](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE).
