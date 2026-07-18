# RetailPulse — Multi-Region Retail Supply Chain & Revenue Intelligence Platform

An end-to-end data analytics project simulating a 55-store retail chain: inventory optimization, demand forecasting, and profitability analysis across regions, stores, and product categories.

Built to demonstrate the full analyst tool stack — **SQL, Python, Power BI, and Excel** — working together on a single, realistic business problem, not as disconnected exercises.

---

## Business Problem

A multi-region retail chain has no unified view of:
- Which stores/products are underperforming and why
- How much revenue is at risk from stockouts vs. tied up in dead stock
- Whether current discounting strategy is actually driving sales volume
- How demand will trend next quarter, by category

This project builds the analytics layer to answer all four questions, from raw transactional data to an executive-ready dashboard.

---

## Tech Stack

| Layer | Tools |
|---|---|
| Data generation | Python (Pandas, NumPy, Faker) |
| Database / modeling | SQLite (star schema), portable SQL (CTEs, window functions, views) |
| Analysis / forecasting | Python (Pandas, Prophet, Matplotlib, Seaborn) |
| BI / visualization | Power BI (DAX, Power Query) |
| Reporting / validation | Excel (SUMIFS, INDEX/MATCH, conditional formatting) |

---

## Dataset

**1.32M+ rows** across 6 tables, generated with realistic business logic (not random noise):
- Category-specific seasonality (Electronics spike in festive season, Stationery in back-to-school, etc.)
- Store-type demand multipliers (Metro > Urban > Suburban > Rural)
- Regional price variance (±8%)
- Weekend uplift, promotional discounting (12% of transactions)

| Table | Rows | Grain |
|---|---|---|
| `fact_sales` | 550,310 | one row per transaction |
| `fact_inventory` | 772,418 | one row per store-product-week snapshot |
| `dim_store` | 55 | one row per store |
| `dim_product` | 595 | one row per SKU |
| `dim_supplier` | 25 | one row per supplier |
| `dim_date` | 1,096 | one row per day, 2023–2025 |

> **Note on synthetic data**: Real multi-store retail transaction data at this granularity isn't publicly available due to commercial sensitivity. The dataset is generated with realistic statistical distributions (seasonality, regional pricing, category demand curves) so every technique here transfers directly to real business data. See `python/data_generation.py` for the full generation logic.

---

## Data Model (Star Schema)

```
                    dim_date
                       |
   dim_store ----  fact_sales  ---- dim_product ---- dim_supplier
                       |                                  |
                  fact_inventory ------------------------- 
```

`fact_sales` and `fact_inventory` are the two fact tables, each joining out to `dim_store`, `dim_product`, `dim_date`, and (for inventory) `dim_supplier`. See `sql/schema.sql` for full DDL with PKs, FKs, and indexes.

---

## Repository Structure

```
RetailPulse/
├── README.md
├── retailpulse.db                    # SQLite database, pre-loaded and indexed
├── data/
│   ├── raw/                          # source CSVs (6 tables, 1.32M rows)
│   └── processed/                    # EDA/forecast outputs, Power BI-ready
├── sql/
│   ├── schema.sql                    # star schema DDL, PKs, FKs, indexes
│   ├── views.sql                     # 3 reusable views
│   └── analysis_queries.sql          # 28 tested advanced queries
├── python/
│   ├── data_generation.py            # synthetic dataset generator
│   ├── data_cleaning_eda.py          # quality checks, EDA, chart generation
│   ├── forecasting_model.py          # Prophet demand forecasting per category
│   └── automation_pipeline.py        # chains the above into one ETL run
├── excel/
│   ├── RetailPulse_Validation_Report.xlsx   # 5-sheet formula-driven workbook
│   ├── build_workbook_part1.py
│   └── build_workbook_part2.py
├── powerbi/                          
└── docs/
    ├── eda_summary.txt               # data quality + EDA findings
    ├── forecast_accuracy.txt         # MAPE scores by category
    ├── pipeline_run_log.txt          # sample automation run log
    ├── project_report.md             # full written project report
    └── charts/                       # EDA + forecast chart images
```

---

## Key Findings

- **16.72% average forecast MAPE** across 7 product categories (Grocery best at 12.36%, Stationery hardest at 20.09% — consistent with back-to-school demand being spikier and harder to predict).
- **Discount % has ~0.001 correlation with units sold** — discounting is not meaningfully driving incremental volume in this dataset. Flagged as a recommendation to reassess promo spend allocation.
- **Electronics drives ~85% of total revenue** despite being a smaller share of SKUs — a concentration risk worth monitoring.
- **14.1% of transactions are statistical outliers** by revenue (IQR method), but investigation showed these are legitimate high-value Electronics sales, not data errors — an example of validating before cleaning rather than blindly removing outliers.

Full details in `docs/eda_summary.txt` and `docs/forecast_accuracy.txt`.

---

## How to Reproduce

```bash
# 1. Generate the dataset (or use the CSVs already in data/raw/)
cd python
python data_generation.py

# 2. Load into SQLite, run EDA, run forecasts (one command)
python automation_pipeline.py

# 3. Run individual SQL queries
# Open retailpulse.db in DB Browser for SQLite (https://sqlitebrowser.org/)
# and run any query from sql/analysis_queries.sql

# 4. Build the Power BI dashboard
# Follow docs/powerbi_build_guide.md step by step

# 5. Open the Excel workbook
# excel/RetailPulse_Validation_Report.xlsx — all formulas live, recalculates automatically
```

> **Note:** The SQLite database (`retailpulse.db`) is not included in this repository because of GitHub's file size limits. It can be regenerated locally using the provided Python scripts.

---

## SQL Highlights

28 queries in `sql/analysis_queries.sql` covering window functions (RANK, LAG, moving averages, NTILE), CTEs (including a recursive CTE), multiple join types, and advanced analytics (ABC classification, cohort-style analysis, supplier reliability scoring).

Worth noting: an earlier version of the inventory turnover query (Q17) joined `fact_sales` to `fact_inventory` directly on `product_id` alone, causing a many-to-many fan-out that both inflated the numbers and made the query hang. Fixed by pre-aggregating each fact table before joining — see the comment in the query for the full explanation. A good example of debugging a real performance/correctness issue, not just writing queries that happen to run.

---

## Author

Pankaj — BCA graduate, Data Science Intern (Prinston Smart Engineers), Data Analytics Trainee (Anudip Foundation)
[GitHub](https://github.com/pankajkumar-05) · [LinkedIn](https://linkedin.com/in/pankaj005)
