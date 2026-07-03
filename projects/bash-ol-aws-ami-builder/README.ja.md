---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-06
---
# Oracle Linux AWS AMI Builder

[English](./README.md) | 日本語

> 📂 [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) リポジトリの [`projects/bash-ol-aws-ami-builder/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/projects/bash-ol-aws-ami-builder) 配下のアーティファクトです
> ⚠️ **AI 生成コンテンツ** — 実行前にソースコードを確認してください。[リポジトリのAIコンテンツポリシー](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)で完全な免責事項を確認できます。
> 📐 **開発者向け仕様書**:[`SPEC.md`](./SPEC.md) (English only)([English](./SPEC.md)) — phase contract、ログ規約、env プロパティキー、現実装ですでに対処済みの過去の落とし穴を記録

Oracle 公式の [`oracle-linux-image-tools`](https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools) を活用し、Oracle Linux 8 / 9 / 10 (x86_64) の AWS AMI を自前で構築するためのラッパースクリプト一式です。

**Oracle Linux 7** (x86_64) も実験的にサポートしています — 詳細は [セクション 1](#1-構成ファイル) 末尾の注記、[セクション 9.6](#96-oracle-linux-7-サポート実験的) および [セクション 10](#10-既知の制約注意事項) の警告を参照してください。

**Oracle Linux 6** (x86_64) はさらに実験的なサポートです。アップストリームには `distr/ol6-slim/` ディレクトリそのものが存在しないため、本ラッパーは sed パッチ 2 種に加えて、必要な 4 ファイルを実行時に動的生成します。仕組みは [セクション 9.7](#97-oracle-linux-6-サポート実験的)、制約は [セクション 10](#10-既知の制約注意事項) 項目 8 を参照してください。

Oracle 公式 AMI(オーナー ID `131827586825`)の AWS Marketplace 提供が終了したため、独自の AMI 構築・運用フローを確立する目的で作成しています。

> **2026 年 2 月以降の AWS 新機能対応**
> AWS が C8i / M8i / R8i インスタンスでネスト仮想化をサポートしたことに伴い、本ガイドは **M8i 系インスタンスでのビルドを主推奨**としています。これによりベアメタルインスタンス(`.metal`)を使う必要がなく、**コストが従来の約 1/15** になります。

---

## ⚠️ 免責事項(実行前に必ずお読みください)

**自己責任でご利用ください。** 本スクリプトは「現状有姿(AS IS)」で提供され、明示・黙示を問わずいかなる保証もありません。作者および貢献者は、本スクリプトの使用、改変、再配布に起因する直接・間接の損害(データ消失、想定外のクラウド料金、アカウント停止など)について一切責任を負いません。

本スクリプトを実行することで、以下を承諾したものとみなします。

* Oracle Linux に関する **Oracle のエンドユーザライセンス契約**、**AWS のサービス利用規約**(特に VM Import/Export および EC2)、および関連法規への準拠は利用者の責任で確認すること
* スクリプトはビルドホスト上で **`sudo` を実行**し、KVM/libvirt のインストールや `${WORKSPACE}` 配下ディレクトリの ACL 変更を行うこと(Phase 1 で導入される内容を確認し、これらの変更に同意したものとみなします)
* スクリプトは **AWS の課金を発生**させます:ビルダーの EC2 インスタンス時間、インポートされたイメージの EBS スナップショットストレージ、ステージング VMDK の S3 ストレージ。**これらのリソースの監視とクリーンアップは利用者の責任**です
* `import-snapshot` と `register-image` の呼び出しは **永続的な AWS リソース**(EBS スナップショットと AMI)を作成します。削除は利用者の責任で行ってください。孤立したスナップショットは予期せぬ AWS 課金の典型的な原因です
* 任意の環境で実行する前に、スクリプトのソースコード(または [`SPEC.md`](./SPEC.md) (English only) 仕様書)をレビューすること
* ビルドプロセスは **一時的な内部 VM のみ**でカーネルレベル機能の変更を行います。ビルドホスト自体は Phase 1 のパッケージ導入と Phase 2 の ACL 調整以外には変更されません。とはいえ、ビルドホストは **使い捨て**(専用 EC2 インスタンスが理想)として扱うことを強く推奨します

これらのツールは慎重に運用してください。**Oracle が公式に配布する AMI が存在する場合はそちらを優先**してください。本リポジトリは、Oracle が AWS Marketplace に対象リリースの AMI を公開していない、かつ利用者が自前ビルド AMI を自身の AWS アカウントで運用する意思がある、というニッチなケースを対象としています。

---

## なぜこのスクリプトが必要か

AWS Marketplace は Oracle Linux の一部のリリース(主に OL 8.x /
9.x)について公式 AMI を提供していますが、 カバレッジは部分的です:
OL 6 / 7 / 10 は未公開、 メンテナンスされていない、 または有料
Marketplace 出品の背後にあります。 コンプライアンス要件、 クロス
バージョンアップグレードの試験、 Oracle の Marketplace AMI 公開前
の早期検証など、 自身でビルドした AMI が必要な運用者は、 そのギャップ
を自分で埋める必要があります。 さらに Oracle 公式の
`oracle-linux-image-tools`(正典の上流ビルダー)を動かすには、
KVM ホストの構築と、 ビルド結果の raw image を自身の AWS アカウント
に AMI として着地させる丁寧なグルー処理が必要です。

`build-ol-aws-ami.sh` は、 全 9 フェーズのパイプライン全体を自動化
します:ビルドホスト前提条件(KVM/libvirt)、 ワークスペース ACL
ブートストラップ、 Oracle 上流のクローン、 バージョン固有のランタイム
パッチ(OL 6 / OL 7)、 `build-image.sh` の起動、 ビルド後の
streamable VMDK 変換、 S3 ステージング、 EC2 `import-snapshot`、
`register-image`。 単一の env properties ファイル
(`env.properties.aws-ol{6,7,8,9,10}`)で全パラメーターを集中
管理しており、 別の OL リリースで再実行するには 1 ファイル変更で
済みます。

### 適している用途

- AWS Marketplace に未公開の OL リリース(現状は OL 6、 OL 7 の
  EOL 期、 OL 10 の早期)が必要な **運用者**
- ネスト仮想化に対応した EC2 インスタンス(M8i 系)や
  オンプレ KVM ホストでの **ビルドホスト構築**
- 運用者自身がビルドしていない Marketplace ブロブよりも、 自身で
  ビルドした AMI を必要とする **コンプライアンス・監査シナリオ**

### 対象外

- Oracle が AWS Marketplace に既に公開しているリリースに対する
  **日常運用 AMI の生成**(常に公式 AMI を優先してください)
- **AWS 以外のターゲット**(Azure、 GCP、 OCI — インポートフローは
  AWS 固有で、 `import-snapshot` + `register-image` を使用)
- **エアギャップ環境でのビルド**(Oracle 上流のクローン、 パッケージ
  リポジトリ、 AWS API のためにビルドホストはインターネット接続が必須)
- **マルチテナントなビルドホスト**(ラッパーは `sudo` を呼び出し、
  ビルドホストのワークスペース ACL を変更します)

### 読者向けナビゲーション

- **初めて運用する方** は、 上記の免責事項を読み、 セクション 5
  (事前準備)とセクション 6(実行)から始めてください。
- **環境選択**(M8i のネスト仮想化 vs オンプレ KVM、 OL バージョン
  のカバレッジマトリクス)については、 セクション 3(ビルダー環境
  の選択)を参照してください。
- **内部挙動の確認**(9 フェーズ、 エラー耐性戦略、 ACL ブートストラップ、
  OL6 ランタイム合成)については、 [`SPEC.md`](./SPEC.md) Part A
  および Part B を参照してください(SPEC は英語のみで維持されて
  います)。
- **リポジトリ全体に共通する LLM エージェント運用ガイド**(ガバナンス
  階層、 ground truth 抽出、 Doc-Touching マトリクス、 Part A 継承
  ルール、 アンチパターン)は、 リポジトリルートの
  [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) を参照してください(英語のみ)。
  本スクリプトの `SPEC.md` Part A は、 本リポジトリの sibling
  **Bash / AWS スクリプト用の正典継承元** として機能します
  ([`projects/powershell-download-speakerdeck-oracle4engineer/SPEC.md`](../powershell-download-speakerdeck-oracle4engineer/SPEC.md)
  が PowerShell 系の正典であるのと並列の役割)。

---

## 1. 構成ファイル

| ファイル | 用途 |
|---------|------|
| `build-ol-aws-ami.sh` | メインのビルドオーケストレータ。前提準備〜AMI 登録までを 9 フェーズに分けて実行。バージョン非依存で、`--env` で OL バージョンを指定 |
| `env.properties.aws-ol10` | **Oracle Linux 10 Update 1**(x86_64)用パラメータ |
| `env.properties.aws-ol9` | **Oracle Linux 9 Update 7**(x86_64)用パラメータ |
| `env.properties.aws-ol8` | **Oracle Linux 8 Update 10**(x86_64)用パラメータ |
| `env.properties.aws-ol7` | **Oracle Linux 7 Update 9**(x86_64)用パラメータ — **実験的・アップストリーム非推奨**。重要な注意事項はセクション 9.6 および 10 を参照 |
| `env.properties.aws-ol6` | **Oracle Linux 6 Update 10**(x86_64)用パラメータ — **実験的・アップストリームに `distr/ol6-slim/` 自体が無い**。重要な注意事項はセクション 9.7 および 10 を参照 |
| `setup-vmimport-role.sh` | AWS VM Import/Export 用の `vmimport` IAM サービスロールを初回のみ作成 |
| `install-ena-driver.sh` | 指定バージョン(OL6 → 2.9.1、OL7 → 2.17.0)または latest 自動解決(OL8/9/10、評価/単体実行専用 — SPEC B.9参照)の Amazon ENA ドライバを DKMS でビルド/導入する自己完結スクリプト。依存(EPEL・gcc/make・dkms・`kernel-uek-devel`)を自身で導入し、**素の OL インスタンス上で単体実行**して検証可能。ENA ビルド有効時(既定、OL6/OL7 のみ — OL8/9/10 は AMI パイプラインでは引き続き in-distro ドライバのまま)に Phase 3 がゲストの AWS プロビジョニングへ注入 |
| `install-ssm-agent.sh` | Amazon SSM Agent の RPM を導入し起動時に有効化する自己完結スクリプト(OL6 → 固定 `3.3.4624.0`、OL7-OL10 → `latest`)。RPM を `curl` で取得し `rpm -Uvh` で導入(EL6 の yum-over-HTTPS 問題を回避)。install+run テストマトリクス(`tests/ssm/`)向けに**単体実行**可能、または SSM 導入有効時(既定)に Phase 3 がゲストの AWS プロビジョニングへ注入 |
| `install-awscli.sh` | AWS CLI v2 を導入(OL6 → 固定 `2.17.51`、OL7/OL8 → `latest`)し、OL リポジトリの `awscli`(v1)を versionlock で除外する自己完結スクリプト。自己完結の v2 バンドルを展開しバンドル同梱の `aws/install` で導入。install+run テストマトリクス(`tests/awscli/`)向けに**単体実行**可能、または AWS CLI 導入有効時(既定、OL6/OL7/OL8 — OL9/OL10 は既定のパッケージマネージャを利用)に Phase 3 がゲストの AWS プロビジョニングへ注入 |
| `README.md` | エンドユーザ向けドキュメント(英語、ベースライン) |
| `README.ja.md` | エンドユーザ向けドキュメント(日本語) |
| `SPEC.md` | 開発者向け仕様書(英語)— phase contract、ログ規約、設計判断の詳細 |

---

## 2. 全体フロー

```
[ビルダー EC2 (M8i 系・ネスト仮想化有効)]    [AWS]
      │                                        │
      │ ① ISO ダウンロード                      │
      │ ② virt-install で OS インストール       │
      │   (KVM L1 上で OL10 を L2 として起動)   │
      │ ③ virt-customize でプロビジョン         │
      │ ④ VMDK 出力                            │
      │                                        │
      ├─── ⑤ aws s3 cp ──────────────────►   S3 Bucket
      │                                        │
      ├─── ⑥ import-snapshot ─────────────►   EBS Snapshot
      │                                        │
      └─── ⑦ register-image ──────────────►   AMI 完成
```

---

## 3. ビルダー環境の選択

`oracle-linux-image-tools` は KVM/libvirt を使うため、ビルドホストには CPU 仮想化拡張(Intel VT-x / AMD-V)が露出している必要があります。**3 つの選択肢**があります。

### 3.1 推奨: AWS EC2 の M8i / C8i / R8i 系(ネスト仮想化有効)

2026 年 2 月以降、AWS は通常の EC2 インスタンス(非ベアメタル)で**ネスト仮想化**をサポートしました。これにより `m8i.xlarge` クラスの安価なインスタンスでビルダーを動かせます。

| 項目 | 内容 |
|------|------|
| 対応インスタンス | C8i, C8i-flex, C8id / M8i, M8i-flex, M8id / R8i, R8i-flex, R8id |
| サイズ | `.large` 〜 `.96xlarge`(全サイズ対応) |
| アーキテクチャ | x86_64(Intel Xeon 6, Sapphire Rapids 世代) |
| リージョン | すべての商用リージョン(東京 ap-northeast-1 含む) |
| 追加料金 | **なし**(通常のインスタンス料金のみ) |
| 推奨スペック | `m8i.xlarge` (4 vCPU / 16 GB) — `oracle-linux-image-tools` のデフォルト要件に適合 |

**起動例:**
```bash
aws ec2 run-instances \
  --image-id <Oracle Linux 9 ベースの AMI ID> \
  --instance-type m8i.xlarge \
  --cpu-options "NestedVirtualization=enabled" \
  --key-name your-keypair \
  --security-group-ids sg-xxxxx \
  --subnet-id subnet-xxxxx \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":60,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ol10-builder}]' \
  --region ap-northeast-1
```

> 重要: `--cpu-options "NestedVirtualization=enabled"` を **起動時** に指定するか、起動後に停止 → `modify-instance-cpu-options` で有効化する必要があります。

### 3.2 代替案 1: AWS EC2 の `.metal` インスタンス

ネスト仮想化機能を使わない従来手法。コスト面で M8i 系より不利ですが、確実な選択肢です。

| 項目 | 内容 |
|------|------|
| 対応インスタンス | `c5n.metal`, `m5.metal`, `c6i.metal`, `m6i.metal`, `i3.metal` 等 |
| 料金 | 約 $4〜$5/h(東京リージョン目安) |
| メリット | KVM が即時動作、設定不要 |
| デメリット | 高コスト、頻繁なビルドには不向き |

### 3.3 代替案 2: オンプレミス KVM ホスト

すでに社内に KVM 対応の Linux ホストがある場合は、そちらでも問題なく動作します。コストはゼロですが、AWS への VMDK アップロード時に大容量転送が発生する点に注意が必要です。

### 3.4 共通要件

| 項目 | 要件 |
|------|------|
| OS | **最新2世代のみ**(それ以前は Phase 1 で拒否)。dnf 系: OL / RHEL / Rocky / AlmaLinux / CentOS Stream **10 または 9**、Fedora **44 または 43**。apt 系: Ubuntu **26.04 または 24.04 LTS**、Debian **13 または 12**。完全なパッケージ一覧と参照のみ(拒否対象。例: Ubuntu 22.04、OL / RHEL 8 以前)は [SPEC B.6](./SPEC.md) を参照 |
| アーキテクチャ | **x86_64**(ターゲット AMI と一致させる必要あり) |
| メモリ | 8 GB 以上(ビルド VM 用に割り当て) |
| ディスク | ワークスペースに **30GB 以上の空き** |
| ネットワーク | `yum.oracle.com` および `github.com` への HTTPS 到達性 |
| 権限 | `sudo` 可能な一般ユーザ。`root` 直接実行は不可 |

---

## 4. ネスト仮想化の有効化(M8i 系を使う場合のみ)

### 4.1 新規起動時に有効化

```bash
aws ec2 run-instances \
  --instance-type m8i.xlarge \
  --cpu-options "NestedVirtualization=enabled" \
  ...(その他のオプション)
```

### 4.2 既存停止インスタンスへの追加適用

```bash
INSTANCE_ID=i-xxxxxxxxxxxxx
REGION=ap-northeast-1

# インスタンスを停止
aws ec2 stop-instances --instance-ids ${INSTANCE_ID} --region ${REGION}
aws ec2 wait instance-stopped --instance-ids ${INSTANCE_ID} --region ${REGION}

# ネスト仮想化を有効化
aws ec2 modify-instance-cpu-options \
  --instance-id ${INSTANCE_ID} \
  --region ${REGION} \
  --nested-virtualization enabled

# インスタンスを起動
aws ec2 start-instances --instance-ids ${INSTANCE_ID} --region ${REGION}
```

### 4.3 ネスト仮想化の動作確認

ビルダー EC2 にログインして以下を確認します。

```bash
# CPU 仮想化拡張フラグの確認 (vmx が表示されれば OK)
grep -E '(vmx|svm)' /proc/cpuinfo | head -n 1

# /dev/kvm の存在確認
ls -l /dev/kvm

# AWS 側からの確認 (ec2:DescribeInstances 権限が必要)
aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --region ${REGION} \
  --query 'Reservations[0].Instances[0].CpuOptions.NestedVirtualization'
# → "enabled" が返れば OK
```

### 4.4 サポート対象インスタンスの確認(リージョン別)

```bash
aws ec2 describe-instance-types \
  --filters "Name=processor-info.supported-features,Values=nested-virtualization" \
  --query "sort(InstanceTypes[].InstanceType)" \
  --region ap-northeast-1
```

---

## 5. 事前準備

### 5.1 リポジトリ取得

```bash
git clone <この一式を置いたリポジトリ> ol-aws-ami-builder
cd ol-aws-ami-builder
chmod +x build-ol-aws-ami.sh setup-vmimport-role.sh
```

### 5.2 AWS CLI のセットアップ

```bash
aws configure
aws sts get-caller-identity
```

必要な IAM 権限(最低限):
- `s3:CreateBucket`, `s3:PutObject`, `s3:GetObject`, `s3:HeadBucket`
- `iam:CreateRole`, `iam:PutRolePolicy`, `iam:GetRole`
- `ec2:ImportSnapshot`, `ec2:DescribeImportSnapshotTasks`, `ec2:RegisterImage`
- `ec2:CreateTags`, `ec2:DescribeImages`, `ec2:DescribeSnapshots`

### 5.3 vmimport IAM ロールの作成 (初回のみ)

```bash
./setup-vmimport-role.sh my-oracle-linux-ami-import-bucket
```

このロールは AWS VM Import/Export が S3 から VMDK を読み出すために必須です。**初回 1 回のみ**作成してください。上記のバケット名は、本ディレクトリ内のすべての `env.properties.aws-ol{N}` テンプレートで共有される `S3_BUCKET` の値と一致しているため、この 1 つのロールで OL6 / OL7 / OL8 / OL9 / OL10 すべてのビルドをカバーします。各 env ファイルの `S3_KEY_PREFIX`(例: `ol10-ami-import`)によって、バケット内でバージョンごとに VMDK が分離されます。

### 5.4 環境設定ファイルの編集

ターゲットの Oracle Linux バージョンに合わせてテンプレートを選択します。

```bash
# Oracle Linux 10 Update 1
cp env.properties.aws-ol10 env.properties.local

# Oracle Linux 9 Update 7
cp env.properties.aws-ol9 env.properties.local

# Oracle Linux 8 Update 10
cp env.properties.aws-ol8 env.properties.local

# Oracle Linux 7 Update 9 (実験的 — セクション 9.6 および 10 を必ず参照)
cp env.properties.aws-ol7 env.properties.local

# Oracle Linux 6 Update 10 (実験的 — セクション 9.7 および 10 を必ず参照)
cp env.properties.aws-ol6 env.properties.local

vi env.properties.local
```

スクリプトは `ISO_URL` から OL のメジャー/アップデートバージョンを自動判別するため、バージョンを切り替える際は env ファイルを差し替えるだけ(または `ISO_URL` を別リリースに変更するだけ)で済みます。

**最低限変更すべき項目:**

| パラメータ | 例 |
|-----------|----|
| `WORKSPACE` | `/tmp/ol10-build-ws`(デフォルト。qemu ユーザーから普通に到達可能。`/tmp` が tmpfs でサイズ不足の場合は `/var/tmp/ol10-build-ws` に変更) |
| `S3_BUCKET` | `my-oracle-linux-ami-import-bucket`(全 OL バージョン共通。`setup-vmimport-role.sh` と一致) |
| `AWS_REGION` | 空のままにすると EC2 IMDSv2/v1 から自動取得(EC2 外では `ap-northeast-1` にフォールバック)。明示的に指定するとオーバーライドされます。 |
| `UPDATE_TO_LATEST` | デフォルト `yes`。ゲスト VM 内でインストール後に `dnf/yum update` を実行し、ISO リリース以降に発見された kernel および userspace の CVE を解消します。トレードオフを理解した上でのみ `security` や `no` に変更してください。 |
| `AMI_NAME` | 任意。未指定なら日時付きで自動生成 |

---

## 6. 実行

### 6.1 通常実行(フル実行)

```bash
./build-ol-aws-ami.sh --env env.properties.local
```

実行時間の目安: **40〜90 分**(回線速度・インスタンス性能に依存)

| Phase | 内容 | 時間目安 |
|-------|------|---------|
| 0 | 前提条件チェック | 数秒 |
| 1 | KVM 等のパッケージ導入 | 2〜5 分(初回のみ) |
| 2 | qemu ユーザーへのワークスペース traverse ACL 付与 | 数秒 |
| 3 | リポジトリ取得 | 数秒 |
| 4 | ISO チェックサム取得 / env 生成 | 数秒 |
| 5 | VMDK ビルド(`virt-install` で OS インストール) | **20〜40 分** |
| 6 | S3 アップロード | 2〜10 分 |
| 7 | `import-snapshot`(EBS スナップショット作成) | **10〜30 分** |
| 8 | `register-image`(AMI 登録) | 1 分未満 |

### 6.2 実行モード

| オプション | 用途 |
|-----------|------|
| `--skip-prereq` | KVM 等のパッケージ導入(Phase 1)をスキップ。2 回目以降の実行で時間短縮 |
| `--build-only` | Phase 6(VMDK 生成 + Nitro 起動準備チェック)まで実行し、AWS 取り込みフェーズ(7〜9)の手前で停止。AWS 取り込みは別途実行したい場合。`--skip-aws-import` と同等 |
| `--skip-aws-import` | Phase 7〜9 をスキップ(`--build-only` と同等) |
| `--skip-ena-driver` | ゲスト内で Amazon ENA ドライバをビルド/導入**しない**。既定ではビルド(AWS 最適化 AMI、Nitro v4+/ENAv3 対応)。本スイッチで純粋な(無改変の)OL AMI を生成 |
| `--skip-ssm-agent` | ゲスト内で Amazon SSM Agent を導入**しない**。既定では導入し起動時に有効化(OL6-OL10)するため、AMI は AWS SSM Run Command 準拠で出荷される。本スイッチでエージェントを除外 |
| `--skip-awscli` | ゲスト内で AWS CLI v2 を導入**しない**。既定では OL6/OL7/OL8 に導入し(AWS CLI v1 が非サポート化しつつあるため標準 CLI として)、v1 パッケージを versionlock で除外する。本スイッチで導入を除外。OL9/OL10 は対象外(既定のパッケージマネージャで AWS CLI v2 を導入)で本スイッチの影響を受けない |
| `--imds-support <mode>` | AMI に焼き込む IMDS サポート: `default`(IMDSv1+v2、`HttpTokens=optional`)または `v2.0`(IMDSv2 必須、**OL7+ のみ**)。既定は `default`。OL6 + `v2.0` は拒否(cloud-init 0.7.5 が IMDSv2 非対応のため) |
| `--log-file <path>` | 実行ログの出力先。既定は `${WORKSPACE}/build-ol-aws-ami-YYYYMMDD-hhmmss.log`(いずれの場合もコンソール出力をファイルにも記録。ファイルは ANSI 除去済み) |
| `--debug` | `[DEBUG]` 行をコンソールにも出力(ファイルには指定有無に関わらず常時記録) |

### 6.3 Phase 0 の自動診断機能

Phase 0 では実行環境を自動検出し、問題があれば対応案内を出します。

**ケース A: M8i 系だがネスト仮想化が無効化されている場合**
```
2026-06-08 07:32:35 [ERROR] EC2 上で CPU 仮想化拡張が露出していません
2026-06-08 07:32:35 [INFO]  検出されたインスタンスタイプ: m8i.xlarge
2026-06-08 07:32:35 [WARN]  [ケース A] m8i はネスト仮想化対応のファミリーですが、本機能が無効化されています。
2026-06-08 07:32:35 [INFO]  対応手順: ネスト仮想化を有効化してください。
2026-06-08 07:32:35 [INFO]    aws ec2 stop-instances --instance-ids i-xxxxx --region ap-northeast-1
2026-06-08 07:32:35 [INFO]    aws ec2 modify-instance-cpu-options ...
```

**ケース B: ネスト仮想化非対応のインスタンスファミリーを使っている場合**
```
2026-06-08 07:32:35 [WARN]  [ケース B] m5 はネスト仮想化非対応のインスタンスファミリーです。
2026-06-08 07:32:35 [INFO]  選択肢 1 (推奨): ネスト仮想化対応の C8i / M8i / R8i 系に乗り換え
2026-06-08 07:32:35 [INFO]  選択肢 2: ベアメタルインスタンスに乗り換え
```

**ケース C: ベアメタルインスタンスで KVM が使えない場合**
```
2026-06-08 07:32:35 [WARN]  [ケース C] m5.metal はベアメタルですが /dev/kvm が利用不可です。
2026-06-08 07:32:35 [INFO]  対応手順:
2026-06-08 07:32:35 [INFO]    1) kvm モジュールがロードされているか確認: lsmod | grep kvm
2026-06-08 07:32:35 [INFO]    2) 未ロードなら手動ロード: sudo modprobe kvm-intel
```

これにより、**初回セットアップ時の試行錯誤を最小化**できます。

---

## 7. コスト比較

東京リージョン目安、1 ビルドあたり 1 時間と仮定。

| 方式 | ビルダー | 時間単価 | 1 ビルドあたり | 月 4 回 | 月 30 回 |
|------|---------|---------|--------------|--------|---------|
| **推奨: M8i 系 + ネスト仮想化** | `m8i.xlarge` | $0.30/h | **$0.30** | $1.20 | **$9.00** |
| 推奨: C8i 系 (CPU 重視) | `c8i.2xlarge` | $0.50/h | $0.50 | $2.00 | $15.00 |
| 代替: ベアメタル(従来手法) | `c5n.metal` | $4.50/h | $4.50 | $18.00 | $135.00 |
| 代替: ベアメタル | `m5.metal` | $5.50/h | $5.50 | $22.00 | $165.00 |

**月 30 回ビルドする場合、約 $126/月のコスト削減**が可能です。CI/CD パイプライン化にも十分耐えられる経済性です。

---

## 8. 完成 AMI の確認と起動テスト

### 8.1 AMI 一覧

```bash
aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:OS,Values=OracleLinux10U1" \
  --query 'Images[*].[ImageId,Name,CreationDate,BootMode]' \
  --output table
