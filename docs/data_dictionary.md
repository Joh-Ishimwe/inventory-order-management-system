# Data dictionary

Every table, column, procedure and view. Keep this file in step with
`sql/schema/` — a dictionary that has drifted is worse than none.

---

## business_rules

Configuration. Every tunable business number lives here so it exists in one
place instead of being spread through queries and procedure bodies.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| rule_key | VARCHAR(50) | PK | Name of the rule |
| rule_value | DECIMAL(12,4) | NOT NULL | Its value |
| description | VARCHAR(255) | NOT NULL | What it controls |
| updated_at | TIMESTAMP | auto | When it last changed |

Seeded keys (all placeholders until finance confirm them):

| Key | Default | Meaning |
|---|---|---|
| tier_window_months | 3 | Months of history counted toward a tier |
| tier_gold_min | 100.00 | Net spend needed for Gold |
| tier_silver_min | 50.00 | Net spend needed for Silver |
| bulk_t1_min_units | 5 | Units of one product for the first bulk band |
| bulk_t1_rate | 0.05 | First bulk band rate |
| bulk_t2_min_units | 10 | Units for the second bulk band |
| bulk_t2_rate | 0.10 | Second bulk band rate |
| bulk_t3_min_units | 25 | Units for the third bulk band |
| bulk_t3_rate | 0.15 | Third bulk band rate |
| spend_t1_min | 50.00 | Order value for the first spend band |
| spend_t1_rate | 0.05 | First spend band rate |
| spend_t2_min | 100.00 | Order value for the second spend band |
| spend_t2_rate | 0.10 | Second spend band rate |
| replenishment_buffer_multiplier | 2.0 | Restock target as a multiple of the reorder level |

Bulk bands apply per line, by unit count. Spend bands apply to the whole order,
after bulk discounts.

---

## customers

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| customer_id | INT | PK, AUTO_INCREMENT | Identifier |
| name | VARCHAR(100) | NOT NULL | Full name |
| email | VARCHAR(255) | NOT NULL, UNIQUE, shape CHECK | Email; no two customers share one |
| phone_number | VARCHAR(20) | nullable | Optional |
| is_active | BOOLEAN | NOT NULL, default TRUE | Soft delete. FALSE retires the account and keeps its history |
| created_at | TIMESTAMP | auto | Row created |
| updated_at | TIMESTAMP | auto on update | Row last changed |

Customers are never deleted. `place_order` refuses orders from inactive ones.

---

## products

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| product_id | INT | PK, AUTO_INCREMENT | Identifier |
| name | VARCHAR(150) | NOT NULL | Product name |
| category | VARCHAR(50) | nullable, indexed | Grouping for reports |
| price | DECIMAL(10,2) | NOT NULL, >= 0 | Current list price |
| stock_quantity | INT | NOT NULL, >= 0 | Running balance. Only `record_stock_change` may change it |
| reorder_level | INT | NOT NULL, >= 0 | Below this, the product needs restocking |
| is_low_stock | BOOLEAN | generated stored, indexed | `stock_quantity <= reorder_level`, precomputed so it can be indexed |
| created_at | TIMESTAMP | auto | Row created |
| updated_at | TIMESTAMP | auto on update | Row last changed |

`DECIMAL` for price, never `FLOAT`. Floats store most decimal fractions
approximately, and small errors accumulate. Unacceptable for money.

---

## orders

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| order_id | INT | PK, AUTO_INCREMENT | Identifier |
| customer_id | INT | NOT NULL, FK to customers, RESTRICT | Who placed it |
| placed_at | DATETIME | NOT NULL, default now, not future | When. DATETIME because TIMESTAMP stops at 2038 |
| subtotal_amount | DECIMAL(10,2) | NOT NULL, >= 0 | Line items at list price. Maintained by trigger |
| bulk_discount_amount | DECIMAL(10,2) | NOT NULL, >= 0 | Total taken off by the per-line quantity discounts |
| order_discount_rate | DECIMAL(5,4) | NOT NULL, 0 to <1 | Order-value band, fixed when the order was placed |
| order_discount_amount | DECIMAL(10,2) | NOT NULL, >= 0 | Cash taken off by the order-value band |
| total_amount | DECIMAL(10,2) | NOT NULL, >= 0 | What was charged, after both discounts |

Money flows: `subtotal_amount` − `bulk_discount_amount` − `order_discount_amount`
= `total_amount`.

There is no stored `order_date` column. The views derive `DATE(placed_at)` and
expose it under that name — see architecture.md for why.
| status | VARCHAR(20) | NOT NULL, CHECK, transition trigger | pending, shipped, delivered, cancelled, returned |
| created_at | TIMESTAMP | auto | Row created |
| updated_at | TIMESTAMP | auto on update | Row last changed |

Allowed status moves: `pending → shipped/cancelled`,
`shipped → delivered/cancelled`, `delivered → returned`. Cancelled and
returned are final.

---

## order_details

Resolves the many-to-many between orders and products. One row is one product
inside one order.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| order_detail_id | INT | PK, AUTO_INCREMENT | Identifier |
| order_id | INT | NOT NULL, FK to orders, CASCADE | Parent order |
| product_id | INT | NOT NULL, FK to products, RESTRICT | Product ordered |
| quantity | INT | NOT NULL, > 0 | Units ordered |
| unit_price | DECIMAL(10,2) | NOT NULL, >= 0 | Price at order time, copied not looked up |
| discount_rate | DECIMAL(5,4) | NOT NULL, 0 to <1 | Bulk discount for this line, set from quantity on insert |
| returned_quantity | INT | NOT NULL, 0 to quantity | Units sent back |
| return_date | DATE | nullable, CHECK paired with returned_quantity | When the return happened |
| created_at | TIMESTAMP | auto | Row created |
| updated_at | TIMESTAMP | auto on update | Row last changed |

