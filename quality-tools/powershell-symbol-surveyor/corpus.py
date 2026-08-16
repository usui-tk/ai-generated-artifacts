#!/usr/bin/env python3
"""Corpus manager for the PowerShell Symbol Surveyor.

A corpus entry pins one script at one path across a contiguous run of committed
generations. The repository's own git history is the sample material: the owner
controls it, and a pinned generation is immutable, so a corpus entry stays
reproducible for as long as the history is reachable.

Two rules give the design its shape.

1. An entry never follows a rename. `git log --follow` is a heuristic, not a
   recorded fact, and `git show <rev>:<current path>` fails silently for every
   generation before a move. Pinning one path removes both failure modes by
   construction rather than by defensive coding: every generation an entry
   records is one where the blob provably exists at that exact path. When a
   script moves, the old entry seals and a new entry is registered.

2. An entry is append-only. `update` re-derives the generation list and refuses
   unless the stored list is a strict prefix of what git reports now. Growth is
   additive - no previously measured generation changes - while a rewritten or
   truncated history is refused rather than absorbed.

Output is byte-stable by construction: no timestamps, no environment stamps, no
run-dependent values anywhere in a written entry. That is what makes `check`
work, because growth detection is regeneration plus comparison, and a file that
differs on every regeneration cannot support it.

Entry identity is the leading four-digit number in the filename. Everything
between the number and the `.json` suffix is descriptive and is never read, so
renaming an entry file cannot break anything and cannot go stale.

Analysis subcommands (`deletions`, `transitions`, `ever-defined`) report counts
and observations. They produce no verdict and write no files.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

TOOL_VERSION = "1.0.0"
SCHEMA_VERSION = "1.0"
LIST_TYPE = "pss-corpus-entry"
GENERATED_BY = "quality-tools/powershell-symbol-surveyor/corpus.py"

CORPUS_DIRNAME = "corpus"
PSS_RELATIVE = "pss.py"

# Identity is the leading four digits. A non-digit must follow, otherwise
# "00012-x.json" would silently read as entry 0001 with the descriptive part
# "2-x". The descriptive middle is never interpreted.
ENTRY_RE = re.compile(r"^(\d{4})(?!\d).*\.json$")

GLOB_CHARS = set("*?[]")

HEADER_ORDER = [
    "schema_version",
    "list_type",
    "generated_by",
    "repo",
    "script_path",
    "start_rev",
    "end_rev",
    "count",
]
RECORD_ORDER = ["rev", "date", "blob", "subject"]

RC_OK = 0
RC_FINDINGS = 1
RC_ERROR = 2


class CorpusError(Exception):
    """A refusal. Raised instead of returning a degraded result."""


# --------------------------------------------------------------------------
# git plumbing
# --------------------------------------------------------------------------

def git(repo, *args):
    return subprocess.run(("git",) + args, cwd=repo,
                          capture_output=True, text=True)


def git_ok(repo, *args):
    r = git(repo, *args)
    if r.returncode != 0:
        raise CorpusError("git %s failed: %s"
                          % (" ".join(args), r.stderr.strip()))
    return r.stdout


def repo_name(repo):
    """Best-effort remote-derived name; falls back to the directory name."""
    r = git(repo, "config", "--get", "remote.origin.url")
    url = r.stdout.strip() if r.returncode == 0 else ""
    if url:
        base = url.rstrip("/").rsplit("/", 1)[-1]
        if base.endswith(".git"):
            base = base[:-4]
        if base:
            return base
    return os.path.basename(os.path.abspath(repo))


def blob_at(repo, rev, path):
    """Blob sha for path at rev, or None when the path is absent there."""
    r = git(repo, "rev-parse", "--verify", "--quiet", "%s:%s" % (rev, path))
    sha = r.stdout.strip()
    return sha if r.returncode == 0 and sha else None


def path_at_head(repo, path):
    return blob_at(repo, "HEAD", path) is not None


def enumerate_generations(repo, path, start_rev=None):
    """Chronological generations of path, plus the boundary revs excluded.

    `git log -- <path>` reports the commit that deletes the path as well.  A
    deletion carries no blob, so it is not a generation; it is returned
    separately so the caller can report it instead of dropping it in silence.

    No --follow: the path is fixed for the life of an entry.
    """
    out = git_ok(repo, "log", "--format=%H%x1f%ad%x1f%s", "--date=short",
                 "--", path)
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        parts = line.split("\x1f")
        if len(parts) != 3:
            raise CorpusError("unparsable git log row: %r" % line)
        rows.append(parts)
    rows.reverse()  # git log is newest-first; entries store oldest-first.

    if start_rev:
        full = git_ok(repo, "rev-parse", "--verify", "%s^{commit}"
                      % start_rev).strip()
        idx = next((i for i, r in enumerate(rows) if r[0] == full), None)
        if idx is None:
            raise CorpusError(
                "start-rev %s does not touch %s" % (start_rev, path))
        rows = rows[idx:]

    gens, excluded = [], []
    for rev, date, subject in rows:
        blob = blob_at(repo, rev, path)
        if blob is None:
            excluded.append(rev)
            continue
        gens.append({"rev": rev, "date": date, "blob": blob,
                     "subject": subject})
    return gens, excluded


# --------------------------------------------------------------------------
# entry serialisation
# --------------------------------------------------------------------------

def serialize(doc):
    """Deterministic ena-shaped text: indented header, one record per line.

    Fixed key order, ensure_ascii, LF endings, no timestamp. Regenerating an
    unchanged entry must reproduce the file byte for byte.
    """
    lines = ["{"]
    for key in HEADER_ORDER:
        lines.append("  %s: %s,"
                     % (json.dumps(key), json.dumps(doc[key],
                                                    ensure_ascii=True)))
    lines.append('  "generations": [')
    gens = doc["generations"]
    for i, rec in enumerate(gens):
        body = ", ".join(
            "%s: %s" % (json.dumps(k), json.dumps(rec[k], ensure_ascii=True))
            for k in RECORD_ORDER)
        lines.append("    { %s }%s" % (body, "" if i == len(gens) - 1 else ","))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def build_doc(repo, script_path, gens, repo_label):
    return {
        "schema_version": SCHEMA_VERSION,
        "list_type": LIST_TYPE,
        "generated_by": GENERATED_BY,
        "repo": repo_label,
        "script_path": script_path,
        "start_rev": gens[0]["rev"],
        "end_rev": gens[-1]["rev"],
        "count": len(gens),
        "generations": gens,
    }


def write_entry(path, doc):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(serialize(doc))


def load_entry(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    for key in HEADER_ORDER + ["generations"]:
        if key not in doc:
            raise CorpusError("%s: missing field %r" % (path, key))
    if doc["list_type"] != LIST_TYPE:
        raise CorpusError("%s: list_type is %r, expected %r"
                          % (path, doc["list_type"], LIST_TYPE))
    gens = doc["generations"]
    if not gens:
        raise CorpusError("%s: entry has no generations" % path)
    # end_rev / count duplicate what the records already state. The duplication
    # is deliberate (the header alone shows the range) and is therefore checked
    # rather than trusted.
    if doc["start_rev"] != gens[0]["rev"]:
        raise CorpusError("%s: start_rev does not match the first generation"
                          % path)
    if doc["end_rev"] != gens[-1]["rev"]:
        raise CorpusError("%s: end_rev does not match the last generation"
                          % path)
    if doc["count"] != len(gens):
        raise CorpusError("%s: count says %d, %d generations present"
                          % (path, doc["count"], len(gens)))
    return doc


# --------------------------------------------------------------------------
# entry discovery
# --------------------------------------------------------------------------

def corpus_dir(root):
    return os.path.join(root, CORPUS_DIRNAME)


def discover(root):
    """Return ({number: filepath}, [ignored filenames]).

    A duplicate number is refused: picking one of two entries with the same
    identity would be a silent selection, which is the failure class this tool
    exists to avoid.  Non-conforming files are ignored but reported.
    """
    cdir = corpus_dir(root)
    entries, ignored = {}, []
    if not os.path.isdir(cdir):
        return entries, ignored
    for name in sorted(os.listdir(cdir)):
        full = os.path.join(cdir, name)
        if not os.path.isfile(full):
            ignored.append(name)
            continue
        m = ENTRY_RE.match(name)
        if not m:
            ignored.append(name)
            continue
        num = int(m.group(1))
        if num in entries:
            raise CorpusError(
                "duplicate entry number %04d: %s and %s"
                % (num, os.path.basename(entries[num]), name))
        entries[num] = full
    return entries, ignored


def resolve_entry(root, ident):
    entries, _ = discover(root)
    try:
        num = int(ident)
    except ValueError:
        raise CorpusError("entry id must be a number, got %r" % ident)
    if num not in entries:
        raise CorpusError("no entry %04d" % num)
    return num, entries[num]


def slugify(script_path):
    stem = os.path.splitext(script_path)[0]
    slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    return slug or "entry"


def validate_script_path(repo, script_path):
    if os.path.isabs(script_path):
        raise CorpusError("script path must be repository-relative")
    if any(c in GLOB_CHARS for c in script_path):
        raise CorpusError(
            "globs are not accepted: a corpus entry pins exactly one script")
    if not script_path.lower().endswith(".ps1"):
        raise CorpusError("not a PowerShell script: %s" % script_path)
    if os.path.isdir(os.path.join(repo, script_path)):
        raise CorpusError(
            "directories are not accepted: a corpus entry pins one script")


# --------------------------------------------------------------------------
# pss invocation
# --------------------------------------------------------------------------

def pss_path(root):
    p = os.path.join(root, PSS_RELATIVE)
    if not os.path.isfile(p):
        raise CorpusError("pss.py not found next to corpus.py (%s)" % p)
    return p


def survey_generation(repo, root, rec, script_path, tmpdir):
    """Materialise one generation and survey it. A miss is an error.

    Every recorded generation was proven to carry a blob when the entry was
    written, so a failure here means the pin no longer resolves - which must
    surface, never be skipped.
    """
    blob = git(repo, "cat-file", "-p", rec["blob"])
    if blob.returncode != 0:
        raise CorpusError("blob %s unreachable (generation %s)"
                          % (rec["blob"][:8], rec["rev"][:8]))
    src = os.path.join(tmpdir, "s.ps1")
    with open(src, "w", encoding="utf-8", newline="") as fh:
        fh.write(blob.stdout)
    out = os.path.join(tmpdir, "m.json")
    r = subprocess.run([sys.executable, pss_path(root), "survey", src,
                        "--format", "json", "--out", out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise CorpusError("pss survey failed at %s: %s"
                          % (rec["rev"][:8], r.stderr.strip()[:200]))
    with open(out, encoding="utf-8") as fh:
        return json.load(fh)


def iter_models(repo, root, doc, limit=0):
    gens = doc["generations"]
    if limit:
        gens = gens[-limit:]
    tmp = tempfile.mkdtemp()
    for rec in gens:
        yield rec, survey_generation(repo, root, rec, doc["script_path"], tmp)


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def cmd_add(args, root):
    repo = os.path.abspath(args.repo)
    validate_script_path(repo, args.script_path)
    gens, excluded = enumerate_generations(repo, args.script_path,
                                           args.start_rev)
    if not gens:
        raise CorpusError("no committed generation of %s" % args.script_path)

    entries, ignored = discover(root)
    num = (max(entries) + 1) if entries else 1
    slug = args.slug or slugify(args.script_path)
    name = "%04d-%s.json" % (num, slug)
    cdir = corpus_dir(root)
    os.makedirs(cdir, exist_ok=True)
    target = os.path.join(cdir, name)
    if os.path.exists(target):
        raise CorpusError("%s already exists" % name)

    doc = build_doc(repo, args.script_path, gens, args.repo_label
                    or repo_name(repo))
    write_entry(target, doc)

    print("added   : %s" % name)
    print("script  : %s" % doc["script_path"])
    print("repo    : %s" % doc["repo"])
    print("range   : %s .. %s" % (doc["start_rev"][:8], doc["end_rev"][:8]))
    print("count   : %d generation(s)" % doc["count"])
    if excluded:
        print("boundary: %d rev(s) touched the path without a blob "
              "(deletion commits, not generations): %s"
              % (len(excluded), ", ".join(r[:8] for r in excluded)))
    if ignored:
        print("ignored : %d non-conforming file(s) in %s/"
              % (len(ignored), CORPUS_DIRNAME))
    print("sealed  : %s" % ("no" if path_at_head(repo, doc["script_path"])
                            else "yes (path absent at HEAD)"))
    return RC_OK


def compare_entry(repo, doc):
    """Compare a stored entry against git now. Returns (findings, fresh)."""
    fresh, _ = enumerate_generations(repo, doc["script_path"],
                                     doc["start_rev"])
    stored = doc["generations"]
    findings = []
    if len(fresh) < len(stored):
        findings.append("history shorter than the entry (%d < %d): rewritten "
                        "or truncated" % (len(fresh), len(stored)))
    n = min(len(stored), len(fresh))
    for i in range(n):
        if stored[i]["rev"] != fresh[i]["rev"]:
            findings.append("generation %d diverges: stored %s, git %s"
                            % (i + 1, stored[i]["rev"][:8],
                               fresh[i]["rev"][:8]))
            break
        if stored[i]["blob"] != fresh[i]["blob"]:
            findings.append("generation %d content differs at %s: stored blob "
                            "%s, git %s" % (i + 1, stored[i]["rev"][:8],
                                            stored[i]["blob"][:8],
                                            fresh[i]["blob"][:8]))
            break
    grown = len(fresh) - len(stored)
    return findings, fresh, grown


def cmd_update(args, root):
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    findings, fresh, grown = compare_entry(repo, doc)
    if findings:
        for f in findings:
            print("REFUSED: %s" % f)
        print("An entry is append-only. Register a new entry instead of "
              "rewriting this one.")
        return RC_ERROR
    if grown <= 0:
        print("%04d: already current (%d generation(s)); nothing to do"
              % (num, doc["count"]))
        return RC_OK
    new_doc = build_doc(repo, doc["script_path"], fresh, doc["repo"])
    write_entry(path, new_doc)
    print("updated : %s" % os.path.basename(path))
    print("appended: %d generation(s) (%d -> %d)"
          % (grown, doc["count"], new_doc["count"]))
    print("end_rev : %s -> %s" % (doc["end_rev"][:8], new_doc["end_rev"][:8]))
    return RC_OK


def cmd_check(args, root):
    repo = os.path.abspath(args.repo)
    entries, ignored = discover(root)
    if not entries:
        print("corpus check: no entries")
        return RC_OK
    total = 0
    for num in sorted(entries):
        path = entries[num]
        doc = load_entry(path)
        findings, _, grown = compare_entry(repo, doc)
        name = os.path.basename(path)
        if findings:
            total += len(findings)
            for f in findings:
                print("FINDING %04d %s: %s" % (num, name, f))
        elif grown > 0:
            total += 1
            print("FINDING %04d %s: %d new generation(s) since the pin "
                  "(run `update %04d` to re-pin)" % (num, name, grown, num))
        else:
            print("ok      %04d %s: %d generation(s), pinned"
                  % (num, name, doc["count"]))
    if ignored:
        print("ignored : %d non-conforming file(s): %s"
              % (len(ignored), ", ".join(ignored)))
    print()
    if total:
        print("corpus check: %d finding(s)" % total)
        return RC_FINDINGS
    print("corpus check: PASS - every entry matches its pin")
    return RC_OK


def cmd_list(args, root):
    repo = os.path.abspath(args.repo)
    entries, ignored = discover(root)
    if not entries:
        print("no corpus entries")
        return RC_OK
    for num in sorted(entries):
        path = entries[num]
        doc = load_entry(path)
        sealed = not path_at_head(repo, doc["script_path"])
        print("%04d  %-6s  %4d gen  %s..%s  repo=%s"
              % (num, "sealed" if sealed else "open", doc["count"],
                 doc["start_rev"][:8], doc["end_rev"][:8], doc["repo"]))
        print("      script : %s" % doc["script_path"])
        print("      file   : %s" % os.path.basename(path))
    if ignored:
        print()
        print("ignored: %d non-conforming file(s): %s"
              % (len(ignored), ", ".join(ignored)))
    return RC_OK


def refs_to(model, fid):
    """Every place the model still mentions this function id or its name."""
    name = fid.split("/", 1)[1] if "/" in fid else fid
    hits = {"edge": 0, "soft": 0, "interp": 0}
    for e in model.get("edges", []):
        if e.get("to") == fid:
            hits["edge"] += e.get("sites", 1)
    for s in model.get("soft_references", []):
        if s.get("matches") == fid or s.get("literal") == name:
            hits["soft"] += 1
    for s in model.get("string_interpolation_references", []):
        if s.get("name") == name:
            hits["interp"] += 1
    return hits


def cmd_deletions(args, root):
    """When a function disappeared, did the model still reference it?

    A residual reference after a deletion is a break the model can see. No
    residual means the deletion was either safe or invisible, and the
    limitations count bounds which. No verdict is produced; counts only.
    """
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    print("entry       : %04d %s" % (num, os.path.basename(path)))
    print("script      : %s" % doc["script_path"])
    print("generations : %d" % doc["count"])
    print()

    prev = prev_rec = None
    stats = {"pairs": 0, "deletions": 0, "dangling": 0, "clean": 0,
             "gen_with_del": 0, "del_with_blindspot": 0}
    findings = []
    for rec, cur in iter_models(repo, root, doc, args.limit):
        if prev is not None:
            stats["pairs"] += 1
            before = {s["id"] for s in prev["symbols"]}
            after = {s["id"] for s in cur["symbols"]}
            removed = sorted(before - after)
            if removed:
                stats["gen_with_del"] += 1
            for fid in removed:
                stats["deletions"] += 1
                h = refs_to(cur, fid)
                if h["edge"] + h["soft"] + h["interp"]:
                    stats["dangling"] += 1
                    findings.append((prev_rec["rev"][:8], rec["rev"][:8], fid,
                                     h, len(prev.get("limitations") or [])))
                else:
                    stats["clean"] += 1
                if prev.get("limitations"):
                    stats["del_with_blindspot"] += 1
        prev, prev_rec = cur, rec

    print("pairs compared            : %d" % stats["pairs"])
    print("generations with deletion : %d" % stats["gen_with_del"])
    print("functions removed         : %d" % stats["deletions"])
    print("  left a visible residual : %d" % stats["dangling"])
    print("  no residual in model    : %d" % stats["clean"])
    print("  removed while the pre-state carried unresolved call sites : %d"
          % stats["del_with_blindspot"])
    if findings:
        print()
        for a, b, fid, h, lim in findings[:25]:
            print("  %s->%s  %-48s edge=%d soft=%d interp=%d  "
                  "(limitations before: %d)"
                  % (a, b, fid.replace("function/", ""), h["edge"], h["soft"],
                     h["interp"], lim))
        if len(findings) > 25:
            print("  ... %d more" % (len(findings) - 25))
    return RC_OK


def cmd_transitions(args, root):
    """Track caller counts for named functions and report the transitions."""
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    targets = [t.lower() for t in args.targets]
    print("entry       : %04d %s" % (num, os.path.basename(path)))
    print("targets     : %d" % len(targets))
    print("generations : %d" % doc["count"])
    print()

    prev = {}
    for rec, model in iter_models(repo, root, doc, args.limit):
        by_name = {}
        for s in model["symbols"]:
            by_name.setdefault(s["name"].lower(), s["id"])
        callers = {}
        for t in targets:
            fid = by_name.get(t)
            callers[t] = (sum(1 for e in model.get("edges", [])
                              if e.get("to") == fid) if fid else -1)
        for t in targets:
            was, now = prev.get(t), callers[t]
            if was is None:
                continue
            if was > 0 and now == 0:
                print("LOST CALLERS    %-30s %s %s  %d -> 0"
                      % (t, rec["rev"][:8], rec["date"], was))
                print("                %s" % rec["subject"][:92])
            elif was >= 0 and now == -1:
                print("DEFINITION GONE %-30s %s %s"
                      % (t, rec["rev"][:8], rec["date"]))
            elif was == -1 and now >= 0:
                print("DEFINED         %-30s %s %s  callers=%d"
                      % (t, rec["rev"][:8], rec["date"], now))
        prev = callers
    print()
    print("final caller counts (-1 = not defined):")
    for t in targets:
        print("  %-32s %d" % (t, prev.get(t, -1)))
    return RC_OK


def cmd_ever_defined(args, root):
    """Names ever defined across the entry, against those present at the end."""
    repo = os.path.abspath(args.repo)
    num, path = resolve_entry(root, args.id)
    doc = load_entry(path)
    ever, head = {}, set()
    for rec, model in iter_models(repo, root, doc, args.limit):
        names = {s["name"] for s in model["symbols"]}
        for n in names:
            ever.setdefault(n.lower(), rec["rev"][:8])
        head = names
    head_lower = {h.lower() for h in head}
    gone = sorted(n for n in ever if n not in head_lower)
    print("entry                     : %04d %s"
          % (num, os.path.basename(path)))
    print("generations               : %d" % doc["count"])
    print("names ever defined        : %d" % len(ever))
    print("names defined at last gen : %d" % len(head))
    print("defined earlier, not last : %d" % len(gone))
    if gone and args.show:
        print()
        for n in gone[:args.show]:
            print("  %-44s first seen %s" % (n, ever[n]))
        if len(gone) > args.show:
            print("  ... %d more" % (len(gone) - args.show))
    return RC_OK


# --------------------------------------------------------------------------
# entry point
# --------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(
        description="Corpus manager for the PowerShell Symbol Surveyor.")
    p.add_argument("--version", action="version",
                   version="corpus.py %s" % TOOL_VERSION)
    p.add_argument("--root", default=os.path.dirname(os.path.abspath(__file__)),
                   help="tool directory holding corpus/ (default: alongside "
                        "this script)")
    p.add_argument("--repo", default=".",
                   help="repository whose history supplies the generations")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("add", help="register a new corpus entry")
    a.add_argument("script_path", help="repository-relative path to one .ps1")
    a.add_argument("--slug", help="descriptive filename part (never read back)")
    a.add_argument("--start-rev", help="begin the entry at this revision")
    a.add_argument("--repo-label", help="override the recorded repo name")
    a.set_defaults(func=cmd_add)

    u = sub.add_parser("update", help="append newly committed generations")
    u.add_argument("id")
    u.set_defaults(func=cmd_update)

    c = sub.add_parser("check", help="compare every entry against git now")
    c.set_defaults(func=cmd_check)

    l = sub.add_parser("list", help="derived view of the registered entries")
    l.set_defaults(func=cmd_list)

    d = sub.add_parser("deletions",
                       help="per-generation function removals and residuals")
    d.add_argument("id")
    d.add_argument("--limit", type=int, default=0,
                   help="survey only the last N generations")
    d.set_defaults(func=cmd_deletions)

    t = sub.add_parser("transitions",
                       help="caller-count transitions for named functions")
    t.add_argument("id")
    t.add_argument("--targets", nargs="+", required=True)
    t.add_argument("--limit", type=int, default=0)
    t.set_defaults(func=cmd_transitions)

    e = sub.add_parser("ever-defined",
                       help="names ever defined vs present at the last "
                            "generation")
    e.add_argument("id")
    e.add_argument("--limit", type=int, default=0)
    e.add_argument("--show", type=int, default=0,
                   help="list up to N names that are no longer defined")
    e.set_defaults(func=cmd_ever_defined)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    root = os.path.abspath(args.root)
    try:
        return args.func(args, root)
    except CorpusError as exc:
        print("corpus.py: %s" % exc, file=sys.stderr)
        return RC_ERROR


if __name__ == "__main__":
    sys.exit(main())
