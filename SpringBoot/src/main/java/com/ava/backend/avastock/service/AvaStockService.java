package com.ava.backend.avastock.service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.avastock.dto.AvaStockBomItemUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockBomVersionUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockChecklistSaveRequest;
import com.ava.backend.avastock.dto.AvaStockPartAdjustRequest;
import com.ava.backend.avastock.dto.AvaStockPartPurchaseRequest;
import com.ava.backend.avastock.dto.AvaStockPartQrCodeCreateRequest;
import com.ava.backend.avastock.dto.AvaStockPartUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockProductModelUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockProductReceiptRequest;
import com.ava.backend.avastock.dto.AvaStockServiceStartRequest;
import com.ava.backend.avastock.dto.AvaStockShipmentCreateRequest;
import com.ava.backend.avastock.entity.BomItemEntity;
import com.ava.backend.avastock.entity.BomVersionEntity;
import com.ava.backend.avastock.entity.DestinationEntity;
import com.ava.backend.avastock.entity.FinishedProductEntity;
import com.ava.backend.avastock.entity.OperationCheckItemEntity;
import com.ava.backend.avastock.entity.PartEntity;
import com.ava.backend.avastock.entity.PartQrCodeEntity;
import com.ava.backend.avastock.entity.PartStockMovementEntity;
import com.ava.backend.avastock.entity.ProductModelEntity;
import com.ava.backend.avastock.entity.ProductOperationEntity;
import com.ava.backend.avastock.entity.ProductReceiptEntity;
import com.ava.backend.avastock.entity.ProductStatusHistoryEntity;
import com.ava.backend.avastock.entity.ProductUnitEntity;
import com.ava.backend.avastock.entity.ServiceCaseEntity;
import com.ava.backend.avastock.entity.ShipmentEntity;
import com.ava.backend.avastock.entity.ShipmentItemEntity;
import com.ava.backend.avastock.repository.BomItemRepository;
import com.ava.backend.avastock.repository.BomVersionRepository;
import com.ava.backend.avastock.repository.DestinationRepository;
import com.ava.backend.avastock.repository.FinishedProductRepository;
import com.ava.backend.avastock.repository.OperationCheckItemRepository;
import com.ava.backend.avastock.repository.PartQrCodeRepository;
import com.ava.backend.avastock.repository.PartRepository;
import com.ava.backend.avastock.repository.PartStockMovementRepository;
import com.ava.backend.avastock.repository.ProductModelRepository;
import com.ava.backend.avastock.repository.ProductOperationRepository;
import com.ava.backend.avastock.repository.ProductReceiptRepository;
import com.ava.backend.avastock.repository.ProductStatusHistoryRepository;
import com.ava.backend.avastock.repository.ProductUnitRepository;
import com.ava.backend.avastock.repository.ServiceCaseRepository;
import com.ava.backend.avastock.repository.ShipmentItemRepository;
import com.ava.backend.avastock.repository.ShipmentRepository;

@Service
public class AvaStockService {

	private static final String MFG = "MANUFACTURING";
	private static final String AS = "AS";
	private static final List<String> NON_CANCELLED = List.of("DRAFT", "SAVED", "COMPLETED");
	private static final List<String> OPEN_SERVICE = List.of("OPEN", "SAVED");

	private final ProductModelRepository productModels;
	private final BomVersionRepository bomVersions;
	private final BomItemRepository bomItems;
	private final PartRepository parts;
	private final PartQrCodeRepository partQrCodes;
	private final ProductReceiptRepository productReceipts;
	private final ProductUnitRepository productUnits;
	private final ProductOperationRepository operations;
	private final OperationCheckItemRepository checkItems;
	private final PartStockMovementRepository movements;
	private final ServiceCaseRepository serviceCases;
	private final FinishedProductRepository finishedProducts;
	private final DestinationRepository destinations;
	private final ShipmentRepository shipments;
	private final ShipmentItemRepository shipmentItems;
	private final ProductStatusHistoryRepository statusHistory;

	public AvaStockService(
		ProductModelRepository productModels,
		BomVersionRepository bomVersions,
		BomItemRepository bomItems,
		PartRepository parts,
		PartQrCodeRepository partQrCodes,
		ProductReceiptRepository productReceipts,
		ProductUnitRepository productUnits,
		ProductOperationRepository operations,
		OperationCheckItemRepository checkItems,
		PartStockMovementRepository movements,
		ServiceCaseRepository serviceCases,
		FinishedProductRepository finishedProducts,
		DestinationRepository destinations,
		ShipmentRepository shipments,
		ShipmentItemRepository shipmentItems,
		ProductStatusHistoryRepository statusHistory
	) {
		this.productModels = productModels;
		this.bomVersions = bomVersions;
		this.bomItems = bomItems;
		this.parts = parts;
		this.partQrCodes = partQrCodes;
		this.productReceipts = productReceipts;
		this.productUnits = productUnits;
		this.operations = operations;
		this.checkItems = checkItems;
		this.movements = movements;
		this.serviceCases = serviceCases;
		this.finishedProducts = finishedProducts;
		this.destinations = destinations;
		this.shipments = shipments;
		this.shipmentItems = shipmentItems;
		this.statusHistory = statusHistory;
	}

	@Transactional(readOnly = true)
	public Map<String, Object> home() {
		return map(
			"summary", dashboardSummary(),
			"recentShipments", recentShipments(),
			"inventory", partInventory()
		);
	}

