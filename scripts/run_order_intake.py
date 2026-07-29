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

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.ingestion.files import read_order_requests  # noqa: E402
from src.monitoring.logging import get_logger, setup_logging  # noqa: E402
from src.pipelines.order_processing import process_orders  # noqa: E402
from src.utils.config import load_config  # noqa: E402
from src.utils.paths import ensure_project_dirs  # noqa: E402


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
