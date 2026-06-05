# Change-authoring (pre-flight) prompt template

Paste this **before authoring a specific change** to make the agent run the
repository's pre-flight and gate discipline. It points at the canonical checklist
and gates in `AGENTS.md`; it does not duplicate their contents.

```
Before authoring this change, complete the pre-flight defined in `AGENTS.md` (the
"Required Pre-Flight Checklist", §3) and apply its "Self-Check Gates" (§8):

- Read the relevant Layer 0 / Layer 1 / Layer 3 governance for the file(s) you will
  touch; if you touch a SPEC / README / TESTING doc, extract the implementation
  ground truth first (§4).
- Identify the correct Layer and prefer the highest applicable one (DRY). Respect
  the §6 Part A Inheritance Rule (ABSOLUTE) and the §2 sibling-isolation policy.
- Decide which verification gates apply (e.g. psa.py 0/0/0, ParseFile, offline
  tests, bilingual lock-step, encoding) and plan to run them. A non-green gate is a
  deviation (§8.3) — stop and escalate; never silently accept it.

Then tell me: the change, the Layer it belongs to, the files you will touch, and the
gates you will run — and proceed only within that scope. A Layer-0 edit, a
cross-repo change, or any delete requires my explicit authorization first.
```
