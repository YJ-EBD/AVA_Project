package com.ava.backend.avastock.controller;

import java.util.List;
import java.util.Map;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.avastock.dto.AvaStockChecklistSaveRequest;
import com.ava.backend.avastock.dto.AvaStockPartAdjustRequest;
import com.ava.backend.avastock.dto.AvaStockPartPurchaseRequest;
import com.ava.backend.avastock.dto.AvaStockProductReceiptRequest;
import com.ava.backend.avastock.dto.AvaStockQrLookupRequest;
import com.ava.backend.avastock.dto.AvaStockServiceStartRequest;
import com.ava.backend.avastock.dto.AvaStockShipmentCreateRequest;
import com.ava.backend.avastock.service.AvaStockService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/ava-stock")
public class AvaStockController {

	private final AvaStockService avaStockService;

	public AvaStockController(AvaStockService avaStockService) {
		this.avaStockService = avaStockService;
	}

	@GetMapping("/health")
	public Map<String, Object> health() {
		return Map.of("status", "ok", "feature", "AVA_stock");
	}

	@GetMapping("/home")
	public Map<String, Object> home() {
		return avaStockService.home();
	}

	@PostMapping("/qr/lookup")
	public Map<String, Object> qrLookup(@Valid @RequestBody AvaStockQrLookupRequest request) {
		return avaStockService.qrLookup(request.qrValue());
	}

	@PostMapping("/products/receipts")
	public Map<String, Object> receiveProduct(
		@Valid @RequestBody AvaStockProductReceiptRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.receiveProduct(request, principal);
	}

	@GetMapping("/products/{productUnitId}")
	public Map<String, Object> product(@PathVariable Long productUnitId) {
		return avaStockService.productDetail(productUnitId);
	}

	@GetMapping("/products/by-qr/{qrValue}")
	public Map<String, Object> productByQr(@PathVariable String qrValue) {
		return avaStockService.productByQr(qrValue);
	}

	@GetMapping("/products/{productUnitId}/progress")
	public Map<String, Object> productProgress(@PathVariable Long productUnitId) {
		return (Map<String, Object>) avaStockService.productDetail(productUnitId).get("progress");
	}

	@GetMapping("/products/{productUnitId}/used-parts")
	public Object usedParts(@PathVariable Long productUnitId) {
		return avaStockService.productDetail(productUnitId).get("usedParts");
	}

	@GetMapping("/products/{productUnitId}/manufacturing/checklist")
	public Map<String, Object> manufacturingChecklist(@PathVariable Long productUnitId) {
		return avaStockService.manufacturingChecklist(productUnitId);
	}

	@PostMapping("/products/{productUnitId}/manufacturing/save")
	public Map<String, Object> saveManufacturing(
		@PathVariable Long productUnitId,
		@RequestBody AvaStockChecklistSaveRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.saveManufacturing(productUnitId, request, principal);
	}

	@PostMapping("/products/{productUnitId}/manufacturing/complete")
	public Map<String, Object> completeManufacturing(
		@PathVariable Long productUnitId,
		@RequestBody AvaStockChecklistSaveRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.completeManufacturing(productUnitId, request, principal);
	}

	@PostMapping("/products/{productUnitId}/service/start")
	public Map<String, Object> startService(
		@PathVariable Long productUnitId,
		@RequestBody(required = false) AvaStockServiceStartRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.startService(productUnitId, request, principal);
	}

	@GetMapping("/service-cases/{serviceCaseId}/checklist")
	public Map<String, Object> serviceChecklist(@PathVariable Long serviceCaseId) {
		return avaStockService.serviceChecklist(serviceCaseId);
	}

	@PostMapping("/service-cases/{serviceCaseId}/save")
	public Map<String, Object> saveService(
		@PathVariable Long serviceCaseId,
		@RequestBody AvaStockChecklistSaveRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.saveService(serviceCaseId, request, principal);
	}

	@PostMapping("/service-cases/{serviceCaseId}/complete")
	public Map<String, Object> completeService(
		@PathVariable Long serviceCaseId,
		@RequestBody AvaStockChecklistSaveRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.completeService(serviceCaseId, request, principal);
	}

	@GetMapping("/parts/{partId}")
	public Map<String, Object> part(@PathVariable Long partId) {
		return avaStockService.partDetail(partId);
	}

	@GetMapping("/parts/by-qr/{qrValue}")
	public Map<String, Object> partByQr(@PathVariable String qrValue) {
		return avaStockService.partByQr(qrValue);
	}

	@PostMapping("/parts/{partId}/purchase")
	public Map<String, Object> purchasePart(
		@PathVariable Long partId,
		@Valid @RequestBody AvaStockPartPurchaseRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.purchasePart(partId, request, principal);
	}

	@PostMapping("/parts/{partId}/adjust")
	public Map<String, Object> adjustPart(
		@PathVariable Long partId,
		@Valid @RequestBody AvaStockPartAdjustRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.adjustPart(partId, request, principal);
	}

	@GetMapping("/parts/{partId}/movements")
	public List<Map<String, Object>> partMovements(@PathVariable Long partId) {
		return avaStockService.partMovements(partId);
	}

	@GetMapping("/parts/inventory")
	public List<Map<String, Object>> partInventory() {
		return avaStockService.partInventory();
	}

	@PostMapping("/shipments")
	public Map<String, Object> createShipment(
		@Valid @RequestBody AvaStockShipmentCreateRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaStockService.createShipment(request, principal);
	}

	@GetMapping("/shipments")
	public List<Map<String, Object>> shipments() {
		return avaStockService.recentShipments();
	}

	@GetMapping("/shipments/{shipmentId}")
	public Map<String, Object> shipment(@PathVariable Long shipmentId) {
		return avaStockService.shipmentDetail(shipmentId);
	}

	@GetMapping("/dashboard/summary")
	public Map<String, Object> dashboardSummary() {
		return avaStockService.dashboardSummary();
	}

	@GetMapping("/dashboard/stock")
	public List<Map<String, Object>> dashboardStock() {
		return avaStockService.dashboardStock();
	}

	@GetMapping("/dashboard/recent-shipments")
	public List<Map<String, Object>> dashboardRecentShipments() {
		return avaStockService.recentShipments();
	}

	@GetMapping("/dashboard/part-usage")
	public List<Map<String, Object>> dashboardPartUsage() {
		return avaStockService.partUsage();
	}

	@GetMapping("/dashboard/shipment-history")
	public List<Map<String, Object>> dashboardShipmentHistory() {
		return avaStockService.recentShipments();
	}
}
