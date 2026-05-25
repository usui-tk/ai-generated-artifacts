# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux 検証 (psa.py + pwsh 7 上の PSScriptAnalyzer) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows 検証 (Windows PS 5.1 上の PSScriptAnalyzer + スモークテスト) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Windows Synthetic フルパイプライン (`-SyntheticTestMode`) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml) |

[English](README.md) | **日本語**

Windows Server の評価版 ISO に Microsoft のサービススタック更新プログラム
(SSU)、最新累積更新プログラム (LCU)、Dynamic Updates、.NET 更新を統合して、
`install.wim` / `boot.wim` / `winre.wim` の中身が既に最新状態になった
ブート可能 ISO を出力するスクリプトです。ラボや検証環境の Windows Server
2016 / 2019 / 2022 / 2025 を構築するときに発生する数時間に及ぶ Windows
Update 工程を一掃することが目的です。Windows 11 + Windows PowerShell 5.1
を主対象とし、PowerShell 7 以降でも動作します。

**動的パッチ解決機能。** パッチセットは `Config/<OsKey>.json` の
`PatchBaseline` ノードに記録され、記録時点 (`PatchTuesdayOfBaseline`)
が現在の Patch Tuesday より古い場合に、Microsoft Update Catalog から
自動的に再取得・再記録されます。さらに DISM マウントを開始する前に、
`wsusscn2.cab` と Windows Update Agent COM API による依存性検証パスが
実行され、提供パッチセットが必要な依存関係 (例: 最新 LCU の前提 SSU)
を満たしているか Microsoft 公式判定で確認されます。

本スクリプトは
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
リポジトリの `scripts/powershell/update-windows-server-iso/` 配下に
あります。

## ⚠️ 免責事項

**自己責任でご利用ください。** 本スクリプトは「現状有姿(AS IS)」で提供され、
明示・黙示を問わずいかなる保証もありません。本スクリプトの使用、改変、
配布に起因または関連して発生した、直接的または間接的なあらゆる損害 (データ
損失、アカウント停止、ネットワーク障害、ディスク容量枯渇、インストールメディア
の破損等を含むが、これらに限らない) に対し、作者および貢献者は一切の責任を
負いません。

本スクリプトを実行することにより、利用者は以下を承諾するものとします:

* 評価版 ISO に対しては **Microsoft ソフトウェアライセンス条項**、パッチ
  ファイルに対しては **Microsoft Update Catalog 利用規約** に従っているか
  を、利用者の責任で確認すること
* 大量のデータをダウンロードすることに伴う一切の影響 (帯域コスト、ストレージ
  コスト、レート制限、IP ブロック) は利用者の責任で負担すること
* 出力 ISO を **公的に再配布しない** こと。評価版ライセンスは評価版
  Microsoft バイナリの再配布を禁じています
* 出力 ISO は、評価版ライセンスが認める期間内において、内部ラボ・検証・
  評価目的にのみ使用すること
* 本番データを保持する環境で実行する前に、本スクリプトのソースコード
  (特に DISM マウントおよび `oscdimg` 書き込み経路) を読んで動作を理解
  すること
* DISM 操作には管理者権限が必要で、異常終了時に WIM マウントが残存する
  可能性があります。スクリプト自身のクリーンアップが間に合わなかった場合、
  利用者の責任で除去する必要があります

本リポジトリ全体に適用される完全な免責事項と自己責任条項については、
[ルート README](../../../README.md) ([英語版](../../../README.md))
を参照してください。

## ライセンス

本プロジェクトは `usui-tk/ai-generated-artifacts` リポジトリの一部であり、
**MIT ライセンス**で配布されます。完全なライセンス本文はリポジトリ
ルートの [`LICENSE`](../../../LICENSE) ファイルを参照してください。

要約: 著作権表示およびライセンス通知の保持を条件として、利用者は本ソフト
ウェアを任意の目的で使用、改変、再配布することができます。本ソフト
ウェアは無保証で提供されます (上記免責事項および LICENSE ファイルを参照)。

なお、この MIT ライセンスは **スクリプト本体** に対するものです。本
スクリプトが処理する Microsoft バイナリ (評価版 ISO、SSU、LCU 等) は
カバーされません。これらは各アセットに付属する **Microsoft ソフトウェア
ライセンス条項** に従います。

