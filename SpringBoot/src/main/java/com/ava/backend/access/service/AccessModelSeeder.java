package com.ava.backend.access.service;

import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.ava.backend.access.entity.AccessRoleEntity;
import com.ava.backend.access.entity.PermissionEntity;
import com.ava.backend.access.repository.AccessRoleRepository;
import com.ava.backend.access.repository.PermissionRepository;

@Configuration
public class AccessModelSeeder {

	@Bean
	ApplicationRunner seedAccessModel(
		AccessRoleRepository roleRepository,
		PermissionRepository permissionRepository
	) {
		return args -> {
			seedRole(roleRepository, "SUPERUSER", "Superuser", "Cross-company AVA administration permission.");
			seedRole(roleRepository, "ADMIN", "Administrator", "Company administration permission.");
			seedRole(roleRepository, "USER", "User", "Default AVA user permission.");
			seedPermission(permissionRepository, "users:read", "Read users", "Read company users and profiles.");
			seedPermission(permissionRepository, "users:manage", "Manage users", "Enable, disable, and update users.");
			seedPermission(permissionRepository, "chat:use", "Use chat", "Use normal AVA messenger chat.");
			seedPermission(permissionRepository, "azoom:use", "Use AZOOM", "Use AZOOM channels and media.");
			seedPermission(permissionRepository, "ai:use", "Use AVA AI", "Use AVA AI conversations.");
			seedPermission(permissionRepository, "admin:read", "Read admin", "Read admin dashboards and logs.");
			seedPermission(permissionRepository, "settings:manage", "Manage settings", "Update runtime application settings.");
		};
	}

	private void seedRole(AccessRoleRepository repository, String code, String name, String description) {
		if (!repository.existsByCode(code)) {
			repository.save(new AccessRoleEntity(code, name, description));
		}
	}

	private void seedPermission(PermissionRepository repository, String code, String name, String description) {
		if (!repository.existsByCode(code)) {
			repository.save(new PermissionEntity(code, name, description));
		}
	}
}
