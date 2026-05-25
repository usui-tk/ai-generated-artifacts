#!/usr/bin/env python3
"""T3: PowerShell function unit tests driven from Python.

Uses the ``-Action TestHarness`` REPL exposed by
``Update-WindowsServerIso.ps1`` to invoke PowerShell functions with
JSON-encoded arguments and JSON-encoded results. This lets us write
function-level assertions in Python instead of in a pwsh wrapper
script - which is faster to iterate on, and produces clearer failure
messages than ``throw``.

What this tool covers that fixture tests (T2) do NOT:

- ``Get-CatalogQueryTemplate``        the per-OS query/token tables
- ``Get-LanguagePackQueryTemplate``   the language-pack token tables
- ``Get-KbIdFromUpdateTitle``         the regex used during dedup
- ``Select-AllCanonicalPatchFiles``   multi-file picker for umbrella KBs
- ``Select-CanonicalPatchFile``       single-file picker
- ``Test-IsCombinedLcuTitle``         combined-LCU detection

Adding a new test = add one function below; each calls
``ps.invoke('<FunctionName>', **kwargs)`` and asserts on the return.

Exit codes:
    0   all assertions passed
    1   at least one assertion failed
    2   could not start the TestHarness session
"""
from __future__ import annotations

import argparse
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from common.ps_invoke import PSSession, PSHarnessError  # noqa: E402

_SCRIPT_PATH = _HERE.parent / 'Update-WindowsServerIso.ps1'


@dataclass
class TestOutcome:
    name: str
    ok: bool
    detail: str

    def __repr__(self) -> str:
        glyph = 'PASS' if self.ok else 'FAIL'
        return f'  {glyph}  {self.name}: {self.detail}'


# -----------------
# Test cases
# -----------------

def test_query_template_server2022_has_both_comma_forms(ps: PSSession) -> TestOutcome:
    """Bug 2 regression: Server2022 TitleTokens must contain BOTH forms."""
    name = 'Get-CatalogQueryTemplate Server2022 dual TitleTokens'
    t = ps.invoke('Get-CatalogQueryTemplate', OsVersion='Server2022', PatchMonth='2026-05')
    tokens = t.get('TitleTokens', [])
    expected = {
        'Microsoft server operating system version 21H2',
        'Microsoft server operating system, version 21H2',
    }
    got = set(tokens) if isinstance(tokens, list) else {tokens}
    if expected.issubset(got):
        return TestOutcome(name, True, f'{len(got)} token(s), both forms present')
    return TestOutcome(name, False,
                       f'TitleTokens={tokens!r}, expected both comma forms')


def test_query_template_each_os_has_required_types(ps: PSSession) -> TestOutcome:
    """Every OS template must define SSU, LCU, and DotNet at minimum."""
    name = 'Get-CatalogQueryTemplate per-OS Type coverage'
    missing: List[str] = []
    for os_key in ('Server2016', 'Server2019', 'Server2022', 'Server2025'):
        t = ps.invoke('Get-CatalogQueryTemplate', OsVersion=os_key, PatchMonth='2026-05')
        types = {q.get('Type') for q in t.get('Queries', [])}
        for required in ('SSU', 'LCU', 'DotNet'):
            if required not in types:
                missing.append(f'{os_key}/{required}')
    if not missing:
        return TestOutcome(name, True, 'all 4 OSes define SSU+LCU+DotNet')
    return TestOutcome(name, False, f'missing: {missing}')


def test_query_template_server2022_no_comma_in_query_template(ps: PSSession) -> TestOutcome:
    """The actual Search.aspx query strings must use the live (comma-less) form."""
    name = 'Get-CatalogQueryTemplate Server2022 QueryTemplate has no comma'
    t = ps.invoke('Get-CatalogQueryTemplate', OsVersion='Server2022', PatchMonth='2026-05')
    bad: List[str] = []
    for q in t.get('Queries', []):
        qt = q.get('QueryTemplate', '')
        if 'operating system,' in qt:  # the comma form
            bad.append(f'{q.get("Type")}: {qt}')
    if not bad:
        return TestOutcome(name, True, 'all 5 queries use the comma-less form')
    return TestOutcome(name, False, f'{len(bad)} query/queries still have comma: {bad[0]!r}')


def test_get_kb_id_extraction(ps: PSSession) -> TestOutcome:
    """Get-KbIdFromUpdateTitle should match (KB######) and skip non-matches."""
    name = 'Get-KbIdFromUpdateTitle'
    cases = [
        ('2026-05 Cumulative Update (KB5037591)',                   'KB5037591'),
        ('SSU for ... (KB5043050)',                                 'KB5043050'),
        ('Something without a kb reference',                         ''),
        ('', ''),
    ]
    failures: List[str] = []
    for title, want in cases:
        got = ps.invoke('Get-KbIdFromUpdateTitle', Title=title)
        if got != want:
            failures.append(f'{title!r} -> got {got!r}, want {want!r}')
    if not failures:
        return TestOutcome(name, True, f'{len(cases)} cases passed')
    return TestOutcome(name, False, '; '.join(failures))


