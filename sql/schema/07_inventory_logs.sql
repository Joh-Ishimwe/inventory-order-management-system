USE inventory_order_management;

-- Append-only ledger. Every stock movement gets a row, and rows are never
-- edited or removed (triggers enforce that). stock_quantity should always
-- equal the sum of change_amount for a product.
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
