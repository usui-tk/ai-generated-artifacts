#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Phase A entitlement FACT-PROBE: one deterministic run collects, for every
#   target major x condition, the repo/entitlement facts (F1-F8) the suite's
#   redesign needs - raw logs + machine-readable facts.tsv, analyzable offline
#   by tools/analyze-entitlement.sh.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, curl. Engine: podman (preferred; required for the `mounts`
#   condition and entitled hosts) or root+chroot (sandbox fallback, anonymous
#   facts only). openssl+xxd for product-cert tag extraction.
# ----- Usage examples -------------------------------------------------------
#   bash tests/probe-entitlement.sh                       # majors 10 9 8 7 6
#   bash tests/probe-entitlement.sh --majors "9 8" --conds auto
#   bash tests/probe-entitlement.sh --outdir /tmp/probe --shallow
# ----- Known limitations ----------------------------------------------------
#   Read-only by design: containers are --rm; the ONLY host writes are under
#   the output dir. The `mounts` condition (current suite passthrough, for the
#   A/B comparison) needs podman; chroot mode records requires-podman.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r37: reproducible entitlement fact-probe)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/probe-entitlement.sh - reproducible entitlement fact collection
#
# Replaces the ad-hoc, one-off probing that made the prior investigation
# untrustworthy. Conditions per major:
#   auto   - PLAIN run, no manual mounts: whatever the host/runtime injects
#            by itself (the auto-injection hypothesis) is what we observe.
#   mounts - the suite's CURRENT rhsm passthrough (acq_entitlement_mount_args)
#            as the A/B comparison arm (F3: effect/harm of the manual mounts).
# The in-container collector is EMITTED by pe_emit_collector() (unit-tested in
# t023 for the yum-vs-dnf syntax pitfalls) and runs with subscription-manager
# plugins ENABLED - unlike probe-env.sh, whose --disableplugin repolist cannot
# observe entitled repos by construction (recorded Phase C defect).
# Output: OUTDIR/{MANIFEST.txt,facts.tsv,raw/<major>/<cond>/...}.
#==============================================================================
# errexit deliberately omitted: a fact-probe must keep going on individual
# failures and RECORD them (a failure is a fact, not an abort).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=../lib/acquire-rootfs.sh
. "${PROJ}/lib/acquire-rootfs.sh"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"

MAJORS="10 9 8 7 6"
CONDS="auto mounts"
OUTDIR=""
DEEP=1
RUN_TIMEOUT="${RUN_TIMEOUT:-900}"
PKG_TIMEOUT="${PKG_TIMEOUT:-300}"

