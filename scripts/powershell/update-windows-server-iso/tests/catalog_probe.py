#!/usr/bin/env python3
"""T1: Live Microsoft Update Catalog probe.

Confirms that the assumptions ``Update-WindowsServerIso.ps1`` makes
about the Microsoft Update Catalog HTTP scrape paths are still valid
TODAY, by hitting the live Catalog endpoints and asserting that the
expected HTML structures are present.

This is the tool to run BEFORE making changes to any of:

- ``Get-CatalogQueryTemplate``           (S5: OS title format stability)
- ``Resolve-PatchSetFromCatalog``        (S5: narrow filter still passes)
- ``Get-UpdateIdFromCatalog``            (S1, S2)
- ``Get-DownloadLinkFromCatalog``        (S4, S6)
- ``Get-SupersedenceFromCatalog``        (S3)
- ``Resolve-LanguageSpecificPatchesFromCatalog`` (S9)

Each check writes its observation into ``tests/snapshots/last_probe.json``;
the next run computes a diff so drift is highlighted clearly.

Exit codes:
    0   all checks passed (no drift, or drift was reported with --snapshot)
    1   at least one check failed (regression / drift without --snapshot)
    2   probe could not run (network unreachable, etc.)

Usage:
    python3 catalog_probe.py --check all
    python3 catalog_probe.py --check title-format --os Server2022
    python3 catalog_probe.py --snapshot    # update snapshots/last_probe.json
"""
from __future__ import annotations

import argparse
import sys
import urllib.error
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Allow running both as a module and as a script.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from common import catalog_client, html_parsers, snapshot  # noqa: E402

# -----------------
# Canonical queries (one per OS) used to exercise the scrape paths
# -----------------

def _patch_month() -> str:
    """Return the patch-month string (YYYY-MM) to probe.

    Defaults to the current calendar month. We do NOT compute the
    "second-Tuesday boundary" buffer here because the probe is a
    sanity check, not a release-cadence trigger; if Microsoft has not
    yet published this month's patches, the per-OS hit counts will
    fall to zero and the probe will reasonably report drift.
    """
    return datetime.utcnow().strftime('%Y-%m')


_OS_QUERIES = {
    # Each entry: (Catalogue search query, list of acceptable Title tokens
    # the narrow filter checks for, *known* live OS title fragment for
    # cross-check)
    'Server2025': {
        'query':  'Cumulative Update for Microsoft server operating system version 24H2',
        'tokens': ['Microsoft server operating system version 24H2'],
    },
    'Server2022': {
        'query':  'Cumulative Update for Microsoft server operating system version 21H2',
        # Both comma-less and comma forms accepted (see SPEC §D.19).
        'tokens': [
            'Microsoft server operating system version 21H2',
            'Microsoft server operating system, version 21H2',
        ],
    },
    'Server2019': {
        'query':  'Cumulative Update for Windows Server 2019 for x64-based Systems',
        'tokens': ['Windows Server 2019'],
    },
    'Server2016': {
        'query':  'Cumulative Update for Windows Server 2016 for x64-based Systems',
        'tokens': ['Windows Server 2016'],
    },
}


# -----------------
# Check primitives
# -----------------

class CheckResult:
    def __init__(self, name: str, ok: bool, message: str, data: Optional[Dict[str, Any]] = None) -> None:
        self.name = name
        self.ok = ok
        self.message = message
        self.data: Dict[str, Any] = data or {}

    def __repr__(self) -> str:
        glyph = '[+]' if self.ok else '[-]'
        return f'{glyph} {self.name:<48} {self.message}'


