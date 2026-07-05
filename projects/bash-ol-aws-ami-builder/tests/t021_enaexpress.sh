#!/usr/bin/env bash
#==============================================================================
# tests/t021_enaexpress.sh - ENA Express readiness classification (pure logic)
#
# ena_express_verdict classifies an ENA driver version against AWS's documented
# ENA Express driver-version floors (ena-express.html): < 2.2.9 -> not-ready,
# >= 2.2.9 -> bandwidth-only (full bandwidth, no ena_srd_* metrics),
# >= 2.8.0 -> express-ready (both). It is a driver-capability signal only
# (necessary, not sufficient -- ENA Express is an AWS API ENI attribute).
#
# The classification lives in THREE reuse-by-copy implementations that this
# tier keeps in behavioural agreement across a boundary-version set:
#   (1) install-ena-driver.sh  ena_express_verdict()   [the source of truth]
#   (2) tests/ena/list-ena-releases.sh ena_express_verdict()  [lister copy]
#   (3) run-ena-buildtest-matrix.sh's ledger-merge Python express_verdict()
#       [report/enrichment duplicate]
# It also asserts the release-list snapshot's ENA-Express-era schema (1.2):
# min_version present, every entry carries ge_min + express_verdict, and the
# recorded ge_min agrees with min_version. Pure and host-runnable (python3
# only for (3)); no container, no network, no build.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
INST="${PROJ}/install-ena-driver.sh"
LISTER="${PROJ}/tests/ena/list-ena-releases.sh"
MATRIX="${PROJ}/tests/ena/run-ena-buildtest-matrix.sh"
RELEASES="${PROJ}/tests/ena/ena-driver-releases.json"

# The boundary set every implementation must classify identically. Covers: the
# empty/unknown shape, both floor edges (2.2.9 / 2.8.0) and their predecessors,
# mid-range members of each class, the stock in-tree 1.1.2, and a far-future
# major so the compare is proven numeric (not lexicographic).
CASES=(
  ":unknown"
  "1.1.2:not-ready"
  "2.2.8:not-ready"
  "2.2.9:bandwidth-only"
  "2.5.0:bandwidth-only"
  "2.7.9:bandwidth-only"
  "2.8.0:express-ready"
  "2.9.1:express-ready"
  "2.17.0:express-ready"
  "10.0.0:express-ready"
)

# ---- (1) installer copy (the source of truth) -------------------------------
# shellcheck disable=SC1090
. <(sed -n '/^_ena_ver_ge()/,/^}/p'        "${INST}")
# shellcheck disable=SC1090
. <(sed -n '/^ena_express_verdict()/,/^}/p' "${INST}")
if declare -F ena_express_verdict >/dev/null 2>&1; then
  for c in "${CASES[@]}"; do
    v="${c%%:*}"; want="${c#*:}"
    assert_eq "${want}" "$(ena_express_verdict "${v}")" \
      "installer ena_express_verdict('${v}') = ${want}"
  done
  # Keep the installer verdicts for the cross-copy agreement below. Bash
  # associative arrays reject an empty subscript, so the empty-version case
  # is stored under a sentinel key.
  declare -A INST_VERDICT=()
  for c in "${CASES[@]}"; do
    v="${c%%:*}"; INST_VERDICT["${v:-__empty__}"]="$(ena_express_verdict "${v}")"
  done
else
  t_fail "could not load ena_express_verdict from install-ena-driver.sh"
fi

# ---- (2) lister copy: behavioural agreement with the installer --------------
# Rename on load so both copies coexist; the lister uses ver_ge (its own
# reuse-by-copy of the matrix compare), loaded under a suffixed name too.
# shellcheck disable=SC1090
. <(sed -n '/^ver_ge()/,/^}/p' "${LISTER}" | sed 's/^ver_ge()/ver_ge_list()/')
# shellcheck disable=SC1090
. <(sed -n '/^ena_express_verdict()/,/^}/p' "${LISTER}" \
      | sed 's/^ena_express_verdict()/ena_express_verdict_list()/; s/ver_ge /ver_ge_list /g')
if declare -F ena_express_verdict_list >/dev/null 2>&1 && [ "${#INST_VERDICT[@]}" -gt 0 ]; then
  for c in "${CASES[@]}"; do
    v="${c%%:*}"
    assert_eq "${INST_VERDICT["${v:-__empty__}"]}" "$(ena_express_verdict_list "${v}")" \
      "lister copy agrees with the installer for '${v}'"
  done
