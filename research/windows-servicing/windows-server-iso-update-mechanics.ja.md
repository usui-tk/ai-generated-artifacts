# Windows Server ISO 更新メカニズム:実務者のためのナレッジベース

> 🇯🇵 日本語版
> 英語版: [`windows-server-iso-update-mechanics.en.md`](./windows-server-iso-update-mechanics.en.md)

## アブストラクト

Microsoft Evaluation ISO と累積更新プログラムの束から完全にパッチ済みの Windows Server インストールメディア(いわゆる「slipstream 済 ISO」)を構築する作業は、見かけほど単純ではありません。WIM をマウントし、 MSU パッケージを適用し、 必要に応じてブートバイナリを再構築し、 再パッケージング — というハイレベルなレシピは 10 年以上にわたって文書化されています。 しかし、 単一の Microsoft ドキュメントには記載されていない事項として、 実務者が 2024 年以降のセキュアブート環境でクリーンに起動する Server 2016 / 2019 / 2022 / 2025 ISO を出荷するために実際に踏破しなければならない「横断的関心事マトリクス」があります。具体的には:Microsoft アカウント認証なしにパッチメタデータを発見する方法、 `bootmgfw.efi` とその `_EX` 兄弟ファイルの Authenticode チェーンの解釈方法、 LCU(Latest Cumulative Update)適用前に Servicing Stack Update(SSU)の依存関係を解決する方法、 物理サーバを開封せずに結果を検証する方法 — などです。

本記事は、 実際の ISO 更新パイプラインで数か月にわたる改訂サイクルを通じて蓄積された技術的な発見の統合です。 これは特定のツールに対する how-to ガイドではありません。 目的は、 言語やフレームワークの選択に関わらず、 今後の実装者(人間あるいは LLM)がナビゲートしなければならないナレッジ表面を記録することにあります。 記事末尾の Provenance(出典)セクションで、 本ドキュメントに統合された投資ログの元のリポジトリを示しています。

**適用範囲（Scope of applicability）。** 本記事は、 Windows Server LTSC インストールメディアのオフラインサービシングおよび再構築ワークフローに特化しています。 クライアント版 Windows、 Windows Update for Business のポリシーオーケストレーション、 および稼働中のインプレースサービシングは意図的にスコープ外としています。 本記事の発見を、 独立した検証なしにこれらの領域へ一般化すべきではありません。

### 調査手法(Methodology)

本記事の発見はドキュメントのみからではなく、 経験的に導出されたものです。 それらを生み出した調査は、 複数の月例 Patch Tuesday サイクルにわたって以下の手法を組み合わせて繰り返しました:

- **実 cab の検査**:連続する `wsusscn2.cab` スナップショットに対して Master XML をパースし、 スキーマを仮定するのではなく実際の依存性・バンドル・ペイロード構造を観測。
- **WIM の検査**:Server 2016 / 2019 / 2022 / 2025 の Evaluation メディアを横断し、 `\Windows\Boot\` レイアウトとバージョンごとの `_EX` ブートバイナリの有無を比較。
- **Authenticode チェーン検証**:`X509Chain.Build()` により、 直接の署名者の表示名を信頼するのではなく、 各ブートバイナリのチェーンを trust anchor まで辿る。
- **Microsoft Update Catalog の相互参照検証**:KB とビルドの対応、 および Catalog で観測された combined LCU/SSU ダウンロード挙動を確認。
- **WSUS および Microsoft Learn ドキュメントとの比較**:公式に公開されている事実（Classification GUID、 release-info のビルド/KB テーブル）について照合。
- **月例 Patch Tuesday サイクルを横断した再ビルド検証**:新しい更新に対して end-to-end ビルドを再実行し、 観測が単一スナップショットの反映ではなく時間を通じて成立することを確認。

ある主張がこれらの手法のうち 1 つにしか基づかない場合、 確信度レベルのセクション（§10）でその旨を明示しています。

---

## 1. 背景と対象読者

Microsoft は Windows Server を 2 種類のインストール可能な形式で提供しています:**Evaluation ISO**(Microsoft Evaluation Center からダウンロード可能、 180 日の期限付き、 ライセンス契約なしで自由に入手可能)と、 **小売 / ボリュームライセンス ISO**(Microsoft 365 管理センター、 Volume Licensing Service Center、 または Open Value 契約を介して取得)です。 実装者主導の ISO 自動化では Evaluation ISO が最も実用的な入力となることが多いですが、 メディアの再配布・保管は Microsoft のライセンス条項に従う必要があります（例えば CI アーティファクトストアへチェックインする前に、 Evaluation Center の条項がそれを許可しているか確認してください）。

そのような Evaluation メディアから「完全にパッチ済み」の ISO を構築する作業を行う実務者は、 通常以下のような問いから始めます:*「install.wim に最低限どの MSU および CAB パッケージを適用すれば、 イメージがデプロイされて起動したときに、 最新の Patch Tuesday レベルとなり、 かつ PCA2011 を信頼しなくなったセキュアブート環境で受け入れられるか?」*。 ナイーブな回答 — 「今月の LCU を適用する」 — は不完全です。 完全な回答は少なくとも以下に触れます:

- どの **パッチメタデータ表面**(release-info Markdown、 .NET CU リリースノート、 Microsoft Update Catalog、 `wsusscn2.cab`)が必要な情報を実際に公開しているか
- 発見した LCU が事前に **Servicing Stack Update** の適用を要求するかどうか
- install.wim にすでに **PCA2023 署名済ブートバイナリ** が含まれているか、 あるいは Microsoft の `Make2023BootableMedia.ps1` リファレンススクリプトを介して合成する必要があるか
- ビルド後に、 ブートバイナリが期待される Authenticode チェーンを持つことを **検証する方法** — PowerShell の `Get-AuthenticodeSignature` コマンドレット自体にプレゼンテーション上の落とし穴があり、 統合されたコーパス中で少なくとも 1 回の調査を誤導したという事実を踏まえて

本記事は、 これらのトピックを順に取り上げ、 2024-Q4 から 2026-Q2 の Patch Tuesday サイクルから抽出した具体例を交えながら説明します。 読者は Windows servicing の用語(LCU、 SSU、 MSU、 CAB、 WIM、 DISM)に定義レベルで親しんでいることを想定します。 セクション 5 と付録 A で、 非自明な使われ方をする用語を補強します。

本記事が **扱わない** 範囲:ブート可能 USB の作成、 OEM イメージのカスタマイズ、 Windows Update for Business のポリシー策定、 対応する Linux ディストリビューションのサービシングトピック。 これらは他の場所で十分に文書化されています。

高レベルでは、 本記事が描き出す end-to-end ワークフローは次のような形をしています。 各段階は後続の 1 つ以上のセクションの主題であり、 この図は詳細に入る前に読者の見取り図を与えるためだけに置いています:

```text
 release-info / .NET リリースノート       (§2.1, §2.2  — 発見)
            |
            v
     KB 発見レイヤー                       (§2.1–§2.3  — 何を取得するか)
            |
            v
   Microsoft Update Catalog               (§2.3       — 権威ある成果物)
            |
            v
     成果物の取得 (.msu / .cab)            (§2.3, §5.2 — LCU + SSU)
            |
            v
      wsusscn2 パース (Master XML)         (§2.4       — オフライン発見)
            |
            v
 依存性 / supersedence DB                 (§5.5, §5.6 — 事前検証データ)
            |
            v
     事前検証                             (§5.5, §8.1 — fail closed)
            |
            v
        WIM サービシング (LCU 適用)        (§3.3, §4   — パッチレベル)
            |
            v
   PCA2023 メディア合成 (_EX)              (§3.2–§3.6  — Secure Boot)
            |
            v
     検証パイプライン                     (§3.7, §8   — 署名者チェーン + レイアウト)
            |
            v
  Hyper-V / 物理ブートテスト               (§3.7, §8.4 — ファームウェア信頼)
