"""
canonical_json - Repository-canonical JSON serialization (Python reference)

This module implements the JSON serialization format declared as normative
in this subproject's SPEC.md Part B.23 "JSON Canonical Serialization".
The format is designed so that the byte sequence emitted by this Python
module matches the byte sequence emitted by the PowerShell helper
``ConvertTo-CanonicalJson`` / ``Save-CanonicalJsonFile`` in
``Update-WindowsServerIso.ps1`` for the same logical input.

The byte-level match makes the data/*.json and tests/fixtures/*.json
files in this subproject editable from either runtime (Linux Python 3.x,
Linux PowerShell 7.x) without producing spurious git diffs.

Canonical format (SPEC Part B.23 §B.23.1):
    1. Encoding         : UTF-8 (no BOM)
    2. Line endings     : LF
    3. Indentation      : 2 spaces (no tabs)
    4. Key-value sep    : ": " (colon + 1 space)
    5. Array item sep   : ",\\n<indent>"
    6. Non-ASCII chars  : literal (NO \\uXXXX escape)
    7. Key order        : preserve insertion order (no sort)
    8. Trailing newline : exactly 1 LF at end of output
    9. Null values      : emitted as "key": null
   10. Max depth        : caller-controlled (parameter ``depth``)

Tested for byte-level equality with the PowerShell reference implementation
through ``tests/canonical_json_test.py`` (T11).
"""
from __future__ import annotations

import json
import os
from typing import Any


# Default indent width; mirrors the PowerShell ConvertTo-CanonicalJson
# -IndentWidth default. Changing this is a normative format change and
# requires a SPEC.md Part B.23 amendment in lock-step.
DEFAULT_INDENT_WIDTH = 2

# Default maximum nesting depth; mirrors the PowerShell -Depth default.
# 20 is well above the deepest known schema in data/*.json (currently 6).
DEFAULT_DEPTH = 20


def canonical_json_dumps(
    obj: Any,
    depth: int = DEFAULT_DEPTH,
    indent_width: int = DEFAULT_INDENT_WIDTH,
    trailing_newline: bool = True,
) -> str:
    """Serialize ``obj`` to a string in the repository-canonical JSON format.

    The returned string matches the bytes that
    ``ConvertTo-CanonicalJson -InputObject $obj -Depth <depth>`` produces in
    the PowerShell helper for the same logical input.

    Parameters
    ----------
    obj : Any
        Python object to serialize. dict, list, str, int, float, bool, None.
        dict insertion order is preserved (Python 3.7+ guarantee).
    depth : int, optional
        Maximum allowed nesting depth (default ``DEFAULT_DEPTH``). Values that
        would nest deeper raise ``ValueError`` to match the PowerShell
        ``-Depth`` over-limit behaviour.
    indent_width : int, optional
        Number of space characters per indentation level (default
        ``DEFAULT_INDENT_WIDTH``).
    trailing_newline : bool, optional
        If True (default), the returned string ends with exactly one LF.
        If False, no trailing newline is appended.

    Returns
    -------
    str
        JSON text in canonical format.

    Raises
    ------
    ValueError
        If the input nests deeper than ``depth`` allows.
    TypeError
        If the input contains a value that is not JSON-serialisable.
    """
    if depth < 1:
        raise ValueError(f"depth must be >= 1, got {depth}")
    if indent_width < 1:
        raise ValueError(f"indent_width must be >= 1, got {indent_width}")

    # Enforce depth limit before json.dumps to give a precise error message
    # matching the PowerShell side. json.dumps itself does not enforce one.
    _assert_depth(obj, depth)

    # json.dumps with these flags produces:
    #   - indent=indent_width  : 2-space (or N-space) indent + newlines
    #   - ensure_ascii=False   : literal UTF-8 (no \uXXXX escapes)
    #   - separators=(',', ': '): comma+newline+indent separator (since indent
    #                            is set, json uses comma+newline), and
    #                            ": " (colon+1 space) for key/value
    #   - sort_keys=False (default): preserve dict insertion order
    body = json.dumps(
        obj,
        indent=indent_width,
        ensure_ascii=False,
        separators=(",", ": "),
    )

    if trailing_newline:
        body += "\n"
    return body


def save_canonical_json_file(
    obj: Any,
    path: str | os.PathLike,
    depth: int = DEFAULT_DEPTH,
    indent_width: int = DEFAULT_INDENT_WIDTH,
) -> None:
    """Write ``obj`` to ``path`` as a canonical JSON file.

    Output guarantees (SPEC Part B.23 §B.23.2):
        - UTF-8 encoded, no BOM
        - LF line endings (no CRLF, even on Windows)
        - Exactly one trailing LF
        - Atomic-ish write: writes to ``<path>.tmp`` then renames over ``<path>``

    The byte sequence on disk matches what
    ``Save-CanonicalJsonFile -InputObject $obj -Path <path>`` produces in
    the PowerShell helper for the same logical input.

    Parameters
    ----------
    obj : Any
        Object to serialize.
    path : str | PathLike
        Destination file path.
    depth : int, optional
        See ``canonical_json_dumps``.
    indent_width : int, optional
        See ``canonical_json_dumps``.
    """
    text = canonical_json_dumps(
        obj,
        depth=depth,
        indent_width=indent_width,
        trailing_newline=True,
    )
    # Write raw bytes (no platform translation of newlines).
    tmp_path = f"{os.fspath(path)}.tmp"
    with open(tmp_path, "wb") as fh:
        fh.write(text.encode("utf-8"))
    os.replace(tmp_path, path)


def _assert_depth(obj: Any, max_depth: int, current: int = 0) -> None:
    """Raise ValueError if ``obj`` nests deeper than ``max_depth``.

    Counts depth the same way as PowerShell ConvertTo-Json -Depth: the
    top-level object is depth 0, its members are depth 1, etc. Strings,
    numbers, bools, and None do not increase depth.
    """
    if current > max_depth:
        raise ValueError(
            f"Object nests deeper than allowed depth ({max_depth}); "
            f"reached depth {current}."
        )
    if isinstance(obj, dict):
        for v in obj.values():
            _assert_depth(v, max_depth, current + 1)
    elif isinstance(obj, list):
        for v in obj:
            _assert_depth(v, max_depth, current + 1)
    # leaf types: no recursion needed
