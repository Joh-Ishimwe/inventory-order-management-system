USE inventory_order_management;

-- one-to-many from products; optional link to orders
CREATE TABLE inventory_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    product_id INT NOT NULL,
    order_id INT,
    change_amount INT NOT NULL,
    reason VARCHAR(50) NOT NULL,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (change_amount <> 0),
    CHECK (reason IN ('ORDER','REPLENISHMENT','RETURN','CANCELLATION','ADJUSTMENT')),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
        ON DELETE RESTRICT,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON DELETE SET NULL
);