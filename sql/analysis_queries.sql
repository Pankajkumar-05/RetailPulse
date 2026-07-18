-- ============================================================
-- RetailPulse: 28 Advanced SQL Analysis Queries
-- Organized by technique: Window Functions, CTEs, Joins,
-- Advanced Analytics. Views are in views.sql.
-- Note on Stored Procedures: SQLite does not support stored
-- procedures. Query 22-24 are written as parameterized queries
-- here, with the equivalent PostgreSQL stored procedure syntax
-- included as comments for interview discussion.
-- ============================================================

-- ============================================================
-- SECTION A: WINDOW FUNCTIONS (Q1-Q5)
-- ============================================================

-- Q1: Rank products by revenue within each store
SELECT
    store_id,
    product_id,
    total_revenue,
    RANK() OVER (PARTITION BY store_id ORDER BY total_revenue DESC) AS revenue_rank,
    DENSE_RANK() OVER (PARTITION BY store_id ORDER BY total_revenue DESC) AS dense_revenue_rank
FROM (
    SELECT store_id, product_id, SUM(revenue) AS total_revenue
    FROM fact_sales
    GROUP BY store_id, product_id
) t
ORDER BY store_id, revenue_rank
LIMIT 20;

-- Q2: 7-day moving average of daily revenue (company-wide)
SELECT
    date_id,
    daily_revenue,
    ROUND(AVG(daily_revenue) OVER (
        ORDER BY date_id
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7day
FROM (
    SELECT date_id, SUM(revenue) AS daily_revenue
    FROM fact_sales
    GROUP BY date_id
) d
ORDER BY date_id
LIMIT 20;

-- Q3: Month-over-month revenue growth using LAG()
SELECT
    year,
    month,
    monthly_revenue,
    LAG(monthly_revenue) OVER (ORDER BY year, month) AS prev_month_revenue,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY year, month)) * 100.0
        / NULLIF(LAG(monthly_revenue) OVER (ORDER BY year, month), 0), 2
    ) AS mom_growth_pct
FROM (
    SELECT d.year, d.month, SUM(f.revenue) AS monthly_revenue
    FROM fact_sales f
    JOIN dim_date d ON f.date_id = d.date_id
    GROUP BY d.year, d.month
) m
ORDER BY year, month;

-- Q4: Running cumulative revenue per store (YTD-style running total)
SELECT
    store_id,
    date_id,
    daily_revenue,
    SUM(daily_revenue) OVER (PARTITION BY store_id ORDER BY date_id) AS cumulative_revenue
FROM (
    SELECT store_id, date_id, SUM(revenue) AS daily_revenue
    FROM fact_sales
    GROUP BY store_id, date_id
) s
WHERE store_id = 1
ORDER BY date_id
LIMIT 20;

-- Q5: Percentile ranking of stores into quartiles by total revenue
SELECT
    store_id,
    total_revenue,
    NTILE(4) OVER (ORDER BY total_revenue DESC) AS performance_quartile
FROM (
    SELECT store_id, SUM(revenue) AS total_revenue
    FROM fact_sales
    GROUP BY store_id
) r
ORDER BY total_revenue DESC;


-- ============================================================
-- SECTION B: CTEs & RECURSIVE QUERIES (Q6-Q9)
-- ============================================================

-- Q6: Top 5 products per category per region using CTE + window function
WITH product_region_sales AS (
    SELECT
        p.category,
        s.region,
        p.product_name,
        SUM(f.revenue) AS revenue
    FROM fact_sales f
    JOIN dim_product p ON f.product_id = p.product_id
    JOIN dim_store s ON f.store_id = s.store_id
    GROUP BY p.category, s.region, p.product_name
),
ranked AS (
    SELECT *,
        RANK() OVER (PARTITION BY category, region ORDER BY revenue DESC) AS rnk
    FROM product_region_sales
)
SELECT * FROM ranked WHERE rnk <= 5
ORDER BY category, region, rnk
LIMIT 30;

-- Q7: Recursive CTE building a simple calendar sequence (demonstrates recursion)
WITH RECURSIVE date_seq(n) AS (
    SELECT 0
    UNION ALL
    SELECT n + 1 FROM date_seq WHERE n < 29
)
SELECT
    date('2025-01-01', '+' || n || ' days') AS generated_date
FROM date_seq;

