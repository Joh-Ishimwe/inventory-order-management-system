#!/usr/bin/env python3
"""Reports products below their reorder point, and can restock them.

    python scripts/run_replenishment.py            report only
    python scripts/run_replenishment.py --apply    actually restock

Reporting is the default on purpose: reordering commits money, so it should
be a deliberate action rather than a side effect of running a script.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.monitoring.logging import get_logger, setup_logging  # noqa: E402
from src.pipelines.replenishment import replenish  # noqa: E402
from src.utils.config import load_config  # noqa: E402
from src.utils.paths import ensure_project_dirs  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Low stock report and replenishment.")
    parser.add_argument("--apply", action="store_true", help="place the restocks")
    parser.add_argument("--buffer", type=float, default=2.0,
                        help="restock to this multiple of the reorder level")
    parser.add_argument("--env", default=None)
    args = parser.parse_args()

    ensure_project_dirs()
    config = load_config(args.env)
    setup_logging(config.log_level, config.log_file)
    logger = get_logger("run_replenishment")

    try:
        outcome = replenish(config, buffer_multiplier=args.buffer, apply=args.apply)
    except Exception:
        logger.exception("replenishment run failed")
        return 1

    print(json.dumps(outcome, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
