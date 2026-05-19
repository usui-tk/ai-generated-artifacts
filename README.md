# ai-generated-artifacts

> 🇯🇵 日本語版は [README.ja.md](./README.ja.md) を参照してください。

## Overview

This repository serves as a public, long-term knowledge base for **artifacts generated or assisted by AI tools** (primarily Anthropic Claude). It consolidates a wide range of AI-produced outputs into a single, navigable structure — from technical research to executable scripts, design documents, presentation materials, reusable templates, AI prompts, and study notes.

The repository is intentionally broad in scope, designed to grow over time without renaming or restructuring.

---

## Repository Structure

The repository is divided into seven top-level directories, each dedicated to a distinct artifact type.

```
ai-generated-artifacts/
├── LICENSE
├── README.md                 # English (primary)
├── README.ja.md              # Japanese
├── SPEC.md                   # Repository-level CI / cross-cutting policy (English)
├── .gitignore
│
├── research/                 # Research articles, surveys, analyses
├── scripts/                  # Automation scripts, utilities, code samples
├── documents/                # Strategy docs, design docs, proposals, plans
├── presentations/            # Slide decks (PowerPoint, Markdown, PDF)
├── templates/                # Reusable templates (ADR, WBS, hearing sheets)
├── prompts/                  # Reusable AI prompts
└── study-notes/              # Certification and learning notes
```

Each top-level directory has its own `README.md` (with both English and Japanese in a single file) documenting:

- Purpose and scope (what to include / what NOT to include)
- Routing rules versus adjacent directories
- Subcategory policy and naming conventions
- Required metadata or header conventions
- Directory-specific disclaimer

---

## Cross-cutting Specifications

Policies that span more than one sub-project (for example, the
continuous-integration design and the timeout discipline applied to
every workflow) are documented at the repository root in
[`SPEC.md`](./SPEC.md). Sub-project-specific specifications live in
each sub-project's own `SPEC.md`.

Start with the repository-level [`SPEC.md`](./SPEC.md) when:

- You are adding a new CI workflow under `.github/workflows/`.
- You are modifying an existing workflow's timeout, naming, or
  `if`-guard.
- You are reviewing a fork PR and need the published review protocol.

---

## Continuous Integration

The repository ships four GitHub Actions workflows under
`.github/workflows/`. Their status is summarised below; the
sub-project READMEs carry only the badges relevant to that sub-project.

| Workflow | Target | Badge |
|:---|:---|:---|
| psa.py self-quality gates | `scripts/python/powershell-static-analyzer/` | [![psa.py CI](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml) |
| Download-SpeakerDeck STAGE 1 (Linux) | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml) |
| Download-SpeakerDeck STAGE 2 (Windows) | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml) |
| Download-SpeakerDeck STAGE 3 (Release verification) | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml) |

