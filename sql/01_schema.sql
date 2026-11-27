DROP TABLE IF EXISTS rejected_records;
DROP TABLE IF EXISTS etl_audit_log;
DROP TABLE IF EXISTS daily_prices;
DROP TABLE IF EXISTS stocks;

CREATE TABLE stocks (
    stock_id SERIAL PRIMARY KEY,
    ticker VARCHAR(10) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE daily_prices(
    price_id SERIAL PRIMARY KEY,
    stock_id INT NOT NULL REFERENCES stocks(stock_id) ON DELETE CASCADE,
    trade_date DATE NOT NULL,
    open_price NUMERIC(12, 4) NOT NULL CHECK (open_price >= 0),
    high_price NUMERIC(12, 4) NOT NULL CHECK (high_price >= 0),
    low_price NUMERIC(12, 4) NOT NULL CHECK (low_price >= 0),
    close_price NUMERIC(12, 4) NOT NULL CHECK (close_price >= 0),
    volume BIGINT NOT NULL CHECK (volume >= 0),
    CONSTRAINT uq_stock_trade_date UNIQUE (stock_id, trade_date),
    CONSTRAINT chk_high_gte_low CHECK (high_price >= low_price)
);


CREATE TABLE etl_audit_log(
    run_id SERIAL PRIMARY KEY,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP,
    total_rows_read INT DEFAULT 0,
    rows_inserted INT DEFAULT 0,
    rows_rejected INT DEFAULT 0,
    status VARCHAR(20) NOT NULL

);

CREATE TABLE rejected_records(
reject_id SERIAL PRIMARY KEY,
run_id INT REFERENCES etl_audit_log(run_id) ON DELETE CASCADE,
csv_row_number INT NOT NULL,
raw_payload TEXT NOT NULL,
rejection_reason TEXT NOT NULL,
rejected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);