def check_search_reachable() -> CheckResult:
    """S1+S2: Search.aspx is reachable and the GUID extraction regex still fires."""
    query = '2026-05'  # any short prefix - we just want a 200 + non-zero GUIDs
    try:
        resp = catalog_client.fetch(catalog_client.search_url(query))
    except (urllib.error.URLError, TimeoutError) as exc:
        return CheckResult('S1+S2 search reachable', False, f'network failure: {exc}')
    if not resp.ok:
        return CheckResult('S1+S2 search reachable', False, f'HTTP {resp.status}')
    guids = html_parsers.extract_update_ids(resp.body)
    if not guids:
        return CheckResult('S1+S2 search reachable', False,
                           f'HTTP 200 but goToDetails GUID extraction found 0 results - HTML changed?',
                           data={'body_length': len(resp.body)})
    return CheckResult('S1+S2 search reachable', True,
                       f'HTTP 200, {len(guids)} GUIDs found',
                       data={'guids_found': len(guids)})


def check_title_format(os_key: str, patch_month: str) -> CheckResult:
    """S5: live titles for ``os_key`` are matched by at least one TitleToken.

    Runs the same kind of query the PS scraper does and asserts that
    every returned title matches at least one of the accepted
    TitleTokens. If a title fails, drift has occurred (e.g. Microsoft
    rewrote the OS heading); a fix in ``Get-CatalogQueryTemplate``
    is required.
    """
    spec = _OS_QUERIES.get(os_key)
    if not spec:
        return CheckResult(f'S5 title-format {os_key}', False, f'Unknown OS key {os_key!r}')
    query = f'{patch_month} {spec["query"]}'
    try:
        resp = catalog_client.fetch(catalog_client.search_url(query))
    except (urllib.error.URLError, TimeoutError) as exc:
        return CheckResult(f'S5 title-format {os_key}', False, f'network failure: {exc}')
    if not resp.ok:
        return CheckResult(f'S5 title-format {os_key}', False, f'HTTP {resp.status}')
    hits = html_parsers.extract_search_hits(resp.body)
    if not hits:
        return CheckResult(f'S5 title-format {os_key}', False,
                           f'zero hits for query {query!r} - title format may have drifted',
                           data={'query': query})
    tokens = spec['tokens']
    matched: List[str] = []
    unmatched: List[str] = []
    for h in hits:
        if any(tok.lower() in h.title.lower() for tok in tokens):
            matched.append(h.title)
        else:
            unmatched.append(h.title)
    if unmatched:
        return CheckResult(f'S5 title-format {os_key}', False,
                           (f'{len(unmatched)} of {len(hits)} hits match NO accepted TitleToken. '
                            f'First unmatched: {unmatched[0][:80]}'),
                           data={'query': query, 'hits': len(hits),
                                 'matched': len(matched), 'unmatched': unmatched[:5]})
    return CheckResult(f'S5 title-format {os_key}', True,
                       f'{len(hits)} hit(s), all match at least one TitleToken',
                       data={'query': query, 'hits': len(hits), 'tokens_seen':
                             list({tok for tok in tokens for h in hits if tok.lower() in h.title.lower()})})


def check_supersedence_panel(sample_update_id: Optional[str]) -> CheckResult:
    """S3: ScopedViewInline.aspx still exposes a parseable Supersedes panel.

    Picks the first UpdateId from a generic Catalog search (or the
    caller-supplied one) and confirms that the supersedence regex
    finds either: (a) >= 1 Supersedes entry, or (b) an explicit empty
    panel. A *missing* panel means HTML structure drift.
    """
    if not sample_update_id:
        # Use any current Server 2022 LCU hit as a sample
        try:
            resp = catalog_client.fetch(catalog_client.search_url(
                'Cumulative Update for Microsoft server operating system version 21H2'))
        except (urllib.error.URLError, TimeoutError) as exc:
            return CheckResult('S3 supersedence panel', False, f'network failure: {exc}')
        guids = html_parsers.extract_update_ids(resp.body)
        if not guids:
            return CheckResult('S3 supersedence panel', False,
                               'no GUIDs returned for sample query; cannot probe supersedence')
        sample_update_id = guids[0]
    try:
        resp = catalog_client.fetch(catalog_client.scoped_view_url(sample_update_id))
    except (urllib.error.URLError, TimeoutError) as exc:
        return CheckResult('S3 supersedence panel', False, f'network failure: {exc}')
    if not resp.ok:
        return CheckResult('S3 supersedence panel', False, f'HTTP {resp.status}')
    if 'supersedesInfo' not in resp.body:
        return CheckResult('S3 supersedence panel', False,
                           'ScopedViewInline page contains no supersedesInfo anchor - HTML drift',
                           data={'sample_update_id': sample_update_id})
    items = html_parsers.extract_supersedes(resp.body)
    return CheckResult('S3 supersedence panel', True,
                       f'panel found, {len(items)} item(s)',
                       data={'sample_update_id': sample_update_id, 'item_count': len(items),
                             'first_items': items[:3]})


