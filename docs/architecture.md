# Architecture

MySQL 8 on InnoDB. InnoDB is not optional here: it is what enforces foreign
keys and supports transactions, and the whole design leans on both.

## The model

```
customers ||--o{ orders : places
orders    ||--o{ order_details : contains
products  ||--o{ order_details : "appears in"
products  ||--o{ inventory_logs : "movements of"
orders    ||--o{ inventory_logs : "may have caused"
business_rules : standalone configuration
```

**Customers to orders is one-to-many.** One customer places many orders; each
order belongs to exactly one customer. The foreign key sits on `orders`, the
"many" side, because a single column there can hold the one customer it needs.

**Orders to products is many-to-many.** An order holds many products, and a
product appears in many orders. Neither direction fits in one column, so they
meet in `order_details`. Each row there is one product inside one order, which
is also the natural home for `quantity`, `unit_price` and `returned_quantity`:
those describe the pairing, not the order or the product on its own.

**Products to inventory_logs is one-to-many.** Every movement concerns exactly
one product.

**Orders to inventory_logs is one-to-many and optional.** A movement caused by
a sale points back to its order. A supplier delivery or a stocktake correction
has no order, so `order_id` is null.

## Design decisions

### Stock has exactly one owner

`products.stock_quantity` is a running balance; `inventory_logs` is the ledger
behind it. Two representations of the same fact can drift apart, so only one
procedure, `record_stock_change`, is allowed to write either. It updates the
balance and writes the ledger row together, in the caller's transaction.

`v_stock_reconciliation` compares the two. If a row shows `is_balanced = FALSE`,
something bypassed the procedure. The build fails on that, and the test suite
asserts it is zero.

That is also why the seed data never types a stock number in. Products start
at zero and every unit arrives through `record_stock_change`, so the ledger
and the balances agree by construction rather than by luck.

### The ledger is genuinely append-only

`BEFORE UPDATE` and `BEFORE DELETE` triggers on `inventory_logs` raise an
error. Corrections are made by posting a balancing `ADJUSTMENT` row, which
leaves both the mistake and the fix visible.

This is also why `inventory_logs.order_id` uses `ON DELETE RESTRICT` rather
than `SET NULL`. MySQL carries out foreign key actions without firing
triggers, so `SET NULL` would quietly rewrite a row the guard is meant to
protect. `RESTRICT` means an order with stock history cannot be deleted at
all: cancel it instead, which is the correct operation anyway.

### Business rules live in a table

Tier thresholds, the spending window and discount bands are rows in
`business_rules`, read through the `get_rule()` function. Nothing hard-codes
a threshold.

This replaced an earlier version where the tier thresholds appeared in four
separate places: a report query, two triggers and a reconciliation procedure.
Changing Gold from 100 to 150 meant four edits and a real chance of missing
one. Now it is one `UPDATE`, and `tests/02_test_procedures.sql` proves the
change flows through with no code touched.

### Tiers are computed, not stored

`v_customer_tiers` works the tier out on demand from `v_order_summary`.

The alternative was a `customer_tier` column kept up to date by triggers. That
was built first and then removed. It needed two triggers, a reconciliation
procedure and a scheduled event, because a tier based on a rolling three-month
window goes stale as time passes with no order event to notice. Computing it
on demand cannot go stale, needs none of that machinery, and keeps the rules
in one place. At this data size the cost is not measurable.

Removing it also dropped a dependency on MySQL's event scheduler, which is off
by default, needs `SUPER` to switch on, and resets on server restart unless
it is set in the config file.

### Order money is broken into four columns

`subtotal_amount` (list price), `bulk_discount_amount`,
`order_discount_amount` and `total_amount`. Storing only the final figure
loses the reason for it, and a discount that cannot be explained is a problem
in an audit.

Two rules can apply, in this order:

1. **Bulk discount, by quantity.** Set per line, from the number of units of
   that one product, against the `bulk_*` bands. It lives on
   `order_details.discount_rate` because it depends on the line, not the
   order. A `BEFORE INSERT` trigger sets it, so the rule holds whether the
   line came from `place_order`, the seed script, or a manual insert.
