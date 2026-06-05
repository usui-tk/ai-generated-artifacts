# Contributing to {{REPO_NAME}}

> 🇯🇵 日本語版は本ファイル下部を参照してください。

Thank you for your interest in this repository. This is a **personal, public knowledge base** of AI-generated and AI-assisted artifacts. It is not an actively-developed software project; nevertheless, constructive feedback is welcomed.

---

## What this repository is — and is not

<!-- FILL: repo-specific "is / is not" framing. Common shape:
- **Is**: a long-term archive of AI-produced artifacts; conventions documented in README.md.
- **Is not**: a community-developed OSS project soliciting features, nor a substitute for official vendor documentation or production software.
-->

By interacting with this repository (issues, pull requests, references), you acknowledge the **Use at Your Own Risk** terms in the [root README](./README.md) and the per-directory disclaimers.

---

## How you can contribute

| Type | Where to file | Expected response |
|:---|:---|:---|
| **Factual corrections** (errors, broken commands, outdated versions) | GitHub Issue, label intent `correction` | Best-effort; no SLA |
| **Broken links / typos** | GitHub Issue or Pull Request | Best-effort; no SLA |
| **Security concerns** | See [Security policy](./SECURITY.md), or file a private advisory | Best-effort triage |
| **Suggestions / major restructuring** | GitHub Issue, label intent `discussion` | May or may not be incorporated |

The following are **not** expected to be acted on: feature requests unrelated to existing artifacts; "make this also support \<unrelated platform\>"; requests to add proprietary, NDA-protected, or closed-source content.

---

## Filing a good issue

1. **Which artifact** is affected — full path within the repo.
2. **What you expected vs. what you observed** — concrete, reproducible.
3. **Environment context** when relevant (OS version, runtime version, region, etc.).
4. **A proposed fix** if you have one, even informally.

For script-related issues, include the **phase ID** where the failure occurred and a 10-50 line log excerpt around the failure — not the whole log.

---

## Submitting a pull request

Pull requests are accepted but reviewed on a best-effort basis with no guaranteed timeline.

### Before opening a PR

- [ ] Read the relevant directory's `README.md` and any `SPEC.md` to understand local conventions.
- [ ] **Match the bilingual policy** of the file you touch (see the documentation language policy): twin-file documents (`README.md` + `README.ja.md`) and in-file-bilingual documents (`CODE_OF_CONDUCT.md` / `CONTRIBUTING.md` / `SECURITY.md`) are updated on both sides in the same commit.
- [ ] **Match the file-format policy**: `.ps1` / `.psm1` / `.psd1` are UTF-8 **with BOM** and **CRLF**; `.md` / `.py` / `.yml` / `.json` / `.jsonl` are UTF-8 **without BOM** and **LF**. Emit canonical bytes at the source and verify before `git add`.
- [ ] For PowerShell scripts, run the canonical analyzer to `0 errors / 0 warnings / 0 info`:
  ```bash
  python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1
  ```
- [ ] If you touch a project that ships a `SPEC.md`, re-check its **Part C — Quality Gates & Validation Checklist** before committing.
- [ ] Never commit real secrets (API keys, private account IDs, passwords, tokens).
- [ ] **For docs describing implementation behaviour** (`SPEC.md` / `README.md` / `TESTING.md`): verify factual claims against the script body, `param()` declarations, function inventory, and `tests/` BEFORE authoring — do not rely on prior docs as ground truth.
<!-- FILL: repo-specific extra checklist items (e.g. CI-workflow change rules, psa.py version-sync rule, AGENTS.md extraction-procedure references). -->

### PR description should include

- The **artifact path(s)** touched.
- A 1-3 sentence summary of the change.
- For SPEC / convention changes: whether downstream artifacts (scripts, `README.md`, `README.ja.md`, `TESTING.md`) need follow-up.
- For bilingual files: confirmation that both sides are in sync.

---

## Commit message convention

Loose convention; readability over rigidity:

```
<area>: <imperative summary>

<optional body explaining the why, not the what>
```

`<area>` is typically a top-level directory or a project name.

---

## Code of conduct

Be respectful, accurate, and constructive. Personal attacks, harassment, or attempts to push proprietary / NDA-protected content into the repository are not acceptable. See [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md).

---

## License

By submitting a pull request, you agree that your contribution is licensed under the [MIT License](./LICENSE) — the same license as the rest of the repository. Third-party trademarks, product names, and reference materials remain the property of their respective owners.

---

# 日本語版

# {{REPO_NAME}} への貢献について

