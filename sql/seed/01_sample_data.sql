USE inventory_order_management;

-- Sample data for demos and testing (names and emails are made up); stock always flows
-- through record_stock_change, and dates are relative to today so the tier window keeps working.

-- Customers. Grace is deactivated, to exercise the soft-delete path.
INSERT INTO customers (name, email, phone_number, is_active) VALUES
('Jane Mukamana',  'jane.mukamana@example.com',  '+250788111111', TRUE),
('Tom Habimana',   'tom.habimana@example.com',   '+250788222222', TRUE),
('Sarah Uwase',    'sarah.uwase@example.com',    '+250788333333', TRUE),
('Eric Niyonzima', 'eric.niyonzima@example.com', '+250788444444', TRUE),
('Grace Ingabire', 'grace.ingabire@example.com', '+250788555555', FALSE);

-- Products, all starting at zero stock.
INSERT INTO products (name, category, price, stock_quantity, reorder_level) VALUES
('Wireless Mouse',      'Electronics', 15.99, 0, 10),
('Mechanical Keyboard', 'Electronics', 45.50, 0,  8),
('USB-C Cable',         'Electronics',  7.99, 0, 15),
('Laptop Stand',        'Accessories', 25.00, 0,  5),
('Desk Lamp',           'Home Office', 18.75, 0,  5),
('Notebook Set',        'Stationery',   6.50, 0, 20);

-- Opening stock. Desk Lamp gets none, so it shows as out of stock.
CALL record_stock_change(1,  50, 'INITIAL', NULL, 'Opening stock');
CALL record_stock_change(2,  30, 'INITIAL', NULL, 'Opening stock');
CALL record_stock_change(3,   3, 'INITIAL', NULL, 'Opening stock, arrived short');
CALL record_stock_change(4,  20, 'INITIAL', NULL, 'Opening stock');
CALL record_stock_change(6, 100, 'INITIAL', NULL, 'Opening stock');

-- Historical orders, inserted directly with past dates and a settled status; live orders go through place_order instead.

-- Order 1: Jane, delivered — two small-quantity lines, no bulk discount, but crosses the first spend band.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (1, DATE_SUB(NOW(), INTERVAL 20 DAY), 'delivered');
SET @o1 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o1, 1, 1, 15.99),
(@o1, 2, 1, 45.50);
CALL apply_order_discount(@o1);
CALL record_stock_change(1, -1, 'ORDER', @o1, NULL);
CALL record_stock_change(2, -1, 'ORDER', @o1, NULL);

-- Order 2: Tom, shipped, below any discount band.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (2, DATE_SUB(NOW(), INTERVAL 15 DAY), 'shipped');
SET @o2 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o2, 4, 1, 25.00);
CALL apply_order_discount(@o2);
CALL record_stock_change(4, -1, 'ORDER', @o2, NULL);

-- Order 3: Sarah, delivered, then one of two units sent back.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (3, DATE_SUB(NOW(), INTERVAL 10 DAY), 'delivered');
SET @o3 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o3, 1, 2, 15.99);
CALL apply_order_discount(@o3);
CALL record_stock_change(1, -2, 'ORDER', @o3, NULL);

-- Order 4: Jane, placed then cancelled through the real procedure, so the
-- stock is returned and logged rather than typed in.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (1, DATE_SUB(NOW(), INTERVAL 8 DAY), 'pending');
SET @o4 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o4, 2, 1, 45.50);
CALL apply_order_discount(@o4);
CALL record_stock_change(2, -1, 'ORDER', @o4, NULL);

-- Order 5: Eric, pending — five units of one product, earning the first bulk band.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (4, DATE_SUB(NOW(), INTERVAL 3 DAY), 'pending');
SET @o5 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o5, 6, 5, 6.50);
CALL apply_order_discount(@o5);
CALL record_stock_change(6, -5, 'ORDER', @o5, NULL);

-- Order 6: Jane again, large enough for the second spend band, pushing her into Gold.
INSERT INTO orders (customer_id, placed_at, status)
VALUES (1, DATE_SUB(NOW(), INTERVAL 5 DAY), 'delivered');
SET @o6 = LAST_INSERT_ID();
INSERT INTO order_details (order_id, product_id, quantity, unit_price) VALUES
(@o6, 2, 2, 45.50),
(@o6, 1, 1, 15.99);
CALL apply_order_discount(@o6);
CALL record_stock_change(2, -2, 'ORDER', @o6, NULL);
CALL record_stock_change(1, -1, 'ORDER', @o6, NULL);

-- Now exercise the remaining paths through their real procedures.

-- Sarah returns one of her two mice.
SELECT order_detail_id INTO @od_return
FROM order_details WHERE order_id = @o3 AND product_id = 1;
CALL return_order_line(@od_return, 1, DATE_SUB(CURDATE(), INTERVAL 7 DAY), 'Wrong colour');

-- Jane's fourth order is cancelled.
CALL cancel_order(@o4, 'Customer changed their mind');

-- A supplier delivery.
CALL replenish_stock(4, 10, 'Supplier delivery, PO-1041');

-- A stocktake correction.
CALL adjust_stock(6, -2, 'Two sets water damaged in the store room');