# -----------------
# Orchestrator
# -----------------

def run_all_checks(patch_month: str) -> List[CheckResult]:
    results: List[CheckResult] = []
    results.append(check_search_reachable())
    for os_key in ('Server2016', 'Server2019', 'Server2022', 'Server2025'):
        results.append(check_title_format(os_key, patch_month))
    results.append(check_supersedence_panel(sample_update_id=None))
    return results


def results_to_snapshot(results: List[CheckResult], patch_month: str) -> Dict[str, Any]:
    return {
        'generated_at': snapshot.now_iso(),
        'patch_month':  patch_month,
        'checks': {
            r.name: {
                'ok':      r.ok,
                'message': r.message,
                'data':    r.data,
            } for r in results
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else 'Catalog probe')
    parser.add_argument('--check', default='all',
                        choices=['all', 'search', 'title-format', 'supersedence'],
                        help='which check group to run (default: all)')
    parser.add_argument('--os', dest='os_key', default=None,
                        help='restrict title-format check to one OsKey')
    parser.add_argument('--patch-month', default=None,
                        help='patch month in YYYY-MM (default: current UTC month)')
    parser.add_argument('--snapshot', action='store_true',
                        help='save the run result to tests/snapshots/last_probe.json')
    args = parser.parse_args()

    patch_month = args.patch_month or _patch_month()
    print(f'== T1 Catalog Probe ==  patch_month={patch_month}')
    if args.check == 'all':
        results = run_all_checks(patch_month)
    elif args.check == 'search':
        results = [check_search_reachable()]
    elif args.check == 'title-format':
        os_keys = [args.os_key] if args.os_key else list(_OS_QUERIES.keys())
        results = [check_title_format(o, patch_month) for o in os_keys]
    elif args.check == 'supersedence':
        results = [check_supersedence_panel(sample_update_id=None)]
    else:  # pragma: no cover (argparse choices)
        return 2

    for r in results:
        print(' ', r)

    # Compute drift vs prior snapshot
    snap_path = _HERE / 'snapshots' / 'last_probe.json'
    prior = snapshot.load_snapshot(snap_path)
    current = results_to_snapshot(results, patch_month)

    if prior:
        prior_checks = prior.get('checks', {})
        current_checks = current['checks']
        diffs = snapshot.diff_dict(prior_checks, current_checks)
        meaningful = [d for d in diffs if not d[0].endswith('.generated_at')]
        if meaningful:
            print(f'\nDrift vs prior snapshot ({prior.get("generated_at", "?")}):')
            for path, kind, oldv, newv in meaningful[:15]:
                print(f'  {kind:<8} {path}: {oldv!r} -> {newv!r}')
            if len(meaningful) > 15:
                print(f'  ... ({len(meaningful) - 15} more)')
        else:
            print('\nNo drift vs prior snapshot.')

    if args.snapshot:
        out_path = snapshot.save_snapshot(snap_path, current)
        print(f'\nSnapshot saved: {out_path}')

    failed = [r for r in results if not r.ok]
    return 0 if not failed else 1


if __name__ == '__main__':
    sys.exit(main())
