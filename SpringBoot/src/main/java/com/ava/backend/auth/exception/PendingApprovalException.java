package com.ava.backend.auth.exception;

public class PendingApprovalException extends RuntimeException {

	public PendingApprovalException(String message) {
		super(message);
	}
}
