#!/usr/bin/env bash
#
# build-cleancore-ol6.sh
# ----------------------------------------------------------------------------
# Naming convention: build-cleancore-ol<MAJOR>.sh  (the OS version is the
# trailing token). Family: build-cleancore-ol6.sh / -ol7.sh / -ol8.sh /
# -ol9.sh / -ol10.sh
#
# Build a *clean-core* Oracle Linux 6 container rootfs. Dedicated, self-contained
# OL6 script (no shared library, no config externalization -- by design).
#
# OL6 is the YUM-family + NEEDS-VERIFICATION member: it is EOL, so its rpm stays
# 4.8 / BerkeleyDB-4 FOREVER. Only an EL6-native rpm can write an rpmdb that the
# in-guest EL6 rpm can read (an EL7 rpm 4.11 / db5 builder yields a db an EL6 rpm
# reads as 0 packages -- proven). Hence the builder MUST be an EL6 image. The
# package set is a slim-aligned, container-appropriate trim (@core dropped, a
# minimal userland plus test-base essentials, EPEL wired in but shipped disabled)
# that mirrors clean-core OL7's Include/Exclude translated to EL6 names; there is
# no upstream ol6-slim to diff against, so the set is curated (see INCLUDE below).
#
# Three execution environments are involved; each block below is tagged:
#   [A] HOST       - orchestrates only (download, extract, fetch RPMs, edit, pack, test).
#   [B] BUILDER    - a THROWAWAY EL6-native builder rootfs, driven via unshare+chroot.
#                    Acquired in preference order: (1) the Oracle "6-slim" container
#                    rootfs (OL6.10) pinned in oracle/container-images at the SAME
#                    commit OL7/OL8 use -- already ships the el6_10 NSS/openssl
#                    1.0.1e/curl stack, so it can TLS-handshake modern yum.oracle.com
#                    directly (no modernization); (2) FALLBACK the legacy OL6.6
#                    public-yum docker image (rpm 4.8 / db4), whose 2014-era NSS/curl
#                    CANNOT handshake modern yum.oracle.com, so that path is FIRST
#                    modernized -- host-fetched el6_10 TLS RPMs are rpm-installed by
#                    the builder's own rpm 4.8, then yum+rpm updated. Contents are
#                    NOT shipped either way.
#   [C] CLEAN-CORE - the DELIVERABLE rootfs from the yum --installroot transaction.
#
# ----------------------------------------------------------------------------
# PRIMARY SOURCES (verify upstream)
#   - Builder image (1) "6-slim" rootfs (OL6.10), Oracle official -- a plain
#     `FROM scratch + ADD rootfs.tar.xz` tarball, same channel/pin as OL7/OL8;
#     equivalent to ghcr.io/oracle/oraclelinux:6-slim (this rootfs IS its source):
#       https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/6-slim
#       https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/6-slim/oraclelinux-6-slim-amd64-rootfs.tar.xz
#   - Builder image (2) FALLBACK OL6.6 public-yum docker image (rpm 4.8 / db4):
#       https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz
#   - Package set = a slim-aligned curated trim (mirrors clean-core OL7 in EL6
#     names). See the INCLUDE/EXCLUDE below.
#   - Package repositories + el6_10 TLS RPMs (fallback path only), Oracle official:
#       https://yum.oracle.com/repo/OracleLinux/OL6/latest/x86_64/
#   - EPEL 6 release RPM (EOL; Oracle does not host EPEL 6), Fedora archive:
#       https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/epel-release-6-8.noarch.rpm
#   - Cleanup guidance (VM-oriented; container-applicable subset adopted), AWS:
#       https://docs.aws.amazon.com/imagebuilder/latest/userguide/security-best-practices.html
# ----------------------------------------------------------------------------
# Usage:   bash build-cleancore-ol6.sh [output.tar.gz]
#   env :  WORK=<scratch dir>   INSECURE_TLS=0  (drop sslverify=0 on a trusted host)
# Requires: root (unshare/chroot/mknod), curl, tar, xz, gzip, unshare, truncate, find.
# Exit:    0 = built and self-test passed; non-zero = build error or test failure.
# ----------------------------------------------------------------------------
set -euo pipefail

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — configuration (inline by design; not externalized)            ║
# ╚════════════════════════════════════════════════════════════════════════╝
OSMAJOR=6
# Builder image, in preference order (see the [B] notes above):
#   1) PRIMARY  - the Oracle "6-slim" container rootfs (OL6.10), pinned in
#      oracle/container-images at the SAME commit the OL7/OL8 builders use. A plain
#      rootfs tar.xz (`FROM scratch + ADD`), extracted directly like OL7/OL8. OL6.10
#      already ships the el6_10 NSS/openssl(1.0.1e)/curl stack, so it handshakes
#      modern yum.oracle.com with NO bootstrap modernization. Equivalent to
#      ghcr.io/oracle/oraclelinux:6-slim (same image; this rootfs is its source).
#      The raw-git channel matches OL7/OL8 and avoids the OCI token/manifest dance.
#   2) FALLBACK - the legacy OL6.6 public-yum docker image (rpm 4.8 / db4). Its
#      2014-era NSS/curl cannot handshake modern yum.oracle.com, so this path ALSO
#      runs the el6_10 TLS RPM modernization (host-fetched, rpm-installed).
# Builder image, in preference order (see the [B] notes above):
#   1) PRIMARY  - the Oracle container-registry "6-slim" image by its FLOATING tag
#      (always the latest 6.x = OL6.10 slim), pulled over the OCI registry v2 API
#      (curl-only, or a container runtime if present). Modern TLS; no modernization.
#   2) FALLBACK - the SAME 6-slim rootfs pinned in oracle/container-images at
#      CI_COMMIT (byte-stable git-raw tarball) if the registry is unreachable.
#   3) LAST     - the legacy OL6.6 public-yum docker image (rpm 4.8 / db4), whose
#      2014-era NSS/curl needs the el6_10 TLS RPM modernization.
OL_REGISTRY="${OL_REGISTRY:-https://container-registry.oracle.com}"
OL_IMAGE="${OL_IMAGE:-os/oraclelinux}"
OL_TAG="${OL_TAG:-6-slim}"                             # floating: latest 6.x slim
CI_COMMIT="0218ab4ba2f820b1b978dcc5a76435040397a472"
BUILDER_SLIM_URL="https://github.com/oracle/container-images/raw/${CI_COMMIT}/6-slim/oraclelinux-6-slim-amd64-rootfs.tar.xz"
BUILDER_PUBYUM_URL="https://public-yum.oracle.com/docker-images/OracleLinux/OL6/oraclelinux-6.6.tar.xz"

