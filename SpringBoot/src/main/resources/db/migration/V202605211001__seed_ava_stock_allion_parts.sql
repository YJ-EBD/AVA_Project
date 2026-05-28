INSERT INTO ava_stock_parts (part_code, part_name, unit, image_url, description, active)
VALUES
    ('CONTROL_BOARD', '컨트롤보드', 'EA', '/ava-stock-assets/items/컨트롤보드.png', 'ALLION 기본 구성 부품', TRUE),
    ('HANDPIECE', '핸드피스', 'EA', '/ava-stock-assets/items/핸드피스.png', 'ALLION 기본 구성 부품', TRUE),
    ('HIC_MODULE', 'HIC모듈', 'EA', '/ava-stock-assets/items/HIC모듈.png', 'ALLION 기본 구성 부품', TRUE),
    ('DISPLAY', '디스플레이', 'EA', '/ava-stock-assets/items/디스플레이.png', 'ALLION 기본 구성 부품', TRUE),
    ('SMPS', 'SMPS', 'EA', '/ava-stock-assets/items/SMPS.png', 'ALLION 기본 구성 부품', TRUE),
    ('EMI_FILTER', 'EMI필터', 'EA', '/ava-stock-assets/items/EMI필터.png', 'ALLION 기본 구성 부품', TRUE),
    ('FLOW_SENSOR', '플로우센서', 'EA', '/ava-stock-assets/items/플로우센서.png', 'ALLION 기본 구성 부품', TRUE),
    ('WATER_PUMP', '워터펌프', 'EA', '/ava-stock-assets/items/워터펌프.png', 'ALLION 기본 구성 부품', TRUE),
    ('RADIATOR', '라디에이터', 'EA', '/ava-stock-assets/items/라디에이터.png', 'ALLION 기본 구성 부품', TRUE),
    ('WATER_TANK', '물통', 'EA', '/ava-stock-assets/items/물통.png', 'ALLION 기본 구성 부품', TRUE)
ON CONFLICT (part_code) DO UPDATE SET
    part_name = EXCLUDED.part_name,
    unit = EXCLUDED.unit,
    image_url = EXCLUDED.image_url,
    description = EXCLUDED.description,
    active = TRUE,
    updated_at = now();

WITH seeded_parts(part_code, qr_value, label) AS (
    VALUES
        ('CONTROL_BOARD', 'AVA-STOCK:PART:CONTROL_BOARD', '컨트롤보드 QR'),
        ('HANDPIECE', 'AVA-STOCK:PART:HANDPIECE', '핸드피스 QR'),
        ('HIC_MODULE', 'AVA-STOCK:PART:HIC_MODULE', 'HIC모듈 QR'),
        ('DISPLAY', 'AVA-STOCK:PART:DISPLAY', '디스플레이 QR'),
        ('SMPS', 'AVA-STOCK:PART:SMPS', 'SMPS QR'),
        ('EMI_FILTER', 'AVA-STOCK:PART:EMI_FILTER', 'EMI필터 QR'),
        ('FLOW_SENSOR', 'AVA-STOCK:PART:FLOW_SENSOR', '플로우센서 QR'),
        ('WATER_PUMP', 'AVA-STOCK:PART:WATER_PUMP', '워터펌프 QR'),
        ('RADIATOR', 'AVA-STOCK:PART:RADIATOR', '라디에이터 QR'),
        ('WATER_TANK', 'AVA-STOCK:PART:WATER_TANK', '물통 QR')
)
INSERT INTO ava_stock_part_qr_codes (part_id, qr_value, label, active)
SELECT p.id, seeded_parts.qr_value, seeded_parts.label, TRUE
FROM seeded_parts
JOIN ava_stock_parts p ON p.part_code = seeded_parts.part_code
ON CONFLICT (qr_value) DO UPDATE SET
    part_id = EXCLUDED.part_id,
    label = EXCLUDED.label,
    active = TRUE;

WITH seeded_parts(part_code) AS (
    VALUES
        ('CONTROL_BOARD'),
        ('HANDPIECE'),
        ('HIC_MODULE'),
        ('DISPLAY'),
        ('SMPS'),
        ('EMI_FILTER'),
        ('FLOW_SENSOR'),
        ('WATER_PUMP'),
        ('RADIATOR'),
        ('WATER_TANK')
)
INSERT INTO ava_stock_part_stock_movements (part_id, movement_type, qty_delta, memo)
SELECT p.id, 'PURCHASE_IN', 100, '초기 부품 등록 100EA'
FROM seeded_parts
JOIN ava_stock_parts p ON p.part_code = seeded_parts.part_code
WHERE NOT EXISTS (
    SELECT 1
    FROM ava_stock_part_stock_movements m
    WHERE m.part_id = p.id
      AND m.movement_type = 'PURCHASE_IN'
      AND m.memo = '초기 부품 등록 100EA'
);

