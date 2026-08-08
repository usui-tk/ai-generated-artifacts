---
title: "Windows Server パッチ適用済みISOビルド — メタデータソース・リファレンスアーキテクチャ"
subtitle: "自律ISOビルドパイプラインの本番メタデータソースを選定するためのアーキテクチャ意思決定記録（ADR）"
doc-type: reference-architecture (ADR-structured)
lang: ja
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-08-08
status: living-document
revision: "r2.5 (r12シリーズ実測拡張: Catalogローカライズ/宣言的発見・Setup-DU網羅・親子配送・PCA2023実測サブセット・WIMメタデータ機構; 2026-08)"
scope: "Windows Server 2016 / 2019 / 2022 / 2025 LTSC, x64, オフライン slipstream"
snapshot: "2026-06 Patch Tuesday サイクル"
source-en: "windows-server-iso-update-mechanics.en.md（本書は英語版から派生した翻訳）"
---

# Windows Server パッチ適用済みISOビルド：どのメタデータソースを、なぜ選ぶか

> 🇯🇵 **日本語版（英語版から派生した翻訳）。**
> 正本は英語版 `windows-server-iso-update-mechanics.en.md` です。本書は英語版に追従して保守します。**編集は必ず英語版を先に行い**、英語版と日本語版を並行して編集しないでください。コード（Appendix A〜E）は言語非依存のため英語のまま掲載しています。

> **文書種別。** 本書は **リファレンスアーキテクチャ**であり、**アーキテクチャ意思決定記録（ADR: Architecture Decision Record）**の構造を採ります。すなわち *Context（背景）*・*Alternatives Considered（検討した代替案）*・*Decision（決定）*・*Consequences（結果）* を述べ（§3.1）、それぞれをデータモデルの解説と、再現可能な実装（埋め込みスクリプト）で裏付けます。当初は調査メモでしたが、構造がその枠を超えたためこの位置づけとしています。

> **読み方の手引き — Stable と Snapshot。** 本書では2種類の内容を意図的に混在させています。読者は常にどちらかを意識してください。
> - **`[STABLE]`** — 不変のアーキテクチャ、データモデル、評価基準、GUID。数か月〜数年単位で有効。
> - **`[SNAPSHOT]`** — **2026-06** の Patch Tuesday 時点の具体的な KB / updateID / digest の値。**毎月入れ替わります**。ツールは実行のたびに再発見します。
>
> | セクション | 区分 |
> |---|---|
> | §1〜§3（役割・ADR・評価マトリクス）、§13.2（GUIDレジスタ）、§14（アーキテクチャ） | **`[STABLE]`** |
> | §4〜§6 のデータモデル、§7 世代マトリクス、§8 Secure Boot（同時に `[DRAFT]`）、§9〜§11 ツール | **`[STABLE]`** |
> | §12（検証済みスナップショット）、および本文中のあらゆる具体的な KB/updateID/digest | **`[SNAPSHOT]`** |

> **規範表現（RFC-2119 形式）。** 本書が運用上のルールを述べる箇所では、要求事項と説明を区別できるよう（かつ機械的に抽出できるよう）強度を明示します。
> - **MUST** / **MUST NOT** — 厳格な要求。違反するとビルドが不正になる、または失敗する。
> - **SHOULD** — 強い推奨。逸脱する場合は具体的な理由が必要。
> - **MAY** — 正しさに影響しない選択肢。
>
> マークのない散文は **説明または観察**であり、要求事項ではありません。

---

## 概要（Abstract）

**Problem（課題）。** Microsoft 評価版イメージと当月の累積更新から、フルパッチ適用済みの Windows Server 2016 / 2019 / 2022 / 2025 インストール ISO（x64, LTSC）を、オフラインで、再現可能に、かつ **自律ビルドパイプライン（Autonomous Build Pipeline）が端から端まで実行できる形**でビルドすること。難所は DISM コマンド以前にあります。すなわち *パッチの識別子と依存関係を、どの Microsoft の面（surface）から取得するのか* です。データは、形・網羅性・到達可能性の点で互いに食い違う複数の面に散在しています。

**Result（結論）。** **Microsoft Update Catalog** が **本番ソース（Production source）** ＝ ビルドが実際に消費する唯一の面です。他の2つは補助的役割に徹します。**MS-WSUSSS**（SOAP）は **権威ソース（Authority source）**（Catalog が正しいことを *証明する* ためのオラクル）、**`wsusscn2.cab`** は **検証ソース（Verification source）**（オフラインの依存関係/適用性データベース）です。この3つの役割は厳密に区別します。

**Why the Catalog（なぜ Catalog か）。** Catalog は、無人エージェントから **到達可能（reachable）**（素の HTTP、認証不要）であり、**網羅的（complete）**（ISO が必要とするすべてのライン、*Dynamic Update を含む*）であり、**検証可能（verifiable）**（返すすべての成果物が、共有の **Digest** プライマリキー上で権威オラクルとバイト単位で一致する）唯一の面です。権威ソースは到達不可、検証ソースは網羅性に欠けます。したがって Catalog は唯一実現可能な **単一本番ソース（Single Production Source）**であり、その出力は *信用* ではなく *証明* されています。

詳しい論拠 — 三役モデル、7軸の評価マトリクス、ADR 形式の決定 — は Part I（§2〜§3）にあります。Part II〜V がそれを、面ごとのデータモデル、解決→ISO のマッピング、埋め込み実装一式、収集データで裏付けます。**スコープ:** Windows Server LTSC メディアのオフライン servicing/再ビルドのみ、x64 のみ。Windows クライアント、Windows Update for Business、稼働中OSの in-place servicing は対象外（完全な非ゴールは §1.1）。

### Architecture at a glance（全体俯瞰）

**Figure 1 — Architecture at a glance（全体俯瞰）。** 設計の全体を1画面で：三役・単一の本番データ依存・証明済み成果物・自律ビルド。

```
  ┌──────────────────────────────────────────────────────────────────────┐
  │                       RESEARCH / VERIFICATION                          │
  │                                                                        │
  │   AUTHORITY              VERIFICATION                                   │
  │   MS-WSUSSS (SOAP)  ───► wsusscn2.cab                                   │
  │   ground truth          dependency / applicability                     │
  │        │                      │                                        │
  │        └──── Digest (primary key) proves ────┐                         │
  └──────────────────────────────────────────────┼─────────────────────────┘
                                                 ▼
  ┌──────────────────────────────────────────────────────────────────────┐
  │                    PRODUCTION  (Single Production Source)               │
  │                                                                        │
  │   Learn release-info ─► MICROSOFT UPDATE CATALOG ─► URL + SHA-1 Digest  │
  │   (LCU KB seed)         reachable · complete · proved                   │
  │                                  │                                      │
  │                                  ▼                                      │
  │   Autonomous Build Pipeline:  download → verify → DISM apply → ISO      │
  └──────────────────────────────────────────────────────────────────────┘
                                  ▼
                Offline, fully-patched, bootable Windows Server media
```

（図は安定した相互参照のため番号を付しています。本図が Figure 1。三役モデルは **Figure 2**（§2.1）、Catalog のデータモデルは **Figure 3**（§6.2.1）、研究/本番アーキテクチャは **Figure 4〜5**（§14）、一行サマリは **Figure 6**（§14.1）です。）

### 方法論と来歴（provenance）の規律

以下の主要な主張はいずれも、経験的に導出したうえで、3つの面のうち少なくとも2つで相互検証しています。それを生んだ規律であり、読者が本書に対して適用すべき基準でもあります。

- **オラクル基準の検証。** [A] SOAP が答え合わせの基準（answer-key）です。[B] や [C] に関する主張は、スキーマ非依存のキー — 可能な限り **ファイル Digest（SHA-1, base64）** — でオラクルと一致して初めて、仮説から事実へ「昇格」します。
- **不在は証明するもの、決して仮定しない。** 「データはここに無い」は高いハードルの結論で、別ストリーム・別検索パターン・別抽出方法を尽くして初めて到達できます。元調査での初期の「不在」判定のいくつかは、単に *検索が誤っていた* だけでした（§5.4 / §6.4 参照）。そのハードルを越えてなお不在が確定する場合は、*理由とともに* 記述します（例：2022 SafeOS DU、§5.5）。
- **クライアント先行の障害帰属（[A] 向け）。** 文書化され、呼び出し可能で、本番稼働しているプロトコルのエンドポイントがエラーや疎な結果を返した場合、既定の説明は **こちらのリクエストの欠陥**であってサーバー側の制限ではありません。実在の WSUS サーバーが同じエンドポイントから毎日カタログ全体を同期している事実が、その根拠です。
- **来歴タグ。** `[VERIFIED]` = 実際に収集した SOAP データに基づく / `[CAB-VERIFIED <date>]` = 実際にダウンロードした `wsusscn2.cab` に基づく / `[CATALOG-VERIFIED <date>]` = 実際の Catalog ラウンドトリップに基づく / `[DRAFT]` = 構造的に推論したが **まだ厳密な検証を経ていない**（§8 の Secure Boot 関連がこれ）。タグの無い記述は、確定した事実ではなく推論・構造です。

---

# PART I — 結論と評価軸

## 1. 背景・目的・想定読者

Microsoft は Windows Server をインストール可能な2形態で提供します。**評価版 ISO**（Microsoft Evaluation Center、180日タイマー、ライセンス不要で自由にダウンロード可能）と、**リテール/ボリュームライセンス ISO** です。エージェント駆動の自動化には評価版 ISO が最も実用的な入力ですが、メディアの再配布・保管は Microsoft のライセンス条項に従う必要があります。

そのようなメディアから「フルパッチ適用済み」ISO を作る実務者は、まず次の問いから始めます。*デプロイして起動したとき、当月の Patch Tuesday レベルに達し、かつ PCA2011 をもはや信頼しない Secure Boot 環境に受け入れられるためには、`install.wim` に適用すべき `.msu` / `.cab` パッケージの最小セットは何か？* 素朴な答え「今月の LCU を当てる」は不完全です。完全な答えは少なくとも次に触れます。

- 各ライン（LCU / SSU / .NET CU / Dynamic Update）を実際に公開している **メタデータ面**はどれか
- その LCU は **Servicing Stack Update** を先に適用する必要があるか（`0x800f0823` 失敗）
- `install.wim` がすでに **PCA2023 署名のブートバイナリ**を同梱しているか、合成が必要か
- 物理ハードウェアを起動せずに結果を **検証**する方法

**想定読者。** 2種類です。第一に、実在の ISO 更新パイプラインを保守する人間のエンジニア（Takayuki / usui-tk）。第二に — そして明示的に — **この作業の記憶を持たない将来の LLM/エージェントのセッション**。後者は、ソース選定を引き継ぎ、ツールを再実行し、埋め込みのスクリプトとスナップショットだけからデータを再現できなければなりません。結論先出しの構成と埋め込み実装は、主にこの第二の読者のために存在します。

### 1.1 Non-goals（非ゴール）`[STABLE]`

期待値を正確に設定するため、以下は明示的に **対象外**です。本アーキテクチャはこれらを解決も論評もしません。これらを期待する読者は別を当たってください。

- **Windows クライアントエディション**（Windows 10 / 11 のコンシューマ/Pro メディア）。一部のペイロード（UUP, 24H2）がクライアント系と共有でも、本書は Windows Server LTSC のみ。
- **オンライン / in-place servicing。** カバーするのは *オフライン* の `install.wim` への slipstream のみ。ライブの Windows Update、in-place アップグレード、稼働中OSのパッチ適用は対象外。
- **Windows Update for Business** のポリシーオーケストレーション、デプロイリング、更新の延期。
- **WSUS / SCCM / ConfigMgr のデプロイ。** これはパッチ *配布* やフリート管理の設計ではなく、*メディアビルド* の設計です。（MS-WSUSSS は検証オラクルとしてのみ登場し、配布面としては扱いません。）
- **エンタープライズのパッチ管理** 全般 — コンプライアンスレポート、メンテナンスウィンドウ、承認ワークフロー。
- **非 x64 アーキテクチャ**（arm64, x86）— *除外対象* として言及する場合（例：2025 の arm64 .NET 兄弟）を除く。
- **ドライバー / ファームウェア / OEM イメージのカスタマイズ**、起動可能 USB の作成。
- **Secure Boot のエンドツーエンド確定検証** — `[DRAFT]`（§8）としてのみ存在し、メタデータ作業と同じ検証水準には達していません。

## 2. 結論サマリ：3つの面、1つの本番ソース

選定したパイプラインのエンドツーエンドの形：

```
Learn release-info (?accept=text/markdown)      → ビルドごとの現行 LCU KB を発見
            |
            v
Microsoft Update Catalog  [C]  (PRODUCTION)     → KB を解決 → ダウンロードURL + SHA-1 digest
            |                                       (Dynamic Update 含む全ライン; 認証不要)
            v
Download .msu / .cab  →  verify SHA-1
            |
            v
DISM offline servicing  (SSU/baseline → LCU → .NET → SafeOS-DU(WinRE))
            |
            v
PCA2023 media synthesis (_EX boot bins)  [DRAFT, §8]
            |
            v
Rebuild ISO  →  signer-chain + boot verification
```
上流（発見＋解決）は到達可能で再現可能な Catalog に寄せ、正しさは [A] SOAP オラクルに対して証明し、[B] cab で相互チェックします。

| | 面 | 概要 | エージェントのサンドボックスから到達可? | オフライン再現可? | **全**ライン網羅? | 本パイプラインでの役割 |
|---|---|---|---|---|---|---|
| **[A]** | MS-WSUSSS SOAP | サーバー間同期プロトコル（権威） | **No**（egress で TLS-MITM、Windows ホスト要） | No | Yes | **オラクル / answer-key のみ** |
| **[B]** | `wsusscn2.cab` | オフライン適用性スキャンカタログ | Yes（DL + 解析） | Yes | **No**（クラシックOSの Dynamic Update を欠く） | **検証ソース** — 依存/適用性/オフライン検証DB |
| **[C]** | Microsoft Update Catalog | 公開 HTML ウェブアプリ | **Yes**（HTTP, 認証不要） | Yes（全レスポンスをキャッシュ） | **Yes**（Dynamic Update 含む） | **本番ソース** |

**なぜ Catalog が勝つか — そして、なぜ権威が決定軸ではないか。** [A] は厳密に最も権威があります。実在の下流 WSUS サーバーが使う当のプロトコルであり、本書の ground-truth の出所です。「最も権威がある」が基準なら [A] が文句なしに勝ちます。しかし目的は **無人かつ再現可能に ISO をビルドするエージェント**であり、その目的に照らすと：

- [A] は **到達可能性のテストに落ちる。** サンドボックス→`sws.update.microsoft.com` の経路は、egress ゲートウェイの上流 TLS-MITM の証明書検証失敗で、こちらのリクエストが送られる前に切断されます。Microsoft 証明書をコンテナに取り込んでも解決しません（コンテナのトラストストアの不足ではない）。[A] は実在の Windows ホストと慎重なマルチコール同期シーケンスを要し、いずれもエージェント単独では再現できません。
- [B] は **網羅性と扱いやすさのテストに落ちる。** 到達可能・再現可能で digest でオラクルに一致しますが、**設計上 Dynamic Update のラインを欠きます**（これは *稼働中OS向けのオフライン適用性スキャン* であり、SafeOS DU は別イメージである WinRE を対象とするためスコープ外 — §5.5）。さらに数GB規模で、素朴な扱いは確実に停止します。これを単一ソースにすると、結局 Dynamic Update のために Catalog へ寄る必要があり、利得なく2ソースを維持することになります。
- [C] は **3つすべてに合格する。** 認証不要の素の HTTP で直接到達でき、Dynamic Update を含む **全** ラインを提供し、直接の CDN URL と SHA-1 digest を返します。エージェントは検索・解決・ダウンロードができ、全レスポンスをキャッシュして再実行をオフラインかつ冪等にできます。

つまり判定は **自律エージェントにとっての操作性**で決まり、プロトコルの序列では決まりません。[A] をオラクルとして残すのは、それが最も権威があるからこそ — Catalog が正しい成果物を選んだことを *証明* できるから — であり、[B] は高速なオフライン依存チェックとして残します。しかしビルドが実際に消費する成果物は **[C]** から来ます。

### 2.1 Authority / Production / Verification は3つの異なる役割

最もよくある読者の誤りは、「権威がある」と「使うのに最適」を1つの軸に潰してしまうこと — *SOAP → Microsoft 公式 → 最も正しい → ゆえに使う* と推論することです。この連鎖は最後の一歩で誤っています。**「最も権威がある」は「最も使いやすい」ではありません。** 目的は自動 ISO ビルドであり、その目的に対して面は **単一の序列ではなく、3つの異なる役割**に分かれます。役割の定義を先に示します：

> - **権威ソース（Authority source）** — *構成上、正準的に正しい面*（実在の WSUS サーバーがそこからカタログ全体を毎日同期する）。ground truth を定義するために使い、ビルドには供給しません。
> - **本番ソース（Production source）** — *自律ビルドパイプラインが直接消費するメタデータソース*で、適用する成果物（ダウンロードURL + 整合性 digest）を取得します。ビルドが実際に呼ぶのはこれだけです。
> - **検証ソース（Verification source）** — *関係（依存 / 適用性 / supersedence）のオフラインDB*で、本番ソースが解決したセットを検証します。

- **権威ソース — MS-WSUSSS [A]。** ground truth。ビルドには消費されず、*本番ソースが正しいことを証明する*ために存在します。
- **本番ソース — Microsoft Update Catalog [C]。** ビルドが実際に呼ぶ面。序列ではなく操作性で選定。
- **検証ソース — `wsusscn2.cab` [B]。** Catalog とは *別の役割*。Catalog が **成果物**（URL + digest）を返すのに対し、cab は **関係**（依存・適用性・supersedence）を返します。Catalog が解決したセットを検証するもので、成果物のフォールバック格納庫ではありません。

> **命名規約（本書全体）。** 以降、アーキテクチャ上の **役割名を一次の指示対象**とし、具体的な面は実装詳細として扱います。本書は「SOAP が Catalog を証明する」より「**権威ソース**が**本番ソース**を検証する」を優先し、面の名前（SOAP / Catalog / cab）はメカニズムの説明で必要な箇所に後置します。読者が覚えるべきは役割名であり、面はその役割が 2026 年時点でどう実装されているかにすぎません。

**Figure 2 — 三役モデル（Authority / Production / Verification）。**

```
                 +------------------------------+
                 |        AUTHORITY SOURCE       |
                 |        MS-WSUSSS (SOAP)        |
                 |  the protocol a real WSUS     |
                 |  server syncs from daily      |
                 +---------------+---------------+
                                 |
                      Digest verification  (SHA-1, schema-independent)
                                 |  "Catalog is not trusted on faith —
                                 v   it is SOAP-verified"
                 +------------------------------+
                 |       PRODUCTION SOURCE       |
                 |   Microsoft Update Catalog    |
                 |  reachable · complete · agent-|
                 |  drivable · gives URLs+digests|
                 +---------------+---------------+
                                 |
                          Download URL  →  ISO build pipeline
                                 ^
                      Applicability / dependency / supersedence
                                 |
                 +------------------------------+
                 |      VERIFICATION SOURCE      |
                 |        wsusscn2.cab           |
                 |  offline dependency / applic- |
                 |  ability / validation database|
                 +------------------------------+
```

この分離が表面的でなく決定的である理由は3つあります。

1. **Catalog は唯一の *単一本番ソース（Single Production Source）*。** これがアーキテクチャ上の論拠であり、「到達可能」より強い主張です。本番ソースが有用なのは、パイプラインが必要な **すべて** のラインをそこ *単独* で取得でき、後付けの第2ソースが要らない場合だけです。これを満たすのは Catalog **のみ**：到達可能 *かつ* 全ライン（LCU, SSU, .NET CU, **そして Dynamic Update**）を提供します。SOAP は全ラインを持つが到達不可、cab は到達可能だが Dynamic Update を欠く — どちらも単独で成立しません。ゆえに Catalog は単に *到達可能なソースの一つ* ではなく、**単一本番ソース**として機能できる唯一のソースであり、本番アーキテクチャのデータ依存はちょうど1つで済みます。最小アーキテクチャは偶然ではなく特長です。
2. **Catalog は信用でなく SOAP 検証済み — クロスソースのプライマリキーで結合。** Catalog が解決した各ラインは、**ファイル Digest（SHA-1, base64）** で [A] オラクルに照合済みです。Digest は単なる整合性チェックサムではなく、**3つの面すべてで共有されるプライマリキー**と捉えるのが適切です — 同じ物理ファイルは、それぞれの包み方に関係なく、SOAP でも Catalog でも `wsusscn2.cab` でも同じ Digest を持ちます。このプライマリキーで照合することで、主張は「Catalog はたぶん正しい」から「Catalog の成果物は、暗号学的に、権威プロトコルが提供する当のファイルと同一である」へ変わります（§12.3）。これが本書最大の保証です。
3. **Catalog は Dynamic Update を持つ唯一の *到達可能* な面。** `wsusscn2.cab` は設計上 SafeOS DU の系統を欠き（§5.5）、SOAP は持つが到達不可。Catalog はそれを持ち **かつ** 認証不要で到達可能です。ISO が現に必要とする OS ライン（2022/2025 SafeOS DU）にとって、これは単独で決め手であり、事実1が成り立つ具体的理由でもあります。

## 3. 評価マトリクス（判定を好みでなく設計判断にするために）

§2 の比較は単一の「どれが最良か」ランキングではなく、複数の独立軸にわたるスコアです。マトリクスとして並べることで、判定は主観的な好みから、読者が再導出できる再現可能な設計判断に変わります。

| 軸 | 問い | [A] SOAP | [B] `wsusscn2.cab` | [C] Catalog |
|---|---|---|---|---|
| **到達可能性** | ビルド環境（エージェントのサンドボックス）から、特権サイドチャネル無しで取得できるか? | ✗（egress で TLS-MITM; Windows ホスト要） | ✓（CDN ダウンロード） | ✓（HTTP, 認証不要） |
| **機械可読性** | レスポンスは通常ツールで解析できる安定した形か? | △（不透明な SOAP blob; 空 500 フォルト; `?wsdl` 無し） | ✓（XML だが 25 GB） | ✓（HTML, 予測可能なフォーム） |
| **再現性** | 第三者が再実行して同一結果を得られ、全入力を固定可能か? | ✗（ライブのプロトコル/アンカー状態） | ✓（コンテンツアドレス可能; SHA-256 で固定） | ✓（全 HTML/HEAD レスポンスをキャッシュ） |
| **自律エージェント親和性** | エージェントが反復的に *扱える* か（query → read → adjust → retry を HTTP/regex/CAB ツールのみで）? | ✗ | △（オフラインだが巨大; 素朴な扱いで停止） | ✓ |
| **網羅性**（**Dynamic Update** 含む） | ISO が必要とする *すべて* のラインを公開しているか? | ✓ | ✗（クラシックOSの SafeOS DU 無し） | ✓ |
| **安定性** | 識別子は Microsoft のリネームを越えて持続するか? | ✓（GUID） | ✓（GUID） | △（タイトル文字列はリネームする; **GUID/KB は不変** — §6.1） |
| **クロス検証能力** | スキーマ非依存のキーで独立ソースと照合できるか? | n/a（自身がオラクル） | ✓（digest ↔ SOAP） | ✓（digest ↔ SOAP） |
| **→ Decision（帰結する役割）** | 上記スコアが各面に確定させるもの | **権威ソース**（オラクルのみ） | **検証ソース**（依存/検証DB） | **本番ソース** ✅（単一・自律ビルド） |

マトリクスの読み方：**[C] は、無人ビルドに効くすべての軸 — 到達可能性、機械可読性、再現性、エージェント親和性、網羅性、クロス検証 — で良好な唯一の面**です。**[A]** は *権威*（この表とは直交する軸）で最高ですが、到達可能性とエージェント親和性で明確に落ちます — だからこそオラクルであってソースではありません。**[B]** は到達可能・再現可能・クロス検証可能ですが、網羅性（Dynamic Update 無し）に落ち、エージェント親和性も限界的です — だからこそ検証DBであって本番ソースではありません。

マトリクスは記述で終わらず **決定**で終わります。最下行はスコアが強制する設計上の結論です。ビルドパイプラインが依存する全軸をクリアするのは **[C]** だけなので、これが **本番ソース**になります。**[A]** は権威で勝つが到達可能性/エージェント親和性に落ちるので **権威/オラクル**に限定。**[B]** は到達可能でクロス検証可能だが網羅性に欠けるので **検証ソース**に落ち着きます。§2.1 の役割は、このマトリクスに先んじて主張したものではなく、ここから *導出* したものです。

「自律エージェント親和性」軸について一言 — これは最も陳腐化しにくい軸だからです。Catalog の価値は、単に LLM が *読める* ことではなく、自律エージェントが **パイプライン全体**を、人手も特権サイドチャネルも無しに走らせられることにあります。

```
agent → HTTP GET Search.aspx → parse HTML → updateID
      → HTTP POST DownloadDialog.aspx → parse JS → {URL, SHA-1 digest}
      → HTTP GET CDN → download .msu/.cab → verify SHA-1
      → DISM offline servicing → rebuild ISO
```
各矢印は通常の HTTP/parse/hash 操作です。基準を（狭い「LLM 親和性」ではなく）**Autonomous-Agent-Friendly** と表現することで、エージェントのツールが成熟しても結論は有効であり続けます。陳腐化しにくいのは *技術* 用語でなく *能力* 用語です。「LLM」「AI」は数年で呼び替えられますが、**Autonomous Resolver** が駆動する **Autonomous Build Pipeline** がメディアの **Autonomous Build** を行う、という記述はワークフロー自体の記述であり、何が走らせるかに依存しません。それら持続的な用語で言えば、Catalog の決定的特性は：完全に **自律的なビルドパイプライン**が端から端まで — 発見・解決・ダウンロード・検証・適用 — を、人手も特権サイドチャネルも無しに所有できる唯一の面である、ということです。

### 3.1 アーキテクチャ意思決定記録（ADR サマリ）`[STABLE]`

ソフトウェアアーキテクトが1ブロックで決定を読めるよう、標準的な ADR の形で示します。

- **Context（背景）。** 自律パイプラインが、パッチ適用済み Windows Server LTSC ISO を、オフラインかつ再現可能にビルドする必要がある。パッチの識別子と依存関係は、到達可能性・網羅性・機械可読性で異なる複数の Microsoft の面に存在する（§2）。ビルド環境は、Windows ホストも特権サイドチャネルも持たない無人のエージェントサンドボックスである。
- **Alternatives considered（検討した代替案）。** **(A) MS-WSUSSS SOAP** — 最も権威があり網羅的。だがサンドボックスから到達不可で再現困難。**(B) `wsusscn2.cab`** — 到達可能・再現可能・digest 一致。だが設計上 Dynamic Update を欠き、数GB規模。**(C) Microsoft Update Catalog** — 認証不要で到達可能、網羅的（Dynamic Update 含む）、エージェント駆動可能、digest 検証可能。（§3 のマトリクスで7軸採点済み。）
- **Decision（決定）。** **本アーキテクチャは Microsoft Update Catalog を単一の本番ソースとして選定する。** 理由は *それが、到達可能性・網羅性・機械可読性を同時に満たす唯一の代替案 — すなわち **単一本番ソース**として機能できる唯一の選択肢 — でありながら、権威に対して暗号学的に検証可能だからである*。SOAP は **権威ソース**（オラクル）として、`wsusscn2.cab` は **検証ソース**として残す。
- **Consequences（結果）。** *正の側面:* 本番アーキテクチャのデータ依存はちょうど **1つ**（最小アーキテクチャ）。解決された全成果物は Digest プライマリキーで権威に対し **証明**される。パイプライン全体が自律エージェント駆動可能。*負/受容するコスト:* Catalog は HTML（regex パーサーを隔離・保守する必要、§6.1）。タイトル文字列は OS 世代でリネームする（GUID/KB 不変で緩和）。クラシックOSの Dynamic Update は Catalog に *のみ* 存在するため、その1ラインにオフラインのフォールバックは無い。*残課題:* Secure Boot / `_EX` メディア作業（§8）は **`[DRAFT]`** で、同じ検証水準にはまだ達していない。

---

# PART II — 技術的裏付け（各面がその評価を得た理由）

この Part は Part I の「なぜ」です。判定を受け入れる読者は Part IV へ飛んで構いません。受け入れない読者は、各面のデータモデルをここで確認してください。

## 4. [A] MS-WSUSSS — 権威あるオラクル（そしてなぜソースになれないか）

### 4.1 正体と、アクセスの壁

MS-WSUSSS は Microsoft の **サーバー間同期** SOAP プロトコル（「USS」/ upstream-server-sync 面）です。下流の WSUS サーバーがこれを呼んで更新カタログ全体を取得します。実在のクライアントOSは兄弟の **MS-WUSP** クライアント-サーバープロトコルを使います。いずれも完全かつ公開で仕様化されています（全リクエスト形・型・フィールド・シーケンス）。エンドポイント（`sws.update.microsoft.com`, `fe2cr.update.microsoft.com` …）は実働の本番サーバーで、実在の WSUS サーバーが毎日同期しています。

この「公開仕様＋呼び出し可能エンドポイント＋実証済みサーバー」の三点が **クライアント先行ルール**の根拠です。観測される障害は既定では *こちらの* リクエストの欠陥であって、サーバーの制限ではありません。同時にアクセス判定の根拠でもあります。プロトコルは動くが、**ここからは動かない**。エージェントのサンドボックスは `sws` への TLS ハンドシェイクを完了できません — egress ゲートウェイが上流 TLS-MITM を行い、こちらのリクエストが送られる前に証明書検証が失敗します。Microsoft ルートをコンテナに取り込んでも直りません。よってメタデータ側は **Windows ホスト**（PowerShell 5.1, ja-JP）を要し、一方 **ペイロード CDN**（`dl.delivery.mp.microsoft.com`、`*.microsoft.com` に一致）はサンドボックスから到達可能 — メタデータは取れなくとも、小さなペイロードはコンテナ内で取得し `cabextract` できます。

### 4.2 データモデル：bundle → leaf → payload

`[VERIFIED]` WSUSSS 宇宙の各更新は3層オブジェクトです。

- **Bundle** — `<Categories>`（Product GUID と Classification GUID）、`<Prerequisites>`（適用性 detectoid）、supersedence を持つ。これが *選択* する単位（「最新の live な Server 2025 Security バンドル」）。
- **Leaf** — bundle の子（`BundledLeaf` / 逆方向 `BundledBy`）。実際の `<PayloadFiles>` と詳細な適用性を持つ。
- **Payload files** — 具体的な `.cab` / `.msu` / `.psf`。各々 **Digest（SHA-1, base64）**・Size・解決可能なダウンロードURLを持つ。

識別キーは `UpdateID`（GUID）+ `RevisionNumber`。**Digest はスキーマ非依存の結合キー**で、各面が物理ファイルをどう包んでも、[A]/[B]/[C] を横断して同一ファイルを特定できます。

### 4.3 ハンドラ分類とエラ（era）モデル

`[CONFIRMED-EMPIRICAL]` この面は3つの更新 **ハンドラ**を露出し、パッチラインは世代をまたいでそれらを移動します — 4つのOSに関する最重要の構造事実です。

- **`UpdateHandlers/Cbs`** — 2016/2019/2022 のレガシー LCU / SSU / .NET。適用性は完全な CBS コンポーネントツリー（2016 で豊富、2022 で薄くなる）。
- **`UpdateHandlers/OSInstaller`** — UUP（2025）：LCU・.NET・SafeOS DU。適用性は `ProductReleaseInstalled` + `DeviceAttribute`（薄い SOAP）に **CompDB**（§4.5）。
- **`UpdateHandlers/CommandLineInstallation`** — **2022 SafeOS DU のみ**（レガシー DU モデル）。`HandlerSpecificData` は `InstallCommand Program="Windows10.0-KB5094157-x64.cab"`。適用性は自明（`IsInstalled=False` / `IsInstallable=True`）。DU は稼働中OSに依存せず DISM がセットアップメディア/WinRE へ無条件に適用するため。

### 4.4 世代をまたぐ SSU と .NET — 「3つのエラ」パッケージング

`[CONFIRMED-EMPIRICAL]` SSU の *パッケージ自体* は世代間で一貫します（`Handler=Cbs`、`selfUpdate="true" permanence="permanent"`、ペイロードは `.cab` + express/`.psf`）。変わるのは **パッケージングの形**です。

| OS | SSU の配信 | SSU ビルド（2026-06） | LCU の servicing-stack floor |
|---|---|---|---|
| 2016 | **スタンドアロン**（独自 bundle/leaf, `KB5094141`） | 14393.9220 | 14393.7692（実値, `installerAssembly`） |
| 2019 | LCU leaf に **埋め込み**（`KB5094143`） | ~17763.8880 | 17763.2090（実値） |
| 2022 | LCU leaf に **埋め込み**（`KB5094147`） | 20348.5251 | プレースホルダ `6.0.0.0`（実値は埋め込みサブパッケージのみ） |
| 2025 | **バンドルファイル** — LCU メガペイロード内の UUP checkpoint（`SSU-26100.32985`） | 26100.32985 | n/a（leaf に CBS floor 無し; checkpoint を LCU 本体より先に適用） |

`0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED` 失敗は適用時の **数値バージョン比較**です。CBS はイメージの現行 servicing-stack バージョンを LCU の必要 floor と比較します。*実* floor を `installerAssembly` で宣言するのは **2016 と 2019** のみ。それを先に満たす *スタンドアロン* SSU を公開するのは **2016** のみです。（2019 の floor は LCU に埋め込まれた SSU で満たされます。）.NET も同じ legacy→UUP 勾配に従います。2016/2019/2022 は `Handler=Cbs` で単一の `NDP48`/`NDP481` cab、2025 は `Handler=OSInstaller` で小さな `DotNetServicingCompDB_*.cab` + NDP481 cab。

### 4.5 2025 UUP CompDB 適用性モデル

`[VERIFIED]` 2025 では深い適用性が **アセンブリ単位の CBS ツリーではなく**、**Composition Database（CompDB）**、スキーマ `http://schemas.microsoft.com/embedded/2004/10/ImageUpdate` — DISM `/Apply-Image` が使う当のイメージ合成システム — です。小さな CompDB cab（~11 KB）は CDN 到達可能でサンドボックス内で `cabextract` できます。各 CompDB は、更新クラス（`Type` = Standalone / BuildUpdate; `Feature Type` = **GDR** / **SetupDynamicUpdate** / **SafeOSUpdate**）、適用元ビルド（`OSVersion`）と生成ビルド（`TargetOSVersion`）、パッケージ＋ペイロード（cab + hash）を述べます。2025 ではこのモデルが LCU / .NET / Setup DU / SafeOS DU で統一されます。**SSU には CompDB が無く**、直接の checkpoint ペイロードとして配信され、（あらゆるエラと同様に）自己更新します（selfUpdate/permanent）。

2025 限定の注記：**Setup DU は 23H2/24H2 エラの構成物**です。Server 2022 には Setup DU が **存在しません**（catalog 確認済み: 21H2 の Setup DU 件数 = 0）。その唯一の Dynamic Update は SafeOS DU です。よって 2022 の「Setup DU」マトリクスセルは未取得ではなく N/A です。

### 4.6 [A] の結論 — そして、なぜ SOAP はそれでも不可欠だったか

[A] は **完全で権威あるモデル**と、全世代・全ラインの ground-truth digest を与えます。オラクルとして代替不能です。しかしエージェントから到達不可、Windows ホストを要し、再現困難 — ゆえに本番ソースにはなれません。そのデータは、[B] と [C] を検証する per-OS `dataset/<os>.json` answer-key として生き続けます（§12）。

**なぜ SOAP はそれでも必要だったか。** Catalog を本番ソースに選んだことで、SOAP 作業が後から見て不要に見えるかもしれません — そうではありません。Catalog は到達可能で網羅的ですが、**自分自身を検証できません**。返したファイルがその KB の *正準的* 成果物か、ある行の `updateID` が本当の WSUS バンドル識別子か、を Catalog 内部の何も教えてくれません。それに答えられるのは独立した権威面だけで、SOAP がその面です。依存はこう走ります。

```
Catalog がファイルを解決  →  (Catalog 単独では正準性を証明できない)
        │
        ▼
SOAP オラクルの Digest  ==  Catalog の Digest      →  証明完了
```

ゆえに SOAP は、本番では **消費されない**にもかかわらず、**研究/検証フェーズでは不可欠**でした。§12.3 の各 Catalog 結果を *仮定* でなく *証明済み* と述べられるのは SOAP のおかげです。正しい読み方は「SOAP は使えないと判明した」ではなく、「SOAP は Catalog を信頼できるものにした計器であり、その役目を果たして本番経路から退いた」です。これはまさに §2.1 の Authority 対 Production の分離を、SOAP の側から見たものです。

## 5. [B] `wsusscn2.cab` — オフライン依存関係DB（強力な次点、一次ではない）

### 5.1 正体と、安全な取り扱いの問題

`wsusscn2.cab` は **Windows Update のオフライン適用性スキャンカタログ** — Windows Update Agent がマシンをオフラインでスキャンする際に使うファイルです。約 650 MB の単一 CAB で、おおむね月2回再公開され、Windows Update CDN から認証不要でダウンロードできます。アクセス軸で [A] とは正反対：オフライン・静的・コンテンツアドレス可能・エージェント解析可能です。

難点は規模です。展開すると 75 個の detail cab にわたる **25 GB** の XML になります。素朴な扱い（全ロード、`cat`、エディタで開く）は確実にエージェントのコンテキストを枯渇させ、セッションを停止させます。譲れない規律（すべて **MUST**）：抽出前に一覧する、選択的に抽出する、`lxml.iterparse` / `XmlReader` でストリームする、Digest で特定する、そして detail cab を一括抽出 **MUST NOT**。（§11 のリファレンス実装がこれをコード化しています。）

### 5.2 物理構造：2層、RevisionId シャーディング

`[CAB-VERIFIED 2026-06-24]`（スナップショット SHA-256 `5b075a6d…eec122`, 649,341,212 B, package.xml `CreationDate 2026-06-09`）：

```
wsusscn2.cab  (76 top-level entries)
├── index.xml          <CABLIST>: RevisionId → どの packageN.cab か (RANGESTART 経由)。二分探索可能。
├── package.cab  → package.xml = MASTER XML (114 MB)
│      <OfflineSyncPackage PackageVersion=1.1 ProtocolVersion=1.0 xmlns=…/OfflineSync>
│        <Updates>      <Update RevisionId=…> × 136,478 </Updates>
│        <FileLocations><FileLocation Id="<digest>" Url="…"/> × 97,339</FileLocations>  ← トップレベル1セクション
└── package2.cab … package75.cab   = DETAIL cabs; 計 136,478 個の `c/<RevisionId>` (Updates と 1:1)
```

Master XML のルート要素は **`<OfflineSyncPackage>`**、名前空間は `http://schemas.microsoft.com/msus/2004/02/OfflineSync` — 「offline sync package」はこの形式に対する Microsoft 自身の名称で、`wsusscn2.cab` は単なる配布ファイル名にすぎません。75 個の detail cab への分割は **コンテンツでサイズ調整した RevisionId 範囲シャーディング**です。`index.xml` の `<CABLIST>` が各 `packageN.cab` に連続した RevisionId 範囲を割り当て、蓄積コンテンツが新シャードを要する所に境界が来ます。`CreationDate ↑ ⇒ RevisionId ↑ ⇒ 後ろの cab` なので、**全OSの当月パッチセットは常に最新の 1〜2 cab に着地**します（本スナップショットでは package74/75）。

### 5.3 キー/識別モデル — cab は [A] とどう違うか

`[CAB-VERIFIED 2026-06-24]` cab は [A] と同じデータを別の形で持ち、その差分が肝心です。

- **識別キー = `RevisionId`（int）。** 全クロスリンクがこれを使う（`<BundledBy><Revision Id=…>`, `<SupersededBy><Revision Id=…>`）。（`UpdateId`+`RevisionNumber` も存在するが、リンクは RevisionId 経由。）
- **ファイルキー = Digest（SHA-1, b64）。** leaf の `<PayloadFiles><File Id="<digest>"/>` が、単一トップレベル `<FileLocations>` セクション経由で URL に解決される。**すべてを Digest で結合する。**
- **[A] と方向が反転。** SOAP は bundle に順方向 `BundledLeaf` / `SupersededIds` を与える。cab の **Master** は対象に **逆方向** `BundledBy` / `SupersededBy` を、**順方向** `BundledUpdates` / `SupersededUpdates` は per-package **detail** cab に置く。
- **Master 子要素に名前空間プレフィックス無し**（既定 xmlns）。SOAP は `upd:` を使った。
- **Master は `KBArticleID` も Title も持たない。** KB は `<FileLocation Url>` 内の `kb(\d+)` トークンから導出する。

`[CAB-VERIFIED 2026-06-24, セッション2訂正]` detail cab は1つでなく **3つ**のストリームを持つ：`c/<RevisionId>`（コア：識別子、関係、ApplicabilityRules、CBS ツリー）、`l/<lang>/<RevisionId>`（ローカライズ Title — つまり **Title は cab に存在する**、言語別）、`x/<RevisionId>`（ExtendedProperties: **FileName + 全ファイル variant + SHA-256**）。以前の「FileName は cab に無い」はセッション1で `c/` のみを見た誤りでした。3ストリームとも CAB 解凍後はプレーンテキスト XML です。

### 5.4 supersedence の照合 — 「最新」の核心

`[CAB-VERIFIED 2026-06-24]` 「どの LCU が現行か?」の成否を分ける問いは、cab の supersedence がオラクルと一致するかです。完全に一致します。

- Master: 逆方向 `<SupersededBy>`（本スナップショットで 14,136 件）。
- Detail（bundle `c/<RevisionId>`）: 順方向 `<Relationships><SupersededUpdates>`。
- **2016 LCU bundle の順方向セット = 119 ID = SOAP `SupersededIds[]` と完全一致**（∩ = 119, cab のみ = 0, soap のみ = 0）。

よって「live」= `<SupersededBy>` が空。ある Product GUID の最新 live bundle が現行です。これでオラクルの選択を 1:1 で再現します。

### 5.5 唯一の真の欠落：SafeOS Dynamic Update は cab スコープ外

`[CAB-VERIFIED 2026-06-24]` これは `wsusscn2.cab` が **持たない**唯一のラインで、その理由が一般化するため重要です。徹底的なスイープ（leaf UID `b20655a0`、bundle UID `c6476311`、SHA-1 と SHA-256 の両方、KB トークン、8段の supersedence チェーン全体 — すべて Master で 0；**かつ** 74 detail cab × {`c/`,`l/`,`x/`} の全スイープ = 0/74）の後、2つのエスカレーション（cab のどこにも埋め込み圧縮 blob は無い；ダウンロードした LCU の `update.mum` 191 パッケージに SafeOS-DU 参照ゼロ）も経て、**2022 SafeOS DU KB5094157 は cab とその参照ペイロードの真に外部**であると確定 — *証明された* 不在です。

理由は二度訂正され、いまや正確です：**`wsusscn2.cab` は *稼働中OS* 向けのオフライン適用性スキャンカタログであり、SafeOS DU は別イメージである WinRE を対象とするためオフラインスキャンのスコープ外で、SafeOS-DU 更新カテゴリ全体が除外される。**（「WSUS=No」ではありません — そのチャネルの主張は WinRE *ラッパー* KB5098814 という別パッケージのものでした。KB5094157 自体は WU + Catalog + WSUS に出ています。）アーキテクチャ上の根本原因：クラシック servicing OS（2016/2019/2022）は SafeOS DU を **完全に別個の更新**として配信 ⇒ 決してバンドルされず、オフラインスキャン cab に入らない。UUP OS（2025）は SafeOS DU を単一マルチファイル LCU leaf 内に **同梱** ⇒ 存在し cab から導出可能。これが、2025 の SafeOS DU が cab から復元でき 2022 のはできない、まさにその理由です。

### 5.6 OS別 cab ネイティブ resolver（と OS別の落とし穴）

`[CAB-VERIFIED 2026-06-24]` 4つの独立した OS別 resolver が、cab 単独でオラクルを再現します（全ラインで digest 完全一致）。これらは設計上 **別個に保持**します — ロジックを早く共有しすぎるとデータのニュアンスが隠れるためです。共有 resolver なら静かに壊す落とし穴：

- **2016** — SSU bundle は `ServicePacks` でなく `Security` 分類。LCU と SSU はオフラインではファイル名で区別不能で、**SelfContained `.cab` サイズ**で判別（SSU ~12.6 MB vs LCU ~1.83 GB, ~145倍。両者とも FileLocation URL への HEAD でオラクル Size に一致）。
- **2019** — Product GUID は bundle 上で最頻のものではない；OS 固有の `f702a48c-…` を使う。.NET ラインは **LCU より古い**（5月 vs 6月）⇒ 最新-Security-全体でなく line ごとの最新を選ぶ。in-scope .NET leaf = **non-NDP48**（ベース 4.7.2; 3.5 は同梱）。
- **2022** — 同じ KB が2つの Product GUID 下に存在（`71718f13` 一般 vs `97b08ca0` Azure Edition）；`71718f13` を使う。in-scope .NET は **2019 と反転**：**NDP48** が in-scope（2022 の in-box .NET = 4.8）、NDP481 は out-of-scope。SafeOS DU は cab に無い（§5.5）。
- **2025** — LCU は SelfContained cab でなく **16ファイルの UUP メガペイロード1つ**；ファイル名で分類（`ssu-*`, `*-baseless*`/`*-x64.cab` = SafeOS, `.msu` の KB==LCU?LCU:GA baseline, `-ndp*` = .NET, `*.wim` = LP/FoD, `*metadata*` = meta）。SSU + SafeOS DU は leaf 埋め込み。in-scope .NET = **NDP481**（再び反転）。arm64 は .NET のみ存在 → スキップ。

### 5.7 スコープフィルタ：タイトルでなく GUID ベース

`[CAB-VERIFIED 2026-06-24]` 約 136,000 件の Master エントリを約 138 件の in-scope bundle に絞るフィルタは **GUID** を使います。GUID は WSUS のグローバル識別子で、（§6.1 の壊れやすいタイトル文字列と違い）表示名のリネームを越えて持続するからです。4つの **Server LTSC Product GUID**：2016 `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5`, 2019 `f702a48c-919b-45d6-9aef-ca4248d50397`, 2022 `71718f13-7324-4b0f-8f9e-2ca9dc978e53`, 2025 `b256987d-4693-4c87-955d-dbb9341205eb`。観測された5つの **Classification GUID**：SecurityUpdates `0FA1201D-…`（LCU）, UpdateRollups `28BC880E-…`（.NET CU）, ServicePacks `68C5B0A3-…`（SSU）, CriticalUpdates `E6CF1350-…`, Updates `CD5FFD1E-…`（Dynamic Update）。EOS/ESU の OS GUID（2008/2008 R2/2012/2012 R2）は明示的な **deny-list**：サポート終了でも cab からデータが消えないためです。スコープ規則は **allow-overrides**（deny-list GUID が併存していても、allow-list GUID を *いずれか* 持てば採用 — 例：マルチOSの MSRT バンドル）。

### 5.8 [B] の結論

[B] は到達可能・再現可能・オラクルに対し digest 完全一致です。しかし **Catalog とは役割が異なり**、両者を混同するのが罠です。Catalog は **成果物ソース**（ファイル＝URL+digest を返す）。`wsusscn2.cab` は **関係データベース** — 成果物ソースが答えられない問いに答えます。

- **依存** — この LCU は servicing-stack floor を宣言するか、セットはそれを満たすか?（`0x800f0823` 事前チェック）
- **適用性** — この更新はオフライン WUA スキャンモデルで、この OS/ビルドに適用可能か?
- **supersedence / 検証** — 選んだ LCU はこの Product GUID の最新の非 superseded ビルドか?

ゆえに [B] は **オフラインの依存/適用性/検証データベース**と理解するのが最適で、*Catalog が解決したセットを検証* するために使います — 成果物のフォールバック格納庫ではありません。*単一* 本番ソースにはなれません：設計上 Dynamic Update を欠き（§5.5）、数GB規模で、停止回避にストリーミング規律を要します。§2.1 の三役モデルにおける本来の位置は **検証ソース**で、本番 Catalog の下に座し、Catalog が露出しない関係層を供給します。

## 6. [C] Microsoft Update Catalog — 本番ソース

### 6.1 正体と、扱うべき命名の癖

`catalog.update.microsoft.com` の Catalog は、実際の `.msu`/`.cab` ダウンロード URL を公開する唯一の面で、認証不要でエージェントから直接到達できます。**JSON API ではなく HTML ウェブアプリ**なので、すべては HTML への regex に Microsoft Learn の companion Markdown 1つを加えたものです。クライアントはブラウザ `User-Agent` を送る SHOULD（素のライブラリ UA は拒否され得る）、リクエストを間隔（~0.6 s）あける SHOULD、再実行をオフライン・冪等にするため **全レスポンスをキャッシュする** SHOULD です。

唯一の構造的な罠は Server 2019 と 2022 の間の **OS 命名変更**です。古い OS はタイトルでブランド名を使い（「Windows Server 2019」）、Server 2022 から Microsoft はコードネーム形に切り替えました（2022 は「Microsoft server operating system, version 21H2」、2025 は「…version 24H2」 — ブランド「Server 2025」はタイトルに一切現れない）。よってタイトルヒューリスティックは **両方** の命名規約を保持する MUST、そして（最もよくある静かな誤り）**Products 列で後フィルタする** MUST — `21H2` を含むクエリでも `24H2` 行が上位に来得る（逆も）。基底の **Product GUID はこれらのリネームで不変**（§5.7）であり、だからこそ cab の GUID フィルタはどんなタイトル照合より堅牢です。

**実測による拡張（2026-08・r12シリーズ終端）。** r12 リバースエンジニアリング・シリーズ中に Catalog のさらなる挙動が2点実測され、終端で確認された。第一に、Catalog は Title と Classification の**表示文字列**をリクエスト文脈に応じてローカライズする（ドイツ語・フランス語・日本語ほかを観測）一方、Product 名・KB ID・update GUID・ファイル名は安定である — したがって英語表示テキストへの生一致は、上記の命名の罠に重なる第二の脆さとなる。頑健な照合は**セマンティック**でなければならない: 分類ごとの別名集合（ローカライズ形を含む）に加え、唯一の非曖昧行が残る場合に安定な同一性列をキーとする構造的フォールバックを備える。第二に、タイトル・ヒューリスティックの脆さというクラスへの構造的解答は、発見をコードではなく**宣言データ**にすることである: 終端実装は Kind ごとの検索プロファイル（クエリ戦略・タイトル許容/拒否制約・分類要件）を宣言ポリシーオブジェクトとして保持し、全ヒューリスティックが点検可能かつ宣言由来テストで保護され、その場しのぎの文字列述語の中に住まなくなる。

### 6.2 4つの面

`[CATALOG-VERIFIED 2026-06-24]`

| # | 面 | メソッド | 得られるもの |
|---|---|---|---|
| 1 | `Search.aspx?q=<query>` | GET | 結果表: (updateID GUID, title, products, classification, date, version, size) |
| 2 | `DownloadDialog.aspx` | POST `updateIDs=[{…"updateID":"<GUID>"}]` | 更新ごとのファイル一覧: fileName, **直接 CDN URL**, **digest (SHA-1 b64)**, sha256（多くは空） |
| 3 | `ScopedViewInline.aspx?updateid=<GUID>` | GET | supersedence（`n/a` = 最新）+ KB 記事番号（任意の確認ゲート） |
| 4 | Learn release-info `?accept=text/markdown` | GET | ビルドごとの現行 LCU KB（LCU の発見シード） |

`DownloadDialog.aspx` が実 URL + digest を得る **唯一** の方法です。レスポンスは埋め込み JS 代入を持つ HTML（`downloadInformation[i].files[n].url/digest/sha256/fileName`）で、`files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'` で照合します。`digest` は **SHA-1 base64**（信頼できる整合性値）、`sha256` は頻繁に空、`fileName` は同ファイルの 40-hex SHA-1 で終わります。1つの更新が **複数ファイル**を返し得ます（2025 LCU = 2; .NET ロールアップ = 複数 leaf）— 常に `files[n]` を反復してください。

### 6.2.1 Catalog はスクレイピングでなくデータモデル

Catalog を「スクレイピングする HTML サイト」と片付けたくなりますが、それは実際の成果を過小評価します。§6.2 の4つの面は独立したページではなく、単一の決定論的たどり方を持つ **解決可能なデータモデル**に合成され、そのたどり方を復元したこと *自体* がリバースエンジニアリングの成果です。設計文書として読むと、モデルは **3層**を持ちます。

**Figure 3 — Catalog のデータモデル（Identity / Artifact / Validation 層）。**

```
┌─ IDENTITY LAYER ────────────────────────────────────────────────┐
│  KB (article number)                                            │
│     │  Search.aspx?q=<KB>                                       │
│     ▼                                                           │
│  updateID (GUID)            ← the Catalog's per-row identity    │
└──────────────────────────────┬──────────────────────────────────┘
                               │  DownloadDialog.aspx (POST updateID)
┌─ ARTIFACT LAYER ─────────────▼──────────────────────────────────┐
│  files[]  →  { fileName, Digest (SHA-1 b64), sha256?, URL }     │
│     │                                                           │
│     ├─ URL     → direct CDN download                           │
│     └─ Digest  → the cross-source PRIMARY KEY ───────────┐      │
└──────────────────────────────────────────────────────────┼──────┘
                                                            │
┌─ VALIDATION LAYER ─────────────────────────────────────────▼─────┐
│  Digest  ==  [A] SOAP oracle Digest      → proves the artifact   │
│  Digest/RevisionId  ↔  [B] wsusscn2.cab  → proves applicability  │
└──────────────────────────────────────────────────────────────────┘
```

- **Identity 層** — 人間可読の KB を Catalog の `updateID`（GUID）に解決。3つの識別子が連れ立って動き、混同してはいけません：**KB**（論理更新ごとに安定）、**updateID**（行ごとの GUID かつ DownloadDialog の POST キー）、**Digest**（ファイルの SHA-1 base64）。
- **Artifact 層** — `updateID` を1つ以上のファイルに解決。各ファイルは直接 CDN **URL** と **Digest** を持つ。
- **Validation 層** — Digest は **3つの面すべてで共有されるプライマリキー**：同じ物理ファイルは SOAP・Catalog・`wsusscn2.cab` で同じ Digest を持つ。これで照合することで、Catalog の成果物が権威ファイルと等しいこと（`==` [A] オラクル Digest）を証明し、[B] cab が Catalog の持たない適用性/依存事実を供給できる。

この最後の層こそが Catalog を単なるスクレイピング対象でなく *検証可能* にします。Catalog をこの3層モデル（不透明な HTML でなく）として扱うことで、自律 resolver は **seed → KB → updateID → URL + Digest** を決定論的に算出し、その結果を Digest 等価で SOAP に対し *証明* できます（§6.4, §12.3）。

### 6.3 シードのみの解決（KB をハードコードしない）

`[CATALOG-VERIFIED 2026-06-24]` 設計目標は、将来の月が **KB を編集せずに**正しく解決されることです。OS ごとの唯一の入力は3項目の **seed**：

```
2016: { products:"Windows Server 2016",                    buildMajor:"14393", verToken: null  }
2019: { products:"Windows Server 2019",                    buildMajor:"17763", verToken: null  }
2022: { products:"Microsoft Server operating system-21H2", buildMajor:"20348", verToken:"21H2" }
2025: { products:"Microsoft Server Operating System-24H2", buildMajor:"26100", verToken:"24H2" }
```
その他すべて（KB, UID, URL, digest）は **発見**されます — シードのみの性質は、全 resolver を空キャッシュに対して実行し各 KB を同一に再発見することで証明済みです。レシピ：

- **LCU** — Learn release-info を取得；OS の `buildMajor` の最新マイナービルドを選ぶ → LCU KB；その KB で Catalog 検索；**Products で後フィルタ**；選んだ行を DownloadDialog（2025 = 2ファイルセット）。
- **SSU** — 2016: `"Servicing Stack Update Windows Server 2016"` を検索、最新を選び、LCU の **前に適用**。2019/2022: スタンドアロン無し（埋め込み）。2025: LCU 2ファイルセット中の非 LCU `.msu`（GA baseline `KB5043080`、checkpoint SSU を運ぶ）。
- **.NET CU** — OS ごとの .NET クエリを検索、Products で後フィルタ、x64 を保持；最新月の **superset ロールアップ**（runtime トークン最多）を選び；in-scope leaf = OS の in-media デフォルト runtime を `-ndp` タグで（2019 → `-ndp` タグ無し; 2022 → `-ndp48`; 2025 → `-ndp481`）。
- **SafeOS DU** — 2022/2025 のみ。判別は命名エラで異なる：**2025** はタイトル自体に "Safe OS Dynamic Update"；**2022** はタイトルが単に "Dynamic Update …"（Setup DU と同一）なので **Products** 列 "Windows Safe OS Dynamic Update" で曖昧性解消。x64 `.cab`；最新を選ぶ。

### 6.4 classic 対 UUP の結合 — 検証を誠実に保つ方法

`[CATALOG-VERIFIED 2026-06-24]` 最重要の照合事実：Catalog の `updateID` は、classic と UUP のパッケージングで [A] オラクルの UID と **異なる**関係を持ちます。

| line type | オラクルへの結合キー | digest の挙動 |
|---|---|---|
| classic LCU / .NET（`.msu`, 2016/2019/2022） | `updateID == オラクル UID`, + KB | 結合専用（`.msu` がオラクルの内側 `.cab` を *包む* ため SHA-1 が異なる） |
| UUP LCU（2025） | **KB + digest** | **digest 一致** |
| SafeOS DU `.cab`（2022/2025） | **KB + digest** | **digest 一致** |
| 2025 .NET（`.msu`） | KB + leaf KB | 結合専用 |

罠：UUP（2025）では Catalog `updateID` がオラクル UID と **異なる**（合成パイプラインが違う）ため、UID 等価の「検証」は不一致に見えます — 代わりに **KB + digest** で結合する必要があります。classic `.msu` ではラッパーの SHA-1 が内側 cab の SHA-1 *ではない*ことが想定挙動（「結合専用」）で、破損ではありません。

### 6.5 [C] の結論

[C] は §3 マトリクスのあらゆる軸で良好です：到達可能（HTTP, 認証不要）、機械可読（予測可能な HTML フォーム）、再現可能（全キャッシュ）、自律エージェント親和（シードのみ解決、通常の HTTP/regex）、網羅的（Dynamic Update 含む全ライン）、クロス検証可能。最後の性質が決定的で、最も強い形で言い直す価値があります：**Catalog は信用されているのではなく、SOAP 検証されている。** 解決された各ラインは、スキーマ非依存のキー **SHA-1 Digest** で [A] オラクルに照合済みです。Catalog とオラクルが同一物理ファイルを出すライン（UUP LCU, SafeOS DU `.cab`）では digest は **バイト同一**で、classic `.msu` ラッパーでは updateID+KB で結合が成立します。結果：**全4OSが全ラインで合格**（§12.3）。Catalog が本番ソースなのは、まさにその出力が権威プロトコルのそれと等しいと証明でき、なおかつエージェントが無人で到達・駆動できる唯一の面だからです。

---

# PART III — ISO のための横断的関心事

## 7. パッチライン × 世代マトリクス（統合ビュー）

`[VERIFIED]` §4〜§6 を束ねて — 各 OS が必要とするものと、選定した（Catalog）パイプラインでの出所：

| Line | 2016 | 2019 | 2022 | 2025 | 本番ソース |
|---|---|---|---|---|---|
| **LCU** | yes | yes | yes | yes（UUP, 2ファイル） | Catalog（KB は Learn 経由） |
| **SSU** | **スタンドアロン**（先に適用） | LCU 埋め込み | LCU 埋め込み | GA-baseline `.msu`（checkpoint） | Catalog |
| **.NET CU** | in-scope 無し（LCU 内） | rollup → non-NDP leaf | rollup → NDP48 leaf | rollup → NDP481 leaf | Catalog |
| **SafeOS DU** | none | none | yes（cab には無い） | yes（cab に同梱） | Catalog |

読み方：**LCU が全4OSの背骨**。**SSU の形はエラごとに変わる**（separate → embedded → checkpoint file）。**.NET の in-scope NDP は反転する**（2019 non-NDP → 2022 NDP48 → 2025 NDP481）ので決してハードコードしない。

**Dynamic Update 行がソース選定の決め手です。** Dynamic Update（SafeOS DU）は 2022 以降にのみ現れ、3つの面をきれいに分かちます。

```
wsusscn2.cab  →  Dynamic Update 無し（オフラインスキャンのスコープ外, §5.5）
MS-WSUSSS     →  Dynamic Update あり、ただしエージェントから到達不可
Catalog       →  Dynamic Update あり、かつ 認証不要で到達可能
```

ゆえに 2022/2025 の SafeOS DU — ISO が現に必要とするライン — について、Catalog は単に *1つの* ソースなのではなく、**そのデータを持つ唯一の到達可能な本番ソース**です。cab は Catalog への寄りを強い、SOAP は到達できません。この1行だけで、[B] を単独本番ソースから失格させ、[C] を確定させるのに十分です。Catalog は、オフライン cab が構造的に供給できない1行を含め、全ラインを一様に供給します。

### 7.1 マトリクスへの実測拡張（2026-08・r12シリーズ終端）

r12 シリーズ中に実測された2つの事実が、判定を変えることなく上のマトリクスを精緻化する。第一に、**Setup Dynamic Update の行は4つの Server 世代すべてに存在する** — uup 世代の OS だけではない: ライブ Catalog は 2016・2019・2022・2025 の各々に Setup DU を解決し、終端の OS 別構成はその行を保持する（2026-07/08 スナップショット値として KB5068794 / KB5068795 / KB5079518 / KB5095966。KB は月次で入れ替わり、世代ごとの存在が安定な主張である）。Setup DU は上で論じた SafeOS DU とは別系統であり、WinRE/Safe OS イメージではなくメディア上の Windows Setup 自身のソースを更新する。

第二に、パッケージの**親子配送メカニズムが実測で使用中**である: Line モデルは `ParentKbId` を持ち、Server 2022 の .NET CU 子（KB5101010 と KB5101005）はともに親 KB5102206 を宣言する — 結合親パッケージの子であり、解決は親行を経由する。実機4 VM の post-install 証跡は 2022 への子 KB 実装着荷を裏付ける。出荷された **SSU** が親子配送を使う事例は未検証のままである — 実測された唯一の 2016 スタンドアロン SSU は直接解決（`ParentKbId` は null）— よって本メカニズムは .NET 子については確認済み、SSU については未解決の問いに留まる。

## 8. Secure Boot（PCA2023）とメディア構造 — **DRAFT / 検証中**

> **⚠️ ステータス: DRAFT。** パッチメタデータの素材（§4〜§7, §12）と異なり、以下の Secure Boot・メディア構造の知見は **構造的に推論され部分的に観測されているが、本書の他所と同じメタデータ基準の水準ではまだ厳密に検証されていません**。先行調査から方向付けとして引き継いだもので、ビルド＆ブート検証ループを同じ厳密さで回し次第 **改訂されます**。§8 のすべてを `[DRAFT]` として扱ってください。

### 8.1 PCA2023 移行を一段落で `[DRAFT]`

2024 サイクルは、Windows ブートバイナリに署名する CA を **PCA2011**（`Microsoft Windows Production PCA 2011`）から **PCA2023**（`Windows UEFI CA 2023`）へローテートします。Stage 1（現在）：ファームウェア更新が PCA2023 をプラットフォームの DB へ段階的にプロビジョニング；両チェーンが受理される。Stage 2（告知済み、2026 後半以降）：更新済みプラットフォームで PCA2011 が DBX へ移り、以後ブートマネージャが PCA2011 のみで署名されたメディアは起動しなくなる。よって前方互換メディアは、PCA2011 がまだ受理される今日であっても **PCA2023 署名のブートバイナリ**を同梱しなければなりません。Microsoft のリファレンスは `Make2023BootableMedia.ps1`（KB5053484 / `microsoft/secureboot_objects` リポジトリ）— **リリースタグまたはコミットハッシュ + 関数名**で固定すること、内部バージョン文字列（陳腐化済み）で固定しないこと。

### 8.2 `_EX` 二重ステージングと世代非対称 `[DRAFT]`

仕組みは **`install.wim` 内の二重ステージング**：`\Windows\Boot\{EFI,Fonts,DVD}\` に加え、更新済みイメージは PCA2023 で再署名した同じバイナリを持つ `{EFI,Fonts,DVD}_EX\` 兄弟を運びます。計画すべき非対称：

| OS | GA install.wim の `EFI_EX` | LCU servicing 後 | 備考 |
|---|---|---|---|
| 2016 | ✗（LCU で合成） | EFI_EX ✓, Fonts_EX ✓, **DVD_EX ✗** | servicing 後も `efisys_EX.bin` のソース無し（open item） |
| 2019 | ✗（LCU で合成） | full `_EX` ✓ | ブートマネージャは 2016 とバイト同一 |
| 2022 | ✗（LCU で合成） | full `_EX` ✓ | — |
| 2025 | ✓（GA で同梱） | n/a | `_EX` 既存；パッチのみ必要 |

### 8.3 残しておく価値のある2つの検証上の落とし穴 `[DRAFT]`

- **`Get-AuthenticodeSignature` は *直近の* 署名者を報告し、トラストアンカーを報告しない。** PCA2023 検出には `X509Chain.Build()` でチェーンを再構築し、root/intermediate を thumbprint で確認する必要がある — 直近の発行者名に "PCA 2011" を含むバイナリでも別のチェーンになり得る（逆も）。
- **`boot.wim` は LCU で servicing されない。** WinPE は独自の servicing ライフサイクルを持つ縮小 OS で、LCU `.msu` を `boot.wim` に適用すると失敗（`0x80070032`）、ネスト CAB 経路でも LCU cab が失敗（`0x8007371b`、pseudo-locale メンバー欠落）。よって PCA2023 `_EX` コンテンツは、パッチ済み `boot.wim` でなく **servicing 済み `install.wim`** から得る。（マウントした `boot.wim` へファイルを *コピーする* ことは可能 — WinPE が拒むのは CBS パッケージトランザクション。）

### 8.4 検証の到達範囲 `[DRAFT]`

ビルド後チェックはブートテストより厳密に少ないことを証明し、レポートはそれを明言する必要があります。file-presence はレイアウトを、Authenticode-chain は署名者チェーンを、Hyper-V Gen2 ブートは仮想ファームウェアの受理を証明し、実 DB/DBX のトラスト判定を行使するのは **物理ハードウェア**だけです。署名者チェーン検証器の `Pass` は **必要だが十分ではなく**、いかなるファームウェアもメディアを受理することを証明しません。

### 8.5 実測アップデート（2026-08・r12シリーズ終端）— DRAFT 内の検証済みサブセット

r12 シリーズは本節が待っていたビルドループを実走し、実測されたサブセットを確定的に述べられるようになった。Server 2025 の PCA2023 署名ブートマネージャへの変換は、実 ja-jp メディア上で**完了・検証済み**である: 静的検証フェーズは 33/33 で合格し、5つの PCA2023 出力ターゲットすべてが有効だった。変換後メディアのルート `\bootmgr.efi` は **Microsoft のメディア変換設計により PCA2011 のまま**である — これは UEFI クリティカル・ブートパス上になく（ファームウェアは `\EFI\Boot\bootx64.efi` を起動する）、その PCA2011 チェーンは変換の欠陥ではない。

さらに4つの Server VM からの実機 post-install 証跡（2026-08）は、サービス済みメディアから構築した 2016・2022・2025 上で Secure Boot 2023 証明書ロールアウトが**ファームウェア変数に対して直接検証**されたことを示し、2019 は既知の監視乖離（レジストリのロールアウト状態が遅延する一方、直接のファームウェア変数検査は既に 2023 証明書セットを検証済み）を呈する — 保守的な証跡格付けはこれを糊塗してはならない。PCA2023 専用ファームウェア上のブート挙動は §8.4 の述べる別ゲートのテストのままであり、§8 の残余は `[DRAFT]` に留まる。

## 9. 解決から ISO へ

`[ソース/順序メタデータは VERIFIED; DISM 機構は標準的な servicing ガイダンス]` Catalog は OS ごとに、ファイル（直接 URL + SHA-1 digest）と、どれが in-scope かを与えます。消費の仕方：

1. **ダウンロード + 検証（MUST）。** 各ファイルは使用前に SHA-1 digest で検証する MUST；不一致はビルドを中止する MUST。
2. **適用順序（MUST）。** `install.wim` へオフラインで、順序は **SSU/baseline → LCU → .NET（in-scope leaf）→ SafeOS DU（WinRE へ）→ /Cleanup-Image → recapture → rebuild ISO** とする MUST。
   - 2016: スタンドアロン SSU（`KB5094141`）を LCU（`KB5094122`）の **前に**適用する MUST — SSU を飛ばすと `0x800f0823`。
   - 2019/2022: 結合 LCU（SSU 埋め込み）。
   - 2025: GA baseline（`KB5043080`, checkpoint SSU）が LCU（`KB5094125`）に先行する MUST。
   - .NET: in-scope leaf `.msu`（2019 `KB5087061` / 2022 `KB5087068` / 2025 `KB5087051`）を適用；leaf は OS デフォルト runtime **と** 3.5 を運ぶ。（3.5 が別の有効化ステップを要するかは open item。）
   - SafeOS DU（2022 `KB5094157` / 2025 `KB5094150`）：**WinRE / Safe OS** イメージ用の `.cab` — `install.wim` の OS でなく `winre.wim` に適用する MUST。

よって ISO ビルドは **抽象的にのみ2ソース取得**（すべて Catalog、cab/SOAP は検証）です。実際にはエージェントは全4ラインに対し **1つ** の本番ソース — Catalog — を呼びます。

### 9.1 WIM イメージ・メタデータの機構（実測・2026-08）

サービシングは `install.wim` イメージのメタデータの物語を、標準的な DISM ガイダンスが扱わない形で変える。r12 シリーズはこれをエンドツーエンドで実測した。明示的な置換注記とともに畳み込む3つの事実: (1) Windows Setup のエディション一覧と Explorer は、実測した Server 2016・2022 メディアで WIM IMAGE の **CREATIONTIME** 日付を表示する — サービシング変更を反映した LASTMODIFICATIONTIME はユーザーの見る表示を変えないため、最新に*見える*べきサービス済みイメージは CREATIONTIME の書き換えを要する。(2) WIMGAPI の書込パスは**その書き換えに信頼できない**: `WIMSetImageInformation` は試験メディア上で、要求した image-XML 値を**永続化しないまま成功を返す**ことが実測された（サイレント非永続化）。これは API 経由で日付を書く計画を置換する。信頼できる経路は WIM の **raw XML リソースの直接編集** — バイト長・エンコーディング・BOM・終端子・リソース記述子を保存し、整合性テーブルを常に再計算する — であり、WIMGAPI は再読検証のみに退く。(3) 生き残った読取/検証パスで API は形式に厳格である: 再直列化した Unicode XML は **UTF-16LE BOM を欠くと拒否される**（Win32 エラー 203）— API は Unicode XML ファイルのメモリ表現を要求しており、BOM を剥がすシリアライザで XML を往復させるツールには容易な罠である。

---

# PART IV — リファレンス実装（第三者再現性）

この Part は、上記の各主張を生成・検証・再現するために使った全スクリプトの **完全なソース**を埋め込みます。散文の可読性を保つため、それらは文書 **末尾**（Appendix A〜E）に配置しています。本セクションはその索引と実行レシピです。各ツールは単一ファイルで自己完結します。

## 10. 本番ツール — Microsoft Update Catalog `[C]`

相互運用可能な単一ファイルツール2本が §6 を実装します（同一アクション、同一 JSON 形、共有 `findings/` キャッシュ）。**完全なソース: Appendix A（Python）と Appendix B（PowerShell）。**

```
catalog_patchset.py            # Python 3 (stdlib のみ)
Resolve-CatalogPatchSet.ps1    # PowerShell 5.1+/7 (関数的移植)

actions:
  resolve    [2016 2019 2022 2025]   OS別 LCU/SSU/.NET/DU 解決（シードのみ、KB ハードコード無し）
  inventory  [2016 2019 2022 2025]   .NET CU 完全インベントリ（collect-don't-drop）
  verify     [2016 2019 2022 2025]   SOAP オラクルに対するクロスチェック（--oracle-dir / -OracleDir 要）
```
```bash
# Python
python3 catalog_patchset.py resolve 2016 2019 2022 2025 --cache findings
# PowerShell
pwsh ./Resolve-CatalogPatchSet.ps1 -Action resolve -Os 2016,2019,2022,2025 -CacheDir ./findings
```
両者は同じタグ（`search.<slug>.html`, `dl.<uid8>.html`, `scoped.<uid8>.html`, `learn.release-info.md`, `sizes.json`）にキャッシュし、相互にキャッシュ互換です — 第三者は一方を他方のキャッシュに対し再実行して同一結果を得られます。

## 11. 検証ツール — オラクル生成器 `[A]` とオフライン・クロスチェック `[B]`

これらは本番経路には使われず、**本番経路が正しいことを証明する**ために存在し、検証の主張を独立に再現できるよう埋め込んでいます。

- **`Invoke-WuProtocolSurvey.ps1`**（Appendix C）— per-OS `dataset/<os>.json` オラクルを生成した MS-WSUSSS SOAP サーベイツール。PowerShell 5.1, ja-JP、`sws` エンドポイントへ到達可能な Windows ホストを要する（＝**エージェントサンドボックスでは実行不可** — §4.1 のアクセスの壁の具体化）。匿名ハンドシェイク、`GetRevisionIdList` アンカーデルタ列挙、`GetUpdateData` の bundle/leaf 追跡、blob 解凍を行う。`Expand-FsCompressedBlob` と `ConvertFrom-WuUpdateSegment` を正準的な XML 処理テンプレートとして読むこと。
- **`wsusscn2_analyzer.py`**（Appendix D）と **`Resolve-Wsusscn2PatchSet.ps1`**（Appendix E）— オフライン cab アナライザ（スキーマ `wsusscn2-analysis/1.1`）。Master XML をストリーム（`lxml.iterparse` / `XmlReader`）し、4つの OS 別解決を cab から再現し、オラクルに対し `verify` し、cab が欠く1ライン（§5.5）のために Catalog の SafeOS-DU resolver（`safeos` / `-Action SafeOsDu`）を加える。

```bash
# cab アナライザ（オフライン・クロスチェック）
python3 wsusscn2_analyzer.py download
python3 wsusscn2_analyzer.py analyze --cab wsusscn2.cab --summary -o result.json
python3 wsusscn2_analyzer.py verify Server2025 --cab wsusscn2.cab --oracle Server2025.json
```

---

# PART V — 収集データと付録

## 12. 検証済みスナップショット（2026-06）— 主張の裏にある実データ

> これらは Patch Tuesday ごとに入れ替わります。(a) 散文を実値に錨付けし、(b) 読者がツールを健全性チェックできるよう掲載します。UID は GUID の先頭 8 hex、`digest` = SHA-1 base64。

### 12.1 [A] SOAP オラクル — OS別ハーベスト形 `[VERIFIED 2026-06]`

収集した `dataset/<os>.json` answer-key（実 `GetUpdateData` レスポンス）：

| OS | Records | Bundles | Live bundles | Newest LCU | Kinds |
|---|---|---|---|---|---|
| Server 2016 | 518 | 259 | 21 | KB5094122 | dotnet=81 LCU=73 SSU=51 other=313 |
| Server 2019 | 421 | 181 | 11 | KB5094123 | dotnet=82 LCU=56 SSU=23 other=260 |
| Server 2022 | 412 | 193 | 11 | KB5094128 | dotnet=40 LCU=116 other=256 |
| Server 2025 | 80 | 40 | 3 | KB5094125 | dotnet=18 LCU=22 other=40 |

オラクルからの実 Server 2025 レコード断片（抜粋）。leaf 埋め込みの SSU と SafeOS DU を示す：

```json
"Ssu":      { "Model":"uup-checkpoint-in-lcu-leaf", "Standalone":false, "Version":"26100.32985",
              "Files":[{"FileName":"SSU-26100.32985-x64-express.cab","Digest":"yGhWECaSjm//sYUWJoQRo8zVw8k=","Size":112422}] },
"SafeOsDu": { "Model":"co-bundled-in-lcu-leaf", "Standalone":false,
              "Files":[{"FileName":"Windows11.0-KB5094150-x64-baseless.psf","Digest":"ORXQbDk0YK5ZUpmeQLToGOg2CdA=","Size":332819650}] }
```

### 12.2 [B] cab スナップショット同一性 `[CAB-VERIFIED 2026-06-24]`

```
Download : https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab  (via aka fwlink 74689)
Size     : 649,341,212 bytes
SHA-256  : 5b075a6d9fdaa1751b8c70bf164531163e6750444e9100453f96dce3a4eec122
Master   : package.xml 114,221,784 B — 136,478 updates / 97,339 file-locations
Root     : <OfflineSyncPackage> / http://schemas.microsoft.com/msus/2004/02/OfflineSync ; CreationDate 2026-06-09
```

### 12.3 OS別の解決セット + 三者一致 `[VERIFIED + CAB-VERIFIED + CATALOG-VERIFIED, 2026-06]`

| OS | LCU | SSU | .NET (in-scope leaf) | SafeOS DU | オラクル照合 |
|---|---|---|---|---|---|
| 2016 | KB5094122 (`e0284a61…`, `.msu`) | KB5094141（スタンドアロン, 先に適用） | n/a（LCU 内） | n/a | **OVERALL ✓** |
| 2019 | KB5094123 (`786110c1…`) | LCU 埋め込み | KB5087061（non-NDP48） | n/a | **OVERALL ✓** |
| 2022 | KB5094128 (`522273b0…`) | LCU 埋め込み | KB5087068（NDP48） | cab には無い → Catalog **KB5094157** | **OVERALL ✓** |
| 2025 | KB5094125 (`c108488b…`, UUP) | 26100.32985（checkpoint） | KB5087051（NDP481） | KB5094150（cab 同梱 == Catalog） | **OVERALL ✓** |

ここでの **Digest はクロスソースのプライマリキー**：同じ物理ファイルが提供される所では、値が SOAP・Catalog・cab でバイト同一です。

**合格したクロスソース同一性チェック（無料の正しさシグナル）：**
- 2025 LCU: Catalog `updateID ≠ オラクル UID`（UUP として想定通り）だが **digest `jon6SRff…` は一致**。
- 2022 SafeOS DU KB5094157: Catalog 行の `updateID c6476311 == SOAP バンドル UID`、ダウンロードしたファイルの **SHA-1 `w+5dA…` と SHA-256 `1idumQ…` がオラクルと完全一致** — Catalog ファイルは暗号学的に、cab 解析が探していた当の成果物。
- 2025 SafeOS DU: Catalog のスタンドアロンファイルは cab 同梱の `…KB5094150-x64.cab`（digest `icy52…`）と **バイトサイズ同一**。
- Learn release-info の LCU/.NET KB が全4OSで解決 KB と一致（`CrossCheck.Match = true`）。

### 12.4 Catalog DownloadDialog レスポンス形（実例）`[CATALOG-VERIFIED 2026-06]`

```js
downloadInformation[0].files[0].url      = 'https://catalog.s.download.windowsupdate.com/.../windows10.0-kb5094122-x64_<sha1hex>.msu'
downloadInformation[0].files[0].digest   = 'Nr3Up4Pt5vYXS4++EEbo46YTrUQ='   // SHA-1, base64 (信頼できる)
downloadInformation[0].files[0].sha256   = ''                               // 頻繁に空 — 依存しない
downloadInformation[0].files[0].fileName = 'windows10.0-kb5094122-x64_<sha1hex>.msu'
```

## 13. 確信度・GUIDレジスタ・用語集・open items

### 13.1 確信度レベル

| 主張クラス | 確信度 | 根拠 |
|---|---|---|
| OS別 LCU/SSU/.NET 現行セット（2026-06） | **高** | 三者一致（オラクル + cab digest + Catalog digest） |
| SSU 三エラ・パッケージングモデル | **高** | 実 blob + cab から世代横断でデコード |
| `wsusscn2.cab` 構造（RevisionId, 3ストリーム, digest 結合） | **高** | 2026-06 cab の完全ストリーミングプロファイル |
| 2022 SafeOS DU の cab 不在 + 理由 | **高** | Master + 74 cab × 3 ストリーム + 2 エスカレーションを尽くした |
| Catalog シードのみ解決 | **高** | 空キャッシュ再発見、全4OSをオラクルに対し検証 |
| 適用時の .NET 3.5 有効化ステップ | **未解決** | 未確定；ビルドセッションの問い |
| §8 Secure Boot / `_EX` / ブート検証 | **DRAFT** | 構造的に推論、未だ厳密検証なし |

### 13.2 GUID レジスタ（唯一の持続的シード）

**Server LTSC Product GUID:** 2016 `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` · 2019 `f702a48c-919b-45d6-9aef-ca4248d50397` · 2022 `71718f13-7324-4b0f-8f9e-2ca9dc978e53`（一般; `97b08ca0-…` = Azure Edition） · 2025 `b256987d-4693-4c87-955d-dbb9341205eb`。
**Classification GUID:** SecurityUpdates `0FA1201D-4330-4FA8-8AE9-B877473B6441` · UpdateRollups `28BC880E-0592-4CBF-8F95-C79B17911D5F` · ServicePacks `68C5B0A3-D1A6-4553-AE49-01D3A7827828` · CriticalUpdates `E6CF1350-C01B-414D-A61F-263D14D133B4` · Updates `CD5FFD1E-E932-4E3A-BF74-18BF0B1BBD83`。
**EOS/ESU deny-list:** 2008 `ba0ae9cc-…` · 2008 R2 `fdfe8200-…` · 2012 `a105a108-…` · 2012 R2 `d31bd4c3-…`。
**2022 SafeOS DU カテゴリノード:** `e4b04398-adbd-4b69-93b9-477322331cd3`（+ `dd1aa213-…`）, DU-product `abc45868-…`。

### 13.3 用語集

**LCU** Latest Cumulative Update · **SSU** Servicing Stack Update · **.NET CU** .NET Framework 累積更新 · **DU** Dynamic Update（Setup DU と SafeOS DU）· **UUP** Unified Update Platform（2025 / Win11 24H2 の合成パイプライン）· **CompDB** Composition Database（UUP のビルドレベル適用性）· **CBS** Component-Based Servicing · **MSU/CAB/PSF** パッケージコンテナ形式 · **WIM** Windows Imaging Format（`install.wim`, `boot.wim`, `winre.wim`）· **WinRE / SafeOS** SafeOS DU が対象とする回復イメージ · **PCA2011 / PCA2023** ブートバイナリ署名 CA。

### 13.4 Open items

- §8 Secure Boot のエンドツーエンド・ビルド＆ブート検証（DRAFT → 検証済み）。
- DISM の .NET 3.5 適用性 / OS別の有効化ステップ。
- Server 2016 の `DVD_EX` / `efisys_EX.bin` の正準ソース。
- Catalog resolver の URL を実 ISO ビルダー（`Update-WindowsServerIso.ps1`）へ配線。

### 13.5 来歴（Provenance）

本書は3つのソース調査を統合します。各々が自己完結状態ファイル＋収集データセットとして引き継がれました：MS-WSUSSS SOAP サーベイ（オラクル）、`wsusscn2.cab` リバースエンジニアリング（オフライン・クロスチェック）、Microsoft Update Catalog 解決作業（本番ソース）。本文中の 2026-06 スナップショット値は日付付きの例で、埋め込みツール（Appendix A〜E）が実行のたびに現行セットを再発見します。

### 13.6 改訂履歴 `[STABLE]`

本書は living document です。構造は安定とみなします（今後の変更は再構成でなく内容であるべき）。

| リビジョン | 焦点 | 概要 |
|---|---|---|
| r1.x | 調査 | 初期のマルチサーフェス調査（SOAP / wsusscn2 / Catalog）、月次サイクルで事実収集。 |
| r2.0 | 改稿 | ゼロベース改稿；結論先出しの3ソース比較；Catalog を本番ソースに選定；全検証ツール埋め込み。 |
| r2.1 | 役割 | Authority/Production/Verification 三役モデル；7軸評価マトリクス；"Autonomous-Agent-Friendly"；Catalog をスクレイピングでなくデータモデルとして提示；SOAP 検証済みの強調。 |
| r2.2 | 洗練 | "Single Production Source"；本番ソースの定義を先出し；Digest をクロスソース・プライマリキーに；Identity/Artifact/Validation データモデル層；マトリクスに Decision 行；"Why we still needed SOAP"；研究対本番アーキテクチャの要約。 |
| r2.3 | ADR | リファレンスアーキテクチャ化；ADR 形式の決定（§3.1）；Stable/Snapshot 凡例；Abstract を圧縮；一行アーキテクチャチェーン；役割名を一次の指示対象に。 |
| r2.4 | 編集 | Non-goals（§1.1）；改訂履歴（本表）；図の識別子（Figure 1〜6）；RFC-2119 規範言語；1ページの "Architecture at a glance"（Figure 1）。最後の *構造* 改訂と宣言。 |

## 14. アーキテクチャ要約 — 研究フェーズ対本番フェーズ

調査全体は2つのアーキテクチャに収束します：本番ソースが信頼できることを *確立した* **研究/検証アーキテクチャ**と、以後 自律ビルドパイプラインが回す **本番アーキテクチャ**です。両者を分けることが、本書の主題を最も簡潔に1画面で述べたものになります。

**Figure 4 — 研究/検証アーキテクチャ**（source-of-truth 監査ごとに一度実行；正しさを確立）：

```
            ┌──────────────────────────────────────────────┐
            │  RESEARCH / VERIFICATION PHASE                │
            └──────────────────────────────────────────────┘

  MS-WSUSSS SOAP  ──(harvest on a Windows host)──►  dataset/<os>.json   [A] oracle
        │                                                    │
        │                                          ground-truth Digest
        ▼                                                    │
  Microsoft Update Catalog  ──(resolve seed→KB→updateID→file)│
        │                                                    │
        ▼                                                    ▼
     Catalog Digest  ═══════════ EQUAL? (Primary Key) ═══════╡  →  PROVEN
        │                                                    │
        ▼                                                    ▼
  wsusscn2.cab  ──(applicability / dependency / supersedence)┘   cross-check
```

**Figure 5 — 本番アーキテクチャ**（Patch Tuesday ごとに自律ビルドパイプラインが実行；証明済みソースのみ消費）：

```
            ┌──────────────────────────────────────────────┐
            │  PRODUCTION PHASE  (Single Production Source) │
            └──────────────────────────────────────────────┘

  Learn release-info  ──►  current LCU KB per build           (discovery seed)
        │
        ▼
  Microsoft Update Catalog  ──►  URL + SHA-1 Digest per line  (the ONE data dependency)
        │                         LCU · SSU · .NET · SafeOS DU
        ▼
  Download  ──►  verify SHA-1 against Digest
        │
        ▼
  DISM offline servicing   (SSU/baseline → LCU → .NET → SafeOS-DU→WinRE)
        │
        ▼
  PCA2023 _EX media synthesis   [DRAFT, §8]
        │
        ▼
  Rebuild ISO  ──►  patched, bootable Windows Server media
```

合わせて読むと：**研究アーキテクチャが Digest で Catalog が権威に等しいことを証明し**、**本番アーキテクチャは以後ちょうど1つのデータ依存**（Catalog）で済みます。Catalog が唯一の **単一本番ソース**だからです。SOAP と `wsusscn2.cab` は上の図にのみ現れます — 下の図を信頼できるものにしてから、そこから退場しました。この非対称こそが設計の全体です：*権威ある-が-到達不可な面で一度検証し、到達可能で-網羅的な面から永続的にビルドする。*

### 14.1 本書全体を一行で

読者が他の何も覚えなくても、このチェーンだけは覚えてください — これが本書のエンドツーエンドです。

**Figure 6 — 本書全体を一行で。**

```
   Research
      │
      ▼
   Authority source        (MS-WSUSSS SOAP)        — defines ground truth
      │   verifies, by Digest primary key
      ▼
   Verification source     (wsusscn2.cab)          — confirms applicability/dependency
      │   cross-checks
      ▼
   Production design       (Microsoft Update Catalog = Single Production Source)
      │   reachable · complete · proved
      ▼
   Autonomous Build Pipeline   (discover → resolve → download → verify → DISM)
      │
      ▼
   Offline Patched Windows Server ISO
```

続く Appendix は、まさにこのチェーンの **リファレンス実装**です — 本番ソースを実行可能コードとして（A〜B）、そしてそれを証明した権威/検証ソースを（C〜E）。アーキテクチャ *こそが* メッセージであり、コードはその証明です。

---

# Appendices — リファレンス実装ソース（全文）

> 以下のスクリプトは、第三者再現性のため逐語で埋め込んでいます。本書の各主張を生成・検証するために使った **完全な**ツールです。本番経路: Appendix **A〜B**（Catalog）。検証: Appendix **C**（SOAP オラクル生成器）、Appendix **D〜E**（オフライン cab クロスチェック）。コードは言語非依存のため英語のまま掲載しています。

## Appendix A — `catalog_patchset.py`（Catalog 本番 resolver, Python）

**役割:** 本番ソース `[C]`。Microsoft Update Catalog からの OS別 LCU/SSU/.NET/SafeOS-DU のシードのみ解決。`verify` は SOAP オラクルに対しクロスチェック。stdlib のみ。

```python
#!/usr/bin/env python3
"""catalog_patchset.py — single-file Microsoft Update Catalog patch-set tool for
Windows Server (2016/2019/2022/2025) patched-ISO building.

Consolidation of: catalog_lib + catalog_resolver + dotnet_inventory +
verify_against_oracle. See CATALOG-ANALYSIS-HANDOFF.md (BLOCK 0.T defines the
"in-box"/media-payload terminology; BLOCK J the endpoint model; BLOCK K the per-OS
resolvers; BLOCK L the .NET full inventory).

Subcommands (CLI):
  resolve   [2016 2019 2022 2025]   per-OS LCU/SSU/.NET/DU resolution (OS-seed only)
  inventory [2016 2019 2022 2025]   full .NET CU inventory (collect-don't-drop)
  verify    [2016 2019 2022 2025]   cross-check resolution vs the SOAP oracle

All Catalog responses are cached under findings/ (re-runs are offline/idempotent).
DownloadDialog yields each file's SHA1(b64) digest + URL without downloading; sizes
come from a HEAD Content-Length. Oracle verify reads local SOAP datasets (--oracle-dir).
"""
from __future__ import annotations
import argparse, csv, json, os, re, sys, time, urllib.parse, urllib.request

# ============================================================================
# SECTION 1 — Microsoft Update Catalog client  (was catalog_lib.py)
# ============================================================================
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")
SEARCH_URL = "https://www.catalog.update.microsoft.com/Search.aspx"
DOWNLOAD_URL = "https://www.catalog.update.microsoft.com/DownloadDialog.aspx"
SCOPED_URL = "https://www.catalog.update.microsoft.com/ScopedViewInline.aspx"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "findings")
os.makedirs(CACHE, exist_ok=True)

_GUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"


def _get(url: str, tag: str, force: bool = False) -> str:
    path = os.path.join(CACHE, tag)
    if os.path.exists(path) and not force:
        return open(path, encoding="utf-8", errors="replace").read()
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
    open(path, "w", encoding="utf-8").write(html)
    time.sleep(0.6)  # be polite to the Catalog
    return html


def _post(url: str, body: str, tag: str, force: bool = False) -> str:
    path = os.path.join(CACHE, tag)
    if os.path.exists(path) and not force:
        return open(path, encoding="utf-8", errors="replace").read()
    req = urllib.request.Request(url, data=body.encode("utf-8"),
                                 headers={"User-Agent": UA,
                                          "Content-Type": "application/x-www-form-urlencoded"})
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "replace")
    open(path, "w", encoding="utf-8").write(html)
    time.sleep(0.6)
    return html


def _txt(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s)).strip()


def search(query: str, force: bool = False) -> list[dict]:
    """Return result rows for a Catalog query (KB number or title text)."""
    tag = "search." + re.sub(r"[^A-Za-z0-9]+", "_", query)[:60] + ".html"
    html = _get(SEARCH_URL + "?q=" + urllib.parse.quote(query), tag, force)
    rows = []
    for m in re.finditer(r"id=['\"](%s)_link['\"][^>]*>(.*?)</a>" % _GUID, html, re.S | re.I):
        uid = m.group(1)
        title = _txt(m.group(2))
        cells = {}
        for col in range(0, 8):
            c = re.search(r'id="%s_C%d_R\d+"[^>]*>(.*?)</td>' % (re.escape(uid), col),
                          html, re.S | re.I)
            cells[col] = _txt(c.group(1)) if c else ""
        size_bytes = None
        mb = re.search(r"(\d{4,})", cells.get(6, ""))
        if mb:
            size_bytes = int(mb.group(1))
        rows.append({
            "uid": uid, "title": title or cells.get(1, ""),
            "products": cells.get(2, ""), "classification": cells.get(3, ""),
            "lastUpdated": cells.get(4, ""), "version": cells.get(5, ""),
            "sizeText": cells.get(6, ""), "sizeBytes": size_bytes,
        })
    return rows


def resolve(uid: str, force: bool = False) -> list[dict]:
    """POST DownloadDialog for a Catalog updateID -> list of files with digest."""
    body = ('updateIDs=[{"size":0,"languages":"","uidInfo":"%s","updateID":"%s"}]'
            "&updateIDsBlockedForImport=&wsusApiPresent=&contentImport="
            "&sku=&serverName=&ssl=&portNumber=&version=") % (uid, uid)
    tag = "dl." + uid[:8] + ".html"
    html = _post(DOWNLOAD_URL, body, tag, force)
    files = {}
    for k, idx, val in re.findall(
            r"downloadInformation\[\d+\]\.files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'", html):
        # k is the file index (group 1); idx is the field name (group 2)... fix below
        pass
    # robust per-file field capture
    out = {}
    for fidx, field, val in re.findall(
            r"files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'", html):
        out.setdefault(int(fidx), {})[field] = val
    files_list = []
    for i in sorted(out):
        f = out[i]
        files_list.append({
            "idx": i,
            "fileName": f.get("fileName", ""),
            "url": f.get("url", ""),
            "digest": f.get("digest", ""),   # SHA1 base64 of the distributed file
            "sha256": f.get("sha256", ""),
            "enTitle": f.get("enTitle", ""),
        })
    return files_list


def head_size(url: str, force: bool = False):
    """Content-Length of a download URL via a HEAD request (no body download).
    Cached in findings/sizes.json so re-runs are offline/idempotent."""
    cache = os.path.join(CACHE, "sizes.json")
    sizes = {}
    if os.path.exists(cache):
        try:
            sizes = json.load(open(cache))
        except Exception:
            sizes = {}
    if url in sizes and not force:
        return sizes[url]
    n = None
    try:
        req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
        r = urllib.request.urlopen(req, timeout=30)
        n = int(r.headers.get("Content-Length") or 0) or None
    except Exception:
        n = None
    sizes[url] = n
    json.dump(sizes, open(cache, "w"))
    time.sleep(0.3)
    return n


def scoped(uid: str, force: bool = False) -> dict:
    """Fetch the details page -> supersedence + KB + arch."""
    tag = "scoped." + uid[:8] + ".html"
    html = _get(SCOPED_URL + "?updateid=" + uid, tag, force)
    def grab(anchor):
        m = re.search(r'id="%s"[^>]*>(.*?)</div>' % anchor, html, re.S | re.I)
        return _txt(m.group(1)) if m else None
    superseded_by = grab("supersededbyInfo")
    supersedes = grab("supersedesInfo")
    kbs = re.search(r"KB article numbers:\s*</span>\s*([0-9,\s]+)", html)
    arch = re.search(r"architecture[^:]*:\s*</span>\s*([A-Za-z0-9 ,]+)", html, re.I)
    return {
        "uid": uid,
        "is_latest": (superseded_by is not None and superseded_by.lower().startswith("n/a")),
        "supersededByText": superseded_by,
        "supersedesText": supersedes,
        "kb": (kbs.group(1).strip() if kbs else None),
    }

# ============================================================================
# SECTION 2 — per-OS resolvers: LCU / SSU / .NET / SafeOS DU  (was catalog_resolver.py)
# ============================================================================
UA = UA
LEARN_RELEASE_INFO = ("https://learn.microsoft.com/en-us/windows/release-health/"
                      "windows-server-release-info?accept=text/markdown")

# OS identity: server Products-column token + Learn build-major + version token.
OS = {
    "2016": {"products": "Windows Server 2016",                          "buildMajor": "14393", "verToken": None},
    "2019": {"products": "Windows Server 2019",                          "buildMajor": "17763", "verToken": None},
    "2022": {"products": "Microsoft Server operating system-21H2",       "buildMajor": "20348", "verToken": "21H2"},
    "2025": {"products": "Microsoft Server Operating System-24H2",       "buildMajor": "26100", "verToken": "24H2"},
}


# ---------------------------------------------------------------- helpers ----
def learn_lcu_kbs() -> dict:
    """Parse Learn release-info markdown -> {buildMajor: (build, kb, date)} newest."""
    html = _get(LEARN_RELEASE_INFO, "learn.release-info.md")
    best = {}
    # rows like: | ... | <build like 26100.32995> | [KB5094125](...help/5094125) |
    for m in re.finditer(r"\|\s*(\d{5})\.(\d+)\s*\|\s*\[KB(\d+)\]", html):
        major, minor, kb = m.group(1), int(m.group(2)), m.group(3)
        cur = best.get(major)
        if cur is None or minor > cur[1]:
            best[major] = (f"{major}.{minor}", minor, "KB" + kb)
    return {k: (v[0], v[2]) for k, v in best.items()}


def _server_row(rows, products_token, arch_in_title="x64"):
    """Pick the x64 server row matching the Products token (case-insensitive)."""
    pt = products_token.lower()
    cands = [r for r in rows if pt in r["products"].lower()]
    # prefer the row whose title mentions x64 / the server brand, exclude client
    x = [r for r in cands if "x64" in r["title"].lower() or "x64" in r["sizeText"].lower()
         or "for x64" in r["title"].lower()]
    return (x or cands or [None])[0]


def _newest(rows):
    """Newest row by the YYYY-MM prefix in the title (LCU/.NET/DU titles start with it)."""
    def key(r):
        m = re.match(r"\s*(\d{4})-(\d{2})", r["title"])
        return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    return max(rows, key=key) if rows else None


def _runtime_count(title):
    return len(re.findall(r"\b\d+\.\d+(?:\.\d+)?\b", title))


def _line(kind, row, files, in_scope=None, note=""):
    return {
        "kind": kind,
        "kb": _kb_of(row["title"]) if row else None,
        "catalogUid": row["uid"] if row else None,
        "products": row["products"] if row else None,
        "title": row["title"] if row else None,
        "sizeBytes": row["sizeBytes"] if row else None,
        "files": files or [],
        "inScope": in_scope,
        "note": note,
    }


def _kb_of(text):
    m = re.search(r"KB(\d+)", text or "", re.I)
    return ("KB" + m.group(1)) if m else None


def _x64_rows(rows):
    """Keep server x64 rows; drop arm64/x86 variants (ISO target is x64)."""
    out = [r for r in rows if "arm64" not in r["title"].lower()
           and "x86" not in r["title"].lower()]
    pref = [r for r in out if "x64" in r["title"].lower()]
    return pref or out


# ---------------------------------------------------------------- LCU ---------
def _resolve_lcu(os_key):
    info = OS[os_key]
    lcus = learn_lcu_kbs()
    build_kb = lcus.get(info["buildMajor"])
    if not build_kb:
        return _line("LCU", None, [], note="LCU not discovered from Learn")
    build, kb = build_kb
    rows = search(kb)
    row = _server_row(rows, info["products"])
    files = resolve(row["uid"]) if row else []
    in_scope = {"build": build, "files": [f["fileName"] for f in files]}
    return _line("LCU", row, files, in_scope,
                 note=f"discovered via Learn (build {build})")


# ---------------------------------------------------------------- SSU ---------
def _resolve_ssu_2016():
    rows = search("Servicing Stack Update Windows Server 2016")
    cands = [r for r in rows if "Servicing Stack Update" in r["title"]
             and "Windows Server 2016" in r["products"]]
    row = _newest(cands)
    files = resolve(row["uid"]) if row else []
    return _line("SSU", row, files,
                 {"standalone": True, "files": [f["fileName"] for f in files]},
                 note="2016 only: standalone SSU row (apply before LCU)")


# ---------------------------------------------------------------- .NET --------
# "in-box" / "in-scope" = the .NET runtime whose PAYLOAD ships in the base install
# media (install.wim), per BLOCK 0.T of CATALOG-ANALYSIS-HANDOFF.md -- a MEDIA-PAYLOAD
# test, NOT a "default-enabled" test. (.NET 3.5 is default-DISABLED but in the media,
# so it IS in-box; the combined CU's in-scope base leaf already bundles 3.5 + the
# default runtime, so picking that one leaf patches 3.5 too.)
# The acquisition target per OS = the leaf for that OS's in-media default runtime:
#   2016 -> 3.5 + 4.6.2/4.7.x : serviced INSIDE the LCU, no standalone leaf to fetch
#   2019 -> 3.5 + 4.7.2       : base leaf, file has NO -ndpNN suffix (KB5087061)
#   2022 -> 3.5 + 4.8         : -ndp48 leaf (KB5087068)   [media ships 4.8]
#   2025 -> 3.5 + 4.8.1       : -ndp481 leaf (KB5087051)  [media ships 4.8.1]
# Out-of-scope add-on = a runtime NOT in the base media (e.g. 4.8 on 2016/2019).
_NET_INSCOPE = {
    "2019": lambda fn: ("-ndp48" not in fn and "-ndp481" not in fn),  # media default 4.7.2 (+3.5)
    "2022": lambda fn: "-ndp48" in fn and "-ndp481" not in fn,        # media default 4.8 (+3.5)
    "2025": lambda fn: "-ndp481" in fn,                               # media default 4.8.1 (+3.5)
}


def _resolve_net(os_key):
    info = OS[os_key]
    if os_key == "2016":
        return _line(".NET", None, [],
                     note="2016: in-box .NET payload (3.5 + 4.6.2/4.7.x; media-payload "
                          "def, BLOCK 0.T) is serviced INSIDE the LCU -- no standalone "
                          "in-box .NET package exists. The only standalone WS2016 .NET "
                          "CU is .NET 4.8 (KB5087065), an add-on NOT in base media -> "
                          "out-of-scope. No leaf to fetch (matches oracle).")
    token = info["products"]
    q = {
        "2019": "Cumulative Update for .NET Framework Windows Server 2019",
        "2022": "Cumulative Update for .NET Framework Microsoft server operating "
                "system version 21H2 x64",
        "2025": "Cumulative Update for .NET Framework 4.8.1 Microsoft server "
                "operating system version 24H2 x64",
    }[os_key]
    rows = [r for r in search(q) if token.lower() in r["products"].lower()]
    rows = _x64_rows(rows)
    nm = _newest(rows)
    if not nm:
        return _line(".NET", None, [], note="no .NET row matched OS token")
    month = re.match(r"\s*(\d{4}-\d{2})", nm["title"]).group(1)
    variants = [r for r in rows if r["title"].lstrip().startswith(month)]
    # superset rollup = most runtime versions enumerated in the title
    row = max(variants, key=lambda r: _runtime_count(r["title"]))
    files = resolve(row["uid"])
    x64 = [f for f in files if "-x64" in f["fileName"]]
    sel = [f for f in x64 if _NET_INSCOPE[os_key](f["fileName"])]
    return _line(".NET", row, files,
                 {"inScopeFiles": [f["fileName"] for f in sel],
                  "inScopeKb": [_kb_of(f["fileName"]) for f in sel]},
                 note=f"superset rollup; in-scope leaf = {os_key} in-media default "
                      f".NET runtime (media-payload def, BLOCK 0.T; bundles 3.5)")


# ------------------------------------------------------------- SafeOS DU ------
def _resolve_safeos_du(os_key):
    info = OS[os_key]
    if os_key in ("2016", "2019"):
        return _line("SafeOSDU", None, [],
                     note=f"{os_key}: no monthly SafeOS DU line (matches oracle)")
    tok = info["verToken"]
    # 2022 SafeOS DU ships a *classic* title ("Dynamic Update ...", no "Safe OS");
    # 2025 ships a *modern* title ("Safe OS Dynamic Update ..."). Both carry
    # "Safe OS Dynamic Update" in the Products column -> that is the discriminator.
    q = {
        "2022": "Dynamic Update Microsoft server operating system version 21H2",
        "2025": "Safe OS Dynamic Update for Microsoft server operating system "
                "version 24H2 x64",
    }[os_key]
    rows = search(q)
    cands = [r for r in rows
             if "Safe OS Dynamic Update" in r["products"]   # works for 21H2 & 24H2
             and tok in r["title"]
             and "server operating system" in r["title"].lower()
             and "arm64" not in r["title"].lower()]
    row = _newest(cands)
    files = resolve(row["uid"]) if row else []
    x64 = [f for f in files if "x64" in f["fileName"] and f["fileName"].endswith(".cab")]
    return _line("SafeOSDU", row, files,
                 {"files": [f["fileName"] for f in x64]},
                 note="Products has 'Safe OS Dynamic Update' + title version token")


# ----------------------------------------------------------- per-OS API -------
def resolve_2016():
    return {"os": "Server2016",
            "lines": [_resolve_lcu("2016"), _resolve_ssu_2016(),
                      _resolve_net("2016"), _resolve_safeos_du("2016")]}

def resolve_2019():
    return {"os": "Server2019",
            "lines": [_resolve_lcu("2019"),
                      _line("SSU", None, [], note="embedded in LCU (no standalone row)"),
                      _resolve_net("2019"), _resolve_safeos_du("2019")]}

def resolve_2022():
    return {"os": "Server2022",
            "lines": [_resolve_lcu("2022"),
                      _line("SSU", None, [], note="embedded in LCU (no standalone row)"),
                      _resolve_net("2022"), _resolve_safeos_du("2022")]}

def resolve_2025():
    lcu = _resolve_lcu("2025")
    # 2025 LCU DownloadDialog returns a 2-file set: the LCU itself + a GA baseline
    # that carries the checkpoint SSU. Identify the baseline WITHOUT hardcoding its KB:
    # it is the .msu in the set whose KB is NOT the discovered LCU KB.
    lcu_kb = (lcu.get("kb") or "").lower()
    baseline = [f for f in lcu["files"]
                if f["fileName"].lower().endswith(".msu")
                and (lcu_kb == "" or lcu_kb not in f["fileName"].lower())]
    bl_kb = _kb_of(baseline[0]["fileName"]) if baseline else None
    ssu = _line("SSU", None, baseline,
                {"files": [f["fileName"] for f in baseline]},
                note="2025: checkpoint SSU carried by the co-served GA baseline "
                     "(the non-LCU .msu in the 2-file set)")
    ssu["kb"] = bl_kb
    return {"os": "Server2025",
            "lines": [lcu, ssu, _resolve_net("2025"), _resolve_safeos_du("2025")]}


RESOLVERS = {"2016": resolve_2016, "2019": resolve_2019,
             "2022": resolve_2022, "2025": resolve_2025}

# ============================================================================
# SECTION 3 — .NET CU full inventory (collect-don't-drop)  (was dotnet_inventory.py)
# ============================================================================
ORACLE_DIR = "/home/claude/inspect/20260624-073249-WuProtocolSurvey/fs/dataset"

# Per-OS Catalog discovery query for the .NET CU (same tokens the resolver uses,
# but here we keep ALL newest-month variants, not just the superset).
_NET_QUERY = {
    "2016": "Cumulative Update for .NET Framework Windows Server 2016",
    "2019": "Cumulative Update for .NET Framework Windows Server 2019",
    "2022": "Cumulative Update for .NET Framework Microsoft server operating "
            "system version 21H2 x64",
    "2025": "Cumulative Update for .NET Framework 4.8.1 Microsoft server "
            "operating system version 24H2 x64",
}


def _oracle_net_leaves(os_name):
    """leafKB -> {'InScope':..., 'Scope':...} from the SOAP oracle CurrentSetLeaves."""
    out = {}
    try:
        d = json.load(open(os.path.join(ORACLE_DIR, os_name + ".json")))
    except FileNotFoundError:
        return out
    for l in d.get("CurrentSetLeaves", []):
        if l.get("Line") == "NET" and l.get("LeafKB"):
            out["KB" + str(l["LeafKB"])] = {
                "InScope": str(l.get("InScope")),
                "Scope": l.get("Scope"),
            }
    return out


def _ndp_and_runtime(filename, os_key):
    """Derive the NDP tag + a human runtime label from the leaf filename."""
    fn = filename.lower()
    if "-ndp481" in fn:
        return "ndp481", "4.8.1"
    if "-ndp48" in fn:
        return "ndp48", "4.8"
    # no NDP suffix = the base/in-box leaf (3.5 + the OS's shipping runtime)
    base = {"2016": "3.5 + 4.6.2/4.7.x", "2019": "3.5 + 4.7.2",
            "2022": "3.5 + 4.8", "2025": "3.5 + 4.8.1"}.get(os_key, "3.5 + base")
    return "none", base


def _arch(filename):
    fn = filename.lower()
    return ("arm64" if "arm64" in fn else "x86" if "-x86" in fn
            else "x64" if "-x64" in fn else "?")


def inventory(os_key):
    info = OS[os_key]
    oracle = _oracle_net_leaves("Server" + os_key)
    rows = search(_NET_QUERY[os_key])
    # server rows for this OS, x64, newest calendar month only
    if os_key in ("2016", "2019"):
        srv = [r for r in rows if ("Windows Server " + os_key) in r["products"]]
    else:
        srv = [r for r in rows if info["products"].lower() in r["products"].lower()]
    srv = _x64_rows(srv)
    nm = _newest(srv)
    bundles_out = []
    note = None
    if nm:
        month = re.match(r"\s*(\d{4}-\d{2})", nm["title"]).group(1)
        variants = [r for r in srv if r["title"].lstrip().startswith(month)]
        for b in sorted(variants, key=lambda r: -_runtime_count(r["title"])):
            leaves = []
            for f in resolve(b["uid"]):
                if _arch(f["fileName"]) != "x64":
                    continue
                lk = _kb_of(f["fileName"])
                ndp, runtime = _ndp_and_runtime(f["fileName"], os_key)
                orc = oracle.get(lk, {})
                leaves.append({
                    "leafKB": lk, "fileName": f["fileName"],
                    "ndpTag": ndp, "runtime": runtime, "arch": "x64",
                    "digest": f["digest"], "sha256": f.get("sha256", ""),
                    "sizeBytes": head_size(f["url"]),   # real .msu size via HEAD
                    "url": f["url"],
                    "oracleInScope": orc.get("InScope"),       # 'True'/'False'/None
                    "oracleScope": orc.get("Scope"),           # 'inbox'/'addon-out-of-scope'/None
                })
            bundles_out.append({
                "bundleKB": _kb_of(b["title"]), "bundleUid": b["uid"],
                "title": b["title"], "products": b["products"],
                "runtimeCountInTitle": _runtime_count(b["title"]),
                "sizeBytes": b["sizeBytes"], "leaves": leaves,
            })
    if os_key == "2016":
        note = ("2016: in-box .NET (3.5/4.6.2/4.7.x) is serviced INSIDE the LCU "
                "(KB5094122) — not published as a standalone .NET CU. The bundles "
                "listed here are the standalone .NET 4.8 CU (add-on; oracle marks it "
                "out-of-scope for a base image). Listed in full per the collect-don't-"
                "drop policy; the LCU separately covers in-box .NET.")
    return {"os": "Server" + os_key, "month": (month if nm else None),
            "bundles": bundles_out, "note": note}


def all_os():
    return {k: inventory(k) for k in ["2016", "2019", "2022", "2025"]}

# ============================================================================
# SECTION 4 — oracle (SOAP) cross-check  (was verify_against_oracle.py)
# ============================================================================
ORACLE_DIR = "/home/claude/inspect/20260624-073249-WuProtocolSurvey/fs/dataset"
# 2022 SafeOS DU is out-of-SOAP-scope; its digest is the Catalog/cab-verified value.
KNOWN_DU_DIGEST = {"2022": "w+5dA+5b36FoRspRo6sXEHEmC5Q="}

def oracle(n): return json.load(open(os.path.join(ORACLE_DIR, n + ".json")))

def bundle_uids(d):
    out = {}
    for c in d.get("CurrentSet", []):
        out.setdefault(c["Line"], set()).add(c["UpdateID"][:8])
    return out

def inscope_leaves(d):
    """line -> {leafKB:set, selfContainedDigests:set}"""
    out = {}
    for l in d.get("CurrentSetLeaves", []):
        if str(l.get("InScope")) not in ("True", "None"):  # keep True or unknown(2016)
            continue
        e = out.setdefault(l["Line"], {"leafKB": set(), "digests": set()})
        if l.get("LeafKB"): e["leafKB"].add("KB" + str(l["LeafKB"]))
        for f in (l.get("Files") or []):
            if f.get("PatchingType") == "SelfContained" and f.get("Digest"):
                e["digests"].add(f["Digest"])
            kb = re.search(r"kb(\d+)", f.get("FileName", ""), re.I)
            if kb: e["leafKB"].add("KB" + kb.group(1))
    # SafeOsDu (2025) lives in its own node
    sd = d.get("SafeOsDu") or {}
    if sd.get("Files"):
        e = out.setdefault("SafeOSDU", {"leafKB": set(), "digests": set()})
        for f in sd["Files"]:
            if f.get("FileName","").lower().endswith("x64.cab") and f.get("Digest"):
                e["digests"].add(f["Digest"])
    return out

def check(os_key, n):
    res = RESOLVERS[os_key]()
    uids = bundle_uids(oracle(n)); leaves = inscope_leaves(oracle(n))
    print(f"\n========== {res['os']} ==========")
    for ln in res["lines"]:
        kind = ln["kind"]; oline = "NET" if kind == ".NET" else ("SafeOSDU" if kind=="SafeOSDU" else kind)
        if not ln["kb"] and not ln["files"]:
            print(f"  [{kind:9}] (none) ✓  {ln['note'][:64]}"); continue
        chk = []
        # uid join
        ou = uids.get(oline, set())
        if ou and ln["catalogUid"]:
            chk.append("uid=" + ("MATCH" if ln["catalogUid"][:8] in ou else f"differs(orc {sorted(ou)})"))
        # in-scope leaf KB
        lk = leaves.get(oline, {}).get("leafKB", set())
        got_kb = {ln["kb"]} if ln["kb"] else set()
        if ln["inScope"]:
            got_kb |= set(re.search(r"kb\d+", f, re.I).group(0).upper()
                          for f in ln["inScope"].get("inScopeFiles", []) if re.search(r"kb\d+",f,re.I))
        if lk:
            chk.append("leafKB=" + ("OK" if (got_kb & lk) else f"DIFF(got {got_kb} orc {lk})"))
        # digest
        cat_dig = {f["digest"] for f in ln["files"] if f.get("digest")}
        exp = set(leaves.get(oline, {}).get("digests", set()))
        if os_key in KNOWN_DU_DIGEST and kind == "SafeOSDU":
            exp.add(KNOWN_DU_DIGEST[os_key])
        if exp:
            chk.append("digest=" + ("MATCH" if (cat_dig & exp)
                       else "join-only(.msu wraps oracle .cab)"))
        print(f"  [{kind:9}] KB={ln['kb']} uid={(ln['catalogUid'] or '-')[:8]}  " + "  ".join(chk))

# ============================================================================
# SECTION 5 — unified CLI
# ============================================================================
def _print_resolve(keys):
    out = {k: RESOLVERS[k]() for k in keys}
    print(json.dumps(out, ensure_ascii=False, indent=2))

def _print_inventory(keys):
    out = {k: inventory(k) for k in keys}
    print(json.dumps(out, ensure_ascii=False, indent=2))

def _print_verify(keys):
    names = {"2016":"Server2016","2019":"Server2019","2022":"Server2022","2025":"Server2025"}
    for k in keys:
        check(k, names[k])

def main(argv=None):
    p = argparse.ArgumentParser(description="Microsoft Update Catalog patch-set tool (Windows Server)")
    p.add_argument("action", choices=["resolve","inventory","verify"])
    p.add_argument("os", nargs="*", default=["2016","2019","2022","2025"],
                   help="OS keys (default: all four)")
    p.add_argument("--cache", help="cache dir (default: ./findings)")
    p.add_argument("--oracle-dir", help="SOAP oracle dataset dir (verify/inventory annotation)")
    a = p.parse_args(argv)
    global CACHE, ORACLE_DIR
    if a.cache:
        CACHE = a.cache; os.makedirs(CACHE, exist_ok=True)
    if a.oracle_dir:
        ORACLE_DIR = a.oracle_dir
    keys = [k for k in a.os if k in RESOLVERS] or ["2016","2019","2022","2025"]
    if a.action == "resolve":   _print_resolve(keys)
    elif a.action == "inventory": _print_inventory(keys)
    elif a.action == "verify":  _print_verify(keys)

if __name__ == "__main__":
    main()

```

## Appendix B — `Resolve-CatalogPatchSet.ps1`（Catalog 本番 resolver, PowerShell）

**役割:** 本番ソース `[C]`、Appendix A の関数的移植。PowerShell 5.1+/7；同一アクション・同一 JSON 形・共有 `findings/` キャッシュ。

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
  Microsoft Update Catalog patch-set tool for Windows Server (2016/2019/2022/2025)
  patched-ISO building. Functional PowerShell port of catalog_patchset.py.

.DESCRIPTION
  Three actions:
    resolve    per-OS LCU/SSU/.NET/DU resolution (OS-seed only; discovers KBs at run time)
    inventory  full .NET CU inventory (collect-don't-drop: every latest-month leaf, annotated)
    verify     cross-check the resolution against the SOAP oracle datasets

  Discovery: Microsoft Learn release-info markdown (LCU build-major -> OS) + Catalog
  title search (SSU/.NET/DU). Resolution: Search.aspx -> row -> DownloadDialog.aspx ->
  files (SHA1 b64 digest + URL, no download). Sizes via HEAD Content-Length.
  "in-box"/"in-scope" = media-payload/applicability (see CATALOG-ANALYSIS-HANDOFF.md
  BLOCK 0.T). in/out-of-scope is recorded as an ATTRIBUTE, never used to drop data
  in the inventory. All HTTP responses cache under -CacheDir (re-runs are idempotent).

.EXAMPLE
  pwsh ./Resolve-CatalogPatchSet.ps1 -Action resolve
  pwsh ./Resolve-CatalogPatchSet.ps1 -Action inventory -Os 2019,2022
  pwsh ./Resolve-CatalogPatchSet.ps1 -Action verify -OracleDir /path/to/dataset
#>
[CmdletBinding()]
param(
    [ValidateSet('resolve', 'inventory', 'verify')]
    [string]$Action = 'resolve',
    [string[]]$Os = @('2016', '2019', '2022', '2025'),
    [string]$CacheDir = (Join-Path $PSScriptRoot 'findings'),
    [string]$OracleDir,
    [int]$JsonDepth = 12
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# ============================================================================
# Constants
# ============================================================================
$script:UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$script:SEARCH_URL   = 'https://www.catalog.update.microsoft.com/Search.aspx'
$script:DOWNLOAD_URL = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'
$script:SCOPED_URL   = 'https://www.catalog.update.microsoft.com/ScopedViewInline.aspx'
$script:LEARN_RELEASE_INFO = 'https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown'
$script:CACHE = $CacheDir
$script:OracleDir = $OracleDir
if (-not (Test-Path $script:CACHE)) { New-Item -ItemType Directory -Path $script:CACHE -Force | Out-Null }

# server Products token + Learn build-major + version token, per OS
$script:OSDEF = @{
    '2016' = @{ products = 'Windows Server 2016';                    buildMajor = '14393'; verToken = $null }
    '2019' = @{ products = 'Windows Server 2019';                    buildMajor = '17763'; verToken = $null }
    '2022' = @{ products = 'Microsoft Server operating system-21H2'; buildMajor = '20348'; verToken = '21H2' }
    '2025' = @{ products = 'Microsoft Server Operating System-24H2'; buildMajor = '26100'; verToken = '24H2' }
}
$script:NET_QUERY = @{
    '2016' = 'Cumulative Update for .NET Framework Windows Server 2016'
    '2019' = 'Cumulative Update for .NET Framework Windows Server 2019'
    '2022' = 'Cumulative Update for .NET Framework Microsoft server operating system version 21H2 x64'
    '2025' = 'Cumulative Update for .NET Framework 4.8.1 Microsoft server operating system version 24H2 x64'
}
# 2022 SafeOS DU is out-of-SOAP-scope; digest is the Catalog/cab-verified value.
$script:KNOWN_DU_DIGEST = @{ '2022' = 'w+5dA+5b36FoRspRo6sXEHEmC5Q=' }

# ============================================================================
# SECTION 1 — Microsoft Update Catalog client
# ============================================================================
function Convert-HtmlToText {
    param([string]$s)
    if ($null -eq $s) { return '' }
    $s = [regex]::Replace($s, '<[^>]+>', ' ')
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    $s = [regex]::Replace($s, '\s+', ' ')
    return $s.Trim()
}

function Get-CatalogText {
    param([string]$Url, [string]$Tag)
    $p = Join-Path $script:CACHE $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -UserAgent $script:UA -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Invoke-CatalogPost {
    param([string]$Url, [string]$Body, [string]$Tag)
    $p = Join-Path $script:CACHE $Tag
    if (Test-Path $p) { return (Get-Content -LiteralPath $p -Raw) }
    $r = Invoke-WebRequest -Uri $Url -Method Post -Body $Body `
        -ContentType 'application/x-www-form-urlencoded' `
        -UserAgent $script:UA -UseBasicParsing -TimeoutSec 60
    $r.Content | Set-Content -LiteralPath $p -Encoding UTF8 -NoNewline
    Start-Sleep -Milliseconds 600
    return $r.Content
}

function Get-HeadSize {
    param([string]$Url)
    $cache = Join-Path $script:CACHE 'sizes.json'
    $sizes = @{}
    if (Test-Path $cache) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            foreach ($pr in $j.PSObject.Properties) { $sizes[$pr.Name] = $pr.Value }
        } catch { $sizes = @{} }
    }
    if ($sizes.ContainsKey($Url)) { return $sizes[$Url] }
    $n = $null
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -UserAgent $script:UA -UseBasicParsing -TimeoutSec 30
        $cl = $r.Headers['Content-Length']
        if ($cl) { $n = [long]($cl | Select-Object -First 1) }
    } catch { $n = $null }
    $sizes[$Url] = $n
    ($sizes | ConvertTo-Json -Compress) | Set-Content -LiteralPath $cache -Encoding UTF8
    Start-Sleep -Milliseconds 300
    return $n
}

function Search-Catalog {
    param([string]$Query)
    $slug = [regex]::Replace($Query, '[^A-Za-z0-9]+', '_')
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60) }
    $tag = "search.$slug.html"
    $html = Get-CatalogText ($script:SEARCH_URL + '?q=' + [uri]::EscapeDataString($Query)) $tag
    $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $rx = [regex]::new("id=['""]($guid)_link['""][^>]*>(.*?)</a>", 'Singleline,IgnoreCase')
    $rows = @()
    foreach ($m in $rx.Matches($html)) {
        $uid = $m.Groups[1].Value
        $title = Convert-HtmlToText $m.Groups[2].Value
        $cells = @{}
        for ($col = 0; $col -le 7; $col++) {
            $crx = [regex]::new(('id="' + [regex]::Escape($uid) + '_C' + $col + '_R\d+"[^>]*>(.*?)</td>'), 'Singleline,IgnoreCase')
            $cm = $crx.Match($html)
            if ($cm.Success) { $cells[$col] = Convert-HtmlToText $cm.Groups[1].Value } else { $cells[$col] = '' }
        }
        $size = $null
        $smb = [regex]::Match($cells[6], '(\d{4,})')
        if ($smb.Success) { $size = [long]$smb.Groups[1].Value }
        $titleOut = if ($title) { $title } else { $cells[1] }
        $rows += [pscustomobject]@{
            uid = $uid; title = $titleOut; products = $cells[2]; classification = $cells[3]
            lastUpdated = $cells[4]; version = $cells[5]; sizeText = $cells[6]; sizeBytes = $size
        }
    }
    return , $rows
}

function Resolve-CatalogDownload {
    param([string]$Uid)
    $body = 'updateIDs=[{"size":0,"languages":"","uidInfo":"' + $Uid + '","updateID":"' + $Uid + '"}]' +
            '&updateIDsBlockedForImport=&wsusApiPresent=&contentImport=&sku=&serverName=&ssl=&portNumber=&version='
    $tag = "dl.$($Uid.Substring(0,8)).html"
    $html = Invoke-CatalogPost $script:DOWNLOAD_URL $body $tag
    $files = @{}
    $rx = [regex]::new("files\[(\d+)\]\.(\w+)\s*=\s*'([^']*)'")
    foreach ($m in $rx.Matches($html)) {
        $i = [int]$m.Groups[1].Value; $field = $m.Groups[2].Value; $val = $m.Groups[3].Value
        if (-not $files.ContainsKey($i)) { $files[$i] = @{} }
        $files[$i][$field] = $val
    }
    $out = @()
    foreach ($i in ($files.Keys | Sort-Object)) {
        $f = $files[$i]
        $out += [pscustomobject]@{
            idx = $i
            fileName = $(if ($f.ContainsKey('fileName')) { $f['fileName'] } else { '' })
            url      = $(if ($f.ContainsKey('url'))      { $f['url'] }      else { '' })
            digest   = $(if ($f.ContainsKey('digest'))   { $f['digest'] }   else { '' })
            sha256   = $(if ($f.ContainsKey('sha256'))   { $f['sha256'] }   else { '' })
            enTitle  = $(if ($f.ContainsKey('enTitle'))  { $f['enTitle'] }  else { '' })
        }
    }
    return , $out
}

function Get-CatalogScoped {
    param([string]$Uid)
    $tag = "scoped.$($Uid.Substring(0,8)).html"
    $html = Get-CatalogText ($script:SCOPED_URL + '?updateid=' + $Uid) $tag
    function _grab([string]$anchor) {
        $m = [regex]::Match($html, ('id="' + $anchor + '"[^>]*>(.*?)</div>'), 'Singleline,IgnoreCase')
        if ($m.Success) { return (Convert-HtmlToText $m.Groups[1].Value) } else { return $null }
    }
    $supersededBy = _grab 'supersededbyInfo'
    $isLatest = ($null -ne $supersededBy) -and ($supersededBy.ToLower().StartsWith('n/a'))
    $kbm = [regex]::Match($html, 'KB article numbers:\s*</span>\s*([0-9,\s]+)')
    [pscustomobject]@{
        uid = $Uid; is_latest = $isLatest; supersededByText = $supersededBy
        kb = $(if ($kbm.Success) { $kbm.Groups[1].Value.Trim() } else { $null })
    }
}

# ============================================================================
# SECTION 2 — per-OS resolvers: LCU / SSU / .NET / SafeOS DU
# ============================================================================
function Get-LearnLcuKbs {
    $html = Get-CatalogText $script:LEARN_RELEASE_INFO 'learn.release-info.md'
    $best = @{}
    $rx = [regex]::new('\|\s*(\d{5})\.(\d+)\s*\|\s*\[KB(\d+)\]')
    foreach ($m in $rx.Matches($html)) {
        $major = $m.Groups[1].Value; $minor = [int]$m.Groups[2].Value; $kb = $m.Groups[3].Value
        if ((-not $best.ContainsKey($major)) -or ($minor -gt $best[$major].minor)) {
            $best[$major] = [pscustomobject]@{ build = "$major.$minor"; minor = $minor; kb = "KB$kb" }
        }
    }
    return $best
}

function Get-KbOf {
    param([string]$Text)
    $m = [regex]::Match(("$Text"), 'KB(\d+)', 'IgnoreCase')
    if ($m.Success) { return 'KB' + $m.Groups[1].Value } else { return $null }
}

function Get-X64Rows {
    param($Rows)
    $out = @($Rows | Where-Object { ($_.title.ToLower() -notmatch 'arm64') -and ($_.title.ToLower() -notmatch 'x86') })
    $pref = @($out | Where-Object { $_.title.ToLower() -match 'x64' })
    if ($pref.Count) { return , $pref } else { return , $out }
}

function Get-ServerRow {
    param($Rows, [string]$ProductsToken)
    $pt = $ProductsToken.ToLower()
    $cands = @($Rows | Where-Object { $_.products.ToLower().Contains($pt) })
    $x = @($cands | Where-Object { $_.title.ToLower().Contains('x64') -or $_.sizeText.ToLower().Contains('x64') })
    if ($x.Count) { return $x[0] }
    if ($cands.Count) { return $cands[0] }
    return $null
}

function Get-Newest {
    param($Rows)
    @($Rows) | Sort-Object @{ Expression = {
        $m = [regex]::Match($_.title, '\s*(\d{4})-(\d{2})')
        if ($m.Success) { [int]$m.Groups[1].Value * 100 + [int]$m.Groups[2].Value } else { 0 }
    } } -Descending | Select-Object -First 1
}

function Get-RuntimeCount {
    param([string]$Title)
    ([regex]::Matches($Title, '\b\d+\.\d+(\.\d+)?\b')).Count
}

function New-Line {
    param([string]$Kind, $Row, $Files, $InScope, [string]$Note)
    [pscustomobject]@{
        kind       = $Kind
        kb         = $(if ($Row) { Get-KbOf $Row.title } else { $null })
        catalogUid = $(if ($Row) { $Row.uid } else { $null })
        products   = $(if ($Row) { $Row.products } else { $null })
        title      = $(if ($Row) { $Row.title } else { $null })
        sizeBytes  = $(if ($Row) { $Row.sizeBytes } else { $null })
        files      = $(if ($Files) { @($Files) } else { @() })
        inScope    = $InScope
        note       = $Note
    }
}

function Resolve-Lcu {
    param([string]$OsKey)
    $info = $script:OSDEF[$OsKey]
    $lcus = Get-LearnLcuKbs
    $bk = $lcus[$info.buildMajor]
    if (-not $bk) { return (New-Line 'LCU' $null @() $null 'LCU not discovered from Learn') }
    $rows = Search-Catalog $bk.kb
    $row = Get-ServerRow $rows $info.products
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $inScope = [pscustomobject]@{ build = $bk.build; files = @($files | ForEach-Object { $_.fileName }) }
    return (New-Line 'LCU' $row $files $inScope ("discovered via Learn (build $($bk.build))"))
}

function Resolve-Ssu2016 {
    $rows = Search-Catalog 'Servicing Stack Update Windows Server 2016'
    $cands = @($rows | Where-Object { $_.title.Contains('Servicing Stack Update') -and $_.products.Contains('Windows Server 2016') })
    $row = Get-Newest $cands
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $inScope = [pscustomobject]@{ standalone = $true; files = @($files | ForEach-Object { $_.fileName }) }
    return (New-Line 'SSU' $row $files $inScope '2016 only: standalone SSU row (apply before LCU)')
}

# in-box / in-scope = the .NET runtime whose payload ships in the base media (BLOCK 0.T).
# Picks the leaf for the OS's default/shipping runtime; 3.5 rides bundled in that leaf.
function Test-NetInScope {
    param([string]$OsKey, [string]$FileName)
    switch ($OsKey) {
        '2019' { return (($FileName -notmatch '-ndp48') -and ($FileName -notmatch '-ndp481')) }  # base 4.7.2 (+3.5)
        '2022' { return (($FileName -match '-ndp48') -and ($FileName -notmatch '-ndp481')) }      # 4.8 (+3.5)
        '2025' { return ($FileName -match '-ndp481') }                                            # 4.8.1 (+3.5)
    }
    return $false
}

function Resolve-Net {
    param([string]$OsKey)
    $info = $script:OSDEF[$OsKey]
    if ($OsKey -eq '2016') {
        return (New-Line '.NET' $null @() $null ('2016: in-box .NET payload (3.5 + 4.6.2/4.7.x) is serviced INSIDE the LCU; ' +
                'the only standalone WS2016 .NET CU is .NET 4.8 (add-on, NOT in base media) -> out-of-scope. No leaf to fetch.'))
    }
    $q = $script:NET_QUERY[$OsKey]
    $rows = Search-Catalog $q
    $rows = @($rows | Where-Object { $_.products.ToLower().Contains($info.products.ToLower()) })
    $rows = Get-X64Rows $rows
    $nm = Get-Newest $rows
    if (-not $nm) { return (New-Line '.NET' $null @() $null 'no .NET row matched OS token') }
    $month = [regex]::Match($nm.title, '\s*(\d{4}-\d{2})').Groups[1].Value
    $variants = @($rows | Where-Object { $_.title.TrimStart().StartsWith($month) })
    $row = $variants | Sort-Object @{ Expression = { Get-RuntimeCount $_.title } } -Descending | Select-Object -First 1
    $files = Resolve-CatalogDownload $row.uid
    $x64 = @($files | Where-Object { $_.fileName -match '-x64' })
    $sel = @($x64 | Where-Object { Test-NetInScope $OsKey $_.fileName })
    $inScope = [pscustomobject]@{
        inScopeFiles = @($sel | ForEach-Object { $_.fileName })
        inScopeKb    = @($sel | ForEach-Object { Get-KbOf $_.fileName })
    }
    return (New-Line '.NET' $row $files $inScope ("superset rollup; in-scope leaf = $OsKey in-media default .NET runtime (BLOCK 0.T; bundles 3.5)"))
}

function Resolve-SafeOsDu {
    param([string]$OsKey)
    $info = $script:OSDEF[$OsKey]
    if ($OsKey -eq '2016' -or $OsKey -eq '2019') {
        return (New-Line 'SafeOSDU' $null @() $null "${OsKey}: no monthly SafeOS DU line (matches oracle)")
    }
    $tok = $info.verToken
    $q = if ($OsKey -eq '2022') { 'Dynamic Update Microsoft server operating system version 21H2' }
         else { 'Safe OS Dynamic Update for Microsoft server operating system version 24H2 x64' }
    $rows = Search-Catalog $q
    $cands = @($rows | Where-Object {
        $_.products.Contains('Safe OS Dynamic Update') -and
        $_.title.Contains($tok) -and
        $_.title.ToLower().Contains('server operating system') -and
        ($_.title.ToLower() -notmatch 'arm64')
    })
    $row = Get-Newest $cands
    $files = if ($row) { Resolve-CatalogDownload $row.uid } else { @() }
    $x64 = @($files | Where-Object { $_.fileName.Contains('x64') -and $_.fileName.EndsWith('.cab') })
    $inScope = [pscustomobject]@{ files = @($x64 | ForEach-Object { $_.fileName }) }
    return (New-Line 'SafeOSDU' $row $files $inScope "Products has 'Safe OS Dynamic Update' + title version token")
}

function Resolve-Os {
    param([string]$OsKey)
    switch ($OsKey) {
        '2016' { return [pscustomobject]@{ os = 'Server2016'; lines = @((Resolve-Lcu '2016'), (Resolve-Ssu2016), (Resolve-Net '2016'), (Resolve-SafeOsDu '2016')) } }
        '2019' { return [pscustomobject]@{ os = 'Server2019'; lines = @((Resolve-Lcu '2019'), (New-Line 'SSU' $null @() $null 'embedded in LCU (no standalone row)'), (Resolve-Net '2019'), (Resolve-SafeOsDu '2019')) } }
        '2022' { return [pscustomobject]@{ os = 'Server2022'; lines = @((Resolve-Lcu '2022'), (New-Line 'SSU' $null @() $null 'embedded in LCU (no standalone row)'), (Resolve-Net '2022'), (Resolve-SafeOsDu '2022')) } }
        '2025' {
            $lcu = Resolve-Lcu '2025'
            $lcuKb = if ($lcu.kb) { $lcu.kb.ToLower() } else { '' }
            $baseline = @($lcu.files | Where-Object {
                $_.fileName.ToLower().EndsWith('.msu') -and (($lcuKb -eq '') -or (-not $_.fileName.ToLower().Contains($lcuKb)))
            })
            $blKb = if ($baseline.Count) { Get-KbOf $baseline[0].fileName } else { $null }
            $ssu = New-Line 'SSU' $null $baseline ([pscustomobject]@{ files = @($baseline | ForEach-Object { $_.fileName }) }) `
                '2025: checkpoint SSU carried by the co-served GA baseline (the non-LCU .msu in the 2-file set)'
            $ssu.kb = $blKb
            return [pscustomobject]@{ os = 'Server2025'; lines = @($lcu, $ssu, (Resolve-Net '2025'), (Resolve-SafeOsDu '2025')) }
        }
    }
}

# ============================================================================
# SECTION 3 — .NET CU full inventory (collect-don't-drop)
# ============================================================================
function Get-OracleNetLeaves {
    param([string]$OsName)
    $out = @{}
    if (-not $script:OracleDir) { return $out }
    $p = Join-Path $script:OracleDir "$OsName.json"
    if (-not (Test-Path $p)) { return $out }
    $d = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
    foreach ($l in $d.CurrentSetLeaves) {
        if ($l.Line -eq 'NET' -and $l.LeafKB) {
            $out["KB$($l.LeafKB)"] = [pscustomobject]@{ InScope = "$($l.InScope)"; Scope = $l.Scope }
        }
    }
    return $out
}

function Get-NdpAndRuntime {
    param([string]$FileName, [string]$OsKey)
    $f = $FileName.ToLower()
    if ($f -match '-ndp481') { return @('ndp481', '4.8.1') }
    if ($f -match '-ndp48')  { return @('ndp48', '4.8') }
    $base = @{ '2016' = '3.5 + 4.6.2/4.7.x'; '2019' = '3.5 + 4.7.2'; '2022' = '3.5 + 4.8'; '2025' = '3.5 + 4.8.1' }[$OsKey]
    if (-not $base) { $base = '3.5 + base' }
    return @('none', $base)
}

function Get-LeafArch {
    param([string]$FileName)
    $f = $FileName.ToLower()
    if ($f -match 'arm64') { 'arm64' } elseif ($f -match '-x86') { 'x86' } elseif ($f -match '-x64') { 'x64' } else { '?' }
}

function Get-DotNetInventory {
    param([string]$OsKey)
    $info = $script:OSDEF[$OsKey]
    $oracle = Get-OracleNetLeaves ('Server' + $OsKey)
    $rows = Search-Catalog $script:NET_QUERY[$OsKey]
    if ($OsKey -eq '2016' -or $OsKey -eq '2019') {
        $srv = @($rows | Where-Object { $_.products.Contains("Windows Server $OsKey") })
    } else {
        $srv = @($rows | Where-Object { $_.products.ToLower().Contains($info.products.ToLower()) })
    }
    $srv = Get-X64Rows $srv
    $nm = Get-Newest $srv
    $bundles = @(); $note = $null; $month = $null
    if ($nm) {
        $month = [regex]::Match($nm.title, '\s*(\d{4}-\d{2})').Groups[1].Value
        $variants = @($srv | Where-Object { $_.title.TrimStart().StartsWith($month) } |
            Sort-Object @{ Expression = { Get-RuntimeCount $_.title } } -Descending)
        foreach ($b in $variants) {
            $leaves = @()
            foreach ($f in (Resolve-CatalogDownload $b.uid)) {
                if ((Get-LeafArch $f.fileName) -ne 'x64') { continue }
                $lk = Get-KbOf $f.fileName
                $nr = Get-NdpAndRuntime $f.fileName $OsKey
                $orc = $oracle[$lk]
                $leaves += [pscustomobject]@{
                    leafKB = $lk; fileName = $f.fileName; ndpTag = $nr[0]; runtime = $nr[1]; arch = 'x64'
                    digest = $f.digest; sha256 = $f.sha256; sizeBytes = (Get-HeadSize $f.url); url = $f.url
                    oracleInScope = $(if ($orc) { $orc.InScope } else { $null })
                    oracleScope   = $(if ($orc) { $orc.Scope } else { $null })
                }
            }
            $bundles += [pscustomobject]@{
                bundleKB = (Get-KbOf $b.title); bundleUid = $b.uid; title = $b.title; products = $b.products
                runtimeCountInTitle = (Get-RuntimeCount $b.title); sizeBytes = $b.sizeBytes; leaves = $leaves
            }
        }
    }
    if ($OsKey -eq '2016') {
        $note = '2016: in-box .NET (3.5/4.6.2/4.7.x) is serviced INSIDE the LCU (KB5094122) - not a standalone .NET CU. ' +
                'The bundle listed is the standalone .NET 4.8 add-on (oracle marks out-of-scope), kept in full per collect-dont-drop.'
    }
    return [pscustomobject]@{ os = ('Server' + $OsKey); month = $month; bundles = $bundles; note = $note }
}

# ============================================================================
# SECTION 4 — oracle (SOAP) cross-check
# ============================================================================
function _OracleDoc { param([string]$Name) Get-Content -LiteralPath (Join-Path $script:OracleDir "$Name.json") -Raw | ConvertFrom-Json }

function Get-BundleUids {
    param($D)
    $out = @{}
    foreach ($c in $D.CurrentSet) {
        if (-not $out.ContainsKey($c.Line)) { $out[$c.Line] = @() }
        $out[$c.Line] += $c.UpdateID.Substring(0, 8)
    }
    return $out
}

function Get-InScopeLeaves {
    param($D)
    $out = @{}
    foreach ($l in $D.CurrentSetLeaves) {
        $ins = "$($l.InScope)"
        if ($ins -ne 'True' -and $ins -ne '') { continue }   # keep True or unknown (2016)
        if (-not $out.ContainsKey($l.Line)) { $out[$l.Line] = [pscustomobject]@{ leafKB = @(); digests = @() } }
        if ($l.LeafKB) { $out[$l.Line].leafKB += ("KB$($l.LeafKB)") }
        foreach ($f in $l.Files) {
            if ($f.PatchingType -eq 'SelfContained' -and $f.Digest) { $out[$l.Line].digests += $f.Digest }
            $kbm = [regex]::Match($f.FileName, 'kb(\d+)', 'IgnoreCase')
            if ($kbm.Success) { $out[$l.Line].leafKB += ('KB' + $kbm.Groups[1].Value) }
        }
    }
    if ($D.SafeOsDu -and $D.SafeOsDu.Files) {
        if (-not $out.ContainsKey('SafeOSDU')) { $out['SafeOSDU'] = [pscustomobject]@{ leafKB = @(); digests = @() } }
        foreach ($f in $D.SafeOsDu.Files) {
            if ($f.FileName.ToLower().EndsWith('x64.cab') -and $f.Digest) { $out['SafeOSDU'].digests += $f.Digest }
        }
    }
    return $out
}

function Test-AgainstOracle {
    param([string]$OsKey, [string]$Name)
    $res = Resolve-Os $OsKey
    $d = _OracleDoc $Name
    $uids = Get-BundleUids $d
    $leaves = Get-InScopeLeaves $d
    Write-Host ""
    Write-Host ("========== $($res.os) ==========")
    foreach ($ln in $res.lines) {
        $kind = $ln.kind
        $oline = if ($kind -eq '.NET') { 'NET' } else { $kind }
        if (-not $ln.kb -and -not @($ln.files).Count) {
            Write-Host ("  [{0,-9}] (none) - {1}" -f $kind, ($ln.note.Substring(0, [Math]::Min(64, $ln.note.Length))))
            continue
        }
        $chk = @()
        $ou = if ($uids.ContainsKey($oline)) { $uids[$oline] } else { @() }
        if ($ou.Count -and $ln.catalogUid) {
            $cat = $ln.catalogUid.Substring(0, 8)
            $chk += "uid=" + $(if ($ou -contains $cat) { 'MATCH' } else { "differs(orc $($ou -join ','))" })
        }
        $lk = if ($leaves.ContainsKey($oline)) { @($leaves[$oline].leafKB) } else { @() }
        $gotKb = @(); if ($ln.kb) { $gotKb += $ln.kb }
        if ($ln.inScope -and $ln.inScope.PSObject.Properties['inScopeFiles']) {
            foreach ($fn in $ln.inScope.inScopeFiles) { $k = Get-KbOf $fn; if ($k) { $gotKb += $k } }
        }
        if ($lk.Count) {
            $hit = $false; foreach ($g in $gotKb) { if ($lk -contains $g) { $hit = $true } }
            $chk += "leafKB=" + $(if ($hit) { 'OK' } else { "DIFF(got $($gotKb -join ',') orc $($lk -join ','))" })
        }
        $catDig = @($ln.files | ForEach-Object { $_.digest } | Where-Object { $_ })
        $exp = @(); if ($leaves.ContainsKey($oline)) { $exp = @($leaves[$oline].digests) }
        if ($script:KNOWN_DU_DIGEST.ContainsKey($OsKey) -and $kind -eq 'SafeOSDU') { $exp += $script:KNOWN_DU_DIGEST[$OsKey] }
        if ($exp.Count) {
            $inter = $false; foreach ($cd in $catDig) { if ($exp -contains $cd) { $inter = $true } }
            $chk += "digest=" + $(if ($inter) { 'MATCH' } else { 'join-only(.msu wraps oracle .cab)' })
        }
        Write-Host ("  [{0,-9}] KB={1} uid={2}  {3}" -f $kind, $ln.kb, $(if ($ln.catalogUid) { $ln.catalogUid.Substring(0, 8) } else { '-' }), ($chk -join '  '))
    }
}

# ============================================================================
# SECTION 5 — dispatch
# ============================================================================
$osKeys = @($Os | Where-Object { $script:OSDEF.ContainsKey($_) })
if (-not $osKeys.Count) { $osKeys = @('2016', '2019', '2022', '2025') }
$names = @{ '2016' = 'Server2016'; '2019' = 'Server2019'; '2022' = 'Server2022'; '2025' = 'Server2025' }

switch ($Action) {
    'resolve' {
        $r = [ordered]@{}
        foreach ($k in $osKeys) { $r[$k] = Resolve-Os $k }
        $r | ConvertTo-Json -Depth $JsonDepth
    }
    'inventory' {
        $r = [ordered]@{}
        foreach ($k in $osKeys) { $r[$k] = Get-DotNetInventory $k }
        $r | ConvertTo-Json -Depth $JsonDepth
    }
    'verify' {
        if (-not $script:OracleDir) { Write-Error "verify requires -OracleDir (path to the SOAP oracle dataset JSONs)"; exit 2 }
        foreach ($k in $osKeys) { Test-AgainstOracle $k $names[$k] }
    }
}

```

## Appendix C — `Invoke-WuProtocolSurvey.ps1`（MS-WSUSSS SOAP オラクル生成器）

**役割:** 検証オラクル `[A]`。MS-WSUSSS SOAP プロトコル経由で per-OS `dataset/<os>.json` answer-key を生成。**`sws` エンドポイントへ到達可能な Windows ホストを要し、エージェントサンドボックスでは実行不可（§4.1 のアクセスの壁）。** `Expand-FsCompressedBlob` / `ConvertFrom-WuUpdateSegment` を正準的な XML 処理テンプレートとして読むこと。

```powershell
﻿#requires -Version 5.1
<#
.SYNOPSIS
  Windows Update Services PROTOCOL SURVEY -- single self-contained harness.

  ONE script, NO external dependencies (no dot-sourced libraries). One execution
  captures the COMPLETE observable surface of BOTH protocols as a single
  point-in-time static reference point:

      [MS-WUSP]   Windows Update Services: Client-Server Protocol
      [MS-WSUSSS] Windows Update Services: Server-Server Protocol

  Discipline (INVESTIGATION-STATE.md section 0.1) -- UNSCOPED observation-based RE:
    * method NOT pre-decided; ALL observable data acquired; NOTHING minimized.
    * every operation of BOTH protocols is probed; a fault(500/404) body is
      captured as DATA (it reveals the request shape the live server requires).
    * SyncUpdates (WUSP) walked with NO FilterCategoryIds; GetRevisionIdList
      (WSUSSS) walked with EMPTY Categories/Classifications -- the full unscoped
      catalog surface, including the server-side ceiling boundary.
    * one run folder, one CapturedUtc, one coverage manifest spanning both.

  Encoding: this file is ASCII-only, saved UTF-8 with BOM (ja-JP / CP932 safe;
  no console mojibake). All captured data files are written UTF-8 (no BOM).

  Run on a real Windows host (the sandbox cannot reach the MS endpoints):
      powershell -ExecutionPolicy Bypass -File .\Invoke-WuProtocolSurvey.ps1
  Then hand back the printed run folder (self-contained), zipped.

  CHANGELOG 2026-06-20 r2 (from the first live run):
    * WUSP handshake is ANONYMOUS: GetAuthorizationCookie (SimpleAuth) returns 404
      on the public front-end; GetCookie no longer depends on it. GetCookie now
      sends an anonymous AuthorizationCookie (PlugInId=Anonymous, empty CookieData),
      element namespace .../Server/ClientWebService, oldCookie nil, protocolVersion 1.8.
    * WUSP Client Web Service operations use the WSDL-declared namespace
      .../Server/ClientWebService (was bare .../SoftwareDistribution). GetConfig keeps
      the bare namespace (proven to return data live). ReportEventBatch uses the
      Reporting Web Service endpoint/action/namespace.
    * WSUSSS GetCookie drops the empty <oldCookie> element (it caused HTTP 500); the
      proven body is authCookies + protocolVersion 1.7 only.
    * GetRevisionIdList page 1 uses GetConfig=true to capture the full catalog config.
#>
[CmdletBinding()]
param(
    [ValidateSet('WindowsUpdate','MicrosoftUpdate','DcatFlighting')]
    [string]$Service = 'WindowsUpdate',
    [string]$WuspClientEndpoint,
    [string]$WuspSimpleAuthEndpoint,
    [string]$WsusssServerSyncEndpoint,
    [string]$WsusssDssAuthEndpoint,
    [string]$WuspProtocolVersion = '1.8',        # proven WUSP GetCookie wire version
    [int]$MaxRevPages   = 100,
    [int]$SampleSize    = 80,
    [string[]]$Locales  = @('en-US'),
    [switch]$OnlyWuaApi,
    [switch]$OnlyWsusssSoapApi,
    [switch]$OnlyWuspSoapApi,
    [switch]$FeasibilityStudy,
    [switch]$SampleData,
    [int]$HarvestSampleSize = 2000,
    [int]$FullEnumMaxRounds = 250,
    [int]$LeafDepthAcquireRounds = 8,
    [int]$LeafDepthSampleSize = 200,
    [switch]$IncludeWsusssReporting,
    [switch]$SkipSpecFetch,
    [switch]$SkipSls,
    [string]$Label
)

# ---- embedded version (printed to the log + written to 99.summary.json so the exact build is identifiable) ----
$SurveyVersion    = '1.13.49'
$SurveyBuildDate  = '2026-06-21'
$SurveyVersionTag = "WuProtocolSurvey/$SurveyVersion ($SurveyBuildDate)"
$SurveyChangeNote = 'r13.49 (harvest robustness: per-batch RETRY + failed-batch recording). The FULL-scope GetUpdateData harvest (B6) previously issued ONE GetUpdateData per batch and, on a transient SOAP failure, counted err and moved on -- permanently losing that batch of 100 records (observed once in an ~8h/200K run: batch 1845, 100 of 200,257 = 0.05 percent, a single transient blip near the end where server latency spiked). FIX: each batch now retries up to $hbMaxAttempts=3 (1 initial + 2 retries) with a 5s/10s backoff before counting err; a RECOVERED line is logged when a retry succeeds. Any batch that STILL fails after retries is recorded in $hbFailedBatches (Batch number, FirstUpdateID, Count, Reason=soap-fail-after-retry|parse) and surfaced in the harvest summary as FailedBatches[] -- so the exact lost UpdateIDs are known for a targeted re-fetch without diffing the enumeration. No change to the harvest record shape (still the 25-field per-OS-identical record from r13.47 case-X) or to any other path. Validated: AST OK, braces balanced, BOM + ASCII + pure CRLF; the retry loop was unit-tested (fail x2 then succeed -> RECOVERED on attempt 3; fail x3 -> err counted + FailedBatch recorded). r13.48 (Server2025 per-OS unit -- the fourth and final per-OS unit; grounded in the ACTUAL acquired data of this session, NOT any unverified markdown). ADDED Get-Server2025CurrentSet + Invoke-Server2025LeafFollow + a Server2025 dispatch case. Server2025 facts: ARCH = 2025 publishes x64 AND arm64; the ISO target is x64 only, so arm64 is skipped (a NEW axis vs 2016/2019/2022). LCU = Microsoft server operating system version 24H2 (KB5094125, build 26100.32995), x64. .NET = combined CU 3.5 and 4.8.1 (KB5087051), x64; in-box on 2025 is 4.8.1, so the WHOLE x64 .NET leaf is in scope (NO add-on split -- the inverse of 2019/2022). SSU = NO standalone line (UUP); the servicing stack ships as a checkpoint SSU-26100.xxxxx-x64 INSIDE the LCU leaf 16-file payload. DU = the SafeOS DU (Windows11.0-KB5094150-x64) is co-bundled in the SAME LCU leaf -- NO separate DU node/acquisition for 2025 (unlike the 2022 case-2). The leaf-follow follows the LCU leaf 3291c997 (the 16-file UUP mega-payload) and CLASSIFIES each file leaf-aware: SSU (name starts SSU-), SafeOS-DU (Windows11.0-KBnnn-x64 .cab/.psf), LCU vs GA (the .msu whose KB equals the parent LCU KB is the LCU, the other is the GA baseline -- durable, no hardcoded KB), LP-FoD (.wim), meta (AggregatedMetadata / DesktopDeployment / FodMetadata); the .NET leaf files are tagged NET. The dataset gains FIRST-CLASS Ssu (Model=uup-checkpoint-in-lcu-leaf, Standalone=false, Version, Role=servicing-stack prerequisite of the LCU, Files with Digest+Url, Provenance=wire:leaf-follow) and SafeOsDu (Model=co-bundled-in-lcu-leaf, Files) records, so the SSU and the SafeOS DU are recorded first-class (visible to dependency / apply-order analysis) even though they are leaf-embedded -- NOT buried among 16 anonymous files. SSU recording is done ONLY where the data actually EXISTS in the acquired wire data: 2025 (separate SSU-26100 files in the leaf, wire-grounded) and 2016 (standalone SSU bundle, already a current-set line); 2019/2022 have NO separate SSU entity in the acquired data (the SSU is inside the single LCU SelfContained .cab), so NO SSU record is fabricated for them -- per the user principle: record what the data shows, do not inject external knowledge. dataset gains Ssu / SafeOsDu / DuModelNote (null for the OSes that do not set them). 2016/2019/2022 are UNCHANGED. Validated: AST OK, braces balanced, BOM + ASCII + pure CRLF; the real Invoke-Server2025LeafFollow was unit-tested on the ACTUAL leaf 3291c997 GetUpdateData blob extracted from the raw covering capture of this session (16 files, all 16 URLs resolved; SSU = SSU-26100.32985-x64-express.cab + .psf, Version 26100.32985, url-resolved; SafeOS DU = 3 Windows11.0-KB5094150 files, url-resolved; LCU vs GA .msu correctly split). Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. r13.47 (IMPLEMENT the uniform DU-leak fix -- all design closed with the user). (1) FULL-SCOPE harvest = SHARED extractor: a new GLOBAL ConvertFrom-WuUpdateSegment (the per-record field build lifted verbatim from Get-FsMetadata) plus the hoisted Get-FsTypeGuess / Get-FsYm / Expand-FsCompressedBlob is now called by BOTH the WSUSSS GetUpdateData harvest (B6) AND the FS per-OS Get-FsMetadata, so the harvest record is the IDENTICAL 25-field shape as the per-OS dataset (parity by construction, the user CASE-X = same shape). The harvest now also decompresses XmlUpdateBlobCompressed (its own scratch dir, deleted after) so the ~14.4 percent (28,801 of 200,243) compressed component records that previously carried a NULL Title are recovered WITH Title + CatMembers + PrereqIds + BundledLeaf -- the full-scope dataset is now complete and node-membership-bearing, which doubles as the standing DETECTOR for any future DU-model change. FileDigests was added to the shared extractor output so neither path loses it (per-OS gains it too). (2) per-OS Server2022 DU = CASE 2 (impact localized): a SEPARATE DU sub-acquisition inside the Server2022 dispatch ONLY -- Get-FsCovering on the modern DU node(s) {e4b04398 [, dd1aa213]} (the covering pairs them with the 5 servicing classifications = the DU set) -> title-select the newest version-21H2 server SafeOS DU (skip 22H2 / Azure / Hotpatch / Preview / client; newest by KB number) -> DU leaf-follow (Get-FsMetadata on its BundledLeaf -> SafeOS cab + URL) -> the dataset gains DynamicUpdate. The MAIN 2022 covering {71718f13, 97b08ca0} is UNCHANGED; 2016 / 2019 / 2025 unchanged. The ~1017-candidate DU covering cost is inherent (the DU is not node-separable from client DU -- only title-separable) and is confined to the Server2022 case per the CASE-2 decision. (3) per-OS field parity = NO-OP: the per-OS dataset ALREADY persists CatMembers / PrereqIds / BundledLeaf / IsBundle / UpdateType / Products / SupersededIds per record (verified 412/412 on the real Server2022.json), so nothing was added there and FS runtime is unchanged (the 1-hour gate was moot). (4) 2025 future-DU risk = RECORDED only, NOT preemptively fixed (the user agreed -- implementing it today benefits no one): 2025 has NO standalone server DU now (the 200K harvest has ZERO Setup Dynamic Update titles and no version-24H2 server DU) and its SafeOS DU rides inside the LCU leaf (already covered by the b256987d covering), so adding e4b04398 to the 2025 covering now would only pull ~1017 unrelated client DU in for zero benefit. IF a standalone 2025 DU ever appears, the e4b04398 pattern (all 31 probed server+client DU sit under e4b04398, never the OS node) predicts it will leak from the b256987d covering exactly like 2022 -- and the harvest, now persisting CatMembers, will surface it WITHOUT a re-probe. Validated: AST OK, braces balanced, BOM + ASCII + pure CRLF; the shared extractor was PARITY-tested byte-IDENTICAL to the old Get-FsMetadata across all 32 real probe-bundle records (CatMembers / PrereqIds / Products / BundledLeaf / IsBundle / SupersededIds / Urls / Title / KB / UpdateType all 0-diff), and the refactored harvest loop was unit-tested on the real bundle response (rich 25-field records, CatMembers populated 32/32). r13.46 (DU-node FINDING recorded + temporary DU probe REMOVED -- per the user: after analysis, delete all temporary data-acquisition processing). The one-shot DU probe (r13.45) ran on the real host over a comprehensive 32-bundle DU sample and ANSWERED the node-membership question; its code (the opt-in switch, the FS-block probe branch, the embedded seed) is now fully removed and the per-OS path is back to the r13.44 shape. DURABLE FINDING (ground truth from the probe GetUpdateData, kept as the static reference for the upcoming uniform fix): a server Dynamic Update bundle has exactly TWO Prerequisites IsCategory groups -- a CLASSIFICATION group {e6cf1350 = Critical} and a PRODUCT group AtLeastOne{e4b04398-adbd-4b69-93b9-477322331cd3 [, dd1aa213-54e7-4173-8456-b278964a26b6]} (the two product GUIDs are OR-ed in ONE group; e4b04398 is present in ALL server DU, dd1aa213 only on newer ones, so e4b04398 alone covers). The DU is NOT linked to the OS product node (71718f13/97b08ca0 for 2022, b256987d for 2025) at all -- that is exactly why the 2022 covering {71718f13,97b08ca0}+{classifications} drops it (covering semantics: each IsCategory group needs a filter member; the DU PRODUCT group has neither 71718f13 nor 97b08ca0). e4b04398 is the modern (Win10-era/UUP) Dynamic Update category and is SHARED by client Win10/11 DU AND every server-OS DU generation (no-version + version 21H2 + version 22H2), so server-vs-client and generation are distinguishable ONLY by TITLE (version 21H2 = Server 2022), never by node. 2025 is DIFFERENT: KB5094125 (the 2025 LCU dep-anchor, node b256987d+Security) has NO DU category; its leaf 3291c997 carries the SafeOS DU (windows11.0-kb5094150-x64*.cab x3) as FILES inside the 16-file LCU payload, so the 2025 SafeOS DU is ALREADY covered by the existing 2025 LCU covering -- no separate DU node for 2025. 2016/2019 publish no server DU (none in the 200K harvest). Every server DU leaf carries its single SafeOS cab + URL (e.g. KB5094157 -> windows10.0-kb5094157-x64.cab). PLANNED UNIFORM FIX (NOT in this version -- to be implemented after the covering-cost decision): per-OS = for Server2022 only, add e4b04398 to the covering node set + a 2022 DU selector that picks the newest version-21H2 server SafeOS DU by title (skip 22H2/Azure/client/Preview) + a 2022 DU leaf-follow; 2016/2019 unchanged (no DU); 2025 DU rides in the LCU leaf (the future 2025 leaf-follow must keep all 16 files incl KB5094150). full-scope = persist each revision CatMembers (IsCategory product members) in the GetUpdateData harvest so node membership is recoverable without a probe. Validated: AST OK, braces balanced, BOM + ASCII; the per-OS path is the r13.44 logic (probe fully reverted). r13.44 (Server2022 per-OS design + implementation -- third per-OS unit, independent of 2016/2019, ground-truthed from the 2022 dataset + research doc 5.4 + Microsoft Learn). Server2022 diverges again -- the per-OS reasons: SSU: NO standalone SSU line (the dataset has ZERO standalone 2022 SSU); 2022 is combined, the servicing stack is the embedded SSU package (KB5094147) inside the LCU leaf, installerAssembly placeholder 6.0.0.0 (research doc 5.4). LCU: the general Server 2022 LCU is titled Microsoft server operating system version 21H2 (NOT Windows Server 2022); the SAME KB (KB5094128) also appears under the Windows Server 2022 Datacenter: Azure Edition SKU title, and the 2022 node carries 36 Azure Stack HCI hotpatch records -- the selector matches the 21H2 title and skips any title containing Azure / Hotpatch / Preview, so the general LCU is selected once (Azure Edition + HCI excluded). .NET: combined CU 3.5/4.8/4.8.1 (newest KB5088862) carrying TWO leaves -- in-box 3.5/4.8 (Windows10.0-KB5087068-x64-NDP48) and add-on 4.8.1 (Windows10.0-KB5087059-x64-NDP481); in-box on 2022 is 4.8, so the NDP48 leaf is IN SCOPE and the NDP481 leaf is the add-on -- the INVERSE of the 2019 rule (2019 in-box 4.7.2 makes NDP48 an add-on). ADDED. (1) Get-Server2022CurrentSet (2022-local): LCU (21H2 title, Azure/Hotpatch/Preview skipped) + .NET (combined CU, 21H2); NO SSU line. (2) Invoke-Server2022LeafFollow (derived from the 2019 leaf-follow with the .NET classification INVERTED): a .NET leaf whose file name carries NDP481 is addon-out-of-scope (4.8.1), every other leaf (NDP48 / 3.5) is inbox; NDP481 is tested before NDP48 because it contains NDP48 as a substring. (3) dispatch gains a Server2022 case; the dataset gains LcuScopeNote (Azure Edition / HCI exclusion) alongside SsuModelNote + DotNetScopeNote. The generic leaf-aware cross-check is unchanged and now covers 2022 too (LCU + the in-box .NET leaf KB5087068). 2025 remains untouched (own unit later: UUP, bundled-file SSU, in-box 4.8.1). Run 2016 + 2019 + 2022 together: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; Get-Server2022CurrentSet was unit-tested on the real Server2022 dataset (expect LCU KB5094128 + .NET KB5088862, NO SSU, Azure Edition + HCI excluded), the inverted NDP481-vs-NDP48 leaf classification on mock leaves, and the leaf-aware cross-check (in-box leaf KB5087068 -> MATCH in the Learn 2022 .NET set). r13.43 (Server2019 per-OS design + implementation -- second per-OS unit, independent of Server2016, ground-truthed from the 2019 dataset + research doc windows-server-iso-update-mechanics.en.md 5.4 + Microsoft Learn). Server2019 differs structurally from 2016 on BOTH the SSU and the .NET axis -- exactly why the design is per-OS. SSU: 2019 has NO standalone SSU line -- it is COMBINED, the servicing stack ships as the embedded selfUpdate/permanent package (KB5094143) inside the LCU leaf (research doc 5.4, SOAP-verified 2026-06); the standalone 2019 SSU is frozen at KB5005112 (2021-08) and superseded, so it is not selected. .NET: unlike 2016 (in-box .NET rides in the LCU), 2019 publishes a COMBINED .NET CU bundle 3.5/4.7.2/4.8 (newest KB5088864, 2026-05) carrying TWO leaves -- the in-box 3.5/4.7.2 payload (Windows10.0-KB5087061-x64) AND the add-on 4.8 payload (Windows10.0-KB5087066-x64-NDP48); the in-box runtime on 2019 is 4.7.2, so the bundle is SELECTED but only its in-box (non-NDP48) leaf is in scope. KB5087061/KB5087066 are LEAVES of the bundle, not standalone records -- the Learn dotnet page lists those leaf KBs while the catalog has the single bundle KB5088864. ADDED. (1) Get-Server2019CurrentSet (2019-local patterns): LCU (Cumulative Update for Windows Server 2019, newest, Preview skipped) + .NET (the combined CU bundle, newest, Preview skipped); NO SSU line. (2) Invoke-Server2019LeafFollow (derived from the 2016 leaf-follow + per-OS leaf classification): follows the LCU leaf (which carries the embedded SSU) and the .NET bundle leaves, tagging each with LeafKB (from the file name) + Scope -- a .NET leaf whose file name carries NDP48/NDP481 is addon-out-of-scope (4.8/4.8.1), the non-NDP48 .NET leaf is inbox (3.5/4.7.2), the LCU leaf is lcu-inbox; InScope derived. (3) dispatch gains a Server2019 case; the dataset gains SsuModelNote + a 2019 DotNetScopeNote recording the embedded-SSU and combined-CU-in-box-leaf-only decisions (visible rationale, not a silent drop). (4) the generic Learn cross-check now takes the leaves and, for the .NET row, prefers the IN-BOX leaf KB (KB5087061) over the bundle KB so the membership test compares against the leaf KBs Learn actually lists; the console leaf line flags the out-of-scope addon leaf. 2016 is unchanged (no NET line, so its cross-check path is identical). 2022/2025 remain untouched (own units later: 2022 in-box 4.8 + combined SSU + possible Azure Stack HCI exclusion; 2025 UUP). Run BOTH 2016 + 2019 together: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; Get-Server2019CurrentSet was unit-tested on the real Server2019 dataset (expect LCU KB5094123 + .NET KB5088864, NO SSU), the leaf Scope/LeafKB classification on mock NDP48 vs non-NDP48 leaves, and the leaf-aware cross-check (in-box leaf KB5087061 -> MATCH in the Learn 2019 .NET set). r13.42 (Server2016 .NET SCOPE CORRECTION -- triangulated #1 live analysis + #2 research doc windows-server-iso-update-mechanics.en.md section 2.2 + #3 INVESTIGATION-STATE 17.7.3, then confirmed with the user; in-box-only policy chosen). FINDING (all three sources agree): for Server2016 the in-box .NET runtimes (3.5 / 4.6.2 / 4.7.x) are serviced BY the OS LCU itself -- the dotnet release-notes lists that .NET row under the OS-LCU KB (2026-04 KB5082198 and 2026-05 KB5087537 both equal that month OS LCU; both verified equal to our dataset OS-LCU history), the title carries no .NET Framework token (the different-umbrella sibling the research doc warns about), and our dataset has ZERO standalone .NET 3.5/4.6.2/4.7.x records -- so there is no separate in-box .NET package; only the .NET 4.8 CU (KB5087065) is a standalone package, and 4.8 is an ADD-ON that is NOT pre-installed (Server2016 in-box is 4.6.2, Microsoft-confirmed). DECISION (user, option A): patch the pre-installed runtime only -> .NET 4.8 is OUT OF SCOPE for Server2016. CHANGES. (1) Get-Server2016CurrentSet no longer selects a .NET line: the NET48 pattern/line is removed, so the current set is exactly SSU + LCU (the LCU carries the in-box .NET). The LCU title pattern does NOT match the .NET 4.8 title, so 4.8 is cleanly dropped, not mis-bucketed. (2) The per-OS dataset gains DotNetScopeNote recording that in-box .NET rides in the LCU and 4.8 is excluded as a not-preinstalled add-on (visible rationale, not a silent drop). (3) Invoke-LearnCrossCheck now emits the LCU row for every OS but the .NET row ONLY when the current set carries a standalone .NET line -- so Server2016 cross-checks LCU only; the .NET membership test is retained for OSes that will have an in-scope standalone .NET line (e.g. Server2019 in-box 4.7.2 looks like a separate KB5087061 package -- to be handled in its own per-OS unit). This is exactly the per-OS divergence the design anticipated. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the corrected Server2016 selector (expect SSU KB5094141 + LCU KB5094122 x2 = 3 identities, NO .NET) and the LCU-only cross-check were unit-tested on the real Server2016 dataset + live Learn markdown. r13.41 (step 4 -- Microsoft Learn cross-check, implemented as a GENERIC OS-independent unit per the user direction, reusing the proven parser logic from usui-tk/ai-generated-artifacts Update-WindowsServerIso.ps1 rather than rewriting from zero). Microsoft Learn publishes a uniform structure across OSes, so unlike the current-set selector and leaf-follow (which are per-OS), the cross-check is intentionally generic. Scope confirmed with the user: LCU and .NET only (SSU has no Learn-markdown table). Adapted functions (the reference on-disk cache / Write-* / Save-CanonicalJsonFile machinery is dropped for a lean in-memory fetch): Get-LearnMarkdown (Invoke-WebRequest with ?accept=text/markdown), Split-LearnTableRow / Test-LearnTableSeparator / ConvertFrom-LearnKbCell / ConvertFrom-LearnReleaseInfoLcu (LCU history -> newest LCU KB per OS, from windows-server-release-info), and Split-LearnDotNetFrontMatter / ConvertFrom-LearnDotNetIndexMarkdown / ConvertFrom-LearnDotNetOsLabel / ConvertFrom-LearnDotNetMarkdown / Get-LearnDotNetLatestByOs (the dotnet release-notes index -> newest month pages -> per-OS .NET KBs). Invoke-LearnCrossCheck compares our current-set KBs against Learn: LCU is a direct equality (one LCU per OS); .NET is a MEMBERSHIP test (our .NET KB must appear among the Learn .NET KBs for that OS on the newest page), because an OS lists multiple .NET rows -- e.g. Server2016 publishes BOTH KB5087537 (3.5/4.7.2 rollup) AND KB5087065 (4.8), and our current set targets 4.8, so equality against the first row would wrongly fail. Output: the per-OS dataset gains CrossCheck (per line: OurKB, LearnKB(s), Match, LearnDate, Source); console prints a LEARN CROSS-CHECK line per OS. The cross-check runs for whichever OS has a current set (today Server2016 only) and is wrapped in try/catch so a Learn outage never breaks the run. Validated on the live Learn markdown: all four OS LCUs parse to the correct 2026-06 KBs (Server2016 KB5094122 matches our current set), and Server2016 .NET KB5087065 is found in the Learn newest .NET set [KB5087537, KB5087065] -> MATCH. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the Learn LCU + .NET parsers and the compare were unit-tested on the real release-info and dotnet release-notes markdown. r13.40 (FIX the Server2016 leaf-follow returning 0 files for the LCU leaves -- found on the live r13.39 run). The r13.39 run resolved all four Server2016 leaves but the two LCU leaves came back files=0/urls=0 while SSU=3 and .NET=1 worked. Root cause, confirmed by decompressing the captured leaf-follow response (fs/raw.Server2016.leaffollow.b0.xml): the <Files> section sits at the very END of the update blob, AFTER the ApplicabilityRules. For the LCU the decompressed blob is ~68 MB (Files at offset ~68.1M), so the 2 MB head read (correct and necessary for the covering harvest at scale) missed Files entirely; SSU (~617 KB) and .NET (~207 KB) are small enough that Files fell inside the 2 MB head, which is why only they worked. FIX: Expand-FsCompressedBlob gains an optional -TailBytes; when set it returns the 2 MB head (Title + Prerequisites, which live at the top) PLUS the last -TailBytes (the Files section, which lives at the bottom), read memory-safely (UTF-16-aligned tail seek, no full 68 MB load). ONLY the Server2016 leaf-follow passes -TailBytes (262144 = 256 KB, ample margin over the few-KB Files section); the covering harvest path is unchanged (head-only). Verified on the captured leaf response: LCU KB5094122 now yields windows10.0-kb5094122-x64.cab (~1.83 GB, SelfContained) plus the Express .cab + .psf delta files on the rev201 identity (rev200 carries just the SelfContained .cab), .NET KB5087065 the NDP48 .cab, SSU KB5094141 its cab/express/psf -- and every file digest resolves to a download URL via the response ServerSyncUrlData. NOTE the dual-identity is now meaningful: the two KB5094122 leaves differ (rev200 = SelfContained only; rev201 = SelfContained + Express + PSF), so the de-dup must keep the SelfContained .cab (the offline-servicing payload) -- a step-4 / apply-set detail. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the head+tail decompress + Files extraction was re-verified by decompressing the real LCU/SSU/.NET leaf blobs and confirming the files and URL joins. r13.39 (Server2016-ONLY leaf-follow -- step 3 dependency confirmation for Server2016 only; the additional dataset narrowed to the Server2016 current set). Adds ONE per-OS unit, Invoke-Server2016LeafFollow, called ONLY in the Server2016 dispatch case (2019/2022/2025 untouched, each gets its own leaf-follow later). For each Server2016 current-set bundle (SSU KB5094141 / LCU KB5094122 x2 / .NET 4.8 KB5087065) it takes the BundledLeaf (UpdateID + RevisionNumber, deduped) and issues GetUpdateData on the leaf using the SAME proven wire call as the covering harvest (Invoke-SoapCapture, NsSDS/GetUpdateData, the FS cookie), then parses the leaf blob for the real payload: Files (FileName / Digest / DigestAlgorithm / Size / PatchingType) with the download URL joined from ServerSyncUrlData by FileDigest, plus the leaf Prerequisites and en Title. Leaf blobs may be LZX-compressed, so it reuses Expand-FsCompressedBlob (2 MB head; the Files section sits near the top, well within it). Output: the Server2016 dataset gains CurrentSetLeaves (per leaf: Line, ParentKB, LeafUpdateID/Revision, Compressed, FileCount, UrlCount, Files[], LeafPrereqIds); the first leaf-follow GetUpdateData response is saved raw (fs/raw.Server2016.leaffollow.b0.xml) for ground-truth; console prints a Server2016 LEAF-FOLLOW line with per-leaf file/url counts. This is a small number of EXTRA SOAP calls (Server2016 current set = 4 leaf identities = 1 batch), exactly the narrowed acquisition agreed. NO cross-OS generalization; the leaf parse is Server2016-local (duplication accepted per policy). Next (after the run confirms the Server2016 leaf files/URLs): step 4 cross-check the Server2016 current set against Microsoft Learn (LCU via windows-server-release-info markdown -- confirmed KB5094122 present and matching; .NET via the dotnet release-notes markdown; SSU has no Learn-markdown table, a noted gap). Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the leaf File/URL/Prerequisite parse was unit-tested on a real leaf GetUpdateData response. r13.38 (Server2016-ONLY current-set selector -- first per-OS design/implementation unit; explicitly NOT generalized). Per the agreed policy, design and implementation are split strictly PER OPERATING SYSTEM: separate named functions, OS-local parameters/variables, no shared generic selector, no cross-OS rule. This version adds exactly ONE such unit, Get-Server2016CurrentSet, and a dispatch that calls it ONLY for Server2016 (switch with a single case; Server2019/2022/2025 are deliberately untouched and will each get their own separate function later). The Server2016 unit encodes only Server2016 facts established in the per-OS L3 analysis: the current set is LCU + standalone SSU + .NET 4.8, selected as newest-by-title-date per line; dual-identity (same KB, multiple identities -- e.g. the 2026-06 LCU KB5094122 carries two) is preserved by keeping every identity sharing the newest year-month in its line, to be de-duplicated later at the leaf. Server2016 has no Dynamic Update line and no Azure Stack HCI in its node, so neither is handled here (and must not be assumed for other OS). Output: per-OS dataset gains CurrentSet (populated for Server2016 only; null for the others until their own unit exists); console prints the Server2016 current set with leaf-follow target counts. No leaf-follow yet (that is the next per-OS step, also Server2016-first). Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the Server2016 selector was unit-tested on the real Server2016 dataset (expect SSU KB5094141 x1 + .NET KB5087065 x1 + LCU KB5094122 x2 = 4 target identities). r13.37 (parse fix for the Decision-B leaf-follow target -- found while validating r13.36 on the live run). The BundledUpdates leaf pointer is parsed order-independently now. Root cause: Server2025 wraps the leaf in <upd:AtLeastOne> AND emits the attributes in the reverse order (RevisionNumber BEFORE UpdateID), e.g. <upd:AtLeastOne><upd:UpdateIdentity RevisionNumber="100" UpdateID="..."/></upd:AtLeastOne>, whereas 2016/2019/2022 emit UpdateID then RevisionNumber. The old regex assumed UpdateID-first, so every 2025 BundledLeaf came back RevisionNumber=0, which would have broken the future leaf GetUpdateData. Fix: match each <UpdateIdentity ...> element inside BundledUpdates, then pull UpdateID and RevisionNumber from it independently (the AtLeastOne wrapper is transparent). No behaviour change for 2016/2019/2022 (still UpdateID+RevisionNumber); 2025 now carries the real leaf RevisionNumber. SupersededUpdates stays UpdateID-only (order-independent already). Validated on real 2022 (UpdateID-first) and 2025 (AtLeastOne + RevisionNumber-first) bundle blobs. r13.36 (BASELINE step -- Decision A agreed with the user: capture the full Relationships graph SKELETON with NO extra SOAP calls). r13.35 closed the record-loss (noblob 0 across all four OS; ~220 compressed component updates recovered per legacy OS with their prereq edges), so the per-OS set is complete; this version stops reducing Relationships to a bool and parses its contents from the blobs already fetched. Ground truth from a live bundle blob: Relationships = SupersededUpdates (UpdateID-only, 5-8 per LCU) + Prerequisites (already parsed) + BundledUpdates (UpdateID PLUS RevisionNumber -- the single leaf pointer, e.g. RevisionNumber=200). Each record now carries SupersededIds (the supersedence chain), BundledLeaf (UpdateID+RevisionNumber pairs -- the exact GetUpdateData target for the future leaf-follow), and IsBundle (derived = has BundledUpdates). After the per-OS records are collected, two dataset-level fields are computed cheaply: IsSuperseded (this UpdateID appears in some other record SupersededIds -- so the live/non-superseded set is directly queryable, which is exactly the Decision-B narrowing key) and the SUPERSEDENCE-CLOSURE check (SupersededTargets vs SupersededTargetsInSet = how many supersedence edge targets resolve to a record inside this per-OS set) -- the data-completeness verification the user asked for, so we can see whether the live-set computation is sound before driving leaf acquisition off it. Dataset/overview add Bundles / Superseded / LiveBundles / SupClosure; console prints them per OS. NO leaf-follow yet (Decision B / the additional dataset is next, narrowed by LiveBundles); NO Files/URL beyond the bundle (those live on the leaf). Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the SupersededUpdates / BundledUpdates (with RevisionNumber) extraction was unit-tested on a real Server2022 bundle blob. r13.35 (RECOVER the ~44 percent of per-OS records that r13.34 labelled noblob -- they were NOT empty, they are real updates whose blob is COMPRESSED; grounded in the user reference INVESTIGATION-STATE.md and re-verified on live raw data). The r13.34 raw sample (saved on purpose) showed the noblob ServerSyncUpdateData carry <XmlUpdateBlobCompressed> -- a base64 MSCF cabinet (LZX) holding the UTF-16 update XML -- which the parse did not handle; and separately Server2025 had 40 plain blobs whose content spans NEWLINES that the non-Singleline regex silently dropped. Confirmed via cabextract on the live cab: it decompresses to <upd:Update ...> in UTF-16 with UpdateType / LocalizedProperties / Prerequisites; these compressed updates are payload/component packages (Title is a .cab name, e.g. Windows10.0-KB....x64.cab) carrying 4-5 prerequisite edges -- real dependency-graph data. TWO fixes. (1) COMPRESSED BLOBS: a new Expand-FsCompressedBlob follows the reference method (base64 -> temp .cab -> expand.exe -> read as UTF-16); the parse now falls back to it when XmlUpdateBlob is absent, so the component updates and their prereq edges are captured instead of dropped. KEY EFFICIENCY: the header fields all sit in the first ~1-2 KB while the bulk (ApplicabilityRules CBS tree) can be ~80 MB, so only the first 2 MB of the decompressed file is read -- expand still writes the full file to a TEMP scratch dir OUTSIDE the run folder (never zipped, deleted per record), but PowerShell never loads the 80 MB. (2) PLAIN BLOB SINGLELINE: the XmlUpdateBlob (and Compressed) regex is now (?s) so multi-line plain blobs (the 40 Server2025 records) extract correctly. Records gain a Compressed flag; overview adds a Decompressed count. SCALING NOTE recorded: the full obtainable-catalog baseline (~200K, the survey harvest path, NOT this FS) will hit the same compressed blobs at scale -- expand-per-record writing tens of MB each is heavy, so that path needs a head-only / partial-decompress strategy before the full baseline is run. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the decompress-head + field extraction was verified with cabextract on real small AND large 2016/2022 compressed blobs (UpdateType=Software, en title, 4-5 prereq edges all recovered from the <=2MB head). r13.34 (make the per-OS dataset the dependency-rich BASELINE -- Case 1 of the agreed cascade; per the user: hold a full + an OS-narrowed baseline, then layer filtering, and never lose patch type/kind or dependency-relevant data). The r13.33 run exposed that the prior per-OS dataset was a thin slice: ~45 percent of every OS was EMPTY records (Title/KB/Products all blank) labelled unknown, and the records carried NO dependency graph. Ground truth from a real LCU blob: each blob carries UpdateType, a Prerequisites block with plain UpdateIdentity prerequisite edges PLUS AtLeastOne IsCategory groups, a Relationships block, and ~53 UpdateIdentity refs -- all of which were being discarded. THREE changes. (1) DEPENDENCY-RICH RECORD: each record now carries HasBlob, UpdateType, Kind (leaf-by-title or non-leaf-by-UpdateType, so the empty records are LABELLED not unknown), the plain prerequisite edges (PrereqIds), the IsCategory membership (CatMembers), and HasRelationships / HasFiles -- the substrate the dependency analysis (apply-order / prereq SSU / checkpoint / bundle-to-leaf) is derived from. (2) NODE COMPLETENESS: Server2022 fixed node set is now 71718f13 PLUS 97b08ca0 -- the r13.33 covering on 71718f13 alone returned 228 referencing only 71718f13, while an older 2022 LCU blob sits under 97b08ca0, so the 2022 history (supersedence chain) was entirely missing; node discovery still expands from LCU product members on top. (3) GROUND-TRUTH INSTRUMENTATION: the first GetUpdateData response per OS is saved raw (fs/raw.<os>.getupdatedata.b0.xml) so the empty/non-leaf records can be inspected directly next run rather than inferred. Dataset/overview now report Leaf / NonLeaf / NoBlob counts and the Kind breakdown. This is Case 1 (per-OS baseline, NO filter); the full obtainable-catalog baseline and the language / additional-filter cascade (Cases 2,3) come next, each diffed against this baseline to prove zero type/kind/dependency loss. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the UpdateType / Prerequisites-split / IsCategory extraction was unit-tested on a real KB5065432 blob (UpdateType=Software, 4 prereq edges, 2 IsCategory groups incl 97b08ca0). r13.33 (fix the two faults from the r13.32 live run on Server2016: membership=1 then a crash at node-discovery with property TypeGuess not found). ROOT CAUSE A (crash): Get-FsMetadata and Get-FsCovering returned their List via the comma idiom (,$out / ,$ids); reproduced in pwsh that @(func) over an EMPTY List-returned-by-comma yields Count=1 whose one item IS the empty List object, which was then added to the record set and lacked TypeGuess under StrictMode. FIX: both functions now return the List WITHOUT the leading comma, so @(func) enumerates to 0 / N items; a defensive PSObject.Properties[TypeGuess] guard was also added to the LCU Where-Object filters. ROOT CAUSE B (membership=1): the r13.32 server-side <Languages> covering filter COLLAPSES the per-OS covering from the expected hundreds (Server2016 ~518) to ~1 -- that populated Languages element in this position is rejected by the catalog, and the fallback fired only on EXACTLY 0 so the bad count slipped through. FINDING: query-level <Languages> narrowing does NOT work here. FIX: the query-level <Languages> filter is REMOVED; covering reverts to the validated no-Languages form (Categories-before-Classifications, anchor-paged). en/ja scoping is KEPT and handled at the DATASET level where it is robust: each blob carries 33 LocalizedProperties, so the en (then ja) Title is extracted per record (TitleEn/TitleJa/HasEn/HasJa) and the dataset/overview report LanguageScope=en,ja with RecordsWithEn/WithJa. LCU/SSU/.NET/DU payloads are language-neutral; per-language selection (en+ja Language Pack .wim only) stays a Phase-2 leaf concern. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; both the empty-List comma bug and the no-comma fix were reproduced in pwsh. r13.32 (FS Phase 1 -- LANGUAGE scoping to en + ja, per the user: the ISO patch targets are English and Japanese OS only): ground truth from a real blob -- ONE update blob carries 33 LocalizedProperties (one Title per language incl en and ja); language is NOT a separate UpdateID, so the LCU/SSU/.NET/DU are single language-neutral updates that each hold all language titles. TWO reflections. (1) RELIABLE TITLES: the metadata parse no longer grabs the FIRST <Title> (its order varies per update -- that is why the 2025 LCU showed an Arabic title); it now builds a language->title map from LocalizedProperties and takes the en title (then ja, then any) -- so TypeGuess / OS / recency run on the reliable English title. Records now carry TitleEn / TitleJa / HasEn / HasJa. (2) SERVER-SIDE NARROWING: Get-FsCovering takes an optional -Languages list and emits <Languages><string>en</string><string>ja</string></Languages> AFTER <Classifications> (WSDL element order); Phase 1 covers with Languages=[en,ja], so other-language-specific updates (mainly the 31 non-en/ja Language Packs) are dropped at the server. SAFE FALLBACK: if a language-filtered covering returns 0 for an OS (untested element form), it retries WITHOUT Languages and flags LanguageQueryFilter=ineffective (en/ja still taken from the blob), so a covering-shape surprise never yields an empty dataset. Dataset/overview now record LanguageScope=en,ja, the server-vs-blob filter status, and RecordsWithEn/WithJa. The LCU/SSU/.NET/DU payloads are language-neutral; per-language selection (en+ja Language Pack .wim only, not all 33) is a Phase-2/leaf concern. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; en/ja title extraction verified on a real KB5065432 blob (en + ja titles both recovered). r13.31 (FS PHASE 1 -- per-OS smart-dataset BUILDER; the agreed step 1 of the dataset(1)/resolve(2) loop): the re-verification (r13.30) PROVED server-side per-OS narrowing works (a Categories-first anchor-paged covering query returns a bounded ~hundreds set containing the current LCU; FULL-harvest cross-check confirmed the current 2026-06 LCU KB5094128 is in the 2022 covering set). This version turns that into the foundational per-OS DATASET builder. For each OS it: starts from the FIXED product GUID(s) (register 11.1: 2016 569e8e8f / 2019 f702a48c / 2022 71718f13 / 2025 b256987d) + the 5 servicing classifications; covering-queries the bounded per-OS revision set (Categories-first, anchor-paged -- the validated form); GetUpdateData-batches it (Title / KB / MsrcSeverity / URLs + the IsCategory product members); DISCOVERS the complete product-node set from the LCU memberships (an OS has MULTIPLE nodes -- e.g. 2022 = 71718f13 + 97b08ca0 -- and the fixed GUID alone is incomplete); EXPANDS the covering with the discovered nodes; and persists fs/dataset/<os>.json (FixedNodes / DiscoveredNodes / AllNodes / MembershipCount / NewestLcu / Records[UpdateID,Rev,Title,KB,MsrcSeverity,HasUrl,Urls,Products,TypeGuess]) plus fs/00.dataset-overview.json. KEY DESIGN POINTS grounded by a harvest prototype: (a) OS membership comes from the COVERING set (product node), NOT titles -- titles are multi-locale (2025 LCU is Arabic) and 21H2 collides with Windows 10 client, so title-based OS tagging contaminates the set; (b) TypeGuess is best-effort only (locale-robust substrings) and is CONFIRMED later by the per-OS resolver from leaf file names; (c) the 2025 fixed GUID b256987d is expected to surface only OLD revisions (the current 2025 LCU is under a different node) -- this version will make that gap VISIBLE (NewestLcu old) rather than hidden, which is the (A) acquire-from-elsewhere signal. NO dependency / apply-order here (deferred). NO Era abstraction in code -- Phase 2 will be explicit per-OS resolvers (Resolve-Server2016/2019/2022/2025) even where logic overlaps, because SSU handling already differs per OS (2016 standalone current SSU KB5094141 vs 2019/2022 embedded-in-LCU-leaf vs 2025 bundled file). Heaviest FS run so far (~per-OS covering + GetUpdateData of the bounded sets, batched 100, timestamped progress). Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; the GetUpdateData parse is the proven B6 form + the IsCategory product extraction; mock-tested the covering pager, the batched-metadata parse, node discovery, and per-OS persistence. r13.30 (FS Phase B REBUILT as an EMPIRICAL re-verification -- per the user direction NOT to swallow the prior incomplete WSUSSS conclusions but to RE-TEST them with corrected filters): the prior INVESTIGATION-STATE.md is treated as implementation reference (filter shape, GUIDs, blob structure) only, NOT as settled conclusion -- the report itself re-grades its scoped-enumeration findings OPEN (A-5), caveats the 80-result as sync-state-dependent + 2025-only, and its Get-WsusssRevisionList calls the filter form it elsewhere flags as wrong, so the prior scoped result is not trustworthy as a conclusion. THREE corrections make Phase B a real test: (1) ELEMENT ORDER -- Categories BEFORE Classifications (the working broad enumeration uses catXml+classXml; the confirmed New-WsusssScopedFilter is Categories-first; my r13.28/29 FS sent classXml+catX REVERSED, which likely caused the all-0 result, behaving like classifications-only=0); (2) ANCHOR-PAGED to completion (bounded; not a single page1 delta), with an early stop if a page set exceeds 50K (already not narrowing) or the anchor stops advancing; (3) ALL FOUR OS, not 2025 only. Trials: (a) single-product control (correct order) -- does one product alone still return 0 even with the order fixed; (b) per-LCU combined -- the LCU own <AtLeastOne IsCategory=true> members together (covering), anchor-paged; (c) per-OS covering -- {all product GUIDs seen for the OS} + {5 servicing classifications}, anchor-paged. DECISIVE CHECK: does a KNOWN-CURRENT LCU (seed UpdateID proven present in the unscoped 200K harvest) appear in any correctly-built scoped/covering query? The VERDICT is grounded in THIS run either way -- POSITIVE (a scoped/covering query surfaced a current LCU -> per-OS narrowing viable, prior claim refuted) or NEGATIVE (our own Categories-first anchor-paged all-OS test still did not surface a current LCU -> we now hold our OWN evidence, not an assumed one). Outputs fs/20.scoped-trials.json (per-trial count/pages/seedHits), fs/00.fs-summary.json, raw fs/b.combined.* + fs/b.peros.*. Phase A (IsCategory group extraction) unchanged. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; mock-tested the Categories-first paged filter build, the anchor-stop + 50K early-stop, and the empirical verdict branches. r13.29 (FS probe REFINED from the r13.28 ground truth -- test the COVERING hypothesis with COMBINED category sets): the r13.28 -FeasibilityStudy run returned revisions=0 for ALL 16 single-category trials, INCLUDING the categories each LCU is actually filed under. Reading the captured LCU blobs (fs/a.*) showed why: a leaf LCU has exactly TWO category prerequisites expressed as <AtLeastOne IsCategory=true> groups -- a classification group (0fa1201d = Security Updates) AND a product group (Server 2022 LCUs -> 71718f13 or 97b08ca0; Server 2016 KB5037763 -> 569e8e8f, NOT e26d4a30, which is why the e26d4a30 product-control missed); the plain <UpdateIdentity> prereqs are detectoid/SSU deps, not categories (r13.28 wrongly treated those as categories too). The all-categories=200K / single=0 / classifications-only=0 pattern => COVERING semantics: a revision is returned only if EACH IsCategory group has a member in the Categories filter, so a SINGLE category never suffices -- the groups must be passed TOGETHER. r13.28 only ever tested one category at a time, so it did not actually test narrowing. THIS version fixes both: Phase A now extracts the <AtLeastOne IsCategory=true> group members (the true category memberships, classification + product) instead of every taxonomy GUID; Phase B now runs the COMBINED covering test -- (B1) per-LCU: Categories = that LCU full IsCategory member set together (e.g. {0fa1201d, 71718f13}) + the 5 servicing classifications -> count + does the LCU appear; (B2) per-OS: Categories = {all product GUIDs seen for that OS} + {5 classifications} -> the OS servicing set count + which seed LCUs appear. VERDICT: if a combined-scoped trial returns a BOUNDED set CONTAINING the known LCU, server-side per-OS narrowing is CONFIRMED and the FS pipeline scopes per OS server-side then GetUpdateData only that set (the smart path; no 200K sweep). Raw per-trial GetRevisionIdList saved (fs/b.combined.*, fs/b.peros.*). Run again: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. Validated: AST OK, braces balanced, BOM + ASCII; mock-tested the IsCategory-group extraction (2 groups per LCU, detectoid prereqs excluded), the combined-set filter build, the nested Invoke-FsScoped, and the verdict. r13.28 (FEASIBILITY STUDY block -- self-contained, opt-in -FeasibilityStudy; per the user direction to keep ONE script but put the OS-targeting/use-case logic in its OWN decoupled section with no scope dependency on the survey): the foundational WSUSSS+WUSP investigation is now FROZEN (unchanged); this adds a separate FEASIBILITY STUDY section for the ISO-build use case. -FeasibilityStudy forces the three domain flags off (so PART 0/1 + WUSP, spec-fetch and pre-flight all skip) and runs ONLY the FS block, which is fully self-contained: its OWN handshake (GetAuthConfig -> GetAuthorizationCookie -> GetCookie -> fresh cookie), its OWN GetConfig=true taxonomy, its OWN seed -- it does NOT read $leafRows / $harvest or any survey result. PURPOSE: test whether the WSUSSS GetRevisionIdList Categories filter can NARROW the catalog to a target OS SERVER-SIDE (the smart path the user wants, vs the full 200K sweep which is equivalent to analyzing wsusscn2.cab and is explicitly NOT wanted as the means). A single top-level product node was proven = 0 (leaves are filed under DESCENDANT category nodes, not the product node), so the probe (A) GetUpdateData on KNOWN target-OS LCUs (seed from the prior harvest: Server 2022 KB5065432/KB5039227/KB5029250, Server 2016 KB5037763) and extracts the category UpdateIDs each LCU is actually filed under (blob UpdateID refs intersected with the taxonomy); (B) scopes GetRevisionIdList by each of those category UpdateIDs + the 5 servicing classifications and records the revision COUNT and whether the seed LCU appears -- i.e. does any category scoping yield a bounded per-OS set CONTAINING the known LCU. Outputs fs/: 00.fs-summary, 10.seed-category-memberships, 20.scoped-trials, raw handshake 01..04, raw per-LCU GetUpdateData a.<KB>.* (the modern-LCU blobs -- ground truth to refine the category-membership parse from), and the first 6 scoped-trial raws b.trialNN.*. Wrapped in try/catch -> fs/99.error.json + always-zip. VERDICT line: if a category-scoped trial returns a bounded set containing a known LCU -> server-side narrowing is FEASIBLE and the FS part will use it (small scoped query -> GetUpdateData only that set -> visualize); if not, the raw LCU blobs let us refine the candidate categories (loop discipline) -- inconclusive, not disproven. Run: Invoke-WuProtocolSurvey.ps1 -FeasibilityStudy. The heavy GetUpdateData full sweep is NOT used here -- this is the narrowable-SOAP-API investigation. Validated: AST OK, braces balanced, BOM + ASCII; FS-only run is StrictMode-safe (summary vars envSummary/wsusssWalk/etc. are pre-initialized). r13.27 (cosmetic -- fix the stale summary acquisition-mode label): the r13.26 -SampleData run succeeded end-to-end (harvest records=2000 titled=1687 with-URL=1597 modern-KB5=81, zip 16MB, no crash, WSUSSS 18/18 + WUSP 10/10 as expected) and CONFIRMED the harvest surfaces modern server LCUs with real CDN URLs -- e.g. KB5065432 / KB5039227 / KB5029250 = Cumulative Update for Microsoft server operating system version 21H2 (Server 2022) each captured with Title / KB / MsrcSeverity / FileDigest / download.windowsupdate.com URL. The only defect was a STALE summary line: the final WSUSSS summary still printed the r13.25 per-OS-scoped text even though r13.26 removed per-OS scoping; it now prints the accurate broad-enumeration + stride-sampled-harvest description (with the enumerated count + -HarvestSampleSize). No logic change. OBSERVED (informs the next ISO-build step, not a defect): of the 81 modern KB5 in the sample, 17 carry an inline file URL and 64 do not -- the URL-less ones are bundle/wrapper updates whose payload (.msu) lives in CHILD leaves (the main-wrapper vs anchor-leaf pattern), so resolving a target-OS LCU to its installable .msu requires following the bundle->leaf relation (a GetUpdateData on the child updates), which is the ISO-build resolution step. Validated: AST OK, braces balanced, BOM + ASCII. r13.26 (FIX the r13.24/r13.25 runtime crash + STRENGTHEN robustness + REPLACE the dead per-OS scoping with a real analyzable GetUpdateData harvest -- per the user run-failure report): the live run crashed with a .NET format error because a Write-Host format string used the INVALID alignment specifier {2,>9} (the > is not allowed; right-align is {2,N}); it was in the per-OS table print I added and copied. Because WSUSSS had no error guard, the crash produced NO zip. THREE corrections. (1) ROBUSTNESS: the entire WSUSSS PART 1 body is now wrapped in try/catch -- any failure writes wsusss/99.error.json and the run CONTINUES to the shared summary + zip, so a crash never again yields an empty hand-back (the WUSP block already had this; WSUSSS now matches). (2) PER-OS SCOPING REMOVED (it was wrong): the r13.24 probe run PROVED that a per-OS SCOPED GetRevisionIdList (filter Categories=[one server OS product GUID] + Classifications=[servicing]) returns ZERO revisions for ALL FOUR server OSes (HTTP 200, empty NewRevisions), even though those product GUIDs ARE present in the B5a taxonomy dictionary -- a single product category node surfaces no leaves (the leaves gate on the full category set), the SAME structural dead-end as the WUSP product-scan. So the per-OS SAMPLE branch + Invoke-WsusssScopedAcquisition (and its broken format string) are DELETED. B5b now ALWAYS does the broad OS-independent enumeration (classifications [+ all categories], ~200K in one ~35MB call); OS-targeting is derived LATER from the harvested metadata. (3) ANALYZABLE HARVEST (the real point -- acquire data for log/offline analysis): B6 is no longer a single 80-id digest grab; it is a BATCHED GetUpdateData harvest over the enumerated set that persists per-revision ANALYZABLE records -- UpdateID, RevisionNumber, Title, KBArticleID, MsrcSeverity, FileDigests, and download URLs (MUUrl, joined by digest) -- to wsusss/06.getupdatedata-harvest.json plus a counts summary (06.getupdatedata-harvest-summary.json: enumerated, harvested, titled, with-KB, with-URL, modern-KB5xxxxxx, batch errors, elapsed). FULL (default) harvests EVERY enumerated revision; SAMPLE (-SampleData) harvests -HarvestSampleSize (default 2000) revisions spread EVENLY across the whole catalog by STRIDE sampling -- NOT first-N, because the catalog head is XP-era and the modern server LCU/SSU are deeper, so the stride sample is representative. Batched by MaxNumberOfUpdatesPerRequest (100), WSUSSS-style timestamped progress every 20 batches + a DONE line; raw first 3 batches saved (06.getupdatedata.b0000..). The XmlUpdateBlob parse is the confirmed-from-captures escaped upd:Update form (Title/KBArticleID/MsrcSeverity); MUUrl is plain text in ServerSyncUrlData. B7-B9 keep the small $uids sample. NAMING: -SampleData kept (it now genuinely controls the harvest sample size). NEXT: run -SampleData to get a representative analyzable sample quickly (~20 GetUpdateData calls) and confirm modern KB5xxxxxx server LCU/SSU appear with URLs; then FULL for the complete dataset. Validated: AST OK, braces balanced, BOM + ASCII; unit-tested the harvest parse on the REAL captured 06.getupdatedata response (titles/KB/digests/URLs extracted) and the stride sampler + always-zip path. r13.25 (CONSOLIDATE to the TWO execution modes -- remove the extra -WsusssServerScopeProbe switch; per-OS scoped is now the SAMPLE-mode WSUSSS behavior): per the user instruction not to add unnecessary command switches and to keep exactly two run modes (FULL scope and SAMPLE). REMOVED the -WsusssServerScopeProbe param and its dedicated handshake-then-probe-then-zip-then-exit block. The per-OS scoped acquisition the probe introduced is now folded into the existing -SampleData mode as the WSUSSS B5b SAMPLE branch: FULL (default, no switch) keeps the OS-INDEPENDENT broad EC-2 enumeration (shape-select + complete anchor-paged ~200K); SAMPLE (-SampleData) now, for each server OS product GUID (2016 e26d4a30 / 2019 6e56e6da / 2022 71718f13 / 2025 b256987d), issues a per-OS SCOPED GetRevisionIdList (filter Categories=[that OS] + Classifications=[the 5 servicing GUIDs]) and a sampled GetUpdateData (Title/KBArticleID/MUUrl), then folds the per-OS sampled revision identities into leafRows so B6-B17 conformance flows naturally; the per-OS RevisionID counts + sample titles/KBs/URLs print as a table and persist to wsusss/scoped/ (00.scoped-acquisition-summary.json + per-OS ril.<OS>.* / gud.<OS>.* raw). The broad shape-probe loop (which could pull a large classifications-only page) now runs ONLY in FULL mode, so SAMPLE is genuinely per-OS-light; the B5b conformance verdict in SAMPLE mode comes from the first per-OS GetRevisionIdList capture. The probe function Invoke-WsusssServerScopeProbe was renamed Invoke-WsusssScopedAcquisition and now returns PerOs (summary rows) + Revisions (merged sampled identities) + TotalRevisions + FirstCap. NAMING DECISION (the user asked whether -SampleData is the right name for the second mode): KEPT -SampleData. Rationale -- the switch governs all three protocols (WUA env / WSUSSS / WUSP) and in every one it produces a bounded representative analysis set rather than the exhaustive catalog; for WSUSSS specifically the per-OS scoped slice is complete-in-scope but the GetUpdateData metadata is SAMPLED (first N), so it genuinely is a sample; and the user themselves named this mode -SampleData as the sampling mode. Renaming a pervasively-used switch would churn the WUSP/WUA semantics for no clarity gain. (If a clearer name like -Targeted is preferred, it is a one-pass rename.) No change to FULL-mode behavior, to the WUSP increments, or to the conformance/report logic. Validated: AST OK, braces balanced, BOM + ASCII; unit-tested the scoped-acquisition function returns per-OS rows + merged revisions + total + first cap, and a mock of the SAMPLE branch folds them into leafRows. r13.24 (WSUSSS SERVER-SCOPE PROBE -- live validation that query-stage scoping surfaces modern server updates): adds -WsusssServerScopeProbe, a focused fast mode that runs the WSUSSS handshake (B1-B4) then, for each server OS product GUID (2016 e26d4a30 / 2019 6e56e6da / 2022 71718f13 / 2025 b256987d), issues a SCOPED GetRevisionIdList with filter Categories=[that OS product] + Classifications=[the 5 servicing GUIDs], records the returned RevisionID COUNT, and samples GetUpdateData on the first 40 to confirm Title / KBArticleID / MUUrl (the real download.windowsupdate.com URL). It then zips and exits BEFORE the heavy B5b 200K enumeration / B6-B17 / WUSP, so the probe is cheap. New function Invoke-WsusssServerScopeProbe parses NewRevisions/UpdateIdentity for counts and unescapes XmlUpdateBlob (escaped upd:Update XML, confirmed from real captures) for Title/KB; MUUrl is plain text in ServerSyncUrlData. Persists wusp-style raw + a distilled wsusss/scopeprobe/00.scope-probe-summary.json + per-OS ril.<OS>.* / gud.<OS>.* captures, and prints a per-OS table (revisions / sampled / titled / sample KBs) + sample titles + a sample URL. PURPOSE (ground-truth-first): the WUSP per-product ProductScan returned 0 leaves and the WUSP anonymous corpus is the legacy self-contained .cab catalog (no modern Windows OS LCU/SSU); this probe checks whether the WSUSSS catalog-distribution path, scoped per OS, DOES surface the modern server LCU/SSU with their CDN URLs -- BEFORE committing to the full per-OS harvest implementation. If the probe shows sensible per-OS counts with modern KB5xxxxxx titles, the next step is the full FULL (OS-independent, raw + all 200K GetUpdateData) + SAMPLE (per-OS scoped, complete-in-scope) acquisition. If it comes back empty, we pivot before building. No change to the existing full-enum / harvest / report logic -- this is an additive, self-contained diagnostic switch. Validated: AST OK, braces balanced, BOM + ASCII. r13.23 (reporting polish -- WSUSSS report column fix + NEW MS-WUSP operation report): the r13.22 -SampleData re-run confirmed all five fixes worked (with-files=67, leaf-depth probe 6/6 OK -- GetExtendedUpdateInfo CONFORMANT, GetExtendedUpdateInfo2 + RegisterComputer EXPECTED-OUT-OF-PROFILE, SyncPrinterCatalog seeded CONFORMANT). Two presentation changes here. (1) LAYOUT FIX -- the WSUSSS OPERATION REPORT operation column was -40 wide but B5a (GetRevisionIdList(GetConfig=true dictionary), 44 chars) overflowed it and pushed that row phase/expected/actual columns out of alignment; widened the operation column to -46 in the console header, the console rows, and the 97.operation-report.txt rows. (2) NEW MS-WUSP OPERATION REPORT -- mirrors the WSUSSS report: a spec-grounded $WuspApplicability map places each of the 10 ClientWebService ops in a sync PHASE with its applicability basis + WSDL spec ref + expected verdict (W1 GetConfig / W2 GetCookie handshake; W3 SyncUpdates / W4 StartCategoryScan / W5 GetExtendedUpdateInfo catalog sync; W6 GetFileLocations / W7 RefreshCache / W8 SyncPrinterCatalog metadata; W9 GetExtendedUpdateInfo2 / W10 RegisterComputer = out-of-profile:anonymous, expected EXPECTED-OUT-OF-PROFILE). Write-WuspOperationReport gathers the ACTUAL verdict per op from the live objects -- handshake verdicts from the auth context, SyncUpdates/StartCategoryScan from the full-enum + product-scan results, and the six leaf-depth ops from the New-WuspOpRecord classifications -- then prints the EXPECTED vs ACTUAL table with [OK] / [!! UNEXPECTED] verdicts and a RESULT line (X/10 as expected, CORE gate clean), and persists wusp/90.wusp-operation-report.{txt,json}. expected-out-of-profile counts as AS-EXPECTED, exactly like WSUSSS B10-B17. No acquisition/protocol change -- presentation + a new persisted artifact only. $psAll/$ld are initialized to null at the WUSP block top so the report call is StrictMode-safe when an increment did not run. Validated: AST OK, braces balanced, BOM + ASCII; unit-tested the WUSP report renders 10/10 with the two anonymous ops classified expected. r13.22 (STAGE 1 -- real-run fault fixes from the -SampleData run + the two approved decisions): the live -SampleData run completed and was diagnosed from the raw captures; this version applies five corrections. (1) FILE PARSE FIX -- the all-leaf harvest reported with-files=0 because the real leaf file element is <File Digest=.. DigestAlgorithm=SHA1 FileName=.. Size=.. PatchingType=..><AdditionalDigest Algorithm=SHA256>..</AdditionalDigest></File> i.e. the digest is an ATTRIBUTE, not a <FileDigest> element; Invoke-WuspGetExtended now parses the <File ..> attributes into per-leaf Files objects (Name/Digest/DigestAlgorithm/Size/PatchingType) and derives FileDigests (the SHA1 Digest attribute) + FileNames from them; the probe digest harvest in Invoke-WuspLeafDepth was corrected the same way; the harvest record now carries Files + FileCount. (2) PROBE infoTypes FIX -- the probe GetExtendedUpdateInfo faulted 500 InvalidParameters fragmentTypes because it sent Published/VerificationRule/Eula which the public host rejects; reduced to the accepted subset Core/Extended/LocalizedProperties (the same set the harvest uses successfully). (3) SyncPrinterCatalog FIX -- the empty installedNonLeafUpdateIDs faulted InvalidParameters; it is now seeded (first 200 of the FULL-ENUM Category non-leaf, via the new -SeedNonLeafRevisionIDs param on Invoke-WuspLeafDepth). (4) VERDICT RE-CLASSIFICATION (approved decision A) -- GetExtendedUpdateInfo2 FailedAuthentication (the anonymous path cannot fetch URLs) and RegisterComputer RegistrationNotRequired (IsRegistrationRequired=false) are the CORRECT spec responses for the anonymous public profile, NOT non-conformance; a new New-WuspOpRecord classifies each op conformant / expected-out-of-profile / non-conformant (expected map keyed per op), exactly as WSUSSS B10-B17 are treated, and the probe count + log now report conformant+expected as OK and label EXPECTED-OUT-OF-PROFILE distinctly. (5) PRODUCTSCAN SEED + REORDER (approved decision B) -- the scoped product query returned 0 leaves (only non-leaf) because the base-data 226 seed was insufficient; FULL ENUMERATION now runs BEFORE the per-product ProductScan, and ProductScan seeds InstalledNonLeafUpdateIDs from the FULL-ENUM non-leaf set, cap-safe split (Category -> InstalledNonLeaf, Detectoid/other -> the new -SeedCachedRevisionIDs -> OtherCached); increment order is now base-data -> FULL ENUMERATION -> ProductScan -> LEAF DEPTH. WSUSSS is unchanged (it was fully conformant). NO Stage-2 classification/reconciliation here -- this fixes acquisition + conformance so the next run yields populated files, conformant/expected probe ops, and product-scoped leaves. Validated: AST OK, braces balanced, BOM + ASCII; mocked dry-run confirms the file parse, New-WuspOpRecord classification, and the SeedCached path. r13.21 (STAGE 1 part 1c+ -- filtered-side enrichment for the Stage-2 (product x classification) reconciliation): on top of the r13.20 full per-product filtered-set acquisition, two additions make the cross-check robust. (1) each FILTERED leaf now also carries its prerequisite Frag (Invoke-WuspProductScan LeafPatches gains Frag), so a leaf present in the filtered view but ABSENT from the full set (an addition) can still be classification-attributed and same-UpdateID frag differences are inspectable; presence / absence / revision-change is already keyed by (UpdateID, RevisionNumber). (2) a lean cross-product roll-up products/01.filtered-leaves-rollup.json (per product: identity-only leaf list UpdateID / RevisionNumber / RevisionID / UpdateType + LeafCount + Recognized + Completed) -- the single FILTERED-side artifact Stage 2 will diff cell by cell against the full-set leaves (fullset/21.leaves-with-fragments) attributed to each (product x classification). With this, ALL Stage-1 raw is persisted for offline analysis: full set, all-leaf Title+files, probe URL chain, per-product filtered sets + the filtered roll-up. NO classification or reconciliation is computed (that is Stage 2). Validated: AST OK, braces balanced, BOM + ASCII. r13.20 (STAGE 1 part 1c -- ProductScan FULL per-product filtered-set acquisition + persistence): the per-product scoped query now acquires the FULL filtered leaf set (FilterCategoryIds = product, category baseline seeded) under the default, bounded only under -SampleData. TWO changes make full enumeration cap-safe and complete: (1) the scoped SyncUpdates loop now declares InstalledNonLeafUpdateIDs CATEGORY-ONLY -- it parses each non-leaf UpdateType via Get-WuspCoreInfo and routes Detectoid / other non-leaf to OtherCachedUpdateIDs (uncapped), keeping only Category non-leaf in the capped array (the same cap-safe fix FULL ENUMERATION uses); without it a full per-product walk would exceed the ~400 InstalledNonLeaf server cap (seed ~368 + detectoids) and fault. (2) the increment passes -MaxRounds = FullEnumMaxRounds (full, to per-product convergence) by default and 8 (bounded) under -SampleData, plus -CachedCap 200000. The per-product filtered leaf set is persisted both inside summary.{Os}.{Guid}.json (LeafPatches) and as a clean leaves.{Os}.{Guid}.json (leaf identities RevisionID/UpdateID/RevisionNumber/UpdateType) for the Stage 2 join. NO reconciliation/classification here -- Stage 2 will attribute each filtered leaf to its (product x classification) cell (via the leaf prerequisites / the FULL-SET join) and reconcile filtered-vs-full per cell. LIMITATION recorded: filtered-only leaves (additions, if any) have no FULL-SET fragment to classify against; the reconciliation will still DETECT them, and capturing per-leaf prerequisite refs to classify additions is a later refinement. -SampleData now scopes all three heavy WUSP increments (FULL ENUM 15 rounds, LEAF DEPTH 200 leaves, PRODUCT SCAN 8 rounds/product). Validated: AST OK, braces balanced, BOM + ASCII. r13.19 (STAGE 1 part 1b -- all-leaf depth harvest: Title + files for every leaf; URLs probe-only): the LEAF DEPTH increment no longer self-acquires a tiny bounded sample -- it now consumes the FULL ENUMERATION increment leaf set ($fe.Leaves, all ~8725; fallback to a bounded self-acquire only if FULL ENUM is unavailable). It then does TWO things: (1) a CONFORMANCE PROBE on the first batch (<=50 leaves) that exercises all 6 remaining ClientWebService ops incl the URL chain (GetExtendedUpdateInfo2 / GetFileLocations) -> keeps 10/10, persisted to 40.leafdepth-summary; and (2) an ALL-LEAF HARVEST of Title + files for EVERY target leaf via batched GetExtendedUpdateInfo (50/req per MaxExtendedUpdatesPerRequest, ~175 chunks for the full set), persisted to 41.leaf-harvest-all (full per-leaf records: RevisionID/UpdateID/RevisionNumber/Title/FileDigests/FileNames) + 42.leaf-harvest-summary (counts). Per the agreed Stage 1 scope, URLs are harvested on the probe sample ONLY (the heavy all-leaf GetFileLocations over ~tens-of-thousands of digests is deferred to the ISO-build use-case); classification (Stage 2) needs Title + files, which GetExtendedUpdateInfo alone provides. Invoke-WuspGetExtended was extended (DRY, also used by the category enumeration -- harmless there) to also extract FileDigests (<FileDigest>) and best-effort FileNames into ByRev, and to log progress every 10 batches; the file parse is best-effort and will be refined from the real leaf Extended structure (loop discipline; raw first-3 chunks saved). -SampleData now scopes BOTH the heavy ops: FULL ENUM is bounded to 15 rounds (yields >200 leaves) and LEAF DEPTH harvests the first -LeafDepthSampleSize leaves (default raised 25 -> 200, a spot large enough to see the classification distribution). Default (no -SampleData) = FULL ENUM to convergence + all-leaf harvest. $fe is initialized to null at the WUSP block top so the LEAF DEPTH guard is StrictMode-safe when FULL ENUM did not run. NO classification/reconciliation yet (that is Stage 2); this part only ACQUIRES + persists the raw material. Validated: AST OK, braces balanced, BOM + ASCII. r13.18 (STAGE 1 part 1a -- three-domain switch/flow redesign): restructures the script around the three investigations (WUA-API local / WSUSSS SOAP / WUSP SOAP) per the user staged plan. DEFAULT (no switch) now runs ALL THREE in the order WUA -> WSUSSS -> WUSP and flows into the single shared summary + zip. NEW mutually-exclusive restriction switches -OnlyWuaApi / -OnlyWsusssSoapApi / -OnlyWuspSoapApi (at most one; a second throws) derive the domain flags runWua/runWsusss/runWusp. NEW -SampleData (opt-in sampling; default = FULL data) replaces -FullData (every old -FullData use is inverted to -not SampleData). REMOVED switches: -RunWusp (the WUSP block is now gated by runWusp and relocated AFTER WSUSSS, with its self-contained zip + exit removed so all three domains feed the shared summary), -SkipWsusss / -SkipEnv (replaced by the domain flags), -AllowOnline / -IncludeDism / -MaxEnvUpdates (the WUA-API domain is now LOCAL-ONLY -- the online WUA scan 08b and DISM 08c sections are removed, their section keys kept as SKIP so the schema is stable; the env-capture MaxUpdates internal cap stays at default 40 for the local lists), and the dead -MaxSyncRounds. The WUSP sub-increments (base-data / product-scan / full-enum / leaf-depth) now run by DEFAULT (the per-increment switch gates are dropped; -SampleData will later scope the heavy ones). For -OnlyWuaApi the SOAP spec-fetch and the endpoint pre-flight are SKIPPED (no network probes). Summary Captured flags now read the domain flags and a Wusp entry was added. NO new acquisition logic in this part -- the all-leaf depth harvest + product-scan reconciliation come in parts 1b/1c; this is the structural foundation only. Validated: AST OK, braces balanced, BOM + ASCII, no dangling refs to removed params, three-domain sequencing with shared summary. r13.17 (REMOVE V1 + drop the V2 notation -- per user): the old WUSP PART2 (V1, A1-A13 inline) is DELETED in full. It was never run by the current workflow, carried known spec violations (e.g. GetExtendedUpdateInfo2 sent 8 infoTypes vs the spec-allowed FileUrl/FileDecryption only), and only consumed context. Removed: the whole if-runWusp block (A1 SLS-discovery .. A13 ReportEventBatch), the WSUSSS-quality WUSP gate, the V1-only switches RunWusp(old) and ForceWusp, and the dead wuspWalk init + the summary fields that referenced runWusp/wuspWalk. KEPT (shared, not V1): PART 1 WSUSSS (B1-B17), the SLS/preflight helpers (Invoke-HttpGetCapture, Get-SlsProtocol, SkipSls, WuspClientEndpoint, serviceId -- all used by the WUSP pre-flight), and the unified summary + zip. With V1 gone there is no longer a V1-vs-V2, so the V2 notation is dropped everywhere: the RunWuspV2 switch becomes RunWusp (runs the WUSP investigation standalone, exiting before PART 1); the MS-WUSP V2 REBUILD console banners become plain MS-WUSP; the V2 ERROR label becomes WUSP ERROR; the v2Dir variable + the wusp/v2/ output subfolder become wuspDir + wusp/ (so WUSP outputs are now wusp/basedata, wusp/fullset, wusp/leafdepth, wusp/products directly). NEW INVOCATION: the WUSP investigation now runs as Invoke-WuProtocolSurvey.ps1 -RunWusp -SkipEnv (plus -BaseData / -ProductScan / -FullEnum / -LeafDepth as before); the old -RunWuspV2 no longer exists. No behavior change to the WUSP investigation logic itself -- pure removal + rename. Validated: AST OK, braces balanced, param block binds, no dangling refs, no remaining V2 notation, old PART2 A-op markers all gone. Script shrank 2740 -> 2483 lines. r13.16 (LEAF DEPTH -- complete the remaining 6 WUSP ClientWebService ops in one increment): adds -LeafDepth (use with -RunWusp -SkipEnv), a new Invoke-WuspLeafDepth that finishes the WUSP foundational investigation. It self-contained-acquires a real LEAF sample (bounded Invoke-WuspCategoryEnumeration -FullEnumeration -MaxRounds 8, since categories must be declared before leaves appear per the cap-fix) then runs, ALL conformance-judged (NOT 200) via Test-ResponseConformance + $WuspContracts: (1) the DEPTH CHAIN -- GetExtendedUpdateInfo on LEAF revisionIDs (infoTypes Core/Extended/LocalizedProperties/.. per 2.2.2.2.6) harvesting FileDigest (SHA-1) -> GetExtendedUpdateInfo2 on LEAF UpdateIdentities (2.2.2.2.10) -> FileLocations URLs -> GetFileLocations on the harvested digests (2.2.2.2.7) -> URLs; (2) three STANDALONE PROBES one conformance call each -- RegisterComputer (2.2.2.2.3, computerInfo built from the client identity, spec-order minOccurs=1 fields), RefreshCache (2.2.2.2.5, globalIDs = sample leaf UpdateIdentities), SyncPrinterCatalog (2.2.2.2.9, empty installedNonLeaf+printerUpdateIDs = valid probe). SPEC-CORRECTNESS FIX vs the old PART2: GetExtendedUpdateInfo2 infoTypes is spec-restricted to FileUrl/FileDecryption ONLY (the old PART2 sent 8 values incl Published/Core/.. -- a 2.2.2.2.10 violation); corrected here. This takes the WUSP foundational op coverage from 5/10 to 10/10 ClientWebService ops exercised + conformance-judged (the depth chain GetExtendedUpdateInfo-on-leaf / GetExtendedUpdateInfo2 / GetFileLocations were the biggest gap; RegisterComputer/RefreshCache/SyncPrinterCatalog were untested). Outputs (wusp/v2/leafdepth/): 40.leafdepth-summary.json (per-op conformance verdict + Failures + the leaf->FileDigests->URLs chain counts + samples) plus raw captures 30.getextendedupdateinfo.leaf / 31.getextendedupdateinfo2.leaf / 32.getfilelocations / 33.registercomputer / 34.refreshcache / 35.syncprintercatalog. WSUSSS-style timestamped logging throughout (acquire/complete lines + per-op CONFORMANT/NON-CONFORMANT table). Parsers (FileDigest harvest, <Url> extraction) are best-effort for this first run -- the raw captures are authoritative and the parse will be refined from the real leaf Extended/FileLocations structure (loop discipline). New params -LeafDepthAcquireRounds (default 8) / -LeafDepthSampleSize (default 25). Helpers reused: New-WuspAuthContext (fresh cookie per query), Invoke-SoapCapture, Save-Capture, Get-ClientIdentity. Unit-tested: all 6 ops conformance-judged; depth-chain extraction (digests/urls) correct; GEI2 sends FileUrl/FileDecryption only; UpdateIdentity child-element shape, base64Binary fileDigests, computerInfo build, globalIDs, empty printer arrays all verified. NEXT (live run): run -RunWusp -LeafDepth -SkipEnv; confirm each of the 6 ops CONFORMANT on real data, refine the leaf Extended/FileLocations parse from the captures, and map the live leaf->files->URLs chain (the WSUSSS side already did this: LCU KB5094125 bundle c108488b -> leaf eb6ace0a -> 16 files incl SSU + checkpoint KB5043080 + URLs) -- which completes the WUSP foundational investigation at 10/10. r13.15 (A COMPLETE -- full unfiltered corpus acquired; + WSUSSS-style timestamped/elapsed logging): the -FullEnumMaxRounds 250 run reached stop-reason=sync-complete at round 227 -- TRUE natural convergence (r226 New=40 Truncated=false -> r227 New=0 Truncated=false, the catalog was exhausted). FULL SET = 20219 distinct: 368 Category + 11022 Detectoid + 104 Ref/None non-leaf + 8725 leaves. The Category-only cap fix held: InstalledNonLeafUpdateIDs peaked at 368, under the ~400 server cap (headroom 32 -- worth noting the category count itself sits just under the cap, a future risk if a catalog state pushes categories past 400). OtherCachedUpdateIDs carried detectoids+leaves (~19800) with no cap fault, confirming it is effectively uncapped relative to the ~400 InstalledNonLeaf cap. So the complete WUSP anonymous fe2cr corpus is now persisted (wusp/v2/fullset/: 00.fullset-summary, 10.nonleaf-categories incl. every non-leaf fragment, 20.leaves-index, 21.leaves-with-fragments incl. every leaf applicability fragment). LOGGING (requested -- match the WSUSSS operation logs): the full-enumeration now emits WSUSSS-style timestamped lines -- a START line ([HH:mm:ss.fff] + MaxRounds), periodic progress every 20 rounds ([HH:mm:ss.fff] round R/Max | leaves/non-leaf/InstalledNonLeaf | distinct | elapsed s | updates/s), and an END line (rounds, stop-reason, CONVERGED vs NOT, total elapsed in s and min, throughput updates/s, avg s/round, cap headroom, full corpus breakdown). Invoke-WuspCategoryEnumeration gained -ProgressEvery plus a Stopwatch; the result now carries ElapsedSeconds/StartedUtc, and 00.fullset-summary persists StartedUtc/EndedUtc/ElapsedSeconds/UpdatesPerSecond/Converged/CapHeadroom. The premature next-phase (filter) console line was removed -- the WUSP investigation continues; use-case/filtering work is deferred until the investigation is complete. Unit-tested: progress lines emit on cadence, ElapsedSeconds is set, convergence intact. r13.14 (cap fix VALIDATED; full-enum now scale-bound only -- parameterize MaxRounds): the Category-only declaration fix WORKED -- the live run declared InstalledNonLeafUpdateIDs=292 (well under the ~400 cap) and hit NO 500 fault, reaching 4176 leaves + 1153 non-leaf (850 Detectoid) = 5329 distinct. Two confirmations the fix is durable: (1) the Category count stopped growing at round 31 and stayed at 292 -- it does NOT head toward the cap; every late non-leaf burst (r57-60, 90/round) was DETECTOIDS, which correctly route to OtherCachedUpdateIDs (uncapped, seen at 5026 with no fault). (2) 0 leaves depend on a detectoid, as predicted. The run did NOT converge: it stopped at max-rounds-60-reached with New=90 DISTINCT still per round (the server pages ~90 new/round), so the corpus is larger than 5329. No drivers yet (0 leaves carry HardwareID); leaves are all Software across products+classifications (Security/Updates/UpdateRollups/Critical/ServicePacks + product categories). The remaining limit is pure SCALE: unfiltered enumeration must re-declare all cached IDs each round (no anchor in the protocol), so it is O(N^2) in request size, and at 90/round a large catalog needs many rounds. FIX this version: the full-enum MaxRounds is now a parameter -FullEnumMaxRounds (default 250, was a hard 60) and CachedCap is raised to 200000 (the old 6000 would have force-stopped near 6000 leaves). So the user controls how far to push. The end-of-run save fires on convergence OR MaxRounds OR fault, so partial corpora are always persisted; InstalledNonLeafDeclared is printed so the cap stays visible. NOTE: complete enumeration of the entire anonymous catalog may be impractical (tens of thousands, O(N^2)); the categories (the filter DIMENSIONS) are already COMPLETE at 292, so deriving the SEED-value filter conditions can begin on the complete category set + a substantial leaf sample without waiting for 100% leaf completion -- a decision for the user. r13.13 (ROOT CAUSE FOUND + FIX: InstalledNonLeafUpdateIDs server cap ~400; declare Category-only): the instrumented re-run PROVED the fault is deterministic, not transient -- all 3 retries at the fault round returned 500 again, and the run faulted at round 22 / 420 non-leaf (last run round 31 / 426). The saved fault body is ClientFault InvalidParameters parameters.InstalledNonLeafUpdateIDs (the GUID in it is a per-call correlation id, not an update id). Cross-run reconciliation pins the cause precisely: in the OLD audit walk, requests declaring 393 InstalledNonLeafUpdateIDs returned OK while every request declaring 405/407/414/431/468 got NO response (faulted) -- so my earlier read that the old walk reached 468 was WRONG: 468 FAILED; 393 was the max that succeeded. Combined with this run (333/397 OK, 420/426 fault) the server cap on InstalledNonLeafUpdateIDs is ~400 (<=393 OK, >=405 ClientFault). OtherCachedUpdateIDs is NOT capped (3088 seen OK). The full non-leaf tree (~420-470) exceeds the cap, which is why a single unfiltered sweep could never complete. KEY DATA that yields the fix: of the 420 non-leaf, 257 are Detectoid and 158 are Category; and of 1426 leaves, the 262 with an IsCategory prerequisite reference ZERO detectoids -- every leaf prerequisite is a Category (product/classification). Detectoids are applicability nodes, never leaf prerequisites, so they need not be declared as installed-non-leaf. FIX (full enum): declare ONLY Category-type non-leaf in InstalledNonLeafUpdateIDs (~158, safely under the ~400 cap) and route Detectoid / Ref(None) non-leaf to OtherCachedUpdateIDs (uncapped; suppresses re-send) -- so the capped array stays small while every leaf is still revealed (leaves gate on categories, which remain fully declared). Each non-leaf records DeclaredIn; the run now prints InstalledNonLeafUpdateIDs declared (must stay under ~400). The 5 Unparseable non-leaf were identified as Ref/AdditionalDigest cab-anchor fragments (not categories), correctly routed to OtherCached. Unit-tested: Category->InstalledNonLeaf, Detectoid->OtherCached, leaves->OtherCached, converges on no-new-distinct. PREDICTION for the next live run: InstalledNonLeafDeclared ~158 (<400), no 500, full-enumeration-complete-no-new-distinct, leaf count grows past 1426/2230 to the true total. Retry-on-500 + non-leaf fragment capture + burst-round saving from r13.12 retained. r13.12 (full-enum did NOT complete -- instrument + add resilience): the -FullEnum live run captured 426 non-leaf + 2230 leaves WITH applicability fragments, but it did NOT converge -- rounds 24-29 each added exactly 90 NEW DISTINCT leaves (a steady server page, NOT shrinking), so the corpus is larger than what we got and the full set is still incomplete. The stop at round 31 was NOT a generic 500: the saved body is a SOAP ClientFault InvalidParameters on parameters.InstalledNonLeafUpdateIDs (the server rejected that array). Reconciliation rules OUT a simple count limit -- the OLD audit walk declared up to 468 InstalledNonLeafUpdateIDs / 3556 total with no such fault, while THIS run faulted at 426 / 2656 total. So the cause is specific content, not size. Prime suspects: of the 426 non-leaf, 5 have UpdateID=None (no parseable UpdateIdentity in the core fragment), and round 30 was a burst of 29 new non-leaf right before the fault -- but SaveFullN=2 meant we did NOT capture the round-30 response or the non-leaf fragments, so the exact bad ID is not yet provable. Rather than guess a fix, this version INSTRUMENTS and adds RESILIENCE so the next live run either completes or yields the ground truth: (1) full-enum now retries a 500 up to 3 extra times with a 3s backoff (the fault may also be a transient/load-variable close, consistent with the old walk reaching further on a different day) -- each attempt recorded; (2) full-enum now preserves every NON-LEAF with its Frag plus an Unparseable flag (UpdateID empty) and FirstSeenRound, so the 5 UpdateID=None nodes can be inspected directly; (3) full-enum now saves the response of EVERY round that reveals new non-leaf (cap.SyncUpdates.burst.rNN), even past SaveFullN, so the round-30 burst is captured. Also surfaced from the captured corpus (informs the LATER filter step, not acted on yet): leaf UpdateType is Software 1797 / None 433; only 2 of 2230 leaves carry an inline b.WindowsVersion check while 335 carry registry checks and 1514 carry ApplicabilityRules -- i.e. OS targeting is via the prerequisite graph + registry/applicability, NOT inline OS-version predicates, so the SEED-value filter must work through the prerequisite/applicability structure, which is exactly why the COMPLETE corpus (incl. all non-leaf prerequisite nodes) is needed before deriving filter conditions. Unit-tested: a transient 500 is retried and the walk continues; non-leaf fragments + Unparseable flag are captured; burst rounds are saved. NEXT: re-run -FullEnum; if it still faults at the InstalledNonLeafUpdateIDs array, the captured non-leaf fragments + the round-30 burst response will identify the offending node(s) and the fix will be made from that ground truth. r13.11 (REFRAME -- acquire the COMPLETE corpus first): grounded correction of the approach after the user pointed out two things the data confirmed. (1) The OS product GUID is a FILTER applied to patch data, NOT a tree the patches hang under -- a scoped FilterCategoryIds=[OS product] query returns the OS APPLICABILITY data (detectoids whose IsInstalled rules check b.WindowsVersion ProductType/MajorVersion + registry), which is a DIFFERENT axis from the patch (leaf) data; the leaves carry their OWN ApplicabilityRules and are categorized on the classification axis, so OS targeting is via applicability evaluation, not product-prerequisite. The earlier leaf-prereq join (and the dead-end conclusion) was the wrong lens. (2) No single key/tree yields everything -- the correct method is to acquire the FULL set, then clarify the filter conditions from it using SEED-specific values. GROUND TRUTH that corrected my own wrong assumptions before building: the full anonymous fe2cr corpus is only ~468 distinct non-leaf + ~3088 distinct leaves (~3556 updates total), and the old r33 oversized-500 was NOT a hard ceiling (a clean audit walk reached r41 / 3556 declared ints / ~102KB requests with no 500) -- so full enumeration IS feasible and my prior cannot-fully-enumerate / leaves-not-needed assumptions were both wrong. The diagnosis of why the tool was not acquiring the full set: Invoke-WuspCategoryEnumeration deliberately broke at category-tree-complete (2 rounds no-new-non-leaf) with the literal comment leaves we do not need -- i.e. the assumption was encoded into the data collection, so the data could never disconfirm it. FIX (surgical -- the loop already accumulated leaves into OtherCachedUpdateIDs, tracked distinct via the seenRev set, and had the true-completion stop newCount==0 && !Truncated): Invoke-WuspCategoryEnumeration gains a -FullEnumeration switch that (a) does NOT early-stop at category-tree-complete, (b) preserves every leaf with its applicability Frag in res.Leaves, and (c) adds a no-new-distinct stop (2 rounds of zero new DISTINCT updates = corpus complete even though the server keeps Truncated=true and re-sends, which is exactly what the old walk showed). New -FullEnum switch (use with -RunWusp -SkipEnv) runs the complete enumeration and persists the full corpus to wusp/v2/fullset/ (00.fullset-summary, 10.nonleaf-categories, 20.leaves-index, 21.leaves-with-fragments). The default (no -FullEnumeration) path is UNCHANGED so the product-scan category baseline still stops at category-tree-complete. Unit-tested both: -FullEnumeration walks past the category-complete point, captures all distinct leaves WITH applicability fragments, and stops on no-new-distinct; the default path early-stops with zero leaves. CachedCap=6000 > 3088 and MaxRounds=60 both accommodate the full set. NEXT (only AFTER the live full set is in hand): derive the SEED-value filter conditions FROM the complete corpus (evaluate each leaf ApplicabilityRules against the per-OS SEED identity) -- not before it. r13.10 (FIX increment-3 zero leaves -- the real mechanism: seed InstalledNonLeafUpdateIDs with the category baseline): the r13.9 DNF attempt did not change anything -- the live StartCategoryScan returned preferredCategoryIds = the product ONLY even though the (product AND classification) DNF was sent correctly (5 AND-groups, verified in the raw request). Spec 3.1.5.6 explains why and confirms this is BY DESIGN: the PreferredCategoryList rule states that for a group containing a product AND an update-classification category, ONLY the product CategoryID is added to the preferred list. So FilterCategoryIds is always the product, and classification scoping is NOT done through StartCategoryScan/FilterCategoryIds. The real reason leaves were zero: a leaf is prerequisite-bound to (Product AND Classification) categories, and the product-only scoped response never surfaces the classification categories, so they were never in InstalledNonLeafUpdateIDs and no leaf entered NeededRevisions (spec 3.1.5.7). This matches the base-data behavior exactly -- leaves only appeared there in rounds 4-5 AFTER all categories incl classifications had been declared. FIX: -ProductScan now first establishes a non-leaf category BASELINE (reusing the base-data enumeration if -BaseData ran, else doing one category walk) and SEEDS each product scan InstalledNonLeafUpdateIDs with that full baseline (all category revisionIDs), so the leaves (product AND classification) prerequisites are satisfied while FilterCategoryIds = the product restricts the result to that product. StartCategoryScan reverted to the product-only requestedCategories (spec-correct); Invoke-WuspProductScan gains -SeedNonLeafRevisionIDs and dedups the seed against in-loop non-leaf. Unit-tested: the round-1 request carries both the seeded InstalledNonLeafUpdateIDs and FilterCategoryIds=[product], and leaf patches are collected. This is hypothesis H1 (spec-grounded + base-data-confirmed); the live run will confirm leaves now appear per product, including whether 569e8e8f carries patches vs being an empty/legacy node. The per-product MaxRounds=8 bounded sample keeps the request under the oversized-array threshold; full enumeration is a later decision. r13.9 (FIX increment-3 returns zero leaves: scope by Product AND Classification, not Product alone; + correction of the absent claim): the -ProductScan live run produced two findings. (A) CORRECTION: the earlier claim that 569e8e8f / f702a48c are absent from the WUSP catalog was WRONG. StartCategoryScan recognized ALL SIX product GUIDs (recognized=true, preferred>=1, inError=0), including the two WSUS-only seeds. The base-data SyncUpdates non-leaf TREE walk did not surface them (a different retrieval path / deployment-scope), but the server DOES know them -- the StartCategoryScan recognition probe (a different method) is authoritative, exactly as the multi-GUID investigation predicted. (B) ROOT CAUSE of leafPatches=0 for EVERY product (incl. the known-good e26d4a30 / 71718f13 / b256987d): the scoped SyncUpdates used FilterCategoryIds = the product GUID ONLY, which returns the product detectoid/category subgraph (e26d4a30: 73 non-leaf across 5 rounds) but ZERO leaves -- because a leaf update is prerequisite-bound to a (Product AND Classification) pair, so a product-only filter satisfies no leaf. (Base-data returned leaves because it used NO filter = all deployed.) FIX: Invoke-WuspProductScan now builds the StartCategoryScan requestedCategories as a DNF pairing the product with each servicing classification in its own AND-group -- (product AND SecurityUpdates) OR (product AND CriticalUpdates) OR (product AND UpdateRollups) OR (product AND ServicePacks) OR (product AND Updates) -- so preferredCategoryIds carries product+classifications and FilterCategoryIds scopes leaves into view. New -ClassificationGuids param (the V2 block passes the 5 seed classification GUIDs); ClassificationGuidsRequested is recorded per product. Unit-tested: the DNF is emitted with the correct AND-group indices, preferred parses to product+classifications, and the scoped loop now collects leaf patches. NOTE the user insight was correct -- the missing dimension was the classification SCOPE, not client OS identity (client OS data drives leaf APPLICABILITY which is evaluated client-side; for software sync SystemSpec is forbidden, so the server response is client-OS-independent). NEXT: run -ProductScan live to confirm leaves now appear per (product x classification); compare 569e8e8f vs e26d4a30 leaf coverage (does the WSUS-only node carry patches or is it an empty/legacy node); then size each product scope and decide bounded-sample vs full enumeration + Title resolution. r13.8 (MS-WUSP increment 3: per-product scoped query, multi-GUID premise + GUID-named evidence): the base-data run proved a product TITLE is not unique -- WSUS Get-WsusProduct lists Windows Server 2016 under BOTH 569e8e8f and e26d4a30 (same for 2019). So each Product GUID is now treated as an independent first-class query. (1) SEED TABLE rebuilt to the multi-GUID (B) form: each OS carries every known Product GUID with a Catalogs note (WUSP = live fe2cr anonymous client catalog, ground-truth from the base-data run; WSUS = WSUS/USS product enumeration) and a WuspLive verdict. WUSP-live GUIDs e26d4a30 (WS2016) / 6e56e6da (WS2019) / 71718f13 (WS2022) / b256987d (WS2025); WSUS-only GUIDs 569e8e8f / f702a48c retained as real products absent from the WUSP client catalog. Seed validation + the V2 display now show the GUID per row. (2) NEW per-product machinery (Invoke-WuspProductScan): for each Product GUID, a fresh auth context -> StartCategoryScan(CategoryId=guid) [spec 3.1.5.6 / 2.2.2.2.8; NO cookie] -> preferredCategoryIds (recognized+expanded) / requestedCategoryIdsInError (NOT recognized by the server -- a direct evidence signal that a GUID is absent from this catalog) -> FilterCategoryIds (ArrayOfCategoryIdentifier {Id=guid}) -> scoped SyncUpdates loop collecting the leaf patches under the product. Evidence is written per GUID with the GUID embedded in BOTH the directory (products/{Os}__{Guid}/) and the file names (cap.StartCategoryScan.{Guid}.*, cap.SyncUpdates.{Guid}.rNN.*, summary.{Os}.{Guid}.json); a products/00.product-scan-index.json rolls up recognized/preferred/inError/leaf counts per GUID. New switch -ProductScan (use with -RunWusp -SkipEnv, with or without -BaseData) runs one independent fresh query per Product GUID. Unit-tested both paths: a recognized GUID returns preferred categories and collects leaf patches; a WSUS-only GUID (569e8e8f) returns it in requestedCategoryIdsInError with zero preferred = not-recognized, which is captured as the evidence (Ok=true, Recognized=false). FilterCategoryIds requires client pv>=1.7 (1.8) + server pv>=3.2 (4.2): satisfied. NEXT: run live to confirm StartCategoryScan behavior per GUID (esp. the WSUS-only GUIDs) and size each product scope; then decide bounded-sample vs full per-product enumeration and Title resolution. r13.7 (FIX increment-2 classification: GetExtendedUpdateInfo maps by revisionID, not UpdateID GUID; + seed key name): the increment-2 live run completed clean (rounds=5, 226 categories, stop=category-tree-complete, all 5 Classification seeds PRESENT), but every non-detectoid category fell into Uncategorized (Classification/Product/Company all 0) and the 4 Product seeds did not validate. The saved raw GetExtendedUpdateInfo captures gave the ground truth for two defects: (1) the GetExtendedUpdateInfo Extended fragment does NOT contain <UpdateIdentity UpdateID=...> (it is the Extended fragment: ExtendedProperties + HandlerSpecificData/CategoryInformation + LocalizedProperties), so mapping the result by UpdateID GUID matched nothing -> all Uncategorized. The response returns the revisionID in the <Update>/<ID> element, and TWO Update entries per revision (one Extended carrying CategoryType via <CategoryInformation CategoryType=...>, one LocalizedProperties carrying <Title>). FIXED: Invoke-WuspGetExtended now iterates <Update> nodes, keys by <ID> (revisionID int), and MERGES CategoryType + Title across the two entries (ByRev replaces ByGuid); classification joins each category by its RevisionID. Unit-tested on the live b02 capture: 50/50 revisions resolve CategoryType (Product 28, ProductFamily 22) AND Title. (2) the seed table key is Products (not ServerProducts), so the Product-seed read returned null and only the 5 Classification seeds were validated; FIXED to read Seeds[Products] with NameProp Os, and seed LiveCategoryType now resolves via the category revisionID -> CategoryType map. Spec discriminator unchanged (MS-WSUSSS 3.1.1.1): UpdateClassification -> Classification; Company/ProductFamily/Product -> Product axis. No request/sequence change -- response-parse + seed-key data fixes only. r13.6 (FIX increment-2 base-data crash: PS 5.1 StrictMode chained dictionary dot-access): the increment-1 handshake + the increment-2 SyncUpdates/GetExtended logic are correct, but the live run threw at the seed-validation step -- property ServerProducts not found -- because under Windows PowerShell 5.1 + Set-StrictMode -Version Latest, a chained dot-access on an OrderedDictionary obtained THROUGH a pscustomobject property (WuspEnv.Seeds.ServerProducts, where Seeds is the [ordered] seed table) throws, even though the key exists (a direct [ordered]-variable dot-access like res.Categories does NOT throw, which is why the bug surfaced only at the property-chained access and why pwsh 7 did not reproduce it). FIXED two such patterns version-agnostically: (1) seed reads now use IDictionary index access with Contains guards (Seeds[ServerProducts] / Seeds[Classifications]) instead of dot; (2) the Counts result is now a [pscustomobject] (was [ordered]) so the V2-block display WuspEnv-style chained access enum.Counts.Rounds resolves as a NoteProperty rather than a chained OrderedDictionary key (which would have thrown next, same root cause). Re-verified end-to-end on replayed live r01 data: enumeration runs clean, seed validation produces rows via the index path, Counts is PSCustomObject. No protocol/logic change -- a PS-version data-access defect only. r13.5 (MS-WUSP CLEAN REBUILD -- increment 2: base-data category enumeration): the increment-1 handshake is confirmed working (GetConfig + GetCookie both CONFORMANT 200; cookie acquired; ServerProtocolVersion=4.2; IsRegistrationRequired=false), so this increment adds the first independent LIVE base-data query: a fresh auth context + a SyncUpdates non-leaf loop (spec 3.1.5.7: InstalledNonLeafUpdateIDs starts empty, each round appends returned non-leaf IDs to InstalledNonLeafUpdateIDs and leaf IDs to OtherCachedUpdateIDs to make progress; NewCookie is followed intra-query; the loop stops when no NEW non-leaf appears for 2 rounds = category tree complete, so it does NOT walk the bulk leaves) that collects every IsLeaf=false UpdateInfo. GROUND TRUTH established from 40 real SyncUpdates captures before building: (1) the core fragment is a bare sibling-element sequence with NO <Update> root, parsed by the spec XPATH attributes UpdateIdentity/@UpdateID + Properties/@UpdateType (Get-WuspCoreInfo, unit-tested 46/46 on a live r01); (2) CategoryType does NOT exist in the core fragment (0 occurrences across 3556 live fragments) -- the Product-vs-Classification split comes ONLY from the Extended fragment via GetExtendedUpdateInfo (infoTypes Core+Extended+LocalizedProperties, locales en-US, batched by GetConfig.MaxExtendedUpdatesPerRequest=50), mapped to each category by the UpdateID GUID embedded in the fragment (envelope-shape independent); (3) the spec discriminator (MS-WSUSSS 3.1.1.1): Classification = UpdateType Category + CategoryType UpdateClassification; Product = CategoryType Company/ProductFamily/Product; Detectoid is its own UpdateType. Outputs (wusp/v2/basedata/): 10.enumeration-summary, 11.categories.all, 12.classifications, 13.products, 14.companies, 15.detectoids, 16.uncategorized, 17.seed-validation, plus the first 2 SyncUpdates + first 2 GetExtendedUpdateInfo raw captures (to finalize the Extended parse from live data). The confirmed seeds (5 Classification + 4 Server Product GUIDs) are validated for PRESENCE against the live full category list -- not assumed to be the universe. Verified on real r01: all 5 seed Classification GUIDs already appear as root categories, and Get-WuspCategoryEnumeration runs clean end-to-end on replayed live data (loop + extended map + classify + seed-check). New switch -BaseData (use with -RunWusp -SkipEnv) runs increment 1 then increment 2; zip is always produced. NEXT: confirm the live Extended-fragment CategoryType encoding from the raw captures, finalize any Uncategorized, then the per-OS conditional queries (StartCategoryScan DNF -> FilterCategoryIds scoped SyncUpdates) as first-class independent live queries. r13.4 (FIX GetCookie 500 root cause: wrong request namespace): the captured 500 body was a SOAP fault -- ClientFault / InvalidParameters / authCookies -- i.e. the server rejected the authCookies parameter. Root cause: New-WuspEnv set the request body namespace to the BARE data-contract ns (http://www.microsoft.com/SoftwareDistribution), but the MS-WUSP ClientWebService operations must use the WSDL targetNamespace http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService (confirmed by the section-4 examples: GetConfig, GetCookie, SyncUpdates all use it). GetConfig happened to pass on the bare ns (its only param is a plain string), but GetCookie''s authCookies landed in the wrong namespace so the server could not bind it -> InvalidParameters. FIXED: New-WuspEnv.Ns -> ClientWebService targetNamespace (now matches ActionBase + the spec examples + the old code''s GetCookie ns). Also hardened Get-SoapFault: it now detects a <Fault> that carries attributes (the regex required <Fault> with no attrs, so this fault slipped through as not-a-fault), handles SOAP 1.2 Reason/Text, and falls back to the <detail> text so non-standard faults surface their reason (this 500 now reports FAULT: InvalidParameters authCookies). r13.3 (capture the error-response BODY so the GetCookie 500 can be diagnosed): r13.2 fixed currentClientTime->currentTime and AuthPlugins now parse correctly ([PidValidator,Anonymous]), but GetCookie STILL returns 500 -- and the response headers show Content-Length=415, i.e. the 500 carries a body (a SOAP Fault with the real reason) that was being LOST. Root cause of the lost body: in PS 5.1 Invoke-WebRequest consumes the response stream before THROWing on an error status, so $exn.Response.GetResponseStream() reads empty; the body is reliably available on the ErrorRecord as $_.ErrorDetails.Message. FIXED Invoke-SoapCapture to read $_.ErrorDetails.Message first (general improvement for all error captures, WSUSSS included); -RunWusp now also prints the SOAP FaultString inline and persists cap.GetCookie.response.xml. The GetCookie request itself is spec-compliant (authCookies/oldCookie/lastChange/currentTime/protocolVersion all present, well-formed); the next run will capture the actual fault text and the real cause will be fixed from that ground truth (no guessing). r13.2 (FIX GetCookie 500 -- a real defect the old code never validated): the increment-1 live run gave GetConfig CONFORMANT(200) but GetCookie NON-CONFORMANT(500, empty body). Root cause: the GetCookie request sent <currentClientTime> but the MS-WUSP WSDL (2.2.2.2.2) requires <currentTime> (s:dateTime, minOccurs=1); the server could not find the required element and rejected with an empty 500. The old PART 2 carried the same currentClientTime bug but was never exercised on a real run (WUSP was always gated), so it had been happens-to-work-untested -- exactly why the rebuild was warranted. FIXED: currentClientTime -> currentTime; lastChange is now always sent (also minOccurs=1); AuthInfo plugin parse fixed PlugInId -> PlugInID (WSDL casing; AuthPlugins was empty because of this). Also: New-WuspAuthContext now keeps the raw GetConfig/GetCookie captures and -RunWusp persists them (wusp/v2/cap.GetConfig.*, cap.GetCookie.*) for ground-truth/debug. Live ground truth captured this run: ServerProtocolVersion=4.2 (>=3.2 so FilterCategoryIds is available), IsRegistrationRequired=false (RegisterComputer is NOT required -- resolves its applicability by spec signal, not guess). r13.1 (FIX -RunWusp crash + harden error handling): the increment-1 run crashed under StrictMode at the verdict display -- it referenced .Status, but the Test-ResponseConformance verdict has .HttpStatus/.Conformant/.Failures (no .Status). Because the crash happened BEFORE the zip step, no zip was produced. FIXED: verdict display now uses .Conformant + .HttpStatus + .Failures; the whole V2 auth-context body is wrapped in try/catch (writes wusp/v2/99.error.json with the message/line on failure); and the zip is now created ALWAYS (outside the try), so partial results are always handed back. Exit code 1 on error, 0 on success. r13.0 (MS-WUSP CLEAN REBUILD -- increment 1: intrinsic env + per-query fresh auth context): start of the WUSP rebuild (the old PART 2 is happens-to-work quality and is being replaced, not extended). Cookie/auth consistency by design: ONLY intrinsic info (endpoint, namespaces, seeds, contracts, client protocolVersion) is reused via New-WuspEnv; the session Cookie is re-created FRESH before EVERY query by New-WuspAuthContext (GetConfig -> [SimpleAuth] -> GetCookie) and lives only inside that query -- no cross-query cookie/auth state (within one query the Truncated-loop NewCookie is intra-query continuation, not cross-query state). Added $WuspContracts (WSDL response contracts for all 10 ClientWebService ops) so WUSP is conformance-judged (NOT 200=success); Test-ResponseConformance generalized with a -Contracts param. Added $WuspSeedCategories (confirmed-seed Server Product GUIDs + Classification GUIDs, with provenance; these are the confirmed SUBSET, to be validated against the live full Product/Classification lists by the upcoming base-data query -- NOT the universe). New standalone switch -RunWusp runs increment 1 (env + one fresh auth context) independently of WSUSSS and exits before PART 1; writes wusp/v2/01.authcontext.json + 00.managed-values.json + 02.seeds.json. NEXT: base-data query (non-leaf category enumeration -> full Product/Classification lists), then conditional queries (StartCategoryScan DNF -> FilterCategoryIds scoped SyncUpdates) as first-class independent live queries, then full-enumeration feasibility. r12.7 (B6-B9 spec contracts + EC-2 probe polish): (B) GetUpdateData/GetUpdateDecryptionData/GetDriverIdList/GetDriverSetData now have WSDL response contracts (result element ServerUpdateData/ServerDecryptionData/DriverSetAndRevisionIdList/ServerDriverSetData; all child elements are minOccurs=0 so conformance = not-SOAP-fault + spec result element present, NOT a children check). B6-B9 now GATE on .Conformant (was .IsSuccess) and emit CONFORMANT/NON-CONFORMANT; applicability expectation upgraded http-2xx -> CONFORMANT. CORE conformance is now 10/10 (B1-B9). (A) Invoke-BoundedSizeProbe classifies the WebException (.Status) so an unscoped server connection-close is reported as a clean server-reset (documented EC-2 unreliability) label instead of a raw exception dump; timeout 30s to 20s. r12.6 (EC-2 RESOLVED -- unscoped vs scoped): the unscoped-GetConfig=false contradiction (517-row "success" vs 120s drop) is resolved by spec 3.1.4.5 + run evidence. Per spec, GetConfig=false null-anchor returns the ENTIRE Revision Table in ONE response (anchor is a temporal delta, NOT pagination; no server page limit) -- observed ~312 MB (327,152,039 bytes). The "517-row success" was a 64KB capture-TRUNCATION artifact, not a small complete answer; the "drop" was a server-initiated close of that long ~312MB transfer (WebException, ~120s; completed in another run, so NOT a proven fixed cap -- a load/timing-variable close). CANONICAL EC-2 ENUMERATION is now SCOPED (Classifications[+Categories]=200,281, reliable); the unscoped full table is CHARACTERIZED by a new Invoke-BoundedSizeProbe (reads Content-Length + a 256KB sample then aborts -- no 120s wait, no 312MB buffer) and recorded to 05b.ec2-probe.unscoped.bounded.json. unscoped removed from the chosen-shape loop. r12.5 (SPEC-GROUNDED APPLICABILITY -- Track1/Track2): replaces the guess-based per-op expectations ("documented bare-500", "absent on public USS") with a model derived from the [MS-WSUSSS] sync sequence (3.2.4) and server-advertised config. Each op is placed in its sync PHASE with the spec PRECONDITION that gates it; our profile = anonymous AUTONOMOUS DSS <- catalog-only USS (CatalogOnlySync=TRUE), so phases 1-2 (B1-B9) are in-profile while phase3 B10 (replica-only, 3.1.4.10 MUST NOT invoke unless Replica), phase4 B11 (CatalogOnlySync=FALSE-only, 3.2.4.4), phase5 B12-B17 (reporting rollup, separate service) are OUT-OF-PROFILE -- by spec, not by guess. B12-B17 now carry a BOUNDED NOT-PUBLISHED proof (spec 2.1 mandates the path on the authoritative USS host = ServerSync host; absence there + role model 3.2.4.5/DoDetailedRollup/Appendix-A) instead of a lone-404 assumption. Endpoint derivation is now explicit + recorded to 00.data-provenance.json (ServerSync/DssAuth/Reporting: USS host per 1.5 + spec 2.1 paths; DssAuth cross-checked vs GetAuthConfig.AuthInfo.ServiceUrl); WUSP/SLS URLs (fe2/fe2cr/statsfe2) are a different protocol and are NOT conflated. The operation report (97.operation-report.*) now shows phase + spec-grounded basis + spec ref per op. NOTE on empirical endpoint check: from a non-MITM Windows host the run yields real codes (ServerSync/DssAuth 400=hosted, Reporting 404=absent at the spec path); an Anthropic-sandbox probe cannot reproduce these (egress gateway MITMs TLS and fails upstream cert verification -> synthetic 503), so the real-host run is the authoritative HTTP evidence. r12.4 (CONFORMANCE + DATA-PROVENANCE -- WSUSSS CORE B1-B5a): ROOT-CAUSE FIX for the standard that triggered this review -- the tool judged success by "HTTP 200" (Invoke-SoapCapture set IsSuccess on any 2xx, no body/fault/schema check) and the CORE gate keyed off it; request data was unmanaged (e.g. GetAuthorizationCookie sent the SAME random GUID as BOTH accountName and accountGuid). Added a CONFORMANCE + DATA-PROVENANCE layer (from the MS-WSUSSS WSDL): $WsusssContracts (per-op request/response contract), Test-ResponseConformance (the anti-200 verdict: transport-body + NOT-soap-fault + spec-result-element-present + required-result-children-present; a 200 carrying a Fault or lacking the result element is NON-CONFORMANT), Test-RequestConformance (root/namespace/required-children/soapAction vs WSDL), New-ManagedValue (every request value gets value+source+specRef+justification). B1-B5a now GATE on .Conformant (NOT .IsSuccess); accountName corrected to a distinct managed label (was a duplicate GUID -- data defect); GetCookie protocolVersion 1.7 and the auth GUIDs are now managed values. Per run: 00.data-provenance.json + 98.conformance.json + a conformance summary line. Add-Cov is verdict-aware (CONFORMANT/NON-CONFORMANT for contracted ops; http-2xx-uncontracted flagged for B6-B17/WUSP not yet contracted -- the gap is shown, not hidden). NEXT INCREMENT: extend contracts+verdicts to B5b(EC-2)/B6-B9, reconcile the unscoped-vs-scoped EC-2 record, then the WUSP side. No endpoint/handshake logic changed except the accountName data-correction (guarded by the new B2 verdict). r12.3 (WUSP A8/A9 leaf-first sampling): FIX -- GetExtendedUpdateInfo (A8) / GetExtendedUpdateInfo2 (A9) faulted 500-empty in the first live run because the extended-info sample was taken from the HEAD of the SyncUpdates walk, which is all IsLeaf=false (categories/detectoids, Action=Evaluate). Non-leaf pseudo-updates carry no metadata fragments, so asking GetExtendedUpdateInfo(2) for fragments on them faults. Proof it is NOT a request-shape defect: A11 RefreshCache succeeded on the SAME cookie + SAME first-80 non-leaf UpdateIdentity set (RefreshCache fetches no fragments); A8/A9 requests are byte-level spec-compliant (SOAPAction matches WSDL 6.2; ArrayOfInt <int> / ArrayOfXmlUpdateFragmentType <XmlUpdateFragmentType> / ArrayOfString <string> wrappers correct; infoTypes enums valid -- GetExtendedUpdateInfo 6 values per 2.2.2.2.6, GetExtendedUpdateInfo2 8 values incl FileUrl/FileDecryption per 2.2.2.2.10; UpdateIdentity carries UpdateID+RevisionNumber). Sampling now orders identities LEAF-FIRST (then non-leaf to fill) so A8/A9 are exercised on real leaf updates that have fragments; sample leaf/non-leaf provenance recorded to 07.syncupdates.sample.json + provenance.WuspWalk.Sample. A5 RegisterComputer 500 (managed/WSUS-flow op; public anonymous fe2cr likely rejects by policy; not required for the SSOT goal -- GetCookie anonymous cookie is accepted by all other ops) and SyncUpdates r33 500 (oversized accumulated reported-ID array; 32 rounds / 2836 updates already a solid catalog) are tracked separately, not addressed here. Spec re-confirmed live: MS-WUSP Published rev 38.0 (2026-02-09) == embedded reference. r12.2 (WUSP validation-prep): all 12 MS-WUSP ops (A2 GetConfig..A13 ReportEventBatch) confirmed present + request-shape reviewed against spec (SyncUpdates parameter sequence 2.2.2.2.4, GetExtendedUpdateInfo 2.2.2.2.6 ordering). Hardening: NeedTwoGroupOutOfScopeUpdates is now sent ONLY when the WUSP server GetConfig ProtocolVersion >= 3.2 (client GetCookie protocolVersion 1.8 >= 1.7), per spec 2.2.2.2.4 -- unconditional send to a < 3.2 server is a spec violation that can fault. Untested live; run -RunWusp -SkipWsusss to validate WUSP without the slow WSUSSS B5b. r12.1 (fix+data): (1) FIX -- Invoke-SoapCapture catch is now StrictMode-safe: a transport/timeout exception with no .Response property (the server DROPPING the unscoped EC-2 GetRevisionIdList connection) no longer aborts the run via "property Response cannot be found"; the access is guarded and the exception type is recorded, so the capture degrades to a fault and B5b falls through to the scoped shapes. (2) DATA -- $WuaBaselineSku Datacenter resolved from TBU to captured (NewProductType=8, SuiteMask=0x190) via a Server 2025 Datacenter RETAIL run (build 26100.32995): vs DatacenterEvaluation the ONLY delta is NewProductType (80->8); SuiteMask/OldProductType/WuaAgent identical -- supporting the build-keyed servicing hypothesis. Standard/StandardEvaluation remain TBD. r12: WUA CLIENT BASELINE dataset (phase0 ground truth, schema wua-phase0-capture/1.1) for MS-WUSP client / pseudo-data validation. Captured 2026-06-16 from four Windows Server Datacenter Evaluation EVAL media (Hyper-V Gen2, ja-JP). Factored on three ORTHOGONAL axes -- $WuaBaselineCommon (version-independent), $WuaBaselineLocale (en-US 1033 / ja-JP 1041), $WuaBaselineSku (edition; ONLY NewProductType + SuiteMask vary; OldProductType=3 for all), $WuaBaselineOs (isolated per generation 2016/2019/2022/2025, never mixed). Ground-truth vs placeholder is explicit: DatacenterEvaluation=captured (NewProductType=80, SuiteMask=0x190); Datacenter (retail)=TBU (capture next run on patched Server 2025 Datacenter retail -- same build 26100 confirms the Eval-vs-Retail delta); Standard variants=TBD; no derived/assumed numbers stored, RefDoc cites the winnt.h constant to confirm. Adds composer Get-WuaBaselineIdentity (ready for a future -EmulateServer path) + Compare-WuaIdentityToBaseline (records local-vs-baseline diff and surfaces local SKU values to resolve TBU/TBD). RECORD-ONLY this phase: no identity/request behavior change; written to 00.wua-baseline.json + provenance.WuaClientBaseline. r11.1 perf retained ($ProgressPreference + streaming GetRevisionIdList). Per INVESTIGATION-STATE.md section 0.0.'

# ---- spec provenance (Open Specs published-version reference, embedded as of the date below; the script
#      also fetches the LIVE published version at runtime unless -SkipSpecFetch). ----
$SpecProvenance = [ordered]@{
  'MS-WSUSSS' = [ordered]@{ Title='Windows Update Services: Server-Server Protocol'; Url='https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wsusss/f49f0c3e-a426-4b4b-b401-9aeb2892815c'; EmbeddedRevision='16.0'; EmbeddedDate='2024-04-23'; EmbeddedClass='Major'; EmbeddedAsOf='2026-06-20' }
  'MS-WUSP'   = [ordered]@{ Title='Windows Update Services: Client-Server Protocol'; Url='https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-wusp/b8a2ad1d-11c4-4b64-a2cc-12771fcb079b';   EmbeddedRevision='38.0'; EmbeddedDate='2026-02-09'; EmbeddedClass='Major'; EmbeddedAsOf='2026-06-20' }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Domain selection: three investigations (WUA-API local / WSUSSS SOAP / WUSP SOAP) ---
# Default (no -Only* switch) = run ALL THREE. The -Only* switches are mutually exclusive (at most one).
$onlyCount = @($OnlyWuaApi,$OnlyWsusssSoapApi,$OnlyWuspSoapApi | Where-Object { $_ }).Count
if ($onlyCount -gt 1) { throw 'The -OnlyWuaApi / -OnlyWsusssSoapApi / -OnlyWuspSoapApi switches are mutually exclusive; specify at most one.' }
$runWua    = (-not $OnlyWsusssSoapApi) -and (-not $OnlyWuspSoapApi)
$runWsusss = (-not $OnlyWuaApi) -and (-not $OnlyWuspSoapApi)
$runWusp   = (-not $OnlyWuaApi) -and (-not $OnlyWsusssSoapApi)
if ($FeasibilityStudy) { $runWua=$false; $runWsusss=$false; $runWusp=$false }  # FS is a self-contained study block; the survey domains are skipped.
# Suppress the built-in Invoke-WebRequest progress bar. In Windows PowerShell 5.1 the per-chunk progress
# rendering dominates wall-clock on large bodies (e.g. the multi-100MB GetRevisionIdList catalog response):
# turning it off speeds those reads up by an order of magnitude. The script uses its own Write-Host progress,
# so nothing user-visible is lost. No effect on SOAP request/response correctness.
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls13
    }
} catch { }

# ===================================================================================
# INLINED HELPERS  (no external files)
# ===================================================================================
function New-RunDir {
    param([Parameter(Mandatory)][string]$Name)
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dir = [IO.Path]::Combine((Get-Location).Path, ('{0}-{1}' -f $stamp, $Name))
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    return $dir
}
function Save-Text {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}
function Save-Bytes { param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes) [IO.File]::WriteAllBytes($Path,$Bytes) }
function Save-Json {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Object,[int]$Depth=20)
    Save-Text -Path $Path -Text ($Object | ConvertTo-Json -Depth $Depth)
}
function Get-SpecPublishedVersion {
    # Best-effort fetch of the Open Specs "Published Version" row (Date / Protocol Revision / Revision Class)
    # from the Microsoft Learn page (markdown rendering). Returns FetchOk=$false on any failure (offline host, etc.).
    param([Parameter(Mandatory)][string]$Url)
    $res=[ordered]@{ FetchOk=$false; Revision=$null; Date=$null; Class=$null; HttpStatus=$null; Error=$null }
    try {
        $resp=Invoke-WebRequest -Uri ($Url + '?accept=text/markdown') -UseBasicParsing -TimeoutSec 25
        $res.HttpStatus=[int]$resp.StatusCode
        $txt=[string]$resp.Content
        $i=$txt.IndexOf('## Published Version')
        if($i -ge 0){
            $seg=$txt.Substring($i,[Math]::Min(1500,$txt.Length-$i))
            $m=[regex]::Match($seg,'\|\s*([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\s*\|\s*([0-9][0-9.]*)\s*\|\s*([A-Za-z]+)\s*\|')
            if($m.Success){ $res.Date=$m.Groups[1].Value; $res.Revision=$m.Groups[2].Value; $res.Class=$m.Groups[3].Value; $res.FetchOk=$true }
            else { $res.Error='Published Version row not matched' }
        } else { $res.Error='Published Version section not found' }
    } catch { $res.Error=$_.Exception.Message }
    [pscustomobject]$res
}
function Get-XmlText {
    param($Node,[Parameter(Mandatory)][string]$Local)
    if ($null -eq $Node) { return $null }
    $n = $Node.SelectSingleNode(".//*[local-name()='$Local']")
    if ($n) { $n.InnerText } else { $null }
}
function Format-Xml {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Xml)
    if ([string]::IsNullOrEmpty($Xml)) { return $Xml }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($Xml)
        $sw = New-Object System.IO.StringWriter
        $xw = New-Object System.Xml.XmlTextWriter($sw)
        $xw.Formatting = [System.Xml.Formatting]::Indented
        $doc.WriteContentTo($xw); $xw.Flush()
        return $sw.ToString()
    } catch { return $Xml }
}
# NEVER-THROW capturing SOAP 1.1 poster: returns exact request + exact response (success OR fault).
function Invoke-SoapCapture {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Action,
          [Parameter(Mandatory)][string]$InnerBody,[int]$TimeoutSec=120)
    $envelope = '<?xml version="1.0" encoding="utf-8"?>' +
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>' + $InnerBody + '</s:Body></s:Envelope>'
    $out = [ordered]@{ Url=$Url; Action=$Action; RequestEnvelope=$envelope; IsSuccess=$false; StatusCode=0; ResponseContent=''; ResponseHeaders=@{}; ErrorMessage='' }
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'text/xml; charset=utf-8' `
            -Headers @{ SOAPAction = '"' + $Action + '"' } -Body $envelope -TimeoutSec $TimeoutSec -UseBasicParsing
        $out.IsSuccess=$true; $out.StatusCode=[int]$resp.StatusCode; $out.ResponseContent=[string]$resp.Content
        foreach ($k in $resp.Headers.Keys) { $out.ResponseHeaders[$k]=[string]$resp.Headers[$k] }
    } catch {
        # StrictMode-safe: a transport/timeout failure (e.g. the server DROPPING the unscoped GetRevisionIdList
        # connection -- the documented EC-2 unscoped-rejection) raises an exception whose type has NO .Response
        # property, and `$_.Exception.Response` under Set-StrictMode -Version Latest THROWS ("property cannot be
        # found"), masking the fault and aborting the run. Guard the access and record the exception type so the
        # capture degrades to a recorded fault (IsSuccess=$false) and the caller can fall through (e.g. B5b moves
        # on to the scoped shapes) instead of crashing.
        $exn=$_.Exception
        $out.ErrorMessage = ("[{0}] {1}" -f $exn.GetType().FullName, $exn.Message)
        # PS 5.1: on an HTTP error status Invoke-WebRequest THROWS after already consuming the response stream,
        # so $exn.Response.GetResponseStream() reads EMPTY. The error body (e.g. a SOAP Fault explaining a 500)
        # is reliably available on the ErrorRecord as $_.ErrorDetails.Message -- read that first.
        try { if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $out.ResponseContent=[string]$_.ErrorDetails.Message } } catch {}
        $r=$null; try { $r=$exn.Response } catch {}
        if ($r) {
            try { $out.StatusCode=[int]$r.StatusCode } catch {}
            if (-not $out.ResponseContent) { try { $sr=New-Object IO.StreamReader($r.GetResponseStream()); $out.ResponseContent=$sr.ReadToEnd() } catch {} }
            try { foreach ($k in $r.Headers.Keys) { $out.ResponseHeaders[$k]=[string]$r.Headers[$k] } } catch {}
        }
    }
    return [pscustomobject]$out
}
# NEVER-THROW capturing HTTP GET (SLS discovery).
function Invoke-HttpGetCapture {
    param([Parameter(Mandatory)][string]$Url,[int]$TimeoutSec=60)
    $out=[ordered]@{ Url=$Url; FinalUrl=''; IsSuccess=$false; StatusCode=0; ContentType=''; Bytes=$null; Text=''; ResponseHeaders=@{}; ErrorMessage='' }
    try {
        $req=[System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
        $req.Method='GET'; $req.AllowAutoRedirect=$true; $req.Timeout=$TimeoutSec*1000; $req.UserAgent='Windows-Update-Agent'
        $resp=$req.GetResponse()
        $out.IsSuccess=$true; $out.StatusCode=[int]$resp.StatusCode; $out.FinalUrl=[string]$resp.ResponseUri.AbsoluteUri; $out.ContentType=[string]$resp.ContentType
        try { foreach ($k in $resp.Headers.Keys){ $out.ResponseHeaders[$k]=[string]$resp.Headers[$k] } } catch {}
        $ms=New-Object System.IO.MemoryStream; $resp.GetResponseStream().CopyTo($ms); $out.Bytes=$ms.ToArray()
        try { $out.Text=[System.Text.Encoding]::UTF8.GetString($out.Bytes) } catch {}
        $resp.Close()
    } catch {
        $out.ErrorMessage=$_.Exception.Message; $r=$null; try { $r=$_.Exception.Response } catch {}
        if ($r) {
            try { $out.StatusCode=[int]$r.StatusCode } catch {}
            try { $ms=New-Object System.IO.MemoryStream; $r.GetResponseStream().CopyTo($ms); $out.Bytes=$ms.ToArray(); $out.Text=[System.Text.Encoding]::UTF8.GetString($out.Bytes) } catch {}
        }
    }
    return [pscustomobject]$out
}

# --- Endpoint pre-flight: one quick GET per endpoint to learn hosted vs not-hosted BEFORE issuing SOAP. ---
$script:Hosting = @{}   # url(lower) -> @{ Status; Hosted; Verdict }
function Get-EndpointStatus {
    param([Parameter(Mandatory)][string]$Url,[int]$TimeoutSec=15)
    $o=[ordered]@{ Url=$Url; Status=0; Hosted=$false; Verdict=''; Error='' }
    try {
        $req=[System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Url)
        $req.Method='GET'; $req.AllowAutoRedirect=$true; $req.Timeout=$TimeoutSec*1000; $req.UserAgent='Windows-Update-Agent'
        $resp=$req.GetResponse(); $o.Status=[int]$resp.StatusCode; $resp.Close()
    } catch [Net.WebException] {
        $we=$_.Exception
        if($we.Response){ try{$o.Status=[int]$we.Response.StatusCode}catch{}; try{$we.Response.Close()}catch{} } else { $o.Error=$we.Message }
    } catch { $o.Error=$_.Exception.Message }
    # HOSTED = path exists and responds (200/400/401/403/405/500). NOT-HOSTED = 404. else ambiguous/unreachable.
    if     ($o.Status -in 200,400,401,403,405,500) { $o.Hosted=$true;  $o.Verdict='hosted' }
    elseif ($o.Status -eq 404)                     { $o.Hosted=$false; $o.Verdict='not-hosted (404)' }
    elseif ($o.Status -in 502,503,504)             { $o.Hosted=$true;  $o.Verdict="gateway $($o.Status) (assume hosted)" }
    elseif ($o.Status -eq 0)                        { $o.Hosted=$true;  $o.Verdict=("unreachable now ({0}); will still attempt" -f $o.Error) }
    else                                            { $o.Hosted=$true;  $o.Verdict="HTTP $($o.Status) (assume hosted)" }
    [pscustomobject]$o
}
function Register-Hosting { param([string]$Url,$Probe) if($Url){ $script:Hosting[$Url.ToLowerInvariant()]=$Probe } }
function Test-Hosted {
    # Returns $true unless pre-flight positively classified the endpoint as not-hosted (404). Unknown -> attempt.
    param([string]$Url)
    if(-not $Url){ return $true }
    $h=$script:Hosting[$Url.ToLowerInvariant()]
    if($null -eq $h){ return $true }
    return [bool]$h.Hosted
}
function New-NotHostedCap {
    param([string]$Url)
    $h=$script:Hosting[$Url.ToLowerInvariant()]
    $st= if($h){[int]$h.Status}else{404}
    [pscustomobject]@{ Url=$Url; IsSuccess=$false; StatusCode=$st; NotHosted=$true; ResponseContent=''; ResponseHeaders=@{}; ErrorMessage='endpoint not hosted (pre-flight)' }
}
function Join-Url { param([string]$Base,[string]$Suffix) ($Base.TrimEnd('/') + '/' + $Suffix.TrimStart('/')) }
# Count UpdateIdentity leaves in a GetRevisionIdList response and capture the first $SampleSize (UpdateID +
# RevisionNumber) in a SINGLE streaming pass. Uses XmlReader (no DOM): the unscoped catalog body holds ~2.6M
# leaves; a [xml] DOM of that is multi-GB and parsing it twice (count, then sample) cost ~18 min in r11.
# Streaming does both in one pass at a fraction of the time/memory. Namespace-agnostic (matches on LocalName),
# same elements the prior local-name() XPath matched.
function Measure-RevisionIdList {
    param([string]$Xml,[int]$SampleSize=80)
    $sample=[System.Collections.Generic.List[object]]::new()
    if([string]::IsNullOrEmpty($Xml)){ return [pscustomobject]@{ Count=0; Sample=$sample } }
    $count=0; $curUid=$null; $curRev=$null; $inLeaf=$false; $lastEl=$null
    $settings=New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit
    $settings.IgnoreComments=$true; $settings.IgnoreProcessingInstructions=$true; $settings.IgnoreWhitespace=$true
    $sr=New-Object System.IO.StringReader($Xml)
    $rd=[System.Xml.XmlReader]::Create($sr,$settings)
    try {
        while($rd.Read()){
            switch($rd.NodeType){
                ([System.Xml.XmlNodeType]::Element) {
                    $lastEl=$rd.LocalName
                    if($rd.LocalName -eq 'UpdateIdentity'){ $count++; $curUid=$null; $curRev=$null; $inLeaf=($sample.Count -lt $SampleSize) }
                    if($rd.IsEmptyElement){ $lastEl=$null }
                }
                ([System.Xml.XmlNodeType]::Text) {
                    if($inLeaf){ if($lastEl -eq 'UpdateID'){ $curUid=$rd.Value } elseif($lastEl -eq 'RevisionNumber'){ $curRev=$rd.Value } }
                }
                ([System.Xml.XmlNodeType]::EndElement) {
                    if($rd.LocalName -eq 'UpdateIdentity'){ if($inLeaf -and $curUid){ $sample.Add([pscustomobject]@{ UpdateID=$curUid; RevisionNumber=([int]($(if($curRev){$curRev}else{0}))) }) }; $inLeaf=$false }
                    $lastEl=$null
                }
            }
        }
    } finally { try{ $rd.Dispose() }catch{}; try{ $sr.Dispose() }catch{} }
    [pscustomobject]@{ Count=$count; Sample=$sample }
}
# DISCOVERY: SLS environment.xml <Protocol> (clientServerUrl[CR], reportingServerUrl) from the minimal-form CAB bytes.
function Get-SlsProtocol {
    param([byte[]]$Bytes)
    if(-not $Bytes -or $Bytes.Length -lt 8 -or [Text.Encoding]::ASCII.GetString($Bytes[0..3]) -ne 'MSCF'){ return $null }
    $win = if($env:WINDIR){$env:WINDIR}else{'C:\Windows'}; $expand = Join-Path $win 'System32\expand.exe'
    if(-not (Test-Path $expand)){ return $null }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('wusls_' + [Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $root = Join-Path $tmp 'root.cab'; [IO.File]::WriteAllBytes($root,$Bytes)
        $q = New-Object System.Collections.Queue; $q.Enqueue($root); $done=@{}; $guard=0
        while($q.Count -gt 0 -and $guard -lt 40){
            $guard++; $cab=$q.Dequeue(); if($done.ContainsKey($cab)){continue}; $done[$cab]=$true
            $dest="$cab.x"; New-Item -ItemType Directory -Force -Path $dest | Out-Null
            try { & $expand '-F:*' $cab $dest 2>&1 | Out-Null } catch {}
            foreach($f in (Get-ChildItem -Path $dest -File -Recurse -ErrorAction SilentlyContinue)){
                try { $h=[IO.File]::ReadAllBytes($f.FullName) } catch { continue }
                if($h.Length -ge 4 -and [Text.Encoding]::ASCII.GetString($h[0..3]) -eq 'MSCF'){ $q.Enqueue($f.FullName) }
            }
        }
        foreach($f in (Get-ChildItem -Path $tmp -File -Recurse -ErrorAction SilentlyContinue)){
            $txt=$null; try { $txt=[IO.File]::ReadAllText($f.FullName) } catch {}
            if($txt -and $txt -match '<Protocol\b[^>]*clientServerUrl'){
                $m=[regex]::Match($txt,'<Protocol\b([^>]*)>'); $h=@{}
                foreach($a in [regex]::Matches($m.Groups[1].Value,'(\w+)\s*=\s*"([^"]*)"')){ $h[$a.Groups[1].Value]=$a.Groups[2].Value }
                return $h
            }
        }
        return $null
    } finally { try { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue } catch {} }
}
# DISCOVERY: GetConfig AuthInfo -> SimpleAuth applicability (plugins + first non-empty ServiceUrl). Read-only query.
function Get-WuspAuthInfoSurvey {
    param([string]$ClientEp)
    $res=[ordered]@{ Ok=$false; Plugins=@(); SimpleAuthUrl=$null; Error='' }
    $a='http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService'
    $cap=Invoke-SoapCapture -Url $ClientEp -Action "$a/GetConfig" -InnerBody '<GetConfig xmlns="http://www.microsoft.com/SoftwareDistribution"></GetConfig>' -TimeoutSec 30
    if($cap.IsSuccess -and $cap.ResponseContent){
        try { $x=[xml]$cap.ResponseContent
            foreach($pi in $x.SelectNodes("//*[local-name()='AuthPlugInInfo']")){
                $idn=$pi.SelectSingleNode(".//*[local-name()='PlugInID']"); $plug=if($idn){[string]$idn.InnerText}else{''}
                $sun=$pi.SelectSingleNode(".//*[local-name()='ServiceUrl']"); $su=if($sun){[string]$sun.InnerText}else{''}
                if($plug){ $res.Plugins+=$plug }
                if($su -and $su.Trim() -and -not $res.SimpleAuthUrl){ $res.SimpleAuthUrl=$su.Trim() }
            }
            $res.Ok=$true
        } catch { $res.Error=$_.Exception.Message }
    } else { $res.Error= if($cap.ErrorMessage){$cap.ErrorMessage}else{"status $($cap.StatusCode)"} }
    [pscustomobject]$res
}
# Per-protocol preflight: probe each endpoint, print a protocol-scoped report, return PASS/FAIL (REQUIRED-gated).
function Invoke-PreflightGroup {
    param([string]$Proto,[string]$Title,$Eps)
    Write-Host ''
    Write-Host ("--- PRE-FLIGHT [{0}] -- {1} ---" -f $Proto,$Title)
    $rows=@()
    foreach($e in $Eps){
        if(-not $e.Url){ continue }
        $pf=Get-EndpointStatus -Url $e.Url
        Register-Hosting -Url $e.Url -Probe $pf   # store the (lenient) probe for later per-op Test-Hosted decisions
        # GATE uses a STRICT positive-hosted confirmation (an .asmx answers a bare GET with 200/400/500). A 404
        # is a proven absence; 0/502/503/504 are NOT positive confirmations, so they do NOT clear a REQUIRED gate.
        $pos = ($pf.Status -in 200,400,401,403,405,500)
        $verdict = if($pos){"hosted ($($pf.Status))"} elseif($pf.Status -eq 404){'NOT FOUND (404)'} elseif($pf.Status -in 502,503,504){"gateway/ambiguous ($($pf.Status))"} elseif($pf.Status -eq 0){"unreachable"} else {"HTTP $($pf.Status)"}
        $rows += [ordered]@{ Protocol=$Proto; Name=$e.Name; Role=$e.Role; Source=$e.Src; Why=$e.Why; Url=$e.Url; Status=$pf.Status; Hosted=$pos; Verdict=$verdict }
        Write-Host ("    [{0,-8}] {1,-16} {2,4}  {3,-26} [src: {4}]" -f $e.Role,$e.Name,$pf.Status,$verdict,$e.Src)
    }
    $req=@($rows | Where-Object { $_.Role -eq 'REQUIRED' })
    $reqOk=@($req | Where-Object { $_.Hosted })
    $pass = ($req.Count -gt 0 -and $reqOk.Count -eq $req.Count)
    Write-Host ("    -> [{0}] preconditions: {1}  (REQUIRED hosted {2}/{3})" -f $Proto,$(if($pass){'PASS'}else{'FAIL'}),$reqOk.Count,$req.Count)
    [pscustomobject]@{ Protocol=$Proto; Pass=$pass; Required=$req.Count; RequiredHosted=$reqOk.Count; Rows=$rows }
}
function Save-Capture {
    param([Parameter(Mandatory)][string]$Dir,[Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)]$Capture)
    $meta=[ordered]@{}
    foreach ($p in $Capture.PSObject.Properties) {
        if ($p.Name -in @('RequestEnvelope','ResponseContent','Text','Bytes')) { continue }
        $meta[$p.Name]=$p.Value
    }
    Save-Json -Path ([IO.Path]::Combine($Dir,"$Prefix.meta.json")) -Object $meta
    if ($Capture.PSObject.Properties.Name -contains 'RequestEnvelope') {
        Save-Text -Path ([IO.Path]::Combine($Dir,"$Prefix.request.xml")) -Text (Format-Xml $Capture.RequestEnvelope)
    }
    $respText=$null
    if ($Capture.PSObject.Properties.Name -contains 'ResponseContent') { $respText=[string]$Capture.ResponseContent }
    elseif ($Capture.PSObject.Properties.Name -contains 'Text')         { $respText=[string]$Capture.Text }
    if ($respText) { Save-Text -Path ([IO.Path]::Combine($Dir,"$Prefix.response.xml")) -Text (Format-Xml $respText) }
    if (($Capture.PSObject.Properties.Name -contains 'Bytes') -and $Capture.Bytes) {
        Save-Bytes -Path ([IO.Path]::Combine($Dir,"$Prefix.response.bin")) -Bytes $Capture.Bytes
    }
}
function Save-CaptureCapped {
    # SIMPLE-MODE save: when -not $Full and the response body is large, persist only a truncated head
    # (the validated fact is the row COUNT, captured separately) so the run folder stays small.
    param([Parameter(Mandatory)][string]$Dir,[Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)]$Capture,[bool]$Full,[int]$MaxKB=64)
    if ($Full) { Save-Capture -Dir $Dir -Prefix $Prefix -Capture $Capture; return }
    $body=[string]$Capture.ResponseContent
    if ($body -and $body.Length -gt ($MaxKB*1024)) {
        $copy=$Capture.PSObject.Copy()
        $copy.ResponseContent = $body.Substring(0,$MaxKB*1024) + ("`n<!-- [simple mode] response truncated at {0}KB of {1} bytes; pass -FullData for the complete body -->" -f $MaxKB,$body.Length)
        Save-Capture -Dir $Dir -Prefix $Prefix -Capture $copy
    } else {
        Save-Capture -Dir $Dir -Prefix $Prefix -Capture $Capture
    }
}
# Live client-generated data (local registry / CIM / COM -- no network).
function Get-ClientIdentity {
    $cv='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; $wu='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    $g={ param($p,$n) try { (Get-ItemProperty -Path $p -Name $n -ErrorAction Stop).$n } catch { $null } }
    $major=& $g $cv 'CurrentMajorVersionNumber'; $minor=& $g $cv 'CurrentMinorVersionNumber'
    $build=& $g $cv 'CurrentBuildNumber'; $ubr=& $g $cv 'UBR'
    if ($null -eq $major){$major=10}; if ($null -eq $minor){$minor=0}
    $os=$null;$cs=$null
    try { $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {}
    try { $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}
    $wuaVer=$null; try { $ai=New-Object -ComObject Microsoft.Update.AgentInfo; $wuaVer=[string]$ai.GetInfo('ProductVersionString') } catch {}
    $suite=if($os){[int]$os.OSProductSuite}else{$null}; $oldPT=if($os){[int]$os.ProductType}else{$null}; $sku=if($os){[int]$os.OperatingSystemSKU}else{$null}
    $lcid=$null; try { $lcid=(Get-WinSystemLocale).LCID } catch { if($os){ try { $lcid=[int]$os.OSLanguage } catch {} } }
    $arch=$env:PROCESSOR_ARCHITECTURE
    [pscustomobject][ordered]@{
        CapturedUtc=(Get-Date).ToUniversalTime().ToString('o')
        ProductName=& $g $cv 'ProductName'; EditionID=& $g $cv 'EditionID'; DisplayVersion=& $g $cv 'DisplayVersion'
        ReleaseId=& $g $cv 'ReleaseId'; BuildLabEx=& $g $cv 'BuildLabEx'
        OSMajorVersion=[int]$major; OSMinorVersion=[int]$minor; OSBuildNumber=[int]$build; UBR=$ubr
        ComputerInfoVector=('{0}|{1}|{2}|{3}|{4}|{5}|0' -f $major,$minor,$build,$suite,$oldPT,$sku)
        SuiteMask=$suite; OldProductType=$oldPT; NewProductTypeSKU=$sku; OSLocaleLCID=$lcid; ProcessorArchitecture=$arch
        FeatureScoreMatchKey=('{0}.{1}.{2}' -f $arch,$major,$minor)
        ClientId_SusClientId=& $g $wu 'SusClientId'; WuaAgentVersion=$wuaVer
        SmbiosManufacturer=if($cs){[string]$cs.Manufacturer}else{$null}; SmbiosModel=if($cs){[string]$cs.Model}else{$null}
        DefaultAuServiceId=& $g $wu 'DefaultService'
    }
}
# Fixed identifiers (invariant). SLS ServiceIDs + observed fallback client.asmx endpoints.
# ============================================================================
# SHARED update-blob field extractor + helpers (GLOBAL -- used by BOTH the WSUSSS GetUpdateData harvest (B6)
# AND the FS per-OS Get-FsMetadata, so the full-scope harvest and the per-OS dataset carry the IDENTICAL
# record shape -- parity by construction. The XmlUpdateBlobCompressed decompress stays in each caller
# (it owns its scratch dir); this extractor takes the already-decoded blob + the raw segment.)
# ============================================================================
function Get-FsTypeGuess { param([string]$Title)
  if(-not $Title){ return 'unknown' }
  if($Title -match '\.NET Framework|NET Framework'){ return 'dotnet' }
  if($Title -match 'Servicing Stack|ServicingStack'){ return 'SSU' }
  if($Title -match 'Dynamic Update|SafeOS|Setup Dynamic'){ return 'DU' }
  if($Title -match 'Cumulative Update'){ return 'LCU' }
  if($Title -match [char]0x062A){ return 'LCU-localized' }
  return 'other'
}
function Get-FsYm { param([string]$Title)
  if($Title -and $Title -match '^\s*([0-9]{4})-([0-9]{2})'){ return ([int]$Matches[1]*100+[int]$Matches[2]) }
  return 0
}
function Expand-FsCompressedBlob {
  param([string]$B64,[string]$ScratchDir,[int]$TailBytes=0)
  if([string]::IsNullOrEmpty($B64)){ return $null }
  $cab=[IO.Path]::Combine($ScratchDir,([Guid]::NewGuid().ToString('N')+'.cab'))
  $out=[IO.Path]::Combine($ScratchDir,([Guid]::NewGuid().ToString('N')+'.xml'))
  try{
    [IO.File]::WriteAllBytes($cab,[Convert]::FromBase64String($B64))
    & expand.exe $cab $out 2>$null | Out-Null
    if(-not (Test-Path $out)){ return $null }
    $st=[IO.File]::OpenRead($out)
    try{
      $headLen=[int][Math]::Min([int64]2097152,$st.Length); $hbuf=New-Object byte[] $headLen; $hr=0; while($hr -lt $headLen){ $n=$st.Read($hbuf,$hr,$headLen-$hr); if($n -le 0){ break }; $hr+=$n }
      $head=[Text.Encoding]::Unicode.GetString($hbuf,0,$hr)
      if($TailBytes -gt 0 -and $st.Length -gt [int64]$headLen){
        $avail=$st.Length-[int64]$headLen; $tlen=[int][Math]::Min([int64]$TailBytes,$avail)
        $start=$st.Length-[int64]$tlen; if(($start % 2) -ne 0){ $start++; $tlen-- }
        [void]$st.Seek($start,[IO.SeekOrigin]::Begin)
        $tbuf=New-Object byte[] $tlen; $tr=0; while($tr -lt $tlen){ $n=$st.Read($tbuf,$tr,$tlen-$tr); if($n -le 0){ break }; $tr+=$n }
        return ($head + [Text.Encoding]::Unicode.GetString($tbuf,0,$tr))
      }
      return $head
    } finally{ $st.Dispose() }
  } catch { return $null }
  finally { foreach($f in @($cab,$out)){ if(Test-Path $f){ Remove-Item $f -Force -ErrorAction SilentlyContinue } } }
}
function ConvertFrom-WuUpdateSegment {
  param([Parameter(Mandatory)][string]$Seg,[AllowEmptyString()][string]$Blob,[bool]$WasCompressed,[hashtable]$UrlMap,[string[]]$ClassList)
  $seg=$Seg; $blob=$Blob; $wasComp=$WasCompressed; $urlMap=$UrlMap
  $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
  $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $lpMap=@{}; foreach($lp in [regex]::Matches($blob,'<[A-Za-z0-9]+:LocalizedProperties>(.*?)</[A-Za-z0-9]+:LocalizedProperties>','Singleline')){ $lseg=$lp.Groups[1].Value; $lng= if($lseg -match '<[A-Za-z0-9]+:Language>([^<]+)</'){ $Matches[1] } else { $null }; $lti= if($lseg -match '<[A-Za-z0-9]+:Title>([^<]+)</'){ $Matches[1] } else { $null }; if($lng -and $lti -and -not $lpMap.ContainsKey($lng)){ $lpMap[$lng]=$lti } }
            $titleEn= if($lpMap.ContainsKey('en')){ $lpMap['en'] } else { $null }; $titleJa= if($lpMap.ContainsKey('ja')){ $lpMap['ja'] } else { $null }
            $title= if($titleEn){ $titleEn } elseif($titleJa){ $titleJa } elseif($blob -match '<(?:[A-Za-z0-9]+:)?Title>([^<]+)</(?:[A-Za-z0-9]+:)?Title>'){ $Matches[1] } else { $null }
            $kb= if($blob -match '<(?:[A-Za-z0-9]+:)?KBArticleID>([^<]+)<'){ $Matches[1] } else { $null }
            $sev= if($blob -match 'MsrcSeverity="([^"]+)"'){ $Matches[1] } else { $null }
            $digs=@(); foreach($dm in [regex]::Matches($seg,'<base64Binary>([^<]+)</base64Binary>')){ $digs+=$dm.Groups[1].Value }; $digs=@($digs|Select-Object -Unique)
            $urls=@(); foreach($d in $digs){ if($urlMap.ContainsKey($d)){ $urls+=$urlMap[$d] } }
            $prods=@(); foreach($gm in [regex]::Matches($blob,'<[A-Za-z0-9]+:AtLeastOne IsCategory="true">(.*?)</[A-Za-z0-9]+:AtLeastOne>','Singleline')){ foreach($im in [regex]::Matches($gm.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $g=$im.Groups[1].Value.ToLowerInvariant(); if($ClassList -notcontains $g -and $prods -notcontains $g){ $prods+=$g } } }
            $hasBlob=([bool]$blob)
            $utype= if($blob -match 'UpdateType="([^"]+)"'){ $Matches[1] } else { $null }
            $prereqIds=@(); $catMembers=@()
            $pm2=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Prerequisites>(.*?)</(?:[A-Za-z0-9]+:)?Prerequisites>')
            if($pm2.Success){ $pblk=$pm2.Groups[1].Value
              foreach($gm2 in [regex]::Matches($pblk,'<[A-Za-z0-9]+:AtLeastOne IsCategory="true">(.*?)</[A-Za-z0-9]+:AtLeastOne>','Singleline')){ foreach($im2 in [regex]::Matches($gm2.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $catMembers+=$im2.Groups[1].Value.ToLowerInvariant() } }
              $allRef=@(); foreach($im3 in [regex]::Matches($pblk,'UpdateID="([0-9A-Fa-f-]{36})"')){ $allRef+=$im3.Groups[1].Value.ToLowerInvariant() }
              $prereqIds=@($allRef | Where-Object { $catMembers -notcontains $_ } | Select-Object -Unique)
            }
            $catMembers=@($catMembers|Select-Object -Unique)
            $supersededIds=@(); $bundledLeaf=@()
            $relm=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Relationships>(.*?)</(?:[A-Za-z0-9]+:)?Relationships>')
            if($relm.Success){ $relx=$relm.Groups[1].Value
              $sum=[regex]::Match($relx,'(?s)<(?:[A-Za-z0-9]+:)?SupersededUpdates>(.*?)</(?:[A-Za-z0-9]+:)?SupersededUpdates>')
              if($sum.Success){ foreach($im in [regex]::Matches($sum.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $supersededIds+=$im.Groups[1].Value.ToLowerInvariant() } }
              $bum=[regex]::Match($relx,'(?s)<(?:[A-Za-z0-9]+:)?BundledUpdates>(.*?)</(?:[A-Za-z0-9]+:)?BundledUpdates>')
              if($bum.Success){ foreach($idn in [regex]::Matches($bum.Groups[1].Value,'<(?:[A-Za-z0-9]+:)?UpdateIdentity\b[^>]*>')){ $el=$idn.Value; $uidm=[regex]::Match($el,'UpdateID="([0-9A-Fa-f-]{36})"'); if($uidm.Success){ $revm=[regex]::Match($el,'RevisionNumber="([0-9]+)"'); $bundledLeaf+=[pscustomobject]@{UpdateID=$uidm.Groups[1].Value; RevisionNumber=$(if($revm.Success){[int]$revm.Groups[1].Value}else{0})} } } }
            }
            $supersededIds=@($supersededIds|Select-Object -Unique); $isBundle=([bool]@($bundledLeaf).Count)
            $hasRel=([regex]::Match($blob,'<(?:[A-Za-z0-9]+:)?Relationships>').Success)
            $hasFiles=([regex]::Match($blob,'<(?:[A-Za-z0-9]+:)?File[ />]').Success)
            $tg=(Get-FsTypeGuess $title)
            $kind= if(-not $hasBlob){ 'noblob' } elseif($utype -and $utype -ne 'Software'){ $utype } elseif($tg -ne 'unknown'){ $tg } else { 'other-software' }
            [pscustomobject]@{ UpdateID=$uidH; RevisionNumber=$revH; HasBlob=$hasBlob; Compressed=$wasComp; UpdateType=$utype; Kind=$kind; Title=$title; TitleEn=$titleEn; TitleJa=$titleJa; HasEn=([bool]$titleEn); HasJa=([bool]$titleJa); KB=$kb; MsrcSeverity=$sev; HasUrl=([bool]@($urls).Count); Urls=@($urls|Select-Object -Unique); FileDigests=$digs; Products=$prods; PrereqIds=$prereqIds; CatMembers=$catMembers; IsBundle=$isBundle; BundledLeaf=@($bundledLeaf); SupersededIds=$supersededIds; HasRelationships=$hasRel; HasFiles=$hasFiles; TypeGuess=$tg }
}
# ============================================================================
$ServiceIds=@{ WindowsUpdate='9482F4B4-E343-43B6-B170-9A65BC822C77'; MicrosoftUpdate='7971F918-A847-4430-9279-4A52D1EFE18D'; DcatFlighting='8B24B027-1DEE-BABB-9A95-3517DFB9C552' }
$ObservedClientEndpoints=@{
    '9482F4B4-E343-43B6-B170-9A65BC822C77'='https://fe2cr.update.microsoft.com/v6/ClientWebService/client.asmx'
    '7971F918-A847-4430-9279-4A52D1EFE18D'='https://fe2cr.update.microsoft.com/v6/ClientWebService/client.asmx'
    '8B24B027-1DEE-BABB-9A95-3517DFB9C552'='https://fe3cr.delivery.mp.microsoft.com/ClientWebService/client.asmx'
}
# Build family -> generation label (labeling only; never a collection filter).
$GenFamilies=@(
    @{K='Server2016';N='Windows Server 2016';B=14393}, @{K='Server2019';N='Windows Server 2019';B=17763},
    @{K='Server2022';N='Windows Server 2022';B=20348}, @{K='Server2025';N='Windows Server 2025 / Win11 24H2';B=26100},
    @{K='Win11-25H2';N='Windows 11 25H2';B=26200}
)
function Resolve-Generation {
    param([int]$Build)
    foreach($f in $GenFamilies){ if($Build -eq $f.B){ return [pscustomobject]@{FriendlyName=$f.N;BuildFamily=$f.B;IsKnown=$true} } }
    return [pscustomobject]@{ FriendlyName=("Unknown/Future (build {0})" -f $Build); BuildFamily=$Build; IsKnown=$false }
}
# =============================================================================================
# WUA CLIENT-GENERATED-DATA BASELINE  (phase0 capture; schema wua-phase0-capture/1.1)
#   Ground-truth WUA client identity captured 2026-06-16 from four Windows Server DATACENTER
#   EVALUATION media (Hyper-V Gen2 VMs, ja-JP). This is the baseline for MS-WUSP client
#   (pseudo-data) validation. Factored on THREE ORTHOGONAL axes so a concrete identity is
#   COMPOSED, never hard-mixed, and so a future per-parameter change stays localized:
#       $WuaBaselineCommon  -- version-independent, all-generation-common
#       $WuaBaselineLocale  -- language axis (en-US / ja-JP)
#       $WuaBaselineSku     -- edition axis; ONLY NewProductType + SuiteMask vary by SKU
#       $WuaBaselineOs      -- OS-specific, isolated per generation (NEVER mixed 2016/19/22/25)
#   Ground-truth vs placeholder is EXPLICIT. Only DatacenterEvaluation is captured. Datacenter
#   (retail) is TBU -- to be captured next run on a patched Server 2025 Datacenter retail box
#   (same build 26100 confirms the Eval-vs-Retail delta directly). The Standard variants are TBD.
#   RefDoc cites the winnt.h PRODUCT_* constant to CONFIRM on capture, NOT to assume here.
# =============================================================================================
$WuaBaselineCommon = [ordered]@{
    OSMajorVersion=10; OSMinorVersion=0; OSServicePackMajor=0; OSServicePackMinor=0
    ProcessorArchitecture='AMD64'
    OldProductType=3                       # VER_NT_SERVER -- identical across every Server SKU
    Smbios=[ordered]@{ Manufacturer='Microsoft Corporation'; Model='Virtual Machine'; SystemFamily='Virtual Machine'; SystemSKUNumber='None'; PCSystemType='1'; BaseBoardManufacturer='Microsoft Corporation'; BaseBoardProduct='Virtual Machine'; BiosManufacturer='Microsoft Corporation'; BiosVersion='Hyper-V UEFI Release v4.1'; BiosSmbiosVersion='Hyper-V UEFI Release v4.1' }
    Note='Hyper-V Gen2 VM family; SMBIOS strings are VM-generic, not OS-version-specific. ComputerHardwareSpecification.HardwareIDs are hashed from these.'
}
$WuaBaselineLocale = [ordered]@{
    'en-US'=[ordered]@{ OSLocale=1033; CultureName='en-US' }
    'ja-JP'=[ordered]@{ OSLocale=1041; CultureName='ja-JP' }   # locale of the captured EVAL media
}
# SKU axis. OldProductType stays 3 for all; ONLY NewProductType + SuiteMask differ by edition.
#   Status: captured = read from a real machine (ground truth); TBU = to be updated from an imminent
#   capture; TBD = to be determined (no capture planned yet). NewProductType/SuiteMask are left as the
#   literal 'TBU'/'TBD' string until a real value is captured -- no derived/assumed numbers are stored.
$WuaBaselineSku = [ordered]@{
    'DatacenterEvaluation'=[ordered]@{ Status='captured'; NewProductType=80;    SuiteMask=0x190; RefDoc='PRODUCT_DATACENTER_EVALUATION_SERVER=0x50'; Note='ground truth (2026-06-16); SuiteMask 0x190 = SINGLEUSERTS|DATACENTER|TERMINAL' }
    'Datacenter'          =[ordered]@{ Status='captured'; NewProductType=8;     SuiteMask=0x190; RefDoc='PRODUCT_DATACENTER_SERVER=0x08';            Note='ground truth (2026-06-20, Server 2025 Datacenter retail build 26100.32995, ja-JP). vs Eval: SuiteMask IDENTICAL (0x190), OldProductType IDENTICAL (3), WuaAgent IDENTICAL -- ONLY NewProductType differs (80 Eval -> 8 retail)' }
    'StandardEvaluation'  =[ordered]@{ Status='TBD';      NewProductType='TBD'; SuiteMask='TBD'; RefDoc='PRODUCT_STANDARD_EVALUATION_SERVER=0x4F';   Note='variation; fill when a Standard Evaluation box is captured' }
    'Standard'            =[ordered]@{ Status='TBD';      NewProductType='TBD'; SuiteMask='TBD'; RefDoc='PRODUCT_STANDARD_SERVER=0x07';              Note='variation; fill when a Standard retail box is captured' }
}
$WuaBaselineOs = [ordered]@{
    'Server2016'=[ordered]@{ OSBuildNumber=14393; UBR=693;   ReleaseId='1607'; DisplayVersion=''; ProductName='Windows Server 2016 Datacenter Evaluation'; EditionId='ServerDatacenterEval'; BuildLabEx='14393.693.amd64fre.rs1_release.161220-1747'; WuaAgentVersion='10.0.14393.594';  WcpDllVersionAtCapture='10.0.14393.693';  SusClientId='af6e7933-884f-44ad-9040-da01970a47e1'; SmbiosUuid='BD966889-E6D8-4553-829A-A6C9231323C1'; CapturedUtc='2026-06-16T12:57:02Z' }
    'Server2019'=[ordered]@{ OSBuildNumber=17763; UBR=3650;  ReleaseId='1809'; DisplayVersion=''; ProductName='Windows Server 2019 Datacenter Evaluation'; EditionId='ServerDatacenterEval'; BuildLabEx='17763.1.amd64fre.rs5_release.180914-1434';  WuaAgentVersion='10.0.17763.3532'; WcpDllVersionAtCapture='10.0.17763.3641'; SusClientId='659d1878-0602-4e6c-a297-2bc7de47aeca'; SmbiosUuid='D3CE793E-1F7B-4500-A20D-660D7920B522'; CapturedUtc='2026-06-16T13:02:02Z' }
    'Server2022'=[ordered]@{ OSBuildNumber=20348; UBR=587;   ReleaseId='2009'; DisplayVersion='21H2'; ProductName='Windows Server 2022 Datacenter Evaluation'; EditionId='ServerDatacenterEval'; BuildLabEx='20348.1.amd64fre.fe_release.210507-1500'; WuaAgentVersion='10.0.20348.502';  WcpDllVersionAtCapture='10.0.20348.557';  SusClientId='47f1b1a7-1bbd-4189-9b35-ad0a1832903a'; SmbiosUuid='62808363-7F33-4A8F-949E-97AB99EA799B'; CapturedUtc='2026-06-16T13:06:20Z' }
    'Server2025'=[ordered]@{ OSBuildNumber=26100; UBR=32230; ReleaseId='2009'; DisplayVersion='24H2'; ProductName='Windows Server 2025 Datacenter Evaluation'; EditionId='ServerDatacenterEval'; BuildLabEx='26100.1.amd64fre.ge_release.240331-1435'; WuaAgentVersion='1451.2512.5042.0'; WcpDllVersionAtCapture='10.0.26100.32985'; SusClientId='2d4ec9f0-aa24-48f3-874b-b68342faa73c'; SmbiosUuid='9645FF23-022D-42D9-A8E7-C8B60C373E01'; CapturedUtc='2026-06-16T13:10:15Z' }
}
function Get-WuaBaselineIdentity {
    # Compose a concrete MS-WUSP client identity from the three orthogonal baseline axes. Field names
    # match Get-ClientIdentity so a future -EmulateServer path can substitute it directly. TBU/TBD SKU
    # values surface as $null with SkuResolved=$false (never an assumed number).
    param(
        [Parameter(Mandatory)][ValidateSet('Server2016','Server2019','Server2022','Server2025')][string]$Os,
        [ValidateSet('en-US','ja-JP')][string]$Locale='en-US',
        [ValidateSet('DatacenterEvaluation','Datacenter','StandardEvaluation','Standard')][string]$Sku='DatacenterEvaluation'
    )
    $o=$WuaBaselineOs[$Os]; $c=$WuaBaselineCommon; $l=$WuaBaselineLocale[$Locale]; $s=$WuaBaselineSku[$Sku]
    $skuResolved = ($s.Status -eq 'captured')
    $npt   = if($skuResolved){[int]$s.NewProductType}else{$null}
    $suite = if($skuResolved){[int]$s.SuiteMask}else{$null}
    [pscustomobject][ordered]@{
        BaselineOs=$Os; BaselineLocale=$Locale; BaselineSku=$Sku; SkuStatus=$s.Status; SkuResolved=$skuResolved
        ProductName=$o.ProductName; EditionID=$o.EditionId; DisplayVersion=$o.DisplayVersion; ReleaseId=$o.ReleaseId; BuildLabEx=$o.BuildLabEx
        OSMajorVersion=$c.OSMajorVersion; OSMinorVersion=$c.OSMinorVersion; OSBuildNumber=$o.OSBuildNumber; UBR=$o.UBR
        SuiteMask=$suite; OldProductType=$c.OldProductType; NewProductTypeSKU=$npt; OSLocaleLCID=$l.OSLocale; ProcessorArchitecture=$c.ProcessorArchitecture
        FeatureScoreMatchKey=('{0}.{1}.{2}' -f $c.ProcessorArchitecture,$c.OSMajorVersion,$c.OSMinorVersion)
        ClientId_SusClientId=$o.SusClientId; WuaAgentVersion=$o.WuaAgentVersion
        SmbiosManufacturer=$c.Smbios.Manufacturer; SmbiosModel=$c.Smbios.Model; SmbiosUuid=$o.SmbiosUuid
        ComputerInfoVector=('{0}|{1}|{2}|{3}|{4}|{5}|0' -f $c.OSMajorVersion,$c.OSMinorVersion,$o.OSBuildNumber,$(if($null -ne $suite){$suite}else{'?'}),$c.OldProductType,$(if($null -ne $npt){$npt}else{'?'}))
        WcpDllVersionAtCapture=$o.WcpDllVersionAtCapture; CapturedUtc=$o.CapturedUtc
        Provenance='wua-phase0-capture/1.1 baseline (composed)'
    }
}
function Compare-WuaIdentityToBaseline {
    # Diff the LIVE local identity against the matching captured baseline (by OS build). Surfaces the
    # local SKU-distinguishing values (NewProductType + SuiteMask) -- on a Datacenter/Standard box these
    # are exactly the values to slot into the matching TBU/TBD SKU entry.
    param([Parameter(Mandatory)]$Ident)
    $osKey=$null
    foreach($k in $WuaBaselineOs.Keys){ if([int]$WuaBaselineOs[$k].OSBuildNumber -eq [int]$Ident.OSBuildNumber){ $osKey=$k; break } }
    $rows=[System.Collections.Generic.List[object]]::new()
    if($osKey){
        $b=$WuaBaselineOs[$osKey]
        $pairs=@(
            @{F='OSBuildNumber'; B=$b.OSBuildNumber;   L=$Ident.OSBuildNumber}
            @{F='UBR';           B=$b.UBR;             L=$Ident.UBR}
            @{F='WuaAgentVersion';B=$b.WuaAgentVersion;L=$Ident.WuaAgentVersion}
            @{F='SusClientId';   B=$b.SusClientId;     L=$Ident.ClientId_SusClientId}
        )
        foreach($p in $pairs){ $rows.Add([pscustomobject]@{ Field=$p.F; Baseline="$($p.B)"; Local="$($p.L)"; Match=("$($p.B)" -eq "$($p.L)") }) }
    }
    [pscustomobject]@{
        MatchedOs=$osKey
        LocalSku=[ordered]@{ NewProductType=$Ident.NewProductTypeSKU; SuiteMask=$Ident.SuiteMask; OldProductType=$Ident.OldProductType; OSLocaleLCID=$Ident.OSLocaleLCID }
        Diff=$rows
    }
}
# request-body helpers
function Get-CookieWuspXml { param([string]$Enc) if($Enc){"<cookie><EncryptedData>$Enc</EncryptedData></cookie>"}else{'<cookie></cookie>'} }
function Get-ArrayOfIntXml { param([string]$Name,[int[]]$Ids) if(-not $Ids -or $Ids.Count -eq 0){"<$Name />"}else{"<$Name>"+(($Ids|ForEach-Object{"<int>$_</int>"}) -join '')+"</$Name>"} }

# ===================================================================================
# ENVIRONMENT-CAPTURE SUPPORT  (ported from WUA Phase-0; wsusscn2.cab feature excluded)
#   Investigates the Windows OS host running this survey = the client-generated data (1) layer.
# ===================================================================================
# native helpers: RtlGetVersion + GetProductInfo (exact client-state fields)
$script:TlbCompileErr=$null
try {
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NativeOs {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct OSVERSIONINFOEXW {
    public int dwOSVersionInfoSize, dwMajorVersion, dwMinorVersion, dwBuildNumber, dwPlatformId;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string szCSDVersion;
    public ushort wServicePackMajor, wServicePackMinor, wSuiteMask;
    public byte wProductType, wReserved;
  }
  [DllImport("ntdll.dll")] static extern int RtlGetVersion(ref OSVERSIONINFOEXW v);
  [DllImport("kernel32.dll")] static extern bool GetProductInfo(int a,int b,int c,int d, out int t);
  public static string Get() {
    var v=new OSVERSIONINFOEXW(); v.dwOSVersionInfoSize=Marshal.SizeOf(typeof(OSVERSIONINFOEXW));
    RtlGetVersion(ref v); int sku=0; GetProductInfo(v.dwMajorVersion,v.dwMinorVersion,0,0, out sku);
    return string.Format("{0}|{1}|{2}|{3}|{4}|{5}|{6}",
      v.dwMajorVersion,v.dwMinorVersion,v.dwBuildNumber,v.wSuiteMask,v.wProductType,sku,v.wServicePackMajor);
  }
}
'@
} catch { }
# COM type-library dumper via a live COM object (universal; no file path needed)
try {
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using CT = System.Runtime.InteropServices.ComTypes;
public static class TlbDump {
  [ComImport, Guid("00020400-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IDispatchLite {
    [PreserveSig] int GetTypeInfoCount(out int c);
    void GetTypeInfo(int i, int lcid, out CT.ITypeInfo ti);
  }
  static string Name(CT.ITypeInfo ti, int memid){
    try{ string[] n=new string[1]; int c; ti.GetNames(memid, n, 1, out c); return (c>0)?n[0]:""; }catch{ return ""; }
  }
  static string Enumerate(CT.ITypeLib tlb, string srcLabel){
    var sb=new StringBuilder(); int tc=tlb.GetTypeInfoCount();
    sb.AppendLine("# typelib via "+srcLabel+"  types="+tc);
    for(int i=0;i<tc;i++){
      CT.ITypeInfo ti=null; tlb.GetTypeInfo(i, out ti);
      string nm,doc,hf; int hc; tlb.GetDocumentation(i, out nm, out doc, out hc, out hf);
      IntPtr pTA=IntPtr.Zero; ti.GetTypeAttr(out pTA);
      var ta=(CT.TYPEATTR)Marshal.PtrToStructure(pTA, typeof(CT.TYPEATTR));
      Guid g=ta.guid; CT.TYPEKIND k=ta.typekind; int cF=ta.cFuncs; int cV=ta.cVars;
      ti.ReleaseTypeAttr(pTA);
      sb.AppendLine(string.Format("TYPE  {0,-34} kind={1,-11} guid={{{2}}}  funcs={3} vars={4}", nm, k, g, cF, cV));
      if(k==CT.TYPEKIND.TKIND_INTERFACE || k==CT.TYPEKIND.TKIND_DISPATCH){
        for(int f=0;f<cF;f++){
          IntPtr pFD=IntPtr.Zero; ti.GetFuncDesc(f, out pFD);
          var fd=(CT.FUNCDESC)Marshal.PtrToStructure(pFD, typeof(CT.FUNCDESC));
          string fn=Name(ti, fd.memid); ti.ReleaseFuncDesc(pFD);
          if(fn.Length>0) sb.AppendLine("    fn   "+fn);
        }
      } else if(k==CT.TYPEKIND.TKIND_ENUM){
        for(int v=0;v<cV;v++){
          IntPtr pVD=IntPtr.Zero; ti.GetVarDesc(v, out pVD);
          var vd=(CT.VARDESC)Marshal.PtrToStructure(pVD, typeof(CT.VARDESC));
          string vn=Name(ti, vd.memid); object val=null;
          try{ val=Marshal.GetObjectForNativeVariant(vd.desc.lpvarValue); }catch{}
          ti.ReleaseVarDesc(pVD);
          sb.AppendLine("    enum "+vn+" = "+(val==null?"?":val.ToString()));
        }
      }
    }
    return sb.ToString();
  }
  public static string DumpFromObject(object comObj){
    var disp=(IDispatchLite)comObj;
    CT.ITypeInfo ti; disp.GetTypeInfo(0,0, out ti);
    CT.ITypeLib tlb; int idx; ti.GetContainingTypeLib(out tlb, out idx);
    return Enumerate(tlb, "live-object GetContainingTypeLib");
  }
}
'@
} catch { $script:TlbCompileErr=$_.Exception.Message }

function ConvertTo-Array { param($Collection)
    $out=@(); if($null -eq $Collection){return ,$out}
    if($Collection -is [string] -or $Collection -is [ValueType]){ return ,@($Collection) }
    try{ $n=$Collection.Count; for($i=0;$i -lt $n;$i++){$out+=$Collection.Item($i)} }
    catch{ try{ foreach($x in $Collection){$out+=$x} }catch{ $out=@($Collection) } }
    return ,$out
}
function Get-CategoryNames { param($Categories)
    $out=@(); if($null -eq $Categories){ return ,$out }
    try{ $n=$Categories.Count
        for($i=0;$i -lt $n;$i++){ $c=$Categories.Item($i); $nm=$null
            try{ $nm=[string]$c.Name }catch{ try{ $nm=[string]$c }catch{} }
            if(-not [string]::IsNullOrEmpty($nm)){ $out+=$nm } }
    }catch{ try{ foreach($c in $Categories){ $nm=$null; try{$nm=[string]$c.Name}catch{}; if($nm){$out+=$nm} } }catch{} }
    return ,$out
}
function Get-IfaceIID { param($ComObj)
    try{ $tn=($ComObj|Get-Member|Select-Object -First 1 -ExpandProperty TypeName); if($tn -match '#\{(.+)\}'){return $Matches[1]} }catch{}
    return $null
}
function Get-CimSafe { param($Class,$Props)
    $o=$null
    try{ $o=Get-CimInstance -ClassName $Class -ErrorAction Stop | Select-Object -First 1 }
    catch{ try{ $o=Get-WmiObject -Class $Class -ErrorAction Stop | Select-Object -First 1 }catch{} }
    $r=[ordered]@{}; foreach($pr in $Props){ $r[$pr]=$(try{ [string]$o.$pr }catch{ $null }) }; return $r
}
function Invoke-DumpUpdates { param($SearchResult,[int]$Max)
    $arr=@(); $ups=$SearchResult.Updates; $n=[Math]::Min($ups.Count,$Max)
    for($i=0;$i -lt $n;$i++){ $u=$ups.Item($i)
        $kb=@();try{$kb=ConvertTo-Array $u.KBArticleIDs}catch{}
        $sup=@();try{$sup=ConvertTo-Array $u.SupersededUpdateIDs}catch{}
        $cat=@();try{$cat=Get-CategoryNames $u.Categories}catch{}
        $bun=@();try{$bun=ConvertTo-Array $u.BundledUpdates|ForEach-Object{$_.Identity.UpdateID}}catch{}
        $arr+=[ordered]@{ updateID=$(try{$u.Identity.UpdateID}catch{$null}); rev=$(try{$u.Identity.RevisionNumber}catch{$null})
            title=$(try{$u.Title}catch{$null}); kbArticleIDs=$kb; msrcSeverity=$(try{$u.MsrcSeverity}catch{$null})
            supersededUpdateIDs=$sup; categories=$cat; bundledUpdateIDs=$bun
            rebootBehavior=$(try{$u.InstallationBehavior.RebootBehavior}catch{$null}) }
    }
    $iid=$null; if($ups.Count -gt 0){ $iid=Get-IfaceIID $ups.Item(0) }
    return @{ totalReturned=$ups.Count; updateInterfaceIID=$iid; updates=$arr }
}

# PART 0 worker: comprehensive Windows OS environment investigation -> $EnvDir.
function Invoke-EnvironmentCapture {
    param([Parameter(Mandatory)][string]$EnvDir,[int]$MaxUpdates=40,[string]$Label)
    Set-StrictMode -Off
    $ErrorActionPreference='Continue'
    $ssDefault=0
    $report=[ordered]@{ schema='wua-phase0-capture/1.1 (integrated)'; timestampUtc=(Get-Date).ToUniversalTime().ToString('o'); label=$Label; sections=[ordered]@{} }
    function Set-Section { param([string]$Name,[string]$Status,$Data)
        $report.sections[$Name]=[ordered]@{ status=$Status; data=$Data }
        $tag=switch($Status){ 'PASS'{'[ PASS ]'} 'FAIL'{'[ FAIL ]'} 'SKIP'{'[ SKIP ]'} 'WARN'{'[ WARN ]'} default{'[ .... ]'} }
        Write-Host ("    {0}  env/{1}" -f $tag,$Name)
    }

    # SECTION 1: host/OS identity + native client-state record
    try {
        $cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cs=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $cpu=Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        $cult=Get-Culture
        $native=$null; try{ $native=[NativeOs]::Get() }catch{}
        $n=@{}; if($native){ $pp=$native -split '\|'; $n=@{ major=[int]$pp[0]; minor=[int]$pp[1]; build=[int]$pp[2]; suiteMask=[int]$pp[3]; oldProductType=[int]$pp[4]; newProductType=[int]$pp[5]; spMajor=[int]$pp[6] } }
        $host1=[ordered]@{
            psVersion=$PSVersionTable.PSVersion.ToString(); currentBuild=$cv.CurrentBuildNumber; ubr=$cv.UBR
            displayVersion=$cv.DisplayVersion; releaseId=$cv.ReleaseId; productName=$cv.ProductName; editionId=$cv.EditionID
            installationType=$cv.InstallationType; buildLabEx=$cv.BuildLabEx
            wmiBuildNumber=$os.BuildNumber; wmiCaption=$os.Caption; wmiOSArchitecture=$os.OSArchitecture
            wmiProductType=$os.ProductType; wmiOSSku=$os.OperatingSystemSKU; wmiOSLanguage=$os.OSLanguage
            cpuArchitecture=$cpu.Architecture; cpuAddressWidth=$cpu.AddressWidth
            cultureName=$cult.Name; cultureLCID=$cult.LCID; muiLanguages=@($os.MUILanguages)
        }
        $clientState=[ordered]@{
            OSMajorVersion=$(if($n.major){$n.major}else{10}); OSMinorVersion=$(if($null -ne $n.minor){$n.minor}else{0})
            OSBuildNumber=$(if($n.build){$n.build}else{[int]$cv.CurrentBuildNumber}); UBR=$cv.UBR
            OSServicePackMajor=$(if($null -ne $n.spMajor){$n.spMajor}else{0}); SuiteMask=$n.suiteMask
            OldProductType=$n.oldProductType; NewProductType=$n.newProductType; OSLocale=$cult.LCID
            ProcessorArchitecture=$(if($cpu.Architecture -eq 9){'AMD64'}else{"ARCH$($cpu.Architecture)"})
            FeatureScoreMatchingKey=$(if($cpu.Architecture -eq 9){"AMD64.$($n.major).$($n.minor)"}else{$null})
            OSDescription=$cv.ProductName
        }
        Set-Section '01.host-identity' 'PASS' ([ordered]@{ host=$host1; nativeOsRaw=$native; clientStateRecord=$clientState })
        $script:EnvBuild="$($cv.CurrentBuildNumber).$($cv.UBR)"; $script:EnvInstType=$cv.InstallationType
    } catch { Set-Section '01.host-identity' 'FAIL' $_.Exception.Message; $script:EnvBuild='unknown'; $script:EnvInstType='unknown' }

    $isAdmin=$false
    try{ $isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }catch{}

    # SECTION 2: WUA binary / DLL inventory
    try {
        $sys=Join-Path $env:windir 'System32'
        $names=@('wuapi.dll','wuaueng.dll','wups.dll','wups2.dll','wuauclt.exe','wuautoappupdate.dll','wudriver.dll','wuuhext.dll','wuwebv.dll','UsoCore.dll','MoUsoCoreWorker.exe','usoclient.exe','wuapihost.exe','wuredir.dll','wcp.dll','cbscore.dll','dismapi.dll')
        $inv=@()
        foreach($nm in $names){ $p=Join-Path $sys $nm
            if(Test-Path $p){ $fi=Get-Item $p; $vi=$fi.VersionInfo
                $sha=$null; try{ $sha=(Get-FileHash $p -Algorithm SHA256 -ErrorAction Stop).Hash }catch{}
                $sig=$null; try{ $s=Get-AuthenticodeSignature $p -ErrorAction Stop; $sig=@{ status="$($s.Status)"; signer=$(if($s.SignerCertificate){$s.SignerCertificate.Subject}else{$null}) } }catch{}
                $inv+=[ordered]@{ name=$nm; fileVersion=$vi.FileVersion; productVersion=$vi.ProductVersion; lengthBytes=$fi.Length; lastWriteUtc=$fi.LastWriteTimeUtc.ToString('o'); sha256=$sha; signature=$sig } }
        }
        Set-Section '02.dll-inventory' 'PASS' @{ system32=$sys; count=$inv.Count; files=$inv }
        try{ $inv | ForEach-Object { [pscustomobject]@{ name=$_.name; fileVersion=$_.fileVersion; productVersion=$_.productVersion; sha256=$_.sha256; lastWriteUtc=$_.lastWriteUtc } } | Export-Csv -Path (Join-Path $EnvDir 'dll-inventory.csv') -NoTypeInformation -Encoding UTF8 }catch{}
    } catch { Set-Section '02.dll-inventory' 'FAIL' $_.Exception.Message }

    # SECTION 3: WUA interface inventory (registry) + type library (best-effort)
    try {
        $wuaPattern='^(IUpdate|IWindowsDriverUpdate|ICategory|ISearchResult|IUpdateSession|IUpdateService|IUpdateServiceManager|IUpdateServiceRegistration|IUpdateHistoryEntry|IUpdateCollection|IUpdateException|IInstallationResult|IDownloadResult|ISystemInformation|IAutomaticUpdates|IUpdateInstaller|IUpdateDownloader|IUpdateSearcher|IImageInformation|ICategoryCollection|IStringCollection)'
        $ifaces=@()
        try { $rootK=[Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('Interface')
            foreach($iid in $rootK.GetSubKeyNames()){ try{ $k=$rootK.OpenSubKey($iid); if($null -eq $k){continue}; $nm=$k.GetValue($null); $k.Close(); if($nm -and ($nm -match $wuaPattern)){ $ifaces+=[pscustomobject]@{ name="$nm"; iid=$iid } } }catch{} }
            $rootK.Close() } catch {}
        $ifaceNames=@($ifaces | Select-Object -ExpandProperty name)
        $ifaceVers=[ordered]@{}
        foreach($base in 'IUpdate','IUpdateSearcher','IUpdateSession','IUpdateService','IUpdateServiceManager','IWindowsDriverUpdate','IUpdateHistoryEntry','IUpdateInstaller','IUpdateDownloader'){
            $pat='^'+[regex]::Escape($base)+'\d*$'; $ifaceVers[$base]=@($ifaceNames | Where-Object { $_ -match $pat } | Select-Object -Unique | Sort-Object) }
        try{ $ifaces | Sort-Object name | ForEach-Object { '{0,-44} {1}' -f $_.name, $_.iid } | Out-File -FilePath (Join-Path $EnvDir 'interfaces-registry.txt') -Encoding ascii }catch{}
        $tlbCompiled=([System.Management.Automation.PSTypeName]'TlbDump').Type -ne $null
        $diag=[ordered]@{ tlbTypeCompiled=$tlbCompiled; tlbCompileError=$script:TlbCompileErr; strategy=$null; errors=[ordered]@{} }
        $tl=$null
        if($tlbCompiled){ try{ $sess03=New-Object -ComObject Microsoft.Update.Session; $tl=[TlbDump]::DumpFromObject($sess03); if($tl){$diag.strategy='live-object'} }catch{ $diag.errors['liveObject']=$_.Exception.Message } }
        $typelibFile=$null; $typeCount=$null; $enumCount=$null
        if($tl){ $typelibFile='typelib-wuapi.txt'
            [System.IO.File]::WriteAllText((Join-Path $EnvDir $typelibFile), $tl, (New-Object System.Text.UTF8Encoding($false)))
            $typeCount=([regex]::Matches($tl,"(?m)^TYPE\s")).Count; $enumCount=([regex]::Matches($tl,"kind=TKIND_ENUM")).Count
            foreach($base in @($ifaceVers.Keys)){ $vs=@(); ([regex]::Matches($tl,"TYPE\s+($base\d*)\s")) | ForEach-Object { $vs += $_.Groups[1].Value }
                $ifaceVers[$base]=@(@($ifaceVers[$base]) + $vs | Where-Object {$_} | Select-Object -Unique | Sort-Object) } }
        $st= if($ifaces.Count -le 0){'FAIL'} elseif(-not $tl){'WARN'} else {'PASS'}
        Set-Section '03.typelib-wuapi' $st ([ordered]@{ registryInterfaceCount=$ifaces.Count; interfaceVersions=$ifaceVers; interfacesFile='interfaces-registry.txt'; typelibStrategy=$diag.strategy; typeCount=$typeCount; enumCount=$enumCount; dumpFile=$typelibFile; diag=$diag })
    } catch { Set-Section '03.typelib-wuapi' 'FAIL' $_.Exception.Message }

    # SECTION 4: live COM object model + agent version
    $session=$null
    try {
        $session=New-Object -ComObject Microsoft.Update.Session
        $searcher=$session.CreateUpdateSearcher()
        $svcMgr=New-Object -ComObject Microsoft.Update.ServiceManager
        $sysInfo=New-Object -ComObject Microsoft.Update.SystemInfo
        $agent=@{}; try{ $ai=New-Object -ComObject Microsoft.Update.AgentInfo; $agent=@{ productVersionString=$ai.GetInfo('ProductVersionString'); apiMajorVersion=$ai.GetInfo('ApiMajorVersion'); apiMinorVersion=$ai.GetInfo('ApiMinorVersion') } }catch{}
        function MemberDump($o){ ($o|Get-Member -MemberType Property,Method|Select-Object Name,MemberType|ForEach-Object{ "$($_.MemberType.ToString().Substring(0,1)):$($_.Name)" }) }
        Set-Section '04.com-object-model' 'PASS' ([ordered]@{ agent=$agent; sessionIID=Get-IfaceIID $session; searcherIID=Get-IfaceIID $searcher; svcMgrIID=Get-IfaceIID $svcMgr; sessionMembers=@(MemberDump $session); searcherMembers=@(MemberDump $searcher); svcMgrMembers=@(MemberDump $svcMgr); sysInfoMembers=@(MemberDump $sysInfo) })
    } catch { Set-Section '04.com-object-model' 'FAIL' $_.Exception.Message }

    # SECTION 5: registered services / ServiceID model
    try {
        if($null -eq $svcMgr){ $svcMgr=New-Object -ComObject Microsoft.Update.ServiceManager }
        $svcs=ConvertTo-Array $svcMgr.Services | ForEach-Object {
            [ordered]@{ name=$_.Name; serviceID=$_.ServiceID; isScanPackageService=$(try{$_.IsScanPackageService}catch{$null}); isManaged=$(try{$_.IsManaged}catch{$null}); offersWindowsUpdates=$(try{$_.OffersWindowsUpdates}catch{$null}); isDefaultAUService=$(try{$_.IsDefaultAUService}catch{$null}); serviceUrl=$(try{$_.ServiceUrl}catch{$null}) } }
        Set-Section '05.services' 'PASS' @{ count=$svcs.Count; services=$svcs }
    } catch { Set-Section '05.services' 'FAIL' $_.Exception.Message }

    # SECTION 6: installed-state oracle (history + hotfix + .NET + servicing stack)
    try {
        if($null -eq $session){ $session=New-Object -ComObject Microsoft.Update.Session }
        $searcher=$session.CreateUpdateSearcher()
        $total=$searcher.GetTotalHistoryCount(); $take=[Math]::Min($total,500)
        $bucket=@{}; $servicing=@()
        if($take -gt 0){ $hist=$searcher.QueryHistory(0,$take)
            for($i=0;$i -lt $hist.Count;$i++){ $h=$hist.Item($i); $cat=$null
                try{ $cats=Get-CategoryNames $h.Categories; if($cats.Count -gt 0){$cat=$cats[0]} }catch{}
                $key=$(if($cat){$cat}else{'(none)'}); if(-not $bucket.ContainsKey($key)){$bucket[$key]=0}; $bucket[$key]++
                if($cat -ne 'Microsoft Defender Antivirus' -and $servicing.Count -lt $MaxUpdates){
                    $servicing+=[ordered]@{ title=$(try{$h.Title}catch{$null}); category=$cat; updateID=$(try{$h.UpdateIdentity.UpdateID}catch{$null}); rev=$(try{$h.UpdateIdentity.RevisionNumber}catch{$null}); operation=$(try{$h.Operation}catch{$null}); resultCode=$(try{$h.ResultCode}catch{$null}); date=$(try{$h.Date.ToString('o')}catch{$null}); serverSelection=$(try{$h.ServerSelection}catch{$null}); clientAppID=$(try{$h.ClientApplicationID}catch{$null}) } } } }
        $hotfix=@(); try{ $hotfix=Get-HotFix -ErrorAction Stop | Select-Object HotFixID,Description,InstalledOn | ForEach-Object{ [ordered]@{ id=$_.HotFixID; description=$_.Description; installedOn=$(if($_.InstalledOn){$_.InstalledOn.ToString('o')}else{$null}) } } }catch{}
        $dotnet=[ordered]@{}
        try{ $v4=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue; if($v4){ $dotnet['v4Full']=@{ release=$v4.Release; version=$v4.Version } }
             $v35=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction SilentlyContinue; if($v35){ $dotnet['v3_5']=@{ install=$v35.Install; version=$v35.Version } } }catch{}
        $ss=[ordered]@{}
        try{ $wcp=$null
            foreach($p in @((Join-Path $env:windir 'servicing\wcp.dll'),(Join-Path $env:windir 'System32\wcp.dll'),(Join-Path $env:windir 'WinSxS\wcp.dll'))){ if(Test-Path $p){ $wcp=(Get-Item $p -ErrorAction SilentlyContinue).VersionInfo.FileVersion; if($wcp){break} } }
            if(-not $wcp){ try{ $cand=Get-ChildItem (Join-Path $env:windir 'WinSxS') -Filter 'wcp.dll' -Recurse -ErrorAction SilentlyContinue | Sort-Object {$_.VersionInfo.FileVersion} -Descending | Select-Object -First 1; if($cand){ $wcp=$cand.VersionInfo.FileVersion } }catch{} }
            $ss['wcpDllVersion']=$wcp }catch{ $ss['wcpDllVersion']=$null }
        try{ $ss['cbsRegPresent']=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' }catch{}
        Set-Section '06.installed-state' 'PASS' ([ordered]@{ historyTotal=$total; historyScanned=$take; categoryBuckets=$bucket; servicingSample=$servicing; servicingSampleCount=$servicing.Count; hotfixCount=$hotfix.Count; hotfixes=$hotfix; dotnet=$dotnet; servicingStack=$ss })
    } catch { Set-Section '06.installed-state' 'FAIL' $_.Exception.Message }

    # SECTION 7: local persisted stores
    try {
        $sd=Join-Path $env:windir 'SoftwareDistribution'; $edb=Join-Path $sd 'DataStore\DataStore.edb'; $wuLogs=Join-Path $env:windir 'Logs\WindowsUpdate'
        $wsus=$null; try{ $wsus=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue }catch{}
        Set-Section '07.local-stores' 'PASS' ([ordered]@{ dataStoreEdbExists=Test-Path $edb; dataStoreEdbBytes=$(if(Test-Path $edb){(Get-Item $edb).Length}else{$null}); downloadDirExists=Test-Path (Join-Path $sd 'Download'); wuEtlCount=$(if(Test-Path $wuLogs){(Get-ChildItem $wuLogs -Filter *.etl -ErrorAction SilentlyContinue).Count}else{0}); wuRegKeyExists=Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'; wsusPolicyServer=$(if($wsus){$wsus.WUServer}else{$null}) })
    } catch { Set-Section '07.local-stores' 'FAIL' $_.Exception.Message }

    # SECTION 8a (wsusscn2.cab offline scan): intentionally NOT implemented (excluded per request).
    Set-Section '08a.offline-scan' 'SKIP' 'wsusscn2.cab feature intentionally excluded from this harness'

    Set-Section '08b.online-scan' 'SKIP' 'online WUA scan removed (WUA-API domain is local-only)'
    Set-Section '08c.dism-packages' 'SKIP' 'DISM servicing-package scan removed (WUA-API domain is local-only)'

    # SECTION 9: MS-WUSP client-generated identity (section 23.8): SusClientId, SMBIOS hardware-id inputs, InstalledNonLeafUpdateIDs proxy
    try {
        $clientId=[ordered]@{ susClientId=$null; susClientIdValidation=$null; source='HKLM\...\WindowsUpdate' }
        try{ $wuKey='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'; $p=Get-ItemProperty $wuKey -ErrorAction SilentlyContinue
             if($p){ $clientId.susClientId=[string]$p.SusClientId; $clientId.susClientIdValidation=[string]$p.SusClientIDValidation } }catch{}
        $hw=[ordered]@{
            note='Raw SMBIOS fields; MS-WUSP ComputerHardwareSpecification.HardwareIDs are derived (hashed) from these.'
            csProduct=Get-CimSafe 'Win32_ComputerSystemProduct' @('UUID','Vendor','Name','Version','IdentifyingNumber')
            computerSystem=Get-CimSafe 'Win32_ComputerSystem' @('Manufacturer','Model','SystemFamily','SystemSKUNumber','PCSystemType')
            baseBoard=Get-CimSafe 'Win32_BaseBoard' @('Manufacturer','Product','Version')
            bios=Get-CimSafe 'Win32_BIOS' @('Manufacturer','SMBIOSBIOSVersion','Version','ReleaseDate')
        }
        $nonLeaf=[ordered]@{
            captureMode='PROXY-NETWORK-FREE (Option A)'; isTrueSet=$false
            note='NOT the true non-leaf set. WUA does not expose installed detectoid/category IDs via a high-level offline API. Resolve the real InstalledNonLeafUpdateIDs from a live SyncUpdates trace or a DataStore.edb parse before using for MS-WUSP.'
            installedCategoryNames=@(); installedLeafSample=@()
        }
        try{ $sess9=New-Object -ComObject Microsoft.Update.Session; $srch9=$sess9.CreateUpdateSearcher(); $tot9=$srch9.GetTotalHistoryCount(); $take9=[Math]::Min($tot9,500)
            if($take9 -gt 0){ $hist9=$srch9.QueryHistory(0,$take9); $catSet=New-Object System.Collections.Generic.HashSet[string]; $leafIds=@()
                for($i=0;$i -lt $hist9.Count;$i++){ $h=$hist9.Item($i)
                    try{ foreach($cn in (Get-CategoryNames $h.Categories)){ [void]$catSet.Add($cn) } }catch{}
                    try{ $uid=[string]$h.UpdateIdentity.UpdateID; if($uid -and $leafIds.Count -lt $MaxUpdates){ $leafIds+=$uid } }catch{} }
                $nonLeaf.installedCategoryNames=@($catSet) | Sort-Object; $nonLeaf.installedLeafSample=$leafIds }
        }catch{ $nonLeaf.note=$nonLeaf.note+' [history-proxy capture failed: '+$_.Exception.Message+']' }
        Set-Section '09.wusp-client-identity' 'PASS' ([ordered]@{ clientId=$clientId; hardwareIdInputs=$hw; installedNonLeafUpdateIDs=$nonLeaf })
    } catch { Set-Section '09.wusp-client-identity' 'FAIL' $_.Exception.Message }

    # finalize env/: report JSON (no BOM) + ASCII manifest
    $json=$report | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText((Join-Path $EnvDir 'phase0-report.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
    $pass=($report.sections.GetEnumerator()|Where-Object{$_.Value.status -eq 'PASS'}).Count
    $warn=($report.sections.GetEnumerator()|Where-Object{$_.Value.status -eq 'WARN'}).Count
    $fail=($report.sections.GetEnumerator()|Where-Object{$_.Value.status -eq 'FAIL'}).Count
    $skip=($report.sections.GetEnumerator()|Where-Object{$_.Value.status -eq 'SKIP'}).Count
    $csr=$report.sections['01.host-identity'].data.clientStateRecord
    $agent=$report.sections['04.com-object-model'].data.agent
    $ifv=$report.sections['03.typelib-wuapi'].data.interfaceVersions
    $man=@()
    $man+='WUA ENVIRONMENT CAPTURE MANIFEST (PART 0)'
    $man+="Label            : $Label"
    $man+="InstallationType : $($script:EnvInstType)"
    $man+="Build.UBR        : $($script:EnvBuild)"
    $man+="EditionID        : $($report.sections['01.host-identity'].data.host.editionId)"
    if($csr){ $man+="ClientState      : OSBuild=$($csr.OSBuildNumber) UBR=$($csr.UBR) Suite=0x$('{0:X}' -f [int]$csr.SuiteMask) OldPT=$($csr.OldProductType) NewPT=$($csr.NewProductType) LCID=$($csr.OSLocale) Arch=$($csr.ProcessorArchitecture)" }
    if($agent){ $man+="WUA Agent        : ProductVer=$($agent.productVersionString) Api=$($agent.apiMajorVersion).$($agent.apiMinorVersion)" }
    if($ifv){ $man+="IUpdate ifaces   : $((@($ifv.IUpdate)) -join ', ')"; $man+="Searcher ifaces  : $((@($ifv.IUpdateSearcher)) -join ', ')" }
    $man+="Sections         : PASS=$pass WARN=$warn FAIL=$fail SKIP=$skip"
    [System.IO.File]::WriteAllText((Join-Path $EnvDir 'manifest.txt'), ($man -join "`r`n"), (New-Object System.Text.ASCIIEncoding))
    return [ordered]@{ Pass=$pass; Warn=$warn; Fail=$fail; Skip=$skip; Build=$script:EnvBuild; InstallationType=$script:EnvInstType; AgentVersion=$(if($agent){$agent.productVersionString}else{$null}) }
}

# ===================================================================================
# RUN INIT  (shared -- single point-in-time snapshot of BOTH protocols)
# ===================================================================================
$runName='WuProtocolSurvey'; if($Label){$runName="$runName-$Label"}
$dir=New-RunDir -Name $runName
$wuspDir=[IO.Path]::Combine($dir,'wusp'); [IO.Directory]::CreateDirectory($wuspDir)|Out-Null
$wsusssDir=[IO.Path]::Combine($dir,'wsusss'); [IO.Directory]::CreateDirectory($wsusssDir)|Out-Null
$capturedUtc=(Get-Date).ToUniversalTime().ToString('o')
Write-Host "[*] run dir: $dir"
Write-Host "[*] script version: $SurveyVersionTag"
Write-Host "[*] CapturedUtc (single snapshot for both protocols): $capturedUtc"

$coverage=[System.Collections.Generic.List[object]]::new()
$script:opStart = $null
function Start-Op {
    # main-item START line: timestamp + [proto step] op -- start
    param([string]$Proto,[string]$Step,[string]$Op)
    $script:opStart=[DateTime]::Now
    Write-Host ("  [{0}] [{1} {2}] {3} -- start" -f $script:opStart.ToString('HH:mm:ss.fff'),$Proto,$Step,$Op)
}
function Add-Cov {
    # main-item COMPLETE line: timestamp + [proto step] op -> status (duration) note
    # If -Verdict (a Test-ResponseConformance result) is supplied, status reflects SPEC CONFORMANCE,
    # NOT raw HTTP -- this is the deliberate replacement of the "200 == success" standard.
    param([string]$Proto,[string]$Step,[string]$Op,$Cap,[string]$Note='',$Verdict=$null)
    $conf=$null
    if ($null -ne $Verdict) {
        $conf=[bool]$Verdict.Conformant
        $status= if($conf){"CONFORMANT($($Verdict.HttpStatus))"} else {"NON-CONFORMANT($($Verdict.HttpStatus): $(@($Verdict.Failures) -join ','))"}
        [void]$Script:WsusssVerdicts.Add($Verdict)
    } else {
        # legacy HTTP-status line, kept ONLY for ops without a contract yet (e.g. B6-B17, WUSP). These read
        # 'ok' from a 2xx and are NOT conformance-judged -- flagged so the gap is visible, not hidden.
        $status= if($null -eq $Cap){'not-attempted'} elseif($Cap.PSObject.Properties.Name -contains 'NotHosted' -and $Cap.NotHosted){"endpoint-not-hosted($($Cap.StatusCode))"} elseif($Cap.IsSuccess){"http-2xx-uncontracted($($Cap.StatusCode))"} else {"fault($($Cap.StatusCode))"}
    }
    $coverage.Add([pscustomobject][ordered]@{ protocol=$Proto; step=$Step; operation=$Op; status=$status; conformant=$conf; note=$Note })
    $end=[DateTime]::Now
    $dur= if($script:opStart){ ($end-$script:opStart).TotalSeconds } else { 0.0 }
    $noteStr= if($Note){" $Note"}else{''}
    Write-Host ("  [{0}] [{1} {2}] {3} -> {4} ({5:N2}s){6}" -f $end.ToString('HH:mm:ss.fff'),$Proto,$Step,$Op,$status,$dur,$noteStr)
    $script:opStart=$null
}
function Write-Detail {
    # non-main (sub) message: indented, timestamp + summary; optional further-indented detail line
    param([string]$Summary,[string]$Detail='')
    Write-Host ("    [{0}] {1}" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$Summary)
    if($Detail){ Write-Host ("        {0}" -f $Detail) }
}

# [0] client identity (shared)
Write-Host '[0] client identity (client-generated data) ...'
$ident=Get-ClientIdentity
$gen=Resolve-Generation -Build $ident.OSBuildNumber
Save-Json -Path ([IO.Path]::Combine($dir,'00.client-identity.json')) -Object $ident
Save-Json -Path ([IO.Path]::Combine($dir,'00.generation.json'))      -Object $gen
Write-Host ("    {0}  build {1}.{2}  vector {3}" -f $gen.FriendlyName,$ident.OSBuildNumber,$ident.UBR,$ident.ComputerInfoVector)
$serviceId=$ServiceIds[$Service]

# [0b] PART 0: comprehensive Windows OS environment investigation (client-generated data layer)
$envSummary=$null
if ($runWua) {
    Write-Host ''
    Write-Host '=== PART 0: ENVIRONMENT (WUA / OS host investigation) ==='
    $envDir=[IO.Path]::Combine($dir,'env'); [IO.Directory]::CreateDirectory($envDir)|Out-Null
    try { $envSummary=Invoke-EnvironmentCapture -EnvDir $envDir -Label $Label }
    catch { Write-Host ("    [env] capture error: {0}" -f $_.Exception.Message) }
    if($envSummary){ Write-Host ("    env: PASS={0} WARN={1} FAIL={2} SKIP={3}  agent={4}" -f $envSummary.Pass,$envSummary.Warn,$envSummary.Fail,$envSummary.Skip,$envSummary.AgentVersion) }
}

$wsusssWalk=$null

# ---- PROTOCOL PROVENANCE: spec published-version (embedded ref + live fetch) and live-endpoint protocol info ----
$provenance=[ordered]@{ CapturedUtc=$capturedUtc; Specs=[ordered]@{}; Endpoints=[ordered]@{ Wsusss=[ordered]@{}; Wusp=[ordered]@{} } }

# ---- WUA CLIENT BASELINE (phase0 ground-truth dataset) + local-vs-baseline diff. RECORD-ONLY: this does
#      NOT alter identity or any request. It defines the dataset, records it in provenance, and (when the
#      local box is a Server build) surfaces the local SKU values so a Datacenter/Standard retail run resolves
#      the TBU/TBD SKU entries. The composer Get-WuaBaselineIdentity is ready for a future -EmulateServer path.
$wuaBaselineSkuView=[ordered]@{}
foreach($sk in $WuaBaselineSku.Keys){ $wuaBaselineSkuView[$sk]=[ordered]@{ Status=$WuaBaselineSku[$sk].Status; NewProductType=$WuaBaselineSku[$sk].NewProductType; SuiteMask=$WuaBaselineSku[$sk].SuiteMask; RefDoc=$WuaBaselineSku[$sk].RefDoc } }
$wuaBaselineDiff=Compare-WuaIdentityToBaseline -Ident $ident
$provenance['WuaClientBaseline']=[ordered]@{
    Schema='wua-phase0-capture/1.1'; CapturedUtc='2026-06-16'; Source='Windows Server Datacenter Evaluation EVAL media (Hyper-V Gen2, ja-JP)'
    OsGenerations=@($WuaBaselineOs.Keys); Locales=@($WuaBaselineLocale.Keys); Sku=$wuaBaselineSkuView; LocalDiff=$wuaBaselineDiff
}
try { Save-Json -Path ([IO.Path]::Combine($dir,'00.wua-baseline.json')) -Object ([ordered]@{ Common=$WuaBaselineCommon; Locale=$WuaBaselineLocale; Sku=$WuaBaselineSku; Os=$WuaBaselineOs; LocalDiff=$wuaBaselineDiff }) } catch {}
$lSuite= try { [int]$ident.SuiteMask } catch { 0 }
Write-Host ''
Write-Host '=== WUA CLIENT BASELINE (phase0 ground-truth; MS-WUSP client / pseudo-data reference) ==='
Write-Host ("    OS (isolated): {0}" -f (@($WuaBaselineOs.Keys) -join ', '))
Write-Host  '    SKU axis: DatacenterEvaluation=captured(NPT=80,Suite=0x190) | Datacenter=captured(NPT=8,Suite=0x190) | StandardEvaluation=TBD | Standard=TBD'
Write-Host  '    locale  : en-US(1033) / ja-JP(1041)   [captured media: ja-JP]'
if($wuaBaselineDiff.MatchedOs){
    Write-Host ("    local build {0} == baseline [{1}] (server SKU). local SKU values: NewProductType={2} SuiteMask=0x{3:X} OldProductType={4}" -f $ident.OSBuildNumber,$wuaBaselineDiff.MatchedOs,$ident.NewProductTypeSKU,$lSuite,$ident.OldProductType)
    Write-Host  '      -> on a Datacenter/Standard retail box, slot these into the matching SKU entry to resolve TBU/TBD'
} else {
    Write-Host ("    local build {0} not in the Server baseline set; local identity: NewProductType={1} SuiteMask=0x{2:X} OldProductType={3} (client SKU, for contrast)" -f $ident.OSBuildNumber,$ident.NewProductTypeSKU,$lSuite,$ident.OldProductType)
}
Write-Host ''
Write-Host '=== PROTOCOL PROVENANCE: spec versions (Open Specs) ==='
foreach($specKey in $SpecProvenance.Keys){
    $emb=$SpecProvenance[$specKey]
    if($SkipSpecFetch -or -not ($runWsusss -or $runWusp)){ $live=[pscustomobject]@{FetchOk=$false;Revision=$null;Date=$null;Class=$null;HttpStatus=$null;Error='skipped (no SOAP domain / -SkipSpecFetch)'} }
    else { $live=Get-SpecPublishedVersion -Url $emb.Url }
    $provenance.Specs[$specKey]=[ordered]@{
        Title=$emb.Title; Url=$emb.Url
        EmbeddedRevision=$emb.EmbeddedRevision; EmbeddedDate=$emb.EmbeddedDate; EmbeddedClass=$emb.EmbeddedClass; EmbeddedAsOf=$emb.EmbeddedAsOf
        LiveFetchOk=$live.FetchOk; LiveRevision=$live.Revision; LiveDate=$live.Date; LiveClass=$live.Class; LiveError=$live.Error
    }
    if($live.FetchOk){ Write-Host ("    {0,-10} live: rev {1} ({2}, {3})  | embedded ref: rev {4} ({5})" -f $specKey,$live.Revision,$live.Date,$live.Class,$emb.EmbeddedRevision,$emb.EmbeddedDate) }
    else { Write-Host ("    {0,-10} live: [unavailable: {1}]  | embedded ref: rev {2} ({3}, {4})" -f $specKey,$live.Error,$emb.EmbeddedRevision,$emb.EmbeddedDate,$emb.EmbeddedClass) }
}

# ===================================================================================
# ENDPOINT PRE-FLIGHT -- MANDATORY precondition gate (ALWAYS runs; per-protocol; read-only GET).
#   Per user mandate: the pre-flight is a precondition for execution. It ALWAYS runs, and EACH protocol's
#   pre-flight is executed and reported SEPARATELY -- even when a host/endpoint is shared between protocols,
#   because a shared host today is no guarantee tomorrow. A protocol advances to its SOAP phase ONLY when
#   ALL of its REQUIRED endpoints are hosted (REQUIRED-gate, fail-fast). OPTIONAL/N-A endpoints are probed
#   and reported but do NOT gate: a 404 on the WSUSSS Reporting service (role-based, absent on the public
#   catalog USS) or an N/A SimpleAuth (anonymous path; GetConfig advertises no ServiceUrl) is the CORRECT,
#   expected terminal state, not a fault. WUSP client/reporting host bases are DISCOVERED at runtime from the
#   SLS environment.xml; SimpleAuth applicability is DISCOVERED from the live GetConfig AuthInfo. Pins fall
#   back gracefully and are labeled in [src: ...].
# ===================================================================================
Write-Host ''
if ($runWsusss -or $runWusp) {
Write-Host '=== ENDPOINT PRE-FLIGHT (mandatory; per-protocol; REQUIRED-gates each protocol) ==='

# ---- [MS-WSUSSS] pinned (server-server; spec 2.1; no discovery mechanism) ----
$ssEpPF  = if($WsusssServerSyncEndpoint){$WsusssServerSyncEndpoint}else{'https://sws.update.microsoft.com/ServerSyncWebService/ServerSyncWebService.asmx'}
$dssEpPF = if($WsusssDssAuthEndpoint){$WsusssDssAuthEndpoint}else{'https://sws.update.microsoft.com/DssAuthWebService/DssAuthWebService.asmx'}
$repEpPF = [regex]::Replace($ssEpPF,'ServerSyncWebService/ServerSyncWebService\.asmx$','ReportingWebService/ReportingWebService.asmx','IgnoreCase')
$pfWsusss = Invoke-PreflightGroup -Proto 'MS-WSUSSS' -Title 'server-server (public USS)' -Eps @(
    @{ Name='ServerSync'; Url=$ssEpPF;  Role='REQUIRED'; Src='derived: USS host (admin-config per 1.5) + spec 2.1 path'; Why='catalog metadata sync (B1,B4-B9)' }
    @{ Name='DssAuth';    Url=$dssEpPF; Role='REQUIRED'; Src='derived: spec 2.1 path; cross-checked vs GetAuthConfig.AuthInfo.ServiceUrl'; Why='update authorization (B2)' }
    @{ Name='Reporting';  Url=$repEpPF; Role='OPTIONAL'; Src='derived: same USS host as ServerSync + spec 2.1 path'; Why='DSS->USS rollup (B12-B17); separate service; if absent at this derived path -> NOT-PUBLISHED (bounded proof, not lone 404)' }
)

# ---- [MS-WUSP] dynamic: SLS environment.xml (client/reporting bases) + GetConfig AuthInfo (SimpleAuth) ----
$pfArch  = if($ident.ProcessorArchitecture -eq 'AMD64'){'x64'}else{([string]$ident.ProcessorArchitecture).ToLower()}
$pfOsver = '{0}.{1}.{2}.{3}' -f $ident.OSMajorVersion,$ident.OSMinorVersion,$ident.OSBuildNumber,$ident.UBR
$pfSlsUrl= 'https://sls.update.microsoft.com/SLS/{0}/{1}/{2}/0' -f $serviceId,$pfArch,$pfOsver   # minimal form
$script:WuspDisc=$null
if(-not $SkipSls){
    $pfSls=Invoke-HttpGetCapture -Url $pfSlsUrl
    if($pfSls.Bytes -and $pfSls.Bytes.Length -ge 4 -and [Text.Encoding]::ASCII.GetString($pfSls.Bytes[0..3]) -eq 'MSCF'){ $script:WuspDisc=Get-SlsProtocol -Bytes $pfSls.Bytes }
}
if($script:WuspDisc -and ($script:WuspDisc['clientServerUrlCR'] -or $script:WuspDisc['clientServerUrl'])){
    $pfCliBase= if($script:WuspDisc['clientServerUrlCR']){$script:WuspDisc['clientServerUrlCR']}else{$script:WuspDisc['clientServerUrl']}; $pfCliSrc='SLS-dynamic'
} else {
    $pfFull= if($WuspClientEndpoint){$WuspClientEndpoint}else{$ObservedClientEndpoints[$serviceId.ToUpper()]}
    $pfCliBase=[regex]::Replace([string]$pfFull,'ClientWebService/client\.asmx$','','IgnoreCase'); $pfCliSrc= if($WuspClientEndpoint){'param'}else{'pinned-fallback'}
}
$pfCliEp=(Join-Url $pfCliBase 'ClientWebService/client.asmx')
if($script:WuspDisc -and $script:WuspDisc['reportingServerUrl']){ $pfRepBase=$script:WuspDisc['reportingServerUrl']; $pfRepSrc='SLS-dynamic' } else { $pfRepBase='http://statsfe2.update.microsoft.com/'; $pfRepSrc='pinned-fallback' }
$pfRepEp=(Join-Url $pfRepBase 'ReportingWebService/ReportingWebService.asmx')
$pfAuth=Get-WuspAuthInfoSurvey -ClientEp $pfCliEp
if($pfAuth.Ok -and $pfAuth.SimpleAuthUrl){
    $pfSimpRole='REQUIRED'; $pfSimpWhy=("GetConfig AuthInfo: plugins=[{0}]; SimpleAuth ServiceUrl advertised" -f ($pfAuth.Plugins -join ', '))
    $pfSimpUrl= if($pfAuth.SimpleAuthUrl -match '^https?://'){$pfAuth.SimpleAuthUrl}else{ Join-Url ([regex]::Match($pfCliEp,'^https?://[^/]+').Value) $pfAuth.SimpleAuthUrl }
} elseif($pfAuth.Ok){
    $pfSimpRole='N/A'; $pfSimpUrl=(Join-Url $pfCliBase 'SimpleAuthWebService/SimpleAuth.asmx'); $pfSimpWhy=("GetConfig AuthInfo: plugins=[{0}]; NO ServiceUrl advertised -> SimpleAuth not used on this path" -f ($pfAuth.Plugins -join ', '))
} else {
    $pfSimpRole='N/A'; $pfSimpUrl=(Join-Url $pfCliBase 'SimpleAuthWebService/SimpleAuth.asmx'); $pfSimpWhy=("GetConfig query failed ({0}); SimpleAuth applicability unknown" -f $pfAuth.Error)
}
Write-Host '    discovery: SLS environment.xml + GetConfig AuthInfo'
if($script:WuspDisc){ foreach($k in 'clientServerUrl','clientServerUrlCR','reportingServerUrl'){ if($script:WuspDisc[$k]){ Write-Host ("      {0,-18} = {1}" -f $k,$script:WuspDisc[$k]) } } } else { Write-Host '      SLS discovery unavailable -> pinned-fallback bases' }
Write-Host ("      auth plugins       = {0}" -f $(if($pfAuth.Ok){($pfAuth.Plugins -join ', ')}else{('[query failed: '+$pfAuth.Error+']')}))
Write-Host ("      SimpleAuth         = {0}" -f $(if($pfAuth.SimpleAuthUrl){$pfAuth.SimpleAuthUrl}else{'(none) -> N/A'}))
$pfWusp = Invoke-PreflightGroup -Proto 'MS-WUSP' -Title 'client-server (SLS-discovered)' -Eps @(
    @{ Name='SLS discovery'; Url=$pfSlsUrl; Role='REQUIRED'; Src='pinned host+shape'; Why='endpoint discovery (A1)' }
    @{ Name='Client';        Url=$pfCliEp;  Role='REQUIRED'; Src=$pfCliSrc;           Why='metadata sync (A2,A4,A6,A7...)' }
    @{ Name='Reporting';     Url=$pfRepEp;  Role='OPTIONAL'; Src=$pfRepSrc;           Why='ReportEventBatch (A13)' }
    @{ Name='SimpleAuth';    Url=$pfSimpUrl;Role=$pfSimpRole;Src='GetConfig-dynamic'; Why=$pfSimpWhy }
)

$provenance['EndpointPreflight']=[ordered]@{
    Wsusss=[ordered]@{ Pass=$pfWsusss.Pass; RequiredHosted=$pfWsusss.RequiredHosted; Required=$pfWsusss.Required; Rows=$pfWsusss.Rows }
    Wusp  =[ordered]@{ Pass=$pfWusp.Pass;   RequiredHosted=$pfWusp.RequiredHosted;   Required=$pfWusp.Required;   Rows=$pfWusp.Rows }
    Discovery=[ordered]@{ Sls=$script:WuspDisc; Auth=[ordered]@{ Ok=$pfAuth.Ok; Plugins=$pfAuth.Plugins; SimpleAuthUrl=$pfAuth.SimpleAuthUrl; Error=$pfAuth.Error } }
}
$script:WsusssPreflightPass=$pfWsusss.Pass
$script:WuspPreflightPass=$pfWusp.Pass
Write-Host ''
Write-Host ("=== PRE-FLIGHT RESULT:  MS-WSUSSS {0}   |   MS-WUSP {1} ===" -f $(if($pfWsusss.Pass){'PASS'}else{'FAIL'}),$(if($pfWusp.Pass){'PASS'}else{'FAIL'}))
} else { $script:WsusssPreflightPass=$false; $script:WuspPreflightPass=$false; Write-Host '=== ENDPOINT PRE-FLIGHT: skipped (no SOAP domain selected; -OnlyWuaApi) ===' }

# ===================================================================================
# PART 1 -- [MS-WSUSSS] Server-Server Protocol  (catalog distribution; runs FIRST, gates WUSP)
#   ALL operations B1-B17 are executed and captured (NO scope-limiting on data acquisition).
#     B1-B4   auth/config
#     B5a     GetConfig=true config/category dictionary
#     B5b     GetConfig=false enumeration (EC-2): scoped by Classifications + Categories
#     B6-B9   GetUpdateData / GetUpdateDecryptionData / GetDriverIdList / GetDriverSetData
#     B10-B11 GetDeployments / DownloadFiles (spec-exact requests; sample/schema capture)
#     B12-B17 Rollup/Report (spec-exact requests; sample/schema capture)
#   QUALITY GATE (CORE-gating): $wsusssCatalogClean is the metadata-SSOT health flag. It is cleared ONLY by a
#   genuine fault of a HOSTED CORE catalog op (B1-B9 + the EC-2 enumeration). B10-B17 are SUPPLEMENTARY and
#   NON-GATING: B10/B11 are replica-context / already-inline samples on a hosted endpoint, and B12-B17 are
#   DSS->USS rollup/report ops whose Reporting Web Service is proven (endpoint pre-flight + spec 2.1 role model)
#   to be absent on the public catalog USS -- recorded as endpoint-not-hosted, not faults. The gate still governs
#   whether PART 2 (WUSP) may run and remains user-mandated: do NOT weaken/remove the CORE gate without
#   explicit user authorization.
# ===================================================================================
# ===================================================================================
# ----------------------------------------------------------------------------------
# Invoke-BoundedSizeProbe: POST a SOAP request but read ONLY a bounded sample from the response stream, then
# abort -- to CHARACTERIZE a response too large to transfer reliably (e.g. unscoped GetRevisionIdList = the
# entire Revision Table, observed ~312 MB / 327,152,039 bytes) WITHOUT buffering it all or waiting for the
# server to close the long connection (~120s). Records the server-declared Content-Length when present.
function Invoke-BoundedSizeProbe {
    param([Parameter(Mandatory)][string]$Url,[Parameter(Mandatory)][string]$Action,[Parameter(Mandatory)][string]$InnerBody,
          [int]$TimeoutSec=20,[int]$MaxBytes=262144)
    $out=[ordered]@{ Url=$Url; Action=$Action; StatusCode=0; DeclaredContentLength=$null; BytesSampled=0; ResultElementSeen=$false; SampleRows=0; Aborted=$false; ExceptionKind=$null; Note='' }
    $envelope='<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'+$InnerBody+'</s:Body></s:Envelope>'
    $resp=$null
    try {
        $req=[System.Net.HttpWebRequest]::Create($Url)
        $req.Method='POST'; $req.ContentType='text/xml; charset=utf-8'; $req.Timeout=$TimeoutSec*1000; $req.ReadWriteTimeout=$TimeoutSec*1000
        $req.Headers.Add('SOAPAction','"'+$Action+'"'); $req.UserAgent='Windows-Update-Agent'; $req.AllowAutoRedirect=$true
        $reqBytes=[Text.Encoding]::UTF8.GetBytes($envelope); $req.ContentLength=$reqBytes.Length
        $rs=$req.GetRequestStream(); $rs.Write($reqBytes,0,$reqBytes.Length); $rs.Close()
        $resp=$req.GetResponse()
        $out.StatusCode=[int]$resp.StatusCode
        $out.DeclaredContentLength=$resp.ContentLength   # -1 when chunked / not declared
        $stream=$resp.GetResponseStream()
        $buf=New-Object byte[] 65536; $sb=New-Object System.Text.StringBuilder; $total=0
        while($total -lt $MaxBytes){ $want=[Math]::Min(65536,$MaxBytes-$total); $n=$stream.Read($buf,0,$want); if($n -le 0){break}; $total+=$n; [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf,0,$n)) }
        $out.BytesSampled=$total
        $txt=$sb.ToString()
        $out.ResultElementSeen = ($txt -match '<(?:\w+:)?GetRevisionIdListResult\b')
        $out.SampleRows = ([regex]::Matches($txt,'<(?:\w+:)?UpdateIdentity\b')).Count
        $out.Aborted = ($total -ge $MaxBytes)
        try{ $stream.Close() }catch{}; try{ $resp.Close() }catch{}; try{ $req.Abort() }catch{}
        $out.Note='bounded probe: read first '+$total+' bytes then aborted (full body NOT transferred)'
    } catch {
        $ex=$_.Exception; $inner=$ex.InnerException
        $webEx = if($ex -is [System.Net.WebException]){$ex} elseif($inner -is [System.Net.WebException]){$inner} else {$null}
        $kind = if($webEx){ [string]$webEx.Status } else { $ex.GetType().Name }
        $out.ExceptionKind=$kind
        if($kind -match 'ConnectionClosed|KeepAliveFailure|ReceiveFailure|ConnectFailure|Timeout'){
            $out.Note="unscoped server-reset/timeout ($kind) -- the documented EC-2 unreliability: the full Revision Table (~312MB) transfer did not complete this run; scoped enumeration is canonical."
        } else {
            $out.Note="bounded probe exception ($kind): $($ex.Message)"
        }
        try{ if($resp){$resp.Close()} }catch{}
    }
    [pscustomobject]$out
}

# CONFORMANCE + DATA-PROVENANCE LAYER  [2026-06-21]
#   Replaces the "HTTP 200 == success" standard with SPEC-GROUNDED conformance, and makes every
#   request-data value MANAGED (value + spec/ground-truth source + justification, recorded per run).
#   The CORE quality gate keys off .Conformant, NOT .IsSuccess. Contracts are from the [MS-WSUSSS] WSDL.
#   A 200 carrying a SOAP Fault, or a 200 whose body lacks the spec result element, is NON-CONFORMANT.
# ===================================================================================
# Per-operation contract (WSDL). RespRequired = result-body elements a CONFORMANT response MUST carry.
$Script:WsusssContracts = @{
  GetAuthConfig          = [ordered]@{ ActionSuffix='/GetAuthConfig';                                  SpecReq='3.1.4.1.2.1'; SpecResp='3.1.4.1.3.1'; ReqRoot='GetAuthConfig';          ReqRequired=@();                            RespResult='GetAuthConfigResult';          RespRequired=@('AuthInfo') }
  GetAuthorizationCookie = [ordered]@{ ActionSuffix='/Server/DssAuthWebService/GetAuthorizationCookie'; SpecReq='3.1.4.2.2.1'; SpecResp='2.2.4.1';     ReqRoot='GetAuthorizationCookie'; ReqRequired=@('accountName','accountGuid');    RespResult='GetAuthorizationCookieResult'; RespRequired=@('PlugInId','CookieData') }
  GetCookie              = [ordered]@{ ActionSuffix='/GetCookie';                                       SpecReq='3.1.4.3.2.1'; SpecResp='2.2.4.4';     ReqRoot='GetCookie';              ReqRequired=@('authCookies','protocolVersion'); RespResult='GetCookieResult';          RespRequired=@('Expiration','EncryptedData') }
  GetConfigData          = [ordered]@{ ActionSuffix='/GetConfigData';                                   SpecReq='3.1.4.4.2.1'; SpecResp='3.1.4.4.3.1'; ReqRoot='GetConfigData';          ReqRequired=@('cookie','configAnchor');     RespResult='GetConfigDataResult';          RespRequired=@('ProtocolVersion') }
  GetRevisionIdList      = [ordered]@{ ActionSuffix='/GetRevisionIdList';                               SpecReq='3.1.4.5.2.1'; SpecResp='3.1.4.5.3.6'; ReqRoot='GetRevisionIdList';      ReqRequired=@('cookie','filter');           RespResult='GetRevisionIdListResult';      RespRequired=@('Anchor') }
  GetUpdateData          = [ordered]@{ ActionSuffix='/GetUpdateData';                                   SpecReq='3.1.4.6.2.1'; SpecResp='3.1.4.6.3.1'; ReqRoot='GetUpdateData';          ReqRequired=@('cookie');                    RespResult='GetUpdateDataResult';          RespRequired=@() }
  GetUpdateDecryptionData= [ordered]@{ ActionSuffix='/GetUpdateDecryptionData';                         SpecReq='3.1.4.18.2.1';SpecResp='3.1.4.18.3.1';ReqRoot='GetUpdateDecryptionData';ReqRequired=@('cookie');                    RespResult='GetUpdateDecryptionDataResult';RespRequired=@() }
  GetDriverIdList        = [ordered]@{ ActionSuffix='/GetDriverIdList';                                 SpecReq='3.1.4.7.2.1'; SpecResp='3.1.4.7.3.1'; ReqRoot='GetDriverIdList';        ReqRequired=@('cookie');                    RespResult='GetDriverIdListResult';        RespRequired=@() }
  GetDriverSetData       = [ordered]@{ ActionSuffix='/GetDriverSetData';                                SpecReq='3.1.4.8.2.1'; SpecResp='3.1.4.8.3.1'; ReqRoot='GetDriverSetData';       ReqRequired=@('cookie');                    RespResult='GetDriverSetDataResult';       RespRequired=@() }
}

# Managed request data: value + source + spec ref + justification, recorded to 00.data-provenance.json.
$Script:DataProvenance = New-Object System.Collections.ArrayList
$Script:WsusssVerdicts = New-Object System.Collections.ArrayList
function New-ManagedValue {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][AllowEmptyString()][string]$Value,
          [Parameter(Mandatory)][ValidateSet('spec-fixed','ground-truth','generated','derived')][string]$Source,
          [Parameter(Mandatory)][string]$SpecRef,[Parameter(Mandatory)][string]$Justification)
    [void]$Script:DataProvenance.Add([pscustomobject][ordered]@{ name=$Name; value=$Value; source=$Source; specRef=$SpecRef; justification=$Justification })
    return $Value
}

# SOAP fault detector: a 200 carrying a Fault is NOT success. Returns $null or the fault detail.
function Get-SoapFault {
    param([string]$Xml)
    if ([string]::IsNullOrEmpty($Xml)) { return $null }
    if ($Xml -notmatch '<(?:\w+:)?Fault[\s>]') { return $null }
    $code=$null; if($Xml -match '<(?:\w+:)?(?:faultcode|Code)[^>]*>([^<]+)'){$code=$matches[1].Trim()}
    $str=$null
    if($Xml -match '<(?:\w+:)?faultstring[^>]*>([^<]*)'){$str=$matches[1].Trim()}
    elseif($Xml -match '<(?:\w+:)?Reason[^>]*>.*?<(?:\w+:)?Text[^>]*>([^<]+)'){$str=$matches[1].Trim()}
    if([string]::IsNullOrWhiteSpace($str)){
        # fallback for non-standard faults (e.g. the WUSP <detail> ClientFault carrying InvalidParameters/authCookies):
        # collect the text content of <detail> so the real reason is surfaced instead of an empty faultstring.
        $dm=[regex]::Match($Xml,'(?s)<(?:\w+:)?detail[^>]*>(.*?)</(?:\w+:)?detail>')
        if($dm.Success){ $txt=[regex]::Replace($dm.Groups[1].Value,'<[^>]+>',' '); $str=([regex]::Replace($txt,'\s+',' ')).Trim() }
    }
    $err=$null;  if($Xml -match '<ErrorCode>([^<]*)'){$err=$matches[1]}
    [pscustomobject]@{ FaultCode=$code; FaultString=$str; ErrorCode=$err }
}

# RESPONSE conformance -- the anti-"200" verdict. Checks: transport returned a body; NOT a SOAP fault;
# the spec result element is present; required result-body children present. .Conformant = all pass.
function Test-ResponseConformance {
    param([Parameter(Mandatory)][string]$Op,[Parameter(Mandatory)]$Cap,$Contracts=$Script:WsusssContracts)
    $c=$Contracts[$Op]
    $checks=New-Object System.Collections.ArrayList
    $xml = if($Cap){[string]$Cap.ResponseContent}else{''}
    $st  = if($Cap){$Cap.StatusCode}else{0}
    [void]$checks.Add([pscustomobject]@{ check='transport-returned-body'; pass=[bool]$xml; detail=("httpStatus={0} bytes={1}" -f $st,$xml.Length) })
    $fault = Get-SoapFault $xml
    [void]$checks.Add([pscustomobject]@{ check='not-soap-fault'; pass=(-not $fault); detail=$(if($fault){"FAULT: $($fault.FaultString) / err=$($fault.ErrorCode)"}else{'no fault'}) })
    $hasResult=$false; if($c -and $xml){ $hasResult = ($xml -match ("<(?:\w+:)?{0}\b" -f [regex]::Escape($c.RespResult))) }
    [void]$checks.Add([pscustomobject]@{ check='spec-result-element-present'; pass=$hasResult; detail=$(if($c){"expect <$($c.RespResult)> (spec $($c.SpecResp))"}else{'NO CONTRACT'}) })
    $missing=@(); if($c -and $hasResult){ foreach($r in $c.RespRequired){ if($xml -notmatch ("<(?:\w+:)?{0}\b" -f [regex]::Escape($r))){ $missing+=$r } } }
    [void]$checks.Add([pscustomobject]@{ check='required-result-children-present'; pass=($missing.Count -eq 0); detail=$(if($missing.Count){"MISSING: $($missing -join ',')"}else{"present: $($c.RespRequired -join ',')"}) })
    $fails=@($checks | Where-Object { -not $_.pass } | ForEach-Object { $_.check })
    [pscustomobject]@{ Op=$Op; Conformant=([bool]$c -and $fails.Count -eq 0); HttpStatus=$st; HttpOk=[bool]($Cap -and $Cap.IsSuccess); Fault=$fault; Checks=$checks; Failures=$fails }
}

# REQUEST conformance -- validate the envelope WE built vs the contract (root, namespace, required children, action).
function Test-RequestConformance {
    param([Parameter(Mandatory)][string]$Op,[Parameter(Mandatory)][string]$Envelope,[string]$ActionSent='')
    $c=$Script:WsusssContracts[$Op]; $checks=New-Object System.Collections.ArrayList
    [void]$checks.Add([pscustomobject]@{ check='request-root-present'; pass=($Envelope -match ("<(?:\w+:)?{0}\b" -f [regex]::Escape($c.ReqRoot))); detail="<$($c.ReqRoot)> (spec $($c.SpecReq))" })
    [void]$checks.Add([pscustomobject]@{ check='sd-namespace-present'; pass=($Envelope -match 'http://www\.microsoft\.com/SoftwareDistribution'); detail='xmlns SoftwareDistribution' })
    $missing=@(); foreach($r in $c.ReqRequired){ if($Envelope -notmatch ("<(?:\w+:)?{0}\b" -f [regex]::Escape($r))){ $missing+=$r } }
    [void]$checks.Add([pscustomobject]@{ check='required-request-children-present'; pass=($missing.Count -eq 0); detail=$(if($missing.Count){"MISSING: $($missing -join ',')"}else{"present: $($c.ReqRequired -join ',')"}) })
    if($ActionSent){ [void]$checks.Add([pscustomobject]@{ check='soapaction-matches-wsdl'; pass=($ActionSent.EndsWith($c.ActionSuffix)); detail="sent=$ActionSent expect *$($c.ActionSuffix)" }) }
    $fails=@($checks | Where-Object { -not $_.pass } | ForEach-Object { $_.check })
    [pscustomobject]@{ Op=$Op; Conformant=([bool]$c -and $fails.Count -eq 0); Checks=$checks; Failures=$fails }
}

# --- EXPECTATION MODEL: per WSUSSS step, what a CORRECT run should produce. Lets the operator see at a
#     glance whether each op matched its expected outcome (the "is this the expected result?" question). ---
# SPEC-GROUNDED APPLICABILITY MODEL (Track1/Track2): each op is placed in its [MS-WSUSSS] sync PHASE (3.2.4)
# with the PRECONDITION that gates it. Our profile = anonymous AUTONOMOUS DSS <- catalog-only USS
# (CatalogOnlySync=TRUE). Phases 1-2 are in-profile; phase 3 (replica-only), phase 4 (CatalogOnlySync=FALSE),
# phase 5 (reporting rollup, separate service) are OUT-OF-PROFILE here -- by spec, not by guess.
$Script:WsusssApplicability = @{
  B1  = @{ Phase=1; Basis='in-profile';        SpecRef='3.2.4.1';          Expect='CONFORMANT'; Gating=$true;  Note='Authorization phase (always applicable)' }
  B2  = @{ Phase=1; Basis='in-profile';        SpecRef='3.2.4.1';          Expect='CONFORMANT'; Gating=$true;  Note='Authorization (managed accountName/accountGuid)' }
  B3  = @{ Phase=1; Basis='in-profile';        SpecRef='3.2.4.1';          Expect='CONFORMANT'; Gating=$true;  Note='Authorization (access cookie)' }
  B4  = @{ Phase=2; Basis='in-profile';        SpecRef='3.2.4.2';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (config data; advertises CatalogOnlySync/ProtocolVersion)' }
  B5a = @{ Phase=2; Basis='in-profile';        SpecRef='3.2.4.2';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (taxonomy dictionary)' }
  B5b = @{ Phase=2; Basis='in-profile';        SpecRef='3.2.4.2';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (EC-2). RESOLVED: scoped (Classifications[+Categories]) is the canonical reliable enumeration; unscoped null-anchor = entire Revision Table (~312MB single response, transfer unreliable) -> bounded size-probe only.' }
  B6  = @{ Phase=2; Basis='in-profile';        SpecRef='3.1.4.6';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (GetUpdateData) -- spec-contracted (result element + not-fault)' }
  B7  = @{ Phase=2; Basis='in-profile';        SpecRef='3.1.4.18';         Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (GetUpdateDecryptionData) -- spec-contracted' }
  B8  = @{ Phase=2; Basis='in-profile';        SpecRef='3.1.4.7';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (GetDriverIdList) -- spec-contracted' }
  B9  = @{ Phase=2; Basis='in-profile';        SpecRef='3.1.4.8';          Expect='CONFORMANT'; Gating=$true;  Note='Metadata Sync (GetDriverSetData) -- spec-contracted' }
  B10 = @{ Phase=3; Basis='out-of-profile:replica-only';   SpecRef='3.1.4.10/3.2.4.3'; Expect='fault';      Gating=$false; Note='Deployments phase -- spec 3.1.4.10: MUST NOT invoke unless DSS is a Replica Server. We are an autonomous catalog client -> OUT-OF-PROFILE; probe records the precondition reject as evidence.' }
  B11 = @{ Phase=4; Basis='out-of-profile:catalogonlysync'; SpecRef='3.2.4.4/3.1.4.11'; Expect='fault';      Gating=$false; Note='Content phase -- applies only if CatalogOnlySync=FALSE. USS advertised CatalogOnlySync=TRUE -> content fetched via MUUrl (URLs already in B6) -> OUT-OF-PROFILE.' }
  B12 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting phase (DSS->USS rollup) on the SEPARATE Reporting Web Service. NOT-PUBLISHED on this USS: spec 2.1 mandated path absent on the authoritative host (= ServerSync host) + role model 3.2.4.5/DoDetailedRollup/Appendix-A (USS rollup receiver, v1.3+). Bounded proof, not a lone 404.' }
  B13 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting (RollupDownstreamServers) -- NOT-PUBLISHED on this USS (see B12 basis).' }
  B14 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting (RollupComputers; gated by USS DoDetailedRollup) -- NOT-PUBLISHED on this USS.' }
  B15 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting (GetOutOfSyncComputers; gated by DoDetailedRollup) -- NOT-PUBLISHED on this USS.' }
  B16 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting (RollupComputerStatus; gated by DoDetailedRollup) -- NOT-PUBLISHED on this USS.' }
  B17 = @{ Phase=5; Basis='out-of-profile:not-published';  SpecRef='2.1/3.2.4.5';      Expect='not-hosted'; Gating=$false; Note='Reporting (ReportEventBatch) -- NOT-PUBLISHED on this USS.' }
}

$Script:WuspApplicability = [ordered]@{
  W1  = @{ Operation='GetConfig';             Phase=1; Basis='in-profile:handshake';          SpecRef='2.2.2.2.1';  Expect='CONFORMANT';              Gating=$true;  Note='client config + auth plugins + ServerProtocolVersion' }
  W2  = @{ Operation='GetCookie';             Phase=1; Basis='in-profile:anonymous-cookie';   SpecRef='2.2.2.2.2';  Expect='CONFORMANT';              Gating=$true;  Note='anonymous session cookie (PidValidator/Anonymous)' }
  W3  = @{ Operation='SyncUpdates';           Phase=2; Basis='in-profile:catalog-sync';       SpecRef='2.2.2.2.4';  Expect='CONFORMANT';              Gating=$true;  Note='non-leaf + leaf enumeration engine (base-data + full-enum + product-scan)' }
  W4  = @{ Operation='StartCategoryScan';     Phase=2; Basis='in-profile:category-scope';     SpecRef='2.2.2.2.8';  Expect='CONFORMANT';              Gating=$false; Note='product GUID recognition + preferred-category list (client pv>=1.7, server pv>=3.2)' }
  W5  = @{ Operation='GetExtendedUpdateInfo'; Phase=2; Basis='in-profile:metadata';           SpecRef='2.2.2.2.6';  Expect='CONFORMANT';              Gating=$true;  Note='Title + Files via Core/Extended/LocalizedProperties (the public host rejects Published/VerificationRule/Eula)' }
  W6  = @{ Operation='GetFileLocations';      Phase=3; Basis='in-profile:file-locations';     SpecRef='2.2.2.2.7';  Expect='CONFORMANT';              Gating=$false; Note='digest -> URL (empty digest set on the anonymous probe still returns a conformant empty result)' }
  W7  = @{ Operation='RefreshCache';          Phase=3; Basis='in-profile:cache-refresh';      SpecRef='2.2.2.2.5';  Expect='CONFORMANT';              Gating=$false; Note='globalID cache refresh' }
  W8  = @{ Operation='SyncPrinterCatalog';    Phase=3; Basis='in-profile:printer-catalog';    SpecRef='2.2.2.2.9';  Expect='CONFORMANT';              Gating=$false; Note='seeded installedNonLeafUpdateIDs (an empty array faults InvalidParameters)' }
  W9  = @{ Operation='GetExtendedUpdateInfo2';Phase=4; Basis='out-of-profile:anonymous-auth'; SpecRef='2.2.2.2.10'; Expect='EXPECTED-OUT-OF-PROFILE'; Gating=$false; Note='FileUrl/FileDecryption require authentication; the anonymous path returns FailedAuthentication -- correct for this profile' }
  W10 = @{ Operation='RegisterComputer';      Phase=4; Basis='out-of-profile:anonymous-reg';  SpecRef='2.2.2.2.3';  Expect='EXPECTED-OUT-OF-PROFILE'; Gating=$false; Note='GetConfig advertised IsRegistrationRequired=false; the server returns RegistrationNotRequired -- correct for this profile' }
}

# Map a raw coverage status string to a comparable bucket.
function Get-StatusBucket {
    param([string]$Status)
    if     ($Status -like 'CONFORMANT*')          { 'CONFORMANT' }
    elseif ($Status -like 'NON-CONFORMANT*')      { 'NON-CONFORMANT' }
    elseif ($Status -like 'http-2xx*')            { 'http-2xx' }
    elseif ($Status -like 'ok*')                  { 'http-2xx' }   # legacy vocabulary
    elseif ($Status -like 'fault*')               { 'fault' }
    elseif ($Status -like 'endpoint-not-hosted*') { 'not-hosted' }
    elseif ($Status -eq   'not-attempted')        { 'not-attempted' }
    else                                          { 'other' }
}

# Per-operation report: joins each WSUSSS coverage row with its expectation and prints EXPECTED vs ACTUAL
# with an [OK] / [!! UNEXPECTED] verdict. Written to 97.operation-report.{txt,json}.
function Write-OperationReport {
    param([Parameter(Mandatory)][string]$OutDir)
    $rows=@($coverage | Where-Object { $_.protocol -eq 'WSUSSS' })
    $report=New-Object System.Collections.ArrayList
    foreach($r in $rows){
        $exp=$Script:WsusssApplicability[$r.step]
        $actB=Get-StatusBucket $r.status
        $expB= if($exp){$exp.Expect}else{'(none)'}
        $match= if(-not $exp){'NO-EXPECT'} elseif($actB -eq $expB){'OK'} else {'UNEXPECTED'}
        [void]$report.Add([pscustomobject][ordered]@{ step=$r.step; operation=$r.operation; gate=$(if($exp -and $exp.Gating){'CORE'}else{'supp'}); phase=$(if($exp){$exp.Phase}else{$null}); basis=$(if($exp){$exp.Basis}else{'(none)'}); specRef=$(if($exp){$exp.SpecRef}else{''}); expected=$expB; actual=$r.status; actualBucket=$actB; verdict=$match; note=$(if($exp){$exp.Note}else{''}) })
    }
    Write-Host ''
    Write-Host '=== WSUSSS OPERATION REPORT (spec-grounded: phase / applicability basis / expected vs actual) ==='
    Write-Host ('  {0,-4} {1,-46} {2,-3} {3,-26} {4,-12} {5,-28} {6}' -f 'step','operation','ph','basis (spec-grounded)','expected','actual','verdict')
    Write-Host ('  ' + ('-' * 128))
    foreach($x in $report){
        $flag= if($x.verdict -eq 'OK'){'[OK]'} elseif($x.verdict -eq 'UNEXPECTED'){'[!! UNEXPECTED]'} else {'[? no-expect]'}
        Write-Host ('  {0,-4} {1,-46} {2,-3} {3,-26} {4,-12} {5,-28} {6}' -f $x.step,$x.operation,$x.phase,$x.basis,$x.expected,$x.actual,$flag)
    }
    $okc=@($report|Where-Object{$_.verdict -eq 'OK'}).Count
    $unx=@($report|Where-Object{$_.verdict -eq 'UNEXPECTED'}).Count
    Write-Host ('  ' + ('-' * 128))
    Write-Host ("  RESULT: {0}/{1} operations AS EXPECTED (spec-grounded)   |   UNEXPECTED: {2}   |   CORE gate clean: {3}" -f $okc,$report.Count,$unx,$wsusssCatalogClean)
    if($unx -gt 0){ Write-Host '  -> investigate the [!! UNEXPECTED] row(s) above before trusting this run.' }
    Save-Json -Path ([IO.Path]::Combine($OutDir,'97.operation-report.json')) -Object @($report)
    $lines=@('WSUSSS OPERATION REPORT (spec-grounded: phase / applicability basis / expected vs actual)','')
    foreach($x in $report){ $lines += ('{0,-4} {1,-46} ph{2} {3,-26} expected={4,-12} actual={5,-28} {6}  [spec {7}]  {8}' -f $x.step,$x.operation,$x.phase,$x.basis,$x.expected,$x.actual,$x.verdict,$x.specRef,$x.note) }
    $lines += @('', ("RESULT: {0}/{1} as expected | UNEXPECTED: {2} | CORE gate clean: {3}" -f $okc,$report.Count,$unx,$wsusssCatalogClean))
    Save-Text -Path ([IO.Path]::Combine($OutDir,'97.operation-report.txt')) -Text ($lines -join "`r`n")
    [pscustomobject]@{ Total=$report.Count; Ok=$okc; Unexpected=$unx }
}

# Per-operation report for MS-WUSP: joins each ClientWebService op with its spec-grounded expectation
# and prints EXPECTED vs ACTUAL with an [OK] / [!! UNEXPECTED] verdict. expected-out-of-profile (anonymous
# profile -- GetExtendedUpdateInfo2 FailedAuthentication, RegisterComputer RegistrationNotRequired) is an
# AS-EXPECTED outcome, exactly like WSUSSS B10-B17. Written to wusp/90.wusp-operation-report.{txt,json}.
function Write-WuspOperationReport {
    param($Ac,$Fe,$PsAll,$Ld,[Parameter(Mandatory)][string]$OutDir)
    $act=@{}
    $vGet={ param($v) if($v){ if([bool]$v.Conformant){'conformant'}else{'non-conformant'} } else {'not-run'} }
    $hGet={ param($v) if($v -and $v.HttpStatus){[int]$v.HttpStatus}else{0} }
    if($Ac -and $Ac.Verdicts){
        $act['GetConfig']=@{ Class=(& $vGet $Ac.Verdicts['GetConfig']); Http=(& $hGet $Ac.Verdicts['GetConfig']) }
        $act['GetCookie']=@{ Class=(& $vGet $Ac.Verdicts['GetCookie']); Http=(& $hGet $Ac.Verdicts['GetCookie']) }
    }
    if($Fe -and (@($Fe.Categories).Count -or @($Fe.Leaves).Count)){ $act['SyncUpdates']=@{ Class='conformant'; Http=200 } }
    if($PsAll){ if(@(@($PsAll) | Where-Object { $_.Recognized }).Count){ $act['StartCategoryScan']=@{ Class='conformant'; Http=200 } } }
    if($Ld -and $Ld.Ops){ foreach($o in @($Ld.Ops)){ $act[$o.Op]=@{ Class=[string]$o.Class; Http=[int]$o.HttpStatus } } }

    $report=New-Object System.Collections.ArrayList
    foreach($k in $Script:WuspApplicability.Keys){
        $a=$Script:WuspApplicability[$k]; $op=$a.Operation
        $cur= if($act.ContainsKey($op)){ $act[$op] } else { @{ Class='not-run'; Http=0 } }
        $cls=[string]$cur.Class
        $actDisp= switch($cls){ 'conformant'{"CONFORMANT($($cur.Http))"} 'expected-out-of-profile'{"EXPECTED-OUT-OF-PROFILE($($cur.Http))"} 'non-conformant'{"NON-CONFORMANT($($cur.Http))"} default{'not-run'} }
        $actBucket= switch($cls){ 'conformant'{'CONFORMANT'} 'expected-out-of-profile'{'EXPECTED-OUT-OF-PROFILE'} 'non-conformant'{'NON-CONFORMANT'} default{'NOT-RUN'} }
        $verdict= if($actBucket -eq $a.Expect){'OK'} elseif($cls -eq 'not-run'){'NOT-RUN'} else {'UNEXPECTED'}
        [void]$report.Add([pscustomobject][ordered]@{ step=$k; operation=$op; gate=$(if($a.Gating){'CORE'}else{'supp'}); phase=$a.Phase; basis=$a.Basis; specRef=$a.SpecRef; expected=$a.Expect; actual=$actDisp; actualBucket=$actBucket; verdict=$verdict; note=$a.Note })
    }
    Write-Host ''
    Write-Host '=== MS-WUSP OPERATION REPORT (spec-grounded: phase / applicability basis / expected vs actual) ==='
    Write-Host ('  {0,-4} {1,-24} {2,-3} {3,-30} {4,-24} {5,-28} {6}' -f 'step','operation','ph','basis (spec-grounded)','expected','actual','verdict')
    Write-Host ('  ' + ('-' * 132))
    foreach($x in $report){
        $flag= if($x.verdict -eq 'OK'){'[OK]'} elseif($x.verdict -eq 'UNEXPECTED'){'[!! UNEXPECTED]'} else {'[-- not run]'}
        Write-Host ('  {0,-4} {1,-24} {2,-3} {3,-30} {4,-24} {5,-28} {6}' -f $x.step,$x.operation,$x.phase,$x.basis,$x.expected,$x.actual,$flag)
    }
    $okc=@($report|Where-Object{$_.verdict -eq 'OK'}).Count
    $unx=@($report|Where-Object{$_.verdict -eq 'UNEXPECTED'}).Count
    $nrun=@($report|Where-Object{$_.verdict -eq 'NOT-RUN'}).Count
    $coreClean= -not [bool](@($report|Where-Object{ $_.gate -eq 'CORE' -and $_.verdict -ne 'OK' }).Count)
    Write-Host ('  ' + ('-' * 132))
    Write-Host ("  RESULT: {0}/{1} operations AS EXPECTED (spec-grounded)   |   UNEXPECTED: {2}   |   not-run: {3}   |   CORE gate clean: {4}" -f $okc,$report.Count,$unx,$nrun,$coreClean)
    if($unx -gt 0){ Write-Host '  -> investigate the [!! UNEXPECTED] row(s) above before trusting this run.' }
    Save-Json -Path ([IO.Path]::Combine($OutDir,'90.wusp-operation-report.json')) -Object @($report)
    $lines=@('MS-WUSP OPERATION REPORT (spec-grounded: phase / applicability basis / expected vs actual)','')
    foreach($x in $report){ $lines += ('{0,-4} {1,-24} ph{2} {3,-30} expected={4,-24} actual={5,-28} {6}  [spec {7}]  {8}' -f $x.step,$x.operation,$x.phase,$x.basis,$x.expected,$x.actual,$x.verdict,$x.specRef,$x.note) }
    $lines += @('', ("RESULT: {0}/{1} as expected | UNEXPECTED: {2} | not-run: {3} | CORE gate clean: {4}" -f $okc,$report.Count,$unx,$nrun,$coreClean))
    Save-Text -Path ([IO.Path]::Combine($OutDir,'90.wusp-operation-report.txt')) -Text ($lines -join "`r`n")
    [pscustomobject]@{ Total=$report.Count; Ok=$okc; Unexpected=$unx; NotRun=$nrun; CoreClean=$coreClean }
}

$wsusssCatalogClean = $true
$wsusssEc2Rows = 0

# ============================================================================
# [MS-WUSP] CLEAN REBUILD -- FOUNDATION (increment 1: intrinsic env + per-query auth context)
#   Cookie/auth consistency rule: ONLY intrinsic info (endpoint, namespaces, seeds, contracts,
#   client protocolVersion) is reused. Auth (the session Cookie) is re-created FRESH before EVERY
#   query via New-WuspAuthContext (GetConfig -> [SimpleAuth] -> GetCookie) and lives ONLY inside
#   that query -- no cross-query cookie/auth state, so queries carry no hidden dependencies. (Within
#   ONE query's Truncated paging loop the server's NewCookie is followed; that is intra-query
#   continuation per the protocol, not cross-query state.)
# ============================================================================

# WUSP per-op response contracts (from the MS-WUSP WSDL). Conformance verdict = transport body +
# NOT-soap-fault + spec result element present (+ required children only where the WSDL marks them
# minOccurs>=1). Most result children are minOccurs=0, so RespRequired is mostly empty by design.
$Script:WuspContracts = @{
  GetConfig             = [ordered]@{ ActionSuffix='/GetConfig';             SpecReq='2.2.2.2.1';  SpecResp='2.2.2.2.1';  ReqRoot='GetConfig';             ReqRequired=@();                                RespResult='GetConfigResult';             RespRequired=@('LastChange') }
  GetCookie             = [ordered]@{ ActionSuffix='/GetCookie';             SpecReq='2.2.2.2.2';  SpecResp='2.2.2.2.2';  ReqRoot='GetCookie';             ReqRequired=@('lastChange','protocolVersion');  RespResult='GetCookieResult';             RespRequired=@('EncryptedData') }
  RegisterComputer      = [ordered]@{ ActionSuffix='/RegisterComputer';      SpecReq='2.2.2.2.3';  SpecResp='2.2.2.2.3';  ReqRoot='RegisterComputer';      ReqRequired=@('cookie');                        RespResult='RegisterComputerResponse';    RespRequired=@() }
  SyncUpdates           = [ordered]@{ ActionSuffix='/SyncUpdates';           SpecReq='2.2.2.2.4';  SpecResp='2.2.2.2.4';  ReqRoot='SyncUpdates';           ReqRequired=@('cookie','parameters');           RespResult='SyncUpdatesResult';           RespRequired=@('Truncated') }
  RefreshCache          = [ordered]@{ ActionSuffix='/RefreshCache';          SpecReq='2.2.2.2.5';  SpecResp='2.2.2.2.5';  ReqRoot='RefreshCache';          ReqRequired=@('cookie','globalIDs');            RespResult='RefreshCacheResult';          RespRequired=@() }
  GetExtendedUpdateInfo = [ordered]@{ ActionSuffix='/GetExtendedUpdateInfo'; SpecReq='2.2.2.2.6';  SpecResp='2.2.2.2.6';  ReqRoot='GetExtendedUpdateInfo'; ReqRequired=@('cookie','revisionIDs');          RespResult='GetExtendedUpdateInfoResult'; RespRequired=@() }
  GetFileLocations      = [ordered]@{ ActionSuffix='/GetFileLocations';      SpecReq='2.2.2.2.7';  SpecResp='2.2.2.2.7';  ReqRoot='GetFileLocations';      ReqRequired=@('cookie','fileDigests');          RespResult='GetFileLocationsResult';      RespRequired=@() }
  StartCategoryScan     = [ordered]@{ ActionSuffix='/StartCategoryScan';     SpecReq='2.2.2.2.8';  SpecResp='2.2.2.2.8';  ReqRoot='StartCategoryScan';     ReqRequired=@();                                RespResult='StartCategoryScanResponse';   RespRequired=@() }
  SyncPrinterCatalog    = [ordered]@{ ActionSuffix='/SyncPrinterCatalog';    SpecReq='2.2.2.2.9';  SpecResp='2.2.2.2.9';  ReqRoot='SyncPrinterCatalog';    ReqRequired=@('cookie');                        RespResult='SyncPrinterCatalogResult';    RespRequired=@('Truncated') }
  GetExtendedUpdateInfo2= [ordered]@{ ActionSuffix='/GetExtendedUpdateInfo2';SpecReq='2.2.2.2.10'; SpecResp='2.2.2.2.10'; ReqRoot='GetExtendedUpdateInfo2';ReqRequired=@('cookie','updateIDs');            RespResult='GetExtendedUpdateInfo2Result';RespRequired=@() }
}

# Self-evident SEED categories (confirmed values; NOT the universe). The live FULL Product/
# Classification lists are enumerated separately by the base-data query; these seeds are the
# confirmed subset of interest, cross-checked against that live enumeration.
$Script:WuspSeedCategories = [ordered]@{
  # Multi-GUID premise: a product TITLE is NOT unique -- one OS can have several distinct
  # Product category GUIDs (confirmed via WSUS Get-WsusProduct: "Windows Server 2016" exists
  # as BOTH 569e8e8f and e26d4a30). Each GUID is a FIRST-CLASS, independently-queried product.
  # Catalogs notes where the GUID was observed: WUSP = live fe2cr anonymous client catalog
  # (ground-truth from the increment-2 base-data enumeration, run 2026-06-21); WSUS = WSUS/USS
  # product enumeration (Microsoft.UpdateServices.Internal.BaseApi.UpdateServer). WuspLive is
  # the verdict from the base-data run (so a per-product query knows whether to expect data).
  Products = @(
    [pscustomobject]@{ Os='Server2016'; Title='Windows Server 2016';                     Guid='e26d4a30-aba6-4616-a890-011970d93636'; Catalogs='WUSP+WSUS'; WuspLive=$true;  Note='in live WUSP fe2cr client catalog' }
    [pscustomobject]@{ Os='Server2016'; Title='Windows Server 2016';                     Guid='569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5'; Catalogs='WSUS';      WuspLive=$false; Note='WSUS/USS product enumeration; absent from WUSP fe2cr client catalog (0 occurrences in the complete category-tree enumeration)' }
    [pscustomobject]@{ Os='Server2019'; Title='Windows Server 2019';                     Guid='6e56e6da-f22f-47c9-97b4-510153a06740'; Catalogs='WUSP+WSUS'; WuspLive=$true;  Note='in live WUSP fe2cr client catalog' }
    [pscustomobject]@{ Os='Server2019'; Title='Windows Server 2019';                     Guid='f702a48c-919b-45d6-9aef-ca4248d50397'; Catalogs='WSUS';      WuspLive=$false; Note='WSUS/USS product enumeration; absent from WUSP fe2cr client catalog (0 occurrences in the complete category-tree enumeration)' }
    [pscustomobject]@{ Os='Server2022'; Title='Microsoft server operating system-21H2';  Guid='71718f13-7324-4b0f-8f9e-2ca9dc978e53'; Catalogs='WUSP+WSUS'; WuspLive=$true;  Note='in live WUSP fe2cr client catalog (= Windows Server 2022)' }
    [pscustomobject]@{ Os='Server2025'; Title='Microsoft Server Operating System-24H2';  Guid='b256987d-4693-4c87-955d-dbb9341205eb'; Catalogs='WUSP+WSUS'; WuspLive=$true;  Note='in live WUSP fe2cr client catalog (= Windows Server 2025)' }
  )
  Classifications = @(
    [pscustomobject]@{ Name='SecurityUpdates'; Guid='0FA1201D-4330-4FA8-8AE9-B877473B6441' }
    [pscustomobject]@{ Name='UpdateRollups';   Guid='28BC880E-0592-4CBF-8F95-C79B17911D5F' }
    [pscustomobject]@{ Name='ServicePacks';    Guid='68C5B0A3-D1A6-4553-AE49-01D3A7827828' }
    [pscustomobject]@{ Name='CriticalUpdates'; Guid='E6CF1350-C01B-414D-A61F-263D14D133B4' }
    [pscustomobject]@{ Name='Updates';         Guid='CD5FFD1E-E932-4E3A-BF74-18BF0B1BBD83' }
  )
  Provenance = 'confirmed-seed. Product TITLES are NOT unique -- multiple Product GUIDs per OS (WSUS Get-WsusProduct: Windows Server 2016 = 569e8e8f AND e26d4a30; Windows Server 2019 = f702a48c AND 6e56e6da). Per-product info is gathered per GUID. WUSP-live GUIDs (e26d4a30/6e56e6da/71718f13/b256987d) are confirmed present in the fe2cr anonymous client catalog by the increment-2 base-data run (2026-06-21); the WSUS-only GUIDs (569e8e8f/f702a48c) are real WSUS/USS products (ansible #60785 / dsccommunity #65 + wsusscn2 reverse-match) but were absent from the WUSP client category tree. Server2025=b256987d corrected 2026-05 (old ca006cfb dropped -- lacks KB5087539). Classification GUIDs: WSUS official (the live WUSP list has 8: the 5 seeds + Definition Updates / Feature Packs / Tools). Seeds are validated against the live full lists by the base-data query.'
}

# Intrinsic environment (reused across queries; NO auth state here).
function New-WuspEnv {
    param([Parameter(Mandatory)][string]$ClientEp)
    [pscustomobject]@{
        ClientEp              = $ClientEp
        Ns                    = 'http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService'
        ActionBase            = 'http://www.microsoft.com/SoftwareDistribution/Server/ClientWebService'
        ClientProtocolVersion = '1.8'
        Seeds                 = $Script:WuspSeedCategories
        Contracts             = $Script:WuspContracts
    }
}

# Per-query FRESH auth context: GetConfig -> [SimpleAuth] -> GetCookie. Returns an ephemeral object
# whose Cookie/CookieXml are valid ONLY for the calling query. Conformance-judged (NOT 200=success).
function New-WuspAuthContext {
    param([Parameter(Mandatory)]$WuspEnv)
    $ep=$WuspEnv.ClientEp; $ns=$WuspEnv.Ns; $ab=$WuspEnv.ActionBase; $pv=$WuspEnv.ClientProtocolVersion
    $ctx=[ordered]@{ ClientEp=$ep; Cookie=$null; CookieXml=''; LastChange=$null; IsRegistrationRequired=$null;
                     AuthMode='anonymous'; AuthPlugins=@(); ServerProtocolVersion=$null; Properties=[ordered]@{};
                     AllowedEventIds=@(); Managed=(New-Object System.Collections.ArrayList); Verdicts=[ordered]@{}; Captures=[ordered]@{}; Ok=$false }
    [void]$ctx.Managed.Add((New-ManagedValue -Name 'client.protocolVersion' -Value $pv -Source 'spec-fixed' -SpecRef '2.2.2.2.2' -Justification 'client SHOULD pass 1.8 (FilterCategoryIds needs client >=1.7)'))
    # [1] GetConfig -- no cookie; advertises auth + config (LastChange, IsRegistrationRequired, ProtocolVersion)
    $cfg=Invoke-SoapCapture -Url $ep -Action "$ab/GetConfig" -InnerBody "<GetConfig xmlns=`"$ns`"><protocolVersion>$pv</protocolVersion></GetConfig>"
    $ctx.Verdicts['GetConfig'] = Test-ResponseConformance -Op 'GetConfig' -Cap $cfg -Contracts $Script:WuspContracts
    $ctx.Captures['GetConfig']=$cfg
    if($cfg.IsSuccess -and $cfg.ResponseContent){
        try { $x=[xml]$cfg.ResponseContent
            $ctx.LastChange = Get-XmlText $x 'LastChange'
            $ctx.IsRegistrationRequired = Get-XmlText $x 'IsRegistrationRequired'
            $plugins=@(); foreach($p in $x.SelectNodes("//*[local-name()='AuthPlugInInfo']")){ $pn=Get-XmlText $p 'PlugInID'; if($pn){ $plugins+=$pn } }
            $ctx.AuthPlugins=$plugins
            foreach($pr in $x.SelectNodes("//*[local-name()='ConfigurationProperty']")){ $n=Get-XmlText $pr 'Name'; $v=Get-XmlText $pr 'Value'; if($n){ $ctx.Properties[$n]=$v } }
            $ctx.ServerProtocolVersion=[string]$ctx.Properties['ProtocolVersion']
            foreach($e in $x.SelectNodes("//*[local-name()='AllowedEventIds']/*[local-name()='int']")){ $ctx.AllowedEventIds += $e.InnerText }
            $svc=$x.SelectSingleNode("//*[local-name()='AuthPlugInInfo']/*[local-name()='ServiceUrl']")
            if($svc -and $svc.InnerText){ $ctx.AuthMode='SimpleAuth'; $ctx.Properties['SimpleAuthServiceUrl']=$svc.InnerText }
        } catch {}
    }
    # [2] SimpleAuth path (only if advertised) -- anonymous public path skips this. (GetAuthorizationCookie
    #     wiring deferred to a later increment; recorded so the mode is explicit.)
    $anonAuth='<authCookies><AuthorizationCookie><PlugInId>Anonymous</PlugInId><CookieData></CookieData></AuthorizationCookie></authCookies>'
    [void]$ctx.Managed.Add((New-ManagedValue -Name 'GetCookie.authCookies.PlugInId' -Value 'Anonymous' -Source 'derived' -SpecRef '2.2.3.4' -Justification 'GetConfig advertises no SimpleAuth ServiceUrl -> anonymous AuthorizationCookie'))
    # [3] GetCookie -- consumes Config.LastChange; produces the session Cookie (lives only in this query)
    $lcv = if($ctx.LastChange){$ctx.LastChange}else{'0001-01-01T00:00:00Z'}
    $lcXml = "<lastChange>$lcv</lastChange>"
    [void]$ctx.Managed.Add((New-ManagedValue -Name 'GetCookie.lastChange' -Value ([string]$ctx.LastChange) -Source $(if($ctx.LastChange){'ground-truth'}else{'generated'}) -SpecRef '2.2.2.2.2' -Justification 'echoes GetConfig.LastChange; omitted if Config unavailable'))
    $oldNil='<oldCookie><EncryptedData xsi:nil="true" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" /></oldCookie>'
    $nowXml="<currentTime>$([DateTime]::UtcNow.ToString('o'))</currentTime>"
    $gc=Invoke-SoapCapture -Url $ep -Action "$ab/GetCookie" -InnerBody "<GetCookie xmlns=`"$ns`">$anonAuth$oldNil$lcXml$nowXml<protocolVersion>$pv</protocolVersion></GetCookie>"
    $ctx.Verdicts['GetCookie'] = Test-ResponseConformance -Op 'GetCookie' -Cap $gc -Contracts $Script:WuspContracts
    $ctx.Captures['GetCookie']=$gc
    if($gc.IsSuccess -and $gc.ResponseContent){
        try { $x=[xml]$gc.ResponseContent
            $exp=Get-XmlText $x 'Expiration'; $enc=Get-XmlText $x 'EncryptedData'
            if($enc){ $ctx.Cookie=[pscustomobject]@{Expiration=$exp;EncryptedData=$enc}
                      $ctx.CookieXml="<cookie><Expiration>$exp</Expiration><EncryptedData>$enc</EncryptedData></cookie>" }
        } catch {}
    }
    $ctx.Ok = ([bool]$ctx.Verdicts['GetConfig'].Conformant -and [bool]$ctx.Verdicts['GetCookie'].Conformant -and [bool]$ctx.Cookie)
    [pscustomobject]$ctx
}

# ===================================================================================
# [MS-WUSP] increment 2: base-data category enumeration
#   Spec-grounded (3.1.5.7 SyncUpdates iteration; 3.1.1.1 core-fragment XPATHs;
#   MS-WSUSSS 3.1.1.1 CategoryType discriminator). One independent LIVE query:
#   fresh auth -> SyncUpdates non-leaf loop -> collect Category/Detectoid updates
#   -> GetExtendedUpdateInfo (CategoryType + Title) -> split Classification/Product
#   -> validate the confirmed seeds against the live full lists. Captures raw.
# ===================================================================================

# core fragment is a bare sibling-element sequence (NO <Update> root), confirmed live:
#   <UpdateIdentity UpdateID="GUID" RevisionNumber="N"/><Properties UpdateType="..."/>...
# reliable fields via the spec XPATH attributes (regex on the already-unescaped fragment).
function Get-WuspCoreInfo {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Frag)
    $uid = if ($Frag -match 'UpdateIdentity\s+UpdateID="([^"]+)"') { $Matches[1] } else { $null }
    $rev = if ($Frag -match 'RevisionNumber="(\d+)"') { [int]$Matches[1] } else { $null }
    $ut  = if ($Frag -match '<Properties\b[^>]*\bUpdateType="([^"]+)"') { $Matches[1] } else { $null }
    [pscustomobject]@{ UpdateID = $uid; RevisionNumber = $rev; UpdateType = $ut }
}

# GetExtendedUpdateInfo: CategoryType lives ONLY in the Extended fragment (NOT the core
# fragment -- confirmed: 0 CategoryType across 3556 live core fragments). Title is in
# LocalizedProperties. We map by the UpdateID GUID embedded in each fragment (envelope-
# shape independent), and ALWAYS save the first batches raw to finalize the parse.
function Invoke-WuspGetExtended {
    param(
        [Parameter(Mandatory)][string]$Ep,
        [Parameter(Mandatory)][string]$Ns,
        [Parameter(Mandatory)][string]$Ab,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CookieXml,
        [int[]]$RevisionIDs,
        [int]$BatchSize = 50,
        [string]$RunDir = '',
        [int]$SaveFullN = 2
    )
    $infoTypes = '<infoTypes><XmlUpdateFragmentType>Core</XmlUpdateFragmentType><XmlUpdateFragmentType>Extended</XmlUpdateFragmentType><XmlUpdateFragmentType>LocalizedProperties</XmlUpdateFragmentType></infoTypes>'
    $locales   = '<locales><string>en-US</string></locales>'
    $byRev = @{}
    $batches = New-Object System.Collections.ArrayList
    if (-not $RevisionIDs -or $RevisionIDs.Count -eq 0) { return [pscustomobject]@{ ByRev = $byRev; Batches = $batches } }
    if ($BatchSize -lt 1) { $BatchSize = 50 }
    $b = 0
    for ($i = 0; $i -lt $RevisionIDs.Count; $i += $BatchSize) {
        $b++
        $hi = [Math]::Min($i + $BatchSize - 1, $RevisionIDs.Count - 1)
        $chunk = $RevisionIDs[$i..$hi]
        $ridXml = '<revisionIDs>' + (($chunk | ForEach-Object { "<int>$_</int>" }) -join '') + '</revisionIDs>'
        $body = "<GetExtendedUpdateInfo xmlns=`"$Ns`">$CookieXml$ridXml$infoTypes$locales</GetExtendedUpdateInfo>"
        $cap = Invoke-SoapCapture -Url $Ep -Action "$Ab/GetExtendedUpdateInfo" -InnerBody $body
        $vd  = Test-ResponseConformance -Op 'GetExtendedUpdateInfo' -Cap $cap -Contracts $Script:WuspContracts
        if ($RunDir -and $b -le $SaveFullN) { try { Save-Capture -Dir $RunDir -Prefix ("cap.GetExtendedUpdateInfo.b{0:D2}" -f $b) -Capture $cap } catch {} }
        $parsed = 0
        if ($cap.IsSuccess -and $cap.ResponseContent) {
            try {
                [xml]$xd = $cap.ResponseContent
                # each <Update> = one revisionID (<ID>) + one <Xml> fragment; the server returns
                # TWO Update entries per revision (Extended carries CategoryType via CategoryInformation;
                # LocalizedProperties carries <Title>). Confirmed live: NO <UpdateIdentity> in these
                # extended fragments, so we key by the Update node's <ID> (revisionID) and merge.
                foreach ($un in $xd.SelectNodes("//*[local-name()='Update']")) {
                    $idn = $un.SelectSingleNode("*[local-name()='ID']")
                    if (-not $idn) { continue }
                    $rid = [int]$idn.InnerText
                    $frag = ''
                    foreach ($xn in $un.SelectNodes(".//*[local-name()='Xml']")) { $frag += [string]$xn.InnerText }
                    if (-not $frag) { continue }
                    $ct = if ($frag -match 'CategoryType="([^"]+)"') { $Matches[1] } else { $null }
                    $ti = if ($frag -match '<Title>([^<]+)</Title>') { $Matches[1] } else { $null }
                    $fileObjs = New-Object System.Collections.ArrayList
                    foreach ($fm in [regex]::Matches($frag, '<File\s+([^>]*?)/?>')) {
                        $at = $fm.Groups[1].Value
                        $fnm = if ($at -match 'FileName="([^"]*)"') { $Matches[1] } else { $null }
                        if (-not $fnm) { continue }
                        $fdg = if ($at -match '\bDigest="([^"]*)"') { $Matches[1] } else { $null }
                        $fda = if ($at -match 'DigestAlgorithm="([^"]*)"') { $Matches[1] } else { $null }
                        $fsz = if ($at -match '\bSize="([^"]*)"') { $Matches[1] } else { $null }
                        $fpt = if ($at -match 'PatchingType="([^"]*)"') { $Matches[1] } else { $null }
                        [void]$fileObjs.Add([pscustomobject]@{ Name = $fnm; Digest = $fdg; DigestAlgorithm = $fda; Size = $fsz; PatchingType = $fpt })
                    }
                    $digs = @(@($fileObjs) | ForEach-Object { $_.Digest } | Where-Object { $_ })
                    $fns  = @(@($fileObjs) | ForEach-Object { $_.Name } | Where-Object { $_ })
                    if (-not $byRev.ContainsKey($rid)) { $byRev[$rid] = [pscustomobject]@{ CategoryType = $null; Title = $null; FileDigests = @(); FileNames = @(); Files = @() } }
                    if ($ct -and -not $byRev[$rid].CategoryType) { $byRev[$rid].CategoryType = $ct }
                    if ($ti -and -not $byRev[$rid].Title) { $byRev[$rid].Title = $ti }
                    if ($digs.Count -and -not $byRev[$rid].FileDigests.Count) { $byRev[$rid].FileDigests = @($digs | Select-Object -Unique) }
                    if ($fns.Count -and -not $byRev[$rid].FileNames.Count) { $byRev[$rid].FileNames = @(@($fns) | Select-Object -Unique) }
                    if ($fileObjs.Count -and -not $byRev[$rid].Files.Count) { $byRev[$rid].Files = @($fileObjs) }
                    $parsed++
                }
            } catch {}
        }
        [void]$batches.Add([pscustomobject]@{ Batch = $b; Count = $chunk.Count; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; FragmentsParsed = $parsed })
        if (($b % 10) -eq 0) { Write-Host ("    [{0}] GetExtendedUpdateInfo batch {1} | mapped revs={2}" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$b,$byRev.Count) }
    }
    [pscustomobject]@{ ByRev = $byRev; Batches = $batches }
}

# main increment-2 query. Returns the enumeration result; ALWAYS structured (errors captured).
function Invoke-WuspCategoryEnumeration {
    param(
        [Parameter(Mandatory)]$WuspEnv,
        [Parameter(Mandatory)]$AuthCtx,
        [string]$RunDir = '',
        [int]$MaxRounds = 60,
        [int]$CachedCap = 6000,
        [int]$SaveFullN = 2,
        [switch]$FullEnumeration,
        [int]$ProgressEvery = 0
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $res = [ordered]@{
        Ok = $false; Reason = ''; Rounds = (New-Object System.Collections.ArrayList);
        Categories = (New-Object System.Collections.ArrayList);
        Leaves = (New-Object System.Collections.ArrayList);
        Classifications = (New-Object System.Collections.ArrayList);
        Products = (New-Object System.Collections.ArrayList);
        Companies = (New-Object System.Collections.ArrayList);
        Detectoids = (New-Object System.Collections.ArrayList);
        Uncategorized = (New-Object System.Collections.ArrayList);
        SeedValidation = (New-Object System.Collections.ArrayList);
        Counts = [ordered]@{}; ExtendedBatches = @(); ElapsedSeconds = 0.0; StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    if (-not $AuthCtx -or -not $AuthCtx.Ok) { $res.Reason = 'auth-context-not-ok'; return [pscustomobject]$res }

    $ep = $WuspEnv.ClientEp; $ns = $WuspEnv.Ns; $ab = $WuspEnv.ActionBase
    $ck = [string]$AuthCtx.CookieXml
    $pvOk = $false
    try { if ($AuthCtx.ServerProtocolVersion) { $pvOk = ([version]$AuthCtx.ServerProtocolVersion -ge [version]'3.2') } } catch {}
    $needTwo = if ($pvOk) { '<NeedTwoGroupOutOfScopeUpdates>true</NeedTwoGroupOutOfScopeUpdates>' } else { '' }

    $nonLeaf = New-Object System.Collections.ArrayList   # InstalledNonLeafUpdateIDs accumulator
    $cached  = New-Object System.Collections.ArrayList   # OtherCachedUpdateIDs accumulator (suppresses re-send)
    $seenRev = New-Object 'System.Collections.Generic.HashSet[int]'
    $zeroNonLeafStreak = 0
    $zeroNewStreak = 0

    for ($r = 1; $r -le $MaxRounds; $r++) {
        $nl = Get-ArrayOfIntXml 'InstalledNonLeafUpdateIDs' ($nonLeaf.ToArray())
        $oc = Get-ArrayOfIntXml 'OtherCachedUpdateIDs' ($cached.ToArray())
        $pr = "<parameters><ExpressQuery>false</ExpressQuery>$nl$oc<SkipSoftwareSync>false</SkipSoftwareSync>$needTwo</parameters>"
        $body = "<SyncUpdates xmlns=`"$ns`">$ck$pr</SyncUpdates>"
        $cap = Invoke-SoapCapture -Url $ep -Action "$ab/SyncUpdates" -InnerBody $body
        # FULL ENUM resilience: a 500 here may be a transient/load-variable server close (the old walk
        # reached 468 non-leaf / 3556 total without faulting), so retry the identical request a few
        # times before treating it as terminal. Each attempt is recorded.
        if ($FullEnumeration -and ($null -eq $cap -or -not $cap.IsSuccess -or $cap.StatusCode -ge 400)) {
            for ($attempt = 2; $attempt -le 4; $attempt++) {
                Start-Sleep -Seconds 3
                $cap = Invoke-SoapCapture -Url $ep -Action "$ab/SyncUpdates" -InnerBody $body
                [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = $null; New = 0; NewNonLeaf = 0; Truncated = $null; Note = "retry-attempt-$attempt-http-$($cap.StatusCode)" })
                if ($cap.IsSuccess -and $cap.StatusCode -lt 400) { break }
            }
        }
        $vd  = Test-ResponseConformance -Op 'SyncUpdates' -Cap $cap -Contracts $Script:WuspContracts
        $saveThis = ($RunDir -and ($r -le $SaveFullN))
        if ($saveThis) { try { Save-Capture -Dir $RunDir -Prefix ("cap.SyncUpdates.r{0:D2}" -f $r) -Capture $cap } catch {} }

        if (-not $cap.IsSuccess -or $cap.StatusCode -ge 400) {
            [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = 0; NewNonLeaf = 0; Truncated = $null; Note = 'request-failed-stop' })
            if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix ("cap.SyncUpdates.fail.r{0:D2}" -f $r) -Capture $cap } catch {} }
            $res.Reason = "syncupdates-http-$($cap.StatusCode)-at-round-$r"
            break
        }

        $newCount = 0; $newNonLeaf = 0; $trunc = $null
        try {
            [xml]$xd = $cap.ResponseContent
            foreach ($u in $xd.SelectNodes("//*[local-name()='UpdateInfo']")) {
                $idn = $u.SelectSingleNode("*[local-name()='ID']")
                if (-not $idn) { continue }
                $rid = [int]$idn.InnerText
                if ($seenRev.Contains($rid)) { continue }
                [void]$seenRev.Add($rid); $newCount++
                $leafn = $u.SelectSingleNode("*[local-name()='IsLeaf']")
                $isLeaf = ($leafn -and $leafn.InnerText -eq 'true')
                $xmln = $u.SelectSingleNode("*[local-name()='Xml']")
                $frag = if ($xmln) { [string]$xmln.InnerText } else { '' }
                if (-not $isLeaf) {
                    $newNonLeaf++
                    $info = Get-WuspCoreInfo -Frag $frag
                    # CAP FIX (full enum): InstalledNonLeafUpdateIDs is server-capped at ~400 (>=405 -> ClientFault
                    # InvalidParameters). Detectoids are the bulk (~257) yet NO leaf depends on a detectoid as a
                    # prerequisite (verified: 0/1426), so they need not be declared as installed-non-leaf. Declare
                    # ONLY Category-type non-leaf (products/classifications = the actual leaf prerequisites, ~158)
                    # in InstalledNonLeafUpdateIDs, and route detectoids / Ref nodes to OtherCachedUpdateIDs
                    # (uncapped; suppresses re-send). This keeps the capped array under the limit while still
                    # revealing every leaf. (Non-full paths are unchanged: they stop at category-tree-complete.)
                    $declIn = 'InstalledNonLeaf'
                    if ($FullEnumeration -and $info.UpdateType -ne 'Category') {
                        [void]$cached.Add($rid); $declIn = 'OtherCached'
                    } else {
                        [void]$nonLeaf.Add($rid)
                    }
                    $catRec = [pscustomobject]@{ RevisionID = $rid; UpdateID = $info.UpdateID; RevisionNumber = $info.RevisionNumber; UpdateType = $info.UpdateType }
                    if ($FullEnumeration) {
                        Add-Member -InputObject $catRec -NotePropertyName Frag -NotePropertyValue $frag -Force
                        Add-Member -InputObject $catRec -NotePropertyName Unparseable -NotePropertyValue ([bool](-not $info.UpdateID)) -Force
                        Add-Member -InputObject $catRec -NotePropertyName FirstSeenRound -NotePropertyValue $r -Force
                        Add-Member -InputObject $catRec -NotePropertyName DeclaredIn -NotePropertyValue $declIn -Force
                    }
                    [void]$res.Categories.Add($catRec)
                } else {
                    [void]$cached.Add($rid)
                    if ($FullEnumeration) {
                        # FULL SET: preserve every leaf with its applicability fragment so the
                        # downstream SEED-value filtering operates on the complete corpus (no
                        # presupposition about which leaves matter -- capture all, filter later).
                        $linfo = Get-WuspCoreInfo -Frag $frag
                        [void]$res.Leaves.Add([pscustomobject]@{ RevisionID = $rid; UpdateID = $linfo.UpdateID; RevisionNumber = $linfo.RevisionNumber; UpdateType = $linfo.UpdateType; Frag = $frag })
                    }
                }
            }
            $tn = $xd.SelectSingleNode("//*[local-name()='Truncated']")
            $trunc = ($tn -and $tn.InnerText -eq 'true')
            # follow NewCookie within this query (intra-query continuation, per protocol)
            $ncEnc = $xd.SelectSingleNode("//*[local-name()='NewCookie']/*[local-name()='EncryptedData']")
            $ncExp = $xd.SelectSingleNode("//*[local-name()='NewCookie']/*[local-name()='Expiration']")
            if ($ncEnc -and $ncEnc.InnerText) {
                $expTxt = if ($ncExp) { [string]$ncExp.InnerText } else { '' }
                $ck = "<cookie><Expiration>$expTxt</Expiration><EncryptedData>$($ncEnc.InnerText)</EncryptedData></cookie>"
            }
        } catch {
            [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = $newCount; NewNonLeaf = $newNonLeaf; Truncated = $trunc; Note = "parse-error: $($_.Exception.Message)" })
            $res.Reason = "syncinfo-parse-error-at-round-$r"
            break
        }

        [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = $newCount; NewNonLeaf = $newNonLeaf; Truncated = $trunc; Note = '' })
        # FULL ENUM progress: timestamped, with elapsed + throughput (WSUSSS-style logging cadence)
        if ($ProgressEvery -gt 0 -and ($r % $ProgressEvery -eq 0)) {
            $el = $sw.Elapsed.TotalSeconds
            $tot = $seenRev.Count
            $rate = if ($el -gt 0) { [math]::Round($tot / $el, 1) } else { 0 }
            $catN = @(@($res.Categories) | Where-Object { $_.DeclaredIn -eq 'InstalledNonLeaf' }).Count
            Write-Host ("    [{0}] round {1}/{2} | leaves={3} non-leaf={4} (InstalledNonLeaf={5}) | distinct={6} | {7:N1}s elapsed, {8}/s" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')), $r, $MaxRounds, @($res.Leaves).Count, @($res.Categories).Count, $catN, $tot, $el, $rate)
        }
        # FULL ENUM diagnosis: save the response of any round that reveals NEW non-leaf (a category/bundle
        # burst, e.g. the round-30 burst that preceded the InstalledNonLeafUpdateIDs fault) even past SaveFullN.
        if ($FullEnumeration -and $RunDir -and $newNonLeaf -gt 0 -and -not $saveThis) { try { Save-Capture -Dir $RunDir -Prefix ("cap.SyncUpdates.burst.r{0:D2}" -f $r) -Capture $cap } catch {} }

        if ($newNonLeaf -eq 0) { $zeroNonLeafStreak++ } else { $zeroNonLeafStreak = 0 }
        # category tree complete: no new non-leaf for 2 rounds. This EARLY stop abandons the leaves
        # and is only valid when we just need the category baseline (e.g. the product-scan seed).
        # For FULL enumeration we must NOT stop here -- we continue until the whole set (all leaves
        # included) is enumerated, i.e. true completion below.
        if (-not $FullEnumeration -and $zeroNonLeafStreak -ge 2) { $res.Reason = 'category-tree-complete'; break }
        if ($newCount -eq 0 -and -not $trunc) { $res.Reason = 'sync-complete'; break }
        # full enumeration: also a no-new-distinct round (server only re-sends) means the corpus is
        # complete even if the server keeps Truncated=true, so stop after 2 zero-new-distinct rounds.
        if ($FullEnumeration) { if ($newCount -eq 0) { $zeroNewStreak++ } else { $zeroNewStreak = 0 }; if ($zeroNewStreak -ge 2) { $res.Reason = 'full-enumeration-complete-no-new-distinct'; break } }
        if ($cached.Count -gt $CachedCap) { $res.Reason = "cached-cap-$CachedCap-reached"; break }
        if ($r -eq $MaxRounds) { $res.Reason = "max-rounds-$MaxRounds-reached" }
    }

    # GetExtendedUpdateInfo on Category-type revisions -> CategoryType + Title
    $catRevs = @($res.Categories | Where-Object { $_.UpdateType -eq 'Category' } | ForEach-Object { [int]$_.RevisionID })
    $maxExt = 50
    try { if ($AuthCtx.Properties['MaxExtendedUpdatesPerRequest']) { $maxExt = [int]$AuthCtx.Properties['MaxExtendedUpdatesPerRequest'] } } catch {}
    $ext = Invoke-WuspGetExtended -Ep $ep -Ns $ns -Ab $ab -CookieXml $ck -RevisionIDs $catRevs -BatchSize $maxExt -RunDir $RunDir -SaveFullN $SaveFullN
    $res.ExtendedBatches = @($ext.Batches)

    # classify each collected category using the live CategoryType (spec discriminator), joined by revisionID
    $rev2ct = @{}   # guid(lower) -> CategoryType, for seed validation
    foreach ($c in $res.Categories) {
        $ct = $null; $ti = $null
        if ($ext.ByRev.ContainsKey([int]$c.RevisionID)) { $ct = $ext.ByRev[[int]$c.RevisionID].CategoryType; $ti = $ext.ByRev[[int]$c.RevisionID].Title }
        if ($c.UpdateID -and $ct) { $rev2ct[([string]$c.UpdateID).ToLowerInvariant()] = $ct }
        $row = [pscustomobject]@{ RevisionID = $c.RevisionID; UpdateID = $c.UpdateID; UpdateType = $c.UpdateType; CategoryType = $ct; Title = $ti }
        if ($c.UpdateType -eq 'Detectoid') { [void]$res.Detectoids.Add($row); continue }
        switch ($ct) {
            'UpdateClassification' { [void]$res.Classifications.Add($row) }
            'Company'              { [void]$res.Companies.Add($row) }
            'Product'              { [void]$res.Products.Add($row) }
            'ProductFamily'        { [void]$res.Products.Add($row) }
            default                { [void]$res.Uncategorized.Add($row) }
        }
    }

    # validate the confirmed seeds against the LIVE full lists (presence check)
    $liveGuids = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($c in $res.Categories) { if ($c.UpdateID) { [void]$liveGuids.Add(([string]$c.UpdateID).ToLowerInvariant()) } }
    $seedRoot = $WuspEnv.Seeds
    $prodSeeds = $null; $clsSeeds = $null
    if ($seedRoot -is [System.Collections.IDictionary]) {
        if ($seedRoot.Contains('Products'))        { $prodSeeds = $seedRoot['Products'] }
        if ($seedRoot.Contains('Classifications')) { $clsSeeds  = $seedRoot['Classifications'] }
    } elseif ($seedRoot) {
        if ($seedRoot.PSObject.Properties['Products'])        { $prodSeeds = $seedRoot.Products }
        if ($seedRoot.PSObject.Properties['Classifications']) { $clsSeeds  = $seedRoot.Classifications }
    }
    $seedSets = @(
        @{ Kind = 'Product';        Items = $prodSeeds; NameProp = 'Os' },
        @{ Kind = 'Classification'; Items = $clsSeeds;  NameProp = 'Name' }
    )
    foreach ($ss in $seedSets) {
        if (-not $ss.Items) { continue }
        foreach ($item in $ss.Items) {
            $name = [string]$item.($ss.NameProp)
            $guid = [string]$item.Guid
            $gk = $guid.ToLowerInvariant()
            $present = $liveGuids.Contains($gk)
            $liveCt = $null
            if ($rev2ct.ContainsKey($gk)) { $liveCt = $rev2ct[$gk] }
            [void]$res.SeedValidation.Add([pscustomobject]@{ Kind = $ss.Kind; Name = $name; Guid = $guid; PresentInLiveList = $present; LiveCategoryType = $liveCt })
        }
    }

    $res.Counts = [pscustomobject]([ordered]@{
        Rounds = $res.Rounds.Count
        TotalCategories = $res.Categories.Count
        Classifications = $res.Classifications.Count
        Products = $res.Products.Count
        Companies = $res.Companies.Count
        Detectoids = $res.Detectoids.Count
        Uncategorized = $res.Uncategorized.Count
        SeedsPresent = (@($res.SeedValidation | Where-Object { $_.PresentInLiveList }).Count)
        SeedsTotal = $res.SeedValidation.Count
    })
    $res.Ok = ($res.Categories.Count -gt 0)
    $res.ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    [pscustomobject]$res
}

# ===================================================================================
# [MS-WUSP] LEAF DEPTH increment: complete the remaining ClientWebService ops.
#   DEPTH CHAIN (leaf -> files -> URLs), spec-grounded:
#     GetExtendedUpdateInfo (2.2.2.2.6, infoTypes Core/Extended/.. -> FileDigest SHA-1)
#       -> GetExtendedUpdateInfo2 (2.2.2.2.10, infoTypes FileUrl/FileDecryption ONLY -> FileLocations)
#       -> GetFileLocations     (2.2.2.2.7, fileDigests base64 SHA-1 -> URLs)
#   STANDALONE PROBES (single conformance call each):
#     RegisterComputer (2.2.2.2.3, computerInfo), RefreshCache (2.2.2.2.5, globalIDs),
#     SyncPrinterCatalog (2.2.2.2.9, installedNonLeafUpdateIDs+printerUpdateIDs)
#   NOTE: GetExtendedUpdateInfo2 infoTypes is spec-restricted to FileUrl/FileDecryption (the old
#   PART2 sent 8 values -- a spec violation; corrected here). All ops conformance-judged (NOT 200).
# ===================================================================================
function New-WuspOpRecord {
    # Verdict-aware op record. Some HTTP-500 faults are the CORRECT spec response for the anonymous
    # public profile (NOT non-conformance): GetExtendedUpdateInfo2 needs authentication (FailedAuthentication),
    # RegisterComputer reports RegistrationNotRequired. Classify those as expected-out-of-profile, like WSUSSS B10-B17.
    param([string]$Op,[string]$Scope,$Vd,[string]$Resp = '',[string]$Note = '')
    $expected = @{ 'GetExtendedUpdateInfo2' = @('FailedAuthentication'); 'RegisterComputer' = @('RegistrationNotRequired') }
    $conf = [bool]$Vd.Conformant
    $class = 'non-conformant'
    if ($conf) { $class = 'conformant' }
    elseif ($expected.ContainsKey($Op)) { foreach ($pat in $expected[$Op]) { if ($Resp -and ($Resp -match $pat)) { $class = 'expected-out-of-profile'; break } } }
    [pscustomobject]@{ Op = $Op; Scope = $Scope; Conformant = $conf; Class = $class; Expected = ($class -eq 'expected-out-of-profile'); HttpStatus = $Vd.HttpStatus; Failures = (@($Vd.Failures) -join ','); Note = $Note }
}

function Invoke-WuspLeafDepth {
    param(
        [Parameter(Mandatory)]$WuspEnv,
        [Parameter(Mandatory)]$AuthCtx,
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)]$Leaves,
        [string]$RunDir = '',
        [int]$SampleSize = 25,
        [int]$DigestCap = 60,
        [int[]]$SeedNonLeafRevisionIDs = @()
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ep = $WuspEnv.ClientEp; $ns = $WuspEnv.Ns; $ab = $WuspEnv.ActionBase
    $ck = [string]$AuthCtx.CookieXml
    $ops = New-Object System.Collections.ArrayList
    $res = [ordered]@{
        Reason = ''; SampleSize = 0; Ops = $ops;
        FileDigests = @(); Eui2Urls = @(); GflUrls = @();
        ElapsedSeconds = 0.0; StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $sample = @($Leaves | Where-Object { $_.UpdateID } | Select-Object -First $SampleSize)
    $res.SampleSize = $sample.Count
    if ($sample.Count -eq 0) { $res.Reason = 'no-leaves'; $res.ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); return [pscustomobject]$res }

    # infoTypes: the public host rejects Published/VerificationRule/Eula (InvalidParameters: fragmentTypes);
    # Core/Extended/LocalizedProperties is the accepted subset and carries Title + the <Files> element.
    $itExt  = '<infoTypes>' + ((@('Core','Extended','LocalizedProperties') | ForEach-Object { "<XmlUpdateFragmentType>$_</XmlUpdateFragmentType>" }) -join '') + '</infoTypes>'
    $itExt2 = '<infoTypes>' + ((@('FileUrl','FileDecryption') | ForEach-Object { "<XmlUpdateFragmentType>$_</XmlUpdateFragmentType>" }) -join '') + '</infoTypes>'
    $loc    = '<locales><string>en-US</string></locales>'
    $uidArr = '<updateIDs>' + (($sample | ForEach-Object { "<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$([int]$_.RevisionNumber)</RevisionNumber></UpdateIdentity>" }) -join '') + '</updateIDs>'

    Write-Detail 'leaf-depth sample' ("{0} leaves (leaf-first); depth chain + 3 standalone probes" -f $sample.Count)

    # ---- [1] GetExtendedUpdateInfo on LEAF revisionIDs -> harvest FileDigest (SHA-1) ----
    $script:opStart = [DateTime]::Now
    $revXml = '<revisionIDs>' + (($sample | ForEach-Object { "<int>$([int]$_.RevisionID)</int>" }) -join '') + '</revisionIDs>'
    $eui = Invoke-SoapCapture -Url $ep -Action "$ab/GetExtendedUpdateInfo" -InnerBody "<GetExtendedUpdateInfo xmlns=`"$ns`">$ck$revXml$itExt$loc</GetExtendedUpdateInfo>"
    $euiVd = Test-ResponseConformance -Op 'GetExtendedUpdateInfo' -Cap $eui -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '30.getextendedupdateinfo.leaf' -Capture $eui } catch {} }
    $digests = @()
    if ($eui.IsSuccess -and $eui.ResponseContent) { try { $digests = @([regex]::Matches($eui.ResponseContent, '<File\s+[^>]*?\bDigest="([^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $DigestCap) } catch {} }
    $res.FileDigests = $digests
    [void]$ops.Add((New-WuspOpRecord -Op 'GetExtendedUpdateInfo' -Scope 'leaf' -Vd $euiVd -Resp $eui.ResponseContent -Note ("revIDs={0} digests={1}" -f $sample.Count, $digests.Count)))
    $script:opStart = $null

    # ---- [2] GetExtendedUpdateInfo2 on LEAF UpdateIdentities (FileUrl+FileDecryption) -> FileLocations URLs ----
    $eui2 = Invoke-SoapCapture -Url $ep -Action "$ab/GetExtendedUpdateInfo2" -InnerBody "<GetExtendedUpdateInfo2 xmlns=`"$ns`">$ck$uidArr$itExt2$loc</GetExtendedUpdateInfo2>"
    $eui2Vd = Test-ResponseConformance -Op 'GetExtendedUpdateInfo2' -Cap $eui2 -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '31.getextendedupdateinfo2.leaf' -Capture $eui2 } catch {} }
    $u2 = @()
    if ($eui2.IsSuccess -and $eui2.ResponseContent) { try { $u2 = @([regex]::Matches($eui2.ResponseContent, '<Url>([^<]+)</Url>') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First 200) } catch {} }
    $res.Eui2Urls = $u2
    [void]$ops.Add((New-WuspOpRecord -Op 'GetExtendedUpdateInfo2' -Scope 'leaf' -Vd $eui2Vd -Resp $eui2.ResponseContent -Note ("updateIDs={0} urls={1}" -f $sample.Count, $u2.Count)))

    # ---- [3] GetFileLocations on harvested digests -> URLs ----
    $fdXml = if ($digests.Count) { '<fileDigests>' + (($digests | ForEach-Object { "<base64Binary>$_</base64Binary>" }) -join '') + '</fileDigests>' } else { '<fileDigests />' }
    $gfl = Invoke-SoapCapture -Url $ep -Action "$ab/GetFileLocations" -InnerBody "<GetFileLocations xmlns=`"$ns`">$ck$fdXml</GetFileLocations>"
    $gflVd = Test-ResponseConformance -Op 'GetFileLocations' -Cap $gfl -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '32.getfilelocations' -Capture $gfl } catch {} }
    $gu = @()
    if ($gfl.IsSuccess -and $gfl.ResponseContent) { try { $gu = @([regex]::Matches($gfl.ResponseContent, '<Url>([^<]+)</Url>') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First 200) } catch {} }
    $res.GflUrls = $gu
    [void]$ops.Add((New-WuspOpRecord -Op 'GetFileLocations' -Scope 'digests' -Vd $gflVd -Resp $gfl.ResponseContent -Note ("digests={0} urls={1}" -f $digests.Count, $gu.Count)))

    # ---- [4] RegisterComputer (computerInfo from client-generated identity; all minOccurs=1 fields, spec order) ----
    $cvM = 0; $cvN = 0; $cvB = 0; $cvQ = 0
    try { $cvp = ([string]$Identity.WuaAgentVersion -split '\.'); if ($cvp.Count -ge 1) { [int]::TryParse($cvp[0], [ref]$cvM) | Out-Null }; if ($cvp.Count -ge 2) { [int]::TryParse($cvp[1], [ref]$cvN) | Out-Null }; if ($cvp.Count -ge 3) { [int]::TryParse($cvp[2], [ref]$cvB) | Out-Null }; if ($cvp.Count -ge 4) { [int]::TryParse($cvp[3], [ref]$cvQ) | Out-Null } } catch {}
    if ($cvM -gt 32767) { $cvM = 0 }; if ($cvN -gt 32767) { $cvN = 0 }; if ($cvB -gt 32767) { $cvB = 0 }; if ($cvQ -gt 32767) { $cvQ = 0 }
    $ci = "<computerInfo>" +
        "<OSMajorVersion>$($Identity.OSMajorVersion)</OSMajorVersion>" +
        "<OSMinorVersion>$($Identity.OSMinorVersion)</OSMinorVersion>" +
        "<OSBuildNumber>$($Identity.OSBuildNumber)</OSBuildNumber>" +
        "<OSServicePackMajorNumber>0</OSServicePackMajorNumber>" +
        "<OSServicePackMinorNumber>0</OSServicePackMinorNumber>" +
        "<BiosReleaseDate>2024-01-01T00:00:00Z</BiosReleaseDate>" +
        "<ProcessorArchitecture>$($Identity.ProcessorArchitecture)</ProcessorArchitecture>" +
        "<SuiteMask>$($Identity.SuiteMask)</SuiteMask>" +
        "<OldProductType>$($Identity.OldProductType)</OldProductType>" +
        "<NewProductType>$($Identity.NewProductTypeSKU)</NewProductType>" +
        "<SystemMetrics>0</SystemMetrics>" +
        "<ClientVersionMajorNumber>$cvM</ClientVersionMajorNumber>" +
        "<ClientVersionMinorNumber>$cvN</ClientVersionMinorNumber>" +
        "<ClientVersionBuildNumber>$cvB</ClientVersionBuildNumber>" +
        "<ClientVersionQfeNumber>$cvQ</ClientVersionQfeNumber>" +
        "</computerInfo>"
    $rc = Invoke-SoapCapture -Url $ep -Action "$ab/RegisterComputer" -InnerBody "<RegisterComputer xmlns=`"$ns`">$ck$ci</RegisterComputer>"
    $rcVd = Test-ResponseConformance -Op 'RegisterComputer' -Cap $rc -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '33.registercomputer' -Capture $rc } catch {} }
    [void]$ops.Add((New-WuspOpRecord -Op 'RegisterComputer' -Scope 'computerInfo' -Vd $rcVd -Resp $rc.ResponseContent -Note ("build={0}.{1}" -f $Identity.OSBuildNumber, $Identity.UBR)))

    # ---- [5] RefreshCache (globalIDs = sample leaf UpdateIdentities) ----
    $gid = '<globalIDs>' + (($sample | ForEach-Object { "<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$([int]$_.RevisionNumber)</RevisionNumber></UpdateIdentity>" }) -join '') + '</globalIDs>'
    $rcf = Invoke-SoapCapture -Url $ep -Action "$ab/RefreshCache" -InnerBody "<RefreshCache xmlns=`"$ns`">$ck$gid</RefreshCache>"
    $rcfVd = Test-ResponseConformance -Op 'RefreshCache' -Cap $rcf -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '34.refreshcache' -Capture $rcf } catch {} }
    [void]$ops.Add((New-WuspOpRecord -Op 'RefreshCache' -Scope 'globalIDs' -Vd $rcfVd -Resp $rcf.ResponseContent -Note ("globalIDs={0}" -f $sample.Count)))

    # ---- [6] SyncPrinterCatalog (cookie present; SEEDED installedNonLeaf -- empty array faults InvalidParameters) ----
    $spcInl = if (@($SeedNonLeafRevisionIDs).Count) { '<installedNonLeafUpdateIDs>' + ((@($SeedNonLeafRevisionIDs) | Select-Object -First 200 | ForEach-Object { "<int>$([int]$_)</int>" }) -join '') + '</installedNonLeafUpdateIDs>' } else { '<installedNonLeafUpdateIDs />' }
    $spc = Invoke-SoapCapture -Url $ep -Action "$ab/SyncPrinterCatalog" -InnerBody "<SyncPrinterCatalog xmlns=`"$ns`">$ck$spcInl<printerUpdateIDs /></SyncPrinterCatalog>"
    $spcVd = Test-ResponseConformance -Op 'SyncPrinterCatalog' -Cap $spc -Contracts $Script:WuspContracts
    if ($RunDir) { try { Save-Capture -Dir $RunDir -Prefix '35.syncprintercatalog' -Capture $spc } catch {} }
    [void]$ops.Add((New-WuspOpRecord -Op 'SyncPrinterCatalog' -Scope 'seeded-probe' -Vd $spcVd -Resp $spc.ResponseContent -Note ("installedNonLeaf={0} printerUpdateIDs=0" -f @($SeedNonLeafRevisionIDs).Count)))

    $res.ElapsedSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    [pscustomobject]$res
}

# ===================================================================================
# [MS-WUSP] increment 3: per-product scoped query (multi-GUID premise)
#   A product TITLE is not unique -> each Product GUID is an independent first-class query.
#   Flow (spec 3.1.5.6 + 2.2.2.2.8): StartCategoryScan(CategoryId=productGuid) [NO cookie]
#   -> preferredCategoryIds (recognized+expanded) / requestedCategoryIdsInError (unrecognized
#   by the server -> direct evidence a GUID is not in this catalog) -> FilterCategoryIds
#   (ArrayOfCategoryIdentifier {Id=guid}) -> scoped SyncUpdates loop (collect the leaf patches).
#   Evidence is saved per GUID with the GUID embedded in the directory and file names.
# ===================================================================================

function ConvertTo-WuspGuidList {
    # parse an ArrayOfGuid node (<guid>..</guid> children) under a named parent
    param($Xd, [string]$ParentLocal)
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $Xd) { return $out }
    $p = $Xd.SelectSingleNode("//*[local-name()='$ParentLocal']")
    if ($p) { foreach ($g in $p.SelectNodes("*[local-name()='guid']")) { if ($g.InnerText) { [void]$out.Add([string]$g.InnerText) } } }
    $out
}

function Invoke-WuspProductScan {
    param(
        [Parameter(Mandatory)]$WuspEnv,
        [Parameter(Mandatory)]$AuthCtx,
        [Parameter(Mandatory)][string]$Os,
        [Parameter(Mandatory)][string]$ProductGuid,
        [string]$Title = '',
        [int[]]$SeedNonLeafRevisionIDs = @(),
        [int[]]$SeedCachedRevisionIDs = @(),
        [string]$RunDir = '',
        [int]$MaxRounds = 8,
        [int]$CachedCap = 8000,
        [int]$SaveFullN = 2
    )
    $res = [ordered]@{
        Os = $Os; ProductGuid = $ProductGuid; Title = $Title; Ok = $false; Reason = '';
        SeedNonLeafCount = @($SeedNonLeafRevisionIDs).Count;
        ScanConformant = $false; ScanHttp = 0; Recognized = $false;
        PreferredCategoryIds = @(); RequestedInError = @();
        Rounds = (New-Object System.Collections.ArrayList);
        LeafPatches = (New-Object System.Collections.ArrayList);
        NonLeafSeen = 0; Completed = $false; Counts = $null
    }
    $ep = $WuspEnv.ClientEp; $ns = $WuspEnv.Ns; $ab = $WuspEnv.ActionBase
    if (-not $AuthCtx -or -not $AuthCtx.Ok) { $res.Reason = 'auth-context-not-ok'; return [pscustomobject]$res }
    $ck = [string]$AuthCtx.CookieXml

    # per-GUID evidence sink: directory + filenames carry the GUID
    $pdir = ''
    if ($RunDir) { $pdir = [IO.Path]::Combine($RunDir, ("{0}__{1}" -f $Os, $ProductGuid)); New-Item -ItemType Directory -Force -Path $pdir | Out-Null }

    # [1] StartCategoryScan (no cookie). Per spec 3.1.5.6 the PreferredCategoryList for a
    # (product AND classification) group returns ONLY the product, so FilterCategoryIds = the
    # product. Classification scoping is therefore NOT done here -- it is done by satisfying the
    # leaf prerequisites (product AND classification) via InstalledNonLeafUpdateIDs (the seed).
    $rc = "<requestedCategories><CategoryRelationship><IndexOfAndGroup>0</IndexOfAndGroup><CategoryId>$ProductGuid</CategoryId></CategoryRelationship></requestedCategories>"
    $scan = Invoke-SoapCapture -Url $ep -Action "$ab/StartCategoryScan" -InnerBody "<StartCategoryScan xmlns=`"$ns`">$rc</StartCategoryScan>"
    $scanVd = Test-ResponseConformance -Op 'StartCategoryScan' -Cap $scan -Contracts $Script:WuspContracts
    $res.ScanConformant = [bool]$scanVd.Conformant; $res.ScanHttp = $scan.StatusCode
    if ($pdir) { try { Save-Capture -Dir $pdir -Prefix ("cap.StartCategoryScan.{0}" -f $ProductGuid) -Capture $scan } catch {} }
    if ($scan.IsSuccess -and $scan.ResponseContent) {
        try {
            [xml]$sx = $scan.ResponseContent
            $res.PreferredCategoryIds = @(ConvertTo-WuspGuidList -Xd $sx -ParentLocal 'preferredCategoryIds')
            $res.RequestedInError    = @(ConvertTo-WuspGuidList -Xd $sx -ParentLocal 'requestedCategoryIdsInError')
        } catch { $res.Reason = "scan-parse-error: $($_.Exception.Message)" }
    } else {
        $res.Reason = "startcategoryscan-http-$($scan.StatusCode)"; return [pscustomobject]$res
    }
    $gl = $ProductGuid.ToLowerInvariant()
    $res.Recognized = (@($res.RequestedInError | Where-Object { ([string]$_).ToLowerInvariant() -eq $gl }).Count -eq 0) -and ($res.PreferredCategoryIds.Count -gt 0)

    if ($res.PreferredCategoryIds.Count -eq 0) {
        # not scannable in this catalog -- this IS the evidence (expected for WSUS-only GUIDs)
        $res.Reason = 'no-preferred-categories (GUID not recognized by the WUSP server)'
        $res.Counts = [pscustomobject]([ordered]@{ Preferred = 0; InError = $res.RequestedInError.Count; Rounds = 0; LeafPatches = 0; NonLeafSeen = 0 })
        $res.Ok = $true   # the query itself succeeded; absence is a valid result
        return [pscustomobject]$res
    }

    # [2] FilterCategoryIds (ArrayOfCategoryIdentifier {Id=guid}) from the preferred set
    $fci = '<FilterCategoryIds>' + (($res.PreferredCategoryIds | ForEach-Object { "<CategoryIdentifier><Id>$_</Id></CategoryIdentifier>" }) -join '') + '</FilterCategoryIds>'

    # [3] scoped SyncUpdates loop -- collect the leaf patches under this product
    # SEED InstalledNonLeafUpdateIDs with the full non-leaf category baseline so the leaves'
    # (product AND classification) prerequisites are satisfied (the product filter alone never
    # surfaces the classification categories, so without the seed no leaf enters NeededRevisions).
    $nonLeaf = New-Object System.Collections.ArrayList
    $seenNL  = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($sid in @($SeedNonLeafRevisionIDs)) { if ($seenNL.Add([int]$sid)) { [void]$nonLeaf.Add([int]$sid) } }
    $cached  = New-Object System.Collections.ArrayList
    foreach ($sid in @($SeedCachedRevisionIDs)) { if ($seenNL.Add([int]$sid)) { [void]$cached.Add([int]$sid) } }
    $seen    = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($r = 1; $r -le $MaxRounds; $r++) {
        $nl = Get-ArrayOfIntXml 'InstalledNonLeafUpdateIDs' ($nonLeaf.ToArray())
        $oc = Get-ArrayOfIntXml 'OtherCachedUpdateIDs' ($cached.ToArray())
        $pr = "<parameters><ExpressQuery>false</ExpressQuery>$nl$oc<SkipSoftwareSync>false</SkipSoftwareSync>$fci<NeedTwoGroupOutOfScopeUpdates>true</NeedTwoGroupOutOfScopeUpdates></parameters>"
        $cap = Invoke-SoapCapture -Url $ep -Action "$ab/SyncUpdates" -InnerBody "<SyncUpdates xmlns=`"$ns`">$ck$pr</SyncUpdates>"
        $vd  = Test-ResponseConformance -Op 'SyncUpdates' -Cap $cap -Contracts $Script:WuspContracts
        if ($pdir -and $r -le $SaveFullN) { try { Save-Capture -Dir $pdir -Prefix ("cap.SyncUpdates.{0}.r{1:D2}" -f $ProductGuid, $r) -Capture $cap } catch {} }
        if (-not $cap.IsSuccess -or $cap.StatusCode -ge 400) {
            [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = 0; NewLeaf = 0; Truncated = $null; Note = 'request-failed-stop' })
            $res.Reason = "scoped-syncupdates-http-$($cap.StatusCode)-at-round-$r"; break
        }
        $newCount = 0; $newLeaf = 0; $trunc = $null
        try {
            [xml]$xd = $cap.ResponseContent
            foreach ($u in $xd.SelectNodes("//*[local-name()='UpdateInfo']")) {
                $idn = $u.SelectSingleNode("*[local-name()='ID']"); if (-not $idn) { continue }
                $rid = [int]$idn.InnerText
                if ($seen.Contains($rid)) { continue }
                [void]$seen.Add($rid); $newCount++
                $leafn = $u.SelectSingleNode("*[local-name()='IsLeaf']")
                $isLeaf = ($leafn -and $leafn.InnerText -eq 'true')
                $xmln = $u.SelectSingleNode("*[local-name()='Xml']")
                $frag = if ($xmln) { [string]$xmln.InnerText } else { '' }
                if ($isLeaf) {
                    [void]$cached.Add($rid); $newLeaf++
                    $info = Get-WuspCoreInfo -Frag $frag
                    [void]$res.LeafPatches.Add([pscustomobject]@{ RevisionID = $rid; UpdateID = $info.UpdateID; RevisionNumber = $info.RevisionNumber; UpdateType = $info.UpdateType; Frag = $frag })
                } else {
                    # Category-only InstalledNonLeaf declaration (cap-safe for full enumeration): keep only
                    # Category non-leaf in the capped array; route Detectoid / other to OtherCachedUpdateIDs (uncapped).
                    $ninfo = Get-WuspCoreInfo -Frag $frag
                    if ($ninfo.UpdateType -eq 'Category') { if ($seenNL.Add($rid)) { [void]$nonLeaf.Add($rid) } }
                    else { if ($seenNL.Add($rid)) { [void]$cached.Add($rid) } }
                    $res.NonLeafSeen++
                }
            }
            $tn = $xd.SelectSingleNode("//*[local-name()='Truncated']"); $trunc = ($tn -and $tn.InnerText -eq 'true')
            $ncEnc = $xd.SelectSingleNode("//*[local-name()='NewCookie']/*[local-name()='EncryptedData']")
            $ncExp = $xd.SelectSingleNode("//*[local-name()='NewCookie']/*[local-name()='Expiration']")
            if ($ncEnc -and $ncEnc.InnerText) { $ck = "<cookie><Expiration>$(if($ncExp){[string]$ncExp.InnerText}else{''})</Expiration><EncryptedData>$($ncEnc.InnerText)</EncryptedData></cookie>" }
        } catch {
            [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = $newCount; NewLeaf = $newLeaf; Truncated = $trunc; Note = "parse-error: $($_.Exception.Message)" })
            $res.Reason = "scoped-syncinfo-parse-error-at-round-$r"; break
        }
        [void]$res.Rounds.Add([pscustomobject]@{ Round = $r; Http = $cap.StatusCode; Conformant = [bool]$vd.Conformant; New = $newCount; NewLeaf = $newLeaf; Truncated = $trunc; Note = '' })
        if ($newCount -eq 0 -and -not $trunc) { $res.Completed = $true; $res.Reason = 'scoped-sync-complete'; break }
        if ($cached.Count -gt $CachedCap) { $res.Reason = "cached-cap-$CachedCap-reached (bounded sample)"; break }
        if ($r -eq $MaxRounds -and -not $res.Completed) { $res.Reason = "max-rounds-$MaxRounds-reached (bounded sample; more updates remain)" }
    }
    if (-not $res.Reason) { $res.Reason = 'scoped-sync-complete'; $res.Completed = $true }
    $res.Counts = [pscustomobject]([ordered]@{ Preferred = $res.PreferredCategoryIds.Count; InError = $res.RequestedInError.Count; Rounds = $res.Rounds.Count; LeafPatches = $res.LeafPatches.Count; NonLeafSeen = $res.NonLeafSeen; Completed = $res.Completed })
    $res.Ok = $true
    if ($pdir) { try { Save-Json -Path ([IO.Path]::Combine($pdir, ("summary.{0}.{1}.json" -f $Os, $ProductGuid))) -Object ([pscustomobject]$res) } catch {} }
    if ($pdir) { try { Save-Json -Path ([IO.Path]::Combine($pdir, ("leaves.{0}.{1}.json" -f $Os, $ProductGuid))) -Object @($res.LeafPatches) } catch {} }
    [pscustomobject]$res
}




if ($runWsusss -and $script:WsusssPreflightPass) {
  Write-Host ''
  Write-Host '=== PART 1: [MS-WSUSSS] (catalog distribution -- run FIRST; gates WUSP) ==='
  try {
  $NsSDS='http://www.microsoft.com/SoftwareDistribution'
  $NsDSS='http://www.microsoft.com/SoftwareDistribution/Server/DssAuthWebService'
  $XsiNil='i:nil="true" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"'
  $ssEp= if($WsusssServerSyncEndpoint){$WsusssServerSyncEndpoint}else{'https://sws.update.microsoft.com/ServerSyncWebService/ServerSyncWebService.asmx'}
  $dssEp=if($WsusssDssAuthEndpoint){$WsusssDssAuthEndpoint}else{'https://sws.update.microsoft.com/DssAuthWebService/DssAuthWebService.asmx'}
  # Reporting Web Service (spec 2.1): the rollup/report ops (B12-B17) live on a SEPARATE endpoint from ServerSync.
  $repEp=[regex]::Replace($ssEp,'ServerSyncWebService/ServerSyncWebService\.asmx$','ReportingWebService/ReportingWebService.asmx','IgnoreCase')
  # fixed classification GUIDs (invariant axis; documented section 11.1) -- the complete classification set.
  $WsusssClassifications=@('0fa1201d-4330-4fa8-8ae9-b877473b6441','28bc880e-0592-4cbf-8f95-c79b17911d5f','68c5b0a3-d1a6-4553-ae49-01d3a7827828','e6cf1350-c01b-414d-a61f-263d14d133b4','cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83')

  # [B1] GetAuthConfig (CORE)
  Start-Op 'WSUSSS' 'B1' 'GetAuthConfig'
  $ac=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetAuthConfig" -InnerBody "<GetAuthConfig xmlns=`"$NsSDS`" />"
  $acV=Test-ResponseConformance -Op 'GetAuthConfig' -Cap $ac
  Save-Capture -Dir $wsusssDir -Prefix '01.getauthconfig' -Capture $ac; Add-Cov 'WSUSSS' 'B1' 'GetAuthConfig' $ac 'CORE' $acV
  if(-not $acV.Conformant){ $wsusssCatalogClean=$false }
  $dssUrl=$dssEp
  if($ac.IsSuccess -and $ac.ResponseContent){ try{ $x=[xml]$ac.ResponseContent; foreach($ai in $x.SelectNodes("//*[local-name()='ServerSyncAuthInfo']")){ if((Get-XmlText $ai 'PlugInId') -eq 'DssTargeting'){ $u=Get-XmlText $ai 'ServiceUrl'; if($u){$dssUrl=$u}; break } } }catch{} }
  # Endpoint-derivation provenance (Track2): record HOW each WSUSSS endpoint URL was derived -- no pinning/guessing.
  $null=New-ManagedValue 'endpoint.ServerSync' $ssEp 'derived' '2.1/1.5' 'USS host is admin-configured (1.5: WSUSSS has NO protocol-level endpoint discovery) + spec 2.1 relative path ServerSyncWebService/ServerSyncWebService.asmx. This is the authoritative USS host.'
  $null=New-ManagedValue 'endpoint.DssAuth' $dssUrl 'derived' '2.1/3.1.4.1' ('spec 2.1 path, cross-checked against GetAuthConfig.AuthInfo.ServiceUrl: ' + $(if($dssUrl -ne $dssEp){"server-advertised override -> $dssUrl"}else{'no DssTargeting override advertised; using spec 2.1 default on the USS host'}) + '.')
  $null=New-ManagedValue 'endpoint.Reporting' $repEp 'derived' '2.1' 'SAME USS host as ServerSync + spec 2.1 relative path ReportingWebService/ReportingWebService.asmx. Probing at THIS derived path (not a guessed host) is what makes an absence a bounded NOT-PUBLISHED proof rather than a lone 404.'

  # [B2] GetAuthorizationCookie (CORE)
  $acctGuid=New-ManagedValue 'accountGuid' ([guid]::NewGuid().ToString()) 'generated' '3.1.4.2.2.1' 'accountGuid: GUID identifying the downstream/replica server in the DSS auth handshake. A real WSUS DSS sends its stable SusServerId; for this anonymous catalog survey a per-run GUID stands in (recorded for reproducibility; not interpreted by the public USS for anonymous DssTargeting auth).'
  $acctName=New-ManagedValue 'accountName' 'WSUS-ServerSync-Survey' 'spec-fixed' '3.1.4.2.2.1' 'accountName: the downstream server account NAME (string), DISTINCT from accountGuid. Was previously a duplicate of the GUID -- a data-management defect now corrected to a stable human-readable label. If the live USS rejects this, the B2 conformance verdict will flag it and the gate blocks WUSP (spec-grounded loop, not "it worked").'
  Start-Op 'WSUSSS' 'B2' 'GetAuthorizationCookie'
  $gac=Invoke-SoapCapture -Url $dssUrl -Action "$NsDSS/GetAuthorizationCookie" -InnerBody "<GetAuthorizationCookie xmlns=`"$NsDSS`"><accountName>$acctName</accountName><accountGuid>$acctGuid</accountGuid></GetAuthorizationCookie>"
  $gacV=Test-ResponseConformance -Op 'GetAuthorizationCookie' -Cap $gac
  Save-Capture -Dir $wsusssDir -Prefix '02.getauthorizationcookie' -Capture $gac; Add-Cov 'WSUSSS' 'B2' 'GetAuthorizationCookie' $gac 'CORE' $gacV
  if(-not $gacV.Conformant){ $wsusssCatalogClean=$false }
  $plugInId=$null;$cookieData=$null
  if($gac.IsSuccess -and $gac.ResponseContent){ try{ $x=[xml]$gac.ResponseContent; $plugInId=Get-XmlText $x 'PlugInId'; $cookieData=Get-XmlText $x 'CookieData' }catch{} }

  # [B3] GetCookie -> access cookie (CORE)  (proven body: authCookies + protocolVersion 1.7; NO oldCookie)
  $enc=$null;$exp=$null
  if($cookieData){
    Start-Op 'WSUSSS' 'B3' 'GetCookie'
    $pv17=New-ManagedValue 'GetCookie.protocolVersion' '1.7' 'ground-truth' '3.1.4.3.2.1' 'protocolVersion the client advertises in GetCookie. 1.7 is the proven-accepted value (GetConfigData reports server ProtocolVersion 1.21; the client floor 1.7 is honored). Recorded so the wire version is managed, not incidental.'
    $gc=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetCookie" -InnerBody "<GetCookie xmlns=`"$NsSDS`"><authCookies><AuthorizationCookie><PlugInId>$plugInId</PlugInId><CookieData>$cookieData</CookieData></AuthorizationCookie></authCookies><protocolVersion>$pv17</protocolVersion></GetCookie>"
    $gcV=Test-ResponseConformance -Op 'GetCookie' -Cap $gc
    Save-Capture -Dir $wsusssDir -Prefix '03.getcookie' -Capture $gc; Add-Cov 'WSUSSS' 'B3' 'GetCookie' $gc 'CORE' $gcV
    if(-not $gcV.Conformant){ $wsusssCatalogClean=$false }
    if($gcV.Conformant -and $gc.ResponseContent){ try{ $x=[xml]$gc.ResponseContent; $enc=Get-XmlText $x 'EncryptedData'; $exp=Get-XmlText $x 'Expiration' }catch{} }
  } else { Add-Cov 'WSUSSS' 'B3' 'GetCookie' $null 'CORE skipped: no CookieData'; $wsusssCatalogClean=$false }
  $sck= if($enc){"<cookie><Expiration>$exp</Expiration><EncryptedData>$enc</EncryptedData></cookie>"}else{'<cookie></cookie>'}

  # [B4] GetConfigData (CORE) -- harvest NewConfigAnchor
  Start-Op 'WSUSSS' 'B4' 'GetConfigData'
  $gcd=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetConfigData" -InnerBody "<GetConfigData xmlns=`"$NsSDS`">$sck<configAnchor $XsiNil /></GetConfigData>"
  $gcdV=Test-ResponseConformance -Op 'GetConfigData' -Cap $gcd
  Save-Capture -Dir $wsusssDir -Prefix '04.getconfigdata' -Capture $gcd; Add-Cov 'WSUSSS' 'B4' 'GetConfigData' $gcd 'CORE' $gcdV
  if(-not $gcdV.Conformant){ $wsusssCatalogClean=$false }
  $configAnchor=$null
  if($gcd.IsSuccess -and $gcd.ResponseContent){ try{ $x=[xml]$gcd.ResponseContent; $configAnchor=Get-XmlText $x 'NewConfigAnchor'
      $provenance.Endpoints.Wsusss['ServerSyncUrl']=$ssEp
      $provenance.Endpoints.Wsusss['DssAuthUrl']=$dssUrl
      $provenance.Endpoints.Wsusss['ProtocolVersion']=(Get-XmlText $x 'ProtocolVersion')
      $provenance.Endpoints.Wsusss['CatalogOnlySync']=(Get-XmlText $x 'CatalogOnlySync')
      $provenance.Endpoints.Wsusss['MaxNumberOfUpdatesPerRequest']=(Get-XmlText $x 'MaxNumberOfUpdatesPerRequest')
      $provenance.Endpoints.Wsusss['GetCookieProtocolVersionSent']='1.7'
      try{ if($gcd.ResponseHeaders){ $provenance.Endpoints.Wsusss['HttpServer']=[string]$gcd.ResponseHeaders['Server'] } }catch{}
      Write-Detail 'WSUSSS endpoint provenance (from GetConfigData)' ("ProtocolVersion={0} CatalogOnlySync={1} MaxUpdates/req={2}" -f $provenance.Endpoints.Wsusss['ProtocolVersion'],$provenance.Endpoints.Wsusss['CatalogOnlySync'],$provenance.Endpoints.Wsusss['MaxNumberOfUpdatesPerRequest'])
    }catch{} }

  # [B5a] GetRevisionIdList GetConfig=true -> category/classification/detectoid DICTIONARY (taxonomy)
  $taxoRows=[System.Collections.Generic.List[object]]::new(); $taxoSeen=@{}
  Start-Op 'WSUSSS' 'B5a' 'GetRevisionIdList(GetConfig=true dictionary)'
  $rilC=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetRevisionIdList" -InnerBody "<GetRevisionIdList xmlns=`"$NsSDS`">$sck<filter><GetConfig>true</GetConfig><Get63LanguageOnly>false</Get63LanguageOnly></filter></GetRevisionIdList>"
  $rilCV=Test-ResponseConformance -Op 'GetRevisionIdList' -Cap $rilC
  Save-Capture -Dir $wsusssDir -Prefix '05a.getrevisionidlist-config' -Capture $rilC
  if($rilC.IsSuccess -and $rilC.ResponseContent){ try{ $x=[xml]$rilC.ResponseContent
      foreach($id in $x.SelectNodes("//*[local-name()='NewRevisions']/*[local-name()='UpdateIdentity']")){ $uid=Get-XmlText $id 'UpdateID'; $rev=Get-XmlText $id 'RevisionNumber'; if($uid){ $k=$uid.ToLowerInvariant(); if(-not $taxoSeen.ContainsKey($k)){ $taxoRows.Add([pscustomobject]@{UpdateID=$uid;RevisionNumber=[int]$rev}); $taxoSeen[$k]=1 } } } }catch{} }
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'05a.getrevisionidlist-config.rows.json')) -Object $taxoRows
  Add-Cov 'WSUSSS' 'B5a' 'GetRevisionIdList(GetConfig=true dictionary)' $rilC ("CORE taxonomy=$($taxoRows.Count)") $rilCV
  if(-not $rilCV.Conformant){ $wsusssCatalogClean=$false }
  Write-Detail 'GetRevisionIdList GetConfig=true (taxonomy dictionary)' ("taxonomy nodes = {0}" -f $taxoRows.Count)

  # [B5b] GetRevisionIdList GetConfig=false enumeration (EC-2). RESOLVED (spec 3.1.4.5 + run evidence):
  #   The fully-UNSCOPED null-anchor form returns the ENTIRE Revision Table in ONE response -- observed
  #   ~312 MB (327,152,039 bytes). GetRevisionIdList has NO server page limit; the anchor is a TEMPORAL delta
  #   ("entries with LastChangedAnchor newer than the request anchor"; null anchor => everything), NOT
  #   pagination -- so the first unscoped call IS the whole set and cannot be chunked. That single ~312 MB
  #   transfer is large and unreliable: it completed in one run but the server closed the long connection
  #   (~120s, server-initiated) in another. The earlier "517-row success" was a 64KB capture-truncation
  #   artifact, NOT a small complete answer. => CANONICAL EC-2 ENUMERATION = SCOPED (Classifications [+
  #   Categories]); the unscoped full table is only CHARACTERIZED by a bounded size-probe (no full transfer).
  Start-Op 'WSUSSS' 'B5b' 'GetRevisionIdList(GetConfig=false EC-2)'
  $classXml="<Classifications>"+(($WsusssClassifications|ForEach-Object{"<IdAndDelta><Id>$_</Id><Delta>false</Delta></IdAndDelta>"}) -join '')+"</Classifications>"
  $catXml="<Categories>"+(($taxoRows|ForEach-Object{"<IdAndDelta><Id>$($_.UpdateID)</Id><Delta>false</Delta></IdAndDelta>"}) -join '')+"</Categories>"
  # (a) UNSCOPED: BOUNDED size-probe only -- do NOT attempt the ~312MB transfer, do NOT use as the chosen shape.
  $unscopedBody="<GetRevisionIdList xmlns=`"$NsSDS`">$sck<filter><GetConfig>false</GetConfig><Get63LanguageOnly>false</Get63LanguageOnly></filter></GetRevisionIdList>"
  $unscopedProbe=Invoke-BoundedSizeProbe -Url $ssEp -Action "$NsSDS/GetRevisionIdList" -InnerBody $unscopedBody -TimeoutSec 30 -MaxBytes 262144
  $unscopedBytes= if($unscopedProbe.DeclaredContentLength -gt 0){[long]$unscopedProbe.DeclaredContentLength}else{$null}
  $unscopedDesc= if($unscopedProbe.StatusCode -eq 200 -and $unscopedProbe.ResultElementSeen){ ("full Revision Table; Content-Length={0}; sampled {1} bytes/{2} rows then aborted; single-transfer large+unreliable -> scoped is canonical (EC-2 RESOLVED)" -f $(if($unscopedBytes){"$unscopedBytes bytes (~$([math]::Round($unscopedBytes/1MB)) MB)"}else{'chunked/undeclared'}),$unscopedProbe.BytesSampled,$unscopedProbe.SampleRows) } else { $unscopedProbe.Note }
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'05b.ec2-probe.unscoped.bounded.json')) -Object $unscopedProbe
  Write-Detail 'EC-2 probe: unscoped (bounded)' $unscopedDesc
  # (b) SCOPED shapes -- the RELIABLE/canonical enumeration (anchor-paged in FULL mode; single page in SIMPLE).
  $ec2Shapes=@(
    [ordered]@{ Name='classifications-only';       Scope=$classXml }
    [ordered]@{ Name='classifications+categories'; Scope=$catXml+$classXml }
  )
  $leafRows=[System.Collections.Generic.List[object]]::new(); $leafSeen=@{}; $rstop='done'; $page=0; $chosenShape=$null; $chosenProbe=$null; $chosenMeasure=$null; $ec2Total=0
  $shapeProbe=[System.Collections.Generic.List[object]]::new()
  $shapeProbe.Add([pscustomobject]@{Shape='unscoped(bounded)';Status=$unscopedProbe.StatusCode;Success=($unscopedProbe.StatusCode -eq 200 -and $unscopedProbe.ResultElementSeen);Page1Rows=$unscopedProbe.SampleRows;ContentLength=$unscopedProbe.DeclaredContentLength;Note=$unscopedDesc})
  # EC-2 acquisition: OS-INDEPENDENT broad enumeration. Pick a scoped shape (classifications [+ all categories])
  # and anchor-page the COMPLETE Revision Table (~200K in one ~35MB call). This is the ONLY shape that surfaces
  # the modern server content: per-OS Category scoping (Categories=[one product GUID]) returns EMPTY -- a single
  # product category node surfaces no leaves (leaves gate on the full category set), confirmed live 2026-06-22
  # (all four server OS = 0 revisions), the same structural result as the WUSP product-scan. So OS-targeting is
  # NOT done at enumeration time; it is derived LATER by filtering the harvested GetUpdateData metadata (B6).
  # -SampleData does NOT bound this enumeration (it is one call); it bounds the GetUpdateData harvest in B6.
  Write-Detail 'EC-2 acquisition mode' 'broad OS-independent enumeration (classifications [+ categories]); anchor-paged complete (one ~35MB call)'
  if($true){
    foreach($shape in $ec2Shapes){
      $p1=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetRevisionIdList" -InnerBody "<GetRevisionIdList xmlns=`"$NsSDS`">$sck<filter><GetConfig>false</GetConfig><Get63LanguageOnly>false</Get63LanguageOnly>$($shape.Scope)</filter></GetRevisionIdList>"
      Save-CaptureCapped -Dir $wsusssDir -Prefix ("05b.ec2-probe.{0}" -f $shape.Name) -Capture $p1 -Full:$false
      $rows1=0; $meas=$null
      if($p1.IsSuccess -and $p1.ResponseContent){ try{ $meas=Measure-RevisionIdList -Xml $p1.ResponseContent -SampleSize $SampleSize; $rows1=$meas.Count }catch{} }
      $shapeProbe.Add([pscustomobject]@{Shape=$shape.Name;Status=$p1.StatusCode;Success=$p1.IsSuccess;Page1Rows=$rows1})
      Write-Detail ("EC-2 probe: {0}" -f $shape.Name.Trim()) ("status {0} rows={1}" -f $p1.StatusCode,$rows1)
      if($p1.IsSuccess -and $rows1 -gt 0){ $chosenShape=$shape; $chosenProbe=$p1; $chosenMeasure=$meas; break }
    }
    if($chosenShape){
      # complete anchor-paged enumeration, full persistence
      $anchor=$null;$prevAnchor=$null
      do {
        $page++
        $anchorXml= if($anchor){"<Anchor>$([Security.SecurityElement]::Escape($anchor))</Anchor>"}else{''}
        $ril=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetRevisionIdList" -InnerBody "<GetRevisionIdList xmlns=`"$NsSDS`">$sck<filter>$anchorXml<GetConfig>false</GetConfig><Get63LanguageOnly>false</Get63LanguageOnly>$($chosenShape.Scope)</filter></GetRevisionIdList>"
        Save-Capture -Dir $wsusssDir -Prefix ("05b.getrevisionidlist.p{0:D3}" -f $page) -Capture $ril
        if(-not $ril.IsSuccess){ $rstop="fault($($ril.StatusCode)) at page $page"; break }
        $newThis=0
        try { $x=[xml]$ril.ResponseContent
          foreach($id in $x.SelectNodes("//*[local-name()='NewRevisions']/*[local-name()='UpdateIdentity']")){ $uid=Get-XmlText $id 'UpdateID'; $rev=Get-XmlText $id 'RevisionNumber'
            if($uid){ $k=$uid.ToLowerInvariant()+'#'+$rev; if(-not $leafSeen.ContainsKey($k)){ $leafRows.Add([pscustomobject]@{UpdateID=$uid;RevisionNumber=[int]$rev}); $leafSeen[$k]=1; $newThis++ } } }
          $prevAnchor=$anchor; $anchor=Get-XmlText $x 'Anchor'
        } catch { $rstop="parse-error page $page"; break }
        Write-Detail ("EC-2 enumeration [{0}] page {1}" -f $chosenShape.Name,$page) ("+{0} new (total {1})" -f $newThis,$leafRows.Count)
        if($newThis -eq 0){ $rstop="done (page $page yielded 0 new)"; break }
        if($anchor -and $prevAnchor -and ($anchor -eq $prevAnchor)){ $rstop="done (anchor stopped advancing at page $page)"; break }
      } while($page -lt $MaxRevPages -and $anchor)
      if($page -ge $MaxRevPages){ $rstop="stopped at MaxRevPages=$MaxRevPages (increase -MaxRevPages for full breadth)" }
      $ec2Total=$leafRows.Count
    } else {
      $rstop='no SCOPED EC-2 shape returned rows (classifications/categories empty or failed) -- unscoped is bounded-probed only; see 05b.ec2-probe.*'
    }
  }
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'05b.getrevisionidlist.rows.json')) -Object $leafRows
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'05b.ec2-shape-probe.json')) -Object $shapeProbe
  $wsusssEc2Rows=$ec2Total
  $chosenName= if($chosenShape){$chosenShape.Name}else{'none'}
  $b5bKept= "all $ec2Total enumerated"
  $b5bV= if($chosenProbe){ Test-ResponseConformance -Op 'GetRevisionIdList' -Cap $chosenProbe } else { $null }
  Add-Cov 'WSUSSS' 'B5b' 'GetRevisionIdList(GetConfig=false EC-2)' $chosenProbe ("CORE shape=$chosenName pages=$page leaf=$ec2Total ($b5bKept) stop=[$rstop]") $b5bV
  if($ec2Total -le 0){ $wsusssCatalogClean=$false }
  $wsusssWalk=[ordered]@{ TaxonomyNodes=$taxoRows.Count; Ec2Shape=$chosenName; Ec2Pages=$page; Ec2LeafRevisions=$ec2Total; Ec2RowsKept=$($leafRows.Count); Ec2Stop=$rstop; Ec2ShapeProbe=$shapeProbe }

  # downstream sample: real leaf updates from EC-2 (fall back to taxonomy only if EC-2 returned nothing)
  $srcRows= if($leafRows.Count -gt 0){ $leafRows } else { $taxoRows }
  $smpUid2=@($srcRows|Select-Object -First $SampleSize)
  $uids="<updateIds>"+(($smpUid2|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+"</updateIds>"

  # [B6] GetUpdateData HARVEST -- the ANALYZABLE metadata layer. The EC-2 enumeration yields only (UpdateID,
  # RevisionNumber); the per-update Title / KBArticleID / MsrcSeverity / file digests / download URLs live in
  # GetUpdateData. We harvest them in batches (MaxNumberOfUpdatesPerRequest) and persist per-revision records
  # that offline analysis filters to a target OS. FULL = every enumerated revision; SAMPLE (-SampleData) = a
  # sample spread EVENLY across the whole catalog (stride sampling -- NOT first-N, since the catalog HEAD is
  # XP-era and the modern server LCU/SSU are deeper), so the sample is representative of the full breadth.
  Start-Op 'WSUSSS' 'B6' 'GetUpdateData'
  $allRows=@($leafRows)
  if($SampleData -and $allRows.Count -gt $HarvestSampleSize){
    $stride=[math]::Max(1,[int][math]::Floor($allRows.Count / $HarvestSampleSize))
    $hrows=New-Object System.Collections.ArrayList
    for($i=0; $i -lt $allRows.Count -and $hrows.Count -lt $HarvestSampleSize; $i+=$stride){ [void]$hrows.Add($allRows[$i]) }
    $harvestRows=@($hrows); $harvestMode=("SAMPLE (-SampleData): {0} of {1} via stride {2} (evenly spread)" -f $harvestRows.Count,$allRows.Count,$stride)
  } else {
    $harvestRows=$allRows; $harvestMode=("FULL: all {0} enumerated revisions" -f $allRows.Count)
  }
  Write-Detail 'GetUpdateData harvest mode' $harvestMode
  $batchSize=100; try { if($provenance.Endpoints.Wsusss['MaxNumberOfUpdatesPerRequest']){ $batchSize=[int]$provenance.Endpoints.Wsusss['MaxNumberOfUpdatesPerRequest'] } } catch {}
  if($batchSize -lt 1 -or $batchSize -gt 100){ $batchSize=100 }
  $harvest=New-Object System.Collections.ArrayList; $fileDigests=@(); $gudFirst=$null; $hbErr=0
  $hbMaxAttempts=3; $hbFailedBatches=New-Object System.Collections.ArrayList   # retry transient GetUpdateData batch failures before counting err; record any final failures for targeted re-fetch
  $harvestScratch=[IO.Path]::Combine([IO.Path]::GetTempPath(),('harvestblob_'+[Guid]::NewGuid().ToString('N'))); New-Item -ItemType Directory -Force -Path $harvestScratch | Out-Null
  $totalBatches=[math]::Ceiling($harvestRows.Count / [double]$batchSize)
  $hsw=[System.Diagnostics.Stopwatch]::StartNew()
  Write-Host ("    [{0}] WSUSSS GetUpdateData harvest START | rows={1} | batch={2} | batches={3} | mode={4}" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$harvestRows.Count,$batchSize,$totalBatches,$(if($SampleData){'SAMPLE'}else{'FULL'}))
  for($bi=0; $bi -lt $harvestRows.Count; $bi+=$batchSize){
    $batch=@($harvestRows[$bi..([math]::Min($bi+$batchSize-1,$harvestRows.Count-1))])
    $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
    $bn=[int]($bi/$batchSize)
    $gud=$null; $hbAttempt=0
    while($hbAttempt -lt $hbMaxAttempts){
      $hbAttempt++
      $gud=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$sck$uidB</GetUpdateData>"
      if($gud.IsSuccess -and $gud.ResponseContent){ break }
      if($hbAttempt -lt $hbMaxAttempts){ Start-Sleep -Seconds ([math]::Min(30,(5*$hbAttempt))) }   # transient backoff: 5s, 10s
    }
    if($hbAttempt -gt 1 -and $gud.IsSuccess -and $gud.ResponseContent){ Write-Host ("    [{0}] harvest batch {1}/{2} RECOVERED after {3} attempt(s)" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),($bn+1),$totalBatches,$hbAttempt) }
    if($null -eq $gudFirst){ $gudFirst=$gud }
    if($bn -lt 3){ Save-Capture -Dir $wsusssDir -Prefix ("06.getupdatedata.b{0:D4}" -f $bn) -Capture $gud }
    if($gud.IsSuccess -and $gud.ResponseContent){
      try {
        $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
        foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
          $seg=$suN.Groups[1].Value
          $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
          $wasComp=$false
          if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $harvestScratch; if($dc){ $blob=$dc; $wasComp=$true } } }
          [void]$harvest.Add((ConvertFrom-WuUpdateSegment -Seg $seg -Blob $blob -WasCompressed $wasComp -UrlMap $urlMap -ClassList $WsusssClassifications))
        }
        if($fileDigests.Count -lt 40){ foreach($m in [regex]::Matches($gud.ResponseContent,'<FileDigest>([^<]+)</FileDigest>')){ if($fileDigests.Count -lt 40){ $fileDigests+=$m.Groups[1].Value } } }
      } catch { $hbErr++; [void]$hbFailedBatches.Add([pscustomobject]@{ Batch=($bn+1); FirstUpdateID=$batch[0].UpdateID; Count=@($batch).Count; Reason='parse' }) }
    } else { $hbErr++; [void]$hbFailedBatches.Add([pscustomobject]@{ Batch=($bn+1); FirstUpdateID=$batch[0].UpdateID; Count=@($batch).Count; Reason='soap-fail-after-retry' }) }
    if(($bn % 20) -eq 0 -or ($bi+$batchSize) -ge $harvestRows.Count){
      Write-Host ("    [{0}] harvest batch {1}/{2} | records={3} | with-url={4} | err={5} | {6}s" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),($bn+1),$totalBatches,$harvest.Count,@(@($harvest)|Where-Object{@($_.Urls).Count -gt 0}).Count,$hbErr,[math]::Round($hsw.Elapsed.TotalSeconds,1))
    }
  }
  $hsw.Stop()
  try { if(Test-Path $harvestScratch){ Remove-Item $harvestScratch -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
  $fileDigests=@($fileDigests | Select-Object -Unique | Select-Object -First 40)
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'06.getupdatedata-harvest.json')) -Object @($harvest)
  $hTitled=@(@($harvest)|Where-Object{$_.Title}).Count
  $hKb=@(@($harvest)|Where-Object{$_.KB}).Count
  $hUrl=@(@($harvest)|Where-Object{@($_.Urls).Count -gt 0}).Count
  $hModern=@(@($harvest)|Where-Object{ $_.KB -and ($_.KB -match '^5[0-9]{6}$') }).Count
  $harvestSummary=[ordered]@{ Mode=$harvestMode; Enumerated=$ec2Total; Harvested=@($harvest).Count; Titled=$hTitled; WithKB=$hKb; WithUrl=$hUrl; ModernKb5=$hModern; Batches=$totalBatches; BatchErrors=$hbErr; BatchSize=$batchSize; FailedBatches=@($hbFailedBatches); ElapsedSeconds=[math]::Round($hsw.Elapsed.TotalSeconds,1) }
  Save-Json -Path ([IO.Path]::Combine($wsusssDir,'06.getupdatedata-harvest-summary.json')) -Object $harvestSummary
  Write-Host ("    [{0}] harvest DONE | records={1} | titled={2} | with-KB={3} | with-URL={4} | KB5xxxxxx={5} | err={6} | {7}s" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),@($harvest).Count,$hTitled,$hKb,$hUrl,$hModern,$hbErr,[math]::Round($hsw.Elapsed.TotalSeconds,1))
  $gud=$gudFirst
  $gudV= if($gudFirst){ Test-ResponseConformance -Op 'GetUpdateData' -Cap $gudFirst } else { $null }
  Add-Cov 'WSUSSS' 'B6' 'GetUpdateData' $gudFirst ("CORE harvested=$(@($harvest).Count)/$ec2Total titled=$hTitled withURL=$hUrl") $gudV
  if($gudV -and -not $gudV.Conformant){ $wsusssCatalogClean=$false }
  Write-Detail 'GetUpdateData harvest' ("records={0} titled={1} with-KB={2} with-URL={3} modern-KB5={4} (analyzable: wsusss/06.getupdatedata-harvest.json)" -f @($harvest).Count,$hTitled,$hKb,$hUrl,$hModern)

  # [B7] GetUpdateDecryptionData (CORE)
  Start-Op 'WSUSSS' 'B7' 'GetUpdateDecryptionData'
  $gudd=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetUpdateDecryptionData" -InnerBody "<GetUpdateDecryptionData xmlns=`"$NsSDS`">$sck$uids</GetUpdateDecryptionData>"
  $guddV=Test-ResponseConformance -Op 'GetUpdateDecryptionData' -Cap $gudd
  Save-Capture -Dir $wsusssDir -Prefix '07.getupdatedecryptiondata' -Capture $gudd; Add-Cov 'WSUSSS' 'B7' 'GetUpdateDecryptionData' $gudd 'CORE' $guddV
  if(-not $guddV.Conformant){ $wsusssCatalogClean=$false }

  # [B8] GetDriverIdList (CORE)
  Start-Op 'WSUSSS' 'B8' 'GetDriverIdList'
  $gdil=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetDriverIdList" -InnerBody "<GetDriverIdList xmlns=`"$NsSDS`">$sck<deviceList /><installedNonLeafUpdateIDs /></GetDriverIdList>"
  $gdilV=Test-ResponseConformance -Op 'GetDriverIdList' -Cap $gdil
  Save-Capture -Dir $wsusssDir -Prefix '08.getdriveridlist' -Capture $gdil; Add-Cov 'WSUSSS' 'B8' 'GetDriverIdList' $gdil 'CORE' $gdilV
  if(-not $gdilV.Conformant){ $wsusssCatalogClean=$false }

  # [B9] GetDriverSetData (CORE)
  Start-Op 'WSUSSS' 'B9' 'GetDriverSetData'
  $gdsd=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetDriverSetData" -InnerBody "<GetDriverSetData xmlns=`"$NsSDS`">$sck<driverSets /></GetDriverSetData>"
  $gdsdV=Test-ResponseConformance -Op 'GetDriverSetData' -Cap $gdsd
  Save-Capture -Dir $wsusssDir -Prefix '09.getdriversetdata' -Capture $gdsd; Add-Cov 'WSUSSS' 'B9' 'GetDriverSetData' $gdsd 'CORE' $gdsdV
  if(-not $gdsdV.Conformant){ $wsusssCatalogClean=$false }

  # [B10] GetDeployments -- replica-context op (spec 3.1.4.10: "to a replica DSS"). HOSTED endpoint
  #       (ServerSync); on a non-replica/CatalogOnlySync USS this is a SAMPLE capture. NON-GATING.
  $syncAnchorVal= if($configAnchor){$configAnchor}else{[DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss.fff')}
  Start-Op 'WSUSSS' 'B10' 'GetDeployments'
  $gdep=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetDeployments" -InnerBody "<GetDeployments xmlns=`"$NsSDS`">$sck<deploymentAnchor></deploymentAnchor><syncAnchor>$([Security.SecurityElement]::Escape($syncAnchorVal))</syncAnchor></GetDeployments>"
  Save-Capture -Dir $wsusssDir -Prefix '10.getdeployments' -Capture $gdep; Add-Cov 'WSUSSS' 'B10' 'GetDeployments' $gdep ("OUT-OF-PROFILE(replica-only; spec 3.1.4.10 MUST NOT invoke unless Replica) probe-evidence syncAnchor=$syncAnchorVal")

  # [B11] DownloadFiles -- HOSTED endpoint; file URLs are ALSO already inline in B6 (fileUrls/MUUrl).
  #       SAMPLE/confirmation call. NON-GATING.
  $fdl= if($fileDigests.Count){"<fileDigestList>"+(($fileDigests|ForEach-Object{"<base64Binary>$_</base64Binary>"}) -join '')+"</fileDigestList>"}else{"<fileDigestList />"}
  Start-Op 'WSUSSS' 'B11' 'DownloadFiles'
  $dlf=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/DownloadFiles" -InnerBody "<DownloadFiles xmlns=`"$NsSDS`">$sck$fdl</DownloadFiles>"
  Save-Capture -Dir $wsusssDir -Prefix '11.downloadfiles' -Capture $dlf; Add-Cov 'WSUSSS' 'B11' 'DownloadFiles' $dlf ("OUT-OF-PROFILE(CatalogOnlySync=TRUE; spec 3.2.4.4 content via MUUrl) probe-evidence digests=$($fileDigests.Count) (URLs inline in B6)")

  # [B12-B17] Rollup/Report (DSS->USS) on the REPORTING Web Service ($repEp). Per spec 2.1 + 3.1.4 these are
  #   DSS->USS rollup ops. Pre-flight establishes whether the Reporting service is hosted here. If NOT hosted
  #   (404 on the public catalog USS), each op is recorded as endpoint-not-hosted WITHOUT issuing SOAP. These
  #   are NON-GATING regardless (reporting/rollup is orthogonal to the catalog metadata SSOT).
  if(Test-Hosted $repEp){
    $now2="<clientTime>$([DateTime]::UtcNow.ToString('o'))</clientTime>"
    $parentId=[guid]::NewGuid().ToString()
    Start-Op 'WSUSSS' 'B12' 'GetRollupConfiguration'
    $grc=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/GetRollupConfiguration" -InnerBody "<GetRollupConfiguration xmlns=`"$NsSDS`">$sck</GetRollupConfiguration>"
    Save-Capture -Dir $wsusssDir -Prefix '12.getrollupconfiguration' -Capture $grc; Add-Cov 'WSUSSS' 'B12' 'GetRollupConfiguration' $grc 'REPORTING (sample)'
    Start-Op 'WSUSSS' 'B13' 'RollupDownstreamServers'
    $rds=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/RollupDownstreamServers" -InnerBody "<RollupDownstreamServers xmlns=`"$NsSDS`">$sck$now2<downstreamServers /></RollupDownstreamServers>"
    Save-Capture -Dir $wsusssDir -Prefix '13.rollupdownstreamservers' -Capture $rds; Add-Cov 'WSUSSS' 'B13' 'RollupDownstreamServers' $rds 'REPORTING (sample)'
    Start-Op 'WSUSSS' 'B14' 'RollupComputers'
    $rcp=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/RollupComputers" -InnerBody "<RollupComputers xmlns=`"$NsSDS`">$sck$now2<computers /></RollupComputers>"
    Save-Capture -Dir $wsusssDir -Prefix '14.rollupcomputers' -Capture $rcp; Add-Cov 'WSUSSS' 'B14' 'RollupComputers' $rcp 'REPORTING (sample)'
    Start-Op 'WSUSSS' 'B15' 'GetOutOfSyncComputers'
    $goos=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/GetOutOfSyncComputers" -InnerBody "<GetOutOfSyncComputers xmlns=`"$NsSDS`">$sck<parentServerId>$parentId</parentServerId><lastRollupNumbers /></GetOutOfSyncComputers>"
    Save-Capture -Dir $wsusssDir -Prefix '15.getoutofsynccomputers' -Capture $goos; Add-Cov 'WSUSSS' 'B15' 'GetOutOfSyncComputers' $goos 'REPORTING (sample)'
    Start-Op 'WSUSSS' 'B16' 'RollupComputerStatus'
    $rcs=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/RollupComputerStatus" -InnerBody "<RollupComputerStatus xmlns=`"$NsSDS`">$sck$now2<parentServerId>$parentId</parentServerId><computers /></RollupComputerStatus>"
    Save-Capture -Dir $wsusssDir -Prefix '16.rollupcomputerstatus' -Capture $rcs; Add-Cov 'WSUSSS' 'B16' 'RollupComputerStatus' $rcs 'REPORTING (sample)'
    Start-Op 'WSUSSS' 'B17' 'ReportEventBatch'
    $reb2=Invoke-SoapCapture -Url $repEp -Action "$NsSDS/ReportEventBatch" -InnerBody "<ReportEventBatch xmlns=`"$NsSDS`">$sck$now2<eventBatch /></ReportEventBatch>"
    Save-Capture -Dir $wsusssDir -Prefix '17.reporteventbatch' -Capture $reb2; Add-Cov 'WSUSSS' 'B17' 'ReportEventBatch' $reb2 'REPORTING (sample)'
  } else {
    Write-Detail 'B12-B17 Reporting Web Service' ("NOT-PUBLISHED on this USS -- BOUNDED PROOF: spec 2.1 MANDATES this path on the authoritative USS host (= ServerSync host); probe at the derived URL is absent; role model 3.2.4.5/DoDetailedRollup/Appendix-A (USS receives DSS->USS rollup, v1.3+) confirms a catalog-distribution USS is not a rollup receiver. NOT a lone-404 guess. No SOAP issued: {0}" -f $repEp)
    $repProof='NOT-PUBLISHED (spec 2.1 path absent on authoritative host + role 3.2.4.5; bounded proof)'
    Start-Op 'WSUSSS' 'B12' 'GetRollupConfiguration';   Add-Cov 'WSUSSS' 'B12' 'GetRollupConfiguration'   (New-NotHostedCap $repEp) $repProof
    Start-Op 'WSUSSS' 'B13' 'RollupDownstreamServers';  Add-Cov 'WSUSSS' 'B13' 'RollupDownstreamServers'  (New-NotHostedCap $repEp) $repProof
    Start-Op 'WSUSSS' 'B14' 'RollupComputers';          Add-Cov 'WSUSSS' 'B14' 'RollupComputers'          (New-NotHostedCap $repEp) $repProof
    Start-Op 'WSUSSS' 'B15' 'GetOutOfSyncComputers';     Add-Cov 'WSUSSS' 'B15' 'GetOutOfSyncComputers'     (New-NotHostedCap $repEp) $repProof
    Start-Op 'WSUSSS' 'B16' 'RollupComputerStatus';      Add-Cov 'WSUSSS' 'B16' 'RollupComputerStatus'      (New-NotHostedCap $repEp) $repProof
    Start-Op 'WSUSSS' 'B17' 'ReportEventBatch';          Add-Cov 'WSUSSS' 'B17' 'ReportEventBatch'          (New-NotHostedCap $repEp) $repProof
  }

  } catch {
    Write-Host ('=== [MS-WSUSSS] ERROR -- {0} (run continues; partial results + zip still produced) ===' -f $_.Exception.Message)
    try { Save-Json -Path ([IO.Path]::Combine($wsusssDir,'99.error.json')) -Object ([ordered]@{ Message=$_.Exception.Message; Type=$_.Exception.GetType().FullName; Line=$_.InvocationInfo.ScriptLineNumber; Position=$_.InvocationInfo.PositionMessage }) } catch {}
    $wsusssCatalogClean=$false
  }
} else {
  Write-Host ''
  if (-not $runWsusss) { Write-Host '=== PART 1: [MS-WSUSSS] skipped (domain not selected) ===' }
  else { Write-Host '=== PART 1: [MS-WSUSSS] BLOCKED -- pre-flight FAILED (a REQUIRED endpoint is not hosted); no SOAP issued ==='; $wsusssCatalogClean=$false }
}



# ===================================================================================

# ===================================================================================
# [MS-WUSP] domain -- runs AFTER WSUSSS (order WUA -> WSUSSS -> WUSP); feeds the shared summary.
# ===================================================================================
if ($runWusp) {
    Write-Host ''
    Write-Host '=== [MS-WUSP] increment 1: intrinsic env + per-query fresh auth context ==='
    $v2Err=$null
    $fe=$null
    $psAll=$null
    $ld=$null
    if(-not $script:WuspPreflightPass){
        Write-Host '    WUSP pre-flight FAILED (a REQUIRED endpoint is not hosted) -- cannot run the handshake.'
    } else {
        try {
            $wenv=New-WuspEnv -ClientEp $pfCliEp
            Write-Host ("    intrinsic (reused): ClientEp={0}" -f $wenv.ClientEp)
            Write-Host '    [per-query] New-WuspAuthContext (fresh GetConfig -> GetCookie) ...'
            $ac=New-WuspAuthContext -WuspEnv $wenv
            $cfgV=$ac.Verdicts['GetConfig']; $ckV=$ac.Verdicts['GetCookie']
            $fmtV={ param($x) if($x){ $b=("{0} (http {1}; {2})" -f $(if($x.Conformant){'CONFORMANT'}else{'NON-CONFORMANT'}),$x.HttpStatus,$(if($x.Failures -and $x.Failures.Count){$x.Failures -join ','}else{'ok'})); if($x.Fault){ $b=$b+(" | FAULT: {0}" -f $x.Fault.FaultString) }; $b } else {'(no verdict)'} }
            Write-Host ("    GetConfig : {0}" -f (& $fmtV $cfgV))
            Write-Host ("    GetCookie : {0}" -f (& $fmtV $ckV))
            Write-Host ("    Config    : IsRegistrationRequired={0} | AuthPlugins=[{1}] | ServerProtocolVersion={2}" -f $ac.IsRegistrationRequired,($ac.AuthPlugins -join ','),$ac.ServerProtocolVersion)
            Write-Host ("    Cookie    : {0}" -f $(if($ac.Cookie){'acquired (Expiration='+$ac.Cookie.Expiration+')'}else{'NONE'}))
            Write-Host ("    AuthContext.Ok = {0}" -f $ac.Ok)
            $rec=[ordered]@{ ClientEp=$wenv.ClientEp;
                GetConfigVerdict=$cfgV; GetCookieVerdict=$ckV;
                LastChange=$ac.LastChange; IsRegistrationRequired=$ac.IsRegistrationRequired; AuthMode=$ac.AuthMode;
                AuthPlugins=$ac.AuthPlugins; ServerProtocolVersion=$ac.ServerProtocolVersion; Properties=$ac.Properties;
                AllowedEventIds=$ac.AllowedEventIds; CookieAcquired=[bool]$ac.Cookie; CookieExpiration=$(if($ac.Cookie){$ac.Cookie.Expiration}else{$null}); Ok=$ac.Ok }
            Save-Json -Path ([IO.Path]::Combine($wuspDir,'01.authcontext.json')) -Object $rec
            Save-Json -Path ([IO.Path]::Combine($wuspDir,'00.managed-values.json')) -Object @($ac.Managed)
            Save-Json -Path ([IO.Path]::Combine($wuspDir,'02.seeds.json')) -Object $Script:WuspSeedCategories
            foreach($cn in @($ac.Captures.Keys)){ try { Save-Capture -Dir $wuspDir -Prefix ("cap.{0}" -f $cn) -Capture $ac.Captures[$cn] } catch {} }
            if($ac.Ok){
                Write-Host ''
                Write-Host '=== [MS-WUSP] increment 2: base-data category enumeration ==='
                Write-Host '    [query] SyncUpdates non-leaf loop (spec 3.1.5.7) -> categories -> GetExtendedUpdateInfo (CategoryType+Title) ...'
                $bd2Dir=[IO.Path]::Combine($wuspDir,'basedata'); New-Item -ItemType Directory -Force -Path $bd2Dir | Out-Null
                $enum=Invoke-WuspCategoryEnumeration -WuspEnv $wenv -AuthCtx $ac -RunDir $bd2Dir
                Write-Host ("    rounds={0} | total categories={1} (Classification={2}, Product={3}, Company={4}, Detectoid={5}, Uncategorized={6})" -f $enum.Counts.Rounds,$enum.Counts.TotalCategories,$enum.Counts.Classifications,$enum.Counts.Products,$enum.Counts.Companies,$enum.Counts.Detectoids,$enum.Counts.Uncategorized)
                Write-Host ("    stop reason : {0}" -f $enum.Reason)
                Write-Host ("    seed check  : {0}/{1} confirmed seeds present in the live list" -f $enum.Counts.SeedsPresent,$enum.Counts.SeedsTotal)
                foreach($sv in $enum.SeedValidation){ Write-Host ("      [{0}] {1,-22} {2}  {3,-8} {4}" -f $sv.Kind.Substring(0,[Math]::Min(4,$sv.Kind.Length)),$sv.Name,$sv.Guid,$(if($sv.PresentInLiveList){'PRESENT'}else{'absent'}),$(if($sv.LiveCategoryType){"(CategoryType=$($sv.LiveCategoryType))"}else{''})) }
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'10.enumeration-summary.json')) -Object ([ordered]@{ Ok=$enum.Ok; Reason=$enum.Reason; Counts=$enum.Counts; Rounds=@($enum.Rounds); ExtendedBatches=@($enum.ExtendedBatches) })
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'11.categories.all.json')) -Object @($enum.Categories)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'12.classifications.json')) -Object @($enum.Classifications)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'13.products.json')) -Object @($enum.Products)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'14.companies.json')) -Object @($enum.Companies)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'15.detectoids.json')) -Object @($enum.Detectoids)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'16.uncategorized.json')) -Object @($enum.Uncategorized)
                Save-Json -Path ([IO.Path]::Combine($bd2Dir,'17.seed-validation.json')) -Object @($enum.SeedValidation)
            }
            if($ac.Ok){
                Write-Host ''
                Write-Host '=== [MS-WUSP] FULL ENUMERATION (acquire the COMPLETE corpus first; filter later) ==='
                Write-Host '    walking SyncUpdates to TRUE completion (NOT stopping at category-tree-complete); every leaf + its applicability fragment is preserved.'
                $feDir=[IO.Path]::Combine($wuspDir,'fullset'); New-Item -ItemType Directory -Force -Path $feDir | Out-Null
                $feac=New-WuspAuthContext -WuspEnv $wenv
                if(-not $feac.Ok){
                    Write-Host '    (auth context failed for full enumeration)'
                } else {
                    $feStartUtc=(Get-Date).ToUniversalTime().ToString('o')
                    $feMaxRounds = if($SampleData){ 15 } else { $FullEnumMaxRounds }
                    Write-Host ("    [{0}] full-enumeration START | MaxRounds={1} | mode={2} | paging ~90 new/round | categories cap-safe (Category-only)" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$feMaxRounds,$(if($SampleData){'SAMPLE (-SampleData)'}else{'FULL (default)'}))
                    $fe=Invoke-WuspCategoryEnumeration -WuspEnv $wenv -AuthCtx $feac -RunDir $feDir -FullEnumeration -MaxRounds $feMaxRounds -CachedCap 200000 -ProgressEvery 20
                    $feRounds=@($fe.Rounds).Count
                    $feNonLeaf=@($fe.Categories).Count
                    $feLeaf=@($fe.Leaves).Count
                    $feInNL=@(@($fe.Categories) | Where-Object { $_.DeclaredIn -eq 'InstalledNonLeaf' }).Count
                    $feDet=@(@($fe.Categories) | Where-Object { $_.UpdateType -eq 'Detectoid' }).Count
                    $feSec=[double]$fe.ElapsedSeconds
                    $feEndUtc=(Get-Date).ToUniversalTime().ToString('o')
                    $feRate= if($feSec -gt 0){ [math]::Round(($feNonLeaf+$feLeaf)/$feSec,1) } else { 0 }
                    $feConverged= ($fe.Reason -like 'sync-complete' -or $fe.Reason -like 'full-enumeration-complete*')
                    Write-Host ("    [{0}] full-enumeration END   | rounds={1} | stop-reason={2} | {3}" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$feRounds,$fe.Reason,$(if($feConverged){'CONVERGED (complete corpus)'}else{'NOT converged -- raise -FullEnumMaxRounds or inspect fault'}))
                    Write-Host ("    elapsed: {0:N2}s ({1:N1} min) | throughput: {2} updates/s | avg {3:N2}s/round" -f $feSec,($feSec/60.0),$feRate,$(if($feRounds){[math]::Round($feSec/$feRounds,2)}else{0}))
                    Write-Host ("    InstalledNonLeafUpdateIDs declared (Category-only) = {0}  (server cap ~400; headroom {1})" -f $feInNL,(400-$feInNL))
                    Write-Host ("    FULL SET: non-leaf={0} (Detectoid={1}, Category={2}, other={3}) | leaves(patches)={4} | TOTAL distinct={5}" -f $feNonLeaf,$feDet,$feInNL,($feNonLeaf-$feDet-$feInNL),$feLeaf,($feNonLeaf+$feLeaf))
                    # persist the complete corpus so the SEED-value filtering (next phase) runs on real full data
                    Save-Json -Path ([IO.Path]::Combine($feDir,'00.fullset-summary.json')) -Object ([ordered]@{
                        Ok=$fe.Ok; Reason=$fe.Reason; Converged=$feConverged; Rounds=$feRounds;
                        StartedUtc=$feStartUtc; EndedUtc=$feEndUtc; ElapsedSeconds=$feSec; UpdatesPerSecond=$feRate;
                        NonLeafCount=$feNonLeaf; DetectoidCount=$feDet; CategoryCount=$feInNL; InstalledNonLeafDeclared=$feInNL; CapHeadroom=(400-$feInNL); LeafCount=$feLeaf; TotalCount=($feNonLeaf+$feLeaf);
                        RoundDetail=@($fe.Rounds)
                    })
                    Save-Json -Path ([IO.Path]::Combine($feDir,'10.nonleaf-categories.json')) -Object @($fe.Categories)
                    # leaves: identity table (small) separate from the bulky applicability fragments
                    $leafIdx=@(@($fe.Leaves) | ForEach-Object { [pscustomobject]@{ RevisionID=$_.RevisionID; UpdateID=$_.UpdateID; RevisionNumber=$_.RevisionNumber; UpdateType=$_.UpdateType } })
                    Save-Json -Path ([IO.Path]::Combine($feDir,'20.leaves-index.json')) -Object $leafIdx
                    Save-Json -Path ([IO.Path]::Combine($feDir,'21.leaves-with-fragments.json')) -Object @($fe.Leaves) -Depth 8
                    Write-Host ("    [{0}] full-set persisted: 00.fullset-summary / 10.nonleaf-categories / 20.leaves-index / 21.leaves-with-fragments" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')))
                }
            }

            if($ac.Ok){
                Write-Host ''
                Write-Host '=== [MS-WUSP] increment 3: per-product scoped query (multi-GUID; one fresh query per GUID) ==='
                $psDir=[IO.Path]::Combine($wuspDir,'products'); New-Item -ItemType Directory -Force -Path $psDir | Out-Null
                $psSeeds=$null
                $sr=$wenv.Seeds
                if($sr -is [System.Collections.IDictionary]){ if($sr.Contains('Products')){ $psSeeds=$sr['Products'] } }
                elseif($sr -and $sr.PSObject.Properties['Products']){ $psSeeds=$sr.Products }
                # leaf prerequisites are (Product AND Classification) plus detectoids; the product filter never
                # surfaces them, so seed from the FULL-ENUM non-leaf set (cap-safe split: Category -> InstalledNonLeaf,
                # Detectoid/other -> OtherCached). FULL ENUM now runs BEFORE this block; fall back to base-data if absent.
                $seedCat=@(); $seedCached=@()
                if($fe -and @($fe.Categories).Count){
                    $seedCat   =@(@($fe.Categories) | Where-Object { $_.UpdateType -eq 'Category' } | ForEach-Object { [int]$_.RevisionID })
                    $seedCached=@(@($fe.Categories) | Where-Object { $_.UpdateType -ne 'Category' } | ForEach-Object { [int]$_.RevisionID })
                    Write-Host ("    seed from FULL ENUM non-leaf: Category={0} (InstalledNonLeaf, cap-safe) + Detectoid/other={1} (OtherCached)" -f $seedCat.Count,$seedCached.Count)
                } elseif((Get-Variable -Name enum -Scope 0 -ErrorAction SilentlyContinue) -and $enum -and $enum.Categories){
                    $seedCat   =@(@($enum.Categories) | Where-Object { $_.UpdateType -eq 'Category' } | ForEach-Object { [int]$_.RevisionID })
                    $seedCached=@(@($enum.Categories) | Where-Object { $_.UpdateType -ne 'Category' } | ForEach-Object { [int]$_.RevisionID })
                    Write-Host ("    FULL ENUM unavailable -- seed from base-data: Category={0} + other={1}" -f $seedCat.Count,$seedCached.Count)
                }
                $psMaxRounds = if($SampleData){ 8 } else { $FullEnumMaxRounds }
                Write-Host ("    product-scan mode: {0} | MaxRounds={1} per product" -f $(if($SampleData){'SAMPLE (-SampleData, bounded)'}else{'FULL (per-product to convergence)'}),$psMaxRounds)
                $psAll=New-Object System.Collections.ArrayList
                $psLeafRollup=New-Object System.Collections.ArrayList
                foreach($p in @($psSeeds)){
                    Write-Host ("    -- product [{0}] {1}  {2}" -f $p.Os,$p.Title,$p.Guid)
                    Write-Host '       [per-query] fresh New-WuspAuthContext -> StartCategoryScan -> scoped SyncUpdates (seeded) ...'
                    $pac=New-WuspAuthContext -WuspEnv $wenv
                    if(-not $pac.Ok){ Write-Host '       (auth context failed for this product; recording and continuing)'; [void]$psAll.Add([pscustomobject]@{ Os=$p.Os; ProductGuid=$p.Guid; Title=$p.Title; Ok=$false; Reason='auth-failed' }); continue }
                    $scan=Invoke-WuspProductScan -WuspEnv $wenv -AuthCtx $pac -Os $p.Os -ProductGuid $p.Guid -Title $p.Title -SeedNonLeafRevisionIDs $seedCat -SeedCachedRevisionIDs $seedCached -MaxRounds $psMaxRounds -CachedCap 200000 -RunDir $psDir
                    Write-Host ("       recognized={0} | preferred={1} | rounds={2} leafPatches={3} completed={4}" -f $scan.Recognized,$scan.Counts.Preferred,$scan.Counts.Rounds,$scan.Counts.LeafPatches,$scan.Completed)
                    Write-Host ("       reason: {0}" -f $scan.Reason)
                    [void]$psAll.Add([pscustomobject]@{ Os=$p.Os; ProductGuid=$p.Guid; Title=$p.Title; Catalogs=$p.Catalogs; WuspLiveSeed=$p.WuspLive; Ok=$scan.Ok; Recognized=$scan.Recognized; Reason=$scan.Reason; Counts=$scan.Counts })
                    [void]$psLeafRollup.Add([pscustomobject]@{ Os=$p.Os; ProductGuid=$p.Guid; Title=$p.Title; Recognized=$scan.Recognized; Completed=$scan.Completed; LeafCount=@($scan.LeafPatches).Count; Leaves=@(@($scan.LeafPatches) | ForEach-Object { [pscustomobject]@{ UpdateID=$_.UpdateID; RevisionNumber=$_.RevisionNumber; RevisionID=$_.RevisionID; UpdateType=$_.UpdateType } }) })
                }
                Save-Json -Path ([IO.Path]::Combine($psDir,'00.product-scan-index.json')) -Object @($psAll)
                Save-Json -Path ([IO.Path]::Combine($psDir,'01.filtered-leaves-rollup.json')) -Object @($psLeafRollup) -Depth 5
                Write-Host ("    product-scan index written ({0} product GUIDs)" -f $psAll.Count)
            }

            if($ac.Ok){
                Write-Host ''
                Write-Host '=== [MS-WUSP] LEAF DEPTH (complete the remaining ClientWebService ops) ==='
                Write-Host '    depth chain: GetExtendedUpdateInfo(leaf) -> GetExtendedUpdateInfo2 -> GetFileLocations; + RegisterComputer / RefreshCache / SyncPrinterCatalog'
                $ldDir=[IO.Path]::Combine($wuspDir,'leafdepth'); New-Item -ItemType Directory -Force -Path $ldDir | Out-Null
                $ldac=New-WuspAuthContext -WuspEnv $wenv
                if(-not $ldac.Ok){
                    Write-Host '    (auth context failed for leaf-depth)'
                } else {
                    # leaves come from the FULL ENUMERATION increment above (ALL leaves); fallback to a bounded self-acquire if unavailable
                    $ldLeaves=@()
                    if($fe -and @($fe.Leaves).Count){ $ldLeaves=@($fe.Leaves); Write-Host ("    using FULL-ENUM leaves: {0} available" -f $ldLeaves.Count) }
                    else {
                        Write-Host ("    [{0}] FULL-ENUM leaves unavailable -- bounded self-acquire (MaxRounds={1}) ..." -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$LeafDepthAcquireRounds)
                        $ldEnum=Invoke-WuspCategoryEnumeration -WuspEnv $wenv -AuthCtx $ldac -RunDir '' -FullEnumeration -MaxRounds $LeafDepthAcquireRounds -CachedCap 200000
                        $ldLeaves=@($ldEnum.Leaves)
                    }
                    $ldTarget= if($SampleData){ @($ldLeaves | Select-Object -First $LeafDepthSampleSize) } else { @($ldLeaves) }
                    Write-Host ("    leaf-depth target: {0} leaves | mode={1}" -f $ldTarget.Count,$(if($SampleData){("SAMPLE (-SampleData, first {0})" -f $LeafDepthSampleSize)}else{'FULL (all leaves)'}))
                    if($ldTarget.Count -eq 0){
                        Write-Host '    (no leaves available -- raise -LeafDepthAcquireRounds or check FULL ENUM)'
                    } else {
                        # ---- (1) CONFORMANCE PROBE: first batch (<=50) exercises all 6 remaining ops incl the URL chain -> 10/10 ----
                        $probeLeaves=@($ldTarget | Select-Object -First 50)
                        $ldac2=New-WuspAuthContext -WuspEnv $wenv
                        $depthCtx= if($ldac2.Ok){$ldac2}else{$ldac}
                        $spcSeed=@(); if($fe -and @($fe.Categories).Count){ $spcSeed=@(@($fe.Categories) | Where-Object { $_.UpdateType -eq 'Category' } | ForEach-Object { [int]$_.RevisionID } | Select-Object -First 200) }
                        $ld=Invoke-WuspLeafDepth -WuspEnv $wenv -AuthCtx $depthCtx -Identity $ident -Leaves $probeLeaves -RunDir $ldDir -SampleSize 50 -SeedNonLeafRevisionIDs $spcSeed
                        $ldConf=@(@($ld.Ops) | Where-Object { $_.Conformant -or $_.Expected }).Count
                        $ldTot=@($ld.Ops).Count
                        Write-Host ("    [{0}] leaf-depth probe: {1}/{2} ops OK (conformant+expected-out-of-profile) | probe={3} leaves | {4:N2}s" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$ldConf,$ldTot,$ld.SampleSize,$ld.ElapsedSeconds)
                        foreach($o in @($ld.Ops)){
                            $tag= if($o.Conformant){"CONFORMANT($($o.HttpStatus))"}elseif($o.Expected){"EXPECTED-OUT-OF-PROFILE($($o.HttpStatus): anonymous; $($o.Failures))"}else{"NON-CONFORMANT($($o.HttpStatus): $($o.Failures))"}
                            Write-Host ("      {0,-24} {1,-6} -> {2}  [{3}]" -f $o.Op,$o.Scope,$tag,$o.Note)
                        }
                        Write-Host ("    probe URL chain: leaf FileDigests={0} | GetExtendedUpdateInfo2 URLs={1} | GetFileLocations URLs={2}  (URLs sampled on the probe only)" -f @($ld.FileDigests).Count,@($ld.Eui2Urls).Count,@($ld.GflUrls).Count)
                        Save-Json -Path ([IO.Path]::Combine($ldDir,'40.leafdepth-summary.json')) -Object ([ordered]@{
                            StartedUtc=$ld.StartedUtc; ElapsedSeconds=$ld.ElapsedSeconds; ProbeSize=$ld.SampleSize;
                            OpsConformant=$ldConf; OpsTotal=$ldTot; Ops=@($ld.Ops);
                            FileDigestCount=@($ld.FileDigests).Count; Eui2UrlCount=@($ld.Eui2Urls).Count; GflUrlCount=@($ld.GflUrls).Count;
                            FileDigestsSample=@(@($ld.FileDigests) | Select-Object -First 20);
                            Eui2UrlsSample=@(@($ld.Eui2Urls) | Select-Object -First 20);
                            GflUrlsSample=@(@($ld.GflUrls) | Select-Object -First 20)
                        })
                        # ---- (2) ALL-LEAF HARVEST: Title + files for EVERY target leaf (batched GetExtendedUpdateInfo; URLs NOT harvested here) ----
                        $harvRevs=@($ldTarget | Where-Object { $_.UpdateID -and $_.RevisionID } | ForEach-Object { [int]$_.RevisionID })
                        $hac=New-WuspAuthContext -WuspEnv $wenv
                        $hck= if($hac.Ok){[string]$hac.CookieXml}else{[string]$depthCtx.CookieXml}
                        $hbatch=50; try { if($hac.Properties['MaxExtendedUpdatesPerRequest']){ $hbatch=[int]$hac.Properties['MaxExtendedUpdatesPerRequest'] } } catch {}
                        if($hbatch -lt 1){ $hbatch=50 }
                        Write-Host ("    [{0}] leaf-harvest START | leaves={1} | batch={2} | chunks~{3} (Title+files; URLs deferred to ISO-build use-case)" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),$harvRevs.Count,$hbatch,[math]::Ceiling($harvRevs.Count/[double]$hbatch))
                        $gx=Invoke-WuspGetExtended -Ep $wenv.ClientEp -Ns $wenv.Ns -Ab $wenv.ActionBase -CookieXml $hck -RevisionIDs $harvRevs -BatchSize $hbatch -RunDir $ldDir -SaveFullN 3
                        $recs=@($ldTarget | ForEach-Object {
                            $rv=[int]$_.RevisionID; $t=$null; $dg=@(); $fn=@(); $fl=@()
                            if($gx.ByRev.ContainsKey($rv)){ $t=$gx.ByRev[$rv].Title; $dg=@($gx.ByRev[$rv].FileDigests); $fn=@($gx.ByRev[$rv].FileNames); $fl=@($gx.ByRev[$rv].Files) }
                            [pscustomobject]@{ RevisionID=$rv; UpdateID=$_.UpdateID; RevisionNumber=$_.RevisionNumber; UpdateType=$_.UpdateType; Title=$t; FileCount=$fl.Count; FileDigestCount=$dg.Count; Files=$fl; FileDigests=$dg; FileNames=$fn }
                        })
                        $titled=@(@($recs) | Where-Object { $_.Title }).Count
                        $withFiles=@(@($recs) | Where-Object { $_.FileDigestCount -gt 0 }).Count
                        $bConf=@(@($gx.Batches) | Where-Object { $_.Conformant }).Count
                        $bTot=@($gx.Batches).Count
                        Write-Host ("    [{0}] leaf-harvest complete: {1} leaves | titled={2} | with-files={3} | batches {4}/{5} conformant" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')),@($recs).Count,$titled,$withFiles,$bConf,$bTot)
                        Save-Json -Path ([IO.Path]::Combine($ldDir,'41.leaf-harvest-all.json')) -Object @($recs) -Depth 6
                        Save-Json -Path ([IO.Path]::Combine($ldDir,'42.leaf-harvest-summary.json')) -Object ([ordered]@{
                            Mode=$(if($SampleData){'SAMPLE'}else{'FULL'}); TargetLeaves=$ldTarget.Count; Harvested=@($recs).Count; Titled=$titled; WithFiles=$withFiles;
                            Batches=$bTot; BatchesConformant=$bConf; BatchSize=$hbatch; BatchLog=@($gx.Batches);
                            Note='URLs (GetExtendedUpdateInfo2/GetFileLocations) harvested on the conformance-probe sample only (40.*); all-leaf URL harvest deferred to the ISO-build use-case per Stage 1 scope.'
                        })
                        Write-Host ("    [{0}] leaf-depth persisted: 40.leafdepth-summary (probe) + 41.leaf-harvest-all + 42.leaf-harvest-summary + raw 30..35 (probe) / cap.GetExtendedUpdateInfo.bNN (harvest)" -f ([DateTime]::Now.ToString('HH:mm:ss.fff')))
                    }
                }
            }
            if($ac.Ok){
                try { [void](Write-WuspOperationReport -Ac $ac -Fe $fe -PsAll $psAll -Ld $ld -OutDir $wuspDir) } catch { Write-Host ("    [WUSP REPORT skipped] {0}" -f $_.Exception.Message) }
            }
        } catch {
            $v2Err=$_
            Write-Host ("    [WUSP ERROR] {0}" -f $_.Exception.Message)
            Write-Host ("    [WUSP ERROR] at {0}:{1}" -f $_.InvocationInfo.ScriptName,$_.InvocationInfo.ScriptLineNumber)
            try { Save-Json -Path ([IO.Path]::Combine($wuspDir,'99.error.json')) -Object ([ordered]@{ Message=$_.Exception.Message; Type=$_.Exception.GetType().FullName; Line=$_.InvocationInfo.ScriptLineNumber; Position=$_.InvocationInfo.PositionMessage; Raw=([string]$ac.Verdicts) }) } catch {}
        }
    }
}


# ===================================================================================
# FEASIBILITY STUDY (ISO-build use case) -- SELF-CONTAINED; opt-in via -FeasibilityStudy.
# Decoupled from the survey: own handshake, own taxonomy, own seed; PART 0/1 + WUSP are
# SKIPPED when -FeasibilityStudy is set (it forces the three domain flags off), so there is
# NO section/scope dependency on the survey results.
# QUESTION (the use-case feasibility): can the WSUSSS GetRevisionIdList Categories filter
# NARROW the catalog to a target OS SERVER-SIDE? A single top-level product node was proven
# = 0 (leaves are filed under DESCENDANT category nodes, not the product node). This probe:
#   (A) GetUpdateData on KNOWN target-OS LCUs and read the category UpdateIDs each LCU is
#       actually filed under (blob UpdateID refs intersected with the GetConfig=true taxonomy);
#   (B) scope GetRevisionIdList by each of those category UpdateIDs (+ servicing classifications)
#       and record the revision COUNT and whether the seed LCU appears -- i.e. does any category
#       scoping yield a bounded per-OS set that CONTAINS the known LCU.
# First run is also a CAPTURE run: the raw GetUpdateData of each modern LCU (fs/a.*) is the
# ground truth to refine the category-membership parse from, per loop discipline.
# ===================================================================================
if ($FeasibilityStudy) {
  Write-Host ''
  Write-Host '=== FEASIBILITY STUDY: Case 1 -- per-OS BASELINE dataset (no filter; dependency-rich: UpdateType + prereq edges + node audit; raw sample saved) ==='
  $fsDir=[IO.Path]::Combine($dir,'fs'); New-Item -ItemType Directory -Force -Path $fsDir | Out-Null
  try {
    $NsSDS='http://www.microsoft.com/SoftwareDistribution'
    $NsDSS='http://www.microsoft.com/SoftwareDistribution/Server/DssAuthWebService'
    $ssEp= if($WsusssServerSyncEndpoint){$WsusssServerSyncEndpoint}else{'https://sws.update.microsoft.com/ServerSyncWebService/ServerSyncWebService.asmx'}
    $dssEp=if($WsusssDssAuthEndpoint){$WsusssDssAuthEndpoint}else{'https://sws.update.microsoft.com/DssAuthWebService/DssAuthWebService.asmx'}
    $WsusssClassifications=@('0fa1201d-4330-4fa8-8ae9-b877473b6441','28bc880e-0592-4cbf-8f95-c79b17911d5f','68c5b0a3-d1a6-4553-ae49-01d3a7827828','e6cf1350-c01b-414d-a61f-263d14d133b4','cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83')
    $classXml='<Classifications>'+(($WsusssClassifications|ForEach-Object{"<IdAndDelta><Id>$_</Id><Delta>false</Delta></IdAndDelta>"}) -join '')+'</Classifications>'

    # --- self-contained handshake -> fresh cookie ($sck) ---
    Write-Host '  [FS handshake] GetAuthConfig -> GetAuthorizationCookie -> GetCookie ...'
    $ac=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetAuthConfig" -InnerBody "<GetAuthConfig xmlns=`"$NsSDS`" />"
    Save-Capture -Dir $fsDir -Prefix '01.getauthconfig' -Capture $ac
    $dssUrl=$dssEp; if($ac.IsSuccess -and $ac.ResponseContent){ try{ $x=[xml]$ac.ResponseContent; foreach($ai in $x.SelectNodes("//*[local-name()='ServerSyncAuthInfo']")){ if((Get-XmlText $ai 'PlugInId') -eq 'DssTargeting'){ $u=Get-XmlText $ai 'ServiceUrl'; if($u){$dssUrl=$u}; break } } }catch{} }
    $gac=Invoke-SoapCapture -Url $dssUrl -Action "$NsDSS/GetAuthorizationCookie" -InnerBody "<GetAuthorizationCookie xmlns=`"$NsDSS`"><accountName>WSUS-ServerSync-Survey</accountName><accountGuid>$([guid]::NewGuid().ToString())</accountGuid></GetAuthorizationCookie>"
    Save-Capture -Dir $fsDir -Prefix '02.getauthorizationcookie' -Capture $gac
    $plugInId=$null;$cookieData=$null; if($gac.IsSuccess -and $gac.ResponseContent){ try{ $x=[xml]$gac.ResponseContent; $plugInId=Get-XmlText $x 'PlugInId'; $cookieData=Get-XmlText $x 'CookieData' }catch{} }
    $enc=$null;$exp=$null
    if($cookieData){
      $gc=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetCookie" -InnerBody "<GetCookie xmlns=`"$NsSDS`"><authCookies><AuthorizationCookie><PlugInId>$plugInId</PlugInId><CookieData>$cookieData</CookieData></AuthorizationCookie></authCookies><protocolVersion>1.7</protocolVersion></GetCookie>"
      Save-Capture -Dir $fsDir -Prefix '03.getcookie' -Capture $gc
      if($gc.IsSuccess -and $gc.ResponseContent){ try{ $x=[xml]$gc.ResponseContent; $enc=Get-XmlText $x 'EncryptedData'; $exp=Get-XmlText $x 'Expiration' }catch{} }
    }
    $sck= if($enc){"<cookie><Expiration>$exp</Expiration><EncryptedData>$enc</EncryptedData></cookie>"}else{'<cookie></cookie>'}
    if(-not $enc){ Write-Host '  [FS] WARNING: no cookie acquired -- handshake failed; see fs/0*.xml (probe continues best-effort)' }

    # ============================================================================
    # PHASE 1 (DATASET) -- per-OS smart dataset acquisition (foundational; no dependency analysis).
    # For each OS: start from the FIXED product GUID(s) (the durable seed), covering-query the
    # bounded per-OS revision set (Categories-first, anchor-paged -- the r13.30 validated form),
    # GetUpdateData it (Title/KB/Severity/URLs + IsCategory product members), DISCOVER the complete
    # product-node set from the LCU memberships (an OS has multiple nodes), expand the covering if
    # new nodes appear, and persist the per-OS dataset. OS membership = the covering set (product
    # node) -- NOT titles (titles are multi-locale and "21H2" collides with Windows 10 client). Type
    # is a best-effort GUESS here; the per-OS RESOLVER (Phase 2, separate) confirms it from leaf files.
    # NO dependency / apply-order here (that is the deferred next phase).
    # ============================================================================
    function Get-Server2016CurrentSet { param([object[]]$Records)
      # Server2016-ONLY current-set selector. Do NOT call for any other OS; each OS owns a separate, independent function.
      # Server2016 facts (per-OS L3 analysis, cross-checked with the research doc / INVESTIGATION-STATE + Microsoft Learn, human-confirmed):
      #   in-box .NET (3.5/4.6.2/4.7.x) is serviced VIA the OS LCU (same KB as the LCU, e.g. KB5094122; there is NO standalone in-box .NET package in the catalog);
      #   the standalone .NET 4.8 CU (KB5087065) services the ADD-ON 4.8 runtime, which is NOT pre-installed -> EXCLUDED under the in-box-only policy.
      # So the Server2016 current set is exactly LCU + standalone SSU (no separate .NET line). No Dynamic Update line. No Azure Stack HCI in this product node.
      # Policy: per-OS separation over generality. These patterns/variables are Server2016-local and must not be shared.
      $s2016SsuPattern = 'Servicing Stack Update for Windows Server 2016'
      $s2016LcuPattern = 'Cumulative Update for Windows Server 2016'
      $s2016Lines      = @('SSU','LCU')
      $s2016Tagged=@()
      foreach($r in @($Records)){
        if(-not $r.IsBundle){ continue }
        $t= if($r.TitleEn){ $r.TitleEn } elseif($r.Title){ $r.Title } else { '' }
        $line= if($t -match $s2016SsuPattern){ 'SSU' } elseif($t -match $s2016LcuPattern){ 'LCU' } else { $null }
        if(-not $line){ continue }
        $ym= if($t -match '^\s*([0-9]{4})-([0-9]{2})'){ ($Matches[1]+'-'+$Matches[2]) } else { '0000-00' }
        $s2016Tagged+=[pscustomobject]@{ Line=$line; Ym=$ym; KB=$r.KB; UpdateID=$r.UpdateID; RevisionNumber=$r.RevisionNumber; BundledLeaf=@($r.BundledLeaf); TitleEn=$r.TitleEn; IsSuperseded=$(if($r.PSObject.Properties['IsSuperseded']){$r.IsSuperseded}else{$null}) }
      }
      $s2016Current=@()
      foreach($ln in $s2016Lines){
        $inLine=@($s2016Tagged | Where-Object { $_.Line -eq $ln })
        if(-not $inLine.Count){ continue }
        $newestYm=@($inLine | Sort-Object Ym -Descending)[0].Ym
        foreach($pp in @($inLine | Where-Object { $_.Ym -eq $newestYm })){ $s2016Current+=$pp }
      }
      return @($s2016Current)
    }

    function Get-Server2019CurrentSet { param([object[]]$Records)
      # Server2019-ONLY current-set selector. Independent per-OS unit; patterns/vars are Server2019-local (duplication across OS accepted per policy).
      # Server2019 facts (ground-truthed from the dataset + research doc 5.4 + Microsoft Learn; in-box-only policy):
      #   SSU: NO standalone SSU line -- 2019 is COMBINED; the servicing stack ships as the embedded selfUpdate/permanent package (KB5094143)
      #        inside the LCU leaf (research doc 5.4). The standalone 2019 SSU is frozen at KB5005112 (2021-08) and superseded -> not selected.
      #   .NET: the current 2019 .NET CU is a COMBINED bundle "3.5, 4.7.2 and 4.8" (e.g. KB5088864) that carries TWO leaves --
      #        the in-box 3.5/4.7.2 payload (Windows10.0-KB5087061-x64) AND the add-on 4.8 payload (Windows10.0-KB...-NDP48).
      #        In-box on 2019 is 4.7.2, so the bundle is selected here but ONLY its in-box (non-NDP48) leaf is in scope; the 4.8 NDP48 leaf is excluded at leaf-follow.
      # So the Server2019 current set is LCU + .NET(combined CU bundle). No separate SSU line. Preview (optional non-security) updates are skipped.
      $s2019LcuPattern = 'Cumulative Update for Windows Server 2019'
      $s2019NetPattern = 'Cumulative Update for \.NET Framework.*Windows Server 2019'
      $s2019Lines      = @('NET','LCU')
      $s2019Tagged=@()
      foreach($r in @($Records)){
        if(-not $r.IsBundle){ continue }
        $t= if($r.TitleEn){ $r.TitleEn } elseif($r.Title){ $r.Title } else { '' }
        if($t -match 'Preview'){ continue }
        $line= if($t -match $s2019NetPattern){ 'NET' } elseif($t -match $s2019LcuPattern){ 'LCU' } else { $null }
        if(-not $line){ continue }
        $ym= if($t -match '^\s*([0-9]{4})-([0-9]{2})'){ ($Matches[1]+'-'+$Matches[2]) } else { '0000-00' }
        $s2019Tagged+=[pscustomobject]@{ Line=$line; Ym=$ym; KB=$r.KB; UpdateID=$r.UpdateID; RevisionNumber=$r.RevisionNumber; BundledLeaf=@($r.BundledLeaf); TitleEn=$r.TitleEn; IsSuperseded=$(if($r.PSObject.Properties['IsSuperseded']){$r.IsSuperseded}else{$null}) }
      }
      $s2019Current=@()
      foreach($ln in $s2019Lines){
        $inLine=@($s2019Tagged | Where-Object { $_.Line -eq $ln })
        if(-not $inLine.Count){ continue }
        $newestYm=@($inLine | Sort-Object Ym -Descending)[0].Ym
        foreach($pp in @($inLine | Where-Object { $_.Ym -eq $newestYm })){ $s2019Current+=$pp }
      }
      return @($s2019Current)
    }

    function Get-Server2022CurrentSet { param([object[]]$Records)
      # Server2022-ONLY current-set selector. Independent per-OS unit; patterns/vars are Server2022-local (duplication across OS accepted per policy).
      # Server2022 facts (ground-truthed from the dataset + research doc 5.4 + Microsoft Learn; in-box-only policy):
      #   SSU: NO standalone SSU line -- 2022 is COMBINED (embedded SSU KB5094147 in the LCU leaf; installerAssembly placeholder 6.0.0.0), research doc 5.4. The dataset has zero standalone 2022 SSU.
      #   LCU: the GENERAL Server 2022 LCU is titled "Microsoft server operating system version 21H2" (NOT "Windows Server 2022"); the SAME KB also appears under the
      #        "Windows Server 2022 Datacenter: Azure Edition" SKU title, and the 2022 node also carries Azure Stack HCI hotpatches -- both are excluded (different SKU / hotpatch).
      #   .NET: the current 2022 .NET CU is a COMBINED bundle "3.5, 4.8 and 4.8.1" (e.g. KB5088862) carrying TWO leaves -- the in-box 3.5/4.8 payload
      #        (Windows10.0-KB5087068-x64-NDP48) AND the add-on 4.8.1 payload (Windows10.0-KB5087059-x64-NDP481). In-box on 2022 is 4.8, so only the NDP48 (non-481) leaf is in scope (the 481 leaf is excluded at leaf-follow).
      # So the Server2022 current set is LCU(21H2) + .NET(combined CU bundle). No separate SSU line. Azure Edition / Azure Stack HCI / Hotpatch / Preview are skipped.
      $s2022LcuPattern = 'Cumulative Update for Microsoft server operating system version 21H2'
      $s2022NetPattern = 'Cumulative Update for \.NET Framework.*Microsoft server operating system version 21H2'
      $s2022Lines      = @('NET','LCU')
      $s2022Tagged=@()
      foreach($r in @($Records)){
        if(-not $r.IsBundle){ continue }
        $t= if($r.TitleEn){ $r.TitleEn } elseif($r.Title){ $r.Title } else { '' }
        if(($t -match 'Azure') -or ($t -match 'Hotpatch') -or ($t -match 'Preview')){ continue }
        $line= if($t -match $s2022NetPattern){ 'NET' } elseif($t -match $s2022LcuPattern){ 'LCU' } else { $null }
        if(-not $line){ continue }
        $ym= if($t -match '^\s*([0-9]{4})-([0-9]{2})'){ ($Matches[1]+'-'+$Matches[2]) } else { '0000-00' }
        $s2022Tagged+=[pscustomobject]@{ Line=$line; Ym=$ym; KB=$r.KB; UpdateID=$r.UpdateID; RevisionNumber=$r.RevisionNumber; BundledLeaf=@($r.BundledLeaf); TitleEn=$r.TitleEn; IsSuperseded=$(if($r.PSObject.Properties['IsSuperseded']){$r.IsSuperseded}else{$null}) }
      }
      $s2022Current=@()
      foreach($ln in $s2022Lines){
        $inLine=@($s2022Tagged | Where-Object { $_.Line -eq $ln })
        if(-not $inLine.Count){ continue }
        $newestYm=@($inLine | Sort-Object Ym -Descending)[0].Ym
        foreach($pp in @($inLine | Where-Object { $_.Ym -eq $newestYm })){ $s2022Current+=$pp }
      }
      return @($s2022Current)
    }
    function Invoke-Server2016LeafFollow { param([object[]]$CurrentSet,[string]$SsEp,[string]$NsSDS,[string]$Cookie,[string]$ScratchDir,[string]$RawSampleFile)
      # Server2016-ONLY leaf-follow (additional dataset / Decision-B, narrowed to the Server2016 current set).
      # Do NOT call for any other OS; each OS owns its own leaf-follow. Resolves each current-set bundle BundledLeaf
      # via GetUpdateData and captures the leaf Files (FileName/Digest/Size/PatchingType) + download URL + leaf Prerequisites.
      $s2016LeafTargets=@(); $s2016Seen=@{}
      foreach($cs in @($CurrentSet)){
        foreach($lf in @($cs.BundledLeaf)){
          if(-not $lf.UpdateID){ continue }
          $key=($lf.UpdateID.ToLowerInvariant()+'/'+$lf.RevisionNumber)
          if($s2016Seen.ContainsKey($key)){ continue }; $s2016Seen[$key]=1
          $s2016LeafTargets+=[pscustomobject]@{ Line=$cs.Line; ParentKB=$cs.KB; ParentUpdateID=$cs.UpdateID; UpdateID=$lf.UpdateID; RevisionNumber=$lf.RevisionNumber }
        }
      }
      $s2016Results=@(); $bs=100
      for($bi=0;$bi -lt $s2016LeafTargets.Count;$bi+=$bs){
        $batch=@($s2016LeafTargets[$bi..([math]::Min($bi+$bs-1,$s2016LeafTargets.Count-1))])
        $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
        $gud=Invoke-SoapCapture -Url $SsEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$Cookie$uidB</GetUpdateData>"
        if($RawSampleFile -and $bi -eq 0 -and $gud.ResponseContent){ try{ [IO.File]::WriteAllText($RawSampleFile,$gud.ResponseContent) }catch{} }
        if($gud.IsSuccess -and $gud.ResponseContent){
          $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
          foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
            $seg=$suN.Groups[1].Value
            $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
            $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
            $wasComp=$false
            if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $ScratchDir -TailBytes 262144; if($dc){ $blob=$dc; $wasComp=$true } } }
            $files=@()
            foreach($fm in [regex]::Matches($blob,'<(?:[A-Za-z0-9]+:)?File\b[^>]*>')){
              $fe=$fm.Value
              $fn= if($fe -match 'FileName="([^"]*)"'){ $Matches[1] } else { $null }
              $dg= if($fe -match 'Digest="([^"]*)"'){ $Matches[1] } else { $null }
              $da= if($fe -match 'DigestAlgorithm="([^"]*)"'){ $Matches[1] } else { $null }
              $sz= if($fe -match 'Size="([0-9]+)"'){ [long]$Matches[1] } else { 0 }
              $pt= if($fe -match 'PatchingType="([^"]*)"'){ $Matches[1] } else { $null }
              $url= if($dg -and $urlMap.ContainsKey($dg)){ $urlMap[$dg] } else { $null }
              $files+=[pscustomobject]@{ FileName=$fn; Digest=$dg; DigestAlgorithm=$da; Size=$sz; PatchingType=$pt; Url=$url }
            }
            $leafPrereq=@()
            $pm=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Prerequisites>(.*?)</(?:[A-Za-z0-9]+:)?Prerequisites>')
            if($pm.Success){ foreach($im in [regex]::Matches($pm.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $leafPrereq+=$im.Groups[1].Value.ToLowerInvariant() } }
            $leafPrereq=@($leafPrereq|Select-Object -Unique)
            $tEn=$null; foreach($lp in [regex]::Matches($blob,'<[A-Za-z0-9]+:LocalizedProperties>(.*?)</[A-Za-z0-9]+:LocalizedProperties>','Singleline')){ $lseg=$lp.Groups[1].Value; $lng= if($lseg -match '<[A-Za-z0-9]+:Language>([^<]+)</'){ $Matches[1] } else { $null }; if($lng -eq 'en' -and $lseg -match '<[A-Za-z0-9]+:Title>([^<]+)</'){ $tEn=$Matches[1]; break } }
            $tgt=@($s2016LeafTargets | Where-Object { $_.UpdateID -and $uidH -and ($_.UpdateID.ToLowerInvariant() -eq $uidH.ToLowerInvariant()) })
            $line= if($tgt.Count){ $tgt[0].Line } else { $null }
            $pkb=  if($tgt.Count){ $tgt[0].ParentKB } else { $null }
            $s2016Results+=[pscustomobject]@{ Line=$line; ParentKB=$pkb; LeafUpdateID=$uidH; LeafRevisionNumber=$revH; Compressed=$wasComp; TitleEn=$tEn; FileCount=@($files).Count; UrlCount=@(@($files)|Where-Object{$_.Url}).Count; Files=$files; LeafPrereqIds=$leafPrereq }
          }
        }
      }
      return @($s2016Results)
    }

    function Invoke-Server2019LeafFollow { param([object[]]$CurrentSet,[string]$SsEp,[string]$NsSDS,[string]$Cookie,[string]$ScratchDir,[string]$RawSampleFile)
      # Server2019-ONLY leaf-follow. Resolves each current-set bundle leaf via GetUpdateData and captures Files + URL + Prerequisites.
      # PER-OS: classifies each .NET leaf by payload -- a leaf whose file name carries NDP48/NDP481 is the 4.8/4.8.1 ADD-ON (out of scope under
      # the in-box-only policy, in-box on 2019 is 4.7.2); the non-NDP48 leaf is the in-box 3.5/4.7.2 payload (in scope). LeafKB is taken from the file name.
      # Do NOT call for any other OS; each OS owns its own leaf-follow. Resolves each current-set bundle BundledLeaf
      # via GetUpdateData and captures the leaf Files (FileName/Digest/Size/PatchingType) + download URL + leaf Prerequisites.
      $s2019LeafTargets=@(); $s2019Seen=@{}
      foreach($cs in @($CurrentSet)){
        foreach($lf in @($cs.BundledLeaf)){
          if(-not $lf.UpdateID){ continue }
          $key=($lf.UpdateID.ToLowerInvariant()+'/'+$lf.RevisionNumber)
          if($s2019Seen.ContainsKey($key)){ continue }; $s2019Seen[$key]=1
          $s2019LeafTargets+=[pscustomobject]@{ Line=$cs.Line; ParentKB=$cs.KB; ParentUpdateID=$cs.UpdateID; UpdateID=$lf.UpdateID; RevisionNumber=$lf.RevisionNumber }
        }
      }
      $s2019Results=@(); $bs=100
      for($bi=0;$bi -lt $s2019LeafTargets.Count;$bi+=$bs){
        $batch=@($s2019LeafTargets[$bi..([math]::Min($bi+$bs-1,$s2019LeafTargets.Count-1))])
        $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
        $gud=Invoke-SoapCapture -Url $SsEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$Cookie$uidB</GetUpdateData>"
        if($RawSampleFile -and $bi -eq 0 -and $gud.ResponseContent){ try{ [IO.File]::WriteAllText($RawSampleFile,$gud.ResponseContent) }catch{} }
        if($gud.IsSuccess -and $gud.ResponseContent){
          $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
          foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
            $seg=$suN.Groups[1].Value
            $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
            $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
            $wasComp=$false
            if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $ScratchDir -TailBytes 262144; if($dc){ $blob=$dc; $wasComp=$true } } }
            $files=@()
            foreach($fm in [regex]::Matches($blob,'<(?:[A-Za-z0-9]+:)?File\b[^>]*>')){
              $fe=$fm.Value
              $fn= if($fe -match 'FileName="([^"]*)"'){ $Matches[1] } else { $null }
              $dg= if($fe -match 'Digest="([^"]*)"'){ $Matches[1] } else { $null }
              $da= if($fe -match 'DigestAlgorithm="([^"]*)"'){ $Matches[1] } else { $null }
              $sz= if($fe -match 'Size="([0-9]+)"'){ [long]$Matches[1] } else { 0 }
              $pt= if($fe -match 'PatchingType="([^"]*)"'){ $Matches[1] } else { $null }
              $url= if($dg -and $urlMap.ContainsKey($dg)){ $urlMap[$dg] } else { $null }
              $files+=[pscustomobject]@{ FileName=$fn; Digest=$dg; DigestAlgorithm=$da; Size=$sz; PatchingType=$pt; Url=$url }
            }
            $leafPrereq=@()
            $pm=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Prerequisites>(.*?)</(?:[A-Za-z0-9]+:)?Prerequisites>')
            if($pm.Success){ foreach($im in [regex]::Matches($pm.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $leafPrereq+=$im.Groups[1].Value.ToLowerInvariant() } }
            $leafPrereq=@($leafPrereq|Select-Object -Unique)
            $tEn=$null; foreach($lp in [regex]::Matches($blob,'<[A-Za-z0-9]+:LocalizedProperties>(.*?)</[A-Za-z0-9]+:LocalizedProperties>','Singleline')){ $lseg=$lp.Groups[1].Value; $lng= if($lseg -match '<[A-Za-z0-9]+:Language>([^<]+)</'){ $Matches[1] } else { $null }; if($lng -eq 'en' -and $lseg -match '<[A-Za-z0-9]+:Title>([^<]+)</'){ $tEn=$Matches[1]; break } }
            $tgt=@($s2019LeafTargets | Where-Object { $_.UpdateID -and $uidH -and ($_.UpdateID.ToLowerInvariant() -eq $uidH.ToLowerInvariant()) })
            $line= if($tgt.Count){ $tgt[0].Line } else { $null }
            $pkb=  if($tgt.Count){ $tgt[0].ParentKB } else { $null }
            $leafKb=$null; $isNdp=$false
            foreach($f in @($files)){ $fnl=([string]$f.FileName).ToLowerInvariant(); if($fnl -match 'ndp48'){ $isNdp=$true }; if((-not $leafKb) -and ($fnl -match 'kb([0-9]{6,7})')){ $leafKb=$Matches[1] } }
            if((-not $leafKb) -and $tEn -and ($tEn -match '(?i)kb([0-9]{6,7})')){ $leafKb=$Matches[1] }
            $scope= if($line -eq 'NET'){ if($isNdp){ 'addon-out-of-scope' } else { 'inbox' } } elseif($line -eq 'LCU'){ 'lcu-inbox' } else { 'inbox' }
            $s2019Results+=[pscustomobject]@{ Line=$line; ParentKB=$pkb; LeafUpdateID=$uidH; LeafRevisionNumber=$revH; Compressed=$wasComp; TitleEn=$tEn; LeafKB=$leafKb; Scope=$scope; InScope=($scope -ne 'addon-out-of-scope'); FileCount=@($files).Count; UrlCount=@(@($files)|Where-Object{$_.Url}).Count; Files=$files; LeafPrereqIds=$leafPrereq }
          }
        }
      }
      return @($s2019Results)
    }

    function Invoke-Server2022LeafFollow { param([object[]]$CurrentSet,[string]$SsEp,[string]$NsSDS,[string]$Cookie,[string]$ScratchDir,[string]$RawSampleFile)
      # Server2022-ONLY leaf-follow. Resolves each current-set bundle leaf via GetUpdateData and captures Files + URL + Prerequisites.
      # PER-OS: in-box on 2022 is 4.8, so ONLY the NDP481 (4.8.1) leaf is the add-on (out of scope); the NDP48 (4.8) leaf and the 3.5 payload are in-box (in scope).
      # NOTE NDP481 contains NDP48 as a substring, so 481 is tested FIRST. LeafKB is taken from the file name. (This is the INVERSE of the 2019 rule, by design.)
      # Do NOT call for any other OS; each OS owns its own leaf-follow. Resolves each current-set bundle BundledLeaf
      # via GetUpdateData and captures the leaf Files (FileName/Digest/Size/PatchingType) + download URL + leaf Prerequisites.
      $s2022LeafTargets=@(); $s2022Seen=@{}
      foreach($cs in @($CurrentSet)){
        foreach($lf in @($cs.BundledLeaf)){
          if(-not $lf.UpdateID){ continue }
          $key=($lf.UpdateID.ToLowerInvariant()+'/'+$lf.RevisionNumber)
          if($s2022Seen.ContainsKey($key)){ continue }; $s2022Seen[$key]=1
          $s2022LeafTargets+=[pscustomobject]@{ Line=$cs.Line; ParentKB=$cs.KB; ParentUpdateID=$cs.UpdateID; UpdateID=$lf.UpdateID; RevisionNumber=$lf.RevisionNumber }
        }
      }
      $s2022Results=@(); $bs=100
      for($bi=0;$bi -lt $s2022LeafTargets.Count;$bi+=$bs){
        $batch=@($s2022LeafTargets[$bi..([math]::Min($bi+$bs-1,$s2022LeafTargets.Count-1))])
        $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
        $gud=Invoke-SoapCapture -Url $SsEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$Cookie$uidB</GetUpdateData>"
        if($RawSampleFile -and $bi -eq 0 -and $gud.ResponseContent){ try{ [IO.File]::WriteAllText($RawSampleFile,$gud.ResponseContent) }catch{} }
        if($gud.IsSuccess -and $gud.ResponseContent){
          $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
          foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
            $seg=$suN.Groups[1].Value
            $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
            $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
            $wasComp=$false
            if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $ScratchDir -TailBytes 262144; if($dc){ $blob=$dc; $wasComp=$true } } }
            $files=@()
            foreach($fm in [regex]::Matches($blob,'<(?:[A-Za-z0-9]+:)?File\b[^>]*>')){
              $fe=$fm.Value
              $fn= if($fe -match 'FileName="([^"]*)"'){ $Matches[1] } else { $null }
              $dg= if($fe -match 'Digest="([^"]*)"'){ $Matches[1] } else { $null }
              $da= if($fe -match 'DigestAlgorithm="([^"]*)"'){ $Matches[1] } else { $null }
              $sz= if($fe -match 'Size="([0-9]+)"'){ [long]$Matches[1] } else { 0 }
              $pt= if($fe -match 'PatchingType="([^"]*)"'){ $Matches[1] } else { $null }
              $url= if($dg -and $urlMap.ContainsKey($dg)){ $urlMap[$dg] } else { $null }
              $files+=[pscustomobject]@{ FileName=$fn; Digest=$dg; DigestAlgorithm=$da; Size=$sz; PatchingType=$pt; Url=$url }
            }
            $leafPrereq=@()
            $pm=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Prerequisites>(.*?)</(?:[A-Za-z0-9]+:)?Prerequisites>')
            if($pm.Success){ foreach($im in [regex]::Matches($pm.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $leafPrereq+=$im.Groups[1].Value.ToLowerInvariant() } }
            $leafPrereq=@($leafPrereq|Select-Object -Unique)
            $tEn=$null; foreach($lp in [regex]::Matches($blob,'<[A-Za-z0-9]+:LocalizedProperties>(.*?)</[A-Za-z0-9]+:LocalizedProperties>','Singleline')){ $lseg=$lp.Groups[1].Value; $lng= if($lseg -match '<[A-Za-z0-9]+:Language>([^<]+)</'){ $Matches[1] } else { $null }; if($lng -eq 'en' -and $lseg -match '<[A-Za-z0-9]+:Title>([^<]+)</'){ $tEn=$Matches[1]; break } }
            $tgt=@($s2022LeafTargets | Where-Object { $_.UpdateID -and $uidH -and ($_.UpdateID.ToLowerInvariant() -eq $uidH.ToLowerInvariant()) })
            $line= if($tgt.Count){ $tgt[0].Line } else { $null }
            $pkb=  if($tgt.Count){ $tgt[0].ParentKB } else { $null }
            $leafKb=$null; $isAddon=$false
            foreach($f in @($files)){ $fnl=([string]$f.FileName).ToLowerInvariant(); if($fnl -match 'ndp481'){ $isAddon=$true }; if((-not $leafKb) -and ($fnl -match 'kb([0-9]{6,7})')){ $leafKb=$Matches[1] } }
            if((-not $leafKb) -and $tEn -and ($tEn -match '(?i)kb([0-9]{6,7})')){ $leafKb=$Matches[1] }
            $scope= if($line -eq 'NET'){ if($isAddon){ 'addon-out-of-scope' } else { 'inbox' } } elseif($line -eq 'LCU'){ 'lcu-inbox' } else { 'inbox' }
            $s2022Results+=[pscustomobject]@{ Line=$line; ParentKB=$pkb; LeafUpdateID=$uidH; LeafRevisionNumber=$revH; Compressed=$wasComp; TitleEn=$tEn; LeafKB=$leafKb; Scope=$scope; InScope=($scope -ne 'addon-out-of-scope'); FileCount=@($files).Count; UrlCount=@(@($files)|Where-Object{$_.Url}).Count; Files=$files; LeafPrereqIds=$leafPrereq }
          }
        }
      }
      return @($s2022Results)
    }
    function Get-Server2025CurrentSet { param([object[]]$Records)
      # Server2025-ONLY current-set selector. Independent per-OS unit; patterns/vars are Server2025-local (duplication across OS accepted per policy).
      # Server2025 facts (ground-truthed from the real covering dataset + the leaf 3291c997 16-file payload present in the acquired raw GetUpdateData data):
      #   ARCH: 2025 publishes x64 AND arm64; the ISO target is x64 only, so arm64 is skipped.
      #   LCU: titled "Cumulative Update for Microsoft server operating system version 24H2 ... x64" (KB5094125, build 26100.32995).
      #   .NET: a COMBINED CU "3.5 and 4.8.1" (KB5087051), x64 + arm64 variants; in-box on 2025 is 4.8.1, so the whole x64 leaf is in scope (NO add-on split, unlike 2019/2022).
      #   SSU: NO standalone SSU line -- 2025 is UUP; the servicing stack ships as a checkpoint (SSU-26100.xxxxx-x64) inside the LCU leaf 16-file payload. The dataset has zero standalone 2025 SSU.
      #   DU: the SafeOS DU (Windows11.0-KB5094150-x64) is co-bundled inside the SAME LCU leaf -- no separate DU node/acquisition for 2025.
      # So the Server2025 current set is LCU(24H2,x64) + .NET(combined CU,24H2,x64). No separate SSU line. arm64 / Preview are skipped.
      $s2025LcuPattern = 'Cumulative Update for Microsoft server operating system version 24H2'
      $s2025NetPattern = 'Cumulative Update for \.NET Framework.*Microsoft server operating system version 24H2'
      $s2025Lines      = @('NET','LCU')
      $s2025Tagged=@()
      foreach($r in @($Records)){
        if(-not $r.IsBundle){ continue }
        $t= if($r.TitleEn){ $r.TitleEn } elseif($r.Title){ $r.Title } else { '' }
        if(($t -match 'arm64') -or ($t -match 'Preview')){ continue }
        $line= if($t -match $s2025NetPattern){ 'NET' } elseif($t -match $s2025LcuPattern){ 'LCU' } else { $null }
        if(-not $line){ continue }
        $ym= if($t -match '^\s*([0-9]{4})-([0-9]{2})'){ ($Matches[1]+'-'+$Matches[2]) } else { '0000-00' }
        $s2025Tagged+=[pscustomobject]@{ Line=$line; Ym=$ym; KB=$r.KB; UpdateID=$r.UpdateID; RevisionNumber=$r.RevisionNumber; BundledLeaf=@($r.BundledLeaf); TitleEn=$r.TitleEn; IsSuperseded=$(if($r.PSObject.Properties['IsSuperseded']){$r.IsSuperseded}else{$null}) }
      }
      $s2025Current=@()
      foreach($ln in $s2025Lines){
        $inLine=@($s2025Tagged | Where-Object { $_.Line -eq $ln })
        if(-not $inLine.Count){ continue }
        $newestYm=@($inLine | Sort-Object Ym -Descending)[0].Ym
        foreach($pp in @($inLine | Where-Object { $_.Ym -eq $newestYm })){ $s2025Current+=$pp }
      }
      return @($s2025Current)
    }
    function Invoke-Server2025LeafFollow { param([object[]]$CurrentSet,[string]$SsEp,[string]$NsSDS,[string]$Cookie,[string]$ScratchDir,[string]$RawSampleFile)
      # Server2025-ONLY leaf-follow. Resolves each current-set bundle leaf via GetUpdateData and captures Files + URL + Prerequisites.
      # PER-OS (UUP): the LCU leaf is a 16-file mega-payload. Each file is CLASSIFIED (SSU / SafeOS-DU / LCU / GA / LP-FoD / meta / other) so the embedded
      # SSU checkpoint and the co-bundled SafeOS DU can be recorded first-class. .NET on 2025 is in-box 4.8.1, so the whole x64 .NET leaf is in scope (no add-on split).
      # File classes (durable, no hardcoded KB): SSU = name starts SSU- ; LP-FoD = *.wim ; meta = AggregatedMetadata/DesktopDeployment/FodMetadata ;
      #   *.msu Windows11.0-KBnnn-x64 = LCU when KB equals the parent LCU KB else GA(baseline) ; *.cab/*.psf Windows11.0-KBnnn-x64 = SafeOS-DU.
      $s2025LeafTargets=@(); $s2025Seen=@{}
      foreach($cs in @($CurrentSet)){
        foreach($lf in @($cs.BundledLeaf)){
          if(-not $lf.UpdateID){ continue }
          $key=($lf.UpdateID.ToLowerInvariant()+'/'+$lf.RevisionNumber)
          if($s2025Seen.ContainsKey($key)){ continue }; $s2025Seen[$key]=1
          $s2025LeafTargets+=[pscustomobject]@{ Line=$cs.Line; ParentKB=$cs.KB; ParentUpdateID=$cs.UpdateID; UpdateID=$lf.UpdateID; RevisionNumber=$lf.RevisionNumber }
        }
      }
      $s2025Results=@(); $bs=100
      for($bi=0;$bi -lt $s2025LeafTargets.Count;$bi+=$bs){
        $batch=@($s2025LeafTargets[$bi..([math]::Min($bi+$bs-1,$s2025LeafTargets.Count-1))])
        $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
        $gud=Invoke-SoapCapture -Url $SsEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$Cookie$uidB</GetUpdateData>"
        if($RawSampleFile -and $bi -eq 0 -and $gud.ResponseContent){ try{ [IO.File]::WriteAllText($RawSampleFile,$gud.ResponseContent) }catch{} }
        if($gud.IsSuccess -and $gud.ResponseContent){
          $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
          foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
            $seg=$suN.Groups[1].Value
            $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
            $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
            $wasComp=$false
            if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $ScratchDir -TailBytes 262144; if($dc){ $blob=$dc; $wasComp=$true } } }
            $tgt=@($s2025LeafTargets | Where-Object { $_.UpdateID -and $uidH -and ($_.UpdateID.ToLowerInvariant() -eq $uidH.ToLowerInvariant()) })
            $line= if($tgt.Count){ $tgt[0].Line } else { $null }
            $pkb=  if($tgt.Count){ ([string]$tgt[0].ParentKB) } else { $null }
            $files=@()
            foreach($fm in [regex]::Matches($blob,'<(?:[A-Za-z0-9]+:)?File\b[^>]*>')){
              $fe=$fm.Value
              $fn= if($fe -match 'FileName="([^"]*)"'){ $Matches[1] } else { $null }
              $dg= if($fe -match 'Digest="([^"]*)"'){ $Matches[1] } else { $null }
              $da= if($fe -match 'DigestAlgorithm="([^"]*)"'){ $Matches[1] } else { $null }
              $sz= if($fe -match 'Size="([0-9]+)"'){ [long]$Matches[1] } else { 0 }
              $pt= if($fe -match 'PatchingType="([^"]*)"'){ $Matches[1] } else { $null }
              $url= if($dg -and $urlMap.ContainsKey($dg)){ $urlMap[$dg] } else { $null }
              $fnl=([string]$fn).ToLowerInvariant()
              # leaf-aware: only the LCU 16-file payload carries SSU/SafeOS-DU/GA; the .NET leaf files are tagged NET (avoids mis-tagging Windows11.0-KBnnn-x64-NDP*.cab as SafeOS-DU)
              $cls='other'
              if($line -eq 'LCU'){
                if($fnl -match '^ssu-'){ $cls='SSU' }
                elseif($fnl -match '\.wim$'){ $cls='LP-FoD' }
                elseif($fnl -match 'aggregatedmetadata|desktopdeployment|fodmetadata'){ $cls='meta' }
                elseif($fnl -match 'windows11\.0-kb([0-9]+)-x64.*\.msu$'){ $cls= if($pkb -and ($Matches[1] -eq $pkb)){ 'LCU' } else { 'GA' } }
                elseif($fnl -match 'windows11\.0-kb[0-9]+-x64.*\.(cab|psf)$'){ $cls='SafeOS-DU' }
              } elseif($line -eq 'NET'){ $cls='NET' }
              $files+=[pscustomobject]@{ FileName=$fn; Digest=$dg; DigestAlgorithm=$da; Size=$sz; PatchingType=$pt; Url=$url; Class=$cls }
            }
            $leafPrereq=@()
            $pm=[regex]::Match($blob,'(?s)<(?:[A-Za-z0-9]+:)?Prerequisites>(.*?)</(?:[A-Za-z0-9]+:)?Prerequisites>')
            if($pm.Success){ foreach($im in [regex]::Matches($pm.Groups[1].Value,'UpdateID="([0-9A-Fa-f-]{36})"')){ $leafPrereq+=$im.Groups[1].Value.ToLowerInvariant() } }
            $leafPrereq=@($leafPrereq|Select-Object -Unique)
            $tEn=$null; foreach($lp in [regex]::Matches($blob,'<[A-Za-z0-9]+:LocalizedProperties>(.*?)</[A-Za-z0-9]+:LocalizedProperties>','Singleline')){ $lseg=$lp.Groups[1].Value; $lng= if($lseg -match '<[A-Za-z0-9]+:Language>([^<]+)</'){ $Matches[1] } else { $null }; if($lng -eq 'en' -and $lseg -match '<[A-Za-z0-9]+:Title>([^<]+)</'){ $tEn=$Matches[1]; break } }
            $leafKb=$null; foreach($f in @($files)){ $fnl2=([string]$f.FileName).ToLowerInvariant(); if((-not $leafKb) -and ($fnl2 -match 'kb([0-9]{6,7})')){ $leafKb=$Matches[1] } }
            if((-not $leafKb) -and $tEn -and ($tEn -match '(?i)kb([0-9]{6,7})')){ $leafKb=$Matches[1] }
            $scope= if($line -eq 'LCU'){ 'lcu-inbox' } else { 'inbox' }
            $s2025Results+=[pscustomobject]@{ Line=$line; ParentKB=$(if($tgt.Count){$tgt[0].ParentKB}else{$null}); LeafUpdateID=$uidH; LeafRevisionNumber=$revH; Compressed=$wasComp; TitleEn=$tEn; LeafKB=$leafKb; Scope=$scope; InScope=$true; FileCount=@($files).Count; UrlCount=@(@($files)|Where-Object{$_.Url}).Count; Files=$files; LeafPrereqIds=$leafPrereq }
          }
        }
      }
      return @($s2025Results)
    }
    # ===== GENERIC (OS-independent) Microsoft Learn cross-check (step 4) =====
    # Microsoft Learn publishes a uniform structure across OSes, so these are intentionally GENERIC (not per-OS).
    # Logic adapted from the proven parsers in usui-tk/ai-generated-artifacts Update-WindowsServerIso.ps1
    # (the heavy on-disk cache / Write-* / Save-CanonicalJsonFile machinery is dropped for a lean in-memory fetch).
    $LearnUA='ai-generated-artifacts/learn-crosscheck (+https://github.com/usui-tk/ai-generated-artifacts)'
    $LearnReleaseInfoUrl='https://learn.microsoft.com/en-us/windows/release-health/windows-server-release-info?accept=text/markdown'
    $LearnDotNetIndexUrl='https://learn.microsoft.com/en-us/dotnet/framework/release-notes/release-notes?accept=text/markdown'
    $LearnDotNetUrlBase='https://learn.microsoft.com/en-us/dotnet/framework/release-notes/'
    $LearnReleaseInfoMonthlyHeaders=@('Servicing option','Update type','Availability date','Build','KB article')
    $LearnDotNetOsLongToShort=[ordered]@{
      'Microsoft server operating system, version 24H2'='Server2025'
      'Microsoft server operating system version 24H2'='Server2025'
      'Windows Server 2022'='Server2022'
      'Windows 10 1809 and Windows Server 2019'='Server2019'
      'Windows Server 2019'='Server2019'
      'Windows 10 1607 and Windows Server 2016'='Server2016'
      'Windows Server 2016'='Server2016'
    }
    function Get-LearnMarkdown { param([string]$Url)
      try{
        $r=Invoke-WebRequest -Uri $Url -Method Get -UserAgent $LearnUA -TimeoutSec 30 -UseBasicParsing
        if($r.StatusCode -ne 200){ return $null }
        $b=[string]$r.Content; if($null -eq $b){ return $null }
        return ($b -replace "`r`n","`n")
      } catch { return $null }
    }
    function Split-LearnTableRow { param([string]$Line)
      $parts=$Line -split '\|'; $parts=$parts | ForEach-Object { $_.Trim() }
      if($parts.Count -gt 0 -and $parts[0] -eq ''){ $parts=$parts[1..($parts.Count-1)] }
      if($parts.Count -gt 0 -and $parts[-1] -eq ''){ $parts=$parts[0..($parts.Count-2)] }
      return ,([string[]]$parts)
    }
    function Test-LearnTableSeparator { param([string]$Line)
      $s=$Line.Trim(); if(-not $s.StartsWith('|')){ return $false }
      $cells=Split-LearnTableRow -Line $s; if($cells.Count -eq 0){ return $false }
      foreach($c in $cells){ if($c -notmatch '^:?-+:?$'){ return $false } }
      return $true
    }
    function ConvertFrom-LearnKbCell { param([string]$Cell)
      $t=$Cell.Trim(); if([string]::IsNullOrEmpty($t)){ return $null }
      $m=[regex]::Match($t,'\[?KB?(\d{6,7})\]?'); if(-not $m.Success){ return $null }
      return ('KB'+$m.Groups[1].Value)
    }
    function ConvertFrom-LearnReleaseInfoLcu { param([string]$Markdown)
      # GENERIC parse: windows-server-release-info markdown -> hashtable OsShort -> newest LCU {KB,Date,Build,UpdateType}
      $res=@{}; if(-not $Markdown){ return $res }
      $lines=$Markdown -split "`n"; $section=''; $curOs=''; $hdr=($LearnReleaseInfoMonthlyHeaders -join '|'); $i=0
      while($i -lt $lines.Count){
        $t=$lines[$i].Trim()
        if($t.StartsWith('## Windows Server release history')){ $section='rh'; $curOs=''; $i++; continue }
        if($t.StartsWith('## ') -and $section -eq 'rh'){ $section=''; $curOs='' }
        $mo=[regex]::Match($t,'^\*\*Windows Server (\d{4})\s*\(OS build (\d+)\)\*\*',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if($mo.Success -and $section -eq 'rh'){ $curOs=('Server'+$mo.Groups[1].Value); $i++; continue }
        if($section -eq 'rh' -and $curOs -and $t.StartsWith('|')){
          $cells=Split-LearnTableRow -Line $t
          $sep=(($i+1) -lt $lines.Count) -and (Test-LearnTableSeparator -Line $lines[$i+1])
          if((($cells -join '|') -eq $hdr) -and $sep){
            $k=$i+2
            while($k -lt $lines.Count){
              $rl=$lines[$k]; if(-not $rl.TrimStart().StartsWith('|')){ break }
              $rc=Split-LearnTableRow -Line $rl
              if($rc.Count -eq $LearnReleaseInfoMonthlyHeaders.Count -and $rc[2] -match '^\d{4}-\d{2}-\d{2}$'){
                $kb=ConvertFrom-LearnKbCell -Cell $rc[4]
                if($kb){ $date=$rc[2]; if((-not $res.ContainsKey($curOs)) -or ($date -gt $res[$curOs].Date)){ $res[$curOs]=[pscustomobject]@{ KB=$kb; Date=$date; Build=$rc[3]; UpdateType=$rc[1] } } }
              }
              $k++
            }
            $i=$k; continue
          }
        }
        $i++
      }
      return $res
    }
    function Get-LearnLcuLatestByOs { $md=Get-LearnMarkdown -Url $LearnReleaseInfoUrl; return (ConvertFrom-LearnReleaseInfoLcu -Markdown $md) }
    function Split-LearnDotNetFrontMatter { param([string]$Markdown)
      if(-not $Markdown.StartsWith('---')){ return $Markdown }
      $rest=$Markdown.Substring(3); $m=[regex]::Match($rest,'(?m)^---\s*$'); if(-not $m.Success){ return $Markdown }
      return (($rest.Substring($m.Index+$m.Length)) -replace '^[\r\n]+','')
    }
    function ConvertFrom-LearnDotNetIndexMarkdown { param([string]$Markdown)
      $body=Split-LearnDotNetFrontMatter -Markdown $Markdown
      $rx=[regex]'^- ([A-Za-z]+ \d{1,2}, \d{4}) - \[([^\]]+)\]\(([^)]+)\)\s*(?:\*\*[^*]+\*\*)?\s*$'
      $entries=@(); $inv=[Globalization.CultureInfo]::InvariantCulture
      foreach($rawLine in ($body -split "`n")){
        $line=$rawLine.TrimEnd("`r"); $h=$rx.Match($line); if(-not $h.Success){ continue }
        $dateText=$h.Groups[1].Value; $iso=''
        try{ $iso=([datetime]::ParseExact($dateText,'MMMM d, yyyy',$inv)).ToString('yyyy-MM-dd') } catch { $iso='' }
        $entries+=[pscustomobject]@{ DateText=$dateText; Date=$iso; Kind=$h.Groups[2].Value.Trim(); AbsoluteUrl=($LearnDotNetUrlBase+$h.Groups[3].Value.Trim()) }
      }
      return @($entries)
    }
    function ConvertFrom-LearnDotNetOsLabel { param([string]$Label)
      foreach($needle in $LearnDotNetOsLongToShort.Keys){ if($Label.Contains($needle)){ return [string]$LearnDotNetOsLongToShort[$needle] } }
      return ''
    }
    function ConvertFrom-LearnDotNetMarkdown { param([string]$Markdown)
      # GENERIC parse: one monthly .NET CU page Summary tables -> hashtable OsShort -> @(.NET rows {Versions,KB})
      $body=Split-LearnDotNetFrontMatter -Markdown $Markdown
      $hRx=[regex]'^## Summary tables\s*$'; $otherRx=[regex]'^## (?!Summary tables\b).+$'
      $hdrRx=[regex]'^\|\s*Product version\s*\|'; $sepRx=[regex]'^\|\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|\s*$'
      $osRx=[regex]'^\|\s*\*\*([^|*]+?)\*\*\s*\|\s*(.*?)\s*\|\s*$'; $netRx=[regex]'^\|\s*\.NET Framework\s+([^|]+?)\s*\|\s*(.*?)\s*\|\s*$'; $kbRx=[regex]'(\d{6,7})'
      $inSec=$false; $res=@{}; $curOs=$null
      foreach($rawLine in ($body -split "`n")){
        $line=$rawLine.TrimEnd("`r")
        if(-not $inSec){ if($hRx.IsMatch($line)){ $inSec=$true }; continue }
        if($otherRx.IsMatch($line)){ break }
        if($hdrRx.IsMatch($line)){ $curOs=$null; continue }
        if($sepRx.IsMatch($line)){ continue }
        $om=$osRx.Match($line)
        if($om.Success){ $curOs=(ConvertFrom-LearnDotNetOsLabel -Label ($om.Groups[1].Value.Trim())); continue }
        $nm=$netRx.Match($line)
        if($nm.Success -and $curOs){
          $kbm=$kbRx.Match($nm.Groups[2].Value)
          if($kbm.Success){ $kb=('KB'+$kbm.Groups[1].Value); $ver=$nm.Groups[1].Value.Trim(); if(-not $res.ContainsKey($curOs)){ $res[$curOs]=@() }; $res[$curOs]+=[pscustomobject]@{ Versions=$ver; KB=$kb } }
        }
      }
      return $res
    }
    function Get-LearnDotNetLatestByOs { param([int]$MaxPages=4)
      $idx=Get-LearnMarkdown -Url $LearnDotNetIndexUrl; $res=@{}; if(-not $idx){ return $res }
      $entries=@(ConvertFrom-LearnDotNetIndexMarkdown -Markdown $idx); $n=0
      foreach($e in $entries){
        if($n -ge $MaxPages){ break }
        $md=Get-LearnMarkdown -Url ($e.AbsoluteUrl+'?accept=text/markdown'); $n++
        if(-not $md){ continue }
        $page=ConvertFrom-LearnDotNetMarkdown -Markdown $md
        foreach($os in @($page.Keys)){ if(-not $res.ContainsKey($os)){ $rows=@($page[$os]); $res[$os]=[pscustomobject]@{ KB=$rows[0].KB; Versions=$rows[0].Versions; Rows=$rows; MonthDate=$e.Date } } }
      }
      return $res
    }
    function Invoke-LearnCrossCheck { param([string]$OsShortName,[object[]]$CurrentSet,[object[]]$CurrentSetLeaves)
      # GENERIC cross-check vs Microsoft Learn. LCU is checked for every OS (one LCU per OS). The .NET row is emitted ONLY when the current set
      # carries an in-scope STANDALONE .NET line -- per-OS: Server2016 has none (its in-box .NET 3.5/4.6.2/4.7.x rides in the OS LCU), so 2016 = LCU only.
      $ourLcu=@(@($CurrentSet)|Where-Object{$_.Line -eq 'LCU'}|ForEach-Object{$_.KB}|Select-Object -Unique)
      $ourNet=@(@($CurrentSet)|Where-Object{$_.Line -like 'NET*'}|ForEach-Object{$_.KB}|Select-Object -Unique)
      $norm={ param($k) if($k){ ('KB'+(($k -replace '^KB','').Trim())) } else { $null } }
      $rows=@()
      $lcuMap=Get-LearnLcuLatestByOs
      $learnLcu= if($lcuMap.ContainsKey($OsShortName)){ $lcuMap[$OsShortName] } else { $null }
      $oL= if($ourLcu.Count){ (& $norm $ourLcu[0]) } else { $null }; $lL= if($learnLcu){ $learnLcu.KB } else { $null }
      $rows+=[pscustomobject]@{ Line='LCU'; OurKB=$oL; LearnKB=$lL; LearnDate=$(if($learnLcu){$learnLcu.Date}else{$null}); Match=([bool]($oL -and $lL -and ($oL -eq $lL))); Source='windows-server-release-info' }
      if($ourNet.Count){
        $netMap=Get-LearnDotNetLatestByOs
        $learnNet= if($netMap.ContainsKey($OsShortName)){ $netMap[$OsShortName] } else { $null }
        $netKbForCheck=$ourNet[0]
        if($CurrentSetLeaves){ $inboxNet=@(@($CurrentSetLeaves)|Where-Object{ $_.PSObject.Properties['Scope'] -and $_.PSObject.Properties['LeafKB'] -and ($_.Line -like 'NET*') -and ($_.Scope -eq 'inbox') -and $_.LeafKB }); if($inboxNet.Count){ $netKbForCheck=$inboxNet[0].LeafKB } }
        $oN=(& $norm $netKbForCheck)
        $learnNetKbs= if($learnNet){ @(@($learnNet.Rows)|ForEach-Object{ $_.KB }) } else { @() }
        $netMatch=[bool]($oN -and (@($learnNetKbs) -contains $oN))
        $rows+=[pscustomobject]@{ Line='NET'; OurKB=$oN; LearnKB=$(if($netMatch){ $oN } elseif(@($learnNetKbs).Count){ (@($learnNetKbs) -join ',') } else { $null }); LearnKBs=@($learnNetKbs); LearnDate=$(if($learnNet){$learnNet.MonthDate}else{$null}); Match=$netMatch; Source='dotnet-release-notes' }
      }
      return @($rows)
    }
    function Get-FsCovering { param([string[]]$Cats,[int]$MaxPages=4)
      $catX='<Categories>'+(($Cats|ForEach-Object{"<IdAndDelta><Id>$_</Id><Delta>false</Delta></IdAndDelta>"}) -join '')+'</Categories>'
      $ids=[System.Collections.Generic.List[object]]::new(); $seen=@{}; $anchor=$null; $prev=$null; $page=0
      do {
        $page++
        $aX= if($anchor){"<Anchor>$([Security.SecurityElement]::Escape($anchor))</Anchor>"}else{''}
        $ril=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetRevisionIdList" -InnerBody "<GetRevisionIdList xmlns=`"$NsSDS`">$sck<filter>$aX<GetConfig>false</GetConfig><Get63LanguageOnly>false</Get63LanguageOnly>$catX$classXml</filter></GetRevisionIdList>"
        $new=0
        if($ril.IsSuccess -and $ril.ResponseContent){ try{ $x=[xml]$ril.ResponseContent
          foreach($id in $x.SelectNodes("//*[local-name()='NewRevisions']/*[local-name()='UpdateIdentity']")){ $u=Get-XmlText $id 'UpdateID'; $rv=Get-XmlText $id 'RevisionNumber'; if($u){ $k=$u.ToLowerInvariant(); if(-not $seen.ContainsKey($k)){ $seen[$k]=1; $new++; $ids.Add([pscustomobject]@{UpdateID=$u;RevisionNumber=[int]$rv}) } } }
          $prev=$anchor; $anchor=Get-XmlText $x 'Anchor'
        }catch{} }
        if($ids.Count -gt 60000){ break }
        if($new -eq 0){ break }
        if($anchor -and $prev -and ($anchor -eq $prev)){ break }
      } while($page -lt $MaxPages -and $anchor)
      $ids
    }
    # decompress an XmlUpdateBlobCompressed (base64 -> .cab holding UTF-16 XML -> expand.exe), reading only the HEAD
    # (UpdateType/Title/KB/Prerequisites live in the first ~1-2KB; the bulk is the ApplicabilityRules CBS tree, up to ~80MB)
    function Get-FsMetadata { param([object[]]$Rows,[string]$Label,[string]$RawSampleFile)
      $out=[System.Collections.Generic.List[object]]::new(); $bs=100
      $tot=[math]::Ceiling($Rows.Count/[double]$bs)
      for($bi=0;$bi -lt $Rows.Count;$bi+=$bs){
        $batch=@($Rows[$bi..([math]::Min($bi+$bs-1,$Rows.Count-1))])
        $uidB='<updateIds>'+(($batch|ForEach-Object{"<UpdateIdentity><UpdateID>$($_.UpdateID)</UpdateID><RevisionNumber>$($_.RevisionNumber)</RevisionNumber></UpdateIdentity>"}) -join '')+'</updateIds>'
        $gud=Invoke-SoapCapture -Url $ssEp -Action "$NsSDS/GetUpdateData" -InnerBody "<GetUpdateData xmlns=`"$NsSDS`">$sck$uidB</GetUpdateData>"
        if($RawSampleFile -and $bi -eq 0 -and $gud.ResponseContent){ try{ [IO.File]::WriteAllText($RawSampleFile,$gud.ResponseContent) }catch{} }
        if($gud.IsSuccess -and $gud.ResponseContent){ try{
          $urlMap=@{}; foreach($um in [regex]::Matches($gud.ResponseContent,'<ServerSyncUrlData>.*?<FileDigest>([^<]+)</FileDigest>.*?<MUUrl>([^<]+)</MUUrl>.*?</ServerSyncUrlData>','Singleline')){ $urlMap[$um.Groups[1].Value]=$um.Groups[2].Value }
          foreach($suN in [regex]::Matches($gud.ResponseContent,'<ServerSyncUpdateData>(.*?)</ServerSyncUpdateData>','Singleline')){
            $seg=$suN.Groups[1].Value
            $uidH= if($seg -match '<UpdateID>([^<]+)</UpdateID>'){ $Matches[1] } else { $null }
            $revH= if($seg -match '<RevisionNumber>([0-9]+)</RevisionNumber>'){ [int]$Matches[1] } else { 0 }
            $blob= if($seg -match '(?s)<XmlUpdateBlob>(.*?)</XmlUpdateBlob>'){ [System.Net.WebUtility]::HtmlDecode($Matches[1]) } else { '' }
            $wasComp=$false
            if(-not $blob){ $b64c= if($seg -match '(?s)<XmlUpdateBlobCompressed>(.*?)</XmlUpdateBlobCompressed>'){ ($Matches[1].Trim()) } else { '' }; if($b64c){ $dc=Expand-FsCompressedBlob -B64 $b64c -ScratchDir $fsScratch; if($dc){ $blob=$dc; $wasComp=$true } } }
            $rec=ConvertFrom-WuUpdateSegment -Seg $seg -Blob $blob -WasCompressed $wasComp -UrlMap $urlMap -ClassList $WsusssClassifications
            $out.Add($rec)
          }
        }catch{} }
        Write-Host ("      [{0}] GetUpdateData {1} batch {2}/{3} | records={4}" -f ([DateTime]::Now.ToString('HH:mm:ss')),$Label,([int]($bi/$bs)+1),$tot,$out.Count)
      }
      $out
    }

    # FIXED product GUID(s) per OS (register 11.1) -- the durable seed; the full node set is then DISCOVERED.
    $fsOsList=@(
      [pscustomobject]@{Os='Server2016';Fixed=@('569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5')},
      [pscustomobject]@{Os='Server2019';Fixed=@('f702a48c-919b-45d6-9aef-ca4248d50397')},
      [pscustomobject]@{Os='Server2022';Fixed=@('71718f13-7324-4b0f-8f9e-2ca9dc978e53','97b08ca0-db59-468d-8c47-0ecaad647997')},
      [pscustomobject]@{Os='Server2025';Fixed=@('b256987d-4693-4c87-955d-dbb9341205eb')}
    )
    $dsDir=[IO.Path]::Combine($fsDir,'dataset'); New-Item -ItemType Directory -Force -Path $dsDir | Out-Null
    $fsScratch=[IO.Path]::Combine([IO.Path]::GetTempPath(),('fsblob_'+[Guid]::NewGuid().ToString('N'))); New-Item -ItemType Directory -Force -Path $fsScratch | Out-Null
    $fsOverview=@()
    foreach($osc in $fsOsList){
      Write-Host ("  [FS 1] {0}: covering(fixed {1}) -> GetUpdateData -> discover nodes ..." -f $osc.Os,($osc.Fixed -join ','))
      $m0=@(Get-FsCovering -Cats (@($osc.Fixed)+$WsusssClassifications) -MaxPages 4)
      Write-Host ("    {0}: covering(fixed) membership = {1}  (en/ja titles come from each blob)" -f $osc.Os,$m0.Count)
      $recs=[System.Collections.Generic.List[object]]::new()
      foreach($r in @(Get-FsMetadata -Rows $m0 -Label ($osc.Os+'/M0') -RawSampleFile ([IO.Path]::Combine($fsDir,('raw.'+$osc.Os+'.getupdatedata.b0.xml'))))){ [void]$recs.Add($r) }
      # discover the complete product-node set from LCU-typed entries
      $nodes=@($osc.Fixed)
      foreach($r in @($recs | Where-Object { $_.PSObject.Properties['TypeGuess'] -and $_.TypeGuess -like 'LCU*' })){ foreach($p in @($r.Products)){ if($nodes -notcontains $p){ $nodes+=$p } } }
      $added=@($nodes | Where-Object { $osc.Fixed -notcontains $_ })
      if($added.Count -gt 0){
        Write-Host ("    {0}: discovered +{1} product node(s): {2} -> expanding covering" -f $osc.Os,$added.Count,($added -join ','))
        $m1=@(Get-FsCovering -Cats (@($nodes)+$WsusssClassifications) -MaxPages 4)
        $known=@{}; foreach($r in $recs){ if($r.UpdateID){ $known[$r.UpdateID.ToLowerInvariant()]=1 } }
        $extra=@($m1 | Where-Object { -not $known.ContainsKey($_.UpdateID.ToLowerInvariant()) })
        if($extra.Count -gt 0){ foreach($r in @(Get-FsMetadata -Rows $extra -Label ($osc.Os+'/expand'))){ [void]$recs.Add($r) } }
      }
      $lcuAll=@(@($recs) | Where-Object { $_.PSObject.Properties['TypeGuess'] -and $_.TypeGuess -like 'LCU*' } | Sort-Object @{Expression={Get-FsYm $_.Title}} -Descending)
      $newestLcu= if($lcuAll.Count){ $lcuAll[0] } else { $null }
      $enN=@(@($recs)|Where-Object{$_.HasEn}).Count; $jaN=@(@($recs)|Where-Object{$_.HasJa}).Count
      $allSup=@{}; foreach($r in $recs){ foreach($sid in @($r.SupersededIds)){ if($sid){ $allSup[$sid]=1 } } }
      $uidSet=@{}; foreach($r in $recs){ if($r.UpdateID){ $uidSet[$r.UpdateID.ToLowerInvariant()]=1 } }
      foreach($r in $recs){ $ku= if($r.UpdateID){ $r.UpdateID.ToLowerInvariant() } else { $null }; $isSup= if($ku){ $allSup.ContainsKey($ku) } else { $false }; $r | Add-Member -NotePropertyName IsSuperseded -NotePropertyValue $isSup -Force }
      $supTotal=$allSup.Count; $supIn=0; foreach($k in $allSup.Keys){ if($uidSet.ContainsKey($k)){ $supIn++ } }
      $bundleN=@(@($recs)|Where-Object{$_.IsBundle}).Count; $supersededN=@(@($recs)|Where-Object{$_.IsSuperseded}).Count; $liveBundleN=@(@($recs)|Where-Object{$_.IsBundle -and -not $_.IsSuperseded}).Count
      $leafN=@(@($recs)|Where-Object{$_.HasBlob -and $_.Title}).Count; $nonleafN=@(@($recs)|Where-Object{$_.HasBlob -and -not $_.Title}).Count; $noblobN=@(@($recs)|Where-Object{-not $_.HasBlob}).Count
      $compN=@(@($recs)|Where-Object{$_.Compressed}).Count
      $kindH=@{}; foreach($r in $recs){ $k=$r.Kind; if(-not $kindH.ContainsKey($k)){$kindH[$k]=0}; $kindH[$k]++ }
      $currentSet = $null; $currentSetLeaves = $null; $dotNetScopeNote = $null; $ssuModelNote = $null; $lcuScopeNote = $null; $dynamicUpdate = $null; $ssu = $null; $safeOsDu = $null; $duModelNote = $null
      switch($osc.Os){
        'Server2016' {
          $currentSet = @(Get-Server2016CurrentSet -Records @($recs))
          $currentSetLeaves = @(Invoke-Server2016LeafFollow -CurrentSet $currentSet -SsEp $ssEp -NsSDS $NsSDS -Cookie $sck -ScratchDir $fsScratch -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2016.leaffollow.b0.xml')))
          $dotNetScopeNote = 'in-box .NET (3.5/4.6.2/4.7.x) is serviced via the OS LCU (same KB as the LCU; no standalone in-box .NET package in catalog); the standalone .NET 4.8 CU is EXCLUDED as a not-preinstalled add-on per the in-box-only policy'
          $ssuModelNote = 'standalone SSU (KB5094141) is selected as a separate line -- 2016 is the only OS with a separately-selectable SSU (research doc 5.4)'
        }
        'Server2019' {
          $currentSet = @(Get-Server2019CurrentSet -Records @($recs))
          $currentSetLeaves = @(Invoke-Server2019LeafFollow -CurrentSet $currentSet -SsEp $ssEp -NsSDS $NsSDS -Cookie $sck -ScratchDir $fsScratch -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2019.leaffollow.b0.xml')))
          $dotNetScopeNote = '.NET via the COMBINED CU (3.5/4.7.2/4.8, e.g. KB5088864); only the in-box 3.5/4.7.2 leaf (Windows10.0-KB5087061-x64) is in scope -- the 4.8 NDP48 leaf is flagged addon-out-of-scope per the in-box-only policy'
          $ssuModelNote = 'no standalone SSU line -- 2019 is combined; the servicing stack is the embedded selfUpdate/permanent SSU (KB5094143) inside the LCU leaf (research doc 5.4)'
        }
        'Server2022' {
          $currentSet = @(Get-Server2022CurrentSet -Records @($recs))
          $currentSetLeaves = @(Invoke-Server2022LeafFollow -CurrentSet $currentSet -SsEp $ssEp -NsSDS $NsSDS -Cookie $sck -ScratchDir $fsScratch -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2022.leaffollow.b0.xml')))
          $dotNetScopeNote = '.NET via the COMBINED CU (3.5/4.8/4.8.1, e.g. KB5088862); in-box on 2022 is 4.8, so only the 3.5/4.8 leaf (NDP48, KB5087068) is in scope -- the 4.8.1 NDP481 leaf (KB5087059) is flagged addon-out-of-scope per the in-box-only policy'
          $ssuModelNote = 'no standalone SSU line -- 2022 is combined; the servicing stack is the embedded SSU package (KB5094147) inside the LCU leaf (installerAssembly placeholder 6.0.0.0), research doc 5.4'
          $lcuScopeNote = 'LCU = Microsoft server operating system version 21H2 (the general Server 2022 LCU); the Datacenter: Azure Edition SKU (same KB, different edition) and the Azure Stack HCI hotpatches are excluded as out-of-scope'
          # --- 2022 Dynamic Update sub-acquisition (CASE 2: SEPARATE, localized; does NOT touch the main covering) ---
          # The server DU is NOT under the OS product node (71718f13/97b08ca0); it sits under the modern DU category
          # e4b04398 (shared by client + every server DU generation), so it is acquired by its OWN covering on the DU
          # node(s) and selected by TITLE: server 'version 21H2' = Server 2022, skipping 22H2 / Azure / Hotpatch / Preview / client.
          try {
            $duNodes=@('e4b04398-adbd-4b69-93b9-477322331cd3','dd1aa213-54e7-4173-8456-b278964a26b6')
            $duCov=@(Get-FsCovering -Cats $duNodes -MaxPages 12)
            $duRecs=@(Get-FsMetadata -Rows $duCov -Label 'Server2022/DU' -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2022.du.b0.xml')))
            $du2022=@($duRecs | Where-Object { $_.TitleEn -and ($_.TitleEn -match 'server operating system version 21H2') -and ($_.TitleEn -notmatch 'Azure|Hotpatch|Preview') })
            $duSel=$du2022 | Sort-Object { if($_.KB -and ($_.KB -match '^[0-9]+$')){ [int]$_.KB } else { 0 } } -Descending | Select-Object -First 1
            $duLeaves=@()
            if($duSel -and @($duSel.BundledLeaf).Count -gt 0){ $duLeaves=@(Get-FsMetadata -Rows @($duSel.BundledLeaf) -Label 'Server2022/DU-leaf' -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2022.du-leaf.b0.xml'))) }
            if($duSel){
              $dynamicUpdate=[ordered]@{ Node='e4b04398 (modern DU category; NOT the OS product node) -- CASE 2 separate covering, title-selected version-21H2 server SafeOS DU'; CandidatesInCovering=@($duRecs).Count; Server21H2Candidates=@($du2022).Count; Selected=[ordered]@{ UpdateID=$duSel.UpdateID; RevisionNumber=$duSel.RevisionNumber; KB=$duSel.KB; TitleEn=$duSel.TitleEn; MsrcSeverity=$duSel.MsrcSeverity; BundledLeaf=@($duSel.BundledLeaf); SupersededIds=@($duSel.SupersededIds) }; Leaves=@($duLeaves | ForEach-Object { [ordered]@{ UpdateID=$_.UpdateID; RevisionNumber=$_.RevisionNumber; TitleEn=$_.TitleEn; Compressed=$_.Compressed; FileDigests=@($_.FileDigests); Urls=@($_.Urls) } }) }
            } else {
              $dynamicUpdate=[ordered]@{ Node='e4b04398'; CandidatesInCovering=@($duRecs).Count; Server21H2Candidates=0; Selected=$null; Leaves=@(); Note='no version-21H2 server SafeOS DU found in the DU covering' }
            }
            if($duSel){ Write-Host ("    {0}: DYNAMIC UPDATE (CASE2 e4b04398): KB{1} | leaves={2} | DU-candidates={3} ver21H2={4}" -f $osc.Os,$duSel.KB,@($duLeaves).Count,@($duRecs).Count,@($du2022).Count) }
          } catch { $dynamicUpdate=[ordered]@{ Error=$_.Exception.Message } }
        }
        'Server2025' {
          $currentSet = @(Get-Server2025CurrentSet -Records @($recs))
          $currentSetLeaves = @(Invoke-Server2025LeafFollow -CurrentSet $currentSet -SsEp $ssEp -NsSDS $NsSDS -Cookie $sck -ScratchDir $fsScratch -RawSampleFile ([IO.Path]::Combine($fsDir,'raw.Server2025.leaffollow.b0.xml')))
          $dotNetScopeNote = '.NET via the combined CU 3.5/4.8.1 (KB5087051), x64; in-box on 2025 is 4.8.1, so the whole x64 .NET leaf is in scope (no add-on split). arm64 .NET is excluded.'
          $ssuModelNote = 'UUP checkpoint model: NO standalone SSU line. The servicing stack ships as SSU-26100.xxxxx-x64 (a checkpoint) INSIDE the LCU leaf 16-file payload, recorded first-class in the Ssu field from the leaf files. The SSU is the LCU servicing-stack prerequisite (gates apply-order).'
          $lcuScopeNote = 'LCU = Microsoft server operating system version 24H2 (KB5094125, build 26100.32995), x64. No arm64 LCU in this node; Preview excluded.'
          $duModelNote = 'SafeOS DU (Windows11.0-KB5094150-x64) is co-bundled in the LCU leaf and recorded first-class in SafeOsDu. No separate DU node/acquisition for 2025 (unlike the Server2022 case-2).'
          $lcuLeaf=@($currentSetLeaves | Where-Object { $_.Line -eq 'LCU' })
          $ssuFiles=@(); $duFiles=@()
          foreach($ll in @($lcuLeaf)){ foreach($f in @($ll.Files)){ if($f.PSObject.Properties['Class']){ if($f.Class -eq 'SSU'){ $ssuFiles+=$f } elseif($f.Class -eq 'SafeOS-DU'){ $duFiles+=$f } } } }
          $ssuVer=$null; foreach($sf in @($ssuFiles)){ if((-not $ssuVer) -and ($sf.FileName -match 'SSU-([0-9]+\.[0-9]+)')){ $ssuVer=$Matches[1] } }
          if(@($ssuFiles).Count){ $ssu=[ordered]@{ Model='uup-checkpoint-in-lcu-leaf'; Standalone=$false; Provenance='wire:leaf-follow'; Role='servicing-stack prerequisite of the LCU (gates apply-order); delivered as a checkpoint inside the LCU leaf payload'; Version=$ssuVer; Files=@($ssuFiles | ForEach-Object { [ordered]@{ FileName=$_.FileName; Digest=$_.Digest; Size=$_.Size; PatchingType=$_.PatchingType; Url=$_.Url } }) } }
          if(@($duFiles).Count){ $safeOsDu=[ordered]@{ Model='co-bundled-in-lcu-leaf'; Standalone=$false; Provenance='wire:leaf-follow'; Note='SafeOS DU rides inside the LCU leaf 16-file payload; no separate DU node/acquisition for 2025'; Files=@($duFiles | ForEach-Object { [ordered]@{ FileName=$_.FileName; Digest=$_.Digest; Size=$_.Size; PatchingType=$_.PatchingType; Url=$_.Url } }) } }
          if($ssu){ Write-Host ("    {0}: SSU (UUP checkpoint in LCU leaf): {1} ({2} file[s])" -f $osc.Os,$ssuVer,@($ssuFiles).Count) }
          if($safeOsDu){ Write-Host ("    {0}: SafeOS DU (co-bundled in LCU leaf): {1} file[s]" -f $osc.Os,@($duFiles).Count) }
        }
      }
      if($null -ne $currentSet){
        $csStr=(@($currentSet) | ForEach-Object { ('{0}=KB{1}(leaf x{2})' -f $_.Line,$_.KB,@($_.BundledLeaf).Count) }) -join ' '
        Write-Host ("    {0}: CURRENT SET ({1} target identity[ies]): {2}" -f $osc.Os,@($currentSet).Count,$csStr)
      }
      if($null -ne $currentSetLeaves){
        $lfFiles=0; $lfUrls=0; foreach($lr in @($currentSetLeaves)){ $lfFiles+=[int]$lr.FileCount; $lfUrls+=[int]$lr.UrlCount }
        $lfStr=(@($currentSetLeaves) | ForEach-Object { ('{0}:leaf {1}=files {2}/urls {3}{4}{5}' -f $_.Line,$(if($_.LeafUpdateID){$_.LeafUpdateID.Substring(0,8)}else{'-'}),$_.FileCount,$_.UrlCount,$(if($_.Compressed){'(cmp)'}else{''}),$(if($_.PSObject.Properties['Scope'] -and $_.Scope -eq 'addon-out-of-scope'){' [OUT-OF-SCOPE:addon]'}else{''})) }) -join ' | '
        Write-Host ("    {0}: LEAF-FOLLOW ({1} leaf[s], files={2} urls={3}): {4}" -f $osc.Os,@($currentSetLeaves).Count,$lfFiles,$lfUrls,$lfStr)
      }
      $crossCheck = $null
      if($null -ne $currentSet){ try { $crossCheck = @(Invoke-LearnCrossCheck -OsShortName $osc.Os -CurrentSet $currentSet -CurrentSetLeaves $currentSetLeaves) } catch { $crossCheck = $null } }
      if($null -ne $crossCheck){
        foreach($cc in @($crossCheck)){ Write-Host ("    {0}: LEARN CROSS-CHECK {1}: ours={2} learn={3} -> {4}" -f $osc.Os,$cc.Line,$(if($cc.OurKB){$cc.OurKB}else{'-'}),$(if($cc.LearnKB){$cc.LearnKB}else{'unavailable'}),$(if($cc.Match){'MATCH'}else{'MISMATCH/NA'})) }
      }
      $ds=[ordered]@{ Os=$osc.Os; LanguageScope='en,ja'; LanguageHandling='dataset-level: en/ja Title taken from each blob LocalizedProperties (33 langs per blob); server-side <Languages> covering filter collapses results to ~1 rev and is NOT used'; RecordsWithEn=$enN; RecordsWithJa=$jaN; FixedNodes=$osc.Fixed; DiscoveredNodes=$added; AllNodes=$nodes; MembershipCount=$recs.Count; Leaf=$leafN; NonLeaf=$nonleafN; NoBlob=$noblobN; KindBreakdown=$kindH; Bundles=$bundleN; Superseded=$supersededN; LiveBundles=$liveBundleN; SupersededTargets=$supTotal; SupersededTargetsInSet=$supIn; CurrentSet=$currentSet; CurrentSetLeaves=$currentSetLeaves; CrossCheck=$crossCheck; DotNetScopeNote=$dotNetScopeNote; SsuModelNote=$ssuModelNote; LcuScopeNote=$lcuScopeNote; DynamicUpdate=$dynamicUpdate; Ssu=$ssu; SafeOsDu=$safeOsDu; DuModelNote=$duModelNote; NewestLcu=$(if($newestLcu){[ordered]@{KB=$newestLcu.KB;UpdateID=$newestLcu.UpdateID;TitleEn=$newestLcu.TitleEn;TitleJa=$newestLcu.TitleJa;HasUrl=$newestLcu.HasUrl}}else{$null}); Records=@($recs) }
      Save-Json -Path ([IO.Path]::Combine($dsDir,("{0}.json" -f $osc.Os))) -Object $ds
      $typeStr=(($kindH.GetEnumerator()|Sort-Object Name|ForEach-Object{"$($_.Name)=$($_.Value)"}) -join ' ')
      $fsOverview+=[pscustomobject]@{Os=$osc.Os;Records=$recs.Count;Bundles=$bundleN;Superseded=$supersededN;LiveBundles=$liveBundleN;SupClosure=("{0}/{1}" -f $supIn,$supTotal);Decompressed=$compN;WithEn=$enN;WithJa=$jaN;Nodes=$nodes.Count;Discovered=$added.Count;NewestLcuKB=$(if($newestLcu){$newestLcu.KB}else{$null});Kinds=$typeStr}
      Write-Host ("    {0}: records={1} bundles={2} superseded={3} live-bundles={4} sup-closure={5}/{6} newestLCU=KB{7} | {8}" -f $osc.Os,$recs.Count,$bundleN,$supersededN,$liveBundleN,$supIn,$supTotal,$(if($newestLcu){$newestLcu.KB}else{'?'}),$typeStr)
    }
    Save-Json -Path ([IO.Path]::Combine($fsDir,'00.dataset-overview.json')) -Object $fsOverview
    if(Test-Path $fsScratch){ Remove-Item $fsScratch -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    Write-Host '  FS PHASE 1 (dataset) complete -- per-OS datasets in fs/dataset/<os>.json; overview in fs/00.dataset-overview.json.'
    Write-Host '  (Phase 2 = per-OS resolvers; dependency/apply-order = deferred next phase.)'
  } catch {
    Write-Host ('=== [FS] ERROR -- {0} (zip still produced) ===' -f $_.Exception.Message)
    try { Save-Json -Path ([IO.Path]::Combine($fsDir,'99.error.json')) -Object ([ordered]@{ Message=$_.Exception.Message; Line=$_.InvocationInfo.ScriptLineNumber; Position=$_.InvocationInfo.PositionMessage }) } catch {}
  }
}

# UNIFIED SUMMARY + MANIFEST  (single point-in-time snapshot of both protocols)
# ===================================================================================
$summary=[ordered]@{
    Schema='wu-protocol-survey/1.0'
    ScriptVersion=$SurveyVersion; ScriptVersionTag=$SurveyVersionTag; ScriptBuildDate=$SurveyBuildDate; ScriptChangeNote=$SurveyChangeNote
    CapturedUtc=$capturedUtc
    Host=[ordered]@{ Generation=$gen.FriendlyName; Build=("{0}.{1}" -f $ident.OSBuildNumber,$ident.UBR); ComputerInfoVector=$ident.ComputerInfoVector; WuaAgentVersion=$ident.WuaAgentVersion }
    Service=$Service; ServiceId=$serviceId
    Provenance=$provenance
    Environment=[ordered]@{ Captured=$runWua; Summary=$envSummary }
    Wsusss=[ordered]@{ Captured=$runWsusss; CatalogClean=$wsusssCatalogClean; Ec2LeafRevisions=$wsusssEc2Rows; ReportingProbed=[bool]$IncludeWsusssReporting; Walk=$wsusssWalk }
    Wusp=[ordered]@{ Captured=$runWusp }
    Gate  =[ordered]@{ Policy='WSUSSS CORE quality: all ops (B1-B17) checked'; WsusssAllClean=$wsusssCatalogClean }
    Coverage=$coverage
    Discipline='UNSCOPED per section 0.1: both protocols fully probed; SyncUpdates without FilterCategoryIds; GetRevisionIdList with empty Categories/Classifications; faults captured as observation data.'
}
Save-Json -Path ([IO.Path]::Combine($dir,'00.data-provenance.json')) -Object @($Script:DataProvenance)
Save-Json -Path ([IO.Path]::Combine($dir,'98.conformance.json')) -Object @($Script:WsusssVerdicts)
$confTotal=@($Script:WsusssVerdicts).Count
$confOk=@($Script:WsusssVerdicts | Where-Object { $_.Conformant }).Count
Write-Host (" conformance: {0}/{1} WSUSSS CORE ops SPEC-CONFORMANT (HTTP 200 is NOT the standard) -> 98.conformance.json ; data-provenance: {2} managed values -> 00.data-provenance.json" -f $confOk,$confTotal,@($Script:DataProvenance).Count)
Save-Json -Path ([IO.Path]::Combine($dir,'99.summary.json')) -Object $summary
Save-Json -Path ([IO.Path]::Combine($dir,'provenance.json')) -Object $provenance

$readme=@(
 'WINDOWS UPDATE PROTOCOL SURVEY -- single point-in-time snapshot of BOTH protocols.',
 ("Script version: {0}" -f $SurveyVersionTag),
 'Hand back THIS entire folder (self-contained: request+response+meta for every call), zipped.',
 '',
 ("CapturedUtc: {0}" -f $capturedUtc),
 ("Host: {0}  build {1}.{2}  vector {3}" -f $gen.FriendlyName,$ident.OSBuildNumber,$ident.UBR,$ident.ComputerInfoVector),
 '',
 '  00.client-identity.json / 00.generation.json   client-generated data (local)',
 '  env\     PART 0 Windows OS environment investigation (phase0-report.json + manifest.txt + dll/iface/typelib dumps)',
 '  wsusss\  [MS-WSUSSS] runs FIRST (gates WUSP); 05a=GetConfig=true dictionary, 05b=GetConfig=false EC-2 unscoped enumeration; rollup/report=out-of-scope',
 '  wusp\    [MS-WUSP] runs ONLY if WSUSSS catalog clean (gated); 07.* = full SyncUpdates walk',
 '  99.summary.json   coverage manifest (both protocols) + walk summaries',
 '  provenance.json   spec published-version (embedded ref + live fetch) + live-endpoint protocol info',
 '',
 'A fault(500/404) body is DATA, not failure: it reveals the request shape the live server',
 'requires. Nothing is skipped, minimized, or scoped (no FilterCategoryIds; empty WSUSSS filter).'
) -join "`r`n"
Save-Text -Path ([IO.Path]::Combine($dir,'00.README.txt')) -Text $readme

$confN =@($coverage|Where-Object{$_.status -like 'CONFORMANT*'}).Count
$nconfN=@($coverage|Where-Object{$_.status -like 'NON-CONFORMANT*'}).Count
$h2xxN =@($coverage|Where-Object{$_.status -like 'http-2xx*' -or $_.status -like 'ok*'}).Count
$faultN=@($coverage|Where-Object{$_.status -like 'fault*'}).Count
$nhN   =@($coverage|Where-Object{$_.status -like 'endpoint-not-hosted*'}).Count
$skipN =@($coverage|Where-Object{$_.status -eq 'not-attempted'}).Count
$opReport = Write-OperationReport -OutDir $dir
Write-Host ''
Write-Host '==================================================================='
Write-Host ("  script version : {0}" -f $SurveyVersionTag)
Write-Host ("  single CapturedUtc: {0}" -f $capturedUtc)
Write-Host ("  coverage: conformant={0} non-conformant={1} http-2xx-uncontracted={2} fault(=data)={3} not-hosted={4} not-attempted={5}  (see 97.operation-report.txt / 99.summary.json)" -f $confN,$nconfN,$h2xxN,$faultN,$nhN,$skipN)
if($wsusssWalk){ Write-Host ("  WSUSSS catalog   : taxonomy={0} | EC-2 leaf={1} ({2} pages) stop=[{3}]" -f $wsusssWalk.TaxonomyNodes,$wsusssWalk.Ec2LeafRevisions,$wsusssWalk.Ec2Pages,$wsusssWalk.Ec2Stop) }
Write-Host ("  acquisition mode : {0}" -f $(if(-not $SampleData){'FULL (default): complete data persisted'}else{('SAMPLE (-SampleData): broad enumeration ({0} enumerated) + stride-sampled GetUpdateData harvest (-HarvestSampleSize {1})' -f $wsusssEc2Rows,$HarvestSampleSize)}))
Write-Host ("  CORE catalog clean: {0}   (B10-B17 are non-gating)" -f $wsusssCatalogClean)
foreach($specKey in $provenance.Specs.Keys){ $sp=$provenance.Specs[$specKey]; $rv= if($sp.LiveFetchOk){"$($sp.LiveRevision) ($($sp.LiveDate)) [live]"}else{"$($sp.EmbeddedRevision) ($($sp.EmbeddedDate)) [embedded]"}; Write-Host ("  spec {0,-10}: rev {1}" -f $specKey,$rv) }
if($provenance.Endpoints.Wsusss['ProtocolVersion']){ Write-Host ("  WSUSSS endpoint ProtocolVersion (live): {0}" -f $provenance.Endpoints.Wsusss['ProtocolVersion']) }

# auto-compress the complete run folder into a sibling .zip (the deliverable to hand back).
$zipPath="$dir.zip"
try {
    if(Test-Path $zipPath){ Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
    if(Get-Command Compress-Archive -ErrorAction SilentlyContinue){
        Compress-Archive -Path $dir -DestinationPath $zipPath -Force -ErrorAction Stop
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dir,$zipPath)
    }
    $zipMB=[Math]::Round(((Get-Item $zipPath).Length/1MB),2)
    Write-Host ("  ==== ZIP CREATED (hand back THIS file): {0}  ({1} MB) ====" -f $zipPath,$zipMB)
} catch {
    Write-Host ("  [zip] auto-compress failed: {0}" -f $_.Exception.Message)
    Write-Host ("  ==== HAND BACK THIS FOLDER (zip it manually): {0} ====" -f $dir)
}
Write-Host '==================================================================='

```

## Appendix D — `wsusscn2_analyzer.py`（オフライン cab クロスチェック, Python）

**役割:** オフライン依存クロスチェック `[B]`。`wsusscn2.cab` の Master XML をストリーム（`lxml.iterparse`）し、4つの OS別解決を再現、オラクルに対し `verify`、cab が欠く SafeOS DU を Catalog から解決。スキーマ `wsusscn2-analysis/1.1`。

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wsusscn2_analyzer.py — Offline Windows Server patch-set analyzer for wsusscn2.cab

A single-file, reproducible tool that downloads Microsoft's offline-scan catalog
(``wsusscn2.cab``), parses it, and resolves — per Windows Server generation — the
current latest patch set (LCU / SSU / .NET / SafeOS Dynamic Update) with exact
payload digests and download URLs.

Design goals
------------
* **Reproducible**: same input cab -> byte-stable JSON. Every output is stamped
  with the input cab SHA-256, snapshot date, tool version and schema version.
* **Machine-readable first**: normalized JSON is the primary product; a compact
  human summary is secondary.
* **Per-OS resolvers**: 2016 / 2019 / 2022 / 2025 each have their own resolver
  (deliberately NOT prematurely unified — the per-OS data nuances differ).
* **Grounded constants**: product/classification GUIDs and the .NET in-scope rule
  are explicit, commented constants. KB numbers are NEVER hardcoded — the newest
  live entity is always selected from the cab itself.

Dependencies: Python 3.9+, ``lxml``, and the external ``cabextract`` binary.

License: MIT (see LICENSE).
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as _dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from typing import Dict, Iterable, List, Optional, Tuple

try:
    import lxml.etree as ET
except ImportError:  # pragma: no cover
    sys.stderr.write("FATAL: lxml is required (pip install lxml --break-system-packages)\n")
    raise

# ---------------------------------------------------------------------------
# Versioning & invariants
# ---------------------------------------------------------------------------
TOOL_VERSION = "1.0.0"
SCHEMA_VERSION = "wsusscn2-analysis/1.1"

# Microsoft's official, stable URL for the offline-scan cabinet. The same URL
# always serves the current month's catalog.
WSUSSCN2_URL = "http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab"

# Master XML namespace (the OfflineSync package schema).
NS = "http://schemas.microsoft.com/msus/2004/02/OfflineSync"

# Update-classification GUIDs (stable WSUS taxonomy).
CLASSIFICATION = {
    "Security":      "0fa1201d-4330-4fa8-8ae9-b877473b6441",
    "UpdateRollups": "28bc880e-0592-4cbf-8f95-c79b17911d5f",
    "ServicePacks":  "68c5b0a3-d1a6-4553-ae49-01d3a7827828",
    "Critical":      "e6cf1350-c01b-414d-a61f-263d14d133b4",
    "Updates":       "cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83",
}

# Per-OS product-category GUIDs. These are pinned EMPIRICALLY (validated against
# the SOAP oracle): for each generation, this is the node whose live Security
# bundles carry that generation's LCU. Do not substitute "most frequent" GUIDs —
# those wrongly catch sibling architectures/editions.
OS_PRODUCT_GUID = {
    "Server2016": "569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5",
    "Server2019": "f702a48c-919b-45d6-9aef-ca4248d50397",
    "Server2022": "71718f13-7324-4b0f-8f9e-2ca9dc978e53",
    "Server2025": "b256987d-4693-4c87-955d-dbb9341205eb",
}

SUPPORTED_OSES = list(OS_PRODUCT_GUID.keys())


def _qn(tag: str) -> str:
    """Namespaced QName for the OfflineSync schema."""
    return "{%s}%s" % (NS, tag)


def _localname(tag: str) -> str:
    return tag.split("}", 1)[1] if "}" in tag else tag


def _utcnow_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ===========================================================================
# Layer 1 — Downloader
# ===========================================================================
class Downloader:
    """Fetches wsusscn2.cab from the official URL with integrity recording.

    The download is content-addressed by SHA-256: the hash is computed during
    streaming and recorded so every downstream artifact can be tied to the exact
    input bytes (reproducibility anchor).
    """

    def __init__(self, url: str = WSUSSCN2_URL):
        self.url = url

    def fetch(self, dest_path: str, *, force: bool = False,
              progress: bool = True) -> Dict[str, object]:
        if os.path.exists(dest_path) and not force:
            sha, size = self._hash_file(dest_path)
            return {
                "path": os.path.abspath(dest_path), "url": self.url,
                "sha256": sha, "size": size, "cached": True,
                "downloaded_utc": None,
            }
        os.makedirs(os.path.dirname(os.path.abspath(dest_path)) or ".", exist_ok=True)
        h = hashlib.sha256()
        total = 0
        tmp = dest_path + ".part"
        req = urllib.request.Request(self.url, headers={"User-Agent": "wsusscn2-analyzer/%s" % TOOL_VERSION})
        with urllib.request.urlopen(req, timeout=120) as resp:
            declared = int(resp.headers.get("Content-Length", 0) or 0)
            with open(tmp, "wb") as fh:
                while True:
                    chunk = resp.read(1024 * 1024)
                    if not chunk:
                        break
                    fh.write(chunk)
                    h.update(chunk)
                    total += len(chunk)
                    if progress and declared:
                        pct = 100.0 * total / declared
                        sys.stderr.write("\r  downloading wsusscn2.cab: %6.1f%% (%d/%d bytes)" % (pct, total, declared))
                        sys.stderr.flush()
        if progress:
            sys.stderr.write("\n")
        os.replace(tmp, dest_path)
        return {
            "path": os.path.abspath(dest_path), "url": self.url,
            "sha256": h.hexdigest(), "size": total, "cached": False,
            "downloaded_utc": _utcnow_iso(),
        }

    @staticmethod
    def _hash_file(path: str) -> Tuple[str, int]:
        h = hashlib.sha256()
        size = 0
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
                size += len(chunk)
        return h.hexdigest(), size


# ===========================================================================
# Layer 2 — Extractor
# ===========================================================================
class Extractor:
    """Expands wsusscn2.cab into the Master XML (package.xml) and index.xml.

    Physical layout of wsusscn2.cab (verified):
      index.xml            -- RevisionId-range -> detail-cab map (CABLIST)
      package.cab          -> package.xml      -- the Master OfflineSync package
      package2..N.cab      -- per-RevisionId detail fragments (not needed for
                              current-set resolution; resolution works off the
                              Master + leaf PayloadFiles which the Master carries)
    """

    def __init__(self, cab_path: str, workdir: str):
        if not shutil.which("cabextract"):
            raise RuntimeError("cabextract not found on PATH (required to expand wsusscn2.cab)")
        self.cab_path = cab_path
        self.workdir = workdir
        os.makedirs(workdir, exist_ok=True)

    def _run(self, *args: str) -> None:
        proc = subprocess.run(args, capture_output=True, text=True)
        # cabextract prints a benign trailing-bytes warning on wsusscn2.cab; ignore.
        if proc.returncode != 0:
            raise RuntimeError("cabextract failed: %s\n%s" % (" ".join(args), proc.stderr))

    def extract_master(self) -> str:
        """Extract index.xml + package.cab -> package.xml. Returns Master path."""
        # index.xml (top-level)
        self._run("cabextract", "-q", "-F", "index.xml", "-d", self.workdir, self.cab_path)
        # package.cab (top-level) then package.xml (inside it)
        self._run("cabextract", "-q", "-F", "package.cab", "-d", self.workdir, self.cab_path)
        pkg_cab = os.path.join(self.workdir, "package.cab")
        if not os.path.exists(pkg_cab):
            # Some snapshots name the master cab differently; fall back to listing.
            raise RuntimeError("package.cab not found inside wsusscn2.cab")
        self._run("cabextract", "-q", "-F", "package.xml", "-d", self.workdir, pkg_cab)
        master = os.path.join(self.workdir, "package.xml")
        if not os.path.exists(master):
            raise RuntimeError("package.xml not found inside package.cab")
        return master


# ===========================================================================
# Layer 3 — Parser (streaming, memory-safe)
# ===========================================================================
@dataclasses.dataclass
class UpdateRecord:
    """A normalized Master <Update> record (only fields needed for resolution)."""
    revision_id: int
    update_id: str
    creation_date: str
    is_bundle: bool
    is_leaf: bool
    superseded_by_count: int
    product_guids: Tuple[str, ...]
    classification_guids: Tuple[str, ...]
    payload_digests: Tuple[str, ...]          # this record's own PayloadFiles
    bundled_by_revids: Tuple[int, ...]         # parent bundle RevisionIds (reverse)

    @property
    def is_live(self) -> bool:
        return self.superseded_by_count == 0


class MasterModel:
    """In-memory model of the Master XML, built by a single streaming pass.

    Holds:
      * file_url[digest] -> URL                (the single top-level FileLocations)
      * by_update_id[uid] -> UpdateRecord
      * leaves_by_parent_revid[revid] -> [UpdateRecord, ...]   (bundle -> leaves)
    """

    def __init__(self):
        self.file_url: Dict[str, str] = {}
        self.by_update_id: Dict[str, UpdateRecord] = {}
        self.leaves_by_parent_revid: Dict[int, List[UpdateRecord]] = collections.defaultdict(list)
        self.master_sha256: Optional[str] = None
        self.update_count: int = 0
        self.filelocation_count: int = 0

    @classmethod
    def from_master(cls, master_path: str) -> "MasterModel":
        self = cls()
        # Hash the Master for provenance (independent of cab hash).
        h = hashlib.sha256()
        with open(master_path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
        self.master_sha256 = h.hexdigest()

        # We need a record's bundle->leaf edges (reverse: <BundledBy>) to link a
        # bundle to its leaves. Records appear in document order; FileLocations
        # come at the END of the Master. So we collect raw records first, then
        # build the leaf index after the pass.
        raw: List[UpdateRecord] = []
        context = ET.iterparse(master_path, events=("end",))
        for _event, el in context:
            tag = _localname(el.tag)
            if tag == "FileLocation":
                self.file_url[el.get("Id")] = el.get("Url")
                self.filelocation_count += 1
                _clear(el)
            elif tag == "Update":
                rec = cls._parse_update(el)
                self.by_update_id[rec.update_id] = rec
                raw.append(rec)
                self.update_count += 1
                _clear(el)
        # Build bundle -> leaves index from the reverse edges.
        for rec in raw:
            for parent_revid in rec.bundled_by_revids:
                self.leaves_by_parent_revid[parent_revid].append(rec)
        return self

    @staticmethod
    def _parse_update(el) -> UpdateRecord:
        rid = int(el.get("RevisionId"))
        uid = el.get("UpdateId")
        cd = el.get("CreationDate") or ""
        is_bundle = el.get("IsBundle") == "true"
        is_leaf = el.get("IsLeaf") == "true"

        prods: List[str] = []
        classes: List[str] = []
        cats = el.find(_qn("Categories"))
        if cats is not None:
            for c in cats.findall(_qn("Category")):
                ctype = c.get("Type")
                if ctype == "Product":
                    prods.append(c.get("Id"))
                elif ctype == "UpdateClassification":
                    classes.append(c.get("Id"))

        digs: List[str] = []
        pf = el.find(_qn("PayloadFiles"))
        if pf is not None:
            for f in pf.findall(_qn("File")):
                digs_id = f.get("Id")
                if digs_id:
                    digs.append(digs_id)

        sb = el.find(_qn("SupersededBy"))
        sup_n = len(sb.findall(_qn("Revision"))) if sb is not None else 0

        parents: List[int] = []
        bb = el.find(_qn("BundledBy"))
        if bb is not None:
            for r in bb.findall(_qn("Revision")):
                parents.append(int(r.get("Id")))

        return UpdateRecord(
            revision_id=rid, update_id=uid, creation_date=cd,
            is_bundle=is_bundle, is_leaf=is_leaf, superseded_by_count=sup_n,
            product_guids=tuple(prods), classification_guids=tuple(classes),
            payload_digests=tuple(digs), bundled_by_revids=tuple(parents),
        )

    # -- convenience accessors -------------------------------------------------
    def url_for(self, digest: str) -> Optional[str]:
        return self.file_url.get(digest)

    def filename_for(self, digest: str) -> Optional[str]:
        u = self.file_url.get(digest)
        return u.rsplit("/", 1)[-1] if u else None

    def leaves_of(self, bundle: UpdateRecord) -> List[UpdateRecord]:
        return self.leaves_by_parent_revid.get(bundle.revision_id, [])

    def live_bundles_for_product(self, product_guid: str,
                                 classification_guid: Optional[str] = None) -> List[UpdateRecord]:
        out = []
        for rec in self.by_update_id.values():
            if not rec.is_bundle or not rec.is_live:
                continue
            if product_guid not in rec.product_guids:
                continue
            if classification_guid and classification_guid not in rec.classification_guids:
                continue
            out.append(rec)
        # Deterministic: newest CreationDate first, tie-break by revision_id desc.
        out.sort(key=lambda r: (r.creation_date, r.revision_id), reverse=True)
        return out


def _clear(el) -> None:
    """Free a finished element and its already-processed previous siblings."""
    el.clear()
    while el.getprevious() is not None:
        del el.getparent()[0]


# ===========================================================================
# Layer 4 — File classification (leaf payload -> patch role)
# ===========================================================================
_KB_RE = re.compile(r"kb(\d+)", re.I)
_ARCH_RE = re.compile(r"-(x64|x86|arm64)", re.I)
_NDP_RE = re.compile(r"-ndp(48[01]?)", re.I)


def kb_of(name: Optional[str]) -> Optional[str]:
    if not name:
        return None
    m = _KB_RE.search(name)
    return m.group(1) if m else None


def arch_of(name: Optional[str]) -> Optional[str]:
    if not name:
        return None
    m = _ARCH_RE.search(name)
    return m.group(1).lower() if m else None


def ndp_of(name: Optional[str]) -> Optional[str]:
    if not name:
        return None
    m = _NDP_RE.search(name)
    return m.group(1) if m else None


def classify_uup_file(filename: Optional[str], parent_lcu_kb: Optional[str]) -> str:
    """Classify one file of a 2025-style UUP LCU leaf by its filename.

    Roles: SSU / SafeOS-DU / LCU / GA / NET / LP-FoD / meta / other.
    LCU vs GA is decided durably by KB equality with the parent bundle KB
    (no hardcoded KB): the .msu whose KB == parent LCU KB is the LCU, the other
    .msu is the GA baseline.
    """
    if not filename:
        return "unknown-no-url"
    f = filename.lower()
    if f.startswith("ssu-"):
        return "SSU"
    # SafeOS DU: windows11.0-kbNNN-x64[-baseless].cab/.psf
    if re.search(r"windows1[01]\.0-kb\d+-x64(-baseless)?[._].*\.(cab|psf)$", f) or \
       re.search(r"windows1[01]\.0-kb\d+-x64\.cab$", f):
        return "SafeOS-DU"
    if _NDP_RE.search(f):
        return "NET"
    if f.endswith(".msu"):
        k = kb_of(f)
        if parent_lcu_kb and k == parent_lcu_kb:
            return "LCU"
        return "GA"
    if f.endswith(".wim"):
        return "LP-FoD"
    if "metadata" in f or "compdb" in f or "desktopdeployment" in f:
        return "meta"
    return "other"


def _file_record(model: "MasterModel", digest: str, role: str = None,
                 parent_lcu_kb: str = None) -> Dict[str, object]:
    fn = model.filename_for(digest)
    return {
        "fileName": fn,
        "digest": digest,
        "url": model.url_for(digest),
        "role": role if role is not None else classify_uup_file(fn, parent_lcu_kb),
    }


# ===========================================================================
# Layer 5 — Per-OS resolvers
# ===========================================================================
# Each resolver returns a normalized dict:
#   { "os", "productGuid", "lcu": {...}, "ssu": {...}|None, "dotnet": {...}|None,
#     "safeOsDu": {...}|None, "notes": [...] }
# A patch entry: { "kb", "bundleUpdateId", "leafUpdateId", "title"?, "files": [file_record,...] }
#
# Resolvers are deliberately INDEPENDENT per OS (the data nuances differ). Shared
# helpers above are mechanical only; the SELECTION logic lives per-OS.


def _newest_live_security_bundle(model, product_guid, title_substr=None, title_excludes=()):
    """Return live Security bundles for a product (newest first), optionally
    title-filtered. Title is not in the Master, so callers that need titles must
    rely on filename/KB heuristics instead; title_substr is reserved for future
    detail-cab enrichment and currently ignored when titles are unavailable."""
    return model.live_bundles_for_product(product_guid, CLASSIFICATION["Security"])


def _lcu_leaf_files(model, bundle, parent_lcu_kb):
    """All payload files across the bundle's leaves, as classified file records."""
    files = []
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            files.append((leaf, dg))
    return files


def _bundle_payload_kbs(model, bundle) -> List[str]:
    kbs = set()
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            k = kb_of(model.filename_for(dg))
            if k:
                kbs.add(k)
    return sorted(kbs)


def _bundle_payload_archs(model, bundle) -> List[str]:
    archs = set()
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            a = arch_of(model.filename_for(dg))
            if a:
                archs.add(a)
    return sorted(archs)


def _head_size(url: Optional[str]) -> Optional[int]:
    """Return the Content-Length of a FileLocation URL via HEAD, or None.

    File sizes are stable for a given cab snapshot, so this is reproducible.
    Used only where the Master lacks a size and the discriminator needs one
    (Server2016 LCU-vs-SSU). Fails closed (None) when offline.
    """
    if not url:
        return None
    try:
        req = urllib.request.Request(url, method="HEAD",
                                     headers={"User-Agent": "wsusscn2-analyzer/%s" % TOOL_VERSION})
        with urllib.request.urlopen(req, timeout=30) as r:
            cl = r.headers.get("Content-Length")
            return int(cl) if cl else None
    except Exception:
        return None


def _first_cab_digest(model, bundle) -> Optional[str]:
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            if (model.filename_for(dg) or "").lower().endswith(".cab"):
                return dg
    return None


def _make_2016_entry(model, bundle, digest, role, size) -> Dict[str, object]:
    fn = model.filename_for(digest)
    return {
        "kb": kb_of(fn),
        "bundleUpdateId": bundle.update_id,
        "creationDate": bundle.creation_date,
        "files": [{"fileName": fn, "digest": digest, "url": model.url_for(digest),
                   "role": role, "sizeBytes": size}],
    }


def resolve_server2016(model: "MasterModel") -> Dict[str, object]:
    """2016: LCU + STANDALONE SSU (the only OS with a separate SSU). Both are live
    Security bundles whose single SelfContained .cab is `windows10.0-kbNNN-x64.cab`
    — indistinguishable by name/title offline. They are separated by SIZE
    (SSU ~12.6MB << LCU ~1.8GB) via a HEAD on the FileLocation URL (per-snapshot
    stable -> reproducible). .NET 4.8 (ndp48) is out of scope (in-box .NET rides in
    the LCU)."""
    pg = OS_PRODUCT_GUID["Server2016"]
    bundles = model.live_bundles_for_product(pg, CLASSIFICATION["Security"])
    # Servicing candidates = .cab leaves WITHOUT an -ndp token (exclude .NET 4.8).
    cands = []
    for b in bundles:
        names = [model.filename_for(dg) for leaf in model.leaves_of(b) for dg in leaf.payload_digests]
        if not names or any(ndp_of(n) for n in names):
            continue
        if not any((n or "").lower().endswith(".cab") for n in names):
            continue
        cands.append(b)
    if not cands:
        return _os_result("Server2016", pg, None, None, None, None,
                          ["no 2016 servicing (LCU/SSU) bundles found"])
    newest_date = cands[0].creation_date[:10]      # bundles sorted newest-first; group by DATE
    newest = [b for b in cands if b.creation_date[:10] == newest_date]
    scored = []
    for b in newest:
        dg = _first_cab_digest(model, b)
        size = _head_size(model.url_for(dg)) if dg else None
        scored.append((b, dg, size))
    sizes_known = all(s is not None for _, _, s in scored)
    notes = ["2016 is the only generation with a standalone SSU line.",
             "In-box .NET (3.5/4.6.2/4.7.x) is serviced by the OS LCU; .NET 4.8 (ndp48) is out of scope."]
    if sizes_known and len(scored) >= 2:
        scored.sort(key=lambda t: t[2], reverse=True)
        lcu = _make_2016_entry(model, scored[0][0], scored[0][1], "LCU", scored[0][2])
        ssu = _make_2016_entry(model, scored[-1][0], scored[-1][1], "SSU", scored[-1][2])
        notes.append("LCU vs SSU separated by SelfContained .cab size via HEAD (SSU<<LCU); reproducible per snapshot.")
        return _os_result("Server2016", pg, lcu, ssu, None, None, notes)
    if sizes_known and len(scored) == 1:
        lcu = _make_2016_entry(model, scored[0][0], scored[0][1], "LCU", scored[0][2])
        notes.append("Only one servicing candidate found; treated as LCU.")
        return _os_result("Server2016", pg, lcu, None, None, None, notes)
    # Offline / HEAD unavailable: cannot separate LCU vs SSU reliably.
    cand_entry = {
        "candidates": [
            {"kb": kb_of(model.filename_for(dg)), "bundleUpdateId": b.update_id,
             "digest": dg, "url": model.url_for(dg), "fileName": model.filename_for(dg)}
            for b, dg, _ in scored
        ],
        "note": "OFFLINE: size probe unavailable; LCU/SSU not separated. Run online or provide sizes.",
    }
    res = _os_result("Server2016", pg, None, None, None, None,
                     notes + ["LCU/SSU undetermined (offline; needs size probe)."])
    res["lcuSsuCandidates"] = cand_entry
    return res


def resolve_server2019(model: "MasterModel") -> Dict[str, object]:
    """2019: LCU + .NET combined CU (in-box 4.7.2 -> the NON-NDP48 leaf is in
    scope; NDP48 is the add-on). SSU is embedded in the LCU (no standalone)."""
    pg = OS_PRODUCT_GUID["Server2019"]
    return _resolve_lcu_and_dotnet(model, "Server2019", pg, inbox_ndp="non-ndp48",
        notes=["No standalone SSU (embedded in the LCU leaf).",
               ".NET in-box = 4.7.2 -> in-box (non-NDP48) leaf in scope; NDP48 (4.8) is add-on."])


def resolve_server2022(model: "MasterModel") -> Dict[str, object]:
    """2022: LCU + .NET combined CU (in-box 4.8 -> NDP48 leaf in scope; NDP481 is
    the add-on — the INVERSE of 2019). SSU embedded. The SafeOS DU is a *separate*
    Dynamic Update (Product "Windows Safe OS Dynamic Update", Description
    "ComponentUpdate"), out of the offline-scan cab's classification scope, so the
    cab-native ``safeOsDu`` is null; it is acquired from the Microsoft Update
    Catalog (see ``safeOsDuCatalog`` / the ``safeos`` command)."""
    pg = OS_PRODUCT_GUID["Server2022"]
    res = _resolve_lcu_and_dotnet(model, "Server2022", pg, inbox_ndp="ndp48",
        notes=["No standalone SSU (embedded in the LCU leaf).",
               ".NET in-box = 4.8 -> NDP48 leaf in scope; NDP481 (4.8.1) is add-on (inverse of 2019).",
               "SafeOS DU (KB5094157-style) is a separate Dynamic Update (ComponentUpdate); it is "
               "out of the offline-scan cab's scope (security/rollup/servicepack only), so it is NOT "
               "in wsusscn2.cab. Acquire it from the Microsoft Update Catalog / WSUS — resolve the "
               "current one via the catalog resolver (safeOsDuCatalog / the 'safeos' command)."])
    res["safeOsDu"] = None
    res["safeOsDuStatus"] = "not-in-cab:available-from-catalog"
    return res


def resolve_server2025(model: "MasterModel") -> Dict[str, object]:
    """2025 (UUP): the LCU is a single multi-file UUP leaf carrying LCU + GA +
    checkpoint SSU + co-bundled SafeOS DU + LP-FoD + meta. .NET in-box = 4.8.1 ->
    the whole x64 .NET leaf (NDP481) is in scope (no add-on split)."""
    pg = OS_PRODUCT_GUID["Server2025"]
    bundles = _newest_live_security_bundle(model, pg)

    lcu_bundle = None
    net_bundle = None
    for b in bundles:
        kbs = _bundle_payload_kbs(model, b)
        archs = _bundle_payload_archs(model, b)
        files = [(leaf, dg) for leaf, dg in _lcu_leaf_files(model, b, None)]
        names = [(model.filename_for(dg) or "").lower() for _, dg in files]
        is_net = any("-ndp" in n for n in names)
        if is_net:
            if "x64" in archs and net_bundle is None:
                net_bundle = b
            continue
        # LCU bundle: x64, leaf carries a .msu whose KB == the bundle's cumulative KB.
        if "x64" in archs and any(n.endswith(".msu") for n in names) and lcu_bundle is None:
            lcu_bundle = b

    lcu = ssu = safeos = dotnet = None
    if lcu_bundle is not None:
        # Determine the LCU KB = the KB shared by the bundle's primary cumulative
        # .msu. Heuristic: among .msu files, the LCU KB is the one that also names
        # the bundle's newest payload; we take the .msu KB that is NOT the GA
        # baseline. Since both are .msu, classify by: the LCU .msu KB equals the
        # KB that the SSU/SafeOS share the month with -> we instead pick the LCU
        # as the .msu whose KB appears with the SafeOS DU; fallback: the higher KB.
        lcu_kb = _infer_lcu_kb(model, lcu_bundle)
        files = []
        for leaf, dg in _lcu_leaf_files(model, lcu_bundle, lcu_kb):
            files.append(_file_record(model, dg, parent_lcu_kb=lcu_kb))
        files.sort(key=lambda r: (r["role"], r["fileName"] or ""))
        lcu = {"kb": lcu_kb, "bundleUpdateId": lcu_bundle.update_id,
               "leafUpdateIds": sorted({l.update_id for l, _ in _lcu_leaf_files(model, lcu_bundle, None)}),
               "files": [f for f in files if f["role"] in ("LCU", "GA", "meta", "LP-FoD", "other")]}
        ssu_files = [f for f in files if f["role"] == "SSU"]
        safe_files = [f for f in files if f["role"] == "SafeOS-DU"]
        if ssu_files:
            ssu = {"model": "uup-checkpoint-in-lcu-leaf", "standalone": False,
                   "version": _ssu_version(ssu_files), "files": ssu_files}
        if safe_files:
            safeos = {"model": "co-bundled-in-lcu-leaf", "standalone": False,
                      "kb": kb_of(safe_files[0]["fileName"]), "files": safe_files}
    if net_bundle is not None:
        net_files = []
        for leaf in model.leaves_of(net_bundle):
            for dg in leaf.payload_digests:
                net_files.append(_file_record(model, dg, role=None))
        dotnet = {"kb": (sorted({kb_of(f["fileName"]) for f in net_files if kb_of(f["fileName"])}) or [None])[0],
                  "bundleUpdateId": net_bundle.update_id,
                  "scope": "whole-x64-leaf-in-scope (in-box 4.8.1, NDP481, no add-on split)",
                  "files": net_files}
    notes = ["UUP model: LCU is one multi-file leaf (LCU+GA+checkpoint SSU+SafeOS DU+LP-FoD+meta).",
             "SSU is a checkpoint INSIDE the LCU leaf (no standalone).",
             "SafeOS DU is co-bundled in the LCU leaf (no separate DU node).",
             ".NET in-box 4.8.1 -> whole x64 .NET leaf (NDP481) in scope; arm64 skipped."]
    return _os_result("Server2025", pg, lcu, ssu, dotnet, safeos, notes)


def _infer_lcu_kb(model, bundle) -> Optional[str]:
    """For a 2025 LCU bundle, infer the LCU KB. Among the leaf's .msu files there
    are exactly two: the LCU and the GA baseline. The LCU is the NEWER cumulative;
    the GA baseline KB is the lower/older. We pick the .msu KB that shares the
    leaf with the SafeOS DU + SSU (i.e. the cumulative). Durable rule: the LCU KB
    is the larger numeric KB among the two .msu files."""
    msu_kbs = []
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            fn = (model.filename_for(dg) or "").lower()
            if fn.endswith(".msu"):
                k = kb_of(fn)
                if k:
                    msu_kbs.append(int(k))
    if not msu_kbs:
        return None
    return str(max(msu_kbs))


def _ssu_version(ssu_files) -> Optional[str]:
    for f in ssu_files:
        m = re.search(r"ssu-([\d.]+)-x64", (f["fileName"] or "").lower())
        if m:
            return m.group(1)
    return None


def _resolve_lcu_and_dotnet(model, os_name, pg, inbox_ndp, notes) -> Dict[str, object]:
    """Shared shape for 2019/2022: an LCU bundle (single SelfContained .cab leaf)
    plus a combined .NET CU bundle with two leaves (in-box vs add-on NDP)."""
    bundles = _newest_live_security_bundle(model, pg)
    lcu = dotnet = None
    for b in bundles:
        archs = _bundle_payload_archs(model, b)
        if "x64" not in archs:
            continue
        names = []
        for leaf in model.leaves_of(b):
            for dg in leaf.payload_digests:
                names.append((model.filename_for(dg) or "").lower())
        is_net = any("-ndp" in n for n in names) or any("dotnet" in n or "ndp4" in n for n in names)
        if is_net and dotnet is None:
            dotnet = _dotnet_entry(model, b, inbox_ndp)
        elif (not is_net) and lcu is None:
            lcu = _make_entry(model, b, role_hint="LCU")
    return _os_result(os_name, pg, lcu, None, dotnet, None, notes)


def _dotnet_entry(model, bundle, inbox_ndp) -> Dict[str, object]:
    """Build a .NET entry, tagging each leaf in/out of scope per the OS rule.
    inbox_ndp: 'ndp48' (2022, NDP48 in scope) or 'non-ndp48' (2019, non-NDP48 in
    scope)."""
    files = []
    for leaf in model.leaves_of(bundle):
        for dg in leaf.payload_digests:
            fn = model.filename_for(dg)
            ndp = ndp_of(fn)
            if inbox_ndp == "ndp48":
                in_scope = (ndp == "48")
            else:  # non-ndp48 in scope (2019: in-box 3.5/4.7.2 leaf, no NDP token)
                in_scope = (ndp is None) or (ndp not in ("48", "481"))
            files.append({"fileName": fn, "digest": dg, "url": model.url_for(dg),
                          "ndp": ndp, "inScope": bool(in_scope)})
    files.sort(key=lambda r: (not r["inScope"], r["fileName"] or ""))
    in_scope_kbs = sorted({kb_of(f["fileName"]) for f in files if f["inScope"] and kb_of(f["fileName"])})
    all_kbs = sorted({kb_of(f["fileName"]) for f in files if kb_of(f["fileName"])})
    return {
        # Primary KB = the IN-SCOPE leaf (the payload that is actually applied),
        # NOT the combined-CU bundle KB. The bundle KB (e.g. KB5088862) is NOT in
        # the cab Master (no KBArticleID), so only leaf KBs are derivable offline.
        "kb": in_scope_kbs[0] if in_scope_kbs else (all_kbs[0] if all_kbs else None),
        "inScopeKb": in_scope_kbs[0] if in_scope_kbs else None,
        "allLeafKbs": all_kbs,
        "bundleUpdateId": bundle.update_id,
        "bundleKbNote": "the combined-CU bundle KB is not in the cab Master (no KBArticleID); only leaf KBs are derivable",
        "inScopeRule": ("NDP48 in scope" if inbox_ndp == "ndp48" else "non-NDP48 (in-box) in scope"),
        "files": files,
    }


def _make_entry(model, bundle, role_hint=None) -> Dict[str, object]:
    """Generic entry: the bundle's leaves and their classified files."""
    leaf_files = []
    leaf_ids = set()
    for leaf in model.leaves_of(bundle):
        leaf_ids.add(leaf.update_id)
        for dg in leaf.payload_digests:
            leaf_files.append(_file_record(model, dg, role=None))
    leaf_files.sort(key=lambda r: (r["role"], r["fileName"] or ""))
    return {
        "kb": (_bundle_payload_kbs(model, bundle) or [None])[0],
        "kbs": _bundle_payload_kbs(model, bundle),
        "bundleUpdateId": bundle.update_id,
        "leafUpdateIds": sorted(leaf_ids),
        "creationDate": bundle.creation_date,
        "files": leaf_files,
    }


def _os_result(os_name, pg, lcu, ssu, dotnet, safeos, notes) -> Dict[str, object]:
    return {
        "os": os_name,
        "productGuid": pg,
        "lcu": lcu,
        "ssu": ssu,
        "dotnet": dotnet,
        "safeOsDu": safeos,
        "notes": notes,
    }


RESOLVERS = {
    "Server2016": resolve_server2016,
    "Server2019": resolve_server2019,
    "Server2022": resolve_server2022,
    "Server2025": resolve_server2025,
}


# ===========================================================================
# Layer 6 — Verifier (match resolved digests against a SOAP oracle JSON)
# ===========================================================================
def _collect_digests(os_result: Dict[str, object]) -> Dict[str, set]:
    """Collect resolved digests per line for comparison."""
    out = {"lcu": set(), "ssu": set(), "dotnet": set(), "safeOsDu": set()}
    for key in out:
        entry = os_result.get(key)
        if not entry:
            continue
        for f in entry.get("files", []):
            if f.get("digest"):
                out[key].add(f["digest"])
    return out


def _oracle_digests(oracle: Dict[str, object]) -> Dict[str, set]:
    """Collect oracle digests per line from BOTH the first-class fields (Ssu /
    SafeOsDu) AND CurrentSetLeaves (LCU / SSU / NET)."""
    out = {"lcu": set(), "ssu": set(), "dotnet": set(), "safeOsDu": set()}
    ssu = oracle.get("Ssu")
    if ssu:
        out["ssu"] |= {f["Digest"] for f in ssu.get("Files", []) if f.get("Digest")}
    sd = oracle.get("SafeOsDu")
    if sd:
        out["safeOsDu"] |= {f["Digest"] for f in sd.get("Files", []) if f.get("Digest")}
    line_map = {"LCU": "lcu", "SSU": "ssu", "NET": "dotnet"}
    for leaf in (oracle.get("CurrentSetLeaves") or []):
        key = line_map.get(leaf.get("Line"))
        if not key:
            continue
        for f in leaf.get("Files", []):
            if f.get("Digest"):
                out[key].add(f["Digest"])
    return out


def verify_against_oracle(os_result: Dict[str, object], oracle: Dict[str, object]) -> Dict[str, object]:
    """Compare resolved digests vs the SOAP oracle, per line.

    The cab is the WSUS *offline* catalog: per leaf it carries only the
    SelfContained payload, while the SOAP oracle additionally lists online-only
    express/psf deltas. So the correct relation is **cab digests ⊆ oracle digests**
    (non-empty). A line passes when every cab-resolved digest is present in the
    oracle's digest set for that line.
    """
    resolved = _collect_digests(os_result)
    expected = _oracle_digests(oracle)
    report = {}
    for line in ("lcu", "ssu", "dotnet", "safeOsDu"):
        exp = expected[line]
        got = resolved[line]
        if not exp and not got:
            report[line] = {"checked": False, "reason": "neither oracle nor cab has digests for this line"}
            continue
        if not exp:
            report[line] = {"checked": False, "reason": "oracle has no digests for this line",
                            "cabResolved": sorted(got)}
            continue
        report[line] = {
            "checked": True,
            "cabResolved": sorted(got),
            "oracleExpected": sorted(exp),
            "matched": sorted(got & exp),
            "cabOnly": sorted(got - exp),          # should be empty (cab ⊆ oracle)
            "oracleOnly": sorted(exp - got),       # online-only express/psf (expected, informational)
            "pass": bool(got) and got.issubset(exp),
        }
    report["overall"] = all(v.get("pass", True) for v in report.values()
                            if isinstance(v, dict) and v.get("checked"))
    return report


# ===========================================================================
# Output assembly
# ===========================================================================
def build_provenance(cab_info: Dict[str, object], model: "MasterModel") -> Dict[str, object]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "toolVersion": TOOL_VERSION,
        "generatedUtc": _utcnow_iso(),
        "source": {
            "url": cab_info.get("url"),
            "cabSha256": cab_info.get("sha256"),
            "cabSize": cab_info.get("size"),
            "cabDownloadedUtc": cab_info.get("downloaded_utc"),
            "masterSha256": model.master_sha256,
        },
        "masterStats": {
            "updates": model.update_count,
            "fileLocations": model.filelocation_count,
        },
    }


def analyze(cab_path: str, cab_info: Dict[str, object], workdir: str,
            oses: Iterable[str], safeos_catalog: bool = False,
            safeos_arch: str = "x64", safeos_verify: bool = False) -> Dict[str, object]:
    extractor = Extractor(cab_path, workdir)
    master = extractor.extract_master()
    model = MasterModel.from_master(master)
    result = {
        "provenance": build_provenance(cab_info, model),
        "results": {},
    }
    for os_name in oses:
        os_result = RESOLVERS[os_name](model)
        if safeos_catalog:
            enrich_with_catalog_safeos(os_result, os_name, arch=safeos_arch,
                                       verify_download=safeos_verify)
        result["results"][os_name] = os_result
    return result


# ===========================================================================
# Human-readable summary (secondary)
# ===========================================================================
def render_summary(report: Dict[str, object]) -> str:
    lines = []
    prov = report["provenance"]
    lines.append("wsusscn2.cab analysis  (tool %s, schema %s)" % (prov["toolVersion"], prov["schemaVersion"]))
    lines.append("  cab sha256 : %s" % prov["source"]["cabSha256"])
    lines.append("  generated  : %s" % prov["generatedUtc"])
    lines.append("  master     : %d updates / %d file-locations" %
                 (prov["masterStats"]["updates"], prov["masterStats"]["fileLocations"]))
    lines.append("")
    for os_name, r in report["results"].items():
        lines.append("== %s ==" % os_name)
        for line_key, label in (("lcu", "LCU"), ("ssu", "SSU"), ("dotnet", ".NET"), ("safeOsDu", "SafeOS DU")):
            entry = r.get(line_key)
            if not entry:
                status = r.get("safeOsDuStatus") if line_key == "safeOsDu" else None
                lines.append("  %-9s : %s" % (label, status or "(none / N/A)"))
                continue
            kb = entry.get("kb") or entry.get("version") or "?"
            nfiles = len(entry.get("files", []))
            lines.append("  %-9s : KB%s  (%d file%s)" % (label, kb, nfiles, "" if nfiles == 1 else "s"))
        cat = r.get("safeOsDuCatalog")
        if cat:
            lines.append("  %-9s : KB%s  (catalog: %s)" %
                         ("SafeOS@Cat", cat.get("kb") or "?", cat.get("fileName") or cat.get("updateId") or "?"))
        lines.append("")
    return "\n".join(lines)


# ===========================================================================
# SafeOS Dynamic Update resolver  (Microsoft Update Catalog)
# ---------------------------------------------------------------------------
# The SafeOS DU (WinRE) is a *separate* Dynamic Update (Product
# "Windows Safe OS Dynamic Update", Description "ComponentUpdate") and is
# therefore OUT OF SCOPE of the offline-scan wsusscn2.cab (which carries only
# security/rollup/servicepack classifications). It is published to the
# Microsoft Update Catalog / WSUS. This resolver derives the *current* SafeOS
# DU for a given Server generation from OS-limited seed only (OS -> version
# token); KB numbers are never hardcoded. Verified end-to-end (catalog file ==
# SOAP-oracle file by SHA1/SHA256) for Server 2022 (KB5094157) and Server 2025
# (KB5094150).
# ===========================================================================
CATALOG_SEARCH_URL = "https://www.catalog.update.microsoft.com/Search.aspx"
CATALOG_DOWNLOAD_URL = "https://www.catalog.update.microsoft.com/DownloadDialog.aspx"

# OS-limited base information: the only per-OS seed required. The catalog titles
# Server generations by their "Microsoft server operating system version" token
# (also derivable from the build: 20348 -> 21H2, 26100 -> 24H2).
SAFEOS_OS_TOKEN = {
    "Server2022": "21H2",
    "Server2025": "24H2",
}
# The discriminator phrase that marks a SafeOS DU row regardless of OS:
#   * 2025 (modern naming): the TITLE itself contains "Safe OS Dynamic Update".
#   * 2022 (classic naming): the TITLE is just "Dynamic Update ..." (identical to
#     the Setup DU), so the row is disambiguated by the PRODUCTS column, which
#     carries "Windows Safe OS Dynamic Update" (a pure Setup DU does not).
_SAFEOS_TITLE_MARK = "safe os dynamic update"
_SAFEOS_PRODUCT_MARK = "windows safe os dynamic update"

_CAT_LINK_RE = re.compile(r"id=['\"]([0-9a-f-]{36})_link['\"][^>]*>(.*?)</a>", re.S | re.I)


def _http_get_text(url: str, timeout: int = 60) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (wsusscn2-analyzer/%s)" % TOOL_VERSION})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def _http_post_text(url: str, body: str, timeout: int = 60) -> str:
    req = urllib.request.Request(
        url, data=body.encode("utf-8"),
        headers={"User-Agent": "Mozilla/5.0 (wsusscn2-analyzer/%s)" % TOOL_VERSION,
                 "Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def _strip_tags(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s)).strip()


def parse_catalog_rows(html: str) -> List[Dict[str, object]]:
    """Parse a Microsoft Update Catalog Search.aspx result page into rows.

    Pure function (no network) so it is unit-testable against a saved fixture.
    Each row: {uid, title, products, lastUpdated, sizeText, sizeBytes}.
    """
    rows: List[Dict[str, object]] = []
    for m in _CAT_LINK_RE.finditer(html):
        uid = m.group(1)
        title = _strip_tags(m.group(2))

        def _cell(col: int) -> str:
            cm = re.search(r'id="%s_C%d_R\d+"[^>]*>(.*?)</td>' % (re.escape(uid), col), html, re.S | re.I)
            return _strip_tags(cm.group(1)) if cm else ""

        size_text = _cell(6)
        msize = re.search(r"(\d+)\s*$", size_text)
        rows.append({
            "uid": uid,
            "title": title,
            "products": _cell(2),
            "classification": _cell(3),
            "lastUpdated": _cell(4),
            "sizeText": size_text,
            "sizeBytes": int(msize.group(1)) if msize else None,
        })
    return rows


def _row_sort_key(row: Dict[str, object]):
    """Newest-first key from the YYYY-MM in the title (primary) then LastUpdated."""
    mt = re.match(r"\s*(\d{4})-(\d{2})", str(row.get("title", "")))
    ym = (int(mt.group(1)), int(mt.group(2))) if mt else (0, 0)
    md = re.search(r"(\d+)/(\d+)/(\d+)", str(row.get("lastUpdated", "")))
    dt = (int(md.group(3)), int(md.group(1)), int(md.group(2))) if md else (0, 0, 0)
    return (ym, dt)


def select_safeos_du_row(rows: List[Dict[str, object]], token: str,
                         arch: str = "x64") -> Optional[Dict[str, object]]:
    """Pick the newest SafeOS DU row for a version token + architecture.

    Pure function. Applies the per-OS discriminator (title OR products), the
    version-token filter, and the architecture filter, then returns the newest.
    """
    cand = []
    for r in rows:
        title_l = str(r.get("title", "")).lower()
        prod_l = str(r.get("products", "")).lower()
        is_safeos = (_SAFEOS_TITLE_MARK in title_l) or (_SAFEOS_PRODUCT_MARK in prod_l)
        arch_ok = (("%s-based" % arch) in title_l) or (arch.lower() in title_l)
        token_ok = token.lower() in title_l
        if is_safeos and arch_ok and token_ok:
            cand.append(r)
    if not cand:
        return None
    cand.sort(key=_row_sort_key, reverse=True)
    return cand[0]


def catalog_resolve_download_urls(uid: str, timeout: int = 60) -> List[str]:
    """POST to DownloadDialog.aspx and return the .cab/.msu download URLs."""
    body = ('updateIDs=[{"size":0,"languages":"","uidInfo":"%s","updateID":"%s"}]'
            "&updateIDsBlockedForImport=&wsusApiPresent=&contentImport="
            "&sku=&serverName=&ssl=&portNumber=&version=") % (uid, uid)
    html = _http_post_text(CATALOG_DOWNLOAD_URL, body, timeout=timeout)
    return sorted(set(re.findall(r"https?://[^'\"]+\.(?:cab|msu)", html)))


def _b64_digests(path: str) -> Tuple[str, str]:
    import base64
    with open(path, "rb") as fh:
        data = fh.read()
    return (base64.b64encode(hashlib.sha1(data).digest()).decode(),
            base64.b64encode(hashlib.sha256(data).digest()).decode())


def resolve_safeos_du_from_catalog(os_name: str, arch: str = "x64",
                                   verify_download: bool = False,
                                   timeout: int = 60) -> Optional[Dict[str, object]]:
    """Derive the current SafeOS DU for a Server generation from the Catalog.

    Input is OS-limited (os_name -> version token). Returns a normalized entry
    or None if unavailable/offline. Network-bound (Catalog), so callers gate it
    behind an explicit opt-in. ``verify_download`` additionally downloads the
    payload and attaches base64 SHA1/SHA256 (matching the SOAP-oracle format).
    """
    token = SAFEOS_OS_TOKEN.get(os_name)
    if not token:
        return None
    query = "Safe OS Dynamic Update Microsoft server operating system version %s" % token
    try:
        url = CATALOG_SEARCH_URL + "?q=" + urllib.parse.quote(query)
        html = _http_get_text(url, timeout=timeout)
    except Exception:
        return None
    row = select_safeos_du_row(parse_catalog_rows(html), token, arch)
    if not row:
        return None
    entry: Dict[str, object] = {
        "source": "microsoft-update-catalog",
        "model": "standalone-dynamic-update",
        "standalone": True,
        "kb": kb_of(row["title"]),
        "updateId": row["uid"],
        "title": row["title"],
        "products": row["products"],
        "lastUpdated": row["lastUpdated"],
        "arch": arch,
        "osVersionToken": token,
        "sizeBytes": row.get("sizeBytes"),
        "url": None,
        "fileName": None,
    }
    try:
        urls = catalog_resolve_download_urls(str(row["uid"]), timeout=timeout)
        # Prefer the x64 .cab payload matching the KB.
        kb = (entry["kb"] or "").lower()
        pick = next((u for u in urls if kb and kb in u.lower() and arch.lower() in u.lower()), None)
        pick = pick or (urls[0] if urls else None)
        if pick:
            entry["url"] = pick
            entry["fileName"] = pick.rsplit("/", 1)[-1]
    except Exception:
        pass
    if verify_download and entry.get("url"):
        try:
            tmp = os.path.join(tempfile.gettempdir(), "safeos-" + str(entry["kb"]) + ".cab")
            urllib.request.urlretrieve(entry["url"], tmp)
            sha1b64, sha256b64 = _b64_digests(tmp)
            entry["sha1B64"] = sha1b64
            entry["sha256B64"] = sha256b64
            entry["sizeBytes"] = os.path.getsize(tmp)
            entry["verified"] = True
            os.remove(tmp)
        except Exception:
            entry["verified"] = False
    return entry


def enrich_with_catalog_safeos(os_result: Dict[str, object], os_name: str,
                               arch: str = "x64", verify_download: bool = False) -> None:
    """Attach a Catalog-derived SafeOS DU (``safeOsDuCatalog``) in place.

    Only meaningful for generations that have a SafeOS DU (2022 / 2025). For
    2022 the cab-native ``safeOsDu`` stays null (out of cab scope) but the
    Catalog entry provides the real acquisition path; for 2025 it cross-refs
    the co-bundled cab leaf.
    """
    if os_name not in SAFEOS_OS_TOKEN:
        return
    cat = resolve_safeos_du_from_catalog(os_name, arch=arch, verify_download=verify_download)
    os_result["safeOsDuCatalog"] = cat
    if os_name == "Server2022" and cat is not None:
        os_result["safeOsDuStatus"] = "not-in-cab:resolved-from-catalog"


# ===========================================================================
# CLI
# ===========================================================================
def _default_paths(workroot: str):
    return os.path.join(workroot, "wsusscn2.cab"), os.path.join(workroot, "_extract")


def cmd_download(args) -> int:
    cab_path, _ = _default_paths(args.workdir)
    cab_path = args.output or cab_path
    info = Downloader(args.url).fetch(cab_path, force=args.force)
    print(json.dumps(info, ensure_ascii=False, indent=2))
    return 0


def cmd_analyze(args) -> int:
    cab_path, extract_dir = _default_paths(args.workdir)
    if args.cab:
        cab_path = args.cab
        sha, size = Downloader._hash_file(cab_path)
        info = {"path": os.path.abspath(cab_path), "url": None, "sha256": sha,
                "size": size, "cached": True, "downloaded_utc": None}
    else:
        info = Downloader(args.url).fetch(cab_path, force=args.force)
    oses = args.os or SUPPORTED_OSES
    report = analyze(cab_path, info, extract_dir, oses,
                     safeos_catalog=getattr(args, "safeos_catalog", False),
                     safeos_arch=getattr(args, "safeos_arch", "x64"),
                     safeos_verify=getattr(args, "safeos_verify", False))
    _emit(report, args)
    return 0


def cmd_resolve(args) -> int:
    args.os = [args.os_name]
    return cmd_analyze(args)


def cmd_verify(args) -> int:
    cab_path, extract_dir = _default_paths(args.workdir)
    if args.cab:
        cab_path = args.cab
        sha, size = Downloader._hash_file(cab_path)
        info = {"path": os.path.abspath(cab_path), "url": None, "sha256": sha,
                "size": size, "cached": True, "downloaded_utc": None}
    else:
        info = Downloader(args.url).fetch(cab_path, force=args.force)
    os_name = args.os_name
    report = analyze(cab_path, info, extract_dir, [os_name])
    oracle = json.load(open(args.oracle, encoding="utf-8"))
    vr = verify_against_oracle(report["results"][os_name], oracle)
    out = {"os": os_name, "provenance": report["provenance"], "verification": vr}
    print(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=False))
    return 0 if vr.get("overall") else 2


def cmd_safeos(args) -> int:
    """Resolve the current SafeOS DU for one OS straight from the Microsoft
    Update Catalog — no cab required (OS-limited seed only)."""
    entry = resolve_safeos_du_from_catalog(args.os_name, arch=args.arch,
                                           verify_download=args.verify_download)
    out = {
        "tool": "wsusscn2_analyzer",
        "toolVersion": TOOL_VERSION,
        "schemaVersion": SCHEMA_VERSION,
        "generatedUtc": _utcnow_iso(),
        "os": args.os_name,
        "safeOsDuCatalog": entry,
    }
    text = json.dumps(out, ensure_ascii=False, indent=2)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        sys.stderr.write("written: %s\n" % args.out)
    else:
        print(text)
    return 0 if entry else 3


def _emit(report: Dict[str, object], args) -> None:
    if args.summary:
        sys.stderr.write(render_summary(report) + "\n")
    text = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        sys.stderr.write("written: %s\n" % args.out)
    else:
        print(text)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="wsusscn2_analyzer",
        description="Download and analyze Microsoft's wsusscn2.cab; resolve per-OS latest patch sets.")
    p.add_argument("--workdir", default=os.path.join(tempfile.gettempdir(), "wsusscn2-work"),
                   help="working directory for cab + extraction (default: temp)")
    p.add_argument("--url", default=WSUSSCN2_URL, help="wsusscn2.cab source URL")
    sub = p.add_subparsers(dest="command", required=True)

    sp = sub.add_parser("download", help="download wsusscn2.cab and print its provenance")
    sp.add_argument("-o", "--output", help="destination path for the cab")
    sp.add_argument("--force", action="store_true", help="re-download even if cached")
    sp.set_defaults(func=cmd_download)

    sp = sub.add_parser("analyze", help="resolve all (or selected) OSes -> normalized JSON")
    sp.add_argument("--cab", help="use a local cab instead of downloading")
    sp.add_argument("--os", action="append", choices=SUPPORTED_OSES,
                    help="restrict to one OS (repeatable); default = all")
    sp.add_argument("-o", "--out", help="write JSON to file (default: stdout)")
    sp.add_argument("--summary", action="store_true", help="also print a human summary to stderr")
    sp.add_argument("--force", action="store_true", help="re-download even if cached")
    sp.add_argument("--safeos-catalog", dest="safeos_catalog", action="store_true",
                    help="ALSO resolve the SafeOS DU from the Microsoft Update Catalog "
                         "(network; adds 'safeOsDuCatalog' for 2022/2025)")
    sp.add_argument("--safeos-arch", dest="safeos_arch", default="x64",
                    help="architecture for the SafeOS DU catalog lookup (default: x64)")
    sp.add_argument("--safeos-verify", dest="safeos_verify", action="store_true",
                    help="download the SafeOS DU payload and attach SHA1/SHA256 (base64)")
    sp.set_defaults(func=cmd_analyze)

    sp = sub.add_parser("resolve", help="resolve a single OS -> normalized JSON")
    sp.add_argument("os_name", choices=SUPPORTED_OSES)
    sp.add_argument("--cab", help="use a local cab instead of downloading")
    sp.add_argument("-o", "--out", help="write JSON to file (default: stdout)")
    sp.add_argument("--summary", action="store_true", help="also print a human summary to stderr")
    sp.add_argument("--force", action="store_true", help="re-download even if cached")
    sp.add_argument("--safeos-catalog", dest="safeos_catalog", action="store_true",
                    help="ALSO resolve the SafeOS DU from the Microsoft Update Catalog "
                         "(network; adds 'safeOsDuCatalog' for 2022/2025)")
    sp.add_argument("--safeos-arch", dest="safeos_arch", default="x64",
                    help="architecture for the SafeOS DU catalog lookup (default: x64)")
    sp.add_argument("--safeos-verify", dest="safeos_verify", action="store_true",
                    help="download the SafeOS DU payload and attach SHA1/SHA256 (base64)")
    sp.set_defaults(func=cmd_resolve)

    sp = sub.add_parser("safeos", help="resolve the current SafeOS DU for one OS from the "
                                       "Microsoft Update Catalog (no cab required)")
    sp.add_argument("os_name", choices=sorted(SAFEOS_OS_TOKEN.keys()))
    sp.add_argument("--arch", default="x64", help="architecture (default: x64)")
    sp.add_argument("--verify-download", dest="verify_download", action="store_true",
                    help="download the payload and attach SHA1/SHA256 (base64)")
    sp.add_argument("-o", "--out", help="write JSON to file (default: stdout)")
    sp.set_defaults(func=cmd_safeos)

    sp = sub.add_parser("verify", help="resolve one OS and check digests against a SOAP oracle JSON")
    sp.add_argument("os_name", choices=SUPPORTED_OSES)
    sp.add_argument("--oracle", required=True, help="path to the SOAP oracle JSON (ServerXXXX.json)")
    sp.add_argument("--cab", help="use a local cab instead of downloading")
    sp.add_argument("--force", action="store_true", help="re-download even if cached")
    sp.set_defaults(func=cmd_verify)

    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())

```

## Appendix E — `Resolve-Wsusscn2PatchSet.ps1`（オフライン cab クロスチェック, PowerShell）

**役割:** オフライン依存クロスチェック `[B]`、Appendix D の PowerShell 移植。ストリーミング `XmlReader`；7-Zip 抽出；2016 の LCU-vs-SSU 判別のための HEAD サイズプローブ。

```powershell
#Requires -Version 7.0
<#
.SYNOPSIS
    Offline Windows Server patch-set analyzer for wsusscn2.cab (PowerShell port).

.DESCRIPTION
    Downloads Microsoft's offline-scan catalog (wsusscn2.cab), parses it, and
    resolves -- per Windows Server generation -- the current latest patch set
    (LCU / SSU / .NET / SafeOS Dynamic Update) with exact payload digests and
    download URLs.

    This is a feature-parity PowerShell port of wsusscn2_analyzer.py and emits the
    SAME normalized JSON schema (wsusscn2-analysis/1.0), so the two are
    interoperable.

    Design goals:
      * Reproducible: same input cab -> stable JSON, stamped with the cab SHA-256.
      * Machine-readable first: normalized JSON is primary; -AsJson:$false returns
        PowerShell objects for pipeline use; -Summary prints a human digest.
      * Per-OS resolvers (2016/2019/2022/2025), deliberately independent.
      * Grounded constants: product/classification GUIDs and the .NET in-scope
        rule are explicit. KB numbers are NEVER hardcoded -- the newest live
        entity is selected from the cab on every run.

    Dependencies: PowerShell 7+, and one cab extractor on PATH. Preference order:
    7-Zip (7z/7za) -> expand.exe (Windows) -> cabextract.

.PARAMETER Action
    Download | Analyze | Resolve | Verify

.PARAMETER Os
    Target OS for Resolve/Verify (or to restrict Analyze): Server2016 | Server2019
    | Server2022 | Server2025.

.PARAMETER Cab
    Use a local wsusscn2.cab instead of downloading.

.PARAMETER OraclePath
    Path to a SOAP oracle JSON (ServerXXXX.json) for Verify.

.PARAMETER OutFile
    Write JSON output to a file (default: stdout).

.PARAMETER MasterXml
    Advanced: skip extraction and parse an already-extracted Master package.xml
    directly (useful on platforms without a cab extractor).

.EXAMPLE
    ./Resolve-Wsusscn2PatchSet.ps1 -Action Analyze -Cab .\wsusscn2.cab -Summary -OutFile result.json

.EXAMPLE
    ./Resolve-Wsusscn2PatchSet.ps1 -Action Verify -Os Server2025 -Cab .\wsusscn2.cab -OraclePath .\Server2025.json

.NOTES
    License: MIT.
#>
[CmdletBinding()]
param(
    [ValidateSet('Download', 'Analyze', 'Resolve', 'Verify', 'SafeOsDu')]
    [string]$Action,

    [ValidateSet('Server2016', 'Server2019', 'Server2022', 'Server2025')]
    [string]$Os,

    [string]$Cab,
    [string]$OraclePath,
    [string]$OutFile,
    [string]$MasterXml,
    [string]$Url = 'http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab',
    [string]$WorkDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'wsusscn2-work'),
    [switch]$Summary,
    [switch]$Force,
    [switch]$SafeOsFromCatalog,
    [string]$SafeOsArch = 'x64',
    [switch]$SafeOsVerify,
    [bool]$AsJson = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Versioning & invariants
# ---------------------------------------------------------------------------
$script:ToolVersion   = '1.0.0'
$script:SchemaVersion = 'wsusscn2-analysis/1.1'
$script:NS            = 'http://schemas.microsoft.com/msus/2004/02/OfflineSync'

# Update-classification GUIDs (stable WSUS taxonomy).
$script:Classification = @{
    Security      = '0fa1201d-4330-4fa8-8ae9-b877473b6441'
    UpdateRollups = '28bc880e-0592-4cbf-8f95-c79b17911d5f'
    ServicePacks  = '68c5b0a3-d1a6-4553-ae49-01d3a7827828'
    Critical      = 'e6cf1350-c01b-414d-a61f-263d14d133b4'
    Updates       = 'cd5ffd1e-e932-4e3a-bf74-18bf0b1bbd83'
}

# Per-OS product-category GUIDs, pinned empirically (validated vs the SOAP oracle).
# NOTE 2016's full GUID is ...-c6cd-... (a wrong -c466- suffix silently yields 0
# matches), so these full UUIDs matter.
$script:OsProductGuid = [ordered]@{
    Server2016 = '569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5'
    Server2019 = 'f702a48c-919b-45d6-9aef-ca4248d50397'
    Server2022 = '71718f13-7324-4b0f-8f9e-2ca9dc978e53'
    Server2025 = 'b256987d-4693-4c87-955d-dbb9341205eb'
}
$script:SupportedOses = @($script:OsProductGuid.Keys)

function Get-UtcNowIso { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

# ===========================================================================
# File-name classification helpers
# ===========================================================================
function Get-KbFromName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    if ($Name -match '(?i)kb(\d+)') { return $Matches[1] }
    return $null
}

function Get-ArchFromName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    if ($Name -match '(?i)-(x64|x86|arm64)') { return $Matches[1].ToLower() }
    return $null
}

function Get-NdpFromName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $null }
    if ($Name -match '(?i)-ndp(48[01]?)') { return $Matches[1] }
    return $null
}

function Get-UupFileRole {
    <#
      Classify one file of a 2025-style UUP LCU leaf by its filename.
      Roles: SSU / SafeOS-DU / LCU / GA / NET / LP-FoD / meta / other.
      LCU vs GA is decided durably by KB equality with the parent bundle KB
      (no hardcoded KB).
    #>
    param([string]$FileName, [string]$ParentLcuKb)
    if ([string]::IsNullOrEmpty($FileName)) { return 'unknown-no-url' }
    $f = $FileName.ToLower()
    if ($f.StartsWith('ssu-')) { return 'SSU' }
    if ($f -match '(?i)windows1[01]\.0-kb\d+-x64(-baseless)?[._].*\.(cab|psf)$' -or
        $f -match '(?i)windows1[01]\.0-kb\d+-x64\.cab$') { return 'SafeOS-DU' }
    if ($f -match '(?i)-ndp48[01]?') { return 'NET' }
    if ($f.EndsWith('.msu')) {
        $k = Get-KbFromName $f
        if ($ParentLcuKb -and $k -eq $ParentLcuKb) { return 'LCU' }
        return 'GA'
    }
    if ($f.EndsWith('.wim')) { return 'LP-FoD' }
    if ($f -match 'metadata|compdb|desktopdeployment') { return 'meta' }
    return 'other'
}

# ===========================================================================
# Layer 1 - Downloader
# ===========================================================================
function Get-FileSha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try { $hash = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
        return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLower())
    } finally { $sha.Dispose() }
}

function Invoke-Wsusscn2Download {
    <#
      Fetch wsusscn2.cab from the official URL with streaming SHA-256.
      Content-addressed by SHA-256 so downstream artifacts tie to exact bytes.
    #>
    param([string]$Url, [string]$DestPath, [switch]$Force)

    if ((Test-Path -LiteralPath $DestPath) -and -not $Force) {
        $size = (Get-Item -LiteralPath $DestPath).Length
        return [ordered]@{
            path = (Resolve-Path -LiteralPath $DestPath).Path
            url = $Url; sha256 = (Get-FileSha256 $DestPath); size = $size
            cached = $true; downloaded_utc = $null
        }
    }
    $dir = Split-Path -LiteralPath $DestPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $client.DefaultRequestHeaders.Add('User-Agent', "wsusscn2-analyzer/$script:ToolVersion")
    $tmp = "$DestPath.part"
    $total = 0L
    try {
        $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $resp.EnsureSuccessStatusCode() | Out-Null
        $declared = 0L
        if ($resp.Content.Headers.ContentLength) { $declared = [long]$resp.Content.Headers.ContentLength }
        $stream = $resp.Content.ReadAsStream()
        $out = [System.IO.File]::Create($tmp)
        try {
            $buffer = New-Object byte[] (1MB)
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $out.Write($buffer, 0, $read)
                $sha.TransformBlock($buffer, 0, $read, $null, 0) | Out-Null
                $total += $read
                if ($declared -gt 0) {
                    Write-Progress -Activity 'Downloading wsusscn2.cab' `
                        -Status ("{0:N0}/{1:N0} bytes" -f $total, $declared) `
                        -PercentComplete ([int](100.0 * $total / $declared))
                }
            }
        } finally { $out.Dispose(); $stream.Dispose() }
        $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
        $hashHex = ([System.BitConverter]::ToString($sha.Hash).Replace('-', '').ToLower())
    } finally { $client.Dispose(); $sha.Dispose(); Write-Progress -Activity 'Downloading wsusscn2.cab' -Completed }

    Move-Item -LiteralPath $tmp -Destination $DestPath -Force
    return [ordered]@{
        path = (Resolve-Path -LiteralPath $DestPath).Path
        url = $Url; sha256 = $hashHex; size = $total
        cached = $false; downloaded_utc = (Get-UtcNowIso)
    }
}

# ===========================================================================
# Layer 2 - Extractor (7-Zip preferred -> expand.exe -> cabextract)
# ===========================================================================
function Resolve-CabExtractor {
    <# Return a descriptor for the first available cab extractor. #>
    foreach ($name in '7z', '7za') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return [pscustomobject]@{ Kind = '7zip'; Exe = $cmd.Source } }
    }
    $expand = Get-Command 'expand.exe' -ErrorAction SilentlyContinue
    if (-not $expand) { $expand = Get-Command 'expand' -ErrorAction SilentlyContinue }
    if ($expand) { return [pscustomobject]@{ Kind = 'expand'; Exe = $expand.Source } }
    $cabx = Get-Command 'cabextract' -ErrorAction SilentlyContinue
    if ($cabx) { return [pscustomobject]@{ Kind = 'cabextract'; Exe = $cabx.Source } }
    throw "No cab extractor found. Install 7-Zip (7z), or use Windows expand.exe, or cabextract."
}

function Invoke-ExtractMember {
    <# Extract a single named member from $CabPath into $OutDir using $Extractor. #>
    param($Extractor, [string]$CabPath, [string]$Member, [string]$OutDir)
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    switch ($Extractor.Kind) {
        '7zip' {
            & $Extractor.Exe e -y "-o$OutDir" $CabPath $Member *> $null
        }
        'expand' {
            # expand.exe extracts a specific file: expand <cab> -F:<member> <outdir>
            & $Extractor.Exe $CabPath "-F:$Member" $OutDir *> $null
        }
        'cabextract' {
            & $Extractor.Exe -q -F $Member -d $OutDir $CabPath *> $null
        }
    }
    $out = Join-Path $OutDir (Split-Path $Member -Leaf)
    if (-not (Test-Path -LiteralPath $out)) {
        throw "Failed to extract '$Member' from '$CabPath' with $($Extractor.Kind)."
    }
    return $out
}

function Expand-Wsusscn2Cab {
    <# wsusscn2.cab -> package.cab -> package.xml (the Master). Returns its path. #>
    param([string]$CabPath, [string]$WorkDir)
    $extractor = Resolve-CabExtractor
    Write-Verbose "Using cab extractor: $($extractor.Kind) ($($extractor.Exe))"
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    [void](Invoke-ExtractMember $extractor $CabPath 'index.xml' $WorkDir)
    $pkgCab = Invoke-ExtractMember $extractor $CabPath 'package.cab' $WorkDir
    $master = Invoke-ExtractMember $extractor $pkgCab 'package.xml' $WorkDir
    return $master
}

# ===========================================================================
# Layer 3 - Parser (streaming XmlReader, memory-safe for the 114MB Master)
# ===========================================================================
function Read-UpdateSubtree {
    <# Positioned on an <Update> start element; extract a normalized record. #>
    param([System.Xml.XmlReader]$Reader)
    $ridRaw   = $Reader.GetAttribute('RevisionId')
    $rid      = if ($ridRaw) { [int]$ridRaw } else { 0 }
    $uid      = $Reader.GetAttribute('UpdateId')
    $cd       = $Reader.GetAttribute('CreationDate')
    $isBundle = ($Reader.GetAttribute('IsBundle') -eq 'true')
    $isLeaf   = ($Reader.GetAttribute('IsLeaf') -eq 'true')

    $prods   = [System.Collections.Generic.List[string]]::new()
    $classes = [System.Collections.Generic.List[string]]::new()
    $digs    = [System.Collections.Generic.List[string]]::new()
    $parents = [System.Collections.Generic.List[int]]::new()
    $supN    = 0
    $section = $null

    if (-not $Reader.IsEmptyElement) {
        $sub = $Reader.ReadSubtree()
        [void]$sub.Read()    # consume the <Update> start within the subtree
        while ($sub.Read()) {
            if ($sub.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                switch ($sub.LocalName) {
                    'Categories'   { $section = 'cat' }
                    'PayloadFiles' { $section = 'pf' }
                    'SupersededBy' { $section = 'sup' }
                    'BundledBy'    { $section = 'bb' }
                    'Category' {
                        $t = $sub.GetAttribute('Type'); $id = $sub.GetAttribute('Id')
                        if ($t -eq 'Product') { $prods.Add($id) }
                        elseif ($t -eq 'UpdateClassification') { $classes.Add($id) }
                    }
                    'File' { if ($section -eq 'pf') { $id = $sub.GetAttribute('Id'); if ($id) { $digs.Add($id) } } }
                    'Revision' {
                        if ($section -eq 'sup') { $supN++ }
                        elseif ($section -eq 'bb') { $rv = $sub.GetAttribute('Id'); if ($rv) { $parents.Add([int]$rv) } }
                    }
                }
            }
            elseif ($sub.NodeType -eq [System.Xml.XmlNodeType]::EndElement) {
                if ($sub.LocalName -in @('Categories', 'PayloadFiles', 'SupersededBy', 'BundledBy')) { $section = $null }
            }
        }
        $sub.Dispose()
    }

    return [pscustomobject]@{
        RevisionId         = $rid
        UpdateId           = $uid
        CreationDate       = if ($cd) { $cd } else { '' }
        IsBundle           = $isBundle
        IsLeaf             = $isLeaf
        SupersededByCount  = $supN
        ProductGuids       = $prods.ToArray()
        ClassificationGuids = $classes.ToArray()
        PayloadDigests     = $digs.ToArray()
        BundledByRevIds    = $parents.ToArray()
        IsLive             = ($supN -eq 0)
    }
}

function Read-MasterModel {
    <#
      Single streaming pass over the Master XML. Returns a model object with:
        FileUrl[digest] -> url
        ByUpdateId[uid] -> record
        LeavesByParentRevId[revid] -> [records]   (built from reverse BundledBy)
    #>
    param([string]$MasterPath)

    $fileUrl    = [System.Collections.Generic.Dictionary[string, string]]::new()
    $byUpdateId = [System.Collections.Generic.Dictionary[string, object]]::new()
    $leaves     = [System.Collections.Generic.Dictionary[int, System.Collections.Generic.List[object]]]::new()
    $raw        = [System.Collections.Generic.List[object]]::new()
    $flCount = 0

    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.IgnoreWhitespace = $true
    $settings.IgnoreComments = $true
    $reader = [System.Xml.XmlReader]::Create($MasterPath, $settings)
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
            switch ($reader.LocalName) {
                'FileLocation' {
                    $id = $reader.GetAttribute('Id'); $u = $reader.GetAttribute('Url')
                    if ($id) { $fileUrl[$id] = $u; $flCount++ }
                }
                'Update' {
                    $rec = Read-UpdateSubtree $reader
                    if ($rec.UpdateId) { $byUpdateId[$rec.UpdateId] = $rec }
                    $raw.Add($rec)
                }
            }
        }
    } finally { $reader.Dispose() }

    foreach ($rec in $raw) {
        foreach ($parentRid in $rec.BundledByRevIds) {
            if (-not $leaves.ContainsKey($parentRid)) { $leaves[$parentRid] = [System.Collections.Generic.List[object]]::new() }
            $leaves[$parentRid].Add($rec)
        }
    }

    $sha = Get-FileSha256 $MasterPath
    return [pscustomobject]@{
        FileUrl             = $fileUrl
        ByUpdateId          = $byUpdateId
        LeavesByParentRevId = $leaves
        MasterSha256        = $sha
        UpdateCount         = $raw.Count
        FileLocationCount   = $flCount
    }
}

# -- model accessors --------------------------------------------------------
function Get-UrlForDigest { param($Model, [string]$Digest)
    if ($Digest -and $Model.FileUrl.ContainsKey($Digest)) { return $Model.FileUrl[$Digest] }
    return $null
}
function Get-FilenameForDigest { param($Model, [string]$Digest)
    $u = Get-UrlForDigest $Model $Digest
    if ($u) { return ($u -split '/')[-1] }
    return $null
}
function Get-LeavesOf { param($Model, $Bundle)
    if ($Model.LeavesByParentRevId.ContainsKey($Bundle.RevisionId)) { return $Model.LeavesByParentRevId[$Bundle.RevisionId] }
    return @()
}
function Get-LiveBundlesForProduct {
    param($Model, [string]$ProductGuid, [string]$ClassificationGuid)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($rec in $Model.ByUpdateId.Values) {
        if (-not $rec.IsBundle -or -not $rec.IsLive) { continue }
        if ($ProductGuid -notin $rec.ProductGuids) { continue }
        if ($ClassificationGuid -and $ClassificationGuid -notin $rec.ClassificationGuids) { continue }
        $out.Add($rec)
    }
    # Deterministic: newest CreationDate first, tie-break RevisionId desc.
    return @($out | Sort-Object -Property @{Expression = 'CreationDate'; Descending = $true}, @{Expression = 'RevisionId'; Descending = $true})
}

function Get-BundlePayloadKbs { param($Model, $Bundle)
    $kbs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        foreach ($dg in $leaf.PayloadDigests) {
            $k = Get-KbFromName (Get-FilenameForDigest $Model $dg)
            if ($k) { [void]$kbs.Add($k) }
        }
    }
    return @($kbs | Sort-Object)
}
function Get-BundlePayloadArchs { param($Model, $Bundle)
    $a = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        foreach ($dg in $leaf.PayloadDigests) {
            $ar = Get-ArchFromName (Get-FilenameForDigest $Model $dg)
            if ($ar) { [void]$a.Add($ar) }
        }
    }
    return @($a | Sort-Object)
}

function New-FileRecord {
    param($Model, [string]$Digest, [string]$Role, [string]$ParentLcuKb)
    $fn = Get-FilenameForDigest $Model $Digest
    if (-not $Role) { $Role = Get-UupFileRole $fn $ParentLcuKb }
    return [ordered]@{ fileName = $fn; digest = $Digest; url = (Get-UrlForDigest $Model $Digest); role = $Role }
}

# ===========================================================================
# Layer 4 - HEAD size probe (for 2016 LCU vs SSU)
# ===========================================================================
function Get-HeadSize {
    param([string]$Url)
    if ([string]::IsNullOrEmpty($Url)) { return $null }
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 30 -ErrorAction Stop
        $cl = $resp.Headers['Content-Length']
        if ($cl -is [array]) { $cl = $cl[0] }
        if ($cl) { return [long]$cl }
        return $null
    } catch { return $null }
}

function Get-FirstCabDigest { param($Model, $Bundle)
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        foreach ($dg in $leaf.PayloadDigests) {
            $fn = (Get-FilenameForDigest $Model $dg)
            if ($fn -and $fn.ToLower().EndsWith('.cab')) { return $dg }
        }
    }
    return $null
}

# ===========================================================================
# Layer 5 - Per-OS resolvers (independent by design)
# ===========================================================================
function New-OsResult {
    param([string]$OsName, [string]$Pg, $Lcu, $Ssu, $Dotnet, $SafeOs, [string[]]$Notes)
    return [ordered]@{
        os = $OsName; productGuid = $Pg
        lcu = $Lcu; ssu = $Ssu; dotnet = $Dotnet; safeOsDu = $SafeOs
        notes = $Notes
    }
}

function Resolve-Server2016 {
    param($Model)
    $pg = $script:OsProductGuid.Server2016
    $bundles = Get-LiveBundlesForProduct $Model $pg $script:Classification.Security
    $cands = [System.Collections.Generic.List[object]]::new()
    foreach ($b in $bundles) {
        $names = @(); foreach ($leaf in (Get-LeavesOf $Model $b)) { foreach ($dg in $leaf.PayloadDigests) { $names += (Get-FilenameForDigest $Model $dg) } }
        if ($names.Count -eq 0) { continue }
        $hasNdp = $false; foreach ($n in $names) { if (Get-NdpFromName $n) { $hasNdp = $true; break } }
        if ($hasNdp) { continue }
        $hasCab = $false; foreach ($n in $names) { if ($n -and $n.ToLower().EndsWith('.cab')) { $hasCab = $true; break } }
        if (-not $hasCab) { continue }
        $cands.Add($b)
    }
    $notes = @(
        '2016 is the only generation with a standalone SSU line.',
        'In-box .NET (3.5/4.6.2/4.7.x) is serviced by the OS LCU; .NET 4.8 (ndp48) is out of scope.'
    )
    if ($cands.Count -eq 0) { return (New-OsResult 'Server2016' $pg $null $null $null $null ($notes + 'no 2016 servicing bundles found')) }

    # Group by DATE (first 10 chars) - same-day LCU & SSU differ only by time.
    $newestDate = $cands[0].CreationDate.Substring(0, 10)
    $newest = @($cands | Where-Object { $_.CreationDate.Substring(0, 10) -eq $newestDate })

    $scored = foreach ($b in $newest) {
        $dg = Get-FirstCabDigest $Model $b
        [pscustomobject]@{ Bundle = $b; Digest = $dg; Size = (Get-HeadSize (Get-UrlForDigest $Model $dg)) }
    }
    $sizesKnown = -not ($scored | Where-Object { $null -eq $_.Size })

    if ($sizesKnown -and @($scored).Count -ge 2) {
        $sorted = @($scored | Sort-Object -Property Size -Descending)
        $lcu = New-Wsus2016Entry $Model $sorted[0] 'LCU'
        $ssu = New-Wsus2016Entry $Model $sorted[-1] 'SSU'
        $notes += 'LCU vs SSU separated by SelfContained .cab size via HEAD (SSU<<LCU); reproducible per snapshot.'
        return (New-OsResult 'Server2016' $pg $lcu $ssu $null $null $notes)
    }
    if ($sizesKnown -and @($scored).Count -eq 1) {
        $lcu = New-Wsus2016Entry $Model $scored[0] 'LCU'
        $notes += 'Only one servicing candidate found; treated as LCU.'
        return (New-OsResult 'Server2016' $pg $lcu $null $null $null $notes)
    }
    # Offline / HEAD unavailable.
    $res = New-OsResult 'Server2016' $pg $null $null $null $null ($notes + 'LCU/SSU undetermined (offline; needs size probe).')
    $res['lcuSsuCandidates'] = @($scored | ForEach-Object {
        [ordered]@{ kb = (Get-KbFromName (Get-FilenameForDigest $Model $_.Digest)); bundleUpdateId = $_.Bundle.UpdateId
                    digest = $_.Digest; url = (Get-UrlForDigest $Model $_.Digest); fileName = (Get-FilenameForDigest $Model $_.Digest) }
    })
    return $res
}

function New-Wsus2016Entry {
    param($Model, $Scored, [string]$Role)
    $fn = Get-FilenameForDigest $Model $Scored.Digest
    return [ordered]@{
        kb = (Get-KbFromName $fn); bundleUpdateId = $Scored.Bundle.UpdateId
        creationDate = $Scored.Bundle.CreationDate
        files = @([ordered]@{ fileName = $fn; digest = $Scored.Digest; url = (Get-UrlForDigest $Model $Scored.Digest); role = $Role; sizeBytes = $Scored.Size })
    }
}

function New-DotnetEntry {
    param($Model, $Bundle, [string]$InboxNdp)   # InboxNdp: 'ndp48' (2022) | 'non-ndp48' (2019)
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        foreach ($dg in $leaf.PayloadDigests) {
            $fn = Get-FilenameForDigest $Model $dg
            $ndp = Get-NdpFromName $fn
            if ($InboxNdp -eq 'ndp48') { $inScope = ($ndp -eq '48') }
            else { $inScope = ($null -eq $ndp) -or ($ndp -notin @('48', '481')) }
            $files.Add([ordered]@{ fileName = $fn; digest = $dg; url = (Get-UrlForDigest $Model $dg); ndp = $ndp; inScope = [bool]$inScope })
        }
    }
    $sorted = @($files | Sort-Object -Property @{Expression = { -not $_.inScope }}, @{Expression = 'fileName'})
    $inScopeKbs = @($sorted | Where-Object { $_.inScope } | ForEach-Object { Get-KbFromName $_.fileName } | Where-Object { $_ } | Sort-Object -Unique)
    $allKbs = @($sorted | ForEach-Object { Get-KbFromName $_.fileName } | Where-Object { $_ } | Sort-Object -Unique)
    $primary = if ($inScopeKbs.Count) { $inScopeKbs[0] } elseif ($allKbs.Count) { $allKbs[0] } else { $null }
    return [ordered]@{
        kb = $primary
        inScopeKb = if ($inScopeKbs.Count) { $inScopeKbs[0] } else { $null }
        allLeafKbs = $allKbs
        bundleUpdateId = $Bundle.UpdateId
        bundleKbNote = 'the combined-CU bundle KB is not in the cab Master (no KBArticleID); only leaf KBs are derivable'
        inScopeRule = if ($InboxNdp -eq 'ndp48') { 'NDP48 in scope' } else { 'non-NDP48 (in-box) in scope' }
        files = $sorted
    }
}

function New-GenericLcuEntry {
    param($Model, $Bundle)
    $leafFiles = [System.Collections.Generic.List[object]]::new()
    $leafIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        [void]$leafIds.Add($leaf.UpdateId)
        foreach ($dg in $leaf.PayloadDigests) { $leafFiles.Add((New-FileRecord $Model $dg $null $null)) }
    }
    $sorted = @($leafFiles | Sort-Object -Property @{Expression = 'role'}, @{Expression = 'fileName'})
    $kbs = @(Get-BundlePayloadKbs $Model $Bundle)
    return [ordered]@{
        kb = $(if ($kbs.Count -gt 0) { $kbs[0] } else { $null })
        kbs = $kbs; bundleUpdateId = $Bundle.UpdateId
        leafUpdateIds = @($leafIds | Sort-Object); creationDate = $Bundle.CreationDate
        files = $sorted
    }
}

function Resolve-LcuAndDotnet {
    param($Model, [string]$OsName, [string]$Pg, [string]$InboxNdp, [string[]]$Notes)
    $bundles = Get-LiveBundlesForProduct $Model $Pg $script:Classification.Security
    $lcu = $null; $dotnet = $null
    foreach ($b in $bundles) {
        $archs = Get-BundlePayloadArchs $Model $b
        if ('x64' -notin $archs) { continue }
        $names = @(); foreach ($leaf in (Get-LeavesOf $Model $b)) { foreach ($dg in $leaf.PayloadDigests) { $names += (Get-FilenameForDigest $Model $dg).ToLower() } }
        $isNet = $false; foreach ($n in $names) { if ($n -match '-ndp' -or $n -match 'dotnet') { $isNet = $true; break } }
        if ($isNet -and $null -eq $dotnet) { $dotnet = New-DotnetEntry $Model $b $InboxNdp }
        elseif (-not $isNet -and $null -eq $lcu) { $lcu = New-GenericLcuEntry $Model $b }
    }
    return (New-OsResult $OsName $Pg $lcu $null $dotnet $null $Notes)
}

function Resolve-Server2019 {
    param($Model)
    return (Resolve-LcuAndDotnet $Model 'Server2019' $script:OsProductGuid.Server2019 'non-ndp48' @(
        'No standalone SSU (embedded in the LCU leaf).',
        '.NET in-box = 4.7.2 -> in-box (non-NDP48) leaf in scope; NDP48 (4.8) is add-on.'
    ))
}

function Resolve-Server2022 {
    param($Model)
    $res = Resolve-LcuAndDotnet $Model 'Server2022' $script:OsProductGuid.Server2022 'ndp48' @(
        'No standalone SSU (embedded in the LCU leaf).',
        '.NET in-box = 4.8 -> NDP48 leaf in scope; NDP481 (4.8.1) is add-on (inverse of 2019).',
        'SafeOS DU (KB5094157-style) is a separate Dynamic Update (ComponentUpdate); it is out of the offline-scan cab''s scope (security/rollup/servicepack only), so it is NOT in wsusscn2.cab. Acquire it from the Microsoft Update Catalog / WSUS — resolve the current one via the catalog resolver (safeOsDuCatalog / -Action SafeOsDu).'
    )
    $res.safeOsDu = $null
    $res['safeOsDuStatus'] = 'not-in-cab:available-from-catalog'
    return $res
}

function Get-Inferred2025LcuKb {
    param($Model, $Bundle)
    $msuKbs = [System.Collections.Generic.List[int]]::new()
    foreach ($leaf in (Get-LeavesOf $Model $Bundle)) {
        foreach ($dg in $leaf.PayloadDigests) {
            $fn = (Get-FilenameForDigest $Model $dg)
            if ($fn -and $fn.ToLower().EndsWith('.msu')) { $k = Get-KbFromName $fn; if ($k) { $msuKbs.Add([int]$k) } }
        }
    }
    if ($msuKbs.Count -eq 0) { return $null }
    return [string](($msuKbs | Measure-Object -Maximum).Maximum)
}

function Resolve-Server2025 {
    param($Model)
    $pg = $script:OsProductGuid.Server2025
    $bundles = Get-LiveBundlesForProduct $Model $pg $script:Classification.Security
    $lcuBundle = $null; $netBundle = $null
    foreach ($b in $bundles) {
        $archs = Get-BundlePayloadArchs $Model $b
        $names = @(); foreach ($leaf in (Get-LeavesOf $Model $b)) { foreach ($dg in $leaf.PayloadDigests) { $names += (Get-FilenameForDigest $Model $dg).ToLower() } }
        $isNet = $false; foreach ($n in $names) { if ($n -match '-ndp') { $isNet = $true; break } }
        if ($isNet) { if ('x64' -in $archs -and $null -eq $netBundle) { $netBundle = $b }; continue }
        $hasMsu = $false; foreach ($n in $names) { if ($n.EndsWith('.msu')) { $hasMsu = $true; break } }
        if ('x64' -in $archs -and $hasMsu -and $null -eq $lcuBundle) { $lcuBundle = $b }
    }

    $lcu = $null; $ssu = $null; $safeos = $null; $dotnet = $null
    if ($lcuBundle) {
        $lcuKb = Get-Inferred2025LcuKb $Model $lcuBundle
        $allFiles = [System.Collections.Generic.List[object]]::new()
        $leafIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($leaf in (Get-LeavesOf $Model $lcuBundle)) {
            [void]$leafIds.Add($leaf.UpdateId)
            foreach ($dg in $leaf.PayloadDigests) { $allFiles.Add((New-FileRecord $Model $dg $null $lcuKb)) }
        }
        $sorted = @($allFiles | Sort-Object -Property @{Expression = 'role'}, @{Expression = 'fileName'})
        $lcuFiles = @($sorted | Where-Object { $_.role -in @('LCU', 'GA', 'meta', 'LP-FoD', 'other') })
        $ssuFiles = @($sorted | Where-Object { $_.role -eq 'SSU' })
        $safeFiles = @($sorted | Where-Object { $_.role -eq 'SafeOS-DU' })
        $lcu = [ordered]@{ kb = $lcuKb; bundleUpdateId = $lcuBundle.UpdateId
                           leafUpdateIds = @($leafIds | Sort-Object); files = $lcuFiles }
        if ($ssuFiles.Count) {
            $ver = $null
            foreach ($f in $ssuFiles) { if ($f.fileName -match '(?i)ssu-([\d.]+)-x64') { $ver = $Matches[1]; break } }
            $ssu = [ordered]@{ model = 'uup-checkpoint-in-lcu-leaf'; standalone = $false; version = $ver; files = $ssuFiles }
        }
        if ($safeFiles.Count) {
            $safeos = [ordered]@{ model = 'co-bundled-in-lcu-leaf'; standalone = $false
                                  kb = (Get-KbFromName $safeFiles[0].fileName); files = $safeFiles }
        }
    }
    if ($netBundle) {
        $netFiles = [System.Collections.Generic.List[object]]::new()
        foreach ($leaf in (Get-LeavesOf $Model $netBundle)) { foreach ($dg in $leaf.PayloadDigests) { $netFiles.Add((New-FileRecord $Model $dg $null $null)) } }
        $netKbs = @($netFiles | ForEach-Object { Get-KbFromName $_.fileName } | Where-Object { $_ } | Sort-Object -Unique)
        $dotnet = [ordered]@{ kb = if ($netKbs.Count) { $netKbs[0] } else { $null }
                              bundleUpdateId = $netBundle.UpdateId
                              scope = 'whole-x64-leaf-in-scope (in-box 4.8.1, NDP481, no add-on split)'
                              files = @($netFiles) }
    }
    $notes = @(
        'UUP model: LCU is one multi-file leaf (LCU+GA+checkpoint SSU+SafeOS DU+LP-FoD+meta).',
        'SSU is a checkpoint INSIDE the LCU leaf (no standalone).',
        'SafeOS DU is co-bundled in the LCU leaf (no separate DU node).',
        '.NET in-box 4.8.1 -> whole x64 .NET leaf (NDP481) in scope; arm64 skipped.'
    )
    return (New-OsResult 'Server2025' $pg $lcu $ssu $dotnet $safeos $notes)
}

$script:Resolvers = @{
    Server2016 = ${function:Resolve-Server2016}
    Server2019 = ${function:Resolve-Server2019}
    Server2022 = ${function:Resolve-Server2022}
    Server2025 = ${function:Resolve-Server2025}
}

# ===========================================================================
# SafeOS Dynamic Update resolver (Microsoft Update Catalog)
# ---------------------------------------------------------------------------
# The SafeOS DU (WinRE) is a *separate* Dynamic Update (Product
# "Windows Safe OS Dynamic Update", Description "ComponentUpdate") and is OUT OF
# SCOPE of the offline-scan wsusscn2.cab. It is published to the Microsoft Update
# Catalog / WSUS. This resolves the *current* SafeOS DU for a Server generation
# from OS-limited seed only (OS -> version token); KB numbers are never
# hardcoded. Verified end-to-end (catalog file == SOAP-oracle file by digest)
# for Server 2022 (KB5094157) and Server 2025 (KB5094150).
# ===========================================================================
$script:CatalogSearchUrl   = 'https://www.catalog.update.microsoft.com/Search.aspx'
$script:CatalogDownloadUrl = 'https://www.catalog.update.microsoft.com/DownloadDialog.aspx'

# OS-limited base information: the only per-OS seed required (also derivable
# from the build: 20348 -> 21H2, 26100 -> 24H2).
$script:SafeOsOsToken = [ordered]@{
    Server2022 = '21H2'
    Server2025 = '24H2'
}
$script:SafeOsTitleMark   = 'safe os dynamic update'
$script:SafeOsProductMark = 'windows safe os dynamic update'

function ConvertFrom-CatalogSearchHtml {
    <#  Pure parser (no network): Search.aspx result page -> row objects.
        Each row: uid, title, products, classification, lastUpdated, sizeText, sizeBytes. #>
    param([string]$Html)
    $rows = [System.Collections.Generic.List[object]]::new()
    $linkRx = [regex]"(?is)id=['""]([0-9a-f-]{36})_link['""][^>]*>(.*?)</a>"
    foreach ($m in $linkRx.Matches($Html)) {
        $uid = $m.Groups[1].Value
        $title = ($m.Groups[2].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
        $cell = {
            param([int]$Col)
            $cm = [regex]::Match($Html, ('(?is)id="' + [regex]::Escape($uid) + '_C' + $Col + '_R\d+"[^>]*>(.*?)</td>'))
            if ($cm.Success) { return (($cm.Groups[1].Value -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()) }
            return ''
        }
        $sizeText = & $cell 6
        $sizeBytes = $null
        $sm = [regex]::Match($sizeText, '(\d+)\s*$'); if ($sm.Success) { $sizeBytes = [long]$sm.Groups[1].Value }
        $rows.Add([ordered]@{
                uid = $uid; title = $title; products = (& $cell 2); classification = (& $cell 3)
                lastUpdated = (& $cell 4); sizeText = $sizeText; sizeBytes = $sizeBytes
            })
    }
    return $rows
}

function Get-SafeOsRowSortKey {
    param($Row)
    $ym = 0
    $tm = [regex]::Match([string]$Row.title, '^\s*(\d{4})-(\d{2})')
    if ($tm.Success) { $ym = [int]$tm.Groups[1].Value * 100 + [int]$tm.Groups[2].Value }
    $dt = 0
    $dm = [regex]::Match([string]$Row.lastUpdated, '(\d+)/(\d+)/(\d+)')
    if ($dm.Success) { $dt = [int]$dm.Groups[3].Value * 10000 + [int]$dm.Groups[1].Value * 100 + [int]$dm.Groups[2].Value }
    return ($ym * 1000000 + $dt)
}

function Select-SafeOsDuRow {
    <#  Pure selector: apply the per-OS discriminator (title OR products),
        the version-token + arch filters, then return the newest row. #>
    param($Rows, [string]$Token, [string]$Arch = 'x64')
    $cand = foreach ($r in $Rows) {
        $titleL = ([string]$r.title).ToLower(); $prodL = ([string]$r.products).ToLower()
        $isSafe = ($titleL.Contains($script:SafeOsTitleMark)) -or ($prodL.Contains($script:SafeOsProductMark))
        $archOk = ($titleL.Contains(($Arch.ToLower() + '-based'))) -or ($titleL.Contains($Arch.ToLower()))
        $tokOk = $titleL.Contains($Token.ToLower())
        if ($isSafe -and $archOk -and $tokOk) { $r }
    }
    $cand = @($cand)
    if ($cand.Count -eq 0) { return $null }
    return ($cand | Sort-Object -Property @{ Expression = { Get-SafeOsRowSortKey $_ } } -Descending)[0]
}

function Resolve-CatalogDownloadUrl {
    param([string]$Uid)
    $body = 'updateIDs=[{"size":0,"languages":"","uidInfo":"' + $Uid + '","updateID":"' + $Uid + '"}]' +
    '&updateIDsBlockedForImport=&wsusApiPresent=&contentImport=&sku=&serverName=&ssl=&portNumber=&version='
    $resp = Invoke-WebRequest -Uri $script:CatalogDownloadUrl -Method Post -Body $body `
        -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -UserAgent 'Mozilla/5.0' -TimeoutSec 60
    $urls = [System.Collections.Generic.List[string]]::new()
    foreach ($mm in [regex]::Matches($resp.Content, "https?://[^'`"]+\.(?:cab|msu)")) { [void]$urls.Add($mm.Value) }
    return ($urls | Sort-Object -Unique)
}

function Resolve-SafeOsDuFromCatalog {
    <#  Derive the current SafeOS DU for a Server generation from the Catalog.
        Input is OS-limited (Os -> version token). Returns a normalized entry or
        $null if unavailable/offline. -VerifyDownload attaches base64 SHA1/SHA256. #>
    param([string]$Os, [string]$Arch = 'x64', [switch]$VerifyDownload)
    if (-not $script:SafeOsOsToken.Contains($Os)) { return $null }
    $token = $script:SafeOsOsToken[$Os]
    $query = "Safe OS Dynamic Update Microsoft server operating system version $token"
    try {
        $uri = $script:CatalogSearchUrl + '?q=' + [uri]::EscapeDataString($query)
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -UserAgent 'Mozilla/5.0' -TimeoutSec 60
    }
    catch { return $null }
    $row = Select-SafeOsDuRow (ConvertFrom-CatalogSearchHtml $resp.Content) $token $Arch
    if (-not $row) { return $null }
    $entry = [ordered]@{
        source = 'microsoft-update-catalog'; model = 'standalone-dynamic-update'; standalone = $true
        kb = (Get-KbFromName $row.title); updateId = $row.uid; title = $row.title
        products = $row.products; lastUpdated = $row.lastUpdated; arch = $Arch
        osVersionToken = $token; sizeBytes = $row.sizeBytes; url = $null; fileName = $null
    }
    try {
        $urls = @(Resolve-CatalogDownloadUrl $row.uid)
        $kbL = ([string]$entry.kb).ToLower()
        $pick = $urls | Where-Object { $kbL -and $_.ToLower().Contains($kbL) -and $_.ToLower().Contains($Arch.ToLower()) } | Select-Object -First 1
        if (-not $pick -and $urls.Count) { $pick = $urls[0] }
        if ($pick) { $entry.url = $pick; $entry.fileName = ($pick -split '/')[-1] }
    }
    catch { }
    if ($VerifyDownload -and $entry.url) {
        try {
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("safeos-" + $entry.kb + ".cab")
            Invoke-WebRequest -Uri $entry.url -OutFile $tmp -UseBasicParsing -TimeoutSec 600
            $bytes = [System.IO.File]::ReadAllBytes($tmp)
            $sha1 = [System.Security.Cryptography.SHA1]::Create().ComputeHash($bytes)
            $sha256 = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
            $entry['sha1B64'] = [Convert]::ToBase64String($sha1)
            $entry['sha256B64'] = [Convert]::ToBase64String($sha256)
            $entry.sizeBytes = $bytes.Length
            $entry['verified'] = $true
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        catch { $entry['verified'] = $false }
    }
    return $entry
}

function Add-CatalogSafeOsDu {
    <#  Attach a Catalog-derived SafeOS DU (safeOsDuCatalog) to an OS result. #>
    param($OsResult, [string]$Os, [string]$Arch = 'x64', [switch]$VerifyDownload)
    if (-not $script:SafeOsOsToken.Contains($Os)) { return }
    $cat = Resolve-SafeOsDuFromCatalog -Os $Os -Arch $Arch -VerifyDownload:$VerifyDownload
    $OsResult['safeOsDuCatalog'] = $cat
    if ($Os -eq 'Server2022' -and $cat) { $OsResult['safeOsDuStatus'] = 'not-in-cab:resolved-from-catalog' }
}

# ===========================================================================
# Layer 6 - Verifier (cab digests subset-of oracle digests, per line)
# ===========================================================================
function Get-ResolvedDigests {
    param($OsResult)
    $out = @{ lcu = [System.Collections.Generic.HashSet[string]]::new()
              ssu = [System.Collections.Generic.HashSet[string]]::new()
              dotnet = [System.Collections.Generic.HashSet[string]]::new()
              safeOsDu = [System.Collections.Generic.HashSet[string]]::new() }
    foreach ($key in @('lcu', 'ssu', 'dotnet', 'safeOsDu')) {
        $entry = $OsResult[$key]
        if (-not $entry) { continue }
        if ($entry.Contains('files') -and $entry['files']) {
            foreach ($f in $entry['files']) { if ($f['digest']) { [void]$out[$key].Add($f['digest']) } }
        }
    }
    return $out
}

function Get-OracleDigests {
    param($Oracle)
    $out = @{ lcu = [System.Collections.Generic.HashSet[string]]::new()
              ssu = [System.Collections.Generic.HashSet[string]]::new()
              dotnet = [System.Collections.Generic.HashSet[string]]::new()
              safeOsDu = [System.Collections.Generic.HashSet[string]]::new() }
    if ($Oracle.PSObject.Properties['Ssu'] -and $Oracle.Ssu -and $Oracle.Ssu.PSObject.Properties['Files']) {
        foreach ($f in $Oracle.Ssu.Files) { if ($f.Digest) { [void]$out.ssu.Add($f.Digest) } }
    }
    if ($Oracle.PSObject.Properties['SafeOsDu'] -and $Oracle.SafeOsDu -and $Oracle.SafeOsDu.PSObject.Properties['Files']) {
        foreach ($f in $Oracle.SafeOsDu.Files) { if ($f.Digest) { [void]$out.safeOsDu.Add($f.Digest) } }
    }
    $lineMap = @{ LCU = 'lcu'; SSU = 'ssu'; NET = 'dotnet' }
    if ($Oracle.PSObject.Properties['CurrentSetLeaves'] -and $Oracle.CurrentSetLeaves) {
        foreach ($leaf in $Oracle.CurrentSetLeaves) {
            $key = $lineMap[$leaf.Line]
            if (-not $key) { continue }
            if ($leaf.PSObject.Properties['Files'] -and $leaf.Files) {
                foreach ($f in $leaf.Files) { if ($f.Digest) { [void]$out[$key].Add($f.Digest) } }
            }
        }
    }
    return $out
}

function Test-AgainstOracle {
    param($OsResult, $Oracle)
    $resolved = Get-ResolvedDigests $OsResult
    $expected = Get-OracleDigests $Oracle
    $report = [ordered]@{}
    $overall = $true
    foreach ($line in @('lcu', 'ssu', 'dotnet', 'safeOsDu')) {
        $exp = $expected[$line]; $got = $resolved[$line]
        if ($exp.Count -eq 0 -and $got.Count -eq 0) {
            $report[$line] = [ordered]@{ checked = $false; reason = 'neither oracle nor cab has digests for this line' }
            continue
        }
        if ($exp.Count -eq 0) {
            $report[$line] = [ordered]@{ checked = $false; reason = 'oracle has no digests for this line'; cabResolved = @($got | Sort-Object) }
            continue
        }
        $matched = @($got | Where-Object { $exp.Contains($_) } | Sort-Object)
        $cabOnly = @($got | Where-Object { -not $exp.Contains($_) } | Sort-Object)
        $oracleOnly = @($exp | Where-Object { -not $got.Contains($_) } | Sort-Object)
        $pass = ($got.Count -gt 0) -and ($cabOnly.Count -eq 0)
        if (-not $pass) { $overall = $false }
        $report[$line] = [ordered]@{
            checked = $true
            cabResolved = @($got | Sort-Object); oracleExpected = @($exp | Sort-Object)
            matched = $matched; cabOnly = $cabOnly; oracleOnly = $oracleOnly; pass = $pass
        }
    }
    $report['overall'] = $overall
    return $report
}

# ===========================================================================
# Output assembly + summary
# ===========================================================================
function New-Provenance {
    param($CabInfo, $Model)
    return [ordered]@{
        schemaVersion = $script:SchemaVersion; toolVersion = $script:ToolVersion
        generatedUtc = (Get-UtcNowIso)
        source = [ordered]@{
            url = $CabInfo.url; cabSha256 = $CabInfo.sha256; cabSize = $CabInfo.size
            cabDownloadedUtc = $CabInfo.downloaded_utc; masterSha256 = $Model.MasterSha256
        }
        masterStats = [ordered]@{ updates = $Model.UpdateCount; fileLocations = $Model.FileLocationCount }
    }
}

function Invoke-Analyze {
    param([string]$MasterPath, $CabInfo, [string[]]$Oses,
        [switch]$SafeOsFromCatalog, [string]$SafeOsArch = 'x64', [switch]$SafeOsVerify)
    $model = Read-MasterModel $MasterPath
    $results = [ordered]@{}
    foreach ($osName in $Oses) {
        $fn = $script:Resolvers[$osName]
        $osResult = & $fn $model
        if ($SafeOsFromCatalog) {
            Add-CatalogSafeOsDu -OsResult $osResult -Os $osName -Arch $SafeOsArch -VerifyDownload:$SafeOsVerify
        }
        $results[$osName] = $osResult
    }
    return [ordered]@{ provenance = (New-Provenance $CabInfo $model); results = $results }
}

function Format-Summary {
    param($Report)
    $sb = [System.Text.StringBuilder]::new()
    $p = $Report.provenance
    [void]$sb.AppendLine("wsusscn2.cab analysis  (tool $($p.toolVersion), schema $($p.schemaVersion))")
    [void]$sb.AppendLine("  cab sha256 : $($p.source.cabSha256)")
    [void]$sb.AppendLine("  generated  : $($p.generatedUtc)")
    [void]$sb.AppendLine("  master     : $($p.masterStats.updates) updates / $($p.masterStats.fileLocations) file-locations")
    [void]$sb.AppendLine("")
    foreach ($osName in $Report.results.Keys) {
        $r = $Report.results[$osName]
        [void]$sb.AppendLine("== $osName ==")
        foreach ($pair in @(@('lcu', 'LCU'), @('ssu', 'SSU'), @('dotnet', '.NET'), @('safeOsDu', 'SafeOS DU'))) {
            $key = $pair[0]; $label = $pair[1]; $entry = $r[$key]
            if (-not $entry) {
                $status = if ($key -eq 'safeOsDu' -and $r.Contains('safeOsDuStatus')) { $r['safeOsDuStatus'] } else { '(none / N/A)' }
                [void]$sb.AppendLine(("  {0,-9} : {1}" -f $label, $status)); continue
            }
            $kb = if ($entry.Contains('kb') -and $entry['kb']) { $entry['kb'] } elseif ($entry.Contains('version') -and $entry['version']) { $entry['version'] } else { '?' }
            $nfiles = if ($entry.Contains('files') -and $entry['files']) { @($entry['files']).Count } else { 0 }
            [void]$sb.AppendLine(("  {0,-9} : KB{1}  ({2} file{3})" -f $label, $kb, $nfiles, $(if ($nfiles -eq 1) { '' } else { 's' })))
        }
        if ($r.Contains('safeOsDuCatalog') -and $r['safeOsDuCatalog']) {
            $c = $r['safeOsDuCatalog']
            $cname = if ($c.fileName) { $c.fileName } elseif ($c.updateId) { $c.updateId } else { '?' }
            [void]$sb.AppendLine(("  {0,-9} : KB{1}  (catalog: {2})" -f 'SafeOS@Cat', $c.kb, $cname))
        }
        [void]$sb.AppendLine("")
    }
    return $sb.ToString()
}

function ConvertTo-StableJson { param($Object) return ($Object | ConvertTo-Json -Depth 30) }

# ===========================================================================
# CLI dispatch
# ===========================================================================
function Get-CabInfoForLocal { param([string]$Path)
    return [ordered]@{ path = (Resolve-Path -LiteralPath $Path).Path; url = $null
                       sha256 = (Get-FileSha256 $Path); size = (Get-Item -LiteralPath $Path).Length
                       cached = $true; downloaded_utc = $null }
}

function Get-MasterAndInfo {
    param([string]$WorkDir, [string]$Cab, [string]$MasterXml, [string]$Url, [switch]$Force)
    $extractDir = Join-Path $WorkDir '_extract'
    if ($MasterXml) {
        if (-not (Test-Path -LiteralPath $MasterXml)) { throw "MasterXml not found: $MasterXml" }
        # Synthesize cab info from the master (no cab hash available).
        $info = [ordered]@{ path = $null; url = $null; sha256 = $null
                            size = $null; cached = $true; downloaded_utc = $null }
        return @{ Master = (Resolve-Path -LiteralPath $MasterXml).Path; Info = $info }
    }
    if ($Cab) { $cabPath = $Cab; $info = Get-CabInfoForLocal $Cab }
    else {
        $cabPath = Join-Path $WorkDir 'wsusscn2.cab'
        $info = Invoke-Wsusscn2Download -Url $Url -DestPath $cabPath -Force:$Force
    }
    $master = Expand-Wsusscn2Cab -CabPath $cabPath -WorkDir $extractDir
    return @{ Master = $master; Info = $info }
}

function Out-Result {
    param($Report, [string]$OutFile, [switch]$Summary, [bool]$AsJson)
    if ($Summary) { [Console]::Error.WriteLine((Format-Summary $Report)) }
    if (-not $AsJson) { return $Report }    # emit object to pipeline
    $json = ConvertTo-StableJson $Report
    if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $json -Encoding utf8; [Console]::Error.WriteLine("written: $OutFile") }
    else { Write-Output $json }
}

# ===========================================================================
# CLI dispatch (skipped when the script is dot-sourced, e.g. by Pester tests)
# ===========================================================================
if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Action) { Get-Help -Full $PSCommandPath; return }

switch ($Action) {
    'Download' {
        $cabPath = if ($Cab) { $Cab } else { Join-Path $WorkDir 'wsusscn2.cab' }
        $info = Invoke-Wsusscn2Download -Url $Url -DestPath $cabPath -Force:$Force
        Write-Output (ConvertTo-StableJson $info)
    }
    'Analyze' {
        $oses = if ($Os) { @($Os) } else { $script:SupportedOses }
        $ma = Get-MasterAndInfo -WorkDir $WorkDir -Cab $Cab -MasterXml $MasterXml -Url $Url -Force:$Force
        $report = Invoke-Analyze -MasterPath $ma.Master -CabInfo $ma.Info -Oses $oses `
            -SafeOsFromCatalog:$SafeOsFromCatalog -SafeOsArch $SafeOsArch -SafeOsVerify:$SafeOsVerify
        Out-Result -Report $report -OutFile $OutFile -Summary:$Summary -AsJson $AsJson
    }
    'Resolve' {
        if (-not $Os) { throw "Resolve requires -Os." }
        $ma = Get-MasterAndInfo -WorkDir $WorkDir -Cab $Cab -MasterXml $MasterXml -Url $Url -Force:$Force
        $report = Invoke-Analyze -MasterPath $ma.Master -CabInfo $ma.Info -Oses @($Os) `
            -SafeOsFromCatalog:$SafeOsFromCatalog -SafeOsArch $SafeOsArch -SafeOsVerify:$SafeOsVerify
        Out-Result -Report $report -OutFile $OutFile -Summary:$Summary -AsJson $AsJson
    }
    'SafeOsDu' {
        if (-not $Os) { throw "SafeOsDu requires -Os (Server2022 or Server2025)." }
        $entry = Resolve-SafeOsDuFromCatalog -Os $Os -Arch $SafeOsArch -VerifyDownload:$SafeOsVerify
        $out = [ordered]@{
            tool = 'Resolve-Wsusscn2PatchSet'; toolVersion = $script:ToolVersion
            schemaVersion = $script:SchemaVersion; generatedUtc = (Get-UtcNowIso)
            os = $Os; safeOsDuCatalog = $entry
        }
        if (-not $AsJson) { $out } else { $json = ConvertTo-StableJson $out
            if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $json -Encoding utf8; [Console]::Error.WriteLine("written: $OutFile") }
            else { Write-Output $json } }
        if (-not $entry) { exit 3 }
    }
    'Verify' {
        if (-not $Os) { throw "Verify requires -Os." }
        if (-not $OraclePath) { throw "Verify requires -OraclePath." }
        $ma = Get-MasterAndInfo -WorkDir $WorkDir -Cab $Cab -MasterXml $MasterXml -Url $Url -Force:$Force
        $report = Invoke-Analyze -MasterPath $ma.Master -CabInfo $ma.Info -Oses @($Os)
        $oracle = Get-Content -LiteralPath $OraclePath -Raw | ConvertFrom-Json
        $vr = Test-AgainstOracle -OsResult $report.results[$Os] -Oracle $oracle
        $out = [ordered]@{ os = $Os; provenance = $report.provenance; verification = $vr }
        if (-not $AsJson) { $out } else { Write-Output (ConvertTo-StableJson $out) }
        if (-not $vr.overall) { exit 2 }
    }
}

```

---
*メモ終わり。正本は英語版で、本日本語版はそこから派生。スナップショット値は 2026-06 の例 — Appendix A〜E のツールが実行のたびに現行セットを再発見します。*
