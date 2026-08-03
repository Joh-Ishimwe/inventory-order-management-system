# Decision record

Each entry is a decision, the options considered, and why one won. Written so
a reviewer can disagree with the reasoning rather than guess at it.

---

## 1. Multi-product orders: one JSON call

**Options.** (a) a JSON array in a single call; (b) three steps — create a
draft, add lines, finalise; (c) a staging table the caller fills, then submits.

**Chosen: (a).**

One call is one transaction, so an order either exists completely or not at
all. The three-step flow can be abandoned halfway, leaving rows that are not a
real order, and then every report and every stock figure has to filter drafts
out forever. That filtering is easy to forget in one place and wrong there
quietly. The staging table has the same problem plus shared-state trouble if
two callers use it at once.

**Cost.** The caller has to build JSON, which is slightly more work than
calling a procedure three times. `JSON_TABLE` also requires MySQL 8.0+, which
this project already requires.

---

## 2. Tiers and totals: computed, not stored

**Options.** (a) store `customer_tier` on `customers` and maintain it with
triggers; (b) compute it on demand in a view.

**Chosen: (b).** The stored version was built first, then removed.

Storing it needed two triggers, a reconciliation procedure and a nightly
scheduled event. The event existed because a tier based on a rolling
three-month window goes stale purely as time passes: no order changes, so no
trigger fires, but the answer is now wrong. A computed view cannot go stale.

The deciding factor was duplication. The stored version had the thresholds
written out in four places — a report query, two triggers, and the
reconciliation procedure. Changing Gold from 100 to 150 meant four edits, and
missing one would produce reports that quietly disagreed. Combined with
`business_rules`, there is now exactly one copy.

Removing it also dropped the event scheduler dependency, which is off by
default, needs `SUPER` to enable, and resets on restart unless it is written
into the server config.

**Cost.** The tier view does slightly more work per query. Not measurable at
this size; on a large customer base, read the thresholds into variables once
instead of calling the function per group.

---

## 3. Discounts are applied, not just displayed

**Options.** (a) show the discount in a report and leave `total_amount` as the
undiscounted figure; (b) store subtotal, rate and charged total on the order.

**Chosen: (b).**

The brief says apply a discount. A report that displays one while the order
records the full price means the discount does not exist as far as the business
is concerned.

Three columns rather than one because a discount that cannot be explained is a
problem in an audit. `subtotal_amount` is what it cost, `discount_rate` is what
was taken off, `total_amount` is what was charged.

**The rate is frozen at placement.** The triggers that keep the subtotal in
step with the line items reuse the stored rate rather than recalculating it, so
raising the discount threshold next quarter does not silently reprice last
quarter's orders. This was a bug in the earlier version: the total-recalculating
trigger overwrote whatever the order procedure had set, which would have erased
any discount the moment one was introduced.

---

## 4. Two discounts, not one: bulk by quantity, then by order value

**Options.** (a) discount per line item, based on units of one product;
(b) discount on the whole order's value; (c) both, applied in sequence.

**Chosen: (c).** An earlier version had only (b), which was a mistake.

The brief says "bulk discounts based on quantity ordered", and that means
units. Implementing it as order value was a deviation dressed up as a design
choice: an order of one expensive item got a "bulk" discount while an order of
twenty cheap ones got nothing, which is the opposite of what a bulk rule is
for.

So the quantity rule is now the primary mechanism and lives where it belongs,
on the line: `order_details.discount_rate`, set from `quantity` against the
`bulk_*` bands. It sits on the line rather than the order because it depends on
how many units of that one product were bought, which is a property of the
line, not the order.

The order-value rule was kept as a second, clearly separate layer, because
rewarding a large order is a real thing a business does and it was already
built. It is applied *after* the bulk discount, on the reduced amount, so the
two do not compound into more than intended.

That makes four money columns on `orders` instead of one:
`subtotal_amount` at list price, `bulk_discount_amount`,
`order_discount_amount`, and `total_amount`. Any charge can be explained by
naming which rule took what off.

**Cost.** More columns, and two sets of bands to keep in `business_rules`.
Worth it: a single blended rate would have made "why was this order 12.4% off?"
unanswerable. `v_order_discounts` exposes the blended rate as a derived figure
for reporting, but nothing is stored that way.

**Still a business decision.** The band values are placeholders. If the real
policy uses cumulative purchase history rather than per-line quantity, the
change is confined to the `trg_order_details_before_insert` trigger and rows
in `business_rules`.

---

## 5. Stock has one owner

**Options.** (a) let each procedure update `products.stock_quantity` and write
its own ledger row; (b) funnel everything through `record_stock_change`.

**Chosen: (b).**

The balance and the ledger are two representations of the same fact, and two
representations drift. One procedure that always does both together means they
cannot. `v_stock_reconciliation` verifies it, and the build fails if it does
not hold.

`record_stock_change` deliberately contains no `COMMIT`, so it can be called
inside a bigger transaction without ending it early. `place_order` calls it
once per line, inside its own transaction.

**Cost.** `place_order` loops over lines and calls a procedure per product
rather than doing one set-based update. Slower in principle, irrelevant for the
handful of items in a real order, and worth it for having one owner.

---

## 6. The ledger is append-only, enforced

**Options.** (a) treat it as append-only by convention; (b) block `UPDATE` and
`DELETE` with triggers.

**Chosen: (b).** An audit trail that can be edited is not an audit trail. The
earlier version documented the intent without enforcing it, which is the same
as not having it.

