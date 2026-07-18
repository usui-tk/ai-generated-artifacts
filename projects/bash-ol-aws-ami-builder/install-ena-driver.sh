#!/usr/bin/env bash
#
# install-ena-driver.sh
#
# Build and install a pinned Amazon ENA Linux kernel driver, so an OL image/
# instance is AWS-optimized (Nitro v4+ / ENAv3 capable). It is SELF-CONTAINED:
# it sets up the repos (EPEL) and installs every build dependency itself (gcc,
# make, dkms, and the matching kernel-uek-devel headers), so it can be run two
# ways:
#   1. Standalone, directly on a stock OL6/OL7 EC2 instance, to iterate on and
#      validate the driver build before any end-to-end image build.
#   2. From oracle-linux-image-tools provisioning, via a hook the wrapper
#      (build-ol-aws-ami.sh, Phase 3) appends to cloud/aws/provision.sh. It runs
#      by default; the wrapper's --skip-ena-driver switch removes the hook to
#      produce a pure (unmodified) OL AMI.
#
# Why a pinned version (not "latest"):
#   The ENA driver is a kernel module; newer releases progressively assume newer
#   kernels/toolchains. We pin the newest release that BUILDS on each target OS:
#     - OL6 -> ena_linux_2.9.1  (newest that builds on OL6/UEK4; >= 2.2.9 so
#              ENAv3 capable. The buildable window on the updated UEK4 kernel
#              4.1.12-124.48.6.el6uek is roughly [2.8.6, 2.9.1], validated on a
#              real Nitro instance: below ~2.8.6 the driver's kcompat redefines
#              page_ref_count (Oracle backported it into UEK4 >= 124.43.1; the
#              driver's guard is conditional on UEK detection -- see "Target
#              kernel"); at
#              2.10.0 the driver gained the ECC build-time API autodetect, which
#              false-positives on this old kernel + EL6 gcc 4.4.7 and pulls in
#              newer-kernel symbols absent here (pci_dev_id, irq_update_affinity_
#              hint, ethtool_puts, netif_napi_add_config), so 2.10.0+ fail to
#              compile. 2.9.1 is the last pre-ECC release -> the ceiling.)
#     - OL7 -> ena_linux_2.17.2 (newest release supporting RHEL7; confirmed
#              building on UEK6 5.4.17-2136.338.4.2.el7uek in the 2026-07-11
#              container-matrix run; RHEL7 remains in the driver's
#              supported-distros list)
#     - OL8 -> amzn-drivers LATEST resolved at runtime. Target kernel is
#              UEKR7 (5.15) -- what real OL8.10 AMIs from this pipeline run --
#              which requires BOTH the gcc-toolset-11 PATH block and the UEK
#              detection retarget below (2.17.2 confirmed building in a
#              container FT, 2026-07-12). OL8/UEKR6 (5.4) needs neither.
#              PRODUCTION: build-ol-aws-ami.sh injects the self-build hook on
#              OL6-OL10 by default (ENA Express generation). Real AMI boot on
#              OL8 self-build is not yet E2E-verified (container compile +
#              DKMS-install proof only; the SSM-integration precedent).
#     - OL9  -> amzn-drivers LATEST resolved at runtime. Confirmed building
#                against UEKR8 (6.12) in the container matrix (2026-07-03),
#                incl. the gcc-toolset-14 PATH requirement. OL9's in-distro
#                ENA already ships LLQ, but has no exposed driver version
#                string (in-tree, not amzn-drivers-tagged). PRODUCTION, same
#                real-AMI-boot caveat as OL8.
#     - OL10 -> amzn-drivers LATEST resolved at runtime. Confirmed building
#                against UEKR8 in the container matrix (2026-07-03; OL10's
#                in-distro ena.ko moved to kernel-uek-modules-core as of
#                UEKR8, confirmed via kernel-uek.spec %changelog). PRODUCTION,
#                same real-AMI-boot caveat as OL8.
#   Override per run with ENA_DRIVER_VERSION (single pin) for evaluation -- this
#   is how tests/ena/run-ena-buildtest-matrix.sh drives ENA_BUILDTEST=1 across
#   the release list without editing this file per version.
#
# Target kernel:
#   Standalone on a running instance -> the LIVE kernel (its /lib/modules dir
#   exists). Under a libguestfs appliance (provisioning) `uname -r` is the
#   APPLIANCE kernel with no modules dir in the guest, so we fall back to the
#   highest UEK under /lib/modules. The build always targets a specific kernel
#   via `dkms ... -k <kver>`. If the stock kernel's kernel-uek-devel has been
#   pruned from the repos, we install the latest kernel-uek + matching headers
#   and retarget to it (a guaranteed buildable pair).
#   The amzn-drivers Makefile ALSO derives IS_UEK / ENA_KERNEL_SUBVERSION_* from
#   `uname -r`; under the appliance that is the non-UEK appliance kernel, which
#   mis-fires the kcompat.h page_ref_count guard against a backported UEK4 kernel
#   (>= 124.43.1). For OL6 we patch that detection to read BUILD_KERNEL (the
#   DKMS target) -- see patch_ena_uek_detection() below.
#
# DKMS:
#   The driver is installed via DKMS (REMAKE_INITRD/AUTOINSTALL) so it is rebuilt
#   automatically across kernel upgrades. DKMS comes from EPEL:
#     - OL7 -> Oracle-provided EPEL (ol7_developer_EPEL)
#     - OL6 -> Fedora EPEL 6 archive (Oracle does not provide EPEL 6)
#   If DKMS is unavailable, fall back to a plain `make` build + depmod.
#
# Source: amzn/amzn-drivers (kernel/linux/ena). Apache-2.0 build instructions
# adapted; this script is original.
#
set -euo pipefail

# ---- pinned versions (overridable) -----------------------------------------
ENA_VERSION_OL6="${ENA_VERSION_OL6:-2.9.1}"
ENA_VERSION_OL7="${ENA_VERSION_OL7:-2.17.2}"
# OL8/OL9/OL10 resolve to the amzn-drivers LATEST tag at runtime (see
# _ena_resolve_latest below) unless explicitly pinned here or via
# ENA_DRIVER_VERSION. Left empty by default = "resolve latest"; set a concrete
# x.y.z to pin (e.g. if tests/ena/run-ena-buildtest-matrix.sh identifies a
# buildable ceiling for one of these OSes, mirroring how OL6's [2.8.6, 2.9.1]
# window was established). In the AMI pipeline, build-ol-aws-ami.sh resolves
# latest HOST-SIDE ([OLAWS-ENA02]) and passes the concrete version in via
# ENA_DRIVER_VERSION, so the AMI identity and the built module always agree;
# the runtime resolution below is the standalone / container-test path.
ENA_VERSION_OL8="${ENA_VERSION_OL8:-}"
ENA_VERSION_OL9="${ENA_VERSION_OL9:-}"
ENA_VERSION_OL10="${ENA_VERSION_OL10:-}"
# Last-known-good fallback pin if _ena_resolve_latest cannot reach GitHub (no
# network / rate-limited) -- keeps OL8/9/10 buildable rather than hard-failing.
ENA_LATEST_FALLBACK_PIN="${ENA_LATEST_FALLBACK_PIN:-2.17.2}"
EPEL6_ARCHIVE_BASEURL="${EPEL6_ARCHIVE_BASEURL:-https://archives.fedoraproject.org/pub/archive/epel/6/x86_64/}"

# ---- execution-environment switch (default = production) -------------------
# ENA_BUILDTEST=1 selects the container compile-test environment (kernel-less;
# dkms build only -- no install/boot). Default 0 = the production path (VM-build
# provisioning, or a standalone live OL instance), unchanged. The test-mode
# branches are added incrementally; see SPEC A.7 / handoff B.1.9 Part 3.
ENA_BUILDTEST="${ENA_BUILDTEST:-0}"
# INSECURE_TLS=1 drops TLS peer verification for the test-mode network commands
# only (MITM dev proxy / EL6 NSS trust gaps). Default 0 = verification on.
# Production never reads this beyond the default; it is consulted only inside the
# ENA_BUILDTEST branches.
INSECURE_TLS="${INSECURE_TLS:-0}"

