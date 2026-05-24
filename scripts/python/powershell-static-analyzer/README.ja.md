# powershell-static-analyzer

[![psa.py CI](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__python__powershell-static-analyzer.yml)

> 🇺🇸 [English](./README.md) / 🇯🇵 日本語

PowerShell スクリプト用の単一 Python 3 ファイル静的解析ツール (`psa.py`)
です。PowerShell の通常のパーサーが構文解析時には検出しないが、長尺の
スクリプトを地味に壊してしまうクラスのバグを検出します。

このディレクトリは `psa.py` の**唯一の正典ソース**です。本 `ai-generated-artifacts`
リポジトリ内の PowerShell スクリプトも、外部リポジトリも、各々が独自の
コピーを保持するのではなく、このファイルを参照します。

正式な仕様書（CLI 契約、ルール意味論、出力スキーマ、環境検出契約）に
ついては [`SPEC.md`](./SPEC.md) を参照してください (リポジトリ共通の
ドキュメント言語ポリシーにより英語のみで維持されています)。

**現在のバージョン**: [`VERSION`](./VERSION) ファイルを参照してください (バイト列のみの正典キャリア。同じ文字列が `psa.py` の `__version__` および `psa.py --version` 出力にミラーされます)。

clone も Python 実行も不要で、 最新の mainline バージョンを軽量に取得できます:

```bash
curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION
```

これは AI / LLM 駆動のワークフローや CI が、 ローカルにキャッシュした `psa.py` が最新かどうかを判定するための **正規手段** です。 consumer 側に期待される latest-mainline ワークフローの詳細は [SPEC.md §1.4](./SPEC.md#14-versioning) およびリポジトリルートの [`README.md`](../../../README.md) "psa.py Versioning Policy" を参照してください。

---

## 更新履歴

リリースノートは [`CHANGELOG.md`](./CHANGELOG.md)
([Keep a Changelog 1.1.0](https://keepachangelog.com/ja/1.1.0/) 形式) を参照してください。

なお、 リポジトリ共通のドキュメント言語ポリシーにより、
`CHANGELOG.md` は **英語のみ** で維持されています。
詳細は本リポジトリのルート [`README.ja.md`](../../../README.ja.md)
の「言語ポリシー」セクションを参照してください。

## 由来と保守ポリシー

`psa.py` はもともと
[`usui-tk/Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
の `tools/psa.py` として誕生しました。その後、本 `ai-generated-artifacts`
リポジトリに**唯一の正典ソース**として集約され、
`Deploy-Drivers-For-WindowsServer` リポジトリ側の `tools/psa.py`
は削除されました。同リポジトリは現在、`psa.py` をこちらの外部依存として
参照しています（同リポジトリの [SPEC §A.11](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md#a11-static-analysis-with-psapy)
を参照）。

**バグ修正・新規チェックの追加・auto-variable 一覧の更新は、すべて
このディレクトリの `psa.py` に対して行ってください**。下流の利用側
リポジトリは、`git clone` または raw blob の単一ファイルダウンロードに
よって最新版を取得します。フォークの保守は行いません。

---

## なぜ独自アナライザを作るのか

Microsoft は [PSScriptAnalyzer][PSScriptAnalyzer] を提供しており、これは
素晴らしいツールで併用すべきです。ただし PSScriptAnalyzer には 2 つの
制約があります。

1. 実行に PowerShell 5.1 以降が必要（Windows / PowerShell がまだ用意
   されていない CI 環境では「鶏と卵」の状態）。
2. 検出するバグの種類が異なり、主にスタイルやベストプラクティス違反を
   対象としています。数千行スクリプトの**括弧アンバランス**、**タイポ
   による未定義変数参照**、**`-match` を素の `$variable` に対して使う**
   といった問題は、デフォルトでは検出されません。

`psa.py` は Python 3 が動く環境ならどこでも動作するスクリプトで、
PSScriptAnalyzer を補完するチェックを提供します。PSScriptAnalyzer の
代替品ではなく、**PowerShell が動かない CI パイプライン**でも使える
追加のセーフティネットとして設計されています。

---

## 前提条件

- Python 3.8 以降
- 標準ライブラリのみ — **外部依存ゼロ**
- 解析対象の `.ps1` または `.psm1` ファイル

---

## 使い方

```bash
# 単一スクリプトを解析
python3 scripts/python/powershell-static-analyzer/psa.py path/to/script.ps1

# 複数ファイル / glob
python3 scripts/python/powershell-static-analyzer/psa.py *.ps1

# ディレクトリを再帰的にスキャン (.ps1 + .psm1)
python3 scripts/python/powershell-static-analyzer/psa.py -r ./scripts

# JSON 出力（機械可読）
python3 scripts/python/powershell-static-analyzer/psa.py --format json script.ps1

# SARIF 出力（GitHub Code Scanning / IDE プラグイン用）
python3 scripts/python/powershell-static-analyzer/psa.py --format sarif script.ps1 > result.sarif

# 重大度でフィルタ
python3 scripts/python/powershell-static-analyzer/psa.py --severity error script.ps1

# デフォルト無効ルールを有効化
python3 scripts/python/powershell-static-analyzer/psa.py --enable PSA6002 script.ps1

# 特定ルールを無効化
python3 scripts/python/powershell-static-analyzer/psa.py --disable PSA2001 script.ps1

# 指定したルールのみ実行
python3 scripts/python/powershell-static-analyzer/psa.py --include PSA1001,PSA1002 script.ps1

# 明示的に設定ファイルを指定 (ローカルパス)
python3 scripts/python/powershell-static-analyzer/psa.py --config .psa.config.json script.ps1

# リモート設定ファイルを使用 (http(s) URL、GitHub raw 推奨)
python3 scripts/python/powershell-static-analyzer/psa.py \
        --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json script.ps1

# ルール一覧を表示
python3 scripts/python/powershell-static-analyzer/psa.py --list-rules

# PowerShell / PSScriptAnalyzer の利用可否を検出（情報提供のみ）
python3 scripts/python/powershell-static-analyzer/psa.py --check-env

# 通常解析出力に環境サマリを前置（情報提供のみ）
python3 scripts/python/powershell-static-analyzer/psa.py --show-env script.ps1

# .psa.config.json のスキーマを検証 (ファイル解析は行わない)
python3 scripts/python/powershell-static-analyzer/psa.py --config-check .psa.config.json

# SPEC.md と RULES が同期しているかを検証 (リリースプロセスのゲート)
python3 scripts/python/powershell-static-analyzer/psa.py --self-check
```

### 終了コード

| コード | 意味 |
|:---:|:---|
| `0` | クリーン（error も warning もなし） |
| `1` | warning のみ（CI ではソフトフェイル扱いも可） |
| `2` | error あり（CI は必ず失敗扱い）、 もしくは self-quality チェック (`--config-check` / `--self-check`) で違反検出 |

---

## 出力フォーマット（テキスト）

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 4106
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

問題が検出された場合:

```
==== psa.py: PowerShell Static Analyzer ====
File   : path/to/script.ps1
Lines  : 8792
Issues : 1 errors, 42 warnings, 31 info

---- ERROR (1) ----
  [PSA5001] line   499:  5: plain-text password parameter $PfxPassword;
                                use [SecureString] or [PSCredential]

---- WARNING (42) ----
  [PSA3004]            line  1076     : empty catch block
  [PSA2003]            line  2337: 22: -match against bare $noisePattern ...
  [PSA3001]            line  2422     : Start-Process -ArgumentList; ...
  ...
```

各 issue には `PSAxxxx` コード、severity、行・列、短いメッセージ
が含まれます。

---

## ルールカタログ

`PSA1xxx` — パース・構文系（常に Error）

| コード | デフォルト | 内容 |
|:---|:---:|:---|
| **PSA1001** | ✅ 有効 | 中括弧バランス: `{` の数 vs `}` の数 |
| **PSA1002** | ✅ 有効 | 丸括弧バランス: `(` vs `)` |
| **PSA1003** | ✅ 有効 | 角括弧バランス: `[` vs `]` |

`PSA2xxx` — 変数・スコープ系（Error / Warning / Info）

| コード | 重大度 | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSA2001** | Error | ✅ 有効 | 未定義変数参照（ヒューリスティック） |
| **PSA2002** | Warning | ✅ 有効 | PowerShell 自動変数への代入 (`$args`, `$matches`, `$Event`, `$Host`, `$Profile`, …; 3.6.0 時点で 38 個) |
| **PSA2003** | Warning | ✅ 有効 | `-match` を素の `$variable` に対して使用 |
| **PSA2004** | Warning | ✅ 有効 | `$x -eq $null` は `$null -eq $x` を推奨（コレクションの罠回避） |
| **PSA2005** | Warning | ✅ 有効 | `if` / `while` 条件内に代入演算子 `=` |
| **PSA2006** | Warning | ✅ 有効 | `if` / `while` 条件内にリダイレクト演算子 `>` / `<` |
| **PSA2007** | Warning | ✅ 有効 | パラメータ名が PowerShell 自動変数と衝突 (3.6.0 新規) |
| **PSA2008** | Info | ✅ 有効 | `$Script:Foo++` / `+=` / `-=` の前に初期化がない (3.6.0 新規) |
| **PSA2009** | Warning | ✅ 有効 | `[pscustomobject]@{...}` のイニシャライザで宣言されていないプロパティを `.` 代入している (3.8.0 新規) — PowerShell 5.1 のシール済みオブジェクト実行時例外 (`"<PropName>" の設定中に例外が発生しました: "このオブジェクトにプロパティ '<PropName>' が見つかりません。"`) を静的解析で検出 |
| **PSA2010** | Error | ✅ 有効 | スキャン対象のいずれのファイルにも定義されていない関数呼び出しを検出 (3.9.0 新規) — `Find-Signtool` (正しくは `Find-KitTool 'signtool.exe'`) のような typo を捕捉。 `.psa.config.json` の `psa2010_known_cmdlets` で組み込み cmdlet 一覧を拡張可能 |
| **PSA2011** | Error | ✅ 有効 | `Split-Path -LiteralPath ... -Parent` が Windows PowerShell 5.1 ja-JP で `AmbiguousParameterSet` を発生させるパターンを検出 (3.9.0 新規) — `[System.IO.Path]::GetDirectoryName($path)` または `Split-Path -Path $path -Parent` に修正 |

`PSA3xxx` — コーディングパターン（Warning）

| コード | デフォルト | 内容 |
|:---|:---:|:---|
| **PSA3001** | ✅ 有効 | `Start-Process -ArgumentList`; `ProcessStartInfo` を推奨 |
| **PSA3002** | ✅ 有効 | 行末バッククォートの直後が空行 |
| **PSA3003** | ✅ 有効 | `-match` を空文字列リテラルに対して使用 |
| **PSA3004** | ✅ 有効 | 空の `catch { }` ブロック |
| **PSA3005** | ✅ 有効 | `Start-Transcript -Path` の代わりに `-LiteralPath` を使うべき。 `[`、 `]`、 その他 wildcard メタ文字を含むパスで誤動作 (3.2.0 新規) |
| **PSA3006** | ✅ 有効 | 廃止予定の WMI cmdlet (`Get-WmiObject`, `Invoke-WmiMethod` 等); CIM cmdlet を推奨 (3.6.0 新規) |

`PSA4xxx` — スタイル・情報（Info）

| コード | デフォルト | 内容 |
|:---|:---:|:---|
| **PSA4001** | ✅ 有効 | 未完了マーカー（TODO / FIXME / XXX / HACK） |
| **PSA4002** | ✅ 有効 | 行末の余分な空白 |
| **PSA4003** | ⛔ 無効 | `max_line_length` 超過（既定 120 文字） |
| **PSA4004** | ✅ 有効 | 行末セミコロン |

`PSA5xxx` — セキュリティ（Error / Warning）

| コード | 重大度 | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSA5001** | Error | ✅ 有効 | 平文パスワードパラメータ（`[string]$Password`） |
| **PSA5002** | Warning | ✅ 有効 | `Invoke-Expression` の使用 |
| **PSA5003** | Warning | ✅ 有効 | 脆弱なハッシュアルゴリズム（MD5 / SHA1） |
| **PSA5004** | Warning | ✅ 有効 | `ComputerName` のリテラル文字列ハードコード |

`PSA6xxx` — ベストプラクティス（Warning / Info）

| コード | 重大度 | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSA6001** | Warning | ✅ 有効 | 関数名に PowerShell 承認動詞以外を使用（`Get-Verb` 参照） |
| **PSA6002** | Warning | ⛔ 無効 | cmdlet エイリアスを使用（`ls`, `cd`, `dir`, `where`, …） |
| **PSA6003** | Warning | ✅ 有効 | 関数名の名詞は単数形であるべき |
| **PSA6004** | Warning | ✅ 有効 | `$global:` 変数の定義を避ける |
| **PSA6005** | Warning | ✅ 有効 | Mandatory パラメータにデフォルト値を持たせない |
| **PSA6006** | Warning | ✅ 有効 | switch パラメータのデフォルト値を `$true` にしない |
| **PSA6007** | Info | ✅ 有効 | 値を返す advanced 関数に `[OutputType()]` がない (3.6.0 新規) |
| **PSA6008** | Info | ✅ 有効 | function attribute (`[CmdletBinding()]`, `[Diagnostics.*]` 等) を持つが明示的な `param()` がない (3.6.0 新規) |

`PSA7xxx` — ファイル形式・エンコーディング（Warning / Error）

| コード | Sev | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSA7001** | Warning | ✅ 有効 | PowerShell スクリプトが UTF-8 BOM を持たない（Windows PowerShell 5.1 が BOM 無し UTF-8 を Shift-JIS と誤認する可能性あり） |
| **PSA7002** | Warning | ✅ 有効 | PowerShell スクリプトが LF-only または改行コード混在（正本は CRLF。混在は LF-only コンテンツを CRLF ファイルにプログラム的に挿入した結果として発生することが多く、 AST パーサーには検出されない。 3.7.0 新規） |

`PSA8xxx` — ファイル間整合性 (Warning) — 3.2.0 新規、 ファイル間

| コード | デフォルト | 内容 |
|:---|:---:|:---|
| **PSA8001** | ✅ 有効 (単一ファイル呼出しでは無音) | function body のハッシュ drift。 同じ関数名が 2 つ以上のファイルで異なる正規化済み body を持つ場合、 すべての出現箇所が flag される。 `psa8001_ignore_functions` で関数ごとに抑制可能 (exact 名 + `regex:` パターン)。 |

`PSA9xxx` — 複雑度メトリクス — 3.2.0 新規

| コード | 重大度 | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSA9001** | Info | ⛔ 無効 | 関数 body が `max_function_lines` (デフォルト 200) を超過 |
| **PSA9002** | Warning | ⛔ 無効 | 外部プロセス呼出し (`&` 演算子 / `msiexec` / `signtool` / `inf2cat` / `pnputil` / `bcdedit` 等) の後 5 行以内に `$LASTEXITCODE` / `$?` / `.ExitCode` / `-PassThru` チェックがない |

`PSAPxxxx` — プロジェクト・パイプライン規約ルール — 3.2.0 新規ファミリ、 **すべてデフォルト OFF**

| コード | 重大度 | デフォルト | 内容 |
|:---|:---:|:---:|:---|
| **PSAP0001** | Warning | ⛔ 無効 (opt-in) | phase 関数命名規約: `Invoke-(Prep\|Verify\|Inst)PhaseNN_DescriptiveName`。 名前が `Invoke-(Prep\|Verify\|Inst\|Phase\|Pipeline)` で始まるがカノニカル regex にマッチしない関数のみ flag。 |
| **PSAP0002** | Warning | ⛔ 無効 (opt-in) | 必須スクリプト識別子変数: `$Script:ScriptVersion`、 `$Script:ScriptHash`、 `$Script:ScriptShortTag`。 欠落している識別子ごとに 1 件 PSAP0002 が emit される。 |

### 一部ルールがデフォルト無効である理由

シグナル対ノイズ比を高く保つため、 汎用ルール 2 つはデフォルト無効に
しています。

- **PSA4003（長すぎる行）** — 行長はスタイル的要素が強く、コメント
  ヘッダー、長い URL、ARN ライクな文字列など文脈に大きく依存します。
  チームで長さ制限を合意した時にプロジェクト単位で有効化してください。
- **PSA6002（cmdlet エイリアス）** — 多くの実運用スクリプトで `foreach`
  や `where` が意図的に使われています。スタイルガイドでエイリアスを
  禁止している場合に有効化してください。

コマンドラインで `--enable PSA6002` を指定するか、`.psa.config.json`
の `enable` リストに追加してください。

---

## 検出**しない**事項

- cmdlet の存在確認（PowerShell セッションが必要）
- 型の正しさ（PowerShell は動的型）
- モジュールインポート（`Import-Module` の解決）
- AST 解析を要するスタイルチェック（`PSUseConsistentIndentation`、
  `PSUseCorrectCasing` など — これらは PSScriptAnalyzer の領分）

---

## インライン抑制

行単位:

```powershell
$x -match $pattern  # psa-disable-line PSA2003
```

次の行:

```powershell
# psa-disable-next-line PSA3001,PSA3002
Start-Process -ArgumentList $args ...
```

ファイル全体（通常はファイル先頭付近に配置）:

```powershell
# psa-disable-file PSA4001
```

---

## 設定ファイル（`.psa.config.json`）

`.psa.config.json` がカレントディレクトリにあると、`psa.py` は自動的に
これを読み込みます。明示的に指定するには `--config PATH_OR_URL` を
使います（ローカル・リモート両対応 — 後述）。

設定ファイルは **JSONC** 形式です。JSON に加え、`//` 行コメントと
`/* */` ブロックコメントが使えます。

```jsonc
{
  // デフォルト無効ルールを有効化
  "enable":  ["PSA6002"],

  // デフォルト有効ルールを無効化
  "disable": ["PSA4001"],

  // 最低重大度: "error" / "warning" / "info"
  "severity": "warning",

  // PSA4003 の行長制限
  "max_line_length": 120
}
```

### テンプレートファイル

このディレクトリに [`.psa.config.json.template`](./.psa.config.json.template)
というテンプレートを同梱しています。全オプションをビルトインデフォルト
付きで全てコメントアウト状態で記載しているため、これをコピーして
自分の設定の出発点にできます:

```bash
cp scripts/python/powershell-static-analyzer/.psa.config.json.template \
   .psa.config.json
# 上書きしたい項目だけコメントを外して編集
```

### リモート設定（HTTP / HTTPS）

`--config` はローカルパスに加え、http(s) URL も受け付けます。GitHub
レポジトリに置いたチーム共通設定を参照するのに便利です。**raw** URL
形式を使ってください:

```bash
psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
```

**堅牢性の強化（2.3.0 以降）:**

- Chrome 131 の User-Agent と Sec-Ch-Ua クライアントヒントを送出
  するため、Bot を弾く CDN/WAF のデフォルトフィルタを通過できます。
- TLS 1.2 を最小として明示設定。最大は TLS 1.3 まで自動ネゴシエート。
  証明書検証は常に ON。
- 5xx およびネットワークエラーで指数バックオフリトライ
  （サーバーエラーは 6秒→12秒→24秒、ネットワークエラーは
  2秒→4秒→8秒）。4xx は即座に失敗。
- 環境変数でチューニング可能: `PSA_CONFIG_TIMEOUT`（既定 30 秒）、
  `PSA_CONFIG_MAX_RETRIES`（既定 3）、`PSA_CONFIG_QUIET`。

`raw.githubusercontent.com/...` を使うこと。blob URL
（`github.com/.../blob/...`）は HTML を返すためパース不能。

取得内容は `psa.py` 側ではキャッシュされず、毎回 URL にアクセスします。
詳細な契約は [SPEC.md §5.4](./SPEC.md#54-リモート設定http--https)
を参照。

### 優先順位（低 → 高）

1. ビルトインのデフォルト
2. `.psa.config.json`（暗黙検出） または `--config`（明示指定、
   ローカルファイルまたは URL）
3. CLI 引数（`--enable`, `--disable`, `--include`, `--severity`,
   `--max-line-length`）
4. インライン抑制コメント

---

## CI への組み込み例

GitHub Actions のワークフロー断片（Linux ランナー、Windows / PowerShell
不要）:

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
      - name: Run psa.py
        run: |
          python3 scripts/python/powershell-static-analyzer/psa.py -r \
                  --format sarif scripts/ > psa.sarif
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: psa.sarif
```

error のみで CI を落とす最小構成:

```yaml
      - name: Run psa.py (errors only)
        run: |
          python3 scripts/python/powershell-static-analyzer/psa.py \
                  --severity error \
                  scripts/powershell/download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1
```

---

## PSScriptAnalyzer との併用

PowerShell 5.1 以降が使える環境では、両方走らせるとカバレッジが最大化
されます。

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path path/to/script.ps1 -Severity Warning,Error
```

`psa.py` と PSScriptAnalyzer はほぼ重複しない補完的なチェックを持ち、
共通するルール（例: 空 catch 検出）も通常は同じ判断をします。

---

## 新規チェックの追加方法

`psa.py` の構造は意図的に最小限です。新規チェック `PSA7001` を追加
する手順:

1. `psa.py` 冒頭の `RULES` タプルリストにエントリを追加
   （`(code, severity, default_enabled, message)`）。
2. `check_yourthing(text|clean)` 関数を作成し、
   `severity` / `code` / `line` / `col` / `message` をキーとする dict の
   リストを返す形にする。
3. `analyze_text()` から `if cfg.enabled['PSA7001']:` でガードして呼ぶ。
4. `SPEC.md` §4 に `### 4.N — PSA7001 — タイトル` 見出しと検出仕様を追記
   （`--self-check` を green に保つため）。
5. `test_psa_rules.py` に新ルールの positive / negative / edge ケースを
   追加（ルールカタログテストスイートを完全な状態に保つため）。
6. 上記のルールカタログと `README.md` にも新コードを記載する。
7. 下流の利用側リポジトリ（例:
   [`Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)）
   に通知し、SPEC / README のチェック表を更新してもらう。

リリースタグを打つ前に、 [SPEC.md §12](./SPEC.md#12-self-quality-gates)
で定められた self-quality 3 本柱がすべて exit `0` で通る必要があります:

```bash
python3 test_psa_rules.py
python3 psa.py --self-check
python3 psa.py --config-check .psa.config.json.template
```

`strip_strings_and_comments(text)` ヘルパーは、`''`, `""`, `@'…'@`,
`@"…"@`, `# …`, `<# … #>` 内のコンテンツを無視したいチェックの標準
前処理です — 必ず使用してください。

**リマインダー**: このディレクトリは `psa.py` の**唯一の正典ソース**
です。変更はすべてここで行い、下流の利用側は更新版を取得します。

---

## 動作確認済みの利用側

以下のリポジトリ／PowerShell スクリプトは、（正典ソースである）この
`psa.py` で動作確認されています。

### 同一リポジトリ内

| スクリプト | パス |
|:---|:---|
| `Download-SpeakerDeck.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |
| `Test-PdfMetadata.ps1` | [`scripts/powershell/download-speakerdeck-oracle4engineer/`](../../powershell/download-speakerdeck-oracle4engineer/) |

### 外部リポジトリ

| リポジトリ | スクリプト | 参照 |
|:---|:---|:---|
| [`usui-tk/Deploy-Drivers-For-WindowsServer`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer) | `Deploy-AMDChipsetDriverOnWindowsServer.ps1`, `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`, `Deploy-AMDNpuDriverOnWindowsServer.ps1`, `Deploy-MSBthPanInboxOnWindowsServer.ps1` | [SPEC §A.11](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md#a11-static-analysis-with-psapy)（アナライザ導入手順、Version policy、ベースライン）・[SPEC §A.11.6](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/SPEC.md#a116-self-quality-gates-for-psapy-consumer-side-usage)（`--config-check` / `--self-check` の consumer 側採用方法） |

（新しい PowerShell スクリプト — 内部または外部 — が `psa.py` を
採用したら、このリストを更新してください。）

---

## 設計思想

- **単一ファイル、標準ライブラリのみ**: `pip install` 不要、仮想環境
  不要、バージョン衝突なし。Python 3 が動く環境ならどこにでも置けます。
- **誤検出には保守的**: 「狼が来た」と叫び続けるアナライザは無視される
  運命です。判断に迷うルールはデフォルト無効にし、ユーザーが明示的に
  有効化する設計にしています。
- **PowerShell を理解するトークナイザ**: ヒアドキュメント（`@"…"@`,
  `@'…'@`）、サブ式（`$()`, `@()`）、`$env:` / `$using:` スコープを
  正しく扱い、下流の正規表現ルールが「意味のあるコード」だけを見られる
  ようにしています。

---

## ライセンス

`psa.py` は本リポジトリと同じ MIT License で公開されています。
リポジトリルートの [`LICENSE`](../../../LICENSE) を参照してください。
