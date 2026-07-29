USE inventory_order_management;

-- Orders and products are many-to-many, so they meet in this table.
-- One row = one product inside one order.
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
