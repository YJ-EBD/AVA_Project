package com.ava.backend.admin.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.admin.dto.AdminOverviewResponse;
import com.ava.backend.admin.dto.AdminUserResponse;
import com.ava.backend.admin.dto.AdminUserUpdateRequest;
import com.ava.backend.admin.service.AdminService;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.ops.dto.AppSettingResponse;
import com.ava.backend.ops.dto.AppSettingUpsertRequest;
import com.ava.backend.ops.dto.AuditLogResponse;
import com.ava.backend.ops.dto.SystemLogResponse;
import com.ava.backend.ops.service.AppSettingService;
import com.ava.backend.ops.service.AuditLogService;
import com.ava.backend.ops.service.SystemLogService;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/admin")
@PreAuthorize("hasAnyRole('ADMIN','SUPERUSER')")
public class AdminController {

	private final AdminService adminService;
	private final AppSettingService appSettingService;
	private final AuditLogService auditLogService;
	private final SystemLogService systemLogService;

	public AdminController(
		AdminService adminService,
		AppSettingService appSettingService,
		AuditLogService auditLogService,
		SystemLogService systemLogService
	) {
		this.adminService = adminService;
		this.appSettingService = appSettingService;
		this.auditLogService = auditLogService;
		this.systemLogService = systemLogService;
	}

	@GetMapping("/overview")
	public AdminOverviewResponse overview(@AuthenticationPrincipal AuthPrincipal principal) {
		return adminService.overview(principal);
	}

	@GetMapping("/users")
	public List<AdminUserResponse> users(@AuthenticationPrincipal AuthPrincipal principal) {
		return adminService.users(principal);
	}

	@GetMapping("/users/pending-approvals")
	public List<AdminUserResponse> pendingApprovals(@AuthenticationPrincipal AuthPrincipal principal) {
		return adminService.pendingApprovals(principal);
	}

	@PostMapping("/users/{userId}/approve")
	public AdminUserResponse approveUser(
		@PathVariable UUID userId,
		@AuthenticationPrincipal AuthPrincipal principal,
		HttpServletRequest request
	) {
		AdminUserResponse response = adminService.approveUser(userId, principal);
		auditLogService.record(
			principal,
			"admin.user.approve",
			"user",
			userId.toString(),
			"role=" + response.role() + ",enabled=" + response.enabled(),
			request
		);
		return response;
	}

	@PutMapping("/users/{userId}")
	public AdminUserResponse updateUser(
		@PathVariable UUID userId,
		@Valid @RequestBody AdminUserUpdateRequest requestBody,
		@AuthenticationPrincipal AuthPrincipal principal,
		HttpServletRequest request
	) {
		AdminUserResponse response = adminService.updateUser(userId, requestBody, principal);
		auditLogService.record(
			principal,
			"admin.user.update",
			"user",
			userId.toString(),
			"role=" + response.role() + ",enabled=" + response.enabled(),
			request
		);
		return response;
	}

	@GetMapping("/settings")
	public List<AppSettingResponse> settings() {
		return appSettingService.all();
	}

	@PutMapping("/settings")
	public AppSettingResponse upsertSetting(
		@Valid @RequestBody AppSettingUpsertRequest requestBody,
		@AuthenticationPrincipal AuthPrincipal principal,
		HttpServletRequest request
	) {
		AppSettingResponse response = appSettingService.upsert(requestBody, principal);
		auditLogService.record(
			principal,
			"admin.setting.upsert",
			"app_setting",
			response.key(),
			"key=" + response.key(),
			request
		);
		return response;
	}

	@GetMapping("/audit-logs")
	public List<AuditLogResponse> auditLogs() {
		return auditLogService.latest();
	}

	@GetMapping("/system-logs")
	public List<SystemLogResponse> systemLogs() {
		return systemLogService.latest();
	}
}
