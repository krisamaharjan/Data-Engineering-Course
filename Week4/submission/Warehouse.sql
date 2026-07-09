DROP TABLE IF EXISTS dim_vehicle;

CREATE TABLE dim_vehicle (
    vehicle_key     SERIAL PRIMARY KEY,          -- surrogate key
    vehicle_id      INTEGER NOT NULL UNIQUE,     -- natural key from OLTP vehicles table
    plate_number    VARCHAR(20) NOT NULL,
    make            VARCHAR(50) NOT NULL,
    model           VARCHAR(50) NOT NULL,
    year            INTEGER NOT NULL,
    color           VARCHAR(20),
    category        VARCHAR(20) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
    
);

-- ─────────────────────────────────────────────────────────────────────────────
-- dim_time
-- Pre-populated with every 15-minute bucket (96 rows).
-- time_key format: HHMM integer rounded down to nearest 15 min.
-- Example: a trip requested at 14:37 gets time_key = 1430.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE dim_time (
    time_key        INTEGER      PRIMARY KEY,   -- HHMM, e.g. 1430 = 2:30 PM
    hour            SMALLINT     NOT NULL CHECK (hour BETWEEN 0 AND 23),
    minute_bucket   SMALLINT     NOT NULL CHECK (minute_bucket IN (0, 15, 30, 45)),
    time_label      VARCHAR(8)   NOT NULL,      -- '14:30'
    time_of_day     VARCHAR(12)  NOT NULL,      -- 'Morning' / 'Afternoon' / 'Evening' / 'Night'
    is_rush_hour    BOOLEAN      NOT NULL       -- TRUE for 7-9am and 5-8pm weekday proxy
);


INSERT INTO dim_time (time_key, hour, minute_bucket, time_label, time_of_day, is_rush_hour)
SELECT
    h * 100 + m                                   AS time_key,
    h                                              AS hour,
    m                                              AS minute_bucket,
    to_char(make_time(h, m, 0), 'HH24:MI')         AS time_label,
    CASE
        WHEN h BETWEEN 5  AND 11 THEN 'Morning'
        WHEN h BETWEEN 12 AND 16 THEN 'Afternoon'
        WHEN h BETWEEN 17 AND 20 THEN 'Evening'
        ELSE 'Night'
    END                                            AS time_of_day,
    (h IN (7, 8, 9, 17, 18, 19))                   AS is_rush_hour
FROM generate_series(0, 23) AS h,
     generate_series(0, 45, 15) AS m
ORDER BY h, m;


ALTER TABLE fact_trips
    ADD COLUMN vehicle_key INTEGER NOT NULL REFERENCES dim_vehicle(vehicle_key),
    ADD COLUMN time_key    INTEGER NOT NULL REFERENCES dim_time(time_key);


SELECT * FROM dim_date dd ;

SELECT * FROM dim_driver dd;

SELECT * FROM dim_time;

SELECT * FROM dim_vehicle;

SELECT COUNT(*) FROM fact_trips;   --count: 10,000

SELECT COUNT(*) FROM fact_trips WHERE vehicle_key IS NULL OR time_key IS NULL;  --count: 0

ALTER TABLE fact_trips
    ALTER COLUMN vehicle_key SET NOT NULL,
    ALTER COLUMN time_key SET NOT NULL;

SELECT * FROM fact_trips;

SELECT * FROM dim_location dl ;

SELECT * FROM dim_passenger dp ;

SELECT * FROM dim_payment_method dpm ;

---------------------------------------------------------------------------------------
-------  3. Revenue by city / month
--Write a warehouse query that returns total revenue grouped by pickup city and month.

--Then write the equivalent query against the OLTP schema (trips, locations, etc.) directly.

--Answer: how many table joins does each version need? Which one needed fewer, and why?


SELECT 
	sum(ft.fare_amount) AS total_revenue,
	ft.pickup_location_key,
	dd.YEAR,
	dd.MONTH 
FROM fact_trips ft 
LEFT JOIN dim_location dl
ON dl.location_key = ft.pickup_location_key 
LEFT JOIN dim_date dd 
ON dd.date_key =ft.date_key 
GROUP BY ft.pickup_location_key , dd.YEAR, dd.MONTH
ORDER BY ft.pickup_location_key , dd.YEAR, dd.MONTH;



