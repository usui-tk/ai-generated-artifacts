#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Standalone AWS-RHUI fact collector. Runs ON a real AWS EC2 RHEL host
#   (majors 6-10) and gathers everything needed to answer "does AWS RHUI authorize by
#   OS major, or only by configuration/parameters?" - the pre-work for deciding
#   whether the suite's RHSM-entitled tests can run under RHUI instead. Output
#   is a SINGLE tar.gz for offline analysis by Claude.
#     Categories: (base) OS/repos/RHUI-client RPM/plugins/dnf-vars/repolist;
#     (pkgs) RPM-file analysis of the RHUI/leapp packages WITHOUT installing
#     them (download-only + rpm -q*p + payload extraction - answers "does
#     leapp-rhui-aws ship certs or only repo files?" non-destructively);
#     (certs) the FULL /etc/pki/rhui tree INCLUDING PRIVATE KEYS + openssl/rct
#     decodes + a COVERAGE self-check (origin sha256 manifest vs the copies,
#     plus every ssl* path referenced by any .repo checked for presence);
#     (crossmajor) host-cert HTTPS reachability of OTHER majors' content paths;
#     (eus) EUS/ELS/AUS/E4S repo enumeration; (leapp) an OPT-IN NON-DESTRUCTIVE
#     `leapp preupgrade --no-rhsm` dry-run (majors 7/8/9); (chain) curl-native
#     forward chain INCLUDING actual build-material RPM acquisition per
#     reachable major (proof of obtainability, not just reachability).
# ----- Prerequisites --------------------------------------------------------
#   bash 4+, run as root on the target RHEL EC2 instance, curl, tar, openssl.
#   Network egress to the region RHUI endpoint + IMDS. The instance is expected
#   to be DISPOSABLE: --leapp installs packages and writes /var/log/leapp.
# ----- Usage examples -------------------------------------------------------
#   sudo bash collect-aws-rhui-facts.sh             # auto-detect major, base collection
#   sudo bash collect-aws-rhui-facts.sh --chain         # multi-hop cert-chain probe
#   sudo bash collect-aws-rhui-facts.sh --chain --keep-rpms  # keep fetched RPM blobs
#   sudo bash collect-aws-rhui-facts.sh --leapp         # opt-in preupgrade dry-run
#   sudo bash collect-aws-rhui-facts.sh --major 8 --outdir /tmp/rhui
#   sudo bash collect-aws-rhui-facts.sh --no-crossmajor --no-eus --no-pkgs
# ----- Known limitations ----------------------------------------------------
#   * The output tar.gz CONTAINS PRIVATE KEYS (RHUI entitlement credential).
#     Treat it as a secret: never commit it, transfer over a secure channel.
#     (The keys are collected UNPROCESSED by explicit operator decision: the
#     repository only ever receives this script, never a collected archive.)
#   * leapp preupgrade (opt-in --leapp) is dry-run only; this script NEVER runs
#     `leapp upgrade`. The EUS `--channel eus` preupgrade variant is out of
#     scope here (base+eus enumeration captures the EUS repo shape).
#   * The multi-hop chain (--chain) rides the in-spec N->N+1 leapp-rhui-aws
#     cert bundling REPEATEDLY, which is OUT OF SPEC beyond N+1. It may work
#     today and be closed by an RHUI-side change tomorrow; every archive is a
#     point-in-time record, never a durability promise.
#   * Build-material RPMs fetched by --chain are verified (HTTP status, sha256,
#     rpm -qip) and then DELETED to keep the archive small; --keep-rpms keeps
#     the blobs. leapp-rhui-aws carrier RPMs are always kept (chain evidence).
#   * Raw primary metadata blobs (81-115MB gz each; 294MB of the 307MB r80 el8
#     archive) are slimmed after use to sha256 + package-name list + <package>
#     slices of the interest set; --keep-metadata retains the raw blobs.
#   * Network states are point-in-time. Real-RHUI E2E is the operator's task
#     (this sandbox cannot reproduce RHUI responses).
#   * AWS-SPECIFIC: the RHUI endpoint shape, the IMDS-signed instance-identity
#     authorization (X-RHUI-ID / X-RHUI-SIGNATURE), and the leapp-rhui-aws
#     package are all AWS. Azure / GCP get their own sibling collectors
#     (collect-azure-rhui-facts.sh / collect-gcp-rhui-facts.sh) - do NOT
#     overload this one with other clouds.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Opus 4.8), claude.ai sessions
#   Generation date: 2026-07-08 (RHUI entitlement investigation; helpers are
#   reuse-by-copy of tests/probe-env.sh pe_host_inventory / pe_rhui_crossmajor
#   and lib/probe-common.sh, per ADR 0003 self-contained user-runnable script)
# ---------------------------------------------------------------------------
#==============================================================================
# tests/collect-aws-rhui-facts.sh - AWS RHUI: one host, one major, one tar.gz.
#
# Self-contained by ADR 0003: a user copies this ONE file to a disposable EC2
# instance and runs it; it sources no project library. The pure helpers below
# are reuse-by-copy of lib/probe-common.sh (pm/repolist/b64url/major-url) and
# the collection logic mirrors tests/probe-env.sh pe_host_inventory and
# pe_rhui_crossmajor_check - proven on 2026-07-04, here made key-inclusive and
# leapp-aware per the operator's explicit decision (full key material required
# for the design analysis; metadata-only would force partial judgements).
#
# errexit deliberately omitted: a collector must keep going on individual
# failures and RECORD them (a failure is a fact, not an abort). Every probed
# command is captured as a .cmd/.out/.rc triple so no exit code is ever hidden
# behind a pipe (STARTUP-CORE execution discipline 4.1).
#==============================================================================
set -uo pipefail

RC_TOOL_VERSION="1.5.0"
# Packages whose <package> XML slices survive the primary-blob slimming
# (alternation for one POSIX-awk pass; fixed names, no regex metacharacters).
RC_SLIM_WL="kernel-devel|gcc|make|elfutils-libelf-devel|leapp-rhui-aws"
RC_CLOUD="aws"   # this collector is AWS-specific; other clouds get sibling scripts
RC_CMD_TIMEOUT="${RC_CMD_TIMEOUT:-120}"

rc_log() { printf '%s [collect-rhui] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

#------------------------------------------------------------------------------
# Pure helpers (unit-tested by tests/t025_rhuicollect.sh) - reuse-by-copy of
# lib/probe-common.sh. Kept byte-faithful to the proven originals.
#------------------------------------------------------------------------------

# rc_pm_for_major MAJOR - the package manager binary for a RHEL major.
rc_pm_for_major() {
  case "$1" in
    10|9|8) printf 'dnf\n' ;;
    7|6)    printf 'yum\n' ;;
    *)      return 1 ;;
  esac
}

# rc_repolist_cmd MAJOR SCOPE(enabled|all) - the repolist command per major.
rc_repolist_cmd() {
  case "$1:$2" in
    10:enabled|9:enabled|8:enabled) printf '%s\n' 'dnf -q repolist --enabled' ;;
    10:all|9:all|8:all)             printf '%s\n' 'dnf -q repolist --all' ;;
    7:enabled)                      printf '%s\n' 'yum -q repolist enabled' ;;
    7:all)                          printf '%s\n' 'yum -q repolist all' ;;
    6:enabled)                      printf '%s\n' 'yum repolist enabled' ;;
    6:all)                          printf '%s\n' 'yum repolist all' ;;
    *)                              return 1 ;;
  esac
}

# rc_b64url - stdin -> urlsafe base64 (RHUI X-RHUI-ID/SIGNATURE encoding).
rc_b64url() { base64 -w0 | tr '+/' '-_'; }

# rc_rhui_major_url TEMPLATE MAJOR - synthesize another major's RHUI content
# URL from a host repo template (retarget /rhelN/, $releasever, $basearch).
# Pure; REGION substitution is the caller's job.
rc_rhui_major_url() {
  printf '%s\n' "$1" | sed -E \
    -e "s#/rhel[0-9]+/#/rhel$2/#" \
    -e "s#\\\$releasever#$2#g" \
    -e "s#\\\$basearch#x86_64#g"
}

# rc_leapp_target MAJOR - the in-place upgrade target major (empty if none:
# RHEL 6 has no leapp path; RHEL 10 has no released N+1). Decides whether the
# cross-major leapp dry-run applies.
rc_leapp_target() {
  case "$1" in
    9) printf '10\n' ;;
    8) printf '9\n' ;;
    7) printf '8\n' ;;
    *) return 1 ;;
  esac
}

# rc_chain_list MAJOR - the downstream majors reachable by REPEATED leapp hops,
# in order (pure). This is the "materialize N+1's cert, then use N+1 to reach
# N+2's cert" chain: 8 -> "9 10", 9 -> "10", else empty. It only lists what is
# ACQUIRABLE cert-wise; whether the server then authorizes non-adjacent content
# is exactly the open question the chain probe measures.
rc_chain_list() {
  local m="$1" out="" t
  while t="$(rc_leapp_target "${m}")"; do
    out="${out:+${out} }${t}"
    m="${t}"
  done
  [ -n "${out}" ] && printf '%s\n' "${out}"
  return 0
}

