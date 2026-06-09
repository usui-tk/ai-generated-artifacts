"""Common utilities for the Update-WindowsServerIso self-verification tools.

These tools live under ``projects/powershell-update-windows-server-iso/tests/``
and exist to give Claude (and human operators) a self-verification surface
for the Microsoft Update Catalog HTTP scrape paths and other external
dependencies baked into ``Update-WindowsServerIso.ps1``. The split between
``common/`` (this package) and the per-tool entry-point scripts
(``catalog_probe.py``, ``catalog_fixture_test.py``, etc.) follows the
``psa.py`` precedent: standard-library-only Python, no pip install
required, no third-party HTTP library.
"""

__all__ = [
    'catalog_client',
    'html_parsers',
    'ps_invoke',
    'snapshot',
]
