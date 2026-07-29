-- utf8mb4 so any language or emoji stores safely.
-- ai_ci = accent- and case-insensitive, so searches are forgiving.
CREATE DATABASE IF NOT EXISTS inventory_order_management
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
