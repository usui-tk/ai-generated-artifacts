#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# run-awscli-installtest-matrix.sh
# ----------------------------------------------------------------------------
# Determine, per Oracle Linux major (OL6/OL7/OL8), which AWS CLI v2 versions
# INSTALL and actually RUN -- the comprehensive, host-side install-test that
# mirrors tests/ssm/run-ssm-installtest-matrix.sh. For each (OL, version) it
# builds (or reuses) a disposable clean-core rootfs, runs install-awscli.sh in
# AWSCLI_INSTALLTEST mode inside an unshare+chroot, and records the structured
# [installtest][result] into a dedup ledger + a per-OS Markdown report.
#
# WHY glibc (the axis): AWS CLI v2 ships a self-contained zip bundle that BUNDLES
# its own Python, so it does not use the OS Python -- but the bundled interpreter
# and its .so's are built against a manylinux glibc, so the OS glibc gates whether
# the bundle installs/runs. AWS policy ("Linux Support Updates for AWS CLI v2",
# 2024-09-16): current v2 is built on manylinux2014 (glibc 2.17) and supports
# glibc >= 2.17; glibc <= 2.16 should pin v2 <= 2.17.49. So:
#   * OL6 glibc 2.12 -- only old enough builds (<= 2.17.49) install/run.
#   * OL7 glibc 2.17 -- the floor: current v2 installs/runs.
#   * OL8 glibc 2.28 -- above the floor: current v2 installs/runs.
# env_glibc is read in-container from the rpm db (`rpm -q glibc`) and is FAITHFUL
# (the clean-core's real OL glibc is what the bundle links against), so this
# install-test is conclusive for the glibc axis -- unlike the SSM kernel axis.
#
# WHY kver is still recorded: glibc is the compatibility gate, but the OL UEK
# kernel is provisioned + recorded (`rpm -q kernel-uek`) and used as the ledger
# dedup PRIMARY key, so a new OL kernel RE-TESTS every version (a re-test flag),
# exactly as the SSM matrix does. test_host_kernel is the runner kernel the binary
# actually executes on (a container shares the host kernel).
#
# Scope (versions): every AWS CLI v2 release (major == 2) is in scope -- the sweep
# is comprehensive and omits nothing (awscli_in_scope). The OL-repo `awscli` (v1)
# is never install-tested here; it is the package install-awscli.sh blocks.
#
# Modes:
#   (default)  test EVERY v2 version from the release list, per OL.
#   --full     accepted for parity with the SSM matrix; all v2 is already in scope.
#
# Ledger dedup key (osmajor, awscli_version, kver), kver PRIMARY.
#
# Usage:
#   run-awscli-installtest-matrix.sh [--ol "6 7 8"] [--awscli-versions "..."]
#   --ol "<list>"            OL majors to test (default: 6 7 8). OL5 is a
#                            supported OPT-IN target (never in the default
#                            set; e.g. --ol 5): install-test/PoC scope, the
#                            bundle is host-staged (EL5 has no in-guest TLS
#                            1.2 path), unzip already ships in the clean-core,
#                            and the kver record is the live-probed terminal
#                            el5uek NVR (AWSCLI_OL5_KVER contract). Ceiling
#                            pin 2.17.51 = the OL6 pin, same measured reason.
#   --merge-from <path>      no builds: union ANOTHER ledger JSON into
#                            --ledger, then regenerate every report (python3
#                            only). Same-key same-status keeps the existing
#                            row; same-key DIFFERENT-status is a hard error
#                            unless --merge-prefer resolves it.
#   --merge-prefer <side>    'ours' or 'theirs' for merge conflicts.
#   --awscli-versions "..."  explicit version list (default: from the release JSON)
#   --full                   parity flag (all v2 already in scope)
#   --ledger <path>          ledger JSON (default: tests/awscli/awscli-installtest-ledger.json)
#   --results-dir <dir>      where RESULTS-ol<N>.md are written (default: tests/awscli)
#   --cleancore-dir <dir>    clean-core tarball cache (default: ./cleancore-out)
#   --work-dir <dir>         clean-core build scratch base
#   --releases <path>        release JSON (default: tests/awscli/awscli-releases.json)
#   --rebuild-cleancore      force a clean-core rebuild
#   --preflight-retries <n>  transient-failure retries for the QA preflight (default 2)
#   --strict                 if the latest-version probe fails, SKIP (default: fail-open)
#   --force                  bypass the update gate (run every OL) and the ledger dedup
#
# Exit: 0 = the matrix ran and the ledger/reports were written (individual test
# failures are recorded, not fatal); non-zero = a setup/precondition error.
# ----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ORCHESTRATOR="${SCRIPT_DIR}/../cleancore/build-cleancore.sh"
INSTALL_SCRIPT="${PROJ_DIR}/install-awscli.sh"

OL_LIST="6 7 8"
MERGE_FROM=""
MERGE_PREFER=""
AWSCLI_VERSIONS=""
FULL=0
LEDGER="${SCRIPT_DIR}/awscli-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
CLEANCORE_DIR="./cleancore-out"
WORK_BASE=""
RELEASES="${SCRIPT_DIR}/awscli-releases.json"
REBUILD_CLEANCORE=0
FORCE=0
STRICT=0
PREFLIGHT_RETRIES=2
INSECURE_TLS="${INSECURE_TLS:-1}"
AWSCLI_REPO_URL="${AWSCLI_REPO_URL:-https://github.com/aws/aws-cli.git}"

log()  { printf '%s [awscli-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { log "WARNING: $*" >&2; }
die()  { log "ERROR: $*" >&2; exit 1; }
hr()   { log "================================================================"; }

# pinned QA-preflight version per OL major (a known-good smoke version). 2.17.51
# is the highest build proven to install+run on OL6 (glibc 2.12) by this matrix --
# the last GLIBC_2.5 / Python-3.11.9 build -- and it runs on OL7 (2.17) and OL8
# (2.28) alike, so it is a safe health-check across the scope. Kept in step with
# install-awscli.sh's OL6 production pin (AWSCLI_VERSION_OL6).
# OL5 shares the 2.17.51 ceiling pin with OL6 -- the 2.17.52 Python 3.12
# rebase jumps the bundle glibc floor 2.5 -> 2.17, walling out both glibc 2.12
# (OL6) and 2.5 (OL5); measured 2026-07-18, see install-awscli.sh.
pin_for() { case "$1" in 5|6|7|8) echo 2.17.51 ;; *) echo "" ;; esac; }

