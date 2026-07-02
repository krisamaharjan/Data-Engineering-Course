"""
transactional_loader.py
-----------------------
Week 3 Assignment — Q5

Loads a batch of trip dicts into the trips table inside a single
transaction. If any row fails, the entire batch is rolled back.
"""

import psycopg2
import logging
import os


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)s  %(message)s"
)
logger = logging.getLogger(__name__)

DB_CONFIG = dict(
    host=os.getenv("host"),
    port = os.getenv("port"),
    dbname = os.getenv("database"),
    user= os.getenv("user"),
    password=os.getenv("password")
)

INSERT_SQL = """
    INSERT INTO trips (
        driver_id, passenger_id,
        pickup_location_id, dropoff_location_id,
        fare_amount, distance_km, status,
        requested_at, completed_at, rating, payment_methods_id
    ) VALUES (
        %(driver_id)s, %(passenger_id)s,
        %(pickup_location_id)s, %(dropoff_location_id)s,
        %(fare_amount)s, %(distance_km)s, %(status)s,
        %(requested_at)s, %(completed_at)s,
        %(rating)s, %(payment_methods_id)s
    )
"""


def load_batch(conn, rows: list) -> int:
    
    # Turn off autocommit so nothing is saved until we explicitly commit
    conn.autocommit = False

    # "with" opens the cursor and auto-closes it when we leave this block,
    # whether things succeed or fail
    with conn.cursor() as cur:
        try:
          
            for row_number, row in enumerate(rows, start=1):
                cur.execute(INSERT_SQL, row)
           
            conn.commit()
            logger.info(f"Batch loaded successfully: {len(rows)} rows committed")
            return len(rows)

        except Exception as e:
           
            conn.rollback()
            logger.error(f"Batch failed on row {row_number}: {e}")

            # Never swallow the error — let the caller know it failed
            raise


def get_test_batches():
    """
    Returns two test batches:
      - good_batch: 5 valid trips (should commit)
      - bad_batch:  5 trips where row 3 has an invalid rating (should roll back)
    """
    base = dict(
        driver_id=1, passenger_id=1,
        pickup_location_id=1, dropoff_location_id=2,
        fare_amount=250.00, distance_km=8.5,
        status="completed",
        requested_at="2025-01-15 09:00:00",
        completed_at="2025-01-15 09:35:00",
        rating=4.5,
        payment_methods_id=1
    )

    good_batch = [{**base, "fare_amount": 100 * (i + 1)} for i in range(5)]

    bad_batch = []
    for i in range(5):
        row = {**base, "fare_amount": 100 * (i + 1)}
        if i == 2:
            row["rating"] = 99  # violates CHECK (rating BETWEEN 1.0 AND 5.0)
        bad_batch.append(row)

    return good_batch, bad_batch


def main():
    conn = psycopg2.connect(**DB_CONFIG)
    good_batch, bad_batch = get_test_batches()

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM trips")
        count_before = cur.fetchone()[0]
    conn.commit()
    logger.info(f"Trips before any load: {count_before:,}")

    # ── Test 1: good batch ────────────────────────────────────────
    logger.info("--- Test 1: loading good batch (expect success) ---")
    try:
        loaded = load_batch(conn, good_batch)
        logger.info(f"Test 1 passed: {loaded} rows loaded")
    except Exception as e:
        logger.error(f"Test 1 failed unexpectedly: {e}")

    # ── Test 2: bad batch ─────────────────────────────────────────
    logger.info("--- Test 2: loading bad batch (expect rollback) ---")
    try:
        loaded = load_batch(conn, bad_batch)
        logger.warning(f"Test 2: loaded {loaded} rows — was rollback triggered?")
    except Exception:
        logger.info("Test 2 passed: exception raised after rollback")

    # ── Verify final count ────────────────────────────────────────
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM trips")
        count_after = cur.fetchone()[0]

    logger.info(f"Trips after both tests: {count_after:,}")
    logger.info(f"Net rows added: {count_after - count_before}")
    # Expected: +5 (good batch committed, bad batch rolled back)

    conn.close()


if __name__ == "__main__":
    main()

"""
Output
2026-07-02 23:14:14,393  INFO  Trips before any load: 5,000
2026-07-02 23:14:14,393  INFO  --- Test 1: loading good batch (expect success) ---
2026-07-02 23:14:14,419  INFO  Batch loaded successfully: 5 rows committed
2026-07-02 23:14:14,419  INFO  Test 1 passed: 5 rows loaded
2026-07-02 23:14:14,419  INFO  --- Test 2: loading bad batch (expect rollback) ---
2026-07-02 23:14:14,420  ERROR  Batch failed on row 3: numeric field overflow
DETAIL:  A field with precision 2, scale 1 must round to an absolute value less than 10^1.

2026-07-02 23:14:14,420  INFO  Test 2 passed: exception raised after rollback
2026-07-02 23:14:14,421  INFO  Trips after both tests: 5,005
2026-07-02 23:14:14,421  INFO  Net rows added: 5

"""