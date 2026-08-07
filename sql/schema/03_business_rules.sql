-- Configurable business thresholds and rates, seeded as data instead of hardcoded.
USE inventory_order_management;

-- Every tunable business number lives here; changing one is a single UPDATE, not a code edit.
CREATE TABLE business_rules (
    rule_key    VARCHAR(50)    PRIMARY KEY,
    rule_value  DECIMAL(12,4)  NOT NULL,
    description VARCHAR(255)   NOT NULL,
    updated_at  TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP
);

-- All values are placeholders until finance/product confirm the real ones.
INSERT INTO business_rules (rule_key, rule_value, description) VALUES
-- Customer tiers
('tier_window_months',   3.0000,  'How many months of history count toward a tier'),
('tier_gold_min',      100.0000,  'Net spend needed for Gold'),
('tier_silver_min',     50.0000,  'Net spend needed for Silver'),

-- Bulk discount: order more of one product on one line, pay less per unit.
('bulk_t1_min_units',    5.0000,  'Units of one product needed for the first bulk band'),
('bulk_t1_rate',         0.0500,  'First bulk band rate (5%)'),
('bulk_t2_min_units',   10.0000,  'Units needed for the second bulk band'),
('bulk_t2_rate',         0.1000,  'Second bulk band rate (10%)'),
('bulk_t3_min_units',   25.0000,  'Units needed for the third bulk band'),
('bulk_t3_rate',         0.1500,  'Third bulk band rate (15%)'),

-- Order-value discount: a separate reward for total spend, applied after any bulk discount.
('spend_t1_min',        50.0000,  'Order value needed for the first spend band'),
('spend_t1_rate',        0.0500,  'First spend band rate (5%)'),
('spend_t2_min',       100.0000,  'Order value needed for the second spend band'),
('spend_t2_rate',        0.1000,  'Second spend band rate (10%)'),

-- Replenishment: how far above the reorder level a restock brings a product.
('replenishment_buffer_multiplier', 2.0000,
 'Restock target as a multiple of the reorder level');
