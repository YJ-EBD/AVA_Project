WITH units(serial_no, qr_value) AS (
    VALUES
        ('ALLION-SEMI-0002', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0002'),
        ('ALLION-SEMI-0003', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0003'),
        ('ALLION-SEMI-0004', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0004'),
        ('ALLION-SEMI-0005', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0005'),
        ('ALLION-SEMI-0006', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0006'),
        ('ALLION-SEMI-0007', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0007'),
        ('ALLION-SEMI-0008', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0008'),
        ('ALLION-SEMI-0009', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0009'),
        ('ALLION-SEMI-0010', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0010'),
        ('ALLION-SEMI-0011', 'AVA-STOCK:PRODUCT:ALLION:SEMI-0011')
),
new_receipt AS (
    INSERT INTO ava_stock_product_receipts (supplier_name, received_date, memo, created_at)
    SELECT
        'ABBA-S',
        CURRENT_DATE,
        'ALLION additional semi products 0002-0011',
        now()
    WHERE EXISTS (
        SELECT 1
        FROM units u
        WHERE NOT EXISTS (
            SELECT 1
            FROM ava_stock_product_units pu
            WHERE pu.serial_no = u.serial_no
        )
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
    current_status,
    created_at,
    updated_at
)
SELECT
    target_model.id,
    target_bom.id,
    (SELECT id FROM new_receipt),
    units.serial_no,
    units.qr_value,
    'SEMI_RECEIVED',
    now(),
    now()
FROM units
CROSS JOIN target_model
CROSS JOIN target_bom
WHERE NOT EXISTS (
    SELECT 1
    FROM ava_stock_product_units pu
    WHERE pu.serial_no = units.serial_no
);

WITH units(serial_no) AS (
    VALUES
        ('ALLION-SEMI-0002'),
        ('ALLION-SEMI-0003'),
        ('ALLION-SEMI-0004'),
        ('ALLION-SEMI-0005'),
        ('ALLION-SEMI-0006'),
        ('ALLION-SEMI-0007'),
        ('ALLION-SEMI-0008'),
        ('ALLION-SEMI-0009'),
        ('ALLION-SEMI-0010'),
        ('ALLION-SEMI-0011')
)
INSERT INTO ava_stock_product_status_history (
    product_unit_id,
    from_status,
    to_status,
    reason,
    ref_type,
    changed_at
)
SELECT
    pu.id,
    NULL,
    'SEMI_RECEIVED',
    'RECEIPT',
    'RECEIPT',
    now()
FROM units
JOIN ava_stock_product_units pu ON pu.serial_no = units.serial_no
WHERE NOT EXISTS (
    SELECT 1
    FROM ava_stock_product_status_history h
    WHERE h.product_unit_id = pu.id
      AND h.reason = 'RECEIPT'
      AND h.to_status = 'SEMI_RECEIVED'
);