# rc_detect_major - best-effort RHEL major from the release file (path via
# RC_RELEASE_FILE so the parse is unit-testable against a fixture).
rc_detect_major() {
  local rel="${RC_RELEASE_FILE:-/etc/redhat-release}" line
  [ -f "${rel}" ] || return 1
  line="$(cat "${rel}" 2>/dev/null)"
  printf '%s\n' "${line}" | grep -oE 'release [0-9]+' | grep -oE '[0-9]+' | head -1
}

#------------------------------------------------------------------------------
# Command recorder: NAME.cmd / NAME.out / NAME.rc under a section dir. Never
# pipes a command's exit code away.
#------------------------------------------------------------------------------
# rc_run DIR NAME CMD... - run CMD (joined), record the triple.
rc_run() {
  local dir="$1" name="$2"; shift 2
  local cmd="$*"
  mkdir -p "${dir}"
  printf '%s\n' "${cmd}" > "${dir}/${name}.cmd"
  timeout "${RC_CMD_TIMEOUT}" bash -c "${cmd}" > "${dir}/${name}.out" 2>&1
  printf '%s\n' "$?" > "${dir}/${name}.rc"
}

#------------------------------------------------------------------------------
# IMDS (region + signed instance identity for RHUI authorization headers).
#------------------------------------------------------------------------------
RC_IMDS_TOKEN=""
rc_imds_token() {
  RC_IMDS_TOKEN="$(curl -sS -m 5 -X PUT http://169.254.169.254/latest/api/token \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 120' 2>/dev/null)"
}
rc_imds_get() {
  local path="$1" v
  v="$(curl -sS -m 5 -H "X-aws-ec2-metadata-token: ${RC_IMDS_TOKEN}" \
    "http://169.254.169.254/latest/${path}" 2>/dev/null)"
  [ -n "${v}" ] && { printf '%s' "${v}"; return 0; }
  curl -sS -m 5 "http://169.254.169.254/latest/${path}" 2>/dev/null
}

#------------------------------------------------------------------------------
# Collectors (side-effecting; run on the host).
#------------------------------------------------------------------------------

