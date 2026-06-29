package com.ava.backend.config;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.ava.backend.chat.service.CompanyAllStaffChatService;
import com.ava.backend.chat.repository.ChatMessageRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Configuration
public class DemoDataSeeder {

	private static final String ADMIN_EMAIL = "admin@ava.admin";
	private static final String SUPERUSER_EMAIL = "amos5105@naver.com";
	private static final String SYSTEM_ACCOUNT_PASSWORD = "Ava1234!";
	private static final List<String> DEMO_ROOM_CODES = List.of(
		"ra-team",
		"research-lab",
		"all-staff",
		"design-team",
		"logistics-room"
	);

	@Bean
	ApplicationRunner seedSystemAccounts(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		NamedParameterJdbcTemplate jdbcTemplate,
		ChatMessageRepository mongoMessageRepository,
		CompanyScopeService companyScopeService,
		CompanyAllStaffChatService allStaffChatService,
		@Value("${AVA_ADMIN_ACCOUNT_PASSWORD:Ava1234!}") String adminAccountPassword
	) {
		return args -> {
			ensureUserAccountRoleConstraint(jdbcTemplate);
			ensureAvaAiConversationScopeConstraint(jdbcTemplate);
			removeDemoData(jdbcTemplate, mongoMessageRepository);
			normalizeCompanies(profileRepository, companyScopeService);
			ensurePrivilegedAccounts(accountRepository, profileRepository, passwordEncoder, adminAccountPassword);
			ensureAbbaDepartmentDemoUsers(accountRepository, profileRepository, passwordEncoder);
			allStaffChatService.ensureKnownCompanyRoomsAndMemberships();
		};
	}

	private void ensureUserAccountRoleConstraint(NamedParameterJdbcTemplate jdbcTemplate) {
		try {
			jdbcTemplate.getJdbcTemplate().execute(
				"alter table user_accounts drop constraint if exists user_accounts_role_check"
			);
			jdbcTemplate.getJdbcTemplate().execute(
				"""
				alter table user_accounts
				add constraint user_accounts_role_check
				check (role in ('SUPERUSER', 'ADMIN', 'USER'))
				"""
			);
		} catch (RuntimeException ignored) {
			// The table may not exist yet on a fresh schema; Hibernate will create it with the current enum values.
		}
	}

	private void ensureAvaAiConversationScopeConstraint(NamedParameterJdbcTemplate jdbcTemplate) {
		try {
			jdbcTemplate.getJdbcTemplate().execute(
				"""
				do $$
				declare
					constraint_name text;
				begin
					for constraint_name in
						select c.conname
						from pg_constraint c
						join pg_class t on t.oid = c.conrelid
						join pg_namespace n on n.oid = t.relnamespace
						where t.relname = 'ava_ai_conversations'
						  and n.nspname = current_schema()
						  and c.contype = 'u'
						  and pg_get_constraintdef(c.oid) = 'UNIQUE (account_id)'
					loop
						execute 'alter table ava_ai_conversations drop constraint ' || quote_ident(constraint_name);
					end loop;
				end $$;
				"""
			);
			jdbcTemplate.getJdbcTemplate().execute(
				"""
				do $$
				begin
					if not exists (
						select 1
						from pg_constraint c
						join pg_class t on t.oid = c.conrelid
						join pg_namespace n on n.oid = t.relnamespace
						where c.conname = 'uk_ava_ai_conversation_account_company'
						  and t.relname = 'ava_ai_conversations'
						  and n.nspname = current_schema()
					) then
						alter table ava_ai_conversations
						add constraint uk_ava_ai_conversation_account_company
						unique (account_id, company_name);
					end if;
				end $$;
				"""
			);
		} catch (RuntimeException ignored) {
			// PostgreSQL production schema is adjusted here; other local/test DBs can rely on Hibernate DDL.
		}
	}

