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
  - [B.3 env.properties.aws-ol{7,8,9,10}](#b3-envpropertiesaws-ol78910)
- [Part C — 既知の落とし穴と教訓](#part-c--既知の落とし穴と教訓)

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
- `detect_ec2_environment` / `guide_ec2_kvm_issue`(EC2 自己診断)
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
9. EC2 ヘルパー                     detect_ec2_environment, guide_ec2_kvm_issue
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

## B.3 `env.properties.aws-ol{7,8,9,10}`

### 識別情報

サポートする OL メジャーリリースごとに 1 つずつ、計 4 つの付随テンプレート。本ディレクトリにコミットされており、編集前に `env.properties.local` にコピーすべきもの。

OL7 テンプレートは実験的扱い — 上流の AWS クラウドターゲットに対して OL7 が動作するようにするランタイムパッチの根拠は C.10 を参照のこと。

### テンプレート間の差異

| キー | OL10 テンプレート | OL9 テンプレート | OL8 テンプレート | OL7 テンプレート |
|------|-----------------|----------------|----------------|----------------|
| `WORKSPACE` | `/tmp/ol10-build-ws` | `/tmp/ol9-build-ws` | `/tmp/ol8-build-ws` | `/tmp/ol7-build-ws` |
| `DISTR` | `ol10-slim` | `ol9-slim` | `ol8-slim` | `ol7-slim` |
| `ISO_URL` | OL10 U1 | OL9 U7 | OL8 U10 | OL7 U9(`Server-` 接中辞付き) |
| `# OS_VARIANT` 例示 | `rhel10.1` | `rhel9.7` | `rhel8.10` | `rhel7.9` |
| `# AMI_NAME` 例示 | `OracleLinux-10-U1-...` | `OracleLinux-9-U7-...` | `OracleLinux-8-U10-...` | `OracleLinux-7-U9-...` |
| `KERNEL` | 未設定(distr デフォルト) | 未設定 | 未設定 | `uek`(必須 — C.10 参照) |
| `UEK_RELEASE` | 未設定 | 未設定 | 未設定 | `6`(OL7 で唯一現実的な UEK) |
| ファイル冒頭警告バナー | なし | なし | なし | EOL / パッチ / 本番禁止の旨を記載 |

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
