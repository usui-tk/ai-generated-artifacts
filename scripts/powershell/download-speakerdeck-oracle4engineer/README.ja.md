# Download-SpeakerDeck.ps1

| ステージ | ステータス |
|:---|:---|
| STAGE 1 — Linux チェック (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage1__linux.yml) |
| STAGE 2 — Windows チェック (PSScriptAnalyzer on Windows PS 5.1 + スモークテスト) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage2__windows.yml) |
| STAGE 3 — Windows リリース検証 (`-DryRun`) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__download-speakerdeck-oracle4engineer__stage3__windows-release.yml) |

[English](README.md) | **日本語**

指定した Speaker Deck アカウントから、公開されているすべてのスライド資料を一括ダウンロードします。
Windows 11 + Windows PowerShell 5.1 を想定（PowerShell 7+ でも動作します）。

このスクリプトは
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
リポジトリの `scripts/powershell/download-speakerdeck-oracle4engineer/` 配下に格納されています。

## ⚠️ 免責事項

**ご利用は自己責任でお願いします。** 本スクリプトは「現状のまま (AS IS)」
提供されており、明示・黙示を問わずいかなる保証もありません。本スクリプトの
使用、改変、配布に起因または関連して発生したあらゆる損害(データ損失、
アカウント停止、ネットワーク障害、ディスク容量逼迫、その他直接的・間接的な
損害を含むが、これらに限定されない)について、作者および貢献者は一切の
責任を負いません。

本スクリプトを実行することにより、利用者は以下を承諾するものとします:

* 利用が Speaker Deck の利用規約および適用される法令・規制に準拠している
  ことを **利用者自身が確認する責任を負う** こと
* 多数のファイルをダウンロードすることに伴う結果(通信費用、ストレージ
  費用、レート制限、IP ブロック等)について **利用者自身が責任を負う** こと
* ダウンロードした資料の知的財産権は原作者に帰属することを尊重し、原著者
  の権利を侵害しないこと
* 実行前にスクリプトのソースコードを確認し、その動作を理解した上で使用
  すること

本ツールは節度を持ってご利用ください。レート制限を尊重してください
(スクリプトには組み込みのスロットリングがありますが、これを回避しては
いけません)。必要以上に高速・頻繁にコンテンツをダウンロードしないで
ください。

本リポジトリ内のすべての成果物に適用される完全な免責事項と自己責任条項
については、[ルート README](../../../README.ja.md)
([English](../../../README.md))を参照してください。

## ライセンス

本プロジェクトは `usui-tk/ai-generated-artifacts` リポジトリの一部であり、**MIT ライセンス** の下で公開されています。完全な条文はリポジトリルートの
[`LICENSE`](../../../LICENSE)
ファイルを参照してください。

要約：原著作権表示およびライセンス表示を保持する限り、本ソフトウェアを目的を問わず自由に使用、改変、配布できます。本ソフトウェアは無保証で提供されます。詳細は上記の免責事項および LICENSE ファイルを参照してください。

## なぜこのスクリプトが必要か

Speaker Deck のウェブ UI が提供するダウンロード機能は、 1 デッキ
ずつしかありません。 自身が公開したコンテンツをバックアップしたい
アカウント所有者、 調査資料をアーカイブする研究者、 発表者のアーカイブ
を監査する管理者にとって、 対象アカウントが数十(あるいは数百)の
デッキを保有するようになると手作業のワークフローは深刻に困難に
なります:デッキごとに複数回のクリックと個別のダウンロードダイアログ
が必要で、 ファイル名の正規化も手動で行う必要があり、 新規アップロード
を増分的に検出する仕組みも組み込まれていません。

`Download-SpeakerDeck.ps1` は、 アカウントページの列挙、 デッキ
メタデータ抽出(日付、 タイトル、 slug)、 ファイル名正規化、 年フォルダ
分類、 PDF 整合性チェック、 ダウンロード済みファイルの増分スキップを、
ワークフロー全体として自動化します。 `-DryRun` の単一起動で、 ネット
ワーク(一覧ページ以外)に触れずに完全な計画 CSV を生成。 続いて
ライブ実行が計画を実行(組み込みのスロットリング付き)。

### 適している用途

- 自身が公開したデッキをバックアップする Speaker Deck **アカウント所有者**
- 発表者の公開コンテンツをオフライン学習用にアーカイブする
  **研究者・教育者**(上記の免責事項に記載された ToS / 知的財産権の
  義務に従う前提)
- 法令準拠アーカイブのための年次スナップショットを生成する
  **CI パイプライン**

### 対象外

- **非公開** デッキの取得(Speaker Deck は一般的な公開 API を提供
  しておらず、 本スクリプトは公開アカウントページのスクレイピングのみ)
- **認証が必要な** コンテンツ(本スクリプトは認証情報を使用しない)
- **任意のスライドホスティングサービスからの一括ダウンロード**
  (本スクリプトは Speaker Deck 専用)

### 読者向けナビゲーション

- **初めて運用する方** は、 上記の免責事項を読み、 下記の *クイック
  スタート* セクションを概観してください。 スクリプト本体の `-Help`
  フラグでも使用方法バナーが出力されます。
- **内部挙動の確認**(フェーズ、 PDF メタデータ事後分類、 エラー耐性
  戦略)については、 [`SPEC.md`](./SPEC.md) Part B を参照してください
  (SPEC は英語のみで維持されています)。
- **完全なテストマトリクスとセルフ検証手順** については、
  [`TESTING.md`](./TESTING.md) を参照してください(英語のみ)。
