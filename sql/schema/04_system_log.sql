-- System activity/error log: separate from inventory_logs. inventory_logs tracks stock
-- *movement*; this tracks whether the procedures driving that movement (and other
-- operations) actually ran cleanly, so a failure leaves a trail even though its
-- business-data changes get rolled back.
USE inventory_order_management;

CREATE TABLE system_logs (
    log_id      INT           PRIMARY KEY AUTO_INCREMENT,
    log_level   VARCHAR(10)   NOT NULL,
    source      VARCHAR(64)   NOT NULL,
    message     VARCHAR(500)  NOT NULL,
    error_code  VARCHAR(20),
    context     JSON,
    logged_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_system_logs_level CHECK (log_level IN ('INFO','WARNING','ERROR'))
);
