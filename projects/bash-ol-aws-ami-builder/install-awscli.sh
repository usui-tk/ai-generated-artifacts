#!/usr/bin/env bash
#
# install-awscli.sh
#
# Install the AWS CLI v2 (the EC2-instance utility) on an Oracle Linux
# image/instance, and -- in test mode -- determine whether a given AWS CLI v2
# version INSTALLS and actually RUNS on this (glibc, kernel). SELF-CONTAINED
# (no shared library). Mirrors install-ssm-agent.sh / install-ena-driver.sh.
#
# Two execution environments:
#   1. Production (AWSCLI_INSTALLTEST=0, default): install the pinned/requested
#      AWS CLI v2 from the official zip bundle on a real OL instance, and pin the
#      OL-repo `awscli` (v1) package out via versionlock so yum/dnf never installs
#      v1. NOT wired into build-ol-aws-ami.sh today -- whether AWS CLI v2 joins
#      the AMI pipeline is the maintainer's call AFTER the install+run test report
#      (a future SPEC section), exactly as SSM was test-first (B.10 -> B.11).
#   2. Test (AWSCLI_INSTALLTEST=1): the container install-test environment used by
#      tests/awscli/run-awscli-installtest-matrix.sh. Installs the requested
#      version into a disposable clean-core rootfs, records the (glibc, kernel)
#      context, runs `aws --version` locally (no AWS creds / no IMDS), and emits a
#      single-line [result] JSON the matrix ledger consumes.
#
# WHY glibc: AWS CLI v2 ships as a self-contained zip bundle that BUNDLES its own
# Python runtime, so it does NOT use the OS Python -- but the bundled interpreter
# and its shared objects are built against a manylinux glibc, so the OS glibc
# gates whether the bundle installs and runs. AWS policy ("Linux Support Updates
# for AWS CLI v2", 2024-09-16): v2 Linux executables are built on the manylinux2014
# image (glibc 2.17); from that date v2 supports glibc >= 2.17, and glibc <= 2.16
# has no guaranteed compatibility with newer v2 -- the documented escape hatch is
# to stay on v2 <= 2.17.49. So the real surface is (glibc) x version:
#   * OL6 glibc 2.12 -- below the 2.17 floor: current v2 will not install/run; only
#                       an old enough build (older manylinux floor) does. The
#                       install+run matrix settled this empirically: OL6 runs up
#                       to 2.17.51 (the last build whose bundled .so's need only
#                       GLIBC_2.5); 2.17.52 is the first to require GLIBC_2.17 and
#                       fails. 2.17.51 is the last bundled-Python-3.11.9 build --
#                       2 patches above AWS's documented <= 2.17.49 boundary.
#   * OL7 glibc 2.17 -- exactly the floor: current v2 is expected to install + run.
#   * OL8 glibc 2.28 -- above the floor: current v2 installs + runs.
# The OL glibc is read authoritatively from the rpm db (`rpm -q glibc`); the OL
# target UEK kernel is recorded the same way as the SSM path (`rpm -q kernel-uek`)
# -- secondary here, kept for a ledger schema parallel to SSM; `uname -r` is the
# live host (runner) kernel, recorded separately as test_host_kernel.
#
# RUN proxy: `aws --version` exercises the bundled Python + glibc-linked .so's --
# the meaningful binary-load check (a too-old glibc fails the loader here with
# "version `GLIBC_2.NN' not found"). `aws sts get-caller-identity` needs AWS creds
# + network (a real instance), so it is the real-instance confirmation, NOT part
# of the in-container test (analogous to SSM's ec2messages runtime check).
#
# Sources:
#   GitHub:  https://github.com/aws/aws-cli (v2 branch + tags) -- the version set
#   Bundle:  https://awscli.amazonaws.com/awscli-exe-linux-x86_64[-<VERSION>].zip
#   Policy:  https://aws.amazon.com/blogs/developer/linux-support-updates-for-aws-cli-v2/
# This script is original.
#
set -euo pipefail

