#!/usr/bin/env bash
#==============================================================================
# validate-kickstart.sh -- syntax conformance for wrapper-authored kickstarts
#==============================================================================
# Validates the kickstart file(s) that THIS wrapper authors against the
# matching pykickstart command set (the anaconda generation that ships with the
# target OL release).
#
# Why only OL6 today: upstream oracle-linux-image-tools ships no distr/ol6-slim,
# so this wrapper SYNTHESIZES the OL6 kickstart (the EOF_OL6_KS heredoc in
# build-ol-aws-ami.sh). That is the wrapper's own artifact, so it is validated
# here. OL7+ consume upstream-shipped kickstarts (validated upstream).
#
# Version mapping: OL6 -> RHEL6 (anaconda-13). pykickstart exposes a per-release
# command set; "ksvalidator -v RHEL6" rejects directives/options that only
# exist on later anaconda (e.g. "bootloader --boot-drive", a bare "rootpw
# --lock"). See SPEC Part D pitfall D.18 and TESTING.md.
#
# LIMITATION (important): this checks SYNTAX ONLY. It does NOT verify runtime
# capability -- e.g. whether anaconda-13 can actually create an xfs root, or
# whether a listed package exists in the OL6 repos (iptables-services does not).
# Those are confirmed only by a live build (e.g. an isolated virt-install with
# the installer console visible).
#==============================================================================
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="${here}/../build-ol-aws-ami.sh"

if ! command -v ksvalidator >/dev/null 2>&1; then
  echo "SKIP: ksvalidator (pykickstart) not installed -- 'pip install pykickstart'"
  exit 0
fi
if [[ ! -f "${script}" ]]; then
  echo "FAIL: cannot find build-ol-aws-ami.sh at ${script}"
  exit 1
fi

fail=0

# validate_heredoc <heredoc-marker> <ksversion> <label>
validate_heredoc() {
  local marker="$1" ksver="$2" label="$3"
  local tmp; tmp=$(mktemp)
  # Extract the single-quoted heredoc body (literal; no shell expansion).
  awk -v m="${marker}" '
    $0 ~ ("<<\x27" m "\x27") { f=1; next }
    $0 == m                  { f=0 }
    f                        { print }
  ' "${script}" > "${tmp}"

  if [[ ! -s "${tmp}" ]]; then
    echo "FAIL: ${label}: could not extract heredoc ${marker}"
    fail=1; rm -f "${tmp}"; return
  fi

  local out; out=$(ksvalidator -v "${ksver}" "${tmp}" 2>&1 || true)
  if printf '%s' "${out}" | grep -q 'problem occurred'; then
    echo "FAIL: ${label} (ksvalidator -v ${ksver}):"
    printf '%s\n' "${out}" | sed 's/^/    /'
    fail=1
  else
    echo "PASS: ${label} (ksvalidator -v ${ksver}, $(wc -l < "${tmp}") lines)"
  fi
  rm -f "${tmp}"
}

echo "== kickstart syntax conformance =="
validate_heredoc 'EOF_OL6_KS' RHEL6 'OL6 synthesized kickstart'

if [[ ${fail} -ne 0 ]]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
