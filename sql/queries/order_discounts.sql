USE inventory_order_management;

-- Discount is based on the ORDER's total spending amount (not per-product
-- quantity), reflecting a "spend more, save more" policy.
--
-- ASSUMPTION (placeholder, pending real business input):
--   Orders >= $100  → 10% discount
--   Orders >= $50   → 5% discount
--   Orders < $50    → no discount

SELECT
    o.order_id,
    c.name AS customer_name,
    ROUND(o.total_amount, 2) AS order_total,
    CASE
        WHEN o.total_amount >= 100 THEN 0.10
        WHEN o.total_amount >= 50  THEN 0.05
        ELSE 0
    END AS discount_rate,
    ROUND(
        o.total_amount * (1 - 
            CASE
                WHEN o.total_amount >= 100 THEN 0.10
                WHEN o.total_amount >= 50  THEN 0.05
                ELSE 0
            END
        ), 2
    ) AS discounted_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.status != 'cancelled'
ORDER BY o.total_amount DESC;