-- sql/queries/tier_reconciliation.sql
USE inventory_order_management;

DELIMITER $$

-- Recalculates EVERY customer's tier from scratch. Needed because tier
-- depends on a rolling 3-month window; a customer's tier can go stale
-- purely from time passing, with no order event to trigger a recheck.
CREATE PROCEDURE recalculate_all_tiers()
BEGIN
    UPDATE customers c
    LEFT JOIN (
        SELECT o.customer_id,
               ROUND(COALESCE(SUM(o.total_amount - IFNULL(r.returned_value, 0)), 0), 2) AS net_spent
        FROM orders o
        LEFT JOIN (
            SELECT order_id, SUM(returned_quantity * unit_price) AS returned_value
            FROM order_details
            GROUP BY order_id
        ) r ON o.order_id = r.order_id
        WHERE o.status != 'cancelled'
          AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
        GROUP BY o.customer_id
    ) spending ON c.customer_id = spending.customer_id
    SET c.customer_tier = CASE
        WHEN COALESCE(spending.net_spent, 0) >= 100 THEN 'Gold'
        WHEN COALESCE(spending.net_spent, 0) >= 50  THEN 'Silver'
        ELSE 'Bronze'
    END;
END$$

DELIMITER ;

-- Runs recalculate_all_tiers() automatically every day at 1 AM.
CREATE EVENT IF NOT EXISTS evt_daily_tier_reconciliation
ON SCHEDULE EVERY 1 DAY STARTS (CURRENT_DATE + INTERVAL 1 DAY + INTERVAL 1 HOUR)
DO CALL recalculate_all_tiers();