Consequence: `inventory_logs.order_id` uses `ON DELETE RESTRICT`, not
`SET NULL`. MySQL performs foreign key actions without firing triggers, so
`SET NULL` would have quietly modified a protected row. `RESTRICT` means an
order with stock history cannot be deleted — cancel it instead, which is the
right operation anyway.

---

## 7. Business rules in a table

**Options.** (a) constants in the SQL; (b) a `business_rules` table read
through a function.

**Chosen: (b).** Thresholds are business decisions that change without any
code needing to change. Putting them in a table makes a change one `UPDATE`,
by someone who does not have to be an engineer, and there is a test asserting
that raising the Gold threshold moves a customer down with no code touched.

**Cost.** A key/value table stores everything as `DECIMAL`, including
`tier_window_months`, which is conceptually an integer. Accepted for the
flexibility; the alternative was a typed column per rule and a schema change
every time a rule is added.

---

## 8. Folders organised by artifact type

**Options.** (a) keep everything in `sql/queries/`; (b) split into `schema/`,
`procedures/`, `triggers/`, `views/`, `indexes/`, `security/`, `seed/`.

**Chosen: (b).** The old layout had procedures, triggers and index DDL all
sitting in a folder called `queries/`, which misrepresented the contents:
`order_placement.sql` is not a query. A reviewer should be able to find the
schema without opening files to check what they are.

---

## 9. Python layer included

**Options.** (a) SQL only; (b) SQL plus a Python layer.

**Chosen: (b).**

The database enforces correctness; it cannot do operational robustness. Timeouts
on connections, retrying a deadlock but not a rule violation, structured logs
that can be searched later, and isolating one bad record so a batch survives —
none of that is expressible in SQL.

It also solves a practical problem: `.sql` files with `DELIMITER` cannot be fed
straight to a driver, because `DELIMITER` is a client command rather than SQL.
`split_sql_script` handles it, so the same files work in Workbench and from
Python instead of needing two versions.

**Cost.** More to install and more surface area. Mitigated by every `.sql` file
still working on its own, so the Python layer is a convenience rather than a
requirement.

---

## 10. Access control included

**Options.** (a) leave it out, since the brief does not mention users;
(b) define roles and grants.

**Chosen: (b).** Once anything other than a person at a keyboard connects, an
account with unrestricted rights is a real finding. The model is also what
makes `SQL SECURITY DEFINER` useful: the application gets `EXECUTE` and nothing
else, so every write is forced through validated code.

It also gives the views a second purpose. Column-level grants mean an analyst
cannot read `email` or `phone_number` at all, rather than being trusted not to.

---

## 11. Failing tests fail loudly

**Options.** (a) test scripts that print results for a human to check;
(b) assertions that raise an error.

**Chosen: (b).** The earlier tests were comments saying "expect X" next to a
query. Nothing failed when the expectation was wrong; someone had to notice.
`assert_equals` and `expect_error` raise, so a wrong result stops the run and
`run_pipeline.py --with-tests` returns a non-zero exit code.

**Consequence.** The tests call the real procedures rather than mocking them
— the only way to actually prove `place_order` and the rest work — which
means the run creates real orders and ledger rows. Wrapping the suite in one
transaction and rolling it back afterward will not undo this: `place_order`,
`cancel_order` and the rest each open and commit their own transaction, and
starting a transaction while one is already open implicitly commits it, so
an outer `ROLLBACK` has nothing left to undo. `inventory_logs` is
append-only regardless (decision 6), so those rows could not be deleted
either way. Rebuild the database after a `--with-tests` run rather than
treating it as a no-op.

---

## 12. Replenishment: computed and applied in SQL

**Options.** (a) work out the restock quantity in Python, then loop over
products and call `replenish_stock` once per row; (b) compute the quantity in
a view and apply the whole plan through one stored procedure.

**Chosen: (b).** The restock math (target as a multiple of the reorder level)
and the "apply every low product, keep going if one fails" loop were both
originally in Python. Neither needs to be: the math is one expression over
`v_low_stock`, and the loop is a cursor. Moving both into SQL means
`v_replenishment_plan` and `replenish_all` are, like everything else,
reviewable and runnable on their own in Workbench, with no Python required to
see them work. Python's role shrank to calling one of the two and printing
what came back.

The buffer multiplier itself moved into `business_rules` rather than staying
a Python CLI default, for the same reason every other threshold is there:
changing it is one `UPDATE`, not a code or flag change.

**Cost.** `replenish_all` uses a cursor and a per-row exception handler to
keep one failing product from losing the rest of the batch — more moving
parts than a Python `try/except` in a loop. Accepted because it means the
batch-apply behaviour exists even when nothing but a `.sql` client is
present.

---

## 13. Seed data built through the real procedures

**Options.** (a) insert stock levels and order totals directly; (b) start
products at zero and move every unit through `record_stock_change`, place
returns and cancellations through their procedures.

**Chosen: (b).**

The earlier seed had a genuine inconsistency: an order recorded a total of
15.98 while its single line was 2 × 15.99 = 31.98, and the ledger rows did not
add up to the stock levels beside them. Hand-written data drifts from its own
rules.

Building it through the real code paths means it cannot be inconsistent, and it
doubles as a working demonstration of every procedure. Dates are relative to
today rather than fixed, so the rolling tier window keeps working however long
from now this is run.
