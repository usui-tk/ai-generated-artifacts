#!/usr/bin/env bash
#
# build-cleancore-ol7.sh
# ----------------------------------------------------------------------------
# Naming convention: build-cleancore-ol<MAJOR>.sh  (the OS version is the
# trailing token). Family: build-cleancore-ol6.sh / -ol7.sh / -ol8.sh /
# -ol9.sh / -ol10.sh
# ----------------------------------------------------------------------------
# Build a *clean-core* Oracle Linux 7 container rootfs. Dedicated, self-contained
# OL7 script (no shared library, no config externalization -- by design).
#
# Three execution environments are involved; each block below is tagged:
#   [A] HOST         - the machine running this script (Claude sandbox / CI:
#                      Ubuntu 24.04 / end-user: RHEL 10|9, Fedora 44). It only
#                      orchestrates: downloads, extracts, edits files, packs, tests.
#   [B] BUILDER      - a THROWAWAY Oracle "7-slim" container rootfs, driven via
#                      unshare+chroot. It uses ONLY the builder-dedicated
#                      cleancore.repo below (its own bundled repo configs are
#                      never read). Its EL7 yum/rpm perform the install so the
#                      rpmdb is in-guest-readable. Builder contents are NOT shipped.
#   [C] CLEAN-CORE   - the DELIVERABLE rootfs produced by the install transaction
#                      (yum --installroot). Finalized, cleaned, and self-tested
#                      from [A] (no container runtime is used).
#
# ----------------------------------------------------------------------------
# PRIMARY SOURCES (verify upstream; pinned where possible)
#   - Builder image (OL7 "7-slim" rootfs tarball), Oracle official:
#       https://github.com/oracle/container-images/tree/0218ab4ba2f820b1b978dcc5a76435040397a472/7-slim
#       https://github.com/oracle/container-images/raw/0218ab4ba2f820b1b978dcc5a76435040397a472/7-slim/oraclelinux-7-slim-amd64-rootfs.tar.xz
#   - Package set (kickstart %packages), Oracle official:
#       https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools/distr/ol7-slim
#       https://github.com/oracle/oracle-linux/blob/main/oracle-linux-image-tools/distr/ol7-slim/ol7-ks.cfg
#   - Package repositories, Oracle official:
#       https://yum.oracle.com/
#   - Cleanup guidance (VM-oriented; container-applicable subset adopted), AWS:
#       https://docs.aws.amazon.com/imagebuilder/latest/userguide/security-best-practices.html
# ----------------------------------------------------------------------------
# Usage:   bash build-cleancore-ol7.sh [output.tar.gz]
#   env :  WORK=<scratch dir>   INSECURE_TLS=0  (drop sslverify=0 on a trusted host)
# Requires: root (unshare/chroot/mknod), curl, tar, xz, unshare, truncate, find, gzip.
# Exit:    0 = built and self-test passed; non-zero = build error or test failure.
# ----------------------------------------------------------------------------
set -euo pipefail

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST — configuration (inline by design; not externalized)            ║
# ╚════════════════════════════════════════════════════════════════════════╝
OSMAJOR=7
# Builder image, in preference order: (1) PRIMARY the Oracle container-registry
# "7-slim" image by its FLOATING tag (always the latest 7.x slim), pulled over the
# OCI registry v2 API (curl-only, or a container runtime if present); (2) FALLBACK
# the SAME 7-slim rootfs pinned in oracle/container-images at CI_COMMIT (byte-stable
# git-raw tarball) if the registry is unreachable.
OL_REGISTRY="${OL_REGISTRY:-https://container-registry.oracle.com}"
OL_IMAGE="${OL_IMAGE:-os/oraclelinux}"
OL_TAG="${OL_TAG:-7-slim}"                              # floating: latest 7.x slim
CI_COMMIT="0218ab4ba2f820b1b978dcc5a76435040397a472"   # oracle/container-images pin (fallback)
BUILDER_URL="https://github.com/oracle/container-images/raw/${CI_COMMIT}/7-slim/oraclelinux-7-slim-amd64-rootfs.tar.xz"

WORK="${WORK:-/tmp/cleancore-ol7}"
OUT_TARBALL="${1:-${WORK}/cleancore-ol7-rootfs.tar.gz}"

