package com.ava.backend.admin.service;

import java.util.Comparator;
import java.util.List;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.access.AccessDeniedException;

import com.ava.backend.admin.dto.AdminOverviewResponse;
import com.ava.backend.admin.dto.AdminUserResponse;
import com.ava.backend.admin.dto.AdminUserUpdateRequest;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.chat.service.CompanyAllStaffChatService;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.notification.repository.NotificationRepository;
import com.ava.backend.notification.service.NotificationService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class AdminService {

	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final ChatRoomRepository chatRoomRepository;
	private final ChatMessageJpaRepository chatMessageRepository;
	private final NotificationRepository notificationRepository;
	private final NotificationService notificationService;
	private final CompanyScopeService companyScopeService;
	private final CompanyAllStaffChatService allStaffChatService;

	public AdminService(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		ChatRoomRepository chatRoomRepository,
		ChatMessageJpaRepository chatMessageRepository,
		NotificationRepository notificationRepository,
		NotificationService notificationService,
		CompanyScopeService companyScopeService,
		CompanyAllStaffChatService allStaffChatService
	) {
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.chatRoomRepository = chatRoomRepository;
		this.chatMessageRepository = chatMessageRepository;
		this.notificationRepository = notificationRepository;
		this.notificationService = notificationService;
		this.companyScopeService = companyScopeService;
		this.allStaffChatService = allStaffChatService;
	}

	@Transactional(readOnly = true)
	public AdminOverviewResponse overview(AuthPrincipal principal) {
		List<UserAccount> manageableAccounts = accountRepository.findAll().stream()
			.filter(account -> canManageAccount(principal, account))
			.toList();
		String companyName = companyScopeService.effectiveCompany(principal);
		List<String> roomCodes = chatRoomRepository.findAll().stream()
			.filter(room -> companyName.equalsIgnoreCase(companyScopeService.normalizeCompany(room.getCompanyName())))
			.map(room -> room.getCode())
			.toList();
		long totalUsers = manageableAccounts.size();
		long enabledUsers = manageableAccounts.stream().filter(UserAccount::isEnabled).count();
		return new AdminOverviewResponse(
			totalUsers,
			enabledUsers,
			totalUsers - enabledUsers,
			roomCodes.size(),
			roomCodes.isEmpty() ? 0 : chatMessageRepository.countByRoomCodeIn(roomCodes),
			notificationRepository.countByAccountIdAndReadAtIsNull(principal.userId())
		);
	}

	@Transactional(readOnly = true)
	public List<AdminUserResponse> users(AuthPrincipal actor) {
		return accountRepository.findAll().stream()
			.filter(account -> canManageAccount(actor, account))
			.sorted(Comparator.comparing(UserAccount::getCreatedAt).reversed())
			.map(this::toResponse)
			.toList();
	}

	@Transactional(readOnly = true)
	public List<AdminUserResponse> pendingApprovals(AuthPrincipal actor) {
		return users(actor).stream()
			.filter(user -> !user.enabled())
			.toList();
	}

	@Transactional
	public AdminUserResponse updateUser(UUID userId, AdminUserUpdateRequest request, AuthPrincipal actor) {
		UserAccount account = accountRepository.findById(userId)
			.orElseThrow(() -> new IllegalArgumentException("User not found."));
		requireCanManageAccount(actor, account);
		boolean selfUpdate = actor.userId().equals(account.getId());
		UserRole previousRole = account.getRole();
		boolean previousEnabled = account.isEnabled();
		String previousCompany = profileRepository.findByAccountId(account.getId())
			.map(UserProfile::getCompanyName)
			.map(companyScopeService::normalizeCompany)
			.orElse(CompanyScopeService.DEFAULT_COMPANY);
		if (request.displayName() != null && !request.displayName().isBlank()) {
			account.setDisplayName(limit(request.displayName(), 80));
		}
		if (!selfUpdate && request.role() != null) {
			if (actor.role() != UserRole.SUPERUSER && request.role() == UserRole.SUPERUSER) {
				throw new AccessDeniedException("Only superusers can grant SUPERUSER role.");
			}
			account.setRole(request.role());
		}
		if (!selfUpdate && request.enabled() != null) {
			account.setEnabled(request.enabled());
		}
		profileRepository.findByAccountId(account.getId()).ifPresent(profile -> {
			if (!selfUpdate && request.companyName() != null && !request.companyName().isBlank()) {
				profile.setCompanyName(limit(request.companyName(), 80));
			}
			if (request.department() != null && !request.department().isBlank()) {
				profile.setDepartment(limit(request.department(), 80));
			}
			if (request.position() != null && !request.position().isBlank()) {
				profile.setPosition(limit(request.position(), 80));
			}
		});
		if (previousRole != account.getRole()) {
			notificationService.notifyUser(
				account.getId(),
				"account.role_changed",
				"Role changed",
				"Your AVA role was changed to " + account.getRole().name() + ".",
				"user",
				account.getId().toString()
			);
		}
		if (previousEnabled != account.isEnabled()) {
			notificationService.notifyUser(
				account.getId(),
				"account.enabled_changed",
				"Account status changed",
				account.isEnabled() ? "Your AVA account was enabled." : "Your AVA account was disabled.",
				"user",
				account.getId().toString()
			);
		}
		String currentCompany = profileRepository.findByAccountId(account.getId())
			.map(UserProfile::getCompanyName)
			.map(companyScopeService::normalizeCompany)
			.orElse(previousCompany);
		allStaffChatService.syncApprovedMembers(previousCompany);
		if (!previousCompany.equalsIgnoreCase(currentCompany)) {
			allStaffChatService.syncApprovedMembers(currentCompany);
		}
		return toResponse(account);
	}

	@Transactional
	public AdminUserResponse approveUser(UUID userId, AuthPrincipal actor) {
		UserAccount account = accountRepository.findById(userId)
			.orElseThrow(() -> new IllegalArgumentException("User not found."));
		requireCanManageAccount(actor, account);
		if (!account.isEnabled()) {
			account.setEnabled(true);
			notificationService.notifyUser(
				account.getId(),
				"account.approved",
				"Account approved",
				"Your AVA account was approved.",
				"user",
				account.getId().toString()
			);
		}
		allStaffChatService.syncMembershipForAccount(account);
		return toResponse(account);
	}

	private boolean canManageAccount(AuthPrincipal actor, UserAccount account) {
		String actorCompany = companyScopeService.effectiveCompany(actor);
		String accountCompany = profileRepository.findByAccountId(account.getId())
			.map(UserProfile::getCompanyName)
			.orElse("");
		if (account.getRole() == UserRole.SUPERUSER) {
			return actor.userId().equals(account.getId())
				&& actorCompany.equalsIgnoreCase(companyScopeService.normalizeCompany(accountCompany));
		}
		if (actor.role() == UserRole.SUPERUSER) {
			return actorCompany.equalsIgnoreCase(companyScopeService.normalizeCompany(accountCompany));
		}
		return actorCompany.equalsIgnoreCase(companyScopeService.normalizeCompany(accountCompany));
	}

	private void requireCanManageAccount(AuthPrincipal actor, UserAccount account) {
		if (!canManageAccount(actor, account)) {
			throw new AccessDeniedException("You cannot manage users outside your company.");
		}
	}

	private AdminUserResponse toResponse(UserAccount account) {
		UserProfile profile = profileRepository.findByAccountId(account.getId()).orElse(null);
		return new AdminUserResponse(
			account.getId(),
			account.getEmail(),
			account.getDisplayName(),
			account.getRole(),
			account.isEnabled(),
			profile == null ? "" : profile.getCompanyName(),
			profile == null ? "" : profile.getDepartment(),
			profile == null ? "" : profile.getPosition(),
			profile == null ? "" : profile.getStatus(),
			account.getCreatedAt()
		);
	}

	private String limit(String value, int maxLength) {
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}
}
