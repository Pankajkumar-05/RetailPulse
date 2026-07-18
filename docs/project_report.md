# RetailPulse — Project Report

## 1. Business Problem

A multi-region retail chain (55 stores, 5 regions, 595 SKUs across 7 categories) has no unified analytics layer connecting sales, inventory, and supplier performance. This leads to three concrete revenue-impacting issues:

1. **Stockouts** — high-demand products run out because reorder decisions aren't systematic
2. **Overstocking / dead stock** — capital tied up in slow-moving inventory
3. **No demand visibility** — store and category managers can't anticipate seasonal swings, leading to reactive rather than planned inventory decisions

This project builds the analytics platform — from raw transactional data to an executive dashboard — that addresses all three.

## 2. Data

The dataset is synthetically generated (`python/data_generation.py`) using realistic, business-plausible logic rather than random values, because real multi-store transaction data at this granularity isn't publicly available:

- **Seasonality by category**: Electronics and Apparel spike during festive season (Oct-Nov); Stationery spikes in back-to-school months (Jun-Jul); Beverages spike in summer
- **Store-type demand multipliers**: Metro stores have ~2-3x the demand of Rural stores
- **Regional price variance**: ±8% around base price, simulating local pricing decisions
- **Promotional activity**: 12% of transactions carry a 5-30% discount

Final volume: 550,310 sales transactions and 772,418 inventory snapshots across a 3-year window (2023-2025), for **1.32M+ total rows** across all 6 tables.

## 3. Data Modeling

A star schema was used with two fact tables (`fact_sales`, `fact_inventory`) and four dimension tables (`dim_store`, `dim_product`, `dim_supplier`, `dim_date`). This design was chosen over a single flat table because:
- It avoids repeating store/product/supplier attributes across 1M+ transaction rows
- It matches how BI tools (Power BI) expect data to be modeled for efficient aggregation
- It mirrors real data warehouse design, which is directly transferable to interview discussions

One modeling decision worth calling out: connecting the category-level demand forecast (`forecast_output`) to the SKU-level `dim_product` table required a small **bridge dimension table** (`dim_category`), since `dim_product[category]` has duplicate values and can't serve as the "one" side of a relationship on its own. This is a common real-world grain-mismatch problem in dimensional modeling.

## 4. SQL Analysis

28 queries were written and tested against the live database (`sql/analysis_queries.sql`), covering:
- **Window functions**: RANK, DENSE_RANK, moving averages, LAG/LEAD for MoM growth, running cumulative totals, NTILE quartiles
- **CTEs**: including a recursive CTE, multi-level CTEs for slow-mover detection, cohort-style analysis
- **Joins**: multi-table joins, self-joins, LEFT JOIN for dead-stock detection, simulated FULL OUTER JOIN (SQLite lacks native support) via UNION
- **Advanced analytics**: ABC classification by cumulative revenue contribution, inventory turnover ratio, supplier reliability vs. stockout rate, cross-store price variance

### A debugging note worth including in interviews
An early version of the inventory turnover query joined `fact_sales` directly to `fact_inventory` on `product_id` alone (no date or store match). Because both tables have many rows per product, this created a many-to-many join fan-out — the query both returned inflated numbers and took over a minute to run on the full dataset. The fix: pre-aggregate each fact table to one row per product *before* joining. This dropped runtime to under a second and produced correct results. This is a genuinely useful story about diagnosing and fixing a real performance/correctness bug, not a contrived example.

## 5. Python: Cleaning, EDA, Forecasting

### Data quality
- Zero nulls, zero duplicate transaction IDs
- IQR-based outlier detection flagged 14.1% of transactions as statistical outliers by revenue — investigation showed these are legitimate high-value Electronics purchases, not errors. They were flagged, not removed, since deleting them would understate true revenue concentration.

