USE inventory_order_management;

-- get_rule: the only way anything reads a business threshold, so each one exists in one place.
DROP FUNCTION IF EXISTS get_rule;

DELIMITER $$
CREATE FUNCTION get_rule(p_key VARCHAR(50))
RETURNS DECIMAL(12,4)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_value DECIMAL(12,4);
    DECLARE v_count INT;

    SELECT COUNT(*) INTO v_count FROM business_rules WHERE rule_key = p_key;
    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Unknown business rule key';
    END IF;

    SELECT rule_value INTO v_value FROM business_rules WHERE rule_key = p_key;
    RETURN v_value;
END$$
DELIMITER ;

-- log_event: the only way anything writes to system_logs. Deliberately does its own
-- COMMIT (unlike record_stock_change), so a log row survives even when the caller's
-- transaction rolls back. That only works because of where it gets called from: after
-- the caller's own ROLLBACK (failure) or after the caller's own COMMIT (success) --
-- never while a caller's transaction is still open, or this would commit it early.
DROP PROCEDURE IF EXISTS log_event;

DELIMITER $$
CREATE PROCEDURE log_event(
    IN p_log_level  VARCHAR(10),
    IN p_source     VARCHAR(64),
    IN p_message    VARCHAR(500),
    IN p_error_code VARCHAR(20),
    IN p_context    JSON
)
BEGIN
    INSERT INTO system_logs (log_level, source, message, error_code, context)
    VALUES (p_log_level, p_source, p_message, p_error_code, p_context);
    COMMIT;
END$$
DELIMITER ;

-- record_stock_change: the single owner of stock movement, keeping the balance and the
-- ledger from drifting apart. Deliberately has no COMMIT, so it composes inside a bigger transaction.
DROP PROCEDURE IF EXISTS record_stock_change;

DELIMITER $$
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

    -- Lock the row before reading, so two callers can't both see stock for the same last unit.
    SELECT stock_quantity INTO v_stock
    FROM products WHERE product_id = p_product_id FOR UPDATE;

    IF v_stock + p_change_amount < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Change would push stock below zero';
    END IF;

    UPDATE products
       SET stock_quantity = stock_quantity + p_change_amount
     WHERE product_id = p_product_id;

    INSERT INTO inventory_logs (product_id, order_id, change_amount, balance_after, reason, note)
    VALUES (p_product_id, p_order_id, p_change_amount, v_stock + p_change_amount, p_reason, p_note);
END$$
DELIMITER ;

-- apply_order_discount: sets the order-value discount on top of bulk discounts, judged on the
-- post-bulk amount (not list price) and frozen once at placement.
DROP PROCEDURE IF EXISTS apply_order_discount;

DELIMITER $$
CREATE PROCEDURE apply_order_discount(IN p_order_id INT)
BEGIN
    DECLARE v_after_bulk DECIMAL(10,2);
    DECLARE v_rate       DECIMAL(5,4) DEFAULT 0;

    SELECT ROUND(COALESCE(SUM(ROUND(quantity * unit_price * (1 - discount_rate), 2)), 0), 2)
      INTO v_after_bulk
    FROM order_details WHERE order_id = p_order_id;

    IF v_after_bulk >= get_rule('spend_t2_min') THEN
        SET v_rate = get_rule('spend_t2_rate');
    ELSEIF v_after_bulk >= get_rule('spend_t1_min') THEN
        SET v_rate = get_rule('spend_t1_rate');
    END IF;

    UPDATE orders
       SET order_discount_rate   = v_rate,
           order_discount_amount = ROUND(v_after_bulk * v_rate, 2),
           total_amount          = ROUND(v_after_bulk * (1 - v_rate), 2)
     WHERE order_id = p_order_id;
END$$
DELIMITER ;

-- recalc_order_money: rebuilds an order's money columns from its lines, shared by all three
-- order_details triggers so editing a line never reprices the order against today's bands.
DROP PROCEDURE IF EXISTS recalc_order_money;