# rc_collect_base OUTDIR MAJOR
rc_collect_base() {
  local out="$1/base" major="$2" pm
  pm="$(rc_pm_for_major "${major}")" || pm=dnf
  mkdir -p "${out}/yum.repos.d"
  rc_run "${out}" s01-os        'cat /etc/redhat-release; uname -a; id -u'
  rc_run "${out}" s02-repos-pre 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
  cp -p /etc/yum.repos.d/*.repo "${out}/yum.repos.d/" 2>/dev/null

  # RHUI client + subscription packages, deeply (rpm -qi/-ql/--scripts).
  rc_run "${out}" s03-rhui-packages \
    'rpm -qa "rh-amazon-rhui-client*" "rhui-azure-rhel*" "google-rhui-client*" "leapp-rhui-*" "subscription-manager*" "*rhsm*" 2>&1 | sort'
  local pkg
  for pkg in rh-amazon-rhui-client rh-amazon-rhui-client-ha leapp-rhui-aws \
             amazon-libdnf-plugin subscription-manager; do
    rpm -q "${pkg}" >/dev/null 2>&1 || continue
    rc_run "${out}" "s04-rpm-qi-${pkg}"       "rpm -qi ${pkg}"
    rc_run "${out}" "s05-rpm-ql-${pkg}"       "rpm -ql ${pkg}"
    rc_run "${out}" "s06-rpm-scripts-${pkg}"  "rpm -q --scripts ${pkg}"
    rc_run "${out}" "s06-rpm-triggers-${pkg}" "rpm -q --triggers ${pkg}"
  done

  # repolist (enabled + all) and per-repo info.
  local rl_en rl_all
  rl_en="$(rc_repolist_cmd "${major}" enabled)" || rl_en='dnf -q repolist --enabled'
  rl_all="$(rc_repolist_cmd "${major}" all)"    || rl_all='dnf -q repolist --all'
  rc_run "${out}" s07-repolist-enabled "${rl_en}"
  rc_run "${out}" s08-repolist-all     "${rl_all}"
  if [ "${pm}" = dnf ]; then
    rc_run "${out}" s09-repoinfo-all 'dnf -q repoinfo --all 2>&1'
  else
    rc_run "${out}" s09-repoinfo-all 'yum-config-manager 2>&1 || cat /etc/yum.repos.d/*.repo 2>&1'
  fi

  # RHUI/dnf plugin machinery + dnf/yum vars (config-driven authorization surface).
  rc_run "${out}" s10-dnf-vars 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'
  rc_run "${out}" s11-plugins  'ls -laR /etc/dnf/plugins/ /etc/yum/pluginconf.d/ 2>&1; grep -rH . /etc/dnf/plugins/ /etc/yum/pluginconf.d/ 2>/dev/null'
  # Copy the RHUI client implementation sources (py/conf/repo/vars) for analysis.
  mkdir -p "${out}/rhui-client-src"
  for pkg in rh-amazon-rhui-client rh-amazon-rhui-client-ha leapp-rhui-aws amazon-libdnf-plugin; do
    rpm -q "${pkg}" >/dev/null 2>&1 || continue
    local f
    while IFS= read -r f; do
      case "${f}" in
        *.py|*.conf|*.repo|*/dnf/vars/*|*/yum/vars/*)
          [ -f "${f}" ] && cp -p --parents "${f}" "${out}/rhui-client-src/" 2>/dev/null ;;
      esac
    done < <(rpm -ql "${pkg}" 2>/dev/null)
  done

  # IMDS region/identity presence (identity used in place for crossmajor).
  {
    printf 'region=%s\n' "$(rc_imds_get meta-data/placement/region)"
    printf 'instance-id=%s\n' "$(rc_imds_get meta-data/instance-id)"
    printf 'ami-id=%s\n' "$(rc_imds_get meta-data/ami-id)"
  } > "${out}/s12-imds.txt" 2>&1

  # Dynamic plugin discovery: the fixed package list above can miss a
  # generation-specific plugin shape. Reverse-map (rpm -qf) every file that
  # actually lives in the pm plugin directories, so an unexpected owner shows
  # up as a fact instead of a silent hole.
  # shellcheck disable=SC2016  # $f expands inside rc_run's bash -c, not here
  rc_run "${out}" s13-plugin-owners \
    'for f in /usr/lib/python*/site-packages/dnf-plugins/* /usr/share/dnf-plugins/* /usr/lib/yum-plugins/* /usr/lib64/libdnf/plugins/* /etc/dnf/plugins/* /etc/yum/pluginconf.d/*; do [ -e "$f" ] || continue; printf "%s -> %s\n" "$f" "$(rpm -qf "$f" 2>&1)"; done'
  rc_run "${out}" s14-rhui-pkg-sweep 'rpm -qa 2>/dev/null | grep -iE "amazon|rhui|leapp" | sort; true'
}

# rc_collect_pkgs OUTDIR MAJOR - RPM-FILE analysis WITHOUT installing anything:
# download-only acquisition of the RHUI/leapp packages, then rpm -qip / -qlp /
# -qp --scripts / -qp --triggers on the FILES, then payload extraction
# (rpm2cpio) so the exact shipped .repo/cert/plugin material is in the archive.
# This answers the memo's item 7 ("does leapp-rhui-aws update certs, or only
# repo files?") with zero mutation of the host. Keys inside payloads are kept
# unprocessed (same operator decision as certs/).
rc_collect_pkgs() {
  local out="$1/pkgs" major="$2" pm pkg dl rpmf name
  pm="$(rc_pm_for_major "${major}")" || pm=dnf
  mkdir -p "${out}/rpms"
  for pkg in rh-amazon-rhui-client rh-amazon-rhui-client-ha leapp-rhui-aws \
             amazon-libdnf-plugin; do
    dl="${out}/rpms"
    # Download-only, two ladders per pm family; every rung's rc is recorded.
    if [ "${pm}" = dnf ]; then
      rc_run "${out}" "p01-download-${pkg}" \
        "dnf -y download --destdir '${dl}' ${pkg} 2>&1 || dnf -y install --downloadonly --destdir='${dl}' ${pkg} 2>&1"
    else
      rc_run "${out}" "p01-download-${pkg}" \
        "yumdownloader --destdir '${dl}' ${pkg} 2>&1 || yum -y install --downloadonly --downloaddir='${dl}' ${pkg} 2>&1"
    fi
    # Analyze exactly the file(s) matching this package name (deps that
    # --downloadonly may have pulled are left in rpms/ as-is - more facts).
    for rpmf in "${dl}/${pkg}"-[0-9]*.rpm; do
      [ -e "${rpmf}" ] || continue
      name="$(basename "${rpmf}" .rpm)"
      rc_run "${out}" "p02-rpm-qip-${name}"      "rpm -qip '${rpmf}'"
      rc_run "${out}" "p03-rpm-qlp-${name}"      "rpm -qlp '${rpmf}'"
      rc_run "${out}" "p04-rpm-scripts-${name}"  "rpm -qp --scripts '${rpmf}'"
      rc_run "${out}" "p05-rpm-triggers-${name}" "rpm -qp --triggers '${rpmf}'"
      rc_run "${out}" "p06-rpm-sha256-${name}"   "sha256sum '${rpmf}'"
      mkdir -p "${out}/payload/${name}"
      rc_run "${out}" "p07-extract-${name}" \
        "cd '${out}/payload/${name}' && rpm2cpio '${rpmf}' | cpio -idmu 2>&1"
      rc_run "${out}" "p08-payload-find-${name}" \
        "find '${out}/payload/${name}' -type f | sort"
    done
  done
}

# rc_collect_certs OUTDIR - FULL /etc/pki/rhui tree INCLUDING PRIVATE KEYS
# (operator decision) plus openssl x509 / rct decodes. The archive is a secret.
rc_collect_certs() {
  local out="$1/certs" d f cov rel osum csum miss=0 mism=0 total=0 p
  mkdir -p "${out}/pki"
  cov="${out}/COVERAGE.txt"
  # 1) ORIGIN manifest FIRST: what exists on the host, with sha256, before any
  #    copy. "Unprocessed data" is only claimable if the archive itself can
  #    prove the copies match the origin.
  : > "${out}/origin-sha256.txt"
  for d in /etc/pki/rhui /etc/pki/entitlement /etc/pki/product \
           /etc/pki/product-default; do
    [ -d "${d}" ] || continue
    find "${d}" -type f -print0 2>/dev/null | sort -z \
      | xargs -0 -r sha256sum >> "${out}/origin-sha256.txt" 2>>"${out}/origin-errors.txt"
  done
  # 2) Verbatim copy (keys included) with the rc RECORDED, not swallowed.
  : > "${cov}"
  for d in /etc/pki/rhui /etc/pki/entitlement /etc/pki/product \
           /etc/pki/product-default; do
    [ -d "${d}" ] || { printf 'ABSENT-DIR: %s\n' "${d}" >> "${cov}"; continue; }
    cp -rp --parents "${d}" "${out}/pki/" 2>>"${out}/origin-errors.txt"
    printf 'COPY: %s rc=%s\n' "${d}" "$?" >> "${cov}"
  done
  # 3) Coverage diff: every origin file must exist in the copy with the SAME
  #    sha256. missing=0 mismatch=0 is the only healthy verdict.
  while IFS= read -r rel; do
    osum="${rel%%  *}"; p="${rel#*  }"
    total=$((total + 1))
    if [ ! -f "${out}/pki${p}" ]; then
      printf 'MISSING: %s\n' "${p}" >> "${cov}"; miss=$((miss + 1)); continue
    fi
    csum="$(sha256sum "${out}/pki${p}" 2>/dev/null)"; csum="${csum%%  *}"
    if [ "${osum}" != "${csum}" ]; then
      printf 'MISMATCH: %s origin=%s copy=%s\n' "${p}" "${osum}" "${csum}" >> "${cov}"
      mism=$((mism + 1))
    fi
  done < "${out}/origin-sha256.txt"
  local cverdict=INCOMPLETE
  if [ "${total}" = 0 ]; then cverdict=EMPTY
  elif [ "${miss}" = 0 ] && [ "${mism}" = 0 ]; then cverdict=OK; fi
  printf 'coverage: total=%s missing=%s mismatch=%s verdict=%s\n' \
    "${total}" "${miss}" "${mism}" "${cverdict}" >> "${cov}"
  # 4) Repo-reference closure: every ssl* path any .repo points at must exist
  #    on the host AND be inside the collected set - a referenced-but-uncollected
  #    credential is exactly the hole this check exists to catch.
  while IFS= read -r p; do
    [ -n "${p}" ] || continue
    if [ ! -e "${p}" ]; then
      printf 'REPO-REF-DANGLING: %s (referenced by a .repo, absent on host)\n' "${p}" >> "${cov}"
    elif [ -f "${out}/pki${p}" ]; then
      printf 'REPO-REF-OK: %s\n' "${p}" >> "${cov}"
    else
      printf 'REPO-REF-UNCOLLECTED: %s (exists on host, outside collected dirs)\n' "${p}" >> "${cov}"
    fi
  done < <(sed -n 's/^ssl\(clientcert\|clientkey\|cacert\)=//p' \
             /etc/yum.repos.d/*.repo 2>/dev/null | sort -u)
  # x509 decode (full -text: subject/issuer/serial/validity/SAN/keyusage/EKU).
  : > "${out}/x509-decode.txt"
  for f in /etc/pki/rhui/*.pem /etc/pki/rhui/*.crt \
           /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt \
           /etc/pki/entitlement/*.pem; do
    [ -e "${f}" ] || continue
    case "${f}" in *-key.pem|*key*) continue ;; esac
    {
      printf '== %s ==\n' "${f}"
      openssl x509 -in "${f}" -noout -text 2>&1
      printf -- '-- fingerprint --\n'
      openssl x509 -in "${f}" -noout -fingerprint -sha256 2>&1
    } >> "${out}/x509-decode.txt"
  done
  # Private-key decode (operator wants full material captured, not metadata).
  : > "${out}/key-decode.txt"
  for f in /etc/pki/rhui/*-key.pem /etc/pki/rhui/*.key \
           /etc/pki/entitlement/*-key.pem; do
    [ -e "${f}" ] || continue
    {
      printf '== %s ==\n' "${f}"
      openssl pkey -in "${f}" -noout -text 2>&1
    } >> "${out}/key-decode.txt"
  done
  # rct cat-cert decodes the content-set extension into readable repo paths.
  if command -v rct >/dev/null 2>&1; then
    : > "${out}/content-sets.txt"
    for f in /etc/pki/rhui/product/*.pem /etc/pki/rhui/product/*.crt \
             /etc/pki/entitlement/*.pem; do
      [ -e "${f}" ] || continue
      case "${f}" in *-key.pem|*key*) continue ;; esac
      {
        printf '== rct cat-cert %s ==\n' "${f}"
        rct cat-cert "${f}" 2>&1
      } >> "${out}/content-sets.txt"
    done
  fi
}

# rc_crossmajor_probe_one OUT CERT KEY LABEL URL CAARG HDR... - follow the
# mirrorlist body to the first mirror and GET repomd.xml with the client cert.
rc_crossmajor_probe_one() {
  local out="$1" cert="$2" key="$3" label="$4" url="$5"; shift 5
  local body mlst first rstat
  body="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "$@" \
    -w '\n__HTTP__%{http_code}' "${url}" 2>/dev/null)"
  mlst="${body##*__HTTP__}"
  first="$(printf '%s\n' "${body}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
  if [ -n "${first}" ]; then
    rstat="$(curl -sS -m 20 -o /dev/null -w '%{http_code}' \
      --cert "${cert}" --key "${key}" "$@" \
      "${first%/}/repodata/repomd.xml" 2>/dev/null)"
  else
    rstat="no-mirror"
  fi
  printf '%s mirrorlist_http=%s repomd_http=%s first_mirror=%s\n' \
    "${label}" "${mlst:-000}" "${rstat}" "${first:-none}" >> "${out}"
}

# rc_collect_crossmajor OUTDIR - does THIS host's RHUI client cert reach OTHER
# majors' content? Reuse-by-copy of pe_rhui_crossmajor_check. Keys used in
# place. rhel99 is the calibration control (expected non-200).
rc_collect_crossmajor() {
  local out="$1/crossmajor/rhui-crossmajor.txt" repo=/etc/yum.repos.d/redhat-rhui.repo
  local sec tmpl cert key ca region url m caarg=() m_list
  mkdir -p "$1/crossmajor"
  [ -f "${repo}" ] || { echo "skipped: ${repo} absent (not an AWS RHUI host?)" > "${out}"; return 0; }
  sec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${repo}")"
  tmpl="$(printf '%s\n' "${sec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  cert="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientcert=//p' | head -1)"
  key="$(printf '%s\n' "${sec}" | sed -n 's/^sslclientkey=//p' | head -1)"
  ca="$(printf '%s\n' "${sec}" | sed -n 's/^sslcacert=//p' | head -1)"
  if [ -z "${tmpl}" ] || [ ! -f "${cert}" ] || [ ! -f "${key}" ]; then
    echo "skipped: baseos mirrorlist template or client cert/key unavailable" > "${out}"; return 0
  fi
  region="$(rc_imds_get meta-data/placement/region)"
  {
    printf 'region=%s\n' "${region:-unresolved}"
    printf 'template=%s\n' "${tmpl}"
    printf 'cert=%s\n' "${cert}"
    printf 'key=%s (used in place, full copy is under certs/)\n' "${key}"
  } > "${out}"
  [ -n "${region}" ] || { echo "skipped: region unresolved via IMDS" >> "${out}"; return 0; }
  [ -n "${ca}" ] && [ -f "${ca}" ] && caarg=(--cacert "${ca}")
  # AWS RHUI authorization = TLS client cert AND the SIGNED instance-identity
  # document, sent as X-RHUI-ID / X-RHUI-SIGNATURE (urlsafe base64).
  local id_doc id_sig hdr=()
  id_doc="$(rc_imds_get dynamic/instance-identity/document)"
  id_sig="$(rc_imds_get dynamic/instance-identity/signature)"
  if [ -n "${id_doc}" ] && [ -n "${id_sig}" ]; then
    hdr=(-H "X-RHUI-ID: $(printf '%s' "${id_doc}" | rc_b64url)"
         -H "X-RHUI-SIGNATURE: $(printf '%s' "${id_sig}" | rc_b64url)")
    echo "identity_headers=present" >> "${out}"
  else
    echo "identity_headers=UNAVAILABLE (expect 403s)" >> "${out}"
  fi
  for m in 10 9 8 99; do
    url="$(rc_rhui_major_url "${tmpl}" "${m}" | sed "s/REGION/${region}/")"
    rc_crossmajor_probe_one "${out}" "${cert}" "${key}" "major=${m}" "${url}" "${caarg[@]}" "${hdr[@]}"
  done
  for m in 7 6; do
    url="https://rhui.${region}.aws.ce.redhat.com/pulp/mirror/content/dist/rhel/rhui/server/${m}/${m}Server/x86_64/os"
    rc_crossmajor_probe_one "${out}" "${cert}" "${key}" "major=${m}(legacy)" "${url}" "${caarg[@]}" "${hdr[@]}"
  done
  : "${m_list:=}"  # silence unused-in-some-paths; documents intent
}

# rc_collect_eus OUTDIR MAJOR - enumerate + inspect EUS/ELS/AUS/E4S repos. The
# extended-lifecycle content is the other axis of the config-driven hypothesis
# (and the only cross-version data for RHEL 6, which has no leapp).
rc_collect_eus() {
  local out="$1/eus" major="$2" pm rl_all
  pm="$(rc_pm_for_major "${major}")" || pm=dnf
  mkdir -p "${out}"
  rl_all="$(rc_repolist_cmd "${major}" all)" || rl_all='dnf -q repolist --all'
  # The eus/els/aus/e4s repo IDs present in the full repolist.
  rc_run "${out}" e01-eus-repo-ids \
    "${rl_all} 2>&1 | grep -iE 'eus|els|aus|e4s' || echo '(no extended-lifecycle repo ids found)'"
  if [ "${pm}" = dnf ]; then
    # shellcheck disable=SC2016  # $(...)/$i/\$1 expand inside rc_run's bash -c, not here
    rc_run "${out}" e02-eus-repoinfo \
      'for i in $(dnf -q repolist --all 2>/dev/null | awk "NR>1{print \$1}" | grep -iE "eus|els|aus|e4s"); do echo "== $i =="; dnf -q repoinfo "$i" 2>&1; done'
    rc_run "${out}" e03-eus-config \
      'dnf config-manager --dump 2>&1 | grep -iE "eus|els|aus|e4s" || echo "(none)"'
  else
    rc_run "${out}" e02-eus-repoinfo \
      "grep -iE 'eus|els|aus|e4s' /etc/yum.repos.d/*.repo 2>&1 || echo '(none in repo files)'"
  fi
}

# rc_collect_leapp OUTDIR MAJOR - NON-DESTRUCTIVE cross-major straddle capture.
# Installs leapp-rhui-aws (+ deps, which materialize the N+1 major's repos) and
# runs `leapp preupgrade --no-rhsm`. NEVER runs `leapp upgrade`. Majors 7/8/9.
rc_collect_leapp() {
  local out="$1/leapp" major="$2" target
  target="$(rc_leapp_target "${major}")" || {
    mkdir -p "${out}"; echo "skipped: no leapp target for RHEL ${major}" > "${out}/SKIPPED.txt"; return 0
  }
  mkdir -p "${out}"
  printf 'source_major=%s target_major=%s\n' "${major}" "${target}" > "${out}/target.txt"

  # dnf vars BEFORE (releasever pinning is central to the straddle question).
  rc_run "${out}" l01-vars-before 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'

  # Enable the RHUI client-config repo + install the leapp engine. The engine
  # package leapp-upgrade-el<N>toel<N+1> pulls leapp itself AND leapp-rhui-aws
  # (r73 installed only leapp-rhui-aws, so `leapp` was absent -> preupgrade rc127).
  if [ "${major}" = 7 ]; then
    rc_run "${out}" l02-enable-rhui 'yum-config-manager --enable rhui-client-config-server-7 rhel-7-server-rhui-extras-rpms 2>&1'
    rc_run "${out}" l03-install-leapp "yum -y install leapp-upgrade-el7toel${target} 2>&1"
  else
    rc_run "${out}" l02-enable-rhui "dnf config-manager --set-enabled rhui-client-config-server-${major} 2>&1"
    rc_run "${out}" l03-install-leapp "dnf -y install leapp-upgrade-el${major}toel${target} 2>&1"
  fi

  # The dry run. --no-rhsm because RHUI (not subscription-manager) is the source.
  # This is where leapp pulls the TARGET major's repos - the straddle we want.
  rc_run "${out}" l04-preupgrade 'leapp preupgrade --no-rhsm 2>&1'

  # dnf vars AFTER + the repo/cert state leapp materialized for the target.
  rc_run "${out}" l05-vars-after 'ls -laR /etc/dnf/vars/ /etc/yum/vars/ 2>&1; grep -rH . /etc/dnf/vars/ /etc/yum/vars/ 2>/dev/null'
  rc_run "${out}" l06-repos-after 'ls -la /etc/yum.repos.d/ 2>&1; sha256sum /etc/yum.repos.d/*.repo 2>&1'
  mkdir -p "${out}/yum.repos.d-after" "${out}/var-log-leapp"
  cp -p /etc/yum.repos.d/*.repo "${out}/yum.repos.d-after/" 2>/dev/null
  # leapp's own reports/logs (leapp-report.txt/.json, leapp-preupgrade.log).
  cp -rp /var/log/leapp/. "${out}/var-log-leapp/" 2>/dev/null
  # Any target-major RHUI cert leapp dropped in (leapp-rhui-aws ships them).
  rc_run "${out}" l07-leapp-rhui-files 'rpm -ql leapp-rhui-aws 2>&1; find /etc/pki/rhui /etc/leapp -type f 2>/dev/null'
}

# rc_run_long DIR NAME CMD... - like rc_run but with a long timeout, for heavy
# installs / --downloadonly fetches (leapp engine pulls, build-dep downloads).
rc_run_long() {
  local dir="$1" name="$2"; shift 2
  local cmd="$*"
  mkdir -p "${dir}"
  printf '%s\n' "${cmd}" > "${dir}/${name}.cmd"
  timeout "${RC_CHAIN_TIMEOUT:-900}" bash -c "${cmd}" > "${dir}/${name}.out" 2>&1
  printf '%s\n' "$?" > "${dir}/${name}.rc"
}

# rc_count_packages FILE - decompress a primary.xml.* metadata file and count
# <package entries. The "file list" built purely from curl + local tools.
rc_count_packages() {
  local f="$1"
  case "${f}" in
    *.gz)  gzip -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.xz)  xz -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.bz2) bzip2 -dc "${f}" 2>/dev/null | grep -c '<package ' ;;
    *.zck) if command -v unzck >/dev/null 2>&1; then unzck -c "${f}" 2>/dev/null | grep -c '<package '; else echo 'zck-unsupported'; fi ;;
    *)     grep -c '<package ' "${f}" 2>/dev/null ;;
  esac
}

# rc_curl_repo_enum DIR TAG CERT KEY MLURL EXTRA... - drive an RHUI repo with
# curl + the client cert ONLY (no dnf): follow mirrorlist -> repomd.xml ->
# primary metadata -> build the package file list. EXTRA... are extra curl args
# (--cacert, -H X-RHUI-ID, -H X-RHUI-SIGNATURE). Records status at each layer;
# the repomd_http field is the authorization verdict.
rc_curl_repo_enum() {
  local dir="$1" tag="$2" cert="$3" key="$4" mlurl="$5"; shift 5
  local sum="${dir}/${tag}-curl-enum.txt"
  local ml mlrc first repomd rmrc href prim prc pkgs
  mkdir -p "${dir}"
  ml="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "$@" -w '\n__HTTP__%{http_code}' "${mlurl}" 2>/dev/null)"
  mlrc="${ml##*__HTTP__}"
  first="$(printf '%s\n' "${ml}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
  {
    printf 'tag=%s\n' "${tag}"
    printf 'mirrorlist_url=%s\n' "${mlurl}"
    printf 'mirrorlist_http=%s\n' "${mlrc:-000}"
    printf 'first_mirror=%s\n' "${first:-none}"
  } > "${sum}"
  [ -n "${first}" ] || { printf 'result=no-mirror\n' >> "${sum}"; return 0; }
  repomd="${dir}/${tag}-repomd.xml"
  rmrc="$(curl -sS -m 30 --cert "${cert}" --key "${key}" "$@" -o "${repomd}" -w '%{http_code}' "${first%/}/repodata/repomd.xml" 2>/dev/null)"
  printf 'repomd_http=%s\n' "${rmrc}" >> "${sum}"
  [ "${rmrc}" = 200 ] || { printf 'result=repomd-denied(%s)\n' "${rmrc}" >> "${sum}"; return 0; }
  href="$(grep -oE 'href="[^"]*primary[^"]*"' "${repomd}" 2>/dev/null | head -1 | sed 's/^href="//; s/"$//')"
  printf 'primary_href=%s\n' "${href:-none}" >> "${sum}"
  [ -n "${href}" ] || { printf 'result=no-primary-href\n' >> "${sum}"; return 0; }
  prim="${dir}/${tag}-$(basename "${href}")"
  prc="$(curl -sS -m 60 --cert "${cert}" --key "${key}" "$@" -o "${prim}" -w '%{http_code}' "${first%/}/${href}" 2>/dev/null)"
  printf 'primary_http=%s\n' "${prc}" >> "${sum}"
  [ "${prc}" = 200 ] || { printf 'result=primary-denied(%s)\n' "${prc}" >> "${sum}"; return 0; }
  pkgs="$(rc_count_packages "${prim}")"
  printf 'package_count=%s\n' "${pkgs:-unknown}" >> "${sum}"
  printf 'result=OK-curl-only-file-list-built\n' >> "${sum}"
}

# rc_decompress FILE - stream a repodata file to stdout, format-agnostic.
rc_decompress() {
  case "$1" in
    *.gz)  gzip -dc "$1" 2>/dev/null ;;
    *.xz)  xz -dc "$1" 2>/dev/null ;;
    *.bz2) bzip2 -dc "$1" 2>/dev/null ;;
    *.zst) zstd -dc "$1" 2>/dev/null ;;
    *)     cat "$1" 2>/dev/null ;;
  esac
}

# rc_curl_fetch_pkg DIR TAG PKG CERT KEY MLURL EXTRA... - fetch a single RPM by
# name from an RHUI repo with curl ONLY (no dnf: no modular/dep/install-state
# drama - dnf has failed three different ways cross-major, curl has not). Follows
# mirrorlist -> repomd.xml -> primary, finds the package's <location href>, and
# curls the RPM into DIR/rpms/. Prints the fetched rpm path on success (rc 0).
rc_curl_fetch_pkg() {
  local dir="$1" tag="$2" pkg="$3" cert="$4" key="$5" mlurl="$6"; shift 6
  local sum="${dir}/${tag}-fetch.txt" ml first repomd rmrc href prim loc rpmrc rpmpath
  mkdir -p "${dir}/rpms"
  ml="$(curl -sS -m 20 --cert "${cert}" --key "${key}" "$@" -w '\n__HTTP__%{http_code}' "${mlurl}" 2>/dev/null)"
  first="$(printf '%s\n' "${ml}" | grep -Eo 'https?://[^[:space:]]+' | grep -v '__HTTP__' | head -1)"
  { printf 'tag=%s pkg=%s\n' "${tag}" "${pkg}"; printf 'first_mirror=%s\n' "${first:-none}"; } > "${sum}"
  [ -n "${first}" ] || { printf 'result=no-mirror\n' >> "${sum}"; return 1; }
  repomd="${dir}/${tag}-repomd.xml"
  rmrc="$(curl -sS -m 30 --cert "${cert}" --key "${key}" "$@" -o "${repomd}" -w '%{http_code}' "${first%/}/repodata/repomd.xml" 2>/dev/null)"
  printf 'repomd_http=%s\n' "${rmrc}" >> "${sum}"
  [ "${rmrc}" = 200 ] || { printf 'result=repomd-denied(%s)\n' "${rmrc}" >> "${sum}"; return 1; }
  href="$(grep -oE 'href="[^"]*primary[^"]*"' "${repomd}" 2>/dev/null | head -1 | sed 's/^href="//; s/"$//')"
  [ -n "${href}" ] || { printf 'result=no-primary\n' >> "${sum}"; return 1; }
  prim="${dir}/${tag}-$(basename "${href}")"
  curl -sS -m 90 --cert "${cert}" --key "${key}" "$@" -o "${prim}" "${first%/}/${href}" 2>/dev/null
  # Boundary-safe location match: the name must start a path component
  # (`.../make-4...`), or `make` grabs automake/cmake/gcc-toolset-N-make and
  # `head -1` ships the wrong package (latent in r79; caught on real el8
  # metadata before it could fire). `-[0-9]` excludes kernel-devel-matched.
  loc="$(rc_decompress "${prim}" | grep -oE '<location href="([^"]*/)?'"${pkg}"'-[0-9][^"]*\.rpm"' | head -1 | sed 's/.*href="//; s/"$//')"
  printf 'location=%s\n' "${loc:-none}" >> "${sum}"
  [ -n "${loc}" ] || { printf 'result=pkg-not-in-primary\n' >> "${sum}"; return 1; }
  rpmpath="${dir}/rpms/$(basename "${loc}")"
  rpmrc="$(curl -sS -m 120 --cert "${cert}" --key "${key}" "$@" -o "${rpmpath}" -w '%{http_code}' "${first%/}/${loc}" 2>/dev/null)"
  printf 'rpm_http=%s\nrpm=%s\n' "${rpmrc}" "${rpmpath}" >> "${sum}"
  [ "${rpmrc}" = 200 ] || { printf 'result=rpm-denied(%s)\n' "${rpmrc}" >> "${sum}"; return 1; }
  printf 'result=OK\n' >> "${sum}"
  printf '%s\n' "${rpmpath}"
}

