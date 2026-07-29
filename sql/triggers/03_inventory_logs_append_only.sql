USE inventory_order_management;

DROP TRIGGER IF EXISTS trg_inventory_logs_no_update;
DROP TRIGGER IF EXISTS trg_inventory_logs_no_delete;

DELIMITER $$
-- An audit trail that can be edited is not an audit trail. These make the
-- ledger genuinely append-only instead of only append-only by convention.
-- To correct a mistake, add a balancing ADJUSTMENT row.

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
