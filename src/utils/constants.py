"""Fixed values shared across the project."""

# Build order matters: a table cannot reference one that does not exist yet,
# and procedures cannot be created before the tables they touch.
SQL_BUILD_ORDER = [
    "sql/schema/00_drop_all.sql",
    "sql/schema/01_create_database.sql",
    "sql/schema/02_business_rules.sql",
    "sql/schema/03_tables.sql",
    "sql/procedures/procedures.sql",
    "sql/triggers/triggers.sql",
    "sql/views/views.sql",
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
