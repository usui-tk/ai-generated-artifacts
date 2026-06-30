#!/usr/bin/env bash
#==============================================================================
# install-aws_awscli-v2.sh - install the AWS CLI v2 on a RHEL-family host, and -
# in test mode - decide whether a given version INSTALLS and RUNS on this
# (glibc). Self-contained (no sourced library). Named to match the test folder
# tests/aws_awscli-v2/; run-awscli-installtest-matrix.sh kicks this script with
# parameters and consumes the single-line [result] JSON it emits.
#
# Two modes:
#   1. Production (AWSCLI_INSTALLTEST=0, default): install the pinned/requested
#      AWS CLI v2 from the official zip bundle, then block the repo awscli (v1)
#      via versionlock so yum/dnf never installs it over the v2 bundle.
#   2. Test (AWSCLI_INSTALLTEST=1): unzip the bundle to a disposable prefix,
#      introspect it OFFLINE (bundled Python + empirical min glibc), install,
#      run `aws --version` locally (no creds/IMDS), verify the landed version,
#      and emit one [aws_awscli-v2][installtest][result] {json} line.
#
# Every failure path still emits a structured {"status":"fail",...} result (die),
# so the matrix always records a parseable, reasoned row. The verdict is applied
# by the matrix; this script emits raw facts.
#
# Env:  AWSCLI_VERSION   (e.g. 2.27.0; default: per-major pin below)
#       AWSCLI_INSTALLTEST (0|1; default 0)
#       AWSCLI_ZIP_BASEURL (default https://awscli.amazonaws.com)
#       INSECURE_TLS     (0|1; default 0 -> curl -k for a MITM dev proxy)
#==============================================================================
set -uo pipefail

AWSCLI_VERSION="${AWSCLI_VERSION:-}"
AWSCLI_INSTALLTEST="${AWSCLI_INSTALLTEST:-0}"
ZIP_BASEURL="${AWSCLI_ZIP_BASEURL:-https://awscli.amazonaws.com}"
ZIP_NAME="awscli-exe-linux-x86_64"
INSECURE_TLS="${INSECURE_TLS:-0}"

# Per-RHEL-major pins: the AWS CLI v2 version the test matrix validated for each
# major. RHEL 6 (glibc 2.12) is below the v2 glibc-2.17 floor, so it is pinned to
# the last build that still supports older glibc (min_glibc 2.5; 2.17.50+ require
# glibc 2.17); RHEL 7-10 (glibc >= 2.17) track latest. An explicit AWSCLI_VERSION
# overrides these - the matrix always passes one in test mode, so the pins are the
# production default (resolved per the running OS in resolve_version below).
AWSCLI_VERSION_RHEL6="${AWSCLI_VERSION_RHEL6:-2.17.49}"
AWSCLI_VERSION_RHEL7="${AWSCLI_VERSION_RHEL7:-latest}"
AWSCLI_VERSION_RHEL8="${AWSCLI_VERSION_RHEL8:-latest}"
AWSCLI_VERSION_RHEL9="${AWSCLI_VERSION_RHEL9:-latest}"
AWSCLI_VERSION_RHEL10="${AWSCLI_VERSION_RHEL10:-latest}"

# Per-entry context, filled in as measured so die can emit a full fail result.
OSMAJOR=""; GLIBC=""; INSTALLED_VERSION=""; RAN="false"; RUN_METHOD=""
BUNDLED_PYTHON=""; MIN_GLIBC_MEASURED=""; RESULT_EMITTED=0

