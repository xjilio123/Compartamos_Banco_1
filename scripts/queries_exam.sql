-- ============================================================================
-- FASE 2: TRANSFORMACIÓN Y MODELADO STAR SCHEMA (Capa STAGE)
-- Base de Datos: SQL Server (T-SQL) - AJUSTADO 100% A TU INSTANCIA REAL
-- ============================================================================

-- ============================================================================
-- 1. LIMPIEZA DE CLIENTES (Creación de dim_customers) - REVISADA SIN CITY
-- ============================================================================
IF OBJECT_ID('dbo.dim_customers', 'U') IS NOT NULL 
    DROP TABLE dbo.dim_customers;

WITH ClientesFiltrados AS (
    SELECT 
        CAST(REPLACE(customer_id, '"', '') AS INT) AS customer_id,
        UPPER(TRIM(first_name)) AS first_name,
        UPPER(TRIM(last_name)) AS last_name,
        ROW_NUMBER() OVER (
            PARTITION BY REPLACE(customer_id, '"', '') 
            ORDER BY (SELECT NULL)
        ) AS indice_duplicado
    FROM dbo.raw_customers
    WHERE customer_id IS NOT NULL AND customer_id <> 'NULL' AND TRIM(customer_id) <> ''
)
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    GETDATE() AS fecha_actualizacion_stage
INTO dbo.dim_customers
FROM ClientesFiltrados
WHERE indice_duplicado = 1;


-- ============================================================================
-- 2. LIMPIEZA DE PRODUCTOS (Creación de dim_products)
-- ============================================================================
IF OBJECT_ID('dbo.dim_products', 'U') IS NOT NULL 
    DROP TABLE dbo.dim_products;

WITH ProductosFiltrados AS (
    SELECT 
        CAST(REPLACE(product_id, '"', '') AS INT) AS product_id,
        UPPER(TRIM(product_name)) AS product_name,
        COALESCE(NULLIF(UPPER(TRIM(category)), ''), 'GENERAL') AS category,
        TRY_CAST(REPLACE(price_usd, ',', '.') AS DECIMAL(10,2)) AS price_usd,
        TRY_CAST(stock_quantity AS INT) AS stock_quantity,
        CASE 
            WHEN TRY_CAST(REPLACE(discount_pct, ',', '.') AS DECIMAL(5,2)) > 100.0 THEN 0.0
            ELSE TRY_CAST(REPLACE(discount_pct, ',', '.') AS DECIMAL(5,2))
        END AS discount_pct,
        UPPER(TRIM(supplier)) AS supplier,
        UPPER(TRIM(status)) AS status,
        ROW_NUMBER() OVER (
            PARTITION BY REPLACE(product_id, '"', '') 
            ORDER BY (SELECT NULL)
        ) AS indice_duplicado
    FROM dbo.raw_products
    WHERE product_id IS NOT NULL AND product_id <> 'NULL' AND TRIM(product_id) <> ''
      AND TRY_CAST(REPLACE(price_usd, ',', '.') AS DECIMAL(10,2)) >= 0
      AND TRY_CAST(stock_quantity AS INT) >= 0
)
SELECT 
    product_id, 
    product_name, 
    category, 
    COALESCE(price_usd, 0.00) AS price_usd,
    COALESCE(stock_quantity, 0) AS stock_quantity,
    COALESCE(discount_pct, 0.00) AS discount_pct,
    supplier,
    status,
    GETDATE() AS fecha_actualizacion_stage
INTO dbo.dim_products
FROM ProductosFiltrados
WHERE indice_duplicado = 1;


-- ============================================================================
-- 3. TABLA DE HECHOS: PEDIDOS (Creación de fact_orders)
-- ============================================================================
IF OBJECT_ID('dbo.fact_orders', 'U') IS NOT NULL 
    DROP TABLE dbo.fact_orders;

WITH PedidosProcesados AS (
    SELECT 
        CAST(REPLACE(order_id, '"', '') AS INT) AS order_id,
        CAST(customer_id AS INT) AS customer_id,
        CAST(product_id AS INT) AS product_id,
        CAST(quantity AS INT) AS quantity,
        CAST(
            CASE 
                WHEN order_date LIKE '%/%' THEN CONVERT(DATE, order_date, 103)
                ELSE TRY_CONVERT(DATE, order_date, 120)
            END 
        AS DATE) AS order_date,
        TRY_CAST(REPLACE(unit_price, ',', '.') AS DECIMAL(10,2)) AS unit_price,
        TRY_CAST(REPLACE(discount_applied, ',', '.') AS DECIMAL(5,2)) AS discount_applied,
        TRY_CAST(REPLACE(total_amount_usd, ',', '.') AS DECIMAL(10,2)) AS total_amount_usd,
        UPPER(TRIM(order_status)) AS order_status,
        UPPER(TRIM(payment_method)) AS payment_method,
        UPPER(TRIM(shipping_country)) AS shipping_country,
        UPPER(TRIM(store_flavor)) AS store_flavor,
        ROW_NUMBER() OVER (
            PARTITION BY REPLACE(order_id, '"', '') 
            ORDER BY (SELECT NULL)
        ) AS indice_duplicado
    FROM dbo.raw_orders
    WHERE order_id IS NOT NULL AND order_id <> 'NULL'
      AND CAST(quantity AS INT) > 0
)
SELECT 
    order_id,
    customer_id,
    product_id,
    order_date,
    quantity,
    COALESCE(unit_price, 0.00) AS unit_price,
    COALESCE(discount_applied, 0.00) AS discount_applied,
    COALESCE(total_amount_usd, 0.00) AS total_amount_usd,
    order_status,
    payment_method,
    shipping_country,
    store_flavor,
    GETDATE() AS fecha_carga_dw
INTO dbo.fact_orders
FROM PedidosProcesados
WHERE indice_duplicado = 1;