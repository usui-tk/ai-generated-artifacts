"""JSON snapshot read/write + diff helpers.

The Catalog probe (T1) records the current shape of the live Catalog
HTML (per-OS hit counts, observed title patterns, supersedence
counts) as a JSON snapshot under ``tests/snapshots/last_probe.json``.
On the next run, the new snapshot is compared with the saved one and
any drift is reported.

Snapshots are kept JSON-stable: keys sorted, 2-space indented,
final newline - so ``git diff`` and human review are tractable.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


def save_snapshot(path: str | Path, data: Dict[str, Any]) -> Path:
    """Persist ``data`` as a JSON snapshot. Returns the resolved path."""
    p = Path(path).resolve()
    p.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + '\n'
    p.write_text(body, encoding='utf-8')
    return p


def load_snapshot(path: str | Path) -> Optional[Dict[str, Any]]:
    """Load a JSON snapshot, returning ``None`` if the file is absent."""
    p = Path(path)
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding='utf-8'))


def now_iso() -> str:
    """Current UTC time as ISO 8601 (e.g. for snapshot timestamps)."""
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def diff_dict(old: Optional[Dict[str, Any]], new: Dict[str, Any]) -> List[Tuple[str, str, Any, Any]]:
    """Return a flat list of differences between two dicts.

    Each entry is a 4-tuple ``(path, kind, old_value, new_value)`` where
    ``kind`` is one of ``'added'`` / ``'removed'`` / ``'changed'``.
    Recurses into nested dicts; lists are compared as whole values.

    Example return entry:
        ('Server2022.title_count', 'changed', 4, 5)
    """
    out: List[Tuple[str, str, Any, Any]] = []
    if old is None:
        out.append(('<root>', 'added', None, new))
        return out
    _diff_dict_into(old, new, prefix='', out=out)
    return out


def _diff_dict_into(old: Dict[str, Any], new: Dict[str, Any], prefix: str, out: List) -> None:
    old_keys = set(old.keys())
    new_keys = set(new.keys())

    for key in sorted(new_keys - old_keys):
        out.append((f'{prefix}{key}', 'added', None, new[key]))
    for key in sorted(old_keys - new_keys):
        out.append((f'{prefix}{key}', 'removed', old[key], None))
    for key in sorted(old_keys & new_keys):
        ov = old[key]
        nv = new[key]
        new_prefix = f'{prefix}{key}.'
        if isinstance(ov, dict) and isinstance(nv, dict):
            _diff_dict_into(ov, nv, new_prefix, out)
        elif ov != nv:
            out.append((f'{prefix}{key}', 'changed', ov, nv))
