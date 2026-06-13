DROP VIEW IF EXISTS validation_primary_result;
DROP VIEW IF EXISTS validation_grouped_result;
DROP VIEW IF EXISTS validation_result_enriched;
DROP VIEW IF EXISTS validation_result;

DROP TABLE IF EXISTS workflow_run_log;
DROP TABLE IF EXISTS inbound_orders;
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS item_master;
DROP TABLE IF EXISTS vendor_master;

CREATE TABLE item_master (
    item_code VARCHAR(20) PRIMARY KEY,
    item_name VARCHAR(100),
    item_category VARCHAR(50)
);

CREATE TABLE vendor_master (
    vendor_code VARCHAR(20) PRIMARY KEY,
    vendor_name VARCHAR(100),
    is_active BOOLEAN
);

CREATE TABLE purchase_orders (
    po_no VARCHAR(30),
    item_code VARCHAR(20),
    vendor_code VARCHAR(20),
    order_qty INTEGER,
    order_date DATE,
    PRIMARY KEY (po_no, item_code)
);

CREATE TABLE inbound_orders (
    inbound_id VARCHAR(30) PRIMARY KEY,
    inbound_date DATE,
    po_no VARCHAR(30),
    item_code VARCHAR(20),
    vendor_code VARCHAR(20),
    inbound_qty INTEGER
);

CREATE TABLE workflow_run_log (
    run_id SERIAL PRIMARY KEY,
    workflow_name VARCHAR(100),
    run_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    detail_report_path TEXT,
    summary_report_path TEXT,
    total_error_count INTEGER,
    status VARCHAR(20)
);

COPY item_master(item_code, item_name, item_category)
FROM '/sample_data/item_master.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY vendor_master(vendor_code, vendor_name, is_active)
FROM '/sample_data/vendor_master.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY purchase_orders(po_no, item_code, vendor_code, order_qty, order_date)
FROM '/sample_data/purchase_orders.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

COPY inbound_orders(inbound_id, inbound_date, po_no, item_code, vendor_code, inbound_qty)
FROM '/sample_data/inbound_orders.csv'
WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');

CREATE VIEW validation_result AS

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    NULL::INTEGER AS reference_qty,
    '수량 음수' AS error_type,
    '입고 수량이 0보다 작습니다.' AS error_message
FROM inbound_orders i
WHERE i.inbound_qty < 0

UNION ALL

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    p.order_qty AS reference_qty,
    '발주수량 초과' AS error_type,
    '입고 수량이 발주 수량보다 많습니다.' AS error_message
FROM inbound_orders i
JOIN purchase_orders p
    ON i.po_no = p.po_no
   AND i.item_code = p.item_code
WHERE i.inbound_qty > p.order_qty

UNION ALL

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    NULL::INTEGER AS reference_qty,
    '미등록 품목' AS error_type,
    '품목 마스터에 존재하지 않는 품목 코드입니다.' AS error_message
FROM inbound_orders i
LEFT JOIN item_master m
    ON i.item_code = m.item_code
WHERE m.item_code IS NULL

UNION ALL

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    NULL::INTEGER AS reference_qty,
    '미등록 협력사' AS error_type,
    '협력사 마스터에 존재하지 않는 협력사 코드입니다.' AS error_message
FROM inbound_orders i
LEFT JOIN vendor_master v
    ON i.vendor_code = v.vendor_code
WHERE v.vendor_code IS NULL

UNION ALL

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    NULL::INTEGER AS reference_qty,
    '발주정보 없음' AS error_type,
    '해당 발주번호와 품목 조합이 발주 데이터에 없습니다.' AS error_message
FROM inbound_orders i
LEFT JOIN purchase_orders p
    ON i.po_no = p.po_no
   AND i.item_code = p.item_code
WHERE p.po_no IS NULL

UNION ALL

SELECT
    i.inbound_id,
    i.inbound_date,
    i.po_no,
    i.item_code,
    i.vendor_code,
    i.inbound_qty,
    d.duplicate_count AS reference_qty,
    '중복 입고 의심' AS error_type,
    '동일 입고일, 발주번호, 품목, 협력사, 수량이 모두 같은 입고 데이터가 여러 번 등록되었습니다.' AS error_message
FROM inbound_orders i
JOIN (
    SELECT
        inbound_date,
        po_no,
        item_code,
        vendor_code,
        inbound_qty,
        COUNT(*) AS duplicate_count
    FROM inbound_orders
    GROUP BY
        inbound_date,
        po_no,
        item_code,
        vendor_code,
        inbound_qty
    HAVING COUNT(*) > 1
) d
    ON i.inbound_date = d.inbound_date
   AND i.po_no = d.po_no
   AND i.item_code = d.item_code
   AND i.vendor_code = d.vendor_code
   AND i.inbound_qty = d.inbound_qty;

CREATE VIEW validation_result_enriched AS
SELECT
    *,
    CASE error_type
        WHEN '수량 음수' THEN 1
        WHEN '미등록 품목' THEN 2
        WHEN '미등록 협력사' THEN 3
        WHEN '발주정보 없음' THEN 4
        WHEN '발주수량 초과' THEN 5
        WHEN '중복 입고 의심' THEN 6
        ELSE 99
    END AS error_priority
FROM validation_result;

CREATE VIEW validation_grouped_result AS
SELECT
    inbound_id,
    MIN(inbound_date) AS inbound_date,
    MIN(po_no) AS po_no,
    MIN(item_code) AS item_code,
    MIN(vendor_code) AS vendor_code,
    MIN(inbound_qty) AS inbound_qty,
    COUNT(*) AS error_event_count,
    STRING_AGG(error_type, ', ' ORDER BY error_priority) AS error_types,
    STRING_AGG(error_message, ' / ' ORDER BY error_priority) AS error_messages
FROM validation_result_enriched
GROUP BY inbound_id;

CREATE VIEW validation_primary_result AS
SELECT
    inbound_id,
    inbound_date,
    po_no,
    item_code,
    vendor_code,
    inbound_qty,
    error_type AS primary_error_type,
    error_message AS primary_error_message,
    error_priority
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY inbound_id
            ORDER BY error_priority ASC
        ) AS rn
    FROM validation_result_enriched
) ranked
WHERE rn = 1;