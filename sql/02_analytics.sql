WITH price_lag AS (
    SELECT 
        s.ticker, 
        dp.trade_date,
        dp.close_price,
        LAG(dp.close_price) OVER (PARTITION BY dp.stock_id ORDER BY dp.trade_date) AS prev_close
    FROM daily_prices AS dp
    INNER JOIN stocks AS s
        ON dp.stock_id = s.stock_id
)
SELECT 
    ticker,
    trade_date, 
    close_price,
    prev_close,
    ROUND(((close_price - prev_close) / NULLIF(prev_close, 0)) * 100, 2) AS daily_return_pct
FROM price_lag
WHERE prev_close IS NOT NULL
ORDER BY ticker, trade_date
LIMIT 20;

-- 3. Annual Volatility Leaders (Top 3 per Year)

WITH yearly_volatility AS (
    SELECT
        EXTRACT(YEAR FROM dp.trade_date)::INT AS trade_year,
        s.ticker,
        COUNT(dp.trade_date) AS trading_days,
        ROUND(AVG(((dp.high_price - dp.low_price) / NULLIF(dp.low_price, 0)) * 100), 2) AS avg_daily_swing_pct,
        ROUND(AVG(dp.volume), 0) AS avg_daily_volume
    FROM daily_prices AS dp
    INNER JOIN stocks AS s
        ON dp.stock_id = s.stock_id
    GROUP BY trade_year, s.ticker
    HAVING COUNT(dp.trade_date) >= 200
),
ranked_volatility AS (
    SELECT
        trade_year,
        ticker,
        trading_days,
        avg_daily_swing_pct,
        avg_daily_volume,
        DENSE_RANK() OVER (
            PARTITION BY trade_year
            ORDER BY avg_daily_swing_pct DESC
        ) AS volatility_rank
    FROM yearly_volatility
)
SELECT
    trade_year,
    ticker,
    trading_days,
    avg_daily_swing_pct,
    avg_daily_volume,
    volatility_rank
FROM ranked_volatility
WHERE volatility_rank <= 3
ORDER BY trade_year ASC, 
volatility_rank ASC;


-- 4. Maximum Historical Drawdown (Top 10 Worst Drops)

WITH drawdown_calc AS (
    SELECT
        s.ticker,
        dp.close_price,
        MAX(dp.close_price) OVER (
            PARTITION BY dp.stock_id
            ORDER BY dp.trade_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_peak
    FROM daily_prices AS dp
    INNER JOIN stocks AS s
        ON dp.stock_id = s.stock_id
)
SELECT
    ticker,
    ROUND(MAX(close_price), 2) AS all_time_high_close,
    ROUND(MIN(close_price), 2) AS lowest_close_price,
    ROUND(MIN(((close_price - running_peak) / NULLIF(running_peak, 0)) * 100), 2) AS max_drawdown_pct
FROM drawdown_calc
GROUP BY ticker
ORDER BY max_drawdown_pct ASC
LIMIT 10;