DELIMITER $$
CREATE PROCEDURE recalc_order_money(IN p_order_id INT)
BEGIN
    DECLARE v_gross      DECIMAL(10,2);
    DECLARE v_after_bulk DECIMAL(10,2);
    DECLARE v_rate       DECIMAL(5,4);

    -- Gross is list price; after-bulk applies each line's own rate, rounded per line as an invoice would show it.
    SELECT ROUND(COALESCE(SUM(quantity * unit_price), 0), 2),
           ROUND(COALESCE(SUM(ROUND(quantity * unit_price * (1 - discount_rate), 2)), 0), 2)
      INTO v_gross, v_after_bulk
    FROM order_details WHERE order_id = p_order_id;

    SELECT order_discount_rate INTO v_rate FROM orders WHERE order_id = p_order_id;

    UPDATE orders
       SET subtotal_amount       = v_gross,
           bulk_discount_amount  = ROUND(v_gross - v_after_bulk, 2),
           order_discount_amount = ROUND(v_after_bulk * v_rate, 2),
           total_amount          = ROUND(v_after_bulk * (1 - v_rate), 2)
     WHERE order_id = p_order_id;
END$$
DELIMITER ;

-- place_order: places a multi-item order atomically; p_items is a JSON array of {product_id, quantity}.
DROP PROCEDURE IF EXISTS place_order;

DELIMITER $$
CREATE PROCEDURE place_order(
    IN  p_customer_id INT,
    IN  p_items       JSON,
    OUT p_order_id    INT
)
BEGIN
    DECLARE v_done        BOOLEAN DEFAULT FALSE;
    DECLARE v_product_id  INT;
    DECLARE v_quantity    INT;
    DECLARE v_stock       INT;
    DECLARE v_price       DECIMAL(10,2);
    DECLARE v_active      INT;
    DECLARE v_missing     INT;
    DECLARE v_bad_qty     INT;
    DECLARE v_msg         VARCHAR(255);
    DECLARE v_err_msg     VARCHAR(255);
    DECLARE v_err_state   VARCHAR(10);

    -- Ordered by product_id, so two concurrent orders always lock in the same order and can't deadlock.
    DECLARE cur_items CURSOR FOR
        SELECT product_id, quantity FROM tmp_place_order_items ORDER BY product_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    -- Any error rolls back and re-signals unchanged, so the caller sees the real reason.
    -- The log_event call happens after ROLLBACK, so the log row survives it.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT, v_err_state = RETURNED_SQLSTATE;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_place_order_items;
        CALL log_event('ERROR', 'place_order', v_err_msg, v_err_state,
                        JSON_OBJECT('customer_id', p_customer_id));
        RESIGNAL;
    END;

    -- Check the input before opening a transaction.
    IF p_items IS NULL OR JSON_TYPE(p_items) <> 'ARRAY' OR JSON_LENGTH(p_items) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'p_items must be a non-empty JSON array of {product_id, quantity}';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_place_order_items;
    CREATE TEMPORARY TABLE tmp_place_order_items (
        product_id INT PRIMARY KEY,
        quantity   INT NOT NULL
    );

    START TRANSACTION;

    -- Flatten the JSON into rows; GROUP BY merges a product listed twice into one line.
    INSERT INTO tmp_place_order_items (product_id, quantity)
    SELECT jt.product_id, SUM(jt.quantity)
    FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
             product_id INT PATH '$.product_id',
             quantity   INT PATH '$.quantity'
         )) AS jt
    GROUP BY jt.product_id;

    SELECT COUNT(*) INTO v_bad_qty
    FROM tmp_place_order_items
    WHERE quantity IS NULL OR quantity <= 0 OR product_id IS NULL;
    IF v_bad_qty > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Every item needs a product_id and a quantity above zero';
    END IF;

    SELECT COUNT(*) INTO v_active
    FROM customers WHERE customer_id = p_customer_id AND is_active = TRUE;
    IF v_active = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Customer does not exist or is not active';
    END IF;

    -- Catch unknown products up front, so the loop below can assume every lookup finds a row.
    SELECT COUNT(*) INTO v_missing
    FROM tmp_place_order_items t
    LEFT JOIN products p ON p.product_id = t.product_id
    WHERE p.product_id IS NULL;
    IF v_missing > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'One or more product_id values do not exist';
    END IF;

    INSERT INTO orders (customer_id, status) VALUES (p_customer_id, 'pending');
    SET p_order_id = LAST_INSERT_ID();

    OPEN cur_items;
    item_loop: LOOP
        FETCH cur_items INTO v_product_id, v_quantity;
        IF v_done THEN
            LEAVE item_loop;
        END IF;

        SELECT stock_quantity, price INTO v_stock, v_price
        FROM products WHERE product_id = v_product_id FOR UPDATE;

        IF v_stock < v_quantity THEN
            SET v_msg = CONCAT('Insufficient stock for product_id ', v_product_id,
                               ': asked ', v_quantity, ', available ', v_stock);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
        END IF;

        -- Price is copied in here, not looked up later.
        INSERT INTO order_details (order_id, product_id, quantity, unit_price)
        VALUES (p_order_id, v_product_id, v_quantity, v_price);

        CALL record_stock_change(v_product_id, -v_quantity, 'ORDER', p_order_id, NULL);
    END LOOP;
    CLOSE cur_items;

    -- subtotal_amount was already maintained by the order_details trigger, so the discount can use it now.
    CALL apply_order_discount(p_order_id);

    COMMIT;
    CALL log_event('INFO', 'place_order', 'Order placed', NULL,
                    JSON_OBJECT('order_id', p_order_id, 'customer_id', p_customer_id));
    DROP TEMPORARY TABLE IF EXISTS tmp_place_order_items;
