USE inventory_order_management;

DROP PROCEDURE IF EXISTS apply_order_discount;

DELIMITER $$
-- Sets the order-value discount, on top of whatever bulk discounts the
-- individual lines already earned. Called once when the order is placed, so
-- the rate is frozen at that moment.
--
-- The band is judged on the amount after bulk discounts, not the list price,
-- so the two rules do not compound into more than intended.
CREATE PROCEDURE apply_order_discount(IN p_order_id INT)
BEGIN
    DECLARE v_after_bulk DECIMAL(10,2);
    DECLARE v_rate       DECIMAL(5,4) DEFAULT 0;

    SELECT ROUND(COALESCE(SUM(ROUND(quantity * unit_price * (1 - discount_rate), 2)), 0), 2)
      INTO v_after_bulk
    FROM order_details WHERE order_id = p_order_id;

    IF v_after_bulk >= get_rule('spend_t2_min') THEN
        SET v_rate = get_rule('spend_t2_rate');
    ELSEIF v_after_bulk >= get_rule('spend_t1_min') THEN
        SET v_rate = get_rule('spend_t1_rate');
    END IF;

    UPDATE orders
       SET order_discount_rate   = v_rate,
           order_discount_amount = ROUND(v_after_bulk * v_rate, 2),
           total_amount          = ROUND(v_after_bulk * (1 - v_rate), 2)
     WHERE order_id = p_order_id;
END$$
DELIMITER ;
