# Documentation directory

This directory holds long-form documentation for the
`update-windows-server-iso` subproject that is too detailed for the
top-level `README.md` and too narrow in scope to belong in
`SPEC.md`.

The directory was introduced in r06.0 alongside the file-organisation
rules in SPEC.md §B.22. Anything written here MUST follow those
rules.

## Contents

```
docs/
├── README.md     this file -- describes the directory itself
└── poc/          Proof-of-Concept reports and operational docs
    ├── poc-release-info-readme.md      how to run release_info PoC scripts
    ├── poc-release-info-report.md      findings: release-info Markdown source
    ├── poc-dotnet-cu-report.md         findings: .NET CU release-notes source
    └── poc-dynamic-update-report.md    findings: Dynamic Update via Catalog
```

## What lives here vs. elsewhere

| Document kind                                          | Where it lives                  |
|--------------------------------------------------------|---------------------------------|
| Project-wide specification                             | `../SPEC.md` (top level)        |
| Per-release notes                                      | `../CHANGELOG.md` (top level)   |
| User-facing how-to                                     | `../README.md`, `../README.ja.md` |
| Operational guide for `tests/` regression suite        | `../tests/README.md`            |
| Operational guide for PoC scripts in `tests/`          | `docs/poc/poc-<topic>-readme.md` |
| PoC findings and recommendations                       | `docs/poc/poc-<topic>-report.md` |
| Architecture decision record (future)                  | `docs/decision/decision-*.md`   |
| Design memo (future)                                   | `docs/design/design-*.md`       |
| Operator runbook (future)                              | `docs/runbook/runbook-*.md`     |

Only `docs/poc/` exists today. Other subdirectories may be added
when a SPEC update describes them (per SPEC.md §B.22.4).

## Naming rules

Files under `docs/` and its subdirectories use kebab-case
(hyphen-separated lowercase) Markdown filenames with a purpose
suffix:

```
<topic>-<purpose>.md
```

For files under `docs/poc/`, the topic is additionally prefixed
with `poc-` to make the disposable nature visible at every level:

```
poc-<topic>-<purpose>.md
```

The recognised purpose suffixes are:

| Suffix     | Meaning                                                        |
|------------|----------------------------------------------------------------|
| `-readme`  | "How to use / run this thing" -- operational guide             |
| `-report`  | "What we found" -- findings and conclusions                    |
| `-design`  | Forward-looking design memo                                    |
| `-decision`| Architecture decision record                                   |
| `-runbook` | Operator procedure for production incidents                    |

`<topic>` must match the corresponding code's topic exactly,
including separator style. PoC code uses `poc_<topic>_` (snake_case
for Python), and PoC docs use `poc-<topic>-` (kebab-case for
Markdown). Both share the same `<topic>` token in their middle
position.

## File format conventions (inherited from Part A)

All Markdown files in this directory and its subdirectories use:

- UTF-8 encoding without BOM
- LF line endings (not CRLF)
- No trailing whitespace
- Final newline at EOF

These match the project-wide conventions catalogued in SPEC.md
Part A.

## Cross-references

- [`../SPEC.md`](../SPEC.md) §B.22 -- File organisation rules (normative)
- [`../tests/README.md`](../tests/README.md) -- Test suite docs
- [`./poc/`](./poc/) -- PoC documentation
