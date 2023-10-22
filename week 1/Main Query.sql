-- 1. What is the total amount each customer spent at the restaurant?
SELECT s.customer_id, SUM(m.price) AS total_amt
FROM sales s
LEFT JOIN menu m
USING(product_id)
GROUP BY 1
ORDER BY 2 DESC;

-- 2. How many days has each customer visited the restaurant?
SELECT customer_id, COUNT(DISTINCT order_date) AS num_visits
FROM sales
GROUP BY 1
ORDER BY 2 DESC;

-- 3. What was the first item from the menu purchased by each customer?
SELECT DISTINCT s1.customer_id, m.product_name
FROM(SELECT customer_id, MIN(order_date) date
FROM sales
GROUP BY 1) s1
LEFT JOIN sales s2
ON s1.date = s2.order_date
	AND s1.customer_id = s2.customer_id
LEFT JOIN menu m
ON s2.product_id = m.product_id
ORDER BY 1;

-- 4. What is the most purchased item on the menu and how many times was it purchased by all customers?
SELECT product_id, product_name, COUNT(*) num_purchases
FROM sales s
LEFT JOIN menu m
 USING(product_id)
GROUP BY 1, 2
ORDER BY num_purchases DESC;

-- 5. Which item was the most popular for each customer?
WITH w1 AS (
	SELECT customer_id, product_id, COUNT(product_id) num_purchases
	FROM sales
	GROUP BY 1,2
	ORDER BY 1, 2
	),
	w2 AS (
	SELECT 
		*,
		MAX(num_purchases) OVER(PARTITION BY customer_id) fav_item
	FROM w1
	)

SELECT customer_id, product_name, num_purchases
FROM w2
LEFT JOIN menu m
ON w2.product_id = m.product_id
WHERE num_purchases = fav_item
ORDER BY 1;

-- 6. Which item was purchased first by the customer after they became a member?
WITH w1 AS (
	SELECT s.customer_id, order_date, product_id
	FROM members me
	INNER JOIN sales s
	ON s.customer_id = me.customer_id
	AND s.order_date >= me.join_date
	),
	w2 AS (
	SELECT customer_id, MIN(order_date) first_order
	FROM w1
	GROUP BY 1
	)

SELECT s.customer_id, s.order_date, m.product_name
FROM sales s
RIGHT JOIN w2
ON s.order_date = w2.first_order
	AND s.customer_id = w2.customer_id
LEFT JOIN menu m
ON s.product_id = m.product_id
ORDER BY order_date;

-- 7. Which item was purchased just before the customer became a member?
WITH w1 AS (
	SELECT s.customer_id, order_date, product_id
	FROM members me
	INNER JOIN sales s
	ON s.customer_id = me.customer_id
	AND s.order_date < me.join_date
	),
	w2 AS (
	SELECT customer_id, MAX(order_date) last_order
	FROM w1
	GROUP BY 1
	)

SELECT s.customer_id, s.order_date, m.product_name
FROM sales s
RIGHT JOIN w2
ON s.order_date = w2.last_order
	AND s.customer_id = w2.customer_id
LEFT JOIN menu m
ON s.product_id = m.product_id
ORDER BY order_date;

-- 8. What is the total items and amount spent for each member before they became a member?
SELECT 
	s.customer_id, 
	SUM(price) total_spend
FROM sales s
LEFT JOIN members me
	ON s.customer_id = me.customer_id
LEFT JOIN menu m
	ON s.product_id = m.product_id
WHERE s.order_date < me.join_date
GROUP BY 1;

-- 9.  If each $1 spent equates to 10 points and sushi has a 2x points multiplier - how many points would each customer have?
SELECT 
	customer_id,
	SUM(CASE WHEN product_name = 'sushi' 
			THEN (2*price*10)
		ELSE price*10
		END) AS points
FROM sales s
LEFT JOIN menu m
USING (product_id)
GROUP BY 1
ORDER BY 1;

-- 10. In the first week after a customer joins the program (including their join date) they earn 2x points on all items, not just sushi - how many points do customer A and B have at the end of January?
SELECT customer_id, 
	SUM(CASE WHEN order_date BETWEEN join_date AND join_date + 7
 			OR product_name = 'sushi'
			THEN 2*10*price
		ELSE 10*price
	   	END) AS points		
FROM sales
INNER JOIN members me
USING (customer_id)
LEFT JOIN menu m
USING (product_id)
WHERE date_part('month', order_date) = 1
GROUP BY 1
ORDER BY 1;

--Join All Things
SELECT 
	s.customer_id, 
	s.order_date,
	m1.product_name,
	m1.price,
	CASE WHEN order_date >= join_date THEN 'Y'
		ELSE 'N' END AS member
FROM sales s
LEFT JOIN menu m1
USING (product_id)
LEFT JOIN members m2
USING(customer_id)
ORDER BY 1, 2;

--Rank all things
WITH w1 AS (
	SELECT 
		s.customer_id, 
		s.order_date,
		m1.product_name,
		m1.price,
		CASE WHEN order_date >= join_date THEN 'Y'
			ELSE 'N' END AS member,
		CASE WHEN order_date >= join_date THEN RANK()OVER(PARTITION BY s.customer_id ORDER BY order_date)
				END AS rankings
	FROM sales s
	LEFT JOIN menu m1
	USING (product_id)
	LEFT JOIN members m2
	USING(customer_id)
	ORDER BY 1, 2)
	
SELECT 
	customer_id, 
	order_date,
	product_name,
	price,
	member,
	rankings - (SELECT COUNT(*) FROM w1 WHERE rankings IS NULL AND w.customer_id = w1.customer_id) AS rankings
FROM w1 w;