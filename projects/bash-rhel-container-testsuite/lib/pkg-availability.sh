# ----- Purpose --------------------------------------------------------------
#   Classify package availability per (major, entitlement): anonymous-UBI /
#   entitled-only / EPEL / vendor-hosted, per SPEC section 8.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; sourced library (no side effects at source time).
# ----- Usage examples -------------------------------------------------------
#   source lib/pkg-availability.sh   # from a matrix runner / probe / test tier
# ----- Known limitations ----------------------------------------------------
#   Not a standalone executable; functions assume the caller handles logging
#   and error policy (spec home A.5).
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
# shellcheck shell=bash
#==============================================================================
# lib/pkg-availability.sh - the package-availability classification (Phase 7).
#
# The design plan sec 12 classifies every repo-installed or vendor-hosted input
# by WHERE it comes from and WHETHER entitlement is required. This module is the
# canonical, pure encoding of that taxonomy, so a new tool (tool #2) declares its
# acquisition source and the suite immediately knows the entitlement story.
#
# Classes:
#   anonymous-ubi  - the ubi-* repos (RHEL 7 also optional/extras/RHSCL); anywhere
#   entitled-only  - rhel-* repos (kernel, kernel-devel); entitled mode only
#   epel           - Fedora EPEL (e.g. dkms); out of base, pinned, OFF by default
#   vendor-hosted  - outside any repo (AWS CLI bundle, SSM S3 RPM); over the vendor CDN
#   base-image     - already in the base image (no repo needed)
#
# Pure and sourceable (no shebang, no I/O). tests/t014_pkgavail.sh covers it.
#==============================================================================

# pkgavail_class <source-token> : map a known acquisition source to its class.
pkgavail_class() {
  case "${1:-}" in
    ubi-baseos|ubi-appstream|ubi-codeready|ubi-optional|ubi-extras|rhscl)
                              printf 'anonymous-ubi' ;;
    kernel|kernel-devel|rhel-server|rhel-baseos|rhel-appstream)
                              printf 'entitled-only' ;;
    dkms|epel)                printf 'epel' ;;
    awscli-bundle|ssm-s3-rpm) printf 'vendor-hosted' ;;
    base-image|glibc|coreutils)
                              printf 'base-image' ;;
    *)                        printf 'unknown'; return 1 ;;
  esac
}

# pkgavail_known <class> : rc 0 if a recognised class, else rc 1.
pkgavail_known() {
  case "${1:-}" in
    anonymous-ubi|entitled-only|epel|vendor-hosted|base-image) return 0 ;;
    *) return 1 ;;
  esac
}

# pkgavail_needs_entitlement <class> : rc 0 (true) iff the class requires
# entitlement (entitled-only). All other classes are reachable anonymously.
pkgavail_needs_entitlement() {
  case "${1:-}" in
    entitled-only) return 0 ;;
    anonymous-ubi|epel|vendor-hosted|base-image) return 1 ;;
    *) return 2 ;;
  esac
}

# pkgavail_anonymous_status <class> : the status a tool with this primary input
# records when run ANONYMOUSLY.
#   entitled-only -> needs-entitlement   (cannot install without entitlement)
#   epel          -> epel-optional       (off by default; opt-in pinned repo)
#   else          -> installable         (anonymous-ubi / vendor-hosted / base-image)
pkgavail_anonymous_status() {
  case "${1:-}" in
    entitled-only) printf 'needs-entitlement' ;;
    epel)          printf 'epel-optional' ;;
    anonymous-ubi|vendor-hosted|base-image) printf 'installable' ;;
    *)             printf 'unknown'; return 1 ;;
  esac
}

# pkgavail_over_network <class> : where the bytes come from (for allow-list / CI).
#   anonymous-ubi/entitled-only -> registry.access.redhat.com (the repos)
#   epel                        -> dl.fedoraproject.org (pinned)
#   vendor-hosted               -> *.amazonaws.com
#   base-image                  -> none (already present)
pkgavail_over_network() {
  case "${1:-}" in
    anonymous-ubi|entitled-only) printf 'registry.access.redhat.com' ;;
    epel)                        printf 'dl.fedoraproject.org' ;;
    vendor-hosted)               printf 'vendor-cdn' ;;
    base-image)                  printf 'none' ;;
    *)                           printf 'unknown'; return 1 ;;
  esac
}

# pkgavail_tool_source <vendor_tool> : the primary acquisition source token of a
# known tool (feed to pkgavail_class). The contract: every tool declares one.
pkgavail_tool_source() {
  case "${1:-}" in
    aws_awscli-v2) printf 'awscli-bundle' ;;
    aws_ssm-agent) printf 'ssm-s3-rpm' ;;
    aws_ena-driver) printf 'kernel-devel' ;;
    *)             printf 'unknown'; return 1 ;;
  esac
}
