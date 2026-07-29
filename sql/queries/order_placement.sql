USE inventory_order_management;

-- Places a new order for one product, checking stock availability first.
-- Rejects the order entirely (no partial data) if insufficient stock.
DELIMITER $$

CREATE PROCEDURE place_order(
    IN p_customer_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_stock INT;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_order_id INT;

    SELECT stock_quantity, price INTO v_stock, v_price
    FROM products
    WHERE product_id = p_product_id
    FOR UPDATE;

    IF v_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock for this product';
    ELSE
        START TRANSACTION;

        INSERT INTO orders (customer_id, order_date, total_amount, status)
        VALUES (p_customer_id, CURDATE(), p_quantity * v_price, 'pending');

        SET v_order_id = LAST_INSERT_ID();

        INSERT INTO order_details (order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, p_product_id, p_quantity, v_price);

        UPDATE products
        SET stock_quantity = stock_quantity - p_quantity
        WHERE product_id = p_product_id;

        INSERT INTO inventory_logs (product_id, order_id, change_amount, reason)
        VALUES (p_product_id, v_order_id, -p_quantity, 'ORDER');

        COMMIT;
    END IF;
END$$

DELIMITER ;