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

-- ============================================================================
-- FASE 3: CAPA ANALYTICS (Tablas Finales y Métricas Agregadas)
-- Base de Datos: SQL Server (T-SQL)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ESTRUCTURA: dim_cliente
-- Documentación:
--   - customer_id (INT, PK): Identificador único del cliente.
--   - first_name (VARCHAR): Nombre del cliente en mayúsculas.
--   - last_name (VARCHAR): Apellido del cliente en mayúsculas.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.dim_cliente', 'U') IS NOT NULL DROP TABLE dbo.dim_cliente;

SELECT 
    customer_id,
    first_name,
    last_name,
    GETDATE() AS fecha_carga_analytics
INTO dbo.dim_cliente
FROM dbo.dim_customers;


-- ----------------------------------------------------------------------------
-- 2. ESTRUCTURA: fact_cliente (Tablón con Métricas de Cliente)
-- Documentación:
--   - customer_id (INT, FK): Identificador único del cliente.
--   - total_pedidos (INT): Cantidad total de órdenes realizadas.
--   - total_unidades_compradas (INT): Suma de productos adquiridos.
--   - total_gastado_usd (DECIMAL): Dinero total invertido (Neto con descuentos).
--   - ticket_medio_usd (DECIMAL): Gasto promedio por orden de compra.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fact_cliente', 'U') IS NOT NULL DROP TABLE dbo.fact_cliente;

SELECT 
    customer_id,
    COUNT(order_id) AS total_pedidos,
    SUM(quantity) AS total_unidades_compradas,
    CAST(SUM(total_amount_usd) AS DECIMAL(10,2)) AS total_gastado_usd,
    CAST(AVG(total_amount_usd) AS DECIMAL(10,2)) AS ticket_medio_usd,
    GETDATE() AS fecha_calculo_metrics
INTO dbo.fact_cliente
FROM dbo.fact_orders
GROUP BY customer_id;


-- ----------------------------------------------------------------------------
-- 3. ESTRUCTURA: dim_producto
-- Documentación:
--   - product_id (INT, PK): Identificador único del producto.
--   - product_name (VARCHAR): Nombre comercial del artículo.
--   - category (VARCHAR): Categoría de negocio asignada.
--   - price_usd (DECIMAL): Precio base oficial en dólares.
--   - supplier (VARCHAR): Nombre del proveedor.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.dim_producto', 'U') IS NOT NULL DROP TABLE dbo.dim_producto;

SELECT 
    product_id,
    product_name,
    category,
    price_usd,
    supplier,
    GETDATE() AS fecha_carga_analytics
INTO dbo.dim_producto
FROM dbo.dim_products;


-- ----------------------------------------------------------------------------
-- 4. ESTRUCTURA: fact_producto (Tablón con Métricas de Producto)
-- Documentación:
--   - product_id (INT, FK): Identificador único del producto.
--   - total_ordenes_solicitado (INT): Veces que el producto entró en un carrito.
--   - unidades_totales_vendidas (INT): Volumen total vendido.
--   - ingresos_brutos_usd (DECIMAL): Recaudación sin aplicar descuentos.
--   - ingresos_netos_totales_usd (DECIMAL): Recaudación real final percibida.
--   - descuento_promedio_aplicado (DECIMAL): Porcentaje medio de rebaja otorgado.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dbo.fact_producto', 'U') IS NOT NULL DROP TABLE dbo.fact_producto;

SELECT 
    product_id,
    COUNT(order_id) AS total_ordenes_solicitado,
    SUM(quantity) AS unidades_totales_vendidas,
    CAST(SUM(quantity * unit_price) AS DECIMAL(10,2)) AS ingresos_brutos_usd,
    CAST(SUM(total_amount_usd) AS DECIMAL(10,2)) AS ingresos_netos_totales_usd,
    CAST(AVG(discount_applied) AS DECIMAL(5,2)) AS descuento_promedio_aplicado,
    GETDATE() AS fecha_calculo_metrics
INTO dbo.fact_producto
FROM dbo.fact_orders
GROUP BY product_id;

-- ============================================================================
-- FASE 5: EXAMEN DE CONSULTAS ANALÍTICAS Y ESTADÍSTICAS
-- Base de Datos: SQL Server (Capa ANALYTICS / STAGE)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- P1. Los 3 clientes con mayor número de pedidos en el último trimestre disponible
-- ----------------------------------------------------------------------------
WITH RangoUltimoTrimestre AS (
    -- Detectamos dinámicamente cuál es la fecha máxima en los datos y restamos 3 meses
    SELECT 
        MAX(order_date) AS fecha_maxima,
        DATEADD(month, -3, MAX(order_date)) AS fecha_inicio_trimestre
    FROM dbo.fact_orders
)
SELECT TOP 3
    o.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS nombre_completo,
    COUNT(o.order_id) AS cantidad_pedidos
FROM dbo.fact_orders o
INNER JOIN dbo.dim_cliente c ON o.customer_id = c.customer_id
CROSS JOIN RangoUltimoTrimestre r
WHERE o.order_date BETWEEN r.fecha_inicio_trimestre AND r.fecha_maxima
GROUP BY o.customer_id, c.first_name, c.last_name
ORDER BY cantidad_pedidos DESC;


-- ----------------------------------------------------------------------------
-- P2. Revenue mensual por categoría de producto (Ordenado de mayor a menor)
-- ----------------------------------------------------------------------------
SELECT 
    YEAR(o.order_date) AS [año],
    MONTH(o.order_date) AS mes,
    p.category AS categoria,
    CAST(SUM(o.total_amount_usd) AS DECIMAL(10,2)) AS revenue_total
FROM dbo.fact_orders o
INNER JOIN dbo.dim_producto p ON o.product_id = p.product_id
GROUP BY YEAR(o.order_date), MONTH(o.order_date), p.category
ORDER BY revenue_total DESC;


-- ----------------------------------------------------------------------------
-- P3. Detección de anomalías: Pedidos que superan 2 desviaciones estándar (Z-Score > 2)
-- ----------------------------------------------------------------------------
WITH EstadisticasGlobales AS (
    -- Calculamos la media y la desviación estándar de la tabla de hechos
    SELECT 
        AVG(total_amount_usd) AS promedio_monto,
        STDEV(total_amount_usd) AS desviacion_monto
    FROM dbo.fact_orders
),
CalculoZScore AS (
    SELECT 
        o.order_id,
        o.customer_id,
        o.total_amount_usd,
        -- Aplicación de la fórmula matemática del Z-Score
        (o.total_amount_usd - eg.promedio_monto) / NULLIF(eg.desviacion_monto, 0) AS z_score
    FROM dbo.fact_orders o
    CROSS JOIN EstadisticasGlobales eg
)
SELECT 
    order_id,
    customer_id,
    CAST(total_amount_usd AS DECIMAL(10,2)) AS total_amount_usd,
    CAST(z_score AS DECIMAL(10,2)) AS z_score
FROM CalculoZScore
WHERE z_score > 2.0 -- Filtro estricto solicitado: Mayor a 2 desviaciones estándar
ORDER BY z_score DESC;