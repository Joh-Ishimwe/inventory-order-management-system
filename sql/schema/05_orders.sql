USE inventory_order_management;

-- One customer has many orders. The foreign key lives here, on the "many" side.
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