# ===========================================================================
# Pure helpers (no I/O) -- unit-tested by tests/t019_awscliverdict.sh. Keep each a
# column-0 function from its definition line to the first column-0 '}'.
# ===========================================================================

# awscli_ge <a> <b> : exit 0 iff dotted-numeric version a >= b (up to 4 parts).
# Used for AWS CLI versions (e.g. 2.17.49) AND glibc versions (e.g. 2.17 vs 2.12).
awscli_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# awscli_min_glibc <version> : the bundle's minimum glibc, a DOCUMENTED heuristic
# (not a per-binary readelf -- the empirical ledger is the truth). AWS's "Linux
# Support Updates for AWS CLI v2" (2024-09-16) sets the manylinux2014 floor of
# glibc 2.17 for current v2 and names 2.17.49 as the last build for glibc <= 2.16.
# So: version >= 2.17.50 -> 2.17 (manylinux2014); version <= 2.17.49 -> 2.5 (the
# older manylinux1 floor, which OL6's glibc 2.12 satisfies). empty/junk -> unknown.
awscli_min_glibc() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  case "${v}" in *[!0-9.]*|.*|*.) printf 'unknown'; return 0 ;; esac
  if awscli_ge "${v}" "2.17.50"; then printf '2.17'; else printf '2.5'; fi
}

# awscli_in_scope <ver> <full> : exit 0 iff this version is tested. Scope is every
# AWS CLI v2 release (major == 2); v1 is never install-tested (it is the package
# we block). full is accepted for parity with the SSM matrix -- all v2 is in scope
# either way (the comprehensive sweep omits nothing).
awscli_in_scope() {
  local v="${1:-}" maj
  maj="${v%%.*}"
  [ "${maj}" = "2" ]
}

# awscli_verdict <os_glibc> <min_glibc> <ran> : the per-(OL,version) verdict.
#   runs            -> installed + ran (the empirical truth)
#   glibc-too-old   -> did not run AND os_glibc < min_glibc (the expected floor)
#   unexpected-fail -> did not run BUT os_glibc >= min_glibc (investigate: not glibc)
awscli_verdict() {
  local osg="${1:-}" ming="${2:-}" ran="${3:-false}"
  if [ "${ran}" = "true" ]; then printf 'runs'; return 0; fi
  if [ -n "${ming}" ] && [ "${ming}" != "unknown" ] && [ -n "${osg}" ] && ! awscli_ge "${osg}" "${ming}"; then
    printf 'glibc-too-old'
  else
    printf 'unexpected-fail'
  fi
}

# python_eol <X.Y[.Z]> : the documented end-of-life (security-support end) date for
# a bundled CPython minor, per Python's official 5-year support cycle. A STATIC
# table (Q2 option b) -- deterministic; the RESULTS header stamps the verified date
# + sources. Accepts a full "3.11.9" or a minor "3.11"; unknown minor -> "unknown".
# VERIFIED 2026-06-17 from endoflife.date/python (+ eosl.date, eol.wiki). Keep in
# sync with the PY_EOL table in the RESULTS generator below.
python_eol() {
  local v="${1:-}" maj min mm
  maj="${v%%.*}"; min="${v#*.}"; min="${min%%.*}"
  case "${maj}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  case "${min}" in ''|*[!0-9]*) printf 'unknown'; return 0 ;; esac
  mm="${maj}.${min}"
  case "${mm}" in
    3.6)  printf '2021-12-23' ;;
    3.7)  printf '2023-06-27' ;;
    3.8)  printf '2024-10-07' ;;
    3.9)  printf '2025-10-31' ;;
    3.10) printf '2026-10-31' ;;
    3.11) printf '2027-10-31' ;;
    3.12) printf '2028-10-31' ;;
    3.13) printf '2029-10-31' ;;
    3.14) printf '2030-10-31' ;;
    *)    printf 'unknown' ;;
  esac
}

# ---- args ------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ol)                OL_LIST="${2:-}"; shift ;;
    --awscli-versions)   AWSCLI_VERSIONS="${2:-}"; shift ;;
    --full)              FULL=1 ;;
    --ledger)            LEDGER="${2:-}"; shift ;;
    --results-dir)       RESULTS_DIR="${2:-}"; shift ;;
    --cleancore-dir)     CLEANCORE_DIR="${2:-}"; shift ;;
    --work-dir)          WORK_BASE="${2:-}"; shift ;;
    --releases)          RELEASES="${2:-}"; shift ;;
    --rebuild-cleancore) REBUILD_CLEANCORE=1 ;;
    --preflight-retries) PREFLIGHT_RETRIES="${2:-}"; shift ;;
    --strict)            STRICT=1 ;;
    --force)             FORCE=1 ;;
    --merge-from)        MERGE_FROM="${2:-}"; shift ;;
    --merge-prefer)      MERGE_PREFER="${2:-}"; shift ;;
    -h|--help)           sed -n '2,/^# ---.*$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                   die "unknown argument: $1 (-h for help)" ;;
  esac
  shift
done
OL_LIST="${OL_LIST//,/ }"
AWSCLI_VERSIONS="${AWSCLI_VERSIONS//,/ }"