# Execution-environment segment, computed once from the switch and injected by
# every [ena-driver] emitter below, so output is tagged by environment WITHOUT
# changing call sites. Production (ENA_BUILDTEST=0) -> empty -> the historical
# tags are emitted unchanged; the container compile-test (=1) inserts a
# [buildtest] segment after the script tag. The environment segment is
# orthogonal to the message-kind segment ([stage]/[ERROR]).
_env_tag() { if [[ "${ENA_BUILDTEST}" == "1" ]]; then printf '[buildtest]'; fi; }
log() { echo "[ena-driver]$(_env_tag) $*"; }
# Greppable build-stage breadcrumb. Distinct from log() so the host wrapper (and
# a human reading a failed build) can pick out the phase boundaries. NOTE: the
# guest provisioning output is swallowed by virt-customize on a SUCCESSFUL build
# (see dump_build_diag) -- these breadcrumbs surface on the failure path (where
# they pin which sub-step broke) and in the preserved make.log context, not as a
# live host signal. Live host-side progress comes from the wrapper heartbeat.
stage() { echo "[ena-driver]$(_env_tag)[stage] $*"; }
die() {
  echo "[ena-driver]$(_env_tag)[ERROR] $*" >&2
  if [[ "${ENA_BUILDTEST}" == "1" ]]; then
    # structured fail result for the test harness (reason JSON-escaped). The exit
    # code (non-zero, below) agrees with status=fail. Test mode only.
    printf '[ena-driver][buildtest][result] {"status":"fail","osmajor":"%s","ena_version":"%s","kver":"%s","ena_express":"%s","reason":"%s"}\n' \
      "${osmajor:-}" "${ena_version:-}" "${kver:-}" \
      "$(ena_express_verdict "${ena_version:-}" 2>/dev/null || printf 'unknown')" \
      "$(printf '%s' "$*" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
  exit 1
}

# Resolve the amzn-drivers "latest" ENA tag via `git ls-remote --tags` -- the
# same ground-truth method tests/ena/list-ena-releases.sh uses (git protocol,
# not the GitHub REST API, which is unauthenticated-rate-limited on shared-IP
# CI runners / sandboxes -- see that script's header for the full rationale).
# Ensures `git` is present (installs it if missing; every target OS ships it in
# its base/AppStream repos, so this never needs EPEL). Verifies the resolved
# tag's source tarball is actually fetchable (a HEAD) before returning it, so a
# tag that exists but has no published archive yet is never selected. Echoes
# the concrete version (e.g. 2.17.0), or "" on any failure -- the caller then
# falls back to ENA_LATEST_FALLBACK_PIN rather than hard-failing the build.
_ena_resolve_latest() {
  local repo="https://github.com/amzn/amzn-drivers.git"
  if ! command -v git >/dev/null 2>&1; then
    (command -v dnf >/dev/null 2>&1 && dnf -y install git >/dev/null 2>&1) \
      || (command -v yum >/dev/null 2>&1 && yum -y install git >/dev/null 2>&1) \
      || true
  fi
  command -v git >/dev/null 2>&1 || return 0
  local ver
  ver="$(git ls-remote --tags "${repo}" 'ena_linux_*' 2>/dev/null \
           | sed -E 's#.*refs/tags/ena_linux_##; s/\^\{\}$//' \
           | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+$' \
           | sort -t. -k1,1n -k2,2n -k3,3n -u | tail -1)"
  [[ -n "${ver}" ]] || return 0
  if command -v curl >/dev/null 2>&1 && curl -fsIL --max-time 15 \
       "https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_${ver}.tar.gz" \
       >/dev/null 2>&1; then
    printf '%s' "${ver}"
  fi
}

# _ena_ver_ge <a> <b> : dotted version compare (a >= b). Support helper for
# ena_express_verdict below; the matrix/lister carry their own copies
# (reuse-by-copy, ADR 0003) -- tests/t021_enaexpress.sh guards against drift.
_ena_ver_ge() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# ena_express_verdict <version> : AWS ENA Express driver-version floor
# classification (ena-express.html: >= 2.2.9 full bandwidth, >= 2.8.0 ena_srd_*
# metrics). This is the project's SOURCE OF TRUTH copy; the lister and the
# matrix report duplicate it (reuse-by-copy) and tests/t021_enaexpress.sh keeps
# the copies identical. Pure function of the version only -- NOT an eligibility
# check: ENA Express itself is enabled via the AWS API EnaSrdEnabled
# ENI-attachment attribute and gated by instance type; meeting the floor is
# necessary, not sufficient (a build "ok" already carries the same caveat).
ena_express_verdict() {
  local v="${1:-}"
  [ -n "${v}" ] || { printf 'unknown'; return 0; }
  if _ena_ver_ge "${v}" "2.8.0"; then printf 'express-ready'; return 0; fi
  if _ena_ver_ge "${v}" "2.2.9"; then printf 'bandwidth-only'; return 0; fi
  printf 'not-ready'
}

# compiler error is captured in the parent build log. This matters because
# oracle-linux-image-tools (libguestfs virt-customize) only echoes a guest
# provisioning script's output to the host when the script FAILS; on success it
# is silent. Without this, a DKMS module-build failure leaves only the opaque
# "Bad return status for module build" line and an in-guest make.log path that
# the operator (or a downstream user filing a report) never gets to see. Emits
# `dkms status` and every make.log found under the module's DKMS tree, each line
# prefixed so it stays greppable. Best-effort: never the cause of a new failure.
dump_build_diag() {
  local ml pfx; pfx="[ena-driver]$(_env_tag)[ERROR]"
  echo "${pfx} ---- build diagnostics (ENA ${ena_version:-?}, kernel ${kver:-?}) ----" >&2
  if command -v dkms >/dev/null 2>&1; then
    echo "${pfx} dkms status:" >&2
    dkms status 2>&1 | sed "s/^/${pfx}   /" >&2 || true
  fi
  while IFS= read -r ml; do
    [[ -n "${ml}" ]] || continue
    echo "${pfx} ---- ${ml} ----" >&2
    sed "s/^/${pfx}   /" "${ml}" >&2 || true
  done < <(find "/var/lib/dkms/amzn-drivers/${ena_version:-}" -name 'make.log' 2>/dev/null || true)
  echo "${pfx} ---- end build diagnostics ----" >&2
}

# Verdict for the self-build verify: decide whether the requested ENA version was
# ACTUALLY built, from the versions of every ena.ko found under the module tree.
# This is the guard against a silent false success: `dkms build`/`dkms install`
# on the EL6 dkms (2.4.0) return exit 0 even when the in-guest compile FAILS, so
# `set -e` does not catch it; the kernel-uek package also ships a stock in-tree
# ena.ko (e.g. 1.1.2), so a naive "is any ena.ko present?" check passes on the
# stock module and reports success for a build that never produced the pinned
# version. The robust signal is therefore the installed MODULE VERSION, not the
# command exit code or mere file presence: the build succeeded iff some installed
# ena.ko reports the requested version (the pinned version is known-good in
# production and installs as e.g. `2.9.1g`, so a prefix match on the request is
# the success shape). Pure (args only) so it is unit-testable in isolation.
#   ena_buildtest_verdict <requested_version> [found_version ...]
# On success: prints the matching version and returns 0.
# On failure: prints a human/LLM-readable reason and returns 1.
ena_buildtest_verdict() {
  local want="$1"; shift
  local found="$*" v
  if [[ -z "${found// /}" ]]; then
    printf 'no ena.ko found under the module tree after install -- the dkms build produced no module'
    return 1
  fi
  for v in ${found}; do
    if [[ "${v}" == "${want}"* ]]; then printf '%s' "${v}"; return 0; fi
  done
  printf 'no installed ena.ko matches the requested ENA version %s (found only: %s) -- the dkms build did not produce a module matching the request (the installed module version, not the build exit status, is authoritative) and only the stock in-tree module remains' \
    "${want}" "${found}"
  return 1
}

