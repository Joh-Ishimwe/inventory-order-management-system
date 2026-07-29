USE inventory_order_management;

-- Line-by-line view of an order, showing the bulk discount each line earned.
-- This is where the quantity-based rule is visible: two lines of the same
-- product at different quantities get different rates.
CREATE OR REPLACE VIEW v_order_line_detail AS
SELECT
    od.order_detail_id,
    od.order_id,
    DATE(o.placed_at)                                        AS order_date,
    p.product_id,
    p.name                                                   AS product_name,
    p.category,
    od.quantity,
    od.unit_price,
    ROUND(od.quantity * od.unit_price, 2)                    AS line_list_price,
    od.discount_rate                                         AS bulk_discount_rate,
    ROUND(od.quantity * od.unit_price * od.discount_rate, 2)  AS bulk_discount_amount,
    ROUND(od.quantity * od.unit_price * (1 - od.discount_rate), 2) AS line_after_bulk,
    od.returned_quantity,
    od.return_date
FROM order_details od
JOIN orders   o ON o.order_id   = od.order_id
JOIN products p ON p.product_id = od.product_id;
