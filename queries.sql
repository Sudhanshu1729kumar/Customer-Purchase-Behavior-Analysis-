

USE ecommerce_ba;

-- 1) BASIC KPIs
SELECT 
  (SELECT COUNT(*) FROM customers) AS total_customers,
  (SELECT COUNT(*) FROM orders) AS total_orders,
  ROUND(SUM(order_value),2) AS GMV,
  ROUND(AVG(order_value),2) AS AOV
FROM orders;
/* INSIGHT: At-a-glance health of the business. */

-- 2) RFM SEGMENTATION (CTEs + NTILE + CASE)
WITH rfm AS (
  SELECT 
    o.customer_id,
    DATEDIFF(CURDATE(), DATE(MAX(o.order_date))) AS recency,
    COUNT(*) AS frequency,
    SUM(o.order_value) AS monetary
  FROM orders o
  WHERE o.order_status <> 'cancelled'
  GROUP BY o.customer_id
), scored AS (
  SELECT 
    r.*,
    NTILE(4) OVER (ORDER BY recency DESC) AS r_score,
    NTILE(4) OVER (ORDER BY frequency) AS f_score,
    NTILE(4) OVER (ORDER BY monetary) AS m_score
  FROM rfm r
)
SELECT 
  customer_id, recency, frequency, monetary,
  r_score, f_score, m_score,
  CASE 
    WHEN r_score=1 AND f_score=4 AND m_score=4 THEN 'Champions'
    WHEN r_score<=2 AND f_score>=3 AND m_score>=3 THEN 'Loyal'
    WHEN r_score>=3 AND f_score<=2 THEN 'At Risk'
    WHEN r_score=4 AND f_score=1 AND m_score=1 THEN 'Hibernating'
    ELSE 'Regular'
  END AS segment
FROM scored
ORDER BY m_score DESC, f_score DESC;
/* INSIGHT: Identify top-value vs churn-risk segments. */

-- 3) TOP PRODUCTS PER CATEGORY (Window + Rank)
WITH prod AS (
  SELECT 
    p.category, p.subcategory, oi.product_id,
    SUM(oi.quantity) AS qty_sold,
    SUM(oi.quantity * oi.unit_price) AS revenue
  FROM order_items oi
  JOIN products p ON p.product_id = oi.product_id
  JOIN orders o ON o.order_id = oi.order_id
  WHERE o.order_status <> 'cancelled'
  GROUP BY p.category, p.subcategory, oi.product_id
), ranked AS (
  SELECT *, RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rnk
  FROM prod
)
SELECT * FROM ranked WHERE rnk <= 3 ORDER BY category, rnk;
/* INSIGHT: Best sellers by category. */

-- 4) DISCOUNT EFFECT ON CONVERSION
WITH order_discounts AS (
  SELECT 
    o.order_id, o.order_status, o.order_value,
    ROUND(AVG(oi.discount_pct)*100,0) AS avg_disc_pct
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  GROUP BY o.order_id, o.order_status, o.order_value
), buckets AS (
  SELECT 
    CASE 
      WHEN avg_disc_pct=0 THEN '0%'
      WHEN avg_disc_pct BETWEEN 1 AND 10 THEN '1-10%'
      WHEN avg_disc_pct BETWEEN 11 AND 20 THEN '11-20%'
      WHEN avg_disc_pct BETWEEN 21 AND 35 THEN '21-35%'
      ELSE '35%+'
    END AS disc_bucket,
    order_status, order_value
  FROM order_discounts
)
SELECT disc_bucket,
  COUNT(*) AS orders,
  ROUND(AVG(order_value),2) AS avg_order_value,
  SUM(order_status='delivered')/COUNT(*) AS delivered_rate
FROM buckets
GROUP BY disc_bucket
ORDER BY orders DESC;
/* INSIGHT: Find promo sweet spot balancing AOV and delivered rate. */

-- 5) RETURN RATE BY CATEGORY
SELECT 
  p.category,
  COUNT(*) AS items_sold,
  SUM(item_status='returned') AS items_returned,
  ROUND(SUM(item_status='returned')/COUNT(*),3) AS return_rate
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_status <> 'cancelled'
GROUP BY p.category
ORDER BY return_rate DESC;
/* INSIGHT: Target categories with high returns for QC/content fixes. */

-- 6) COHORT RETENTION (Monthly)
WITH first_order AS (
  SELECT customer_id, DATE_FORMAT(MIN(order_date),'%Y-%m') AS cohort
  FROM orders
  WHERE order_status <> 'cancelled'
  GROUP BY customer_id
),
monthly_orders AS (
  SELECT customer_id, DATE_FORMAT(order_date,'%Y-%m') AS ord_month
  FROM orders
  WHERE order_status <> 'cancelled'
),
cohort_map AS (
  SELECT f.customer_id, f.cohort, m.ord_month
  FROM first_order f
  JOIN monthly_orders m ON f.customer_id=m.customer_id
)
SELECT 
  cohort, ord_month, COUNT(DISTINCT customer_id) AS active_customers
FROM cohort_map
GROUP BY cohort, ord_month
ORDER BY cohort, ord_month;
/* INSIGHT: Retention curve across cohorts. */

-- 7) CUSTOMER CHURN CLASSIFICATION
WITH last_orders AS (
  SELECT customer_id, MAX(order_date) AS last_order, COUNT(*) AS order_count
  FROM orders
  WHERE order_status <> 'cancelled'
  GROUP BY customer_id
)
SELECT customer_id,
  order_count,
  DATEDIFF(CURDATE(), DATE(last_order)) AS days_since_last,
  CASE 
    WHEN order_count=1 AND DATEDIFF(CURDATE(), DATE(last_order))>60 THEN 'One-time'
    WHEN DATEDIFF(CURDATE(), DATE(last_order))>90 THEN 'Churned'
    WHEN DATEDIFF(CURDATE(), DATE(last_order)) BETWEEN 31 AND 90 THEN 'At Risk'
    ELSE 'Active'
  END AS status
