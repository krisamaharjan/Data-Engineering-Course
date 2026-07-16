"""
Standalone demo: proves the quality gate halts on bad data.
The production source DB enforces constraints that make it
impossible to insert genuinely bad rows through `trips` — so
this test exercises quality.py directly with a synthetic
DataFrame, the same shape transform_trips() would produce.
"""
import logging
import pandas as pd

from quality import run_quality_checks, DataQualityError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(filename)s:%(lineno)d] %(message)s",
)

bad_df = pd.DataFrame([{
    "source_trip_id": 99001,
    "date_key": 20260716,
    "driver_key": 1,
    "vehicle_key": 1,
    "passenger_key": 1,
    "pickup_location_key": 1,
    "dropoff_location_key": 2,
    "payment_method_key": 1,
    "promo_code_key": pd.NA,
    "base_fare": 20.0,
    "tip_amount": 0.0,
    "discount_amount": 0.0,
    "fare_amount": -25.00,   # deliberately invalid
    "distance_km": 5.0,
    "status": "completed",
    "duration_minutes": 10.0,
    "driver_rating": 5.0,
    "passenger_rating": 5.0,
    "surge_multiplier": 1.0,
    "requested_at": pd.Timestamp.now(),
    "time_key": 1,
}])

print("Running quality gate against a synthetic bad row...")
try:
    run_quality_checks(bad_df)
except DataQualityError as e:
    logging.error(str(e))
    print("Quality gate correctly halted on bad data.")