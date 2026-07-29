-- Drops all tables (in reverse dependency order) so the schema can be
-- rebuilt from scratch, for a clean/repeatable test run.
USE inventory_order_management;

DROP TABLE IF EXISTS inventory_logs;
DROP TABLE IF EXISTS order_details;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;