log() { printf '%s [probe-ent] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# pe_emit_collector PM DEEP PKG_TIMEOUT - print the in-container collector
# script. Pure text emission (unit-tested): static parts are QUOTED heredocs
# (what you read is what runs - no emit-time expansion surprises); the per-
# manager dynamic lines are printf-inserted. The dnf-only repoinfo step is
# resolved at EMIT time so a yum collector carries no dnf syntax at all.
pe_emit_collector() {
  local pm="$1" deep="$2" ptmo="$3"
  printf '#!/bin/bash\n# emitted by probe-entitlement.sh - runs INSIDE the image; writes /probe-out only\nset -u\nO=/probe-out\nT=%s\n' "${ptmo}"
  cat <<'PART1'
r() { n="$1"; shift; printf '%s\n' "$*" > "$O/$n.cmd"
      timeout "$T" bash -c "$*" > "$O/$n.out" 2>&1; echo $? > "$O/$n.rc"; }
r s01-os        'cat /etc/redhat-release; uname -m; id -u'
r s02-files-pre 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
mkdir -p "$O/files-pre" "$O/files-post" "$O/certs"
cp -p /etc/yum.repos.d/*.repo "$O/files-pre/" 2>/dev/null
cp -p /etc/pki/product-default/*.pem /etc/pki/product/*.pem "$O/certs/" 2>/dev/null
r s03-secrets   'ls -laR /run/secrets/ 2>&1; sha256sum /run/secrets/redhat.repo 2>&1'
PART1
  printf "r s04-repolist-enabled-pre '%s'\n" "$(pc_repolist_cmd "${pm}" enabled)"
  printf "r s05-repolist-all         '%s'\n" "$(pc_repolist_cmd "${pm}" all)"
  printf "r s06-trigger              '%s -q makecache 2>&1 | tail -20'\n" "${pm}"
  cat <<'PART2'
cp -p /etc/yum.repos.d/*.repo "$O/files-post/" 2>/dev/null
r s07-files-post 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
PART2
  printf "r s08-repolist-enabled-post '%s'\n" "$(pc_repolist_cmd "${pm}" enabled)"
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
  printf 'k=0; for c in $cand; do k=$((k+1))\n  r "s12-crb-enable-$k" "%s -q --enablerepo=$c makecache 2>&1 | tail -5; echo repo=$c"\ndone\nexit 0\n' "${pm}"
}

# pe_record OUT MAJOR COND KEY VALUE - append one facts.tsv row.
pe_record() { pc_tsv_row "$2" "$3" "$4" "$5" "$6" >> "$1/facts.tsv"; }

# pe_collect_podman MAJOR COND DIR - one podman run executes the collector.
pe_collect_podman() {
  local major="$1" cond="$2" dir="$3" ref margs=""
  ref="$(acq_ref_for_major "${major}")" || return 1
  [ "${cond}" = mounts ] && margs="$(acq_entitlement_mount_args rhsm)"
  pe_emit_collector "$(pc_pm_for_major "${major}")" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
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
  pe_emit_collector "$(pc_pm_for_major "${major}")" "${DEEP}" "${PKG_TIMEOUT}" > "${dir}/collector.sh"
  mount --bind "${dir}" "${work}/root/probe-out" && \
    mount -t proc proc "${work}/root/proc" && \
    mount --bind /dev "${work}/root/dev"
  timeout "${RUN_TIMEOUT}" chroot "${work}/root" /bin/bash /probe-out/collector.sh
  rc=$?
  umount "${work}/root/dev" "${work}/root/proc" "${work}/root/probe-out" 2>/dev/null
  rm -rf "${work}"
  return "${rc}"
}

pe_main() {
  local engine major cond dir rc pem tags pid ts
  while [ $# -gt 0 ]; do
    case "$1" in
      --majors)  MAJORS="$2"; shift 2 ;;
      --conds)   CONDS="$2"; shift 2 ;;
      --outdir)  OUTDIR="$2"; shift 2 ;;
      --shallow) DEEP=0; shift ;;
      *) log "unknown arg: $1"; return 2 ;;
    esac
  done
  if command -v podman >/dev/null 2>&1; then engine=podman
  elif [ "$(id -u)" = 0 ] && command -v chroot >/dev/null 2>&1; then engine=chroot
  else log "need podman, or root+chroot"; return 2; fi
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  OUTDIR="${OUTDIR:-${HERE}/ENTITLEMENT-PROBE-${ts}}"
  mkdir -p "${OUTDIR}"
  {
    echo "engine=${engine}"; echo "date_utc=${ts}"; echo "majors=${MAJORS}"
    echo "conds=${CONDS}"; echo "deep=${DEEP}"
    echo "build_pkgs=$(pc_build_pkgset)"; echo "install_pkgs=$(pc_install_pkgset)"
    echo "host=$(uname -sr)"
  } > "${OUTDIR}/MANIFEST.txt"
  : > "${OUTDIR}/facts.tsv"
  for major in ${MAJORS}; do
    for cond in ${CONDS}; do
      dir="${OUTDIR}/raw/${major}/${cond}"; mkdir -p "${dir}"
      log "collect major=${major} cond=${cond} engine=${engine}"
      if [ "${engine}" = podman ]; then pe_collect_podman "${major}" "${cond}" "${dir}"
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

# t023 sources this file with PE_SOURCED=1 to unit-test the emit/record layer.
if [ "${PE_SOURCED:-0}" != 1 ]; then
  pe_main "$@"
fi