WORK="${WORK:-/tmp/cleancore-ol6}"
OUT_TARBALL="${1:-${WORK}/cleancore-ol6-rootfs.tar.gz}"

# Sandbox without a usable NSS trust store -> sslverify=0 for the BUILD only,
# written into the build-time cleancore.repo (dropped before delivery).
INSECURE_TLS="${INSECURE_TLS:-1}"
SSL=1; [ "${INSECURE_TLS}" = "1" ] && SSL=0
CURL_K=""; [ "${INSECURE_TLS}" = "1" ] && CURL_K="-k"   # host curl for the registry pull

# The NSS dynamic CA trust enable below (finalize step C) is a workaround for the
# Claude build sandbox, whose egress proxy presents an intercepting (MITM) cert:
# enabling the dynamic store lets the clean-core's NSS-backed curl/yum trust the
# proxy CA. On a real build host (physical / VM) there is no intercepting proxy,
# the clean-core verifies standard CAs with its shipped ca-certificates bundle,
# and EL6 'update-ca-trust' cannot run identically there -- so the step AND its
# self-test are SKIPPED off-sandbox. IS_SANDBOX is exported inside the sandbox;
# the egress-gateway CA on the build host is a secondary signal.
SANDBOX=0
[ -n "${IS_SANDBOX:-}" ] && SANDBOX=1
if [ "${SANDBOX}" = "0" ]; then
  for _ca in /usr/local/share/ca-certificates/egress-gateway-ca-*.crt; do
    [ -e "${_ca}" ] && { SANDBOX=1; break; }
  done
fi
# Explicit override of the auto-detection: CLEANCORE_CATRUST=on|off forces the
# workaround on/off (default 'auto'). 'off' is also how the real-host code path
# is exercised from within the sandbox.
case "${CLEANCORE_CATRUST:-auto}" in
  on)  SANDBOX=1 ;;
  off) SANDBOX=0 ;;
esac

REPO_BASE="https://yum.oracle.com/repo/OracleLinux/OL${OSMAJOR}/latest/x86_64"

# TLS stack to host-fetch (modern host TLS) and install with the builder's rpm
# 4.8 so the builder's NSS 3.16 -> 3.44 and modern https becomes possible.
TLS_PKGS=( nspr nss nss-util nss-softokn nss-softokn-freebl nss-sysinit
           nss-tools curl libcurl ca-certificates openssl )

# Package manifest = a slim-aligned, container-appropriate set: @core is dropped
# (no kernel/boot/init/firewall/cron/syslog/sshd -- a container is never PID 1),
# leaving a minimal userland plus explicit test-base essentials. This mirrors the
# clean-core OL7 Include translated to EL6 package names; every name is verified
# present in OL6/latest. EL6 name differences vs OL7: procps-ng -> procps;
# nmap-ncat -> nc; no git-core split -> plain git (pulls ~perl-*); the release is
# oraclelinux-release-el6. net-tools IS included (the one deliberate deviation
# from OL7's no-net-tools): EL6 has no standalone hostname package, so the
# hostname command ships in net-tools.
# yum-plugin-versionlock (default; in OL6/latest): package-pinning plugin so the
# base can hold/exclude packages -- parallels install-awscli.sh's versionlock v1-block.
INCLUDE=( yum oraclelinux-release oraclelinux-release-el6 yum-utils yum-plugin-versionlock
  curl wget git bzip2 unzip zip
  sudo which tar diffutils less findutils procps psmisc net-tools vim-minimal
  iproute iputils bind-utils traceroute nc tcpdump )

