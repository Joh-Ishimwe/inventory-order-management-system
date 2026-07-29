USE inventory_order_management;

-- Order summary per customer: date, total amount (net of returns), item count.
-- Includes ALL customers, even those with zero orders (LEFT JOIN).
-- Cancelled orders excluded; returned quantities reduce the counted total.

SELECT
    c.customer_id,
    c.name AS customer_name,
    o.order_id,
    o.order_date,
    ROUND(o.total_amount, 2) AS order_total,
    ROUND(SUM(od.returned_quantity * od.unit_price), 2) AS returned_value,
    ROUND(o.total_amount - SUM(od.returned_quantity * od.unit_price), 2) AS net_amount,
    COUNT(od.order_detail_id) AS number_of_items
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id AND o.status != 'cancelled'
LEFT JOIN order_details od ON o.order_id = od.order_id
GROUP BY c.customer_id, c.name, o.order_id, o.order_date, o.total_amount
ORDER BY c.customer_id, o.order_date;