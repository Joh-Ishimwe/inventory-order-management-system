USE inventory_order_management;

CREATE TABLE customers (
    customer_id  INT           PRIMARY KEY AUTO_INCREMENT,
    name         VARCHAR(100)  NOT NULL,
    email        VARCHAR(255)  NOT NULL UNIQUE,
    phone_number VARCHAR(20),
    -- Soft delete. Customers are never removed, because their order
    -- history still has accounting value after they leave.
    is_active    BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_customers_email_shape CHECK (email LIKE '%_@_%._%')
);
