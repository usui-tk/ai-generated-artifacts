# Project-bootstrap prompt template

Paste this at the **start of a new-project session** to bootstrap an AI agent into
creating a `sandbox`-stage project under the lifecycle maturity model (ADR 0024 /
ADR 0025). It points at the single-source governance and the birth-kit; it
deliberately restates no rules (reference, don't restate).

```
You are creating a NEW project in the `usui-tk/ai-generated-artifacts` repository,
which is governed by an explicit, in-repo governance model with a project-lifecycle
maturity axis. Before doing anything else:

1. Read `AGENTS.md` §10 "New Project Bootstrap" — the operating procedure — and the
   current-truth view in `governance/SPEC.md` §Execution framework ("Project-lifecycle
   maturity model" / "Exploration/RE mode").
2. The new project is born at the `sandbox` stage. Its birth-kit is:
   - the doc-set rendered from the template canon (`governance/templates/`):
     README.md + README.ja.md + SPEC.md + CHANGELOG.md (+ TESTING.md once tests
     exist), with doc-provenance pins;
   - the AI disclaimer + language policy (English/ASCII code and commits; bilingual
     README pair);
   - the encoding contract and syntax gates.
   Everything else (manifest registration, STATUS tracking, full static analysis,
   vendoring, per-phase loop) is EXEMPT until promotion.
3. Default working discipline is exploration mode (ADR 0025). HARD boundary while in
   it: never touch `reference-code/` canon bodies, vendored regions, `governance/`,
   or the Layer-0 root docs. If the work reveals a needed canon/governance change,
   surface it — it exits the mode into the normal [AUTH] loop.

Project to create:
- directory name (kebab-case, family-prefixed): projects/<FILL: e.g. bash-xyz-tool>
- one-line purpose: <FILL>
- language family: <FILL: bash | powershell | python>
- initial scope / first experiment: <FILL>

Render the birth-kit doc-set, confirm the syntax/encoding gates pass, then tell me
what you built and wait for my direction. Make no changes outside the new project
directory.
```
