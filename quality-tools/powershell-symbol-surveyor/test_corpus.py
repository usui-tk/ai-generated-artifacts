#!/usr/bin/env python3
"""Self-test for corpus.py.

Fixtures are real git repositories built in a temporary directory, because the
behaviour under test is git behaviour: renames, deletions, appended history and
rewritten history. A mock would reproduce the assumptions rather than the facts,
and the traps this tool exists to avoid were all assumption failures.

Run directly; no test framework, no shared imports (ADR 0003).
"""
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import corpus  # noqa: E402

PASS = 0
FAIL = 0


def check(label, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print("[PASS] %s" % label)
    else:
        FAIL += 1
        print("[FAIL] %s%s" % (label, (" - " + detail) if detail else ""))


def git(repo, *args, **kw):
    r = subprocess.run(("git",) + args, cwd=repo, capture_output=True,
                       text=True, **kw)
    if r.returncode != 0 and not kw.get("allow_fail"):
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr))
    return r


def commit(repo, path, body, message):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(body)
    git(repo, "add", "-A")
    git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", message, "--date=2026-01-01T00:00:00")


_REPO_SEQ = [0]


def make_repo(tmp):
    """A fresh repository per test: shared state would couple the cases."""
    _REPO_SEQ[0] += 1
    repo = os.path.join(tmp, "repo%02d" % _REPO_SEQ[0])
    os.makedirs(repo)
    git(repo, "init", "-q", "-b", "main")
    return repo


def fn(name, calls=()):
    body = "\n".join("    %s" % c for c in calls)
    return "function %s {\n%s\n}\n" % (name, body or "    $null = 1")


def script(*names):
    return "\n".join(fn(n) for n in names)


