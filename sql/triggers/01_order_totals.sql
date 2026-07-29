USE inventory_order_management;

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
