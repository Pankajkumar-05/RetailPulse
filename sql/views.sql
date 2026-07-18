-- ============================================================
-- RetailPulse: VIEWS
-- ============================================================

-- View 1: Store-level performance summary
DROP VIEW IF EXISTS vw_store_performance;
CREATE VIEW vw_store_performance AS
SELECT
    s.store_id,
    s.store_name,
    s.region,
    s.store_type,
    COUNT(f.transaction_id)      AS total_transactions,
    SUM(f.quantity_sold)         AS total_units_sold,
    ROUND(SUM(f.revenue), 2)     AS total_revenue,
    ROUND(SUM(f.cost), 2)        AS total_cost,
    ROUND(SUM(f.revenue) - SUM(f.cost), 2) AS gross_profit,
    ROUND((SUM(f.revenue) - SUM(f.cost)) * 100.0 / NULLIF(SUM(f.revenue), 0), 2) AS gross_margin_pct
FROM fact_sales f
JOIN dim_store s ON f.store_id = s.store_id
GROUP BY s.store_id, s.store_name, s.region, s.store_type;

-- View 2: Product profitability
DROP VIEW IF EXISTS vw_product_profitability;
CREATE VIEW vw_product_profitability AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    SUM(f.quantity_sold)         AS total_units_sold,
    ROUND(SUM(f.revenue), 2)     AS total_revenue,
    ROUND(SUM(f.revenue) - SUM(f.cost), 2) AS gross_profit,
    ROUND(AVG(f.discount_pct), 3) AS avg_discount_pct,
    ROUND((SUM(f.revenue) - SUM(f.cost)) * 100.0 / NULLIF(SUM(f.revenue), 0), 2) AS margin_pct
FROM fact_sales f
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY p.product_id, p.product_name, p.category;

-- View 3: Reorder alerts (current stock below reorder level)
DROP VIEW IF EXISTS vw_reorder_alerts;
CREATE VIEW vw_reorder_alerts AS
SELECT
    i.date_id,
    st.store_name,
    st.region,
    p.product_name,
    p.category,
    i.stock_on_hand,
    i.reorder_level,
    (i.reorder_level - i.stock_on_hand) AS units_short,
    sup.supplier_name,
    sup.lead_time_days
FROM fact_inventory i
JOIN dim_store st   ON i.store_id = st.store_id
JOIN dim_product p  ON i.product_id = p.product_id
JOIN dim_supplier sup ON i.supplier_id = sup.supplier_id
WHERE i.stock_on_hand < i.reorder_level;
