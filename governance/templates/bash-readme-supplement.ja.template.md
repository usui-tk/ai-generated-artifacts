<!--
  bash- README SUPPLEMENT template (Japanese half; renders into the project README.ja.md).
  Lock-step Japanese mirror of bash-readme-supplement.template.md. Same L1 readme items
  (families includes bash) in the same L1 order, as content_model = specific stubs.
     6  readme.action-reference  [powershell, bash]  conditional
     7  readme.phase-reference   [powershell, bash]  conditional
     8  readme.parameters        [powershell, bash]  required
  Interleave into the repo- README CORE at ASSEMBLE GROUP 1 (CORE "CI ステータス" の後),
  L1 order 6-8. bash has no items in L1 order 14-15 (no GROUP 2). Change both halves in
  the same commit.
-->

<!-- ===== ASSEMBLE GROUP 1: repo- README CORE の "CI ステータス" の後に挿入(L1 order 6-8) ===== -->

## アクション一覧

<!-- readme.action-reference (L1 order 6; [powershell, bash]; conditional -
     成果物が action / サブコマンド引数でディスパッチする場合のみ記載)。
     FILL: 全 action をカテゴリ別に列挙。各 action に 1 行の目的、書き込み(状態変更)
     の有無、権限要件を記載。 -->

## フェーズ一覧

<!-- readme.phase-reference (L1 order 7; [powershell, bash]; conditional)。
     FILL: 内部のフェーズ / ステージ構成 - フェーズ ID、各フェーズの動作、実行順序、
     DryRun / 評価モードでスキップされるフェーズ。 -->

## パラメーター

<!-- readme.parameters (L1 order 8; [powershell, bash]; required)。
     FILL: 完全なオプション / 引数表(名前 | 型 | デフォルト | 説明)に続き、
     「排他的指定 / オプショングループ」サブセクションで併用不可の組合せを明記。 -->
