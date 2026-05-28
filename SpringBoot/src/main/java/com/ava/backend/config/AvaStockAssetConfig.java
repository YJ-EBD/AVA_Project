package com.ava.backend.config;

import java.nio.file.Path;
import java.nio.file.Paths;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class AvaStockAssetConfig implements WebMvcConfigurer {

	@Override
	public void addResourceHandlers(ResourceHandlerRegistry registry) {
		Path projectRoot = projectRoot();
		registry
			.addResourceHandler("/ava-stock-assets/items/**")
			.addResourceLocations(projectRoot.resolve("_AVA_stock_Item").toUri().toString());
		registry
			.addResourceHandler("/ava-stock-assets/products/**")
			.addResourceLocations(projectRoot.resolve("_AVA_stock_product").toUri().toString());
	}

	private static Path projectRoot() {
		Path cwd = Paths.get("").toAbsolutePath().normalize();
		if (cwd.getFileName() != null && "SpringBoot".equalsIgnoreCase(cwd.getFileName().toString())) {
			Path parent = cwd.getParent();
			if (parent != null) {
				return parent;
			}
		}
		return cwd;
	}
}