本リポジトリにご関心をお寄せいただきありがとうございます。本リポジトリは AI が生成・支援したアーティファクトの **個人公開ナレッジベース** です。活発に開発されるソフトウェアプロジェクトではありませんが、建設的なフィードバックは歓迎します。

---

## 本リポジトリの位置づけ

<!-- FILL: repo 固有の「である/でない」記述(英語節と対応)。 -->

本リポジトリとやり取りする(Issue、Pull Request、参照)ことで、[ルート README](./README.ja.md) の **自己責任での利用** 条件およびディレクトリ毎の免責事項に同意したものとみなされます。

---

## 受け付けるコントリビューション

| 種別 | 起票先 | 想定対応 |
|:---|:---|:---|
| **事実誤りの訂正**(誤記、壊れたコマンド、古いバージョン) | GitHub Issue(intent `correction`) | ベストエフォート・SLA なし |
| **リンク切れ / 誤字** | GitHub Issue または Pull Request | ベストエフォート・SLA なし |
| **セキュリティ懸念** | [Security policy](./SECURITY.md) 参照、またはプライベート advisory | ベストエフォートでトリアージ |
| **提案 / 大規模な再構成** | GitHub Issue(intent `discussion`) | 取り込まれる場合と取り込まれない場合があります |

以下は対応を想定していません:既存アーティファクトと無関係な機能要望、「無関係なプラットフォーム対応の追加」要望、プロプライエタリ/NDA 保護/クローズドソースの内容追加要望。

---

## 質の高い Issue を起票するために

1. **どのアーティファクト** が対象か — リポジトリ内のフルパス
2. **期待した挙動と観測した挙動** — 具体的かつ再現可能に
3. **環境情報**(関連する場合: OS バージョン、ランタイムバージョン、リージョン等)
4. **修正案**(あれば。非公式でも可)

スクリプト関連の Issue では、失敗が発生した **フェーズ ID** と、失敗箇所前後の 10〜50 行のログ抜粋(全ログではなく)を添えてください。

---

## Pull Request を送る

Pull Request は受け付けますが、保証された期限なくベストエフォートでレビューします。

### PR 作成前のチェック

- [ ] 対象ディレクトリの `README.md` と該当する `SPEC.md` を読み、ローカル規約を把握する
- [ ] 触れるファイルの **bilingual 方針** に従う:twin-file(`README.md` + `README.ja.md`)および in-file bilingual(`CODE_OF_CONDUCT.md` / `CONTRIBUTING.md` / `SECURITY.md`)は同一コミットで両側を更新する
- [ ] **ファイルフォーマット方針** に従う:`.ps1` / `.psm1` / `.psd1` は UTF-8 **BOM 付き**・**CRLF**、`.md` / `.py` / `.yml` / `.json` / `.jsonl` は UTF-8 **BOM なし**・**LF**。生成元で正準バイト列を出力し、`git add` 前に検証する
- [ ] PowerShell スクリプトは正準アナライザを `0 errors / 0 warnings / 0 info` まで実行:
  ```bash
  python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1
  ```
- [ ] `SPEC.md` を持つプロジェクトに触れる場合、その **Part C — Quality Gates & Validation Checklist** をコミット前に再確認する
- [ ] 実在の機密情報(API キー、非公開アカウント ID、パスワード、トークン)を絶対にコミットしない
- [ ] **実装挙動を記述するドキュメント**(`SPEC.md` / `README.md` / `TESTING.md`)は、スクリプト本体・`param()`・関数一覧・`tests/` に対して事実確認してから執筆する(既存ドキュメントを ground truth にしない)
<!-- FILL: repo 固有の追加チェック項目(英語節と対応)。 -->

### PR 説明に含めるべき内容

- 触れた **アーティファクトのパス**
- 変更の 1〜3 文要約
- SPEC/規約変更の場合:下流アーティファクト(スクリプト、`README.md`、`README.ja.md`、`TESTING.md`)の追従要否
- bilingual ファイルの場合:両側が同期している旨の確認

---

## コミットメッセージ規約

緩やかな規約(厳密さより可読性):

```
<area>: <命令形の要約>

<なぜ変更したか(何を、ではなく)を説明する任意の本文>
```

`<area>` は通常トップレベルディレクトリ名またはプロジェクト名です。

---

## 行動規範

敬意を持ち、正確かつ建設的に。個人攻撃・ハラスメント、プロプライエタリ/NDA 保護内容の押し込みは受け付けません。[`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) 参照。

---

## ライセンス

Pull Request を送ることで、あなたの貢献がリポジトリ全体と同じ [MIT License](./LICENSE) の下でライセンスされることに同意したものとします。第三者の商標・製品名・参照資料は各権利者に帰属します。