# rc_builddep_scan HD MAJOR PKG... - grep the already-curl-fetched primary
# metadata (baseos + appstream) for each build-dep package name and record where
# each was found. Pure read of local files - no network, no dnf.
rc_builddep_scan() {
  local hd="$1" t="$2"; shift 2
  local out="${hd}/builddep-scan.txt" p f n where
  : > "${out}"
  for p in "$@"; do
    where=""
    for f in "${hd}/curl-rhel${t}-baseos-"*primary* "${hd}/curl-rhel${t}-appstream-"*primary*; do
      [ -e "${f}" ] || continue
      # grep -c consumes the WHOLE stream. grep -q exits at the first match,
      # SIGPIPEs the decompressor (rc 141), and under pipefail the `if` sees
      # FALSE even though the match EXISTS. Only large real metadata (80MB+)
      # opens the SIGPIPE window - small fixtures never reproduce it, which is
      # how the -q form passed the sandbox and failed on every real host (r81).
      n="$(rc_decompress "${f}" | grep -cE "<name>${p}</name>" || true)"
      if [ "${n:-0}" -gt 0 ]; then
        where="${f##*/curl-rhel"${t}"-}"; where="${where%%-*}"
        break
      fi
    done
    printf '%s: %s\n' "${p}" "${where:-NOT-FOUND}" >> "${out}"
  done
}

