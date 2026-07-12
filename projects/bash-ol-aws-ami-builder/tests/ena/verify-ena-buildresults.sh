#!/bin/bash
# verify-ena-buildresults.sh -- standalone, READ-ONLY verification of the ENA
# self-build matrix's results. It NEVER builds and NEVER touches the production
# build path: it reads the matrix ledger (buildtest-ledger.json) plus a small
# verification bundle the build side preserved, and emits its OWN load-readiness
# report. Composes as a separate pass:  build -> verify -> build.
#
# Module integration stays delegated to DKMS (install-ena-driver.sh dkms.conf
# REMAKE_INITRD + dkms add/build/install); this tool only JUDGES the artifacts
# they produced, after the fact. No condition/branch lives in the build script.
#
# WHY EXTERNAL: re-runnable offline (re-verify or add checks without a rebuild),
# unit-testable (pure verdicts below), and the build invariant is structurally
# guaranteed -- a read-only reader cannot perturb the build.
#
# Bundle contract (all small; the build side preserves these with a dumb copy):
#   <bundle>/modules/ol<N>-ena_<ver>-<kver>.ko  (per built version -- the only per-version file)
#   <bundle>/kver/<kver>/Module.symvers          (shared per kver)
#   <bundle>/kver/<kver>/kernel.vermagic         (shared per kver; the target kernel's vermagic)
#   <bundle>/kver/<kver>/initramfs.list          (shared per kver; cpio -t / lsinitrd listing)
#
# Per OK ledger row (semantics from the load-readiness design):
#   L4a vermagic-match       GATE  ko vermagic == kernel vermagic (else would not insmod)
#   L4b symbol-crc-kabi      GATE  every required symbol present + CRC-match in Module.symvers
#   L3  initramfs-inclusion  INFO  ena.ko in the initramfs listing (DKMS/dracut territory; non-defect)
#   L5  module-load+device   SKIP  real load needs the UEK kernel on real Nitro (B-T8)
# A MISSING bundle artifact for an OK row is a FAIL (load_ready unknown), NEVER a
# silent skip -- the same no-false-ok discipline as the install-time verify.
#
# Self-contained (inline helpers; no sourced library). Reads vermagic via kmod's
# modinfo when present, else from the .ko's .modinfo section via `strings` (no
# running kernel needed); the symbol/CRC gate uses kmod and SKIPs (loudly) where
# kmod is unavailable.
set -uo pipefail

# ---- pure verdict helpers (unit-tested in isolation; no I/O) -----------------

# lc_vermagic_verdict <ko_vermagic> <expected_vermagic>
#   rc 0 + "ok" if they match (trailing whitespace ignored); else rc 1 + reason.
lc_vermagic_verdict() {
  local a b
  a="$(printf '%s' "${1:-}" | sed 's/[[:space:]]*$//')"
  b="$(printf '%s' "${2:-}" | sed 's/[[:space:]]*$//')"
  if [ -z "$a" ]; then printf 'no module vermagic'; return 1; fi
  if [ -z "$b" ]; then printf 'no expected vermagic'; return 1; fi
  if [ "$a" = "$b" ]; then printf 'ok'; return 0; fi
  printf 'vermagic "%s" != expected "%s"' "$a" "$b"; return 1
}

# lc_symbols_verdict <dump_text> <symvers_text>
#   dump_text   : lines "<crc> <symbol>"        (required symbols; modprobe --dump-modversions)
#   symvers_text: lines "<crc> <symbol> <mod> <export>" (kernel Module.symvers)
#   rc 0 + "ok <n>" if every required symbol is present with a matching CRC; else rc 1 + counts.
lc_symbols_verdict() {
  local dump="${1:-}" symvers="${2:-}" ok=0 bad=0 miss=0 c s crc sym kc
  local -A KCRC=()
  if [ -z "$dump" ]; then printf 'no required-symbol list'; return 1; fi
  if [ -z "$symvers" ]; then printf 'no Module.symvers'; return 1; fi
  while read -r c s _; do [ -n "${s:-}" ] && KCRC["$s"]="$c"; done <<EOF
${symvers}
EOF
  while read -r crc sym _; do
    [ -n "${sym:-}" ] || continue
    kc="${KCRC[$sym]:-}"
    if [ -z "$kc" ]; then miss=$((miss+1)); elif [ "$kc" = "$crc" ]; then ok=$((ok+1)); else bad=$((bad+1)); fi
  done <<EOF
${dump}
EOF
  if [ "$bad" -eq 0 ] && [ "$miss" -eq 0 ]; then printf 'ok %d' "$ok"; return 0; fi
  printf '%d crc-mismatch / %d missing (of %d)' "$bad" "$miss" "$((ok+bad+miss))"; return 1
}

# ---- the rest runs only when executed (not when sourced for unit tests) ------
[ "${LC_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

LEDGER=""; BUNDLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2;;
    --bundle) BUNDLE="${2:-}"; shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2;;
  esac
done
if [ -z "$LEDGER" ] || [ ! -f "$LEDGER" ]; then printf 'ledger not found: %s\n' "${LEDGER:-(unset)}" >&2; exit 2; fi
if [ -z "$BUNDLE" ] || [ ! -d "$BUNDLE" ]; then printf 'bundle dir not found: %s\n' "${BUNDLE:-(unset)}" >&2; exit 2; fi

