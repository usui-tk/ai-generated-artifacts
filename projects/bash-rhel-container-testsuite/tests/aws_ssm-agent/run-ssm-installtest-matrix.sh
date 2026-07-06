#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Run the SSM Agent install (both init modes) test matrix per RHEL major; append
#   measured rows to the JSON ledger and regenerate RESULTS-rhel<N>.md.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, python3; report mode: none beyond the repo. --run: podman (or the
#   curl-only OCI fallback) + container egress; entitled host for rhel-* repos.
# ----- Usage examples -------------------------------------------------------
#   bash run-ssm-installtest-matrix.sh              # regenerate reports from the ledger
#   OSMAJORS="9 8" bash run-ssm-installtest-matrix.sh --run   # live matrix
# ----- Known limitations ----------------------------------------------------
#   --run is L3 (manual/CI); RESULTS files are generated - never hand-edited.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/aws_ssm-agent/run-ssm-installtest-matrix.sh
#   AWS SSM Agent install-test matrix (framework (b)+(d)) for the RHEL family.
#
# SSM is the init-sensitive tool. Acquired from the AWS S3 RPM
#   https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/<ver>/linux_amd64/amazon-ssm-agent.rpm
# its two axes (the design plan sec 11.2) are:
#   * glibc    - the RPM's libc dependency closure gates install (recorded per
#                major; install success is empirical, no fabricated floor).
#   * init_mode- env_init_mode=none -> install + `amazon-ssm-agent -version`
#                (a `systemctl enable` may warn without PID 1 systemd);
#                env_init_mode=systemd -> boot ubi-init as PID 1, then
#                `systemctl enable`/`start` and verify the unit activates.
# The container shares the HOST kernel, so the go.mod->min-kernel proxy used for
# the OL VM matrix is intentionally dropped. A documented minimum VERSION
# (>= 3.3.3598.0) separates full-feature agents from ec2messages-only ones.
#
# Surfaces: NO-ARG (DEFAULT) runs the full E2E in one shot - sweep every in-scope
# version (min SSM_MIN -> latest) x major x init_mode, persist the ledger, then
# regenerate RESULTS-rhel<N>.md (mirrors the OL model's one-script workflow).
#   --run              : run the sweep + persist the ledger only (needs podman/L3)
#   --generate-results : (re)generate the reports only, hermetic (no containers)
# Knobs: OSMAJORS, INITMODES, SSM_VERSIONS, INSECURE_TLS.
#
# The column-0 pure helpers carry the unit coverage in tests/t009_ssmverdict.sh.
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELEASES="${SCRIPT_DIR}/ssm-releases.json"
LEDGER="${SCRIPT_DIR}/ssm-installtest-ledger.json"
RESULTS_DIR="${SCRIPT_DIR}"
INSTALL_SCRIPT="${PROJ_DIR}/install-aws_ssm-agent.sh"   # kicked by run_matrix (--run)
SSM_MIN="3.3.3598.0"
# r51 (user decision, 2026-07-04): EL6 additionally sweeps adjudicated
# TRACK-RECORD versions below the compliance floor - versions the user
# verified working on real RHEL 6. They are reported in a dedicated
# "legacy" RESULTS section, clearly marked as below the floor.
SSM_LEGACY_VERSIONS_EL6="${SSM_LEGACY_VERSIONS_EL6:-3.0.1479.0}"
FULL="${FULL:-0}"

# go_version_of <version> : read the go_version from the releases JSON (empty if absent).
go_version_of() {
  [ -f "${RELEASES}" ] || { printf ''; return 0; }
  python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
g={v['version']:(v.get('go_version') or '') for v in d.get('versions',[])}
print(g.get(sys.argv[2],''))" "${RELEASES}" "$1" 2>/dev/null || true
}

# go_min_kernel <go_version> : the minimum Linux kernel for the Go toolchain.
# REUSE-BY-COPY from the OL sibling (tests/ssm/run-ssm-installtest-matrix.sh).
go_min_kernel() {
  local gv="$1" maj minr
  [ -n "${gv}" ] || { printf 'unknown'; return 0; }
  maj="${gv%%.*}"; minr="${gv#*.}"; minr="${minr%%.*}"
  case "${maj}" in
    [2-9]|[1-9][0-9]) printf '3.2'; return 0 ;;
  esac
  if [ "${minr:-0}" -ge 21 ] 2>/dev/null; then printf '3.2'
  elif [ "${minr:-0}" -ge 18 ] 2>/dev/null; then printf '2.6.32'
  else printf '2.6.23'; fi
}

