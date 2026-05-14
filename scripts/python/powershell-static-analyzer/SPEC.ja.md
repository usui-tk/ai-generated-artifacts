# psa.py 仕様書

> 🇺🇸 [English](./SPEC.md) / 🇯🇵 日本語

本ディレクトリで保守されている PowerShell 静的解析ツール `psa.py` の
正式仕様書です。

**ドキュメントバージョン**: 3.0.0
**適用範囲**: `psa.py` 3.0.0 以降の 3.x 系
**ステータス**: 規範的（normative）

利用者向けの概要は [`README.ja.md`](./README.ja.md) を参照してください。
本ドキュメントは `psa.py` と呼び出し側の間の**契約**を定義します。
すなわち、CLI・設定ファイル・出力フォーマット・終了コード・抑制構文・
環境検出 — ここに記載されていない事項は、パッチリリースで予告なく
変更される可能性があります。

---

## 目次

1. [スコープ](#1-スコープ)
2. [アーキテクチャ](#2-アーキテクチャ)
3. [コマンドラインインターフェース](#3-コマンドラインインターフェース)
4. [ルール仕様](#4-ルール仕様)
5. [設定ファイル](#5-設定ファイル)
6. [出力フォーマット](#6-出力フォーマット)
7. [インライン抑制](#7-インライン抑制)
8. [環境検出](#8-環境検出)
9. [終了コード](#9-終了コード)
10. [トークナイザの挙動](#10-トークナイザの挙動)
11. [拡張ガイド](#11-拡張ガイド)

---

## 1. スコープ

### 1.1 目的

`psa.py` は PowerShell スクリプト（`.ps1`, `.psm1`）用の単一 Python 3
ファイルの静的解析ツールです。PowerShell パーサーが構文解析時には
検出しないバグ群を検出します。[PSScriptAnalyzer][PSScriptAnalyzer] の
デフォルトルールセットでもカバーされない領域（数千行スクリプトでの
括弧バランス、ヒューリスティックによる未定義変数参照、セキュリティ
アンチパターン等）を対象としています。

[PSScriptAnalyzer]: https://github.com/PowerShell/PSScriptAnalyzer

### 1.2 非目標

`psa.py` は PSScriptAnalyzer、PowerShell パーサー、PowerShell ランタイム
本体の**代替品ではありません**。以下は明示的にスコープ外です:

- cmdlet の存在確認（PowerShell セッションが必要）
- 型推論（PowerShell は動的型付け言語）
- モジュールインポートの解決
- AST レベルの解析（インデント一貫性、大文字小文字統一など）— これらは
  PSScriptAnalyzer の領分
- 自動修正・コード書き換え

### 1.3 設計制約

`psa.py` は次の条件を**満たさなければなりません**:

- 単一の Python ファイルであること
- Python 3 標準ライブラリのみを使用すること
- Python 3.8 以降が動く全プラットフォームで動作すること
- 同じ（ファイル, 設定）の組に対し、どのプラットフォームでも同一の
  出力を返すこと
- 決定論的かつ有限時間で完了すること（静的解析はファイルのトークン数
  に対し O(n) で完了**することが望ましい**）
- 入力ファイルを書き換えないこと

### 1.4 バージョニング

`psa.py` は[セマンティックバージョニング 2.0.0](https://semver.org/lang/ja/)
に従います。バージョニング上の**パブリック API 面**は以下です:

- コマンドラインインターフェース（フラグ、終了コード、出力フォーマット
  識別子）
- ルールコード名（`PSAxxxx`）
- JSON 出力スキーマ
- SARIF 出力（SARIF 2.1.0 仕様に従う）
- 設定ファイルスキーマ

`psa.py` 内部の Python モジュール境界（関数名・クラス名）はパブリック
API には**含まれず**、いつでも変更されえます。

---

## 2. アーキテクチャ

### 2.1 コンポーネント概要

```
                  ┌──────────────────┐
   入力           │  expand_paths()  │   再帰的glob展開
   ファイル /     │                  │   (.ps1, .psm1 を収集)
   ディレクトリ ─▶└────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  read_text()     │   UTF-8 デコード
                  └────────┬─────────┘   (不正バイトは置換)
                           │
                           ▼
                  ┌────────────────────────────┐
                  │ strip_strings_and_comments │  行番号を保持
                  └────────┬───────────────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  analyze_text()  │   有効化ルールを全て実行
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  抑制フィルタ    │   インライン / 行 / ファイル単位
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  重大度フィルタ  │
                  └────────┬─────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  フォーマッタ    │   text / json / sarif
                  └────────┬─────────┘
                           │
                           ▼
                       標準出力
```

### 2.2 処理モデル

`psa.py` はバッチプロセッサです。各入力ファイルについて:

1. UTF-8 で**読み込む**（不正バイトは置換）
2. **トークン化**：文字列とコメントの内容を同じ長さの空白に置換
   （行・列位置を保持）
3. 有効化された各ルールを生テキストまたはトークン化テキストに対して
   **実行**し、issue リストを生成
4. インライン抑制ディレクティブで issue を**フィルタリング**
5. 最低重大度（`--severity`）で issue を**フィルタリング**
6. 同一の (code, line, col, message) タプルを**重複排除**
7. (line, col, code) で**ソート**して安定的・再現可能な出力にする

複数の入力ファイルは独立に処理されます。クロスファイル解析は行いません。

### 2.3 Issue の内部表現

各ルールは次のキーを持つ dict を返します:

| キー | 型 | 説明 |
|:---|:---|:---|
| `severity` | str | `"error"` / `"warning"` / `"info"` |
| `code` | str | 新しい `PSAxxxx` コード |
| `line` | int | 1 始まりの行番号。ファイル全体の問題は `0` |
| `col` | int | 1 始まりの列番号。該当なしは `0` |
| `message` | str | 1 行の人間可読な説明 |

---

## 3. コマンドラインインターフェース

### 3.1 構文

```
psa.py [OPTIONS] [PATH ...]
psa.py --list-rules
psa.py --check-env
psa.py --version
```

### 3.2 位置引数

| 引数 | 説明 |
|:---|:---|
| `PATH` | ファイルパス、ディレクトリパス、または glob パターン。POSIX 非対応シェルでも動作するよう `psa.py` 自身が glob 展開を行います。ディレクトリは `-r` を指定しない限りスキップされます。 |

### 3.3 オプション

| フラグ | 引数 | 既定値 | 説明 |
|:---|:---|:---|:---|
| `-r`, `--recursive` | — | off | ディレクトリ引数を再帰的に走査（`*.ps1`, `*.psm1`） |
| `--format` | `text\|json\|sarif` | `text` | 出力フォーマット。§6 参照 |
| `--severity` | `error\|warning\|info` | （全て） | 報告する最低重大度 |
| `--enable` | `CODE[,CODE...]` | — | 指定ルールを有効化。繰り返し可 |
| `--disable` | `CODE[,CODE...]` | — | 指定ルールを無効化。繰り返し可 |
| `--include` | `CODE[,CODE...]` | — | 指定ルールのみ実行。繰り返し可 |
| `--config` | `PATH_OR_URL` | 暗黙検出 | ローカルファイルパスまたは http(s) URL から設定読み込み。§5.4 参照 |
| `--max-line-length` | `N` | `120` | `PSA4003` の閾値 |
| `--no-color` | — | 自動 | ANSI カラー出力を無効化。stdout が TTY でない場合と `NO_COLOR` 環境変数が設定されている場合は自動的に無効化されます |
| `--list-rules` | — | — | ルールカタログを stdout に出力し終了（`0`） |
| `--check-env` | — | — | 環境検出（§8）を実行し終了（`0`） |
| `--show-env` | — | off | 通常解析出力に環境サマリを前置。終了コードに影響なし |
| `--version` | — | — | バージョン情報を出力し終了（`0`） |

### 3.4 引数形式

ルールコードは `PSAxxxx` 形式で指定します（例: `PSA2001`、
大文字小文字非区別）。カンマ区切りリストを 1 つの引数値として
渡せます（例: `--disable PSA4001,PSA4002`）。

### 3.5 設定の優先順位

設定は低優先度から高優先度の順に積層されます:

1. ビルトインデフォルト（`psa.py` 内の `RULES` テーブル）
2. 設定ファイル（`.psa.config.json`）— §5 参照
3. CLI フラグ
4. インライン抑制ディレクティブ — §7 参照

優先度の高い設定は、各ルール単位で低優先度の設定を上書きします。
「全か無か」のカスケードはありません。`--disable` で 1 ルールを無効化
しても、他のルールは現在の状態が維持されます。

---

## 4. ルール仕様

このセクションは規範的です。各ルールの検出ロジックは、代替実装で同じ
挙動を再現できる程度に詳述しています。

### 4.1 PSA1001 — 中括弧バランス

- **重大度**: Error
- **デフォルト**: 有効

**検出**: 文字列・コメント除去後（§11）、クリーンテキスト中の `{` と
`}` の出現数をカウント。数が一致しない場合に報告。

**報告位置**: line `0`, col `0`（ファイル全体）。

### 4.2 PSA1002 — 丸括弧バランス

- **重大度**: Error
- **デフォルト**: 有効

**検出**: PSA1001 と同様、`(` / `)` を対象。

### 4.3 PSA1003 — 角括弧バランス

- **重大度**: Error
- **デフォルト**: 有効

**検出**: PSA1001 と同様、`[` / `]` を対象。

### 4.4 PSA2001 — 未定義変数参照

- **重大度**: Error
- **デフォルト**: 有効

**検出**: ヒューリスティック。各関数ブロック（`function 名前 { … }`）に
対し:

1. ローカル代入名を収集（`$x = …`, `foreach ($x in …)`,
   `for ($x = …`, `param(…)` ブロック、インラインパラメータリスト）
2. グローバル代入名を収集（関数外の代入）
3. 関数本体内の全 `$variable` 参照を走査
4. 参照名がローカル集合・グローバル集合・`AUTO_VARS`（PowerShell の
   自動変数）・外部スコープ（`$env:`, `$using:`）のいずれにも含まれない
   場合、(変数名, 関数名) ペアごとに 1 回報告

**報告位置**: 関数本体内の行・列。

**既知の限界**: スプラッティング（`@args`）、動的に解決される変数名
（`Get-Variable`）、モジュールエクスポート変数は理解しません。誤検出が
発生する可能性があります。意図的な場合は
`# psa-disable-line PSA2001` で抑制してください。

### 4.5 PSA2002 — auto-variable 上書き

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `$name = …` のうち、`name`（小文字化後）が RISKY_SHADOW_VARS
集合に含まれるもの:
`args`, `lastexitcode`, `input`, `matches`, `foreach`, `host`,
`true`, `false`。

### 4.6 PSA2003 — `-match` を素の変数に対して使用

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `-match $name` パターン（`$name` が `$null` でないもの）。
PowerShell では `-match $null` が `$true` を返すため、これは典型的な
バグの温床。

### 4.7 PSA2004 — `$null` を `-eq`/`-ne` の右辺に配置

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `$variable -eq $null` パターン（`-ne`, `-ceq`, `-cne`,
`-ieq`, `-ine` も対象）。PowerShell では `$null -eq $x` 形式が安全で、
理由は `$x` がコレクションの場合、`$null` 右辺形式は**コレクション要素
のうち $null と等しいもの**を返すため、ブール値にならないためです。

### 4.8 PSA2005 — 条件式内の代入演算子

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `if|while|elseif ( $variable = ...` パターン（`=` の次が
`=` でないもの。`==` の誤検出を回避）。

### 4.9 PSA2006 — 条件式内のリダイレクト演算子

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `if|while|elseif ( $variable [<>] ...` パターン。
PowerShell では `>` `<` はファイルリダイレクションで、比較演算子では
ありません。`-gt` / `-lt` を使うべきです。

### 4.10 PSA3001 — `Start-Process -ArgumentList`

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `Start-Process … -ArgumentList` パターン。`-ArgumentList`
パラメータは空白を含むパスでクオート問題がよく知られています。
`System.Diagnostics.ProcessStartInfo` を推奨。

### 4.11 PSA3002 — バッククォート継続行の次が空行

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: 単一のバッククォート（`` `` `` ではない）で終わる行で、
次の行が空または空白のみの行。

**ソーステキスト**: バッククォート後の末尾空白も重要なため、本ルールは
生テキスト（除去前）を検査します。

### 4.12 PSA3003 — `-match` を空文字列に対して使用

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `-match ''` または `-match ""` パターン。常に真を返す。

### 4.13 PSA3004 — 空の catch ブロック

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `catch [型]? { }` で中括弧の間に内容なし。`catch {\n}`
形式も 4 行ウィンドウで検出可能。

### 4.14 PSA4001 — 未完了マーカー

- **重大度**: Info
- **デフォルト**: 有効

**検出**: `#` コメント内に `TODO`, `FIXME`, `XXX`, `HACK` のいずれか
（大文字小文字区別、単語境界）。

### 4.15 PSA4002 — 行末空白

- **重大度**: Info
- **デフォルト**: 有効

**検出**: 改行文字を除いた行の末尾文字が `\t` または `' '`。

### 4.16 PSA4003 — 長すぎる行

- **重大度**: Info
- **デフォルト**: **無効**

**検出**: 可視長が `max_line_length`（既定 120）を超える行。
`--max-line-length` または `.psa.config.json` の `max_line_length` で
設定可能。

### 4.17 PSA4004 — 行末セミコロン

- **重大度**: Info
- **デフォルト**: 有効

**検出**: 末尾空白を除去した行が `;` 単独で終わる場合（`;;` は意図的な
マーカーであることが多いため対象外）。

### 4.18 PSA5001 — 平文パスワードパラメータ

- **重大度**: Error
- **デフォルト**: 有効

**検出**: `[string]$NamePassword`, `[string]$NamePwd`,
`[string]$NameCredential` パターン（大文字小文字区別なし、接頭・接尾辞
も含む）。PowerShell では `[SecureString]` や `[PSCredential]` を使う
べきです。

### 4.19 PSA5002 — `Invoke-Expression`

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `Invoke-Expression` またはエイリアス `iex` をコマンド語として
使用。他言語の `eval()` 相当。

### 4.20 PSA5003 — 脆弱なハッシュアルゴリズム

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `MD5(CryptoServiceProvider|Managed)?`,
`SHA1(CryptoServiceProvider|Managed)?`, または `-Algorithm "MD5"`/
`"SHA1"` パターン。

### 4.21 PSA5004 — `ComputerName` のハードコード

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `-ComputerName "literal"`（シングルクオート可）パターン。
`localhost`, `.`, `127.0.0.1` はホワイトリスト除外。

### 4.22 PSA6001 — 承認動詞以外の使用

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `function 動詞-名詞` 形式で、動詞（小文字化）が PowerShell
承認動詞集合に含まれないもの（`APPROVED_VERBS` に約 100 動詞を
ハードコード、`Get-Verb` の出力相当）。

### 4.23 PSA6002 — cmdlet エイリアスの使用

- **重大度**: Warning
- **デフォルト**: **無効**

**検出**: 標準 cmdlet エイリアス（`ls`, `cd`, `dir`, `where` など
約 150 個ハードコード）がコマンド位置（行頭、`;` `|` `&` `(` の直後）に
出現。

**除外**:

- `foreach (`, `switch (`, `select (`, `sort (`, `set (` — これらは
  PowerShell キーワード形式であり、エイリアスではない
- `name = …` — ハッシュテーブルキー / プロパティ代入

### 4.24 PSA6003 — 関数名の名詞が複数形

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `動詞-名詞` 形式の関数名で、名詞が小文字化後 `s` で終わり、
かつ正当な複数形ホワイトリストに含まれないもの:
`process`, `address`, `progress`, `access`, `success`, `class`,
`pass`, `business`, `analysis`, `basis`, `series`, `species`,
`thesis`, `crisis`, `status`, `bus`。`ss` で終わる名前も除外。

### 4.25 PSA6004 — `$global:` 変数の定義

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `$global:Name = …` パターン。`$script:` またはパラメータ
渡しを推奨。

### 4.26 PSA6005 — Mandatory パラメータにデフォルト値

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `[Parameter(…Mandatory…)] [型] $Name = デフォルト` パターン。
Mandatory パラメータは決してデフォルトを使用しないため、デフォルト
宣言は誤解を招きます。

### 4.27 PSA6006 — switch パラメータのデフォルト値が `$true`

- **重大度**: Warning
- **デフォルト**: 有効

**検出**: `[switch]$Name = $true` パターン。switch は常に `$false`
デフォルトであり、`$true` 設定は呼び出し側を混乱させます。

---

## 5. 設定ファイル

### 5.1 場所と検出順序

`psa.py` は次の順で設定ファイルを決定します:

1. `--config` で指定された値（ローカルパスまたは http(s) URL — §5.4
   参照）。読み込み・パースに失敗した場合は、stderr にエラーを出力して
   終了コード `2` で終了します。
2. カレントディレクトリの `.psa.config.json`（暗黙検出）。`--config`
   未指定の場合のみ試行されます。

両方とも存在しない場合はビルトインデフォルトが適用されます。

### 5.2 ファイル形式

設定ファイルは **JSONC** 形式です。通常の JSON に次の 2 つの拡張を
加えたもの:

- `// 行コメント` — 行末まで
- `/* ブロックコメント */` — 複数行可

文字列リテラル内のコメント風シーケンスは保持されます。ブロックコメント
内の改行も保持されるため、JSON パースエラー時の行番号が意味を持つよう
になっています。

`psa.py` と同じディレクトリに `.psa.config.json.template` という
テンプレートファイルが同梱されています。全フィールドをビルトイン
デフォルト値とともに記載しており、`cp .psa.config.json.template
.psa.config.json` でそのまま利用可能です。

ファイルは UTF-8 でエンコードされ、JSON **オブジェクト**としてパースされ
なければなりません（配列やスカラーは不可）。全トップレベルフィールドは
オプションで、`{}` も有効な設定です。

### 5.3 スキーマ

```jsonc
{
  // 強制有効化（デフォルト無効状態を上書き）
  "enable": ["PSA6002"],

  // 強制無効化
  "disable": ["PSA4001"],

  // 報告する最低重大度: "error" / "warning" / "info"
  "severity": "warning",

  // PSA4003 の行長閾値
  "max_line_length": 120
}
```

| フィールド | 型 | 既定値 | 備考 |
|:---|:---|:---|:---|
| `enable` | string 配列 | `[]` | 各文字列はルールコード（`PSAxxxx`）。未知のコードは黙って無視 |
| `disable` | string 配列 | `[]` | `enable` と同じ形式 |
| `severity` | string | `"info"` | 表示重大度のフロア |
| `max_line_length` | int | `120` | 正の整数 |

### 5.4 リモート設定（HTTP / HTTPS）

`--config` はファイルパスに加え、http(s) URL も受け付けます:

```bash
psa.py --config https://raw.githubusercontent.com/<owner>/<repo>/<branch>/.psa.config.json <script>.ps1
```

GitHub の場合、**raw** URL 形式を使用してください
（`raw.githubusercontent.com/...`）。通常の blob URL
（`github.com/.../blob/...`）は HTML を返すため JSON パースに失敗
します。

#### 5.4.1 TLS 設定

`psa.py` は SSL コンテキストを明示的に構築します:

| 設定 | 値 | 理由 |
|:---|:---|:---|
| `minimum_version` | `TLSv1_2` | 2020 年以降の業界標準。TLS 1.0/1.1 は RFC 8996（2021）で非推奨指定済みのため提供しません。GitHub と主要 CDN は TLS 1.2 以上を要求 |
| `maximum_version` | (デフォルト) | 未設定。ハンドシェイクで両端が共通サポートする最高バージョンを自動ネゴシエート。モダンサーバーには TLS 1.3、古いサーバーには TLS 1.2 を選ぶ |
| `verify_mode` | `CERT_REQUIRED` | `ssl.create_default_context()` 経由で OS トラストストアを読み込み。証明書検証は**常に ON** で、無効化はできません |
| `check_hostname` | `True` | ホスト名不一致でハンドシェイク失敗 |

**「サーバーがサポートする最高バージョンに自動切替」**の挙動は TLS
ハンドシェイク自体に内在しているため、`psa.py` 側でカスタムの
ダウングレード再試行ループは不要です。

#### 5.4.2 リクエストヘッダー

CDN や WAF（特に Cloudflare 配下のサイト）が公開 raw ファイルでも
明らかな Bot User-Agent を拒否することがあるため、`psa.py` は最近の
Chrome ビルドとして自己申告します:

```
User-Agent       : Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36
Accept           : application/json, text/plain, text/*, */*
Accept-Language  : en-US,en;q=0.9
Accept-Encoding  : identity
Sec-Ch-Ua        : "Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"
Sec-Ch-Ua-Mobile : ?0
Sec-Ch-Ua-Platform : "Windows"
```

Sec-Ch-Ua クライアントヒントは意図的に User-Agent 文字列と整合させて
います。Chrome バージョンを更新する際は両者をセットで上げてください。

#### 5.4.3 リトライポリシー

`psa.py` は一時的な失敗時に指数バックオフで再試行します。これは
姉妹プロジェクト `Download-SpeakerDeck.ps1` の
`Invoke-WebRequestWithRetry` パターンを移植したものです。

| 結果 | 動作 | 次回試行までのバックオフ |
|:---|:---|:---|
| 成功（`2xx`） | ボディを返却 | — |
| サーバーエラー（`5xx`） | 再試行 | `2^attempt × 3` 秒 (6 秒, 12 秒, 24 秒, …) |
| ネットワーク・タイムアウト・接続エラー | 再試行 | `2^attempt` 秒 (2 秒, 4 秒, 8 秒, …) |
| クライアントエラー（`4xx`: 404, 403, 401, …） | 即座に中断 | — (永続的な失敗のため再試行は無駄) |

初回試行を含む総試行回数は `PSA_CONFIG_MAX_RETRIES`（既定 3）です。
試行回数を使い切った場合は最後の例外が `Config.load()` に伝播し、
ユーザー向けエラーに変換されます。

再試行ごとに stderr に 1 行のメッセージを出力します:

```
psa.py: HTTP 503 from https://example.com/.psa.config.json; retry 1/2 in 6s
psa.py: HTTP 503 from https://example.com/.psa.config.json; retry 2/2 in 12s
```

`PSA_CONFIG_QUIET=1` を設定すると抑制できます。

#### 5.4.4 環境変数によるチューニング

| 変数 | 既定値 | 効果 |
|:---|---:|:---|
| `PSA_CONFIG_TIMEOUT` | `30` | 1 試行あたりの接続+読み取りタイムアウト（秒） |
| `PSA_CONFIG_MAX_RETRIES` | `3` | 初回試行を含む総試行回数。`1` でリトライ無効化 |
| `PSA_CONFIG_QUIET` | (未設定) | 任意の非空値を設定すると、stderr へのリトライ進捗メッセージを抑制 |

不正な値（数値でない・非正数）は黙ってデフォルトに復帰し、タイポで
CI を壊さないようになっています。

#### 5.4.5 キャッシュ

リモート設定は**1 回の呼び出しにつき 1 回**取得され、ディスクに
キャッシュされません。`psa.py` の呼び出しごとに毎回上流 URL に
アクセスします。高頻度の CI シナリオでは、設定をローカルファイルに
ミラーリングし、`--config` でそれを指すことを検討してください。

### 5.5 優先順位

同じルールが `enable` と `disable` の両方に現れた場合、結果は
**実装定義**です。順序に依存しないでください。CLI フラグは設定ファイル
を常に上書きします。

---

## 6. 出力フォーマット

### 6.1 テキストフォーマット

`--format text`（既定）で出力されます。構造:

```
==== psa.py: PowerShell Static Analyzer ====
File   : <パス>
Lines  : <総行数>
Issues : <N> errors, <M> warnings, <K> info

---- ERROR (<N>) ----
  [<コード>] line <L>:<C>: <メッセージ>
  ...

---- WARNING (<M>) ----
  ...

---- INFO (<K>) ----
  ...
```

issue がない場合、本体は `  (no issues found)` となります。

ANSI カラーエスケープは stdout が TTY で `NO_COLOR` 環境変数が未設定の
場合に出力されます。`--no-color` は無条件にカラーを無効化します。

### 6.2 JSON フォーマット

`--format json` で出力されます。単一入力ファイルの場合:

```jsonc
{
  "file": "<パス>",
  "lines": 4106,
  "summary": {
    "errors": 0,
    "warnings": 17,
    "info": 0
  },
  "issues": [
    {
      "code": "PSA3004",
      "severity": "warning",
      "line": 211,
      "col": 0,
      "message": "empty catch block"
    }
    // ...
  ],

  // --show-env 指定時のみ:
  "environment": { /* §8 参照 */ }
}
```

複数入力ファイルの場合はトップレベルがラップされます:

```jsonc
{
  "files": [ /* 各ファイルの上記オブジェクト（environment 除く） */ ],
  "environment": { /* §8 参照、--show-env 指定時のみ */ }
}
```

JSON 出力は常に 2 スペースインデントの整形出力で、ASCII エスケープは
行いません（`ensure_ascii=False`）。

### 6.3 SARIF 2.1.0 フォーマット

`--format sarif` で出力されます。SARIF 2.1.0 スキーマに準拠。
トップレベル構造:

```jsonc
{
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "psa.py",
          "version": "2.1.0",
          "informationUri": "...",
          "rules": [ /* 27 個のルール記述子 */ ]
        }
      },
      "results": [ /* issue 1 件につき 1 エントリ */ ],
      "properties": {
        "environment": { /* §8、--show-env 指定時のみ */ }
      }
    }
  ]
}
```

重大度マッピング（SARIF `level` フィールド）:

| `psa.py` 重大度 | SARIF `level` |
|:---|:---|
| `error` | `error` |
| `warning` | `warning` |
| `info` | `note` |

`properties.environment` 拡張は、ツール固有プロパティとして SARIF 仕様で
許可されている `psa.py` 固有の拡張です。

---

## 7. インライン抑制

### 7.1 構文

抑制ディレクティブは `psa.py` がパースする PowerShell コメントです:

```ebnf
suppression  ::=  "#" whitespace? directive
directive    ::=  scope whitespace codes
scope        ::=  "psa-disable-line"      // 同じ行で抑制
              |  "psa-disable-next-line"  // 次の行で抑制
              |  "psa-disable-file"        // ファイル全体で抑制
codes        ::=  code ( ( "," | whitespace ) code )*
code         ::=  "PSA" digit{4}  | "C" digit{1,2}
```

ディレクティブ名は大文字小文字非区別。コードはどちらの形式でも可。

### 7.2 セマンティクス

- `psa-disable-line CODES` — コメントが現れたソース行上で、指定コードを
  抑制
- `psa-disable-next-line CODES` — 直後のソース行で指定コードを抑制
- `psa-disable-file CODES` — ファイル全体で位置によらず指定コードを抑制。
  複数の `psa-disable-file` コメントは累積

抑制はルール実行**後**に適用されます。ルールは常に実行され、マッチした
issue が出力前にフィルタされます。

### 7.3 例

```powershell
$x -match $pattern  # psa-disable-line PSA2003

# psa-disable-next-line PSA3001,PSA3002
Start-Process -ArgumentList $args ...

# psa-disable-file PSA4001
function Do-Something {
  # TODO: ここは報告されない
}
```

---

## 8. 環境検出

### 8.1 目的

環境検出は**情報提供**機能です。実行環境に PowerShell と
PSScriptAnalyzer が存在するかをプローブします。制約のある環境
（PowerShell が未インストールの AI サンドボックス等）で `psa.py` を
使うユーザーが、補完ツールの利用可否を確認できるようにすることが目的
です。出力は**助言的**であり、終了コード・issue 数・任意のフィルタに
**一切影響しません**。

### 8.2 動作モード

環境検出をトリガーする CLI フラグは 2 つあります:

- `--check-env`: 検出のみ実行し終了。解析は行わない。検出結果に
  かかわらず終了コードは `0`。
- `--show-env`: 通常解析出力に環境サマリを前置。解析は通常通り続行。
  PowerShell がインストール済みで起動が遅い場合、検出処理で最大
  約 2 × `ENV_PROBE_TIMEOUT` 秒（現状各 10 秒のため、最悪約 20 秒）の
  遅延が発生する可能性あり。

### 8.3 プローブ手順

1. **PowerShell バイナリの検出**: 次の順で試行 — `pwsh`, `powershell`,
   `powershell.exe`。`shutil.which()` で最初に解決したものを採用。

2. **PowerShell バージョンのプローブ**: 次のコマンドを実行:

   ```
   <バイナリ> -NoProfile -NonInteractive -Command "$PSVersionTable.PSVersion.ToString()"
   ```

   タイムアウトは 10 秒。タイムアウト、非ゼロ終了、空出力のいずれかが
   発生した場合、PowerShell は利用不可と報告。

3. **PSScriptAnalyzer のプローブ**（手順 2 が成功した場合のみ）:

   ```
   <バイナリ> -NoProfile -NonInteractive -Command \
     "$m = Get-Module -ListAvailable PSScriptAnalyzer | \
      Sort-Object Version -Descending | Select-Object -First 1; \
      if ($m) { $m.Version.ToString() }"
   ```

   タイムアウトは 10 秒。インストール済みの最新バージョンを報告。

### 8.4 出力（テキストフォーマット）

```
==== psa.py: Environment Detection ====
psa.py        : <psa バージョン>
Python        : <Python バージョン> (<OS> <リリース>)
PowerShell    : <コマンド> <PSVersion> at <フルパス>
                ^^^ 未検出時は "not found on PATH"
PSScriptAnalyzer : <モジュールバージョン> (available)
                ^^^ 未検出時は "not installed"

Info:
  <3 つのメッセージ亜種から 1 つ — §8.5 参照>
```

### 8.5 推奨メッセージの亜種

`psa.py` は次の 3 つから 1 つの info レベルメッセージを選択します:

| PowerShell | PSScriptAnalyzer | メッセージ |
|:---:|:---:|:---|
| ✓ | ✓ | "PSScriptAnalyzer は利用可能です… 両方のツールを実行することを推奨" |
| ✓ | ✗ | "PowerShell は利用可能ですが、PSScriptAnalyzer は未インストールです。インストールには:…" |
| ✗ | ✗ | "psa.py はスタンドアロンモードで動作中です。PATH 上に PowerShell ランタイムが検出されませんでした" |

### 8.6 出力（JSON / SARIF）

返却されるデータ構造（`--check-env --format json`, `--show-env
--format json`, SARIF `properties.environment` で使用）:

```jsonc
{
  "python_version": "3.12.3",
  "python_executable": "/usr/bin/python3",
  "platform": "Linux 6.18.5",
  "psa_version": "2.1.0",
  "powershell": {
    "command": "pwsh",
    "path": "/usr/bin/pwsh",
    "version": "7.4.6"
  } | null,
  "psscriptanalyzer": {
    "version": "1.22.0"
  } | null
}
```

`powershell` と `psscriptanalyzer` は未検出時 `null`。データモデルは
安定です。将来のマイナーリリースで**新キー追加**は行われ得ますが、
メジャーバージョン内で既存キーの名称変更・削除は行いません。

### 8.7 決定論性と副作用

環境検出は**冪等**かつ**副作用なし**です:

- ファイルへの書き込みなし
- ネットワーク呼び出しなし
- 環境変数の書き換えなし
- プローブされる PowerShell プロセスは `-NoProfile -NonInteractive`
  で実行され、ユーザープロファイル実行をバイパス

プローブの失敗（タイムアウト、バイナリ不在、非ゼロ終了）は、Python
例外として伝播することは**ありません**。常に「ツールが検出されなかった」
に縮約されます。

---

## 9. 終了コード

| 終了コード | 条件 |
|:---:|:---|
| `0` | 解析成功。error も warning も報告されず。`--list-rules`, `--check-env`, `--version`, `--help` も `0` を返す |
| `1` | 解析成功。warning は報告されたが error なし。info のみで `1` にはならない |
| `2` | 解析成功。1 件以上の error が報告。**または**起動時致命的エラー（入力ファイルなし、設定ファイル読み込み失敗など） |
| `130` | SIGINT（Ctrl-C）による中断 |

`--show-env` フラグは、環境プローブの結果がいかなるものであっても、
終了コードに**一切影響しません**。

---

## 10. トークナイザの挙動

トークナイザ（`strip_strings_and_comments`）は、文字列、ヒアドキュメント、
コメントの内容を空白文字に置換しつつ、行番号と列オフセットを保持します。
これにより、下流の正規表現ベースのルールは、クオートルールを再実装する
ことなく「真の」 PowerShell コードのみを見ることができます。

### 10.1 認識される構文

| 構文 | 挙動 |
|:---|:---|
| `# …\n` | 行末まで空白に置換 |
| `<# … #>` | 空白に置換、複数行可 |
| `'…'` | 空白に置換。`''` はエスケープされた単一引用符として扱う |
| `"…"` | 空白に置換。**ただし、内部の `$variable` 参照は保持**（未定義変数検出に必須）。`` `" `` はバッククォートエスケープされた引用符として認識 |
| `@'\n…\n'@` | ヒアドキュメント（単一引用符）。空白に置換 |
| `@"\n…\n"@` | ヒアドキュメント（二重引用符）。`"…"` と同じく `$variable` を保持 |

### 10.2 変数識別子の抽出

二重引用符文字列とヒアドキュメント内では、次の形式の変数参照を
保持します:

- `$name` — 単純な識別子
- `$scope:name` — スコープ付き（`$env:`, `$using:` など）
- `${complex}` — 中括弧付き（任意の内容）

### 10.3 行の保持

トークナイザの出力は、入力と**完全に同じ**「行ごとの文字数」と「行数」
を持ちます。これは正確な行・列レポートに不可欠です。

---

## 11. 拡張ガイド

### 11.1 新ルールの追加

`PSA7001` を追加する場合:

1. `psa.py` 冒頭の `RULES` タプルリストにエントリを追加:

   ```python
   ('PSA7001', 'warning', None, True, 'Short message'),
   ```

   4 タプル: `(code, severity, default_enabled, short_message)`

2. `check_yourthing(...)` 関数を実装。標準の 5 キー（§2.3 参照）を
   持つ issue dict のリストを返す。

3. `analyze_text()` に組み込む:

   ```python
   if cfg.enabled['PSA7001']:
       raw += check_yourthing(clean)
   ```

4. `README.md`, `README.ja.md`, 本 SPEC §4（および日本語版）の
   ルール表に新コードを記載。

5. マイナーバージョンを上げる（例: `2.1.0` → `2.2.0`）。

### 11.2 新出力フォーマットの追加

1. `format_yourformat(per_file_results, env_info=None)` を実装。

2. `parse_args()` の `--format` choices に追加:

   ```python
   p.add_argument('--format', choices=('text', 'json', 'sarif', 'yourformat'), ...)
   ```

3. `main()` でディスパッチ:

   ```python
   elif cfg.format == 'yourformat':
       print(format_yourformat(per_file, env_info))
   ```

4. 本 SPEC §6 に記載。

### 11.3 新設定フィールドの追加

1. `Config.__init__()` にフィールドを既定値付きで追加。

2. `Config.load()` で `data` からパース。

3. ルール実装内で使用。

4. 本 SPEC §5.2 に記載。

---

## 付録 A — ルール重大度マトリクス

| コード | 重大度 | デフォルト |
|:---|:---|:---:|
| PSA1001 | error | ✅ |
| PSA1002 | error | ✅ |
| PSA1003 | error | ✅ |
| PSA2001 | error | ✅ |
| PSA2002 | warning | ✅ |
| PSA2003 | warning | ✅ |
| PSA2004 | warning | ✅ |
| PSA2005 | warning | ✅ |
| PSA2006 | warning | ✅ |
| PSA3001 | warning | ✅ |
| PSA3002 | warning | ✅ |
| PSA3003 | warning | ✅ |
| PSA3004 | warning | ✅ |
| PSA4001 | info | ✅ |
| PSA4002 | info | ✅ |
| PSA4003 | info | ⛔ |
| PSA4004 | info | ✅ |
| PSA5001 | error | ✅ |
| PSA5002 | warning | ✅ |
| PSA5003 | warning | ✅ |
| PSA5004 | warning | ✅ |
| PSA6001 | warning | ✅ |
| PSA6002 | warning | ⛔ |
| PSA6003 | warning | ✅ |
| PSA6004 | warning | ✅ |
| PSA6005 | warning | ✅ |
| PSA6006 | warning | ✅ |

---

## 付録 B — ドキュメント履歴

| バージョン | 日付 | 変更 |
|:---|:---|:---|
| 2.3.0 | 2026 | リモート設定取得を堅牢化: 明示的な TLS 1.2 最小バージョン設定（最大は TLS 1.3 まで自動ネゴシエート）、ブラウザライク User-Agent（Chrome 131）+ Sec-Ch-Ua クライアントヒント、5xx およびネットワークエラーに対する指数バックオフリトライ（4xx はリトライしない）、環境変数によるチューニング（`PSA_CONFIG_TIMEOUT`, `PSA_CONFIG_MAX_RETRIES`, `PSA_CONFIG_QUIET`）。§5.4 参照 |
| 2.2.0 | 2026 | 設定ファイルを JSONC 形式に拡張（行 `//` ・ブロック `/* */` コメント対応）。`--config` がローカルパスに加え http(s) URL を受け付け（§5.4）。テンプレートファイル `.psa.config.json.template` を同梱し、全オプションをビルトインデフォルト付きで記載 |
| 2.1.0 | 2026 | 初版。`psa.py` 2.1.0 向けに §8（環境検出）を追加。既存挙動（ルール、フォーマット、CLI）は `psa.py` 2.0.0 から継承 |