```

このチェーン全体を貫く決定的なアーキテクチャ上の区別は、 上位段階（発見と依存性分析）が速度のためにリバースエンジニアリングしたオフラインメタデータに依拠する一方、 下位段階（適用可能性・サービシング・ブート受容）は Microsoft 自身の権威あるロジックに委ねる、 という点です。 この境界を念頭に置くと、 記事の残りが追いやすくなります。

---

## 2. Microsoft のパッチメタデータ表面

ある Patch Tuesday の Windows Server 用更新一式は、 少なくとも 4 つの異なる Microsoft 運用の表面に分散しています。 どれも他の表面の完全なインデックスにはなっておらず、 それらの間の関係は過去数年で変化しており、 動作するパイプラインはその変化に対応する必要があります。

### 2.1 release-info Markdown ソース

この作業で最も活用が不足している Microsoft 表面は、 `learn.microsoft.com/en-us/windows/release-health/windows-server-release-info` にある **Windows Server release-info ページ** です。 同じ URL に `?accept=text/markdown` を付加してリクエストすると、 Microsoft Learn のコンテンツネゴシエーション層は、 レンダリングされた HTML ではなく生の GitHub-flavored Markdown としてページを返します。 本文はソース Markdown テーブルそのもの — ラッパーなし、 JavaScript なし、 認証なし、 通常使用ではレート制限ヘッダーも観測されません。

このページは GitHub ベースです:YAML フロントマターには `gitcommit` および `git_commit_id` フィールドが含まれ、 これらは `https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md` を指しています。 これは、 注意深い実装者が再現性のために特定のコミットハッシュにピン留めでき、 原理上は `/commits` エンドポイントを監視して構造変化を検知できることを意味します。

ページに含まれるコンテンツ:

| コンテンツ | カバレッジ |
|---|---|
| OS ごとの月次 LCU + OOB + プレビューロールアップテーブル | Server 2016 は 2016-08 から、 Server 2019 は 2018-10 から、 Server 2022 は 2021-08 から、 Server 2025 は 2024-10 から — ギャップは稀(Server 2016 の GA 月に 1 件) |
| Server 2025 と Server 2022 の Hotpatch カレンダー | 1 年分のベースライン vs ホットパッチの月割り、 Microsoft がスケジュール済だがリリース前のエントリも含む |
| 更新タイプの文字 | "B" = Patch Tuesday、 "C"/"D" = プレビューロールアップ、 "OOB" = 緊急配信、 "A"/"E" = 過去の例外 |

ページが **含まない** コンテンツ:

- .NET Framework 累積更新(これらは独自のリリースノートページを持つ — セクション 2.2)
- Dynamic Update.Setup または Dynamic Update.SafeOs(Catalog 経由のみ — セクション 2.3)
- 言語パック(Catalog 経由のみ)
- スタンドアロンの Servicing Stack Update を独立した行として(これらは Catalog 上では LCU とバンドル配信され、 release-info には独立して列挙されません)

Hotpatch カレンダーには特記事項があります。 暦年 2024 / 2025 / 2026 がすべて公開されています。 Server 2022 の CY2024 には 1 つの例外があります — 8 月が期待される「Hotpatch」ではなく「Baseline (Restart)」とラベル付けされていました — おそらく Microsoft が Server 2022 のベースラインケイデンスを CY2024 と CY2025 の間で調整し、 正典の 1 月 / 4 月 / 7 月 / 10 月パターンに合わせたためです。 実務上の含意は:**正典のベースライン月リストはカレンダーの行ごとの `Type` フィールド** であり、 ハードコードされた `{1, 4, 7, 10}` ルールではありません。 1 月 / 4 月 / 7 月 / 10 月ヒューリスティックを使う実装者は、 CY2025 と CY2026 では正解を得ますが、 CY2024 の 1 セルで誤った答えを得ます。

このページのパーサーは小さくて済みます。 2 つのテーブルレイアウトでコンテンツ全体をカバーできます:5 カラムヘッダー `| Servicing option | Update type | Availability date | Build | KB article |` を持つ月次リリーステーブルと、 6 カラムヘッダー `| Month | Update type | Type | Availability date | Build | KB article |` を持つ Hotpatch カレンダーです。 標準ライブラリのみの 300 行程度の Python パーサーで両方を JSON に抽出できます。 パーサーはヘッダーテキストを正確に検証し、 Microsoft がカラムをリネームしたら継続を拒否すべきです — これにより構造ドリフトが発生したら人間のレビューがトリガーされます。 加えて実装では、 取得したコミット ID・取得タイムスタンプ・生 markdown の SHA-256 をパース済み JSON とともに永続化すべきです。 これにより上流の構造ドリフトを検知でき、 既知の入力に対する再現可能なパースが保てます。

### 2.2 .NET Framework 累積更新リリースノート

.NET Framework 累積更新の companion 表面は、 `learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes` のリリースノートインデックスです。 ここでも同じ `?accept=text/markdown` スイッチが機能します。 各月次ページ(例:`release-notes/2026/04-14-april-cumulative-update`)は、 「## Summary tables」セクションを含む Markdown を返します。 テーブルレイアウトは月をまたいで一貫しています:

| 行タイプ | カラム 1 | カラム 2 |
|---|---|---|
| OS 行 | 太字の OS 名 | オプションの太字「アンブレラ」KB |
| ランタイム別行 | プレーンテキスト ".NET Framework `<バージョン>`" | `[KB######](url)` リンク |

代表的な月(2026-04)の OS ごとの行数:

| OS | 上流での OS タイトル | アンブレラ KB | ランタイム別行 |
|---|---|---|:-:|
| Server 2025 | Microsoft server operating system, version 24H2 | (なし) | 1 |
| Server 23H2 | Microsoft server operating system, version 23H2 | (なし) | 1 |
| Server 2022 | Windows Server 2022 | あり | 2 |
| Server 2019 | Windows 10 1809 and Windows Server 2019 | あり | 2 |
| Server 2016 | Windows 10 1607 and Windows Server 2016 | (なし) | **2** |
| Server 2012 R2 | Windows Server 2012 R2 | あり | 3(LTSC ISO 用途では対象外) |

Server 2016 の行数 **2** にフラグを立てる価値があります。 「アンブレラ KB タイトルに 'for Microsoft .NET Framework' を含む」ヒューリスティックを使う Catalog スクレイプ実装は、 Server 2016 の .NET CU KB を **1 つだけ** 認識します — .NET 4.8 の兄弟だけです — なぜなら .NET 3.5 / 4.6.2 / 4.7.x の兄弟は、 そのヒューリスティックと一致しない別のアンブレラタイトルで配信されているからです。 リリースノートページは両方の行を直接公開しており、 したがって正典のソースです。 .NET 4.8 を有効化して起動する Server 2016 イメージは欠落した兄弟を目に見えて欠くことはありませんが、 4.7.x を保持するイメージは欠きます。

.NET リリースノートページも GitHub ベース(`dotnet/docs` リポジトリ)なので、 コミットピン留めは release-info と対称的に可能です。

### 2.3 Microsoft Update Catalog

`catalog.update.microsoft.com` の Microsoft Update Catalog は、 実際の `.msu` および `.cab` のダウンロード URL を公開している唯一の表面です。 KB 番号をダウンロード可能な成果物に解決するには、 実務者はここを使う必要があります。 Catalog は HTML レンダリング、 JavaScript 駆動で、 スクレイピングに敵対的なことで悪名高い表面です。 本番品質のアプローチは、 これを厳密に URL リゾルバとして使用すること(KB が与えられたらダウンロードを取得)であり、 ディスカバリ表面として使用しない(月が与えられたら LCU っぽいタイトル文字列を探す)ことです。

Catalog インタラクションには 2 つの十分に文書化された落とし穴があります:

**Server 2019 と Server 2022 の間で OS 命名が変わった**。 古い OS は更新タイトルでユーザー向けブランド名を使用します:「Windows Server 2019」「Windows Server 2016」。 Server 2022 から、 Microsoft は「Microsoft server operating system, version `<NNHN>`」という命名に切り替えました。 `<NNHN>` はコードネームバージョン:Server 2022 は `21H2`、 Server 2025 は `24H2` です。 Catalog で「Windows Server 2025 2026-04」を検索しても有用な結果は返りません。 「Microsoft server operating system version 24H2 2026-04」を検索すると LCU と依存性が返ってきます。 タイトル文字列ヒューリスティックは両方の命名規則を維持し、 OS バージョンによって分岐する必要があります。

**Server 2025 LCU は現状 2 ファイルのダウンロードセットに解決される**。 すべての Server 2025 LCU 解決は *2 つの* ダウンロード URL を返します:LCU 本体に加えて、 固定 KB(現状は `KB5043080`)— これは Servicing Stack ベースラインです。 これはどの LCU 月をリクエストしても同じ Servicing Stack パッケージです。 運用上、 これは Server 2025 にスタンドアロン SSU が存在しないことを強く示唆します — Microsoft は Catalog の `DownloadDialog.aspx` を介して、 すべての LCU と並んで SSU 依存性を 2 ファイルバンドルとして配信します。 「LCU」URL のみをダウンロードし 2 番目を無視するパイプラインは、 LCU が `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED` で適用に失敗する WIM を生成します。 正しいパターンは:2 つの `.msu` ファイルをダウンロードし、 依存性順序の判断は `Add-WindowsPackage` に任せること — これは SSU 順序を自動的に処理します。 Server 2025 で観測されたこの 2 ファイル LCU+SSU 挙動は、 Microsoft の正式なサービシング保証ではなく、 現行 Catalog の挙動として扱うべきです。

release-info から取得した KB を直接(KB のみ入力、 タイトル文字列ヒューリスティックなしで)Catalog 経由でダウンロード URL に変換できるかという検証では、 代表的な 8 サンプルテストの成功率は 8 / 8 です。 したがって Catalog は実用的な URL リゾルバですが、 貧弱なディスカバリ表面です。 元の調査からの広範な試行錯誤から得られた建築的教訓は次の通りです:**release-info / .NET リリースノートが発見者、 Catalog がリゾルバ**。 これによりタイトル文字列ヒューリスティック表面とそれがもたらす脆弱性を最小化できます。

### 2.4 wsusscn2.cab オフラインサービシングデータベース

「更新 KB-A は KB-B が事前にインストールされていることを要求するか?」 という形式の問いに対して、 最も権威あるオフラインのメタデータソースは **Windows Update Standalone Scan** データベース(`wsusscn2.cab`)です。 これは `https://catalog.s.download.windowsupdate.com/d/msdownload/update/v3/static/trusted/.../wsusscn2.cab` で複数 GB の単一 CAB ファイルとして配信されます。 このファイルはおおよそ月 2 回公開され、 最後の公開以降にリリースされた更新を見るには新しいダウンロードが必要です。 なお、 最終的な適用可能性の評価は依然として Windows Update Agent のサービシングロジックが行います。

`wsusscn2.cab` はネストされた CAB で、 以下のような高レベル構造を持ちます:

```
wsusscn2.cab
├── (75 件程度の最上位ファイル)
├── package.cab
│   └── package.xml          ← "Master XML" — グローバル依存性グラフ
└── packageN.cab               (更新バンドルごとに 1 つ、 N = 1, 2, 3 ...)
    ├── update.mum
    ├── update.cat
    └── (更新ごとの詳細 XML)
```

> **Master XML 自身が名乗るフォーマット名(ルート要素 + 名前空間)。**
> 見落としやすいものの、 このデータ表面全体にとって最も権威ある命名の
> 典拠なので、 押さえておく価値があります:`package.xml` を展開して
> 最初の要素を見ると、 **ルート要素は `<Updates>` でも `<Package>` でも
> なく `<OfflineSyncPackage>`** であり、 既定の XML 名前空間として
> **`http://schemas.microsoft.com/msus/2004/02/OfflineSync`**(`msus` =
> Microsoft Update Services)を宣言しています。 観測されるルートは次の
> 形です:
>
> ```xml
> <OfflineSyncPackage MinimumClientVersion="5.8.0.2678"
>     PackageId="..." PackageVersion="1.1" ProtocolVersion="1.0"
>     SourceId="..."
>     xmlns="http://schemas.microsoft.com/msus/2004/02/OfflineSync">
>   <Updates>
>     <Update UpdateId="..." RevisionId="..." IsLeaf="..." IsBundle="...">
>       ...
> ```
>
> つまり **「offline sync package」は、 このメタデータに対する Microsoft
> 自身のフォーマット名** であり、 データ自身の中で宣言されています —
> `wsusscn2.cab` は単なる配布ファイル名にすぎません(「WSUS オフライン
> スキャンファイル」は口語的な呼称)。 このフォーマットを消費するコード
> を命名する際、 不透明な配布ファイル名 `wsusscn2` ではなく権威ある
> `OfflineSyncPackage` / `OfflineSync` という用語から識別子を導出すると、
> 初見の読み手にも意図が伝わりやすく、 *オフライン* の同期メタデータを
> *オンライン* の Microsoft Update Catalog 表面(§2.3)と明確に区別できます。
> 名前空間中の `2004/02` はスキーマ系統が 2004 年以来安定していることを
> 示しますが、 それでも前方互換性は保証されないものと考えるべきです
> (下記サポート状況の注記を参照)。

オフラインでの依存性分析において、 Master XML(`package.xml`、 展開後 ~108 MB)は CAB 内で通常最も有用な成果物です。 Windows Update 全体の各更新リビジョンについて、 以下が記録されています:

- `<Categories>` — OS ファミリ GUID(Product)と Classification GUID
- `<Prerequisites>` — この更新を適用する前に存在しなければならない UpdateId GUID のフラットリスト
- `<SupersededBy>` — `<Revision Id>` エントリの逆方向リスト(最近のスナップショットで 14,000 件超);「この LCU はすでに supersede されているか?」を検出するのに役立つ
- `<PayloadFiles>` — 実ペイロードファイルへの `<File Id="<digest>">` 参照(leaf 更新側に存在）
- `<FileLocation>` — `Id="<digest>" Url="...">` エントリ。ペイロードの digest をダウンロード URL に解決する（URL には KB 番号の正規表現を適用できる）
- `<BundledBy>` — `<Revision Id>` の親リンク。Combined LCU+SSU パッケージの検出と、leaf のペイロードを bundle へ集約するのに使用

> **実データによる訂正(2026-05-12 の実 cab 検証）。** Master XML には
> `<KBArticleID>` element は **存在しません** — KB 番号は package.xml には
> 一切含まれません。KB 番号は per-package CAB メタデータと Microsoft Update
> Catalog にのみ存在します（下表参照）。したがって Master XML 内の更新は
> `UpdateId` / `RevisionId` で識別します。KB 番号は `<FileLocation>` の URL に
> 時折現れる `kb(\d+)` トークンから *推定* するしかなく、Master XML から
> 直接得ることはできません。

Master XML と個別の `packageN.cab` フラグメントは、 **重複する依存性メタデータを異なる視点から記録** しています — 両者は意味的に等価ではありません。 Master XML はフラット化されたリポジトリ全体の要約であり、 各 `packageN.cab` は更新ごとのより豊かな適用可能性セマンティクスを保持しています:

| 情報 | Master XML | パッケージ別 CAB |
|:---|:-:|:-:|
| `<Prerequisites>` | ✓ フラット GUID リスト | ✓ 完全な `<AtLeastOne>` 判断木 |
| `<SupersededUpdates>`(順方向) | ✗ | ✓ |
| `<SupersededBy>`(逆方向) | ✓(2026-05 スナップショットで 14,059 件) | ✗ |
| `<BundledUpdates>`(子) | ✗ | ✓ |
| `<BundledBy>`(親) | ✓ | ✗ |
| `<PayloadFiles>` & `<FileLocations>` | ✓ | ✗ |
| `<KBArticleID>` element | ✗ | ✓(Metadata 内) |
| `<Categories>`(OS ファミリ GUID) | ✓ | ✗ |
| `<ApplicabilityRules>` | ✗ | ✓ |

単純な前提条件の発見（例:「KB5087537 は何に依存するか?」）には Master XML で通常は十分です。 完全な適用可能性評価や分岐解決ロジック（例:「どの依存性 / バンドル判断木の枝がこの OS リビジョンと一致するか?」）には、 パッケージ別 CAB メタデータ — あるいはより信頼性の高い手段として Windows Update Agent の適用可能性評価 — が依然として必要になる場合があります。

Master XML のパースはそのスケールに注意が必要です。 コモディティハードウェアでの代表的な計測値:

| 操作 | 時間 | メモリピーク |
|---|---:|---:|
| 7-Zip: `wsusscn2.cab` → 75 件の最上位ファイル | 4.3 秒 | (低) |
| 7-Zip: `package.cab` → `package.xml`(108 MB) | < 1 秒 | — |
| `XmlDocument.Load` の `package.xml` | 4.2 秒 | +536 MB |
| Master XML 文字列検索(10 タグ) | 1.9 秒 | +113 MB |
| パッケージ別 CAB スキャン(`packageN.cab` 内 12,500 ファイル) | 6.7 秒抽出 + 127.9 秒スキャン | < 50 MB |
| 仮想的な全パッケージ別スキャン(全 75 CAB) | 約 2.5 時間 | 15-20 GB ディスクピーク |

全パッケージ別スキャンは定期的な refresh には実用的ではありません。 Master XML のみのストリーミング `XmlReader` パーサーが実用的な妥協点です:数十秒で各 `<Prerequisites>`、 `<SupersededBy>`、 `<BundledBy>`、 `<PayloadFiles>`、 `<FileLocation>` を抽出し、 ほとんどの事前検証質問に答えられる小さな JSON 依存性データベース（本プロジェクトが用いる in-scope bundle 粒度で約 0.2 MB）を生成できます。 完全なオフライン WUA 適用可能性評価は Master XML の直接パースよりも大幅に低速です — これは想定どおりで、 WUA が直接的なメタデータ抽出ではなく、 完全な適用可能性ルール・supersedence チェーン・コンポーネント状態を評価するためです — したがって発見（discovery）ワークフローよりも検証（validation）ワークフローに適しており、 これが、 本パイプラインが発見には Master XML パースを用い、 WUA を最終的な適用可能性検証に留保している理由です。

> **サポート状況に関する注記。** `package.xml` の直接パースは、 観測されたメタデータ構造に基づく実装手法であり、 Microsoft がサポートする API 契約ではありません。 スキーマは予告なく変更され得ます。 最終的な適用可能性・インストール可能性の判断は、 権威ある適用可能性評価器（authoritative applicability evaluator）である Windows Update Agent のサービシングロジック（マウント済みイメージに対するオフライン WUA スキャン）で検証すべきです。 スキーマがサポート外であるにもかかわらず Master XML が運用上有用であり続けるのは、 依存関係をリポジトリ全体の形で露出し、 完全なオフライン WUA 適用可能性スキャンよりも桁違いに高速に照会できるためです — これが、 発見には Master XML を用い、 最終検証には WUA を留保する理由です。 その複雑さにもかかわらず `wsusscn2.cab` が他に代えがたい価値を持つのは、 Windows サービシングエコシステム全体の前提条件・supersedence 関係をリポジトリ規模で露出する、 広くアクセス可能な唯一のオフラインメタデータコーパスだからです。 とはいえ、 将来の wsusscn2 スキーマ改訂をまたいだ互換性は一切保証されないものと考えるべきです。

**設計思想（Design philosophy）。** 本ワークフロー全体を貫く指導原則は、 リバースエンジニアリングしたメタデータは発見と高速化のために用いつつ、 最終的な適用可能性・インストール可能性の判断は可能な限り Microsoft 自身のサービシングロジック（WUA）に委ねる、 というものです。 したがってサポート外のメタデータは権威あるものではなく助言的なものとして扱います。 本パイプラインは、 サポート外または構造的に曖昧なメタデータに対して意図的に fail-closed（安全側に停止する）設計思想を採用します:予期しない構造に遭遇したパーサーは推測するのではなく中断して人間のレビューを要求し、 前提条件の欠落はパイプラインを停止させ、 署名の曖昧さは無害なエッジケースではなく失敗として扱います。 いかなる schema drift（スキーマのずれ）も、 黙って吸収するパースのエッジケースではなく、 人間のレビューを要する互換性イベントとして扱います。

#### 2.4.1 Category 階層の package.xml 内表現

§2.4 で Master XML の主要要素(`<Update>`、 `<Prerequisites>`、 `<SupersededBy>`、 `<FileLocation>`)を紹介しました。 もうひとつ重要な観察があります:**WSUS の Product カテゴリ階層そのものが、 Master XML 内に `<Update>` 要素として暗黙的に埋め込まれている** という事実です。

WSUS の Categories(Company、 ProductFamily、 Product、 UpdateClassification)は、 Update が `<Categories>` ブロックで参照する GUID として登場するだけでなく、 **その GUID をそのまま `UpdateId` として持つ `<Update>` 要素** が package.xml 内に独立して存在します。 つまり Category 自身が「Category を表す Update」として記録されているわけです。

Category Update の識別子:

| 属性 | 値 | 意味 |
|:---|:---|:---|
| `DeploymentAction` | `"Evaluate"` | このエントリは適用対象ではなく評価対象 |
| `IsSoftware` | `"false"` | このエントリはソフトウェア(実体パッケージ)ではない |
| `<Title>` / `<Description>` | (存在しない) | Master XML の Category Update は人間可読プロパティを持たない |
| `<Prerequisites><UpdateId>` | 親 Category の GUID | 階層を逆引きできる back-link |

具体例として Windows Server 2016 の Category Update:

```xml
<Update CreationDate="2017-05-31T01:22:24Z"
        DefaultLanguage="en"
        UpdateId="569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5"
        RevisionNumber="204"
        RevisionId="21923899"
        DeploymentAction="Evaluate"
        IsSoftware="false">
  <Prerequisites>
    <UpdateId Id="6964aab4-c5b5-43bd-a17d-ffb4346a8e1d" />
  </Prerequisites>
</Update>
```

`UpdateId="569e8e8f-..."` が「Windows Server 2016」という Product の GUID、 `Prerequisites/UpdateId Id="6964aab4-..."` が親 ProductFamily「Windows」の GUID です。

2026-05-12 取得の wsusscn2 で観測されたカウント:

| カテゴリ | 件数 |
|:---|---:|
| 全 `<Update>` | 136,102 |
| Category Update(`DeploymentAction="Evaluate"` AND `IsSoftware="false"`) | 4,199 |
| Windows ProductFamily(`6964aab4-...`)直下の Category | 154 |

Master XML は Title/Description などの人間可読プロパティを持たないので、 **Category の表示名は package.xml 単独からは取得できません**。 これは §B.19.8 で議論する Microsoft prose exclusion ルールとも整合します。 名前と GUID の対応を取るには外部参照(WSUS の公式 documentation、 kbupdate-library、 OSDBuilder の adjacent OSS、 または実 WSUS 環境での `Get-WsusProduct -TitleIncludes`)が必要です。 ただし scope filter のような自動処理にとっては、 **名前の解決は不要で、 GUID だけあれば十分** です。

Category 階層の逆引きで Server LTSC 系の Product GUID を同定する具体的手法と、 確定された GUID 一覧は §5.7 と §6.4 を参照してください。

### 2.5 CAB 展開方式の比較

元の調査で実時間のコストを生んだ実用的な注意:CAB 展開ツールの選択は重要です。

| 方式 | 評価 | 備考 |
|---|---|---|
| `expand.exe -F:` | **`wsusscn2.cab` には避ける** | 出力ディレクトリが CAB 内に存在するパスと重なるとセルフ上書きバグが発生。 `/Y` が指定されていても展開途中で `ERROR_FILE_EXISTS` を投げる |
| `Shell.Application` COM | 動作するフォールバック | 7-Zip より遅い、 ファイル単位のタイミングが非決定的、 アンチウイルスとの相互作用でハングすることがある |
| `7-Zip`(CLI またはライブラリ) | **推奨** | 高速(最上位は 5 秒未満)、 終了コード 0/1/≥2(ok / warn / fatal)が解釈しやすい、 決定的 |

最もクリーンなパターンは:`7za x -y -bd -bso0 wsusscn2.cab` を新しいステージングディレクトリへ展開し、 生成されたツリーを辿る、 です。

---

## 3. PCA2023 セキュアブート移行

2024 Patch Tuesday サイクルは、 セキュアブート自体の導入以来最も破壊的なセキュアブート変更を記録しました。 Microsoft は Windows ブートバイナリの署名に使用する Production Certificate Authority を **PCA2011**(`Microsoft Windows Production PCA 2011`、 Windows 8 以降使用)から **PCA2023**(`Windows UEFI CA 2023`)へとローテートしています。 ISO ビルド実務者にとってこれは「LCU がレジストリキーを更新する」変更ではありません。 「インストールメディア自体のブートマネージャーバイナリを再署名しなければならない」変更です。 これが重要なのは、 セキュアブートの信頼判断が Authenticode 検証時ではなく firmware time（ファームウェア時）に行われるためです:ISO のみを操作するツーリングは署名者チェーンを確認できますが、 ターゲットファームウェアが何を受け入れるかは確認できません。

### 3.1 PCA2023 とは何か、 何を置き換えるか

すべての署名付き Windows ブートバイナリ(`bootmgfw.efi`、 `bootmgr.efi`、 OS ローダーなど)は、 Microsoft の周知のルート認証局のいずれかに証明書チェーンで遡る Authenticode 署名を持っています。 ブートバイナリの関連チェーンは次の通りです:

- **PCA2011 チェーン(レガシー)**:leaf → `Microsoft Windows Production PCA 2011` → `Microsoft Root Certificate Authority 2010`
- **PCA2023 信頼チェーン(新)**:leaf → `Windows UEFI CA 2023` → `Microsoft Root Certificate Authority 2010`(またはプラットフォームの信頼アンカーによっては 2023 ルート)

このシフトは実機上で 2 段階で展開されています:

（セキュアブート内部に馴染みの薄い読者向け:DB は許可された署名認証局を、 DBX は明示的に失効された署名または認証局を保持します。）

1. **第 1 段階(2024-2026、 現在)**:Microsoft は PCA2023 で署名されたブートバイナリを出荷しますが、 ファームウェアアップデート(Windows Update またはベンダー固有のチャネル経由で配信)によって PCA2023 証明書がプラットフォームの DB(許可署名)へとローリングベースでプロビジョニングされます。 PCA2011 は引き続き DB に残ります。 両方のチェーンが受け入れられます。
2. **第 2 段階(2026 年末以降に発表予定)**:ファームウェアアップデートを受信したプラットフォーム上で、 PCA2011 が DB から DBX(失効署名)に移されます。 その時点で、 PCA2011 でのみ署名されたブートマネージャーを持つインストールメディアは、 更新済みプラットフォームでの起動に失敗します。

前方互換なインストールメディア（PCA2011 廃止後も起動可能であり続けることを意図したメディア）を生成したいパイプラインは、 PCA2011 が今日まだ受け入れられていても、 PCA2023 信頼チェーンを持つブートバイナリを出荷する必要があります。 これをどう行うかについての Microsoft のリファレンスは `Make2023BootableMedia.ps1` スクリプト(本記事執筆時点の最新版:v1.4、 日付 2026-03-13)で、 Microsoft Support 記事 KB5053484 を介して配信されています。

### 3.2 ステージングディレクトリ:EFI_EX、 Fonts_EX、 DVD_EX

Microsoft が PCA2023 ロールアウトに選んだメカニズムは、 **install.wim 内のデュアルステージング** です。 おなじみの `\Windows\Boot\EFI\`、 `\Windows\Boot\Fonts\`、 `\Windows\Boot\DVD\` ディレクトリと並んで、 更新された install.wim には `EFI_EX\`、 `Fonts_EX\`、 `DVD_EX\` の兄弟が含まれます。 `_EX` ディレクトリには同じブートバイナリ(およびフォントと DVD ブートリソース)が PCA2023 で署名されて格納されています。

ISO ビルドにおける `_EX` ディレクトリの役割:

- **ビルド時**:`Make2023BootableMedia.ps1` リファレンスロジックが、 マウントされた install.wim 内部から `_EX` 兄弟を出力メディアのルート(既存の ISO ルートレベルの `\boot\` および `\efi\` ディレクトリを置き換えまたは補完)へとコピーする
- **ランタイム**:PCA2023 がプロビジョニングされたセキュアブートプラットフォームが結果のメディアを信頼する

### 3.3 Server バージョンごとの install.wim 形状

各 Server バージョンの Evaluation ISO の install.wim を直接検査すると、 計画に組み入れなければならない重要な非対称性が明らかになります:

| OS | EFI 存在 | EFI_EX 存在 | `\Windows\Boot\` 内の総 `*.efi` 数 | メカニズム |
|---|:-:|:-:|:-:|---|
| Server 2016 EVAL ja-jp | ✓ | ✗ | 3 | `EFI_EX` は最近の LCU を適用することでビルド時に **合成** する必要がある。 LCU が WinSxS 経由で `_EX` バイナリを追加 |
| Server 2019 EVAL ja-jp | ✓ | ✗ | 3 | 2016 と同様 |
| Server 2022 EVAL ja-jp | ✓ | ✗ | 3 | 2016 と同様 |
| Server 2025 EVAL ja-jp | ✓ | ✓ | **6** | `EFI_EX` が **GA 時点で install.wim に同梱**;合成不要 |

Server 2016 / 2019 / 2022 では、 `EnableInstallWimUpdate=true` ワークフロー(LCU を install.wim に適用してから、 パッチ済 WIM から `_EX` を出力メディアに抽出)が必要です。 Server 2025 では、 EFI_EX が install.wim にすでに存在するため、 PCA2023 ブートバイナリ抽出のための EFI_EX 合成は **不要** です。 ただし、 パッチレベル準拠のための install.wim サービシング（LCU の適用）は依然として必要です — スキップできるのは `_EX` 合成ステップのみであり、 パッチ適用ステップそのものではありません。

2025 install.wim には EFI に追加で 1 ファイル含まれます:**`SecureBootRecovery.efi`**(PCA2011 署名)。 Server 2016 / 2019 / 2022 には存在しません。 このファイルはセキュアブートリカバリ手順に関連しており、 2025 に存在することは informational のみです — ビルド時の `_EX` 合成の問題には関係ありません。

### 3.4 Authenticode チェーン検証:Get-AuthenticodeSignature の落とし穴

PowerShell の `Get-AuthenticodeSignature` コマンドレットを EFI バイナリに対して実行すると、 戻り値オブジェクトは `SignerCertificate` プロパティを公開し、 慣習的な思考では、 このプロパティの `Issuer` フィールドがバイナリに署名した CA を示すと考えます。 **これは微妙ですが重要な意味で誤導的です。**

`SignerCertificate` の `Issuer` はチェーン内の **直接の署名者** — つまり leaf の親を返します。 しかし PCA2023 移行で問題となるのは「leaf の直接の署名者は誰か」ではありません — それは「ファームウェアが DB / DBX に対して検証する証明書チェーンの trust anchor となる CA は何か」です。 これを正しく回答するには、 `X509Chain.Build()` でチェーンを再構築して辿る必要があります。 これが重要なのは、 失敗が後段で現れるためです:直接の発行者によって正しく署名されているように見えるバイナリでも、 異なる trust anchor しか信頼しないファームウェアでは起動に失敗し得ます。

具体例として、 Server 2025 の `EFI_EX\bootmgfw_EX.efi` で観測されたもの:

```
Status         : Valid
Signer Subject : CN=Microsoft Windows, O=Microsoft Corporation, ...
Signer Issuer  : CN=Windows UEFI CA 2023            ← Get-AuthenticodeSignature から
Cert Thumbprint: (何らかの thumbprint)

Chain(X509Chain.Build() 経由):
  CN=Microsoft Windows
   └─ CN=Windows UEFI CA 2023
       └─ CN=Microsoft Root Certificate Authority 2010

=> PCA 2023 in chain: True
   PCA 2011 in chain: False
```

同じ Server 2025 install.wim 上の `\Windows\Boot\EFI\bootmgfw.efi` に対して、 同じコードは次を返します:

```
Signer Issuer  : CN=Microsoft Windows Production PCA 2011
=> PCA 2011 in chain: True
   PCA 2023 in chain: False
```

自然な一見の読みは、 PCA2011 ファイルが「壊れている」 もので PCA2023 ファイルが「新しいもの」だ、 というものです。 完全なチェーン検査でこれは確証されます。 しかし逆の間違い — 直接の署名者の *表示名* に「PCA 2011」という文字列が含まれているからといってチェーンを検証せずにバイナリが PCA2011 と仮定する — は実際の調査で発生しました。 防御的なコーディングパターンは:チェーン認証局の検出のために `SignerCertificate.Issuer` 表示文字列を信用しないこと;常にチェーンを再構築し、 thumbprint で期待されるルートまたは中間者を確認すること。

### 3.5 dual-sign vs single-sign と signtool /ds による検証

チェーン認証局の問題とは別の質問として、 単一のバイナリが複数の Authenticode 署名を持つかどうか(いわゆる「dual-sign」バイナリ)があります。 これは他のコンテキストでの実際の Microsoft パターン(ドライバーパッケージは SHA-1 と SHA-256 の両方の署名を持つことが普通)なので、 ブートバイナリも遷移期間中に PCA2011 + PCA2023 を dual-sign しているかもしれない、 と疑うのは合理的です。

`Get-AuthenticodeSignature` は **primary** 署名のみを返します。 secondary 署名を検出するには、 正典のツールは `signtool.exe verify /pa /all /v <file>` で、 ここで `/all` はすべての埋め込み署名を列挙し、 `/v` は冗長出力を生成します。 特定の署名インデックスを探るには、 `signtool verify /ds 0`、 `/ds 1`、 `/ds 2` などで明示的に取得します。

経験的に、 Server 2025 の `\Windows\Boot\EFI\bootmgfw.efi` も `\Windows\Boot\EFI_EX\bootmgfw_EX.efi` も 1 つを超える署名を持ちません。 パターンは single-sign です:`EFI\bootmgfw.efi` には PCA2011、 `EFI_EX\bootmgfw_EX.efi` には PCA2023 のいずれかであり、 同じファイル上に両方ではありません。 将来の Server バージョンでもこれが続くかは未知です。

実用的な落とし穴:`$ErrorActionPreference = 'Stop'` の下で PowerShell から signtool を実行する場合、 署名 1 つしか持たないファイルに対する `signtool verify /ds 1` 呼び出しは exit code 1 と stderr への "No signature found" を返し、 PowerShell はこれを終了エラーとして扱います。 スクリプトはループ途中で abort します。 修正は signtool を helper で wrap し、 呼び出しの間だけ `ErrorActionPreference` を `'Continue'` に切り替え、 exit code と output を明示的にキャプチャしてカスタムオブジェクトを返すことです — signtool の通常ケースの exit-code-1 動作を終了エラーとして伝播させないこと。

### 3.6 ファイルハッシュ vs Authenticode ハッシュ

Server 2025 で `\Windows\Boot\EFI\bootmgfw.efi` と `\Windows\Boot\EFI_EX\bootmgfw_EX.efi` を比較すると、 小さいですが概念的に重要な詳細が出てきます:

```
\Windows\Boot\EFI\bootmgfw.efi       : SHA256 47C12C1F26...    (ファイル全体)
\Windows\Boot\EFI_EX\bootmgfw_EX.efi : SHA256 47C12C1F26...    (ファイル全体)
```

2 つのバイナリは Authenticode 署名領域を除いた PE イメージ内容（すなわち Authenticode が測定する PE 内容）においてバイト同一です。 しかし 2 つのファイルに埋め込まれた Authenticode 署名は異なります:

```
\Windows\Boot\EFI\bootmgfw.efi       : PCA2011 で署名
\Windows\Boot\EFI_EX\bootmgfw_EX.efi : PCA2023 で署名
```

この区別は運用上重要です。 Authenticode ハッシングは、 Authenticode 署名自体のバイト(具体的には PE ヘッダー内の `IMAGE_DIRECTORY_ENTRY_SECURITY` 領域とチェックサムフィールド)を **除外** するように定義されています。 signtool が報告する "Hash of file (sha256)" は *Authenticode ハッシュ* であり、 *ファイルハッシュ* ではありません。 両方のバイナリは同じ Authenticode ハッシュを持ちますが(PE 本体が同一)、 `Get-FileHash` で直接測定するとファイルハッシュは異なります — 各ファイル末尾の署名 blob が異なるからです。

つまり Microsoft のアプローチは:既存の `bootmgfw.efi` の PE 本体を取り、 PCA2023 で再署名し、 結果を `bootmgfw_EX.efi` として保存する、 というものです。 PE コードは変更されず、 署名のみが新しいものです。 これはゴールに対する妥当な解釈です — 実行可能な PE セクションは変更されていないように見え、 観測可能な差異は Authenticode 署名チェーンに限られます;信頼アンカーのみが変わります。

他の `_EX` ファイルでは常に同じというわけではありません。 Server 2025 の `bootmgr_EX.efi` は `bootmgr.efi` と *署名を含めて* バイト単位で同一です — `_EX` サフィックスがあるにも関わらず PCA2011 署名を持ちます。 これは検査した Server 2025 メディアで観測され、 bootmgr_EX が PCA2011 署名コピーである旨を示す Microsoft の `Make2023BootableMedia.ps1` v1.4 のコメントと整合します。 Microsoft が正式なサービシング仕様を公開しない限り、 これは実装観測に基づく挙動として扱ってください;遷移期間のアーティファクトか永続的な設計選択かは、 まだ公式に文書化されていません。

### 3.7 ビルド済 ISO の PCA2023 readiness を検証する

ISO がブートルートへの `_EX` 置換を適用して構築された後、 ビルドパイプラインの作成者には検証問題があります:ハードウェアブートテストなしで、 出力 ISO が DB から PCA2011 を除去したセキュアブート環境で通過することを確認する方法はあるか?

Microsoft の `Make2023BootableMedia.ps1` v1.4 自体は **検証を一切行いません** — 純粋にファイルコピー操作です。 スクリプトは Authenticode 関連コードを参照しません。 Microsoft の設計上、 出力検証は呼び出し側の責任です。

実用的なビルド後検証アプローチは、 「ファイル存在 + 署名者チェーン」パターンです:仕様で PCA2023 信頼チェーンを持つべきとされるブートバイナリの小さい固定セットそれぞれについて、 出力 ISO 上の期待されるパスにファイルが存在することと、 その Authenticode チェーンに PCA2023 中間証明書が含まれることの両方を検証します。 Server 2025 の完全セットは 5 ターゲットです:

| 出力メディアルート上のターゲット | 期待チェーン |
|---|---|
| `\boot\bootmgr.efi` | PCA2011(意図的、 `Make2023BootableMedia.ps1` コメントに従う) |
| `\boot\bootmgr` | PCA2011(BIOS ブートファイル、 変更なし) |
| `\efi\boot\bootx64.efi` | **PCA2023** |
| `\sources\boot.wim` 内の更新済 `bootmgfw.efi` | **PCA2023** |
| `\setup.exe` | PCA2011(署名済インストーラ;ブートバイナリではない;PCA2023 不要) |

これらのターゲットを巡回し、 各々に対して `Get-AuthenticodeSignature` の後 `X509Chain.Build()` を試み、 4 状態の結果(`Pass`、 `PassWithNotes`、 `Warning`、 `Fail`)に集約する検証関数は、 決定論的なデプロイ前シグナルを与えます。 関数はすべてのレポートに SCOPE clarifier を付与しなければなりません — 次のようなもの:

> SCOPE: file presence + signer-chain only. Actual boot behaviour on firmware with PCA2011 revoked from DBX is NOT verified here. Manual boot test on hardware or a Hyper-V Gen2 VM with a PCA2023 Secure Boot template is required before production deployment.

パイプライン設計の観点では、 SCOPE clarifier はオペレータに正しい期待を設定します:検証関数からの `Pass` は必要ですが十分ではありません。 実際に証明されるのは、 ファイルシステム構造と Authenticode チェーンが正しいことだけです。 デプロイ対象のファームウェアが実際にチェーンを受け入れるかどうかは、 そのターゲットが Microsoft の PCA2023 DB プロビジョニング更新を受信したかどうかに依存し、 これは ISO のみを操作するツーリングの範囲外です。

検証が及ぶ範囲を明示することは、 オペレータの期待を正しく設定するのに役立ちます。 各検証レイヤーは厳密に異なるものを証明します:

| 検証 | 証明すること | 証明しないこと |
|:---|:---|:---|
| Authenticode チェーン検査 | ファイルが期待される署名者チェーンを持つ（例:PCA2023 で終端する） | いずれかのファームウェアがそれを受け入れること |
| ファイル存在チェック | メディアレイアウトが構造的に正しい（`_EX` バイナリが期待パスに存在） | バイナリが正しく署名されていること |
| Hyper-V Gen2 ブートテスト | ブートマネージャーが Hyper-V の仮想ファームウェアに受け入れられる | 物理 OEM ファームウェアが受け入れること（DB/DBX 状態は異なり得る） |
| 物理ハードウェアブートテスト | 特定の OEM ファームウェアの信頼 DB/DBX 状態が互換である | *別の* OEM/ファームウェア世代が互換であること |

どの行も単独では十分ではありません;各行は累積的であり、 実際の DB/DBX 信頼判断を代表的なターゲット上で行使するのは最下行だけです。

---

## 4. install.wim 構造:バージョン横断サーベイ

前セクションでは PCA2023 のコンテキストで `EFI_EX` などを議論しました。 本セクションでは、 Server バージョン全体で install.wim 自体に関する構造的事実を列挙します。 これはどのビルダーも対応しなければならない事項です。

### 4.1 最上位 `\Windows\Boot\` レイアウト

すべての Windows Server install.wim には `\Windows\Boot\` ツリーが含まれます。 対象範囲内の 4 つの LTSC バージョン(各バージョンの英語 EVAL Index 4 をリファレンスとして使用)で観測されたディレクトリ:

```
\Windows\Boot\
├── DVD\         (常に存在 — DVD ブートリソース)
├── EFI\         (常に存在 — PCA2011 署名 EFI ブートバイナリ)
├── Fonts\       (常に存在 — ブート時フォントファイル)
├── Misc\        (常に存在、 1 ファイル)
├── PCAT\        (常に存在 — BIOS ブートリソース)
└── Resources\   (常に存在)
```

Server 2025 のみ、 追加の 3 つの兄弟ディレクトリが現れます:

```
├── DVD_EX\      (Server 2025 install.wim のみ)
├── EFI_EX\      (Server 2025 install.wim のみ)
└── Fonts_EX\    (Server 2025 install.wim のみ)
```

Server 2025 上の `EFI_EX` ディレクトリは、 `Get-ChildItem -Recurse -File` でカウントすると合計 72 ファイルを含みます。 そのうち 2 つは `*.efi`(`bootmgfw_EX.efi`、 `bootmgr_EX.efi`)で、 70 個は `.mui` ローカライゼーションリソースと言語サブディレクトリファイルです。 ベアなディレクトリ列挙は `EFI_EX (72 files)` を報告し、 `*.efi` フィルタ列挙は `2 files` を報告します — どちらも正しく、 別々のものをカウントしています。

### 4.2 バージョン別 `*.efi` インベントリ

各 Server バージョンの install.wim の `\Windows\Boot\` 配下の完全再帰 `*.efi` 列挙:

| OS | 総 `*.efi` 数 | ファイル |
|---|:-:|---|
| Server 2016 | 3 | `EFI\bootmgfw.efi`、 `EFI\bootmgr.efi`、 `EFI\memtest.efi` |
| Server 2019 | 3 | 同じ 3 ファイル |
| Server 2022 | 3 | 同じ 3 ファイル |
| Server 2025 | 6 | `EFI\SecureBootRecovery.efi`、 `EFI_EX\bootmgfw_EX.efi`、 `EFI_EX\bootmgr_EX.efi` を追加 |

このリストのすべてのファイルは有効な Authenticode 署名を持っています。 各々の信頼チェーン — 具体的には、 直接の署名証明書とは区別される、 チェーンが終端するルート/中間階層である trust-anchor パス — は PCA2023 作業(セクション 3.7)の関連する質問です;ファイル存在の質問は上の表で回答されています。

### 4.3 インデックスとエディションのカバレッジ

`install.wim` は通常マルチインデックス WIM です(`dism /Get-ImageInfo /WimFile:install.wim` でそれらを列挙)。 慣習的なレイアウトは:

| Index | エディション |
|:-:|---|
| 1 | Standard(Server Core) |
| 2 | Standard(Desktop Experience) |
| 3 | Datacenter(Server Core) |
| 4 | Datacenter(Desktop Experience) |

一部の EVAL ISO はエディション名に「Evaluation」サフィックスを追加します(例:`Windows Server 2016 Standard Evaluation (Desktop Experience)`)。 ブートバイナリ構造は単一の install.wim 内のすべてのインデックスで同じなので、 ほとんどの分析は 1 つのインデックスだけマウントすることで実施できます — 慣例的に最も機能完備のエディションである Index 4 が使われます。

### 4.4 SecureBootRecovery.efi:Server 2025 の新顔

`SecureBootRecovery.efi` は Server 2025 の install.wim で初めて登場し、 PCA2011 で署名されています。 Server 2016 / 2019 / 2022 には現れません。 セキュアブートリカバリ手順に関連した役割(おそらくファームウェアアップデートがアクティブな署名者を失効させた場合に信頼を再確立する)ですが、 ランタイム動作の正典の文書化は元の調査では見つかりませんでした。 Server 2025 専用ファイルとして扱い、 任意のブートバイナリコピー操作で通過させてください;Microsoft の明示的なガイダンスなしに置換または再署名を試みないでください。 本記事では、 `SecureBootRecovery.efi` が標準インストール時の通常のブートフローに関与するか否かについては結論を下しません。

---

## 5. Servicing Stack 依存性

スリップストリーミングパイプラインで最も影響の大きい失敗クラスは **Servicing Stack 不一致** です。 LCU 適用前にこれを検出して解決する方法を知ることは、 実用的には 5 分のビルドと午後のフォレンジックログ読みの違いです。

### 5.1 Servicing Stack Update とは何か

**Servicing Stack** は他のコンポーネントをインストールする責任を持つ Windows のコンポーネントです。 それ自体がインストール可能なコンポーネントです。 Microsoft は Servicing Stack Update(SSU)を定期的に出荷し、 サービサのバグを修正したり、 サービサが新しいパッケージ形式を理解できるようにします。 ある日付以降に生成された LCU は、 install.wim の現在のサービサより新しい SSU を要求するかもしれません。

要件が満たされない場合、 `Add-WindowsPackage`(または DISM 直接)は次を返します:

```
HRESULT 0x800f0823 = CBS_E_NEW_SERVICING_STACK_REQUIRED
```

関連するログ行(`addpkg.log` または `dism.log`)は次のように読めます:

```
Package "Package_for_RollupFix~31bf3856ad364e35~amd64~~14393.9140.1.19"
  requires Servicing Stack v10.0.14393.7692
  but current Servicing Stack is v10.0.14393.693.
```

要求と現在のバージョンは明示的なので、 解決は単純化されます:サービサを ≥ 14393.7692 へとバンプする SSU を特定し、 それを先に適用すること。

### 5.2 スタンドアロン LCU vs Combined LCU+SSU

Microsoft は、 長年の間、 2 つの配信形態を行き来してきました:

- **スタンドアロン LCU**:LCU MSU には LCU のみが含まれる;SSU は独自の KB 番号を持つ別個の MSU として並列で配信される。 パイプラインは両方を SSU 先に適用しなければならない。 Server 2016、 Server 2019、 Server 2022(ほとんどの場合)はこのパターンに従う。
- **Combined LCU+SSU**:単一の MSU に LCU と SSU の両方がバンドルパッケージとして含まれる。 `Add-WindowsPackage` が順序を自動的に処理する。 パイプラインは 1 つの MSU だけダウンロードすれば良い。 Server 2025 はこのパターンに従う(SSU はすべての LCU と 2 ファイル Catalog ダウンロードとしてバンドルされる — セクション 2.3 参照)。

Combined MSU を判別する信頼できる実装レベルの指標は、 `update.mum` と `.cab` ペイロードに加えて `update.ses` ファイルが存在することです。 スタンドアロン LCU には `update.ses` がありません。 MSU の中を覗くパイプライン(`expand.exe -F:* msu_file destination` 経由)はこれを検出できます:

```
Combined:    update.mum, update.ses, Windows10.0-KBXXXXXXX-x64.CAB
スタンドアロン: update.mum,             Windows10.0-KBXXXXXXX-x64.CAB
```

config ロード時のバンドルタイプ検出は WIM マウント時の SSU-required 失敗を回避します。 WIM マウント時の失敗は高価です(WIM マウントを undo し、 SSU を先に適用してリスタートする必要がある)。 運用上、 この区別は、 ビルドが WIM サービシング開始前に安価に失敗するか、 すでに進行中になってから高価に失敗するかを決めます。

### 5.3 SSU-LCU ペアリング問題: 依存関係は実際にはどう表現されているか

Combined-MSU 以外の世界では、運用者は任意の LCU に対してどの SSU がペアになるかを知る必要がある。Microsoft は LCU の KB ページに平文で公開している(「改善点」セクションがしばしば「この更新プログラムは次の依存関係を導入します: KB`<NNNNNNN>` サービス スタック更新プログラム」で始まる)。サードパーティのサイトもこのペアリングを繰り返し掲載している。

自動化の自然な発想は、`wsusscn2.cab` の中に「LCU から SSU への KB 番号による前提条件(prerequisite)エッジ」を探すことである。**2026-05-12 に実際の `wsusscn2.cab` をリバースエンジニアリングした結果、そのようなエッジは Master XML にも per-package 詳細 CAB にも存在しないことが判明した。** この訂正は正確に述べる価値がある。本セクションの初期ドラフトは依存関係を誤って記述していたためである:

- LCU の Master XML `<Prerequisites>` ブロックが保持するのは **適用可能性 / detectoid の `UpdateId` GUID**(`DeploymentAction="Evaluate"` ノード、および Product カテゴリ・Classification カテゴリの GUID)である。これらは *評価* の関係(「この更新はこのマシンに適用可能か?」)であって、**インストール順序の依存関係ではない**。SSU を名指ししていない。実証的に、in-scope な更新群の prerequisite エッジを in-scope 集合に対して解決すると、in-scope な SSU KB は 0 件になる。
- したがって SSU 依存について **計算すべき KB-prerequisite の「閉包(closure)」は存在しない**。`<Prerequisites>` をたどっても「この LCU はどの SSU KB を必要とするか?」には答えられない。データがそこに無いからである。

実際に `0x800f0823` を引き起こす依存関係は、代わりに **最小サービス スタック バージョン**として表現される。これは LCU の per-package CBS メタデータ(`packageNN.cab` 内の `c/<RevisionId>`)にある:

```
<CbsPackageApplicabilityMetadata>
  ...
  <installerAssembly name="Microsoft-Windows-ServicingStack"
                     version="10.0.14393.7692" .../>   <-- 最小 SS バージョン
```

インストール時、CBS はマシンの現在のサービス スタック バージョンをこの `installerAssembly` バージョンと比較し、現在値が必要値を下回る場合に `CBS_E_NEW_SERVICING_STACK_REQUIRED`(`0x800f0823`)を返す。依存関係は **数値バージョン比較**であって、KB の一致ではない。正しい事前検証は次のとおり: *LCU の per-package メタデータから必要 SS バージョンを取り出し、同じパッチセット内の SSU が提供するサービス スタック バージョンがその値以上であることを検証する。*

具体例(Server 2016、2026-05、実 cab で検証済み):

```
Windows Server 2016 の LCU、2026-05 (KB5087537)
  leaf RevisionId 45255701 (3 つのうち 1 つ。x86/x64/エディション別の変種)
  per-package メタデータ c/45255701:
    Package_for_RollupFix version="14393.9140.1.19"   <-- LCU のビルド
    installerAssembly Microsoft-Windows-ServicingStack
                      version="10.0.14393.7692"        <-- 必要な SS の下限

  対応する SSU KB5088064(別の更新)がサービス スタックを 14393.7692 以上に
  引き上げる。Master XML は "5088064" を KB 要素として記載しておらず、
  KB5087537 の prerequisite も KB5088064 を参照していない。
```

つまり `wsusscn2.cab` 由来データから config をプリロードするパイプラインは、config ロード時に「Server 2016 LCU は少なくとも `10.0.14393.7692` のサービス スタックを必要とし、運用者がリストした SSU はその値以上を提供しなければならない」と検出できる。人間可読の SSU KB 番号自体は依然としてヒューリスティックにしか得られない(SSU 更新のペイロード URL 内の `kb(\d+)` トークン、または Catalog の相互参照)が、*依存関係の判定*はその KB 番号を知ることに依存しない -- バージョン比較に依存する。正しい SSU を含めずに config を手編集した運用者は WIM 適用時に `0x800f0823` を受け取る。事前のバージョンチェックはその 20 分の失敗を 1 秒の失敗に変える。

### 5.4 Server バージョンごとの SSU モデル (2026-05-12 の cab で検証)

2026-05-12 のリバースエンジニアリングでは、各 OS について同一の月次 LCU を 3 か月連続(2026-03/04/05)で解決し、毎回 per-package CBS メタデータを読んだ。4 つの OS は構造的に異なる 4 系統に分かれ、その系統は **月をまたいで安定**している:

| OS | SSU 系統 | SS 要件の所在 | 観測値 (2026-05) |
|---|---|---|---|
| Server 2016 | SSU 完全分離 | LCU の `installerAssembly` が **実際の**最小 SS バージョンを持つ | 必要 SS = `10.0.14393.7692` (3 か月とも一定) |
| Server 2019 | SSU 分離 + 内包参照 | LCU の `installerAssembly` (実値) **および** 内包の `Package_for_ServicingStack_<nnnn>` | 必要 SS = `10.0.17763.2090`; 内包 SSU `17763.8754` |
| Server 2022 | Combined (SSU が LCU に統合) | `installerAssembly` はプレースホルダ `6.0.0.0`; 実際の SS 情報は内包の `Package_for_ServicingStack_<nnnn>` | 内包 SSU `20348.5120` (毎月更新) |
| Server 2025 | Checkpoint 累積更新 (`.msu`) | leaf に `CbsPackageApplicabilityMetadata` が **無い**; `.msu` ペイロードが複数 KB を同梱 | ペイロード = LCU KB5087539 + ベースライン KB5043080 + SafeOS DU KB5087588 |

実務上の帰結は 2 点:

1. **Server 2016 と 2019 が `0x800f0823` の現実的リスクがある OS** である。SSU が別パッケージで、運用者が先に適用しなければならないからだ。その `installerAssembly` バージョンが照合すべき権威ある下限値となる。値は実ビルド番号(例: `10.0.14393.7692`)で、所与の LCU ビルドに対して一定である。
2. **Server 2022 と 2025 は SSU を LCU 内に内包する。** Server 2022 の `installerAssembly` は `6.0.0.0`(名目上のプレースホルダで、実ビルド番号ではない)を示し、実際のサービス スタック ビルドは内包の `Package_for_ServicingStack_<nnnn>` サブパッケージ(例: `5120` -> ビルド `20348.5120.1.0`)としてのみ可視で、毎月進む。Server 2025 の checkpoint `.msu` は自己完結しているため、外部 SSU ペアリングのチェックはこの OS には意味をなさない。

以前の「Server 2022 はほぼスタンドアロン; `update.ses` を検査せよ」という助言(旧ドラフト)は本知見で更新される: 2026-03/04/05 の cab では Server 2022 LCU は毎月 Combined であり、内包の `Package_for_ServicingStack_<nnnn>` が毎回存在した。§5.2 の `update.ses` テストはディスク上の MSU を検査する際の *実行時* 指標としては依然有効だが、cab メタデータは MSU を開かずとも SS ビルドをパイプラインに伝える。常にそうだが、これは 3 か月の窓での観測挙動であって契約上の保証ではない。パイプラインは OS ごとに系統をハードコードするのではなく、毎月 per-package メタデータを読むべきである。

### 5.5 事前検証ゲートとしての依存性検証 (訂正モデル)

本作業の実地での反復から得られた有用な設計パターンは、依存性検証をビルド時の発見ではなく **事前検証ゲート**として扱うことである。パイプラインは各 OS について適用するパッチをリストした config に対して動作する。DISM マウントの前に、パイプラインは `wsusscn2.cab` 由来の依存性データベースに対してパッチセットを検証する。

本セクションの旧ドラフトはこのゲートを KB-prerequisite の **閉包(closure)**(「LCU の prerequisite を引き、すべての prerequisite KB が config にあるか検証する」)として記述していた。§5.3 で根底のモデルを訂正した: たどるべき SSU KB-prerequisite は存在しない。したがって事前検証ゲートは、いずれも KB 閉包ではない **3 つの独立したチェック**として再定義される:

1. **存在確認(Presence)** -- 運用者がリストした各 KB が Layer 2 の in-scope 更新に解決する(その OS の現行 cab に LCU が実際に存在する)。解決しない KB は、supersede 済み(§5.9 参照)か scope 外(§5.8 参照)のいずれかで、ゲートはどちらかを報告する。
2. **サービス スタック バージョン比較** -- SSU 分離型の OS(2016/2019)について、LCU の per-package メタデータ(`installerAssembly`)から必要 SS バージョンを読み、同じパッチセット内の SSU がその下限以上のサービス スタック バージョンを提供することを検証する。これが実際に `0x800f0823` を防ぐチェックである。
3. **Supersession / 同一性** -- 選択した LCU がその OS で最新の非 supersede ビルドであることを(`<SupersededBy>` チェーン経由で)確認し、運用者が陳腐化したビルドをスリップストリームしないようにする。

これにより失敗検出が「20 分以上の WIM マウントとコピー作業の後」から「config ロードの 1 秒後」へ移る。1 秒の失敗は同じ運用者のセッション内で診断・修正できる。20 分の失敗は運用者が席を外していることが多い。重要なのは、このゲートが **静的メタデータのみ**を消費し、WIM をマウントしないことである(SPEC B.19.13 の厳格ルール)。

### 5.6 3 層データベース設計

上の事前検証ゲートを `wsusscn2.cab` をソース・オブ・トゥルースとして実装すると、 Git 管理の質問が浮上します:パースされた依存性データはどこに住むのか? 動作する 3 層設計:

- **Layer 1 — `config/<os>.json`**:人間が書く、 今月適用する KB を宣言する
- **Layer 2 — `data/wsusscn2-database.json`**:パースされた Master XML 依存性グラフ、 Git コミット済(2-5 MB)、 定期的な `RefreshDependencyDatabase` アクションで再生成される
- **Layer 3 — `workspace/cache/wsusscn2/`**:生の展開された CAB、 Git コミットしない(refresh 時に展開、 容量節約のため後で削除)

この階層化の利点は再現性です:Layer 2 の Git 履歴は、 各依存性が上流で Microsoft によっていつ導入されたかを示し、 「先月 config を書いた時にこの前提条件はすでに存在していたか、 それともその後 Microsoft が新しい依存性を追加したか?」をオペレータが監査できます。 Layer 3 の生 CAB は Layer 2 が再生成されたら保管価値がないので、 Git の外にあるのは設計通りです。

### 5.7 scope filter の根拠となる Product GUID 一覧

§5.5 と §5.6 で SSU-LCU/CU の依存性検証パイプラインを設計しました。 このパイプラインの最初のフィルタリング段階(scope filter)は、 wsusscn2.cab の Master XML に登場する全 ~136,000 件の `<Update>` から **Server LTSC 系列だけを切り出す** ために、 WSUS の `Categories.Product` GUID と `Categories.UpdateClassification` GUID を判定キーとして使います。

このセクションでは scope filter で使う **確定された GUID 表** を示します。 GUID は WSUS の global identifier として時間と共に変わらないので、 タイトル文字列ヒューリスティック(§6.2 で議論する脆弱性)に依存せず堅牢な判定が可能です。 GUID ベースのフィルタリングは表示名の変更やローカライズの差異を切り抜けるため、 タイトル文字列ヒューリスティックよりも大幅に安定します — これは本ワークフロー全体の重要なアーキテクチャ上の洞察のひとつです。

**Update Classification GUIDs**(WSUS 公式、 12 種類のうち 5 種類が実 wsusscn2 で観測):

| Classification | GUID | 実 wsusscn2 観測件数 | 本タスクとの対応 |
|:---|:---|---:|:---|
| SecurityUpdates | `0FA1201D-4330-4FA8-8AE9-B877473B6441` | 19,361 | LCU 系の主分類 |
| UpdateRollups | `28BC880E-0592-4CBF-8F95-C79B17911D5F` | 1,421 | .NET CU 系の主分類 |
| ServicePacks | `68C5B0A3-D1A6-4553-AE49-01D3A7827828` | 341 | SSU を含む |
| CriticalUpdates | `E6CF1350-C01B-414D-A61F-263D14D133B4` | 11 | 一部の Critical patch |
| Updates | `CD5FFD1E-E932-4E3A-BF74-18BF0B1BBD83` | 1 | Dynamic Update 系を含む |

出典:Microsoft Learn 「WSUS Classification GUIDs」(`learn.microsoft.com/ja-jp/previous-versions/windows/desktop/ff357803`)。 観測件数は 2026-05-12 取得の wsusscn2.cab に対する集計値。

**Server LTSC Product GUIDs**(scope filter の対象、 4 種類):

| Server バージョン | WSUS Catalog 表示名 | Product GUID | 確定根拠 |
|:---|:---|:---|:---|
| Windows Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` | Microsoft 公式コードベース(`ansible/ansible` Issue 60785 の Categories ダンプ、 `dsccommunity/UpdateServicesDsc` Issue 65)+ 実 wsusscn2 の Category Update から逆引き一致 |
| Windows Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` | WSUSOffline forum + 実 wsusscn2 Category Update created 2018-10-13(GA タイミング一致)|
| Windows Server 2022 LTSC | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` | 実 wsusscn2 Category Update created 2021-08-09(LTSC GA 直前);観測した payload URL は ndp481 関連（.NET Framework 4.8.1）パッケージを参照。 同梱ランタイムを payload 名のみから推定はしない |
| Windows Server 2025 LTSC | Microsoft server operating system-24H2 | `b256987d-4693-4c87-955d-dbb9341205eb` | **2026-05 訂正**（旧値 `ca006cfb-...`）：b256987d カテゴリの最新 SecurityUpdate bundle（2026-05-11）は現行の Server 2025 LCU **KB5087539**（build 26100.32860）を持つが、Windows 11 24H2 の *クライアント* LCU KB5089549 は持たないため server 専用と確定。旧 `ca006cfb-...` は 2025-09-08 で停止し KB5087539 を持たない（下の注記参照）|

参考(Server LTSC ではないため scope filter には含めない関連 Product):

| 名称 | Product GUID | 備考 |
|:---|:---|:---|
| Microsoft Server Operating System-22H2 | `2c7888b6-f9e9-4ee9-87af-a77705193893` | Azure Stack HCI 22H2 系 SAC |
| Microsoft Server Operating System-23H2 | `607efb8d-feed-48a0-930e-14d0cf2da71f` | Azure Stack HCI 23H2 系 SAC、 payload URL に build 25398 を確認 |

**SSU / LCU / .NET CU / Dynamic Update と Classification の対応**(SPEC §B.19.7 の Update type 表現)。 なお、 Classification GUID そのものは Microsoft が定義した識別子ですが、 以下の更新 *カテゴリ* と Classification *使用法* の対応は観測された wsusscn2 メタデータパターンに基づくものであり、 契約ではなくヒューリスティックとして扱うべきです:

- **SSU**:Classification = ServicePacks(`68C5B0A3-...`)。 Windows 6.x 世代以前は `Updates` も含んだが、 Windows 10/Server 2016 以降の SSU は ServicePacks に分類される。
- **LCU**:Classification = SecurityUpdates(`0FA1201D-...`)。 月例セキュリティ更新の Cumulative Update が該当。
- **.NET CU**:Classification = UpdateRollups(`28BC880E-...`)が主、 一部 SecurityUpdates(セキュリティを含むもの)。 .NET Framework 3.5 / 4.7.x / 4.8 / 4.8.1 の cumulative。
- **Dynamic Update**:Classification = Updates(`CD5FFD1E-...`)または CriticalUpdates(`E6CF1350-...`)。 Setup DU、 SafeOS DU が該当。 LTSC OS では公開ケイデンスが散発的(§6.3 参照)。

**deny-list: EOS / ESU の Server OS Product GUID(明示的除外)。** 2026-05-12 の調査で、サポート終了(EOS)および ESU 専用の Server OS 製品カテゴリは、OS がサポートを離れても `wsusscn2.cab` から削除されないことが確認された。これらは ESU 月次ロールアップを含む実ペイロード付き更新とともに無期限に残り続ける。したがって「無い」と仮定するのではなく、**能動的に除外**しなければならない。次の 4 つの GUID を deny-list として記録する(WSUS Offline コミュニティの製品 GUID リストと相互参照し、実 cab 内の存在を確認済み):

| Server バージョン | Product GUID | サポート状態 |
|:---|:---|:---|
| Windows Server 2008 | `ba0ae9cc-5f01-40b4-ac3f-50192b5d6aaf` | EOS (ESU 終了) |
| Windows Server 2008 R2 | `fdfe8200-9d98-44ba-a12a-772282bf60ef` | EOS (ESU 終了) |
| Windows Server 2012 | `a105a108-7c9b-4518-bbbe-73f0fe30012b` | ESU (2026-10 まで) |
| Windows Server 2012 R2 | `d31bd4c3-d872-41c9-a2e7-231f372588cb` | ESU (2026-10 まで) |

**deny-overrides ではなく allow-overrides。** 一部の更新は deny-list の OS と allow-list の OS の *両方* に正当に適用される。複数 OS 対応の悪意のあるソフトウェアの削除ツール(MSRT、KB890830)が典型例で、2012 R2 の GUID と 2016/2019 の GUID の両方を持つ。実 cab にはこうした「重複(overlap)」更新が 33 件存在する。したがって scope ルールは、deny-list GUID も併せ持つ場合でも、allow-list GUID を *いずれか* 持つなら更新を admit しなければならない。deny-overrides ルールはこれら正当な in-scope 更新を誤って除外してしまう。deny-list の役割は、**deny-list GUID のみ**を持つ更新(allow-list に何も該当しない ESU 専用ロールアップ。例: KB5087471 / KB5063950 / KB5063906。これらは 2012 / 2012 R2 GUID を持つ)を除外することである。

scope filter の正典(改訂版):

> Update が scope に admit される条件:
> 1. bundle であり、かつ
> 2. `Categories.Product` が 4 つの allow-list Server LTSC Product GUID の少なくとも 1 つに一致する(allow-overrides: deny-list GUID が併存していてもこれが成立する)、かつ
> 3. `Categories.UpdateClassification` が上記 5 つの Classification GUID のいずれかに一致する、かつ
> 4. `CreationDate` が parser 実行日から RecencyMonths の窓内である。
>
> deny-list は多層防御である: deny-list GUID のみ(allow-list GUID 無し)を持つ更新は除外され、警告として表面化させてもよい。これにより運用者は ESU/EOS パッチが検出され意図的に除外されたことを確認できる。

これらの条件を満たす Update のみが Layer 2 JSON に出力される。`RecencyMonths` の窓は parser の `-RecencyMonths` パラメータである: 既定 24、36 設定可、`-1` で条件を完全に無効化する(§5.9 参照)。2026-05-12 取得の wsusscn2 では、Master XML の ~136,000 件が 138 件の in-scope bundle(155 個の distinct payload KB)に絞り込まれ、2-5 MB の目標に十分収まる。

### 5.8 EOS / ESU データの永続性と deny-list

長期運用パイプラインにとって EOS の中心的な問いは、*OS がサポートを離れたとき、そのデータは `wsusscn2.cab` から消えるか?* である。2026-05-12 の調査は、各 OS の Product GUID を持つすべての Master XML 更新を集計することで実証的に答える:

| OS | サポート状態 | cab 内 更新数 | payload 有 | distinct KB | 最新 payload CreationDate |
|:---|:---|---:|---:|---:|:---|
| Server 2008 | EOS (ESU 終了) | 6577 | 4080 | 1078 | 2026-05-08 |
| Server 2008 R2 | EOS (ESU 終了) | 3540 | 2227 | 1018 | 2026-05-08 |
| Server 2012 | ESU (2026-10 まで) | 1659 | 979 | 803 | 2026-05-11 |
| Server 2012 R2 | ESU (2026-10 まで) | 1498 | 830 | 806 | 2026-05-11 |
| Server 2016 | メインストリーム間もなく終了 | 284 | 132 | 119 | 2026-05-11 |
| Server 2019 | サポート中 | 213 | 118 | 102 | 2026-05-11 |
| Server 2022 | サポート中 | 184 | 98 | 95 | 2026-05-11 |
| Server 2025 | サポート中 | 63 | 31 | 47 | 2026-05-11 |

3 つの知見:

1. **EOS はデータを削除しない。** 完全 EOS の Server 2008 / 2008 R2 ですら 1000 を超える payload 付き KB を保持し、最新 CreationDate は cab スナップショットのわずか数週間前である。(これらは主に Defender 定義更新と、権利を持つ顧客に今も配信される ESU 期のセキュリティ ロールアップである。)EOS で消去されるものは無い。
2. **古い OS ほどデータが *多い*。** Server 2008 は 6577 件、Server 2025 は 63 件。累積更新以前のサービシング時代が、旧 GUID 配下に長年の個別月次パッチを大量に残した一方、累積更新型 OS(2016 以降)はエントリが遥かに少ない。これは、もし deny-list の OS を scope に入れた場合に RecencyMonths の窓がデータ量制御として効く理由である。
3. **Server 2016 の今後の ESU 移行は取得において非問題である。** 完全 EOS の 2008/2008 R2 ですら GUID を変えずに payload 付きで残り続けているため、Server 2016 の GUID(`569e8e8f-...`)はメインストリーム終了後・ESU 移行後も解決し続ける。OS は ESU 移行時に新しい GUID を取得しない。`569e8e8f-...` を allow-list に残せば「最新の Server 2016 ロールアップ」は取得可能なままである。

これが、EOS/ESU 除外をデータ消滅頼みではなく Product-GUID deny-list として扱う根拠である: データは決して消えないので、除外は明示的でなければならない。

### 5.9 recency 窓とフォールバック深度

`RecencyMonths` 条件(既定 24)は `CreationDate` の窓である: `CreationDate` が `Now - RecencyMonths` より古い bundle は reject され、`-1` で条件は無効化される。2026-05-12 の堅牢性テストは、過去 36 か月分の OS 別 LCU KB 番号(コミュニティの Patch Tuesday アーカイブから収集)を現行 cab の in-scope 集合に対して照合し、「検索ロジックが実際にどこまで遡れるか」を問うた:

| OS | in-scope な最古 LCU | 実効到達 | 形状 |
|:---|:---|:---|:---|
| Server 2022 | 2024-06 (KB5039227) | 約 12-13 か月 | 最深 |
| Server 2016 | 2024-11 (KB5046612) | 約 7 か月 | 中程度 |
| Server 2025 | 2025-04 (KB5055523) | 約 8 か月 (2024-11 GA 以降) | GA 以降ほぼ全部 |
| Server 2019 | 2025-08 (KB5063877) | 約 3-4 か月 | 最浅 |

重要な洞察は、**実効到達が 24 か月の窓よりはるかに短く**、OS により異なることである。窓は `CreationDate` の上限だが、supersession が実用的な深度を縮める: 新しい LCU が古い LCU を supersede すると、古い方は payload 付き in-scope bundle ではなくなる。古い月を引いたときの「ミス」は **supersession(より新しいビルドが存在する)であって、データ欠損ではない** -- パイプラインはそのように報告すべきである。

パイプラインにとって、これは正確で実装可能な保証をもたらす:

- サポート中の各 OS の **最新** LCU は常に取得可能(月次サイクルは完全に決定論的)。
- 特定の古い月が要求され scope に無い場合、その OS の最新 in-scope LCU にフォールバックし、ミスを supersession として扱う。
- フォールバックの上限は `RecencyMonths` 設定(現在 24; 36 も対応)であり、`CreationDate` 窓がどこまで古いビルドを admit するかを画定する。窓の外では、非 supersede の古いビルドでも設計上除外される -- これが、もし deny-list の EOS OS(数千の履歴 KB を持つ)が admit された場合でも scope を氾濫させないための仕組みでもある。

---

## 6. Microsoft Update Catalog の命名上のクセ

セクション 2.3 で Catalog 命名変更を紹介しました。 本セクションでは含意を深掘りします。

### 6.1 21H2 / 24H2 リネーム

Microsoft の Windows Server 製品命名規則は Server 2019 と Server 2022 の間で変わりました。 古い OS は Catalog 更新タイトル内でユーザー向けブランド名で参照されます:

```
Title: 2026-04 Cumulative Update for Windows Server 2016 for x64-based Systems (KB...)
Title: 2026-04 Cumulative Update for Windows Server 2019 for x64-based Systems (KB...)
```

新しい OS はコードネームバージョンで参照されます:

```
Title: 2026-04 Cumulative Update for Microsoft server operating system, version 21H2 for x64-based Systems (KB...)
Title: 2026-04 Cumulative Update for Microsoft server operating system, version 24H2 for x64-based Systems (KB...)
```

`21H2` は Server 2022 のコードネーム;`24H2` は Server 2025 のコードネームです。 (ユーザー向けブランド「Server 2025」はどの Catalog 更新タイトルにも現れません。)

タイトル文字列ヒューリスティックにとっての含意:OS トークンリストは OS バージョン別であるべきで、 単一の正規表現ではダメ。 「Windows Server」を部分文字列として扱うと、 Server 2022 と 2025 の結果を黙って除外します。 「Microsoft server operating system」を部分文字列として扱うと、 2016 と 2019 を除外します。

### 6.2 脆弱性表面としてのタイトル文字列ヒューリスティック

更新タイトルの文字列マッチングで Catalog 結果を消費するパイプラインは、 次のようなヒューリスティックのリストを維持することにコミットします:

- 「タイトルに 'Cumulative Update for' を含む」 — LCU タイトルにマッチ
- 「タイトルに 'Safe OS Dynamic Update for' を含む」 — SafeOS DU タイトルにマッチ
- 「タイトルに 'Setup Dynamic Update for' を含む」 — Setup DU タイトルにマッチ
- 「タイトルに 'Servicing Stack Update for' を含む」 — スタンドアロン SSU タイトルにマッチ
- 「タイトルに 'for Microsoft .NET Framework' を含む」 — .NET CU アンブレラタイトルにマッチ

これらそれぞれが、 いずれかの時点で破綻するか予想外の動作をすることが観測されています:

- 「.NET Framework」ヒューリスティックは Server 2016 の .NET 4.8 兄弟をキャッチしますが、 .NET 3.5 / 4.7.x 兄弟を見逃します — 兄弟は別のアンブレラタイトルを使用します(セクション 2.2)。
- 「Dynamic Update for」ヒューリスティックは Server 2019 と Server 2016 で 0 ヒットを返します — これらの OS バージョンは月次 DU を出荷していないからです。 「0 ヒット」を通常ケースの結果ではなく失敗として扱うパイプラインは、 これらの OS でブロックします。

元の調査の Phase 3 アーキテクチャ推奨から導かれた構造的修正は、 release-info / .NET リリースノート Markdown ソースを **発見**(今月どの KB が存在するか)に使用し、 Catalog を **URL 解決のみ**(KB 番号が与えられたらダウンロード URL を見つける)に使用することです。 これによりほとんどのタイトル文字列ヒューリスティックがパイプラインのクリティカルパスから削除されます。

### 6.3 OS バージョンごとの Dynamic Update ケイデンス

経験的な Dynamic Update ケイデンス:

| OS | DU.Setup | DU.SafeOs | 備考 |
|---|---|---|---|
| Server 2016 | 月次公開なし | 月次公開なし | DU は feature-update window のみ;LTSC OS にはこれは稀 |
| Server 2019 | 月次公開なし | 月次公開なし | 2016 と同様 |
| Server 2022 | オプション、 公開時月次 | オプション、 公開時月次 | Catalog は通常各 1 ヒット返す |
| Server 2025 | **打ち切りまたは散発的**(2025-12 から 2026-04 のウィンドウで連続多月の公開なし) | 月次 | Microsoft はケイデンス変更を正式にアナウンスしていない |

パイプラインは「Server 2025 で今月 DU.Setup なし」を soft シグナルとして扱い、 エラーとしてではなく扱う必要があります。 Refresher は「No Setup DU published」をログして進む。 これは Server 2016 と 2019 が常に行ってきたことに一致します。

### 6.4 WSUS Product Category GUIDs と Server LTSC 系列の対応

§6.1 で WSUS の Catalog タイトル命名規則が Server 2019 と Server 2022 の間で変わったこと(「Windows Server 2019」 → 「Microsoft server operating system-21H2」 / 「Microsoft Server Operating System-24H2」)を扱いました。 こうした **表示名のリネームは表面的な現象** であり、 内部の GUID 体系は変化しません。 ここでは WSUS の Product Category 階層と、 Server LTSC 系 4 種類の GUID の対応を確定し、 命名揺れの影響を受けない参照表として記録します。

#### Product Category の階層構造

WSUS の Categories は 4 段階の階層を持ち、 wsusscn2.cab の `<Update>` Prerequisites で表現されます(§2.4.1 で観察)。

```
Microsoft (Company)
└─ Windows (ProductFamily)
   ├─ Windows Server 2016                            (Product, LTSC)
   ├─ Windows Server 2019                            (Product, LTSC)
   ├─ Windows Server 2022 LTSC                       (Product, LTSC、
   │     表示名「Microsoft server operating system-21H2」)
   ├─ Windows Server 2025 LTSC                       (Product, LTSC、
   │     表示名「Microsoft Server Operating System-24H2」)
   ├─ Windows 10, version 1903 and later             (Product, Client)
   ├─ Windows Server, version 1903 and later         (Product, Server SAC)
   ├─ Microsoft Server Operating System-22H2         (Product, Azure SAC)
   ├─ Microsoft Server Operating System-23H2         (Product, Azure SAC、
   │     build 25398 系)
   └─ ... (Server 2008 / 2008 R2 / 2012 / 2012 R2 等の旧 LTSC 各種)
```

実 wsusscn2(2026-05-12)では Windows ProductFamily 直下に **154 件** の Product Category が登場します。 Server 系のほか SQL Server / Office / Exchange / Forefront 等の Microsoft 製品ファミリも別 ProductFamily として並存していますが、 本タスクの scope filter は Windows 直下の Server LTSC 4 種類のみを対象とします。

#### 表示名のリネームと GUID 不変性

§6.1 で示したように、 Microsoft は Server 2022 から「Microsoft server operating system-21H2」 / 「Microsoft Server Operating System-24H2」というコードネーム命名規則に切り替えました。 タイトル文字列ヒューリスティック(§6.2)はこの命名変更で破綻しますが、 **GUID は不変** です:

| Server バージョン | 表示名(歴史的) | 表示名(現在) | Product GUID |
|:---|:---|:---|:---|
| Server 2016 | Windows Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` |
| Server 2019 | Windows Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` |
| Server 2022 LTSC | (新規) | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` |
| Server 2025 LTSC | (新規) | Microsoft server operating system-24H2 | `b256987d-4693-4c87-955d-dbb9341205eb` |

この表は §5.7 の scope filter の根拠表と同期しています。

注意点として、 Server 2022 と Server 2025 の Catalog 表示名は **同じ "Microsoft" を含むが、 大文字小文字の慣習が一貫していない**(`Microsoft server operating system-21H2` の `o` は小文字、 `Microsoft Server Operating System-24H2` は title case)。 これは Microsoft 内部の命名揺れであり、 GUID で参照する場合は影響を受けません。

#### 名前 → GUID 解決の正典ソース

実環境で表示名から GUID を解決する手段は以下のとおりです。 確実性の高い順:

1. **実 WSUS 環境**:`Get-WsusServer | Get-WsusProduct -TitleIncludes "21H2"` で取得。 WSUS server が必要だが、 Microsoft 公式 API 経由なので最も信頼性が高い。
2. **Windows Update Agent API**:対象 OS 上で `Microsoft.Update.Session` COM オブジェクトの `Search` 結果から `update.Categories[].CategoryID` を列挙。 Server 2022 VM / Server 2025 VM などの参照環境が必要。
3. **実 wsusscn2.cab からの逆引き**:本ドキュメント §2.4.1 で説明した方法。 オフラインで実行可能だが、 名前自体は package.xml から取れないため Category Update created date と payload URL の build 番号(Server 2022 LTSC = 20348、 Server 2025 LTSC = 26100、 Server 23H2 = 25398、 Server 2019 = 17763、 Server 2016 = 14393)で同定する。
4. **OSS の cross-reference**:[kbupdate-library](https://github.com/potatoqualitee/kbupdate-library)、 [OSDBuilder](https://github.com/OSDeploy/OSD)、 [WSUSOffline](https://forums.wsusoffline.net/) などのコミュニティリポジトリ。 公式ではないが、 観察値の検証用 cross-reference として有用。
5. **Microsoft Learn の「WSUS Classification GUIDs」 ページ**(`learn.microsoft.com/ja-jp/previous-versions/windows/desktop/ff357803`):Classification 側は完全な公式表が存在する。 Product 側は同等の公式表が公開されていないため、 上記の手段の組合せが必要。

本タスク(`Update-WindowsServerIso.ps1`)の `$Script:WsusScnOsCategoryGuids` テーブルは、 上記 1〜5 の手段で cross-reference された確定値を採用します(§5.7 の表が出典)。

---

## 7. 運用上の落とし穴

本セクションでは、 主要なトピカルセクションでカバーされない元の調査で遭遇した運用上の落とし穴を分類します。 各々は実時間のコストを生んでおり、 同様のツーリングを構築する人にとって短い注意の価値があります。

### 7.1 PowerShell 5.1 ConsoleHost の日本語文字 mojibake

症状:WIM の `ImageName` フィールド(例:`Windows Server 2016 Standard Evaluation (デスクトップ エクスペリエンス)`)から読み取られた日本語文字列を出力する `Write-Host` または `Write-Output` 呼び出しで、 同一実行内の一部の行で各非 ASCII コードポイントが 2 回(`デデススククトトッッププ`...)レンダリングされるが他の行ではされない。

失敗の特性:

- 元のデータを破壊しない — 同じ実行が書く CSV には正しい文字列が含まれる
- 再実行間で決定的に再現しない
- 元のコーパスでのフォローアップ調査は原因を **DISM mount-cache 状態** に絞り込んだ:過去の中断された実行から残った古いマウント、 孤立ハードリンク、 部分的にクリーンアップされた `WimMountedImageInfo` エントリが、 同じ WIM の後続列挙で破壊されたエディション名を提供することを引き起こす可能性がある
- 最も単純なワークアラウンドは **OS ファミリごとに fresh WorkRoot** を使うこと — Server 2016 と Server 2025 のビルドで `D:\UpdateWsi` を再利用せず、 OS ごとに `D:\UpdateWsi_2016`、 `D:\UpdateWsi_2025` などにパーティション化する

根本原因は正式には確定していません。 互換性のある仮説:

- DISM は `%TEMP%`、 `%WINDIR%\Logs\DISM`、 または `WimMountedImageInfo` レジストリキーにマウントごとのメタデータをキャッシュする;これらのいずれかの破壊は同じ WIM の後のマウントに毒を盛り得る
- PowerShell 5.1 の `ConsoleHost` はレガシー Win32 console subsystem を使用し、 これは UTF-16 サロゲートペアと、 日本語と ASCII を混在させた行でのコードページ遷移を扱う際の既知の問題を持つ

診断手順:問題が再現したら、 `dism /Get-MountedImageInfo` と `Get-WindowsImage -Mounted` をサイドファイルにダンプする;古いマウントエントリはキャッシュポイズニング仮説の直接的な証拠を提供する。

### 7.2 ネストされた CAB での `expand.exe -F:` セルフ上書き

症状:`expand.exe -F:* wsusscn2.cab destination_dir` が `destination_dir` が CAB 内に存在するパスと重なる時、 `/Y` が指定されていても `ERROR_FILE_EXISTS` で途中で失敗する。

根本原因:`expand.exe` は CAB の論理ツリー内の複数の位置に現れるファイルを重複排除しない。 内部のファイル名が外部 CAB のファイルと共有されるネストされた CAB は、 expand が直前に書いたファイルを上書きさせる可能性がある。

ワークアラウンド:7-Zip(`7za x -y -bd -bso0`)を使うか、 新しいステージングディレクトリに展開してディスクコストを許容する。 `Shell.Application` COM ベースの展開もバグを回避できるが、 遅く独自の非決定性問題を持つ。

### 7.3 PowerShell 7.4 での `List[object]` + `@()` 展開

症状:`System.Collections.Generic.List[object]` を介して `[pscustomobject]` インスタンスのリストを構築し、 `@($list)` でリストを配列ラップすると `System.ArgumentException: Argument types do not match` を投げる。 `List[string]` で同じコードは動作する。

```powershell
$list = [System.Collections.Generic.List[object]]::new()
$list.Add([pscustomobject]@{Label = 'a'}) | Out-Null
$list.Add([pscustomobject]@{Label = 'b'}) | Out-Null

@($list)            # PS 7.4 で FAILS: Argument types do not match
[object[]]@($list)  # 同じ理由で FAILS
$list.ToArray()     # OK
foreach ($x in $list) { $arr += $x }   # OK
```

ワークアラウンド:関数出力境界で `$list.ToArray()` を使用する。 これは PowerShell 7.4.x で観測されたもので、 後のバージョンでの動作は再テストされていない。

より深い問題は、 PowerShell の `@()` サブエクスプレッション演算子でラップされた強い型付けされたジェネリックコレクションの取り扱いにある;この演算子は配列強制を実施するが、 `pscustomobject` 要素を含む `List[object]` では常に成功するわけではない。

### 7.4 終了エラーとしての signtool exit-code-1

セクション 3.5 ですでに言及されていました。 拡張版:`signtool verify /ds N` は要求された署名インデックスが存在しない場合、 exit code 1 を返し、 "No signature found" を stderr に書く。 `$ErrorActionPreference = 'Stop'` の下で、 PowerShell はこれを終了エラーとして扱い、 caller が 1 を期待していて処理する準備をしていた場合(追加の署名を探っており、 「もうない」は通常ケース)であっても、 signtool を呼ぶスクリプトを中断する。

ワークアラウンド:signtool を helper 関数で wrap し、 呼び出しの間 `$ErrorActionPreference = 'Continue'` に切り替え、 exit code と output を明示的にキャプチャし、 構造化結果オブジェクトを返す。

---

## 8. 検証戦略

検証に関する元の調査の経験は、 次のように要約できます:自動検証の各層は異なる回帰クラスをキャッチしますが、 「バイナリがファームウェアで起動するかどうか」のクラスをキャッチする自動検証はありません。

### 8.1 事前検証ゲート

最も安価な検証は、 I/O 重い作業が始まる前の config ロード時です。 この段階で問う価値のある質問:

- **パッチセット一貫性**:config 内の KB 番号は自己一貫したセットを形成するか?(セクション 5.5 — `wsusscn2.cab` 派生データを使った事前検証依存性グラフ検証。)
- **ファイルシステム存在**:config から参照されるすべての MSU が実際にディスク上に存在し、 期待される SHA-256 を持つか?(単純なチェックサムテーブルが半完了ダウンロードの半数をキャッチする。)
- **OS バージョン一致**:config の宣言された OS は install.wim の埋め込まれたバージョンと一致するか?(`Get-WindowsImage` は `ImageVersion` を返す;config は期待される `BuildNumberMin` を宣言し、 WIM がそれより古ければ中断できる。)
- **Servicing-stack-already-present**:config が LCU をスタンドアロンと宣言している場合、 SSU も config に含まれているか?(セクション 5.3。)

これらのチェックはミリ秒で完了し、 オペレータが同じセッション内ですぐに行動できるエラーを生成します。

### 8.2 マウント時と適用時のゲート

WIM がマウントされると、 `Add-WindowsPackage` は適用不可能なパッケージを詳細な HRESULT で拒否します。 最も一般的な 2 つ:

- `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED` — SSU 依存性が満たされなかった(セクション 5.1)
- `0x800f0922 CBS_E_INSTALLERS_FAILED_TO_LOAD` — 破損した SSU または互換性のないアーキテクチャ

どちらの失敗も慣習的な意味で「スクリプトの責任」ではありません;それらは事前検証でキャッチされるべき config エラーを反映しています。 修復は声を大にして失敗し、 WIM をクリーンな状態でマウント解除し、 オペレータにどの config 行が注意を要するか伝えることです。

### 8.3 ビルド後検証

出力 ISO が生成されたら、 最終検証レイヤーが次を確認できます:

- **ファイルシステム構造**:期待される `\boot\`、 `\efi\`、 `\sources\` ツリーが存在する
- **ブートバイナリの同一性**:期待されるパスのバイナリが期待されるファイルまたは Authenticode ハッシュを持つ(セクション 3.6)
- **Authenticode チェーン**:仕様で PCA2023 信頼チェーンを持つべきとされるブートバイナリが、 実際に PCA2023 中間証明書を含むチェーンに再構築される(セクション 3.7)

Microsoft リファレンス `Make2023BootableMedia.ps1` v1.4 はこれを一切しません。 これらのチェックを実行する検証関数は、 したがって Microsoft パターンからの逸脱ではなく、 上位互換の品質改善です。 検証関数の出力はセクション 3.7 の SCOPE clarifier を持つ必要があります — 自動検証はハードウェアブートテストの代わりにはなりません。

### 8.4 検証境界

自動ツールが越えられない線:**セキュアブートプラットフォームが生成された ISO を実際に起動するかどうか**。 これは、 ターゲットファームウェアが DB に PCA2023 をプロビジョニングされたかどうか(または、 失効後の世界では、 ターゲットファームウェアがまだ DB に PCA2011 を保持しているかどうか)に依存します。 これはマシンごと、 ファームウェアバージョンごとの状態です。 唯一の決定的なテストは ISO を代表的なターゲットで起動することです — デプロイメント世代のファームウェアアップデートを受信した物理ハードウェア、 または、 最近の Microsoft 公開セキュアブートテンプレート(これ自体が PCA2023 を念頭に置いて作成された)から作成された Hyper-V Gen2 VM。 Hyper-V Gen2 検証はデプロイ前のスモークテストとして有用ですが、 ファームウェアの trust-anchor プロビジョニングは物理 OEM ハードウェアと大きく異なり得ます:Hyper-V の仮想ファームウェアの DB/DBX プロビジョニング状態は特定の物理プラットフォームと異なり得るため、 Hyper-V でのパスが物理プラットフォームでのパスを保証するわけではありません。

ブートテストを欠くパイプラインは「壊れて」いません;SCOPE clarifier が人間のオペレータに見えるようにする既知で限定された制限とともに動作しています。

---

## 9. 残された疑問

本記事は 2026 年中期時点の知識状態を統合しています。 元のコーパスにいくつかの疑問が残っており、 フォローアップ調査の適切な出発点になります:

1. **PCA2011 DBX 展開タイミング**:Microsoft は将来のタイムラインで PCA2011 を DBX へ移すと発表していますが、 正確な日付は公開されていません。 長期サポートされる ISO(デプロイメント 5 年以上)を構築するパイプラインはここに回答が必要です;保守的な仮定は「2026-2027 のどこか」です。

2. **`bootmgr_EX.efi` の永続性**:Server 2025 の `bootmgr_EX.efi` は PCA2011 署名を含めて `bootmgr.efi` とバイト単位で同一です。 これが遷移期間アーティファクト(将来は `bootmgr_EX.efi` が PCA2023 で再署名される)か永続的な設計選択(BIOS ブートは PCA2023 を必要としないので、 `_EX` サフィックスがあってもファイルは意図的に PCA2011)かは不明です。 Microsoft の `Make2023BootableMedia.ps1` v1.4 のコメントは後者を示唆していますが、 ファイルの未来の状態は予測できません。

3. **`.NET Framework` ページインデックスのパース**:`.NET Framework release-notes` インデックスページは Markdown として配信されていますが、 エントリリストは単純な正規表現ベースのパーサーが見逃すシンタックスバリエーションを使います。 Markdown ライブラリまたはより堅牢なパーサーがこのギャップを閉じ、 パイプラインに「最新の .NET CU は何月か?」 のセルフブートストラップを与えます。

4. **Hotpatch ISO 統合**:Hotpatch カレンダー(セクション 2.1)はクエリ可能ですが、 ホットパッチパッケージがマウントされたオフライン WIM に `Add-WindowsPackage` できることを示すデータはありません。 Hotpatch モデルは、 実行中の OS が登録されている必要があるランタイムインメモリパッチングメカニズムです。 Hotpatch ベースライン月 LCU からビルドするパイプライン(新規デプロイメントが直接的なベースラインアップデートリブートなしにホットパッチへ登録できるように)は考えられますが、 Microsoft がこのパターンを正式にサポートするかは不明です。

5. **Server 2025 DU.Setup ケイデンス**:セクション 6.3 で述べたように、 Microsoft は Server 2025 の Setup Dynamic Update が打ち切られたのか、 四半期ケイデンスに移ったのか、 単に無関係の理由で長期間欠落しているのか、 を正式にアナウンスしていません。

6. **DISM mount-cache mojibake 根本原因**:セクション 7.1 の仮説(mount-cache 状態破壊)は症状と整合的ですが、 決定的には isolated されていません。 制御されたマウント / アンマウントシーケンスと明示的なキャッシュ検査を伴う、 クリーンな Windows インストールでのクリーンルーム再現は仮説を確証するか否認するかを与えます。

### 既知の未知(Known Unknowns)

上記の Open Questions（具体的な調査ギャップ）とは異なり、 以下は現在のデータをさらに分析するのではなく、 Microsoft の将来の決定に解決が依存する前向きの不確実性です:

- Microsoft が最終的に `bootmgr.efi`（現状 PCA2011 署名のまま残る BIOS/`_EX` ブートファイル）を PCA2023 署名するか否か。
- Server 2025 の DU.Setup ケイデンス変更が意図的な方針転換なのか、 偶発的な欠落なのか。
- 将来の `wsusscn2.cab` リビジョンが KB 識別子を異なる形で露出するか否か（例:KB 要素の再導入、 または KB 推定が現在依存している payload-URL 命名パターンの変更）。
- Server vNext が `_EX` デュアルツリーモデルを継続するか、 別の PCA2023 配信メカニズムに置き換えるか。
- PCA2011 の DBX 失効タイミングが、 単一の Microsoft 公表日に従うのではなく、 OEM ファームウェアエコシステムごとに異なるか否か。
- Microsoft が将来、 Server LTSC の Product Category GUID マッピングを公式に公開するか否か（現状は wsusscn2 とコミュニティソースからの逆引きに委ねられている。§5.7 参照）。
- GitHub バックの release-info Markdown ソース（§2.1）が形式の安定性を保つか、 あるいはテーブルレイアウトのパーサーを破壊する形で廃止・再構成されるか否か。

これらは本記事が回答できるから挙げているのではなく、 長寿命のパイプラインがこれらのいずれかの変化に備えて余裕を持つべきだからです。

---

## 10. 確信度レベル(Confidence Levels)

本記事は Microsoft が文書化した事実と、 推定あるいは経験的に観測した挙動を混在させているため、 どの主張がどの種類の根拠に基づくのかを明示しておく価値があります。 長寿命のツールを構築する読者は、 確信度の低い分類を変更され得るものとして扱い、 自身の環境に対して再検証すべきです。

### 公式 / Microsoft 文書化済み

Microsoft 自身の公開ドキュメントまたは出荷ツールに基づくもので、 最も安定しています:

- WSUS Classification GUID(5 つの識別子そのもの)。 Microsoft Learn「WSUS Classification GUIDs」ページ準拠。
- Windows Server release-info ページ(ビルド番号、 KB 番号、 提供日)。 Microsoft Learn 公開。
- 権威ある適用可能性評価器としての Windows Update Agent(WUA)オフラインスキャンの利用。
- PCA2023 ブートメディア移行ツールとしての `Make2023BootableMedia.ps1` の目的。

### 高確信度の推定

正式にはそう文書化されていませんが、 裏付ける根拠(実 wsusscn2 データからの逆引き、 複数の独立ソースとの相互参照)が強固なものです:

- Server LTSC Product GUID マッピング(Server 2016 / 2019 / 2022 / 2025)。 実 wsusscn2 メタデータからの逆引きで検証し、 コミュニティ OSS と観測された LCU KB 番号と相互参照。
- `package.xml` の依存性グラフ関係(`Prerequisites`、 `SupersededBy`、 `BundledBy`、 leaf から bundle への payload ロールアップ)。
- 現行 Catalog スナップショットで観測された Server 2025 LCU バンドル挙動(combined LCU + SSU 依存性解決メタデータ)。

### 観測されたが契約ではないもの

特定時点のメタデータスナップショットまたはメディアで見られた挙動を記述したものです。 有用ですが Microsoft はコミットしておらず、 予告なく変更され得ます:

- Catalog タイトルヒューリスティック(21H2 / 24H2 の表示名規則と大文字小文字)。
- OS バージョンごとの Dynamic Update ケイデンス。
- EFI_EX / bootmgr_EX 実装詳細(どの `_EX` バイナリが同梱されるか、 その署名チェーン)。
- payload URL 命名規則(KB 番号を抽出する元の `windows10.0-kb<数字>-<arch>` ファイル名パターン)。
- `package.xml` スキーマの前提(要素名、 属性配置、 KB 要素の不在)。

疑わしい場合、 適用可能性については WUA オフラインスキャンが権威ある判定者であり、 KB とビルドの対応については Microsoft Update Catalog と release-info ページが権威あるソースです。

---

## 付録 A:Microsoft Servicing 用語集

| 用語 | 定義 |
|---|---|
| **Applicability evaluation（適用可能性評価）** | 特定のイメージに特定の更新がインストール可能か否かの判断。 Windows Update Agent のサービシングロジック（WUA 参照）が権威をもって行う。 メタデータレベルの依存性発見とは別概念。 |
| **Authenticode hash** | 署名領域（`IMAGE_DIRECTORY_ENTRY_SECURITY`）と PE ヘッダのチェックサムを除外して定義される PE イメージハッシュ。 コードが同一で署名が異なる 2 つのバイナリは、 Authenticode hash は一致するがファイルハッシュは異なる。 PE image hash 参照。 |
| **Bundle** | wsusscn2 において `IsBundle="true"` が付いた更新。 Product と Classification のカテゴリを持つが自身のペイロードは持たず、 `<BundledBy>` で自分を指す leaf 更新からペイロードが集約される。 |
| **CAB** | Cabinet ファイル(`.cab`)。 Microsoft の圧縮アーカイブ形式。 MSU 内のペイロードアーカイブと、 `wsusscn2.cab` および内部パッケージの形式。 |
| **CBS** | Component-Based Servicing。 Vista 以降の Windows servicing モデル。 `CBS_E_*` プレフィックスのエラーコードはここに由来。 |
| **Classification GUID** | 更新の分類（SecurityUpdates、 UpdateRollups、 ServicePacks 等）を表す WSUS 定義の識別子。 GUID 自体は Microsoft 定義だが、 更新 *カテゴリ* と分類 *使用法* の対応はヒューリスティック（§5.7 参照）。 |
| **DBX** | セキュアブートの失効データベース。 ファームウェアが DB に関わらずロードを拒否する証明書とイメージハッシュのリスト。 |
| **DB** | セキュアブートの許可署名データベース。 ファームウェアが受け入れる証明書のリスト。 PCA2011 と PCA2023 の両方とも、 関連プロビジョニングを受信したプラットフォーム上では DB エントリ。 |
| **DISM** | Deployment Image Servicing and Management。 オフライン(マウントされた)Windows イメージを操作するための Windows ツール / API。 |
| **DU** | Dynamic Update。 Microsoft がインストール中の Windows Setup 環境に注入する更新。 **DU.Setup** は Setup 自体を更新する;**DU.SafeOs** は WinPE / WinRE リカバリ環境を更新する。 |
| **SafeOS DU** | DU.SafeOs バリアント:主要な Setup バイナリではなく WinPE / WinRE（SafeOS）リカバリ環境を対象とする Dynamic Update。 |
| **EFI / EFI_EX** | install.wim 内部とインストールメディア上のディレクトリ名。 `EFI` は伝統的な PCA2011 署名ブートバイナリを保持する;`EFI_EX` は同じバイナリを PCA2023 で再署名したものを保持する。 |
| **HRESULT** | Windows API 全体で使用される 32 ビット戻り値コード。 `0x800f0823` は SSU 必要エラー。 |
| **LCU** | Latest Cumulative Update。 OS 自体の月次 Patch Tuesday ロールアップ。 |
| **MSU** | Microsoft Update Standalone Installer ファイル(`.msu`)。 Microsoft がダウンロード可能な更新に使うパッケージ形式。 MSU は構造的には `.cab` ペイロードとメタデータファイルを含む CAB。 |
| **Offline Sync Package** | オフラインスキャン用更新メタデータに対する Microsoft 自身のフォーマット名。 `package.xml` のルート要素 `<OfflineSyncPackage>` と XML 名前空間 `http://schemas.microsoft.com/msus/2004/02/OfflineSync` で宣言される。 `wsusscn2.cab` として配布され、 Windows Update Agent がオフライン適用可能性スキャンで消費する。 不透明な配布ファイル名ではなく、 この表面をパースするコードを命名する際の権威ある用語(§2.4 参照)。 |
| **PCA2011** | `Microsoft Windows Production PCA 2011`。 Windows 8 時代以降 Windows ブートバイナリに署名してきた証明書認証局。 段階的廃止中。 |
| **PCA2023** | `Windows UEFI CA 2023`。 置換 CA。 |
| **PE image hash** | オンディスクの PE ファイル全体（`Get-FileHash` が測定するもの）のハッシュ。 署名領域を含む点で、 それを除外する Authenticode hash と対をなす。 |
| **Product Category** | 製品（例:Server LTSC エディション）を表す WSUS Category。 Product GUID で識別される。 wsusscn2 では `<Category>` 参照としても、 スタンドアロンの Category Update としても現れる（§2.4.1 参照）。 |
| **SSU** | Servicing Stack Update。 サービサ自体を更新する。 サービサが LCU をインストールする。 スタンドアロン(独立 MSU)または Combined(LCU の MSU にバンドル)。 |
| **Supersedence（supersede 関係）** | より新しい更新が古い更新を置き換える関係。 wsusscn2 の Master XML は逆方向（`<SupersededBy>`）を露出する;順方向はパッケージ別 CAB にのみ存在する。 |
| **スリップストリーミング** | インストール済 OS が初回起動時にすでにパッチ済となるよう、 インストールメディアに更新を統合する慣行。 |
| **WIM** | Windows Imaging Format。 `install.wim` と `boot.wim` のファイル形式。 概念的には重複排除されたマルチイメージアーカイブ。 |
| **WSUS** | Windows Server Update Services。 Microsoft の企業向け更新管理サーバ。 `wsusscn2.cab` は WSUS クライアントが Microsoft のオンラインサービスに接触せず更新適用性を判断するために使うオフラインスキャンカタログ。 |
| **WUA** | Windows Update Agent。 更新がインストール可能か否かを判断する適用可能性ロジックが権威ある評価器であるオンマシンのサービシングコンポーネント;オフライン WUA スキャンはマウント済みイメージに対して検証する。 |

---

## 付録 B:ソース URL リファレンス

| リソース | URL |
|---|---|
| Windows Server release-info ページ(Markdown) | `https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown` |
| Windows Server release-info ソース on GitHub | `https://github.com/MicrosoftDocs/windows-release-pr/blob/live/windows/release-information/windows-server-release-info.md` |
| .NET Framework release-notes インデックス(Markdown) | `https://learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown` |
| Microsoft Update Catalog | `https://catalog.update.microsoft.com/` |
| Microsoft Update Catalog: ScopedView(更新ごとの詳細) | `https://catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=<GUID>` |
| `wsusscn2.cab` ダウンロード(現在の静的 URL) | `https://catalog.s.download.windowsupdate.com/d/msdownload/update/v3/static/trusted/.../wsusscn2.cab` |
| Microsoft Support:`Make2023BootableMedia.ps1` リファレンス | KB5053484(記事番号で Microsoft Support サイトを検索) |

URL は Microsoft の裁量に従い、 通知なく変更される場合があります。 release-info ページの GitHub ベース性質はこのセットの中で最も強い安定性保証を提供します。

---

## 付録 C:Provenance と元の素材

本記事は、 実際の Windows Server ISO 更新パイプラインのマルチリビジョン開発中に蓄積された技術的発見を統合しています。 基となる調査ログ — リビジョン固有のデバッグ記録と、 ここに抽出された一般的な技術的発見が混在していた — はそのパイプラインと並んで「生きたドキュメント」として元々維持されていました。

元のリポジトリは [`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) の `scripts/powershell/update-windows-server-iso/` 配下にあります。 この素材を生んだ調査サイクルは、 リポジトリの CHANGELOG にタグ付けされたサイクルリビジョンにまたがります;以下の発見は、 現在退役した `docs/history/` サブディレクトリから抽出されました。

本記事は何であって何でないか:

- **である**:Windows Server ISO スリップストリーミングが触れる技術的表面エリア(パッチメタデータソース、 PCA2023 移行のセマンティクス、 install.wim バージョン横断的非対称性、 SSU 依存性モデル、 Catalog 命名上のクセ、 運用上の落とし穴を含む)への、 ポータブルでプロジェクト独立なリファレンス。
- **ではない**:特定の実装のドキュメント。 元のパイプラインからのフェーズ番号、 関数名、 設定ファイルスキーマ、 リビジョン識別子は意図的に削除されています。 本記事は同様のツーリングをどの言語またはフレームワークで構築する人にとっても有用であることを意図しており、 元のパイプラインの消費者のみではありません。

元のリポジトリの PowerShell パイプラインの上に構築する実装者にとって、 ツール固有動作のソース・オブ・トゥルースはパイプライン自身の `SPEC.md` と `README.md` です;本記事は横断的関心事マップであり、 ユーザーマニュアルではありません。

本記事は Anthropic Claude(Opus 4.7)によりリポジトリメンテナの指示の下、 元の `docs/history/` 内容を読み統合することにより準備されました。 リポジトリの調査ログから得られた知見を統合し、 必要に応じて Microsoft の公開ドキュメントを相互参照しています。

---

## 付録 D:運用上の保証 vs 観測

この表は、 本記事の主要な主張の認識論的ステータスを集約したもので、 将来のメンテナがどの事実に依拠して安全か、 どれを再検証すべきかを一目で把握できるようにします。 「公式アナウンス済み」は Microsoft が公表していることを、 「運用上安定」はこれまでの全観測で成立しているが正式な保証はないことを、 「観測」は特定のスナップショット/メディアで見られたもので予告なく変わり得ることを意味します。

| トピック | ステータス |
|:---|:---|
| PCA2023 ロールアウト（移行そのもの） | 公式アナウンス済み |
| PCA2011 → DBX 失効の *タイミング* | 原則アナウンス済み;正確な日付は保証なし |
| WSUS Classification GUID（識別子） | 公式文書化済み |
| Server LTSC Product GUID の永続性 | 運用上安定（公式公開ではない） |
| Product カテゴリ → 名前の解決 | 逆引きが必要（公式なオフライン表なし） |
| wsusscn2 スキーマの安定性 | 保証なし |
| パース対象としての `package.xml` | サポート外の実装詳細 |
| FileLocation URL からの KB 推定 | ヒューリスティック（URL 構造は契約ではない） |
| `_EX` デュアルツリーのディレクトリ構造 | 観測（Server 2025 メディア） |
| Server 2025 の 2 ファイル LCU+SSU Catalog 挙動 | 観測（現行 Catalog） |
| `bootmgr_EX.efi` の PCA2011 署名 | 観測 / 実装と整合 |
| LTSC での Dynamic Update ケイデンス | 観測のみ |
| 最終的な適用可能性 / インストール可能性 | WUA サービシングロジックのみが権威 |

「公式アナウンス済み」または「公式文書化済み」以外のステータスの行は、 助言的なものとして扱ってください:発見と高速化には有用ですが、 Microsoft 自身のサービシング検証の代替にはなりません。