	private void removeDemoData(
		NamedParameterJdbcTemplate jdbcTemplate,
		ChatMessageRepository mongoMessageRepository
	) {
		List<UUID> demoAccountIds = jdbcTemplate.queryForList(
			"""
			select id
			from user_accounts
			where lower(email) like :avaLocalPattern
			   or lower(email) like :candidatePattern
			   or lower(email) like :inviteTestPattern
			   or lower(email) = :oldAdmin
			""",
			Map.of(
				"avaLocalPattern", "%@ava.local",
				"candidatePattern", "candidate%@ava.local",
				"inviteTestPattern", "ava.invite.test%@abba-s.local",
				"oldAdmin", "admin@ava.local"
			),
			UUID.class
		);

		List<String> roomCodes = new ArrayList<>(DEMO_ROOM_CODES);
		roomCodes.addAll(jdbcTemplate.queryForList(
			"""
			select room.code
			from chat_rooms room
			where not exists (
				select 1
				from chat_room_members member
				where member.room_id = room.id
			)
			""",
			Map.of(),
			String.class
		));
		if (!demoAccountIds.isEmpty()) {
			roomCodes.addAll(jdbcTemplate.queryForList(
				"""
				select distinct room.code
				from chat_rooms room
				join chat_room_members member on member.room_id = room.id
				where room.code like 'direct-%'
				  and member.account_id in (:accountIds)
				""",
				new MapSqlParameterSource("accountIds", demoAccountIds),
				String.class
			));
		}

		if (!roomCodes.isEmpty()) {
			MapSqlParameterSource roomParams = new MapSqlParameterSource("roomCodes", roomCodes);
			jdbcTemplate.update("delete from chat_message_read_receipts where room_code in (:roomCodes)", roomParams);
			jdbcTemplate.update("delete from chat_talk_drawer_items where room_code in (:roomCodes)", roomParams);
			jdbcTemplate.update("delete from chat_message_records where room_code in (:roomCodes)", roomParams);
			jdbcTemplate.update(
				"delete from chat_room_members where room_id in (select id from chat_rooms where code in (:roomCodes))",
				roomParams
			);
			jdbcTemplate.update("delete from chat_rooms where code in (:roomCodes)", roomParams);
			for (String roomCode : roomCodes) {
				try {
					mongoMessageRepository.deleteByRoomCode(roomCode);
				} catch (RuntimeException ignored) {
					// MongoDB is optional in local runs; PostgreSQL cleanup remains authoritative.
				}
			}
		}

		if (!demoAccountIds.isEmpty()) {
			MapSqlParameterSource accountParams = new MapSqlParameterSource("accountIds", demoAccountIds);
			jdbcTemplate.update("delete from chat_message_read_receipts where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update(
				"""
				delete from chat_message_read_receipts
				where message_id in (
					select id from chat_message_records where sender_id in (:accountIds)
				)
				""",
				accountParams
			);
			jdbcTemplate.update("delete from chat_talk_drawer_items where uploaded_by_account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from chat_message_records where sender_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from chat_room_members where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from sessions where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from notifications where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from company_blocked_employees where target_account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from company_blocked_employees where blocked_by_account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from azoom_members where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from user_roles where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from user_roles where assigned_by_account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from user_chat_folder_settings where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from user_profiles where account_id in (:accountIds)", accountParams);
			jdbcTemplate.update("delete from user_accounts where id in (:accountIds)", accountParams);
		}
	}

	private void normalizeCompanies(
		UserProfileRepository profileRepository,
		CompanyScopeService companyScopeService
	) {
		for (UserProfile profile : profileRepository.findAll()) {
			String normalized = companyScopeService.normalizeCompany(profile.getCompanyName());
			if (!normalized.equals(profile.getCompanyName())) {
				profile.setCompanyName(normalized);
				profileRepository.save(profile);
			}
		}
	}

