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

## 3. Implement the contract (SPEC §10 a–e)

Create `tests/<vendor>_<tool>/` with:

- **(a)** `list-<tool>-releases.sh` → a deterministic `<tool>-releases.json`
  (enumerate versions from an auth-free source; carry reuse-by-copy helpers).
- **(b)** `run-<tool>-{install,build}test-matrix.sh` with **column-0 pure helpers**
  (a version compare, a per-major map, an in-scope filter, and a `*_verdict()`),
  a `--run` L3 loop (acquire → install/build → smoke → record), and a hermetic
  `--generate-results`.
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

`check-tool-contract.sh` must list the new tool as `ok`, and `t013` must stay
green. Keep every script ShellCheck-`style`-clean (markdown backticks in `printf`
formats as `\140`) and all files LF.