# ---- pinned version (overridable) ------------------------------------------
# Per-OL default mirrors install-ssm-agent.sh's *_OL<major> map. OL7/OL8 follow
# the moving `latest` bundle; OL6 (glibc 2.12) cannot run current v2, so its
# default is pinned to 2.17.51 -- the highest build the OL6/OL7/OL8 install+run
# matrix proved actually installs AND runs on OL6 (the last bundled-Python-3.11.9
# build; 2.17.52 is the first to require GLIBC_2.17 and fails on glibc 2.12). This
# is 2 patches above AWS's documented <= 2.17.49 boundary, confirmed empirically;
# both bundle Python 3.11.9 (security-support end 2027-10-31), so the pin gains a
# newer CLI/botocore at no Python-EOL cost. An explicit AWSCLI_VERSION overrides
# (the install-test matrix always sets it).
# OL5 (legacy PoC target; glibc 2.5): ceiling-pinned to 2.17.51 -- the SAME pin
# as OL6, for the now-measured same reason: at 2.17.52 the bundle rebases
# Python 3.11 -> 3.12 and its empirical glibc floor jumps 2.5 -> 2.17 (launcher
# additionally demands GLIBC_2.7/2.14; loader errors captured verbatim,
# 2026-07-18 investigation). The FULL OL5 sweep (all 921 fetchable v2
# releases on the OL5.11 clean-core, merged into the canonical ledger:
# 493 ok / 428 fail, `tests/awscli/RESULTS-ol5.md`) confirms the boundary
# lands exactly at 2.17.51 / 2.17.52: zero ok above the ceiling -- ALL ok
# rows via the standard aws/install symlink under the matrix execution
# model -- and a hard, permanent glibc-too-old wall for >= 2.17.52 (the sole
# other fail, 2.0.32, is an upstream S3 404). (Investigation lesson, recorded
# in SPEC: the 3.8/3.9-bundled-bootloader band NEEDS /proc mounted to
# self-resolve; a proc-less ad-hoc chroot mis-resolves from the symlink dir.
# The matrix always mounts /proc, as does any real instance.) OL5 is install-test /
# PoC scoped: the bundle zip must be pre-staged from the host (EL5 openssl
# 0.9.8e = TLS 1.0 max cannot reach the TLS-1.2-only awscli.amazonaws.com
# in-OS) and a chroot "runs" does not prove the real UEK R2 kernel runtime.
AWSCLI_VERSION_OL5="${AWSCLI_VERSION_OL5:-2.17.51}"
AWSCLI_VERSION_OL6="${AWSCLI_VERSION_OL6:-2.17.51}"
AWSCLI_VERSION_OL7="${AWSCLI_VERSION_OL7:-latest}"
AWSCLI_VERSION_OL8="${AWSCLI_VERSION_OL8:-latest}"
AWSCLI_VERSION="${AWSCLI_VERSION:-}"
AWSCLI_ZIP_BASEURL="${AWSCLI_ZIP_BASEURL:-https://awscli.amazonaws.com}"
AWSCLI_ZIP_NAME="${AWSCLI_ZIP_NAME:-awscli-exe-linux-x86_64}"
AWSCLI_INSTALL_DIR="${AWSCLI_INSTALL_DIR:-/opt/aws/awscli}"
AWSCLI_BIN_DIR="${AWSCLI_BIN_DIR:-/usr/bin}"

# ---- execution-environment switch (default = production) -------------------
# AWSCLI_INSTALLTEST=1 selects the container install-test environment (install +
# local `aws --version` only -- no AWS creds, no IMDS). Default 0 = production.
AWSCLI_INSTALLTEST="${AWSCLI_INSTALLTEST:-0}"
# INSECURE_TLS=1 drops TLS peer verification for the test-mode network commands
# only (MITM dev proxy / EL6 NSS trust gaps). Consulted only in the test branch.
INSECURE_TLS="${INSECURE_TLS:-0}"

# Execution-environment tag, injected by every emitter so output is tagged by
# environment WITHOUT changing call sites (mirrors install-ssm-agent.sh).
_env_tag() { if [[ "${AWSCLI_INSTALLTEST}" == "1" ]]; then printf '[installtest]'; fi; }
log()   { echo "[awscli]$(_env_tag) $*"; }
stage() { echo "[awscli]$(_env_tag)[stage] $*"; }

