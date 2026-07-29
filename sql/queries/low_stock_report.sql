USE inventory_order_management;

-- Flags products at or below their reorder point.
SELECT product_id, name, category, stock_quantity, reorder_level
FROM products
WHERE stock_quantity <= reorder_level
ORDER BY stock_quantity ASC;