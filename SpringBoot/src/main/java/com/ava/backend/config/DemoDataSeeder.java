package com.ava.backend.config;

import java.util.ArrayList;
import java.util.List;

import org.springframework.boot.ApplicationRunner;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.ava.backend.chat.entity.ChatMessageDocument;
import com.ava.backend.chat.entity.ChatMessageEntity;
import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.entity.ChatRoomMemberEntity;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.repository.ChatMessageRepository;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Configuration
public class DemoDataSeeder {

	@Bean
	ApplicationRunner seedDemoData(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		ChatRoomRepository roomRepository,
		ChatRoomMemberRepository memberRepository,
		ChatMessageJpaRepository messageJpaRepository,
		ChatMessageRepository messageRepository,
		PasswordEncoder passwordEncoder,
		@Value("${ava.seed.mongo-messages:true}") boolean seedMongoMessages
	) {
		return args -> {
			if (accountRepository.count() > 0) {
				normalizeExistingProfiles(accountRepository, profileRepository);
				ensureCandidateUsers(accountRepository, profileRepository, passwordEncoder);
				return;
			}

			List<UserAccount> users = new ArrayList<>();
			users.add(createUser(accountRepository, profileRepository, passwordEncoder, "admin@ava.local", "관리자", "관리자", "010-0000-0000", "관리", UserRole.ADMIN, "#0F1530"));
			users.add(createUser(accountRepository, profileRepository, passwordEncoder, "amos5105@naver.com", "장유종", "AVA", "010-5105-0000", "한국 개발부", UserRole.USER, "#7AA06A"));
			String[] names = {
				"김라온", "박도윤", "이서진", "최민준", "정시우", "한유찬", "문하준", "오지후", "윤태오", "서이준",
				"강민재", "배수민", "강현우", "김태연", "박서아", "이준호", "최유나", "정다은", "한지민", "오세훈",
				"윤가온", "송민서", "임도현", "홍예준", "민서현", "고하늘", "류채원", "진태민", "서나윤", "권유리",
				"강입고", "김출고", "박재고", "이검수", "최포장", "정상차", "한운송", "문배차", "오하역", "윤검품",
				"김민재 대리", "박서연 주임", "이도현 책임", "최하린 매니저", "정우성 과장", "한지우 연구원", "오나래 디자이너",
				"강수진 PM", "윤태호 선임", "서하늘 사원"
			};
			String[] colors = {"#8FC7D5", "#A6C6EE", "#DDE8A5", "#9FB2D9", "#7DB3D7", "#E2B28D", "#B6A4E8", "#92D5E2"};
			for (int i = 0; i < names.length; i++) {
				users.add(createUser(
					accountRepository,
					profileRepository,
					passwordEncoder,
					"user%02d@ava.local".formatted(i + 1),
					names[i],
					names[i],
					"010-%04d-%04d".formatted(1000 + i, 2000 + i),
					i < 12 ? "RA팀" : i < 23 ? "연구소" : i < 30 ? "디자인팀" : i < 40 ? "입출고" : "개인",
					UserRole.USER,
					colors[i % colors.length]
				));
			}

			createRoom(roomRepository, memberRepository, messageJpaRepository, messageRepository, seedMongoMessages, "ra-team", "RA팀", ChatRoomType.GROUP, true, "인증 일정표 업데이트해서 공유했습니다.", users.subList(2, 14));
			createRoom(roomRepository, memberRepository, messageJpaRepository, messageRepository, seedMongoMessages, "research-lab", "연구소", ChatRoomType.GROUP, false, "Qwen 테스트 로그와 벤치 결과 확인 부탁드립니다.", users.subList(14, 25));
			createRoom(roomRepository, memberRepository, messageJpaRepository, messageRepository, seedMongoMessages, "all-staff", "전직원", ChatRoomType.GROUP, false, "오늘 오후 5시 전사 공지 확인해주세요.", users.subList(0, 20));
			createRoom(roomRepository, memberRepository, messageJpaRepository, messageRepository, seedMongoMessages, "design-team", "디자인팀", ChatRoomType.GROUP, false, "메신저 아이콘 시안 2차 업로드했습니다.", users.subList(25, 34));
			createRoom(roomRepository, memberRepository, messageJpaRepository, messageRepository, seedMongoMessages, "logistics-room", "입출고방", ChatRoomType.GROUP, false, "오전 입고분 검수 완료, 출고 리스트 확인 중입니다.", users.subList(34, 49));

			for (int i = 42; i < users.size(); i++) {
				UserAccount target = users.get(i);
				createRoom(
					roomRepository,
					memberRepository,
					messageJpaRepository,
					messageRepository,
					seedMongoMessages,
					"direct-" + target.getId(),
					target.getDisplayName(),
					ChatRoomType.DIRECT,
					false,
					target.getDisplayName() + "님과 1:1 대화를 시작했습니다.",
					List.of(users.get(1), target)
				);
			}
			ensureCandidateUsers(accountRepository, profileRepository, passwordEncoder);
		};
	}

	private UserAccount createUser(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		String email,
		String displayName,
		String nickname,
		String phoneNumber,
		String department,
		UserRole role,
		String avatarColor
	) {
		UserAccount account = accountRepository.save(new UserAccount(
			email,
			passwordEncoder.encode("Ava1234!"),
			displayName,
			role
		));
		UserProfile profile = new UserProfile(account, department, nickname, normalizeKoreanPhone(phoneNumber), null, "온라인", avatarColor);
		profile.setCompanyName("ABBA-S");
		profile.setPosition(defaultPosition(displayName, role));
		profileRepository.save(profile);
		return account;
	}

