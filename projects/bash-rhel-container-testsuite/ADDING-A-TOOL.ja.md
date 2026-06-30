# ツールの追加方法

[English](./ADDING-A-TOOL.md) | 日本語

本スイートは**ツール非依存**です。各ツールは `tests/<vendor>_<tool>/` に置かれ、
同一の契約（フレームワーク、SPEC §10 の a〜e）を実装します。適合チェッカ
`tests/conformance/check-tool-contract.sh` がこれを強制し、ツールが非適合だと
`tests/t013_toolcontract.sh` がスイートを失敗させます。したがって非 AWS の 2 つ目の
ツール追加は「空欄を埋める」作業になります。

## 1. 命名（SPEC §14）

`<vendor>_<tool>`: ベンダ境界は `_`、ツール内の語は `-`。例:
`azure_az-cli`、`gcp_gcloud-cli`、`hashicorp_terraform`、`util_jq`、`k8s_kubectl`。
新しい名前は SPEC.md の命名語彙に記録します。

## 2. 取得元を分類（SPEC §12、`lib/pkg-availability.sh`）

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

## 3. 契約を実装（SPEC §10、(0) ＋ a〜e）

- **(0)** プロジェクト直下の **`install-<vendor>_<tool>.sh`**（test フォルダ名と一致）
  … 実ホストでも使えるインストーラ。テストモード（`<TOOL>_INSTALLTEST=1`）では
  使い捨て rootfs で install/build → smoke → `[<vendor>_<tool>][installtest][result]`
  JSON を1行出力（**生の事実**: ran／installed／built＋文脈）。本番モードは実ホストに
  インストール。**RHEL メジャー別のバージョンピン**（各メジャーの検証済み版）を持ち、
  `resolve_version` が本番既定として解決（明示の `<TOOL>_VERSION` が優先、テスト時は
  マトリクスが明示指定）。ピンを単体検証できるよう `<TOOL>_LIB_ONLY=1` ガードを付与
  （`tests/t015_installpins.sh` 参照）。

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

## 4. 検証

```sh
bash tests/run-all.sh                              # 新階層を含む全階層
bash tests/conformance/check-tool-contract.sh      # 契約適合
```

`check-tool-contract.sh` が新ツールを `ok` と表示し（直下の
`install-<vendor>_<tool>.sh` が存在・実行可能で、マトリクスが**キック**することを要求）、
`t013` が緑のままであること。各スクリプトは ShellCheck `style` クリーン
（`printf` 内の Markdown バックティックは `\140`）、全ファイル LF を維持します。
