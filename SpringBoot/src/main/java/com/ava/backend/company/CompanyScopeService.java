package com.ava.backend.company;

import java.util.List;
import java.util.Locale;

import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class CompanyScopeService {

	public static final String DEFAULT_COMPANY = "ABBA-S";
	public static final String CADILLAC = "Cadillac";
	public static final String COMPANY_HEADER = "X-AVA-Company";
	public static final List<String> AVAILABLE_COMPANIES = List.of(DEFAULT_COMPANY, CADILLAC);

	private final UserProfileRepository profileRepository;

	public CompanyScopeService(UserProfileRepository profileRepository) {
		this.profileRepository = profileRepository;
	}

	public List<String> availableCompanies() {
		return AVAILABLE_COMPANIES;
	}

	public String effectiveCompany(AuthPrincipal principal) {
		String ownCompany = profileRepository.findByAccountId(principal.userId())
			.map(UserProfile::getCompanyName)
			.map(this::normalizeCompany)
			.orElse(DEFAULT_COMPANY);
		if (principal.role() != UserRole.SUPERUSER) {
			return ownCompany;
		}
		return requestedCompany()
			.map(this::normalizeCompany)
			.filter(this::isKnownCompany)
			.orElse(ownCompany);
	}

	public String normalizeCompany(String value) {
		if (value == null || value.isBlank()) {
			return DEFAULT_COMPANY;
		}
		String normalized = value.trim().replaceAll("\\s+", " ");
		if (DEFAULT_COMPANY.equalsIgnoreCase(normalized)) {
			return DEFAULT_COMPANY;
		}
		if (CADILLAC.equalsIgnoreCase(normalized) || "Cadillak".equalsIgnoreCase(normalized)) {
			return CADILLAC;
		}
		return DEFAULT_COMPANY;
	}

	public boolean isKnownCompany(String value) {
		String normalized = normalizeCompany(value).toLowerCase(Locale.ROOT);
		return AVAILABLE_COMPANIES.stream()
			.map(company -> company.toLowerCase(Locale.ROOT))
			.anyMatch(normalized::equals);
	}

	private java.util.Optional<String> requestedCompany() {
		if (RequestContextHolder.getRequestAttributes() instanceof ServletRequestAttributes attributes) {
			String header = attributes.getRequest().getHeader(COMPANY_HEADER);
			if (header != null && !header.isBlank()) {
				return java.util.Optional.of(header);
			}
		}
		return java.util.Optional.empty();
	}
}
