SET search_path = foodie_fi;

--SECTION A: ONBOARDING JOURNEY
--Wite a brief description about each customer’s onboarding journey (the 8 sample customers given).
SELECT 
	s.customer_id, 
	p.plan_name,
	s.start_date
FROM subscriptions s
LEFT JOIN plans p
ON p.plan_id = s.plan_id
WHERE customer_id IN (1, 2, 11, 13, 15, 16, 18, 19)
ORDER BY customer_id, start_date;
/*
Customer 1: Joined on 1st August 2020 with a free trial, then downgraded to Basic Monthly after the trial period.
Customer 2: Joined on 20th September 2020, used the free trial, then upgraded to pro annual after the trial.
Customer 11: Joined on 19th November 2020 and cancelled the subscription after the trial period.
Customer 13: Jonied on 15th December 2020, then downgraded to Basic Monthly after the trial period. They continued
				with that plan until March 2021, when they did a Pro Monthly Plan.
Customer 15: Joined the service on 17th March 2020 and continued with the Pro monthly after the trial. 6 days 
				into the second cycle, they cancelled the subscription.
Customer 16: Joined on 31st May 2020, downgraded to a Basic Monthly after the trial period, and upgraded to a Pro
				Annual twoards the end of the 4th month.
Customer 18: Joined on 6th July 2020, continued with Pro Monthly after trial ended.
Customer 19: Joined pm 22nd June 2020, continued with Pro Monthly after trial period and switched to Pro Annual 
				2 months later.
*/




--B: DATA ANALYSIS QUESTIONS

--#1: How many customers has foodie-fi ever had?
SELECT COUNT(DISTINCT customer_id) num_customers
FROM subscriptions; --1000 customers

--#2: Monthly distribtuion of trial plan start date
SELECT DATE_TRUNC('month', start_date)::date AS trial_month, COUNT(*) num_signups
FROM subscriptions s
LEFT JOIN plans p
USING (plan_id)
WHERE plan_name = 'trial'
GROUP BY 1
ORDER BY 1; --Best month was March 2020 with 94 signups

--#3: What plans start dates occur after 2020?
SELECT plan_name, COUNT(*) AS num_starts
FROM subscriptions s
LEFT JOIN plans p
USING (plan_id)
WHERE EXTRACT(YEAR FROM start_date) > 2020
GROUP BY 1
ORDER BY 2 DESC;
--71 customers churned after 2020, 63 upgraded to Pro Annual, 60 did Pro Monthly while 8 downgraded to Basic Monthly

--#4: Number of Churned Customers and Churn Rate
SELECT 
	COUNT(*) num_churns,
	ROUND(COUNT(*)*100.0/(SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1) || '%' AS churn_rate
FROM subscriptions s
LEFT JOIN plans p
USING (plan_id)
WHERE plan_name = 'churn'; --307 churns, 30.7% churn rate

--#5: How many customers churned immediately after their free trial?
SELECT COUNT(*)
FROM subscriptions s
LEFT JOIN plans p
	USING (plan_id)
WHERE plan_name = 'trial'; --Every customer started with a free trial therefore;

SELECT
	COUNT(*) AS num_quick_churners,
	ROUND(COUNT(*)*100.0/(SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1)||'%' perc_quick_churners
FROM (
	SELECT customer_id, STRING_AGG(plan_name, ', ') AS plans
	FROM subscriptions s
	LEFT JOIN plans p
		USING (plan_id)
	GROUP BY customer_id
	ORDER BY customer_id
) AS subq
WHERE plans = 'trial, churn'; --92 customers (9.2%) churned immediately after their quick trial


--#6: Number of Customer Plans After Free Trial
SELECT 
	COUNT(*) AS num_non_trial,
	ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM subscriptions), 1) AS perc_non_trial
FROM subscriptions s
LEFT JOIN plans p
	USING (plan_id)
WHERE plan_name <> 'trial';

--#7: Customer count and percentage breakdown of all 5 plan_name values at 2020-12-31?
/*Interpretation: If records were checked on the last day of 2020...
...how many customers would each plan have, and what is the percentage distribution?*/
WITH cte AS (
		SELECT 
		*,
		MAX(start_date) OVER(PARTITION BY customer_id) AS last_change
		FROM subscriptions s
		LEFT JOIN plans p
		USING (plan_id)
	),
	cte2 AS (
		SELECT *
		FROM cte
		WHERE start_date = last_change
			AND start_date <= '2020-12-31'
	)
SELECT 
	plan_name,
	COUNT(DISTINCT customer_id) AS num_subscribers,
	ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM cte2), 1) perc_totoal
FROM cte2
GROUP BY plan_name
ORDER BY num_subscribers DESC; --By the end of 2020, Pro Monthly had the 267 subscribers; the most of any plan (32.9%)

--#8: How many customers upgraded to an annual plan in 2020
SELECT COUNT(DISTINCT customer_id) AS num_upgrades
FROM subscriptions s
LEFT JOIN plans p
USING (plan_id)
WHERE EXTRACT(YEAR FROM start_date) = 2020
	AND plan_name LIKE '%annual%';

--#9: Average Number of Days to Annual Plan
WITH joins AS (
		SELECT customer_id, MIN(start_date) AS join_date
		FROM subscriptions s
		LEFT JOIN plans p
		USING (plan_id)
		GROUP BY customer_id
	),
	annuals AS (
		SELECT customer_id, start_date AS upgrade_date
		FROM subscriptions s
		LEFT JOIN plans p
		USING (plan_id)
		WHERE plan_name LIKE '%annual%'
	),
	tta AS (
		SELECT customer_id, upgrade_date-join_date AS diff
		FROM joins
		INNER JOIN annuals
		USING (customer_id)
	)
