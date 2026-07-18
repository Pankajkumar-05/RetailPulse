"""
RetailPulse - Automation Pipeline
------------------------------------
Simulates a scheduled ETL refresh: regenerate/refresh source data,
reload into SQLite, rerun EDA exports, rerun forecasts - all with
one command. In a production setting this would be triggered by
a scheduler (cron / Airflow / Windows Task Scheduler) rather than
run manually.

Run: python automation_pipeline.py
"""

import subprocess
import sys
import os
import sqlite3
import pandas as pd
from datetime import datetime

BASE = os.path.dirname(__file__)
DB_PATH = os.path.join(BASE, "..", "retailpulse.db")
RAW_DIR = os.path.join(BASE, "..", "data", "raw")

LOG_PATH = os.path.join(BASE, "..", "docs", "pipeline_run_log.txt")


def log(msg):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{timestamp}] {msg}"
    print(line)
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")


def step_load_to_sqlite():
    """Reload CSVs into SQLite (simulates the 'Load' step of ETL after
    an upstream refresh has dropped new CSVs into data/raw/)."""
    log("STEP: Loading CSVs into SQLite...")
    conn = sqlite3.connect(DB_PATH)
    tables = ["dim_store", "dim_supplier", "dim_product", "dim_date", "fact_sales", "fact_inventory"]
    for t in tables:
        df = pd.read_csv(os.path.join(RAW_DIR, f"{t}.csv"))
        df.to_sql(t, conn, if_exists="replace", index=False)
        log(f"  Loaded {t}: {len(df):,} rows")
    # Recreate indexes after reload (to_sql with if_exists='replace' drops them)
    idx_statements = [
        "CREATE INDEX IF NOT EXISTS idx_sales_store ON fact_sales(store_id)",
        "CREATE INDEX IF NOT EXISTS idx_sales_product ON fact_sales(product_id)",
        "CREATE INDEX IF NOT EXISTS idx_sales_date ON fact_sales(date_id)",
        "CREATE INDEX IF NOT EXISTS idx_inv_store ON fact_inventory(store_id)",
        "CREATE INDEX IF NOT EXISTS idx_inv_product ON fact_inventory(product_id)",
        "CREATE INDEX IF NOT EXISTS idx_inv_date ON fact_inventory(date_id)",
    ]
    for stmt in idx_statements:
        conn.execute(stmt)
    # Recreate views too
    views_path = os.path.join(BASE, "..", "sql", "views.sql")
    with open(views_path) as f:
        conn.executescript(f.read())
    conn.commit()
    conn.close()
    log("  Indexes and views recreated.")


def step_run_eda():
    log("STEP: Running data cleaning & EDA...")
    result = subprocess.run([sys.executable, os.path.join(BASE, "data_cleaning_eda.py")],
                             capture_output=True, text=True)
    if result.returncode != 0:
        log(f"  EDA step FAILED:\n{result.stderr[-500:]}")
        raise RuntimeError("EDA step failed")
    log("  EDA completed successfully.")


def step_run_forecast():
    log("STEP: Running forecasting model...")
    result = subprocess.run([sys.executable, os.path.join(BASE, "forecasting_model.py")],
                             capture_output=True, text=True)
    if result.returncode != 0:
        log(f"  Forecast step FAILED:\n{result.stderr[-500:]}")
        raise RuntimeError("Forecast step failed")
    log("  Forecasting completed successfully.")


def main():
    log("=" * 60)
    log("RETAILPULSE AUTOMATION PIPELINE - RUN START")
    log("=" * 60)
    try:
        step_load_to_sqlite()
        step_run_eda()
        step_run_forecast()
        log("PIPELINE RUN COMPLETE - all steps succeeded.")
    except Exception as e:
        log(f"PIPELINE RUN FAILED: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
