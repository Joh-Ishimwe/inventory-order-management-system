-- Indexes supporting the app's actual query patterns.
USE inventory_order_management;

-- Foreign key columns already have an auto-created index, so they're skipped here.

-- Reports filter on status constantly.
CREATE INDEX idx_orders_status ON orders(status);

-- "This customer's orders in the last N months" reads both columns.
CREATE INDEX idx_orders_customer_placed ON orders(customer_id, placed_at);

-- Date-range reporting across all customers.
CREATE INDEX idx_orders_placed_at ON orders(placed_at);

-- Makes the low-stock view an index lookup rather than a full scan.
CREATE INDEX idx_products_low_stock ON products(is_low_stock);

-- Browsing the catalogue by category.
CREATE INDEX idx_products_category ON products(category);

-- Audit history for one product over a date range.
CREATE INDEX idx_logs_product_changed ON inventory_logs(product_id, changed_at);

-- v_recent_system_errors filters on level and a date range; v_system_log_summary groups by source.
CREATE INDEX idx_system_logs_level_logged ON system_logs(log_level, logged_at);
CREATE INDEX idx_system_logs_source ON system_logs(source);
