# study-notes/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains AI-generated or AI-assisted **study notes** — organized study materials for certifications and technical learning topics.

**JA:** AI が生成・支援した**学習ノート**（認定試験対策、技術習得トピックの整理ノート）を格納します。

---

## What to Include / 収録対象

- Certification exam preparation notes (organized by exam code/topic)
- Technical learning summaries
- Concept explanations and cheat sheets
- Cross-references between related concepts
- Personal annotations and mnemonic aids

- 認定試験対策ノート（試験コード・トピック別）
- 技術学習のサマリ
- 概念解説、チートシート
- 関連概念間のクロスリファレンス
- 個人的なメモ・記憶補助

## What NOT to Include / 収録対象外

- **Verbatim or near-verbatim exam questions** (copyright violation) — **試験問題の逐語的または近似的な転載**（著作権侵害）
- Copyrighted training material content (textbooks, official course material) — 著作権で保護された教材の内容（書籍、公式コース教材）
- Brain dumps or material obtained through NDA violations — 試験秘密保持契約違反で得た情報
- Materials sourced from unauthorized leak repositories — 流出元から取得した資料

⚠️ **EN: This is a STRICT rule.** Study notes here must be synthesized from public, licensed, or self-generated sources — not from confidential exam content, which would violate the certification's NDA and put your certification at risk.

⚠️ **JA: これは厳格なルールです。** 本ディレクトリの学習ノートは、公開資料・正規ライセンス資料・自己作成資料からの統合のみとし、機密扱いの試験コンテンツは含めません。後者は受験規約違反に該当し、認定資格そのものが取り消されるリスクがあります。

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Study notes are organized by **vendor/topic family** at the first level, and by **specific exam or topic** at the second level.

**JA:** 学習ノートは第一階層で**ベンダー／トピックファミリー**、第二階層で**個別試験・トピック**で整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `aws/` | AWS certification notes (DOP-C02, SAP-C02, etc.) / AWS 認定試験ノート |
| `azure/` | Azure certification notes (AZ-204, AI-102, etc.) / Azure 認定試験ノート |
| `gcp/` | Google Cloud certification notes / Google Cloud 認定試験ノート |
| `oci/` | Oracle Cloud certification notes (e.g., OCI AI Foundations) / OCI 認定試験ノート |
| `github/` | GitHub certifications (Advanced Security, Administration, Actions) / GitHub 認定試験ノート |
| `microsoft-fundamentals/` | Microsoft fundamentals (AI-900, AZ-900, etc.) / Microsoft Fundamentals 系 |

Subdirectories are created on demand.

サブディレクトリは必要に応じて作成します。

---

## File Naming / ファイル命名規則

```
<exam-code>-<topic-slug>.<lang>.md      # for certification topics
<topic-slug>.<lang>.md                  # for general technical topics
```

- For certification-related notes, lead with the exam code / 認定試験関連は試験コードを先頭に
- `<lang>`: `en` or `ja` / 言語コード
- Group notes for a single exam in one subdirectory / 1試験の関連ノートは同じサブディレクトリにまとめる

**Examples:**
```
study-notes/aws/dop-c02-monitoring-and-logging.ja.md
study-notes/aws/dop-c02-incident-response.ja.md
study-notes/azure/az-204-app-service.ja.md
study-notes/github/ghas-secret-scanning.ja.md
```

---

## Required Structure / 推奨構成

Each note should include:

各ノートには以下を含めます。

- **Topic / Exam reference** / トピック／対象試験
- **Source materials** (links to official docs, public articles used) / 参照資料（公式ドキュメント・公開記事へのリンク）
- **Key concepts** in your own words / 自分の言葉でまとめた主要概念
- **Common pitfalls and gotchas** / よくある落とし穴・注意点
- **Last updated** / 最終更新日
- **Generation context** (AI tool used) / 生成時の文脈（利用 AI ツール）

---

## Citation Policy / 引用方針

When referencing official documentation or public articles:

公式ドキュメントや公開記事を参照する際は以下に従います。

- **Always cite the source URL** / 必ず出典 URL を記載
- **Paraphrase rather than copy** / 逐語コピーではなく言い換える
- **Quote sparingly** (short snippets only, properly attributed) / 引用は最小限（短い断片のみ、適切に出典明示）
- **Respect the source's license** / 出典のライセンスを尊重

---

## ⚠️ Disclaimer / 免責事項

Study notes are AI-generated and may contain **errors, outdated information, or misinterpretations** of exam objectives. They are **not a substitute for official study material** and may not reflect the most current exam content. Always cross-reference with the official exam guide and authoritative sources before relying on these notes for exam preparation.

学習ノートは AI 生成であり、**誤り、情報の陳腐化、試験目標の誤解**を含む可能性があります。**公式学習教材の代替ではなく**、最新の試験内容を反映していない可能性があります。試験対策として依拠する前に、必ず公式試験ガイドおよび信頼できる情報源と相互参照してください。

Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer.

完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