log() { printf '%s [install-aws_awscli-v2] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# die <reason> : in test mode emit a structured fail result (once), then exit 1.
die() {
  log "ERROR: $*"
  if [ "${AWSCLI_INSTALLTEST}" = "1" ] && [ "${RESULT_EMITTED}" = "0" ]; then
    RESULT_EMITTED=1
    printf '[aws_awscli-v2][installtest][result] {"status":"fail","tool":"aws_awscli-v2","osmajor":"%s","awscli_version":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s","bundled_python":"%s","min_glibc_measured":"%s","reason":"%s"}\n' \
      "${OSMAJOR}" "${AWSCLI_VERSION}" "${GLIBC}" "${INSTALLED_VERSION}" "${RAN}" "${RUN_METHOD}" "${BUNDLED_PYTHON}" "${MIN_GLIBC_MEASURED}" "$(json_escape "$*")"
  fi
  exit 1
}

os_major() {
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    ( . /etc/os-release; printf '%s' "${VERSION_ID%%.*}" )
  elif [ -r /etc/redhat-release ]; then
    sed -n 's/.*release \([0-9]\+\).*/\1/p' /etc/redhat-release | head -1
  fi
}

host_glibc() {
  rpm -q --qf '%{VERSION}\n' glibc 2>/dev/null | head -1 && return 0
  ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$'
}

# detect_bundled_python <root> : the bundled CPython minor, from the libpython
# filename in the unzipped bundle (e.g. .../libpython3.11.so.1.0 -> "3.11").
detect_bundled_python() {
  local root="$1" lp
  lp="$(find "${root}/aws" -maxdepth 4 -name 'libpython3*.so*' -type f 2>/dev/null | head -1)"
  [ -n "${lp}" ] || { printf ''; return 0; }
  printf '%s' "${lp##*/}" | sed -E 's/^libpython([0-9]+\.[0-9]+).*/\1/'
}

# bundled_python_running <aws-bin> : the FULL X.Y.Z from `aws --version`'s
# Python/X.Y.Z (only when the binary runs - refines the offline minor).
bundled_python_running() {
  [ -x "$1" ] || { printf ''; return 0; }
  "$1" --version 2>&1 | grep -oE 'Python/[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's#Python/##'
}

# measure_min_glibc <root> : the bundle's EMPIRICAL minimum glibc - the max
# GLIBC_x.y symbol version required across its .so's, read dependency-free (no
# readelf/binutils) by grepping the version strings embedded in the binaries.
measure_min_glibc() {
  local root="$1"
  find "${root}/aws" -name '*.so*' -type f -exec grep -aohE 'GLIBC_[0-9]+\.[0-9]+' {} + 2>/dev/null \
    | sed 's/^GLIBC_//' | sort -t. -k1,1n -k2,2n -u | tail -1
}

curl_get() {
  local url="$1" out="$2"
  local -a opts=(-fsSL --retry 2 -o "${out}")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(-k)
  curl "${opts[@]}" "${url}"
}

zip_url_for() {
  if [ "$1" = "latest" ]; then printf '%s/%s.zip' "${ZIP_BASEURL}" "${ZIP_NAME}"
  else printf '%s/%s-%s.zip' "${ZIP_BASEURL}" "${ZIP_NAME}" "$1"; fi
}

# fetch_unzip <workdir> : download + unzip the bundle into <workdir>/aws. die on error.
fetch_unzip() {
  local wd="$1" url
  url="$(zip_url_for "${AWSCLI_VERSION}")"
  log "fetching ${url}"
  curl_get "${url}" "${wd}/awscliv2.zip" || die "fetch failed: ${url}"
  ( cd "${wd}" && unzip -q awscliv2.zip ) || die "unzip failed (is unzip installed?)"
}

# block_awscli_v1 : production-only; exclude the repo awscli (v1) via versionlock
# so yum/dnf never installs it over the v2 bundle. Best-effort (WARNING only).
block_awscli_v1() {
  local -a so=()
  [ "${INSECURE_TLS}" = "1" ] && so=(--setopt=sslverify=0)
  if command -v dnf >/dev/null 2>&1; then
    if dnf -y "${so[@]}" install python3-dnf-plugin-versionlock >/dev/null 2>&1 \
       && dnf "${so[@]}" versionlock exclude 'awscli' >/dev/null 2>&1; then
      log "v1-block: dnf versionlock excludes awscli (v1)"; return 0
    fi
  elif command -v yum >/dev/null 2>&1; then
    if yum -y "${so[@]}" install yum-plugin-versionlock >/dev/null 2>&1 \
       && yum "${so[@]}" versionlock exclude 'awscli' >/dev/null 2>&1; then
      log "v1-block: yum versionlock excludes awscli (v1)"; return 0
    fi
  fi
  log "WARNING: could not apply the awscli(v1) versionlock exclude - verify yum/dnf does not pull v1"
}

resolve_version() {
  [ -n "${AWSCLI_VERSION}" ] && return 0
  case "$(os_major)" in
    6)  AWSCLI_VERSION="${AWSCLI_VERSION_RHEL6}" ;;
    7)  AWSCLI_VERSION="${AWSCLI_VERSION_RHEL7}" ;;
    8)  AWSCLI_VERSION="${AWSCLI_VERSION_RHEL8}" ;;
    9)  AWSCLI_VERSION="${AWSCLI_VERSION_RHEL9}" ;;
    10) AWSCLI_VERSION="${AWSCLI_VERSION_RHEL10}" ;;
    *)  AWSCLI_VERSION="latest" ;;
  esac
}

