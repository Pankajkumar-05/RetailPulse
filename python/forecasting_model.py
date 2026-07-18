"""
RetailPulse - Demand Forecasting
------------------------------------
Forecasts future revenue/demand per category using Prophet
(handles seasonality, trend, holidays well - good fit for
retail data with festive-season spikes).

We forecast at the CATEGORY level (not per-product-per-store)
because: (a) it's more stable with less noise, (b) it directly
answers the business question "how much inventory value should
we plan for next quarter, by category", and (c) it's a common,
defensible scope for a first forecasting model - going straight
to SKU-store granularity would need far more historical data
per series to be reliable.

Run: python forecasting_model.py
Outputs:
  - ../data/processed/forecast_output.csv  (Power BI ready)
  - ../docs/charts/forecast_<category>.png
  - Console: MAPE (Mean Absolute Percentage Error) per category
"""

import sqlite3
import pandas as pd
import numpy as np
from prophet import Prophet
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import os
import warnings
warnings.filterwarnings("ignore")

BASE = os.path.dirname(__file__)
DB_PATH = os.path.join(BASE, "..", "retailpulse.db")
PROCESSED_DIR = os.path.join(BASE, "..", "data", "processed")
CHARTS_DIR = os.path.join(BASE, "..", "docs", "charts")
os.makedirs(PROCESSED_DIR, exist_ok=True)
os.makedirs(CHARTS_DIR, exist_ok=True)

conn = sqlite3.connect(DB_PATH)

sales = pd.read_sql("""
    SELECT f.date_id, f.revenue, p.category
    FROM fact_sales f
    JOIN dim_product p ON f.product_id = p.product_id
""", conn)
conn.close()

sales["date_id"] = pd.to_datetime(sales["date_id"])

# Aggregate to daily revenue per category
daily_cat = sales.groupby(["date_id", "category"])["revenue"].sum().reset_index()

FORECAST_HORIZON_DAYS = 90  # forecast next ~3 months
all_forecasts = []
mape_scores = {}

categories = daily_cat["category"].unique()
print(f"Forecasting {len(categories)} categories: {list(categories)}\n")

for cat in categories:
    cat_data = daily_cat[daily_cat["category"] == cat][["date_id", "revenue"]].copy()
    cat_data.columns = ["ds", "y"]
    cat_data = cat_data.sort_values("ds")

    # Train/test split for MAPE validation - hold out last 90 days
    split_point = cat_data["ds"].max() - pd.Timedelta(days=FORECAST_HORIZON_DAYS)
    train = cat_data[cat_data["ds"] <= split_point]
    test = cat_data[cat_data["ds"] > split_point]

    model = Prophet(
        yearly_seasonality=True,
        weekly_seasonality=True,
        daily_seasonality=False,
        seasonality_mode="multiplicative"  # revenue swings scale with level - fits retail better than additive
    )
    model.fit(train)

    future = model.make_future_dataframe(periods=FORECAST_HORIZON_DAYS)
    forecast = model.predict(future)

    # Evaluate against held-out actuals
    forecast_test = forecast[forecast["ds"] > split_point][["ds", "yhat"]]
    merged = test.merge(forecast_test, on="ds", how="inner")
    if len(merged) > 0:
        mape = np.mean(np.abs((merged["y"] - merged["yhat"]) / merged["y"].replace(0, np.nan))) * 100
        mape_scores[cat] = round(mape, 2)
        print(f"{cat:20s} MAPE: {mape:6.2f}%")
    else:
        mape_scores[cat] = None

    forecast["category"] = cat
    all_forecasts.append(forecast[["ds", "category", "yhat", "yhat_lower", "yhat_upper"]])

    # Plot actual vs forecast for this category
    plt.figure(figsize=(10, 5))
    plt.plot(cat_data["ds"], cat_data["y"], label="Actual", color="#2E86AB", alpha=0.6)
    plt.plot(forecast["ds"], forecast["yhat"], label="Forecast", color="#F18F01")
    plt.fill_between(forecast["ds"], forecast["yhat_lower"], forecast["yhat_upper"], alpha=0.2, color="#F18F01")
    plt.title(f"Revenue Forecast: {cat}")
    plt.legend()
    plt.tight_layout()
    safe_name = cat.replace(" ", "_").replace("&", "and")
    plt.savefig(os.path.join(CHARTS_DIR, f"forecast_{safe_name}.png"), dpi=110)
    plt.close()

# Combine all forecasts and export
final_forecast = pd.concat(all_forecasts, ignore_index=True)
final_forecast.columns = ["date_id", "category", "forecast_revenue", "forecast_lower", "forecast_upper"]
final_forecast.to_csv(os.path.join(PROCESSED_DIR, "forecast_output.csv"), index=False)

print(f"\nAverage MAPE across categories: {np.mean([v for v in mape_scores.values() if v is not None]):.2f}%")
print(f"Forecast output saved to: {os.path.join(PROCESSED_DIR, 'forecast_output.csv')}")
print(f"Charts saved to: {CHARTS_DIR}")

# Save MAPE scores for reference in reporting
with open(os.path.join(BASE, "..", "docs", "forecast_accuracy.txt"), "w") as f:
    f.write("RetailPulse Forecast Accuracy (MAPE %) by Category\n")
    f.write("=" * 50 + "\n")
    for cat, score in mape_scores.items():
        f.write(f"{cat}: {score}%\n")
    valid_scores = [v for v in mape_scores.values() if v is not None]
    f.write(f"\nAverage MAPE: {np.mean(valid_scores):.2f}%\n")
    f.write("\nNote: MAPE (Mean Absolute Percentage Error) measures forecast accuracy.\n")
    f.write("Lower is better. Under 20% is considered good for retail demand forecasting;\n")
    f.write("under 10% is excellent. Category-level forecasts are more stable than\n")
    f.write("SKU-level forecasts due to demand pooling across products.\n")