# Sandbox without a usable NSS trust store -> sslverify=0 for the BUILD only,
# supplied transiently via --setopt (never written into the deliverable's repos).
INSECURE_TLS="${INSECURE_TLS:-1}"
SSL=1; [ "${INSECURE_TLS}" = "1" ] && SSL=0
CURL_K=""; [ "${INSECURE_TLS}" = "1" ] && CURL_K="-k"   # host curl for the registry pull

REPO_LATEST="https://yum.oracle.com/repo/OracleLinux/OL${OSMAJOR}/latest/x86_64/"
REPO_UEKR6="https://yum.oracle.com/repo/OracleLinux/OL${OSMAJOR}/UEKR6/x86_64/"

# Package manifest (slim-aligned, NOT @core). The pristine ol7-slim image is the
# reference footprint: dropping @core means no kernel/boot/firewall/cron/syslog. A
# minimal userland comes in via yum + oraclelinux-release; the rest are the explicit
# essentials a test base needs. EL7-specific vs OL8-OL10: this is yum (no dnf, so no
# dnf-plugins-core); no langpack pin (EL7 has no glibc langpack split); git is plain
# git (EL7 has no git-core split -- it pulls ~30 perl-* packages, accepted for tool
# parity with the other OLs); git-lfs and the zstd CLI are NOT in the EL7 base repos
# (EPEL-only / absent), so they are omitted (installable on demand from EPEL). The
# Oracle EPEL repo is wired in but shipped disabled (finalized below). systemd is
# pulled transitively by iputils/procps-ng on EL7 and is accepted -- in container/
# chroot use it is never PID 1. NOTE (EL7-specific): the base oraclelinux-release
# (which provides /etc/oracle-release) must be listed explicitly -- unlike EL8-EL10,
# the EL7 oraclelinux-release-el7 repo-config package does NOT pull it in.
# yum-plugin-versionlock (default; in OL7/latest): package-pinning plugin so the
# base can hold/exclude packages -- parallels install-awscli.sh's versionlock v1-block.
INCLUDE=( yum oraclelinux-release oraclelinux-release-el7 oracle-epel-release-el7 yum-utils yum-plugin-versionlock
  curl wget git jq bzip2 unzip zip
  sudo which tar diffutils less findutils procps-ng psmisc hostname vim-minimal
  iproute iputils bind-utils traceroute nmap-ncat tcpdump )

# Defensive excludes only. Without @core the bulky members (kernel, firmware,
# firewalld, cron, syslog, NetworkManager, sssd, rhn-*) are never candidates, so
# the old @core-removal list is unnecessary. The globs below are a safety net in
# case a dependency ever tries to pull a kernel or firmware blob into what must
# remain a kernel-less container rootfs.
EXCLUDE="*firmware*,kernel*"

BUILDER="${WORK}/builder"      # [B] throwaway EL7-native builder rootfs
OUT="/cleancore"               # [C] installroot path INSIDE the builder
DELIV="${BUILDER}${OUT}"       # [C] deliverable rootfs as seen from [A]

