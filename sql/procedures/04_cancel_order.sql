USE inventory_order_management;

DROP PROCEDURE IF EXISTS cancel_order;

DELIMITER $$
-- Cancels an order that has not been delivered yet, and puts the stock back.
CREATE PROCEDURE cancel_order(
    IN p_order_id INT,
    IN p_note     VARCHAR(255)
)
BEGIN
    DECLARE v_done       BOOLEAN DEFAULT FALSE;
    DECLARE v_status     VARCHAR(20);
    DECLARE v_exists     INT;
    DECLARE v_product_id INT;
    DECLARE v_restore    INT;

    -- Only what the customer still has counts. Anything already returned
    -- was put back by the return, so returning it twice would inflate stock.
    DECLARE cur_lines CURSOR FOR
        SELECT product_id, quantity - returned_quantity
        FROM order_details
        WHERE order_id = p_order_id AND quantity - returned_quantity > 0
        ORDER BY product_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists FROM orders WHERE order_id = p_order_id;
    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unknown order_id';
    END IF;

    SELECT status INTO v_status FROM orders WHERE order_id = p_order_id FOR UPDATE;

    IF v_status NOT IN ('pending','shipped') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only pending or shipped orders can be cancelled';
    END IF;

    OPEN cur_lines;
    line_loop: LOOP
        FETCH cur_lines INTO v_product_id, v_restore;
        IF v_done THEN
            LEAVE line_loop;
        END IF;
        CALL record_stock_change(v_product_id, v_restore, 'CANCELLATION', p_order_id, p_note);
    END LOOP;
    CLOSE cur_lines;

    UPDATE orders SET status = 'cancelled' WHERE order_id = p_order_id;

    COMMIT;
END$$
DELIMITER ;
