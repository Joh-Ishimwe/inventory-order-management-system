-- Master build script. Run from the project root:
--   mysql -u root -p < sql/run_all.sql
-- or SOURCE sql/run_all.sql from an open client session.

SOURCE sql/schema/00_drop_all.sql;
SOURCE sql/schema/02_tables.sql;
SOURCE sql/schema/03_business_rules.sql;
SOURCE sql/schema/04_system_log.sql;
SOURCE sql/procedures/procedures.sql;
SOURCE sql/triggers/triggers.sql;
SOURCE sql/views/views.sql;
SOURCE sql/indexes/01_indexes.sql;
SOURCE sql/seed/01_sample_data.sql;

-- Tests aren't included: they call real procedures and leave rows behind.
-- Run separately: tests/00_test_helpers.sql, then 01, 02, 03 in order.
