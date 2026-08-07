USE inventory_order_management;

-- Proves the database refuses bad data on its own, without relying on
-- application code to remember the rules.
-- Run straight after a fresh build. Nothing here should change any data.

SELECT '--- constraint tests ---' AS suite;

CALL expect_error(
  'INSERT INTO orders (customer_id, status) VALUES (9999, ''pending'')',
  'order for a customer that does not exist');

CALL expect_error(
  'UPDATE products SET stock_quantity = -5 WHERE product_id = 1',
  'negative stock');

CALL expect_error(
  'INSERT INTO customers (name, email) VALUES (''Copy'', ''jane.mukamana@example.com'')',
  'duplicate customer email');

CALL expect_error(
  'INSERT INTO customers (name, email) VALUES (''No At Sign'', ''bad.example.com'')',
  'email with no @');

CALL expect_error(
  'INSERT INTO customers (name, email) VALUES (''No Dot'', ''bad@examplecom'')',
  'email with no . after the @');

CALL expect_error(
  'INSERT INTO order_details (order_id, product_id, quantity, unit_price)
     VALUES (1, 1, 1, 15.99)',
  'same product twice in one order');

CALL expect_error(
  'INSERT INTO order_details (order_id, product_id, quantity, unit_price)
     VALUES (1, 3, 0, 7.99)',
  'order line with zero quantity');

CALL expect_error(
  'UPDATE order_details SET returned_quantity = 99 WHERE order_detail_id = 1',
  'returning more units than were ordered');

CALL expect_error(
  'INSERT INTO order_details (order_id, product_id, quantity, unit_price, discount_rate)
     VALUES (1, 3, 1, 7.99, 1.5000)',
  'line discount rate of more than 100 percent');

CALL expect_error(
  'INSERT INTO orders (customer_id, placed_at) VALUES (1, DATE_ADD(NOW(), INTERVAL 5 DAY))',
  'order dated in the future');

CALL expect_error(
  'UPDATE orders SET status = ''pending'' WHERE order_id = 1',
  'delivered order moved back to pending');

CALL expect_error(
  'UPDATE inventory_logs SET change_amount = 999 WHERE log_id = 1',
  'editing the append-only ledger');

CALL expect_error(
  'DELETE FROM inventory_logs WHERE log_id = 1',
  'deleting from the append-only ledger');

CALL expect_error(
  'INSERT INTO inventory_logs (product_id, change_amount, reason)
     VALUES (1, 5, ''MADE_UP_REASON'')',
  'unrecognised stock change reason');

CALL expect_error(
  'DELETE FROM customers WHERE customer_id = 1',
  'deleting a customer who has orders');
