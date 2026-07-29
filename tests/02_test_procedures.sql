USE inventory_order_management;

-- Checks the business logic end to end, against the numbers the seed
-- produces. Run on a freshly built and seeded database.

SELECT '--- procedure tests ---' AS suite;

-- Seed totals ------------------------------------------------------------
SELECT CAST(COUNT(*) AS CHAR) INTO @v FROM orders;
CALL assert_equals(@v, '6', 'seed created six orders');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 1;
CALL assert_equals(@v, '47', 'wireless mouse stock after orders and one return');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 2;
CALL assert_equals(@v, '27', 'keyboard stock after orders and one cancellation');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 4;
CALL assert_equals(@v, '29', 'laptop stand stock after a supplier delivery');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 6;
CALL assert_equals(@v, '93', 'notebook stock after an order and a write-off');

-- Bulk discount: based on units of one product on one line -----------------
SELECT CAST(discount_rate AS CHAR) INTO @v
FROM order_details WHERE order_id = 5 AND product_id = 6;
CALL assert_equals(@v, '0.0500', 'five units of one product earned the first bulk band');

SELECT CAST(bulk_discount_amount AS CHAR) INTO @v FROM orders WHERE order_id = 5;
CALL assert_equals(@v, '1.62', 'order 5 bulk discount is 5 percent of 32.50');

SELECT CAST(total_amount AS CHAR) INTO @v FROM orders WHERE order_id = 5;
CALL assert_equals(@v, '30.88', 'order 5 charged amount has the bulk discount taken off');

SELECT CAST(discount_rate AS CHAR) INTO @v
FROM order_details WHERE order_id = 3 AND product_id = 1;
CALL assert_equals(@v, '0.0000', 'two units is below the first bulk band, so no discount');

-- Order-value discount: applied on top of any bulk discount ---------------
SELECT CAST(subtotal_amount AS CHAR) INTO @v FROM orders WHERE order_id = 1;
CALL assert_equals(@v, '61.49', 'order 1 list price total comes from its line items');

SELECT CAST(order_discount_rate AS CHAR) INTO @v FROM orders WHERE order_id = 1;
CALL assert_equals(@v, '0.0500', 'order 1 crossed the first spend band');

SELECT CAST(total_amount AS CHAR) INTO @v FROM orders WHERE order_id = 1;
CALL assert_equals(@v, '58.42', 'order 1 charged amount has the spend discount taken off');

SELECT CAST(order_discount_rate AS CHAR) INTO @v FROM orders WHERE order_id = 6;
CALL assert_equals(@v, '0.1000', 'order 6 crossed the second spend band');

SELECT CAST(total_amount AS CHAR) INTO @v FROM orders WHERE order_id = 6;
CALL assert_equals(@v, '96.29', 'order 6 charged amount reflects the ten percent band');

-- Tiers are computed from the rules table ----------------------------------
SELECT customer_tier INTO @v FROM v_customer_tiers WHERE customer_id = 1;
CALL assert_equals(@v, 'Gold', 'Jane reaches Gold on net spend');

SELECT customer_tier INTO @v FROM v_customer_tiers WHERE customer_id = 3;
CALL assert_equals(@v, 'Bronze', 'Sarah stays Bronze once her return is deducted');

SELECT CAST(COUNT(*) AS CHAR) INTO @v FROM v_customer_tiers;
CALL assert_equals(@v, '5', 'every customer appears, including ones with no orders');

SELECT customer_tier INTO @v FROM v_customer_tiers WHERE customer_id = 5;
CALL assert_equals(@v, 'Bronze', 'a customer with no orders is Bronze, not missing');

-- Changing a threshold is one UPDATE, and everything follows ---------------
UPDATE business_rules SET rule_value = 200 WHERE rule_key = 'tier_gold_min';
SELECT customer_tier INTO @v FROM v_customer_tiers WHERE customer_id = 1;
CALL assert_equals(@v, 'Silver', 'raising the Gold bar moves Jane down with no code change');
UPDATE business_rules SET rule_value = 100 WHERE rule_key = 'tier_gold_min';

-- Low stock ---------------------------------------------------------------
SELECT CAST(COUNT(*) AS CHAR) INTO @v FROM v_low_stock;
CALL assert_equals(@v, '2', 'two products are at or below their reorder point');

SELECT severity INTO @v FROM v_low_stock WHERE product_id = 5;
CALL assert_equals(@v, 'OUT_OF_STOCK', 'desk lamp is flagged as out of stock');

-- Multi-product orders in a single call -----------------------------------
CALL place_order(2, '[{"product_id":1,"quantity":2},{"product_id":6,"quantity":3}]', @new_order);
SELECT CAST(COUNT(*) AS CHAR) INTO @v FROM order_details WHERE order_id = @new_order;
CALL assert_equals(@v, '2', 'one call created an order with two products');

SELECT CAST(subtotal_amount AS CHAR) INTO @v FROM orders WHERE order_id = @new_order;
CALL assert_equals(@v, '51.48', 'multi-product list price total (2x15.99 + 3x6.50)');

SELECT CAST(bulk_discount_amount AS CHAR) INTO @v FROM orders WHERE order_id = @new_order;
CALL assert_equals(@v, '0.00', 'small quantities earn no bulk discount');

