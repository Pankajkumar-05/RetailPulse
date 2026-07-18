-- ============================================================
-- RetailPulse: Star Schema DDL
-- Fact tables: fact_sales, fact_inventory
-- Dimension tables: dim_store, dim_product, dim_supplier, dim_date
-- Note: Data is loaded from CSVs via Python (pandas.to_sql).
-- This script documents the schema design and re-creates it with
-- proper constraints if you rebuild the DB from scratch.
-- ============================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS fact_inventory;
DROP TABLE IF EXISTS dim_store;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_supplier;
DROP TABLE IF EXISTS dim_date;

-- ---------------------------
-- DIMENSION: dim_date
-- ---------------------------
CREATE TABLE dim_date (
    date_id            TEXT PRIMARY KEY,   -- 'YYYY-MM-DD'
    day                 INTEGER,
    month               INTEGER,
    month_name          TEXT,
    quarter             INTEGER,
    year                INTEGER,
    day_of_week         TEXT,
    is_weekend          INTEGER,           -- 0/1
    is_festive_season   INTEGER,
    is_summer           INTEGER,
    is_back_to_school   INTEGER
);

-- ---------------------------
-- DIMENSION: dim_store
-- ---------------------------
CREATE TABLE dim_store (
    store_id            INTEGER PRIMARY KEY,
    store_name          TEXT,
    region              TEXT,
    city                TEXT,
    store_type          TEXT,
    opening_date        TEXT,
    demand_multiplier   REAL
);

-- ---------------------------
-- DIMENSION: dim_supplier
-- ---------------------------
CREATE TABLE dim_supplier (
    supplier_id         INTEGER PRIMARY KEY,
    supplier_name       TEXT,
    lead_time_days      INTEGER,
    reliability_score   REAL
);

-- ---------------------------
-- DIMENSION: dim_product
-- ---------------------------
CREATE TABLE dim_product (
    product_id          INTEGER PRIMARY KEY,
    product_name        TEXT,
    category            TEXT,
    unit_price          REAL,
    unit_cost           REAL,
    margin_pct          REAL,
    seasonality_type    TEXT,
    supplier_id         INTEGER,
    FOREIGN KEY (supplier_id) REFERENCES dim_supplier(supplier_id)
);

-- ---------------------------
-- FACT: fact_sales
-- ---------------------------
CREATE TABLE fact_sales (
    transaction_id      INTEGER PRIMARY KEY,
    date_id             TEXT,
    store_id            INTEGER,
    product_id          INTEGER,
    quantity_sold       INTEGER,
    unit_price          REAL,
    discount_pct        REAL,
    revenue             REAL,
    cost                REAL,
    FOREIGN KEY (date_id) REFERENCES dim_date(date_id),
    FOREIGN KEY (store_id) REFERENCES dim_store(store_id),
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id)
);

-- ---------------------------
-- FACT: fact_inventory
-- ---------------------------
CREATE TABLE fact_inventory (
    inventory_id        INTEGER PRIMARY KEY,
    date_id             TEXT,
    store_id            INTEGER,
    product_id          INTEGER,
    stock_on_hand       INTEGER,
    reorder_level       INTEGER,
    supplier_id         INTEGER,
    FOREIGN KEY (date_id) REFERENCES dim_date(date_id),
    FOREIGN KEY (store_id) REFERENCES dim_store(store_id),
    FOREIGN KEY (product_id) REFERENCES dim_product(product_id),
    FOREIGN KEY (supplier_id) REFERENCES dim_supplier(supplier_id)
);

-- ---------------------------
-- INDEXES (for join/filter performance on large fact tables)
-- ---------------------------
CREATE INDEX idx_sales_store    ON fact_sales(store_id);
CREATE INDEX idx_sales_product  ON fact_sales(product_id);
CREATE INDEX idx_sales_date     ON fact_sales(date_id);

CREATE INDEX idx_inv_store      ON fact_inventory(store_id);
CREATE INDEX idx_inv_product    ON fact_inventory(product_id);
CREATE INDEX idx_inv_date       ON fact_inventory(date_id);
