USE inventory_order_management;

DROP PROCEDURE IF EXISTS place_order;

DELIMITER $$
-- Places one order containing any number of products, in a single call.
--
-- p_items is a JSON array, for example:
--   [{"product_id":1,"quantity":2},{"product_id":3,"quantity":1}]
--
-- Either the whole order succeeds or none of it happens. There is no
-- half-built draft left behind if something fails partway.
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

    -- Ordered by product_id on purpose. If every caller locks products in
    -- the same order, two concurrent orders cannot deadlock each other.
    DECLARE cur_items CURSOR FOR
        SELECT product_id, quantity FROM tmp_place_order_items ORDER BY product_id;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    -- Any error at all: undo everything, then pass the error up unchanged
    -- so the caller sees the real reason.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_place_order_items;
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

    -- Flatten the JSON into rows. GROUP BY merges a product listed twice
    -- into one line, which the unique constraint on order_details requires.
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

    -- Catch unknown products up front, so the loop below can assume
    -- every lookup finds a row.
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

    -- subtotal_amount was maintained by the order_details trigger as each
    -- line went in, so the discount can be worked out from it now.
    CALL apply_order_discount(p_order_id);

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_place_order_items;
END$$
DELIMITER ;