# rc_rhui_config_url TEMPLATE MAJOR - retarget a client-config mirrorlist
# template to another major: /server/<n>/ -> /server/<MAJOR>/ ; $basearch fixed.
# (REGION substitution is the caller's job.) Grounded on the observed shape
# .../protected/rhui-client-config/rhel/server/<N>/$basearch/os.
rc_rhui_config_url() {
  printf '%s\n' "$1" | sed -E \
    -e "s#/server/[0-9]+/#/server/$2/#" \
    -e "s#\\\$basearch#x86_64#g"
}

# rc_fetch_pkg_from_prim DIR TAG PKG PRIM MIRROR CERT KEY EXTRA... - fetch one
# RPM using an ALREADY-DOWNLOADED primary + first mirror. A 115MB primary must
# be transferred ONCE per repo, not once per package (r80 re-downloaded it for
# every material - 4x waste). Prints the fetched rpm path on success.
rc_fetch_pkg_from_prim() {
  local dir="$1" tag="$2" pkg="$3" prim="$4" mirror="$5" cert="$6" key="$7"; shift 7
  local sum="${dir}/${tag}-fetch.txt" loc rpmrc rpmpath
  mkdir -p "${dir}/rpms"
  { printf 'tag=%s pkg=%s\n' "${tag}" "${pkg}"
    printf 'prim=%s\nmirror=%s\n' "${prim}" "${mirror}"; } > "${sum}"
  # Boundary-safe: name must start a path component (see rc_curl_fetch_pkg).
  # Any one version proves obtainability; head -1 is deliberate.
  loc="$({ rc_decompress "${prim}" || true; } \
    | grep -oE '<location href="([^"]*/)?'"${pkg}"'-[0-9][^"]*\.rpm"' \
    | head -1 | sed 's/.*href="//; s/"$//')"
  printf 'location=%s\n' "${loc:-none}" >> "${sum}"
  [ -n "${loc}" ] || { printf 'result=pkg-not-in-primary\n' >> "${sum}"; return 1; }
  rpmpath="${dir}/rpms/$(basename "${loc}")"
  rpmrc="$(curl -sS -m 120 --cert "${cert}" --key "${key}" "$@" -o "${rpmpath}" -w '%{http_code}' "${mirror%/}/${loc}" 2>/dev/null)"
  printf 'rpm_http=%s\nrpm=%s\n' "${rpmrc}" "${rpmpath}" >> "${sum}"
  [ "${rpmrc}" = 200 ] || { printf 'result=rpm-denied(%s)\n' "${rpmrc}" >> "${sum}"; return 1; }
  printf 'result=OK\n' >> "${sum}"
  printf '%s\n' "${rpmpath}"
}

# rc_slim_primary HD PKGREGEX GLOB... - the raw primary blobs are the size bomb
# (81-115MB gz each; 294MB of the 307MB el8 r80 archive). After the scan and
# the material fetches they have served their purpose: replace each blob with
# (a) its sha256, (b) the sorted unique package NAME list, (c) the <package>
# XML slices of the packages of interest (location/NVR evidence survives, the
# bulk does not). RC_KEEP_METADATA=1 keeps the blobs (--keep-metadata).
rc_slim_primary() {
  local hd="$1" wl="$2"; shift 2
  local f base
  for f in "$@"; do
    [ -e "${f}" ] || continue
    base="${f%%.xml*}"
    sha256sum "${f}" > "${base}-primary.sha256" 2>/dev/null
    { rc_decompress "${f}" || true; } \
      | grep -oE '<name>[^<]+</name>' | sed 's/<name>//; s#</name>##' \
      | sort -u | gzip > "${base}-names.txt.gz"
    # One POSIX-awk pass: keep the full <package>..</package> element of every
    # package on the interest list (fixed names, no regex metacharacters).
    # Real createrepo output packs '</package><package type=...>' on ONE line;
    # split those first or the next package's reset swallows the flush (found
    # on the real el8 appstream primary, not on hand-written fixtures).
    { rc_decompress "${f}" || true; } | sed 's#><package #>\
<package #g' | awk -v wl="${wl}" '
      index($0, "<package ") { inp=1; buf=""; hit=0 }
      inp {
        buf = buf $0 "\n"
        if ($0 ~ ("<name>(" wl ")</name>")) hit=1
      }
      index($0, "</package>") { if (inp && hit) printf "%s", buf; inp=0 }
    ' > "${base}-slices.xml"
    [ "${RC_KEEP_METADATA:-0}" = 1 ] || rm -f "${f}"
  done
}

# rc_fetch_build_materials HD T CERT KEY EXTRA... - prove OBTAINABILITY, not
# just reachability: for every build-dep the scan located, download the actual
# RPM (reusing the repo primary + first mirror already on disk), record HTTP
# status + sha256 + rpm -qip, then delete the blob (RC_KEEP_RPMS=1 keeps it).
# repomd-200 and RPM-body-200 are separate authorization layers; only the
# download closes the gap between "listed in primary" and "the suite could
# really build from here". Prints 'ok=X total=Y' for the caller's SUMMARY line.
rc_fetch_build_materials() {
  local hd="$1" t="$2" cert="$3" key="$4"; shift 4
  local out="${hd}/build-materials.txt" scan="${hd}/builddep-scan.txt"
  local line p where prim mirror rpmf sum nvr ok=0 total=0
  : > "${out}"
  if [ ! -f "${scan}" ]; then
    printf 'skipped: builddep-scan.txt absent\n' >> "${out}"
    printf 'ok=0 total=0'; return 0
  fi
  while IFS= read -r line; do
    p="${line%%:*}"; where="$(printf '%s' "${line#*: }" | tr -d '[:space:]')"
    total=$((total + 1))
    case "${where}" in
      baseos|appstream) ;;
      *) printf '%s: SKIP (scan=%s)\n' "${p}" "${where}" >> "${out}"; continue ;;
    esac
    prim="$(find "${hd}" -maxdepth 1 -name "curl-rhel${t}-${where}-*primary*" 2>/dev/null | head -1)"
    mirror="$(sed -n 's/^first_mirror=//p' "${hd}/curl-rhel${t}-${where}-curl-enum.txt" 2>/dev/null | head -1)"
    if [ -z "${prim}" ] || [ -z "${mirror}" ] || [ "${mirror}" = none ]; then
      printf '%s: FETCH-FAILED (no local primary/mirror for %s)\n' "${p}" "${where}" >> "${out}"
      continue
    fi
    rpmf="$(rc_fetch_pkg_from_prim "${hd}/materials" "mat-rhel${t}-${p}" "${p}" \
             "${prim}" "${mirror}" "${cert}" "${key}" "$@")" || true
    if [ -z "${rpmf}" ] || [ ! -f "${rpmf}" ]; then
      printf '%s: FETCH-FAILED (repo=%s; see materials/mat-rhel%s-%s-fetch.txt)\n' \
        "${p}" "${where}" "${t}" "${p}" >> "${out}"
      continue
    fi
    sum="$(sha256sum "${rpmf}" 2>/dev/null)"; sum="${sum%% *}"
    nvr="$(rpm -qp "${rpmf}" 2>/dev/null)" || true
    rpm -qip "${rpmf}" > "${hd}/materials/mat-rhel${t}-${p}-qip.txt" 2>&1
    printf '%s: OK repo=%s nvr=%s sha256=%s\n' \
      "${p}" "${where}" "${nvr:-unreadable}" "${sum:-none}" >> "${out}"
    ok=$((ok + 1))
    [ "${RC_KEEP_RPMS:-0}" = 1 ] || rm -f "${rpmf}"
  done < "${scan}"
  printf 'summary: ok=%s total=%s keep_rpms=%s\n' "${ok}" "${total}" "${RC_KEEP_RPMS:-0}" >> "${out}"
  printf 'ok=%s total=%s' "${ok}" "${total}"
}