2. **Order-value discount.** A separate reward for the size of the whole
   order, from the `spend_*` bands, applied by `apply_order_discount` to the
   amount *after* bulk discounts so the two do not compound.

Both rates are frozen when the order is placed. `recalc_order_money`, which
the `order_details` triggers call to keep the header in step with the lines,
reuses the stored `order_discount_rate` rather than recalculating it, and the
line rate is only ever set on insert. Editing an old order therefore does not
reprice it against today's bands.

`v_order_discounts` reports a blended `effective_discount_rate` for
convenience, but nothing is stored that way: the two rules stay separable.

### Orders are placed in one call

`place_order` takes a JSON array of items and does everything inside a single
transaction: validate, lock, create the order, add every line, move the stock,
write the ledger, apply the discount.

The alternative was a three-step flow (create a draft, add lines, finalise).
It was rejected because a draft can be abandoned halfway, leaving rows that
are not a real order and that every report then has to filter out. One atomic
call has no such state.

Products are locked in ascending `product_id` order. If every caller locks in
the same order, two concurrent orders touching the same products cannot
deadlock each other.

A product listed twice in one payload is merged into a single line rather than
rejected, which is what the unique constraint on `(order_id, product_id)`
requires and what a caller would expect.

### Two layers of protection, on purpose

`place_order` checks stock and returns a clear message so a customer sees
"only 3 available". `CHECK (stock_quantity >= 0)` is the safety net beneath it.
The first exists for the experience, the second because application code has
bugs and races happen.

### Status cannot move backwards

A trigger allows only `pending → shipped/cancelled`,
`shipped → delivered/cancelled` and `delivered → returned`. Cancelled and
returned are final. Without this, a delivered order could be flipped back to
pending and quietly corrupt every report built on status.

### Soft delete

Customers are never removed. `is_active = FALSE` retires an account while its
order history stays intact for accounting. `ON DELETE RESTRICT` on
`orders.customer_id` makes deleting a customer with orders impossible, which
is the intended outcome rather than an inconvenience.

`place_order` refuses orders from inactive customers, so the flag actually
does something rather than sitting there unused.

### Time is stored properly, and order_date is derived

`orders.placed_at` is `DATETIME`, not `TIMESTAMP`, because `TIMESTAMP` stops
working after 2038. A full timestamp also means two orders on the same day can
still be put in order.

Day-level `order_date` is derived in the views as `DATE(placed_at)` rather than
stored as a generated column. It was a `STORED` generated column at first, and
that failed: MySQL evaluates a stored generated column against the row before a
`BEFORE INSERT` trigger has finished with it, and `orders` has one, so every
insert produced `'0000-00-00'` and error 1292.

`products.is_low_stock` is still a stored generated column and works fine,
because `products` has no trigger. That contrast is the whole explanation.

Deriving it in the views costs nothing here: the views alias it as `order_date`
so callers see the same thing, and the date-range index sits on `placed_at`,
which serves the same queries.

### The low stock filter is indexable

`WHERE stock_quantity <= reorder_level` compares two columns, and no index can
serve that: it is always a full table scan. `products.is_low_stock` is a
generated stored column holding the comparison, and it is indexed, so
`v_low_stock` is a lookup rather than a scan.

### Indexes are chosen, not sprinkled

Only columns real queries filter, join or sort on are indexed, because indexes
slow writes down and take space. Foreign key columns are deliberately left
alone: MySQL indexes them automatically, and adding them again just duplicates
work. `sql/indexes/01_indexes.sql` says so in a comment, so the omission reads
as a decision rather than an oversight.

## Known limits

- **An order with no line items is possible at the table level.** MySQL has no
  deferred constraints, so "an order must have at least one line" cannot be a
  constraint. `place_order` enforces it; direct inserts could break it.
- **Returns beyond a time limit are not restricted.** Any delivered order can
  be returned, however old. A real returns window belongs in `business_rules`.
- **Partial fulfilment is not supported.** An order for five units when three
  are in stock is rejected outright rather than partially filled or
  backordered. Rejecting is the safer default; backorders are a product
  decision, not a technical one.
- **`v_customer_tiers` calls a function per row group.** Correct, and fine at
  this size. On a large customer base it would be worth reading the thresholds
  into variables once instead.
