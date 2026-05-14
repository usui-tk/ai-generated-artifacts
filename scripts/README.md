# scripts/

> 🇺🇸 English / 🇯🇵 日本語

## Purpose / 目的

**EN:** Contains AI-generated or AI-assisted **scripts** — automation scripts, utilities, and code samples.

**JA:** AI が生成または支援した**スクリプト**（自動化スクリプト、ユーティリティ、コードサンプル）を格納します。

---

## ⚠️ Critical Warning — Scripts Carry Execution Risk

## ⚠️ 重要な警告 — スクリプトには実行リスクがあります

**EN:** Scripts can modify files, change system state, send data, incur cloud costs, or affect production systems. **Always read and understand a script before executing it.**

**JA:** スクリプトはファイル変更、システム状態変更、データ送信、クラウド利用料発生、本番システムへの影響を引き起こし得ます。**実行前に必ず内容を読み理解してください。**

---

## What to Include / 収録対象

- Automation scripts (PowerShell, Bash, Python, etc.)
- One-off utilities for migration, conversion, batch processing
- Code samples used in research or proof-of-concept work
- Helper scripts referenced by other artifacts in this repository

- 自動化スクリプト（PowerShell、Bash、Python など）
- 移行・変換・バッチ処理のための単発ユーティリティ
- リサーチや PoC で利用したコードサンプル
- 本レポジトリ内の他のアーティファクトから参照されるヘルパースクリプト

## What NOT to Include / 収録対象外

- Long-form code explanations → `research/` or `documents/`
- Reusable code templates / scaffolding → `templates/`
- AI prompts → `prompts/`
- Configuration files containing real secrets / production endpoints → **anywhere in this repo**

- コードの長文解説 → `research/` または `documents/`
- 再利用可能なコードひな型・スキャフォールド → `templates/`
- AI プロンプト → `prompts/`
- 実在の機密情報・本番環境エンドポイントを含む設定ファイル → **本レポジトリのどこにも置かない**

---

## Subcategory Policy / サブカテゴリ方針

**EN:** Scripts are organized by **language** as the primary axis, with **purpose** as the secondary axis where useful.

**JA:** スクリプトは**言語**を第一軸、**用途**を必要に応じた第二軸として整理します。

### Possible Subdirectories / 想定サブディレクトリ

| Subdirectory | Description |
|:---|:---|
| `powershell/` | Windows / cross-platform PowerShell scripts / PowerShell スクリプト |
| `bash/` | Linux / Unix shell scripts / シェルスクリプト |
| `python/` | Python utilities and tools / Python ユーティリティ |
| `aws/` | AWS-specific automation (CLI, SDK) — may contain mixed languages / AWS 固有の自動化（言語混在可） |
| `azure/` | Azure-specific automation (CLI, Az PowerShell) — may contain mixed languages / Azure 固有の自動化（言語混在可） |

Subdirectories are created on demand as scripts are added.

サブディレクトリはスクリプト追加時に必要に応じて作成します。

---

## File Naming / ファイル命名規則

- Follow the language's idiomatic naming convention / 言語の慣習に従う
  - PowerShell: `Verb-Noun.ps1` (e.g., `Download-SpeakerDeck.ps1`)
  - Bash: `kebab-case.sh` (e.g., `setup-ec2-bootstrap.sh`)
  - Python: `snake_case.py` (e.g., `inventory_collector.py` — short forms like `psa.py` are also acceptable as long as they remain lowercase / アンダースコア区切り)
- Configuration / environment files: `kebab-case` or dotted-prefix form. Examples / 設定・環境ファイル：
  - `env.properties.aws-ol10` (per-target environment file, dotted prefix + kebab target suffix)
  - `.psa.config.json` (tool-local configuration with a leading dot)
- Each script should be paired with a README in the same subdirectory if non-trivial / 重要なスクリプトはサブディレクトリの README で説明
- Bilingual READMEs use the bilingual file pattern (`README.md` + `README.ja.md`) when separate files are warranted; otherwise, use a single `README.md` with both languages interleaved / READMEは2ファイル分割もしくは併記の双方を許容