# rhel_init <major> : the per-major init system (RESULTS wording; the
# install script MEASURES the branch it used and reports init_system).
rhel_init() {
  case "${1:-}" in
    10|9|8|7) printf 'systemd' ;;
    6)        printf 'upstart' ;;
    *)        printf 'unknown' ;;
  esac
}

# ssm_major_versions <major> <base...> : the sweep set for MAJOR - the base
# (in-scope) set plus, on EL6 only, the legacy track-record versions.
# upstart/EL6 is a legitimate target, not an exception (r51).
ssm_major_versions() {
  local m="$1"; shift
  printf '%s' "$*"
  if [ "${m}" = "6" ] && [ -n "${SSM_LEGACY_VERSIONS_EL6}" ]; then
    printf ' %s' "${SSM_LEGACY_VERSIONS_EL6}"
  fi
  printf '\n'
}
# S3 base for the per-version agent rpm (mirrors install-aws_ssm-agent.sh and
# list-ssm-releases.sh); used by the availability pre-scan (ssm_rpm_http_status).
RPM_BASEURL="${SSM_RPM_BASEURL:-https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent}"

log() { printf '%s [ssm-matrix] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# --- pure helpers (column-0; loaded by t009_ssmverdict.sh) -------------------

# ssm_ge <a> <b> : 4-part dotted-numeric compare, a >= b.
ssm_ge() {
  local a="$1" b="$2" hi
  [ "${a}" = "${b}" ] && return 0
  hi="$(printf '%s\n%s\n' "${a}" "${b}" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)"
  [ "${hi}" = "${a}" ]
}

# rhel_glibc <major> : the MEASURED per-major glibc (the design plan sec 3.2).
rhel_glibc() {
  case "${1:-}" in
    10) printf '2.39' ;; 9) printf '2.34' ;; 8) printf '2.28' ;;
    7)  printf '2.17' ;; 6) printf '2.12' ;; *) printf 'unknown' ;;
  esac
}

# ssm_in_scope <version> <min> <full> : default (>=min) vs --full (all) filter.
ssm_in_scope() {
  local v="${1:-}" min="${2:-}" full="${3:-0}"
  [ "${full}" = "1" ] && return 0
  ssm_ge "${v}" "${min}"
}

# ssm_inscope_versions : the in-scope SSM versions (>= SSM_MIN) in DESCENDING
# order (latest first) - the sweep and report ordering (r57: newest first).
ssm_inscope_versions() {
  releases_versions 2>/dev/null | while IFS= read -r v; do
    [ -n "${v}" ] || continue
    ssm_ge "${v}" "${SSM_MIN}" && printf '%s\n' "${v}"
  done | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n -r
}

# ssm_all_versions : ALL SSM versions in DESCENDING order (--full sweep).
ssm_all_versions() {
  releases_versions 2>/dev/null | while IFS= read -r v; do
    [ -n "${v}" ] || continue; printf '%s\n' "${v}"
  done | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n -r
}

# ssm_compliance <maxver> <min> : headline feature verdict for a major.
#   compliant-capable -> the newest installable agent is >= min (full SSM)
#   ec2messages-only  -> newest installable < min (no full Systems Manager)
#   none              -> nothing installed+ran
ssm_compliance() {
  local maxver="${1:-}" min="${2:-}"
  [ -n "${maxver}" ] || { printf 'none'; return 0; }
  if ssm_ge "${maxver}" "${min}"; then printf 'compliant-capable'; else printf 'ec2messages-only'; fi
}

# ssm_init_outcome <init_mode> : what a successful install can demonstrate.
#   none    -> version-only  (binary smoke; service not PID-1 manageable)
#   systemd -> service-capable (enable/start + unit activation)
ssm_init_outcome() {
  case "${1:-}" in
    none)    printf 'version-only' ;;
    systemd) printf 'service-capable' ;;
    *)       printf 'unknown' ;;
  esac
}

# ssm_verdict <installed> <ran> <init_mode> : the EMPIRICAL per-cell headline.
ssm_verdict() {
  local installed="${1:-false}" ran="${2:-false}" mode="${3:-none}"
  [ "${installed}" = "true" ] || { printf 'install-fail'; return 0; }
  [ "${ran}" = "true" ] || { printf 'installed-no-run'; return 0; }
  case "${mode}" in
    systemd) printf 'runs-service' ;;
    none)    printf 'runs-no-init' ;;
    *)       printf 'runs' ;;
  esac
}

