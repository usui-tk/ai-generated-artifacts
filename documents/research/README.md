# research/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains AI-generated **research articles** — technical research, comparative analyses, market or technology surveys, and exploratory investigations.

**JA:** AI が生成した**リサーチ記事**（技術リサーチ、比較分析、市場・技術動向調査、探索的調査など）を格納します。

---

## What to Include / 収録対象

- Technical surveys (e.g., hyperscaler infrastructure comparisons, framework comparisons)
- Vendor/product comparative analyses
- Architectural pattern research
- Emerging technology investigations
- Reading notes synthesized from multiple sources

- 技術調査（例：ハイパースケーラーのインフラ比較、フレームワーク比較）
- ベンダー・製品の比較分析
- アーキテクチャパターンに関するリサーチ
- 新興技術の探索的調査
- 複数情報源を統合した読書ノート

## What NOT to Include / 収録対象外

- Executable code or scripts → `scripts/`
- Design documents, proposals, plans → `documents/`
- Slide decks → `presentations/`
- Reusable templates → `templates/`
- Certification study materials → `study-notes/`

- 実行可能なコード／スクリプト → `scripts/`
- 設計書・提案書・計画書 → `documents/`
- スライド資料 → `presentations/`
- 再利用可能なひな型 → `templates/`
- 認定試験対策資料 → `study-notes/`

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Articles are organized into **topic-based** subdirectories. Each topic has its own folder.

**JA:** 記事は**トピック別**にサブディレクトリで整理します。トピックごとに専用フォルダを作成します。

### Existing / 既存

| Subdirectory | Description |
|:---|:---|
| `cloud-infrastructure/` | Hyperscaler infrastructure, hardware, networking, storage / ハイパースケーラーインフラ、ハードウェア、ネットワーク、ストレージ |

### Possible Future Topics / 想定される将来トピック

`ai-models/`, `application-modernization/`, `data-platforms/`, `security/`, `developer-tools/`, `observability/`, ...

---

## File Naming / ファイル命名規則

```
<topic-slug>.<lang>.md
```

- `<topic-slug>`: lowercase, hyphen-separated, descriptive / 小文字・ハイフン区切り・内容を端的に表す
- `<lang>`: `en` (English) or `ja` (Japanese) / 言語コード
- Both `.en.md` and `.ja.md` are expected for bilingual articles / バイリンガル記事は両方作成

**Examples:**
```
research/cloud-infrastructure/hyperscaler-cloud-infrastructure-technology-survey.en.md
research/cloud-infrastructure/hyperscaler-cloud-infrastructure-technology-survey.ja.md
```

---

## Required Metadata / 必須メタデータ

Each article should begin with the following at the top of the file:

各記事の冒頭には以下を記述します。

- **Title** / タイトル
- **Executive summary or abstract** / エグゼクティブサマリまたは要旨
- **Scope and assumptions** / 調査範囲と前提条件
- **Generation context** (date, AI tool used, source materials if available) / 生成時の文脈（生成日、利用 AI ツール、参照資料）

---

## ⚠️ Disclaimer / 免責事項

All articles here are AI-generated and may contain **inaccuracies, outdated information, or factual errors**. Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer and self-responsibility terms.

本ディレクトリの記事はすべて AI 生成であり、**不正確な記述、情報の陳腐化、事実誤認**を含む可能性があります。完全な免責事項と自己責任条項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
