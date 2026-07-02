# Contributing to ai-generated-artifacts

> 🇯🇵 日本語版は本ファイル下部を参照してください。

Thank you for your interest in this repository. This is a **personal, public knowledge base** of AI-generated and AI-assisted artifacts (primarily authored with Anthropic Claude). It is not an actively-developed software project; nevertheless, constructive feedback is welcomed.

---

## What this repository is — and is not

- **Is**: A long-term archive of AI-produced research, scripts, design documents, presentations, templates, prompts, and study notes. Conventions and structure are documented in [`README.md`](./README.md).
- **Is not**: A community-developed open-source project soliciting feature contributions, nor a substitute for official vendor documentation, certification material, or production-ready software.

By interacting with this repository (issues, pull requests, references), you acknowledge the **Use at Your Own Risk** terms in the [root README](./README.md) and the per-directory disclaimers.

---

## How you can contribute

The following contributions are welcomed:

| Type | Where to file | Expected response |
|:---|:---|:---|
| **Factual corrections** (errors in research articles, broken commands in scripts, outdated version numbers) | GitHub Issue with the label intent `correction` | Best-effort; no SLA |
| **Broken links / typos** | GitHub Issue or Pull Request | Best-effort; no SLA |
| **Security concerns** (a script behaving unsafely, exposed credential pattern in an example) | See [Security policy](./SECURITY.md) if present, otherwise email the maintainer or file a private security advisory | Best-effort triage |
| **Suggestions for new artifact categories or major restructuring** | GitHub Issue with the label intent `discussion` | May or may not be incorporated |

The following are **not** expected to be acted on:

- Feature requests unrelated to existing artifacts.
- "Make this script also support \<unrelated platform\>" — out of scope.
- Requests to add or merge proprietary, NDA-protected, or closed-source content.

---

## Filing a good issue

A high-quality issue includes:

1. **Which artifact** is affected — full path within the repo (e.g., `projects/bash-ol-aws-ami-builder/SPEC.md` §B.3.2).
2. **What you expected vs. what you observed** — concrete, reproducible.
3. **Environment context** when relevant (OS version, PowerShell version, AWS region, etc.).
4. **A proposed fix** if you have one, even informally.

For script-related issues, include the **phase ID** where the failure occurred (e.g., `Phase 5 of build-ol-aws-ami.sh`) and a 10–50 line log excerpt around the failure — not the whole log.

---

## Submitting a pull request

Pull requests are accepted but reviewed on a best-effort basis with no guaranteed timeline.

### Before opening a PR

- [ ] Read the relevant directory's `README.md` and any `SPEC.md` to understand the conventions in that area.
- [ ] Match the **bilingual policy** of the file you are touching: if the original is bilingual (`<NAME>.md` + `<NAME>.ja.md`), update both in the same commit. See [`README.md`](./README.md) → "Naming Conventions" and "Language Policy".
- [ ] **Match the file-format policy** for every file you create or edit. `.ps1` / `.psm1` / `.psd1` must be UTF-8 with BOM and CRLF line endings; `.md` / `.py` / `.yml` / `.json` / etc. must be UTF-8 without BOM and LF-only line endings. AI-agent file generation and Python helper scripts default to the wrong form on Linux / macOS hosts — always emit canonical bytes at the source and verify before `git add`. See [`README.md`](./README.md) → "File Format Policy" for the per-extension contract, tooling rules, and pre-commit verification commands.
- [ ] Run any applicable static checks. For PowerShell scripts under this repository, this includes the canonical `psa.py` analyzer:
  ```bash
  python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1
  ```
  See [`quality-tools/powershell-static-analyzer/README.md`](./quality-tools/powershell-static-analyzer/README.md) → "Usage". `psa.py` rules `PSA7001` (UTF-8 BOM presence) and `PSA7002` (LF-only / mixed line endings, new in v3.7.0) enforce the file-format policy at lint time.