-- Q8: Multi-level CTE - identify slow-moving inventory (sold < 20 units in last 30 days of data)
WITH last_30_days AS (
    SELECT MAX(date_id) AS max_date FROM fact_sales
),
recent_sales AS (
    SELECT f.product_id, f.store_id, SUM(f.quantity_sold) AS units_sold_30d
    FROM fact_sales f, last_30_days
    WHERE f.date_id >= date(last_30_days.max_date, '-30 days')
    GROUP BY f.product_id, f.store_id
),
slow_movers AS (
    SELECT r.product_id, r.store_id, r.units_sold_30d
    FROM recent_sales r
    WHERE r.units_sold_30d < 20
)
SELECT
    sm.store_id,
    st.store_name,
    p.product_name,
    p.category,
    sm.units_sold_30d
FROM slow_movers sm
JOIN dim_store st ON sm.store_id = st.store_id
JOIN dim_product p ON sm.product_id = p.product_id
ORDER BY sm.units_sold_30d ASC
LIMIT 20;

-- Q9: Cohort-style analysis - first purchase month vs repeat activity, per store
WITH store_first_month AS (
    SELECT store_id, MIN(date_id) AS first_sale_date
    FROM fact_sales
    GROUP BY store_id
),
store_monthly_activity AS (
    SELECT f.store_id, d.year, d.month, COUNT(DISTINCT f.date_id) AS active_days
    FROM fact_sales f
    JOIN dim_date d ON f.date_id = d.date_id
    GROUP BY f.store_id, d.year, d.month
)
SELECT
    sfm.store_id,
    sfm.first_sale_date,
    sma.year,
    sma.month,
    sma.active_days
FROM store_first_month sfm
JOIN store_monthly_activity sma ON sfm.store_id = sma.store_id
ORDER BY sfm.store_id, sma.year, sma.month
LIMIT 20;


-- ============================================================
-- SECTION C: JOINS (Q10-Q13)
-- ============================================================

-- Q10: Multi-table join - flag stockout risk using sales velocity + supplier lead time
SELECT
    st.store_name,
    p.product_name,
    i.stock_on_hand,
    i.reorder_level,
    sup.lead_time_days,
    ROUND(i.stock_on_hand * 1.0 / NULLIF(i.reorder_level, 0), 2) AS stock_coverage_ratio
FROM fact_inventory i
JOIN dim_store st ON i.store_id = st.store_id
JOIN dim_product p ON i.product_id = p.product_id
JOIN dim_supplier sup ON i.supplier_id = sup.supplier_id
WHERE i.stock_on_hand < i.reorder_level
  AND sup.lead_time_days >= 10
ORDER BY stock_coverage_ratio ASC
LIMIT 20;

-- Q11: Self-join - compare same product's revenue across different stores
SELECT
    a.product_id,
    a.store_id AS store_a,
    b.store_id AS store_b,
    a.total_revenue AS revenue_a,
    b.total_revenue AS revenue_b,
    ROUND(a.total_revenue - b.total_revenue, 2) AS revenue_diff
FROM (
    SELECT store_id, product_id, SUM(revenue) AS total_revenue
    FROM fact_sales GROUP BY store_id, product_id
) a
JOIN (
    SELECT store_id, product_id, SUM(revenue) AS total_revenue
    FROM fact_sales GROUP BY store_id, product_id
) b ON a.product_id = b.product_id AND a.store_id < b.store_id
WHERE a.product_id = 10
ORDER BY revenue_diff DESC
LIMIT 20;

-- Q12: LEFT JOIN - products never sold in a specific region (dead stock candidates)
SELECT p.product_id, p.product_name, p.category
FROM dim_product p
LEFT JOIN (
    SELECT DISTINCT f.product_id
    FROM fact_sales f
    JOIN dim_store s ON f.store_id = s.store_id
    WHERE s.region = 'Central'
) sold ON p.product_id = sold.product_id
WHERE sold.product_id IS NULL;

-- Q13: FULL OUTER JOIN equivalent (SQLite lacks native FULL OUTER JOIN - simulated via UNION)
-- Reconciles products that appear in sales but not inventory, and vice versa
SELECT product_id, 'in_sales_not_inventory' AS discrepancy_type
FROM (SELECT DISTINCT product_id FROM fact_sales)
WHERE product_id NOT IN (SELECT DISTINCT product_id FROM fact_inventory)
UNION ALL
SELECT product_id, 'in_inventory_not_sales' AS discrepancy_type
FROM (SELECT DISTINCT product_id FROM fact_inventory)
WHERE product_id NOT IN (SELECT DISTINCT product_id FROM fact_sales);


-- ============================================================
-- SECTION D: STORED-PROCEDURE-STYLE QUERIES (Q14-Q16)
-- SQLite has no stored procedures. Below are the equivalent
-- parameterized queries. PostgreSQL CREATE PROCEDURE versions
-- are included as comments for interview discussion.
-- ============================================================

