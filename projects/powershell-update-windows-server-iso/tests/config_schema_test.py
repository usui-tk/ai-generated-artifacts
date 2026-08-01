#!/usr/bin/env python3
"""Config schema conformance test (SPEC B.4; declaration-based selection).

Validates every ``data/config-Server*.json`` against the machine-readable
schema that config **declares**: the top-level ``Schema`` field selects
``schema/config.schema.v4.json`` for ``"4.0"`` and the legacy
``schema/config.schema.json`` for ``"3.0"`` (an undeclared or unknown value
is a failure -- the declaration is the contract, r12.00 Schema 4.0). The
selected schema is the single source of truth that mirrors the SPEC B.4
prose; this test is what makes the contract enforceable in CI.

Why this exists
---------------
The P03 r10.3 defect (code assigned resolved patches to a non-schema
``PatchBaseline.Patches`` property while the schema mandates
``NeutralPatches``) slipped through because the only "spec" was free prose in
SPEC.md. A free-prose spec cannot catch that class of drift; a machine-checked
schema can. This test fails loudly if:

  * a config grows a property the schema does not declare (typos, drift,
    accidental legacy fields),
  * a config drops a required property,
  * a property has the wrong type, or
  * the forbidden legacy ``PatchBaseline.Patches`` field reappears.

Design constraints
------------------
This project's Python tooling is standard-library-only (the same rule psa.py
follows: "No external dependencies"). The ``jsonschema`` package is therefore
NOT available on CI runners, so this module ships a tiny subset validator
covering exactly the keywords used by the two committed schemas:
type, required, properties, additionalProperties, patternProperties, items,
enum, const, "not" (required-form, used to forbid the legacy Patches field),
$ref (local "#/definitions/..." and, for the 2020-12 v4 schema,
"#/$defs/..."), plus the five 2020-12-draft keywords the v4 schema uses:
$defs-anchored refs, oneOf, pattern, minItems, and minimum. It is
intentionally minimal -- a contract checker for the two known schemas, not a
general JSON Schema engine.

Relationship to the CI inline check
------------------------------------
The stage1 workflow has an inline "[Format] Validate Config JSON files" step
that checks presence of required keys (a positive check). This test is the
complementary negative/structural check: it rejects unknown properties and the
forbidden Patches field, which the inline check cannot see. The two are kept
deliberately separate so the fast inline gate still works without this file.
"""

import json
import pathlib
import re
import sys

PASS = "  PASS"
FAIL = "  FAIL"

TESTS_DIR = pathlib.Path(__file__).resolve().parent
SUBPROJECT_ROOT = TESTS_DIR.parent
DATA_DIR = SUBPROJECT_ROOT / "data"
SCHEMA_PATH_V3 = SUBPROJECT_ROOT / "schema" / "config.schema.json"
SCHEMA_PATH_V4 = SUBPROJECT_ROOT / "schema" / "config.schema.v4.json"

# Declaration-based selection (r12.00): the config's own top-level `Schema`
# field names the contract it claims to satisfy. Anything not in this map is
# an undeclared contract and fails loudly.
SCHEMA_BY_DECLARATION = {
    "3.0": SCHEMA_PATH_V3,
    "4.0": SCHEMA_PATH_V4,
}


def _type_ok(value, type_name):
    """Map a JSON Schema primitive type name to a Python isinstance check."""
    if type_name == "object":
        return isinstance(value, dict)
    if type_name == "array":
        return isinstance(value, list)
    if type_name == "string":
        return isinstance(value, str)
    if type_name == "integer":
        # bool is a subclass of int in Python; JSON integers are not booleans.
        return isinstance(value, int) and not isinstance(value, bool)
    if type_name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if type_name == "boolean":
        return isinstance(value, bool)
    if type_name == "null":
        return value is None
    return False


