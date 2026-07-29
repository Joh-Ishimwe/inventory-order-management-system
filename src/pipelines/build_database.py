"""Builds the database from the .sql files.

Every step is a file on disk rather than SQL embedded in Python, so the same
scripts can be run by hand in Workbench or reviewed on their own.
"""
from __future__ import annotations

from src.monitoring.logging import get_logger
from src.storage.mysql import MySQLClient
from src.utils.config import AppConfig
from src.utils.constants import SECURITY_FILES, SEED_FILES, SQL_BUILD_ORDER, TEST_FILES

logger = get_logger(__name__)


def build(config: AppConfig, with_seed: bool = True,
          with_security: bool = False, with_tests: bool = False) -> dict[str, int]:
    """Run the build, and optionally the seed, roles and tests.

    The first script creates the database, so this connects without selecting
    one. Otherwise a first run on a clean machine would fail before it
    started, with "unknown database".
    """
    counts = {"schema": 0, "seed": 0, "security": 0, "tests": 0}

    with MySQLClient(config, use_database=False) as client:
        logger.info("building schema", extra={"context": {"files": len(SQL_BUILD_ORDER)}})
        for path in SQL_BUILD_ORDER:
            counts["schema"] += client.run_script_file(path)

        if with_seed:
            logger.info("loading seed data")
            for path in SEED_FILES:
                counts["seed"] += client.run_script_file(path)

        if with_security:
            logger.info("creating roles and grants")
            for path in SECURITY_FILES:
                counts["security"] += client.run_script_file(path)

        if with_tests:
            logger.info("running test suites")
            for path in TEST_FILES:
                counts["tests"] += client.run_script_file(path, echo_results=True)

    logger.info("build finished", extra={"context": counts})
    return counts


def verify(config: AppConfig) -> dict[str, object]:
    """Quick health check after a build."""
    with MySQLClient(config) as client:
        summary = {
            "customers": client.query("SELECT COUNT(*) AS n FROM customers")[0]["n"],
            "products": client.query("SELECT COUNT(*) AS n FROM products")[0]["n"],
            "orders": client.query("SELECT COUNT(*) AS n FROM orders")[0]["n"],
            "order_lines": client.query("SELECT COUNT(*) AS n FROM order_details")[0]["n"],
            "ledger_entries": client.query("SELECT COUNT(*) AS n FROM inventory_logs")[0]["n"],
            "low_stock_products": client.query("SELECT COUNT(*) AS n FROM v_low_stock")[0]["n"],
        }
        # If this is anything but zero, stock changed without going through
        # record_stock_change, which is a real bug.
        unbalanced = client.query(
            "SELECT COUNT(*) AS n FROM v_stock_reconciliation WHERE is_balanced = FALSE"
        )[0]["n"]
        summary["stock_out_of_balance"] = unbalanced

    if unbalanced:
        logger.error("stock does not reconcile with the ledger",
                     extra={"context": {"products_affected": unbalanced}})
    else:
        logger.info("verification passed", extra={"context": summary})
    return summary