- **リビジョン単位の変更履歴** は [`CHANGELOG.md`](./CHANGELOG.md)
  を参照してください(英語のみ)。
- **リポジトリ全体に共通する LLM エージェント運用ガイド**(ガバナンス
  階層、 ground truth 抽出、 Doc-Touching マトリクス、 Part A 継承
  ルール、 アンチパターン)は、 リポジトリルートの
  [`AGENTS.md`](../../../AGENTS.md) を参照してください(英語のみ)。
  本スクリプトの `SPEC.md` Part A は、 本リポジトリスタイルの
  sibling Layer 3 SPEC の **正典継承元** として機能します。

## フォルダ構成

```
scripts/powershell/download-speakerdeck-oracle4engineer/
  Download-SpeakerDeck.ps1     # 本体スクリプト（この README が説明する対象）
  README.md / README.ja.md     # エンドユーザー向けドキュメント（このファイル群）
  SPEC.md (English only)         # 開発者 / LLM 向け仕様書（下記「開発者向け仕様」参照）
  TESTING.md (English only)   # 検証手順と実行結果
```

本スクリプトの検証に用いる PowerShell 静的解析ツール `psa.py` は、
レポジトリ全体での正規配置場所
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/)
に格納されています。

スクリプトを **実行するだけ** であれば、この README を読めば十分です。**拡張や類似スクリプト作成** の場合は `SPEC.md` も併せてご確認ください。

## クイックスタート

```powershell
# 1. ファイルのブロック解除（"インターネットからダウンロードした"警告を解除）
Unblock-File .\Download-SpeakerDeck.ps1

# 2. 現在のセッションだけスクリプト実行を許可
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. DryRun（評価のみ、ダウンロードは実施しない）
.\Download-SpeakerDeck.ps1 -DryRun

# 4. デフォルト設定で本番実行（アカウント: oracle4engineer）
.\Download-SpeakerDeck.ps1
```

## パラメータ

| パラメータ           | デフォルト       | 説明                                                                |
| -------------------- | ---------------- | ------------------------------------------------------------------- |
| `-Account`           | `oracle4engineer`| Speaker Deck アカウント名                                           |
| `-OutputDir`         | `.\downloads`    | デッキの出力先ディレクトリ（スクリプト配置場所からの相対パス）      |
| `-WorkDir`           | `.\work`         | 作業用ディレクトリ・診断ファイル出力先（スクリプト配置場所からの相対パス） |
| `-DelaySeconds`      | `1.0`            | リクエスト間隔の基準値（秒）                                        |
| `-JitterSeconds`     | `0.3`            | `DelaySeconds` に加減算するランダムジッター幅                       |
| `-MaxConcurrency`    | `5`              | 並列ダウンロードの上限                                              |
| `-InitialConcurrency`| `3`              | 並列ダウンロードの初期値                                            |
| `-MinConcurrency`    | `1`              | 並列ダウンロードの下限（スロットリング時に使用）                    |
| `-MaxRetries`        | `3`              | ダウンロード 1 件あたりの最大リトライ回数                           |
| `-Force`             | (off)            | 既存ファイルを上書き（指定なしの場合、1 KB 超の既存ファイルはスキップ） |
| `-DryRun`            | (off)            | Phase 1 〜 5 を完全に実行（Phase 5 のファイル名計画 CSV まで出力）。Phase 6/7/8 は明示的に SKIPPED と記録され、Phase 9 のレポート出力は実施される |
| `-SkipEnvCheck`      | (off)            | Phase 1 をスキップし、安全側のデフォルト閾値を使用                  |
| `-Clean`             | (off)            | 実行前に OutputDir と WorkDir を削除（クリーンな再実行）            |
| `-CleanOnly`         | (off)            | `-Clean` と同じ削除を行い、Phase 実行せず即終了                     |
| `-FlatLayout`             | (off)            | 年フォルダ分割を無効化し、すべてのファイルを OutputDir 直下にフラット配置 |
| `-SkipPdfReclassification`| (off)            | Phase 8（PDF メタデータによる `_undated` ファイル救済）をスキップ        |

## 年フォルダ分割（デフォルト動作）

スクリプトは既定で、公開年ごとのサブフォルダにダウンロードを整理します：

```
downloads/
  2026/
    [Oracle TechNight#99] ...__file.pdf
  2025/
    ...
  2024/
    ...
  _undated/
    （年を特定できなかったファイル）
```

年は以下の優先順位で導出されます：

1. **OriginalFilename** の `YYYYMMDD` パターン（および `YYYY-MM-DD`、`YYYY_MM_DD`）
   — デッキ作成者がファイル名に埋め込んだ日付（コンテンツ作成日の代理）
2. og:meta から取得した **PublishDate**（Speaker Deck へのアップロード日）
3. Title 中の **日本語年表記**（`YYYY` + 年-kanji U+5E74）
4. Title 中の単独 4 桁年 `20YY`
5. フォールバック: `_undated/`

年は `[2010, 現在年 + 1]` の範囲内のときのみ採用されます。

このユーザー視点での意図は、**クラウドサービスの日々の進化により陳腐化したコンテンツを視覚的に把握しやすくする** ことです。タイトルだけ見ても古さがわかりにくい場合でも、年フォルダによって「2018 年の資料は内容が古い可能性が高い」と一目で判断できます。

従来のフラットレイアウト（OutputDir 直下に全ファイル）を使いたい場合は、`-FlatLayout` を指定してください。

## パス解決

