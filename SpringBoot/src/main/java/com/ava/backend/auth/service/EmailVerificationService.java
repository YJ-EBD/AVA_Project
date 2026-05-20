package com.ava.backend.auth.service;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.auth.dto.EmailVerificationConfirmRequest;
import com.ava.backend.auth.dto.EmailVerificationConfirmResponse;
import com.ava.backend.auth.dto.EmailVerificationRequest;
import com.ava.backend.auth.dto.EmailVerificationResponse;
import com.ava.backend.auth.entity.EmailVerificationCodeEntity;
import com.ava.backend.auth.repository.EmailVerificationCodeRepository;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;

@Service
public class EmailVerificationService {

	private static final SecureRandom RANDOM = new SecureRandom();

	private final EmailVerificationCodeRepository repository;
	private final JavaMailSender mailSender;
	private final PasswordEncoder passwordEncoder;
	private final Duration codeTtl;
	private final int maxAttempts;
	private final String fromAddress;
	private final String smtpUsername;
	private final String brandName;
	private final String productName;

	public EmailVerificationService(
		EmailVerificationCodeRepository repository,
		JavaMailSender mailSender,
		PasswordEncoder passwordEncoder,
		@Value("${ava.auth.email-verification.code-minutes:5}") long codeMinutes,
		@Value("${ava.auth.email-verification.max-attempts:5}") int maxAttempts,
		@Value("${ava.auth.email-verification.from:}") String fromAddress,
		@Value("${spring.mail.username:}") String smtpUsername,
		@Value("${ava.auth.email-verification.brand-name:ABBA-S}") String brandName,
		@Value("${ava.auth.email-verification.product-name:AVA}") String productName
	) {
		this.repository = repository;
		this.mailSender = mailSender;
		this.passwordEncoder = passwordEncoder;
		this.codeTtl = Duration.ofMinutes(Math.max(1, codeMinutes));
		this.maxAttempts = Math.max(1, maxAttempts);
		this.smtpUsername = clean(smtpUsername);
		this.fromAddress = resolveFromAddress(clean(fromAddress), this.smtpUsername);
		this.brandName = defaultText(brandName, "ABBA-S");
		this.productName = defaultText(productName, "AVA");
	}

	@Transactional
	public EmailVerificationResponse sendCode(EmailVerificationRequest request) {
		String email = normalizeEmail(request.email());
		if (smtpUsername.isBlank() || fromAddress.isBlank()) {
			throw new IllegalStateException("SMTP 설정이 없습니다.");
		}
		Instant now = Instant.now();
		repository.deleteByExpiresAtBefore(now);

		String code = code();
		EmailVerificationCodeEntity saved = repository.save(new EmailVerificationCodeEntity(
			email,
			passwordEncoder.encode(code),
			now,
			now.plus(codeTtl)
		));
		send(email, code);
		return new EmailVerificationResponse(saved.getEmail(), codeTtl.toSeconds());
	}

	@Transactional
	public EmailVerificationConfirmResponse confirm(EmailVerificationConfirmRequest request) {
		verify(request.email(), request.code(), false);
		return new EmailVerificationConfirmResponse(normalizeEmail(request.email()), true);
	}

	@Transactional
	public void verifyAndConsume(String email, String code) {
		verify(email, code, true);
	}

	private void verify(String email, String code, boolean consume) {
		String normalizedEmail = normalizeEmail(email);
		String normalizedCode = normalizeCode(code);
		Instant now = Instant.now();
		EmailVerificationCodeEntity verification = repository
			.findFirstByEmailIgnoreCaseAndConsumedAtIsNullOrderByCreatedAtDesc(normalizedEmail)
			.orElseThrow(() -> new IllegalArgumentException("이메일 인증번호를 먼저 받아주세요."));
		if (verification.isConsumed()) {
			throw new IllegalArgumentException("이미 사용된 이메일 인증번호입니다.");
		}
		if (verification.isExpired(now)) {
			throw new IllegalArgumentException("이메일 인증번호가 만료되었습니다.");
		}
		if (verification.getAttempts() >= maxAttempts) {
			throw new IllegalArgumentException("이메일 인증번호 입력 횟수를 초과했습니다.");
		}
		verification.markAttempt();
		if (!passwordEncoder.matches(normalizedCode, verification.getCodeHash())) {
			throw new IllegalArgumentException("이메일 인증번호가 올바르지 않습니다.");
		}
		verification.markVerified(now);
		if (consume) {
			verification.markConsumed(now);
		}
	}

	private void send(String to, String code) {
		try {
			MimeMessage message = mailSender.createMimeMessage();
			MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
			helper.setSubject("[ " + brandName + " ] 이메일 인증 코드");
			helper.setFrom(fromAddress);
			helper.setTo(to);
			helper.setText(
				buildVerificationPlainText(brandName, code, (int) codeTtl.toMinutes()),
				buildVerificationHtml(brandName, productName, to, code, (int) codeTtl.toMinutes())
			);
			mailSender.send(message);
		} catch (MessagingException | MailException error) {
			throw new IllegalStateException("이메일 인증번호 발송에 실패했습니다.", error);
		}
	}

	private String buildVerificationPlainText(String brandName, String code, int expiresMinutes) {
		return """
			%s 회원가입 이메일 인증 코드입니다.

			인증 코드: %s
			유효 시간: %d분

			회원가입 화면으로 돌아가 위 코드를 입력해주세요.
			본인이 요청하지 않았다면 본 메일을 무시해주세요.
			""".formatted(brandName, code, expiresMinutes);
	}