# _ena_first_make_error : the FIRST compiler error line from the DKMS make.log
# (e.g. "implicit declaration of function 'from_timer'"), truncated to 200
# chars, or "" when no make.log / no error line exists. Ported from the RHEL
# sibling (r61): embedding the specific kernel-API error in the failure reason
# lets the matrix report's fail-pattern analysis group failures by ROOT CAUSE
# instead of a generic "build failed" message. Best-effort, read-only.
_ena_first_make_error() {
  local ml
  ml="$(find "/var/lib/dkms/amzn-drivers/${ena_version:-}" -name 'make.log' 2>/dev/null | head -1 || true)"
  [[ -n "${ml}" && -f "${ml}" ]] || return 0
  grep -m1 ' error:' "${ml}" 2>/dev/null | sed 's/^.*error: //' | head -c 200 || true
}

# On a SUCCESSFUL build the guest provisioning output is swallowed by
# virt-customize (see dump_build_diag), so the DKMS make.log -- the only record
# of what the compile actually did -- would be lost. Copy it to a stable path
# that ships inside the produced AMI, so it can be inspected post-hoc on a
# launched instance. Best-effort: never the cause of a new failure. (On a FAILED
# build, dump_build_diag already surfaces the same make.log to the host log.)
record_make_log() {
  local dest="/var/log/ol-aws-ami-builder-ena-make.log" ml
  ml="$(find "/var/lib/dkms/amzn-drivers/${ena_version:-}" -name 'make.log' 2>/dev/null | head -1 || true)"
  if [[ -n "${ml}" && -f "${ml}" ]]; then
    mkdir -p "$(dirname "${dest}")" 2>/dev/null || true
    if cp -f "${ml}" "${dest}" 2>/dev/null; then
      stage "preserved DKMS make.log -> ${dest} (ships in the AMI for post-hoc inspection)"
    else
      log "[make.log] could not copy ${ml} -> ${dest}"
    fi
  else
    log "[make.log] no DKMS make.log under /var/lib/dkms/amzn-drivers/${ena_version:-} (nothing to preserve)"
  fi
}

# Highest /lib/modules entry matching a shell glob (by version sort), or "".
highest_modules_dir() {
  local pattern="$1" best="" d bn
  for d in ${pattern}; do
    [[ -d "${d}" ]] || continue
    bn="$(basename "${d}")"
    if [[ -z "${best}" || "$(printf '%s\n%s\n' "${best}" "${bn}" | sort -V | tail -n1)" == "${bn}" ]]; then
      best="${bn}"
    fi
  done
  printf '%s' "${best}"
}

# ---- detect Oracle Linux major version -------------------------------------
osmajor=""
if [[ -r /etc/oracle-release ]]; then
  osmajor="$(grep -oE 'release [0-9]+' /etc/oracle-release 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
fi
if [[ -z "${osmajor}" && -r /etc/os-release ]]; then
  # /etc/os-release exists only at runtime on the target host; treat as empty
  # for the static lint (deterministic regardless of the lint host).
  # shellcheck source=/dev/null
  osmajor="$(. /etc/os-release 2>/dev/null; echo "${VERSION_ID%%.*}")"
fi
[[ -n "${osmajor}" ]] || die "cannot determine Oracle Linux major version"
log "Oracle Linux major version: ${osmajor}"

# ---- detect Oracle Linux minor (update) version -----------------------------
# Consumed only by the OL10 developer-EPEL discovery below (the self-minor
# candidate). Best-effort: empty when undeterminable, in which case only the
# shipped-repo-file candidates are considered.
osminor=""
if [[ -r /etc/oracle-release ]]; then
  osminor="$(grep -oE 'release [0-9]+\.[0-9]+' /etc/oracle-release 2>/dev/null | grep -oE '[0-9]+$' | head -1 || true)"
fi
if [[ -z "${osminor}" && -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  osminor="$(. /etc/os-release 2>/dev/null; v="${VERSION_ID#*.}"; if [[ "${v}" != "${VERSION_ID}" ]]; then echo "${v%%.*}"; fi)"
fi
[[ -n "${osminor}" ]] && log "Oracle Linux minor (update) version: ${osminor}"

case "${osmajor}" in
  6)  ena_version="${ENA_DRIVER_VERSION:-${ENA_VERSION_OL6}}" ;;
  7)  ena_version="${ENA_DRIVER_VERSION:-${ENA_VERSION_OL7}}" ;;
  8|9|10)
    if [[ -n "${ENA_DRIVER_VERSION:-}" ]]; then
      ena_version="${ENA_DRIVER_VERSION}"
    else
      case "${osmajor}" in
        8)  ena_version="${ENA_VERSION_OL8}" ;;
        9)  ena_version="${ENA_VERSION_OL9}" ;;
        10) ena_version="${ENA_VERSION_OL10}" ;;
      esac
      if [[ -z "${ena_version}" ]]; then
        stage "resolving amzn-drivers latest ENA tag for OL${osmajor}"
        ena_version="$(_ena_resolve_latest)"
        if [[ -z "${ena_version}" ]]; then
          log "could not resolve amzn-drivers latest tag (no network / rate-limited); falling back to ${ENA_LATEST_FALLBACK_PIN}"
          ena_version="${ENA_LATEST_FALLBACK_PIN}"
        else
          log "resolved amzn-drivers latest ENA tag: ${ena_version}"
        fi
      fi
    fi
    ;;
  *) log "OL${osmajor} ships a current in-distro ENA driver; no rebuild needed. Skipping."; exit 0 ;;
esac
log "Target ENA driver version: ${ena_version}"

# ---- OL10 developer-EPEL: discover -> verify (live repo + dkms) -> finalize -
# OL10's developer/EPEL repo is versioned per update release (baseurl
# .../OL10/<N>/developer/EPEL/..., section [ol10_u<N>_developer_EPEL]) and the
# shipped oracle-epel-ol10.repo can LAG the running minor -- measured
# 2026-07-16: oracle-epel-release-el10 1.0-2 shipped [ol10_u0_...] -> /OL10/0/,
# 1.0-5..1.0-6 (latest) ship [ol10_u1_...] -> /OL10/1/, and a 10.2 system still
# carries the u1 section because /OL10/2/developer/EPEL/ was not yet published
# (HTTP 404) -- or LEAD it once Oracle publishes u2 and ships the rename. A
# hard-coded section name therefore breaks SILENTLY on every OL10 update (the
# exact failure mode that produced "No match for argument: dkms" at the
# u0 -> u1 rename). OL10 ONLY: OL6-9 keep their proven fixed-name paths
# (unversioned EPEL paths; no churn) per the OS-isolation principle.
#
# Mechanism (user adjudications D1/D2/D3, 2026-07-16):
#   1. Candidates from BOTH sources: every [ol10(_u<N>)?_developer_EPEL]
#      section of the shipped repo file (best-effort installing
#      oracle-epel-release-el10 first when the file is absent), PLUS a
#      CONSTRUCTED .../OL10/<osminor>/... URL for the running minor even when
#      no shipped section mentions it (follows a lagging repo file forward).
#   2. Verify each candidate against the LIVE yum server through the same dnf
#      stack the install itself uses (core-dnf --repofrompath; no plugins):
#      the repo must be reachable AND must actually offer the dkms package --
#      repomd reachability alone is not sufficient (D1).
#   3. Select: the self-minor candidate first, else the highest verified u<N>
#      (an unversioned section ranks lowest).
#   4. Finalize: a live shipped section is enabled in place, and DEAD shipped
#      developer-EPEL sections are explicitly disabled so later transactions
#      cannot trip on an unreachable repo (D2); a constructed-only winner is
#      materialized as a DISPOSABLE repo file (marker header; gpgcheck=1 with
#      the Oracle key) which is removed right after the dkms provisioning
#      step (D2).
# Every candidate and its verdict is logged -- no silent no-match failures.
#
# AWS-scope assumption (documented in SPEC): the Oracle repo-file variables
# expand as $ociregion="" / $ocidomain="oracle.com" (the public yum server);
# OCI-internal mirror regions are out of scope for this AWS AMI pipeline.

