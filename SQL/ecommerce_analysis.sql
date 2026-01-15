-- E-Commerce SQL Project
-- Database: ecommerce_data


IF DB_ID('ecommerce_data') IS NULL
CREATE DATABASE ecommerce_data;
GO

USE ecommerce_data;
GO


-- 1) DATA QA / VALIDATION

-- 1A) Row counts validation (Data check)
SELECT 'customers' AS table_name, COUNT(*) AS rows_cnt FROM customers
UNION ALL SELECT 'products',    COUNT(*) FROM products
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'payments',    COUNT(*) FROM payments;

-- 1B) Primary key duplicate checks

-- customers
SELECT customer_id, COUNT(*) AS duplicates
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- orders
SELECT order_id, COUNT(*) AS duplicates
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- order_items
SELECT order_item_id, COUNT(*) AS duplicates
FROM order_items
GROUP BY order_item_id
HAVING COUNT(*) > 1;

-- payments
SELECT payment_id, COUNT(*) AS duplicates
FROM payments
GROUP BY payment_id
HAVING COUNT(*) > 1;

-- products
SELECT product_id, COUNT(*) AS duplicates
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- 1C) NULL checks (data quality)

-- orders
SELECT
  SUM(CASE WHEN order_total IS NULL THEN 1 ELSE 0 END) AS null_order_total,
  SUM(CASE WHEN order_date  IS NULL THEN 1 ELSE 0 END) AS null_order_date
FROM orders;

-- products
SELECT
  SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END) AS null_unit_price
FROM products;

-- 1D) Orphan record checks (referential integrity)

-- Orders without customers
SELECT COUNT(*) AS orphan_orders
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- Order_items without orders
SELECT COUNT(*) AS orphan_order_items
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Order_items without products
SELECT COUNT(*) AS orphan_order_items_products
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Payments without orders
SELECT COUNT(*) AS orphan_payments
FROM payments p
LEFT JOIN orders o ON p.order_id = o.order_id
WHERE o.order_id IS NULL;

-- 2) BUSINESS ANALYSIS / KPIs (Core)
  
-- 2A) Total Revenue
SELECT SUM(order_total) AS total_revenue
FROM orders;

-- 2B) AOV (Average Order Value)
SELECT AVG(order_total * 1.0) AS avg_order_value
FROM orders;

-- 2C) Repeat customers (% of customers with 2+ orders)
SELECT
  SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS repeat_customer_pct
FROM (
  SELECT customer_id, COUNT(*) AS order_count
  FROM orders
  GROUP BY customer_id
) x;

-- 2D) Monthly Revenue Trend (clean month key)
SELECT
  DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS month_start,
  SUM(order_total) AS total_revenue
FROM orders
GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
ORDER BY month_start;

-- 2E) Month-over-Month Growth %
;WITH monthly_revenue AS (
  SELECT
    DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1) AS month_start,
    SUM(order_total) AS revenue
  FROM orders
  GROUP BY DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
)
SELECT
  month_start,
  revenue,
  LAG(revenue) OVER (ORDER BY month_start) AS previous_month_revenue,
  ROUND(
    (revenue - LAG(revenue) OVER (ORDER BY month_start)) * 100.0 /
    NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0),
    2
  ) AS mom_rev_pct
FROM monthly_revenue
ORDER BY month_start;

-- 2F) Revenue by Region
SELECT c.region, SUM(o.order_total) AS revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
where o.order_status = 'completed'
GROUP BY c.region
ORDER BY revenue DESC;

-- 2G) Revenue by Product Category (Completed orders only)
SELECT p.category, SUM(oi.quantity * p.unit_price) AS revenue
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_status = 'completed'
GROUP BY p.category
ORDER BY revenue DESC;

-- 3) BUSINESS ANALYSIS (50k+ INSIGHTS)

-- 3A) Customer Cohorts (Retention)


;WITH first_order AS (
  SELECT
    customer_id,
    MIN(DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)) AS cohort_month
  FROM orders
  GROUP BY customer_id
),
orders_with_cohort AS (
  SELECT
    o.customer_id,
    f.cohort_month,
    DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS order_month
  FROM orders o
  JOIN first_order f ON o.customer_id = f.customer_id
)
SELECT
  cohort_month,
  DATEDIFF(MONTH, cohort_month, order_month) AS months_since_first_order,
  COUNT(DISTINCT customer_id) AS active_customers
