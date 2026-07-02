# shellcheck shell=bash
#==============================================================================
# lib/acquire-rootfs.sh - RHEL-family image acquisition + environment detection
#
# Sourceable library (no shebang, no top-level execution beyond sourcing the
# sibling pkgmgr lib and defining constants). Provides:
#   * pure helpers - image/tag/ref maps, amd64 digest selection, init-mode
#     invocation args, entitlement classification (the L1-unit surface);
#   * I/O wrappers - podman pull and the curl-only anonymous OCI v2 fallback,
#     the 3-step entitlement detector, secrets presence (all mockable).
#
# Acquisition is podman-preferred with a curl-only OCI v2 anonymous pull as the
# fallback (manifest GET returns HTTP 200 with NO token step; blobs 302 ->
# cdn01.quay.io -> 200). RHEL 7 ubi-init must be pulled by a fixed tag/digest
# (the floating :latest is rejected by the host signature policy, sec 3.5).
# INSECURE_TLS=1 adds curl -k for an in-sandbox TLS-intercepting egress.
#==============================================================================

__ACQ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ubi-pkgmgr.sh
. "${__ACQ_DIR}/ubi-pkgmgr.sh"

ACQ_REGISTRY="registry.access.redhat.com"
ACQ_SECRETS_DIR="/run/secrets/etc-pki-entitlement"

# --- pure helpers (L1 unit surface) ------------------------------------------

# acq_image_for_major MAJOR - the registry repo path for the baseline image.
# RHEL 7/8/9/10 use ubiN/ubi-init; RHEL 6 uses the legacy non-UBI rhel6/rhel.
acq_image_for_major() {
  case "$1" in
    10) printf 'ubi10/ubi-init\n' ;;
    9)  printf 'ubi9/ubi-init\n' ;;
    8)  printf 'ubi8/ubi-init\n' ;;
    7)  printf 'ubi7/ubi-init\n' ;;
    6)  printf 'rhel6/rhel\n' ;;
    *)  return 1 ;;
  esac
}

# acq_tag_for_major MAJOR - the default tag. RHEL 7 pins the fixed 7.9-88 (the
# floating :latest fails the host signature policy, sec 3.5); others use latest.
acq_tag_for_major() {
  case "$1" in
    7)        printf '7.9-88\n' ;;
    6|8|9|10) printf 'latest\n' ;;
    *)        return 1 ;;
  esac
}

# acq_ref_for_major MAJOR [DIGEST] - the full pull reference. With a DIGEST, pin
# by @digest (reproducible, supported for every major); otherwise registry/image:tag.
acq_ref_for_major() {
  local major="$1" digest="${2:-}" image tag
  image="$(acq_image_for_major "${major}")" || return 1
  if [ -n "${digest}" ]; then
    printf '%s/%s@%s\n' "${ACQ_REGISTRY}" "${image}" "${digest}"
    return 0
  fi
  tag="$(acq_tag_for_major "${major}")" || return 1
  printf '%s/%s:%s\n' "${ACQ_REGISTRY}" "${image}" "${tag}"
}

# acq_init_run_args INIT_MODE REF [CMD...] - print the podman run argument vector
# (space-joined) for the init mode. 'none' runs an explicit command (systemd not
# PID 1; install/binary tests); 'systemd' boots the image detached (its Cmd is
# /sbin/init) for service/unit tests, followed by a separate podman exec.
acq_init_run_args() {
  local mode="$1" ref="$2"
  shift 2 || return 1
  case "${mode}" in
    none)
      if [ "$#" -gt 0 ]; then
        printf 'run --rm %s %s\n' "${ref}" "$*"
      else
        printf 'run --rm %s /bin/bash -lc true\n' "${ref}"
      fi
      ;;
    systemd)
      printf 'run -d %s\n' "${ref}" ;;
    *)
      return 1 ;;
  esac
}

