#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Phase A analyzer: rebuild the F1-F7 fact tables from a probe --facts
#   output directory - deterministically, from the collected artifacts ONLY
#   (no live system access), so any analysis is reproducible from the run.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+. Input: an ENTITLEMENT-PROBE-* dir from tests/probe-env.sh --facts.
# ----- Usage examples -------------------------------------------------------
#   bash tools/analyze-entitlement.sh tests/ENTITLEMENT-PROBE-<ts>
# ----- Known limitations ----------------------------------------------------
#   Transaction-table parsing (F4/F6 package->repo) is best-effort across
#   yum/dnf formats; the raw s10/s11 logs stay the ground truth.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-04 (r37: reproducible entitlement fact-probe)
# ---------------------------------------------------------------------------
#==============================================================================
# tools/analyze-entitlement.sh - render ANALYSIS.md from probe artifacts
#
# Sections map 1:1 to the Phase A fact list: F1 enabled repos + defining file,
# F2 injection/generation evidence (secrets, redhat.repo pre/post, product
# tags), F3 auto-vs-mounts delta, F4/F6 package->repo resolution, F5 CRB,
# F7 the EL6 rows. Writes OUTDIR/ANALYSIS.md and echoes it.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=../lib/probe-common.sh
. "${PROJ}/lib/probe-common.sh"

OUT="${1:-}"
[ -d "${OUT}" ] || { echo "usage: analyze-entitlement.sh <probe-output-dir>" >&2; exit 2; }
MD="${OUT}/ANALYSIS.md"

# an_repolist_ids MAJOR FILE - repo ids out of a repolist capture, per-manager:
# dnf (-q) prints "id name" (no counts); yum (-q ... enabled) prints
# "id name status" where status is a numeric count - and, because the raw log
# merges stderr, mirror-error noise lines must be excluded (only rows whose
# LAST field is a count are table rows). yum ids also carry a /$basearch
# suffix and a leading !/* cache marker - both stripped.
an_repolist_ids() {
  local major="$1" file="$2"
  case "$(pc_pm_for_major "${major}")" in
    dnf) awk 'NR>1 && NF {print $1}' "${file}" ;;
    yum) awk '$NF ~ /^[0-9,]+$/ && $1 != "repolist:" {sub(/^[!*]/,"",$1); sub(/\/.*/,"",$1); print $1}' "${file}" ;;
  esac
}

# an_defining_file DIR REPOID - locate the .repo file (post-trigger copy)
# whose section defines REPOID; authoritative dnf Repo-filename wins if logged.
an_defining_file() {
  local dir="$1" id="$2" f
  if [ -s "${dir}/s09-repoinfo.out" ]; then
    f="$(awk -v id="${id}" '$0 ~ "^Repo-id" && $0 ~ id {hit=1} hit && /^Repo-filename/ {print $3; exit}' \
          "${dir}/s09-repoinfo.out")"
    [ -n "${f}" ] && { printf '%s\n' "${f}"; return; }
  fi
  for f in "${dir}/files-post/"*.repo; do
    [ -e "${f}" ] || continue
    grep -Eq "$(pc_repoid_pattern "${id}")" "${f}" && { printf '%s\n' "$(basename "${f}")"; return; }
  done
  printf '?\n'
}

# an_txn_pairs FILE - best-effort "package<TAB>repo" pairs out of a yum/dnf
# transaction table (lines: name arch version repo size).
an_txn_pairs() {
  awk '/^(Installing|Upgrading|Installing dependencies|Installing weak dependencies):/{t=1;next}
       /^(Transaction Summary|Install  |Upgrade  )/{t=0}
       t && NF>=4 && $1 !~ /^(Package|=)/ {print $1"\t"$4}' "$1" 2>/dev/null | sort -u
}