`-OutputDir` および `-WorkDir` は、**スクリプトの .ps1 ファイルが配置されているディレクトリ**（`$PSScriptRoot`）からの相対パスとして解決されます。呼び出し側のカレントディレクトリは使われません。

これにより：

* どのフォルダから `.\Download-SpeakerDeck.ps1` を実行しても、出力先は常に同じ場所（スクリプトの隣）になります。
* ダウンロード結果と作業ファイルの両方が一箇所にまとまり、後片付けが容易です。

スクリプトが `C:\Temp\download-speakerdeck-oracle4engineer\Download-SpeakerDeck.ps1` にある場合、デフォルトでは以下のような構造になります：

```
C:\Temp\download-speakerdeck-oracle4engineer\
  ├─ Download-SpeakerDeck.ps1
  ├─ downloads\          ← -OutputDir デフォルト（コンテンツのみ・PDF）
  │   └─ <title>__<filename>.<ext>
  └─ work\               ← -WorkDir デフォルト（スクリプト管理ファイル）
      ├─ diag\
      │   ├─ speakerdeck_diag_*.html        ← Phase 2 で 0 件検出時のみ
      │   └─ failed\
      │       └─ 0042_<slug>.txt            ← Phase 6 失敗 1 件ごとの詳細診断
      └─ logs\
          ├─ P04_evaluation_log.csv         ← Phase 4 結果（DryRun のみ）
          ├─ P05_filename_plan.csv          ← Phase 5 結果（常に生成）
          ├─ P06_download_log.csv           ← Phase 6 結果（本番実行のみ）
          ├─ P06_errors.jsonl               ← Phase 6 失敗時のみ（JSONL）
          └─ P07_final_state.csv            ← Phase 7 突合結果（本番実行のみ）
```

すべての CSV/JSONL ファイルに **`P##_` プリフィックス** が付与されているため、エクスプローラーの名前順表示 = Phase 実行順となり、パイプラインのデータフローが一目で把握できます。

絶対パスを指定すれば、スクリプト相対の挙動はオプトアウトできます：

```powershell
.\Download-SpeakerDeck.ps1 -OutputDir "D:\SpeakerDeck\decks" -WorkDir "D:\SpeakerDeck\work"
```

## フェーズ構成

```
Phase 1 : 環境評価                       (Setup)
          - Step 0: PowerShell 実行環境ダンプ
                    (PS バージョン、Edition、CLR、ビット数、OS、
                     ExecutionPolicy、エンコーディング、TLS、
                     カルチャー、スクリプトパス) + 互換性チェック表
          - Step A: レジストリ確認 (LongPathsEnabled)
          - Step B: 実機ダミーファイル作成テスト
          - Step C: 環境を 4 段階に分類して閾値を決定
Phase 2 : 公開資料総数取得                (Scan)
Phase 3 : 一覧収集                       (Scan)  シーケンシャル、全ページ
Phase 4 : 個別評価                       (Scan)  軽い並列度、ダウンロード可否を判定
Phase 5 : ファイル名計画                  (Plan)
          - 全項目の OutputFilename / OutputFullPath を事前計算
          - OutputFullPath の重複と MAX_PATH 違反を事前検知
          - P05_filename_plan.csv へ保存
Phase 6 : 適応的並列ダウンロード           (Fetch) -- DryRun 時はスキップ
          - Runspace Pool、初期 3 / 最大 5
          - HTTP 429 で自動スロットル（並列度を半減 + 60 秒待機）
          - HTTP 5xx で並列度を 1 段階下げる
          - 連続失敗 3 件で緊急ブレーキ（最小値強制 + 90 秒待機）
          - 連続成功 10 件で並列度を +1 引き上げ
Phase 7 : 突合 (Reconciliation)         (Verify) -- DryRun 時はスキップ
          - Plan + Download Log + ディスク実体を結合
          - レコードごとに Discrepancy フラグ付与
            (OK / SizeMismatch / MissingAfterSuccess / WrongYearFolder 等)
          - プラン外ファイル（前回実行残骸、.part 等）も "(extra)" 行として記録
          - P07_final_state.csv へ保存
Phase 8 : PDF メタデータによる事後分類      (Verify) -- DryRun 時はスキップ
          - _undated/ に正常ダウンロードされた各 PDF について
            ピュア PowerShell の正規表現でメタデータを読み取り
          - /CreationDate / xmp:CreateDate 等から有効な年
            (2010..currentYear+1) が得られたら _undated/<file>.pdf
            から <year>/<file>.pdf へファイルを移動
          - work/logs/year_overrides.csv に追記
            （次回実行時の Phase 5 が優先順位 0 で参照することで
            再ランでも一貫性が保たれる：再ランでは何もしない）
          - -SkipPdfReclassification でオプトアウト可能
          - -FlatLayout 指定時は自動的にスキップ
Phase 9 : 最終レポート                    (Report)
          - ダウンロード集計 + 失敗内訳 + 年別分布
          - PDF メタデータ事後分類の統計 (Phase 8)
```

## PDF メタデータによる事後分類 (Phase 8)

デッキの Title、OriginalFilename、og:meta のいずれからも公開年が判定できない場合、Phase 5 は `_undated/` フォルダに振り分けます。Phase 8 は **実際にダウンロードした PDF の内部メタデータ** を読み取って 2 度目の判定を試みます。典型的に救済できるのは以下のケース：

* Speaker Deck の og:meta が剥奪 / 未設定
* 投稿者のファイル名に日付情報が埋め込まれていない
* タイトルが実タイトルではなく slug（URL の一部）になっている

