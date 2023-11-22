SET search_path = pizza_runner;

--A. PIZZA METRICS
SELECT * 
FROM customer_orders;

--#1. Number of Pizzas Ordered
SELECT COUNT(*) AS num_pizzas
FROM customer_orders; --14 pizzas ordered

--#2. How many unique orders were placed?
SELECT COUNT(DISTINCT order_id) num_orders
FROM customer_orders; --10 orders

--#3. Successful deliveries by each runner
SELECT runner_id, COUNT(*) successful_deliveries
FROM runner_orders
WHERE cancellation IS NULL
GROUP BY runner_id; --4 deliveries by runner 1, 3 by runner 2, and 1 by runner 3

--#4. How many of each type of pizza was delivered
SELECT pizza_name, COUNT(*) num_deliveries
FROM customer_orders c
LEFT JOIN runner_orders r
USING (order_id)
LEFT JOIN pizza_names
USING (pizza_id)
WHERE cancellation IS NULL
GROUP BY pizza_name; --3 Vegetarian and 9 Meatlovers pizzas delivered

--#5 Number of Meatlover and Vegetarian orders by each customer
SELECT customer_id, pizza_name, COUNT(*) num_orders
FROM customer_orders
LEFT JOIN pizza_names
USING (pizza_id)
GROUP BY customer_id, pizza_name
ORDER BY customer_id, pizza_name; --Result a bit too long to write here

--#6. Maximum pizzas in a single order
SELECT COUNT(*) AS num_pizzas
FROM customer_orders c
LEFT JOIN runner_orders r
ON c.order_id = r.order_id
WHERE cancellation IS NULL
GROUP BY c.order_id
ORDER BY num_pizzas DESC
LIMIT 1; --3 pizzas; the maximum single-order delivery

--#7. Changes
SELECT
	customer_id,
	CASE WHEN exclusions IS NULL AND extras IS NULL
			THEN 'Change'
		ELSE 'No Change'
	END AS pizza_state,
	COUNT(*) AS num_pizzas
FROM customer_orders c
LEFT JOIN runner_orders r
ON c.order_id = r.order_id
WHERE cancellation IS NULL
GROUP BY 1, 2
ORDER BY 1, 2; --See results when you run query

--#8. Delivered Pizzas with exclusions and extras
SELECT COUNT(*) AS num_pizzas
FROM customer_orders c
LEFT JOIN runner_orders r
ON c.order_id = r.order_id
WHERE cancellation IS NULL
	AND (CASE WHEN exclusions IS NOT NULL AND extras IS NOT NULL
			THEN 1
		ELSE 0
	END) = 1
ORDER BY 1; --Only one delivered pizza had both exclusions and extras

--#9. Number of Orders, each hour of the day.
SELECT DATE_PART('hour', order_time) AS hour, COUNT(*) AS num_orders
FROM customer_orders
GROUP BY 1
ORDER BY 1;

--#10. Number of Orders, each day of the week.
SELECT to_char(order_time, 'Day') AS weekday, COUNT(*) AS num_orders
FROM customer_orders
GROUP BY 1
ORDER BY 2 DESC;


--B: RUNNER AND CUSTOMER EXPERIENCE
SELECT *
FROM runners;

--#1. Number of Runner Signups Each 
SELECT 
	'Week '|| DATE_PART('week', registration_date + 3) AS week_num,
	COUNT(*) AS num_signups
FROM runners
GROUP BY 1
ORDER BY 1;

--#2. Avg. Runner Arrival Time
SELECT runner_id, ROUND(AVG(EXTRACT(EPOCH FROM (pickup_time - order_time))/60), 2) AS avg_pickup_time --runner_id, ROUND(AVG(duration), 2) || ' mins' AS avg_duration
FROM runner_orders r
LEFT JOIN customer_orders c
ON c.order_id = r.order_id
GROUP BY 1
ORDER BY 1;

--#3. Correlation between num_pizzas and preparation time
WITH tmp AS (SELECT 
	order_id,
	ROUND(EXTRACT(EPOCH FROM (pickup_time - order_time))/60.0, 2) AS order_to_pickup,
	COUNT(order_id) AS num_pizzas
FROM customer_orders c
LEFT JOIN runner_orders r
USING (order_id)
WHERE pickup_time IS NOT NULL
GROUP BY 1, 2
ORDER BY 1)

