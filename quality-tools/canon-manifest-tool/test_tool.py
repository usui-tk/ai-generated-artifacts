#!/usr/bin/env python3
"""Tests for canon-manifest-tool (tool.py).

A self-validating manifest CRUD tool must: (a) apply manifest-only ops and leave the
master valid (validator 0 findings); (b) reject malformed input at the pre-check;
(c) REFUSE a marker-coupled change -- one that would break the validator's manifest<->
marker / bijection checks -- and roll the master back to byte-identical (the write-path
boundary is enforced by self-validation, not a special case); (d) emit canonical-JSON
rows byte-for-byte. Each test builds a tiny synthetic mini-repo (a faithful D-fixture per
ADR 0010) that includes a real copy of the governance-state validator + schemas so the
subprocess self-validation actually runs. Runtime: python3 + jsonschema. Run:
    python3 test_tool.py

Taxonomy (ADR 0010): dependency bucket (3) environment (filesystem + subprocess
validator) x data class D-fixture (synthetic tree); functional (drives the real CLI
end-to-end), not unit.
"""

import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))           # .../ai-generated-artifacts
VALIDATOR_SRC = os.path.join(REPO, "quality-tools", "governance-state-validator",
                             "validate_state.py")
SCHEMA_SRC = os.path.join(REPO, "governance", "schema")

sys.path.insert(0, HERE)
import tool  # noqa: E402

# Import the real normalizer to build a marker whose hash passes validator check G.
sys.path.insert(0, os.path.dirname(VALIDATOR_SRC))
from validate_state import canon_norm_hash  # noqa: E402

BODY = "function Get-Foo { param($X) Write-Output $X }"
MARKER = (
    "\ufeff# >>> CANONICAL unit_id=pwsh.helper.get-foo version=1.0.0 hash=%s "
    "policy=canonical binding=follow-latest >>>\r\n"
    "%s\r\n"
    "# <<< CANONICAL unit_id=pwsh.helper.get-foo <<<\r\n"
) % (canon_norm_hash(BODY), BODY)


def row(**over):
    base = {
        "schema_version": "1", "unit_id": "pwsh.helper.get-foo",
        "kind": "powershell-helper",
        "canonical_location": "reference-code/powershell/Public/Get-Foo.ps1",
        "canonical_version": "1.0.0", "change_policy": "canonical",
        "binding_mode": "follow-latest", "consumers": [], "tested": True,
        "platform_scope": "cross-platform",
    }
    base.update(over)
    return base


def build_repo():
    """A minimal valid mini-repo: 1 region unit (marker-aligned) + 1 whole-tool unit."""
    root = tempfile.mkdtemp(prefix="cmt_")
    # validator + schemas
    vdir = os.path.join(root, "quality-tools", "governance-state-validator")
    os.makedirs(vdir)
    shutil.copy(VALIDATOR_SRC, os.path.join(vdir, "validate_state.py"))
    shutil.copytree(SCHEMA_SRC, os.path.join(root, "governance", "schema"))
    # region unit code (marker-aligned, BOM+CRLF) -> satisfies checks C/D/E/G
    pub = os.path.join(root, "reference-code", "powershell", "Public")
    os.makedirs(pub)
    with open(os.path.join(pub, "Get-Foo.ps1"), "w", encoding="utf-8", newline="") as fh:
        fh.write(MARKER)
    # whole-tool unit code (a file must exist for check C)
    tdir = os.path.join(root, "quality-tools", "demo-tool")
    os.makedirs(tdir)
    with open(os.path.join(tdir, "demo.py"), "w", encoding="utf-8") as fh:
        fh.write("# demo\n")
    # manifest: the region row + a whole-tool row
    state = os.path.join(root, "governance", "state")
    os.makedirs(state)
    tool_row = {
        "schema_version": "1", "unit_id": "tool.demo-tool", "kind": "tool",
        "canonical_location": "quality-tools/demo-tool/demo.py",
        "canonical_version": "0.1.0", "change_policy": "canonical",
        "binding_mode": "follow-latest", "consumers": [], "tested": True,
        "platform_scope": "cross-platform",
    }
    with open(os.path.join(state, "manifest.jsonl"), "w", encoding="utf-8",
              newline="\n") as fh:
        fh.write(tool._canonical_line(row()) + "\n")
        fh.write(tool._canonical_line(tool_row) + "\n")
    return root


