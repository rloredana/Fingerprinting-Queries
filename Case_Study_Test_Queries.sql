-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question 1: What’s the country with the highest share of orders/transactions?
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- APPROACH
-- Counts orders per country and computes their share (%) of total orders.
-- Includes all orders (refunded or not) and returns the top country.

SELECT order_site_country AS country,
       COUNT(order_id) AS orders,
       ROUND(COUNT(order_id) * 100 / SUM(COUNT(order_id)) OVER (), 2) AS share_percent
FROM refurbed.orders_refunds
GROUP BY order_site_country
ORDER BY orders DESC
LIMIT 1;

-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question 2: Please estimate both average Conversion Rate (CR) and average daily Revenue per channel_id.
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- APPROACH
-- Combine GA4 traffic sessions with orders to calculate:
-- - Conversion Rate: session-level, gross, all transactions included
-- - Avg daily Revenue: uses net revenue, excluding refunds

WITH conversions AS (
  SELECT 
    channel_id,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN transaction_id IS NOT NULL THEN session_id END) AS conversions
  FROM refurbed.ga4_traffic
  GROUP BY channel_id
),

daily_revenue AS (
  SELECT 
    g.channel_id AS channel_id,
    DATE(o.order_date) AS order_day,
    SUM(o.revenue_eur) AS revenue_per_day
  FROM refurbed.ga4_traffic g
  JOIN refurbed.orders_refunds o ON g.transaction_id = o.order_id
  WHERE o.refund_date IS NULL
  GROUP BY g.channel_id, order_day
),

avg_daily_revenue AS (
  SELECT 
    channel_id,
    ROUND(AVG(revenue_per_day), 2) AS avg_daily_revenue
  FROM daily_revenue
  GROUP BY channel_id
)

SELECT 
  c.channel_id AS channel_id,
  ROUND(100 * c.conversions / c.total_sessions, 2) AS conversion_rate,
  ROUND(IFNULL(a.avg_daily_revenue, 0), 2) AS avg_daily_revenue,
FROM conversions c
LEFT JOIN avg_daily_revenue a ON c.channel_id = a.channel_id
ORDER BY channel_id ASC;

-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question 3: refurbed customers are offered the option of returning the product free of charge within first 30 days since the purchase. 
--             In those cases, the full amount is refunded to the customer, and refurbed earns no revenue. What can you say about average refund rates?
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- APPROACH
-- Compute refund rates both by number of orders and by revenue.
-- Analyse both overall and per country.

-- Overall refund stats
SELECT
  COUNT(order_id) AS total_orders,
  COUNTIF(refund_date IS NOT NULL) AS refunded_orders,
  ROUND(100 * COUNTIF(refund_date IS NOT NULL) / COUNT(order_id), 2) AS refund_rate_per_orders,
  ROUND(SUM(revenue_eur), 2) AS total_revenue,
  ROUND(SUM(refunded_revenue_eur), 2) AS total_refunded_revenue,
  ROUND(100 * SUM(refunded_revenue_eur) / SUM(revenue_eur), 2) AS refund_rate_per_revenue
FROM refurbed.orders_refunds;

-- Refund stats per country
SELECT
  order_site_country AS country,
  COUNT(order_id) AS total_orders,
  COUNTIF(refund_date IS NOT NULL) AS refunded_orders,
  ROUND(100 * COUNTIF(refund_date IS NOT NULL) / COUNT(order_id), 2) AS refund_rate_per_orders,
  ROUND(SUM(revenue_eur), 2) AS total_revenue,
  ROUND(SUM(refunded_revenue_eur), 2) AS total_refunded_revenue,
  ROUND(100 * SUM(refunded_revenue_eur) / SUM(revenue_eur), 2) AS refund_rate_per_revenue,
  ROUND(SUM(refunded_revenue_eur) / NULLIF(COUNTIF(refund_date IS NOT NULL),0), 2) AS avg_revenue_per_refunded_order
FROM refurbed.orders_refunds
GROUP BY order_site_country;

-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question 4: What can you say about the efficiency of different marketing channels? See Costs per channel information in channels.csv.
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- APPROACH
-- Combine GA4 traffic sessions with orders to calculate:
-- - Conversion rate (session-level)
-- - Average daily revenue and total revenue per channel
-- Estimate avg monthly revenue by multiplying avg daily revenue by 30
-- Calculate ROAS = avg monthly revenue / channel cost
-- Classify channels by:
-- - Performance segment (organic, active paid, unprofitable, inactive)
-- - Efficiency based on ROAS thresholds
-- Refunds are excluded from revenue calculations (net revenue)

WITH conversions AS (
  SELECT 
    channel_id,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(DISTINCT CASE WHEN transaction_id IS NOT NULL THEN session_id END) AS conversions
  FROM refurbed.ga4_traffic
  GROUP BY channel_id
),

