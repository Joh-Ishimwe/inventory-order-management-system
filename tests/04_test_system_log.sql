USE inventory_order_management;

-- Confirms system_logs actually captures success and failure paths of the procedures,
-- and that it behaves like inventory_logs: append-only, so a record of what happened
-- can't be edited after the fact.
-- Run after 02_test_procedures.sql (uses the same seeded customers/products).

SELECT '--- system log tests ---' AS suite;

-- A successful call leaves an INFO row for that source ---------------------
CALL adjust_stock(3, 5, 'test: system log check');

SELECT log_level INTO @v
FROM system_logs
WHERE source = 'adjust_stock'
ORDER BY log_id DESC LIMIT 1;
CALL assert_equals(@v, 'INFO', 'adjust_stock logs an INFO row on success');

SELECT CAST(JSON_EXTRACT(context, '$.product_id') AS CHAR) INTO @v
FROM system_logs
WHERE source = 'adjust_stock'
ORDER BY log_id DESC LIMIT 1;
CALL assert_equals(@v, '3', 'the INFO row keeps the product_id that was adjusted');

-- A rejected call leaves an ERROR row, and the rejected change is not applied ----
SELECT stock_quantity INTO @before FROM products WHERE product_id = 1;

CALL expect_error(
  'CALL place_order(5, ''[{"product_id":1,"quantity":1}]'', @x)',
  'place_order rejects an order from a deactivated customer');

SELECT stock_quantity INTO @after FROM products WHERE product_id = 1;
CALL assert_equals(CAST(@after AS CHAR), CAST(@before AS CHAR),
                    'the rejected order left stock untouched');

SELECT log_level INTO @v
FROM system_logs
WHERE source = 'place_order'
ORDER BY log_id DESC LIMIT 1;
CALL assert_equals(@v, 'ERROR', 'place_order logs an ERROR row when it rejects an order');

SELECT message INTO @v
FROM system_logs
WHERE source = 'place_order'
ORDER BY log_id DESC LIMIT 1;
CALL assert_equals(@v, 'Customer does not exist or is not active',
                    'the ERROR row keeps the real reason for the failure, not a generic one');

-- system_logs is append-only, same as inventory_logs -----------------------
CALL expect_error('UPDATE system_logs SET message = ''edited'' WHERE log_id = 1',
                   'system_logs rows cannot be updated');
CALL expect_error('DELETE FROM system_logs WHERE log_id = 1',
                   'system_logs rows cannot be deleted');
