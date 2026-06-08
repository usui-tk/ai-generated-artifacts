"""HTTP fetcher for Microsoft Update Catalog.

Uses only stdlib (``urllib.request``) so no pip install is required.
Encapsulates the URL templates, headers, retry-with-jitter, and timeout
policy in one place so the per-check probes do not duplicate them.

The User-Agent matches the one used by the PowerShell scraper in
``Update-WindowsServerIso.ps1`` (``UpdateWsi/r02``) so both clients are
indistinguishable from the Catalogue's perspective; this keeps the
Python probes a faithful representation of what the production
PowerShell scraper sees.
"""
from __future__ import annotations

import time
import random
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Optional

_BASE = 'https://www.catalog.update.microsoft.com'
_DEFAULT_USER_AGENT = 'Mozilla/5.0 (compatible; UpdateWsi/r02)'
_DEFAULT_TIMEOUT = 30  # seconds


@dataclass
class CatalogResponse:
    """Result of a Catalog HTTP GET."""
    url: str
    status: int
    body: str
    headers: dict

    @property
    def ok(self) -> bool:
        return 200 <= self.status < 300


def search_url(query: str) -> str:
    """Build the Search.aspx URL for the given query string.

    Matches the URL construction in
    ``Get-UpdateIdFromCatalog`` (PS) so probes use the same endpoint
    the production scraper does.
    """
    return _BASE + '/Search.aspx?q=' + urllib.parse.quote(query)


def scoped_view_url(update_id: str) -> str:
    """Build the ScopedViewInline.aspx URL for a given UpdateId."""
    return _BASE + '/ScopedViewInline.aspx?updateid=' + urllib.parse.quote(update_id)


def download_dialog_url(update_id: str) -> str:
    """Build the DownloadDialog.aspx URL for a given UpdateId.

    The DownloadDialog endpoint accepts a POST body containing the
    UpdateId list as JSON-ish. The production PowerShell scraper uses
    a different (simpler) endpoint that GETs the page, so we replicate
    that path here.
    """
    return _BASE + '/DownloadDialog.aspx'


def fetch(
    url: str,
    *,
    user_agent: str = _DEFAULT_USER_AGENT,
    timeout: int = _DEFAULT_TIMEOUT,
    max_retries: int = 3,
    method: str = 'GET',
    data: Optional[bytes] = None,
    extra_headers: Optional[dict] = None,
) -> CatalogResponse:
    """GET (or POST) a URL with retry-with-jitter.

    Returns ``CatalogResponse``. On final failure raises
    ``urllib.error.URLError`` to the caller.
    """
    headers = {'User-Agent': user_agent}
    if extra_headers:
        headers.update(extra_headers)
    last_err: Optional[BaseException] = None
    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                body = resp.read().decode('utf-8', errors='replace')
                return CatalogResponse(
                    url=url,
                    status=resp.status,
                    body=body,
                    headers=dict(resp.headers.items()),
                )
        except (urllib.error.URLError, TimeoutError) as exc:
            last_err = exc
            if attempt < max_retries:
                # exponential backoff with jitter (matches PS Wait-WithJitter)
                base = 2 ** (attempt - 1)
                jitter = random.uniform(0.0, 1.5)
                time.sleep(base + jitter)
    if last_err is not None:
        raise last_err
    raise RuntimeError('Unreachable: fetch exited the retry loop without success or error')


def head(
    url: str,
    *,
    user_agent: str = _DEFAULT_USER_AGENT,
    timeout: int = _DEFAULT_TIMEOUT,
) -> CatalogResponse:
    """Issue a HEAD request, following one redirect if present.

    Used by the Eval-ISO and wsusscn2 probes to inspect Last-Modified
    / Content-Length without downloading the body.
    """
    return fetch(url, method='HEAD', timeout=timeout, user_agent=user_agent, max_retries=2)