	@Transactional(readOnly = true)
	public Map<String, Object> qrLookup(String qrValue) {
		String value = normalize(qrValue);
		return productUnits.findByQrValue(value)
			.map(product -> map(
				"qrType", "PRODUCT",
				"qrValue", value,
				"productUnitId", product.getId(),
				"partId", null,
				"modelCode", product.getModel().getModelCode(),
				"modelName", product.getModel().getModelName(),
				"serialNo", product.getSerialNo(),
				"currentStatus", product.getCurrentStatus(),
				"partCode", null,
				"partName", null
			))
			.or(() -> partQrCodes.findByQrValueAndActiveTrue(value)
				.map(partQr -> map(
					"qrType", "PART",
					"qrValue", value,
					"productUnitId", null,
					"partId", partQr.getPart().getId(),
					"modelCode", null,
					"modelName", null,
					"serialNo", null,
					"currentStatus", null,
					"partCode", partQr.getPart().getPartCode(),
					"partName", partQr.getPart().getPartName()
				)))
			.orElseGet(() -> map("qrType", "UNKNOWN", "qrValue", value));
	}

	@Transactional
	public Map<String, Object> receiveProduct(AvaStockProductReceiptRequest request, AuthPrincipal principal) {
		ProductModelEntity model = productModels.findByModelCodeIgnoreCase(normalize(request.modelCode()))
			.orElseThrow(() -> notFound("Product model not found."));
		BomVersionEntity bom = bomVersions.findFirstByModelAndCurrentVersionTrueAndActiveTrue(model)
			.orElseThrow(() -> notFound("Current BOM version not found."));
		ProductReceiptEntity receipt = productReceipts.save(new ProductReceiptEntity(
			blankToNull(request.supplierName()),
			blankToNull(request.memo()),
			principal.userId()
		));
		ProductUnitEntity product = productUnits.save(new ProductUnitEntity(
			model,
			bom,
			receipt,
			normalize(request.serialNo()),
			normalize(request.qrValue())
		));
		writeStatusHistory(product, null, product.getCurrentStatus(), "RECEIPT", "RECEIPT", receipt.getId(), principal.userId());
		return productDetail(product.getId());
	}

	@Transactional(readOnly = true)
	public Map<String, Object> productDetail(Long productUnitId) {
		ProductUnitEntity product = product(productUnitId);
		return productMap(product, progress(product), usedParts(product));
	}

	@Transactional(readOnly = true)
	public Map<String, Object> productByQr(String qrValue) {
		ProductUnitEntity product = productUnits.findByQrValue(normalize(qrValue))
			.orElseThrow(() -> notFound("Product QR not found."));
		return productMap(product, progress(product), usedParts(product));
	}

	@Transactional
	public Map<String, Object> manufacturingChecklist(Long productUnitId) {
		ProductUnitEntity product = product(productUnitId);
		ProductOperationEntity operation = manufacturingOperation(product, null);
		return checklist(product, operation);
	}

	@Transactional
	public Map<String, Object> saveManufacturing(Long productUnitId, AvaStockChecklistSaveRequest request, AuthPrincipal principal) {
		ProductUnitEntity product = product(productUnitId);
		ProductOperationEntity operation = manufacturingOperation(product, principal.userId());
		applyChecklist(operation, request, false, "PRODUCTION_USE", principal.userId());
		operation.markSaved(request == null ? null : request.notes());
		String previous = product.getCurrentStatus();
		product.setCurrentStatus("MFG_SAVED");
		writeStatusHistory(product, previous, "MFG_SAVED", "MANUFACTURING_SAVE", "OPERATION", operation.getId(), principal.userId());
		return checklist(product, operations.save(operation));
	}

	@Transactional
	public Map<String, Object> completeManufacturing(Long productUnitId, AvaStockChecklistSaveRequest request, AuthPrincipal principal) {
		ProductUnitEntity product = product(productUnitId);
		ProductOperationEntity operation = manufacturingOperation(product, principal.userId());
		applyChecklist(operation, request, true, "PRODUCTION_USE", principal.userId());
		operation.markCompleted(principal.userId(), request == null ? null : request.notes());
		operations.save(operation);
		String previous = product.getCurrentStatus();
		product.setCurrentStatus("MFG_REVIEW");
		writeStatusHistory(product, previous, "MFG_REVIEW", "MANUFACTURING_REVIEW", "OPERATION", operation.getId(), principal.userId());
		return productDetail(productUnitId);
	}

	@Transactional
	public Map<String, Object> startService(Long productUnitId, AvaStockServiceStartRequest request, AuthPrincipal principal) {
		ProductUnitEntity product = product(productUnitId);
		ServiceCaseEntity serviceCase = serviceCases.findFirstByProductUnitAndServiceStatusIn(product, OPEN_SERVICE)
			.orElseGet(() -> serviceCases.save(new ServiceCaseEntity(
				product,
				"AS-" + product.getId() + "-" + System.currentTimeMillis(),
				request == null ? null : request.issueSummary(),
				principal.userId()
			)));
		ProductOperationEntity operation = operations.findFirstByServiceCaseAndOperationTypeAndOperationStatusNot(serviceCase, AS, "CANCELLED")
			.orElseGet(() -> operations.save(new ProductOperationEntity(product, product.getBomVersion(), serviceCase, AS, principal.userId())));
		String previous = product.getCurrentStatus();
		product.setCurrentStatus("AS_IN_PROGRESS");
		writeStatusHistory(product, previous, "AS_IN_PROGRESS", "AS_START", "SERVICE_CASE", serviceCase.getId(), principal.userId());
		return map("serviceCase", serviceCaseMap(serviceCase), "checklist", checklist(product, operation));
	}

	@Transactional(readOnly = true)
	public Map<String, Object> serviceChecklist(Long serviceCaseId) {
		ServiceCaseEntity serviceCase = serviceCase(serviceCaseId);
		ProductOperationEntity operation = operations.findFirstByServiceCaseAndOperationTypeAndOperationStatusNot(serviceCase, AS, "CANCELLED")
			.orElseThrow(() -> notFound("A/S operation not found."));
		return map("serviceCase", serviceCaseMap(serviceCase), "checklist", checklist(serviceCase.getProductUnit(), operation));
	}