```

### 8.2 起動テスト

```bash
AMI_ID=ami-xxxxxxxxxxxxx
KEY_PAIR=your-keypair
SG_ID=sg-xxxxxxxx
SUBNET_ID=subnet-xxxxxxxx

aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type t3.small \
  --key-name "${KEY_PAIR}" \
  --security-group-ids "${SG_ID}" \
  --subnet-id "${SUBNET_ID}" \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ol10-test}]'
```

SSH ログイン:
```bash
ssh -i your-keypair.pem ec2-user@<public-ip>
```

`cloud-init` 経由で公開鍵が `ec2-user` にデプロイされます。

---

## 9. 主な設計判断(サマリ)

> **すべての設計判断の詳細**(phase 番号付け、ログ規約、env プロパティ自動検出、AWS 固有の癖)は [`SPEC.md`](./SPEC.md) (English only)([English](./SPEC.md))にあります。以下は運用者にとって特に重要なポイントのみ抜粋しています。各項目の歴史的経緯は SPEC の Part D を参照してください。

### 9.1 import-image ではなく import-snapshot + register-image

2 段階フロー(`import-snapshot` で EBS スナップショット作成 → `register-image` で AMI 属性付与)を採用することで、`BootMode`、ENA、NitroTPM、IMDS の設定を明示制御できます。`import-image` は便利ですが、AWS の OS 自動判別に依存しており、新しい Oracle Linux リリースは AWS のサポート OS リストに未登録の可能性があります。どの `register-image` フラグが無条件 / 条件付きかは SPEC §B.1 を参照。

### 9.2 ENA / NVMe ドライバ

`oracle-linux-image-tools` の `cloud=aws` ターゲットは、Amazon ENA ドライバと `cloud-init` をイメージに同梱します。OL8/9/10 のカーネル(UEK または RHCK)はネイティブで `ena` モジュールと `nvme` モジュールを含むため、Nitro インスタンスとの完全互換性のために別途のドライバ追加は不要です。

### 9.3 `BOOT_MODE_BUILD = "bios"`(AWS 向けは必須)

Oracle 上位の `bin/build-image.sh` は AWS 対象に対し `BOOT_MODE=bios` を強制し、`uefi` や `hybrid` は拒否します。生成 AMI は `legacy-bios` として登録されます。これは今日時点で **唯一動作する組み合わせ** です — 発見経緯は SPEC §D.4 を参照。AMI はすべての Nitro インスタンスタイプで起動可能。トレードオフとして、NitroTPM と UEFI Secure Boot は有効化できません。

### 9.4 cloud-init / ec2-user

**EC2 ログインユーザー.** 本ビルダーが生成する全 AMI(OL6 / OL7 / OL8 / OL9 / OL10)で、初回起動時のログインアカウントは **`ec2-user`** です(SSH 鍵のみ。パスワード/ root ログインは無効)。接続:

```
ssh -i your-keypair.pem ec2-user@<public-ip>
```

**ユーザー名を決める主体と優先順位.** ログインユーザーは cloud-init の `system_info.default_user.name` で、初回起動時に以下の3層(優先度 低→高)で解決されます。

1. **OS パッケージ既定値** — Oracle Linux の `cloud-init` RPM が同梱する `/etc/cloud/cloud.cfg` の `default_user.name: cloud-user`。これは**ディストリのパッケージ値**であり、本プロジェクトの値では**ありません**。
2. **上流 image-tools** — `oracle-linux-image-tools` の `cloud/aws` プロビジョニングがドロップイン `/etc/cloud/cloud.cfg.d/90_ol.cfg` に `name: ${CLOUD_USER}` を書き込みます。cloud-init は `cloud.cfg.d` のドロップインを基底 `cloud.cfg` より優先してマージするため、これがパッケージ既定値を**上書き**します。
3. **本ビルダー** — すべての `env.properties.aws-ol{N}` テンプレートが `CLOUD_USER="ec2-user"` を設定するため、層 2 が `ec2-user` に解決されます。よって実効ログイン名の決定主体は **本プロジェクトの env テンプレート**です。

**デフォルトユーザーは全バージョンで `ec2-user` に統一.** 全 OL バージョンで `ec2-user` を唯一・正典のログインアカウントとして扱ってください。`cloud-user` は運用上のアカウントには決してならないため、依存しないでください。`cloud-user` という文字列はパッケージの `/etc/cloud/cloud.cfg` に不活性のまま残る場合があります(層 2 で上書きされる)。OL6 では本ビルダーのプロビジョニングフックがさらに、(a) デフォルトユーザーから `systemd-journal` グループを除去し(このグループは systemd 系=OL7+ のみに存在し、存在すると cloud-init の `useradd` が失敗してログインアカウントが作られない。SPEC D.26 参照)、(b) その不活性な `cloud-user` 文字列を `ec2-user` に書き換えて、ビルド済みイメージの点検時に名前が一貫して見えるようにします。OL7-10 は層 1-3 のまま `ec2-user` を取得します。

### 9.4a 全バージョン共通の `S3_BUCKET`

すべての `env.properties.aws-ol{N}` テンプレートは `S3_BUCKET="my-oracle-linux-ami-import-bucket"` を共有しているため、1 つの S3 バケットと 1 つの `vmimport` IAM ロール(`./setup-vmimport-role.sh my-oracle-linux-ami-import-bucket` で作成)で、全 OL バージョンのビルドをカバーできます。バージョンごとの `S3_KEY_PREFIX`(例: `ol10-ami-import`)により、バケット内でビルドごとの VMDK が分離されます。

### 9.4b 動的な `AWS_REGION` 解決

すべての env テンプレートで `AWS_REGION=""` がデフォルトです。空の場合、ラッパーは `load_env` 時に以下の順序でリージョンを解決します。

1. **IMDSv2** — `http://169.254.169.254/latest/meta-data/placement/region` へのトークンベース呼び出し
2. **IMDSv1** — 同エンドポイントへのトークン無し GET。IMDSv2 のトークン取得 PUT が失敗した場合のみ使用(`HttpTokens=disabled` のレガシーホストやネットワーク制限環境を想定)
3. **フォールバック定数 `ap-northeast-1`** — IMDS パスのいずれも値を返さない場合に使用(オンプレミス KVM ビルドホストの通常ケース)

