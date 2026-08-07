# Inventory and Order Management System

A MySQL 8 database for an e-commerce company: products and stock, customers,
orders with any number of products, returns and cancellations, a full audit
trail of every stock movement, and reporting on spend, discounts and low
stock.

---

## What is in here

| Folder | What it holds |
|---|---|
| `sql/schema/` | Tables, keys and constraints |
| `sql/procedures/` | Order placement, returns, cancellations, stock changes |
| `sql/triggers/` | Order totals, status rules, append-only ledger guard |
| `sql/views/` | Reporting views, including the tier and reconciliation views |
| `sql/indexes/` | Indexes, with the reasoning for each one |
| `sql/seed/` | Sample data, built through the real procedures |
| `sql/run_all.sql` | Master script that builds everything in order |
| `tests/` | SQL test suites for constraints, procedures and reconciliation |

---

## Getting started

Needs MySQL 8.0.16 or newer (`CHECK` constraints are only enforced from that
version).

One file builds everything — schema, procedures, triggers, views, indexes,
seed data:

```bash
mysql -u root -p < sql/run_all.sql
```

or, inside Workbench or an open client session:

```sql
SOURCE sql/run_all.sql;
```

It creates the database, so a fresh instance needs no manual setup beyond
having MySQL running. See `sql/run_all.sql` for the file order if you'd
rather run each step by hand.

Tests are separate, since they call the real procedures and leave rows
behind: run `tests/00_test_helpers.sql`, then `01`, `02`, `03` in order.

---

## Entity relationships

Full column-level detail lives in [doc/architecture.md](doc/architecture.md)
and is kept in step with the schema there; this is the same diagram, so the
two never drift apart.

![Entity relationship diagram](doc/inventory_order_management_erd.png)

## Architecture

Business rules feed the procedures and triggers that are the only path to
the tables; nothing else writes to them. Views sit on top for reporting, and
everything is reached through a normal MySQL client — there is no separate
application layer.

---

## Everyday commands

```sql
-- Low stock report
SELECT * FROM v_low_stock;

-- The restock plan (quantity computed from business_rules)
SELECT * FROM v_replenishment_plan;

-- Apply the whole plan in one call
CALL replenish_all('Scheduled restock');
```

---

## How it works

**Orders can hold any number of products.** `place_order` takes a JSON array:

```sql
CALL place_order(2, '[{"product_id":1,"quantity":2},
                      {"product_id":6,"quantity":3}]', @order_id);
```

It runs as one transaction. Either the whole order lands or none of it does,
so there is never a half-built order to clean up.

**Stock has one owner.** Only `record_stock_change` touches
`products.stock_quantity`, and it always writes a matching ledger row.
`v_stock_reconciliation` proves the balance and the ledger still agree.

**The ledger cannot be edited.** Triggers block `UPDATE` and `DELETE` on
`inventory_logs`. To fix a mistake you post a correcting `ADJUSTMENT`, which
is what an audit trail is for.

**Business numbers live in a table, not in code.** Tier thresholds, the
spending window and discount bands sit in `business_rules` and are read
through one function. Changing the Gold threshold is a single `UPDATE`, and
every report follows immediately.

**Tiers are worked out on demand.** Nothing is stored, so a tier can never go
stale, and the rules exist in one place instead of several.

**Two discounts, both really applied.** A bulk discount by unit count, set per
line from the quantity of that product, then an order-value discount on the
reduced amount. `orders` carries the list price, both discount amounts and the
charged total, so any figure can be explained. Both rates freeze at placement,
so changing the bands later does not reprice old orders.

---

## Reports

| View | Answers |
|---|---|
| `v_order_summary` | Per order: customer, date, charged amount, line count, what came back |
| `v_low_stock` | What needs reordering, and how badly |
| `v_customer_tiers` | Bronze, Silver or Gold, with the spend behind it |
| `v_order_discounts` | Both discounts per order, their total, and the blended rate |
| `v_order_line_detail` | Line by line, with the bulk discount each line earned |
| `v_stock_reconciliation` | Whether stock balances still match the ledger |
| `v_replenishment_plan` | Low-stock products plus the restock quantity `replenish_all` would apply |

---

## A note on the sample data

Every name, email and phone number is invented. No real customer data.
