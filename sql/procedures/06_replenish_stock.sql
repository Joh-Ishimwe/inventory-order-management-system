USE inventory_order_management;

DROP PROCEDURE IF EXISTS replenish_stock;

DELIMITER $$
-- Adds stock from a supplier delivery.
--
-- The quantity check matters more than it looks. Procedures run with the
-- privileges of whoever created them, so an account that only has EXECUTE
-- on this one procedure is borrowing admin rights while inside it. Without
-- this check, that account could pass a negative number and quietly drain
-- stock while it was logged as a delivery.
CREATE PROCEDURE replenish_stock(
    IN p_product_id INT,
    IN p_quantity   INT,
    IN p_note       VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Replenishment quantity must be above zero';
    END IF;

    START TRANSACTION;
    CALL record_stock_change(p_product_id, p_quantity, 'REPLENISHMENT', NULL, p_note);
    COMMIT;
END$$
DELIMITER ;
