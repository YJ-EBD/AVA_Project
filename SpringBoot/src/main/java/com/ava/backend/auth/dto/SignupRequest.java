package com.ava.backend.auth.dto;

import java.time.LocalDate;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record SignupRequest(
	@NotBlank @Email String email,
	@NotBlank @Size(min = 8, max = 80) String password,
	@NotBlank @Size(max = 80) String displayName,
	@Size(max = 80) String companyName,
	@Size(max = 80) String nickname,
	@Size(max = 40) String phoneNumber,
	@NotBlank @Email @Size(max = 120) String contactEmail,
	@NotBlank @Size(max = 12) String emailVerificationCode,
	@Size(max = 20) String gender,
	@Size(max = 80) String department,
	LocalDate birthDate
) {
}
