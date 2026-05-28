-- AVA_stock / multi-product QR production, inventory, shipment, and A/S database
-- Target DB: PostgreSQL 14+
-- Final verified design notes:
-- v2 patch: progress views count missing checklist rows as PENDING, so QR progress is correct before all rows are materialized.
-- 1) Product QR stays with one physical product_unit from semi-product receipt to manufacturing, shipment, and A/S.
-- 2) Each product model has its own BOM/checklist through bom_versions + bom_items.
-- 3) A product_unit is locked to a BOM version at receipt time, so old products are not affected by later BOM changes.
-- 4) Manufacturing and A/S both use product_operations + operation_check_items.
-- 5) Part inventory source of truth is part_stock_movements. Current stock is calculated by v_part_inventory.
-- 6) For save/edit operations, the app/service layer must post only inventory deltas to part_stock_movements.

BEGIN;

-- =========================================================
-- 0. Users
-- =========================================================
CREATE TABLE users (
    user_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_name      VARCHAR(100) NOT NULL,
    role_code      VARCHAR(30),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 1. Product models and BOM versions
-- =========================================================
CREATE TABLE product_models (
    model_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_code      VARCHAR(60) NOT NULL UNIQUE,     -- e.g. ALLION, ALLION_PRO, PRODUCT_B
    model_name      VARCHAR(150) NOT NULL,
    description     TEXT,
    image_url       TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE bom_versions (
    bom_version_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_id        BIGINT NOT NULL REFERENCES product_models(model_id),
    version_no      INTEGER NOT NULL,
    version_name    VARCHAR(100),
    is_current      BOOLEAN NOT NULL DEFAULT FALSE,
    effective_from  DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to    DATE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_bom_model_version UNIQUE (model_id, version_no),
    CONSTRAINT uq_bom_version_model UNIQUE (bom_version_id, model_id),
    CONSTRAINT chk_bom_effective_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

CREATE UNIQUE INDEX uq_one_current_bom_per_model
ON bom_versions(model_id)
WHERE is_current = TRUE AND is_active = TRUE;

-- =========================================================
-- 2. Parts and product-specific checklist/BOM items
-- =========================================================
CREATE TABLE parts (
    part_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    part_code      VARCHAR(100) NOT NULL UNIQUE,     -- e.g. ALLION-A, PRO-A
    part_name      VARCHAR(150) NOT NULL,            -- e.g. 부품A, 컨트롤보드
    unit           VARCHAR(20) NOT NULL DEFAULT 'EA',
    image_url      TEXT,
    description    TEXT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- BOM item = one checklist row for a specific product model/version.
-- Different product models can have different parts and different quantities.
CREATE TABLE bom_items (
    bom_item_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bom_version_id  BIGINT NOT NULL,
    model_id        BIGINT NOT NULL,
    part_id         BIGINT NOT NULL REFERENCES parts(part_id),
    item_label      VARCHAR(150),                    -- optional UI override name
    default_qty     INTEGER NOT NULL DEFAULT 1 CHECK (default_qty > 0),
    sort_order      INTEGER NOT NULL DEFAULT 1,
    is_required     BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_bom_item_version_model
        FOREIGN KEY (bom_version_id, model_id) REFERENCES bom_versions(bom_version_id, model_id),
    CONSTRAINT uq_bom_item_part UNIQUE (bom_version_id, part_id),
    CONSTRAINT uq_bom_item_order UNIQUE (bom_version_id, sort_order),
    CONSTRAINT uq_bom_item_version UNIQUE (bom_item_id, bom_version_id),
    CONSTRAINT uq_bom_item_part_match UNIQUE (bom_item_id, part_id)
);

-- QR codes attached to part boxes. One part can have multiple box QR labels.
CREATE TABLE part_qr_codes (
    part_qr_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    part_id       BIGINT NOT NULL REFERENCES parts(part_id),
    qr_value      VARCHAR(255) NOT NULL UNIQUE,
    label         VARCHAR(150),
    location_code VARCHAR(80),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 3. Semi-product receipt and physical product units
-- =========================================================
CREATE TABLE product_receipts (
    receipt_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    supplier_name   VARCHAR(150),
    received_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    memo            TEXT,
    created_by      BIGINT REFERENCES users(user_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE product_units (
    product_unit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    model_id        BIGINT NOT NULL REFERENCES product_models(model_id),
    bom_version_id  BIGINT NOT NULL,
    receipt_id      BIGINT REFERENCES product_receipts(receipt_id),
    serial_no       VARCHAR(120) NOT NULL UNIQUE,    -- product unique number / IMEI
    qr_value        VARCHAR(255) NOT NULL UNIQUE,    -- QR payload attached to the physical product
    current_status  VARCHAR(30) NOT NULL DEFAULT 'SEMI_RECEIVED'
        CHECK (current_status IN (
            'SEMI_RECEIVED',      -- semi-product received
            'MFG_SAVED',          -- manufacturing checklist saved, not completed
            'FINISHED_READY',     -- manufacturing completed, ready to ship
            'SHIPPING',           -- outbound shipping in progress
            'SHIPPED',            -- delivered / shipped out
            'AS_IN_PROGRESS',     -- inspection / repair / A/S in progress
            'AS_READY',           -- A/S completed, ready to return or ship
            'HOLD',
            'SCRAPPED'
        )),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_product_unit_bom_model
        FOREIGN KEY (bom_version_id, model_id) REFERENCES bom_versions(bom_version_id, model_id),
    CONSTRAINT uq_product_unit_bom UNIQUE (product_unit_id, bom_version_id),
    CONSTRAINT uq_product_unit_model UNIQUE (product_unit_id, model_id)
);

CREATE INDEX idx_product_units_model_status ON product_units(model_id, current_status);
CREATE INDEX idx_product_units_qr ON product_units(qr_value);

CREATE TABLE product_status_history (
    status_history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_unit_id   BIGINT NOT NULL REFERENCES product_units(product_unit_id),
    from_status       VARCHAR(30),
    to_status         VARCHAR(30) NOT NULL,
    reason            VARCHAR(150),
    ref_type          VARCHAR(40),      -- RECEIPT, OPERATION, SHIPMENT, SERVICE_CASE, MANUAL
    ref_id            BIGINT,
    changed_by        BIGINT REFERENCES users(user_id),
    changed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 4. A/S case header
-- =========================================================
CREATE TABLE service_cases (
    service_case_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_unit_id BIGINT NOT NULL REFERENCES product_units(product_unit_id),
    service_no      VARCHAR(120) NOT NULL UNIQUE,
    service_status  VARCHAR(30) NOT NULL DEFAULT 'OPEN'
        CHECK (service_status IN ('OPEN', 'SAVED', 'COMPLETED', 'CANCELLED')),
    issue_summary   TEXT,
    received_date   DATE NOT NULL DEFAULT CURRENT_DATE,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    saved_at        TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_by      BIGINT REFERENCES users(user_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_service_case_product UNIQUE (service_case_id, product_unit_id)
);

CREATE INDEX idx_service_cases_product ON service_cases(product_unit_id, service_status);

CREATE UNIQUE INDEX uq_one_open_service_case_per_product
ON service_cases(product_unit_id)
WHERE service_status IN ('OPEN', 'SAVED');

-- =========================================================
-- 5. Manufacturing / A/S operations and checklist state
-- =========================================================
CREATE TABLE product_operations (
    operation_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_unit_id    BIGINT NOT NULL,
    bom_version_id     BIGINT NOT NULL,
    service_case_id    BIGINT,
    operation_type     VARCHAR(30) NOT NULL CHECK (operation_type IN ('MANUFACTURING', 'AS')),
    operation_status   VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
        CHECK (operation_status IN ('DRAFT', 'SAVED', 'COMPLETED', 'CANCELLED')),
    started_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    saved_at           TIMESTAMPTZ,
    completed_at       TIMESTAMPTZ,
    created_by         BIGINT REFERENCES users(user_id),
    completed_by       BIGINT REFERENCES users(user_id),
    notes              TEXT,
    CONSTRAINT uq_operation_bom UNIQUE (operation_id, bom_version_id),
    CONSTRAINT fk_operation_product_bom
        FOREIGN KEY (product_unit_id, bom_version_id) REFERENCES product_units(product_unit_id, bom_version_id),
    CONSTRAINT fk_operation_service_case_product
        FOREIGN KEY (service_case_id, product_unit_id) REFERENCES service_cases(service_case_id, product_unit_id),
    CONSTRAINT chk_operation_service_case
        CHECK (
            (operation_type = 'AS' AND service_case_id IS NOT NULL)
            OR
            (operation_type = 'MANUFACTURING' AND service_case_id IS NULL)
        )
);

CREATE INDEX idx_product_operations_product ON product_operations(product_unit_id, operation_type, operation_status);
CREATE INDEX idx_product_operations_service_case ON product_operations(service_case_id);

CREATE UNIQUE INDEX uq_one_manufacturing_operation_per_product
ON product_operations(product_unit_id)
WHERE operation_type = 'MANUFACTURING' AND operation_status <> 'CANCELLED';

CREATE UNIQUE INDEX uq_one_as_operation_per_service_case
ON product_operations(service_case_id)
WHERE operation_type = 'AS' AND service_case_id IS NOT NULL AND operation_status <> 'CANCELLED';

-- Store every checklist row. This lets you distinguish unchecked/in-progress from explicitly unused.
CREATE TABLE operation_check_items (
    check_item_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation_id    BIGINT NOT NULL,
    bom_version_id  BIGINT NOT NULL,
    bom_item_id     BIGINT NOT NULL,
    part_id         BIGINT NOT NULL,
    check_status    VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (check_status IN ('PENDING', 'USED', 'NOT_USED')),
    qty_used        INTEGER NOT NULL DEFAULT 0 CHECK (qty_used >= 0),
    checked_at      TIMESTAMPTZ,
    checked_by      BIGINT REFERENCES users(user_id),
    memo            TEXT,
    CONSTRAINT uq_operation_bom_item UNIQUE (operation_id, bom_item_id),
    CONSTRAINT fk_check_item_operation_bom
        FOREIGN KEY (operation_id, bom_version_id) REFERENCES product_operations(operation_id, bom_version_id) ON DELETE CASCADE,
    CONSTRAINT fk_check_item_bom_item
        FOREIGN KEY (bom_item_id, bom_version_id) REFERENCES bom_items(bom_item_id, bom_version_id),
    CONSTRAINT fk_check_item_bom_part
        FOREIGN KEY (bom_item_id, part_id) REFERENCES bom_items(bom_item_id, part_id),
    CONSTRAINT chk_check_item_qty
        CHECK (
            (check_status = 'USED' AND qty_used > 0)
            OR
            (check_status IN ('PENDING', 'NOT_USED') AND qty_used = 0)
        )
);

CREATE INDEX idx_operation_check_items_operation ON operation_check_items(operation_id, check_status);
CREATE INDEX idx_operation_check_items_part ON operation_check_items(part_id);

-- =========================================================
-- 6. Part inventory ledger
-- =========================================================
CREATE TABLE part_stock_movements (
    movement_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    part_id         BIGINT NOT NULL REFERENCES parts(part_id),
    part_qr_id      BIGINT REFERENCES part_qr_codes(part_qr_id),
    product_unit_id BIGINT REFERENCES product_units(product_unit_id),
    service_case_id BIGINT REFERENCES service_cases(service_case_id),
    operation_id    BIGINT REFERENCES product_operations(operation_id),
    check_item_id   BIGINT REFERENCES operation_check_items(check_item_id),
    movement_type   VARCHAR(30) NOT NULL CHECK (movement_type IN (
        'PURCHASE_IN',      -- part QR: 추가매입
        'MANUAL_USE',       -- part QR: 수동 사용
        'PRODUCTION_USE',   -- manufacturing use
        'AS_USE',           -- replacement/repair use in A/S
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'REVERSAL'
    )),
    qty_delta       INTEGER NOT NULL,
    memo            TEXT,
    created_by      BIGINT REFERENCES users(user_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_stock_delta_sign CHECK (
        (movement_type IN ('PURCHASE_IN', 'ADJUSTMENT_IN') AND qty_delta > 0)
        OR
        (movement_type IN ('MANUAL_USE', 'PRODUCTION_USE', 'AS_USE', 'ADJUSTMENT_OUT') AND qty_delta < 0)
        OR
        (movement_type = 'REVERSAL' AND qty_delta <> 0)
    ),
    CONSTRAINT chk_stock_operation_refs CHECK (
        (movement_type IN ('PRODUCTION_USE', 'AS_USE') AND operation_id IS NOT NULL AND check_item_id IS NOT NULL AND product_unit_id IS NOT NULL)
        OR
        (movement_type NOT IN ('PRODUCTION_USE', 'AS_USE'))
    )
);

CREATE INDEX idx_part_stock_movements_part ON part_stock_movements(part_id, created_at);
CREATE INDEX idx_part_stock_movements_product ON part_stock_movements(product_unit_id, created_at);
CREATE INDEX idx_part_stock_movements_operation ON part_stock_movements(operation_id);
CREATE INDEX idx_part_stock_movements_check_item ON part_stock_movements(check_item_id);
CREATE INDEX idx_part_stock_movements_type ON part_stock_movements(movement_type, created_at);

-- Optional cache table. The ledger view v_part_inventory remains the source of truth.
CREATE TABLE part_inventory_cache (
    part_id       BIGINT PRIMARY KEY REFERENCES parts(part_id),
    current_qty   INTEGER NOT NULL DEFAULT 0,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================
-- 7. Finished products and shipments
-- =========================================================
CREATE TABLE finished_products (
    finished_id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_unit_id               BIGINT NOT NULL UNIQUE REFERENCES product_units(product_unit_id),
    manufacturing_operation_id    BIGINT NOT NULL UNIQUE REFERENCES product_operations(operation_id),
    finished_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_by                   BIGINT REFERENCES users(user_id)
);

CREATE TABLE destinations (
    destination_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    destination_name  VARCHAR(150) NOT NULL,
    country           VARCHAR(80),
    city              VARCHAR(80),
    address           TEXT,
    contact_name      VARCHAR(100),
    contact_phone     VARCHAR(50),
    is_active         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_destination_name UNIQUE (destination_name)
);

CREATE TABLE shipments (
    shipment_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    destination_id   BIGINT NOT NULL REFERENCES destinations(destination_id),
    shipment_type    VARCHAR(30) NOT NULL DEFAULT 'OUTBOUND'
        CHECK (shipment_type IN ('OUTBOUND', 'AS_RETURN', 'RESHIP_AFTER_AS')),
    shipping_method  VARCHAR(200) NOT NULL,       -- e.g. 홍콩행 인천 항공선적
    shipping_date    DATE NOT NULL,
    shipment_status  VARCHAR(30) NOT NULL DEFAULT 'IN_TRANSIT'
        CHECK (shipment_status IN ('READY', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED')),
    tracking_no      VARCHAR(120),
    memo             TEXT,
    created_by       BIGINT REFERENCES users(user_id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shipments_date_status ON shipments(shipping_date, shipment_status);
CREATE INDEX idx_shipments_destination ON shipments(destination_id);

CREATE TABLE shipment_items (
    shipment_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    shipment_id      BIGINT NOT NULL REFERENCES shipments(shipment_id) ON DELETE CASCADE,
    product_unit_id  BIGINT NOT NULL REFERENCES product_units(product_unit_id),
    item_status      VARCHAR(30) NOT NULL DEFAULT 'INCLUDED'
        CHECK (item_status IN ('INCLUDED', 'CANCELLED')),
    memo             TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_shipment_product UNIQUE (shipment_id, product_unit_id)
);

CREATE INDEX idx_shipment_items_product ON shipment_items(product_unit_id);

-- =========================================================
-- 8. Views for app, admin dashboard, and Notion-style page
-- =========================================================

-- QR router: scan once and decide whether it is a product QR or part QR.
CREATE OR REPLACE VIEW v_qr_lookup AS
SELECT
    'PRODUCT'::TEXT AS qr_type,
    pu.qr_value,
    pu.product_unit_id,
    NULL::BIGINT AS part_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    pu.current_status,
    NULL::TEXT AS part_code,
    NULL::TEXT AS part_name
FROM product_units pu
JOIN product_models pm ON pm.model_id = pu.model_id
UNION ALL
SELECT
    'PART'::TEXT AS qr_type,
    pq.qr_value,
    NULL::BIGINT AS product_unit_id,
    p.part_id,
    NULL::TEXT AS model_code,
    NULL::TEXT AS model_name,
    NULL::TEXT AS serial_no,
    NULL::TEXT AS current_status,
    p.part_code,
    p.part_name
FROM part_qr_codes pq
JOIN parts p ON p.part_id = pq.part_id
WHERE pq.is_active = TRUE;

-- Current part inventory by ledger sum.
CREATE OR REPLACE VIEW v_part_inventory AS
SELECT
    p.part_id,
    p.part_code,
    p.part_name,
    p.unit,
    COALESCE(SUM(psm.qty_delta), 0)::INTEGER AS current_qty
FROM parts p
LEFT JOIN part_stock_movements psm ON psm.part_id = p.part_id
GROUP BY p.part_id, p.part_code, p.part_name, p.unit;

-- Operation progress for manufacturing or A/S.
CREATE OR REPLACE VIEW v_operation_progress AS
SELECT
    po.operation_id,
    po.operation_type,
    po.operation_status,
    pu.product_unit_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    pu.qr_value,
    pu.current_status,
    COUNT(bi.bom_item_id)::INTEGER AS total_check_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'USED')::INTEGER AS used_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'NOT_USED')::INTEGER AS not_used_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'PENDING')::INTEGER AS pending_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') IN ('USED', 'NOT_USED'))::INTEGER AS decided_items,
    ROUND((COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'USED')::NUMERIC / NULLIF(COUNT(bi.bom_item_id), 0)) * 100, 1) AS used_part_pct,
    ROUND((COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') IN ('USED', 'NOT_USED'))::NUMERIC / NULLIF(COUNT(bi.bom_item_id), 0)) * 100, 1) AS decision_progress_pct
FROM product_operations po
JOIN product_units pu ON pu.product_unit_id = po.product_unit_id
JOIN product_models pm ON pm.model_id = pu.model_id
JOIN bom_items bi ON bi.bom_version_id = po.bom_version_id AND bi.is_active = TRUE
LEFT JOIN operation_check_items oci ON oci.operation_id = po.operation_id AND oci.bom_item_id = bi.bom_item_id
GROUP BY po.operation_id, po.operation_type, po.operation_status, pu.product_unit_id, pm.model_code, pm.model_name, pu.serial_no, pu.qr_value, pu.current_status;

-- Semi-product QR screen: current manufacturing progress, even if operation has not started.
CREATE OR REPLACE VIEW v_product_manufacturing_progress AS
SELECT
    pu.product_unit_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    pu.qr_value,
    pu.current_status,
    po.operation_id,
    COALESCE(po.operation_status, 'NOT_STARTED') AS operation_status,
    COUNT(bi.bom_item_id)::INTEGER AS total_check_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'USED')::INTEGER AS used_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'NOT_USED')::INTEGER AS not_used_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'PENDING')::INTEGER AS pending_items,
    COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') IN ('USED', 'NOT_USED'))::INTEGER AS decided_items,
    ROUND((COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') = 'USED')::NUMERIC / NULLIF(COUNT(bi.bom_item_id), 0)) * 100, 1) AS used_part_pct,
    ROUND((COUNT(*) FILTER (WHERE COALESCE(oci.check_status, 'PENDING') IN ('USED', 'NOT_USED'))::NUMERIC / NULLIF(COUNT(bi.bom_item_id), 0)) * 100, 1) AS decision_progress_pct
FROM product_units pu
JOIN product_models pm ON pm.model_id = pu.model_id
JOIN bom_items bi ON bi.bom_version_id = pu.bom_version_id AND bi.is_active = TRUE
LEFT JOIN product_operations po
    ON po.product_unit_id = pu.product_unit_id
   AND po.operation_type = 'MANUFACTURING'
   AND po.operation_status <> 'CANCELLED'
LEFT JOIN operation_check_items oci
    ON oci.operation_id = po.operation_id
   AND oci.bom_item_id = bi.bom_item_id
GROUP BY pu.product_unit_id, pm.model_code, pm.model_name, pu.serial_no, pu.qr_value, pu.current_status, po.operation_id, po.operation_status;

-- Current checklist rows for product operation screens.
CREATE OR REPLACE VIEW v_operation_checklist AS
SELECT
    po.operation_id,
    po.operation_type,
    po.operation_status,
    pu.product_unit_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    bi.bom_item_id,
    bi.sort_order,
    bi.is_required,
    COALESCE(bi.item_label, p.part_name) AS display_part_name,
    p.part_id,
    p.part_code,
    p.part_name,
    bi.default_qty,
    COALESCE(oci.check_status, 'PENDING') AS check_status,
    COALESCE(oci.qty_used, 0) AS qty_used,
    oci.checked_at,
    oci.memo
FROM product_operations po
JOIN product_units pu ON pu.product_unit_id = po.product_unit_id
JOIN product_models pm ON pm.model_id = pu.model_id
JOIN bom_items bi ON bi.bom_version_id = po.bom_version_id AND bi.is_active = TRUE
JOIN parts p ON p.part_id = bi.part_id
LEFT JOIN operation_check_items oci ON oci.operation_id = po.operation_id AND oci.bom_item_id = bi.bom_item_id;

-- Total parts used by product, split into manufacturing and A/S.
CREATE OR REPLACE VIEW v_product_used_parts_summary AS
SELECT
    pu.product_unit_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    p.part_id,
    p.part_code,
    p.part_name,
    SUM(CASE WHEN po.operation_type = 'MANUFACTURING' THEN oci.qty_used ELSE 0 END)::INTEGER AS manufacturing_qty,
    SUM(CASE WHEN po.operation_type = 'AS' THEN oci.qty_used ELSE 0 END)::INTEGER AS as_qty,
    SUM(oci.qty_used)::INTEGER AS total_qty
FROM product_units pu
JOIN product_models pm ON pm.model_id = pu.model_id
JOIN product_operations po ON po.product_unit_id = pu.product_unit_id AND po.operation_status IN ('SAVED', 'COMPLETED')
JOIN operation_check_items oci ON oci.operation_id = po.operation_id AND oci.check_status = 'USED'
JOIN parts p ON p.part_id = oci.part_id
GROUP BY pu.product_unit_id, pm.model_code, pm.model_name, pu.serial_no, p.part_id, p.part_code, p.part_name;

-- Product inventory dashboard by model.
CREATE OR REPLACE VIEW v_product_inventory_dashboard AS
SELECT
    pm.model_id,
    pm.model_code,
    pm.model_name,
    COUNT(pu.product_unit_id)::INTEGER AS total_registered_products,
    COUNT(*) FILTER (WHERE pu.current_status IN ('SEMI_RECEIVED', 'MFG_SAVED'))::INTEGER AS semi_stock_qty,
    COUNT(*) FILTER (WHERE pu.current_status IN ('AS_IN_PROGRESS'))::INTEGER AS as_in_progress_qty,
    COUNT(*) FILTER (WHERE pu.current_status IN ('SEMI_RECEIVED', 'MFG_SAVED', 'AS_IN_PROGRESS'))::INTEGER AS semi_or_as_stock_qty,
    COUNT(*) FILTER (WHERE pu.current_status IN ('FINISHED_READY', 'AS_READY'))::INTEGER AS shippable_qty,
    COUNT(*) FILTER (WHERE pu.current_status = 'SHIPPING')::INTEGER AS shipping_qty,
    COUNT(*) FILTER (WHERE pu.current_status = 'AS_IN_PROGRESS')::INTEGER AS inspection_repair_qty,
    COUNT(*) FILTER (WHERE pu.current_status = 'SHIPPED')::INTEGER AS shipped_qty,
    COUNT(*) FILTER (WHERE pu.current_status IN ('SEMI_RECEIVED', 'MFG_SAVED', 'FINISHED_READY', 'AS_IN_PROGRESS', 'AS_READY', 'HOLD'))::INTEGER AS in_house_total_qty,
    COUNT(*) FILTER (WHERE pu.current_status IN ('HOLD', 'SCRAPPED'))::INTEGER AS hold_or_scrapped_qty
FROM product_models pm
LEFT JOIN product_units pu ON pu.model_id = pm.model_id
GROUP BY pm.model_id, pm.model_code, pm.model_name;

-- Shipment history: which product, when, how, and where.
CREATE OR REPLACE VIEW v_shipment_history AS
SELECT
    s.shipment_id,
    s.shipment_type,
    s.shipping_date,
    s.shipment_status,
    d.destination_name,
    d.country,
    d.city,
    s.shipping_method,
    s.tracking_no,
    pm.model_code,
    pm.model_name,
    pu.product_unit_id,
    pu.serial_no,
    pu.qr_value,
    si.item_status
FROM shipments s
JOIN destinations d ON d.destination_id = s.destination_id
JOIN shipment_items si ON si.shipment_id = s.shipment_id AND si.item_status <> 'CANCELLED'
JOIN product_units pu ON pu.product_unit_id = si.product_unit_id
JOIN product_models pm ON pm.model_id = pu.model_id;

-- Product detail for complete/A/S screens.
CREATE OR REPLACE VIEW v_product_current_detail AS
SELECT
    pu.product_unit_id,
    pm.model_code,
    pm.model_name,
    pu.serial_no,
    pu.qr_value,
    pu.current_status,
    fp.finished_at,
    latest_ship.destination_name AS latest_destination_name,
    latest_ship.shipping_method AS latest_shipping_method,
    latest_ship.shipping_date AS latest_shipping_date,
    latest_ship.shipment_status AS latest_shipment_status
FROM product_units pu
JOIN product_models pm ON pm.model_id = pu.model_id
LEFT JOIN finished_products fp ON fp.product_unit_id = pu.product_unit_id
LEFT JOIN LATERAL (
    SELECT d.destination_name, s.shipping_method, s.shipping_date, s.shipment_status
    FROM shipment_items si
    JOIN shipments s ON s.shipment_id = si.shipment_id
    JOIN destinations d ON d.destination_id = s.destination_id
    WHERE si.product_unit_id = pu.product_unit_id
      AND si.item_status <> 'CANCELLED'
      AND s.shipment_status <> 'CANCELLED'
    ORDER BY s.shipping_date DESC, s.shipment_id DESC
    LIMIT 1
) latest_ship ON TRUE;

-- Part usage trace: which part was used, how many, by which product/operation, and latest shipment destination if any.
CREATE OR REPLACE VIEW v_part_usage_trace AS
SELECT
    psm.movement_id,
    psm.created_at,
    psm.movement_type,
    psm.qty_delta,
    ABS(psm.qty_delta)::INTEGER AS used_qty,
    p.part_id,
    p.part_code,
    p.part_name,
    po.operation_type,
    po.operation_id,
    sc.service_no,
    pm.model_code,
    pm.model_name,
    pu.product_unit_id,
    pu.serial_no,
    latest_ship.destination_name AS latest_destination_name,
    latest_ship.shipping_method AS latest_shipping_method,
    latest_ship.shipping_date AS latest_shipping_date,
    psm.memo
FROM part_stock_movements psm
JOIN parts p ON p.part_id = psm.part_id
LEFT JOIN product_operations po ON po.operation_id = psm.operation_id
LEFT JOIN service_cases sc ON sc.service_case_id = psm.service_case_id
LEFT JOIN product_units pu ON pu.product_unit_id = psm.product_unit_id
LEFT JOIN product_models pm ON pm.model_id = pu.model_id
LEFT JOIN LATERAL (
    SELECT d.destination_name, s.shipping_method, s.shipping_date
    FROM shipment_items si
    JOIN shipments s ON s.shipment_id = si.shipment_id
    JOIN destinations d ON d.destination_id = s.destination_id
    WHERE si.product_unit_id = pu.product_unit_id
      AND si.item_status <> 'CANCELLED'
      AND s.shipment_status <> 'CANCELLED'
    ORDER BY s.shipping_date DESC, s.shipment_id DESC
    LIMIT 1
) latest_ship ON TRUE
WHERE psm.movement_type IN ('MANUAL_USE', 'PRODUCTION_USE', 'AS_USE', 'ADJUSTMENT_OUT');

-- Part usage joined with all shipments of the product, for full traceability.
CREATE OR REPLACE VIEW v_part_usage_with_shipment_history AS
SELECT
    put.movement_id,
    put.created_at AS part_used_at,
    put.movement_type,
    put.used_qty,
    put.part_id,
    put.part_code,
    put.part_name,
    put.operation_type,
    put.service_no,
    put.model_code,
    put.model_name,
    put.product_unit_id,
    put.serial_no,
    sh.shipment_id,
    sh.shipment_type,
    sh.shipping_date,
    sh.shipment_status,
    sh.destination_name,
    sh.shipping_method,
    sh.tracking_no
FROM v_part_usage_trace put
LEFT JOIN v_shipment_history sh ON sh.product_unit_id = put.product_unit_id;

COMMIT;

-- =========================================================
-- Seed example
-- =========================================================
-- INSERT INTO product_models(model_code, model_name) VALUES ('ALLION', 'ALLION'), ('PRODUCT_B', '제품B');
-- INSERT INTO bom_versions(model_id, version_no, version_name, is_current)
-- SELECT model_id, 1, 'v1', TRUE FROM product_models WHERE model_code IN ('ALLION', 'PRODUCT_B');
-- INSERT INTO parts(part_code, part_name) VALUES
--   ('ALLION-A', '부품A'), ('ALLION-B', '부품B'), ('ALLION-C', '부품C'), ('ALLION-D', '부품D'), ('ALLION-E', '부품E'),
--   ('ALLION-F', '부품F'), ('ALLION-G', '부품G'), ('ALLION-H', '부품H'), ('ALLION-I', '부품I'), ('ALLION-J', '부품J');
-- Then insert 10 rows into bom_items for ALLION v1.
