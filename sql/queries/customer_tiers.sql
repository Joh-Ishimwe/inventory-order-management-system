USE inventory_order_management;

-- Customer spending tiers based on NET spending (returns deducted, cancellations
-- excluded) over the last 3 months.
--
-- ASSUMPTION (placeholder, pending real business input from product/finance):
--   Gold   >= $100 net spend in the last 3 months
--   Silver >= $50  net spend in the last 3 months
--   Bronze  < $50
-- These thresholds and the 3-month window are easy to adjust in one place below.

SELECT
    c.customer_id,
    c.name,
    ROUND(COALESCE(SUM(
        o.total_amount - IFNULL(returns.returned_value, 0)
    ), 0), 2) AS net_spent_last_3_months,
    CASE
        WHEN COALESCE(SUM(o.total_amount - IFNULL(returns.returned_value, 0)), 0) >= 100 THEN 'Gold'
        WHEN COALESCE(SUM(o.total_amount - IFNULL(returns.returned_value, 0)), 0) >= 50  THEN 'Silver'
        ELSE 'Bronze'
    END AS customer_tier
FROM customers c
LEFT JOIN orders o
    ON c.customer_id = o.customer_id
    AND o.status != 'cancelled'
    AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
LEFT JOIN (
    SELECT order_id, SUM(returned_quantity * unit_price) AS returned_value
    FROM order_details
    GROUP BY order_id
) returns ON o.order_id = returns.order_id
GROUP BY c.customer_id, c.name
ORDER BY net_spent_last_3_months DESC;