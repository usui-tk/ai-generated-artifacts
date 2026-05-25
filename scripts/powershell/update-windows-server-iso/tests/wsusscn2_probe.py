#!/usr/bin/env python3
"""T5: wsusscn2.cab freshness probe.

``Update-WindowsServerIso.ps1`` P06 ``ValidatePatchSet`` relies on
Microsoft's offline-scan catalog ``wsusscn2.cab``. Microsoft refreshes
this cab roughly monthly with the latest Windows Update Agent metadata
for every product they still service. If the cab on disk is more than
~45 days old, the validator may incorrectly flag a current LCU as
"missing dependency" because the catalog has not yet learned the new
KB number.

This probe HEADs (well, Ranges) the canonical wsusscn2.cab URL and
reports the ``Last-Modified`` and ``Content-Length`` headers. The
operator (or Claude) can compare that timestamp against today to
decide whether to pull a fresh copy.

We do NOT download the cab (~1 GB). We do NOT verify a SHA-256 -
Microsoft does not publish one for wsusscn2.cab.

Exit codes:
    0   cab endpoint reachable and not impossibly stale
    1   cab endpoint reachable but appears stale (> 60 days old)
    2   endpoint unreachable (genuine network or Microsoft-side failure)
    3   endpoint blocked by local egress proxy (NOT a Microsoft failure;
        re-run from a less-restricted environment)
"""
from __future__ import annotations

import argparse
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

# Canonical wsusscn2.cab URL used by Microsoft Update Agent.
# Documented at https://learn.microsoft.com/windows/win32/wua_sdk/using-wua-to-scan-for-updates-offline
_WSUSSCN2_URLS = [
    'https://catalog.s.download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab',
    # Mirror occasionally used; check it as a fallback for diagnostic value
    'http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab',
]


def _probe(url: str, *, timeout: int = 30) -> dict:
    """Range-GET the wsusscn2.cab URL and return a dict of headers."""
    req = urllib.request.Request(
        url,
        headers={
            'User-Agent': 'Mozilla/5.0 (compatible; UpdateWsi-WsusScn2Probe/0.1)',
            'Range':      'bytes=0-1',
        },
    )
    out: dict = {'url': url, 'ok': False}
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            out['ok']             = True
            out['final_url']      = resp.url
            out['status']         = resp.status
            out['content_range']  = resp.headers.get('Content-Range', '')
            out['last_modified']  = resp.headers.get('Last-Modified', '')
            resp.read()  # drain 2-byte body
    except urllib.error.HTTPError as he:
        deny = he.headers.get('x-deny-reason', '') if he.headers else ''
        if deny:
            # The HTTP egress proxy refused the destination host (common in
            # constrained execution environments like Claude sessions). This
            # is NOT a Microsoft-side failure; flag it so the operator knows
            # to re-run from a less restricted environment.
            out['error'] = f'HTTP {he.code} (egress proxy denied: {deny})'
            out['proxy_denied'] = True
        else:
            out['error'] = f'HTTP {he.code}'
    except (urllib.error.URLError, TimeoutError) as exc:
        out['error'] = f'network: {exc}'
    return out


def _parse_total_size(content_range: str) -> int:
    if '/' not in content_range:
        return 0
    try:
        return int(content_range.rsplit('/', 1)[1])
    except ValueError:
        return 0


def _age_days(last_modified_header: str) -> float:
    """Convert an HTTP-date string to age in days (UTC); returns -1 on parse fail."""
    try:
        dt = parsedate_to_datetime(last_modified_header)
    except (TypeError, ValueError):
        return -1.0
    if dt is None:
        return -1.0
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - dt
    return delta.total_seconds() / 86400.0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else 'wsusscn2.cab probe')
    parser.add_argument('--stale-days', type=int, default=60,
                        help='age threshold beyond which the cab is treated as stale (default 60)')
    parser.add_argument('--all-mirrors', action='store_true',
                        help='also probe non-primary mirror URLs (default: primary only)')
    args = parser.parse_args()

    print('== T5 wsusscn2.cab Probe ==')

    urls = _WSUSSCN2_URLS if args.all_mirrors else _WSUSSCN2_URLS[:1]
    any_ok = False
    any_stale = False
    any_proxy_denied = False
    for url in urls:
        print(f'  Probing: {url}')
        result = _probe(url)
        if not result.get('ok'):
            if result.get('proxy_denied'):
                any_proxy_denied = True
            print(f'    FAIL  {result.get("error", "<no error>")}')
            continue
        any_ok = True
        size_total = _parse_total_size(result.get('content_range', ''))
        last_mod   = result.get('last_modified', '')
        age        = _age_days(last_mod)
        if size_total > 0:
            size_str = f'{size_total // (1024*1024)} MB'
        else:
            size_str = '<unknown>'
        if age >= 0:
            age_str = f'{age:.1f} days old'
        else:
            age_str = 'age unknown'
        print(f'    OK    HTTP {result.get("status")}, {size_str}, Last-Modified: {last_mod or "n/a"} ({age_str})')
        if age >= 0 and age > args.stale_days:
            any_stale = True
            print(f'    WARN  cab is {age:.0f} days old (> {args.stale_days} day threshold); '
                  f'P06 may misclassify recent KBs as "missing dependency"')

    print()
    if not any_ok:
        if any_proxy_denied:
            print('  Summary: endpoint blocked by egress proxy in this execution environment.')
            print('           This is NOT a Microsoft-side failure - the destination host is not')
            print('           in the proxy allow-list. Re-run this probe from an unrestricted')
            print('           network (developer workstation, CI runner with full egress).')
            return 3
        print('  Summary: 0 mirror(s) reachable.')
        return 2
    if any_stale:
        print('  Summary: cab reachable but stale.')
        return 1
    print('  Summary: cab reachable and within freshness window.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
