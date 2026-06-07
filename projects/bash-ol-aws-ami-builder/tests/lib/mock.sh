# shellcheck shell=bash
#==============================================================================
# tests/lib/mock.sh - command mocking + call spying (dependency class:
# "external commands", Axis 2 of the test model)
#
# Self-contained PATH-shadow mocks (no bats/shellmock): mock_setup creates a
# shadow bin dir, prepends it to PATH, and points a call log at a caller-owned
# work dir; mock_cmd writes a fake executable that records its argv to the log
# and then runs the supplied behaviour. The caller inspects the log for spying.
#
# Intended use is inside an isolated subshell (so the PATH/global changes are
# subshell-local), with the work dir created and cleaned up by the parent test.
#==============================================================================

# mock_setup WORKDIR - create the shadow bin under WORKDIR, prepend to PATH, and
# start an empty call log at WORKDIR/calls. WORKDIR is owned/cleaned by caller.
mock_setup() {
  MOCK_BIN="$1/bin"
  MOCK_LOG="$1/calls"
  mkdir -p "${MOCK_BIN}"
  : > "${MOCK_LOG}"
  PATH="${MOCK_BIN}:${PATH}"
  export PATH MOCK_BIN MOCK_LOG
}

# mock_cmd NAME [BEHAVIOUR] - install a fake `NAME` on the shadow PATH. The fake
# records "NAME arg1 arg2 ..." to the call log, then runs BEHAVIOUR (bash that
# sees the real "$@"; default: exit 0). Example arg-dependent behaviour:
#   mock_cmd id 'case "$1" in qemu) exit 0;; *) exit 1;; esac'
mock_cmd() {
  local name="$1" behaviour="${2:-exit 0}"
  cat > "${MOCK_BIN}/${name}" <<MOCK_EOF
#!/usr/bin/env bash
{ printf '%s' '${name}'; for __a in "\$@"; do printf ' %s' "\${__a}"; done; printf '\n'; } >> '${MOCK_LOG}'
${behaviour}
MOCK_EOF
  chmod +x "${MOCK_BIN}/${name}"
}

# mock_calls NAME - print the recorded invocation lines for NAME (for spying).
mock_calls() {
  grep -- "^$1 " "${MOCK_LOG}" 2>/dev/null || true
}
