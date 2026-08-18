#!/usr/bin/env python3
"""Derived model cache generator for the PowerShell Symbol Surveyor.

Surveying every generation of a corpus entry is expensive - minutes, not
seconds - so the resulting models are cached outside the repository and carried
between sessions. SPEC 14.4 governs what such a cache must carry to stay
usable. This is the producer it specifies.

It exists because the specification had no implementation. The procedure lived
in prose in a session handoff document and was reconstructed from that prose
each time, which is not a procedure but a description of one. The cost was
paid: a shipped cache carried `gen_index: null` on all 230 records, because the
reconstructed snippet read a key the corpus does not have and nothing checked
the result. A generator that is an artifact can be gated; a snippet quoted in a
handoff cannot.

Two constraints come straight from SPEC 14.4 and are the reason this file is
shaped the way it is.

**It computes no identity of its own.** `baseline_digest` and `model_shape` are
obtained by running `test_pss.py --emit-baseline-digest` and copying the
result. Recomputing them here would put a measurement instrument back outside
the repository - the defect ADR 0033 retired - and would let a cache and the
gate that reads it disagree about what was measured. `hashlib` is deliberately
absent from this file, and `test_pss.py` checks that it stays absent.

**A generation is identified by `rev` and `blob`, never by position.** ADR 0033
puts identity in the blob. An index is derivable from the order of the entry's
own list, so storing it would create a second source of truth for the same
fact, and a stored position is the one that can silently disagree with the list
it came from.

The axis set is fixed at all axes rather than exposed. A cache is only useful
against another cache, and two caches materialised differently are not
comparable (SPEC 5.7); an option here would make incomparable caches easy to
produce and hard to notice. Fixing it also happens to be faster, because a
model that already carries every axis measures no axis increments (SPEC 3.1).
"""
import argparse
import gzip
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS_DIR = os.path.join(HERE, "corpus")

sys.path.insert(0, HERE)
import pss  # noqa: E402  (path set above; single-file tools, ADR 0003)

EXIT_OK = 0
EXIT_ERROR = 2

# SPEC 14.4: the header fields a derived cache must carry. Named here so the
# gate can compare an emitted header against the specification rather than
# against another copy of this list.
HEADER_FIELDS = (
    "axes",
    "baseline_digest",
    "cache_kind",
    "corpus_count",
    "corpus_end_rev",
    "corpus_entry",
    "corpus_start_rev",
    "model_shape",
    "model_version",
    "pss_version",
    "script_path",
    "spec_contract",
)

CACHE_KIND = "pss-raw-cache"
SPEC_CONTRACT = "SPEC 14.4"


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False)


def repo_root(start):
    path = start
    while not os.path.isdir(os.path.join(path, ".git")):
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent
    return path


def git_show(root, blob):
    """Read one pinned blob. Decoded as utf-8-sig: the corpus holds PowerShell
    scripts, which carry a BOM by the repository's encoding contract, and a BOM
    left in the text would appear in the model as a character of the source."""
    out = subprocess.run(["git", "-C", root, "cat-file", "-p", blob],
                         capture_output=True)
    if out.returncode != 0:
        raise RuntimeError("git cat-file failed for %s: %s"
                           % (blob, out.stderr.decode("utf-8", "replace").strip()))
    return out.stdout.decode("utf-8-sig")


def emit_identity(root):
    """Take `baseline_digest` and `model_shape` from the one implementation.

    SPEC 14.4: "A generation script computes nothing itself; it calls this and
    copies the result." The values are parsed back out of the emitted document
    rather than recomputed, so a cache and the baseline gate cannot disagree
    about what was measured.
    """
    out = subprocess.run(
        [sys.executable, os.path.join(HERE, "test_pss.py"),
         "--emit-baseline-digest"], capture_output=True, cwd=root)
    if out.returncode != 0:
        raise RuntimeError("--emit-baseline-digest failed: %s"
                           % out.stderr.decode("utf-8", "replace").strip())
    return json.loads(out.stdout.decode("utf-8"))