def _resolve_ref(ref, root_schema):
    """Resolve a local '#/definitions/Name' reference."""
    if not ref.startswith("#/"):
        raise ValueError(f"only local refs are supported, got {ref!r}")
    node = root_schema
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def _validate(value, schema, root_schema, path, errors):
    """Validate `value` against `schema`, appending dotted-path errors."""
    if "$ref" in schema:
        schema = _resolve_ref(schema["$ref"], root_schema)

    # type
    if "type" in schema:
        types = schema["type"]
        if isinstance(types, str):
            types = [types]
        if not any(_type_ok(value, t) for t in types):
            errors.append(f"{path}: expected type {schema['type']}, got {type(value).__name__}")
            return  # further checks assume the type matched

    # const
    if "const" in schema and value != schema["const"]:
        errors.append(f"{path}: expected const {schema['const']!r}, got {value!r}")

    # enum
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: value {value!r} not in enum {schema['enum']}")

    # oneOf (2020-12; v4 schema) -- exactly one branch must validate
    if "oneOf" in schema:
        matches = 0
        for branch in schema["oneOf"]:
            branch_errors = []
            _validate(value, branch, root_schema, path, branch_errors)
            if not branch_errors:
                matches += 1
        if matches != 1:
            errors.append(f"{path}: oneOf matched {matches} branches (exactly 1 required)")

    # pattern (2020-12; v4 schema) -- string regex constraint
    if "pattern" in schema and isinstance(value, str):
        if re.search(schema["pattern"], value) is None:
            errors.append(f"{path}: value {value!r} does not match pattern {schema['pattern']!r}")

    # minimum (2020-12; v4 schema) -- numeric lower bound
    if "minimum" in schema and isinstance(value, (int, float)) and not isinstance(value, bool):
        if value < schema["minimum"]:
            errors.append(f"{path}: value {value!r} below minimum {schema['minimum']!r}")

    # minItems (2020-12; v4 schema) -- array length lower bound
    if "minItems" in schema and isinstance(value, list):
        if len(value) < schema["minItems"]:
            errors.append(f"{path}: array has {len(value)} items, minItems is {schema['minItems']}")

    # object
    if isinstance(value, dict):
        props = schema.get("properties", {})
        pattern_props = schema.get("patternProperties", {})
        additional = schema.get("additionalProperties", True)

        for req in schema.get("required", []):
            if req not in value:
                errors.append(f"{path}: missing required property '{req}'")

        # "not": {"required": [...]} -- forbid named properties (Patches guard)
        not_schema = schema.get("not")
        if isinstance(not_schema, dict) and "required" in not_schema:
            forbidden = [p for p in not_schema["required"] if p in value]
            if forbidden:
                errors.append(
                    f"{path}: forbidden propert{'y' if len(forbidden) == 1 else 'ies'} "
                    f"present: {forbidden} (schema 'not.required')"
                )

        compiled_patterns = [(re.compile(p), s) for p, s in pattern_props.items()]
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else key
            if key in props:
                _validate(child, props[key], root_schema, child_path, errors)
                continue
            matched = False
            for rx, subschema in compiled_patterns:
                if rx.search(key):
                    matched = True
                    if isinstance(subschema, dict) and subschema:
                        _validate(child, subschema, root_schema, child_path, errors)
                    break
            if matched:
                continue
            if additional is False:
                errors.append(f"{child_path}: additional property not allowed by schema")
            elif isinstance(additional, dict):
                _validate(child, additional, root_schema, child_path, errors)

    # array
    if isinstance(value, list) and "items" in schema:
        item_schema = schema["items"]
        for i, item in enumerate(value):
            _validate(item, item_schema, root_schema, f"{path}[{i}]", errors)


def validate_instance(instance, schema):
    """Return a list of human-readable validation errors ([] == valid)."""
    errors = []
    _validate(instance, schema, schema, "", errors)
    return errors