各 curl 呼び出しは `--max-time 2` で 2 秒に制限されているため、非 EC2 ホストでの起動時オーバーヘッドは最大でも約 4 秒です。選択された値とソースは毎回ビルド冒頭にログ出力されます: `AWS_REGION = us-east-1 (source: imdsv2)`

ビルド実行環境に依存せず特定のリージョンに固定したい場合は、`env.properties.local` に `AWS_REGION="ap-northeast-1"`(または他のリージョン)を明示設定してください。

### 9.4c `UPDATE_TO_LATEST` とカーネルレベル CVE 対策

すべての env テンプレートで `UPDATE_TO_LATEST="yes"` がデフォルトです。この設定は Phase 4 を経由して上位の `distr/ol{N}-slim/provision.sh` 内 `distr::configure` 関数に伝達され、ISO ベースのインストール完了後にゲスト VM 内で `dnf update -y`(OL8/9/10)または `yum update -y`(OL6/7)が実行されます。このステップが無いと、生成 AMI には ISO 同梱のパッケージしか含まれず、その後に公開された kernel や userspace の修正がすべて取り込まれません。特に OL10 U1 では Linux Kernel CVE の発見頻度が高く、無視できない露出となります。バイト単位の再現性が必要などの理由で ISO 後の更新を明示的に行いたくない場合は、`env.properties.local` で `UPDATE_TO_LATEST="no"` を指定してください。セキュリティ識別済みのエラータのみに限定する `"security"` も指定可能です。

