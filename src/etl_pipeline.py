import os
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

CSV_PATH = os.path.join("data", "raw", "all_stocks_5yr.csv")

db_url = URL.create(
    drivername="postgresql+psycopg2",
    username=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST"),
    port=int(os.getenv("DB_PORT", 5432)),
    database=os.getenv("DB_NAME"),
)
engine = create_engine(db_url)

df = pd.read_csv(CSV_PATH)
df["csv_row_number"] = df.index + 2 
total_read = len(df)

df = df.rename(columns={
    "Name": "ticker",
    "date": "trade_date",
    "open": "open_price",
    "high": "high_price",
    "low": "low_price",
    "close": "close_price",
})


df["ticker"] = df["ticker"].str.strip()
df["trade_date"] = pd.to_datetime(df["trade_date"], errors="coerce")
for col in ["open_price", "high_price", "low_price", "close_price", "volume"]:
    df[col] = pd.to_numeric(df[col], errors="coerce")

required_cols = ["ticker", "trade_date", "open_price", "high_price", "low_price", "close_price", "volume"]
is_valid = (
    df[required_cols].notna().all(axis=1)
    & (df["ticker"] != "")
    & (df["open_price"] >= 0)
    & (df["high_price"] >= 0)
    & (df["low_price"] >= 0)
    & (df["close_price"] >= 0)
    & (df["volume"] >= 0)
    & (df["high_price"] >= df["low_price"])
)

valid_df = df[is_valid].drop_duplicates(subset=["ticker", "trade_date"]).copy()
valid_df["trade_date"] = valid_df["trade_date"].dt.date
valid_df["volume"] = valid_df["volume"].astype("int64")
bad_df = df[~is_valid].copy()


with engine.begin() as conn:
    run_id = conn.execute(
        text("INSERT INTO etl_audit_log (status) VALUES ('RUNNING') RETURNING run_id")
    ).scalar()


    existing_stocks = pd.read_sql("SELECT stock_id, ticker FROM stocks", conn)
    new_tickers = pd.DataFrame({"ticker": valid_df["ticker"].unique()})
    new_tickers = new_tickers[~new_tickers["ticker"].isin(existing_stocks["ticker"])]
    if not new_tickers.empty:
        new_tickers.to_sql("stocks", conn, if_exists="append", index=False)


    all_stocks = pd.read_sql("SELECT stock_id, ticker FROM stocks", conn)
    prices_to_load = valid_df.merge(all_stocks, on="ticker", how="inner")

    existing_keys = pd.read_sql("SELECT stock_id, trade_date FROM daily_prices", conn)
    if not existing_keys.empty:
        prices_to_load = prices_to_load.merge(
            existing_keys, on=["stock_id", "trade_date"], how="left", indicator=True
        )
        prices_to_load = prices_to_load[prices_to_load["_merge"] == "left_only"]

    price_cols = ["stock_id", "trade_date", "open_price", "high_price", "low_price", "close_price", "volume"]
    if not prices_to_load.empty:
        prices_to_load[price_cols].to_sql(
            "daily_prices", conn, if_exists="append", index=False, chunksize=2000, method="multi"
        )


    if not bad_df.empty:
        rejected_to_load = pd.DataFrame({
            "run_id": run_id,
            "csv_row_number": bad_df["csv_row_number"],
            "raw_payload": bad_df[required_cols].astype(str).apply(lambda r: r.to_json(), axis=1),
            "rejection_reason": "Missing or invalid price/date/volume",
        })
        rejected_to_load.to_sql("rejected_records", conn, if_exists="append", index=False)


    conn.execute(
        text("""
            UPDATE etl_audit_log
            SET finished_at = CURRENT_TIMESTAMP,
                total_rows_read = :read,
                rows_inserted = :inserted,
                rows_rejected = :rejected,
                status = 'SUCCESS'
            WHERE run_id = :run_id
        """),
        {
            "read": total_read,
            "inserted": len(prices_to_load),
            "rejected": len(bad_df),
            "run_id": run_id,
        },
    )

print(f"ETL SUCCESS (run_id={run_id}) | Read: {total_read} | Inserted: {len(prices_to_load)} | Rejected: {len(bad_df)}")