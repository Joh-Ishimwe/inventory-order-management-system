USE inventory_order_management;

-- linking table: many-to-many orders <-> products
CREATE TABLE order_details (
    order_detail_id INT PRIMARY KEY AUTO_INCREMENT,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    returned_quantity INT NOT NULL DEFAULT 0,
    return_date DATE,
    CHECK (quantity > 0),
    CHECK (unit_price >= 0),
    CHECK (returned_quantity >= 0),
    CHECK (returned_quantity <= quantity),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(product_id)
        ON DELETE RESTRICT
);