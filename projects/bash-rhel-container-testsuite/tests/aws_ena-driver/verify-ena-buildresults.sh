#!/usr/bin/env bash
# verify-ena-buildresults.sh - standalone, READ-ONLY verification of the ENA
# build-test matrix's results. It NEVER builds and NEVER touches the build path:
# it reads the matrix ledger (buildtest-ledger.json) plus a small verification
# bundle the build side preserved, and emits its OWN load-readiness report.
# Composes as a separate pass:  build -> verify  (re-runnable offline).
#
# Bundle contract (all small; the build side preserves these with a dumb copy):
#   <bundle>/modules/rhel<N>-ena_<ver>-<kver>.ko   (per built version)
#   <bundle>/kver/<kver>/Module.symvers            (shared per kver)
#   <bundle>/kver/<kver>/kernel.vermagic           (shared per kver; target kernel vermagic)
#
# Per OK ledger row (load-readiness, since real load is L4 on Nitro):
#   L4a vermagic-match    GATE  ko vermagic == kernel vermagic (else would not insmod)
#   L4b symbol-crc-kabi   GATE  every required symbol present + CRC-match in Module.symvers
#   L5  module-load       SKIP  real load needs Nitro hardware (always L4)
# A MISSING bundle artifact for an OK row is a FAIL (load_ready unknown), never a
# silent skip - the no-false-ok discipline.
#
# The pure verdict helpers below are unit-tested in tests/t011_enaverify.sh; the
# tier sources this file with ENA_LIB_ONLY=1 so only the helpers load.
set -uo pipefail

# ---- pure verdict helpers (no I/O; column-0 for sed extraction) --------------

# ena_vermagic_verdict <ko_vermagic> <expected_vermagic>
#   rc 0 + "ok" if they match (trailing whitespace ignored); else rc 1 + reason.
ena_vermagic_verdict() {
  local a b
  a="$(printf '%s' "${1:-}" | sed 's/[[:space:]]*$//')"
  b="$(printf '%s' "${2:-}" | sed 's/[[:space:]]*$//')"
  if [ -z "${a}" ]; then printf 'no module vermagic'; return 1; fi
  if [ -z "${b}" ]; then printf 'no expected vermagic'; return 1; fi
  if [ "${a}" = "${b}" ]; then printf 'ok'; return 0; fi
  printf 'vermagic "%s" != expected "%s"' "${a}" "${b}"; return 1
}

# ena_symbols_verdict <dump_text> <symvers_text>
#   dump_text   : lines "<crc> <symbol>"                 (required symbols)
#   symvers_text: lines "<crc> <symbol> <mod> <export>"  (kernel Module.symvers)
#   rc 0 + "ok <n>" if every required symbol is present with a matching CRC;
#   else rc 1 + counts.
ena_symbols_verdict() {
  local dump="${1:-}" symvers="${2:-}" ok=0 bad=0 miss=0 crc sym kc
  local -A KCRC=()
  if [ -z "${dump}" ]; then printf 'no required-symbol list'; return 1; fi
  if [ -z "${symvers}" ]; then printf 'no Module.symvers'; return 1; fi
  while read -r crc sym _; do [ -n "${sym:-}" ] && KCRC["${sym}"]="${crc}"; done <<EOF
${symvers}
EOF
  while read -r crc sym _; do
    [ -n "${sym:-}" ] || continue
    kc="${KCRC[${sym}]:-}"
    if [ -z "${kc}" ]; then miss=$(( miss + 1 ))
    elif [ "${kc}" = "${crc}" ]; then ok=$(( ok + 1 ))
    else bad=$(( bad + 1 )); fi
  done <<EOF
${dump}
EOF
  if [ "${bad}" -eq 0 ] && [ "${miss}" -eq 0 ]; then printf 'ok %d' "${ok}"; return 0; fi
  printf '%d crc-mismatch / %d missing (of %d)' "${bad}" "${miss}" "$(( ok + bad + miss ))"; return 1
}

# ---- the rest runs only when executed (not when sourced for unit tests) ------
[ "${ENA_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER="${SCRIPT_DIR}/buildtest-ledger.json"; BUNDLE="${SCRIPT_DIR}/build-bundle"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --bundle) BUNDLE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [ -z "${LEDGER}" ] || [ ! -f "${LEDGER}" ]; then printf 'ledger not found: %s (run ./run-ena-buildtest-matrix.sh first)\n' "${LEDGER:-(unset)}" >&2; exit 2; fi
if [ -z "${BUNDLE}" ] || [ ! -d "${BUNDLE}" ]; then
  printf 'no build bundle at %s -> nothing to verify yet (load-readiness pending).\n' "${BUNDLE:-(unset)}" >&2
  printf 'Run the entitled build first (./run-ena-buildtest-matrix.sh on an entitled/Nitro-adjacent host); it preserves the ko + Module.symvers + vermagic bundle, then re-run verify.\n' >&2
  exit 0
fi

# Stream OK rows (built=true) from the ledger as TSV: osmajor<TAB>ena_version<TAB>kver
rows="$(python3 - "${LEDGER}" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception as e:
    sys.stderr.write("ledger parse error: %s\n"%e); sys.exit(3)
for r in d.get("results",[]):
    if r.get("built"):
        print("%s\t%s\t%s"%(r.get("osmajor",""),r.get("ena_version",""),r.get("kver","")))
PY
)"

n_rows=0; n_ready=0; n_notready=0
while IFS="$(printf '\t')" read -r os ver kver; do
  [ -n "${os}${ver}" ] || continue
  n_rows=$(( n_rows + 1 ))
  ko="${BUNDLE}/modules/rhel${os}-ena_${ver}-${kver}.ko"
  vm="${BUNDLE}/kver/${kver}/kernel.vermagic"
  if [ ! -f "${ko}" ] || [ ! -f "${vm}" ]; then
    printf '[verify][result] {"os":"%s","ena_version":"%s","kver":"%s","check":"bundle","status":"fail","detail":"missing artifact"}\n' "${os}" "${ver}" "${kver}"
    n_notready=$(( n_notready + 1 )); continue
  fi
  ko_vm="$(modinfo -F vermagic "${ko}" 2>/dev/null | head -1 || strings "${ko}" 2>/dev/null | sed -n 's/^vermagic=//p' | head -1)"
  if det="$(ena_vermagic_verdict "${ko_vm}" "$(cat "${vm}")")"; then
    printf '[verify][result] {"os":"%s","ena_version":"%s","kver":"%s","check":"vermagic","status":"ok","detail":"%s"}\n' "${os}" "${ver}" "${kver}" "${det}"
    n_ready=$(( n_ready + 1 ))
  else
    printf '[verify][result] {"os":"%s","ena_version":"%s","kver":"%s","check":"vermagic","status":"fail","detail":"%s"}\n' "${os}" "${ver}" "${kver}" "${det}"
    n_notready=$(( n_notready + 1 ))
  fi
done <<EOF
${rows}
EOF

printf 'verify summary: %d ok-rows, %d load-ready, %d not-ready\n' "${n_rows}" "${n_ready}" "${n_notready}" >&2
[ "${n_notready}" -eq 0 ]
