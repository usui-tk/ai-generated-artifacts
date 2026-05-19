# ai-generated-artifacts

> 🇺🇸 English version: [README.md](./README.md)

## 概要

本レポジトリは、**AI ツール（主に Anthropic Claude）によって生成または支援されたアーティファクト**を公開・長期管理するためのナレッジベースです。技術リサーチ、実行可能なスクリプト、設計ドキュメント、プレゼンテーション資料、再利用可能なテンプレート、AI プロンプト、学習ノートなど、AI 由来のあらゆる成果物を、単一の体系化された構造に集約します。

レポジトリの範囲は意図的に広く設計されており、**今後のレポジトリ名・トップレベル構造の変更を行うことなく拡張できる**ことを前提としています。

---

## レポジトリ構造

レポジトリはアーティファクトの種類別に 7 つのトップレベルディレクトリに分かれます。

```
ai-generated-artifacts/
├── LICENSE
├── README.md                 # 英語版（プライマリ）
├── README.ja.md              # 日本語版
├── SPEC.md                   # レポジトリレベルの CI / 横断的ポリシー（英語のみ）
├── .gitignore
│
├── research/                 # リサーチ記事、調査、分析
├── scripts/                  # 自動化スクリプト、ユーティリティ、コードサンプル
├── documents/                # 戦略書、設計書、提案書、計画書
├── presentations/            # プレゼンテーション資料（PowerPoint、Markdown、PDF）
├── templates/                # 再利用可能なひな型（ADR、WBS、ヒアリングシート）
├── prompts/                  # 再利用可能な AI プロンプト
└── study-notes/              # 認定試験・学習ノート
```

各トップレベルディレクトリには `README.md`（英語と日本語を 1 ファイルに併記）が配置されており、以下の事項を明記しています。

- 目的・収録範囲（含めるべきもの／含めないもの）
- 隣接ディレクトリとの振り分けルール
- サブカテゴリ方針と命名規則
- 必須メタデータまたはヘッダー規約
- ディレクトリ固有の免責事項

---

## 横断的仕様

複数のサブプロジェクトにまたがるポリシー（たとえば、すべてのワークフロー
共通の継続的インテグレーション設計とタイムアウト規律）は、レポジトリ
直下の [`SPEC.md`](./SPEC.md) に集約しています。サブプロジェクト固有の
仕様は、各サブプロジェクトの `SPEC.md` を参照してください。

[`SPEC.md`](./SPEC.md) を最初に参照するべきケースは以下のとおりです。

- `.github/workflows/` 配下に新規ワークフローを追加するとき
- 既存ワークフローのタイムアウト、命名、または `if` ガードを変更するとき
- フォーク PR のレビュー時に、公開されたレビュープロトコルを参照するとき

---

## 継続的インテグレーション

本レポジトリは `.github/workflows/` に 4 本の GitHub Actions ワークフローを
備えています。各バッジは下表のとおりです。サブプロジェクトの README には、
そのサブプロジェクトに該当するバッジのみを掲載しています。