PDF 内部での年判定の優先順位：

1. **PDF Info Dictionary** `/CreationDate (D:YYYYMMDD...)` → `PdfInfoDict`
2. **XMP** `<xmp:CreateDate>YYYY-...</...>` → `PdfXmp`
3. **XMP 旧名前空間** `<xap:CreateDate>` → `PdfXmpLegacy`
4. **XMP pdf 名前空間** `<pdf:CreationDate>` → `PdfXmpPdfNs`
5. **フォールバック日付** `/ModDate` または `<xmp:ModifyDate>`（CreationDate が無い場合のみ）

範囲 `[2010, currentYear + 1]` のチェックは Phase 5 と同じです。

### 再実行時の整合性 (year_overrides.csv)

救済に成功するたびに `work/logs/year_overrides.csv` に以下のカラムで追記されます：

```
DeckUrl, OriginalFilename, PlanYearFolder, ResolvedYearFolder,
ResolvedDate, YearSource, DetectedAt
```

**次回実行時**、Phase 5 の `Get-DeckYear` はこの CSV を **優先順位 0**（他のすべての判定より前）で参照します。その結果：

* 前回救済済みのデッキは今回最初から正しい年フォルダに振り分けられる
* Phase 6 はファイルが既にその場所にあることを検知してダウンロードをスキップ
* Phase 7 は不整合を検出しない（誤った `WrongYearFolder` 警告は出ない）
* Phase 8 は救済対象なし (`Examined: 0`)

最初から救済をやり直したい場合は `year_overrides.csv` を削除するか `-Clean` を使用してください。

## PowerShell 実行環境の要件

本スクリプトは **Windows PowerShell 5.1** を最小要件としています
（Windows 10、Windows 11、Windows Server 2016 / 2019 / 2022 / 2025 に
標準で同梱されている既定のシェル）。PowerShell 7+ も動作しますが必須ではありません。

**起動時に強制チェックされる要件**（満たさない場合はスクリプトが拒否）：

* PowerShell バージョン 5.1 以上
* 64-bit PowerShell プロセス（`(x86)` ホストは拒否）

**警告のみ（実行は継続）**：

* OS ビルド番号が既知の一覧にない（新しいビルドは動作する。古いものは WMF 5.1 が必要な場合あり）

Phase 1 の Step 0 で完全な環境診断情報が出力されます。問題報告の際は
このブロックを共有していただくと、再現環境を正確に特定できます。

## 出力ファイル名のルール

* **フル形式**     : `<title>__<original_filename>`
* **短縮形式**     : `<title>_<YYYYMMDD>.<ext>`（システム制約が厳しい環境で使用）
* **タイトル切詰** : 短縮形式でも収まらない場合、有効な filename / full path 制限に合わせてタイトルを切り詰め

Windows で禁止される文字は、ASCII 互換文字へ置換します：

| 禁止文字 | 置換後   |
| -------- | -------- |
| `<`      | `(`      |
| `>`      | `)`      |
| `:`      | `-`      |
| `"`      | `'`      |
| `/` `\` `|` | `_`   |
| `?` `*`  | (削除)   |

## 出力ファイル

`downloads\` ツリーには Speaker Deck から取得した PDF コンテンツのみが配置されます。スクリプトが生成する管理ファイル（ログ・診断ダンプ）はすべて `work\` 配下にまとめられます。CSV/JSONL ログには **`P##_` プリフィックス** が付いており、アルファベット順 = Phase 実行順となります。

* `<OutputDir>\<title>__<filename>.<ext>`               — ダウンロードされた資料本体（コンテンツのみ）
* `<WorkDir>\logs\P04_evaluation_log.csv`               — Phase 4 のデッキ別ダウンロード可否判定結果（DryRun 時のみ）
* `<WorkDir>\logs\P05_filename_plan.csv`                — Phase 5 の事前計算ファイル名計画（常に生成）
* `<WorkDir>\logs\P06_download_log.csv`                 — Phase 6 のデッキ別 CSV サマリー（本番実行時のみ）
* `<WorkDir>\logs\P06_errors.jsonl`                     — Phase 6 の構造化エラーログ（JSONL、失敗 1 件 = 1 行、失敗発生時のみ）
* `<WorkDir>\logs\P07_final_state.csv`                  — Phase 7 の突合結果（Plan + Download Log + ディスク実体を統合、行ごとに Discrepancy フラグ付き、本番実行時のみ）
* `<WorkDir>\logs\year_overrides.csv`                   — Phase 8 の PDF メタデータ救済履歴。次回実行時の Phase 5 が優先順位 0 で参照する（初回救済成功時に遅延作成）
* `<WorkDir>\logs\debugtrace.jsonl`                     — **Debug Trace Facility**：各 Phase の frame.open / step / frame.close イベントを記録するリアルタイム JSONL ストリーム（常に生成。下記「デバッグトレース」セクション参照）
* `<WorkDir>\diag\speakerdeck_diag_<account>_*.html`    — Phase 2 が 0 件検知時の生 HTML ダンプ
* `<WorkDir>\diag\failed\<index>_<slug>.txt`            — Phase 6 失敗 1 件ごとの詳細診断（HTTP ステータス、ヘッダー、レスポンスボディ先頭、スタックトレース、リトライ履歴）
* `<WorkDir>\diag\debugtrace_export_<phaseId>_<ts>.json` — **Debug Trace Facility**：Phase が例外を投げた瞬間の自動エクスポート JSON スナップショット（未捕捉例外が発生した場合のみ。下記「デバッグトレース」セクション参照）

