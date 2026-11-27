-- 04_views.sql
-- Analytical PostgreSQL views for Power BI dashboard integration

-- 1. Daily Price & Rolling Moving Averages (7-Day & 30-Day)

CREATE OR REPLACE VIEW vw_stock_daily_trends AS
SELECT
    s.ticker,
    dp.trade_date,
    dp.open_price,
    dp.high_price,
    dp.low_price,
    dp.close_price,
    dp.volume,
    ROUND(
        AVG(dp.close_price) OVER (
            PARTITION BY s.ticker
            ORDER BY dp.trade_date ASC
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )::NUMERIC,
        2
    ) AS ma_7_day,
    ROUND(
        AVG(dp.close_price) OVER (
            PARTITION BY s.ticker
            ORDER BY dp.trade_date ASC
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )::NUMERIC,
        2
    ) AS ma_30_day
FROM daily_prices AS dp
INNER JOIN stocks AS s
    ON dp.stock_id = s.stock_id;


-- 2. Yearly Performance & Annual Return Summary

CREATE OR REPLACE VIEW vw_stock_yearly_performance AS
WITH yearly_ranked AS (
    SELECT
        s.ticker,
        EXTRACT(YEAR FROM dp.trade_date)::INT AS trade_year,
        dp.close_price,
        dp.low_price,
        dp.high_price,
        dp.volume,
        ROW_NUMBER() OVER (
            PARTITION BY s.ticker, EXTRACT(YEAR FROM dp.trade_date)
            ORDER BY dp.trade_date ASC
        ) AS yrs_first,
        ROW_NUMBER() OVER (
            PARTITION BY s.ticker, EXTRACT(YEAR FROM dp.trade_date)
            ORDER BY dp.trade_date DESC
        ) AS yrs_last
    FROM daily_prices AS dp
    INNER JOIN stocks AS s
        ON dp.stock_id = s.stock_id
),
yearly_agg AS (
    SELECT
        ticker,
        trade_year,
        ROUND(AVG(close_price)::NUMERIC, 2) AS avg_close_price,
        MIN(low_price) AS min_low_price,
        MAX(high_price) AS max_high_price,
        SUM(volume) AS total_volume,
        MAX(CASE WHEN yrs_first = 1 THEN close_price END) AS year_open_close,
        MAX(CASE WHEN yrs_last = 1 THEN close_price END) AS year_end_close
    FROM yearly_ranked
    GROUP BY ticker, trade_year
)
SELECT
    ticker,
    trade_year,
    avg_close_price,
    min_low_price,
    max_high_price,
    total_volume,
    year_open_close,
    year_end_close,
    ROUND(
        (((year_end_close - year_open_close)::NUMERIC / NULLIF(year_open_close, 0)) * 100),
        2
    ) AS annual_return_pct
FROM yearly_agg;


-- 3. 5-Year Risk, Return & Volatility Summary

CREATE OR REPLACE VIEW vw_stock_volatility_summary AS
WITH price_with_prev AS (
    SELECT
        s.ticker,
        dp.close_price,
        dp.volume,
        LAG(dp.close_price) OVER (
            PARTITION BY s.ticker
            ORDER BY dp.trade_date ASC
        ) AS prev_close
    FROM daily_prices AS dp
    INNER JOIN stocks AS s
        ON dp.stock_id = s.stock_id
),
daily_returns AS (
    SELECT
        ticker,
        volume,
        (((close_price - prev_close)::NUMERIC / NULLIF(prev_close, 0)) * 100) AS daily_return_pct
    FROM price_with_prev
)
SELECT
    ticker,
    COUNT(*) AS total_trading_days,
    ROUND(AVG(daily_return_pct)::NUMERIC, 4) AS avg_daily_return_pct,
    ROUND(STDDEV(daily_return_pct)::NUMERIC, 4) AS daily_volatility_pct,
    ROUND(AVG(volume)::NUMERIC, 0) AS avg_daily_volume
FROM daily_returns
GROUP BY ticker;