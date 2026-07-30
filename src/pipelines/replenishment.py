"""Finds products below their reorder point and tops them up.

Deliberately not automatic. Reordering spends money, so the default is to
report what needs attention. Actually placing the restock is an explicit
choice, made by passing apply=True.
"""
from __future__ import annotations

from typing import Any

from src.monitoring.logging import get_logger
from src.storage.mysql import MySQLClient, PermanentDatabaseError
from src.utils.config import AppConfig

logger = get_logger(__name__)


def find_low_stock(config: AppConfig) -> list[dict[str, Any]]:
    with MySQLClient(config) as client:
        rows = client.query(
            "SELECT product_id, name, stock_quantity, reorder_level, "
            "units_below_reorder_point, severity "
            "FROM v_low_stock ORDER BY severity DESC, stock_quantity ASC"
        )
    logger.info("low stock scan complete", extra={"context": {"products_found": len(rows)}})
    return rows


def replenish(config: AppConfig, buffer_multiplier: float = 2.0,
              apply: bool = False) -> dict[str, Any]:
    """Work out a restock quantity per low product, and optionally apply it.

    The suggested amount brings stock up to a multiple of the reorder level
    rather than exactly to it, so the product does not immediately reappear
    on the low-stock report after one sale.
    """
    candidates = find_low_stock(config)
    plan = []
    for row in candidates:
        target = int(round(row["reorder_level"] * buffer_multiplier))
        quantity = max(target - row["stock_quantity"], 1)
        plan.append({"product_id": row["product_id"], "name": row["name"],
                     "current": row["stock_quantity"], "restock_by": quantity})

    if not apply:
        logger.info("replenishment plan prepared, not applied",
                    extra={"context": {"products": len(plan)}})
        return {"applied": False, "plan": plan}

    if not plan:
        logger.info("nothing below reorder point, nothing to apply")
        return {"applied": False, "reason": "nothing below reorder point",
                 "succeeded": [], "failed": []}

    applied, failed = [], []
    with MySQLClient(config) as client:
        for item in plan:
            try:
                client.call_procedure(
                    "replenish_stock",
                    [item["product_id"], item["restock_by"], "Automated replenishment run"],
                )
                applied.append(item)
                logger.info("stock replenished", extra={"context": item})
            except PermanentDatabaseError as exc:
                failed.append({**item, "reason": str(exc)})
                logger.warning("replenishment refused",
                               extra={"context": {**item, "detail": str(exc)}})

    return {"applied": True, "succeeded": applied, "failed": failed}
