# presentations/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains AI-generated **presentation materials** — slide decks for technical topics, strategy briefings, training, or knowledge sharing.

**JA:** AI が生成した**プレゼンテーション資料**（技術トピック、戦略説明、教育・トレーニング、ナレッジ共有用のスライドデック）を格納します。

---

## What to Include / 収録対象

- PowerPoint (`.pptx`) decks
- Markdown-based slide decks (Marp, Slidev, reveal.js)
- PDF exports of slide decks (for archival)
- Speaker notes accompanying slides

- PowerPoint（`.pptx`）デック
- Markdown ベースのスライドデック（Marp、Slidev、reveal.js など）
- アーカイブ用 PDF エクスポート
- スライドの登壇者ノート

## What NOT to Include / 収録対象外

- Long-form documents that happen to have headings → `documents/`
- Research articles → `research/`
- Slide templates / master files → `templates/`
- Slides containing real client logos, photos, or confidential content → **anywhere in this repo**

- 見出しがあるだけの長文ドキュメント → `documents/`
- リサーチ記事 → `research/`
- スライドのひな型・マスターファイル → `templates/`
- 実顧客のロゴ・写真・機密内容を含むスライド → **本レポジトリのどこにも置かない**

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Presentations are organized by **theme** as the primary axis.

**JA:** プレゼンテーションは**テーマ**を主軸として整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `cloud-migration/` | Migration patterns, lift-and-shift vs refactoring / 移行パターン、Lift & Shift vs Refactoring |
| `ai-strategy/` | AI adoption, generative AI case studies / AI 導入、生成 AI 事例 |
| `cloud-architecture/` | Architecture overviews, design patterns / アーキテクチャ概要、設計パターン |
| `training/` | Internal training and onboarding decks / 社内研修・オンボーディング |

Subdirectories are created on demand.

サブディレクトリは必要に応じて作成します。

---

## File Naming / ファイル命名規則

```
<slug>.<lang>.<ext>
```

- `<slug>`: lowercase, hyphen-separated, descriptive / 小文字・ハイフン区切り・内容を端的に表す
- `<lang>`: `en` or `ja` / 言語コード
- `<ext>`: `pptx` (PowerPoint), `md` (Markdown slides), `pdf` (archived export)
- For source + export pairs, share the slug: `<slug>.ja.pptx` + `<slug>.ja.pdf` / ソースとエクスポートはスラッグを共通化

**Examples:**
```
presentations/cloud-migration/lift-and-shift-vs-refactoring.ja.pptx
presentations/cloud-migration/lift-and-shift-vs-refactoring.ja.pdf
presentations/ai-strategy/tmn-systems-genai-case-study.ja.pptx
```

---

## Required Metadata / 必須メタデータ

Each deck should include the following on its title or opening slide:

各デックの表紙またはオープニングスライドに以下を含めます。

- **Title** / タイトル
- **Audience** / 想定対象者
- **Created / Last updated date** / 作成日・最終更新日
- **Generation context** (AI tool used, source materials) / 生成時の文脈（利用 AI ツール、参照資料）

A closing or speaker-notes slide should include a brief AI-generated disclaimer.

末尾またはノートに、AI 生成資料である旨の免責を簡潔に記載します。

---

## File Size Consideration / ファイルサイズ留意

PowerPoint files with embedded images can be large. Keep individual decks **under 25 MB** where possible. For large decks, consider:

埋め込み画像を含む PowerPoint は容量が大きくなりがちです。1 ファイル **25 MB 未満**を目安にしてください。大容量の場合は以下を検討します。

- Compressing embedded images / 埋め込み画像を圧縮
- Splitting into multiple decks / 複数デックに分割
- Linking to external image sources rather than embedding / 埋め込みではなく外部画像をリンク

---

## ⚠️ Disclaimer / 免責事項

All presentations are AI-generated and may contain **inaccuracies, outdated information, or factual errors**. Verify content before using publicly. Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer.

すべてのプレゼンテーション資料は AI 生成であり、**不正確な記述、情報の陳腐化、事実誤認**を含む可能性があります。公的に利用される前に必ず内容を検証してください。完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