daily_revenue AS (
  SELECT 
    g.channel_id AS channel_id,
    DATE(o.order_date) AS order_day,
    SUM(o.revenue_eur) AS revenue_per_day
  FROM refurbed.ga4_traffic g
  JOIN refurbed.orders_refunds o ON g.transaction_id = o.order_id
  WHERE o.refund_date IS NULL
  GROUP BY g.channel_id, order_day
),

avg_daily_revenue AS (
  SELECT 
    channel_id,
    ROUND(AVG(revenue_per_day), 2) AS avg_daily_revenue,
    ROUND(SUM(revenue_per_day), 2) AS total_revenue
  FROM daily_revenue
  GROUP BY channel_id
)

SELECT 
  c.channel_id AS channel_id,
  ROUND(100 * c.conversions / c.total_sessions, 2) AS conversion_rate_percent,
  ROUND(IFNULL(a.avg_daily_revenue, 0), 2) AS avg_daily_revenue,
  ROUND(IFNULL(a.avg_daily_revenue, 0) * 30, 2) AS avg_monthly_revenue,
  IFNULL(a.total_revenue, 0) AS total_revenue,
  IFNULL(ch.av_monthly_spend, 0) AS channel_cost,
  ROUND(100 * IFNULL(a.total_revenue, 0) / SUM(IFNULL(a.total_revenue, 0)) OVER (), 2) AS share_of_total_revenue_td,
  ROUND(100 * (IFNULL(a.avg_daily_revenue, 0) * 30) / SUM(IFNULL(a.avg_daily_revenue, 0) * 30) OVER (), 2) AS share_of_total_monthly_revenue,
  IFNULL(ROUND(IFNULL(a.avg_daily_revenue, 0) * 30 / NULLIF(ch.av_monthly_spend, 0), 2), 0) AS ROAS,
  CASE
    WHEN ch.av_monthly_spend = 0 AND IFNULL(a.avg_daily_revenue, 0) > 0 THEN 'Organic / unpaid success'
    WHEN ch.av_monthly_spend > 0 AND IFNULL(a.avg_daily_revenue, 0) = 0 THEN 'Unprofitable / wasted spend'
    WHEN ch.av_monthly_spend > 0 AND IFNULL(a.avg_daily_revenue, 0) > 0 THEN 'Active paid channel'
    ELSE 'Inactive channel'
  END AS performance_segment,
  CASE
    WHEN ch.av_monthly_spend = 0 THEN 'Undefined / No Spend'
    WHEN ROUND((a.avg_daily_revenue * 30) / NULLIF(ch.av_monthly_spend, 0), 2) >= 100 THEN 'Highly Efficient'
    WHEN ROUND((a.avg_daily_revenue * 30) / NULLIF(ch.av_monthly_spend, 0), 2) >= 20 THEN 'Efficient'
    WHEN ROUND((a.avg_daily_revenue * 30) / NULLIF(ch.av_monthly_spend, 0), 2) >= 1 THEN 'Moderate'
    ELSE 'Inefficient'
  END AS efficiency_classification
FROM conversions c
LEFT JOIN avg_daily_revenue a 
  ON c.channel_id = a.channel_id
LEFT JOIN refurbed.channels ch
  ON c.channel_id = ch.channel_id
ORDER BY channel_id ASC;


-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question 5: Did you observe any interesting patterns in the dataset? Anything unusual or irregular? Any data you wish we’d provide to answer the questions / better understand the trends?
-- ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Overall, the dataset provides enough information to analyze conversion rates, revenue, refunds, and channel efficiency, though the insights remain mostly at an aggregate level. A few clear patterns emerge: Germany accounts for about 62% of total orders, showing strong geographic concentration of demand, while Italy and Sweden contribute smaller but meaningful shares. Some channels, like Channel 1, achieve high conversion rates but relatively low revenue, whereas Channel 7 generates very high revenue despite a lower conversion rate — suggesting that revenue is more influenced by order value than by conversion volume. Refunds occur in roughly 11% of orders and 9% of total revenue, with Sweden showing the highest refund rate, but the average value of refunded orders is quite consistent (around 100–115 EUR).
															
-- There are also some irregularities in the data. The user_pseudo_id values are inconsistent, and the number of unique user IDs exceeds the number of sessions, which is unusual and complicates user-level analysis. In addition, a few channels show marketing spend without generating any conversions or revenue, which could indicate inactive campaigns, misattributed spend, or reporting gaps.																
-- To deepen the analysis, it would be helpful to have more granular information — such as user demographics (e.g., new vs. returning users), product-level details (categories and prices) would allow deeper insights into revenue drivers and refunded order characteristics, and more precise campaign spend attribution. These additions would make it easier to explain performance differences and uncover underlying trends driving conversions and refunds.																





