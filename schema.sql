
-- SCHEMA: Meesho-style E-commerce (synthetic)
-- Compatible with MySQL 8+

CREATE DATABASE IF NOT EXISTS ecommerce_ba;
USE ecommerce_ba;

DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS shipments;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS vendors;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
  customer_id VARCHAR(10) PRIMARY KEY,
  signup_date DATE,
  state VARCHAR(50),
  city VARCHAR(50),
  gender ENUM('F','M'),
  age INT,
  segment ENUM('Reseller','Direct Buyer'),
  acquisition_channel VARCHAR(30)
);

CREATE TABLE vendors (
  vendor_id VARCHAR(10) PRIMARY KEY,
  state VARCHAR(50),
  avg_rating DECIMAL(3,2)
);

CREATE TABLE products (
  product_id VARCHAR(10) PRIMARY KEY,
  category VARCHAR(50),
  subcategory VARCHAR(50),
  vendor_id VARCHAR(10),
  mrp DECIMAL(10,2),
  cost DECIMAL(10,2),
  FOREIGN KEY (vendor_id) REFERENCES vendors(vendor_id)
);

CREATE TABLE orders (
  order_id VARCHAR(12) PRIMARY KEY,
  customer_id VARCHAR(10),
  order_date DATETIME,
  ship_state VARCHAR(50),
  payment_method VARCHAR(20),
  device VARCHAR(20),
  coupon_applied TINYINT(1),
  order_status ENUM('delivered','cancelled','returned'),
  order_value DECIMAL(12,2),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
  order_item_id BIGINT PRIMARY KEY,
  order_id VARCHAR(12),
  product_id VARCHAR(10),
  vendor_id VARCHAR(10),
  quantity INT,
  unit_price DECIMAL(10,2),
  discount_pct DECIMAL(5,2),
  item_status ENUM('delivered','cancelled','returned'),
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  FOREIGN KEY (product_id) REFERENCES products(product_id),
  FOREIGN KEY (vendor_id) REFERENCES vendors(vendor_id)
);

CREATE TABLE payments (
  order_id VARCHAR(12) PRIMARY KEY,
  payment_date DATETIME,
  amount DECIMAL(12,2),
  method VARCHAR(20),
  success TINYINT(1),
  FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE shipments (
  order_id VARCHAR(12) PRIMARY KEY,
  promised_date DATE,
  shipped_date DATE,
  delivered_date DATE,
  delivery_partner VARCHAR(30),
  late_delivery_flag TINYINT(1),
  FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE reviews (
  order_id VARCHAR(12) PRIMARY KEY,
  review_date DATE,
  rating INT,
  FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE events (
  event_id BIGINT PRIMARY KEY,
  customer_id VARCHAR(10),
  event_time DATETIME,
  session_id VARCHAR(64),
  event_type ENUM('visit','view','add_to_cart','checkout','purchase'),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);
