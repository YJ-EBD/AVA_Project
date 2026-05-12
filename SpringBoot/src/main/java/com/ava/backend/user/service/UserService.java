package com.ava.backend.user.service;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.dto.CompanyBlockRequest;
import com.ava.backend.user.dto.CompanyEmployeeRequest;
import com.ava.backend.user.dto.ProfileUpdateRequest;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.CompanyBlockedEmployee;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.mapper.UserMapper;
import com.ava.backend.user.repository.CompanyBlockedEmployeeRepository;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class UserService {

	private static final String ONLINE = "\uC628\uB77C\uC778";
	private static final String BACKGROUND = "\uBC31\uADF8\uB77C\uC6B4\uB4DC";
	private static final String OFFLINE = "\uC624\uD504\uB77C\uC778";
	private static final String DEFAULT_COMPANY = "ABBA-S";
	private static final String DEFAULT_DEPARTMENT = "\uBBF8\uC9C0\uC815";
	private static final String DEFAULT_POSITION = "\uC0AC\uC6D0";

	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final CompanyBlockedEmployeeRepository blockedEmployeeRepository;
	private final UserMapper userMapper;

	public UserService(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		CompanyBlockedEmployeeRepository blockedEmployeeRepository,
		UserMapper userMapper
	) {
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.blockedEmployeeRepository = blockedEmployeeRepository;
		this.userMapper = userMapper;
	}

	@Transactional(readOnly = true)
	public UserProfileResponse profile(UserAccount account) {
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseGet(() -> new UserProfile(account, "AVA", "온라인", "#7AA06A"));
		return userMapper.toResponse(account, profile);
	}

	@Transactional(readOnly = true)
	public List<UserProfileResponse> profiles(AuthPrincipal principal) {
		UserProfile currentProfile = profileEntity(principal.userId());
		String companyName = normalizeCompany(currentProfile.getCompanyName());
		return profileRepository.findAll().stream()
			.filter(profile -> companyName.equalsIgnoreCase(normalizeCompany(profile.getCompanyName())))
			.filter(profile -> !blockedEmployeeRepository.existsByCompanyNameIgnoreCaseAndTargetAccountId(
				companyName,
				profile.getAccount().getId()
			))
			.sorted(Comparator
				.comparing((UserProfile profile) -> isUnspecifiedDepartment(profile.getDepartment()))
				.thenComparing(UserProfile::getDepartment, Comparator.nullsLast(String::compareToIgnoreCase))
				.thenComparing(profile -> profile.getAccount().getDisplayName(), String.CASE_INSENSITIVE_ORDER)
				.thenComparing(profile -> profile.getAccount().getEmail(), String.CASE_INSENSITIVE_ORDER))
			.map(profile -> userMapper.toResponse(profile.getAccount(), profile))
			.toList();
	}

	@Transactional(readOnly = true)
	public List<UserProfileResponse> searchEmployees(
		AuthPrincipal principal,
		String name,
		String phoneNumber,
		String email
	) {
		UserProfile currentProfile = profileEntity(principal.userId());
		String companyName = normalizeCompany(currentProfile.getCompanyName());
		String normalizedName = normalizeText(name);
		String normalizedPhone = digitsOnly(phoneNumber);
		String normalizedEmail = normalizeEmail(email);

		List<UserProfile> matches = profileRepository.findAll().stream()
			.filter(profile -> {
				UserAccount account = profile.getAccount();
				boolean matchesName = normalizedName.isEmpty()
					|| normalizeText(account.getDisplayName()).contains(normalizedName)
					|| normalizeText(profile.getNickname()).contains(normalizedName);
				boolean matchesPhone = normalizedPhone.isEmpty()
					|| digitsOnly(profile.getPhoneNumber()).contains(normalizedPhone);
				boolean matchesEmail = normalizedEmail.isEmpty()
					|| account.getEmail().toLowerCase(Locale.ROOT).contains(normalizedEmail);
				return matchesName && matchesPhone && matchesEmail;
			})
			.sorted(Comparator
				.comparing((UserProfile profile) -> isUnspecifiedDepartment(profile.getDepartment()))
				.thenComparing(UserProfile::getDepartment, Comparator.nullsLast(String::compareToIgnoreCase))
				.thenComparing(profile -> profile.getAccount().getDisplayName(), String.CASE_INSENSITIVE_ORDER))
			.limit(20)
			.toList();
		Set<UUID> blockedIds = blockedEmployeeRepository
			.findByCompanyNameIgnoreCaseAndTargetAccountIdIn(
				companyName,
				matches.stream().map(profile -> profile.getAccount().getId()).toList()
			)
			.stream()
			.map(blocked -> blocked.getTargetAccount().getId())
			.collect(java.util.stream.Collectors.toSet());

		return matches.stream()
			.map(profile -> userMapper.toResponse(
				profile.getAccount(),
				profile,
				blockedIds.contains(profile.getAccount().getId())
			))
			.toList();
	}

	@Transactional
	public UserProfileResponse addCompanyEmployee(AuthPrincipal principal, CompanyEmployeeRequest request) {
		assertAdmin(principal);
		UserProfile currentProfile = profileEntity(principal.userId());
		String companyName = normalizeCompany(currentProfile.getCompanyName());
		UserAccount targetAccount = findTarget(request.targetUserId(), request.email(), request.name(), request.phoneNumber());
		UserProfile targetProfile = profileEntity(targetAccount.getId());
		targetProfile.setCompanyName(companyName);
		if (isBlank(targetProfile.getDepartment())) {
			targetProfile.setDepartment(DEFAULT_DEPARTMENT);
		}
		if (isBlank(targetProfile.getPosition())) {
			targetProfile.setPosition(DEFAULT_POSITION);
		}
		blockedEmployeeRepository.deleteByCompanyNameIgnoreCaseAndTargetAccountId(companyName, targetAccount.getId());
		return userMapper.toResponse(targetAccount, targetProfile);
	}

	@Transactional
	public UserProfileResponse blockEmployee(AuthPrincipal principal, CompanyBlockRequest request) {
		assertAdmin(principal);
		UserProfile currentProfile = profileEntity(principal.userId());
		String companyName = normalizeCompany(currentProfile.getCompanyName());
		UserAccount currentAccount = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("\uACC4\uC815\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
		UserAccount targetAccount = findTarget(request.targetUserId(), request.email(), null, null);
		UserProfile targetProfile = profileEntity(targetAccount.getId());
		if (!blockedEmployeeRepository.existsByCompanyNameIgnoreCaseAndTargetAccountId(companyName, targetAccount.getId())) {
			blockedEmployeeRepository.save(new CompanyBlockedEmployee(companyName, targetAccount, currentAccount));
		}
		return userMapper.toResponse(targetAccount, targetProfile, true);
	}

	@Transactional
	public UserProfileResponse unblockEmployee(AuthPrincipal principal, CompanyBlockRequest request) {
		assertAdmin(principal);
		UserProfile currentProfile = profileEntity(principal.userId());
		String companyName = normalizeCompany(currentProfile.getCompanyName());
		UserAccount targetAccount = findTarget(request.targetUserId(), request.email(), null, null);
		UserProfile targetProfile = profileEntity(targetAccount.getId());
		blockedEmployeeRepository.deleteByCompanyNameIgnoreCaseAndTargetAccountId(companyName, targetAccount.getId());
		return userMapper.toResponse(targetAccount, targetProfile, false);
	}

	@Transactional(readOnly = true)
	public UserProfile profileEntity(UUID accountId) {
		return profileRepository.findByAccountId(accountId)
			.orElseThrow(() -> new IllegalArgumentException("프로필을 찾을 수 없습니다."));
	}

	@Transactional
	public UserProfileResponse updatePresence(UUID accountId, String requestedStatus) {
		UserProfile profile = profileEntity(accountId);
		profile.setStatus(normalizePresence(requestedStatus));
		profile.setPresenceUpdatedAt(Instant.now());
		return userMapper.toResponse(profile.getAccount(), profile);
	}

	@Transactional
	public UserProfileResponse updateProfile(UUID accountId, ProfileUpdateRequest request) {
		UserProfile profile = profileEntity(accountId);
		if (request.nickname() != null) {
			profile.setNickname(trimToLimit(request.nickname(), 20));
		}
		if (request.statusMessage() != null) {
			profile.setStatusMessage(trimToLimit(request.statusMessage(), 60));
		}
		if (request.avatarImageUrl() != null) {
			profile.setAvatarImageUrl(normalizeAvatarImageUrl(request.avatarImageUrl()));
		}
		if (request.profileBackgroundImageUrl() != null) {
			profile.setProfileBackgroundImageUrl(normalizeAvatarImageUrl(request.profileBackgroundImageUrl()));
		}
		if (request.profileBackgroundColor() != null) {
			String color = request.profileBackgroundColor().trim();
			if (color.matches("#[0-9a-fA-F]{6}")) {
				profile.setProfileBackgroundColor(color.toUpperCase());
				profile.setProfileBackgroundImageUrl(null);
			}
		}
		return userMapper.toResponse(profile.getAccount(), profile);
	}

	@Transactional
	public void markOffline(UUID accountId) {
		profileRepository.findByAccountId(accountId).ifPresent(profile -> {
			profile.setStatus(OFFLINE);
			profile.setPresenceUpdatedAt(Instant.now());
		});
	}

	private String normalizePresence(String status) {
		if (ONLINE.equals(status) || BACKGROUND.equals(status) || OFFLINE.equals(status)) {
			return status;
		}
		return OFFLINE;
	}

	private String trimToLimit(String value, int maxLength) {
		String trimmed = value.trim();
		return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
	}

	private String normalizeAvatarImageUrl(String value) {
		String trimmed = value.trim();
		if (trimmed.isEmpty()) {
			return null;
		}
		if (trimmed.length() > 1_500_000) {
			throw new IllegalArgumentException("Profile image is too large.");
		}
		if (trimmed.startsWith("data:image/") || trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
			return trimmed;
		}
		throw new IllegalArgumentException("Unsupported profile image format.");
	}

	private void assertAdmin(AuthPrincipal principal) {
		if (principal.role() != UserRole.ADMIN) {
			throw new IllegalArgumentException("\uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.");
		}
	}

	private UserAccount findTarget(String targetUserId, String email, String name, String phoneNumber) {
		if (!isBlank(targetUserId)) {
			UUID id = UUID.fromString(targetUserId.trim());
			return accountRepository.findById(id)
				.orElseThrow(() -> new IllegalArgumentException("\uC9C1\uC6D0\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
		}
		if (!isBlank(email)) {
			return accountRepository.findByEmailIgnoreCase(email.trim())
				.orElseThrow(() -> new IllegalArgumentException("\uC9C1\uC6D0\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
		}
		String normalizedName = normalizeText(name);
		String normalizedPhone = digitsOnly(phoneNumber);
		return profileRepository.findAll().stream()
			.filter(profile -> normalizedName.isEmpty()
				|| normalizeText(profile.getAccount().getDisplayName()).equals(normalizedName)
				|| normalizeText(profile.getNickname()).equals(normalizedName))
			.filter(profile -> normalizedPhone.isEmpty() || digitsOnly(profile.getPhoneNumber()).equals(normalizedPhone))
			.map(UserProfile::getAccount)
			.findFirst()
			.orElseThrow(() -> new IllegalArgumentException("\uC9C1\uC6D0\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
	}

	private String normalizeCompany(String value) {
		return isBlank(value) ? DEFAULT_COMPANY : value.trim();
	}

	private static boolean isUnspecifiedDepartment(String value) {
		return value == null || value.isBlank() || "\uBBF8\uC9C0\uC815".equals(value.trim());
	}

	private String normalizeEmail(String value) {
		return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
	}

	private String normalizeText(String value) {
		return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
	}

	private String digitsOnly(String value) {
		return value == null ? "" : value.replaceAll("[^0-9]", "");
	}

	private boolean isBlank(String value) {
		return value == null || value.isBlank();
	}
}