# ssm_rpm_url <ver> : the S3 URL of the agent rpm for a version (rpm is version-
# global - the same artifact for every RHEL major).
ssm_rpm_url() { printf '%s/%s/linux_amd64/amazon-ssm-agent.rpm' "${RPM_BASEURL}" "$1"; }

# ssm_rpm_unavailable <http_status> : true when the rpm is DEFINITIVELY not
# published at S3 - the version tag exists (git ls-remote) but the artifact was
# never distributed. 403/404 = unpublished (a correct terminal status, distinct
# from install-fail). 000/2xx/5xx are NOT unavailable: 000/5xx are transient
# fetch errors to surface as errors, 2xx means the rpm is present.
ssm_rpm_unavailable() { case "${1:-}" in 403|404) return 0 ;; *) return 1 ;; esac; }

# --- releases.json + ledger readers ------------------------------------------

releases_versions() {
  [ -f "${RELEASES}" ] || return 1
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for x in d.get("versions",[]):
    print(x.get("version",""))
PY
}

releases_max() {
  [ -f "${RELEASES}" ] || return 1
  python3 - "${RELEASES}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
vs=[x.get("version","") for x in d.get("versions",[])]
def key(v):
    p=(v.split(".")+["0","0","0","0"])[:4]
    try: return tuple(int(x) for x in p)
    except ValueError: return (0,0,0,0)
print(max(vs,key=key) if vs else "")
PY
}

ledger_cell() { # <major> <version> <init_mode> -> "installed|ran" or empty
  local major="$1" ver="$2" mode="$3"
  [ -f "${LEDGER}" ] || return 0
  python3 - "${LEDGER}" "${major}" "${ver}" "${mode}" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
maj,ver,mode=sys.argv[2],sys.argv[3],sys.argv[4]
for r in d.get("results",[]):
    if str(r.get("osmajor"))==maj and r.get("ssm_version")==ver and r.get("init_mode")==mode:
        print("%s|%s"%(str(r.get("installed")).lower(),str(r.get("ran")).lower())); break
PY
}

ledger_verdict() { # <major> <version> <init_mode> -> the stored verdict (e.g.
  # 'unavailable') or empty. Lets the (hermetic) report honour a TERMINAL status
  # recorded in the ledger instead of recomputing it from installed/ran.
  local major="$1" ver="$2" mode="$3"
  [ -f "${LEDGER}" ] || return 0
  python3 - "${LEDGER}" "${major}" "${ver}" "${mode}" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
maj,ver,mode=sys.argv[2],sys.argv[3],sys.argv[4]
for r in d.get("results",[]):
    if str(r.get("osmajor"))==maj and r.get("ssm_version")==ver and r.get("init_mode")==mode:
        print(r.get("verdict","")); break
PY
}

# ssm_rpm_http_status <ver> : final HTTP status of the agent rpm HEAD (200/403/
# 404/000). NETWORK - used only by the --run availability pre-scan, never by the
# hermetic report. Mirrors list-ssm-releases.sh url_check_status.
ssm_rpm_http_status() {
  local url code
  url="$(ssm_rpm_url "$1")"
  local -a opts=(-sS -I -L -o /dev/null -w '%{http_code}' --max-time "${URL_CHECK_TIMEOUT:-25}")
  [ "${INSECURE_TLS:-0}" = "1" ] && opts+=(-k)
  code="$(curl "${opts[@]}" "${url}" 2>/dev/null || true)"
  [ -n "${code}" ] || code="000"
  printf '%s' "${code}"
}

# --- (d) RESULTS generation (hermetic) ---------------------------------------

# ledger_host_line : format the ledger's 'host' meta as a one-line summary for
# the RESULTS header (or a placeholder if a live run has not populated it yet).
ledger_host_line() {
  [ -f "${LEDGER}" ] || { printf '(not yet run)'; return 0; }
  python3 - "${LEDGER}" <<'PY2' 2>/dev/null || printf '(not yet run)'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("(not yet run)"); sys.exit(0)
h=d.get("host")
if not h: print("(not yet run)"); sys.exit(0)
print("%s, kernel %s %s, SELinux: %s, %s" % (h.get("os","?"),h.get("kernel","?"),h.get("arch","?"),h.get("selinux","?"),h.get("runtime","?")))
PY2
}

