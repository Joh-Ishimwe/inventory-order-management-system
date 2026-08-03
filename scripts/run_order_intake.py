#!/usr/bin/env python3
"""Places a batch of orders from a JSON file.

    python scripts/run_order_intake.py data/samples/order_requests.json

The sample file deliberately contains bad requests. The point is that they
are reported and skipped while the good ones still go through.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.monitoring.logging import get_logger, setup_logging  # noqa: E402
from src.pipelines.order_processing import process_orders  # noqa: E402
from src.utils.config import load_config  # noqa: E402
from src.utils.paths import ensure_project_dirs, project_path  # noqa: E402


def read_order_requests(relative_path: str) -> list[dict[str, Any]]:
    """Read a JSON file holding a list of order requests."""
    path = project_path(relative_path)
    if not path.exists():
        raise FileNotFoundError(f"Input file not found: {relative_path}")
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if not isinstance(payload, list):
        raise ValueError("Expected a JSON list of order requests")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description="Place a batch of orders.")
    parser.add_argument("input_file", nargs="?", default="data/samples/order_requests.json")
    parser.add_argument("--env", default=None)
    args = parser.parse_args()

    ensure_project_dirs()
    config = load_config(args.env)
    setup_logging(config.log_level, config.log_file)
    logger = get_logger("run_order_intake")

    try:
        requests = read_order_requests(args.input_file)
        outcome = process_orders(config, requests)
    except Exception:
        logger.exception("order intake failed")
        return 1

    print(json.dumps(outcome, indent=2, default=str))
    # Some orders failing is a normal outcome, not a crash, so this still
    # exits zero. Only an unrecoverable failure returns non-zero.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