	private void ensurePrivilegedAccounts(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder,
		String adminAccountPassword
	) {
		String resolvedAdminPassword =
			adminAccountPassword == null || adminAccountPassword.isBlank()
				? SYSTEM_ACCOUNT_PASSWORD
				: adminAccountPassword;
		UserAccount adminAccount = accountRepository.findByEmailIgnoreCase(ADMIN_EMAIL)
			.orElseGet(() -> new UserAccount(
				ADMIN_EMAIL,
				passwordEncoder.encode(resolvedAdminPassword),
				"박주한",
				UserRole.ADMIN
			));
		adminAccount.setPasswordHash(passwordEncoder.encode(resolvedAdminPassword));
		adminAccount.setDisplayName("박주한");
		adminAccount.setRole(UserRole.ADMIN);
		adminAccount.setEnabled(true);
		adminAccount = accountRepository.save(adminAccount);

		final UserAccount savedAdminAccount = adminAccount;
		UserProfile adminProfile = profileRepository.findByAccountId(savedAdminAccount.getId())
			.orElseGet(() -> new UserProfile(
				savedAdminAccount,
				"Management",
				"박주한",
				"010-0000-0000",
				null,
				"\uC624\uD504\uB77C\uC778",
				"#0F1530"
			));
		adminProfile.setCompanyName(CompanyScopeService.DEFAULT_COMPANY);
		adminProfile.setDepartment("Management");
		adminProfile.setPosition("Admin");
		adminProfile.setNickname("박주한");
		profileRepository.save(adminProfile);

		UserAccount superuserAccount = accountRepository.findByEmailIgnoreCase(SUPERUSER_EMAIL)
			.orElseGet(() -> new UserAccount(
				SUPERUSER_EMAIL,
				passwordEncoder.encode(SYSTEM_ACCOUNT_PASSWORD),
				"amos5105",
				UserRole.SUPERUSER
			));
		if (superuserAccount.getDisplayName() == null || superuserAccount.getDisplayName().isBlank()) {
			superuserAccount.setDisplayName("amos5105");
		}
		superuserAccount.setRole(UserRole.SUPERUSER);
		superuserAccount.setEnabled(true);
		superuserAccount = accountRepository.save(superuserAccount);

		final UserAccount savedSuperuserAccount = superuserAccount;
		UserProfile superuserProfile = profileRepository.findByAccountId(savedSuperuserAccount.getId())
			.orElseGet(() -> new UserProfile(
				savedSuperuserAccount,
				"Management",
				savedSuperuserAccount.getDisplayName(),
				"010-0000-0000",
				null,
				"\uC624\uD504\uB77C\uC778",
				"#0F1530"
			));
		superuserProfile.setCompanyName(CompanyScopeService.DEFAULT_COMPANY);
		if (superuserProfile.getDepartment() == null || superuserProfile.getDepartment().isBlank()) {
			superuserProfile.setDepartment("Management");
		}
		if (superuserProfile.getPosition() == null || superuserProfile.getPosition().isBlank()) {
			superuserProfile.setPosition("Superuser");
		}
		if (superuserProfile.getNickname() == null || superuserProfile.getNickname().isBlank()) {
			superuserProfile.setNickname(savedSuperuserAccount.getDisplayName());
		}
		profileRepository.save(superuserProfile);
	}

	private void ensureAbbaDepartmentDemoUsers(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder
	) {
		List<DepartmentSeed> departments = List.of(
			new DepartmentSeed("RA팀", "ra", List.of("김태희", "송혜교", "전지현", "손예진", "한지민", "공효진")),
			new DepartmentSeed("연구소", "research", List.of("이민호", "김수현", "박보검", "정우성", "이정재", "조인성")),
			new DepartmentSeed("경영지원부", "management-support", List.of("한효주", "박신혜", "문채원", "김고은", "신세경", "서현진")),
			new DepartmentSeed("생산기술", "production-engineering", List.of("강동원", "지창욱", "이종석", "여진구", "서인국", "김우빈")),
			new DepartmentSeed("QA", "qa", List.of("임윤아", "권유리", "김태연", "정수정", "배수지", "손나은")),
			new DepartmentSeed("디자인팀", "design", List.of("김유정", "김소현", "김지원", "박보영", "천우희", "전여빈")),
			new DepartmentSeed("기구설계팀", "mechanical-design", List.of("공지철", "이동욱", "유연석", "남주혁", "류준열", "이제훈"))
		);

		for (DepartmentSeed department : departments) {
			for (int index = 0; index < department.names().size(); index++) {
				String name = department.names().get(index);
				int userNumber = index + 1;
				String email = "ava.demo.%s.%02d@abba-s.local".formatted(department.slug(), userNumber);
				UserAccount account = accountRepository.findByEmailIgnoreCase(email)
					.orElseGet(() -> new UserAccount(
						email,
						passwordEncoder.encode("Ava1234!"),
						name,
						UserRole.USER
					));
				account.setDisplayName(name);
				account.setRole(UserRole.USER);
				account.setEnabled(true);
				account = accountRepository.save(account);

				final UserAccount savedAccount = account;
				final String avatarColor = testUserAvatarColor(Math.abs(email.hashCode()));
				UserProfile profile = profileRepository.findByAccountId(savedAccount.getId())
					.orElseGet(() -> new UserProfile(
						savedAccount,
						department.name(),
						name,
						null,
						null,
						"\uC624\uD504\uB77C\uC778",
						avatarColor
					));
				profile.setCompanyName(CompanyScopeService.DEFAULT_COMPANY);
				profile.setDepartment(department.name());
				profile.setPosition("\uC0AC\uC6D0");
				profile.setNickname(name);
				profile.setContactEmail(email);
				profile.setAvatarColor(avatarColor);
				profileRepository.save(profile);
			}
		}
	}

	private record DepartmentSeed(String name, String slug, List<String> names) {
	}

	private String testUserAvatarColor(int index) {
		String[] colors = {
			"#7C6BFF",
			"#4F8DFF",
			"#42AFC9",
			"#74A76F",
			"#D7A04E",
			"#D77772"
		};
		return colors[Math.floorMod(index - 1, colors.length)];
	}
}
