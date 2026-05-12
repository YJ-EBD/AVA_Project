package com.ava.backend.auth.service;

import java.time.Instant;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.dto.AccountFindResponse;
import com.ava.backend.auth.dto.AuthResponse;
import com.ava.backend.auth.dto.LoginRequest;
import com.ava.backend.auth.dto.RefreshTokenRequest;
import com.ava.backend.auth.dto.SignupRequest;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.dao.UserAccountDao;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.mapper.UserMapper;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class AuthService {

	private static final String ONLINE = "\uC628\uB77C\uC778";
	private static final String OFFLINE = "\uC624\uD504\uB77C\uC778";

	private final UserAccountDao userAccountDao;
	private final UserProfileRepository profileRepository;
	private final PasswordEncoder passwordEncoder;
	private final LoginSessionService loginSessionService;
	private final TokenService tokenService;
	private final UserMapper userMapper;

	public AuthService(
		UserAccountDao userAccountDao,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		LoginSessionService loginSessionService,
		TokenService tokenService,
		UserMapper userMapper
	) {
		this.userAccountDao = userAccountDao;
		this.profileRepository = profileRepository;
		this.passwordEncoder = passwordEncoder;
		this.loginSessionService = loginSessionService;
		this.tokenService = tokenService;
		this.userMapper = userMapper;
	}

	@Transactional
	public AuthResponse signup(SignupRequest request) {
		String email = normalizeEmail(request.email());
		if (userAccountDao.existsByEmail(email)) {
			throw new IllegalArgumentException("이미 가입된 AVA 계정입니다.");
		}
		UserAccount account = new UserAccount(
			email,
			passwordEncoder.encode(request.password()),
			request.displayName().trim(),
			UserRole.USER
		);
		userAccountDao.save(account);
		UserProfile profile = profileRepository.save(new UserProfile(
			account,
			blankToDefault(request.department(), "미지정"),
			blankToDefault(request.nickname(), request.displayName().trim()),
			blankToNull(request.phoneNumber()),
			request.birthDate(),
			"온라인",
			"#7B61FF"
		));
		profile.setCompanyName("ABBA-S");
		profile.setPosition("사원");
		return issue(account, profile, false, true);
	}

	@Transactional
	public AuthResponse login(LoginRequest request) {
		UserAccount account = userAccountDao.findByEmail(normalizeEmail(request.email()))
			.filter(UserAccount::isEnabled)
			.orElseThrow(() -> new IllegalArgumentException("이메일 또는 비밀번호가 올바르지 않습니다."));
		if (!passwordEncoder.matches(request.password(), account.getPasswordHash())) {
			throw new IllegalArgumentException("이메일 또는 비밀번호가 올바르지 않습니다.");
		}
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseThrow(() -> new IllegalStateException("프로필 데이터가 없습니다."));
		return issue(account, profile, true, request.rememberMe() || request.autoLogin());
	}

	@Transactional
	public AuthResponse refresh(RefreshTokenRequest request) {
		var claims = tokenService.parse(request.refreshToken())
			.filter(TokenService.TokenClaims::isRefreshToken)
			.filter(token -> loginSessionService.isCurrentSession(token.userId(), token.sessionId()))
			.orElseThrow(() -> new IllegalArgumentException("갱신 토큰이 유효하지 않습니다."));
		UserAccount account = userAccountDao.findById(claims.userId())
			.orElseThrow(() -> new IllegalArgumentException("계정을 찾을 수 없습니다."));
		UserProfile profile = profileRepository.findByAccountId(account.getId())
			.orElseThrow(() -> new IllegalStateException("프로필 데이터가 없습니다."));
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

	private String normalizeEmail(String email) {
		return email.trim().toLowerCase();
	}

	private String blankToDefault(String value, String defaultValue) {
		return value == null || value.isBlank() ? defaultValue : value.trim();
	}

	private String blankToNull(String value) {
		return value == null || value.isBlank() ? null : value.trim();
	}

	private String maskEmail(String email) {
		int at = email.indexOf('@');
		if (at <= 2) {
			return "***" + email.substring(Math.max(at, 0));
		}
		return email.substring(0, 2) + "***" + email.substring(at);
	}
}
