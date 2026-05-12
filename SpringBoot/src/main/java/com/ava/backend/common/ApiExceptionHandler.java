package com.ava.backend.common;

import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {

	@ExceptionHandler({IllegalArgumentException.class, IllegalStateException.class})
	public ResponseEntity<Map<String, String>> handleBadRequest(RuntimeException exception) {
		return ResponseEntity.badRequest().body(Map.of("message", exception.getMessage()));
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	public ResponseEntity<Map<String, String>> handleValidation(MethodArgumentNotValidException exception) {
		String message = exception.getBindingResult().getFieldErrors().stream()
			.findFirst()
			.map(error -> error.getField() + ": " + error.getDefaultMessage())
			.orElse("요청 값이 올바르지 않습니다.");
		return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("message", message));
	}
}