# Per-entry context, filled in as it is measured, so the die-handler can emit a
# fully-populated fail result.
osmajor=""; awscli_version="${AWSCLI_VERSION}"; kver=""; glibc=""; test_host_kernel=""
installed_version=""; ran="false"; run_method=""
# Bundle introspection (offline; populated right after unzip, so even a glibc-too-old
# fail result records them): the bundled CPython version and the bundle's EMPIRICAL
# minimum glibc (max GLIBC_x.y symbol required by its .so's).
bundled_python=""; min_glibc_measured=""

die() {
  echo "[awscli]$(_env_tag)[ERROR] $*" >&2
  if [[ "${AWSCLI_INSTALLTEST}" == "1" ]]; then
    printf '[awscli][installtest][result] {"status":"fail","osmajor":"%s","awscli_version":"%s","kver":"%s","test_host_kernel":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s","bundled_python":"%s","min_glibc_measured":"%s","reason":"%s"}\n' \
      "${osmajor}" "${awscli_version}" "${kver}" "${test_host_kernel}" "${glibc}" "${installed_version}" "${ran}" "${run_method}" "${bundled_python}" "${min_glibc_measured}" \
      "$(printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
  exit 1
}

# ---- detect OS major (no sourcing: grep both release files) -----------------
detect_osmajor() {
  local v=""
  if [[ -r /etc/oracle-release ]]; then
    v="$(grep -oE '[0-9]+' /etc/oracle-release | head -1 || true)"
  fi
  if [[ -z "${v}" && -r /etc/os-release ]]; then
    v="$(grep -E '^VERSION_ID=' /etc/os-release | grep -oE '[0-9]+' | head -1 || true)"
  fi
  printf '%s' "${v}"
}

# ---- the bundle zip URL for a version (or the moving `latest`) --------------
zip_url_for() {
  local ver="$1"
  if [[ "${ver}" == "latest" ]]; then
    printf '%s/%s.zip' "${AWSCLI_ZIP_BASEURL}" "${AWSCLI_ZIP_NAME}"
  else
    printf '%s/%s-%s.zip' "${AWSCLI_ZIP_BASEURL}" "${AWSCLI_ZIP_NAME}" "${ver}"
  fi
}

# ---- fetch helper (honors INSECURE_TLS) ------------------------------------
fetch() {
  local url="$1" dest="$2"
  local -a opts=(-fsSL -o "${dest}" --max-time "${AWSCLI_FETCH_TIMEOUT:-180}")
  if [[ "${INSECURE_TLS}" == "1" ]]; then opts+=(-k); fi
  curl "${opts[@]}" "${url}"
}

# ---- read the installed aws version (empty if it does not execute) ----------
# `aws --version` prints e.g. "aws-cli/2.17.49 Python/3.11.8 Linux/... exe/x86_64".
# Running it both reads the version AND exercises the bundled Python + glibc-linked
# .so's: a too-old glibc fails the loader here, so an empty return is the faithful
# "installed but won't run on this glibc" signal.
installed_aws_version() {
  local out=""
  if [[ -x "${AWSCLI_BIN_DIR}/aws" ]]; then
    if out="$("${AWSCLI_BIN_DIR}/aws" --version 2>&1)"; then
      printf '%s' "${out}" | sed -n 's#.*aws-cli/\([0-9][0-9.]*\).*#\1#p' | head -1
    fi
  fi
}

