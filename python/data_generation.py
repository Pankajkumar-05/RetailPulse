"""
RetailPulse - Synthetic Retail Dataset Generator
--------------------------------------------------
Generates a realistic, business-plausible dataset for a multi-region
retail chain: stores, products, suppliers, a full date dimension,
and two fact tables (sales, inventory) totaling 500K+ rows.

WHY SYNTHETIC (say this in interviews, don't hide it):
Real multi-store retail transaction data at this granularity is not
publicly available due to commercial sensitivity. We simulate it using
realistic distributions (seasonality, regional pricing, category-level
demand curves, promo effects) so the analytics techniques transfer
directly to real business data. This is a standard practice used by
analytics teams for prototyping pipelines before real data access.

Run: python data_generation.py
Output: CSV files in ../data/raw/
"""

import numpy as np
import pandas as pd
from faker import Faker
from datetime import datetime, timedelta
import os

np.random.seed(42)
fake = Faker()
Faker.seed(42)

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "raw")
os.makedirs(OUT_DIR, exist_ok=True)

# -----------------------------------------------------------------
# 1. DIM_STORE
# -----------------------------------------------------------------
REGIONS = ["North", "South", "East", "West", "Central"]
STORE_TYPES = ["Metro", "Urban", "Suburban", "Rural"]

N_STORES = 55
stores = []
for i in range(1, N_STORES + 1):
    region = np.random.choice(REGIONS, p=[0.22, 0.22, 0.20, 0.20, 0.16])
    store_type = np.random.choice(STORE_TYPES, p=[0.25, 0.35, 0.25, 0.15])
    # Metro stores tend to have higher footfall -> higher base demand multiplier
    demand_multiplier = {
        "Metro": np.random.uniform(1.4, 1.8),
        "Urban": np.random.uniform(1.1, 1.4),
        "Suburban": np.random.uniform(0.8, 1.1),
        "Rural": np.random.uniform(0.5, 0.8),
    }[store_type]
    stores.append({
        "store_id": i,
        "store_name": f"RetailPulse {region} #{i:03d}",
        "region": region,
        "city": fake.city(),
        "store_type": store_type,
        "opening_date": fake.date_between(start_date="-6y", end_date="-2y"),
        "demand_multiplier": round(demand_multiplier, 3),
    })
dim_store = pd.DataFrame(stores)

# -----------------------------------------------------------------
# 2. DIM_SUPPLIER
# -----------------------------------------------------------------
N_SUPPLIERS = 25
suppliers = []
for i in range(1, N_SUPPLIERS + 1):
    suppliers.append({
        "supplier_id": i,
        "supplier_name": fake.company(),
        "lead_time_days": np.random.choice([3, 5, 7, 10, 14, 21], p=[0.15, 0.25, 0.25, 0.15, 0.12, 0.08]),
        "reliability_score": round(np.random.uniform(0.80, 0.99), 2),  # on-time delivery rate
    })
dim_supplier = pd.DataFrame(suppliers)

# -----------------------------------------------------------------
# 3. DIM_PRODUCT
# -----------------------------------------------------------------
CATEGORIES = {
    "Grocery": {"base_price": (50, 400), "margin": (0.08, 0.15), "seasonality": "low"},
    "Electronics": {"base_price": (800, 25000), "margin": (0.10, 0.22), "seasonality": "high_festive"},
    "Apparel": {"base_price": (300, 3000), "margin": (0.25, 0.45), "seasonality": "high_seasonal"},
    "Home & Kitchen": {"base_price": (200, 5000), "margin": (0.15, 0.30), "seasonality": "medium"},
    "Personal Care": {"base_price": (50, 800), "margin": (0.20, 0.35), "seasonality": "low"},
    "Beverages": {"base_price": (20, 300), "margin": (0.10, 0.18), "seasonality": "medium_summer"},
    "Stationery": {"base_price": (10, 500), "margin": (0.15, 0.25), "seasonality": "high_back_to_school"},
}