SELECT ROUND(CORR(order_to_pickup, num_pizzas)::NUMERIC, 3) AS correlation
FROM tmp; --Correlation value of 0.836 shows a strong positive correlation between number of pizzas and time taken to prepare

--#4. Avg Distance Travelled for Each Customer
SELECT customer_id, ROUND(AVG(distance), 1) AS avg_distance
FROM (
	SELECT DISTINCT order_id, customer_id, distance
	FROM runner_orders r
	LEFT JOIN customer_orders c
	USING (order_id)
	WHERE distance IS NOT NULL
	ORDER BY order_id
	) AS orders
GROUP BY 1
ORDER BY 2 DESC;

--#5. Longest vs Shortest Delivery Times
SELECT 
	MAX(duration) AS max_delivery_time,
	MIN(duration) AS min_delivery_time,
	MAX(duration)-MIN(duration) AS difference
FROM runner_orders;

--#6. Avg. speed each runner, each delivery
SELECT 
	order_id,
	runner_id,
	ROUND(distance/(duration/60.0), 1) || ' km/hr' AS avg_speed
FROM runner_orders
WHERE duration IS NOT NULL
ORDER BY runner_id, order_id; 

--#7. Delivery Percentage Each Runner
WITH flagger AS (SELECT 
	order_id,
	runner_id, 
	CASE WHEN cancellation IS NULL
			THEN 1
		ELSE 0 
		END AS delivery_flag
FROM runner_orders)

SELECT runner_id, ROUND(SUM(delivery_flag*100.0)/COUNT(*), 2) || '%' AS perc_delivery
FROM flagger
GROUP BY runner_id;


--C: INGREDIENT OPTIMISATION

--#1. Ingredients for each pizza
WITH tops AS (
	SELECT pizza_id, TRIM(UNNEST(string_to_array(toppings, ','))) AS toppings
	FROM pizza_recipes
	),
	recipes AS (
	SELECT *
	FROM tops t
	LEFT JOIN pizza_toppings p
	ON p.topping_id::varchar = t.toppings
	)
SELECT pizza_id, STRING_AGG(topping_name, ', ') AS ingredients
FROM recipes
GROUP BY pizza_id
ORDER BY pizza_id;

--#2. The most commonly-added extra
SELECT topping_name AS extra, COUNT(*) AS num_orders
FROM customer_orders c
LEFT JOIN pizza_toppings p
ON p.topping_id = LEFT(extras, 1)::integer
	OR p.topping_id = RIGHT(extras, 1)::integer
WHERE extras IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC
LIMIT 1; --Bacon is the most-added extra; it was added four times

--#3. What was the most common exclusion?
SELECT topping_name AS exclusion, COUNT(*) AS num_orders
FROM customer_orders c
LEFT JOIN pizza_toppings p
ON p.topping_id = LEFT(exclusions, 1)::integer
	OR p.topping_id = RIGHT(exclusions, 1)::integer
WHERE exclusions IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC
LIMIT 1; --Cheese was the most common exclusion; 4 times, it was excluded


