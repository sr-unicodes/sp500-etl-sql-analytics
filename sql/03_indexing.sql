
-- 1. Baseline benchmarks

-- AAPL moving average: scans stocks_pkey and filters out 504 rows (5.95 ms)

EXPLAIN ANALYZE
SELECT
    s.ticker,
    dp.trade_date,
    dp.close_price,
    ROUND(AVG(dp.close_price) OVER (
        PARTITION BY dp.stock_id
        ORDER BY dp.trade_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma_7_day,
    ROUND(AVG(dp.close_price) OVER (
        PARTITION BY dp.stock_id
        ORDER BY dp.trade_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2) AS ma_30_day
FROM daily_prices AS dp
INNER JOIN stocks AS s
    ON dp.stock_id = s.stock_id
WHERE s.ticker = 'AAPL'
ORDER BY dp.trade_date DESC
LIMIT 20;


-- 2017 date range: full Seq Scan on daily_prices, 492,997 rows filtered (171.57 ms)

EXPLAIN ANALYZE
SELECT
    stock_id,
    trade_date,
    close_price,
    volume
FROM daily_prices
WHERE trade_date BETWEEN '2017-01-01' AND '2017-12-31';


-- 2. Create B-Tree indexes

CREATE INDEX IF NOT EXISTS idx_stocks_ticker
    ON stocks (ticker);

CREATE INDEX IF NOT EXISTS idx_daily_prices_trade_date
    ON daily_prices (trade_date);


-- 3. Post-index benchmarks

-- 2017 date range: switched to Bitmap Index Scan on idx_daily_prices_trade_date (19.52 ms, ~8.8x faster)

EXPLAIN ANALYZE
SELECT
    stock_id,
    trade_date,
    close_price,
    volume
FROM daily_prices
WHERE trade_date BETWEEN '2017-01-01' AND '2017-12-31';

-- AAPL moving average: planner still chose stocks_pkey over idx_stocks_ticker (9.33 ms, same plan cost).
-- With only 505 rows in stocks, scanning the pkey takes <0.1 ms anyway, so the secondary index isn't worth keeping.

EXPLAIN ANALYZE
SELECT
    s.ticker,
    dp.trade_date,
    dp.close_price,
    ROUND(AVG(dp.close_price) OVER (
        PARTITION BY dp.stock_id
        ORDER BY dp.trade_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS ma_7_day,
    ROUND(AVG(dp.close_price) OVER (
        PARTITION BY dp.stock_id
        ORDER BY dp.trade_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2) AS ma_30_day
FROM daily_prices AS dp
INNER JOIN stocks AS s
    ON dp.stock_id = s.stock_id
WHERE s.ticker = 'AAPL'
ORDER BY dp.trade_date DESC
LIMIT 20;

-- 4. Drop unused index to avoid extra write overhead during ETL loads

DROP INDEX IF EXISTS idx_stocks_ticker;