	@Transactional
	public Map<String, Object> saveService(Long serviceCaseId, AvaStockChecklistSaveRequest request, AuthPrincipal principal) {
		ServiceCaseEntity serviceCase = serviceCase(serviceCaseId);
		ProductOperationEntity operation = operations.findFirstByServiceCaseAndOperationTypeAndOperationStatusNot(serviceCase, AS, "CANCELLED")
			.orElseThrow(() -> notFound("A/S operation not found."));
		applyChecklist(operation, request, false, "AS_USE", principal.userId());
		operation.markSaved(request == null ? null : request.notes());
		serviceCase.markSaved();
		return serviceChecklist(serviceCaseId);
	}

	@Transactional
	public Map<String, Object> completeService(Long serviceCaseId, AvaStockChecklistSaveRequest request, AuthPrincipal principal) {
		ServiceCaseEntity serviceCase = serviceCase(serviceCaseId);
		ProductOperationEntity operation = operations.findFirstByServiceCaseAndOperationTypeAndOperationStatusNot(serviceCase, AS, "CANCELLED")
			.orElseThrow(() -> notFound("A/S operation not found."));
		applyChecklist(operation, request, true, "AS_USE", principal.userId());
		operation.markCompleted(principal.userId(), request == null ? null : request.notes());
		serviceCase.markCompleted();
		ProductUnitEntity product = serviceCase.getProductUnit();
		String previous = product.getCurrentStatus();
		product.setCurrentStatus("AS_READY");
		writeStatusHistory(product, previous, "AS_READY", "AS_COMPLETE", "SERVICE_CASE", serviceCase.getId(), principal.userId());
		return productDetail(product.getId());
	}

	@Transactional(readOnly = true)
	public Map<String, Object> partDetail(Long partId) {
		PartEntity part = partEntity(partId);
		return partMap(part, movements.currentQty(part));
	}

	@Transactional(readOnly = true)
	public Map<String, Object> partByQr(String qrValue) {
		PartQrCodeEntity partQr = partQrCodes.findByQrValueAndActiveTrue(normalize(qrValue))
			.orElseThrow(() -> notFound("Part QR not found."));
		return partMap(partQr.getPart(), movements.currentQty(partQr.getPart()));
	}

	@Transactional
	public Map<String, Object> purchasePart(Long partId, AvaStockPartPurchaseRequest request, AuthPrincipal principal) {
		PartEntity part = partEntity(partId);
		PartStockMovementEntity movement = new PartStockMovementEntity(
			part,
			"PURCHASE_IN",
			Math.max(1, request.quantity()),
			blankToNull(request.memo()),
			principal.userId()
		);
		if (request.qrValue() != null && !request.qrValue().isBlank()) {
			partQrCodes.findByQrValueAndActiveTrue(normalize(request.qrValue())).ifPresent(movement::setPartQr);
		}
		movements.save(movement);
		return partDetail(partId);
	}

