DROP VIEW IF EXISTS validation_result;
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
    po_no VARCHAR(20),
    item_code VARCHAR(20),
    vendor_code VARCHAR(20),
    order_qty INTEGER,
    order_date DATE,
    PRIMARY KEY (po_no, item_code)
);

CREATE TABLE inbound_orders (
    inbound_id VARCHAR(20) PRIMARY KEY,
    inbound_date DATE,
    po_no VARCHAR(20),
    item_code VARCHAR(20),
    vendor_code VARCHAR(20),
    inbound_qty INTEGER
);

INSERT INTO item_master VALUES
('ITM-001', '알루미늄 하우징', '원자재'),
('ITM-002', 'PCB 보드', '전자부품'),
('ITM-003', '센서 모듈', '전자부품'),
('ITM-004', '포장 박스', '부자재');

INSERT INTO vendor_master VALUES
('V001', '대한부품', true),
('V002', '성진테크', true),
('V003', '미래패키징', true);

INSERT INTO purchase_orders VALUES
('PO-1001', 'ITM-001', 'V001', 100, '2026-06-11'),
('PO-1002', 'ITM-002', 'V001', 50, '2026-06-11'),
('PO-1003', 'ITM-003', 'V002', 200, '2026-06-11'),
('PO-1004', 'ITM-004', 'V003', 30, '2026-06-11'),
('PO-1005', 'ITM-001', 'V001', 120, '2026-06-11'),
('PO-1006', 'ITM-002', 'V001', 80, '2026-06-11');

INSERT INTO inbound_orders VALUES
('INB-001', '2026-06-12', 'PO-1001', 'ITM-001', 'V001', 100),
('INB-002', '2026-06-12', 'PO-1002', 'ITM-002', 'V001', 65),
('INB-003', '2026-06-12', 'PO-1003', 'ITM-999', 'V002', 10),
('INB-004', '2026-06-12', 'PO-1004', 'ITM-004', 'V999', 10),
('INB-005', '2026-06-12', 'PO-1005', 'ITM-001', 'V001', -5),
('INB-006', '2026-06-12', 'PO-1006', 'ITM-002', 'V001', 30),
('INB-007', '2026-06-12', 'PO-1006', 'ITM-002', 'V001', 30),
('INB-008', '2026-06-12', 'PO-9999', 'ITM-003', 'V002', 20),
('INB-009', '2026-06-12', 'PO-1003', 'ITM-003', 'V002', 220),
('INB-010', '2026-06-12', 'PO-1004', 'ITM-004', 'V003', 30);

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
    '동일 발주번호와 품목 조합으로 여러 번 입고되었습니다.' AS error_message
FROM inbound_orders i
JOIN (
    SELECT
        po_no,
        item_code,
        COUNT(*) AS duplicate_count
    FROM inbound_orders
    GROUP BY po_no, item_code
    HAVING COUNT(*) > 1
) d
    ON i.po_no = d.po_no
   AND i.item_code = d.item_code;