# Tests source this script for the pure pin/resolver/introspection logic without
# installing: AWSCLI_LIB_ONLY=1 stops here, after the helpers + pins are defined.
[ "${AWSCLI_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

trap 'die "unexpected error (line ${LINENO})"' ERR

OSMAJOR="$(os_major)"
GLIBC="$(host_glibc)"
resolve_version

if [ "${AWSCLI_INSTALLTEST}" = "1" ]; then
  # --- test mode: unzip, introspect offline, install, run, verify, emit -------
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' EXIT
  fetch_unzip "${workdir}"
  BUNDLED_PYTHON="$(detect_bundled_python "${workdir}")"
  MIN_GLIBC_MEASURED="$(measure_min_glibc "${workdir}")"
  log "bundle: Python ${BUNDLED_PYTHON:-?} | empirical min glibc ${MIN_GLIBC_MEASURED:-?}"
  prefix="${workdir}/prefix"
  "${workdir}/aws/install" -i "${prefix}/aws-cli" -b "${prefix}/bin" >/dev/null 2>&1 \
    || die "bundle install failed (glibc too old or installer error)"
  INSTALLED_VERSION="$("${prefix}/bin/aws" --version 2>&1 | sed -n 's#aws-cli/\([0-9.]*\).*#\1#p')"
  [ -n "${INSTALLED_VERSION}" ] || die "installs-but-wont-run: aws installed but --version did not run on RHEL${OSMAJOR} (glibc ${GLIBC})"
  RAN="true"; RUN_METHOD="aws --version"
  _bp="$(bundled_python_running "${prefix}/bin/aws")"; [ -n "${_bp}" ] && BUNDLED_PYTHON="${_bp}"
  if [ "${AWSCLI_VERSION}" != "latest" ] && [ "${INSTALLED_VERSION}" != "${AWSCLI_VERSION}" ]; then
    die "version-mismatch: requested ${AWSCLI_VERSION} but installed ${INSTALLED_VERSION}"
  fi
  RESULT_EMITTED=1
  printf '[aws_awscli-v2][installtest][result] {"status":"ok","tool":"aws_awscli-v2","osmajor":"%s","awscli_version":"%s","glibc":"%s","installed_version":"%s","ran":%s,"run_method":"%s","bundled_python":"%s","min_glibc_measured":"%s"}\n' \
    "${OSMAJOR}" "${AWSCLI_VERSION}" "${GLIBC}" "${INSTALLED_VERSION}" "${RAN}" "${RUN_METHOD}" "${BUNDLED_PYTHON}" "${MIN_GLIBC_MEASURED}"
  exit 0
fi

# --- production mode ----------------------------------------------------------
log "installing AWS CLI v2 (${AWSCLI_VERSION}) to /usr/local"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
fetch_unzip "${workdir}"
"${workdir}/aws/install" -i /usr/local/aws-cli -b /usr/local/bin >/dev/null 2>&1 \
  || "${workdir}/aws/install" --update -i /usr/local/aws-cli -b /usr/local/bin >/dev/null 2>&1 \
  || die "AWS CLI v2 install failed"
/usr/local/bin/aws --version || true
block_awscli_v1
log "done"
