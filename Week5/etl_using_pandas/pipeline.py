import argparse
import logging
import os
import time
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

# Load .env from Week5/.env
load_dotenv(Path(__file__).parent.parent / ".env")

from extract import (
    extract_driver,
    extract_vehicle,
    extract_passenger,
    extract_location,
    extract_payment_method,
    extract_promo_code,
    extract_trips_incremental,
    extract_trips_full,
    extract_lookup_dim,
    get_watermark,
)

from transform import (
    derive_driver_dim,
    derive_passenger_dim,
    derive_location_dim,
    transform_trips,
)

from load import (
    truncate_warehouse,
    load_dim_driver,
    load_dim_vehicle,
    load_dim_passenger,
    load_dim_location,
    load_dim_payment_method,
    load_dim_promo_code,
    load_fact_trips,
)

from quality import run_quality_checks


def parse_args():
    parser = argparse.ArgumentParser(description="Rides ETL pipeline (pandas)")
    parser.add_argument(
        "--full-reload",
        action="store_true",
        help="Truncate warehouse and reload all data (default: incremental)",
    )
    return parser.parse_args()


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(filename)s:%(lineno)d] %(message)s",
)
logger = logging.getLogger(__name__)


SOURCE_DB_CONFIG = {
    "host": os.getenv("SOURCE_DB_HOST"),
    "port": os.getenv("SOURCE_DB_PORT"),
    "dbname": os.getenv("SOURCE_DB_NAME"),
    "user": os.getenv("SOURCE_DB_USER"),
    "password": os.getenv("SOURCE_DB_PASSWORD"),
}

DEST_DB_CONFIG = {
    "host": os.getenv("DEST_DB_HOST"),
    "port": os.getenv("DEST_DB_PORT"),
    "dbname": os.getenv("DEST_DB_NAME"),
    "user": os.getenv("DEST_DB_USER"),
    "password": os.getenv("DEST_DB_PASSWORD"),
}


def main():
    args = parse_args()
    mode = "FULL" if args.full_reload else "INCREMENTAL"

    print(f"Running mode: {mode}", flush=True)

    src_conn = psycopg2.connect(**SOURCE_DB_CONFIG)
    dst_conn = psycopg2.connect(**DEST_DB_CONFIG)

    try:
        # Full reload: truncate warehouse tables first
        if mode == "FULL":
            logger.info("Truncating warehouse tables...")
            truncate_warehouse(dst_conn)

        # -------------------------
        # Load dimension tables
        # -------------------------
        time0 = time.time()

        load_dim_driver(dst_conn, derive_driver_dim(extract_driver(src_conn)))
        load_dim_vehicle(dst_conn, extract_vehicle(src_conn))
        load_dim_passenger(dst_conn, derive_passenger_dim(extract_passenger(src_conn)))
        load_dim_location(dst_conn, derive_location_dim(extract_location(src_conn)))
        load_dim_payment_method(dst_conn, extract_payment_method(src_conn))
        load_dim_promo_code(dst_conn, extract_promo_code(src_conn))

        logger.info(
            f"Dimension table load completed in {time.time() - time0:.2f}s"
        )

        # -------------------------
        # Extract lookup tables
        # -------------------------
        time0 = time.time()

        lookups = extract_lookup_dim(dst_conn)

        logger.info(
            f"Lookup table extraction completed in {time.time() - time0:.2f}s"
        )

        logger.info(
            f"Connecting to source: "
            f"{SOURCE_DB_CONFIG['host']}:{SOURCE_DB_CONFIG['port']}/"
            f"{SOURCE_DB_CONFIG['dbname']}"
        )

        # -------------------------
        # Extract trips
        # -------------------------
        time0 = time.time()

        if mode == "INCREMENTAL":
            watermark = get_watermark(dst_conn)
            trips_df = extract_trips_incremental(src_conn, watermark)
        else:
            trips_df = extract_trips_full(src_conn)

        logger.info(
            f"Trip extraction completed in {time.time() - time0:.2f}s"
        )

        # -------------------------
        # Transform
        # -------------------------
        time0 = time.time()

        fact_df = transform_trips(trips_df, lookups)

        logger.info(
            f"Transformation completed in {time.time() - time0:.2f}s"
        )

        # -------------------------
        # Quality + Load
        # -------------------------
        if fact_df.empty:
            logger.info("No new rows to load — pipeline finished.")
        else:
            time0 = time.time()

            run_quality_checks(fact_df)

            logger.info(
                f"Quality checks completed in {time.time() - time0:.2f}s"
            )

            time0 = time.time()

            load_fact_trips(dst_conn, fact_df)

            logger.info(
                f"Fact table load completed in {time.time() - time0:.2f}s"
            )

    finally:
        src_conn.close()
        dst_conn.close()


if __name__ == "__main__":
    main()