# ---- pre-flight ------------------------------------------------------------
if [ -n "${MERGE_FROM}" ]; then
  # Merge mode (reuse-by-copy of the ENA matrix implementation, same
  # user-adjudicated policy 2026-07-18): union ANOTHER ledger into --ledger on
  # the dedup key (osmajor, awscli_version, kver), then regenerate every
  # report. python3 only -- no root, no containers, no network. Same-key
  # same-status keeps the EXISTING row; same-key DIFFERENT-status is a HARD
  # ERROR unless --merge-prefer ours|theirs resolves it; keys only in the
  # other ledger are adopted.
  case "${MERGE_PREFER}" in ""|ours|theirs) : ;; *) die "--merge-prefer must be 'ours' or 'theirs' (got '${MERGE_PREFER}')" ;; esac
  command -v python3 >/dev/null 2>&1 || die "missing required host tool: python3"
  [ -f "${MERGE_FROM}" ] || die "no ledger to merge from at ${MERGE_FROM}"
  [ -f "${LEDGER}" ] || die "no ledger at ${LEDGER} (with no base ledger there is nothing to merge into; copy the file instead)"
  mkdir -p "${RESULTS_DIR}"; RESULTS_DIR="$(cd "${RESULTS_DIR}" && pwd)"
  OL_LIST=""
  log "merge mode: merging ${MERGE_FROM} into ${LEDGER} (prefer: ${MERGE_PREFER:-none = conflict is fatal}); no builds"
else
[ "$(id -u)" -eq 0 ] || die "must run as root (clean-core build + unshare/chroot need it)."
case "${SCRIPT_DIR}" in
  ""|/) die "refusing to run: matrix script resolves to '${SCRIPT_DIR:-<empty>}' (irregular placement; destructive clean-core cleanup could hit the OS root)." ;;
esac
for t in unshare chroot tar curl python3; do
  command -v "${t}" >/dev/null 2>&1 || die "missing required host tool: ${t}"
done
[ -f "${ORCHESTRATOR}" ]   || die "orchestrator not found: ${ORCHESTRATOR}"
[ -f "${INSTALL_SCRIPT}" ] || die "install-awscli.sh not found: ${INSTALL_SCRIPT}"
WORK_BASE="${WORK_BASE:-${TMPDIR:-/tmp}/cleancore-work-awscli-installtest}"
case "${WORK_BASE}" in ""|/|//) die "refusing to run: --work-dir resolves to '${WORK_BASE:-<empty>}' (would risk destructive cleanup)." ;; esac
mkdir -p "${WORK_BASE}"; WORK_BASE="$(cd "${WORK_BASE}" && pwd)"
[ "${WORK_BASE}" = "/" ] && die "refusing to run: --work-dir resolved to '/'."
fi

# ---- the version list for an OL (from --awscli-versions, else the release JSON),
# filtered by the mode (all v2 are in scope). --------------------------------
versions_for_ol() {
  local raw=""
  if [ -n "${AWSCLI_VERSIONS}" ]; then
    raw="${AWSCLI_VERSIONS}"
  elif [ -f "${RELEASES}" ]; then
    raw="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
print(' '.join(v['version'] for v in d.get('versions',[])))" "${RELEASES}" 2>/dev/null || true)"
  fi
  local v out=""
  for v in ${raw}; do
    if awscli_in_scope "${v}" "${FULL}"; then out="${out} ${v}"; fi
  done
  printf '%s' "${out# }"
}

# min_glibc for a version, read from the release JSON if present (else computed).
min_glibc_of() {
  local v="$1" mg=""
  if [ -f "${RELEASES}" ]; then
    mg="$(python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
g={x['version']:(x.get('min_glibc') or '') for x in d.get('versions',[])}
print(g.get(sys.argv[2],''))" "${RELEASES}" "${v}" 2>/dev/null || true)"
  fi
  [ -n "${mg}" ] || mg="$(awscli_min_glibc "${v}")"
  printf '%s' "${mg}"
}

# ---- OL5 host-side staging + kver probe -------------------------------------
# EL5 has NO in-guest network path (openssl 0.9.8e = TLS 1.0 max vs the
# TLS-1.2-only awscli.amazonaws.com / yum.oracle.com), so unlike OL6-8 the
# matrix stages the requested bundle zip into the container from the HOST
# (cached under WORK_BASE) -- the installer OL5 pre-stage contract. Nothing
# else needs provisioning (unzip 5.52 ships in the OL5 clean-core). The kver
# record comes from a live probe of the terminal OL5 UEK/latest channel
# (reuse-by-copy of the ENA matrix probe, OL5-fixed; pinned fallback) and is
# passed via AWSCLI_OL5_KVER -- "probed, not provisioned": the kernel is not
# this matrix's compat axis and the EL5 kernel RPM %post initrd scriptlets
# are unsafe in a chroot.
OL5_UEK_FALLBACK_KVER="2.6.39-400.297.3.el5uek.x86_64"
OL5_KVER_CACHE=""

