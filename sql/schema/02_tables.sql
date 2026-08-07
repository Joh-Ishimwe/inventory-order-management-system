-- Core tables: customers, products, orders, order lines and the stock audit log.
USE inventory_order_management;

-- customers
CREATE TABLE customers (
    customer_id  INT           PRIMARY KEY AUTO_INCREMENT,
    name         VARCHAR(100)  NOT NULL,
    email        VARCHAR(255)  NOT NULL UNIQUE,
    phone_number VARCHAR(20),
    is_active    BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_customers_email_shape CHECK (email LIKE '%_@_%._%')
);

-- products
CREATE TABLE products (
    product_id     INT           PRIMARY KEY AUTO_INCREMENT,
    name            VARCHAR(150)  NOT NULL,
    category        VARCHAR(50),
    price           DECIMAL(10,2) NOT NULL,
    stock_quantity  INT           NOT NULL DEFAULT 0,
    reorder_level   INT           NOT NULL DEFAULT 0,
    is_low_stock    BOOLEAN       AS (stock_quantity <= reorder_level) STORED,
    created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_products_stock_non_negative CHECK (stock_quantity >= 0),
    CONSTRAINT chk_products_price_non_negative CHECK (price >= 0),
    CONSTRAINT chk_products_reorder_non_negative CHECK (reorder_level >= 0)
);

-- orders
CREATE TABLE orders (
    order_id        INT           PRIMARY KEY AUTO_INCREMENT,
    customer_id     INT           NOT NULL,
    placed_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    subtotal_amount       DECIMAL(10,2) NOT NULL DEFAULT 0,
    bulk_discount_amount  DECIMAL(10,2) NOT NULL DEFAULT 0,
    order_discount_rate   DECIMAL(5,4)  NOT NULL DEFAULT 0,
    order_discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    total_amount          DECIMAL(10,2) NOT NULL DEFAULT 0,

    status          VARCHAR(20)   NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_orders_subtotal_non_negative CHECK (subtotal_amount >= 0),
    CONSTRAINT chk_orders_bulk_non_negative     CHECK (bulk_discount_amount >= 0),
    CONSTRAINT chk_orders_orderdisc_non_negative CHECK (order_discount_amount >= 0),
    CONSTRAINT chk_orders_total_non_negative    CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_discount_range        CHECK (order_discount_rate >= 0
                                                   AND order_discount_rate < 1),
    CONSTRAINT chk_orders_status CHECK (
        status IN ('pending','shipped','delivered','cancelled','returned')
    ),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT
);

-- order_details
CREATE TABLE order_details (
    order_detail_id   INT           PRIMARY KEY AUTO_INCREMENT,
    order_id          INT           NOT NULL,
    product_id        INT           NOT NULL,
    quantity          INT           NOT NULL,
    unit_price        DECIMAL(10,2) NOT NULL,
    discount_rate     DECIMAL(5,4)  NOT NULL DEFAULT 0,
    returned_quantity INT           NOT NULL DEFAULT 0,
    return_date       DATE,
    created_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_order_details_order_product UNIQUE (order_id, product_id),
    CONSTRAINT chk_od_quantity_positive   CHECK (quantity > 0),
    CONSTRAINT chk_od_price_non_negative  CHECK (unit_price >= 0),
    CONSTRAINT chk_od_discount_range      CHECK (discount_rate >= 0
                                             AND discount_rate < 1),
    CONSTRAINT chk_od_returned_range      CHECK (returned_quantity >= 0
                                             AND returned_quantity <= quantity),
    CONSTRAINT chk_od_return_date_present CHECK (
        (returned_quantity = 0 AND return_date IS NULL)
        OR (returned_quantity > 0 AND return_date IS NOT NULL)
    ),
    CONSTRAINT fk_od_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_od_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT
);

-- inventory_logs
CREATE TABLE inventory_logs (
    log_id        INT         PRIMARY KEY AUTO_INCREMENT,
    product_id    INT         NOT NULL,
    order_id      INT,
    change_amount INT         NOT NULL,
    balance_after INT         NOT NULL,
    reason        VARCHAR(20) NOT NULL,
    note          VARCHAR(255),
    changed_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_logs_change_nonzero CHECK (change_amount <> 0),
    CONSTRAINT chk_logs_balance_non_negative CHECK (balance_after >= 0),
    CONSTRAINT chk_logs_reason CHECK (
        reason IN ('INITIAL','ORDER','REPLENISHMENT','RETURN','CANCELLATION','ADJUSTMENT')
    ),
    CONSTRAINT fk_logs_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_logs_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE RESTRICT
);
