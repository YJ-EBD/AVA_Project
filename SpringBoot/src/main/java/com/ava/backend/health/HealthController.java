package com.ava.backend.health;

import java.util.List;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.config.ProductionReadinessValidator;

@RestController
@RequestMapping("/api")
public class HealthController {

	private final ProductionReadinessValidator productionReadinessValidator;

	public HealthController(ProductionReadinessValidator productionReadinessValidator) {
		this.productionReadinessValidator = productionReadinessValidator;
	}

	@GetMapping("/health")
	public Map<String, String> health() {
		return Map.of(
			"service", "ava-backend",
			"status", "UP"
		);
	}

	@GetMapping("/readiness")
	public Map<String, Object> readiness() {
		boolean productionLike = productionReadinessValidator.isProductionLikeEnvironment();
		List<String> problems = productionLike ? productionReadinessValidator.validate() : List.of();
		return Map.of(
			"service", "ava-backend",
			"status", problems.isEmpty() ? "READY" : "BLOCKED",
			"productionLike", productionLike,
			"problems", problems
		);
	}
}