# rc_collect_chain OUTDIR MAJOR - CURL-NATIVE, DATA-GROUNDED forward chain (r79).
# Verifies how many majors a host of MAJOR N can reach: its own + every newer
# major (el8 -> 8,9,10 ; el9 -> 9,10 ; el10 -> 10). Derived entirely from the
# collected archives, NOT assumptions:
#   * content repos (baseos/appstream/...) are gated by content-rhel<M>.crt;
#     the client-config repo (.../protected/rhui-client-config/rhel/server/<M>/)
#     is gated by a SEPARATE rhui-client-config-server-<M>.crt.
#   * each leapp-rhui-aws (built for major M) bundles the NEXT major's certs -
#     BOTH content-rhel<M+1> AND rhui-client-config-server-<M+1> - so the chain
#     is non-circular: the config cert obtained at one hop unlocks the next
#     major's client-config repo, which hosts the next leapp-rhui-aws.
# Every step is curl + client cert only (+ IMDS identity header). Never dnf,
# never leapp. leapp-rhui-aws is not assumed to live in a specific repo: each
# hop SEARCHES client-config, then baseos, then appstream, and records where it
# was actually hosted.
rc_collect_chain() {
  local out="$1/chain" major="$2"
  local crepo=/etc/yum.repos.d/redhat-rhui.repo
  local cfgrepo=/etc/yum.repos.d/redhat-rhui-client-config.repo
  local csec c_tmpl ca c_cert_own c_key_own
  local cfgsec cfg_tmpl cfg_cert_own cfg_key_own
  local region caarg=() hdr=() id_doc id_sig
  local chain _chain=() src t hop=0 hd ohd verdict mats
  local cur_c_cert cur_c_key cur_cfg_cert cur_cfg_key
  local cand where rest u cc ck rpmfile certT keyT cfgT cfgkeyT cfg_url base_url app_url
  mkdir -p "${out}"
  chain="$(rc_chain_list "${major}")"

  [ -f "${crepo}" ] || { echo "skipped: ${crepo} absent" > "${out}/SKIPPED.txt"; return 0; }
  csec="$(awk '/^\[rhel-[0-9]+-baseos-rhui-rpms\]/{f=1;next} /^\[/{f=0} f' "${crepo}")"
  c_tmpl="$(printf '%s\n' "${csec}" | sed -n 's/^mirrorlist=//p' | head -1)"
  ca="$(printf '%s\n' "${csec}" | sed -n 's/^sslcacert=//p' | head -1)"
  c_cert_own="$(printf '%s\n' "${csec}" | sed -n 's/^sslclientcert=//p' | head -1)"
  c_key_own="$(printf '%s\n' "${csec}" | sed -n 's/^sslclientkey=//p' | head -1)"
  if [ -f "${cfgrepo}" ]; then
    cfgsec="$(awk '/^\[rhui-client-config-server-[0-9]+\]/{f=1;next} /^\[/{f=0} f' "${cfgrepo}")"
    cfg_tmpl="$(printf '%s\n' "${cfgsec}" | sed -n 's/^mirrorlist=//p' | head -1)"
    cfg_cert_own="$(printf '%s\n' "${cfgsec}" | sed -n 's/^sslclientcert=//p' | head -1)"
    cfg_key_own="$(printf '%s\n' "${cfgsec}" | sed -n 's/^sslclientkey=//p' | head -1)"
  fi
  region="$(rc_imds_get meta-data/placement/region)"
  {
    printf 'source_major=%s downstream_chain=%s mode=curl-native-datagrounded\n' "${major}" "${chain:-<none>}"
    printf 'own_content_cert=%s\nown_config_cert=%s\n' "${c_cert_own}" "${cfg_cert_own:-<none>}"
  } > "${out}/chain.txt"
  if [ -z "${c_tmpl}" ] || [ -z "${region}" ] || [ ! -f "${c_cert_own}" ]; then
    echo "skipped: content template / region / own content cert unavailable" >> "${out}/chain.txt"; return 0
  fi
  [ -n "${ca}" ] && [ -f "${ca}" ] && caarg=(--cacert "${ca}")
  id_doc="$(rc_imds_get dynamic/instance-identity/document)"
  id_sig="$(rc_imds_get dynamic/instance-identity/signature)"
  [ -n "${id_doc}" ] && [ -n "${id_sig}" ] && hdr=(
    -H "X-RHUI-ID: $(printf '%s' "${id_doc}" | rc_b64url)"
    -H "X-RHUI-SIGNATURE: $(printf '%s' "${id_sig}" | rc_b64url)")

  : > "${out}/SUMMARY.txt"

  # ---- measure the OWN major (baseline; expected 200) ----
  ohd="${out}/own-rhel${major}"; mkdir -p "${ohd}"
  base_url="$(rc_rhui_major_url "${c_tmpl}" "${major}" | sed "s/REGION/${region}/")"
  app_url="$(printf '%s' "${base_url}" | sed 's#/baseos/#/appstream/#')"
  rc_curl_repo_enum "${ohd}" "curl-rhel${major}-baseos" "${c_cert_own}" "${c_key_own}" "${base_url}" "${caarg[@]}" "${hdr[@]}"
  rc_curl_repo_enum "${ohd}" "curl-rhel${major}-appstream" "${c_cert_own}" "${c_key_own}" "${app_url}" "${caarg[@]}" "${hdr[@]}"
  rc_builddep_scan "${ohd}" "${major}" kernel-devel gcc make elfutils-libelf-devel
  mats="$(rc_fetch_build_materials "${ohd}" "${major}" \
           "${c_cert_own}" "${c_key_own}" "${caarg[@]}" "${hdr[@]}")"
  rc_slim_primary "${ohd}" "${RC_SLIM_WL}" \
    "${ohd}/curl-rhel${major}-baseos-"*primary* "${ohd}/curl-rhel${major}-appstream-"*primary*
  verdict="$(sed -n 's/^repomd_http=//p' "${ohd}/curl-rhel${major}-baseos-curl-enum.txt" 2>/dev/null | head -1)"
  printf 'target=%s (own) curl_baseos_repomd_http=%s build_materials=%s\n' \
    "${major}" "${verdict:-none}" "${mats}" > "${ohd}/RESULT.txt"
  printf 'rhel%s: repomd=%s build-materials %s (own major, own content cert)\n' \
    "${major}" "${verdict:-none}" "${mats}" >> "${out}/SUMMARY.txt"

  if [ -z "${chain}" ]; then
    printf 'reachable_majors=1 (rhel%s only; top of the line, no downstream)\n' "${major}" >> "${out}/SUMMARY.txt"
    return 0
  fi

  # ---- downstream forward chain ----
  cur_c_cert="${c_cert_own}"; cur_c_key="${c_key_own}"
  cur_cfg_cert="${cfg_cert_own}"; cur_cfg_key="${cfg_key_own}"
  src="${major}"
  read -ra _chain <<< "${chain}"
  for t in "${_chain[@]}"; do
    hop=$((hop + 1))
    hd="${out}/hop${hop}-src${src}-to${t}"; mkdir -p "${hd}"
    printf 'hop=%s source_major=%s target_major=%s\n' "${hop}" "${src}" "${t}" > "${hd}/hop.txt"

    # ACQUIRE major-<t> certs: SEARCH major-<src> repos for leapp-rhui-aws (built
    # for src; it bundles content-rhel<t> + config-server-<t>). Try client-config
    # (config cert), then baseos, then appstream (content cert). Record where.
    cfg_url=""
    [ -n "${cfg_tmpl}" ] && cfg_url="$(rc_rhui_config_url "${cfg_tmpl}" "${src}" | sed "s/REGION/${region}/")"
    base_url="$(rc_rhui_major_url "${c_tmpl}" "${src}" | sed "s/REGION/${region}/")"
    app_url="$(printf '%s' "${base_url}" | sed 's#/baseos/#/appstream/#')"
    rpmfile=""
    for cand in "clientconfig|${cfg_url}|${cur_cfg_cert}|${cur_cfg_key}" \
                "baseos|${base_url}|${cur_c_cert}|${cur_c_key}" \
                "appstream|${app_url}|${cur_c_cert}|${cur_c_key}"; do
      where="${cand%%|*}"; rest="${cand#*|}"; u="${rest%%|*}"; rest="${rest#*|}"; cc="${rest%%|*}"; ck="${rest##*|}"
      { [ -n "${u}" ] && [ -n "${cc}" ] && [ -f "${cc}" ]; } || continue
      rpmfile="$(rc_curl_fetch_pkg "${hd}" "fetch-${where}-el${src}" "leapp-rhui-aws" "${cc}" "${ck}" "${u}" "${caarg[@]}" "${hdr[@]}")"
      if [ -n "${rpmfile}" ] && [ -f "${rpmfile}" ]; then
        printf 'leapp-rhui-aws hosted in: %s\n  url=%s\n' "${where}" "${u}" > "${hd}/acquired-from.txt"; break
      fi
    done
    if [ -n "${rpmfile}" ] && [ -f "${rpmfile}" ]; then
      rc_run "${hd}" a01-extract "cd '${hd}' && rpm2cpio '${rpmfile}' | cpio -idmu 2>&1"
    fi
    # Discover the bundled certs by SEARCHING the extracted payload, not by
    # trusting a hardcoded path: a packaging-layout change must surface as a
    # NOT-ACQUIRED fact, not as a silent miss at a stale path.
    rc_run "${hd}" a02-bundle-contents \
      "find '${hd}' -type f \\( -name '*.crt' -o -name '*.key' -o -name '*.repo' \\) | sort"
    certT="$(find "${hd}" -type f -name "content-rhel${t}.crt" 2>/dev/null | head -1)"
    keyT="$(find "${hd}" -type f -name "content-rhel${t}.key" 2>/dev/null | head -1)"
    cfgT="$(find "${hd}" -type f -name "rhui-client-config-server-${t}.crt" 2>/dev/null | head -1)"
    cfgkeyT="$(find "${hd}" -type f -name "rhui-client-config-server-${t}.key" 2>/dev/null | head -1)"
    {
      printf 'discovered content_cert=%s\ndiscovered content_key=%s\n' "${certT:-<none>}" "${keyT:-<none>}"
      printf 'discovered config_cert=%s\ndiscovered config_key=%s\n' "${cfgT:-<none>}" "${cfgkeyT:-<none>}"
    } >> "${hd}/hop.txt"
    if [ ! -f "${certT}" ] || [ ! -f "${keyT}" ]; then
      printf 'STOP: content-rhel%s not acquired via curl from any major-%s repo (chain caps here)\n' "${t}" "${src}" > "${hd}/RESULT.txt"
      printf 'rhel%s: NOT-ACQUIRED (content-rhel%s carrier unreachable from major-%s)\n' "${t}" "${t}" "${src}" >> "${out}/SUMMARY.txt"
      rc_slim_primary "${hd}" "${RC_SLIM_WL}" "${hd}/fetch-"*primary*
      break
    fi

    # MEASURE major-<t> content reachability from THIS billing-<major> host.
    base_url="$(rc_rhui_major_url "${c_tmpl}" "${t}" | sed "s/REGION/${region}/")"
    app_url="$(printf '%s' "${base_url}" | sed 's#/baseos/#/appstream/#')"
    rc_curl_repo_enum "${hd}" "curl-rhel${t}-baseos" "${certT}" "${keyT}" "${base_url}" "${caarg[@]}" "${hdr[@]}"
    rc_curl_repo_enum "${hd}" "curl-rhel${t}-appstream" "${certT}" "${keyT}" "${app_url}" "${caarg[@]}" "${hdr[@]}"
    rc_builddep_scan "${hd}" "${t}" kernel-devel gcc make elfutils-libelf-devel
    mats="$(rc_fetch_build_materials "${hd}" "${t}" \
             "${certT}" "${keyT}" "${caarg[@]}" "${hdr[@]}")"
    rc_slim_primary "${hd}" "${RC_SLIM_WL}" \
      "${hd}/curl-rhel${t}-baseos-"*primary* "${hd}/curl-rhel${t}-appstream-"*primary* \
      "${hd}/fetch-"*primary*
    verdict="$(sed -n 's/^repomd_http=//p' "${hd}/curl-rhel${t}-baseos-curl-enum.txt" 2>/dev/null | head -1)"
    printf 'target=%s curl_baseos_repomd_http=%s build_materials=%s content_cert=%s\n' \
      "${t}" "${verdict:-none}" "${mats}" "${certT}" > "${hd}/RESULT.txt"
    printf 'rhel%s: repomd=%s build-materials %s (content-rhel%s acquired from major-%s)\n' \
      "${t}" "${verdict:-none}" "${mats}" "${t}" "${src}" >> "${out}/SUMMARY.txt"
    if [ "${verdict}" != 200 ]; then
      printf 'STOP: rhel%s content NOT authorized from billing-%s host.\n' "${t}" "${major}" >> "${hd}/RESULT.txt"; break
    fi
    # advance: next hop sources from major-<t> with the certs just extracted.
    cur_c_cert="${certT}"; cur_c_key="${keyT}"
    [ -f "${cfgT}" ] && { cur_cfg_cert="${cfgT}"; cur_cfg_key="${cfgkeyT}"; }
    src="${t}"
  done
}

