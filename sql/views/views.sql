USE inventory_order_management;

-- =============================================================================
-- v_order_summary
-- One row per order: who placed it, when, what it came to, how many lines,
-- and how much of it came back.
-- Cancelled orders are left out, since no revenue was earned.
-- =============================================================================
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
    -- A refund gives back what was actually paid for those units: the line
    -- price after its bulk discount, then after the order-level discount.
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

-- =============================================================================
-- v_low_stock
-- Products at or below their reorder point, worst first.
-- Filters on the generated is_low_stock column so an index can be used.
-- =============================================================================
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

-- =============================================================================
-- v_customer_tiers
-- Spending tier per customer, worked out live rather than stored.
--
-- Nothing is cached, so a tier can never drift out of date. It also means
-- the thresholds exist in exactly one place: the business_rules table,
-- read through get_rule().
--
-- Net spend = what was charged, minus the value of anything returned,
-- ignoring cancelled orders, over the rolling window in business_rules.
-- =============================================================================
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

-- =============================================================================
-- v_order_discounts
-- What each order was discounted, split by the two rules that can apply.
-- Reads the stored rates rather than recalculating, so historical orders keep
-- the discount they were actually charged even after the bands change.
-- =============================================================================
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
    -- The blended saving across the whole order, useful for reporting even
    -- though no single rule was set to this number.
    CASE WHEN o.subtotal_amount > 0
         THEN ROUND(1 - (o.total_amount / o.subtotal_amount), 4)
         ELSE 0 END                              AS effective_discount_rate
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status <> 'cancelled';

-- =============================================================================
-- v_stock_reconciliation
-- Health check. products.stock_quantity is a running balance;
-- inventory_logs is the ledger behind it. They must agree.
--
-- Any row where is_balanced = FALSE means something changed stock without
-- going through record_stock_change, which is a bug worth chasing.
-- =============================================================================
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

-- =============================================================================
-- v_order_line_detail
-- Line-by-line view of an order, showing the bulk discount each line earned.
-- This is where the quantity-based rule is visible: two lines of the same
-- product at different quantities get different rates.
-- =============================================================================
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

-- =============================================================================
-- v_replenishment_plan
-- What each low-stock product should be restocked by, worst first.
-- Restocks to a multiple of the reorder level rather than exactly to it, so
-- the product does not immediately reappear on the low-stock report after
-- one sale. The multiplier is a business rule, not a hardcoded number.
-- =============================================================================
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
