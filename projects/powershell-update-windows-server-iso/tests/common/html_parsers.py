"""HTML extraction patterns for Microsoft Update Catalog responses.

Each parser mirrors a regex used inside ``Update-WindowsServerIso.ps1``:

- ``extract_update_ids``:    ``Get-UpdateIdFromCatalog`` (Search.aspx GUID hits)
- ``extract_titles``:        the Title column on Search.aspx hits
- ``extract_download_urls``: ``Get-DownloadLinkFromCatalog``
                             (DownloadDialog.aspx files-array)
- ``extract_supersedes``:    supersedence section parser
                             (ScopedViewInline.aspx supersedence panel)

Keeping these in a single Python module lets the probes assert that the
parser still recognises what the live Catalog emits AND that the same
regex still works against the saved offline fixtures.

If the Catalog ever changes its HTML structure, the failing assertion
will be in ONE place (this module), and the fix lands here AND in the
matching PowerShell scraper - they are intentionally kept in sync.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import List, Optional


# -----------------
# Search.aspx hits
# -----------------

# Matches:
#   goToDetails("4d2eef27-0f15-49a4-94db-4f8a2c54ae3d")
_RX_GUID = re.compile(r'goToDetails\("([0-9a-fA-F-]+)"\)')

# Matches the Title <a> element, e.g.:
#   <a ... id="<guid>_link"
#      ... onclick="goToDetails(...)"
#      ... >  2026-05 Cumulative Update for ...  </a>
# Quotes around id can be single or double; Catalog uses both forms.
_RX_TITLE_LINK = re.compile(
    r"""<a\b[^>]*\bid=['"]([0-9a-fA-F-]+)_link['"][^>]*>\s*([^<]+?)\s*</a>""",
    re.IGNORECASE | re.DOTALL,
)


@dataclass
class SearchHit:
    update_id: str
    title: str


def extract_update_ids(html: str) -> List[str]:
    """Return the list of UpdateId GUIDs found in a Search.aspx page.

    De-duplicated, order-preserving.
    """
    seen = set()
    out: List[str] = []
    for m in _RX_GUID.finditer(html):
        guid = m.group(1).lower()
        if guid not in seen:
            seen.add(guid)
            out.append(guid)
    return out


def extract_search_hits(html: str) -> List[SearchHit]:
    """Return Search.aspx hits as a list of (update_id, title) tuples.

    Order matches the order of <a id="...link"> elements in the HTML;
    duplicates (same id, same title) are collapsed.
    """
    seen = set()
    out: List[SearchHit] = []
    for m in _RX_TITLE_LINK.finditer(html):
        guid = m.group(1).lower()
        title = m.group(2).strip()
        # Decode common HTML entities the Catalog uses
        title = title.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>').replace('&quot;', '"')
        key = (guid, title)
        if key not in seen:
            seen.add(key)
            out.append(SearchHit(update_id=guid, title=title))
    return out


# -----------------
# DownloadDialog files
# -----------------

# Matches:
#   downloadInformation[0].files[0].url = 'https://...msu';
_RX_DOWNLOAD_URL = re.compile(
    r"downloadInformation\[\d+\]\.files\[\d+\]\.url\s*=\s*'([^']+)'",
    re.IGNORECASE,
)


def extract_download_urls(html: str) -> List[str]:
    """Return all file URLs found in a DownloadDialog.aspx response.

    Order matches order in the page; duplicates removed.
    """
    seen = set()
    out: List[str] = []
    for m in _RX_DOWNLOAD_URL.finditer(html):
        url = m.group(1)
        if url not in seen:
            seen.add(url)
            out.append(url)
    return out


# -----------------
# ScopedViewInline supersedence
# -----------------

# Matches the Supersedes panel; ScopedViewInline.aspx renders it as:
#   <div id="supersedesInfo">
#       <a ...>Title 1</a>
#       <a ...>Title 2</a>
#   </div>
# or "n/a" when the update supersedes nothing. The regex captures the
# div body so we can decide between "n/a" and a real list of anchors.
_RX_SUPERSEDES_BLOCK = re.compile(
    r'<div\b[^>]*\bid=["\']supersedesInfo["\'][^>]*>(.*?)</div>',
    re.IGNORECASE | re.DOTALL,
)
_RX_INNER_HREF = re.compile(r'<a\b[^>]*>([^<]+)</a>', re.IGNORECASE | re.DOTALL)
_RX_KB = re.compile(r'\b(KB\d{6,7})\b')


def extract_supersedes(html: str) -> List[str]:
    """Return the list of Supersedes entries from a ScopedViewInline page.

    Each entry is the text of one <a> tag inside the
    ``supersedesInfo`` div, with whitespace collapsed. Returns ``[]``
    when the panel is absent OR when its content is literally ``n/a``
    (Catalog's representation of "this update supersedes nothing").
    """
    block_match = _RX_SUPERSEDES_BLOCK.search(html)
    if not block_match:
        return []
    block = block_match.group(1)
    # "n/a" with optional whitespace means no supersedes
    if re.match(r'^\s*n/a\s*$', block, re.IGNORECASE):
        return []
    items = [re.sub(r'\s+', ' ', m.group(1)).strip() for m in _RX_INNER_HREF.finditer(block)]
    return [i for i in items if i]


def title_mentions_kb(title: str) -> Optional[str]:
    """Return any KB token found in the title (with or without parens), or None."""
    m = _RX_KB.search(title)
    return m.group(1) if m else None
