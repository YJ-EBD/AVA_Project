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
import com.ava.backend.auth.dto.LoginRequest;
import com.ava.backend.auth.dto.RefreshTokenRequest;
import com.ava.backend.auth.dto.SignupRequest;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.auth.service.AuthService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

	private final AuthService authService;

	public AuthController(AuthService authService) {
		this.authService = authService;
	}

	@PostMapping("/signup")
	public AuthResponse signup(@Valid @RequestBody SignupRequest request) {
		return authService.signup(request);
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

	@GetMapping("/find-account")
	public AccountFindResponse findAccount(@RequestParam String email) {
		return authService.findAccount(email);
	}
}
