USE inventory_order_management;

DROP TRIGGER IF EXISTS trg_orders_before_insert;
DROP TRIGGER IF EXISTS trg_orders_status_transition;

DELIMITER $$
-- CHECK constraints cannot call CURDATE(), so a future-dated order has to
-- be caught here instead.
CREATE TRIGGER trg_orders_before_insert
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.placed_at > NOW() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'An order cannot be placed in the future';
    END IF;
END$$

-- Stops an order sliding backwards through its lifecycle, for example a
-- delivered order being flipped back to pending.
--
-- Allowed moves:
--   pending   -> shipped, cancelled
--   shipped   -> delivered, cancelled
--   delivered -> returned
--   cancelled and returned are final
CREATE TRIGGER trg_orders_status_transition
BEFORE UPDATE ON orders
FOR EACH ROW
BEGIN
    DECLARE v_msg VARCHAR(255);

    IF NEW.status <> OLD.status THEN
        IF NOT (
               (OLD.status = 'pending'   AND NEW.status IN ('shipped','cancelled'))
            OR (OLD.status = 'shipped'   AND NEW.status IN ('delivered','cancelled'))
            OR (OLD.status = 'delivered' AND NEW.status = 'returned')
        ) THEN
            SET v_msg = CONCAT('Status cannot go from ', OLD.status, ' to ', NEW.status);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;
    END IF;
END$$
DELIMITER ;
