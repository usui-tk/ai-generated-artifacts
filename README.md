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
    Used for repository-convention files whose English filename is itself canonical: `README.md` / `README.ja.md`, `SPEC.md` / `SPEC.ja.md`, `TESTING.md` / `TESTING.ja.md`, etc.
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

- **Default: Bilingual** — when feasible, artifacts are published in both English and Japanese using one of the two patterns documented under "Files" above
- **Acceptable: Single language** — when bilingual versioning is impractical (e.g., language-specific examples), use a single file in the most appropriate language
- READMEs within top-level subdirectories may interleave English and Japanese in a single file to avoid duplication, as long as both languages remain equally complete; deeper script/project directories typically use the paired-file pattern (`README.md` + `README.ja.md`)

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