OL10_EPEL_REPO_FILE="${OL10_EPEL_REPO_FILE:-/etc/yum.repos.d/oracle-epel-ol10.repo}"
OL10_EPEL_DISPOSABLE=""   # set when a disposable repo file is materialized

_ol10_epel_expand_url() {
  # Expand the Oracle repo-file baseurl variables for live probing.
  local url="$1"
  url="${url//\$ociregion/}"
  url="${url//\$ocidomain/oracle.com}"
  url="${url//\$basearch/$(uname -m)}"
  printf '%s' "${url}"
}

_ol10_epel_file_candidates() {
  # Emit "section<TAB>expanded-baseurl" for every developer-EPEL section in
  # the shipped repo file; emits nothing when the file is absent/unreadable.
  # Pure bash line parsing (no pipefail-exposed pipes).
  [[ -r "${OL10_EPEL_REPO_FILE}" ]] || return 0
  local sec="" line
  while IFS= read -r line; do
    if [[ "${line}" =~ ^\[(ol10(_u[0-9]+)?_developer_EPEL)\]$ ]]; then
      sec="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "${line}" =~ ^\[ ]] && sec=""
    if [[ -n "${sec}" && "${line}" =~ ^baseurl= ]]; then
      printf '%s\t%s\n' "${sec}" "$(_ol10_epel_expand_url "${line#baseurl=}")"
      sec=""
    fi
  done < "${OL10_EPEL_REPO_FILE}"
  return 0
}

_ol10_epel_probe() {
  # $1 = expanded baseurl. rc 0 iff the LIVE repo is reachable AND offers the
  # dkms package. Core-dnf only (`list`, --repofrompath -- no plugin commands)
  # so it rides the exact network stack (proxy/TLS) of the eventual install.
  # skip_if_unavailable=0 forces an error (not a silent skip) on a dead repo.
  local url="$1" out rc=0
  command -v dnf >/dev/null 2>&1 || return 1
  local -a df=(-q --disablerepo='*' "--repofrompath=olawsprobe,${url}"
               --enablerepo=olawsprobe --setopt=olawsprobe.gpgcheck=0
               --setopt=olawsprobe.skip_if_unavailable=0)
  if [[ "${ENA_BUILDTEST}" == "1" && "${INSECURE_TLS}" == "1" ]]; then
    df+=(--setopt=sslverify=false)
  fi
  out="$(dnf "${df[@]}" list available dkms 2>/dev/null)" || rc=1
  [[ ${rc} -eq 0 ]] || return 1
  grep -q '^dkms\.' <<<"${out}"
}

_ol10_epel_select() {
  # stdin:  "<section-name>\t<1|0>" per candidate (1 = verified live + dkms).
  # stdout: the selected section name. Selection order: the running minor's
  # own section first (D1), else the highest verified u<N> (an unversioned
  # ol10_developer_EPEL ranks below any versioned one). rc 1 when nothing
  # verified.
  # best_n starts at -2 so an unversioned section (rank -1) can still win as
  # the sole survivor (caught by the fixture FT, 2026-07-16).
  local name ok best="" best_n=-2 n
  while IFS=$'\t' read -r name ok; do
    [[ "${ok}" == "1" ]] || continue
    n=-1
    [[ "${name}" =~ ^ol10_u([0-9]+)_developer_EPEL$ ]] && n="${BASH_REMATCH[1]}"
    if [[ -n "${osminor:-}" && "${n}" == "${osminor}" ]]; then
      printf '%s' "${name}"
      return 0
    fi
    if (( n > best_n )); then best_n="${n}"; best="${name}"; fi
  done
  printf '%s' "${best}"
  [[ -n "${best}" ]]
}

_ol10_epel_set_enabled() {
  # $1 = section name, $2 = 0|1. Exact-span sed on the shipped repo file
  # (plugin-free; deterministic -- the section name came from this same file).
  local sec="$1" en="$2"
  [[ -w "${OL10_EPEL_REPO_FILE}" ]] || return 0
  if [[ "${en}" == "1" ]]; then
    sed -i "/^\[${sec}\]/,/^\[/ s/^enabled=0/enabled=1/" "${OL10_EPEL_REPO_FILE}"
  else
    sed -i "/^\[${sec}\]/,/^\[/ s/^enabled=1/enabled=0/" "${OL10_EPEL_REPO_FILE}"
  fi
}

setup_epel_ol10() {
  # Orchestrator: discover -> verify -> finalize. rc 0 leaves exactly one
  # verified, dkms-carrying developer-EPEL repo enabled (shipped section or
  # disposable file); rc 1 = no candidate verified (callers decide: production
  # degrades to the plain-make fallback, ENA_BUILDTEST dies).
  local pm="yum"
  command -v dnf >/dev/null 2>&1 && pm="dnf"
  if [[ ! -r "${OL10_EPEL_REPO_FILE}" ]]; then
    log "OL10 EPEL: ${OL10_EPEL_REPO_FILE} absent; best-effort installing oracle-epel-release-el10"
    "${pm}" install -y oracle-epel-release-el10 >/dev/null 2>&1 || true
  fi
  local -a cand_names=() cand_urls=() cand_origin=() cand_ok=()
  local sec url i
  while IFS=$'\t' read -r sec url; do
    [[ -n "${sec}" ]] || continue
    cand_names+=("${sec}"); cand_urls+=("${url}"); cand_origin+=("file")
  done < <(_ol10_epel_file_candidates)
  if [[ -n "${osminor:-}" ]]; then
    url="https://yum.oracle.com/repo/OracleLinux/OL10/${osminor}/developer/EPEL/$(uname -m)/"
    local have=0
    for i in "${!cand_urls[@]}"; do
      [[ "${cand_urls[$i]}" == "${url}" ]] && have=1
    done
    if [[ ${have} -eq 0 ]]; then
      cand_names+=("ol10_u${osminor}_developer_EPEL")
      cand_urls+=("${url}")
      cand_origin+=("constructed")
    fi
  fi
  if [[ ${#cand_names[@]} -eq 0 ]]; then
    log "OL10 EPEL: no candidates (repo file absent/empty AND minor undetectable) -- cannot locate a developer-EPEL repo"
    return 1
  fi
  local verdicts=""
  for i in "${!cand_names[@]}"; do
    if _ol10_epel_probe "${cand_urls[$i]}"; then
      cand_ok+=("1")
      log "OL10 EPEL: candidate ${cand_names[$i]} (${cand_origin[$i]}) ${cand_urls[$i]} -- LIVE, dkms available"
    else
      cand_ok+=("0")
      log "OL10 EPEL: candidate ${cand_names[$i]} (${cand_origin[$i]}) ${cand_urls[$i]} -- dead or no dkms"
    fi
    verdicts+="${cand_names[$i]}"$'\t'"${cand_ok[$i]}"$'\n'
  done
  local selected
  selected="$(_ol10_epel_select <<<"${verdicts}")" || {
    log "OL10 EPEL: NO candidate verified (all dead or missing dkms) -- diagnostics above"
    return 1
  }
  # D2: dead shipped sections are explicitly disabled either way.
  local sel_origin="" sel_url=""
  for i in "${!cand_names[@]}"; do
    if [[ "${cand_names[$i]}" == "${selected}" ]]; then
      sel_origin="${cand_origin[$i]}"; sel_url="${cand_urls[$i]}"
    fi
    if [[ "${cand_origin[$i]}" == "file" && "${cand_ok[$i]}" == "0" ]]; then
      _ol10_epel_set_enabled "${cand_names[$i]}" 0
      log "OL10 EPEL: disabled dead shipped section ${cand_names[$i]}"
    fi
  done
  if [[ "${sel_origin}" == "file" ]]; then
    _ol10_epel_set_enabled "${selected}" 1
    log "OL10 EPEL: selected shipped section ${selected} (enabled in ${OL10_EPEL_REPO_FILE})"
  else
    # Constructed-only winner: materialize a DISPOSABLE repo file (D2).
    # assert-all-then-write: the full content is composed before the single
    # write; the caller removes the file right after dkms provisioning.
    OL10_EPEL_DISPOSABLE="$(dirname "${OL10_EPEL_REPO_FILE}")/olaws-ol10-epel-disposable.repo"
    local content
    content="# DISPOSABLE -- generated by install-ena-driver.sh (OL10 developer-EPEL
# discovery: the shipped ${OL10_EPEL_REPO_FILE} carries no live developer-EPEL
# section for this system, so the verified self-minor repo is materialized
# here). Removed automatically right after the dkms provisioning step; safe
# to delete if ever found lingering.
[${selected}]
name=Oracle Linux 10 EPEL Packages for Development (olaws disposable)
baseurl=${sel_url}
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
"
    printf '%s' "${content}" > "${OL10_EPEL_DISPOSABLE}" \
      || { log "OL10 EPEL: failed to write ${OL10_EPEL_DISPOSABLE}"; OL10_EPEL_DISPOSABLE=""; return 1; }
    log "OL10 EPEL: selected constructed ${selected} -- materialized disposable ${OL10_EPEL_DISPOSABLE}"
  fi
  return 0
}

cleanup_ol10_epel_disposable() {
  [[ -n "${OL10_EPEL_DISPOSABLE}" && -e "${OL10_EPEL_DISPOSABLE}" ]] || return 0
  rm -f "${OL10_EPEL_DISPOSABLE}"
  log "OL10 EPEL: removed disposable repo file ${OL10_EPEL_DISPOSABLE}"
  OL10_EPEL_DISPOSABLE=""
}

# ---- ENA_BUILDTEST: provision a kernel into the disposable container -------
# A container is kernel-less (no running kernel, no /lib/modules tree), so the
# production kernel detection below cannot work. The test container is throwaway,
# so install a full kernel-uek + its headers up front: that creates
# /lib/modules/<kver>/ (+ the build symlink), after which the production path
# (kver detection, header check, dkms build/install, verify) runs unchanged.
# Plain test commands; sslverify is dropped only at INSECURE_TLS=1 (e.g. a MITM
# dev proxy). Production never enters this block.
if [[ "${ENA_BUILDTEST}" == "1" ]]; then
  log "provisioning kernel-uek + build deps into the container (disposable)"
  # Per-OS: enable the shipped (disabled) EPEL persistently so the production
  # setup_epel below finds it already enabled and early-returns (no second repo),
  # and select the UEK repo for kernel-uek. Plain test commands.
  case "${osmajor}" in
    6)
      sed -i '/^\[epel\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/epel.repo
      bt_uek_repo="ol6_UEKR4" ;;
    7)
      sed -i '/^\[ol7_developer_EPEL\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/oracle-epel-ol7.repo
      bt_uek_repo="ol7_UEKR6" ;;
    8)
      sed -i '/^\[ol8_developer_EPEL\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/oracle-epel-ol8.repo
      # OL8 slim ships dnf only; bootstrap the yum compat so the production yum
      # calls (here and below) resolve. A real OL8 VM already has it.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL8"
      else
        dnf -y install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL8"
      fi
      # OL8 ships two UEK tracks (verified against yum.oracle.com repomd.xml,
      # 2026-07-11): ol8_UEKR6 (5.4) and ol8_UEKR7 (5.15). UEKR7 is the target
      # here -- it is what real OL8.10 AMIs from this pipeline actually run
      # (boot-E2E evidence: 5.15.0-32x.el8uek on every booted/built guest),
      # so testing UEKR6 by default no longer informs the product. The old
      # hardcoded ol8_UEKR6 default meant the matrix validated a kernel the
      # AMIs do not ship (caught by the first real OL8 build vs matrix
      # divergence, 2026-07-11). Override with BT_UEK_REPO_OVERRIDE=ol8_UEKR6
      # only for a UEKR6-specific regression check.
      bt_uek_repo="${BT_UEK_REPO_OVERRIDE:-ol8_UEKR7}" ;;
    9)
      sed -i '/^\[ol9_developer_EPEL\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/oracle-epel-ol9.repo
      # Same dnf-only bootstrap as OL8; a real OL9 VM already has yum.
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL9"
      else
        dnf -y install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL9"
      fi
      # OL9 ships two UEK tracks in its default repo config (verified from a real
      # clean-core image's uek-ol9.repo): ol9_UEKR7 (5.15, enabled=1 by default)
      # and ol9_UEKR8 (6.12, enabled=0 by default). UEKR8 is the target here --
      # UEKR7 is the older/legacy track and there is no reason to keep testing
      # against it now that UEKR8 is available. Override with
      # BT_UEK_REPO_OVERRIDE=ol9_UEKR7 only if a UEKR7-specific regression check
      # is ever needed.
      bt_uek_repo="${BT_UEK_REPO_OVERRIDE:-ol9_UEKR8}" ;;
    10)
      # OL10's developer-EPEL section name is update-versioned and churns on
      # every OL10 point release (u0 -> u1 measured; u2 next) -- see the
      # discover/verify/finalize block above. The old hard-coded
      # [ol10_u1_developer_EPEL] sed matched nothing after any rename
      # (the silent "No match for argument: dkms" failure mode), so the
      # container path now runs the same live-verified discovery as
      # production. yum is bootstrapped first (clean-core ships dnf only).
      if [[ "${INSECURE_TLS}" == "1" ]]; then
        dnf -y --setopt=sslverify=false install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL10"
      else
        dnf -y install yum >/dev/null || die "ENA_BUILDTEST: failed to bootstrap yum on OL10"
      fi
      setup_epel_ol10 || die "ENA_BUILDTEST: no live OL10 developer-EPEL repo verified (all candidates dead or missing dkms; per-candidate verdicts logged above)"
      # OL10 only ships a UEKR8 (6.12) track today.
      bt_uek_repo="ol10_UEKR8" ;;
    *) die "ENA_BUILDTEST: OS major ${osmajor} not wired for the container test" ;;
  esac
  if [[ "${INSECURE_TLS}" == "1" ]]; then
    yum -y --setopt=sslverify=false --enablerepo="${bt_uek_repo}" \
      install kernel-uek kernel-uek-devel gcc make tar findutils dkms \
      || die "ENA_BUILDTEST: failed to provision kernel-uek + build deps"
  else
    yum -y --enablerepo="${bt_uek_repo}" \
      install kernel-uek kernel-uek-devel gcc make tar findutils dkms \
      || die "ENA_BUILDTEST: failed to provision kernel-uek + build deps"
  fi
