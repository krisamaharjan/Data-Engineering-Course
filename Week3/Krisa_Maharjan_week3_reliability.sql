--All SQL runs against the normalized schema from Week 2
-- (drivers, riders, locations, trips)

-- ─────────────────────────────────────────────────────────────────
-- Q1: Add indexes to the trips table
--
-- Before adding ANY index, run EXPLAIN ANALYZE on each query below
-- and record the execution time in a comment.
-- Then add your indexes and run EXPLAIN ANALYZE again.
-- The comparison IS the answer — not just the CREATE INDEX statement.
-- ─────────────────────────────────────────────────────────────────

-- Baseline queries — run EXPLAIN ANALYZE on each BEFORE indexing:

-- Query A: filter by driver

EXPLAIN ANALYZE 
	SELECT * FROM trips WHERE driver_id=3;

---Query A before: Seq Scan on trips, execution time = 2.025 ms

---------------------------------------------------------------------------

-- Query B: filter by status

EXPLAIN ANALYZE
	SELECT * FROM trips WHERE status= 'cancelled';

---Query A before: Seq Scan on trips, execution time = 1.547 ms

-----------------------------------------------------------------------------

EXPLAIN ANALYZE
	SELECT * FROM trips
	WHERE driver_id= 3 AND status= 'completed';

---Query A before: Seq Scan on trips, execution time = 2.714 ms

-----------------------------------------------------------------------------

CREATE INDEX indx_trips_driver_id ON trips(driver_id); 

EXPLAIN ANALYZE 
	SELECT * FROM trips WHERE driver_id=3;

---Query A After: Bitmap Heap Scan on trips, execution time = 0.907 ms

---------------------------------------------------------------------------

CREATE INDEX indx_trips_status ON trips(status);

EXPLAIN ANALYZE
	SELECT * FROM trips 
	WHERE status= 'cancelled';


---Query A After: Bitmap Heap Scan on trips, execution time = 0.496 ms

-----------------------------------------------------------------------------

CREATE INDEX indx_trips_driver_status ON trips(driver_id, status);

EXPLAIN ANALYZE
	SELECT * FROM trips
	WHERE driver_id= 3 AND status= 'completed';

---Query A before: Bitmap Heap Scan on trips, execution time = 0.788 ms

-----------------------------------------------------------------------------

-- ─────────────────────────────────────────────────────────────────
-- Q2: Create completed_trips_view

CREATE VIEW completed_trips_view AS 
SELECT 
t.trips_id,
d.name  AS driver_name,
p.name  AS passenger_name,
pck.city_name  AS pickup_city,
dst.city_name AS dropodd_city,
t.fare_amount,
t.distance_km,
t.rating,
t.payment_methods_id,
t.requested_at,
t.completed_at
FROM trips t
INNER JOIN drivers  d
ON t.driver_id = d.driver_id
INNER JOIN passengers p 
ON t.passenger_id = p.passenger_id
INNER JOIN locations pck
ON t.pickup_location_id = pck.location_id
INNER JOIN locations dst 
ON t.dropoff_location_id = dst.location_id
WHERE t.status = 'completed';

SELECT * FROM completed_trips_view LIMIT 5;

SELECT COUNT(*) FROM completed_trips_view;
-- count= 2862

-- ─────────────────────────────────────────────────────────────────
-- Q3: Create driver_summary view

CREATE VIEW driver_summary AS
SELECT
	d.name AS driver_name,
	COUNT(*) AS total_trips,
	COUNT(*) FILTER (WHERE t.status= 'completed') AS completed_trips,
	COUNT(*) FILTER (WHERE t.status= 'cancelled_trips') AS cancelled_trips,
	ROUND(
		COUNT(*) FILTER (WHERE t.status= 'cancelled_trips')*100.0/COUNT(*),1) AS cancelled_rate,
	ROUND(
		AVG(t.fare_amount) FILTER (WHERE t.status= 'completed_trips')::NUMERIC ,2) AS avg_fare,
	ROUND(
		AVG(t.rating) FILTER (WHERE t.status= 'completed_trips')::NUMERIC ,1) AS avg_rating
	FROM drivers d
	JOIN trips t
	ON d.driver_id= t.driver_id
	GROUP BY d.name;

SELECT * FROM driver_summary ORDER BY completed_trips DESC;


-- ─────────────────────────────────────────────────────────────────
-- Q4: Transaction with intentional failure

BEGIN;

INSERT INTO drivers(name) VALUES ('Test Driver');

--grab the new driver_id, or just subquery it below
INSERT INTO trips (driver_id,
	passenger_id,
	pickup_location_id,
	dropoff_location_id,
	fare_amount,
	distance_km,
	rating,
	payment_methods_id,
	status,
	requested_at,
	completed_at
)
VALUES
((SELECT driver_id FROM drivers d WHERE d.name='Test Driver'), 9, 3, 7, 15.00, 5.0, 5, 2, 'completed', now(), now()),
((SELECT driver_id FROM drivers d WHERE d.name='Test Driver'), 2, 4, 5, 40.00, 4.0, 3, 3, 'completed', now(), now()),
((SELECT driver_id FROM drivers d WHERE d.name='Test Driver'), 3, 7, 3, 90.00, 2.0, 5, 2, 'completed', now(), now())
;

INSERT INTO trips (driver_id,
	passenger_id,
	pickup_location_id,
	dropoff_location_id,
	fare_amount,
	distance_km,
	rating,
	payment_methods_id,
	status,
	requested_at,
	completed_at
)
VALUES
((SELECT driver_id FROM drivers d WHERE d.name='Test Driver'), 2, 4, 6, 115.00, 8.0, 99, 2, 'completed', now(), now());


COMMIT;

--ERROR: numeric field overflow Detail: A field with precision 2, scale 1 must round to an absolute value less than 10^1.

ROLLBACK ;

-- TEST DRIVER is deleted from the table


SELECT * FROM trips t
WHERE t.driver_id=15;

-- Verification query:
SELECT
    'drivers' AS tbl,
    COUNT(*) AS test_driver_rows
FROM drivers
WHERE name = 'Test Driver'
UNION ALL
SELECT 'trips', COUNT(*)
FROM trips t
JOIN drivers d ON t.driver_id = d.driver_id
WHERE d.name = 'Test Driver';

-- Expected: drivers = 0 and trips=0

-- ─────────────────────────────────────────────────────────────────
-- Q6 (STRETCH): Window function — running total fare per driver

SELECT 
	t.trips_id,
	d.name AS driver_name,
	t.requested_at,
	t.fare_amount,
	SUM(fare_amount) OVER (PARTITION BY d.driver_id ORDER BY requested_at) AS running_total_fare
	FROM trips t 
	JOIN drivers d 
	ON t.driver_id = d.driver_id
	WHERE t.status = 'completed'
	ORDER BY driver_name, t.requested_at ; 
	
	