generate_results() {
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; nothing to generate"; return 0; }
  python3 - "${LEDGER}" "${RELEASES}" "${RESULTS_DIR}" "${SSM_MIN}" <<'PYREPORT'
import json, os, sys

ledger_path, releases_path, results_dir, min_ver = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def vkey(s):
    p = (str(s).split('.') + ['0','0','0','0'])[:4]
    return tuple(int(x) if str(x).isdigit() else 0 for x in p)

def ge(a, b):
    return vkey(a) >= vkey(b)

def go_min_kernel(gov):
    if not gov: return 'unknown'
    parts = str(gov).split('.')
    try:
        maj = int(parts[0]); minr = int(parts[1]) if len(parts) > 1 else 0
    except ValueError:
        return 'unknown'
    if maj > 1: return '3.2'
    if minr >= 21: return '3.2'
    if minr >= 18: return '2.6.32'
    return '2.6.23'

# load ledger
try:
    led = json.load(open(ledger_path))
except Exception:
    print("ERROR: cannot load ledger"); sys.exit(1)

# load releases for go_version lookup
gv_map = {}
if os.path.exists(releases_path):
    try:
        rd = json.load(open(releases_path))
        gv_map = {v['version']: v.get('go_version', '') for v in rd.get('versions', []) if isinstance(v, dict)}
    except Exception:
        pass

# host metadata
host = led.get("host", {})
if host:
    host_line = "%s, kernel %s %s, SELinux: %s, %s" % (
        host.get("os","?"), host.get("kernel","?"), host.get("arch","?"),
        host.get("selinux","?"), host.get("runtime","?"))
else:
    host_line = "(not yet run)"

# group results by (osmajor, ssm_version) - prefer init_mode=none for the primary
# row; overlay systemd evidence on the representative version.
results = led.get("results", [])
by_major = {}
for r in results:
    m = str(r.get("osmajor", ""))
    by_major.setdefault(m, []).append(r)

for major in sorted(by_major, key=lambda m: int(m) if m.isdigit() else 99):
    rows_raw = by_major[major]
    # deduplicate: (version, init_mode) -> latest entry wins
    seen = {}
    for r in rows_raw:
        k = (r.get("ssm_version",""), r.get("init_mode","none"))
        seen[k] = r
    # for each version, use "none" row as primary; note systemd if available
    ver_data = {}
    for (ver, mode), r in seen.items():
        if ver not in ver_data:
            ver_data[ver] = {"none": None, "systemd": None}
        ver_data[ver][mode] = r

    # build table rows sorted descending
    table_rows = []
    for ver in sorted(ver_data, key=vkey, reverse=True):
        d = ver_data[ver]
        primary = d.get("none") or d.get("systemd") or {}
        status = primary.get("status", "pending")
        ran = primary.get("ran", False)
        installed = primary.get("installed", False)
        reason = primary.get("reason", "")
        gv = gv_map.get(ver, "")
        mk = go_min_kernel(gv) if gv else "unknown"
        if status == "ok" and not reason:
            note = "installed %s" % primary.get("installed_version", ver) if installed else ""
        else:
            note = reason.replace("|", "\\|") if reason else ""
        table_rows.append({
            "version": ver,
            "status": status,
            "ran": ran,
            "go_version": gv or "?",
            "min_kernel": mk,
            "note": note,
        })

    # verdict: find the max ok version from "none" mode
    ok_versions = [ver for ver, d in ver_data.items()
                   if (d.get("none") or {}).get("status") == "ok"
                   or (d.get("systemd") or {}).get("status") == "ok"]
    max_ok = max(ok_versions, key=vkey) if ok_versions else ""
    if not max_ok:
        verdict = "**none** -- nothing installed+ran in this RHEL environment"
    elif ge(max_ok, min_ver):
        verdict = "**compliant-capable** -- max install+run `%s` >= `%s` (remediation possible)" % (max_ok, min_ver)
    else:
        verdict = ("**ec2messages-only** -- max install+run `%s` < `%s`: the required version will "
                   "not install/run in this RHEL environment, so it CANNOT be remediated by an agent "
                   "update and is affected by the 2026-06-16 Run Command ec2messages deprecation" % (max_ok, min_ver))

    # glibc from the first result
    glibc = next((str(r.get("glibc","")) for r in rows_raw if r.get("glibc")), "?")

    # count versions
    all_vers = list(ver_data.keys())
    inscope = [v for v in all_vers if ge(v, min_ver)]

    lines = []
    lines.append("# AWS SSM Agent - RHEL %s install/run results" % major)
    lines.append("")
    lines.append("Generated by `run-ssm-installtest-matrix.sh` from "
                 "`ssm-installtest-ledger.json` -- DO NOT hand-edit (regenerated each run).")
    lines.append("")
    lines.append("## Why this matters -- AWS Systems Manager Run Command deprecation")
    lines.append("")
    lines.append("Starting **2026-06-16**, SSM Run Command stops executing commands on managed instances that "
                 "still use the legacy **ec2messages** (Amazon Message Delivery Service) endpoints -- endpoints "
                 "used only by SSM Agents too old to support the newer **ssmmessages** (Amazon Message Gateway "
                 "Service) endpoints. AWS's remediation is to update the SSM Agent to "
                 "**%s or newer** and grant the instance role the ssmmessages channel permissions "
                 "(`CreateControlChannel` / `CreateDataChannel` / `OpenControlChannel` / `OpenDataChannel`); "
                 "affected instances are listed in the AWS Health Dashboard. This report characterizes, per RHEL "
                 "major, which agent versions install+run -- i.e. whether a RHEL %s image can be brought to a "
                 "**compliant (>= %s)** agent." % (min_ver, major, min_ver))
    lines.append("")
    lines.append("References (AWS docs): "
                 "[Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html); "
                 "[message service endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up-messageAPIs.html#message-services); "
                 "[update SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-tutorial-update-software.html); "
                 "[ssmmessages IAM actions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonmessagegatewayservice.html); "
                 "[check agent version with Fleet Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent-get-version.html).")
    lines.append("")
    lines.append("**Fidelity.** `status=ok` means the RPM installed AND the agent binary ran locally. "
                 "The **glibc** axis is faithful -- the container's real RHEL glibc gates a dynamic "
                 "version's install/run. The container shares the host kernel, so the run does NOT "
                 "exercise the RHEL kernel axis. The static kernel-axis signal is **compat_min_kernel** "
                 "(the Go toolchain's minimum kernel from the release's go.mod).")
    lines.append("")
    lines.append("## Test environment: RHEL %s (glibc %s)" % (major, glibc))
    lines.append("")
    lines.append("- `env_glibc` : %s  (`rpm -q glibc`)" % glibc)
    lines.append("- `test_host` : %s" % host_line)
    lines.append("")
    lines.append("Verdict: %s." % verdict)
    lines.append("")
    lines.append("| ssm_version | status | ran | agent_go_version | compat_min_kernel | note |")
    lines.append("|---|---|---|---|---|---|")
    for row in table_rows:
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            row["version"], row["status"],
            "yes" if row["ran"] else "no",
            row["go_version"], row["min_kernel"],
            row["note"]))
    lines.append("")
    lines.append("_Sweep: %d version(s) tested (%d in-scope >= %s). "
                 "Regenerate: `OSMAJORS=%s ./run-ssm-installtest-matrix.sh`._" % (
                     len(all_vers), len(inscope), min_ver, major))
    lines.append("")

    open(os.path.join(results_dir, "RESULTS-rhel%s.md" % major), 'w').write("\n".join(lines).rstrip("\n") + "\n")
    print("wrote RESULTS-rhel%s.md (%d versions, verdict: %s)" % (major, len(table_rows), verdict.split("**")[1] if "**" in verdict else "?"))
