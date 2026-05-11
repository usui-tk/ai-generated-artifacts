# PowerShell スクリプト仕様書 (SPEC)

> **このドキュメントの目的**
>
> 本ファイルは、このリポジトリのスタイルに従ったエンタープライズ品質の PowerShell スクリプトを構築するための正式な仕様書です。LLM (Claude) が新しいプロジェクトの開始時に直接読み取り、規約を一から再導出する必要がないように記述されています。
>
> **最も重要なルール**：あるふるまいが **Part A（共通仕様）** に記述されている場合、新しいスクリプトは必ずそこで参照されている既存実装を再利用しなければなりません。フェーズヘッダー、ログマーカー、環境診断、エラー JSONL フォーマット、psa.py 静的解析ツールを再設計してはいけません。これらは多くのリビジョンを経て堅牢化されており、実環境のバグ修正を反映しています。書き直すと退行（リグレッション）を招きます。
>
> **Part B** は、新しいスクリプト固有の処理ロジックを文書化するためのテンプレートとして使用してください。Part A のすべては共通仕様として継承されます。

---

## 目次

- [Part A — 共通仕様（すべてのスクリプトで再利用可能）](#part-a--共通仕様すべてのスクリプトで再利用可能)
  - [A.1 参考アセット](#a1-参考アセット)
  - [A.2 ソースファイル形式](#a2-ソースファイル形式)
  - [A.3 バナーとバージョン識別](#a3-バナーとバージョン識別)
  - [A.4 フェーズアーキテクチャ](#a4-フェーズアーキテクチャ)
  - [A.5 ログ規約](#a5-ログ規約)
  - [A.6 パス取扱い（-LiteralPath ルール）](#a6-パス取扱い-literalpath-ルール)
  - [A.7 パラメーター規約](#a7-パラメーター規約)
  - [A.8 エラーと診断の規約](#a8-エラーと診断の規約)
  - [A.9 CSV / JSONL カラム規約](#a9-csv--jsonl-カラム規約)
  - [A.10 環境評価 (Phase 1)](#a10-環境評価-phase-1)
  - [A.11 psa.py による静的解析](#a11-psapy-による静的解析)
  - [A.12 バイリンガルドキュメント](#a12-バイリンガルドキュメント)
  - [A.13 開発ワークフロー](#a13-開発ワークフロー)
- [Part B — スクリプト固有仕様（テンプレート）](#part-b--スクリプト固有仕様テンプレート)
- [Part C — 品質ゲートと検証チェックリスト](#part-c--品質ゲートと検証チェックリスト)
- [Part D — 既知の落とし穴と教訓](#part-d--既知の落とし穴と教訓)

---

# Part A — 共通仕様（すべてのスクリプトで再利用可能）

## A.1 参考アセット

これらは共通ロジックの正規ソースです。**直接プルしてください。再実装しないでください**。

### A.1.1 参考 PowerShell スクリプト（フェーズ / バナー / ログのパターン）

```
https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/blob/main/Deploy-AMDChipsetDriverOnWindowsServer.ps1
```

この 21 フェーズ構成のデプロイメントスクリプトは、以下の正規ソースです：

- `Write-PhaseHeader` / `Write-PhaseFooter` / `Show-PhaseSummary`
- `Write-Step` / `Write-Ok` / `Write-Warn` / `Write-Fail` / `Write-Skip`
- `Format-Elapsed`（人間が読みやすい経過時間フォーマット）
- バナーブロックのレイアウト
- `Show-PowerShellEnvironment`（Phase 1 Step 0 の環境ダンプ）
- `Assert-PowerShellCompatibility`（強制終了チェック）

新しいスクリプトを開始する際は、この参考 URL ではなく、**同じリポジトリ内の既存の本番スクリプトの最新リビジョンから、これらのヘルパーをそのままコピー** してください。社内コピーには既に適用済みのバグ修正が含まれている可能性があるためです。

### A.1.2 静的解析ツール

```
https://github.com/usui-tk/deploy-amd-drivers-for-windowsserver/blob/main/tools/psa.py
```

`psa.py` は **純粋な Python**（PowerShell インストール不要）の静的解析ツールで、10 種類のチェック（C1〜C10）を実装しています。以下のように使用すること：

- そのまま再利用（上流と調整せずにフォークまたは変更しないこと）
- 新しいスクリプトのリポジトリの `tools/psa.py` に配置
- すべてのコミット前のゲートとして使用

詳細は A.11 を参照。

### A.1.3 社内併用スクリプト（推奨）

Speaker Deck Bulk Downloader（`Download-SpeakerDeck.ps1`、2026-05-11 時点で r19、配置: `scripts/powershell/download-speakerdeck-oracle4engineer/`）は、以下の最新参考実装です：

- 9 フェーズアーキテクチャ + 年フォルダ出力構成
- Runspace Pool 経由の適応的並列ダウンロード
- PDF メタデータによる事後分類（Phase 8 / year_overrides.csv パターン）
- フェーズ間 CSV カラム規約（A.9 を参照）

新しい一括取得スクリプトやデータ処理スクリプトの作成を依頼された場合は、**まずこのスクリプトを読み**、そのスケルトンをコピーしてください。

### A.1.4 ターゲット別スクリプトのフォルダ命名規則

スクリプトが汎用化されており、複数の対象アカウント・サービス・テナントに対して再利用可能な場合、スクリプト本体は汎用のまま（`-Account` や `-Subscription` 等でパラメーター化）を維持しつつ、**フォルダ名** に実際のターゲット名をサフィックスとして付与し、別ターゲット用に展開した際の名前衝突を回避します。

パターン：`<verb-noun>-<target-identifier>/`

例：

| フォルダ | 内容 |
|---|---|
| `download-speakerdeck-oracle4engineer/` | `oracle4engineer` アカウントを対象に実行するスクリプト |
| `download-speakerdeck-acmecorp/` | 同じスクリプトを `acmecorp` 対象で実行（若干のカスタマイズあり得る）|
| `download-githubrepos-anthropics/` | 仮想例：`anthropics` 組織を対象とした GitHub リポジトリダウンローダー |
| `inventory-aws-prod/` | `prod` アカウントを対象とした AWS インベントリスクリプト |

**スクリプトのファイル名自体はクリーンに保ちます**（`Download-SpeakerDeck.ps1`、`Download-SpeakerDeck-oracle4engineer.ps1` ではない）。**フォルダ名** だけがターゲット識別子を持ちます。これにより PowerShell の `Verb-Noun.ps1` 慣習を維持しつつ、同じロジックを異なるターゲット向けに複数配置した際の名前衝突を防ぎます。

スクリプトが真にアカウント非依存で、そのまま再利用される場合（例：デフォルト値が偶然 1 つのアカウントに設定されているだけで、`-Account` が完全に外部から指定可能）、単一フォルダで十分であり、サフィックスはデフォルトアカウント名とします。2 つのターゲット間のカスタマイズが非自明な規模になった時点で、フォルダをフォークします。

## A.2 ソースファイル形式

| ルール | 値 |
|---|---|
| エンコーディング | UTF-8 with BOM（先頭 3 バイトが `EF BB BF`）|
| ソースバイト | **BOM 以外は厳格に ASCII のみ** |
| 非 ASCII の戦略 | .NET 正規表現の Unicode エスケープ（`\u5E74` で `年` 等）と、ランタイム文字列の `[char]0xXXXX` を使用 |
| 改行コード | ディスク上は CRLF（PS 5.1 フレンドリー）|
| インデント | スペース 4 個、タブ不使用 |
| 行の最大長 | ハードリミットなし。可読性優先 |
| シバン行 | なし（PowerShell スクリプトでは不要）|

**なぜ ASCII のみ？** `ja-JP` の Windows 上の PowerShell 5.1 は、デフォルトのファイルエンコーディングがしばしば cp932 になり、ソースバイトが混在すると微妙なパーサーエラーが発生します。ソースを ASCII に保つことで、エンコーディング起因のインシデントを根絶できます。日本語テキストは、Unicode エスケープを介するか外部ファイルから読み込む形で、必ずランタイムに発行されます。

**検証方法：**

```bash
python3 -c "
with open('script.ps1','rb') as f: d=f.read()
assert d[:3]==bytes([0xEF,0xBB,0xBF]), 'BOM 欠落'
non_ascii = sum(1 for b in d[3:] if b > 0x7F)
assert non_ascii == 0, f'非 ASCII バイト {non_ascii} 個'
print('OK')
"
```

## A.3 バナーとバージョン識別

### バージョン文字列の書式

```powershell
$Script:ScriptVersion = '<short-name>-YYYY.MM.DD-rNN'
$Script:ScriptTag     = '<short-kebab-tag-describing-the-revision>'
```

例：

- `speakerdeck-2026.05.11-r17` / タグ `outfile-wildcard-fix`
- `amd-driver-2025.11.04-r12` / タグ `windows-server-2025-support`

### SHA256 による自己フィンガープリント

スクリプトは起動時に自分自身のファイルをハッシュ化し、先頭 12 桁の hex を露出する必要があります。これは各フェーズヘッダーに表示され、ログを再現可能にします：

```powershell
$Script:ScriptHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.Substring(0,12).ToLower()
$Script:ScriptShortTag = "v$Script:ScriptVersion/$Script:ScriptHash"
```

### バナーブロック

バナーは（セキュリティ警告がある場合はその後で）常に最初に印刷されます。書式：

```
========================================================================
  <スクリプト表示名>
  v<ScriptVersion>/<ScriptHash>
========================================================================
  <主要パラメーター 1>  : <値>
  <主要パラメーター 2>  : <値>
  ...
========================================================================
```

有効なオプトインスイッチは、パラメーターブロックの下に列挙：

```
  Force                : ON
  DryRun               : ON
  SkipEnvCheck         : ON
```

## A.4 フェーズアーキテクチャ

### 番号付けルール

1. **フェーズは 1 から始まる整数、1 ずつインクリメント**
2. **小数点付きフェーズ番号は禁止**（`P6.5` 禁止。代わりに `P08` 等を使用）
3. フェーズ ID はゼロパディング：`P01` 〜 `P09`、続いて `P10`, `P11`, ...
4. フェーズ ID は **実行間で安定** させる。新しいフェーズを追加するために番号を振り直す場合は、すべての番号を振り直すこと（Speaker Deck スクリプトの r16 を前例として参照）

### フェーズグループ

すべてのフェーズは、以下のいずれかのグループ（最大 5 文字の識別子）に属します：

| グループ | 目的 |
|---|---|
| `Setup` | 環境評価、サニティチェック |
| `Scan` | 外部ソースからの読み取り専用データ収集 |
| `Plan` | メモリ内計算、ディスクやリモートへの副作用なし |
| `Fetch` | 副作用を伴うネットワーク操作 |
| `Verify` | 実状態と計画の突合 |
| `Report` | 人間可読のサマリー生成 |

### フェーズヘッダー / フッター

参考実装を再利用してください。画面表示は以下のような形式：

```
========================================================================
 PHASE P03  - ListCollection         (Scan   ) start: 14:04:38
 script: vspeakerdeck-2026.05.11-r17/b7a478b625b8
========================================================================
...
 PHASE P03  -> DONE     elapsed: 1m3.5s
```

フェーズステータスの終端値：`done`, `skipped`, `failed`

### Phase Timing Summary（フェーズ実行時間サマリー）

実行終了時に、以下のような表を出力：

```
========================================================================
 Phase Timing Summary
========================================================================
  P01   DONE     elapsed: 0.38s
  P02   DONE     elapsed: 0.69s
  ...
  ----------------------------------------
  Total elapsed: 20m39.1s
========================================================================
```

フェーズ ID 列の幅は `{0,-4}`（`P01` 〜 `P99` まで対応可能）

## A.5 ログ規約

### マーカー

| マーカー | 関数 | 色 | 意味 |
|---|---|---|---|
| `[*]` | `Write-Step` | Cyan | 処理中 / 情報ステップ |
| `[+]` | `Write-Ok` | Green | 成功完了 |
| `[!]` | `Write-Warn` | Yellow | 復帰可能な警告 |
| `[X]` | `Write-Fail` | Red | 失敗（非致命的）|
| `[~]` | `Write-Skip` | DarkGray | 意図的にスキップ |

これらのマーカーは **5 文字幅（`[X] ` には末尾スペースを含む）** で固定幅。タイムスタンプ / 経過時間プレフィックスの内側に出力されます。標準的な行の書式：

```
[HH:MM:SS] [+E.EEs]    [+] 人間可読のメッセージ
```

ここで `E.EEs` はスクリプト開始からの経過時間で、以下のいずれか：

- 60 秒未満なら `S.SSs`
- 1 分〜59 分なら `MmS.Ss`
- 1 時間以上なら `HhMmS.Ss`

`Format-Elapsed` が正規のヘルパー関数です。参考スクリプトからコピーしてください。

### 色の規律

| 概念 | 色 |
|---|---|
| 処理中 / 情報 | Cyan |
| 成功 | Green |
| 警告（復帰可能）| Yellow |
| 失敗 / 異常 | Red |
| スキップ / 注意外 | DarkGray |
| ハイライト / DryRun | Magenta |
| デフォルトのテキスト | （色指定なし）|

### コンソールエンコーディング

スクリプトの先頭で UTF-8 コンソール出力を強制：

```powershell
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }
```

### TLS ハードニング

TLS 1.2 以上を常に強制：

```powershell
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor `
        [Net.SecurityProtocolType]::Tls
} catch { }
```

## A.6 パス取扱い（-LiteralPath ルール）

> **このセクションは苦労して見つけたバグ修正を体系化したものです。注意深く読んでください。**

### ワイルドカード解釈の落とし穴

PowerShell のパスベースコマンドレット（`Test-Path`, `Get-Item`, `Remove-Item`, `Move-Item`, `Copy-Item`, `Set-Content`, `Add-Content`, `Export-Csv -Path`）は、`[` `]` をワイルドカード文字クラスとして扱います。`C:\out\[Foo].pdf` のようなパスは「F, o, o のいずれか 1 文字にマッチ」と解釈され、`FileNotFoundException`（「ワイルドカード パス … がファイルに解決されなかった」）で失敗します。

現実世界のパスには以下が含まれる可能性があります：

- `[TechNight #49]` のようなタイトル内の `[` `]`
- slug から導出されたファイル名内の `#`
- その他の正規表現で意味を持つ文字（稀）

### ルール：どこでも -LiteralPath を使う

外部データ（タイトル、URL、ユーザー入力）から導出されるすべてのパスについて、`-LiteralPath` をサポートするすべてのコマンドレットで使用すること。コマンドレットのそばに、その理由を防御的なコメントとして付記すること。

### -LiteralPath をサポートしないコマンドレット

| コマンドレット | 回避策 |
|---|---|
| `Invoke-WebRequest -OutFile` | GUID 名の安全なパスにダウンロードし、`Move-Item -LiteralPath` で実際の宛先へ移動 |
| `Start-BitsTransfer -Destination` | 上と同じ |
| `Split-Path -LiteralPath -Parent`（PS 5.1）| `[System.IO.Path]::GetDirectoryName($p)` を使用 |
| `Resolve-Path` | `[System.IO.Path]::GetFullPath($p)` を使用 |

### 安全な一時ファイルの正規パターン（Invoke-WebRequest 用）

```powershell
# ワイルドカードを含まないダウンロードパスを構築: <dir>\.dl_<GUID>.part
$safeTmpDir  = [System.IO.Path]::GetDirectoryName($targetPath)
$safeTmpName = '.dl_' + [Guid]::NewGuid().ToString('N') + '.part'
$safeTmp     = Join-Path $safeTmpDir $safeTmpName

Invoke-WebRequest -Uri $url -OutFile $safeTmp -UseBasicParsing -ErrorAction Stop

# 実際の .part の場所へ移動（[ ] を含む可能性あり）。Move-Item は
# -LiteralPath をサポートするため、ワイルドカード解釈されない。
Move-Item -LiteralPath $safeTmp -Destination $realPartPath -Force
```

### 派生ファイル名のサニタイズ

URL の slug からファイル名を導出する場合、以下のようにサニタイズ：

```powershell
$safe = $slug -replace '[<>:"/\\|?*]', '_'
if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80) }
```

`[`, `]`, `#` は **Windows のファイル名として合法な文字** であることに注意してください — 削除しないこと。緩和策は `-LiteralPath` であって、文字削除ではありません。

## A.7 パラメーター規約

### 標準スイッチ（これらの名前をそのまま使用）

| スイッチ | 動作 |
|---|---|
| `-DryRun` | すべての読み取り専用フェーズを実行し、Fetch/Verify フェーズは明示的に SKIPPED と記録 |
| `-Force` | 既存の出力を上書き |
| `-Clean` | 出力 / 作業ディレクトリを削除してから実行 |
| `-CleanOnly` | `-Clean` と同じワイプ後、フェーズを実行せずに終了 |
| `-SkipEnvCheck` | Phase 1 をスキップし、安全側のデフォルト閾値を使用 |

### 相互排他

`param(...)` の直後に検証ブロックを追加：

```powershell
if ($Clean -and $CleanOnly) {
    throw '-Clean か -CleanOnly のどちらかを指定してください（両方は不可）。'
}
```

### バナー表示

バナーブロック（A.3）には、有効なすべてのオプトインスイッチを色分けして表示する必要があります：

- `-Force`, `-SkipEnvCheck`, `-Clean`, `-CleanOnly` → Yellow
- `-DryRun` → Magenta

## A.8 エラーと診断の規約

### 3 層の診断出力

1. **コンソールログ** — 失敗ごとに簡潔なマーカー
2. **失敗ごとの `.txt` ダンプ** — `<work>\diag\failed\<idx>_<slug>.txt`
3. **構造化 JSONL** — `<work>\logs\PNN_errors.jsonl`

### 失敗カテゴリの分類

最終レポートの失敗内訳のために、例外を粗いカテゴリにまとめる。例：

```
System.Net.WebException
System.IO.FileNotFoundException
System.IO.IOException
Timeout
HTTPStatus.4XX
HTTPStatus.5XX
Other
```

### 診断 .txt ダンプの書式

固定スキーマ：

```
========================================================================
Failure diagnostic for deck #<idx>
========================================================================
Generated at        : <ISO timestamp>
Script version      : v<ver>/<hash>

-- Deck info ----------------------------------------------------------
<key-value 行>

-- Output path --------------------------------------------------------
<key-value 行>

-- Failure summary ----------------------------------------------------
<key-value 行>

-- Error details ------------------------------------------------------
<key-value 行>

-- Response body preview (first ~2KB) ---------------------------------
<切り詰めた body>

-- Attempt history ----------------------------------------------------
<試行ごとに 1 行>

-- Stack trace --------------------------------------------------------
<スタック>
```

### JSONL スキーマ（失敗ごと）

1 行に自己完結した JSON オブジェクト 1 件。キーは `camelCase`：

```json
{
  "timestamp": "<ISO>",
  "scriptVersion": "<ver>/<hash>",
  "index": 42,
  "title": "...",
  "deckUrl": "...",
  "category": "...",
  "exceptionType": "...",
  "exceptionMessage": "...",
  "attempts": 3,
  "attemptHistory": [ ... ]
}
```

## A.9 CSV / JSONL カラム規約

### すべてのフェーズ別 CSV に共通のカラム

スクリプトが複数フェーズで CSV 出力を持つ場合、以下のカラムは **同一の名前** ですべての CSV に出現する必要があります：

| カラム | 意味 |
|---|---|
| `Index` | スキャン順での 1 始まりのレコード番号 |
| `Title` | 表示名（タイトル、ラベルなど）|

これら以外に、スクリプトはフェーズごとの独自カラムを定義します。各後続フェーズの CSV は、前フェーズのカラムの **厳密なスーパーセット** に加え、フェーズ固有のカラムを追加することで、CSV をまたいだ join / grep を可能にします。

### ファイル名の書式

```
PNN_<purpose>.csv
PNN_<purpose>.jsonl
```

例：`P04_evaluation_log.csv`, `P06_errors.jsonl`, `P07_final_state.csv`

### 永続的な状態ファイル

スクリプトが実行間で状態（オーバーライド、キャッシュなど）を保持する場合、`PNN_` プレフィックスのないフラットなファイル名を使用：

```
work/logs/year_overrides.csv
work/logs/url_cache.csv
```

これらはフェーズ別ログとは別物で、README に記載します。

## A.10 環境評価 (Phase 1)

すべてのスクリプトの Phase 1 には以下を含める必要があります：

### Step 0: PowerShell 実行環境

以下をすべてダンプ：

- PS バージョン、エディション（Desktop / Core）
- CLR バージョン、エンジンビルド
- プロセスアーキテクチャ（必ず 64 ビット）
- OS 名、ビルド番号、アーキテクチャ
- ホスト、実行ポリシー
- TLS デフォルト設定
- カルチャー、UI カルチャー
- デフォルトエンコーディング、コンソールエンコーディング
- スクリプトパス、作業ディレクトリ

続いて `Assert-PowerShellCompatibility` を実行：

- PS 5.1 以上が必要
- 64 ビットプロセスが必要
- Windows 10/11 または Windows Server 2016 以上が必要

### Step A: レジストリチェック

`HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled` を読み取り

### Step B: 実環境のファイルシステムテスト

ダミーファイルを段階的に長くしたパス長（100, 200, 240, 260, 300, 500, 1000 文字）で作成し、現環境での実効上限を測定

### Step C: ティア分類

最も長い成功時のパス長に基づき、以下に分類：

| ティア | 最大長 | 実効的なファイル名 / フルパス閾値 |
|---|---|---|
| Tier 1: Modern | 900 以上 | 240 / 480 |
| Tier 2: Partial | 260〜900 | 240 / 480 |
| Tier 3: Conservative | 200〜260 | 100 / 240 |
| Tier 4: Restricted | 200 未満 | 80 / 200 |

## A.11 psa.py による静的解析

### セットアップ

```
<repo>/
  tools/
    psa.py              # 上流からプル
```

### 必須ゲート

すべてのコミット前に：

```bash
python3 tools/psa.py path/to/script.ps1
```

**0 errors / 0 warnings / 0 info** で合格すること。

### チェックの範囲（C1〜C10）

`psa.py` は以下をカバー：

- C1: エンコーディング（UTF-8 BOM の存在、BOM 以外は ASCII のみ）
- C2: 主要トークンのバランス（中括弧、丸括弧、角括弧）
- C3: 引用符の整合性
- C4: 未定義変数の検出（関数スコープ内）
- C5: 非推奨コマンドレットの使用
- C6: `-LiteralPath` の欠落（必要そうな箇所）
- C7: ベア `$var` に対する `-match`（左辺 null 時のリスク）
- C8: 禁止パターン（`Invoke-Expression` など）
- C9: 不適切な文字列連結
- C10: フェーズ ID の整合性

（正確なチェックリストは進化する可能性があります。`psa.py --help` を参照）

### psa.py が誤検出を出した場合

よくあるケースと解決策：

| 誤検出 | 解決策 |
|---|---|
| 異なる関数で設定された `$Script:Foo` に対する C4「undefined variable」| スクリプトロード時に初期化：`$Script:Foo = $null` |
| `-LiteralPath` をサポートしないコマンドレットに対する C6 | インラインコメント `# psa-ignore-C6: cmdlet has no -LiteralPath` を追加 |

psa.py が特定のパターンを体系的に誤分類する場合は、ローカルで抑制するのではなく、上流に issue を上げてください。

## A.12 バイリンガルドキュメント

### ファイルセット

すべてのスクリプト（あるいは複数スクリプトを格納するリポジトリ内の各スクリプトプロジェクト）は以下を保持：

| ファイル | 役割 |
|---|---|
| `README.md` | 英語版、一次ドキュメント |
| `README.ja.md` | 日本語版ミラー、`README.md` と同期 |
| `spec.en.md` | 開発者 / LLM 向け仕様書（本ファイルのパターン）|
| `spec.ja.md` | 仕様書の日本語版ミラー |

スクリプトが大きなマルチスクリプトリポジトリ内に配置される場合（例：`usui-tk/ai-generated-artifacts/scripts/powershell/<name>/`）、`LICENSE` ファイルはリポジトリルートに配置され、すべてのスクリプトで共有されます。スクリプトが独立したリポジトリの場合は、同じディレクトリに `LICENSE` ファイルを配置します。

### 同期ルール

**`README.md` に触れるすべてのスクリプト変更は、同じコミット内で `README.ja.md` を更新する必要があります**。両ファイルの `Lines : NNNN` フィールドは一致する必要があります。機械可読フィールド（パス、パラメーター名、バージョン文字列）は翻訳せず、散文、ヘッダー、説明文のみ翻訳します。

### 日本語版ミラーのスタイル

- ヘッダーやテーブル列の説明では「全角コロン (：)」を使用
- コードブロックとパラメーター名は ASCII のまま
- セクション順とテーブルレイアウトを正確に一致させる

### A.12.5 必須の免責事項とライセンスセクション

すべての README（英語版と日本語版の両方）は、1 行サマリーと言語切替リンクの直後に、以下 2 つのセクションを **必ず** 含める必要があります：

1. **免責事項 (`## ⚠️ Disclaimer` / `## ⚠️ 免責事項`)**
   - 「AS IS（現状のまま）」「無保証」の宣言
   - 損害（データ損失、アカウント停止、帯域 / ストレージ費用、レート制限、IP ブロック）に対する責任制限
   - 利用者責任のチェックリスト：利用規約遵守、知的財産権の尊重、実行前のソースコード確認
   - 「節度を持って利用」の呼びかけ（組み込みスロットリングを回避しない）

2. **ライセンス (`## License` / `## ライセンス`)**
   - ライセンス名の明示（本スクリプトファミリーのデフォルトは MIT）
   - リポジトリルートの `LICENSE` ファイルへのリンク
   - ユーザーができること（使用 / 改変 / 配布）と必須事項（著作権 + ライセンス表示の保持）を 1 段落で要約
   - ソフトウェアが無保証であることの再強調

リポジトリルートには別途 `LICENSE` ファイルを配置し、ライセンスの完全な条文を含めます。MIT ライセンスのボイラープレート著作権ヘッダー：

```
MIT License

Copyright (c) <YEAR> <Project Name> contributors

Permission is hereby granted, ...
```

プロジェクトが別のライセンス（Apache 2.0、BSD-3-Clause、GPL-3.0 等）を選択する場合でも、README セクションの構造は同じ。ライセンス名と 1 段落の要約だけを差し替えます。

## A.13 開発ワークフロー

### イテレーションサイクル

```
1. コードの作成または変更
2. psa.py を実行 — 0/0/0 必須
3. まず -DryRun で実行
4. plan CSV を確認
5. 本番実行
6. error JSONL と final state CSV を確認
7. 新しい失敗パターンが見つかれば、spec.en.md Part D を更新
```

### リビジョン規律

- 意味のある変更ごとに `-rNN` サフィックスをインクリメント
- `ScriptTag` で変更を 3〜5 単語の kebab-case で記述
- 大規模なリファクタリング（フェーズ番号振り直し等）には独立したリビジョンを割り当て
- スクリプト先頭に内部の CHANGELOG コメントブロックを保持

### 発明より再利用

新機能が必要になったら、優先順位は：

1. **社内の参考スクリプト** から最も近い既存実装を確認。コピーして適応
2. **A.1.1 の参考 URL** で正規パターンを確認
3. **どちらにも該当しない場合のみ** 一から設計する — そして、次のスクリプトが再利用できるよう、新しいパターンを 本 SPEC に文書化する

---

# Part B — スクリプト固有仕様（テンプレート）

> このセクションは、すべての新スクリプトが埋めるテンプレートです。Part A から異なる点のみを記述します。Speaker Deck Bulk Downloader を実例として使用します。

## B.1 識別情報

| フィールド | 値 |
|---|---|
| スクリプト名 | `Download-SpeakerDeck.ps1` |
| 表示名 | Speaker Deck Bulk Downloader |
| 現在のリビジョン | r17（`outfile-wildcard-fix`）|
| 目的 | Speaker Deck アカウントの全公開 PDF を一括ダウンロード |
| オーナー | （記入）|

## B.2 入力

| ソース | 説明 |
|---|---|
| `-Account` パラメーター | Speaker Deck アカウント名（デフォルト `oracle4engineer`）|
| Speaker Deck の Web ページ | 一覧ページとデッキ詳細ページ、HTML パースで取得 |
| （再実行のみ）`work/logs/year_overrides.csv` | 前回の Phase 8 救済による年フォルダオーバーライド |

## B.3 出力

```
<OutputDir>/
  YYYY/
    <title>__<original>.pdf           # 年フォルダレイアウト（デフォルト）
  _undated/
    <title>__<original>.pdf           # 年が判定できなかった場合
<WorkDir>/
  logs/
    P04_evaluation_log.csv            # DryRun のみ
    P05_filename_plan.csv             # 常に生成
    P06_download_log.csv              # 本番実行のみ
    P06_errors.jsonl                  # 失敗発生時のみ
    P07_final_state.csv               # 本番実行のみ
    year_overrides.csv                # Phase 8 が遅延作成
  diag/
    failed/<idx>_<slug>.txt           # 失敗 1 件ごとのダンプ
```

## B.4 フェーズマップ

| ID | 名称 | グループ | 説明 |
|---|---|---|---|
| P01 | EnvCheck | Setup | Part A.10 のとおり |
| P02 | GetTotalCount | Scan | プロフィールページを読み、デッキ総数を抽出 |
| P03 | ListCollection | Scan | ページ送りで一覧を走査し、(URL, title) を収集 |
| P04 | Evaluation | Scan | デッキ別 `og:meta` 取得、ダウンロード可否を判定 |
| P05 | FilenamePlan | Plan | デッキごとのファイル名 + フルパスを計算、重複や MAX_PATH 超過をフラグ、CSV 保存 |
| P06 | Download | Fetch | 適応的並列ダウンロード（Runspace Pool）、429/5xx でスロットル |
| P07 | Reconciliation | Verify | plan + download log + ディスク実体を統合、不整合をフラグ |
| P08 | UndatedReclassify | Verify | `_undated/` 内のファイルの PDF メタデータを読み取り、年が解決できれば年フォルダへ移動、`year_overrides.csv` に追記 |
| P09 | FinalReport | Report | 統計 + 失敗内訳 + 年別分布 |

## B.5 年フォルダ構成

デフォルトレイアウト：`<OutputDir>/<YYYY>/<filename>`。`YYYY` は以下のシグナルから順に導出（優先順位 0 が最高）：

| # | ソース | ラベル |
|---|---|---|
| 0 | `year_overrides.csv`（前回 Phase 8 由来）| `OverrideCsv` |
| 1 | `OriginalFilename` 中の `YYYYMMDD` パターン | `OriginalFilename` |
| 2 | `og:meta` の PublishDate | `PublishDate` |
| 3 | Title に `YYYY年`（日本語の漢字）が含まれる | `TitleJp` |
| 4 | Title にベア 4 桁年が含まれる | `TitleNum` |
| 5 | いずれも該当しない → `_undated/` | `Fallback` |

有効な年の範囲：`[2010, currentYear + 1]`

`-FlatLayout` で年フォルダを無効化（旧式の単一フォルダモード）

## B.6 PDF メタデータによる事後分類 (Phase 8)

Phase 7 の後に実行。`_undated/` 内のダウンロード成功ファイル各々について、純 PowerShell の正規表現で PDF メタデータを読み取り（外部ライブラリ不要）：

| 優先順位 | ソース | YearSource ラベル |
|---|---|---|
| 1 | Info Dictionary `/CreationDate` | `PdfInfoDict` |
| 2 | XMP `<xmp:CreateDate>` | `PdfXmp` |
| 3 | XMP 旧名前空間 `<xap:CreateDate>` | `PdfXmpLegacy` |
| 4 | XMP `<pdf:CreationDate>` | `PdfXmpPdfNs` |
| 5 | Info Dict `/ModDate`（フォールバック）| `PdfInfoDictMod` |
| 6 | XMP `<xmp:ModifyDate>`（フォールバック）| `PdfXmpMod` |

有効な年が見つかったら、ファイルを `_undated/foo.pdf` から `<year>/foo.pdf` へ移動し、`year_overrides.csv` に追記。

`-SkipPdfReclassification` でオプトアウト可能。`-DryRun` および `-FlatLayout` 時には自動的にスキップ。

## B.7 適応的並列ダウンロード (Phase 6)

| 設定 | 値 |
|---|---|
| 初期並列度 | 3 |
| 最大並列度 | 5 |
| 最小並列度 | 1 |
| デッキあたり最大リトライ | 3 |
| リクエストごとのタイムアウト | 300 秒 |
| 並列度の引き上げトリガー | 10 連続成功 → +1 並列度 |
| スロットルトリガー（HTTP 429）| 並列度を半減、60 秒スリープ |
| ステップダウントリガー（HTTP 5xx）| -1 並列度 |
| 緊急ブレーキ | 3 連続失敗 → 並列度を min に強制、90 秒スリープ |

## B.8 失敗回復

Phase 6 worker は 2 種類の失敗形態を処理：

1. **HTTP エラー**（ステータスコードあり）→ バックオフでリトライ、JSONL でカテゴリ分類
2. **ローカル I/O エラー**（例：r17 のワイルドカードバグ）→ リトライ、`.txt` ダンプにフルスタックトレースをキャプチャ

`.part` ファイルはサイズのサニティチェック（100 バイト以上）後にのみ、最終ファイル名にアトミックに移動。

A.6 のワイルドカード問題を解決する正規の安全 temp パターンを参照。

## B.9 冪等性

同じパラメーターで再実行した場合：

- ディスク上に既存のファイルはスキップ（`-Force` 指定時を除く）
- Phase 5 の優先順位 0 で `year_overrides.csv` を読む
- Phase 8 は救済対象 0 件（「定常状態」）

最初からやり直すには `-Clean` を使用（`<OutputDir>` と `<WorkDir>` の両方をワイプ）。

---

# Part C — 品質ゲートと検証チェックリスト

すべてのコミット前に、以下すべてが合格すること：

### 静的チェック

- [ ] `python3 tools/psa.py <script>.ps1` → 0 errors / 0 warnings / 0 info
- [ ] ファイルは UTF-8 BOM (`EF BB BF`) で開始
- [ ] BOM 以外に非 ASCII バイトが存在しない
- [ ] スクリプトの行数が README.md と README.ja.md の `Lines : NNNN` と一致
- [ ] `Script:ScriptVersion` と `Script:ScriptTag` を変更内容に応じて更新

### 機能チェック

- [ ] `-DryRun` がエラーなく完走
- [ ] Phase Timing Summary に期待どおりのフェーズ ID（P01 〜 PNN、欠番なし）が表示
- [ ] すべてのフェーズ CSV が期待するカラムセットで存在
- [ ] 本番実行で P07 突合に 0 件の異常（または異常が P09 の出力で説明済み）
- [ ] 再実行で定常状態（Phase 8 examined: 0、新たな失敗なし）

### ドキュメントチェック

- [ ] README.md にすべての新パラメーター、スイッチ、出力ファイルが記載
- [ ] README.ja.md が構造的に行単位で等価
- [ ] スクリプト先頭の CHANGELOG コメントに変更内容を列挙
- [ ] README.md の冒頭付近に **Disclaimer** セクションあり（A.12.5 準拠）
- [ ] README.md の冒頭付近に **License** セクションあり（A.12.5 準拠）
- [ ] README.ja.md に等価な **免責事項** と **ライセンス** セクションあり
- [ ] リポジトリルートに `LICENSE` ファイルが存在

### CSV 間チェック

- [ ] 共通カラム（Index, Title, DeckUrl, …）がすべてのフェーズ別 CSV で同一の名前
- [ ] 各後続フェーズの CSV が前フェーズのカラムのスーパーセット

---

# Part D — 既知の落とし穴と教訓

これらは過去のリビジョンで発見された実バグです。将来のスクリプトは修正を継承し、バグを再導入しないこと。

## D.1 r10 — ファイル名のワイルドカード文字で Test-Path / Get-Item / Remove-Item / Move-Item が失敗

**症状：** パスに `[` `]` を含むファイル（例：`[TechNight #49]`）が、突合時に `FileNotFoundException` で失敗。

**根本原因：** `-LiteralPath` を指定しない限り、PowerShell は `[` `]` をワイルドカード文字クラスとして扱う。

**修正：** すべての `Test-Path`, `Get-Item`, `Remove-Item`, `Move-Item`, `Copy-Item`, `Set-Content`, `Add-Content`, `Export-Csv` で `-LiteralPath` を使用。

## D.2 r11 — `Split-Path -LiteralPath -Parent` は PS 5.1 に存在しない

**症状：** `Split-Path -LiteralPath $p -Parent` 使用時に `ParameterSetException`。

**根本原因：** PS 5.1 の `Split-Path` の `LiteralPathSet` には `-Parent` が含まれない（PS 7 で追加）。

**修正：** `[System.IO.Path]::GetDirectoryName($p)` を使用。

## D.3 r17 — `Invoke-WebRequest -OutFile` は `-LiteralPath` をサポートしない

**症状：** `[` / `]` を含むタイトルで、ダウンロードが `FileNotFoundException`「ワイルドカード パス … がファイルに解決されなかった」で静かに失敗。

**根本原因：** `-OutFile` は内部で `-Path` セマンティクスを使用（ワイルドカード展開あり）。PS 5.1 では `Invoke-WebRequest` に `-LiteralPath` パラメーターが存在しない。

**修正：** まず GUID 名の安全パスにダウンロードし、それから `Move-Item -LiteralPath` で実際の宛先へ移動。A.6 の正規パターンを参照。

## D.4 フェーズ番号振り直しのリスク (r16)

**症状：** フェーズを振り直す際（例：`P6.5` を削除）、自動テキスト置換が誤マッチを生じることがある。例えば、`Phase 7`（旧 FinalReport）に言及するコメントが、元の文脈は「救済フェーズ」を指していたのに `Phase 9` に誤って移行されることがある。

**緩和策：** 一括振り直しの後、コメントや docstring のすべての `Phase N` 言及について、その意味する対象（散文が実際にどの名前付きフェーズを指しているか）を、旧番号ではなくセマンティクスに照らして監査すること。

## D.5 ja-JP Windows でのコンソールエンコーディング

**症状：** スクリプト出力中の日本語文字が `??` や文字化けとしてレンダリングされる、特に CI や非対話シェルで。

**修正：** スクリプト先頭で `$OutputEncoding` と `[Console]::OutputEncoding` の両方を UTF-8 に強制。

## D.6 型なし `[char]0x5E74` vs 正規表現 `\u5E74`

正規表現で非 ASCII 文字を **マッチさせる** 必要がある場合、正規表現エンジンの `\uXXXX` エスケープを使用（ソースには ASCII のまま保持）。ランタイムで非 ASCII 文字を **生成する** 必要がある場合（例：ログメッセージ用）は、外部ファイルから読み取るか、`[char]0xXXXX` 経由で構築する — ソースに直接置かないこと。

---

## 付録：この SPEC から新スクリプトを派生させる方法

このスタイルで新しい PowerShell スクリプトの作成を依頼された場合：

1. この 本 SPEC を最初から最後まで読む
2. 最も近い既存の社内スクリプトを特定（A.1.3）
3. 以下をコピー：
   - スクリプトのバナー / バージョンブロック
   - `Write-PhaseHeader` / `Write-PhaseFooter` / ログヘルパー
   - `Show-PowerShellEnvironment` / `Assert-PowerShellCompatibility`
   - `Format-Elapsed`
   - CSV / JSONL writer
   - 上流からの `tools/psa.py`
4. フェーズ本体を新スクリプトのロジックに置き換え
5. フェーズを P01 から振り直し
6. Part B のテンプレートフィールドを埋める
7. 品質ゲート（Part C）を実行
8. 新しい落とし穴が発見されたら spec.en.md Part D を更新

本ドキュメント自体もバージョン管理されています。読んでいる SPEC のリビジョンが、作業中のスクリプトのリビジョンと一致していることを必ず確認してください。
