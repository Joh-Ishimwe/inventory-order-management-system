USE inventory_order_management;

-- Health check. products.stock_quantity is a running balance;
-- inventory_logs is the ledger behind it. They must agree.
--
-- Any row where is_balanced = FALSE means something changed stock without
-- going through record_stock_change, which is a bug worth chasing.
CREATE OR REPLACE VIEW v_stock_reconciliation AS
SELECT
    p.product_id,
    p.name,
    p.stock_quantity                              AS balance_on_product,
    COALESCE(SUM(l.change_amount), 0)             AS sum_of_ledger,
    p.stock_quantity - COALESCE(SUM(l.change_amount), 0) AS difference,
    (p.stock_quantity = COALESCE(SUM(l.change_amount), 0)) AS is_balanced
FROM products p
LEFT JOIN inventory_logs l ON l.product_id = p.product_id
GROUP BY p.product_id, p.name, p.stock_quantity;
