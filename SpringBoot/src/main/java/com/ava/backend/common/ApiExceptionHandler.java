package com.ava.backend.common;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.ava.backend.auth.exception.DuplicateLoginException;
import com.ava.backend.auth.exception.PendingApprovalException;

import jakarta.servlet.http.HttpServletRequest;

@RestControllerAdvice
public class ApiExceptionHandler {

	@ExceptionHandler(DuplicateLoginException.class)
	public ResponseEntity<ApiErrorResponse> handleDuplicateLogin(
		DuplicateLoginException exception,
		HttpServletRequest request
	) {
		return ResponseEntity.status(HttpStatus.CONFLICT).body(ApiErrorResponse.of(
			HttpStatus.CONFLICT.value(),
			"DUPLICATE_LOGIN",
			exception.getMessage(),
			request.getRequestURI()
		));
	}

	@ExceptionHandler(PendingApprovalException.class)
	public ResponseEntity<ApiErrorResponse> handlePendingApproval(
		PendingApprovalException exception,
		HttpServletRequest request
	) {
		return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ApiErrorResponse.of(
			HttpStatus.FORBIDDEN.value(),
			"PENDING_APPROVAL",
			exception.getMessage(),
			request.getRequestURI()
		));
	}

	@ExceptionHandler({IllegalArgumentException.class, IllegalStateException.class})
	public ResponseEntity<ApiErrorResponse> handleBadRequest(RuntimeException exception, HttpServletRequest request) {
		return ResponseEntity.badRequest().body(ApiErrorResponse.of(
			HttpStatus.BAD_REQUEST.value(),
			"BAD_REQUEST",
			exception.getMessage(),
			request.getRequestURI()
		));
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	public ResponseEntity<ApiErrorResponse> handleValidation(
		MethodArgumentNotValidException exception,
		HttpServletRequest request
	) {
		String message = exception.getBindingResult().getFieldErrors().stream()
			.findFirst()
			.map(error -> error.getField() + ": " + error.getDefaultMessage())
			.orElse("Request validation failed.");
		Map<String, Object> details = new LinkedHashMap<>();
		exception.getBindingResult().getFieldErrors().forEach(error ->
			details.put(error.getField(), error.getDefaultMessage())
		);
		return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ApiErrorResponse.of(
			HttpStatus.BAD_REQUEST.value(),
			"VALIDATION_FAILED",
			message,
			request.getRequestURI(),
			details
		));
	}

	@ExceptionHandler(AccessDeniedException.class)
	public ResponseEntity<ApiErrorResponse> handleAccessDenied(
		AccessDeniedException exception,
		HttpServletRequest request
	) {
		return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ApiErrorResponse.of(
			HttpStatus.FORBIDDEN.value(),
			"FORBIDDEN",
			"Access denied.",
			request.getRequestURI()
		));
	}

	@ExceptionHandler(AuthenticationException.class)
	public ResponseEntity<ApiErrorResponse> handleAuthentication(
		AuthenticationException exception,
		HttpServletRequest request
	) {
		return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ApiErrorResponse.of(
			HttpStatus.UNAUTHORIZED.value(),
			"UNAUTHORIZED",
			"Authentication is required.",
			request.getRequestURI()
		));
	}

	@ExceptionHandler(Exception.class)
	public ResponseEntity<ApiErrorResponse> handleUnexpected(Exception exception, HttpServletRequest request) {
		return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ApiErrorResponse.of(
			HttpStatus.INTERNAL_SERVER_ERROR.value(),
			"INTERNAL_ERROR",
			"Unexpected server error.",
			request.getRequestURI()
		));
	}
}