probe_ol5_uek_kver() {
  local base="https://yum.oracle.com/repo/OracleLinux/OL5/UEK/latest/x86_64"
  local repomd gz out href kver
  repomd="$(mktemp)"; gz="$(mktemp)"; out="$(mktemp)"
  kver=""
  if curl -fsS --max-time 60 "${base}/repodata/repomd.xml" -o "${repomd}" 2>/dev/null; then
    href="$(grep -oE '"[^"]*primary\.xml\.gz"' "${repomd}" | head -1 | tr -d '"')"
    if [ -n "${href}" ] && curl -fsS --max-time 180 --max-filesize 268435456 "${base}/${href}" -o "${gz}" 2>/dev/null; then
      python3 - "${gz}" "${out}" 2>/dev/null <<'PYK' || true
import gzip, sys, xml.etree.ElementTree as ET
gz, outp = sys.argv[1], sys.argv[2]
ns = {"c": "http://linux.duke.edu/metadata/common"}
best = None
def vkey(s):
    o = []
    for part in str(s).replace("-", ".").split("."):
        o.append((1, int(part)) if part.isdigit() else (0, part))
    return o
root = ET.parse(gzip.open(gz)).getroot()
for pkg in root.findall("c:package", ns):
    name = pkg.findtext("c:name", default="", namespaces=ns)
    arch = pkg.findtext("c:arch", default="", namespaces=ns)
    if name != "kernel-uek" or arch != "x86_64":
        continue
    v = pkg.find("c:version", ns)
    if v is None:
        continue
    kv = "%s-%s.%s" % (v.get("ver", ""), v.get("rel", ""), arch)
    if best is None or vkey(kv) > vkey(best):
        best = kv
if best:
    open(outp, "w").write(best)
PYK
      kver="$(cat "${out}" 2>/dev/null || true)"
    fi
  fi
  rm -f "${repomd}" "${gz}" "${out}"
  printf '%s' "${kver}"
}

ol5_kver() {
  if [ -z "${OL5_KVER_CACHE}" ]; then
    OL5_KVER_CACHE="$(probe_ol5_uek_kver || true)"
    [ -n "${OL5_KVER_CACHE}" ] || OL5_KVER_CACHE="${OL5_UEK_FALLBACK_KVER}"
  fi
  printf '%s' "${OL5_KVER_CACHE}"
}

ol5_stage_zip() { # $1=img $2=version ; stage the bundle zip into the container
  local img="$1" ver="$2" cache="${WORK_BASE}/ol5-awscli-zips" f
  f="awscli-exe-linux-x86_64-${ver}.zip"
  mkdir -p "${cache}" || return 1
  if ! unzip -tqq "${cache}/${f}" >/dev/null 2>&1; then
    if [ "${INSECURE_TLS}" = "1" ]; then
      curl -fsSL -k --max-time 300 "https://awscli.amazonaws.com/${f}" -o "${cache}/${f}" || { echo "OL5 staging: bundle download failed: ${f}"; return 1; }
    else
      curl -fsSL --max-time 300 "https://awscli.amazonaws.com/${f}" -o "${cache}/${f}" || { echo "OL5 staging: bundle download failed: ${f}"; return 1; }
    fi
    unzip -tqq "${cache}/${f}" >/dev/null 2>&1 || { echo "OL5 staging: not a zip: ${f}"; return 1; }
  fi
  cp -f "${cache}/${f}" "${img}/usr/src/${f}" || return 1
  echo "OL5 staging: ${f} staged (kver record $(ol5_kver))"
  return 0
}

# ---- run ONE install+run test for (ol, version) against a clean-core tarball;
# echo the raw [result] JSON object (or empty if the test emitted none). ------
run_one_installtest() {
  local ol="$1" ver="$2" tarball="$3" outlog="$4" img ol5kv=""
  img="$(mktemp -d)"
  tar -C "${img}" -xzf "${tarball}"
  cp /etc/resolv.conf "${img}/etc/resolv.conf" 2>/dev/null || true
  cp "${INSTALL_SCRIPT}" "${img}/install-awscli.sh"
  # OL5: host-side bundle staging + probed kver (see the OL5 section above).
  # A staging failure lands in the outlog; the installer OL5 pre-stage
  # contract then records the fail with a clear reason.
  if [ "${ol}" = "5" ]; then
    ol5_stage_zip "${img}" "${ver}" >> "${outlog}" 2>&1 \
      || echo "[awscli-matrix] OL5 staging failed (see above); the guest pre-stage contract will record the failure" >> "${outlog}"
    ol5kv="$(ol5_kver)"
  fi
  unshare --fork --pid --mount --uts --ipc -- bash -c "
    export PATH=/usr/sbin:/usr/bin:/sbin:/bin
    mount --bind /dev '${img}/dev'
    mount -t proc proc '${img}/proc'
    mount -t sysfs sys '${img}/sys'
    export AWSCLI_INSTALLTEST=1 AWSCLI_VERSION='${ver}' INSECURE_TLS='${INSECURE_TLS}' AWSCLI_OL5_KVER='${ol5kv}'
    chroot '${img}' /bin/bash /install-awscli.sh
  " >> "${outlog}" 2>&1 || true
  rm -rf "${img}"
  { grep -E '\[awscli\]\[installtest\]\[result\]' "${outlog}" || true; } | tail -1 | sed 's/^.*\[result\] //'
}

# ---- QA preflight: install+run ONLY the pinned version as a smoke test that the
# clean-core rootfs + install-awscli.sh are healthy, before the full sweep.
# QA-only (NOT recorded in the ledger); a clear failure early-exits this OL. -----
preflight_reason_is_transient() {
  printf '%s' "${1:-}" | grep -qiE 'fetch failed|could not resolve|timed out|connection (refused|reset)|temporar|mirror|download-fail'
}

preflight_qa() {
  local ol="$1" tarball="$2" pin attempt=1 max rjson st reason
  pin="$(pin_for "${ol}")"
  [ -n "${pin}" ] || { warn "OL${ol}: no QA pin; skipping preflight"; return 0; }
  max=$(( PREFLIGHT_RETRIES + 1 ))
  while [ "${attempt}" -le "${max}" ]; do
    log "OL${ol} QA preflight [${attempt}/${max}]: install+run pinned AWS CLI ${pin}"
    local blog; blog="$(mktemp)"
    rjson="$(run_one_installtest "${ol}" "${pin}" "${tarball}" "${blog}" || true)"
    st="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    reason="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason',''))" 2>/dev/null || true)"
    if [ "${st}" = "ok" ]; then rm -f "${blog}"; log "OL${ol} QA preflight OK (pinned ${pin})"; return 0; fi
    local keep="${CLEANCORE_DIR}/preflight-ol${ol}-FAILED.log"; cp -f "${blog}" "${keep}" 2>/dev/null || true; rm -f "${blog}"
    if preflight_reason_is_transient "${reason}" && [ "${attempt}" -lt "${max}" ]; then
      warn "OL${ol} QA preflight transient (${reason:-no-result}); retrying"; attempt=$(( attempt + 1 )); continue
    fi
    warn "OL${ol} QA preflight FAILED (pinned ${pin}: ${reason:-no-result}) -- log at ${keep}"
    return 1
  done
  return 1
}

# ---- update gate -----------------------------------------------------------
# Run the OL if the latest upstream AWS CLI v2 release is newer than the highest
# the ledger has tested for it (or the OL has no ledger entry). A new OL UEK is
# still handled by the kver-PRIMARY ledger dedup (a new UEK re-tests every version).
probe_latest_awscli() {
  git ls-remote --tags "${AWSCLI_REPO_URL}" 2>/dev/null \
    | sed -E 's#.*refs/tags/##; s/\^\{\}$//' \
    | grep -oE '^2\.[0-9]+\.[0-9]+$' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

ledger_max_awscli_for_ol() {
  [ -f "${LEDGER}" ] || { printf ''; return 0; }
  python3 -c "import json,sys
d=json.load(open(sys.argv[1])); ol=sys.argv[2]
vs=[e['awscli_version'] for e in d.get('entries',[]) if e.get('osmajor')==ol]
def key(s):
  p=(s.split('.')+['0','0','0','0'])[:4]
  return tuple(int(x) if x.isdigit() else 0 for x in p)
print(sorted(vs,key=key)[-1] if vs else '')" "${LEDGER}" "$1" 2>/dev/null || true
}

gate_should_run_ol() {
  local ol="$1" latest maxled
  [ "${FORCE}" = "1" ] && { log "OL${ol}: --force -> running (gate bypassed)"; return 0; }
  latest="$(probe_latest_awscli || true)"
  if [ -z "${latest}" ]; then
    if [ "${STRICT}" = "1" ]; then warn "OL${ol}: AWS CLI version probe failed; --strict -> SKIP"; return 1; fi
    warn "OL${ol}: AWS CLI version probe failed; fail-open -> running"; return 0
  fi
  maxled="$(ledger_max_awscli_for_ol "${ol}")"
  if [ -z "${maxled}" ]; then log "OL${ol}: no ledger entry -> running"; return 0; fi
  if awscli_ge "${maxled}" "${latest}"; then
    log "OL${ol}: ledger covers latest AWS CLI ${latest} (max tested ${maxled}) -> SKIP"; return 1
  fi
  log "OL${ol}: newer AWS CLI available (${latest} > ledger max ${maxled}) -> running"; return 0
}

# ---- run the matrix --------------------------------------------------------
RESULTS_TSV="$(mktemp)"   # one row per attempted test: ol \t version \t result-json
trap 'rm -f "${RESULTS_TSV}"' EXIT

mkdir -p "${CLEANCORE_DIR}"
ol_total=0; g_ol_ran=0; g_ol_skipped=0; g_ok=0; g_fail=0; g_skip=0; g_tests=0
for ol in ${OL_LIST}; do ol_total=$(( ol_total + 1 )); done

for ol in ${OL_LIST}; do
  case "${ol}" in 5|6|7|8) : ;; *) warn "OL${ol}: wired for OL5 (opt-in via --ol) and OL6/7/8 only; skipping."; g_ol_skipped=$(( g_ol_skipped + 1 )); continue ;; esac

  if ! gate_should_run_ol "${ol}"; then g_ol_skipped=$(( g_ol_skipped + 1 )); continue; fi

  tarball="${CLEANCORE_DIR}/cleancore-ol${ol}.tar.gz"
  if [ "${REBUILD_CLEANCORE}" = "1" ] || [ ! -f "${tarball}" ]; then
    log "OL${ol}: building clean-core rootfs -> ${tarball}"
    INSECURE_TLS="${INSECURE_TLS}" bash "${ORCHESTRATOR}" --ol "${ol}" --out-dir "${CLEANCORE_DIR}" --work-dir "${WORK_BASE}" \
      || die "OL${ol}: clean-core build failed"
  fi
  [ -f "${tarball}" ] || die "OL${ol}: clean-core tarball missing after build: ${tarball}"

  if ! preflight_qa "${ol}" "${tarball}"; then
    warn "OL${ol}: QA preflight failed -> skipping the OL (ledger untouched)"; g_ol_skipped=$(( g_ol_skipped + 1 )); continue
  fi
  g_ol_ran=$(( g_ol_ran + 1 ))

  vlist="$(versions_for_ol)"
  if [ -z "${vlist}" ]; then
    warn "OL${ol}: no in-scope versions; nothing to test"
    continue
  fi
  total=0; for _v in ${vlist}; do total=$(( total + 1 )); done
  log "OL${ol}: testing ${total} v2 version(s) (comprehensive sweep)"

  live_kver=""; idx=0; ol_ok=0; ol_fail=0; ol_skip=0
  for ver in ${vlist}; do
    idx=$(( idx + 1 ))
    if [ "${FORCE}" != "1" ] && [ -n "${live_kver}" ] && [ -f "${LEDGER}" ]; then
      if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