log() { printf '%s [cleancore-ol7] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# helper: run a read-only command inside the [C] clean-core rootfs.
# Plain chroot (root) is enough for the self-test reads (rpm -qa, command -v,
# bash true); no namespaces / /dev bind are needed for these.
c_run() { chroot "${DELIV}" "$@"; }

# --- Tag-based builder image pull (OCI registry v2; curl-only + runtime fast-path) ---
# Pull oraclelinux:<tag> from the Oracle container registry into a rootfs dir. A
# floating tag (e.g. 7-slim) is always the latest N.x slim. Returns 0 on success,
# 1 to let the caller fall back. Self-contained (no shared lib) per the per-builder
# design; mirrors the OL5 builder. Needs host curl (+ python3 for the curl-only
# path); a missing tool or any failure simply returns 1 (-> caller falls back).
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
# ║ [A] HOST — acquire the builder rootfs. PRIMARY: the floating 7-slim tag    ║
# ║     from the Oracle container registry (latest 7.x; OCI v2 / curl).         ║
# ║     FALLBACK: the pinned 7-slim git-raw rootfs (byte-stable) if unreachable.║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A] acquiring the EL7 builder rootfs"
rm -rf "${WORK}"
mkdir -p "${BUILDER}"
if oci_pull_rootfs "${OL_REGISTRY}" "${OL_IMAGE}" "${OL_TAG}" "${BUILDER}"; then
  log "[A] using the floating ${OL_TAG} image from ${OL_REGISTRY#https://}/${OL_IMAGE} (latest 7.x)"
elif curl -fsSL --retry 2 -o "${WORK}/builder.tar.xz" "${BUILDER_URL}" 2>/dev/null; then
  log "[A] registry pull unavailable; falling back to the pinned 7-slim rootfs (${BUILDER_URL})"
  tar -C "${BUILDER}" -xJf "${WORK}/builder.tar.xz"
  rm -f "${WORK}/builder.tar.xz"
else
  log "[A] ERROR: could not acquire the 7-slim builder rootfs (registry + pinned both failed)"; exit 1
fi
[ -x "${BUILDER}/bin/rpm" ] || [ -x "${BUILDER}/usr/bin/rpm" ] || { log "[A] ERROR: builder has no rpm"; exit 1; }
# the slim image ships no resolv.conf; share host DNS for the build
cp -f /etc/resolv.conf "${BUILDER}/etc/resolv.conf" 2>/dev/null || true

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [A] HOST -> writes the builder-dedicated clean-core yum.repo into [B]'s fs ║
# ║     (shared pre-step 1: verified yum.oracle.com URLs). The builder uses    ║
# ║     ONLY this repo; its bundled repo configs are never read.               ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->B] (1) writing builder-dedicated clean-core yum.repo"
cat > "${BUILDER}/etc/yum.repos.d/cleancore.repo" <<EOF
[cc_latest]
name=OL${OSMAJOR} latest
baseurl=${REPO_LATEST}
gpgcheck=0
enabled=0
[cc_uekr6]
name=OL${OSMAJOR} UEKR6
baseurl=${REPO_UEKR6}
gpgcheck=0
enabled=0
EOF

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B] BUILDER — runs INSIDE the builder via chroot.                        ║
# ║     Update ONLY the package managers (yum, rpm) so the build transaction  ║
# ║     runs on current tooling. oraclelinux-release is intentionally NOT     ║
# ║     updated: the builder never reads its own repo configs (only           ║
# ║     cleancore.repo), and the deliverable gets a current oraclelinux-      ║
# ║     release from the install transaction below.                          ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B] updating builder package managers (yum, rpm)"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y \
    --disablerepo='*' --enablerepo=cc_latest --enablerepo=cc_uekr6 --nogpgcheck \
    --setopt=sslverify=${SSL} \
    update yum rpm
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [B] BUILDER — the install transaction; writes the [C] clean-core rootfs   ║
# ║     via yum --installroot (OUT lives inside the builder fs).              ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[B->C] building clean-core into ${DELIV}"
rm -rf "${DELIV}"
unshare --fork --pid --mount --uts --ipc bash -c "
  mount --bind /dev '${BUILDER}/dev'  2>/dev/null || true
  mount -t proc proc '${BUILDER}/proc' 2>/dev/null || true
  chroot '${BUILDER}' /usr/bin/yum -y --installroot='${OUT}' --releasever=${OSMAJOR} \
    --disablerepo='*' --enablerepo=cc_latest --enablerepo=cc_uekr6 --nogpgcheck \
    --setopt=group_package_types=mandatory --setopt=tsflags=nodocs \
    --setopt=install_weak_deps=False --setopt=sslverify=${SSL} \
    --exclude='${EXCLUDE}' \
    install ${INCLUDE[*]}
  chroot '${BUILDER}' /usr/bin/yum --installroot='${OUT}' clean all >/dev/null 2>&1 || true
"

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — finalized from [A] (host) since no runtime is used.       ║
# ║     (3) device nodes + OCI-variable rewrite + drop the build-time repo.    ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (3) device nodes, OCI-variable rewrite, drop build-time repo"
for n in "null c 1 3" "zero c 1 5" "random c 1 8" "urandom c 1 9" \
         "full c 1 7" "console c 5 1" "ptmx c 5 2" "tty c 5 0"; do
  # shellcheck disable=SC2086  # intentional word-split of the "name type maj min" node spec
  set -- $n
  rm -f "${DELIV}/dev/$1"
  mknod -m 666 "${DELIV}/dev/$1" "$2" "$3" "$4" 2>/dev/null || true
