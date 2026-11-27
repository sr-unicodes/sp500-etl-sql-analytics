from datetime import datetime
from decimal import Decimal, InvalidOperation


def validate_row(row):

    ticker = (row.get("Name") or "").strip()
    if not ticker or len(ticker) > 10:
        return None, "Invalid or missing ticker"

    date_str = (row.get("date") or "").strip()
    try:
        trade_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        return None, f"Invalid date format: '{date_str}'"

    open_str = (row.get("open") or "").strip()
    high_str = (row.get("high") or "").strip()
    low_str = (row.get("low") or "").strip()
    close_str = (row.get("close") or "").strip()

    try:
        open_price = Decimal(open_str)
        high_price = Decimal(high_str)
        low_price = Decimal(low_str)
        close_price = Decimal(close_str)
    except InvalidOperation:
        return None, "Missing or non-numeric price value"

    if open_price < 0 or high_price < 0 or low_price < 0 or close_price < 0:
        return None, "Negative price value"

    if high_price < low_price:
        return None, f"High price ({high_price}) is less than low price ({low_price})"

    volume_str = (row.get("volume") or "").strip()
    try:
        volume = int(volume_str)
    except ValueError:
        return None, f"Invalid volume: '{volume_str}'"

    if volume < 0:
        return None, "Negative volume value"

    clean_row = {
        "ticker": ticker,
        "trade_date": trade_date,
        "open_price": open_price,
        "high_price": high_price,
        "low_price": low_price,
        "close_price": close_price,
        "volume": volume,
    }
    return clean_row, None


if __name__ == "__main__":
    good_row = {
        "date": "2018-02-07",
        "open": "163.085",
        "high": "163.4",
        "low": "159.0685",
        "close": "159.54",
        "volume": "51608580",
        "Name": "AAPL",
    }

    bad_row = {
        "date": "2018-02-07",
        "open": "",
        "high": "163.4",
        "low": "159.0685",
        "close": "159.54",
        "volume": "51608580",
        "Name": "AAPL",
    }

    print("Good row:", validate_row(good_row))
    print("Bad row: ", validate_row(bad_row))