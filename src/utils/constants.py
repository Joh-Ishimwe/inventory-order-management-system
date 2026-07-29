"""Fixed values shared across the project."""

# Build order matters: a table cannot reference one that does not exist yet,
# and procedures cannot be created before the tables they touch.
SQL_BUILD_ORDER = [
    "sql/schema/00_drop_all.sql",
    "sql/schema/01_create_database.sql",
    "sql/schema/02_business_rules.sql",
    "sql/schema/03_customers.sql",
    "sql/schema/04_products.sql",
    "sql/schema/05_orders.sql",
    "sql/schema/06_order_details.sql",
    "sql/schema/07_inventory_logs.sql",
    "sql/procedures/00_get_rule.sql",
    "sql/procedures/01_record_stock_change.sql",
    "sql/procedures/02_apply_order_discount.sql",
    "sql/procedures/08_recalc_order_money.sql",
    "sql/procedures/03_place_order.sql",
    "sql/procedures/04_cancel_order.sql",
    "sql/procedures/05_return_order_line.sql",
    "sql/procedures/06_replenish_stock.sql",
    "sql/procedures/07_adjust_stock.sql",
    "sql/triggers/01_order_totals.sql",
    "sql/triggers/02_orders_validation.sql",
    "sql/triggers/03_inventory_logs_append_only.sql",
    "sql/views/01_v_order_summary.sql",
    "sql/views/02_v_low_stock.sql",
    "sql/views/03_v_customer_tiers.sql",
    "sql/views/04_v_order_discounts.sql",
    "sql/views/05_v_stock_reconciliation.sql",
    "sql/views/06_v_order_line_detail.sql",
    "sql/indexes/01_indexes.sql",
]

SEED_FILES = ["sql/seed/01_sample_data.sql"]

SECURITY_FILES = ["sql/security/01_roles_and_grants.sql"]

TEST_FILES = [
    "tests/00_test_helpers.sql",
    "tests/01_test_constraints.sql",
    "tests/02_test_procedures.sql",
    "tests/03_test_reconciliation.sql",
]

# Folders the pipeline needs. Created on startup if they are not there,
# so a fresh clone runs without anyone preparing the filesystem first.
REQUIRED_DIRS = [
    "logs",
    "data/raw",
    "data/staging",
    "data/processed",
    "data/samples",
]

# Errors worth retrying: the server was busy, unreachable, or two
# transactions collided. Trying again a moment later often just works.
TRANSIENT_MYSQL_ERRORS = {
    1040,  # too many connections
    1205,  # lock wait timeout
    1213,  # deadlock
    2003,  # cannot connect
    2006,  # server gone away
    2013,  # lost connection mid-query
}

# Errors where retrying is pointless and hides the real problem.
# 1644 is our own SIGNAL, so it means a business rule said no.
PERMANENT_MYSQL_ERRORS = {
    1045,  # access denied
    1062,  # duplicate key
    1146,  # table does not exist
    1644,  # business rule rejection raised by SIGNAL
    3819,  # CHECK constraint failed
}