Governance, naming conventions, timeout tiers, and the fork-PR review
protocol are defined in [`SPEC.md`](./SPEC.md) (§2 through §9). Per-CI
change history lives in each sub-project's own `CHANGELOG.md`, never in
a separate `.github/workflows/CHANGELOG.md` (none exists, and creating
one is forbidden by [`SPEC.md`](./SPEC.md#9-spec-ci-070-ci-change-history-location) §9).

For the repository-level security baseline (Dependabot, secret
scanning, push protection, CodeQL, Actions allowlist, and the
`GITHUB_TOKEN` scope policy), see [`SPEC.md` §11 (SPEC-CI-080)](./SPEC.md#11-spec-ci-080-repository-security-baseline). The artifact
content minimization policy that constrains what each workflow's
`[Artifacts] Upload logs` step may upload is documented in [`SPEC.md`
§12 (SPEC-CI-081)](./SPEC.md#12-spec-ci-081-artifact-content-minimization).

---

## Content Routing — Where Does My Artifact Belong?

When unsure which directory to use, follow this decision rule:

| The artifact is primarily... | Place it in |
|:---|:---|
| A **comparison, survey, or analysis** answering "what are the options?" | `research/` |
| **Executable code** in any language | `scripts/` |
| A **specific plan, design, or recommendation** for a particular scenario | `documents/` |
| A **slide deck** intended to be presented | `presentations/` |
| A **skeleton, scaffold, or form** designed to be copied and filled in | `templates/` |
| A **reusable AI prompt** | `prompts/` |
| **Learning material** for certification or technical study | `study-notes/` |

For composite artifacts (e.g., a template paired with explanatory commentary), split into the primary location and cross-reference from a single source-of-truth file.

---

## Naming Conventions

### Directories

- Lowercase, hyphen-separated, **plural** form (denotes a collection)
  - ✅ `research/`, `scripts/`, `study-notes/`
  - ❌ `Research/`, `script/`, `study_notes/`

### Subdirectories

- Lowercase, hyphen-separated, descriptive of the **topic, language, or category**
  - ✅ `research/cloud-infrastructure/`, `scripts/powershell/`, `study-notes/aws/`

### Files

- Lowercase, hyphen-separated slug
- Two bilingual filename patterns are accepted:
  - **Pattern A — paired language suffix** (`<slug>.en.md` / `<slug>.ja.md`)
    Used for ordinary content files such as research articles or study notes.
  - **Pattern B — primary-and-translation** (`<NAME>.md` is the English primary, `<NAME>.ja.md` is the Japanese translation)
    Used for `README.md` / `README.ja.md`. (Other repository-convention files — `SPEC.md`, `TESTING.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` — are English-only per the Language Policy below.)
- Single-language files: `<slug>.md`
- Code files follow the idiomatic naming convention of their language (e.g., `Verb-Noun.ps1` for PowerShell, `kebab-case.sh` for Bash, `snake_case.py` for Python)

### Forbidden in Filenames

- Uppercase letters (except in language-mandated names or repository-convention names — `LICENSE`, `README.md`, `SPEC.md`, `TESTING.md`, and PowerShell `Verb-Noun.ps1` files)
- Spaces
- Japanese or other non-ASCII characters
- Special symbols beyond `-`, `_`, and `.`
- Names longer than approximately 50 characters

---

## Language Policy

This repository uses a **repository-wide common policy** for documentation languages, applied uniformly across all sub-directories and sister repositories:

| File type | Languages maintained | Master | Notes |
| --- | --- | --- | --- |
| `README.md` | English **and** Japanese (`README.ja.md`) | `README.md` (English) | English is the master; `README.ja.md` is its translation, kept in sync in the same PR. |
| `SPEC.md` | **English only** | — | Specifications are maintained in English only to avoid drift. |
| `TESTING.md` | **English only** | — | Test procedures and validation results, English only. |
| `CHANGELOG.md` | **English only** | — | Chronological per-release change log, English only. |
| `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` | **English only** | — | Repository-policy files, English only. |
| Research articles, study notes (Pattern A `<slug>.en.md` / `<slug>.ja.md`) | English and / or Japanese as feasible | — | Content files; bilingual where practical. |
| Top-level subdirectory READMEs | Interleaved EN / JA in a single file | — | An exception for very short overview READMEs that would suffer from duplication; both languages must remain equally complete. |

**Policy rationale**: Only `README.md` is duplicated into Japanese because it is the primary entry point for new readers. Specifications, testing procedures, and release logs are maintained in English only to avoid synchronization drift — a problem that LLM-assisted maintenance is especially vulnerable to. Japanese readers should use `README.ja.md` for orientation and then refer to the English source-of-truth documents for technical detail.

When older artifacts contain `SPEC.ja.md` or `TESTING.ja.md` files, they should be removed in the next maintenance pass and their references in other documents updated to point to the English originals.

---

## Revision History Policy

This repository uses a **repository-wide common policy** for managing per-version change history, applied uniformly across all sub-projects (scripts, tools, prompts) maintained here:

- **Per-version release notes live in `CHANGELOG.md`**, not in script bodies, not in `README.md`, not in `SPEC.md`.
- Each sub-project that has a meaningful release cadence ships its own `CHANGELOG.md` next to its other files (e.g., [`scripts/python/powershell-static-analyzer/CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md)).
- `CHANGELOG.md` follows the [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format and adheres to [Semantic Versioning 2.0.0](https://semver.org/).
- `CHANGELOG.md` is **English only**, per the [Language Policy](#language-policy) above.

**What goes where:**

| Information type                                  | Location                                                |
| ------------------------------------------------- | ------------------------------------------------------- |
| *What does this code do today?*                   | Script body comments + `README.md`                      |
| *Why is it designed this way?*                    | `SPEC.md` (especially "Part D — Known Pitfalls" or equivalent) |
| *What changed in each release, and when?*         | `CHANGELOG.md`                                          |
| *What is the public API contract for SemVer?*     | `SPEC.md` Versioning section                            |

**Why this matters**: LLM-assisted code maintenance is especially prone to accumulating stale per-revision comments inside script bodies (`# r42: fixed X`, `# r56+: now does Y`). Such comments rapidly become untraceable noise — readers cannot resolve `r42` without consulting Git history anyway. Centralizing release notes in `CHANGELOG.md` and keeping scripts focused on current behaviour avoids this failure mode.

**Static-analyzer enforcement**: For PowerShell scripts, `psa.py` ships two opt-in rules — `PSAP0003` (inline `# rNN:` revision tags) and `PSAP0004` (end-of-file `REVISION HISTORY` blocks) — that detect violations of this policy. Sub-projects enforce them via their `.psa.config.json` `enable` list. (Consumers should always validate against the latest mainline `psa.py`; see the "psa.py Versioning Policy" section below.)

For per-sub-project deeper guidance, see the **Revision discipline** subsection of each sub-project's `SPEC.md`.

**CI changes are recorded in the CI-target script's `CHANGELOG.md`, NOT in any separate location** (`.github/workflows/CHANGELOG.md` does not exist and MUST NOT be created — see [`SPEC.md`](./SPEC.md#9-spec-ci-070-ci-change-history-location) §9). A change to a workflow YAML is recorded in the same `CHANGELOG.md` as the script that the workflow validates.

---

## psa.py Versioning Policy

This repository hosts [`psa.py`](./scripts/python/powershell-static-analyzer/), the canonical PowerShell static analyzer used by every PowerShell sub-project in this repository **and** by sister repositories (notably [`Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)). This section defines the repository-wide rule for what version of `psa.py` consumers must validate against, and the canonical workflow for discovering and adopting new versions.

### Core rule: latest mainline is the only supported version

Consumers — including LLM / AI-assisted maintainers, CI pipelines, and human developers — MUST validate their PowerShell code against the **latest mainline** `psa.py` from this repository. Pinning to a fixed SemVer (e.g. "I tested with `psa.py` 3.3.0") is **not supported**:

- New `psa.py` versions may add opt-in rules (the `PSAPxxxx` family) that surface previously-hidden discipline violations.
- New `psa.py` versions may tighten heuristics for existing rules.
- A previously-clean codebase under an older `psa.py` is **not** evidence of correctness under the current `psa.py`. It must be re-validated.

Sub-project documentation (`README.md`, `SPEC.md`, `TESTING.md`, etc.) MUST NOT pin `psa.py` to a specific version number. References to a specific version are acceptable only in `CHANGELOG.md` (which is rNN/version-by-design) and in `psa.py`'s own `CHANGELOG.md`.

### How to discover the current mainline version

The canonical source of truth for "what is the current `psa.py` version on mainline" is the `VERSION` file sitting next to `psa.py`:

```
scripts/python/powershell-static-analyzer/
├── psa.py        ← __version__ string inside
├── VERSION       ← single ASCII line, no leading 'v', terminating LF
├── SPEC.md
├── CHANGELOG.md
└── README.md
```

Three equivalent retrieval methods (any of them works; pick the one that fits your environment):

```bash
# Method 1 — remote HTTP GET, no clone, no Python (recommended for CI / one-off checks).
LATEST=$(curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION)
echo "Latest psa.py on mainline: $LATEST"

# Method 2 — already cloned (e.g., sister repository checkout next to this one).
LATEST=$(cat /path/to/ai-generated-artifacts/scripts/python/powershell-static-analyzer/VERSION)

# Method 3 — invoke a local copy of psa.py (requires Python).
LATEST=$(python3 /path/to/psa.py --version | awk '{print $2}')
```

The three methods MUST agree: `psa.py` runs a startup self-check that compares its `__version__` against the sibling `VERSION` file and warns to stderr if they differ. See [`SPEC.md` §1.4](./scripts/python/powershell-static-analyzer/SPEC.md#14-versioning) for the contract.

### LLM / AI workflow for adopting a new version

When an LLM / AI maintainer (or a human) is about to make changes to **any** PowerShell script that is validated by `psa.py` (in this repository or in a sister repository), the very first step of the development cycle MUST be:

1. **Fetch the current mainline version**: run Method 1 above to get `LATEST`.
2. **Compare with the local copy actually being used**: read `__version__` from the local `psa.py`, or run `python3 /path/to/local/psa.py --version`. Call this `LOCAL`.
3. **If `LATEST != LOCAL`**:
   1. Replace `psa.py` AND its sibling `VERSION` file from mainline (both files MUST move together):
      ```bash
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py -o psa.py
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION -o VERSION
      ```
   2. Read the new entries in [`CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md) and the current [`SPEC.md`](./scripts/python/powershell-static-analyzer/SPEC.md) to understand what changed (new rules, tightened heuristics, schema changes).
   3. Re-evaluate the project's `.psa.config.json` `enable` list against the latest `SPEC.md`. Newly-added opt-in rules that match the project's discipline goals SHOULD be enabled.
   4. Re-run the full test suite for every PowerShell script in the project under the new `psa.py`. Treat any new findings as regressions to be addressed in the same change set, not as findings to be deferred.
4. **If `LATEST == LOCAL`**: proceed with the planned change, but still re-run the analyzer on the modified scripts before declaring done.

This workflow makes the "latest mainline" rule machine-actionable: an LLM that has read this section can derive a deterministic sequence of `curl`, comparison, fetch, and re-test steps for any task that touches PowerShell code in this repository or its sister repositories.

### What about released SemVer versions in `CHANGELOG.md`?

The version numbers in [`psa.py`'s `CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md) (e.g. `## [3.4.0] — 2026-05-19`) remain the canonical historical record of when each behaviour change shipped. They are written for human auditors and for diffing the API contract between two points in time. They are NOT a pinning target: consumers do not pick "version 3.4.0" as their reference; they pick "mainline today" and consult the CHANGELOG to understand how that differs from "mainline last time I synced".

---

## ⚠️ Use at Your Own Risk (Self-Responsibility)

**All content in this repository is provided "AS IS", without warranty of any kind. Use it entirely at your own risk.**

By accessing, referencing, executing, or otherwise using any artifact in this repository, you acknowledge and agree to the following:

1. **No warranty of correctness or fitness for purpose.** The author makes no representations or warranties regarding the accuracy, completeness, reliability, suitability, or availability of any content. Information may be outdated, incomplete, or factually incorrect.

2. **No liability for damages.** The author shall not be held liable for any direct, indirect, incidental, consequential, or special damages arising from the use of any content in this repository — including but not limited to data loss, system failure, security incidents, financial loss, downtime, business impact, or loss of certifications or professional standing.

3. **Independent verification required.** Before applying any information, recommendation, design, code, or template from this repository to real-world systems — especially production environments — you are solely responsible for:
   - Reviewing and validating accuracy with authoritative sources
   - Testing thoroughly in a safe, isolated environment
   - Assessing security, performance, compliance, and licensing implications
   - Obtaining appropriate approvals within your organization

4. **Scripts and code carry execution risk.** Running scripts can modify files, change system state, transmit data, incur cloud or service costs, or affect third-party systems. Always read and understand a script before executing it.

5. **No credentials in artifacts.** Artifacts in this repository must not contain real secrets (API keys, passwords, tokens, account IDs you wish to keep private). Scripts are designed to receive credentials via environment variables, parameters, or interactive prompts.

6. **Study notes are not a substitute for official material.** Notes under `study-notes/` are personal synthesis from public sources and must not be relied upon as the primary preparation material for certifications. They never contain NDA-protected exam content.

---

## 🤖 AI-Generated Content Disclaimer

- This repository contains content **generated or assisted by AI tools** (primarily Anthropic Claude).
- AI-generated outputs are subject to **hallucinations, factual errors, outdated information, and reasoning mistakes**.
- All artifacts should be **independently reviewed and validated by humans** with appropriate domain expertise before being relied upon.
- AI-generated code and configurations may require additional validation for security, performance, compliance, and licensing considerations.
- References to third-party products, services, prices, specifications, or version numbers may have changed since the artifact was generated.

---

## Review and Maintenance Policy

- Artifacts are reviewed by the author when feasible, but **no periodic refresh is guaranteed**.
- Modifications and enhancements aim to remain traceable through Git history.
- Assumptions, constraints, and context used during generation are documented within each artifact where applicable.
- Outdated artifacts may remain in the repository for historical reference and are not automatically removed.

---

## Contributing

This is a personal repository. Issues and pull requests are not actively solicited, but constructive feedback (corrections, broken links, factual errors) is welcomed via GitHub Issues. There is no guarantee of response or incorporation.

---

## License

This repository is licensed under the [MIT License](./LICENSE).

The MIT License covers the contents authored or compiled by the repository owner. **Third-party trademarks, product names, and referenced materials** mentioned in artifacts remain the property of their respective owners.

---

## Notes

This repository is intended to support personal learning, research, and knowledge sharing activities involving AI tools. It does **not** imply endorsement of AI-generated outputs as authoritative, production-ready, or professionally certified material.
