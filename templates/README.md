# templates/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains **reusable templates** — skeleton documents, scaffolding, and forms designed to be copied and filled in for specific use cases.

**JA:** **再利用可能なひな型**（特定のユースケースに合わせてコピーして記入する骨組み文書、スキャフォールド、フォーム類）を格納します。

---

## What to Include / 収録対象

- ADR (Architecture Decision Record) templates
- WBS (Work Breakdown Structure) templates
- Assessment / hearing sheets
- README skeletons for new projects
- Project plan templates
- Evaluation matrix templates
- Document outline templates

- ADR（アーキテクチャ決定書）テンプレート
- WBS（作業分解構成図）テンプレート
- 評価・ヒアリングシート
- 新規プロジェクト用 README ひな型
- プロジェクト計画テンプレート
- 評価マトリックステンプレート
- ドキュメントアウトラインテンプレート

## What NOT to Include / 収録対象外

- Completed/instantiated documents using a template → `documents/`
- Code skeletons that compile and run → `scripts/`
- Slide masters / theme files containing brand assets → reconsider (may not belong in this public repo)
- Real project artifacts disguised as templates → `documents/`

- テンプレートを利用した実成果物 → `documents/`
- コンパイル・実行可能なコードスケルトン → `scripts/`
- ブランドアセットを含むスライドマスター・テーマファイル → 公開可否を再検討
- テンプレートの体裁を装った実プロジェクト成果物 → `documents/`

---

## templates/ vs documents/ — How to Decide / 振り分け判定

| Question | If yes → | If no → |
|:---|:---|:---|
| Is this designed to be **copied and filled in** by another author/project? | `templates/` | next question |
| Does this contain **specific content for a specific scenario**? | `documents/` | reconsider category |

**EN:** A `templates/` artifact is mostly placeholders. A `documents/` artifact is mostly real content.

**JA:** `templates/` の成果物は大部分がプレースホルダ。`documents/` の成果物は大部分が実コンテンツ。

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Templates are organized by **template type** as the primary axis.

**JA:** テンプレートは**種類**を主軸として整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `adr/` | Architecture Decision Record templates (general, AWS-specific, Azure-specific) / ADR テンプレート（汎用、AWS向け、Azure向け） |
| `wbs/` | Work Breakdown Structure templates / WBS テンプレート |
| `assessment/` | Customer assessment / hearing sheet templates / 顧客評価・ヒアリングシート |
| `readme/` | Project README skeletons / プロジェクト README ひな型 |
| `project-plan/` | Project planning templates / プロジェクト計画テンプレート |

Subdirectories are created on demand.

サブディレクトリは必要に応じて作成します。

---

## File Naming / ファイル命名規則

```
<template-type>-template.<lang>.md
```

- Include the literal word `template` in the filename to make purpose obvious / ファイル名に `template` を含めて用途を明確化
- `<template-type>`: short descriptor / テンプレート種別の短い説明
- `<lang>`: `en` or `ja` / 言語コード

**Examples:**
```
templates/adr/adr-template.en.md
templates/adr/adr-template.ja.md
templates/adr/adr-aws-template.ja.md
templates/wbs/azure-to-aws-migration-wbs-template.ja.md
templates/assessment/customer-hearing-sheet-template.ja.md
```

For non-markdown templates (e.g., `.xlsx`, `.docx`, `.pptx`), the same naming convention applies with the appropriate extension.

Markdown 以外のテンプレート（`.xlsx`、`.docx`、`.pptx` など）も同じ命名規則に従います。

---

## Placeholder Convention / プレースホルダ規約

Use a consistent placeholder syntax so users can find-and-replace easily:

利用者が一括置換できるよう、プレースホルダ記法を統一します。

- `{{PLACEHOLDER_NAME}}` — required user input / 利用者が必ず入力する項目
- `[Optional: explanation]` — optional guidance / 任意の補足説明
- `<!-- HINT: ... -->` — guidance for the user, removed before publishing / 利用者向けヒント、公開時に削除

**Example:**
```markdown
# ADR-{{NUMBER}}: {{TITLE}}

## Status
{{STATUS}}  <!-- HINT: Proposed | Accepted | Deprecated | Superseded -->

## Context
{{CONTEXT}}

## Decision
{{DECISION}}

## Consequences
{{CONSEQUENCES}}
```

---

## ⚠️ Disclaimer / 免責事項

Templates are AI-generated and may not be appropriate for all situations. **Review and adapt before use**, especially for compliance-sensitive contexts (regulated industries, formal contracts, regulatory submissions). Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer.

テンプレートは AI 生成であり、すべての状況に適しているとは限りません。特にコンプライアンス上重要な文脈（規制業界、正式契約、当局提出物など）では、**利用前に必ずレビューし調整してください**。完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
