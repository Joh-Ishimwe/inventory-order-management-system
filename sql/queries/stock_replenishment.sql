USE inventory_order_management;

-- Adds stock back to a product and logs the change as a replenishment.
DELIMITER $$

CREATE PROCEDURE replenish_stock(
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    START TRANSACTION;

    UPDATE products
    SET stock_quantity = stock_quantity + p_quantity
    WHERE product_id = p_product_id;

    INSERT INTO inventory_logs (product_id, order_id, change_amount, reason)
    VALUES (p_product_id, NULL, p_quantity, 'REPLENISHMENT');

    COMMIT;
END$$

DELIMITER ;