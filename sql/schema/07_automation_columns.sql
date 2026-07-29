-- sql/schema/07_automation_columns.sql
USE inventory_order_management;

ALTER TABLE customers
ADD COLUMN customer_tier VARCHAR(20) NOT NULL DEFAULT 'Bronze';