USE inventory_order_management;

-- v_order_summary: one row per order — who, when, total, line count, and returns; cancelled orders are excluded.
CREATE OR REPLACE VIEW v_order_summary AS
SELECT
    o.order_id,
    c.customer_id,
    c.name                                  AS customer_name,
    c.is_active                             AS customer_is_active,
    DATE(o.placed_at)                       AS order_date,
    o.status,
    o.subtotal_amount                       AS list_price_total,
    o.bulk_discount_amount,
    o.order_discount_rate,
    o.order_discount_amount,
    o.total_amount                          AS charged_amount,
    COUNT(od.order_detail_id)               AS number_of_lines,
    COALESCE(SUM(od.quantity), 0)           AS units_ordered,
    COALESCE(SUM(od.returned_quantity), 0)  AS units_returned,
    -- A refund gives back what was actually paid: the line price after its bulk discount, then the order-level discount.
    ROUND(COALESCE(SUM(
        ROUND(od.returned_quantity * od.unit_price * (1 - od.discount_rate), 2)
    ), 0) * (1 - o.order_discount_rate), 2) AS refunded_amount,
    ROUND(o.total_amount - COALESCE(SUM(
        ROUND(od.returned_quantity * od.unit_price * (1 - od.discount_rate), 2)
    ), 0) * (1 - o.order_discount_rate), 2) AS net_amount
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
LEFT JOIN order_details od ON od.order_id = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY o.order_id, c.customer_id, c.name, c.is_active,
         o.placed_at, o.status, o.subtotal_amount, o.bulk_discount_amount,
         o.order_discount_rate, o.order_discount_amount, o.total_amount;

-- v_low_stock: products at or below their reorder point, filtered on the generated is_low_stock column so an index can be used.
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    product_id,
    name,
    category,
    stock_quantity,
    reorder_level,
    GREATEST(reorder_level - stock_quantity, 0) AS units_below_reorder_point,
    CASE WHEN stock_quantity = 0 THEN 'OUT_OF_STOCK' ELSE 'LOW' END AS severity
FROM products
WHERE is_low_stock = TRUE;

-- v_customer_tiers: spending tier per customer, computed live from business_rules (via get_rule())
-- so nothing drifts out of date; net spend = charged minus returns, over the rolling window, excluding cancellations.
CREATE OR REPLACE VIEW v_customer_tiers AS
SELECT
    c.customer_id,
    c.name,
    c.is_active,
    ROUND(COALESCE(SUM(s.net_amount), 0), 2) AS net_spend_in_window,
    COUNT(s.order_id)                        AS orders_in_window,
    CASE
        WHEN COALESCE(SUM(s.net_amount), 0) >= get_rule('tier_gold_min')   THEN 'Gold'
        WHEN COALESCE(SUM(s.net_amount), 0) >= get_rule('tier_silver_min') THEN 'Silver'
        ELSE 'Bronze'
    END                                      AS customer_tier
FROM customers c
LEFT JOIN v_order_summary s
       ON s.customer_id = c.customer_id
      AND s.order_date >= DATE_SUB(CURDATE(),
              INTERVAL CAST(get_rule('tier_window_months') AS SIGNED) MONTH)
GROUP BY c.customer_id, c.name, c.is_active;

-- v_order_discounts: each order's discount split by the two rules, reading stored rates so historical orders keep what they were actually charged.
CREATE OR REPLACE VIEW v_order_discounts AS
SELECT
    o.order_id,
    c.name                                       AS customer_name,
    DATE(o.placed_at)                            AS order_date,
    o.subtotal_amount                            AS list_price_total,
    -- Earned by buying units in quantity, per line.
    o.bulk_discount_amount,
    -- Earned by the value of the whole order, applied after the bulk one.
    o.order_discount_rate,
    o.order_discount_amount,
    ROUND(o.bulk_discount_amount + o.order_discount_amount, 2) AS total_discount,
    o.total_amount                               AS charged_amount,
    -- The blended saving across the whole order, useful for reporting even though no single rule set this number.
    CASE WHEN o.subtotal_amount > 0
         THEN ROUND(1 - (o.total_amount / o.subtotal_amount), 4)
         ELSE 0 END                              AS effective_discount_rate
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status <> 'cancelled';

-- v_stock_reconciliation: health check comparing products.stock_quantity against the inventory_logs ledger;
-- any is_balanced = FALSE row means something bypassed record_stock_change.
CREATE OR REPLACE VIEW v_stock_reconciliation AS
SELECT
    p.product_id,
    p.name,
    p.stock_quantity                              AS balance_on_product,
    COALESCE(SUM(l.change_amount), 0)             AS sum_of_ledger,
    p.stock_quantity - COALESCE(SUM(l.change_amount), 0) AS difference,
    (p.stock_quantity = COALESCE(SUM(l.change_amount), 0)) AS is_balanced
FROM products p
LEFT JOIN inventory_logs l ON l.product_id = p.product_id
GROUP BY p.product_id, p.name, p.stock_quantity;

-- v_order_line_detail: line-by-line view of an order showing each line's bulk discount, where the
-- quantity-based rule becomes visible (same product, different quantities, different rates).
CREATE OR REPLACE VIEW v_order_line_detail AS
SELECT
    od.order_detail_id,
    od.order_id,
    DATE(o.placed_at)                                        AS order_date,
    p.product_id,
    p.name                                                   AS product_name,
    p.category,
    od.quantity,
    od.unit_price,
    ROUND(od.quantity * od.unit_price, 2)                    AS line_list_price,
    od.discount_rate                                         AS bulk_discount_rate,
    ROUND(od.quantity * od.unit_price * od.discount_rate, 2)  AS bulk_discount_amount,
    ROUND(od.quantity * od.unit_price * (1 - od.discount_rate), 2) AS line_after_bulk,
    od.returned_quantity,
    od.return_date
FROM order_details od
JOIN orders   o ON o.order_id   = od.order_id
JOIN products p ON p.product_id = od.product_id;

-- v_recent_system_errors: ERROR-level entries from the last 7 days, newest first --
-- the first place to look when something reports a failure.
CREATE OR REPLACE VIEW v_recent_system_errors AS
SELECT log_id, source, message, error_code, context, logged_at
FROM system_logs
WHERE log_level = 'ERROR'
  AND logged_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
ORDER BY logged_at DESC;

-- v_system_log_summary: event counts by day/source/level, to spot a source suddenly
-- erroring more than usual rather than reading rows one at a time.
CREATE OR REPLACE VIEW v_system_log_summary AS
SELECT
    DATE(logged_at) AS log_date,
    source,
    log_level,
    COUNT(*) AS event_count
FROM system_logs
GROUP BY DATE(logged_at), source, log_level;

-- v_replenishment_plan: how much each low-stock product should be restocked by, to a multiple of the
-- reorder level (via the replenishment_buffer_multiplier rule) so it doesn't reappear after one sale.
CREATE OR REPLACE VIEW v_replenishment_plan AS
SELECT
    product_id,
    name,
    category,
    stock_quantity,
    reorder_level,
    severity,
    GREATEST(
        ROUND(reorder_level * get_rule('replenishment_buffer_multiplier')) - stock_quantity,
        1
    ) AS restock_by
FROM v_low_stock;
