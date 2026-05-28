package com.ava.backend.avastock.controller;

import java.util.List;
import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.avastock.dto.AvaStockBomItemUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockBomVersionUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockPartQrCodeCreateRequest;
import com.ava.backend.avastock.dto.AvaStockPartUpsertRequest;
import com.ava.backend.avastock.dto.AvaStockProductModelUpsertRequest;
import com.ava.backend.avastock.service.AvaStockService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/ava-stock/admin")
@PreAuthorize("hasAnyRole('ADMIN','SUPERUSER')")
public class AvaStockAdminController {

	private final AvaStockService avaStockService;

	public AvaStockAdminController(AvaStockService avaStockService) {
		this.avaStockService = avaStockService;
	}

	@GetMapping("/product-models")
	public List<Map<String, Object>> productModels() {
		return avaStockService.productModelMasters();
	}

	@PostMapping("/product-models")
	public Map<String, Object> createProductModel(@Valid @RequestBody AvaStockProductModelUpsertRequest request) {
		return avaStockService.createProductModel(request);
	}

	@PutMapping("/product-models/{modelId}")
	public Map<String, Object> updateProductModel(
		@PathVariable Long modelId,
		@Valid @RequestBody AvaStockProductModelUpsertRequest request
	) {
		return avaStockService.updateProductModel(modelId, request);
	}

	@GetMapping("/product-models/{modelId}/bom-versions")
	public List<Map<String, Object>> bomVersions(@PathVariable Long modelId) {
		return avaStockService.bomVersions(modelId);
	}

	@PostMapping("/product-models/{modelId}/bom-versions")
	public Map<String, Object> createBomVersion(
		@PathVariable Long modelId,
		@Valid @RequestBody AvaStockBomVersionUpsertRequest request
	) {
		return avaStockService.createBomVersion(modelId, request);
	}

	@PutMapping("/bom-versions/{bomVersionId}")
	public Map<String, Object> updateBomVersion(
		@PathVariable Long bomVersionId,
		@Valid @RequestBody AvaStockBomVersionUpsertRequest request
	) {
		return avaStockService.updateBomVersion(bomVersionId, request);
	}

	@GetMapping("/bom-versions/{bomVersionId}/items")
	public List<Map<String, Object>> bomItems(@PathVariable Long bomVersionId) {
		return avaStockService.bomItems(bomVersionId);
	}

	@PostMapping("/bom-versions/{bomVersionId}/items")
	public Map<String, Object> createBomItem(
		@PathVariable Long bomVersionId,
		@Valid @RequestBody AvaStockBomItemUpsertRequest request
	) {
		return avaStockService.createBomItem(bomVersionId, request);
	}

	@PutMapping("/bom-items/{bomItemId}")
	public Map<String, Object> updateBomItem(
		@PathVariable Long bomItemId,
		@Valid @RequestBody AvaStockBomItemUpsertRequest request
	) {
		return avaStockService.updateBomItem(bomItemId, request);
	}

	@DeleteMapping("/bom-items/{bomItemId}")
	public Map<String, Object> deactivateBomItem(@PathVariable Long bomItemId) {
		return avaStockService.deactivateBomItem(bomItemId);
	}

	@GetMapping("/parts")
	public List<Map<String, Object>> parts() {
		return avaStockService.partMasters();
	}

	@PostMapping("/parts")
	public Map<String, Object> createPart(@Valid @RequestBody AvaStockPartUpsertRequest request) {
		return avaStockService.createPart(request);
	}

	@PutMapping("/parts/{partId}")
	public Map<String, Object> updatePart(
		@PathVariable Long partId,
		@Valid @RequestBody AvaStockPartUpsertRequest request
	) {
		return avaStockService.updatePart(partId, request);
	}

	@PostMapping("/parts/{partId}/qr-codes")
	public Map<String, Object> createPartQrCode(
		@PathVariable Long partId,
		@Valid @RequestBody AvaStockPartQrCodeCreateRequest request
	) {
		return avaStockService.createPartQrCode(partId, request);
	}
}