k=(sys.argv[2],sys.argv[3],sys.argv[4])
sys.exit(0 if any((e['osmajor'],e['awscli_version'],e['kver'])==k for e in d.get('entries',[])) else 1)
" "${LEDGER}" "${ol}" "${ver}" "${live_kver}"; then
        log "OL${ol} [${idx}/${total}] AWS CLI ${ver}: SKIP (already in ledger for kver ${live_kver})"
        ol_skip=$(( ol_skip + 1 )); continue
      fi
    fi
    log "OL${ol} [${idx}/${total}] AWS CLI ${ver}: install+run test..."
    tlog="$(mktemp)"
    rjson="$(run_one_installtest "${ol}" "${ver}" "${tarball}" "${tlog}" || true)"
    if [ -z "${rjson}" ]; then
      rjson="{\"status\":\"fail\",\"osmajor\":\"${ol}\",\"awscli_version\":\"${ver}\",\"kver\":\"${live_kver}\",\"test_host_kernel\":\"\",\"glibc\":\"\",\"installed_version\":\"\",\"ran\":false,\"run_method\":\"\",\"reason\":\"no result line (infrastructure error)\"}"
    fi
    st="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || true)"
    if [ "${st}" != "ok" ]; then
      keep="${CLEANCORE_DIR}/installtest-ol${ol}-awscli_${ver}.log"; cp -f "${tlog}" "${keep}" 2>/dev/null || true
      warn "OL${ol} [${idx}/${total}] AWS CLI ${ver}: ${st:-no-result} -- log preserved at ${keep}"
      ol_fail=$(( ol_fail + 1 ))
    else
      ol_ok=$(( ol_ok + 1 ))
    fi
    rm -f "${tlog}"
    printf '%s\t%s\t%s\n' "${ol}" "${ver}" "${rjson}" >> "${RESULTS_TSV}"
    kv="$(printf '%s' "${rjson}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('kver',''))" 2>/dev/null || true)"
    [ -n "${kv}" ] && live_kver="${kv}"
    log "OL${ol} [${idx}/${total}] AWS CLI ${ver}: ${st:-?} (kver ${live_kver:-?})"
  done
  log "---- OL${ol}: matrix done -- ${ol_ok} ok, ${ol_fail} fail, ${ol_skip} skipped (of ${total}) ----"
  g_ok=$(( g_ok + ol_ok )); g_fail=$(( g_fail + ol_fail )); g_skip=$(( g_skip + ol_skip )); g_tests=$(( g_tests + ol_ok + ol_fail ))