PYREPORT
}

# --- (b) L3 install-test loop (container egress required) ---------------------
# result_field <result-json-line> <key> : extract a value from an install
# script's single-line [installtest][result] JSON (string, bool, or number).
# Pure, jq-free. Reuse-by-copy across the tool matrices.
result_field() {
  local line="$1" key="$2" v
  v="$(printf '%s' "${line}" | grep -oE "\"${key}\":\"[^\"]*\"" | head -1 | sed 's/^[^:]*://; s/\"//g')"
  if [ -z "${v}" ]; then
    v="$(printf '%s' "${line}" | grep -oE "\"${key}\":(true|false|[0-9]+)" | head -1 | sed 's/^[^:]*://')"
  fi
  printf '%s' "${v}"
}

# ensure_ledger : create the ledger skeleton if it is missing (e.g. right after
# `rm -rf *.json`), so a from-scratch `list -> run` still produces the baseline
# evidence file that the report reads. persist_ledger then folds rows into it.
ensure_ledger() {
  [ -f "${LEDGER}" ] && return 0
  cat > "${LEDGER}" <<'JSON'
{
  "tool": "aws_ssm-agent",
  "note": "Empirical install-test ledger. Created/appended by run-ssm-installtest-matrix.sh on a container-egress host (L3); never hand-edited.",
  "results": []
}
JSON
  log "created ledger skeleton: ${LEDGER}"
}