	private String buildVerificationHtml(
		String brandName,
		String productName,
		String toEmail,
		String code,
		int expiresMinutes
	) {
		String safeBrandName = htmlEscape(brandName);
		String safeProductName = htmlEscape(productName);
		String safeEmail = htmlEscape(clean(toEmail));
		String safeCode = htmlEscape(clean(code));
		String codeDisplay = code.matches("\\d{6}") ? code.substring(0, 3) + " " + code.substring(3) : safeCode;

		return """
			<!doctype html>
			<html lang="ko">
			  <head>
			    <meta charset="utf-8">
			    <meta name="viewport" content="width=device-width, initial-scale=1.0">
			    <title>%s 이메일 인증</title>
			  </head>
			  <body style="margin:0;padding:0;background-color:#edf3fb;font-family:'Apple SD Gothic Neo','Malgun Gothic','Noto Sans KR',Arial,sans-serif;color:#182544;">
			    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">
			      %s 이메일 인증 코드 %s
			    </div>
			    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%%" style="width:100%%;background-color:#edf3fb;margin:0;padding:28px 0;">
			      <tr>
			        <td align="center" style="padding:0 16px;">
			          <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%%" style="max-width:640px;">
			            <tr>
			              <td style="background-color:#1c53de;background-image:linear-gradient(145deg,#2d6fff 0%%,#1c53de 52%%,#123eae 100%%);border-radius:28px 28px 0 0;padding:38px 40px 30px;color:#ffffff;">
			                <div style="font-size:12px;line-height:1.2;font-weight:800;letter-spacing:0.16em;color:rgba(233,240,255,0.76);">EMAIL VERIFICATION</div>
			                <div style="margin-top:14px;font-size:30px;line-height:1.3;font-weight:800;letter-spacing:-0.03em;">
			                  회원가입을 계속하려면<br>이메일 인증을 완료해주세요.
			                </div>
			                <div style="margin-top:14px;font-size:15px;line-height:1.8;color:rgba(233,240,255,0.86);">
			                  %s 계정 생성 요청이 접수되었습니다.
			                  아래 인증 코드를 입력하면 회원가입을 계속 진행할 수 있습니다.
			                </div>
			              </td>
			            </tr>
			            <tr>
			              <td style="background-color:#ffffff;border-radius:0 0 28px 28px;padding:34px 40px 40px;box-shadow:0 22px 50px rgba(20,48,105,0.14);">
			                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%%" style="width:100%%;border:1px solid #d7e1f2;border-radius:22px;background-color:#f8fbff;">
			                  <tr>
			                    <td style="padding:26px 26px 24px;">
			                      <div style="font-size:12px;line-height:1.2;font-weight:800;letter-spacing:0.14em;color:#7f8fad;">인증 코드</div>
			                      <div style="margin-top:14px;padding:20px 22px;border-radius:18px;border:1px solid #cfd9eb;background-color:#ffffff;font-size:34px;line-height:1.1;font-weight:800;letter-spacing:0.18em;color:#1846c7;text-align:center;">
			                        %s
			                      </div>
			                      <div style="margin-top:16px;font-size:14px;line-height:1.8;color:#62728f;">
			                        요청 이메일:
			                        <strong style="color:#1d2b49;">%s</strong>
			                        <br>
			                        유효 시간:
			                        <strong style="color:#1d2b49;">%d분</strong>
			                      </div>
			                    </td>
			                  </tr>
			                </table>

			                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%%" style="width:100%%;margin-top:18px;border-collapse:separate;">
			                  <tr>
			                    <td style="padding:18px 20px;border-radius:18px;background-color:#f4f8ff;border:1px solid #e2ebf8;font-size:14px;line-height:1.8;color:#5f6f8d;">
			                      <strong style="display:block;margin-bottom:6px;color:#182544;">안내</strong>
			                      이 코드는 회원가입 화면에서만 입력해주세요.<br>
			                      본인이 요청하지 않았다면 이 메일을 무시하셔도 안전합니다.
			                    </td>
			                  </tr>
			                </table>

			                <div style="margin-top:26px;font-size:12px;line-height:1.8;color:#8a97b2;">
			                  본 메일은 발신 전용 자동 안내 메일입니다.<br>
			                  %s | %s
			                </div>
			              </td>
			            </tr>
			          </table>
			        </td>
			      </tr>
			    </table>
			  </body>
			</html>
			""".formatted(
				safeBrandName,
				safeBrandName,
				safeCode,
				safeProductName,
				htmlEscape(codeDisplay),
				safeEmail,
				expiresMinutes,
				safeBrandName,
				safeProductName
			);
	}

	private String code() {
		return "%06d".formatted(RANDOM.nextInt(1_000_000));
	}

	private String normalizeEmail(String email) {
		if (email == null || email.isBlank()) {
			throw new IllegalArgumentException("이메일을 입력해주세요.");
		}
		return email.trim().toLowerCase();
	}

	private String normalizeCode(String code) {
		if (code == null || code.isBlank()) {
			throw new IllegalArgumentException("이메일 인증번호를 입력해주세요.");
		}
		return code.trim();
	}

	private String resolveFromAddress(String from, String username) {
		if (!from.isBlank()) {
			return from;
		}
		if (username.contains("@")) {
			return username;
		}
		return username.isBlank() ? "" : username + "@naver.com";
	}

	private String defaultText(String value, String fallback) {
		String cleaned = clean(value);
		return cleaned.isBlank() ? fallback : cleaned;
	}

	private String clean(String value) {
		return value == null ? "" : value.trim();
	}

	private String htmlEscape(String value) {
		return clean(value)
			.replace("&", "&amp;")
			.replace("<", "&lt;")
			.replace(">", "&gt;")
			.replace("\"", "&quot;")
			.replace("'", "&#39;");
	}
}
