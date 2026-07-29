-- sql/queries/automation_triggers.sql
USE inventory_order_management;

DELIMITER $$

-- Recalculates the parent order's total whenever its line items change.
CREATE TRIGGER trg_order_details_recalc_total_insert
AFTER INSERT ON order_details
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = (
        SELECT ROUND(SUM(quantity * unit_price), 2)
        FROM order_details
        WHERE order_id = NEW.order_id
    )
    WHERE order_id = NEW.order_id;
END$$

CREATE TRIGGER trg_order_details_recalc_total_update
AFTER UPDATE ON order_details
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = (
        SELECT ROUND(SUM(quantity * unit_price), 2)
        FROM order_details
        WHERE order_id = NEW.order_id
    )
    WHERE order_id = NEW.order_id;
END$$

CREATE TRIGGER trg_order_details_recalc_total_delete
AFTER DELETE ON order_details
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = (
        SELECT ROUND(COALESCE(SUM(quantity * unit_price), 0), 2)
        FROM order_details
        WHERE order_id = OLD.order_id
    )
    WHERE order_id = OLD.order_id;
END$$

-- Recalculates the customer's tier whenever one of their orders changes
-- (new order, status change, or total_amount change from the trigger above).
CREATE TRIGGER trg_orders_recalc_tier
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    DECLARE v_net DECIMAL(10,2);

    SELECT ROUND(COALESCE(SUM(
        o.total_amount - IFNULL(r.returned_value, 0)
    ), 0), 2) INTO v_net
    FROM orders o
    LEFT JOIN (
        SELECT order_id, SUM(returned_quantity * unit_price) AS returned_value
        FROM order_details
        GROUP BY order_id
    ) r ON o.order_id = r.order_id
    WHERE o.customer_id = NEW.customer_id
      AND o.status != 'cancelled'
      AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH);

    UPDATE customers
    SET customer_tier = CASE
        WHEN v_net >= 100 THEN 'Gold'
        WHEN v_net >= 50  THEN 'Silver'
        ELSE 'Bronze'
    END
    WHERE customer_id = NEW.customer_id;
END$$

-- Same recalculation on brand-new orders (order created directly, not via
-- order_details changes).
CREATE TRIGGER trg_orders_recalc_tier_insert
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
    DECLARE v_net DECIMAL(10,2);

    SELECT ROUND(COALESCE(SUM(
        o.total_amount - IFNULL(r.returned_value, 0)
    ), 0), 2) INTO v_net
    FROM orders o
    LEFT JOIN (
        SELECT order_id, SUM(returned_quantity * unit_price) AS returned_value
        FROM order_details
        GROUP BY order_id
    ) r ON o.order_id = r.order_id
    WHERE o.customer_id = NEW.customer_id
      AND o.status != 'cancelled'
      AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH);

    UPDATE customers
    SET customer_tier = CASE
        WHEN v_net >= 100 THEN 'Gold'
        WHEN v_net >= 50  THEN 'Silver'
        ELSE 'Bronze'
    END
    WHERE customer_id = NEW.customer_id;
END$$

DELIMITER ;