### CSV カラム共通規約

4 種類の CSV ログ(`P04_*`, `P05_*`, `P06_*`, `P07_*`)は、 Phase を
またいだ突合・grep ができるよう **共通カラム名** を使用しています。
同じ意味のデータは必ず同じカラム名で記録されます:

| カラム名 | 意味 | 含まれる CSV |
|---|---|---|
| `Index` | スキャン順での 1 始まりのレコード番号 | P04, P05, P06, P07 |
| `Title` | デッキの og:title | P04, P05, P06, P07 |
| `DeckUrl` | Speaker Deck のデッキページ URL | P04, P05, P06, P07 |
| `DownloadUrl` | PDF 本体のダウンロード URL | P04, P05, P06, P07 |
| `OriginalFilename` | 投稿者がアップロード時に付けた元ファイル名(サニタイズ前)| P04, P05, P06, P07 |
| `PublishDate` | og:meta 由来の YYYYMMDD(Phase 4 で取得)| P04, P05, P06, P07 |
| `YearFolder` | 年フォルダ名(`2024`、 `2025`、 …、 または `_undated`)| P04, P05, P06(P07 では `PlanYearFolder` / `DiskYearFolder` に分離)|
| `YearSource` | YearFolder を導出した規則名(`OverrideCsv` / `OriginalFilename` / `PublishDate` / `TitleJp` / `TitleNum` / `Fallback` / `PdfInfoDict` / `PdfXmp` 他)| P04, P05, P06 |
| `OutputFilename` | ディスク上で実際に使用するサニタイズ後のファイル名 | P05, P06, P07 |

各 Phase の CSV は、 前 Phase のデータを **スーパーセット** として
継承し、 その Phase 固有の情報を追加します(例:P06 は `Status` /
`Bytes` / `DurationMs` / `Attempts` を、 P07 は `Discrepancy` /
`PlanYearFolder` / `DiskYearFolder` / `FileExists` / `SizeMatch` を
追加)。

`year_overrides.csv` ファイル(Phase 8 で生成)は Phase 単位のログ
ではなく、 再実行間で永続化される状態ファイルです。 カラム仕様は
「PDF メタデータによる事後分類 (Phase 8)」セクションを参照して
ください。

## トラブルシューティング

### 「セキュリティ警告」が表示される

```powershell
Unblock-File .\Download-SpeakerDeck.ps1
```

### 「このシステムではスクリプトの実行が無効になっている」エラー

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 「Not downloadable」が大量に発生する

これは投稿者がダウンロードを無効化しているケースです。スクリプトはこの設定を尊重し、ダウンロードをスキップします。

### HTTP 429 / 503 が頻発する

自動スロットリングが作動しますが、それでもエラーが続く場合は、手動で並列度を下げてください：

```powershell
.\Download-SpeakerDeck.ps1 -MaxConcurrency 2 -InitialConcurrency 1 -DelaySeconds 2.0
```

### Phase 2 で 0 件しか取得できない

Speaker Deck の HTML 構造が変更された可能性があります。 Page 1 で
0 件が返された場合、 スクリプトは自動的に取得した HTML を以下に
ダンプします:

```
<WorkDir>\diag\speakerdeck_diag_<account>_<timestamp>.html
```

