#!/usr/bin/env bash
#==============================================================================
# install-aws_awscli-v2.sh - install the AWS CLI v2 on a RHEL-family host, and -
# in test mode - decide whether a given version INSTALLS and RUNS on this
# (glibc). Self-contained (no sourced library). Named to match the test folder
# tests/aws_awscli-v2/; run-awscli-installtest-matrix.sh kicks this script with
# parameters and consumes the single-line [result] JSON it emits.
#
# Two modes:
#   1. Production (AWSCLI_INSTALLTEST=0, default): install the requested/latest
#      AWS CLI v2 from the official zip bundle on a real host.
#   2. Test (AWSCLI_INSTALLTEST=1): install into a disposable prefix, run
#      `aws --version` locally (no creds / no IMDS), and emit one
#      [aws_awscli-v2][installtest][result] {json} line for the matrix ledger.
#
# WHY glibc: the v2 bundle ships its own Python built against a manylinux glibc,
# so the OS glibc gates install/run. The matrix applies the verdict; this script
# emits the raw observation (ran true/false + context).
#
# Env:  AWSCLI_VERSION   (e.g. 2.27.0; default: latest)
#       AWSCLI_INSTALLTEST (0|1; default 0)
#       AWSCLI_ZIP_BASEURL (default https://awscli.amazonaws.com)
#       INSECURE_TLS     (0|1; default 0 -> curl -k for a MITM dev proxy)
# Requires: curl, unzip (or the bundle's self-extractor), rpm/ldd. Network: the
# bundle CDN over *.amazonaws.com.
#==============================================================================
set -euo pipefail

AWSCLI_VERSION="${AWSCLI_VERSION:-}"
AWSCLI_INSTALLTEST="${AWSCLI_INSTALLTEST:-0}"

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
ZIP_BASEURL="${AWSCLI_ZIP_BASEURL:-https://awscli.amazonaws.com}"
ZIP_NAME="awscli-exe-linux-x86_64"
INSECURE_TLS="${INSECURE_TLS:-0}"

log() { printf '%s [install-aws_awscli-v2] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

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

curl_get() {
  local url="$1" out="$2"
  local -a opts=(-fsSL --retry 2 -o "${out}")
  [ "${INSECURE_TLS}" = "1" ] && opts+=(-k)
  curl "${opts[@]}" "${url}"
}

emit_result() { # <ran:true|false> <installed_version> <reason>
  local ran="$1" iv="$2" reason="$3"
  printf '[aws_awscli-v2][installtest][result] {"tool":"aws_awscli-v2","osmajor":"%s","awscli_version":"%s","glibc":"%s","ran":%s,"installed_version":"%s","run_method":"aws --version","reason":"%s"}\n' \
    "$(os_major)" "${AWSCLI_VERSION}" "$(host_glibc)" "${ran}" "${iv}" "${reason}"
}

install_bundle() { # <prefix-bin> <prefix-install> -> rc 0 on install
  local bindir="$1" instdir="$2" url zip tmp
  if [ "${AWSCLI_VERSION}" = "latest" ]; then
    zip="${ZIP_NAME}.zip"
  else
    zip="${ZIP_NAME}-${AWSCLI_VERSION}.zip"
  fi
  url="${ZIP_BASEURL}/${zip}"
  tmp="$(mktemp -d)"
  log "fetching ${url}"
  curl_get "${url}" "${tmp}/awscliv2.zip" || { rm -rf "${tmp}"; return 1; }
  ( cd "${tmp}" && { unzip -q awscliv2.zip || return 1; } ) || { rm -rf "${tmp}"; return 1; }
  "${tmp}/aws/install" -i "${instdir}" -b "${bindir}" >/dev/null 2>&1 || \
    "${tmp}/aws/install" --update -i "${instdir}" -b "${bindir}" >/dev/null 2>&1 || { rm -rf "${tmp}"; return 1; }
  rm -rf "${tmp}"
}

# resolve_version : explicit AWSCLI_VERSION wins; otherwise fall back to the
# per-major pin for the running OS (production default). Resolved before install
# so the [result] reports the version actually used.
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

# Tests source this script for the pure pin/resolver logic without installing:
# AWSCLI_LIB_ONLY=1 stops here, after the helpers + per-major pins are defined.
[ "${AWSCLI_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

resolve_version

if [ "${AWSCLI_INSTALLTEST}" = "1" ]; then
  # --- test mode: disposable prefix, smoke `aws --version`, emit [result] ----
  prefix="$(mktemp -d)"
  if ! install_bundle "${prefix}/bin" "${prefix}/aws-cli"; then
    emit_result false "" "bundle install failed (glibc too old or fetch error)"
    rm -rf "${prefix}"; exit 0
  fi
  if ver="$("${prefix}/bin/aws" --version 2>&1)"; then
    iv="$(printf '%s' "${ver}" | sed -n 's#aws-cli/\([0-9.]*\).*#\1#p')"
    emit_result true "${iv:-unknown}" ""
  else
    emit_result false "" "installed but aws --version did not run"
  fi
  rm -rf "${prefix}"
  exit 0
fi

# --- production mode: install into the system default location ----------------
log "installing AWS CLI v2 (${AWSCLI_VERSION}) to /usr/local"
if install_bundle /usr/local/bin /usr/local/aws-cli; then
  /usr/local/bin/aws --version || true
  log "done"
else
  log "ERROR: AWS CLI v2 install failed"
  exit 1
fi