fi

# ---- detect target kernel --------------------------------------------------
# Standalone on a running OL instance: target the LIVE kernel (its modules dir
# exists), so the freshly built module can be loaded/validated immediately.
# In oracle-linux-image-tools provisioning the script runs under a libguestfs
# appliance whose `uname -r` is NOT the guest's kernel and has no modules dir in
# the guest fs, so we fall back to the highest UEK under /lib/modules.
kver="${ENA_DRIVER_KVER:-}"
if [[ -z "${kver}" ]]; then
  runk="$(uname -r 2>/dev/null || true)"
  if [[ -n "${runk}" && -d "/lib/modules/${runk}/kernel" ]]; then
    kver="${runk}"
  fi
fi
if [[ -z "${kver}" ]]; then
  kver="$(highest_modules_dir '/lib/modules/*uek*/')"
fi
if [[ -z "${kver}" ]]; then
  kver="$(highest_modules_dir '/lib/modules/*/')"
fi
[[ -n "${kver}" ]] || die "cannot determine target kernel under /lib/modules"
[[ -d "/lib/modules/${kver}" ]] || die "kernel modules dir /lib/modules/${kver} not found"
log "Target kernel: ${kver}"

# ---- idempotency: skip if the pinned version is already installed ----------
existing_ko="$(find "/lib/modules/${kver}" -type f -name 'ena.ko*' 2>/dev/null | grep -E '/updates/|/extra/' | head -1 || true)"
if [[ -n "${existing_ko}" ]]; then
  cur="$(modinfo -F version "${existing_ko}" 2>/dev/null | head -1 || true)"
  if [[ -n "${cur}" && "${cur}" == "${ena_version}"* ]]; then
    log "ENA ${cur} already installed for ${kver}; nothing to do."
    exit 0
  fi
