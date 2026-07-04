#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Unified environment probe. Default (--probe-env): classify the host and
#   every RHEL major's readiness (exec/pkgmgr/repos/egress/verdict) into
#   tests/ENV-PROBE.json. --facts: the deep entitlement fact collection
#   (F1-F7 raw logs + facts.tsv, analyzed by tools/analyze-entitlement.sh).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl. Readiness mode needs podman (L3). Facts mode: podman
#   preferred (required for the `mounts` condition and entitled hosts) or
#   root+chroot (sandbox fallback, anonymous facts only).
# ----- Usage examples -------------------------------------------------------
#   bash tests/probe-env.sh                     # readiness, majors 10 9 8 7 6
#   bash tests/probe-env.sh --majors "6"        # readiness, just RHEL 6
#   bash tests/probe-env.sh --facts             # entitlement fact collection
#   bash tests/probe-env.sh --facts --conds auto --outdir /tmp/probe
# ----- Known limitations ----------------------------------------------------
#   Network states are point-in-time; outputs are regenerated, not committed.
#   Facts mode is read-only by design: containers are --rm and the only host
#   writes land under the output directory.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r39 probe unification; readiness logic from
#   the r01-r28 probe-env, fact collection from the r37 probe-entitlement)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/probe-env.sh - unified environment probe (readiness + entitlement facts)
#
# READINESS (default, --probe-env): one short-lived container per major with a
# common set of checks - does the image run at all (exec: pull, arch, old-
# userspace glibc/vsyscall), pkgmgr, whether repolist completes WITH the
# subscription-manager plugins ENABLED and NO manual mounts (the r37/r39
# correction: the pre-r39 probe disabled the very plugin that materializes
# entitled repos, and premised entitlement on manual host mounts - both wrong;
# repo access is auto-injected per container, see the Phase A probe runs),
# S3/EPEL egress, and the pure probe_verdict classifier. Output: a run-log
# banner, a readiness table, and ENV-PROBE.json. The per-major `entitlement`
# field is OBSERVED inside each container: auto-injected (/run/secrets/
# redhat.repo present) or anonymous.
#
# FACTS (--facts): the reproducible entitlement fact collection (formerly
# tests/probe-entitlement.sh, r37). Conditions per major: `auto` (plain run -
# what the runtime injects by itself) and `mounts` (the suite's legacy rhsm
# passthrough, kept ONLY as the A/B comparison arm; Phase A measured it
# harmful on every major). The in-container collector is EMITTED by
# pe_emit_collector() (unit-tested in t023) and never pipes a step's exit
# code away (the r37 collector masked s06/s12 rc behind `| tail`). Output:
# OUTDIR/{MANIFEST.txt,facts.tsv,raw/<major>/<cond>/...}.
#==============================================================================
# errexit deliberately omitted: a probe must keep going on individual failures
# and REPORT them (a failure is a fact, not an abort).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=../lib/acquire-rootfs.sh
. "${PROJ}/lib/acquire-rootfs.sh"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"

OUT_JSON="${HERE}/ENV-PROBE.json"
MAJORS="${OSMAJORS:-10 9 8 7 6}"
CONDS="auto mounts"
OUTDIR=""
DEEP=1
RUN_TIMEOUT="${RUN_TIMEOUT:-900}"
PKG_TIMEOUT="${PKG_TIMEOUT:-300}"

