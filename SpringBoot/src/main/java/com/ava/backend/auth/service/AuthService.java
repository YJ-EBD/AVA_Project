package com.ava.backend.auth.service;

import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.dto.AccountFindResponse;
import com.ava.backend.auth.dto.AuthRealtimeEvent;
import com.ava.backend.auth.dto.AuthResponse;
import com.ava.backend.auth.dto.LoginRequest;
import com.ava.backend.auth.dto.PasswordVerificationRequest;
import com.ava.backend.auth.dto.RefreshTokenRequest;
import com.ava.backend.auth.dto.SignupRequest;
import com.ava.backend.auth.dto.SignupResponse;
import com.ava.backend.auth.exception.DuplicateLoginException;
import com.ava.backend.auth.exception.PendingApprovalException;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.dao.UserAccountDao;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.mapper.UserMapper;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class AuthService {

	private static final Logger log = LoggerFactory.getLogger(AuthService.class);
	private static final String ONLINE = "\uC628\uB77C\uC778";
	private static final String OFFLINE = "\uC624\uD504\uB77C\uC778";
	private static final String DUPLICATE_LOGIN_MESSAGE = "\uB2E4\uB978 \uAE30\uAE30\uC5D0\uC11C \uB85C\uADF8\uC778 \uC911\uC785\uB2C8\uB2E4.";
	private static final String PENDING_APPROVAL_MESSAGE = "\uAD00\uB9AC\uC790 \uC2B9\uC778 \uD6C4 \uB85C\uADF8\uC778 \uAC00\uB2A5\uD569\uB2C8\uB2E4.";
	private static final String FORCED_LOGOUT_MESSAGE =
		"\uB2E4\uB978 \uAE30\uAE30\uC5D0\uC11C \uB85C\uADF8\uC778\uD574 \uB85C\uADF8\uC544\uC6C3\uB418\uC5C8\uC2B5\uB2C8\uB2E4.";

	private final UserAccountDao userAccountDao;
	private final UserProfileRepository profileRepository;
	private final PasswordEncoder passwordEncoder;
	private final LoginSessionService loginSessionService;
	private final TokenService tokenService;
	private final UserMapper userMapper;
	private final SimpMessagingTemplate messagingTemplate;
	private final EmailVerificationService emailVerificationService;
	private final CompanyScopeService companyScopeService;

	public AuthService(
		UserAccountDao userAccountDao,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		LoginSessionService loginSessionService,
		TokenService tokenService,
		UserMapper userMapper,
		SimpMessagingTemplate messagingTemplate,
		EmailVerificationService emailVerificationService,
		CompanyScopeService companyScopeService
	) {
		this.userAccountDao = userAccountDao;
		this.profileRepository = profileRepository;
		this.passwordEncoder = passwordEncoder;
		this.loginSessionService = loginSessionService;
		this.tokenService = tokenService;
		this.userMapper = userMapper;
		this.messagingTemplate = messagingTemplate;
		this.emailVerificationService = emailVerificationService;
		this.companyScopeService = companyScopeService;
	}

	@Transactional
	public SignupResponse signup(SignupRequest request) {
		String email = normalizeEmail(request.email());
		if (userAccountDao.existsByEmail(email)) {
			throw new IllegalArgumentException("\uC774\uBBF8 \uAC00\uC785\uB41C AVA \uACC4\uC815\uC785\uB2C8\uB2E4.");
		}
		emailVerificationService.verifyAndConsume(request.contactEmail(), request.emailVerificationCode());
		UserAccount account = new UserAccount(
			email,
			passwordEncoder.encode(request.password()),
			request.displayName().trim(),
			UserRole.USER
		);
		account.setEnabled(false);
		userAccountDao.save(account);
		UserProfile profile = profileRepository.save(new UserProfile(
			account,
			blankToDefault(request.department(), "\uBBF8\uC9C0\uC815"),
			blankToDefault(request.nickname(), request.displayName().trim()),
			blankToNull(request.phoneNumber()),
			request.birthDate(),
			OFFLINE,
			"#7B61FF"
		));
		profile.setCompanyName(normalizeCompanyName(request.companyName()));
		profile.setContactEmail(blankToNull(request.contactEmail()));
		profile.setGender(blankToNull(request.gender()));
		profile.setPosition("\uC0AC\uC6D0");
		return new SignupResponse(
			userMapper.toResponse(account, profile),
			true,
			PENDING_APPROVAL_MESSAGE
		);
	}

	@Transactional
	public AuthResponse login(LoginRequest request) {
		UserAccount account = userAccountDao.findByEmail(normalizeEmail(request.email()))
			.orElseThrow(() -> new IllegalArgumentException("\uC774\uBA54\uC77C \uB610\uB294 \uBE44\uBC00\uBC88\uD638\uAC00 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4."));
		if (!passwordEncoder.matches(request.password(), account.getPasswordHash())) {
			throw new IllegalArgumentException("\uC774\uBA54\uC77C \uB610\uB294 \uBE44\uBC00\uBC88\uD638\uAC00 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.");
		}
		if (!account.isEnabled()) {
			throw new PendingApprovalException(PENDING_APPROVAL_MESSAGE);
		}
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseThrow(() -> new IllegalStateException("\uD504\uB85C\uD544 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4."));
		boolean hasActiveSession = loginSessionService.hasActiveSession(account.getId());
		if (hasActiveSession && !request.forceLogin()) {
			throw new DuplicateLoginException(DUPLICATE_LOGIN_MESSAGE);
		}
		if (hasActiveSession) {
			publishForcedLogout(account);
		}
		return issue(account, profile, true, request.rememberMe() || request.autoLogin());
	}

	@Transactional
	public AuthResponse refresh(RefreshTokenRequest request) {
		var claims = tokenService.parse(request.refreshToken())
			.filter(TokenService.TokenClaims::isRefreshToken)
			.filter(token -> loginSessionService.isCurrentSession(token.userId(), token.sessionId()))
			.orElseThrow(() -> new IllegalArgumentException("\uAC31\uC2E0 \uD1A0\uD070\uC774 \uC720\uD6A8\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4."));
		UserAccount account = userAccountDao.findById(claims.userId())
			.orElseThrow(() -> new IllegalArgumentException("\uACC4\uC815\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseThrow(() -> new IllegalStateException("\uD504\uB85C\uD544 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4."));
		var tokens = tokenService.issue(account, claims.sessionId());
		return new AuthResponse(
			tokens.accessToken(),
			tokens.refreshToken(),
			"Bearer",
			tokens.expiresInSeconds(),
			false,
			userMapper.toResponse(account, profile)
		);
	}

	@Transactional
	public void logout(AuthPrincipal principal) {
		profileRepository.findByAccountId(principal.userId()).ifPresent(profile -> {
			profile.setStatus(OFFLINE);
			profile.setPresenceUpdatedAt(Instant.now());
		});
		loginSessionService.invalidate(principal.userId());
	}

	@Transactional(readOnly = true)
	public AccountFindResponse findAccount(String email) {
		boolean found = userAccountDao.existsByEmail(normalizeEmail(email));
		return new AccountFindResponse(found, found ? maskEmail(email) : "");
	}

	@Transactional(readOnly = true)
	public void verifyPassword(AuthPrincipal principal, PasswordVerificationRequest request) {
		UserAccount account = userAccountDao.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("\uACC4\uC815\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."));
		if (!passwordEncoder.matches(request.password(), account.getPasswordHash())) {
			throw new IllegalArgumentException("\uBE44\uBC00\uBC88\uD638\uAC00 \uC62C\uBC14\uB974\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.");
		}
	}

	private AuthResponse issue(UserAccount account, UserProfile profile, boolean canReplacePrevious, boolean rememberLogin) {
		profile.setStatus(ONLINE);
		profile.setPresenceUpdatedAt(Instant.now());
		var session = loginSessionService.register(account.getId(), rememberLogin);
		var tokens = tokenService.issue(account, session.sessionId());
		return new AuthResponse(
			tokens.accessToken(),
			tokens.refreshToken(),
			"Bearer",
			tokens.expiresInSeconds(),
			canReplacePrevious && session.replacedPreviousLogin(),
			userMapper.toResponse(account, profile)
		);
	}

	private void publishForcedLogout(UserAccount account) {
		try {
			messagingTemplate.convertAndSendToUser(
				account.getEmail(),
				"/queue/auth-events",
				new AuthRealtimeEvent(
					"forced_logout",
					"duplicate_login",
					FORCED_LOGOUT_MESSAGE,
					Instant.now()
				)
			);
		} catch (RuntimeException exception) {
			log.warn("Forced-logout notification failed for user {}.", account.getId(), exception);
		}
	}

	private String normalizeEmail(String email) {
		return email.trim().toLowerCase();
	}

	private String blankToDefault(String value, String defaultValue) {
		return value == null || value.isBlank() ? defaultValue : value.trim();
	}

	private String blankToNull(String value) {
		return value == null || value.isBlank() ? null : value.trim();
	}

	private String normalizeCompanyName(String companyName) {
		String normalized = companyScopeService.normalizeCompany(companyName);
		if (companyScopeService.isKnownCompany(normalized)) {
			return normalized;
		}
		throw new IllegalArgumentException("\uC120\uD0DD\uD560 \uC218 \uC5C6\uB294 \uD68C\uC0AC\uC785\uB2C8\uB2E4.");
	}

	private String maskEmail(String email) {
		int at = email.indexOf('@');
		if (at <= 2) {
			return "***" + email.substring(Math.max(at, 0));
		}
		return email.substring(0, 2) + "***" + email.substring(at);
	}
}