def test_select_all_canonical_patch_files_returns_array(ps: PSSession) -> TestOutcome:
    """Select-AllCanonicalPatchFiles given 2 viable links should return both."""
    name = 'Select-AllCanonicalPatchFiles dual-link case (bug 3 regression)'
    links = [
        {'Url': 'https://example.com/a/windows10.0-kb5087066-x64-ndp48_xxxx.msu',
         'FileName': 'windows10.0-kb5087066-x64-ndp48_xxxx.msu'},
        {'Url': 'https://example.com/a/windows10.0-kb5087061-x64_yyyy.msu',
         'FileName': 'windows10.0-kb5087061-x64_yyyy.msu'},
    ]
    got = ps.invoke('Select-AllCanonicalPatchFiles', Links=links, PatchType='DotNet', Architecture='x64')
    # PS may return a single object if 1 result, or array if multiple.
    if isinstance(got, dict):
        got_list = [got]
    elif isinstance(got, list):
        got_list = got
    else:
        return TestOutcome(name, False, f'unexpected return type: {type(got).__name__}')
    if len(got_list) == 2:
        return TestOutcome(name, True, '2 links returned (both .NET runtimes preserved)')
    return TestOutcome(name, False,
                       f'returned {len(got_list)} link(s), expected 2 (got: {got_list!r})')


def test_select_canonical_patch_file_filters_express(ps: PSSession) -> TestOutcome:
    """Single-file picker must reject Express / Delta packages."""
    name = 'Select-CanonicalPatchFile rejects Express'
    links = [
        {'Url': 'https://example.com/a/foo-express.cab', 'FileName': 'foo-express.cab'},
        {'Url': 'https://example.com/a/foo.msu', 'FileName': 'foo.msu'},
    ]
    got = ps.invoke('Select-CanonicalPatchFile', Links=links, PatchType='LCU', Architecture='x64')
    if got is None:
        return TestOutcome(name, False, 'returned $null - canonical file rejected too aggressively?')
    if got.get('FileName') == 'foo.msu':
        return TestOutcome(name, True, 'picked foo.msu over foo-express.cab')
    return TestOutcome(name, False, f'picked {got.get("FileName")!r}, expected foo.msu')


def test_test_is_combined_lcu_title(ps: PSSession) -> TestOutcome:
    """Test-IsCombinedLcuTitle must recognise the combined marker."""
    name = 'Test-IsCombinedLcuTitle'
    cases = [
        ('2026-05 Cumulative Update (servicing stack) for Server 2019 ...', True),
        ('2026-05 Combined Cumulative Update for Server 2025 ...',          True),
        ('2026-05 Cumulative Update for Windows Server 2016 ...',           False),
    ]
    failures: List[str] = []
    for title, want in cases:
        got = ps.invoke('Test-IsCombinedLcuTitle', LcuTitle=title)
        if bool(got) != want:
            failures.append(f'{title[:50]!r} -> got {got!r}, want {want!r}')
    if not failures:
        return TestOutcome(name, True, f'{len(cases)} cases passed')
    return TestOutcome(name, False, '; '.join(failures))


# -----------------
# Orchestrator
# -----------------

ALL_TESTS: List[Callable[[PSSession], TestOutcome]] = [
    test_query_template_server2022_has_both_comma_forms,
    test_query_template_server2022_no_comma_in_query_template,
    test_query_template_each_os_has_required_types,
    test_get_kb_id_extraction,
    test_select_all_canonical_patch_files_returns_array,
    test_select_canonical_patch_file_filters_express,
    test_test_is_combined_lcu_title,
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else 'PS function harness')
    parser.add_argument('--script', default=str(_SCRIPT_PATH),
                        help='Path to Update-WindowsServerIso.ps1 (default: parent dir)')
    args = parser.parse_args()

    print(f'== T3 PowerShell Function Harness ==')
    print(f'   script: {args.script}')

    try:
        ps = PSSession(args.script)
        ps.start()
    except PSHarnessError as exc:
        print(f'\nERROR: could not start TestHarness session: {exc}')
        return 2

    results: List[TestOutcome] = []
    try:
        for case in ALL_TESTS:
            try:
                results.append(case(ps))
            except PSHarnessError as exc:
                results.append(TestOutcome(case.__name__, False, f'PSHarnessError: {exc}'))
            except Exception as exc:  # pylint: disable=broad-except
                tb = traceback.format_exc(limit=2)
                results.append(TestOutcome(case.__name__, False, f'unexpected: {exc} | {tb!r}'))
    finally:
        ps.close()

    for r in results:
        print(r)

    failed = [r for r in results if not r.ok]
    print()
    print(f'  Summary: {len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} total')
    return 0 if not failed else 1


if __name__ == '__main__':
    sys.exit(main())
