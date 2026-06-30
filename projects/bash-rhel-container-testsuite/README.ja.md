---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-07-01
---
# RHEL ファミリー コンテナテストスイート

[English](./README.md) | 日本語

> 📂 [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) の一部 → [`projects/bash-rhel-container-testsuite/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-rhel-container-testsuite)
> ⚠️ **AI 生成コンテンツ** — 実行前にソースを確認してください。免責の全文は [scripts ディレクトリのポリシー](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md) を参照。
> 📐 **開発者向け仕様**: [SPEC.md](./SPEC.md)（英語のみ）— 確定済みの設計判断、2 つの軸、テスト階層、ツール互換性フレームワーク、フェーズ契約。

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
  install-awscli.sh                # RHEL 適応版インストールスクリプト (Phase 3-5)
  install-ssm-agent.sh  install-ena-driver.sh
  tests/
    lib/{assert,mock,heredoc}.sh   # 移植済みハーネス
    run-all.sh                     # L0-L2 を一括実行するランナー
    t001_parse.sh  t002_shellcheck.sh             # L0（実装済み）
    t003_acquireunit.sh … t007_epelresolve.sh     # L1/L2（Phase 2 ✅）
    t008_awscliverdict.sh  t009_ssmverdict.sh    # L1 AWS CLI + SSM 判定（Phase 3-4 ✅）
    t010_enaverdict.sh  t011_enaverify.sh         # L1 ENA 判定 + verifier（Phase 5 ✅）
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
ホストで明示的に実行します（Phase 3-5 で追加）。階層モデルと環境依存の全体像は
[TESTING.md](./TESTING.md) を参照してください。

---

## ステータス

これは **Phase 5（AWS ENA driver）** のドロップです。ここまでの完了状況:

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
  生成済み `RESULTS`）と階層 `t010`/`t011`。**スイート緑: 11 階層、267 件成功、0 件失敗。**
  残課題は **ライブビルド（L3、entitled ホスト）** で、モジュールのロードは L4 です。

次は **Phase 6 — EOL／制約付きメジャー**（RHEL 7 は凍結 yum＋固定タグ、RHEL 6 は匿名
リポジトリ無し・entitled `rhel-6-server`・EPEL アーカイブのみ）です。フェーズ計画の全体は
[SPEC.md](./SPEC.md) §10 にあります。

---

## ライセンス

リポジトリの [LICENSE](https://github.com/usui-tk/ai-generated-artifacts/blob/main/LICENSE) を参照してください。