	@Transactional
	public Map<String, Object> adjustPart(Long partId, AvaStockPartAdjustRequest request, AuthPrincipal principal) {
		if (request.quantity() == 0) {
			throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Adjustment quantity must not be zero.");
		}
		PartEntity part = partEntity(partId);
		String type = request.quantity() > 0 ? "ADJUSTMENT_IN" : "ADJUSTMENT_OUT";
		movements.save(new PartStockMovementEntity(part, type, request.quantity(), request.reason(), principal.userId()));
		return partDetail(partId);
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> partMovements(Long partId) {
		PartEntity part = partEntity(partId);
		return movements.findByPartOrderByCreatedAtDesc(part).stream()
			.map(movement -> map(
				"id", movement.getId(),
				"movementType", movement.getMovementType(),
				"qtyDelta", movement.getQtyDelta(),
				"createdAt", movement.getCreatedAt()
			))
			.toList();
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> partInventory() {
		return parts.findAll().stream()
			.sorted(Comparator.comparing(PartEntity::getPartCode, String.CASE_INSENSITIVE_ORDER))
			.map(part -> partMap(part, movements.currentQty(part)))
			.toList();
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> productModelMasters() {
		return productModels.findAll().stream()
			.sorted(Comparator.comparing(ProductModelEntity::getModelCode, String.CASE_INSENSITIVE_ORDER))
			.map(this::productModelMasterMap)
			.toList();
	}

	@Transactional
	public Map<String, Object> createProductModel(AvaStockProductModelUpsertRequest request) {
		String modelCode = normalize(request.modelCode());
		if (productModels.findByModelCodeIgnoreCase(modelCode).isPresent()) {
			throw new ResponseStatusException(HttpStatus.CONFLICT, "Product model code already exists.");
		}
		ProductModelEntity model = new ProductModelEntity(modelCode, normalize(request.modelName()));
		model.setDescription(blankToNull(request.description()));
		model.setImageUrl(blankToNull(request.imageUrl()));
		model.setActive(request.active() == null || request.active());
		return productModelMasterMap(productModels.save(model));
	}

	@Transactional
	public Map<String, Object> updateProductModel(Long modelId, AvaStockProductModelUpsertRequest request) {
		ProductModelEntity model = productModel(modelId);
		model.setModelName(normalize(request.modelName()));
		model.setDescription(blankToNull(request.description()));
		model.setImageUrl(blankToNull(request.imageUrl()));
		if (request.active() != null) {
			model.setActive(request.active());
		}
		return productModelMasterMap(productModels.save(model));
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> partMasters() {
		return parts.findAll().stream()
			.sorted(Comparator.comparing(PartEntity::getPartCode, String.CASE_INSENSITIVE_ORDER))
			.map(this::partMasterMap)
			.toList();
	}

	@Transactional
	public Map<String, Object> createPart(AvaStockPartUpsertRequest request) {
		String partCode = normalize(request.partCode());
		if (parts.findByPartCodeIgnoreCase(partCode).isPresent()) {
			throw new ResponseStatusException(HttpStatus.CONFLICT, "Part code already exists.");
		}
		PartEntity part = new PartEntity(partCode, normalize(request.partName()));
		part.setUnit(blankToNull(request.unit()) == null ? "EA" : request.unit().trim());
		part.setImageUrl(blankToNull(request.imageUrl()));
		part.setDescription(blankToNull(request.description()));
		if (request.active() != null) {
			part.setActive(request.active());
		}
		return partMasterMap(parts.save(part));
	}

	@Transactional
	public Map<String, Object> updatePart(Long partId, AvaStockPartUpsertRequest request) {
		PartEntity part = partEntity(partId);
		part.setPartName(normalize(request.partName()));
		part.setUnit(blankToNull(request.unit()) == null ? "EA" : request.unit().trim());
		part.setImageUrl(blankToNull(request.imageUrl()));
		part.setDescription(blankToNull(request.description()));
		if (request.active() != null) {
			part.setActive(request.active());
		}
		return partMasterMap(parts.save(part));
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> bomVersions(Long modelId) {
		ProductModelEntity model = productModel(modelId);
		return bomVersions.findByModelOrderByVersionNoDesc(model).stream()
			.map(this::bomVersionMap)
			.toList();
	}

	@Transactional
	public Map<String, Object> createBomVersion(Long modelId, AvaStockBomVersionUpsertRequest request) {
		ProductModelEntity model = productModel(modelId);
		boolean makeCurrent = request.currentVersion() == null || request.currentVersion();
		if (makeCurrent) {
			clearCurrentBomVersion(model);
		}
		BomVersionEntity version = new BomVersionEntity(
			model,
			request.versionNo(),
			blankToNull(request.versionName()),
			makeCurrent
		);
		if (request.active() != null) {
			version.setActive(request.active());
		}
		return bomVersionMap(bomVersions.save(version));
	}

	@Transactional
	public Map<String, Object> updateBomVersion(Long bomVersionId, AvaStockBomVersionUpsertRequest request) {
		BomVersionEntity version = bomVersion(bomVersionId);
		version.setVersionName(blankToNull(request.versionName()));
		if (request.active() != null) {
			version.setActive(request.active());
		}
		if (request.currentVersion() != null) {
			if (request.currentVersion()) {
				clearCurrentBomVersion(version.getModel());
			}
			version.setCurrentVersion(request.currentVersion());
		}
		return bomVersionMap(bomVersions.save(version));
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> bomItems(Long bomVersionId) {
		BomVersionEntity version = bomVersion(bomVersionId);
		return bomItems.findByBomVersionOrderBySortOrderAsc(version).stream()
			.map(this::bomItemMap)
			.toList();
	}

	@Transactional
	public Map<String, Object> createBomItem(Long bomVersionId, AvaStockBomItemUpsertRequest request) {
		BomVersionEntity version = bomVersion(bomVersionId);
		PartEntity part = partEntity(request.partId());
		BomItemEntity item = new BomItemEntity(version, version.getModel(), part, request.sortOrder() == null ? 1 : request.sortOrder());
		item.setItemLabel(blankToNull(request.itemLabel()));
		item.setDefaultQty(request.defaultQty() == null ? 1 : request.defaultQty());
		item.setRequiredFlag(Boolean.TRUE.equals(request.requiredFlag()));
		item.setActive(request.active() == null || request.active());
		return bomItemMap(bomItems.save(item));
	}

	@Transactional
	public Map<String, Object> updateBomItem(Long bomItemId, AvaStockBomItemUpsertRequest request) {
		BomItemEntity item = bomItem(bomItemId);
		item.setItemLabel(blankToNull(request.itemLabel()));
		item.setDefaultQty(request.defaultQty() == null ? item.getDefaultQty() : request.defaultQty());
		item.setSortOrder(request.sortOrder() == null ? item.getSortOrder() : request.sortOrder());
		item.setRequiredFlag(Boolean.TRUE.equals(request.requiredFlag()));
		if (request.active() != null) {
			item.setActive(request.active());
		}
		return bomItemMap(bomItems.save(item));
	}

	@Transactional
	public Map<String, Object> deactivateBomItem(Long bomItemId) {
		BomItemEntity item = bomItem(bomItemId);
		item.setActive(false);
		return bomItemMap(bomItems.save(item));
	}

	@Transactional
	public Map<String, Object> createPartQrCode(Long partId, AvaStockPartQrCodeCreateRequest request) {
		PartEntity part = partEntity(partId);
		String qrValue = normalize(request.qrValue());
		if (partQrCodes.findByQrValueAndActiveTrue(qrValue).isPresent()) {
			throw new ResponseStatusException(HttpStatus.CONFLICT, "Part QR already exists.");
		}
		PartQrCodeEntity qrCode = new PartQrCodeEntity(part, qrValue, blankToNull(request.label()));
		qrCode.setLocationCode(blankToNull(request.locationCode()));
		return partQrMap(partQrCodes.save(qrCode));
	}

	@Transactional
	public Map<String, Object> createShipment(AvaStockShipmentCreateRequest request, AuthPrincipal principal) {
		DestinationEntity destination = destinations.findByDestinationNameIgnoreCase(request.destinationName().trim())
			.orElseGet(() -> destinations.save(new DestinationEntity(request.destinationName().trim())));
		String shipmentStatus = blankToNull(request.shipmentStatus()) == null ? "IN_TRANSIT" : request.shipmentStatus().trim().toUpperCase();
		ShipmentEntity shipment = shipments.save(new ShipmentEntity(
			destination,
			request.shippingMethod().trim(),
			request.shippingDate() == null ? LocalDate.now() : request.shippingDate(),
			shipmentStatus,
			principal.userId()
		));
		for (Long productUnitId : request.productUnitIds()) {
			ProductUnitEntity product = product(productUnitId);
			String requestedImei = blankToNull(request.imei());
			if (requestedImei != null && !requestedImei.equals(product.getSerialNo())) {
				productUnits.findBySerialNo(requestedImei)
					.filter(existing -> !existing.getId().equals(product.getId()))
					.ifPresent(existing -> {
						throw new ResponseStatusException(HttpStatus.CONFLICT, "IMEI already exists.");
					});
				product.setSerialNo(requestedImei);
			}
			confirmManufacturingIfPending(product, principal.userId());
			shipmentItems.save(new ShipmentItemEntity(shipment, product));
			String nextStatus = "READY".equals(shipmentStatus)
				? ("AS_READY".equals(product.getCurrentStatus()) ? "AS_READY" : "FINISHED_READY")
				: ("DELIVERED".equals(shipmentStatus) ? "SHIPPED" : "SHIPPING");
			String previous = product.getCurrentStatus();
			if (!previous.equals(nextStatus)) {
				product.setCurrentStatus(nextStatus);
				writeStatusHistory(product, previous, nextStatus, "SHIPMENT", "SHIPMENT", shipment.getId(), principal.userId());
			}
		}
		return shipmentMap(shipment);
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> recentShipments() {
		return shipments.findTop20ByOrderByShippingDateDescCreatedAtDesc().stream()
			.map(this::shipmentMap)
			.toList();
	}

	@Transactional(readOnly = true)
	public Map<String, Object> shipmentDetail(Long shipmentId) {
		ShipmentEntity shipment = shipments.findById(shipmentId)
			.orElseThrow(() -> notFound("Shipment not found."));
		return shipmentMap(shipment);
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> partUsage() {
		return movements.findAll().stream()
			.filter(movement -> movement.getProductUnit() != null)
			.sorted(Comparator.comparing(
				PartStockMovementEntity::getCreatedAt,
				Comparator.nullsLast(Comparator.reverseOrder())
			))
			.limit(200)
			.map(movement -> {
				ProductUnitEntity product = movement.getProductUnit();
				List<ShipmentItemEntity> productShipments = shipmentItems.findByProductUnit(product);
				ShipmentEntity latestShipment = productShipments.stream()
					.map(ShipmentItemEntity::getShipment)
					.max(Comparator.comparing(ShipmentEntity::getCreatedAt))
					.orElse(null);
				return map(
					"movementId", movement.getId(),
					"partId", movement.getPart().getId(),
					"partCode", movement.getPart().getPartCode(),
					"partName", movement.getPart().getPartName(),
					"movementType", movement.getMovementType(),
					"qtyDelta", movement.getQtyDelta(),
					"createdAt", movement.getCreatedAt(),
					"productUnitId", product.getId(),
					"modelCode", product.getModel().getModelCode(),
					"modelName", product.getModel().getModelName(),
					"serialNo", product.getSerialNo(),
					"destinationName", latestShipment == null ? null : latestShipment.getDestination().getDestinationName(),
					"shippingMethod", latestShipment == null ? null : latestShipment.getShippingMethod(),
					"shippingDate", latestShipment == null ? null : latestShipment.getShippingDate()
				);
			})
			.toList();
	}

	@Transactional(readOnly = true)
	public Map<String, Object> dashboardSummary() {
		List<ProductUnitEntity> products = productUnits.findAll();
		long semi = products.stream().filter(product -> "SEMI_RECEIVED".equals(product.getCurrentStatus())).count();
		long inProduction = products.stream().filter(product -> "MFG_SAVED".equals(product.getCurrentStatus())).count();
		long reviewPending = products.stream().filter(product -> "MFG_REVIEW".equals(product.getCurrentStatus())).count();
		long as = products.stream().filter(product -> "AS_IN_PROGRESS".equals(product.getCurrentStatus())).count();
		long shippable = products.stream().filter(product -> List.of("FINISHED_READY", "AS_READY").contains(product.getCurrentStatus())).count();
		long shipping = products.stream().filter(product -> "SHIPPING".equals(product.getCurrentStatus())).count();
		return map(
			"totalStock", semi + inProduction + reviewPending + as + shippable + shipping,
			"semiStock", semi,
			"inProduction", inProduction,
			"reviewPending", reviewPending,
			"asInProgress", as,
			"shippable", shippable,
			"shipping", shipping,
			"inspectionRepair", as
		);
	}

	@Transactional(readOnly = true)
	public List<Map<String, Object>> dashboardStock() {
		Map<ProductModelEntity, List<ProductUnitEntity>> grouped = productUnits.findAll().stream()
			.collect(Collectors.groupingBy(ProductUnitEntity::getModel));
		return grouped.entrySet().stream()
			.sorted(Comparator.comparing(entry -> entry.getKey().getModelCode(), String.CASE_INSENSITIVE_ORDER))
			.map(entry -> {
				List<ProductUnitEntity> products = entry.getValue();
				return map(
					"modelId", entry.getKey().getId(),
					"modelCode", entry.getKey().getModelCode(),
					"modelName", entry.getKey().getModelName(),
					"totalRegisteredProducts", products.size(),
					"semiStockQty", countStatus(products, "SEMI_RECEIVED"),
					"inProductionQty", countStatus(products, "MFG_SAVED"),
					"reviewPendingQty", countStatus(products, "MFG_REVIEW"),
					"asInProgressQty", countStatus(products, "AS_IN_PROGRESS"),
					"shippableQty", countStatus(products, "FINISHED_READY", "AS_READY"),
					"shippingQty", countStatus(products, "SHIPPING"),
					"shippedQty", countStatus(products, "SHIPPED")
				);
			})
			.toList();
	}

	private ProductOperationEntity manufacturingOperation(ProductUnitEntity product, UUID actorId) {
		return operations.findFirstByProductUnitAndOperationTypeAndOperationStatusNot(product, MFG, "CANCELLED")
			.orElseGet(() -> operations.save(new ProductOperationEntity(product, product.getBomVersion(), null, MFG, actorId)));
	}

	private void confirmManufacturingIfPending(ProductUnitEntity product, UUID actorId) {
		if (!"MFG_REVIEW".equals(product.getCurrentStatus())) {
			return;
		}
		ProductOperationEntity operation = operations.findFirstByProductUnitAndOperationTypeAndOperationStatusNot(product, MFG, "CANCELLED")
			.orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "Manufacturing operation is not ready for confirmation."));
		if (!"COMPLETED".equals(operation.getOperationStatus())) {
			throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Manufacturing checklist must be completed before confirmation.");
		}
		finishedProducts.findByProductUnit(product)
			.orElseGet(() -> finishedProducts.save(new FinishedProductEntity(product, operation, actorId)));
		String previous = product.getCurrentStatus();
		product.setCurrentStatus("FINISHED_READY");
		writeStatusHistory(product, previous, "FINISHED_READY", "MANUFACTURING_CONFIRM", "OPERATION", operation.getId(), actorId);
	}

	private void applyChecklist(
		ProductOperationEntity operation,
		AvaStockChecklistSaveRequest request,
		boolean complete,
		String useMovementType,
		UUID actorId
	) {
		Map<Long, AvaStockChecklistSaveRequest.Item> requestItems = request == null || request.items() == null
			? Map.of()
			: request.items().stream()
				.filter(item -> item.bomItemId() != null)
				.collect(Collectors.toMap(AvaStockChecklistSaveRequest.Item::bomItemId, Function.identity(), (left, right) -> right));
		List<BomItemEntity> bomRows = bomItems.findByBomVersionAndActiveTrueOrderBySortOrderAsc(operation.getBomVersion());
		for (BomItemEntity bomItem : bomRows) {
			AvaStockChecklistSaveRequest.Item requestItem = requestItems.get(bomItem.getId());
			boolean used = requestItem != null && requestItem.used();
			int targetQty = used ? Math.max(1, requestItem.quantity() == null ? bomItem.getDefaultQty() : requestItem.quantity()) : 0;
			String status = used ? "USED" : complete ? "NOT_USED" : "PENDING";
			OperationCheckItemEntity checkItem = checkItems.findByOperationAndBomItem(operation, bomItem)
				.orElseGet(() -> checkItems.save(new OperationCheckItemEntity(operation, bomItem)));
			checkItem.setState(status, targetQty, actorId, requestItem == null ? null : blankToNull(requestItem.memo()));
			checkItems.save(checkItem);
			int targetDelta = used ? -targetQty : 0;
			int postedDelta = movements.postedDelta(checkItem);
			int delta = targetDelta - postedDelta;
			if (delta < 0) {
				movements.save(PartStockMovementEntity.forCheckItem(checkItem, useMovementType, delta, "Checklist use", actorId));
			} else if (delta > 0) {
				movements.save(PartStockMovementEntity.forCheckItem(checkItem, "REVERSAL", delta, "Checklist reversal", actorId));
			}
		}
	}

	private Map<String, Object> checklist(ProductUnitEntity product, ProductOperationEntity operation) {
		List<OperationCheckItemEntity> existing = checkItems.findByOperationOrderByBomItemSortOrderAsc(operation);
		Map<Long, OperationCheckItemEntity> byBomItem = existing.stream()
			.collect(Collectors.toMap(item -> item.getBomItem().getId(), Function.identity()));
		List<Map<String, Object>> items = new ArrayList<>();
		for (BomItemEntity bomItem : bomItems.findByBomVersionAndActiveTrueOrderBySortOrderAsc(product.getBomVersion())) {
			OperationCheckItemEntity checkItem = byBomItem.get(bomItem.getId());
			items.add(map(
				"checkItemId", checkItem == null ? null : checkItem.getId(),
				"bomItemId", bomItem.getId(),
				"partId", bomItem.getPart().getId(),
				"partCode", bomItem.getPart().getPartCode(),
				"partName", displayPartName(bomItem),
				"defaultQty", bomItem.getDefaultQty(),
				"sortOrder", bomItem.getSortOrder(),
				"required", bomItem.isRequiredFlag(),
				"checkStatus", checkItem == null ? "PENDING" : checkItem.getCheckStatus(),
				"qtyUsed", checkItem == null ? 0 : checkItem.getQtyUsed(),
				"memo", checkItem == null ? null : checkItem.getMemo()
			));
		}
		return map(
			"product", productMap(product, progress(product), usedParts(product)),
			"operationId", operation.getId(),
			"operationType", operation.getOperationType(),
			"operationStatus", operation.getOperationStatus(),
			"items", items,
			"progress", progressFromItems(items)
		);
	}

	private Map<String, Object> progress(ProductUnitEntity product) {
		return operations.findFirstByProductUnitAndOperationTypeAndOperationStatusNot(product, MFG, "CANCELLED")
			.map(operation -> progressFromItems(checklistItemsOnly(product, operation)))
			.orElseGet(() -> progressFromItems(checklistItemsOnly(product, null)));
	}

	private List<Map<String, Object>> checklistItemsOnly(ProductUnitEntity product, ProductOperationEntity operation) {
		Map<Long, OperationCheckItemEntity> byBomItem = operation == null
			? Map.of()
			: checkItems.findByOperationOrderByBomItemSortOrderAsc(operation).stream()
				.collect(Collectors.toMap(item -> item.getBomItem().getId(), Function.identity()));
		return bomItems.findByBomVersionAndActiveTrueOrderBySortOrderAsc(product.getBomVersion()).stream()
			.map(bomItem -> {
				OperationCheckItemEntity checkItem = byBomItem.get(bomItem.getId());
				return map(
					"checkStatus", checkItem == null ? "PENDING" : checkItem.getCheckStatus(),
					"qtyUsed", checkItem == null ? 0 : checkItem.getQtyUsed()
				);
			})
			.toList();
	}

	private Map<String, Object> progressFromItems(List<Map<String, Object>> items) {
		int total = items.size();
		long used = items.stream().filter(item -> "USED".equals(item.get("checkStatus"))).count();
		long notUsed = items.stream().filter(item -> "NOT_USED".equals(item.get("checkStatus"))).count();
		long pending = Math.max(0, total - used - notUsed);
		long decided = used + notUsed;
		return map(
			"totalCheckItems", total,
			"usedItems", used,
			"notUsedItems", notUsed,
			"pendingItems", pending,
			"decidedItems", decided,
			"usedPartPct", total == 0 ? 0 : Math.round((used * 1000.0) / total) / 10.0,
			"decisionProgressPct", total == 0 ? 0 : Math.round((decided * 1000.0) / total) / 10.0
		);
	}

	private List<Map<String, Object>> usedParts(ProductUnitEntity product) {
		return operations.findByProductUnitAndOperationStatusIn(product, NON_CANCELLED).stream()
			.flatMap(operation -> checkItems.findByOperationOrderByBomItemSortOrderAsc(operation).stream())
			.filter(item -> "USED".equals(item.getCheckStatus()) && item.getQtyUsed() > 0)
			.collect(Collectors.groupingBy(item -> item.getPart().getId(), LinkedHashMap::new, Collectors.toList()))
			.values()
			.stream()
			.map(items -> {
				OperationCheckItemEntity first = items.get(0);
				int manufacturingQty = items.stream()
					.filter(item -> MFG.equals(item.getOperation().getOperationType()))
					.mapToInt(OperationCheckItemEntity::getQtyUsed)
					.sum();
				int asQty = items.stream()
					.filter(item -> AS.equals(item.getOperation().getOperationType()))
					.mapToInt(OperationCheckItemEntity::getQtyUsed)
					.sum();
				return map(
					"partId", first.getPart().getId(),
					"partCode", first.getPart().getPartCode(),
					"partName", first.getPart().getPartName(),
					"manufacturingQty", manufacturingQty,
					"asQty", asQty,
					"totalQty", manufacturingQty + asQty
				);
			})
			.toList();
	}

	private Map<String, Object> productMap(ProductUnitEntity product, Map<String, Object> progress, List<Map<String, Object>> usedParts) {
		ShipmentEntity latestShipment = shipmentItems.findByProductUnit(product).stream()
			.map(ShipmentItemEntity::getShipment)
			.max(Comparator.comparing(ShipmentEntity::getCreatedAt))
			.orElse(null);
		return map(
			"productUnitId", product.getId(),
			"modelId", product.getModel().getId(),
			"modelCode", product.getModel().getModelCode(),
			"modelName", product.getModel().getModelName(),
			"modelImageUrl", product.getModel().getImageUrl(),
			"serialNo", product.getSerialNo(),
			"qrValue", product.getQrValue(),
			"currentStatus", product.getCurrentStatus(),
			"progress", progress,
			"usedParts", usedParts,
			"latestShipment", latestShipment == null ? null : shipmentMap(latestShipment)
		);
	}

	private Map<String, Object> partMap(PartEntity part, int currentQty) {
		return map(
			"partId", part.getId(),
			"partCode", part.getPartCode(),
			"partName", part.getPartName(),
			"unit", part.getUnit(),
			"imageUrl", part.getImageUrl(),
			"description", part.getDescription(),
			"currentQty", currentQty
		);
	}

	private Map<String, Object> serviceCaseMap(ServiceCaseEntity serviceCase) {
		return map(
			"serviceCaseId", serviceCase.getId(),
			"serviceNo", serviceCase.getServiceNo(),
			"serviceStatus", serviceCase.getServiceStatus(),
			"issueSummary", serviceCase.getIssueSummary(),
			"productUnitId", serviceCase.getProductUnit().getId(),
			"startedAt", serviceCase.getStartedAt(),
			"savedAt", serviceCase.getSavedAt(),
			"completedAt", serviceCase.getCompletedAt()
		);
	}

	private Map<String, Object> shipmentMap(ShipmentEntity shipment) {
		List<ShipmentItemEntity> items = shipmentItems.findByShipment(shipment);
		ProductUnitEntity firstProduct = items.isEmpty() ? null : items.get(0).getProductUnit();
		return map(
			"shipmentId", shipment.getId(),
			"destinationName", shipment.getDestination().getDestinationName(),
			"shippingMethod", shipment.getShippingMethod(),
			"shippingDate", shipment.getShippingDate(),
			"shipmentStatus", shipment.getShipmentStatus(),
			"createdAt", shipment.getCreatedAt(),
			"productUnitId", firstProduct == null ? null : firstProduct.getId(),
			"modelCode", firstProduct == null ? null : firstProduct.getModel().getModelCode(),
			"modelName", firstProduct == null ? null : firstProduct.getModel().getModelName(),
			"serialNo", firstProduct == null ? null : firstProduct.getSerialNo(),
			"imei", firstProduct == null ? null : firstProduct.getSerialNo(),
			"qrValue", firstProduct == null ? null : firstProduct.getQrValue(),
			"currentStatus", firstProduct == null ? null : firstProduct.getCurrentStatus(),
			"items", items.stream()
				.map(this::shipmentItemMap)
				.toList()
		);
	}

	private Map<String, Object> shipmentItemMap(ShipmentItemEntity item) {
		ProductUnitEntity product = item.getProductUnit();
		return map(
			"shipmentItemId", item.getId(),
			"productUnitId", product.getId(),
			"modelCode", product.getModel().getModelCode(),
			"modelName", product.getModel().getModelName(),
			"serialNo", product.getSerialNo(),
			"qrValue", product.getQrValue(),
			"currentStatus", product.getCurrentStatus(),
			"itemStatus", item.getItemStatus()
		);
	}

	private Map<String, Object> productModelMasterMap(ProductModelEntity model) {
		return map(
			"modelId", model.getId(),
			"modelCode", model.getModelCode(),
			"modelName", model.getModelName(),
			"description", model.getDescription(),
			"imageUrl", model.getImageUrl(),
			"active", model.isActive(),
			"createdAt", model.getCreatedAt(),
			"updatedAt", model.getUpdatedAt(),
			"bomVersions", bomVersions.findByModelOrderByVersionNoDesc(model).stream()
				.map(this::bomVersionMap)
				.toList()
		);
	}

	private Map<String, Object> partMasterMap(PartEntity part) {
		return map(
			"partId", part.getId(),
			"partCode", part.getPartCode(),
			"partName", part.getPartName(),
			"unit", part.getUnit(),
			"imageUrl", part.getImageUrl(),
			"description", part.getDescription(),
			"active", part.isActive(),
			"currentQty", movements.currentQty(part),
			"qrCodes", partQrCodes.findByPartOrderByCreatedAtDesc(part).stream()
				.map(this::partQrMap)
				.toList()
		);
	}

	private Map<String, Object> bomVersionMap(BomVersionEntity version) {
		return map(
			"bomVersionId", version.getId(),
			"modelId", version.getModel().getId(),
			"modelCode", version.getModel().getModelCode(),
			"versionNo", version.getVersionNo(),
			"versionName", version.getVersionName(),
			"currentVersion", version.isCurrentVersion(),
			"effectiveFrom", version.getEffectiveFrom(),
			"effectiveTo", version.getEffectiveTo(),
			"active", version.isActive()
		);
	}

	private Map<String, Object> bomItemMap(BomItemEntity item) {
		return map(
			"bomItemId", item.getId(),
			"bomVersionId", item.getBomVersion().getId(),
			"modelId", item.getModel().getId(),
			"partId", item.getPart().getId(),
			"partCode", item.getPart().getPartCode(),
			"partName", item.getPart().getPartName(),
			"itemLabel", item.getItemLabel(),
			"defaultQty", item.getDefaultQty(),
			"sortOrder", item.getSortOrder(),
			"requiredFlag", item.isRequiredFlag(),
			"active", item.isActive()
		);
	}

	private Map<String, Object> partQrMap(PartQrCodeEntity qrCode) {
		return map(
			"partQrId", qrCode.getId(),
			"partId", qrCode.getPart().getId(),
			"qrValue", qrCode.getQrValue(),
			"label", qrCode.getLabel(),
			"locationCode", qrCode.getLocationCode(),
			"active", qrCode.isActive(),
			"createdAt", qrCode.getCreatedAt()
		);
	}

	private void writeStatusHistory(
		ProductUnitEntity product,
		String fromStatus,
		String toStatus,
		String reason,
		String refType,
		Long refId,
		UUID changedBy
	) {
		if (fromStatus != null && fromStatus.equals(toStatus)) {
			return;
		}
		statusHistory.save(new ProductStatusHistoryEntity(product, fromStatus, toStatus, reason, refType, refId, changedBy));
	}

	private ProductUnitEntity product(Long productUnitId) {
		return productUnits.findById(productUnitId).orElseThrow(() -> notFound("Product not found."));
	}

	private ProductModelEntity productModel(Long modelId) {
		return productModels.findById(modelId).orElseThrow(() -> notFound("Product model not found."));
	}

	private BomVersionEntity bomVersion(Long bomVersionId) {
		return bomVersions.findById(bomVersionId).orElseThrow(() -> notFound("BOM version not found."));
	}

	private BomItemEntity bomItem(Long bomItemId) {
		return bomItems.findById(bomItemId).orElseThrow(() -> notFound("BOM item not found."));
	}

	private PartEntity partEntity(Long partId) {
		return parts.findById(partId).orElseThrow(() -> notFound("Part not found."));
	}

	private ServiceCaseEntity serviceCase(Long serviceCaseId) {
		return serviceCases.findById(serviceCaseId).orElseThrow(() -> notFound("A/S case not found."));
	}

	private ResponseStatusException notFound(String message) {
		return new ResponseStatusException(HttpStatus.NOT_FOUND, message);
	}

	private void clearCurrentBomVersion(ProductModelEntity model) {
		bomVersions.findByModelOrderByVersionNoDesc(model).forEach(version -> {
			if (version.isCurrentVersion()) {
				version.setCurrentVersion(false);
			}
		});
	}

	private static String normalize(String value) {
		return value == null ? "" : value.trim();
	}

	private static String blankToNull(String value) {
		String normalized = normalize(value);
		return normalized.isBlank() ? null : normalized;
	}

	private static String displayPartName(BomItemEntity item) {
		return item.getItemLabel() == null || item.getItemLabel().isBlank()
			? item.getPart().getPartName()
			: item.getItemLabel();
	}

	private static long countStatus(Collection<ProductUnitEntity> products, String... statuses) {
		List<String> allowed = List.of(statuses);
		return products.stream().filter(product -> allowed.contains(product.getCurrentStatus())).count();
	}

	private static Map<String, Object> map(Object... values) {
		Map<String, Object> map = new LinkedHashMap<>();
		for (int i = 0; i + 1 < values.length; i += 2) {
			map.put(String.valueOf(values[i]), values[i + 1]);
		}
		return map;
	}
}