- [ ] **For PowerShell changes: verify `psa.py` is at the latest mainline version before validating.** Compare the mainline `VERSION` against your local copy and refresh both `psa.py` + `VERSION` together if they differ. See [`README.md`](./README.md) → "psa.py Versioning Policy" for the full workflow.
- [ ] If you touch a project under `projects/<lang>-<project>/` that ships a `SPEC.md`, verify the corresponding **Part C — Quality Gates & Validation Checklist** before committing.
- [ ] **For CI workflow changes (anything under `.github/workflows/`, the `PSScriptAnalyzerSettings.psd1` files, or the root [`SPEC.md`](./SPEC.md)): read [`SPEC.md`](./SPEC.md) first, then record the change in the CI-target script's `CHANGELOG.md` — never in a separate location ([`SPEC.md`](./SPEC.md#9-spec-ci-070-ci-change-history-location) §9 forbids `.github/workflows/CHANGELOG.md` and similar).**
- [ ] Never commit real secrets (API keys, account IDs you wish to keep private, passwords, tokens). See [`README.md`](./README.md) → "No credentials in artifacts".
- [ ] **For doc changes that describe implementation behaviour (`SPEC.md` / `README.md` / `TESTING.md`):** verify factual claims against the script body, `param()` declarations, function inventory, and `tests/` contents BEFORE authoring. Do not rely on prior documentation as ground truth — prior docs may themselves be stale or drifted. See [`AGENTS.md` §4](./AGENTS.md#4-implementation-ground-truth-extraction) for the canonical extraction procedure.

### PR description should include

- The **artifact path(s)** touched.
- A 1–3 sentence summary of the change.
- For SPEC / convention changes: a note on whether downstream artifacts (scripts, `README.md`, `README.ja.md`, `TESTING.md`) need follow-up updates. See [`AGENTS.md` §5](./AGENTS.md#5-spec--readme--testing-doc-touching-matrix) for the canonical matrix mapping SPEC sections to their downstream impact zones.
- For bilingual files: confirmation that both `<NAME>.md` and `<NAME>.ja.md` are in sync.

---

## Commit message convention

Loose convention; readability over rigidity:

```
<area>: <imperative summary>

<optional body explaining the why, not the what>
```

Examples:

```
docs: fix broken link to AWS VM Import/Export documentation
projects/bash-ol-aws-ami-builder: update OL10 ISO checksum for U2 release
research/cloud-infrastructure: correct CPU SKU naming in EPYC Bergamo section
```

`<area>` is typically a top-level directory (`docs`, `projects/...`, `documents/...`) or a project name.

---

## Code of conduct

Be respectful, accurate, and constructive. Personal attacks, harassment, or attempts to push proprietary / NDA-protected content into the repository are not acceptable.

---

## License

By submitting a pull request, you agree that your contribution is licensed under the [MIT License](./LICENSE) — the same license as the rest of the repository. Third-party trademarks, product names, and reference materials remain the property of their respective owners.

---

# 日本語版

# ai-generated-artifacts への貢献について

本リポジトリは、**AI ツール(主に Anthropic Claude)で生成または支援されたアーティファクト**を集約した、個人運用の公開ナレッジベースです。継続的に開発されるソフトウェアプロジェクトではありませんが、建設的なフィードバックは歓迎します。

---

## 本リポジトリの位置づけ

- **本リポジトリは**:AI が生成したリサーチ、スクリプト、設計書、プレゼン資料、テンプレート、プロンプト、学習ノートを長期保管するアーカイブです。規約と構造は [`README.ja.md`](./README.ja.md) に明記されています。
- **本リポジトリでは**:コミュニティ駆動の OSS プロジェクトとして機能追加要望を募集しているわけではなく、また、ベンダー公式ドキュメントや認定教材、本番運用ソフトウェアの代替を意図したものでもありません。

本リポジトリ(Issue・Pull Request・参照を含む)を利用する場合は、[ルート README](./README.ja.md) の **「自己責任での利用について」** および各ディレクトリ固有の免責事項に同意したものとみなされます。

---

## 受け付けるコントリビューション

| 種別 | 起票先 | 対応方針 |
|:---|:---|:---|
| **事実関係の訂正**(リサーチ記事の誤り、スクリプト内コマンドの不備、バージョン番号陳腐化など) | GitHub Issue(意図ラベル `correction`) | ベストエフォート、SLA なし |
| **リンク切れ・誤字** | GitHub Issue または Pull Request | ベストエフォート、SLA なし |
| **セキュリティ上の懸念**(スクリプトの危険な挙動、認証情報がサンプルに混入等) | [Security policy](./SECURITY.md)(存在する場合)経由、または GitHub Security Advisory(プライベート報告) | ベストエフォートでトリアージ |
| **新カテゴリ提案・大規模再編の提案** | GitHub Issue(意図ラベル `discussion`) | 取り込みは保証しません |

以下は対応対象外です:

- 既存アーティファクトと関連性のない機能要望
- 「このスクリプトを別プラットフォームにも対応してほしい」(スコープ外)
- 商用 / NDA 保護 / クローズドソースコンテンツの追加・統合依頼

---

## 質の高い Issue を起票するために

1. **対象アーティファクト**:リポジトリ内のフルパス(例:`projects/bash-ol-aws-ami-builder/SPEC.md` §B.3.2)
2. **期待した挙動 / 実際の挙動**:再現可能な形で具体的に
3. **環境コンテキスト**:OS バージョン、PowerShell バージョン、AWS リージョン等(関連する場合)
4. **修正案**:あれば(非公式でも可)

スクリプト関連の Issue では、失敗が発生した **フェーズ ID**(例:`build-ol-aws-ami.sh の Phase 5`)と、失敗箇所周辺の **10〜50 行のログ抜粋**(ログ全体は不要)を添付してください。

---

## Pull Request を送る前に

PR はベストエフォートで受け付けます(レビュー期限は保証しません)。

### PR 作成前のチェック

- [ ] 対象ディレクトリの `README.md` と関連する `SPEC.md` を読んで当該エリアの規約を理解する
- [ ] 変更対象のファイルの **バイリンガル規約** に従う:原版がバイリンガル(`<NAME>.md` + `<NAME>.ja.md`)の場合、同一コミットで両方更新する。詳細は [`README.ja.md`](./README.ja.md) の「命名規則」と「言語ポリシー」を参照
- [ ] **ファイル形式ポリシー** に従う。 `.ps1` / `.psm1` / `.psd1` は UTF-8 with BOM + CRLF、 `.md` / `.py` / `.yml` / `.json` 等は UTF-8 without BOM + LF-only でなければならない。 AI エージェントによるファイル生成や Python ヘルパースクリプトは Linux / macOS ホスト上ではデフォルトで誤った形式 (LF-only) を生成する — オーサリング時点で正本バイトを書き出し、 `git add` 前に検証すること。 拡張子ごとの規約・ツーリング規則・コミット前検証コマンドは [`README.ja.md`](./README.ja.md) の「ファイル形式ポリシー」を参照
- [ ] 該当する静的チェックを実行する。本リポジトリの PowerShell スクリプトについては、正規配置の `psa.py` を必ず使用:
  ```bash
  python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1
  ```
  詳細は [`quality-tools/powershell-static-analyzer/README.ja.md`](./quality-tools/powershell-static-analyzer/README.ja.md) の「使い方」を参照。 `psa.py` の `PSA7001`（UTF-8 BOM の存在チェック）と `PSA7002`（LF-only / 改行コード混在、 v3.7.0 新規）がファイル形式ポリシーを lint 時に強制する
- [ ] **PowerShell 変更時: 検証前に `psa.py` が latest mainline バージョンであることを確認する。** mainline の `VERSION` をローカルコピーと比較し、 異なる場合は `psa.py` と `VERSION` の両方を一緒に更新する。 詳細ワークフローは [`README.ja.md`](./README.ja.md) の「psa.py のバージョニングポリシー」セクションを参照
- [ ] `projects/<lang>-<project>/` 配下で `SPEC.md` を持つプロジェクトを変更する場合、コミット前に対応する **Part C — 品質ゲートと検証チェックリスト** を確認する
- [ ] **CI ワークフローの変更 (`.github/workflows/` 配下、 `PSScriptAnalyzerSettings.psd1` ファイル、 ルート [`SPEC.md`](./SPEC.md) のいずれか) を行う場合: まず [`SPEC.md`](./SPEC.md) を読み、 変更内容を CI 対象スクリプトの `CHANGELOG.md` に記録する — 別の場所に記録してはならない ([`SPEC.md`](./SPEC.md#9-spec-ci-070-ci-change-history-location) §9 が `.github/workflows/CHANGELOG.md` 等の作成を禁止している)。**
- [ ] 実在の機密情報(API キー、非公開アカウント ID、パスワード、トークン)を **絶対にコミットしない**。[`README.ja.md`](./README.ja.md) の「アーティファクトに認証情報を埋め込まないでください」を参照
- [ ] **実装挙動を記述するドキュメント変更時(`SPEC.md` / `README.md` / `TESTING.md`):** 執筆 **前** に、スクリプト本体、`param()` 宣言、関数一覧、`tests/` 内容に照らして事実関係を検証する。過去のドキュメントを ground truth として信用しないこと(過去ドキュメント自体が陳腐化・乖離している可能性がある)。 抽出手順の正典は [`AGENTS.md` §4](./AGENTS.md#4-implementation-ground-truth-extraction) を参照

### PR 説明に含めるべき内容

- 変更対象の **アーティファクトパス**
- 変更の 1〜3 文サマリ
- SPEC や規約変更の場合:下流アーティファクト(スクリプト・`README.md`・`README.ja.md`・`TESTING.md`)で追従更新が必要かの注記。SPEC のどの章を変更すると下流のどこに影響するかの正典マトリクスは [`AGENTS.md` §5](./AGENTS.md#5-spec--readme--testing-doc-touching-matrix) を参照
- バイリンガルファイル:`<NAME>.md` と `<NAME>.ja.md` の両方が同期されていることの確認

---

## コミットメッセージ規約

厳格な規約ではなく、可読性優先:

```
<area>: <命令形のサマリ>

<オプション:why を補足するボディ>
```

例:

```
docs: fix broken link to AWS VM Import/Export documentation
projects/bash-ol-aws-ami-builder: update OL10 ISO checksum for U2 release
research/cloud-infrastructure: correct CPU SKU naming in EPYC Bergamo section
```

`<area>` は通常、トップレベルディレクトリ名(`docs`、`projects/...`、`documents/...` 等)、またはプロジェクト名とします。

---

## 行動規範

敬意・正確性・建設性を保ってください。個人攻撃、ハラスメント、または商用・NDA 保護コンテンツのリポジトリ持ち込みは受け付けません。

---

## ライセンス

Pull Request を送信することにより、貢献内容を本リポジトリと同一の [MIT License](./LICENSE) のもとで提供することに同意したものとします。アーティファクト内で言及される第三者の商標・製品名・参照素材は、それぞれの権利者に帰属します。
