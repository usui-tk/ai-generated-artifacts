# shellcheck shell=bash
#==============================================================================
# lib/os-profile.sh - the canonical per-RHEL-major OS profile (Phase 6).
#
# One queryable source of truth for the EOL/constrained-major facts the design
# plan measured (sec 3.2, 3.5, 6, 12.1): tier, baseline image, package manager,
# image-pull constraint, anonymous/entitled repos, lifecycle, EPEL status, and
# the entitled kernel-devel repo. The per-tool matrices and the acquisition
# libraries carry their own copies of individual facts (acq_image_for_major,
# acq_tag_for_major, epel_is_archive, ena_kdevel_repo); tests/t012_osprofile.sh
# asserts this module AGREES with each of them, so the scattered maps cannot
# drift from this canon.
#
# Pure and sourceable (no shebang, no I/O). Every helper takes a RHEL major and
# echoes a single token; an unknown major echoes 'unknown' and returns non-zero,
# EXCEPT the boolean-style predicates which return 2 for unknown.
#
# Tiers (sec 6):
#   A - current     : 10 / 9 / 8  (ubi-init; floating tag; dnf; ubi-* anon repos)
#   B - settled     : 7           (ubi7/ubi-init FIXED TAG; yum; anon incl RHSCL)
#   C - constrained : 6           (rhel6/rhel non-UBI; NO anon repo; EPEL archive-only)
#==============================================================================

# osp_known <major> : rc 0 if a supported major, else rc 1.
osp_known() {
  case "${1:-}" in 6|7|8|9|10) return 0 ;; *) return 1 ;; esac
}

# osp_tier <major> : A | B | C
osp_tier() {
  case "${1:-}" in
    10|9|8) printf 'A' ;;
    7)      printf 'B' ;;
    6)      printf 'C' ;;
    *)      printf 'unknown'; return 1 ;;
  esac
}

# osp_image <major> : baseline image (MUST match acq_image_for_major).
osp_image() {
  case "${1:-}" in
    10) printf 'ubi10/ubi-init' ;;
    9)  printf 'ubi9/ubi-init' ;;
    8)  printf 'ubi8/ubi-init' ;;
    7)  printf 'ubi7/ubi-init' ;;
    6)  printf 'rhel6/rhel' ;;
    *)  printf 'unknown'; return 1 ;;
  esac
}

# osp_pkgmgr <major> : the static default package manager (dnf | yum).
osp_pkgmgr() {
  case "${1:-}" in
    10|9|8) printf 'dnf' ;;
    7|6)    printf 'yum' ;;
    *)      printf 'unknown'; return 1 ;;
  esac
}

# osp_pull_tag <major> : the tag the image must be pulled by (MUST match
# acq_tag_for_major). RHEL 7 ubi-init's FLOATING tag signature is rejected by the
# host policy (sec 3.5) -> fixed tag 7.9-88; the others pull by 'latest'.
osp_pull_tag() {
  case "${1:-}" in
    7)        printf '7.9-88' ;;
    10|9|8|6) printf 'latest' ;;
    *)        printf 'unknown'; return 1 ;;
  esac
}

# osp_pull_constraint <major> : fixed-tag (7, signature) | floating-ok (others).
osp_pull_constraint() {
  case "${1:-}" in
    7)        printf 'fixed-tag' ;;
    10|9|8|6) printf 'floating-ok' ;;
    *)        printf 'unknown'; return 1 ;;
  esac
}

# osp_anon_repos <major> : ubi (10/9/8) | yum-anon (7) | none (6, base image only).
osp_anon_repos() {
  case "${1:-}" in
    10|9|8) printf 'ubi' ;;
    7)      printf 'yum-anon' ;;
    6)      printf 'none' ;;
    *)      printf 'unknown'; return 1 ;;
  esac
}

# osp_has_anon_repo <major> : rc 0 if an anonymous repo exists, rc 1 if not (6),
# rc 2 if unknown. The decisive Tier-C property (sec 6).
osp_has_anon_repo() {
  case "${1:-}" in
    10|9|8|7) return 0 ;;
    6)        return 1 ;;
    *)        return 2 ;;
  esac
}

# osp_entitled_repo <major> : the entitled repo family carrying kernel/kernel-devel.
osp_entitled_repo() {
  case "${1:-}" in
    10) printf 'rhel-10-for-x86_64' ;;
    9)  printf 'rhel-9-for-x86_64' ;;
    8)  printf 'rhel-8-for-x86_64' ;;
    7)  printf 'rhel-7-server-rpms' ;;
    6)  printf 'rhel-6-server-rpms' ;;
    *)  printf 'unknown'; return 1 ;;
  esac
}

# osp_kdevel_repo <major> : the repo providing kernel-devel WHEN ENTITLED (sec 3.3).
# MUST match aws_ena-driver's ena_kdevel_repo. kernel-devel is obtainable in EVERY
# major when entitled - so this is never 'none'.
osp_kdevel_repo() {
  case "${1:-}" in
    10|9) printf 'appstream' ;;
    8)    printf 'baseos' ;;
    7|6)  printf 'server' ;;
    *)    printf 'unknown'; return 1 ;;
  esac
}

# osp_lifecycle <major> : current (10/9/8) | frozen (7) | eol-constrained (6).
osp_lifecycle() {
  case "${1:-}" in
    10|9|8) printf 'current' ;;
    7)      printf 'frozen' ;;
    6)      printf 'eol-constrained' ;;
    *)      printf 'unknown'; return 1 ;;
  esac
}

# osp_epel_status <major> : current (8/9) | current-minor (10, minor-branched) |
# archive (7, EOL archive tree) | archive-only (6, special-cased, not a live cap).
osp_epel_status() {
  case "${1:-}" in
    9|8) printf 'current' ;;
    10)  printf 'current-minor' ;;
    7)   printf 'archive' ;;
    6)   printf 'archive-only' ;;
    *)   printf 'unknown'; return 1 ;;
  esac
}

# osp_epel_is_live <major> : rc 0 if EPEL is a live capability (8/9/10), rc 1 if
# archive/EOL (6/7 - not a live capability), rc 2 if unknown. RHEL 6 is the
# OL6-style special case (archive-only); 7 is archive (EOL) too.
osp_epel_is_live() {
  case "${1:-}" in
    10|9|8) return 0 ;;
    7|6)    return 1 ;;
    *)      return 2 ;;
  esac
}