-- Q14: Reorder quantity calculation (parameterized by store_id in application layer)
-- Postgres equivalent: CREATE OR REPLACE PROCEDURE calc_reorder_qty(p_store_id INT) ...
SELECT
    i.store_id,
    i.product_id,
    p.product_name,
    i.stock_on_hand,
    i.reorder_level,
    sup.lead_time_days,
    -- Reorder qty = (avg daily demand * lead time) + safety stock - current stock
    MAX(0, ROUND((i.reorder_level / 7.0) * sup.lead_time_days + (i.reorder_level * 0.2) - i.stock_on_hand)) AS suggested_reorder_qty
FROM fact_inventory i
JOIN dim_product p ON i.product_id = p.product_id
JOIN dim_supplier sup ON i.supplier_id = sup.supplier_id
WHERE i.store_id = 1
  AND i.stock_on_hand < i.reorder_level
LIMIT 20;

-- Q15: Monthly store performance report (parameterized by year/month)
SELECT
    st.store_name,
    d.year,
    d.month,
    SUM(f.revenue) AS monthly_revenue,
    SUM(f.quantity_sold) AS monthly_units,
    ROUND(SUM(f.revenue) - SUM(f.cost), 2) AS monthly_profit
FROM fact_sales f
JOIN dim_store st ON f.store_id = st.store_id
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.year = 2024 AND d.month = 11
GROUP BY st.store_name, d.year, d.month
ORDER BY monthly_revenue DESC
LIMIT 20;

-- Q16: Filter sales by date range and region (parameterized)
SELECT
    st.region,
    COUNT(f.transaction_id) AS transactions,
    SUM(f.revenue) AS total_revenue
FROM fact_sales f
JOIN dim_store st ON f.store_id = st.store_id
WHERE f.date_id BETWEEN '2024-10-01' AND '2024-11-30'
  AND st.region = 'North'
GROUP BY st.region;


-- ============================================================
-- SECTION E: ADVANCED ANALYTICS (Q17-Q28)
-- ============================================================

-- Q17: Inventory turnover ratio per product category
-- Note: pre-aggregate each fact table by product_id BEFORE joining.
-- Joining fact_sales to fact_inventory directly on product_id (without
-- also joining on date/store) causes a many-to-many fan-out that both
-- inflates the numbers and is extremely slow on large fact tables.
WITH sales_agg AS (
    SELECT product_id, SUM(quantity_sold) AS units_sold
    FROM fact_sales
    GROUP BY product_id
),
inventory_agg AS (
    SELECT product_id, AVG(stock_on_hand) AS avg_stock_on_hand
    FROM fact_inventory
    GROUP BY product_id
)
SELECT
    p.category,
    SUM(s.units_sold) AS units_sold,
    AVG(i.avg_stock_on_hand) AS avg_stock_on_hand,
    ROUND(SUM(s.units_sold) * 1.0 / NULLIF(AVG(i.avg_stock_on_hand), 0), 2) AS turnover_ratio
FROM sales_agg s
JOIN inventory_agg i ON s.product_id = i.product_id
JOIN dim_product p ON s.product_id = p.product_id
GROUP BY p.category
ORDER BY turnover_ratio DESC;

-- Q18: Seasonal demand pattern by month across categories
SELECT
    d.month,
    d.month_name,
    p.category,
    SUM(f.quantity_sold) AS total_units
FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
JOIN dim_product p ON f.product_id = p.product_id
GROUP BY d.month, d.month_name, p.category
ORDER BY d.month, total_units DESC
LIMIT 30;

-- Q19: ABC analysis - classify products by cumulative revenue contribution
WITH product_revenue AS (
    SELECT product_id, SUM(revenue) AS total_revenue
    FROM fact_sales
    GROUP BY product_id
),
ranked AS (
    SELECT
        product_id,
        total_revenue,
        SUM(total_revenue) OVER (ORDER BY total_revenue DESC) AS running_total,
        SUM(total_revenue) OVER () AS grand_total
    FROM product_revenue
)
SELECT
    product_id,
    total_revenue,
    ROUND(running_total * 100.0 / grand_total, 2) AS cumulative_pct,
    CASE
        WHEN running_total * 100.0 / grand_total <= 70 THEN 'A'
        WHEN running_total * 100.0 / grand_total <= 90 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM ranked
ORDER BY total_revenue DESC
LIMIT 30;

-- Q20: Cross-store price variance for the same SKU
SELECT
    product_id,
    MIN(unit_price) AS min_price,
    MAX(unit_price) AS max_price,
    ROUND(MAX(unit_price) - MIN(unit_price), 2) AS price_spread,
    ROUND((MAX(unit_price) - MIN(unit_price)) * 100.0 / NULLIF(MIN(unit_price),0), 2) AS pct_variance
