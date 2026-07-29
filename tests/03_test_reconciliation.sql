USE inventory_order_management;

-- The single most valuable check in the project. If the running balance on
-- products ever stops matching the ledger in inventory_logs, something
-- changed stock without going through record_stock_change.
--
-- Run this after the other suites, so it also covers the changes they made.

SELECT '--- reconciliation ---' AS suite;

SELECT CAST(COUNT(*) AS CHAR) INTO @out_of_balance
FROM v_stock_reconciliation WHERE is_balanced = FALSE;

CALL assert_equals(@out_of_balance, '0', 'every product balance matches its ledger');

-- Show the working, so the number can be eyeballed as well as asserted.
SELECT * FROM v_stock_reconciliation ORDER BY product_id;