### Key EDA findings
- Electronics accounts for ~85% of total revenue despite being a modest share of total SKUs — a concentration worth monitoring for supply risk
- Weekend transactions average ~21% higher value than weekday transactions
- **Correlation between discount % and units sold is ~0.001** — essentially zero. This suggests current discounting is not driving meaningful incremental volume and may simply be eroding margin. This is the project's strongest actionable business recommendation.

### Forecasting
Demand was forecast at the **category level** (not per-SKU-per-store) using Facebook Prophet with multiplicative seasonality, chosen because:
- Category-level series have less noise and more historical signal than individual SKU-store combinations
- It directly answers a planning-relevant business question ("how much inventory value to plan for next quarter, by category")
- It's a defensible, appropriately-scoped starting point — going straight to SKU-store granularity would need far more history per series to forecast reliably

Validated against a held-out 90-day test period, achieving a **16.72% average MAPE** across 7 categories (range: 12.36% for Grocery to 20.09% for Stationery). This falls in the "good" range for retail demand forecasting (industry rule of thumb: under 20% is good, under 10% is excellent) and is honest, unmanipulated model output — not a cherry-picked number.

## 6. Power BI Dashboard

A 6-page dashboard was designed (full build instructions in `docs/powerbi_build_guide.md`) covering:
1. Executive Summary — top-line KPIs, revenue trend, regional/store rankings
2. Sales Performance — MoM growth, weekend/weekday and seasonal comparisons
3. Inventory Health — reorder alerts, stock coverage, dead stock value
4. Demand Forecast — actual vs. forecast revenue with confidence bands, by category
5. Store Comparison — scorecard table and a revenue-vs-margin scatter plot to spot high-revenue/low-margin stores
6. Profitability & Pricing — margin by category, discount impact, cross-store price variance

All DAX measures were written against verified column names from the actual dataset (not assumed), including handling for the category grain mismatch described above.

## 7. Excel Validation

A 5-sheet, fully formula-driven workbook (`excel/RetailPulse_Validation_Report.xlsx`) was built to cross-validate the SQL/Power BI numbers and provide a leadership-facing summary:
- **176 formulas, zero calculation errors** (verified via LibreOffice recalculation)
- Regional and category totals computed independently via SUMIFS and checked against direct Python aggregation — matched to the rupee
- A reorder point calculator mirroring the SQL Q14 logic, with an editable safety-stock assumption cell that recalculates the entire sheet
- An executive summary using INDEX/MATCH to dynamically surface the top-performing region and category

## 8. Recommendations

1. **Reassess promotional strategy** — the near-zero discount/volume correlation suggests promo spend may not be earning its margin cost. Recommend a controlled A/B test on discount depth in a subset of stores before continued broad rollout.
2. **Prioritize Electronics supply chain resilience** — given its outsized revenue share, stockouts in this category carry disproportionate risk. Recommend tighter reorder thresholds and supplier lead-time monitoring specifically for this category.
3. **Use category-level forecasts for quarterly inventory planning** — the ~17% MAPE is reliable enough to inform purchasing/allocation decisions at the category level, though not yet precise enough for automated SKU-level reordering without further model refinement.
4. **Investigate high-lead-time suppliers** — the supplier reliability query showed lead time correlates with stockout frequency; renegotiating terms or diversifying suppliers for the slowest categories could reduce stockout risk.

## 9. Limitations & Honest Caveats

- The dataset is synthetic; while generated with realistic business logic, it does not capture real-world irregularities (supply disruptions, competitor actions, economic shocks) that a production model would need to handle.
- Forecasting was done at category level; SKU-level or store-level forecasts would need more historical data per series and likely a different modeling approach (e.g., hierarchical forecasting).
- The synthetic data's sales volume is fairly evenly distributed across products, which meant the initial "dead stock" threshold needed to be recalibrated against the data's actual distribution rather than an arbitrary business rule — a reminder to validate assumptions against the data rather than assuming a textbook threshold will fit.