FROM last_orders
ORDER BY days_since_last DESC;
/* INSIGHT: Lifecycle buckets for CRM. */

-- 8) VENDOR PERFORMANCE
WITH v AS (
  SELECT 
    oi.vendor_id,
    COUNT(DISTINCT oi.order_id) AS orders_served,
    SUM(oi.quantity*oi.unit_price) AS revenue,
    AVG(o.order_status='returned') AS order_return_rate,
    AVG(s.late_delivery_flag) AS late_rate
  FROM order_items oi
  JOIN orders o ON o.order_id=oi.order_id
  LEFT JOIN shipments s ON s.order_id=o.order_id
  GROUP BY oi.vendor_id
)
SELECT v.*,
  RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
  RANK() OVER (ORDER BY order_return_rate) AS quality_rank,
  RANK() OVER (ORDER BY late_rate) AS ops_rank
FROM v
ORDER BY revenue DESC
LIMIT 20;
/* INSIGHT: See trade-offs across vendors. */

-- 9) DELIVERY PARTNER SLA
SELECT 
  delivery_partner,
  COUNT(*) AS orders,
  ROUND(AVG(DATEDIFF(delivered_date, shipped_date)),2) AS avg_days_ship_to_deliver,
  ROUND(AVG(late_delivery_flag),3) AS late_rate
FROM shipments
GROUP BY delivery_partner
ORDER BY late_rate DESC;
/* INSIGHT: SLA benchmarking. */

-- 10) PRICE ELASTICITY SIGNAL
WITH eff AS (
  SELECT p.category, oi.product_id,
         AVG(oi.unit_price) AS eff_price,
         SUM(oi.quantity) AS qty
  FROM order_items oi
  JOIN products p ON p.product_id = oi.product_id
  JOIN orders o ON o.order_id = oi.order_id
  WHERE o.order_status <> 'cancelled'
  GROUP BY p.category, oi.product_id
)
SELECT category,
  ROUND(CORR(eff_price, qty),3) AS price_qty_corr
FROM eff
GROUP BY category;
/* INSIGHT: Promo sensitivity by category. */

-- 11) FUNNEL (Events)
WITH f AS (
  SELECT
    customer_id,
    MAX(event_type='visit') AS visit,
    MAX(event_type='view') AS view_,
    MAX(event_type='add_to_cart') AS addcart,
    MAX(event_type='checkout') AS checkout,
    MAX(event_type='purchase') AS purchase
  FROM events
  GROUP BY customer_id, session_id
)
SELECT 
  SUM(visit) AS sessions_visit,
  SUM(view_) AS sessions_view,
  SUM(addcart) AS sessions_addcart,
  SUM(checkout) AS sessions_checkout,
  SUM(purchase) AS sessions_purchase,
  ROUND(SUM(purchase)/SUM(visit),3) AS session_purchase_rate
FROM f;
/* INSIGHT: Drop-offs across funnel. */

-- 12) STATE-WISE MARGIN RATE
WITH margin AS (
  SELECT 
    o.ship_state,
    SUM(oi.quantity*(oi.unit_price - p.cost)) AS gross_margin
  FROM order_items oi
  JOIN products p ON p.product_id = oi.product_id
  JOIN orders o ON o.order_id = oi.order_id
  WHERE o.order_status <> 'cancelled'
  GROUP BY o.ship_state
),
 gmv AS (
  SELECT ship_state, SUM(order_value) AS gmv FROM orders WHERE order_status <> 'cancelled' GROUP BY ship_state
)
SELECT g.ship_state, g.gmv, m.gross_margin, ROUND(m.gross_margin/g.gmv,3) AS margin_rate
FROM gmv g
JOIN margin m ON m.ship_state=g.ship_state
ORDER BY margin_rate ASC;
/* INSIGHT: Identify low-margin states to optimize mix/discounts. */

-- 13) LATE DELIVERY IMPACT ON RETURNS
WITH t AS (
  SELECT 
    o.order_id, s.late_delivery_flag,
    AVG(oi.item_status='returned') AS item_returned
  FROM orders o
  JOIN shipments s ON s.order_id=o.order_id
  JOIN order_items oi ON oi.order_id=o.order_id
  WHERE o.order_status <> 'cancelled'
  GROUP BY o.order_id, s.late_delivery_flag
)
SELECT late_delivery_flag,
       ROUND(AVG(item_returned),3) AS avg_item_return_rate,
       COUNT(*) AS orders
FROM t
GROUP BY late_delivery_flag;
/* INSIGHT: SLA → returns relationship. */

-- 14) DEVICE & PAYMENT MIX
SELECT device, payment_method,
  COUNT(*) AS orders,
  ROUND(AVG(order_value),2) AS AOV,
  AVG(order_status='delivered') AS delivered_rate
FROM orders
GROUP BY device, payment_method
ORDER BY orders DESC;
/* INSIGHT: Checkout optimization by mix. */

-- 15) NEW vs REPEAT BY MONTH
WITH ords AS (
  SELECT o.*, 
    MIN(o2.order_date) OVER (PARTITION BY o.customer_id) AS first_order_dt
  FROM orders o
  WHERE o.order_status <> 'cancelled'
)
SELECT DATE_FORMAT(order_date,'%Y-%m') AS ym,
  SUM(order_date = first_order_dt) AS new_orders,
  SUM(order_date > first_order_dt) AS repeat_orders
FROM ords
GROUP BY ym
ORDER BY ym;
/* INSIGHT: Acquisition vs retention engine. */
