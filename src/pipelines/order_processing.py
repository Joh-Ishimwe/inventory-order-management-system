"""Places a batch of orders.

Each order is handled on its own. One rejected order does not stop the rest
of the batch, which is the difference between a pipeline that survives real
input and one that dies on the first surprise.
"""
from __future__ import annotations

import json
from typing import Any

from src.monitoring.logging import get_logger
from src.storage.mysql import MySQLClient, PermanentDatabaseError
from src.utils.config import AppConfig

logger = get_logger(__name__)


def process_orders(config: AppConfig, requests: list[dict[str, Any]]) -> dict[str, Any]:
    """Try to place every order in the batch, and report what happened.

    place_order itself enforces every business rule (non-empty items,
    positive quantities, active customer, product existence) via SIGNAL, so
    the only thing coerced here is customer_id, which the driver needs as
    an actual int to bind as a procedure argument.
    """
    placed: list[dict[str, Any]] = []
    failed: list[dict[str, Any]] = []

    with MySQLClient(config) as client:
        for position, request in enumerate(requests, start=1):
            try:
                customer_id = int(request.get("customer_id"))
            except (TypeError, ValueError):
                reason = f"customer_id is not valid: {request.get('customer_id')!r}"
                failed.append({"position": position, "reason": reason})
                logger.warning("order rejected before reaching the database",
                               extra={"context": {"position": position, "reason": reason}})
                continue

            payload = json.dumps(request.get("items"))
            try:
                # The procedure is one transaction, so an order either lands
                # completely or not at all. Nothing partial is left behind.
                returned = client.call_procedure(
                    "place_order",
                    [customer_id, payload, 0],
                )
                order_id = returned[2] if len(returned) > 2 else None
                placed.append({"position": position, "order_id": order_id})
                logger.info("order placed",
                            extra={"context": {"position": position, "order_id": order_id}})

            except PermanentDatabaseError as exc:
                # A business rule said no: not enough stock, inactive
                # customer, unknown product. Record it and move on.
                failed.append({"position": position, "reason": str(exc)})
                logger.warning("order refused by the database",
                               extra={"context": {"position": position, "detail": str(exc)}})

            except Exception as exc:  # noqa: BLE001
                failed.append({"position": position, "reason": str(exc)})
                logger.exception("unexpected failure placing an order",
                                 extra={"context": {"position": position}})

    outcome = {"submitted": len(requests), "placed": len(placed), "failed": len(failed),
               "placed_detail": placed, "failed_detail": failed}
    logger.info("order batch finished",
                extra={"context": {k: outcome[k] for k in ("submitted", "placed", "failed")}})
    return outcome
