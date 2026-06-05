<!--
  python- README SUPPLEMENT template (Japanese half; renders into the project README.ja.md).
  Lock-step Japanese mirror of python-readme-supplement.template.md. Same L1 readme items
  (families = [python]) in the same L1 order, as content_model = specific stubs.
     9   readme.rule-catalog   [python]  conditional
     10  readme.output-format  [python]  conditional
  Interleave into the repo- README CORE at ASSEMBLE GROUP 1 (CORE "CI ステータス" の後),
  L1 order 9-10. No GROUP 2. Change both halves in the same commit.
-->

<!-- ===== ASSEMBLE GROUP 1: repo- README CORE の "CI ステータス" の後に挿入(L1 order 9-10) ===== -->

<!-- >>> CANONICAL unit_id=readme.rule-catalog version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## ルールカタログ

<!-- readme.rule-catalog (L1 order 9; [python]; conditional -
     ツールがルールベース(リンター / アナライザ等)の場合のみ記載)。
     FILL: ルールのカタログ - ルール ID、カテゴリ、何を検出するか、デフォルト重大度、
     デフォルトで有効か。デフォルト無効のルールとその理由も記載。 -->

<!-- <<< CANONICAL unit_id=readme.rule-catalog <<< -->
<!-- >>> CANONICAL unit_id=readme.output-format version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## 出力フォーマット

<!-- readme.output-format (L1 order 10; [python]; conditional)。
     FILL: ツールが出力する形式(例: 人間可読テキスト、JSON、SARIF)、各形式の選択方法、
     デフォルト形式の短い例。 -->
<!-- <<< CANONICAL unit_id=readme.output-format <<< -->