#------------------------------------------------------------------------------
# Orchestration + packaging.
#------------------------------------------------------------------------------
rc_write_manifest() {
  local out="$1" major="$2" host="$3" ts="$4"
  {
    printf 'tool: collect-aws-rhui-facts.sh v%s\n' "${RC_TOOL_VERSION}"
    printf 'cloud: %s\n' "${RC_CLOUD}"
    printf 'collected_at: %s\n' "${ts}"
    printf 'host: %s\n' "${host}"
    printf 'rhel_major: %s\n' "${major}"
    printf 'uname: %s\n' "$(uname -a 2>/dev/null)"
    printf '\n*** SECURITY: this archive contains PRIVATE KEYS (RHUI entitlement\n'
    printf '    credential). Treat as a secret - do NOT commit; transfer securely. ***\n\n'
    printf 'sections:\n'
    printf '  base/       OS, repos, RHUI-client RPM (-qi/-ql/--scripts/--triggers),\n'
    printf '              plugin owners (rpm -qf sweep), dnf vars, IMDS\n'
    printf '  pkgs/       download-only RPM-file analysis (rpm -q*p) + extracted payloads\n'
    printf '              of the RHUI/leapp packages - nothing installed\n'
    printf '  certs/      FULL /etc/pki/rhui incl. keys + openssl/rct decodes +\n'
    printf '              COVERAGE.txt (origin sha256 vs copies; .repo ssl* closure)\n'
    printf '  crossmajor/ host-cert HTTPS reachability of other majors (rhel99=control)\n'
    printf '  eus/        EUS/ELS/AUS/E4S repo enumeration\n'
    printf '  leapp/      OPT-IN non-destructive "leapp preupgrade --no-rhsm" straddle (7/8/9)\n'
    printf '  chain/      curl-native forward chain: own major + every newer major reachable\n'
    printf '              (el8->3, el9->2, el10->1) + per-major build-material RPM\n'
    printf '              acquisition proof; SUMMARY.txt has the verdicts (--chain).\n'
    printf '              primary blobs slimmed to sha256 + name list + slices\n'
    printf '              (--keep-metadata retains the raw blobs)\n'
  } > "${out}/MANIFEST.txt"
}