FROM fact_sales
GROUP BY product_id
ORDER BY pct_variance DESC
LIMIT 20;

-- Q21: Discount impact on volume (does discounting actually drive more units?)
SELECT
    CASE WHEN discount_pct > 0 THEN 'Discounted' ELSE 'Full Price' END AS pricing_type,
    COUNT(*) AS transactions,
    ROUND(AVG(quantity_sold), 2) AS avg_units_per_transaction,
    ROUND(AVG(revenue), 2) AS avg_revenue_per_transaction
FROM fact_sales
GROUP BY pricing_type;

-- Q22: Weekend vs weekday performance
SELECT
    d.is_weekend,
    COUNT(f.transaction_id) AS transactions,
    SUM(f.revenue) AS total_revenue,
    ROUND(AVG(f.revenue), 2) AS avg_transaction_value
FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.is_weekend;

-- Q23: Store type profitability comparison
SELECT
    st.store_type,
    COUNT(DISTINCT st.store_id) AS num_stores,
    SUM(f.revenue) AS total_revenue,
    ROUND(SUM(f.revenue) - SUM(f.cost), 2) AS total_profit,
    ROUND((SUM(f.revenue) - SUM(f.cost)) * 100.0 / NULLIF(SUM(f.revenue),0), 2) AS margin_pct
FROM fact_sales f
JOIN dim_store st ON f.store_id = st.store_id
GROUP BY st.store_type
ORDER BY total_revenue DESC;

-- Q24: Supplier reliability vs stockout frequency
SELECT
    sup.supplier_name,
    sup.reliability_score,
    sup.lead_time_days,
    COUNT(CASE WHEN i.stock_on_hand < i.reorder_level THEN 1 END) AS stockout_events,
    COUNT(*) AS total_snapshots,
    ROUND(COUNT(CASE WHEN i.stock_on_hand < i.reorder_level THEN 1 END) * 100.0 / COUNT(*), 2) AS stockout_rate_pct
FROM fact_inventory i
JOIN dim_supplier sup ON i.supplier_id = sup.supplier_id
GROUP BY sup.supplier_name, sup.reliability_score, sup.lead_time_days
ORDER BY stockout_rate_pct DESC
LIMIT 15;

-- Q25: Top 10 highest-margin products overall
SELECT product_name, category, margin_pct
FROM dim_product
ORDER BY margin_pct DESC
LIMIT 10;

-- Q26: Region-wise YoY revenue comparison (2024 vs 2023)
SELECT
    st.region,
    d.year,
    SUM(f.revenue) AS annual_revenue
FROM fact_sales f
JOIN dim_store st ON f.store_id = st.store_id
JOIN dim_date d ON f.date_id = d.date_id
WHERE d.year IN (2023, 2024)
GROUP BY st.region, d.year
ORDER BY st.region, d.year;

-- Q27: Festive season lift - compare Oct/Nov revenue vs rest of year
SELECT
    d.is_festive_season,
    SUM(f.revenue) AS total_revenue,
    COUNT(f.transaction_id) AS transactions,
    ROUND(SUM(f.revenue) * 1.0 / COUNT(f.transaction_id), 2) AS avg_transaction_value
FROM fact_sales f
JOIN dim_date d ON f.date_id = d.date_id
GROUP BY d.is_festive_season;

-- Q28: Dead stock value (products with stock but near-zero sales in last 30 days)
WITH last_30_days AS (
    SELECT MAX(date_id) AS max_date FROM fact_sales
),
recent_sales AS (
    SELECT product_id, SUM(quantity_sold) AS units_sold_30d
    FROM fact_sales, last_30_days
    WHERE date_id >= date(last_30_days.max_date, '-30 days')
    GROUP BY product_id
),
dead_stock AS (
    -- Threshold set relative to the bottom 10th percentile of 30-day sales
    -- in this dataset (verified empirically: min=50, avg=153 units/30d).
    -- In a real deployment this threshold would be product/category-specific,
    -- e.g. below X% of that SKU's own historical average.
    SELECT i.product_id, i.store_id, i.stock_on_hand
    FROM fact_inventory i
    LEFT JOIN recent_sales r ON i.product_id = r.product_id
    WHERE COALESCE(r.units_sold_30d, 0) < 70
)
SELECT
    ds.store_id,
    p.product_name,
    p.category,
    ds.stock_on_hand,
    p.unit_cost,
    ROUND(ds.stock_on_hand * p.unit_cost, 2) AS dead_stock_value
FROM dead_stock ds
JOIN dim_product p ON ds.product_id = p.product_id
ORDER BY dead_stock_value DESC
LIMIT 20;