# persist_ledger <rows-file> : fold the swept JSONL rows into ${LEDGER}'s results[]
# (dedup by osmajor+ssm_version+init_mode; last write wins). Atomic tmp+replace.
# This is what turns a --run sweep into durable evidence the report reads.
persist_ledger() {
  local rows="$1"
  [ -f "${LEDGER}" ] || { log "no ledger at ${LEDGER}; skipping persist"; return 0; }
  python3 - "${LEDGER}" "${rows}" <<'PY2' 2>/dev/null || { log "WARNING: ledger persist failed"; return 0; }
import json,sys,os,tempfile
led,rowsfile=sys.argv[1],sys.argv[2]
try: d=json.load(open(led))
except Exception: sys.exit(1)
rows=[]
for ln in open(rowsfile):
    ln=ln.strip()
    if not ln: continue
    try: rows.append(json.loads(ln))
    except Exception: pass
def key(r): return (str(r.get("osmajor")), r.get("ssm_version"), r.get("init_mode"))
merged={}
for r in d.get("results",[]): merged[key(r)]=r
for r in rows: merged[key(r)]=r
d["results"]=[merged[k] for k in sorted(merged, key=lambda k:(int(k[0]) if str(k[0]).isdigit() else 0, k[1] or "", k[2] or ""))]
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(led) or ".")
with os.fdopen(fd,"w") as fh: json.dump(d,fh,indent=2); fh.write("\n")
os.replace(tmp,led)
PY2
  log "ledger updated: ${LEDGER} ($(grep -c '"ssm_version"' "${rows}") rows swept)"
}

