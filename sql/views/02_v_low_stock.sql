USE inventory_order_management;

-- Products at or below their reorder point, worst first.
-- Filters on the generated is_low_stock column so an index can be used.
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    product_id,
    name,
    category,
    stock_quantity,
    reorder_level,
    GREATEST(reorder_level - stock_quantity, 0) AS units_below_reorder_point,
    CASE WHEN stock_quantity = 0 THEN 'OUT_OF_STOCK' ELSE 'LOW' END AS severity
FROM products
WHERE is_low_stock = TRUE;
