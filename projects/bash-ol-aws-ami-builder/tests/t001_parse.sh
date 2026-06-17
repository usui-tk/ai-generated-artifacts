#!/usr/bin/env bash
#==============================================================================
# tests/t001_parse.sh - B-T1 Parse (test pyramid layer L0, static)
#
# (1) `bash -n` every .sh in the project (main wrapper + siblings + the test
#     harness itself, dogfooded).
# (2) Bash-specific: extract each *shell-bodied* heredoc that ships into the
#     guest / into distr/ol6-slim/ and `bash -n` the body, since the outer parse
#     of the wrapper does not cover literal heredoc text.
#
# The heredoc allowlist below is curated to the SHELL-bodied heredocs only.
# Non-shell heredocs are intentionally excluded: EOF_OL6_KS (kickstart -> B-T4
# ksvalidator), EOF_OL6_ENV / tool_env (env.properties), and the dracut/sshd/ntp
# config heredocs.
#==============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "${HERE}/.." && pwd)"
# shellcheck source=lib/assert.sh
. "${HERE}/lib/assert.sh"
# shellcheck source=lib/heredoc.sh
. "${HERE}/lib/heredoc.sh"

MAIN="${PROJ}/build-ol-aws-ami.sh"

# (1) bash -n on every .sh in the project tree
while IFS= read -r f; do
  bash -n "${f}"
  rc=$?
  assert_rc 0 "${rc}" "bash -n ${f#"${PROJ}"/}"
done < <(find "${PROJ}" -name '*.sh' -type f | sort)

# (2) shell-bodied heredoc bodies (allowlist)
HEREDOC_SHELL_BODIES=(
  OLAWS_NITRO_BODY
  OLAWS_SERIAL_BODY
  OLAWS_OL6_CLOUD_USER_BODY
  EOF_OL6_IMG
  EOF_OL6_PROV
)

for m in "${HEREDOC_SHELL_BODIES[@]}"; do
  body="$(extract_heredoc "${m}" "${MAIN}")"
  if [ -z "${body}" ]; then
    t_fail "heredoc ${m} present and non-empty in build-ol-aws-ami.sh"
    continue
  fi
  printf '%s\n' "${body}" | bash -n
  rc=$?
  assert_rc 0 "${rc}" "bash -n heredoc body ${m}"
done

t_done