### 9.5 ネスト仮想化を主推奨にする理由

2026 年 2 月以降、AWS が C8i / M8i / R8i でネスト仮想化を正式サポートしたことで、以下が達成されました。

1. **Oracle 公式ツールに準拠**したまま、**圧倒的に安価**にビルド可能(`m8i.xlarge` で約 $0.30/ビルド vs `c5n.metal` で約 $5/ビルド)
2. **CI/CD パイプライン化が現実解**になる経済性
3. ベアメタル特有の起動遅延(数分待ち)が発生せず、ビルド全体時間が短縮
4. Spot Instance / Auto Scaling との組み合わせも視野に入る

### 9.6 Oracle Linux 7 サポート(実験的)

OL7 はベストエフォートでサポートされており、以下の挙動上の特徴があります。

- **ランタイムパッチ**: アップストリームの `cloud/aws/image-scripts.sh` には `AWS images builder only supports OL8 and above` という OL7 拒否チェックがハードコードされています。`build-ol-aws-ami.sh` の Phase 3 はリポジトリ clone 直後に `OL_MAJOR_VERSION == 7` を検出し、該当行を no-op に書き換えます(参考用にパッチ済みファイルの隣に `image-scripts.sh.ol7-patch.bak` を残します)。
- **アップストリームへは何もコミットしません**: パッチは `${WORKSPACE}/oracle-linux/` 配下のローカル作業ツリーのみに適用されます。`oracle/oracle-linux` への変更は行いません。
- **動作する理由**: OL7 は他の点ではアップストリームのツーリングで完全に保持されており(`distr/ol7-slim/` は健在、AWS プロビジョニング処理が要求する `kernel-uek-modules` も OL7 の UEK6 が提供します)、OL7 拒否は技術的非互換ではなく純粋にポリシー上のガードです。
- **強制される設定**: `BOOT_MODE_BUILD=bios` は二重の理由で必須です。AWS ターゲットが強制する点に加え、OL7 自体も強制します(`bin/build-image.sh`: `OL7 only supports bios BOOT_MODE`)。他の値を指定するとビルドは即座に中断されます。
- **推奨カーネル**: OL7 では `KERNEL=uek` のままにしてください。RHCK パスは別パッケージ `kernel-modules` を必要としますが OL7 はこれを分割していないため、アップストリームの `cloud/aws/provision.sh` が `KERNEL=rhck` だと失敗します。UEK6 は Amazon ENA ドライバを含み、アップストリームの OL7 デフォルトでもあります。
- **起動時の警告バナー**: `load_env` で `OL_MAJOR_VERSION == 7` が検出されると、EOL ステータス、ランタイムパッチの挙動、本番利用禁止について複数行の警告が prominent に出力されます。

