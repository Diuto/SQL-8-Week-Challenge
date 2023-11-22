SET search_path = pizza_runner; --Set default schema to pizza_runner for queries

--DATA CLEANING

--CUSTOMER ORDERS
SELECT *
FROM customer_orders
ORDER BY order_time;

UPDATE customer_orders
SET exclusions = NULL
WHERE exclusions IN ('', 'null')

UPDATE customer_orders
SET extras = NULL
WHERE extras IN ('', 'null');

--RUNNER ORDERS
SELECT *
FROM runner_orders;

--Step 1: remove null strings from column, replace them with sql null
UPDATE runner_orders
SET pickup_time = (CASE WHEN pickup_time = 'null' THEN NULL
				   ELSE pickup_time END);
				   
--Step 2: remove nulls from distance and duration columns, then remove everything other than the numbers.
UPDATE runner_orders
SET distance = TRIM(CASE WHEN distance LIKE '%k%'
							THEN LEFT(distance, STRPOS(distance, 'k')-1)
						WHEN distance = 'null' 
							THEN NULL
						ELSE distance 
		 				END), --DISTANCE IS IN KILOMETRES 
	duration = TRIM(CASE WHEN duration LIKE '%min%'
							THEN LEFT(duration, STRPOS(duration, 'min')-1)
						WHEN duration = 'null' 
							THEN NULL
						ELSE duration
		 				END); --DURATION IS IN MINUTES
						
--Step 3: Change null strings and empty strings to sql nulls
UPDATE runner_orders
SET cancellation = NULL
WHERE cancellation IN ('', 'null');

--Step 4: Change the dat types of the necessary columns
ALTER TABLE runner_orders
ALTER COLUMN pickup_time TYPE timestamp USING pickup_time::timestamp without time zone,
ALTER COLUMN distance TYPE numeric USING distance::numeric,
ALTER COLUMN duration TYPE numeric USING duration::numeric;


--PIZZA RECIPES
SELECT *
FROM pizza_recipes;

--Unnest the Toppings
UPDATE pizza_recipes
SET toppings = UNNEST(string_to_array(toppings, ','))