| ワークフロー | 対象 | バッジ |
|:---|:---|:---|
| psa.py セルフ品質ゲート | `scripts/python/powershell-static-analyzer/` | [![psa.py CI](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml) |
| Download-SpeakerDeck STAGE 1（Linux） | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml) |
| Download-SpeakerDeck STAGE 2（Windows） | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml) |
| Download-SpeakerDeck STAGE 3（リリース検証） | `scripts/powershell/download-speakerdeck-oracle4engineer/` | [![DSD STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml) |

ガバナンス、命名規則、タイムアウト階層、フォーク PR レビュープロトコルは
すべて [`SPEC.md`](./SPEC.md)（§2 〜 §9）で定義しています。CI ごとの変更
履歴は対象スクリプトの `CHANGELOG.md` に記録されます。`.github/workflows/CHANGELOG.md`
のような中央集約ファイルは存在せず、[`SPEC.md`](./SPEC.md) §9 で作成が
禁止されています。

レポジトリレベルのセキュリティベースライン（Dependabot、 シークレット
スキャン、 push protection、 CodeQL、 Actions allowlist、 `GITHUB_TOKEN`
スコープポリシー等）については [`SPEC.md` §11 (SPEC-CI-080)](./SPEC.md#11-spec-ci-080-repository-security-baseline) を参照してください。 各ワークフローの
`[Artifacts] Upload logs` ステップでアップロード可能なファイルを制限する
アーティファクト最小化ポリシーは [`SPEC.md` §12 (SPEC-CI-081)](./SPEC.md#12-spec-ci-081-artifact-content-minimization) に記載しています。

---

## コンテンツ振り分け — どのディレクトリに置くべきか？

迷ったときは、以下の判定ルールに従ってください。

| アーティファクトが主として… | 配置先 |
|:---|:---|
| 「**どんな選択肢があるか**」に答える比較・調査・分析 | `research/` |
| 言語を問わない**実行可能なコード** | `scripts/` |
| 特定シナリオに対する**具体的な計画・設計・推奨事項** | `documents/` |
| 発表用の**スライドデック** | `presentations/` |
| コピーして記入して使う**骨組み・スキャフォールド・フォーム** | `templates/` |
| **再利用可能な AI プロンプト** | `prompts/` |
| 認定試験や技術習得のための**学習資料** | `study-notes/` |

複合的なアーティファクト（例：テンプレートと解説文書のセット）の場合は、主たる配置先を1箇所に決め、もう片方からはクロスリファレンスで参照する形にします。

---

## 命名規則

### ディレクトリ

- 小文字、ハイフン区切り、**複数形**（コレクションであることを示す）
  - ✅ `research/`, `scripts/`, `study-notes/`
  - ❌ `Research/`, `script/`, `study_notes/`

### サブディレクトリ

- 小文字、ハイフン区切り、**トピック・言語・カテゴリ**を端的に表現
  - ✅ `research/cloud-infrastructure/`, `scripts/powershell/`, `study-notes/aws/`

### ファイル

- 小文字、ハイフン区切りのスラッグ
- バイリンガルファイルは以下の 2 パターンを許容：
  - **パターン A — 言語サフィックス対** (`<slug>.en.md` / `<slug>.ja.md`)
    リサーチ記事や学習ノートなど一般的なコンテンツファイルに使用。
  - **パターン B — プライマリ + 翻訳** (`<NAME>.md` が英語プライマリ、`<NAME>.ja.md` が日本語翻訳版)
    `README.md` / `README.ja.md` に使用。 他のリポジトリ慣例ファイル (`SPEC.md`、 `TESTING.md`、 `CHANGELOG.md`、 `CONTRIBUTING.md`、 `SECURITY.md`、 `CODE_OF_CONDUCT.md`) は下記「言語ポリシー」により **英語のみ** で維持されます。
- 単一言語ファイル: `<slug>.md`
- コードファイルは言語の慣習に従う（例：PowerShell は `Verb-Noun.ps1`、Bash は `kebab-case.sh`、Python は `snake_case.py`）

### ファイル名で避けるべきもの

- 大文字（言語仕様で必須の名前、およびリポジトリ慣例ファイル名 — `LICENSE`、`README.md`、`SPEC.md`、`TESTING.md`、PowerShell の `Verb-Noun.ps1` 等を除く）
- スペース
- 日本語等の非 ASCII 文字
- `-`、`_`、`.` 以外の特殊記号
- 50文字を超える長すぎる名前

---

## 言語ポリシー

本リポジトリでは、 すべてのサブディレクトリおよび姉妹リポジトリで統一して適用される **リポジトリ横断の共通ポリシー** を採用しています:

| ファイル種別 | 維持される言語 | マスター | 備考 |
| --- | --- | --- | --- |
| `README.md` | 英語 **および** 日本語 (`README.ja.md`) | `README.md` (英語) | 英語版がマスター。 `README.ja.md` はその翻訳版であり、 同じ PR 内で同期更新する。 |
| `SPEC.md` | **英語のみ** | — | 仕様書は drift 回避のため英語のみで維持。 |
| `TESTING.md` | **英語のみ** | — | テスト手順・検証結果、 英語のみ。 |
| `CHANGELOG.md` | **英語のみ** | — | 時系列のリリースノート、 英語のみ。 |
| `CONTRIBUTING.md`、 `SECURITY.md`、 `CODE_OF_CONDUCT.md` | **英語のみ** | — | リポジトリポリシーファイル、 英語のみ。 |
| リサーチ記事・学習ノート (パターン A `<slug>.en.md` / `<slug>.ja.md`) | 可能であれば英語および日本語 | — | コンテンツファイル。 現実的な範囲でバイリンガル化。 |
| トップレベル直下のサブディレクトリの README | 1 ファイル内に日英を併記 | — | 非常に短い概要 README で重複が無駄になる場合の例外。 両言語が等しく完全であることが条件。 |

**ポリシーの根拠**: 新規読者の入口となる `README.md` のみ日本語版を並行維持します。 仕様書・テスト手順・リリースノートは同期 drift を回避するため英語のみで維持します — これは LLM 支援メンテナンスで特に発生しやすい問題です。 日本語話者の読者は `README.ja.md` でオリエンテーションを取った後、 詳細な技術内容については英語のソース・オブ・トゥルースを参照する想定です。

過去アーティファクトに `SPEC.ja.md` や `TESTING.ja.md` が残っている場合は、 次のメンテナンスパスで削除し、 他ドキュメントの参照を英語版に向け直してください。

---

## リビジョン履歴ポリシー

本リポジトリでは、 リリース毎の変更履歴の管理について、 全サブプロジェクト (スクリプト、 ツール、 プロンプト) で統一して適用される **リポジトリ横断の共通ポリシー** を採用しています:

- **リリース毎の変更履歴は `CHANGELOG.md` に集約します。** スクリプト本体や `README.md` や `SPEC.md` の中には書きません。
- 各サブプロジェクトは、 リリース cadence (頻度) のあるものは独自の `CHANGELOG.md` を他ファイルの隣に配置します (例: [`scripts/python/powershell-static-analyzer/CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md))。
- `CHANGELOG.md` は [Keep a Changelog 1.1.0](https://keepachangelog.com/ja/1.1.0/) 形式に従い、 [Semantic Versioning 2.0.0](https://semver.org/lang/ja/) に準拠します。
- `CHANGELOG.md` は上記「[言語ポリシー](#言語ポリシー)」に従い **英語のみ** で維持されます。

**情報種別ごとの配置場所:**

| 情報の種別                                            | 配置場所                                                       |
| ----------------------------------------------------- | -------------------------------------------------------------- |
| *このコードは今、 何をするのか?*                      | スクリプト本体のコメント + `README.md`                         |
| *なぜこの設計になっているのか?*                       | `SPEC.md` (特に "Part D — Known Pitfalls" 相当の節)            |
| *各リリースで何が変わったか、 いつ変わったか?*        | `CHANGELOG.md`                                                 |
| *SemVer で保護される公開 API 契約は何か?*             | `SPEC.md` Versioning 節                                        |

**この区分が重要な理由**: LLM 支援によるコードメンテナンスでは、 過去のリビジョン情報がスクリプト本体に溜まりがちです (`# r42: X を修正`、 `# r56+: 今は Y する` など)。 こうしたコメントはすぐに追跡不能な雑音になります — 読者は `r42` の指す内容を Git 履歴を辿らない限り解決できません。 リリースノートを `CHANGELOG.md` に集約し、 スクリプト本体は現在の挙動だけに集中させることで、 この失敗モードを回避します。

**静的解析による強制**: PowerShell スクリプトについては、 `psa.py` が 2 つの opt-in ルール — `PSAP0003` (インラインの `# rNN:` リビジョンタグ) と `PSAP0004` (EOF の `REVISION HISTORY` ブロック) — を提供し、 本ポリシー違反を検出します。 各サブプロジェクトは `.psa.config.json` の `enable` リストで opt-in します。 (consumer は常に最新の mainline `psa.py` で検証してください。 下の「psa.py のバージョニングポリシー」セクションを参照。)

各サブプロジェクト固有のガイダンスは、 サブプロジェクトの `SPEC.md` の **Revision discipline** サブセクションを参照してください。

**CI の変更は CI 対象スクリプトの `CHANGELOG.md` に記録します** (`.github/workflows/CHANGELOG.md` のような別個の中央集約ファイルは存在せず、 [`SPEC.md`](./SPEC.md#9-spec-ci-070-ci-change-history-location) §9 で作成が禁止されています)。 ワークフロー YAML への変更は、 そのワークフローが検証するスクリプトの `CHANGELOG.md` に記録します。

---

## psa.py のバージョニングポリシー

本レポジトリは [`psa.py`](./scripts/python/powershell-static-analyzer/) を保持しています。 これは本レポジトリ内のすべての PowerShell サブプロジェクト **および** 姉妹レポジトリ (特に [`Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)) が使用する正典の PowerShell 静的解析ツールです。 本セクションは、 consumer が検証対象とすべき `psa.py` のバージョンに関するレポジトリ横断ルール、 および新バージョンの発見・採用に関する正典ワークフローを定義します。

### 中核ルール: latest mainline 以外はサポートしない

consumer (LLM / AI 補助のメンテナ、 CI パイプライン、 人間開発者を含む) は **必ず** 本レポジトリの **latest mainline** の `psa.py` で PowerShell コードを検証してください。 固定 SemVer (例: 「`psa.py` 3.3.0 でテスト済み」) への pin は **サポートされません**:

- 新しい `psa.py` バージョンは、 opt-in ルール (`PSAPxxxx` ファミリー) を追加して、 これまで見えていなかった規律違反を検出する可能性があります。
- 新しい `psa.py` バージョンは、 既存ルールのヒューリスティクスを強化する可能性があります。
- 古い `psa.py` で clean だった codebase は、 **現在の** `psa.py` で正しいことの根拠にはなりません。 再検証が必要です。

サブプロジェクトのドキュメント (`README.md`, `SPEC.md`, `TESTING.md` 等) では、 `psa.py` を特定バージョン番号に pin して **はいけません**。 特定バージョン番号の参照が許容されるのは `CHANGELOG.md` (バージョン毎の歴史記録) と `psa.py` 自身の `CHANGELOG.md` のみです。

### 現在の mainline バージョンの取得方法

「mainline の `psa.py` の現在バージョンは何か」 の正典情報源は、 `psa.py` の隣にある `VERSION` ファイルです:

```
scripts/python/powershell-static-analyzer/
├── psa.py        ← 内部に __version__ 文字列
├── VERSION       ← 単一 ASCII 行、 先頭 'v' なし、 末尾 LF
├── SPEC.md
├── CHANGELOG.md
└── README.md
```

3 つの等価な取得方法 (どれを使っても OK。 環境に合わせて選択):

```bash
# 方法 1 — リモート HTTP GET、 clone 不要、 Python 不要 (CI / 単発チェックに推奨)
LATEST=$(curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION)
echo "Latest psa.py on mainline: $LATEST"

# 方法 2 — 既に clone 済み (例: 姉妹レポジトリのチェックアウトと同階層)
LATEST=$(cat /path/to/ai-generated-artifacts/scripts/python/powershell-static-analyzer/VERSION)

# 方法 3 — ローカルの psa.py を起動 (Python 必要)
LATEST=$(python3 /path/to/psa.py --version | awk '{print $2}')
```

3 つの方法は必ず一致します: `psa.py` は起動時に `__version__` と隣接 `VERSION` ファイルを比較する self-check を実行し、 不一致を stderr に警告します。 契約の詳細は [`SPEC.md` §1.4](./scripts/python/powershell-static-analyzer/SPEC.md#14-versioning) を参照。

### 新バージョン採用のための LLM / AI ワークフロー

LLM / AI メンテナ (あるいは人間) が、 `psa.py` で検証される **任意の** PowerShell スクリプト (本レポジトリでも姉妹レポジトリでも) に変更を加えようとするとき、 開発サイクルの **最初のステップ** として以下を **必ず** 実施してください:

1. **mainline の現在バージョンを取得**: 上の方法 1 を実行して `LATEST` を得る。
2. **実際に使用中のローカルコピーと比較**: ローカルの `psa.py` から `__version__` を読むか、 `python3 /path/to/local/psa.py --version` を実行。 これを `LOCAL` と呼ぶ。
3. **`LATEST != LOCAL` の場合**:
   1. mainline から `psa.py` と隣接の `VERSION` ファイルの **両方** を置き換える (両ファイルは必ず一緒に動かす):
      ```bash
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py -o psa.py
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION -o VERSION
      ```
   2. [`CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md) の新エントリと現在の [`SPEC.md`](./scripts/python/powershell-static-analyzer/SPEC.md) を読み、 何が変わったか (新ルール、 強化されたヒューリスティクス、 スキーマ変更) を理解する。
   3. プロジェクトの `.psa.config.json` の `enable` リストを、 最新の `SPEC.md` と照らして再評価する。 プロジェクトの規律目標に合う新規 opt-in ルールがあれば、 有効化を検討する。
   4. 新しい `psa.py` で、 プロジェクト内のすべての PowerShell スクリプトに対してフルテストスイートを再実行する。 新たに検出された findings は、 同じ変更セット内で対処すべき regression として扱う (先送りしない)。
4. **`LATEST == LOCAL` の場合**: 予定の変更を進めて構いません。 ただし変更後のスクリプトに対しては必ず再度 analyzer を回してから完了宣言してください。

このワークフローにより、 「latest mainline」 ルールは機械的に実行可能になります: 本セクションを読んだ LLM は、 本レポジトリや姉妹レポジトリの PowerShell コードに触れる任意のタスクに対して、 `curl`・比較・取得・再テストの決定論的な手順列を導出できます。

### `CHANGELOG.md` 内の released SemVer バージョンの位置づけ

[`psa.py` の `CHANGELOG.md`](./scripts/python/powershell-static-analyzer/CHANGELOG.md) 内のバージョン番号 (例: `## [3.4.0] — 2026-05-19`) は、 各挙動変更がいつリリースされたかの正典的な歴史記録です。 これは人間の監査者向け、 および API 契約を 2 時点間で diff するための記述です。 これは **pin の対象ではありません**: consumer は「バージョン 3.4.0」を参照ポイントとして選ぶのではなく、 「今日の mainline」を選び、 「前回 sync した時の mainline」 との差分を理解するために CHANGELOG を参照します。

---

## ⚠️ 自己責任での利用について

**本レポジトリのコンテンツはすべて「現状有姿（AS IS）」で提供されており、いかなる保証も伴いません。利用は完全に利用者ご自身の責任でお願いします。**

本レポジトリのアーティファクトを参照・実行・利用される場合は、以下の事項に同意したものとみなされます。

1. **正確性・適合性に関する保証はありません。** コンテンツの正確性、完全性、信頼性、目的への適合性、可用性について、作者は一切の表明・保証を行いません。情報が古くなっていたり、不完全であったり、事実誤認を含んでいる可能性があります。

2. **損害に対する責任は負いません。** 本レポジトリのコンテンツの利用に起因または関連して発生したいかなる直接的・間接的・付随的・結果的・特別な損害（データ損失、システム障害、セキュリティインシデント、金銭的損失、ダウンタイム、業務影響、認定資格や専門家としての地位の喪失を含むがこれらに限定されません）についても、作者は責任を負いません。

3. **独立した検証は利用者の責任です。** 本レポジトリの情報・推奨事項・設計・コード・テンプレートを実環境（特に本番環境）に適用する前には、以下を利用者の責任で実施してください。
   - 一次情報・公式ドキュメントによる正確性の確認
   - 隔離された安全な環境での十分なテスト
   - セキュリティ・パフォーマンス・コンプライアンス・ライセンス影響の評価
   - 所属組織における適切な承認の取得

4. **スクリプト・コードには実行リスクがあります。** スクリプトの実行はファイル変更、システム状態の変更、データ送信、クラウド・サービス利用料の発生、第三者システムへの影響を引き起こし得ます。スクリプトを実行する前に必ず内容を読み理解してください。

5. **アーティファクトに認証情報を埋め込まないでください。** 本レポジトリのアーティファクトには、実在する API キー、パスワード、トークン、非公開のアカウント ID 等の機密情報を含めません。スクリプトは認証情報を環境変数・パラメーター・対話型プロンプト経由で受け取る設計を基本とします。

6. **学習ノートは公式教材の代替ではありません。** `study-notes/` 配下のノートは公開情報を個人的に統合したものであり、認定試験対策の主要教材として依拠することは想定していません。受験 NDA で保護される試験問題内容は一切含めません。

---

## 🤖 AI 生成コンテンツに関する免責事項

- 本レポジトリには、**AI ツール（主に Anthropic Claude）によって生成または支援されたコンテンツ**が含まれます。
- AI 生成出力には、**ハルシネーション（誤情報の生成）、事実誤認、情報の陳腐化、推論誤り**が含まれる可能性があります。
- すべてのアーティファクトは、利用される前に、適切な専門知識を持つ**人間による独立したレビュー・検証**を受けることを前提としています。
- AI 生成のコードや構成については、セキュリティ、パフォーマンス、コンプライアンス、ライセンスの観点で追加の検証が必要となる場合があります。
- アーティファクト内で言及されている第三者の製品・サービス・価格・仕様・バージョン情報は、生成時点以降に変更されている可能性があります。

---

## レビュー・メンテナンス方針

- アーティファクトは、可能な範囲で作者によりレビューされますが、**定期的な更新は保証されません**。
- 修正・拡張は Git の履歴から追跡可能であることを目指します。
- アーティファクト生成時の前提条件・制約・背景情報は、可能な限り各アーティファクト内に記述します。
- 古くなったアーティファクトは、履歴的参照のため残置されることがあり、自動的に削除されるわけではありません。

---

## コントリビューションについて

本レポジトリは個人レポジトリです。Issue や Pull Request を積極的に募集しているわけではありませんが、建設的なフィードバック（誤りの指摘、リンク切れ、事実誤認の報告など）は GitHub Issues でお寄せいただけます。ただし、対応・反映の保証はありません。

---

## ライセンス

本レポジトリは [MIT License](./LICENSE) の下で公開されています。

MIT ライセンスはレポジトリ所有者が作成・編集したコンテンツに適用されます。アーティファクト内で言及される**第三者の商標・製品名・参照素材**については、それぞれの権利者に帰属します。

---

## 補足

本レポジトリは、AI ツールを用いた個人的な学習・リサーチ・ナレッジ共有活動を支援することを目的としています。AI 生成出力を権威ある情報、本番環境向け成果物、または専門家の認定を経た成果物として推奨するものでは**ありません**。
