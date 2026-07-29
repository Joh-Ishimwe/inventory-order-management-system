#!/usr/bin/env python3
"""One command to build the whole project.

    python scripts/run_pipeline.py                 build + seed
    python scripts/run_pipeline.py --with-tests    also run the test suites
    python scripts/run_pipeline.py --with-security also create roles/grants
    python scripts/run_pipeline.py --no-seed       empty database only

Missing folders are created on the way, so this works on a fresh clone.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Lets the script run from anywhere without setting PYTHONPATH.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.monitoring.logging import get_logger, setup_logging  # noqa: E402
from src.pipelines import build_database  # noqa: E402
from src.utils.config import load_config  # noqa: E402
from src.utils.paths import ensure_project_dirs  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the inventory and order database.")
    parser.add_argument("--env", default=None, help="config environment (default: dev)")
    parser.add_argument("--no-seed", action="store_true", help="skip the sample data")
    parser.add_argument("--with-tests", action="store_true", help="run the test suites")
    parser.add_argument("--with-security", action="store_true", help="create roles and grants")
    args = parser.parse_args()

    # Before anything else: make sure the folders this run writes to exist.
    created = ensure_project_dirs()

    config = load_config(args.env)
    setup_logging(config.log_level, config.log_file)
    logger = get_logger("run_pipeline")

    if created:
        logger.info("created missing folders",
                    extra={"context": {"folders": [str(p) for p in created]}})

    logger.info("pipeline starting", extra={"context": {"environment": config.environment}})

    try:
        build_database.build(
            config,
            with_seed=not args.no_seed,
            with_security=args.with_security,
            with_tests=args.with_tests,
        )
        summary = build_database.verify(config)
    except Exception:
        logger.exception("pipeline failed")
        return 1

    # A non-zero exit code means a scheduler or CI job notices the failure.
    if summary.get("stock_out_of_balance"):
        logger.error("finished, but stock does not reconcile")
        return 2

    logger.info("pipeline finished successfully", extra={"context": summary})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