# ---- run check: does the installed aws actually FUNCTION on this glibc? ------
# Two offline (no creds / no IMDS) checks, both required, so the "ran" verdict is
# stronger than a static version print:
#   1. `aws --version`      -- loads the bundled interpreter + glibc-linked .so's
#                              (the bare binary-load check; fails the loader on a
#                              too-old glibc with "version `GLIBC_2.NN' not found").
#   2. `aws configure list` -- instantiates a CLI session and walks the command
#                              dispatch + config provider chain + botocore import,
#                              exercising far more of the runtime than (1). It exits
#                              0 with no config (all values "<not set>"), so it is a
#                              deterministic offline functional probe.
# Echoes the methods that ran (command-substitution-friendly, like SSM); returns
# non-zero and echoes nothing if either fails. `aws sts get-caller-identity` needs
# AWS creds + network -> it is the REAL-INSTANCE confirmation, not run in-container.
aws_runs_locally() {
  local out="" methods=""
  [[ -x "${AWSCLI_BIN_DIR}/aws" ]] || return 1
  if out="$(AWS_PAGER='' "${AWSCLI_BIN_DIR}/aws" --version 2>&1)" \
     && printf '%s' "${out}" | grep -qiE 'aws-cli/[0-9]+\.[0-9]+\.[0-9]+'; then
    methods="aws --version"
  else
    return 1
  fi
  if out="$(AWS_PAGER='' "${AWSCLI_BIN_DIR}/aws" configure list 2>&1)" \
     && printf '%s' "${out}" | grep -qiE 'profile|access_key|region'; then
    methods="${methods} + aws configure list"
  else
    return 1
  fi
  printf '%s' "${methods}"
  return 0
}

# ---- offline bundle introspection (works even when the bundle WON'T run) ------
# Both read the UNZIPPED bundle directly, so a glibc-too-old result still records
# the bundled Python + the empirical glibc floor (no need to execute the binary).
#   detect_bundled_python <root> : the bundled CPython minor, from the libpython
#     filename (e.g. aws/dist/libpython3.11.so.1.0 -> "3.11"); "" if not found.
#   bundled_python_running       : the FULL "X.Y.Z" from `aws --version`'s
#     "Python/X.Y.Z" (only when the binary runs -- refines the offline minor).
#   measure_min_glibc <root>     : the bundle's EMPIRICAL minimum glibc -- the max
#     GLIBC_x.y symbol version required across its .so's, read with a dependency-free
#     grep of the version strings embedded in the binaries (no readelf/binutils;
#     matches readelf exactly). This is the authoritative per-bundle glibc floor.
detect_bundled_python() {
  local root="$1" lp
  lp="$(find "${root}/aws" -maxdepth 4 -name 'libpython3*.so*' -type f 2>/dev/null | head -1)"
  [[ -n "${lp}" ]] || { printf ''; return 0; }
  # Pure-bash extraction (behaviour-identical to the old `sed -E` form):
  # EL5's sed 4.1.5 has no -E and, under set -e, its usage error killed the
  # whole install on the OL5 container FT. "libpython3.8.so.1.0" -> "3.8".
  local bn="${lp##*/}"
  bn="${bn#libpython}"
  printf '%s' "${bn%%.so*}"
}
bundled_python_running() {
  [[ -x "${AWSCLI_BIN_DIR}/aws" ]] || { printf ''; return 0; }
  "${AWSCLI_BIN_DIR}/aws" --version 2>&1 \
    | grep -oE 'Python/[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's#Python/##'
}
measure_min_glibc() {
  local root="$1"
  find "${root}/aws" -name '*.so*' -type f -exec grep -aohE 'GLIBC_[0-9]+\.[0-9]+' {} + 2>/dev/null \
    | sed 's/^GLIBC_//' | sort -t. -k1,1n -k2,2n -u | tail -1
}

# ---- block the OL-repo awscli (v1) via versionlock -------------------------
# OL6/OL7/OL8 ship an `awscli` (v1) package in their repos. Install the versionlock
# plugin and EXCLUDE `awscli` so yum/dnf will never pull v1 over the bundle-
# installed v2: yum-plugin-versionlock (YUM, OL6/OL7), python3-dnf-plugin-versionlock
# (DNF, OL8). Best-effort: a WARNING (not fatal) if the plugin/repo is unavailable
# -- the bundle install itself does not depend on it.
block_awscli_v1() {
  local -a setopt=()
  if [[ "${INSECURE_TLS}" == "1" ]]; then setopt=(--setopt=sslverify=false); fi
  if command -v dnf >/dev/null 2>&1 && dnf --version >/dev/null 2>&1; then
    if dnf -y "${setopt[@]}" install python3-dnf-plugin-versionlock >/dev/null 2>&1 \
       && dnf "${setopt[@]}" versionlock exclude 'awscli' >/dev/null 2>&1; then
      log "v1-block: dnf versionlock excludes 'awscli' (v1)"; return 0
    fi
  elif command -v yum >/dev/null 2>&1; then
    if yum -y "${setopt[@]}" install yum-plugin-versionlock >/dev/null 2>&1 \
       && yum "${setopt[@]}" versionlock exclude 'awscli' >/dev/null 2>&1; then
      log "v1-block: yum versionlock excludes 'awscli' (v1)"; return 0
    fi
  fi
  log "WARNING: could not apply the awscli(v1) versionlock exclude -- verify yum/dnf does not pull v1"
  return 0
}