n_rows=0 n_ready=0 n_notready=0 n_info=0
jstr() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit() {  # emit <os> <ver> <kver> <check> <status> <detail>
  printf '[verify][result] {"os":"%s","ena_version":"%s","kver":"%s","check":"%s","status":"%s","detail":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$(jstr "$6")"
  printf '  ol%s ena_%-10s %-22s %-4s -- %s\n' "$1" "$2" "$4" "$5" "$6" >&2
}

have_kmod=0; command -v modprobe >/dev/null 2>&1 && command -v modinfo >/dev/null 2>&1 && have_kmod=1

ko_vermagic() {  # read a .ko's vermagic without needing the running kernel
  if [ "$have_kmod" = "1" ]; then modinfo -F vermagic "$1" 2>/dev/null | head -1; return; fi
  strings "$1" 2>/dev/null | sed -n 's/^vermagic=//p' | head -1
}

# Stream OK rows from the ledger as TSV: osmajor<TAB>ena_version<TAB>kver
rows="$(python3 - "$LEDGER" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    sys.stderr.write("ledger parse error: %s\n" % e); sys.exit(3)
for r in d.get("entries", []):
    if r.get("status") == "ok":
        print("\t".join([str(r.get("osmajor","")), str(r.get("ena_version","")), str(r.get("kver",""))]))
PY
)" || { printf 'failed to read ledger\n' >&2; exit 3; }

if [ -z "$rows" ]; then printf '[verify] no OK rows in the ledger -- nothing to verify\n' >&2; fi

while IFS=$'\t' read -r os ver kver; do
  [ -n "${os}${ver}${kver}" ] || continue
  n_rows=$((n_rows+1)); row_fail=0
  ko="${BUNDLE}/modules/ol${os}-ena_${ver}-${kver}.ko"
  kdir="${BUNDLE}/kver/${kver}"

  # FAIL LOUD on a missing bundle artifact for an OK row (no silent skip).
  if [ ! -f "$ko" ]; then emit "$os" "$ver" "$kver" "bundle" fail "module not in bundle: ${ko#"$BUNDLE"/}"; n_notready=$((n_notready+1)); continue; fi

  # L4a vermagic-match (GATE)
  vm="$(ko_vermagic "$ko")"; exp=""; [ -f "${kdir}/kernel.vermagic" ] && exp="$(head -1 "${kdir}/kernel.vermagic")"
  if [ -z "$exp" ]; then emit "$os" "$ver" "$kver" L4a fail "no kernel.vermagic in bundle for ${kver}"; row_fail=1
  elif d="$(lc_vermagic_verdict "$vm" "$exp")"; then emit "$os" "$ver" "$kver" L4a pass "$vm"
  else emit "$os" "$ver" "$kver" L4a fail "$d"; row_fail=1; fi

  # L4b symbol-crc-kabi (GATE; needs kmod to dump the module's required symbols)
  if [ "$have_kmod" != "1" ]; then emit "$os" "$ver" "$kver" L4b skip "kmod (modprobe) absent -- run the verifier on a host with kmod"
  elif [ ! -f "${kdir}/Module.symvers" ]; then emit "$os" "$ver" "$kver" L4b fail "no Module.symvers in bundle for ${kver}"; row_fail=1
  else
    dump="$(modprobe --dump-modversions "$ko" 2>/dev/null || true)"
    sv="$(cat "${kdir}/Module.symvers" 2>/dev/null || true)"
    if d="$(lc_symbols_verdict "$dump" "$sv")"; then emit "$os" "$ver" "$kver" L4b pass "$d"
    else emit "$os" "$ver" "$kver" L4b fail "$d"; row_fail=1; fi
  fi

  # L3 initramfs-inclusion (INFO; non-gating)
  if [ ! -f "${kdir}/initramfs.list" ]; then emit "$os" "$ver" "$kver" L3 info "no initramfs.list in bundle for ${kver}"
  elif grep -qiE '/ena\.ko' "${kdir}/initramfs.list"; then emit "$os" "$ver" "$kver" L3 info "ena.ko present in initramfs"; n_info=$((n_info+1))
  else emit "$os" "$ver" "$kver" L3 info "ena.ko not in initramfs (expected: DKMS/dracut govern this; nvme root boots, ena loads post-pivot)"; n_info=$((n_info+1)); fi

  # L5 module-load+device (SKIP; the real-Nitro ceiling)
  emit "$os" "$ver" "$kver" L5 skip "real modprobe + device need the UEK kernel running on real Nitro (B-T8)"

  if [ "$row_fail" -eq 0 ]; then n_ready=$((n_ready+1)); else n_notready=$((n_notready+1)); fi
done <<EOF
${rows}
EOF

printf '[verify][summary] {"ok_rows":%d,"load_ready":%d,"not_ready":%d,"kmod":%s}\n' \
  "$n_rows" "$n_ready" "$n_notready" "$([ "$have_kmod" = 1 ] && echo true || echo false)"
[ "$n_notready" -eq 0 ]
