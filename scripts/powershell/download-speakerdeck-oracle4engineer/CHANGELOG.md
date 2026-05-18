# Changelog

All notable changes to `Download-SpeakerDeck.ps1` (the Speaker Deck
bulk downloader in this directory) are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project uses an `rNN` linear revision counter encoded in
`$Script:ScriptVersion` (the AI-generation date stamp + revision tag).
Each revision number is announced in the script banner and in the
DebugTrace JSONL output.

This CHANGELOG is **English only** per the
[repository-wide documentation language policy](../../../README.md#language-policy).

## [Unreleased]

_No unreleased changes at this time._

## [r21] — 2026-05-18 — `changelog-md-policy-cleanup`

### Changed

- All inline `# rNN:`, `(rNN)`, and prose references to past revisions
  (`# before r13`, `# In r06 and earlier`, `# As of r08:`, etc.) have
  been removed from `Download-SpeakerDeck.ps1`. The descriptive prose
  has been rewritten to describe current behaviour in revision-neutral
  terms. Per-release history now lives exclusively in this `CHANGELOG.md`.
- `$Script:ScriptVersion` bumped to `speakerdeck-2026.05.18-r21`,
  `$Script:ScriptTag` set to `changelog-md-policy-cleanup`.
- Verified clean against `psa.py` 3.3.0 with PSAP0003 and PSAP0004
  enabled: 0 errors, 0 warnings, 0 info.

### Added

- This `CHANGELOG.md` file. Future revisions will be appended here in
  Keep a Changelog 1.1.0 format rather than being recorded in inline
  comments.

### Notes

- This release contains no functional changes; behaviour is identical
  to r20. It is a pure source-code cleanup release applying the
  repository-wide revision-history policy.

## [r20] — Earlier — `upstream-spec-style-alignment`

### Changed

- SPEC.md content and structure aligned with the upstream SPEC pattern
  used in other `scripts/powershell/*` sub-projects.

## [Pre-r20]

The per-revision history for r1 through r19 is not formally recorded
in this CHANGELOG file. Earlier releases tracked changes via inline
`# rNN:` comments in the script body. Those comments were removed in
r21 (see above) per the repository-wide revision-history policy
([root README, "Revision History Policy"](../../../README.md#revision-history-policy)),
which centralises per-release notes in `CHANGELOG.md`.

For the historical context that prior revisions encoded, refer to the
Git history of `Download-SpeakerDeck.ps1` in the
[`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts)
repository.

---

[Unreleased]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r21]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
[r20]: https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/powershell/download-speakerdeck-oracle4engineer
