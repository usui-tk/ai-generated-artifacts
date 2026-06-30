# Adding a tool

English | [日本語](./ADDING-A-TOOL.ja.md)

This suite is **tool-agnostic**: each tool lives in `tests/<vendor>_<tool>/` and
implements the same contract (the framework, SPEC §10 a–e). The conformance
checker `tests/conformance/check-tool-contract.sh` enforces it, and
`tests/t013_toolcontract.sh` fails the suite if a tool is non-conformant. Adding a
non-AWS tool #2 is therefore a fill-in-the-blanks exercise.

## 1. Name it (SPEC §14)

`<vendor>_<tool>`: vendor boundary is `_`, within-tool words are `-`. Examples:
`azure_az-cli`, `gcp_gcloud-cli`, `hashicorp_terraform`, `util_jq`, `k8s_kubectl`.
Record the new name in SPEC.md's naming vocabulary.

## 2. Classify the acquisition source (SPEC §12, `lib/pkg-availability.sh`)

Decide where the tool's primary input comes from and add it to
`pkgavail_tool_source` / `pkgavail_class`:

| class | meaning | anonymous story |
|:--|:--|:--|
| `anonymous-ubi` | the `ubi-*` repos (7 also optional/extras/RHSCL) | installable |
| `entitled-only` | `rhel-*` repos (kernel-devel, …) | `needs-entitlement` |
| `epel` | Fedora EPEL (dkms, …), pinned, off by default | `epel-optional` |
| `vendor-hosted` | outside any repo (a bundle / S3 RPM) over the vendor CDN | installable |
| `base-image` | already present in the base image | installable |

`pkgavail_anonymous_status "$(pkgavail_class "$(pkgavail_tool_source <name>)")"`
then answers "what happens anonymously?" in one call.

## 3. Implement the contract (SPEC §10, (0) + a–e)

- **(0)** a project-root **`install-<vendor>_<tool>.sh`** (name matches the test
  folder) — a real-host-usable installer with a test mode (`<TOOL>_INSTALLTEST=1`)
  that installs/builds in a disposable rootfs, smoke-checks, and emits one
  `[<vendor>_<tool>][installtest][result] {json}` line of **raw facts** (ran /
  installed / built + context). Production mode installs on the real host. Carry
  **per-RHEL-major version pins** (the validated version per major) resolved in
  `resolve_version` as the production default; an explicit `<TOOL>_VERSION` wins,
  and the matrix passes one in test mode. Add a `<TOOL>_LIB_ONLY=1` guard so the
  pins are unit-testable (see `tests/t015_installpins.sh`).

Create `tests/<vendor>_<tool>/` with:

- **(a)** `list-<tool>-releases.sh` → a deterministic `<tool>-releases.json`
  (enumerate versions from an auth-free source; carry reuse-by-copy helpers).
- **(b)** `run-<tool>-{install,build}test-matrix.sh` with **column-0 pure helpers**
  (a version compare, a per-major map, an in-scope filter, and a `*_verdict()`),
  a `--run` L3 loop that **kicks the root install script** (`podman run -v
  <install-script>:... -e <TOOL>_INSTALLTEST=1 -e <PARAMS> <ref> ...`), parses the
  `[result]` with `result_field`, applies the verdict, and records; plus a
  hermetic `--generate-results`. Install logic is never inlined here.
- **(c)** `<tool>-…-ledger.json` with a schema'd, initially-empty `"results": []`.
- **(d)** `RESULTS-rhel{6,7,8,9,10}.md` produced by `--generate-results`
  (never hand-edited).
- **(e)** `tests/t0NN_<tool>verdict.sh` that loads the matrix's pure helpers by
  name and asserts them table-driven, plus the matrix/lister reuse-by-copy.

Reuse the canon: `lib/os-profile.sh` for per-major facts (glibc via the tool's
own table, image, pull constraint, repos, lifecycle, EPEL) and
`lib/acquire-rootfs.sh` for init-mode-aware acquisition.

## 4. Verify

```sh
bash tests/run-all.sh                              # all tiers incl. the new one
bash tests/conformance/check-tool-contract.sh      # contract conformance
```

`check-tool-contract.sh` must list the new tool as `ok` (it requires the root
`install-<vendor>_<tool>.sh` to exist, be executable, and be **kicked** by the
matrix), and `t013` must stay green. Keep every script ShellCheck-`style`-clean
(markdown backticks in `printf` formats as `\140`) and all files LF.