def main():
    passed = 0
    failed = 0

    print("=" * 72)
    print("Config schema conformance (SPEC B.4 / declaration-based selection)")
    print("=" * 72)

    # Load both committed schemas; each config then selects its own by
    # declaration. A missing or unparsable schema is a hard failure.
    schemas = {}
    for spath in (SCHEMA_PATH_V3, SCHEMA_PATH_V4):
        if not spath.exists():
            print(f"{FAIL}  schema file not found: {spath}")
            print("\n  Summary: 0 passed, 1 failed, 1 total")
            return 1
        try:
            schemas[spath] = json.loads(spath.read_text(encoding="utf-8"))
            print(f"{PASS}  schema loaded: {spath.name}")
            passed += 1
        except (OSError, ValueError) as exc:
            print(f"{FAIL}  schema failed to parse ({spath.name}): {exc}")
            print("\n  Summary: 0 passed, 1 failed, 1 total")
            return 1

    # Self-test the mini-validator so a broken validator cannot mask config
    # errors by silently passing everything.
    selftest_schema = {
        "type": "object",
        "required": ["a"],
        "properties": {"a": {"type": "string"}},
        "additionalProperties": False,
        "not": {"required": ["legacy"]},
    }
    must_pass = {"a": "ok"}
    must_fail_missing = {}                       # missing required 'a'
    must_fail_extra = {"a": "ok", "b": 1}        # additional prop
    must_fail_type = {"a": 123}                  # wrong type
    must_fail_forbidden = {"a": "ok", "legacy": 1}  # forbidden prop
    st2020 = {
        "type": "object",
        "properties": {
            "kind": {"oneOf": [{"const": "a"}, {"const": "b"}]},
            "kb": {"type": "string", "pattern": "^KB[0-9]+$"},
            "order": {"type": "integer", "minimum": 1},
            "items_": {"type": "array", "minItems": 1,
                       "items": {"$ref": "#/$defs/Leaf"}},
        },
        "$defs": {"Leaf": {"type": "string"}},
    }
    checks = [
        ("validator accepts a valid object", validate_instance(must_pass, selftest_schema) == []),
        ("validator rejects missing required", len(validate_instance(must_fail_missing, selftest_schema)) > 0),
        ("validator rejects additional property", len(validate_instance(must_fail_extra, selftest_schema)) > 0),
        ("validator rejects wrong type", len(validate_instance(must_fail_type, selftest_schema)) > 0),
        ("validator rejects forbidden 'not.required'", len(validate_instance(must_fail_forbidden, selftest_schema)) > 0),
        # 2020-12 keyword coverage (v4 schema): $defs ref, oneOf, pattern,
        # minItems, minimum -- each exercised in both directions.
        ("2020-12: valid instance passes all five keywords",
         validate_instance({"kind": "a", "kb": "KB5043080", "order": 1,
                            "items_": ["x"]}, st2020) == []),
        ("2020-12: oneOf rejects a non-matching value",
         len(validate_instance({"kind": "c"}, st2020)) > 0),
        ("2020-12: pattern rejects a malformed KB id",
         len(validate_instance({"kb": "5043080"}, st2020)) > 0),
        ("2020-12: minimum rejects a below-floor integer",
         len(validate_instance({"order": 0}, st2020)) > 0),
        ("2020-12: minItems + $defs ref reject an empty/typed-wrong array",
         len(validate_instance({"items_": []}, st2020)) > 0
         and len(validate_instance({"items_": [1]}, st2020)) > 0),
    ]
    for name, ok in checks:
        if ok:
            print(f"{PASS}  self-test: {name}")
            passed += 1
        else:
            print(f"{FAIL}  self-test: {name}")
            failed += 1

    # Validate every OS config.
    required_files = [
        "config-Server2016.json",
        "config-Server2019.json",
        "config-Server2022.json",
        "config-Server2025.json",
    ]
    for fname in required_files:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            print(f"{FAIL}  {fname}: not found under data/")
            failed += 1
            continue
        try:
            instance = json.loads(fpath.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            print(f"{FAIL}  {fname}: parse error: {exc}")
            failed += 1
            continue
        declared = instance.get("Schema")
        spath = SCHEMA_BY_DECLARATION.get(declared)
        if spath is None:
            print(f"{FAIL}  {fname}: undeclared/unknown Schema value {declared!r} "
                  f"(known: {sorted(SCHEMA_BY_DECLARATION)})")
            failed += 1
            continue
        errs = validate_instance(instance, schemas[spath])
        if not errs:
            print(f"{PASS}  {fname}: declares Schema {declared} and conforms to {spath.name}")
            passed += 1
        else:
            print(f"{FAIL}  {fname}: {len(errs)} violation(s) against declared {spath.name}:")
            for e in errs[:20]:
                print(f"           - {e}")
            failed += 1

    # Targeted regression guard for the r10.3 defect: the legacy 'Patches'
    # field must not exist in any committed config.
    for fname in required_files:
        fpath = DATA_DIR / fname
        if not fpath.exists():
            continue
        instance = json.loads(fpath.read_text(encoding="utf-8"))
        pb = instance.get("PatchBaseline", {})
        if isinstance(pb, dict) and "Patches" in pb:
            print(f"{FAIL}  {fname}: legacy PatchBaseline.Patches present (must be NeutralPatches)")
            failed += 1
        else:
            print(f"{PASS}  {fname}: no legacy PatchBaseline.Patches (r10.3 regression guard)")
            passed += 1

    print()
    total = passed + failed
    print(f"  Summary: {passed} passed, {failed} failed, {total} total")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
