package com.ava.backend.auth.security;

import java.io.IOException;
import java.util.List;

import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.ava.backend.auth.service.LoginSessionService;
import com.ava.backend.auth.service.TokenService;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

	private final TokenService tokenService;
	private final LoginSessionService loginSessionService;

	public JwtAuthenticationFilter(TokenService tokenService, LoginSessionService loginSessionService) {
		this.tokenService = tokenService;
		this.loginSessionService = loginSessionService;
	}

	@Override
	protected void doFilterInternal(
		HttpServletRequest request,
		HttpServletResponse response,
		FilterChain filterChain
	) throws ServletException, IOException {
		String header = request.getHeader(HttpHeaders.AUTHORIZATION);
		if (header != null && header.startsWith("Bearer ")) {
			tokenService.parse(header.substring(7))
				.filter(TokenService.TokenClaims::isAccessToken)
				.filter(claims -> loginSessionService.isCurrentSession(claims.userId(), claims.sessionId()))
				.ifPresent(claims -> {
					var principal = new AuthPrincipal(
						claims.userId(),
						claims.email(),
						claims.displayName(),
						claims.role(),
						claims.sessionId()
					);
					var authentication = new UsernamePasswordAuthenticationToken(
						principal,
						null,
						List.of(new SimpleGrantedAuthority("ROLE_" + claims.role().name()))
					);
					SecurityContextHolder.getContext().setAuthentication(authentication);
				});
		}
		filterChain.doFilter(request, response);
	}
}