END$$
DELIMITER ;

-- cancel_order: cancels an order that has not been delivered yet, and puts the stock back.
DROP PROCEDURE IF EXISTS cancel_order;

DELIMITER $$
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
    DECLARE v_err_msg     VARCHAR(255);
    DECLARE v_err_state   VARCHAR(10);

    -- Only outstanding quantity counts; already-returned units were restored by the return itself.
    DECLARE cur_lines CURSOR FOR
        SELECT product_id, quantity - returned_quantity
        FROM order_details
        WHERE order_id = p_order_id AND quantity - returned_quantity > 0
        ORDER BY product_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT, v_err_state = RETURNED_SQLSTATE;
        ROLLBACK;
        CALL log_event('ERROR', 'cancel_order', v_err_msg, v_err_state,
                        JSON_OBJECT('order_id', p_order_id));
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
    CALL log_event('INFO', 'cancel_order', 'Order cancelled', NULL,
                    JSON_OBJECT('order_id', p_order_id));
END$$
DELIMITER ;

-- return_order_line: returns some or all units of one line on a delivered order.
DROP PROCEDURE IF EXISTS return_order_line;

DELIMITER $$
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
    DECLARE v_err_msg     VARCHAR(255);
    DECLARE v_err_state   VARCHAR(10);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT, v_err_state = RETURNED_SQLSTATE;
        ROLLBACK;
        CALL log_event('ERROR', 'return_order_line', v_err_msg, v_err_state,
                        JSON_OBJECT('order_detail_id', p_order_detail_id));
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
    CALL log_event('INFO', 'return_order_line', 'Return recorded', NULL,
                    JSON_OBJECT('order_detail_id', p_order_detail_id, 'order_id', v_order_id,
                                'quantity', p_quantity));
END$$
DELIMITER ;

-- replenish_stock: adds stock from a supplier delivery; the positive-quantity check matters because
-- a caller with only EXECUTE here is borrowing admin rights and could otherwise drain stock silently.
DROP PROCEDURE IF EXISTS replenish_stock;

DELIMITER $$
CREATE PROCEDURE replenish_stock(
    IN p_product_id INT,
    IN p_quantity   INT,
    IN p_note       VARCHAR(255)
)
BEGIN
    DECLARE v_err_msg   VARCHAR(255);
    DECLARE v_err_state VARCHAR(10);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT, v_err_state = RETURNED_SQLSTATE;
        ROLLBACK;
        CALL log_event('ERROR', 'replenish_stock', v_err_msg, v_err_state,
                        JSON_OBJECT('product_id', p_product_id, 'quantity', p_quantity));
        RESIGNAL;
    END;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Replenishment quantity must be above zero';
    END IF;

    START TRANSACTION;
    CALL record_stock_change(p_product_id, p_quantity, 'REPLENISHMENT', NULL, p_note);
    COMMIT;
    CALL log_event('INFO', 'replenish_stock', 'Stock replenished', NULL,
                    JSON_OBJECT('product_id', p_product_id, 'quantity', p_quantity));