OL7 関連の制約の全容は [セクション 10](#10-既知の制約注意事項) の項目 7 を参照してください。

### 9.7 Oracle Linux 6 サポート(実験的)

OL6 は OL7 よりさらに深い回避が必要なサポート対象です。アップストリームのツーリングには **`distr/ol6-slim/` ディレクトリ自体が存在しない**ため、本ラッパーは実行時に埋め込みテンプレートからそれを動的生成します。加えて、`cloud/aws/provision.sh` に対する 2 つめのランタイムパッチも必要です。

- **ランタイムパッチ #1(OL7 と共用)**: `cloud/aws/image-scripts.sh` には `AWS images builder only supports OL8 and above` という OL8 未満を拒否するチェックがあります。`build-ol-aws-ami.sh` の Phase 3 は `OL_MAJOR_VERSION <= 7` を検出し、該当行を no-op に書き換えます。パッチ済みファイルの隣に `image-scripts.sh.ol6-patch.bak` を残します。
- **ランタイムパッチ #2(OL6 専用)**: `cloud/aws/provision.sh` は `KERNEL=uek` のとき無条件に `yum install -y "${YUM_VERBOSE}" kernel-uek-modules` を実行しますが、このパッケージは **OL6 UEKR4 リポジトリに存在しません**(ENA/NVMe/virtio ドライバの `.ko` ファイルはすべて本体 `kernel-uek` RPM に同梱されています)。Phase 3 はこのインストール行を `ORACLE_RELEASE >= 7` でガードし、OL6 では no-op にします。パッチ済みファイルの隣に `provision.sh.ol6-patch-uek-modules.bak` を残します。冪等性のため、マーカー grep でパッチ済みなら再適用をスキップします。
- **動的生成される `distr/ol6-slim/`**: 4 ファイル(`env.properties`, `image-scripts.sh`, `ol6-ks.cfg`, `provision.sh`)が `${WORKSPACE}/oracle-linux/oracle-linux-image-tools/distr/ol6-slim/` 配下に `build-ol-aws-ami.sh` 内のヒアドキュメントから書き出されます。`distr/ol7-slim/` の構造をベースに、OL6 固有の置換を反映:systemd の代わりに Upstart(`service` / `chkconfig` 呼び出し)、GRUB2 の代わりに GRUB Legacy(`/boot/grub/grub.conf` 直接編集)、Anaconda 13.x kickstart 構文(`inst.` プレフィックス無し)、ext4 ルート(lvm / btrfs はこのレイヤーで非対応。さらに anaconda-13 は OL6 で xfs ルートも拒否 — SPEC D.16 参照)。
- **アップストリームへは何もコミットしません**: 3 つのアーティファクト(パッチ 2 種 + 動的生成 `distr/ol6-slim/`)は `${WORKSPACE}/oracle-linux/` 配下のローカル作業ツリーのみに適用されます。`oracle/oracle-linux` への変更は行いません。
- **強制される設定**: `BOOT_MODE_BUILD=bios` は三重の理由で必須です。AWS ターゲットが強制し、アップストリーム OL7 経路が強制し(OL6 もこれを継承)、そもそも OL6 anaconda 13.x が UEFI インストール非対応です。
- **カーネル制約**: OL6+AWS では `KERNEL=uek` かつ `UEK_RELEASE=4` のみが有効です。UEK2/3 は ENA ドライバを持ちません。UEK5/6/7 は OL6 ビルドがありません。RHCK 2.6.32 も ENA を持ちません。OL6 用 `image-scripts.sh` の `distr::validate` は `UEK_RELEASE=4` を強制します。
- **`linux-firmware` は粘着的**: OL6 の `kernel-uek` は `linux-firmware` を強い依存関係として持ちます。`LINUX_FIRMWARE="No"` でいったん削除しても、後続の `yum install kernel-uek` で再インストールされます。
- **起動時の警告バナー**: `load_env` で `OL_MAJOR_VERSION == 6` が検出されると、EOL ステータス、2 つのランタイムパッチ、動的生成 `distr/ol6-slim/`、本番利用禁止について複数行の警告が prominent に出力されます。

OL6 関連の制約の全容は [セクション 10](#10-既知の制約注意事項) の項目 8 を参照してください。

---

## 10. 既知の制約・注意事項

1. **aarch64 (Graviton) AMI は未対応**
   `oracle-linux-image-tools` は AWS について x86_64 のみサポート。また AWS のネスト仮想化機能も Graviton では未対応のため、aarch64 AMI を作るには別途対応が必要です。

2. **ビルダーホストのアーキテクチャ一致が必須**
   x86_64 AMI を作るには x86_64 ホストが必要です。クロスアーキビルドは libguestfs/virt-install のレイヤーで困難です。

3. **AWS 側のサービスクォータ**
   `import-snapshot` は AWS アカウント単位で同時実行数に制限があります(デフォルト 5 並列)。大量ビルド時は AWS Service Quotas で確認してください。

4. **OL10 の VM Import 公式サポート**
   2026 年 5 月時点で AWS VM Import/Export の公式 OS 互換リストに OL10 が明記されていない可能性があります。`import-image` ではなく `import-snapshot` + `register-image` を使う本方式は、この制約を回避するためのものです。

5. **ライセンスとサポート**
   Oracle Linux のサポート契約が必要な場合、Oracle Linux Premier Support を別途契約してください。

6. **ネスト仮想化の性能**
   AWS は性能要件・低遅延要件の厳しいワークロードについては引き続きベアメタルを推奨しています。本ツールのビルド処理は IO バウンドであり、ネスト仮想化の性能オーバーヘッドは実用上問題になりません。

7. **Oracle Linux 7 固有の制約**
   - **EOL**: Premier Support は 2024-12-31 で終了しました。Oracle はアップストリームの `oracle-linux-image-tools` README で OL7 を deprecated 扱いとしています。
   - **アップストリームの AWS サポート外**: アップストリームは `cloud=aws` で OL7 を明示的に拒否します。本ラッパーは Phase 3 でランタイムパッチを当ててこれを回避します([9.6](#96-oracle-linux-7-サポート実験的) 参照)。将来のアップストリームリファクタでパッチが効かなくなる可能性があります。
   - **x86_64 のみ**: OL7 では aarch64 AMI 経路は存在しません。OL8/9/10 にある `distr/_aarch64` の OL7 対応版はありません。
   - **BIOS のみ**: UEFI / hybrid ブートモードは利用できません。NitroTPM や UEFI Secure Boot を有効化できない AMI になります。
   - **UEK カーネル事実上必須**: 理屈上は `KERNEL=rhck` を指定できますが、アップストリームの AWS プロビジョニング処理が要求する `kernel-modules` パッケージを OL7 の RHCK は分割していないため、`KERNEL=uek`(OL7 env テンプレートのデフォルト)のまま使ってください。
   - **`lvm` ルートファイルシステム非対応**: OL7 はこのレイヤーでは `xfs` と `btrfs` のみサポートします(`lvm` は OL8 で追加)。
   - **本番利用禁止**: 検証・学習・レガシーマイグレーション以外には使用しないでください。

8. **Oracle Linux 6 固有の制約**
   - **EOL**: Premier Support は 2021-03-31 で終了しました。Extended Life Support(ELS)も 2024 年で終了し、それ以降 Oracle は OL6 へのセキュリティアップデートを提供していません。
   - **アップストリームにそもそも存在しない**: アップストリームの `oracle-linux-image-tools` リポジトリには `distr/ol6-slim/` ディレクトリ自体がありません。本ラッパーは必要な 4 ファイル(`env.properties`, `image-scripts.sh`, `ol6-ks.cfg`, `provision.sh`)を Phase 3 で動的生成します([9.7](#97-oracle-linux-6-サポート実験的) 参照)。AWS 用 `image-scripts.sh` のガードは OL7 と同じ方式でパッチします。
   - **追加ランタイムパッチ**: `cloud/aws/provision.sh` には OL6 専用の追加パッチを当て、OL6 では `yum install kernel-uek-modules` をスキップします。このパッケージは OL6/UEKR4 に存在しません(モジュールは `kernel-uek` 本体に同梱)。
   - **x86_64 のみ**: OL6 には aarch64 リリースがそもそも存在せず、aarch64 AMI 経路はありません。
   - **BIOS のみ**: OL6 anaconda 13.x は UEFI インストール非対応です。NitroTPM や UEFI Secure Boot は有効化できません。
   - **UEK4 必須**: `KERNEL=uek` かつ `UEK_RELEASE=4` のみが有効です。UEK2/3 は ENA ドライバを持ちません。UEK5/6/7 は OL6 ビルドが存在しません。RHCK 2.6.32 も ENA を持ちません。
   - **ファイルシステムは ext4 ルートのみ**: anaconda-13 は OL6 で xfs(および lvm / btrfs)ルートを拒否するため、ルートパーティションは ext4 必須です(実機インストールで確認 — SPEC D.16/D.18 参照)。
   - **`linux-firmware` は恒久削除できない**: `kernel-uek` が依存関係として強く要求するため、`yum install kernel-uek` のたびに再インストールされます。
   - **AWS VM Import/Export 公式サポート外**: 本ラッパーは `import-snapshot` + `register-image` を使ってポリシーを迂回しますが、将来 AWS がポリシーを厳格化すると動作不能になる可能性があります。
   - **Phase A/B 検証済み、Phase C 未検証**: 静的検証 9 項目(osinfo-db エントリ、ISO checksum、リポジトリ HTTPS、dracut フラグ、cloud-init 提供状況、アップストリーム OL バージョン分岐)および OL6 ISO ブートテスト(virt-install + isolinux + Anaconda 13.21.263 TUI)は検証済みです。kickstart 完走、provision.sh の OL6 環境完走、cloud-init による `ec2-user` 作成、AWS Nitro 起動は **作者により未検証** です。
   - **本番利用禁止**: OL7 よりさらに強い制約です。検証・学習・レガシーマイグレーション以外には絶対に使用しないでください。

---

## 11. トラブルシューティング

### Phase 0 で「CPU 仮想化拡張が露出していません」エラー

→ Phase 0 の自動診断メッセージに従ってください。多くの場合、ネスト仮想化が未有効化です。
セクション 4.2 の手順で `modify-instance-cpu-options` を実行してください。

### Phase 1 で `qemu-kvm` インストール失敗

→ EPEL や CodeReady Builder リポジトリの有効化が必要な場合があります。
```bash
sudo dnf config-manager --set-enabled crb  # Oracle Linux 9 / RHEL 9
sudo dnf install -y epel-release
```

### Phase 5 で `KVM acceleration not available, using 'qemu'` 警告

→ ネスト仮想化が無効、または `/dev/kvm` のパーミッション不足。
```bash
ls -l /dev/kvm
sudo modprobe kvm-intel
sudo usermod -aG kvm,libvirt $USER
# グループ変更を反映するため再ログインが必要
```

### Phase 8 で `ClientError: Unsupported kernel version`

→ AWS VM Import が OL10 のカーネルを未認識。`import-image` 経由ならこのエラーになりますが、本スクリプトは `import-snapshot` を使うため**本来は発生しません**。発生した場合は AWS サポートに OL10 サポート追加を依頼してください。

### 生成 AMI 起動時に `cloud-init` でハングする

→ `SERIAL_CONSOLE_RUNTIME="Yes"` を確認。EC2 Serial Console でログを確認可能です。
```bash
aws ec2 get-console-output --instance-id i-xxxxx --region <region>
```

---

## 12. 参考資料

- [oracle/oracle-linux/oracle-linux-image-tools](https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools) — Oracle 公式ツール
- [Use nested virtualization to run hypervisors in Amazon EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html) — AWS のネスト仮想化機能ドキュメント
- [Amazon EC2 supports nested virtualization on virtual Amazon EC2 instances (What's New)](https://aws.amazon.com/about-aws/whats-new/2026/02/amazon-ec2-nested-virtualization-on-virtual/) — 2026 年 2 月リリースアナウンス
- [Oracle Linux ISOs](https://yum.oracle.com/oracle-linux-isos.html) — ISO ダウンロードとチェックサム
- [AWS VM Import/Export User Guide](https://docs.aws.amazon.com/vm-import/latest/userguide/) — `import-snapshot` / `register-image` の詳細
- [Boot modes in EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ami-boot.html) — `uefi-preferred` 等の挙動

---

## 13. 来歴

### AI 生成について

本ラッパースクリプトは、**Anthropic 社の Claude (Sonnet 4.5)** との対話を通じて 2026 年 5 月に反復的に開発・改善されたものです。Oracle Linux 8 / 9 / 10 の AWS 上での実ビルドで end-to-end の動作確認まで完了しています。Oracle Linux 7 の実験的サポートは、その後 2026 年 5 月に **Anthropic 社の Claude (Opus 4.7)** を用いて追加されました。OL7 パッチ機構自体は検証済み(sed 置換動作、構文整合性、冪等性)ですが、**OL7 の end-to-end AMI ビルドは作者により検証されていません**。さらに 2026 年 5 月、**Anthropic 社の Claude (Opus 4.7)** を用いて Oracle Linux 6 の実験的サポートを追加しました。事前の 2 フェーズ検証(Phase A:静的検証 9 項目 — osinfo-db、ISO チェックサム、リポジトリ HTTPS、dracut フラグ、cloud-init 等。Phase B:libvirt 11.5 / qemu 10.0 環境で virt-install + Anaconda 13.21.263 TUI ブートテスト)を経て、2 つのランタイムパッチおよび動的生成 `distr/ol6-slim/` の構文検証は完了していますが、**OL6 の end-to-end AMI ビルド(kickstart 完走から AWS Nitro 起動まで)は作者により検証されていません**。

さらにその後の 2026 年 5 月のクロスバージョンリファクタリング(同じく Anthropic Claude Opus 4.7 を使用)では、`S3_BUCKET` を 5 テンプレート全てで `my-oracle-linux-ami-import-bucket` に統一し、ランタイム解決チェーン `resolve_aws_region()`(IMDSv2 → IMDSv1 → `ap-northeast-1` フォールバック)を追加することで全テンプレートが `AWS_REGION=""` をデフォルトとできるようにし、上位の `UPDATE_TO_LATEST="yes"` デフォルトを各 env ファイルで明示宣言し Phase 4 でラッパー層パススルーを実装し、OL6 テンプレートの `ROOT_FS` デフォルトを `ext4` から `xfs` に切り替え(`/boot` を ext4 のまま維持する行アンカー付き sed パターンで GRUB Legacy 互換性を確保 — **ただしこれは後に `ext4` へ差し戻されました。実機インストールで anaconda-13 が OL6 の xfs ルートを拒否することが判明したためです。CHANGELOG / SPEC D.16 参照**)、5 つの `ISO_CHECKSUM` リファレンス値を RHEL 10.1 のビルドホスト上で `linux.oracle.com/security/gpg/checksum/` に対して検証しました。リファクタリングには README と SPEC の対応更新が含まれており、bash `-n` および shellcheck エラークラスでは静的検証済みですが、**リファクタリング後の構成での AWS 実環境 end-to-end 再実行は未実施です**。

本ラッパーから呼び出される上位の `oracle-linux-image-tools` プロジェクトは Oracle 社が独自に開発・公開しているもので、本リポジトリとは独立しています。 本ラッパーのライセンス条項は本ドキュメント末尾の[ライセンス](#ライセンス)セクションに記載されています。

### フィードバック / 修正依頼 / コントリビューション

問題報告、改善提案、または新しい Oracle Linux リリース用テンプレート追加の要望は、Issue を作成してください:

https://github.com/usui-tk/ai-generated-artifacts/issues

バグ報告では、以下を含めてください。

- **ビルドホスト**:OS / バージョン / インスタンスタイプ(EC2 の場合)/ nested-virt 有効化の有無
- **対象**:使用した `env.properties.aws-ol{N}`、およびカスタマイズしたキー
- **失敗したフェーズ**:エラー直前の `========== Phase N: ...` バナー
- **ログ抜粋**:失敗周辺の 10〜50 行(1000 行以上のログ全体ではなく)
- **すでに試したこと**:例: `${WORKSPACE}` のクリーン、WORKSPACE のファイルシステム切り替えなど

コードレベルの変更については、まず [`SPEC.md`](./SPEC.md) (English only) を参照してください。Part D(「既知の落とし穴と教訓」)は現実装ですでに対処済みのバグを記録しており、Part A は新コードが従うべき規約を定義しています。

---

## ライセンス

`build-ol-aws-ami.sh`、 `setup-vmimport-role.sh`、 および本ディレクトリ
内の関連 `env.properties.aws-ol{6,7,8,9,10}` ファイルは、 本
`ai-generated-artifacts` リポジトリの他のコンテンツと同じ
**MIT ライセンス** で提供されます。 ライセンス全文はリポジトリルート
の [`LICENSE`](../../../LICENSE) を参照してください。

要約:本スクリプト群は、 商用 AMI ビルドパイプラインへの組み込みや
姉妹リポジトリへの組み込みを含むあらゆる目的での使用・改変・配布が
許可されます。 ただし、 再配布時には元の著作権およびライセンス通知
を保持する必要があります。 本スクリプト群は、 上記の免責事項および
`LICENSE` ファイルに詳述されているとおり、 無保証で提供されます。
本ラッパーが駆動する上流の `oracle-linux-image-tools` プロジェクト
は、 Oracle が独立してライセンスを設定しており、 **本ライセンスの
対象外** です。 上流の条件については Oracle の上流リポジトリを参照
してください。
