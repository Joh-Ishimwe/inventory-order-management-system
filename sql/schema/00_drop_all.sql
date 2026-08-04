-- Drops all schema objects (views, triggers, procedures, tables) for a clean rebuild.
CREATE DATABASE IF NOT EXISTS inventory_order_management
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE inventory_order_management;

DROP VIEW IF EXISTS v_order_line_detail;
DROP VIEW IF EXISTS v_stock_reconciliation;
DROP VIEW IF EXISTS v_order_discounts;
DROP VIEW IF EXISTS v_customer_tiers;
DROP VIEW IF EXISTS v_low_stock;
DROP VIEW IF EXISTS v_order_summary;

DROP EVENT IF EXISTS evt_daily_tier_reconciliation;

DROP TRIGGER IF EXISTS trg_inventory_logs_no_update;
DROP TRIGGER IF EXISTS trg_inventory_logs_no_delete;
DROP TRIGGER IF EXISTS trg_orders_status_transition;
DROP TRIGGER IF EXISTS trg_orders_before_insert;
DROP TRIGGER IF EXISTS trg_order_details_before_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_update;
DROP TRIGGER IF EXISTS trg_order_details_after_delete;

DROP PROCEDURE IF EXISTS place_order;
DROP PROCEDURE IF EXISTS cancel_order;
DROP PROCEDURE IF EXISTS return_order_line;
DROP PROCEDURE IF EXISTS replenish_stock;
DROP PROCEDURE IF EXISTS adjust_stock;
DROP PROCEDURE IF EXISTS record_stock_change;
DROP PROCEDURE IF EXISTS apply_order_discount;
DROP PROCEDURE IF EXISTS recalc_order_money;
DROP PROCEDURE IF EXISTS assert_equals;

DROP FUNCTION IF EXISTS get_rule;


DROP TABLE IF EXISTS inventory_logs;
DROP TABLE IF EXISTS order_details;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS business_rules;