END$$
DELIMITER ;

-- adjust_stock: corrects stock after a stocktake, breakage or write-off; a reason note is required.
DROP PROCEDURE IF EXISTS adjust_stock;

DELIMITER $$
CREATE PROCEDURE adjust_stock(
    IN p_product_id    INT,
    IN p_change_amount INT,
    IN p_note          VARCHAR(255)
)
BEGIN
    DECLARE v_err_msg   VARCHAR(255);
    DECLARE v_err_state VARCHAR(10);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err_msg = MESSAGE_TEXT, v_err_state = RETURNED_SQLSTATE;
        ROLLBACK;
        CALL log_event('ERROR', 'adjust_stock', v_err_msg, v_err_state,
                        JSON_OBJECT('product_id', p_product_id, 'change_amount', p_change_amount));
        RESIGNAL;
    END;

    IF p_note IS NULL OR TRIM(p_note) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Adjustments must say why, for the audit trail';
    END IF;

    START TRANSACTION;
    CALL record_stock_change(p_product_id, p_change_amount, 'ADJUSTMENT', NULL, p_note);
    COMMIT;
    CALL log_event('INFO', 'adjust_stock', 'Stock adjusted', NULL,
                    JSON_OBJECT('product_id', p_product_id, 'change_amount', p_change_amount));
END$$
DELIMITER ;

-- replenish_all: applies the restock plan one product at a time, recording failures as FAILED
-- instead of aborting the batch, and returns one row per product attempted.
DROP PROCEDURE IF EXISTS replenish_all;

DELIMITER $$
CREATE PROCEDURE replenish_all(IN p_note VARCHAR(255))
BEGIN
    DECLARE v_done        INT DEFAULT FALSE;
    DECLARE v_product_id  INT;
    DECLARE v_name        VARCHAR(150);
    DECLARE v_stock       INT;
    DECLARE v_restock_by  INT;
    DECLARE v_error       VARCHAR(255);
    DECLARE v_ok_count     INT;
    DECLARE v_failed_count INT;

    DECLARE plan_cursor CURSOR FOR
        SELECT product_id, name, stock_quantity, restock_by FROM v_replenishment_plan;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DROP TEMPORARY TABLE IF EXISTS tmp_replenish_results;
    CREATE TEMPORARY TABLE tmp_replenish_results (
        product_id     INT,
        name           VARCHAR(150),
        previous_stock INT,
        restocked_by   INT,
        status         VARCHAR(10),
        detail         VARCHAR(255)
    );

    OPEN plan_cursor;
    read_loop: LOOP
        FETCH plan_cursor INTO v_product_id, v_name, v_stock, v_restock_by;
        IF v_done THEN
            LEAVE read_loop;
        END IF;

        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                GET DIAGNOSTICS CONDITION 1 v_error = MESSAGE_TEXT;
                INSERT INTO tmp_replenish_results VALUES
                    (v_product_id, v_name, v_stock, v_restock_by, 'FAILED', v_error);
            END;

            CALL replenish_stock(v_product_id, v_restock_by, p_note);
            INSERT INTO tmp_replenish_results VALUES
                (v_product_id, v_name, v_stock, v_restock_by, 'OK', NULL);
        END;
    END LOOP;
    CLOSE plan_cursor;

    SELECT * FROM tmp_replenish_results;

    -- One summary row per batch run, on top of the per-product rows replenish_stock already logged.
    SELECT COUNT(*) INTO v_ok_count     FROM tmp_replenish_results WHERE status = 'OK';
    SELECT COUNT(*) INTO v_failed_count FROM tmp_replenish_results WHERE status = 'FAILED';
    CALL log_event('INFO', 'replenish_all', 'Batch replenishment run', NULL,
                    JSON_OBJECT('attempted', v_ok_count + v_failed_count,
                                'ok', v_ok_count, 'failed', v_failed_count));

    DROP TEMPORARY TABLE tmp_replenish_results;
END$$
DELIMITER ;
