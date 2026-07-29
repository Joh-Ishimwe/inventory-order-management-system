\# Architecture — Inventory and Order Management System



\## Overview

This system tracks products, customers, orders, and inventory changes for an

e-commerce business. It is built in MySQL 8.0, using InnoDB as the storage

engine (required for foreign key enforcement and transactions).



\## Entity Relationship Diagram



customers ||--o{ orders : places

orders ||--o{ order\_details : contains

products ||--o{ order\_details : "appears in"

products ||--o{ inventory\_logs : "tracked by"

orders ||--o{ inventory\_logs : "may trigger"



\- \*\*Customers -> Orders\*\*: one-to-many. One customer can place many orders;

&#x20; each order belongs to exactly one customer.

\- \*\*Orders <-> Products\*\*: many-to-many, resolved via the `order\_details`

&#x20; linking table. One order can contain many products; one product can appear

&#x20; in many orders. Neither relationship fits in a single foreign key column,

&#x20; which is why `order\_details` exists as its own table with two foreign keys.

\- \*\*Products -> Inventory Logs\*\*: one-to-many. Every stock change is tied to

&#x20; exactly one product.

\- \*\*Orders -> Inventory Logs\*\*: one-to-many, but optional (nullable FK). A

&#x20; stock change caused by a customer order links back to that order; a manual

&#x20; replenishment or adjustment has `order\_id = NULL` since no order caused it.



\## Design decisions and their reasoning



\### Soft delete on customers (`is\_active`)

Customers are never physically deleted. Deleting a customer with existing

orders would either be blocked (if `ON DELETE RESTRICT`, our actual setting)

or would silently destroy order history (if `ON DELETE CASCADE`). Instead,

`is\_active = FALSE` marks an account inactive while preserving all historical

orders for audit/reporting purposes. Standard practice for any system where

past transactional data has ongoing business value.



\### Partial returns (`order\_details.returned\_quantity`)

A customer may return only some of the units they ordered on a line item

(e.g., ordered 5, returned 2). `returned\_quantity` tracks this at the

individual line-item level rather than the whole-order level, since returns

are naturally a per-product event. Enforced with

`CHECK (returned\_quantity <= quantity)` so a return can never exceed what was

actually ordered.



\### Order status lifecycle

`orders.status` is constrained to: `pending`, `shipped`, `delivered`,

`cancelled`, `returned`. This was added after reviewing the schema and

noticing there was no way to represent a cancelled or returned order — the

original design only supported the "happy path."



\### Non-negative stock (`CHECK (stock\_quantity >= 0)`)

A database-level safety net preventing negative stock, in addition to the

application-level check performed by the `place\_order` procedure before

accepting an order. Two layers are intentional: the procedure gives customers

a clean rejection message; the CHECK constraint protects data integrity even

if application logic has a bug or two requests race each other.



\### Inventory logs as an append-only ledger

`inventory\_logs` never gets updated or deleted (by design, not currently

enforced with a trigger) — every stock change, whether from a sale, a

cancellation, a return, a manual replenishment, or a stock adjustment, is

recorded as a new row. This satisfies the spec's requirement for "a full

history of inventory changes... retrievable for auditing purposes." The

`reason` column (`ORDER`, `REPLENISHMENT`, `RETURN`, `CANCELLATION`,

`ADJUSTMENT`) distinguishes why each change happened without needing to infer

it from `order\_id` being null or not.



\### Order placement as a stored procedure with transactions

`place\_order` wraps order creation, stock deduction, and logging in a single

`START TRANSACTION` / `COMMIT` block, so a failure partway through leaves no

partial data. Stock sufficiency is checked with `SELECT ... FOR UPDATE`

before any writes happen, and insufficient stock triggers a `SIGNAL` that

aborts the whole operation cleanly. This directly satisfies "deduct the

correct quantity from stock" and "ensure the system can handle multiple

products in a single order" from the Phase 2 spec (repeating the same

insert/update/log block once per product line).



\### Reporting: LEFT JOIN vs JOIN

Order/spending reports use `LEFT JOIN` from `customers` so that customers

with zero orders still appear (e.g., with $0 spent, Bronze tier), rather than

silently disappearing from business reports. Discount reporting uses a plain

`JOIN` from `orders`, since that report is specifically about orders that

exist.



\### Business rule placeholders (Phase 3)

The following thresholds are illustrative placeholders, clearly documented as

such and easy to change in one place, pending real numbers from a product or

finance stakeholder:

\- Customer tier thresholds (Gold >= $100, Silver >= $50, evaluated over a

&#x20; trailing 3-month window)

\- Order-level discount thresholds (10% at $100+, 5% at $50+)



Cancelled orders are excluded from all spending calculations. Returned

quantities reduce a customer's counted net spending, since that revenue was

not actually retained.

