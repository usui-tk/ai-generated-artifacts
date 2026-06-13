#!/usr/bin/env bash
#==============================================================================
# tests/t13_enaledgerguard.sh - ENA matrix ledger writer: version-mismatch guard
#                               (layer L1, defense-in-depth for the false-ok bug)
#
# The matrix records install-ena-driver.sh's [result] verbatim. Even with the
# installer hardened (t12), the ledger keeps an INDEPENDENT guard: an "ok" whose
# installed ko_version does not match the requested ena_version (e.g. a stale
# installer that fell back to the stock in-tree ena.ko 1.1.2) is downgraded to
# "fail" before it can enter the ledger -- otherwise it would poison the report
# and the kver-primary dedup gate (the bad combo would be skipped forever).
#
# This tier extracts the real ledger-writer Python out of the matrix script and
# drives it with a synthetic results TSV, then asserts the recorded statuses.
# Host-runnable, self-contained (python3 only; no container, no dkms, no build).
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
MATRIX="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Extract ONLY the ledger-writer heredoc (its opener carries RESULTS_TSV + <<PY;
# the body runs to the next column-0 PY). The script has several PY heredocs, so
# anchor on this specific opener rather than the first one.
awk '/RESULTS_TSV.*<<.PY/{f=1;next} f&&/^PY$/{exit} f' "${MATRIX}" > "${WORK}/writer.py"
if [ ! -s "${WORK}/writer.py" ] || ! grep -q '^import json' "${WORK}/writer.py"; then
  t_fail "could not extract the ledger-writer Python from run-ena-buildtest-matrix.sh"
  t_done
  exit
fi

# Synthetic results: a true ok, the exact false-ok (stock 1.1.2 for a 2.12.0
# request), a genuine fail, and a true ok with a 'g'-suffixed version.
mkdir -p "${WORK}/res"
{
  printf '6\t2.9.1\t{"status":"ok","osmajor":"6","ena_version":"2.9.1","kver":"k","dkms":1,"ko":"x","ko_version":"2.9.1g"}\n'
  printf '6\t2.12.0\t{"status":"ok","osmajor":"6","ena_version":"2.12.0","kver":"k","dkms":1,"ko":"x","ko_version":"1.1.2"}\n'
  printf '6\t2.4.0\t{"status":"fail","osmajor":"6","ena_version":"2.4.0","kver":"k","reason":"patch did not apply"}\n'
  printf '6\t2.8.6\t{"status":"ok","osmajor":"6","ena_version":"2.8.6","kver":"k","dkms":1,"ko":"x","ko_version":"2.8.6g"}\n'
} > "${WORK}/r.tsv"

if ! python3 "${WORK}/writer.py" "${WORK}/ledger.json" "${WORK}/r.tsv" "${WORK}/res" >/dev/null 2>"${WORK}/err"; then
  t_fail "ledger writer failed to run: $(cat "${WORK}/err")"
  t_done
  exit
fi

field_of() {  # field_of <ena_version> <key>
  python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
e=next((x for x in d['entries'] if x['ena_version']==sys.argv[2]), None)
print(e.get(sys.argv[3]) if e else 'MISSING')" "${WORK}/ledger.json" "$1" "$2"
}

assert_eq "ok"   "$(field_of 2.9.1  status)" "true ok (ko_version 2.9.1g matches) -> stays ok"
assert_eq "ok"   "$(field_of 2.8.6  status)" "true ok ('g'-suffixed 2.8.6g matches) -> stays ok"
assert_eq "fail" "$(field_of 2.12.0 status)" "false ok (stock 1.1.2 for a 2.12.0 request) -> downgraded to fail"
assert_eq "fail" "$(field_of 2.4.0  status)" "genuine fail -> stays fail"
assert_match "$(field_of 2.12.0 reason)" "does not match requested 2\.12\.0" "downgraded row carries an explanatory reason"

t_done
