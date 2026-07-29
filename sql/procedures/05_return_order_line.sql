USE inventory_order_management;

DROP PROCEDURE IF EXISTS return_order_line;

DELIMITER $$
-- Returns some or all units of one line on a delivered order.
-- Partial returns are the normal case: five ordered, two sent back.
CREATE PROCEDURE return_order_line(
    IN p_order_detail_id INT,
    IN p_quantity        INT,
    IN p_return_date     DATE,
    IN p_note            VARCHAR(255)
)
BEGIN
    DECLARE v_exists      INT;
    DECLARE v_order_id    INT;
    DECLARE v_product_id  INT;
    DECLARE v_returnable  INT;
    DECLARE v_status      VARCHAR(20);
    DECLARE v_open_lines  INT;
    DECLARE v_date        DATE;
    DECLARE v_placed      DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Return quantity must be above zero';
    END IF;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists
    FROM order_details WHERE order_detail_id = p_order_detail_id;
    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown order_detail_id';
    END IF;

    SELECT od.order_id, od.product_id, od.quantity - od.returned_quantity,
           o.status, DATE(o.placed_at)
      INTO v_order_id, v_product_id, v_returnable, v_status, v_placed
    FROM order_details od
    JOIN orders o ON o.order_id = od.order_id
    WHERE od.order_detail_id = p_order_detail_id
    FOR UPDATE;

    IF v_status <> 'delivered' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only delivered orders can be returned';
    END IF;

    IF p_quantity > v_returnable THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot return more units than are still outstanding';
    END IF;

    SET v_date = IFNULL(p_return_date, CURDATE());
    IF v_date < v_placed THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Return date cannot be before the order date';
    END IF;

    UPDATE order_details
       SET returned_quantity = returned_quantity + p_quantity,
           return_date       = v_date
     WHERE order_detail_id = p_order_detail_id;

    CALL record_stock_change(v_product_id, p_quantity, 'RETURN', v_order_id, p_note);

    -- If nothing is left outstanding, the whole order counts as returned.
    SELECT COUNT(*) INTO v_open_lines
    FROM order_details
    WHERE order_id = v_order_id AND returned_quantity < quantity;

    IF v_open_lines = 0 THEN
        UPDATE orders SET status = 'returned' WHERE order_id = v_order_id;
    END IF;

    COMMIT;
END$$
DELIMITER ;
