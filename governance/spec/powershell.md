<!-- AI read-contract: this is the Layer-2 COMMON spec home for the PowerShell family -
     the canonical source of SPEC "Part A" common conventions that consumer SPECs VENDOR
     (managed-region copy, ADR 0019) rather than restate. Each region is delimited by an
     ADR 0015 canonical marker (Markdown comment leader). Regions conform to the Layer-1
     item canon (governance/doc-format/doc-format.jsonl; the spec.part-a.* items with
     content_model=vendored) and are registered as kind=spec-region rows in the manifest.
     SCOPE: common convention text ONLY - consumer-specific values are tokenised ({{...}})
     or deferred to the consumer's own SPEC (Part B / project sections). This file does NOT
     restate README content (the readme.* items own that) or tool-owned config (master in
     the owning tool canon, ADR 0009).
     HASH STATUS: marker hash= is PENDING. The doc-region normalized-hash contract and the
     stamp/verify path are owned by the document-conformance gate (TF (e), a SEPARATE tool);
     the governance-state validator does NOT check these markers (its D/G gates are scoped to
     kind=powershell-helper / reference-code by design). PENDING is replaced with a stamped
     hash when the doc-conformance gate lands, before any consumer vendors from this home. -->

# PowerShell family - common specification (Part A) - canonical source

This is the **Layer-2 common** home for the PowerShell scripting family. Consumer SPECs
inherit "Part A" by **vendoring** the regions below (ADR 0019); they do not hand-restate them
(AGENTS.md §6). The phase *count/map*, parameter *list*, and other per-consumer specifics live
in each consumer's **Part B** / project sections, not here. Version: see
`governance/doc-format/VERSION` (Layer-1 format) and this home's region markers (`version=`).

## Part A - common conventions

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.reference-assets version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.1 Reference assets

Every PowerShell script in the canon draws on a shared set of reference assets: (1) the
static-analysis configuration and gate (see A.11); (2) the companion specification documents
that make up the doc-set (README + README.ja, SPEC, and where applicable TESTING and
CHANGELOG); (3) the in-house canonical reference script `{{REFERENCE_SCRIPT}}`, the worked
example of these conventions; and (4) the shared helper units vendored from the code canon
(`reference-code/powershell/`). The specific reference script and helper set a consumer uses
are recorded in that consumer's own SPEC; this region only fixes that the assets exist and
where their conventions are defined.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.reference-assets <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.source-file-format version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.2 Source file format

Script source files are encoded **UTF-8 with BOM** and use **CRLF** line endings. Non-ASCII
characters are confined to intentional data/string literals; identifiers, keywords, and code
are ASCII (the documentation-language policy is A.12). Encoding and line-ending conformance is
enforced by the static-analysis gate (A.11); files that are not BOM+CRLF, or that carry stray
non-ASCII outside sanctioned literals, fail the gate.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.source-file-format <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.banner-version version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.3 Banner and version

Each script carries a single canonical **version string** and emits a **startup banner** that
prints the script identity, the version, and a **SHA256 self-fingerprint** of the running
file. The version string is the one source of truth for the script's revision and is the value
recorded in CHANGELOG. The banner format and the fingerprint computation are common; the
concrete version value is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.banner-version <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.phase-architecture version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.4 Phase architecture

Scripts are organised into **numbered phases**. The numbering convention (monotonic integer
phases, optional phase *groups*, and a uniform per-phase header/footer log line carrying the
phase number, title, and elapsed tag) is common. The **phase count and the phase map**
(which work each phase does) are consumer-specific and are defined in the consumer's **Part
B**, not here.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.phase-architecture <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.logging version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.5 Logging conventions

Logging goes through the shared logging helper family (vendored from the code canon). Messages
carry a **severity marker** from the canonical set (informational / detail / caution / error
and the phase markers); console output uses the canonical colour discipline for each severity;
network operations use TLS. Scripts do not write ad-hoc colour or bypass the helpers. The
helper set is fixed by the code canon; this region fixes the *conventions* for using it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.logging <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.path-handling version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.6 Path handling

Paths are handled defensively: prefer **`-LiteralPath`** over wildcard-expanding parameters;
never expand wildcards on externally supplied input; build paths with validated joins (not
string concatenation); and confine scratch files to a controlled work root rather than the
current directory or a shared temp location. These rules are common; the specific work-root
location is per-consumer.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.path-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.parameter-handling version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.7 Parameter conventions

