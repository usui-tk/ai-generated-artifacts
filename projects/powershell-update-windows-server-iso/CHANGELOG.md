---
doc-provenance:
  layer-1-format: 1.0.0
  layer-2-template: 1.0.0
  rendered: 2026-06-08
---
# Changelog

All notable changes to `Update-WindowsServerIso.ps1` (and its
companion files in this project directory) are documented in this
file. Per the repository-wide policy documented in the root
[`SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/SPEC.md), CI workflow changes are recorded here
too — not inside `.github/workflows/` — because this project is the
CI target.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The script version is held in `$Script:ScriptVersion` near the top of
the script and follows the
`update-wsi-<YYYY.MM.DD>-r<NN>` pattern.

## [Unreleased]

### Governance

- **Series-end consolidation stream opened.** The r12 merge campaign
  is complete (r12.00 through r12.75 landed verbatim; the series is
  closed). From this commit onward, commits on this branch are
  Claude-authored under the normal design-first governance: every
  commit is individually proposed, approved and manifest-gated. The
  campaign's verbatim-landing rules (including the pass-through
  pre-approval) no longer apply.
- **Test re-implementation campaign opened.** The external
  implementation's test corpus — including its terminal required
  regression suite — remains input-only and is not adopted verbatim
  (user ruling, 2026-08-07). Its specifications are absorbed by
  re-authoring repository-governed contracts in the existing test
  idiom, declaration-derived where a declared surface exists, with
  every source assertion group tracked to an explicit disposition in
  an out-of-repo re-implementation ledger. The real-environment-
  validated r12.75 code is the specification baseline: test authoring
  does not drive code changes, and any clearly-improving code change
  is raised as a separate proposal with its own version bump.
  Re-examination of the refactoring plan is deferred until this
  campaign completes.

### Tests

- **T47 `collector_artifact_test.py` added** (test re-implementation
  campaign, phase A, first half): the Collector's first
  repository-side regression coverage. Pins the deliverable identity
  (supported filename present, retired project-context filename
  absent), the exact CollectorVersion/SchemaVersion pair
  (`r12` / `windows-server-post-install-evidence/1.10`, advanced
  deliberately per Collector release in place of the external suite's
  floor pins), the project-neutral evidence contract (error schema,
  artifact prefix, OS-tokenized naming, no E2E terminology), the
  pre-r9 retirement guards with cross-version baseline comparison
  explicitly disabled, the collection posture (ESP/MSInfo32
  default-on, C:\Temp output contract, OutputRoot restriction,
  mountvol-based read-only ESP access, the eight-function evidence
  inventory), the no-network invariant, and a Collector parse gate
  that extends the battery beyond the main script. 29 assertions;
  fault-detection verified by mutation on a disposable copy
  (schema drift and an injected network surface both fail closed).
  Specification source: distribution axes R1269/R1270/R1275,
  re-authored; dispositions tracked in the out-of-repo
  re-implementation ledger.
- **T48 `collector_semantics_test.py` added** (phase A, second half):
  behavioral coverage of the Collector's r10→r12 hardening arc. The
  functions under test are extracted from the Collector's own AST and
  exercised against fixtures whose values are measured post-install
  facts from the four-OS ja-jp runs: pending-reboot discrimination
  (measured Server 2022/2025 updater-cleanup PFRO shapes classify
  Advisory; unknown operations, rename/move pairs and malformed data
  stay Blocking; CBS / Windows Update always override; read errors
  yield Unknown without asserting a pending reboot), Secure Boot
  event-field parsing (blank 1801/1808 label fields stay null instead
  of consuming the next label; populated fields retained), the r11
  restart-preflight decision matrix (explicit confirmation with
  provenance; Advisory/Blocking/Unknown startup states fail closed;
  boot history corroborates but is never authoritative; pending state
  captured at startup and rechecked; preflight precedes Secure Boot
  collection), and the r12 Secure Boot evidence semantics
  (WindowsUEFICA2023Capable reference-only; measured WinCS shape
  parses and Disabled-under-Updated means not-required with
  UEFICA2023Status as the status authority; a stale historical 1808
  cannot override a newer 1801; the measured 2022/2025 Updated shape
  confirms with its three evidence sources; the measured 2019
  monitoring divergence stays conservative; Authenticode
  primary-signer observations remain diagnostic-only). 42 assertions;
  fault detection verified by mutation on a disposable copy (an
  allow-list regression and a removed precondition banner both fail
  closed). Specification source: distribution axes R1273/R1274/R1275,
  re-authored. With T47 this closes the Collector coverage gap;
  offline suite is now 26 PASS + the declared T30 red.
- **T49 `oscdimg_reference_test.py` added** (phase B): first contract
  protecting the declared tool-reference file adopted at r12.63.
  D-half, anchored on `data/tool-references/oscdimg-reference.json`:
  the file's SchemaVersion pinned exactly, ExpectedAdkFamily /
  ExpectedAdkServicingKb asserted by FORMAT only, at least two AMD64
  repository references each with a 64-hex digest and a Microsoft
  Symbol Server URL, and at least two qualified identities with valid
  digests — the concrete declared values are deliberately NOT
  duplicated into the test, because the declared file is the value
  authority and duplicating values is the staleness hazard the
  declaration model exists to avoid. B-half, AST-verified: the legacy
  ADK fallback executes nothing and states its non-modification
  behavior, the installer-URL variable and adksetup.exe constants and
  the retired advisory messages are gone from executable code,
  New-BootableIso requires functional qualification and records the
  functional status and resolver evidence path, P01 preserves
  machine-readable resolver-failure evidence, the five oscdimg schema
  identities and three reference names and qualification evidence
  keys are declared, and the Microsoft-script reference parser is
  exercised behaviorally on a synthetic fixture (symbol-store key,
  lowercased hash, version, date). 44 assertions; fault detection
  verified by mutation on a disposable copy (an invalid declared
  digest and a re-introduced retired advisory message both fail
  closed). Specification source: distribution axes R1263/R1264,
  re-authored; the R1264 collection-shape rows are deferred to the
  T51 binder guard per the ledger. Offline suite is now 27 PASS + the
  declared T30 red.
- **T52 `media_authority_test.py` added** (phase C, first half):
  behavioral coverage of the P09/P10/P11 final-writer authority model.
  The functions under test are extracted from the script's own AST and
  exercised against measured fixtures, with the DISM boundary mocked
  for the WinPE media-sync runtime group: the retained r12.62
  media-sync surface (sync/identity/export functions, their schema
  versions, the P08/P09/P11 evidence artifact names, the cleanup defer
  wiring, and the r12.72 explicit creation of the standard EFI boot
  manager and root bootmgr.efi), the r12.62 WinPE media-sync runtime
  (boot.wim index 2 mocked at build 26100: zero-failure sync,
  setuphost.exe required, all seven semantic media targets
  byte-matched to their WinPE source, authority categories correct,
  and the separator-normalized standard boot-manager target set
  exactly the four Microsoft alias paths — pinned in platform-
  invariant form because the Windows case-insensitive alias de-dup
  collapses the raw record list to 4 rows while Linux pwsh keeps both
  separator forms of one alias, raw 5), the r12.72 P10 write-set
  authority binding (a byte-changed firmware boot manager binds to
  P10Pca2023Overlay, an unchanged root bootmgr.efi retains
  P09WinPeSyncRetained, boot.stl always binds to P10BootStlSync,
  exactly two override authorities), the P11 final-identity evidence
  gating (valid explicit P10 evidence consumed with both overrides;
  absent, required-but-missing, tampered-ISO and stale-evidence states
  all rejected), the measured Server 2022 reviewed-pinned Catalog
  identity shape (Verified in PinnedReviewedIdentity mode with the
  ExactConfiguredFileNameDigest binding; a digest-less filename stays
  fail-closed; the P04 selector emits the explicit
  ConfiguredSha1OrFileNameDigest token; the full Setup-DU package
  authority gate reaches Trusted with the pinned-identity success
  status), the measured Server 2019 final Setup-binary authority
  (P09 WinPE authority governs setup binaries over the earlier DU
  hash with the three authority classes counted; byte tampering after
  P09 rejected; a boot.wim override claim without matching successful
  P09 evidence rejected), and the Setup-DU final manifest validation
  guards (unsupported P09 evidence schema and traversal RelativePath
  both rejected). 50 assertions; fault detection verified by mutation
  on a disposable copy (a corrupted P10 authority label, a weakened
  stale-evidence guard and a weakened filename-digest binding all
  fail closed). Specification source: distribution axes
  R1262/R1271/R1272, re-authored; the P11 chain is exercised through
  explicitly authored P09 evidence because the distribution's
  chain-through of raw sync output relies on the Windows alias de-dup
  (the Windows-side chain remains covered by the user-side G2 gate);
  the R1262/R1271/R1272 revision-floor rows are DROP (T40 pins the
  exact ScriptVersion); dispositions tracked in the out-of-repo
  re-implementation ledger. Offline suite is now 28 PASS + the
  declared T30 red.
- **T40 `setup_binaries_sync_test.py` P08S wiring pin reworked**
  (phase C, second half — the O7-deferred option B): the global
  token-count proxy (`code.count("'P08','P08S','P09'") == 5`, whose
  expected value broke at r12.35 when the resume layer legitimately
  added a fifth wiring site) is replaced by a structural invariant
  plus per-site pins. The invariant: every quoted phase-ID list
  literal of three or more elements that contains both P08 and P09
  must wire P08S strictly between them (two-element constructs such
  as parameter ValidateSets are exempt by the length discriminator —
  the measured code has seven such two-element constructs and five
  conforming pipeline lists). The per-site pins name the five known
  lists individually: both standardFull pipeline variants, the Build
  action list, the r12.05 ResumeFromPhase P08 list, and the r12.35
  resume downstream-cleanup prefix list. A legitimately added new
  pipeline list that wires P08S correctly no longer breaks the
  contract (verified by positive control), while a list that drops or
  misorders P08S fails with a line-diagnosed message (verified by
  mutation on a disposable copy at two sites, including the exact
  r12.35 shape that triggered O7). The supersession is documented in
  the test header; the release-pin row and the r12.72
  build-independent Setup-binary plan rows (the R1272 plan contract,
  which the r12.72 T39 revision had already landed in this test) are
  unchanged. T40 is now 21 assertions (was 17). Note for the
  re-implementation ledger: the R1272 "build-independent plan" rows
  map to the pre-existing T40 section 1 rows; the option-B subject
  drained here was the wiring proxy.
- **T50 `catalog_semantics_test.py` added** (phase D, first part):
  behavioral coverage of the r12.52 -> r12.67 Catalog hardening arc.
  The functions under test are extracted from the script's own AST and
  exercised against measured Catalog shapes (the user-observed Server
  2016 four-row Setup DU query and the KB4132216 HTTP-200 page shape):
  the merged R1252 + R1265 + R1267 catalog/collection function
  inventory (48 functions exactly once — also the future input to the
  refactoring plan's static duplicate-function check), the horizontal
  static invariants (no GetNewClosure validator, no scriptblock
  ContentValidator parameter or call site, no nested sorted return,
  the three typed semantic modes plus ExactKbSearch declared,
  transport evidence carrying the validation context, the unvalidated
  POST cache helper gone, collision-resistant cache identity and flat
  PatchBaseline contracts present), the typed validator wiring
  (legacy search helper and Search-Catalog select the exact-KB
  contract; cache and transport both flow through the centralized
  semantic validator; CATALOG_VALIDATOR_EXECUTION_FAILED
  distinguished and excluded from transient retries), the legacy
  helper containment (no direct Invoke-WebRequest -Uri; supplied
  validated HTML reused before networking), the Setup-DU scalar
  identity pins (flat selector returns; UpdateId validated before
  POST body construction; nested candidate rows rejected; selected
  uid validated), and the runtime groups: semantic retry (invalid
  HTTP-200 retried with Failure/transient/200 then Success transport
  events; invalid cache discarded after exactly one revalidated
  fetch; supplied HTML parsed with zero network requests), typed
  endpoint semantics (each active mode accepts its measured shape and
  rejects the mismatch; a malformed exact-KB context fails the
  contract — the exact-KB row filter is pinned on a single-anchor
  page because the measured filter is a context-window heuristic,
  ±1800 chars), cache identity tags (distinct digest-bearing search
  tags; full-UpdateId download/legacy/scoped tags), scalar boundaries
  (arrays, Generic.List values and space-joined multi-GUID strings
  rejected at the UpdateId/KbId/query boundaries), and flat
  collection shapes (four flat candidates from the measured 2016
  shape with the single KB5068794 row selected;
  Select-SetupDuCandidate / Get-X64Rows / ConvertTo-ConfigLines flat;
  language-pack template and WIM inventory materialized). 104
  assertions; fault detection verified by mutation on a disposable
  copy (a transient-reclassified validator failure, a weakened
  UpdateId cardinality guard, and the reintroduced historical r12.65
  nested-return bug all fail closed, the last at both the static and
  runtime layers). Specification source: distribution axes
  R1252/R1265/R1266/R1267, re-authored; the R1252 servicing-contract
  component-hash rows are ADOPT-D in T45; revision-floor rows are
  DROP. Offline suite is now 29 PASS + the declared T30 red.
- **T51 `generic_list_binder_test.py` added** (phase D, second part):
  the r12.17/r12.64 incident class — PowerShell 7.4+ throwing
  'Argument types do not match' when a Generic.List[object] holding
  PSCustomObject rows is materialized through the array subexpression
  or constructed through New-Object. Static pins: no New-Object
  Generic.List construction anywhere in the active script; P11
  evidence takes RowCount from the List Count property directly with
  the failing subexpression form absent; the r12.64 oscdimg
  repository-reference resolver uses constructor-created
  List[object]/List[string] with explicit typed ToArray()
  materialization for records and errors (forbidden subexpression
  forms absent, repository-resolution schema advanced to
  secureboot-objects-oscdimg-resolution/1.1); the local-candidate
  resolver constructs via ::new() and returns a typed ToArray() with
  the subexpression return absent. Behavioral pins under the pinned
  pwsh: constructor-created List[object] of PSCustomObjects
  materializes with order and properties preserved and groups
  correctly (the exact r12.64 repository-record shape); List[string]
  paths survive typed materialization; the exact r12.17 P11 evidence
  shape builds with RowCount from .Count. 17 assertions; fault
  detection verified by mutation on a disposable copy (the r12.63
  @()-materialization failure shape and a reintroduced New-Object
  construction both fail closed). Specification source: distribution
  axes R1217/R1264 plus the R1264 collection-shape rows deferred from
  T49, re-authored; oscdimg function uniqueness stays pinned in T49.
  Offline suite is now 30 PASS + the declared T30 red.
- **T45 `servicing_contract_baseline_test.py` extended** (phase D,
  third part): a script-computed component-hash cross-check closes
  the loop the declaration-shape assertions leave open — that the
  declared file matches itself is necessary but not sufficient; the
  new pin is that the *script* still computes what the file declares.
  The canonical-JSON contract constructors (14 functions) are
  extracted from the script's own AST under the pinned pwsh,
  `Get-ServicingContractComponentHashes` is evaluated for every OS,
  and each of the eight component digests must equal the declared
  baseline value (4 OS x 8 fields). T45 is now 26 assertions (was
  21) and gains a pwsh dependency for the extension section (same
  dependency class as T40/T47/T48/T50/T51/T52); the
  declaration-shape sections remain pure Python. Fault detection
  verified by mutation on a disposable copy: a single semantic line
  changed inside the Server2016 contract definition
  (Install.PendingPolicy) is detected as a Server2016
  ContractSha256 divergence with every other OS and component still
  green. Specification source: distribution axis R1252, ADOPT-D —
  the assertion is anchored on the declared instrument
  (`data/servicing-contract-baselines.json`), not on distribution
  test code.

### Documentation

- **TESTING.md tier re-baseline** (test re-implementation campaign,
  phase E — docs-only): the suite documentation is re-baselined to
  the measured r12.75 series-terminal state. §0 gains rows for the
  six campaign contracts (T47 – T52) and re-measured rows for T30
  (still the declared SUPERSEDED-PENDING red, 6/8; the series closed
  with the discovery model declared in T46 and behaviorally covered
  in T50, while the terminal retained the title-heuristic selector —
  the final supersession disposition is a consolidation-stream
  adjudication), T35 (9 after the r12.57 default-enable reshape), T40
  (21 after the option-B structural-invariant rework), T41/T42/T43
  (139/37/128 at r12.75 — the counts track the declaration), T45
  (26; the anchor exists, the NOT-YET path is dormant) and the
  canonical-format gate (28 files); a suite-level re-measure
  statement records the baseline (30 test files PASS + the declared
  T30 red only). §5's quick-run reference is rewritten to the
  current suite — the stale pre-r12.00 rows referencing the retired
  and deleted T23/T27/T28/T31/T33/T34/T37 files are removed — and the
  two-bucket determinism categorisation is replaced by the three-tier
  execution model: tier 1 offline-deterministic (Python + the pinned
  pwsh), tier 2 live-network (T1/T4; the expanded live-network tier
  design remains a standing consolidation item), tier 3 evidence
  (user-side G2/G3 and the operator-pending pipeline rows). The
  E-DEFER register is declared explicitly EMPTY with the measured
  reason: no re-authored assertion group required real-machine
  execution, including the WinPE media-sync runtime, which phase C
  measured as fully runnable under Linux pwsh with only a
  platform-invariant normalization. An absorption-boundary section
  records that the input-only required regression set was fully
  dispositioned in the out-of-repo ledger and that the external
  historical corpus stays out of scope absent a separate order.
  `tests/README.md` (the canonical inventory) is synced in the same
  change set: T47 – T52 inventory and file-layout rows added, the
  T30/T35/T40/T45/T46 rows and the stale counts re-measured, and the
  stdlib-only wording corrected to name the pwsh dependency. Stale T3
  assertion counts in TESTING.md §2.3/§6.1 are corrected to the
  measured 7.
- **Test re-implementation campaign closed** (phase E is the final
  phase). Every disposition in the out-of-repo re-implementation
  ledger is landed; the repository suite is the operative regression
  net going forward. The standing consolidation items now resume
  in this stream: PSA declared-debt drain (with ScriptVersion bumps),
  knowledge-ledger sweep, live-network tier design, and — at the
  release conversation — the fold of this [Unreleased] section into
  a release heading together with the README.md/README.ja.md
  both-language sync and heading lock-step check. Re-examination of
  the refactoring plan begins only after those items complete, per
  the standing work order.

## [update-wsi-2026.08.07-r12.75] - 2026-08-07

Tag retained: `post-install-evidence-collector-r9-merge`.
**This revision is the r12-series terminal** (user adjudication,
2026-08-07): the external r12 implementation ended here, and every
snapshot from r12.00 through r12.75 has now been landed verbatim
onto this branch (r12.02 lost upstream; r12.36 landed twice per the
double-work rule). The series is CLOSED; consolidation work
(declared-debt drain, knowledge-ledger sweep) follows as separately
governed commits.

### Changed

- **Collector hardened to r12 / schema 1.10 — Secure Boot evidence
  semantics** (ISO servicing pipeline unchanged from r12.72): the
  current/latest rollout state is authoritative; a historical event
  1808 can no longer override newer state; WinCS is treated as
  deployment-configuration evidence only; and the
  WindowsUEFICA2023Capable / Authenticode signer observations are
  explicitly scoped as diagnostics. A startup-preflight evidence
  record (`windows-server-post-install-startup-preflight/1.0`)
  accompanies the main schema. This is the collector revision the
  distribution's acceptance gates expect for the four-VM re-run.
  Collector delta +236 lines net (round-trip criterion verified
  both directions); main-script delta is the identity and the
  validation-marker comment (+2 net lines). The staged main script
  is byte-identical to the terminal-evaluation specimen whose ZIP
  and script SHA-256 were verified against the published plan
  identity. `data/*` and `schema/*` are byte-identical to r12.74.

### Tests

- **T40**: release pin advanced to the terminal
  `update-wsi-2026.08.07-r12.75` (the tag is retained). No terminal
  D-contract required an edit anywhere in the r12.57–r12.75 stretch;
  the contract set closes exactly as derived at r12.00.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. Main script PSA committed 6E/229W/27I
  (raw sweep 6E/230W/27I: +1W is the PSA7002 LF artefact); the
  collector r12 measures 1E/13W/44I standalone as a reference
  figure. All PSA findings across both deliverables are declared
  series debt, scheduled for the post-terminal drain. Snapshot form: main script
  BOM + LF; collector BOM + CRLF; committed checkout form BOM+CRLF
  for both.

## [update-wsi-2026.08.07-r12.74] - 2026-08-07

Tag retained: `post-install-evidence-collector-r9-merge`.

### Changed

- **Collector hardened to r11 / schema 1.9** (ISO servicing pipeline
  unchanged from r12.72): full evidence collection now requires an
  explicit post-install restart confirmation plus a clean startup
  pending-reboot gate, records boot-history corroboration, and
  re-checks the pending-reboot state immediately before the final
  assessment. This is the collector revision that produced the
  four-OS post-install evidence sets accompanying the distribution.
  Collector delta +362 lines net (round-trip criterion verified both
  directions); main-script delta is the identity and the
  validation-marker comment (+2 net lines). `data/*` and `schema/*`
  are byte-identical to r12.73.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.07-r12.74`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. Main script PSA committed 6E/229W/27I
  (raw sweep 6E/230W/27I: +1W is the PSA7002 LF artefact) —
  unchanged from r12.73. Snapshot form: main script BOM + LF;
  collector BOM + CRLF; committed checkout form BOM+CRLF for both.

## [update-wsi-2026.08.07-r12.73] - 2026-08-07

Tag retained: `post-install-evidence-collector-r9-merge`.

### Changed

- **Collector hardened to r10 / schema 1.8** (ISO servicing pipeline
  unchanged from r12.72): pending-reboot evidence now distinguishes
  genuinely blocking servicing state from narrowly recognized
  Microsoft updater cleanup activity, and Secure Boot event message
  parsing is line-safe when BucketId/Confidence fields are blank.
  Collector delta +287 lines net (round-trip criterion verified both
  directions per the r12.70 rule); on the main script the delta is
  the identity and the validation-marker comment (+1 net line, date
  component moves to 08.07). `data/*` and `schema/*` are
  byte-identical to r12.72.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.07-r12.73`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. Main script PSA committed 6E/229W/27I
  (raw sweep 6E/230W/27I: +1W is the PSA7002 LF artefact; +1W on the
  marker line, declared series debt). Snapshot form: main script
  BOM + LF; collector BOM + CRLF; committed checkout form BOM+CRLF
  for both.

## [update-wsi-2026.08.05-r12.72] - 2026-08-07

Tag retained: `post-install-evidence-collector-r9-merge`.

### Changed

- **Final-writer authority is hardened horizontally**: the r12.58+
  lesson (the file firmware actually consumes must be proven, not
  inferred) is applied across the final-media pipeline. P08S plans
  `setup.exe` AND `setuphost.exe` for every supported OS (the sync
  SET is build-independent; the 26100 threshold now lives in the
  REQUIREMENT — a missing `setuphost.exe` throws on 26100+ and is
  tolerated below only when genuinely absent from `boot.wim` index
  2), P09 explicitly creates and verifies the required standard
  boot-manager targets, P10 emits an identity-bound media
  write-set (`Get-P10MediaWriteSnapshot` /
  `New-P10MediaWriteSetEvidence` with safe relative-path
  resolution), and P11 accepts later P10 bytes only through that
  successful evidence. Setup DU final verification validates
  schema, path safety, uniqueness, and source/after hash-size
  binding. The collector is unchanged (r9, schema 1.7).
  Script-only change (+289 lines net); `data/*` and `schema/*` are
  byte-identical to r12.71.

### Tests

- **T39-style pin relocation on T40** (reserved at the session-7
  terminal evaluation; verified green at the r12.72 frame and
  re-verified at the r12.75 terminal frame, 17/17): the
  "26100+ only" plan pin and the "unknown build → setup.exe only"
  pin are replaced by the measured successor surface — every build
  (including unknown) plans both files, and a NEW row pins the
  relocated threshold (`SetupHostRequired` at 10.0.26100.0 with the
  required-but-missing failure text).
- **T40**: release pin advanced to `update-wsi-2026.08.05-r12.72`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/228W/27I (raw sweep
  6E/229W/27I: +1W is the PSA7002 LF artefact; +8W on the new
  evidence code, declared series debt). Snapshot form: BOM + LF
  (main script); committed checkout form BOM+CRLF.

## [update-wsi-2026.08.05-r12.71] - 2026-08-07

Tag retained: `post-install-evidence-collector-r9-merge`.

### Fixed

- **The four-OS clean-E2E failures on Server 2019 / Server 2022 are
  corrected**: P11 now verifies the Setup DU records against the
  authoritative FINAL P09 WinPE setup-binary synchronization state
  (rather than an earlier intermediate), and the reviewed pinned
  Catalog identity accepts an exact digest-bearing configured
  filename as the SHA-1 binding while remaining fail-closed on the
  UpdateId, filename, architecture, metadata and review-basis
  checks. The collector is unchanged at this revision (r9, schema
  1.7). Script-only change (+168 lines net); `data/*` and
  `schema/*` are byte-identical to r12.70.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.05-r12.71`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/220W/27I (raw sweep
  6E/221W/27I: +1W is the PSA7002 LF artefact; +10W on the revised
  verification code, declared series debt). Snapshot form: BOM + LF
  (main script); committed checkout form BOM+CRLF.

## [update-wsi-2026.08.05-r12.70] - 2026-08-07

Tag: `post-install-evidence-collector-r9-merge`.

### Changed

- **Collector r9 is merged as the supported post-install evidence
  collector**: `Collect-WindowsServerPostInstallEvidence.ps1` grows
  from the r2 seed (630 lines) to the full r9 implementation (3,253
  lines) — the read-only installed-OS evidence surface that the
  distribution's four-VM validation runs use. On the main script the
  delta is the identity and the validation-marker comment (+1 net
  line); ISO servicing behavior is unchanged. `data/*` and
  `schema/*` are byte-identical to r12.69.
- **Collector snapshot form is CRLF (recorded)**: unlike every other
  archive deliverable (pure BOM+LF), the r12.70 Collector snapshot
  is pure BOM+CRLF, so Git's `*.ps1` check-in normalization stores
  an LF blob whose SHA differs from the snapshot by design.
  Round-trip identity was proven in both directions
  (LF-normalized snapshot == staged blob; blob re-expanded to CRLF
  == snapshot byte-for-byte), so the committed CHECKOUT canonical
  form (BOM+CRLF) equals the snapshot exactly and verbatim landing
  holds at the canonical level. This two-way check is the standing
  blob-verification criterion for the collector from this revision
  on.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.05-r12.70`
  (date component moves to 08.05) with the measured tag
  `post-install-evidence-collector-r9-merge`. No terminal D-contract
  required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. Main script PSA committed 6E/210W/27I
  (raw sweep 6E/211W/27I: +1W is the PSA7002 LF artefact) —
  unchanged from r12.69. The collector r9 measures 1E/13W/35I
  standalone as a reference figure, carried verbatim as declared
  series debt. Snapshot form: main script BOM + LF; collector
  BOM + CRLF (see above); committed checkout form BOM+CRLF for
  both via `.gitattributes`.

## [update-wsi-2026.08.04-r12.69] - 2026-08-07

Tag: `post-install-evidence-artifact-naming`.

### Added

- **The post-install evidence collector joins the repository as a
  second committed deliverable** (path adopted by user adjudication
  this session, option A):
  `Collect-WindowsServerPostInstallEvidence.ps1` (Collector r2, 630
  lines) lands verbatim at the project root and will track the
  snapshot state revision-by-revision through the series terminal,
  exactly like the main script. The revision gives the collector a
  purpose-based, project-neutral artifact contract — the
  `Collect-WindowsServerPostInstallEvidence.ps1` name itself,
  post-install-evidence schema/output names, and a
  `WindowsServerEvidence` default output root. Distribution
  checksum companions (`*.sha256`, `checksums.sha256`) remain
  input-only, consistent with existing practice for the main
  script. On the main script the delta is the identity and the
  validation-marker comment (+1 net line); ISO servicing behavior
  is unchanged. `data/*` and `schema/*` are byte-identical to
  r12.68.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.04-r12.69`
  with the measured tag `post-install-evidence-artifact-naming`. No
  terminal D-contract required an edit (the D-contracts target the
  main script; the collector is outside their frame).

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. Main script PSA committed 6E/210W/27I
  (raw sweep 6E/211W/27I: +1W is the PSA7002 LF artefact). The
  collector measures 1E/2W/9I standalone as a reference figure —
  carried verbatim as declared series debt per the no-fix-forward
  rule. Snapshot form: BOM + LF on both scripts;
  committed checkout form BOM+CRLF via `.gitattributes`.

## [update-wsi-2026.08.04-r12.68] - 2026-08-07

Tag: `e2e-distribution-finalization`.

### Changed

- **Distribution-layout finalization (identity-and-marker change on
  the committed surface)**: the snapshot finalizes the clean-E2E
  distribution layout — the supported post-install evidence
  collector ships as a stable top-level distribution artifact and
  the oscdimg qualification lab is retained under the
  distribution's `tests/` — without changing any ISO servicing
  behavior. On the committed script the delta is the version/tag
  identity and the validation-marker comment only (+1 line net);
  the distribution-side layout files are input-only under the
  standing series ruling. `data/*` and `schema/*` are byte-identical
  to r12.67.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.04-r12.68`
  (date component moves to 08.04) with the measured tag
  `e2e-distribution-finalization`. No terminal D-contract required
  an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/209W/27I (raw sweep
  6E/210W/27I: +1W is the PSA7002 LF artefact; +1W on the marker
  line, declared series debt). Snapshot form: BOM + LF; committed checkout form BOM+CRLF.

## [update-wsi-2026.08.03-r12.67] - 2026-08-07

Tag: `catalog-boundary-horizontal-hardening`.

### Changed

- **The Catalog/PowerShell collection-shape hardening is applied
  horizontally**: the r12.64–r12.66 fix patterns are completed
  across every active Catalog boundary rather than only at the
  originally failing sites. All active Catalog response contracts
  are typed in-process validators (internal scriptblock validators
  removed); Search, DownloadDialog and ScopedView bodies are
  semantically validated BEFORE caching; cache keys are
  collision-resistant and identity-bound; Catalog identities are
  scalar-validated at every legacy and current download boundary;
  `Generic.List` values are materialized with `ToArray()`; and
  collection selectors return flat sequences throughout. Script-only
  change (+147 lines net); `data/*` and `schema/*` are
  byte-identical to r12.66.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.03-r12.67`
  with the measured tag `catalog-boundary-horizontal-hardening`. No
  terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/208W/27I (raw sweep
  6E/209W/27I: +1W is the PSA7002 LF artefact) — unchanged from
  r12.66. Snapshot form: BOM + LF; committed
  checkout form BOM+CRLF.

## [update-wsi-2026.08.03-r12.66] - 2026-08-07

Tag: `catalog-validator-scope-fix`.

### Fixed

- **Exact-KB Catalog validation works under PowerShell 7 scoping**:
  validators created with `GetNewClosure()` were isolated from the
  script-scope parser functions they call, so exact-KB semantic
  validation could fail for scope reasons and be misread as a
  Catalog transient. Exact-KB validation is now a typed in-process
  contract shared by the cache and transport paths, closures no
  longer sever the validators from script scope, and a validator
  IMPLEMENTATION failure is fail-fast instead of being retried
  against the Catalog. Script-only change (+87 lines net); `data/*`
  and `schema/*` are byte-identical to r12.65.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.03-r12.66`
  with the measured tag `catalog-validator-scope-fix`. No terminal
  D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/208W/27I (raw sweep
  6E/209W/27I: +1W is the PSA7002 LF artefact; +2W declared series
  debt). Snapshot form: BOM + LF; committed
  checkout form BOM+CRLF.

## [update-wsi-2026.08.03-r12.65] - 2026-08-07

Tag: `catalog-setupdu-scalar-updateid-fix`.

### Fixed

- **Setup DU Catalog requests carry exactly one UpdateId**: nested
  candidate collection in the Setup DU discovery path could coerce
  multiple Update Catalog UpdateIds into a single space-delimited
  string, producing a malformed DownloadDialog request. Candidate
  selectors now emit flat rows, every DownloadDialog request
  validates that its identity is exactly one GUID before transport,
  and a malformed identity fails CLOSED without retrying the
  Catalog. Script-only change (+54 lines net); `data/*` and
  `schema/*` are byte-identical to r12.64.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.03-r12.65`
  with the measured tag `catalog-setupdu-scalar-updateid-fix`. No
  terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/206W/27I (raw sweep
  6E/207W/27I: +1W is the PSA7002 LF artefact) — unchanged from
  r12.64. Snapshot form: BOM + LF; committed
  checkout form BOM+CRLF.

## [update-wsi-2026.08.03-r12.64] - 2026-08-07

Tag: `oscdimg-resolver-collection-fix`.

### Fixed

- **The r12.63 resolver's `Generic.List` array-subexpression
  regression on PowerShell 7.4+ is corrected**: repository records,
  error collections, and local candidate paths in the oscdimg
  resolver are now materialized with `List<T>.ToArray()`, and
  `New-Object`-style generic-list construction is removed from the
  resolver — the known engine behavior where wrapping a generic list
  in an array subexpression throws on current PowerShell 7.4+/7.5+
  runtimes. Script-only change (+39 lines net); `data/*` and
  `schema/*` are byte-identical to r12.63.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.03-r12.64`
  with the measured tag `oscdimg-resolver-collection-fix`. No
  terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 6E/206W/27I (raw sweep
  6E/207W/27I: +1W is the PSA7002 LF artefact). **A sixth PSA error
  joins with the revised resolver code and is carried as declared
  series debt per the no-fix-forward rule** (series PSA debt is now
  6E). Snapshot form: BOM + LF; committed
  checkout form BOM+CRLF.

## [update-wsi-2026.08.03-r12.63] - 2026-08-07

Tag: `oscdimg-qualified-resolution`.

### Added

- **`oscdimg.exe` resolution becomes source-aware qualification**
  (replacing the hash-only advisory and the ADK-install fallback):
  candidates are gathered from signed AMD64 local ADK installs
  (PE + Authenticode + ADK-registration evidence) and from
  Microsoft `secureboot_objects` Symbol-Server references resolved
  at runtime from the fetched `Make2023BootableMedia.ps1` script
  text, with a WorkRoot-managed exact-SHA-256 fallback download —
  the host ADK is never modified, selection fails CLOSED when no
  candidate qualifies, and each candidate must pass a cached
  behavioral ISO-assembly test before use. **A new declared dataset
  `data/tool-references/oscdimg-reference.json`
  (`oscdimg-reference/1.0`) enters the repository** (path adopted by
  user adjudication this session): expected ADK family/servicing KB,
  the selection policy, pinned repository references and qualified
  identities that the resolver consumes. The former
  `Install-WindowsAdkFallback` path is removed. Script delta +719
  lines / −206; the remaining `data/*` and `schema/*` files are
  byte-identical to r12.62.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.03-r12.63`
  (date component moves to 08.03) with the measured tag
  `oscdimg-qualified-resolution`. No terminal D-contract required an
  edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/204W/27I (raw sweep
  5E/205W/27I: +1W is the PSA7002 LF artefact; +22W/+15I on the new
  resolver code, declared series debt). Snapshot form: BOM + LF; committed checkout form BOM+CRLF.

## [update-wsi-2026.08.02-r12.62] - 2026-08-07

Tag: `winpe-final-media-sync`.

### Added

- **The Microsoft final WinPE-to-media contract is implemented after
  Setup DU**: once every `boot.wim` index has been serviced and
  committed, the media Dynamic Update sequence requires the serviced
  WinPE payload to be carried onto the final media — not only inside
  the WIM. The revision adds `Export-BootWimCompressed` (rebuilds
  `boot.wim` by exporting every index in original order to a fresh
  `/Compress:max` WIM, with index-count and metadata comparison, the
  original left untouched on any failure — the documented step-25
  export), `Sync-ServicedWinPeMediaFiles` +
  `New-WinPeMediaSyncRecord` (root-invariant final media sync with
  per-file records), and `Test-FinalWinPeMediaIdentity` (the complete
  final-ISO identity surface is verified before release assessment).
  WinPE/WinRE component cleanup uses `/ResetBase /Defer` per the
  media-servicing guidance. Script-only change (+663 lines);
  `data/*` and `schema/*` are byte-identical to r12.61.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.62`
  with the measured tag `winpe-final-media-sync` (first tag change
  since r12.55). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/182W/12I (raw sweep
  5E/183W/12I: +1W is the PSA7002 LF artefact; +21W on the new
  export/sync/verification code, declared series debt). Snapshot
  form: BOM + LF; committed checkout form
  BOM+CRLF.

## [update-wsi-2026.08.02-r12.61] - 2026-08-07

Tag retained: `setupdu-baseline-language-preservation`.

### Added

- **`boot.stl` becomes PCA2023 conversion target #5**: Microsoft
  documents `EFI\Microsoft\Boot\boot.stl` as a required Secure Boot
  validation input for refreshed installation media, and an
  original-media copy left in place can still fail boot with
  `0xc0430001` even after the four r12.5x targets are converted. A
  new `Sync-Pca2023MediaBootStl` step refreshes the file from the
  serviced image, and P11 gains Target #5 rows that prove
  byte-identity against the authoritative serviced-image source —
  presence alone is explicitly NOT an acceptable gate, and a present
  file without identity evidence is reported as unproven rather than
  passed. Script-only change (+407 lines); `data/*` and `schema/*`
  are byte-identical to r12.60.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.61`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/161W/12I (raw sweep
  5E/162W/12I: +1W is the PSA7002 LF artefact; +15W on the new sync
  and verification code, declared series debt). Snapshot form: BOM + LF; committed checkout form BOM+CRLF.

## [update-wsi-2026.08.02-r12.60] - 2026-08-07

Tag retained: `setupdu-baseline-language-preservation`.

### Fixed

- **El Torito Sector Count 0/1 is honored as the UEFI end-of-media
  sentinel**: for platform-0xEF no-emulation entries, UEFI defines
  Sector Count 0 or 1 as a sentinel meaning the EFI System Partition
  extends from the image Load RBA toward the end of the medium — not
  a literal 0- or 512-byte image, and `oscdimg` emits Sector Count 1
  for Windows efisys images. r12.59 treated the field literally and
  rejected standards-compliant media before hashing the embedded
  image. Identity is now proven by hashing the expected efisys image
  length from the firmware-visible Load RBA (evidence schema
  `iso-el-torito-uefi/1.1` with explicit sentinel-interpretation
  fields); explicit Sector Count values above 1 keep the stronger
  catalog-extent lower-bound check. The r12.59 gains — Int64-safe
  parsing and P10 fail-closed — are retained. Script-only change
  (+22 lines); `data/*` and `schema/*` are byte-identical to r12.59.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.60`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/146W/12I (raw sweep
  5E/147W/12I: +1W is the PSA7002 LF artefact; +6W on the revised
  verification code, declared series debt). Snapshot form: BOM + LF; committed checkout form BOM+CRLF.

## [update-wsi-2026.08.02-r12.59] - 2026-08-07

Tag retained: `setupdu-baseline-language-preservation`.

### Fixed

- **The r12.58 El Torito verification is Int64-safe and P10 fails
  closed**: the r12.58 parser selected the correct `efisys_ex.bin`
  but clamped its read length through an Int32-bound `Math.Min`, so
  a real multi-gigabyte ISO (measured on an 8.91-GiB image) produced
  a false verification failure. The catalog read is now Int64-safe
  with an explicit truncated-catalog guard, and P10 fails CLOSED —
  the phase itself fails when the firmware-visible embedded image
  cannot be proven, instead of deferring the failure to P11 while
  reporting P10 done. Script delta +25 lines;
  `data/config-Server2025.json` value-level only (Notes sentence +
  `_meta.scriptVersion`) — no declared key changes.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.59`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/140W/12I (raw sweep
  5E/141W/12I: +1W is the PSA7002 LF artefact; +2W on the revised
  parser code, declared series debt). Snapshot form: BOM + LF; committed checkout form BOM+CRLF.

## [update-wsi-2026.08.02-r12.58] - 2026-08-07

Tag retained: `setupdu-baseline-language-preservation`.

### Fixed

- **The r12.57 PCA2023 boot failure is corrected at the El Torito
  layer**: the shared ISO assembly now binds the El Torito
  platform-0xEF (UEFI) boot entry to `efisys_ex.bin` for
  PCA2023-converted media, instead of letting the legacy `efisys.bin`
  remain wired into the boot catalog while only the loose files were
  converted. A new boot-catalog parser
  (`Get-IsoElToritoUefiBootImageEvidence`,
  `iso-el-torito-uefi/1.0` evidence) reads the ISO9660 boot catalog,
  extracts the UEFI boot image by LBA/sector count, and proves
  byte-identity against the expected efisys image; P11 gains a
  static-verification row backed by a `P11_uefi_el_torito.json`
  evidence file (`P11-static-verification/1.1`) and P12 consumes the
  same proof, so the class of failure r12.57 shipped (catalog and
  loose files disagreeing) is now caught before any boot attempt.
  Script delta +295 lines; `data/config-Server2025.json` changes at
  the value level only (the `Pca2023.Notes` sentence now describes
  the correction; `_meta.scriptVersion` stamp) — no declared key is
  added or removed.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.58`
  (the tag is retained). No terminal D-contract required an edit, and
  the two pins relocated at r12.57 remain green unchanged.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/138W/12I (raw sweep
  5E/139W/12I: +1W is the PSA7002 LF artefact). The +17W step versus
  r12.57 is concentrated in the new El Torito parser (PSA2009 rises
  from 1 to 17) and is carried as declared series debt per the
  no-fix-forward rule. Snapshot form: BOM + LF;
  committed checkout form BOM+CRLF via `.gitattributes`.
  (Supersedes the corresponding sentence in the r12.57 entry:
  the "mixed line endings" reading there was a measurement
  artifact; the archive snapshots measure pure BOM + LF.)

## [update-wsi-2026.08.02-r12.57] - 2026-08-07

Tag retained: `setupdu-baseline-language-preservation`.

### Changed

- **PCA2023 conversion becomes the Server 2025 default**: the single
  declared-surface change is a value-level policy flip on
  `data/config-Server2025.json` — `Pca2023.Mode` moves from
  `Firmware2023Default` to `ConvertByDefault`, `RequiredByDefault`
  from `false` to `true`, and `CompliancePolicy` from `AuditOnly` to
  `RequirePca2023`. No declared key is added or removed, so the
  terminal contract set and the derived gap timeline are unchanged.
  The script delta (−4 lines) sits entirely on the same axis: the
  `-ForcePca2023OnServer2025` switch is demoted to a deprecated
  compatibility slot whose only remaining consumer is an operator
  caution, the Server 2025 P10 documented-conversion-boundary skip
  gate is removed (default-on needs no gate), and the fallback
  compliance policy is `RequirePca2023` for every OS family.

### Known defect (carried verbatim; corrected at r12.58)

- Operator validation of media built from this revision found that
  the PCA2023-converted Server 2025 ISOs fail Hyper-V Generation 2
  UEFI boot (status `0xc0430001`) in both tested languages even
  though P11 and P12 report green: the shared ISO assembly helper
  still resolves the legacy `efisys.bin` as the El Torito UEFI boot
  image, so the boot catalog embeds the PCA2011 image while the
  loose media files are PCA2023 — firmware boots from the catalog,
  not from the loose files, and the static checks only inspected the
  loose files. This revision lands unmodified per the series rulings
  (the history is the deliverable; no fix-forward); the correction
  is the r12.58 revision.

### Tests

- **Two T39-style pin relocations** (both verified green at the
  r12.57 frame and re-verified at the r12.75 terminal frame):
  `pca2023_default_auto_test.py` replaces the retired force-gate
  presence pin with three successor pins (promotion of the switch
  into the Deprecated compatibility slot, the caution wiring on that
  slot, and the ABSENCE of the removed gate);
  `media_inspection_test.py` flips the Server 2025
  documented-conversion-boundary marker from a presence pin to an
  absence pin while retaining the operator opt-out marker, the two
  `Get-P10SkipReason` call sites and the BY-POLICY caution.
- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.57`
  (the tag is retained). No terminal D-contract required an edit.

### Distribution note

- The r12.57 snapshot ships its own regression additions (a Server
  2025 PCA-default PowerShell test, a static validator, a ja-jp
  PCA2023 fixture and a static validation summary) and edits its
  release-validation trio; these are input-only under the standing
  series ruling and are not committed.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/121W/12I (raw sweep
  5E/122W/12I: +1W is the PSA7002 LF artefact) — unchanged from
  r12.56. The r12.57 snapshot in the currently attached archive
  measures a UTF-8 BOM with mixed line endings (LF-dominant); the
  committed checkout form remains BOM+CRLF via `.gitattributes`
  normalization.

## [update-wsi-2026.08.02-r12.56] - 2026-08-02

Tag retained: `setupdu-baseline-language-preservation`.

### Added

- **Automatic per-invocation run transcript**: every invocation —
  including Resume preflight and Resume execution — starts a
  PowerShell transcript under `WorkRoot\logs`, so a failed or
  interrupted run always leaves a complete session record without
  the operator having to enable anything. A JSONL debug-trace file
  output can additionally be enabled for structured step tracing.
  The transcript wiring also covers the P12 PCA2023-readiness and
  P13 final-report phases. Script-only change (+36 lines); `data/*`
  and `schema/*` are byte-identical to r12.55.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.02-r12.56`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 5E/121W/12I (raw sweep
  5E/122W/12I: +1W is the PSA7002 LF artefact) — a fifth PSA error
  joins with the new debug-trace code (`PSA2001` undefined variable
  in `Enable-DebugTraceFileOutput`) and is carried as declared
  series debt per the no-fix-forward rule. The r12.56 snapshot in
  the currently attached source archive measures BOM + LF (the
  committed checkout form is BOM+CRLF via `.gitattributes`
  normalization).

## [update-wsi-2026.08.01-r12.55] - 2026-08-02

Tag: `setupdu-baseline-language-preservation`.

### Changed

- **Baseline language resources are preserved, not removed**: when
  the SOURCE media itself ships locale directories outside the
  r12.49 allowlist, those baseline-original resources are now
  recorded (`PreserveExistingLanguageResource` decisions;
  `BaselinePreservedDisallowedLocaleDirectories` and
  `BaselinePreservedDisallowedFiles` with per-file SHA-256 in the
  language-cleanup manifest) and kept on the media instead of being
  cleaned up — the allowlist governs what the OVERLAY may add, not
  what the vendor media already contained. Media without baseline
  language evidence retains the former strict behavior.
- **P11 verifies no-new-locale instead of allowlist-only**: the
  language-scope verification row now asserts that every observed
  disallowed locale directory is within the baseline-preserved set
  (nothing new was introduced by the overlay) and that each
  baseline-preserved file still exists with its recorded SHA-256.
  Script-only change; `data/*` and `schema/*` are untouched at this
  revision.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.55`
  with the measured tag `setupdu-baseline-language-preservation`.
  No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 4E/120W/12I (raw sweep
  4E/121W/12I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot form remains BOM + LF at r12.55.

## [update-wsi-2026.08.01-r12.54] - 2026-08-02

Tag: `setupdu-pinned-authority-handoff`.

### Changed

- **Pinned Catalog identity evidence handoff**: the P04 fetch phase
  records the pinned-identity basis and its verification state
  (`CatalogPinnedIdentityBasis`, `CatalogPinnedIdentityVerified`)
  into the resolved-patch manifest, and Setup DU package authority
  accepts a reviewed pinned identity as a first-class basis
  (`CatalogPinnedIdentityAndLocalHashVerified`) alongside the
  scraped-identity path — under pinned-identity mode the
  Search.aspx-scoped evidence is declared not required rather than
  silently absent.
- **P09 resume compatibility for pre-handoff evidence**: a resume
  over a build fetched at r12.53 recovers the reviewed pinned
  identity from the r12.53 P04 evidence
  (`LegacyR12.53PinnedIdentityRecovered` →
  `CatalogLegacyPinnedIdentityAndLocalHashVerified`), so pinned
  authority verification does not force a refetch across the
  revision boundary. Script-only change; `data/*` and `schema/*`
  are untouched at this revision.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.54`
  with the measured tag `setupdu-pinned-authority-handoff`. No
  terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21. PSA committed 4E/120W/12I (raw sweep
  4E/121W/12I: +1W is the PSA7002 LF artefact) — one PSA2002
  automatic-variable shadow left the error set with the reworked
  resume-manifest sites (5E → 4E; remaining findings stay declared
  series debt). The snapshot form remains BOM + LF at r12.54 (the
  CRLF half of the O1 oscillation is still ahead).

## [update-wsi-2026.08.01-r12.53] - 2026-08-02

Tag retained: `catalog-semantic-retry`.

### Changed

- **Pinned UpdateId resolution on the Server 2025 declaration**:
  `data/config-Server2025.json` lines carry reviewed pinned
  identities — `UpdateId`, exact file name, and SHA-1 (base64 and
  hex) — so `PinOs`/`PinAll` refresh modes resolve Catalog assets
  without depending on Search.aspx HTML discovery. This is a
  declared-surface change: T43 tracks it as 120 → 128 asserts,
  matching the convergence-matrix transition row for this revision
  (terminal D-totals reached: 139/37/128/64/21/112 = 501).
- **Parser-shape resilience and raw Catalog evidence capture**:
  Catalog search, UpdateId and download-link parsing tolerate
  page-shape variation, and the raw response is captured as
  transport evidence alongside the parse result, extending the
  r12.51/r12.52 transport hardening.

### Fixed

- **Canonical `.ps1` BOM restored** (O1 watch closure, first half):
  the snapshot script regains the UTF-8 BOM at this revision — the
  measured snapshot form is BOM + LF — so the committed checkout
  form returns to BOM+CRLF under `.gitattributes` normalization and
  the PSA7001 (missing BOM) debt carried since r12.10 clears. The
  CRLF half of the oscillation returns at a later revision (the
  snapshot form is BOM+CRLF by r12.56).

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.53`
  (the tag is retained). No terminal D-contract required an edit:
  the T43 total moves with the declaration.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/128/64/112 + T45 21 (T43 120 → 128, matrix match). PSA
  committed 5E/120W/12I (raw sweep 5E/121W/12I: +1W is the PSA7002
  LF artefact; PSA7001 no longer fires; declared series debt).

## [update-wsi-2026.08.01-r12.52] - 2026-08-02

Tag: `catalog-semantic-retry`.

### Changed

- **Catalog semantic-response retry**: the Catalog can answer
  HTTP 200 with a temporary landing/error/challenge page instead of
  the requested content. Such responses are now detected as
  semantically invalid and treated as transient — retried under the
  shared escalating transport schedule from r12.51 — and only a
  transport- and semantic-validated response is cached; a
  semantically invalid cache entry is discarded before the retry.
- **Single-fetch fallback hardening**: the last-resort search
  parser and the download-link fallback reuse the SAME validated
  HTML / DownloadDialog response as the primary path instead of
  repeating the request through independent fixed-timeout code
  paths, so every parser sees one consistent, validated page.
  Script-only change; `data/*` and `schema/*` are untouched at this
  revision.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.52`
  with the measured tag `catalog-semantic-retry`. No terminal
  D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 5E/113W/11I (raw sweep
  5E/114W/11I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot script remains BOM-absent at r12.52 (O1 watch
  continues).

## [update-wsi-2026.08.01-r12.51] - 2026-08-02

Tag retained: `setupdu-language-allowlist`.

### Added

- **Catalog transport hardening**: a centralized, deterministic
  retry policy for Microsoft Update Catalog requests — escalating
  timeout schedule (60/120/180 s) with fixed retry delays — so a
  transient Catalog timeout cannot terminate a multi-hour build
  before any asset is modified. Each transport attempt is recorded
  as evidence under the logs directory, and the Catalog POST path
  now sends the same pinned request headers as the page-fetch path.
- **Pinned monthly-auxiliary identity under `PinOs`**: the
  Server 2025 contract (advanced to `-r7`) declares
  `Discovery.MonthlyAuxiliaryIdentityPolicy`
  (`PinnedKbExactAssetWhenPinOs`). When the effective patch-refresh
  mode is `PinOs`, SafeOS DU and Setup DU resolution queries the
  Catalog by the exact pinned KB identity and fails closed if the
  pinned KB is absent from the scoped result or resolves no x64
  asset; the decision evidence records the selection mode
  (`pinned-kb-exact-asset` vs `same-month-or-latest-prior`).

### Changed

- **Servicing-contract baselines advanced**: schema `2.5` → `2.6`;
  the Server 2025 contract revision `-r6` → `-r7` with re-pinned
  component hashes (declared change; the other three contracts are
  unchanged; T45 totals unchanged at 21).

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.51`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 5E/113W/11I (raw sweep
  5E/114W/11I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot script remains BOM-absent at r12.51 (O1 watch
  continues).

## [update-wsi-2026.08.01-r12.50] - 2026-08-02

Tag retained: `setupdu-language-allowlist`.

### Changed

- **Server 2025 contract hardened to parity** (`-r5` → `-r6`,
  baselines schema `2.4` → `2.5`; the other three contracts are
  unchanged): the boot.wim declaration flips
  `SmokeTestRequired` to `true`, and the `Setup` declaration gains
  the same package-authority trio Server 2022 received at r12.47
  (`SameVersionDifferentContentPolicy=ApplyTrustedPackagePayload`,
  `PackageAuthorityPolicy=CatalogScopedIdentityAndLocalHash`,
  `RequireTrustedPackage=true`) alongside the existing language
  allowlist. Script delta is the contract declaration only.
- **E2E baselines add the language-compliant Server 2022 cases**:
  `data/servicing-e2e-baselines.json` schema `1.2` → `1.3`; new
  `Server2022-ja-jp` and `Server2022-en-us` cases record the r12.49
  static builds as language-compliant
  (`CompliantEnUsAndTargetOnly`), with user-confirmed Hyper-V
  Generation 2 Secure Boot and complete installation, measured
  builds 20348.5386 and P11/P06/operation-evidence counts. The
  superseded `Server2022-ja-jp-r12.48` case is retained for audit
  history.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.08.01-r12.50`
  (the tag is retained). No terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 5E/112W/10I (raw sweep
  5E/113W/10I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot script remains BOM-absent at r12.50 (O1 watch
  continues).

## [update-wsi-2026.07.31-r12.49] - 2026-08-02

Tag: `setupdu-language-allowlist`.

### Added

- **Setup DU language-resource allowlist**: every per-OS servicing
  contract now declares `Setup.LanguageResourcePolicy`
  (`EnUsAndTargetOnly`) — the allowed Setup DU language directories
  are en-us plus the target media language. The overlay records a
  `SkipLanguageResource` decision for package payloads outside the
  allowlist, and disallowed locale directories already present on the
  media are cleaned up only when their content can be safely
  attributed to a prior verified overlay; unattributable content
  fails closed before the media is touched.
- **P11 verifies the language scope**: new
  `SetupDuLanguageResourceAllowlist` verification row (observed
  locale directories must all be within the declared allowlist) and
  the `SetupDuFinalManifest` row additionally proves excluded
  language files are absent, driven by the overlay manifest's
  `Policy.AllowedLanguageDirectories`.

### Changed

- **Servicing-contract baselines advanced**: schema `2.3` → `2.4`;
  all four contract revisions move (Server 2016/2019 `-r4` → `-r5`,
  Server 2022 `-r5` → `-r6`, Server 2025 `-r4` → `-r5`) with
  re-pinned component hashes (declared change; T45 totals unchanged
  at 21).
- **E2E baselines record the language-scope supersession**:
  `data/servicing-e2e-baselines.json` schema `1.1` → `1.2`; the four
  existing cases carry `SetupDuLanguageScopeStatus`
  `SupersededByR1249LanguageAllowlist`, and a new
  `Server2022-ja-jp-r12.48` case records the r12.48 static build as
  passed under pre-r12.49 checks but language-scope non-compliant
  (`RequiresR1249P09Repair`).

### Tests

- **T40**: release pin advanced to `update-wsi-2026.07.31-r12.49`
  with the measured tag `setupdu-language-allowlist`. No terminal
  D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 5E/112W/10I (raw sweep
  5E/113W/10I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot script remains BOM-absent at r12.49 (O1 watch
  continues).

## [update-wsi-2026.07.31-r12.48] - 2026-08-02

Tag: `server2022-setupdu-resume-hash`.

### Changed

- **Setup DU expected-hash resolution widened and provenance-tagged**:
  `Get-SetupDuPackageAuthority` now resolves the expected SHA-256
  from an ordered set of provenance sources — `Patch.Integrity.Sha256`,
  the `ExpectedHashes` dictionary, asset-metadata evidence, and the
  resume manifest's `LocalAssetSha256` — and records which source
  supplied the value (`ExpectedSha256Source`, plus the resume
  manifest evidence path) in the authority evidence, so a hash match
  is auditable back to where the expectation came from.
- **Resume rehydration keeps the digest chain**: resumed runs persist
  the measured `LocalAssetSha256` (with source
  `ResumePriorManifestVerified`) back into the resume patch state
  (schema `resume-patch-state/1.2`), keeping the Setup DU authority
  check independently auditable across a resume boundary. Script-only
  change; `data/*` and `schema/*` are untouched at this revision.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.07.31-r12.48`
  with the measured tag `server2022-setupdu-resume-hash`. No terminal
  D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 5E/110W/10I (raw sweep
  5E/111W/10I: +1W is the PSA7002 LF artefact). A fifth PSA error
  joins at this revision — `PSA2002` (shadowing the automatic
  variable `$matches`) at the resume-manifest repair site — and is
  carried as declared series debt per the no-fix-forward rule. The
  snapshot script remains BOM-absent at r12.48 (O1 watch continues).

## [update-wsi-2026.07.31-r12.47] - 2026-08-02

Tag: `server2022-setupdu-authority`.

### Added

- **Setup DU package authority for Server 2022**: the Server 2022
  servicing contract (advanced to `-r5`) extends its `Setup`
  declaration with `SameVersionDifferentContentPolicy`
  (`ApplyTrustedPackagePayload`), `PackageAuthorityPolicy`
  (`CatalogScopedIdentityAndLocalHash`) and
  `RequireTrustedPackage=true`. New helpers
  `Get-SetupDuOverlayPolicy` and `Get-SetupDuPackageAuthority`
  establish package authority before an overlay: patch type, KB id,
  UpdateId, trusted source host, local SHA-256 and catalog-scoped
  identity must all verify, and the result is written as
  `setupdu-package-authority/1.0` evidence. When source and
  destination report the same file version but differing SHA-256,
  the trusted package payload is applied under the declared policy;
  if authority cannot be established the overlay fails closed before
  touching the media.

### Changed

- **Servicing-contract baselines advanced**: schema `2.2` → `2.3`;
  the Server 2022 contract revision `-r4` → `-r5` with re-pinned
  component hashes (declared change; the other three contracts are
  unchanged at `-r4`; T45 totals unchanged at 21).

### Tests

- **T40**: release pin advanced to `update-wsi-2026.07.31-r12.47`
  with the measured tag `server2022-setupdu-authority` (the tag
  changed at this revision after being retained since r12.44). No
  terminal D-contract required an edit.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 4E/110W/10I (raw sweep
  4E/111W/10I: +1W is the PSA7002 LF artefact; declared series
  debt). The snapshot script remains BOM-absent at r12.47 (O1 watch
  continues).

## [update-wsi-2026.07.30-r12.46] - 2026-08-02

Tag retained: `safeos-p11-metadata-contract-isolation-stage1`.

### Changed

- **LCU evidence is declaration-driven**: each per-OS servicing
  contract (advanced to `-r4`) now declares
  `Verification.LcuEvidenceMode` — `RollupFixAndMeasuredBuild` on the
  Server 2016 contract, `MeasuredBuild` on Server 2019/2022/2025 —
  and `Test-LcuTargetApplied` reads the declared mode from the
  contract under test (defaulting to `MeasuredBuild` when absent)
  instead of branching on a per-OS KB-identity fork. Under
  `RollupFixAndMeasuredBuild`, package, registry and kernel evidence
  must each reach the expected build; failures are reported
  per-source.
- **Server 2016 LCU authority corrected**: the authoritative
  cumulative-update package on 14393 is `Package_for_RollupFix`
  (build parsed from the package name), while KB-named packages
  remain standalone SSU/prerequisite evidence and are never treated
  as the LCU identity — selecting the highest KB-named package could
  mislabel the SSU as the LCU (observed with KB5099542 / KB5099535).
  The evidence object gains `LcuEvidenceMode`, `RelatedKbIds` and
  `RelatedKbPackageNames` so related KB packages stay visible without
  claiming LCU authority.
- **boot.wim compatibility smoke test generalized**: the
  Server 2019-specific wording in the P06 smoke-test decision and
  step messages is replaced by contract-driven text keyed on the
  selected OS, preparing the same gate for the other OS families
  without behavioural change where the contract does not require the
  test.
- **Servicing-contract baselines advanced**:
  `data/servicing-contract-baselines.json` schema `2.1` → `2.2`; all
  four per-OS contract revisions `-r3` → `-r4` with re-pinned SHA-256
  component hashes (declared change tracking the `LcuEvidenceMode`
  addition; T45 totals unchanged at 21).
- **E2E baselines advanced to the r12.45 static builds**:
  `data/servicing-e2e-baselines.json` schema `1.0` → `1.1`; all four
  cases (Server 2016 ja-jp/en-us, Server 2019 en-us/ja-jp) carry
  r12.45 static-build evidence — statuses upgraded, output ISO
  SHA-256 values re-pinned, four-part servicing-stack versions, and
  measured P11/P06/operation-evidence counts. The Server 2016 en-us
  case moves from `PendingE2E` to `R1245StaticBuildValidated`.

### Tests

- **T40**: release pin advanced to `update-wsi-2026.07.30-r12.46`
  (the tag is retained). No terminal D-contract required an edit for
  this revision: the `-r4` contract advance is absorbed by
  declaration reading (measured pass-through on the contract axis).

### Distribution note

- The r12.46 distribution ships its own validation additions
  (`tests/Test-R1246Server2016LcuEvidenceAndServer2022Readiness.ps1`,
  `tests/validate_r1246_static.py`,
  `validation-summary-r12.46.json`, and the R12.46 analysis /
  test-plan / validation-report documents). Per the standing ruling
  these are input-only and are not committed in-series.

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 4E/109W/10I (raw sweep
  4E/110W/10I: +1W is the PSA7002 LF artefact; declared series debt
  per the no-fix-forward rule). The snapshot script remains
  BOM-absent at r12.46 (the O1 watch for the BOM-return revision
  continues).

## [update-wsi-2026.07.29-r12.45] - 2026-08-02

Tag retained: `safeos-p11-metadata-contract-isolation-stage1`.

### Added

- **Servicing-contract role-target layer**: patch routing is now read
  from the per-OS servicing contract's declared `RoleTargets` map
  instead of type-keyed code paths. New helpers
  `Get-ServicingContractRoleTargets` and `Get-PatchTargetsForRole`
  resolve a canonical role (e.g. `CheckpointDependency`, `FinalLCU`)
  to its declared target set; `Test-PatchPlanAgainstServicingContract`
  validates a built plan against the declaration; contract identity is
  hashable via `Get-CanonicalObjectSha256` /
  `Get-ServicingContractHash` /
  `Get-ServicingContractComponentHashes`. Measured Server 2025
  routing under the declaration: a Checkpoint entry targets
  Install/Boot/WinRE and the final LCU targets Install/Boot.
- **`data/servicing-e2e-baselines.json`** (new file, landed by
  per-path adjudication): compact measured E2E baseline records for
  four OS/language cases (Server 2016 ja-jp/en-us, Server 2019
  en-us/ja-jp) — status, implementation baseline, output ISO SHA-256
  where captured, measured install/boot builds and boot update model.
  No ISO/WIM payloads are embedded; the records do not replace
  Windows E2E execution after shared-core changes.

### Changed

- **Servicing-contract baselines advanced**:
  `data/servicing-contract-baselines.json` schema
  `servicing-contract-baselines/1.0` → `2.1`; all four per-OS
  contract revisions `-r1` → `-r3` with re-pinned SHA-256 component
  hashes (declared change; T45 17 → 21 asserts, matrix match).
- **KB-identity evidence guard is declaration-driven**: the P11
  generic `Kb_<id>` presence rows are now gated by the contract's
  declared `Verification.KbIdentityEvidenceMode`
  (`Server2016InstallSsu` on the Server 2016 contract; `None` on the
  other three) instead of the `OsVersion -eq 'Server2016'` literal.

### Tests

- **T32 routing rows re-located to the declaration (T39-type event
  #3, user-adjudicated)**: the `checkpoint_placement_test.py` routing
  pins encoded the pre-r12.45 model (Checkpoint routed nowhere;
  Install carries the LCU alone). Measured at the r12.46/r12.56/r12.57
  frames, the new routing persists to the series terminal, so the
  pins were revised to read the declared `RoleTargets` from the
  contract under test and derive the expected slices (membership and
  ApplyOrder), never hardcoding per-OS targets. 15 asserts.
- **`media_inspection_test.py` Kb_-guard row follows the declared
  mode**: asserts the single `Kb_` row site sits behind the declared
  `KbIdentityEvidenceMode` check and that only the Server 2016
  contract declares `Server2016InstallSsu` (the other three declare
  `None`). 31 asserts.
- **T40**: release pin advanced to `update-wsi-2026.07.29-r12.45`
  (the tag is retained).

### Gate state

- Offline suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 21. PSA committed 4E/109W/10I (raw sweep
  4E/110W/10I: +1W is the PSA7002 LF artefact; declared series debt
  per the no-fix-forward rule).

## [update-wsi-2026.07.29-r12.44] - 2026-08-02

ScriptTag advanced to `safeos-p11-metadata-contract-isolation-stage1`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Per-OS servicing contracts with hash enforcement**: four contract
  constructors (`New-Server2016/2019/2022/2025ServicingContract`) and
  `Assert-AllServicingContractBaselines`; the new
  `data/servicing-contract-baselines.json`
  (`servicing-contract-baselines/1.0`, four `-r1` contract revisions
  with canonical SHA-256 component hashes) fails the build closed on
  any undeclared contract change. The file landed by per-path
  adjudication; T45 converges NOT-YET -> 17 asserts as scheduled
  (matrix match).

### Tests

- **T40**: release pin advanced to `update-wsi-2026.07.29-r12.44`
  with the new tag.

### Gate state

- Suite 25/26 (the declared T30 red only). D-contract totals
  139/37/120/64/112 + T45 17. PSA committed 4E/106W/10I (raw +1W =
  PSA7002 LF artefact; declared series debt per the no-fix-forward
  rule).

## [update-wsi-2026.07.29-r12.43] - 2026-08-02

Tag retained: `all-os-version-decision-hardening` (the version date component moves to 07.29).
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Fail-closed SafeOS-DU boot.wim verification decision**: the
  boot.wim verification requires a `Package_for_SafeOSDU` identity at
  or above the expected SafeOS version with no pending packages; the
  full-LCU verification contract is not applied under the SafeOSDU
  model. Script-only change.

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 139/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/103W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.28-r12.42] - 2026-08-02

Tag retained: `all-os-version-decision-hardening`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Changed

- **Server 2019 boot.wim update model declared as SafeOSDU**:
  `config-Server2019.json` declares `BootWimUpdateModel` SafeOSDU and
  the standalone ServicingStack step is dropped from the 2019
  boot.wim plan (declared change; T41 140 -> 139 asserts, matrix
  match).

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 139/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/103W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.28-r12.41] - 2026-08-02

Tag retained: `all-os-version-decision-hardening`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Boot.wim smoke-test mount forensics (evidence 1.1)**: the P06
  smoke test records a staged narrative marker, attribute/read-only
  tracking and explicit per-index DISM mount logs, so a mount-side
  failure leaves an attributable record. Script-only change.

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 140/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/102W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.28-r12.40] - 2026-08-02

Tag retained: `all-os-version-decision-hardening` (the version date component moves to 07.28).
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Mandatory Server 2019 boot.wim pre-servicing smoke test**: P06
  exercises the LCU against an isolated copy/mount of boot.wim before
  the real servicing pass (mandatory for Server 2019 with
  `BootWimLcuPolicy=enabled`); evidence schema
  `P06-bootwim-servicing-smoke-test/1.0`. Script-only change; one
  declared PSA warning is resolved by the deliverable.

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 140/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/102W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.27-r12.39] - 2026-08-02

Tag retained: `all-os-version-decision-hardening`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Changed

- **P11 setup-binary verification prefers the post-overlay digest**:
  verification consumes `ExpectedSha256After` from the SetupDU
  overlay evidence (the `setupdu-overlay/1.x` fallback is retained;
  an empty expectation fails). Script-only change.

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 140/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/103W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.27-r12.38] - 2026-08-02

Tag retained: `all-os-version-decision-hardening`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Server 2016 SSU state detection filesystem fallback**:
  `Get-OfflineServicingStackFilesystemState` supplies the active
  servicing stack from the component directory when package identity
  does not surface it (measured Server 2016 case); the evidence rows
  record the source column
  (`offline-servicing-stack-filesystem-state/1.0`). Script-only
  change.

### Tests

- **T40**: release pin advanced (the tag is retained).

### Gate state

- Suite 25/26 (T30 declared). D-totals 140/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/103W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.27-r12.37] - 2026-08-02

ScriptTag advanced to `all-os-version-decision-hardening`.
(Backfilled 2026-08-02: this revision's commit landed without its
CHANGELOG entry; authored from the landed commit and the measured
gate records.)

### Added

- **Fail-closed patch version-decision pipeline**: a 27-helper layer
  makes every patch-version decision explicit and evidence-backed —
  downgrade rejection, `ManualReviewRequired` escalation,
  version-aware SetupDU overlay, and `patch-version-decision/1.0`
  evidence records.

### Changed

- **Declared vocabulary migration**: `VersionDecisionPolicy` /
  `Lines[].VersionPolicy` join schema v4 and all configs (declared
  change; T42 30 -> 37 asserts, matrix match). Snapshot overlay:
  script + five configs + schema.

### Tests

- **T40**: release pin advanced with the new tag.

### Gate state

- Suite 25/26 (T30 declared). D-totals 140/37/120/64/112 + T45
  NOT-YET. PSA committed 4E/102W/10I (raw +1W = PSA7002).

## [update-wsi-2026.07.26-r12.36] - 2026-08-02

Revision r12.36 carries two independent delivered works under one
revision number (series ruling: two commits, one CHANGELOG heading).

Part 1 — tag: `server2019-bootwim-hresult-policy-fix`.
Part 2 — tag: `offline-servicing-failure-forensics` (the version date
component moves 07.26 → 07.27 within the same revision number).

### Fixed

- **Boot.wim failure policy decides on the HRESULT, not localized
  text**: DISM exceptions for cases like `0x80070032` can carry only
  a localized message while the machine-readable `HResult` remains on
  the exception; a new `Get-ExceptionDiagnosticText` helper renders
  the unsigned `HRESULT=0x…` alongside the message, the P08 boot.wim
  failure decision consumes that diagnostic, and the policy exception
  is recorded as a structured `bootwim-policy-exception` JSONL entry
  (type, message, diagnostic, image, policy, strategy, error code,
  install-validation flag). Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.26-r12.36`
  with the measured tag (part 1), then to
  `update-wsi-2026.07.27-r12.36` (part 2).

### Added (part 2)

- **Offline servicing failure forensics**: four new helpers
  (`Copy-ServicingEvidenceFile`, `Copy-ServicingLogTailEvidence`,
  `Export-OfflineServicingFailureEvidence`,
  `Export-ExpandedMsuMetadataEvidence`) capture a forensics bundle on
  offline-servicing failure — DISM/CBS log tails, expanded-MSU
  metadata and related evidence files are copied with verification
  into the evidence tree, so a failed servicing run leaves an
  analyzable record instead of only an error line. Script-only
  change.

### Gate state (measured on the branch, after both parts)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged across both parts).
PSA **2E/94W/9I** after part 1 and **2E/95W/9I** after part 2 — one
warning joins the debt with the forensics layer; committed verbatim
per the no-fix-forward rule.

## [update-wsi-2026.07.26-r12.35] - 2026-08-02

Tag: `resume-checkpoint-evidence-hardening` (the tag advances; the
version date component moves 07.25 → 07.26). Resume becomes a
verified, checkpointed evidence transaction.

### Changed

- **Resume checkpoint/evidence layer**: twenty new helpers build a
  session-scoped resume transaction — critical evidence files are
  enumerated by relative path, copied with per-file verification,
  backed up into an `evidence-history` under the session root, and
  tree manifests (`Get-ResumeTreeManifest` /
  `Test-ResumeTreeManifestMatch`) prove checkpoint integrity.
  Media checkpoints (`New-ResumeMediaCheckpoint`), downstream-state
  reset, verified transaction backups and
  `Ensure-P08FinalInstallWimEvidenceForResume` make P08/P09 resume a
  fail-closed, evidence-bound operation with a recorded session
  action log. Script-only change (+737 net lines).
- **T40**: release pin advanced to `update-wsi-2026.07.26-r12.35`
  with the measured tag. The P08S wiring pin (a token-count proxy) is
  updated 4 → 5 lists by adjudication: the resume layer legitimately
  adds a fifth `'P08','P08S',…` site (the downstream-cleanup prefix
  list); the four original lists are intact and the count is measured
  stable at 5 through the series terminal.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **2E/94W/9I** on
the committed tree — the deliverable resolves three long-standing
errors (two PSA2012 positional `Save-CanonicalJsonFile` calls and the
PSA2013 never-assigned read); the remaining errors are one PSA2012
and the PSA2010 `Resolve-OscdimgPath` forward reference. Five
warnings and one info join the debt; committed verbatim per the
no-fix-forward rule.

## [update-wsi-2026.07.25-r12.34] - 2026-08-02

Tag: `rawxml-filetime-conversion-regression-fix` (the tag is
retained). The resolved-patch manifest gains a resume-safe lifecycle.

### Fixed

- **Resume-manifest lifecycle**: `resolved_patch_manifest.json`
  (schema `release-patch-manifest/1.3`) is persisted as soon as P04
  has verified all payloads — previously it was written late enough
  that a P11 failure made P09 resume impossible. Three new helpers
  carry the lifecycle: `Write-ResolvedPatchEvidenceManifest`
  (early persistence), `Repair-ResolvedPatchManifestForResume`
  (rebuilds a missing manifest from measured evidence without
  trusting mutable state) and `Get-CatalogPayloadSha1FromFileName`
  (recovers the expected digest from the Catalog payload naming
  convention `_<40-hex-SHA1>.cab/.msu`). Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.25-r12.34`
  (tag retained per the deliverable).

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/89W/8I** on
the committed tree — fourteen warnings join the debt; committed
verbatim per the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.25-r12.33] - 2026-08-02

Tag: `rawxml-filetime-conversion-regression-fix` (the tag is
retained). Display-date persistence is verified on the final media
WIM, not only the servicing workspace copy.

### Fixed

- **Final-WIM evidence boundary**: four new helpers
  (`Test-WimIntegrityTableAgainstFile`,
  `Test-InstallWimDisplayDatePersistence`,
  `Test-InstallWimFinalEvidenceBinding`,
  `New-InstallWimFinalMetadataEvidence`) bind the display-date
  evidence to the final install.wim as placed on the media — the
  final snapshot must carry the P07-serviced index set without
  duplicates, the persisted CREATIONTIME values must match the
  requested transition, and the integrity table is re-validated
  against the final file bytes. Evidence of the servicing-workspace
  copy alone no longer counts as persistence proof. Script-only
  change.
- **T40**: release pin advanced to `update-wsi-2026.07.25-r12.33`
  (tag retained per the deliverable).

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/75W/8I** on
the committed tree — two warnings join the debt; committed verbatim
per the no-fix-forward rule.

## [update-wsi-2026.07.25-r12.32] - 2026-08-02

Tag: `rawxml-filetime-conversion-regression-fix` (the tag is
retained). The native preflight stops assuming a full-inventory
snapshot.

### Fixed

- **Subset-inventory consistency check**: a new
  `Test-WimInventorySnapshotConsistency` helper validates the
  display-date snapshot against the before/after WIM inventories when
  only a subset of image indexes is serviced — requested indexes must
  be non-empty and duplicate-free, and before/after inventories must
  agree on the index set outside the snapshot. The r12.29 preflight
  implicitly assumed the snapshot covered every image index.
  Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.25-r12.32`
  (tag retained per the deliverable).

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/73W/8I** on
the committed tree — unchanged from r12.31; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.25-r12.31] - 2026-08-02

Tag: `rawxml-filetime-conversion-regression-fix` (the tag is
retained). Runtime-validation identity revision.

### Changed

- **PowerShell 7 runtime validation recorded**: a validation marker
  states the r12.30 FILETIME layer as
  pwsh7-runtime-validated (PowerShell 7.6.4, Linux x64), with
  Windows-native gates still required; revision-anchored comments
  advance. Script-only identity/annotation revision (+1 net line);
  no behavioural change.
- **T40**: release pin advanced to `update-wsi-2026.07.25-r12.31`
  (tag retained per the deliverable).

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/73W/8I** on
the committed tree — unchanged from r12.30; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.25-r12.30] - 2026-08-02

Tag: `rawxml-filetime-conversion-regression-fix` (the tag advances;
the version date component moves 07.24 → 07.25). The raw-XML FILETIME
split stops relying on a PowerShell hex-literal cast.

### Fixed

- **FILETIME low/high split via `BitConverter`**: the r12.29 path
  cast an unsuffixed all-bits hexadecimal mask, which PowerShell
  parses as signed Int32 `-1` before the UInt64 cast — corrupting the
  HIGHPART/LOWPART split. The conversion now takes the `Int64`
  `ToFileTimeUtc()` value (rejecting pre-1601 dates), splits it
  through `BitConverter` byte access, requires a little-endian host,
  and a new `Test-WimFileTimeConversionRoundTrip` self-check verifies
  the round trip before any write. Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.25-r12.30`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/73W/8I** on
the committed tree — one warning joins the debt; committed verbatim
per the no-fix-forward rule.

## [update-wsi-2026.07.24-r12.29] - 2026-08-02

Tag: `rawxml-creationtime-integrity-integration` (the tag advances;
the version date component moves 07.21 → 07.24). The display-date
write moves off WIMGAPI onto a raw XML-resource strategy with
integrity-table recalculation.

### Changed

- **Raw XML CREATIONTIME strategy**: measured runs showed WIMGAPI
  write calls returning success without persisting the requested
  value, so the display-date transition now edits the WIM's raw XML
  resource directly — a 21-helper layer parses the WIM header and
  resource descriptors, rewrites CREATIONTIME values while preserving
  layout (byte length, encoding, BOM, terminators, descriptors and
  LASTMODIFICATIONTIME untouched), always recalculates an existing
  integrity table (`New-WimIntegrityTableBytes` over the changed byte
  ranges), and then verifies the reopened WIM through WIMGAPI, DISM
  and a read-only mount preflight. Fail-closed guards refuse
  multi-part WIMs, `WRITE_IN_PROGRESS` headers and malformed
  integrity structures. WIMGAPI remains for reread verification only.
  Script-only change (+1,149 net lines).
- **T40**: release pin advanced to `update-wsi-2026.07.24-r12.29`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/72W/8I** on
the committed tree — sixteen warnings join the debt with the raw-WIM
byte layer; committed verbatim per the no-fix-forward rule, draining
post-series.

## [update-wsi-2026.07.21-r12.28] - 2026-08-02

Tag: `wimgapi-utf16le-creationtime-displaydate-fix` (the tag advances;
the version date component moves 07.20 → 07.21). The display-date
layer targets the measured field with the API's required encoding.

### Fixed

- **Display date targets CREATIONTIME, written as BOM-prefixed
  UTF-16LE**: measured behaviour corrected two r12.26 assumptions —
  (1) Windows displays the CREATIONTIME date for the tested Server
  media even when LASTMODIFICATIONTIME already reflects the change,
  so the display-date transition now sets CREATIONTIME
  (`Set-WimImageCreationTimeXml`); (2) `WIMSetImageInformation`
  rejects a re-serialized Unicode string without the UTF-16LE BOM
  (Win32 error 203), so the XML round-trip now goes through
  BOM-prefixed UTF-16LE buffers (`Get-WimUnicodeXmlFromHandle`,
  `ConvertTo-WimUnicodeXmlBuffer`, `Set-WimUnicodeXmlOnHandle`) with
  a native preflight (`Invoke-WimDisplayDateNativePreflight`).
  Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.21-r12.28`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/56W/8I** on
the committed tree — two warnings join the debt; committed verbatim
per the no-fix-forward rule.

## [update-wsi-2026.07.20-r12.27] - 2026-08-02

Tag: `wimgapi-image-root-localname-hotfix` (the tag advances). The
r12.26 WIM image-XML root check is made adapter-safe.

### Fixed

- **WIM image XML root check uses `LocalName`**: PowerShell's XML
  adapter is case-insensitive, so on WIM IMAGE XML a child `<NAME>`
  element can shadow `XmlElement.Name`; the r12.26 root check
  (`.Name -ne 'IMAGE'`) could therefore reject valid metadata. The
  check now reads the unambiguous CLR `LocalName` property.
  Script-only hotfix to the r12.26 layer.
- **T40**: release pin advanced to `update-wsi-2026.07.20-r12.27`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/54W/8I** on
the committed tree — unchanged from r12.26; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.20-r12.26] - 2026-08-02

Tag: `install-wim-display-date-metadata-and-p14-evidence` (the tag
advances). Serviced install.wim indexes can carry an operator-declared
display date, applied through the WIM API with invariant-fingerprint
evidence.

### Added

- **`-ImageDisplayDate` parameter and WIM metadata layer**: thirteen
  new helpers (WIM API interop initialisation, per-handle image XML
  get/set, `ConvertTo`/`ConvertFrom-WimFileTimeParts`,
  invariant-fingerprint capture, metadata snapshot/transition
  validation and the `Resolve-InstallWimDisplayDateDecision` driver)
  set the display last-modification date on serviced install.wim
  indexes (`yyyy-MM-dd`, format-validated at entry). The transition
  is evidence-gated: a metadata-invariant fingerprint proves that
  only the display date moved, and the before/after snapshot joins
  the P14 evidence surface. Script-only change (+552 net lines).
- **T40**: release pin advanced to `update-wsi-2026.07.20-r12.26`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (unchanged). PSA **5E/54W/8I** on
the committed tree — five warnings and one info join the debt with
the new WIM interop layer; committed verbatim per the no-fix-forward
rule, draining post-series.

## [update-wsi-2026.07.20-r12.25] - 2026-08-02

Tag: `measured-e2e-os-specific-servicing-and-catalog-rehydration` (the
tag advances; the version date component moves 07.19 → 07.20).
Measured-E2E corrections to per-OS boot.wim servicing, declared in the
schema.

### Changed

- **Boot.wim servicing declared per OS**: four new resolver/decision
  helpers (`Resolve-BootWimFailurePolicyValue`,
  `Resolve-BootWimServicingStrategyValue`,
  `Get-BootWimFailurePolicyDecision`, `Get-BootWimServicingStrategy`)
  consume a widened declaration — `schema/config.schema.v4.json`
  constrains the failure-policy fields to enumerated values
  (`enabled/disabled/tolerate`; reason codes `FailBuild`,
  `UnsupportedByPinnedSourceMedia`,
  `ResearchTolerateNotReleaseEligible`, `LegacyPolicy`) and adds a
  `BootWimServicingStrategy` enum. `config-Server2019.json` declares
  `BootWimServicingStrategy: ExpandedCombinedCab`.
- **Stale pre-download digest removed, Catalog rehydration**
  (`config-Server2025.json`): a pre-download SHA-256 that failed a
  measured P04 run is removed (`Sha256: null`); the mutable candidate
  rehydrates the Catalog SHA-256 after stable-identity selection
  (declared in the line's Notes). T43 tracks the declaration:
  123 → 120 asserts per its declaration-derived count, matching the
  convergence-matrix row for this revision.
- **T40**: release pin advanced to `update-wsi-2026.07.20-r12.25`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/120/64/112 with T45 NOT-YET (T43 moves with the declaration —
a declared change, not a regression). PSA **5E/49W/7I** on the
committed tree — one warning joins the debt; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.19-r12.24] - 2026-08-02

Tag: `evidence-audit-and-pca2023-verdict-provenance` (the tag
advances). PCA2023 verdicts carry their measurement provenance.

### Changed

- **PCA2023 verdict provenance**: the signature-evidence record is
  widened to state how each verdict was reached — X.509 chain fields
  (`X509IsPca2023` / `X509IsPca2011`) are kept distinct from parsed
  signtool embedded-signature provenance (`Embedded*`), and boot-file
  verdicts carry a `BootX64VerdictMethod`. An audit consumer can now
  distinguish a chain-derived verdict from an embedded-signature one
  instead of reading a single collapsed boolean. Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.19-r12.24`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **5E/48W/7I** on
the committed tree — unchanged from r12.23; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.19-r12.23] - 2026-08-02

Tag: `resume-automatic-variable-safety` (the tag advances). The resume
path stops colliding with PowerShell automatic variables and gains a
non-destructive preflight.

### Added

- **`-ResumePreflightOnly` switch**: validates an existing P08/P09
  resume workspace and rehydrates all measured state without mutating
  anything (requires `-ResumeFromPhase P08|P09`); resume is refused
  when neither the P08 boot.wim transaction backup nor the source ISO
  is available.

### Fixed

- **Automatic-variable collision removed**: a resume-path local that
  collided with the read-only automatic variable `$Host` is renamed
  (one PSA2002 shadowing warning resolved by the deliverable).
- **T40**: release pin advanced to `update-wsi-2026.07.19-r12.23`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **5E/48W/7I** on
the committed tree — one error joins the debt (1× PSA2013:
`$Script:IsoPathResolved` read but never assigned) and one PSA2002
warning is resolved; committed verbatim per the no-fix-forward rule,
draining post-series.

## [update-wsi-2026.07.19-r12.22] - 2026-08-02

Tag: `resume-asset-state-rehydration` (the tag advances). Resumed runs
rebuild resolved patch-asset state from measured evidence.

### Fixed

- **Resume rehydrates resolved patch assets**: two new helpers
  (`Set-ResumePatchProperty`, `Restore-ResolvedPatchAssetsForResume`)
  rebuild the P02 runtime patch objects from the measured P04 Catalog
  crosscheck evidence when resuming at P08/P09. P01/P02 intentionally
  rebuild runtime objects from immutable config, which left monthly
  auxiliary entries in their pre-P04 metadata-only state on
  `-ResumeFromPhase P08/P09` — P09 then rejected assets it had itself
  produced. Rehydration fails closed: it refuses to resume when
  `P04.ok` is missing or when the evidence does not contain exactly
  one Catalog row per OS/KB/servicing type. Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.19-r12.22`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **4E/49W/7I** on
the committed tree — one warning joins the debt with the new helpers;
committed verbatim per the no-fix-forward rule.

## [update-wsi-2026.07.19-r12.21] - 2026-08-02

Tag: `dotnet-applicability-secureboot-v165-alignment` (the tag
advances; the version date component moves 07.18 → 07.19).

### Changed

- **.NET applicability grading**: the .NET freshness assessment gains
  a `NotApplicable` grade — a configured standalone runtime absent
  from every install index no longer counts against freshness, and an
  all-`NotApplicable` .NET set aggregates to `Fresh` (there is no
  stale payload to service). Refines the r12.20 `Kind='DotNet'`
  filtering.
- **Secure Boot tooling reference pinned at v1.6.5**: a new
  `Get-SecureBootWorkflowReference` helper and script-scope constants
  pin the delegated conversion tooling identity
  (`SecureBootObjectsRelease v1.6.5-signed`, source tag `v1.6.5`,
  commit `798cdc5`, `Make2023BootableMedia.ps1` v1.4 / 2026-03-13),
  aligning every reference emitted in evidence and messages.
- **Server 2025 audit-only rationale corrected**
  (`data/config-Server2025.json` Notes): the audit-only default is a
  project safety policy pending a measured Server 2025 conversion and
  Secure Boot E2E — not a statement about Microsoft's tooling, which
  is generic Windows-media tooling without this project-specific
  exclusion.
- **T40**: release pin advanced to `update-wsi-2026.07.19-r12.21`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **4E/48W/7I** on
the committed tree — unchanged from r12.20; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.18-r12.20] - 2026-08-02

Tag: `runtime-catalog-handoff-placeholder-fix` (the tag advances).
KB-only placeholder file names stop constraining live resolution.

### Fixed

- **Placeholder file names excluded from the identity handoff**: a new
  `Test-IsCatalogPlaceholderFileName` helper identifies
  non-authoritative KB-only placeholder names (e.g. `KB5101007.msu`)
  in configured lines. The r12.18 stable-identity selector treated
  such a placeholder as an exact expected file name, over-constraining
  the P04 live resolution; a placeholder is never a Catalog identity
  and is now bypassed at the runtime handoff (metadata-only lines) and
  at local-leaf comparison. Script-only change.
- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.20`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **4E/48W/7I** on
the committed tree — one warning joins the debt with the new helper;
committed verbatim per the no-fix-forward rule.

## [update-wsi-2026.07.18-r12.19] - 2026-08-02

Tag: `catalog-scoped-product-identity-live-verified` (the tag
advances). Catalog resolution gains a scoped, per-asset identity
verification tier, live-verified for the 2026-07 baseline.

### Changed

- **Scoped product-identity verification**: five new helpers
  (`Get-CatalogScopedElementText`, `Get-CatalogScopedLabeledText`,
  `Get-CatalogScopedDetail`, `Test-CatalogProductScope`,
  `Test-CatalogScopedDetailAgainstRule`) add a ScopedView tier to
  Catalog resolution — each live case must pass Search product scope,
  ScopedView UpdateId/KB/product/architecture verification and
  DownloadDialog file selection before an asset is accepted. This is
  the scheduled first step of the T30 structural answer (scoped
  product identity at this revision; pinned identity completes at
  r12.51–r12.53 per the reclassification card — T30 remains
  SUPERSEDED-PENDING, no contract change here).
- **Crosscheck manifest schema 1.3 → 1.4**: rules gain
  `ExpectedUpdateId`, `ExpectedFileName` values are filled for the
  full four-generation 2026-07 baseline, and the manifest now carries
  all exact assets used by that baseline (not core anchors only).
- **Config UpdateId columns resolved**: the four `config-Server*.json`
  files fill previously null `UpdateId` values with the live-resolved
  Catalog Update IDs for their declared lines (declared surface
  content only; no policy-shape change).
- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.19`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged). PSA **4E/47W/7I** on
the committed tree — unchanged from r12.18; committed verbatim per
the no-fix-forward rule.

## [update-wsi-2026.07.18-r12.18] - 2026-08-02

Tag: `catalog-stable-identity-localization-isolation` (the tag
advances). Catalog asset selection moves fully onto the stable
identity columns.

### Changed

- **Catalog selection keyed on stable identity, display text
  isolated**: five new helpers (`Get-TextFingerprint`,
  `Get-CatalogDisplayMetadataAssessment`, `Test-CatalogRowAgainstRule`,
  `Get-PatchConfiguredCatalogIdentity`, `Select-CatalogCandidateAsset`)
  restructure candidate selection so that the decision path consumes
  only locale-stable columns (KB ID, Update ID, product, file name),
  while localized Title/Classification display text is assessed
  separately and reported, never matched on. This completes the
  isolation line begun at r12.16 (Accept-Language pinning) and
  r12.07/r12.08 (semantic aliases and structural fallback).
- **Crosscheck manifest schema 1.2 → 1.3**:
  `data/catalog-crosscheck-manifest.json` rules gain
  `StableTitleMustContain`, `ExpectedFileName` and `CanonicalTitle`
  columns, giving the crosscheck a per-rule stable-identity surface
  (2026-07-B baseline identities carried over unchanged).
- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.18`
  with the measured tag.

### Distribution note

The delivered snapshot ships its own regression suite under `tests/`
and two workflow files (`catalog-live.yml`,
`powershell-regression.yml`). Input-only per the series ruling;
no distribution test or workflow file is committed.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; D-contract totals
140/30/123/64/112 with T45 NOT-YET (unchanged — the declared policy
surface does not move at this revision). PSA **4E/47W/7I** on the
committed tree — eight warnings join the debt with the new catalog
helpers; committed verbatim per the no-fix-forward rule, draining
post-series.

## [update-wsi-2026.07.18-r12.17] - 2026-08-02

Tag: `generic-list-binder-hardening` (the tag advances). Generic-list
construction stops going through the `New-Object` type binder.

### Fixed

- **Generic-list construction hardened**: every
  `New-Object System.Collections.Generic.List[...]` site (script
  state, debug-trace buffers, plan/step accumulators and helpers) is
  replaced by the direct `[System.Collections.Generic.List[...]]::new()`
  constructor — 76 sites, zero `New-Object` generic-list calls remain
  (measured). The `New-Object` generic-type binder is the
  edition-fragile path; the static constructor syntax binds
  identically on Windows PowerShell 5.1 and PowerShell 7. Script-only
  change: `data/*` and `schema/*` are byte-identical to r12.15
  (measured).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.17`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/39W/7I**
on the committed tree — one finding joins the debt (1× PSAP0005
revision-anchored comment); committed verbatim per the no-fix-forward
rule, draining post-series.

## [update-wsi-2026.07.18-r12.16] - 2026-08-02

Tag: `catalog-language-and-workspace-containment` (the tag advances).
Catalog requests pin their language at the source, and run outputs are
contained inside the WorkRoot.

### Fixed

- **Catalog request language pinned**: every Catalog request now
  carries declared headers via `Get-CatalogRequestHeaders`
  (`Accept-Language: en-US,en;q=0.9`, no-cache), with a declared
  display-language policy (`en-us|ja-jp`). This removes the
  serving-edge locale non-determinism at its source; the r12.07/08
  semantic-alias matcher becomes the second line while the strict
  matcher stays the fail-closed boundary, and the alias tables shrink
  accordingly (non-ASCII characters in the script drop from 303 to
  103, measured).
- **Workspace containment**: `Resolve-PathWithinRoot` constrains
  operator-supplied paths to resolve inside the WorkRoot (traversal
  rejected), and `Start-RunTranscript` starts the run transcript
  through the contained path. Script-only change: `data/*` and
  `schema/*` are byte-identical to r12.15 (measured).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.16`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/38W/7I**
on the committed tree — two findings join the debt (1× PSA6003 plural
noun, 1× PSAP0005 revision-anchored comment); committed verbatim per
the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.18-r12.15] - 2026-08-02

Tag: `bound-release-evidence-and-july-auxiliaries` (the tag advances).
Release evidence becomes a bound, indexed artifact set, and the July
auxiliary lines land in every config.

### Added

- **Bound release-evidence layer**: the release evidence gains an
  identity (`Get-ReleaseEvidenceIdentity`), a saved index
  (`Save-ReleaseEvidenceIndex`, `Write-ReleaseEvidenceMarker`,
  `Read-ReleaseJsonFile`), a resolved-patch evidence manifest
  (`New-ResolvedPatchEvidenceManifest`), a static-verification
  assessment, and structural boot-evidence validation
  (`Test-BootEvidenceArtifacts` / `Test-BootEvidenceApproval`):
  BootOnly evidence must declare `RequiresOperatorReview=true` and
  carry screenshot integrity records verified by SHA-256.
- **2026-07 auxiliary lines in all four configs**: the July
  re-resolution reshapes the shipped line sets (new `Discovered`
  auxiliary rows such as KB5101007 / KB5099548). The
  declaration-derived T43 tracks the surface (150 → 123 assertions)
  with no edit (measured, matching the convergence-matrix row).

### Changed

- **T39 revised (pin re-location, adjudicated)**: r12.15 re-locates
  the VM-state honesty surface — Install success is graded from guest
  evidence with an empty reasons list, BootOnly carries an enforced
  "screenshots never directly produce ReleaseReady" reason and the
  structural evidence validator above. The T39 honesty pin follows
  the measured surface (the r12.04 pinned literals it supersedes were
  comment/expression forms of the same concern); 17 assertions.
- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.15`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/36W/7I**
on the committed tree — three findings join the debt (1× PSA2012
positional `Save-CanonicalJsonFile` call, 1× PSA6003 plural noun, 3×
PSA6007 missing `[OutputType]`, the latter as info); committed
verbatim per the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.18-r12.14] - 2026-08-02

Tag: `release-evidence-and-july-dotnet` (the tag advances; the version
date moves to 2026.07.18). Release evidence gains two assessment
decisions, and Server 2022's .NET line reaches the July CU.

### Added

- **Two assessment helpers**: `Get-AuxiliaryFreshnessAssessment`
  (grades the auxiliary-package freshness state for the release
  evidence) and `Get-BootValidationAssessment` (grades the boot
  validation outcome), both returning closed records consumed by the
  release evidence path.

### Changed

- **Server 2022 .NET line advances to the 2026-07 CU**: KB5087068
  (2026-05, `State=Fallback`) is replaced by KB5101010 (2026-07,
  `Classification: Security Updates`) declared as a **child of the
  combined parent KB5102206 via `ParentKbId`** — the first shipped
  line measured to use the parent/child resolution path. The
  declaration-derived T43 tracks the line surface (153 → 150
  assertions) with no edit (measured, matching the convergence-matrix
  row).
- **T40**: release pin advanced to `update-wsi-2026.07.18-r12.14`
  with the measured tag and date.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **3E/35W/4I**
on the committed tree — unchanged from r12.13; the declared series
debt carries as-is per the no-fix-forward rule.

## [update-wsi-2026.07.17-r12.13] - 2026-08-02

Tag: `measured-e2e-corrections` (the tag advances; the version date
moves to 2026.07.17). A batch of corrections from measured E2E runs,
each landing as a declared decision or evidence artifact.

### Fixed

- **Measured E2E correction batch** — seven new decision/evidence
  helpers: `Get-BootSequencePolicyDecision` (boot.wim apply-sequence
  policy), `Get-ExpandedMsuCabRolesForSubPhase` +
  `Assert-ExpandedBootLcuTarget` (expanded-CAB role classification and
  target assertion for the ExpandedCab path),
  `Get-WinReServicingVerificationDecision` (WinRE verification
  routing), `Test-Server2025PcaPolicyPreflight` (PCA policy
  preflight), `Write-DismRollbackEvidence` and
  `Write-PatchFreshnessSummary` (rollback and freshness evidence
  artifacts).
- **Server 2025 PCA compliance defaults to audit-only**: the shipped
  `config-Server2025.json` moves `CompliancePolicy` from
  `RequirePca2023` to `AuditOnly` and declares
  `SourceMediaAssurance: Unverified` — the 2016/2019/2022
  media-conversion workflow is not documented for this media
  generation, so requiring PCA2023 needs an explicitly verified source
  or `-ForcePca2023OnServer2025`.

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.17-r12.13`
  with the measured tag and date.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **3E/35W/4I**
on the committed tree — one carried PSA2010 error is resolved by the
deliverable (`Get-PatchTargets` is now defined) and five findings join
the debt (1× PSA2002 + 1× PSA2007 `$Error` shadowing, 3× PSA6005
mandatory-parameter defaults); committed verbatim per the
no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.15-r12.12] - 2026-08-02

Tag: `july-asset-integrity-fix` (the tag advances). The 2026-07 lines
carry their resolved Catalog file identities, and identity refresh gets
its own declared decision.

### Fixed

- **Catalog file identity rehydration**:
  `Get-CatalogIdentityRefreshDecision` decides, from the baseline
  state and `-UseBaselineOnly`, whether an already-selected KB may
  refresh missing or stale Catalog transport/file identity in memory —
  `-UseBaselineOnly` pins the selected KB set but does not turn a
  `ResearchCandidate` into an immutable release;
  `ResearchCandidate` / `Discovered` / `Resolved` baselines may
  rehydrate, while `Frozen` / `Approved` stay immutable and fail on
  any digest change.
- **All four configs carry resolved 2026-07 asset identities**: the
  July lines gain their actual Catalog `FileName`s with matching
  SHA-1 digests (e.g. the Server 2016 SSU and combined packages). The
  declaration-derived T43 tracks the added `Integrity` surface and
  grows from 145 to 153 assertions with no edit (measured, matching
  the convergence-matrix row).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.12`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/30W/4I**
on the committed tree — unchanged from r12.11; the declared series
debt carries as-is per the no-fix-forward rule.

## [update-wsi-2026.07.15-r12.11] - 2026-08-02

Tag: `resume-parameter-default-fix` (the tag advances). Runs without
`-ResumeFromPhase` stop tripping over the parameter's own ValidateSet.

### Fixed

- **`-ResumeFromPhase` self-assignment trap**: assigning the unbound
  validated parameter back to a script-scoped variable of the same
  name triggered `ValidateSet` against the implicit empty string on
  both Windows PowerShell 5.1 and PowerShell 7. The operator-facing
  parameter stays untouched and only its normalized state is copied to
  a separate, unconstrained internal variable
  (`$Script:RequestedResumeFromPhase`), which the resume gates read.
  Script-only change: `data/*` and `schema/*` are byte-identical to
  r12.06 (measured); the UTF-8 BOM remains absent as delivered
  (PSA7001 carries from r12.10).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.11`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/30W/4I**
on the committed tree — unchanged from r12.10; the declared series
debt carries as-is per the no-fix-forward rule.

## [update-wsi-2026.07.15-r12.10] - 2026-08-02

Tag: `option-semantics-pwsh7-fix` (continued). Generic-collection
enumeration stops depending on the PowerShell edition.

### Fixed

- **Stable array materialisation**: `ConvertTo-StableObjectArray`
  materialises any enumerable (including
  `System.Collections.Generic.List`) as a plain object array, avoiding
  engine-specific array-subexpression behaviour between Windows
  PowerShell 5.1 and PowerShell 7; the P04 fresh-config-line
  enumeration goes through it, and a test switch deliberately
  round-trips through a generic list so both editions exercise the
  same implementation. Script-only change: `data/*` and `schema/*` are
  byte-identical to r12.06 (measured).

### Distribution note

The r12.10 snapshot is the first in the series to ship its own CI
workflow files (`.github/workflows/catalog-live.yml`,
`powershell-regression.yml`) alongside its own regression suite
(`tests/Invoke-RegressionSuite.ps1` and companions). Per the series
ruling these are input only and are not committed — workflow changes
are never taken in-series; the content is logged in the campaign
observation ledger. The snapshot script also drops the UTF-8 BOM
(committed verbatim; surfaced by PSA below).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.10`
  (tag unchanged).

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/30W/4I**
on the committed tree — one finding joins the carried debt (1×
PSA7001: the script lacks the UTF-8 BOM at this revision); committed
verbatim per the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.15-r12.09] - 2026-08-02

Tag: `option-semantics-pwsh7-fix` (the tag advances). The P03/P04
refresh switches get one declared decision point, testable on both
PowerShell editions.

### Fixed

- **Refresh-option semantics centralised**: the interaction of
  `-UseBaselineOnly`, `-SkipDynamicPatchRefresh` and
  `-AutoDetectLatestPatches` with the baseline state is now decided in
  one pure helper, `Get-PatchRefreshDecision`, returning a closed
  record (`Mode` = `FreshnessControlled` | `BaselineOnly` |
  `ForceRefresh` | `PinnedOsBaselineWithMonthlyAuxiliaries`, plus the
  refresh flags, the exact-Catalog-asset policy and baseline
  mutability). `-UseBaselineOnly` now also suppresses monthly-auxiliary
  resolution and identity refresh. The helper is exercised through
  `-Action TestHarness` under both Windows PowerShell 5.1 and
  PowerShell 7 so the two editions' option semantics cannot silently
  diverge again. Script-only change: `data/*` and `schema/*` are
  byte-identical to r12.06 (measured).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.09`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/29W/4I**
on the committed tree — one finding joins the carried debt (1×
PSAP0005 revision-anchored comment in the new helper); committed
verbatim per the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.15-r12.08] - 2026-08-02

Tag: `catalog-classification-hardening` (the tag advances from
`catalog-localization-hardening`). The classification filter stops
being a single point of failure for unseen localized labels.

### Fixed

- **Structural fallback for unrecognized Classification labels**: the
  Catalog localizes display labels independently of the Product and
  package-identity columns, so a previously unseen localized
  `Classification` string could make the strict row filter return
  zero rows. When that happens the filter re-evaluates with
  classification ignored and accepts a **single structurally
  unambiguous** row — exact KB, architecture, title semantics, Product
  and Product-reject rules stay mandatory — logging a caution with the
  actual label. The alias table also gains a further Japanese
  security-update variant. Script-only change: `data/*` and `schema/*`
  are byte-identical to r12.06 (measured).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.08`
  with the measured tag.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/28W/4I**
on the committed tree — unchanged from r12.07; the declared series
debt carries as-is per the no-fix-forward rule.

## [update-wsi-2026.07.15-r12.07] - 2026-08-02

Tag: `catalog-localization-hardening` (the tag advances from
`release-validation-hardening`). Catalog display-text
localization stops rejecting valid rows.

### Fixed

- **Catalog semantic matching**: the Microsoft Update Catalog can
  serve localized `Title` and `Classification` display strings
  (German, French, Japanese and other locales) depending on the
  serving edge and request context, while product names, KB IDs,
  Update IDs and file names stay stable. Three new helpers
  (`Get-CatalogSemanticAliases`, `Test-CatalogSemanticEquals`,
  `Test-CatalogSemanticContains`) carry per-token alias tables for the
  canonical English classification and title tokens, and the row
  filters match against the alias set instead of the raw English
  string — a valid row is no longer rejected solely because its
  display text is localized. Script-only change: `data/*` and
  `schema/*` are byte-identical to r12.06 (measured).

### Changed

- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.07`.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/28W/4I**
on the committed tree — the carried debt is joined by four findings in
the new helpers (3× PSA6003 plural noun, 1× PSA7003: 282 non-ASCII
characters inside the localized alias tables); committed verbatim per
the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.15-r12.06] - 2026-08-02

Tag: `release-validation-hardening` (continued). The monthly patch set
stops being a hand-refreshed constant: the baseline month is declared
per config and the auxiliary packages are re-resolved at fetch time.

### Added

- **Three `DiscoveryPolicy` keys** in every config:
  `BaselineMonth` (`"2026-07"` in the shipped profiles),
  `MonthlyAuxiliaryStrict`, and `ResolveMonthlyAuxiliariesAtFetch`.
  The declaration-derived T46 absorbed the new keys without an edit
  (measured).
- **P04 monthly-auxiliary resolution (Step 0A)**: when
  `ResolveMonthlyAuxiliariesAtFetch` is declared true, the run derives
  the baseline month from the config's `PatchBaseline`, re-resolves
  the SafeOS DU and Setup DU rows for that month, re-resolves the
  Server 2016 standalone monthly SSU, and builds .NET monthly selector
  lines from the official .NET Framework release-notes cache (fetching
  the cache when missing or stale). Selected rows replace the shipped
  fallback lines, duplicates are merged, and the selection is
  persisted as a `logs/` evidence artifact
  (`P04_monthly_auxiliary_selection.json`).

### Changed

- **All four shipped patch sets re-resolved to the 2026-07 baseline.**
  Server 2016's monthly SSU (KB5099542) is declared `State=Discovered`
  with no `DownloadUrl` — resolution is deferred to fetch under the
  new policy. The declaration-derived T43 absorbed the shape without
  an edit (measured); the pre-series T23 contract this supersedes was
  retired at r12.00 (SPEC §B.15.4).
- **T40**: release pin advanced to `update-wsi-2026.07.15-r12.06`
  (the P08S four-list wiring is unchanged, measured).

### Distribution note

The r12.06 snapshot ships its own validation scripts and reports under
its `tests/` directory. Per the series ruling these are input only and
are not committed; their content is logged in the campaign observation
ledger.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/24W/4I**
on the committed tree — the r12.04/r12.05 declared debt carries
unchanged (2× PSA2010, 2× PSA2012) and four findings join it in the
new monthly-auxiliary code (2× PSA3004 empty catch, 1× PSA5003 SHA1
usage, 1× PSA6003 plural noun); committed verbatim per the
no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.15-r12.05] - 2026-08-02

Tag: `release-validation-hardening` (continued). Closes the four
measured r12.04 E2E failures (2026-07-14 runs) and adds phase-resume.

### Added

- **`Common.BootWimPackageMode`** (declared per OS; schema enum
  `DirectMsu` | `ExpandedCab`): Server 2019 moves to `ExpandedCab` —
  the measured answer to `0x80070032`, raised while the outer LCU MSU
  processed its embedded unattend data against boot.wim. Expanded
  mode extracts the MSU once, inspects MUM identities/content,
  excludes WSUS/express/metadata CABs, and applies servicing-stack
  payloads before RollupFix payloads. Other generations stay
  `DirectMsu`.
- **`-ResumeFromPhase P08` / `P09`**: safely reuse an existing
  WorkRoot after validation (the measured 2016/2022/2025 runs resume
  at P09; 2019 restores boot.wim and resumes at P08). P08S writes an
  explicit marker; r12.04 JSON evidence is accepted as a one-time
  legacy resume source.

### Fixed

- **Windows PowerShell 5.1 `TrimStart` type mismatch** (stopped
  2016/2022/2025 in P09): `Get-SetupDuFileManifest` now uses an
  explicit separator `char[]`, full-path boundary checks and
  traversal rejection.
- **Failed-mount durability**: P07/P08 use transaction backups — a
  failed mount is discarded and the original WIM restored (a strict
  P08 failure no longer saves a partially serviced boot.wim); WinRE
  distribution likewise discards an index that fails copy/hash
  validation.
- **DISM evidence classification**: based on the explicit operation
  result plus the current session tail; child-package CBS noise no
  longer promotes `PackageNotApplicable` / `ProviderWarning` /
  `RecoveredInternalError` over a successful top-level operation.

### Changed

- **T40**: the P08S pipeline-wiring pin follows the measured
  structure — four phase lists now carry `P08 → P08S → P09` (the two
  standard pipelines, the Build action, and the new ResumeFromPhase
  list); release pin advanced to `update-wsi-2026.07.15-r12.05`.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA **4E/20W/4I**
on the committed tree — declared series debt: the two r12.04 PSA2010
undefined-function calls persist and two PSA2012 positional-call
findings against `Save-CanonicalJsonFile` join them; committed
verbatim per the no-fix-forward rule, draining post-series.

## [update-wsi-2026.07.14-r12.04] - 2026-08-02

Tag: `release-validation-hardening`. The release gate becomes explicit:
what must be *proven* before an ISO is release-eligible is declared per
config and enforced by an expanded P11 plus a read-only P12 and a final
P13 report.

### Added

- **Five `ValidationPolicy` flags** in every config and the v4
  template: `FailOnPca2023ComplianceFailure`,
  `SuppressRedundantCombinedLcuReapply`, `VerifyAllInstallIndexes`,
  `VerifySetupDuManifest`, `VerifyWinRePackageState`. The
  declaration-derived T42 reads the flag set from the config under
  test and adapted without an edit (measured).
- **P11 evidence expansion**: per-index install.wim
  `TargetBuildAfterUpdate` verification, enabled boot.wim index build
  verification, per-index runtime-matched .NET rollup state, embedded
  WinRE presence/byte-identity plus build and pending-package count,
  SafeOS DU evidence, a Setup DU final file manifest, and final-ISO
  WIM hashes equal to the serviced extracted WIMs — persisted as new
  `logs/` artifacts (winre_post_verification.json,
  setupdu_overlay_manifest.json, P11_verification.csv,
  inspection_post.json, dism_outcomes.jsonl).

### Changed

- **boot.wim servicing stance hardened**: Server 2019 moves to
  `enabled` (an index that does not reach the configured target build
  now fails P11); Server 2022's `tolerate` is removed from the shipped
  profile. The declaration lives in `ValidationPolicy` /
  `Common.BootWimUpdateModel`; the retained-legacy
  `Common.BootWimLcuPolicy` mirrors it (SPEC §B.15.4 / T34 record).
- **Server 2025 PCA policy**: the shipped profile declares
  `Pca2023.CompliancePolicy=RequirePca2023`; because automatic 2025
  conversion is intentionally outside Microsoft's documented
  conversion boundary, a PCA2011-only result is retained for
  diagnosis but is not release-eligible, and the run ends non-zero
  after P13 writes the final report. The P10 skip marker now records
  this stance (`skipped-by-policy: Server2025 documented-conversion
  boundary; policy=...` / operator opt-out), replacing the old
  "Server2025 default" skip reason.
- **Combined-LCU reapply suppression**: on combined SSU/LCU
  generations one asset may carry both `ServicingStackCarrier` and
  `FinalLCU` roles; if no language pack / FOD / optional component /
  DU changed the mounted image in between, the second application is
  suppressed (declared by `SuppressRedundantCombinedLcuReapply`).
- **T38** (media inspection): the Server2016-only `Kb_` guard pin
  widens its match window — the guard itself survives verbatim but
  the guarded block grew with the P11 census; the P10 skip-marker pin
  follows the new marker reasons. 31 assertions.
- **T39** (boot-verification tool set): the "VM state is NOT a boot
  verdict" honesty pin becomes structural — since r12.04 the main
  BootTest derives `Success` from guest evidence (Install) or forces
  operator review (BootOnly), never from the recorded `VmState`; the
  harness keeps the explicit disclaimer. 17 assertions.
- **T40** release pin advanced to `update-wsi-2026.07.14-r12.04`.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. PSA
**2E/18W/4I** on the committed tree — the two errors are PSA2010
undefined-function calls in the snapshot (`Get-PatchTargets`,
`Resolve-OscdimgPath`), latent defects committed verbatim per the
no-fix-forward rule and declared here as series debt; they drain in
the post-series conformance release. D-contract totals unchanged from
r12.03 (140/30/150/64/112; T45 NOT-YET).

## [update-wsi-2026.07.12-r12.03] - 2026-08-01

Tag: `e2e-log-fixes` (continued). Catalog cross-check pass over all
four generations: not just "the KB exists", but the x64 Catalog row,
title, Product, Classification, DownloadDialog file set and CDN
reachability are made verifiable expectations.

> **Note on r12.02.** Revision r12.02 was permanently lost
> (user-deleted) and is not fabricated here; this revision's diff
> subsumes it. The commit sequence therefore goes r12.01 → r12.03 by
> design, and the sparse numbering is the honest record.

### Added

- **`data/catalog-crosscheck-manifest.json`** — a per-OS, per-Kind
  table of Catalog expectations (required title tokens, required
  Product tokens, Classification, file extension) for every baseline
  KB, referenced from each config's `_meta.catalogCrossCheckManifest`.
  This makes the cross-check machine-consumable: the same expectations
  drive the P04 pre-fetch verification and the Windows-side
  `tests/Test-CatalogAllOs.ps1` reachability probe (HEAD or 1-byte
  Range GET).
- **`ServicingModel.DotNetPolicyDetails`** (Server 2016): declares the
  in-box vs standalone .NET stance measured in the cross-check — the
  in-box .NET is updated by the OS LCU; KB5087537 is NOT applied as a
  separate MSU; the only standalone candidate is the .NET 4.8
  KB5087065. The 2016 .NET line gains a
  `RuntimeSelector.NetFx4Release` guard so the standalone MSU is only
  applied when the image's runtime matches.

### Changed

- **Per-generation Catalog aliasing**: Server 2022 and 2025 rows are
  matched under their full server product tokens (their Catalog title
  and Product spellings differ from the client rows and from each
  other); SafeOS DU vs Setup DU on 2016/2019/2022 share a title shape
  and are discriminated by the Product column; the Server 2025 target
  LCU's DownloadDialog is verified to contain both the checkpoint and
  the target file.
- **Server 2019 KB5094123**: the previously pinned CDN URL (measured
  HTTP 404) is removed from the config; the asset is re-resolved
  KB-based at run time under the r12.01 exact-KB mechanism.
- **`Lines[]` role targeting refined** (2016): SafeOS DU / Setup DU
  lines carry explicit `TargetsByRole` entries.
- **T40** release pin advanced to `update-wsi-2026.07.12-r12.03`.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red. Declaration-derived
contract totals move with the declaration exactly as the convergence
matrix records for this revision (T41 140, T42 30, T43 150, T44 64,
T46 112; T45 NOT-YET). PSA 0E/17W/3I on the committed tree (declared
series debt).

## [update-wsi-2026.07.12-r12.01] - 2026-08-01

Tag: `e2e-log-fixes`. Fixes derived from the 2026-07-12 E2E runs on a
Windows Server 2025 / Windows PowerShell 5.1 host, where all four OS
builds failed for four *distinct* measured causes (not one shared
root): 2016 stopped at P07 on a .NET line that was metadata-only (KB
known, distribution file never resolved); 2019 failed at P04 on a
pinned CDN URL returning HTTP 404; 2022 hit `0x800f0823` in WinRE
because its servicing stack (20348.557) sat below the LCU's floor;
2025's P08S succeeded but a `Generic.List` → `@(...)` coercion was
type-mismatched under Windows PowerShell 5.1.

### Added

- **Exact-KB Catalog re-resolution**: `Get-CatalogRowsForResolvedPatch`
  and `Resolve-ResolvedPatchAssetFromCatalog` re-resolve the
  distribution assets of the KBs already in the baseline — never
  selecting a different KB. Server 2022/2025 queries are narrowed by
  the full Server product token so Windows-client rows are excluded;
  SafeOS DU and Setup DU are discriminated by the Products column; the
  Catalog search / DownloadDialog caches can be refreshed explicitly.
- **`Merge-ResolvedPatchDuplicates`**: de-duplicates resolved patches
  on `Kind` + KB, preferring an entry with a real file over a
  metadata-only one and taking the union of `Roles`.

### Changed

- **P04 fails early on unresolved assets**: an exact-KB resolution
  step runs first and any line still metadata-only after it fails the
  phase — instead of r12.00's behaviour of admitting metadata-only
  lines at P04 and failing later inside P07/P08/P09. Build phases
  consume resolved files only.
- **`config-Server2022.json`**: the source-prerequisite (bridge)
  declaration now targets WinRE as well (Targets 2 → 3) and its
  `Condition.WinRePolicy` records the E2E-confirmed stance
  (`ApplyWhenSourceBelowFloor_E2EConfirmed_0x800f0823`) — the measured
  answer to the WinRE `0x800f0823` failure.
- **Offline-registry probe quieting**: the `SecureBoot\Servicing` key
  may be absent on older ISOs; the probe now checks `Test-Path` and
  reads with `-ErrorAction SilentlyContinue`, so transcripts no longer
  record a terminating error that was already being caught.
- **T40** release pin advanced to `update-wsi-2026.07.12-r12.01` /
  `e2e-log-fixes`; the pin-tracking wording in TESTING.md /
  tests/README.md is made revision-agnostic (the pin advances in every
  merge commit).

### Unchanged (safety envelope)

Single-script layout; baseline KBs are never silently swapped;
previews are never auto-adopted; Frozen/Approved hash mismatches are
never silently accepted; WinRE `0x800f0823` is never ignored;
checkpoint CU + target LCU stay co-located in one folder.

### Gate state (measured on the branch)

Offline suite 25/26 PASS with T30 the declared red; PSA 0E/15W/0I on
the committed tree (declared series debt; +1W over r12.00).

## [update-wsi-2026.07.11-r12.00] - 2026-08-01

Tag: `schema-v4-role-planner`. First commit of the r12-series merge
campaign on the integration branch
`integration/powershell-update-windows-server-iso/r12-series` (56
commits total; the history itself is the deliverable). The script,
`data/*` and `schema/*` are committed **verbatim** from the delivered
r12.00 snapshot (14,861 lines; staged-blob SHA-256 verified identical
to the snapshot source): Schema 4.0 lands whole — the declared
servicing-policy architecture that every later revision refines. The
repository contract set is re-founded on the terminal-referenced
convergence model: contracts are authored once against the series
terminal and evaluated per revision; a contract whose anchor does not
yet exist at a revision is a recorded gap (`NOT-YET`), not a failure.

### Added

- **Config Schema v4.0** (`schema/config.schema.v4.json`, JSON Schema
  draft 2020-12) and `data/config-template-v4.json`. All four
  `data/config-Server*.json` move to `Schema: "4.0"` and gain the
  declared policy surfaces: `ServicingModel` (canonical servicing
  model; `ApplyPlans` declares the apply sequence as data, replacing
  the in-code apply map), `DiscoveryPolicy` (live-Catalog discovery:
  `CatalogAliases`, per-Kind `SearchProfiles`, release-channel and
  preview policy), `ValidationPolicy` (what must be proven before
  freeze/approval), `Compatibility` (the config's own migration map:
  `LegacyFieldsRetained` / `CanonicalV4Fields`), and per-Line `Roles`,
  `TargetsByRole`, `Applicability`, `RuntimeSelector`, `Integrity`,
  `State`, `Evidence`, `ParentKbId`. SPEC §B.4.0 is the normative
  description.
- **Six declaration-derived contracts (T41–T46)** — authored once
  against the series terminal, expected values read from the config
  under test, never hardcoded:
  T41 `apply_plan_conformance_test.py` (ApplyPlans + TargetsByRole),
  T42 `servicing_model_declaration_test.py` (SourcePrerequisites,
  BootWimUpdateModel, ValidationPolicy),
  T43 `line_integrity_declaration_test.py` (Lines[].Integrity + Roles),
  T44 `compatibility_declaration_test.py` (legacy/canonical
  meta-contract: a test asserting a `LegacyFieldsRetained` field is by
  definition asserting the superseded model),
  T45 `servicing_contract_baseline_test.py` (NOT-YET at r12.00: its
  anchor `data/servicing-contract-baselines.json` is introduced at
  r12.44),
  T46 `discovery_policy_declaration_test.py` (CatalogAliases +
  SearchProfiles; supersedes T28, with T30's replacement scheduled).
- **SPEC §B.4.0** (Config Schema v4.0 — declared servicing policy) and
  **SPEC §B.15.4** (contract retirements at r12.00: per retired
  contract, what it asserted and why that reading of Microsoft's
  servicing model was wrong).

### Changed

- **Config schema gate** (`config_schema_test.py`): schema selection is
  now **declaration-based** — each config's top-level `Schema` field
  selects `config.schema.json` (`"3.0"`) or `config.schema.v4.json`
  (`"4.0"`); an unknown value fails loudly. The stdlib-only validator
  gains the five 2020-12 keywords the v4 schema uses (`#/$defs/...`
  refs, `oneOf`, `pattern`, `minItems`, `minimum`), each covered by
  self-tests in both directions.
- **T32 `checkpoint_placement_test.py`** (partial retirement): the
  `PatchModel` Forbid-axis assertion is retired (see Removed) and
  replaced by a retirement guard asserting the Forbid axis stays
  **absent** from `Test-PatchModelConsistency`, plus three new rows
  pinning the r12.00 State-driven integrity requirement (a Line at
  state `Frozen`+ must carry a SHA-256; a `LegacyResolved` Line must
  carry at least one integrity key). The landing-layout and routing
  rows are unchanged.
- **T29 `patch_integrity_digest_test.py`** (replaced wiring guard): the
  static pins on direct flat-field seeding (`$p.Digest` / `$p.Sha256`)
  are replaced by single-accessor pins — all baseline hash reads go
  through `Get-BaselineHashValue -Line ... -Algorithm Sha1|Sha256`,
  which serves the canonical `Integrity.<Alg>.Value` node and guards
  the flat `Digest`/`Sha256` fields as the retained-legacy path; a
  regression pin rejects any resurfaced direct-field seeding. The
  format-boundary rows are unchanged; the data-side declaration is T43.
- **T40 `setup_binaries_sync_test.py`**: release pin advanced to
  `update-wsi-2026.07.11-r12.00` / `schema-v4-role-planner` (recurs at
  every merge).
- **T30 `setup_du_discriminator_test.py`** → **SUPERSEDED-PENDING (the
  declared red on the integration branch)**: r12.00's selector returns
  three candidate rows where the contract expects one. Not adjudicated
  as a defect — Catalog title-string heuristics are a known fragility
  surface and the series tightens exactly this via
  `DiscoveryPolicy.SearchProfiles`, progressively (scoped product
  identity at r12.19; pinned identity at r12.51–53). The replacement
  contract ("resolved rows conform to the declared SearchProfiles")
  becomes assertable once the policy is honoured end to end; re-examine
  at the r12.19 and r12.51 merge cards.
- **SPEC §B.4** heading and intro (v4.0 current, v3.0 retained;
  compatibility note on §B.4.1–§B.4.5) and **§B.15** (the Require/Forbid
  matrix documented as **superseded** with Microsoft citations; kept as
  the historical record).
- **TESTING.md / tests/README.md**: contract inventory updated for the
  retirements, the T41–T46 additions, and the revised gates.

### Removed

Eight contracts retired. Per the series rule, no test is deleted
without a record of what it asserted and why that reading of
Microsoft's servicing model was wrong; SPEC §B.15.4 carries the full
records — summarised here:

- **T28 `setup_du_forbid_test.py`** — asserted Setup DU exists only for
  the uup-checkpoint OS and that 2016/2019/2022 resolve the empty
  no-line marker. Wrong: Microsoft publishes Setup DU per servicing
  branch; the live Catalog resolves KB5068794 / KB5068795 / KB5079518
  for 2016 / 2019 / 2022. A point-in-time absence of rows had been
  generalised into a publishing rule. Successor: T46 (+ live-network
  behavioural half, scheduled).
- **T23 `config_required_ssu_downloadurl_test.py`** — asserted every
  SSU line carries its own `DownloadUrl` and a per-OS
  `PatchModel` ⇔ SSU-presence consistency. Wrong: an SSU delivered as
  a child of a combined parent (`ParentKbId`) has no standalone URL and
  is resolvable through its parent; under live discovery a committed
  URL is a staleness hazard, not a guarantee. Successor: T43.
- **T27 `catalog_patchset_builder_test.py`** — asserted the builder
  reproduces an in-code apply map keyed by `PatchModel`. Wrong: the
  apply sequence is a property of the servicing model, expressible as
  data — `ServicingModel.ApplyPlans` — which the builder must conform
  to rather than restate; the earlier fail-closed rows had encoded
  fixture staleness as designed behaviour. Successor: T41.
- **T31 `lcu_target_verify_test.py`** — asserted Server 2016 verifies
  post-update state by KB-id membership while other OSes verify by
  measured build. Wrong: the fork mistook an implementation workaround
  for a Microsoft-side distinction; 2016 joins the unified
  `RollupFixAndMeasuredBuild` evidence mode (measured at r12.46).
  Successor: T42/T43.
- **T32 (Forbid rows only)** — the `PatchModel` Forbid axis encoded
  per-generation publishing assumptions the Catalog disproves; the
  runtime keeps Require + the State-driven integrity rule. The file
  survives with the routing rows and the new absence guard.
- **T33 `bridge_lcu_contract_test.py`** — asserted a standalone
  `BridgeLcu` block and "no other OS carries a bridge". Wrong: the
  bridge is one instance of the uniform source-prerequisite fact
  (`SourcePrerequisites[]` + `Condition.Mode`); Server 2016 carries a
  legacy prerequisite under the same structure, falsifying the scope
  pin. Successor: T42.
- **T34 `bootwim_policy_test.py`** — asserted a per-OS
  `BootWimLcuPolicy` matrix (enabled/disabled/tolerate). Wrong twice:
  the stance is a validation policy, not a per-OS capability
  (`ValidationPolicy.FailOnBootWimServicingFailure`, every OS
  `enabled` from r12.04); and boot.wim cannot be LCU-serviced at all
  (WinPE rejects the `.msu` with `0x80070032`; the extracted CAB fails
  `0x8007371b`) — a per-OS policy matrix over a structurally
  impossible operation encoded a distinction that does not exist.
  Successor: T42.
- **T37 `per_os_evidence_test.py`** — asserted four forked per-OS
  evidence resolvers and hardcoded 2024-4B build floors. Wrong: the
  floors are per-prerequisite facts of Microsoft's servicing timeline,
  declared in `SourcePrerequisites[].Condition`; one uniform declared
  structure now expresses what four hand-written branches used to.
  Successor: T42 + the declared `Detection` list.

### Gate state (measured on the branch, not assumed)

Offline suite 25/26 PASS with T30 the **declared** red (branch rule:
red is allowed, but only declared red). PSA on the committed tree:
0 errors / 14 warnings / 0 info (the raw-LF snapshot sweep additionally
shows the one-off PSA7002 line-ending artefact; committed form is CRLF
via `.gitattributes` and does not carry it). PSA debt is declared per
revision and drains in the post-series conformance release.

### Fixed (2026-07-14 — docs only; no script change)

- Repaired the pre-migration analyzer path `../../python/powershell-static-analyzer/psa.py`
  in five documents — the analyzer's canonical home is
  `quality-tools/powershell-static-analyzer/`, so the documented commands /
  links were dead: README.md, README.ja.md, SPEC.md, TESTING.md (command
  examples: `../../python/...` → `../../quality-tools/...`) and
  tests/README.md (relative markdown link: `../../python/...` →
  `../../../quality-tools/...`, three levels up from `tests/`). The corrected
  command was validated by actually running it from the project directory
  against the live analyzer (psa.py 4.3.0):
  `0 errors / 0 warnings / 0 info` on the current 14586-line script.

## [update-wsi-2026.07.11-r11.68] - 2026-07-11

Tag: `setup-binaries-sync`. Root cause closed [measured 2026-07-11]:
P08 services boot.wim (the Setup engine) but the media `\sources`
Setup binaries stayed at shipped versions; per Microsoft's
media-dynamic-update guidance, setup.exe (and setuphost.exe on
10.0.26100+) from the serviced boot.wim must be identical to the
media copies or "Windows Setup will fail during installation" -- and
it did: the 2016/2022/2025 output ISOs failed before edition
selection ("a media driver ... is missing") while WinPE could read
the 8.4 GB install.wim and diskpart saw the disk; the failing rig
showed X:\sources\setup.exe 333,304 B (2026-07-08) vs
D:\sources\setup.exe 333,184 B (2026-01-15). Server 2019 escaped
only because its boot.wim is pinned old (17763.3650). The E2E
inspection had a blind spot: it never compared these binaries.

### Added

- **P08S `SyncSetupBinaries`** (Build; between P08 and P09): mounts
  boot.wim idx2 read-only, plans the file set from the image build
  (`Get-SetupBinarySyncPlan`: setup.exe always; setuphost.exe on
  26100+), and syncs the media copies as an EXPLICIT, recorded
  operation [user requirement 2026-07-11]: per file, size + UTC
  timestamp + SHA-256 are captured for the boot.wim side and for the
  media BEFORE and AFTER, printed to the console and persisted to
  `logs/P08S_setup_binaries_sync.csv` +
  `logs/setup_binaries_sync.json`; identical files are recorded as
  `already-identical` (no blind copy); every copy is post-verified
  by SHA-256 (hard failure on mismatch); the ISO-extracted ReadOnly
  attribute is cleared before copying. The boot.wim-side binaries
  are stashed to `work/p08s_setup_binaries/`, and P09 reapplies the
  stash after its Setup DU overlay step (MS order: the boot.wim
  copies win) -- dormant while no SetupDU resolves, wired so a
  future SetupDU cannot silently undo the sync. For Server 2016
  this doubles as the working closure of the V3 SetupDU gap.
- **P11 `SetupBinarySync_*` rows**: the inspection now records the
  Setup-binary identity (presence/size/timestamp/SHA-256) of every
  boot image and of the media root (`MediaSetupBinaries`), and P11
  compares them per the plan gate: mismatch grades **Fail** with
  both sides' evidence in the notes. Closes the blind spot.

### Tests

- **T40** `setup_binaries_sync_test.py` (16 assertions): plan build
  gates (26100 boundary; unknown-build degradation), file-evidence
  measurement (exact size/SHA-256/ISO-8601 UTC; missing-path shape),
  record vocabulary, and structure pins (phase wiring between
  P08/P09 across all three pipeline lists; SHA-verified copy;
  ReadOnly clearing; CSV/JSON artifacts; console before/after lines;
  stash + P09 post-overlay reapply; P11 Fail grading; version bump).


## [update-wsi-2026.07.08-r11.67] - 2026-07-08

Tag: `boot-verification-tools`. Boot verification arc (design
adjudicated 2026-07-08): the project's target world -- firmware where
PCA2011 is REVOKED (in DBX) -- can be reproduced faithfully in a
Hyper-V Gen2 VM by applying the KB5025885 mitigations inside a guest
(db/dbx are per-VM NVRAM). Certificate EXPIRY alone blocks nothing;
only the revocation does, so the revoked-rig cells are the substance
and the standard-firmware cells are lightweight regression records.

### Added

- **`tools/boot-verification/`**: matrix harness
  (`Invoke-IsoBootVerification.ps1`, cells T1-T12: standard +
  revoked rigs, screenshot capture at 30/90/180 s, expectation-aware
  `ledger.jsonl`; install-depth cells auto-verdict via the EVIDENCE
  VHDX), `New-EvidenceDataVhdx.ps1` (tokenised `autounattend.xml` +
  collector on a data VHDX; the target ISO is never modified),
  `Export-InstalledSystemEvidence.ps1` (guest evidence JSON aligned
  with `inspection_post.json` vocabulary),
  `Test-SecureBootRigState.ps1` (RIG READY gate: db has the 2023 CA
  AND dbx carries PCA2011), `BootVerification.Common.ps1` (pure ESL
  parser, RGB565->BMP converter, cell map, ledger), README (rig
  recipe with KB5025885 values 0x40/0x100/0x80/0x200, the
  expiry-vs-revocation explainer, T9-first rule, checkpoint-rollback
  experiment, boot.stl triage, adjudication mapping).

### Changed

- **`-Action BootTest` rebuilt** after two measured defects: it used
  the third-party `MicrosoftUEFICertificateAuthority` Secure Boot
  template (Windows media must verify against `MicrosoftWindows`),
  and it graded `VM State = Running` as a pass although a VM sits at
  a firmware failure screen in the Running state. It now boots with
  the correct template, saves console screenshots (GDI-free
  RGB565->BMP), reports State as context only, and requires the
  operator's verdict; old logic is not retained.

### Tests

- **T39** `boot_verification_tools_test.py` (17 assertions): tool-set
  ParseFile, BMP/ESL/subject/cell-map/ledger pure-function REPL
  matrix, template well-formedness + tokens + explicit disk-0 wipe,
  template/verdict/README structure pins. Added to the standard gate
  battery.


## [update-wsi-2026.07.08-r11.66] - 2026-07-08

Tag: `evidence-kb-set`. The 2026-07-08 E2E showed the Server 2016 SSU
(KB5094141) and LCU (KB5094122) landing at the SAME build
(14393.9234): single-KB evidence selection displayed the SSU as "the
LCU package", and the comparator's kb-hit missed the expected LCU
(the verdict survived only via the build fallback).

### Changed

- **Server 2016 evidence carries `KbIdsAtBuild`** -- ALL KB-named
  packages at the top build (New-LcuEvidenceObject passthrough;
  other-OS resolvers leave it empty).
- **`Test-LcuTargetApplied` (2016) matches by membership** against
  that set (LcuKbId equality retained), and its Notes display the
  full KB set instead of one arbitrary id.

### Tests

- T37 -> 17 (same-build SSU+LCU shape carries both ids);
  T31 -> 27 (membership match when the SSU shades the single slot).


## [update-wsi-2026.07.08-r11.65] - 2026-07-08

Tag: `kind-verify`. The 2026-07-08 E2E measured the premise of P11's
generic Kb_<id> presence rows out of existence: KB ids appear in
installed package names ONLY on Server 2016. The .NET cumulative
surfaces as `Package_for_DotNetRollup~~10.0.4802.1` (2019/2022) /
`Package_for_DotNetRollup_481~~10.0.9335.3` (2025) -- no KB id,
neither the offering KB nor the child MSU KB -- so the r11.60 alias
mechanism had no name to match, and SafeOSDU/SetupDU/Checkpoint never
surface as install.wim idx-1 packages at all. The rows were
structurally Warn-locked on 3 of 4 OSes [adjudicated 2026-07-08].

### Changed

- **P11 verifies per Kind**: a `KindVerificationScope` row documents
  the mapping (LCU/Checkpoint via `LcuTargetApplied` measured build;
  DotNet via the new census; SafeOSDU = WinRE payload and SetupDU =
  sources files are not verifiable as install.wim packages and are
  excluded); new pure `Get-DotNetRollupEvidence` census (suffix-aware,
  highest version wins) feeds a `DotNetRollupApplied` row (Pass with
  package name + measured version / Warn when a DotNet Line resolved
  but no package is visible); generic `Kb_<id>` rows survive ONLY on
  Server 2016, where package names are KB-named and the rows are real
  signal.
- **`Get-KbAliasFromPatchPath` removed entirely** (no shims): with
  name-based KB matching retired on RollupFix OSes it had no caller.
  The DotNet-only KbId/FileName divergence audit REMAINS in T38 as a
  committed-data fact guard (the Catalog parent/child structure).

### Tests

- T38 reworked to 31 assertions: DotNet census REPL matrix (plain +
  `_481` + absent), scope/census wiring pins, Kb_ rows pinned behind
  the Server2016 guard, alias-extractor-gone pin.


## [update-wsi-2026.07.08-r11.64] - 2026-07-08

Tag: `skip-aware-output-check`. The 2026-07-08 Server 2025 E2E ended
with `Output ISO check OverallStatus = Fail` although P10 was skipped
BY THE ADJUDICATED DEFAULT (r11.55: Server 2025 converts only with
`-ForcePca2023OnServer2025`) -- an intentional outcome graded as a
build failure [adjudicated 2026-07-08, option (a): fix the grading;
whether Server 2025 should convert by default is deferred to the
Secure Boot boot-test results].

### Changed

- **P10 skip markers now record WHY**: `P10.skipped` carries a reason
  string (`skipped-by-policy: operator opt-out` / `skipped-by-policy:
  Server2025 default` / `prereq-critical` / `already-healthy`).
- **`Test-OutputIsoPca2023Readiness` is skip-aware**
  (`-ConversionSkipReason`, fed by the new `Get-P10SkipReason` at
  both call sites): a PCA2011 critical path under a
  `skipped-by-policy` reason grades **Warning** with the policy named
  and the consequence stated (will not boot on 2011-revoked
  firmware); a genuine conversion shortfall stays **Fail**; the
  result carries `ConversionSkippedByPolicy` / `ConversionSkipReason`.

### Tests

- T38 extended (marker reasons + both call sites + policy wording pin).


## [update-wsi-2026.07.08-r11.63] - 2026-07-08

Tag: `fallback-health-wording`. The 2026-07-08 4-OS E2E proved the
Server 2019 rescue end to end (P10 fallback converted from
install.wim; the output ISO's bootx64.efi verifies against the
"Windows UEFI CA 2023" chain), but the readiness health text then
described that exact shape as "boot.wim may be a custom media build".

### Changed

- Health classification gains a dedicated branch for the
  install.wim-fallback shape (PCA2023 signer + no boot.wim `_EX` +
  install.wim `_EX` present): the reason now states the fallback
  conversion accurately. Health stays **Warning** by adjudication
  (2026-07-08): the 2023-boot-manager + as-shipped-WinPE combination
  is upgraded to Healthy only after a Secure Boot boot test proves
  it; the neither-image wording is kept for the genuine custom-build
  case.


## [update-wsi-2026.07.07-r11.62] - 2026-07-07

Tag: `pca2023-fallback-source`. Second half of the Server 2019
PCA2023 rescue [user-adjudicated 2026-07-07]:
`Convert-WimBootToPca2023Signed` now selects its `_EX` payload source
from an ordered candidate list -- boot.wim idx 1 first (aligned with
Microsoft's Make2023BootableMedia.ps1, which mounts boot.wim), then
the serviced install.wim's primary index as FALLBACK when boot.wim
carries no `_EX` staging set.

Evidence basis for the fallback: (1) firmware Secure Boot verifies
the MEDIA's boot manager, not the WinPE payload behind it; (2) a
Microsoft Q&A response confirms that replacing a revoked media boot
manager with a 2023-signed `bootmgfw_EX.efi` taken from an updated
image is a working direct workaround (old WinPE boots fine behind the
new boot manager); (3) the LCU stages identical `_EX` payloads into
any serviced image, and Server 2019's install.wim IS serviced while
its boot.wim is structurally unserviceable (0x80070032). This
combination is NOT a Microsoft-supported configuration; the final
proof is a boot test on PCA2023-only firmware (2011 CA revoked),
tracked as a follow-up (real hardware or a QEMU/OVMF rig with the
2023 CA alone in db and the 2011 CA in dbx).

### Changed

- **Ordered source candidates + `SourceWim` in the result**: a
  fallback selection logs a Caution naming the source and the
  evidence path; P10's success line reports the source. When NEITHER
  image carries the staging set the error message says so plainly.

### Tests

- T38 extended to 28: fallback wiring pin (candidate loop +
  `SourceWim`) and a candidate-ORDER pin (boot.wim stays primary).


## [update-wsi-2026.07.07-r11.61] - 2026-07-07

Tag: `inspect-install-ex`. First half of the Server 2019 PCA2023
rescue [user-adjudicated 2026-07-07]. Delivery-goal analysis: 2019's
boot.wim is structurally unserviceable (0x80070032, D1-probed), the
PCA2023 conversion sourced its payloads from boot.wim ONLY, so the
2019 output ISO would stay PCA2011-signed -- unbootable on firmware
that revoked the 2011 CA (the post-2026-06 world this project
targets). The earlier "the only impact is a stale installer
environment" assessment was WRONG against that goal. The LCU stages
the `_EX` payloads into ANY serviced image, and 2019's install.wim IS
serviced: this patch makes that fallback source MEASURED end to end
before the conversion patch consumes it.

### Changed

- **`Get-WimIndexInspection`: `_EX` census on BOTH kinds** (was
  boot-only). `Compare-MediaInspection` reports `ExPayloadAppeared`
  for both WIM slots.
- **Readiness inventory records the install.wim `_EX` census**
  (`InstallHasEfiExDir` / `InstallHasBootMgrFwEx` / `InstallHasFontsEx`
  / `InstallHasDvdEx` / `InstallHasEfisysExBin`) in the SAME mount
  session as the existing hive reads (no extra mount cost).
- **Health classification recognizes the fallback**: PCA2011 signer +
  no boot.wim `_EX` + install.wim `_EX` present is now its own
  Warning ("P10 sources from install.wim"); the neither-image case
  states plainly that P10 has no conversion source. Display + report
  gain an install-side `_EX` line.

### Tests

- T38 extended to 26 (both-kinds census fixture, install-slot
  appearance, readiness wiring pin); T3 harness schema re-pinned with
  the five new inventory fields.


## [update-wsi-2026.07.07-r11.60] - 2026-07-07

Tag: `kb-alias`. Resolves the DotNet KbId/FileName divergence flagged
during the 2026-07-07 E2E analysis (Server 2022 Line: KbId KB5088862
vs file kb5087068; Server 2019: KB5088864 vs kb5087061).
Investigation against Microsoft primary sources confirmed this is the
Catalog's parent/child KB structure for .NET Framework monthly
updates -- the OS-level KB exists for update-OFFERING, the installed
artifact is the .NET-version-specific child MSU, and per Microsoft
the OS-level KB "is not expected to be listed as an installed update
on the device". NOT a data defect; but P11's Kb_<parent> row could
never match an installed package name -- a structural false Absent.

### Changed

- **P11 Kb rows accept the child-KB alias**: new pure extractor
  `Get-KbAliasFromPatchPath` derives the child KB from the resolved
  patch's file path when it differs from the declared KbId; a package
  name matching EITHER id counts as Present, and the row's Notes
  records the alias (and when the match came via it).

### Tests

- T38 extended to 24 assertions: alias extraction matrix, P11 alias
  wiring pin, and a data audit across all four committed configs
  pinning that KbId/FileName divergence occurs ONLY on Kind=DotNet
  Lines -- any other divergence fails the audit and forces
  investigation.


## [update-wsi-2026.07.07-r11.59] - 2026-07-07

Tag: `media-inspection`. The inspection arc proper [user-adjudicated
2026-07-07]: record the FULL measured state of the media before and
after servicing (every WIM index, exactly one read-only mount per
index, everything gathered in that one pass -- time cost explicitly
accepted), and cross-check measurement against config declarations
without gating on it yet (observe-first; measurement-driven gating is
a next-arc step after the inspection survives one E2E cycle).

### Added

- **Inspection engine**: `Get-WimBuildSources` (acquisition refactored
  out of `Get-ImageLcuEvidence`), `Get-WimIndexInspection` (one mount:
  three build sources + per-OS evidence + full package-name list +
  install: winre.wim presence/size/SHA-256 + SecureBoot servicing hive
  values / boot: `_EX` payload census), `Get-MediaInspection` (all
  indexes of install.wim + boot.wim, WIM sizes + SHA-256, and
  `boot.stl` locations -- the MS LCU pages require boot.stl on
  media serviced with dynamic updates; missing => 0xc0430001 at
  Secure Boot validation), `Write-MediaInspectionJson`.
- **P06**: pre-servicing inspection => `logs/inspection_pre.json`
  (failure = Warning + errors.jsonl entry, never a phase failure).
- **P13**: `Compare-MediaInspection` pure diff =>
  `logs/inspection_diff.json` + per-index console summary, and
  `Get-InspectionCrossChecks` observe-first findings: declared
  `BootWimLcuPolicy` vs measured boot.wim build movement (tolerate +
  measured success is the recorded evidence for flipping an OS to
  `enabled`), and declared `BridgeLcu` vs the pre-measured floor
  (redundancy = config-drift Warning). Warnings go to the console AND
  errors.jsonl; nothing gates.
- **T38 `media_inspection_test.py`** (19 assertions).

### Fixed

- **P11's package verification had never run**: `Get-WindowsPackage`
  was invoked with `-ImagePath`/`-Index` -- an invalid parameter set
  that threw on every OS, and the surrounding catch downgraded it to
  a Caution. The Kb rows and the TargetBuildAfterUpdate hard-Fail row
  [DECIDED 2026-07-02] were dead code from birth (proven by the
  2026-07-07 E2E logs on all four OSes). P11 now: (1) proves ISO/
  extracted content identity per WIM by SHA-256 (hard Fail on
  mismatch; DISM cannot mount a WIM on read-only ISO media, so the
  deep inspection runs over the extracted tree and these rows anchor
  it to the shipped bytes), (2) runs the full post inspection =>
  `logs/inspection_post.json` (hard Fail row if unavailable), and
  (3) derives the Kb rows and the TBAU check from measured evidence.
- **`Test-LcuTargetApplied` forked per OS** (destructive signature
  change: `-OsKey`/`-Evidence` replace `-PackageNames`): the KB-name
  comparator would have hard-failed 2019/2022/2025 media whose LCU
  HAD applied (no KB id exists in RollupFix package names).
  Server2016 judges by KB id with build fallback; RollupFix OSes by
  measured build vs TargetBuildAfterUpdate; a missing TBAU on a
  RollupFix OS is INDETERMINATE (Warn), never a silent Pass. Hard-
  Fail semantics on mismatch retained [DECIDED 2026-07-02].

### Tests

- T31 re-pinned to the per-OS comparator (26 assertions); T38 added.


## [update-wsi-2026.07.07-r11.58] - 2026-07-07

Tag: `per-os-evidence`. Third fix of the 2026-07-07 E2E (run 2) batch,
and the core of the per-OS inspection arc [user-adjudicated
2026-07-07]: LCU-level detection was a single shared function
(`Get-LcuVersionFromInstallWim`) that matched ONLY
`Package_for_KB######` names. That naming exists on Server 2016 alone;
2019/2022/2025 name their cumulative package
`Package_for_RollupFix~...~~<build>.<rev>` with NO KB id, so the
detector returned '(none)' on media whose LCU had in fact applied
status=Ok -- P10 mis-skipped (Critical false-skip) and P12 mis-failed
on 2022/2025 in the same run that proved the servicing worked.

### Changed

- **Judgment forked per OS** (never shared again): four independent
  resolvers `Resolve-LcuEvidence_Server2016/2019/2022/2025`, each
  owning its LCU package-naming rule and its documented 2024-4B build
  floor (MS primary sources, verified 2026-07-07: 2016 KB5036899 =
  14393.6897; 2019 KB5036896 = 17763.5696; 2022 KB5036909 =
  20348.2402; 2025: the 26100 GA itself postdates 2024-04, floor
  26100.1). Server 2025 resolvers the checkpoint model: multiple
  RollupFix packages visible, highest build wins.
- **Three independent build sources, one mount session**
  (`Get-ImageLcuEvidence` acquisition shell + dispatcher): package
  names (Get-WindowsPackage), SOFTWARE hive CurrentBuildNumber+UBR,
  and ntoskrnl.exe file version -- consensus arithmetic
  (registry > packages > kernel; `BuildSourcesAgree` requires >= 2
  matching sources) in the judgment-free `New-LcuEvidenceObject`.
  Unknown OsKey is a typed throw: silently mis-inspecting an OS is
  the exact failure this engine replaces.
- **`Get-WimSystemHiveValue` -> `Get-WimOfflineHiveValue`**
  (destructive rename): the offline hive reader now takes
  `-HiveFile SYSTEM|SOFTWARE`; all call sites updated.
- **Readiness/P12 fields re-based on builds**: `InstallWimBuild` /
  `BootWimBuild` + `...BuildAgree` replace the retired
  `...HighestKbDate` (an InstallTime-derived value with no per-OS
  meaning); `MeetsPca2023Prereq` is now a measured-build >= floor
  comparison. Displays and the P12 report updated accordingly.

### Tests

- **T37 `per_os_evidence_test.py`** (16 assertions): build
  normalisation, all four resolvers against real package-name shapes
  (including the exact 2026-07 E2E 20348.5256.1.13), floor
  boundaries, checkpoint highest-build-wins, source consensus, and
  the dispatcher throw.


## [update-wsi-2026.07.07-r11.57] - 2026-07-07

Tag: `boot-bridge`. Second fix of the 2026-07-07 E2E (run 2) batch:
Server 2022's boot.wim rejected the target LCU on both indexes. The
surface message was "An error occurred applying the Unattend.xml file
from the .msu package", but the WARNING line carries the real code:
`0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED` -- the IDENTICAL
axis-3 image-side servicing-stack floor that I0.BridgeLcu fixed on
install.wim in the same run (install.wim: bridge first, then LCU,
status=Ok on all 4 indexes; boot.wim: no bridge wired, target LCU
head-on, 0x800f0823). This overturns the r11.53 Install-only routing
rationale ("boot.wim would re-enter WinPE constraints for zero gain")
by measurement, and it is DISTINCT from the Server 2019 closure
(0x80070032 at CBS finalize; D1 probe closed all 6 variants).

### Changed

- **`PatchTargetMap['BridgeLcu']` = Install + Boot** (never WinRE).
- **New sub-phase `B0.BridgeLcu`**: `Build-BootApplySequence` emits it
  FIRST (mirrors I0); applied unconditionally when present [A1],
  supersedence no-ops it on already-current images. For OSes without
  a bridge envelope B0 is empty and skips.
- **Server 2022 `BootWimLcuPolicy` stays `tolerate`**
  [user-adjudicated 2026-07-07]: the next E2E measures whether the
  bridged boot.wim accepts the target LCU. Success => flip to
  `enabled`; a distinct failure code => true closure, flip to
  `disabled`. No spec-shortfall is accepted for 2022 without that
  measurement.

### Tests

- T33 extended to 19 assertions: Install+Boot routing, B0-first
  ordering, bridge in B0 / target LCU in B3.


## [update-wsi-2026.07.07-r11.56] - 2026-07-07

Tag: `p08-plan-scope`. First fix of the 2026-07-07 4-OS E2E (run 2)
batch: Server 2019 P08 failed with "Cannot index into a null array"
inside the WinRE section's inline Where-Object (script line 10726).
Root cause is an r11.54 regression: the policy-branch restructure
captured `$plan = Get-OrInitPatchPlan` inside the NON-disabled branch,
so the `disabled` path (2019) reached the WinRE section with `$plan`
undefined; `@($plan.WinReSequence)` produced `@($null)` and the
scriptblock indexed into `$null.PSObject`. The disabled-skip and
WinRE-decoupling semantics of r11.54 were correct; the variable scoping
was not.

### Fixed

- **`$plan = Get-OrInitPatchPlan` hoisted above the policy branch**
  (single assignment, shared by the boot.wim loop and the WinRE
  section on every policy path).
- **WinRE has-work decision moved BEFORE the install.wim mount.** A
  no-work WinRE pass (e.g. 2019: no SSU / no SafeOS DU lines) used to
  mount + dismount install.wim (60-100s) just to discover there was
  nothing to apply; it now skips the mount entirely.

### Added

- **`Test-WimSequenceHasWork`**: pure, null-hardened, REPL-testable
  replacement for the inline has-work pipeline ($null sequence, $null
  elements, cleanup markers, and empty Patches all mean "no work").
- **T36 `p08_plan_scope_test.py`** (10 assertions): the helper's
  null-hardening matrix (including the exact `@($null)` crash shape)
  plus P08 structure pins (hoisted single plan assignment; has-work
  before mount; inline pipeline gone).


## [update-wsi-2026.07.06-r11.55] - 2026-07-06

Tag: `pca2023-default-auto`. Fourth change of the 2026-07-05 E2E batch
(policy axis) [DECIDED 2026-07-06]: every E2E run left P10 skipped
(default OFF) and every P12 readiness verdict was Warning --
PCA2011-signed boot managers on media built AFTER the 2026-06 PCA2011
signing-CA expiry. The opt-in default made the wrong outcome the easy
one. P10 is already readiness-driven (pre-flight snapshot: Critical =>
skip with warning, Healthy => nothing to do), so running it by default
is safe by construction.

### Changed

- **P10 ConvertPca2023BootManager now runs BY DEFAULT** (readiness-
  driven). The opt-in `-EnablePca2023BootManager` is retired
  (destructive rename, no shim); the new opt-out
  `-SkipPca2023BootManager` keeps the shipped PCA2011-signed boot
  manager for operators targeting older firmware without the 2023
  certs.
- **The Server 2025 gate is KEPT**: conversion on 2025 still requires
  `-ForcePca2023OnServer2025` (certified 2025 platforms carry the
  2023 certificates in firmware; Microsoft documents the conversion
  as not required there). P12's 2025 advisory text updated to match.

### Added

- **T35 `pca2023_default_auto_test.py`** (7 assertions): retired-token
  absence, parameter surface, P10 opt-out + 2025 force gates, default
  falsy opt-out (P10 default-on).


## [update-wsi-2026.07.06-r11.54] - 2026-07-06

Tag: `bootwim-policy`. Third fix of the 2026-07-05 E2E batch (Server
2019 axis, generalised): P08 failed with `0x80070032
ERROR_NOT_SUPPORTED` at CBS finalize when applying the LCU to the 2019
EVAL media's boot.wim -- the same structural closure the 2026-06-12 D1
probe established across all 6 apply variants. The E2E showed boot.wim
LCU-serviceability is a PER-OS property of the committed source media
(2016 succeeds and even materialises the PCA2023 staging set; 2019 is
closed; 2022 is unmeasured; 2025 was broken by the checkpoint
mislabel, fixed in r11.52), so a single boolean cannot express it.

### Changed

- **`Common.EnableBootWimUpdate` (boolean) retired; new per-OS
  tri-state `Common.BootWimLcuPolicy`** (destructive rename, no shim;
  both schemas' Common definitions updated byte-equal). Values:
  `enabled` (strict; failure aborts), `disabled` (boot.wim left as
  shipped), `tolerate` (attempt; on failure downgrade to a Caution,
  dismount the index with `-Discard` -- never commit a partial CBS
  transaction -- log a `bootwim-tolerated-failure` errors.jsonl row,
  and continue). Committed matrix: 2016 `enabled`, 2019 `disabled`,
  2022 `tolerate`, 2025 `enabled`.
- **P08 gate rework: `disabled` no longer skips WinRE.** The old
  boolean gate returned from ALL of P08, silently dropping WinRE
  SSU/SafeOS-DU servicing whenever boot.wim servicing was off. The
  policy now governs only the boot.wim loop; the WinRE section runs
  under its own `EnableWinREUpdate` as designed.
- New pure validator **`Resolve-BootWimLcuPolicyValue`** (case-fold,
  empty defaults to `disabled` -- the safe floor -- and unknown values
  are a typed error, never coerced); profile hydration routes through
  it.

### Added

- **T34 `bootwim_policy_test.py`** (16 assertions): per-OS policy
  matrix in configs + seeds, schema enum + retired-flag absence, and
  the validator's REPL behaviour.


## [update-wsi-2026.07.06-r11.53] - 2026-07-06

Tag: `bridge-lcu`. Second fix of the 2026-07-05 E2E batch (Server 2022
axis): P07 failed after 2m33s with `0x800f0823
CBS_E_NEW_SERVICING_STACK_REQUIRED` -- the EVAL media's in-image
servicing stack (20348.587, loaded from WinSxS for offline servicing)
cannot even OPEN the current combined LCU's CBS payload. This is the
long-identified axis 3 (image-side servicing-stack floor), previously
only a reserved schema seat. Microsoft's documented remedy (per-KB
pages, e.g. KB5094128): "Make sure that your image includes KB5030216
(09/12/2023) or a later LCU. If not, install it on your offline media
before you install the latest update" -- the floor is SSU 20348.1960.

### Added

- **SEED envelope `PatchBaseline.BridgeLcu`** (config + seed schema,
  identical subschema; optional): static per-OS bridge LCU with
  `MinimumImageServicingStack` + `EvidenceUrl` (the floor and its MS
  primary source travel with the data). `data/seed/seed-Server2022.json`
  and `data/config-Server2022.json` carry KB5030216 (Catalog-resolved
  2026-07-06: file `windows10.0-kb5030216-x64_cbe5...fc61.msu`, Digest
  = the FileName-embedded SHA-1 in base64). No other OS needs a bridge
  today (2016/2019/2025 media floors verified satisfied by the same
  E2E run).
- **`ConvertTo-BridgeLcuResolvedPatch`**: single materialisation point
  for the envelope (PatchType `BridgeLcu`, ApplyOrder 0, sha-1
  ExpectedHashes, FLAT landing folder -- deliberately outside the `cu`
  checkpoint-discovery subfolder). Both ResolvedPatches writers (P02
  baseline seeding + post-refresh re-derivation) call it, so a P03
  refresh cannot silently drop the bridge.
- **Sub-phase `I0.BridgeLcu`**: `Build-InstallApplySequence` now emits
  it FIRST; applied unconditionally when present [DECIDED 2026-07-06,
  A1] -- DISM supersedence no-ops it on already-current images.
  Routing is Install-only (`PatchTargetMap['BridgeLcu']`): boot.wim
  would re-enter the WinPE LCU-servicing constraints, and WinRE is
  serviced by SSU + SafeOS DU.
- **`Build-ConfigSkeletonFromSeed`** copies the envelope through in
  canonical key position (after `ChecksumAlgorithm`), so an A00
  rebuild preserves it byte-aligned.
- **T33 `bridge_lcu_contract_test.py`** (17 assertions): envelope
  shape/identity/floor/evidence, Digest/FileName SHA-1 cross-encoding,
  Install-only routing, I0-first ordering, scope pin.


## [update-wsi-2026.07.06-r11.52] - 2026-07-06

Tag: `checkpoint-model`. First fix of the 2026-07-05 4-OS E2E failure
batch (Server 2025 axis): the 24H2 checkpoint cumulative baseline
KB5043080 was modelled as Kind `SSU` and force-applied FIRST to every
targeted WIM; on the (newer, 2026-01-refresh) boot.wim this failed with
`0x80073712 ERROR_SXS_COMPONENT_STORE_CORRUPT` and aborted P08.
Microsoft's checkpoint contract is the opposite: `Add-WindowsPackage`
is invoked with the TARGET cumulative update only, and DISM uses the
PackagePath FOLDER to discover and install prerequisite checkpoint MSUs
only when the image actually needs them (MS Learn "Checkpoint
cumulative updates and the Microsoft Update Catalog"; per-KB DISM
guidance, e.g. the KB5094126 page).

### Changed

- **Config Schema: new Line Kind `Checkpoint`; `uup-checkpoint` now
  REQUIRES it and FORBIDS `SSU`.** The 2025 anchor line (KB5043080) is
  re-labelled `Kind: "Checkpoint"` in `data/config-Server2025.json`;
  `Resolve-Os`/`ConvertTo-ConfigLines`/`Test-PatchModelConsistency`
  emit/accept the new Kind (the schema `allOf` discriminated union and
  its runtime mirror updated in lock-step).
- **Checkpoint entries are never applied standalone.**
  `$Script:PatchTargetMap['Checkpoint'] = @()` -- the checkpoint is
  downloaded and co-located, not routed to any WIM target. The former
  `B1.SSU`/`I1.SSU` force-apply of KB5043080 disappears for 2025.
- **CU discovery folder.** New `Get-PatchLocalPath` lands Kind
  `LCU`/`Checkpoint` under `patches\<OS>\cu\` and every other Kind in
  the flat per-OS folder, satisfying the MS requirement that ONLY the
  target cumulative update and its checkpoints be present in the
  `-PackagePath` discovery folder. Both `LocalPath` writers (P02
  baseline seeding + the post-refresh re-derivation) route through the
  helper; P04 creates the per-patch landing directory. Offline
  pre-place contract moves with it: LCU + Checkpoint under
  `patches\<OS>\cu\`, everything else under `patches\<OS>\`.

### Added

- **T32 `checkpoint_placement_test.py`** (11 assertions): pins the
  landing-folder split, the no-target routing (and that `Checkpoint`
  is a known Type), and the uup-checkpoint Require/Forbid rules.

### Fixed

- T27 expected-Kind set and T23 SSU-consistency rule updated to the
  Checkpoint model (a config carrying Kind `SSU` now implies
  `separate-ssu` only). The T27 raw fixture's 2025 anchor had its
  resolver-owned `kind` label migrated `SSU`->`Checkpoint`; every
  Catalog-truth field (files/urls/digests/titles) stays VERBATIM from
  the 2026-07-02 live capture.


### Fixed -- documentation currency sweep: reconcile README (EN/JA) / SPEC / TESTING / tests/README with the r11.51 implementation (docs-only, no version bump)

A doc-vs-implementation reconciliation pass (mechanical: counts, T-table
vs `tests/` directory, CI workflow steps vs their description) found and
fixed the following stale content:

- **SPEC**: "thirteen Actions" -> fourteen (the actual `ValidateSet`);
  C.9 still described "thirteen numbered tools (T1 through T13)" and its
  determinism list cited the retired/never-shipped T5/T8/T9/T10/T12/T13
  -- rewritten to the real sparse inventory (seventeen numbered tools,
  T1-T31, retired numbers never reused, plus three gates) with eleven
  missing rows added (T20, T23-T31, seed gate) and the format-gate file
  count corrected 26 -> 29; the Part G revision-history table, which
  stopped at "r09.0 (planned implementation)", gains compact rows
  covering r10.x through the r11.44-r11.51 audit-remediation arc.
- **TESTING**: T3 assertion count 10 -> 7; format-gate count 26 -> 29;
  the missing T23 row added; the Stage 1 summary row overstated CI (it
  claimed T2/T3/T6/T7/T11/T20/T24-T27 run in Stage 1 -- the workflow
  actually runs the BOM/CRLF/ASCII check, the config schema gate,
  psa.py and PSScriptAnalyzer) and now states reality, with the full
  offline suite attributed to the local gate battery; the psa /
  encoding / PSAP0005 header rows and the offline-suite rows re-run
  this session are re-stamped "r11.51 audit-residue-sweep / 2026-07-02".
- **tests/README**: the tool inventory and file-layout listings were
  missing ten tests (T20 was listed with a wrong count, T23-T31 and the
  seed/format gates absent); the config-schema-gate description still
  said the validator "requires `NeutralPatches`" (v3.0 requires
  `PatchBaseline.Lines`; both legacy shapes are forbidden); T27's count
  14 -> 16; the CI-relations paragraph referenced the retired T5 and
  claimed T2 is the only CI-runnable tool -- rewritten to the actual
  Stage 1 contents, noting the offline suite as a future Stage 1
  extension candidate.
- **README (EN/JA, lockstep)**: "nineteen tools (T1-T19)" -> the sparse
  T1-T31 inventory (T12-T19 were retired with the wsusscn2 D1 removal),
  in both the directory-tree comment and the self-verification section.

No normative behavior statements changed except where the document
contradicted the shipped implementation.

### Fixed -- eval_iso_probe (T4): replace the URL substring host check with a parsed-hostname exact match (CodeQL alert #52, `py/incomplete-url-substring-sanitization`, CWE-20; tool-only, no script version bump)

The HTTP-400 "unprobable, not broken" special case for Server 2016's
download host tested `'software-download.microsoft.com' in url`. As a
substring check it also matches the allowed host embedded anywhere in
an arbitrary URL (`https://evil.example/software-download.microsoft.com/...`,
`https://software-download.microsoft.com.evil.example/...`), which is
exactly the CodeQL finding. The check now parses the URL and compares
`urllib.parse.urlparse(url).hostname` (lower-cased) exactly against the
allowed host. Verified: the legitimate host still matches; three bypass
shapes (path-embedded, subdomain-suffix, query-embedded) are rejected.
In this probe the URL comes from the committed config rather than an
untrusted source, so the practical exposure was low -- but the check is
also simply more correct: any future URL whose *path* happened to
contain the host string would no longer be mis-classified as the
known-quirky endpoint.

### Fixed / Removed -- final audit residue sweep: SPEC vocabulary tables to v3.0 Kinds, orphaned fixtures deleted, dead-function finding re-dispositioned (r11.50 -> r11.51, tag `audit-residue-sweep`; audit G4 + G5 + G6)

**G6 (vocabulary residue).** Three SPEC tables still presented the
retired pre-migration type vocabulary as normative after the r11.50
retirement: the B.10 target-lane table (now the v3.0 Kind mapping; the
`SetupDU` rationale also corrects "pending.xml" to the real P09
mechanism -- `expand.exe` extraction overlaid onto the extracted ISO
`sources\` tree), the B.10 authoritative `PatchType` enum, and the
per-OS applicability matrix (now expressed as the in-model
Require/Forbid line contract per `PatchModel`, fixing among others the
claim that Server 2022 carries a Setup DU line -- `embedded-ssu-du`
forbids it; only `uup-checkpoint` carries `SetupDU`). B.22.8 is marked
superseded (it described subdividing the retired
`NeutralPatches[].Type` field). The last "v2.0" comment in the script
(P04 `Iso.Sha256` check) is reworded timelessly.

**G5 (orphaned fixtures).** `tests/fixtures/dynamic_update_cache/`
(relic of the retired DU 36-month cache probe),
`tests/fixtures/release_info_resolver/` and
`tests/fixtures/catalog_title_tokens/` had zero referencing tests;
deleted (history stays in git).

**G4 (re-dispositioned, no change).** `Disable-DebugTraceFileOutput`
was flagged as a dead function (zero call sites). Closer inspection
shows it is one third of the documented debug-trace operator API
(`Enable-...` / `Disable-...` / `Get-...Status`, SPEC debug-trace
table), reachable interactively via `-Action TestHarness`, and a
CANONICAL vendored unit (`pwsh.helper.disable-debugtracefileoutput`)
whose body is hash-pinned by the canon drift scanner -- deleting or
even annotating it in place would break canon conformance for no
functional gain. Disposition: keep as-is; recorded here so the next
audit does not re-flag it.

### Removed / Fixed -- retire the three legacy patch-input paths (`-PatchUrls` / `-PatchDirectory` / `-ManifestPath`) and their pre-migration classifier; fix two defects in the post-refresh re-derivation (r11.49 -> r11.50, tag `legacy-input-retirement`; audit G1 + new finding G7)

**Retired (G1).** The three operator patch-input paths predated the
data-source migration and were unsound against today's pipeline on two
independent counts, both proven in the 2026-07-02 final inspection:
(1) their filename classifier `Get-PatchType` emitted a vocabulary
(`DotNet.Runtime` / `DynamicUpdate.*` / `Defender` / `Edge` / `Other`)
that exists neither in `$Script:PatchTargetMap` nor in any
`Build-*ApplySequence` bucket -- unknown types fell to install.wim-only
with a warning and `DotNet.Runtime` silently vanished from every
sub-phase; (2) run against real Catalog filenames (which carry no type
tokens), the heuristic misclassified SSU, SafeOSDU and SetupDU all as
`LCU` (`kb\d+` fires first), so an SSU would apply at LCU order
(0x800f0823 risk) and a SafeOS DU to the wrong images. Removed: the
three parameters, their help blocks, the three P02 Step-3 branches, the
`.meta4` side-car probing, `Read-MetalinkManifest`,
`Get-PatchType`, `Get-PatchApplyOrder` (taking the orphaned
`DotNet.OsLevel` / `Defender` / `Edge` order rows with them -- audit
G6), and the now-constant `$userProvidedPatches` guard. The
PatchTargetMap preamble now documents the real v3.0 Kind mapping
instead of the pre-migration vocabulary (G6); an unreachable
`DotNet.Runtime` comparison in `Select-CanonicalPatchFile` becomes
`-like 'DotNet*'`; the I5 `DynamicUpdate.Component` sub-phase is kept
as an explicitly-annotated reserved slot mirroring Microsoft's
documented sequence. Baseline-driven runs are unaffected; offline runs
remain supported by pre-staging the baseline files under
`<WorkRoot>/patches/<OsVersion>/` (P04 skips verified files), now
documented in both READMEs and the TESTING E2E procedures
(`-UseBaselineOnly` replaces `-PatchDirectory` throughout).

**Fixed (G7, found during this retirement).** The post-refresh
re-derivation block projected `PatchType = $p.Type`, but refreshed Line
objects carry the type under `Kind` (and the script does not run under
Set-StrictMode), so every entry silently got a `$null` PatchType --
after an in-run P03 refresh, all patches dropped out of the apply
sub-phases. It now projects `$p.Kind`, matching the P02 seeding path.
The same block also declared only a `sha-256` expected hash, missing
the `sha-1` Catalog `Digest` wiring the P02 path received under the
`digest-format-boundary` fix; both writers now declare the same
two-layer expectation. (Follow-up candidate: extract the two duplicated
Line->ResolvedPatch projections into one pure helper, the same
single-writer treatment TargetBuildAfterUpdate received.)

### Removed -- retire the dead `-EvalIsoMode` switch and the reader-less `Iso.*` config/seed fields; rewrite SPEC B.7 to the real source-ISO resolution (r11.48 -> r11.49, tag `evaliso-retirement`; audit G2)

The 2026-07-02 final inspection found the evaluation-ISO mechanism had
lost its wiring on every level: the `-EvalIsoMode` switch was declared and
mutual-exclusion-checked but consumed nowhere (the READMEs advertised a
"permit fwlink download" gate that does not exist -- `Resolve-IsoSourceUrl`
uses `Iso.Url` unconditionally); the per-language `Iso.FileName` /
`FwlinkUrl` / `SizeBytes` / `ReleaseDate` fields had zero readers across
the script and the test suite (and were already rotting: `SizeBytes` was
`0` and `ReleaseDate` empty in every committed block); and SPEC B.7
documented a four-pattern ISO filename auto-detection (including an
`EvalIsoBaseName` config key) that has no implementation and no such key.

Retired accordingly: the switch, its help block and both help examples,
the exclusivity check, the four fields in all 16 `LanguageSpecific.*.Iso`
blocks (4 configs + 4 seeds), and the fictional B.7 table. B.7 now
documents the actual three-branch resolution (SyntheticTestMode /
`-IsoPath` / download from `-IsoUrl`-or-`Iso.Url` to
`<OsShortName>_<lang>.iso`) plus the P04 `Iso.Sha256` verification, and
notes that evaluation ISOs remain fully usable via `-IsoPath` / `-IsoUrl`.
Both schemas pin the surviving `Iso` shape (`Url` + `Sha256` +
`_Verified*` provenance, `additionalProperties: false`) so the retired
fields cannot creep back -- the same structural-guard pattern as the
r10.3 legacy-`Patches` guard. `Resolve-IsoSourceUrl` prose also loses its
last "v2.0 config" wording (audit G6, partial). Both READMEs drop the
`-EvalIsoMode` row and exclusivity bullet in lockstep; TESTING's E2E
prep step now stages the ISO via `Iso.Url` / `-IsoUrl` / `-IsoPath`. One
line-number straggler in SPEC that the G3 sweep missed (a reference
wrapped across a line break) is also converted to symbol wording.

### Fixed -- SPEC: replace all raw script line-number references with symbol references (docs-only, no version bump; audit G3)

The 2026-07-02 final inspection mechanically verified all 18 `script L<n>`
references in SPEC against the current source and found the majority stale
(the r11.44-r11.48 edits shifted lines; e.g. a reference to the mutual-
exclusivity guard pointed at a closing brace). Raw line numbers in a
normative document rot on every edit by construction. All 18 are replaced
with stable symbol references (function names such as
`Get-PhaseListByAction`, `Invoke-CleanupAction`, `Get-RefreshDecision`,
`Get-WimIndexInventory`, or named structures such as `$osLessActions`),
each verified to exist in the current source. No behavioral statements
changed.

### Fixed -- clear the six psa.py canon findings that broke stage-1 CI; unmask the text step's exit code (r11.47 -> r11.48, tag `psa-canon-conformance`)

The r11.46 edits introduced six psa.py canon findings that failed the CI
run for that push: four PSAP0005 hits (comments carrying revision-anchored
`[r11.46]` wording -- the canon requires timeless script-body prose, with
history living in CHANGELOG/SPEC), one PSA6003 (the new
`Get-TargetBuildFromLines` noun reads as plural -- justified-disabled, as
"Lines" is the Config Schema v3.0 field name), and one PSA2003 (`-match`
against a bare `$kbPattern` -- justified-disabled; the pattern is
`[regex]::Escape` of a Mandatory string, never null). All four comments are
reworded timelessly (pointing at the CHANGELOG tag instead of the revision
number); behavior is unchanged.

Two process failures let this reach CI and are also fixed: (1) the stage-1
text-analysis step piped psa.py into `tee`, masking the exit code -- the
step stayed green on findings and the run died later at the SARIF step
with no readable finding list; `set -o pipefail` added with a comment.
(2) The local gate runs truncated psa.py output (`tail -1`) and never
checked the exit code -- the session's gate discipline is corrected to
full-output + exit-code checks.

### Changed -- CI: actions/checkout bumped v6 -> v7 across the four stage workflows (workflows-only, no version bump)

Live-verified against the upstream repositories on 2026-07-02:
actions/checkout's latest major is v7.0.0 (2026-06-17); the remaining pins
are already current majors (setup-python v6, upload-artifact v7, cache v5,
codeql-action v4 -- the upstream-recommended major-tag reference --
create-pull-request v8) and are left unchanged. checkout v7's notable
behavior change -- refusing FORK pull-request code checkouts under
`pull_request_target` / `workflow_run` triggers unless
`allow-unsafe-pr-checkout: true` -- does not affect these workflows: stage 2
is `workflow_run`-triggered but this repository's flow is same-repo
push/PR, and the refusal targets fork PRs only (it is a desirable
supply-chain guardrail here, not a regression risk). Older pins found
OUTSIDE this project (checkout@v5 / upload-artifact@v5 in the speakerdeck
and quality-tools workflows) are out of this project's blast radius and are
reported for a separate decision.

### Fixed -- sweep the v2-era schema residue left by the D1/D2 migration (r11.46 -> r11.47, tag `schema-v2-residue-sweep`)

Audit F3. The v3.0 migration updated the loader's CODE (`$acceptedSchemas =
@('3.0')`) but left the surrounding prose and stamps in the v2 era, i.e.
comments actively contradicting the code: the loader docstring claimed it
"accepts Schema 2.0 or 2.1" and described a v2.0-grace soft-warning path
that no longer exists (the code hard-throws); the in-memory PatchBaseline
stub and the A02 FieldClassification payload still stamped `Schema = '2.0'`;
the A01 summary labeled a missing Pca2023 block "(Schema 2.0)"; and
`tests/eval_iso_probe.py` attributed the Iso-URL layout to "Schema v2.0".
All swept to the v3.0 reality (comment-and-stamp changes only; no behavior
change -- the loader accepted only 3.0 before and after). The residue class
is the same one that produced C1: prose/duplicates drifting from the single
authoritative implementation.

### Fixed -- CI: stage1's duplicated inline config validator (hardcoded Schema 2.0/2.1) removed; stage4's stale pre-graduation script path corrected (workflows-only, no version bump)

The 2026-07-02 audit's C1/C2 findings. Stage 1 carried an INLINE Python
copy of config validation that hardcoded `Schema must be '2.0' or '2.1'`,
so every CI run failed after the v3.0 data-source migration -- while the
correct gate (`tests/config_schema_test.py`, schema-file-driven) ran green
in the very same workflow a step later. The duplicate is deleted; the
schema test is now the single config-validation authority in CI, with a
workflow comment forbidding re-inlining (validation logic lives once, in
the test + `schema/config.schema.json`). Stage 4's monthly-refresh job
still pointed at the pre-graduation path
(`scripts\powershell\update-windows-server-iso\...`), so every cron run
since graduation failed on a missing script; the path now targets
`projects\powershell-update-windows-server-iso\`. The stage-4 PR
checklist is reconciled to v3.0 (`Lines[]` + `Digest`; Server 2025
`SetupDU` Line + derived `TargetBuildAfterUpdate`, replacing the retired
`NeutralPatches[]` / `IsCombined` items), and stale `wsusscn2 scan`
comments in stages 2/3 now name the current P03/P06 roles. Root cause
recorded: the D1/D2 migration's blast radius never included
`.github/workflows/` (the Doc-Touching Matrix has no CI row -- a
governance gap deferred to a separate `[AUTH]` session).

### Changed -- TargetBuildAfterUpdate becomes DERIVED with a real consumer; VerificationMethod / ExcludeKbList retired (r11.45 -> r11.46, tag `tbau-derived-lcu-verify`)

Audit F2 found three PatchBaseline fields with zero runtime readers.
`TargetBuildAfterUpdate` was hand-maintained in the seeds and stale on all
four OSes (2025: `26100.32522`, the May build, against a resolved June LCU
of `26100.32995`). `VerificationMethod` was written (`'auto-scrape'`) but
never read. `ExcludeKbList` was never read, and its 2025 entry mis-described
the checkpoint SSU KB5043080 as unnecessary while `Lines[]` applies it at
ApplyOrder 1.

TargetBuildAfterUpdate is now DERIVED: every Lines writer (the in-memory
refresh writeback AND the A00/A01 config-object refresh loop -- the very
first A00 run shipped an empty value because only the former was wired,
caught by T31's data contract) sets it via the single pure helper
`Get-TargetBuildFromLines` from the LCU Line's Catalog-captured
`InScope.build` (staleness becomes
structurally impossible; the value is Catalog-sourced per the data-source
policy), and it gains a consumer -- the new pure comparator
`Test-LcuTargetApplied`, wired into P11 StaticVerify as a HARD Fail row
(`LcuTargetApplied`): the applied LCU package IS the build-attainment
marker, so a serviced image missing the baseline LCU now fails verification
instead of warning [DECIDED 2026-07-02, user]. The check runs only when the
resolved patch set actually intended the baseline LCU, so custom
`-PatchUrls` runs are unaffected. The comparator is pure (no DISM) and
offline-gated by the new T31 `tests/lcu_target_verify_test.py`
(24 assertions: comparator + derivation-helper behavior, data contract,
schema contract, static wiring over both writers).

The two dead fields are retired end-to-end: dropped from the RebuildDataset
placeholder and refresh writer, removed from `schema/config-seed.schema.json`
(the seed `PatchBaseline` envelope is now `Schema` + `ChecksumAlgorithm`
only, `additionalProperties: false` making stale seeds fail loudly) and from
`schema/config.schema.json`, and deleted from all four seeds and configs
(the configs' `TargetBuildAfterUpdate` is set to its derived value in the
same commit). SPEC B.4.3 example + the B.14 SEED/DERIVED matrix reconciled;
TESTING gains the T31 row + run line.

### Fixed -- the 2025 SetupDU line could never resolve on the live Catalog; discriminate by title, recapture the fixture verbatim, and hard-fail silent starvation (r11.44 -> r11.45, tag `setupdu-discriminator-hardfail`)

`Resolve-SetupDu` (introduced r11.38, a production-side invention with no
counterpart in the validated reference resolver set) filtered candidates with
`products.Contains('Setup Dynamic Update')`, assuming SafeOS/Setup symmetry.
The live Catalog has no such product category: a Setup DU row's Products
column is only `Windows 10 and later Dynamic Update` (the reference
architecture memo's resolution-recipes section already recorded this -- only
the SafeOS DU carries a dedicated product string). The filter could never
match; the resolved line came back empty; rule (1) of `ConvertTo-ConfigLines`
silently dropped it; and the committed `config-Server2025.json` shipped
without its SetupDU line while every gate stayed green -- because the T27
fixture had FABRICATED the assumed Products string (audit F1, 2026-07-02;
live probe confirmed the 2026-06 Setup DU KB5095966 exists and is the top
hit for the exact query the script sends).

Fix, three parts: (1) selection is now by TITLE via the new pure
`Select-SetupDuCandidate` ('Setup Dynamic Update' + version token +
'server operating system', not arm64; Products kept only as a
Dynamic-Update-family sanity net), offline-gated by the new T30
`tests/setup_du_discriminator_test.py` (8 assertions) against rows captured
verbatim from the live Catalog. (2) The T27 fixture's SetupDU row is replaced
with the VERBATIM 2026-07-02 capture (uid `3401a3ef-...`, real Products, real
url/digest/sha256/size from DownloadDialog; the fixture note now states the
capture provenance and the never-author rule). (3) Rule (1) of
`ConvertTo-ConfigLines` now HARD-FAILS when a Kind inside the PatchModel's
apply map resolves to 0 files [DECIDED 2026-07-02, user] -- silent drops stay
only for by-design absences (2016 .NET/SafeOSDU, 2019/2022 SSU); T27 gains
the starvation-guard assertions (14 -> 16). SPEC B.22.6 records the corrected
discriminator + the guard; TESTING gains the T30 row and refreshed T27 row.
The committed `config-Server2025.json` still lacks its SetupDU line until the
next `A00 RebuildDataset` run regenerates the dataset with this fix.

### Fixed -- patch verification compared Catalog base64 digests against hex; normalize at a single boundary and wire the SHA-1 primary key (r11.43 -> r11.44, tag `digest-format-boundary`)

Config Schema v3.0 stores `PatchBaseline.Lines[].Digest` (SHA-1) and `.Sha256`
exactly as the Microsoft Update Catalog DownloadDialog serves them: base64.
`Test-PatchIntegrity` compared those expected values directly against
`Get-FileHash` output (hex), so EVERY real download failed verification with
"SHA-256 content mismatch" -- the D2 migration rewired the data source without
reconciling the verifier's expected format (its help still said "Metalink",
the pre-migration source). This was the F4 finding of the 2026-07-02
re-evaluation audit and a hard End-to-End blocker.

Fix: (1) new `ConvertTo-HexDigestString` -- the SINGLE conversion boundary;
expected digests stay base64 at rest (raw Catalog truth; the Digest is the
cross-surface primary key per the reference architecture memo) and are
normalized to hex at comparison time; hex passes through for the
filename-embedded SHA-1 path. (2) Both `Test-PatchIntegrity` expectations
(`sha-1`/`sha-256`) now route through the boundary. (3) P04 ExpectedHashes
seeding now wires `Line.Digest` as the `sha-1` expectation (previously only
`Sha256` was wired; the primary key was never checked). (4) Help text
reconciled from "Metalink" to the Catalog model. Cross-verified on a live
Catalog file (KB5095966): the base64 digest decodes to exactly the
filename-embedded SHA-1. New offline gate T29
`tests/patch_integrity_digest_test.py` (11 assertions) pins the round-trip
against an independent Python implementation, the live vector, the rejection
paths, and the wiring (a bare `.ToLower()` comparison can no longer resurface
silently). SPEC B.4.3 records the digest-format rule; TESTING gains the T29
row + Stage-1 run line.

### Fixed — mark the abandoned r09.0 dependency-database roadmap as superseded in SPEC §G.2 (docs-only, no version bump)

SPEC §G.2 ("Open at r09.0 inception") still listed the wsusscn2-derived
Servicing Dependency Database work -- the `RefreshDependencyDatabase` action and
the `-EnableDependencyCheck` opt-in (r09.0 Steps 1-3) -- as pending / future
work, contradicting §B.19, which already records that the whole approach was
removed in the data-source migration and replaced by `Test-PatchModelConsistency`
(P06 `ValidatePatchServicing`). Reworded the §G.2 block to mark Steps 1-3
**superseded** (retained for historical context, will not be implemented) and
pointed to §B.19 as the authoritative record. The still-accurate Step 4 note --
the KB5087537 SSU-prerequisite incident resolved on the config side as of r11.20
via `Resolve-Ssu2016` -- is preserved. SPEC-only (Part G appendix, not a vendored
Part A region).

### Fixed — reconcile the TESTING.md test inventory to the actual test set (docs-only, no version bump)

The TESTING.md test inventories (both the status matrix and the run-command
catalog) still listed three tests removed by the dead-code cleanups, and omitted
two current ones:

- Removed the phantom entries `T8 dynamic_update_cache_test.py`,
  `T9 catalog_title_tokens_test.py`, `T10 release_info_resolver_test.py` (their
  subsystems and files were deleted in `2eb6d7e` / `79e7ad7`) from both the
  matrix and the catalog, and corrected the Stage 1 summary span `T6-T11` ->
  `T6/T7/T11` (it spanned the deleted tests).
- Added `seed_contract_test.py` (the SEED contract gate, landed in `b340ead` but
  never cataloged) to both inventories, and added the `T28 setup_du_forbid_test.py`
  row to the matrix to match the catalog entry added with T28.
- Verified: every `tests/*.py` referenced in TESTING.md now exists, and every
  offline `*_test.py` is cataloged.

### Added — T28: direct offline unit test for `Resolve-SetupDu`'s Forbid branch (tests-only, no version bump)

`Resolve-SetupDu` had no direct test; its 2025 happy path is covered offline by
T27 (against a captured fixture), but the deterministic Forbid branch that every
non-2025 OS must hit was only exercised indirectly. Added
`tests/setup_du_forbid_test.py` (T28): for each of Server 2016 / 2019 / 2022 it
calls `Resolve-SetupDu` through the TestHarness REPL and asserts the empty
SetupDU "no line" marker (`kind == 'SetupDU'`, no files, no Catalog row, and a
`note` recording the Forbid reason + OS key). Needs no network and no fixture
(the function returns before any Catalog call when `-OsKey != '2025'`). 12
assertions; listed in the TESTING.md offline catalog. Offline `*_test.py` suite
is now 13/13.

### Fixed — README parameter table parity: add 2 missing live params, correct the count (docs-only, no version bump)

The "Parameters (complete)" table claimed "All 35 parameters" but listed 32 and
omitted two live `param()` switches. Reconciled against the `param()` ground
truth (34 parameters) in both READMEs, in lock-step:

- Added `-SkipResetBaseOnCleanup` (omit DISM `/ResetBase` on cleanup;
  `/StartComponentCleanup`-only scavenging) and `-SkipExportCompress` (skip
  `Export-Image /Compress:max`; faster build, larger `install.wim`) to the
  `advanced` group in `README.md` and `README.ja.md`.
- Corrected the table-intro count `35` -> `34` in both READMEs (now 34 rows
  each, matching the 34-parameter `param()` block).

### Removed — retire the write-only data-contract machinery (`r11.42` -> `r11.43`, tag `retire-dead-data-contract`)

The shared data-contract stamp had become a write-only orphan: its sole
consumer `Test-DataContractConsistency` was removed in `79e7ad7`, but the
`_meta.dataContractId` / `dataContractVersion` keys were still stamped into
every config, still REQUIRED by `config.schema.json`, and the schema
description still named the removed function. Confirmed inert (zero readers in
the live script) and, consistent with the project's no-dead-code stance,
removed end to end rather than kept:

- Script: dropped `$Script:DataContractId` / `$Script:DataContractVersion` and
  their comment block; the `_meta` stamp now writes only `scriptVersion` /
  `generatedAt` (the informational provenance), and its local builder was
  renamed `$contractMeta` -> `$metaStamp` to match. `$Script:ScriptVersion`
  bumped to `r11.43` (behavioural change).
- `config.schema.json`: removed `dataContractId` / `dataContractVersion` from
  `_meta.required` and from `properties`, and reworded the `_meta` description
  to drop the data-contract / removed-function framing.
- `data/config-Server*.json` (all four): dropped the two `_meta` keys via the
  canonical-JSON writer (each diff is exactly `-2` lines; all four still
  validate against the updated schema). `_meta.scriptVersion` is left at the
  generating version (`r11.42`) since only dead metadata was stripped, not the
  data.
- A stale claim in the script comment that the stamp was also written into the
  `cache-*.json` files was incorrect (those files never carried it) and is gone
  with the comment.

### Fixed — resolve the 7 unfilled `§D.NN` cross-references in SPEC.md (doc-only, no version bump)

Seven SPEC cross-references were left as the literal placeholder `§D.NN`
(an incomplete-refactoring residue) instead of a concrete target. Resolved
against the live §D section (which runs D.1-D.30 under two group headers).
SPEC-only; the edits are internal cross-references in Part B (not a vendored
Part A region), so no README/TESTING propagation and no `$Script:ScriptVersion`
bump:

- L1232 (umbrella-KB / `Select-AllCanonicalPatchFiles` r04.3 fix) -> **§D.21**
  (Umbrella KBs attach multiple files to one UpdateId).
- L1732 (Catalogue Title comma-form drift, Server 2022) -> **§D.19** (the
  matching pitfall entry).
- The four B.22.21 cross-reference-matrix rows (`$Script:` typo PSA2013 /
  `Write-PhaseHeader` positional PSA2012 / `(if ...)` subexpression PSA1004 /
  idempotent renderers) -> their **§B.22.17 - §B.22.20** sections, where the
  r07.0 incidents are already recorded inline (no separate §D entry exists, so
  pointing to the §B record is the non-duplicative resolution).
- L610 (the `Enable*Update` promotion note) reworded to drop the dangling
  `§D.NN` pointer; the earlier read-but-not-promoted defect has since been
  corrected and the promotion is enforced.

### Fixed — complete the stale-reference cleanup the `2eb6d7e` changelog claimed (test helpers; no script change, no version bump)

The `2eb6d7e` entry claimed it "Cleaned stale docstring/probe references (...,
common/html_parsers.py)", but two stale references to removed symbols survived:

- `tests/common/html_parsers.py` still carried the dead `extract_kb_id` helper —
  a parser-parity mirror of the **removed** `Get-KbIdFromUpdateTitle` PowerShell
  function, with no remaining caller (verified: not in `__init__.__all__`, not
  imported by `catalog_probe.py` / `eval_iso_probe.py`, which use
  `extract_update_ids` / `extract_search_hits` / `extract_supersedes`). Removed
  the function, its section comment, and its module-docstring list entry. `re`
  stays used by the other parsers.
- `tests/common/catalog_client.py` `head_request` docstring said "Used by the
  Eval-ISO and **wsusscn2** probes"; the wsusscn2 probe was removed in the
  data-source migration. Corrected to "Eval-ISO and Catalog probes" (the two
  live probes).

### Fixed — TESTING.md reconciled to the `A00 RebuildDataset` data pipeline (docs/tests only, no script change, no version bump)

`TESTING.md` had not been propagated when `A00 RebuildDataset` landed (r11.42),
and it contradicted this changelog's own claim that A00 "replac[es] the manual
A03 -> A01 prose procedure in TESTING.md §8". Reconciled against the live script
(no `.ps1` change, so no `$Script:ScriptVersion` bump):

- **§8.1** rewritten to lead with the single entry point `-Action RebuildDataset
  -PatchMonth <yyyy-MM>`, documenting A00's five stages (seed validation -> A03 ->
  `Build-ConfigSkeletonFromSeed` -> A01 Force -> non-empty `Lines` verify); the
  manual A03 -> A01 two-step is retained as the equivalent pre-r11.42 path.
- **§2.1 verification checklist** corrected: **14** Actions present (was 13 —
  `RebuildDataset` was missing) and **4** Admin phases **A00 – A03** (was 3,
  `A01 – A03`), matching the `-Action` ValidateSet and the phase registry.
- **§8.1 A03 timing** made self-consistent: step 1 previously read "~30 s" while
  the same section's note recorded the observed "A03 2m28s"; unified to the
  observed value.
- CI Stage-4 (§6.4) is unchanged — that workflow invokes the existing
  `RefreshAllBaselines` action, not A00, so its description stays accurate.

### Regenerate `data/config-Server*.json` from the committed seeds via `A00 RebuildDataset` (data refresh; no script change, tag `data-pipeline-regenerate`)

First end-to-end run of the A00 pipeline (previous entry): rebuild the dataset from `data/seed/seed-Server*.json` + live upstream (Microsoft Learn release-info / .NET CU, Microsoft Update Catalog) for PatchMonth `2026-06`, from empty. A00 Stage 4 reports a non-empty `PatchBaseline.Lines` for all four OS (Server2016=2, 2019=2, 2022=3, 2025=4). The diff against the prior (r11.32-generated) configs is code evolution, not data drift:

- **`Lines` content unchanged** (same `KbId` / `UpdateId` / `DownloadUrl` / `Digest` / `ApplyOrder` per line) EXCEPT one `.NET` leaf `Note` on Server2019/2022/2025 (`superset rollup; in-scope leaf = <os> in-media default .NET runtime (BLOCK 0.T; bundles 3.5)`), which now matches the current `New-Line` text in the script; the older committed `Note` carried a `media-payload def, ` prefix no longer emitted by any code path.
- **Refresh-stamp key order**: `Set-GroupVerifiedState` (`Add-Member -Force`) positions `LastVerifiedDate` / `LastVerifiedBy` / `PatchTuesdayOfBaseline` after `Lines` (the refresher canonical position); the older committed configs had them before `Lines`. Both orders pass `canonical_json_format_check` (key order is not gate-enforced).
- **Stamps + `_meta`**: `LastVerifiedDate` -> `2026-06-28`; `_meta.scriptVersion` -> `update-wsi-2026.06.28-r11.42`; `_meta.generatedAt` refreshed.
- **Upstream caches refreshed in lock-step**: `data/raw-dotnet-cu.json`, `data/cache-dotnet-cu.json`, `data/cache-release-info.json`, `data/raw-release-info.meta.json` re-fetched.
- **Verification**: `canonical_json_format_check` 29/0, `config_schema_test` 14/0, `canonical_json_test` 26/0, `seed_contract_test` 17/0; canon-restamp 58 IN SYNC; governance A-G PASS; doc-gate 0/17. No `.ps1` changed, so no `$Script:ScriptVersion` bump.

### Implement the `A00 RebuildDataset` data-pipeline entry point (`Invoke-AdminPhaseA00_RebuildDataset` + `Build-ConfigSkeletonFromSeed`); rebuild `data/config-Server*.json` from the committed seeds (P2; `$Script:ScriptVersion` set to `update-wsi-2026.06.28-r11.42`, tag `data-pipeline-rebuilddataset`)

P2 of the data-pipeline restoration (design at P0/B.14, SEED contract + gate at P1). Adds the single, gate-checked rebuild entry point the SPEC named but the script lacked: a full `data/` regeneration that is runnable from empty, replacing the manual A03→A01 prose procedure in TESTING.md §8.

- **`Build-ConfigSkeletonFromSeed` (new).** Lays a `data/seed/seed-Server<os>.json` profile into the full config shape with the DERIVED regions as empty placeholders in their canonical key positions (`PatchBaseline.Lines` + refresh stamps, every `LanguageSpecificPatches`, `_meta`), so the normal refresh path fills them in place. The placeholder ordering reproduces the committed config envelope order; the per-group refresh stamps are then (re)written by Set-GroupVerifiedState (Add-Member -Force), which positions them after Lines -- the refresher canonical stamp position -- so a config rebuilt from empty matches what a normal A01 RefreshAllBaselines emits, and may differ in stamp position from an older committed config generated before that path.
- **`Invoke-AdminPhaseA00_RebuildDataset` (new, `A00`, osLessAction).** Pure orchestrator: (0) validate each in-scope seed (exists, parses, `OsKey` matches filename); (1) `Invoke-AdminPhaseA03_RefreshSnapshots`; (2) `Build-ConfigSkeletonFromSeed` -> `Save-CanonicalJsonFile` per OS; (3) `Invoke-AdminPhaseA01_RefreshAllBaselines` in Force mode (fills `Lines` / `LanguageSpecificPatches` / stamps / `_meta` in place); (4) verify each config carries a non-empty `PatchBaseline.Lines`. Honours `-PatchMonth` (required) and `-OnlyOs`. Owns no DebugTrace (A03/A01 manage theirs); network-bearing and hang-prone, so run detached + polled per the data-generation hazard policy, never synchronously.
- **Registration.** `RebuildDataset` added to the `-Action` ValidateSet, the `osLessActions` set, and the action registry (`Id='A00'`) and the action-to-phase dispatch resolver. A01 keeps its `# psa-disable-next-line PSA6003` (A00 inserted above it so the suppression stays adjacent).
- **Docs.** SPEC B.14.1 de-`[PLANNED]` (now implemented); B.6.3 Admin Actions table + B.6.4 `osLessActions` list + the phase-identifier range (`A00`-`A03`) + the data-source table gain `RebuildDataset`; README (EN/JA) Admin Actions section adds the action (four -> five) in lock-step.
- **Verification.** `pwsh` ParseFile 0 errors; PSScriptAnalyzer 0/0/0; `psa.py` clean (config-aware); canon-restamp 58 IN SYNC (canon untouched); governance A-G PASS; drift scanner clean; offline suite green (`seed_contract` 17, `config_schema` 14, `canonical_json_format_check` 29, `canonical_json_test` 26, `catalog_fixture` 13, `release_info` 13, `dotnet_cu` 16, `removed_live_wua` 20) + `powershell_harness` 7/0 (T3) + `catalog_patchset_builder` 14/0 (T27). The A00 *run* itself is deferred to the data-generation step; the offline test of A00 output lands at P3.

### Add the seed contract gate (`tests/seed_contract_test.py`): mechanically coordinate the SEED/DERIVED boundary with the schema (tests + doc; no `$Script:ScriptVersion` change, tag `seed-contract-gate`)

Hardens the foundation before the `A00` builder (P2). The SEED/DERIVED boundary had been hand-derived from the coarse group classification, which let the `PatchBaseline` envelope be silently dropped from the seed (corrected in the preceding entry). This gate makes the boundary a *mechanical* property checked against the schema, so that class of defect cannot recur.

- **`tests/seed_contract_test.py` (new, 17 assertions, no T number — schema gate).** Asserts: (1) **coverage** — every field in `schema/config.schema.json` (top-level and inside `Common` / `PatchBaseline` / `Pca2023` / `AutoRefreshPolicy` / `LanguageEntry`) is classified as exactly one of SEED (admitted by `schema/config-seed.schema.json`) or DERIVED (a declared table whose basis is what the refreshers / `Save-ConfigWithBaseline` actually generate), with no unclassified field, no overlap, and no seed-extra; (2) **projection consistency** — the reused SEED definitions are byte-equal to the config schema's and `PatchBaselineSeed` equals the `PatchBaseline` envelope; (3) **conformance** — every `data/seed/seed-Server*.json` validates against the seed schema (reusing the `config_schema_test` stdlib validator, no new dependency).
- **Efficacy demonstrated.** Injecting an unclassified field into the config schema's `PatchBaseline` fails `coverage[PatchBaseline]` (`unclassified=['NewMysteryField']`); injecting `Lines` into a seed file fails conformance (`PatchBaseline.Lines: additional property not allowed`). Both are exactly the defect classes the gate exists to stop.
- **Docs.** `tests/README.md` inventory + quick-start updated in step (AGENTS §9 AP-3); SPEC B.14.2 gains a sentence recording that the boundary is enforced by this gate, not by prose. No `.ps1` touched, so no `$Script:ScriptVersion` bump.

### Add the SEED contract: `schema/config-seed.schema.json` + `data/seed/seed-Server*.json` (4), extracted from the current configs; reconcile SPEC B.14.2 (data + schema + doc; no `$Script:ScriptVersion` change, tag `data-pipeline-seed`)

P1 of the data-pipeline restoration (design documented at P0, B.14). Makes the SEED — the committed, hand-maintained half of the dataset (SPEC B.14.2) — an explicit, validated artifact, so a full config can later be built from `seed + DERIVED` by `A00` (P2). No behavioural script change.

- **`schema/config-seed.schema.json` (new).** A draft-07 schema that is a *projection* of `schema/config.schema.json`: it reuses the `Common` / `Pca2023` / `AutoRefreshPolicy` definitions verbatim, adds a `PatchBaselineSeed` definition = the **`PatchBaseline` envelope** (`Schema` / `TargetBuildAfterUpdate` / `VerificationMethod` / `ChecksumAlgorithm` / `ExcludeKbList`, with `additionalProperties:false` forbidding the DERIVED `Lines` and the refresh stamps), defines a `SeedLanguageEntry` = the per-language block minus the DERIVED `LanguageSpecificPatches`, requires `[Schema, OsKey, PatchModel, Common, PatchBaseline]`, and sets top-level `additionalProperties:false` with no `^_` pattern — which *forbids* the generated `_meta`. The shared definitions are byte-copied from `config.schema.json` and MUST stay consistent with it (a consistency check lands with the P3 offline tests).
- **`data/seed/seed-Server{2016,2019,2022,2025}.json` (new, 4).** Extracted from the current `data/config-Server*.json` by keeping exactly the SEED regions — `Schema`, `OsKey`, `Common` (incl. its `^_` provenance keys), the **`PatchBaseline` envelope** (`Schema` / `TargetBuildAfterUpdate` / `VerificationMethod` / `ChecksumAlgorithm` / `ExcludeKbList`), `Pca2023`, `AutoRefreshPolicy`, the per-language `DisplayName` / `Iso` / `VolumeLabelPrefix`, and `PatchModel` — and dropping the DERIVED `PatchBaseline.Lines` and its refresh stamps (`LastVerifiedDate` / `LastVerifiedBy` / `PatchTuesdayOfBaseline`), `_meta`, and per-language `LanguageSpecificPatches`. Config key order is preserved; each file is written through the repository-canonical serializer (`canonical_json_dumps`), so the existing `canonical_json_format_check` (which walks `data/`) covers them automatically.
- **SPEC B.14.2 reconciled.** The SEED row that previously named only `LanguageSpecific.<lang>.Iso` is corrected to the full per-language SEED block (`DisplayName` / `Iso` / `VolumeLabelPrefix`); the over-coarse `PatchBaseline | DERIVED` row is split into a SEED **envelope** row (`Schema` / `TargetBuildAfterUpdate` / `VerificationMethod` / `ChecksumAlgorithm` / `ExcludeKbList`) and a DERIVED `PatchBaseline.Lines` row, with a note that the refresh stamps and `_meta` are generated at rebuild; the evidence note is updated from "[PLANNED — P1]" to record that the seed schema and seed files now exist, with the consuming `A00` builder still [PLANNED — P2].
- **Verification.** All 4 seed files validate against `config-seed.schema.json` (jsonschema 4.26.0); a full config is correctly *rejected* by the seed schema (DERIVED regions forbidden). `canonical_json_format_check` 29/0 (now incl. the 4 seed files), `config_schema_test` 14/0 and `canonical_json_test` 26/0 unaffected. Changes confined to `data/` + `schema/` + the SPEC/CHANGELOG; no `.ps1` touched, so no `$Script:ScriptVersion` bump.

### Document the data pipeline in SPEC B.14: add the single rebuild entry point (`A00 RebuildDataset` [PLANNED — P2]) and the SEED/DERIVED boundary; reconcile the stale `PatchBaseline` Refresher name (doc-only; no `$Script:ScriptVersion` change, tag `data-pipeline-spec`)

The `data/` dataset is built from a committed SEED plus DERIVED fields regenerated from upstream, but the orchestration that ties the stages together (`RefreshSnapshots` → build each config) existed only as a manual prose procedure in `TESTING.md` §8 — never as an explicit, gate-checked artifact. That missing, unwritten execution entry point is the documented root cause of recent confusion over what the dataset can and cannot regenerate. This change makes the data pipeline a first-class part of the SPEC, ahead of implementation (P2).

- **`B.14` retitled and restructured** from *Refresh policy and RefreshAllBaselines decision matrix* to *Data pipeline and refresh policy*, split into three subsections: `B.14.1` the canonical rebuild entry point, `B.14.2` the SEED/DERIVED boundary, `B.14.3` the (existing) field-cadence decision matrix. The top-level section number is unchanged, so no `B.15`+ renumbering and no cross-reference churn; the Table of Contents entry is updated in step.
- **`B.14.1` — `A00 RebuildDataset` [PLANNED — implemented at P2].** Specifies the single from-empty rebuild entry point (`-PatchMonth` required; runnable with no pre-existing `data/config-Server*.json`), its four ordered stages (seed validation → `RefreshSnapshots` → config build → verification), and its detached+polled execution requirement (long-running / hang-prone per handoff B.2.9). Explicitly tagged `[WORKING]` / `[PLANNED]`: the live Admin Actions remain `A01`/`A02`/`A03` (`B.6.3`) until P2 lands `A00`, so no Action-list drift (AGENTS §9 AP-2) is introduced.
- **`B.14.2` — SEED vs DERIVED boundary.** Tabulates every config region as SEED (committed: `Schema`/`OsKey`/`PatchModel`, `Common`, `Pca2023`/`AutoRefreshPolicy`, `LanguageSpecific.<lang>.Iso`) or DERIVED (`PatchBaseline`, `LanguageSpecific.<lang>.LanguageSpecificPatches`, `_meta`), each with its source. Records the script-body ground truth that both DERIVED Refreshers take only `-OsVersion`/`-PatchMonth` and read the caches — they do not read the existing config — which is what makes a from-empty build possible.
- **Stale Refresher name reconciled.** The `B.14.3` matrix listed the `PatchBaseline` Refresher as `Resolve-PatchSetFromCatalog`, which does not exist in the current script; corrected to `Invoke-CatalogPatchSetRefresh` (script L5283, the only matching function). Evidence basis added inline (function locators) per the evidence-explicitness principle.

 (11 functions, ~590 lines); move OS-scoping documentation onto the Catalog Products column (`$Script:ScriptVersion` -> `update-wsi-2026.06.28-r11.41`, tag `dynamic-update-cache-removal`)

The follow-up flagged by the previous entry. The b3 producer scopes Catalog hits to an OS by the structured **Products** column (`Get-ServerRow` matches the per-OS token in `$script:CatOsDef`, e.g. `Microsoft Server operating system-21H2`), never by parsing the update Title. That left the entire config-driven Title-token matching path -- and the Dynamic Update cache that was its only runtime consumer -- with no live caller. A block-comment-stripped reachability pass over the post-call-site-edit tree confirmed a closed dead set of 11 functions; `PSScriptAnalyzer` is 0/0/0 after removal (no live caller dangled). Removing the Title-token mechanism does not re-expose the §D.19 comma-drift failure class: the Products column is structured metadata, immune to Title punctuation drift, so it supersedes (rather than merely replaces) the Title-token safeguard.

- **Functions removed (11).** Dynamic Update 36-month cache family (`Get-DynamicUpdateCachePath`, `New-EmptyDynamicUpdateCache`, `Get-DynamicUpdateCache`, `Save-DynamicUpdateCache`, `Test-DynamicUpdatePatchMonth`, `Add-DynamicUpdateCacheEntry`, `Get-DynamicUpdateProbePlan`); and the four Catalog-title helpers used only by the A03 DU probe, not by the b3 producer (`Get-CatalogTitleTokenList`, `Test-CatalogTitleMatch`, `Select-LatestPatchBySupersedence`, `Get-KbIdFromUpdateTitle`). The `$Script:DynamicUpdateCacheWindowMonths` / `$Script:DynamicUpdateCacheSchema` / `$Script:CatalogTitleNegativeTokens` script vars were dropped with them. The cache-free live DU resolvers (`Resolve-SafeOsDu` / `Resolve-SetupDu`, always-latest) are untouched.
- **A03 restructured.** `Invoke-AdminPhaseA03_RefreshSnapshots` drops its third sub-step (the Dynamic Update probe): now two sub-steps (release-info, .NET CU), with the `$duResults` accumulator, the per-DU summary CSV rows, and the `[N/3]` labels updated to `[N/2]`. `Show-RefreshSnapshotsSummary` loses its `$DuResults` parameter and the `[2] Dynamic Update probes` render block (sections renumbered).
- **Data + tests.** Removed `data/cache-dynamicupdate-Server2022.json` and `-Server2025.json` (the only two cache files; no build-time reader). Removed `catalog_title_tokens_test.py` (T9, the sole offline-suite failure after the helpers were dropped). Retargeted the T3 harness (`powershell_harness.py`): dropped `test_get_kb_id_extraction` (used `Get-KbIdFromUpdateTitle`), 7 cases remain and pass.
- **Config + schema.** Removed the now-unused `Common.CatalogTitleTokens` field from all four `data/config-Server*.json` (canonical re-serialized) and its (optional) property from `schema/config.schema.json`.
- **Docs reconciled.** SPEC §B.22.2 retitled *Catalog OS-scoping: Products column* (was *Catalog Title token matching*) and §B.22.6 retitled *Dynamic Update: always-latest resolution* (was *36-month cache*); the §B.22.5 .NET carry-forward paragraph and the §D.19 fix/mitigation were rewritten to the Products-column reality; the file tree dropped the two cache files plus the `T8`/`T9`/`T10` test lines (`T8`/`T10` were left over from the previous entry's reconciliation); the T9 inventory row and the `Select-LatestPatchBySupersedence` helper-table row were removed. README.md / README.ja.md / tests/README.md were reconciled lock-step (`T3` count 8 -> 7, T9 run-line and Title-token troubleshooting updated; bilingual `##`/`###` counts preserved at 16/12).

### Remove the dead pre-b3 legacy resolution subtree (21 functions, ~1.2k lines) and reconcile its test/SPEC/README references (`$Script:ScriptVersion` -> `update-wsi-2026.06.28-r11.40`, tag `legacy-resolution-removal`)

The b3 data-source migration rewired the Refresher to `Invoke-CatalogPatchSetRefresh` (live Catalog scrape + release-info reconciliation), leaving the entire pre-b3 release-info-discovery resolution path unreferenced. A block-comment-stripped reachability analysis (roots = top-level + the two active Refreshers + the 58 canon regions) confirmed a closed, self-referential dead set of 21 consumer-owned functions with no live entry point; `PSScriptAnalyzer` is 0/0/0 after removal (no live caller dangled).

- **Functions removed (21).** Release-info discovery cluster (`Resolve-PatchSetFromReleaseInfo`, `Get-PatchSetFromReleaseInfoDiscovery`, `Select-AllCanonicalPatchFiles`, `Get-KbIdFromPatchFileName`, `Convert-CatalogPatchToBaselineEntry`); supersedence-scrape pair (`Get-SupersedenceFromCatalog`, `ConvertFrom-CatalogSupersedenceSection`); catalog-query orphans (`Get-CatalogScoped` [+ nested `_grab`], `Get-CatalogQueryUrl`, `Test-IsCombinedLcuTitle`, `Get-HeadSize`); DU-window helpers reachable only from the dead cluster (`Get-LatestDynamicUpdate`, `ConvertTo-DynamicUpdatePatchMonthSortKey`, `Get-DynamicUpdateWindowEarliestPatchMonth`, `Remove-DynamicUpdateOutsideWindow`); and standalone orphans (`Format-MegabyteCount`, `Get-IsoMetadata`, `Write-MetalinkManifest`, `Get-PatchListForWinReWim`, `Test-DataContractConsistency`). The orphaned `$Script:LastSupersedenceExclusions` script var (assigned only inside the removed resolver, never read) was dropped with them. The live DU-cache read/write family (still written by A03) and the live DU resolvers (`Resolve-SafeOsDu`/`Resolve-SetupDu`, cache-free) are untouched -- the always-latest DU-cache retirement is a separate follow-up.
- **Tests reconciled.** Removed three offline tests that exercised only the dead set (`release_info_resolver_test.py` T10, `supersedence_section_test.py`, `dynamic_update_cache_test.py` T8). Retargeted the T3 harness (`powershell_harness.py`): dropped the two dead cases (`Select-AllCanonicalPatchFiles`, `Test-IsCombinedLcuTitle`), 8 cases remain and pass. Cleaned stale docstring/probe references (`catalog_probe.py`, `catalog_fixture_test.py`, `common/html_parsers.py`).
- **SPEC/README reconciled.** SPEC B.22.1 rewritten from "release-info as canonical source" to the b3 reality (Catalog scrape resolved + release-info reconciled); removed-function rows dropped from the helper inventory and the T-inventory (T8/T10); current-tense references in B.15.2 / B.22.6 / the r11.20 SSU note repointed to the b3 `Resolve-Net` / `Resolve-Ssu2016` resolvers. Genuine r04.x/r07.0 fix-history and the existing "removed in migration" notes were preserved as history. `README`/`README.ja` test-run list and troubleshooting row updated in lock-step (heading counts unchanged).
- **Scope.** `projects/powershell-update-windows-server-iso/` only; `.ps1` (all removals outside every canon region) + `tests/` + SPEC/README/tests-README. ScriptVersion -> r11.40.

### Wire `AutoRefreshPolicy.ScrapeRetries` into the b3 producer and drop the vestigial `-OsLanguage` refresher parameter (`$Script:ScriptVersion` -> `update-wsi-2026.06.28-r11.39`, tag `catalog-scrape-retry`)

`Invoke-CatalogPatchSetRefresh` carried two body-unused parameters that the static-analysis gate flagged (`PSReviewUnusedParameter`): `-OsLanguage` and `-MaxRetries`. They are different in kind and are resolved differently.

- **`-MaxRetries` wired (not removed).** `ScrapeRetries` is a documented (`README`/`README.ja`) and configured (all four `config-Server*.json` `AutoRefreshPolicy.ScrapeRetries`) policy, but the b3 producer body never consumed it -- the documented scrape-retry was never implemented after the migration. The live `Resolve-Os` scrape is now wrapped in a `$MaxRetries`-bounded retry loop with exponential backoff (1s/2s/4s), re-attempting a whole-scrape failure before rethrowing on the final attempt. Individual HTTP requests already retry transient network/429/503 inside the canonical `Invoke-WebRequestWithRetry`; this is the coarser scrape-level net the policy describes. Config + README unchanged (they were already correct; only the code caught up).
- **`-OsLanguage` removed.** The neutral `PatchBaseline` is language-independent by Microsoft's design (cumulative SSU/LCU/.NET/DU are language-neutral; language packs are resolved separately by `Resolve-LanguageSpecificPatchesFromCatalog`), so the parameter was genuinely vestigial. Dropped from the signature and both call sites; `Resolve-Os` takes only `-OsKey`.
- **Result.** `PSScriptAnalyzer` 0/0/0 (the two `PSReviewUnusedParameter` warnings cleared).
- **Scope.** `.ps1` only (the b3 producer + its two call sites, all outside every canon region); no config/README/schema change. ScriptVersion -> r11.39.

### Restore offline config-dataset construction for the b3 producer (T27), and reconcile SPEC/TESTING/`tests/README` to the r11.35-r11.38 apply-path completion (docs + `tests/` only, no `$Script:ScriptVersion` change)

The b3 producer (`Resolve-Os`) scrapes the live Catalog and -- unlike the pre-D2 release-info path (T10) -- no Python-drivable offline builder was carried forward, so the v3.0 config baseline could no longer be (re)built without network I/O. This restores that path and documents the r11.35-r11.38 work recorded below.

- **Offline builder (T27, `catalog_patchset_builder_test.py`).** Drives `ConvertTo-ConfigLines` through the TestHarness REPL -- the `-RawResolved` injection point the orchestrator documents ("live `Resolve-Os` in production; the captured fixture in tests") -- against a committed layer-1 raw fixture (`tests/fixtures/catalog_raw/resolve-2026-06.json`: the four-OS `{ os; lines[] }` capture plus a Server 2025 `SetupDU` raw line) to BUILD `PatchBaseline.Lines[]` offline. 14 assertions: per-OS Kinds match the `PatchModel` allowed set, every Line carries a `Digest`, the uup-checkpoint OS builds a `SetupDU` Line at `ApplyOrder` 5. `T27` is the next free tier (the `T12`-`T22` servicing-dependency block was retired in D1). Live acquisition is unchanged and remains the T1 probe's / UAT's job.
- **Docs reconciled.** SPEC B.4 `EnableInstallWimUpdate` corrected to `true` for all four OS (the Server 2025 placeholder `false` was flipped in r11.37). TESTING P06 row: `ValidatePatchServicing` now runs the per-`PatchModel` consistency check (`Test-PatchModelConsistency`, fed by the promoted `PatchModel`) instead of a pass-through stub. TESTING + `tests/README` tier inventory extended with T27.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; docs + `tests/` + fixture; no `.ps1` change. (Pre-existing: the in-code `$Script:ScriptTag` is stale at `dism-scratchdir-localisation` -- unchanged since before r11.35 -- and is flagged for separate alignment.)

### SetupDU acquisition: add `Resolve-SetupDu` to the b3 producer (`$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.38`, tag `setupdu-acquisition`)

`SetupDU` was the one `Kind` with no producer in the b3 data-source: the migration ported resolvers for `LCU`/`SSU`/`DotNet`/`SafeOSDU` but deferred the Setup Dynamic Update one ("added by the resolver extension upstream, not here"). The consumer side was already complete after r11.36 (P09 overlay filters `SetupDU`; `$Script:PatchTargetMap` routes it to `Setup`; the `uup-checkpoint` applyMap gives `ApplyOrder` 5), so only acquisition was missing.

- `Resolve-SetupDu` mirrors `Resolve-SafeOsDu`, differing only by the Catalog Products discriminator (`Setup Dynamic Update` vs `Safe OS Dynamic Update`) -- the same pairing the legacy data-source discovered together via `@('DynamicUpdate.Setup','DynamicUpdate.SafeOs')`. Setup DU is published only for the UUP-checkpoint OS (Server 2025/24H2); the other models Forbid it, so it is wired into the 2025 branch of `Resolve-Os` only and returns an empty placeholder elsewhere.
- **Verification.** Offline FT (mocked Catalog rows incl. the real KB5095966 title plus SafeOS/arm64/21H2 decoys): the resolver selects the x64 Setup DU and rejects the decoys; downstream the line transforms to a `SetupDU` Line (`ApplyOrder` 5), passes consistency, classifies as `SetupDU`, routes to `Setup`, and is selected by P09's filter. 10 assertions. Live acquisition + the `expand.exe` overlay of the real CAB remain UAT scope.
- **Scope.** `.ps1` only; the b3 acquisition region (outside all canon regions). ScriptVersion -> r11.38.

### Complete the v3.0 config-loader and apply-path gating (`$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.37`, tag `v3-config-loader-completion`)

The D2 migration moved configs to Config Schema v3.0 (`PatchBaseline.Lines[]`) but the loader and several gates still assumed the v2.x shape, so a v3.0 build failed to start or silently skipped apply phases. Four fixes, all reproduced offline against the four landed configs:

- **Schema gate (blocker).** `Get-ConfigProfile` (and the admin RefreshAllBaselines loop) accepted only `2.0`/`2.1` and threw on `3.0`; both `acceptedSchemas` sets -> `@('3.0')`, the `Pca2023`-required check keyed on the single v3.0 schema.
- **`PatchModel` promotion.** The flat profile omitted `PatchModel`, so `$OsProfile.PatchModel` was `$null` and P06 could not run; `PatchModel` is now promoted into the profile.
- **`Enable*` flags.** Only `EnableInstallWimUpdate` was present; `EnableBootWimUpdate`/`EnableWinREUpdate` were absent from every config, so P08 (boot.wim) and the WinRE sub-block skipped (`-not $null`). Both flags added (`true`) to all four configs' `Common`. The Server 2025 `EnableInstallWimUpdate` placeholder `false` was set `true` so the monthly LCU integrates into install.wim like the other OS.
- **Baseline freshness/usability.** `Test-PatchBaselineFresh`/`Test-PatchBaselineUsable` read `PatchBaseline.Patches` (v2.x) and gated usability on `.Sha256` (empty on most v3.0 Lines -- e.g. every Server 2016 Line); both now read `.Lines` and gate on `.Digest` (the v3.0 primary key). The legacy `.Patches` branch in P02's baseline-seeding is removed (no shim).
- **Scope.** `.ps1` + the four `config-Server*.json`. ScriptVersion -> r11.37.

### Fix v3.0 apply-path patch-type routing (Kind taxonomy reconciliation, `$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.36`, tag `apply-path-kind-taxonomy`)

After D2 the apply path still bucketed patches by the v2.x `Type` / legacy names while v3.0 Lines carry `Kind`, so every patch mis-classified.

- P02/P03 build `ResolvedPatch.PatchType` from `.Kind` (was `.Type`, empty under v3.0); `Get-PatchEntryType` precedence reordered to `PatchType` -> `Kind` -> `Type`.
- The apply sub-phase builders rekeyed to the v3.0 Kinds: install-apply `DotNet` (was `DotNet.Runtime`), WinRE-apply `SafeOSDU` (was `DynamicUpdate.SafeOs`), P09 `SetupDU` (was `DynamicUpdate.Setup`).
- **Verification.** Offline FT (function-level, AST-extracted): `SSU` -> I1.SSU, `LCU` -> I3.LCU.FirstPass, `DotNet` -> I4.DotNet, `SafeOSDU` -> W3.SafeOsDU. ScriptVersion -> r11.36.

### Complete the b3 integration: rewire P03 RefreshPatchBaseline to the Catalog producer (`$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.35`, tag `b3-p03-rewire`)

Completes the D2 acquisition wiring: P03 `Invoke-SetupPhase03_RefreshPatchBaseline` calls `Invoke-CatalogPatchSetRefresh` (the b3 L1->L3 chain) as its refresh producer; the legacy release-info producer `Resolve-PatchSetFromReleaseInfo` is left in place with no live callers, pending removal in a later cleanup. ScriptVersion -> r11.35.

### Wire the Microsoft Update Catalog as the production data source: replace the wsusscn2 `NeutralPatches[]`/`Type` model with the Catalog-driven `Lines[]`/`Kind` model (`$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.34`, tag `catalog-data-source-d2`)

The acquisition half (D2) of the `wsusscn2` -> Microsoft Update Catalog migration: wires the b3 hybrid resolver into the script and moves the config/schema to Config Schema v3.0. There are no downstream consumers, so the old patch model is removed with no compatibility shim.

- **Producer (b3 hybrid, mutual-complement).** Layer 1 seed-only Catalog acquisition (faithful port of the reference `Resolve-CatalogPatchSet.ps1` production half: Microsoft Learn release-info -> Catalog Search/DownloadDialog -> raw lines) -> `ConvertTo-ConfigLines` (transform) -> Layer 2 release-info reconciliation (`Reconcile-CatalogAgainstReleaseInfo`, a Catalog-external oracle on `cache-release-info.json`) -> Layer 3 `Test-PatchModelConsistency`. `Invoke-CatalogPatchSetRefresh` chains L1->L3 and is the new A01 Refresher.
- **Consumer / apply.** `$Script:PatchTargetMap` rekeyed to the Kind taxonomy (`LCU`/`SSU`/`DotNet`/`SafeOSDU`/`SetupDU`); `Get-PatchEntryType` reads `.Kind` first; the obsolete legacy-DotNet split guard is removed; P06 `ValidatePatchServicing` runs the per-`PatchModel` consistency check (replaces the D1 pass-through).
- **Data / schema / config.** `config.schema.json` -> Config Schema v3.0 (`Lines[]`/`Kind` + top-level `PatchModel` discriminated union; `Digest` required non-empty; legacy `Patches`/`NeutralPatches` forbidden via `not.anyOf`). The four `config-Server*.json` regenerated from real Catalog data (per-file SHA-1 `Digest` cross-validated against the published servicing baseline), re-serialised canonically. T23 (`config_required_ssu_downloadurl`) + its fixture migrated to `Lines`/`Kind`/`PatchModel`.
- **Docs.** SPEC.md B.4 (Config Schema v3.0), B.12 (Catalogue scrape and candidate selection), B.13/B.15 (`PatchModel` supersedes `IsCombined`/`RequiresKbIds`), and C.3.3 updated to the v3.0 model; the B.19 reserved placeholder is filled with the `Test-PatchModelConsistency` / P06 contract (the discriminated-union table). README (EN + JA) and TESTING reconciled in lock-step; the `wsusscn2`/`IsCombined`/supersedence history is preserved as historical record in B.22 and the D-section.
- **Verification.** psa.py 0/0/0, governance-state validator A-G, `canon-hash-restamp` IN SYNC, `doc_gate` PASS (17 files), `canonical-drift-scanner` 97/5, offline suite 14/0, Part-C PASS. The script/config/schema/test half landed on `main` as the D2 commit (iso-subtree byte-match verified); this entry plus the SPEC/README/TESTING reconciliation complete the documented basis.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; no vendored Part A / canon region touched. ScriptVersion -> r11.34.

### Migrate the servicing-readiness data source from `wsusscn2.cab` to the Microsoft Update Catalog: remove the offline dependency-database facility (`$Script:ScriptVersion` -> `update-wsi-2026.06.27-r11.33`, tag `wsusscn2-catalog-migration-d1`)

Retires the wsusscn2-derived Servicing Dependency Database (the offline applicability-graph "Layer 2" facility) in favour of the Microsoft Update Catalog as the production data source. This is the removal half (D1) of the migration; the Catalog-model consistency check that replaces the graph readiness gate is a separate follow-up. There are no downstream consumers, so the removal is destructive with no compatibility shim.

- **Tests.** Remove the 12 `tests/servicing_dependency_*.py` files (T12-T19, T21-T22, the scope-invariants gate, the Layer-2 schema gate), `tests/wsusscn2_probe.py` (T5), and the `tests/common/` + `tests/fixtures/servicing-dependency/` support; `tests/README.md` updated. T20 (`removed_live_wua_guard`) and T23 (`config_required_ssu_downloadurl`) are model-neutral and stay.
- **Script.** Remove 15 functions (the OfflineSync / ServicingDependency parser pipeline, `Invoke-AdminPhaseA04_RefreshDependencyDatabase`, `Update-Layer1DependencyVerification`, `Test-PatchServicingReadinessFromGraph`), the four OfflineSync GUID tables, the `RefreshDependencyDatabase` action (A04) and its ValidateSet member, the `-OfflineSyncPackagePath` parameter, and the A01->A04 chain. P06 `ValidatePatchServicing` becomes a pass-through; real servicing readiness is validated on-mount by `Test-PatchServicingReadinessOnMount` (SPEC B.13). The 7-Zip helper trio, the CanonicalJson group, the DataContract mechanism, and `Build-PatchPlan` are retained.
- **Data / schema / config.** Delete `data/servicing-dependency-database.json` and `schema/servicing-dependency-database.schema.json`; remove `PatchBaseline.OfflineSyncPackage` and the root-level `_DependencyVerified*` fields from all four `config-Server*.json` (re-serialised canonically) and from `config.schema.json`.
- **Docs.** SPEC B.19 is reserved with a placeholder pointing at the Catalog-model replacement; the scattered current-state references across SPEC, TESTING, and README (EN + JA) are reconciled in bilingual lock-step; the D.18 lesson and the r09.0 release history are preserved as historical record.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; no vendored Part A / canon region touched. ScriptVersion -> r11.33.

### Data: regenerate the 2026-06 monthly `/data` baseline (Layer 1 + Layer 2 + caches) and advance the T23 Server 2016 SSU KbId (no `$Script:ScriptVersion` change)

Regenerates the shipped monthly baseline from 2026-05 to **2026-06** via the TESTING §8 procedure (A03 `RefreshSnapshots` -> A01 `RefreshAllBaselines -Mode Force -PatchMonth 2026-06 -OfflineSyncPackagePath <cab>` -> A04 `RefreshDependencyDatabase`) against the published 2026-06 `wsusscn2.cab` (SHA-256 `5b075a6d9fdaa1751b8c70bf164531163e6750444e9100453f96dce3a4eec122`, 649,341,212 bytes). Data-only; the script is untouched, so **no `$Script:ScriptVersion` bump**.

- **Resolved 2026-06 patch set** (Patch Tuesday `2026-06-09`; cross-checked against the live Microsoft release-health page, §B.22.1): Server 2016 LCU **KB5094122** + standalone SSU **KB5094141**; Server 2019 LCU **KB5094123**; Server 2022 LCU **KB5094128** + DynamicUpdate.SafeOs KB5094157; Server 2025 LCU **KB5094125** (+ KB5043080 checkpoint) + DynamicUpdate.Setup **KB5095966** + DynamicUpdate.SafeOs KB5094150. As with the prior baseline, the LCU/SSU/.NET `SizeBytes`/`Sha256` ship `0`/`""` for the real-machine download+verify step to populate.
- **Standalone SSU auto-discovered (r11.20 path).** The Server 2016 same-month SSU **KB5094141** (UpdateId `a5501aa9-aad8-4dc4-922b-23b02e4fe0bf`, `Supersedes: [KB5088064]`) was resolved with its `DownloadUrl` by the A01 Catalog title-search discriminator — no hand-fill, on the `RefreshAllBaselines` path. Server 2019/2022/2025 stay `IsCombined=true` (no standalone SSU found), as designed.
- **.NET CU carried forward (r11.27 path).** 2026-06 is a .NET publication gap (the .NET release-notes index lists 2026-05 as the latest); discovery carried the most-recent applicable `DotNet.Runtime` CU forward for all four OS (e.g. Server 2016 KB5087065) rather than dropping it — the §B.22.5 36-month-window behaviour, verified in the regenerated configs.
- **T23 advanced (same-commit rule, TESTING §8.2).** `tests/config_required_ssu_downloadurl_test.py` hard-codes the current-month Server 2016 SSU KbId; advanced `KB5088064` -> `KB5094141` (the real-data assertion + its explanatory comment). The generic data-driven SSU assertions were unaffected. Offline suite: 26/26 `*_test.py` green on the regenerated data.
- **Open findings routed to the maintenance layer (NOT baked into the baseline):** Server 2019 Layer 1 `IsCombined=True` vs Layer 2 `servicingStackModel=separate` (the two-axis label split) still reproduces; the image-side servicing-stack-floor third axis for combined-model offline servicing remains an open modelling question; Server 2025 DynamicUpdate.Setup KB5095966 is present in 2026-06 (contra an earlier "discontinued" framing). These are recorded for separate investigation alongside the upcoming patch-application-model work.
- **Verification.** G1-G5 green (G1 cab differs from the prior committed `_meta.sourceCab` `e51d4b5a…`; G2 refreshed `data/raw-release-info.md` lists 2026-06; G3 every config `PatchTuesdayOfBaseline=2026-06-09` over this-month KBs; G4 Layer 2 `_meta.sourceCab.sha256` = the staged cab, `generatedAt 2026-06-13`; G5 psa.py 0/0/0, offline suite green, `canon-hash-restamp` IN SYNC, `doc_gate` PASS, governance-state validator A-G).
- **Scope.** `projects/powershell-update-windows-server-iso/` only — `data/*`, the T23 test, this CHANGELOG, and the TESTING §8.4 real-run log; no `.ps1` change, no vendored Part A region touched.

### Read PCA2023/PCA2011 boot signatures from the EMBEDDED signature via signtool (`$Script:ScriptVersion` -> `update-wsi-2026.06.13-r11.32`, tag `signtool-embedded-readiness`)

The shared signer classifier `Test-Pca2023AuthenticodeChain` now prefers the EMBEDDED signature read by `signtool /v /all /pa`, falling back to `Get-AuthenticodeSignature` + X509Chain only when signtool is unavailable. `Get-AuthenticodeSignature` follows the catalog / cross-cert path, which under-reports the LCU-materialized PCA2023 boot manager: a file whose embedded signature is “Windows UEFI CA 2023” can be read as “Windows Production PCA 2011” (§B.16.3). This is most consequential on the converted OUTPUT `bootx64.efi`, where the catalog read made `Test-OutputIsoPca2023Readiness` Target #1 report a successful PCA2023 conversion as still-PCA2011 (false Fail).

- **One fix, three call sites.** `Test-Pca2023AuthenticodeChain` is the single classifier behind `Get-IsoBootCertReadiness` (media `bootx64.efi`) and `Test-OutputIsoPca2023Readiness` (output Targets #1/#2), so the embedded read corrects all of them, including the false Fail on the converted output.
- **`Get-SignToolEmbeddedClass`** runs `signtool verify /v /all /pa` and classifies 2023/2011 from the `Issued to:` subjects across every embedded signature (plain arrays; no generic-list `@()` cast, which throws on PowerShell 7.5/7.6).
- **`Get-ResolvedSignToolExe`** resolves signtool.exe and, if absent, performs a one-time auto-install via `Install-WindowsSdkFallback` (§B.22.22), memoized for the run. When signtool stays unavailable the X509 verdict stands and the new `.Method` field on the result records which path was used.
- **Docs.** SPEC §B.17.2 / §B.18.1 document the embedded-preferred classification; `Test-OutputIsoPca2023Readiness`'s docstring is corrected (it is no longer “only Get-AuthenticodeSignature”); `README.md` / `README.ja.md` add a Windows SDK Signing Tools requirement row in lock-step. ScriptVersion -> r11.32.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; new functions added outside all canonical markers; no vendored Part A region touched.

### Auto-install the Windows ADK Deployment Tools when missing; remove the `-AutoInstallAdk` switch (`$Script:ScriptVersion` -> `update-wsi-2026.06.13-r11.31`, tag `adk-auto-install`)

Aligns ADK/oscdimg acquisition with the script's dominant tool-acquisition policy: install-if-missing with no switch, matching 7-Zip (§B.19.4) and the signtool acquisition added in r11.30 (§B.22.22). Previously ADK was the lone opt-in (`-AutoInstallAdk`); P01 now auto-installs the Deployment Tools feature whenever `oscdimg.exe` is missing, exactly as it already does for 7-Zip.

- **`-AutoInstallAdk` removed** (parameter, `$Script:AutoInstallAdk`, `.PARAMETER` doc, the `.EXAMPLE` usage, and the P01 opt-in branch). The previous "throw an actionable error and abort" arm is gone; `Install-WindowsAdkFallback` still throws a clear error if the install fails or `oscdimg.exe` is still absent afterwards, so a genuine failure remains actionable.
- **P01 wiring.** The Resolve-OscdimgExe-fails branch now auto-installs unconditionally (after the existing "action does not need oscdimg" and `-SyntheticTestMode` guards), mirroring the 7-Zip `Get-SevenZipPath` / `Install-SevenZipFallback` path.
- **Docs.** SPEC §B.22.13 rewritten (opt-in -> auto) and the stale `-AutoInstallAdk` dropped from the §C.5 synthetic example; `README.md` / `README.ja.md` updated in lock-step (tool table, parameter-table row removed, troubleshooting entry); `TESTING.md` §4.1 step 2 reworded. ScriptVersion -> r11.31.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; no vendored Part A region touched. This removes a parameter, but per the project's reverse-engineering-driven status there are no downstream consumers to preserve.

### Add the Windows SDK Signing Tools (signtool.exe) acquisition machinery (`$Script:ScriptVersion` -> `update-wsi-2026.06.13-r11.30`, tag `signtool-acquisition`)

Adds the install-if-missing machinery for `signtool.exe` (Windows SDK Signing Tools) so signature-verification consumers can rely on signtool being present without assuming a pre-installed SDK — mirroring the 7-Zip (§B.19.4) and ADK/oscdimg (§B.22.13) tool-acquisition idioms already in the script. The machinery is defined here; the PCA2023 readiness classifier is wired to use it in a follow-up commit in this series.

- **`Resolve-SignToolExe`** locates signtool.exe (PATH first, then `Windows Kits\10\bin` under both Program Files roots, preferring the newest x64 build) and returns `$null` (does not throw) when absent. No integrity hash check: unlike `oscdimg.exe`, signtool.exe has no fixed reference SHA-256 (it varies per SDK build), so acquisition trust rests on the Microsoft fwlink plus presence verification.
- **`Install-WindowsSdkFallback`** downloads `winsdksetup.exe` from the pinned Microsoft fwlink (`$Script:SdkInstallerUrl` = linkid=2338977, SDK `10.0.26100.6584`) to `<WorkRoot>\cache\sdk\` and runs it with `/features OptionId.SigningTools /quiet /norestart` (Signing Tools feature only, never the full SDK), verifying by tool presence — the same defensive pattern as `Install-WindowsAdkFallback`.
- **Acquisition is automatic (no switch)**, matching the 7-Zip strategy.
- **Spec.** New SPEC §B.22.22 documents the acquisition machinery. No vendored Part A region is touched.
- **Scope.** `projects/powershell-update-windows-server-iso/` only; functions added outside all canonical markers; no Action, parameter, output, or data-schema change, so `README.md` / `README.ja.md` are unaffected at this step.

### Correct the disproven boot.wim/EFI_EX servicing premise + refresh the Make2023BootableMedia reference (docs/comments only; no `$Script:ScriptVersion` change)

A documentation/comment-only correction pass (no behavioural change, so the script version is unchanged). It removes a disproven spec premise and stale citations surfaced by the Secure-Boot investigation (real-environment DISM evidence + Microsoft primary sources + `signtool /all` measurement).

- **Disproven premise removed (SPEC §B.16.2 / §B.16.4).** The claim that "P08 surfaces the Microsoft-shipped EFI_EX staging assets out of install.wim's WinSxS into boot.wim" was disproven and was never implemented: the OS LCU does not service WinPE/boot.wim (Microsoft Learn "Add an Update to a Windows PE Image"; empirically `0x80070032` for the combined `.msu` and `0x8007371b` for the extracted `.cab`, missing WinPE `BootEnvironment-*-PXE.Resources` members). The proven facts replace it — the PCA2023 boot manager (`bootmgfw_EX.efi` = "Windows UEFI CA 2023") is LCU-delivered into the **serviced install.wim's** `\Windows\Boot\EFI_EX\`, and the conversion sources it from there — with the exact conversion path marked **under real-environment verification**. The §B.16.2 acquisition-path column is corrected the same way (it carried the same boot.wim-routing assumption).
- **Microsoft reference repinned (SPEC §B.16.3 / §B.17.1, `README.md` + `README.ja.md`, and the in-script citations).** `Make2023BootableMedia.ps1` "v1.4 (2026-03-13)" plus fixed line numbers (`L829-L941` / `L876-L884` / `L909-L911`) no longer uniquely identify the cited behaviour (upstream PR #361 changed the content while leaving the internal version string at "1.4"). The reference now pins the tag `v1.6.4-signed` / commit `bd7abe3` and cites the function `Copy-2023BootBins` instead of absolute line ranges.
- **In-code SSU-publication comment contradiction fixed.** The `Get-PatchSetFromReleaseInfoDiscovery` docstring said separate-model OSes "(e.g. Server 2016/2019)" still publish a standalone same-month SSU, contradicting the correct inline comment downstream (only Server 2016 does today; Server 2019's servicing-stack floor is met by the LCU-embedded stack). The docstring now matches the implemented discriminator and the ground truth.
- **Scope.** `projects/powershell-update-windows-server-iso/` only (SPEC Part B §B.16/§B.17 — no vendored Part A region touched — plus `.ps1` comments/docstrings outside canonical markers and the bilingual README pair). No Action, parameter, output, data-schema, or control-flow change.

### Localise DISM scratch for mount + dismount (`$Script:ScriptVersion` -> `update-wsi-2026.06.12-r11.29`, tag `dism-scratchdir-localisation`)

`Mount-WindowsImage` and `Dismount-WindowsImage` were invoked without `-ScratchDirectory`, so DISM fell back to its default scratch (typically under `%SystemRoot%\Temp`) — off the WorkRoot volume and outside the `-UseDefenderExclusions` path-exclusion set, which both weakened the exclusion benefit and split DISM scratch I/O across volumes. `Add-WindowsPackage`, `/Cleanup-Image`, and `/Export-Image` already pass the workspace-local `$Script:ScratchDir` (`<WorkRoot>\work\scratch`, introduced in r11.25); the mount and dismount paths were the two that still defaulted.

- **Change.** The mount and dismount argument builders now set `ScratchDirectory = $Script:ScratchDir` (guarded on non-empty, matching the existing call sites), so every DISM operation's scratch stays under the single Defender-excluded WorkRoot.
- **Scope.** `Invoke-WimMountSafe` / `Invoke-WimDismountSafe` only; no Action, parameter, output, or data-schema change, so `README.md` / `README.ja.md` are unaffected. Blast radius is the project script.

### Deterministic supersedence extraction (`$Script:ScriptVersion` -> `update-wsi-2026.06.12-r11.28`, tag `supersedence-determinism`)

`Get-SupersedenceFromCatalog` scraped the Catalog ScopedView `supersedesInfo` section with a non-greedy `...</div>` boundary that stopped at the first inner entry. Because the Catalog reorders that section's entries per request, the single captured KB varied run-to-run, so `PatchBaseline.NeutralPatches[].Supersedes` was not byte-reproducible across regenerations (the only non-deterministic field in an otherwise reproducible `/data` set). The full entry set is identical across requests; only its order changes.

- **Full-section capture.** Extraction now spans the whole `supersedesInfo` / `supersededbyInfo` section (bounded by the next `id="..."` panel), so the complete supersedence chain is read instead of just the first entry.
- **Deterministic parse.** New helper `ConvertFrom-CatalogSupersedenceSection` returns the chain as an ordinal-sorted, de-duplicated list plus a single `Latest` — the immediate predecessor: the entry with the highest `yyyy-MM` title prefix, ties broken on the highest KB number, falling back to the highest KB number when no entry carries a `yyyy-MM`.
- **Compact, meaningful persistence.** The config `Supersedes` field now persists only the immediate-predecessor KB (one deterministic value), keeping the baseline byte-reproducible and the field compact while making it more accurate than the previous arbitrary first-in-list value. The candidate-narrowing path is unaffected (it selects by title).
- **Test.** New `tests/supersedence_section_test.py` asserts order-independence (shuffled input -> identical output), the immediate-predecessor rule, the no-`yyyy-MM` fallback, and de-duplication. Offline suite 26/26.
- **Scope.** `Get-SupersedenceFromCatalog` and its two record-build call sites only; SPEC §B.12 documents the rule. No data-schema change (`Supersedes` stays a single-element list).

### .NET CU publication-gap carry-forward in release-info discovery (`$Script:ScriptVersion` -> `update-wsi-2026.06.12-r11.27`, tag `dotnet-cu-carryforward`)

`Get-PatchSetFromReleaseInfoDiscovery` selected the .NET Framework CU by an exact `PatchMonth` match. Microsoft does not publish a .NET CU every month, so on a publication-gap month (e.g. 2026-06) discovery emitted no `DotNet.Runtime` records at all and the generated baseline silently lost .NET servicing. The Dynamic Update path already tolerates gaps via its 36-month recency (SPEC §B.22.6); the .NET CU path did not.

- **Carry-forward.** When the requested month lists no .NET CU for an OS, discovery now carries forward the most-recent .NET CU month that is `<= PatchMonth`, that still falls inside the same 36-month window as the Dynamic Update lookback, and that actually lists a row for that OS (the choice is per-OS because .NET CU coverage varies by month). An exact-month hit is unchanged; only gap months fall back.
- **Provenance.** The carried record's `DiscoveryNote` records the source month (`... (carried forward from <yyyy-MM>; no <PatchMonth> .NET CU published)`) and a `Write-Step` line is logged, so a carried-forward selection is visible in the build log and in the baseline.
- **Cross-month LCU-priority dedup hardening.** The dedup set is now seeded from every release-info LCU `KbId` for the OS (any in-cache month), not just the requested month's LCU. This prevents a prior-month LCU that Microsoft lists under a .NET row (the Server 2016 sliced cumulative `KB5087537`) from being resurfaced as a spurious `DotNet.Runtime` record when a later month carries the prior month forward.
- **Docs / tests.** SPEC §B.22.5 extended with the publication-gap carry-forward rule (cross-referencing the §B.22.6 36-month window). `T10` (`release_info_resolver_test.py`) gains two scenarios: a basic Server 2019 gap-month carry-forward and a Server 2016 gap-month case that doubles as the cross-month dedup regression guard. Offline suite 25/25.
- **Scope.** Behavioural change to release-info discovery only; no Action, parameter, or data-schema change, so `README.md` / `README.ja.md` are unaffected. Blast radius is the project directory (script + SPEC + test fixture).

### Docs / comments: make stale SPEC section references fact-based and version-independent (no `$Script:ScriptVersion` bump)

The r09.0 SPEC rewrite repurposed §B.23 as "JSON Canonical Serialization" and migrated the architecture decisions to §B.22, but a number of in-code comments (and two runtime messages) still cited the old `B.23.x` subsections for non-canonical-JSON topics — release-info as the truth source, the three-prefix data layout, Catalog title tokens, the SSU / .NET combined-vs-separate handling, Dynamic Update cadence, the legacy `DotNet` type, the two-stage refresh, and empty-baseline seeding. Those numbers now mis-resolve into the JSON-canonical section or dangle.

- Replaced the stale `B.23.x` citations with version-independent wording (a plain "see SPEC.md" pointer or a direct statement of the fact), so the comments no longer depend on a specific SPEC section number that can drift on the next reorganisation.
- Corrected the misleading universal claim "most current monthly LCUs embed the SSU" to the accurate combined-vs-separate statement: combined-model OSes (Server 2022/2025) ship the SSU inside the monthly LCU, while the separate model (Server 2016/2019) publishes a standalone same-month SSU.
- Left the genuinely-canonical-JSON `SPEC Part B.23` references intact (that section legitimately is JSON Canonical Serialization) and did not touch any vendored / canonical region.
- Comment / message wording only: no behaviour change and no `$Script:ScriptVersion` bump. The behavioural separate-model SSU auto-discovery remains separate future work.

### CI: fix the STAGE 2 Windows checks on the Server 2025 runner and refresh action majors (no `$Script:ScriptVersion` bump)

The `windows-latest` GitHub-hosted runner moved from Windows Server 2022 to Server 2025. On that image, Windows PowerShell 5.1 does not have PSGallery pre-registered and `Register-PSRepository -Default` fails against the image's bundled NuGet provider (`NuGet.Commands.CommandException: Missing option value for: '-source'`), which left PSGallery unregistered and aborted the STAGE 2 module-install step (`Set-PSRepository ... No repository with the name 'PSGallery' was found`, exit 1).

- **STAGE 2 PSGallery bootstrap.** Register PSGallery explicitly (`Register-PSRepository -Name PSGallery -SourceLocation https://www.powershellgallery.com/api/v2 -PublishLocation .../package/ -InstallationPolicy Trusted`) with a PackageManagement-layer fallback (`Register-PackageSource -ProviderName PowerShellGet`); neither path goes through the failing `-Default` bootstrap. STAGE 1 (Ubuntu, pwsh 7) is unaffected by the image change and is left unchanged.
- **Action majors refreshed to current latest** across this project's four CI workflows (each verified against the action's GitHub releases): `actions/checkout` v5 -> v6, `actions/upload-artifact` v5 -> v7, `actions/cache` v4 -> v5. `actions/setup-python` (v6), `github/codeql-action` (v4), and `peter-evans/create-pull-request` (v8) are already current. Artifact uploads use per-run unique names and the cache uses a plain path/key, so the bumps are compatible with the current usage.
- CI-only: no script change and no `$Script:ScriptVersion` bump. The Server 2025 bootstrap is validated by the next CI run on the live runner — it cannot be reproduced on the Linux authoring host.

### Tests / harness reader: skip non-response output so the TestHarness session cannot desynchronise (no `$Script:ScriptVersion` bump)

Defence-in-depth companion to the TestHarness stdout fix below. `tests/common/ps_invoke.py` now reads until the JSON response envelope (a JSON object carrying an `ok` field), skipping any empty or non-envelope line instead of treating the first non-empty line as the response. A stray line on stdout (host / information-stream output from a function under test) is therefore discarded rather than mis-read as the response — which previously desynchronised the long-lived per-session `pwsh` process and surfaced as failures on later calls. On EOF without a response the skipped output is included in the raised error for diagnosis. Python test code only; no script change and no `$Script:ScriptVersion` bump.

### Tests / TestHarness: keep the `-Action TestHarness` stdout channel clean so the Python harness reads one JSON object per response (no `$Script:ScriptVersion` bump)

The Python behavioural harness (`tests/powershell_harness.py`, via `tests/common/ps_invoke.py`) drives `Update-WindowsServerIso.ps1 -Action TestHarness` over a single long-lived `pwsh` process and reads exactly one JSON object per line on stdout. Functions that route DISM access through `Invoke-DismCmdlet` (the r11.22 chokepoint) log via `Write-Host`; on PowerShell 7.x the information stream renders to stdout, so those log lines were interleaved ahead of the JSON response. Because the harness reuses one process per session, a stray line desynchronised the request/response pairing and surfaced as JSON-parse / parameter-binding failures on later calls (observed 6 pass / 4 fail under pwsh 7.6.2).

- The fix redirects the information stream away from the call inside the TestHarness request loop (`& $cmd @splat 6>$null`), so only the success-stream result is captured and exactly one JSON object is emitted per request.
- The canonical logging helpers (`_LogLine` / `Write-Step` and the other vendored log functions) are unchanged — this is confined to the consumer-owned TestHarness dispatch block.
- TestHarness-only: no production code path is touched and there is no `$Script:ScriptVersion` change. The offline behavioural gate is back to 10/10.

### Add an opt-in Windows Defender exclusion manager for the build (`-UseDefenderExclusions`, r11.26)

A controlled real-machine A/B probe (idx1, P01-P07, the only variable being the Defender exclusion) measured that excluding the work area and the DISM/CBS servicing processes from Defender real-time scanning cuts the LCU apply ~35% (22m56s -> 14m57s); the StartComponentCleanup is storage-bound (small-file synchronous-write latency, ~900-2,600 writes/s across three drives) and is NOT helped by the exclusion. This adds an opt-in `-UseDefenderExclusions` switch (default OFF, security-affecting) that manages those exclusions only for the duration of a run.

- **Scope.** One path exclusion -- the `WorkRoot` tree (covers mount, scratch, source install.wim and patches recursively) -- plus four process exclusions by file name: `dism.exe`, `DismHost.exe`, `TiWorker.exe`, `TrustedInstaller.exe` (file-name, not full path, because `TiWorker.exe` lives under a versioned WinSxS path).
- **Fail-closed.** Exclusions are applied ONLY when every prerequisite is positively confirmed: the four `*-MpPreference`/`Get-MpComputerStatus` commands exist, `WinDefend` is running, real-time protection is on, Tamper Protection is off, and `AMRunningMode` is `Normal`. Any unmet or unknown condition (e.g. an older Server SKU that does not report `AMRunningMode`) skips the feature entirely and the build continues without exclusions, printing the specific reason. The decision is a pure helper (`Get-DefenderExclusionDecision`).
- **Only-add-what's-absent + only-remove-what-we-added.** `Get-DefenderExclusionPlan` (pure) adds only exclusions not already present (case/trailing-slash-insensitive); what this run adds is recorded to `<WorkRoot>\state\defender-exclusions.json` and only those entries are removed on teardown -- never a pre-existing user exclusion.
- **Crash-safe.** Restoration runs in the script's top-level `finally`; additionally a startup self-heal removes orphaned exclusions recorded by a previous interrupted run. `-Action Cleanup` preserves the `<WorkRoot>\state` folder so that record survives a workspace teardown.
- New test **T26** (`defender_exclusion_plan_test.py`, 13 assertions) covers the three pure helpers (managed set, add-only-absent plan, fail-closed decision incl. `$null`/unknown inputs). The `Add-/Remove-MpPreference` / `Get-MpComputerStatus` wrappers are Windows-only (not exercised offline, same boundary as the DISM cmdlets).

`$Script:ScriptVersion` -> `update-wsi-2026.06.11-r11.26`; `$Script:ScriptTag` -> `defender-exclusion-optin`.

### P07: restore /ResetBase as the default, localise DISM scratch I/O under the work area (r11.25)

A real end-to-end run of r11.24 (with /ResetBase OFF) REGRESSED total time 4h10m -> 6h17m: P07 went 3h52m -> 5h58m. Log analysis pinned the cause to the cleanup, not the export. `/StartComponentCleanup` WITHOUT `/ResetBase` ran ~36 min/index for Core editions and ~72 min/index for Desktop editions (~3h36m total), versus ~88 min total WITH `/ResetBase` on the prior run. `/StartComponentCleanup`-alone preserves uninstall capability and therefore scavenges the component store granularly (many small WinSxS file operations), whereas `/ResetBase` resets the base in bulk (fewer, larger operations); on this heavily-agented host the granular path is hit far harder by per-file AV / change-tracking interception, and the cleanup time scaled ~2x with edition component count -- the interception signature. The default Export-Image /Compress:max pass, by contrast, took only ~20 seconds for all four indexes and delivered the size win (9.50 GB -> 6.04 GB install.wim, 36.4% smaller), confirming it as a near-free keeper.

- `/ResetBase` is ON by default again. A patched golden ISO exists to ship the latest updates already applied; uninstalling those updates is not a use case, so resetting the component-store base (updates non-removable) is the correct default -- and it is empirically faster on this host. The opt-in `-ResetBaseOnCleanup` switch is replaced by the opt-out `-SkipResetBaseOnCleanup` (keeps updates removable; omits `/ResetBase`); `$Script:ResetBaseOnCleanup` is now `-not $SkipResetBaseOnCleanup`. `Get-DismCleanupArgumentList` stays policy-neutral (`-IncludeResetBase` still gates the token); the script wiring sets the default.
- DISM scratch I/O is now localised under the work area. A new `$Script:ScratchDir` (`<WorkRoot>\work\scratch`, created at startup) is threaded into the heavy DISM operations: package application (`Add-WindowsPackage`) via `-ScratchDirectory`, and `/Cleanup-Image` and `/Export-Image` via a `/ScratchDir:<path>` token appended by `Get-DismCleanupArgumentList` / `Get-DismExportArgumentList` when a scratch path is supplied. Previously DISM used its implicit per-process scratch under `C:\`, invisible to a work-area-scoped exclusion; localising it keeps all DISM temp I/O under one directory (and keeps `C:` clean). This is the prerequisite for evaluating a workspace AV-exclusion as the root-cause fix for the interception above.
- The Export-Image /Compress:max pass is unchanged in policy (default ON, `-SkipExportCompress` opts out) and now also receives `/ScratchDir`.
- T24 / T25 each gained two assertions: `-ScratchDir` appends exactly one `/ScratchDir:<path>` token (no embedded space) and the token is omitted when no scratch path is supplied.

`$Script:ScriptVersion` -> `update-wsi-2026.06.11-r11.25`; `$Script:ScriptTag` -> `p07-resetbase-default-on-scratchdir`.

### P07 build-time optimisation: /ResetBase off by default, recover size with a single Export-Image /Compress:max pass (r11.24)

On a real end-to-end run P07 (PatchInstallWim) took 3h52m -- 93% of the 4h10m total. Per-index timing showed the two dominant costs were the LCU apply (~24-32 min/index, inherent to DISM offline servicing) and `/Cleanup-Image /StartComponentCleanup /ResetBase` (~17-27 min/index). `/ResetBase` rebuilds the component-store base and is the avoidable half.

- `/ResetBase` is now OFF by default. The per-image cleanup is `/Cleanup-Image /StartComponentCleanup` only, matching Microsoft's released-media practice. `-ResetBaseOnCleanup` restores the previous behaviour (smaller image, applied updates no longer removable) for operators who want it. `Get-DismCleanupArgumentList` gained a `-IncludeResetBase` switch; `Invoke-DismCleanup` passes `$Script:ResetBaseOnCleanup` through. This applies to install.wim, boot.wim and WinRE cleanup alike.
- Size is recovered by a new default Export-Image pass. After all install.wim indexes are serviced and dismounted, `Export-InstallWimCompressed` runs a single `dism.exe /Export-Image ... /Compress:max` over every index into a fresh WIM and replaces install.wim. This recompresses and single-instances files shared across the four editions -- typically recovering more than per-index `/ResetBase` did -- in one pass instead of four. ALL indexes are exported (no edition is dropped even when only a subset was serviced via `-OnlyInstallWimIndexes`), and the exported WIM is index-count-verified BEFORE the destructive swap; on any failure or count mismatch the original install.wim is left untouched. `-SkipExportCompress` opts out (faster build, larger install.wim). The argument vector is built by the new pure helper `Get-DismExportArgumentList` (interpolation, no `+`), guarding the same precedence trap.
- New offline regression tests: T24 (`dism_cleanup_args_test.py`) now asserts the default vector is three tokens with no `/ResetBase` and that `-IncludeResetBase` appends it as a fourth; T25 (`dism_export_args_test.py`) asserts the five-token `/Export-Image ... /Compress:max` vector. Both check that no token carries an embedded space (the collapse signature).
- Note: index selection (`-OnlyInstallWimIndexes`) already existed and scales P07 time roughly linearly with the number of serviced editions; operators who do not need all four editions can cut P07 time proportionally without code changes.

`$Script:ScriptVersion` -> `update-wsi-2026.06.11-r11.24`; `$Script:ScriptTag` -> `p07-resetbase-off-export-compress`.

### Fix DISM /Cleanup-Image exit 1639: build the cleanup argument vector without the comma/`+` precedence trap (r11.23)

The offline `dism.exe /Cleanup-Image /StartComponentCleanup /ResetBase` pass in `Invoke-DismCleanup` failed with exit code 1639 ("the command-line is missing a required servicing command") on a real end-to-end run. `dism.log` showed dism.exe received the whole argument string as a SINGLE quoted argument: `"/Image:D:\...\mount_install /Cleanup-Image /StartComponentCleanup /ResetBase"`. Root cause: the vector was built as `@('/Image:' + $MountPath, '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')`, and PowerShell binds the comma operator tighter than `+`, so the expression parsed as `'/Image:' + ($MountPath, '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')` -- the trailing array was stringified (space-joined) into the `/Image:` value, collapsing four tokens into one. dism.exe then saw a malformed `/Image:` value with no servicing command. `/ResetBase` was never the cause (the identical command typed by hand passes four discrete arguments and succeeds; dropping `/ResetBase` would not have fixed the collapse). The DISM CLI build-log line looked correct because it joins the argument array with spaces -- only `dism.log`, which quoted the entire string as one argument, exposed it.

Fix: construction moved into a new pure helper `Get-DismCleanupArgumentList -MountPath <path>` returning the vector as a `[string[]]` built with `"/Image:$MountPath"` (string interpolation, no `+` operator), keeping the first element intact and the vector at four discrete tokens. `Invoke-DismCleanup` now calls the helper. Because the helper is pure and returns a string array, it is unit-tested directly: new offline test `tests/dism_cleanup_args_test.py` (T24) asserts the vector is four tokens, the first is the clean `/Image:` target, the servicing tokens follow in order, and -- the collapse signature -- no token contains an embedded space. The test fails on the reintroduced collapse, guarding this bug class going forward.

`$Script:ScriptVersion` -> `update-wsi-2026.06.11-r11.23`; `$Script:ScriptTag` -> `fix-dism-cleanup-arg-vector`.

### DISM observability (cont.): route every DISM cmdlet through `Invoke-DismCmdlet`, reads included, with no cmdlet shadowing (r11.22)

Extends the r11.21 logging to *all* DISM operations -- reads as well as writes -- and consolidates the mechanism into two distinct-named chokepoints so it stays unambiguous as the script grows. A new helper `Invoke-DismCmdlet -CommandName <name> -Parameters @{ ... }` logs the cmdlet and its resolved parameters via `Write-DismInvocation`, then runs the real cmdlet by name with the parameters splatted in and returns its output unchanged. Every DISM cmdlet call site now routes through it: the reads `Get-WindowsImage`, `Get-WindowsPackage` and `Get-WindowsOptionalFeature` -- so an unreadable, corrupt or version-incompatible WIM is visible at the point of failure, not only write failures -- as well as `Mount-WindowsImage`, `Dismount-WindowsImage` and `Add-WindowsPackage`. The in-box cmdlets are deliberately NOT shadowed by same-named proxy functions: that breaks `Get-Command`, IntelliSense, module auto-loading and parameter-set fidelity and is an established PowerShell anti-pattern, so callers pass the cmdlet name explicitly to the distinct-named helper. The per-wrapper `Write-DismInvocation` calls added in r11.21 (in `Invoke-WimMountSafe`, `Invoke-WimDismountSafe`, `Add-WindowsPackageWithRetry`) are removed as now-redundant; DISM logging is uniform through `Invoke-DismCli` (CLI) and `Invoke-DismCmdlet` (cmdlets). No production behaviour changes: parameters, switches, error-action and pipeline output are identical. `$Script:ScriptVersion` -> `update-wsi-2026.06.10-r11.22`; `$Script:ScriptTag` -> `route-all-dism-through-helpers`.

### DISM observability: route every dism.exe call through `Invoke-DismCli` and log all mutating DISM operations (r11.21)

The ISO build leans heavily on DISM, the least predictable and hardest-to-diagnose dependency in the pipeline: a malformed argument can fail at runtime with an opaque exit code (for example `/Cleanup-Image` exiting `1639`) and leave nothing in the build log to show what was actually passed. Two additions make every DISM operation's runtime parameters visible at the point of failure, comprehensively rather than per-call. (1) A new `Invoke-DismCli` function is the single chokepoint for every `dism.exe` command-line invocation: it logs the fully-resolved command line (every argument) and the resulting exit code, then returns the code so the caller decides how to treat a failure. Both existing CLI sites -- `/Cleanup-Image` in `Invoke-DismCleanup` and the synthetic `/Capture-Image` -- now route through it. (2) A new `Write-DismInvocation` helper emits a uniform `operation + parameters` log block; it is called from `Invoke-DismCli` and from the three mutating-cmdlet wrappers (`Invoke-WimMountSafe`/Mount-WindowsImage, `Invoke-WimDismountSafe`/Dismount-WindowsImage, `Add-WindowsPackageWithRetry`/Add-WindowsPackage), so the mount path, image path, index, package path and discard flag of every image-modifying DISM operation appear in the build log before the operation runs. Production behaviour is unchanged -- the command construction, switches and control flow are identical and only logging is added (`dism.exe` stdout is routed to the host so it stays on the console without polluting `Invoke-DismCli`'s return value). `$Script:ScriptVersion` -> `update-wsi-2026.06.10-r11.21`; `$Script:ScriptTag` -> `trace-all-dism-invocations`.

### Docs: simplify the README Quick Start command examples for end users (no code change)

The Quick Start "Template" and "Worked example" blocks (README.md + README.ja.md) drop the explicit `-IsoPath`/`-PatchDirectory` placeholders -- an end-user machine has neither by default, and with the patch baseline shipped in `data/` the script resolves the source ISO download URL from the OS profile and takes its patch set from the distributed baseline -- and now pass `-UseBaselineOnly` by default so a run on the shipped data never depends on live Catalog / release-info publication timing. The `-IsoPath`/`-PatchDirectory`/`-IsoUrl` parameters remain documented in the parameter reference for advanced/offline use.
### Docs: add the monthly baseline regeneration / verification procedure to TESTING.md §8 (no code change)

Records the agent/LLM verification gates (G1-G5) for a monthly `/data` rebuild, distilled from the 2026-05 and 2026-06 real runs. The critical gate **G2 (discovery-source currency)**: the `wsusscn2.cab` and the Update Catalog lead the Microsoft release-health page by a day or more after Patch Tuesday, so a regen attempted before release-info publishes the target month yields a wrong-month or empty patch set (A01 logs `Discovery returned zero records`); such a regen must be deferred, not committed. Logs the 2026-06 deferral: the 2026-06 cab was valid and A04 regenerated Layer 2 cleanly (~5 min), but on 2026-06-10 release-info still listed 2026-05, so the 2026-06 Layer 1 regen was deferred.
### Docs: propagate the standalone-SSU + pinned-month behaviour across SPEC, README, and the windows-servicing research note (no code change)

Documentation-only follow-up to the r11.20 resolver/baseline change below; aligns the prose docs with the shipped behaviour.

- **SPEC §G.2**: the KB5087537 SSU-prerequisite "config-side pending action" is marked resolved (the standalone Server 2016 SSU is now auto-discovered, not hand-patched).
- **SPEC §B.22.11**: `-PatchMonth` is clarified as read-only in the build path but month-pinning in `RefreshAllBaselines` (where it also drives `PatchTuesdayOfBaseline` via `Get-PatchTuesdayForMonth`).
- **SPEC §B.22.5**: documents the same-month Catalog title-search SSU discovery and its role as the SSU-separate-vs-combined discriminator.
- **SPEC schema example**: `PatchTuesdayOfBaseline` corrected to `2026-05-12` (the actual May 2026 Patch Tuesday, matching the regenerated baseline).
- **README.md / README.ja.md**: the `0x800f0823` troubleshooting row notes the same-month SSU is now auto-discovered (manual `NeutralPatches[]` add is the fallback).
- **`documents/research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md`**: §5.3 records the validated same-month "Servicing Stack Update <OS>" Catalog title-search as the SSU-KB discovery method, with the empirical 2026-05 result (Server 2016 -> KB5088064; Server 2019 / 2022 / 2025 -> none).
### Resolver: discover the standalone same-month SSU and regenerate the 2026-05 baseline (`$Script:ScriptVersion` `update-wsi-2026.06.09-r11.19` -> `update-wsi-2026.06.10-r11.20`)

Completes the "config-side pending action" deferred in the docs entry below: implements separate-model SSU resolution so the Server 2016 servicing-stack update is discovered by the generator instead of being hand-patched into `data/config-Server2016.json`.

- **`Resolve-PatchSetFromReleaseInfo`**: after emitting the per-UpdateId records, search the Microsoft Update Catalog for a same-month "Servicing Stack Update" of the OS. When one is found (Server 2016 -> KB5088064, UpdateId `d0f1761f-c762-4764-8443-8c567f6929a2`) it is emitted as a `Type=SSU` NeutralPatch and the matching LCU is flipped to `IsCombined=false`; when none is found (Server 2019/2022/2025) the LCU stays `IsCombined=true`. The same-month + OS-narrowed title search is itself the discriminator, so the step needs no Layer 2 / `-DataDir` input and works on the `RefreshAllBaselines` (A01) call path.
- **Stale "every monthly LCU embeds the SSU" docstrings corrected** (old decision B-1) in the discovery and resolver function headers to match the new behaviour.
- **`RefreshAllBaselines` (A01)**: when `-PatchMonth` pins a specific month, derive `PatchTuesdayOfBaseline` from that month's Patch Tuesday (via `Get-PatchTuesdayForMonth`) instead of the wall-clock latest one, so generating a specific month's baseline is correct and byte-reproducible (a 2026-05 baseline generated on the 2026-06 Patch Tuesday is stamped `2026-05-12`, not `2026-06-09`).
- **T23** (`config_required_ssu_downloadurl_test.py`) extended from the DownloadUrl-only guard to a three-part required-SSU consistency contract (SSU DownloadUrl present; an `IsCombined=false` LCU is paired with an SSU; an SSU implies an `IsCombined=false` LCU); now 19 assertions.
- **`data/config-Server{2016,2019,2022,2025}.json`**: regenerated for the finalised 2026-05 Patch Tuesday baseline with the fixed generator. The Server 2016 SSU is now generator-produced (the manual `_DependencyVerified*` / `_Notes` markers are retired); supersedence is refreshed to the current Catalog; `PatchTuesdayOfBaseline` is `2026-05-12`. Patch identities (KB / UpdateId / DownloadUrl / IsCombined) are unchanged from the previous baseline.
### Docs: repoint stale SPEC B.23.x cross-references in code comments to the r09.0 B.22 decision records (no script revision)

The r09.0 SPEC rewrite moved the old B.23 narrative's architecture decisions into the B.22 decision-record section (see SPEC §G.3 deprecation note: the 24-subsection B.23 narrative was superseded by §B.22), but several `Update-WindowsServerIso.ps1` comments still cited the pre-rewrite B.23.x section numbers, which now point at the unrelated "JSON Canonical Serialization" section. This corrects the unambiguous ones - **comment-only; no `$Script:ScriptVersion` bump, no behaviour change** (verified: CRLF/BOM preserved, restamp IN SYNC, psa 0/0/0):

- raw-/cache- prefix convention: `B.23.3` -> `B.22.3` ("Data directory: flat with 3-prefix naming").
- .NET CU multiplicity: `B.23.5` -> `B.22.5` ("SSU separation and .NET CU multiplicity").
- NeutralPatches storage: `B.23.5` / `B.23.8` -> `B.22.5` / `B.22.8` ("PatchBaseline.NeutralPatches[].Type").

Deliberately left out of this change:
- the combined-LCU / "every current monthly LCU embeds the SSU" comments (old decision B-1): their *claim*, not just the section number, is stale for the SSU-separate OSes (Server 2016/2019), and is corrected together with the resolver behaviour in the separate-model SSU resolution work (tracked as SPEC §G.2's "config-side pending action" follow-up).
- the LCU-priority .NET dedup references (old B-3): no single current B.22 home; left untouched pending a dedicated doc pass.
- the `docs/history/` references throughout SPEC/README: these are intentional pointers to the out-of-repo investigation-report tree (maintained outside this checkout, like the maintenance handoff), not dangling links.

### Data / tests: resolve the Server 2016 SSU (KB5088064) DownloadUrl + fix the T23 guard to check the real config path (no script revision)

Fills the empty `DownloadUrl` on the Server 2016 servicing-stack update (SSU, KB5088064) in `data/config-Server2016.json` so the SSU can be staged ahead of its dependent LCU - the missing input behind the on-host 0x800f0823. The URL was resolved from the Microsoft Update Catalog (UpdateId `d0f1761f-c762-4764-8443-8c567f6929a2`; verified live: HTTP 200, 12,761,169 bytes) and stored in the same baseline shape as the LCU/.NET entries (`DownloadUrl` + `FileName` set; `SizeBytes` / `Sha256` left at `0` / `""` for the real-machine download+verify step to populate, exactly as the LCU/.NET entries currently sit). **No `$Script:ScriptVersion` bump.**

Also fixes a correctness bug in the T23 guard (added earlier this Unreleased cycle): it read a top-level `NeutralPatches` key, but the real schema nests them under `PatchBaseline.NeutralPatches`, so it had been passing vacuously on the real configs. T23 now reads the real path, the bad-config fixture mirrors it, and two assertions lock in the Server 2016 SSU resolution. T23 is now 13 assertions.

- `data/config-Server2016.json`: SSU KB5088064 `DownloadUrl` + `FileName` resolved from the catalog.
- `tests/config_required_ssu_downloadurl_test.py`: read `PatchBaseline.NeutralPatches`; add assertions 08/09 (Server 2016 SSU present + resolved).
- `tests/fixtures/config-guard/bad-config-ssu-empty-url.json`: nested under `PatchBaseline` to mirror the real schema.
- `TESTING.md`: T23 assertion count -> 13.

Note: this SSU URL was hand-resolved as a stop-gap. The root cause - A01 `RefreshAllBaselines` resolves the LCU/.NET catalog URLs but not the SSU's - is addressed separately so future baseline refreshes fill it automatically.

### Tests / fixture-builder: make T12 fixture regeneration byte-identical + guard it against drift (no script revision)

`tests/common/servicing_dependency_fixture_builder.py`'s `build_expected_output()` had drifted behind the committed `tests/fixtures/servicing-dependency/expected-output.json`: the function still emitted the old `scope.now` key (committed: `scope.evaluatedAt`) and omitted `stats.eosEsuBundlesExcluded` / `stats.eosEsuFamiliesExcluded` and the per-update `kbIds` field. Running the documented regeneration command therefore corrupted the committed T12 fixture. **No `$Script:ScriptVersion` bump** - test/tooling only; the committed `expected-output.json` is byte-unchanged.

- `tests/common/servicing_dependency_fixture_builder.py`: realigned `build_expected_output()` with the committed parser output (`scope.now` -> `scope.evaluatedAt`; add `stats.eosEsuBundlesExcluded` + `stats.eosEsuFamiliesExcluded`; add `kbIds: []` to each in-scope bundle). `python3 -m tests.common.servicing_dependency_fixture_builder --out-dir tests/fixtures/servicing-dependency` now regenerates `package.xml`, `expected-output.json`, and `ssu-prereq/package.xml` byte-identically.
- `tests/servicing_dependency_parser_test.py` (T12): added a freshness guard (`00a` / `00b`) asserting the committed `package.xml` and `expected-output.json` match `build_package_xml()` / `build_expected_output()`, so the builder can no longer silently drift (mirrors the T21 guard). T12 is now 25 assertions.
- `TESTING.md`: T12 assertion count references updated to 25.

### Tests - offline reproduction + guards for the Server 2016 0x800f0823 SSU-prerequisite failure (no script revision)

Adds three offline tests that reproduce and guard the real-machine Server 2016 "LCU applied without its prerequisite SSU" failure (`CBS_E_NEW_SERVICING_STACK_REQUIRED`, 0x800f0823) entirely on Linux, ahead of the heavier Windows scenario evaluation. **No `$Script:ScriptVersion` bump** - `Update-WindowsServerIso.ps1` is unchanged; this is test/fixture/doc-only.

- **T21** (`tests/servicing_dependency_ssu_prereq_pipeline_test.py`, 20 assertions): builds a Server 2016 SSU -> LCU prerequisite `package.xml`, runs it through the real Stage 3/4 parser (`ConvertFrom-OfflineSyncPackage`, `New-ServicingDependencyDatabase`) and the servicing-stack populate step (`Update-ServicingStackFromMeta`, CBS leaf `leaf-2016-separate.xml` -> requiredSs `10.0.14393.7692`, `separate` model), then asserts `Test-PatchServicingReadinessFromGraph` predicts `SsTooOld` / `Fail` when the provided servicing stack predates the SSU, and `Pass` when it does not. Includes a freshness guard that the committed fixture matches `build_ssu_prereq_package_xml()`.
- **T22** (`tests/servicing_dependency_ssu_prereq_readiness_test.py`, 15 assertions): a fast, pipeline-free readiness-verdict unit over a hand-authored Layer 2 fixture, exercising the SS-compare boundary (RTM / one-below / exact / newer).
- **T23** (`tests/config_required_ssu_downloadurl_test.py`, 11 assertions): a static config-contract guard that no `NeutralPatches` entry of Type `SSU` ships with an empty `DownloadUrl` (the config data defect behind the on-host failure); checks the bad-config fixture and every committed `data/config-Server*.json`.

- `tests/common/servicing_dependency_fixture_builder.py`: added `build_ssu_prereq_package_xml()` and a `ssu-prereq/package.xml` emission to `main()`; the existing T12 fixture (`package.xml` + `expected-output.json`) is byte-unchanged.
- New fixtures: `tests/fixtures/servicing-dependency/ssu-prereq/package.xml`, `tests/fixtures/servicing-dependency/ssu-prereq-readiness-database.json`, `tests/fixtures/config-guard/bad-config-ssu-empty-url.json`.
- `TESTING.md`, `tests/README.md`: registered the new tests and fixtures.

### CI / build-infrastructure: complete the scripts -> projects migration for this project's workflows (no script revision)

The `scripts/powershell/update-windows-server-iso/` -> `projects/powershell-update-windows-server-iso/` migration (commit `7566d22c`, "migrate to gate-managed vendored Part A") moved the project tree but left this project's four CI workflows pointing at the old path, which broke Stage 1's `[Format]` (FileNotFoundError) and the psa.py / PSScriptAnalyzer SARIF-upload steps (path does not exist). This change completes the migration for the workflows and the in-project references that name them. **No `$Script:ScriptVersion` bump** — script logic is unchanged; the only `.ps1` edit is the stale `Location` help-comment path.

- `.github/workflows/`: renamed the four `scripts__powershell__update-windows-server-iso__*.yml` to `projects__powershell-update-windows-server-iso__*.yml` (path-encoded filenames per the dotfile convention). Repointed every in-file path (project directory, `paths:` trigger filters, `working-directory`, SARIF/artifact paths, header comments, and the `name:` field), and corrected the psa.py invocation to `../../quality-tools/powershell-static-analyzer/psa.py` (psa.py now lives under `quality-tools/`; the old `scripts/python/powershell-static-analyzer/` copy is being removed).
- README.md / README.ja.md: CI badge URLs repointed to the renamed workflow files (bilingual lock-step preserved).
- TESTING.md: the four workflow-file references in the CI section renamed to match.
- schema/config.schema.json, schema/servicing-dependency-database.schema.json: `$id` path segment updated to the new location (opaque identifier; nothing `$ref`s it, and the schema gates resolve local `#/definitions` only).
- tests/common/__init__.py, Update-WindowsServerIso.ps1: stale `scripts/...` path strings in a docstring / help-comment corrected.

Note: renaming the workflow files changes their GitHub workflow identity (run history detaches; required-check names change). Any branch-protection rule that requires these checks by the old file name must be updated in repository settings after this lands.

### r11.19 - Remove live WUA offline scan; P06 becomes a /data-first servicing-readiness gate (blocking)

A behavioural revision that retires P06's live Windows Update Agent (WUA) offline scan and repurposes P06 into a single, default-ON, blocking servicing-readiness gate against the pre-generated wsusscn2 Layer 2 database (`data/servicing-dependency-database.json`). `$Script:ScriptVersion` `r11.18` -> `r11.19`; `$Script:ScriptTag` becomes `remove-live-wua-scan-data-first-servicing-gate`. **Breaking change** (pre-1.0; no real consumers yet): `-IgnorePatchValidation` and `-EnableDependencyCheck` are removed.

**Why.** The former P06 Stage 1 ran a live WUA COM offline scan that evaluates applicability against the *local host's* OS image, not the mounted target WIM. It was therefore host-relative and returned false negatives on cross-OS-family builds (a Server 2025 host building a Server 2016 image scanned the host and reported 0 applicable updates), and it crashed before that point by comparing against the never-populated `PatchBaseline.Patches`. The pre-verified baseline (`NeutralPatches[]`, dependency-verified monthly) plus the Layer 2 database already provide the dependency answer, so the live scan was redundant as well as incorrect.

**Removed.**
- Functions `Invoke-WuaOfflineScan`, `Compare-PatchSetVsWuaScan`, and `Export-PatchValidationReport` (all P06-Stage-1-only).
- Parameters `-IgnorePatchValidation` (P06-Stage-1-only) and `-EnableDependencyCheck` (the servicing-readiness check is now always on). `-OfflineSyncPackagePath` is kept (shared with `RefreshDependencyDatabase`).
- The `<WorkRoot>/diag/<timestamp>/` patch-validation report set (`validation_summary.json`, `validation_detail.csv`, `wsusscn2_scan_raw.json`, `dependency_graph.json`).

**P06 now (`ValidatePatchServicing`; `PhaseRegistry` `Name`/`Func` renamed).** Skips only under `-UseBaselineOnly` or `-SyntheticTestMode`. Validates `$Script:ResolvedPatches` against the Layer 2 database via `Test-PatchServicingReadinessFromGraph` and: blocks on `OverallStatus` `Fail` (`SsTooOld` predicts `0x800f0823`, or `NotInDatabase`); warns on `Superseded`; passes otherwise; **blocks** when Layer 2 is absent/unreadable (run `-Action RefreshDependencyDatabase`, or pass `-UseBaselineOnly`). The non-Windows skip was removed (the gate reads JSON and is cross-platform).

**Docs.** SPEC §B.19.12 rewritten; the phase table, skip table, data-source table, and §B.19.14.5 updated; README.md / README.ja.md phase + parameter tables and the P06 narrative updated (bilingual lock-step preserved, 16/12); TESTING.md status table and the §4.x baseline examples no longer reference `-EnableDependencyCheck`.

**Tests.** Added `removed_live_wua_guard_test.py` (T20, offline static guard, 21 assertions): the three removed functions and two removed parameters stay absent, the old `Invoke-PlanPhase06_ValidatePatchSet` name is gone, and P06's new gate stays wired and blocking (calls `Test-PatchServicingReadinessFromGraph`, keeps both `throw` paths). The verdict -> block mapping (block-on-absence, block-on-`Fail`, warn-on-`Superseded`, pass) is already exercised by T16 (`servicing_dependency_readiness_verdict_test.py`).

### r11.18 - Documentation/comment realignment: Action → Phase map + ForcePca2023OnServer2025 comment

A documentation/comment-quality revision that aligns the Markdown and the in-script comment-based help with the implemented code; no runtime logic changes. `$Script:ScriptVersion` `r11.17` -> `r11.18`, `$Script:ScriptTag` becomes `docs-realign-action-phase-map-and-pca2023-comment`. The shared epoch (`dataContractVersion`) stays `1`.

**Action → Phase map corrected (README.md / README.ja.md / SPEC.md §B.6.1; bilingual lock-step preserved, 16/12).** The Standard pipeline Actions table listed phase sets that predate the current staged-pipeline design. `Get-PhaseListByAction` (script L15080) returns, for a default (non-synthetic) run:

- `Prepare`: `P01-P05` -> **`P01-P06`** (the `standardPrepare` set includes P06 ValidatePatchSet; still no patching and no DISM mount).
- `Build`: `P01-P02 + P04-P10` -> **`P07-P10`** (Build runs only the build phases; it presumes a prior Prepare staged the workspace and does not re-run setup in-line).
- `Verify`: `P01-P02 + P11-P13` -> **`P11-P13`** (Verify runs only the verify phases).
- Removed the SPEC's misleading `or runs it in-line` clause from the Build row (setup is not re-run in-line).

**`-ForcePca2023OnServer2025` parameter comment corrected (script L316-L321).** The comment described the switch as gating `P12 VerifyPca2023Readiness`, but the switch actually governs `P10 ConvertPca2023BootManager`: the Server-2025 default-skip gate lives inside P10 (`if ($osKey -eq 'Server2025' -and -not $Script:ForcePca2023OnServer2025)`, script L13120; advisory NOTE at L11022), and it takes effect only together with the opt-in `-EnablePca2023BootManager`. P12 always runs (the SPEC phase-skip list `P12: none (always runs)` and the README `P12 ... Always runs` row are both correct). The README parameter row (L420, already `Override the Server 2025 default-skip for P10`) was already correct and is unchanged.

**Not touched.** No phase logic, parameter contract, or output format changed. All edits are outside canonical regions: the 58 vendored canon code-regions and the 14 vendored Part A doc-regions are unchanged. `TESTING.md` is unaffected (no test or phase-skip claim changed).

### r11.17 - Documentation realignment: SPEC §B.19 rebuild, README/TESTING ground-truth pass

A documentation-quality revision that realigns the in-project Markdown with the implemented code. No runtime logic changes; `$Script:ScriptVersion` `r11.16` -> `r11.17`, `$Script:ScriptTag` becomes `docs-realign-spec-b19-rebuild`. The shared epoch (`dataContractVersion`) stays `1`.

**SPEC.md — §B.19 zero-base rebuild.** §B.19 (Servicing Dependency Database) was reconstructed from the code ground-truth and the repository governance, replacing the previous 77-subsection text (which had accreted pre-implementation drafts, milestone names, and superseded designs) with a 14-section structure that describes only the current specification plus genuinely future work:

- Removed stale / superseded content: the retired `Test-PatchDependencyClosureFromGraph` name and its KB-closure verdict shape (`Requires` / `MissingFromSet`); phantom parameters `-OfflineCabPath` (real: `-OfflineSyncPackagePath`), `-SkipDependencyCheck` opt-out (real: opt-in `-EnableDependencyCheck`), and `-DisablePca2023BootManager` (real: opt-in `-EnablePca2023BootManager`); the `Packages` / `RevisionIndex` / PascalCase Layer 2 draft (real: `_meta` + `updates`, camelCase); PoC milestone names (Phase 2b1, M1 part 5b, r09.0 Step 2b3); cost/benefit and rollout-step history (now CHANGELOG's / out of scope).
- Added / clarified as current specification: a **Data-processing strategy** section (cab/large-XML handling — 7-Zip-only with the `expand.exe` rationale, two-step targeted extraction, streaming `XmlReader` with the +536 MB DOM-vs-<50 MB streaming budget, encoding and canonical-output integrity); a **testability-driven two-language architecture** rationale (PowerShell body for the Windows-only DISM/Hyper-V targets, pure logic separated from I/O so Python can verify it offline, noted as a candidate for promotion to a shared convention in a future revision); the five-verdict **data-contract** model (`Current` / `Stale` / `Refuse` / `Foreign` / `Unknown`) and the validation-gate inventory (Layer 2 schema, scope-invariants, canonical-format).
- Corrected a diagnostic-output description: the P06 Stage 1 missing-patch fail path does write `validation_summary.json`, `validation_detail.csv`, `wsusscn2_scan_raw.json`, and `dependency_graph.json` under `<WorkRoot>/diag/<timestamp>/` (`Export-PatchValidationReport`); these are real, not phantom.
- Fixed §B.19-external references throughout SPEC (function inventory, B.6.3 A04, phase-skip list) and renumbered all cross-references to the new 14-section layout.

**README.md / README.ja.md (bilingual lock-step preserved, 16/12).**

- Action count `thirteen` -> `fourteen` (en; ja already correct).
- Removed the `r09.0 progress` section (history belongs in this CHANGELOG; future plans belong in SPEC).
- P06 Stage 2 corrected to opt-in advisory (`-EnableDependencyCheck`): logs verdicts, never blocks; the `ABORT` / "planned" / "dependency closure" wording was removed.
- Diagnostic section reframed around troubleshooting files an operator actually inspects (`-LogFile` transcript, `<WorkRoot>/logs/debugtrace.jsonl`, the Stage 1 `diag/<timestamp>/` set).
- Parameters section expanded from "selected" to **all 35 parameters** in a categorised table (category / default / ValidateSet / purpose) with a `Get-Help -Full` pointer.
- Quick start rewritten as a placeholder template plus a worked Server 2016 / Server 2025 example, using per-OS `-WorkRoot`, an auto-timestamped `-LogFile` via `Get-Date`, and the PCA2023 switch difference between the two OSes.
- Self-verification list extended from T1–T13 to **T1–T19 plus the gates**.

**TESTING.md.**

- §0 status, §4, and §5 realigned: P06 Stage 2 shown as opt-in advisory; milestone names simplified; SPEC section references renumbered.
- New **§4.3 Real-machine verification baseline** combining the conventions the operator-pending findings made necessary (per-OS `-WorkRoot`, auto-timestamped `-LogFile`, `-EnableDependencyCheck`, `-Execute`), covering the Server 2016 `0x800f0823` servicing-stack predictor and the P05 mojibake fresh-`-WorkRoot` workaround.
- §5 extended to the full T1–T19 inventory plus a servicing-dependency suite (T12–T19) summary.

**tests/README.md.** SPEC section references renumbered to the rebuilt §B.19; the scope-invariants gate description updated to reflect that the PowerShell deny-list filter is implemented and matches the `classify_scope` reference (no longer a future "later session").

### r11.16 - Self-verification test-file rename to servicing_dependency_* (Batch 3)

Completes the `wsusscn2` → `servicing_dependency` rename programme by renaming the output-verification test files themselves, which r11.15 deliberately left at their `wsusscn2_*` names. The renamed suite verifies the generation and quality of the `servicing-dependency-database.json` output artifact, so the filenames now match the artifact they gate (and the `tests/fixtures/servicing-dependency/` they read). `$Script:ScriptVersion` `r11.15` -> `r11.16`; `$Script:ScriptTag` becomes `servicing-dependency-test-file-rename`. No code path, no data, no schema, and no fixture content changes; the shared epoch (`dataContractVersion`) stays `1`.

Test-file renames (old -> new), 10 gated suites:

- `tests/wsusscn2_parser_test.py` -> `tests/servicing_dependency_parser_test.py` (T12)
- `tests/wsusscn2_layer1_test.py` -> `tests/servicing_dependency_layer1_test.py` (T13)
- `tests/wsusscn2_deny_list_test.py` -> `tests/servicing_dependency_deny_list_test.py` (T14)
- `tests/wsusscn2_servicing_stack_test.py` -> `tests/servicing_dependency_servicing_stack_test.py` (T15)
- `tests/wsusscn2_readiness_verdict_test.py` -> `tests/servicing_dependency_readiness_verdict_test.py` (T16)
- `tests/wsusscn2_recency_fallback_test.py` -> `tests/servicing_dependency_recency_fallback_test.py` (T17)
- `tests/wsusscn2_servicing_stack_populate_test.py` -> `tests/servicing_dependency_servicing_stack_populate_test.py` (T18)
- `tests/wsusscn2_data_contract_test.py` -> `tests/servicing_dependency_data_contract_test.py` (T19)
- `tests/wsusscn2_scope_invariants_test.py` -> `tests/servicing_dependency_scope_invariants_test.py` (scope-invariants gate)
- `tests/wsusscn2_layer2_schema_test.py` -> `tests/servicing_dependency_layer2_schema_test.py` (Layer 2 schema gate)

Helper rename (1):

- `tests/common/wsusscn2_fixture_builder.py` -> `tests/common/servicing_dependency_fixture_builder.py` (generates the T12 fixture under `tests/fixtures/servicing-dependency/`). Its module path `python3 -m tests.common.servicing_dependency_fixture_builder` is updated in SPEC §B.19 and the helper's own usage line; the reference to it in `tests/common/wsusscn2_analyzer.py`'s docstring is updated too.

Deliberately NOT renamed (input-cab artifacts, by agreement; same axis as retaining the literal `wsusscn2.cab`, the runtime `cache/wsusscn2/` directory, and the `wsusscn2 cab/Master XML/parser pipeline` concept prose):

- `tests/wsusscn2_probe.py` (T5) — a freshness probe whose subject is the input `wsusscn2.cab` itself, not the output database.
- `tests/common/wsusscn2_analyzer.py` — a `wsusscn2.cab` schema-discovery helper for the Phase 2b1 investigation; operates on the input cab.

Reference sites updated to the new filenames: the T-suite tables and Quick start in `tests/README.md`, the test inventory in SPEC §C and the per-section gate references in SPEC Part B, the `TESTING.md` §0 status table and run commands, the bilingual `README.md` / `README.ja.md` self-verification sections (lock-step preserved), and the single `tests/servicing_dependency_parser_test.py` mention in the `Update-WindowsServerIso.ps1 -Action TestHarness` comment. The `T-numbering` and per-suite assertion counts are unchanged. Concept prose that names the Microsoft artifact ("wsusscn2 parser pipeline") is retained.

Verification: `psa.py` 0/0/0; `pwsh -ParseFile` 0 errors; all 15 gated offline tests green under the new filenames (including `servicing_dependency_layer2_schema_test.py` resolving its `import config_schema_test`); README en/ja lock-step `## 16 / ### 11` preserved; `.ps1` BOM + CRLF preserved (CR == LF == CRLF == 15456). No residual old test-file stems outside this CHANGELOG's history; preserved `wsusscn2_probe` / `wsusscn2_analyzer` / `wsusscn2.cab` references intact.

### r11.15 - WsusScn / wsusscn2 derived-artifact rename (Batch 2; config field + data/schema/fixture files)

Completes the rename that r11.14 deliberately deferred: the derived artifacts that r11.14 left untouched are now brought onto the `OfflineSync*` (input layer) / `ServicingDependency*` (output layer) naming. r11.14 renamed only pure code identifiers; r11.15 renames the config field, the committed data/schema filenames, and the test-fixtures directory. `$Script:ScriptVersion` `r11.14` -> `r11.15`; `$Script:ScriptTag` becomes `servicing-dependency-artifact-rename`.

The shared epoch (`dataContractVersion`) **stays `1`**, by deliberate decision. The config field rename is an atomic relabel applied to the script, the schema, and all four committed `config-Server*.json` in this single commit: no key is added, removed, retyped, or re-nested — only the spelling of one key changes, with identical value and value-semantics. `Test-DataContractConsistency` (the contract's only consumer) compares `_meta.dataContractVersion`; since script and data ship together and the script is not yet used end-to-end, no externally-generated artifact carrying the pre-rename spelling exists for a bumped script to refuse. Bumping would force a no-op `_meta` re-stamp of five files for zero behavioural change, so it is omitted. Rationale recorded in SPEC §B.19.10 (epoch bumps are reserved for add/remove/retype/re-nest changes an existing consumer could mis-read). `data/servicing-dependency-database.json` is therefore NOT regenerated; the file is renamed with byte-identical content (its `_meta` provenance from the r11.11 generation is preserved as honest history).

Config field rename (old -> new):

- `PatchBaseline.WsusScnCab` -> `PatchBaseline.OfflineSyncPackage` (input-layer concept; the field holds `$OfflineSyncPackageInfo`). Touched in `Update-WindowsServerIso.ps1` (8 references), `schema/config.schema.json` (property + `$ref` + definition), all four `data/config-Server*.json` (key, re-emitted canonical), and SPEC §B.4.

File / directory renames (old -> new):

- `data/wsusscn2-database.json` -> `data/servicing-dependency-database.json` (output-layer Layer 2 database, generated by `New-ServicingDependencyDatabase`)
- `schema/wsusscn2-database.schema.json` -> `schema/servicing-dependency-database.schema.json` (its `$id` self-URL and the `data/...` path in its `description` updated to match)
- `tests/fixtures/wsusscn2/` -> `tests/fixtures/servicing-dependency/` (all contents preserved: `cbs/`, `package.xml`, `deny-list-package.xml`, `expected-output.json`, `readiness-database.json`, `recency-fallback-database.json`)

Probe token rename (old -> new):

- `tests/wsusscn2_probe.py` User-Agent identifier `UpdateWsi-WsusScn2Probe` -> `UpdateWsi-OfflineSyncProbe` (the standalone probe is not part of the gated suite)

Scope decisions (deliberately NOT renamed, by agreement):

- **Test file names** (`tests/wsusscn2_*.py`, 11 files) and the `wsusscn2_*` test-display names are retained. Their in-body identifier references were already updated in r11.14; renaming the filenames is left to a separate increment so this commit stays a clean rename of derived data artifacts only.
- **Conservative prose policy.** In SPEC / README / TESTING / `tests/README.md`, only prose naming the renamed files, directory, or field was updated. Prose that refers to the Microsoft artifact or format itself ("the wsusscn2 cab", "the wsusscn2 Master XML", "the wsusscn2 parser pipeline", etc.) is retained, consistent with retaining the literal `wsusscn2.cab`.
- **Runtime / operator-visible derived names retained** as cab-tied facts: the runtime cache directory `<WorkRoot>/cache/wsusscn2/`, the P06 debug output `wsusscn2_scan_raw.json`, the staging-directory prefix, and the `resolve-wsusscn2-cab` debug step.
- The literal `wsusscn2.cab` filename and its download URL are retained verbatim (Microsoft's actual distribution filename).

Verification: `psa.py` 0/0/0; `pwsh -ParseFile` 0 errors; all 15 gated offline tests green; `canonical_json_format_check` green over the renamed `data/` and `tests/fixtures/` paths; README en/ja lock-step `## 16 / ### 11` preserved; `.ps1` BOM + CRLF preserved (CR == LF == CRLF == 15456). No residual `WsusScnCab` / `wsusscn2-database` / `fixtures/wsusscn2` / `WsusScn2Probe` outside this CHANGELOG's history.

### r11.14 - WsusScn -> OfflineSync / ServicingDependency identifier rename (input/output layers)

Renames the `WsusScn*` function and variable family to names derived from Microsoft's own authoritative format name for the offline-scan metadata. The `wsusscn2.cab` Master XML's root element is `<OfflineSyncPackage>` (schema namespace `http://schemas.microsoft.com/msus/2004/02/OfflineSync`), so the input/source layer adopts the `OfflineSync*` prefix, while the generated output database adopts the functional `ServicingDependency*` name (matching SPEC B.19). The online Microsoft Update Catalog family (`*Catalog*`) is intentionally left unchanged so the online/offline distinction stays explicit. `$Script:ScriptVersion` `r11.13` -> `r11.14`; `$Script:ScriptTag` becomes `offline-sync-package-rename`. This is a pure identifier rename: no committed data, schema, or fixture file changes, so the shared epoch (`dataContractVersion`) stays `1` and `data/wsusscn2-database.json` is NOT regenerated.

Function renames (old -> new):

- `Get-WsusScnCabSourceUrl` -> `Get-OfflineSyncPackageUrl`
- `Test-WsusScnCabFresh` -> `Test-OfflineSyncPackageFresh`
- `Get-WsusScnCabIfNeeded` -> `Get-OfflineSyncPackageIfNeeded`
- `Invoke-WsusScnPackageXmlExtract` -> `Invoke-OfflineSyncPackageExtract`
- `ConvertFrom-WsusScnPackageXml` -> `ConvertFrom-OfflineSyncPackage`
- `Resolve-WsusScnRevisionToCab` -> `Resolve-OfflineSyncRevisionToCab`
- `Get-WsusScnServicingStackInfo` -> `Get-OfflineSyncServicingStackInfo`
- `Select-WsusScnLcuLeafRevision` -> `Select-OfflineSyncLcuLeafRevision`
- `Get-WsusScnCbsServicingSnippet` -> `Get-OfflineSyncCbsServicingSnippet`
- `Invoke-WsusScnLeafServicingStackExtract` -> `Invoke-OfflineSyncLeafServicingStackExtract`
- `Update-WsusScnServicingStackFromMeta` -> `Update-ServicingStackFromMeta`
- `New-WsusScnDependencyDatabase` -> `New-ServicingDependencyDatabase`

Variable / parameter renames (old -> new):

- `$Script:WsusScnOsCategoryGuids` -> `$Script:OfflineSyncOsCategoryGuids`
- `$Script:WsusScnUpdateClassificationGuids` -> `$Script:OfflineSyncUpdateClassificationGuids`
- `$Script:WsusScnCategoryGuidNameMap` -> `$Script:OfflineSyncCategoryGuidNameMap`
- `$Script:WsusScnEosEsuDenyProductGuids` -> `$Script:OfflineSyncEosEsuDenyProductGuids`
- `$WsusScnCabMeta` -> `$OfflineSyncPackageMeta`
- `$WsusScnCabInfo` -> `$OfflineSyncPackageInfo`
- `$WsusScnCabPath` / `$Script:WsusScnCabPath` -> `$OfflineSyncPackagePath`
- CLI parameter `-WsusScnCabPath` -> `-OfflineSyncPackagePath` (operator-visible; breaking)

Adds newcomer-oriented `.DESCRIPTION` lead notes to the central input-layer functions (`ConvertFrom-OfflineSyncPackage`, `Get-OfflineSyncPackageIfNeeded`, `Invoke-OfflineSyncPackageExtract`) explaining that the `OfflineSync*` names derive from the `<OfflineSyncPackage>` XML root element and the `.../msus/2004/02/OfflineSync` schema namespace.

Deferred to a follow-up data-shape change, intentionally NOT touched here: the config field `PatchBaseline.WsusScnCab`, the artifacts `data/wsusscn2-database.json` and `schema/wsusscn2-database.schema.json`, the `tests/fixtures/wsusscn2/` directory, and the standalone `tests/wsusscn2_probe.py`. The literal `wsusscn2.cab` filename and its download URL are retained verbatim (Microsoft's actual distribution filename).

### r11.13 - config-*.json data-contract `_meta` stamp (Layer 1 joins the shared contract)

Stamps the shared data-contract `_meta` block into the `data/config-Server*.json` Layer 1 baselines so they classify as `Current` under `Test-DataContractConsistency` instead of `Unknown`, completing the "stamped into every data artifact" intent of §B.19.10. `$Script:ScriptVersion` is bumped `r11.12` -> `r11.13`; `$Script:ScriptTag` becomes `config-datacontract-meta-stamp`. The shared epoch is unchanged (`dataContractVersion` stays `1`): the stamp adds a new contract-bearing artifact without altering any existing shape, so `data/wsusscn2-database.json` is NOT regenerated.

- **`schema/config.schema.json`.** Adds an optional `_meta` property (strict sub-schema: `dataContractId` const family GUID, `dataContractVersion` integer >= 1, `scriptVersion`, `generatedAt` date-time; `additionalProperties: false`). `_meta` was already permitted by the `^_` `patternProperties` rule; the explicit definition now also validates its shape. It is intentionally NOT added to the root `required` list, so a config without `_meta` stays schema-valid (and simply classifies `Unknown`).
- **`Save-ConfigWithBaseline`.** Now stamps/refreshes `_meta` (an order-stable `[pscustomobject]`) immediately before the canonical write, on every config write. Because Layer 1 only writes a config when a verified value actually changed, unchanged configs are not rewritten and their stamp is stable.
- **`data/config-Server{2016,2019,2022,2025}.json`.** Regenerated through the canonical serializer to append the `_meta` stamp (`dataContractVersion` 1, `scriptVersion` r11.13). The diff is purely additive — only the `_meta` block is added; no existing key is reordered or reformatted. All four now classify `Current`.
- **Docs.** SPEC §B.19.10 records that the Layer 1 configs carry the stamp as of r11.13 and that the epoch stays at 1. README is unchanged (lock-step preserved).
- **Verification.** psa.py 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green (15/15), including `config_schema_test` (validates the new `_meta` sub-schema), `canonical_json_format_check` (configs remain canonical), and `wsusscn2_data_contract_test`.

### r11.12 - P06 Stage 2 servicing-readiness wiring (off by default) and on-mount check rename (M1, §B.19.19.1 Step 2)

Wires the wsusscn2 Layer 2 servicing-readiness verdict into P06 behind a new opt-in switch, and renames the mount-time prerequisite check to match the servicing-readiness vocabulary. `$Script:ScriptVersion` is bumped `r11.11` -> `r11.12`; `$Script:ScriptTag` becomes `p06-servicing-readiness-wiring`. Per SPEC §B.19.19.1 this is Step 2 and ships as its own commit; default behaviour is unchanged.

- **P06 Stage 2 wiring (`-EnableDependencyCheck`, default OFF).** After `compare-patch-sets`, P06 now runs a `servicing-readiness-check` stage that calls the already-tested `Test-PatchServicingReadinessFromGraph` over the provided patch set, logging the overall status and per-patch verdicts (`Pass` / `SsTooOld` / `NotInDatabase` / `Superseded` / `N/A`). The check is **advisory** in this revision — it never blocks the build — and only runs when `-EnableDependencyCheck` is supplied. With the switch absent (the default), P06 behaviour is unchanged. Absence of `data/wsusscn2-database.json` degrades to `Unknown` (Stage 1 still stands), per §B.19.19.2.
- **Rename `Test-PatchDependencyClosureOnMount` -> `Test-PatchServicingReadinessOnMount`.** The mount-time A-3 prerequisite check (definition + its three call sites in the apply loops) is renamed to align with the servicing-readiness model; behaviour and the `$Script:PatchDependencyPolicy` governance are unchanged. The old name is left intact in historical CHANGELOG entries (history is not rewritten); SPEC §B.13, §B.19.13.2, and the Appendix E function table are updated to the new name.
- **Docs.** SPEC §B.19.19.1 records Step 2 as implemented (advisory, default OFF); the P06 parameter set documents `-EnableDependencyCheck`. README is unchanged (lock-step preserved).
- **Verification.** psa.py 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green (15/15). The new code path is gated off by default; the verdict function it calls is covered by T16/T17.

### r11.11 - wsusscn2 servicing-stack Stage 4b wiring (memory-safe streaming) and DB regeneration (M1, part 5b finish)

Wires the servicing-stack populate into the A04 RefreshDependencyDatabase pipeline as Stage 4b, behind a memory-safe streaming extractor, and regenerates the committed `data/wsusscn2-database.json` with the SS fields filled in for all 138 in-scope updates. `$Script:ScriptVersion` is bumped `r11.10` -> `r11.11`; `$Script:ScriptTag` becomes `wsusscn2-servicing-stack-streaming-populate`.

**Memory-safe streaming extractor.**
- **New `Get-WsusScnCbsServicingSnippet`** — an LCU leaf's `c/<rev>` CBS metadata is a single newline-free line up to ~67 MB (Server 2016); reading it whole with `Get-Content -Raw` peaked ~1.5 GB per leaf and drove the populate out of memory on a 4 GB host. The new scanner reads the file in 1 MiB byte buffers with a stateful UTF-8 decoder and a 512-char carry, keeping only the substrings the downstream `Get-WsusScnServicingStackInfo` matches on; peak is O(buffer) regardless of file size, and the snippet yields a result identical to the full-text read. Its capture patterns are held in lock-step with `Get-WsusScnServicingStackInfo`.
- **`Invoke-WsusScnLeafServicingStackExtract`** now streams each leaf via the scanner instead of `Get-Content -Raw`, and deletes each extracted `c/<rev>` immediately (disk hygiene). Its contract is unchanged — it still returns a revision -> text map (now a minimised snippet) — so the pure `Update-WsusScnServicingStackFromMeta` and gate T18 are untouched.

**Stage 4b wiring.**
- A04 gains a `Stage 4b: populate servicing-stack fields` step between Stage 4 (DB write) and Stage 5 (Layer 1). It derives the bundle-revision -> LCU-leaf-revision map from the in-memory parse result, streams the distinct leaves for their SS snippet, re-reads the just-written DB via `ConvertFrom-CanonicalJson`, enriches it in place with `Update-WsusScnServicingStackFromMeta`, and writes it back via `Save-CanonicalJsonFile` (so `_meta` and key order are preserved).
- **New `-SkipServicingStackPopulate` switch** (sibling of `-SkipLayer1Update`); the step is also skipped in DryRun (no DB was written).

**DB regenerated.**
- A full A04 run over the live 2026-05 cab (136,102 updates observed, 138 in scope) populated all 138 updates: `separate` x35 (Server 2016/2019 LCUs, e.g. `requiredServicingStackVersion` `10.0.14393.7692`), `combined` x60 (Server 2022/2025 LCUs with the SSU folded in), `checkpoint` x43 (baseline updates); `providedServicingStackVersion` is null throughout. `data/wsusscn2-database.json` grows 279,585 -> 298,218 bytes. Layer 1 was idempotent over the same cab (unchanged=4), so the `data/config-Server<N>.json` baselines are untouched.
- Peak `pwsh` RSS during the 138-leaf extraction was ~514 MB (vs the prior ~3.9 GB OOM), confirming the streaming scanner as the load-bearing fix.

- **Docs.** SPEC §B documents the Stage 4b semantics and `-SkipServicingStackPopulate`, and the Part B data-shape note now records the SS version/model fields as wired (no longer "a later M1 increment"). README is unchanged (lock-step preserved).
- **Verification.** psa.py 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green (15/15), with the data-contract, Layer 2 schema, canonical-format, and scope-invariant gates re-run against the regenerated DB.

### r11.10 - wsusscn2 servicing-stack populate functions and data-contract wiring (M1, parts 5b + 6)

Completes M1's function set. Adds the servicing-stack populate (the I/O-free pure halves plus a thin 7-Zip wrapper, designed so the offline CI exercises the logic and only the wrapper needs a real cab), and wires the existing `Test-DataContractConsistency` into the A04 RefreshDependencyDatabase pipeline. `$Script:ScriptVersion` is bumped `r11.9` -> `r11.10`; `$Script:ScriptTag` is set to `wsusscn2-servicing-stack-populate`. Populating the committed `data/wsusscn2-database.json` with these SS fields (which requires a full A04 run over the real cab) is a follow-up; the fields stay nullable/optional and the readiness check already tolerates their absence.

**M1 part 5b — servicing-stack populate (two-pass, I/O isolated).**
- Stage 3 (`ConvertFrom-WsusScnPackageXml`) now also records, per in-scope bundle, the leaf revision ids bundled under it (`LeafRevisionIds`), via a `bundleChildLeafRevs` map parallel to the existing payload roll-up. This is a pure addition (text in, no I/O); T12/T13 stay green.
- **`Select-WsusScnLcuLeafRevision`** (pure) — picks a bundle's LCU leaf revision from its `LeafRevisionIds`: a lone leaf; else the leaf whose revision id is the closest below the bundle's own (the LCU is emitted just before its bundle in the cab — empirically bundle 45255709 -> leaf 45255708); else the greatest; empty -> null.
- **`Update-WsusScnServicingStackFromMeta`** (pure) — second pass over the Layer 2 document; from a revision -> CBS-text map and a bundle-revision -> leaf-revision map, derives SS facts via `Get-WsusScnServicingStackInfo` and writes `requiredServicingStackVersion` / `servicingStackModel` (and a null `providedServicingStackVersion`, since the provided SS belongs to the configured patch set and is resolved at readiness-check time) onto each update; updates with no leaf metadata are left unchanged.
- **`Invoke-WsusScnLeafServicingStackExtract`** (the only I/O part) — resolves each leaf revision to its per-package cab via `Resolve-WsusScnRevisionToCab`, extracts the per-package cab then only the leaf's `c/<rev>` entry with 7-Zip, and returns the revision -> CBS-text map. Kept thin so the offline gates cover the pure halves.
- **`Get-SevenZipPath`** now also resolves the Linux `7z` / `7za` binaries (after the Windows `7z.exe` probe, so Windows behaviour is unchanged), letting the I/O wrapper be exercised against a cached cab on Linux/Claude/CI.
- Verified end-to-end against the live cab: the newest 2016 / 2022 / 2025 bundles resolved to leaves 45255708 / 45255607 / 295 and populated `separate` + `10.0.14393.7692` / `combined` + null / `checkpoint` + null respectively — matching M1 part 2.
- **New gate T18 (`wsusscn2_servicing_stack_populate_test.py`)** — 17 assertions over the two pure functions using the same CBS fixtures as T15.

**M1 part 6 — data-contract consistency wiring.**
- `Test-DataContractConsistency` is now called at the end of A04 (after Layer 2 is written and Layer 1 propagated), classifying every artifact in the data root and logging the worst status, so a stale / foreign / unstamped artifact is caught at refresh time instead of at consume time.
- The function gained directory-argument support: a directory in `-Path` expands to its `*.json` files (the A04 wiring passes the data root). Previously a directory was mis-read as a single file and reported Foreign.
- **New gate T19 (`wsusscn2_data_contract_test.py`)** — 11 assertions covering each status (Current / Stale / Refuse / Foreign / Unknown), directory expansion, the roll-up (Unknown never worsens), and that the committed Layer 2 DB classifies Current.

- **Docs.** SPEC §B.19.13.0 documents the populate functions and the Linux 7-Zip resolution; `TESTING.md` and `tests/README.md` register T18 and T19 (suite is now T1-T19).
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell, including **T18 17** and **T19 11**: T12 23, T13 15, T14 10, T15 16, T16 21, T17 15, T18 17, T19 11, scope-invariants 23, Layer 2 schema gate 16, config-schema 14, canonical-format 29, canonical 26, release-info-parser 13, release-info-resolver 22, dynamic-update-cache 20, catalog-fixture 13, catalog-title-tokens 18, dotnet-cu 16.

### r11.9 - wsusscn2 Layer 2 kbIds populate, DB regeneration, and Layer 2 schema gate (M1, part 5a)

First half of M1's data step. Populates `kbIds` on every Layer 2 update, regenerates the committed `data/wsusscn2-database.json` from the real cab so it conforms to the schema, and adds a gate that keeps the shipped DB in sync with the contract. `$Script:ScriptVersion` is bumped `r11.8` -> `r11.9`; `$Script:ScriptTag` is set to `wsusscn2-layer2-kbids-populate`. The per-leaf servicing-stack extraction (populating `requiredServicingStackVersion` etc.) is deliberately deferred to M1 part 5b; those fields stay optional/nullable in the schema and the readiness check already tolerates their absence.

- **`kbIds` populate (Stage 4).** `New-WsusScnDependencyDatabase` now emits a `kbIds` array on every update, recovered from the resolved `payloadUrls` via the `kb(\d+)` token, deduplicated and sorted, in bare numeric form (no `KB` prefix, SPEC B.19.8). This lets the Phase 2c readiness check resolve KBs directly instead of re-deriving from `payloadUrls`.
- **Committed Layer 2 regenerated from the real cab.** The shipped `data/wsusscn2-database.json` was regenerated from the live `wsusscn2.cab` (sha256 `e51d4b5a…c5d4a126`). It now conforms to `schema/wsusscn2-database.schema.json` with zero errors (the previously committed DB predated r11.4 and failed validation on six points: missing `dataContractId`/`dataContractVersion`, `sourceCab.path` instead of `sourceUrl`, `scope.now` instead of `evaluatedAt`). The new DB carries the data-contract identity, portable provenance (`sourceUrl` + `size` + `sha256`, no filesystem path), `scope.evaluatedAt`, populated `kbIds` on all 138 in-scope bundles, and the M1a EOS/ESU stats — the regeneration exercised the deny-list end to end and excluded 4,910 EOS/ESU bundles (Server 2008 / 2008 R2 / 2012 / 2012 R2) with the operator warning.
- **New Layer 2 schema gate (`wsusscn2_layer2_schema_test.py`).** 16 stdlib-only assertions validating the committed DB against the schema (reusing the draft-07-subset validator from `config_schema_test.py`) plus the M1 invariants the schema can't express: data-contract identity, portable provenance, `kbIds` presence + numeric form, the Microsoft-prose hard rule, and forward-compatible servicing-stack field shapes. No T number — data gate, mirroring the format/config-schema/scope-invariants gates.
- **T12 extended.** `wsusscn2_parser_test.py` gains assertion 21b (every emitted update carries a `kbIds` array) and the fixture `expected-output.json` gains the empty `kbIds` arrays its payload URLs imply; T12 is now 23 assertions.
- **Docs.** SPEC §B.19.10 records the `kbIds` populate status and the Layer 2 schema gate; `TESTING.md` and `tests/README.md` register the gate and the T12 count change.
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell, including the new gate: T12 23, T13 15, T14 10, T15 16, T16 21, T17 15, scope-invariants 23, **Layer 2 schema gate 16**, config-schema 14, canonical-format 29, canonical 26, release-info-parser 13, release-info-resolver 22, dynamic-update-cache 20, catalog-fixture 13, catalog-title-tokens 18, dotnet-cu 16. The regenerated DB round-trips byte-identically through `canonical_json_dumps` (it was written by `Save-CanonicalJsonFile`).

### r11.8 - wsusscn2 recency fallback (M1, part 4)

Fourth M1 increment. Adds the recency fallback to `Test-PatchServicingReadinessFromGraph` (SPEC B.19.7.2 / handoff section 2.4): a configured KB that is not in scope is reported as superseded by the newest in-scope LCU for its OS family, rather than as a data gap. `$Script:ScriptVersion` is bumped `r11.7` -> `r11.8`; `$Script:ScriptTag` is set to `wsusscn2-recency-fallback`.

- **Newest-in-scope-LCU index per OS family.** The verdict function now builds, per `$Script:WsusScnOsCategoryGuids` family, the newest in-scope LCU — a `SecurityUpdates`-classified bundle carrying the family's allow-list product GUID, selected by greatest `creationDate`.
- **Fallback on presence miss.** When a configured KB does not resolve to an in-scope update, the patch's `OsKey` is resolved to a family (an exact family key such as `Server2016`, or a free-form key whose year token matches, e.g. `WindowsServer2022` -> `Server2022`). If that family has an in-scope LCU, the verdict becomes `Superseded` with the fallback target's `UpdateId`, `requiredServicingStackVersion`, and `servicingStackModel` surfaced and a `Notes` line naming the target KB and citing the recency fallback. Only when the family cannot be resolved or has no in-scope LCU does the verdict stay `NotInDatabase`. A direct KB match always wins over the fallback path.
- **Verified against the committed cab-derived DB.** With the committed `data/wsusscn2-database.json`, an out-of-scope `KB9999999` + `OsKey=Server2016` falls back to `updateId 276ca876-…` (KB5087537), the real newest in-scope Server 2016 LCU (creationDate 2026-05-11) — matching the leaf identified during M1 part 2.
- **New gate T17 (`wsusscn2_recency_fallback_test.py`).** 15 assertions over `tests/fixtures/wsusscn2/recency-fallback-database.json` (two Server 2016 LCUs of different dates + one Server 2022 LCU): 2016 and 2022 fallbacks (newest-LCU selection, SS surfacing, target KB in notes), exact and free-form OsKey resolution, `NotInDatabase` when no fallback target, direct match precedence, and the roll-up. Offline (only I/O is reading the Layer 2 JSON). The fixture is registered in the canonical-format gate (now 29 files).
- **psa hygiene.** The OS-family resolver uses a literal `String.Contains` test rather than `-match`, avoiding the `-match`-against-bare-token regex pitfall (PSA2003); the year tokens `2016/2019/2022/2025` are mutually non-substring so a containment test is unambiguous.
- **Docs.** SPEC §B.19.7.2 documents the implementation; `TESTING.md` and `tests/README.md` register T17 (suite is now T1-T17).
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell, including **T17 15**: T12 22, T13 15, T14 10, T15 16, T16 21, T17 15, scope-invariants 23, config-schema 14, canonical-format 29, canonical 26, release-info-parser 13, release-info-resolver 22, dynamic-update-cache 20, catalog-fixture 13, catalog-title-tokens 18, dotnet-cu 16.

### r11.7 - wsusscn2 Phase 2c readiness verdict (M1, part 3)

Third M1 increment. Implements the Phase 2c readiness verdict as `Test-PatchServicingReadinessFromGraph`, replacing the abandoned SSU KB-prerequisite-closure model with the three-check servicing-stack model (SPEC B.19.13 / B.19.13.1). `$Script:ScriptVersion` is bumped `r11.6` -> `r11.7`; `$Script:ScriptTag` is set to `wsusscn2-phase2c-readiness-verdict`.

- **`Test-PatchServicingReadinessFromGraph`.** Reads Layer 2 at `$DatabasePath`, indexes updates by KB (the update's `kbIds` when present, else the `kb(\d+)` token recovered from `payloadUrls`, matching the scope-invariants gate) and by `revisionId`, and emits one verdict object per resolved patch with the finalised full-spelling shape (`KbId` / `UpdateId` / `Verdict` / `RequiredServicingStackVersion` / `ProvidedServicingStackVersion` / `ServicingStackModel` / `Superseded` / `Notes`).
- **Three checks.**
  - *Presence* — no KB match in Layer 2 → `NotInDatabase`.
  - *SS version comparison* — `separate` OSes only. Provided SS resolves from `$PolicyOverride[OsKey]`, else `$WimMountState.ProvidedServicingStackVersion`, else the update's `providedServicingStackVersion`; when provided and required are both present, numerically comparable, and provided < required → `SsTooOld` (the `0x800f0823` predictor). `combined` / `checkpoint` skip the check (SSU travels inside the LCU). When `servicingStackModel` / `requiredServicingStackVersion` are absent (Layer 2 predates M1 population), the SS check is reported as skipped in `Notes` and never fails the patch.
  - *Supersession* — `Superseded` only when a `supersededByRevisionIds` entry is itself an in-scope update in Layer 2 (a successor that points out of scope does not mark the patch superseded — it is not a data gap).
- **Roll-up & precedence.** Verdict precedence `NotInDatabase` > `SsTooOld` > `Superseded` > `Pass`; `OverallStatus` = `Fail` (any NotInDatabase/SsTooOld), else `Warning` (any Superseded), else `Pass`. A missing or unreadable Layer 2 yields `Available = $false` / `OverallStatus = 'Unknown'`. Layer 2 is read with the project's `ConvertFrom-CanonicalJson` (consistent with every other JSON reader in the script), which preserves the textual form of dates on every PowerShell version, so `_meta.generatedAt` survives as its canonical ISO-8601 string with no reformatting.
- **New gate T16 (`wsusscn2_readiness_verdict_test.py`).** 21 assertions over a populated Layer 2 fixture (`tests/fixtures/wsusscn2/readiness-database.json`: separate/combined/checkpoint updates, an in-scope-superseded update, an out-of-scope-superseded update). Covers all three checks, both SS outcomes (via WimMountState and via PolicyOverride), N/A skip, supersession in/out of scope, precedence, roll-up, ISO-8601 normalisation, and the missing-DB Unknown path. Offline (only I/O is reading the Layer 2 JSON). The fixture is registered in the canonical-format gate (now 28 files).
- **Docs.** SPEC §B.19.13.1 documents the implementation; `TESTING.md` and `tests/README.md` register T16 (suite is now T1-T16).
- **Canonical-JSON reader consistency.** The Layer 2 read uses `ConvertFrom-CanonicalJson` (the project's hand-rolled parser), matching every other JSON reader in the script, so date strings keep their textual form across PowerShell versions and no `ConvertFrom-Json` `[datetime]` workaround is needed. All committed-data writes elsewhere continue to go through `Save-CanonicalJsonFile`; the remaining raw `ConvertTo-Json` uses are deep-copy idioms, volatile debug traces, and HTTP request bodies (never committed canonical artifacts).
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell, including **T16 21**: T12 22, T13 15, T14 10, T15 16, T16 21, scope-invariants 23, config-schema 14, canonical-format 28, canonical 26, release-info-parser 13, release-info-resolver 22, dynamic-update-cache 20, catalog-fixture 13, catalog-title-tokens 18, dotnet-cu 16. Also exercised against the committed Layer 2 DB (SS fields not yet populated → presence + supersession only, SS reported as skipped), confirming forward-compatibility once M1 part 4 regenerates the data.

### r11.6 - wsusscn2 servicing-stack extraction (M1, part 2)

Second M1 increment. Adds the per-package CBS metadata extraction that feeds the Phase 2c "SS version comparison" check (SPEC B.19.13 check 2), implemented as two pure, offline-testable functions. `$Script:ScriptVersion` is bumped `r11.5` -> `r11.6`; `$Script:ScriptTag` is set to `wsusscn2-servicing-stack-extraction`. This increment adds the extraction primitives; wiring them into a full LCU-bundle -> leaf -> cab walk over the live cab, and the verdict function itself, follow in later M1 parts.

- **`Resolve-WsusScnRevisionToCab`.** Maps a revision id to the per-package cab that holds its `c/<revisionId>` CBS metadata, using the top-level cab's `index.xml` `<CABLIST>` `RANGESTART` boundaries (a revision `R` lives in the cab with the greatest `RANGESTART` <= `R`). Lets the analysis step locate one revision's metadata with a single targeted 7-Zip extraction instead of expanding all ~73 per-package cabs. Pure function (text in, cab name out); no file or 7-Zip I/O.
- **`Get-WsusScnServicingStackInfo`.** Reads a leaf's CBS metadata and derives `requiredServicingStackVersion` + `servicingStackModel`:
  - **separate** (Server 2016 / 2019): `installerAssembly` servicing-stack version is a real build (e.g. `10.0.14393.7692`); that value is the required SS floor for check 2.
  - **combined** (Server 2022): `installerAssembly` version is the nominal `6.0.0.0` placeholder with an inline `Package_for_ServicingStack_<nnnn>`; the SSU travels inside the LCU, so `requiredSs` is null and check 2 is N/A.
  - **checkpoint** (Server 2025): no CBS rollup / servicing-stack metadata at all (`.msu` leaf); `requiredSs` is null. Empty input is treated as checkpoint and never throws.
- **Empirical grounding.** Verified against the 2026-05 `wsusscn2.cab` (sha256 `e51d4b5a...c5d4a126`): newest Server 2016 LCU leaf -> `installerAssembly` `10.0.14393.7692`, no inline servicing-stack package (separate); Server 2022 leaf -> `6.0.0.0` + `Package_for_ServicingStack_5120` (combined); Server 2025 leaf -> ~1 KB metadata blob, no rollup/SS tokens (checkpoint). The RANGESTART map and the model derivation both run correctly over the real cab.
- **New gate T15 (`wsusscn2_servicing_stack_test.py`).** 16 assertions over a trimmed `index.xml` CABLIST and three minimised real-cab CBS leaf fixtures (`tests/fixtures/wsusscn2/cbs/leaf-{2016-separate,2022-combined,2025-checkpoint}.xml`). Covers RANGESTART mapping (exact-boundary, one-below, zero), the three model derivations, inline-package detection, and empty-input robustness. Offline (text input; no cab/7-Zip).
- **Docs.** SPEC gains §B.19.13.0 documenting the two functions, the RANGESTART rule, and the separate/combined/checkpoint derivation with the empirical anchors; `TESTING.md` and `tests/README.md` register T15 (suite is now T1-T15).
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell, including **T15 16**: T12 22, T13 15, T14 10, T15 16, scope-invariants 23, config-schema 14, canonical-format 27, canonical 26, release-info-parser 13, release-info-resolver 22, dynamic-update-cache 20, catalog-fixture 13, catalog-title-tokens 18, dotnet-cu 16. Both functions additionally exercised against the live 640 MB cab's real CBS metadata for 2016 / 2022 / 2025.

### r11.5 - EOS/ESU deny-list warned-exclusion in the wsusscn2 scope filter (M1, part 1)

First implementation increment of M1 (the wsusscn2 analysis step). Adds the explicit EOS/ESU deny-list to the Stage 3 scope filter with allow-overrides semantics matching the `classify_scope` reference, plus warned (not silent) exclusion. `$Script:ScriptVersion` is bumped `r11.4` -> `r11.5`; `$Script:ScriptTag` is set to `wsusscn2-eos-esu-deny-list-warned-exclusion`.

- **Deny-list GUID table.** New `$Script:WsusScnEosEsuDenyProductGuids` (Server 2008 / 2008 R2 / 2012 / 2012 R2) — product categories that persist in wsusscn2 with live payload after the OS leaves support but are out of ISO-integration scope (SPEC B.19.7.1).
- **Scope-filter deny judgment (allow-overrides).** `ConvertFrom-WsusScnPackageXml` gains a `-DenyProductGuids` parameter (defaulting to the table) and counts deny-excluded bundles. A bundle is deny-excluded iff it carries a deny GUID AND no allow GUID, so multi-OS overlap bundles (which also carry an allow GUID) stay in scope — matching the `classify_scope` allow-overrides contract and avoiding the deny-overrides trap. An unknown-product bundle is still rejected by the allow-list, but is NOT counted as EOS/ESU.
- **Exclusion accounting + warning.** The parser records `Stats.EosEsuBundlesExcluded` (count) and `Stats.EosEsuFamiliesExcluded` (distinct OS families), surfaced in the Layer 2 `_meta.stats` as `eosEsuBundlesExcluded` / `eosEsuFamiliesExcluded`. When the count is non-zero, `New-WsusScnDependencyDatabase` emits a single operator `Write-Caution` naming the count and families (the §4 "warned exclusion" decision; the parser itself stays quiet, only the orchestrator warns).
- **New gate T14 (`wsusscn2_deny_list_test.py`).** 10 assertions over a dedicated fixture (`tests/fixtures/wsusscn2/deny-list-package.xml`: deny-only 2012 R2, overlap 2012 R2 + 2016, deny-only 2008, unknown product). Verifies the counts, families, admit of the overlap bundle (with both its deny and allow GUIDs retained), exclusion of the deny-only bundles, and that the unknown-product bundle is excluded without being counted. Executable check that the PowerShell filter matches `classify_scope`.
- **Docs.** SPEC §B.19.7.1 documents the implementation (stat names, the orchestrator warning, T14); SPEC Stage 4 `_meta.stats` shape gains the two fields; `TESTING.md` and `tests/README.md` register T14 (suite is now T1-T14); the T12 fixture `expected-output.json` `_meta.stats` gains `eosEsuBundlesExcluded: 0` / `eosEsuFamiliesExcluded: []` (the T12 fixture has no deny bundles).
- **Verification.** psa.py 4.2.0 0/0/0; `pwsh` 7.4.6 ParseFile 0 errors; full offline suite green under real PowerShell: T12 22, T13 15, **T14 10**, scope-invariants 23, config-schema 14, canonical-format 27, canonical 26, release-info-parser 13, dynamic-update-cache 20, dotnet-cu 16. The committed `data/wsusscn2-database.json` is regenerated (with the new stats) by a Refresh action / the remaining M1 steps.

### r11.4 - wsusscn2 data-contract stamping, provenance hygiene, and cache-file rename

Second increment of the Step 0 data-model foundation. Brings the generator and the supporting docs/tests into line with the r11.3 schema: the Layer 2 generator now emits the shared data-contract identity and the hygiene-corrected `_meta`, and a cross-cutting consistency function is added. `$Script:ScriptVersion` is bumped `update-wsi-2026.05.29-r11.1` -> `update-wsi-2026.05.29-r11.4`; `$Script:ScriptTag` is set to `wsusscn2-data-contract-hygiene-and-cache-rename`.

- **Shared data-contract identity constants.** New `$Script:DataContractId` (`4c173c61-c099-4512-9283-f5d951beda8b`) and `$Script:DataContractVersion` (`1`) — the single source of truth for cross-cutting data-quality, stamped into generated artifacts and superseding per-model schema versions.
- **`New-WsusScnDependencyDatabase` `_meta` updated to the r11.3 schema.** Now emits `dataContractId` / `dataContractVersion`; `sourceCab` carries a portable `sourceUrl` (from `Get-WsusScnCabSourceUrl`) instead of the local filesystem `path`; the recency-evaluation timestamp is `scope.evaluatedAt` (renamed from `now`). The `ConvertFrom-WsusScnPackageXml` stats field `Now` is renamed `EvaluatedAt` to match.
- **New `Test-DataContractConsistency` function.** Cross-cutting gate that compares each data artifact's stamped `dataContractId` / `dataContractVersion` against the script's values and returns an `OverallStatus` of Current / Stale / Refuse / Foreign / Unknown. Defined and available; wiring into the runtime path (e.g. P02 / pre-consume) is deferred to a later increment so it is not run against pre-contract committed data.
- **`cache-du-*` renamed to `cache-dynamicupdate-*`** (the `du` abbreviation did not convey "Dynamic Update"). The path helper and all in-script comment references are updated (12 occurrences); the two committed cache files `data/cache-du-Server{2022,2025}.json` are renamed to `data/cache-dynamicupdate-Server{2022,2025}.json`.
- **Fixture + parser-test alignment.** `tests/fixtures/wsusscn2/expected-output.json` has `_meta.scope.now` renamed to `evaluatedAt` (re-emitted through the canonical serializer). `tests/wsusscn2_parser_test.py` `ENV_FIELDS` gains `dataContractId` / `dataContractVersion` so the structural compare strips the script-stamped metadata.
- **SPEC updated.** §B.19.10 now names `schema/wsusscn2-database.schema.json` as authoritative (the prose §B.19.10.1-10.4 is the deprecated draft, superseded by the schema), documents the provenance hygiene and servicing-stack fields, and replaces the never-implemented `_meta.ParserVersion` versioning with the shared `dataContractId` / `dataContractVersion` mechanism. §B.19.13.1 finalises the verdict field names to full spelling (`RequiredServicingStackVersion` / `ProvidedServicingStackVersion` / `ServicingStackModel`), dropping the `RequiredSs` abbreviation.
- **Stale-reference cleanup (from the r11.3 rename).** `README.md` / `README.ja.md` (bilingual lock-step), `TESTING.md`, and `tests/README.md` had their `schema/config-v2.1.schema.json` references corrected to `schema/config.schema.json` and their `cache-du-*` references corrected to `cache-dynamicupdate-*`; the README schema section gains a Layer 2 schema + shared-data-contract bullet (en/ja).
- **Deferred.** The shared data-contract block is NOT yet added to `schema/config.schema.json`: the Layer 1 config has no `_meta` block (it carries a top-level `Schema` field and PascalCase keys), so its data-contract stamping is modelled together with the config generator change, the reconciliation of the existing `Schema` field, and config-data regeneration in the config-focused increment.
- **Verification.** `psa.py` 4.2.0 reports 0/0/0 on the modified script. Stdlib gates remain green (`config_schema_test` 14, `wsusscn2_scope_invariants` 23, `canonical_json_format_check` 27 — the latter over the renamed cache files and the re-emitted fixture). The committed `data/wsusscn2-database.json` still carries the previous `_meta` shape until a Refresh action regenerates it; the stdlib gate that validates live Layer 2 data against `wsusscn2-database.schema.json` is added once that regeneration lands (M1). The PowerShell-harness gates (T12/T13) must be run in a `pwsh` environment by the maintainer; the fixture and `ENV_FIELDS` were updated so they pass.

### r11.3 - Layer 2 data-model schema + shared data-contract identity (schema + config rename; no PowerShell change)

First increment of the Step 0 data-model foundation. Establishes the data model as the base layer (contract-first, the same pattern as r11.2): the data shape and its cross-cutting identity are fixed in a formal schema before the generating PowerShell code and the committed data are brought into conformance (a later increment / M1). **No PowerShell change in this entry** -- `Update-WindowsServerIso.ps1` is untouched and `$Script:ScriptVersion` is unchanged.

- **New `schema/wsusscn2-database.schema.json` (Draft-07).** Authoritative machine-readable contract for the Layer 2 `data/wsusscn2-database.json`, parallel to the Layer 1 `schema/config.schema.json`. Encodes the implemented `_meta` + `updates` (flat array, camelCase) shape and supersedes the deprecated `Packages`/`RevisionIndex`/PascalCase prose sketch in SPEC §B.19.10.1-10.4 (the SPEC editorial rewrite follows in a later increment).
- **Shared, cross-cutting data-contract identity (replaces per-model schema versions).** The schema pins `_meta.dataContractId` as a constant family GUID (`4c173c61-c099-4512-9283-f5d951beda8b`) and requires `_meta.dataContractVersion` (integer, first epoch `1`). The intent: a single Script-side source of truth, stamped identically into every data artifact, so one comparison validates the whole set cross-functionally rather than reconciling independent per-model versions. The Script-side constants, artifact stamping, and the `Test-DataContractConsistency` cross-cutting gate land in the next increment.
- **Target servicing-stack fields defined (populated by M1).** `updates[].requiredServicingStackVersion`, `providedServicingStackVersion` (full spelling, no abbreviation; nullable), `servicingStackModel` (`separate`/`combined`/`checkpoint`), and `kbIds` (numeric KB strings recovered from `payloadUrls`, persisted for presence lookup) are declared as the target shape for the SS-version-comparison verification model (SPEC §B.19.13).
- **Provenance / hygiene encoded in the contract.** `_meta.sourceCab` requires a portable `sourceUrl` (the canonical CDN URL) and forbids the previously-committed local filesystem `path`; the recency-evaluation timestamp is `_meta.scope.evaluatedAt` (renamed from the ambiguous `now`). These take effect in the committed data when the generator is updated (next increment).
- **Renamed `schema/config-v2.1.schema.json` -> `schema/config.schema.json`** (filename de-versioned; the version now lives in the shared `dataContractVersion`, not in the filename). `tests/config_schema_test.py` references updated (3 occurrences). The config schema content is unchanged in this entry; the shared data-contract block is added to it in the next increment.
- **Verification.** The new schema was validated against 10 positive/negative controls (conforming doc accepted; missing/foreign `dataContractId`, legacy `sourceCab.path`, missing `sourceUrl`, legacy `scope.now`, invalid `servicingStackModel`, missing-required and unknown update fields all rejected). These controls use a JSON-Schema library and are intentionally NOT committed as a gate, preserving the stdlib-only rule for the committed test suite; the committed stdlib gate that validates live Layer 2 data against this schema is added once the generator emits the conforming shape. Existing stdlib gates remain green (`config_schema_test` 14, `wsusscn2_scope_invariants_test` 23, `canonical_json_format_check` 27); the PowerShell-harness gates (T12/T13) are unaffected (no `.ps1` or data change).

### r11.2 - wsusscn2 Phase 2c EOS/ESU scope investigation (docs + Python test only)

Records the findings of a 2026-05-12 reverse-engineering of a real `wsusscn2.cab` (sha256 `e51d4b5a...`, 641 MB) into the SPEC, the research knowledge base, and a new offline Python gate. **No PowerShell change in this entry** -- `Update-WindowsServerIso.ps1` is untouched and `$Script:ScriptVersion` is unchanged; the PowerShell implementation of the deny-list filter and the SS-version-comparison verification model is deferred to a later session. This entry is documentation + test scaffolding that fixes the contract that implementation must satisfy.

- **New gate `tests/wsusscn2_scope_invariants_test.py` (23 assertions, stdlib-only, no PowerShell).** Data-driven contract check of the EOS/ESU exclusion model over `data/wsusscn2-database.json` (production) and `tests/fixtures/wsusscn2/expected-output.json` (fixture), plus a unit test of the allow-overrides `classify_scope` reference function on synthetic cases (in-scope LCU admitted; ESU-only rollup excluded; multi-OS overlap KB890830 admitted). Asserts: allow/deny GUID-table disjointness, scope.productGuids excludes the deny-list, every in-scope update carries an allow-list GUID, no in-scope update is deny-only, no in-scope payload references a known ESU/EOS KB, and a per-OS recency floor. Registered as an unnumbered "scope-invariants gate" mirroring the format/schema-gate convention. The PowerShell deny-list filter (later session) MUST match `classify_scope`.
- **SPEC §B.19.7 rewritten** to express the scope filter as an allow-list with **allow-overrides** semantics, with a new **§B.19.7.1 EOS/ESU deny-list** (Server 2008 / 2008 R2 / 2012 / 2012 R2 Product GUIDs) and **§B.19.7.2** effective-reach/fallback note. Recency clause documented as `-RecencyMonths` (default 24, 36 supported, -1 disables).
- **SPEC §B.19.13 Phase 2c model correction.** The verdict model is redefined from an (impossible) SSU KB-prerequisite *closure* to three checks -- presence, **servicing-stack version comparison** (`installerAssembly` floor vs SSU-provided version), and supersession/identity. A revised `RequiredSs`/`ProvidedSs`/`SsModel` verdict shape is sketched as the target for the next-session implementation.
- **SPEC §B.19.10 schema-drift correction note.** Records that the implemented Layer 2 is `_meta` + `updates` (flat array, camelCase: `productGuids`/`classificationGuids`/`recencyMonths`/`now`, per-update `updateId`/`payloadUrls`/...), not the original `Packages`/`RevisionIndex`/PascalCase draft; points to the fixture and the new gate as authoritative.
- **research `windows-server-iso-update-mechanics.{en,ja}.md`** updated in lock-step: §5.3 corrected (no LCU-to-SSU KB-prereq edge exists; dependency is a minimum servicing-stack version via `installerAssembly`), §5.4 re-grounded on the 2026-03/04/05 four-family finding (2016 separate / 2019 separate+embedded / 2022 combined / 2025 checkpoint `.msu`), §5.5 re-stated as presence + SS-version-comparison + supersession (not KB closure), §5.7 extended with the deny-list + allow-overrides rule, and new **§5.8 (EOS/ESU data persistence)** and **§5.9 (recency window and fallback depth)** added.
- **TESTING.md / tests/README.md** updated to register the scope-invariants gate (status table, CI Stage 1 row 10, file inventory, quick-start) and bump the unnumbered-gate count from two to three.

### r11.1 - cross-repo canon encoding/TLS helper rename

Renames two host-configuration helpers to their Deploy-AMD canon names so that functions performing the same work carry the same names across repositories. Function behaviour is unchanged; this is a pure rename plus the script-identity bump.

- **`Set-ConsoleUtf8` renamed to `Set-Utf8PipelineEncoding`** (1 definition + 1 call site). The body sets all three encodings — `[Console]::OutputEncoding`, `[Console]::InputEncoding`, and the pipeline-global `$OutputEncoding` — so the canon name (which captures the broader pipeline-encoding scope) is more accurate than the old console-only name.
- **`Set-Tls12` renamed to `Set-TlsSecurityProtocol`** (1 definition + 1 call site). The body assigns the `[Net.ServicePointManager]::SecurityProtocol` bitmask; the pre-rename name understated this (the bitmask is broader than TLS 1.2).
- The two bodies are intentionally left unchanged (they are simpler than, and divergent from, the Deploy-AMD canon implementations) and are classified as carve-outs — same name, divergent body — in the sibling repository's SPEC §A.11.7 partial-participant list.
- Corrected a stale copy/paste comment in the `Set-TlsSecurityProtocol` body: the `.DESCRIPTION` previously cited Speaker Deck / `files.speakerdeck.com` (inherited from the sister `Download-SpeakerDeck.ps1` script it was seeded from). It now names this script's actual TLS 1.2+ download endpoints — the Microsoft Update Catalog (`catalog.update.microsoft.com`), the Windows Update CDN (`catalog.s.download.windowsupdate.com`, which serves `wsusscn2.cab`), and the GitHub release endpoints (`api.github.com` / `github.com`) used for the 7-Zip fallback. Comment-only change; no code or behaviour change.
- `$Script:ScriptVersion` bumped `update-wsi-2026.05.29-r11.0` → `update-wsi-2026.05.29-r11.1`; `$Script:ScriptTag` set to `cross-repo-canon-iso-encoding-tls-rename`.

### r11.0 - cross-repo canon port alignment

Aligns this script's ported logging / DebugTrace helpers to the
Deploy-AMD shared-helper canon so that functions performing the same
work carry the same names across repositories, and registers this
script in the sibling repository's SPEC §A.11.7 as a *partial port
participant*. Function behaviour is unchanged; this is a naming and
body-alignment release plus the script-identity bump.

- **`Write-Warn` renamed to `Write-Caution`** script-wide (120
  occurrences: 1 definition + 119 call sites), matching the canon name
  adopted in the sibling repo's
  `cross-repo-shared-utility-canon-write-caution` release. The
  word-boundary rename leaves the unrelated built-in `Write-Warning`
  (5 call sites) untouched.
- **Canonical `Write-Detail` helper added.** The three info lines in
  `Install-SevenZipFallback` (`Version` / `Source` / `URL`) that the
  original port had mapped onto `Write-Step` now call `Write-Detail`,
  matching the Deploy-AMD source and removing the last logger-naming
  divergence previously noted as "deferred" in SPEC §B.19.4.4.
- **Seven helpers aligned to the canon body** (parameter-name and
  type-annotation differences only): `Write-Caution`, `Write-Step`,
  `Write-Ok`, `Write-Fail`, `Write-Skip`, `_DebugTrace_RetireFrame`,
  and `Enable-AutoExportOnPhaseFailure`. As a side effect of the
  `Write-Caution` rename, `Write-DebugFailureReport` also became
  byte-identical to canon.
- **Cross-repo byte-identity grew from 10 to 19** of the tracked canon
  helpers. The remaining same-name helpers (`Write-PhaseHeader`,
  `Write-PhaseFooter`, `_DebugTrace_WriteJsonlLine`, `Start-DebugTrace`,
  `Stop-DebugTrace`, `Enable-DebugTraceFileOutput`,
  `Show-PowerShellEnvironment`) stay as documented carve-outs because
  this script's phase / DebugTrace model and the
  `Show-PowerShellEnvironment` driver-context differ structurally.
  `Set-TlsSecurityProtocol`, `Set-Utf8PipelineEncoding`, and
  `Assert-Admin` are not present in this script.
- **SPEC §B.19.4.4 updated** from the "renamed loggers / deferred"
  wording to the aligned state; the only residual per-script
  differences in the ported 7-Zip helpers are the GitHub API
  `User-Agent` string and a `psa-disable` justification comment, both
  of which correctly encode this script's own identity.
- The sibling repository records the reciprocal classification under a
  new SPEC §A.11.7 *partial port participant* tier under the shared
  `cross-repo-canon-iso-port-alignment` tag.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.4` ->
  `update-wsi-2026.05.29-r11.0`. `$Script:ScriptTag`:
  `cross-repo-canon-iso-port-alignment`.
- `psa.py` (4.2.0) remains 0 / 0 / 0 on this script.

### r10.4 - Config Schema v2.1 and NeutralPatches enforcement

> **Retroactive entry.** This and the four entries below (r10.0 -
> r10.3) document commits that were shipped without their own
> CHANGELOG headings. They are reconstructed here from the commit
> log and the on-disk artifacts so that the version history between
> r09.0 Step 2b3 and r11.0 is contiguous, satisfying AGENTS.md §8
> Self-Check Gate #12. No code is changed by this reconstruction;
> only the changelog record is completed.

Introduces a machine-readable config schema and a CI gate so the
legacy `PatchBaseline.Patches` field cannot silently return.

- **`schema/config-v2.1.schema.json` added.** Declares `Schema=2.1`,
  forbids the legacy `Patches` property, requires `NeutralPatches`
  in `PatchBaseline`, and applies tight structural / type checks.
- **`tests/config_schema_test.py` added** - a stdlib-only draft-07
  subset validator that checks every `data/config-Server*.json`
  against the new schema and carries a targeted regression guard
  against the reappearance of `Patches`. 14 assertions.
- **CI stage 1 runs the new schema conformance test.**
- **SPEC.md** documents that resolved patches live in
  `NeutralPatches` and describes the schema / CI gate.
- **Script side**: `PatchBaseline` defaults switch from `.Patches`
  to `.NeutralPatches` (and `PatchBaseline.Schema` -> `2.0`); all
  `.Patches` assignments are replaced with `.NeutralPatches`.
- `05dd5d1` bumps `psa.py` `__version__` 4.1.0 -> 4.2.0 to match the
  rule addition recorded under r10.1.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.3` ->
  `update-wsi-2026.05.28-r10.4`. `$Script:ScriptTag`:
  `step2b7-p03-neutralpatches-and-config-schema`.

### r10.3 - PatchBaseline property guard

Prevents an assignment error when a baseline is loaded from older
JSON that lacks the expected note properties.

- Pre-creates null `NoteProperty` placeholders on
  `OsProfile.PatchBaseline` (`Patches`, `PatchTuesdayOfBaseline`,
  `LastVerifiedDate`, `LastVerifiedBy`, `VerificationMethod`) before
  any value is assigned, because `ConvertFrom-Json` /
  `ConvertFrom-CanonicalJson` cannot set a non-existent
  `NoteProperty`.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.2` ->
  `update-wsi-2026.05.28-r10.3`. `$Script:ScriptTag`:
  `step2b6-p03-patchbaseline-property-guard`.

### r10.2 - committed wsusscn2 database and Stage 3 progress logging

Re-adds the generated Layer 2 database (it had been removed in
`4b2ac63`) in line with SPEC §B.19.2.2 ("Layer 2 IS committed") and
makes the long Stage 3 parse observable.

- **`data/wsusscn2-database.json` re-added** - the parsed wsusscn2
  results and summary statistics for the four in-scope OS families.
- **Stage 3 progress reporting** in `ConvertFrom-WsusScnPackageXml`:
  tracks `$lastProgressMark` / `$progressEvery` (default 20000) and
  emits periodic `Write-Step` tallies of parsed updates,
  file-locations, and in-scope bundles during long runs.
- **`_DependencyVerified*` metadata added** to
  `config-Server2016/2019/2022/2025.json`.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.1` ->
  `update-wsi-2026.05.28-r10.2`. `$Script:ScriptTag`:
  `step2b5-stage3-parse-progress`.

### r10.1 - OutputType, PSA7003 non-ASCII rule, docs normalization

Two functional additions plus documentation normalization, shipped
across `0ebab36` and `76d9e71`.

- **`PSA7003` added to `psa.py`** (warning, enabled by default):
  flags non-ASCII characters in `.ps1` script bodies outside the
  UTF-8 BOM. Adds `compute_non_ascii_stats()` /
  `check_non_ascii_chars()`, registers the rule in `RULES`, hooks it
  into `analyze_text()` and `main()`, and ships a codepoint-name map
  for actionable diagnostics. `psa.py` CHANGELOG/VERSION bump to
  4.2.0; configuration template, SPEC, README (EN/JA), and rule /
  unit tests updated. `Update-WindowsServerIso.ps1` is the verified
  first consumer (0 findings under the new rule).
- **`[OutputType([object])]` added to `ConvertFrom-CanonicalJson`**
  for better cmdlet metadata (the only functional change in
  `0ebab36`).
- **Docs normalization**: `§` references rewritten as "section B.*";
  several em-dashes / bullets normalized in docblocks and help text.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r10.0` ->
  `update-wsi-2026.05.28-r10.1`. `$Script:ScriptTag`:
  `step2b4-version-independent-canonical-json`.

### r10.0 - version-independent canonical JSON

Introduces a hand-rolled canonical JSON serializer and parser so
that config / cache / Layer 2 files are byte-stable across
PowerShell 5.1, PowerShell 7.x, and Python.

- **`ConvertTo-CanonicalJson` / `ConvertFrom-CanonicalJson` added**
  (plus internal writer / reader helpers). These avoid the
  cross-version differences of the built-in `ConvertTo-Json` /
  `ConvertFrom-Json` (date handling, formatting, ordering).
- **All `ConvertFrom-Json` callers replaced** with
  `ConvertFrom-CanonicalJson` throughout the script.
- **SPEC.md** documents the new parser, serializer, and the
  version-independence / date-handling / formatting rationale.
- `$Script:ScriptVersion`: `update-wsi-2026.05.28-r09.0` ->
  `update-wsi-2026.05.28-r10.0`. `$Script:ScriptTag`:
  `step2b4-version-independent-canonical-json`.

### r09.0 Step 2b3 - real-data-driven parser correction

This change corrects the Phase 2b1 parser and the Phase 2b2 Layer 1
writeback after the **first end-to-end run against a live
`wsusscn2.cab`** (2026-05-12 fetch, 641,849,140 bytes, 136,102
`<Update>` rows) on the Linux verification host. Phase 2b1 had been
authored and unit-tested against an *assumed* wsusscn2 structure that
diverged from reality in several material ways; every assumption is now
replaced with the empirically verified structure (SPEC §B.19.9.6) and
the whole pipeline is validated against the real cab.

This entry **supersedes** the structural claims in the Step 2b2 entry
below (per the AP-9 metadata-correction rule: corrections are recorded
as a new entry, not by rewriting the prior one). Stage chaining, the
A01→A04 soft-fail chain, and DryRun semantics from Step 2b2 are
unchanged and remain accurate.

#### Root cause

Phase 2b1's parser, fixtures, and tests were written without ever
parsing a real `wsusscn2.cab`. The synthetic fixture encoded a guessed
structure, so T12/T13 passed green while the parser produced
**zero usable data** against the real cab (0 file-locations, 0 payload
URLs, 0 KB-bearing in-scope updates). The AGENTS.md §4
ground-truth-extraction rule had not been applied to the external data
format.

#### Corrections (all verified against the live cab)

**Stage 3 (`ConvertFrom-WsusScnPackageXml`)** — rewritten to the real
structure:

| Assumed (Phase 2b1) | Real (verified) |
|---|---|
| `<KBArticleID>` element holds a KB number | No KB number exists anywhere in the Master XML; KB lives in the Catalog |
| Payload is `<Files><File Digest="…" />` | `<PayloadFiles><File Id="<digest>" />` (digest in `Id`) |
| `<BundledBy><RevisionId Id="…" />` | `<BundledBy><Revision Id="…" />` |
| `<SupersededBy><UpdateId Id="…" />` | `<SupersededBy><Revision Id="…" />` |
| `<FileLocation FileDigest="…"><Url>…</Url>` | `<FileLocation Id="<digest>" Url="…" />` |
| In-scope Product+Classification update carries the payload | The in-scope row is a *bundle* with no payload; payloads live on *leaf* rows that point up via `BundledBy` |

The corrected parser does one streaming pass that (a) collects in-scope
bundles, (b) builds a `bundleRevisionId → [payloadDigests]` roll-up by
walking every leaf's `BundledBy` + `PayloadFiles`, and (c) builds a
`digest → URL` map; a post-pass resolves each bundle's `payloadUrls`
from the leaves bundled under it. The positive child-element allowlist
(SPEC §B.19.8) is now `Categories, Category, Prerequisites, UpdateId,
SupersededBy, BundledBy, Revision, PayloadFiles, File`.

**Server 2025 Product GUID correction** (SPEC §B.19.9.7): the Server
2025 Product Category GUID was `ca006cfb-49eb-439b-880a-1312e1fc9713`,
whose newest SecurityUpdate bundle silently stalled at 2025-09-08. The
verified GUID carrying the current Server 2025 LCU (KB5087539,
2026-05-11) is `b256987d-4693-4c87-955d-dbb9341205eb`. It carries the
Server LCU but not the Windows 11 24H2 client LCU (KB5089549), so it is
server-specific. With the fix, all four OS families resolve their
2026-05-11 LCU (Server 2016 KB5087537, 2019 KB5087538, 2022 KB5087545,
2025 KB5087539).

**Stage 4 (`New-WsusScnDependencyDatabase`)** — `kbArticleIds` removed
(no KB in wsusscn2); `supersededByUpdateIds`/`bundledByRevisionIds`
replaced by `supersededByRevisionIds`; `payloadUrls` now come
pre-resolved from Stage 3; `_meta.stats` gains `leafUpdatesWithPayload`
and `payloadDigestsOrphaned`.

**`Get-WsusScnCabIfNeeded` call-site fix (A04 Stage 1)** — the Step 2b2
A04 wrapper called this with non-existent parameters
(`-CabPath`/`-StaleAfterDays`/`-ForceRefetch`). Corrected to the real
signature (`-WsusScnCabMeta`/`-WorkRoot`/`-LatestPatchTuesday`/
`-OverridePath`), mirroring the P06 ValidatePatchSet acquisition
pattern. A04 params are now `-OverridePath`/`-OutputPath`/
`-SkipLayer1Update`.

**Layer 1 (`Update-Layer1DependencyVerification`)** — KB-based fields
replaced with identity fields, since wsusscn2 has no KB:
`_DependencyVerifiedUpdateId`, `_DependencyVerifiedRevisionId`,
`_DependencyVerifiedCreationDate`, `_DependencyVerifiedAt`.

**Tests** — the T12 fixture builder was rewritten to the real
bundle/leaf structure (`PayloadFiles`, `BundledBy/Revision`,
`FileLocation Id/Url`, two-tier bundle↔leaf linkage). T12 reworked to
22 assertions on the new schema; T13 reworked to 15 assertions on the
UpdateId/RevisionId identity fields.

#### End-to-end verification (live cab, Linux host)

- Stage 1: 612 MB download OK (`downloadedNow=True`).
- Stage 2: 7-Zip two-step extraction OK (package.xml 113,842,356 bytes).
- Stage 3: 136,102 observed → 138 in-scope bundles → 110,749 leaves
  with payload → 97,051 file-locations → **0 orphaned digests**,
  **every in-scope bundle's payloadUrls resolved**. ≈ 4.5 min parse.
- Stage 4: Layer 2 JSON written (~198 KB).
- A04 whole-wrapper run: `A04 RefreshDependencyDatabase: completed
  successfully` (`returned: True`).
- Gates: psa 0/0/0, PSScriptAnalyzer 0, T2–T13 175→176 assertions all
  green, canonical-JSON format 26/26.

#### Files changed

- `Update-WindowsServerIso.ps1`: Stage 3 rewrite, Stage 4 reshape,
  Layer 1 rewrite, A04 Stage 1 call-site fix, Server 2025 GUID table +
  name-map correction, `$Script:ScriptTag` → `step2b3-real-data-parser-correction`.
- `tests/common/wsusscn2_fixture_builder.py`: full rewrite to real structure.
- `tests/wsusscn2_parser_test.py`, `tests/wsusscn2_layer1_test.py`: reworked assertions.
- `tests/fixtures/wsusscn2/{package.xml,expected-output.json}`: regenerated.
- `SPEC.md`: added §B.19.9.6 (verified structure) and §B.19.9.7 (Server 2025 GUID correction).

### r09.0 Step 2b2 - A04 wrapper implementation and Layer 1 integration

This change implements the Phase 2b2 lifecycle glue that turns the
parser pipeline (landed in Step 2b1) into a full Action: `-Action
RefreshDependencyDatabase` now chains Stages 1-4 end-to-end and
propagates the latest LCU KB and CreationDate per Server OS family
into the data/config-Server*.json baselines. `-Action
RefreshAllBaselines` automatically chains A04 as a soft-fail
downstream step, so the monthly refresh workflow gains
dependency-database freshness without any operator-facing change.

### What is in this commit

**Production code (`Update-WindowsServerIso.ps1`, +244 net lines)**:

| Site | Lines | Purpose |
|---|---:|---|
| L538-539 | 1 changed | `$Script:ScriptTag` bumped from `step2b1-parser-pipeline-and-fixture-tooling` to `step2b2-a04-wrapper-implementation-and-layer1-integration`. `$Script:ScriptVersion` unchanged. |
| L13012-13182 | replaced | `Invoke-AdminPhaseA04_RefreshDependencyDatabase` body, replacing the Step 2a `NotImplementedException` stub. New body executes Stage 1 (`Get-WsusScnCabIfNeeded`) → Stage 2 (`Invoke-WsusScnPackageXmlExtract`) → Stage 3 (`ConvertFrom-WsusScnPackageXml`) → Stage 4 (`New-WsusScnDependencyDatabase`) → Layer 1 writeback (`Update-Layer1DependencyVerification`). Caller-overridable `-CabPath`, `-OutputPath`, `-StaleAfterDays`, `-ForceRefetch`, `-SkipLayer1Update`. DryRun mode parses but skips the JSON and Layer 1 writebacks. Staging directory beneath `$Script:TempDir`; cleaned on success, preserved on failure for inspection. Soft-fail return: `$false` on any pipeline error, `$true` on success or DryRun completion. |
| L13184-13283 | +100 | `Update-Layer1DependencyVerification` (new helper). For each Server OS family in `$Script:WsusScnOsCategoryGuids`, finds the most-recent LCU-bearing in-scope Update and writes three advisory fields to `data/config-<OsKey>.json`: `_DependencyVerifiedKb`, `_DependencyVerifiedCreationDate`, `_DependencyVerifiedAt`. Idempotent (re-runs report `UnchangedCount` instead of `UpdatedCount` when values match). Uses `Save-ConfigWithBaseline` for atomic LF/UTF-8 writes. |
| L12602-12624 | +23 | `Invoke-AdminPhaseA01_RefreshAllBaselines` soft-fail chain into A04 immediately after `Show-RefreshAllBaselinesSummary`. A04 failure is reported via `Write-Warn` but does NOT mark A01 as failed (the per-OS config baselines are the primary A01 deliverable; the dependency database is downstream advisory data). |

**Design choices**:

- *A01 -> A04 is a chain, not a dependency*. A01 still completes
  successfully even if A04 fails. This protects the monthly refresh
  workflow against transient wsusscn2.cab CDN failures.
- *Layer 1 writeback writes only three advisory fields* per config.
  No structural keys are added; no existing keys are renamed.
  Downstream consumers that do not know about these fields ignore them
  (forward-compatible JSON).
- *DryRun is partial-execute, not full-skip*. A04 still acquires the
  cab and parses package.xml in DryRun so the run is informative; only
  the Layer 2 JSON write and Layer 1 config writeback are skipped.
  This matches the established convention for A01 / A02 / A03.
- *Staging is workspace-local*. The cab extraction stages into
  `$Script:TempDir`-relative paths rather than `[Path]::GetTempPath()`
  so the workspace policy (LogsDir / TempDir siblings) is preserved.
  On failure the staging is left in place for the operator to inspect.

**What is intentionally NOT yet wired up** (Phase 2c scope):

- The SSU/LCU pre-flight gate that *consumes* the `_DependencyVerified*`
  fields (SPEC §B.19.5) is not yet implemented. The fields are now
  written but no Phase reads them yet.
- The dependency-closure graph walk (SPEC §B.19.14, Phase 2c) that
  expands the Layer 2 JSON into a topologically-sorted patch order is
  out of scope here.

**New offline test (`tests/wsusscn2_layer1_test.py`, T13, ~190 lines)**:

14 assertions exercising:

- Stub-config setup pre-flight: 4 minimal `config-Server*.json` files
  created in a temp `data/` directory
- Run 1 (first invocation): `UpdatedCount=2` (Server 2022 + Server 2025),
  `UnchangedCount=0`, `MissingCount=2` (Server 2016 + Server 2019,
  which have no in-scope LCU in the T12 fixture)
- Field-level correctness on Server 2022: `_DependencyVerifiedKb=KB5099001`,
  `_DependencyVerifiedCreationDate=2026-04-15T10:00:00Z`,
  `_DependencyVerifiedAt` present and ISO-8601 formatted
- Field-level correctness on Server 2025: `_DependencyVerifiedKb=KB5099003`,
  `_DependencyVerifiedCreationDate=2026-05-10T10:00:00Z`
- Missing-OS hygiene: Server 2016 config has no `_DependencyVerifiedKb`
  field added (no spurious writeback)
- Existing-field preservation: the pre-existing `OsKey` field survives
  the writeback intact
- Run 2 (idempotent re-invocation): `UpdatedCount=0`, `UnchangedCount=2`,
  `MissingCount=2`

The test runs against a tempdir-cloned `data/` so the repository's real
configs are never touched. Stage 1 (`Get-WsusScnCabIfNeeded`) is
*not* exercised here; it is covered by the live monthly refresh CI
and the synthetic-test-mode end-to-end run.

**Documentation updates**:

- `SPEC.md` §B.19.9.5 *A04 wrapper lifecycle (Phase 2b2 binding)*
  added covering the function signature, parameter semantics, A01
  chaining model, and Layer 1 writeback contract.
- `SPEC.md` §B.19.15.3 updated to reflect that A04 is now implemented
  (was: pointer to Step 2b stub).
- `tests/README.md`: Tool inventory + Quick start + File layout updated
  with T13 row.
- `README.md` / `README.ja.md`: T12 -> T13 in the Self-verification
  tools count, bilingual lock-step preserved.
- `TESTING.md` §0 status table updated with T13 row and A04 status
  changed from "stub" to "implemented".

### Quality gate

| Gate | Result |
|---|---|
| `psa.py` (PSA full rule set) | 0 errors, 0 warnings, 0 info |
| `PSScriptAnalyzer` (Settings.psd1) | 0 findings |
| Unit tests T2-T12 (no regression) | 160/160 passed (138+22) |
| **T13 (new)** | **14/14 passed** |
| Canonical JSON format gate | 26/26 passed (no JSON additions) |
| Bilingual lock-step (README.md / .ja.md / TESTING.md) | preserved |

### r09.0 Step 2b1 - wsusscn2 parser pipeline and fixture tooling

This change implements the Phase 2b1 parser pipeline (Stages 2-4 of the
wsusscn2.cab dependency-database production line) inside
`Update-WindowsServerIso.ps1`, plus the offline T12 self-verification
suite that exercises the pipeline against a small committed fixture.
The implementation builds on the GUID inventory and analyzer tooling
landed in the preceding Step 2b1 preparation commit (648880e).

**Prior-commit metadata correction (AP-9 follow-up)**: the
preparation-step CHANGELOG entry (commit 648880e) recorded
`tests/common/wsusscn2_analyzer.py` as `~370 lines`. The actual file
is 504 lines (verified by `wc -l`). The discrepancy was a CHANGELOG
self-reported value drift, not a code defect (md5 of the file matched
between the staged zip and the committed file). This commit does not
edit 648880e's CHANGELOG entry retroactively but records the
correction here, per AGENTS.md §4 ground-truth-extraction policy.

### What is in this commit

**Production code (`Update-WindowsServerIso.ps1`, +669 lines)**:

| Site | Lines | Purpose |
|---|---:|---|
| L538-539 | 1 changed | `$Script:ScriptTag` bumped from `step2a-followup-canonical-json-migration` to `step2b1-parser-pipeline-and-fixture-tooling`. `$Script:ScriptVersion` unchanged. |
| L569-630 | +62 | Three `$Script:WsusScn*` lookup tables: `WsusScnOsCategoryGuids` (4 Server LTSC Product GUIDs), `WsusScnCategoryGuidNameMap` (GUID -> human label for diagnostic output), `WsusScnUpdateClassificationGuids` (5 WSUS Classification GUIDs). Provenance documented inline pointing at research §5.7 / §6.4. |
| L7021-7117 | +97 | `Invoke-WsusScnPackageXmlExtract` (Stage 2). Two-step 7-Zip extraction (wsusscn2.cab -> package.cab -> package.xml). Uses existing `Get-SevenZipPath` / `Install-SevenZipFallback` from Step 2a. Caller owns the staging directory lifecycle. |
| L7118-7454 | +337 | `ConvertFrom-WsusScnPackageXml` (Stage 3). Streaming `XmlReader`-based parser with a positive child-element allowlist (`KBArticleID`, `Categories`, `Category`, `Prerequisites`, `UpdateId`, `RevisionId`, `SupersededBy`, `BundledBy`, `Files`, `File`) that physically excludes Microsoft prose (`<Title>`/`<Description>`/`<MoreInfoUrl>` are never read; SPEC §B.19.8 hard rule enforcement). Applies the scope filter (Product GUID AND Classification GUID AND 24-month recency, all caller-overridable). Returns `[pscustomobject]` with `Updates` / `FileLocations` / `Stats`. |
| L7455-7587 | +133 | `New-WsusScnDependencyDatabase` (Stage 4). Joins payload URLs from `FileLocations` into each Update's record, attaches provenance metadata (script version/tag, source-cab SHA-256 and size, scope inputs, observation stats), writes via `Save-CanonicalJsonFile` at SPEC §B.23 canonical JSON (depth=32). |

What is intentionally NOT yet wired up: the `Invoke-AdminPhaseA04_RefreshDependencyDatabase`
wrapper still throws `NotImplementedException` (its Phase 2b2 lifecycle
glue would chain Stage 1 → 2 → 3 → 4 with cache-management policy). The
A01.0 `RefreshAllBaselines` action does not yet call the parser
either. Both of those are Phase 2b2 scope.

**New offline test (`tests/wsusscn2_parser_test.py`, T12, ~220 lines)**:

22 assertions exercising:

- Fixture pre-flight: package.xml exists, contains zero Microsoft-prose tags (`<Title`, `<Description`, `<MoreInfoUrl`, `<Summary`, `<DefaultPropertiesLanguage`); expected-output.json structurally valid
- Stage 3 + Stage 4 happy-path: invokes pwsh, dot-sources the script, runs the pipeline against the fixture, parses the produced JSON
- Stats parity: `updatesObserved=6 / updatesInScope=3 / bundlesObserved=2 / categoryUpdates=1 / fileLocationsRetained=2 / payloadUrlsMissing=1`
- Scope-filter admit/reject: Server 2022 LTSC bundle + child admitted, Server 2025 LTSC bundle admitted, Office out-of-scope rejected (Product mismatch), 2022-vintage Server 2019 update rejected (recency cutoff), Category-Update record rejected (no Product/Classification refs in its own Categories block)
- Field-level correctness: `isBundle`, `kbArticleIds`, `productGuids` on the Server 2022 bundle
- Payload-URL join: child update's `payloadUrls` resolved via the FileLocations table; orphan digest (in `<Files>` but not in `<FileLocations>`) correctly omitted from the output
- Microsoft-prose absence in parser output (case-insensitive search for `"title"`, `"description"`, `"moreinfourl"` fields)
- Full structural compare against `expected-output.json` (env-stripped: `scriptVersion`, `scriptTag`, `generatedAt`, `sourceCab`)

Runs offline; no network access; no 7-Zip invocation; no real
wsusscn2.cab download. Stage 2 (`Invoke-WsusScnPackageXmlExtract`) is
platform-coupled (needs 7-Zip and Windows file layout) so it is
exercised only by the live monthly refresh CI workflow, not by T12.

**New fixture builder (`tests/common/wsusscn2_fixture_builder.py`, ~365 lines)**:

CLI + library Python helper that emits both `package.xml` and
`expected-output.json` into `tests/fixtures/wsusscn2/`. The fixture is
deliberately constructed (not derived from any real wsusscn2.cab) so
each Update tests a specific control-flow path in the parser; the GUID
namespace `f0000001-...` is reserved so the fixture cannot collide
with real wsusscn2 records.

**New committed fixtures (`tests/fixtures/wsusscn2/`)**:

| File | Size | Role |
|---|---:|---|
| `package.xml` | 3,312 bytes | Minimal Master XML covering 6 Updates (2 bundles, 1 child, 1 Category, 1 out-of-scope, 1 old in-scope) and 2 FileLocations |
| `expected-output.json` | 3,347 bytes | Canonical-JSON serialization of the expected parser output, env-stripped fields are placeholders |

Both files are deterministically regenerated by
`python3 -m tests.common.wsusscn2_fixture_builder` and `format gate`
verifies the JSON is canonical.

**Documentation updates**:

- `tests/README.md`: added T12 row to the Tool inventory table and a
  T12 row to the Quick start block. File layout updated to list
  `fixtures/wsusscn2/` and `wsusscn2_parser_test.py`.
- `README.md` / `README.ja.md`: T11 -> T12 in the Self-verification
  tools count, bilingual lock-step preserved.
- `TESTING.md`: §0 status table updated with T12 row.

**SPEC.md updates**:

- §B.19.9.4 *Implementation notes for the parser pipeline* added with:
  function signatures of Stages 2-4, the in-memory schema returned by
  Stage 3, the Layer 2 JSON schema written by Stage 4, the
  scope-filter rule, the allowlist enforcement of SPEC §B.19.8, and
  pointers to research §2.4.1 / §5.7 / §6.4.

### Quality gate

| Gate | Result |
|---|---|
| `psa.py` (PSA full rule set) | 0 errors, 0 warnings, 0 info |
| `PSScriptAnalyzer` (Settings.psd1) | 0 findings |
| Unit tests T2-T11 (no regression) | 138/138 passed (13+10+13+16+20+18+22+26) |
| **T12 (new)** | **22/22 passed** |
| Canonical JSON format gate | 26 passed (25 prior + 1 new `expected-output.json`) |
| Bilingual lock-step (README.md / .ja.md / TESTING.md) | preserved |

### r09.0 Step 2b1 preparation - WSUS Product Category GUID investigation and research documentation

This change is a **preparation step** for the Phase 2b1 parser pipeline
implementation. It does not modify `Update-WindowsServerIso.ps1` itself
(no production code change); instead it finalises the **WSUS Product
Category GUID inventory** that the upcoming Phase 2b1 scope filter
(`$Script:WsusScnOsCategoryGuids` and `$Script:WsusScnUpdateClassificationGuids`,
SPEC §B.19.7) will rely on. The investigation and its findings are
captured in the `research/` portable-knowledge tree so the GUID
inventory is auditable independently of the script body.

The motivation: SPEC §B.19.7 declares that the scope filter admits only
"SSU, LCU, .NET CU, or Dynamic Update" updates targeting Windows Server
2016 / 2019 / 2022 / 2025, judged by `Categories.Product` and
`Categories.UpdateClassification` GUID matching. Microsoft does not
publish a complete official table of Product GUIDs for the Server LTSC
family (the Classification side does have one). Phase 2b1 cannot be
authored safely without those values, so this step closes the gap with
a documented reverse-lookup methodology and a finalised reference table.

### What is in this commit

**Research documentation (bilingual, `research/windows-servicing/`)**:

Three new subsections added to the existing `windows-server-iso-update-mechanics.{ja,en}.md`
(675 → 824 lines on each side, bilingual lock-step preserved):

| § | Title (ja) | Role |
|:---|:---|:---|
| 2.4.1 | Category 階層の package.xml 内表現 | Methodology: how the WSUS Product hierarchy is implicitly embedded in `wsusscn2.cab`'s Master XML as `<Update>` elements with `DeploymentAction="Evaluate"` AND `IsSoftware="false"` markers; observed counts (4,199 Category Updates total, 154 directly under Windows ProductFamily) |
| 5.7 | scope filter の根拠となる Product GUID 一覧 | Canonical reference table: 4 Server LTSC Product GUIDs + 5 UpdateClassification GUIDs observed in the wsusscn2 fetched 2026-05-12; mapping of SSU / LCU / .NET CU / Dynamic Update to Classification |
| 6.4 | WSUS Product Category GUIDs と Server LTSC 系列の対応 | The naming-vs-GUID duality: display-name renames (§6.1, "Microsoft server operating system-21H2/24H2") do not affect GUIDs; canonical resolution paths (live WSUS, WUA API, wsusscn2 reverse-lookup, OSS cross-reference, Microsoft Learn) |

The same three subsections are added to the `.en.md` mirror with
matching structure and line numbers (824 lines, 0% line-count diff
between the bilingual pair).

**New test-infrastructure helper (`tests/common/`)**:

| File | Lines | Role |
|:---|---:|:---|
| `tests/common/wsusscn2_analyzer.py` | ~370 | Schema-discovery helper for `wsusscn2.cab`'s `package.xml`. Provides two-step 7-Zip extraction (subprocess-based, mirrors but does not couple to the production Stage 2 helper), tag-count census (parity with Phase 5 v4 observations), Category GUID frequency by Type, streaming `<Update>` / `<FileLocation>` iterators via `ElementTree.iterparse` (memory-safe on the 108 MB Master XML), Microsoft-prose absence check (SPEC §B.19.8 hard rule), and a CLI for manual exploration (`extract` / `summary` / `guids` / `prose` subcommands). Standard-library-only, pip-install-free, matches the existing `tests/common/` convention. Not yet wired to a test entry point — that lands in Phase 2b1 (T12). |

**Documentation updates (`tests/README.md`)**:

- File layout updated to include `common/canonical_json.py` (which
  Phase B1 introduced but never recorded in the layout block) and
  `common/wsusscn2_analyzer.py` (this commit). The Tool inventory
  table is unchanged because `wsusscn2_analyzer.py` is investigation
  infrastructure, not a T-numbered self-verification tool.

**Finalised GUID inventory (the central deliverable, recorded in `research/.../windows-server-iso-update-mechanics.ja.md` §5.7 as canonical)**:

Server LTSC Product GUIDs (scope filter targets):

| Server version | WSUS display name | Product GUID |
|:---|:---|:---|
| Server 2016 | Windows Server 2016 | `569e8e8f-c6cd-42c8-92a3-efbb20a0f6f5` |
| Server 2019 | Windows Server 2019 | `f702a48c-919b-45d6-9aef-ca4248d50397` |
| Server 2022 LTSC | Microsoft server operating system-21H2 | `71718f13-7324-4b0f-8f9e-2ca9dc978e53` |
| Server 2025 LTSC | Microsoft Server Operating System-24H2 | `ca006cfb-49eb-439b-880a-1312e1fc9713` |

> **Note (corrected later):** the Server 2025 GUID recorded here
> (`ca006cfb-...`) was found in Step 2b3 to be a stale 24H2-era
> category. The verified value is `b256987d-4693-4c87-955d-dbb9341205eb`.
> See the "Step 2b3" entry above and SPEC §B.19.9.7.

Server 2022 / 2025 GUIDs were finalised in this session via the
Category-hierarchy reverse-lookup methodology described in §2.4.1
(Category Update `CreationDate` matched with payload-URL build numbers:
build 26100 SSU → Server 2025 LTSC, ndp481 marker → Server 2022 LTSC).
Server 2016 / 2019 GUIDs are additionally cross-referenced against
`ansible/ansible` Issue 60785, `dsccommunity/UpdateServicesDsc` Issue
65, and the WSUSOffline forum.

### What is NOT in this commit (preserved for Phase 2b1 proper)

The production code (`Update-WindowsServerIso.ps1`) is **unchanged**:

- `$Script:WsusScnOsCategoryGuids` / `$Script:WsusScnCategoryGuidNameMap` / `$Script:WsusScnUpdateClassificationGuids` script-scope tables: not yet added (Phase 2b1 §1.3)
- `Invoke-WsusScnPackageXmlExtract` (Stage 2): not yet added (Phase 2b1 §1.4.1)
- `ConvertFrom-WsusScnPackageXml` (Stage 3): not yet added (Phase 2b1 §1.4.2)
- `New-WsusScnDependencyDatabase` (Stage 4): not yet added (Phase 2b1 §1.4.3)
- `tests/common/wsusscn2_fixture_builder.py`: not yet added (Phase 2b1 §1.2.2)
- `tests/wsusscn2_parser_test.py` (T12): not yet added (Phase 2b1 §1.5)
- `SPEC.md` §B.19.9.4 Implementation Notes: not yet added (Phase 2b1 §1.6.1)
- `ScriptVersion` / `ScriptTag`: unchanged (`update-wsi-2026.05.28-r09.0` /
  `step2a-followup-canonical-json-migration`); the next Phase 2b1
  commit will bump `ScriptTag` to `step2b1-parser-pipeline-and-fixture-tooling`.

The A04 wrapper (`Invoke-AdminPhaseA04_RefreshDependencyDatabase`)
keeps its `NotImplementedException` stub from Step 2a — its implementation
is scope of Phase 2b2, not Phase 2b1.

### Quality gate

This commit does not change PowerShell code, so the post-flight gates
that apply are:

| Gate | Result |
|:---|:---|
| `psa.py` (no PS change → no re-run needed; verified clean at baseline) | 0 / 0 / 0 |
| `PSScriptAnalyzer` (same as above) | 0 findings |
| Unit tests T2-T11 (no PS change) | unchanged from baseline (13/10/13/16/20/18/22/26) |
| Canonical JSON format gate (`tests/canonical_json_format_check.py`) | 25 passed (no new committed JSON files in this commit) |
| `tests/common/wsusscn2_analyzer.py` import smoke (Python) | PASS (`python3 -c "from tests.common import wsusscn2_analyzer"` clean) |
| Bilingual lock-step (`research/.../windows-server-iso-update-mechanics.{ja,en}.md`) | H2=13, H3=35, H4=4, 824 lines on each side (0.0% diff) |

### r09.0 Step 2a followup (Phase B2) - JSON canonical migration and format gate

This change applies the canonical JSON format declared in Phase B1
(SPEC Part B.23) to all 25 pre-existing JSON files in this subproject
and adds the Part C quality gate (§C.3.4) that prevents regression.
The change is large in line count but mechanical: no semantic content
is changed, only the formatter.

### What is in this commit

**File reformatting (25 files, byte-level mechanical change)**:

| Directory | File count | Source format | Net size delta |
|---|---:|---|---:|
| `data/` | 10 | PS 5.1 4-space, `":  "` separator, variable-width value alignment | **-414 KB** (-49% on average; the wins come from removing 53-space leading whitespace per array element) |
| `tests/fixtures/` | 10 | Python 2-space already (mostly canonical-compatible) | +537 bytes (one hand-formatted file `release_info_resolver/scenarios.json` had single-line short objects that canonicalise to multi-line) |
| `tests/snapshots/` | 5 | Python 2-space already | 0 bytes (already canonical-compatible) |

The `data/` size delta is the most visible: `cache-dotnet-cu.json`
267 KB → 110 KB, `cache-release-info.json` 402 KB → 216 KB. The
deletion is whitespace, not data; the JSON parse output of each file
before and after is structurally identical (verified by parse-then-compare
during the migration run).

**Source code changes (`Update-WindowsServerIso.ps1`, 12 sites)**:

The 12 `ConvertTo-Json` call sites that wrote to disk were replaced
with `Save-CanonicalJsonFile` (the SPEC §B.23.3 reference writer):

| Site | Previous pattern | Function |
|---|---|---|
| L3236 | `($x \| ConvertTo-Json -Depth 32) -replace ... + manual newline + WriteAllBytes` | `Save-OsConfig` |
| L3535 | same pattern, -Depth 8 | `Invoke-ReleaseInfoFetch` (raw meta) |
| L3860 | same pattern, -Depth 32 | `Update-ReleaseInfoCache` |
| L4366 | same pattern, -Depth 12 | `Invoke-DotNetCuFetch` (raw aggregate) |
| L4433 | same pattern, -Depth 32 | `Update-DotNetCuCache` |
| L4589 | same pattern, -Depth 12 | `Set-DynamicUpdateCachePersistFunc` |
| L10095 | `WriteAllText` + `-replace` + manual `+ "\n"` | `Save-ValidationSummary` |
| L10136 | same | `Save-WsusScnScanRaw` |
| L10172 | same | `Save-DependencyGraph` |
| L11225 | `ConvertTo-Json \| Set-Content -Encoding UTF8 -Force` | `Pca2023OnlyMode` (pcaDir) |
| L12006 | `Set-Content -NoNewline + Add-Content "\n"` | `Invoke-AdminPhaseA02_DumpFieldClassification` |
| L12879 | `ConvertTo-Json \| Set-Content -Encoding UTF8 -Force` | `Pca2023OnlyMode` (scratch) |

The 8 `-Compress` call sites (debug trace, HTTP body, TestHarness
protocol, before/after diff logging) and the 1 clone-idiom site
(`ConvertTo-Json \| ConvertFrom-Json` for deep copy) were left as
raw `ConvertTo-Json` because they intentionally produce single-line
or non-canonical output that the SPEC Part B.23 rules do not cover.
The debug trace Export at L1540 also writes UTF-8 **with BOM** by
design (so a Japanese ConsoleHost can read it back); this is
incompatible with canonical (no-BOM) and is correctly left alone.

ScriptVersion stays `update-wsi-2026.05.28-r09.0`; ScriptTag changes
from `step2a-followup-canonical-json-helpers` to
`step2a-followup-canonical-json-migration`.

**New Part C quality gate**:

- `tests/canonical_json_format_check.py` (~140 lines, new): walks
  `data/`, `tests/fixtures/`, and `tests/snapshots/`; re-serialises
  every `*.json` through `canonical_json_dumps`; fails the gate if any
  file's bytes diverge. Useful diagnostic on failure: shows first
  differing byte offset with surrounding context, plus the remediation
  hint pointing at `Save-CanonicalJsonFile` / `save_canonical_json_file`.

**SPEC.md updates**:

- §B.23.6 rewritten: removed the "migration window" framing; the
  invariants now read as steady-state rules. The explicit out-of-scope
  list (`Workspace_UpdateWsi/`, `-Compress` debug traces,
  `.psa.config.json`) is recorded normatively so future LLM agents and
  human reviewers do not accidentally widen the scope.
- §C.3.4 added: format-compliance gate that consumes the new
  `tests/canonical_json_format_check.py`.

**`tests/README.md`**: T11 entry already present; added a row for the
new format check script in the Tool inventory table and a line in the
Quick start block.

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (12,987 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 / 0 / 0
- `PSScriptAnalyzer` with project settings: 0 findings
- `pwsh -ParseFile`: Parse OK
- T2 (catalog_fixture_test): 13 passed / 0 failed
- T3 (powershell_harness): 10 passed / 0 failed
- T6 (release_info_parser_test): 13 passed / 0 failed
- T7 (dotnet_cu_parser_test): 16 passed / 0 failed
- T8 (dynamic_update_cache_test): 20 passed / 0 failed
- T9 (catalog_title_tokens_test): 18 passed / 0 failed
- T10 (release_info_resolver_test): 22 passed / 0 failed
- T11 (canonical_json_test): 26 passed / 0 failed
- **canonical_json_format_check (Part C gate, NEW): 25 passed / 0 failed**

### Verification of the structural equivalence

Each of the 25 reformatted files was parsed before and after the
conversion and the resulting Python object tree was compared. All 25
files parsed equal-after-equal-before, confirming the change is
formatter-only (no semantic shift).

### Cross-references

- SPEC.md §B.23 (the canonical format, declared in Phase B1; no
  rule changes in this commit, only the §B.23.6 migration text)
- SPEC.md §C.3.4 (the new format gate)
- AGENTS.md §2 sibling-isolation policy: this change is still scoped
  strictly to `scripts/powershell/update-windows-server-iso/`. No file
  in any other subproject is touched.
- AGENTS.md §9 AP-8 (downstream propagation): the gate, the SPEC
  amendments, the test README row, the source code replacements, and
  the file reformatting all ship in this single commit.

### r09.0 Step 2a followup - JSON Canonical Serialization helpers and SPEC Part B.23

This change adds two PowerShell helpers, a Python reference module, a
SPEC Part B.23 normative section, and a new offline regression test
(T11) that together establish a byte-level parity contract between
Linux PowerShell 7.x and Linux Python 3.10+ for every JSON file under
`data/` and `tests/fixtures/`. **No existing JSON files are migrated
in this commit**; the format check itself ships now, and the
mechanical migration of the 25 existing JSON files is the next step
(see "What is NOT in this commit" below).

The motivation is the format drift discovered during r09.0 Step 2a:
the `data/config-Server*.json` files are in a PowerShell 5.1
`ConvertTo-Json` format (4-space indent, `":  "` key/value separator,
variable-width value alignment) that PowerShell 7.x on Linux cannot
reproduce. Any edit to a `data/*.json` file from a Linux runtime
therefore generates a whole-file reformat in the git diff, drowning
the semantic change in noise. The new helpers fix this by declaring
a single canonical format that PS 7 and Python 3 can both emit
byte-for-byte.

### What is in this commit

- **`SPEC.md` Part B.23** (~200 lines, new):
  - §B.23.1 Motivation (format drift identification)
  - §B.23.2 The 10 normative format rules
  - §B.23.3 PowerShell reference implementation (function signatures
    and caller obligations)
  - §B.23.4 Python reference implementation (function signatures and
    caller obligations)
  - §B.23.5 Byte-level parity contract (the normative cross-runtime
    guarantee)
  - §B.23.6 Migration policy from legacy formats

- **`Update-WindowsServerIso.ps1`** (+130 lines, new section
  immediately after the 7-Zip helper block):
  - `ConvertTo-CanonicalJson` — pipeline-friendly wrapper over
    `ConvertTo-Json -Depth $Depth` with three corrections for byte
    parity with Python: CRLF→LF normalisation, scientific-notation
    `E`→`e` lowering, and a trailing-newline policy switch
  - `Save-CanonicalJsonFile` — atomic-ish file writer that uses
    `[System.IO.File]::WriteAllBytes` with a no-BOM UTF-8 encoder so
    LFs survive without platform translation
  - ScriptVersion remains `r09.0`; ScriptTag changes from
    `step2a-sevenzip-port-and-a04-stub` to
    `step2a-followup-canonical-json-helpers`

- **`tests/common/canonical_json.py`** (~170 lines, new):
  - `canonical_json_dumps` — Python reference implementation
  - `save_canonical_json_file` — Python file writer
  - `_assert_depth` — pre-serialisation depth check to give the same
    error class as the PowerShell `-Depth` over-limit case

- **`tests/canonical_json_test.py`** (T11, ~220 lines, new):
  - 26 assertions covering primitives (12), collections (8), Unicode
    (3), real-world `data/*.json` shapes (2), and file-level save (1)
  - Drives the PowerShell side through the existing `PSSession`
    TestHarness REPL (no new test infrastructure)

- **`tests/README.md`** (+2 lines):
  - T11 row in the Tool Inventory table
  - T11 line in the Quick Start example block

### What is NOT in this commit

The following are scoped to the next change cycle (a Phase B2
follow-up), explicitly NOT shipped here so the format and helpers
can be reviewed in isolation:

- The 27 existing `ConvertTo-Json` call sites in
  `Update-WindowsServerIso.ps1` are not yet migrated to
  `ConvertTo-CanonicalJson`.
- The 25 existing JSON files under `data/` and `tests/fixtures/`
  are not yet reformatted to canonical. Their current formats
  (PS 5.1 4-space for `data/*.json`, Python 2-space for
  `tests/fixtures/*.json`) are documented in §B.23.6 as the
  "migration window" baseline.
- The Part C quality-gate format check
  (`tests/canonical_json_format_check.py`) that walks both
  directories and fails on any non-canonical file is described in
  §B.23.6 but not yet implemented; it lands in the same change
  cycle as the mechanical migration.

### Rationale for the split

Phase B1 (this commit) ships the contract and the tools so reviewers
can examine the format rules, the helper signatures, and the byte
parity test in isolation. Phase B2 (next) applies the contract
mechanically to the 25 existing files in one large but
straightforward diff. Bundling the two together would have produced
~1,500 lines of mixed contract change + mechanical reformat, defeating
reviewer focus.

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (13,009 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 / 0 / 0
- `PSScriptAnalyzer` with project settings: 0 findings
- `pwsh -ParseFile`: Parse OK
- T2 (catalog_fixture_test): 13 passed / 0 failed (unchanged baseline)
- T3 (powershell_harness): 10 passed / 0 failed (unchanged baseline)
- T6 (release_info_parser_test): 13 passed / 0 failed (unchanged baseline)
- **T11 (canonical_json_test, NEW): 26 passed / 0 failed**
- TestHarness smoke test: `ConvertTo-CanonicalJson` returns the
  expected JSON via the harness REPL

### Cross-references

- SPEC.md §B.23 (normative format rules and parity contract; new in
  this commit)
- AGENTS.md §2 (sibling-isolation policy: this change is scoped to
  the `update-windows-server-iso` subproject; promotion to a
  Layer 0/1 rule or to the canonical PowerShell SPEC for other
  PowerShell subprojects is intentionally NOT in scope here and
  will be proposed separately under operator approval)
- AGENTS.md §9 AP-3 (inheritance via copy-paste: future ports to
  other subprojects, if approved, should be tracked as verbatim
  copies of these two functions, not as independent rewrites)
- AGENTS.md §9 AP-7 (out-of-scope sibling modification: no files
  under `scripts/powershell/download-speakerdeck-oracle4engineer/`
  or any other sibling are touched by this commit)
- AGENTS.md §9 AP-8 (documentation-only updates without downstream
  propagation: SPEC §B.23 ships together with the helpers, T11, and
  tests/README.md row in this single commit)

### r09.0 Step 2a - 7-Zip helper port, A04 stub, and Server 2016 SSU dependency config fix

This Step 2a ships a **scope-limited code change** that lays the
foundation for the full Servicing Dependency Database parser shipping
in r09.0 Step 2b. Three concrete deliverables ride in this commit:

1. The three 7-Zip helper functions (`Get-SevenZipPath`,
   `Get-LatestSevenZipUrl`, `Install-SevenZipFallback`) are ported
   from the sister project Deploy-AMDChipsetDriverOnWindowsServer.ps1
   with the two unavoidable logger renames documented in SPEC
   §B.19.4.4. These are the CAB-extraction prerequisites for the
   Stage 2 parser function that lands in Step 2b.
2. A new `-Action RefreshDependencyDatabase` Action is registered:
   `param()` ValidateSet entry, `$Script:PhaseRegistry` A04 entry,
   `Get-PhaseListByAction` switch case, `$osLessActions` membership,
   and a wrapper function `Invoke-AdminPhaseA04_RefreshDependencyDatabase`
   that throws `NotImplementedException` with an operator-actionable
   message pointing at SPEC §B.19.15.3. The registration ships in
   Step 2a so the public API contract (param surface, phase listing)
   is atomic with respect to the parser implementation; Step 2b
   replaces the wrapper body without changing any of the public
   integration points.
3. `data/config-Server2016.json` is corrected for the r08.0 Step 4d
   finding (the diagnosis that closes the r08.0 cycle on this OS):
   - `KB5088064` (2026-05 SSU) added as a new NeutralPatches entry
     with `ApplyOrder=1` (placed before the LCU's ApplyOrder=3) and
     the new `_DependencyVerifiedSource: "manual-r09-step2a"` field
     to mark its provenance per SPEC §B.19.12.1.
   - `KB5087537` LCU's `IsCombined: true` is corrected to `false`
     (r08.0 Step 4d evidence: `addpkg.log` confirms standalone LCU,
     not Combined LCU+SSU as the field had stated).
   - `KB5087537` LCU's `RequiresKbIds: []` is populated with
     `["KB5088064"]`, declaring the SSU prerequisite that previously
     caused the HRESULT `0x800f0823` failure on Server 2016 Build runs.

The change set explicitly does **not** ship the parser pipeline
(SPEC §B.19.9), the Layer 2 JSON schema (SPEC §B.19.10), the
`Test-PatchDependencyClosureFromGraph` verifier (SPEC §B.19.13),
nor the P06 Stage 2 split (SPEC §B.19.14). Those four deliverables
are intentionally bundled into r09.0 Step 2b so the parser and its
consumer land together; shipping them piecewise would leave the
script in an "API present but does nothing" state.

### Rationale

Splitting r09.0 Step 2 into Step 2a (this commit) and Step 2b (next)
follows the implementation-size guidance derived during planning:
the full Step 2 scope (~1,300-1,900 lines of additions across parser,
tests, A04 implementation, P06 Stage 2 split) is too large for one
revision to land cleanly with the Self-Check Gates AGENTS.md §8
demands. Step 2a's 78-line + 50-line additions are individually
small, but each is a fully-tested, atomic deliverable that improves
the script's behaviour on Server 2016 immediately — even before
the parser arrives.

The Server 2016 config correction (item 3 above) closes the r08.0
Step 4d investigation on this OS: an operator running r08.0 had to
manually understand the 0x800f0823 error, read addpkg.log, and
hand-edit the config to add KB5088064. After Step 2a, the same
config arrives shipped-correct, and the LCU's IsCombined / RequiresKbIds
fields document the dependency for the next operator. The remaining
gap (auto-discovery of dependencies for newly-released LCUs) is what
Step 2b's parser closes.

### Changed files

- `Update-WindowsServerIso.ps1` (+128 lines)
  - L538-539: ScriptVersion `r08.0` → `r09.0`; ScriptTag
    `fix-subphase-patch-classification` → `step2a-sevenzip-port-and-a04-stub`
  - L243: `param()` ValidateSet adds `RefreshDependencyDatabase`
  - L392: `$osLessActions` adds `RefreshDependencyDatabase`
  - L588 (new): `$Script:PhaseRegistry` adds A04 entry
  - L6737-6816 (new): 7-Zip helpers section (3 functions + section banner)
  - L12247-12297 (new): `Invoke-AdminPhaseA04_RefreshDependencyDatabase` stub
  - L12274 (new): `Get-PhaseListByAction` switch adds `RefreshDependencyDatabase` case
  - L12293: `Show-PhaseList` Actions list adds `RefreshDependencyDatabase`
- `data/config-Server2016.json` (+22 lines)
  - NeutralPatches[0] (new): KB5088064 SSU entry
  - NeutralPatches[1] (existing, fields updated): KB5087537 IsCombined corrected,
    RequiresKbIds populated, `_DependencyVerifiedDate` / `_DependencyVerifiedSource`
    / `_Notes` fields added per SPEC §B.19.12.1
- `SPEC.md` (+27 lines)
  - §B.19.4.4 (new): Implementation notes for the Deploy-AMD port

### Quality gate

- `psa.py`: 0 errors / 0 warnings / 0 info (12,879 lines analysed)
- `psa.py --include PSA1004,PSA2012,PSA2013`: 0 errors / 0 warnings / 0 info
- `PSScriptAnalyzer` with project settings: 0 findings
- T2 (catalog_fixture_test): 13 passed / 0 failed
- T3 (powershell_harness): 10 passed / 0 failed
- T6 (release_info_parser_test): 13 passed / 0 failed
- `pwsh -ParseFile`: Parse OK
- `-Action ListPhases` smoke test: A04 / RefreshDependencyDatabase entry visible in phase registry and Actions list
- `-Action RefreshDependencyDatabase` smoke test: NotImplementedException raised with operator-actionable message naming SPEC §B.19.15.3 and listing pending Step 2b work

### Cross-references

- SPEC.md §B.19.4 (7-Zip strategy, including new §B.19.4.4 Implementation notes)
- SPEC.md §B.19.12.1 (NeutralPatches `_DependencyVerified*` fields)
- SPEC.md §B.19.15.3 (A04 RefreshDependencyDatabase action)
- AGENTS.md §9 AP-2 (registered-but-not-implemented avoidance: stub raises a
  clear NotImplementedException rather than silently no-op)
- AGENTS.md §9 AP-3 (inheritance via copy-paste: the Deploy-AMD port
  is documented as a verbatim copy with two unavoidable logger renames,
  not as new code disguised as a sibling pattern)
- AGENTS.md §9 AP-5 (no inline revision tags: the new function bodies
  carry no `r09:` / `r09.0+` markers; revision context lives in this
  CHANGELOG entry only)
- `research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md`
  §5.3 (SSU-LCU pairing problem, the failure mode this config fix
  prevents) and §7.2 (expand.exe self-overwrite, the reason 7-Zip
  is required)

### r09.0 Step 10 (docs-only) - docs/ retirement and knowledge promotion to `research/windows-servicing/`

This Step 10 ships a **docs-only** change: the entire contents of
`scripts/powershell/update-windows-server-iso/docs/` are promoted out
of the subproject and into the repository's top-level `research/`
category as a single bilingual reference article. **No code is
changed in this or the follow-up commit**. The technical knowledge
accumulated across r06.0 / r07.0 / r08.0 / r09.0 investigation
cycles — release-info Markdown source semantics, .NET CU release
notes, Microsoft Update Catalog naming quirks, `wsusscn2.cab` Master
XML structure, PCA2023 Secure Boot migration mechanics, install.wim
cross-version asymmetry, Servicing Stack dependency model, and
operational hazards (mojibake, expand.exe self-overwrite, signtool
exit-code-1, `List[object]+@()`) — has been synthesized into a
single research article suitable for any practitioner building
similar tooling, independent of this subproject's specific
implementation.

### Restructure summary

- **New article (this commit)**: `research/windows-servicing/`
  - `windows-server-iso-update-mechanics.en.md` (675 lines)
  - `windows-server-iso-update-mechanics.ja.md` (675 lines)
  - Bilingual lock-step: H2=13, H3=33 in both languages.
  - Body is fully generic: no references to `Update-WindowsServerIso.ps1`,
    phase numbers (P05–P13), revision tags (r07.0/r08.0/r09.0), or
    SPEC section identifiers. Provenance to this subproject is
    confined to Appendix C.
- **Follow-up commit will delete** the entire
  `scripts/powershell/update-windows-server-iso/docs/` directory
  (12 files, 4561 lines total: `README.md` + `history/` containing
  `dotnet-cu-report.md`, `dynamic-update-report.md`,
  `mojibake-investigation-note.md`, `r07.0-followups.md`,
  `r08.0-step1-server2016-pca2023-finding.md`,
  `r08.0-step2-installwim-symmetry-check.md`,
  `r08.0-step3-output-verification-and-build.md`,
  `r08.0-step4-findings-and-dependency-investigation.md`,
  `r09.0-step1-phase5-summary.md`, `release-info-readme.md`,
  `release-info-report.md`).

### Rationale

The `docs/` subdirectory had grown to mix two distinct kinds of
content: (a) revision-specific work logs ("what did we find in
r08.0 Step 2?") and (b) durable technical knowledge ("how does
Microsoft serve patch metadata via release-info Markdown?"). The
former has decreasing value over time and is better recovered via
git history; the latter is broadly useful to any Windows servicing
practitioner and was buried inside this subproject where external
readers could not find it. The promotion to `research/` makes the
durable knowledge discoverable to the wider reader base while
acknowledging that revision-specific debugging notes are not the
right artifact to maintain forever.

The choice of `research/` over `documents/` follows the top-level
category policy (`research/README.md`): the article is a "reading
notes synthesized from multiple sources" investigation, not a
specific recommendation/plan/design for a particular scenario.

### Cross-references

- New article: `research/windows-servicing/windows-server-iso-update-mechanics.{en,ja}.md`
- Top-level category guidance: `research/README.md`
- Subproject retains its own `SPEC.md` and `README.md` as the
  source-of-truth for tool-specific behaviour; the research article
  is a cross-cutting concern map, not a user manual.

### r09.0 Step 1 (Phase 6, SPEC-only) - SPEC.md restructure to Part A/B/C/D standard form + Servicing Dependency Database normative specification

This Step 1 Phase 6 ships a **SPEC-only** change: a comprehensive
rewrite of `SPEC.md` that restructures the previous nine-Part layout
(A through I) into the repository-standard four-Part layout (A, B, C,
D) with three appendices (E, F, G). **No code is changed in this
commit**. The implementation work (parser, layer 2 schema, P06
Stage 2 wiring) follows in subsequent r09.0 Steps per the rollout
plan in §B.19.19.1.

### Restructure summary

- **Part E (Roadmap) deprecated**: replaced by CHANGELOG +
  per-cycle followup files; remaining roadmap content moved to
  Appendix G.2.
- **Part F (Function Reuse Map) → Appendix E**: same content,
  Appendix scope.
- **Part G (Self-verification tools) → Part C.9**: merged into
  the Quality Gates Part where the suite conceptually belongs.
- **Part H (Reference Projects) → Appendix F**: slimmed and
  cross-referenced from README.
- **Part I (Servicing Dependency Database, r09.0+) → Part B.19**:
  integrated as a Script-Specific subsection per the Part B/Part I
  Q2 design decision; the layer-2 schema, parser pipeline, and
  P06 integration are now in their natural location alongside the
  other phase-related contracts.
- **B.14b (out-of-sequence) absorbed into §B.4.3**: the
  PatchBaseline schema fields are now part of the OS profile
  schema section.
- **B.23 (Phase 3 Architecture, 24-subsection narrative)
  condensed**: replaced by §B.22 in decision-record form
  (B.22.1–B.22.21). The historical narrative is preserved in
  CHANGELOG.

### New normative content (Part B.19)

§B.19 (Servicing Dependency Database) is fully rewritten to reflect
the Phase 5 PoC findings:

- **B.19.4 7-Zip strategy** (Phase 5 D1): explicit choice of 7-Zip
  over in-box `expand.exe` / `Shell.Application`, with three-helper
  function trio reused from `Deploy-AMDChipsetDriverOnWindowsServer.ps1`.
- **B.19.5 Dual-source structure** (Phase 5): explicit
  acknowledgement that update-relationship metadata is split between
  the Master XML and individual `package*.cab` fragments; r09.0
  consumes Master XML only, with the per-cab parse explicitly
  out of scope.
- **B.19.6 Master XML schema as observed** (Phase 5 v3/v4): the
  full observed schema with Bundle / Standalone / SupersededBy
  shapes, including the empirically-confirmed 14,059 SupersededBy
  occurrences and zero forward-direction tags.
- **B.19.7 / B.19.8 Scope filter + Microsoft-prose exclusion**:
  hard rules that bound layer 2 to ~2–5 MB and keep it free of
  Microsoft creative content.
- **B.19.9 Parser pipeline** (4-stage with XmlReader streaming,
  Phase 5 D3): peak working set < 50 MB vs. +536 MB for
  XmlDocument.Load.
- **B.19.10 Layer 2 JSON schema** (Phase 5 final): the canonical
  shape including `Variants[]` + `RevisionIndex` (for resolving
  `<SupersededBy>` references that use RevisionId integers, not
  UpdateId GUIDs).
- **B.19.13 Verification API**: `Test-PatchDependencyClosureFromGraph`
  signature and its complementary relationship to the existing
  mount-time `Test-PatchDependencyClosureOnMount`.
- **B.19.14 P06 ValidatePatchSet integration**: two-stage P06 with
  independent skip conditions for catalog freshness (Stage 1) and
  dependency closure (Stage 2).
- **B.19.15 Lifecycle**: new Action A04 `RefreshDependencyDatabase`
  plus a new A01.0 sub-phase inside RefreshAllBaselines.
- **B.19.16 Air-gapped operation**: `-OfflineCabPath` parameter
  for environments without CDN access.
- **B.19.18 Maintainer operations guide**: monthly refresh
  procedure and PR review checklist.

### New Lessons Learned (Part D.24-D.30)

Seven new entries codify meta-lessons from the r07.0/r08.0/r09.0
cycles:

- **D.24 Cognitive bias patterns** — Hypothesis lock-in, sampling
  treated as comprehensive, solution attraction. Four mitigations
  pre-committed as the Engineering Hygiene Quartet.
- **D.25 DISM mount-cache poisoning** — Root cause of the
  r07.0 Step 16/17 mojibake; mitigation is fresh WorkRoot per OS
  family.
- **D.26 `List[object]` of pscustomobject argument-type mismatch**
  — Root cause of the r08.0 Step 2 `Argument types do not match`
  failure; `.ToArray()` is the safe alternative.
- **D.27 Microsoft OS tool dependency avoidance** —
  `expand.exe -F:` brittleness; `Make2023BootableMedia.ps1` precedent
  for inheriting Microsoft logic without inheriting the
  implementation; 7-Zip choice for r09.0 wsusscn2 parser.
- **D.28 Sampling versus comprehensive search** — 2-3 element
  exemplar walks are not representative for low-base-rate
  phenomena. Exhaustive `Select-String` on a 108 MB file is
  always cheaper than being wrong.
- **D.29 Code bug versus configuration problem triage** — A
  one-question filter to apply at the top of every failure
  investigation, prompted by the r08.0 Step 4d near-miss.
- **D.30 Helper function unification** — `Get-PatchEntryType` as
  the response to the dual-field-name drift; sweeps are fragile,
  helpers are forever.

### New stable identifier conventions

- **Policy IDs** of the form `SPEC-WSI-NNN` parallel the
  `SPEC-CI-NNN` IDs in the repository-level SPEC. The Policy Index
  table at the top of SPEC.md maps each Policy ID to the section
  that defines it.
- **Section IDs** `B.N.M` and `D.NN` are formally declared
  stable: once assigned, never reused.
- **Normative / informative tagging**: every section is tagged
  explicitly so an LLM agent reading the SPEC knows which rules
  carry contractual obligation and which are background.

### Document scope and language

- This SPEC continues to be English-only per the repository
  Language Policy (root `README.md` "Language Policy").
- The file format remains UTF-8 / LF / no BOM per the Markdown
  contract in the root `README.md` "File Format Policy".
- File line count: 5,074 (old) → 3,935 (new); a 22% reduction
  achieved while adding ~1,000 lines of new normative content
  in §B.19 and ~700 lines of new D.24-D.30 lessons. The net
  reduction comes from condensing the legacy Part B.23 24-
  subsection narrative into decision-records and from removing
  the redundancy between Part F/G/H and other Parts.

### No code change

`Update-WindowsServerIso.ps1` is **unchanged** in this commit.
`$Script:ScriptVersion` and `$Script:ScriptTag` are unchanged. CI
quality gates (psa.py / PSScriptAnalyzer / T2/T3/T6) are unaffected
by this commit because the source file is not touched. The next
r09.0 Step will begin implementing the §B.19 specification; that
Step ships with the corresponding code changes and a fresh
ScriptVersion bump.


### r08.0 Step 4 series - cumulative code bug fixes + SPEC Part I (Servicing Dependency Database) specification

This Step 4 series spans three connected modes:

1. **Step 4a/4b/4c — Code bug fixes**: cumulative bug-fix work
   uncovered while running the first real `Build -Execute` against
   Server 2016 ja-jp EVAL ISO post r08.0 Step 3. Four distinct bugs
   were found across the PatchType handling, ReadOnly attribute,
   Transcript lifecycle, and Export-DebugTraceJson invocation paths.
   These fixes have been validated on Windows PowerShell 5.1 Desktop
   on Server 2025 and pass all quality gates, and have been
   committed separately as `84d840e` (Step 4a) and `df89c6f`
   (Step 4b/4c combined). Server 2016 Build -Execute itself
   remains blocked on the SSU prerequisite uncovered in Step 4d
   (see below).

2. **Step 4d — Servicing Stack dependency investigation**: after
   Step 4c, `Add-WindowsPackage` failed with
   `0x800f0823 CBS_E_NEW_SERVICING_STACK_REQUIRED`. Investigation
   established this is a configuration problem (missing KB5088064 SSU
   entry in `config-Server2016.json`), not a code bug. The investigation
   record is captured in
   `docs/history/r08.0-step4-findings-and-dependency-investigation.md`.

3. **SPEC Part I (Servicing Dependency Database)** — the design
   specification for resolving the class of failures uncovered in
   Step 4d. This commit ships the Part I spec only; implementation
   is deferred to r09.0.

`ScriptVersion`: `update-wsi-2026.05.27-r08.0` (unchanged, same day; spec-only revision)

**SPEC.md additions**.

- New **Part I — Servicing Dependency Database (r09.0+, normative)**
  added at the end of SPEC.md (~960 lines). Defines:
    - I.1: Goals — eliminate the "discover prerequisite failure at
      P07 mid-mount" anti-pattern; pull failure detection forward
      to P06 with Microsoft-authoritative data.
    - I.2: Three-layer architecture:
      - Layer 1 = `data/config-Server*.json` (per-OS summary embedded
        into `PatchBaseline.NeutralPatches[*]`, git-tracked).
      - Layer 2 = `data/wsusscn2-database.json` (aggregated facts-only
        extract from wsusscn2.cab, ~2-5 MB, git-tracked, NO Microsoft
        prose).
      - Layer 3 = `<WorkRoot>/cache/wsusscn2/` (raw ~1 GB
        `wsusscn2.cab`, gitignored).
    - I.3: Data source — CDN URL, monthly cadence, package.xml
      schema observations.
    - I.4: Lifecycle — `RefreshAllBaselines` extension + new
      `-Action RefreshDependencyDatabase` (touches only layer 3).
    - I.5: File layout, gitignore additions, audit-archive
      retention policy (rolling 6 months), layer 2 size monitoring
      target.
    - I.6: Extraction logic — L2c implementation tier, scope filter
      (Server 2016/2019/2022/2025 + SSU/LCU/.NET CU/DU, 24-month
      window), the strict Microsoft-prose exclusion rule, full JSON
      schema for `wsusscn2-database.json`.
    - I.7: Layer 1 integration — `RequiresKbIds`, `Supersedes`,
      `RequiresMinimumOsBuild`, `IsCombined` (auto-overwrite by
      tool), semi-automatic policy on KB add/remove.
    - I.8: New `Test-PatchDependencyClosureFromGraph` function spec
      (the P06-side complement to the existing P07-side
      `Test-PatchDependencyClosureOnMount` from B.13).
    - I.9: P06 ValidatePatchSet redesign — split into Stage 1
      (catalogue freshness, skippable via `-UseBaselineOnly` as
      today) and Stage 2 (dependency closure verification, runs even
      under `-UseBaselineOnly`, new `-SkipDependencyCheck` flag for
      explicit opt-out).
    - I.10: Air-gapped operation — committed layer 2 enables
      verification without network access; new `-OfflineCabPath`
      parameter for manually-supplied wsusscn2.cab regeneration.
    - I.11: New `_DependencyVerifiedDate` /
      `_DependencyVerifiedSource` fields (parallel to existing
      `_VerifiedDate` / `_VerifiedBy`; tool-managed vs human-managed
      provenance tracked as independent dimensions).
    - I.12: Maintainer monthly-refresh procedure, PR review
      checklist.
    - I.13: Rollout / backward compatibility — strict superset of
      r08.0 behaviour; missing layer 2 falls back gracefully to
      existing B.13 logic with WARN.
- Table of Contents updated to include the new Part I entry.
- Part E milestone M3's "Done (r02)" claim is now formally
  superseded by Part I; the Part I header explicitly notes the
  M3 entry was a placeholder claim that was never implemented
  beyond the schema slot. Part E itself remains as the roadmap
  table; M3 status is corrected in spirit by the new Part I,
  but no edit to the Part E table is made in this commit (Part E
  is retained as-is for historical traceability).

**Documentation additions**.

- New `docs/history/r08.0-step4-findings-and-dependency-investigation.md`
  (~435 lines). Captures:
    - The four code bugs found and fixed in Step 4a-c (ReadOnly
      attribute, PatchType field-name drift across 6 call sites,
      Export-DebugTraceJson parameter name, Transcript lifecycle).
    - The Step 4d investigation: addpkg.log analysis pinpointing
      `Package_for_RollupFix~31bf3856ad364e35~amd64~~14393.9140.1.19
      requires Servicing Stack v10.0.14393.7692 but current is
      v10.0.14393.693`; cross-reference against Microsoft Update
      Catalog establishing KB5088064 as the canonical SSU
      prerequisite for KB5087537; identification of the
      `IsCombined: true` misclaim in `config-Server2016.json` as
      a manual-config integrity failure.
    - The Part I design discussion record: all nine design
      decisions (lifecycle, three-layer structure, scope,
      placement, phase integration, plus six sub-decisions) and
      the reasoning behind each.
    - Lessons-learned section: "code bug vs configuration
      problem" early triage, helper-function unification to
      prevent logic drift, spec-first approach for compound
      problems.

**What this commit does NOT change**.

- `Update-WindowsServerIso.ps1` is unchanged in this specific
  commit. The Step 4a/4b/4c code fixes were committed
  independently to `main` as `84d840e` and `df89c6f` prior to
  this spec-only revision.
- `config-Server*.json` files are unchanged. The `IsCombined:
  true` misclaim on KB5087537 is documented in the findings doc
  but not yet corrected, pending the decision above.
- No tests changed (Part I is spec-only; tests will be added
  during r09.0 implementation).

**Quality gates** (SPEC.md / docs only changes).

- Markdown files validate cleanly.
- No PowerShell file changes in this revision; psa.py / PSScript­
  Analyzer / T2/T3/T6 status carries forward unchanged from
  r08.0 Step 3.

---

### r08.0 Step 3 - Test-OutputIsoPca2023Readiness function and P10/P12/P13 integration

This release adds the output-side post-build verification function
that was designed during r08.0 Step 2 but deferred when a PowerShell
type-inference issue could not be resolved within the prior session
budget. Step 3 root-causes the issue (a `List[object]` of
`pscustomobject` elements cannot be materialised with the `@()`
operator under PowerShell 7.4.x; `.ToArray()` is the safe
alternative) and ships the function with full integration into
the existing PCA2023 readiness phases. This closes the highest
priority item raised in SPEC.md §B.24.6.

`ScriptVersion`: `update-wsi-2026.05.27-r08.0` (unchanged, same day)
`ScriptTag`    : `promote-enable-flags-for-build-phases` -> `add-output-iso-pca2023-verification`

**New function**.

- `Test-OutputIsoPca2023Readiness` (~290 lines) verifies an extracted
  OUTPUT-ISO directory against the five conversion targets documented
  in §B.18 (the Microsoft `Make2023BootableMedia.ps1` v1.4
  `Copy-2023BootBins` table):
    - Target #1 (`\efi\boot\bootx64.efi` or `bootaa64.efi`):
      PCA2023 -> Pass; PCA2011 or missing -> Fail
    - Target #2 (`\bootmgr.efi`): any signer or missing -> PassWithNotes
      (encodes the Microsoft-design PCA2011 status from L876-L884)
    - Target #3 (`\efi\microsoft\boot\efisys_ex.bin`):
      present -> Pass; missing -> Fail
    - Target #4 (`\efi\microsoft\boot\fonts\*.ttf`):
      present -> Pass; missing or empty -> Warning
    - Target #5 (`\EFI\Microsoft\Boot\boot.stl`):
      present -> Pass; missing -> PassWithNotes
- OverallStatus aggregation: Fail > Warning > PassWithNotes > Pass.
- The `Reasons[]` array always appends a SCOPE clarifier identifying
  that the in-tree check verifies file presence + signer chain only,
  and that an actual boot test on PCA2011-revoked firmware (hardware
  or Hyper-V Gen2 VM with custom Secure Boot template) is required
  before production deployment.
- The function is strictly READ-ONLY: no DISM mounts, no registry
  hive loads, no signtool invocations. Only `Test-Path` and
  `Get-AuthenticodeSignature` against the extracted media tree.

**Existing function extensions**.

- `Get-Pca2023ReadinessSnapshot`: added `OutputCheck = $null` to both
  return-path `[pscustomobject]@{...}` initialisers. Downstream code
  populates this field via direct assignment after running the new
  verification function.
- `Show-Pca2023ReadinessSnapshot`: new optional `-OutputCheck`
  parameter. In Compact mode adds a single one-line indicator
  ("Output ISO check : overall=Pass     targets=5 (Pass=3 ...)").
  In detail mode adds a new block listing each target's Status,
  expected/actual signer, and Notes.
- `Format-Pca2023ReadinessForReport`: new optional `-OutputCheck`
  parameter. Appends a plain-text "Output ISO PCA2023 readiness
  (post-conversion, file-based)" section consumed by both the P13
  FinalReport and the standalone `pca2023_readiness.md` file.

**Phase integration**.

- **P10 post-flight** (`Invoke-BuildPhase10_ConvertPca2023BootManager`):
  after the conversion completes and the snapshot is force-refreshed,
  invoke `Test-OutputIsoPca2023Readiness` against the extracted media,
  stash the result on `$post.OutputCheck`, and render a Compact line
  via `Show-Pca2023ReadinessSnapshot -Compact -OutputCheck $outputCheck`.
- **P12** (`Invoke-VerifyPhase12_VerifyPca2023Readiness`): always run
  the verification function regardless of whether P10 executed (the
  `-Force` snapshot refresh resets `OutputCheck` to `$null`, so the
  P12 path is idempotent). Render full detail via
  `Show-Pca2023ReadinessSnapshot -OutputCheck $outputCheck`. Emit the
  result into `pca2023_readiness.json` (via the standard
  `ConvertTo-Json -Depth 10` on the snapshot, which now includes
  `OutputCheck`) and `pca2023_readiness.md` (a new Markdown table
  with the 5-target results and a Reasons bullet list).
- **P13 FinalReport** (`Invoke-ReportPhase13_FinalReport`): when the
  snapshot's `OutputCheck` is populated, pass it through to
  `Show-Pca2023ReadinessSnapshot -Compact` so the operator sees the
  output-check status alongside the existing Compact summary. Uses
  a `PSObject.Properties['OutputCheck']` guard for defensive access
  in cases where the snapshot was built from a code path that does
  not populate the field.

**Implementation note: root cause of the Step 2 type-inference issue**.

The earlier r08.0 Step 2 implementation attempt of this function was
reverted because of a `System.ArgumentException: Argument types do
not match` exception that could not be resolved within the session
budget. Step 3 isolated the trigger with a minimal repro:

```powershell
$list = New-Object System.Collections.Generic.List[object]
$list.Add([pscustomobject]@{Label='test1'; Status='Pass'}) | Out-Null
$list.Add([pscustomobject]@{Label='test2'; Status='Fail'}) | Out-Null
@($list)             # FAILS: Argument types do not match
[object[]]@($list)   # FAILS: same
$list.ToArray()      # OK
```

The `@()` array subexpression operator fails on
`System.Collections.Generic.List[object]` whose elements are
`pscustomobject`. `.ToArray()` is the safe materialisation path. The
existing `Test-Pca2023AuthenticodeChain` and `Get-IsoBootCertReadiness`
escape this trap because their list is `List[string]` (where `@()`
works). The new function uses `.ToArray()` for its `TargetChecks`
(pscustomobject collection) but `@()` for its `Reasons` (string
collection), and documents the distinction in an inline comment so
future maintainers do not regress.

**Documentation changes**.

- New: `docs/history/r08.0-step3-output-verification-and-build.md`
  - Full implementation record including the Step 2 issue root-cause
    analysis, 4-case local test results on Linux pwsh 7.4.6, and the
    design rationale for the per-target Status mapping.
- Updated: `SPEC.md` §B.18 scope-and-limits paragraph
  - Replaced "(planned for addition in a follow-up step)" with the
    final description: the function is implemented, invoked from P10
    post-flight and P12, integrated into JSON / Markdown reports and
    the P13 FinalReport.
- Updated: `SPEC.md` §B.24.6
  - First item (`Test-OutputIsoPca2023Readiness`): CLOSED in Step 3.
  - Second item (Issue #346 defense): kept STILL OPEN with
    disposition note that closure depends on Phase 6 Build -Execute
    real run results.
  - Third item (Server 2025 `SecureBootRecovery.efi`): unchanged
    (informational only).
- Updated: `docs/history/r07.0-followups.md`
  - r08.0 Step 3 P0 #1 (`Test-OutputIsoPca2023Readiness` function +
    P10/P12 integration): CLOSED.
  - r08.0 Step 3 P0 #2 (Phase 6 Build -Execute on Server 2016 EVAL
    ja-jp): STILL OPEN, requires Windows host.
  - New P1 entry: Server 2019 / 2022 / 2025 Build -Execute fleet
    rollout (post-Server-2016 acceptance).

**Out-of-scope for this release (deferred to r08.0 Step 4+)**.

- Phase 6 `-Action Build -Execute` real run on Server 2016 EVAL
  ja-jp (the operational acceptance test for the entire r07.0+r08.0
  work). Requires the Windows host with `D:\UpdateWsi_2016\` workspace.
- Microsoft Issue #346-class defensive handling (`etfsboot.com` and
  similar boot.wim-content gaps): the P10 defensive logic is only
  added if Phase 6 reproduces the issue; otherwise no code change.
- Server 2019/2022/2025 Build -Execute horizontal validation.
- Physical-hardware Secure-Boot boot test on PCA2011-revoked DBX
  firmware (the ultimate validation outside the pipeline's scope).

**Quality gates**. All pass: psa.py (0/0/0), psa.py v4.1.0
PSA1004/2012/2013 (0/0/0), PSScriptAnalyzer (0 findings), PowerShell
parser (Parse OK), T2 (13/13), T3 (10/10), T6 (13/13). Encoding
preserved (BOM + CRLF + ASCII). Line count: 12224 -> 12652 (+428).

**Local test verification** (Linux pwsh 7.4.6, synthetic fake-media
trees under `/tmp/foi-*`):

```
Case 1: empty tree (all 5 targets missing)
  Available=True OverallStatus=Fail TargetChecks=5
    [Fail         ] Target #1  actual=missing
    [PassWithNotes] Target #2  actual=missing
    [Fail         ] Target #3  actual=missing
    [Warning      ] Target #4  actual=missing or empty
    [PassWithNotes] Target #5  actual=missing

Case 2: bootmgr.efi only -> OverallStatus=Fail (Target #1 still missing)
Case 3: 5-target full tree (dummy unsigned files) -> Fail (Linux pwsh
        cannot read Authenticode on dummies; on Windows with real
        PCA2023 bootx64.efi, expected: PassWithNotes)
Case 4: nonexistent path -> Available=False, OverallStatus=Fail,
        ErrorMessage populated
```

### r08.0 Step 2 - install.wim symmetry verification, Microsoft official spec cross-check, P07/P08 dead code path fix

This release closes two open follow-up items from r08.0 Step 1
(install.wim EFI_EX presence symmetry check across the 4 supported
OS families, Server 2025 `EFI_EX\bootmgfw_EX.efi` signature analysis)
and uncovers + fixes a long-standing dead code path that was
silently disabling P07 (install.wim updates) and P08 (boot.wim
updates) throughout the r07.0 cycle. The release also performs an
authoritative cross-check against Microsoft's
`Make2023BootableMedia.ps1` v1.4 to confirm that the in-repository
PCA2023 conversion design is aligned with Microsoft's upstream
specification.

`ScriptVersion`: `update-wsi-2026.05.26-r07.0` -> `update-wsi-2026.05.27-r08.0`
`ScriptTag`    : `kbid-from-filename-and-rich-refresh-summary` -> `promote-enable-flags-for-build-phases`

**Pre-flight investigation (read-only)**.

- **Step 5e — install.wim EFI_EX presence symmetry check.** Direct
  mount of Server 2016/2019/2022 EVAL `install.wim` Index 4 confirmed
  that `\Windows\Boot\EFI_EX\` is **absent** in all three out-of-box
  ISOs, matching the r08.0 Step 1 hypothesis. `bootmgfw.efi` in EFI
  is PCA2011 in all three. Closes the first item in SPEC.md §B.24.5.
- **Step 5f / 5g — Server 2025 EFI_EX signature analysis.** Initial
  `Get-AuthenticodeSignature` read returned `Issuer = Windows UEFI
  CA 2023` on `EFI_EX\bootmgfw_EX.efi`, which was briefly misread as
  a possible dual-signature. `signtool /verify /pa /all /v` plus
  `/ds 0`, `/ds 1`, `/ds 2`, `/ds 3` probe disambiguated the case
  decisively: there is **exactly one embedded signature** per file,
  and:
    - `EFI_EX\bootmgfw_EX.efi` is **PCA2023 single-sign**
      (leaf signer "Microsoft Windows", chain root via
      "Windows UEFI CA 2023")
    - `EFI_EX\bootmgr_EX.efi` is **PCA2011 single-sign**
      (leaf signer "Microsoft Windows", chain root via
      "Windows Production PCA 2011")
- **Step 5h — 4-OS exhaustive `*.efi` survey.** Data-driven
  cross-survey under `\Windows\Boot\` in all four install.wim Index 4
  trees. Totals: Server 2016/2019/2022 = 3 `*.efi` each (all PCA2011),
  Server 2025 = 6 `*.efi` (5 PCA2011, 1 PCA2023). No dual-signed
  files in any OS. Closes the second item in SPEC.md §B.24.5.
- **Microsoft official spec cross-check.** `microsoft/secureboot_objects`
  `scripts/windows/Make2023BootableMedia.ps1` v1.4 (dated 2026-03-13)
  was `git clone`'d and read in full. The `Copy-2023BootBins` function
  (L829-L941) writes five target locations onto the extracted media;
  see SPEC.md §B.18 for the full table. **The Microsoft upstream
  comment at L876-L884** explicitly states that `bootmgr_EX.efi`
  remaining PCA2011 is by design ("Note that this file technically
  is not signed with the 'Windows UEFI CA 2023' certificate, but if
  present in the update, it should be copied"). This validates the
  empirical step 5h finding. The Microsoft upstream contains no
  signature verification logic (zero `Get-AuthenticodeSignature` /
  `signtool` references in the 1141-line script); in-tree
  verification by this pipeline is therefore an upstream-compatible
  quality extension.

**Code changes**.

- **(Fix) `Get-ConfigProfile` now promotes phase-enable flags.**
  Three flags were referenced by P07, P08, and WinRE phases as
  `$Script:OsProfile.EnableInstallWimUpdate` /
  `.EnableBootWimUpdate` / `.EnableWinREUpdate` but were never
  promoted from `Common` to the top-level merged profile in
  `Get-ConfigProfile`. As a result, the property access returned
  `$null` regardless of profile content, and the build phases were
  silently skipped throughout the r07.0 cycle. This is the root cause
  of the previously-unexplained "P07/P08 always skip" behaviour.
  Fix promotes the three flags explicitly with an inline comment
  documenting the rationale.
- **(Config) `Common.EnableInstallWimUpdate` set explicitly per OS.**
    - Server 2016 / 2019 / 2022: `true` (Option A route requires
      install.wim LCU application to materialise EFI_EX assets)
    - Server 2025: `false` (out-of-box install.wim ships EFI_EX
      pre-populated; LCU application is optional for PCA2023)
- **(Version) `ScriptVersion` bumped** from `update-wsi-2026.05.26-r07.0`
  to `update-wsi-2026.05.27-r08.0`. `ScriptTag` set to
  `promote-enable-flags-for-build-phases`.

**Documentation changes**.

- New: `docs/history/r08.0-step2-installwim-symmetry-check.md` (407 lines)
  — full session record covering the three step 5 investigation runs,
  the Microsoft official spec cross-check, and the Phase 1-3
  implementation details. Includes the verbatim Microsoft L876-L884
  comment for traceability.
- Updated: `SPEC.md` §B.18 — added the authoritative Microsoft source
  citation, the 5-target conversion table, the L876-L884 PCA2011
  design quote, and the scope-and-limits paragraph clarifying what
  in-tree verification can and cannot establish.
- Updated: `SPEC.md` §B.24.5 — marked two items CLOSED (install.wim
  EFI_EX symmetry and Server 2025 `bootmgfw_EX.efi` signature), kept
  one STILL OPEN (Server 2016 EVAL end-to-end Build -Execute).
- New: `SPEC.md` §B.24.6 — three new open items raised in Step 2
  (Test-OutputIsoPca2023Readiness implementation, Phase 6 readiness
  for Microsoft Issue #346-class problems, Server 2025
  SecureBootRecovery.efi documentation).

**Out-of-scope for this release (deferred to r08.0 Step 3+)**.

- `Test-OutputIsoPca2023Readiness` function — file-by-file post-build
  verification against the five Microsoft conversion targets. Designed
  during this session but implementation deferred after a PowerShell
  type-inference issue in nested `[pscustomobject]` construction was
  not resolvable within the session budget. The design is captured
  in `docs/history/r08.0-step2-installwim-symmetry-check.md` §5.1.
- P10 / P12 integration of the above verification function.
- Phase 6 — Server 2016 EVAL ja-jp `-Action Build -Execute` real run
  on Windows. Microsoft Issue #346 (2026-02-14) reports analogous
  errors on Windows 11 25H2 + latest LCU, so defensive handling for
  missing `etfsboot.com` and similar boot.wim-content gaps may be
  required during the Phase 6 work.

**Quality gates**. All pass: psa.py (0/0/0), psa.py v4.1.0
PSA1004/2012/2013 (0/0/0), PSScriptAnalyzer (0 findings), PowerShell
parser (Parse OK), T2 (13/13), T3 (10/10), T6 (13/13). Encoding
preserved (BOM + CRLF + ASCII).

**Live verification** (Linux pwsh, post-fix profile merge):

```
Server2016   EnableInstallWimUpdate = True   P07 will skip? False
Server2019   EnableInstallWimUpdate = True   P07 will skip? False
Server2022   EnableInstallWimUpdate = True   P07 will skip? False
Server2025   EnableInstallWimUpdate = False  P07 will skip? True
```

### r08.0 Step 1 - Server 2016/2019/2022/2025 PCA2023 readiness investigation

This is a **documentation / investigation** release with no
code changes to `Update-WindowsServerIso.ps1`. The r08.0 cycle
opens with a P0 investigation task carried over from
`docs/history/r07.0-followups.md#P0`: determine the correct
workflow for producing a PCA2023-bootable Server 2016 EVAL
ISO, given that the r07.0 dry-run completion left this question
unanswered.

**Outcome**: the prior "Server 2016 EVAL is not viable for the
PCA2023 use case" interpretation was **incorrect**. All four
supported OS families (Server 2016 / 2019 / 2022 / 2025) can
produce a Healthy PCA2023 ISO via the **Option A** route from
`r07.0-followups.md#P0`:

1. Enable `EnableInstallWimUpdate=true` in
   `config-Server<2016|2019|2022>.json`.
2. Include a 2024-4B-or-later LCU in `PatchBaseline.NeutralPatches`.
3. P10 `ConvertPca2023BootManager` then converts the boot manager
   from PCA2011 to PCA2023 using the EFI_EX staging assets that
   the LCU shipped into install.wim.

Server 2025 is a special case: Microsoft ships the EFI_EX staging
directories pre-populated inside the **out-of-the-box** install.wim,
so the LCU does not (and need not) carry `*_EX.efi` binaries. The
P10 conversion still applies; it just does not depend on LCU
application as a prerequisite.

**Evidence base**. The conclusion is supported by three independent
sources verified during this session:

| Source | Evidence |
|---|---|
| **Microsoft official code** | `microsoft/secureboot_objects` `Make2023BootableMedia.ps1` v1.4 / 2026-03-13: 1141 lines, zero OS-version literals, OS-agnostic by design |
| **Microsoft Support KB5053484** | "Applies To" section explicitly enumerates Server 2016, 2019, 2022 (Server 2025 was not yet released when the KB was published 2025-02-04) |
| **Physical MSU expansion (4 OS)** | Server 2016 KB5087537, Server 2019 KB5087538, Server 2022 KB5087545 all carry the identical 6-binary `*_EX.efi` composition (`bootmgfw_ex.efi`×3 + `wdsmgfw_ex.efi`×2 + `bootmgr_ex.efi`×1) plus matching `bootmgfw_EX*` MUI tree. Server 2025 KB5087539 has none of these, but Server 2025 EVAL install.wim's `\Windows\Boot\` already contains `EFI_EX\` (72 files), `Fonts_EX\` (16 files), `DVD_EX\` (2 files) |

**Methodological side-finding**. Server 2025 MSU packaging crossed
a generational boundary: starting with Server 2025 / Windows 11 24H2,
MSU files are `MSWIM` (Windows Imaging Format) wrappers carrying a
`*.wim` manifests file plus a `*.psf` Patch Storage Stream v2
(`PSTREAM` magic) binary-delta file, instead of the legacy `MSCF`
(CAB) structure used by Server 2016/2019/2022. Future operator-side
manual MSU inspection on Server 2025 requires `DISM /Apply-Image`
instead of `expand.exe`. The pipeline itself is unaffected because
DISM handles both formats transparently when applying packages to a
mounted image.

**Files added**:

- `docs/history/r08.0-step1-server2016-pca2023-finding.md`
  (24,949 bytes) — full investigation report including 4-OS MSU
  structure maps, EFI_EX assessment per OS, install.wim direct
  inspection results, certificate-chain analysis, and the §9
  open-question list for r08.0 Step 2.

**Files updated**:

- `SPEC.md` — new `B.24 LCU package format generation matrix and
  EFI_EX provenance (r08.0+, informative)` summarising the
  investigation results for future readers (e.g. what packaging
  format each OS uses, where EFI_EX comes from per OS, what
  config-Server*.json values follow from this).
- `docs/history/r07.0-followups.md` — `P0 Server 2016 EVAL secure
  boot and PCA2023 readiness` moved to **Closed items** with a
  pointer to the finding; new follow-up items added for the
  r08.0 Step 2 implementation work.

**Files NOT changed** (intentional):

- `Update-WindowsServerIso.ps1` — no behavioural changes are
  required. The existing P10 design (skip-with-warn on Critical
  health, run on Healthy) is correct for all four OS families.
- `data/config-Server*.json` — the config updates are tracked as
  r08.0 Step 2 tasks (see `r07.0-followups.md` § new P0
  entry), not part of this Step 1 documentation-only release.

**Static analysis**: not re-run for Step 1 because no `.ps1` file
was touched. The r07.0 Step 19 clean scan (0/0/0) remains
valid as of this release.

### r07.0 Step 19 - Eliminate duplicate Phase Timing Summary via idempotent Show-PhaseSummary

The Step 18 verification produced the first **fully-clean
end-to-end PrepareBuildVerify run** in r07.0 - and arguably
in this script's lifetime to date - against a real Server 2016
EVAL ja-jp source media. The 13-phase pipeline ran in 4m44s
with exit 0 and no interactive prompts:

```
P01   DONE     elapsed: 0.14s
P02   DONE     elapsed: 0.11s
P03   DONE     elapsed: 0.02s  (skipped, -UseBaselineOnly)
P04   DONE     elapsed: 17.43s (ISO + 2 patches all cached)
P05   DONE     elapsed: 35.82s (robocopy 6.68 GB + WIM enum)
P06   DONE     elapsed: 0.02s  (skipped, -UseBaselineOnly)
P07   DONE     elapsed: 0.02s  (EnableInstallWimUpdate=false)
P08   DONE     elapsed: 0.02s  (EnableBootWimUpdate=false)
P09   DONE     elapsed: 0.02s  (Sandbox mode)
P10   DONE     elapsed: 1m54s  (Critical health -> skip-with-warn)
P11   DONE     elapsed: 0.03s  ("Output ISO missing" recorded)
P12   DONE     elapsed: 1m56s  (full non-compact rendering OK)
P13   DONE     elapsed: 0.05s  (FinalReport with PCA2023 summary)
```

All 14 progress lines in P10 and P12 rendered cleanly,
including the EFI_EX / FONTS_EX / DVD_EX detail lines that
the Step 18 `$(if ...)` fix unblocked. The Step 17 fix kept
the non-compact rendering path from hanging on the broken
Write-PhaseHeader call. The Step 16 progress logging made
the WIM mount/dismount cycles visible in real time. The
mojibake from Step 16 did not recur (fresh WorkRoot).

This is the **dry-run completion milestone**.

**Remaining cosmetic defect surfaced by the milestone run.**
The "Phase Timing Summary" table appeared twice in the
console output - once as part of P13's body (per SPEC.md
Part B.5 P13 Step 1), and once again from the script-tail
`finally` block. Both call sites are by design: P13 prints
the table because SPEC says it does; the `finally` block
prints it as a safety net so an aborted run still gets the
timing table. The duplication on a happy-path run was a
coordination gap.

**Fix**. Make `Show-PhaseSummary` itself idempotent rather
than coordinate between callers. A new
`$Script:PhaseSummaryShown` flag (initialised to `$false`
alongside `$Script:PhaseTimings`) is flipped to `$true` on
the first invocation. The `finally` call after P13 sees the
flag is already true and short-circuits without printing.
The safety-net behaviour is preserved: if P13 does NOT run
(early failure, or an `-Action` that excludes P13), the
flag is still `$false` when the `finally` block fires and
the table prints as before.

A new `-Force` switch on `Show-PhaseSummary` bypasses the
guard for ad-hoc / test scenarios. Production callers never
use it.

`Show-PhaseSummary` is also promoted from a one-line
wrapper to a properly-documented advanced function with
`[CmdletBinding()]`, `[OutputType([void])]`, and a
multi-paragraph `.SYNOPSIS` / `.DESCRIPTION` block
explaining the two callers and the idempotency contract.

**Verification**. A short pwsh smoke-test AST-extracted
`Show-PhaseSummary` and `Format-Elapsed` from the script,
built a fake `$Script:PhaseTimings` list, and called the
function three times:

```
Call #1 (no -Force):  prints table   - OK
Call #2 (no -Force):  silent         - OK (idempotency works)
Call #3 (with -Force): prints again  - OK
```

**Quality gates**. All five gates pass: BOM + CRLF + ASCII
OK (12,213 lines, no LF-only lines), PS Parse OK, `psa.py`
0/0/0, PSScriptAnalyzer 0 issues, T2-T10 all 6 tests PASS,
runtime idempotency smoke-test passes.

A meta-defect was caught and fixed during this release: the
initial `str_replace` insertion of the new
`$Script:PhaseSummaryShown` initialiser produced six
LF-only lines (the editing tool's default newline) into a
CRLF file. psa.py's PSA7002 rule caught it at gate time;
the lines were normalised to CRLF before the second gate
run.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-PhaseSummary` rewritten with idempotency guard,
    `-Force` switch, full doc comment, and `[OutputType([void])]`.
  - `$Script:PhaseSummaryShown = $false` initialiser added
    immediately after `$Script:PhaseTimings = ...`.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.24 and the matching matrix row.

**What comes next.**

PrepareBuildVerify is now production-ready as a dry-run
inspection tool. The remaining work falls into three
categories:

1. **Server 2019 / 2022 / 2025 verification**. Repeat the
   end-to-end PrepareBuildVerify run on the other three
   OS families to confirm no OS-specific surprises.
   Server 2025 in particular should skip P10 cleanly
   (per the existing Server2025 gate) and Server 2022's
   PCA2023 path will exercise the conversion code that
   Server 2016 cannot reach.
2. **`-Execute` mode**. Switch from `PrepareBuildVerify`
   (dry-run) to `Build` or `All` with `-Execute` to
   actually call `oscdimg` and produce the output ISO.
   For Server 2016 EVAL with `EnableInstallWimUpdate=false`,
   the output ISO will be byte-identical to the source
   (no patching done) which is mostly useful as a smoke
   test for the assembly pipeline.
3. **Mojibake DISM-cache investigation** (deferred).
   The notes are in `docs/history/mojibake-investigation-note.md`.
   Pick up when there is time; the workaround (fresh
   WorkRoot per OS family) is already known.

### r07.0 Step 18 - Fix `(if ...)` mis-spelled subexpressions in Show-Pca2023ReadinessSnapshot

Step 17's `Write-PhaseHeader -> Write-SubSection` fix unblocked
the non-compact rendering branch in `Show-Pca2023ReadinessSnapshot`,
and the Step 17 verification run reached and ran it cleanly
all the way through P10 + P11 + P12 snapshot computation +
the new `-- PCA2023 readiness detail --` sub-section header
... at which point it failed with:

```
[X] Phase P12 (VerifyPca2023Readiness) failed: 用語 'if' は、コマンドレット、
    関数、スクリプト ファイル、または操作可能なプログラムの名前として
    認識されません。
[~]     Show-Pca2023ReadinessSnapshot, line 8184
[~]     Invoke-VerifyPhase12_VerifyPca2023Readiness, line 10478
```

Root cause: a second latent bug in the same
`Show-Pca2023ReadinessSnapshot` function. Five lines (L8184-8188)
used the wrong subexpression syntax:

```powershell
# BROKEN - PowerShell parses (if ...) as a command invocation named 'if'
'EFI_EX staging directory : {0}' -f (if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ... )

# CORRECT - $(...) is the subexpression operator that wraps a statement as a value
'EFI_EX staging directory : {0}' -f $(if ($null -eq $emb.HasEfiExDir) { 'n/a' } elseif ... )
```

The same function had this idiom written **correctly** six lines
below ($Signer subject line) and at four other sites
in the SecureBoot/LCU blocks. The bug was a local copy-paste
mistake on the five EFI_EX/FONTS_EX/DVD_EX-family lines,
not a systemic misunderstanding.

**Why this slipped through static analysis**. `(if ...)` is a
syntactically valid command-invocation form in PowerShell's
grammar - the parser accepts it and treats `if` as a command
name to be resolved at runtime. PS Parse passed, psa.py
passed (0/0/0), PSScriptAnalyzer passed (0 issues). The
function was unreachable in earlier verification runs (the
Write-PhaseHeader bug blocked it), and the compact branch -
which is what every other call site uses - skips the broken
lines entirely.

The first runtime invocation through the unblocked non-compact
path immediately surfaced the bug.

**Fixes applied**.

1. Five `(if ...)` -> `$(if ...)` replacements at L8184-L8188.
2. An 8-line in-source comment explaining the trap, the
   correct `$(if ...)` form, and the fact that `@(if ...)`
   (array subexpression) is also valid. Placed immediately
   before the first formerly-broken line.
3. Defensive Python grep over the entire script for any
   other bare `(if ...)`, `(switch ...)`, `(foreach ...)`,
   or `(while ...)` patterns. Zero further hits.
4. Smoke-test runtime verification: a short pwsh script that
   AST-extracts `Show-Pca2023ReadinessSnapshot` and its
   `Write-Step` / `Write-SubSection` / `_LogLine`
   dependencies, builds a fake snapshot pscustomobject,
   and calls the function in non-compact mode. The test
   now passes; before the fix it threw the same "term 'if'
   is not recognized" error.

**Discipline note**. The B.23.22 ASCII-only rule was very
nearly violated in the first iteration of this fix - I had
quoted the localised Japanese error message in the in-source
comment for diagnostic clarity. The quality-gate ASCII check
caught it before commit. The final comment uses an English
paraphrase ("term 'if' is not recognized as a name of a
cmdlet, function, script file...") and keeps the file
ASCII-only.

**Quality gates**. All five pass: BOM + CRLF + ASCII OK
(12,171 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS, runtime smoke-test of
`Show-Pca2023ReadinessSnapshot` in non-compact mode RUNS OK
with all expected output lines.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-Pca2023ReadinessSnapshot` ISO-boot-environment block:
    five `(if ...)` -> `$(if ...)` rewrites, plus an
    8-line explanatory comment.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.23 and the matching matrix row.

**Expected next run**.

With Steps 16-18 stacked, the PrepareBuildVerify command should
now reach P13 FinalReport for the first time and exit cleanly:

1. P01-P09: cached / skipped quickly (P05 robocopy re-runs
   against the existing extracted tree).
2. P10: skip-with-warn (Critical health), DONE.
3. P11: "Output ISO missing", DONE.
4. P12: snapshot computation + full non-compact rendering
   (now working), then DONE.
5. P13: FinalReport with all collected state.
6. Total elapsed ~5 minutes, exit 0, no interactive prompts.

### r07.0 Step 17 - Fix Write-PhaseHeader positional call that hung P12 in non-compact rendering mode

The Step 16 live verification got further than ever before:

- P01 - P09 ran cleanly (0.1 - 35 seconds each).
- P10 entered its new step-by-step progress logging path,
  ran the boot.wim + install.wim readiness snapshot in 1m55s
  with all 14 progress lines visible, classified the health
  as 'Critical' (Server 2016 EVAL install.wim still at
  KB3211320), wrote the new `Write-Warn` block explaining
  the prereq, dropped the `P10.skipped` marker, and DONE.
- P11 StaticVerify ran in 40 ms and correctly recorded
  "Output ISO missing" (expected in PrepareBuildVerify
  dry-run mode).
- P12 VerifyPca2023Readiness ran the snapshot computation
  in 1m55s with the same progress lines, then ...

... PowerShell prompted for interactive input:

```
コマンド パイプライン位置 1 のコマンドレット Write-PhaseHeader
次のパラメーターに値を指定してください:
Name:
```

The user had to Ctrl-C. P13 never ran.

Root cause: `Show-Pca2023ReadinessSnapshot` (the function that
P12 calls at the very end to render the readiness snapshot to
the console) has two rendering modes - compact (a single
one-line summary) and non-compact (a full multi-section dump).
The non-compact branch began with this line:

```powershell
Write-PhaseHeader 'Pca2023 readiness (P12)'
```

`Write-PhaseHeader`'s signature is:

```powershell
param(
    [Parameter(Mandatory)] [string]$Id,
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$Group
)
```

Positional binding fills only `-Id`. PowerShell then prompts
the user for `-Name`. The four `Show-Pca2023ReadinessSnapshot`
call sites are:

- P10 post-flight: passes `-Compact` -> compact branch -> safe
- **P12 verify body: no `-Compact` flag -> hit the broken line**
- P13 summary: passes `-Compact` -> compact branch -> safe
- Standalone analysis helper: no `-Compact` -> would also hit
  the broken line, but this code path is not normally exercised

The fix is one line: replace `Write-PhaseHeader` with
`Write-SubSection`. Semantically this was the right idiom
all along - the function is called *during* a phase (P12 has
already emitted its own phase banner at entry), so a second
phase banner inside the body would be visual noise even if
the call had worked.

A defensive audit was added to confirm no other Mandatory-param
function in the script is called positionally elsewhere. A
small Python pass found 28 functions with >=2 Mandatory
parameters and zero positional-call sites among them, so this
was the only such trap remaining.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Show-Pca2023ReadinessSnapshot` non-compact branch:
    `Write-PhaseHeader 'Pca2023 readiness (P12)'` -> `Write-SubSection 'PCA2023 readiness detail'`
    plus a 10-line comment explaining why
    `Write-SubSection` is the right choice here.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.22 and the matching matrix row.

**Additional observation - mojibake no longer reproduces**.

The Step 16 run had reported a console-rendering artifact:
install.wim idx 2's Japanese edition name appeared with each
character doubled (`デデススククトトッッププ` instead of
`デスクトップ`). The Step 17 run had **identical mojibake-side
conditions** (same PS 5.1.26100.32860, same ja-JP culture,
same `Console OutputEnc utf-8 (cp65001)`, same source ISO),
but the only externally-visible difference - the `-WorkRoot`
path was changed from `D:\UpdateWsi` to `D:\UpdateWsi_2016` -
caused the mojibake to disappear entirely. idx 2 now renders
correctly.

The investigation note at
`docs/history/mojibake-investigation-note.md` has been updated
with this new finding. The working hypothesis has shifted from
"PS 5.1 console UTF-16 surrogate handling" to "DISM mount-cache
state corruption from prior aborted P10 runs". The original
WorkRoot had been used through Steps 11-16 with several
aborted P10 mount/dismount cycles; the new tree was fresh.
This remains a deferred low-priority investigation; the
working workaround in the meantime is "use a fresh WorkRoot
per OS family", which is what Takayuki's run was already
doing.

**Quality gates**. All five pass: BOM + CRLF + ASCII OK
(12,164 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS.

**Expected next run**.

With both Step 16 (P10 skip-with-warn + progress logging,
Invoke-DownloadWithProgress utility) and Step 17 (P12
non-compact rendering fix) applied, the next
`PrepareBuildVerify` run is expected to:

1. P01-P09: run quickly with cached assets (P05 robocopy
   re-runs against the existing extracted tree - robocopy
   skip-already-copied makes this near-instant).
2. P10: skip-with-warn cleanly (`Health = Critical`,
   `P10.skipped` marker, no throw).
3. P11: record "Output ISO missing".
4. P12: complete the second snapshot run (~115 seconds for
   the WIM mount/enum/dismount cycle), then render the
   full readiness detail via the now-fixed `Write-SubSection`
   path and continue to P13.
5. P13: emit the FinalReport with all collected state.
6. Script exits 0 cleanly. No interactive prompt.

### r07.0 Step 16 - P10 progress logging, Critical-Health skip-with-warn, and `Invoke-DownloadWithProgress` utility

Three UX improvements bundled under one release because they
share the same theme - making long-running phases emit visible
progress instead of silent multi-minute pauses.

**Observed regression that motivated the changes.** The Step 15
run got all the way through P01 - P09 cleanly, then P10 ran for
1m54.9s with no on-screen output before throwing
`P10 pre-flight failed: snapshot Health is 'Critical'`. The user
correctly observed three problems:

1. The throw was wrong UX for `-Action PrepareBuildVerify` - the
   action is a dry-run inspection, and the prereq mismatch is
   *information*, not a hard failure that should abort before
   P11/P12/P13 even run.
2. P10 was emitting one `Write-SubSection` header at entry and
   then nothing for the entire 1m54s. The silent block was two
   `Mount-WindowsImage` + `Get-WindowsPackage` enumerations
   inside `Get-IsoBootCertReadiness` - which takes 30-90s per
   WIM on commodity NVMe.
3. The original ISO download (when the cache was empty) had the
   same issue, just on a longer timescale - a 6 GB ISO would
   download silently for 10-15 minutes with only "Downloading..."
   and "Downloaded: {path}".

**Fix 1: P10 Critical-Health throw -> skip-with-warn**.

The P10 Critical branch now writes a structured `Write-Warn`
with the snapshot reasons, prints two follow-up `Write-Warn`
lines explaining how to enable PCA2023 conversion (profile
`EnableInstallWimUpdate = true` + patch baseline must include
2024-4B LCU `KB5036899` or later), drops the `P10.skipped`
marker file that matches the existing skip-condition pattern,
and returns cleanly so P11-P13 still run. The throw for missing
`$Script:ExtractedDir` (workflow ordering violation) is preserved
because P11-P13 would also fail without the extracted tree.

**Fix 2: P10 step-by-step progress logging**.

P10 is now restructured into four named steps with
`Write-SubSection` headers matching the pattern P01-P09
already use:

- `Step 1: Pre-flight gates` (EnablePca2023BootManager check,
  Server2025 advisory, ExtractedDir presence)
- `Step 2: Boot manager readiness snapshot (pre-conversion)` -
  the long block, now with start/end timings
- `Step 3: Convert boot manager to PCA2023 signing` - external
  or internal converter, with per-call elapsed-seconds
- `Step 4: Re-assemble ISO and post-flight verification`

Each step records its start time and prints
`... completed in {0}s` so the user gets concrete progress
even before the snapshot itself emits anything.

The bigger win is propagating progress logging *into*
`Get-IsoBootCertReadiness` - the function that was silent for
the 1m54s. It now emits seven `Write-Step` lines as it runs:

```
  [1/4] Mounting boot.wim idx 1 read-only ...
         boot.wim mounted (12s); inspecting EFI_EX / FONTS_EX / DVD_EX ...
         enumerating boot.wim installed packages (Get-WindowsPackage) ...
         boot.wim LCU level resolved (8s): highest KB = KB3211320
  [2/4] Dismounting boot.wim (discard) ...
         boot.wim dismounted (5s)
         Inspecting bootx64.efi Authenticode signer chain ...
         bootx64.efi signer: Microsoft Windows Production PCA 2011
  [3/4] Mounting install.wim idx 1 read-only ...
         install.wim mounted (28s); enumerating installed packages ...
         install.wim LCU level resolved (35s): highest KB = KB3211320
         reading SYSTEM hive SecureBoot servicing keys ...
  [4/4] Dismounting install.wim (discard) ...
         install.wim dismounted (16s)
```

Now the user sees exactly where time is going in real time.

**Fix 3: `Invoke-DownloadWithProgress` utility**.

The existing `Invoke-WebRequestWithRetry` correctly sets
`$ProgressPreference = 'SilentlyContinue'` to dodge PS 5.1's
O(N^2) progress-bar slowdown on multi-GB downloads, but the
trade-off is total silence for the duration of the download. A
new utility function recovers visibility *without* re-enabling
the slow built-in progress bar.

The technique is borrowed in spirit from
`Deploy-AMDChipsetDriverOnWindowsServer.ps1` in the
[usui-tk/Deploy-Drivers-For-WindowsServer](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer)
repository (see its `Invoke-PrepPhase03_FetchInstaller` around
L7808 - `Write-Step` before, `Write-Ok` after, post-download
size validation against a minimum threshold), but extended with
a background-job + main-thread-polling mechanism that the
reference does not have. The reference can get away with
just start/end markers because its payloads are 50-150 MB
chipset installers; this script downloads multi-GB ISOs where
the lack of mid-stream feedback is much more painful.

Steps performed by the new function:

1. HEAD request to learn expected `Content-Length` (~1 second;
   optional - some CDNs reject HEAD with 405).
2. Spawn a `Start-Job` worker that runs the actual
   `Invoke-WebRequest` with `ProgressPreference = 'SilentlyContinue'`
   in its own runspace.
3. From the main thread, poll the destination file's size via
   `Get-Item -LiteralPath ... | Length` every 5 seconds.
4. Print one progress line per poll:
   `  ... 1,234.5 MB / 6,852.3 MB (18.0%) at 12.3 MB/s ETA 8m 12s`
5. On completion, print a final `Write-Ok` summary:
   `[+] Downloaded: 6,852.3 MB in 9m 17s (12.3 MB/s avg)`
6. Optional `-MinSizeBytes` post-download check; if the file is
   smaller than the threshold, deletes it and throws an
   actionable error message (the
   "CDN returned an error page" defense).

`Invoke-WebRequestWithRetry` is refactored so the `-OutFile`
branch delegates to `Invoke-DownloadWithProgress`. The in-memory
fetch path (HTML/JSON scraping for Microsoft Learn release-info,
.NET CU index, MSU Catalog) keeps the original direct call - those
responses are small and don't benefit from the background-job
overhead. All existing call sites (the ISO download in P04 Step
1, the MSU patch downloads in P04 Step 2, the wsusscn2.cab
download for offline scanning) keep working unchanged; they
now get progress output automatically.

**Quality gates**. All five gates pass: BOM + CRLF + ASCII OK
(12,154 lines), PS Parse OK, `psa.py` 0/0/0, PSScriptAnalyzer
0 issues, T2-T10 all 6 tests PASS. No data files, workflows,
or tests are touched - this is a pure PS1 + docs change.

**Files changed**.

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Added `Format-MegabyteCount` helper (~16 lines).
  - Added `Invoke-DownloadWithProgress` utility (~240 lines)
    with `[OutputType([void])]` on its CmdletBinding.
  - Refactored `Invoke-WebRequestWithRetry` `-OutFile` branch
    to delegate (~30 lines net change).
  - Restructured `Invoke-BuildPhase10_ConvertPca2023BootManager`
    into four named steps with `Write-SubSection` headers,
    per-step timings, and the Critical-Health skip-with-warn
    branch (~90 lines net change).
  - Added 14 progress `Write-Step` calls inside
    `Get-IsoBootCertReadiness` (boot.wim mount/enum/dismount,
    install.wim mount/enum/SYSTEM-hive/dismount).
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.21 and the matching matrix row.

**Next**. Run the same `PrepareBuildVerify` command again and
expect:

1. P04 ISO/patches step now logs progress (or "cached" lines
   if the local cache is hit, which it should be).
2. P10 prints the four `Step 1-4` sub-section headers, then
   the seven `Write-Step` lines from inside the snapshot.
3. P10 ends with `Write-Warn` + skip-with-marker (no throw)
   because the Server 2016 EVAL install.wim still has the 2017
   highest KB; P11-P13 then continue normally.

### r07.0 Step 15 - Fix `$Script:ExtractedMediaPath` and `$Script:WorkRootFull` typos in P10/P12

Triggered by a failure observed on the freshly-pushed Step 14
commit. With the P05 ExpandIso robocopy fix, the script
finally reached and completed P05 through P09, then hit a
guard at the entry to P10:

```
PHASE P05  - ExpandIso  (Plan) start: 18:11:52
 [+] robocopy exit=1 (0-7 = success)
 [+] Extracted ISO contents to: D:\UpdateWsi\source\extracted
 [*]   install.wim idx 1-4: Server 2016 Standard / Datacenter, Core / Desktop
 [*]   boot.wim idx 1-2: Windows PE / Windows Setup
P05  DONE     elapsed: 33.24s
P06  DONE (skipped, -UseBaselineOnly)
P07  DONE (skipped, EnableInstallWimUpdate=false)
P08  DONE (skipped, EnableBootWimUpdate=false)
P09  DONE (sandbox mode, oscdimg run skipped)
PHASE P10  - ConvertPca2023BootManager (Build) start: 18:12:26
P10  FAILED   elapsed: 0.01s
 [X] P10 requires P05 ExpandIso to have produced an extracted
     media tree. Run -Action All or -Action Build.
```

The error message was misleading: P05 had in fact run and
produced the extracted tree at `D:\UpdateWsi\source\extracted`
(P05 spent 33 seconds copying ~6 GB via robocopy and then
~1 second enumerating the four install.wim editions and two
boot.wim indexes). The guard at line 9822 was reading
`$Script:ExtractedMediaPath`, which is a variable that is
never assigned anywhere in the script. The actual script-
scope global that holds the extracted-ISO directory is
`$Script:ExtractedDir`, initialised at L496 alongside the
other working-directory globals. Because `$Script:
ExtractedMediaPath` evaluated to `$null`, the
`-not $extractedPath` branch in the guard fired
unconditionally and threw the misleading 'P05 did not run'
exception.

A defensive audit of the surrounding code surfaced a second
typo of the same family: `$Script:WorkRootFull` was being
read at six sites under P10 and P12 but is also never set.
The correct global is `$Script:WorkRoot`, initialised at
L486 via `Resolve-RelativeToScript $WorkRoot` (which
already returns an absolute path, so the `Full` suffix
that the consumer sites expected was always redundant).
Both typos likely originate from the same earlier rename
that updated the definition sites but missed the consumer
sites.

**Fixes applied**.

Site set 1: `$Script:ExtractedMediaPath` -> `$Script:ExtractedDir`
at the two reader sites in P10 (`Invoke-BuildPhase10_ConvertPca2023BootManager`)
and P12 (`Invoke-VerifyPhase12_VerifyPca2023Readiness`). A
clarifying comment was added above the P10 site noting that
the script-scope global keeps the `ExtractedDir` name while
the PCA2023 helper API surface uses `$ExtractedMediaPath`
as a function-parameter name (the two are not the same
scope).

Site set 2: `$Script:WorkRootFull` -> `$Script:WorkRoot` at
all six reader sites (L9836, L9882, L9917, L10121, L10128,
L10213) under P10 and P12. No assignment site existed for
`WorkRootFull`, so the rename is purely consumer-side and
has no behavioural side effect beyond the fix itself.

The broader global-variable audit also surfaced 24 other
"read but never defined" globals; on inspection these are
all PowerShell `param()` bindings (script parameters
auto-populate `$Script:`-scoped variables), one
defensively-guarded read with a `IsNullOrEmpty` check and
`$PSCommandPath` fallback (`$Script:ScriptPath`), and one
comment-only reference (`$Script:ErrorsJsonlPath`). No
further code change was required for those.

Live verification awaits the operator's re-run. With the
extracted media tree still on disk from the previous run,
P05 will re-run robocopy against the same destination
(robocopy mirroring keeps re-runs incremental and fast),
then P06-P09 skip or run quickly, and P10 should now
proceed past the guard. P10 then calls
`Get-OrEnsurePca2023Snapshot` against the extracted tree
to compute the PCA2023 readiness snapshot; the outcome
depends on the source ISO's boot manager signer chain
(Server 2016 ja-jp EVAL is signed under the PCA2011
root, so the snapshot Health is expected to be
something other than Healthy, which is what makes
the PCA2023 conversion necessary on Server 2016/2019/
2022 in the first place).

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Invoke-BuildPhase10_ConvertPca2023BootManager`:
    replaced one `$Script:ExtractedMediaPath` read and three
    `$Script:WorkRootFull` reads with the correct globals.
  - `Invoke-VerifyPhase12_VerifyPca2023Readiness`: replaced
    one `$Script:ExtractedMediaPath` read and three
    `$Script:WorkRootFull` reads with the correct globals.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.20 and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 14 - Switch P05 ExpandIso to robocopy; fix P09 overlay `-LiteralPath` + wildcard contradiction

Triggered by a failure observed on the freshly-pushed Step 13
commit. With the `Split-Path -LiteralPath -Leaf` parameter-set
bugs fixed, P04 finally completed both patch downloads in just
over 3 minutes, and the script reached P05 ExpandIso for the
first time in this verification cycle. P05 then hit a
different `Copy-Item` failure inside `Expand-SourceIso`:

```
P04   DONE     elapsed: 3m16.1s
PHASE P05  - ExpandIso  (Plan) start: 18:00:31
 -- Step 1: Expand source ISO ---
 [*] Copying from E:\ to D:\UpdateWsi\source\extracted ...
PHASE P05  -> FAILED   elapsed: 2.10s
 [X] Phase P05 (ExpandIso) failed:
     2 番目のパス フラグメントを ドライブ名または UNC 名にすることは
     できません。パラメーター名:path2
 [~]    Expand-SourceIso, line 8909
```

The failing statement was

```powershell
Copy-Item -LiteralPath $src -Destination $DestRoot -Recurse -Force
```

with `$src = 'E:\'` (the mounted ISO's drive root). PowerShell's
`Copy-Item` rejects a drive root as `-LiteralPath` when
combined with `-Recurse -Destination` because internally it
calls `System.IO.Path.Combine` to construct the destination
subpath, and Path.Combine refuses to accept a rooted path
('E:\') as its second argument - it cannot decide whether the
user wants the drive's contents copied INTO `$DestRoot` or the
drive itself created AS `$DestRoot\E:\`, and chooses to raise
rather than guess. The behaviour is identical on PowerShell
5.1 and 7.

While investigating, a second latent `Copy-Item` defect was
discovered at the Dynamic Update overlay site in
`Invoke-BuildPhase09_AssembleIso`:

```powershell
Copy-Item -LiteralPath (Join-Path $tmpExtract '*') ...
```

`-LiteralPath` defeats wildcard expansion by definition, so
the cmdlet would search for a file literally named `*` in
`$tmpExtract` and fail with 'Cannot find path' the first time
a Dynamic Update overlay was actually applied. This site has
not been hit in regression yet because the verification
ladder has been blocked upstream of P09, but it is the same
class of bug and is cheaper to fix now alongside the P05
correction.

**Fixes applied**.

Site 1: P05 `Expand-SourceIso` drive-root copy
(now at the same line, behaviour changed). Replaced the
single `Copy-Item -LiteralPath $src -Destination $DestRoot
-Recurse -Force` with a `robocopy.exe` invocation:

```powershell
$rcArgs = @(
    $src, $DestRoot,
    '/E',           # Subdirectories including empty
    '/COPY:DAT',    # Data, Attributes, Timestamps (no NTFS ACLs)
    '/R:1', '/W:1', # 1 retry, 1-sec wait
    '/NP', '/NDL', '/NFL', '/NJH', '/NJS',  # quiet console
    ('/LOG:' + $rcLog)
)
& robocopy.exe @rcArgs | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw ('robocopy failed (exit {0}): see {1}' -f $LASTEXITCODE, $rcLog)
}
Write-Ok ('robocopy exit={0} (0-7 = success), log: {1}' -f $LASTEXITCODE, $rcLog)
```

`robocopy.exe` ships with Windows since Vista, handles drive
roots as sources correctly, and is 5-10x faster than
`Copy-Item -Recurse` for ISO content (typically ~6 GB across
thousands of small files). The earlier in-source comment that
preferred Copy-Item to 'avoid external tools' was reverted -
robocopy is a Windows built-in, not an external dependency on
this target. Robocopy exit codes 0-7 are documented as success
or informational (0 = no changes, 1 = files copied, etc.); 8
or higher signals at least one fatal error and is converted
to a thrown exception with the log path attached for triage.

Site 2: P09 overlay `Copy-Item -LiteralPath ... '*'`
contradiction. Changed `-LiteralPath` to `-Path` so the
wildcard actually expands:

```powershell
Copy-Item -Path (Join-Path $tmpExtract '*') `
    -Destination (Join-Path $Script:ExtractedDir 'sources') -Recurse -Force
```

The other six `Copy-Item -LiteralPath ...` sites in the
script all copy single-file paths with no wildcards and are
correct as written.

Live verification awaits the operator's re-run. With ISO,
patches, and the seeding fix all known-good from previous
Step 12 / Step 13 runs, the next iteration is expected to
reach the patches as before in ~10 seconds (cached ISO) plus
patch DL (~3 min on a warm cache - likely much faster since
patches are now also on disk), then enter P05 with robocopy
moving ~6 GB from `E:\` to `D:\UpdateWsi\source\extracted` in
roughly 1-3 minutes depending on the host's I/O. After P05
the WIM enumeration runs (`install.wim` and `boot.wim`), then
P06 ValidatePatchSet, then the P07-P13 plan/sandbox phases.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - `Expand-SourceIso`: replaced `Copy-Item -LiteralPath
    $src -Destination $DestRoot -Recurse -Force` with a
    `robocopy.exe` invocation that handles drive-root
    sources and emits a log file under `$Script:LogsDir`.
  - `Invoke-BuildPhase09_AssembleIso`: changed
    `Copy-Item -LiteralPath (Join-Path $tmpExtract '*') ...`
    to `Copy-Item -Path ...` so the wildcard expands.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.19 and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 13 - Fix latent `Split-Path -LiteralPath -Leaf` parameter-set conflict at 7 sites

Triggered by a failure observed on the freshly-pushed Step 12
commit. With the empty-LocalPath bug fixed, P04 finally
reached Step 2 'Patches' and the very first per-patch
statement hit a different runtime error:

```
[+] Existing ISO found (6.68 GB); skipping download.
[*] Recorded ISO SHA-256: ceb4e1f786148782bd684853bda9c6177891da231eb0ca2b5a17130ec938b142
 -- Step 2: Patches ---------------------------------------------
 PHASE P04  -> FAILED   elapsed: 10.56s
 [X] Phase P04 (FetchAssets) failed:
     指定された名前のパラメーターを使用してパラメーター
     セットを解決できません。
 [~]     Invoke-FetchPhase04_FetchAssets, Update-WindowsServerIso.ps1: line 8827
```

Line 8827 contained
`$leaf = Split-Path -LiteralPath $p.LocalPath -Leaf`.
PowerShell rejects this combination at runtime on both
5.1 and 7: `-LiteralPath` and `-Leaf` belong to mutually
exclusive parameter sets. `-LiteralPath` only combines
with `-Resolve` and `-Credential`; `-Leaf` only combines
with the positional `-Path` form. The cmdlet docs do not
emphasise this collision, PSScriptAnalyzer does not flag
it as a static-analysis issue, and the `-LocalPath ...
-Leaf` shape is so syntactically natural that it has
slipped past review for multiple revisions of this
script.

The same parameter-set conflict was actually noticed
earlier for the `-LiteralPath ... -Parent` pair (see the
inline comment above the L1519 `[System.IO.Path]::
GetDirectoryName` call, which already documents the
`AmbiguousParameterSet at runtime` failure mode). The
`-Leaf` and `-LeafBase` variants of the same bug
continued to lurk in seven other places because their
code paths were unreachable in the regression suite
(P04 Step 2 only ran after Step 12; the DISM apply
helpers ran only live; the side-car LeafBase site
required a specific patch-directory layout).

Step 13 replaces all seven sites with
`[System.IO.Path]::GetFileName(...)` (or
`GetFileNameWithoutExtension(...)` for the LeafBase
case), matching the precedent set by the existing
`GetDirectoryName` migration:

```
L2478:  $name = Split-Path -LiteralPath $IsoPath -Leaf
     -> $name = [System.IO.Path]::GetFileName($IsoPath)

L5770:  Set-DebugStep -Step ('add-pkg-' +
            (Split-Path -LiteralPath $PackagePath -Leaf))
     -> Set-DebugStep -Step ('add-pkg-' +
            [System.IO.Path]::GetFileName($PackagePath))

L5783:  Write-Warn (... -f
            (Split-Path -LiteralPath $PackagePath -Leaf))
     -> Write-Warn (... -f
            [System.IO.Path]::GetFileName($PackagePath))

L7008:  ... -f $type, $kb,
            (Split-Path -LiteralPath $pkgPath -Leaf
                                  -ErrorAction SilentlyContinue)
     -> ... -f $type, $kb,
            [System.IO.Path]::GetFileName($pkgPath)

L7040:  ... -f $type, $kb,
            (Split-Path -LiteralPath $pkgPath -Leaf)
     -> ... -f $type, $kb,
            [System.IO.Path]::GetFileName($pkgPath)

L8392:  $sideCar = Join-Path $f.DirectoryName
            ((Split-Path -LiteralPath $f.FullName -LeafBase)
             + '.meta4')
     -> $sideCar = Join-Path $f.DirectoryName
            ([System.IO.Path]::GetFileNameWithoutExtension(
             $f.FullName) + '.meta4')

L8827:  $leaf = Split-Path -LiteralPath $p.LocalPath -Leaf
     -> $leaf = [System.IO.Path]::GetFileName($p.LocalPath)
```

The L7008 call dropped its
`-ErrorAction SilentlyContinue` parameter; that
suppression was silently swallowing the parameter-set
error all this time, leaving an empty `({2})` placeholder
in the DryRun log without surfacing the bug. The .NET
API does not throw on empty input (it returns an empty
string), so future regressions on the input value will
now become visible rather than hidden.

Live verification awaits the operator's re-run. With the
ISO cached at `D:\UpdateWsi\source\iso\WS2016_ja-jp.iso`
and the SHA-256 already recorded, P04 Step 1 will skip
the download within ~10 seconds and Step 2 should reach
the actual patch downloads:

```
[1/2] windows10.0-kb5087537-x64_1a68955...msu
    [~1.5 GB LCU download from catalog.s.download.windowsupdate.com]
[2/2] windows10.0-kb5087065-x64-ndp48_631ce425...msu
    [~70 MB .NET CU download]
```

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Seven `Split-Path -LiteralPath ... -Leaf` /
    `-LeafBase` sites replaced with `[System.IO.Path]
    ::GetFileName` / `::GetFileNameWithoutExtension`.
  - One `-ErrorAction SilentlyContinue` dropped (L7008)
    because the underlying call no longer throws.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.18 documenting the parameter-set
    collision and the migration policy. Added the
    matching matrix row.

No data files, workflows, or tests are touched. Three
in-source comments still mention `Split-Path
-LiteralPath` (one is the original L1519 documentation
that motivated this migration; the other two are
`Step 12` rationale strings added in the previous
revision and intentionally kept as historical context).

### r07.0 Step 12 - Fix P02/P03 baseline seeding `LocalPath = ''` regression

Triggered by a failure observed on the freshly-pushed Step 11
commit, immediately after the ~13-minute Server 2016 ja-jp
Eval ISO download succeeded:

```
[+] ISO downloaded: D:\UpdateWsi\source\iso\WS2016_ja-jp.iso
[*] Recorded ISO SHA-256: ceb4e1f786148782bd684853bda9c6177891da231eb0ca2b5a17130ec938b142
 -- Step 2: Patches ---------------------------------------------
 PHASE P04  -> FAILED   elapsed: 13m5.9s
 [X] Phase P04 (FetchAssets) failed:
     引数が空の文字列であるため、パラメーター 'LiteralPath'
     にバインドできません。
 [~]     Invoke-FetchPhase04_FetchAssets, Update-WindowsServerIso.ps1: line 8782
```

Line 8782 of P04 reads `$leaf = Split-Path -LiteralPath
$p.LocalPath -Leaf`, and the `$p.LocalPath` field of the first
patch entry was an empty string. The regression was introduced
in Step 9 when this CHANGELOG noted that P02's NeutralPatches
lookup had been fixed - the lookup itself was fixed, but the
*seeding* loop that converts `PatchBaseline.NeutralPatches[]`
into `$Script:ResolvedPatches` was carried over with
`LocalPath = ''` hard-coded, the very bug it should have
replaced. The empty value propagated through the baseline
into the first iteration of the P04 download loop, where the
`Split-Path -LiteralPath` call rejected it.

The bug only surfaces with `-UseBaselineOnly` because the
other patch-source paths (`-PatchUrls`, `-PatchDirectory`,
`-ManifestPath`) each compute LocalPath inline before adding
the entry to `$resolved`. With `-UseBaselineOnly` on, the
NeutralPatches-seeding path is the *only* place LocalPath
gets set, and the bug had no escape valve.

Two seeding sites carried the same defect: the P02 baseline
seeding at L8438-8447 and the P03 RefreshPatchBaseline
re-derive at L8704-8716. Step 12 fixes both with the same
helper shape so they stay in lockstep through any future
refactoring:

- `LocalPath` is derived from `$p.FileName` when present
  (the NeutralPatches schema since v3.x always emits
  FileName), falls back to
  `[System.IO.Path]::GetFileName(([Uri]$p.DownloadUrl).AbsolutePath)`
  for legacy entries that omit FileName, and finally falls
  back to `'<KbId>.msu'` if both are missing. The full path
  becomes `Join-Path $Script:PatchesDir (Join-Path
  $Script:OsVersion $pFileName)`, matching the other seeding
  paths in the same function (L8362 and L8375 see the same
  Join-Path shape).
- `ExpectedHashes` is built incrementally - it starts as
  `@{}` and only gets a `sha-256` key when `$p.Sha256` is
  non-empty. The previous code wrote
  `@{ 'sha-256' = $p.Sha256 }` unconditionally, so an empty
  baseline hash produced a hashtable with `.Count = 1` that
  forced P04's cache-validation branch to call
  `Test-PatchIntegrity` against the empty string instead of
  taking the 'no hash to verify; skipping download' fast
  path. That dormant bug would have surfaced on the second
  invocation after a cache existed.

Live verification awaits the operator's re-run of the same
PrepareBuildVerify command. P04 Step 1 (ISO download) is
already cached from the previous 13-minute fetch, so the
next run should reach Step 2 (Patches) within seconds. The
expected behaviour: `[1/2] windows10.0-kb5087537-x64_...msu`
shown by Write-Step, then a ~1.5 GB LCU download for KB5087537
followed by a ~70 MB .NET CU download for KB5087065, after
which P05 ExpandIso takes over and starts unpacking the ISO.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - Two patch-seeding sites updated to compute LocalPath
    from FileName and to build ExpectedHashes only when
    Sha256 is non-empty. Surrounding code unchanged.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.17 (P02/P03 LocalPath derivation +
    ExpectedHashes guard) and the matching matrix row.

No data files, workflows, or tests are touched.

### r07.0 Step 11 - Replace flaky `microsoft/psscriptanalyzer-action` with inline PSScriptAnalyzer+ConvertToSARIF (CI hardening)

Triggered by a stage2 Windows-checks workflow failure observed on
the freshly-pushed Step 10 commit:

```
[PSSA-pwsh51] Run microsoft/psscriptanalyzer-action
  Install-Package: No match was found for the specified search criteria
                   and module name 'ConvertToSARIF'.
                   Try Get-PSRepository to see all available registered
                   module repositories.
Error: Process completed with exit code 1.
```

The PowerShell script under analysis was untouched in Step 10 (the
commit was a data-only refresh of `Iso.Url` + `Iso.FwlinkUrl`), so
the failure was unrelated to the Step 10 content. Investigation
showed the failure mode is in the `microsoft/psscriptanalyzer-action`
Marketplace action itself, which has been observed failing
intermittently against PowerShell Gallery, including on Microsoft's
own CI of that action (workflow run 21604137629 on 2026-02-02).
The repository's README is also unmodified from the GitHub
template, which is a strong signal that the action is in a
semi-maintained state.

The root cause of the install failure is well-understood:
`Install-Module -Name ConvertToSARIF -Force` on a windows-latest
runner sometimes hits a NuGet provider or PSGallery registration
state that returns "no match" rather than a clear connectivity
error. Re-running the same workflow shortly after typically
succeeds, but that fragility is not acceptable for a release-
gating CI step.

This step replaces the action call in BOTH the stage1 (Linux
pwsh 7) and stage2 (Windows PS 5.1) workflows with an inline
two-step pipeline:

1. **Install step** - explicit TLS 1.2 enforcement, NuGet provider
   preflight (install `2.8.5.201+` if missing), PSGallery registration
   + trust, and a small `Install-ModuleWithRetry` helper that
   retries each `Install-Module` up to 3 times with exponential
   backoff. The helper skips installation entirely when
   `Get-Module -ListAvailable` already finds the module, which
   keeps re-runs fast.

2. **Run step** - `Import-Module ConvertToSARIF -Force`, then
   `Invoke-ScriptAnalyzer -Path ... -Settings ... | ConvertTo-SARIF
   -FilePath pssa.sarif`. Identical output shape to what the
   removed action produced, so the downstream
   `github/codeql-action/upload-sarif@v4` step and the SARIF text
   log generator both continue to work without changes.

Why inline instead of pinning to a maintained alternative
(`PSModule/Invoke-ScriptAnalyzer@v4` etc.): the analysis is four
real PowerShell commands (install + import + analyze + convert).
Inlining them is cheaper than depending on any third-party action
for that surface area, and lets us add the TLS / NuGet / retry
guards that the original action lacked. The Linux stage1 was not
yet exhibiting the failure but is updated to the same pattern for
defense in depth - the same PSGallery flake could hit any runner
at any time.

Files changed:

- `.github/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  - Replaced the `microsoft/psscriptanalyzer-action@v1.1` step
    with two inline steps (install with retry, then analyze).
    The `if:` scope guard
    (`scope == 'all' || scope == 'pssa-only' || ...`)
    is preserved on both new steps.
- `.github/workflows/scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  - Same replacement applied to the Windows-checks stage.

No PowerShell script, SPEC, README, data, or test files are
touched in this step. CI workflow changes are policy-recorded
here in CHANGELOG.md per the repository-wide invariant noted at
the top of this file (CI changes do not get their own commit
message in `.github/workflows/*` history alone).

Live verification awaits the operator's commit + push: the
stage1 run should complete with the new inline install logs
visible, and the chained stage2 should run to completion
without the `ConvertToSARIF not found` failure.

### r07.0 Step 10 - Refresh Eval ISO URLs for all 4 supported Server OSes; record fwlink (metalink) alongside direct CDN URL

Pure data refresh triggered by an HTTP 400 Bad Request from
P04 FetchAssets when downloading the Server 2016 ja-jp ISO:

```
PHASE P04 (FetchAssets) failed:
  リモート サーバーがエラーを返しました: (400) 要求が不適切です
  at Invoke-WebRequestWithRetry, line 1944
  Source URL: https://software-download.microsoft.com/download/sg/14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_JA-JP.ISO
```

The Microsoft Evaluation Center had retired the
`software-download.microsoft.com/download/sg/` host; live
verification with `software-static.download.prss.microsoft.com`
and `download.microsoft.com/download/E/0/9/...` (Server 2016
ja-jp specifically uses the legacy Download Center GUID path)
confirmed the new canonical URLs. Step 9's fixes to
`Invoke-WebRequestWithRetry` and the P02 NeutralPatches lookup
both proven correct - the function reached Microsoft and got a
clean HTTP 400 with three retry attempts in the expected
backoff cadence (2 s, 4 s, then bail), which is exactly the
behaviour intended by the retry wrapper.

This step refreshes the URL pool. For each of the 4 OSes
(Server2016, 2019, 2022, 2025) and 2 languages (en-us, ja-jp),
the `LanguageSpecific.<lang>.Iso` block now carries:

- `Url` - the **current** direct CDN URL (what the script
  actually downloads). Hosts vary per OS:
  - Server 2016 en-us:  `software-static.download.prss.microsoft.com/pr/download/`
  - Server 2016 ja-jp:  `download.microsoft.com/download/E/0/9/`
  - Server 2019 (both): `software-static.download.prss.microsoft.com/dbazure/988969d5-.../17763.3650.221105-1748...`
  - Server 2022 (both): `software-static.download.prss.microsoft.com/sg/download/888969d5-...`
  - Server 2025 (both): `software-static.download.prss.microsoft.com/dbazure/998969d5-.../26100.32230.260111-0550...`
- `FwlinkUrl` (NEW) - the canonical Microsoft fwlink metalink.
  For Server 2016 / 2019 / 2022, a single linkid serves both
  languages and the `clcid` query parameter selects the locale.
  For Server 2025 each language has its own linkid (2345730 for
  en-us, 2345828 for ja-jp). Recorded for documentation and as
  a recoverable starting point when the direct URL rotates
  again.
- `FileName` - updated to match the direct URL's basename. Two
  OSes saw a build refresh: Server 2019 from
  `17763.737.190906-2324.rs5_release_svc_refresh` to
  `17763.3650.221105-1748.rs5_release_svc_refresh`, and Server
  2025 from `26100.1742.240906-0331.ge_release_svc_refresh` to
  `26100.32230.260111-0550.lt_release_svc_refresh`. The codename
  suffix change for Server 2025 (`ge_release` to `lt_release`)
  reflects the underlying Windows codename rotation.
- `_VerifiedDate` and `_VerifiedBy` - set to `2026-05-26` and
  `manual:r07.0-Step10-IsoUrl-refresh` respectively, so the
  next stage5 / RefreshAllBaselines audit knows when and by
  whom each URL was last sighted live.

No script logic changes in this step. `Resolve-IsoSourceUrl`
still reads `Iso.Url` verbatim. A future opt-in
`-PreferFwlinkUrl` switch could let the script try the fwlink
first and fall back to `Url` on failure - the data shape
already supports it - but that path is deferred until live
URL rotations make it worth the extra HTTPS round trip per
download. The recorded fwlink remains useful immediately: when
a direct URL rotates, the operator can paste the fwlink into a
browser, follow the 302 redirect to the new direct URL, and
patch the config in one paste.

Files changed:

- `scripts/powershell/update-windows-server-iso/data/config-Server2016.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2019.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2022.json`
- `scripts/powershell/update-windows-server-iso/data/config-Server2025.json`
  - Updated `LanguageSpecific.{en-us,ja-jp}.Iso.{FileName,Url}`;
    inserted new `Iso.FwlinkUrl` field; bumped
    `_VerifiedDate` / `_VerifiedBy`.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  - Added section B.23.16 (dual-URL design + locale-mismatched
    clcid analysis + build-refresh notes) plus a matching row
    in the §B.23 cross-reference matrix.

Live verification awaits the operator's re-run of the same
PrepareBuildVerify command that hit the HTTP 400 - it should
now reach the ISO download successfully and continue through
P04 to P05 ExpandIso.

### r07.0 Step 9 - Fix P02 NeutralPatches lookup, fix P04 ISO/patch download path, polish ADK auto-install

Live regression-test of `-Action PrepareBuildVerify -EvalIsoMode
-UseBaselineOnly -AutoInstallAdk` against a freshly-provisioned
Windows Server 2025 host surfaced three issues. Step 8's
`-AutoInstallAdk` switch worked perfectly (oscdimg.exe was
downloaded + installed in ~30 seconds and P01 / P02 / P03 all ran
to completion). But the test then exposed two pre-existing latent
bugs in the script + one cosmetic redundancy that Step 8
introduced. All three are fixed together in this step.

**Fix 1 - P02 reads `PatchBaseline.NeutralPatches[]` (was `.Patches`)**.

`Invoke-SetupPhase02_ResolveInputs` was still looking at
`$Script:OsProfile.PatchBaseline.Patches` for the
`-UseBaselineOnly` code path, but the field name was migrated to
`NeutralPatches` as part of the r07.0 data layout (committed via
`-Action RefreshAllBaselines` / stage5). The result was that
`-UseBaselineOnly` consistently produced `Patch list resolved: 0
entries` on every config that had ever been refreshed, silently
forcing P02 into an empty patch plan and making the eventual
ISO build skip every patch entirely. The fix prefers
`.NeutralPatches[]` (the SPEC B.23.5 source of truth) and falls
back to legacy `.Patches[]` for backward compatibility with any
config not yet migrated.

**Fix 2 - `Invoke-WebRequestWithRetry` now accepts `-OutFile`,
`-Headers`, and the `-MaxAttempts` alias**.

The wrapper function declared only `-Uri / -MaxRetries /
-TimeoutSec`, but every one of its three call sites (P04 source
ISO download, P04 patch download, P06 wsusscn2.cab download)
called it with `-OutFile`, and two of them with the alias
`-MaxAttempts`. The mismatch had been latent because none of those
download paths had ever been taken to completion against a real
host with a populated baseline. Step 7's `-UseBaselineOnly` plus
Step 8's `-AutoInstallAdk` together made it the first real
end-to-end run, and `Invoke-WebRequestWithRetry` threw immediately
on first use:

```
PHASE P04 (FetchAssets) failed: パラメーター名 'OutFile' に一致するパラメーターが見つかりません。
```

The fix extends `Invoke-WebRequestWithRetry` with proper
`-OutFile` support (streaming to disk with the canonical
`$ProgressPreference = 'SilentlyContinue'` workaround for PS 5.1's
multi-GB Invoke-WebRequest progress-bar slowdown), `-Headers`
support (used by the wsusscn2.cab path for a custom User-Agent),
and a `-MaxAttempts` alias for `-MaxRetries`. The function also
no longer references undefined `$Script:UserAgent` and
`$Script:RequestHeaders`, which would have caused an Invoke-
WebRequest argument-binding error in the in-memory mode if it had
ever been called.

**Fix 3 - polish `Install-WindowsAdkFallback` to avoid double
SHA-256 advisory**.

The Step 8 implementation called `Resolve-OscdimgExe` twice in
the auto-install path: once inside `Install-WindowsAdkFallback`
for the tool-presence verify, and once again in the P01 Step 3
`catch` block for the canonical Write-Ok log line. Each call
emits the Microsoft reference-hash SHA-256 advisory when the
local oscdimg.exe doesn't match the v1.4 reference value, so the
warning block was logged twice for the same binary. The fix:
`Install-WindowsAdkFallback` now returns the discovered
`oscdimg.exe` path, and P01 Step 3 uses the returned value
directly with a single Write-Ok rather than re-resolving.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  - P02 patch-resolution block: read `NeutralPatches[]` (preferred)
    or `Patches[]` (legacy fallback); update log message and
    error message accordingly.
  - `Invoke-WebRequestWithRetry`: add `-OutFile`, `-Headers`,
    `-MaxAttempts` alias; drop dead `$Script:UserAgent /
    $Script:RequestHeaders` references; declare `[OutputType()]`.
  - `Install-WindowsAdkFallback`: return `[string]` (resolved
    path) instead of `[void]`; declare `[OutputType([string])]`.
  - P01 Step 3 auto-install branch: consume the return value;
    remove the now-redundant second `Resolve-OscdimgExe` call.

Regression coverage. T2-T10 all pass (their PowerShell-from-Python
harness does not exercise P02 / P04 / Install-WindowsAdkFallback,
so the data-format and PoC-replacement assertions are unaffected).
psa.py reports 0/0/0; PSScriptAnalyzer reports 0 errors and 0
warnings. End-to-end verification awaits the operator's re-run on
the Windows Server 2025 host.

### r07.0 Step 8 - `-AutoInstallAdk` switch for hands-free Windows ADK Deployment Tools install

Pure environment-provisioning addition triggered by a live P01 abort
on a freshly-provisioned Windows Server 2025 host that lacked the
Windows ADK Deployment Tools (`oscdimg.exe`). The previous P01 Step 3
behaviour was correct (fail fast before the 5-6 GB Evaluation ISO
download in P04) but required an out-of-band install before any
real ISO build attempt. Step 8 makes the install optional and
automatic via a new opt-in switch.

The implementation mirrors the SDK/WDK fallback pattern in the
sibling [`Deploy-AMDChipsetDriverOnWindowsServer.ps1`](https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/blob/main/Deploy-AMDChipsetDriverOnWindowsServer.ps1)
script — `Install-WindowsSdkFallback` /
`Install-WindowsWdkFallback` at ~L5408-5449 of that script.
Specifically:

1. Download a pinned `adksetup.exe` (Microsoft Learn fwlink
   `linkid=2289980`, ADK `10.1.26100.2454` December 2024) to a
   cache directory.
2. Run with `/features OptionId.DeploymentTools /quiet /norestart
   /ceip off /log <log>` to install only the Deployment Tools
   feature (~50-80 MB) — never the full ADK (~3+ GB).
3. Verify by tool presence rather than trusting the exit code,
   because installer EXEs in this family return non-zero when the
   kit is already on the machine. "Tool present + non-zero exit"
   is logged as warn-only "already installed"; only "tool still
   absent" is a hard failure.

The Decemnber-2024 ADK is the right pin for any Server x64 build
host: Microsoft Learn documents it as supporting Server 2025,
Server 2022, and every earlier supported Windows 10/11 release,
and the Deployment Tools binary is forward-compatible — oscdimg
from this ADK assembles ISOs targeting Server 2016 / 2019 / 2022 /
2025 without per-target-OS variants. The newer ADK
`10.1.28000.1` (November 2025) is Windows 11 26H1 Arm64 only and
explicitly NOT appropriate for Server work.

**Default off, opt-in only**. Without `-AutoInstallAdk`, P01 still
throws — but the error message now includes the canonical download
URL, the silent-install command line, and the expected oscdimg.exe
path, so operators in locked-down or air-gapped environments have
everything they need on screen to install the ADK out-of-band.

The existing `Resolve-OscdimgExe` (with its
`Make2023BootableMedia.ps1` v1.4 hash-verification block) is
unchanged and continues to apply to the auto-installed binary.
A hash mismatch remains advisory because ADK servicing patches
can legitimately change the SHA-256 of `oscdimg.exe`.

Files changed:

- `scripts/powershell/update-windows-server-iso/Update-WindowsServerIso.ps1`
  — Added `$Script:AdkInstallerUrl`/`Version`/`OptionId` constants,
  the `-AutoInstallAdk` switch + Script-scope propagation, the new
  `Install-WindowsAdkFallback` function (~120 LOC), and P01 Step 3
  catch-block branching to honour the switch + emit the improved
  error message when not set.
- `scripts/powershell/update-windows-server-iso/SPEC.md`
  — Added §B.23.15 (design notes: pinning rationale, opt-in by
  default, feature-restricted install, verify-by-tool-presence,
  cache placement) and a matching row in the §B.23 cross-reference
  matrix.
- `scripts/powershell/update-windows-server-iso/README.md`
  and `README.ja.md` — Added a Troubleshooting subsection
  documenting the `-AutoInstallAdk` switch alongside the existing
  PowerShell 5.1 / Administrator / DISM prerequisites.

Existing T2-T10 regression tests are unchanged: all 6 test files
(`catalog_fixture_test.py`, `catalog_title_tokens_test.py`,
`dotnet_cu_parser_test.py`, `dynamic_update_cache_test.py`,
`release_info_parser_test.py`, `release_info_resolver_test.py`)
still pass, because Step 8 lives entirely in the P01 prerequisite
layer and does not touch any release-info / dotnet-cu / DU code
paths. psa.py reports 0/0/0; PSScriptAnalyzer reports 0 errors
and 0 warnings.

### r07.0 Step 7 - Server 2016 LCU vs .NET CU same-KB dedup in the discovery layer

Bug-fix and SPEC-formalisation commit triggered by live verification
of Step 6's RefreshSnapshots -> RefreshAllBaselines pipeline against
the 2026-05 Patch Tuesday data on a clean Windows host. The pipeline
populated `data/cache-release-info.json` + `data/cache-dotnet-cu.json`
correctly and produced the expected per-OS NeutralPatches[] counts
for Server 2019 / 2022 / 2025, but Server 2016 emitted three entries
where SPEC §B.23.5 expects two: a Type=LCU record for KB5087537 plus
two Type=DotNet.Runtime records (KB5087537 again, KB5087065). Forensic
inspection showed the duplicate KB5087537 .NET CU record pointed at
the **same .msu file** as the LCU record -- same FileName, same
DownloadUrl, same SHA256, same UpdateId, same Supersedes list -- with
only the `Type` value differing.

**Root cause**. Microsoft Learn's `.NET Framework release-notes`
page for 2026-05 contains the row pair

```
| **Windows 10 1607 and Windows Server 2016** |  |
| .NET Framework 3.5, 4.6.2, 4.7, 4.7.1, 4.7.2 | [5087537](.../kb/5087537) |
| .NET Framework 4.8 | [5087065](.../kb/5087065) |
```

where `KB5087537` is the same KB as the Server 2016 monthly LCU in
`windows-server-release-info`. This is not a Microsoft-side mistake:
the Windows 10 1607 / Server 2016 era LCU follows a "sliced
cumulative update" design where the LCU literally embeds the
.NET 3.5 / 4.6.2 / 4.7.x cumulative-update payload as OS components,
and only .NET 4.8 is shipped as a separate `KB5087065` .msu. The .NET
release-notes faithfully reflects this design. Server 2019 / 2022 /
2025 split the .NET CU into independent KBs and do not exhibit this
overlap (verified live: zero KB overlap across LCU + .NET CU rows for
those three OSes in 2026-05).

**Fix**. Single insertion in
`Get-PatchSetFromReleaseInfoDiscovery` (the pure-cache discovery
half of `Resolve-PatchSetFromReleaseInfo`): immediately before the
`.NET CU from dotnet-cu cache` section, build a
case-insensitive `HashSet[string]` of the LCU `KbId` values already
appended to the discovery record list; inside the per-row .NET CU
loop, skip any row whose `KbId` is present in that set, emitting a
`Write-Verbose` log line citing SPEC §B.23.5 B-3 for forensic
visibility. The skipped row remains verbatim in
`data/cache-dotnet-cu.json` -- the cache is the authoritative
Microsoft snapshot; the dedup is a policy decision applied at
read time, not a destructive cache filter, so a future SPEC
revision can revisit the policy without re-fetching.

Total PS1 change: ~30 lines (1 HashSet construction block + 1
per-row guard + verbose log). No new function. No schema change.

**Resulting behaviour, live verified against the 2026-05 cache**:

```
Server2016   Discovery before fix : 3 records  (LCU + 2 DotNet.Runtime)
Server2016   Discovery after fix  : 2 records  (LCU + 1 DotNet.Runtime)
             KB5087537 appears once (Type=LCU); KB5087065 appears once (Type=DotNet.Runtime)
Server2019   Discovery (unchanged): 3 records  (LCU + 2 DotNet.Runtime)
Server2022   Discovery (unchanged): 4 records  (LCU + 2 DotNet.Runtime + DU.SafeOs)
Server2025   Discovery (unchanged): 3 records  (LCU + 1 DotNet.Runtime + DU.SafeOs)
```

The Server 2016 NeutralPatches[] count now matches the SPEC §B.21.2
per-OS expected count table: 2 entries (1 LCU + 1 .NET CU), not 3.

**SPEC update**. A new sub-decision **B-3 (LCU vs .NET CU same-KB
dedup)** has been added to SPEC §B.23.5 between B-2 and the
existing Consequences block. The new sub-decision documents:

- Context: the Microsoft Learn release-notes row pair that triggers
  the overlap, with the canonical 2026-05 Server 2016 example
  inline.
- Decision: LCU is the authoritative source for any KB it carries,
  with the rationale that (a) LCU's Catalog row exposes the canonical
  two-.msu resolution that the resolver relies on for SPEC B.23.5
  B-1 combined-LCU detection, and (b) the .NET re-listing carries
  no information the LCU does not already provide.
- Implementation: location, mechanism, forensic visibility via
  `Write-Verbose`, and the non-destructive cache property.

The "Consequences" heading at the end of §B.23.5 has been updated
to reference B-1, B-2, and B-3 together.

**T10 regression coverage**. `tests/release_info_resolver_test.py`
gains a new scenario in `tests/fixtures/release_info_resolver/
scenarios.json`:

- `release_info_cache.MonthlyReleases[]` gets a Server 2016 row
  (KB5087537, 2026-05 B).
- `dotnet_cu_cache.Months[2026-05].Entries[]` gets the
  `OsNormalised=Server2016` block with the duplicate-KB row pair
  exactly as captured live (KB5087537 for .NET 3.5/4.6.2/4.7.x,
  KB5087065 for .NET 4.8).
- `du_entries_by_os.Server2016 = []` for symmetry with Server 2019.
- A new `queries[]` entry expects `record count = 2`,
  `Types = [LCU, DotNet.Runtime]` (KB5087537 once as LCU,
  KB5087065 once as DotNet.Runtime).

T10 assertion total: 18 -> 22 (+4 from the new scenario). The
T10 inventory row in SPEC's "Part G test inventory" has been
updated accordingly.

**No breaking change**. The existing `data/config-Server2016.json`
committed at HEAD is not modified by this commit (the Refresher
writes it on next run). `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0`; this is a Step 7 follow-on under
the same release rather than a new release. `data/raw-*.*` and
`data/cache-*.json` are unaffected -- the dedup is applied at
read time, not at cache-write time, so re-running A03
RefreshSnapshots is **not required** to take advantage of the fix.

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, **T10 22/22 (+4)**. Cumulative
112/112 PASS (up from 108/108 in r07.0 Step 6).

### r07.0 Step 6 - Implement `-Action RefreshSnapshots` (A03) and document the two-stage refresh workflow

Implementation gap closure for SPEC §B.23.7 / §B.23.14. The
previous r07.0 commits ported the parser / resolver logic into
the PowerShell main script and migrated the discovery layer to
cache-driven (`Get-PatchSetFromReleaseInfoDiscovery`,
`Resolve-PatchSetFromReleaseInfo`), but never wired the
cache-populating helpers (`Invoke-ReleaseInfoFetch`,
`Update-ReleaseInfoCache`, `Invoke-DotNetCuFetch`,
`Update-DotNetCuCache`, `Add-DynamicUpdateCacheEntry`) into a
user-facing Action. Live verification on a clean Windows host
exposed the gap: running `-Action RefreshAllBaselines` with no
caches present emitted "Discovery returned zero records" for
every OS, and the resulting `data/config-Server*.json` files
had empty `PatchBaseline.NeutralPatches[]`. This commit closes
the gap with the SPEC-blessed name (`RefreshSnapshots`).

**New functions in `Update-WindowsServerIso.ps1` (3)**:

- `Get-DynamicUpdateProbePlan` (helper) -- returns the per-OS
  DU probe target table. Restricted to Server 2022 + Server
  2025 (each with Setup + SafeOs) per SPEC §B.23.6; Server 2019
  has no DU rows in release-info and Server 2016 predates the
  modern "Dynamic Update" naming.
- `Invoke-AdminPhaseA03_RefreshSnapshots` (~290 lines) -- the
  A03 phase body. Three fault-tolerant sub-steps:
  1. release-info: `Invoke-ReleaseInfoFetch` ->
     `Update-ReleaseInfoCache`. Writes
     `data/raw-release-info.md` (+ `.meta.json`) and
     `data/cache-release-info.json`.
  2. .NET CU: `Invoke-DotNetCuFetch` ->
     `Update-DotNetCuCache`. Writes `data/raw-dotnet-cu.json`
     and `data/cache-dotnet-cu.json`.
  3. Dynamic Update probes: iterates the
     `Get-DynamicUpdateProbePlan` table; for each (OS, DuType),
     builds a Catalog Search.aspx query of the form
     `"<patchMonth> <DuLabel> for <OsToken>"`, calls
     `Get-UpdateIdFromCatalog`, narrows results via
     `Test-CatalogTitleMatch`, deduplicates with
     `Select-LatestPatchBySupersedence` when multiple hits
     survive, and persists each result (success or
     `IsEmptyMarker`) via `Add-DynamicUpdateCacheEntry`.
  Honours `-DryRun` (skips all HTTP fetches), honours
  `-PatchMonth` override for parity with A01. Emits an
  A01-style end-of-run summary with per-cache status, per-probe
  result, and a "next step" hint pointing at
  `RefreshAllBaselines`. Failure of one sub-step is logged but
  does not abort the remaining sub-steps. Returns `$true` iff
  every sub-step reported OK or Skipped.
- `Show-RefreshSnapshotsSummary` (helper) -- renders the rich
  end-of-run summary table block for A03, modelled on
  `Show-RefreshAllBaselinesSummary`.

**Wiring changes (5 single-line edits)**:

- Parameter `[ValidateSet]` on `$Action` -- added
  `'RefreshSnapshots'` between `'GenerateManifest'` and
  `'RefreshAllBaselines'`.
- `$osLessActions` array -- added `'RefreshSnapshots'` (A03
  operates on `data/` files, not on a specific OS x language
  ISO).
- `$Script:PhaseRegistry` -- added the A03 row mapping
  `Id='A03' / Name='RefreshSnapshots' / Group='Admin' /
  Func='Invoke-AdminPhaseA03_RefreshSnapshots'` immediately
  after A02.
- `Get-PhaseListByAction` switch -- added the
  `'RefreshSnapshots' -> [string[]]@('A03')` case.
- `Show-PhaseList` hardcoded action enumeration -- inserted
  `'RefreshSnapshots'` between `'GenerateManifest'` and
  `'RefreshAllBaselines'` so the `-Action ListPhases` output
  shows it.

**Pre-existing bug fix (drive-by, 3 occurrences)**:

- `Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`,
  `Get-SupersedenceFromCatalog` each had a retry path that
  called `Wait-WithJitter -BaseSeconds 2 -MaxSeconds 5`. The
  helper's actual parameter is `-JitterRange`, not
  `-MaxSeconds`; the typo silently bound `-MaxSeconds 5` to no
  parameter, leaving `$JitterRange` at its `[double]` default
  of 0, which made `Get-Random -Minimum 0 -Maximum 0` throw
  "The Minimum value (0) cannot be greater than or equal to
  the Maximum value (0)". The bug only fired on a retry path,
  so live operation seldom hit it; A03's DU probe loop
  reliably reproduced it because successive rapid Catalog hits
  triggered rate-limit retries. Fixed by replacing
  `-MaxSeconds 5` with `-JitterRange 1` (about 2s +/- 1s of
  jitter) at all three call sites.

**SPEC.md updates (3 sections)**:

- §B.23.7 -- the tentative "(`-Action RefreshSnapshots` or an
  equivalent name decided at implementation time)" phrasing
  has been replaced with the implemented form
  "(`-Action RefreshSnapshots`, implemented as the A03 Admin
  phase)".
- §B.23.14 -- the cross-reference matrix row for B.23.7 now
  reads `-Action RefreshSnapshots (A03, implemented r07.0
  Step 6)`. A new "A03 RefreshSnapshots implementation
  (completed in r07.0 Step 6)" subsection was added
  immediately before the existing PoC retirement subsection,
  summarising the sub-step composition, the DU probe target
  table rationale (Server 2022 + 2025 only per §B.23.6), and
  noting that the companion `stage5__data-snapshot.yml`
  workflow remains a small follow-up (modelled on
  `stage4__monthly-refresh.yml` with `RefreshAllBaselines`
  swapped for `RefreshSnapshots`) that requires no further
  PowerShell change.
- The runtime-flow numbered list in §B.23.14 step 1 now points
  at the implemented A03 phase rather than at a placeholder
  implementation name.

**README.md / README.ja.md updates**:

- The "Admin actions" section in both README files was
  rewritten to document the two-stage refresh as the canonical
  workflow: Stage 1 = `RefreshSnapshots`, Stage 2 =
  `RefreshAllBaselines`. The list of cache files Stage 1
  produces is enumerated, the new exit-code semantics for A03
  are explained, and a troubleshooting note tells operators
  who see "Discovery returned zero records" to run Stage 1
  first. The new CSV report path
  (`<WorkRoot>/logs/A03_RefreshSnapshots_report.csv`) is added
  alongside the existing A01 report path.

**Live verification on a clean working tree reproduced what
should now be the canonical workflow**:

1. `-Action RefreshSnapshots` populated all three cache
   families. release-info captured 471 monthly + 62 hotpatch
   rows (~68 KB raw, ~216 KB cache); .NET CU captured 29
   monthly pages with 254 entries total (~294 KB raw, ~110 KB
   cache); DU probes for 2026-05 returned KB5087595 (Server
   2022 / SafeOs) and KB5087588 (Server 2025 / SafeOs), with
   the (Server2022, Server2025) x Setup probes correctly
   recorded as `IsEmptyMarker` because Microsoft has not
   published Setup DU for 2026-05.
2. The subsequent `-Action RefreshAllBaselines` then produced
   non-empty `PatchBaseline.NeutralPatches[]` for every OS:
   Server2016 = 2 KBs, Server2019 = 3 KBs, Server2022 = 4 KBs
   (including the SafeOs DU), Server2025 = 4 KBs (including
   the SafeOs DU). This matches the per-OS expected count
   table in SPEC §B.21.2.

**No schema change. No breaking-config change**. Schema
versions are unchanged. `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0`; this is a Step 6 follow-on
under the same release rather than a new release. The
existing `data/config-Server*.json` files committed at HEAD
are not modified by this commit.

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS, unchanged from r07.0 Step 5.

### r07.0 Step 5 - CI workflow: catch-up rename from `Config/` to `data/` (this release)

Mechanical follow-up to r07.0 Step 1 (commit `b34241f`,
"Rename Config/ -> data/ and update references"). The Step 1
commit updated `Update-WindowsServerIso.ps1`,
`data/config-Server*.json`, SPEC.md, and several Markdown docs to
the new `data/` + three-prefix naming scheme, but missed three
stale path references inside two CI workflow files. The
`Validate Config JSON files` check in stage1 has been failing on
every PR since b34241f as a result; the failure surfaced visibly
on the workflow run for commit `7f7d400` ("Bump script to
r07.0"). This commit closes the gap.

**Files modified (2)**:

- `.github/workflows/scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  - `[Format] Validate Config JSON files` step:
    - `Path('.../update-windows-server-iso/Config')` ->
      `Path('.../update-windows-server-iso/data')`
    - required set `{'Server2016.json', ..., 'Server2025.json'}`
      -> `{'config-Server2016.json', ..., 'config-Server2025.json'}`
    - both `glob('*.json')` calls narrowed to
      `glob('config-Server*.json')` (so non-config JSON files
      under `data/` such as future `cache-*.json` or `raw-*.json`
      do not get force-validated as OS configs)
    - error message text updated from "missing Config files"
      to "missing OS config files under data/"
- `.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`
  - `Detect Config diffs` step (line 198):
    `$configRel = '.../Config'` -> `$configRel = '.../data'`
  - `Show full diff (for log archival)` step (line 225): same
    one-line update
  - The existing `add-paths: scripts/.../data/config-*.json`
    argument to `peter-evans/create-pull-request@v8` was already
    on the new path and is unchanged

**Downstream consequences resolved**. The same workflow run that
hit the Config-JSON validation failure also reported two
`Path does not exist` errors when the `[psa.py] Upload SARIF to
Code Scanning` and `[PSSA-pwsh7] Upload SARIF to Code Scanning`
steps tried to upload `psa.sarif` and `pssa.sarif`. These were
not independent failures: the `Validate Config JSON files`
failure short-circuited the SARIF generation steps (which run
under a `success()`-implying conditional), and the upload steps
(which carry `if: always()`) then ran against absent paths. With
the validation step passing again, both SARIF generation steps
run and produce their files, and the uploads succeed.

**Local verification**.

- `python3` extraction of the updated `Validate Config JSON
  files` block executed against
  `scripts/powershell/update-windows-server-iso/data/` returns
  `OK` for all four `config-Server*.json` files (Schema=2.1,
  Build values 14393 / 17763 / 20348 / 26100, both `en-us` and
  `ja-jp` language nodes present).
- `python3 -c "import yaml; yaml.safe_load(open('<file>'))"`
  passes for both modified workflow files.
- Repository-wide grep for stale `Config/` or `/Config[^a-z]`
  references inside `.github/workflows/*.yml` returns zero hits
  after the change.

**No production-code change**. `Update-WindowsServerIso.ps1` is
not modified by this commit; it has had zero references to the
old `Config/` path since r07.0 Step 1. Schema versions are
unchanged. `$Script:ScriptVersion` stays at
`update-wsi-2026.05.26-r07.0` (this is a CI hygiene fix, not a
functional change, so SemVer is not affected).

**Quality-gate status**: psa.py 0/0/0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS, unchanged from r07.0 Step 4.



Mechanical cleanup commit scheduled by SPEC §B.23.14. With the
parser / resolver logic now living in `Update-WindowsServerIso.ps1`
and regression coverage owned by T6-T10, the `poc_<topic>_*`
scripts and their disposable fixtures / snapshots have served
their purpose. This commit removes them as a single atomic step.

**Deleted from the repository**:

- `tests/poc_release_info_01_fetch.py`,
  `tests/poc_release_info_02_parse.py`,
  `tests/poc_release_info_03_analyse.py`,
  `tests/poc_release_info_04_resolve.py`
- `tests/poc_dotnet_cu_01_fetch.py`,
  `tests/poc_dotnet_cu_02_parse.py`
- `tests/poc_dynamic_update_01_probe.py`
- `tests/fixtures/poc_release_info/` (5 disposable derived
  files: `baseline-month-detection.json`,
  `coverage-summary.json`, `letter-frequency.json`,
  `resolve-sample.json`, `update-type-summary.csv`)
- `tests/fixtures/poc_dotnet_cu/` (2 files:
  `release-notes-index.json`, `sample-month.json`)
- `tests/fixtures/poc_dynamic_update/` (1 file:
  `probe-results.json`; T8 already owns its own
  `tests/fixtures/dynamic_update_cache/probe-results.json`
  derived from the 2026-05-26 live captures)
- `tests/snapshots/poc_dotnet_cu/` (4 files; T7 already owns
  `tests/snapshots/dotnet_cu/` with the same shape sourced from
  fresh live captures)
- `docs/poc/` (the entire directory; contents survive under
  `docs/history/` after the rename described below)

**Moved (kept under a new permanent name)**:

- `tests/fixtures/poc_release_info/release-info.json`
  -> `tests/fixtures/release_info/release-info.json`
- `tests/snapshots/poc_release_info/release-info-2026-05-25.md`
  -> `tests/snapshots/release_info/release-info-2026-05-25.md`
- `tests/snapshots/poc_release_info/release-info-2026-05-25.meta.json`
  -> `tests/snapshots/release_info/release-info-2026-05-25.meta.json`
- `tests/snapshots/poc_release_info/.gitattributes`
  -> `tests/snapshots/release_info/.gitattributes` (preserves
  the `*.md -text` rule that keeps Microsoft Learn snapshots
  bit-perfect)
- `docs/poc/poc-release-info-readme.md`
  -> `docs/history/release-info-readme.md`
- `docs/poc/poc-release-info-report.md`
  -> `docs/history/release-info-report.md`
- `docs/poc/poc-dotnet-cu-report.md`
  -> `docs/history/dotnet-cu-report.md`
- `docs/poc/poc-dynamic-update-report.md`
  -> `docs/history/dynamic-update-report.md`

**Code updates**:

- `tests/release_info_parser_test.py` (T6): two path constants
  retargeted from `tests/{fixtures,snapshots}/poc_release_info/`
  to `tests/{fixtures,snapshots}/release_info/`; docstring
  updated to point at the new permanent location and the
  historical record under `docs/history/`. No behavioural
  change; T6 still asserts the same 13 invariants.
- `tests/dotnet_cu_parser_test.py` (T7): docstring comment that
  referenced the now-deleted `tests/snapshots/poc_dotnet_cu/`
  was rewritten to point at `docs/history/dotnet-cu-report.md`
  instead.

**Documentation updates** (SPEC.md / tests/README.md):

- SPEC.md §B.22 (file organisation): directory tree updated to
  show `docs/history/` instead of `docs/poc/`; key-points list
  rewritten to describe the post-cleanup state; §B.22.2 prefix
  table marks `poc_` as a reserved pattern for future PoC use
  (not currently present in the repo) and adds a row for
  `docs/history/`; §B.22.3 worked-examples table replaces the
  deleted PoC files with current production examples
  (`release_info_parser_test.py`,
  `release_info_resolver_test.py`,
  `docs/history/release-info-report.md`).
- SPEC.md §B.23.12: stale reference to
  `poc_release_info_03_analyse.py` rewritten as a historical
  note pointing at `docs/history/release-info-report.md`.
- SPEC.md §B.23.14: "PoC promotion to T6-T8" section rewritten
  as "PoC retirement (completed in r07.0)" describing the
  achieved state (scripts deleted, fixtures/snapshots renamed
  or deleted as appropriate, reports moved to `docs/history/`).
- SPEC.md Part G: T6 and T7 row descriptions updated to point
  at the new paths and at `docs/history/` for the historical
  record. The "Adjunct: PoC scripts under `tests/`" section was
  rewritten as "Adjunct: retired r06 Phase 2 PoC" summarising
  the migration.
- SPEC.md §B.21.2 / §B.21.5 / others: scattered
  `docs/poc/poc-*-report.md` URLs updated to the new
  `docs/history/*-report.md` paths.
- `tests/README.md`: the "PoC scripts (r06.0+, time-bounded)"
  section was replaced by a short "Retired r06 Phase 2 PoC"
  paragraph that records the migration outcome.

**No production-code change**. `Update-WindowsServerIso.ps1` is
not modified by this commit; it has had zero references to the
PoC paths since r07.0 Step 2b. Schema versions are unchanged.
`$Script:ScriptVersion` stays at `update-wsi-2026.05.26-r07.0`
(this is a documentation / repository-hygiene commit, not a
functional change, so SemVer is not affected).

**Sanity guarantees**:

- Zero `poc_` or `poc-` prefixed file or directory remains
  anywhere under `tests/` or `docs/`.
- `tests/snapshots/release_info/.gitattributes` was carried
  forward, so the snapshot's bit-perfect CRLF endings remain
  protected against Git's default end-of-line normalisation.
- T6 still finds its snapshot under the new
  `tests/snapshots/release_info/` location and still asserts
  the same 13 invariants from the same `release-info.json`
  reference fixture.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13,
T7 16/16, T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108
PASS unchanged from r07.0 Step 3.

### r09.0 Step 1 follow-up (doc-renewal) - README/SPEC/TESTING reconstruction with implementation ground truth

This follow-up to the Step 1 Phase 6 SPEC rewrite is a **doc-only**
change that addresses regressions discovered when the post-rewrite
SPEC was compared against the actual script implementation
(`$Script:ScriptVersion = 'update-wsi-2026.05.27-r08.0'`). It also
addresses two longer-standing concerns raised on review of the
existing README/TESTING:

1. **The documents underspecified the script's purpose** — they
   described "what it does" without addressing "why this script exists",
   making it harder for both human readers and downstream LLM/AI
   consumers to anchor their work in the operational scenarios that
   motivated the script.
2. **The documents had accumulated drift relative to the script body**
   (Action list, Phase count, test inventory, data/ layout). Most of
   this drift originated when AI-tool-assisted edits updated only
   the CHANGELOG and not the surrounding documentation when the
   script changed.

### Regressions corrected in `SPEC.md`

The Phase 6 SPEC rewrite (commit c40755c) introduced four regressions
relative to the implementation, all corrected here:

1. **Part A bloated to 365 lines (governance violation)**. Per
   [`scripts/README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/README.md) "Standard SPEC Structure",
   Part A is the cross-project inherited layer maintained by the
   sibling SPEC ([`../download-speakerdeck-oracle4engineer/SPEC.md`](../download-speakerdeck-oracle4engineer/SPEC.md)
   sections A.1-A.14). The Phase 6 rewrite restated A.1-A.7 content
   verbatim instead of inheriting via reference. This introduced
   - drift risk (two copies of the same contract)
   - incomplete coverage (the bloated Part A did not include the
     sibling's A.6 Path Handling, A.9 CSV conventions, A.10
     Environment Evaluation, or A.14 Debug Trace Facility).

   **Fix**: Part A reduced to 53 lines, restated as an inheritance
   declaration pointing to the sibling SPEC sections A.1-A.14.

2. **§B.6 Action map omitted three implemented Actions**. The Phase 6
   rewrite listed 11 Actions while the script's `param() ValidateSet`
   (script L242-L243) declares 13. Missing: `BootTest`, `All`,
   `GenerateManifest`.

   **Fix**: §B.6 expanded to all 13 Actions in three groups (Standard
   pipeline / Specialty / Admin), each linked back to its
   implementation site (script line range).

3. **§C.9 Self-verification suite listed T1-T7 (T7 = planned)**. The
   actual `tests/` directory contains T1-T10, all implemented. The
   canonical T-numbering lives in
   [`tests/README.md`](./tests/README.md).

   **Fix**: §C.9 corrected to T1-T10 with the right assertion counts
   (T3 = 7 — not 10, T7 = `dotnet_cu_parser_test.py` = 16, T8 = 20,
   T9 = 18, T10 = 18). The previously-planned
   `wsusscn2_parser_test.py` is re-designated as planned T11
   (post-r09.0 Step 2 work).

4. **§B.20.1 `data/` layout described as `raw-<topic>/` directories**.
   The actual layout is flat: individual `raw-release-info.md`,
   `raw-dotnet-cu.json`, `cache-release-info.json`, etc.

   **Fix**: §B.20.1 corrected to flat layout; §B.20.2 prefix rules
   updated to add the `cache-` prefix family alongside `config-` and
   `raw-`.

### README/TESTING reconstruction (rationale)

The existing `README.md` / `README.ja.md` / `TESTING.md` were rewritten
zero-base rather than incrementally edited, because:

- The level of drift across all three documents (40-60% of content
  needing correction) made incremental editing slower and more
  error-prone than a fresh rewrite.
- The rewrite is anchored to a freshly-extracted **implementation
  ground truth**, derived directly from `param() ValidateSet`, the
  `Invoke-*Phase*` function inventory (script L8973-L11086), the
  `tests/README.md` canonical T-numbering, and the actual `data/`
  directory listing — not from older documentation.
- The README gained a new top-level **"Why this script exists"**
  section addressing the four operational scenarios (lab/test
  bring-up at scale, PCA2011 boot-manager cert expiry,
  air-gapped/offline labs, reproducible patch baselines) that the
  previous README only implied. A **"Reader's roadmap"** subsection
  adds motivation-based routing rules between
  README / SPEC / TESTING / CHANGELOG / root-level governance, mirroring
  the sibling project's structure.
- `TESTING.md` was restructured to match the sibling-project canonical
  §0-§8 pattern (status summary → static analysis → smoke tests →
  live probes → operator-pending → tool suite → CI → discovered bugs)
  rather than carrying ad-hoc subsections.

### Files changed

| File | Before | After | Note |
|:---|--:|--:|---|
| `SPEC.md` | 3,935 | 3,855 | Part A -312 / §B.6, §B.20, §C.9 expanded |
| `README.md` | 532 | 562 | full rewrite |
| `README.ja.md` | 508 | 551 | full rewrite, lock-step with `README.md` (H2=16/16, H3=11/11) |
| `TESTING.md` | 420 | 456 | full rewrite per sibling §0-§8 canonical |

### Self-check applied during the renewal

To prevent recurrence of the regression pattern from Phase 6, the
following guards were applied at execution time:

1. **Implementation ground truth was extracted first**, before any
   document was touched. The extraction artifact is preserved as
   reference during the renewal session.
2. **Each new section was tagged with the rule and the implementation
   site it corresponds to** (sibling SPEC section / `scripts/README.md`
   subsection / script line range / `tests/README.md` entry).
3. **Redundancy check**: every Part A item that the sibling already
   covers was inherited via reference, never restated. This is the
   anti-Phase-6-regression rule.
4. **Bilingual lock-step**: `README.md` and `README.ja.md` updated
   together, structurally aligned at H2 and H3 level.

### Not touched in this commit

The script body (`Update-WindowsServerIso.ps1`) carries documentation
that has also drifted from the current revision: the header `<#...#>`
comment block lists only nine phases, claims "baseline revision r01",
and omits Actions `BootTest` / `All` / `GenerateManifest` from its
`.PARAMETER Action` description. These are intentionally **out of
scope** for this doc-only commit; they will be corrected during the
r09.0 Step 2+ implementation cycles when the script body is otherwise
touched.

### r09.0 Step 1 follow-up 2 (governance cross-reference) - subproject docs reference repository-wide AGENTS.md

A small follow-up to the prior `r09.0 Step 1 follow-up (doc-renewal)`
entry above. The repository-wide [`AGENTS.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/AGENTS.md) — the
LLM-assisted contributor operating guide, introduced at the
repository root in the same Step 6 governance cycle — is now
referenced from this subproject's documentation:

- `README.md`: the "Reader's roadmap" section gains a bullet pointing
  to `../../../AGENTS.md` for LLM-agent operating guidance (governance
  hierarchy, ground-truth extraction, Doc-Touching Matrix, Part A
  inheritance rule, anti-patterns).
- `README.ja.md`: the same bullet in lock-step (Japanese mirror).
- `SPEC.md`: Part A gains a new subsection `A.x.0 — Rationale and
  forensic record (inheritance rule)` that points to
  `../../../AGENTS.md` §6 (the Part A Inheritance Rule) and §9 (the
  Anti-Pattern catalogue, including AP-1 which documents the
  `c40755c` Part A bloat regression that this SPEC's Part A
  correction in `8df9ff4` resolved). LLM agents extending or revising
  Part A MUST consult both references before touching it.

### Files changed

| File | Before | After |
|:---|--:|--:|
| `README.md` | 562 | 563 |
| `README.ja.md` | 551 | 552 |
| `SPEC.md` | 3855 | 3870 |

### Rationale

The Step 6 cycle introduced `AGENTS.md` at the repository root. Its
forensic value (in particular the §9 AP-1 / AP-9 entries) is highest
when LLM agents working in a Layer 3 SPEC can discover it via a
natural navigation path from the document they are currently editing.
Adding the references in `README.md` (operator-facing navigation) and
`SPEC.md` Part A (agent-facing rule rationale) closes that loop
without restating content (the canonical text lives in `AGENTS.md`,
not duplicated here).

### Not touched

- `TESTING.md` is unchanged. It already references SPEC.md Part C and
  Part D; the `AGENTS.md` link is reachable transitively through
  SPEC.md.
- The script body (`Update-WindowsServerIso.ps1`) is unchanged; this
  remains a doc-only commit.

## [update-wsi-2026.05.26-r07.0] - 2026-05-26

**r07.0 — Phase 3 implementation (release-info-driven refresher; breaking change).**

This is the consolidated r07.0 release that ships the SPEC.md Phase 3
architecture defined in section B.23. Per SPEC B.23.10 the directory
rename, schema bump and refresher rewrite are mutually dependent and
ship as one atomic release; reviewers should treat the whole r07.0
section below as a single coherent change. The release was assembled
incrementally across six commits, each individually quality-gated;
those commits are listed top-down below for traceability.

The minor-version jump from r05 to r07 (skipping r06 as a code release)
follows SemVer for breaking changes: `Resolve-PatchSetFromCatalog` and
`Get-CatalogQueryTemplate` have been deleted, three new cache file
types under `data/` have appeared, and the Config schema field set has
gained the `Common.CatalogTitleTokens` extension. r06.0 stays
exclusively a documentation release (the SPEC + PoC effort committed in
`2935dbd` and `36f4d65`).

The Patch-Tuesday-driven cache refresh automation (SPEC B.23.7 step 1-4
automated) is **NOT** included in r07.0 per SPEC B.23.10; r07.0 ships
manual-trigger only and the automation is deferred to r07.x.

Cumulative quality-gate status at release: psa.py 0 / 0 / 0,
PSScriptAnalyzer 0 findings, PowerShell parse OK, T2 13 / T3 10 /
T6 13 / T7 16 / T8 20 / T9 18 / T10 18 = **108 / 108 assertions pass**.

### r07.0 Step 3 - Version bump and r07.0 finalisation (this release)

Mechanical release-finalisation commit. No behavioural change; the
preceding Step 1 + 2a + 2b set is what r07.0 actually ships.

- `$Script:ScriptVersion` bumped from `update-wsi-2026.05.25-r05.1`
  to `update-wsi-2026.05.26-r07.0`. The script's identity string
  now reflects the SemVer minor-jump documented in SPEC B.23.10.
- `SPEC.md` section B.23.10's "(current)" marker moved from r05.1
  to r07.0. Other r05.1 references in SPEC remain because they
  document historical behaviour or comparisons that motivate the
  r07.0 design; they are not "current version" claims.
- `CHANGELOG.md` `[Unreleased]` block sealed into
  `[update-wsi-2026.05.26-r07.0] - 2026-05-26` with this release
  header. A fresh empty `[Unreleased]` block is added on top for
  future r07.x work.

Quality-gate status: psa.py 0 / 0 / 0, PSScriptAnalyzer 0 findings,
PowerShell parse OK, T2 13/13, T3 10/10, T6 13/13, T7 16/16,
T8 20/20, T9 18/18, T10 18/18. Cumulative 108/108 PASS unchanged
from Step 2b Commit 4.

### r07.0 Step 2b (Refresher main-path migration part) - Cache-driven Resolve-PatchSetFromReleaseInfo replaces Title-scrape discovery (this release)

This commit lands the **second half** of the Step 2b work scheduled
in SPEC.md section B.23.1. The r05.1-era `Resolve-PatchSetFromCatalog`
function and its `Get-CatalogQueryTemplate` helper are **deleted**;
a new cache-driven `Resolve-PatchSetFromReleaseInfo` takes over,
backed by an offline-testable `Get-PatchSetFromReleaseInfoDiscovery`
helper. This is the atomic completion of SPEC B.23.1's "complete
migration" decision: KB discovery is no longer a Title-string
heuristic against the Microsoft Update Catalog; the Catalog now
serves as a **URL resolver only** (KB → download URL plus
supersedence). DU discovery continues via the Step 2a 36-month
cache (now consumed by the new function); LCU discovery comes from
the Step 2a release-info parser; .NET CU discovery comes from the
Step 2a .NET CU parser. URL-resolver narrowing uses the Step 2b
Commit 3 Config-driven `Test-CatalogTitleMatch` helper.

**Important: the discovery layer was validated against synthetic
caches whose shapes were lifted verbatim from the fresh
2026-05-26 captures** under `tests/snapshots/dotnet_cu/` and
`tests/fixtures/dynamic_update_cache/probe-results.json`. No PoC
fixture was consulted. Live observations grounded three
implementation choices:

1. **Server 2022 / Server 2019 .NET CU multi-row** per SPEC B.23.5
   B-2: the live monthly pages list two `.NET Framework` rows
   under "Windows Server 2022" (one for 4.8, one for 4.8.1) and
   under "Windows 10 1809 and Windows Server 2019" (one for 4.7.2,
   one for 4.8). `Get-PatchSetFromReleaseInfoDiscovery` emits ONE
   discovery record per row, so each becomes its own PatchBaseline
   entry. T10 asserts this against a synthetic cache that mirrors
   the live shape.
2. **Server 2025 Setup DU suspended since 2025-12** per SPEC
   B.23.6: the discovery function does NOT emit a DynamicUpdate.Setup
   record when the per-OS DU cache has no in-window entry. The
   test scenario for 2025-12 (no matching caches) returns zero
   records, confirming the defensive path.
3. **Combined LCU + bundled SSU** per SPEC B.23.5 B-1: the new
   orchestrator passes the LCU's full Catalog file list through
   `Select-AllCanonicalPatchFiles` rather than the
   single-file picker, so an LCU UpdateId carrying both an
   LCU.msu and an SSU.msu emits two PatchBaseline entries (one
   with Type=LCU and IsCombined=$true, one with Type=SSU as
   classified by filename heuristic in
   `Convert-CatalogPatchToBaselineEntry`).

**Deleted PowerShell functions**:

- `Resolve-PatchSetFromCatalog` -- 311 lines. The r05.1 Title-string
  scraper. Its responsibility moves to
  `Resolve-PatchSetFromReleaseInfo`.
- `Get-CatalogQueryTemplate` -- 84 lines. The hardcoded per-OS
  query-template + title-token table. SSU/LCU/DU/.NET query
  templates are no longer needed (discovery moved to caches); the
  TitleTokens portion was already moved to Config + helpers in
  Step 2b Commit 3, so the entire function is now dead code.

**New PowerShell functions** (added before
`Resolve-LanguageSpecificPatchesFromCatalog` to keep the catalog
scrapers grouped, with the new release-info path immediately
above):

- `Get-PatchSetFromReleaseInfoDiscovery` -- pure-cache lookup,
  reads `data/cache-release-info.json` (LCU),
  `data/cache-dotnet-cu.json` (.NET CU), and
  `data/cache-du-<OsVersion>.json` (DU) via the existing
  Step 2a path helpers. Performs no network I/O. Accepts
  `-DataDir` for tests so T10 can exercise it against a temp
  directory. Validates `-PatchMonth` against
  `Test-DynamicUpdatePatchMonth` (the YYYY-MM regex helper from
  Step 2a). Returns `pscustomobject[]` with fields
  `Type` / `KbId` / `UpdateId` / `SourceCache` / `SourceRow` /
  `DiscoveryNote`.
- `Resolve-PatchSetFromReleaseInfo` -- orchestrator. Same signature
  as the deleted `Resolve-PatchSetFromCatalog` (OsVersion,
  OsLanguage, PatchMonth, MaxRetries), plus the new optional
  `-DataDir` for test isolation. Returns the same PatchBaseline
  entry shape as the deleted function. SSU emerges from the
  LCU's Catalog bundle via filename heuristic; standalone-SSU
  discovery is intentionally omitted (Microsoft has embedded
  SSU in LCU for current monthly releases per SPEC B.23.5 B-1).

**Caller migration** (three sites, single-line rename each):

- Refresher dispatch table (the
  `PatchBaseline.NeutralPatches.Refresher` registry near the top
  of the script): `'Resolve-PatchSetFromCatalog'` ->
  `'Resolve-PatchSetFromReleaseInfo'`.
- P03 RefreshPatchBaseline phase: the
  `Invoke-SetupPhase03_RefreshPatchBaseline` worker that runs
  during `-Action PrepareSet` now calls
  `Resolve-PatchSetFromReleaseInfo`.
- A01 RefreshAllBaselines admin phase: the
  `Invoke-AdminPhaseA01_RefreshAllBaselines` worker that runs
  during `-Action RefreshAllBaselines` now dispatches to
  `Resolve-PatchSetFromReleaseInfo` for OSes whose field-group
  Refresher matches.

The new function's parameter list is a strict superset of the old
(adds `-DataDir`); existing call sites need no parameter changes.
Net effect on the call graph is a single function-name swap.

**Test surface** changes:

- T3 (`tests/powershell_harness.py`) removed three test cases
  that targeted `Get-CatalogQueryTemplate` (Server2022 dual
  TitleTokens, per-OS Type coverage, Server2022 QueryTemplate
  no-comma form). The function no longer exists. TitleTokens
  coverage is taken over by T9 against the new
  `Get-CatalogTitleTokenList` helper. T3 now reports 10 assertions
  (down from 13); no other T3 case changed.
- T10 (`tests/release_info_resolver_test.py`) new. 18 assertions
  across four discovery scenarios (Server 2025 / 2022 / 2019 for
  2026-05, plus Server 2025 for 2025-12 with no matching caches)
  plus defensive cases (empty data dir, invalid PatchMonth).
  Fixture file is
  `tests/fixtures/release_info_resolver/scenarios.json`,
  shape-matched to the live 2026-05-26 captures.

**No PoC code or fixtures consulted**. T10's fixture KBs, OS
labels and DU UpdateIds were taken from the live captures used
by T7 (`tests/snapshots/dotnet_cu/`) and T8
(`tests/fixtures/dynamic_update_cache/probe-results.json`). The
historical PoC scripts and `tests/snapshots/poc_*/`,
`tests/fixtures/poc_*/` directories were not touched.

**Refresher main path NOW switched**. The migration that SPEC
B.23.1 schedules is complete: KB discovery is cache-driven (LCU
from release-info, .NET CU from .NET CU parser, DU from per-OS
36-month cache), and the Microsoft Update Catalog is consulted
only as a URL resolver. The combined Step 2a + Step 2b set is now
ready for `-Action RefreshAllBaselines` end-to-end runs against
the new path; the only remaining r07.0 schedulable item is the
Patch-Tuesday-triggered cache refresh automation (SPEC B.23.7
step 1-4), which is deferred to r07.x per SPEC B.23.10.

**Net code delta**: -395 lines (deleted 311 + 84) + 395 lines
(added 200 for Resolve-PatchSetFromReleaseInfo + 195 for the
discovery helper). The deletion and addition are intentionally
proportional so the diff is reviewable as one atomic migration.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 **10/10** (down from
13), T6 13/13, T7 16/16, T8 20/20, T9 18/18, T10 **18/18**.
Cumulative: 108/108 assertions.

### r07.0 Step 2b (URL-resolver narrowing part) - Config-driven Catalog title token disambiguation (previous release)

This commit lands the **first half** of the Step 2b work scheduled
in SPEC.md section B.23.1. New PowerShell helpers move the per-OS
Microsoft Update Catalog `TitleTokens` list out of hardcoded
PowerShell tables and into the OS Config (`data/config-Server*.json`,
field `Common.CatalogTitleTokens`), and add a single narrow-filter
predicate that combines those positive tokens with a hardcoded
negative exclusion list. The next commit (Step 2b part 2) will
replace `Resolve-PatchSetFromCatalog` with
`Resolve-PatchSetFromReleaseInfo` and delete the bulk of the
Catalog Title-string discovery code; this commit prepares the
ground by formalising the URL-resolver narrowing surface that
the new caller will consume.

**Important: the design and the tokens themselves were validated
against fresh live Microsoft Update Catalog data captured on
2026-05-26**, not lifted from any PoC fixture. Two specific live
observations grounded the implementation:

1. **Same-KB client-variant fan-out for Server 2016 / 2019**. A
   bare KB query for Server 2019's .NET CU (KB5087066) returns
   three hits: one for `Windows Server 2019` and two for
   `Windows 10 Version 1809` (the matching client-OS kernel).
   Server 2016 / Windows 10 1607 shows the same fan-out. The
   `Common.CatalogTitleTokens = ["Windows Server 2019"]` for
   Server 2019 (and the analogous Server 2016 entry) correctly
   rejects the Windows 10 client variants without needing a
   negative token.
2. **ARM64 contamination on Server 2025 .NET CU**. The live
   Catalog returns both `for x64` and `for arm64` variants of
   the same KB; the hardcoded
   `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
   list rejects the ARM64 variant case-insensitively.

**New PowerShell functions** (added to
`Update-WindowsServerIso.ps1` immediately before the existing
`Get-CatalogQueryTemplate`, inside the Microsoft Update Catalog
scraper section):

- `Get-CatalogTitleTokenList -OsVersion <name>` -- reads the OS
  Config and returns the `Common.CatalogTitleTokens` array.
  Returns an empty array when the field is absent (the SPEC
  default; the URL resolver then accepts the first matching hit).
  Tolerant of missing Config files (returns empty rather than
  throwing) so the function is safe to call from defensive paths.
- `Test-CatalogTitleMatch -OsVersion <name> -Title <title>` --
  predicate. Returns `$true` when the title matches the OS, i.e.
  contains ANY of the OS's positive tokens AND contains NONE of
  the `$Script:CatalogTitleNegativeTokens` negative tokens.
  Case-insensitive substring matching throughout. When the
  positive list is empty the predicate is permissive (still
  honours the negative list).

**New Script-level variable**:

- `$Script:CatalogTitleNegativeTokens = @('Windows 11', 'arm64')`
  -- the OS-uniform negative exclusion list. Hardcoded
  intentionally per SPEC B.23.2 because these exclusions are
  uniform across all in-scope OSes (every Server build rejects
  the Windows 11 client OS and the ARM64 architecture variant).

**Refactor of `Get-CatalogQueryTemplate`**: the per-OS
`TitleTokens` array literals were replaced with
`@(Get-CatalogTitleTokenList -OsVersion '<name>')` calls. The
function's return shape is unchanged -- `TitleTokens` is still a
`[string[]]` -- so all existing callers (Resolve-PatchSetFromCatalog
in particular) continue to work without changes. The Server2022
in-line comment was updated to point at SPEC B.23.2 and the
Config field as the source of truth.

**Behavioural delta from hardcoded -> Config-driven**:

- Server 2025: hardcoded list had 1 token; Config has 2.
  Permissive expansion -- old matches still match.
- Server 2022: hardcoded list had 2 tokens (both comma forms);
  Config has 3 (adds `Windows Server 2022`). Permissive expansion.
- Server 2019 / 2016: identical content in hardcoded and Config
  (single-token lists). No behavioural change.

In every case the refactor STRICTLY EXPANDS coverage and never
narrows it, so no existing successful Catalog scrape can become
a failure on the new path. (Future Microsoft naming changes can
now be absorbed by editing the Config file, not by shipping a
new PowerShell release.)

**Refresher main path NOT changed**. `Resolve-PatchSetFromCatalog`
and its callers (P03 RefreshPatchBaseline phase and A01
RefreshAllBaselines admin phase) continue to drive
-Action RefreshAllBaselines unchanged. Step 2b part 2 will
introduce `Resolve-PatchSetFromReleaseInfo` and delete the
Catalog Title-string discovery code in a single atomic commit.

**OS Configs NOT changed by this commit**. The
`Common.CatalogTitleTokens` field was already present in all
four `data/config-Server*.json` files (apparently pre-populated
during SPEC B.23.2 authoring). The values match what live data
2026-05-26 validates as correct, so no Config edits were needed.
T9 protects the values against future drift.

**New regression test**: `tests/catalog_title_tokens_test.py`
(T9). Covers 18 assertions across: per-OS token sourcing from
all four `data/config-Server*.json` (4 assertions), missing-Config
defensive empty-list default (1 assertion), and 13 live-captured
narrow-filter cases including positive matches for all four
OSes, same-KB client-variant rejection (Windows 10 1607 / 1809),
negative-token exclusion (arm64, Windows 11), and Server 2022's
both comma forms. **All 18 assertions pass** under PowerShell
7.4 on Ubuntu 24.

**New files committed to the repo**:

- `tests/fixtures/catalog_title_tokens/expected-tokens.json` --
  the per-OS expected token lists (the assertion ground truth
  for `Get-CatalogTitleTokenList`).
- `tests/fixtures/catalog_title_tokens/narrow-filter-cases.json`
  -- 13 live-captured Catalog hit titles with the expected
  match decision per OS. Each case is annotated with a
  description explaining which token or negative exclusion
  drives the decision.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20, T9 18/18. Cumulative: 93/93 assertions.

### r07.0 Step 2a (DU 36-month cache part) - Per-OS Dynamic Update cache and 36-month window selection (previous release)

This commit lands the **third half** of the Step 2a work scheduled
in SPEC.md section B.23.1. New PowerShell functions maintain a
per-OS Dynamic Update cache file (`data/cache-du-Server<NNNN>.json`)
that records Microsoft Update Catalog probe results across a
36-month rolling window, and select the latest in-window
successful publish at ISO-build time. The cache decouples
ISO-build runs from live Catalog scraping for DU discovery; an
out-of-band, Patch-Tuesday-triggered refresh action will
populate the cache in a later commit. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Catalog
URL-resolver narrowing remains scheduled for Step 2b.

**Important: the design was validated against live Microsoft
Update Catalog probes captured on 2026-05-26**, not against the
single-month PoC fixture under
`tests/fixtures/poc_dynamic_update/probe-results.json`. Twelve
`(OS, DU type, patch month)` combinations were probed across
2026-05 / 2026-04 / 2026-03. The live results confirmed SPEC
§B.23.6:

- **Server 2025 Setup DU**: 0 hits for all three months, with
  the canonical `id="ctl00_catalogBody_noResultText"` marker
  present in the HTML. This matches "Suspended since 2025-12,
  5+ months" in the §B.23.6 cadence table.
- **Server 2025 SafeOs DU**: published monthly
  (KB5087588 / KB5082237 / KB5078794).
- **Server 2022 DU**: published monthly (KB5087595 / KB5082243;
  the 2026-03 probe failed with a transient SSL error and was
  retried via the fixture's synthetic entries).
- **Server 2019 Setup DU**: 0 hits for all three months,
  confirming the "feature-update windows only" annotation in
  §B.23.6.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-DotNetCuCache` and the Microsoft Update Catalog
scraper section):

- `Get-DynamicUpdateCachePath` — path resolver per OS; accepts
  an optional `-DataDir` for tests.
- `New-EmptyDynamicUpdateCache` — fresh empty cache object for
  an OS with no persisted file yet.
- `Get-DynamicUpdateCache` — read the per-OS cache; **does not**
  throw on missing-file (returns an empty cache instead). This
  matches the "latest known good" stance from §B.23.6: an ISO
  build never aborts because a Patch-Tuesday refresh has not
  yet run for a given OS.
- `Save-DynamicUpdateCache` — persist with UTF-8 + LF + no-BOM,
  same conventions as the other r07.0 caches.
- `Test-DynamicUpdatePatchMonth` — validate `YYYY-MM` format.
- `Add-DynamicUpdateCacheEntry` — append-or-upsert one probe
  result. Same `(PatchMonth, DuType)` replaces in place
  (verified by the `upsert_same_key_latest_wins` T8 scenario);
  arrays use `@(...)` and Add-Member -Force pattern to avoid
  ConvertTo-Json single-element flattening.
- `ConvertTo-DynamicUpdatePatchMonthSortKey` — convert
  `YYYY-MM` to integer (yyyy*100+mm) for fast comparisons.
- `Get-DynamicUpdateWindowEarliestPatchMonth` — compute the
  earliest in-window month relative to a reference date;
  inclusive 36-month range (for `Now=2026-05` the earliest
  in-window month is 2023-06).
- `Get-LatestDynamicUpdate` — select the latest in-window
  successful entry for a given `(OsVersion, DuType)`; returns
  `$null` when no in-window entry has `Success=$true`. Window
  is anchored by `-Now` (default UTC now); tests pass a fixed
  `-Now` for reproducible assertions.
- `Remove-DynamicUpdateOutsideWindow` — drop entries earlier
  than the window; renamed from the proposed
  `Remove-DynamicUpdateOlderThan36Months` to satisfy
  PSScriptAnalyzer PSA6003's singular-noun rule (the "36" is
  baked into `Get-DynamicUpdateWindowEarliestPatchMonth`'s
  default).

**New Script-level variables**:

- `$Script:DynamicUpdateCacheWindowMonths = 36`
- `$Script:DynamicUpdateCacheSchema = '1.0'`

**Refresher main path NOT changed**. The existing Catalog scrape
in `Resolve-PatchSetFromCatalog` is unaffected. The DU cache is
populated and consumed by a separate code path that this commit
adds the data primitives for, but does not yet wire into a
production action; that wiring is scheduled for Step 2b.

**Testability hooks**. Every cache function accepts an optional
`-DataDir` parameter (default `''`) so T8 can route writes to a
temp directory without polluting `data/`. `Get-LatestDynamicUpdate`
and `Remove-DynamicUpdateOutsideWindow` accept an optional
`-Now` parameter (default `[datetime]::UtcNow`) so window
assertions are reproducible regardless of the wall clock. The
production path passes neither parameter and the defaults
restore the production behaviour exactly.

**Idempotent upsert**. `Add-DynamicUpdateCacheEntry` overwrites
any existing entry with the same `(PatchMonth, DuType)`. This
matters because the Patch-Tuesday refresh may probe the same
month multiple times during a single refresh cycle; only the
most recent probe should survive.

**Cross-OS isolation**. The per-OS cache file separation means
writes to `cache-du-Server2025.json` never affect
`cache-du-Server2022.json` and vice versa. Verified by the
`cross-OS isolation` scenario in T8.

**New files committed to the repo**:

- `tests/fixtures/dynamic_update_cache/probe-results.json` —
  the live Microsoft Update Catalog probe output from
  2026-05-26 (12 probe attempts, 8 successful, 1 SSL-error
  transient, 3 expected-empty confirmations per §B.23.6).
- `tests/fixtures/dynamic_update_cache/scenarios.json` —
  Python-generated reference scenarios combining the live probe
  entries with synthetic older months, plus the expected
  outcomes that PowerShell must reproduce.

**New regression test**: `tests/dynamic_update_cache_test.py`
(T8). Covers 20 assertions across three fixture scenarios
(server2025_live_then_setup_empty, server2022_with_old_synthetic,
upsert_same_key_latest_wins) plus three ad-hoc scenarios
(cross-OS isolation, missing-file empty cache, PatchMonth
validation rejection). Each scenario uses an isolated temp
directory via the `-DataDir` parameter and anchors the window
at `Now=2026-05-26T00:00:00Z`. **All 20 assertions pass** under
PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13,
T7 16/16, T8 20/20.

### r07.0 Step 2a (.NET CU part) - PowerShell parser and aggregated raw/cache for the .NET Framework release-notes (previous release)

This commit lands the **second half** of the Step 2a work
scheduled in SPEC.md section B.23.1. New PowerShell functions
fetch and parse the Microsoft Learn `.NET Framework release
information` index plus every monthly cumulative-update
release-notes page it references, writing an aggregated raw JSON
and a parsed cache JSON under `data/`. The existing Refresher
main path (`Resolve-PatchSetFromCatalog`) is **untouched** and
continues to drive `-Action RefreshAllBaselines`. The Dynamic
Update 36-month cache (per-OS `cache-du-Server<NNNN>.json`) and
the Catalog URL-resolver narrowing are scheduled for subsequent
r07.0 commits.

**Important: the data captured for the new parser was fetched
live from learn.microsoft.com on 2026-05-26**, not lifted from
the PoC snapshots under `tests/snapshots/poc_dotnet_cu/`. Doing
so surfaced two PoC-era assumptions that no longer hold against
current Microsoft Learn pages:

1. The index page now formats each entry as
   `- <DATE> - [<KIND>](<URL>)` (the date is **outside** the
   bracket pair and only the kind text is linked). The original
   PoC regex expected `- [<DATE> - <KIND>](<URL>)` and would
   match zero entries on the current page.
2. The monthly pages now place `## Summary tables` AFTER
   `## Known issues in this release`. The original PoC parser
   used `## Known issues` as the stop-marker for the
   tables-region walk, which on the current page would close the
   region before it ever opened. The new parser starts at
   `## Summary tables` and walks to the next `## ` heading or
   end-of-document.

The parser also tolerates the `**New Release**` badge that the
most-recent entry on the index carries, and preserves entries
whose strict %B date parse fails (the live index contains a
2024-10 entry typed "Octber 22, 2024" upstream).

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-ReleaseInfoCache` and the Microsoft Update Catalog
scraper section):

- `Get-DotNetCuRawPath` / `Get-DotNetCuCachePath` — path resolvers
  for the two new files under `data/`.
- `ConvertFrom-DotNetCuOsLabel` — maps the raw OS label printed
  in the release-notes table to a normalised short name (e.g.
  "Microsoft server operating system, version 24H2" -> `Server2025`).
  Order-sensitive substring matching: longer joint labels
  ("Windows 10 1607 and Windows Server 2016") win against the
  shorter pattern they contain.
- `Split-DotNetCuMarkdownFrontMatter` — strips the leading YAML
  block from a `?accept=text/markdown` response.
- `ConvertFrom-DotNetCuIndexMarkdown` — parses the index page;
  returns `EntryCount` / `Kinds` / `EarliestDate` / `LatestDate`
  / `Entries[]` with per-entry `DateText` / `Date` / `Kind` /
  `RelativeUrl` / `AbsoluteUrl`.
- `ConvertFrom-DotNetCuMarkdown` — parses a monthly page; emits
  `EntryCountTotal` / `EntryCountRecognised` / `RowsPerOs`
  (ordered hashtable) / `Entries[]` with per-OS-block `OsLabel`
  / `OsNormalised` / `OsOfferingKb` / `Rows[]`. Multiple
  sub-tables under the same `## Summary tables` heading are
  handled (current 2026-05 pages list three: Cumulative update,
  Security and quality rollup, .NET Framework 3.5 product
  update).
- `Invoke-DotNetCuFetch` — HTTPS fetch of the index URL plus
  every monthly URL it lists. Aggregates the bodies + HTTP
  headers + fetch timestamps into `data/raw-dotnet-cu.json`
  (UTF-8, LF, no-BOM). Per-month fetch failures are recorded as
  `Ok=false` entries with the error message so a single broken
  month does not lose the whole refresh.
- `Update-DotNetCuCache` — reads `raw-dotnet-cu.json`, runs both
  parsers, writes `data/cache-dotnet-cu.json`. Returns the cache
  path.
- `Get-DotNetCuCache` — reads `cache-dotnet-cu.json` for
  Refresher consumers. Throws if the file is missing.

**New Script-level variables**:

- `$Script:DotNetCuIndexUrl` — the index URL with the
  `?accept=text/markdown` query.
- `$Script:DotNetCuUrlBase` — used by the index parser to
  reconstruct absolute URLs from relative paths.
- `$Script:DotNetCuUserAgent` — a descriptive User-Agent string
  identifying this subproject.
- `$Script:DotNetCuOsLongToShort` — an ordered hashtable mapping
  the long OS label substrings to the short names.

**Refresher main path NOT changed**. The existing path
(`Resolve-PatchSetFromCatalog`, `Get-CatalogQueryTemplate`,
`Get-UpdateIdFromCatalog`, the Refresher action workers) is
unaffected by this commit. Switching the Refresher to consume
`cache-dotnet-cu.json` instead of live-scraping is scheduled for
a later r07.0 commit (Step 2b).

**New files committed to the repo**:

- `data/` — no production cache file is committed in this
  commit; production runs that invoke `Invoke-DotNetCuFetch` will
  write `raw-dotnet-cu.json` and `cache-dotnet-cu.json` on demand
  under the Patch-Tuesday-triggered model (SPEC.md §B.23.7).
- `tests/snapshots/dotnet_cu/index.md` — live capture of the
  Microsoft Learn `.NET Framework release information` index
  page (`?accept=text/markdown`) on 2026-05-26.
- `tests/snapshots/dotnet_cu/2026-05-12-may-cumulative-update.md`
  — live capture of the May 2026 monthly CU page.
- `tests/snapshots/dotnet_cu/2026-04-14-april-cumulative-update.md`
  — live capture of the April 2026 monthly CU page.
- The three `.meta.json` siblings carrying `captured_at`,
  `source_url`, `user_agent`, and `byte_count`.
- `tests/fixtures/dotnet_cu/index.json`,
  `tests/fixtures/dotnet_cu/month-2026-05.json`,
  `tests/fixtures/dotnet_cu/month-2026-04.json` — the Python
  reference parser output that defines what the PowerShell
  parsers must reproduce.

**New regression test**: `tests/dotnet_cu_parser_test.py` (T7).
Covers 16 assertions across the index parser (EntryCount,
EarliestDate, LatestDate, Kinds, per-entry deep equality across
all 29 entries, typo-entry preservation), the monthly parser
(EntryCountTotal, EntryCountRecognised, RowsPerOs, Server2022
block deep check, cross-month regression on 2026-04), and the
OS-label mapper (two production-scope labels plus an
unrecognised one). Runs against the fresh snapshots/fixtures
described above and is intentionally independent of the PoC
fixtures under `tests/snapshots/poc_dotnet_cu/`. **All 16
assertions pass** under PowerShell 7.4 on Ubuntu 24.

**Quality-gate status**: psa.py 0 / 0 / 0, PSScriptAnalyzer 0
findings, PowerShell parse OK, T2 13/13, T3 13/13, T6 13/13, T7
16/16. The PoC scripts and PoC snapshot/fixture directories are
unchanged.

### r07.0 Step 2a (release-info part) - PowerShell port of the release-info parser (previous release)

This commit lands the **first half** of the Step 2 work scheduled
in SPEC.md section B.23.1. New PowerShell functions parse the
Microsoft Learn Windows Server release-info Markdown into
structured cache data; the existing Refresher main path
(`Resolve-PatchSetFromCatalog`) is **untouched** and continues
to drive `-Action RefreshAllBaselines`. The .NET CU parser, the
Dynamic Update 36-month cache, and the Catalog URL-resolver
narrowing are scheduled for subsequent r07.0 commits.

**New PowerShell functions** (added to `Update-WindowsServerIso.ps1`
between `Get-OsConfigPath` and the Catalog scraper section):

- `Get-DataDirectoryPath` / `Get-ReleaseInfoRawPath`
  / `Get-ReleaseInfoRawMetaPath` / `Get-ReleaseInfoCachePath` —
  path resolvers for the three new files under `data/`.
- `Invoke-ReleaseInfoFetch` — HTTPS fetch of
  `https://learn.microsoft.com/.../windows-server-release-info?accept=text/markdown`
  using `Invoke-WebRequest -UseBasicParsing` with a descriptive
  User-Agent. Writes the Markdown body to
  `data/raw-release-info.md` (UTF-8, LF, no-BOM) and the HTTP
  headers + fetch timestamp to `data/raw-release-info.meta.json`.
- `Split-ReleaseInfoTableRow` / `Test-ReleaseInfoTableSeparator`
  / `ConvertFrom-ReleaseInfoUpdateType` /
  `ConvertFrom-ReleaseInfoKbCell` — small parser helpers that
  mirror the PoC Python implementations in
  `tests/poc_release_info_02_parse.py`.
- `ConvertFrom-ReleaseInfoMarkdown` — main parser. Returns a
  `pscustomobject` with two properties (`MonthlyReleases`,
  `HotpatchCalendar`) containing per-OS rows. Header text and
  column counts are checked strictly; any drift in Microsoft's
  table layout is reported via `Write-Warn` and the offending
  row is skipped (the offline regression test will then surface
  the count delta).
- `Update-ReleaseInfoCache` — reads `data/raw-release-info.md`,
  parses it, derives per-OS row counts, and writes
  `data/cache-release-info.json` (UTF-8, LF, no-BOM, JSON
  Depth 32).
- `Get-ReleaseInfoCache` — reads
  `data/cache-release-info.json` and returns the deserialised
  object. Refresher consumers in a later commit will use this
  to avoid re-parsing on every build.

**Schema of `data/cache-release-info.json`** (Schema 1.0):

```jsonc
{
  "Schema":            "1.0",
  "GeneratedAt":       "<ISO 8601 UTC>",
  "SourceUrl":         "https://learn.microsoft.com/...",
  "RawMarkdownPath":   "raw-release-info.md",
  "MonthlyRowCount":   471,
  "HotpatchRowCount":  62,
  "PerOsMonthlyCounts":  { "Server2016": 187, "Server2019": 165, "Server2022": 89,  "Server2025": 30 },
  "PerOsHotpatchCounts": { "Server2025": 26, "Server2022": 36 },
  "MonthlyReleases":   [ { "OsShortName": "Server2025", ... }, ... ],
  "HotpatchCalendar":  [ { "OsShortName": "Server2025", "CalendarYear": 2026, ... }, ... ]
}
```

**Constants and tables** added at script scope:

- `$Script:ReleaseInfoUrl`
- `$Script:ReleaseInfoUserAgent`
- `$Script:ReleaseInfoLongToShort`     (Markdown OS header → OsShortName)
- `$Script:ReleaseInfoMonthNameToNumber`
- `$Script:ReleaseInfoMonthlyHeaders`  (expected column names for the monthly release tables)
- `$Script:ReleaseInfoHotpatchHeaders` (expected column names for the Hotpatch calendar tables)

**Tests**

- New T6 `tests/release_info_parser_test.py`: invokes
  `ConvertFrom-ReleaseInfoMarkdown` via the existing TestHarness
  protocol against the PoC snapshot
  `tests/snapshots/poc_release_info/release-info-2026-05-25.md`
  and compares the output against the PoC fixture
  `tests/fixtures/poc_release_info/release-info.json`. The PoC
  fixture was generated by `tests/poc_release_info_02_parse.py`
  during r06.0 Phase 2 and is the reference truth for this
  port. T6 verifies: total monthly row count (471), total
  Hotpatch row count (62), per-OS monthly counts (Server2016=187,
  Server2019=165, Server2022=89, Server2025=30), per-OS Hotpatch
  counts (Server2025=26, Server2022=36), KbId-parse coverage
  per OS, and IsBaseline detection in the Hotpatch table.

**Not in this commit** (deferred to subsequent r07.0 steps):

- `Resolve-PatchSetFromReleaseInfo` (the new Refresher main
  path that consumes `cache-release-info.json`) — Step 2b.
- `.NET CU` parser and `data/cache-dotnet-cu.json` — Step 2a-2
  (next r07.0 commit).
- `Dynamic Update` 36-month cache (`data/cache-du-Server*.json`)
  — Step 2a-2 or Step 2a-3.
- `Get-DownloadUrlForKb` (Catalog URL resolver narrowed to
  KB-only lookup) — Step 2b.
- Deletion of the old `Resolve-PatchSetFromCatalog` KB-discovery
  logic — Step 2b.
- New `RefreshSnapshots` / `InspectBaseline` Actions, the
  `stage5__data-snapshot.yml` workflow, and the ScriptVersion
  bump to `r07.0` — Step 3.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- PSScriptAnalyzer (pwsh 7 Linux): 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- **T6 `release_info_parser_test.py`: 13/13 PASS** (new)
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md` / `.json`: UTF-8 + LF + no-BOM (verified)

### r07.0 Step 1 - data/ migration and DotNet type breaking change (this release)

This is the **first commit of the r07.0 implementation** of the
Phase 3 architecture decisions captured in SPEC.md §B.23. Two
mechanical changes ship in this step; the production code paths
(release-info parser, .NET CU parser, DU cache, URL resolver, new
Actions) come in the following r07.0 commits.

**Changes**

- **Directory rename: `Config/` → `data/` with `config-` filename
  prefix.** All four `Config/Server<N>.json` files are moved to
  `data/config-Server<N>.json`. This is the layout codified in
  SPEC.md §B.23.3 and is the foundation for the upcoming
  `cache-*` and `raw-*` sibling files. The `Config/` directory
  itself is removed.

- **New optional config field: `Common.CatalogTitleTokens`.** Each
  `data/config-Server<N>.json` gains an array of strings used by
  the future Catalog URL resolver to disambiguate KB-only Search.aspx
  responses. Values are sourced from PoC-B evidence in r06.0:

  | OS          | Tokens                                                                                              |
  | ----------- | --------------------------------------------------------------------------------------------------- |
  | Server 2016 | `["Windows Server 2016"]`                                                                           |
  | Server 2019 | `["Windows Server 2019"]`                                                                           |
  | Server 2022 | `["Microsoft server operating system version 21H2", "Microsoft server operating system, version 21H2", "Windows Server 2022"]` |
  | Server 2025 | `["Microsoft server operating system version 24H2", "Windows Server 2025"]`                         |

  The field is additive within Schema 2.1; consumers that do not
  recognise it ignore it (no Schema bump). See SPEC.md §B.23.2
  for the rationale and §B.23.4 for the schema-version stance.

- **Breaking change: `Type=DotNet` split into `DotNet.Runtime`
  + `DotNet.OsLevel`.** The PatchBaseline `Type` enumeration now
  distinguishes the per-runtime KB (applied to install.wim) from
  the OS-offering KB (recorded for traceability but not applied
  to any WIM). All in-tree code paths that referenced `'DotNet'`
  now reference `'DotNet.Runtime'`. The `Get-PatchType` classifier
  routes `.NET`-bearing filenames to `DotNet.Runtime` because the
  OS-offering KB never has an on-disk payload. The `PatchTargetMap`
  declares `DotNet.OsLevel` with an empty target array, so an
  OS-offering KB recorded in a future baseline cleanly skips
  WIM application. See SPEC.md §B.23.8 for the design rationale
  and §B.14b for the updated Type enumeration.

- **`Get-ConfigProfile` rejects legacy baselines.** A config-load
  attempt that finds `Type='DotNet'` entries in `PatchBaseline.Patches[]`
  now fails fast with a precise error pointing at SPEC.md §B.23.8
  and instructing the operator to re-run `-Action RefreshAllBaselines`.
  No automatic migration shim ships; r07.0 is a breaking change
  by design.

**Documentation updates**

- `SPEC.md §B.22.1` directory layout: rewritten in current-state
  voice with a historical note for the pre-r07.0 `Config/`
  layout.
- `SPEC.md §B.22.2` filename prefix rules: collapsed the r06.x /
  r07.0+ split rows into the post-r07.0 layout; the historical
  Phase 3 design narrative remains in §B.23.3.
- `SPEC.md §B.10` JSON example: example `Type` values updated
  to show both `DotNet.Runtime` and `DotNet.OsLevel` rows.
- `SPEC.md §B.14b` Type enumeration: the comment that lists all
  legal Type values now reads `... | DotNet.Runtime | DotNet.OsLevel
  | DotNet.LangPack | ...`.
- `SPEC.md §B.12` (P07 Install target table): added a row for
  `DotNet.OsLevel` showing `(none)` targets.
- `README.md` / `README.ja.md` / `TESTING.md` / `tests/README.md`
  / `tests/eval_iso_probe.py`: all references to `Config/...`
  paths updated to `data/config-...` paths.
- `.github/workflows/stage1__linux.yml` /
  `stage4__monthly-refresh.yml`: path-filter and PR-creation
  patterns updated to `data/**` and `data/config-*.json`.

**Tests**

- `tests/powershell_harness.py` (T3): the
  `Get-CatalogQueryTemplate per-OS Type coverage` and
  `Select-AllCanonicalPatchFiles dual-link case` tests are
  updated to expect `'DotNet.Runtime'` rather than `'DotNet'`.

**Baseline lint cleanup (PSScriptAnalyzer)**

Three pre-existing PSScriptAnalyzer findings were carried over
from earlier commits and resolved as part of Step 1 so the
project's stated "0 errors / 0 warnings / 0 information findings"
quality gate is actually enforced going forward:

- `PSAvoidAssignmentToAutomaticVariable`:
  `foreach ($pid in $installedIds)` renamed to
  `foreach ($packageId in $installedIds)` to avoid shadowing
  the read-only `$pid` automatic variable.
- `PSReviewUnusedParameter`: `Select-AllCanonicalPatchFiles`
  now honours its `$PatchType` parameter by mirroring the
  `DotNet.Runtime`-specific ndp scoring boost that
  `Select-CanonicalPatchFile` already had, making the
  multi-file picker behave consistently with the single-file
  picker when umbrella .NET CU KBs return multiple siblings.
- `PSUseDeclaredVarsMoreThanAssignments`: the unused
  `$regOut` capture from `reg.exe load` was changed to
  `$null = & reg.exe load ...` since success is determined
  by `$LASTEXITCODE` alone.

**Quality gates verified for this commit**

- `psa.py Update-WindowsServerIso.ps1`: 0 errors / 0 warnings / 0 info
- T2 `catalog_fixture_test.py`: 13/13 PASS
- T3 `powershell_harness.py`: 13/13 PASS
- `.ps1`: UTF-8 BOM + CRLF + ASCII-only (verified)
- `.md`: UTF-8 + LF + no-BOM (verified)
- `.json`: UTF-8 + LF + no-BOM (verified)

**Not in this Step 1**

- Script version is still `update-wsi-2026.05.25-r05.1`. The
  `r07.0` version bump happens in the final r07.0 commit.
- `Resolve-PatchSetFromReleaseInfo`, `Get-DownloadUrlForKb`, the
  release-info / .NET CU / DU caches, the `RefreshSnapshots` and
  `InspectBaseline` Actions, and the `stage5__data-snapshot.yml`
  workflow all arrive in subsequent r07.0 commits per the §B.23
  design.

### r06.0 Phase 2 - PoC: online patch metadata acquisition (this release)

This Phase 2 deliverable is **PoC scripts and a written report**,
plus a new normative SPEC.md §B.22 ("File organisation and naming
conventions") that codifies how PoC artefacts coexist with the
production code and the T1-T5 regression suite under the subproject
directory. As with Phase 1, this release contains **no script
(`.ps1`) changes and no on-disk Config schema changes**.

**Driver**. r06.0 Phase 1 left open the empirical question:
*does the Microsoft Learn Windows Server release-info page provide
enough authentication-free metadata to drive the Refresher,
replacing the brittle Microsoft Update Catalog title-string
heuristics catalogued in SPEC.md §D.19 / §D.20 / §D.21?* Phase 2's
PoC answers that question with measured data from 471 monthly
release rows and 62 hotpatch calendar entries.

**SPEC changes**:

- `SPEC.md` §B.22 ("File organisation and naming conventions")
  added. Five subsections:
  - **B.22.1** Directory layout (`Config/`, `tests/`, `docs/` as
    the only first-class children).
  - **B.22.2** Filename prefix rules (`poc_<topic>_<step>_<verb>.py`
    for PoC Python; `poc-<topic>-<purpose>.md` for PoC Markdown).
  - **B.22.3** Worked examples mapping filenames to classes.
  - **B.22.4** Out-of-scope clarifications.
- `SPEC.md` Part G adjunct ("PoC scripts under `tests/`") added,
  cross-referencing the new conventions and listing the current
  PoC inventory.

**PoC artefacts added** (all disposable per B.22):

```
tests/
├── poc_release_info_01_fetch.py    fetch the Markdown
├── poc_release_info_02_parse.py    parse into JSON
├── poc_release_info_03_analyse.py  write CSV + JSON analyses
├── snapshots/poc_release_info/
│   ├── .gitattributes
│   ├── release-info-2026-05-25.md       (68 KB raw Markdown)
│   └── release-info-2026-05-25.meta.json
└── fixtures/poc_release_info/
    ├── release-info.json                (parsed structured form)
    ├── update-type-summary.csv          (YYYY-MM x OS x letter pivot)
    ├── baseline-month-detection.json    (Server 2025/2022 hotpatch calendar)
    ├── letter-frequency.json
    └── coverage-summary.json
docs/
├── README.md                            (docs/ directory guide)
└── poc/
    ├── poc-release-info-readme.md       (how to run the PoC)
    └── poc-release-info-report.md       (findings + Phase 3 recommendations)
```

**PoC findings (summary)**:

- The `?accept=text/markdown` content-negotiation switch returns
  the source Markdown verbatim, 68 KB, no authentication. The page
  is GitHub-backed (`MicrosoftDocs/windows-release-pr`), so its
  format stability is reviewable.
- Monthly release coverage is comprehensive: 117 months for
  Server 2016, 92 for Server 2019, 58 for Server 2022, 20 for
  Server 2025, with zero gaps for the latter three.
- The previously-uncatalogued **"Windows Server hotpatch calendar"**
  section provides authoritative Baseline-vs-Hotpatch month
  labelling for Server 2022 and Server 2025, including
  forward-looking unreleased months. This single discovery answers
  the "how do we know which Server 2025 LCUs are baseline months"
  question without scraping technical blogs.
- The release-info page does NOT cover .NET Framework CU,
  Dynamic Update.Setup, Dynamic Update.SafeOs, or language packs.
  Those Types stay on the Catalog scrape path for Phase 3, but the
  Catalog query can be keyed by KB number (from release-info)
  rather than by Title-string heuristics, removing most of
  SPEC.md §D.19 / §D.20 from the surface area.

The full report including five Phase 3 recommendations and four
open questions is in
[`docs/poc/poc-release-info-report.md`](./docs/poc/poc-release-info-report.md).

**Not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`.
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes. The PoC scripts share the `tests/` directory
  by file-organisation convention but do not participate in the
  T-numbered regression suite.
- No Phase 3 code or design. Phase 3 is driven by the report's
  recommendations and is a separate work item.

#### r06.0 Phase 2 Part 2 — full Phase 2 coverage (this release)

The first cut of Phase 2 above shipped the `release_info` PoC
with three scripts but deferred three of the original PoC
questions (B, E, F) to Phase 3 as "open questions". Part 2
closes those gaps within Phase 2 so that the deliverable matches
the original Phase 2 scope.

**New PoC artefacts**:

- `tests/poc_release_info_04_resolve.py` — answers PoC-B by
  resolving 8 representative (OS, KB) pairs from the parsed
  release-info data through the Microsoft Update Catalog
  (Search.aspx → DownloadDialog.aspx). Verdict: 8/8 succeed
  with KB-only input; OS-naming requires both the
  `Windows Server NNNN` and `Microsoft server operating system
  version NNHN` tokens to disambiguate hits.
- `tests/poc_dotnet_cu_*.py` (new topic) — answers PoC-E by
  fetching and parsing the Microsoft Learn
  `.NET Framework cumulative update` release-notes pages.
  Verdict: the pages are served as Markdown via
  `?accept=text/markdown` and provide an authoritative per-OS x
  per-.NET-version KB table.
- `tests/poc_dynamic_update_01_probe.py` (new topic) — answers
  PoC-F by probing the Catalog with the same query templates as
  `Get-CatalogQueryTemplate`. Verdict: Server 2022 DU.SafeOs and
  Server 2025 DU.SafeOs are reliably discoverable; Server 2025
  DU.Setup has been absent from the Catalog for 5+ consecutive
  months (2025-12 through 2026-04), which the Phase 3 Refresher
  must treat as a soft signal rather than an error.

**New PoC documentation**:

- `docs/poc/poc-dotnet-cu-report.md` (full findings for PoC-E)
- `docs/poc/poc-dynamic-update-report.md` (full findings for PoC-F)
- `docs/poc/poc-release-info-report.md` updated with three
  `(revisited)` subsections that close PoC-B / E / F by linking
  to the new reports.

**SPEC changes**:

- `SPEC.md` §B.21.2 (.NET CU multiplicity by OS) amended to
  record the upstream-source per-OS file counts alongside the
  existing production-telemetry counts, and to explain the
  Server 2016 discrepancy (production sees 1 file; upstream
  release-notes lists 2 KBs).
- `SPEC.md` Part G adjunct updated to reflect the three current
  PoC topics (`release_info`, `dotnet_cu`, `dynamic_update`)
  instead of just one.

**Key empirical findings beyond the original Phase 2 questions**:

- Microsoft Update Catalog publishes Server 2022/2025 LCUs under
  the name "Microsoft server operating system version NNHN"
  (not "Windows Server NNNN"); the Phase 3 resolver must accept
  both token forms.
- Every Server 2025 LCU resolution returns 2 download URLs: the
  LCU itself plus `KB5043080` (the Servicing Stack baseline).
  This empirically validates the "no standalone SSU" claim in
  SPEC.md §B.21.1 for the Server 2025 row.
- SPEC.md §B.21.2 had a Server 2016 .NET CU file count of 1
  derived from r05.1 telemetry; the upstream
  `.NET Framework cumulative update` release-notes table for
  2026-04 lists 2 distinct KBs for Server 2016. The Phase 3
  Refresher should consume from release-notes (not the umbrella
  KB scrape) to surface the missing sibling.

**Still not in this Phase 2**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.

### r06.0 Phase 3 Architecture — SPEC-only: r07.0 design baseline (this release)

This Phase 3 deliverable is the **SPEC consolidation** of the
eleven architecture decisions taken during a 2026-05-25 design
session, building on the Phase 2 PoC findings. As with Phase 1
and Phase 2 Part 2, this release contains **no script (`.ps1`)
changes and no on-disk Config schema changes**.

**Driver**. Phase 2 (especially Part 2's PoC-B/E/F follow-up)
turned up enough hard data to answer the open questions that
§B.21.5 "Future work" had deliberately deferred. Rather than
go straight to implementation, this phase records *what r07.0
will look like* as a normative SPEC section so the implementation
PR can be reviewed against a written design, not against the
chat history of a design call.

**New SPEC section**: **§B.23 Phase 3 Architecture (r07.0+,
normative)** documents the eleven decisions as MADR-style
Decision Records:

| Subsection | Topic                                          | Decision                                                |
| ---------- | ---------------------------------------------- | ------------------------------------------------------- |
| §B.23.1    | Refresher architecture                         | Complete migration to release-info / .NET release-notes |
| §B.23.2    | Catalog Title token matching                   | Config-driven via `CatalogTitleTokens` field            |
| §B.23.3    | Data directory layout                          | `data/` flat with `config-` / `cache-` / `raw-` prefix  |
| §B.23.4    | Schema versioning                              | Stay at 2.1; no Schema 2.2                              |
| §B.23.5    | SSU separation and .NET CU multiplicity        | Filename-based SSU detection; both .NET siblings always |
| §B.23.6    | DU lookback                                    | 36-month rolling cache; latest publish wins             |
| §B.23.7    | Update lifecycle                               | Patch-Tuesday-triggered; Git-tracked                    |
| §B.23.8    | PatchBaseline Type subdivision                 | `DotNet` → `DotNet.Runtime` + new `DotNet.OsLevel`; breaking |
| §B.23.9    | release-info vs Catalog conflicts              | release-info is the absolute truth source               |
| §B.23.10   | r07.0 release granularity                      | Single r07.0 release; r06.x is docs-only                |
| §B.23.11   | `-PreferBaselineMonthLcu`                      | Deferred to Phase 4+                                    |

**Existing SPEC sections amended for cross-reference**:

- §B.21.5 (Future work) now states that the Schema 2.2 sketch is
  **NOT adopted**; per-OS knowledge moves into Config-driven or
  cache-driven mechanisms instead. Cross-references §B.23.
- §B.22.1 (Directory layout) adds an r07.0 migration note: the
  `Config/` directory will be renamed to `data/` per §B.23.3.
- §B.22.2 (Filename prefix rules) adds three new rows for the
  r07.0+ `config-` / `cache-` / `raw-` prefixes.

**Headline architecture points**:

1. **Catalog becomes a URL resolver, not a discovery source.**
   KB numbers harvested from release-info are passed to the
   Catalog to obtain `.msu` URLs; Title-string heuristics for
   discovery are deleted.
2. **`Config/` directory becomes `data/` with three filename
   prefixes** (`config-`, `cache-`, `raw-`). All upstream snapshot
   data is committed to the repository alongside the human-edited
   configs, with Git as the history mechanism (no date in
   filenames).
3. **Schema 2.1 is preserved.** The optional `CatalogTitleTokens`
   field is an additive Schema 2.1 extension; no Schema 2.2 is
   cut.
4. **`Type=DotNet` is deprecated and removed** in favour of
   `DotNet.Runtime` (per-runtime KB, applied to WIM) and
   `DotNet.OsLevel` (OS-offering KB, recorded only). r07.0 is a
   breaking change for any baseline carrying the legacy value;
   no migration shim ships.
5. **DU sources from a 36-month rolling Catalog probe cache.**
   The latest publish within the window wins; absence is logged
   as a warning, not an error. This absorbs PoC-F's finding
   that Server 2025 DU.Setup has been suspended since 2025-12.
6. **release-info is the absolute truth source.** Catalog
   contradictions either (a) stop the build (release-info has a
   KB the Catalog can't resolve) or (b) are ignored (Catalog has
   a KB release-info doesn't list).

**Release plan**:

- r06.0 (this release): SPEC-only documentation, no code changes.
- r07.0 (future release): full Phase 3 implementation per §B.23.
  Breaking change for any baseline carrying `Type=DotNet`.

**Open questions deferred to a third design round** (operations
specifics, not architecture):

- ~~Automated Patch-Tuesday-triggered snapshot refresh in CI~~
  → Resolved: stage5 + stage4 two-stage automation per §B.23.14
- ~~`-PatchMonth` argument for past-month refresh~~
  → Resolved: read-only `-Action InspectBaseline -PatchMonth`
  per §B.23.13
- ~~Server 2022 dynamic baseline-month detection (CY2024 August
  anomaly)~~ → Resolved: parser records baseline-months verbatim
  including anomalies per §B.23.12
- ~~PoC scripts CI promotion to T6-T8~~ → Resolved: PoCs promoted
  to T6-T8 as part of §B.23.14

All third-round questions resolved in this release. The Phase 3
SPEC is now complete; r07.0 implementation work can proceed.

**Third-round additions to §B.23** (this release adds):

| Subsection | Topic                                              | Decision                                                |
| ---------- | -------------------------------------------------- | ------------------------------------------------------- |
| §B.23.12   | Server 2022 baseline-month detection                | Strictly data-driven; authoritative source wins        |
| §B.23.13   | Past-month inspection                               | Read-only `-Action InspectBaseline -PatchMonth YYYY-MM` |
| §B.23.14   | CI structure                                        | Two-stage automation; stage5 (snapshot) + stage4 (baseline regenerate); PoC → T6-T8 |

Additionally, §B.6 (Action → Phase Mapping) gains a new
`InspectBaseline` row, and §B.23.7's "out of scope" disclaimer
on CI automation is upgraded to "in scope per §B.23.14".

**Still not in this Phase 3**:

- No `Update-WindowsServerIso.ps1` changes (still r05.1).
- No `Config/<OsKey>.json` schema changes.
- No T1-T5 changes.
- No `data/` directory yet (rename happens in r07.0).
- No `stage5__data-snapshot.yml` yet (added in r07.0).

### r06.0 Phase 1 - Spec-only: OS Update Type Matrix

This Phase 1 deliverable is SPEC-only and intentionally contains
**no script (.ps1) changes and no on-disk Config schema changes**.
It exists to make the until-now implicit per-OS update Type
assumptions normative, which is a prerequisite for the upcoming
PoC that will validate whether Microsoft's online metadata
sources can replace the Catalogue Title-string heuristics.

**Driver**. Production telemetry from the 2026-05 Patch Tuesday
refresh (r05.1) and a design review highlighted that Server
2016/2019/2022/2025 do not actually share a uniform set of
patch Types: SSU is standalone for 2016/2019 but folded into
the LCU for 2022/2025; .NET CU file multiplicity varies per
OS; Hotpatch exists only as an online-runtime mechanism on
Server 2025 and has no offline-image equivalent. None of this
was written down anywhere normative; the Refresher's behaviour
was a side effect of "Catalogue happened to return zero results
for SSU on Server 2025".

**Changes**:

- `SPEC.md` §B.21 ("Update Type Matrix per OS generation") added
  with five subsections:
  - **B.21.1** The matrix itself: a 4-OS x 8-Type table with
    cell values of `Required` / `Optional` / `N/A` / `Possible`.
  - **B.21.2** .NET CU multiplicity per OS, with the exact
    file counts observed in 2026-05 telemetry (1, 2, 2, 1 for
    Server 2016/2019/2022/2025 respectively).
  - **B.21.3** Combined LCU package detection: the two
    independent signals (Catalogue-side: SSU query returns 0
    hits; Title-side: "combined SSU and LCU" wording) and how
    `IsCombined` is annotated on PatchBaseline entries.
  - **B.21.4** Hotpatch declared out of scope for offline
    image servicing (it is an online-runtime mechanism via
    Azure Arc; no `Add-WindowsPackage` equivalent exists).
    Includes informational note that a future
    `-PreferBaselineMonthLcu` switch could help Server 2025
    machines that want to enroll in Hotpatch.
  - **B.21.5** Future work: candidate `Common.UpdateTypePolicy`
    sub-block for a hypothetical Schema 2.2, explicitly marked
    "NOT YET ADOPTED -- contingent on PoC".
- `SPEC.md` §D.2 ("SSU before LCU") amended with an
  OS-generation note pointing to §B.21.
- `SPEC.md` §D.21 ("Umbrella KBs") amended with a reference to
  §B.21.2 for the expected per-OS file count.

**Not in this Phase 1**:

- No `Update-WindowsServerIso.ps1` changes. `$Script:ScriptVersion`
  stays at `update-wsi-2026.05.25-r05.1`. The script's runtime
  behaviour is unchanged; only the documentation now states
  explicitly what the script was already doing implicitly.
- No `Config/<OsKey>.json` schema changes. Schema stays at
  v2.0 / v2.1 as accepted by r05.0.
- No PoC code yet. Phase 2 will introduce a separate PoC
  directory to validate the online-metadata sources
  (release-info Markdown, Hotpatch baseline-month detection,
  alternative sources for .NET / Dynamic Update).

### Planned (r06 Phase 2)

- PoC for online patch metadata acquisition without
  authentication. Targets: Microsoft Learn
  `windows-server-release-info` (Markdown rendering),
  Hotpatch baseline-month detection, alternative sources for
  .NET / Dynamic Update.
- Outcome: a written report (under `scripts/poc/` or a similar
  location) recommending which sources can replace which parts
  of `Resolve-PatchSetFromCatalog`'s Title-string heuristics.

### Planned (r06 Phase 3, PoC-driven)

- Config Schema v2.2 design (only if Phase 2 demonstrates
  feasibility): a `Common.UpdateTypePolicy` sub-block that
  codifies §B.21.1 per-OS, plus per-Type metadata such as
  `ExpectedFileCount`.
- Patch Manifest Engine: an interface that lets the Refresher
  prefer online-metadata sources for KB-number resolution and
  fall back to Catalogue scraping only for MSU/CAB URL
  resolution.

### Planned (M4 - carryover from earlier roadmap)
- Server 2025 real `LCUExpandViaMum=true` code path. LCU on 2025 ships
  as a MUM/CAB bundle that must be expanded with `expand.exe -F:*`
  before `Add-WindowsPackage` is invoked.

### Planned (M5 - carryover from earlier roadmap)
- Stage 4 CI workflow (`catalog-health`): monthly scheduled run of
  `Resolve-PatchSetFromCatalog` that opens a PR with the resulting
  `Config/<OsKey>.json` diff for human review. Catches Microsoft
  Update Catalogue HTML structure changes within 30 days.

## [update-wsi-2026.05.25-r05.1] - 2026-05-25

Two production-fix changes surfaced by the first real r05.0
`-Action RefreshAllBaselines` run against the 2026-05 Patch Tuesday
release:

### Fixed - KbId/FileName mismatch in PatchBaseline.NeutralPatches

When Microsoft publishes a single "umbrella" CU whose `UpdateId`
attaches multiple `.msu` files (typical for .NET cumulative updates
and for some LCUs that bundle a checkpoint CU's payload), the
previous patch-resolution loop reused the umbrella Title-derived
KbId for every attached file. That produced PatchBaseline entries
where the recorded `KbId` did not match the actual `FileName`:

```json
// Server2019.json, May 2026 baseline (BEFORE this fix)
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087066-x64-ndp48_...msu" },
{ "KbId": "KB5088864", "FileName": "windows10.0-kb5087061-x64_...msu" }
//        ^^^^^^^^^^                              ^^^^^^^^^^
//        umbrella Title KB     actual payload KB encoded in file name
```

Three symptoms were observed in the 2026-05 production output:

- **Server2019 / Server2022 .NET CU**: two identical-KbId entries
  attached to two distinct .msu files (4.8 + 4.8.1 runtimes).
- **Server2025 LCU**: `KbId=KB5087539` (umbrella Title) with
  `FileName=windows11.0-kb5043080-x64_...msu` (checkpoint CU payload).
- **Server2022 Dynamic Update**: `Setup` and `SafeOs` queries
  resolved to the same `UpdateId` because the OS-title narrowing
  step did not separate them by intent.

This release adds two fixes:

1. **New helper `Get-KbIdFromPatchFileName`** that parses
   `kb#######` out of the standard Microsoft file-name patterns
   (`windows10.0-kb5087537-x64_...`, `windows11.0-kb5087588-x64_...`,
   `...-ndp48_...`, `...-ndp481_...`, etc.). Returns the KB id in
   canonical upper-case form; returns `''` for file names that do
   not contain a `kb` token so the caller can fall back to the
   umbrella Title.
2. **`Resolve-PatchSetFromCatalog` per-file KbId**: the
   `foreach ($primary in $primaries)` loop now derives the
   per-file KbId via `Get-KbIdFromPatchFileName` (falling back to
   the Title-derived KbId if the file name has no kb token). Each
   entry now reflects its actual payload KB.
3. **Setup/SafeOs disambiguation post-filter**: for the 21H2/24H2
   Dynamic Update queries whose `QueryTemplate` is shared, an
   additional title-keyword filter ("Setup Dynamic Update" vs
   "Safe OS Dynamic Update" / "SafeOS") is applied after the
   OS-title narrowing so the two queries no longer collide on
   the same UpdateId.

The fix is fully backward compatible: existing PatchBaseline.json
files keep loading, and the FileName + DownloadUrl fields (which
P04 FetchAssets actually uses for download) were already correct;
only the KbId label is updated.

### Added - Rich `-Action RefreshAllBaselines` console summary

`Show-RefreshAllBaselinesSummary` now renders a seven-section
end-of-run summary block that consolidates everything an operator
needs to file a baseline-refresh ticket without re-reading the full
progress log. The block is console-only (no extra files written),
which keeps CI log capture trivial. Sections:

  1. **Field-group decisions** - same counts as before
     (Skip / Manual / Monthly / InitialFill).
  2. **Per-OS patch composition** - one row per OS showing the
     final NeutralPatches count, file count, and a `Type=N` map
     across SSU/LCU/DotNet/DynamicUpdate.* buckets.
  3. **KB delta vs previous PatchBaseline** - per-OS
     `+ added (n)`, `- removed (n)`, `= unchanged (n)` lines with
     the actual KB ids, computed against the BeforePatches
     snapshot captured at the start of the OS loop.
  4. **Manual fill required** - the operator follow-up list,
     grouped by OS so each ticket / diff can be scoped per-OS.
  5. **Pca2023 readiness** - per-OS RequiredByDefault flag and
     RequiredUpdateLevelKb (Schema 2.1 only; Schema 2.0 configs
     are flagged with "(no Pca2023 block)").
  6. **Patch Tuesday timeline** - this run's baseline plus the
     next two upcoming Patch Tuesdays so the next refresh window
     is visible at a glance.
  7. **Run outcome** - explicit Status + Exit code statement
     (`OK` / exit 0, `PARTIAL` / exit 2, `FAILED` / exit 1) so
     CI dashboards do not need to parse return values to know
     whether a run was clean.

Implementation notes:

- The OS loop now captures a deep-clone `BeforePatches` snapshot
  via `ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json` so
  later in-place mutations to `$raw` cannot retroactively poison
  the "before" set.
- The new collector hashtable (`$osSummaries`) is keyed by OsKey
  and aggregates BeforePatches / AfterPatches / Changed /
  ErrorCount / ManualGroups / Pca2023 reference / PreviousVerified
  for every OS processed in the run, even those skipped due to
  Schema mismatch (skipped OSes appear with `(Schema 2.0)` in
  section 5).
- `Manual` decisions add the affected group path to
  `osSummaries[$osKey].ManualGroups`, which section 4 then walks.
- `Refresher failed` exceptions increment
  `osSummaries[$osKey].ErrorCount`. Section 7 inspects the
  overall `$okOverall` aggregate to decide between PARTIAL and
  FAILED status.

## [update-wsi-2026.05.25-r05.0] - 2026-05-25

Major version bump for two distinct (but coordinated) changes:
**(1)** complete integer renumbering of all phase IDs (removing the
historical 0.5-step inserts), **(2)** Secure Boot / PCA2023 boot
manager support per Microsoft KB 5053484 (`Make2023BootableMedia.ps1`).
Both are breaking changes for operators who reference Phase IDs by
name or who have wired specific Phase-IDs into their own runbooks.

### Breaking changes

- **Phase ID renumbering** (no aliases, no deprecation warnings).
  Old IDs (`P02.5`, `P04.5`, `P03`, `P04`, `P05`, `P06`, `P07`, `P08`,
  `P09`) are now invalid - the dispatcher will reject `-PhaseIds
  'P02.5'` style invocations. The new mapping:

  | Old ID | New ID | Phase name |
  |:---:|:---:|---|
  | P01    | **P01** | Initialize (unchanged) |
  | P02    | **P02** | ResolveInputs (unchanged) |
  | P02.5  | **P03** | RefreshPatchBaseline |
  | P03    | **P04** | FetchAssets |
  | P04    | **P05** | ExpandIso |
  | P04.5  | **P06** | ValidatePatchSet |
  | P05    | **P07** | PatchInstallWim |
  | P06    | **P08** | PatchBootWim |
  | P07    | **P09** | AssembleIso |
  | (new)  | **P10** | ConvertPca2023BootManager (Build, default-skip) |
  | P08    | **P11** | StaticVerify |
  | (new)  | **P12** | VerifyPca2023Readiness (Verify, always-runs) |
  | P09    | **P13** | FinalReport |
  | A01    | **A01** | RefreshAllBaselines (unchanged) |
  | A02    | **A02** | DumpFieldClassification (unchanged) |

- **Action mapping internal updates** (Action names unchanged):
  - `Prepare` -> `P01, P02, P03, P04, P05, P06`
  - `Build`   -> `P07, P08, P09, P10`
  - `Verify`  -> `P11, P12, P13`
  - `All` / `PrepareBuildVerify` -> all phases above
  - `GenerateManifest` -> `P01, P02, P03`

- **Function name renames** (script-internal; affects any caller
  that referenced these by reflection or `Get-Command`):
  - `Invoke-SetupPhase02_5_RefreshPatchBaseline` -> `Invoke-SetupPhase03_RefreshPatchBaseline`
  - `Invoke-FetchPhase03_FetchAssets` -> `Invoke-FetchPhase04_FetchAssets`
  - `Invoke-PlanPhase04_ExpandIso` -> `Invoke-PlanPhase05_ExpandIso`
  - `Invoke-PlanPhase04_5_ValidatePatchSet` -> `Invoke-PlanPhase06_ValidatePatchSet`
  - `Invoke-BuildPhase05_PatchInstallWim` -> `Invoke-BuildPhase07_PatchInstallWim`
  - `Invoke-BuildPhase06_PatchBootWim` -> `Invoke-BuildPhase08_PatchBootWim`
  - `Invoke-BuildPhase07_AssembleIso` -> `Invoke-BuildPhase09_AssembleIso`
  - `Invoke-VerifyPhase08_StaticVerify` -> `Invoke-VerifyPhase11_StaticVerify`
  - `Invoke-ReportPhase09_FinalReport` -> `Invoke-ReportPhase13_FinalReport`

- **Config schema bump 2.0 -> 2.1**. All four `Config/<OsKey>.json`
  files gain a new top-level `Pca2023` block. Existing readers that
  hard-code the field set will need a one-line tolerance update.

- **CSV filename change**: P11 StaticVerify now writes
  `logs/P11_verification.csv` instead of the legacy
  `logs/P08_verification.csv`.

### Added

- **P10 ConvertPca2023BootManager phase** (Build group, optional).
  Rewrites the output ISO's boot manager to be signed via the
  "Windows UEFI CA 2023" certificate chain instead of the legacy
  "Windows Production PCA 2011" chain. Required for booting under
  Secure Boot firmware that has revoked PCA2011 trust (post 2026-06
  expiry, BlackLotus CVE-2023-24932 mitigation rollout).

  - **Internal implementation**: `Convert-WimBootToPca2023Signed`
    is a PSA-clean re-implementation of Microsoft's
    `Make2023BootableMedia.ps1#Copy-2023BootBins` logic from
    `microsoft/secureboot_objects` (Version 1.4, 2026-03-13).
    Differences from upstream: Context-bag state instead of
    `$global:WIM_*`, structured logging via `Write-Step`, `throw`
    instead of `exit`, `[Parameter(Mandatory)]` shorthand,
    Verb-Noun PSA compliance.

  - **External script option**: `-Pca2023ScriptPath <path>` invokes
    a user-supplied `Make2023BootableMedia.ps1` instead of the
    internal helper, for operators who need to track Microsoft's
    upstream script version directly.

  - **Multi-layered opt-in**: requires `-EnablePca2023BootManager`
    at minimum; Server 2025 additionally requires
    `-ForcePca2023OnServer2025` because certified Server 2025
    server platforms include the 2023 certificates in firmware
    (KB 5053484 does not list Server 2025 in its supported-OS
    set).

  - **Pre-flight gates**:
    - silent skip if `-EnablePca2023BootManager` not set
    - silent skip if OsKey=Server2025 without `-ForcePca2023OnServer2025`
    - silent skip if pre-flight readiness Health = 'Healthy' (already PCA2023)
    - throw if Health = 'Critical' (source media < 2024-04-09 LCU)

- **P12 VerifyPca2023Readiness phase** (Verify group, always-runs).
  Read-only inspection of the produced ISO; emits JSON + Markdown
  reports under `<WorkRoot>/pca2023/`. Three-tier diagnostic:
  - Tier 1: File-existence checks on `boot.wim:\Windows\Boot\EFI_EX\`
    staging directories (the 2024-4B presence signal)
  - Tier 2: `Get-WindowsPackage` LCU month detection on install.wim
    and boot.wim (the 2024-4B integration level)
  - Tier 3: `Get-AuthenticodeSignature` chain walk on
    `efi\boot\bootx64.efi` (the actual firmware-visible signer
    identity)

- **9 new SecureBoot helper functions** in the script:
  - `Get-LcuVersionFromInstallWim` (DISM `Get-WindowsPackage` wrapper)
  - `Get-WimSystemHiveValue` (offline SYSTEM hive read via `reg.exe load`)
  - `Test-Pca2023AuthenticodeChain` (X509Chain walk for cert classification)
  - `Get-IsoBootCertReadiness` (per-ISO inventory assembler)
  - `Get-Pca2023ReadinessSnapshot` (top-level snapshot with Health 4-value)
  - `Show-Pca2023ReadinessSnapshot` (`-Compact` + full console renderer)
  - `Format-Pca2023ReadinessForReport` (StringBuilder text formatter)
  - `Get-OrEnsurePca2023Snapshot` (idempotent cache accessor)
  - `Convert-WimBootToPca2023Signed` (Microsoft `Copy-2023BootBins` reimpl)

- **`-Pca2023OnlyMode` short-circuit**: takes an existing ISO via
  `-IsoPath` and runs ONLY P12 against it. No download, no patching,
  no ISO re-assembly. For forensic inspection of pre-built ISOs.
  Output JSON goes to `$env:TEMP\updwsi_pca2023only_<pid>\`.

- **3 new T3 smoke tests** in `tests/powershell_harness.py` covering
  the SecureBoot helpers' error paths
  (`Test-Pca2023AuthenticodeChain` missing-file,
  `Get-LcuVersionFromInstallWim` missing-mount,
  `Format-Pca2023ReadinessForReport` null-snapshot safety).

- **SPEC.md sections**:
  - B.18 (PCA2023 boot manager support)
  - B.19 (`-Pca2023OnlyMode` standalone inspection)
  - B.20 (Build-group optional phase exception)
  - D.22 (Secure Boot baseline considerations / lessons learned)

### Changed

- **All 9 phase function definitions renumbered** to integer Phase
  IDs (the renumbering side of this major bump). Function bodies
  unchanged; only the names + the `Start-DebugTrace -PhaseId 'PNN'`
  arguments + the `$Script:PhaseRegistry` rows update.

- **381 Phase ID literals renamed** across the script body (215),
  CHANGELOG/README/SPEC/TESTING (163), and tests/ (3). All `'P02.5'`,
  `'P04.5'`, `'P03'`...`'P09'` quote-wrapped string literals are
  rewritten to their new integer IDs. Markdown body text mentions
  of `P02.5`, `P04.5`, `P03`...`P09` are also rewritten.

- **`$Script:PhaseRegistry`** gains P10 (`ConvertPca2023BootManager`,
  Build) and P12 (`VerifyPca2023Readiness`, Verify) entries.

- **`Resolve-PhasesForAction`** internal mapping updated to reflect
  new integer phase IDs and added P10 / P12 placement (Build / Verify
  groups respectively).

- **P13 FinalReport** now includes a Compact-form PCA2023 readiness
  summary inline (after Log locations, before the `.markers/P13.ok`
  marker write). The detail JSON + Markdown remain in
  `<WorkRoot>/pca2023/` for machine consumers.

- **Per-OS PCA2023 defaults** baked into
  `Config/<OsKey>.json#/Pca2023`:
  - Server2016/2019: `RequiredByDefault=true`, MinDate=`2024-04-09`
  - Server2022: `RequiredByDefault=true`, MinDate=`2025-02-11`
    (per Lenovo lp2353.pdf 20348.2227 baseline requirement)
  - Server2025: `RequiredByDefault=false` (firmware-provided 2023 certs)

### Internal

- Stage A / Stage B internal work organisation:
  - Stage A = pure phase ID renumbering. The script was renamed in
    bulk and ran clean (psa.py 0/0/0, PSScriptAnalyzer 0, T2
    13/13 PASS, T3 7/7 PASS) before any new code was written.
  - Stage B = SecureBoot feature implementation on top of the
    renumbered Stage A baseline.
  - The final r05.0 release ZIP is a single artifact even though
    the internal work was two-staged.

- Custom Python tool `stage_a_renumber_v2.py` for the bulk Phase ID
  rewrite. Uses an opaque-token two-pass strategy to safely handle
  chained renames (where old `'P03'` -> new `'P04'` and old `'P04'`
  -> new `'P05'` would otherwise collide). The token form is
  `XOPAQUEXX<two-digit>XX` which by construction never matches a
  `\bP\d\d\b` regex.

- `read_bytes` / `write_bytes` are used throughout the rewrite tool
  to preserve CRLF line endings on `.ps1` files (Python's `read_text`
  / `write_text` normalise CR/LF, which would have violated the
  `.gitattributes` `*.ps1 text eol=crlf` policy).

### Added (post-Stage-B integration from microsoft/secureboot_objects)

The following six improvements were folded into the r05.0 release
after a second-pass audit of the upstream Microsoft repository
(microsoft/secureboot_objects @ main). They are NOT bug fixes;
they are quality / documentation upgrades surfaced by the audit.

- **oscdimg.exe SHA-256 supply-chain integrity check** (`Resolve-OscdimgExe`).
  After locating `oscdimg.exe`, the function now compares the binary's
  SHA-256 against Microsoft's reference hash for the current
  architecture (AMD64 / ARM64 / x86), lifted verbatim from
  `Make2023BootableMedia.ps1#$global:oscdimg_known_hashes` Version 1.4.
  Mismatch is ADVISORY (warning only), because ADK-installed binaries
  may legitimately differ across ADK versions. The check still detects
  the high-impact failure mode: a malicious binary swap on the host
  running the script.

- **NTFS filesystem check in workspace preflight** (`Assert-WorkspacePreflight`).
  Adds a "Check 3" after the disk-space check: confirms the drive
  hosting `-WorkRoot` is formatted as NTFS. WIM mount and DISM
  operations rely on NTFS-only reparse-point / per-stream-metadata
  semantics; ReFS or FAT32 produce silent corruption. Mirrors
  Microsoft's own
  `Make2023BootableMedia.ps1#Initialize-StagingDirectory` enforcement.
  Skipped under `-DryRun` and on non-Windows pwsh hosts (synthetic CI).

- **SPEC.md D.23 — UEFI Secure Boot defaults templates (informational)**.
  New section documenting the five reference templates from
  `microsoft/secureboot_objects/Templates/` (`MicrosoftOnly`,
  `MicrosoftAndOptionRoms`, `MicrosoftAndThirdParty`,
  `MostCompatible`, `LegacyFirmwareDefaults`) and how target firmware
  template choice affects whether to run P10. These templates describe
  firmware-layer Secure Boot variables and are out of scope for direct
  consumption, but operators need to understand them to interpret P12
  output correctly. Includes a per-template "PCA2023 media required?"
  decision matrix.

- **SPEC.md D.22 — KB 5053484 official scope + `-MediaPath` form
  details**. Promoted from a fuzzy "Microsoft KB documentation" link
  to an explicit "Applies To" enumeration (Server 2012/R2/2016/2019/2022
  + Windows 10/11 client SKUs; Server 2025 deliberately not listed)
  and a documented narrowing rationale (upstream `-MediaPath` accepts
  ISO / directory / network share; this project's pipeline operates on
  the extracted-tree form only for repeatability and auditability).
  README.md and README.ja.md gain a one-paragraph summary of the same.

- **T3 schema-validation tests** (`tests/powershell_harness.py`).
  Three new tests modelled on
  `microsoft/secureboot_objects/scripts/test_validate_dbx_references.py`
  7-axis pattern (absent / empty / invalid JSON / missing field /
  ...). Coverage added:
  1. `Get-IsoBootCertReadiness` non-existent media → `.Available=$false`
     + `.ErrorMessage` mentions boot.wim
  2. `Get-IsoBootCertReadiness` schema completeness — the error-path
     inventory must still carry every documented snapshot field so
     P12 JSON serialization / P13 summary never AttributeError
  3. `Get-Pca2023ReadinessSnapshot` Health enum constraint — must be
     one of `{Healthy, Warning, Critical, Unknown}` even on the
     error path; never `$null` or free-form string

- **`.markdownlint.yaml` configuration file**. New project-root
  markdown lint config adapted from
  `microsoft/secureboot_objects/.markdownlint.yaml`. Adjusted for
  this project's conventions: line_length=120, code_blocks=false,
  tables=false; MD024 (duplicate headings) and MD041 (must-open-
  with-heading) disabled per Keep a Changelog and tests/README
  conventions. The file is opt-in for contributors who run
  markdownlint locally; CI is not yet wired to enforce it.

### Fixed (Schema v2.1 loader, post-publication regression)

The Stage A renumber and Stage B Pca2023 feature work bumped the
Config schema from v2.0 to v2.1 in all four `Config/Server*.json`
files, but **did not** update the `Get-ConfigProfile` loader's
schema-acceptance check, which remained `-eq '2.0'` and rejected
all four r05.0 Configs at runtime. The first `-Action
PrepareBuildVerify` smoke test (Stage 2 Smoke3) failed at P02
ResolveInputs with:

```
[X] Phase P02 (ResolveInputs) failed: Config Server2019.json has
    Schema="2.1"; expected "2.0". Legacy schemas are not supported.
```

Two loaders are now updated to accept both schemas:

- **`Get-ConfigProfile`** (the main per-OS loader called from P02
  ResolveInputs and from every Action that needs OS data) now
  accepts `Schema ∈ {'2.0', '2.1'}`. When `Schema == '2.1'`, the
  `Pca2023` block is also required (per SPEC.md B.10); when
  `Schema == '2.0'`, no Pca2023 block is required — preserving
  full backward compatibility with Configs predating r05.0.

- **`Invoke-AdminAction_RefreshAllBaselines`'s loader** (used by
  Action A01 to walk all four Configs for baseline refresh) is
  updated symmetrically. It also accepts both schemas but does
  not require `Pca2023` (the action only touches `PatchBaseline`
  fields, so the Pca2023 block is orthogonal).

The error message now lists all accepted schemas explicitly
(`expected one of: 2.0, 2.1`), so future schema bumps will produce
a self-documenting error indicating exactly which versions the
running script supports.

### Fixed (CI workflow remediation, r04.x carryover)

Audit of the most recent CI run on `main` (`1aa96df`, STAGE 1
Linux checks #12) surfaced two pre-existing problems that were
about to make the next push fail; both are fixed in r05.0:

- **STAGE 1 Config JSON validator was still using Schema v1 keys**
  (`OsName`, `OsShortName`, `Build`, `Architecture`, `Languages`
  at top level). Schema v2.0 (introduced in r03) restructured these
  under `Common/PatchBaseline/LanguageSpecific`, and Schema v2.1
  (r05.0) added the `Pca2023` block. The validator therefore failed
  with `FAIL: Server2016.json missing top-level "OsName"` and
  exited 1, which cascaded into "psa.sarif not produced" and
  "pssa.sarif not produced" errors in downstream steps. The
  validator has been rewritten to accept Schema 2.0 (warned) and
  2.1 (required), to verify the `Common.*` fields, and to enforce
  the `Pca2023` block presence when `Schema == 2.1`.

- **Embedded em dash (U+2014) in `Assert-WorkspacePreflight`** broke
  the BOM + CRLF + ASCII-only validator at line 2195. The character
  was introduced during Stage B Step 3 (NTFS check) and is now
  replaced with two ASCII hyphens. The validator now passes again
  (416,708 bytes, ASCII-only).

### Changed (CI infrastructure modernisation, r05.0)

Coordinated bump of all GitHub Actions to Node 24-compatible
versions ahead of the 2026-09-16 Node 20 removal deadline and the
December 2026 CodeQL Action v3 deprecation. Affects all 8 workflow
files (update-windows-server-iso STAGE 1-4, download-speakerdeck
STAGE 1-3, psa.py CI):

| Action | Was | Now |
|---|:---:|:---:|
| `actions/checkout` | `@v4` | `@v5` |
| `actions/setup-python` | `@v5` | `@v6` |
| `actions/upload-artifact` | `@v4` | `@v5` |
| `github/codeql-action/upload-sarif` | `@v3` | `@v4` |
| `peter-evans/create-pull-request` | `@v7` | `@v8` |
| `actions/cache` | `@v4` | `@v4` (unchanged - current) |
| `microsoft/psscriptanalyzer-action` | `@v1.1` | `@v1.1` (no v2 released) |

Additionally, `setup-python` now pins to **`python-version: '3.12'`**
instead of the previous `'3.x'`. The latter was resolving to
CPython 3.14.x on the GitHub-hosted Ubuntu 24.04 runner, which
has not been validated against psa.py + the T1-T5 self-
verification tool suite. Pinning to 3.12 (the version the project
has run its full test matrix on) restores deterministic behaviour
and forms an explicit upgrade point — bumping it requires running
the test matrix locally on the target Python version first.

Workflow comments referencing old phase IDs (`P02.5`, `P04.5`,
`P02/P03/P04`, `P08 verify`, "P01 through P09") are also updated
to the r05.0 phase numbering (`P03`, `P06`, `P02/P04/P05`,
`P11 verify`, "P01 through P13").

### Added (CI runner diagnostic pre-flight, r05.0)

Following review of the failed Stage 1 run from commit `1aa96df`,
each CI workflow gains a `[Diag] Runner environment snapshot` step
at the start of the job. The goal is to make triage tractable when
scheduled (Stage 4 cron) or flaky failures occur — every failed run
should carry enough information to diagnose runner-side drift
without re-running the job.

The diagnostic step captures (per stage):

| Stage | Diagnostic information |
|---|---|
| **Stage 1 / psa.py CI (Linux)** | `uname -a`, Python version, `pwsh` presence, CWD, key env vars, repo layout |
| **Stage 2 (Windows)** | `$PSVersionTable`, `Get-ExecutionPolicy -List`, console encoding, identity + admin check, env vars, oscdimg.exe presence at canonical ADK paths |
| **Stage 3 (Windows)** | Same as Stage 2 + free disk space on `C:` |
| **Stage 4 (Windows)** | PSVersion, ExecutionPolicy, identity, env vars |

Each diagnostic step uses `$ErrorActionPreference = 'Continue'`
(or `set +e` for bash) so a missing tool does not tank the
diagnostic step — the goal is to record what IS available.

Additionally, **all** non-diagnostic Windows PowerShell steps
across Stages 2, 3, and 4 are uniformly hardened with:

- `$ErrorActionPreference = 'Stop'` — prevents silent error
  swallowing (PS 5.1's default is `Continue`).
- `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` —
  prevents PS 5.1's legacy ANSI code-page default from mangling
  non-ASCII characters in log streams or `$GITHUB_*` files.
- `defaults.run.working-directory: ${{ github.workspace }}` at the
  job level — anchors relative paths to the checkout root rather
  than to a surprising platform-default location.

Background reference material is captured in
`documents/ci-engineering/github-actions-windows-powershell-guide.md`
(new file in this release). SPEC.md gains a new §C.5c documenting
the diagnostic-step contract.

## [update-wsi-2026.05.25-r04.4] - 2026-05-25

### Added - Self-verification tool suite (`tests/`)

A new `tests/` subdirectory ships alongside `Update-WindowsServerIso.ps1`
holding five Python-based self-verification tools. They exist because
the three live-test bugs fixed in r04.3 had a common root cause -
silent Microsoft-side change in the Catalog HTML / data that no
purely-static analysis could catch - and the project needed a way
for both Claude and human operators to confirm the script's
Microsoft-side assumptions still hold before AND after any change.

The tool suite:

| Tool | Purpose | Network? |
|---|---|:---:|
| `catalog_probe.py`        (T1) | Live Microsoft Update Catalog probe (search, supersedence panel, title-format per OS); diffs vs `snapshots/last_probe.json` | Yes |
| `catalog_fixture_test.py` (T2) | Offline regression test against saved HTML fixtures (`fixtures/2026-05/`); 13 assertions including bug-2 and bug-3 regressions | No |
| `powershell_harness.py`   (T3) | Python-side driver that invokes PowerShell functions via the new `-Action TestHarness` REPL; 7 assertions on Get-CatalogQueryTemplate, Select-AllCanonicalPatchFiles, etc. | No |
| `eval_iso_probe.py`       (T4) | HTTP Range-GET against each `Config/Server<N>.json#/.../Iso/Url`; reports MB + Last-Modified per OS | Yes |
| `wsusscn2_probe.py`       (T5) | HTTP probe of `wsusscn2.cab`; warns when the cab is older than 60 days | Yes |

All tools use **standard-library Python only** (no `pip install`
required), matching the dependency policy already set by
`quality-tools/powershell-static-analyzer/psa.py`.

The directory layout:

```
tests/
  README.md                    -- per-tool usage + when-to-run guide
  catalog_probe.py             -- T1
  catalog_fixture_test.py      -- T2
  powershell_harness.py        -- T3
  eval_iso_probe.py            -- T4
  wsusscn2_probe.py            -- T5
  common/
    catalog_client.py          -- urllib HTTP fetcher with retry-with-jitter
    html_parsers.py            -- Catalog HTML extractors (intentionally
                                  mirrors the PS regexes)
    ps_invoke.py               -- PSSession context manager driving the
                                  -Action TestHarness REPL
    snapshot.py                -- JSON snapshot read/write + diff_dict()
  fixtures/2026-05/            -- 6 HTML files (~331 KB) + expected.json
  snapshots/                   -- T1 output (last_probe.json) lives here
```

### Added - `-Action TestHarness` (script REPL hook)

The PowerShell script gains a new dispatcher branch `-Action TestHarness`,
placed before `Show-EntryBanner` so no banner contaminates stdout.
It loads all function definitions in the current session, then drains
stdin one JSON line at a time, parsing requests of the form
`{"fn":"<FunctionName>","args":{ ... }}` and emitting JSON responses
of the form `{"ok":true,"fn":"...","result": ...}` or
`{"ok":false,"error":"<message>","fn":"..."}`. The REPL exits on
EOF.

This is the entry point for T3 (`tests/powershell_harness.py`).
It is not intended for human invocation; the `-Action` help text
explicitly says so.

`-Action TestHarness` is added to the `osLessActions` set
(no `-OsVersion` required) and to the workspace-preflight skip list
(no Config / 100 GB requirement).

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,695 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- All 5 self-verification tools pass live + offline runs:
  - T1: 7/7 checks, snapshot persisted
  - T2: 13/13 fixture assertions
  - T3: 7/7 PowerShell function assertions
  - T4: 8/8 Iso endpoints (Server2016 endpoint host rejects Range/HEAD;
    treated as "unprobable, not broken")
  - T5: detects `host_not_allowed` egress in restricted environments
    and reports exit 3 (NOT 2), so the operator can tell apart
    "Microsoft outage" from "execution environment blocks the host"

### Compatibility

- `ScriptVersion` bumped to `update-wsi-2026.05.25-r04.4`;
  `ScriptTag` is `self-verification-tools-and-test-harness`.
- No behaviour change for any production Action (Prepare / Build /
  Verify / PrepareBuildVerify / RefreshAllBaselines / Cleanup etc.).
  The TestHarness branch is reached only by an explicit
  `-Action TestHarness` invocation.

## [update-wsi-2026.05.25-r04.3] - 2026-05-25

### Fixed - `NeutralPatches[].Type` mis-classification

Live first-pass test of `-Action RefreshAllBaselines` (2026-05 cycle)
exposed that the `Type` field on every Catalogue-derived
`NeutralPatches` entry was being computed by file-name heuristics in
`Get-PatchType`, even though the calling code in
`Resolve-PatchSetFromCatalog` already knew the authoritative Type
from the Catalogue search query (`SSU` / `LCU` / `DotNet` /
`DynamicUpdate.SafeOs` / `DynamicUpdate.Setup`). The heuristic
broke whenever the file name lacked the expected token (e.g. SSU
file names containing only `kb<N>` with no `servicingstack`
substring; SafeOS DU file names with `kb<N>` but no `safeos`;
.NET CU sub-files without `ndp<N>` or `.net`). Affected real
2026-05 entries were:

| OS | KbId | Title type | Wrong `Type` | Correct `Type` |
|---|---|---|---|---|
| Server2016 | KB5088064 | Servicing Stack Update | `LCU` | `SSU` |
| Server2019 | KB5088864 | Cumulative Update for .NET Framework | `LCU` | `DotNet` |
| Server2025 | KB5087588 | Safe OS Dynamic Update | `LCU` | `DynamicUpdate.SafeOs` |

The Type-routing in `$Script:PatchTargetMap` (SPEC §B.12) depends on
this field to send each patch to the right WIM-target sub-phase
(SPEC §B.14), so the mis-classification would have made install.wim
patching ineffective on a live ISO build.

**Fix**: added `-KnownType` parameter to
`Convert-CatalogPatchToBaselineEntry`. When the caller passes a
non-empty string (which `Resolve-PatchSetFromCatalog` now does
unconditionally via `-KnownType $q.Type`), the function uses that
value verbatim instead of running the file-name heuristic. The
heuristic remains as the fallback path for the empty-`KnownType`
case (preserving backwards compatibility for ad-hoc or test
callers). `Resolve-LanguageSpecificPatchesFromCatalog` was reviewed
and already constructed its entries with `Type = $q.Type` directly,
so no change was needed on the LSP side.

### Fixed - Server2022 Catalogue narrow filter returned zero results

Live first-pass test also exposed that **every** Server 2022 query
fell through `Resolve-PatchSetFromCatalog`'s narrow filter with
zero hits, producing an empty `PatchBaseline.NeutralPatches`
array for `Config/Server2022.json`. Microsoft Update Catalogue has
since dropped the comma in Server 2022 update titles
("Microsoft server operating system, version 21H2" →
"Microsoft server operating system version 21H2", matching the
Server 2025 / 24H2 format). The hard-coded TitleToken used
`[regex]::Escape($titleToken)` (literal match including the
comma), so the new comma-less titles failed to narrow.

**Fix**: `Get-CatalogQueryTemplate` Server2022 branch and
`Get-LanguagePackQueryTemplate` `osTitleTokens` now accept BOTH the
comma-less and the historical comma form via an OR-matched
`TitleTokens` array. The actual `Search.aspx` query strings were
also updated to the current (comma-less) form because that is
what the live Catalogue listings display. The new structure is
robust against any future Microsoft re-edit that flips the format
back.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` now resolves 5 patch entries (LCU + 2 .NET files +
supersedence-dedup of 3 stale .NET candidates), versus 0 before
the fix.

### Fixed - umbrella .NET CU lost N-1 sub-files

Live first-pass test exposed that umbrella .NET Cumulative Update
KBs (e.g. Server 2019 KB5088864 which bundles 4.7.2 and 4.8) lost
all but one MSU when `Select-CanonicalPatchFile` was called: the
function is designed to return a single best file, and there is no
genuine ranking between two ndp-runtime variants of the same
umbrella KB, so the second .msu was silently dropped. Effect: on
an install.wim that contains the dropped runtime, the .NET CU
would have been a no-op and the corresponding CVEs would have
remained unpatched.

**Fix**: added `Select-AllCanonicalPatchFiles` (companion to the
existing single-file picker). It applies the same scoring rules
(so Express / Delta / PSF / metadata are still rejected) but
returns every link that scored > 0. `Resolve-PatchSetFromCatalog`
now routes `Type='DotNet'` queries through the multi-file picker
and emits one `NeutralPatches` entry per surviving file, all
keyed off the same umbrella KB / UpdateId / Title. SSU / LCU /
SafeOS / Setup DU queries continue to use the single-file picker
since Microsoft publishes a single canonical file per UpdateId
for those types.

Verification: live `-Action RefreshAllBaselines -DryRun -OnlyOs
Server2022` for 2026-05 now keeps two .NET .msu files
(`...-x64-ndp481_...msu` and `...-x64-ndp48_...msu`) on the
KB5088862 umbrella entry, where r04.2 would have kept only one.

### Added - `Assert-WorkspacePreflight` (preflight check)

New mandatory preflight that runs before the Action dispatcher.
Two checks, both fatal:

1. **Config presence**. The four canonical
   `Config/Server<N>.json` files (Server2016, Server2019,
   Server2022, Server2025) must exist alongside the script. The
   check fails fast with a list of any missing files, so the run
   does not proceed into the Catalogue scrape only to throw a
   less-helpful "config not found" error in P02 / A01.
2. **Drive free space**. The drive backing `-WorkRoot` must have
   at least **100 GB** free. This is the documented minimum for
   an end-to-end `PrepareBuildVerify` run for one OS (input ISO
   ~7 GB + extracted source ~7 GB + mounted WIM scratch ~15 GB +
   patches ~10 GB + output ISO ~7 GB + DISM headroom). The disk
   check is skipped under `-DryRun` because dry runs do not
   actually write large files.

Preflight is placed **before** the Action dispatcher (rather than
inside P01) so that Admin actions like `-Action RefreshAllBaselines`
and `-Action DumpFieldClassification` (which never run P01) are
also protected. It is intentionally skipped for `-Action ListPhases`
(quick branch that exits without any workspace contact),
`-Action Cleanup` (whose entire purpose is to remove a
partially-built workspace), `-EnvironmentInfoOnly` (the user
explicitly asked for the env dump only), and `-SkipEnvCheck`
(operator override).

The existing P01 Step 4 disk-space check is retained as
informational only; the authoritative 100 GB enforcement happens
in the preflight, and Step 4 now only emits a warning when free
space is below 100 GB (which can only occur if `-SkipEnvCheck`
bypassed the preflight).

### Changed - `-WorkRoot` default is now script-relative

The default value of `-WorkRoot` has changed from the absolute
`C:\Temp\Workspace_UpdateWsi` to the script-relative
`Workspace_UpdateWsi`. The existing `Resolve-RelativeToScript`
helper resolves the relative path against `$Script:ScriptRoot`
(i.e. the directory containing `Update-WindowsServerIso.ps1`),
producing a workspace that lives next to the script tree by
default. Operators who relied on the old `C:\Temp\...` default
should pass `-WorkRoot 'C:\Temp\Workspace_UpdateWsi'` explicitly
or update their automation; the absolute-path override is
unchanged and still works.

The new default plays well with the preflight Config-presence
check above: when the workspace is script-relative, the
`Config/` directory checked by preflight is the same `Config/`
directory shipped with the script.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,627 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2025`:
  exit 2 (Manual fill expected), preflight passes, all 5 patch
  Types resolve correctly, supersedence dedup excludes one
  .NET 3.5+4.8.1 false-positive (unchanged from r04.2 behaviour).
- Live smoke `RefreshAllBaselines -DryRun -OnlyOs Server2022`:
  preflight passes, **5 patch entries resolve** (vs 0 in r04.2
  due to bug 2), the umbrella .NET CU keeps both ndp-runtime
  MSUs (vs 1 in r04.2 due to bug 3).

### Compatibility

- Existing `Config/Server<N>.json` files are unchanged in
  structure (Schema v2.0). r04.3 just produces correct `Type`
  fields and an extra .NET entry for umbrella KBs on the next
  `-Action RefreshAllBaselines` run.
- Operators who depended on the old `-WorkRoot` default need to
  either accept the new script-relative location or pass
  `-WorkRoot` explicitly.
- `ScriptVersion` is bumped to `update-wsi-2026.05.25-r04.3`;
  `ScriptTag` is `live-test-fixes-and-preflight-checks`.

## Documentation maintenance - 2026-05-24

### Added - `TESTING.md`

Created `TESTING.md` for this sub-project to align with the
repository-wide governance documented in the root [`README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md)
"Language Policy" section, which lists `TESTING.md` among the
sub-project documents that are maintained in English only. The
sister project `download-speakerdeck-oracle4engineer/` has carried
a `TESTING.md` from the start; adding one here brings this project
to parity.

Contents:

- **Section 0** — Verification status summary table
- **Section 1** — Static analysis gate (psa.py + PSScriptAnalyzer
  invocation and expected output)
- **Section 2** — Unit tests for the deterministic helpers
  (PatchPlan engine, sub-phase sequence builders,
  supersedence-aware deduplication; 14 test cases total)
- **Section 3** — Synthetic smoke tests 1 through 7 with command
  lines and acceptance criteria
- **Section 4** — Live Microsoft Update Catalogue verification
  (read-only network calls)
- **Section 5** — Operator-pending: real ISO integration. This
  section is intentionally a placeholder because the maintainer
  has no suitable Windows host with DISM access. The acceptance
  criteria are documented; the results table is empty until an
  operator runs the procedure end-to-end and submits results via PR.
- **Section 6** — Continuous integration coverage including the
  Stage 4 monthly-refresh workflow's role as a continuous
  verification of the Catalogue scrape paths
- **Section 7** — Discovered bugs and fix history (cross-references
  to the per-release CHANGELOG entries)

### Changed - sub-project `README.md` and `README.ja.md`

Both READMEs now list `TESTING.md` in the "Folder layout" /
「フォルダ構成」block and end with a paragraph pointing readers
to it ("If you want to know what has been verified and what is
still operator-pending, read TESTING.md").

### Changed - root `README.md` and `README.ja.md` (CI section)

The Continuous Integration section in both root READMEs was
updated to reflect the four `update-windows-server-iso` workflows
introduced in r03 and r03.1:

- The intro line changed from "four GitHub Actions workflows" to
  "eight GitHub Actions workflows" (the Japanese equivalent
  changed from "4 本" to "8 本").
- Four new rows were added to the badge table:
  Update-WindowsServerIso STAGE 1 (Linux), STAGE 2 (Windows),
  STAGE 3 (Synthetic full pipeline), STAGE 4 (Monthly baseline
  refresh).
- A new paragraph immediately after the badge table explains the
  Stage 4 workflow's distinctive `cron`-on-the-15th schedule, its
  PR-creation behaviour when `Config/Server*.json` baselines drift
  from the live Microsoft Update Catalogue state, and its
  classification as an operations workflow (not a quality gate;
  failures do not block other workflows).

These updates close a documentation gap that opened when the
Update-WindowsServerIso project was first added to the repository:
the per-sub-project STAGE 4 workflow existed in `.github/workflows/`
and was already documented in this project's CHANGELOG, but the
root READMEs had not been refreshed to reflect the new total
workflow count.

### Quality

- `psa.py` and PSScriptAnalyzer baselines are unchanged from
  r04.2 because no source code was modified. This is a
  documentation-only maintenance pass.
- `ScriptVersion` is **not** bumped; this entry follows the
  same precedent as the sister project's r21 cleanup commit
  (documentation-only changes do not require a script version
  change).

## [update-wsi-2026.05.24-r04.2] - 2026-05-24

### Added - Supersedence-aware Catalogue patch selection

`Resolve-PatchSetFromCatalog` (in `.build_part08c_catalog_scraper.ps1`)
now resolves the case where the OS-aware Catalogue search returns
multiple candidates for a single patch Type. Previously this case
silently picked `narrowed[0]` (sort-stable but with no real-world
meaning), which could let a wrong KB through when:

- The same monthly slot has both a preview and a final entry
- A neighbouring KB (e.g. a ".NET Framework 3.5 and 4.8.1 Cumulative
  Update") matches the OS Title token used in the LCU query
- Catalogue HTML structure changes confuse the narrowing predicate

The new logic invokes `Get-SupersedenceFromCatalog` for each
non-Preview narrowed candidate, then calls the new
`Select-LatestPatchBySupersedence` helper to keep only the latest
survivor. Excluded candidates are recorded in
`$Script:LastSupersedenceExclusions` for the caller's diagnostic CSV.

Supersedence lookup is only triggered when the narrowed candidate
count exceeds 1; the single-candidate case bypasses the extra HTTP
calls.

### Added - `Select-LatestPatchBySupersedence` helper

New module `.build_part09d_supersedence.ps1` (~200 lines) implements
the deduplication logic:

| Input cardinality | Behaviour |
|-------------------|-----------|
| 0 candidates | Returns `Best=$null`, `Excluded=@()` |
| 1 candidate  | Returns that candidate as Best |
| 2+ candidates | Exclusion pass: any candidate whose KbId or UpdateId appears in another candidate's `Supersedes` array is dropped; if exactly one survivor remains, it is the Best; if multiple survivors remain, sort descending by Title (Catalogue titles start with `YYYY-MM` so lexicographic desc = newest) and pick the first, marking the rest as `Ambiguous; chose newest by title` |
| Edge case (all candidates excluded each other) | Fall back to the first input candidate with a warning |

Each excluded entry carries `Type`, `ExcludedKbId`, `ExcludedTitle`,
`SupersededByKbId`, `SupersededByTitle`, `MatchedToken`, and a
human-readable `Reason` suitable for CSV emission.

### Added - `Get-KbIdFromUpdateTitle` helper

Small utility that extracts the `KB######` substring from a
Catalogue update title using the canonical `(KB\d{6,7})` pattern.
Returns an empty string when no KB id is present.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,368 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-LatestPatchBySupersedence` (5/5 PASS):
    * Two candidates with cand2 superseding cand1 -> cand1 excluded
    * Single candidate -> passthrough, no exclusion
    * Two candidates without supersedence relation -> ambiguous, title-desc tiebreak
    * Supersedes contains UpdateId (not KbId) -> substring match still works
    * Empty input -> Best=$null
- Unit tests for `Get-KbIdFromUpdateTitle`: extracts from canonical titles, returns empty for non-matches.
- Live Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`)
  exercises the supersedence path on real Microsoft Update Catalogue
  data and correctly excludes a stray .NET 3.5+4.8.1 candidate that
  the LCU OS-aware query had picked up as a false positive.

### Changed - Documentation cleanup

References to the deferred ".NET 3.5 Feature on Demand" item have
been removed from CHANGELOG and SPEC. The feature is no longer in
scope: Microsoft's recommended deployment path for .NET 3.5 is to
enable it after image deployment via `Install-WindowsFeature
NET-Framework-Core` (or `Add-WindowsCapability -Online`), not to
embed it in the image.

### Compatibility

- No schema change. Config files (`Config/Server*.json`) and the
  PatchPlan hashtable shape are unchanged from r04.1.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.2`;
  `ScriptTag` is `supersedence-aware-patch-selection`.
- Existing single-candidate Catalogue queries see no behaviour
  change (the extra `Get-SupersedenceFromCatalog` calls only fire
  when narrowing leaves 2 or more candidates).

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU). Microsoft
  Server LTSC editions rarely publish Setup DU, and verification
  requires a Windows host running setup.exe, so this is not
  high-leverage for our use case.
- Per-language Optional Components for WinRE.
- ISO release detection refresher for `LanguageSpecific.<lang>.Iso`.
- Python JSON Schema validator that consumes the
  `DumpFieldClassification` output.

## [update-wsi-2026.05.24-r04.1] - 2026-05-24

### Added - Microsoft media-dynamic-update servicing sub-phase engine

The PatchPlan engine introduced in r04 now emits ordered sub-phase
sequences (per-WIM-target) that reproduce Microsoft's official
servicing sequence end-to-end:

**install.wim sequence** (with twice-apply when language packs are
present):

| Sub-phase                    | Patches              | Notes |
|------------------------------|----------------------|-------|
| I1.SSU                       | SSU                  | servicing stack first |
| I2.LanguagePack              | LP / LXP / DotNet LP | must precede LCU |
| I3.LCU.FirstPass             | LCU                  | after LP per Microsoft |
| I4.DotNet                    | .NET CU              | |
| I5.DynamicUpdate.Component   | DU.Component         | |
| I6.CleanupAndExport          | (marker)             | DISM cleanup hook |
| I7.LCU.SecondPass            | LCU (re-applied)     | only when LP injected; requires remount |

**boot.wim sequence** (no twice-apply needed):

| Sub-phase | Patches | Notes |
|---|---|---|
| B1.SSU              | SSU         | |
| B2.LanguagePack     | LP          | recovery UI language |
| B3.LCU              | LCU         | |
| B4.CleanupAndExport | (marker)    | |

**WinRE.wim sequence** (Safe OS DU replaces LCU per Microsoft):

| Sub-phase | Patches | Notes |
|---|---|---|
| W1.SSU              | SSU                  | (combined LCU acts as SSU surrogate) |
| W2.LanguagePack     | LP                   | recovery UI |
| W3.SafeOsDU         | DynamicUpdate.SafeOs | WinRE-only LCU substitute |
| W4.CleanupAndExport | (marker)             | Export /Compress:Recovery |

### Added - LCU twice-apply (I7.LCU.SecondPass)

Per Microsoft's documented rationale: when a language pack is
injected into install.wim, the LP can shadow files that the LCU
delivered on its first pass, leaving the LCU partially un-applied.
The fix is to re-apply the LCU AFTER the WIM has been
dismounted+committed+exported. The engine emits I7 only when
language packs are actually present in the plan; otherwise the
single-pass flow is preserved (no wasted remount).

The P07 worker honours the I7.RequiresRemount = $true flag by
dismounting after I1-I6, then re-mounting the now-serviced
install.wim for the I7 sub-phase, then dismounting again.

### Added - Full WinRE servicing worker

P08's WinRE block now reads the WinReSequence (W1.SSU -> W2.LP ->
W3.SafeOsDU -> W4.CleanupAndExport) from the cached PatchPlan and
applies each sub-phase against the WinRE.wim it extracted from
install.wim. The serviced WinRE is then copied back into the
install.wim mount so the surrounding install.wim dismount commits
the change. Skips the WinRE mount entirely when the sequence is
empty.

### Added - Invoke-PatchSubPhase common helper

A single helper drives the per-sub-phase apply loop for all three
sequences (Install / Boot / WinRE). It handles DryRun, missing
LocalPath, and Add-WindowsPackage failures uniformly, emits per-
patch result rows for the CSV inventory, and writes structured
error records via Add-ErrorJsonlEntry on failure.

### Added - Build-{Install,Boot,WinRe}ApplySequence builders

These three helpers (in .build_part09c_patchplan.ps1) bucket the
flat patch list per Type and emit the ordered sub-phase array. The
mapping logic (which Type belongs to which sub-phase, when to emit
I7, etc.) is centralised here so future tweaks (e.g. adding a new
SafeOS DU lane to install.wim) only touch one place.

### Changed - P07 / P08 worker control flow

Both phase workers now consume sub-phase sequences instead of a
flat patch list. The legacy `Get-PatchListForInstall|Boot|WinReWim`
helpers (introduced in r04) remain in place for backwards
compatibility with diagnostic consumers; the workers themselves
no longer iterate them. CSV inventory rows now include the new
`SubPhase` column.

P07's install.wim block iterates the install sequence in order;
when a sub-phase has RequiresRemount = $true it is deferred into
a second-pass buffer that runs after the first dismount completes.
This produces a 1-mount or 2-mount pattern depending on whether
language packs are present, matching the Microsoft sequence
exactly.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (7,112 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Sub-phase engine unit tests (5/5 PASS):
    * I7 NOT emitted when no LP in plan
    * I7 emitted with RequiresRemount=$true when LP present
    * boot.wim sequence: B1.SSU -> B2.LP -> B3.LCU -> B4.cleanup
    * WinRE sequence: W1.SSU -> W2.LP -> W3.SafeOsDU -> W4.cleanup (LCU is NOT in WinRE)
    * Empty input -> skeleton sub-phases all present, all empty
- Smoke 3 (Synthetic+DryRun): PatchPlan summary now shows all three
  sub-phase sequences end-to-end.

### Compatibility

- No schema change. PatchTargetMap and PatchDependencyPolicy from
  r04 are unchanged.
- The PatchPlan hashtable gains three new keys (InstallSequence,
  BootSequence, WinReSequence) but the legacy lane keys
  (Install / Boot / WinRE / Setup) are still present and still
  hold the flat sorted lists.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04.1`;
  `ScriptTag` is `lcu-twice-winre-and-lp-injection`.

### Out of scope (deferred to a future release)

- Setup binaries servicing via pending.xml (Setup DU).
- Per-language Optional Components for WinRE.

## [update-wsi-2026.05.24-r04] - 2026-05-24

### Added - WIM-target-aware patch plan engine

A new module (`.build_part09c_patchplan.ps1`) introduces the
`Build-PatchPlan` function that converts the flat
`$Script:ResolvedPatches` array into a target-aware plan with four
lanes:

| Target | Receives |
|--------|----------|
| Install | every patch whose Type maps to "Install" |
| Boot    | every patch whose Type maps to "Boot"    |
| WinRE   | every patch whose Type maps to "WinRE"   |
| Setup   | every patch whose Type maps to "Setup"   |

The mapping is centralised in the new `$Script:PatchTargetMap`
constant in `.build_part03_helpers.ps1`. Following Microsoft's
media-dynamic-update guidance:

| Patch Type              | Targets                  |
|-------------------------|--------------------------|
| SSU                     | Install + Boot + WinRE   |
| LCU                     | Install + Boot           |
| DotNet                  | Install                  |
| DynamicUpdate.Component | Install                  |
| DynamicUpdate.SafeOs    | WinRE                    |
| DynamicUpdate.Setup     | Setup                    |
| LanguagePack            | Install + WinRE          |
| LXP                     | Install                  |
| DotNet.LangPack         | Install                  |

Unknown Types fall back to `[Install]` with a one-time warning per
unique unknown Type.

P02 (`ResolveInputs`) now builds the plan and prints a per-target
summary at the end of the phase. P07 and P08 retain their legacy
`Get-PatchListForInstall|Boot|WinReWim` helpers; these now delegate
to the cached plan so existing call sites stay unchanged.

### Added - Pre-apply dependency closure check

A new helper, `Test-PatchDependencyClosureOnMount`, runs inside the
P07 install.wim and P08 boot.wim apply loops immediately after the
WIM mount and just before the first `Add-WindowsPackage` call. For
each patch whose `RequiresKbIds` is non-empty, it enumerates the
mounted image via `Get-WindowsPackage` and verifies that every
required KB is already present (`PackageIdentity` substring match
against the recorded KB ID).

The check is governed by `$Script:PatchDependencyPolicy`, default
`'Strict'`. Strict mode throws on the first unsatisfied
prerequisite, aborting the run before DISM emits the cryptic
0x800f0823 servicing-stack precondition error. The alternate
`'Warn'` mode logs a warning and continues; there is no CLI flag
yet, but the variable can be set from a wrapper script.

`-DryRun` short-circuits the check with a notice (no real mount to
enumerate against).

### Changed - Patch selection helpers delegate to PatchPlan

The legacy `Get-PatchListForInstallWim` / `Get-PatchListForBootWim`
helpers in `.build_part12_phase05_06_07.ps1` are now thin wrappers
that read from the cached `$Script:PatchPlan`. A new
`Get-PatchListForWinReWim` helper is added for completeness; the
WinRE worker itself is delivered in a follow-up release together
with the LCU twice-apply pattern and language-pack injection.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,700 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Build-PatchPlan`:
    * Typical monthly patch set (SSU/LCU/.NET/SafeOS/Setup) routes
      to the expected lanes
    * LP/LXP correctly differentiated (LP -> Install+WinRE; LXP ->
      Install only)
    * Unknown Type falls back to Install with warning
    * Empty input handled gracefully
- All existing smoke tests still pass; Smoke 5 (live Catalogue
  scrape against Server2025 / 2026-05) resolves 3 patches and the
  combined-LCU detection still fires.

### Compatibility

- Schema v2.0 is unchanged. The new mapping lives in script code
  rather than in the Config files, so adding a new patch Type only
  requires editing `$Script:PatchTargetMap`.
- Existing PatchBaseline entries continue to work; the engine
  reads `.Type`, `.KbId`, `.ApplyOrder`, `.RequiresKbIds` and
  ignores everything else.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r04`;
  `ScriptTag` is `wim-target-aware-patch-plan`.

### Out of scope (deferred to the next release in the r04 line)

- LCU twice-apply sequence in P07 around language-pack injection.
- WinRE.wim mount / service / dismount worker in P08.
- Language Pack injection on install.wim and WinRE.wim.

## [update-wsi-2026.05.24-r03.1] - 2026-05-24

### Added - Stage 4 CI workflow: monthly baseline refresh

A new GitHub Actions workflow,
`.github/workflows/scripts__powershell__update-windows-server-iso__stage4__monthly-refresh.yml`,
runs `-Action RefreshAllBaselines` on a schedule and opens an
automated pull request whenever the `Config/Server*.json` baselines
change. This completes the runtime story for r03's admin action:
baseline maintenance now happens without any human invocation.

Schedule: 02:00 UTC on the 15th of every month. Patch Tuesday is the
second Tuesday (8th-14th of the month); waiting until the 15th gives
Microsoft a 1-7 day window for late re-publications and Catalogue
indexing to settle.

Manual invocation: `workflow_dispatch` with four inputs:
- `mode`         : Monthly / Initial / Force (default: Monthly)
- `onlyOs`       : Server2016 / 2019 / 2022 / 2025 or blank for all
- `onlyLanguage` : en-us / ja-jp or blank for all
- `dryRun`       : true / false (default: false)

The workflow accepts the PowerShell exit code semantics established
in r03: 0 (clean) and 2 (some Manual fields remain) are treated as
success; 1 (orchestrator failure) and anything else fails the run.

PR contents:
- Title: `chore(uwsi): monthly baseline refresh (run #<id>)`
- Branch: `auto/uwsi-baseline-refresh-<id>` (deleted after merge)
- Files: only `scripts/powershell/update-windows-server-iso/Config/*.json`
- Labels: `automated`, `update-windows-server-iso`, `baseline-refresh`
- Body includes the run parameters, exit code, modified-file list,
  and a reviewer checklist for verifying combined-LCU flags and
  PatchTuesdayOfBaseline correctness.

Artefacts:
- `A01_RefreshAllBaselines_report.csv` (per-group decision matrix)
- `debugtrace.jsonl` (script-side trace)

both uploaded to the workflow run with 30-day retention.

A GitHub Actions step summary (`$env:GITHUB_STEP_SUMMARY`) is
always written, even on failure, so the maintainer can see at a
glance what happened without diving into logs.

### Notes

- The PowerShell script body itself is unchanged from r03; r03.1 is
  purely an operations release. `ScriptVersion` is bumped to
  `update-wsi-2026.05.24-r03.1` so workflow runs and PR commit
  messages identify the operations level distinctly from r03.
- `ScriptTag` is `stage4-monthly-refresh-ci`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings.
- All existing smoke tests still pass.
- YAML syntax validated via PyYAML (8 steps).

### Compatibility

- Pure additive change: a new file under `.github/workflows/`. The
  three existing workflows (Stage 1 Linux / Stage 2 Windows / Stage 3
  synthetic-pipeline) are untouched.

### Out of scope (deferred to r04 onward)

Per the "未実装機能の全体マップ" review, the next deliverables are:
- r04: Microsoft-official servicing sequence compliance
  (WIM-target-aware patch plan; LCU twice-apply; pre-apply
   Get-WindowsPackage dependency closure check; WinRE servicing;
   per-WIM AppliesTo metadata; Language Pack injection in P07).
- r05: Supersedes-based superseded KB auto-removal; ISO-release
  refresher; Python JSON Schema validator.

## [update-wsi-2026.05.24-r03] - 2026-05-24

### BREAKING - Config Schema v2.0 (no migration path)

The Config/Server*.json data model has been redesigned with a 3-tier
hierarchy. There is NO migration sidecar; r02.x configs are rejected
by Get-ConfigProfile with a clear error message. Configs must be
either authored manually as v2.0 or generated by RefreshAllBaselines.

The new layout separates three concerns:
- `Common`           : OS-wide constants (build, edition, WIM index)
- `PatchBaseline`    : neutral patches (SSU/LCU/.NET CU/DU.*) shared
                       across all languages
- `LanguageSpecific` : per-language ISO source + LP / LXP / .NET LP

Adding a new language now requires only one node under
`LanguageSpecific` plus listing it in `Common.SupportedLanguages`.

Each field group carries a verification marker:
- `Common._VerifiedDate` / `Common._VerifiedBy`
- `PatchBaseline.LastVerifiedDate` / `LastVerifiedBy`
- `LanguageSpecific.<lang>.Iso._VerifiedDate` / `_VerifiedBy`
- `LanguageSpecific.<lang>.LanguageSpecificPatches.LastVerifiedDate`
   / `LastVerifiedBy` / `PatchTuesdayOfBaseline`

An empty `_VerifiedDate` flags the group as "unresolved" for the
RefreshAllBaselines decision matrix.

### Added - `Action.RefreshAllBaselines` (Admin phase A01)

```
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -DryRun
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Initial
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -Mode Force
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyOs Server2025
.\Update-WindowsServerIso.ps1 -Action RefreshAllBaselines -OnlyLanguage ja-jp
```

Three operating modes:

| Mode    | What gets refreshed |
|---------|---------------------|
| Initial | Every field group whose `_VerifiedDate` is empty |
| Monthly | Field groups whose Cadence is `PatchTuesday` AND whose recorded `PatchTuesdayOfBaseline` is older than the latest Patch Tuesday (default) |
| Force   | Every field group, regardless of verification state or cadence |

For each field group the decision is one of: `Skip` (verified and
current), `InitialFill` (auto-fill an empty group, requires
Refresher), `Monthly` (auto-refresh due to new Patch Tuesday), or
`Manual` (no Refresher available, group must be populated by hand).

A CSV report is emitted to
`<WorkRoot>/logs/A01_RefreshAllBaselines_report.csv` with the
per-group decision; the on-screen summary groups counts by decision
type. Exit codes: 0 (all OK), 1 (one or more Refresher calls failed),
2 (some fields require manual fill).

### Added - `Action.DumpFieldClassification` (Admin phase A02)

Emits `<WorkRoot>/logs/A02_FieldClassification.json` containing the
`$Script:OsConfigFieldGroups` constant, intended for downstream
Python tooling (a future JSON Schema validator). No Catalogue
network access is required.

### Added - Field classification constant

`$Script:OsConfigFieldGroups` is a top-level constant declared in
`.build_part03_helpers.ps1` that maps each logical field group to a
Cadence (Stable / PatchTuesday / IsoRelease) and an optional
Refresher function name. Adding a new field group is a one-line
addition followed by either implementing a new Refresher or leaving
it Manual.

### Added - Per-language patch scraper

New helper `Resolve-LanguageSpecificPatchesFromCatalog` queries
Microsoft Update Catalog for Language Pack, LXP, and .NET Framework
Language Pack matching `OsVersion` + `OsLanguage` + `PatchMonth`.
Best-effort: empty results are treated as "verified absence" rather
than failures, because Microsoft does not publish LP / LXP for every
OS x month combo. Reuses `Select-CanonicalPatchFile` from r02.5 for
file picking.

### Fixed - Stage 2 Smoke 3 (Synthetic+DryRun) failed at P05

`New-SyntheticTestIso` produces a structurally-degenerate ISO9660
image (4-byte placeholder boot files wrapped by oscdimg.exe) that
`Mount-DiskImage` in P05 rejects as "file or directory is corrupted".
Stage 3 (Synthetic+Execute) already bypassed P05 by going straight
to P07; this aligns Stage 2 Smoke 3 with that flow by removing
`P05` and `P06` from `PrepareBuildVerify` / `All` when
`$Script:SyntheticTestMode -eq $true`. No behaviour change for
non-synthetic runs.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (6,344 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Smoke 1 (`-Action ListPhases`): exit 0; A01 / A02 registered;
  Actions section lists `RefreshAllBaselines : A01` and
  `DumpFieldClassification : A02`.
- Smoke 2 (`-EnvironmentInfoOnly`): exit 0; P01 only.
- Smoke 3 (`-SyntheticTestMode -DryRun`): P01 SKIPPED -> P02 DONE ->
  P03 DONE (skip) -> P04 DONE (synthetic ISO) -> P07 ... (P05 /
  P06 are correctly absent from the phase list on Windows).
- Smoke 4 (`-Action DumpFieldClassification`): exit 0; JSON written.
- Smoke 5 (`-Action RefreshAllBaselines -DryRun -OnlyOs Server2025`):
  exit 2 (DryRun + unresolved Iso fields); all 4 field groups
  produce the expected decision (Common=Skip, PatchBaseline=Monthly,
  Iso=Manual x2, LangSpecificPatches=Monthly x2).
- Smoke 6 (`-Mode Force -OnlyLanguage ja-jp`): Force overrides Skip
  for verified Common (-> Manual); OnlyLanguage filters out en-us.
- Smoke 7 (`-Mode Initial`): same decisions as Monthly for this
  baseline (PatchTuesdayOfBaseline empty -> Monthly).

### Compatibility

- This is a destructive schema change. r02.x Configs will be
  rejected. Authoring new Configs by hand is supported; the easiest
  path is to start from a v2.0 Config in this repo and adjust the
  `Common.Build` / `LanguageSpecific.<lang>.Iso.Url` fields.
- `ScriptVersion` is `update-wsi-2026.05.24-r03`;
  `ScriptTag` is `schema-v2-and-refresh-all-baselines`.

### Out of scope (deferred to r04 Option Z)

- WIM-target-aware patch plan (install/boot/winre per-target patch
  lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Pre-apply Get-WindowsPackage dependency closure check.

## [update-wsi-2026.05.24-r02.5] - 2026-05-24

### Fixed - Catalogue search precision + multi-file disambiguation (Option X)

r02 introduced Microsoft Update Catalogue scraping (P03) with three
quality issues that this release fixes. The fixes are based on
Microsoft's official media-dynamic-update guidance plus a review of
WIM Witch, WimWizard, and WIM-Tools reference implementations.

**Problem A - OS-version-aware Catalogue query templates.**
Previously, queries used a loose token like `"servicing stack update
Windows Server 2022"`. Microsoft's actual Catalogue Title pattern for
Server 2022 is `"... Servicing Stack Update for Microsoft server
operating system, version 21H2"` (with a literal comma) and requires
a `Product` / `Description` disambiguator to separate Setup-DU from
SafeOS-DU. The previous loose match could conflate multiple OS
versions in results. Replaced with `Get-CatalogQueryTemplate` which
returns the exact Title patterns documented in
https://learn.microsoft.com/windows/deployment/update/media-dynamic-update,
per OS version (2016 / 2019 / 2022 / 2025).

**Problem B - Combined LCU detection.**
Since 2021 Microsoft embeds the SSU into the LCU and publishes
standalone SSUs only "in rare cases of a breaking change"
(Microsoft Learn quote). The previous code's
`RequiresKbIds = $ssuKbs` assignment treated SSU as always-present
and could falsely report "missing SSU" in P06 validation. Added
`Test-IsCombinedLcuTitle` (explicit marker check) and a structural
detector inside `Resolve-PatchSetFromCatalog` that treats
"SSU search returned zero AND LCU search returned non-zero" as a
combined-LCU month. In combined months, the LCU entry is annotated
with `IsCombined=$true` and its `RequiresKbIds` is left empty.

**Problem C - Multi-file Catalogue selection.**
The previous code did `$primary = $links[0]`, which for .NET
Cumulative Updates and other multi-file packages was a coin toss
between Full, Express, and Delta variants. Picking Express / Delta
breaks `Add-WindowsPackage` because differential packages require a
base. Replaced with `Select-CanonicalPatchFile`, a scoring-based
picker that rejects `express`, `delta`, `psf`, and metadata text
files outright, and prefers `.msu > .cab`, matching architecture,
and (for .NET) matching `ndp<version>` markers.

### Added

- `Get-CatalogQueryTemplate` (~150 lines): OS-specific Catalogue
  Title templates + optional Product / Description filters.
- `Get-CatalogQueryUrl` (~30 lines): builds a Search.aspx URL with
  quoted Product / Description filter tokens.
- `Test-IsCombinedLcuTitle` (~15 lines): title-level combined marker.
- `Select-CanonicalPatchFile` (~80 lines): scoring-based file picker.
- LCU entries now carry an `IsCombined` boolean property in
  PatchBaseline; all patch entries carry a `Variant = 'Full'` string
  (placeholder for r03's `Variants[]` array).

### Changed

- `Resolve-PatchSetFromCatalog` reworked as a two-pass orchestrator:
  pass 1 runs all per-type Catalogue searches and records narrowed
  candidates; the combined-LCU detector runs on the aggregate; pass 2
  resolves the single canonical download file per surviving candidate
  via `Select-CanonicalPatchFile`. Eliminates `$primary = $links[0]`.
- Server 2019 / 2016 queries no longer include `DynamicUpdate.Setup`
  or `DynamicUpdate.SafeOs` (Microsoft does not publish those monthly
  for the older Server LTSC SKUs; they only appear during feature-
  update windows). `Test-PatchBaselineUsable` continues to accept
  partial sets so this is not a regression.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,611 lines).
- PSScriptAnalyzer 1.25.0: 0 findings.
- Unit tests for `Select-CanonicalPatchFile` and
  `Get-CatalogQueryTemplate` pass:
    * full + express -> selects full
    * delta only -> returns null
    * Server 2022 template contains comma form
    * .NET CU with ndp48 prefers the ndp48 variant

### Compatibility

- PatchBaseline schema remains at "1.0". The new `IsCombined` and
  `Variant` fields are added via `Add-Member -Force` so existing
  `Save-ConfigWithBaseline` rewrites them as ordinary JSON properties.
- Existing r02.4 Configs are read transparently; missing
  `IsCombined`/`Variant` fields default to `$false`/`'Full'` when
  consumed by P04/P06/P07.
- `ScriptVersion` is bumped to `update-wsi-2026.05.24-r02.5`;
  `ScriptTag` is `catalog-multifile-and-combined-lcu`.

### Out of scope (deferred to r03 Option Y / Z)

- WIM-target-aware patch plan (install/boot/winre per-target
  patch lists per Microsoft media-dynamic-update sequence).
- LCU twice-apply pattern around language-pack injection.
- Language Pack acquisition per `OsLanguage`.
- Pre-apply `Get-WindowsPackage` dependency closure check.

## [update-wsi-2026.05.24-r02.4] - 2026-05-24

### Fixed - `-EnvironmentInfoOnly` smoke test failed on Windows runner

The `-EnvironmentInfoOnly` switch is intended to be a CI-friendly
"dump PowerShell environment info and exit 0" smoke flag. It was
working in spirit (the Step 0 environment dump did print, with a
message `EnvironmentInfoOnly requested; exiting after env dump.`)
but it was NOT actually exiting the script. The reason: P01's check
issued a bare `return`, which only leaves the phase function. The
phase runner then proceeded to P02 (`ResolveInputs`), which throws
`-OsVersion is required for P02 (...)` because the smoke caller
deliberately omits `-OsVersion`. Stage 2 reported exit code 1.

This was a latent bug present since r01. It was hidden in early
Stage 2 runs because the run-level summary did not surface P02's
internal throw clearly; the recent Stage 2 logs in r02.3 made the
P02 failure visible, which is how it was caught.

Fix: add an `EnvironmentInfoOnly` early branch in the main entry
point that pins `$phaseList = @('P01')` before dispatching. P02+
are simply not in the dispatch list, so the post-P01 flow runs the
normal phase-summary tail and the script exits 0. The pre-existing
`return` inside `Invoke-SetupPhase01_Initialize` still works as a
graceful exit point for Step 0; nothing else in P01 fires.

This complements (rather than replaces) the existing
`Action -eq 'ListPhases'` and `Action -eq 'Cleanup'` early-exit
branches, matching the same idiom.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.

### Compatibility

- Surface behaviour change is localised to `-EnvironmentInfoOnly`:
  it now exits 0 cleanly after P01 instead of erroring out in P02.
  No other code path is affected.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.4`;
  `ScriptTag` is `environment-info-only-early-exit`.

## [update-wsi-2026.05.24-r02.3] - 2026-05-24

### Fixed - legacy error-helper cleanup (inherited from r01)

`Update-WindowsServerIso.ps1` carried three latent API signature
mismatches inherited from r01 that did not show up in the smoke tests
because they only surface on a failure path under specific conditions.
Fixing them now so the next genuine failure produces a readable error
message instead of a misleading "parameter not found" secondary error.

- `Add-ErrorJsonlEntry`: the function body was a verbatim copy from
  the SpeakerDeck downloader project that produced this script's
  scaffold. It took a single `-Item` parameter and serialised
  SpeakerDeck-specific fields (`DeckUrl`, `PublishDate`, etc.).
  Both call sites in this script
  (`Invoke-BuildPhase07_PatchInstallWim`'s `Add-WindowsPackage` catch,
  and `Invoke-PhaseRunner`'s top-level phase catch) instead pass
  `-Phase / -Kind / -Properties` for a generic phase-failure record.
  The two surfaces had been silently incompatible since r01.
  Rewrote `Add-ErrorJsonlEntry` to the actual contract the callers
  use: `-Phase <PNN> -Kind <label> -Properties <hashtable>`, merging
  the hashtable into a fixed-schema JSON object with reserved-key
  protection.
- `Enable-DebugTraceFileOutput`: the function declares `-Directory`
  but was called with `-LogsDir`. Fixed at the call site in the
  top-level script body.
- `Enable-AutoExportOnPhaseFailure`: declares `-OutputDirectory`
  but was called with `-DiagDir`. Fixed at the call site.

### Removed - SpeakerDeck-downloader dead code

The following functions were inherited verbatim from the SpeakerDeck
downloader scaffold and were never referenced by any ISO Updater code
path. Removed to eliminate confusion and reduce surface area:

- `Get-FailureCategory` (HTTP / IO / WebException categorisation
  tailored for SpeakerDeck failures).
- `Write-FailureDiagnostic` (per-deck plain-text dump under
  `$Script:FailedDir`, a variable that this script never sets).

A stale reference to `Write-FailureDiagnostic` in a comment inside
`.build_part04_debugtrace.ps1` was also cleaned up.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info.
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- Line count: 5,452 -> 5,310 (-142, all dead-code removal).
- All 11 `Start-DebugTrace` call sites use `-Context <fn> -PhaseId <PNN>`.
- All 2 `Add-ErrorJsonlEntry` call sites use `-Phase / -Kind / -Properties`.
- All `Enable-*` debug-trace setup calls use the correct parameter names.

### Compatibility

- Pure cleanup release: behaviour is identical for the successful
  pipeline (no `Add-ErrorJsonlEntry` calls occur on the happy path).
- The first observed change will be in the on-disk format of
  `<WorkRoot>/logs/<...>_errors.jsonl` when a phase actually fails:
  it now contains the intended `phase` / `kind` / caller-supplied
  diagnostic properties instead of the previous (never-reached)
  SpeakerDeck-shaped record.
- `ScriptVersion` bumped to `update-wsi-2026.05.24-r02.3`;
  `ScriptTag` is `legacy-error-helper-cleanup`.

## [update-wsi-2026.05.24-r02.2] - 2026-05-24

### Fixed — Stage 2 smoke-test failure introduced by r02

r02.1 cleared the PSScriptAnalyzer findings, but the Stage 2 job still
exited 1 because Smoke test 3 (`-Action PrepareBuildVerify
-SyntheticTestMode -DryRun -SkipEnvCheck`) hit a fatal error inside the
new phase P03. Root cause: when `Start-DebugTrace` was called from the
two new phase workers I introduced in r02, the wrong parameter name
`-PhaseName` was used. The correct name (used by every other phase in
this script) is `-Context`. PowerShell 5.1's partial-match logic
reported the failure as "A parameter cannot be found that matches
parameter name 'Phase'." because `-PhaseId` and `-PhaseName` collide
on the same prefix.

- `Invoke-SetupPhase03_RefreshPatchBaseline`:
  `Start-DebugTrace -PhaseName 'P02.5_RefreshPatchBaseline' -PhaseId 'P03'`
  becomes
  `Start-DebugTrace -Context 'Invoke-SetupPhase03_RefreshPatchBaseline' -PhaseId 'P03'`
  (mirrors the call shape used by P01 through P13).
- `Invoke-PlanPhase06_ValidatePatchSet`:
  `Start-DebugTrace -PhaseName 'P04.5_ValidatePatchSet' -PhaseId 'P06'`
  becomes
  `Start-DebugTrace -Context 'Invoke-PlanPhase06_ValidatePatchSet' -PhaseId 'P06'`.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning /
  Information.
- All 11 `Start-DebugTrace` call sites now use the canonical
  `-Context <function-name> -PhaseId <PNN>` shape.

### Compatibility

- Pure parameter-name fix in two new functions; no behavioural or
  schema change. r02.1 callers see no surface-level difference.
- `ScriptVersion` is bumped from `update-wsi-2026.05.24-r02.1` to
  `update-wsi-2026.05.24-r02.2`. The `r02.2` suffix communicates a
  second fix-up release of the r02 line.

## [update-wsi-2026.05.24-r02.1] - 2026-05-24

### Fixed — Stage 2 PSScriptAnalyzer (Windows PS 5.1) findings

r02 (`50fdb0f`) passed Stage 1 (Linux pwsh 7 + psa.py 0/0/0) but
failed Stage 2 (Windows PS 5.1 + microsoft/psscriptanalyzer-action)
on three rule categories that psa.py does not enforce. r02.1 addresses
all of them while keeping psa.py at 0/0/0.

- **`PSAvoidUsingBrokenHashAlgorithms`** (Severity = Error; the actual
  cause of the Stage 2 exit-code-1 failure) at `Test-PatchIntegrity`'s
  L2a/L2b SHA-1 checks. The function intentionally uses SHA-1 to
  sanity-check the SHA-1 hashes Microsoft Update Catalogue publishes
  alongside its patches, with SHA-256 (L2c) and Authenticode signatures
  (L3) as the real trust anchors. The previous `# psa-disable-line
  PSA5003 -- MS Catalog SHA-1` comments are a psa.py-specific
  suppression and do not affect the upstream `PSAvoidUsing*` rule.
  Replaced with a function-level
  `[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
       'PSAvoidUsingBrokenHashAlgorithms', '', Justification = '...')]`
  which is the canonical PSScriptAnalyzer suppression mechanism.
- **`PSUseDeclaredVarsMoreThanAssignments`** (Severity = Warning) at
  `Invoke-HyperVBootTest`'s `$vm = New-VM ...` assignment. The local
  `$vm` was never read again (subsequent operations use the VM name).
  Replaced with `New-VM ... | Out-Null` to match the surrounding
  Hyper-V calls' style.
- **`PSUseOutputTypeCorrectly`** (Severity = Information; x9 instances)
  at `Get-PhaseListByAction`'s nine `return @(...)` arms. PSSA
  cannot infer that an unannotated `@('a','b')` collection literal
  conforms to the declared `[OutputType([string[]])]`. Each `return`
  is now cast explicitly: `return [string[]]@('P01', 'P02', ...)`.

### Fixed — preventive (not yet observed on CI)

Local PSScriptAnalyzer 1.25.0 also surfaces one `PSReviewUnusedParameter`
warning (`$OsLanguage` declared but unused) inside
`Resolve-PatchSetFromCatalog`. CI's psscriptanalyzer-action@v1.1
appears to ship an earlier PSSA build that does not include this rule,
but to avoid future surprises the parameter is now used by an
informational `Write-Step` call at the head of the function.

### Quality

- psa.py: 0 errors / 0 warnings / 0 info (5,452 lines).
- PSScriptAnalyzer 1.25.0: 0 findings at Severity Error / Warning / Information.

### Compatibility

- Pure additive / mechanical changes: no behavioural difference from
  r02 at runtime.
- `ScriptVersion` is bumped from `update-wsi-2026.06.10-r02` to
  `update-wsi-2026.05.24-r02.1`; the `r02.1` suffix communicates a
  fix-up release of the r02 line.

## [update-wsi-2026.06.10-r02] - 2026-06-10

### Added — dynamic baseline (M2)

- New parameter `-PatchMonth yyyy-MM` to scope the Catalogue search
  (default: current month's Patch Tuesday).
- New parameter `-SkipDynamicPatchRefresh` to bypass P03 even when
  the baseline is stale (offline / air-gapped runs).
- New parameter `-UseBaselineOnly` to forbid all Catalogue access
  and use `PatchBaseline.Patches` strictly as-is.
- New phase **P03 RefreshPatchBaseline**: when
  `PatchTuesdayOfBaseline < Get-LatestPatchTuesday()`, scrape the
  Microsoft Update Catalogue for the target month (SSU + LCU +
  DynamicUpdate.Setup + DynamicUpdate.Component + DynamicUpdate.SafeOs
  + .NET CU), populate `PatchBaseline.Patches`, and write back to
  `Config/<OsKey>.json` atomically.
- Three scraper helpers (`Get-UpdateIdFromCatalog`,
  `Get-DownloadLinkFromCatalog`, `Get-SupersedenceFromCatalog`) that
  use `-UseBasicParsing` for Windows PowerShell 5.1 compatibility,
  set a polite User-Agent, and apply up to `ScrapeRetries` retries
  with jitter on transient HTTP failures.
- `Resolve-PatchSetFromCatalog` orchestrator that issues per-patch-type
  Catalogue queries, filters by OS title token + `x64` architecture,
  and auto-links each LCU's `RequiresKbIds` to the SSU(s) found in
  the same pass.
- Patch Tuesday calculator (`Get-PatchTuesdayForMonth`,
  `Get-LatestPatchTuesday`) with a 1-day buffer to avoid same-day
  edge cases (SPEC §D.15).

### Added — dependency validation (M3)

- New parameter `-WsusScnCabPath` to point at a pre-staged
  `wsusscn2.cab` instead of triggering an automatic download.
- New parameter `-IgnorePatchValidation` to demote P06 failure
  from abort to warning (NOT recommended for production).
- New phase **P06 ValidatePatchSet**: after the install.wim is
  extracted, optionally download (initial run OR cache older than
  current Patch Tuesday) and run a Windows Update Agent COM API
  offline scan with `Microsoft.Update.Session` against the supplied
  patch set. On any missing required patch: ABORT.
- Four diagnostic files emitted under `<WorkRoot>/diag/<timestamp>/`
  on validation failure:
    - `validation_summary.json` (top-level result + missing list)
    - `validation_detail.csv` (one row per patch with Provided / RequiredByWUA / DownloadHint)
    - `wsusscn2_scan_raw.json` (full raw WUA output)
    - `dependency_graph.json` (KB Requires / Supersedes adjacency)
- Diagnostic files are always emitted on detected-missing, regardless
  of `-IgnorePatchValidation`.

### Changed

- ScriptVersion: `update-wsi-2026.06.10-r02`,
  ScriptTag: `dynamic-baseline-and-wsusscn2-validation`.
- Banner unchanged: "Windows Server ISO Updater".
- P02 ResolveInputs: the patch-source resolution chain now also accepts
  "PatchBaseline-driven" when no explicit source (`-PatchUrls` /
  `-PatchDirectory` / `-ManifestPath`) is supplied AND
  `PatchBaseline.Patches` is non-empty (or `-AutoDetectLatestPatches`
  is set, in which case P03 will populate it).
- Phase registry: 11 entries (was 9). Action mappings updated to
  include P03 before P04 and P06 between P05 and P07.
- `Action GenerateManifest` now runs P01, P02, P03 (real Catalogue
  scrape that writes back to Config) instead of the r01 placeholder.

### Configuration

- `Config/Server201[6/9].json`, `Config/Server202[2/5].json` extended:
  - Added `PatchBaseline` node (Schema 1.0) with `TargetBuildAfterUpdate`,
    `PatchTuesdayOfBaseline`, `LastVerifiedDate`, `LastVerifiedBy`,
    `VerificationMethod`, `VerifiedOsLanguages`, `ChecksumAlgorithm`,
    `Patches`, `ExcludeKbList`, and `WsusScnCab`.
  - Added `AutoRefreshPolicy` node with `Mode`, `WritebackToConfig`,
    `FallbackOnScrapeFailure`, `ScrapeRetries`.
  - `AutoDetectKnownGood` marked deprecated (kept for r01 compatibility).
  - Server 2025 `ExcludeKbList` populated with KB5043080 (Checkpoint
    Cumulative Update; not required for OS install).

### Quality

- **psa.py**: 0 errors / 0 warnings / 0 info on the
  combined 5,447-line script (was 4,093 lines in r01).
- All r02 helpers have `[OutputType()]` declarations.
- All `r02`-anchored revision tags removed from script body comments
  (PSAP0003 / PSAP0005 compliant — revision history is here in the
  CHANGELOG, not in source comments).
- New `$matches` auto-variable usage in the Catalogue scraper replaced
  with explicit `[regex]::Match(...).Groups[N].Value` to satisfy
  PSA2002 (SPEC §D.17).

### Compatibility

- r01-format `Config/<OsKey>.json` files load unchanged (the `PatchBaseline`
  node is optional from the loader's perspective; if absent at load
  time, P03 will create it on first scrape).
- All r01 command lines (`-Action`, `-IsoPath`, `-PatchDirectory`,
  `-ManifestPath`, `-SyntheticTestMode -DryRun`, etc.) continue to
  work identically.

### Known limitations

- The Catalogue scraper depends on the current HTML structure of
  catalog.update.microsoft.com. A Microsoft-side change will break
  the scraper; the `AutoRefreshPolicy.FallbackOnScrapeFailure`
  setting controls the recovery behaviour.
- `Invoke-WuaOfflineScan` scans the local Windows host's installed
  image against the offline catalog; it is NOT a true WIM-level
  scan (SPEC §D.18). The validator's findings remain a strong signal
  for dependency completeness in practice.
- M5 (monthly Stage 4 catalog-health workflow) is not yet implemented.
- M4 (Server 2025 MUM/CAB LCU expand) is still a placeholder.

## [update-wsi-2026.05.24-r01] - 2026-05-24

### Added — script

- Initial MVP (M1 milestone) of `Update-WindowsServerIso.ps1`.
- 4,093-line single-file PowerShell script. UTF-8 with BOM, CRLF
  line endings, ASCII-only source bytes.
- Nine-phase pipeline (P01..P13) driven by a registry of
  `pscustomobject` entries and dispatched by `Invoke-PhaseRunner`.
- Sandbox-by-default semantics; destructive operations require
  `-Execute`.
- Synthetic test mode (`-SyntheticTestMode`) for CI: builds a tiny
  non-bootable ISO without downloading any Microsoft asset.
- Hyper-V Gen2 boot smoke test (`-Action BootTest`).
- Four OS configuration profiles under `Config/`:
  `Server2016.json`, `Server2019.json`, `Server2022.json`,
  `Server2025.json`. Per-language entries for en-us and ja-jp.
- Three-layer patch integrity check (filename SHA-1, content SHA-256,
  Authenticode signature) in `Test-PatchIntegrity`.
- DISM mount lifecycle hardened with OSDBuilder-style cleanup and
  10 s + 30 s retry in `Invoke-WimMountSafe` /
  `Invoke-WimDismountSafe` (see SPEC §D.1).
- `0x800f081e` and `0x800f0a13` suppression as Warning per
  documented heuristics in `Add-WindowsPackageWithRetry`
  (SPEC §D.8, §D.9).
- Three-tier boot file fallback chain (`etfsboot.com`, `efisys.bin`)
  in `Resolve-EtfsbootCom` / `Resolve-EfisysBin` (SPEC §D.4).
- Debug Trace Facility with JSONL output on failure, reused verbatim
  from the companion in-house script
  [`Download-SpeakerDeck.ps1`](../download-speakerdeck-oracle4engineer/Download-SpeakerDeck.ps1).

### Added — configuration files

- `.psa.config.json` — psa.py project configuration. Enables all
  PSAP00xx opt-in rules. Lists every Microsoft in-box cmdlet used by
  this script in `psa2010_known_cmdlets` so that the undefined-call
  rule stays silent.
- `PSScriptAnalyzerSettings.psd1` — PSScriptAnalyzer settings.
  Excludes `PSAvoidUsingWriteHost` (operator-facing UX uses the
  Write-Step / Write-Ok wrappers), `PSUseShouldProcessForStateChangingFunctions`
  (script is invoked via `.\` not as a module), and
  `PSUseCmdletBinding` (top-level CmdletBinding already in place).

### Added — documentation

- `README.md` — English primary user documentation, including
  required `## ⚠️ Disclaimer` and `## License` sections.
- `README.ja.md` — Japanese mirror of `README.md`.
- `SPEC.md` — authoritative developer / LLM specification.
  Inherits Part A from the
  [Download-SpeakerDeck SPEC](../download-speakerdeck-oracle4engineer/SPEC.md);
  Part B contains this script's unique contract (workspace layout,
  output naming, OS profile schema, per-phase contracts,
  action→phase mapping, ISO filename patterns, integrity check,
  synthetic mode); Part C is the quality-gate checklist;
  Part D is the catalogue of known pitfalls.
- `CHANGELOG.md` — this file.

### Added — CI workflows (at repo root `.github/workflows/`)

- `scripts__powershell__update-windows-server-iso__stage1__linux.yml`
  — Stage 1, Linux: `psa.py` + PSScriptAnalyzer in pwsh 7, BOM /
  CRLF / ASCII guard, Config JSON parse check.
- `scripts__powershell__update-windows-server-iso__stage2__windows.yml`
  — Stage 2, Windows: PSScriptAnalyzer in PS 5.1, parse-only check,
  read-only smoke modes (`ListPhases`, `EnvironmentInfoOnly`,
  `-SyntheticTestMode -DryRun`).
- `scripts__powershell__update-windows-server-iso__stage3__synthetic.yml`
  — Stage 3, Windows: ADK install (cached), full
  `-SyntheticTestMode` pipeline with `-Execute`. **No ISO artifact is
  ever uploaded**; only logs and diag are persisted as 14-day
  artifacts.

### Quality

- **psa.py**: 0 errors, 0 warnings, 0 info on
  `Update-WindowsServerIso.ps1`.
- All 13 advanced helper functions declare `[OutputType()]`.
- All top-level `param()` variables are accessed via `$Script:`
  from nested functions (PSA2001 compliance).
- No `Split-Path -LiteralPath ... -Parent` (PowerShell 5.1 ja-JP
  AmbiguousParameterSet workaround applied via
  `[System.IO.Path]::GetDirectoryName`).
- No `$args` shadowing (renamed to `$dismArgs` in
  `Invoke-DismCleanup`).
- All inline `# psa-disable-line` annotations carry an explicit
  justification.

### Compatibility

- Windows PowerShell 5.1: required base.
- PowerShell 7.x: also supported.
- Server 2016 / 2019 / 2022 / 2025: all supported.
- en-us and ja-jp ISOs: all supported.

### Known limitations

- `-AutoDetectLatestPatches` is a placeholder; populate Config
  `AutoDetectKnownGood` manually for now. Real implementation lands
  in M2.
- Server 2025 `LCUExpandViaMum=true` is configured but the actual
  expand-via-MUM code path is a future work item (M3).
- x86 and ARM64 are out of scope.
- BootTest requires a local Windows 11 host with Hyper-V; CI cannot
  exercise nested virtualisation.
- The Microsoft Update Catalogue scraper is local-only and not run
  in CI.
