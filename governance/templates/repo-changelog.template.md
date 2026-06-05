<!--
  repo- CHANGELOG template (English only, strictly ASCII; families=all). Renders into the
  project CHANGELOG.md. CHANGELOG is English-only per the canonical doc-language-policy
  (changelog items are bilingual=false) - there is no CHANGELOG.ja twin.
  Realizes the two L1 changelog.* items (both applicability.families = all):
    0  changelog.format  (common-fixed)  - the Keep-a-Changelog header/format boilerplate
    1  changelog.entries (specific)      - the per-revision entries
  No doc-region hash markers (TF (e) owns the contract).
  Tokens: {{PROJECT_TITLE}} {{REPO_ROOT_RELPATH}}
-->
<!-- >>> CANONICAL unit_id=changelog.format version=0.1.0 hash=797cc7c3afb396d3 policy=canonical binding=follow-latest >>> -->
# Changelog

All notable changes to `{{PROJECT_TITLE}}` are documented in this file.

The format is based on
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

<!-- FILL (versioning scheme): state this project's version identifier and where it is
     announced, e.g. an `rNN` linear revision counter encoded in the script banner, or
     a SemVer tag. This sentence is project-specific; keep the rest of this header
     verbatim. -->

This CHANGELOG is **English only** per the repository-wide
[documentation language policy]({{REPO_ROOT_RELPATH}}/README.md).

<!-- <<< CANONICAL unit_id=changelog.format <<< -->
<!-- >>> CANONICAL unit_id=changelog.entries version=0.1.0 hash=NONE policy=structural binding=follow-latest >>> -->
## [Unreleased]

<!-- changelog.entries (L1 order 1; families=all; specific).
     FILL: entries for the next release. Group changes under the Keep a Changelog
     categories that apply (omit empty categories):
       ### Added       - new features / capabilities
       ### Changed     - changes to existing behaviour
       ### Deprecated  - soon-to-be-removed features
       ### Removed      - now-removed features
       ### Fixed        - bug fixes
       ### Security     - vulnerability-relevant changes
-->

<!-- Released versions follow, newest first, each as:

## [<version>] - <YYYY-MM-DD>

### Added
- ...

### Fixed
- ...

  Keep entries factual and reviewer-oriented; record the "why", not just the "what". -->
<!-- <<< CANONICAL unit_id=changelog.entries <<< -->
