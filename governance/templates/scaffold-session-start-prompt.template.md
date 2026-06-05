# Session-start prompt template

Paste this at the **start of a session or task** to bootstrap an AI agent into the
repository's governance. It points at the single-source governance and the entry
point; it deliberately restates no rules (reference, don't restate).

```
You are contributing to the `usui-tk/ai-generated-artifacts` repository, which is
governed by an explicit, in-repo governance model. Before doing anything else:

1. Read `AGENTS.md` (the single-source operating guide) — begin with its
   "Session Start Contract".
2. Per that contract, read `governance/project-management/STATUS.md` — the session
   entry point: current repo HEAD, phase, next action, and open [AUTH]/[WORKING]
   items. Decisions live in `governance/adr/`; design narrative is out-of-repo.
3. Re-clone and re-verify the repository HEAD before acting. Never act on memory;
   if an in-repo artifact and ground-truth disagree, surface it — do not assume.

Then tell me the next action you read from STATUS.md, and wait for my go-ahead.
Make no repository changes until I confirm. Follow the per-phase loop and the
[AUTH] / gate / delete-guard rules exactly as AGENTS.md and the ADRs define them.
```
