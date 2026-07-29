"""Record-level validation.

Checked before anything reaches the database, so a bad row is reported
clearly instead of arriving as a constraint violation later.
"""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any


@dataclass
class ValidationResult:
    is_valid: bool
    errors: list[str]
    cleaned: dict[str, Any] | None = None


def validate_product_row(row: dict[str, Any]) -> ValidationResult:
    """Check and tidy one incoming product record."""
    errors: list[str] = []
    cleaned: dict[str, Any] = {}

    name = (row.get("name") or "").strip()
    if not name:
        errors.append("name is required")
    elif len(name) > 150:
        errors.append("name is longer than 150 characters")
    cleaned["name"] = name

    category = (row.get("category") or "").strip() or None
    if category and len(category) > 50:
        errors.append("category is longer than 50 characters")
    cleaned["category"] = category

    # Decimal, not float. Float arithmetic drifts by tiny amounts, which is
    # unacceptable for money.
    try:
        price = Decimal(str(row.get("price", "")).strip())
        if price < 0:
            errors.append("price cannot be negative")
        cleaned["price"] = price
    except (InvalidOperation, ValueError):
        errors.append(f"price is not a number: {row.get('price')!r}")

    for field in ("stock_quantity", "reorder_level"):
        try:
            value = int(str(row.get(field, "0")).strip() or 0)
            if value < 0:
                errors.append(f"{field} cannot be negative")
            cleaned[field] = value
        except ValueError:
            errors.append(f"{field} is not a whole number: {row.get(field)!r}")

    return ValidationResult(not errors, errors, cleaned if not errors else None)


def validate_order_request(request: dict[str, Any]) -> ValidationResult:
    """Check one order request before it is sent to place_order."""
    errors: list[str] = []

    try:
        customer_id = int(request.get("customer_id"))
        if customer_id <= 0:
            errors.append("customer_id must be a positive whole number")
    except (TypeError, ValueError):
        errors.append(f"customer_id is not valid: {request.get('customer_id')!r}")
        customer_id = None

    items = request.get("items")
    if not isinstance(items, list) or not items:
        errors.append("items must be a non-empty list")
        items = []

    cleaned_items: list[dict[str, int]] = []
    for position, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            errors.append(f"item {position} is not an object")
            continue
        try:
            product_id = int(item.get("product_id"))
            quantity = int(item.get("quantity"))
        except (TypeError, ValueError):
            errors.append(f"item {position} has a non-numeric product_id or quantity")
            continue
        if product_id <= 0:
            errors.append(f"item {position} has an invalid product_id")
        if quantity <= 0:
            errors.append(f"item {position} has a quantity of {quantity}")
        if product_id > 0 and quantity > 0:
            cleaned_items.append({"product_id": product_id, "quantity": quantity})

    if errors:
        return ValidationResult(False, errors)
    return ValidationResult(True, [], {"customer_id": customer_id, "items": cleaned_items})
