USE inventory_order_management;

DROP PROCEDURE IF EXISTS record_stock_change;

DELIMITER $$
-- The single owner of stock movement. Nothing else may touch
-- products.stock_quantity, which is what keeps the balance and the ledger
-- from drifting apart.
--
-- Deliberately has no COMMIT: it must be callable inside a bigger
-- transaction without ending it early.
CREATE PROCEDURE record_stock_change(
    IN p_product_id    INT,
    IN p_change_amount INT,
    IN p_reason        VARCHAR(20),
    IN p_order_id      INT,
    IN p_note          VARCHAR(255)
)
BEGIN
    DECLARE v_exists INT;
    DECLARE v_stock  INT;

    IF p_change_amount = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Stock change of zero is not a change';
    END IF;

    SELECT COUNT(*) INTO v_exists FROM products WHERE product_id = p_product_id;
    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unknown product_id';
    END IF;

    -- Lock the row before reading it, so two callers cannot both decide
    -- there is enough stock for the same last unit.
    SELECT stock_quantity INTO v_stock
    FROM products WHERE product_id = p_product_id FOR UPDATE;

    IF v_stock + p_change_amount < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Change would push stock below zero';
    END IF;

    UPDATE products
       SET stock_quantity = stock_quantity + p_change_amount
     WHERE product_id = p_product_id;

    INSERT INTO inventory_logs (product_id, order_id, change_amount, reason, note)
    VALUES (p_product_id, p_order_id, p_change_amount, p_reason, p_note);
END$$
DELIMITER ;