# acq_select_amd64_digest JSON - print the linux/amd64 manifest digest from an
# OCI image-index / manifest-list JSON (pure). Splits the manifests array onto
# one object per line, then returns the digest of the amd64 entry. No jq/python
# dependency, so it works inside a minimal UBI on the curl-only path.
acq_select_amd64_digest() {
  printf '%s' "$1" \
    | tr -d '\n\r\t' \
    | sed 's/}, *{/}\n{/g' \
    | awk '
        /"architecture" *: *"amd64"/ {
          if (match($0, /"digest" *: *"[^"]+"/)) {
            s = substr($0, RSTART, RLENGTH)
            sub(/.*"digest" *: *"/, "", s)
            sub(/".*/, "", s)
            print s
            exit
          }
        }'
}

# acq_classify_entitlement REPO_OUTPUT KDEVEL_RC - decide anonymous|entitled from
# the POST-TRIGGER enabled-repo listing and whether kernel-devel resolved (rc 0).
# 'entitled' iff a rhel-* repo is present AND kernel-devel resolved. Matching is
# by the rhel-<digit> prefix, never by a per-major hard-coded repo ID (the IDs
# differ by generation: rhel-7-server-rpms vs rhel-9-for-x86_64-appstream-rpms).
acq_classify_entitlement() {
  local repos="$1" kdevel_rc="$2"
  if grep -Eq 'rhel-[0-9]' <<<"${repos}" && [ "${kdevel_rc}" -eq 0 ]; then
    printf 'entitled\n'
  else
    printf 'anonymous\n'
  fi
}

# --- I/O wrappers (mockable) -------------------------------------------------

# acq_curl [CURL_ARGS...] - curl wrapper that adds -k under INSECURE_TLS=1.
acq_curl() {
  local insecure=()
  [ "${INSECURE_TLS:-0}" = "1" ] && insecure=(-k)
  curl -fsSL "${insecure[@]}" "$@"
}

# acq_pull_podman REF - pull REF with podman (preferred engine).
acq_pull_podman() {
  podman pull "$1"
}

# acq_manifest_url MAJOR REF_TAG_OR_DIGEST - the OCI v2 manifests endpoint (pure).
acq_manifest_url() {
  local image="$1" ref="$2"
  printf 'https://%s/v2/%s/manifests/%s\n' "${ACQ_REGISTRY}" "${image}" "${ref}"
}

# acq_blob_url IMAGE DIGEST - the OCI v2 blobs endpoint (pure).
acq_blob_url() {
  printf 'https://%s/v2/%s/blobs/%s\n' "${ACQ_REGISTRY}" "$1" "$2"
}

# acq_secrets_present [DIR] - rc 0 iff >=1 entitlement .pem is present under DIR.
# The suite never reads pem contents; presence is step 1 of detection.
acq_secrets_present() {
  local dir="${1:-${ACQ_SECRETS_DIR}}" f
  for f in "${dir}"/*.pem; do
    [ -e "${f}" ] && return 0
  done
  return 1
}

# acq_trigger_redhat_repo MGR - run one makecache so the subscription-manager
# plugin generates redhat.repo (step 2). Best-effort: failures are non-fatal
# (an anonymous host simply produces no rhel-* repos at step 3).
acq_trigger_redhat_repo() {
  case "$1" in
    dnf)      dnf -y makecache >/dev/null 2>&1 || true ;;
    microdnf) microdnf -y makecache >/dev/null 2>&1 || true ;;
    yum)      yum -y makecache >/dev/null 2>&1 || true ;;
    *)        return 1 ;;
  esac
}

# acq_detect_entitlement MGR [SECRETS_DIR] - echo anonymous|entitled via the
# 3-step probe (secrets present -> trigger redhat.repo -> classify by rhel-*
# prefix + kernel-devel resolution). All external commands are mockable, so the
# whole flow is exercised hermetically in tests/t005_entitlementdetect.sh.
acq_detect_entitlement() {
  local mgr="$1" secrets_dir="${2:-${ACQ_SECRETS_DIR}}" repos kdevel_rc
  if ! acq_secrets_present "${secrets_dir}"; then
    printf 'anonymous\n'
    return 0
  fi
  acq_trigger_redhat_repo "${mgr}"
  repos="$(pkgmgr_enabled_repos "${mgr}" 2>/dev/null || true)"
  if pkgmgr_is_available "${mgr}" kernel-devel; then kdevel_rc=0; else kdevel_rc=1; fi
  acq_classify_entitlement "${repos}" "${kdevel_rc}"
}

# acq_pull_curl MAJOR DEST [DIGEST] - the curl-only anonymous OCI v2 fallback:
# GET the manifest (no token step) -> select the amd64 platform manifest ->
# fetch each layer blob and extract it into DEST. Mockable end-to-end (curl/tar).
# Returns 1 on any acquisition error.
acq_pull_curl() {
  local major="$1" dest="$2" digest="${3:-}" image ref idx amd64 plat layers section d
  image="$(acq_image_for_major "${major}")" || return 1
  if [ -n "${digest}" ]; then ref="${digest}"; else ref="$(acq_tag_for_major "${major}")" || return 1; fi
  mkdir -p "${dest}"

  # 1) manifest list / image index -> amd64 platform digest
  idx="$(acq_curl -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
            "$(acq_manifest_url "${image}" "${ref}")")" || return 1
  amd64="$(acq_select_amd64_digest "${idx}")"
  [ -n "${amd64}" ] || return 1

  # 2) platform manifest -> layer digests (the layers[] array only; the config
  #    blob digest precedes "layers" in an OCI image manifest and is not a layer)
  plat="$(acq_curl -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
             "$(acq_manifest_url "${image}" "${amd64}")")" || return 1
  section="$(printf '%s' "${plat}" | tr -d '\n\r\t' | sed 's/.*"layers"//')"
  layers="$(printf '%s' "${section}" | grep -Eo '"sha256:[^"]+"' | tr -d '"')"
  [ -n "${layers}" ] || return 1

  # 3) fetch + extract each layer blob in order
  while IFS= read -r d; do
    [ -n "${d}" ] || continue
    acq_curl "$(acq_blob_url "${image}" "${d}")" | tar -C "${dest}" -xz || return 1
  done <<<"${layers}"
}

# acq_preflight <install_script> : one-time sanity check before a --run sweep.
# Runs the ubi9 canary with the install script bind-mounted (:ro,z) and confirms a
# container can actually READ it - catching the two systemic failure modes that
# otherwise produce a whole sweep of misleading "install-fail" rows:
#   * SELinux: a bind-mount without relabeling is unreadable inside the container
#     (host RHEL/Fedora default to enforcing) - the mount now uses ':z'.
#   * image pull / egress / auth (rhel6 needs a subscription).
# Prints the real podman error + actionable hints on failure. Returns non-zero so
# the caller can abort with one clear message instead of N bad rows.
acq_preflight() {
  local script="$1" ref err out
  command -v podman >/dev/null 2>&1 || { log "PREFLIGHT: podman not found on PATH"; return 2; }
  ref="$(acq_ref_for_major 9 2>/dev/null || true)"   # ubi9 canary: public, no auth
  [ -n "${ref}" ] || return 0
  err="$(mktemp)"
  out="$(podman run --rm -v "${script}:/probe.sh:ro,z" "${ref}" \
           /bin/sh -c 'cat /probe.sh >/dev/null 2>&1 && echo READABLE' 2>"${err}" || true)"
  if [ "${out}" = "READABLE" ]; then rm -f "${err}"; return 0; fi
  log "PREFLIGHT FAILED: a container could not run/read the mounted install script."
  log "  canary image : ${ref}"
  log "  podman error : $(tail -3 "${err}" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-400)"
  log "  hints:"
  log "    1) SELinux  - bind-mounts now use ':z'; ensure podman is allowed to relabel"
  log "                  (getenforce; or run once with 'sudo setenforce 0' to confirm the cause)."
  log "    2) pull     - check egress to registry.access.redhat.com; 'podman pull ${ref}' by hand."
  log "    3) rhel6    - registry.access.redhat.com/rhel6/rhel needs a subscription (podman login)."
  rm -f "${err}"
  return 1
}

# ---- host environment banner (troubleshooting basics) -----------------------
# Emitted once per --run to: (1) the log, (2) the ledger 'host' meta, (3) one
# line in each RESULTS. Fields: OS, kernel+arch, SELinux (or 'absent' + AppArmor
# note on non-RHEL), container runtime (podman version, rootful/rootless, cgroup).
# No timestamp (by spec). host_json prints a compact JSON object; host_banner
# logs human-readable lines; record_host_meta folds it into the ledger.

host_selinux() {
  if command -v getenforce >/dev/null 2>&1; then getenforce 2>/dev/null; return 0; fi
  if [ -f /sys/fs/selinux/enforce ]; then
    case "$(cat /sys/fs/selinux/enforce 2>/dev/null)" in 1) printf 'Enforcing' ;; 0) printf 'Permissive' ;; *) printf 'unknown' ;; esac
    return 0
  fi
  # no SELinux on this host (e.g. Ubuntu/Debian): note AppArmor if present
  if [ -d /sys/kernel/security/apparmor ] || command -v aa-status >/dev/null 2>&1; then
    printf 'absent (AppArmor present)'
  else
    printf 'absent'
  fi
}

host_runtime() {
  local ver root cg
  ver="$(podman --version 2>/dev/null | head -1)"; [ -n "${ver}" ] || ver="podman: not found"
  if [ "$(id -u 2>/dev/null)" = "0" ]; then root="rootful"; else root="rootless"; fi
  if [ -f /sys/fs/cgroup/cgroup.controllers ]; then cg="cgroup v2"; else cg="cgroup v1"; fi
  printf '%s (%s, %s)' "${ver}" "${root}" "${cg}"
}

# host_json : one compact JSON object of host facts (no timestamp, by spec).
host_json() {
  local pretty id verid kern arch selinux runtime
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    pretty="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-}" )"
    id="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
    verid="$( . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-}" )"
  fi
  [ -n "${pretty}" ] || pretty="$(uname -s 2>/dev/null || printf 'unknown')"
  kern="$(uname -r 2>/dev/null || printf 'unknown')"
  arch="$(uname -m 2>/dev/null || printf 'unknown')"
  selinux="$(host_selinux)"
  runtime="$(host_runtime)"
  python3 - "${pretty}" "${id}" "${verid}" "${kern}" "${arch}" "${selinux}" "${runtime}" <<'PY' 2>/dev/null
import json,sys
p,i,v,k,a,s,r=sys.argv[1:8]
print(json.dumps({"os":p,"os_id":i,"os_version_id":v,"kernel":k,"arch":a,"selinux":s,"runtime":r}))
PY
}

# host_banner : log the host facts as a readable banner (uses the caller's log()).
host_banner() {
  local h; h="$(host_json)"
  log "host: $(printf '%s' "${h}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("%s | kernel %s %s | SELinux: %s | %s" % (d["os"], d["kernel"], d["arch"], d["selinux"], d["runtime"]))' 2>/dev/null || printf '%s' "${h}")"
}

# record_host_meta <ledger> : fold the host object into the ledger's top-level
# "host" key (created if the ledger exists). persist_ledger preserves it.
record_host_meta() {
  local led="$1" h; [ -f "${led}" ] || return 0
  h="$(host_json)"; [ -n "${h}" ] || return 0
  python3 - "${led}" "${h}" <<'PY' 2>/dev/null || true
import json,sys,os,tempfile
led,hj=sys.argv[1],sys.argv[2]
try: d=json.load(open(led))
except Exception: sys.exit(0)
try: d["host"]=json.loads(hj)
except Exception: sys.exit(0)
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(led) or ".")
with os.fdopen(fd,"w") as f: json.dump(d,f,indent=2); f.write("\n")
os.replace(tmp,led)
PY
}

# jesc <string> : JSON-escape a string for safe embedding inside a "..." value
# (no surrounding quotes). Used for the ledger 'reason' field.
jesc() {
  printf '%s' "${1:-}" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf '%s' "${1:-}"
}

# ---- host repo-access classification & entitlement passthrough --------------
# Single source of truth for "what repo access does this host have, and what must
# be bind-mounted to pass it into a container". Consumed by both the sweep
# matrices (actual -v/--network args) and probe-env.sh (reporting). RHSM and RHUI
# are treated as equal first-class sources; the RHUI mount set is DERIVED from the
# repo files (ssl*/gpgkey paths), so new/unknown RHUI providers work unchanged.

# acq_platform : physical | vm:<hv> | cloud:aws|azure|gcp|oci  (host-side).
acq_platform() {
  local v="" vendor="" asset=""
  command -v systemd-detect-virt >/dev/null 2>&1 && v="$(systemd-detect-virt 2>/dev/null || true)"
  [ -r /sys/class/dmi/id/sys_vendor ]        && vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  [ -r /sys/class/dmi/id/chassis_asset_tag ] && asset="$(cat /sys/class/dmi/id/chassis_asset_tag 2>/dev/null || true)"
  case "${asset}" in *OracleCloud.com*) printf 'cloud:oci'; return 0 ;; esac
  case "${vendor}" in
    *Amazon\ EC2*)          printf 'cloud:aws';   return 0 ;;
    Microsoft\ Corporation*) printf 'cloud:azure'; return 0 ;;
    Google*)                printf 'cloud:gcp';   return 0 ;;
  esac
  case "${asset}" in *7783-7084-3265-9085-8269-3286-77*) printf 'cloud:azure'; return 0 ;; esac
  case "${v}" in
    amazon)    printf 'cloud:aws' ;;
    microsoft) printf 'cloud:azure' ;;
    google)    printf 'cloud:gcp' ;;
    ""|none)   printf 'physical' ;;
    *)         printf 'vm:%s' "${v}" ;;
  esac
}