done

hr
log "AWS CLI matrix complete -- ${g_ok} ok, ${g_fail} fail, ${g_skip} skipped across ${g_tests} test(s); OL ran ${g_ol_ran}, skipped ${g_ol_skipped} (of ${ol_total})"
hr

# ---- enrich each result row with min_glibc (from the release list) ----------
ENRICHED_TSV="$(mktemp)"
trap 'rm -f "${RESULTS_TSV}" "${ENRICHED_TSV}"' EXIT
if [ -s "${RESULTS_TSV}" ]; then
  while IFS=$'\t' read -r ol ver rjson; do
    mg="$(min_glibc_of "${ver}")"
    printf '%s\t%s\t%s\t%s\n' "${ol}" "${ver}" "${mg}" "${rjson}" >> "${ENRICHED_TSV}"
  done < "${RESULTS_TSV}"
fi

# ---- merge-from: union another ledger into ours (before the regen below) ----
if [ -n "${MERGE_FROM}" ]; then
  merge_out="$(python3 - "${LEDGER}" "${MERGE_FROM}" "${MERGE_PREFER}" <<'PY_MERGE'
import json, sys
ours_p, theirs_p, prefer = sys.argv[1], sys.argv[2], sys.argv[3]
ours = json.load(open(ours_p))
theirs = json.load(open(theirs_p))
key = lambda e: (str(e.get("osmajor")), str(e.get("awscli_version")), str(e.get("kver")))
oi = {key(e): e for e in ours.get("entries", [])}
adopted = kept = resolved = 0
conflicts = []
for e in theirs.get("entries", []):
    k = key(e)
    if k not in oi:
        oi[k] = e; adopted += 1
    elif oi[k].get("status") == e.get("status"):
        kept += 1                      # same verdict: the incumbent row wins
    elif prefer == "theirs":
        oi[k] = e; resolved += 1
    elif prefer == "ours":
        resolved += 1
    else:
        conflicts.append("OL%s awscli %s kver %s: ours=%s theirs=%s"
                         % (k[0], k[1], k[2], oi[k].get("status"), e.get("status")))
if conflicts:
    print("CONFLICT")
    for c in conflicts:
        print(c)
    sys.exit(3)
ours["entries"] = list(oi.values())
json.dump(ours, open(ours_p, "w"), indent=2)
open(ours_p, "a").write(chr(10))
print("MERGED adopted=%d same-status-kept=%d prefer-resolved=%d total=%d"
      % (adopted, kept, resolved, len(oi)))
PY_MERGE
)" || true
  case "${merge_out}" in
    MERGED*) log "merge-from: ${merge_out}" ;;
    CONFLICT*)
      printf '%s\n' "${merge_out}" | sed '1d' | while IFS= read -r c; do warn "merge conflict: ${c}"; done
      die "merge-from: conflicting status for the same (osmajor, awscli_version, kver) key(s) above -- verdicts are deterministic, so investigate; or resolve explicitly with --merge-prefer ours|theirs" ;;
    *) die "merge-from: merge step failed (unreadable ledger JSON?)" ;;
  esac
fi

# ---- merge into the ledger + regenerate the per-OS Markdown -----------------
python3 - "${LEDGER}" "${ENRICHED_TSV}" "${RESULTS_DIR}" <<'PY'
import json, os, sys

ledger_path, tsv_path, results_dir = sys.argv[1], sys.argv[2], sys.argv[3]

def vkey(s):
    p = (str(s).split('.') + ['0','0','0','0'])[:4]
    return tuple(int(x) if str(x).isdigit() else 0 for x in p)

def ge(a, b):
    return vkey(a) >= vkey(b)

def min_glibc(v):
    # documented heuristic mirror of awscli_min_glibc (matrix shell)
    try:
        ok = all(c.isdigit() or c == '.' for c in v) and v and v[0] != '.' and v[-1] != '.'
    except TypeError:
        ok = False
    if not ok:
        return 'unknown'
    return '2.17' if ge(v, '2.17.50') else '2.5'

def verdict(osg, ming, ran):
    if ran:
        return 'runs'
    if ming and ming != 'unknown' and osg and not ge(osg, ming):
        return 'glibc-too-old'
    return 'unexpected-fail'

# ---- documented lifecycle tables (STATIC; Q2 option b) ----------------------
# Provenance stamps rendered into every report header so the dates are auditable.
EOL_VERIFIED = "2026-06-17"
PY_EOL_SOURCES = "endoflife.date/python, eosl.date/eol/product/python, eol.wiki/python"
OS_EOL_SOURCES = ("blogs.oracle.com/linux, docs.oracle.com (general-notices), "
                  "oracle.com Lifetime Support Policy (operating-system PDF)")

