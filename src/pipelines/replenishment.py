"""Finds products below their reorder point and tops them up.

Deliberately not automatic. Reordering spends money, so the default is to
report what needs attention. Actually placing the restock is an explicit
choice, made by passing apply=True.

The restock math (buffer multiplier, target quantity) and the per-product
apply-and-continue-on-failure loop both live in SQL now
(v_replenishment_plan, replenish_all) rather than in this file. Python's
job is just to call one of the two and hand back what the database says.
"""
from __future__ import annotations

from typing import Any

from src.monitoring.logging import get_logger
from src.storage.mysql import MySQLClient
from src.utils.config import AppConfig

logger = get_logger(__name__)

_RESULT_COLUMNS = ("product_id", "name", "previous_stock", "restocked_by", "status", "detail")


def find_low_stock(config: AppConfig) -> list[dict[str, Any]]:
    with MySQLClient(config) as client:
        rows = client.query(
            "SELECT product_id, name, stock_quantity, reorder_level, severity, restock_by "
            "FROM v_replenishment_plan ORDER BY severity DESC, stock_quantity ASC"
        )
    logger.info("low stock scan complete", extra={"context": {"products_found": len(rows)}})
    return rows


def replenish(config: AppConfig, note: str = "Automated replenishment run",
              apply: bool = False) -> dict[str, Any]:
    """Report the restock plan, or apply it, all computed by replenish_all."""
    plan = find_low_stock(config)

    if not apply:
        logger.info("replenishment plan prepared, not applied",
                    extra={"context": {"products": len(plan)}})
        return {"applied": False, "plan": plan}

    if not plan:
        logger.info("nothing below reorder point, nothing to apply")
        return {"applied": False, "reason": "nothing below reorder point",
                "succeeded": [], "failed": []}

    with MySQLClient(config) as client:
        result_sets = client.execute("CALL replenish_all(%s)", (note,), collect=True)

    rows = result_sets[-1] if result_sets else []
    results = [dict(zip(_RESULT_COLUMNS, row)) for row in rows]
    succeeded = [r for r in results if r["status"] == "OK"]
    failed = [r for r in results if r["status"] == "FAILED"]

    for item in succeeded:
        logger.info("stock replenished", extra={"context": item})
    for item in failed:
        logger.warning("replenishment refused", extra={"context": item})

    return {"applied": True, "succeeded": succeeded, "failed": failed}
