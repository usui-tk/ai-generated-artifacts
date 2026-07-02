#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   L1 unit: the install scripts' introspection
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; hermetic (no network); shellcheck only for t002.
# ----- Usage examples -------------------------------------------------------
#   bash tests/t016_installintrospect.sh
#   bash tests/run-all.sh   # runs every tier
# ----- Known limitations ----------------------------------------------------
#   Asserts count failures and continue (harness scope, spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/t016_installintrospect.sh - L1 unit: the install scripts' introspection
# and structured-result machinery (r09 / parity items B1-B6).
#
# Each probe runs `<TOOL>_LIB_ONLY=1 bash -c '...'` so the install script is
# sourced (defines helpers, installs nothing) in a clean child whose environment
# carries the test-mode flags; the helper code lives in the bash -c string.
#   B3 awscli: measure_min_glibc (max GLIBC_x.y across the bundle .so's),
#              detect_bundled_python (from the libpython filename)
#   B6 ena:    ko_module_version (modinfo/strings version of a built ena.ko)
#   B1/B2:     die emits a single-line {"status":"fail",...,"reason":...} result
#              in test mode (so the matrix always records a parseable, reasoned row)
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"

AWSCLI="${PROJ}/install-aws_awscli-v2.sh"
SSM="${PROJ}/install-aws_ssm-agent.sh"
ENA="${PROJ}/install-aws_ena-driver.sh"
for s in "${AWSCLI}" "${SSM}" "${ENA}"; do
  [ -f "${s}" ] || { t_fail "missing install script: ${s}"; t_done; exit; }
done

# shellcheck disable=SC2016  # $1 is a bash -c positional, intentionally not expanded here
SRC='. "$1" 2>/dev/null;'   # source the install script lib-only ($1), then run the rest

# --- B3: AWS CLI bundle introspection ---------------------------------------
bundle="$(mktemp -d)"; mkdir -p "${bundle}/aws/dist"
printf 'x GLIBC_2.17 y GLIBC_2.28 z GLIBC_2.5\n' > "${bundle}/aws/dist/libcrypto.so.3"
: > "${bundle}/aws/dist/libpython3.11.so.1.0"
mg="$(AWSCLI_LIB_ONLY=1 bash -c "${SRC} measure_min_glibc \"\$2\"" _ "${AWSCLI}" "${bundle}")"
bp="$(AWSCLI_LIB_ONLY=1 bash -c "${SRC} detect_bundled_python \"\$2\"" _ "${AWSCLI}" "${bundle}")"
assert_eq "2.28" "${mg}" "measure_min_glibc -> max GLIBC across .so's (2.28)"
assert_eq "3.11" "${bp}" "detect_bundled_python -> 3.11 from libpython filename"
rm -rf "${bundle}"

empty="$(mktemp -d)"; mkdir -p "${empty}/aws"
mg0="$(AWSCLI_LIB_ONLY=1 bash -c "${SRC} measure_min_glibc \"\$2\"" _ "${AWSCLI}" "${empty}")"
assert_eq "" "${mg0}" "measure_min_glibc on a bundle with no .so -> empty"
rm -rf "${empty}"

# --- B6: ENA built-module version (false-success guard input) ----------------
kod="$(mktemp -d)"; printf 'noise\nversion=2.9.1\nnoise\n' > "${kod}/ena.ko"
kov="$(ENA_LIB_ONLY=1 bash -c "${SRC} ko_module_version \"\$2\"" _ "${ENA}" "${kod}/ena.ko")"
assert_eq "2.9.1" "${kov}" "ko_module_version -> version string from the built ena.ko"
rm -rf "${kod}"

# --- B1/B2: die emits one {"status":"fail",...} result in test mode ----------
awscli_fail="$(AWSCLI_LIB_ONLY=1 AWSCLI_INSTALLTEST=1 bash -c "${SRC} RESULT_EMITTED=0; OSMAJOR=8; die boom-awscli" _ "${AWSCLI}" 2>/dev/null)"
assert_eq 1 "$(printf '%s\n' "${awscli_fail}" | grep -c '\[aws_awscli-v2\]\[installtest\]\[result\]')" "awscli die emits exactly one [result] line"
assert_eq 1 "$(printf '%s' "${awscli_fail}" | grep -c '"status":"fail"')" "awscli die result has status:fail"
assert_eq 1 "$(printf '%s' "${awscli_fail}" | grep -c '"reason":"boom-awscli"')" "awscli die result carries the reason"

ssm_fail="$(SSM_LIB_ONLY=1 SSM_INSTALLTEST=1 bash -c "${SRC} RESULT_EMITTED=0; OSMAJOR=6; die boom-ssm" _ "${SSM}" 2>/dev/null)"
assert_eq 1 "$(printf '%s' "${ssm_fail}" | grep -c '"status":"fail"')" "ssm die result has status:fail"

ena_fail="$(ENA_LIB_ONLY=1 ENA_INSTALLTEST=1 bash -c "${SRC} RESULT_EMITTED=0; OSMAJOR=7; die boom-ena" _ "${ENA}" 2>/dev/null)"
assert_eq 1 "$(printf '%s' "${ena_fail}" | grep -c '"status":"fail"')" "ena die result has status:fail"

# die must NOT emit a [result] in production mode (INSTALLTEST=0)
prod_quiet="$(AWSCLI_LIB_ONLY=1 AWSCLI_INSTALLTEST=0 bash -c "${SRC} RESULT_EMITTED=0; die boom" _ "${AWSCLI}" 2>/dev/null)"
assert_eq 0 "$(printf '%s' "${prod_quiet}" | grep -c 'installtest\]\[result\]')" "die is silent on [result] in production mode"

# --- presence of the parity helpers (sourced lib-only) ----------------------
assert_eq yes "$(AWSCLI_LIB_ONLY=1 bash -c "${SRC} declare -F block_awscli_v1 >/dev/null && printf yes || printf no" _ "${AWSCLI}")" "awscli defines block_awscli_v1 (B4 versionlock)"
assert_eq yes "$(SSM_LIB_ONLY=1 bash -c "${SRC} declare -F enable_for_boot >/dev/null && printf yes || printf no" _ "${SSM}")" "ssm defines enable_for_boot (B5 systemd/chkconfig/upstart)"
assert_eq yes "$(ENA_LIB_ONLY=1 bash -c "${SRC} declare -F dump_build_diag >/dev/null && printf yes || printf no" _ "${ENA}")" "ena defines dump_build_diag (B6 build diagnostics)"

t_done