done
# the build-time repo is never shipped in the deliverable
rm -f "${DELIV}/etc/yum.repos.d/cleancore.repo"
# keep the rpm-provided repo files (from oraclelinux-release) as source of truth;
# rewrite ONLY the unresolvable OCI variables + force https ($basearch is kept).
# shellcheck disable=SC2016  # $ociregion/$ocidomain are literal yum-variable text in the repo files, not shell expansions
find "${DELIV}/etc/yum.repos.d" -type f -name '*.repo*' -print0 \
  | xargs -0 -r sed -i \
      -e 's|yum$ociregion.$ocidomain|yum.oracle.com|g' \
      -e 's|yum$ociregion.oracle.com|yum.oracle.com|g' \
      -e 's|http://yum.oracle.com|https://yum.oracle.com|g'
# (C-ii) ship the Oracle EPEL repo present but DISABLED; the ENA/SSM harnesses
# enable it explicitly (e.g. dkms from EPEL, or git-lfs/zstd which are EPEL-only
# on EL7). The base then resolves against the base repos only, which keeps
# clean-core behaviour predictable.
find "${DELIV}/etc/yum.repos.d" -type f -name 'oracle-epel-*.repo*' -print0 \
  | xargs -0 -r sed -i -E 's/^enabled[[:space:]]*=[[:space:]]*1/enabled=0/'

# ╔════════════════════════════════════════════════════════════════════════╗
# ║ [C] CLEAN-CORE — (2-cleanup) logs / transient data.                        ║
# ║     Adopted from the AWS Image Builder Linux clean-up guidance, reduced to ║
# ║     the CONTAINER-APPLICABLE subset. PREFERENCE: zero-fill (keep the file, ║
# ║     size 0) so nothing that opens the path breaks. A few items are instead ║
# ║     REMOVED because an empty file there is itself broken/meaningless       ║
# ║     (reasons inline). The rpmdb and directory structure are preserved.     ║
# ╚════════════════════════════════════════════════════════════════════════╝
log "[A->C] (2-cleanup) zero-filling logs / transient files"
# machine-id: must EXIST and be EMPTY so a unique id regenerates on first boot
: > "${DELIV}/etc/machine-id"
# zero-fill named files where an empty file is valid + expected
ZERO_FILL=(
  /etc/hostname
  /etc/.updated
  /var/.updated
  /var/lib/rsyslog/imjournal.state
  /root/.bash_history
)
for rel in "${ZERO_FILL[@]}"; do
  if [ -f "${DELIV}${rel}" ]; then : > "${DELIV}${rel}"; fi
done
# zero-fill globbed files (authorized_keys, dhcp leases, per-user history)
for f in "${DELIV}/root/.ssh/authorized_keys" "${DELIV}"/home/*/.ssh/authorized_keys \
         "${DELIV}"/var/lib/dhclient/* "${DELIV}"/home/*/.bash_history; do
  if [ -f "$f" ]; then : > "$f"; fi
done
# zero-fill EVERY regular file under /var/log (keeps files + structure)
find "${DELIV}/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true

