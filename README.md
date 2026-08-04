# Inventory and Order Management System

A MySQL 8 database for an e-commerce company, with a Python layer that builds
it, loads it, and runs day-to-day jobs against it.

It handles products and stock, customers, orders with any number of products,
returns and cancellations, a full audit trail of every stock movement, and
reporting on spend, discounts and low stock.

---

## What is in here

| Folder | What it holds |
|---|---|
| `sql/schema/` | Tables, keys and constraints |
| `sql/procedures/` | Order placement, returns, cancellations, stock changes |
| `sql/triggers/` | Order totals, status rules, append-only ledger guard |
| `sql/views/` | Reporting views, including the tier and reconciliation views |
| `sql/indexes/` | Indexes, with the reasoning for each one |
| `sql/security/` | Roles, grants and example accounts |
| `sql/seed/` | Sample data, built through the real procedures |
| `src/` | Python: config, logging, database access, pipelines |
| `scripts/` | Command-line entry points |
| `tests/` | Test suites that fail loudly rather than printing results to read |
| `docs/` | Architecture, data dictionary, security, decision record |

---

## Getting started

Needs MySQL 8.0.16 or newer (`CHECK` constraints are only enforced from that
version) and Python 3.10+.

```bash
git clone <your-repo-url>
cd inventory-order-management-system

python -m venv venv
# Windows
.\venv\Scripts\Activate.ps1
# macOS or Linux
source venv/bin/activate

pip install -r requirements.txt

cp .env.example .env        # then put your MySQL password in it
```

Build everything:

```bash
python scripts/run_pipeline.py --with-tests
```

That drops anything existing, creates the schema, procedures, triggers, views
and indexes, loads the sample data, runs all four test suites, and finishes
with a reconciliation check. Any missing folders (`logs/`, `data/…`) are
created automatically, so a fresh clone works with no manual setup.

Add roles and example accounts:

```bash
python scripts/run_pipeline.py --with-security
```

### Running it without Python

Every `.sql` file works on its own in MySQL Workbench or the client. Run them
in the order listed in `src/utils/constants.py`, then `sql/seed/`, then
`tests/`.

---

## Everyday commands

Run these directly in Workbench or any MySQL client — replenishing stock is
a procedure call, not Python:

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
`v_stock_reconciliation` proves the balance and the ledger still agree, and
the build fails if they do not.

**The ledger cannot be edited.** Triggers block `UPDATE` and `DELETE` on
`inventory_logs`. To fix a mistake you post a correcting `ADJUSTMENT`, which
is what an audit trail is for.

**Business numbers live in a table, not in code.** Tier thresholds, the
spending window and discount bands sit in `business_rules` and are read
through one function. Changing the Gold threshold is a single `UPDATE`, and
every report follows immediately. There is a test proving exactly that.

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

## Documentation

- `docs/architecture.md` — the model and why it is shaped this way
- `docs/data_dictionary.md` — every table, column and procedure
- `docs/security.md` — roles, grants and the privilege model
- `docs/decisions.md` — the design decisions, the options rejected, and why

---

## A note on the sample data

Every name, email and phone number is invented. Real customer data does not
belong in a repository: it belongs in the database, behind the access
controls in `sql/security/`.
