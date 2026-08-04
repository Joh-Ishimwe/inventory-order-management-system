USE inventory_order_management;

-- Four roles, each given the least it needs; procedures run as their creator (SQL SECURITY DEFINER),
-- so an account can be granted EXECUTE only and still have its writes go through validated code.

CREATE ROLE IF NOT EXISTS app_order_service;
CREATE ROLE IF NOT EXISTS reporting_analyst;
CREATE ROLE IF NOT EXISTS inventory_manager;
CREATE ROLE IF NOT EXISTS auditor;

-- app_order_service: what the application connects as. EXECUTE only, zero table privileges.
GRANT EXECUTE ON PROCEDURE inventory_order_management.place_order        TO app_order_service;
GRANT EXECUTE ON PROCEDURE inventory_order_management.cancel_order       TO app_order_service;
GRANT EXECUTE ON PROCEDURE inventory_order_management.return_order_line  TO app_order_service;
-- Needs to read the catalogue to show it, but must not change prices.
GRANT SELECT (product_id, name, category, price, stock_quantity)
    ON inventory_order_management.products TO app_order_service;
GRANT SELECT ON inventory_order_management.v_order_summary TO app_order_service;

-- reporting_analyst: business reporting, no personal data — column-level grant makes email/phone_number unreachable, not just hidden by habit.
GRANT SELECT (customer_id, name, is_active, created_at)
    ON inventory_order_management.customers TO reporting_analyst;
GRANT SELECT ON inventory_order_management.v_order_summary   TO reporting_analyst;
GRANT SELECT ON inventory_order_management.v_customer_tiers  TO reporting_analyst;
GRANT SELECT ON inventory_order_management.v_order_discounts TO reporting_analyst;
GRANT SELECT ON inventory_order_management.v_low_stock       TO reporting_analyst;
GRANT SELECT ON inventory_order_management.business_rules    TO reporting_analyst;

-- inventory_manager: stock, not customers or money.
GRANT SELECT ON inventory_order_management.products       TO inventory_manager;
GRANT SELECT ON inventory_order_management.inventory_logs TO inventory_manager;
GRANT SELECT ON inventory_order_management.v_low_stock    TO inventory_manager;
GRANT SELECT ON inventory_order_management.v_replenishment_plan   TO inventory_manager;
GRANT SELECT ON inventory_order_management.v_stock_reconciliation TO inventory_manager;
GRANT EXECUTE ON PROCEDURE inventory_order_management.replenish_stock TO inventory_manager;
GRANT EXECUTE ON PROCEDURE inventory_order_management.adjust_stock    TO inventory_manager;
GRANT EXECUTE ON PROCEDURE inventory_order_management.replenish_all   TO inventory_manager;

-- auditor: read the trail, change nothing, see no personal data.
GRANT SELECT ON inventory_order_management.inventory_logs         TO auditor;
GRANT SELECT ON inventory_order_management.v_stock_reconciliation TO auditor;
GRANT SELECT ON inventory_order_management.business_rules         TO auditor;

-- Example accounts. Replace the passwords before running anywhere real, and keep them out of version control.
CREATE USER IF NOT EXISTS 'svc_orders'@'localhost'  IDENTIFIED BY 'change_me_app';
CREATE USER IF NOT EXISTS 'analyst_ro'@'localhost'  IDENTIFIED BY 'change_me_analyst';
CREATE USER IF NOT EXISTS 'stock_mgr'@'localhost'   IDENTIFIED BY 'change_me_stock';
CREATE USER IF NOT EXISTS 'auditor_ro'@'localhost'  IDENTIFIED BY 'change_me_audit';

GRANT app_order_service TO 'svc_orders'@'localhost';
GRANT reporting_analyst TO 'analyst_ro'@'localhost';
GRANT inventory_manager TO 'stock_mgr'@'localhost';
GRANT auditor           TO 'auditor_ro'@'localhost';

-- Roles are inactive until switched on; setting them as default grants privileges the moment these accounts log in.
SET DEFAULT ROLE app_order_service TO 'svc_orders'@'localhost';
SET DEFAULT ROLE reporting_analyst TO 'analyst_ro'@'localhost';
SET DEFAULT ROLE inventory_manager TO 'stock_mgr'@'localhost';
SET DEFAULT ROLE auditor           TO 'auditor_ro'@'localhost';

FLUSH PRIVILEGES;