# CPython minor -> end-of-life (security-support end), per Python's official 5-year
# cycle. Mirror of python_eol() in the matrix shell -- keep the two identical.
PY_EOL = {
    "3.6": "2021-12-23", "3.7": "2023-06-27", "3.8": "2024-10-07",
    "3.9": "2025-10-31", "3.10": "2026-10-31", "3.11": "2027-10-31",
    "3.12": "2028-10-31", "3.13": "2029-10-31", "3.14": "2030-10-31",
}

# Oracle Linux major -> (regular-support end, extended/ELS, sustaining). Oracle
# Premier+Basic run 10 years from GA; Extended Support adds 3 years; Sustaining is
# indefinite (NO new security fixes). Once a newer point release ships the older is
# immediately EOL.
OS_EOL = {
    "6": ("Premier ended ~2021-03; Extended Support ended 2024-12",
          "Sustaining Support from 2025-01 (indefinite; NO new security fixes)"),
    "7": ("Premier ended 2024-12",
          "Extended Support through 2028-06; Sustaining thereafter"),
    "8": ("Premier through ~2029-07 (10 yr from GA)",
          "Extended Support ~+3 yr; Sustaining thereafter"),
}

def python_eol(v):
    if not v:
        return 'unknown'
    parts = str(v).split('.')
    if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit():
        return 'unknown'
    return PY_EOL.get(parts[0] + '.' + parts[1], 'unknown')

# load / init ledger
if os.path.exists(ledger_path):
    led = json.load(open(ledger_path))
else:
    led = {"schema_version": "1.0", "ledger_type": "awscli-installtest", "entries": []}
led.setdefault("entries", [])

# index existing by (osmajor, awscli_version, kver) -- kver PRIMARY dedup
idx = {(e.get('osmajor'), e.get('awscli_version'), e.get('kver')): e for e in led["entries"]}

new_rows = 0
if os.path.exists(tsv_path):
    for line in open(tsv_path):
        line = line.rstrip('\n')
        if not line: continue
        ol, ver, mg, rjson = line.split('\t', 3)
        try:
            r = json.loads(rjson)
        except Exception:
            continue
        entry = {
            "osmajor": str(r.get('osmajor', ol)),
            "awscli_version": str(r.get('awscli_version', ver)),
            "kver": str(r.get('kver', '')),
            "test_host_kernel": str(r.get('test_host_kernel', '')),
            "glibc": str(r.get('glibc', '')),
            "bundled_python": str(r.get('bundled_python', '')),
            "min_glibc_measured": str(r.get('min_glibc_measured', '')),
            "min_glibc": mg or min_glibc(ver),
            "python_eol": python_eol(r.get('bundled_python', '')),
            "status": str(r.get('status', '')),
            "ran": bool(r.get('ran', False)),
            "installed_version": str(r.get('installed_version', '')),
            "run_method": str(r.get('run_method', '')),
            "reason": str(r.get('reason', '')),
        }
        idx[(entry['osmajor'], entry['awscli_version'], entry['kver'])] = entry
        new_rows += 1

led["entries"] = sorted(
    idx.values(),
    key=lambda e: (int(e['osmajor']) if str(e['osmajor']).isdigit() else 99, e.get('kver', ''), vkey(e['awscli_version']))
)
json.dump(led, open(ledger_path, 'w'), indent=2)
open(ledger_path, 'a').write('\n')

# per-OS RESULTS
by_ol = {}
for e in led["entries"]:
    by_ol.setdefault(e['osmajor'], []).append(e)

