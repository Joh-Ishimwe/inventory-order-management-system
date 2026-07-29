USE inventory_order_management;

DROP FUNCTION IF EXISTS get_rule;

DELIMITER $$
-- The only way anything reads a business threshold. Views, procedures and
-- reports all call this, so a threshold exists in exactly one place.
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