osmajor="$(detect_osmajor)"
[[ -n "${osmajor}" ]] || die "cannot determine Oracle Linux major version"

# Resolve the version: an explicit AWSCLI_VERSION wins; otherwise the per-OL
# default (OL6 pinned, OL7/OL8 the moving `latest`). The install-test matrix
# always sets AWSCLI_VERSION, so this per-OL fallback is production-only.
if [[ -z "${awscli_version}" ]]; then
  case "${osmajor}" in
    5) awscli_version="${AWSCLI_VERSION_OL5}" ;;
    6) awscli_version="${AWSCLI_VERSION_OL6}" ;;
    7) awscli_version="${AWSCLI_VERSION_OL7}" ;;
    8) awscli_version="${AWSCLI_VERSION_OL8}" ;;
    *) awscli_version="latest" ;;
  esac
fi

# The runner/host kernel `aws` actually executes against (in a container the host
# kernel, NOT the OL UEK) -- recorded as-is for honesty.
test_host_kernel="$(uname -r 2>/dev/null || true)"

# ---- AWSCLI_INSTALLTEST: provision the OL UEK kernel + unzip ----------------
# Parallels install-ssm-agent.sh: glibc is the gate, but kernel-uek is provisioned
# so the OL target kernel can be read from the rpm db for a ledger schema parallel
# to SSM (a container shares the host kernel, so this does NOT change what `aws`
# runs on -- test_host_kernel above). `unzip` is ensured for the bundle. Scope is
# OL6/OL7/OL8 only. Production never enters this block.
if [[ "${AWSCLI_INSTALLTEST}" == "1" ]]; then
  case "${osmajor}" in
    5)
      # OL5: NO in-guest network path exists (EL5 openssl 0.9.8e = TLS 1.0 max
      # vs the TLS-1.2-only yum.oracle.com -- a protocol-level failure
      # sslverify=false cannot bypass). Nothing needs provisioning either:
      # unzip 5.52 already ships in the OL5 clean-core (verified), and the
      # kver record comes from the AWSCLI_OL5_KVER env contract (the matrix
      # passes the live-probed terminal el5uek NVR -- "probed, not
      # provisioned": the kernel is not the compat axis of this matrix and
      # installing the EL5 kernel RPM in a chroot risks its %post initrd
      # scriptlets). Verify the unzip contract and continue.
      command -v unzip >/dev/null 2>&1 \
        || die "AWSCLI_INSTALLTEST: unzip not present in the OL5 clean-core (contract violated; it ships in the base 125-package set)"
      bt_uek_repo="" ;;
    6) bt_uek_repo="ol6_UEKR4" ;;
    7) bt_uek_repo="ol7_UEKR6" ;;
    8)
      # OL8 slim ships dnf only; bootstrap the yum compat for the install below.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null 2>&1 || die "AWSCLI_INSTALLTEST: failed to bootstrap yum on OL8"
      else
        dnf -y install yum >/dev/null 2>&1 || die "AWSCLI_INSTALLTEST: failed to bootstrap yum on OL8"
      fi
      bt_uek_repo="ol8_UEKR6" ;;
    *) die "AWSCLI_INSTALLTEST: OS major ${osmajor} not wired (OL5 opt-in / OL6/OL7/OL8)" ;;
  esac
  if [[ "${osmajor}" != "5" ]]; then
  stage "provisioning kernel-uek (OL target-kernel record) via ${bt_uek_repo}"
  if [[ "${INSECURE_TLS}" == "1" ]]; then
    yum -y --setopt=sslverify=false --enablerepo="${bt_uek_repo}" install kernel-uek \
      || die "AWSCLI_INSTALLTEST: failed to provision kernel-uek"
  else
    yum -y --enablerepo="${bt_uek_repo}" install kernel-uek \
      || die "AWSCLI_INSTALLTEST: failed to provision kernel-uek"
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    stage "installing unzip (bundle expansion)"
    if [[ "${INSECURE_TLS}" == "1" ]]; then
      yum -y --setopt=sslverify=false install unzip >/dev/null 2>&1 || die "AWSCLI_INSTALLTEST: failed to install unzip"
    else
      yum -y install unzip >/dev/null 2>&1 || die "AWSCLI_INSTALLTEST: failed to install unzip"
    fi
  fi
  fi