SELECT
    l.city_name,
    EXTRACT(YEAR  FROM t.requested_at) AS year,
    EXTRACT(MONTH FROM t.requested_at) AS month,
    SUM(
        t.base_fare * t.surge_multiplier + t.tip_amount - t.discount_amount
    ) AS total_revenue
FROM trips t
JOIN locations l ON t.pickup_location_id = l.location_id
GROUP BY l.city_name, year, month
ORDER BY l.city_name, year, month;


---how many table joins does each version need? Which one needed fewer, and why?
--ANSWER:
--Warehouse query: 2 joins (dim_location, dim_date)
--OLTP query: 1 join (locations)
--OLTP needed fewer joins.
--Why: in OLTP, the date is just a timestamp column already on trips — no lookup needed. In the warehouse, dates live in their own dim_date table, so getting the month costs an extra join.
--This is specific to this simple query, though. Add more filters (driver, vehicle type, payment method) and the warehouse stays easy — one join per dimension. OLTP gets messier fast, since you'd need more joins and have to recompute fare math by hand every time.


-----------------------------------------------------------------------------------------

--4. Payment method revenue
--Write a warehouse query for total revenue per payment method.

SELECT
	dpm.name AS payment_method, 
	sum(ft.fare_amount) AS total_revenue	
FROM fact_trips ft 
LEFT JOIN dim_payment_method dpm 
ON dpm.payment_method_key = ft.payment_method_key 
GROUP BY dpm.name
ORDER BY total_revenue DESC ;

--Extend it (or write a second query) for average fare per trip, per payment method, per month.

SELECT
	dpm.name AS payment_method, 
	dd.YEAR,
	dd.MONTH,
	Round(avg(ft.fare_amount),2) AS Avg_total_revenue,
	count(*) AS trip_count
FROM fact_trips ft 
JOIN dim_payment_method dpm 
ON dpm.payment_method_key = ft.payment_method_key
JOIN  dim_date dd 
ON dd.date_key = ft.date_key 
GROUP BY dpm.name,dd.year , dd.MONTH
ORDER BY dpm.name,dd.year , dd.MONTH;

--------------------------------------------------------------------------------------------------

--5. Busiest hour of day
--Write a warehouse query that returns trip count per hour of day (0–23),
--along with each hour's percentage of all trips — computed with a window function (not a second query for the grand total).

SELECT
    dt.hour,
    COUNT(*) AS trip_count,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_all_trips
FROM fact_trips ft
JOIN dim_time dt ON ft.time_key = dt.time_key
GROUP BY dt.hour
ORDER BY dt.hour;


-----------------------------------------------------------------------------------------------

SELECT MAX(requested_at) FROM fact_trips;

--Output : max- 2026-06-29 21:53:01.00


/*

7. Modify etl.py so the fact load only extracts trips newer than the MAX(requested_at) already present in fact_trips.
Where should that watermark be read from, and what happens the very first time the ETL runs against an empty warehouse?

2026-07-09 16:13:25,285 [INFO] Extracted 25 from the table
2026-07-09 16:13:25,294 [INFO] 0 inserted to dim_driver
2026-07-09 16:13:25,311 [INFO] Extracted 30 from the table
2026-07-09 16:13:25,315 [INFO] 0 inserted to dim_vehicle
2026-07-09 16:13:25,328 [INFO] Extracted 45 from the table
2026-07-09 16:13:25,335 [INFO] 0 inserted to dim_passenger
2026-07-09 16:13:25,353 [INFO] Extracted 25 from the table
2026-07-09 16:13:25,362 [INFO] 0 inserted to dim_location
2026-07-09 16:13:25,363 [INFO] Extracted 7 from the table
2026-07-09 16:13:25,364 [INFO] 0 inserted to dim_payment_method
2026-07-09 16:13:25,370 [INFO] Extracted 10 from the table
2026-07-09 16:13:25,386 [INFO] 0 inserted to dim_promo_code
2026-07-09 16:13:25,394 [INFO] Loading lookup table into memmory
2026-07-09 16:13:25,476 [INFO] Using watermark: 2026-06-29 21:53:01
2026-07-09 16:13:25,480 [INFO] Extracted 0 from the table
2026-07-09 16:13:25,480 [INFO] Transformed 0 rows, skipped 0
2026-07-09 16:13:25,480 [INFO] No fact rows to load — skipping
*/