## フォルダ構成

```
scripts/powershell/update-windows-server-iso/
  Update-WindowsServerIso.ps1     # 本体スクリプト (この README が説明対象)
  README.md / README.ja.md        # エンドユーザー向け文書 (本ファイル群)
  SPEC.md                          # 開発者・LLM 向け仕様書 (英語のみ)
  TESTING.md                       # 検証手順と検証済み事項 (英語のみ)
  CHANGELOG.md                     # リビジョン変更履歴 (英語のみ)
  .psa.config.json                 # psa.py プロジェクト設定
  PSScriptAnalyzerSettings.psd1    # PSScriptAnalyzer プロジェクト設定
  Config/                          # OS 別プロファイル
    Server2016.json
    Server2019.json
    Server2022.json
    Server2025.json
  tests/                           # Python 製 自己検証ツール (r04.4+)
    README.md                      # 各ツールの使い方ガイド
    catalog_probe.py               # T1: Microsoft Update Catalog ライブプローブ
    catalog_fixture_test.py        # T2: HTML フィクスチャによるオフライン回帰テスト
    powershell_harness.py          # T3: -Action TestHarness 経由の PS 関数単体テスト
    eval_iso_probe.py              # T4: 評価版 ISO エンドポイント検査
    wsusscn2_probe.py              # T5: wsusscn2.cab 鮮度検査
    common/                        # 共通モジュール (HTTP / パーサー / PS 呼出)
    fixtures/                      # Catalog HTML キャプチャ (オフライン回帰用)
    snapshots/                     # T1 の出力 (last_probe.json)
```

本スクリプトの検証に使う PowerShell 静的解析ツール (`psa.py`) は、本
リポジトリの正規位置である
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/)
にあります。

本スクリプト用の GitHub Actions ワークフローはリポジトリ直下の
[`.github/workflows/`](../../../.github/workflows/) に
`scripts__powershell__update-windows-server-iso__stage<N>__<runner>.yml`
という命名規則で配置されています。

**実行**したいだけならこの README を読んでください。**スクリプトを拡張
したい、または同種スクリプトを新規に作成したい**場合は [`SPEC.md`](./SPEC.md) も
読んでください。**何が検証済みで何が未検証(オペレーター待ち)か**を
知りたい場合は [`TESTING.md`](./TESTING.md) を参照してください。

## クイックスタート

```powershell
# 1. ファイルをアンブロック (インターネット由来警告を解除)
Unblock-File .\Update-WindowsServerIso.ps1

# 2. 現プロセスで署名済みまたはローカルスクリプト実行を許可
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. 登録フェーズの一覧表示 (副作用なし)
.\Update-WindowsServerIso.ps1 -Action ListPhases

# 4. 環境情報のみ表示して終了
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly

# 5. Server 2019 ja-jp のサンドボックスドライラン (計画を表示するが書き込みなし)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -DryRun

# 6. 実機フルビルド (-Execute 必須。これが唯一 WIM をマウント・修正するモード)
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -Execute
```

## 管理用 Action: Config ベースラインの保守

`Config/<OsKey>.json` はスクリプトが使うベースラインデータの保管場所です。次の 2 つの管理用 Action で、ISO に触れずにこれらのデータを更新・参照できます。

```powershell
# 月次更新(デフォルト Mode): 記録されている Patch Tuesday が
# 最新のものより古いフィールドグループだけを更新する。
# Config/Server*.json をすべて巡回し、Microsoft Update Catalog を
# スクレイプして該当 JSON に書き戻す。
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines

# 初回確定: 自動 Refresher がある未確定フィールドグループ
# (PatchBaseline、LanguageSpecificPatches) も併せて埋める。
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial

# 強制更新: 状態に関係なく全グループを更新する。
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force

# 確認のみ: 書き戻しを行わずに何が変わるかだけを表示する。
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun

# 範囲を OS / 言語で限定する。
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp

# フィールド分類メタ情報を JSON でダンプする
# (外部の Schema validator や、データモデルを確認したい人間が使う)。
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification
# -> <WorkRoot>/logs/A02_FieldClassification.json
```