run_matrix() {
  ensure_ledger
  command -v podman >/dev/null 2>&1 || { log "ERROR: --run needs podman (L3)"; return 2; }
  [ -f "${INSTALL_SCRIPT}" ] || { log "ERROR: install script missing: ${INSTALL_SCRIPT}"; return 2; }
  # shellcheck source=../../lib/acquire-rootfs.sh
  . "${PROJ_DIR}/lib/acquire-rootfs.sh"
  # shellcheck source=../../lib/provision-test-env.sh
  . "${PROJ_DIR}/lib/provision-test-env.sh"
  host_banner
  # r48 (user requirement): the provisioned test-env images are removed on
  # EVERY exit path - normal completion, failure, or interrupt. Base images
  # (UBI/RHEL) are untouched; KEEP_TEST_IMAGES=1 opts out.
  trap provision_cleanup_images EXIT
  # r46 (D-S1/D-S2): containers run PLAIN. RHSM hosts auto-inject entitled
  # repos per container; the entitled RHUI container path is pending.
  local repo_mode; repo_mode="$(acq_repo_access | cut -d'|' -f1)"
  log "repo access mode: ${repo_mode} (containers run plain; RHSM auto-injection provides entitled repos; RHUI entitled path pending)"
  local ent_mounts=""
  record_host_meta "${LEDGER}"
  acq_preflight "${INSTALL_SCRIPT}" || { log "aborting --run (preflight failed; no rows written)"; return 2; }
  local LOG_DIR="${SCRIPT_DIR}/logs"
  local majors="${OSMAJORS:-10 9 8 7 6}"
  # Case A: install/ran do NOT depend on init_mode, only service_enabled does.
  # So sweep every in-scope version in 'none' (install/run evidence per version),
  # and test 'systemd' (service enablement) only on a representative version per
  # major. Override the none set with SSM_VERSIONS, the systemd set with
  # SSM_SYSTEMD_VERSIONS (default = the latest in-scope version).
  local versions
  if [ -n "${SSM_VERSIONS:-}" ]; then
    versions="${SSM_VERSIONS}"
  elif [ "${FULL}" = "1" ]; then
    versions="$(ssm_all_versions | tr '\n' ' ')"
  else
    versions="$(ssm_inscope_versions | tr '\n' ' ')"
  fi
  local systemd_versions="${SSM_SYSTEMD_VERSIONS:-$(releases_max)}"
  local major ref ver rows_tmp avail_map st prep_map prepared
  local idx total
  rows_tmp="$(mktemp)"
  # PRE-FLIGHT: create a test-ready image for every requested major BEFORE any
  # test runs. A non-optional major that cannot be prepared is a missing test
  # prerequisite -> abort the whole run (no tests). EL6 (PROVISION_OPTIONAL_MAJORS)
  # may be unprovisionable and is then skipped, not fatal.
  prep_map="$(mktemp)"
  provision_prepare_majors "${majors}" "${ent_mounts}" "${prep_map}" || {
    log "aborting --run: test-env prerequisite not met (no tests run)"
    rm -f "${prep_map}" "${rows_tmp}"; return 2
  }
  prepared="$(cut -d' ' -f1 "${prep_map}" | tr '\n' ' ')"
  log "sweep (Case A): prepared majors=[${prepared}] none=[${versions}] systemd-rep=[${systemd_versions}] full=${FULL}"
  # Availability pre-scan (once per in-scope version): the agent rpm is version-
  # global, so a version whose S3 rpm is unpublished (403/404) is 'unavailable'
  # on every major - a correct terminal status, recorded directly (no container).
  avail_map="$(mktemp)"
  # shellcheck disable=SC2086  # the version lists are word-split by design
  for ver in ${versions} ${systemd_versions} ${SSM_LEGACY_VERSIONS_EL6}; do
    grep -q "^${ver} " "${avail_map}" 2>/dev/null && continue
    printf '%s %s\n' "${ver}" "$(ssm_rpm_http_status "${ver}")" >> "${avail_map}"
  done
  # Sweep only the successfully prepared majors (EL6 absent if it could not be built).
  for major in ${prepared}; do
    ref="$(grep -m1 "^${major} " "${prep_map}" | cut -d' ' -f2-)"
    # r57: count total versions for this major and display progress [idx/total]
    local major_versions; major_versions="$(ssm_major_versions "${major}" "${versions}")"
    total=0; for _v in ${major_versions}; do total=$(( total + 1 )); done
    idx=0
    # shellcheck disable=SC2086  # per-major set is word-split by design
    for ver in ${major_versions}; do
      idx=$(( idx + 1 ))
      st="$(grep -m1 "^${ver} " "${avail_map}" | cut -d' ' -f2)"
      if ssm_rpm_unavailable "${st}"; then
        log "RHEL${major} [${idx}/${total}] SSM ${ver}: unavailable (rpm HTTP ${st})"
        ssm_unavail_row "${major}" "${ver}" none "${st}" "${rows_tmp}"
      else
        log "RHEL${major} [${idx}/${total}] SSM ${ver}: install+run test..."
        ssm_kick "${major}" "${ver}" none "${ref}" "${LOG_DIR}" "${rows_tmp}"
      fi
    done
    for ver in ${systemd_versions}; do
      st="$(grep -m1 "^${ver} " "${avail_map}" | cut -d' ' -f2)"
      if ssm_rpm_unavailable "${st}"; then ssm_unavail_row "${major}" "${ver}" systemd "${st}" "${rows_tmp}"
      else ssm_kick "${major}" "${ver}" systemd "${ref}" "${LOG_DIR}" "${rows_tmp}"; fi
    done
    log "---- RHEL${major}: sweep done (${total} versions) ----"
  done
  rm -f "${avail_map}" "${prep_map}"
  persist_ledger "${rows_tmp}"
  rm -f "${rows_tmp}"
}

# ssm_unavail_row <major> <ver> <mode> <http> <rows> : record a version whose S3
# rpm is unpublished (403/404) as a distinct 'unavailable' status - a correct
# terminal state, NOT install-fail - and append it to <rows>. No container runs
# (the fetch is doomed); mirrors the OL sibling's 'unavailable' handling.
ssm_unavail_row() {
  local major="$1" ver="$2" mode="$3" http="$4" rows="$5"
  log "RHEL${major} ${ver}/${mode}: unavailable (rpm unpublished at s3, HTTP ${http})"
  printf '{"status":"unavailable","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":false,"ran":false,"service_enabled":false,"verdict":"unavailable","reason":"rpm not published at s3 (HTTP %s)"}\n' \
    "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${http}" >> "${rows}"
}

