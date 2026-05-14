# Oracle Linux AWS AMI Builder

[English](./README.md) | 日本語

> 📂 [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) リポジトリの [`scripts/aws/ol-aws-ami-builder/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/aws/ol-aws-ami-builder) 配下のアーティファクトです
> ⚠️ **AI 生成コンテンツ** — 実行前にソースコードを確認してください。[`scripts/` ディレクトリ規約](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md)で完全な免責事項を確認できます。
> 📐 **開発者向け仕様書**:[SPEC.ja.md](./SPEC.ja.md)([English](./SPEC.md)) — phase contract、ログ規約、env プロパティキー、現実装ですでに対処済みの過去の落とし穴を記録

Oracle 公式の [`oracle-linux-image-tools`](https://github.com/oracle/oracle-linux/tree/main/oracle-linux-image-tools) を活用し、Oracle Linux 8 / 9 / 10 (x86_64) の AWS AMI を自前で構築するためのラッパースクリプト一式です。

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
* 任意の環境で実行する前に、スクリプトのソースコード(または [SPEC.ja.md](./SPEC.ja.md) 仕様書)をレビューすること
* ビルドプロセスは **一時的な内部 VM のみ**でカーネルレベル機能の変更を行います。ビルドホスト自体は Phase 1 のパッケージ導入と Phase 2 の ACL 調整以外には変更されません。とはいえ、ビルドホストは **使い捨て**(専用 EC2 インスタンスが理想)として扱うことを強く推奨します

これらのツールは慎重に運用してください。**Oracle が公式に配布する AMI が存在する場合はそちらを優先**してください。本リポジトリは、Oracle が AWS Marketplace に対象リリースの AMI を公開していない、かつ利用者が自前ビルド AMI を自身の AWS アカウントで運用する意思がある、というニッチなケースを対象としています。

---

## 1. 構成ファイル

| ファイル | 用途 |
|---------|------|
| `build-ol-aws-ami.sh` | メインのビルドオーケストレータ。前提準備〜AMI 登録までを 9 フェーズに分けて実行。バージョン非依存で、`--env` で OL バージョンを指定 |
| `env.properties.aws-ol10` | **Oracle Linux 10 Update 1**(x86_64)用パラメータ |
| `env.properties.aws-ol9` | **Oracle Linux 9 Update 7**(x86_64)用パラメータ |
| `env.properties.aws-ol8` | **Oracle Linux 8 Update 10**(x86_64)用パラメータ |
| `setup-vmimport-role.sh` | AWS VM Import/Export 用の `vmimport` IAM サービスロールを初回のみ作成 |
| `README.md` | エンドユーザ向けドキュメント(英語、ベースライン) |
| `README.ja.md` | エンドユーザ向けドキュメント(日本語) |
| `SPEC.md` | 開発者向け仕様書(英語)— phase contract、ログ規約、設計判断の詳細 |
| `SPEC.ja.md` | 開発者向け仕様書(日本語) |

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
| OS | **Oracle Linux 9 / RHEL 9 / Ubuntu 22.04 以上** を推奨 |
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
./setup-vmimport-role.sh my-ol10-ami-import-bucket
```

このロールは AWS VM Import/Export が S3 から VMDK を読み出すために必須です。**初回 1 回のみ**作成してください。

### 5.4 環境設定ファイルの編集

ターゲットの Oracle Linux バージョンに合わせてテンプレートを選択します。

```bash
# Oracle Linux 10 Update 1
cp env.properties.aws-ol10 env.properties.local

# Oracle Linux 9 Update 7
cp env.properties.aws-ol9 env.properties.local

# Oracle Linux 8 Update 10
cp env.properties.aws-ol8 env.properties.local

vi env.properties.local
```

スクリプトは `ISO_URL` から OL のメジャー/アップデートバージョンを自動判別するため、バージョンを切り替える際は env ファイルを差し替えるだけ(または `ISO_URL` を別リリースに変更するだけ)で済みます。

**最低限変更すべき項目:**

| パラメータ | 例 |
|-----------|----|
| `WORKSPACE` | `/tmp/ol10-build-ws`(デフォルト。qemu ユーザーから普通に到達可能。`/tmp` が tmpfs でサイズ不足の場合は `/var/tmp/ol10-build-ws` に変更) |
| `S3_BUCKET` | `my-ol10-ami-import-bucket`(`setup-vmimport-role.sh` と一致) |
| `AWS_REGION` | `ap-northeast-1` |
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
| `--build-only` | VMDK 生成(Phase 5)までで停止。AWS 取り込みは別途実行したい場合 |
| `--skip-aws-import` | Phase 6〜8 をスキップ(`--build-only` と同等) |

### 6.3 Phase 0 の自動診断機能

Phase 0 では実行環境を自動検出し、問題があれば対応案内を出します。

**ケース A: M8i 系だがネスト仮想化が無効化されている場合**
```
[ERROR] EC2 上で CPU 仮想化拡張が露出していません
[INFO]  検出されたインスタンスタイプ: m8i.xlarge
[WARN]  [ケース A] m8i はネスト仮想化対応のファミリーですが、本機能が無効化されています。
[INFO]  対応手順: ネスト仮想化を有効化してください。
[INFO]    aws ec2 stop-instances --instance-ids i-xxxxx --region ap-northeast-1
[INFO]    aws ec2 modify-instance-cpu-options ...
```

**ケース B: ネスト仮想化非対応のインスタンスファミリーを使っている場合**
```
[WARN]  [ケース B] m5 はネスト仮想化非対応のインスタンスファミリーです。
[INFO]  選択肢 1 (推奨): ネスト仮想化対応の C8i / M8i / R8i 系に乗り換え
[INFO]  選択肢 2: ベアメタルインスタンスに乗り換え
```

**ケース C: ベアメタルインスタンスで KVM が使えない場合**
```
[WARN]  [ケース C] m5.metal はベアメタルですが /dev/kvm が利用不可です。
[INFO]  対応手順:
[INFO]    1) kvm モジュールがロードされているか確認: lsmod | grep kvm
[INFO]    2) 未ロードなら手動ロード: sudo modprobe kvm-intel
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

> **すべての設計判断の詳細**(phase 番号付け、ログ規約、env プロパティ自動検出、AWS 固有の癖)は [SPEC.ja.md](./SPEC.ja.md)([English](./SPEC.md))にあります。以下は運用者にとって特に重要なポイントのみ抜粋しています。各項目の歴史的経緯は SPEC の Part C を参照してください。

### 9.1 import-image ではなく import-snapshot + register-image

2 段階フロー(`import-snapshot` で EBS スナップショット作成 → `register-image` で AMI 属性付与)を採用することで、`BootMode`、ENA、NitroTPM、IMDS の設定を明示制御できます。`import-image` は便利ですが、AWS の OS 自動判別に依存しており、新しい Oracle Linux リリースは AWS のサポート OS リストに未登録の可能性があります。どの `register-image` フラグが無条件 / 条件付きかは SPEC §B.1 を参照。

### 9.2 ENA / NVMe ドライバ

`oracle-linux-image-tools` の `cloud=aws` ターゲットは、Amazon ENA ドライバと `cloud-init` をイメージに同梱します。OL8/9/10 のカーネル(UEK または RHCK)はネイティブで `ena` モジュールと `nvme` モジュールを含むため、Nitro インスタンスとの完全互換性のために別途のドライバ追加は不要です。

### 9.3 `BOOT_MODE_BUILD = "bios"`(AWS 向けは必須)

Oracle 上位の `bin/build-image.sh` は AWS 対象に対し `BOOT_MODE=bios` を強制し、`uefi` や `hybrid` は拒否します。生成 AMI は `legacy-bios` として登録されます。これは今日時点で **唯一動作する組み合わせ** です — 発見経緯は SPEC §C.4 を参照。AMI はすべての Nitro インスタンスタイプで起動可能。トレードオフとして、NitroTPM と UEFI Secure Boot は有効化できません。

### 9.4 cloud-init / ec2-user

`CLOUD_INIT="Yes"` と `CLOUD_USER="ec2-user"` を指定することで、AWS 慣習に合わせた `ec2-user` 経由の SSH 鍵ログインが可能になります。3 つの env テンプレートすべてでデフォルト。

### 9.5 ネスト仮想化を主推奨にする理由

2026 年 2 月以降、AWS が C8i / M8i / R8i でネスト仮想化を正式サポートしたことで、以下が達成されました。

1. **Oracle 公式ツールに準拠**したまま、**圧倒的に安価**にビルド可能(`m8i.xlarge` で約 $0.30/ビルド vs `c5n.metal` で約 $5/ビルド)
2. **CI/CD パイプライン化が現実解**になる経済性
3. ベアメタル特有の起動遅延(数分待ち)が発生せず、ビルド全体時間が短縮
4. Spot Instance / Auto Scaling との組み合わせも視野に入る

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

### Phase 7 で `ClientError: Unsupported kernel version`

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

## 13. 来歴とライセンス

### AI 生成について

本ラッパースクリプトは、**Anthropic 社の Claude (Sonnet 4.5)** との対話を通じて 2026 年 5 月に反復的に開発・改善されたものです。Oracle Linux 8 / 9 / 10 の AWS 上での実ビルドで end-to-end の動作確認まで完了しています。

本ラッパーから呼び出される上位の `oracle-linux-image-tools` プロジェクトは Oracle 社が独自に開発・公開しているもので、本リポジトリとは独立しています。

### ライセンス・保証

**現状有姿(AS IS)で、いかなる保証もなく**提供されます。本スクリプトの利用によって生じたいかなる損害についても、作者および AI ツールは責任を負いません。完全な免責事項は[リポジトリルートの免責事項](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.ja.md)を参照してください。

### フィードバック / 修正依頼 / コントリビューション

問題報告、改善提案、または新しい Oracle Linux リリース用テンプレート追加の要望は、Issue を作成してください:

https://github.com/usui-tk/ai-generated-artifacts/issues

バグ報告では、以下を含めてください。

- **ビルドホスト**:OS / バージョン / インスタンスタイプ(EC2 の場合)/ nested-virt 有効化の有無
- **対象**:使用した `env.properties.aws-ol{N}`、およびカスタマイズしたキー
- **失敗したフェーズ**:エラー直前の `========== Phase N: ...` バナー
- **ログ抜粋**:失敗周辺の 10〜50 行(1000 行以上のログ全体ではなく)
- **すでに試したこと**:例: `${WORKSPACE}` のクリーン、WORKSPACE のファイルシステム切り替えなど

コードレベルの変更については、まず [SPEC.ja.md](./SPEC.ja.md) を参照してください。Part C(「既知の落とし穴と教訓」)は現実装ですでに対処済みのバグを記録しており、Part A は新コードが従うべき規約を定義しています。
