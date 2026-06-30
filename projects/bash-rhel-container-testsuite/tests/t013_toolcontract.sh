#!/usr/bin/env bash
#==============================================================================
# tests/t013_toolcontract.sh - L2: the tool-compatibility framework contract
#
# Asserts the design plan sec 10 (a-e) contract is enforceable and that the three
# shipped tools conform. Loads the pure helper from check-tool-contract.sh
# (CONTRACT_LIB_ONLY=1), checks it on the real tool dirs and on a synthetic
# incomplete dir, then runs the checker end-to-end and asserts exit 0.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
CHECKER="${PROJ}/tests/conformance/check-tool-contract.sh"

# shellcheck source=/dev/null
CONTRACT_LIB_ONLY=1 . "${CHECKER}"

if ! declare -F contract_dir_missing >/dev/null 2>&1; then
  t_fail "could not load contract_dir_missing from check-tool-contract.sh"
  t_done; exit
fi

# --- the three shipped tools conform (no missing artifacts) -----------------
for tool in aws_awscli-v2 aws_ssm-agent aws_ena-driver; do
  miss="$(contract_dir_missing "${PROJ}/tests/${tool}")"
  assert_eq "" "${miss}" "${tool} conforms to the framework contract (no missing artifacts)"
done

# --- a non-existent dir is reported, not crashed ----------------------------
assert_eq "no-such-dir" "$(contract_dir_missing "${PROJ}/tests/aws_does-not-exist")" \
  "missing dir -> 'no-such-dir'"

# --- a synthetic incomplete dir reports the gaps ----------------------------
td="$(mktemp -d)"
miss="$(contract_dir_missing "${td}")"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'lister')"       "empty dir: lister missing"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'releases.json')" "empty dir: releases.json missing"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'matrix')"       "empty dir: matrix missing"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'ledger')"       "empty dir: ledger missing"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'RESULTS-rhel6')" "empty dir: RESULTS-rhel6 missing"

# add a lister + releases.json only; the rest must still be reported missing
: > "${td}/list-foo-releases.sh"; chmod +x "${td}/list-foo-releases.sh"
: > "${td}/foo-releases.json"
miss="$(contract_dir_missing "${td}")"
assert_eq 0 "$(printf '%s' "${miss}" | grep -c 'lister')"        "with lister: lister no longer missing"
assert_eq 0 "$(printf '%s' "${miss}" | grep -c 'releases.json')" "with releases.json: no longer missing"
assert_eq 1 "$(printf '%s' "${miss}" | grep -c 'matrix')"        "still missing the matrix"
rm -rf "${td}"

# --- run the checker end-to-end (executes; asserts overall conformance) -----
if "${CHECKER}" >/dev/null 2>&1; then
  assert_eq 0 0 "check-tool-contract.sh exits 0 (all shipped tools conform)"
else
  t_fail "check-tool-contract.sh exited non-zero (a shipped tool is non-conformant)"
fi

t_done
