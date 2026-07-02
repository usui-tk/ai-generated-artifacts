# Security Policy

> 🇯🇵 日本語版は本ファイル下部を参照してください。

## Scope

This repository (`ai-generated-artifacts`) is a **personal knowledge base** of AI-generated and AI-assisted artifacts. It does **not** host a deployed service, library, or production software. Accordingly, this policy covers:

| In scope | Out of scope |
|:---|:---|
| Scripts in this repository that, **when executed by a user**, behave in a way that introduces a security risk on the user's system (e.g., unsafe defaults, missing input validation, credential exposure, insecure download patterns) | Vulnerabilities in third-party tools the scripts wrap (`oracle-linux-image-tools`, AWS CLI, `psa.py`'s dependencies, etc.) — report those upstream |
| Documentation, prompts, or templates that, if used verbatim, would lead a reader to make a clearly unsafe operational decision (e.g., disabling Secure Boot without warning) | Generic discussions about AI-generated code being potentially unsafe — the [root README](./README.md) disclaimer already covers this comprehensively |
| Real secrets accidentally committed to this repository (API keys, tokens, account IDs the maintainer intends to keep private) | The maintainer's other public information that you found via OSINT — that is not a leak |

## Reporting a vulnerability

**Please do NOT open a public GitHub Issue for security-impacting reports.**

Instead, use one of the following private channels:

1. **GitHub Security Advisory (preferred)** — open a private security advisory at <https://github.com/usui-tk/ai-generated-artifacts/security/advisories/new>. This creates a private discussion thread visible only to you and the maintainer.
2. **Direct contact** — if you cannot use GitHub's security advisory feature, you may contact the maintainer through the email address listed on their GitHub profile (<https://github.com/usui-tk>).

Please include:

- **Affected artifact path** within the repository (e.g., `projects/bash-ol-aws-ami-builder/build-ol-aws-ami.sh`).
- **Concrete reproduction** — a command sequence, an input file, or a step-by-step description.
- **Observed impact** — what an attacker (or unwary user) could do as a result.
- **Suggested fix** if you have one.

## Response expectations

- **Acknowledgement**: best effort, typically within 7 days. No SLA is guaranteed; this is a personal repository.
- **Triage outcome**: the maintainer will reply with one of: *accepted (will fix)*, *accepted (will document, not fix)*, *out of scope (with reason)*, *duplicate*, or *won't fix (with reason)*.
- **Disclosure timeline**: coordinated disclosure is preferred. If a fix is planned, please allow a reasonable window (typically 30–90 days depending on severity) before public discussion.
- **Credit**: with your permission, the reporter is credited in the relevant commit message and/or the artifact's revision history. You may also request to remain anonymous.

## What this repository does NOT promise

- A defined turnaround time.
- Backported fixes to historical revisions.
- Compensation, bug bounty, or any monetary reward.
- That every reported issue will be acted upon — see "out of scope" above.

## Hardening already in place

For completeness, the following are already enforced by the repository:

- Artifacts must **never** contain real secrets (`API keys`, `passwords`, `tokens`, sensitive account IDs). See [`README.md`](./README.md) → "No credentials in artifacts".
- PowerShell scripts in this repository are verified with [`psa.py`](./quality-tools/powershell-static-analyzer/) which includes security-class rules (`PSA5xxx`) for plain-text password parameters, `Invoke-Expression` usage, broken hash algorithms, and hardcoded `ComputerName`.
- All scripts ship with a `## ⚠️ Disclaimer` section near the top of their README per repo convention (canonical policy home: the root [`README.md`](./README.md) "Use at Your Own Risk" / "AI-Generated Content Disclaimer" sections; the per-doc format canon lives under `governance/doc-format/`).
- CI workflows under `.github/workflows/` carry a fork-PR `if`-guard that prevents fork-origin pull requests from running CI automatically (see [`SPEC.md`](./SPEC.md#5-spec-ci-030-fork-pr-handling) §5). Reviews of fork PRs follow the human + AI-assisted protocol documented in the same section.

## Future security considerations

Five candidate hardening measures for the CI surface (maintainer
approval gate for fork-PR runs, SHA-pinning of third-party actions,
`CODEOWNERS`-based pre-merge enforcement, delayed-execution window
for `workflow_run` on fork-origin events, and an automated diff-review
workflow via the Anthropic API) are documented in [`SPEC.md`](./SPEC.md#8-spec-ci-060-future-security-considerations) §8. None are
implemented at the time of writing; the section also lists the trigger
conditions that would prompt the maintainer to revisit them.

---

# 日本語版

# セキュリティポリシー

## 対象範囲

本リポジトリ(`ai-generated-artifacts`)は、AI が生成・支援したアーティファクトを集約した **個人ナレッジベース** です。稼働サービス・ライブラリ・本番ソフトウェアをホストするものではありません。したがって本ポリシーの対象は以下です:

| 対象 | 対象外 |
|:---|:---|
| 本リポジトリのスクリプトが **利用者によって実行された際に**、利用者のシステムにセキュリティリスクを及ぼす挙動を示す事象(安全でないデフォルト、入力検証の欠如、認証情報の露出、安全でないダウンロードパターン等) | スクリプトが利用する第三者ツール(`oracle-linux-image-tools`、AWS CLI、`psa.py` の依存パッケージ等)の脆弱性 — 該当する上流に報告してください |
| ドキュメント、プロンプト、テンプレートを文字通り従ったときに、読者が明らかに危険な運用判断を下すことになるもの(例:警告なしに Secure Boot を無効化させる手順) | 「AI 生成コードは安全でないことがある」という一般論 — [ルート README](./README.ja.md) の免責事項で網羅されています |
| 本リポジトリに誤ってコミットされた実在の機密情報(API キー、トークン、メンテナが非公開を意図したアカウント ID 等) | OSINT で発見されたメンテナのその他の公開情報 — それは漏洩ではありません |

## 脆弱性の報告方法

**セキュリティに影響する事項について、公開の GitHub Issue を起票しないでください。**

代わりに以下のプライベートチャンネルを利用してください:

1. **GitHub Security Advisory(推奨)** — <https://github.com/usui-tk/ai-generated-artifacts/security/advisories/new> でプライベート advisory を作成。報告者とメンテナのみが閲覧できるスレッドが作られます。
2. **直接連絡** — GitHub の Security Advisory が利用できない場合は、メンテナの GitHub プロフィール(<https://github.com/usui-tk>)に記載のメールアドレスへ連絡してください。

報告時には以下を含めてください:

- **対象アーティファクトのパス**(例:`projects/bash-ol-aws-ami-builder/build-ol-aws-ami.sh`)
- **具体的な再現手順** — コマンド列、入力ファイル、ステップバイステップの説明等
- **観測された影響** — 攻撃者(または不注意な利用者)が結果として何ができるか
- **修正案**(あれば)

## 対応の目安

- **受領確認**:ベストエフォート、概ね 7 日以内。SLA の保証はありません(個人リポジトリのため)
- **トリアージ結果**:メンテナは以下のいずれかで返答します — *受理(修正予定)*、*受理(ドキュメント対応、修正はしない)*、*対象外(理由付き)*、*重複*、*対応しない(理由付き)*
- **公開タイミング**:協調的開示を希望します。修正予定の場合、重大度に応じて 30〜90 日程度の猶予を設けたうえでの公開議論をお願いします
- **クレジット**:報告者の同意のもと、該当コミットメッセージやアーティファクトの改訂履歴にクレジットを記載します。匿名希望も尊重します

## 本リポジトリが保証しないこと

- 定まった対応時間
- 過去リビジョンへの修正バックポート
- 報奨金・バグバウンティ・金銭的補償
- すべての報告に対応すること(「対象外」を参照)

## 既存のハードニング

参考までに、本リポジトリではすでに以下を運用しています:

- アーティファクトに実在の機密情報(API キー、パスワード、トークン、機微なアカウント ID)を **絶対に含めない**。[`README.ja.md`](./README.ja.md) の「アーティファクトに認証情報を埋め込まないでください」参照
- 本リポジトリの PowerShell スクリプトは [`psa.py`](./quality-tools/powershell-static-analyzer/) で検証され、プレーンテキストパスワードパラメータ・`Invoke-Expression` 使用・脆弱なハッシュアルゴリズム・ハードコード `ComputerName` をカバーするセキュリティクラスルール(`PSA5xxx`)が適用されます
- 全スクリプトは README 冒頭付近に `## ⚠️ Disclaimer` セクションを必須化(リポジトリ規約 — 正規ポリシーはルート [`README.md`](./README.md) の「Use at Your Own Risk」「AI-Generated Content Disclaimer」節、書式カノンは `governance/doc-format/` 配下)
- `.github/workflows/` 配下の CI ワークフローには Fork PR 用 `if` ガードが設定されており、フォーク発信の PR では CI が自動起動しません([`SPEC.md`](./SPEC.md#5-spec-ci-030-fork-pr-handling) §5 参照)。 フォーク PR のレビューは、 同セクションに記載した「人間 + AI 補助」の 2 段階プロトコルに従います。

## 今後のセキュリティ検討事項

CI 面のハードニング候補 5 項目 — Fork PR ワークフローのメンテナ承認ゲート、 サードパーティ Action の SHA ピン、 `CODEOWNERS` ベースのマージ前レビュー強制、 Fork 発信の `workflow_run` に対する遅延実行、 Anthropic API を用いた自動 diff レビューワークフロー — は [`SPEC.md`](./SPEC.md#8-spec-ci-060-future-security-considerations) §8 に記載しています。 いずれも現時点では未実装で、 同セクションには本ポリシーを再検討するきっかけとなる条件も併記しています。
