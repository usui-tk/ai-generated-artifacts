# TESTING.ja.md — 検証手順と実行結果

本ドキュメントは `Download-SpeakerDeck.ps1` の検証および評価に必要なすべての情報を集約しています。以下の 3 つの領域を網羅します：

1. **静的解析** — `scripts/python/powershell-static-analyzer/psa.py` のゲート（すべてのコミット前に合格必須）
2. **機能検証 — DryRun** — Speaker Deck の本番サイトに対する Phase 1〜5 のドライ実行（読み取り専用）
3. **機能検証 — 本番実行** — `oracle4engineer` アカウントに対する Phase 1〜9 の完全実行と、r16 → r17 のリグレッション修正の証跡

🇬🇧 **English version: see [TESTING.md](./TESTING.md).**

---

## 目次

- [0. 検証ステータスサマリー](#0-検証ステータスサマリー)
- [1. 静的解析ゲート](#1-静的解析ゲート)
- [2. 機能検証 — DryRun モード](#2-機能検証--dryrun-モード)
- [3. 機能検証 — 本番実行](#3-機能検証--本番実行)
- [4. 過去のリグレッション — r16 ワイルドカードバグ（r17 で解決）](#4-過去のリグレッション--r16-ワイルドカードバグr17-で解決)
- [5. 冪等性チェック（再実行時の挙動）](#5-冪等性チェック再実行時の挙動)
- [6. 発見済みバグと修正履歴](#6-発見済みバグと修正履歴)
- [7. CI/CD 自動化の展望](#7-cicd-自動化の展望)

---

## 0. 検証ステータスサマリー

| 項目 | ステータス | 最終検証日 |
|---|---|---|
| `psa.py` v3.1.0 on `Download-SpeakerDeck.ps1`（プロジェクト `.psa.config.json` 適用） | **0 errors / 0 warnings / 0 info** ✓ | psa-baseline-sync |
| `psa.py` v3.1.0 on `Test-PdfMetadata.ps1`（プロジェクト `.psa.config.json` 適用）     | **0 errors / 0 warnings / 0 info** ✓ | psa-baseline-sync |
| ファイルエンコーディング (UTF-8 BOM、BOM 以外は ASCII) | ✓ 両 `.ps1` | r20 ビルド |
| Phase 1 (EnvCheck) — Windows 11 / PS 5.1.26100.8328 | ✓ パス | 2026-05-11 |
| Phase 2〜5 (Scan / Plan) — DryRun モード | ✓ 804 デッキを評価 | 2026-05-11 |
| Phase 6 (Download) — 本番実行 | ✓ **804/804 成功**（失敗ゼロ）| 2026-05-11 (r17) |
| Phase 7 (Reconciliation) — 異常ゼロ | ✓ Discrepancy フラグ全て 0 | 2026-05-11 (r17) |
| Phase 8 (UndatedReclassify) — 再実行時の定常状態 | ✓ examined: 0 | 2026-05-11 (r17) |
| Phase 9 (FinalReport) — 出力検証 | ✓ 年別分布 + ログファイル列挙 | 2026-05-11 (r17) |
| 合計経過時間（本番実行、約 5.7 GB、804 ファイル）| 10 分 4 秒 | 2026-05-11 (r17) |

---

## 1. 静的解析ゲート

`psa.py` v3.1.0（28 ルール体系 `PSA1001`〜`PSA7001`）はすべてのコミット前に合格必須です
（[SPEC.ja.md](./SPEC.ja.md) Part C 参照）。

`psa.py` は CWD から `.psa.config.json` を自動発見するため、
正規の起動方法はこのスクリプトディレクトリから実行することです：

```bash
cd scripts/powershell/download-speakerdeck-oracle4engineer
python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
python3 ../../python/powershell-static-analyzer/psa.py Test-PdfMetadata.ps1
```

ローカルの `.psa.config.json` は、このディレクトリに限り `PSA6003`（関数名詞の複数形）
を disable しています。理由は、`Download-SpeakerDeck.ps1` 内の 3 関数
（`Resolve-RuntimeDirectories`、`Invoke-CleanupDirectories`、`Read-YearOverrides`）が
意図的に複数形名詞を使っているためです（複数リソースを扱う処理の意味的に正確だから）。
config ファイル内にコメントで根拠を記録済み。新規関数は単数形を推奨します。

期待出力（両スクリプト同様）：

```
==== psa.py: PowerShell Static Analyzer ====
File   : Download-SpeakerDeck.ps1
Lines  : 4107
Issues : 0 errors, 0 warnings, 0 info

  (no issues found)
```

`0 / 0 / 0` から外れた場合はコミット禁止。28 ルールの完全仕様は
[`../../python/powershell-static-analyzer/SPEC.ja.md`](../../python/powershell-static-analyzer/SPEC.ja.md)
§4 を参照（`PSA1xxx` 構文 / `PSA2xxx` 意味 / `PSA3xxx` スタイル / `PSA4xxx` 衛生 /
`PSA5xxx` セキュリティ / `PSA6xxx` ベストプラクティス / `PSA7xxx` ファイル形式）。

### 1.1 抑制ポリシー

「意図的な」空 catch ブロック（`PSA3004`）には、理由コメント付きの
インライン抑制ディレクティブを付与しています：

```powershell
try { ... } catch { } # psa-disable-line PSA3004 -- diagnostic only; ...
```

本スクリプト内のすべての `psa-disable-line PSA3004` は個別レビュー済みで、
以下のいずれかに分類されます：

- 診断情報のベストエフォート取得（ステータスコード・レスポンスヘッダ・ボディ）。
  リトライ／エラーハンドリングの判定は別の状態変数で行うため、診断取得失敗を
  握り潰しても安全。
- `foreach`-format / `foreach`-pattern ループ内のフォールバック。
  反復ごとの失敗は「次の候補を試す」という意味で正しい挙動。
- ホスト互換性のためのシム（古い PowerShell ホストに存在しない TLS enum 値など）。

---

## 2. 機能検証 — DryRun モード

DryRun は Phase 1〜5 を完全実行し（filename plan CSV 出力含む）、Phase 6 / 7 / 8 を明示的に SKIPPED とマークします。ファイルダウンロードは発生しません。

### 手順

```powershell
cd D:\Script_OracleDocs
Unblock-File .\Download-SpeakerDeck.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Download-SpeakerDeck.ps1 -DryRun
```

### 期待出力（要約）

```
========================================================================
  Speaker Deck Bulk Downloader
  vspeakerdeck-2026.05.13-r20/<hash>
========================================================================
  Account         : oracle4engineer
  ...

 PHASE P01  - EnvCheck               (Setup  ) -> DONE  elapsed: 0.30s
 PHASE P02  - GetTotalCount          (Scan   ) -> DONE  elapsed: 0.36s
 PHASE P03  - ListCollection         (Scan   ) -> DONE  elapsed: ~1m
 PHASE P04  - Evaluation             (Scan   ) -> DONE  elapsed: ~7m
 PHASE P05  - FilenamePlan           (Plan   ) -> DONE  elapsed: ~0.5s
 PHASE P06  - Download               (Fetch  ) -> SKIPPED (DryRun mode)
 PHASE P07  - Reconciliation         (Verify ) -> SKIPPED (DryRun mode)
 PHASE P08  - UndatedReclassify      (Verify ) -> SKIPPED (DryRun mode)
 PHASE P09  - FinalReport            (Report ) -> DONE  elapsed: ~0.2s
```

### 検証チェックリスト

- [ ] Phase 1 で `LongPathsEnabled = 1` および実効ファイル名 / フルパス閾値が表示
- [ ] Phase 5 が 804 行の `work/logs/P05_filename_plan.csv` を生成
- [ ] Phase 5 サマリーに年フォルダ分布が表示
- [ ] Phase 9 でダウンロードがスキップされたことが明示（成功と誤称しない）

---

## 3. 機能検証 — 本番実行

### 手順

```powershell
cd D:\Script_OracleDocs
.\Download-SpeakerDeck.ps1 -Clean        # 初回ゼロからの実行
# または
.\Download-SpeakerDeck.ps1               # 増分実行（失敗分のみ再取得）
```

### 検証結果（r17 ビルド、2026-05-11、oracle4engineer）

```
[Download]
    New downloads (Success) :   804
    Skipped (already exist) :     0
    Failed                  :     0          ← 失敗ゼロ
    Total size              :  5,676.5 MB

[Year distribution]
    2026 :   64 decks      2025 :  131 decks
    2024 :  134 decks      2023 :  167 decks
    2022 :  143 decks      2021 :  119 decks
    2020 :   42 decks      2019 :    3 decks
    2014 :    1 deck

 PHASE P01  -> DONE     elapsed: 0.30s
 PHASE P02  -> DONE     elapsed: 0.36s
 PHASE P03  -> DONE     elapsed: 1m 2.7s
 PHASE P04  -> DONE     elapsed: 7m 14.5s
 PHASE P05  -> DONE     elapsed: 0.50s
 PHASE P06  -> DONE     elapsed: 1m 45.5s
 PHASE P07  -> DONE     elapsed: 0.30s
 PHASE P08  -> DONE     elapsed: 0.02s
 PHASE P09  -> DONE     elapsed: 0.12s
 ----------------------------------------
 Total elapsed          :        10m 4.4s
```

### Phase 7 突合（異常ゼロ）

```
Reconciliation summary:
  Planned items                   :   804
    OK (downloaded + verified)    :   804
    OK-Skipped (already existed)  :     0
    FailedAsExpected              :     0
    NotAttempted                  :     0
    MissingAfterSuccess           :     0  *
    SizeMismatch                  :     0  *
    FailedButFileExists           :     0  *
    WrongYearFolder               :     0  *
  Extra files on disk             :     0
    UnexpectedFileOnDisk          :     0  *
    PartialDownload (.part)       :     0  *
```

`*` 付きの異常フラグは成功時にはすべて `0` であること必須。

---

## 4. 過去のリグレッション — r16 ワイルドカードバグ（r17 で解決）

本セクションは r17 修正がリグレッションを実際に閉じた証跡を保存しています。

### r16 の症状

```
[14:13:00] [+20.93s]    [X]  [#   6] Failed (System.IO.FileNotFoundException):
                                       oracle-technight-number-97-oracle-ai-database-26ai-updateai
[14:13:16] [+36.89s]    [X]  [#  12] Failed (System.IO.FileNotFoundException):
                                       oawtt26-thr1028
...
合計 76 件の失敗 — すべてのタイトルに '[' または ']' が含まれていた。
```

### r16 の最終状態

```
[Download]
    New downloads (Success) :   728
    Failed                  :    76
    Total size              :  5,182.7 MB
```

### 根本原因（[SPEC.ja.md](./SPEC.ja.md) Part D.6 に体系化）

`Invoke-WebRequest -OutFile` は PowerShell 5.1 において `-LiteralPath` を **サポートしない**。`-OutFile` のパスは内部で `-Path` セマンティクス（ワイルドカード展開あり）で処理されるため、`[` や `]` を含むパスはワイルドカード文字クラスとして解釈され `FileNotFoundException` で失敗する。

### r17 の修正

GUID 名の安全な一時パスにダウンロードしてから、`Move-Item -LiteralPath` で本来の宛先へ移動：

```powershell
$safeTmpName = '.dl_' + [Guid]::NewGuid().ToString('N') + '.part'
$safeTmp     = Join-Path $safeTmpDir $safeTmpName
Invoke-WebRequest -Uri $url -OutFile $safeTmp ...
Move-Item -LiteralPath $safeTmp -Destination $tmpFile -Force
```

### r17 の検証結果

| 年 | r16 成功 | r17 成功 | 救済 |
|---:|---:|---:|---:|
| 2026 | 53 | 64 | **+11** |
| 2025 | 108 | 131 | **+23** |
| 2024 | 115 | 134 | **+19** |
| 2023 | 159 | 167 | **+8** |
| 2022 | 139 | 143 | **+4** |
| 2021 | 108 | 119 | **+11** |
| 2020 | 42 | 42 | 0 |
| 2019 | 3 | 3 | 0 |
| 2014 | 1 | 1 | 0 |
| **合計** | **728** | **804** | **+76** |

**救済件数 (76) は r16 の失敗件数 (76) と完全に一致**。歴史的に失敗していたすべてのデッキが成功し、以前成功していたデッキにリグレッションは発生せず。

---

## 5. 冪等性チェック（再実行時の挙動）

初回成功実行の直後の再実行は、新たな作業ゼロの定常状態に到達するべきです：

### 手順

```powershell
.\Download-SpeakerDeck.ps1     # -Clean なし
```

### 期待される定常状態

- 804 ファイルすべてがディスク上に存在し、Phase 6 は `Skipped (already exist) : 804` を報告
- Phase 7 突合：異常ゼロ
- Phase 8: `Found 0 _undated file(s) eligible for PDF-metadata rescue`
- Phase 9 は新規ダウンロードゼロ、失敗ゼロを表示

### Phase 8 の冪等性メカニズム

`work/logs/year_overrides.csv` ファイルは、Phase 8 の PDF メタデータ救済の決定を実行間で永続化します。Phase 5 の `Get-DeckYear` はこのファイルを優先順位 0（最高）で参照するため、以前救済済みのデッキは再実行時に再救済されずに年フォルダへ直接ルーティングされます。

完全に最初からやり直すには：

```powershell
.\Download-SpeakerDeck.ps1 -Clean
```

これにより `<OutputDir>` と `<WorkDir>`（`year_overrides.csv` を含む）が削除されてから実行されます。

---

## 6. 発見済みバグと修正履歴

| リビジョン | バグ | 深刻度 | 修正 |
|---|---|---|---|
| r10 | `[ ]` を含むパスで `Test-Path` / `Get-Item` / `Remove-Item` / `Move-Item` が失敗 | 高 | すべてのパスコマンドレット呼び出しに `-LiteralPath` を適用 |
| r11 | `Split-Path -LiteralPath -Parent` が PS 5.1 で有効なパラメーターセットではない | 中 | `[System.IO.Path]::GetDirectoryName($p)` を使用 |
| r12 | 年が導出できない場合に _undated/ フォルダが累積 | 中 | 年フォルダ構成 + `_undated/` フォールバックを追加 |
| r13 | 異なる ja-JP セットアップでの環境の不確実性 | 低 | Phase 1 Step 0 で完全な環境ダンプを追加 |
| r14 | フェーズ間で CSV カラムが不整合 | 低 | 共通 8 カラム規約を体系化 |
| r15 | メタデータが存在するのに _undated/ ファイルが再分類されない | 中 | Phase 8 PDF メタデータ事後分類を追加 |
| r16 | フェーズ番号に小数 (`P6.5`) があり、ログで混乱を招く | 低 | P01..P09 に振り直し（1 始まりの整数）|
| **r17** | **`Invoke-WebRequest -OutFile` のワイルドカード解釈で `[ ]` パスが破綻** | **高** | **GUID 名の安全な一時ファイル + `Move-Item -LiteralPath`** |
| r18 | `ai-generated-artifacts` リポジトリへのフォルダ配置統合 | 装飾的 | リポジトリ配置に合わせて README + SPEC を更新 |
| r19 | 単一アカウントフォルダで複数ターゲットをホストできない | 装飾的 | フォルダ名に `-<account>` サフィックスを追加 |
| r20 | SPEC ファイル命名が上流リポジトリと不整合 | 装飾的 | `spec.en.md` を `SPEC.md` に、`spec.ja.md` を `SPEC.ja.md` にリネーム、A.1.x 構造を刷新、psa.py を上流と同期、TESTING.md を追加（その後 psa.py は `scripts/python/powershell-static-analyzer/` にレポジトリ全体の正規配置場所として昇格） |

[SPEC.ja.md](./SPEC.ja.md) Part D の「既知の落とし穴」エントリで、これらの各修正をプロジェクトの組織記憶として正式化しています。

---

## 7. CI/CD 自動化の展望

GitHub Actions のワークフロー（Linux runner — Python のみ、PowerShell 不要）：

```yaml
name: Static analysis
on: [push, pull_request]

jobs:
  psa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Static-analyze main script
        run: |
          cd scripts/powershell/download-speakerdeck-oracle4engineer
          python3 ../../python/powershell-static-analyzer/psa.py Download-SpeakerDeck.ps1
      - name: Static-analyze PoC script
        run: |
          cd scripts/powershell/download-speakerdeck-oracle4engineer
          python3 ../../python/powershell-static-analyzer/psa.py Test-PdfMetadata.ps1
```

Windows 側の機能 CI ジョブは現在計画されていません。理由：

- Phase 6 (Download) は実行ごとに約 5 GB の通信量を消費
- Speaker Deck のレート制限が繰り返し CI 実行を制限する可能性
- 機能検証は意図的にオペレーターが目視確認する人手作業として設計

ローカル検証の推奨頻度：

1. **すべてのコミット** — `psa.py`（上記）
2. **すべての PR** — オペレーターワークステーション上で `-DryRun`（約 9 分）
3. **リリースタグ前** — クリーン環境での本番実行（`-Clean`）と Phase Timing Summary を本ファイルへ取り込み

---

## ライセンス

本ドキュメントは `usui-tk/ai-generated-artifacts` リポジトリの一部であり、[MIT ライセンス](../../../LICENSE) の下で公開されています。