(デフォルト: `<スクリプト配置ディレクトリ>\work\diag\`)

このファイルを開いて現在の HTML 構造を確認し、 `Get-AllDeckList`
関数内の正規表現パターンを調整してください。

診断出力には以下も含まれます:

* HTML のサイズ(文字数)
* HTML 内のアカウント名の出現回数
* `/<アカウント名>/<slug>` 形式の候補パスの数
* `<a` タグと `title=` 属性の総数

`/<アカウント名>/<slug>` のカウントが `0` の場合、 サーバーが簡略化
された HTML を返しています — User-Agent やボット検知が原因の可能性
が高いです。 このスクリプトは既に Chrome 相当のヘッダー(`Accept`、
`Accept-Language`、 `Sec-Fetch-*`、 `Sec-Ch-Ua` 等)を送信していますが、
それでも問題が解消しない場合は、 保存された HTML を実際のブラウザで
開き、 Chrome が受信する内容と比較してください。

### Phase 6（ダウンロード）で失敗が発生した場合

実行終了時に表示される **Failure breakdown** テーブルで失敗の傾向
を確認します:

```
  Failure breakdown:
    HTTP 503 (Service Unavailable)         :  41
    HTTP 429 (Too Many Requests)           :  18
    Timeout                                :   9
    PathTooLong                            :   5
    Other                                  :   3

  Detailed errors saved to:
    C:\Temp\download-speakerdeck-oracle4engineer\work\logs\P06_errors.jsonl
    C:\Temp\download-speakerdeck-oracle4engineer\work\diag\failed\
```

詳細な調査には以下の 2 種類の成果物を使います:

1. **`work\logs\P06_errors.jsonl`** — JSON オブジェクトを 1 行 1 件
   で記録した機械可読形式。 `jq` や `ConvertFrom-Json` で集計でき
   ます:

   ```powershell
   Get-Content .\work\logs\P06_errors.jsonl | ForEach-Object {
       $_ | ConvertFrom-Json
   } | Group-Object category | Sort-Object Count -Descending
   ```

2. **`work\diag\failed\<index>_<slug>.txt`** — 失敗 1 件ごとの人間
   可読な詳細ダンプ。 HTTP ステータス、 レスポンスヘッダー、
   レスポンスボディ先頭 2KB(取得できた場合)、 リトライ履歴、
   失敗時のスタックトレースを含みます。

実行後の包括的な分析には、 **`work\logs\P07_final_state.csv`** も
参照してください。 これは Plan + Download Log + ディスク実体を統合
した突合結果で、 Discrepancy 列で異常(サイズ不一致、 ダウンロード
成功後の消失、 部分ダウンロード等)を一覧できます。

代表的なエラーカテゴリと対策:

| カテゴリ                  | 想定原因                       | 対策                                                                                       |
| ------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------ |
| HTTP 429                  | Speaker Deck のレート制限      | 並列度を下げて再実行: `-MaxConcurrency 2 -InitialConcurrency 1 -DelaySeconds 2.0`          |
| HTTP 503 / 502 / 504      | 一時的なサーバー / CDN エラー  | 再実行で多くは解消(適応的リトライにより 2 回目で成功するケースが多い)                  |
| Timeout                   | 低速回線・大容量 PDF           | 再実行、 または `-MaxRetries 5` の指定                                                     |
| PathTooLong               | NTFS パス長制限の超過          | スクリプトをより短いパスに移動、 または `-OutputDir` を短縮                                |

### 完全にクリーンな状態から再実行する

```powershell
# 全削除 → 即フル実行
.\Download-SpeakerDeck.ps1 -Clean

# 全削除のみ・実行はしない
.\Download-SpeakerDeck.ps1 -CleanOnly
```

両スイッチとも `<OutputDir>` と `<WorkDir>` を再帰的に削除します。安全チェックにより、削除対象パスがスクリプト自身のディレクトリと一致する、ドライブルートに該当する、またはスクリプトを含む親ディレクトリの場合は **実行を拒否** します。

## デバッグトレース

本スクリプトには **Debug Trace Facility** が組み込まれており、 各 Phase の名前付きステップを逐次記録します。 出力は 2 種類です：

| 出力先 | 出力タイミング | 用途 |
|---|---|---|
| `work\logs\debugtrace.jsonl` | 常に生成（本番実行ごと） | 全 Phase の entry / step / exit イベントをリアルタイムに JSONL 形式で追記。 UTF-8 with BOM、 追記専用 |
| `work\diag\debugtrace_export_<phaseId>_<timestamp>.json` | Phase が例外を投げた時のみ | 失敗時点のスナップショットを自動エクスポート。 アクティブスタック、 完了済みフレーム、 Phase 別結果、 ホスト情報を含む単一ファイル |

ワークディレクトリ作成直後に自動的に有効化され、 標準出力に以下のような 1 行確認メッセージが表示されます：

```
[*] Debug trace -> C:\Temp\download-speakerdeck-oracle4engineer\work\logs\debugtrace.jsonl
```

### この機能が役立つ場面

Phase 6 のデッキ別失敗ログ(`P06_errors.jsonl`)は「どのデッキが失敗
したか」を記録します。 Debug Trace Facility はそれとは別の問いに
答えます:「関数内のどの名前付きステップで例外が発生したか」。 デッキ
単位ではない失敗、 たとえば Phase 5 の filename 計画中の
`PathTooLongException`、 CSV 書き込み中の予期せぬ
`System.IO.IOException`、 Phase 4 の正規表現パース失敗などの診断に
最も有用です。

### `debugtrace.jsonl` の調査方法

1 行 1 つの JSON オブジェクトとして格納されています。 便利な one-liner：

```powershell
# kind 別にイベント数を集計
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Group-Object kind | Sort-Object Count -Descending

# Phase 5 内で実行された全ステップを表示
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.kind -eq 'step' -and $_.ctx -eq 'Invoke-Phase5FilenamePlan' } |
    Select-Object ts, step

# 全 failure イベントをスタックトレース付きで表示
Get-Content .\work\logs\debugtrace.jsonl |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.kind -eq 'failure' } |
    Format-List ts, ctx, step, exType, msg, stack
