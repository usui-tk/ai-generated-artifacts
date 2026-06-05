<!--
  powershell- README SUPPLEMENT template (Japanese half; renders into the project README.ja.md).
  Lock-step Japanese mirror of powershell-readme-supplement.template.md. Same L1
  readme items (applicability.families includes powershell) in the same L1 order,
  as content_model = specific stubs (canonical heading + role / FILL guide). Same
  ASSEMBLE grouping. Keep en/ja structurally identical: change both halves in the
  same commit.
     6  readme.action-reference    [powershell, bash]  conditional
     7  readme.phase-reference     [powershell, bash]  conditional
     8  readme.parameters          [powershell, bash]  required
    14  readme.risk-classification [powershell]         optional
    15  readme.hardware-os-scope   [powershell]         optional
  These interleave into the repo- README CORE (repo-readme-core.ja.template.md)
  at its ASSEMBLE points:
    GROUP 1 (order 6-8)  -> CORE "CI ステータス" の後
    GROUP 2 (order 14-15) -> CORE "トラブルシューティング" の後
-->

<!-- ===== ASSEMBLE GROUP 1: repo- README CORE の "CI ステータス" の後に挿入(L1 order 6-8) ===== -->

## アクション一覧

<!-- readme.action-reference (L1 order 6; [powershell, bash]; conditional -
     成果物が Action / サブコマンドパラメータでディスパッチする場合のみ記載)。
     FILL: 全 Action をカテゴリ別(例: 標準パイプライン / 特殊 / Admin)に列挙。
     各 Action に 1 行の目的、書き込み(状態変更)の有無、昇格要件を記載。 -->

## フェーズ一覧

<!-- readme.phase-reference (L1 order 7; [powershell, bash]; conditional)。
     FILL: 内部のフェーズ / ステージ構成 - フェーズ ID、各フェーズの動作、
     実行順序、DryRun / 評価モードでスキップされるフェーズ。 -->

## パラメーター

<!-- readme.parameters (L1 order 8; [powershell, bash]; required)。
     FILL: 完全なパラメータ表(名前 | 型 | デフォルト | 説明)に続き、
     「排他的指定 / パラメータセット」サブセクションで併用不可の組合せを明記。 -->

<!-- ===== ASSEMBLE GROUP 2: repo- README CORE の "トラブルシューティング" の後に挿入(L1 order 14-15) ===== -->

## リスク分類

<!-- readme.risk-classification (L1 order 14; [powershell]; optional)。
     FILL: Action / モードを副作用リスク(読み取り専用 / 評価 vs 変更 / 破壊的)で
     分類し、変更を許可するフラグ(例: -Execute)を明示。 -->

## 対応 OS とハードウェア

<!-- readme.hardware-os-scope (L1 order 15; [powershell]; optional)。
     FILL: 対応する対象 OS と言語のマトリクス、およびホスト要件
     (ランタイムバージョン、権限、必要な外部ツール)。 -->
