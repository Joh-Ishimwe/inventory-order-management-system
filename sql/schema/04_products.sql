USE inventory_order_management;

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
