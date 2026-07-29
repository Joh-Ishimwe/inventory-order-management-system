USE inventory_order_management;

-- What each order was discounted, split by the two rules that can apply.
-- Reads the stored rates rather than recalculating, so historical orders keep
-- the discount they were actually charged even after the bands change.
CREATE OR REPLACE VIEW v_order_discounts AS
SELECT
    o.order_id,
    c.name                                       AS customer_name,
    DATE(o.placed_at)                            AS order_date,
    o.subtotal_amount                            AS list_price_total,
    -- Earned by buying units in quantity, per line.
    o.bulk_discount_amount,
    -- Earned by the value of the whole order, applied after the bulk one.
    o.order_discount_rate,
    o.order_discount_amount,
    ROUND(o.bulk_discount_amount + o.order_discount_amount, 2) AS total_discount,
    o.total_amount                               AS charged_amount,
    -- The blended saving across the whole order, useful for reporting even
    -- though no single rule was set to this number.
    CASE WHEN o.subtotal_amount > 0
         THEN ROUND(1 - (o.total_amount / o.subtotal_amount), 4)
         ELSE 0 END                              AS effective_discount_rate
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.status <> 'cancelled';
