USE inventory_order_management;

-- Spending tier per customer, worked out live rather than stored.
--
-- Nothing is cached, so a tier can never drift out of date. It also means
-- the thresholds exist in exactly one place: the business_rules table,
-- read through get_rule().
--
-- Net spend = what was charged, minus the value of anything returned,
-- ignoring cancelled orders, over the rolling window in business_rules.
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