```

### 自動エクスポートされたスナップショットの調査方法

Phase が例外を投げたとき、 トップレベルの catch ハンドラが `work\diag\` に 1 つの自己完結型 JSON ファイルを書き出します。 ファイル名は `debugtrace_export_<phaseId>_<YYYYMMDD-HHmmss>.json` で、 以下を含みます：

| キー | 意味 |
|---|---|
| `script.version` / `script.tag` / `script.sha256` | 実行されていたビルドの識別子 |
| `hostInfo` | PS バージョン、 edition、 CLR、 OS、 culture、 ホスト名 |
| `phases[]` | Phase 別の outcome と失敗参照 |
| `activeFrames[]` | 失敗時点でトレーススタックに残っていた関数 |
| `completedFrames[]` | 完了済みフレームの履歴 (ステップ毎の所要時間付き) |
| `events[]` | デフォルトで空。 `Export-DebugTraceJson -IncludeEvents` で手動エクスポート時に格納される |

バグレポートに添付するのはこの 1 ファイルだけで充分です。 数 MB 級の `debugtrace.jsonl` を共有しなくても、 メンテナは失敗のフルコンテキストを得られます。

### 無効化について

コマンドラインからは無効化できません(オーバーヘッドが極めて小さい
ため:800 デッキの実行で約 150 KB の JSONL、 ネットワーク I/O ゼロ)。
ベストエフォート設計のため、 ファイルアクティベーションに失敗した
場合(ディスク満杯、 権限不足など)は警告を出して機能なしで継続し
ます。 トレースイベントはメモリにバッファされ続け、 デバッガから
`Export-DebugTraceJson` を呼び出せばエクスポート可能です。

完全な仕様(イベントスキーマ、 module-level state、 public API)は
[SPEC.md A.14](SPEC.md#a14-debug-trace-facility) を参照してください。

---

## 開発者向け仕様

このスクリプトを拡張したい、 フェーズ構成を変更したい、 または同系統の
スクリプトを新規に作成したい場合は、 まず **[`SPEC.md`](SPEC.md)** を
読んでください。 リポジトリ共通のドキュメント言語ポリシーにより、 SPEC
は英語のみで維持されています。 SPEC では以下を体系化しています:

- **Part A(共通仕様)** — このファミリーのすべてのスクリプトが継承する
  規約:ソースファイル形式(UTF-8 BOM + ASCII のみ)、 フェーズ
  アーキテクチャ、 ログマーカー、 `-LiteralPath` ルール、 CSV カラム
  規約、 環境診断、 静的解析ゲート、 ドキュメント言語ポリシー
- **Part B(スクリプト固有仕様)** — このスクリプト固有のフェーズマップ、
  年フォルダ規則、 PDF メタデータ事後分類の詳細(Phase 8)、 適応的
  ダウンロード設定、 失敗回復
- **Part C(品質ゲート)** — すべてのコミット前に満たすべきチェック
  リスト
- **Part D(既知の落とし穴)** — 文書化された過去のバグとその修正:
  PowerShell パスでの `[ ]` ワイルドカード問題、 フェーズ番号振り直しの
  安全性など

リリース毎の変更履歴は **[`CHANGELOG.md`](CHANGELOG.md)**
([Keep a Changelog 1.1.0](https://keepachangelog.com/ja/1.1.0/) 形式)
を参照してください。 リポジトリ共通のドキュメント言語ポリシーにより
英語のみで維持されています。

実際の検証結果(DryRun、 本番実行出力、 冪等性チェック、 リグレッション
修正証跡)については **[`TESTING.md`](TESTING.md)** を参照してください。
直近の本番実行成功結果(`804/804 デッキ、 失敗ゼロ、 合計 10 分 4.4 秒、
5.7 GB`)が記録されています。

`psa.py` 静的解析ツール(latest mainline; `PSA1001`〜`PSA9002` + opt-in
規約ルール `PSAP0001`〜`PSAP0005`)の詳細は
[`../../python/powershell-static-analyzer/README.ja.md`](../../python/powershell-static-analyzer/README.ja.md)
(英語版は [README.md](../../python/powershell-static-analyzer/README.md))、
または完全な仕様書 [`SPEC.md`](../../python/powershell-static-analyzer/SPEC.md)
を参照してください。 正典の analyzer バージョンは
[`../../python/powershell-static-analyzer/VERSION`](../../python/powershell-static-analyzer/VERSION)
ファイルに記録されています。 consumer 側のワークフロー詳細はリポジトリ
ルート [`README.ja.md`](../../../README.ja.md) の「psa.py のバージョニング
ポリシー」を参照してください。

**新規開発における最重要ルール**:フェーズヘッダー、 ログマーカー、
psa.py を一から再導出しないこと。 既存実装からコピーすること。
**発明より再利用**。

---

## 開発者向け：静的解析

このスクリプトは `psa.py`（PowerShell Static Analyzer）で検証済みです。
このツールはレポジトリ全体での正規配置場所
[`scripts/python/powershell-static-analyzer/psa.py`](../../python/powershell-static-analyzer/psa.py)
に格納されており、Pure Python（標準ライブラリのみ）で実装されており、
外部依存はありません。

```bash
# 静的解析の実行（psa.py がローカルの .psa.config.json を自動発見します）
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
```

### ルールカバレッジ (psa.py — latest mainline)

`psa.py` はルールを 9 カテゴリに分類しています。 `PSA1xxx`〜`PSA7xxx`
は PowerShell スクリプト全般に適用される汎用ルール、 `PSA8xxx`
(ファイル間整合性)と `PSA9xxx`(複雑度メトリクス)はより高レベル
のルール、 `PSAPxxxx`(プロジェクト/パイプライン規約)は opt-in
規約ルールです。 ルールセットのバージョン別変遷については analyzer
自身の
[CHANGELOG.md](../../python/powershell-static-analyzer/CHANGELOG.md)
を参照してください。

| カテゴリ | コード範囲 | 例 |
| -------- | ---------- | -- |
| 構文の整合性  | `PSA1001`〜`PSA1003` | 波括弧 / 丸括弧 / 角括弧の整合性 |
| 意味解析      | `PSA2001`〜`PSA2011` | 未定義変数、 自動変数のシャドウイング、 `-match $変数` の罠、 `$null` を `-eq`/`-ne` の右辺に置く問題、 PSCustomObject の未宣言プロパティ代入 (`PSA2009`)、 未定義関数呼び出し (`PSA2010`)、 PS 5.1 で `Split-Path -LiteralPath ... -Parent` が AmbiguousParameterSet を発生させる検出 (`PSA2011`) |
| スタイル      | `PSA3001`〜`PSA3006` | `Start-Process -ArgumentList`、 バックティック行継続後の空行、 空の `catch` ブロック、 `Start-Transcript -Path` は `-LiteralPath` を使うべき |
| 衛生          | `PSA4001`〜`PSA4004` | 未完了マーカー、 行末空白、 長い行、 行末セミコロン |
| セキュリティ  | `PSA5001`〜`PSA5004` | 平文パスワードパラメーター、 `Invoke-Expression`、 壊れたハッシュアルゴリズム、 `ComputerName` ハードコード |
| ベストプラクティス | `PSA6001`〜`PSA6008` | 非承認動詞、 コマンドレットエイリアス、 複数形名詞の関数名、 `$global:` 定義、 必須パラメーターのデフォルト値、 `$true` がデフォルトのスイッチパラメーター、 `[OutputType()]` 属性の規約 |
| ファイル形式  | `PSA7001`〜`PSA7002` | PowerShell スクリプトに UTF-8 BOM がない、 mixed / 誤った改行コード |
| ファイル間整合性 | `PSA8001`         | 同一スキャン対象ファイル群における function body のハッシュ drift |
| 複雑度メトリクス | `PSA9001`〜`PSA9002` | function 本体の長さ閾値 (opt-in)、 外部プロセス呼び出し後の `$LASTEXITCODE` チェック漏れ (opt-in) |
| プロジェクト規約 | `PSAP0001`〜`PSAP0005` | phase 関数命名規約、 必須のスクリプト識別子変数、 インラインリビジョンタグコメント (`PSAP0003`)、 EOF の `REVISION HISTORY` ブロック (`PSAP0004`)、 **コメント本体内のリビジョン参照** (`PSAP0005`、 psa.py 4.0.0 で新規追加)。 **PSAPxxxx は全て default OFF**。 本プロジェクトは `PSAP0003` / `PSAP0004` / `PSAP0005` に opt-in しています (PSAP0005 は strict mode — `psap0005_relaxed_mode` は設定しないため、 コメント本体内の任意の `rNN` 参照が報告される)。 総ルール数は **46** です。 |

各ルールの完全仕様は
[`../../python/powershell-static-analyzer/SPEC.md`](../../python/powershell-static-analyzer/SPEC.md) §4 を参照。

### プロジェクト固有設定

このスクリプトディレクトリには `.psa.config.json` を同梱しており、 以下
を設定しています:

1. **enable**: `PSAP0003`、 `PSAP0004`、 `PSAP0005`(リビジョン規律の
   opt-in ルール)を有効化。 `PSAP0005` は strict mode —
   `psap0005_relaxed_mode` は意図的に設定していないため、 コメント本体
   内の任意の `rNN` 参照が報告されます。 r21 のクリーンアップコミット
   で全 `rNN` 参照を script body から除去済みのため、 strict baseline
   は検証済の end-state です。
2. **disable**: `PSA6003`(関数名詞の複数形)を無効化。
   `Download-SpeakerDeck.ps1` 内の 3 つの関数が意図的に複数形名詞を
   使用しているため。 根拠は config ファイル内にコメントで記録済み。

意図的な空 `catch` ブロック(`PSA3004`)には
`# psa-disable-line PSA3004 -- <理由>` を付与しています。 各抑制判断
の根拠は `SPEC.md` §A.11「Static Analysis with psa.py」に詳細を記載
しています。

