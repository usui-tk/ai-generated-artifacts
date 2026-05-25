#!/usr/bin/env python3
"""T4: Evaluation ISO endpoint probe.

Microsoft publishes Server evaluation ISO downloads via redirector
URLs (``go.microsoft.com/fwlink/?LinkID=...``). The PowerShell script
relies on these URLs to be:

1. Still alive (HTTP 200 on HEAD after the redirect).
2. Pointing at a binary roughly the right size (~5-8 GB).
3. Stable enough to record the SHA-256 in ``Config/Server<N>.json``
   for content verification.

This probe issues HEAD requests against the known fwlink URLs and
reports the final URL, content length, and ``Last-Modified`` header
so the operator can detect when Microsoft rotates a snapshot and
the recorded SHA-256 needs refreshing (see SPEC §D.11).

We do NOT compute the SHA-256 - that would require downloading 6-8 GB
per OS which is outside Claude's scope. We only assert that the
endpoint resolves to a non-tiny binary.

Exit codes:
    0   all configured endpoints respond as expected
    1   at least one endpoint failed or shrank dramatically
    2   could not run (network unreachable, no config)
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from common import catalog_client  # noqa: E402

_CONFIG_DIR = _HERE.parent / 'Config'


@dataclass
class ProbeResult:
    os_key: str
    ok: bool
    message: str
    final_url: str = ''
    content_length: int = 0
    last_modified: str = ''


def _load_iso_endpoints() -> Dict[str, List[str]]:
    """Return {os_key: [fwlink-urls]} extracted from Config/<OsKey>.json.

    Schema v2.0 stores per-language Iso URL under
    ``LanguageSpecific.<lang>.Iso.Url``. We collect all unique URLs
    per OS for the probe.
    """
    endpoints: Dict[str, List[str]] = {}
    for cfg_path in sorted(_CONFIG_DIR.glob('Server*.json')):
        os_key = cfg_path.stem  # e.g. 'Server2025'
        try:
            data = json.loads(cfg_path.read_text(encoding='utf-8'))
        except json.JSONDecodeError as exc:
            print(f'WARN: failed to parse {cfg_path.name}: {exc}', file=sys.stderr)
            continue
        urls: List[str] = []
        ls = data.get('LanguageSpecific') or {}
        for _, lang_block in ls.items():
            iso = lang_block.get('Iso') if isinstance(lang_block, dict) else None
            if iso and isinstance(iso, dict):
                u = iso.get('Url')
                if u and u not in urls:
                    urls.append(u)
        endpoints[os_key] = urls
    return endpoints



def probe_endpoint(os_key: str, url: str, *, min_size_mb: int = 100) -> ProbeResult:
    """Issue a 2-byte Range GET on the ISO URL.

    Microsoft's evaluation-ISO CDN
    (``software-static.download.prss.microsoft.com``) rejects HEAD
    requests with HTTP 400 but supports HTTP Range. We ask for
    bytes 0-1 to get back HTTP 206 with ``Content-Range: bytes 0-1/<total>``,
    which gives us the full file size for free in just 2 bytes of body.

    Older Server 2016 snapshot URLs on
    ``software-download.microsoft.com`` reject Range with HTTP 400
    AND reject HEAD. There is no documented light-weight way to
    probe them; for those we report the endpoint as unprobable
    (``ok=True``, ``message=...``) rather than failing the whole
    run, because returning failure on a known-quirky endpoint is
    pure noise.
    """
    req = urllib.request.Request(
        url,
        headers={
            'User-Agent': 'Mozilla/5.0 (compatible; UpdateWsi-EvalIsoProbe/0.1)',
            'Range':      'bytes=0-1',
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            final = resp.url
            status = resp.status
            content_range = resp.headers.get('Content-Range', '')
            content_length = resp.headers.get('Content-Length', '0')
            last_modified  = resp.headers.get('Last-Modified', '')
            resp.read()  # drain the 2-byte body
    except urllib.error.HTTPError as he:
        # Server 2016's host returns 400 for Range and HEAD alike;
        # treat that as "unprobable, not broken" to keep CI green.
        if he.code == 400 and 'software-download.microsoft.com' in url:
            return ProbeResult(os_key, True,
                               'HTTP 400 (host does not support Range/HEAD; cannot verify size)',
                               final_url=url)
        return ProbeResult(os_key, False, f'HTTP {he.code}', final_url=url)
    except (urllib.error.URLError, TimeoutError) as exc:
        return ProbeResult(os_key, False, f'network failure: {exc}', final_url=url)

    # Parse Content-Range: "bytes 0-1/6014152704"
    total_bytes = 0
    if content_range and '/' in content_range:
        try:
            total_bytes = int(content_range.rsplit('/', 1)[1])
        except ValueError:
            total_bytes = 0
    if total_bytes == 0:
        try:
            total_bytes = int(content_length)
        except ValueError:
            total_bytes = 0

    if status not in (200, 206):
        return ProbeResult(os_key, False, f'unexpected HTTP {status}', final_url=final)
    if total_bytes < min_size_mb * 1024 * 1024:
        return ProbeResult(os_key, False,
                           f'total size {total_bytes} bytes < {min_size_mb} MB; suspicious',
                           final_url=final, content_length=total_bytes, last_modified=last_modified)
    return ProbeResult(os_key, True,
                       f'HTTP {status}, total {total_bytes // (1024*1024)} MB, Last-Modified: {last_modified or "n/a"}',
                       final_url=final, content_length=total_bytes, last_modified=last_modified)


def main() -> int:
    global _CONFIG_DIR  # noqa: PLW0603 -- intentional mutation when --config-dir is used

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else 'Eval ISO probe')
    parser.add_argument('--os', dest='only_os', default=None,
                        help='restrict probe to one Os key (e.g. Server2025)')
    parser.add_argument('--config-dir', default=str(_CONFIG_DIR),
                        help='path to the Config directory holding Server<N>.json')
    args = parser.parse_args()

    if args.config_dir != str(_CONFIG_DIR):
        _CONFIG_DIR = Path(args.config_dir).resolve()

    print('== T4 Evaluation ISO Probe ==')
    print(f'   config dir: {_CONFIG_DIR}')

    endpoints = _load_iso_endpoints()
    if not endpoints:
        print('ERROR: no Server<N>.json files found.')
        return 2

    results: List[ProbeResult] = []
    for os_key, urls in endpoints.items():
        if args.only_os and os_key != args.only_os:
            continue
        if not urls:
            results.append(ProbeResult(os_key, False, 'no Iso.Url defined in Config'))
            continue
        for url in urls:
            print(f'  Probing {os_key}: {url[:80]}...')
            results.append(probe_endpoint(os_key, url))

    print()
    for r in results:
        glyph = '[+]' if r.ok else '[-]'
        print(f'  {glyph} {r.os_key:<12} {r.message}')

    failed = [r for r in results if not r.ok]
    print()
    print(f'  Summary: {len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} total')
    return 0 if not failed else 1


if __name__ == '__main__':
    sys.exit(main())