{
  echo "# ANALYSIS - entitlement fact-probe"
  echo
  echo '```'
  cat "${OUT}/MANIFEST.txt"
  echo '```'
  echo
  if [ -d "${OUT}/host" ]; then
    echo "## RF0 - host inventory (r40: RHSM/RHUI support-matrix grounding)"
    echo
    echo '```'
    cat "${OUT}/host/host-os.txt" 2>/dev/null
    printf 'repo_access: '; cat "${OUT}/host/repo-access.txt" 2>/dev/null; echo
    echo '-- host packages (subscription-manager / RHUI clients) --'
    cat "${OUT}/host/host-packages.txt" 2>/dev/null
    echo '-- host repo files --'
    ls "${OUT}/host/yum.repos.d/" 2>/dev/null
    echo '-- host certificates (metadata only) --'
    cat "${OUT}/host/certs.txt" 2>/dev/null
    if [ -f "${OUT}/host/rhui-crossmajor.txt" ]; then
      echo '-- RHUI cross-major authorization check (r42: repomd layer; rhel99 = control) --'
      cat "${OUT}/host/rhui-crossmajor.txt"
    fi
    if [ -f "${OUT}/host/content-sets.txt" ]; then
      echo '-- certificate content sets (rct cat-cert; the authoritative authorization list) --'
      cat "${OUT}/host/content-sets.txt"
    fi
    echo '```'
    echo
  fi
  echo "## F1 - enabled repos per major x condition (post-trigger)"
  echo
  echo "| major | cond | status | enabled repo id | defining file |"
  echo "|---|---|---|---|---|"
  for d in "${OUT}"/raw/*/*/; do
    major="$(basename "$(dirname "${d%/}")")"; cond="$(basename "${d%/}")"
    status="$(awk -F'\t' -v m="${major}" -v c="${cond}" \
              '$1=="meta"&&$2==m&&$3==c&&$4=="status"{print $5}' "${OUT}/facts.tsv")"
    src="${d}s08-repolist-enabled-post.out"; [ -e "${src}" ] || src="${d}s04-repolist-enabled-pre.out"
    if [ ! -e "${src}" ]; then
      echo "| ${major} | ${cond} | ${status:-?} | (no repolist captured) | - |"
      continue
    fi
    ids="$(an_repolist_ids "${major}" "${src}")"
    if [ -z "${ids}" ]; then
      echo "| ${major} | ${cond} | ${status:-?} | (none enabled) | - |"
      continue
    fi
    printf '%s\n' "${ids}" | while IFS= read -r id; do
      [ -n "${id}" ] || continue
      echo "| ${major} | ${cond} | ${status:-?} | ${id} | $(an_defining_file "${d%/}" "${id}") |"
    done
  done
  echo
  echo "## F2 - injection / generation evidence"
  echo
  echo "| major | cond | /run/secrets seen | redhat.repo pre -> post (etc/yum.repos.d) | product cert tags |"
  echo "|---|---|---|---|---|"
  for d in "${OUT}"/raw/*/*/; do
    major="$(basename "$(dirname "${d%/}")")"; cond="$(basename "${d%/}")"
    sec="absent"
    grep -Eq '^[0-9a-f]{64}  /run/secrets/redhat.repo$' "${d}s03-secrets.out" 2>/dev/null \
      && sec="redhat.repo present"
    pre="absent";  [ -e "${d}files-pre/redhat.repo" ]  && pre="$(sha256sum "${d}files-pre/redhat.repo"  | cut -c1-8)"
    post="absent"; [ -e "${d}files-post/redhat.repo" ] && post="$(sha256sum "${d}files-post/redhat.repo" | cut -c1-8)"
    tags="$(awk -F'\t' -v m="${major}" -v c="${cond}" \
            '$1=="cert"&&$2==m&&$3==c{printf "%s; ",$5}' "${OUT}/facts.tsv")"
    tags="${tags%; }"
    echo "| ${major} | ${cond} | ${sec} | ${pre} -> ${post} | ${tags:-?} |"
  done
  echo
  echo "## F4/F6 - package -> resolving repo (build set / install set)"
  echo
  for step in s10-resolve-build s11-resolve-install; do
    echo "### ${step}"
    echo
    echo "| major | cond | rc | package -> repo |"
    echo "|---|---|---|---|"
    for d in "${OUT}"/raw/*/*/; do
      major="$(basename "$(dirname "${d%/}")")"; cond="$(basename "${d%/}")"
      [ -e "${d}${step}.rc" ] || continue
      rc="$(cat "${d}${step}.rc")"
      pairs="$(an_txn_pairs "${d}${step}.out" | awk -F'\t' '{printf "%s<-%s ",$1,$2}')"
      echo "| ${major} | ${cond} | ${rc} | ${pairs:-"(see raw ${step}.out)"} |"
    done
    echo
  done
  echo "## F5 - CRB / optional enablement attempts"
  echo
  echo "| major | cond | candidate repo | makecache rc |"
  echo "|---|---|---|---|"
  for d in "${OUT}"/raw/*/*/; do
    major="$(basename "$(dirname "${d%/}")")"; cond="$(basename "${d%/}")"
    for f in "${d}"s12-crb-enable-*.rc; do
      [ -e "${f}" ] || continue
      c="$(grep -Eo 'repo=.*' "${f%.rc}.out" 2>/dev/null | head -1)"
      echo "| ${major} | ${cond} | ${c#repo=} | $(cat "${f}") |"
    done
  done
  echo
  echo "## F7 - EL6 track rows (subset of the above; status is itself a fact)"
  echo
  echo '```'
  awk -F'\t' '$2=="6"' "${OUT}/facts.tsv"
  echo '```'
} > "${MD}"

cat "${MD}"
echo "written: ${MD}" >&2
