<!--
  powershell- TESTING skeleton template (English only, strictly ASCII). Renders into the
  project TESTING.md. TESTING is English-only per the canonical doc-language-policy
  (spec home A.12) - there is no TESTING.ja twin.
  Realizes the L1 doc-format testing.* items whose applicability.families includes
  powershell, in L1 order:
    0  testing.status-summary        [powershell, bash]  conditional  common-parameterized
    1  testing.static-analysis-gate  [powershell, bash]  conditional  common-parameterized
    2  testing.discovered-bugs       [powershell, bash]  conditional  specific
    3  testing.ci-coverage           [powershell, bash]  conditional  common-parameterized
    4  testing.verification-procedure[powershell, bash]  optional     specific
    5  testing.validation-results    [powershell]         optional     specific
  Sharing note: items 0-4 are families=[powershell, bash] (shared); the bash- TESTING
  template (d4) realizes the same five L1 items. validation-results (5) is powershell-only.
  Since the specific items are heading+role+FILL stubs, there is no project-content
  duplication; L1 owns identity (verified by TF (e)).
  content_model: common-parameterized -> common skeleton + FILL; specific -> heading +
  role + FILL. No doc-region hash markers (TF (e) owns the contract).
  Token: {{PROJECT_TITLE}}
-->
# TESTING — Verification Procedure and Results — {{PROJECT_TITLE}}

> Verification procedure and recorded results for `{{PROJECT_TITLE}}`. Test design and
> the static-analysis contract follow the Part A conventions documented in `SPEC.md`.

<!-- >>> CANONICAL unit_id=testing.status-summary version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Verification status summary

<!-- testing.status-summary (L1 order 0; [powershell, bash]; conditional;
     common-parameterized). Common skeleton - a status table; FILL the rows. -->

| Item | Status | Notes |
|:---|:---|:---|
<!-- FILL: rows - e.g. current revision, static-analysis gate, offline tests, live
     tests, last real-run / real-machine validation. -->

<!-- <<< CANONICAL unit_id=testing.status-summary <<< -->
<!-- >>> CANONICAL unit_id=testing.static-analysis-gate version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Static analysis gate

<!-- testing.static-analysis-gate (L1 order 1; [powershell, bash]; conditional;
     common-parameterized). -->

### Procedure

Run the canonical analyzer over the script(s):

```bash
python3 quality-tools/powershell-static-analyzer/psa.py <script>.ps1
```

### Required gate

The gate passes only at **0 errors / 0 warnings / 0 info**.

### Suppression policy

<!-- FILL: any inline suppressions in use and their justification (default: none). -->

<!-- <<< CANONICAL unit_id=testing.static-analysis-gate <<< -->
<!-- >>> CANONICAL unit_id=testing.discovered-bugs version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Discovered bugs and fix history

<!-- testing.discovered-bugs (L1 order 2; [powershell, bash]; conditional; specific).
     FILL: an append-only list - symptom -> root cause -> fix (revision), one entry per
     defect found during verification. -->

<!-- <<< CANONICAL unit_id=testing.discovered-bugs <<< -->
<!-- >>> CANONICAL unit_id=testing.ci-coverage version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Continuous integration coverage

<!-- testing.ci-coverage (L1 order 3; [powershell, bash]; conditional;
     common-parameterized). Common: a multi-stage CI model (static-analysis stage on
     Linux, then platform validation stage(s)). FILL: the per-stage definitions and an
     explicit "what CI does NOT cover" note. -->

<!-- <<< CANONICAL unit_id=testing.ci-coverage <<< -->
<!-- >>> CANONICAL unit_id=testing.verification-procedure version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Verification procedure

<!-- testing.verification-procedure (L1 order 4; [powershell, bash]; optional; specific).
     FILL: the offline / smoke tests, live checks, and self-verification suite - test
     IDs and what each asserts, how to run them, and determinism categories. -->

<!-- <<< CANONICAL unit_id=testing.verification-procedure <<< -->
<!-- >>> CANONICAL unit_id=testing.validation-results version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## Recorded validation results

<!-- testing.validation-results (L1 order 5; [powershell]; optional; specific).
     FILL: recorded real-run / real-machine validation results and the baseline they
     establish (operator-pending items, environment, and outcomes). -->
<!-- <<< CANONICAL unit_id=testing.validation-results <<< -->