for ol, entries in by_ol.items():
    kvers = sorted({e.get('kver', '') for e in entries}, reverse=True)
    lines = []
    lines.append(f"# AWS CLI v2 install+run matrix -- OL{ol}")
    if ol == "5":
        lines.append("")
        lines.append("_OL5 is an install-test / PoC scoped, opt-in target (`--ol 5`; never in "
                     "the default OL set): the bundle zip is host-pre-staged (EL5 has no "
                     "in-OS TLS 1.2 path), the recorded kver is the live-probed terminal "
                     "el5uek NVR (probed, not provisioned -- the kernel is not this "
                     "matrix's compat axis), and a chroot `runs` does not prove the real "
                     "UEK R2 kernel runtime. Ceiling pin 2.17.51 = the OL6 pin: the "
                     "2.17.52 Python 3.12 rebase jumps the bundle glibc floor to 2.17, "
                     "walling out glibc 2.5 and 2.12 alike._")
    lines.append("")
    lines.append("Generated by `tests/awscli/run-awscli-installtest-matrix.sh` from "
                 "`awscli-installtest-ledger.json` -- DO NOT hand-edit (regenerated each run).")
    lines.append("")
    lines.append("## Why this matters -- AWS CLI v2 glibc support")
    lines.append("")
    lines.append("AWS CLI v2 ships a self-contained zip bundle that BUNDLES its own Python, so it does not use the "
                 "OS Python -- but the bundled interpreter and its shared objects are built against a **manylinux "
                 "glibc**, so the OS **glibc** gates whether the bundle installs and runs. Per AWS's *Linux Support "
                 "Updates for AWS CLI v2* (2024-09-16), current v2 is built on **manylinux2014 (glibc 2.17)** and "
                 "supports glibc >= 2.17; systems on glibc <= 2.16 should pin v2 **<= 2.17.49**. This report "
                 f"characterizes, per OL{ol} environment, which v2 versions install + run -- i.e. the newest AWS CLI "
                 f"v2 an OL{ol} image can actually use.")
    lines.append("")
    lines.append("References (AWS): "
                 "[Linux support updates](https://aws.amazon.com/blogs/developer/linux-support-updates-for-aws-cli-v2/); "
                 "[install AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html); "
                 "[a specific version](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html).")
    lines.append("")
    lines.append("**Fidelity.** `status=ok` means the v2 bundle installed AND `aws --version` + `aws configure list` "
                 "both ran locally (no AWS creds / no IMDS). Columns: **env_** = the OL test environment (read from "
                 "the rpm db), **compat_** = the requirement derived from the version. The **env_glibc** axis is "
                 "FAITHFUL -- the container's real OL glibc is what the bundle links against, so this install-test is "
                 "conclusive for glibc (unlike a kernel axis). **env_kernel** (`rpm -q kernel-uek`) is the OL UEK a "
                 "real instance runs, provisioned only to record it and to key the ledger (a new kernel re-tests "
                 "every version); the binary actually executed on **test_host_kernel** (the runner's). "
                 "**compat_min_glibc** is the documented manylinux floor for the version (heuristic; the ok/fail "
                 "column is the empirical truth). `aws sts get-caller-identity` needs creds + network and is a "
                 "real-instance confirmation, not part of this test.")
    lines.append("")
    # ---- bundled Python runtime support (static; provenance-stamped) --------
    lines.append("## Bundled Python runtime support")
    lines.append("")
    lines.append("AWS CLI v2 BUNDLES its own CPython; that interpreter is **frozen** and not "
                 "independently patchable -- the only way to move to a newer (still-supported) Python "
                 "is to move to a newer AWS CLI v2 version. On a glibc-capped OS the AWS CLI version is "
                 "capped, so the bundled Python is capped too, and when it reaches end-of-life there is no "
                 "in-place remediation. The `bundled_python` / `python_eol` columns below let you read each "
                 "tested version's interpreter and its support horizon.")
    lines.append("")
    lines.append(f"Python end-of-life (security-support end) -- STATIC table, **verified {EOL_VERIFIED}** "
                 f"from {PY_EOL_SOURCES}. Compare against today's date to read supported vs EOL:")
    lines.append("")
    lines.append("| Python | EOL (security-support end) |")
    lines.append("|---|---|")
    for mm in sorted(PY_EOL, key=lambda s: tuple(int(x) for x in s.split('.'))):
        lines.append(f"| {mm} | {PY_EOL[mm]} |")
    lines.append("")
    # ---- this OS's own lifecycle (static; provenance-stamped) ---------------
    os_reg, os_ext = OS_EOL.get(ol, ("unknown", "unknown"))
    lines.append(f"## Oracle Linux {ol} support (the OS itself)")
    lines.append("")
    lines.append(f"STATIC, **verified {EOL_VERIFIED}** from {OS_EOL_SOURCES}. The OS may itself be past "
                 "regular support, which is independent of whether AWS CLI v2 installs/runs:")
    lines.append("")
    lines.append(f"- regular support : {os_reg}")
    lines.append(f"- beyond          : {os_ext}")
    lines.append("")
    for kv in kvers:
        rows = [e for e in entries if e.get('kver', '') == kv]
        rows.sort(key=lambda e: vkey(e['awscli_version']))
        glibc = next((e.get('glibc', '') for e in rows if e.get('glibc')), '')
        thk = next((e.get('test_host_kernel', '') for e in rows if e.get('test_host_kernel')), '')
        oks = [e for e in rows if e.get('status') == 'ok']
        max_ok = sorted((e['awscli_version'] for e in oks), key=vkey)[-1] if oks else ''
        all_max = sorted((e['awscli_version'] for e in rows), key=vkey)[-1] if rows else ''
        if not max_ok:
            verd = "**none** -- no AWS CLI v2 version installed+ran in this OL environment"
        elif all_max and ge(max_ok, all_max):
            verd = (f"**current** -- the newest tested v2 `{max_ok}` installs+runs (this OL environment can run "
                    "current AWS CLI v2)")
        else:
            verd = (f"**capped at `{max_ok}`** -- v2 installs+runs up to `{max_ok}`; newer builds need a higher "
                    f"glibc than this environment's `{glibc or '?'}`, so they will not install/run here")
        lines.append(f"## Test environment: OL{ol} kernel {kv}")
        lines.append("")
        lines.append(f"- `env_kernel` : {kv}  (`rpm -q kernel-uek` -- the OL UEK a real instance runs; ledger dedup key)")
        lines.append(f"- `env_glibc` : {glibc or '?'}  (`rpm -q glibc` -- the faithful install/run gate)")
        lines.append(f"- `test_host_kernel` : {thk or '?'}  (the bundle actually executed on the runner's kernel)")
        lines.append("")
        lines.append(f"Verdict: {verd}.")
        lines.append("")
        lines.append("| awscli_version | status | ran | bundled_python | python_eol | compat_min_glibc (measured / heuristic) | note |")
        lines.append("|---|---|---|---|---|---|---|")
        for e in sorted(rows, key=lambda e: vkey(e['awscli_version']), reverse=True):
            note = e.get('reason', '') or ('installed ' + e.get('installed_version', '') if e.get('status') == 'ok' else '')
            note = note.replace('|', '\\|')
            meas = e.get('min_glibc_measured', '') or '?'
            heur = e.get('min_glibc') or min_glibc(e.get('awscli_version', ''))
            bpy = e.get('bundled_python', '') or '?'
            peol = e.get('python_eol', '') or python_eol(e.get('bundled_python', ''))
            lines.append(f"| {e['awscli_version']} | {e.get('status','')} | {'yes' if e.get('ran') else 'no'} | "
                         f"{bpy} | {peol} | {meas} / {heur} | {note} |")
        lines.append("")
    open(os.path.join(results_dir, f"RESULTS-ol{ol}.md"), 'w').write("\n".join(lines).rstrip("\n") + "\n")

print(f"ledger entries: {len(led['entries'])} (+{new_rows} this run); reports for OL: {','.join(sorted(by_ol))}")
PY

# ---- summary ---------------------------------------------------------------
if [ -s "${RESULTS_TSV}" ]; then
  n_total="$(wc -l < "${RESULTS_TSV}")"
  n_ok="$(grep -c '"status":"ok"' "${RESULTS_TSV}" || true)"
  log "summary: ${n_total} install+run test(s) this run, ${n_ok} ok; ledger + RESULTS-ol*.md updated"
else
  log "summary: nothing tested this run (all requested combos already in the ledger, or none in scope); reports regenerated"
fi