fi

# Target OL kernel + OS glibc, read authoritatively from the rpm db. glibc is the
# install/run gate; kver is recorded for the SSM-parallel ledger. Falls back to
# the host kernel / getconf only if rpm has no row.
# sort stderr silenced: EL5 coreutils 5.97 has no -V and prints a usage error
# even on the empty OL5 stream (harmless -- the value is unused there -- but it
# pollutes the evidence log). OL6-8 behaviour unchanged.
kver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-uek 2>/dev/null | grep -E '^[0-9]' | sort -V 2>/dev/null | tail -1 || true)"
# OL5: the container has no kernel-uek rpm (see the INSTALLTEST block above);
# the matrix passes the live-probed terminal el5uek NVR instead.
if [[ -z "${kver}" && "${osmajor}" == "5" && -n "${AWSCLI_OL5_KVER:-}" ]]; then
  kver="${AWSCLI_OL5_KVER}"
fi
[[ -n "${kver}" ]] || kver="${test_host_kernel}"
# multilib-safe: x86_64 guests carry glibc.x86_64 AND glibc.i686 -- without a
# newline in the qf the two VERSIONs concatenate ("2.5"+"2.5" -> "2.52.5",
# observed on the real OL5 guest, record #7) and corrupt the glibc floor gate.
glibc="$(rpm -q --qf '%{VERSION}\n' glibc 2>/dev/null | grep -E '^[0-9]' | sort -u | head -1 || true)"
[[ -n "${glibc}" ]] || glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}' || true)"

log "OL${osmajor} | glibc ${glibc:-?} | kver ${kver:-?} (host ${test_host_kernel:-?}) | requested AWS CLI ${awscli_version}"

# ---- download + unzip the bundle -------------------------------------------
url="$(zip_url_for "${awscli_version}")"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
zipfile="${workdir}/awscliv2.zip"

if [[ "${osmajor}" == "5" ]]; then
  # OL5: the bundle must be PRE-STAGED from the host (no in-OS TLS 1.2 path;
  # the matrix stages it before invoking this script -- ENA-parallel contract).
  prestage="/usr/src/${AWSCLI_ZIP_NAME}-${awscli_version}.zip"
  stage "use pre-staged bundle ${prestage}"
  if [[ -f "${prestage}" ]]; then
    cp -f "${prestage}" "${zipfile}"
  else
    die "download-fail: OL5 bundle not pre-staged at ${prestage} -- EL5 cannot fetch from awscli.amazonaws.com in-OS (TLS 1.0 max); stage it from the host (the matrix OL5 branch does this automatically)"
  fi
else
  stage "fetch ${url}"
  fetch "${url}" "${zipfile}" || die "download-fail: AWS CLI v2 bundle fetch failed for ${awscli_version} (${url})"
fi

stage "unzip bundle"
# Pre-assert the tool (record #7: the ISO minimal OL5 guest has no unzip --
# the ks %packages contract supplies it from the U11 media; the EPEL5
# container clean-core observation did not transfer to the guest).
command -v unzip >/dev/null 2>&1 \
  || die "unpack-fail: 'unzip' is not installed (on OL5 it must come from the kickstart %packages contract; see SPEC D.32 record #7)"
