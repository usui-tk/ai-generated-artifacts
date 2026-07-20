#!/usr/bin/env bash
#==============================================================================
# tests/t024_ol5awscli.sh - OL5 AWS CLI v2 wiring + awscli ledger merge (L0/L1)
#
# Pins the user-adjudicated OL5 integration of the AWS CLI install-test
# (2026-07-18) against regressions:
#
#  (A) install-awscli.sh: the OL5 branch is opt-in and host-staged (EL5 has no
#      in-guest TLS 1.2 path); the ceiling pin is 2.17.51 = the OL6 pin (the
#      2.17.52 Python 3.12 rebase jumps the bundle glibc floor 2.5 -> 2.17 --
#      measured); the kver record travels via the AWSCLI_OL5_KVER contract
#      (probed, not provisioned); NO W1 wrapper ships (re-adjudicated after
#      the /proc evidence correction -- the mechanism can never fire under the
#      matrix/instance execution model); shared-code EL5 safety (no `sed -E`;
#      the kver `sort -V` stderr is silenced).
#  (B) run-awscli-installtest-matrix.sh: OL5 never in the default OL set,
#      pin_for(5), --ol 5 acceptance, the staging + probe section, and the
#      merge-mode usage.
#  (C) --merge-from: the three adjudicated conflict-policy cases, hermetic
#      (python3 only; fixtures on this matrix dedup key).
#
# Host-runnable, self-contained: bash + grep + python3; no container, no
# network, no build.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
INST="${PROJ}/install-awscli.sh"
MATRIX="${PROJ}/tests/awscli/run-awscli-installtest-matrix.sh"

inst="$(cat "${INST}")"
mtx="$(cat "${MATRIX}")"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# ---- (A) installer -----------------------------------------------------------
assert_match "${inst}" '^AWSCLI_VERSION_OL5="\$\{AWSCLI_VERSION_OL5:-2\.17\.51\}"$' \
  "installer: OL5 ceiling pin defaults to 2.17.51 (= the OL6 pin; measured 2.17.52 glibc wall)"
assert_match "${inst}" '^    5\) awscli_version="\$\{AWSCLI_VERSION_OL5\}" ;;$' \
  "installer: per-OL default case dispatches 5"
assert_match "${inst}" 'AWSCLI_INSTALLTEST: unzip not present in the OL5 clean-core' \
  "installer: OL5 asserts (never installs) the clean-core unzip"
assert_match "${inst}" 'if \[\[ "\$\{osmajor\}" != "5" \]\]; then' \
  "installer: the in-guest kernel-uek/unzip yum provisioning is bypassed on OL5"
assert_match "${inst}" 'AWSCLI_OL5_KVER' \
  "installer: the OL5 kver env contract exists (probed, not provisioned)"
assert_match "${inst}" 'OL5 bundle not pre-staged at' \
  "installer: the OL5 bundle pre-stage contract is enforced"

# NO W1 (re-adjudicated): neither the wrapper mechanism nor a w1 result field.
if grep -qE 'w1_applied|"w1"' "${INST}"; then
  t_fail "installer: no W1 wrapper mechanism ships (re-adjudicated after the /proc correction)"
else
  t_pass "installer: no W1 wrapper mechanism ships (re-adjudicated after the /proc correction)"
fi

# EL5-guest safety in SHARED code: no `sed -E` anywhere (EL5 sed 4.1.5 has no
# -E and its usage error kills the install under set -e; rationale comments
# legitimately NAME it, so comment lines are excluded); the kver sort -V is
# stderr-silenced.
if grep -v '^\s*#' "${INST}" | grep -qE 'sed -E'; then
  t_fail "installer: no sed -E remains (EL5 sed 4.1.5 killed the install here)"
else
  t_pass "installer: no sed -E remains (EL5 sed 4.1.5 killed the install here)"
fi
assert_match "${inst}" 'sort -V 2>/dev/null \| tail -1 \|\| true' \
  "installer: the kver sort -V is stderr-silenced (EL5 coreutils 5.97 noise)"

# ---- (B) matrix --------------------------------------------------------------
assert_match "${mtx}" '^OL_LIST="6 7 8"$' \
  "matrix: the DEFAULT OL set stays 6-8 (OL5 is opt-in only)"
# The literal \$1 is the match-target text, not a shell expansion.
# shellcheck disable=SC2016
assert_match "${mtx}" 'case "\$1" in 5\|6\|7\|8\) echo 2\.17\.51 ;;' \
  "matrix: pin_for(5) = 2.17.51"