log() { printf '%s [probe-env] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# probe_verdict EXEC S3 EPEL REPOS : pure readiness classifier (unit-tested).
#   blocked  - the image will not even run here (exec != ok)
#   degraded - runs, but a common prerequisite a --run relies on is missing
#              (no S3 or EPEL egress, or yum still stalls)
#   ready    - runs and every common prerequisite holds
probe_verdict() {
  local exec_ok="$1" s3="$2" epel="$3" repos="$4"
  [ "${exec_ok}" = "ok" ] || { printf 'blocked'; return 0; }
  if [ "${s3}" != "ok" ] || [ "${epel}" != "ok" ] || [ "${repos}" = "no-access" ]; then
    printf 'degraded'; return 0
  fi
  printf 'ready'
}

# probe_field OUT KEY : pull KEY=... from the captured probe stdout.
probe_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# probe_one MAJOR : run the common readiness probe in one short-lived
# container, print a JSON object for that major. Bounded by RUN_TIMEOUT; the
# in-container repolist is bounded by PKG_TIMEOUT. Plugins stay ENABLED and
# no mounts are added - the observed state is the auto-injected state.
probe_one() {
  local major="$1" ref out rc=0 rl exec_ok arch redhat pkgmgr repos s3 epel ent verdict
  ref="$(acq_ref_for_major "${major}")" || { printf '{"major":"%s","error":"no image ref"}' "${major}"; return 0; }
  rl="$(pc_repolist_cmd "${major}" enabled)"
  # shellcheck disable=SC2016  # $mgr/$m/$__u/$__n expand inside the container's /bin/sh, not here
  out="$(timeout "${RUN_TIMEOUT}" podman run --rm \
          -e "PKG_TIMEOUT=${PKG_TIMEOUT}" \
          "${ref}" /bin/sh -c '
            echo "EXEC=ok"
            echo "ARCH=$(uname -m 2>/dev/null)"
            echo "REDHAT=$(cat /etc/redhat-release 2>/dev/null | head -1)"
            mgr=""; for m in dnf yum; do command -v "$m" >/dev/null 2>&1 && { mgr="$m"; break; }; done
            echo "PKGMGR=${mgr:-none}"
            if [ -e /run/secrets/redhat.repo ]; then echo "ENT=auto-injected"; else echo "ENT=anonymous"; fi
            if [ -n "$mgr" ]; then
              if timeout "${PKG_TIMEOUT:-300}" '"${rl}"' >/dev/null 2>&1; then
                echo "REPOS=reachable"; else echo "REPOS=no-access"; fi
            else echo "REPOS=no-cmd"; fi
            # egress: retry the WHOLE request so a transient TLS/DNS/connection blip
            # does not flip a target to fail. curl --retry only re-tries what it
            # classifies as transient, and --retry-all-errors is curl 7.71+ (RHEL 6/7
            # ship 7.19/7.29), so we loop in the shell - version-agnostic, retrying
            # on ANY failure (max 3 tries, 1s apart).
            if command -v curl >/dev/null 2>&1; then
              egress() { __u="$1"; __n=0; while [ "$__n" -lt 3 ]; do curl -fsS --max-time 20 -o /dev/null "$__u" 2>/dev/null && return 0; __n=$((__n+1)); [ "$__n" -lt 3 ] && sleep 1; done; return 1; }
              egress https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm && echo "S3=ok" || echo "S3=fail"
              egress https://dl.fedoraproject.org/pub/epel/ && echo "EPEL=ok" || echo "EPEL=fail"
            else echo "S3=unknown"; echo "EPEL=unknown"; fi
          ' 2>/dev/null)" || rc=$?
  if [ "${rc}" = "124" ]; then
    printf '{"major":"%s","image":"%s","exec":"timeout","pkgmgr":"unknown","repos":"unknown","egress_s3":"unknown","egress_epel":"unknown","entitlement":"unknown","verdict":"blocked","reason":"probe timed out after %ss"}' \
      "${major}" "${ref}" "${RUN_TIMEOUT}"
    return 0
  fi
  exec_ok="$(probe_field "${out}" EXEC)"; [ -n "${exec_ok}" ] || exec_ok="fail"
  arch="$(probe_field "${out}" ARCH)"
  redhat="$(probe_field "${out}" REDHAT)"
  pkgmgr="$(probe_field "${out}" PKGMGR)"; [ -n "${pkgmgr}" ] || pkgmgr="unknown"
  repos="$(probe_field "${out}" REPOS)"; [ -n "${repos}" ] || repos="unknown"
  s3="$(probe_field "${out}" S3)"; [ -n "${s3}" ] || s3="unknown"
  epel="$(probe_field "${out}" EPEL)"; [ -n "${epel}" ] || epel="unknown"
  ent="$(probe_field "${out}" ENT)"; [ -n "${ent}" ] || ent="unknown"
  verdict="$(probe_verdict "${exec_ok}" "${s3}" "${epel}" "${repos}")"
  printf '{"major":"%s","image":"%s","arch":"%s","redhat_release":"%s","exec":"%s","pkgmgr":"%s","repos":"%s","egress_s3":"%s","egress_epel":"%s","entitlement":"%s","verdict":"%s"}' \
    "${major}" "${ref}" "${arch}" "$(jesc "${redhat}")" "${exec_ok}" "${pkgmgr}" "${repos}" "${s3}" "${epel}" "${ent}" "${verdict}"
}

probe_readiness() {
  command -v podman >/dev/null 2>&1 || { log "ERROR: --probe-env needs podman (L3)"; return 2; }
  host_banner
  log "probing majors: [${MAJORS}] (RUN_TIMEOUT=${RUN_TIMEOUT}s, PKG_TIMEOUT=${PKG_TIMEOUT}s)"
  local first=1 major j plat
  {
    plat="$(acq_platform)"
    log "platform: ${plat} | repolist runs plugins-ENABLED, no mounts (observed auto-injection)"
    printf '{\n  "host": %s,\n  "platform": "%s",\n  "probes": [\n' "$(host_json)" "${plat}"
    for major in ${MAJORS}; do
      j="$(probe_one "${major}")"
      [ "${first}" = 1 ] || printf ',\n'
      first=0
      printf '    %s' "${j}"
      log "RHEL${major}: $(printf '%s' "${j}" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print("%s | exec=%s repos=%s s3=%s epel=%s ent=%s -> %s" % (d.get("image","?"),d.get("exec","?"),d.get("repos","?"),d.get("egress_s3","?"),d.get("egress_epel","?"),d.get("entitlement","?"),d.get("verdict","?")))
except Exception:
    print("(unparseable)")' 2>/dev/null || printf '(row)')"
    done
    printf '\n  ]\n}\n'
  } > "${OUT_JSON}"
  log "wrote ${OUT_JSON}"
  printf '\n== environment readiness (probe) ==\n'
  python3 - "${OUT_JSON}" <<'PY' 2>/dev/null || cat "${OUT_JSON}"
import json,sys
d=json.load(open(sys.argv[1]))
hdr=("major","pkgmgr","exec","repos","s3","epel","entitle","verdict")
print("%-6s %-8s %-8s %-10s %-6s %-6s %-13s %s" % hdr)
for p in d.get("probes",[]):
    print("%-6s %-8s %-8s %-10s %-6s %-6s %-13s %s" % (
        "RHEL"+str(p.get("major","?")), p.get("pkgmgr","?"), p.get("exec","?"),
        p.get("repos","?"), p.get("egress_s3","?"), p.get("egress_epel","?"),
        p.get("entitlement","?"), p.get("verdict","?")))
print("\nverdict: ready = all common prerequisites hold; degraded = runs but egress/repo gap; blocked = image will not run here.")
PY
}

# ---------------------------------------------------------------------------
# --facts mode: the reproducible entitlement fact collection (ex r37
# tests/probe-entitlement.sh; see TESTING.md "Entitlement fact-probe").
# ---------------------------------------------------------------------------

# pe_emit_collector MAJOR DEEP PKG_TIMEOUT - print the in-container collector
# script. Pure text emission (unit-tested): static parts are QUOTED heredocs
# (what you read is what runs - no emit-time expansion surprises); the per-
# major dynamic lines are printf-inserted. The dnf-only repoinfo step is
# resolved at EMIT time so a yum collector carries no dnf syntax at all.
# No step pipes its exit code away (r37 masked s06/s12 rc behind `| tail`).
pe_emit_collector() {
  local major="$1" deep="$2" ptmo="$3" pm
  pm="$(pc_pm_for_major "${major}")" || return 1
  printf '#!/bin/bash\n# emitted by probe-env.sh --facts - runs INSIDE the image; writes /probe-out only\nset -u\nO=/probe-out\nT=%s\n' "${ptmo}"
  cat <<'PART1'
r() { n="$1"; shift; printf '%s\n' "$*" > "$O/$n.cmd"
      timeout "$T" bash -c "$*" > "$O/$n.out" 2>&1; echo $? > "$O/$n.rc"; }
r s01-os        'cat /etc/redhat-release; uname -m; id -u'
r s02-files-pre 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
mkdir -p "$O/files-pre" "$O/files-post" "$O/certs"
cp -p /etc/yum.repos.d/*.repo "$O/files-pre/" 2>/dev/null
cp -p /etc/pki/product-default/*.pem /etc/pki/product/*.pem "$O/certs/" 2>/dev/null
r s03-secrets   'ls -laR /run/secrets/ 2>&1; sha256sum /run/secrets/redhat.repo 2>&1; ls -laR /etc/pki/rhui/ 2>&1'
PART1
  printf "r s04-repolist-enabled-pre '%s'\n" "$(pc_repolist_cmd "${major}" enabled)"
  printf "r s05-repolist-all         '%s'\n" "$(pc_repolist_cmd "${major}" all)"
  printf "r s06-trigger              '%s -q makecache'\n" "${pm}"
  cat <<'PART2'
cp -p /etc/yum.repos.d/*.repo "$O/files-post/" 2>/dev/null
r s07-files-post 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
PART2
  printf "r s08-repolist-enabled-post '%s'\n" "$(pc_repolist_cmd "${major}" enabled)"
  cat <<'PART2B'
r s13-sm-packages 'rpm -qa "subscription-manager*" "*rhsm*" "python*subscription*" 2>&1 | sort'
PART2B
  if [ "${pm}" = dnf ]; then
    cat <<'PART3'
r s09-repoinfo 'for i in $(dnf -q repolist --enabled 2>/dev/null | awk "NR>1{print \$1}"); do dnf -q repoinfo "$i" | grep -E "^Repo-(id|filename)"; done'
PART3
  fi
  printf "r s10-resolve-build   '%s'\n" "$(pc_resolve_cmd "${pm}" "${deep}" "$(pc_build_pkgset)")"
  printf "r s11-resolve-install '%s'\n" "$(pc_resolve_cmd "${pm}" "${deep}" "$(pc_install_pkgset)")"
  cat <<'PART4'
cand=$(grep -Eio '(codeready-builder-for-rhel-[0-9a-z_.-]+-rpms|rhel-[0-9]+-server-optional-rpms)' "$O/s05-repolist-all.out" 2>/dev/null | sort -u)
printf '%s\n' "$cand" > "$O/s12-crb-candidates.out"
PART4
  # shellcheck disable=SC2016  # $cand/$k/$c expand inside the EMITTED script, not here
  printf 'k=0; for c in $cand; do k=$((k+1))\n  r "s12-crb-enable-$k" "echo repo=$c; %s -q --enablerepo=$c makecache"\ndone\nexit 0\n' "${pm}"
}

# pe_record OUT MAJOR COND KEY VALUE - append one facts.tsv row.
pe_record() { pc_tsv_row "$2" "$3" "$4" "$5" "$6" >> "$1/facts.tsv"; }

# pe_collect_podman MAJOR COND DIR MODE - one podman run executes the
# collector. MODE (rhsm | rhui:<provider> | oci-ol | none, from
# acq_repo_access) selects which legacy mount set the `mounts` A/B arm
# applies - rhsm on subscription-manager hosts, the RHUI file/cert set on
# AWS/Azure RHUI hosts (r40: RHUI is now a first-class probed environment).
pe_collect_podman() {
  local major="$1" cond="$2" dir="$3" mode="$4" ref margs=""
  ref="$(acq_ref_for_major "${major}")" || return 1
  [ "${cond}" = mounts ] && margs="$(acq_entitlement_mount_args "${mode}")"
  pe_emit_collector "${major}" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
  # shellcheck disable=SC2086  # margs is an intentional argv fragment
  timeout "${RUN_TIMEOUT}" podman run --rm ${margs} \
    -v "${dir}:/probe-out:rw,Z" "${ref}" /bin/bash /probe-out/collector.sh
}

# pe_collect_chroot MAJOR COND DIR - sandbox fallback: curl-pull the rootfs,
# bind /proc,/dev + the out dir, run the collector via chroot. Root required.
pe_collect_chroot() {
  local major="$1" cond="$2" dir="$3" work rc
  if [ "${cond}" = mounts ]; then return 90; fi
  work="$(mktemp -d /tmp/probe-ent.XXXXXX)"
  if ! acq_pull_curl "${major}" "${work}/root"; then rm -rf "${work}"; return 91; fi
  cp /etc/resolv.conf "${work}/root/etc/resolv.conf" 2>/dev/null
  mkdir -p "${work}/root/probe-out"
  pe_emit_collector "${major}" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
  mount --bind "${dir}" "${work}/root/probe-out" && \
    mount -t proc proc "${work}/root/proc" && \
    mount --bind /dev "${work}/root/dev"
  timeout "${RUN_TIMEOUT}" chroot "${work}/root" /bin/bash /probe-out/collector.sh
  rc=$?
  umount "${work}/root/dev" "${work}/root/proc" "${work}/root/probe-out" 2>/dev/null
  rm -rf "${work}"
  return "${rc}"
}

# pe_host_inventory OUTDIR - host-side facts the container-side collection
# cannot see: the repo-access classification, the host's repo definition
# files, and CERTIFICATE METADATA ONLY (subject/issuer/dates via openssl;
# private keys and PEM bodies are deliberately NOT collected - the output
# directory travels between machines).
pe_host_inventory() {
  local h="$1/host" f
  mkdir -p "${h}/yum.repos.d"
  { uname -a; cat /etc/redhat-release 2>/dev/null; } > "${h}/host-os.txt" 2>&1
  acq_repo_access > "${h}/repo-access.txt" 2>/dev/null
  rpm -qa 'subscription-manager*' 'rh-amazon-rhui-client*' 'rhui-azure-rhel*' \
          'google-rhui-client*' 2>/dev/null | sort > "${h}/host-packages.txt"
  for f in /etc/yum.repos.d/*.repo; do
    [ -f "${f}" ] && cp -p "${f}" "${h}/yum.repos.d/" 2>/dev/null
  done
  : > "${h}/certs.txt"
  for f in /etc/pki/entitlement/*.pem /etc/pki/rhui/*.pem /etc/pki/rhui/*.crt \
           /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt; do
    [ -e "${f}" ] || continue
    case "${f}" in *-key.pem|*key*) continue ;; esac
    {
      printf '== %s ==\n' "${f}"
      openssl x509 -in "${f}" -noout -subject -issuer -dates 2>&1
    } >> "${h}/certs.txt"
  done
}

pe_facts() {
  local engine major cond dir rc pem tags pid ts mode=none
  if command -v podman >/dev/null 2>&1; then engine=podman
  elif [ "$(id -u)" = 0 ] && command -v chroot >/dev/null 2>&1; then engine=chroot
  else log "--facts needs podman, or root+chroot"; return 2; fi
  mode="$(acq_repo_access | cut -d'|' -f1)"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  OUTDIR="${OUTDIR:-${HERE}/ENTITLEMENT-PROBE-${ts}}"
  mkdir -p "${OUTDIR}"
  {
    echo "engine=${engine}"; echo "date_utc=${ts}"; echo "majors=${MAJORS}"
    echo "conds=${CONDS}"; echo "deep=${DEEP}"; echo "repo_access=${mode}"
    echo "build_pkgs=$(pc_build_pkgset)"; echo "install_pkgs=$(pc_install_pkgset)"
    echo "host=$(uname -sr)"
  } > "${OUTDIR}/MANIFEST.txt"
  pe_host_inventory "${OUTDIR}"
  : > "${OUTDIR}/facts.tsv"
  for major in ${MAJORS}; do
    for cond in ${CONDS}; do
      dir="${OUTDIR}/raw/${major}/${cond}"; mkdir -p "${dir}"
      log "collect major=${major} cond=${cond} engine=${engine} mode=${mode}"
      if [ "${engine}" = podman ]; then pe_collect_podman "${major}" "${cond}" "${dir}" "${mode}"
      else pe_collect_chroot "${major}" "${cond}" "${dir}"; fi
      rc=$?
      pe_record "${OUTDIR}" meta "${major}" "${cond}" collect_rc "${rc}"
      case "${rc}" in
        0)  pe_record "${OUTDIR}" meta "${major}" "${cond}" status ok ;;
        90) pe_record "${OUTDIR}" meta "${major}" "${cond}" status requires-podman ;;
        91) pe_record "${OUTDIR}" meta "${major}" "${cond}" status pull-fail ;;
        *)  pe_record "${OUTDIR}" meta "${major}" "${cond}" status "$(pc_step_verdict "${rc}")" ;;
      esac
      for pem in "${dir}/certs/"*.pem; do
        [ -e "${pem}" ] || continue
        pid="$(pc_product_id "${pem}" 2>/dev/null)" || pid="?"
        tags="$(pc_product_tags "${pem}" 2>/dev/null)" || tags="?"
        pe_record "${OUTDIR}" cert "${major}" "${cond}" "product-$(basename "${pem}")" "id=${pid} tags=${tags}"
      done
    done
  done
  log "done -> ${OUTDIR}"
  log "analyze: bash tools/analyze-entitlement.sh ${OUTDIR}"
}

pe_main() {
  local action=readiness
  while [ $# -gt 0 ]; do
    case "$1" in
      --probe-env) action=readiness; shift ;;
      --facts)     action=facts; shift ;;
      --majors)    MAJORS="$2"; shift 2 ;;
      --conds)     CONDS="$2"; shift 2 ;;
      --outdir)    OUTDIR="$2"; shift 2 ;;
      --json)      OUT_JSON="$2"; shift 2 ;;
      --shallow)   DEEP=0; shift ;;
      -h|--help)   printf 'usage: probe-env.sh [--probe-env|--facts] [--majors "10 9 8 7 6"]\n'
                   printf '       readiness: [--json PATH]\n'
                   printf '       facts:     [--conds "auto mounts"] [--outdir DIR] [--shallow]\n'; return 0 ;;
      *)           log "unknown arg: $1"; return 2 ;;
    esac
  done
  if [ "${action}" = facts ]; then pe_facts; else probe_readiness; fi
}

# t017/t023 source this file with PE_SOURCED=1 to unit-test the pure layer.
if [ "${PE_SOURCED:-0}" != 1 ]; then
  pe_main "$@"
fi