# acq_classify_repo_access HAS_RHSM RHUI_PROVIDER IS_OCI_OL : PURE classifier.
# HAS_RHSM=yes|no, RHUI_PROVIDER=aws|azure|gcp|other|"", IS_OCI_OL=yes|no.
# Priority: rhsm > rhui:<provider> > oci-ol > none.
acq_classify_repo_access() {
  local rhsm="$1" prov="$2" ociol="$3"
  [ "${rhsm}" = "yes" ] && { printf 'rhsm'; return 0; }
  [ -n "${prov}" ]      && { printf 'rhui:%s' "${prov}"; return 0; }
  [ "${ociol}" = "yes" ] && { printf 'oci-ol'; return 0; }
  printf 'none'
}

# acq_entitlement_feasible MODE : PURE. feasible|conditional|na.
acq_entitlement_feasible() {
  case "$1" in
    rhsm)    printf 'feasible' ;;
    rhui:*)  printf 'conditional' ;;
    *)       printf 'na' ;;
  esac
}

_acq_rhui_baseurls() {
  cat /etc/yum.repos.d/redhat-rhui*.repo /etc/yum.repos.d/rh-cloud.repo 2>/dev/null \
    | sed -n 's/^[[:space:]]*baseurl=//p'
}

# acq_repo_access : echo "MODE|CONFIDENCE|SIGNALS" (host-side, multi-signal).
# CONFIDENCE high|medium|low|na; SIGNALS is a comma list of matched cues.
acq_repo_access() {
  local rhsm=no ociol=no plat sig="" conf=na mode
  ls /etc/pki/entitlement/*.pem >/dev/null 2>&1 && { rhsm=yes; sig="rhsm-certs"; }
  plat="$(acq_platform)"
  local base; base="$(_acq_rhui_baseurls)"
  # per-provider signal scoring: rpm-client + baseurl-host + platform-dmi
  local best="" bestn=0 p n s
  for p in aws azure gcp; do
    n=0; s=""
    case "${p}" in
      aws)   command -v rpm >/dev/null 2>&1 && rpm -q rh-amazon-rhui-client >/dev/null 2>&1 && { n=$((n+1)); s="${s},rpm:rh-amazon-rhui-client"; }
             printf '%s' "${base}" | grep -q 'aws\.ce\.redhat\.com'   && { n=$((n+1)); s="${s},baseurl:aws.ce.redhat.com"; }
             [ "${plat}" = "cloud:aws" ]                              && { n=$((n+1)); s="${s},dmi:aws"; } ;;
      azure) command -v rpm >/dev/null 2>&1 && rpm -qa 'rhui-azure-rhel*' 2>/dev/null | grep -q . && { n=$((n+1)); s="${s},rpm:rhui-azure-rhel"; }
             printf '%s' "${base}" | grep -q 'microsoft\.com'         && { n=$((n+1)); s="${s},baseurl:microsoft.com"; }
             [ "${plat}" = "cloud:azure" ]                            && { n=$((n+1)); s="${s},dmi:azure"; } ;;
      gcp)   command -v rpm >/dev/null 2>&1 && { rpm -qa 'google-rhui-client*' 2>/dev/null | grep -q . || rpm -qa 'gce-google-rhui-client*' 2>/dev/null | grep -q .; } && { n=$((n+1)); s="${s},rpm:google-rhui-client"; }
             printf '%s' "${base}" | grep -qi 'googlecloud'           && { n=$((n+1)); s="${s},baseurl:googlecloud"; }
             [ "${plat}" = "cloud:gcp" ]                              && { n=$((n+1)); s="${s},dmi:gcp"; } ;;
    esac
    [ "${n}" -gt "${bestn}" ] && { bestn="${n}"; best="${p}"; sig="${sig}${s}"; }
  done
  local prov=""
  if [ "${rhsm}" = "no" ]; then
    if [ "${bestn}" -ge 1 ]; then
      prov="${best}"
      case "${bestn}" in 3) conf=high ;; 2) conf=medium ;; *) conf=low ;; esac
    elif ls /etc/pki/rhui/*.pem /etc/pki/rhui/product/*.crt >/dev/null 2>&1 \
         || cat /etc/yum.repos.d/*.repo 2>/dev/null | grep -q -- '-rhui-rpms'; then
      prov="other"; conf=low; sig="${sig},generic-rhui"
    fi
  fi
  # OCI Oracle-Linux regional yum (distinct; not RHEL RHUI)
  if [ "${rhsm}" = "no" ] && [ -z "${prov}" ]; then
    if [ -s /etc/yum/vars/ociregion ] || [ -s /etc/dnf/vars/ociregion ] \
       || printf '%s' "$(cat /etc/yum.repos.d/*.repo 2>/dev/null)" | grep -q 'oci\.oraclecloud\.com' \
       || { command -v rpm >/dev/null 2>&1 && rpm -qa 'oraclelinux-release*' 2>/dev/null | grep -q .; }; then
      ociol=yes; sig="${sig},oci-ol"
    fi
  fi
  [ "${rhsm}" = "yes" ] && conf=high
  mode="$(acq_classify_repo_access "${rhsm}" "${prov}" "${ociol}")"
  sig="${sig#,}"
  printf '%s|%s|%s' "${mode}" "${conf}" "${sig:-none}"
}

# acq_entitlement_mount_args [MODE] : echo the podman -v/--network args to pass the
# host's repo access into a container. DERIVES the RHUI mount set from the repo
# files' ssl*/gpgkey paths (provider-agnostic). Empty for oci-ol/none.
acq_entitlement_mount_args() {
  local mode="${1:-$(acq_repo_access | cut -d'|' -f1)}" f p paths
  case "${mode}" in
    rhsm)
      [ -d /etc/pki/entitlement ] && printf -- '-v /etc/pki/entitlement:/etc/pki/entitlement:ro '
      [ -d /etc/rhsm ]            && printf -- '-v /etc/rhsm:/etc/rhsm:ro '
      ;;
    rhui:*)
      for f in /etc/yum.repos.d/redhat-rhui*.repo /etc/yum.repos.d/rh-cloud.repo; do
        [ -f "${f}" ] && printf -- '-v %s:%s:ro ' "${f}" "${f}"
      done
      paths="$(cat /etc/yum.repos.d/redhat-rhui*.repo /etc/yum.repos.d/rh-cloud.repo 2>/dev/null \
                | sed -nE 's#^[[:space:]]*(sslclientcert|sslclientkey|sslcacert|gpgkey)=(file://)?(/[^[:space:]]+).*#\3#p' | sort -u)"
      # shellcheck disable=SC2086  # intentional word-split of newline/space-separated paths
      for p in ${paths}; do [ -e "${p}" ] && printf -- '-v %s:%s:ro ' "${p}" "${p}"; done
      [ -d /etc/pki/rhui ]                       && printf -- '-v /etc/pki/rhui:/etc/pki/rhui:ro '
      [ -f /etc/dnf/plugins/amazon-id.conf ]     && printf -- '-v /etc/dnf/plugins/amazon-id.conf:/etc/dnf/plugins/amazon-id.conf:ro '
      printf -- '--network host '
      ;;
    *) : ;;
  esac
}
