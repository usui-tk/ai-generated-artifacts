# ----- Purpose --------------------------------------------------------------
#   Pure/mockable helpers for the entitlement fact-probe: per-major package-
#   manager syntax absorption (dnf vs yum), variable-tolerant repo-id matching,
#   product-certificate tag extraction, and the probe's step/JSON primitives.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; sourced library (no side effects at source time). openssl
#   only inside pc_product_tags/pc_product_id (I/O surface, mockable).
# ----- Usage examples -------------------------------------------------------
#   source lib/probe-common.sh   # from tests/probe-env.sh / t023
# ----- Known limitations ----------------------------------------------------
#   Not a standalone executable; callers own logging and error policy
#   (spec home A.5). Syntax maps cover RHEL 6-10 only.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r37: reproducible entitlement fact-probe)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
#==============================================================================
# lib/probe-common.sh - entitlement fact-probe helpers (L1 unit surface)
#
# Why this exists: the Phase A entitlement re-investigation must be
# REPRODUCIBLE - no one-off command lines. Every syntax decision that burned a
# prior session lives here as a pure, unit-tested function:
#   * yum (EL6/7) has no `repolist --enabled`; the subcommand form is
#     `repolist enabled` (a leading `--enabled` makes yum print its own
#     subcommand list instead of repos);
#   * repo files may hold LITERAL `$basearch` in section ids (ubi.repo) while
#     repolist prints the EXPANDED id - matching needs a variable-tolerant
#     pattern, not a verbatim grep;
#   * product-certificate tags (the selector the subscription-manager plugin
#     is HYPOTHESIZED to key repo generation on - Phase A verifies this) sit
#     behind OID 1.3.6.1.4.1.2312.9.1.<product>.4 as a DER UTF8String -
#     extracted via asn1parse (rct is absent in minimal images).
#==============================================================================

# pc_pm_for_major MAJOR - the package manager the major's baseline image ships.
pc_pm_for_major() {
  case "$1" in
    10|9|8) printf 'dnf\n' ;;
    7|6)    printf 'yum\n' ;;
    *)      return 1 ;;
  esac
}

# pc_repolist_cmd MAJOR SCOPE - the CORRECT repolist argv for the major.
# SCOPE = enabled|all. yum needs the subcommand form (no leading --enabled),
# and EL6's yum suppresses the WHOLE repolist table under -q (observed on the
# 2026-07-04 entitled run: s08 came back empty while repos were enabled), so
# the EL6 form drops -q and the analyzer filters the extra noise instead.
pc_repolist_cmd() {
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

# pc_repoid_pattern REPOID - grep -E pattern locating the [section] that
# defines an EXPANDED repo id inside .repo files whose section header may
# instead hold the LITERAL $basearch variable (ubi.repo style).
# NOTE the bracket-set ordering: `.` must not follow `[` (POSIX `[.` opens a
# collating symbol and breaks the expression).
pc_repoid_pattern() {
  local p
  # shellcheck disable=SC2016  # $basearch is a literal yum variable, not shell
  p="$(printf '%s' "$1" | sed -E \
        -e 's/[][\^$.*+?(){}|]/\\&/g' \
        -e 's/x86_64|aarch64|ppc64le|s390x/(&|\\$basearch)/g')"
  printf '^\\[%s\\]' "${p}"
}

# pc_product_tags PEM - the provided tags (e.g. "rhel-9,rhel-9-x86_64") from a
# product certificate: OID 1.3.6.1.4.1.2312.9.1.<id>.4 -> next OCTET STRING
# hex dump -> strip the inner DER UTF8String header (0x0C + 1 length byte) ->
# hex to ascii. rc 1 = no tag extension found.
pc_product_tags() {
  local hex
  hex="$(openssl asn1parse -in "$1" 2>/dev/null \
          | awk '/OBJECT.*2312\.9\.1\.[0-9]+\.4$/{grab=1;next} grab&&/OCTET STRING/{sub(/.*\[HEX DUMP\]:/,"");print;exit}')"
  [ -n "${hex}" ] || return 1
  # hex -> ascii without xxd (absent on minimal hosts): \xHH via printf %b
  printf '%b\n' "$(printf '%s' "${hex}" | cut -c5- | sed 's/../\\x&/g')"
}

# pc_product_id PEM - the numeric product id (e.g. 479) from the same OID arc.
pc_product_id() {
  openssl asn1parse -in "$1" 2>/dev/null \
    | sed -nE 's/.*OBJECT[[:space:]]*:1\.3\.6\.1\.4\.1\.2312\.9\.1\.([0-9]+)\.4$/\1/p' \
    | head -1 | grep .
}

# pc_step_verdict RC - classify a probe step's exit code for facts.tsv:
# ok (0) | timeout (124/137 from timeout(1)) | fail (other nonzero).
pc_step_verdict() {
  case "$1" in
    0)       printf 'ok\n' ;;
    124|137) printf 'timeout\n' ;;
    *)       printf 'fail\n' ;;
  esac
}