N_PRODUCTS = 600
products = []
pid = 1
for category, meta in CATEGORIES.items():
    n_in_cat = N_PRODUCTS // len(CATEGORIES)
    for _ in range(n_in_cat):
        price = round(np.random.uniform(*meta["base_price"]), 2)
        margin = round(np.random.uniform(*meta["margin"]), 3)
        products.append({
            "product_id": pid,
            "product_name": f"{category[:4].upper()}-{fake.word().capitalize()}-{pid}",
            "category": category,
            "unit_price": price,
            "unit_cost": round(price * (1 - margin), 2),
            "margin_pct": margin,
            "seasonality_type": meta["seasonality"],
            "supplier_id": np.random.randint(1, N_SUPPLIERS + 1),
        })
        pid += 1
dim_product = pd.DataFrame(products)

# -----------------------------------------------------------------
# 4. DIM_DATE
# -----------------------------------------------------------------
START_DATE = datetime(2023, 1, 1)
END_DATE = datetime(2025, 12, 31)
date_range = pd.date_range(START_DATE, END_DATE, freq="D")

dim_date = pd.DataFrame({"date_id": date_range})
dim_date["day"] = dim_date["date_id"].dt.day
dim_date["month"] = dim_date["date_id"].dt.month
dim_date["month_name"] = dim_date["date_id"].dt.strftime("%B")
dim_date["quarter"] = dim_date["date_id"].dt.quarter
dim_date["year"] = dim_date["date_id"].dt.year
dim_date["day_of_week"] = dim_date["date_id"].dt.day_name()
dim_date["is_weekend"] = dim_date["date_id"].dt.dayofweek >= 5
# Festive season flags (Indian retail calendar - Diwali/festive Oct-Nov, back-to-school Jun, summer Apr-Jun)
dim_date["is_festive_season"] = dim_date["month"].isin([10, 11])
dim_date["is_summer"] = dim_date["month"].isin([4, 5, 6])
dim_date["is_back_to_school"] = dim_date["month"].isin([6, 7])

# -----------------------------------------------------------------
# 5. FACT_SALES  (target: ~550,000 rows)
# -----------------------------------------------------------------
print("Generating fact_sales... this may take a minute.")

sales_rows = []
product_lookup = dim_product.set_index("product_id")
store_lookup = dim_store.set_index("store_id")

# To keep this efficient at scale, sample which (store, product, date) combos
# actually have a transaction, rather than iterating every combo (which would be
# 55 stores x 600 products x 1095 days = 36M+ rows - unrealistic, no store sells
# every product every day).

TARGET_ROWS = 550_000
n_days = len(date_range)

# Precompute per-category seasonal multiplier per month
def seasonal_multiplier(category, month, seasonality_type):
    if seasonality_type == "high_festive" and month in [10, 11]:
        return np.random.uniform(1.8, 2.5)
    if seasonality_type == "high_seasonal" and month in [3, 4, 10, 11]:
        return np.random.uniform(1.5, 2.0)
    if seasonality_type == "medium_summer" and month in [4, 5, 6]:
        return np.random.uniform(1.4, 1.8)
    if seasonality_type == "high_back_to_school" and month in [6, 7]:
        return np.random.uniform(1.6, 2.1)
    return np.random.uniform(0.85, 1.15)

store_ids = dim_store["store_id"].values
product_ids = dim_product["product_id"].values

rows_generated = 0
batch = []
transaction_id = 1

