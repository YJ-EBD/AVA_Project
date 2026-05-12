package com.ava.backend.auth.dto;

public record AccountFindResponse(boolean found, String maskedEmail) {
}
