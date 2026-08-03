USE inventory_order_management;

-- ---------------------------------------------------------------------------
-- customers
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------------
CREATE TABLE products (
    product_id     INT           PRIMARY KEY AUTO_INCREMENT,
    name           VARCHAR(150)  NOT NULL,
    category       VARCHAR(50),
    price          DECIMAL(10,2) NOT NULL,
    -- Running balance. The matching ledger is inventory_logs, and
    -- v_stock_reconciliation checks the two still agree.
    stock_quantity INT           NOT NULL DEFAULT 0,
    reorder_level  INT           NOT NULL DEFAULT 0,
    -- Stored so it can be indexed. A plain
    -- "WHERE stock_quantity <= reorder_level" compares two columns and
    -- can never use an index, so it always scans the whole table.
    is_low_stock   BOOLEAN       AS (stock_quantity <= reorder_level) STORED,
    created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_products_stock_non_negative CHECK (stock_quantity >= 0),
    CONSTRAINT chk_products_price_non_negative CHECK (price >= 0),
    CONSTRAINT chk_products_reorder_non_negative CHECK (reorder_level >= 0)
);

-- ---------------------------------------------------------------------------
-- orders
-- One customer has many orders. The foreign key lives here, on the "many" side.
-- ---------------------------------------------------------------------------
CREATE TABLE orders (
    order_id        INT           PRIMARY KEY AUTO_INCREMENT,
    customer_id     INT           NOT NULL,
    -- DATETIME, not TIMESTAMP: TIMESTAMP stops working after 2038.
    -- Full timestamp so two orders on the same day can still be ordered.
    placed_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- No generated order_date column here on purpose. MySQL evaluates a
    -- STORED generated column against the row before a BEFORE INSERT
    -- trigger has finished with it, and this table has one, which produced
    -- '0000-00-00'. The views derive DATE(placed_at) instead and expose it
    -- under the same name, so nothing downstream changes.

    -- Money is broken out so every discount can be explained afterwards.
    -- Two discounts stack, in this order:
    --   subtotal_amount        what the goods cost at list price
    --   bulk_discount_amount   taken off for buying units in quantity
    --   order_discount_amount  taken off for the value of the whole order
    --   total_amount           what was actually charged
    subtotal_amount       DECIMAL(10,2) NOT NULL DEFAULT 0,
    bulk_discount_amount  DECIMAL(10,2) NOT NULL DEFAULT 0,
    -- Locked in when the order is placed. Later rule changes must not
    -- silently reprice old orders.
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
    -- RESTRICT: a customer with orders cannot be deleted. Deactivate instead.
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- order_details
-- Orders and products are many-to-many, so they meet in this table.
-- One row = one product inside one order.
-- ---------------------------------------------------------------------------
CREATE TABLE order_details (
    order_detail_id   INT           PRIMARY KEY AUTO_INCREMENT,
    order_id          INT           NOT NULL,
    product_id        INT           NOT NULL,
    quantity          INT           NOT NULL,
    -- Copied from products.price at order time. If the price changes
    -- tomorrow, this order still shows what was actually charged.
    unit_price        DECIMAL(10,2) NOT NULL,
    -- Bulk discount for this line, set from the quantity when the line is
    -- created. Belongs on the line, not the order, because it depends on how
    -- many units of this one product were bought.
    discount_rate     DECIMAL(5,4)  NOT NULL DEFAULT 0,
    returned_quantity INT           NOT NULL DEFAULT 0,
    return_date       DATE,
    created_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                    ON UPDATE CURRENT_TIMESTAMP,
    -- One line per product per order. Two lines for the same product
    -- would double-count and break both the returns and the bulk maths.
    CONSTRAINT uq_order_details_order_product UNIQUE (order_id, product_id),
    CONSTRAINT chk_od_quantity_positive   CHECK (quantity > 0),
    CONSTRAINT chk_od_price_non_negative  CHECK (unit_price >= 0),
    CONSTRAINT chk_od_discount_range      CHECK (discount_rate >= 0
                                             AND discount_rate < 1),
    CONSTRAINT chk_od_returned_range      CHECK (returned_quantity >= 0
                                             AND returned_quantity <= quantity),
    -- A return date only makes sense if something was returned.
    CONSTRAINT chk_od_return_date_present CHECK (
        (returned_quantity = 0 AND return_date IS NULL)
        OR (returned_quantity > 0 AND return_date IS NOT NULL)
    ),
    -- CASCADE: line items are meaningless without their parent order.
    CONSTRAINT fk_od_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_od_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
-- inventory_logs
-- Append-only ledger. Every stock movement gets a row, and rows are never
-- edited or removed (triggers enforce that). stock_quantity should always
-- equal the sum of change_amount for a product.
-- ---------------------------------------------------------------------------
CREATE TABLE inventory_logs (
    log_id        INT         PRIMARY KEY AUTO_INCREMENT,
    product_id    INT         NOT NULL,
    -- NULL when no order caused it (a restock, a stocktake correction).
    order_id      INT,
    -- Signed: negative removes stock, positive adds it.
    change_amount INT         NOT NULL,
    reason        VARCHAR(20) NOT NULL,
    note          VARCHAR(255),
    changed_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_logs_change_nonzero CHECK (change_amount <> 0),
    CONSTRAINT chk_logs_reason CHECK (
        reason IN ('INITIAL','ORDER','REPLENISHMENT','RETURN','CANCELLATION','ADJUSTMENT')
    ),
    CONSTRAINT fk_logs_product FOREIGN KEY (product_id)
        REFERENCES products(product_id) ON DELETE RESTRICT,
    -- RESTRICT, not SET NULL. MySQL runs foreign key actions without firing
    -- triggers, so SET NULL would quietly edit a row the append-only guard
    -- is supposed to protect.
    CONSTRAINT fk_logs_order FOREIGN KEY (order_id)
        REFERENCES orders(order_id) ON DELETE RESTRICT
);
