# Update-WindowsServerIso.ps1

| Stage | Status |
|:---|:---|
| STAGE 1 — Linux checks (psa.py + PSScriptAnalyzer on pwsh 7) | [![STAGE 1](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml) |
| STAGE 2 — Windows checks (PSScriptAnalyzer on Windows PS 5.1 + smoke test) | [![STAGE 2](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml) |
| STAGE 3 — Synthetic full pipeline (Windows + ADK) | [![STAGE 3](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage3__synthetic.yml) |
| STAGE 4 — Monthly baseline refresh (cron) | [![STAGE 4](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml/badge.svg?branch=main)](https://github.com/usui-tk/ai-generated-artifacts/actions/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml) |

[English](README.md) | **日本語**

Microsoft の最新の Servicing Stack Update、Latest Cumulative Update、
Dynamic Update、および .NET Framework cumulative update を Windows Server
評価版 ISO に統合し、`install.wim` / `boot.wim` / `winre.wim` に各更新が
適用済みの起動可能 ISO を再構築します。Windows 11 / Windows Server 2016+
ホスト上の Windows PowerShell 5.1（PowerShell 7+ でも動作）を対象としています。

本スクリプトは
[`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
リポジトリ配下の `scripts/powershell/update-windows-server-iso/` に格納されています。

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
  MSU / CAB ファイルを `-PatchDirectory` 経由で受け入れるため、ビルド全体を
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
| Patch Tuesday 前の `wsusscn2.cab` を用いた事前ドライラン（r09.0+）| ドライバー／FOD／LXP／Appx のカスタマイズ |

### 読者向けナビゲーション

- スクリプトを **動かしたい** だけなら本 README で十分です。
- スクリプトを **拡張する／類似スクリプトを作る** 場合は、
  [`SPEC.md`](./SPEC.md)（開発者・LLM 向け仕様書）も併読してください。
- **検証手順と実行結果** は [`TESTING.md`](./TESTING.md) を参照してください。
- **リビジョン単位の変更履歴** は [`CHANGELOG.md`](./CHANGELOG.md) を参照してください。
- **リポジトリ全体に共通する LLM エージェント運用ガイド**(ガバナンス階層、ground truth 抽出、Doc-Touching マトリクス、Part A 継承ルール、アンチパターン)は、リポジトリルートの [`AGENTS.md`](../../../AGENTS.md) を参照してください。
- **リポジトリ全体に共通する** 言語ポリシー、ファイル形式ポリシー、免責事項、
  貢献ルールは、ルートの [`README.md`](../../../README.md)、
  [`CONTRIBUTING.md`](../../../CONTRIBUTING.md)、
  [`SECURITY.md`](../../../SECURITY.md) に集約されています。

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
[ルート README](../../../README.md)
（[英語版](../../../README.md)）を参照してください。

## ライセンス

本プロジェクトは `usui-tk/ai-generated-artifacts` リポジトリの一部であり、
**MIT License** のもとでライセンスされています。完全なライセンス本文は、
リポジトリルートの [`LICENSE`](../../../LICENSE) ファイルを参照してください。

要約すると：利用者は原著作権表示とライセンス表示の保持を条件として、
本ソフトウェアを任意の目的で使用・改変・再配布する自由を持ちます。
ソフトウェアは無保証で提供されます（上記の免責事項と LICENSE ファイルを
参照）。スクリプトがダウンロードする Microsoft バイナリ（ISO / MSU / CAB）は
Microsoft 社固有のライセンスのもとに置かれ、本プロジェクトでは再配布
されません。

## ディレクトリ構成

```
scripts/powershell/update-windows-server-iso/
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
│   ├── cache-dotnet-cu.json
│   └── cache-du-Server{2022,2025}.json
├── tests/                            # 自己検証スイート（T1-T10）
└── docs/history/                     # サイクル別の調査レポート
```

本スクリプトの検証に使用する PowerShell 静的解析ツール（`psa.py`）は、
リポジトリ全体の正規配置場所に格納されています：
[`scripts/python/powershell-static-analyzer/`](../../python/powershell-static-analyzer/)

## クイックスタート

```powershell
# 1. ファイルのブロック解除（「インターネットからダウンロードした」警告の除去）
Unblock-File .\Update-WindowsServerIso.ps1

# 2. 現在のプロセスについて、署名済みまたはローカルスクリプトの実行を許可
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# 3. 登録済みフェーズの表示（読み取り専用）
.\Update-WindowsServerIso.ps1 -Action ListPhases

# 4. 環境のみのスモークチェック（P01 のみ）
.\Update-WindowsServerIso.ps1 -EnvironmentInfoOnly

# 5. Server 2019 ja-jp のサンドボックスドライラン（Setup / Fetch / Plan のみ、
#    DISM への書き込みなし）
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi'

# 6. フルローカルビルド（-Execute が必須。これだけが WIM を実際に
#    マウント・改変する唯一のモード）
.\Update-WindowsServerIso.ps1 `
    -Action PrepareBuildVerify `
    -OsVersion Server2019 -OsLanguage ja-jp `
    -IsoPath 'D:\ISO\WS2019_ja-jp.iso' `
    -PatchDirectory 'D:\Patches\Server2019\2026-05' `
    -WorkRoot 'D:\UpdateWsi' `
    -Execute
```

`-Execute` を指定しない場合、Build フェーズは計画のみ行い DISM への
書き込みをコミットしません。これは [SPEC.md](./SPEC.md) §D.12 に
記述されている **デフォルトでサンドボックス** の姿勢です。

## アクション一覧（13 アクション）

スクリプトの `param() ValidateSet` は 13 個のアクションを宣言しています。
用途別にグループ化すると次のとおりです。デフォルトは `PrepareBuildVerify`。

### 標準パイプラインアクション

| Action | 実行フェーズ | 説明 |
|:---|:---|:---|
| `Prepare` | P01-P05 | ステージングのみ（パッチ適用なし、DISM マウントなし）|
| `Build` | P01-P02 + P04-P10 | パッチ適用とアセンブル |
| `Verify` | P01-P02 + P11-P13 | 既存の出力 ISO を検証 |
| `PrepareBuildVerify`（デフォルト）| P01-P13 | フルパイプライン |
| `All` | P01-P13 + extras | フルパイプライン + 追加処理 |

### 特殊アクション

| Action | 説明 |
|:---|:---|
| `BootTest` | 出力 ISO に対する Hyper-V Gen2 起動スモークテスト（`-SyntheticTestMode` と排他）|
| `GenerateManifest` | 解決済みパッチのマニフェストを算出（P01-P03 のみ）|
| `Cleanup` | ワークスペースと残留 DISM マウントの清掃 |
| `ListPhases` | フェーズとアクションのレジストリを JSON で出力 |
| `TestHarness` | `tests/powershell_harness.py`（T3）が利用する PS 関数評価 REPL モード。人間からは呼び出さない |

### Admin アクション（Config ベースライン管理）

`data/config-<OsKey>.json` ファイル群がスクリプトの利用するベースラインデータを
保持します。3 つの Admin Action により、ISO に触れずにこのデータを更新・点検
できます。**更新は 2 段階** で行います：`RefreshSnapshots` が Microsoft Learn と
Microsoft Update Catalog から上流の `data/raw-*` / `data/cache-*` を取得し、
`RefreshAllBaselines` が各 `data/config-Server*.json` の
`PatchBaseline.NeutralPatches[]` をそれらキャッシュから再生成します。この分離は
SPEC §B.22.12 の設計に対応します。

| Action | Admin Phase | 説明 |
|:---|:-:|:---|
| `RefreshSnapshots` | A03 | 上流キャッシュの取得（release-info、.NET CU、Dynamic Update）|
| `RefreshAllBaselines` | A01 | キャッシュから `data/config-Server*.json` を再生成 |
| `DumpFieldClassification` | A02 | フィールドのカデンス決定マトリックスを JSON で出力 |

```powershell
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

### r09.0 で実装予定

4 番目の Admin Action として **`RefreshDependencyDatabase`**（A04）が
[SPEC.md](./SPEC.md) §B.19.15.3 に仕様化されていますが、現バージョンの
スクリプトには **未実装** です。Microsoft の `wsusscn2.cab` から
`data/wsusscn2-database.json`（Servicing Dependency Database layer 2）を
更新するアクションで、実装は §B.19.19 のロールアウト計画に従います。

## 動作要件

| 項目：| 内容：|
|:---|:---|
| ホスト OS | Windows 10/11 Pro/Enterprise/Education または Windows Server 2016+ |
| PowerShell | Windows PowerShell 5.1+（PowerShell 7+ でも動作）、64-bit プロセス必須 |
| 権限 | Administrator（DISM マウントは管理者権限が必須）|
| Windows ADK | Deployment Tools 機能（`oscdimg.exe` を提供）。`-AutoInstallAdk` で自動インストール可能 |
| ディスク空き容量 | `-WorkRoot` ドライブに 100 GB 以上（最低 60 GB、Workspace プリフライトが 100 GB を強制チェック）|
| ネットワーク | ISO とパッチのダウンロード用インターネットアクセス（`-IsoPath` + `-PatchDirectory` 利用時は不要）|
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
| P06 | ValidatePatchSet | Plan | `wsusscn2.cab` のオフラインスキャン、必須 KB がパッチセットを網羅するか検証 |
| P07 | PatchInstallWim | Build | install.wim 各インデックスに対し SSU → LCU → .NET → DISM クリーンアップ |
| P08 | PatchBootWim | Build | boot.wim（PE + Setup）と winre.wim |
| P09 | AssembleIso | Build | Dynamic Update Setup オーバーレイ、Export-WindowsImage、oscdimg による ISO ビルド |
| P10 | ConvertPca2023BootManager | Build | **オプトイン** PCA2023 Secure Boot 変換（`-EnablePca2023BootManager`）|
| P11 | StaticVerify | Verify | 出力 ISO をマウントし、KB パッケージが含まれるか確認 |
| P12 | VerifyPca2023Readiness | Verify | **常時実行** — `pca2023_readiness.json` + `.md` を出力 |
| P13 | FinalReport | Report | 実行終了サマリ、ISO ハッシュ、ログパス |

各フェーズの詳細契約は [SPEC.md](./SPEC.md) Part B を参照してください。

### Secure Boot / PCA2023 boot manager（r05.0+）

Microsoft の「Windows Production PCA 2011」Secure Boot 署名証明書は
**2026-06** に失効します。2011 証明書を失効済みに更新したファームウェアは、
2011 系で署名された boot manager をもつ ISO の起動を拒否します。P10 / P12 が
この問題に対処します。詳細な運用モデル（OS 別デフォルト、
`-ForcePca2023OnServer2025` を設定するタイミング、`-Pca2023OnlyMode` による
スタンドアロンのフォレンジック検査）は SPEC.md §B.17 と §B.18 を参照してください。

代表的な運用判断：

- **Server 2016 / 2019 / 2022**：PCA2011 を DBX に追加済みのファームウェアを
  ターゲットにする場合、P10 が必要。`-EnablePca2023BootManager` で有効化。
  ソース ISO の `install.wim` の LCU 月は 2024-4B（2024 年 4 月）以降が必要
  （Server 2022 は Lenovo lp2353.pdf に従い、2025-2B が必要）。
- **Server 2025**：P10 はデフォルトでスキップ（Microsoft 認証済み Server 2025
  プラットフォームはファームウェアに 2023 証明書を同梱、KB5053484 は Server
  2025 を手順対象としていない）。PCA2023 変換が必要な非認証ハードウェアで
  運用する場合のみ `-ForcePca2023OnServer2025` で上書き。
- **既存 ISO のフォレンジック検査**：`-Pca2023OnlyMode -IsoPath <existing.iso>`
  で全ビルドパイプラインをスキップし、P12 のみを ISO に対して実行。

完全な設計と検証詳細は SPEC.md §B.17（PCA2023 boot manager サポート）と
§B.18（出力 ISO 検証）を参照してください。

## パラメーター（主要のみ）

完全なパラメーター一覧は `Get-Help .\Update-WindowsServerIso.ps1 -Full` を
参照してください。よく使うものは次のとおりです。

| Parameter | 用途 |
|:---|:---|
| `-Action` | 上記 13 個のアクションのいずれか（デフォルト：`PrepareBuildVerify`）|
| `-OnlyPhases` | フェーズ ID の配列（例 `'P04','P07'`）。Action のデフォルトフェーズセットを上書き |
| `-OsVersion` | `Server2016` / `Server2019` / `Server2022` / `Server2025` |
| `-OsLanguage` | `en-us` / `ja-jp`（デフォルト：`en-us`）|
| `-IsoPath` | ローカル ISO パス（`-IsoUrl` と排他）|
| `-IsoUrl` | 明示的な ISO ダウンロード URL |
| `-PatchDirectory` | ローカル MSU/CAB パッチを格納したディレクトリ |
| `-ManifestPath` | ハッシュ付き Metalink `.meta4` マニフェスト |
| `-PatchUrls` | 明示的なパッチ URL の配列 |
| `-AutoDetectLatestPatches` | Microsoft Update Catalogue からの PatchBaseline 再取得を強制 |
| `-PatchMonth` | リフレッシュ対象のパッチ月（例 `2026-06`、デフォルトは当月）|
| `-SkipDynamicPatchRefresh` | PatchBaseline が古くても P03 をスキップ（オフライン / エアギャップ実行）|
| `-UseBaselineOnly` | PatchBaseline を厳密にそのまま使用、Catalog にアクセスしない |
| `-IgnorePatchValidation` | P06 検証失敗を中断から警告に降格（非推奨）|
| `-WsusScnCabPath` | 事前配置済みの `wsusscn2.cab` パス（自動ダウンロードをスキップ）|
| `-WorkRoot` | ワークスペースのルート。デフォルトは `Workspace_UpdateWsi`（スクリプトと同階層）。ドライブの空き容量は 100 GB 以上が必要（プリフライトが強制）|
| `-OutputDir` | 出力 ISO のディレクトリ（デフォルトは `<WorkRoot>\output`）|
| `-OnlyInstallWimIndexes` | install.wim 更新対象を限定するカンマ区切りインデックス（例 `'2,4'`）|
| `-DryRun` | Build / Verify フェーズをスキップ（Setup / Fetch / Plan のみ）|
| `-SyntheticTestMode` | CI モード：Microsoft アセットに触れずに合成 ISO を構築 |
| `-EvalIsoMode` | Microsoft Evaluation Center の fwlink からのダウンロードを許可 |
| `-Execute` | DISM への実書き込みに **必須**。指定なしでは Build フェーズは計画のみ |
| `-EnablePca2023BootManager` | P10 PCA2023 boot manager 変換のオプトイン（デフォルト OFF）|
| `-ForcePca2023OnServer2025` | Server 2025 デフォルトスキップを上書きして P10 を実行 |
| `-Pca2023OnlyMode` | 既存 ISO のスタンドアロン P12 検査（`-IsoPath` が必須）|
| `-Pca2023ScriptPath` | 内部ヘルパーの代わりに外部 `Make2023BootableMedia.ps1` を使用 |
| `-AutoInstallAdk` | `oscdimg.exe` が見つからない場合に Windows ADK Deployment Tools を自動インストール |

### 排他的指定ルール

スクリプトは複数の排他制約を強制します（L353-L389）。該当する組み合わせは
以下のとおりです。

- `-IsoUrl` ⊥ `-IsoPath`
- `-EnvironmentInfoOnly` ⊥ `-SkipEnvCheck`
- `-Action BootTest` ⊥ `-SyntheticTestMode`
- `-SyntheticTestMode` ⊥ `-EvalIsoMode`
- `-SkipDynamicPatchRefresh` ⊥ `-AutoDetectLatestPatches`
- `-UseBaselineOnly` ⊥ `-AutoDetectLatestPatches`

`-PatchMonth` は `^\d{4}-\d{2}$` 形式（例 `2026-06`）と一致する必要があります。

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
        - PatchBaseline.NeutralPatches を Config JSON にアトミックに書き戻し
P04   FetchAssets（新しく解決された URL と SHA-256 を使用）
P05   ExpandIso
P06 ValidatePatchSet
        - Stage 1：カタログ鮮度比較（既存）
        - Stage 2（r09.0+、予定）：data/wsusscn2-database.json を用いた
          グラフベース依存性閉包チェック（SPEC.md §B.19 参照）
        - 必須プリレキジが欠落しているとき：中断して診断ファイルを生成
P07+  Build / Verify / Report
```

### 検証失敗時の診断データ

P06 が必須パッチの欠落を検出すると、診断ファイルが
`<WorkRoot>/diag/<yyyy-MM-dd_HH-mm-ss>/` に出力されます。ファイル一覧と
利用方法は SPEC.md §B.19.14.3 を参照してください。

`-IgnorePatchValidation` は中断を警告に降格しますが、診断ファイルは引き続き
生成されます。開発時のみ使用してください。

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

`tests/` サブディレクトリには 10 個の Python 自己検証ツール（T1 – T10）が
同梱されており、スクリプトの外部依存をプローブし、PowerShell 関数を
ユニットテストします。Python 標準ライブラリのみを利用するため、
`pip install` は不要です。

```bash
# オフラインテスト — どこでも安全に実行可能
python3 tests/catalog_fixture_test.py        # T2：13 個の fixture アサーション
python3 tests/powershell_harness.py          # T3：7 個の PS 関数アサーション
python3 tests/release_info_parser_test.py    # T6：13 個の release-info パーサーアサーション
python3 tests/dotnet_cu_parser_test.py       # T7：16 個の .NET CU パーサーアサーション
python3 tests/dynamic_update_cache_test.py   # T8：20 個の DU キャッシュアサーション
python3 tests/catalog_title_tokens_test.py   # T9：18 個の Title-token アサーション
python3 tests/release_info_resolver_test.py  # T10：18 個の resolver アサーション

# ライブテスト — 制限のないネットワーク出口が必要
python3 tests/catalog_probe.py --check all   # T1：Microsoft Update Catalog
python3 tests/eval_iso_probe.py              # T4：Server<N> ISO CDN
python3 tests/wsusscn2_probe.py              # T5：wsusscn2.cab 鮮度
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
[`.github/workflows/`](../../../.github/workflows/) にあります。
各ワークフローの変更履歴は本プロジェクトの
[`CHANGELOG.md`](./CHANGELOG.md) に記録します（ルートの
[`SPEC.md`](../../../SPEC.md) §9 で規定されているリポジトリ規約に従う）。

Stage 4 は `workflow_dispatch` の 4 入力（`mode`、`onlyOs`、`onlyLanguage`、
`dryRun`）に対応しており、ワークフローを編集することなくアドホックな更新
実行やスコープ限定が可能です。生成される PR は `add-paths` で
`data/config-*.json`（r09.0+ では `data/wsusscn2-database.json` も）に
限定されます。

重要：Stage 3 は ISO アーティファクトを **絶対にアップロードしません**。
評価版ライセンスが Microsoft バイナリの公衆配布を禁じているため、
ワークフローの `actions/upload-artifact` の明示的な `path:` 列挙でこれを
強制します（リポジトリ SPEC.md §12（SPEC-CI-081）を参照）。

## トラブルシューティング

| 症状：| 原因：| 対処：|
|:---|:---|:---|
| `Administrator privilege required` | 非管理者ユーザーで実行 | PowerShell を管理者として再起動 |
| `oscdimg.exe not found` | Windows ADK Deployment Tools 未インストール | `-AutoInstallAdk` で再実行（約 50-80 MB の Deployment Tools 機能を自動インストール）するか、[Windows ADK インストーラ](https://go.microsoft.com/fwlink/?linkid=2289980) から手動インストール（SPEC.md §B.22.13 参照）|
| `Workspace preflight failed: drive ... has only NN GB free` | `-WorkRoot` ドライブの空き容量が 100 GB 未満 | `-WorkRoot` をより大きなボリュームへ移動するか、空きを確保する（100 GB は 1 OS 分の PrepareBuildVerify エンドツーエンドに必要な最低量）|
| `Workspace preflight failed: ... required Config file(s) missing` | `data/config-Server<N>.json` ファイル群が削除またはコピー漏れ | `Update-WindowsServerIso.ps1` と同階層に `data/` ディレクトリを復元（`Server2016/2019/2022/2025.json` の 4 ファイルすべてが必須）|
| `Catalogue: no narrowed result for ... / Server2022`、`Resolved 0 patch entries` | Microsoft が Catalogue のタイトル形式を変更（句読点ドリフト）| 該当 `data/config-Server*.json` の `TitleTokens` 配列に新形式を追加（SPEC.md §D.19 参照）|
| RefreshAllBaselines 後の `NeutralPatches[]` エントリの `Type` が誤っている | `Convert-CatalogPatchToBaselineEntry` の新規呼び出し側で `-KnownType` 未渡し | Catalogue 検索コンテキストから `-KnownType $q.Type` を渡す（SPEC.md §D.20 参照）|
| .NET CU ベースラインエントリのサブファイルが欠落しているように見える | 複数 `.msu` を持つアンブレラ KB で 1 つしか保持されなかった | `Resolve-PatchSetFromCatalog` が `Type='DotNet'` を `Select-AllCanonicalPatchFiles` 経由でルーティングしているか確認（SPEC.md §D.21 参照）|
| Warning 行に `0x800f081e` が表示 | このパッチは当該 SKU には適用不能 | クロス SKU のパッチセットでは想定内、無視して問題なし（SPEC.md §D.8 参照）|
| P07 の途中で `0x800f0823 — CBS_E_NEW_SERVICING_STACK_REQUIRED` | LCU が前提とする SSU がベースラインから欠落 | 前提 SSU を `NeutralPatches[]` に追加。r09.0+ の Servicing Dependency Database（SPEC.md §B.19）は DISM マウント前の P06 でこれを検出します（SPEC.md §D.2 参照）|
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
  v1.4 の `Copy-2023BootBins`（関数 L829-L941）の PSA-clean 再実装です。
  上流互換の出力検証機能（P12 `Test-OutputIsoPca2023Readiness`）は、
  Microsoft オリジナルにはない品質向上のための拡張です。

本スクリプトは Anthropic Claude（Opus 4.7 期）で生成・反復的に洗練されました。
スクリプトソースの現在の識別子は
`$Script:ScriptVersion = 'update-wsi-2026.05.27-r08.0'` です。次リビジョン
（r09.0）では、[SPEC.md](./SPEC.md) に仕様化された §B.19 Servicing
Dependency Database を実装する予定です。
