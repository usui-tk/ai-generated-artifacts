# prompts/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains **reusable AI prompts** — system prompts, prompt frameworks, and tested prompt patterns for specific tasks.

**JA:** **再利用可能な AI プロンプト**（システムプロンプト、プロンプトフレームワーク、特定タスク向けに検証済みのプロンプトパターン）を格納します。

---

## What to Include / 収録対象

- System prompts that define a persistent AI role or behavior
- Task-specific prompt templates with placeholders
- Multi-turn prompt sequences (chain-of-thought, role-play patterns)
- Notes on what worked, what didn't, and known limitations of each prompt
- Comparative notes across multiple AI tools (Claude, ChatGPT, Gemini) where applicable

- AI に持続的な役割・振る舞いを与えるシステムプロンプト
- プレースホルダを持つタスク特化型プロンプトテンプレート
- マルチターン構成のプロンプトシーケンス（思考連鎖、ロールプレイなど）
- 各プロンプトで「うまくいったこと／いかなかったこと／既知の制約」のメモ
- 該当する場合は、複数 AI ツール（Claude、ChatGPT、Gemini）間の比較メモ

## What NOT to Include / 収録対象外

- Conversation logs / chat transcripts (these belong elsewhere or stay private) — 会話ログ・チャット履歴（公開対象外、または非公開保持）
- API keys, account IDs, or any credentials / API キー、アカウント ID、認証情報の類
- Prompts designed to bypass safety or generate harmful output / 安全装置の回避や有害出力を目的としたプロンプト
- Confidential business prompts containing proprietary methodology / 独自方法論を含む機密のビジネスプロンプト

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Prompts are organized by **purpose** as the primary axis.

**JA:** プロンプトは**用途**を主軸として整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `translation/` | Translation prompts (e.g., bilingual markdown, locale handling) / 翻訳プロンプト |
| `document-generation/` | Document generation prompts (reports, specs, ADRs) / ドキュメント生成プロンプト |
| `code-review/` | Code review and analysis prompts / コードレビュー・分析プロンプト |
| `research/` | Research and investigation prompts / 調査・リサーチプロンプト |
| `summarization/` | Summarization and synthesis prompts / 要約・統合プロンプト |
| `migration/` | Migration analysis and planning prompts / 移行分析・計画プロンプト |

Subdirectories are created on demand.

サブディレクトリは必要に応じて作成します。

---

## File Naming / ファイル命名規則

```
<slug>.<lang>.md
```

- `<slug>`: lowercase, hyphen-separated, descriptive of the prompt purpose / 小文字・ハイフン区切り・プロンプトの目的を端的に表す
- `<lang>`: `en` or `ja` / 言語コード（プロンプトを記述している言語）
- If a prompt is fundamentally identical in English and Japanese, provide both files / プロンプトの本質が日英で同等の場合は両方提供

**Examples:**
```
prompts/translation/markdown-bilingual-translator.en.md
prompts/translation/markdown-bilingual-translator.ja.md
prompts/document-generation/adr-from-discussion-summary.ja.md
prompts/research/hyperscaler-feature-comparison.en.md
```

---

## Required Structure / 必須構成

Each prompt file should follow this structure:

各プロンプトファイルは以下の構成に従います。

```markdown
# <Prompt Name>

## Purpose / 目的
What this prompt is for / このプロンプトの目的

## Target AI Tools / 対象AIツール
e.g., Claude (Sonnet 4.6+), ChatGPT (GPT-4o+), Gemini

## Input Variables / 入力変数
- `{{VARIABLE_1}}`: description
- `{{VARIABLE_2}}`: description

## Prompt Body / プロンプト本体
\`\`\`
[The actual prompt text here]
\`\`\`

## Usage Notes / 利用上の注意
- Recommended model
- Token consumption rough estimate
- Known limitations or failure modes

## Tested Examples / 検証済み事例
Brief notes on prior usage and outcomes
```

---

## Versioning / 版数管理

Prompts evolve. For significant changes, append a version suffix:

プロンプトは進化します。重要な変更時は版数サフィックスを付与します。

```
markdown-bilingual-translator-v2.ja.md
```

The previous version may be kept for comparison but mark deprecated ones clearly within the file.

旧版は比較のため保持して構いませんが、ファイル冒頭に廃止予定であることを明記します。

---

## ⚠️ Disclaimer / 免責事項

AI prompts produce non-deterministic output. The same prompt may yield different results across models, model versions, or even repeat runs on the same model. **Always review AI output before use.** Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer.

AI プロンプトの出力は非決定的です。同じプロンプトでもモデル・モデルバージョン・実行のたびに異なる結果になり得ます。**AI 出力は必ず利用前にレビューしてください。** 完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