assert_match "${mtx}" 'case "\$\{ol\}" in 5\|6\|7\|8\)' \
  "matrix: the test loop accepts --ol 5"
assert_match "${mtx}" '^OL5_UEK_FALLBACK_KVER="2\.6\.39-400\.297\.3\.el5uek\.x86_64"$' \
  "matrix: the OL5 kver probe carries the pinned terminal fallback"
assert_match "${mtx}" 'ol5_stage_zip\(\)' \
  "matrix: the OL5 host-side bundle staging function exists"
assert_match "${mtx}" "AWSCLI_OL5_KVER='\\\$\{ol5kv\}'" \
  "matrix: run_one passes the probed kver through the env contract"
assert_match "${mtx}" '--merge-from <path>' \
  "matrix: usage documents --merge-from"
assert_match "${mtx}" '^    export TMPDIR=/tmp$' \
  "matrix: the guest chroot env pins TMPDIR=/tmp (host TMPDIR must never leak into the guest)"
assert_match "${mtx}" 'OL5 is an install-test / PoC scoped, opt-in target' \
  "matrix: RESULTS-ol5.md carries the OL5 scope paragraph"

# ---- (C) merge mode: hermetic functional check -------------------------------
mk_row() { # ver status ran
  printf '{"osmajor":"5","awscli_version":"%s","kver":"k1","test_host_kernel":"h","glibc":"2.5","bundled_python":"3.11","min_glibc_measured":"2.5","min_glibc":"2.5","python_eol":"x","status":"%s","ran":%s,"installed_version":"","run_method":"","reason":""}' "$1" "$2" "$3"
}
printf '{"schema_version":"1.0","ledger_type":"awscli-installtest","entries":[%s]}\n' "$(mk_row 2.17.51 ok true)" > "${WORK}/base.json"
printf '{"schema_version":"1.0","ledger_type":"awscli-installtest","entries":[%s,%s]}\n' "$(mk_row 2.13.0 ok true)" "$(mk_row 2.17.51 ok true)" > "${WORK}/theirs_a.json"
printf '{"schema_version":"1.0","ledger_type":"awscli-installtest","entries":[%s]}\n' "$(mk_row 2.17.51 fail false)" > "${WORK}/theirs_b.json"

cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r1" --merge-from "${WORK}/theirs_a.json" 2>&1)"
rc=$?
assert_rc 0 "${rc}" "merge C1: adopt + same-status merge succeeds"
assert_match "${out}" 'MERGED adopted=1 same-status-kept=1' \
  "merge C1: one key adopted, one same-status kept"
n_rows="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['entries']))" "${WORK}/led.json")"
assert_eq "2" "${n_rows}" "merge C1: merged ledger has 2 rows"

cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r2" --merge-from "${WORK}/theirs_b.json" 2>&1)"
rc=$?
if [ "${rc}" -ne 0 ]; then
  t_pass "merge C2: same-key different-status is a hard error (rc=${rc})"
else
  t_fail "merge C2: same-key different-status is a hard error (got rc=0)"
fi
assert_match "${out}" 'merge conflict: OL5 awscli 2\.17\.51' \
  "merge C2: the conflicting key is named"
st="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['entries'][0]['status'])" "${WORK}/led.json")"
assert_eq "ok" "${st}" "merge C2: the base ledger is left untouched on the error path"

cp "${WORK}/base.json" "${WORK}/led.json"
out="$(bash "${MATRIX}" --ledger "${WORK}/led.json" --results-dir "${WORK}/r3" --merge-from "${WORK}/theirs_b.json" --merge-prefer theirs 2>&1)"
rc=$?
assert_rc 0 "${rc}" "merge C3: --merge-prefer theirs resolves the conflict"
st="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['entries'][0]['status'])" "${WORK}/led.json")"
assert_eq "fail" "${st}" "merge C3: theirs status replaces ours"

# record #7 pins: the real-guest first contact of the awscli hook
inst="$(cat "${INST}")"
assert_match "${inst}" "rpm -q --qf '%\{VERSION\}.n' glibc" "installer: glibc read is multilib-safe (newline qf; two glibc arches concatenated to 2.52.5 on the real guest without it)"
assert_match "${inst}" 'sort -u | head -1' "installer: multilib duplicate versions collapse to one value"
assert_match "${inst}" 'command -v unzip' "installer: unzip is pre-asserted before the bundle unpack (ISO minimal guest has no unzip; ks %packages supplies it)"
assert_match "${inst}" 'kickstart %packages contract; see SPEC D.32 record #7' "installer: the unzip die message names the supplying contract"

t_done
