# 開発者向け仕様書 (SPEC)

> **本ドキュメントの目的**
>
> 本ファイルは、本ディレクトリ配下の `build-ol-aws-ami.sh` ラッパースクリプトおよび付随する env テンプレートを保守・拡張するための仕様書です。新機能や不具合修正の作業開始時に、人間の開発者あるいは LLM(Claude)が直接参照することで、規約をゼロから再導出する必要がないようにすることを目的としています。
>
> **最も重要な規則**:本ドキュメントで挙動が定義されている要素(phase contract、ログマーカー、env プロパティキー、検証順序)について、新機能追加の際は必ず既存実装を再利用してください。phase 番号、ログマーカーセット、env プロパティの自動検出規則を再設計してはいけません。これらは Part C に記録された数多くのリビジョンを経て堅牢化されており、書き換えはリグレッションを招きます。
>
> リポジトリ全体に適用される ⚠️ AI 生成コンテンツに関する方針(参照: [`../../README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md))は引き続き有効です。本 SPEC はそれを Oracle Linux AWS AMI ビルダー固有の実装詳細で補足するものです。

🇺🇸 **English version of the specification is in [SPEC.md](./SPEC.md).**

---

## 目次

- [Part A — 共通仕様](#part-a--共通仕様)
  - [A.1 参照すべきアセット](#a1-参照すべきアセット)
  - [A.2 ソースファイル構造](#a2-ソースファイル構造)
  - [A.3 パイプライン構成(9 フェーズ)](#a3-パイプライン構成9-フェーズ)
  - [A.4 ロギング規約](#a4-ロギング規約)
  - [A.5 シェルオプションと防御的コーディング](#a5-シェルオプションと防御的コーディング)
  - [A.6 引数規約](#a6-引数規約)
  - [A.7 env プロパティファイル規約](#a7-env-プロパティファイル規約)
  - [A.8 Oracle Linux バージョン自動検出](#a8-oracle-linux-バージョン自動検出)
  - [A.9 エラー・診断規約](#a9-エラー診断規約)
  - [A.10 バイリンガルドキュメント](#a10-バイリンガルドキュメント)
  - [A.11 開発ワークフロー](#a11-開発ワークフロー)
- [Part B — スクリプト個別仕様](#part-b--スクリプト個別仕様)
  - [B.1 build-ol-aws-ami.sh](#b1-build-ol-aws-amish)
  - [B.2 setup-vmimport-role.sh](#b2-setup-vmimport-rolesh)
  - [B.3 env.properties.aws-ol{6,7,8,9,10}](#b3-envpropertiesaws-ol6789-10)
  - [B.4 OL6 ランタイム合成(distr/ol6-slim/ + cloud/aws/ パッチ)](#b4-ol6-ランタイム合成distrol6-slim--cloudaws-パッチ)
- [Part C — 既知の落とし穴と教訓](#part-c--既知の落とし穴と教訓)
- [Part D — OL6 全体アーキテクチャ](#part-d--ol6-全体アーキテクチャ)

---

# Part A — 共通仕様

## A.1 参照すべきアセット

これらが信頼できる情報源です。**これらから直接取り込んでください。再実装しないこと。**

### A.1.1 正規スクリプト

```
build-ol-aws-ami.sh         メインオーケストレータ。9 フェーズ全て
setup-vmimport-role.sh      AWS IAM ロールの初回セットアップ
```

これらのスクリプトは以下の正規実装の出所です。

- `log_step` / `log_info` / `log_warn` / `log_error` / `die`(出力ヘルパー)
- `detect_ec2_environment` / `resolve_aws_region` / `guide_ec2_kvm_issue`(EC2 自己診断とリージョン解決)
- `detect_qemu_user` / `phase2_grant_qemu_access`(libvirt ACL 設定)
- `parse_ol_version_from_iso` / `detect_os_variant`(OL バージョン推測)
- `derive_oracle_checksum_url`(ISO チェックサム URL フォールバック)

### A.1.2 上位依存

本スクリプトは Oracle 公式ツールのラッパーです。

```
https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools
```

具体的には、Phase 5 で上記リポジトリの `bin/build-image.sh` をクローン経由で呼び出します。上位ツールの仕様変更(例: `BOOT_MODE` 許容値、ディストリビューション slug、環境変数キー)は本仕様書で追跡し、`load_env` のバリデーションに反映してください。

### A.1.3 付随ファイル

```
env.properties.aws-ol10     Oracle Linux 10 Update 1 用テンプレート
env.properties.aws-ol9      Oracle Linux 9  Update 7 用テンプレート
env.properties.aws-ol8      Oracle Linux 8  Update 10 用テンプレート
env.properties.aws-ol7      Oracle Linux 7  Update 9 用テンプレート(実験的 — B.3 / C.10 参照)
env.properties.aws-ol6      Oracle Linux 6  Update 10 用テンプレート(実験的 — B.4 / C.11–C.16 / Part D 参照)
README.md / README.ja.md    エンドユーザ向けドキュメント(バイリンガル)
SPEC.md  / SPEC.ja.md       本仕様書(バイリンガル)
```

### A.1.4 ワークスペースパスの方針

`WORKSPACE` のデフォルトは `/tmp/ol{N}-build-ws`(`{N}` は OL メジャーバージョン)です。`/tmp` は FHS 慣習により全ユーザーが traverse 可能であり、libvirt の qemu ユーザー(uid 107)が `/root` 等の制限された親パス配下にあるファイルに到達できない問題を回避できるため、このパスが選択されています。詳細は A.7 および C.3 を参照してください。

---

## A.2 ソースファイル構造

### ファイル構造(上から順に)

```
1. Shebang                          #!/usr/bin/env bash
2. ヘッダバナー(枠線ブロック)       Purpose / Prerequisites / Usage / Limitations / AI info
3. set -euo pipefail                必須。A.5 参照
4. 定数(readonly)                  OL_REPO_URL, OL_TOOLS_SUBDIR, DEFAULT_ISO_URL
5. 実行モードグローバル             SKIP_PREREQ, SKIP_AWS_IMPORT, BUILD_ONLY, ENV_FILE
6. ロギングヘルパー                 log_step, log_info, log_warn, log_error, die
7. 引数解析                         usage, parse_args
8. 環境ロード                       parse_ol_version_from_iso, load_env
9. EC2 ヘルパー                     detect_ec2_environment, resolve_aws_region, guide_ec2_kvm_issue
10. Phase 0–8 関数                  phase0_preflight_checks ... phase8_register_ami
11. ヘルパー関数(関連箇所に配置)   detect_qemu_user, derive_oracle_checksum_url, detect_os_variant
12. main()                          phase0..phase8 を skip/build-only 分岐付きで呼び出し
13. ファイル末尾の起動              main "$@"
```

ヘッダバナーは、リポジトリレベルの `scripts/README.md` 規約により求められる以下の 5 セクションを必ず含むこと。

| セクション | 必須内容 |
|----------|---------|
| Purpose | 1 段落。スクリプトの目的と動機 |
| Prerequisites | ランタイム、権限、必須 CLI |
| Usage examples | 少なくとも 2 つの呼び出し例 |
| Known limitations | aarch64、BOOT_MODE 制約、並行制限 |
| AI generation info | 生成 AI ツール名、生成日 |

---

## A.3 パイプライン構成(9 フェーズ)

### 番号付け規則

- フェーズは **0 から 8 まで欠番なく**連続(`Phase 1.5` のような半端な番号は不可)。
- フェーズ関数名は `phase{N}_<verb>_<noun>()` の snake_case 形式。
- Phase 0 はプリフライト。以降のフェーズは Phase 0 通過を前提とする。

### フェーズレジストリ

| ID | 関数 | グループ | 責務 |
|---:|------|---------|------|
| 0 | `phase0_preflight_checks` | 検証 | KVM 露出、必須コマンド、空き容量、tmpfs/noexec チェック |
| 1 | `phase1_install_prerequisites` | プロビジョニング | KVM/libvirt/virt-install/libguestfs/osinfo-db/acl 導入 |
| 2 | `phase2_grant_qemu_access` | プロビジョニング | WORKSPACE 親パス連鎖への `setfacl u:qemu:x` |
| 3 | `phase3_clone_repository` | ビルド | oracle/oracle-linux を `git clone --depth 1`。**OL7 のみ**: `cloud/aws/image-scripts.sh` の OL7 拒否行を no-op に書き換える(`.ol7-patch.bak` バックアップを残す)。C.10 を参照 |
| 4 | `phase4_prepare_env_properties` | ビルド | ISO チェックサム、OS_VARIANT 解決、`env.properties.local` 生成 |
| 5 | `phase5_run_build` | ビルド | `bin/build-image.sh` 呼び出し、VMDK 生成 |
| 6 | `phase6_upload_to_s3` | AWS | `aws s3 cp` で VMDK をアップロード |
| 7 | `phase7_import_snapshot` | AWS | `import-snapshot` + ポーリングループ |
| 8 | `phase8_register_ami` | AWS | 条件付き `--tpm-support` で `register-image` |

### フェーズグループ(意味的分類)

- **検証**(0): 読み取り専用の診断。状態を変更しない。
- **プロビジョニング**(1, 2): sudo 必要。冪等性あり(既実施ならスキップ)。
- **ビルド**(3, 4, 5): `WORKSPACE` 内で動作。VMDK を生成。
- **AWS**(6, 7, 8): 設定された `AWS_REGION` に対するネットワーク操作。

### フェーズ entry/exit 契約

各フェーズは以下を必ず満たすこと。

1. entry 時に `log_step "Phase {N}: <1 行サマリ>"` を呼ぶ。
2. 失敗時は `die "<対処可能なエラーメッセージ>"`(exit 1)。
3. 成功時は自然 return(明示的に `exit 0` は呼ばない)。`set -e` がそれ以前の未処理非 0 終了を捕捉する。
4. 後続フェーズで必要な状態は普通の shell 変数として export する(例: `VMDK_PATH`、`S3_KEY`、`SNAPSHOT_ID`)。

### スキップ/部分実行のセマンティクス

- `--skip-prereq` → Phase 1 のみスキップ(Phase 2 はパッケージ導入済みでも ACL 更新のため実行)
- `--build-only` → Phase 5 まで実行して exit 0
- `--skip-aws-import` → `--build-only` の同義語

---

## A.4 ロギング規約

### マーカー(色付き)

| マーカー | ヘルパー | ANSI 色 | 意味 |
|---------|---------|--------|------|
| `[STEP]` | `log_step` | 太字緑 | フェーズヘッダバナー |
| `[INFO]` | `log_info` | 太字青 | 情報・進捗 |
| `[WARN]` | `log_warn` | 太字黄 | 縮退するが致命的でない |
| `[ERROR]` | `log_error` | 太字赤 | 失敗。通常は `die` が後続 |

### 行フォーマット

```
[MARKER] YYYY-MM-DD HH:MM:SS <メッセージ>
```

- タイムスタンプはローカル時刻(`date '+%Y-%m-%d %H:%M:%S'`)。
- マーカー/色の組み合わせのみが許容スタイル。新マーカー(`[DEBUG]`、`[OK]`、`[!]` 等)の発明は不可。長時間の運用で読み手が頼る視覚スキャンパターンを壊すため。
- ERROR は `>&2` に出力。INFO/WARN/STEP は stdout。

### バナーブロック

フェーズヘッダは `log_step` で出力され、60 文字の `=` 区切り線を前置する。

```
========== Phase 5: Running oracle-linux-image-tools to build the VMDK ==========
```

これが唯一許容されるフェーズバナーフォーマット。罫線記号の追加や幅変更は不可。多くの利用者が長いログをナビゲートする際に `^==========` で grep するため。

---

## A.5 シェルオプションと防御的コーディング

### `set -euo pipefail` の必須性

本ディレクトリのすべてのスクリプトは `set -euo pipefail` を必ず使用する。3 つのオプションが、bash で最も頻発する 3 つの失敗モードを捕捉する。

- `-e`(`errexit`): 非 0 終了で abort
- `-u`(`nounset`): 未定義変数参照で abort
- `-o pipefail`: パイプライン中の失敗を伝播

### 防御的コーディング規則

1. **`${VAR:?...}` または `${VAR:=...}` 形式の各代入**は、解決後の値を `log_info` 行で出力し、運用者がログから設定を確認できるようにすること。
2. **`${VAR:-}` 形式を使用**:正当に未設定となりうる変数(env ファイルのオプション値)に対しては、裸の `${VAR}` を使わない(`-u` 配下では abort)。
3. **最終文が `[[ ... ]] && die` の関数**は明示的に `return 0` で終わること。成功パスで exit 1 を呼び出し元に漏らさないため。C.1 の事例を参照。
4. **末尾 `|| true`** は、失敗パスが本当に情報的(例: `curl ... | head -1 || true`)で、その後に空結果チェックが続く場合のみ許容。

### `&& die` パターン

パターン:

```bash
[[ -f "${REQUIRED_FILE}" ]] || die "Missing required file: ${REQUIRED_FILE}"
```

これは **関数の最終文でない限り** `set -e` 配下でも問題ない。最終文として使うと成功パスで関数が 1 を返す挙動になる(bash 仕様上の footgun として広く知られる)。C.1 で実際の事故を参照。

### libguestfs 呼び出し時のパターン

Phase 5 では `bin/build-image.sh` 呼び出し前に `LIBGUESTFS_BACKEND=direct` を設定する。これは libvirt の qemu ユーザー権限モデルを回避するために必須。C.6 参照。

---

## A.6 引数規約

### コマンドラインスイッチ

| スイッチ | 型 | 必須 | 説明 |
|---------|-----|-----|------|
| `--env <file>` | path | ✓ | env.properties ファイルパス |
| `--skip-prereq` | フラグ | | Phase 1(パッケージ導入)をスキップ |
| `--skip-aws-import` | フラグ | | Phase 6–8(VMDK 生成のみ)をスキップ |
| `--build-only` | フラグ | | `--skip-aws-import` の同義語 |
| `-h`, `--help` | フラグ | | ヘルプ表示後 exit 0 |

### 相互排他

- `--skip-aws-import` と `--build-only` は同義。両方指定は冗長だが許容(エラーにはせず通知のみ)。
- `--skip-prereq` は他フラグと独立。組み合わせ可能。

### 未知のスイッチ

`parse_args` は未認識スイッチに対して `die "Unknown option: $1"` を実行する。**黙って無視しないこと**。typo が CI 設定に紛れ込み、安全チェックを silent に無効化する経路となるため。

---

## A.7 env プロパティファイル規約

### ファイル形式

```
KEY="value"     # bash 代入。空白を許容するためクォート
# コメントは行頭 # から開始
```

ファイルは `source` でスクリプトの環境に読み込まれるため、bash として有効な構文であること。env ファイル内でのコマンド置換は避ける(セキュリティ・再現性のため)。

### 必須キー

| キー | 必須 | デフォルト | 注記 |
|------|-----|----------|------|
| `WORKSPACE` | ✓ | (なし) | world-traversable パスであること。C.3 参照 |
| `S3_BUCKET` | ✓\* | (なし) | `--build-only` 以外で必須 |
| `AWS_REGION` | ✓\* | (なし) | `--build-only` 以外で必須 |
| `ISO_URL` | | OL10 default | OL バージョンはこの URL から自動検出 |

\* AWS import フェーズを実行する場合のみ必須。

### オプション/自動導出キー

| キー | 自動デフォルト |
|------|--------------|
| `DISTR` | `ol${OL_MAJOR_VERSION}-slim` |
| `CLOUD` | `aws` |
| `AMI_NAME` | `OracleLinux-${MAJOR}-U${UPDATE}-x86_64-$(date +%Y%m%d-%H%M)` |
| `AMI_DESCRIPTION` | `Oracle Linux ${MAJOR} Update ${UPDATE} (x86_64) custom AMI built via oracle-linux-image-tools` |
| `BOOT_MODE_BUILD` | `bios`(Oracle ツールが AWS 向けに bios 強制) |
| `BOOT_MODE` | `legacy-bios`(`BOOT_MODE_BUILD` と整合必須) |
| `OS_VARIANT` | `detect_os_variant` で自動検出 |
| `ISO_CHECKSUM` | `derive_oracle_checksum_url` で自動解決 |

### パススルーキー(`oracle-linux-image-tools` が消費)

以下のキーは `build-ol-aws-ami.sh` 自身は解釈せず、上位ツール `oracle-linux-image-tools` の `bin/build-image.sh` が読み込む `env.properties.local` にそのまま書き込まれる。同梱されている `env.properties.aws-ol{7,8,9,10}` テンプレートに妥当なデフォルト値が設定されており、通常は変更不要。

| キー | 標準値 | 用途 |
|------|--------|------|
| `BUILD_NUMBER` | `0` | 上位ツール出力ファイル名のサフィックス |
| `SETUP_SWAP` | `No` | クラウド VM ではスワップ設定をスキップ |
| `SELINUX` | `enforcing` | 生成 AMI の SELinux モード |
| `ROOT_FS` | `xfs` | 生成 AMI のルートファイルシステム |
| `DISK_SIZE_GB` | `10` | AMI のルートボリュームサイズ |
| `SERIAL_CONSOLE_RUNTIME` | `Yes` | EC2 Serial Console を利用する場合に必須 |
| `CLOUD_INIT` | `Yes` | AMI で cloud-init を有効化 |
| `CLOUD_USER` | `ec2-user` | AWS 慣習の初回ログインユーザー |
| `KERNEL` | `uek`(OL7)/ 未設定(OL8 以上) | OL7 は UEK 必須(C.10 参照) |
| `UEK_RELEASE` | `6`(OL7 のみ) | UEK メジャーリリース。OL7 でのみ意味を持つ |
| `S3_KEY_PREFIX` | `ol${MAJOR}-ami-import` | `S3_BUCKET` 内のキープレフィックス |
| `VMIMPORT_ROLE_NAME` | `vmimport` | `setup-vmimport-role.sh` と一致させること |

`oracle-linux-image-tools` で上流側のキーが追加・改名・削除された場合は、テンプレートと本表を同期して更新する。

`UEK_RELEASE` についての補足: 上位ツールは `KERNEL=uek` のときのみこのキーを使う。OL7 では UEK6 のみが現実的に有効。OL8 以上では指定しても無害(distr レベルのデフォルトが優先される)。

### ファイル命名規則

```
env.properties.aws-ol{N}    N は 7、8、9、10 のいずれか
```

OL メジャーリリースごとに 4 つのテンプレートをリポジトリにコミット。利用者は編集前に `cp env.properties.aws-olN env.properties.local` を行う。`*.local` は git 除外対象。OL7 テンプレートは実験的扱い(B.3 / C.10 参照)。

---

## A.8 Oracle Linux バージョン自動検出

`load_env` は `parse_ol_version_from_iso` を呼び出し、`ISO_URL` から `OL_MAJOR_VERSION` と `OL_UPDATE_VERSION` を抽出する。正規表現:

```bash
OracleLinux-R([0-9]+)-U([0-9]+)
```

これは Oracle 公式の ISO 命名規約(OL7 から OL10 まで)にマッチする。OL7 の `Server-` 接中辞は正規表現が前方一致(完全一致ではない)のため自然にマッチする。検出された値は以下に伝播される。

- `DISTR`(例: `ol10-slim`、`ol7-slim`)
- `AMI_NAME` デフォルト
- `AMI_DESCRIPTION` デフォルト
- AMI タグ `OS=OracleLinux${MAJOR}U${UPDATE}`
- `detect_os_variant` の優先順位リスト
- `load_env` が出力する OL7 専用警告バナー
- `phase3_clone_repository` での OL7 パッチ適用トリガ

正規表現マッチに失敗した場合(独自 ISO URL、ミラーサイト等)、ユーザーは env ファイルで `OL_MAJOR_VERSION` と `OL_UPDATE_VERSION` を明示設定する必要がある。

### `detect_os_variant` の優先順位リスト

`OL_MAJOR_VERSION` / `OL_UPDATE_VERSION` から動的生成。

1. `oraclelinux${MAJOR}.${UPDATE}`(完全一致)
2. `oraclelinux${MAJOR}.${UPDATE-1}`, …, `oraclelinux${MAJOR}.0`
3. `oraclelinux${MAJOR}-unknown`, `oraclelinux${MAJOR}`
4. `rhel${MAJOR}.${UPDATE}`, …, `rhel${MAJOR}.0`, `rhel${MAJOR}-unknown`, `rhel${MAJOR}`(バイナリ互換)
5. `centos-stream${MAJOR}`, `centos-stream-${MAJOR}`(`MAJOR == 7` の場合は `centos7.0`、`centos7` も追加)
6. `oraclelinux${MAJOR-1}.10`, …, `oraclelinux${MAJOR-1}.0`, `oraclelinux${MAJOR-1}`(緩やかな縮退 — `MAJOR > 8` のときのみ適用)
7. `linux2024`, `linux2023`, `linux2022`, `linux2020`, `linux2018`, `linux2016`, `linux2014`(汎用フォールバック)

最初にマッチしたものが採用される。スクリプトはどの variant が選択されたかを `log_info` で出力し、(Native / Compatible / Older / Generic) として分類することで運用者の期待値を整える。OL7 では RHEL 系のビルドホストでもっとも現実的なマッチは `rhel7.9`(古い osinfo-db では `centos7`)になる。

---

## A.9 エラー・診断規約

### 3 階層の出力

1. **致命的**: `die "message"` → `log_error` + `exit 1`。パイプライン進行を妨げる条件で使用。
2. **縮退**: `log_warn "message"` → 実行継続。フォールバック適用時(例: osinfo-db に `oraclelinux10` エントリがなく `rhel10.1` を選択)に使用。
3. **情報**: `log_info "message"` → 通常進捗。

### 対処可能なエラーメッセージの必須形式

回復可能な誤設定で `die` する際、メッセージは必ず以下を含むこと。

1. **何が**起きたか(1 文)
2. **なぜ**問題か(1 文。原因が非自明な場合)
3. **どう**直すか(1 つ以上の具体的コマンドまたは env キー)

良い例:

```
[ERROR] BOOT_MODE_BUILD='uefi' is not supported for CLOUD=aws.
[ERROR]   oracle-linux-image-tools only accepts BOOT_MODE=bios for AWS targets.
[ERROR]   Set BOOT_MODE_BUILD="bios" in env.properties.local (or remove the line
[ERROR]   to use the default).
```

悪い例:

```
[ERROR] Invalid BOOT_MODE_BUILD
```

### 診断カテゴリ

| カテゴリ | 通常影響を受けるフェーズ | 回復ヒント |
|---------|---------------------|-----------|
| KVM/virt 未対応 | 0 | インスタンスタイプ切り替えまたは nested-virt 有効化 |
| コマンド未検出 | 0/1 | `--skip-prereq=0`(デフォルト)で実行 |
| qemu 権限 | 2/5 | 自動対処。手動フォールバックは `/var/tmp` へ |
| ISO チェックサム 404 | 4 | `ISO_CHECKSUM` の手動上書き |
| OS_VARIANT 検出不可 | 4 | osinfo-db 更新または `OS_VARIANT` 明示設定 |
| BOOT_MODE 不整合 | 4/8 | デフォルトに戻す |
| `virt-sparsify` 権限 | 5 | `LIBGUESTFS_BACKEND=direct`(自動設定済み) |
| `import-snapshot` クォータ | 7 | 待機またはクォータ増加申請 |

---

## A.10 バイリンガルドキュメント

### ファイルセット

| 英語 | 日本語 | 内容 |
|------|--------|------|
| `README.md` | `README.ja.md` | エンドユーザ向けドキュメント |
| `SPEC.md` | `SPEC.ja.md` | 開発者向け仕様書(本ドキュメント) |

### 同期規則

英語版を更新した場合は、必ず同じコミット(または英語コミットハッシュを参照する直後のコミット)で日本語版を更新する。以下の項目で同等性を維持すること。

- セクション構造(同じ H2 / H3 見出し)
- 表(同じ列構成)
- コードブロック(同じ内容。日本語ファイルではバイリンガルコメントも可)
- 例(同じコマンド。周辺の説明文は日本語化)

### 日本語版のスタイル

- 英語の技術用語は英語のまま維持(「phase」「qemu user」「libvirt」「WORKSPACE」「BOOT_MODE」「osinfo-db」「VMDK」などを翻訳しない)
- 句読点:「、」「。」「・」(全角)。「,」「.」は使わない
- 括弧:強調する用語に「」、コードスパンに ` `` `

### 必須のヘッダ・フッタセクション

各 README は以下を含むこと。

1. ファイル冒頭のバナー:言語切替リンク、リポジトリリンク、AI 生成コンテンツ警告
2. ファイル末尾の「Provenance and License」セクション:AI ツール、生成日、AS-IS 免責、Issue トラッカーリンク

各 SPEC は以下を含むこと。

1. ファイル冒頭の目的ブロック(「最も重要な規則」を参照)
2. もう一方の言語版 SPEC ファイルへの相互リンク

---

## A.11 開発ワークフロー

### イテレーションサイクル

```
1. 実 AWS ビルドで問題を再現するか、対象関数(parse_ol_version_from_iso、
   detect_os_variant など)のユニットテストを書く
2. build-ol-aws-ami.sh のコードを修正
3. bash -n build-ol-aws-ami.sh                  ← 構文ゲート:必ず通過
4. shellcheck --severity=warning ...            ← lint ゲート:警告 0 必須
5. 影響を受けるフェーズを AWS 上で再実行         ← 機能ゲート
6. 挙動や契約に変更があれば README(en + ja)と SPEC(en + ja)を更新
7. コミット
```

### リビジョン規律

(\*2) リポジトリの `r47` 形式の番号付けとは異なり、本スクリプトはソースにリビジョン番号を埋め込まない。代わりに `ai-generated-artifacts` リポジトリのコミットハッシュが正規のリビジョン識別子。

以下を変更するコミットでは、スクリプトヘッダの AI 生成日スタンプを更新する。

- フェーズセマンティクス(9 フェーズのいずれか)
- 出力形式(ログマーカー、バナーレイアウト)
- パラメータセット(スイッチの追加・削除・改名)

メッセージ内の typo 修正や README の表現修正のような外見上のみの変更は、ヘッダ日付の更新を要さない。

### 発明より再利用

新ヘルパー関数を書く前に以下を確認すること。

1. 既存スクリプトで等価なものを検索(`grep -n '^[a-z_]*()' build-ol-aws-ami.sh`)
2. 見つかれば、並行ヘルパー追加ではなく既存のものを拡張
3. 真に新しい場合は、ファイル末尾ではなく関連ヘルパー(出力/検出/AWS)の近くに配置

---

# Part B — スクリプト個別仕様

## B.1 `build-ol-aws-ami.sh`

### 識別情報

- ヘッダバナーは 8 セクションの枠線ブロック(Purpose、Prerequisites、Usage examples、Pipeline phases、Options、Known limitations、AI generation info)を含む。
- `usage()` ヘルパーがヘッダバナーを `sed` で抽出し `--help` で出力する。終端パターンは `^#==============`。

### 入力

| 入力 | 出所 |
|------|------|
| ビルド設定 | `--env <file>` 引数 |
| ISO ダウンロード | env ファイルの `ISO_URL` |
| ISO チェックサム | `linux.oracle.com/security/gpg/checksum/` から自動解決 |
| ビルドツール本体 | `git clone https://github.com/oracle/oracle-linux.git --depth 1` |
| AWS 認証情報 | 標準 `aws-cli` 解決チェーン |

### 出力

| 出力 | 場所 |
|------|------|
| VMDK | `${WORKSPACE}/OL${MAJOR}U${UPDATE}_x86_64-aws-b0/*.vmdk` |
| S3 オブジェクト | `s3://${S3_BUCKET}/${S3_KEY}`(S3_KEY = `ol-ami-import/<timestamp>-<basename>`) |
| EBS スナップショット | `${AWS_REGION}` 内の `${SNAPSHOT_ID}` |
| AMI | `${AWS_REGION}` 内に登録された `${AMI_ID}` |

### フェーズ固有の挙動(本スクリプト固有)

- **Phase 0** は 3 ケースの EC2 自己診断(`guide_ec2_kvm_issue`)を持つ:
  - Case A: ファミリは nested-virt 対応だが未有効化
  - Case B: ファミリが nested-virt 非対応
  - Case C: bare-metal インスタンスだが kvm モジュール未ロード
- **Phase 2** の ACL ウォークは `${HOME}` ではなく `/` で終端する。`/root` 配下のビルドが失敗するのを防ぐため(`/root` には `o+x` がない)。
- **Phase 4** は文字列補間で上位ツール用 `env.properties.local` を生成(`envsubst` は不使用)。オプション値は `${KEY:+KEY=${KEY}}` 形式で出力/省略を切り替える。
- **Phase 5** は `bin/build-image.sh` 呼び出し前に明示的に `LIBGUESTFS_BACKEND=direct` を export する。C.6 参照。
- **Phase 7** のポーリングループは 90 分のハードタイムアウト(60 秒 × 90 反復)を持ち、describe-import-snapshot-tasks API の失敗は一時的(retry、abort しない)として扱う。
- **Phase 8** は `BOOT_MODE` が `uefi` または `uefi-preferred` の場合のみ `--tpm-support v2.0` を条件付きで追加する。`legacy-bios` AMI に NitroTPM は組み合わせ不能。

### 既知の制約

各項目の歴史的経緯は Part C を参照。

- x86_64 のみ。aarch64 AMI ビルドは現状実装不可(`oracle-linux-image-tools` の AWS target は x86_64 専用)
- AWS の `BOOT_MODE=bios` のみ動作する組み合わせ。`legacy-bios` AMI は NitroTPM や UEFI Secure Boot を使えないが、すべての Nitro インスタンスタイプで起動可能
- `import-snapshot` は AWS アカウントごとにレート制限あり(デフォルト 5 並行)

---

## B.2 `setup-vmimport-role.sh`

### 識別情報

AWS VM Import/Export に必要な `vmimport` IAM サービスロールを作成する小さな(初回のみ実行する)ヘルパー。**9 フェーズパイプラインの一部ではない**。AWS アカウントごとに初回ビルド前に 1 度だけ実行する。

### 入力

```
./setup-vmimport-role.sh <S3_BUCKET> [ROLE_NAME]
```

| 位置引数 | 必須 | デフォルト |
|---------|-----|----------|
| `S3_BUCKET` | ✓ | (なし) |
| `ROLE_NAME` | | `vmimport` |

### 出力

- 標準的な `vmimport` 信頼ポリシー付きの IAM ロールを作成
- 指定バケットにスコープされたインラインポリシー `vmimport-${S3_BUCKET}` を付与

### 冪等性

同名のロールが既存の場合、上書きせず `die` する。異なるバケットにロールを scope したい場合は、カスタム `ROLE_NAME` を使うか手動で付与済みポリシーを編集する。

### 既知の制約

- 信頼ポリシーは SID `vmimport` をリテラルで使用し、サービスプリンシパル `vmie.amazonaws.com` がパーティションに存在することを前提とする。商用 AWS リージョンでは動作するが、GovCloud や中国 region のユーザーは信頼ポリシーの編集が必要。

---

## B.3 `env.properties.aws-ol{6,7,8,9,10}`

### 識別情報

サポートする OL メジャーリリースごとに 1 つずつ、計 5 つの付随テンプレート。本ディレクトリにコミットされており、編集前に `env.properties.local` にコピーすべきもの。

OL7 テンプレートは実験的扱い — 上流の AWS クラウドターゲットに対して OL7 が動作するようにするランタイムパッチの根拠は C.10 を参照のこと。

OL6 テンプレートはさらに実験的扱い: アップストリームには `distr/ol6-slim/` ディレクトリ自体が存在しないため、本ラッパーは 2 種類のランタイム `sed` パッチに加えて、このディレクトリを実行時に動的生成します。設計根拠は B.4 と C.11〜C.15、OL6 全体アーキテクチャは Part D を参照のこと。

### テンプレート間の差異

| キー | OL10 | OL9 | OL8 | OL7 | OL6 |
|------|------|-----|-----|-----|-----|
| `WORKSPACE` | `/tmp/ol10-build-ws` | `/tmp/ol9-build-ws` | `/tmp/ol8-build-ws` | `/tmp/ol7-build-ws` | `/tmp/ol6-build-ws` |
| `DISTR` | `ol10-slim` | `ol9-slim` | `ol8-slim` | `ol7-slim` | `ol6-slim`(動的合成) |
| `ISO_URL` | OL10 U1 | OL9 U7 | OL8 U10 | OL7 U9(`Server-` 接中辞付き) | OL6 U10(`Server-` 接中辞付き) |
| `# OS_VARIANT` 例示 | `rhel10.1` | `rhel9.7` | `rhel8.10` | `rhel7.9` | `ol6.10` |
| `# AMI_NAME` 例示 | `OracleLinux-10-U1-...` | `OracleLinux-9-U7-...` | `OracleLinux-8-U10-...` | `OracleLinux-7-U9-...` | `OracleLinux-6-U10-...` |
| `KERNEL` | 未設定(distr デフォルト) | 未設定 | 未設定 | `uek`(必須 — C.10 参照) | `uek`(必須 — C.12 参照) |
| `UEK_RELEASE` | 未設定 | 未設定 | 未設定 | `6`(OL7 で唯一現実的な UEK) | `4`(OL6 で唯一現実的な UEK) |
| `ROOT_FS` | 未設定(xfs デフォルト) | 未設定 | 未設定 | `xfs`(上流 OL7+ では xfs/btrfs/lvm のみ可) | `xfs`(xfs または ext4 が可。`/boot` は ext4 を維持 — B.4 / C.16 参照) |
| `BOOT_MODE_BUILD` | 未設定 | 未設定 | 未設定 | `bios` | `bios` |
| ファイル冒頭警告バナー | なし | なし | なし | EOL / パッチ / 本番禁止の旨を記載 | EOL / **パッチ 2 種** / `distr/` ランタイム合成 / 本番禁止の旨を記載 |

### バージョン横断で共通化された項目

以下のキーは全 5 テンプレートで意図的に同一値に揃えられており、運用者は任意のテンプレートを `env.properties.local` にコピーし、`# AMI_NAME` 行(と必要に応じて `WORKSPACE`)だけ書き換えれば動かせる構成になっています。

| キー | 共通値 | 理由 |
|------|--------|------|
| `S3_BUCKET` | `my-oracle-linux-ami-import-bucket` | 1 つの IAM ロール(`vmimport`)と 1 つの S3 バケットで全バージョンをカバー。バージョンごとの分離は `S3_KEY_PREFIX` で実現。B.3.1 参照。 |
| `AWS_REGION` | `""`(空) | ランタイムに IMDSv2 → IMDSv1 → `ap-northeast-1` の順で動的解決。B.3.2 と §B.1 の `resolve_aws_region()` 解説を参照。 |
| `UPDATE_TO_LATEST` | `"yes"` | ISO ベースインストール完了後、ゲスト VM 内で `dnf/yum update -y` を実行し、ISO リリース以降の kernel および userspace の CVE を取り込み。B.3.3 参照。 |

### B.3.1 全バージョン共通の `S3_BUCKET` と `vmimport` IAM ロール

リファクタリング前は、各 env テンプレートにバージョンごとのバケット名(`my-ol10-ami-import-bucket`、`my-ol9-ami-import-bucket`…)が含まれており、運用者は以下のいずれかが必要でした:

- `setup-vmimport-role.sh` を 5 回実行(バケットごとに 1 回ずつ。後続実行が前のトラストポリシーを上書き)
- `vmimport-policy` JSON の `Resource` 配列を手動編集して 5 バケットを列挙

統一バケット `my-oracle-linux-ami-import-bucket` 方式により、これらの運用負担はいずれも解消されました。`setup-vmimport-role.sh` は **AWS アカウントごとに 1 回**、この単一のバケット名で実行するだけです。以降の `build-ol-aws-ami.sh` 呼び出しは同じロールポリシーを変更なしで再利用します。バージョンごとの VMDK 分離は各 env テンプレートの `S3_KEY_PREFIX="ol{N}-ami-import"` で確保されており、ステージ済みオブジェクトは `s3://my-oracle-linux-ami-import-bucket/ol{N}-ami-import/...` に格納されます。

S3 バケット自体は `phase6_upload_to_s3` 内で未作成の場合に自動生成されます(public access はブロック)。運用者が事前作成する必要はありません。

### B.3.2 動的な `AWS_REGION` 解決

`build-ol-aws-ami.sh` 内の `resolve_aws_region()`(`load_env` から呼び出し)が以下の 3 段階解決チェーンを実装します:

| ステップ | ソース | 方法 | コスト |
|---------|--------|------|--------|
| 1 | env ファイル(明示指定) | `AWS_REGION` が非空ならチェーンを短絡 | 0 |
| 2a | IMDSv2 | `curl PUT /latest/api/token` でトークン取得後、トークン付きで `GET /latest/meta-data/placement/region` | 最大 2 × 2 秒 |
| 2b | IMDSv1 | `curl GET /latest/meta-data/placement/region`(トークン無し)。ステップ 2a がトークンを返さなかった場合のみ実行 | 最大 1 × 2 秒 |
| 3 | フォールバック定数 | `AWS_REGION="ap-northeast-1"` | 0 |

関数は `AWS_REGION_SOURCE` を `env` / `imdsv2` / `imdsv1` / `fallback` に設定し、選択結果は `load_env` のバナーに表示されます:

```
[INFO] AWS_REGION         = us-east-1 (source: imdsv2)
```

**v2 と v1 を両方サポートする理由**: AWS はセキュリティ上 v2 を推奨(トークンで SSRF を緩和)していますが、2024 年半ば以前に起動された EC2 インスタンスは `HttpTokens=optional` の可能性があり、v1 でも動作します。`HttpTokens=disabled` のインスタンス(まれですが有効な設定)では PUT が失敗し、v1 で取得できます。`HttpTokens=required` のインスタンス(モダンなハードニング済みデフォルト)では v1 は 401 を返すため、本ラッパーはフォールバック定数まで進みます。各 curl 呼び出しは `--max-time 2` で 2 秒に制限されているため、両 IMDS 呼び出しが失敗してもレイテンシ予算は約 4 秒以内に収まります(オンプレミスホストなどメタデータサービスが存在しない場合の典型)。

**フォールバックに `ap-northeast-1` を選んだ理由**: リファクタリング前のバージョンごとテンプレートの歴史的デフォルトと一致し、また本ラッパーの end-to-end 検証時のビルドホストリージョンとも一致するため。他リージョンで運用する場合は `env.properties.local` で `AWS_REGION` を明示してください。

### B.3.3 `UPDATE_TO_LATEST` のラッパー層パススルー

アップストリームの `distr/ol{N}-slim/env.properties` 全ファイルが `UPDATE_TO_LATEST="yes"` をデフォルトとしているため、本ラッパーが何も指定しなくても `distr::configure` 内で `dnf update -y`(OL8/9/10)または `yum update -y`(OL6/7)が実行されます。リファクタリング前のラッパーはこの暗黙のデフォルトに依存しており、ログ出力も一切なかったため、運用者はラッパー層の env ファイルからアップデートの有無を判別できませんでした。

リファクタリング後:

1. 全ラッパー層 env テンプレートで `UPDATE_TO_LATEST="yes"` を明示宣言し、許容される 3 値(`yes` / `security` / `no`)をまとめたコメントブロックを付加。
2. `phase4_prepare_env_properties` が生成する `env.properties.local` に `${UPDATE_TO_LATEST:+...}` 行を出力。運用者が `yes` 以外(例: バイト単位再現性のためのビルドで `no`)に設定したオーバーライドが、暗黙に無視されることなくアップストリーム層まで届きます。
3. OL6 ランタイム生成版 `distr/ol6-slim/env.properties` テンプレート(`phase3_clone_repository` 内の heredoc で出力)も同じ `UPDATE_TO_LATEST="yes"` デフォルトを持ち、合成版 `distr::common_cfg` が同じ env レイヤーオーバーライド機構経由でラッパー指定値を尊重します。

本変更はドキュメンテーションとログ出力主体の改修です。env ファイルを変更しない場合のランタイム挙動はリファクタリング前と同じ(暗黙のアップストリームデフォルト `yes` により同じ `dnf update -y` が実行される)です。

### 保守規則

新しい Oracle Linux Update がリリースされたとき(例: OL10 U2):

1. OL10 テンプレートの `ISO_URL` を新リリースに更新
2. `# OS_VARIANT` と `# AMI_NAME` のコメント例示値を更新
3. スクリプト変更は不要 — `parse_ol_version_from_iso` と `detect_os_variant` が自動追従

新しい Oracle Linux メジャーリリースがリリースされたとき(例: OL11):

1. `env.properties.aws-ol11` を追加(OL10 からコピーして 10→11 置換)
2. README と SPEC の表に対応行を追加
3. Oracle が `OracleLinux-R{N}-U{M}` の ISO 命名規約を維持する限り、スクリプト変更は不要

上流が OL7 の `cloud=aws` チェックを書き換えた場合:

1. `phase3_clone_repository` の `sed` パターンを再評価する。現在のパターンは `AWS images builder only supports OL8 and above` という厳密な文字列でアンカーされている
2. 上流が OL7 ブロックを完全に削除した場合、`grep -Fq` ガードによりパッチは no-op になり、`log_warn` で運用者に通知される。強制的な動作変更は発生しない
3. 上流がチェックを意味論的に異なる形(例: 許可リスト方式)に置き換えた場合、OL7 パッチは再設計が必要。本セクションと `phase3_clone_repository` のコメントを一緒に更新すること

---

## B.4 OL6 ランタイム合成(`distr/ol6-slim/` + `cloud/aws/` パッチ)

### 識別情報

OL6 のサポートは OL7 とは異なる仕組みで実現しています。OL7 が「すでに完全な OL7 配布物に対して 1 種類のランタイム `sed` パッチを当てる」だけで済むのに対し、OL6 では **2 種類のランタイム `sed` パッチに加えて、アップストリームに存在しない `distr/ol6-slim/` ディレクトリ全体をランタイムで合成**する必要があります。これらすべては `build-ol-aws-ami.sh` の `phase3_clone_repository` 内で `OL_MAJOR_VERSION == 6` でガードされて適用されます(パッチ #1 のみ OL7 と共用、`-le 7` でガード)。

### ラッパーパッチマーカー規約

本ラッパーが上流の作業ツリーに加えるすべての改変は、`grep -r '\[ol-aws-ami-builder' "${WORK_REPO_DIR}"` で発見可能でなければなりません。正規のマーカー形式:

```
[ol-aws-ami-builder OL{N} PATCH {short-tag}]
```

`{N}` は OL メジャーバージョン(6, 7, ...)、`{short-tag}` は識別子(各 OL メジャーに 1 種類しかない場合は省略)。現在のマーカー一覧:

| マーカー | パッチ対象ファイル | 目的 |
|----------|------------------|------|
| `[ol-aws-ami-builder OL6 PATCH]` | `cloud/aws/image-scripts.sh` | OL8+ ガードの除去(OL6 モード) |
| `[ol-aws-ami-builder OL7 PATCH]` | `cloud/aws/image-scripts.sh` | OL8+ ガードの除去(OL7 モード) |
| `[ol-aws-ami-builder OL6 PATCH kernel-uek-modules]` | `cloud/aws/provision.sh` | OL6 で `kernel-uek-modules` インストールをスキップ |

各パッチはパッチ済みファイルの隣に `.bak` バックアップを残し、適用前に `grep -Fq` で冪等性ガードを行うため、既存 clone への再適用が二重に行われることはありません。

### `sed` 実行規約

1. **デリミタ**: シェルのパス区切り `/` やコメント `#` と衝突しないよう、`|`(パイプ)を優先する。
2. **アンカー**: 該当行を一意に識別できる固定文字列をアンカーに使う(パッチ #1 は `AWS images builder only supports OL8 and above`、パッチ #2 は `yum install -y "${YUM_VERBOSE}" kernel-uek-modules`)。
3. **冪等性**: 置換前に `grep -Fq '[ol-aws-ami-builder OL{N} PATCH ...]'` を行い、適用済みなら info ログを出してスキップする。
4. **検証**: 置換後に再度マーカー grep を行い、見つからなければ `die` する(Phase 5 で不明瞭なエラーになるのを避ける)。
5. **インデント保存のためのキャプチャグループ**: 上流の行頭に空白がある場合(例: `    yum install ...`)、`\(\s*\)` でキャプチャし `\1` で参照することでインデントを保持する。
6. **GNU sed 拡張は使用可**: 本ラッパーは GNU sed を持つビルダー(Amazon Linux 2/2023、Oracle Linux 8/9/10、RHEL 9/10)で動作することを前提とするため、置換テキスト中の `\n` は使用可。BSD/macOS sed は非サポート。

### `distr/ol6-slim/` のランタイム生成

4 つのファイルは `cat > {path} <<'EOF_OL6_*'` ヒアドキュメントブロックを連続して実行することで書き出します。シングルクォート版のデリミタが**必須**です:

```bash
cat > "${ol6_slim_dir}/provision.sh" <<'EOF_OL6_PROV'
...
EOF_OL6_PROV
```

シングルクォートで囲むことにより**ラッパー実行時の変数展開を抑止**し、`${YUM_VERBOSE}`、`${ROOT_FS,,}`、`${KERNEL^^}` などの参照を文字どおりに保存します。これらは後段の `oracle-linux-image-tools` 実行時に展開されます(意図したとおりの動作)。

埋め込みの内側ヒアドキュメント(例: `cat > /etc/dracut.conf.d/... <<EOF`)については、タブを strip する `<<-EOF` 形式ではなく**先頭空白なしの `<<EOF` を使用**します。これによりエディタやツールがラッパーを再処理した際のタブ/スペース変換に依存しなくなります。

### `distr/ol7-slim/` との同期

`distr/ol7-slim/` がアップストリーム側で構造的に変化した場合(`image-scripts.sh` の関数シグネチャ、kickstart セクションの順序、provision フェーズの契約など)、OL6 のヒアドキュメントテンプレートも併せて見直し更新が必要です。本ラッパーは `distr/ol7-slim/` からランタイムで何も継承しません — トレーサビリティ確保のため、OL6 用テンプレートは完全に自己完結としています。

### 保守規則(OL6)

`oracle-linux-image-tools` がリファクタされた場合:

1. `cloud/aws/image-scripts.sh` の `cloud::validate()` から OL8+ ガードが消えた場合、パッチ #1 は静かに no-op になります(`grep -Fq` ガードが `log_warn` を出します)。ビルド失敗が後段で発生しない限り強制的な対応は不要です。
2. `cloud/aws/provision.sh` の `kernel-uek-modules` インストール行が削除または改名された場合、パッチ #2 も静かに no-op になります。OL6 はそれでも動作する想定です(存在しないパッケージのインストールが行われなくなるため)。
3. `distr/ol7-slim/` の構造変更(関数シグネチャ、`common::distr_cleanup` / `common::latest_kernel` などの共通ヘルパー名)が発生した場合、`phase3_clone_repository` 内の OL6 用ヒアドキュメントテンプレートを手で更新する必要があります。これがアップストリームドリフトに対して最もリスクの高い領域です。

---

# Part C — 既知の落とし穴と教訓

将来のリビジョンで既に修正済みの問題が再発しないよう、記録しています。

## C.1 `parse_args` の最終文 `&& die` が exit 1 を漏らす

**症状**: `parse_args` リターン直後に何のログも出さずスクリプトが exit code 1 で silent に終了した。

**根本原因**: `parse_args` の最終文が `[[ ! -f "${ENV_FILE}" ]] && die "..."` だった。ファイルが存在する場合、`[[ ]]` は 1(false)を返し、`die` は正しくスキップされる — しかし `&&` 式全体の終了コード(1)が関数のリターン値となる。呼び出し元の `set -e` と組み合わさり、スクリプトが abort した。

**修正**: `parse_args` 末尾に明示的な `return 0` を追加。本事故を受けて A.5 #3 の防御的コーディング規則が追加された。

## C.2 Oracle が ISO チェックサムの公開先 URL を変更

**症状**: OL10 に対して `curl ${ISO_URL}.sha256sum` が HTTP 404 を返した。

**根本原因**: OL9 以降、Oracle はチェックサムファイルを `https://linux.oracle.com/security/gpg/checksum/OracleLinux-R{N}-U{M}-Server-{arch}.checksum`(GPG 署名付き、複数ファイル束ね形式)で公開している。ISO ごとの `.sha256sum` ファイルは廃止された。

**修正**: `derive_oracle_checksum_url` がフォールバックチェーン(ユーザー指定 → 旧式 `.sha256sum` → 新式 Oracle URL)を構築する。取得後はファイル本体を ISO ファイル名で `grep` し、64 文字の hex 正規表現で抽出値を検証。

## C.3 qemu ユーザー(uid 107)が `/root` を traverse できない

**症状**: `WORKSPACE` を `/root` 配下に置いた状態で Phase 5(`virt-install`)が `Cannot access storage file '...' (as uid:107, gid:107): Permission denied` で失敗。

**根本原因**: システムモード(`qemu:///system`)の libvirt は qemu を非 root ユーザー(RHEL 系は `qemu`、Debian 系は `libvirt-qemu`)として起動する。`/root` は通常 mode 0700 で、traverse できない。

**修正**: Phase 2 を追加し、`WORKSPACE` の親ディレクトリ連鎖を `/` まで遡り、qemu ユーザーが既に traverse できない箇所に `setfacl -m u:qemu:x` を適用する。ACL 拡張パッケージ(`acl`)を Phase 1 に追加。

さらに、デフォルト `WORKSPACE` を `/tmp/ol{N}-build-ws` に移行。`/tmp` は world-traversable(mode 1777)であり、新規ホストでは問題そのものを回避できる。

## C.4 Oracle の `build-image.sh` が AWS に対し `BOOT_MODE=bios` を強制

**症状**: Phase 5 が `AWS images only supports bios BOOT_MODE` で abort。

**根本原因**: Oracle 上位の `cloud/aws/image-scripts.sh` が AWS target に対し `BOOT_MODE=bios`(大文字小文字区別あり)を強制する。スクリプトの旧デフォルトである `hybrid` は拒否された。

**修正**: デフォルトを `BOOT_MODE_BUILD=bios` と `BOOT_MODE=legacy-bios` に変更。`load_env` が AWS 組み合わせを検証し、ユーザーが `uefi` や `hybrid` を設定した場合は対処可能なメッセージで early-fail する。

帰結:結果として生成される AMI で NitroTPM と UEFI Secure Boot は使用できなくなる。AMI はすべての Nitro インスタンスタイプで起動可能。

## C.5 RHEL 10 ホストの osinfo-db に `oraclelinux10` エントリがない

**症状**: RHEL 10 ビルドホストで Phase 5 が `can't determine OS_VARIANT; you must define it in your environment file` で abort。

**根本原因**: Red Hat の osinfo-db パッケージは Oracle Linux エントリを同梱しない。`osinfo-query` の `oraclelinux10*` 検索結果は空。

**修正**: `detect_os_variant` を動的化し、`OL_MAJOR_VERSION` から候補リストを生成。同じメジャーの RHEL(バイナリ互換)、次に CentOS Stream、次に汎用 `linuxYYYY` にフォールバック。RHEL 10 ホストでは `rhel10.1` が選択される — 優れた代替。

分類メッセージは「Native」(oraclelinux{N})、「Compatible」(rhel{N} / centos-stream{N})、「Older」(oraclelinux{N-1})、「Generic」を区別し、運用者が選択結果を解釈できるようにしている。

## C.6 `virt-sparsify` が mkdtemp(3) の mode 0700 で権限失敗

**症状**: Phase 5 末尾(OS インストールと `virt-customize` 成功後)で `virt-sparsify` が以下のエラーで失敗:

```
Cannot access storage file '.../tmp.XXXXX/sparsifyXXX.qcow2'
(as uid:107, gid:107): Permission denied
```

**根本原因**: `virt-sparsify` は `mkdtemp(3)` で一時オーバーレイサブディレクトリを作成するが、`mkdtemp(3)` は常に mode 0700 を設定する。libvirt の qemu ユーザー(uid 107)は所有していない 0700 ディレクトリを traverse できず、POSIX デフォルト ACL は umask 由来の有効マスクを上書きできない。

**修正**: Phase 5 で `bin/build-image.sh` 呼び出し前に `LIBGUESTFS_BACKEND=direct` を export する。「direct」バックエンドは呼び出し側ユーザー(root)として qemu を実行し、libvirt を完全にバイパスする。これは libguestfs ベースのツール(virt-customize、virt-sysprep、virt-sparsify)にのみ影響する。同じフェーズの `virt-install` は libvirt 経由で実行されるため、Phase 2 の ACL 修正は引き続き必要。

## C.7 RHEL 10 のモジュラー libvirt(`virtqemud`)

**症状**: `systemctl enable --now libvirtd` が RHEL 10 で失敗(該当 unit が存在しない)。

**根本原因**: RHEL 9+ / Fedora 35+ / Debian 12+ では libvirt がモジュラーデーモン(`virtqemud`、`virtnetworkd`、`virtstoraged`)構成で同梱され、モノリシックな `libvirtd` は廃止された。

**修正**: Phase 1 で両方の unit 名を試行し、存在するほうを有効化する。`systemctl list-unit-files` で先にチェックすることで、失敗時は `die` ではなく `log_warn` で済ませる(別経路でデーモンが動いている host を想定)。

## C.8 `.metal` インスタンスのパターンが間違った case 分岐にマッチ

**症状**: `c5n.metal` ホストで `guide_ec2_kvm_issue` が「ファミリは nested-virt 非対応」(Case B)メッセージを出し、すでに bare-metal インスタンスを使っている運用者を混乱させた。

**根本原因**: `family=$(echo ${instance_type} | sed -E 's/\.[^.]+$//')` が `case` 文実行前に `.metal` サフィックスを削除するため、`c5n.metal` が `c5n` になり、metal 判定パターン(`*.metal`)がマッチしなかった。

**修正**: ファミリに縮約する前に、完全な `instance_type` を `*.metal` および `*.metal-*` パターンと照合する。チェック順は以下のとおり:

1. 完全タイプが metal パターンにマッチ → Case C(kvm モジュール未ロード)
2. それ以外でファミリが nested-virt 対応リストに含まれる → Case A(nested-virt 有効化)
3. それ以外 → Case B(インスタンスファミリ変更)

## C.9 Phase ポーリングループで空 status 時に無限ループ

**症状**: `describe-import-snapshot-tasks` が空の `Status` フィールドを返した場合(AWS API の一時的問題)、Phase 7 が無限にハング。

**根本原因**: 元のループは空 status の扱いもハードタイムアウトも持たなかった。空入力に対する `case "${status}"` はどの分岐にもマッチせず、`sleep 60` に戻ってループを継続した。

**修正**: 空文字列の明示的な検出(一時的とみなし retry)と 90 分のハードタイムアウト(60 秒 × 90 反復)を追加。API 失敗は `|| true` で catch して retry。

## C.10 アップストリームが OL7 を AWS クラウドターゲットで拒否

**症状**: `DISTR=ol7-slim` と `CLOUD=aws` を指定して Phase 5 を実行すると、以下のメッセージで即座に中断される。

```
ERROR: AWS images builder only supports OL8 and above
```

**根本原因**: `oracle-linux-image-tools/cloud/aws/image-scripts.sh` が定義する `cloud::validate()` 内に、以下のハードガードがある。

```bash
[[ ${ORACLE_RELEASE} -lt 8 ]] && common::error "AWS images builder only supports OL8 and above"
```

このガードは初期 AWS サポートと同時に導入(上流 CHANGELOG, 2026 年 3 月)されたものであり、OL7 Premier Support の EOL(2024-12-31)よりも後に追加されている。拒否は技術的非互換ではなくポリシー判断: OL7 の UEK6 は Amazon ENA ドライバを含み、`cloud-init` も入手可能で、`cloud::install_aws_packages` 内の `kernel-uek-modules` も正しく解決する。

**修正**: `phase3_clone_repository` は clone 後に `OL_MAJOR_VERSION -eq 7` を検出し、作業コピー側の `cloud/aws/image-scripts.sh` の該当行を no-op に書き換える。

```bash
  : # [ol-aws-ami-builder OL7 PATCH] upstream OL7 block removed (see build-ol-aws-ami.sh phase3)
```

書き換えは `sed -i.ol7-patch.bak …` で行われ、デリミタとして `|` を使用する(`#` はシェルコメント開始記号として置換テキスト内で意味を持つため避ける)。元の行は `cloud/aws/image-scripts.sh.ol7-patch.bak` に保存される。

**ガード機構**:

1. 置換前に `grep -Fq 'AWS images builder only supports OL8 and above'` で該当行の存在を確認。行が存在しない場合(上流が削除・修正済み)、パッチをスキップして `log_warn` で「新しい上流バリデーションに従う」旨を通知する。
2. 置換後に `grep -Fq '[ol-aws-ami-builder OL7 PATCH]'` でマーカーの存在を確認。マーカーが見つからない場合、Phase 5 で不明な失敗が起きる前に `die` する。
3. 置換後の行はリテラル `:` no-op であり、`cloud::validate()` が後でリファクタされても bash 構文上の正当性を保つ。

**意図的に対応していないこと**:

- パッチは AWS 固有の OL7 ブロックのみを削除する。OL7 ディストリ自体は `BOOT_MODE=bios` を強制する(`bin/build-image.sh`: `OL7 only supports bios BOOT_MODE`)。これは AWS の要件と一致するため矛盾しない
- `KERNEL=rhck` は理屈上 OL7 でも到達可能だが、`cloud::install_aws_packages` が要求する `kernel-modules` パッケージを OL7 の RHCK は分割していない。OL7 env テンプレートは `KERNEL=uek` と `UEK_RELEASE=6` をハードコードしてこの罠を回避する
- aarch64 は対応しない: OL7 の `distr/` には `_aarch64` バリアントが無く、上流の AWS バリデータも `*_aarch64` を拒否する。両方のブロッカーが OL7 ではそのまま残る

**将来への対応**: 将来の上流コミットで OL7 チェックが別の場所(例: `bin/build-image.sh` 内)に移動した場合、既存パッチは no-op となり、新しいパッチ箇所の追加が必要になる。書き換え後の行に含まれる `[ol-aws-ami-builder OL7 PATCH]` マーカーは意図的に独特な文字列にしてあり、clone ツリー内で `grep -r` してラッパーが適用したパッチを全て発見できる。

---

## C.11 OL6/UEKR4 には `kernel-uek-modules` パッケージが存在しない

**症状**: 上流の `cloud/aws/provision.sh` の `cloud::install_aws_packages()` を OL6 で実行すると、`yum install -y "${YUM_VERBOSE}" kernel-uek-modules` の行が `No package kernel-uek-modules available` で失敗する。

**根本原因**: `kernel-uek-modules` は OL7 / UEK6 で導入された**カーネルモジュール分割パッケージ**で、本体の `kernel-uek` RPM を小さく保つために設けられたもの。OL6 の UEKR4(`4.1.12-124.x`)にはこの分割が存在せず、ENA / NVMe / virtio / xen / Hyper-V を含むすべてのドライバ `.ko` ファイルは本体 `kernel-uek` RPM に同梱されている。`https://yum.oracle.com/repo/OracleLinux/OL6/UEKR4/x86_64/repodata/primary.xml.gz` を検証して `kernel-uek-modules-*` エントリが存在しないことを確認済み。

**対処**: `phase3_clone_repository` は OL7 と共用の `image-scripts.sh` パッチに加えて、`provision.sh` 用の二つめのランタイムパッチを適用し、該当行を `ORACLE_RELEASE >= 7` でガードする:

```bash
# [ol-aws-ami-builder OL6 PATCH kernel-uek-modules] OL6/UEKR4 has no separate kernel-uek-modules package (modules bundled in kernel-uek)
[[ "${ORACLE_RELEASE}" -ge 7 ]] && yum install -y "${YUM_VERBOSE}" kernel-uek-modules
```

`&&` のショートサーキットにより、OL6 では行が no-op に、OL7+ では従来通りの挙動を保持する。

**ガードレール**:

1. 置換前の冪等性チェック: `grep -Fq '[ol-aws-ami-builder OL6 PATCH kernel-uek-modules]'`
2. 元の行の存在チェック: `grep -Fq 'yum install -y "${YUM_VERBOSE}" kernel-uek-modules'`(上流で削除されていた場合、パッチをスキップして `log_warn`)
3. 置換後のマーカー grep が見つからない場合は `die`(パッチ適用失敗を明示的に検出)

**検証**: AMI 起動後に `lsmod | grep -E '^(ena|nvme)'` と `modinfo ena nvme nvme_core` でドライバの読み込み確認。これは Phase C-4 で行うが、作者によりまだ実行されていない。

---

## C.12 OL6 + UEK4 のみが AWS Nitro 互換の唯一の組み合わせ

**症状**: `KERNEL=uek` かつ `UEK_RELEASE=2` または `UEK_RELEASE=3` で OL6 AMI をビルドすると、Nitro インスタンスで `kernel panic: no driver for 0000:00:05.0`(ENA デバイス)で起動失敗する。

**根本原因**: Amazon ENA ドライバが UEK に追加されたのは UEK4(OL6 では 4.1.12-124.x、OL7 では 4.14.35-1818.x)から。UEK2(2.6.39)と UEK3(3.8.13)は AWS Nitro よりも先行している。OL6 の RHCK(2.6.32-754.x)も ENA を含まない — Red Hat による ENA バックポートは RHEL 7.4 までしか行われていない。UEK5(4.14)以降は OL6 用にビルドされていない。

**対処**: OL6 env テンプレートは `KERNEL=uek` と `UEK_RELEASE=4` をハードコード。動的合成される `distr/ol6-slim/image-scripts.sh` の `distr::validate()` で `UEK_RELEASE=4` を明示的に強制:

```bash
[[ "${UEK_RELEASE}" =~ ^4$ ]] || common::error "UEK_RELEASE must be 4 (OL6 + AWS Nitro requires UEK4; UEK2/3 lack ENA, UEK5+ not available)"
```

OL7 の `^(6)$` パターンより厳しいが、テンプレート自体は同じ構造に従う。

**注意点**: Oracle が将来 OL6 に対する新しい UEK リリースをバックポートした場合(UEK は glibc とツールチェインに強く結合するため極めて起こりにくい)、本バリデータの緩和が必要となる。

---

## C.13 OL6 の `kernel-uek` は `linux-firmware` を強い依存関係として持つ

**症状**: env ファイルで `LINUX_FIRMWARE="No"` を指定するとプロビジョニング中の削除自体は成功するが、後段の `yum install kernel-uek`(カーネルアップデートなど)で再インストールされる。

**根本原因**: OL6 の `kernel-uek` RPM は `Requires: linux-firmware` を宣言している。OL7+ ではこの依存関係が `Recommends:` に緩和された(またはファームウェアがカーネルパッケージに同梱されて削除された)。OL6 では強い依存関係であるため、`yum` は依存関係解決のために常に `linux-firmware` を引き戻す。

**対処**: なし — 既知の制約として記録。OL6 env テンプレートの `LINUX_FIRMWARE` コメントでこの粘着性を明記。動的合成される `distr/ol6-slim/provision.sh` は `LINUX_FIRMWARE="No"` を尊重して `yum remove -y linux-firmware` を発行するが、コメント経由で「後続のカーネル操作が元に戻す」ことをユーザーに伝える。

**将来への対応**: AMI からファームウェアを省いてサイズを縮小することが重要な場合、すべての `kernel-uek` 関連操作完了後(プロビジョニング最終段階)に `rpm -e --nodeps linux-firmware` を発行し、AMI 化以降に `yum update` を実行しないことが推奨。これは現在の本ラッパーのスコープ外。

---

## C.14 OL6 ISO の `.treeinfo` に `images/boot.iso` が宣言されていない

**症状**: libvirt 11.5 / qemu 10.0 上で OL6 U10 ISO に対し `virt-install --location ${ISO}` を実行すると成功する(TUI テキストインストーラが表示される)が、古い `virt-install`(libvirt ≤ 8.x)では `Error: cannot find boot.iso in installation tree` で中断する。

**根本原因**: Anaconda の `.treeinfo` スキーマが OL メジャーバージョン間で変化している。OL6 の `/.treeinfo` は `[images-x86_64]` セクションを `kernel = images/pxeboot/vmlinuz` と `initrd = images/pxeboot/initrd.img` のみで宣言しており、一部の `virt-install` バージョンが期待する `boot.iso` キーを持たない。

**対処**: 本ラッパーは libvirt 11.5+ の `.treeinfo` 緩和処理(kernel/initrd で十分、`boot.iso` 不要)に依存する。Phase A.4 で正規ビルダー RHEL 10(libvirt 11.5.0-2.el10、qemu-kvm 10.0.0-13.el10)上での挙動を確認済み。OL6 env テンプレートのコメントでこの挙動をフラグ。ビルダーホストの libvirt がそれより古い場合は別途対応(`--location ${ISO},kernel=images/pxeboot/vmlinuz,initrd=images/pxeboot/initrd.img` の明示的指定)が必要になるが、本ラッパーはそのつまみを現状公開していない。

**検証**: Phase B-1 でブートテスト実施 — OL6 U10 ISO から libvirt ドメインを起動し、ISO のマウント、isolinux のロード、kickstart プロンプトでの Anaconda 13.21.263 TUI 出現を確認。それ以降のフェーズは作者により未実行。

---

## C.15 OL6 における `detect_os_variant()` のフォールバック挙動(osinfo-db `ol6.X` 命名)

**症状**: `osinfo-db-20250606+` を持つビルダー(RHEL 10 デフォルト)では `virt-install --os-variant oraclelinux6.10` が成功するが、古いビルダー(`osinfo-db-20230101`)では `Unknown OS variant 'oraclelinux6.10'` で失敗する。

**根本原因**: osinfo-db は OL エントリの命名規約を変更した経緯がある。古いビルドは `oraclelinux{N}.{U}` short-id を提供し、新しいビルドは `ol{N}.{U}`(例: `ol6.10`, `ol7.9`)を提供する。両方を持つビルダーもあれば片方しか持たないビルダーもある。

**対処**: `detect_os_variant()` を拡張し、現代の `ol{N}.{U}` ファミリを候補チェーンの先頭に挿入:

```bash
# 0. Modern osinfo-db 'ol{N}.{U}' short-id
candidates+=("ol${major}.${update}")
for ((u = update - 1; u >= 0; u--)); do
  candidates+=("ol${major}.${u}")
done
candidates+=("ol${major}-unknown" "ol${major}")
```

レガシーの `oraclelinux{N}.{U}` ファミリは直下に残置。両方とも持たない OL6 ビルダーの場合、チェーンは `rhel6.{U}` へフォールスルーする(OL6 とバイナリ互換であり、ほぼ常時存在)。

**注意点**: 本ラッパーが行う `osinfo-query` 呼び出しはすべて読み取り専用で副作用は無い。`osinfo-query` 自体が利用不可な場合(2026 時点ではまれだが、絞り込み済みのビルダーイメージでは起こり得る)、`detect_os_variant()` は 1 を返し、運用者は env ファイルで `OS_VARIANT` を手動設定する必要がある。

---

## C.16 OL6 `ROOT_FS=xfs` 時に `/boot` を ext4 のまま維持

**症状**: OL6 の env テンプレートのデフォルトを `ROOT_FS="ext4"` から `ROOT_FS="xfs"`(OL7/8/9/10 と整合)に変更した当初、ラッパー合成版 `distr/ol6-slim/image-scripts.sh` 内の `distr::kickstart` 実装は以下のグローバル置換を行っていました:

```bash
sed -i -e 's!--fstype="ext4"!--fstype="xfs"!g' "${ks_file}"
```

この実装は `/boot` と `/` の **両方** のパーティションを xfs に書き換えてしまいます:

```
part /boot    --fstype="xfs" --ondisk=sda --size=500  --label=/boot
part /        --fstype="xfs" --ondisk=sda --size=4096 --label=root  --grow
```

**根本原因**: OL6 のブートローダーは GRUB Legacy 0.97。grub-0.97 は OL6 のパッチビルドでは XFS 読み取りに対応していますが、GRUB 2(OL7 以降)上での XFS と比較すると実戦投入の経験が浅い組み合わせです。OL6 で XFS ルートを使用する業界標準のプラクティスは、より小さな `/boot` 専用 ext4 パーティションを残すこと。RHEL 6 / OL 6 anaconda の自動パーティショニングがユーザーに XFS ルートを選ばせた場合と同じ構成です。

**対処**: 置換パターンを行アンカー付きの、ルートパーティション専用パターンに変更:

```bash
sed -i -e 's!^\(part /        --fstype=\)"ext4"!\1"xfs"!' "${ks_file}"
```

このパターンは `phase3_clone_repository` 内に埋め込まれた kickstart テンプレートの `part /` と `--fstype=` の間にある 4 つのスペースに依存しています。もし将来このテンプレートが再フォーマットされたら、この置換も連動して更新する必要があります(kickstart テンプレートと sed パターンが `build-ol-aws-ami.sh` 内で同一ファイル内に配置されているのは、まさにこの連動を見落としにくくするためです)。

**検証**: 静的検証で以下を確認:

1. このパターンは埋め込み kickstart テンプレートの `part /        --fstype="ext4"` 行にバイト単位で一致する。
2. このパターンは `part /boot    --fstype="ext4"` 行には一致しない(スペース数が異なる。アンカー `part /        ` は `/` と `--fstype=` の間に 8 文字を要求するが、`/boot    ` はその条件を満たさない)。
3. このパターンは冪等。既に置換済みの行に対する再実行は no-op(`"xfs"` はリテラルの `"ext4"` 文字列にマッチしない)。

**注意点**: OL6 の `ROOT_FS=xfs` 設定に対する end-to-end(Phase C)検証は、本ドキュメント作成時点で著者により未実施(OL6 ビルドパイプライン全体としても Phase A/B 検証のみの状態)。OL7 リファレンス kickstart と GRUB Legacy の XFS ドキュメントに基づき構造的には正しい修正ですが、OL6+XFS を本格利用する運用者は、初回起動時に anaconda や grub の挙動不良が発生した際のデバッグを想定しておいてください。

---

# Part D — OL6 全体アーキテクチャ

## D.1 なぜ OL6 は OL7 と異なるアーキテクチャが必要か

本ラッパーにおける OL7 サポートは、アップストリームの既存 OL7 配布物(`distr/ol7-slim/` が完全に揃っている)を**書き換える**ことで実現しています — 1 種類の `sed` パッチが AWS 固有のガードを除去し、それ以外のアップストリームパイプラインは無修正で動作します。

OL6 サポートは**アップストリームが提供していないものを合成する**必要があります。`distr/ol6-slim/` そのものが存在せず、加えて `cloud/aws/provision.sh` の中には OL6 固有のパッケージ構成のため OL6 では直接失敗する行が含まれます。したがって 3 種類のランタイム改変が必要です:

| # | 種別 | 対象 | 目的 |
|---|------|------|------|
| 1 | `sed` パッチ | `cloud/aws/image-scripts.sh` | OL8+ ガードの除去(OL7 と共用) |
| 2 | `sed` パッチ | `cloud/aws/provision.sh` | OL6 で `kernel-uek-modules` インストールをスキップ(C.11) |
| 3 | ディレクトリ合成 | `distr/ol6-slim/`(4 ファイル) | kickstart + image-scripts + provision の OL6 用ロジックを提供 |

3 つすべては `phase3_clone_repository` に置かれており、clone のたびに再確立されます。ラッパー自身が 4 つの `distr/ol6-slim/` ファイルの正規テンプレートをクォート版ヒアドキュメントとして保持します。

## D.2 Phase A + B 検証サマリ

OL6 サポートは構造化された 2 フェーズ事前検証を経て追加されました。下記すべての検証は 2026-05 時点の `oracle-linux` main ブランチに対し、RHEL 10.0(libvirt 11.5.0-2.el10、qemu-kvm 10.0.0-13.el10)+ `osinfo-db-20250606-1.el10` の環境で実施。

**Phase A — 静的検証(9 項目、全 PASS):**

1. osinfo-db に `ol6.0` 〜 `ol6.10`(11 エントリ)および `rhel6.0` 〜 `rhel6.10`(11 エントリ)が存在 — `detect_os_variant()` はいずれかのファミリで解決可能。
2. アップストリーム `oracle-linux-image-tools` には `distr/ol7-slim/`、`distr/ol8-slim/`、`distr/ol8-aarch64/`、`distr/ol9-slim/`、`distr/ol9-aarch64/`、`distr/ol10-slim/`、`distr/ol10-aarch64/` は存在するが `distr/ol6-slim/` は無い。合成アプローチが必要。
3. `bin/build-image.sh` の有効 `DISTR_NAME` 正規表現は `^OL(6|7|8|9|(10))U` — アップストリームのエントリポイント自体は OL6 を受け入れる。
4. `cloud/aws/image-scripts.sh` 行 33 に OL8+ ガードがそのまま存在 — OL7 と同一構造。パッチ #1 は OL7 と同じ sed パターンで再利用可。
5. `cloud/aws/provision.sh` 行 58 に `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` が存在 — パッチ #2 の sed パターンがマッチする。
6. ISO URL `https://yum.oracle.com/ISOS/OracleLinux/OL6/u10/x86_64/OracleLinux-R6-U10-Server-x86_64-dvd.iso` が解決する(HTTP 200、4,072,669,184 バイト、Last-Modified 2018-06-25)。
7. チェックサム URL `https://linux.oracle.com/security/gpg/checksum/OracleLinux-R6-U10-Server-x86_64.checksum` が解決し、ISO の SHA256 `625044388ee60a031965a42a32f4c1de0c029268975edcd542fd14160e0dadcb` と一致する。
8. OL6 UEKR4 リポジトリ(`https://yum.oracle.com/repo/OracleLinux/OL6/UEKR4/x86_64/`)が HTTP 200 を返す。`primary.xml.gz` を確認し `kernel-uek-4.1.12-*` の存在と `kernel-uek-modules-*` の不在を確認。
9. OL6 における cloud-init の入手可否: `cloud-init-18.4-2.0.9.el6.x86_64` および `cloud-utils-growpart-0.27-9.el6.x86_64` が `ol6_addons` リポジトリに存在することを確認。

**Phase B — 動的検証(2 項目、全 PASS):**

1. ISO ブートテスト: `virt-install --name=ol6-boot-test --memory=2048 --vcpus=2 --disk size=20 --location=${ISO_PATH} --os-variant=ol6.10 --network=default --graphics=none --console pty,target_type=serial` が成功し、isolinux がロード、kickstart プロンプトで Anaconda 13.21.263 TUI が表示されテキスト入力を受け付けることを確認。直後にドメインを破棄(実インストールは行わない)。
2. `osinfo-query os | grep ^ol6` がビルダー上で 11 行返す — `ol6.10` short-id は `virt-install --os-variant` で選択可能。

**Phase C(未実行):** kickstart 完走、OL6 環境での provision.sh、Nitro 上での cloud-init による ec2-user 作成、end-to-end での AMI 起動。これらは実ビルダーホストで OL6 ビルドを実施する次回イテレーションで実施予定。

## D.3 OL7 サポートとの比較

| 観点 | OL7 | OL6 |
|------|-----|-----|
| アップストリーム `distr/` | 存在(`ol7-slim`) | **存在しない** — ランタイム合成 |
| 必要な `sed` パッチ | 1 種類(`image-scripts.sh` ガード) | 2 種類(`image-scripts.sh` + `provision.sh`) |
| カーネル | UEK6(4.14) | UEK4(4.1.12) — OL6 で唯一 ENA 対応 |
| ファイルシステム選択肢 | xfs、btrfs | ext4、xfs(lvm / btrfs はこのレイヤーで非対応) |
| init システム | systemd | Upstart(`service` / `chkconfig`) |
| ブートローダ | GRUB2 | GRUB Legacy |
| kickstart 構文 | Anaconda 19.x(`inst.` プレフィックス) | Anaconda 13.x(`inst.` プレフィックスなし) |
| NTP デーモン | chronyd | ntpd |
| `linux-firmware` | 任意 | `kernel-uek` の強い依存 |
| `kernel-uek-modules` パッケージ | 存在(UEK6) | 存在しない(UEK4) |
| AWS VM Import サポート | EOL(2024-12-31) | EOL(ELS は 2024 末で終了) |
| End-to-end 検証 | 未実施(パッチ検証済み、ビルド未実行) | 未実施(Phase A+B 完了、Phase C 未実行) |

この表の非対称性こそが、OL6 には Part D が必要で OL7 には不要だった理由です。OL7 は元々機能するアップストリームパイプラインに薄いパッチを当てるだけで済みますが、OL6 は OL 固有のグルーレイヤをラッパー内でゼロから組み直すことになります。

---

## 付録: 新しい OL メジャーリリースのサポート追加方法

Oracle が OL11 をリリースした場合:

1. **env テンプレートを追加**:
   ```bash
   cp env.properties.aws-ol10 env.properties.aws-ol11
   sed -i 's/ol10/ol11/g; s/OL10/OL11/g; s/R10-U1/R11-U1/g; ...' env.properties.aws-ol11
   ```
2. **README の表を更新**(英語版・日本語版):「Repository Layout」「Folder layout」、および env テンプレート比較の行を追加
3. **SPEC.md B.3 の表を更新**:新テンプレートの列を追加
4. **動作確認**:
   ```bash
   bash -n build-ol-aws-ami.sh
   shellcheck --severity=warning build-ol-aws-ami.sh
   ./build-ol-aws-ami.sh --env env.properties.aws-ol11 --build-only
   ```

スクリプト変更は不要のはず。`parse_ol_version_from_iso` と `detect_os_variant` が新メジャーバージョンに自動追従する。

Oracle が ISO 命名規約を変更したりチェックサム URL を再度移動した場合は、Part C に新エントリを追加し、新パターンを `parse_ol_version_from_iso` / `derive_oracle_checksum_url` にそれぞれ追加すること。