`UNIQUE (order_id, product_id)`: one line per product per order. Two lines for
the same product would double-count and break the returns arithmetic.

`unit_price` is a snapshot. If the catalogue price changes tomorrow, this order
still shows what the customer actually paid.

---

## inventory_logs

Append-only ledger of stock movement. Every row is one movement, and rows are
never edited or removed.

| Column | Type | Constraints | Meaning |
|---|---|---|---|
| log_id | INT | PK, AUTO_INCREMENT | Identifier |
| product_id | INT | NOT NULL, FK to products, RESTRICT | Product affected |
| order_id | INT | nullable, FK to orders, RESTRICT | Order that caused it, if any |
| change_amount | INT | NOT NULL, <> 0 | Signed: negative removes, positive adds |
| reason | VARCHAR(20) | NOT NULL, CHECK | Why (below) |
| note | VARCHAR(255) | nullable | Free text, e.g. a purchase order number |
| changed_at | TIMESTAMP | auto | When |

Reasons: `INITIAL` (opening stock), `ORDER` (sale), `REPLENISHMENT` (supplier
delivery), `RETURN` (customer sent it back), `CANCELLATION` (order cancelled,
stock released), `ADJUSTMENT` (stocktake, breakage, write-off).

`SUM(change_amount)` per product must equal `products.stock_quantity`.
`v_stock_reconciliation` checks it.

---

## Function

| Function | Returns | Purpose |
|---|---|---|
| get_rule(rule_key) | DECIMAL(12,4) | The only way anything reads a business threshold. Raises an error on an unknown key rather than returning null |

---

## Procedures

| Procedure | Parameters | What it does |
|---|---|---|
| record_stock_change | product_id, change_amount, reason, order_id, note | The only thing allowed to change stock. Locks the row, refuses a move that would go below zero, updates the balance and writes the ledger row. Has no COMMIT, so it can be called inside a larger transaction |
| apply_order_discount | order_id | Works out the order-value band from the amount after bulk discounts, and stores the rate, the cash amount and the charged total. Called once, at placement |
| recalc_order_money | order_id | Rebuilds an order's four money columns from its current lines. Called by the order_details triggers so the arithmetic exists in one place |
| place_order | customer_id, items JSON, OUT order_id | Places an order with any number of products, in one transaction. Validates the payload and the customer, locks products in id order to avoid deadlocks, refuses insufficient stock with a message naming the product, adds every line, moves stock, then applies the discount |
| cancel_order | order_id, note | Cancels a pending or shipped order and releases the stock the customer still holds. Refuses a delivered order |
| return_order_line | order_detail_id, quantity, return_date, note | Returns some or all units of one line on a delivered order. Refuses more than is outstanding, or a date before the order. Marks the whole order returned once nothing is outstanding |
| replenish_stock | product_id, quantity, note | Records a supplier delivery. Refuses a quantity of zero or less |
| adjust_stock | product_id, change_amount, note | Corrects stock after a stocktake or write-off. Can go either way, and requires a note |
| replenish_all | note | Applies the whole restock plan in v_replenishment_plan, one product at a time. A product that fails is recorded FAILED and the rest of the batch still runs. Returns one row per product attempted |
| assert_equals | actual, expected, label | Test helper. Raises an error when they differ |
| expect_error | sql, label | Test helper. Runs a statement expecting it to fail, and fails the test if it succeeded |

### place_order payload

```json
[{"product_id": 1, "quantity": 2}, {"product_id": 6, "quantity": 3}]
```

A product listed more than once is merged into a single line.

---

## Views

| View | One row per | Notes |
|---|---|---|
| v_order_summary | Order | Customer, date, status, list price, both discounts, charged amount, line count, units ordered and returned, refunded and net amount. Cancelled orders excluded |
| v_order_line_detail | Order line | Product, quantity, unit price, the bulk rate that line earned and the cash it saved. Where the quantity rule is visible |
| v_low_stock | Low product | Units below the reorder point, plus LOW or OUT_OF_STOCK. Filters on the indexed generated column |
| v_customer_tiers | Customer | Net spend in the window, order count, Bronze/Silver/Gold. Includes customers with no orders. Thresholds read from business_rules |
| v_order_discounts | Order | Bulk and order-value discounts side by side, their total, and a derived blended rate for reporting. Reads stored rates so history is stable |
| v_stock_reconciliation | Product | Balance against ledger sum, difference, and is_balanced. Anything but TRUE is a bug |
| v_replenishment_plan | Low product | v_low_stock plus a suggested restock quantity, from replenishment_buffer_multiplier. What replenish_all applies |

---

## Indexes

| Index | Columns | Why |
|---|---|---|
| idx_orders_status | status | Every report filters on it |
| idx_orders_customer_placed | customer_id, placed_at | "This customer, recent orders". Leftmost prefix also serves customer_id alone |
| idx_orders_placed_at | placed_at | Date-range reporting across all customers |
| idx_products_low_stock | is_low_stock | Turns the low-stock view into a lookup |
| idx_products_category | category | Browsing by category |
| idx_logs_product_changed | product_id, changed_at | One product's history over a date range |

Not indexed on purpose: foreign key columns. MySQL indexes those
automatically, so repeating them would only duplicate work.