---

## Standard Project Layout / プロジェクトの標準構成

**EN:** When a script is non-trivial (several hundred lines or more, multi-phase logic, or operator-facing output), wrap it in a project directory under the language subdirectory and include the following companion files. The English `<NAME>.md` is canonical; `<NAME>.ja.md` is the synchronized Japanese translation.

**JA:** スクリプトが非自明な規模（数百行以上、多段階処理、運用者向けの出力を伴う等）になる場合は、言語サブディレクトリ配下にプロジェクト用ディレクトリを切り、以下の付随ファイルを同梱します。英語版 `<NAME>.md` がプライマリ、`<NAME>.ja.md` が同期された日本語翻訳版です。

```
scripts/<language>/<project-name>/
  ├── <script>.<ext>             # the main script (Verb-Noun.ps1, kebab.sh, snake.py)
  ├── README.md / README.ja.md   # end-user documentation (required)
  ├── SPEC.md / SPEC.ja.md       # developer specification (recommended for non-trivial scripts)
  ├── TESTING.md / TESTING.ja.md # verification procedure / real-run evidence (optional)
  ├── <config files>             # e.g., env.properties.*, .psa.config.json
  └── <auxiliary scripts>        # related helpers (Test-*.ps1, setup-*.sh, etc.)
```

| File | Role | Required? |
|:---|:---|:---|
| `<script>.<ext>` | The main executable artifact / メインの実行スクリプト | ✓ |
| `README.md` / `README.ja.md` | End-user documentation (installation, quick start, parameters, troubleshooting) / 利用者向けドキュメント | ✓ for non-trivial scripts |
| `SPEC.md` / `SPEC.ja.md` | Developer / LLM specification (phase contract, log conventions, design decisions, known pitfalls) / 開発者・LLM 向け仕様書 | Recommended / 推奨 |
| `TESTING.md` / `TESTING.ja.md` | Verification procedure and recorded real-run results / 検証手順と実機実行記録 | Optional / 任意 |

**EN:** Repository-level files (`LICENSE`, the root `README.md` / `README.ja.md`) live at the repository root and are shared across all script projects — do not duplicate them inside individual project directories.

**JA:** リポジトリ全体に係るファイル（`LICENSE`、ルートの `README.md` / `README.ja.md`）はリポジトリのルートに配置し、全スクリプトプロジェクトで共有します。各プロジェクトディレクトリ内に重複配置しません。

---

## Required Header Convention / 必須ヘッダー規約

Each script must include a header comment describing:

各スクリプトには以下を記述したヘッダーコメントを必須とします。

- **Purpose** / 目的
- **Prerequisites** (runtime version, required modules, permissions) / 前提条件
- **Usage examples** / 使用例
- **Known limitations** / 既知の制約
- **AI tool used and generation date** (if relevant) / 利用 AI ツールと生成日（該当する場合）

---

## Recommended Execution Practices / 推奨される実行手順

1. **Read the source code in full** before execution / 実行前にソースコードを最後まで読む
2. **Run in an isolated test environment first** / 隔離されたテスト環境でまず実行
3. **Check required permissions** and use minimum privileges / 必要権限を確認し最小権限で実行
4. **Back up affected data** before running state-changing scripts / 状態変更スクリプト実行前にデータをバックアップ
5. **Verify external dependencies** and their licenses / 外部依存とライセンスを確認
6. **Never commit secrets** — use environment variables / 機密情報をコミットせず、環境変数で渡す

---

## ⚠️ Disclaimer / 免責事項

All scripts are provided **AS IS, without warranty of any kind**. Refer to the [root README](../README.md) ([日本語](../README.ja.md)) for the full disclaimer and self-responsibility terms.

すべてのスクリプトは**現状有姿（AS IS）でいかなる保証もなく**提供されます。完全な免責事項は[ルート README](../README.md)（[日本語版](../README.ja.md)）を参照してください。
