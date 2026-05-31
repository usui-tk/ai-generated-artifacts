# documents/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** The single home for **cross-cutting knowledge assets** — material that belongs to no single project and is not governance. Organized first by **purpose** (the subfolders below), then by **domain** within each.

**JA:** **横断的なナレッジ資産**（特定プロジェクトに属さず、ガバナンスでもない成果物）の単一の置き場です。まず**目的**（下記サブフォルダ）で分け、その中で**ドメイン**別に整理します。

---

## Purpose Subfolders / 目的別サブフォルダ

| Subfolder | Holds / 収録対象 |
|:---|:---|
| `research/` | Comparisons, surveys, analyses — *"what are the options?"* / 比較・調査・分析（「どんな選択肢があるか」） |
| `guides/` | How-to, design, and engineering guides — *"here is what to do / how to design it."* / ハウツー・設計・エンジニアリングガイド（「こうすべき／こう設計する」） |
| `presentations/` | Slide decks (PowerPoint, Markdown, PDF) / プレゼン資料 |
| `prompts/` | Reusable AI prompts / 再利用可能な AI プロンプト |
| `study-notes/` | Certification and learning notes / 認定試験・学習ノート |

Domain subdirectories live **under** a purpose subfolder, created on demand — e.g. `research/cloud-infrastructure/`, `guides/ci-engineering/`, `guides/cloud-migration/`, `guides/cost-analysis/`.

ドメイン別サブディレクトリは目的サブフォルダの**配下**に必要に応じて作成します（例：`research/cloud-infrastructure/`、`guides/ci-engineering/`、`guides/cloud-migration/`、`guides/cost-analysis/`）。

---

## research/ vs guides/ — How to Decide / 振り分け判定

| Question | If yes → | If no → |
|:---|:---|:---|
| Is this a **comparison or survey** of options/products/approaches? | `research/` | next question |
| Is this a **specific recommendation, plan, design, or how-to** for a scenario? | `guides/` | reconsider purpose |

**EN summary:** `research/` answers *"what are the options?"*; `guides/` answers *"here is what to do / how to design it."* Both now live under `documents/`.

**JA要約:** `research/` は「**どんな選択肢があるか**」に答える成果物、`guides/` は「**こうすべき**／**こう設計する**」を示す成果物。どちらも `documents/` 配下に置きます。

---

## What NOT to Include / 収録対象外

- Code or scripts → `scripts/` (governed subprojects → `projects/`)
- Reusable templates / scaffolds (ADR, marker, WBS) → `governance/templates/`
- Governance ADRs, specs, schema, state → `governance/`
- Verification tooling → `quality-tools/`
- Real client/project confidential information → **nowhere in this repo**

- コード／スクリプト → `scripts/`（被管理サブプロジェクトは `projects/`）
- 再利用可能なひな型・スキャフォールド（ADR、マーカー、WBS）→ `governance/templates/`
- ガバナンス ADR・spec・schema・state → `governance/`
- 検証ツール → `quality-tools/`
- 実顧客・実プロジェクトの機密情報 → **本レポジトリのどこにも置かない**

---

## File Naming / ファイル命名規則

```
<purpose>/<domain>/<slug>.<lang>.md
```

- `<slug>`: lowercase, hyphen-separated, descriptive / 小文字・ハイフン区切り・内容を端的に表す
- `<lang>`: `en` or `ja` / 言語コード
- Optional version suffix for evolving documents: `<slug>-v<N>.<M>.<lang>.md` / 進化する文書は版数サフィックス可

**Examples:**
```
documents/research/cloud-infrastructure/hyperscaler-cloud-infrastructure-technology-survey.en.md
documents/guides/ci-engineering/github-actions-windows-powershell-guide.md
```

---

## Required Metadata / 必須メタデータ

Each document should begin with the following / 各ドキュメントの冒頭には以下を記述します。

- **Title and version** / タイトルと版数
- **Scope (in-scope / out-of-scope)** / 対象範囲（対象内・対象外）
- **Audience** / 想定読者
- **Assumptions and constraints** / 前提条件と制約
- **Revision history** (if versioned) / 改訂履歴（版数管理する場合）
- **Generation context** (date, AI tool used) / 生成時の文脈（生成日、利用 AI ツール）

---

## ⚠️ Disclaimer / 免責事項

All documents are AI-generated and may contain **inaccuracies, design flaws, or unsupported recommendations**. Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer and self-responsibility terms.

すべてのドキュメントは AI 生成であり、**不正確な記述、設計上の欠陥、根拠の薄い推奨事項**を含む可能性があります。完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
