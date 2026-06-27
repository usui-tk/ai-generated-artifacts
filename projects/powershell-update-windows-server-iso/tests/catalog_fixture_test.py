#!/usr/bin/env python3
"""T2: Offline regression test against saved Catalog HTML fixtures.

Reads each HTML fixture under ``tests/fixtures/<patch-month>/``, applies
the same parsers used in ``Update-WindowsServerIso.ps1``'s production
scrape path, and asserts that the result matches the recorded
expected.json for that fixture.

Unlike T1 (live probe), T2 does NOT contact the network and never
varies in output. It is the regression gate that should be re-run
whenever any of the following are changed:

- ``common/html_parsers.py``                 (parser logic)
- ``Update-WindowsServerIso.ps1``            (scrape helpers)
- ``Get-CatalogQueryTemplate`` (TitleTokens) (narrow-filter logic)

Exit codes:
    0   all assertions passed
    1   at least one assertion failed
    2   could not find fixtures / expected.json
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from common import html_parsers  # noqa: E402


@dataclass
class TestResult:
    name: str
    ok: bool
    message: str

    def __repr__(self) -> str:
        glyph = 'PASS' if self.ok else 'FAIL'
        return f'  {glyph}  {self.name}: {self.message}'


def _fixtures_dir(patch_month: str) -> Path:
    return _HERE / 'fixtures' / patch_month


def _load_expected(patch_month: str) -> dict:
    p = _fixtures_dir(patch_month) / 'expected.json'
    if not p.exists():
        raise FileNotFoundError(f'expected.json not found: {p}')
    return json.loads(p.read_text(encoding='utf-8'))


# -----------------
# Per-fixture test runners
# -----------------

def test_search_hit_count(fixture_name: str, html: str, expected_count: int) -> TestResult:
    """The same parser used in production must yield the recorded hit count."""
    hits = html_parsers.extract_search_hits(html)
    if len(hits) == expected_count:
        return TestResult(f'{fixture_name} hit count',
                          True, f'{len(hits)} hits (expected {expected_count})')
    return TestResult(f'{fixture_name} hit count',
                      False, f'{len(hits)} hits, expected {expected_count}')


def test_search_titles(fixture_name: str, html: str, expected_titles: list) -> TestResult:
    """The set of (update_id, title) pairs must exactly match expected."""
    hits = html_parsers.extract_search_hits(html)
    got = {(h.update_id, h.title) for h in hits}
    want = {(e['update_id'], e['title']) for e in expected_titles}
    if got == want:
        return TestResult(f'{fixture_name} titles', True, f'{len(got)} title(s) match')
    only_got = got - want
    only_want = want - got
    msg_parts: List[str] = []
    if only_got:
        msg_parts.append(f'unexpected: {sorted(only_got)[:3]}')
    if only_want:
        msg_parts.append(f'missing: {sorted(only_want)[:3]}')
    return TestResult(f'{fixture_name} titles', False, '; '.join(msg_parts))


def test_supersedence(fixture_name: str, html: str, expected_supersedes: list) -> TestResult:
    """extract_supersedes must reproduce the recorded list."""
    got = html_parsers.extract_supersedes(html)
    if got == expected_supersedes:
        return TestResult(f'{fixture_name} supersedence',
                          True, f'{len(got)} entry/entries')
    return TestResult(f'{fixture_name} supersedence',
                      False, f'got {got!r}, expected {expected_supersedes!r}')


# -----------------
# Bug-specific regression tests
# -----------------

def test_bug2_server2022_comma_less_titles(patch_month: str) -> TestResult:
    """Bug 2 (r04.3): Server2022 titles must NOT lose the comma-less form.

    If a future fixture refresh accidentally captures a Catalog state
    where Microsoft re-added the comma, this assertion alerts us
    immediately so ``Get-CatalogQueryTemplate.TitleTokens`` can be
    updated to keep the new form too.
    """
    fix_path = _fixtures_dir(patch_month) / 'server2022_lcu_search.html'
    if not fix_path.exists():
        return TestResult('bug2 server2022 comma-less', False,
                          f'fixture absent: {fix_path}')
    html = fix_path.read_text(encoding='utf-8')
    hits = html_parsers.extract_search_hits(html)
    if not hits:
        return TestResult('bug2 server2022 comma-less', False,
                          'no hits in fixture - upstream change?')
    comma_less = [h for h in hits if 'system version 21H2' in h.title]
    if comma_less:
        return TestResult('bug2 server2022 comma-less', True,
                          f'{len(comma_less)} hit(s) use the comma-less title form')
    return TestResult('bug2 server2022 comma-less', False,
                      'no hit uses the comma-less title form; SPEC §D.19 may need update')


def test_bug3_dotnet_umbrella_multi_files(patch_month: str) -> TestResult:
    """Bug 3 (r04.3): the Server2019 .NET search must return >= 2 hits.

    Server2019 .NET CU is the canonical umbrella-KB case (e.g.
    KB5088864 bundles 4.7.2 + 4.8). The umbrella search itself
    returns the multiple parent KBs; the multi-file picker
    then handles per-KB multi-file expansion downstream. This
    assertion guards the upstream side: that the Catalog still ranks
    multiple .NET CUs in a single search.
    """
    fix_path = _fixtures_dir(patch_month) / 'server2019_dotnet_search.html'
    if not fix_path.exists():
        return TestResult('bug3 dotnet umbrella', False,
                          f'fixture absent: {fix_path}')
    html = fix_path.read_text(encoding='utf-8')
    hits = html_parsers.extract_search_hits(html)
    server2019_hits = [h for h in hits if 'Server 2019' in h.title or 'server operating system' in h.title.lower()]
    if len(hits) < 2:
        return TestResult('bug3 dotnet umbrella', False,
                          f'.NET search returned {len(hits)} hits, expected >=2')
    return TestResult('bug3 dotnet umbrella', True,
                      f'.NET search returned {len(hits)} hits (Server2019-related: {len(server2019_hits)})')


# -----------------
# Orchestrator
# -----------------

def run_all_fixture_tests(patch_month: str) -> List[TestResult]:
    results: List[TestResult] = []
    expected = _load_expected(patch_month)
    fixtures = expected.get('fixtures', {})
    fix_dir = _fixtures_dir(patch_month)

    for fname, info in fixtures.items():
        fix_path = fix_dir / fname
        if not fix_path.exists():
            results.append(TestResult(fname, False, 'fixture HTML missing'))
            continue
        html = fix_path.read_text(encoding='utf-8')
        if 'total_hits' in info:
            results.append(test_search_hit_count(fname, html, info['total_hits']))
            results.append(test_search_titles(fname, html, info.get('titles', [])))
        if 'supersedes' in info:
            results.append(test_supersedence(fname, html, info['supersedes']))

    # Bug-specific regression tests (independent of expected.json)
    results.append(test_bug2_server2022_comma_less_titles(patch_month))
    results.append(test_bug3_dotnet_umbrella_multi_files(patch_month))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else 'Catalog fixture test')
    parser.add_argument('--patch-month', default='2026-05',
                        help='which fixtures/<patch-month>/ directory to test against')
    args = parser.parse_args()

    print(f'== T2 Catalog Fixture Test ==  patch_month={args.patch_month}')
    try:
        results = run_all_fixture_tests(args.patch_month)
    except FileNotFoundError as exc:
        print(f'ERROR: {exc}')
        return 2

    for r in results:
        print(r)

    failed = [r for r in results if not r.ok]
    print()
    print(f'  Summary: {len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} total')
    return 0 if not failed else 1


if __name__ == '__main__':
    sys.exit(main())
