"""Reading incoming files.

One malformed row must never stop the whole file. Bad rows are logged and
set aside; good rows carry on.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

from src.monitoring.logging import get_logger
from src.transformations.validation import validate_product_row
from src.utils.paths import project_path

logger = get_logger(__name__)


def read_product_csv(relative_path: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Read a product CSV and return (accepted rows, rejected rows).

    Returning both instead of raising is the point: the caller can load what
    was good and report what was not, rather than losing the whole batch.
    """
    path: Path = project_path(relative_path)
    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {relative_path}")

    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []

    with open(path, "r", encoding="utf-8", newline="") as handle:
        for line_number, row in enumerate(csv.DictReader(handle), start=2):
            result = validate_product_row(row)
            if result.is_valid and result.cleaned:
                accepted.append(result.cleaned)
            else:
                rejected.append({"line": line_number, "row": row, "errors": result.errors})
                logger.warning(
                    "row rejected",
                    extra={"context": {
                        "file": relative_path,
                        "line": line_number,
                        "errors": result.errors,
                    }},
                )

    logger.info(
        "file read",
        extra={"context": {
            "file": relative_path,
            "accepted": len(accepted),
            "rejected": len(rejected),
        }},
    )
    return accepted, rejected


def read_order_requests(relative_path: str) -> list[dict[str, Any]]:
    """Read a JSON file holding a list of order requests."""
    path: Path = project_path(relative_path)
    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {relative_path}")
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, list):
        raise ValueError("Expected a JSON list of order requests")
    return payload