# ssm_kick <major> <ver> <mode> <ref> <log_dir> <rows_file> : run one install-test
# in a container, parse the [result], record the row (+reason), and on non-ok
# preserve the container output to <log_dir> (fail/error only).
ssm_kick() {
  local major="$1" ver="$2" mode="$3" ref="$4" log_dir="$5" rows="$6"
  local err_tmp out line installed ran svc status verdict reason row logf rc=0
  err_tmp="$(mktemp)"
  # shellcheck disable=SC2086  # ent_mounts is intentionally word-split into -v/--network args
  out="$(timeout "${RUN_TIMEOUT:-600}" podman run --rm \
          -v "${INSTALL_SCRIPT}:/install-aws_ssm-agent.sh:ro,z" \
          ${ent_mounts:-} \
          -e SSM_INSTALLTEST=1 -e "SSM_VERSION=${ver}" -e "SSM_INIT_MODE=${mode}" -e "INSECURE_TLS=${INSECURE_TLS:-0}" \
          "${ref}" /bin/bash /install-aws_ssm-agent.sh 2>"${err_tmp}")" || rc=$?
  line="$(printf '%s
' "${out}" | grep -F '[aws_ssm-agent][installtest][result]' | tail -1)" || true  # tolerated-empty probe: no result line = reasoned error row (A.5 asymmetry)
  logf="${log_dir}/installtest-rhel${major}-ssm_${ver}_${mode}.log"
  if [ "${rc}" = "124" ]; then
    reason="timed out after ${RUN_TIMEOUT:-600}s (container stalled; possible repo/network wait)"
    status=error; verdict=harness-error
    log "RHEL${major} ${ver}/${mode}: TIMEOUT -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":false,"ran":false,"service_enabled":false,"verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "$(jesc "${reason}")")"
  elif [ -z "${line}" ]; then
    reason="$(python3 -c 'import sys,json; print(json.dumps(" ".join(open(sys.argv[1]).read().split()))[1:-1][:300])' "${err_tmp}" 2>/dev/null || true)"
    [ -n "${reason}" ] || reason="container produced no [result] and no stderr"
    status=error; verdict=harness-error
    log "RHEL${major} ${ver}/${mode}: harness-error -> ${reason}"
    row="$(printf '{"status":"error","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":false,"ran":false,"service_enabled":false,"verdict":"harness-error","reason":"%s"}' \
      "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${reason}")"
  else
    installed="$(result_field "${line}" installed)"; [ "${installed}" = "true" ] || installed=false
    ran="$(result_field "${line}" ran)";             [ "${ran}" = "true" ] || ran=false
    svc="$(result_field "${line}" service_enabled)"; [ "${svc}" = "true" ] || svc=false
    status="$(result_field "${line}" status)"; [ -n "${status}" ] || status=unknown
    verdict="$(ssm_verdict "${installed}" "${ran}" "${mode}")"
    reason="$(jesc "$(result_field "${line}" reason)")"
    row="$(printf '{"status":"%s","osmajor":"%s","ssm_version":"%s","init_mode":"%s","glibc":"%s","installed":%s,"ran":%s,"service_enabled":%s,"verdict":"%s","reason":"%s"}' \
      "${status}" "${major}" "${ver}" "${mode}" "$(rhel_glibc "${major}")" "${installed}" "${ran}" "${svc}" "${verdict}" "${reason}")"
  fi
  if [ "${status}" != "ok" ]; then
    mkdir -p "${log_dir}"
    { printf '=== podman stdout ===
%s
=== podman stderr ===
' "${out}"; cat "${err_tmp}" 2>/dev/null; } > "${logf}" 2>/dev/null || true
    log "  log preserved: ${logf}"
  else
    rm -f "${logf}" 2>/dev/null || true
  fi
  rm -f "${err_tmp}"
  printf '%s
' "${row}"
  printf '%s
' "${row}" >> "${rows}"
}

# --- arg parsing -------------------------------------------------------------
# No-arg default = the full E2E: run the sweep (all in-scope versions x majors x
# init modes), persist the ledger, then regenerate the RESULTS. This mirrors the
# Oracle Linux model project (`./run-...-matrix.sh` does everything in one shot).
#   --run               : run the sweep + persist the ledger only (no report)
#   --generate-results  : (re)generate the reports only, hermetic (no containers)
ACTION="all"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --run)              ACTION="run" ;;
    --generate-results) ACTION="generate-results" ;;
    --full)             FULL=1 ;;
    --releases)         RELEASES="${2:-}"; shift ;;
    --ledger)           LEDGER="${2:-}"; shift ;;
    --results-dir)      RESULTS_DIR="${2:-}"; shift ;;
    -h|--help)          sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) log "unknown option: $1"; exit 2 ;;
  esac
  shift
done

case "${ACTION}" in
  all)              run_matrix || log "run step did not complete (see above); writing reports from the current ledger"; generate_results ;;
  run)              run_matrix ;;
  generate-results) generate_results ;;
esac