unzip -oq "${zipfile}" -d "${workdir}" || die "unpack-fail: could not unzip the AWS CLI v2 bundle"
[[ -x "${workdir}/aws/install" ]] || die "unpack-fail: ${workdir}/aws/install missing after unzip"

# Introspect the bundle OFFLINE, before the install attempt: record the bundled
# CPython minor + the empirical glibc floor now, so even a glibc-too-old fail (the
# install/run die below) still carries them.
bundled_python="$(detect_bundled_python "${workdir}")"
min_glibc_measured="$(measure_min_glibc "${workdir}")"
log "bundle: Python ${bundled_python:-?} | empirical min glibc ${min_glibc_measured:-?}"

# ---- install ---------------------------------------------------------------
# `aws/install` runs the BUNDLED Python to lay down ${AWSCLI_INSTALL_DIR} and the
# ${AWSCLI_BIN_DIR}/aws symlink. If the OS glibc is older than the bundle's
# manylinux floor, the bundled interpreter fails to load HERE -- the faithful
# "won't install on this glibc" signal (the loader reports GLIBC_2.NN not found).
stage "install AWS CLI v2 -> ${AWSCLI_INSTALL_DIR} (bin ${AWSCLI_BIN_DIR})"
if ! "${workdir}/aws/install" -i "${AWSCLI_INSTALL_DIR}" -b "${AWSCLI_BIN_DIR}" --update 2>&1; then
  die "install-fail: aws/install failed for ${awscli_version} (likely glibc below the bundle manylinux floor on OL${osmajor} glibc ${glibc})"
fi

installed_version="$(installed_aws_version)"

[[ -n "${installed_version}" ]] || die "installs-but-wont-run: aws installed but '--version' did not execute on OL${osmajor} (glibc ${glibc}) -- bundled interpreter/glibc miss"
# Version-provenance guard (mirrors SSM's installed-version check): a specific
# request must match what landed (`latest` is allowed to resolve to any version).
if [[ "${awscli_version}" != "latest" && "${installed_version}" != "${awscli_version}" ]]; then
  die "version-mismatch: requested ${awscli_version} but installed ${installed_version}"
fi
log "installed aws-cli ${installed_version}"

# ---- run locally -----------------------------------------------------------
stage "run functional checks locally: 'aws --version' + 'aws configure list' (no creds/IMDS)"
if run_method="$(aws_runs_locally)"; then
  ran="true"
  # Refine the offline minor (e.g. 3.11) to the full patch (e.g. 3.11.9) now that
  # the bundled interpreter executes.
  _bp_full="$(bundled_python_running)"; [[ -n "${_bp_full}" ]] && bundled_python="${_bp_full}"
  log "aws runs locally via '${run_method}'"
else
  ran="false"
  die "installs-but-wont-run: aws ${installed_version} installed but the offline functional checks (aws --version / aws configure list) did not run on OL${osmajor} (glibc ${glibc})"
fi

# ---- production: block the OL-repo awscli (v1) -----------------------------
# The install-test path stops at install+run (repo/versionlock management is a
# real-instance concern, irrelevant to install/run capability). The production
# path excludes the v1 package so yum/dnf never installs it over the v2 bundle.
if [[ "${AWSCLI_INSTALLTEST}" != "1" ]]; then
  stage "block OL-repo awscli (v1) via versionlock"
  block_awscli_v1
fi

# ---- AWSCLI_INSTALLTEST: structured success result for the matrix ----------
if [[ "${AWSCLI_INSTALLTEST}" == "1" ]]; then
  printf '[awscli][installtest][result] {"status":"ok","osmajor":"%s","awscli_version":"%s","kver":"%s","test_host_kernel":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s","bundled_python":"%s","min_glibc_measured":"%s"}\n' \
    "${osmajor}" "${awscli_version}" "${kver}" "${test_host_kernel}" "${glibc}" "${installed_version}" "${ran}" "${run_method}" "${bundled_python}" "${min_glibc_measured}"
fi

log "done."
