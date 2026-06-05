<!--
  repo- README CORE template (Japanese half; renders into the project README.ja.md).
  Lock-step Japanese mirror of repo-readme-core.template.md. Same L1 CORE items
  (applicability.families = all) in the same L1 order, same tokens, same FILL /
  ASSEMBLE points. Keep en/ja structurally identical: when one half changes,
  change both in the same commit.
  Tokens: {{PROJECT_TITLE}} {{REPO_SLUG}} {{REPO_ROOT_RELPATH}}
-->
# {{PROJECT_TITLE}}

> 英語版は [README.md](./README.md) を参照してください。

## ⚠️ 免責事項

**ご利用は自己責任でお願いします。** 本成果物は「現状のまま (AS IS)」提供されて
おり、明示・黙示を問わずいかなる保証もありません。本成果物の使用、改変、配布に
起因または関連して発生したあらゆる損害(データ損失、アカウント停止、ネットワーク
障害、ディスク容量逼迫、その他直接的・間接的な損害を含むが、これらに限定され
ない)について、作者および貢献者は一切の責任を負いません。

本成果物を使用することにより、利用者は以下を承諾するものとします:

* 利用が、対象となるサービスやサイトの利用規約および適用される法令・規制に
  準拠していることを **利用者自身が確認する責任を負う** こと
* 利用に伴う結果(通信費用、ストレージ費用、レート制限、アカウントや IP の
  ブロック等)について **利用者自身が責任を負う** こと
* 取得した資料の知的財産権は原作者に帰属することを尊重し、原著者の権利を
  侵害しないこと
* 実行前にソースコードを確認し、その動作を理解した上で使用すること

本成果物は節度を持ってご利用ください。レート制限を尊重し、組み込みの
スロットリングを回避しないでください。必要以上に高速・頻繁に動作させないで
ください。

<!-- FILL (任意): プロジェクト固有の運用上のリスク注記があれば記載。 -->

本リポジトリ内のすべての成果物に適用される完全な免責事項と自己責任条項に
ついては、[ルート README]({{REPO_ROOT_RELPATH}}/README.ja.md)
([English]({{REPO_ROOT_RELPATH}}/README.md))を参照してください。

## ライセンス

本プロジェクトは `{{REPO_SLUG}}` リポジトリの一部であり、**MIT ライセンス** の
下で公開されています。完全な条文はリポジトリルートの
[`LICENSE`]({{REPO_ROOT_RELPATH}}/LICENSE) ファイルを参照してください。

要約:原著作権表示およびライセンス表示を保持する限り、本ソフトウェアを目的を
問わず自由に使用、改変、配布できます。本ソフトウェアは無保証で提供されます。
詳細は上記の免責事項および LICENSE ファイルを参照してください。

## なぜこれが必要か

<!-- FILL: 1〜2 段落。本成果物が解決する手作業上の課題や未充足のニーズ、
     対象とする利用者、そして何をワークフロー全体として自動化・提供するか。 -->

### 適している用途

<!-- FILL: 想定する利用者・用途の箇条書き(上記免責事項の TOS / 知的財産権
     義務に従うこと)。 -->

### 対象外

<!-- FILL: 本成果物が意図的に対象としないことの箇条書き。 -->

### 読者向けナビゲーション

- **初めて操作する場合**:上記の免責事項を読み、下記の *クイックスタート* に
  目を通してください。
- **内部の挙動と設計**については [`SPEC.md`](./SPEC.md) を参照。
- **テストマトリクスと自己検証手順**については [`TESTING.md`](./TESTING.md) を参照。
- **リビジョン毎の変更履歴**については [`CHANGELOG.md`](./CHANGELOG.md) を参照。
- **リポジトリ全体の LLM エージェント運用ガイド**については、リポジトリルートの
  [`AGENTS.md`]({{REPO_ROOT_RELPATH}}/AGENTS.md) を参照。

## フォルダ構成

```
<!-- FILL: 注釈付きの成果物ディレクトリツリー。bilingual README ペアと
     English-only の開発者向けドキュメントは常に含めること。例: -->
{{PROJECT_TITLE}}
  README.md / README.ja.md     # エンドユーザー向けドキュメント(bilingual)
  SPEC.md                      # 開発者 / LLM 向け仕様(English only)
  TESTING.md                   # 検証手順と結果(English only)
  CHANGELOG.md                 # リビジョン毎の履歴(English only)
```

**使う**だけならこの README を読んでください。**拡張する/同種のものを作る**
場合は `SPEC.md` も読んでください。

## クイックスタート

<!-- FILL: 最初の安全な(DryRun / 評価)起動、続いて本番実行までの、コピー
     して実行できる最小手順。成果物のネイティブ言語のコードブロックを使用。 -->

## CI ステータス

| ステージ | ワークフロー | ステータス |
|:---|:---|:---|
<!-- FILL: CI ワークフロー 1 つにつき 1 行。ワークフローのファイル名は
     プロジェクト固有(SPEC Part A の静的解析 / CI モデルに準拠)。行ごとに
     ステータスバッジを付与。 -->

本リポジトリは多段 CI モデル(まず静的解析、続いてプラットフォーム検証)を
実行します。正準の CI モデルと各ステージの定義は [`SPEC.md`](./SPEC.md) を
参照してください。

<!-- ASSEMBLE: 言語別 / 機能別の SUPPLEMENT セクション(L1 order 6-10)が、
     applicability に従い L1 order でここに挿入される:
       6  readme.action-reference  [powershell, bash]  (conditional)
       7  readme.phase-reference   [powershell, bash]  (conditional)
       8  readme.parameters        [powershell, bash]  (required)
       9  readme.rule-catalog      [python]            (conditional)
       10 readme.output-format     [python]            (conditional)
-->

## 設定

<!-- 外部設定を読み込む成果物の場合のみ記載(conditional)。
     FILL: 設定ファイル / 環境変数 / 優先順位と例。該当しない場合はこの
     セクションごと省略。 -->

## 自己検証

<!-- 自己チェック / 自己テストを同梱する場合のみ記載(optional)。
     FILL: 成果物自身の検証の実行方法と、合格時の状態。該当しない場合は省略。 -->

## トラブルシューティング

<!-- 文書化に値する既知の失敗モードがある場合のみ記載(optional)。
     FILL: 症状 -> 原因 -> 解決 の項目。該当しない場合は省略。 -->

<!-- ASSEMBLE: 言語別 / 機能別の SUPPLEMENT セクション(L1 order 14-15)が、
     applicability に従い L1 order でここに挿入される:
       14 readme.risk-classification [powershell] (optional)
       15 readme.hardware-os-scope   [powershell] (optional)
-->