INSERT INTO ava_stock_product_models (model_code, model_name, description, image_url, active)
VALUES ('ALLION', 'ALLION', 'ALLION 기본 반제품/완제품 모델', '/ava-stock-assets/products/ALLION.png', TRUE)
ON CONFLICT (model_code) DO UPDATE SET
    model_name = EXCLUDED.model_name,
    description = EXCLUDED.description,
    image_url = EXCLUDED.image_url,
    active = TRUE,
    updated_at = now();

WITH target_model AS (
    SELECT id FROM ava_stock_product_models WHERE model_code = 'ALLION'
)
INSERT INTO ava_stock_bom_versions (model_id, version_no, version_name, current_version, active)
SELECT id, 1, 'ALLION 기본 BOM v1', TRUE, TRUE
FROM target_model
ON CONFLICT (model_id, version_no) DO UPDATE SET
    version_name = EXCLUDED.version_name,
    current_version = TRUE,
    active = TRUE,
    updated_at = now();

UPDATE ava_stock_bom_versions
SET current_version = FALSE, updated_at = now()
WHERE model_id = (SELECT id FROM ava_stock_product_models WHERE model_code = 'ALLION')
  AND version_no <> 1;

WITH target_bom AS (
    SELECT bv.id AS bom_version_id, bv.model_id
    FROM ava_stock_bom_versions bv
    JOIN ava_stock_product_models pm ON pm.id = bv.model_id
    WHERE pm.model_code = 'ALLION'
      AND bv.version_no = 1
),
seeded_items(part_code, item_label, sort_order) AS (
    VALUES
        ('CONTROL_BOARD', '컨트롤보드', 1),
        ('HANDPIECE', '핸드피스', 2),
        ('HIC_MODULE', 'HIC모듈', 3),
        ('DISPLAY', '디스플레이', 4),
        ('SMPS', 'SMPS', 5),
        ('EMI_FILTER', 'EMI필터', 6),
        ('FLOW_SENSOR', '플로우센서', 7),
        ('WATER_PUMP', '워터펌프', 8),
        ('RADIATOR', '라디에이터', 9),
        ('WATER_TANK', '물통', 10)
)
INSERT INTO ava_stock_bom_items (
    bom_version_id,
    model_id,
    part_id,
    item_label,
    default_qty,
    sort_order,
    required_flag,
    active
)
SELECT
    target_bom.bom_version_id,
    target_bom.model_id,
    p.id,
    seeded_items.item_label,
    1,
    seeded_items.sort_order,
    TRUE,
    TRUE
FROM seeded_items
JOIN ava_stock_parts p ON p.part_code = seeded_items.part_code
CROSS JOIN target_bom
ON CONFLICT (bom_version_id, part_id) DO UPDATE SET
    item_label = EXCLUDED.item_label,
    default_qty = EXCLUDED.default_qty,
    sort_order = EXCLUDED.sort_order,
    required_flag = TRUE,
    active = TRUE,
    updated_at = now();

WITH new_receipt AS (
    INSERT INTO ava_stock_product_receipts (supplier_name, memo)
    SELECT 'ABBA-S', 'ALLION 초기 반제품 입고'
    WHERE NOT EXISTS (
        SELECT 1 FROM ava_stock_product_units WHERE serial_no = 'ALLION-SEMI-0001'
    )
    RETURNING id
),
target_model AS (
    SELECT id FROM ava_stock_product_models WHERE model_code = 'ALLION'
),
target_bom AS (
    SELECT bv.id
    FROM ava_stock_bom_versions bv
    JOIN ava_stock_product_models pm ON pm.id = bv.model_id
    WHERE pm.model_code = 'ALLION'
      AND bv.version_no = 1
)
INSERT INTO ava_stock_product_units (
    model_id,
    bom_version_id,
    receipt_id,
    serial_no,
    qr_value,
    current_status
)
SELECT
    target_model.id,
    target_bom.id,
    (SELECT id FROM new_receipt),
    'ALLION-SEMI-0001',
    'AVA-STOCK:PRODUCT:ALLION:SEMI-0001',
    'SEMI_RECEIVED'
FROM target_model
CROSS JOIN target_bom
WHERE NOT EXISTS (
    SELECT 1 FROM ava_stock_product_units WHERE serial_no = 'ALLION-SEMI-0001'
);

INSERT INTO ava_stock_product_status_history (
    product_unit_id,
    from_status,
    to_status,
    reason,
    ref_type
)
SELECT
    pu.id,
    NULL,
    'SEMI_RECEIVED',
    'RECEIPT',
    'RECEIPT'
FROM ava_stock_product_units pu
WHERE pu.serial_no = 'ALLION-SEMI-0001'
  AND NOT EXISTS (
      SELECT 1
      FROM ava_stock_product_status_history h
      WHERE h.product_unit_id = pu.id
        AND h.reason = 'RECEIPT'
        AND h.to_status = 'SEMI_RECEIVED'
  );