Scripts expose the canonical **standard parameter set** (the shared switches every consumer
provides) plus consumer-specific parameters. Mutually exclusive options are validated at
entry; invalid combinations fail fast with a diagnostic. Help/usage shows the startup banner.
The standard switch set and the validation discipline are common; the consumer-specific
parameter list is defined in the consumer's SPEC.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.parameter-handling <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.error-diagnostic version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.8 Error and diagnostic model

Diagnostics are **three-layered**: (1) human-readable console output; (2) a per-run detail log
file; (3) structured per-failure records. Failures are **classified** (e.g. transient vs
fatal vs configuration) so callers can react. Each failure is recorded as a structured entry
following the canonical record shape (A.9 JSONL conventions). If a consumer additionally
provides an **operation-level trace facility** (an optional feature - see the consumer's Part
A.14 / project section), the per-failure records and the operation-level trace coexist; this
region does not require such a facility.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.error-diagnostic <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.csv-conventions version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.9 CSV conventions

Tabular outputs and state files share common **column-naming** and **file-naming** conventions:
stable snake/Pascal column names, a per-phase output-file naming scheme, and a designated state
file for resumable runs. CSV is the baseline tabular format every consumer supports.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.csv-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.9 (cont.) JSONL conventions - optional feature

A consumer **may** additionally emit JSONL (one JSON object per line) for machine consumption -
notably the per-failure records of A.8. When present, JSONL files follow the canonical naming
(per-phase, purpose-suffixed), use **camelCase** keys, and are LF-terminated. This region is an
**optional feature**: a consumer that emits only CSV omits it.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.jsonl-conventions <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.environment-eval version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.10 Environment evaluation

The **environment-evaluation phase (the first phase of the run)** assesses the host before any
work: it gathers platform/runtime facts in tiers (a baseline probe, then progressively
deeper checks) and **asserts compatibility** (runtime version, privileges, required tooling),
failing fast with a clear diagnostic when a prerequisite is unmet. The tiered model and the
fail-fast compatibility assertion are common; the specific phase number/name and the exact
checks are consumer-specific (Part B).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.environment-eval <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.static-analysis version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.11 Static analysis

`psa.py` (the canon's PowerShell static analyzer; canonical home in the tool canon) is the
**mandatory static-analysis gate**. Every consumer runs it with a project-local
`.psa.config.json` and MUST be **clean (0 errors / 0 warnings / 0 info)** before each commit.
The `.psa.config.json` **follows-latest** from the analyzer's canonical home (ADR 0009); it is
tool-owned, not part of this doc canon. Which rules a consumer suppresses (with justification)
and any project-specific false-positive dispositions are recorded in the consumer's own SPEC,
not here. CI runs a **three-stage model**: Stage 1 - lint / static analysis (psa.py +
PSScriptAnalyzer), cross-platform; Stage 2 - functional / parse validation (Windows where
required); Stage 3 - release / packaging. The three-stage model is common; the concrete
workflow filenames are path-encoded per consumer (A.13 / the dotfile conventions).
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.static-analysis <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.doc-language-policy version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.12 Documentation language policy

Code, configuration, and the SPEC/TESTING/CHANGELOG doc-set are authored in **English / ASCII**.
Intentional Japanese appears only in the **bilingual README pair** (`README.ja.md`) and in
sanctioned data/string literals. The doc-set file-set and each document's role follow the
canonical structure (README + README.ja, SPEC, and where applicable TESTING and CHANGELOG):
**history lives in CHANGELOG, current/forward design in SPEC**. `README.md` and `README.ja.md`
are maintained in **lock-step** (AGENTS.md §5). The mandatory README disclaimer and license
sections are defined by the canonical README format (the `readme.disclaimer` / `readme.license`
items) and are **not restated here**.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.doc-language-policy <<< -->

<!-- >>> CANONICAL unit_id=spec.powershell.part-a.development-workflow version=0.1.0 hash=PENDING policy=canonical binding=follow-latest >>> -->
### A.13 Development workflow

Changes follow an **iterate-to-green** cycle: edit; run the static-analysis gate (A.11) to
**0/0/0**; run the consumer's verification/tests where present; then commit. Revision history
is recorded in **CHANGELOG** (Keep a Changelog format); the SPEC records the current design,
not a change log. Doc-touching changes keep the doc-set in sync (AGENTS.md §5): a SPEC change
that alters behaviour updates README / README.ja / TESTING in the same change. CI workflow
files are named with a per-consumer path-encoded prefix.
<!-- <<< CANONICAL unit_id=spec.powershell.part-a.development-workflow <<< -->