--#4. Generate an Order Item
/*WITH extra_items AS (
	SELECT order_id, customer_id, pizza_id, exclusions, extras, order_time, STRING_AGG(topping_name, ', ') AS extras_ing
	FROM customer_orders
	LEFT JOIN pizza_toppings p
	ON p.topping_id = LEFT(extras, 1)::integer
		OR p.topping_id = RIGHT(extras, 1)::integer
	WHERE extras IS NOT NULL
	GROUP BY 1,2,3,4,5, 6
	),
	exclusions_items AS (
	SELECT DISTINCT
		order_id,
		customer_id,
		pizza_id,
		exclusions,
		extras,
		order_time,
		STRING_AGG(topping_name, ', ') AS exclusions_ing
	FROM customer_orders
	LEFT JOIN pizza_toppings p
	ON p.topping_id = LEFT(exclusions, 1)::integer
		OR p.topping_id = RIGHT(exclusions, 1)::integer
	WHERE exclusions IS NOT NULL
	GROUP BY 1,2,3,4,5, 6
	),
	pizzas AS (
	SELECT *
	FROM customer_orders c
	LEFT JOIN pizza_names p
	USING(pizza_id)
	)

SELECT DISTINCT
	p.order_id, 
	p.customer_id, 
	p.pizza_id, 
	p.exclusions,
	p.extras,
	p.order_time,
	(CASE WHEN p.exclusions IS NULL AND p.extras IS NULL
			THEN p.pizza_name
		WHEN p.exclusions IS NOT NULL AND p.extras IS NOT NULL
			THEN p.pizza_name || ' - Exclude ' || exclusions_ing || ' -  Extra ' || extras_ing
		WHEN p.extras IS NOT NULL AND p.exclusions IS NULL
			THEN p.pizza_name || ' - Extra ' || extras_ing
		ELSE  p.pizza_name || ' - Exclude ' || exclusions_ing
	END) AS order_item
FROM pizzas p
LEFT JOIN extra_items e
ON p.order_id = e.order_id
	AND p.extras = e.extras
	--AND p.exclusions = e.exclusions
LEFT JOIN exclusions_items ec
ON p.order_id = ec.order_id
	--AND p.extras = ec.extras
	AND p.exclusions = ec.exclusions
ORDER BY p.order_time;*/

WITH keyed AS (
	SELECT ROW_NUMBER() OVER(ORDER BY order_id) AS p_key, *
	FROM customer_orders
	ORDER BY order_time
),
	extras_items AS (
	SELECT p_key, STRING_AGG(topping_name, ', ') AS extras_ing
	FROM keyed k
	LEFT JOIN pizza_toppings p
	ON p.topping_id = LEFT(extras, 1)::integer
		OR p.topping_id = RIGHT(extras, 1)::integer
	WHERE extras IS NOT NULL
	GROUP BY 1
	),
	exclusions_items AS (
	SELECT p_key, STRING_AGG(topping_name, ', ') AS exclusions_ing
	FROM keyed k
	LEFT JOIN pizza_toppings p
	ON p.topping_id = LEFT(exclusions, 1)::integer
		OR p.topping_id = RIGHT(exclusions, 1)::integer
	WHERE exclusions IS NOT NULL
	GROUP BY 1
	)
SELECT
	order_id,
	customer_id,
	pizza_id,
	exclusions,
	extras,
	order_time,
	(
		CASE WHEN exclusions IS NULL AND extras IS NULL
				THEN pizza_name
			WHEN exclusions IS NOT NULL AND extras IS NOT NULL
				THEN pizza_name || ' - Exclude ' || exclusions_ing || ' -  Extra ' || extras_ing
			WHEN extras IS NOT NULL AND exclusions IS NULL
				THEN pizza_name || ' - Extra ' || extras_ing
			ELSE  pizza_name || ' - Exclude ' || exclusions_ing
		END
	) AS order_item
FROM keyed k
LEFT JOIN extras_items et
USING (p_key)
LEFT JOIN exclusions_items ec
USING (p_key)
LEFT JOIN pizza_names p
USING (pizza_id)
ORDER BY order_id, order_time; --This particular question... you'll crumble for the shege you made me see despite such a simple solution!!!