fi

# ---- kernel devel package (UEK vs RHCK) ------------------------------------
develpkg="kernel-uek-devel-${kver}"
if [[ "${kver}" != *uek* ]]; then
  develpkg="kernel-devel-${kver}"
fi

# ---- enable EPEL so dkms is installable ------------------------------------
setup_epel() {
  # The enabled-only early return is NOT taken on OL10: an enabled repo can
  # still be DEAD there (the shipped section ships enabled=1 but its
  # update-versioned URL can lag/lead what Oracle actually publishes), so
  # OL10 always runs the live discover/verify path (idempotent; a re-run
  # rides the dnf metadata cache).
  if [[ "${osmajor}" != "10" ]] && yum repolist enabled 2>/dev/null | grep -qiE 'epel'; then
    log "EPEL already enabled"
    return 0
  fi
  case "${osmajor}" in
    7)
      # Oracle-provided EPEL for OL7
      yum install -y oracle-epel-release-el7 2>/dev/null || true
      if command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --enable ol7_developer_EPEL >/dev/null 2>&1 || true
      fi
      ;;
    8)
      # Oracle-provided EPEL for OL8 (standalone self-build only; the AMI
      # pipeline does not build ENA on OL8).
      yum install -y oracle-epel-release-el8 2>/dev/null || true
      if command -v dnf >/dev/null 2>&1; then
        dnf config-manager --set-enabled ol8_developer_EPEL >/dev/null 2>&1 || true
      elif command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --enable ol8_developer_EPEL >/dev/null 2>&1 || true
      fi
      ;;
    9)
      # Section name confirmed from a real clean-core image's repo file:
      # OL9 -> /etc/yum.repos.d/oracle-epel-ol9.repo [ol9_developer_EPEL]
      # (unversioned path -- .../OL9/developer/EPEL/... -- no per-update
      # churn, unlike OL10). The repo file ships pre-configured (disabled) in
      # the base image, so enabling it directly is the primary path; the
      # oracle-epel-release package install is a best-effort fallback for
      # images that lack the file (never the cause of a new failure).
      if command -v dnf >/dev/null 2>&1; then
        dnf config-manager --set-enabled ol9_developer_EPEL >/dev/null 2>&1 || true
      elif command -v yum-config-manager >/dev/null 2>&1; then
        yum-config-manager --enable ol9_developer_EPEL >/dev/null 2>&1 || true
      fi
      yum install -y oracle-epel-release-el9 2>/dev/null || true
      ;;
    10)
      # OL10's developer-EPEL section is update-versioned and churns per
      # point release; route through the live-verified discovery (see the
      # discover/verify/finalize block above). A verification miss is loud
      # but non-fatal here: the caller's `yum install -y dkms` then fails
      # and the existing plain-make degradation takes over.
      setup_epel_ol10 \
        || log "OL10 EPEL: proceeding without a verified developer-EPEL repo; dkms install will likely fail and fall back to a plain make build"
      ;;
    6)
      # Oracle does NOT provide EPEL 6; point at the Fedora archive directly.
      cat > /etc/yum.repos.d/epel-archive.repo <<EOF
[epel-archive]
name=Extra Packages for Enterprise Linux 6 (archive)
baseurl=${EPEL6_ARCHIVE_BASEURL}
enabled=1
gpgcheck=0
EOF
      ;;
  esac
}

# ---- install build prerequisites -------------------------------------------
# Ensure kernel-uek-devel headers exist for the target kernel. The stock OL ISO
# ships an older kernel-uek whose -devel may have been pruned from the repos
# ("No package kernel-uek-devel-<ver> available"); yum does not fail on a missing
# package, so DKMS then aborts with "kernel headers ... cannot be found". We (1)
# enable the UEK repo and try the exact -devel; (2) if the headers still are not
# present, install the latest kernel-uek + matching -devel and retarget to it
# (always a matched, buildable pair). Self-contained: no external pre-setup.
ensure_kernel_devel() {
  local -a yk=(-y)
  case "${osmajor}" in
    6)  yk+=("--enablerepo=*UEKR4*") ;;
    7)  yk+=("--enablerepo=*UEKR6*") ;;
    # OL8 ships two UEK tracks (UEKR6 5.4 / UEKR7 5.15) and real OL8.10 AMIs
    # from this pipeline run UEKR7 -- enable BOTH so the exact -devel for a
    # UEKR7 target resolves without depending on the guest's own repo config
    # (the old UEKR6-only glob was a leftover of the pre-UEKR7 default; the
    # 2026-07-11 fidelity fix moved the matrix but missed this resolver).
    8)  yk+=("--enablerepo=*UEKR7*" "--enablerepo=*UEKR6*") ;;
    9)  yk+=("--enablerepo=*UEKR8*") ;;
    10) yk+=("--enablerepo=*UEKR8*") ;;
  esac
  yum "${yk[@]}" install "kernel-uek-devel-${kver}" 2>/dev/null || true
  if [[ -e "/lib/modules/${kver}/build" ]]; then
    return 0
  fi
  log "kernel-uek-devel for ${kver} not available; installing the latest kernel-uek + headers and retargeting"
  yum "${yk[@]}" install kernel-uek kernel-uek-devel 2>/dev/null \
    || yum "${yk[@]}" update kernel-uek kernel-uek-devel 2>/dev/null || true
  local newk; newk="$(highest_modules_dir '/lib/modules/*uek*/')"
  if [[ -n "${newk}" && "${newk}" != "${kver}" ]]; then
    log "retargeting kernel: ${kver} -> ${newk}"
    kver="${newk}"; develpkg="kernel-uek-devel-${kver}"
  fi
  yum "${yk[@]}" install "kernel-uek-devel-${kver}" 2>/dev/null || true
  [[ -e "/lib/modules/${kver}/build" ]]
}

stage "installing build prerequisites (gcc, make, kernel headers)"
log "Installing build prerequisites (gcc, make, kernel headers)"
yum install -y gcc make tar findutils || die "failed to install gcc/make/tar"
if [[ "${kver}" == *uek* ]]; then
  stage "resolving kernel-uek-devel headers for ${kver}"
  ensure_kernel_devel || die "could not obtain kernel-uek-devel headers for ${kver} (enable the UEK repo / update the kernel and retry)"
else
  yum install -y "${develpkg}" || die "failed to install ${develpkg}"
  [[ -e "/lib/modules/${kver}/build" ]] || die "kernel headers for ${kver} not present after install"
fi