# Generate transactions day by day (sampling active store-product pairs)
for date in date_range:
    month = date.month
    is_weekend = date.dayofweek >= 5
    # Not every store sells every product every day - sample a realistic subset
    n_transactions_today = int(np.random.uniform(450, 650) * (1.3 if is_weekend else 1.0))

    sampled_stores = np.random.choice(store_ids, size=n_transactions_today)
    sampled_products = np.random.choice(product_ids, size=n_transactions_today)

    for store_id, product_id in zip(sampled_stores, sampled_products):
        prod = product_lookup.loc[product_id]
        store = store_lookup.loc[store_id]

        seas_mult = seasonal_multiplier(prod["category"], month, prod["seasonality_type"])
        base_qty = np.random.poisson(lam=3) + 1
        qty = max(1, int(base_qty * store["demand_multiplier"] * seas_mult * (1.2 if is_weekend else 1.0)))

        # Regional price variance (+/- up to 8%)
        regional_price_factor = np.random.uniform(0.94, 1.08)
        unit_price = round(prod["unit_price"] * regional_price_factor, 2)

        # Promotions: ~12% of transactions have a discount
        has_discount = np.random.random() < 0.12
        discount_pct = round(np.random.uniform(0.05, 0.30), 2) if has_discount else 0.0

        revenue = round(qty * unit_price * (1 - discount_pct), 2)
        cost = round(qty * prod["unit_cost"], 2)

        batch.append({
            "transaction_id": transaction_id,
            "date_id": date.strftime("%Y-%m-%d"),
            "store_id": store_id,
            "product_id": product_id,
            "quantity_sold": qty,
            "unit_price": unit_price,
            "discount_pct": discount_pct,
            "revenue": revenue,
            "cost": cost,
        })
        transaction_id += 1

    rows_generated += n_transactions_today
    if rows_generated >= TARGET_ROWS:
        break

fact_sales = pd.DataFrame(batch)
print(f"fact_sales rows generated: {len(fact_sales):,}")

# -----------------------------------------------------------------
# 6. FACT_INVENTORY (daily snapshot, sampled to keep size reasonable)
# -----------------------------------------------------------------
print("Generating fact_inventory...")

inv_rows = []
inv_id = 1
# Sample ~1 inventory snapshot per store-product per week (not daily) - realistic
# for how inventory snapshots are usually stored/reported
weekly_dates = pd.date_range(START_DATE, END_DATE, freq="W")

for date in weekly_dates:
    for store_id in store_ids:
        store = store_lookup.loc[store_id]
        # Not all products stocked in all stores
        n_products_in_store = np.random.randint(60, 120)
        stocked_products = np.random.choice(product_ids, size=n_products_in_store, replace=False)
        for product_id in stocked_products:
            prod = product_lookup.loc[product_id]
            avg_daily_demand = max(1, int(3 * store["demand_multiplier"]))
            reorder_level = avg_daily_demand * 7  # ~1 week safety stock baseline
            stock_on_hand = max(0, int(np.random.normal(loc=reorder_level * 1.5, scale=reorder_level * 0.5)))

            inv_rows.append({
                "inventory_id": inv_id,
                "date_id": date.strftime("%Y-%m-%d"),
                "store_id": store_id,
                "product_id": product_id,
                "stock_on_hand": stock_on_hand,
                "reorder_level": reorder_level,
                "supplier_id": prod["supplier_id"],
            })
            inv_id += 1

fact_inventory = pd.DataFrame(inv_rows)
print(f"fact_inventory rows generated: {len(fact_inventory):,}")

# -----------------------------------------------------------------
# 7. SAVE ALL FILES
# -----------------------------------------------------------------
dim_store.to_csv(os.path.join(OUT_DIR, "dim_store.csv"), index=False)
dim_supplier.to_csv(os.path.join(OUT_DIR, "dim_supplier.csv"), index=False)
dim_product.to_csv(os.path.join(OUT_DIR, "dim_product.csv"), index=False)
dim_date.to_csv(os.path.join(OUT_DIR, "dim_date.csv"), index=False)
fact_sales.to_csv(os.path.join(OUT_DIR, "fact_sales.csv"), index=False)
fact_inventory.to_csv(os.path.join(OUT_DIR, "fact_inventory.csv"), index=False)

print("\n--- SUMMARY ---")
print(f"dim_store:      {len(dim_store):>10,} rows")
print(f"dim_supplier:   {len(dim_supplier):>10,} rows")
print(f"dim_product:    {len(dim_product):>10,} rows")
print(f"dim_date:       {len(dim_date):>10,} rows")
print(f"fact_sales:     {len(fact_sales):>10,} rows")
print(f"fact_inventory: {len(fact_inventory):>10,} rows")
total = len(dim_store) + len(dim_supplier) + len(dim_product) + len(dim_date) + len(fact_sales) + len(fact_inventory)
print(f"TOTAL ROWS:     {total:>10,}")
print(f"\nAll files saved to: {os.path.abspath(OUT_DIR)}")
