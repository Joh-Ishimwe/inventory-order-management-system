USE inventory_order_management;

DROP PROCEDURE IF EXISTS recalc_order_money;

DELIMITER $$
-- Rebuilds an order's money columns from its current line items.
--
-- It exists as a procedure so the three order_details triggers share one copy
-- of this arithmetic instead of holding three copies that could drift apart.
--
-- Reuses order_discount_rate as already stored rather than recalculating it,
-- so editing a line on an old order does not reprice it against today's
-- bands. Only apply_order_discount sets that rate, once, at placement.
CREATE PROCEDURE recalc_order_money(IN p_order_id INT)
BEGIN
    DECLARE v_gross      DECIMAL(10,2);
    DECLARE v_after_bulk DECIMAL(10,2);
    DECLARE v_rate       DECIMAL(5,4);

    -- Gross is list price. After-bulk applies each line's own rate and rounds
    -- per line, which is how an invoice would show it.
    SELECT ROUND(COALESCE(SUM(quantity * unit_price), 0), 2),
           ROUND(COALESCE(SUM(ROUND(quantity * unit_price * (1 - discount_rate), 2)), 0), 2)
      INTO v_gross, v_after_bulk
    FROM order_details WHERE order_id = p_order_id;

    SELECT order_discount_rate INTO v_rate FROM orders WHERE order_id = p_order_id;

    UPDATE orders
       SET subtotal_amount       = v_gross,
           bulk_discount_amount  = ROUND(v_gross - v_after_bulk, 2),
           order_discount_amount = ROUND(v_after_bulk * v_rate, 2),
           total_amount          = ROUND(v_after_bulk * (1 - v_rate), 2)
     WHERE order_id = p_order_id;
END$$
DELIMITER ;
