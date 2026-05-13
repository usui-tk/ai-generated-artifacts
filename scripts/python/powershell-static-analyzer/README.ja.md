# powershell-static-analyzer

> 🇯🇵 日本語 / 🇺🇸 [English](./README.md)

PowerShell スクリプト用の単一ファイル Python 3 静的解析ツール（`psa.py`）です。
通常の PowerShell パーサーが構文解析時には検出しない、しかし長尺スクリプトを
予期せず壊しがちな種類のバグを捕捉します。

このディレクトリは `ai-generated-artifacts` レポジトリ内における `psa.py` の
**正規配置場所**です。本レポジトリ内の他の PowerShell スクリプト
（例：[`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/)）
は、各自のコピーを持たずに、このパスを参照する形で利用します。

---

## 起源と上流レポジトリ

`psa.py` は
[`usui-tk/Deploy-AMD-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/blob/main/tools/psa.py)
で誕生し、設計理念は引き続き上記レポジトリで管理されています。本ディレクトリ
のコピーは、上流の `tools/psa.py` と同期して維持されます。

**バグ修正および新しいチェックは、まず上流に貢献**してから本ディレクトリに
同期してください。

---

## なぜカスタム解析ツールなのか

Microsoft は [PSScriptAnalyzer](https://learn.microsoft.com/ja-jp/powershell/utility-modules/psscriptanalyzer/overview)
を提供しており、これは優秀なツールで併用すべきです。ただし PSScriptAnalyzer
には本ユースケースにおいて以下の 2 つの制約があります。

1. 実行に PowerShell 5.1 以上が必要（CI に Windows / PowerShell がまだ無い
   場合は鶏と卵の問題になる）。
2. 検出する問題の種類が異なる ― 主にスタイルおよびベストプラクティス違反。
   数千行スクリプトの波括弧不整合、誤字による未定義変数参照、
   `$null` で `True` を返す裸の `$variable` に対する `-match` などは
   **デフォルトでは検出しない**。

`psa.py` は Python 3 が動く環境ならどこでも動作する Python スクリプトであり、
補完的なチェックを実行します。PSScriptAnalyzer の代替ではなく、
**追加のセーフティネット**として位置付けています。

---

## 前提条件

- Python 3.x（外部依存なし。標準ライブラリのみ）
- 解析対象の `.ps1` ファイル

---

## 使用方法

```bash
# 単一スクリプトを解析
python3 scripts/python/powershell-static-analyzer/psa.py path/to/script.ps1

# 例：本レポジトリ内のスクリプトを解析
python3 scripts/python/powershell-static-analyzer/psa.py \
        scripts/powershell/download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1
```

終了コード：

- `0` — クリーン（エラー無し、警告無し）
- `1` — 警告のみ（CI ではソフトフェイル扱いも可）
- `2` — エラーあり（CI は必ず失敗扱いとする）

---

## 出力フォーマット

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 4106
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

検出時：

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 8680
Issues : 0 errors, 9 warnings, 0 info

---- WARNING (9) ----
  [C7] line  2215: -match against bare $noisePattern - $null pattern returns true
  [C6] line  2300: Start-Process -ArgumentList; prefer ProcessStartInfo
  ...
```

各 issue にはチェックコード（C1〜C10）、重大度、行番号、短いメッセージが
含まれます。

---

## 実装されているチェック

| コード | 重大度 | 検出内容 | 重要性 |
| --- | --- | --- | --- |
| **C1** | error | 波括弧バランス：`{` の数 vs `}` の数 | 数千行スクリプトでの 1 個の波括弧不整合は目視デバッグ不可能。パーサーは EOF で構文エラーを報告するため、実際の不整合箇所は分からない。`psa.py` は双方の数を報告するので `grep -n '^[}]'` でトレース可能。 |
| **C2** | error | 丸括弧バランス：`(` vs `)` | C1 と同じだが `()` 用。 |
| **C3** | error | 角括弧バランス：`[` vs `]` | C1 と同じだが `[]` 用。 |
| **C4** | warning | 未定義変数参照（ヒューリスティック） | `$matchedDeciks` のような `$matchedDecks` の誤字を検出。ヒューリスティックのため、他箇所で代入されている `$global:` / `$script:` スコープ変数では誤検出の可能性あり。 |
| **C5** | warning | 自動変数のシャドーイング | `$args`、`$_`、`$matches`、`$null` などへの代入は PowerShell 組み込みを無言で破壊する。自動変数のリストは [about_Automatic_Variables](https://learn.microsoft.com/ja-jp/powershell/module/microsoft.powershell.core/about/about_automatic_variables) に基づく。 |
| **C6** | warning | `Start-Process -ArgumentList`（`-PassThru` / `Wait-Process` 等を伴わない） | `Start-Process` は便利だが、スペースを含むパスを誤処理し、終了コードのパスが貧弱で stderr を捨てる。信頼性が必要なスクリプトでは `[System.Diagnostics.Process]::Start([ProcessStartInfo]@{...})` を推奨。 |
| **C7** | warning | 裸の `$variable` に対する `-match`（例：`$line -match $pattern`）で `$pattern` が `$null` の可能性あり | `$line -match $null` は `True` を返し**かつ `$matches = $null` を代入**する。マッチ前に `[string]::IsNullOrEmpty($pattern)` でラップすること。 |
| **C8** | info | TODO / FIXME マーカー | 残作業のリマインダー。失敗扱いではない。 |
| **C9** | warning | 空行直前の行末バックティック | PowerShell の行継続バックティックは脆弱。次行が空（可視）または末尾空白を含む場合、継続が無言で破綻する。 |
| **C10** | warning | リテラル空文字列 `""` または `''` に対する `-match` | `$x -match ""` は空文字列も含めた**任意の文字列に対して常に True**。ほぼ必ずコーディング誤り。 |

---

## 解析ツールがチェックしないもの

- コマンドレットの存在（PowerShell セッションが必要）
- 型の正しさ（PowerShell は動的型付け。これはシェルスクリプトであり C# ではない）
- モジュールインポート（`Import-Module` の解決）
- 関数シグネチャの正しさ（param 型、必須パラメータ）
- ベストプラクティスのスタイル違反（PSScriptAnalyzer の領域）

---

## PSScriptAnalyzer との併用

PowerShell 5.1 以上が利用可能な場合は併用してください。

```powershell
# psa.py に加えて
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path path/to/script.ps1 -Severity Warning,Error
```

---

## 新しいチェックの追加

`psa.py` の構造は意図的にミニマルです。新しいチェック `C11` を追加するには：

1. `check_yourthing(text)` 関数を追加。`severity`、`code`、`line`、`message`
   をキーとする dict のリストを返すこと。
2. `main()` から呼び出し、`issues` に append する。
3. 新しいコードを上記表および上流レポジトリ
   ([`Deploy-AMD-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer))
   にドキュメント化する。

`strip_strings_and_comments(line)` ヘルパーは `''` / `""` / `# ...` の中身を
無視したいチェックの標準的な前処理です。利用してください。

**注意：** まず上流に変更を貢献してから、更新された `psa.py` を本ディレクトリ
に同期してください。

---

## CI 連携例

GitHub Actions ワークフロー断片（Linux ランナー、Windows / PowerShell 不要）：

```yaml
name: Lint
on: [push, pull_request]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Run psa.py on script
        run: |
          python3 scripts/python/powershell-static-analyzer/psa.py \
                  scripts/powershell/download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1
```

---

## 本レポジトリ内のコンシューマー

以下の PowerShell スクリプトは `psa.py`（本正規配置場所）で検証されています。

| スクリプト | パス |
|:---|:---|
| `Download-SpeakerDeck.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |
| `Test-PdfMetadata.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |

（新しい PowerShell スクリプトが `psa.py` を採用した際は、このリストを
更新してください。）

---

## ライセンス

`psa.py` は本レポジトリの他の部分と同じ MIT ライセンスの下で公開されています。
レポジトリルートの [`LICENSE`](../../../LICENSE) を参照してください。