SELECT ROUND(AVG(diff)) AS avg_tt_annual
FROM tta; --105 days, on average, to switch to annual plan

--#10: Break the averages into 30-day periods
WITH joins AS (
		SELECT customer_id, MIN(start_date) AS join_date
		FROM subscriptions s
		LEFT JOIN plans p
		USING (plan_id)
		GROUP BY customer_id
	),
	annuals AS (
		SELECT customer_id, start_date AS upgrade_date
		FROM subscriptions s
		LEFT JOIN plans p
		USING (plan_id)
		WHERE plan_name LIKE '%annual%'
	),
	tta AS (
		SELECT 
			customer_id, 
			upgrade_date-join_date AS diff
		FROM joins
		INNER JOIN annuals
		USING (customer_id)
	)
SELECT
	(CASE WHEN diff < 30 THEN '30 days and Below'
		WHEN diff BETWEEN 31 AND 60 THEN '31 - 60 days'
		WHEN diff BETWEEN 61 AND 90 THEN '61 - 90 days'
		WHEN diff BETWEEN 91 AND 120 THEN '91 - 120 days'
		ELSE 'Above 120 days'
	END) AS day_bins,
	ROUND(AVG(diff)) AS avg_tt_annual
FROM tta
GROUP BY day_bins;


--#11: How many customers downgraded from a Pro Monthly to Basic Monthly Plan in 2020?
WITH pros AS (
	SELECT customer_id, start_date
	FROM subscriptions s
	LEFT JOIN plans p
	USING (plan_id)
	WHERE plan_name = 'pro monthly'
		AND  EXTRACT(YEAR FROM start_date) = 2020
	),
	basics AS (
	SELECT customer_id, start_date
	FROM subscriptions s
	LEFT JOIN plans p
	USING (plan_id)
	WHERE plan_name = 'basic monthly'
		AND  EXTRACT(YEAR FROM start_date) = 2020
	)
SELECT COUNT(*) AS num_downgrades
FROM pros p
INNER JOIN basics b
USING (customer_id)
WHERE p.start_date < b.start_date; --Nobody who used pro monthly plan downgraded to basic monthly


--C: Challenge Payment Question
--Start by bringing the Start Date For The Next Plan and filtering 2020 and trial/churn since they have no payments
--COALESCE NULLS FOR new_plan with the last day of the year.
CREATE TABLE payments AS

WITH RECURSIVE cte AS (
		SELECT *	
		FROM (SELECT
				s.customer_id,
				s.plan_id,
				p.plan_name,
				p.price,
				s.start_date,
				COALESCE(
					LEAD(s.start_date, 1) OVER(PARTITION BY s.customer_id ORDER BY s.start_date),
					'2020-12-31'::DATE
				) AS new_plan
			FROM subscriptions s
			LEFT JOIN plans p
			USING (plan_id)
			WHERE EXTRACT(YEAR FROM s.start_date) = 2020
			ORDER BY s.customer_id, s.start_date) csubq
		WHERE plan_name NOT IN ('trial', 'churn')
	),
	cte2 AS ( --utilise recurssive ctes to check create a row for each month where the plan stayed running
		SELECT
			customer_id,
			plan_id,
			plan_name,
			start_date,
			price,
			new_plan
		FROM cte

		UNION

		SELECT
			customer_id,
			plan_id,
			plan_name,
			(
				CASE WHEN start_date + '1 month'::INTERVAL < new_plan AND plan_name LIKE '%monthly%'
					THEN start_date + '1 month'::INTERVAL
				ELSE start_date
				END
			)::DATE AS payment_date,
			price,
			new_plan
		FROM cte2
	),
	cte3 AS ( --now, reduce upgrades by amount already paid
		SELECT 
			customer_id, 
			plan_id,
			plan_name,
			start_date AS payment_date,
			(
				CASE WHEN plan_id IN (2, 3)
						AND LAG(plan_id, 1) OVER(win) = 1
					THEN price - LAG(price, 1) OVER (win)
				ELSE price 
				END
			) AS amount,
			RANK() OVER(win) AS payment_order
		FROM cte2
		WINDOW win AS (PARTITION BY customer_id ORDER BY start_date)
		ORDER BY customer_id, payment_date
	)
SELECT * 
FROM cte3
-- WHERE customer_id IN (1, 2, 13, 15, 16, 18, 19) --Uncomment the WHERE clause to check with sample from task.
;


--SECTION D: TECHNICAL QUESTIONS
/*
1. How would you calculate the rate of growth for Foodie-Fi?
I would analyse Quarter-on-Quarter growth for revenue and number of customers. I would also analyse QoQ churn rate and plan upgrades vs downgrades.

2. What key metrics would you recommend Foodie-Fi management to track over time to assess performance of their overall business?
The same metrics I mentioned in #1.

3. What are some key customer journeys or experiences that you would analyse further to improve customer retention?
I would some sort of hypothesis testing to see what behaviours (plan subscriptons, probably usage too, if data is available) are common to churners.

4. If the Foodie-Fi team were to create an exit survey shown to customers who wish to cancel their subscription, what questions would you include in the survey
-Why do you want to leave our service?
-What was your favourite foodie-fi feature?
-What was your least favourite foodie-fi feature?
-On a scale of 1-10, how likely are you to recommend foodie-fi to a friend?

5. What business levers could the Foodie-Fi team use to reduce the customer churn rate? How would you validate the effectiveness of your ideas?
-Advertising
-Offering loyalty bonuses (like a free month of service after 18 straight monthly plans or 2 annual plans)
-User generated content or user-requested content
*/

--NAMASTE!