else
  t_fail "could not load ena_express_verdict from list-ena-releases.sh"
fi

# ---- (3) matrix ledger-merge Python duplicate: agreement --------------------
# Extract the ledger-writer heredoc exactly as t013 does, drive it with one
# fail row per boundary version (no ena_express in the input -> the writer's
# enrichment must compute it), and compare the recorded classification.
if command -v python3 >/dev/null 2>&1; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "${WORK}"' EXIT
  awk '/RESULTS_TSV.*<<.PY/{f=1;next} f&&/^PY$/{exit} f' "${MATRIX}" > "${WORK}/writer.py"
  if [ -s "${WORK}/writer.py" ]; then
    : > "${WORK}/rows.tsv"
    for c in "${CASES[@]}"; do
      v="${c%%:*}"; [ -n "${v}" ] || continue   # the writer keys rows on a version
      printf '9\t%s\t{"status":"fail","osmajor":"9","ena_version":"%s","kver":"k1","reason":"x"}\n' \
        "${v}" "${v}" >> "${WORK}/rows.tsv"
    done
    printf '{"entries": []}' > "${WORK}/ledger.json"
    mkdir -p "${WORK}/out"
    if python3 "${WORK}/writer.py" "${WORK}/ledger.json" "${WORK}/rows.tsv" "${WORK}/out" >/dev/null 2>&1; then
      for c in "${CASES[@]}"; do
        v="${c%%:*}"; [ -n "${v}" ] || continue
        got="$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(next(e['ena_express'] for e in d['entries'] if e['ena_version']==sys.argv[2]))" \
          "${WORK}/ledger.json" "${v}" 2>/dev/null || printf '(missing)')"
        assert_eq "${INST_VERDICT["${v:-__empty__}"]}" "${got}" \
          "matrix Python duplicate agrees with the installer for '${v}'"
      done
    else
      t_fail "ledger-writer Python run failed (see t013 for the extraction contract)"
    fi
  else
    t_fail "could not extract the ledger-writer Python from run-ena-buildtest-matrix.sh"
  fi
else
  t_skip "python3 not available -- matrix Python agreement not checked"
fi

# ---- release-list snapshot: ENA-Express-era schema invariants ---------------
if [ -f "${RELEASES}" ] && command -v python3 >/dev/null 2>&1; then
  out="$(python3 - "${RELEASES}" <<'PY' 2>/dev/null || printf 'ERROR'
import json, sys
d = json.load(open(sys.argv[1]))
vs = d.get("versions", [])
def vkey(s):
    return [int(p) if p.isdigit() else 0 for p in str(s).replace("-", ".").split(".")]
mn = d.get("min_version", "")
problems = []
if d.get("schema_version") != "1.2": problems.append("schema!=1.2")
if not mn: problems.append("no min_version")
for v in vs:
    if "ge_min" not in v or "express_verdict" not in v:
        problems.append("missing fields @ %s" % v.get("version")); break
    if mn and v["ge_min"] != (vkey(v["version"]) >= vkey(mn)):
        problems.append("ge_min disagrees with min_version @ %s" % v["version"]); break
print("OK" if not problems else ";".join(problems))
PY
)"
  assert_eq "OK" "${out}" "ena-driver-releases.json carries the 1.2 schema (min_version + per-entry ge_min/express_verdict, mutually consistent)"
else
  t_skip "release list or python3 unavailable -- snapshot schema not checked"
fi

# ---- matrix default-scope plumbing (structural) ------------------------------
if grep -Eq -- '--full\)\s+FULL=1' "${MATRIX}"; then
  t_pass "matrix registers --full (lift the sweep floor)"
else
  t_fail "matrix does not register --full"
fi
if grep -q 'min_version' "${MATRIX}" && grep -q 'ENA_MIN_VERSION:-2.8.0\|2\.8\.0' "${MATRIX}"; then
  t_pass "matrix reads the default floor from the release list's min_version (2.8.0 fallback)"
else
  t_fail "matrix default floor plumbing (min_version / 2.8.0) not found"
fi
if grep -Eq -- '--report-only\)\s+REPORT_ONLY=1' "${MATRIX}"; then
  t_pass "matrix registers --report-only (build-free report regeneration)"
else
  t_fail "matrix does not register --report-only"
fi

t_done
