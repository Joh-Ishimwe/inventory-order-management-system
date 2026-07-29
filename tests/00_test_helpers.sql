USE inventory_order_management;

DROP PROCEDURE IF EXISTS assert_equals;
DROP PROCEDURE IF EXISTS expect_error;

DELIMITER $$
-- Fails loudly instead of printing something a human has to read and judge.
-- A failing test raises an error, so a script or CI run stops.
CREATE PROCEDURE assert_equals(
    IN p_actual   VARCHAR(255),
    IN p_expected VARCHAR(255),
    IN p_label    VARCHAR(255)
)
BEGIN
    DECLARE v_msg VARCHAR(255);
    IF p_actual <=> p_expected THEN
        SELECT CONCAT('PASS  ', p_label, '  (', IFNULL(p_actual,'NULL'), ')') AS result;
    ELSE
        SET v_msg = CONCAT('FAIL: ', p_label,
                           ' | expected ', IFNULL(p_expected,'NULL'),
                           ' | got ',      IFNULL(p_actual,'NULL'));
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END$$

-- For the cases where being rejected IS the correct behaviour.
-- Runs the statement, expects it to blow up, and fails the test if it did not.
CREATE PROCEDURE expect_error(
    IN p_sql   TEXT,
    IN p_label VARCHAR(255)
)
BEGIN
    DECLARE v_failed BOOLEAN DEFAULT FALSE;
    DECLARE v_msg    VARCHAR(255);
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_failed = TRUE;

    SET @dyn_sql = p_sql;
    PREPARE dyn_stmt FROM @dyn_sql;
    EXECUTE dyn_stmt;
    DEALLOCATE PREPARE dyn_stmt;

    IF v_failed THEN
        SELECT CONCAT('PASS  rejected as expected: ', p_label) AS result;
    ELSE
        SET v_msg = CONCAT('FAIL: expected a rejection but it was allowed: ', p_label);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
    END IF;
END$$
DELIMITER ;
