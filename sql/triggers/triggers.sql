USE inventory_order_management;

-- order_details triggers
DROP TRIGGER IF EXISTS trg_order_details_before_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_insert;
DROP TRIGGER IF EXISTS trg_order_details_after_update;
DROP TRIGGER IF EXISTS trg_order_details_after_delete;

DELIMITER $$

-- Sets the bulk discount for a line from its quantity, on insert only, so an old line keeps
-- the rate it was created with and editing an order never reprices it against today's bands.
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

-- The next three keep the order header in step with its lines, reusing the stored
-- order_discount_rate rather than recalculating it, since the rate is frozen at placement.

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

-- orders triggers
DROP TRIGGER IF EXISTS trg_orders_before_insert;
DROP TRIGGER IF EXISTS trg_orders_status_transition;

DELIMITER $$
-- CHECK constraints cannot call CURDATE(), so a future-dated order has to be caught here instead.
CREATE TRIGGER trg_orders_before_insert
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.placed_at > NOW() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'An order cannot be placed in the future';
    END IF;
END$$

-- Stops an order sliding backwards through its lifecycle (e.g. delivered -> pending).
-- Allowed moves: pending -> shipped/cancelled, shipped -> delivered/cancelled, delivered -> returned.
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

-- inventory_logs triggers: make the ledger genuinely append-only; to correct a mistake, add a balancing ADJUSTMENT row.
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