def mpath(root):
    return tool.manifest_path(root)


def read_bytes(path):
    with open(path, "rb") as fh:
        return fh.read()


def ids(root):
    return [r["unit_id"] for r in tool.load_manifest(mpath(root))]


def run(argv):
    return tool.main(argv)


def run_tests():
    cases = []

    # 0. baseline mini-repo validates clean (fixture is faithful).
    root = build_repo()
    rc, _ = tool.run_validator(tool.default_validator(root), root)
    cases.append(("fixture mini-repo is valid at baseline", rc == 0))
    shutil.rmtree(root)

    # 1. register a NEW whole-tool unit -> OK, row present, validator green.
    root = build_repo()
    os.makedirs(os.path.join(root, "quality-tools", "new-tool"))
    open(os.path.join(root, "quality-tools", "new-tool", "n.py"), "w").write("# n\n")
    rc = run(["--root", root, "register", "--unit-id", "tool.new-tool",
              "--kind", "tool", "--location", "quality-tools/new-tool/n.py",
              "--version", "0.1.0", "--change-policy", "canonical",
              "--binding", "follow-latest", "--platform-scope", "cross-platform",
              "--tested", "true"])
    cases.append(("register whole-tool unit succeeds", rc == 0
                  and "tool.new-tool" in ids(root)))
    shutil.rmtree(root)

    # 1b. register a NEW kind=template row -> OK (KINDS in sync with schema enum).
    root = build_repo()
    os.makedirs(os.path.join(root, "governance", "templates"), exist_ok=True)
    open(os.path.join(root, "governance", "templates", "repo-x.template"), "w").write("x\n")
    rc = run(["--root", root, "register", "--unit-id", "template.dotfile.x",
              "--kind", "template", "--location", "governance/templates/repo-x.template",
              "--version", "0.1.0", "--change-policy", "canonical",
              "--binding", "follow-latest", "--platform-scope", "cross-platform",
              "--tested", "false"])
    cases.append(("register kind=template unit succeeds", rc == 0
                  and "template.dotfile.x" in ids(root)))
    shutil.rmtree(root)

    # 2. register with a duplicate unit_id -> refused at pre-check, no write.
    root = build_repo()
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "register", "--unit-id", "tool.demo-tool",
              "--kind", "tool", "--location", "quality-tools/demo-tool/demo.py",
              "--version", "0.1.0", "--change-policy", "canonical",
              "--binding", "follow-latest", "--platform-scope", "cross-platform"])
    cases.append(("register duplicate unit_id is refused (master unchanged)",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 3. register with an invalid unit_id pattern -> refused at pre-check.
    root = build_repo()
    rc = run(["--root", root, "register", "--unit-id", "BadId",
              "--kind", "tool", "--location", "quality-tools/demo-tool/demo.py",
              "--version", "0.1.0", "--change-policy", "canonical",
              "--binding", "follow-latest", "--platform-scope", "cross-platform"])
    cases.append(("register invalid unit_id pattern is refused", rc == 1))
    shutil.rmtree(root)

    # 4. update: flip tested (manifest-only field) -> OK.
    root = build_repo()
    rc = run(["--root", root, "update", "--unit-id", "tool.demo-tool",
              "--tested", "false"])
    after = tool.load_manifest(mpath(root))
    flipped = next(r for r in after if r["unit_id"] == "tool.demo-tool")
    cases.append(("update flip tested succeeds", rc == 0 and flipped["tested"] is False))
    shutil.rmtree(root)

    # 5. update: add a consumer to a region unit (manifest-only) -> OK, validator green.
    root = build_repo()
    rc = run(["--root", root, "update", "--unit-id", "pwsh.helper.get-foo",
              "--add-consumer", "consumer=demo-consumer,path=consumers/Use-Foo.ps1"])
    after = tool.load_manifest(mpath(root))
    foo = next(r for r in after if r["unit_id"] == "pwsh.helper.get-foo")
    cases.append(("update add-consumer (manifest-only) succeeds",
                  rc == 0 and foo["consumers"]
                  and foo["consumers"][0]["consumer"] == "demo-consumer"))
    shutil.rmtree(root)

    # 6. update: bump canonical_version on a REGION unit -> REFUSED (marker drift,
    #    check D); master rolled back byte-identical. (The boundary, enforced by gate.)
    root = build_repo()
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "update", "--unit-id", "pwsh.helper.get-foo",
              "--version", "1.1.0"])
    cases.append(("marker-coupled version bump is REFUSED + rolled back",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 7. update: change_policy on a REGION unit -> REFUSED (marker drift), rolled back.
    root = build_repo()
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "update", "--unit-id", "pwsh.helper.get-foo",
              "--change-policy", "forked"])
    cases.append(("marker-coupled policy change is REFUSED + rolled back",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 8. deregister a whole-tool unit (no marker, no bijection) -> OK.
    root = build_repo()
    rc = run(["--root", root, "deregister", "--unit-id", "tool.demo-tool"])
    cases.append(("deregister whole-tool unit succeeds",
                  rc == 0 and "tool.demo-tool" not in ids(root)))
    shutil.rmtree(root)

    # 9. deregister a REGION unit whose .ps1 still exists -> REFUSED (bijection, check E).
    root = build_repo()
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "deregister", "--unit-id", "pwsh.helper.get-foo"])
    cases.append(("deregister region unit (file present) is REFUSED + rolled back",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 10. canonical-JSON conformance: every written row equals _canonical_line.
    root = build_repo()
    os.makedirs(os.path.join(root, "quality-tools", "cj"))
    open(os.path.join(root, "quality-tools", "cj", "c.py"), "w").write("# c\n")
    run(["--root", root, "register", "--unit-id", "tool.cj",
         "--kind", "tool", "--location", "quality-tools/cj/c.py",
         "--version", "0.1.0", "--change-policy", "canonical",
         "--binding", "follow-latest", "--platform-scope", "cross-platform"])
    with open(mpath(root), encoding="utf-8") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.strip()]
    ok = all(ln == tool._canonical_line(json.loads(ln)) for ln in lines)
    cases.append(("all rows are canonical-JSON (key-sorted, compact)", ok))
    shutil.rmtree(root)

    # 11. update on a missing unit_id -> clean error, no write.
    root = build_repo()
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "update", "--unit-id", "tool.nope", "--tested", "true"])
    cases.append(("update missing unit_id errors cleanly (master unchanged)",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 12. fail-safe: if the validator is absent, a real (non-dry-run) write is refused
    #     and rolled back rather than committed unverified.
    root = build_repo()
    os.remove(tool.default_validator(root))
    before = read_bytes(mpath(root))
    os.makedirs(os.path.join(root, "quality-tools", "fs"))
    open(os.path.join(root, "quality-tools", "fs", "f.py"), "w").write("# f\n")
    rc = run(["--root", root, "register", "--unit-id", "tool.fs",
              "--kind", "tool", "--location", "quality-tools/fs/f.py",
              "--version", "0.1.0", "--change-policy", "canonical",
              "--binding", "follow-latest", "--platform-scope", "cross-platform"])
    cases.append(("absent validator -> write refused + rolled back (fail-safe)",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    passed = 0
    for name, ok in cases:
        print("[%s] %s" % ("PASS" if ok else "FAIL", name))
        passed += int(ok)
    print("\n%d/%d checks passed" % (passed, len(cases)))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(run_tests())
