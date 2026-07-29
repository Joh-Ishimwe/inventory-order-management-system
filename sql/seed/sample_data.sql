USE inventory_order_management;

-- =========================================================
-- 1. CUSTOMERS (5 customers, one inactive)
-- =========================================================
INSERT INTO customers (name, email, phone_number, is_active) VALUES
('Jane Mukamana', 'jane.mukamana@email.com', '+250788111111', TRUE),
('Tom Habimana', 'tom.habimana@email.com', '+250788222222', TRUE),
('Sarah Uwase', 'sarah.uwase@email.com', '+250788333333', TRUE),
('Eric Niyonzima', 'eric.niyonzima@email.com', '+250788444444', TRUE),
('Grace Ingabire', 'grace.ingabire@email.com', '+250788555555', FALSE);

-- =========================================================
-- 2. PRODUCTS (6 products, varied stock levels)
-- =========================================================
INSERT INTO products (name, category, price, stock_quantity, reorder_level) VALUES
('Wireless Mouse', 'Electronics', 15.99, 50, 10),
('Mechanical Keyboard', 'Electronics', 45.50, 30, 8),
('USB-C Cable', 'Electronics', 7.99, 3, 15),
('Laptop Stand', 'Accessories', 25.00, 20, 5),
('Desk Lamp', 'Home Office', 18.75, 0, 5),
('Notebook Set', 'Stationery', 6.50, 100, 20);

-- =========================================================
-- 3. ORDERS (varied statuses)
-- =========================================================
INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES
(1, '2026-07-01', 61.49, 'delivered'),
(2, '2026-07-05', 25.00, 'shipped'),
(3, '2026-07-10', 15.98, 'delivered'),
(1, '2026-07-15', 45.50, 'cancelled'),
(4, '2026-07-20', 32.50, 'pending');

-- =========================================================
-- 4. ORDER_DETAILS (line items, one with a partial return)
-- =========================================================
INSERT INTO order_details (order_id, product_id, quantity, unit_price, returned_quantity, return_date) VALUES
(1, 1, 1, 15.99, 0, NULL),
(1, 2, 1, 45.50, 0, NULL),
(2, 4, 1, 25.00, 0, NULL),
(3, 1, 2, 15.99, 1, '2026-07-12'),
(4, 2, 1, 45.50, 0, NULL),
(5, 6, 5, 6.50, 0, NULL);

-- =========================================================
-- 5. INVENTORY_LOGS (covers all 5 reason types)
-- =========================================================
INSERT INTO inventory_logs (product_id, order_id, change_amount, reason) VALUES
(1, 1, -1, 'ORDER'),
(2, 1, -1, 'ORDER'),
(4, 2, -1, 'ORDER'),
(1, 3, -2, 'ORDER'),
(1, 3, 1, 'RETURN'),
(2, 4, 1, 'CANCELLATION'),
(3, NULL, 50, 'REPLENISHMENT'),
(5, NULL, 20, 'REPLENISHMENT'),
(6, NULL, -2, 'ADJUSTMENT');