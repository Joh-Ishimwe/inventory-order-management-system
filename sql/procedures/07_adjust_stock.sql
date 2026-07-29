USE inventory_order_management;

DROP PROCEDURE IF EXISTS adjust_stock;

DELIMITER $$
-- Corrects stock after a stocktake, breakage or write-off. Can go either
-- way, so a reason note is required rather than optional.
CREATE PROCEDURE adjust_stock(
    IN p_product_id    INT,
    IN p_change_amount INT,
    IN p_note          VARCHAR(255)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_note IS NULL OR TRIM(p_note) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Adjustments must say why, for the audit trail';
    END IF;

    START TRANSACTION;
    CALL record_stock_change(p_product_id, p_change_amount, 'ADJUSTMENT', NULL, p_note);
    COMMIT;
END$$
DELIMITER ;