SELECT CAST(order_discount_rate AS CHAR) INTO @v FROM orders WHERE order_id = @new_order;
CALL assert_equals(@v, '0.0500', 'multi-product order crossed the first spend band');

SELECT CAST(total_amount AS CHAR) INTO @v FROM orders WHERE order_id = @new_order;
CALL assert_equals(@v, '48.91', 'multi-product charged amount');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 1;
CALL assert_equals(@v, '45', 'stock came down for the first product in the order');

SELECT CAST(stock_quantity AS CHAR) INTO @v FROM products WHERE product_id = 6;
CALL assert_equals(@v, '90', 'stock came down for the second product in the order');

-- A product listed twice in the same payload is merged, not rejected
CALL place_order(2, '[{"product_id":6,"quantity":1},{"product_id":6,"quantity":2}]', @merged);
SELECT CAST(quantity AS CHAR) INTO @v FROM order_details WHERE order_id = @merged;
CALL assert_equals(@v, '3', 'a product listed twice is combined into one line');

-- Both discounts on one order ---------------------------------------------
-- Twelve of one product: second bulk band, and the remaining value still
-- clears the first spend band, so the two rules stack.
CALL place_order(2, '[{"product_id":6,"quantity":12}]', @bulk_order);

SELECT CAST(discount_rate AS CHAR) INTO @v FROM order_details WHERE order_id = @bulk_order;
CALL assert_equals(@v, '0.1000', 'twelve units earned the second bulk band');

SELECT CAST(subtotal_amount AS CHAR) INTO @v FROM orders WHERE order_id = @bulk_order;
CALL assert_equals(@v, '78.00', 'list price total before any discount');

SELECT CAST(bulk_discount_amount AS CHAR) INTO @v FROM orders WHERE order_id = @bulk_order;
CALL assert_equals(@v, '7.80', 'bulk discount is ten percent of the line');

SELECT CAST(order_discount_rate AS CHAR) INTO @v FROM orders WHERE order_id = @bulk_order;
CALL assert_equals(@v, '0.0500', 'the amount after bulk still clears the first spend band');

SELECT CAST(total_amount AS CHAR) INTO @v FROM orders WHERE order_id = @bulk_order;
CALL assert_equals(@v, '66.69', 'charged amount after both discounts');

-- Bulk bands are configuration too ----------------------------------------
UPDATE business_rules SET rule_value = 2 WHERE rule_key = 'bulk_t1_min_units';
CALL place_order(3, '[{"product_id":1,"quantity":2}]', @tuned_order);
SELECT CAST(discount_rate AS CHAR) INTO @v FROM order_details WHERE order_id = @tuned_order;
CALL assert_equals(@v, '0.0500', 'lowering the bulk threshold gives two units a discount');
UPDATE business_rules SET rule_value = 5 WHERE rule_key = 'bulk_t1_min_units';

-- An old line keeps the rate it was created with
SELECT CAST(discount_rate AS CHAR) INTO @v FROM order_details WHERE order_id = @tuned_order;
CALL assert_equals(@v, '0.0500', 'restoring the threshold does not reprice the existing line');

-- Rejections -------------------------------------------------------------
CALL expect_error(
  'CALL place_order(1, ''[{"product_id":3,"quantity":100}]'', @x)',
  'order for more units than exist');

CALL expect_error(
  'CALL place_order(5, ''[{"product_id":1,"quantity":1}]'', @x)',
  'order from a deactivated customer');

CALL expect_error('CALL place_order(1, ''[]'', @x)', 'order with no items');

CALL expect_error(
  'CALL place_order(1, ''[{"product_id":1,"quantity":0}]'', @x)',
  'order line with a quantity of zero');

CALL expect_error(
  'CALL place_order(1, ''[{"product_id":1,"quantity":1},{"product_id":9999,"quantity":1}]'', @x)',
  'order where one of several products does not exist');

CALL expect_error('CALL replenish_stock(1, -50, ''sneaky'')',
  'negative replenishment, which would drain stock while looking like a delivery');

CALL expect_error('CALL adjust_stock(1, -5, NULL)',
  'stock adjustment with no reason given');

CALL expect_error('CALL cancel_order(1, ''too late'')',
  'cancelling an order that was already delivered');

CALL expect_error('CALL return_order_line(1, 99, NULL, ''too many'')',
  'returning more units than are outstanding');

CALL expect_error('SELECT get_rule(''no_such_rule'')',
  'reading a business rule that does not exist');

-- Nothing partial was left behind by the rejected multi-product order
SELECT CAST(COUNT(*) AS CHAR) INTO @v
FROM order_details WHERE product_id = 9999;
CALL assert_equals(@v, '0', 'the failed order left no line items behind');

-- Every order header still agrees with its own lines
SELECT CAST(COUNT(*) AS CHAR) INTO @v
FROM orders o
JOIN (SELECT order_id, ROUND(SUM(quantity * unit_price), 2) AS gross
      FROM order_details GROUP BY order_id) d ON d.order_id = o.order_id
WHERE o.subtotal_amount <> d.gross;
CALL assert_equals(@v, '0', 'no order header disagrees with the sum of its lines');

SELECT '--- all procedure tests passed ---' AS suite;
