USE inventory_order_management;

-- One row per order: who placed it, when, what it came to, how many lines,
-- and how much of it came back.
-- Cancelled orders are left out, since no revenue was earned.
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
