USE inventory_order_management;

-- TEST 1: Valid order should succeed and correctly deduct stock
CALL place_order(3, 2, 2);
-- Expect: new order row, new order_detail row, products.stock_quantity for id=2 reduced by 2

-- TEST 2: Order exceeding available stock should be rejected entirely
CALL place_order(1, 3, 100);
-- Expect: error 'Insufficient stock for this product', no new rows anywhere

-- TEST 3: Replenishment should increase stock and log it
CALL replenish_stock(3, 50);
-- Expect: products.stock_quantity for id=3 increased by 50, new inventory_logs row with reason='REPLENISHMENT'