`RefreshAllBaselines` の終了コード: `0` = すべて成功、`1` = Refresher のいずれかが失敗、`2` = 手動入力が必要なフィールドが残っている(自動 Refresher が無い、典型的には新言語追加時の `LanguageSpecific.<lang>.Iso` グループなど)。

グループ別 CSV レポートが `<WorkRoot>/logs/A01_RefreshAllBaselines_report.csv` に出力されます。

## 動作要件

| 項目 | 要件 |
|---|---|
| OS | Windows 10/11 Pro/Enterprise/Education または Windows Server 2016 以降 |
| PowerShell | Windows PowerShell 5.1 推奨、または PowerShell 7 以降 |
| 権限 | 管理者 (DISM マウントには昇格が必須) |
| ツール | Windows ADK Deployment Tools (`oscdimg.exe` のため) |
| ディスク空き | **`-WorkRoot` ドライブに 100 GB**(ワークスペース プリフライト チェックがすべての Action 開始前に強制。`-SkipEnvCheck` で運用者責任のもと回避可) |
| ネットワーク | ISO とパッチをダウンロードする場合に必要。`-IsoPath` + `-PatchDirectory` ですべてが揃う場合は不要 |
| Hyper-V | `-Action BootTest` を使う場合のみ必要 |

開発・CI 用に追加で必要なもの:

- Python 3.10 以降、および
  [`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/)
  の `psa.py`

## 対応 OS と言語

| OS キー     | ビルド | 言語タグ          | LCU 展開モード   | UEFI CA 2023 |
|-------------|:------:|-------------------|:----------------:|:------------:|
| Server2016  | 14393  | en-us, ja-jp      | 直接適用         | 不要         |
| Server2019  | 17763  | en-us, ja-jp      | 直接適用         | 不要         |
| Server2022  | 20348  | en-us, ja-jp      | 直接適用         | 不要         |
| Server2025  | 26100  | en-us, ja-jp      | MUM/CAB 展開     | 必要         |

OS 別プロファイル JSON は `Config/` 配下にあります。各プロファイルは
ビルド番号、既定の `boot.wim` インデックス、想定インストーラ エディション、
言語別の ISO ダウンロード URL (Eval Center FwLink プライマリ、Microsoft
ダウンロードミラーのフォールバック) を保持します。

## フェーズ一覧

| ID  | 名称              | グループ | 主な処理                                                                          |
|-----|-------------------|----------|-----------------------------------------------------------------------------------|
| P01 | Initialize        | Setup    | PowerShell 環境、管理者、ADK、ディスク空き、Hyper-V を確認                        |
| P02 | ResolveInputs     | Setup    | ISO / パッチ入力の解決、Config JSON の読み込み                                    |
| P04 | FetchAssets       | Fetch    | ISO とパッチをダウンロードしハッシュ検証                                          |
| P05 | ExpandIso         | Plan     | ソース ISO をマウントしてワークスペースへ展開、WIM インデックスを列挙             |
| P07 | PatchInstallWim   | Build    | 各 install.wim インデックスへ SSU → LCU → .NET の順で適用し、DISM クリーンアップ |
| P08 | PatchBootWim      | Build    | boot.wim (PE + Setup) と winre.wim へパッチ適用                                   |
| P09 | AssembleIso       | Build    | Dynamic Update Setup のオーバーレイ、Export-WindowsImage、oscdimg で ISO 生成     |
| P11 | StaticVerify      | Verify   | 出力 ISO をマウントし、KB パッケージが入っていることを確認                        |
| P13 | FinalReport       | Report   | 終端サマリー、ISO ハッシュ、ログのパスを表示                                      |

オプションで `-Action BootTest` を指定すると、出力 ISO に対して Hyper-V
Gen2 VM を起動する疎通テストが実行されます。各フェーズの完全な契約は
`SPEC.md` Part B を参照してください。

## 主要パラメータ

完全なパラメータ一覧は `Get-Help .\Update-WindowsServerIso.ps1 -Full`
で参照できます。代表的なもの:

| パラメータ                   | 用途                                                                            |
|------------------------------|---------------------------------------------------------------------------------|
| `-Action`                    | Prepare / Build / Verify / PrepareBuildVerify / BootTest / All / Cleanup / ListPhases / GenerateManifest |
| `-OsVersion`                 | Server2016 / Server2019 / Server2022 / Server2025                               |
| `-OsLanguage`                | en-us / ja-jp                                                                   |
| `-IsoPath`                   | ローカル ISO のパス (`-IsoUrl` と相互排他)                                      |
| `-IsoUrl`                    | ISO の明示的ダウンロード URL                                                    |
| `-PatchDirectory`            | ローカル MSU/CAB パッチが入ったディレクトリ                                     |
| `-ManifestPath`              | ハッシュ付き Metalink `.meta4` マニフェスト                                     |
| `-PatchUrls`                 | パッチ URL の明示的な配列                                                       |
| `-AutoDetectLatestPatches`   | Microsoft Update Catalog から PatchBaseline を強制再取得                        |
| `-PatchMonth`                | 再取得対象月 (例: `2026-06`、既定は現在月)                                      |
| `-SkipDynamicPatchRefresh`   | PatchBaseline が古くても P03 をスキップ (オフライン・閉域網用)                |
| `-UseBaselineOnly`           | PatchBaseline を厳密にそのまま使う (Catalog アクセス一切なし)                   |
| `-IgnorePatchValidation`     | P06 検証失敗を警告に降格 (推奨されない)                                       |
| `-WsusScnCabPath`            | 事前配置済み wsusscn2.cab のパス (自動ダウンロードを省略)                       |
| `-WorkRoot`                  | ワークスペースルート。既定はスクリプトディレクトリからの相対パス `Workspace_UpdateWsi`(スクリプトの隣にワークスペースが作成される)。別ドライブに置きたい場合は絶対パスを指定(例 `D:\UpdateWsi`)。このパスのドライブに 100 GB 以上の空き容量が必要(プリフライトで強制) |
| `-OutputDir`                 | 出力 ISO ディレクトリ (既定 `<WorkRoot>\output`)                                |
| `-OnlyInstallWimIndexes`     | カンマ区切りインデックス (例 `'2,4'`) で install.wim 更新対象を制限             |
| `-DryRun`                    | Build / Verify をスキップ (Setup / Fetch / Plan のみ)                           |
| `-SyntheticTestMode`         | CI モード: Microsoft アセットに触れずに合成 ISO を構築                          |
| `-EvalIsoMode`               | Microsoft Evaluation Center fwlink 経由のダウンロードを許可                     |
| `-Execute`                   | 実際の DISM 書き込みに **必須**。指定しなければ Build フェーズは計画のみ        |

## 動的パッチベースライン (P03) と依存性検証 (P06)

これら 2 つのフェーズは、運用者によるパッチ手動キュレーション工数を
最小化し、不完全なパッチセットによる ISO 破損を未然に防ぐために
導入されました。

### 動作フロー

```
P02   ResolveInputs
        - Config/<OsKey>.json を読み込み
        - PatchBaseline.PatchTuesdayOfBaseline を取得
        - Get-LatestPatchTuesday と比較
P03 RefreshPatchBaseline (古い場合 OR -AutoDetectLatestPatches 指定時)
        - 対象月の Microsoft Update Catalog をスクレイピング
        - SSU + LCU + DynamicUpdate(.Setup/.Component/.SafeOs) + .NET CU
          をタイトルトークンヒューリスティクスで識別
        - ScopedViewInline.aspx を取得して Supersedes / SupersededBy 取得
        - PatchBaseline.Patches を Config JSON に原子的に書き戻し
        - LCU.RequiresKbIds に SSU の KB 番号を自動設定
P04   FetchAssets (新しい URL / SHA-256 でダウンロード)
P05   ExpandIso
P06 ValidatePatchSet
        - 以下の条件で <WorkRoot>/cache/ に wsusscn2.cab をダウンロード:
            * 初回 (キャッシュなし)
            * Patch Tuesday 以降の実行で、キャッシュが Patch Tuesday より古い
        - Microsoft.Update.Session COM API でオフラインスキャン
        - WUA が要求するパッチ vs 提供されたパッチを照合
        - 必要パッチが不足していた場合、4 つの診断ファイルを
          <WorkRoot>/diag/<timestamp>/ に出力して ABORT
P07+  Build / Verify / Report (従来通り)
```

### 検証失敗時の診断データ

P06 で必要パッチの不足が検出された場合、4 つのファイルが
`<WorkRoot>/diag/<yyyy-MM-dd_HH-mm-ss>/` に出力されてスクリプトが
終了します。

| ファイル | 内容 |
|---|---|
| `validation_summary.json` | サマリ。対象 OS / wsusscn2 メタ / 提供パッチ一覧 / WUA 検出の不足パッチ一覧 |
| `validation_detail.csv` | パッチ1行毎: KbId / Title / RequiredByWUA / Severity / ApplyOrder / DownloadHint |
| `wsusscn2_scan_raw.json` | WUA スキャンの完全な生出力(調査用) |
| `dependency_graph.json` | 隣接リスト形式: Requires + Supersedes エッジ |

`-IgnorePatchValidation` を指定すると abort が警告降格されますが、
診断データは同様に出力されます (開発時のみ推奨)。

### 自動更新ポリシー

```jsonc
"AutoRefreshPolicy": {
  "Mode": "OnNewPatchTuesday",                // 古い場合に再取得
  "WritebackToConfig": true,                  // Config/<OsKey>.json を上書き
  "FallbackOnScrapeFailure": "UseBaseline",   // または "Abort"
  "ScrapeRetries": 3
}
```

| シナリオ | 動作 |
|---|---|
| Baseline が新しい (Patch Tuesday 以後に検証済) | P03 は no-op |
| Baseline が古い + スクレイプ成功 | Config 更新 + 新パッチセットを使用 |
| Baseline が古い + スクレイプ失敗 + 既存 baseline が利用可能 | 警告 + 既存 baseline で続行 |
| Baseline が古い + スクレイプ失敗 + baseline が空 | ABORT |
| `-UseBaselineOnly` 指定 | P03 を無条件スキップ (オフラインモード) |
| `-SyntheticTestMode` 指定 | P03 / P06 とも無条件スキップ (CI モード) |

## 静的解析

プロジェクトディレクトリから実行します:

```bash
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

コミット前の必須ゲートは **0 errors / 0 warnings / 0 info** です。
現在の `r01` ベースラインはこれを満たしています。

## 自己検証ツール

`tests/` サブディレクトリには、本スクリプト専用の 5 つの Python
ベース自己検証ツール(T1〜T5)を同梱しています。Microsoft 側
コンテンツの仕様変化を検出し、PowerShell 関数を Python から単体
テストすることが目的です。**本サブプロジェクト専用**であり、汎用
ツールではありません。依存関係は Python 標準ライブラリのみ
(`pip install` 不要)。

```bash
# オフラインテスト - どの環境でも実行可能
python3 tests/catalog_fixture_test.py    # T2: 13 件のフィクスチャ検証
python3 tests/powershell_harness.py      # T3: 7 件の PS 関数検証

# ライブテスト - ネットワーク egress が必要
python3 tests/catalog_probe.py --check all   # T1: Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4: Server<N> 評価版 ISO CDN
python3 tests/wsusscn2_probe.py              # T5: wsusscn2.cab 鮮度
```

詳細な使い方は [`tests/README.md`](./tests/README.md) を参照。
r04.3 で発覚した 3 件のライブ実機テストバグ(いずれも Microsoft 側
の暗黙の仕様変化が原因で、純粋な静的解析では検出不可能)を受けて
r04.4 で追加されました。

## 継続的インテグレーション

4 つの GitHub Actions ワークフローが、本スクリプトの検証と保守を担当します:

| ワークフローファイル | 実行内容 | トリガー |
|---|---|---|
| `scripts__powershell__update-windows-server-iso__stage1__linux.yml` | psa.py + PSScriptAnalyzer (Linux 上の pwsh 7) | push, PR |
| `scripts__powershell__update-windows-server-iso__stage2__windows.yml` | PSScriptAnalyzer (Windows PS 5.1) + パース + 読み取り専用スモーク | push, PR |
| `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml` | ADK インストール + `-SyntheticTestMode` フルパイプライン | `main` への push, 手動 |
| `scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml` | `-Action RefreshAllBaselines` を実行し、`Config/Server*.json` に差分があれば自動 PR を作成 | cron `0 2 15 * *`(毎月)、手動 |

これらのワークフローはリポジトリ直下の
[`.github/workflows/`](../../../.github/workflows/) にあります。
ワークフロー単位の変更履歴は本プロジェクトの
[`CHANGELOG.md`](./CHANGELOG.md) に記録します (ルート
[`SPEC.md`](../../../SPEC.md) §9 で定められたリポジトリ全体の方針に従う)。

Stage 4 (monthly-refresh) は `workflow_dispatch` で 4 つの入力(`mode`、`onlyOs`、`onlyLanguage`、`dryRun`)を受け付けるため、メンテナはワークフローを編集せずに任意のタイミングでスコープを限定した更新を実行できます。作成される PR は `add-paths` により `Config/*.json` のみに限定されており、他のファイルへの意図しない変更を防ぎます。

**重要**: Stage 3 は ISO アーティファクトをアップロードしません。
評価版ライセンスは Microsoft バイナリの公的再配布を禁じているためです。

## トラブルシューティング

| 現象 | 原因 | 対処 |
|---|---|---|
| `Administrator privilege required` | 非昇格セッションでの実行 | PowerShell を管理者として再起動 |
| `oscdimg.exe not found` | Windows ADK Deployment Tools が未インストール | ADK の Deployment Tools 機能をインストール |
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` ドライブの空きが 100 GB 未満 | より大きなボリュームに `-WorkRoot` を変更、または不要ファイルを削除して空きを確保。100 GB は 1 OS 分の PrepareBuildVerify を最後まで実行できる最小値 |
| `Workspace preflight failed: ... required Config file(s) missing` | `Config/Server<N>.json` が欠落・改名されている、またはスクリプト移動時に `Config/` がコピーされなかった | `Update-WindowsServerIso.ps1` の隣に `Config/` ディレクトリを復元。`Server2016.json` / `Server2019.json` / `Server2022.json` / `Server2025.json` の 4 ファイルすべてが必須 |
| `Catalogue: no narrowed result for ... / Server2022`(他 OS でも発生し得る)、`Resolved 0 patch entries` | Microsoft Update Catalog のタイトル表記が変わった(カンマ削除など句読点ドリフト) | `Get-CatalogQueryTemplate` と `Get-LanguagePackQueryTemplate.osTitleTokens` の該当 `TitleTokens` 配列に新表記を追加。SPEC §D.19 参照 |
| RefreshAllBaselines 後の `NeutralPatches[]` の `Type` が誤っている | `Convert-CatalogPatchToBaselineEntry` の新規呼び出し元が `-KnownType` を渡していない | Catalog 検索コンテキストから `-KnownType $q.Type` を渡す。SPEC §D.20 参照 |
| .NET CU ベースラインエントリのサブファイルが欠落しているように見える | 複数 .msu を持つアンブレラ KB で 1 つしか保持されていない | `Resolve-PatchSetFromCatalog` で `Type='DotNet'` を `Select-AllCanonicalPatchFiles` 経由にしているか確認。SPEC §D.21 参照 |
| `0x800f081e` の Warning 行 | 該当 SKU に適用できないパッチ | クロス SKU パッチセットでは想定内、無視で OK |
| 古い WIM マウントが残存 | 前回実行が異常終了 | `dism /Get-MountedImageInfo` 確認後、`dism /Cleanup-Mountpoints` |
| ISO SHA-256 不一致 | Microsoft がスナップショット URL を更新 | `Config/<OsKey>.json` の `IsoSha256` を新しい値に更新 |

## 謝辞

- DISM のマウント + ディスマウントリトライパターン (10 秒 + 30 秒) は
  [OSDBuilder](https://github.com/OSDeploy/OSDBuilder) (David Segura 氏
  作) の `Dismount-InstallwimOS` ヘルパーから借用しています。
- 0x800f081e の Warning 降格ヒューリスティクスも OSDBuilder 由来です。
- `etfsboot.com` / `efisys.bin` の 3 段階フォールバックは
  [Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN)
  に着想を得ています。
- デバッグトレース機構、ログ規約、環境チェック cmdlet、リトライ
  プリミティブは、同じリポジトリ内の同種スクリプトである
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1)
  から逐語コピーで取り込んでいます。
- Server 2022 用の canonical な SHA-256 は
  [rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper)
  から取得しました。

本スクリプトは Anthropic Claude (Opus 4.7 系統、ベースラインリビジョン
r01 / 2026-05-24) を用いて生成し、段階的にリファインしました。