# Defensive excludes only. With @core dropped, the bulky members (kernel,
# firmware, firewall, cron, syslog, NetworkManager, sssd, rhn-*) are never
# candidates, so the old @core-removal list is unnecessary. The globs are a
# safety net against a dependency ever pulling a kernel or firmware blob into
# what must stay a kernel-less container rootfs.
EXCLUDE="*firmware*,kernel*"

# OL6 EPEL: Oracle does not host EPEL 6 (no oracle-epel-release-el6); EPEL 6 is
# EOL and lives only at the Fedora community archive (https only -- http 302-
# redirects there). In finalize the clean-core ENABLES its NSS dynamic CA trust
# (C), then fetches this release RPM with its OWN curl and installs it with its
# OWN rpm (B), and the repo is repointed to the archive + shipped DISABLED. yum is
# avoided for the fetch: EL6 yum's urlgrabber cannot fetch a direct https package
# URL. The ENA/SSM harnesses enable the repo on demand for e.g. dkms.
EPEL_RPM_URL="https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/epel-release-6-8.noarch.rpm"

BUILDER="${WORK}/builder"      # [B] throwaway EL6-native builder rootfs
OUT="/cleancore"               # [C] installroot path INSIDE the builder
DELIV="${BUILDER}${OUT}"       # [C] deliverable rootfs as seen from [A]