def run(argv):
    """Invoke main() and capture stdout, returning (rc, text)."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        rc = corpus.main(argv)
    return rc, buf.getvalue()


def new_root(tmp, name):
    root = os.path.join(tmp, name)
    os.makedirs(os.path.join(root, "corpus"), exist_ok=True)
    shutil.copy(os.path.join(HERE, "pss.py"), os.path.join(root, "pss.py"))
    return root


# --------------------------------------------------------------------------
# filename identity
# --------------------------------------------------------------------------

def test_filename_rules():
    m = corpus.ENTRY_RE.match("0001-anything-at-all.json")
    check("filename: leading four digits are the identity",
          m is not None and m.group(1) == "0001")

    check("filename: descriptive middle is free-form",
          corpus.ENTRY_RE.match("0002-\u00e4-x_Y.z.json") is not None)

    # The digit-boundary trap: without it, 00012 reads as 0001 + "2".
    check("filename: a fifth digit is refused, not misread as 0001",
          corpus.ENTRY_RE.match("00012-foo.json") is None)

    check("filename: fewer than four digits is not an entry",
          corpus.ENTRY_RE.match("001-foo.json") is None)
    check("filename: non-json is not an entry",
          corpus.ENTRY_RE.match("0001-foo.md") is None)
    check("filename: bare number with suffix is an entry",
          corpus.ENTRY_RE.match("0007.json") is not None)


def test_discovery(tmp):
    root = os.path.join(tmp, "disc")
    cdir = os.path.join(root, "corpus")
    os.makedirs(cdir)
    for n in ["0001-a.json", "0003-b.json", "README.md", "0002-c.json~",
              ".hidden"]:
        open(os.path.join(cdir, n), "w").close()
    entries, ignored = corpus.discover(root)
    check("discovery: conforming files are entries, keyed by number",
          sorted(entries) == [1, 3], str(sorted(entries)))
    check("discovery: non-conforming files are ignored but reported",
          sorted(ignored) == sorted(["README.md", "0002-c.json~", ".hidden"]),
          str(ignored))

    open(os.path.join(cdir, "0001-duplicate.json"), "w").close()
    try:
        corpus.discover(root)
        check("discovery: duplicate number is refused", False,
              "no error raised")
    except corpus.CorpusError as exc:
        check("discovery: duplicate number is refused, never silently chosen",
              "duplicate entry number 0001" in str(exc), str(exc))


# --------------------------------------------------------------------------
# refusals
# --------------------------------------------------------------------------

def test_refusals(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "add S")
    os.makedirs(os.path.join(repo, "dir.ps1"), exist_ok=True)
    root = new_root(tmp, "ref")

    rc, out = run(["--root", root, "--repo", repo, "add", "a/*.ps1"])
    check("refuse: a glob is not a corpus entry",
          rc == corpus.RC_ERROR and "globs are not accepted" in out, out)

    rc, out = run(["--root", root, "--repo", repo, "add", "a"])
    check("refuse: a non-.ps1 path", rc == corpus.RC_ERROR, out)

    rc, out = run(["--root", root, "--repo", repo, "add", "dir.ps1"])
    check("refuse: a directory, even one named like a script",
          rc == corpus.RC_ERROR and "one script" in out, out)

    rc, out = run(["--root", root, "--repo", repo, "add", "/abs/S.ps1"])
    check("refuse: an absolute path", rc == corpus.RC_ERROR, out)

    rc, out = run(["--root", root, "--repo", repo, "add", "a/absent.ps1"])
    check("refuse: a path with no committed generation",
          rc == corpus.RC_ERROR, out)


# --------------------------------------------------------------------------
# add / determinism / rename boundary
# --------------------------------------------------------------------------

def test_add_and_determinism(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 3")
    root = new_root(tmp, "add")

    rc, out = run(["--root", root, "--repo", repo, "add", "a/S.ps1"])
    check("add: first entry is numbered 0001",
          rc == 0 and "0001-a-s.json" in out, out)

    path = os.path.join(root, "corpus", "0001-a-s.json")
    doc = corpus.load_entry(path)
    check("add: every generation is recorded", doc["count"] == 3,
          str(doc["count"]))
    check("add: generations are stored oldest-first",
          doc["generations"][0]["date"] <= doc["generations"][-1]["date"])
    check("add: header pins agree with the records (checked, not trusted)",
          doc["start_rev"] == doc["generations"][0]["rev"]
          and doc["end_rev"] == doc["generations"][-1]["rev"])
    check("add: each record carries an independent blob hash",
          all(len(g["blob"]) == 40 for g in doc["generations"]))

    first = open(path, encoding="utf-8").read()
    rebuilt = corpus.serialize(corpus.load_entry(path))
    check("determinism: re-serialising reproduces the file byte for byte",
          rebuilt == first)
    check("determinism: no timestamp or environment stamp is written",
          "generated_at" not in first and "timestamp" not in first)
    check("determinism: generated_by names the writer (ena convention)",
          doc["generated_by"] == corpus.GENERATED_BY)

    rc, out = run(["--root", root, "--repo", repo, "add", "a/S.ps1",
                   "--slug", "second-take"])
    check("add: the next entry takes the next number",
          rc == 0 and "0002-second-take.json" in out, out)


def test_rename_boundary(tmp):
    """A rename seals the old entry; the deletion commit is not a generation."""
    repo = make_repo(tmp)
    commit(repo, "old/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "old/S.ps1", script("Get-A", "Get-B"), "gen 2")
    os.makedirs(os.path.join(repo, "new"), exist_ok=True)
    git(repo, "mv", "old/S.ps1", "new/S.ps1")
    git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", "move S", "--date=2026-01-01T00:00:00")
    commit(repo, "new/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 4")

    root = new_root(tmp, "ren")
    rc, out = run(["--root", root, "--repo", repo, "add", "old/S.ps1",
                   "--slug", "old-path"])
    doc_old = corpus.load_entry(os.path.join(root, "corpus",
                                             "0001-old-path.json"))
    check("rename: the deletion commit is excluded from the generations",
          doc_old["count"] == 2, str(doc_old["count"]))
    check("rename: the excluded boundary rev is reported, not dropped silently",
          "boundary" in out, out)
    check("rename: the old entry is sealed (path absent at HEAD)",
          "sealed  : yes" in out, out)

    rc, out = run(["--root", root, "--repo", repo, "add", "new/S.ps1",
                   "--slug", "new-path"])
    doc_new = corpus.load_entry(os.path.join(root, "corpus",
                                             "0002-new-path.json"))
    check("rename: the new path becomes a separate, open entry",
          doc_new["count"] == 2 and "sealed  : no" in out,
          "%d / %s" % (doc_new["count"], out))
    check("rename: no generation is shared between the two entries",
          not ({g["rev"] for g in doc_old["generations"]}
               & {g["rev"] for g in doc_new["generations"]}))
    check("rename: every recorded generation resolves at its pinned path",
          all(corpus.blob_at(repo, g["rev"], doc_old["script_path"])
              == g["blob"] for g in doc_old["generations"]))


# --------------------------------------------------------------------------
# growth, rewrite, monotonicity
# --------------------------------------------------------------------------

def test_growth_and_rewrite(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    root = new_root(tmp, "grow")
    run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")

    rc, out = run(["--root", root, "--repo", repo, "check"])
    check("check: a pinned entry matching git is clean",
          rc == corpus.RC_OK and "PASS" in out, out)

    before = open(path, encoding="utf-8").read()
    rc, out = run(["--root", root, "--repo", repo, "update", "1"])
    check("update: an already-current entry is a no-op",
          rc == 0 and open(path, encoding="utf-8").read() == before, out)

    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C"), "gen 3")
    rc, out = run(["--root", root, "--repo", repo, "check"])
    check("check: growth is reported as a finding, never applied silently",
          rc == corpus.RC_FINDINGS and "1 new generation" in out, out)
    check("check: the finding names the command that re-pins it",
          "update 0001" in out, out)

    pre = corpus.load_entry(path)["generations"]
    rc, out = run(["--root", root, "--repo", repo, "update", "1"])
    doc = corpus.load_entry(path)
    check("update: growth appends and advances end_rev",
          rc == 0 and doc["count"] == 3 and doc["end_rev"]
          == doc["generations"][-1]["rev"], out)
    check("update: the stored generations are a strict prefix afterwards "
          "(no earlier measurement is disturbed)",
          doc["generations"][:len(pre)] == pre)

    rc, out = run(["--root", root, "--repo", repo, "check"])
    check("check: clean again after re-pinning", rc == corpus.RC_OK, out)

    # Rewrite the history under the entry: amend the tip.
    commit(repo, "a/S.ps1", script("Get-A", "Get-B", "Get-C", "Get-D"),
           "gen 4")
    git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "--amend", "-m", "gen 4 amended", "--date=2026-01-01T00:00:00")
    git(repo, "reset", "--hard", "HEAD~2")
    commit(repo, "a/S.ps1", script("Get-A", "Get-Z"), "divergent gen 3")

    rc, out = run(["--root", root, "--repo", repo, "check"])
    check("check: a rewritten history is a finding",
          rc == corpus.RC_FINDINGS and "FINDING" in out, out)

    rc, out = run(["--root", root, "--repo", repo, "update", "1"])
    check("update: refuses to absorb a rewritten history",
          rc == corpus.RC_ERROR and "append-only" in out, out)
    check("update: the refusal points at registering a new entry",
          "new entry" in out, out)


def test_load_integrity(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 2")
    root = new_root(tmp, "integ")
    run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")

    doc = corpus.load_entry(path)
    doc["count"] = 99
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(corpus.serialize(doc))
    try:
        corpus.load_entry(path)
        check("integrity: a count contradicting the records is refused", False)
    except corpus.CorpusError as exc:
        check("integrity: a count contradicting the records is refused",
              "count says 99" in str(exc), str(exc))

    doc["count"] = 2
    doc["end_rev"] = "0" * 40
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(corpus.serialize(doc))
    try:
        corpus.load_entry(path)
        check("integrity: an end_rev contradicting the records is refused",
              False)
    except corpus.CorpusError as exc:
        check("integrity: an end_rev contradicting the records is refused",
              "end_rev" in str(exc), str(exc))


# --------------------------------------------------------------------------
# derived views and analysis
# --------------------------------------------------------------------------

def test_list_view(tmp):
    repo = make_repo(tmp)
    commit(repo, "old/S.ps1", script("Get-A"), "gen 1")
    os.makedirs(os.path.join(repo, "new"), exist_ok=True)
    git(repo, "mv", "old/S.ps1", "new/S.ps1")
    git(repo, "-c", "user.name=T", "-c", "user.email=t@e", "commit",
        "-m", "move", "--date=2026-01-01T00:00:00")
    root = new_root(tmp, "lst")
    run(["--root", root, "--repo", repo, "add", "old/S.ps1", "--slug", "old"])
    run(["--root", root, "--repo", repo, "add", "new/S.ps1", "--slug", "new"])
    open(os.path.join(root, "corpus", "NOTES.md"), "w").close()

    rc, out = run(["--root", root, "--repo", repo, "list"])
    check("list: sealed state is derived, never stored",
          "seal" in out and "open" in out, out)
    check("list: no entry file declares its own sealed state",
          all("sealed" not in open(os.path.join(root, "corpus", f),
                                   encoding="utf-8").read()
              for f in os.listdir(os.path.join(root, "corpus"))
              if f.endswith(".json")))
    check("list: ignored files are surfaced in the derived view",
          "NOTES.md" in out, out)
    check("list: entry identity is not stored inside the entry",
          "\"id\"" not in open(os.path.join(root, "corpus", "0001-old.json"),
                               encoding="utf-8").read())


def test_analysis(tmp):
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A", "Get-B"), "gen 1")
    commit(repo, "a/S.ps1", script("Get-A"), "gen 2 drops Get-B")
    root = new_root(tmp, "ana")
    run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])

    rc, out = run(["--root", root, "--repo", repo, "deletions", "1"])
    check("deletions: a removed function is counted",
          rc == 0 and "functions removed         : 1" in out, out)
    check("deletions: counts only, no verdict",
          "verdict" not in out.lower() and "recommend" not in out.lower())

    rc, out = run(["--root", root, "--repo", repo, "transitions", "1",
                   "--targets", "Get-B"])
    check("transitions: a definition disappearing is reported",
          rc == 0 and "DEFINITION GONE" in out, out)

    rc, out = run(["--root", root, "--repo", repo, "ever-defined", "1"])
    check("ever-defined: a name present earlier but not at the end is counted",
          rc == 0 and "defined earlier, not last : 1" in out, out)


def test_unreachable_pin(tmp):
    """A pin that no longer resolves is an error, never a silent skip."""
    repo = make_repo(tmp)
    commit(repo, "a/S.ps1", script("Get-A"), "gen 1")
    root = new_root(tmp, "pin")
    run(["--root", root, "--repo", repo, "add", "a/S.ps1", "--slug", "s"])
    path = os.path.join(root, "corpus", "0001-s.json")
    doc = corpus.load_entry(path)
    doc["generations"][0]["blob"] = "0" * 40
    try:
        for _ in corpus.iter_models(repo, root, doc):
            pass
        check("pins: an unresolvable blob raises rather than skipping", False)
    except corpus.CorpusError as exc:
        check("pins: an unresolvable blob raises rather than skipping",
              "unreachable" in str(exc), str(exc))


def main():
    tmp = tempfile.mkdtemp(prefix="corpus-selftest-")
    try:
        test_filename_rules()
        test_discovery(tmp)
        test_refusals(tmp)
        test_add_and_determinism(tmp)
        test_rename_boundary(tmp)
        test_growth_and_rewrite(tmp)
        test_load_integrity(tmp)
        test_list_view(tmp)
        test_analysis(tmp)
        test_unreachable_pin(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print()
    total = PASS + FAIL
    print("%d/%d checks passed" % (PASS, total))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