FROM orders_with_cohort
GROUP BY cohort_month, DATEDIFF(MONTH, cohort_month, order_month)
ORDER BY cohort_month, months_since_first_order;

-- 3B) Pareto / 80-20 Products

;WITH product_revenue AS (
  SELECT
    p.product_id,
    p.product_name,
    SUM(oi.quantity * p.unit_price) AS revenue
  FROM order_items oi
  JOIN products p ON oi.product_id = p.product_id
  GROUP BY p.product_id, p.product_name
),
ranked_products AS (
  SELECT *,
    SUM(revenue) OVER () AS total_revenue,
    SUM(revenue) OVER (ORDER BY revenue DESC) AS running_revenue
  FROM product_revenue
)
SELECT
  product_id,
  product_name,
  revenue,
  ROUND(running_revenue * 100.0 / total_revenue, 2) AS cumulative_revenue_pct
FROM ranked_products
ORDER BY revenue DESC;

-- 3C) Category Growth Over Time (MoM per category)


;WITH category_monthly AS (
  SELECT
    DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS month_start,
    p.category,
    SUM(oi.quantity * p.unit_price) AS revenue
  FROM order_items oi
  JOIN products p ON oi.product_id = p.product_id
  JOIN orders o ON oi.order_id = o.order_id
  WHERE o.order_status = 'completed'
  GROUP BY DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1), p.category
)
SELECT
  month_start,
  category,
  revenue,
  LAG(revenue) OVER (PARTITION BY category ORDER BY month_start) AS prev_month_revenue,
  ROUND(
    (revenue - LAG(revenue) OVER (PARTITION BY category ORDER BY month_start)) * 100.0 /
    NULLIF(LAG(revenue) OVER (PARTITION BY category ORDER BY month_start), 0),
    2
  ) AS mom_growth_pct
FROM category_monthly
ORDER BY category, month_start;

-- 3D) Payment Delay Analysis
-- Question: How long does it take customers to pay after ordering?

SELECT
  o.order_id,
  o.order_date,
  MIN(p.paid_date) AS first_paid_date,
  DATEDIFF(DAY, o.order_date, MIN(p.paid_date)) AS payment_delay_days
FROM orders o
JOIN payments p ON o.order_id = p.order_id
GROUP BY o.order_id, o.order_date
ORDER BY payment_delay_days DESC;


-- 4A) Top 3 orders per customer

;WITH ranked_orders AS (
  SELECT
    customer_id,
    order_id,
    order_total,
    ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_total DESC) AS rn
  FROM orders
)
SELECT *
FROM ranked_orders
WHERE rn <= 3
ORDER BY customer_id, rn;

-- 4B) Running total by customer

SELECT
  customer_id,
  order_id,
  order_date,
  order_total,
  SUM(order_total) OVER (
    PARTITION BY customer_id
    ORDER BY order_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS running_total
FROM orders
ORDER BY customer_id, order_date;

-- 4C) First and latest order per customer

SELECT DISTINCT
  customer_id,
  MIN(order_date) OVER (PARTITION BY customer_id) AS first_order,
  MAX(order_date) OVER (PARTITION BY customer_id) AS latest_order
FROM orders
ORDER BY customer_id;

-- 4D) Gap between orders (days since last order)

SELECT
  customer_id,
  order_id,
  order_date,
  DATEDIFF(
    DAY,
    LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date),
    order_date
  ) AS days_since_last_order
FROM orders
ORDER BY customer_id, order_date;

-- 5) AUDIT & RISK ANALYSIS

-- 5A) Orders with multiple payment records 

SELECT
  order_id,
  COUNT(*) AS payment_count,
  MIN(paid_date) AS first_payment_date,
  MAX(paid_date) AS last_payment_date
FROM payments
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY payment_count DESC, order_id;

-- 5B) Unpaid orders (orders with no payment record)

SELECT o.order_id, o.order_total
FROM orders o
WHERE NOT EXISTS (
  SELECT 1
  FROM payments p
  WHERE p.order_id = o.order_id
);

-- 5C) Customer revenue tiers

SELECT
  c.customer_id,
  c.customer_name,
  SUM(o.order_total) AS revenue,
  CASE
    WHEN SUM(o.order_total) > 8000 THEN 'platinum'
    WHEN SUM(o.order_total) BETWEEN 5000 AND 8000 THEN 'gold'
    WHEN SUM(o.order_total) BETWEEN 2500 AND 5000 THEN 'silver'
    ELSE 'bronze'
  END AS customer_tier
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY revenue DESC;



