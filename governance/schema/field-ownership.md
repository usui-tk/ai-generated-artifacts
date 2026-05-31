# Field-ownership map (governance data model)

> **Status:** governance record, authored P2.3 (SPINE-4). English-only (A-3).
> **Authority:** this map is the single authority that the P2 JSON Schemas
> (`manifest.schema.json`, `observation.schema.json`) are written against.
> **Grounding:** baseline §4.1 (three tiers), §4.4 (observation fields),
> §4.5 (hash policy), §4.7 (manifest schema), §4.8 (#13 marker frame, #16 schema versioning).

## Purpose

The governance data model has three tiers of source-of-truth. **Each attribute has
exactly one home**, and observations are *derived* (reproducible by re-scanning a
commit), not authored. This record fixes, for every attribute, its one home — so no
attribute is defined in two places — and is the contract the schemas encode.

## The three tiers

- **manifest** (per managed unit; curated; `governance/state/manifest.jsonl`):
  the unit's identity, canonical location, version, default policies, and the
  consumers list.
- **marker** (per inlined instance, in consumer code): the sync claim for that one
  instance — canonical-ref, synced version, synced hash, policy, binding, plus the
  DEP-3 fork fields when forked (§2.7).
- **observation** (scanner output; `governance/state/observations/...`): manifest
  unit-attrs ⋈ marker instance-attrs ⋈ computed hashes ⋈ drift ⋈ run provenance,
  emitted per scan.

## Attribute → home

| Attribute | Home | Notes |
|---|---|---|
| `unit_id` (PK) | **manifest** | markers and observations *reference* it; never redefine it |
| `kind` | **manifest** | language-agnostic unit type (§4.4) |
| `canonical_location` | **manifest** | repo-relative path to the canonical source |
| `canonical_version` (default) | **manifest** | version/tag the canonical carries |
| default `change_policy`, `binding_mode` | **manifest** | unit-level defaults (§2.4) |
| **`consumers[]`** | **manifest only** | the single source of truth; markers/observations reference `unit_id` and **never re-list consumers** |
| `version` (synced), `hash` (synced norm), `policy`, `binding` | **marker** | per inlined instance, in consumer code |
| DEP-3 fork fields (`forwarded`, `applied_upstream`, `change_reason`, `reason_class`) | **marker** | only on `forked` instances (§2.7) |
| `region_locator` | **observation** | provenance for a region (marker id / span) |
| `canonical_hash_norm`, `observed_hash_norm`, `observed_hash_raw`, `hash_what` | **observation** | computed each scan (§4.5); raw hash is forensic-only |
| `drift` | **observation** | derived fast-filter state |
| run provenance (`run_id`, `observed_at`, `runtime`, `repo`, `commit`) | **observation** | per scan run |
| `granularity`, `consumer`, `path` | **observation** | the scanned instance's context (§4.4) |
| `schema_version` | **manifest and observation (each)** | symmetric, per-tier; lets each evolve independently (§4.8 #16) |
| `ext` | **observation** (and curated `ext` allowed on manifest) | open extension; keeps ad-hoc fields out of the top-level namespace |

### One-home rules (load-bearing)

1. An attribute is **never** defined in two tiers. Where a value appears in more than
   one tier (e.g. `canonical_version`), the **manifest** holds the curated truth and
   the marker/observation hold a *claim* or a *computed* value compared against it.
2. The **consumers list lives only in the manifest.** Markers and observations
   reference a unit by `unit_id`.
3. **Computed** values (hashes, `drift`) live only in **observation** — they are
   derived by the scanner and reproducible, never authored.

## Marker final form (fixed at P2.3, on the §4.8 #13 frame)

Language-agnostic comment sentinel; comment prefix is `#` (PowerShell and Bash).

```
# >>> CANONICAL unit_id=<id> version=<ver> hash=<norm-hash> policy=<policy> binding=<binding> >>>
...inlined region body...
# <<< CANONICAL unit_id=<id> <<<
```

- **Key order (BEGIN line):** `unit_id`, `version`, `hash`, `policy`, `binding`.
  END line carries `unit_id` only.
- **Delimiters:** single space between pairs; `key=value` with no spaces around `=`;
  values are **unquoted**.
- **Value charset:** `^[A-Za-z0-9._-]+$` (no whitespace, no quotes) — so a line parses
  by splitting on whitespace then on `=`, with no escaping.
- **Enums:** `policy` is one of `canonical` / `vendored-upstream-first` / `forked`;
  `binding` is one of `follow-latest` / `pin`.
- The trailing `>>>` / `<<<` are visual closers; parsers key off the leading sentinel.
