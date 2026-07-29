USE inventory_order_management;

-- Only columns that real queries filter, join or sort on are indexed.
-- Indexes make reads faster but writes slower, so extra ones are a cost.
--
-- Note on what is NOT here: MySQL creates an index automatically for every
-- foreign key column, so orders.customer_id, order_details.order_id,
-- order_details.product_id and inventory_logs.product_id are already
-- covered. Adding them again would just duplicate work.

-- Reports filter on status constantly.
CREATE INDEX idx_orders_status ON orders(status);

-- "This customer's orders in the last N months" reads both columns.
-- Leftmost-prefix rule: this also serves a customer_id-only lookup,
-- but not a date-only lookup.
CREATE INDEX idx_orders_customer_placed ON orders(customer_id, placed_at);

-- Date-range reporting across all customers. On placed_at, since the day-level
-- order_date is derived in the views rather than stored.
CREATE INDEX idx_orders_placed_at ON orders(placed_at);

-- Makes the low-stock view an index lookup rather than a full scan.
CREATE INDEX idx_products_low_stock ON products(is_low_stock);

-- Browsing the catalogue by category.
CREATE INDEX idx_products_category ON products(category);

-- Audit history for one product over a date range. product_id is already
-- indexed by its foreign key, but adding changed_at lets the range filter
-- use the same index instead of sorting afterwards.
CREATE INDEX idx_logs_product_changed ON inventory_logs(product_id, changed_at);
