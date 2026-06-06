# TESTING

Operational tests for `bash-ol-aws-ami-builder`. These are maintainer-facing
checks, not part of the build pipeline itself.

> **Governance note.** This is a subproject-local maintenance document. The
> bash documentation-template family (including a TESTING template) is not yet
> extracted into the governance canon — by the rule-of-two it stays deferred
> until a second bash consumer exists. So this file intentionally carries **no
> canon doc-provenance front-matter** and is **not** part of the reconstructed
> doc-set verified by `doc_gate --reconstructed`. When a bash TESTING template
> is later canonised, this file can be reconstructed/pinned to it.

## Kickstart syntax conformance (`tests/validate-kickstart.sh`)

Upstream `oracle-linux-image-tools` ships no `distr/ol6-slim`, so this wrapper
**synthesizes** the OL6 kickstart (the `EOF_OL6_KS` heredoc in
`build-ol-aws-ami.sh`). Because that kickstart is the wrapper's own artifact, we
validate its **syntax** against the anaconda generation that OL6 actually ships
(anaconda-13) using [`pykickstart`](https://pykickstart.readthedocs.io/)'s
per-release command set:

- **OL6 → `ksvalidator -v RHEL6`**

OL7 and later consume upstream-shipped kickstarts and are validated upstream.

### Run

```sh
pip install pykickstart          # provides the 'ksvalidator' CLI
bash tests/validate-kickstart.sh
```

Expected output:

```
== kickstart syntax conformance ==
PASS: OL6 synthesized kickstart (ksvalidator -v RHEL6, ... lines)
RESULT: PASS
```

The script exits non-zero if any directive is rejected by the target command
set, and SKIPs (exit 0) if `ksvalidator` is not installed.

### What this catches

Directives/options that exist only on a later anaconda but leaked into the OL6
kickstart (the "OL7-ism" class — see SPEC Part D pitfall **D.18**). For example
it rejects `bootloader --boot-drive=...` and a bare `rootpw --lock`, both of
which are RHEL7+/anaconda-19+ only and halt OL6/anaconda-13 at parse time.

### What this does NOT catch (limitation)

`ksvalidator` checks **syntax only**. It does **not** verify:

- **Runtime filesystem support** — e.g. whether OL6/anaconda-13 can actually
  create an **xfs** root (`ROOT_FS=xfs`). A directive like `part / --fstype=xfs`
  is syntactically valid yet may fail at install time.
- **Package availability** — e.g. `iptables-services` does not exist in the OL6
  repositories (only `iptables` does); a missing package is a runtime package-
  selection failure, not a syntax error.

These are confirmed only by a **live build** — for a runtime failure, reproduce
the install in isolation with a bare `virt-install` (text mode, explicit
`console=ttyS0`) so the anaconda output is fully visible. (`SERIAL_CONSOLE=yes`
can stream the OL6/7 install too, but it is a debug-only opt-in that can hang
the build at install-VM end — the default is `no`; see SPEC A.7 / D.18.)
