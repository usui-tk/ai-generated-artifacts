---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 + smoke test) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Synthetic full pipeline (Windows + ADK) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage3__synthetic.yml) |
| STAGE 4 — Monthly baseline refresh (cron) | [![STAGE 4](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage4__monthly-refresh.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/projects__powershell-update-windows-server-iso__stage4__monthly-refresh.yml) |

[English](README.md) | **日本語**

Microsoft の最新の Servicing Stack Update、Latest Cumulative Update、
Dynamic Update、および .NET Framework cumulative update を Windows Server
評価版 ISO に統合し、`install.wim` / `boot.wim` / `winre.wim` に各更新が
適用済みの起動可能 ISO を再構築します。Windows 11 / Windows Server 2016+
ホスト上の Windows PowerShell 5.1（PowerShell 7+ でも動作）を対象としています。

本スクリプトは
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
リポジトリ配下の `projects/powershell-update-windows-server-iso/` に格納されています。

## なぜこのスクリプトが必要か

Windows Update は稼働中サーバーを最新状態に保つ標準的な手段ですが、
**同一のパッチ適用済み OS イメージを多数のマシンに、繰り返し、予測可能に、
高速に展開する場合には不適切なツール** です。本スクリプトは、Windows Update
だけでは解決しづらい以下 4 つの運用シナリオを対象としています。

- **ラボ／テスト環境の大規模展開**：陳腐化した評価版 ISO から複数の Server VM
  を立て、各 VM で Windows Update を走らせると、VM 1 台あたり数時間を要します。
  パッチ適用済み ISO を一度作って使い回せば、VM 単位のパッチ適用時間はゼロに
  なります。
- **PCA2011 boot manager 証明書失効（2026-06）**：Server 2016 / 2019 / 2022
  の評価版 ISO の boot manager に署名している Microsoft Windows Production
  PCA 2011 証明書は 2026-06 に失効します。BlackLotus CVE-2023-24932 緩和策の
  展開で 2011 証明書を失効済みのファームウェアは、boot manager が 2011 系の
  ままの ISO の起動を拒否します。本スクリプトの P10 フェーズは boot manager を
  **'Windows UEFI CA 2023'** 系で再署名し、失効済みファームウェアの
  ハードウェアで起動できる ISO を生成します。
- **エアギャップ／オフラインラボ**：インターネット出口を持たないラボ
  ネットワークでは Windows Update を利用できません。本スクリプトは事前配置済みの
  MSU / CAB ファイルを `<WorkRoot>/patches/<OsVersion>/` で受け入れます
  —— LCU とチェックポイント MSU は `cu/` サブフォルダ
  （`<WorkRoot>/patches/<OsVersion>/cu/`）、それ以外はフラット配置です
  （P04 は検証済みファイルをスキップ）。これによりビルド全体を
  オフラインで実行できます。
- **再現可能なパッチベースライン**：コンプライアンスやフォレンジック再現
  シナリオでは「この ISO にビルド時点で何が含まれていたか」の監査記録が
  必要です。Config ベースライン（`data/config-Server*.json`）と CHANGELOG が
  併せて監査証跡を提供します。

### 想定する利用者と、対象外

| 適している場合：| 対象外：|
|:---|:---|
| インフラエンジニアによるラボ／プレ本番 Windows Server 群の構築 | 本番のパッチ管理（WSUS、Microsoft Update、Azure Update Manager を使用）|
| 再現可能な評価版 ISO 成果物を必要とするクラウドコンサルタント | Hotpatch によるメモリパッチ（Azure Edition SKU 限定）|
| 失効済みファームウェア機器に対する PCA2023 readiness 検証 | クライアント SKU（Windows 10 / 11）—対象外 |
| 過去パッチベースラインのフォレンジック再現（`-PatchMonth`）| ARM64（現在は x64 のみ）|
| Patch Tuesday 前のドライラン（`-Action Prepare`）| ドライバー／FOD／LXP／Appx のカスタマイズ |

### 読者向けナビゲーション

- スクリプトを **動かしたい** だけなら本 README で十分です。
- スクリプトを **拡張する／類似スクリプトを作る** 場合は、
  [`SPEC.md`](./SPEC.md)（開発者・LLM 向け仕様書）も併読してください。
- **検証手順と実行結果** は [`TESTING.md`](./TESTING.md) を参照してください。
- **リビジョン単位の変更履歴** は [`CHANGELOG.md`](./CHANGELOG.md) を参照してください。
- **リポジトリ全体に共通する LLM エージェント運用ガイド**(ガバナンス階層、ground truth 抽出、Doc-Touching マトリクス、Part A 継承ルール、アンチパターン)は、リポジトリルートの [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) を参照してください。
- **リポジトリ全体に共通する** 言語ポリシー、ファイル形式ポリシー、免責事項、
  貢献ルールは、ルートの [`README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)、
  [`CONTRIBUTING.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/CONTRIBUTING.md)、
  [`SECURITY.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SECURITY.md) に集約されています。

## ⚠️ 免責事項

**自己責任でご利用ください。** 本スクリプトは「現状有姿」で提供され、
明示・黙示を問わずいかなる種類の保証もありません。著者および貢献者は、
本スクリプトの利用、改変、再配布から直接的・間接的に生じる損害、
データ損失、システム破損、アカウント停止、ネットワーク障害、ディスク
容量枯渇、その他いかなる問題についても責任を負いません。

本スクリプトを実行することにより、利用者は以下を承諾するものとします。

- Microsoft Evaluation Center のライセンス条項、および適用される法令への
  準拠を検証する責任は利用者自身にあります。Microsoft の Server 評価版
  ISO は期間限定であり、評価目的での使用に限ってライセンスされています。
- WIM イメージに対する DISM 操作の結果に責任を負います（マウント失敗で
  古い mount-cache 状態が残る、不完全な更新で起動不可能な ISO が生成される、
  PCA2023 変換で 2023 証明書を信頼しないファームウェアでは起動不可能になる、等）。
- 知的財産権を尊重します。ダウンロードされる Microsoft バイナリ
  （ISO、MSU、CAB、.NET CU）の所有権は Microsoft 社に帰属し、再配布は
  許可されていません。
- 任意の環境で実行する前に、スクリプトのソースコードを確認します。
  **特に、本番データを保持するボリュームをもつホストでは決して
  `-Execute` を実行しないでください**。DISM マウント操作は異常終了時に
  マウントポイントを破損させる可能性があります。
- 生成された ISO を評価版ライセンスの範囲内で保持します。パッチ適用済み
  評価版 ISO を公衆向けに再配布することは Microsoft ライセンス違反です。

本リポジトリ全アーティファクトに適用される完全な免責条項と自己責任条件は、
[ルート README](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)
（[英語版](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)）を参照してください。

## ライセンス

本プロジェクトは `usui-tk/ai-generated-artifacts` リポジトリの一部であり、
**MIT License** のもとでライセンスされています。完全なライセンス本文は、
リポジトリルートの [`LICENSE`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE) ファイルを参照してください。

要約すると：利用者は原著作権表示とライセンス表示の保持を条件として、
本ソフトウェアを任意の目的で使用・改変・再配布する自由を持ちます。
ソフトウェアは無保証で提供されます（上記の免責事項と LICENSE ファイルを
参照）。スクリプトがダウンロードする Microsoft バイナリ（ISO / MSU / CAB）は
Microsoft 社固有のライセンスのもとに置かれ、本プロジェクトでは再配布
されません。

## ディレクトリ構成

```
projects/powershell-update-windows-server-iso/
├── Update-WindowsServerIso.ps1     # メインスクリプト
├── README.md / README.ja.md         # 利用者向けドキュメント（本ファイル）
├── SPEC.md (English only)            # 開発者・LLM 向け仕様書
├── TESTING.md (English only)         # 検証手順
├── CHANGELOG.md (English only)       # リビジョン単位の変更履歴
├── .psa.config.json                  # psa.py プロジェクト設定
├── PSScriptAnalyzerSettings.psd1     # PSScriptAnalyzer プロジェクト設定
├── data/                             # 永続的な入力データ（コミット対象、flat 配置）
│   ├── config-Server{2016,2019,2022,2025}.json
│   ├── raw-release-info.md (+ .meta.json)
│   ├── raw-dotnet-cu.json
│   ├── cache-release-info.json
│   └── cache-dotnet-cu.json
├── tests/                            # 自己検証スイート（疎番号 T1-T31 + ゲート）
└── docs/history/                     # サイクル別の調査レポート
```

本スクリプトの検証に使用する PowerShell 静的解析ツール（`psa.py`）は、
リポジトリ全体の正規配置場所に格納されています：
[`quality-tools/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/quality-tools/powershell-static-analyzer/)

## クイックスタート

```powershell
# 1. ファイルのブロック解除と、このプロセスでのローカルスクリプト許可
Unblock-File .\Update-WindowsServerIso.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 2. 読み取り専用の確認（書き込みなし）
.\Update-WindowsServerIso.ps1 -Action ListPhases
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly
```

### テンプレート（プレースホルダーを埋める）

OS ごとに `-WorkRoot` を分け、同時実行や再実行で DISM マウントキャッシュを
共有しないようにします。ログは自動でタイムスタンプを付け、各実行を個別
ファイルにします（日付の手入力は不要）。`data/` に同梱されたパッチベース
ラインを使う前提では、スクリプトが OS プロファイルからソース ISO のダウン
ロード URL を解決し、パッチ一式も配布ベースラインから取得するため、
**`-IsoPath` やパッチ系パラメータは不要**です。`-UseBaselineOnly` を付けると
同梱ベースラインに固定され、Catalog / release-info の公開タイミングに依存
しません。

```powershell
$OsVersion  = 'Server2019'                       # Server2016/2019/2022/2025
$OsLanguage = 'ja-jp'                             # en-us / ja-jp
$WorkRoot   = "D:\UpdateWsi-$OsVersion"           # OS ごとのワークスペース
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $WorkRoot ('logs\{0}-{1}-{2}.log' -f 'PrepareBuildVerify', $OsVersion, $stamp)

# まずドライラン（Setup / Fetch / Plan のみ。DISM 書き込みなし）
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -WorkRoot $WorkRoot -LogFile $LogFile `
    -UseBaselineOnly

# 実ビルド — -Execute を追加（WIM をマウント・変更する唯一のモード）
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion $OsVersion -OsLanguage $OsLanguage `
    -WorkRoot $WorkRoot -LogFile $LogFile `
    -UseBaselineOnly `
    -Execute
```

### 実例：Server 2016 と Server 2025

P10（PCA2023 ブートマネージャ変換）は現在、既定で（readiness 駆動により）
実行されるため、Server 2016 には PCA2023 関連スイッチが一切不要です。
Server 2025 は例外で、`-ForcePca2023OnServer2025` を指定しない限り P10 を
スキップします（認証済み 2025 プラットフォームはファームウェアに 2023
証明書を同梱）。出荷時の PCA2011 署名 boot manager を維持したい場合は、
どの OS でも `-SkipPca2023BootManager` でオプトアウトできます。

```powershell
# Server 2016（PCA2023 スイッチなし）
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2016 -OsLanguage ja-jp `
    -WorkRoot 'D:\UpdateWsi-Server2016' `
    -LogFile ('D:\UpdateWsi-Server2016\logs\build-2016-{0}.log' -f $stamp) `
    -UseBaselineOnly `
    -Execute

# Server 2025（2025 固有の P10 スキップを上書き）
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2025 -OsLanguage ja-jp `
    -WorkRoot 'D:\UpdateWsi-Server2025' `
    -LogFile ('D:\UpdateWsi-Server2025\logs\build-2025-{0}.log' -f $stamp) `
    -ForcePca2023OnServer2025 `
    -UseBaselineOnly `
    -Execute
```

`-Execute` なしでは Build フェーズは計画のみで DISM 書き込みを確定しません。
これは [SPEC.md](./SPEC.md) §D.12 に記載の **既定サンドボックス** の姿勢です。


## アクション一覧（14 アクション）

スクリプトの `param() ValidateSet` は 14 個のアクションを宣言しています。
用途別にグループ化すると次のとおりです。デフォルトは `PrepareBuildVerify`。

### 標準パイプラインアクション

| Action | 実行フェーズ | 説明 |
|:---|:---|:---|
| `Prepare` | P01-P06 | ステージングのみ（パッチ適用なし、DISM マウントなし）|
| `Build` | P07-P10 | パッチ適用とアセンブル（Prepare で作業領域が準備済みであることを前提）|
| `Verify` | P11-P13 | 既存の出力 ISO を検証（先行する Build -Execute による生成を前提）|
| `PrepareBuildVerify`（デフォルト）| P01-P13 | フルパイプライン |
| `All` | P01-P13 + extras | フルパイプライン + 追加処理 |

### 特殊アクション

| Action | 説明 |
|:---|:---|
| `BootTest` | 出力 ISO に対する Hyper-V Gen2 セキュアブート起動スモークテスト。コンソールのスクリーンショットを保存しオペレータが合否判定（`-SyntheticTestMode` と排他。失効ファームウェアを含む本格マトリクスは `tools/boot-verification/` 参照）|
| `GenerateManifest` | 解決済みパッチのマニフェストを算出（P01-P03 のみ）|
| `Cleanup` | ワークスペースと残留 DISM マウントの清掃 |
| `ListPhases` | フェーズとアクションのレジストリを JSON で出力 |
| `TestHarness` | `tests/powershell_harness.py`（T3）が利用する PS 関数評価 REPL モード。人間からは呼び出さない |

### Admin アクション（Config ベースライン管理）

`data/config-<OsKey>.json` ファイル群がスクリプトの利用するベースラインデータを
保持します。5 つの Admin Action により、ISO に触れずにこのデータを更新・点検
できます。**更新は 2 段階** で行います：`RefreshSnapshots` が Microsoft Learn と
Microsoft Update Catalog から上流の `data/raw-*` / `data/cache-*` を取得し、
`RefreshAllBaselines` が各 `data/config-Server*.json` の
`PatchBaseline.Lines[]` をそれらキャッシュから再生成します。この分離は
SPEC §B.22.1 の Refresher アーキテクチャに対応します。`RebuildDataset`（A00）は、コミット済みの `data/seed/seed-Server*.json` からデータセット全体を一括で再構築します（シード検証 -> `RefreshSnapshots` -> 各 config をシードから構築 -> `RefreshAllBaselines`（Force） -> 検証）。空の状態からでも実行できます。

| Action | Admin Phase | 説明 |
|:---|:-:|:---|
| `RebuildDataset` | A00 | シード + キャッシュから `data/config-Server*.json` を全体再構築（空の状態からも可）|
| `RefreshSnapshots` | A03 | 上流キャッシュの取得（release-info、.NET CU、Dynamic Update）|
| `RefreshAllBaselines` | A01 | キャッシュから `data/config-Server*.json` を再生成 |
| `DumpFieldClassification` | A02 | フィールドのカデンス決定マトリックスを JSON で出力 |

```powershell
# ---- コミット済みシードからの一括再構築（検証 -> snapshots -> 構築 -> fill -> 検証）----
.\Update-WindowsServerIso.ps1 -Action RebuildDataset -PatchMonth 2025-06

# ---- 第 1 段：上流キャッシュの populate ----
.\Update-WindowsServerIso.ps1 -Action RefreshSnapshots

# ---- 第 2 段：キャッシュからベースラインを再生成 ----
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines

# 初期フィル（自動 Refresher が利用可能な未検証フィールドも一緒に埋める）
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial

# 強制（状態にかかわらず全グループを再取得）
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force

# 単一 OS / 単一言語へのスコープ限定（第 2 段のみ）
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp

# フィールド分類メタデータを JSON で出力（外部バリデータが利用）
.\Update-WindowsServerIso.ps1 -Action DumpFieldClassification
```

`RefreshSnapshots` の終了コード：`0` = すべてのサブステップが OK、
非ゼロ = いずれかのサブステップが失敗。再実行は冪等。

`RefreshAllBaselines` の終了コード：`0` = すべて OK、`1` = 少なくとも 1 つの
Refresher が失敗、`2` = 手動補完が必要なフィールドあり（自動 Refresher 未定義、
典型的には新規追加された言語の `LanguageSpecific.<lang>.Iso` グループ）。

## 動作要件

| 項目：| 内容：|
|:---|:---|
| ホスト OS | Windows 10/11 Pro/Enterprise/Education または Windows Server 2016+ |
| PowerShell | Windows PowerShell 5.1+（PowerShell 7+ でも動作）、64-bit プロセス必須 |
| 権限 | Administrator（DISM マウントは管理者権限が必須）|
| Windows ADK | Deployment Tools 機能（`oscdimg.exe` を提供）。不在時に自動インストール（スイッチ不要）|
| Windows SDK Signing Tools | 埋め込み PCA2023/PCA2011 ブート署名検証用の `signtool.exe` を提供（P10/P12 readiness）。不在時に自動インストール（スイッチ不要）|
| ディスク空き容量 | `-WorkRoot` ドライブに 100 GB 以上（最低 60 GB、Workspace プリフライトが 100 GB を強制チェック）|
| ネットワーク | ISO とパッチのダウンロード用インターネットアクセス（オフライン時は `-IsoPath` + `<WorkRoot>/patches/<OsVersion>/` へのパッチ事前配置。LCU とチェックポイント MSU は `cu/` サブフォルダへ）|
| 静的解析 | `python3` + 正規配置の `psa.py`（後述「静的解析」を参照）|

## 対応 OS と言語

| OS：| 言語：| 備考：|
|:---|:---|:---|
| Server 2016 | en-us, ja-jp | PCA2023 変換には LCU 2024-4B 以降が必要 |
| Server 2019 | en-us, ja-jp | PCA2023 変換には LCU 2024-4B 以降が必要 |
| Server 2022 | en-us, ja-jp | PCA2023 変換には LCU 2025-2B（build 20348.2227）以降が必要 |
| Server 2025 | en-us, ja-jp | デフォルトでは PCA2023 変換不要（ファームウェアに 2023 証明書が同梱されている）|

新規言語の追加は、該当 `data/config-Server<N>.json` の `LanguageSpecific`
配下にノードを 1 つ追加するだけで完結します（SPEC.md §B.4.5 参照）。

## フェーズ一覧

13 個のフェーズによるパイプライン：

| ID：| 名称：| グループ：| 処理内容：|
|:---|:---|:---|:---|
| P01 | Initialize | Setup | PowerShell 環境、管理者権限、ADK、ディスク、Hyper-V のチェック |
| P02 | ResolveInputs | Setup | ISO / パッチソースの解決、Config JSON のロード |
| P03 | RefreshPatchBaseline | Setup | Microsoft Update Catalogue スクレイプ、`data/config-<OsKey>.json` への書き戻し |
| P04 | FetchAssets | Fetch | ISO + パッチのダウンロード（ハッシュ検証付き）|
| P05 | ExpandIso | Plan | ソース ISO のマウント、ワークスペースへのコピー、WIM インデックスの列挙 |
| P06 | ValidatePatchServicing | Plan | PatchModel 整合チェック＋適用前の全 WIM インデックス検査（`logs/inspection_pre.json`。マウント時の準備性検証は引き続き P07/P08）|
| P07 | PatchInstallWim | Build | install.wim 各インデックスに対し SSU → LCU → .NET → DISM クリーンアップ |
| P08 | PatchBootWim | Build | boot.wim（PE + Setup）と winre.wim |
| P09 | AssembleIso | Build | Dynamic Update Setup オーバーレイ、Export-WindowsImage、oscdimg による ISO ビルド |
| P10 | ConvertPca2023BootManager | Build | **既定で実行**（readiness 駆動）の PCA2023 Secure Boot 変換（オプトアウト：`-SkipPca2023BootManager`。Server 2025 のみ追加で `-ForcePca2023OnServer2025` が必要）|
| P11 | StaticVerify | Verify | 出力 ISO をマウントし、展開ツリーとの SHA-256 内容同一性を検証。適用後の全インデックス検査（`logs/inspection_post.json`）から種別ごとに実測検証（到達ビルド、.NET ロールアップ実在確認。KB 名照合は Server 2016 のみ）|
| P12 | VerifyPca2023Readiness | Verify | **常時実行** — `pca2023_readiness.json` + `.md` を出力 |
| P13 | FinalReport | Report | 実行終了サマリ、ISO ハッシュ、ログパス。適用前後の検査差分と、宣言値と実測値の突き合わせ（observe-first）|

各フェーズの詳細契約は [SPEC.md](./SPEC.md) Part B を参照してください。

### Secure Boot / PCA2023 boot manager（r05.0+）

Microsoft の「Windows Production PCA 2011」Secure Boot 署名証明書は
**2026-06** に失効します。2011 証明書を失効済みに更新したファームウェアは、
2011 系で署名された boot manager をもつ ISO の起動を拒否します。P10 / P12 が
この問題に対処します。詳細な運用モデル（OS 別デフォルト、
`-ForcePca2023OnServer2025` を設定するタイミング、`-Pca2023OnlyMode` による
スタンドアロンのフォレンジック検査）は SPEC.md §B.17 と §B.18 を参照してください。

代表的な運用判断：

- **Server 2016 / 2019 / 2022**：P10 は自動で実行されます（PCA2011 署名 CA は
  2026-06 に失効済みで、変換が標準の姿になったため）。事前 readiness
  スナップショットが引き続きゲートします：Critical（LCU 前提未達）は警告付き
  スキップ、Healthy（署名済み）は no-op。ソース ISO の `install.wim` の LCU 月
  は 2024-4B（2024 年 4 月）以降が必要（Server 2022 は Lenovo lp2353.pdf に
  従い、2025-2B が必要）。旧ファームウェア向けに出荷時の PCA2011 署名 boot
  manager を維持する場合は `-SkipPca2023BootManager` を指定。
- **Server 2025**：この OS のみ P10 は引き続きデフォルトでスキップ
  （Microsoft 認証済み Server 2025 プラットフォームはファームウェアに 2023
  証明書を同梱、KB5053484 は Server 2025 を手順対象としていない）。PCA2023
  変換が必要な非認証ハードウェアで運用する場合のみ
  `-ForcePca2023OnServer2025` で上書き。
- **既存 ISO のフォレンジック検査**：`-Pca2023OnlyMode -IsoPath <existing.iso>`
  で全ビルドパイプラインをスキップし、P12 のみを ISO に対して実行。

完全な設計と検証詳細は SPEC.md §B.17（PCA2023 boot manager サポート）と
§B.18（出力 ISO 検証）を参照してください。

## パラメーター（全件）

全 34 パラメーターを用途別にまとめます。この表はドキュメント時点の
スナップショットです。常に最新の正規一覧は
`Get-Help .\Update-WindowsServerIso.ps1 -Full` を参照してください。

| パラメーター | 分類 | 既定値 / ValidateSet | 用途 |
|:---|:---|:---|:---|
| `-Action` | common | `PrepareBuildVerify`、14 アクションのいずれか | 実行するアクション/パイプライン |
| `-OsVersion` | common | `Server2016`/`2019`/`2022`/`2025` | 対象 OS ファミリ |
| `-OsLanguage` | common | `en-us`（または `ja-jp`）| 対象 OS 言語 |
| `-Execute` | common | switch（OFF）| 実際の DISM 書き込みに**必須**。無指定だと Build は計画のみ |
| `-WorkRoot` | common | `Workspace_UpdateWsi`（スクリプト隣）| ワークスペース。空き 100 GB 以上必要 |
| `-LogFile` | common | （なし）| 実行全体の `Start-Transcript` パス |
| `-OutputDir` | common | `<WorkRoot>\output` | 出力 ISO ディレクトリ |
| `-CleanWorkRoot` | common | switch（OFF）| 実行前にワークスペースを掃除 |
| `-IsoPath` | input | （なし）| ローカル ソース ISO パス（`-IsoUrl` と排他）|
| `-IsoUrl` | input | （なし）| ソース ISO ダウンロード URL（`-IsoPath` と排他）|
| `-OnlyPhases` | advanced | （なし）| アクション既定を上書きするフェーズ ID 配列（例 `'P04','P07'`）|
| `-OnlyInstallWimIndexes` | advanced | （なし）| install.wim 更新を限定するインデックス一覧（例 `'2,4'`）|
| `-UseDefenderExclusions` | advanced | switch（OFF）| オプトイン: 実行中だけ WorkRoot ツリー ＋ dism/DismHost/TiWorker/TrustedInstaller を Defender 除外（fail-closed・LCU 適用が約 35% 高速化）|
| `-SkipResetBaseOnCleanup` | advanced | switch（OFF）| クリーンアップで DISM `/ResetBase` を省略し、`/StartComponentCleanup` のみ実施（置換済みコンポーネントストアを reset 可能なまま保持）|
| `-SkipExportCompress` | advanced | switch（OFF）| `Export-Image /Compress:max` を省略（ビルド高速・`install.wim` は大容量）|
| `-AutoDetectLatestPatches` | patch | switch（OFF）| Catalog から P03 PatchBaseline 更新を強制 |
| `-PatchMonth` | patch | 当月 | 更新対象パッチ月（例 `2026-06`）|
| `-SkipDynamicPatchRefresh` | patch | switch（OFF）| ベースライン陳腐でも P03 をスキップ（オフライン）|
| `-UseBaselineOnly` | patch | switch（OFF）| PatchBaseline をそのまま使用。Catalog アクセスなし |
| `-SkipPca2023BootManager` | secure-boot | switch（OFF）| 既定で実行される P10 PCA2023 ブートマネージャ変換をオプトアウト（出荷時の PCA2011 署名 boot manager を維持）|
| `-ForcePca2023OnServer2025` | secure-boot | switch（OFF）| Server 2025 の P10 既定スキップを上書き |
| `-Pca2023OnlyMode` | secure-boot | switch（OFF）| 既存 ISO の P12 単独検査（`-IsoPath` 必須）|
| `-Pca2023ScriptPath` | secure-boot | （なし）| 内部ヘルパーの代わりに外部 `Make2023BootableMedia.ps1` を使用 |
| `-Mode` | admin | `Monthly`（または `Initial`/`Force`）| `RefreshAllBaselines` の更新モード |
| `-OnlyOs` | admin | `Server2016`/`2019`/`2022`/`2025` | `RefreshAllBaselines` を 1 OS に限定 |
| `-OnlyLanguage` | admin | `en-us`/`ja-jp` | `RefreshAllBaselines` を 1 言語に限定 |
| `-DryRun` | test | switch（OFF）| Setup/Fetch/Plan のみ。Build/Verify をスキップ |
| `-SyntheticTestMode` | test | switch（OFF）| CI モード：合成 ISO、Microsoft アセット不使用 |
| `-SkipEnvCheck` | test | switch（OFF）| 環境プリフライトをスキップ（`-EnvironmentInfoOnly` と排他）|
| `-EnvironmentInfoOnly` | test | switch（OFF）| 環境情報を表示して終了（`-SkipEnvCheck` と排他）|

### 排他的指定ルール

スクリプトは次の排他制約を強制します。

- `-IsoUrl` / `-IsoPath`
- `-EnvironmentInfoOnly` / `-SkipEnvCheck`
- `-Action BootTest` / `-SyntheticTestMode`
- `-SkipDynamicPatchRefresh` / `-AutoDetectLatestPatches`
- `-UseBaselineOnly` / `-AutoDetectLatestPatches`

`-PatchMonth` は `YYYY-MM` 形式（例 `2026-06`）である必要があります。


## 動的パッチベースライン（P03）と依存性検証（P06）

この 2 フェーズが、手動でのパッチ管理を最小化し、不完全なパッチセットによる
壊れた ISO の生成を防止します。

### 動作概要

```
P02   ResolveInputs
        - data/config-<OsKey>.json をロード
        - PatchBaseline.PatchTuesdayOfBaseline を読み取り
        - Get-LatestPatchTuesday と比較
P03 RefreshPatchBaseline（ベースラインが古いとき、または -AutoDetectLatestPatches 指定時）
        - Microsoft Update Catalogue を対象月でスクレイプ
        - Config 駆動の title-token 絞り込みで SSU + LCU + DynamicUpdate(.Setup/.Component/.SafeOs)
          + .NET CU を識別
        - ScopedViewInline.aspx を取得して Supersedes / SupersededBy を確認
        - PatchBaseline.Lines を Config JSON にアトミックに書き戻し
P04   FetchAssets（新しく解決された URL と SHA-256 を使用）
P05   ExpandIso
P06 ValidatePatchServicing
        - PatchModel 別整合チェック（Test-PatchModelConsistency）を実行します。
          これが置き換えた wsusscn2 の Layer 2 グラフゲートは
          データソース移行で削除されました（SPEC.md §B.19）。
        - 実際のサービシング準備性はビルド中にマウント済み WIM 上で
          Test-PatchServicingReadinessOnMount が検証します（SPEC.md §B.13、P07/P08）。
        - 旧来のライブ Windows Update Agent オフラインスキャンは削除
          （ホスト相対で、クロス OS ビルドで偽陰性を生じたため）。
P07+  Build / Verify / Report
```

### 診断データとログ

実行のトラブルシューティングでは、次のファイルを確認します。

| ファイル | タイミング | 内容 |
|:---|:---|:---|
| `<LogFile>` | `-LogFile <path>` 指定時 | 実行全体の `Start-Transcript`（全コンソール行）|
| `<WorkRoot>/logs/debugtrace.jsonl` | 常時（フェーズがトレースを使う場合）| 失敗ステップを特定するステップ単位の JSONL トレース |

### 更新ポリシー

```jsonc
"AutoRefreshPolicy": {
  "Mode": "OnNewPatchTuesday",       // 古いときに更新
  "WritebackToConfig": true,          // data/config-<OsKey>.json を上書き
  "FallbackOnScrapeFailure": "UseBaseline",   // または "Abort"
  "ScrapeRetries": 3
}
```

| シナリオ：| 挙動：|
|:---|:---|
| ベースライン新鮮（前回検証から Patch Tuesday が更新されていない）| P03 は no-op |
| ベースライン陳腐、スクレイプ成功 | Config を更新し新しいパッチを使用 |
| ベースライン陳腐、スクレイプ失敗、既存ベースライン使用可能 | 警告 + 既存ベースラインで継続 |
| ベースライン陳腐、スクレイプ失敗、ベースラインが空または使用不可 | 中断 |
| `-UseBaselineOnly` 指定 | P03 を無条件でスキップ（オフラインモード）|
| `-SyntheticTestMode` 指定 | P03 と P06 を両方スキップ（CI モード）|

完全な決定マトリックスは SPEC.md §B.14 を参照してください。

## 静的解析

プロジェクトディレクトリから次のように実行します。

```bash
python3 ../../python/powershell-static-analyzer/psa.py Update-WindowsServerIso.ps1
```

コミット前の必須ゲートは **0 errors / 0 warnings / 0 info** です。現行ビルドは
この条件を満たしています。最終確認状況は TESTING.md §0 を参照してください。

## 自己検証ツール

`tests/` サブディレクトリには 17 個の Python 自己検証ツール（疎番号
T1 – T31。退役したツールの番号は再利用しません）に加え、
フォーマット／スキーマ／シードの 3 ゲートが同梱されています。これらは
スクリプトの外部依存をプローブし、PowerShell 関数をユニットテストし、
さらに SPEC §B.23 の JSON canonical 形式を強制します。オフラインツールは
Python 標準ライブラリのみを利用するため、`pip install` は不要です。

```bash
# オフラインテスト — どこでも安全に実行可能
python3 tests/catalog_fixture_test.py        # T2：13 個の fixture アサーション
python3 tests/powershell_harness.py          # T3：7 個の PS 関数アサーション
python3 tests/release_info_parser_test.py    # T6：13 個の release-info パーサーアサーション
python3 tests/dotnet_cu_parser_test.py       # T7：16 個の .NET CU パーサーアサーション
python3 tests/canonical_json_test.py         # T11：26 個の PS/Python バイトレベル パリティアサーション

# スキーマ / フォーマットゲート（データを触るコミットごとに実行）
python3 tests/config_schema_test.py                       # config スキーマゲート
python3 tests/canonical_json_format_check.py              # JSON canonical 形式ゲート（SPEC §C.3.4）

# ライブテスト — 制限のないネットワーク出口が必要
python3 tests/catalog_probe.py --check all   # T1：Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4：Server<N> ISO CDN
```

「いつ何を実行すべきか」の正規ガイドは
[`tests/README.md`](./tests/README.md) を参照してください。完全な設計と
CI マッピングは SPEC.md §C.9 にあります。

## 継続的インテグレーション

本スクリプトの検証と維持を 4 つの GitHub Actions ワークフローが担います。

| ワークフローファイル：| 実行内容：| トリガ：|
|:---|:---|:---|
| `...__stage1__linux.yml` | psa.py + PSScriptAnalyzer（Linux 上の pwsh 7）| push、PR |
| `...__stage2__windows.yml` | PSScriptAnalyzer（Windows PS 5.1）+ パース + 読み取り専用スモーク | push、PR |
| `...__stage3__synthetic.yml` | ADK インストール + フル `-SyntheticTestMode` パイプライン | `main` への push、手動 |
| `...__stage4__monthly-refresh.yml` | `-Action RefreshAllBaselines`。`data/config-Server*.json` に差分が出たら自動 PR を起票 | cron `0 2 15 * *`（月次）、手動 |

ワークフローの実体は
[`.github/workflows/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/.github/workflows/) にあります。
各ワークフローの変更履歴は本プロジェクトの
[`CHANGELOG.md`](./CHANGELOG.md) に記録します（ルートの
[`SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md) §9 で規定されているリポジトリ規約に従う）。

Stage 4 は `workflow_dispatch` の 4 入力（`mode`、`onlyOs`、`onlyLanguage`、
`dryRun`）に対応しており、ワークフローを編集することなくアドホックな更新
実行やスコープ限定が可能です。生成される PR は `add-paths` で
`data/config-*.json` に
限定されます。

重要：Stage 3 は ISO アーティファクトを **絶対にアップロードしません**。
評価版ライセンスが Microsoft バイナリの公衆配布を禁じているため、
ワークフローの `actions/upload-artifact` の明示的な `path:` 列挙でこれを
強制します（リポジトリ SPEC.md §12（SPEC-CI-081）を参照）。

## トラブルシューティング

| 症状：| 原因：| 対処：|
|:---|:---|:---|
| `Administrator privilege required` | 非管理者ユーザーで実行 | PowerShell を管理者として再起動 |
| `oscdimg.exe not found` | Windows ADK Deployment Tools 未インストール | `oscdimg.exe` 不在時に P01 が約 50-80 MB の Deployment Tools 機能を自動インストール（スイッチ不要）。失敗した場合は [Windows ADK インストーラ](https://go.microsoft.com/fwlink/?linkid=2289980) から手動インストール（SPEC.md §B.22.13 参照）|
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` ドライブの空き容量が 100 GB 未満 | `-WorkRoot` をより大きなボリュームへ移動するか、空きを確保する（100 GB は 1 OS 分の PrepareBuildVerify エンドツーエンドに必要な最低量）|
| `Workspace preflight failed: ... required Config file(s) missing` | `data/config-Server<N>.json` ファイル群が削除またはコピー漏れ | `Update-WindowsServerIso.ps1` と同階層に `data/` ディレクトリを復元（`Server2016/2019/2022/2025.json` の 4 ファイルすべてが必須）|
| `Catalogue: no narrowed result for ... / Server2022`、`Resolved 0 patch entries` | `$script:CatOsDef` の OS Products トークンが Catalogue の Products カラムと一致しなくなった（例: Microsoft が製品名を変更）、またはパッチ未公開 | ライブ Catalogue 検索で OS Products トークンを確認。OS スコープは Title ではなく Products カラムによる（SPEC.md §B.22.2 参照）|
| RefreshAllBaselines 後に解決済みセットが OS サービシングモデルに違反 | `Lines[]` の Kind が宣言された `PatchModel` と不一致 | P06 `Test-PatchModelConsistency` が必須/禁止 Kind と共に throw します。`PatchModel` が OS と一致するか確認（SPEC.md §B.19 参照）|
| .NET CU ベースラインエントリのサブファイルが欠落しているように見える | 複数 `.msu` を持つアンブレラ KB で 1 つしか保持されなかった | b3 の `Resolve-Net` リゾルバがアンブレラ KB の全 `.msu` サブファイルを保持しているか確認（SPEC.md §D.21 参照）|
| Warning 行に `0x800f081e` が表示 | このパッチは当該 SKU には適用不能 | クロス SKU のパッチセットでは想定内、無視して問題なし（SPEC.md §D.8 参照）|
| P07 の途中で `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` | LCU が前提とする SSU がベースラインから欠落 | `separate-ssu` では P06 `PatchModel` チェック（SPEC.md §B.19）が標準の `SSU` 行を要求するため、SSU 欠落は静的に検出されます。なお欠落する場合は `PatchBaseline.Lines[]` に SSU 行を追加（SPEC.md §D.2 参照）|
| P05 の WIM インデックスバナーで文字化け（日本語が二重）| 過去の中断ランによる DISM マウントキャッシュ汚染 | **OS ファミリごとに新しい `-WorkRoot` を使用**（`D:\UpdateWsi_2016`、`D:\UpdateWsi_2019`、…）（SPEC.md §D.25 参照）|
| 古い WIM マウントが新規実行を阻害 | 過去の実行がマウント途中でクラッシュ | `dism /Get-MountedImageInfo` 実行後に `dism /Cleanup-Mountpoints` を実行（SPEC.md §D.1 参照）|
| ダウンロード後の ISO SHA-256 不一致 | Microsoft が Evaluation Center スナップショット URL を更新 | `data/config-<OsKey>.json` の `LanguageSpecific.<lang>.Iso.Sha256` を新しい値に更新（SPEC.md §D.11 参照）|

調査の広いコンテキストとしては、各サイクルの finding レポートが
[`docs/history/`](./docs/history/) に格納されており、SPEC.md Part D の
各 Pitfall エントリの背景となった issue の deep-dive ナラティブを
提供しています。

## 謝辞

- DISM マウント + アンマウントのリトライパターン（10 秒 + 30 秒）は
  [OSDBuilder](https://github.com/OSDeploy/OSDBuilder)（David Segura 氏）の
  `Dismount-InstallwimOS` ヘルパーから借用しています。
- 0x800f081e の抑制ヒューリスティックも OSDBuilder からです。
- `etfsboot.com` / `efisys.bin` の 3 段階フォールバックチェーンは、
  [Win_ISO_Patching_Scripts_zhCN](https://github.com/adavak/Win_ISO_Patching_Scripts_zhCN) からです。
- Debug Trace Facility、ロギング規約、環境チェック cmdlet、リトライ
  プリミティブは、社内コンパニオンスクリプト
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1)
  からそのまま再利用しています。
- 7-Zip ヘルパー 3 件（`Get-SevenZipPath`、`Get-LatestSevenZipUrl`、
  `Install-SevenZipFallback`）は
  `Deploy-AMDChipsetDriverOnWindowsServer.ps1` からの再利用です。
- 正規の Server 2022 SHA-256 ハッシュは
  [rgl/windows-evaluation-isos-scraper](https://github.com/rgl/windows-evaluation-isos-scraper)
  から取得しました。
- PCA2023 boot manager 変換（P10 `Convert-WimBootToPca2023Signed`）は、
  Microsoft の [`Make2023BootableMedia.ps1`](https://github.com/microsoft/secureboot_objects)
  （`v1.6.4-signed`、commit `bd7abe3`）の `Copy-2023BootBins` の PSA-clean 再実装です。
  上流互換の出力検証機能（P12 `Test-OutputIsoPca2023Readiness`）は、
  Microsoft オリジナルにはない品質向上のための拡張です。

本スクリプトは Anthropic Claude で生成・反復的に洗練されました。
