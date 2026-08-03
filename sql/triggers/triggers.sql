USE inventory_order_management;

-- =============================================================================
-- order_details triggers
-- =============================================================================
DROP TRIGGER IF EXISTS trg_order_details_before_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_update;
DROP TRIGGER IF EXISTS trg_order_details_after_delete;

DELIMITER $$

-- Sets the bulk discount for a line from how many units it is for.
-- Doing it in a trigger means the rule holds however the line was created:
-- through place_order, through the seed script, or by hand.
--
-- Only on insert, never on update, so the rate a line was created with is
-- the rate it keeps. Editing an old order must not reprice it against
-- today's bands.
CREATE TRIGGER trg_order_details_before_insert
BEFORE INSERT ON order_details
FOR EACH ROW
BEGIN
    -- A rate passed in explicitly wins, for a manual override or a migration.
    IF NEW.discount_rate = 0 THEN
        IF NEW.quantity >= get_rule('bulk_t3_min_units') THEN
            SET NEW.discount_rate = get_rule('bulk_t3_rate');
        ELSEIF NEW.quantity >= get_rule('bulk_t2_min_units') THEN
            SET NEW.discount_rate = get_rule('bulk_t2_rate');
        ELSEIF NEW.quantity >= get_rule('bulk_t1_min_units') THEN
            SET NEW.discount_rate = get_rule('bulk_t1_rate');
        END IF;
    END IF;
END$$

-- The next three keep the order header in step with its lines, so the two
-- can never disagree.
--
-- They reuse order_discount_rate as already stored rather than recalculating
-- it, for the same reason as above: the rate is frozen at placement.

CREATE TRIGGER trg_order_details_after_insert
AFTER INSERT ON order_details
FOR EACH ROW
BEGIN
    CALL recalc_order_money(NEW.order_id);
END$$

CREATE TRIGGER trg_order_details_after_update
AFTER UPDATE ON order_details
FOR EACH ROW
BEGIN
    CALL recalc_order_money(NEW.order_id);
END$$

CREATE TRIGGER trg_order_details_after_delete
AFTER DELETE ON order_details
FOR EACH ROW
BEGIN
    CALL recalc_order_money(OLD.order_id);
END$$
DELIMITER ;

-- =============================================================================
-- orders triggers
-- =============================================================================
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

-- =============================================================================
-- inventory_logs triggers
-- An audit trail that can be edited is not an audit trail. These make the
-- ledger genuinely append-only instead of only append-only by convention.
-- To correct a mistake, add a balancing ADJUSTMENT row.
-- =============================================================================
DROP TRIGGER IF EXISTS trg_inventory_logs_no_update;
DROP TRIGGER IF EXISTS trg_inventory_logs_no_delete;

DELIMITER $$
CREATE TRIGGER trg_inventory_logs_no_update
BEFORE UPDATE ON inventory_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'inventory_logs is append-only: post a correcting ADJUSTMENT instead';
END$$

CREATE TRIGGER trg_inventory_logs_no_delete
BEFORE DELETE ON inventory_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'inventory_logs is append-only: rows cannot be deleted';
END$$
DELIMITER ;
