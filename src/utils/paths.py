"""Filesystem setup.

The pipeline should never fall over because a folder was missing. It creates
what it needs on startup instead of expecting someone to have made it.
"""
from __future__ import annotations

from pathlib import Path

from src.utils.constants import REQUIRED_DIRS

# This file is src/utils/paths.py, so the project root is three levels up.
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def project_path(*parts: str) -> Path:
    """Turn a path relative to the project root into an absolute one."""
    return PROJECT_ROOT.joinpath(*parts)


def ensure_project_dirs(extra: list[str] | None = None) -> list[Path]:
    """Create every folder the pipeline writes to.

    exist_ok=True means running this twice is harmless, and parents=True
    means nested paths like data/raw work even if data/ is missing too.
    """
    created: list[Path] = []
    for rel in REQUIRED_DIRS + (extra or []):
        path = project_path(rel)
        if not path.exists():
            path.mkdir(parents=True, exist_ok=True)
            created.append(path)
    return created


def ensure_parent_dir(file_path: Path) -> Path:
    """Make sure the folder for a file exists before writing the file."""
    file_path.parent.mkdir(parents=True, exist_ok=True)
    return file_path
