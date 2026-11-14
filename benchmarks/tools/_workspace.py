"""Explicit suite/game roots; offline comparison modules need no game checkout."""
from __future__ import annotations

import os
from pathlib import Path

BENCHMARK_ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_TOOLS = BENCHMARK_ROOT / 'tools'


def game_root(value: str | Path | None = None) -> Path:
    root = Path(value or os.environ.get('NITROQUAKE_GAME_ROOT') or BENCHMARK_ROOT.parent / 'quake').resolve()
    for relative in ('tools/build-dos.ps1', 'tools/build-dos-experimental.ps1',
                     'tools/common.ps1', 'src/quakedef.h'):
        if not (root / relative).is_file():
            raise ValueError(f'Not a NitroQuake checkout: {root} (missing {relative}); supply --game-root or NITROQUAKE_GAME_ROOT')
    return root


def game_tool(name: str, root: Path | None = None) -> Path:
    return (root or game_root()) / 'tools' / name