# ---- OL9/UEKR8: match the kernel's build-time gcc -------------------------
# OL9's base OS gcc (11.5.0, baseos) is older than the compiler UEKR8's 6.12
# kernel was actually built with (14.2.1) -- confirmed by a real buildtest run:
# the mismatch aborts the DKMS build on an unrecognized flag
# (-fmin-function-alignment=16) before any driver-code issue is even reached.
# Oracle's kernel-uek-devel-<ver> package for UEKR8 ALREADY declares an RPM
# dependency on gcc-toolset-14 (confirmed via a real `yum install` transaction
# log: gcc-toolset-14-gcc 14.2.1-13.el9 pulled in automatically alongside
# kernel-uek-devel) -- so no separate gcc-toolset install is needed here, only
# putting it ahead of the base gcc on PATH for the rest of this script's build
# steps. Only OL9/UEKR8 (kver 6.x) hits this; OL9/UEKR7 (5.15) and OL10 (also
# 6.12, but its base gcc already matched in testing) are left untouched. The
# base /usr/bin/gcc symlink is never modified.
if [[ "${osmajor}" == "9" && "${kver}" == 6.*uek* && -x /opt/rh/gcc-toolset-14/root/usr/bin/gcc ]]; then
  export PATH="/opt/rh/gcc-toolset-14/root/usr/bin:${PATH}"
  log "OL9/UEKR8: using $(/opt/rh/gcc-toolset-14/root/usr/bin/gcc --version | head -1) (pulled in by kernel-uek-devel)"
fi

# ---- OL8/UEKR7: match the kernel's build-time gcc --------------------------
# Same failure mode as OL9/UEKR8 above, one toolset generation earlier. OL8's
# base OS gcc (8.5.0, appstream) is older than the compiler UEKR7's 5.15
# kernel was actually built with (11.5.0) -- confirmed by the first UEKR7 QA
# preflight (2026-07-11): the mismatch aborts the DKMS build on unrecognized
# flags (-ftrivial-auto-var-init=zero, -fzero-call-used-regs=used-gpr) before
# any driver-code issue is even reached; the preserved make.log states "The
# kernel was built by: gcc (GCC) 11.5.0". Oracle's kernel-uek-devel-<ver>
# package for UEKR7 ALREADY declares an RPM dependency on gcc-toolset-11
# (verified with `rpm -qR kernel-uek-devel-5.15.0-322.203.3.3.el8uek` in a
# container FT, 2026-07-12: Requires gcc-toolset-11 / -binutils / ...) -- so
# no separate gcc-toolset install is needed here, only putting it ahead of the
# base gcc on PATH for the rest of this script's build steps. Only OL8/UEKR7
# (kver 5.15.x) hits this; OL8/UEKR6 (5.4, built with the base gcc) is left
# untouched. The base /usr/bin/gcc symlink is never modified. With this block
# (plus the UEK detection retarget below) ENA 2.17.2 builds and DKMS-installs
# as 2.17.2g against 5.15.0-322.203.3.3.el8uek (container FT, 2026-07-12).
if [[ "${osmajor}" == "8" && "${kver}" == 5.15.*uek* && -x /opt/rh/gcc-toolset-11/root/usr/bin/gcc ]]; then
  export PATH="/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}"
  log "OL8/UEKR7: using $(/opt/rh/gcc-toolset-11/root/usr/bin/gcc --version | head -1) (pulled in by kernel-uek-devel)"
fi

use_dkms=1
stage "enabling EPEL + installing dkms"
setup_epel
if ! yum install -y dkms; then
  log "DKMS not installable; falling back to a plain make build (no auto-rebuild on kernel upgrade)"
  use_dkms=0
fi
# The OL10 disposable EPEL repo (when materialized) has served its purpose
# once the dkms provisioning step above completes -- remove it now regardless
# of the install outcome (D2: the repo configuration is throwaway). DKMS
# kernel-upgrade rebuilds need the already-installed toolchain, not the repo.
cleanup_ol10_epel_disposable

# ---- fetch the pinned amzn-drivers source tarball --------------------------
src_tgz="/usr/src/ena_linux_${ena_version}.tar.gz"
src_dir="/usr/src/amzn-drivers-${ena_version}"
url="https://github.com/amzn/amzn-drivers/archive/refs/tags/ena_linux_${ena_version}.tar.gz"
stage "downloading amzn-drivers ${ena_version} source"
log "Downloading ${url}"
rm -rf "${src_dir}"
if command -v curl >/dev/null 2>&1; then
  if [[ "${ENA_BUILDTEST}" == "1" && "${INSECURE_TLS}" == "1" ]]; then
    curl -fsSL -k "${url}" -o "${src_tgz}" || die "download failed: ${url}"
  else
    curl -fsSL "${url}" -o "${src_tgz}" || die "download failed: ${url}"
  fi
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "${src_tgz}" "${url}" || die "download failed: ${url}"
else
  die "neither curl nor wget is available to download the driver source"
fi
tar -xzf "${src_tgz}" -C /usr/src || die "failed to extract ${src_tgz}"
rm -f "${src_tgz}"
[[ -d "/usr/src/amzn-drivers-ena_linux_${ena_version}" ]] \
  || die "unexpected archive layout for ena_linux_${ena_version}"
mv "/usr/src/amzn-drivers-ena_linux_${ena_version}" "${src_dir}"

# ---- retarget the amzn-drivers Makefile's UEK detection (OL6/OL8 cross-kernel)
# The ENA Makefile derives IS_UEK and ENA_KERNEL_SUBVERSION_* from `uname -r`
# (the RUNNING kernel). Under the libguestfs provisioning appliance -- and in
# the container matrix's chroot -- `uname -r` is the non-UEK host/appliance
# kernel, not the DKMS target, so neither macro is set and every UEK-gated
# kcompat.h guard evaluates as "not UEK". Two guards are known to break the
# build when that happens:
#   - OL6/UEK4: the page_ref_count guard redefines a symbol the backported
#     UEK4 kernel (>= 4.1.12-124.43.1, e.g. -124.48.6) already provides
#     -> "redefinition of 'page_ref_count'".
#   - OL8/UEKR7: the bpf_warn_invalid_xdp_action guard collapses the call to
#     the pre-5.17 1-arg form, but UEKR7 5.15 backports the 3-arg mainline
#     signature; upstream kcompat.h explicitly excludes the macro for
#     IS_UEK >= 5.15.0-100.96.32 -- an exclusion that can only fire when
#     IS_UEK is set -> "passing argument 1 ... makes pointer from integer"
#     (reproduced and fix-verified in a container FT, 2026-07-12).
# The build already passes the target kernel as BUILD_KERNEL, so point the
# detection at it instead. OL6|OL8 only (per-OS isolation): OL7/UEK6 builds
# 2.17.2 fine with IS_UEK unset (2026-07-11 matrix run -- the page_ref_count
# block is compiled out on >= 4.6 kernels and the bpf guard's 1-arg collapse
# matches UEK6's un-backported 5.4 signature); OL9/OL10 UEKR8 (6.12 >= 5.17)
# version-exclude the bpf guard regardless of IS_UEK. Their Makefiles are
# left untouched.
patch_ena_uek_detection() {
  local mk="${src_dir}/kernel/linux/ena/Makefile" S='$' sentinel
  sentinel="echo \"${S}(BUILD_KERNEL)\" | grep uek"
  [[ -f "${mk}" ]] || die "amzn-drivers Makefile not found at ${mk}"
  if grep -Fq "${sentinel}" "${mk}"; then
    log "[ena-uek-detect] Makefile UEK detection already retargeted to BUILD_KERNEL; skipping"
    return 0
  fi
  cp -f "${mk}" "${mk}.uek-detect.bak"
  # Read the DKMS target kernel (BUILD_KERNEL), not the running kernel. The
  # `BUILD_KERNEL ?= $(shell uname -r)` default line carries no pipe, so the
  # two pipe-anchored substitutions below leave it untouched.
  sed -i \
    -e "s#uname -r | grep uek#echo \"${S}(BUILD_KERNEL)\" | grep uek#" \
    -e "s#uname -r | sed#echo \"${S}(BUILD_KERNEL)\" | sed#" \
    "${mk}"
  grep -Fq "${sentinel}" "${mk}" \
    || die "[ena-uek-detect] Makefile UEK-detection patch did not apply (upstream layout changed?)"
  log "[ena-uek-detect] retargeted ENA Makefile UEK detection to the DKMS target kernel (backup ${mk}.uek-detect.bak)"
}
if [[ "${osmajor}" == "6" || "${osmajor}" == "8" ]]; then
  patch_ena_uek_detection