--#5. Alphabetically ordered, comma-separated ingredient list for each pizza. Use a 2x in front of any one.
WITH tmp AS (
	SELECT ROW_NUMBER() OVER(ORDER BY order_id) AS p_key, * --Create Primary key for each row in customer orders
	FROM customer_orders
	ORDER BY order_time
),
	new_tops AS (
		SELECT 
			p_key,
			toppings,
			exclusions,
			extras,
			(
				CASE WHEN exclusions IS NULL AND extras IS NULL
					THEN toppings
				WHEN exclusions IS NOT NULL AND extras IS NOT NULL
					THEN CONCAT(REPLACE(REPLACE(toppings, LEFT(exclusions, 1) || ', ', ''), RIGHT(exclusions, 1) || ', ', ''), ', ', extras)
				WHEN exclusions IS NOT NULL AND extras IS NULL
					THEN REPLACE(REPLACE(toppings, LEFT(exclusions, 1) || ', ', ''), RIGHT(exclusions, 1) || ', ', '')
				ELSE CONCAT(toppings, ', ', extras)
				END
			) --Remove or Add toppings as required. Left/Right nesting is for two exclusions
				AS new_toppings
		FROM tmp t
		LEFT JOIN pizza_recipes pr
		ON t.pizza_id = pr.pizza_id
		ORDER BY p_key
	),
	orders AS ( --Multiple nested subquery. This is where it gets interesting
		SELECT 
			p_key, 
			STRING_AGG((CASE WHEN topping_count > 1
					THEN CONCAT(topping_count, 'x ', topping_name)
				ELSE topping_name END),
			 ', ') AS ingredients
		FROM (
				SELECT DISTINCT *, COUNT(*) OVER (PARTITION BY p_key, topping_name ORDER BY topping_name) AS topping_count
				FROM (
					SELECT p_key, UNNEST(string_to_array(new_toppings, ','))::integer AS topping
					FROM new_tops nt
				) s1 --Subquery #1 to change the new toppings table to an array and unnest into multiple rows
				LEFT JOIN pizza_toppings pt
				ON pt.topping_id = s1.topping
				ORDER BY p_key, topping_count DESC
			) s2 	--Subquery #2 to use a window function to check the number of each topping that exists within each order.
					--Also, to rank the toppings in each order alphabetically, as required.
		GROUP BY p_key
	) --Main CTE Query to aggregate the previously unnested ingredients into a single row using the rules stated.

--Finally, the Main Query. This was fun, wasn't it? I wonder if there's a more optimal way to write it.
SELECT order_id, (pizza_name || ': ' || ingredients) AS order_ingredients
FROM tmp
LEFT JOIN pizza_names
USING (pizza_id)
LEFT JOIN orders
USING (p_key);

--#6: Total Quantity of Each Ingredient used in all pizzas, from most frequent to least.
--All I do here is modify the query from #5 above, at the window function part.
WITH tmp AS (
	SELECT ROW_NUMBER() OVER(ORDER BY order_id) AS p_key, * --Create Primary key for each row in customer orders
	FROM customer_orders
	ORDER BY order_time
),
	new_tops AS (
		SELECT 
			p_key,
			toppings,
			exclusions,
			extras,
			(
				CASE WHEN exclusions IS NULL AND extras IS NULL
					THEN toppings
				WHEN exclusions IS NOT NULL AND extras IS NOT NULL
					THEN CONCAT(REPLACE(REPLACE(toppings, LEFT(exclusions, 1) || ', ', ''), RIGHT(exclusions, 1) || ', ', ''), ', ', extras)
				WHEN exclusions IS NOT NULL AND extras IS NULL
					THEN REPLACE(REPLACE(toppings, LEFT(exclusions, 1) || ', ', ''), RIGHT(exclusions, 1) || ', ', '')
				ELSE CONCAT(toppings, ', ', extras)
				END
			) --Remove or Add toppings as required. Left/Right nesting is for two exclusions
				AS new_toppings
		FROM tmp t
		LEFT JOIN pizza_recipes pr
		ON t.pizza_id = pr.pizza_id
		ORDER BY p_key
	),
	orders AS ( --Multiple nested subquery. This is where it gets interesting
		SELECT DISTINCT *, COUNT(*) OVER (PARTITION BY p_key, topping_name ORDER BY topping_name) AS topping_count
		FROM (
				SELECT p_key, UNNEST(string_to_array(new_toppings, ','))::integer AS topping
				FROM new_tops nt
			) s1 --Subquery #1 to change the new toppings table to an array and unnest into multiple rows
		LEFT JOIN pizza_toppings pt
		ON pt.topping_id = s1.topping
		ORDER BY p_key, topping_count DESC
		) 	--Subquery #2 to use a window function to check the number of each topping that exists within each order.
			--Also, to rank the toppings in each order alphabetically, as required.
SELECT topping_name AS ingredient, SUM(topping_count) AS total_qty
FROM orders
GROUP BY 1
ORDER BY 2 DESC; --Bacon (14) is the most used ingredient, closely followed by mushrooms (13)


--D: PRICINGS AND RATINGS
--#1: Meatlovers is $12 and Vegetarian is $10. How much has Pizza Runner made?
SELECT 
	COALESCE(c.order_id::varchar, 'TOTAL') AS order_id,
	'$' || SUM(
		CASE WHEN pizza_name = 'Meatlovers'
				THEN 12
			ELSE 10
		END
	) AS price
