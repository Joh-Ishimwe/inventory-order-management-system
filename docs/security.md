# Security and access control

## The idea

Nothing connects as `root` except the build. Each job gets its own account
with the least it needs, and the application gets no direct table access at
all.

## How the application can write without write access

Stored procedures in MySQL run with the privileges of whoever created them.
That is the default, `SQL SECURITY DEFINER`. So a procedure created by an
admin can write to every table even when the account calling it cannot.

That is what makes this possible:

```sql
GRANT EXECUTE ON PROCEDURE place_order TO app_order_service;
-- and no INSERT, UPDATE or DELETE on any table
```

The application can place orders and nothing else. It cannot write a row
directly, cannot change a price, cannot touch the ledger. Every write goes
through code that validates first.

### The catch, and why validation is a security control here

Because the procedure borrows admin privileges, its body is a trust boundary.
A missing check is not just a data-quality bug, it is a way for a limited
account to do something it should not.

The clearest example is `replenish_stock`. Without a check that the quantity is
above zero, an account holding only `EXECUTE` on that one procedure could call
`replenish_stock(3, -1000)` and drain stock to nothing, recorded in the ledger
as a legitimate supplier delivery, using borrowed privileges.

That is why the check is there, and why `adjust_stock` insists on a note: the
one procedure that is allowed to move stock in either direction must say why.

## The roles

### app_order_service
What the application connects as.

- `EXECUTE` on `place_order`, `cancel_order`, `return_order_line`
- `SELECT` on specific columns of `products` (id, name, category, price, stock)
  so it can show a catalogue
- `SELECT` on `v_order_summary`
- No table writes anywhere

Cannot see customer email or phone. Cannot change a price. Cannot write to the
ledger.

### reporting_analyst
Business reporting without personal data.

- `SELECT (customer_id, name, is_active, created_at)` on `customers`
- `SELECT` on all reporting views
- `SELECT` on `business_rules` so numbers in a report can be explained

The grant on `customers` is column-level. `email` and `phone_number` are not
hidden by policy or by remembering to avoid them: the account cannot read
them. `SELECT * FROM customers` fails.

### inventory_manager
Stock, not customers or revenue.

- `SELECT` on `products`, `inventory_logs`, `v_low_stock`,
  `v_stock_reconciliation`
- `EXECUTE` on `replenish_stock` and `adjust_stock`

Cannot see orders or customers.

### auditor
Read the trail, change nothing.

- `SELECT` on `inventory_logs`, `v_stock_reconciliation`, `business_rules`

No personal data, no ability to write. The append-only triggers mean even a
more privileged account cannot rewrite history.

## Views as a privacy boundary

Granting on views rather than base tables gives the views a second job beyond
convenience. `v_order_summary` exposes a customer's name but never their email
or phone, so an analyst working entirely through views cannot reach personal
data even by accident.

## Running it

```bash
python scripts/run_pipeline.py --with-security
```

Or run `sql/security/01_roles_and_grants.sql` directly. It needs an
administrative account, since creating roles and users is privileged.

## Before this goes anywhere real

1. **Change the example passwords.** `sql/security/01_roles_and_grants.sql`
   creates four accounts with obvious placeholders. They exist so the model can
   be demonstrated, not used.
2. **Keep credentials out of the repository.** They belong in `.env`, which is
   gitignored, or in a secrets manager. `.env.example` shows the shape without
   the values.
3. **Point the application at `svc_orders`, not `root`.** Building the schema
   needs admin rights; running the application does not.
4. **Restrict the host.** These accounts are `@'localhost'`. A real deployment
   should name the application host rather than allowing `%`.
5. **Require TLS** for any connection that is not on the same machine.

## What is deliberately not here

- **Row-level security.** MySQL has no built-in row policies. If a future
  requirement is "each regional manager sees only their region", that means a
  region column plus per-region views, or filtering in the application.
- **Column encryption.** Nothing stored here justifies it yet. Payment details
  would change that answer immediately.
- **Audit logging of reads.** The ledger records who changed stock, but not who
  looked at what. That needs MySQL Enterprise Audit or an equivalent.