	private void ensureCandidateUsers(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder
	) {
		createCandidateUserIfMissing(
			accountRepository,
			profileRepository,
			passwordEncoder,
			"candidate01@ava.local",
			"이초대",
			"이초대",
			"+82 010-7001-3001",
			"#A6C6EE"
		);
		createCandidateUserIfMissing(
			accountRepository,
			profileRepository,
			passwordEncoder,
			"candidate02@ava.local",
			"박외부",
			"박외부",
			"+82 010-7002-3002",
			"#DDE8A5"
		);
		createCandidateUserIfMissing(
			accountRepository,
			profileRepository,
			passwordEncoder,
			"candidate03@ava.local",
			"최입사",
			"최입사",
			"+82 010-7003-3003",
			"#B6A4E8"
		);
	}

	private void createCandidateUserIfMissing(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		String email,
		String displayName,
		String nickname,
		String phoneNumber,
		String avatarColor
	) {
		if (accountRepository.existsByEmailIgnoreCase(email)) {
			return;
		}
		UserAccount account = accountRepository.save(new UserAccount(
			email,
			passwordEncoder.encode("Ava1234!"),
			displayName,
			UserRole.USER
		));
		UserProfile profile = new UserProfile(account, "미지정", nickname, normalizeKoreanPhone(phoneNumber), null, "오프라인", avatarColor);
		profile.setCompanyName("미소속");
		profile.setPosition("사원");
		profileRepository.save(profile);
	}

	private void normalizeExistingProfiles(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository
	) {
		for (UserProfile profile : profileRepository.findAll()) {
			boolean changed = false;
			if (profile.getCompanyName() == null || profile.getCompanyName().isBlank()) {
				profile.setCompanyName("ABBA-S");
				changed = true;
			}
			if (profile.getDepartment() == null || profile.getDepartment().isBlank() || "AVA".equals(profile.getDepartment())) {
				profile.setDepartment("미지정");
				changed = true;
			}
			if (profile.getPosition() == null || profile.getPosition().isBlank() || "사원".equals(profile.getPosition())) {
				var account = accountRepository.findById(profile.getAccount().getId()).orElse(null);
				String position = account == null ? "사원" : defaultPosition(account.getDisplayName(), account.getRole());
				profile.setPosition(position);
				changed = true;
			}
			String normalizedPhone = normalizeKoreanPhone(profile.getPhoneNumber());
			if (normalizedPhone != null && !normalizedPhone.equals(profile.getPhoneNumber())) {
				profile.setPhoneNumber(normalizedPhone);
				changed = true;
			}
			if (changed) {
				profileRepository.save(profile);
			}
		}
	}

	private String defaultPosition(String displayName, UserRole role) {
		if (role == UserRole.ADMIN) {
			return "관리자";
		}
		if (displayName.contains("대리")) {
			return "대리";
		}
		if (displayName.contains("주임")) {
			return "주임";
		}
		if (displayName.contains("책임")) {
			return "책임";
		}
		if (displayName.contains("매니저")) {
			return "매니저";
		}
		if (displayName.contains("과장")) {
			return "과장";
		}
		if (displayName.contains("연구원")) {
			return "연구원";
		}
		if (displayName.contains("디자이너")) {
			return "디자이너";
		}
		if (displayName.contains("PM")) {
			return "PM";
		}
		if (displayName.contains("선임")) {
			return "선임";
		}
		return "사원";
	}

	private void createRoom(
		ChatRoomRepository roomRepository,
		ChatRoomMemberRepository memberRepository,
		ChatMessageJpaRepository messageJpaRepository,
		ChatMessageRepository messageRepository,
		boolean seedMongoMessages,
		String code,
		String title,
		ChatRoomType type,
		boolean pinned,
		String lastMessage,
		List<UserAccount> members
	) {
		ChatRoomEntity room = roomRepository.save(new ChatRoomEntity(code, title, type, pinned, lastMessage));
		for (UserAccount member : members) {
			memberRepository.save(new ChatRoomMemberEntity(room, member));
		}
		if (!members.isEmpty()) {
			messageJpaRepository.save(new ChatMessageEntity(code, members.get(0).getId(), members.get(0).getDisplayName(), lastMessage));
		}
		if (seedMongoMessages && !members.isEmpty()) {
			try {
				messageRepository.save(new ChatMessageDocument(code, members.get(0).getId(), members.get(0).getDisplayName(), lastMessage));
			} catch (RuntimeException ignored) {
				// Local H2-only startup can run without MongoDB. The real MongoDB path is still used when available.
			}
		}
	}

	private String normalizeKoreanPhone(String phoneNumber) {
		if (phoneNumber == null || phoneNumber.isBlank()) {
			return phoneNumber;
		}
		String trimmed = phoneNumber.trim();
		if (trimmed.startsWith("+")) {
			return trimmed;
		}
		String digits = trimmed.replaceAll("[^0-9]", "");
		if (digits.isBlank()) {
			return trimmed;
		}
		if (digits.startsWith("82")) {
			digits = digits.substring(2);
			if (digits.startsWith("0")) {
				digits = digits.substring(1);
			}
			return "+82 " + formatKoreanLocalPhone("0" + digits);
		}
		return "+82 " + formatKoreanLocalPhone(digits);
	}

	private String formatKoreanLocalPhone(String digits) {
		if (digits.length() == 11) {
			return digits.substring(0, 3) + "-" + digits.substring(3, 7) + "-" + digits.substring(7);
		}
		if (digits.length() == 10) {
			return digits.substring(0, 3) + "-" + digits.substring(3, 6) + "-" + digits.substring(6);
		}
		return digits;
	}
}
