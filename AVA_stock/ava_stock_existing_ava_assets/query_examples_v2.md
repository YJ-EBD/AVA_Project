# ALLION final verified DB - query examples

## 1. QR 스캔 라우팅
```sql
SELECT *
FROM v_qr_lookup
WHERE qr_value = :qr_value;
```

## 2. 반제품 QR 스캔 시 진행률
```sql
SELECT *
FROM v_product_manufacturing_progress
WHERE qr_value = :product_qr_value;
```

## 3. 특정 제조/A/S 작업의 체크리스트
```sql
SELECT *
FROM v_operation_checklist
WHERE operation_id = :operation_id
ORDER BY sort_order;
```

## 4. 완제품 또는 A/S 완료 제품 QR 스캔 시 총 사용 부품
```sql
SELECT *
FROM v_product_used_parts_summary
WHERE serial_no = :serial_no
ORDER BY part_code;
```

## 5. 제품 상세: 최신 출고처/출고방법/출고일
```sql
SELECT *
FROM v_product_current_detail
WHERE qr_value = :product_qr_value;
```

## 6. 부품을 어디서 몇 개 썼는지, 그 제품의 최신 납품처
```sql
SELECT *
FROM v_part_usage_trace
WHERE part_code = :part_code
ORDER BY created_at DESC;
```

## 7. 부품 사용 이력 + 해당 제품의 전체 출고 이력
```sql
SELECT *
FROM v_part_usage_with_shipment_history
WHERE part_code = :part_code
ORDER BY part_used_at DESC, shipping_date DESC;
```

## 8. 제품별 재고 대시보드
```sql
SELECT *
FROM v_product_inventory_dashboard
ORDER BY model_code;
```

## 9. 어떤 제품이 언제, 어디로, 어떤 방식으로 출고됐는지
```sql
SELECT *
FROM v_shipment_history
ORDER BY shipping_date DESC, shipment_id DESC;
```

## 10. 부품 현재 재고
```sql
SELECT *
FROM v_part_inventory
ORDER BY part_code;
```

## 11. 반제품 저장/수정 시 재고 차감 규칙 요약
앱 서비스 로직은 체크박스 저장 시 다음처럼 처리해야 합니다.

1. operation_check_items의 목표 상태와 목표 qty_used를 저장한다.
2. 해당 check_item_id에 대해 이미 반영된 재고 수량을 계산한다.
3. 목표 차감 수량과 이미 반영된 수량의 차이만 part_stock_movements에 추가한다.
4. 체크 해제/수량 감소 시에는 REVERSAL 또는 양수 delta로 되돌림 기록을 남긴다.

예:
```sql
-- 이미 반영된 수량. PRODUCTION_USE/AS_USE는 음수, REVERSAL은 양수/음수 가능.
SELECT COALESCE(SUM(qty_delta), 0) AS posted_delta
FROM part_stock_movements
WHERE check_item_id = :check_item_id;
```

목표 상태가 USED, qty_used = 2라면 목표 delta는 -2입니다. 이미 posted_delta가 -1이면 추가로 -1만 입력합니다.