def resolve_entry(name):
    """Accept an entry number, a filename, or a path. Entry identity is the
    leading four digits (corpus.py's rule); everything after is descriptive."""
    if os.path.isfile(name):
        return name
    stem = os.path.basename(name)
    match = re.match(r"^(\d{4})", stem)
    if not match:
        raise RuntimeError("not an entry number, filename or path: %s" % name)
    number = match.group(1)
    for candidate in sorted(os.listdir(CORPUS_DIR)):
        if candidate.startswith(number) and candidate.endswith(".json"):
            return os.path.join(CORPUS_DIR, candidate)
    raise RuntimeError("no corpus entry numbered %s" % number)


def build(entry_path, out_path, limit, root, progress):
    with open(entry_path, encoding="utf-8") as fh:
        entry = json.load(fh)

    generations = entry["generations"]
    if limit:
        generations = generations[:limit]
    if not generations:
        raise RuntimeError("entry has no generations to survey")

    script_path = entry["script_path"]
    identity = emit_identity(root)

    header = {
        "axes": sorted(pss.AXES),
        "baseline_digest": identity["baseline_digest"],
        "cache_kind": CACHE_KIND,
        "corpus_count": len(generations),
        "corpus_end_rev": generations[-1]["rev"],
        "corpus_entry": os.path.basename(entry_path),
        "corpus_start_rev": generations[0]["rev"],
        "model_shape": identity["model_shape"],
        "model_version": identity["model_version"],
        "pss_version": identity["pss_version"],
        "script_path": script_path,
        "spec_contract": SPEC_CONTRACT,
    }
    missing = sorted(set(HEADER_FIELDS) - set(header))
    extra = sorted(set(header) - set(HEADER_FIELDS))
    if missing or extra:
        raise RuntimeError("header does not match SPEC 14.4: missing %s, extra %s"
                           % (missing, extra))

    with gzip.open(out_path, "wt", encoding="utf-8", newline="\n") as out:
        out.write(canonical(header) + "\n")
        for n, gen in enumerate(generations, 1):
            text = git_show(root, gen["blob"])
            model = pss.Survey(script_path, text,
                               axes=sorted(pss.AXES)).run().model()
            # rev and blob only. A position is derivable from this file's own
            # order, and ADR 0033 puts identity in the blob.
            out.write(canonical({"blob": gen["blob"], "rev": gen["rev"],
                                 "model": model}) + "\n")
            if progress and n % 10 == 0:
                sys.stderr.write("  %d/%d\n" % (n, len(generations)))
                sys.stderr.flush()

    return header, len(generations)


def main(argv=None):
    p = argparse.ArgumentParser(
        prog="build_cache.py",
        description="produce a derived model cache for one corpus entry "
                    "(SPEC 14.4); the cache is derived data and is never "
                    "committed")
    p.add_argument("entry", help="corpus entry number, filename or path")
    p.add_argument("-o", "--output",
                   help="output path; defaults to "
                        "pss-raw-cache-<number>.jsonl.gz in the "
                        "working directory")
    p.add_argument("--limit", type=int, default=0,
                   help="survey only the first N generations (for exercising "
                        "the generator; not a usable cache)")
    p.add_argument("--quiet", action="store_true", help="no progress on stderr")
    args = p.parse_args(argv)

    root = repo_root(HERE)
    if root is None:
        sys.stderr.write("build_cache.py: not inside a git repository; the "
                         "corpus is read from git history\n")
        return EXIT_ERROR

    try:
        entry_path = resolve_entry(args.entry)
        number = re.match(r"^(\d{4})", os.path.basename(entry_path)).group(1)
        out_path = args.output or ("pss-raw-cache-%s.jsonl.gz" % number)
        header, count = build(entry_path, out_path, args.limit, root,
                              not args.quiet)
    except (RuntimeError, KeyError, OSError, ValueError) as exc:
        sys.stderr.write("build_cache.py: %s\n" % exc)
        return EXIT_ERROR

    if not args.quiet:
        sys.stderr.write(
            "wrote %s\n  %d generation(s), model_version %s, "
            "baseline_digest %s\n"
            % (out_path, count, header["model_version"],
               header["baseline_digest"][:16]))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
