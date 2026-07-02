---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-07-01
---
# RHEL ファミリー コンテナテストスイート

[English](./README.md) | 日本語

> 📂 [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) の一部 → [`projects/bash-rhel-container-testsuite/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-rhel-container-testsuite)
> ⚠️ **AI 生成コンテンツ** — 実行前にソースを確認してください。免責の全文は [リポジトリのAIコンテンツポリシー](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md) を参照。
> 📐 **開発者向け仕様**: [SPEC.md](./SPEC.md)（英語のみ）— 確定済みの設計判断、2 つの軸、テスト階層、ツール互換性フレームワーク、フェーズ契約。
> ➕ **ツールの追加**: 下記の [ツールの追加](#ツールの追加) 節を参照 — ツール非依存の契約と、2つ目のツール向けの穴埋め手順。

**RHEL ファミリー向けのコンテナベース互換性テストスイート**です。RHEL の各メジャー
（**10 / 9 / 8 / 7 / 6**）について、あるツールのどのバージョンが Red Hat のコンテナ
イメージ上で**インストールでき**、**実行できる**かを測定し、OS ごとのレポートを出力
します。姉妹プロジェクト
[`bash-ol-aws-ami-builder`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-ol-aws-ami-builder)
で実証済みの AWS CLI v2 / SSM Agent / ENA マトリクスを、**ツール中心・RHEL ファミリー
中心**に一般化したものです。

**初期対象ツール:** AWS CLI v2、AWS SSM Agent、AWS ENA Driver。

---

## ⚠️ 免責事項（実行前に必ずお読みください）

**自己責任でご利用ください。** 本ソフトウェアは明示・黙示を問わずいかなる保証もなく
「現状のまま」提供されます。利用・改変・再配布に起因するいかなる損害、データ損失、
意図しないクラウド費用、アカウントやサブスクリプションに関する問題など（直接・間接を
問わず）について、作者および貢献者は一切責任を負いません。

本スイートを実行することで、次の点に同意したものとみなされます。

* **Red Hat のサブスクリプション規約**（特に entitlement のパススルーや
  `registry.redhat.io`）、**AWS のサービス規約**、および適用される法令の遵守は、
  すべて利用者の責任であること。
* L3 統合実行ではコンテナイメージの**プル**やツール成果物（AWS CLI バンドル、SSM の
  S3 RPM）の**ダウンロード**がネットワーク越しに発生し、転送費用が生じ得ること。
* **entitled モード**ではホストの Red Hat entitlement（バインドマウントされたシーク
  レット）を利用すること。スイート自身はシークレットを一切扱わず、ホストがそれを
  パススルーしているか**検出するだけ**であること。
* どの環境で実行する場合も、事前にソース（または [SPEC.md](./SPEC.md)）を確認すること。

本番作業では公式・サポート対象のチャネルを優先してください。本スイートが対象とするのは
**互換性の測定とレポート**であり、本番プロビジョニングではありません。

---

## このスイートが存在する理由

RHEL ファミリーのコンテナを運用していると、同じ問いに繰り返し直面します。
*「このツールのバージョン X は、RHEL N で本当にインストール・実行できるのか？」*
答えは glibc によって、パッケージマネージャ（dnf か yum か）によって、init モデル
（素のシェルか systemd PID 1 か）によって、そしてホストが Red Hat の entitlement を
コンテナにパススルーしているかどうかによって変わります。本スイートはこの問いを
**再現可能なマトリクス**に変換します。RHEL の各メジャーとツールの各バージョンについて、
測定された環境（glibc / kernel / entitlement / init モード）と導出された判定を記録し、
ひと目で読める OS ごとのレポートを再生成します。

本スイートは、直接測定（Phase 0）で確立した 2 つの事実の上に成り立っています。

1. Red Hat の UBI イメージは**匿名で**（トークン取得ステップなしで）プルでき、
   RHEL 7〜10 のインストール・実行テストに利用できる。RHEL 6 はレガシーの
   `rhel6/rhel` ベースを使う。
2. **サブスクリプション登録済みの RHEL ホスト**上で実行すると、entitlement がコンテナ
   へパススルーされ、`rhel-*` リポジトリが有効になり、`kernel-devel` が取得可能になる。
   これにより ENA カーネルモジュールの**ビルド**テストが可能になる。スイートはこれを
   **自動検出**し、そうでなければ `needs-entitlement` を記録する。

---

## 全体で登場する 2 つの軸

* **Entitlement（権限付与）** — `env_entitlement = anonymous | entitled`。3 段階の
  プローブで自動検出します（シークレットの存在確認 → `redhat.repo` 生成のトリガ →
  `rhel-*` リポジトリ接頭辞で分類）。詳細は [SPEC.md](./SPEC.md) §4a。
* **Init モード** — `env_init_mode = none | systemd`。1 つの `ubi-init` イメージで
  両方をカバーします。コマンドを指定して実行すれば（systemd は PID 1 にならない）
  インストール／バイナリのテスト、`podman run -d` で起動すれば `systemctl` による
  サービステストになります。詳細は [SPEC.md](./SPEC.md) §4b。

---

## ディレクトリ構成

```
bash-rhel-container-testsuite/
  README.md  README.ja.md          # バイリンガル（常に同期）
  SPEC.md  TESTING.md              # 開発者向け仕様 + テストガイド
  CHANGELOG.md  .shellcheckrc
  lib/                             # 取得用ライブラリ            (Phase 2 ✅)
    acquire-rootfs.sh  ubi-pkgmgr.sh  epel.sh
    os-profile.sh                    # メジャー別 OS プロファイルの正典（Phase 6 ✅）
    pkg-availability.sh              # パッケージ可用性分類（Phase 7 ✅）
  install-aws_awscli-v2.sh         # 直下のインストールスクリプト: 実ホストでも使用可＋  (r08 ✅)
  install-aws_ssm-agent.sh         #   テストモード付き。test フォルダ名と一致し、
  install-aws_ena-driver.sh        #   マトリクスがパラメータ付きでキックする。
                                   #   各々が RHEL メジャー別の検証済みバージョンをピン留め
  tests/
    lib/{assert,mock,heredoc}.sh   # 移植済みハーネス
    run-all.sh                     # L0-L2 を一括実行するランナー
    t001_parse.sh  t002_shellcheck.sh             # L0（実装済み）
    t003_acquireunit.sh … t007_epelresolve.sh     # L1/L2（Phase 2 ✅）
    t008_awscliverdict.sh  t009_ssmverdict.sh    # L1 AWS CLI + SSM 判定（Phase 3-4 ✅）
    t010_enaverdict.sh  t011_enaverify.sh         # L1 ENA 判定 + verifier（Phase 5 ✅）
    t012_osprofile.sh                             # L1 OS プロファイル + 整合検証（Phase 6 ✅）
    t013_toolcontract.sh  t014_pkgavail.sh        # 契約 + 分類（Phase 7 ✅）
    aws_awscli-v2/                                # AWS CLI マトリクス（Phase 3 ✅）
      list-awscli-releases.sh  awscli-releases.json
      run-awscli-installtest-matrix.sh  awscli-installtest-ledger.json
      RESULTS-rhel{6,7,8,9,10}.md
    aws_ssm-agent/                                # SSM マトリクス（Phase 4 ✅）
      list-ssm-releases.sh  ssm-releases.json
      run-ssm-installtest-matrix.sh  ssm-installtest-ledger.json
      RESULTS-rhel{6,7,8,9,10}.md
    aws_ena-driver/                               # ENA buildtest マトリクス（Phase 5 ✅）
      list-ena-releases.sh  ena-driver-releases.json
      run-ena-buildtest-matrix.sh  buildtest-ledger.json
      verify-ena-buildresults.sh  RESULTS-rhel{6,7,8,9,10}.md
    os-coverage/                                  # OS カバレッジ表（Phase 6 ✅）
      generate-os-coverage.sh  RESULTS-coverage.md
    conformance/                                  # ツール契約チェッカ（Phase 7 ✅）
      check-tool-contract.sh
```

*(Phase N)* と記したファイルは**まだ存在しません**（下記「ステータス」参照）。
`lib/` と `tests/aws_*/` ディレクトリには `.gitkeep` を置き、計画されたレイアウトが
git 上で見えるようにしています。

---

## 実行方法

静的解析 + ハーミティックな単体階層（L0-L2）は、ネットワークなしでどのホストでも
実行できます。

```bash
bash tests/run-all.sh
```

L3 統合マトリクス（実際のプルとインストール）は、コンテナのアウトバウンド通信が可能な
ホストで、ツール別の一括ワークフロー（`rm -rf *.md *.json; ./list-...; ./run-...`、ENA は
さらに `./verify-...`）で実行します。ツール別の実行ガイドは
**[TESTING.md](./TESTING.md) の「Running the end-to-end tests (per target)」**に一箇所へ
まとめてあります。階層モデルと環境依存の全体像もそちらを参照してください。

---

## ステータス

これは最終フェーズ **Phase 7（一般化）** のドロップです。全 7 フェーズ完了:

* ✅ **Phase 0 — 実現可能性調査** — 実測した基礎事実（メジャー別 glibc、匿名リポジトリ
  集合、匿名プル、5 メジャー全体の entitled パススルー、RHEL 7 の固定タグ署名、EPEL
  エンドポイント）。Phase 0 で実測。
* ✅ **Phase 1 — スキャフォールディング** — ディレクトリ骨格、`tests/lib/*` の移植、
  `run-all.sh`、`.shellcheckrc`、バイリンガル文書、そして緑の L0 ゲート。
* ✅ **Phase 2 — 取得（acquisition）** — `lib/acquire-rootfs.sh`、
  `lib/ubi-pkgmgr.sh`、`lib/epel.sh` と単体階層 `t003`〜`t007`。
* ✅ **Phase 3 — AWS CLI v2** — 最初のツール別マトリクス `tests/aws_awscli-v2/*`
  （リリース収集＋927 バージョンの `awscli-releases.json`、install-test マトリクス、
  glibc ledger、生成済み `RESULTS-rhel{6,7,8,9,10}.md`）と判定階層 `t008`。
* ✅ **Phase 4 — AWS SSM Agent** — init 感応のマトリクス `tests/aws_ssm-agent/*`
  （207 バージョンの `ssm-releases.json`、Phase 2 の `acq_init_run_args` を組み込んだ
  **glibc ＋ init_mode** の install-test マトリクス、生成済み `RESULTS`）と判定階層
  `t009`。
* ✅ **Phase 5 — AWS ENA driver** — entitlement ゲート付きの **buildtest** マトリクス
  `tests/aws_ena-driver/*`（70 バージョンの `ena-driver-releases.json`、E2' ビルド
  マトリクス、read-only の load-readiness verifier `verify-ena-buildresults.sh`、
  生成済み `RESULTS`）と階層 `t010`/`t011`。
* ✅ **Phase 6 — EOL／制約付きメジャー** — `lib/os-profile.sh`（メジャー別 OS
  プロファイルの正典）、整合検証の階層 `t012`、生成済み
  `tests/os-coverage/RESULTS-coverage.md`。
* ✅ **Phase 7 — 一般化** — フレームワークが**ツール非依存**になりました:
  `tests/conformance/check-tool-contract.sh` が SPEC §10 (a〜e) 契約を機械的に強制し
  （階層 `t013`）、`lib/pkg-availability.sh` が §12 分類の正典（階層 `t014`）、
  下記の [ツールの追加](#ツールの追加) 節が 2 つ目のツール向けの手順です。
  **スイート緑: 20 階層、478 件成功、0 件失敗**(r29; ShellCheck はデフォルト重大度と `-S style` の両方でクリーン、CWD 非依存)。

**全 7 実装フェーズが完了しました**（さらに r08 でモデルの2層構成を復元: 直下の
`install-aws_*.sh` インストーラ（各々が RHEL メジャー別の検証済みバージョンをピン留め）を
マトリクスがパラメータ付きでキック）。残るはライブの実測埋め — R5（ライブプル）、
R6（AWS CLI install）、R7（SSM install、両 init モード）、R8（entitled ホストでの ENA
ビルド。load は L4）— で、egress 可能／entitled／Nitro ホストで実行します。モデル・
生成器・verifier・ツール契約はサンドボックス内でハーミティックに緑です。詳細は
[SPEC.md](./SPEC.md) Part C(オープン項目 R5-R8)。

---

## ツールの追加

### 1. 命名（SPEC §14）

`<vendor>_<tool>`: ベンダ境界は `_`、ツール内の語は `-`。例:
`azure_az-cli`、`gcp_gcloud-cli`、`hashicorp_terraform`、`util_jq`、`k8s_kubectl`。
新しい名前は SPEC.md の命名語彙に記録します。

### 2. 取得元を分類（SPEC §12、`lib/pkg-availability.sh`）

ツールの主要な入力がどこから来るかを決め、`pkgavail_tool_source` /
`pkgavail_class` に追加します:

| class | 意味 | 匿名時の挙動 |
|:--|:--|:--|
| `anonymous-ubi` | `ubi-*` リポジトリ（7 は optional/extras/RHSCL も） | installable |
| `entitled-only` | `rhel-*` リポジトリ（kernel-devel 等） | `needs-entitlement` |
| `epel` | Fedora EPEL（dkms 等、ピン留め・既定オフ） | `epel-optional` |
| `vendor-hosted` | リポジトリ外（bundle / S3 RPM）をベンダ CDN 経由 | installable |
| `base-image` | ベースイメージに同梱済み | installable |

`pkgavail_anonymous_status "$(pkgavail_class "$(pkgavail_tool_source <name>)")"`
で「匿名時に何が起きるか」を一発で判定できます。

### 3. 契約を実装（SPEC §10、(0) ＋ a〜e）

- **(0)** プロジェクト直下の **`install-<vendor>_<tool>.sh`**（test フォルダ名と一致）
  … 実ホストでも使えるインストーラ。テストモード（`<TOOL>_INSTALLTEST=1`）では
  使い捨て rootfs で install/build → smoke → `[<vendor>_<tool>][installtest][result]`
  JSON を1行出力（**生の事実**: ran／installed／built＋文脈）。本番モードは実ホストに
  インストール。**RHEL メジャー別のバージョンピン**（各メジャーの検証済み版）を持ち、
  `resolve_version` が本番既定として解決（明示の `<TOOL>_VERSION` が優先、テスト時は
  マトリクスが明示指定）。ピンを単体検証できるよう `<TOOL>_LIB_ONLY=1` ガードを付与
  （`tests/t015_installpins.sh`、`tests/t016_installintrospect.sh` 参照）。失敗時は
  テストモードで構造化結果 `{"status":"fail",...,"reason":...}` を出す `die` を使い、
  どの失敗経路でもパース可能で理由付きの ledger 行を残すこと。

`tests/<vendor>_<tool>/` を作成します:

- **(a)** `list-<tool>-releases.sh` → 決定的な `<tool>-releases.json`
  （認証不要のソースからバージョン列挙。reuse-by-copy のヘルパーを持たせる）。
- **(b)** `run-<tool>-{install,build}test-matrix.sh`。**カラム 0 の純粋ヘルパー**
  （バージョン比較・メジャー別マップ・スコープ判定・`*_verdict()`）、`--run`(L3) は
  **直下の install スクリプトをキック**（`podman run -v <install-script>:... -e
  <TOOL>_INSTALLTEST=1 -e <PARAMS> <ref> ...`）、`result_field` で `[result]` を
  パース → verdict 適用 → 記録。ハーミティックな `--generate-results`。install
  ロジックをマトリクスに直書きしないこと。
- **(c)** `<tool>-…-ledger.json`。スキーマ付きで初期は `"results": []`。
- **(d)** `RESULTS-rhel{6,7,8,9,10}.md`。`--generate-results` で生成（手編集禁止）。
- **(e)** `tests/t0NN_<tool>verdict.sh`。マトリクスの純粋ヘルパーを名前で読み込み、
  テーブル駆動で検証。さらにマトリクス／lister の reuse-by-copy も検証。

正典を再利用します: メジャー別の事実は `lib/os-profile.sh`（glibc はツール固有表、
image・pull 制約・リポジトリ・ライフサイクル・EPEL）、init-mode 対応の取得は
`lib/acquire-rootfs.sh`。

### 4. 検証

```sh
bash tests/run-all.sh                              # 新階層を含む全階層
bash tests/conformance/check-tool-contract.sh      # 契約適合
```

`check-tool-contract.sh` が新ツールを `ok` と表示し（直下の
`install-<vendor>_<tool>.sh` が存在・実行可能で、マトリクスが**キック**することを要求）、
`t013` が緑のままであること。各スクリプトは ShellCheck `style` クリーン
（`printf` 内の Markdown バックティックは `\140`）、全ファイル LF を維持します。

---

## 既知の制約

* ハーメティックなスイート(L0–L2)はモデル・生成器・契約を証明しますが、ライブマトリクス(`--run`)には
  コンテナ egress ホスト(`rhel-*` リポジトリ経路にはサブスクリプション登録済み RHEL ホスト)が必要です
  — [SPEC.md](./SPEC.md) Part C のオープン項目 R5–R8 として追跡。
* カーネルモジュールの **load** はコンテナでは検証不能(ホストカーネル共有)のため、ENA の load/runtime は
  常に実 RHEL ホスト上の L4 層です。
* RHEL 6 は Tier C: 匿名リポジトリなし(ベースイメージ内容のみ)。entitled で `rhel-6-server-rpms` が有効化。
  EPEL 6/7 はアーカイブのみ。
* RHEL 7 の `ubi-init` は固定タグまたはダイジェストで pull すること(浮動タグはホスト署名ポリシーが拒否、SPEC D.7)。

---

## 来歴(Provenance)

* **AI ツール**: Anthropic Claude (Claude Fable 5)、claude.ai セッション。改訂履歴は
  [CHANGELOG.md](./CHANGELOG.md)(`rNN` 連番)。
* **生成・保守**: 2026-06 – 2026-07(r01–r30)。doc-set はリポジトリのテンプレート正典から
  レンダリング(front-matter の `doc-provenance` ピン参照)。
* **AS-IS**: 無保証で現状のまま提供。上部の免責事項とリポジトリの
  [LICENSE](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE) を参照。

---

## ライセンス

リポジトリの [LICENSE](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE) を参照してください。
