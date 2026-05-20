package com.ava.backend.auth.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.dto.AccountFindResponse;
import com.ava.backend.auth.dto.AuthResponse;
import com.ava.backend.auth.dto.AuthSessionStatusResponse;
import com.ava.backend.auth.dto.EmailVerificationConfirmRequest;
import com.ava.backend.auth.dto.EmailVerificationConfirmResponse;
import com.ava.backend.auth.dto.EmailVerificationRequest;
import com.ava.backend.auth.dto.EmailVerificationResponse;
import com.ava.backend.auth.dto.LoginRequest;
import com.ava.backend.auth.dto.RefreshTokenRequest;
import com.ava.backend.auth.dto.SignupRequest;
import com.ava.backend.auth.dto.SignupResponse;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.auth.service.EmailVerificationService;
import com.ava.backend.auth.service.AuthService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

	private final AuthService authService;
	private final EmailVerificationService emailVerificationService;

	public AuthController(AuthService authService, EmailVerificationService emailVerificationService) {
		this.authService = authService;
		this.emailVerificationService = emailVerificationService;
	}

	@PostMapping("/signup")
	public SignupResponse signup(@Valid @RequestBody SignupRequest request) {
		return authService.signup(request);
	}

	@PostMapping("/email-verifications")
	public EmailVerificationResponse sendEmailVerification(@Valid @RequestBody EmailVerificationRequest request) {
		return emailVerificationService.sendCode(request);
	}

	@PostMapping("/email-verifications/confirm")
	public EmailVerificationConfirmResponse confirmEmailVerification(
		@Valid @RequestBody EmailVerificationConfirmRequest request
	) {
		return emailVerificationService.confirm(request);
	}

	@PostMapping("/login")
	public AuthResponse login(@Valid @RequestBody LoginRequest request) {
		return authService.login(request);
	}

	@PostMapping("/refresh")
	public AuthResponse refresh(@Valid @RequestBody RefreshTokenRequest request) {
		return authService.refresh(request);
	}

	@PostMapping("/logout")
	public ResponseEntity<Map<String, String>> logout(@AuthenticationPrincipal AuthPrincipal principal) {
		authService.logout(principal);
		return ResponseEntity.ok(Map.of("status", "logged_out"));
	}

	@GetMapping("/session")
	public AuthSessionStatusResponse session(@AuthenticationPrincipal AuthPrincipal principal) {
		return new AuthSessionStatusResponse(principal != null);
	}

	@GetMapping("/find-account")
	public AccountFindResponse findAccount(@RequestParam String email) {
		return authService.findAccount(email);
	}
}
