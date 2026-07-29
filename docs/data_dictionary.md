\# Data Dictionary — Inventory and Order Management System



\## customers



| Column | Type | Constraints | Description |

|---|---|---|---|

| customer\_id | INT | PK, AUTO\_INCREMENT | Unique identifier for the customer |

| name | VARCHAR(100) | NOT NULL | Customer's full name |

| email | VARCHAR(255) | NOT NULL, UNIQUE | Customer's email; no two customers may share one |

| phone\_number | VARCHAR(20) | nullable | Customer's phone number; optional |

| is\_active | BOOLEAN | NOT NULL, DEFAULT TRUE | Soft-delete flag; FALSE = deactivated account, order history preserved |



\## products



| Column | Type | Constraints | Description |

|---|---|---|---|

| product\_id | INT | PK, AUTO\_INCREMENT | Unique identifier for the product |

| name | VARCHAR(150) | NOT NULL | Product name |

| category | VARCHAR(50) | nullable | Product category (e.g., Electronics, Stationery) |

| price | DECIMAL(10,2) | NOT NULL, CHECK >= 0 | Current list price |

| stock\_quantity | INT | NOT NULL, DEFAULT 0, CHECK >= 0 | Current units in stock |

| reorder\_level | INT | NOT NULL, DEFAULT 0, CHECK >= 0 | Threshold below which the product needs replenishment |



\## orders



| Column | Type | Constraints | Description |

|---|---|---|---|

| order\_id | INT | PK, AUTO\_INCREMENT | Unique identifier for the order |

| customer\_id | INT | NOT NULL, FK -> customers.customer\_id, ON DELETE RESTRICT | Which customer placed the order |

| order\_date | DATE | NOT NULL | Date the order was placed |

| total\_amount | DECIMAL(10,2) | NOT NULL, DEFAULT 0, CHECK >= 0 | Total value of the order, calculated from its line items |

| status | VARCHAR(20) | NOT NULL, DEFAULT 'pending', CHECK IN (...) | One of: pending, shipped, delivered, cancelled, returned |



\## order\_details



Linking table resolving the many-to-many relationship between orders and

products. One row = one product within one order.



| Column | Type | Constraints | Description |

|---|---|---|---|

| order\_detail\_id | INT | PK, AUTO\_INCREMENT | Unique identifier for the line item |

| order\_id | INT | NOT NULL, FK -> orders.order\_id, ON DELETE CASCADE | Which order this line item belongs to |

| product\_id | INT | NOT NULL, FK -> products.product\_id, ON DELETE RESTRICT | Which product this line item is for |

| quantity | INT | NOT NULL, CHECK > 0 | Units of this product ordered |

| unit\_price | DECIMAL(10,2) | NOT NULL, CHECK >= 0 | Price per unit at the time of the order |

| returned\_quantity | INT | NOT NULL, DEFAULT 0, CHECK >= 0, CHECK <= quantity | Units of this line item that were later returned |

| return\_date | DATE | nullable | Date the return was recorded, if any |



\## inventory\_logs



Append-only audit log of every stock change. One row = one stock change event.



| Column | Type | Constraints | Description |

|---|---|---|---|

| log\_id | INT | PK, AUTO\_INCREMENT | Unique identifier for the log entry |

| product\_id | INT | NOT NULL, FK -> products.product\_id, ON DELETE RESTRICT | Which product's stock changed |

| order\_id | INT | nullable, FK -> orders.order\_id, ON DELETE SET NULL | Which order caused this change, if any (NULL for manual replenishment/adjustment) |

| change\_amount | INT | NOT NULL, CHECK <> 0 | Signed stock change: negative = stock removed, positive = stock added |

| reason | VARCHAR(50) | NOT NULL, CHECK IN (...) | One of: ORDER, REPLENISHMENT, RETURN, CANCELLATION, ADJUSTMENT |

| changed\_at | TIMESTAMP | DEFAULT CURRENT\_TIMESTAMP | When the change was recorded |



\## Stored procedures



| Procedure | Parameters | Description |

|---|---|---|

| place\_order | p\_customer\_id INT, p\_product\_id INT, p\_quantity INT | Validates stock availability, then atomically creates an order, its order\_details row, deducts stock, and logs the change. Rejects the entire operation (SIGNAL error, no partial data) if stock is insufficient. |

| replenish\_stock | p\_product\_id INT, p\_quantity INT | Increases a product's stock and logs the change with reason 'REPLENISHMENT'. |

