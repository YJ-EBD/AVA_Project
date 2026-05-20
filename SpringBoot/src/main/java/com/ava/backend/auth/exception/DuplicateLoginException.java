package com.ava.backend.auth.exception;

public class DuplicateLoginException extends RuntimeException {

	public DuplicateLoginException(String message) {
		super(message);
	}
}