# pc_tsv_row DOMAIN MAJOR COND KEY VALUE - one facts.tsv row (tabs in VALUE
# are flattened so the 5-column shape is stable for the analyzer).
pc_tsv_row() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(printf '%s' "$5" | tr '\t\n' '  ')"
}

# pc_b64url - urlsafe base64 of stdin (RFC 4648 §5: + -> -, / -> _, padding
# kept), matching python's base64.urlsafe_b64encode used by the AWS RHUI
# amazon-id dnf plugin for the X-RHUI-ID / X-RHUI-SIGNATURE headers.
pc_b64url() { base64 -w0 | tr '+/' '-_'; }

# pc_rhui_major_url TEMPLATE MAJOR - synthesize another major's RHUI content
# URL from a host repo template: the /rhelN/ path segment, the literal
# $releasever and $basearch are all re-targeted. Pure (REGION substitution is
# the caller's job). Grounded on the AWS redhat-rhui.repo shape observed on
# 2026-07-04 (mirrorlist=.../content/dist/rhel10/rhui/$releasever/$basearch/...).
pc_rhui_major_url() {
  printf '%s\n' "$1" | sed -E \
    -e "s#/rhel[0-9]+/#/rhel$2/#" \
    -e "s#\\\$releasever#$2#g" \
    -e "s#\\\$basearch#x86_64#g"
}

# pc_build_pkgset / pc_install_pkgset - the fact-probe package sets, derived
# from the PROJECT PURPOSE (Q-BUILD: ENA-class driver builds need the kernel
# headers + toolchain; Q-INSTALL: the provisioning manifest + tool
# prerequisites). Single source of truth for the probe, analyzer and t023.
pc_build_pkgset()   { printf '%s\n' "kernel-devel gcc make elfutils-libelf-devel"; }
pc_install_pkgset() { printf '%s\n' "gawk unzip tar"; }

# pc_resolve_cmd MGR DEEP PKGS - the resolution-proof command per manager.
# DEEP=1 (D-A2 adjudicated): a REAL --downloadonly fetch into a scratch dir
# inside the container/rootfs (catches SSL/cert failures metadata-only checks
# miss). DEEP=0: transaction resolution only (--assumeno; rc is then
# informational - yum/dnf exit 1 on a declined transaction by design).
pc_resolve_cmd() {
  local mgr="$1" deep="$2" pkgs="$3"
  case "${mgr}:${deep}" in
    dnf:1) printf 'dnf -y install --downloadonly --destdir=/tmp/probe-dl %s\n' "${pkgs}" ;;
    yum:1) printf 'yum -y install --downloadonly --downloaddir=/tmp/probe-dl %s\n' "${pkgs}" ;;
    dnf:0) printf 'dnf --assumeno install %s\n' "${pkgs}" ;;
    yum:0) printf 'yum --assumeno install %s\n' "${pkgs}" ;;
    *)     return 1 ;;
  esac
}
