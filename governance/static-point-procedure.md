# Static-Point Snapshot Procedure

> Governance procedure (referenced by `project-management/STATUS.md`). Defines the
> per-repo, per-phase "static point" (seishi-ten) snapshot.

## What a static point is
A reversible, repo-relative snapshot of a repository taken at a phase boundary, so any
phase can be rolled back to a known-good tree. It is a **convenience artifact, not a
source of truth** (git history is the authority).

## Scope of the Zip
- **Include:** all tracked files **and** untracked-but-not-ignored files (so a freshly
  created scaffold is captured), preserving repo-relative folder structure.
- **Exclude:** `.git/` and everything matched by `.gitignore` (credentials, operational
  caches, `*.duckdb`, prior static-point Zips).
- **Repo-external, non-committed (#5):** the Zip is written outside the working tree and
  is **never committed** (the `.gitignore` already excludes `*-static-point.zip`).

## Procedure (per repo, per phase)
1. Confirm the working tree is at the intended phase-end state and Stage-1 gates are green.
2. Create `<repo>-<phase>-<YYYYMMDDTHHMMSSZ>-static-point.zip` from tracked +
   untracked-not-ignored paths, excluding `.git/` and ignored paths.
3. Verify the Zip preserves repo-relative structure and excludes ignored paths.
4. Record the Zip name + phase + UTC timestamp in `STATUS.md` (static-point index).

## Notes
- One static point per repo per phase; older ones may be discarded once a newer
  green phase exists (they are reproducible from git).
- Taking a static point is a phase-end step (see the phase-end gate, e.g. P0a.10).