# REMOVE (an empty file here is broken or it is pure cache/transient):
#  - ssh host keys: absent => regenerated on first boot; a 0-byte key breaks sshd
#  - systemd journal (binary), cloud-init state, pkg-manager caches, temp dirs
rm -f  "${DELIV}"/etc/ssh/ssh_host_* 2>/dev/null || true
rm -f  "${DELIV}/etc/sudoers.d/90-cloud-init-users" 2>/dev/null || true
rm -rf "${DELIV}"/var/log/journal/* "${DELIV}"/var/lib/cloud/* \
       "${DELIV}"/var/cache/yum/* "${DELIV}"/var/cache/dnf/* \
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
# Self-test chroot with the HOST /dev (+ /proc) bind-mounted -- the matrix
# execution model. Rationale (2026-07-19 field failure, OL5 first hit): a
# plain chroot inherits the unpack volume's mount flags, so on a `nodev`
# work volume the image's own device nodes are inert and the package-manager
# probe dies on /dev/null -- a false negative about the HOST mount, not the
# image. The binds are explicitly torn down BEFORE the image tree is removed
# (an `rm -rf` descending into a live /dev bind would delete host devices).
mount --bind /dev "${IMG}/dev" 2>/dev/null || true
mount -t proc proc "${IMG}/proc" 2>/dev/null || true
# TMPDIR=/tmp inside the guest: a leaked host TMPDIR points at a path that
# does not exist in the image (2026-07-19 field failure class).
t_run() { chroot "${IMG}" /usr/bin/env TMPDIR=/tmp "$@"; }

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
PKGS="$(t_run /usr/bin/rpm -qa 2>/dev/null | wc -l)"
FW="$( { t_run /usr/bin/rpm -qa 2>/dev/null || true; } | grep -ci firmware || true)"
MID_SIZE="$(stat -c%s "${IMG}/etc/machine-id" 2>/dev/null || echo -1)"
SSH_KEYS="$(find "${IMG}/etc/ssh" -name 'ssh_host_*' 2>/dev/null | wc -l)"
NONEMPTY_LOGS="$(find "${IMG}/var/log" -type f -size +0c 2>/dev/null | wc -l)"
OCI_LEFT="$( { grep -rl 'ociregion' "${IMG}/etc/yum.repos.d/" 2>/dev/null || true; } | wc -l)"
if [ -f "${IMG}/etc/yum.repos.d/cleancore.repo" ]; then CC_REPO=1; else CC_REPO=0; fi

st "userland executes (/bin/bash runs in chroot)"   t_run /bin/bash -c true
st "rpmdb readable, >0 packages (${PKGS})"          test "${PKGS}" -gt 0
st "package manager runs (yum --version)"            t_run /usr/bin/yum --version
st "jq present and executable (jq --version)"         t_run /usr/bin/jq --version
st "ssh daemon absent (slim base ships no sshd)"     test ! -e "${IMG}/usr/sbin/sshd"
st "OS is Oracle Linux 7"                            grep -q "release 7" "${IMG}/etc/oracle-release"
st "firmware excluded (0 packages)"                  test "${FW}" -eq 0
st "machine-id blanked (0 bytes)"                    test "${MID_SIZE}" -eq 0
st "ssh host keys absent (regenerate on boot)"       test "${SSH_KEYS}" -eq 0
st "logs zero-filled (no non-empty log files)"       test "${NONEMPTY_LOGS}" -eq 0
st "OCI yum variables rewritten (none remain)"       test "${OCI_LEFT}" -eq 0
st "build-time repo dropped"                          test "${CC_REPO}" -eq 0
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
st "ca-certificates present (TLS trust base)"        t_run /usr/bin/rpm -q ca-certificates

# readiness probe: import+run via a container runtime where possible, else
# unpack+chroot. The search proves the (rewritten) repo config + manager work
# end-to-end: config parse -> metadata download -> query. resolv.conf is supplied
# transiently (the tarball ships none); sslverify follows ${SSL} (transient
# --setopt; never baked into the deliverable's repos).
cc_search_ready() {
  local rt=""
  for c in podman docker; do command -v "$c" >/dev/null 2>&1 && { rt="$c"; break; }; done
  if [ -n "${rt}" ]; then
    local tag="cleancore-ol7-selftest:tmp" rc
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
log "[A] clean-core OL7: ${PKGS} packages, ${SIZE} (unpacked)"
log "  tar.gz : ${OUT_TARBALL}"
umount "${IMG}/proc" 2>/dev/null || true
umount "${IMG}/dev" 2>/dev/null || true
rm -rf "${IMG}"   # drop the test unpack -- the deliverable is the tar.gz
log "[A->C] self-test: ${ST_PASS} passed, ${ST_FAIL} failed, ${ST_SKIP} skipped"
if [ "${ST_FAIL}" -ne 0 ]; then
  log "[A->C] SELF-TEST FAILED"
  exit 1
fi
log "[A->C] self-test PASSED"