FROM customer_orders c
LEFT JOIN pizza_names p
USING (pizza_id)
LEFT JOIN runner_orders r
ON c.order_id = r.order_id
WHERE cancellation IS NULL
GROUP BY ROLLUP(c.order_id)
ORDER BY c.order_id; --The aesthetics was done for my fun, I could simply do a sum and return a single column. 
						--But the total money made is $138.
						
--#2: What if there was $1 charge for extra cheese?
WITH pizzas AS (
	SELECT 
		*,
		CASE WHEN pizza_name = 'Meatlovers'
				THEN 12
			ELSE 10
		END AS price
	FROM pizza_names
	)

	SELECT
		SUM(CASE WHEN LEFT(c.extras, 1)::INTEGER = (SELECT topping_id FROM pizza_toppings WHERE topping_name = 'Cheese')
					OR RIGHT(c.extras, 1)::INTEGER = (SELECT topping_id FROM pizza_toppings WHERE topping_name = 'Cheese')
				THEN price + 1
			ELSE price
			END) AS total_revenue
	FROM customer_orders c
	LEFT JOIN pizzas p
	USING(pizza_id)
	LEFT JOIN runner_orders r
	ON c.order_id = r.order_id
	WHERE cancellation IS NULL;

--#3: Design Additional Ratings Table
CREATE TABLE IF NOT EXISTS order_ratings
AS
	SELECT
		order_id,
		runner_id,
		(
			CASE WHEN cancellation IS NULL
				THEN FLOOR(RANDOM()*(5-1+1)+1)::INTEGER --Creating a random list of integers between 1 and 5
				ELSE NULL 
			END
		) AS rating
	FROM runner_orders;
SELECT *
FROM order_ratings
ORDER BY order_id;

--#4: Join all the required info
SELECT
	c.customer_id,
	c.order_id,
	r.runner_id,
	ra.rating,
	c.order_time,
	r.pickup_time,
	ROUND(EXTRACT(EPOCH FROM (pickup_time - order_time))/60.0, 2) AS order_to_pickup_mins,
	r.duration,
	ROUND(r.distance/(r.duration/60.0), 1) AS avg_speed_kmh,
	COUNT(c.order_id) AS num_pizzas
FROM customer_orders c
LEFT JOIN runner_orders r
ON c.order_id = r.order_id
LEFT JOIN order_ratings ra
ON ra.order_id = c.order_id
WHERE CANCELLATION IS NULL
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9;


--#5: Meat Lovers - $12, Vegetarian - $10, No Cost For Extras; Runner Pay = $0.30/km.
	--how much money does Pizza Runner have left over after these deliveries?
SELECT 
	SUM(delivery_revenue) AS gross_rev,
	SUM(delivery_cost) AS delivery_cost,
	(SUM(delivery_revenue) - SUM (delivery_cost)) AS actual_rev
FROM (
	SELECT 
		runner_id,
		SUM(
			CASE WHEN pizza_name = 'Meatlovers'
					THEN 12
				ELSE 10
			END
		) AS delivery_revenue,
		SUM(distance) AS delivery_distance,
		0.3*SUM(distance) AS delivery_cost
	FROM customer_orders c
	LEFT JOIN runner_orders r
	ON c.order_id = r.order_id
	LEFT JOIN pizza_names p
	ON c.pizza_id = p.pizza_id
	WHERE cancellation IS NULL
	GROUP BY 1
) subq; --Pizza Runner had $73.38 after paying its runners.

--E: BONUS QUESTION; Create a new Supreme Pizza with all toppings
INSERT INTO pizza_names
SELECT 
	MAX(pizza_id) + 1, --Adds 1 to the highest Pizza id and assigns it to a new pizza named 'Supreme'
	'Supreme'
FROM pizza_names
SELECT *
FROM pizza_names;

INSERT INTO pizza_recipes
SELECT
	(SELECT pizza_id FROM pizza_names WHERE pizza_name = 'Supreme'),
	STRING_AGG(topping_id::varchar, ', ')
FROM pizza_toppings
SELECT *
FROM pizza_recipes;