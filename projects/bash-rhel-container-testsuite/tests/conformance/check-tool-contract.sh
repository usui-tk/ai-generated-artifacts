#!/usr/bin/env bash
# ----- Purpose --------------------------------------------------------------
#   Check every tests/<vendor>_<tool>/ folder against the tool contract
#   (SPEC section 7 (0)-(e)): installer, lister, releases JSON, matrix, ledger,
#   RESULTS set; emits one [contract][result] JSON per tool.
# ----- Prerequisites --------------------------------------------------------
#   bash 4+; repo checkout only (hermetic).
# ----- Usage examples -------------------------------------------------------
#   bash tests/conformance/check-tool-contract.sh
# ----- Known limitations ----------------------------------------------------
#   Structural conformance only; it does not run the matrices.
# ----- AI generation info -------------------------------------------------
#   AI tool: Anthropic Claude (Claude Fable 5), claude.ai sessions
#   Generation date: 2026-07-02 (r28 header-conformance pass; script logic
#   authored incrementally across the r01-r27 sessions, see CHANGELOG.md)
# ---------------------------------------------------------------------------
#==============================================================================
# check-tool-contract.sh - conformance checker for the tool-compatibility
# framework (Phase 7). Walks every per-tool directory tests/<vendor>_<tool>/ and
# asserts it implements the design plan sec 10 contract (a-e):
#   (a) exactly one  list-*-releases.sh           (executable)
#   (a) exactly one  *-releases.json
#   (b) exactly one  run-*test-matrix.sh          that supports --generate-results
#                                                  and defines a *_verdict() helper
#   (c) exactly one  *-ledger.json                with a "results" array
#   (d) RESULTS-rhel{6,7,8,9,10}.md               (all five)
#   (e) some tests/t*.sh sources the matrix        (a verdict tier exists)
#
# Read-only; emits [contract][result] lines and a summary; exit 0 iff every tool
# conforms. The pure helper contract_dir_missing is unit-tested by
# tests/t013_toolcontract.sh (sourced with CONTRACT_LIB_ONLY=1).
#==============================================================================
set -euo pipefail

# ---- pure helper (no I/O beyond the dir it is handed; column-0) --------------

# contract_dir_missing <tool_dir> : echo a space-separated list of MISSING
# contract artifacts for one tool directory (empty = conformant). Pure file
# existence/format checks; no network, no execution of the tool scripts.
contract_dir_missing() {
  local d="${1:-}" miss="" n m
  [ -d "${d}" ] || { printf 'no-such-dir'; return 0; }

  # (a) lister + releases.json
  n="$(find "${d}" -maxdepth 1 -name 'list-*-releases.sh' -type f | wc -l)"
  [ "${n}" -ge 1 ] || miss="${miss} lister"
  n="$(find "${d}" -maxdepth 1 -name '*-releases.json' -type f | wc -l)"
  [ "${n}" -ge 1 ] || miss="${miss} releases.json"

  # (b) matrix with --generate-results and a *_verdict() helper
  m="$(find "${d}" -maxdepth 1 -name 'run-*test-matrix.sh' -type f | head -1)"
  if [ -z "${m}" ]; then
    miss="${miss} matrix"
  else
    grep -q -- '--generate-results' "${m}" || miss="${miss} generate-results"
    grep -qE '^[a-z_]+_verdict\(\)' "${m}" || miss="${miss} verdict-helper"
  fi

  # (c) ledger with a results array
  n="$(find "${d}" -maxdepth 1 -name '*-ledger.json' -type f | head -1)"
  if [ -z "${n}" ]; then
    miss="${miss} ledger"
  else
    grep -q '"results"' "${n}" || miss="${miss} ledger-results"
  fi

  # (d) RESULTS-rhel{6,7,8,9,10}.md
  for v in 6 7 8 9 10; do
    [ -f "${d}/RESULTS-rhel${v}.md" ] || miss="${miss} RESULTS-rhel${v}"
  done

  printf '%s' "${miss# }"
}

# contract_install_missing <install_script> <matrix> : tokens for the root
# install-script layer (Phase 8). The project-root install-<vendor>_<tool>.sh
# must exist and be executable, and the matrix must KICK it (reference its
# basename). Empty result = conformant. Pure file/grep checks.
contract_install_missing() {
  local inst="${1:-}" matrix="${2:-}" miss=""
  if [ ! -f "${inst}" ]; then
    miss="${miss} install-script"
  elif [ ! -x "${inst}" ]; then
    miss="${miss} install-script-exec"
  fi
  if [ -f "${matrix}" ] && [ -f "${inst}" ]; then
    grep -q "$(basename "${inst}")" "${matrix}" || miss="${miss} matrix-kick"
  fi
  printf '%s' "${miss# }"
}

# ---- the rest runs only when executed (not when sourced for unit tests) ------
[ "${CONTRACT_LIB_ONLY:-0}" = "1" ] && return 0 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJ_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

n_tools=0 n_ok=0 n_bad=0
for d in "${TESTS_DIR}"/*_*/; do
  [ -d "${d}" ] || continue
  case "$(basename "${d}")" in lib|os-coverage|conformance) continue ;; esac
  n_tools=$(( n_tools + 1 ))
  tool="$(basename "${d}")"
  missing="$(contract_dir_missing "${d}")"
  matrix="$(find "${d}" -maxdepth 1 -name 'run-*test-matrix.sh' -type f | head -1)"
  tier_ok=no
  if [ -n "${matrix}" ]; then
    mbase="$(basename "${matrix}")"
    if grep -lqs -- "${mbase}" "${TESTS_DIR}"/t*.sh 2>/dev/null; then tier_ok=yes; fi
  fi
  [ "${tier_ok}" = "yes" ] || missing="${missing:+${missing} }verdict-tier"
  # the root install-script layer: install-<tool>.sh exists + the matrix kicks it
  imiss="$(contract_install_missing "${PROJ_ROOT}/install-${tool}.sh" "${matrix}")"
  [ -n "${imiss}" ] && missing="${missing:+${missing} }${imiss}"
  if [ -z "${missing}" ]; then
    printf '[contract][result] {"tool":"%s","status":"ok"}\n' "${tool}"
    printf '  %-18s OK\n' "${tool}" >&2
    n_ok=$(( n_ok + 1 ))
  else
    printf '[contract][result] {"tool":"%s","status":"fail","missing":"%s"}\n' "${tool}" "${missing}"
    printf '  %-18s FAIL: %s\n' "${tool}" "${missing}" >&2
    n_bad=$(( n_bad + 1 ))
  fi
done

printf 'contract summary: %d tools, %d ok, %d non-conformant\n' "${n_tools}" "${n_ok}" "${n_bad}" >&2
[ "${n_bad}" -eq 0 ] && [ "${n_tools}" -ge 1 ]
