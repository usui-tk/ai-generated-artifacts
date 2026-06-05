# Security Policy

> 🇯🇵 日本語版は本ファイル下部を参照してください。

## Scope

This repository (`{{REPO_NAME}}`) is a **personal knowledge base** of AI-generated and AI-assisted artifacts. It does **not** host a deployed service, library, or production software. Accordingly, this policy covers:

<!-- FILL: in-scope / out-of-scope table, repo-specific. Keep the common shape:
| In scope | Out of scope |
|:---|:---|
| Scripts that, when executed, introduce a security risk on the user's system (unsafe defaults, missing input validation, credential exposure, insecure download patterns) | Vulnerabilities in third-party tools the scripts wrap - report those upstream |
| Documentation/prompts/templates that, if followed verbatim, lead to a clearly unsafe operational decision | Generic "AI-generated code may be unsafe" discussions - the root README disclaimer covers this |
| Real secrets accidentally committed to this repository | The maintainer's other public information found via OSINT - that is not a leak |
-->

## Reporting a vulnerability

**Please do NOT open a public GitHub Issue for security-impacting reports.**

Instead, use one of the following private channels:

1. **GitHub Security Advisory (preferred)** — open a private security advisory at <{{SECURITY_ADVISORY_URL}}>. This creates a private thread visible only to you and the maintainer.
2. **Direct contact** — if you cannot use GitHub's security advisory feature, contact the maintainer through the email on their GitHub profile (<{{MAINTAINER_PROFILE_URL}}>).

Please include:

- **Affected artifact path** within the repository.
- **Concrete reproduction** — a command sequence, an input file, or a step-by-step description.
- **Observed impact** — what an attacker (or unwary user) could do as a result.
- **Suggested fix** if you have one.

## Response expectations

- **Acknowledgement**: best effort, typically within 7 days. No SLA is guaranteed; this is a personal repository.
- **Triage outcome**: one of *accepted (will fix)*, *accepted (will document, not fix)*, *out of scope (with reason)*, *duplicate*, or *won't fix (with reason)*.
- **Disclosure timeline**: coordinated disclosure is preferred. If a fix is planned, please allow a reasonable window (typically 30-90 days depending on severity) before public discussion.
- **Credit**: with your permission, the reporter is credited in the relevant commit message and/or the artifact's revision history. Anonymity is respected on request.

## What this repository does NOT promise

- A defined turnaround time.
- Backported fixes to historical revisions.
- Compensation, bug bounty, or any monetary reward.
- That every reported issue will be acted upon — see "out of scope" above.

## Hardening already in place

<!-- FILL: repo-specific hardening measures already enforced (e.g. no real secrets in artifacts; psa.py PSA5xxx security-class rules on PowerShell scripts; required README disclaimer section; CI fork-PR guard). Reference the repo's own README/SPEC anchors. -->

## Future security considerations

<!-- FILL: repo-specific candidate hardening measures not yet implemented, and the trigger conditions that would prompt revisiting them. Reference the repo's own SPEC section. -->

---

# 日本語版

# セキュリティポリシー

## 対象範囲

本リポジトリ(`{{REPO_NAME}}`)は、AI が生成・支援したアーティファクトを集約した **個人ナレッジベース** です。稼働サービス・ライブラリ・本番ソフトウェアをホストするものではありません。したがって本ポリシーの対象は以下です:

<!-- FILL: 対象/対象外の表(repo 固有)。共通の形は英語節と同一。 -->

## 脆弱性の報告方法

**セキュリティに影響する事項について、公開の GitHub Issue を起票しないでください。**

代わりに以下のプライベートチャンネルを利用してください:

1. **GitHub Security Advisory(推奨)** — <{{SECURITY_ADVISORY_URL}}> でプライベート advisory を作成。報告者とメンテナのみが閲覧できるスレッドが作られます。
2. **直接連絡** — GitHub の Security Advisory が利用できない場合は、メンテナの GitHub プロフィール(<{{MAINTAINER_PROFILE_URL}}>)に記載のメールアドレスへ連絡してください。

報告時には以下を含めてください:

- **対象アーティファクトのパス**
- **具体的な再現手順** — コマンド列、入力ファイル、ステップバイステップの説明等
- **観測された影響** — 攻撃者(または不注意な利用者)が結果として何ができるか
- **修正案**(あれば)

## 対応の目安

- **受領確認**:ベストエフォート、概ね 7 日以内。SLA の保証はありません(個人リポジトリのため)
- **トリアージ結果**:*受理(修正予定)*、*受理(ドキュメント対応、修正はしない)*、*対象外(理由付き)*、*重複*、*対応しない(理由付き)* のいずれか
- **公開タイミング**:協調的開示を希望します。修正予定の場合、重大度に応じて 30〜90 日程度の猶予を設けたうえでの公開議論をお願いします
- **クレジット**:報告者の同意のもと、該当コミットメッセージやアーティファクトの改訂履歴にクレジットを記載します。匿名希望も尊重します

## 本リポジトリが保証しないこと

- 定まった対応時間
- 過去リビジョンへの修正バックポート
- 報奨金・バグバウンティ・金銭的補償
- すべての報告に対応すること(「対象外」を参照)

## 既存のハードニング

<!-- FILL: すでに運用中の repo 固有ハードニング(英語節と対応)。 -->

## 今後のセキュリティ検討事項

<!-- FILL: 未実装の repo 固有ハードニング候補と、再検討のトリガー条件(英語節と対応)。 -->