### 現在の検証結果

```
==== psa.py: PowerShell Static Analyzer ====
File   : Download-SpeakerDeck.ps1
Lines  : 5205
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

r27 / `psa-py-v4-llm-governance-baseline` リリースで `psa.py` 4.0.1 を使用して検証済み。 スクリプトに変更を加える際は、 コミット前に上記コマンドで検証することを推奨します。 これは SPEC.md の Part C「品質ゲート」でも必須項目として定義されています。

## コンソール出力フォーマット

各ログ行には、現在時刻と現在のフェーズ開始からの経過時間がプレフィックスとして付きます：

```
[HH:mm:ss] [+X.XXs]   [マーカー] メッセージ
```

マーカー記号の意味：

| マーカー | 意味               | 色          |
| -------- | ------------------ | ----------- |
| `[*]`    | 進行中・処理段階   | シアン      |
| `[+]`    | 成功               | 緑          |
| `[!]`    | 警告               | 黄          |
| `[X]`    | 失敗               | 赤          |
| `[~]`    | スキップ           | ダークグレー |

フェーズの境界はマゼンタ色のバナーで囲まれます：

```
========================================================================
 PHASE P03  - ListCollection         (Scan   ) start: 13:04:15
 script: speakerdeck-2026.05.18-r25/abc123def456
========================================================================
[13:04:15] [+0.00s]      [*] Fetching page 1: https://speakerdeck.com/...
[13:04:16] [+0.85s]      [*] page 1: +18 decks (cumulative 18)
...
 PHASE P03  -> DONE     elapsed: 1m12.3s
```

実行終了時には、すべてのフェーズの所要時間サマリが表示されます：

```
========================================================================
 Phase Timing Summary
========================================================================
  P01   DONE     elapsed: 0.55s
  P02   DONE     elapsed: 0.42s
  P03   DONE     elapsed: 1m12.3s
  P04   DONE     elapsed: 4m18.0s
  P05   DONE     elapsed: 0.05s
  P06   DONE     elapsed: 6m02.5s
  P07   DONE     elapsed: 1.20s
  P08   SKIPPED  elapsed: 0.00s
  P09   DONE     elapsed: 0.08s
  ----------------------------------------
  Total elapsed: 11m33.8s
========================================================================
```

## ファイルエンコーディング

* スクリプトは **UTF-8 BOM 付き** で保存されています。これにより、Windows PowerShell 5.1 がファイルを確実に UTF-8 として認識します（BOM が無いと、システムコードページ — 日本語 Windows 環境では Shift-JIS / cp932 — として解釈されてしまいます）。
* 環境差によるエンコーディング問題を避けるため、コンソール出力メッセージとコード内コメントはすべて英語で記述されています。