fi

# ---- report the in-box ENA driver BEFORE the self-build replaces it --------
# The self-build is otherwise silent about what it supersedes. Capture the stock
# in-tree ENA module's identity for the TARGET kernel now, so the before/after
# delta is on record. modinfo's `version` field is frequently empty for an
# in-tree module (e.g. OL7/OL8); fall back to srcversion and always show the
# module file so the line is never uninformative.
report_inbox_ena() {
  command -v modinfo >/dev/null 2>&1 || { log "[in-box ENA] modinfo unavailable; skipping pre-build report"; return 0; }
  local ver src fn
  # '|| true' is LOAD-BEARING (matches every other such pipeline in this file):
  # when the target kernel has NO in-box ena module (observed on a fresh OL8
  # UEK7 guest before kernel-uek-modules lands), modinfo exits non-zero and,
  # under this script's set -euo pipefail, an unguarded substitution kills the
  # WHOLE install silently -- the first real OL8 AMI build (2026-07-11) died
  # exactly here, between the "Building & installing" log line and dkms add,
  # with /usr/src staged and /var/lib/dkms untouched. This function is purely
  # informational and must never be able to abort a build.
  ver="$(modinfo -k "${kver}" -F version ena 2>/dev/null | head -1 || true)"
  src="$(modinfo -k "${kver}" -F srcversion ena 2>/dev/null | head -1 || true)"
  fn="$(modinfo -k "${kver}" -F filename ena 2>/dev/null | head -1 || true)"
  log "[in-box ENA] before self-build: version=${ver:-<none; in-tree, no version field>} srcversion=${src:-?} file=${fn:-<not found>}"
}

# ---- build & install --------------------------------------------------------
build_install_dkms() {
  cat > "${src_dir}/dkms.conf" <<EOF
PACKAGE_NAME="ena"
PACKAGE_VERSION="${ena_version}"
CLEAN="make -C kernel/linux/ena clean"
MAKE="make -C kernel/linux/ena/ BUILD_KERNEL=\${kernelver}"
BUILT_MODULE_NAME[0]="ena"
BUILT_MODULE_LOCATION="kernel/linux/ena"
DEST_MODULE_LOCATION[0]="/updates"
DEST_MODULE_NAME[0]="ena"
REMAKE_INITRD="yes"
AUTOINSTALL="yes"
EOF
  dkms remove  -m amzn-drivers -v "${ena_version}" --all 2>/dev/null || true
  stage "dkms add (amzn-drivers ${ena_version})"
  dkms add     -m amzn-drivers -v "${ena_version}"
  stage "dkms build for ${kver} -- long, quiet in-guest compile (typically a few minutes)"
  dkms build   -m amzn-drivers -v "${ena_version}" -k "${kver}"
  stage "dkms install for ${kver}"
  dkms install -m amzn-drivers -v "${ena_version}" -k "${kver}" --force
  stage "dkms build + install complete for ${kver}"
}

build_install_plain() {
  make -C "${src_dir}/kernel/linux/ena" BUILD_KERNEL="${kver}"
  local dest="/lib/modules/${kver}/updates"
  mkdir -p "${dest}"
  cp -f "${src_dir}/kernel/linux/ena/ena.ko" "${dest}/ena.ko"
  depmod -a "${kver}"
}

if [[ "${use_dkms}" -eq 1 ]]; then
  log "Building & installing ENA ${ena_version} via DKMS for ${kver}"
  report_inbox_ena
  build_install_dkms || { dump_build_diag; _e="$(_ena_first_make_error)"; die "DKMS build/install failed (${_e:-compiler output dumped above; in-guest make.log})"; }
  record_make_log
else
  log "Building & installing ENA ${ena_version} via plain make for ${kver}"
  report_inbox_ena
  build_install_plain || { dump_build_diag; die "plain make build/install failed (build output above)"; }
fi

# ---- regenerate initramfs for the target kernel ----------------------------
if command -v dracut >/dev/null 2>&1; then
  log "Regenerating initramfs for ${kver}"
  dracut -f "/boot/initramfs-${kver}.img" "${kver}" || die "dracut failed for ${kver}"
elif command -v mkinitrd >/dev/null 2>&1; then
  log "Regenerating initrd for ${kver}"
  mkinitrd -f "/boot/initramfs-${kver}.img" "${kver}" || die "mkinitrd failed for ${kver}"
else
  log "WARNING: no dracut/mkinitrd found; initramfs not regenerated"
fi

# ---- verify -----------------------------------------------------------------
# Trust the installed MODULE VERSION, not the dkms exit code (EL6 dkms returns 0
# even on a failed compile) or mere file presence (kernel-uek ships a stock
# in-tree ena.ko). Walk every ena.ko under the tree, record their versions, and
# take the one whose version matches the request as the self-built result;
# ena_buildtest_verdict turns "no match" / "none found" into a FATAL error so a
# masked build failure can never be reported as success (in the matrix OR in a
# production AMI build).
ko=""; newver=""; _found_vers=""
while IFS= read -r _k; do
  [[ -n "${_k}" ]] || continue
  _v="$(modinfo -F version "${_k}" 2>/dev/null | head -1 || true)"
  [[ -n "${_v}" ]] && _found_vers="${_found_vers} ${_v}"
  if [[ -z "${ko}" && "${_v}" == "${ena_version}"* ]]; then ko="${_k}"; newver="${_v}"; fi
done < <(find "/lib/modules/${kver}" -type f -name 'ena.ko*' 2>/dev/null)
if [[ -z "${ko}" ]]; then
  dump_build_diag
  # The verdict names the mismatch; the make.log first error (when present)
  # names the ROOT CAUSE the dkms exit code masked (EL6 dkms exits 0 on a
  # failed compile) -- both travel in the recorded reason (r61 port).
  _e="$(_ena_first_make_error)"
  # Intentional word-splitting of the space-separated version list into args.
  # shellcheck disable=SC2086
  _verdict="$(ena_buildtest_verdict "${ena_version}" ${_found_vers})" || true
  if [[ -n "${_e}" ]]; then
    die "${_verdict} [make.log first error: ${_e}]"
  else
    die "${_verdict}"
  fi
fi
log "Installed ENA driver: ${ko} (version ${newver})"
log "ENA Express readiness (driver-version floor only): $(ena_express_verdict "${newver%%g*}") -- ENA Express itself is an ENI attribute (AWS API EnaSrdEnabled), not a guest OS setting"

# ---- AMI hygiene: drop stale persistent-net rules --------------------------
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true

log "ENA driver build complete (OL${osmajor}, kernel ${kver}, version ${ena_version})"

# ENA_BUILDTEST: structured success result for the test harness. Single-line JSON
# tagged [ena-driver][buildtest][result]; the exit code (0) agrees with
# status=ok. Carries the {OS x ena_linux x kernel} facts a build ledger needs.
# Test mode only; production emits nothing here.
if [[ "${ENA_BUILDTEST}" == "1" ]]; then
  printf '[ena-driver][buildtest][result] {"status":"ok","osmajor":"%s","ena_version":"%s","kver":"%s","dkms":%s,"ko":"%s","ko_version":"%s","ena_express":"%s"}\n' \
    "${osmajor}" "${ena_version}" "${kver}" "${use_dkms}" "${ko}" "${newver}" \
    "$(ena_express_verdict "${ena_version}")"
fi
