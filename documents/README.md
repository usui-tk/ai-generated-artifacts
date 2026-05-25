# documents/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains AI-generated **technical documents** — strategy documents, design documents, proposals, assessments, plans, and similar long-form deliverables.

**JA:** AI が生成した**技術ドキュメント**（戦略書、設計書、提案書、評価書、計画書など、長文の成果物）を格納します。

---

## What to Include / 収録対象

- Strategy documents (e.g., cloud adoption strategy, AI-MSP strategy)
- Design documents and architecture decision records (specific instances, not templates)
- Migration plans and assessment reports
- Cost analyses and TCO calculations
- Proposal documents
- Implementation guides

- 戦略書（クラウド導入戦略、AI-MSP 戦略など）
- 具体的な設計書・アーキテクチャ決定書（ひな型ではなく具体例）
- 移行計画書、評価レポート
- コスト分析、TCO 計算
- 提案書
- 実装ガイド

## What NOT to Include / 収録対象外

- Comparative research articles → `research/`
- Reusable templates → `templates/`
- Slide decks → `presentations/`
- Code or scripts → `scripts/`
- Documents containing real client/project confidential information → **anywhere in this repo**

- 比較リサーチ記事 → `research/`
- 再利用可能ひな型 → `templates/`
- スライド資料 → `presentations/`
- コード／スクリプト → `scripts/`
- 実顧客・実プロジェクトの機密情報を含む文書 → **本レポジトリのどこにも置かない**

---

## research/ vs documents/ — How to Decide / 振り分け判定

| Question | If yes → | If no → |
|:---|:---|:---|
| Is this a **comparison or survey** of options/products/approaches? | `research/` | next question |
| Is this a **specific recommendation, plan, or design** for a particular scenario? | `documents/` | reconsider category |

**EN summary:** `research/` answers *"what are the options?"*. `documents/` answers *"here is what to do."*

**JA要約:** `research/` は「**どんな選択肢があるか**」に答える成果物。`documents/` は「**こうすべき**」「**こう設計する**」を示す成果物。

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Documents are organized by **domain** as the primary axis.

**JA:** ドキュメントは**ドメイン**（テーマ・業務領域）を主軸として整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `cloud-migration/` | Migration planning, assessment, lift-and-shift, refactoring / 移行計画、評価、Lift & Shift、Refactoring |
| `cloud-architecture/` | Specific architecture designs for cloud workloads / 具体的なクラウドアーキテクチャ設計 |
| `cost-analysis/` | TCO calculations, cost comparisons, financial models / TCO 計算、コスト比較、財務モデル |
| `security/` | Security designs, configuration guides for specific scenarios / セキュリティ設計、特定シナリオの設定ガイド |
| `sre-and-ops/` | SRE and operations strategies, runbooks / SRE・運用戦略、ランブック |
| `ai-strategy/` | AI adoption strategies, MSP offerings / AI 導入戦略、MSP オファリング |
| `ci-engineering/` | CI/CD engineering guides, runner-platform reference notes / CI/CD エンジニアリングガイド、ランナープラットフォーム参考資料 |

Subdirectories are created on demand.

サブディレクトリは必要に応じて作成します。

---

## File Naming / ファイル命名規則

```
<slug>.<lang>.md
```

- `<slug>`: lowercase, hyphen-separated, descriptive / 小文字・ハイフン区切り・内容を端的に表す
- `<lang>`: `en` or `ja` / 言語コード
- Optional version suffix for evolving documents: `<slug>-v<N>.<M>.<lang>.md` / 進化する文書は版数サフィックス可

**Examples:**
```
documents/cloud-migration/fujitsu-middleware-legacy-modernization-v3.6.ja.md
documents/cost-analysis/azure-to-aws-migration-financial-model.en.md
```

---

## Required Metadata / 必須メタデータ

Each document should begin with the following:

各ドキュメントの冒頭には以下を記述します。

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