log() { printf '%s [cleancore-ol6] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }


# --- Tag-based builder image pull (OCI registry v2; curl-only + runtime fast-path) ---
# Pull oraclelinux:<tag> from the Oracle container registry into a rootfs dir. A
# floating tag (6-slim) is always the latest 6.x slim (OL6.10). Returns 0 on
# success, 1 to let the caller fall back. Self-contained (no shared lib) per the
# per-builder design; mirrors the OL5 builder. Needs host curl (+ python3 for the
# curl-only path); a missing tool or any failure simply returns 1 (-> fall back).
oci_pull_rootfs() {
  local _reg="$1" _repo="$2" _tag="$3" _dest="$4"
  local _rt="" _c _ref _cid _tok _amd _meta _dig
  for _c in podman docker; do
    if command -v "${_c}" >/dev/null 2>&1; then _rt="${_c}"; break; fi
  done
  if [ -n "${_rt}" ]; then
    _ref="${_reg#https://}/${_repo}:${_tag}"
    "${_rt}" pull "${_ref}" >/dev/null 2>&1 || return 1
    _cid="$("${_rt}" create "${_ref}" /bin/true 2>/dev/null)" || return 1
    if ! "${_rt}" export "${_cid}" 2>/dev/null | tar -C "${_dest}" -xf -; then
      "${_rt}" rm -f "${_cid}" >/dev/null 2>&1 || true; return 1
    fi
    "${_rt}" rm -f "${_cid}" >/dev/null 2>&1 || true
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || return 1
  _meta="$(mktemp -d)" || return 1
  _tok="$(curl -fsS ${CURL_K} --get "${_reg}/auth" \
            --data-urlencode "service=Oracle Registry" \
            --data-urlencode "scope=repository:${_repo}:pull" 2>/dev/null \
          | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])' 2>/dev/null)" || true
  if [ -z "${_tok}" ]; then rm -rf "${_meta}"; return 1; fi
  if ! curl -fsSL ${CURL_K} -H "Authorization: Bearer ${_tok}" \
      -H "Accept: application/vnd.oci.image.index.v1+json" \
      -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
      -H "Accept: application/vnd.oci.image.manifest.v1+json" \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "${_reg}/v2/${_repo}/manifests/${_tag}" -o "${_meta}/index.json" 2>/dev/null; then
    rm -rf "${_meta}"; return 1
  fi
  _amd="$(python3 -c '
import sys,json
d=json.load(open(sys.argv[1]))
if "manifests" in d:
    for m in d["manifests"]:
        p=m.get("platform",{})
        if p.get("architecture")=="amd64" and p.get("os")=="linux":
            print(m["digest"]); break
else:
    print("")' "${_meta}/index.json" 2>/dev/null)" || true
  if [ -n "${_amd}" ]; then
    if ! curl -fsSL ${CURL_K} -H "Authorization: Bearer ${_tok}" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "${_reg}/v2/${_repo}/manifests/${_amd}" -o "${_meta}/manifest.json" 2>/dev/null; then
      rm -rf "${_meta}"; return 1
    fi
  else
    cp -f "${_meta}/index.json" "${_meta}/manifest.json"
  fi
  if ! python3 -c '
import sys,json
d=json.load(open(sys.argv[1]))
for l in d.get("layers",[]): print(l["digest"])' "${_meta}/manifest.json" 2>/dev/null > "${_meta}/layers.txt"; then
    rm -rf "${_meta}"; return 1
  fi
  if [ ! -s "${_meta}/layers.txt" ]; then rm -rf "${_meta}"; return 1; fi
  while IFS= read -r _dig; do
    [ -n "${_dig}" ] || continue
    if ! curl -fsSL ${CURL_K} -H "Authorization: Bearer ${_tok}" \
        "${_reg}/v2/${_repo}/blobs/${_dig}" 2>/dev/null | tar -C "${_dest}" -xz; then
      rm -rf "${_meta}"; return 1
    fi
  done < "${_meta}/layers.txt"
  rm -rf "${_meta}"
  return 0
}

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — acquire the builder rootfs. PRIMARY: the floating 6-slim tag    ║
# ║     from the Oracle container registry (latest 6.x = OL6.10; OCI v2/curl).  ║
# ║     FALLBACK: the pinned 6-slim git-raw rootfs (byte-stable). LAST: the     ║
# ║     OL6.6 public-yum docker image (manifest.json + layer.tar; needs TLS     ║
# ║     modernization). Tag + pinned are both OL6.10 (modern TLS; no mod).       ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] acquiring the EL6 builder rootfs"
rm -rf "${WORK}"
mkdir -p "${BUILDER}"
BUILDER_KIND=""
if oci_pull_rootfs "${OL_REGISTRY}" "${OL_IMAGE}" "${OL_TAG}" "${BUILDER}"; then
  log "[A] using the floating ${OL_TAG} image from ${OL_REGISTRY#https://}/${OL_IMAGE} (latest 6.x = OL6.10)"
  BUILDER_KIND="tagslim610"
elif curl -fsSL --retry 2 -o "${WORK}/builder.tar.xz" "${BUILDER_SLIM_URL}" 2>/dev/null; then
  log "[A] registry pull unavailable; using the pinned 6-slim rootfs (OL6.10): ${BUILDER_SLIM_URL}"
  tar -C "${BUILDER}" -xJf "${WORK}/builder.tar.xz"
  rm -f "${WORK}/builder.tar.xz"
  BUILDER_KIND="slim610"
else
  log "[A] 6-slim rootfs unavailable; falling back to the OL6.6 public-yum docker image"
  curl -fsSL -o "${WORK}/builder.tar.xz" "${BUILDER_PUBYUM_URL}"
  STAGE="${WORK}/stage"
  mkdir -p "${STAGE}"
  tar -C "${STAGE}" -xJf "${WORK}/builder.tar.xz"
  rm -f "${WORK}/builder.tar.xz"
  log "[A] unpacking docker layer(s) into the builder rootfs"
  if [ -f "${STAGE}/manifest.json" ]; then
    # ordered layer list from the docker manifest
    grep -oE '"[^"]*layer\.tar"' "${STAGE}/manifest.json" | tr -d '"' | while read -r layer; do
      [ -n "${layer}" ] && tar -C "${BUILDER}" -xf "${STAGE}/${layer}"
    done
  else
    find "${STAGE}" -name 'layer.tar' -exec tar -C "${BUILDER}" -xf {} \;
  fi
  rm -rf "${STAGE}"
  BUILDER_KIND="pubyum66"
fi
[ -x "${BUILDER}/bin/rpm" ] || { log "[A] ERROR: builder has no /bin/rpm"; exit 1; }
cp -f /etc/resolv.conf "${BUILDER}/etc/resolv.conf" 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — (FALLBACK path only) fetch the el6_10 TLS RPMs (newest           ║
# ║     x86_64/noarch each), using the host's modern TLS, by parsing the OL6    ║
# ║     repo primary.xml. The 6-slim (OL6.10) builder already ships this stack. ║
# ╚════════════════════════════════════════════════════════════════════════╝
TLSDIR="${WORK}/tls"
if [ "${BUILDER_KIND}" = "pubyum66" ]; then
  log "[A] (fallback) fetching el6_10 TLS bootstrap RPMs from ${REPO_BASE}"
  mkdir -p "${TLSDIR}"
  curl -fsSL "${REPO_BASE}/repodata/repomd.xml" -o "${WORK}/repomd.xml"
  PRIMARY_REL="$(grep -oE 'repodata/[a-f0-9]+-primary\.xml\.gz' "${WORK}/repomd.xml" | head -1)"
  [ -n "${PRIMARY_REL}" ] || { log "[A] ERROR: primary.xml.gz not found in repomd"; exit 1; }
  curl -fsSL "${REPO_BASE}/${PRIMARY_REL}" -o "${WORK}/primary.xml.gz"
  gunzip -f "${WORK}/primary.xml.gz"   # -> ${WORK}/primary.xml
  for name in "${TLS_PKGS[@]}"; do
    # newest (version-sorted) x86_64/noarch href for exactly this package name
    href="$(grep -oE "getPackage/${name}-[0-9][^\"]*\.rpm" "${WORK}/primary.xml" \
              | grep -vE '\.i686\.rpm$' | sort -V | tail -1)"
    [ -n "${href}" ] || { log "[A] ERROR: no RPM found for TLS package '${name}'"; exit 1; }
    curl -fsSL "${REPO_BASE}/${href}" -o "${TLSDIR}/$(basename "${href}")"
  done
  log "[A] fetched $(find "${TLSDIR}" -name '*.rpm' | wc -l) TLS RPMs"
else
  log "[A] 6-slim (OL6.10) already ships the el6_10 NSS/openssl/curl stack; skipping TLS modernization"
fi

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A->B] write the builder-dedicated clean-core yum.repo as the ONLY repo     ║
# ║        (builder's own repos removed); on the FALLBACK path also stage the   ║
# ║        el6_10 TLS RPMs for the modernization step below.                    ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->B] writing builder clean-core yum.repo"
rm -f "${BUILDER}/etc/yum.repos.d/"*.repo
cat > "${BUILDER}/etc/yum.repos.d/cleancore.repo" <<EOF
[cc_ol6_latest]
name=OL${OSMAJOR} latest
baseurl=${REPO_BASE}/
gpgcheck=0
sslverify=${SSL}
enabled=1
EOF
if [ "${BUILDER_KIND}" = "pubyum66" ]; then
  log "[A->B] (fallback) staging el6_10 TLS RPMs into the builder"
  mkdir -p "${BUILDER}/tmp/tls"
  cp -f "${TLSDIR}"/*.rpm "${BUILDER}/tmp/tls/"
fi

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B] BUILDER — modernize (runs INSIDE the builder via chroot):              ║
# ║   (TLS) FALLBACK only -- builder rpm 4.8 installs the el6_10 NSS/curl/ca     ║
# ║         stack so its NSS 3.16 -> 3.44 and modern https becomes possible.     ║
# ║         The 6-slim (OL6.10) builder already has this stack and skips it.     ║
# ║   (4A)  yum updates the package managers (yum, rpm) -- both paths.           ║
# ║   oraclelinux-release is intentionally NOT updated here (the builder reads  ║
# ║   only cleancore.repo; the deliverable's release comes from the install).   ║
# ╚════════════════════════════════════════════════════════════════════════╝
if [ "${BUILDER_KIND}" = "pubyum66" ]; then
  log "[B] (TLS) installing el6_10 TLS stack via the builder's rpm 4.8"
  unshare --fork --pid --mount --uts --ipc bash -c "
    mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
    mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
    chroot '${BUILDER}' /bin/rpm -Uvh --replacepkgs --replacefiles /tmp/tls/*.rpm
  "
fi
log "[B] (4A) updating builder package managers (yum, rpm)"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y --setopt=sslverify=${SSL} --nogpgcheck \
    --disablerepo='*' --enablerepo=cc_ol6_latest update yum rpm
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B->C] the install transaction; writes the [C] clean-core rootfs via       ║
# ║        yum --installroot (OUT lives inside the builder fs).                 ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B->C] building clean-core into ${DELIV}"
rm -rf "${DELIV}"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y --installroot='${OUT}' --releasever=${OSMAJOR} \
    --disablerepo='*' --enablerepo=cc_ol6_latest --nogpgcheck \
    --setopt=tsflags=nodocs --setopt=sslverify=${SSL} \
    --exclude='${EXCLUDE}' \
    install ${INCLUDE[*]}
  chroot '${BUILDER}' /usr/bin/yum --installroot='${OUT}' clean all >/dev/null 2>&1 || true
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — finalized from [A] (host).                                ║
# ║     (3) device nodes + OCI-variable rewrite + OL6 UEK enable-var disable;   ║
# ║         then (C) enable the NSS dynamic CA trust, (B) the clean-core fetches ║
# ║         + installs the EPEL release RPM with its OWN curl/rpm, and the EPEL  ║
# ║         repo is repointed to the archive + force-disabled; drop build repo.  ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (3) device nodes, OCI + UEK rewrite, drop build-time repo"
for n in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" \
         "full c 1 7" "console c 5 1" "ptmx c 5 2" "tty c 5 0"; do
  # shellcheck disable=SC2086  # intentional word-split of the "name type maj min" node spec
  set -- $n
  rm -f "${DELIV}/dev/$1"
  mknod -m 666 "${DELIV}/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
done
rm -f "${DELIV}/etc/yum.repos.d/cleancore.repo"
# keep the rpm-provided repo files as source of truth; rewrite ONLY the
# unresolvable OCI variables + force https, and (OL6 uek repo) hard-disable the
# UEK enable-vars $uekr4/$uekr3/$uek. $basearch is a real yum var -- preserved.
# shellcheck disable=SC2016  # $ociregion/$ocidomain/$uek* are literal yum-variable text in the repo files, not shell expansions
find "${DELIV}/etc/yum.repos.d" -type f -name '*.repo*' -print0 \
  | xargs -0 -r sed -i \
      -e 's|yum$ociregion.$ocidomain|yum.oracle.com|g' \
      -e 's|yum$ociregion.oracle.com|yum.oracle.com|g' \
      -e 's|http://yum.oracle.com|https://yum.oracle.com|g' \
      -e "s|enabled[ ]*=[ ]*'\?\$uekr4'\?|enabled=0|g" \
      -e "s|enabled[ ]*=[ ]*'\?\$uekr3'\?|enabled=0|g" \
      -e "s|enabled[ ]*=[ ]*'\?\$uek'\?|enabled=0|g"

# (C) Enable the NSS dynamic CA trust INSIDE the clean-core. EL6's curl/yum are
# NSS-backed; until 'update-ca-trust enable' is run the system CA store is inert
# and NSS verifies NOTHING -- so no https repo (the OL6 base on yum.oracle.com or
# EPEL) is usable on a real host. This runs BEFORE (B) so the release-RPM fetch
# below itself verifies TLS on a trusted host.
log "[A->C] (C) enabling NSS dynamic CA trust in the clean-core"
if [ "${SANDBOX}" = "1" ]; then
  unshare --fork --pid --mount --uts --ipc bash -c "
    mount --bind /dev '${DELIV}/dev'  2>/dev/null || true
    mount -t proc proc '${DELIV}/proc' 2>/dev/null || true
    chroot '${DELIV}' /usr/bin/update-ca-trust enable
    chroot '${DELIV}' /usr/bin/update-ca-trust extract
  "
else
  log "[A->C] (C) SKIP: no intercepting proxy (real host); the clean-core keeps its standard ca-certificates bundle"
fi

# (B) The clean-core fetches the EPEL 6 release RPM with its OWN curl and installs
# it with its OWN rpm (EL6 rpm 4.8 -> db4 rpmdb stays consistent; no host rpm
# --root, which would write an EL6-incompatible rpmdb). yum is avoided on purpose:
# EL6 yum's urlgrabber cannot fetch a direct https package URL here. On a trusted
# host the fetch verifies (after C); in CI (INSECURE_TLS=1) it is insecure (-k)
# because the sandbox egress proxy presents an intercepting cert. epel-release's
# only real dep (redhat-release>=6) is provided by the installed oraclelinux-release.
log "[A->C] (B) clean-core fetches + installs the EPEL 6 release RPM <- ${EPEL_RPM_URL}"
cp -f /etc/resolv.conf "${DELIV}/etc/resolv.conf" 2>/dev/null || true
CURL_K=""; [ "${INSECURE_TLS}" = "1" ] && CURL_K="-k"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${DELIV}/dev'  2>/dev/null || true
  mount -t proc proc '${DELIV}/proc' 2>/dev/null || true
  chroot '${DELIV}' /usr/bin/curl -fsSL ${CURL_K} -o /tmp/epel-release-6-8.noarch.rpm '${EPEL_RPM_URL}'
  chroot '${DELIV}' /bin/rpm -Uvh /tmp/epel-release-6-8.noarch.rpm
  chroot '${DELIV}' /bin/rm -f /tmp/epel-release-6-8.noarch.rpm
"
rm -f "${DELIV}/etc/resolv.conf"
# EPEL 6 (just installed): Oracle does not host it, so the shipped repo points at
# a dead mirrorlist with the baseurl commented. Repoint the baseurl to the Fedora
# community archive, disable the mirrorlist, and force the repo DISABLED (the
# ENA/SSM harnesses enable it on demand). gpgcheck + key are kept; $basearch is a
# real yum var -- preserved.
find "${DELIV}/etc/yum.repos.d" -type f -name 'epel*.repo*' -print0 \
  | xargs -0 -r sed -i -E \
      -e 's|^#?baseurl=http://download\.fedoraproject\.org/pub/epel/|baseurl=https://archives.fedoraproject.org/pub/archive/epel/|' \
      -e 's|^mirrorlist=|#mirrorlist=|' \
      -e 's|^enabled=1|enabled=0|'

# (B) jq: not in the OL6 base repo (it is an EPEL package on EL6), so install it
# from the just-configured EPEL archive. The shipped EPEL repo stays enabled=0
# (above); EPEL is enabled TRANSIENTLY for this one transaction only
# (--enablerepo=epel), so the deliverable's repo state is unchanged. The
# clean-core's OWN EL6 yum performs the install (db4-consistent rpmdb), with
# --nogpgcheck + --setopt=sslverify=${SSL} to match the base install. Network is
# needed, so resolv.conf is supplied transiently (the rootfs ships none).
log "[A->C] (B) clean-core installs jq from EPEL (archive); EPEL stays disabled"
cp -f /etc/resolv.conf "${DELIV}/etc/resolv.conf" 2>/dev/null || true
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${DELIV}/dev'  2>/dev/null || true
  mount -t proc proc '${DELIV}/proc' 2>/dev/null || true
  chroot '${DELIV}' /usr/bin/yum -y --enablerepo=epel --nogpgcheck \
    --setopt=tsflags=nodocs --setopt=sslverify=${SSL} install jq
  chroot '${DELIV}' /usr/bin/yum clean all >/dev/null 2>&1 || true
"
rm -f "${DELIV}/etc/resolv.conf"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — (2-cleanup) logs / transient data (zero-fill preferred).  ║
# ║     OL6 is systemd-less (upstart): there is no journal; machine-id is a     ║
# ║     dbus concept. The rpmdb and directory structure are preserved.         ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (2-cleanup) zero-filling logs / transient files"
: > "${DELIV}/etc/machine-id"
ZERO_FILL=(
  /etc/hostname
  /var/lib/dbus/machine-id
  /root/.bash_history
)
for rel in "${ZERO_FILL[@]}"; do
  if [ -f "${DELIV}${rel}" ]; then : > "${DELIV}${rel}"; fi
done
for f in "${DELIV}/root/.ssh/authorized_keys" "${DELIV}"/home/*/.ssh/authorized_keys \
         "${DELIV}"/var/lib/dhclient/* "${DELIV}"/home/*/.bash_history; do
  if [ -f "$f" ]; then : > "$f"; fi
done
find "${DELIV}/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true

# REMOVE (an empty file here is broken, or it is pure cache/transient):
rm -f  "${DELIV}"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -rf "${DELIV}"/var/lib/cloud/* \
       "${DELIV}"/var/cache/yum/* \
       "${DELIV}"/tmp/* "${DELIV}"/var/tmp/* 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — package the [C] clean-core as tar.gz                            ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] packing -> ${OUT_TARBALL}"
mkdir -p "$(dirname "${OUT_TARBALL}")"
tar --numeric-owner -C "${DELIV}" -czf "${OUT_TARBALL}" .

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — unpack the deliverable (runtime-style) and self-test       ║
# ║     The shipped artifact is the tar.gz, so the tests run against a FRESH     ║
# ║     unpack of it -- exactly what a container runtime does -- NOT the build   ║
# ║     tree. This also catches anything lost or corrupted during packing.      ║
# ╚════════════════════════════════════════════════════════════════════════╝
IMG="${WORK}/unpacked"
log "[A->C] unpacking the deliverable tar.gz (runtime-style) -> ${IMG}"
rm -rf "${IMG}"; mkdir -p "${IMG}"
tar -C "${IMG}" -xzf "${OUT_TARBALL}"
SIZE="$(du -sh "${IMG}" | cut -f1)"   # pristine size, before any test writes cache

# test-time chroot helper -- operates on the UNPACKED image, not the build tree.
t_run() { chroot "${IMG}" "$@"; }

log "[A->C] (self-test) evaluating the unpacked clean-core image"
ST_PASS=0; ST_FAIL=0; ST_SKIP=0
st() {   # st "<label>" <command...>  -> PASS if the command exits 0, else FAIL
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "${label}"; ST_PASS=$((ST_PASS + 1))
  else
    printf '  FAIL  %s\n' "${label}"; ST_FAIL=$((ST_FAIL + 1))
  fi
}
skip() { printf '  SKIP  %s\n' "$1"; ST_SKIP=$((ST_SKIP + 1)); }

# ───────────────────────────────────────────────────────────────────────────
# Section 1 — UNCONDITIONAL tests (no external prerequisites; ALWAYS run).
# ───────────────────────────────────────────────────────────────────────────
PKGS="$(t_run /bin/rpm -qa 2>/dev/null | wc -l)"
FW="$( { t_run /bin/rpm -qa 2>/dev/null || true; } | grep -ci firmware || true)"
MID_SIZE="$(stat -c%s "${IMG}/etc/machine-id" 2>/dev/null || echo -1)"
SSH_KEYS="$(find "${IMG}/etc/ssh" -name 'ssh_host_*' 2>/dev/null | wc -l)"
NONEMPTY_LOGS="$(find "${IMG}/var/log" -type f -size +0c 2>/dev/null | wc -l)"
OCI_LEFT="$( { grep -rl 'ociregion' "${IMG}/etc/yum.repos.d/" 2>/dev/null || true; } | wc -l)"
UEK_ON="$( { grep -rsE "enabled[ ]*=[ ]*'?\\\$uek" "${IMG}/etc/yum.repos.d/" 2>/dev/null || true; } | wc -l)"
if [ -f "${IMG}/etc/yum.repos.d/cleancore.repo" ]; then CC_REPO=1; else CC_REPO=0; fi
EPEL_REPO="${IMG}/etc/yum.repos.d/epel.repo"
EPEL_PRESENT=0; [ -f "${EPEL_REPO}" ] && EPEL_PRESENT=1
EPEL_ENABLED1="$( { grep -cE '^enabled[ ]*=[ ]*1' "${EPEL_REPO}" 2>/dev/null || true; } )"; EPEL_ENABLED1="${EPEL_ENABLED1:-0}"
EPEL_ARCHIVE="$( { grep -cE '^baseurl=https://archives\.fedoraproject\.org/pub/archive/epel/' "${EPEL_REPO}" 2>/dev/null || true; } )"; EPEL_ARCHIVE="${EPEL_ARCHIVE:-0}"
# dynamic CA trust enabled => ca-bundle.crt is a symlink into the extracted store;
# this is the precondition for NSS-backed curl/yum to verify TLS (EPEL/base https).
CATRUST=0; [ -L "${IMG}/etc/pki/tls/certs/ca-bundle.crt" ] && CATRUST=1

st "userland executes (/bin/bash runs in chroot)"   t_run /bin/bash -c true
st "rpmdb readable, >0 packages (${PKGS})"          test "${PKGS}" -gt 0
st "package manager runs (yum --version)"            t_run /usr/bin/yum --version
st "jq present and executable (jq --version)"         t_run /usr/bin/jq --version
st "ssh daemon absent (slim base ships no sshd)"     test ! -e "${IMG}/usr/sbin/sshd"
st "OS is Oracle Linux 6"                            grep -q "release 6" "${IMG}/etc/oracle-release"
st "firmware excluded (0 packages)"                  test "${FW}" -eq 0
st "machine-id blanked (0 bytes)"                    test "${MID_SIZE}" -eq 0
st "ssh host keys absent (regenerate on boot)"       test "${SSH_KEYS}" -eq 0
st "logs zero-filled (no non-empty log files)"       test "${NONEMPTY_LOGS}" -eq 0
st "OCI yum variables rewritten (none remain)"       test "${OCI_LEFT}" -eq 0
st "UEK enable-vars disabled (none remain)"          test "${UEK_ON}" -eq 0
st "build-time repo dropped"                          test "${CC_REPO}" -eq 0
st "EPEL repo present (epel.repo installed)"         test "${EPEL_PRESENT}" -eq 1
st "EPEL shipped disabled (no enabled=1 in epel.repo)" test "${EPEL_ENABLED1}" -eq 0
st "EPEL baseurl repointed to the Fedora archive"    test "${EPEL_ARCHIVE}" -ge 1
if [ "${SANDBOX}" = "1" ]; then
  st "NSS dynamic CA trust enabled (TLS verifiable)"   test "${CATRUST}" -eq 1
else
  skip "NSS dynamic CA trust enabled (TLS verifiable) -- sandbox-only workaround, not applicable on a real host"
fi
st "tar.gz is a valid gzip archive"                  gzip -t "${OUT_TARBALL}"

# ───────────────────────────────────────────────────────────────────────────
# Section 2 — PREREQUISITE-GATED readiness test (is the image ready for the
#   follow-on package work this test base exists for?). Prerequisites, split:
#     image-side  (must live IN the deliverable): enabled yum/dnf repos
#                 (oraclelinux-release*, checked above) + ca-certificates (TLS).
#     harness-side(NOT baked; supplied at test time, as a runtime would): repo
#                 network reachability + DNS, sslverify per ${SSL}, and either a
#                 container runtime or /dev + /proc for a chroot.
#   If a harness-side prerequisite is missing the readiness test is SKIPPED
#   (it never FAILs the build); Section 1 alone governs pass/fail.
# ───────────────────────────────────────────────────────────────────────────
# image-side prerequisite (always checkable, no network): ca-certificates in img
st "ca-certificates present (TLS trust base)"        t_run /bin/rpm -q ca-certificates

# readiness probe: import+run via a container runtime where possible, else
# unpack+chroot. The search proves the (rewritten) repo config + manager work
# end-to-end: config parse -> metadata download -> query. resolv.conf is supplied
# transiently (the tarball ships none); sslverify follows ${SSL} (transient
# --setopt; never baked into the deliverable's repos).
cc_search_ready() {
  local rt=""
  for c in podman docker; do command -v "$c" >/dev/null 2>&1 && { rt="$c"; break; }; done
  if [ -n "${rt}" ]; then
    local tag="cleancore-ol6-selftest:tmp" rc
    if "${rt}" import "${OUT_TARBALL}" "${tag}" >/dev/null 2>&1 \
       && "${rt}" run --rm "${tag}" /bin/bash -c true >/dev/null 2>&1; then
      "${rt}" run --rm "${tag}" /usr/bin/yum -q --setopt=sslverify=${SSL} --nogpgcheck \
        search oraclelinux-release >/dev/null 2>&1; rc=$?
      "${rt}" rmi -f "${tag}" >/dev/null 2>&1 || true
      return "${rc}"
    fi
    "${rt}" rmi -f "${tag}" >/dev/null 2>&1 || true
  fi
  # no runtime, or it cannot run here (e.g. the Claude sandbox) -> unpack+chroot
  cp -f /etc/resolv.conf "${IMG}/etc/resolv.conf" 2>/dev/null || true
  unshare --fork --pid --mount --uts --ipc bash -c "
    mount --bind /dev '${IMG}/dev'  2>/dev/null || true
    mount -t proc proc '${IMG}/proc' 2>/dev/null || true
    chroot '${IMG}' /usr/bin/yum -q --setopt=sslverify=${SSL} --nogpgcheck \
      search oraclelinux-release
  "
}

if curl -fsS --max-time 8 -o /dev/null "https://yum.oracle.com/" 2>/dev/null; then
  st "repo config + manager ready (search oraclelinux-release)" cc_search_ready
else
  skip "repo config + manager ready (search oraclelinux-release) -- no network/DNS/TLS"
fi

# ───────────────────────────────────────────────────────────────────────────
log "[A] clean-core OL6: ${PKGS} packages, ${SIZE} (unpacked)"
log "  tar.gz : ${OUT_TARBALL}"
rm -rf "${IMG}"   # drop the test unpack -- the deliverable is the tar.gz
log "[A->C] self-test: ${ST_PASS} passed, ${ST_FAIL} failed, ${ST_SKIP} skipped"
if [ "${ST_FAIL}" -ne 0 ]; then
  log "[A->C] SELF-TEST FAILED"
  exit 1
fi
log "[A->C] self-test PASSED"