rc_usage() {
  cat <<'EOF'
Usage: sudo bash collect-aws-rhui-facts.sh [options]
  --major N        RHEL major (6-10); default: auto-detect from /etc/redhat-release
  --outdir DIR     working directory; default: a mktemp dir
  --leapp          OPT-IN: run the leapp preupgrade dry-run (majors 7/8/9;
                   installs the leapp engine packages - default is OFF because
                   pkgs/ already analyzes leapp-rhui-aws without installing)
  --no-leapp       explicit off (accepted for compatibility; off is the default)
  --chain          curl-native forward-chain probe: how many majors this host
                   can reach (its own + every newer one: el8->8,9,10 ; el9->9,10
                   ; el10->10), INCLUDING actual build-material RPM downloads
                   per reachable major (verified sha256 + rpm -qip, blobs then
                   deleted). curl + client cert only, no dnf. See chain/
                   SUMMARY.txt.
  --keep-rpms      keep the downloaded build-material RPM blobs in the archive
  --keep-metadata  keep the raw primary metadata blobs (default: replaced by
                   sha256 + package-name list + <package> slices of the
                   packages of interest; the blobs are 81-115MB gz each)
  --no-pkgs        skip the download-only RPM package analysis (pkgs/)
  --no-crossmajor  skip the cross-major HTTPS reachability probe
  --no-eus         skip EUS/ELS repo enumeration
  --keep-outdir    do not delete the working dir after packing
  -h, --help       this help
Output: ./aws-rhui-facts_<host>_rhel<major>_<ts>.tar.gz  (CONTAINS PRIVATE KEYS)
EOF
}

rc_main() {
  local major="" outdir="" do_leapp=0 do_cross=1 do_eus=1 do_chain=0 do_pkgs=1 keep=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --major)        major="$2"; shift 2 ;;
      --outdir)       outdir="$2"; shift 2 ;;
      --leapp)        do_leapp=1; shift ;;
      --no-leapp)     do_leapp=0; shift ;;
      --chain)        do_chain=1; shift ;;
      --keep-rpms)    RC_KEEP_RPMS=1; shift ;;
      --keep-metadata) RC_KEEP_METADATA=1; shift ;;
      --no-pkgs)      do_pkgs=0; shift ;;
      --no-crossmajor) do_cross=0; shift ;;
      --no-eus)       do_eus=0; shift ;;
      --keep-outdir)  keep=1; shift ;;
      -h|--help)      rc_usage; return 0 ;;
      *)              rc_log "unknown option: $1"; rc_usage; return 2 ;;
    esac
  done

  if [ "$(id -u)" != 0 ]; then
    rc_log "WARNING: not root - cert/key copy and leapp install will be incomplete"
  fi
  if [ -z "${major}" ]; then
    major="$(rc_detect_major)" || { rc_log "ERROR: cannot detect RHEL major; pass --major"; return 2; }
  fi
  case "${major}" in 6|7|8|9|10) ;; *) rc_log "ERROR: unsupported major '${major}'"; return 2 ;; esac

  local ts host
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
  [ -n "${outdir}" ] || outdir="$(mktemp -d "/tmp/aws-rhui-facts.XXXXXX")"
  mkdir -p "${outdir}"

  rc_log "collecting: major=${major} host=${host} outdir=${outdir}"
  rc_imds_token
  rc_write_manifest "${outdir}" "${major}" "${host}" "${ts}"
  { rc_collect_base "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_pkgs}" = 1 ]  && { rc_collect_pkgs "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  { rc_collect_certs "${outdir}"; } 2>> "${outdir}/collect.log"
  [ "${do_cross}" = 1 ] && { rc_collect_crossmajor "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_eus}" = 1 ]   && { rc_collect_eus "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_leapp}" = 1 ] && { rc_collect_leapp "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"
  [ "${do_chain}" = 1 ] && { rc_collect_chain "${outdir}" "${major}"; } 2>> "${outdir}/collect.log"

  local archive
  archive="./aws-rhui-facts_${host}_rhel${major}_${ts}.tar.gz"
  tar -czf "${archive}" -C "$(dirname "${outdir}")" "$(basename "${outdir}")" 2>>"${outdir}/collect.log" \
    || { rc_log "ERROR: tar failed"; return 1; }
  [ "${keep}" = 1 ] || rm -rf "${outdir}"
  rc_log "done: ${archive}"
  printf '%s\n' "${archive}"
}

# t025 sources this file with RHUI_COLLECT_SOURCED=1 to unit-test the pure layer.
if [ "${RHUI_COLLECT_SOURCED:-0}" != 1 ]; then
  rc_main "$@"
fi
