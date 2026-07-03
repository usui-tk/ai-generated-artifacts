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

    # 5b. update: add a CROSS-REPO consumer (repo=..., ADR 0030) -> OK, the
    #     entry carries the repo key and the validator (schema A) stays green.
    root = build_repo()
    rc = run(["--root", root, "update", "--unit-id", "pwsh.helper.get-foo",
              "--add-consumer",
              "consumer=deploy-demo,path=Deploy-Demo.ps1,"
              "repo=Deploy-Drivers-For-WindowsServer"])
    after = tool.load_manifest(mpath(root))
    foo = next(r for r in after if r["unit_id"] == "pwsh.helper.get-foo")
    cases.append(("update add-consumer with repo= (ADR 0030) succeeds",
                  rc == 0 and foo["consumers"]
                  and foo["consumers"][0].get("repo")
                  == "Deploy-Drivers-For-WindowsServer"))
    shutil.rmtree(root)

    # 5c. update: an UNKNOWN --add-consumer key is refused (previously it was
    #     silently dropped - a latent footgun closed with the repo addition).
    root = build_repo()
    before = read_bytes(mpath(root))
    try:
        rc = run(["--root", root, "update", "--unit-id", "pwsh.helper.get-foo",
                  "--add-consumer",
                  "consumer=deploy-demo,path=Deploy-Demo.ps1,repository=typo"])
        refused = rc != 0
    except SystemExit:
        refused = True
    cases.append(("update add-consumer with unknown key is refused (no write)",
                  refused and read_bytes(mpath(root)) == before))
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

    # 13. register a kind=project lifecycle row (ADR 0024) -> OK; row carries
    #     maturity and NO region-unit fields; validator (real schema) green.
    root = build_repo()
    os.makedirs(os.path.join(root, "projects", "demo-project"))
    rc = run(["--root", root, "register", "--unit-id", "project.demo-project",
              "--kind", "project", "--location", "projects/demo-project",
              "--maturity", "sandbox"])
    after = tool.load_manifest(mpath(root))
    prow = next((r for r in after if r["unit_id"] == "project.demo-project"), None)
    cases.append(("register kind=project (lifecycle row) succeeds",
                  rc == 0 and prow is not None and prow["maturity"] == "sandbox"
                  and "canonical_version" not in prow and "tested" not in prow))
    # 13b. update --maturity promotes the stage -> OK, validator green.
    rc = run(["--root", root, "update", "--unit-id", "project.demo-project",
              "--maturity", "incubating"])
    after = tool.load_manifest(mpath(root))
    prow = next(r for r in after if r["unit_id"] == "project.demo-project")
    cases.append(("update --maturity promotes the stage",
                  rc == 0 and prow["maturity"] == "incubating"))
    shutil.rmtree(root)

    # 14. register kind=project WITHOUT --maturity -> refused at pre-check.
    root = build_repo()
    os.makedirs(os.path.join(root, "projects", "demo-project"))
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "register", "--unit-id", "project.demo-project",
              "--kind", "project", "--location", "projects/demo-project"])
    cases.append(("register kind=project without --maturity is refused",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 15. register kind=project WITH region-unit flags -> refused (lifecycle
    #     record must not carry them; mirrors the schema allOf branch).
    root = build_repo()
    os.makedirs(os.path.join(root, "projects", "demo-project"))
    before = read_bytes(mpath(root))
    rc = run(["--root", root, "register", "--unit-id", "project.demo-project",
              "--kind", "project", "--location", "projects/demo-project",
              "--maturity", "sandbox", "--version", "0.1.0"])
    cases.append(("register kind=project with region-unit flags is refused",
                  rc == 1 and read_bytes(mpath(root)) == before))
    shutil.rmtree(root)

    # 16. register a NON-project kind now missing --version -> refused in-code
    #     (the argparse-required flags moved to the op for the project branch).
    root = build_repo()
    os.makedirs(os.path.join(root, "quality-tools", "nv"))
    open(os.path.join(root, "quality-tools", "nv", "n.py"), "w").write("# n\n")
    rc = run(["--root", root, "register", "--unit-id", "tool.nv",
              "--kind", "tool", "--location", "quality-tools/nv/n.py"])
    cases.append(("register non-project kind without --version is refused",
                  rc == 1 and "tool.nv" not in ids(root)))
    shutil.rmtree(root)

    # ---- promote (R-3.1 coupled write) test set: a doc mini-repo fixture ----
    import hashlib

    def _doc_hash(body):
        # reuse-by-copy of doc_gate.doc_region_norm_hash (ADR 0003/0020)
        import re as _re
        text = _re.sub(r"<!--.*?-->", "", body, flags=_re.DOTALL)
        norm = _re.sub(r"\s+", " ", text).strip()
        return hashlib.sha256(norm.encode("utf-8")).hexdigest()[:16]

    def _doc_marker(unit_region, ver, body):
        return ("<!-- >>> CANONICAL unit_id=%s version=%s hash=%s policy=canonical "
                "binding=follow-latest >>> -->\n%s\n"
                "<!-- <<< CANONICAL unit_id=%s <<< -->\n"
                % (unit_region, ver, _doc_hash(body), body, unit_region))

    def build_doc_repo(consumer_ver="0.1.0"):
        """build_repo + a spec-region unit: L1 item, spec home, one consumer,
        doc_gate copied in (the promote op's subprocess gate), manifest row."""
        root = build_repo()
        # doc_gate (sibling subprocess gate)
        dg = os.path.join(root, "quality-tools", "document-conformance-gate")
        os.makedirs(dg)
        shutil.copy(os.path.join(os.path.dirname(VALIDATOR_SRC), "..",
                                 "document-conformance-gate", "doc_gate.py"),
                    os.path.join(dg, "doc_gate.py"))
        # L1 doc-format item (family segment stripped by map_unit_to_l1)
        dfd = os.path.join(root, "governance", "doc-format")
        os.makedirs(dfd)
        with open(os.path.join(dfd, "doc-format.jsonl"), "w", newline="\n") as fh:
            fh.write(json.dumps({"item_id": "spec.part-a.demo",
                                 "content_model": "vendored",
                                 "schema_version": "1"}, sort_keys=True,
                                separators=(",", ":")) + "\n")
        # spec home + one consumer, both carrying the region at 0.1.0
        body = "Demo Part A body."
        os.makedirs(os.path.join(root, "governance", "spec"))
        with open(os.path.join(root, "governance", "spec", "demo.md"), "w",
                  newline="\n") as fh:
            fh.write("# demo spec home\n\n"
                     + _doc_marker("spec.bash.part-a.demo", "0.1.0", body))
        os.makedirs(os.path.join(root, "projects", "demo"))
        with open(os.path.join(root, "projects", "demo", "SPEC.md"), "w",
                  newline="\n") as fh:
            fh.write("# demo consumer\n\n"
                     + _doc_marker("spec.bash.part-a.demo", consumer_ver, body))
        # register the spec-region row (direct append, then re-canonicalize)
        row_sr = {"schema_version": "1", "unit_id": "spec.bash.part-a",
                  "kind": "spec-region",
                  "canonical_location": "governance/spec/demo.md",
                  "canonical_version": "0.1.0", "change_policy": "canonical",
                  "binding_mode": "follow-latest",
                  "consumers": [{"consumer": "demo",
                                 "path": "projects/demo/SPEC.md"}],
                  "tested": False, "platform_scope": "cross-platform"}
        with open(mpath(root), "a", newline="\n") as fh:
            fh.write(tool._canonical_line(row_sr) + "\n")
        return root

    def _snap(root):
        return {rel: read_bytes(os.path.join(root, rel)) for rel in
                ("governance/state/manifest.jsonl", "governance/spec/demo.md",
                 "projects/demo/SPEC.md")}

    # 17. promote succeeds: row 1.0.0 + tested=true, BOTH files' markers rewritten,
    #     bodies untouched, validator + doc_gate (incl. C9) green.
    root = build_doc_repo()
    rc = run(["--root", root, "promote", "--unit-id", "spec.bash.part-a",
              "--version", "1.0.0"])
    after = tool.load_manifest(mpath(root))
    row = next(r for r in after if r["unit_id"] == "spec.bash.part-a")
    home = read_bytes(os.path.join(root, "governance/spec/demo.md")).decode()
    cons = read_bytes(os.path.join(root, "projects/demo/SPEC.md")).decode()
    cases.append(("promote: coupled 0.1.0 -> 1.0.0 succeeds (row + tested + 2 markers)",
                  rc == 0 and row["canonical_version"] == "1.0.0"
                  and row["tested"] is True
                  and "version=1.0.0" in home and "version=1.0.0" in cons
                  and "Demo Part A body." in home))
    # 17b. C9 equality holds through the write: doc_gate default green afterwards.
    rc2, _ = tool.run_doc_gate(root)
    cases.append(("promote: doc_gate green after the coupled write (C9 equality)",
                  rc2 == 0))
    shutil.rmtree(root)

    # 18. dry-run: plan printed, nothing written.
    root = build_doc_repo()
    before = _snap(root)
    rc = run(["--root", root, "--dry-run", "promote", "--unit-id",
              "spec.bash.part-a", "--version", "1.0.0"])
    cases.append(("promote --dry-run writes nothing",
                  rc == 0 and _snap(root) == before))
    shutil.rmtree(root)

    # 19. non-doc-region kind -> refused (D11 scope), master unchanged.
    root = build_doc_repo()
    before = _snap(root)
    rc = run(["--root", root, "promote", "--unit-id", "pwsh.helper.get-foo",
              "--version", "1.1.0"])
    cases.append(("promote: non-doc-region kind refused (D11)",
                  rc == 1 and _snap(root) == before))
    shutil.rmtree(root)

    # 20. version must advance: equal/backward refused.
    root = build_doc_repo()
    rc_eq = run(["--root", root, "promote", "--unit-id", "spec.bash.part-a",
                 "--version", "0.1.0"])
    rc_back = run(["--root", root, "promote", "--unit-id", "spec.bash.part-a",
                   "--version", "0.0.9"])
    cases.append(("promote: non-advancing version refused", rc_eq == 1 and rc_back == 1))
    shutil.rmtree(root)

    # 21. a consumer file without the unit's markers -> refused BEFORE any write.
    root = build_doc_repo()
    with open(os.path.join(root, "projects", "demo", "SPEC.md"), "w",
              newline="\n") as fh:
        fh.write("# no markers here\n")
    before = _snap(root)
    rc = run(["--root", root, "promote", "--unit-id", "spec.bash.part-a",
              "--version", "1.0.0"])
    cases.append(("promote: marker-less target refused pre-write (incoherent state)",
                  rc == 1 and _snap(root) == before))
    shutil.rmtree(root)

    # 22. gate failure -> byte-identical rollback of ALL touched files: the
    #     consumer's marker version is pre-desynced (0.2.0 vs manifest 0.1.0);
    #     the baseline default gate does not scan consumer files, but the
    #     promote op's doc_gate --path leg sees the 0.2.0 -> 1.0.0 rewrite is
    #     fine... so instead corrupt the consumer HASH: post-write doc_gate
    #     --path reports hash drift -> the whole transaction must roll back.
    root = build_doc_repo()
    cpath = os.path.join(root, "projects", "demo", "SPEC.md")
    corrupted = read_bytes(cpath).decode().replace("Demo Part A body.",
                                                   "Tampered body.")
    with open(cpath, "w", newline="\n") as fh:
        fh.write(corrupted)
    before = _snap(root)
    rc = run(["--root", root, "promote", "--unit-id", "spec.bash.part-a",
              "--version", "1.0.0"])
    cases.append(("promote: gate failure -> byte-identical rollback of all files",
                  rc == 1 and _snap(root) == before))
    shutil.rmtree(root)

    passed = 0
    for name, ok in cases:
        print("[%s] %s" % ("PASS" if ok else "FAIL", name))
        passed += int(ok)
    print("\n%d/%d checks passed" % (passed, len(cases)))
    return 0 if passed == len(cases) else 1


if __name__ == "__main__":
    sys.exit(run_tests())
