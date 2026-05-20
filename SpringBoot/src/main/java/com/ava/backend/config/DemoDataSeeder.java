package com.ava.backend.config;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.ava.backend.chat.repository.ChatMessageRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.entity.UserRole;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Configuration
public class DemoDataSeeder {

	private static final String SUPERUSER_EMAIL = "admin@ava.admin";
	private static final String SUPERUSER_PASSWORD = "Ava1234!";
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
		CompanyScopeService companyScopeService
	) {
		return args -> {
			ensureUserAccountRoleConstraint(jdbcTemplate);
			ensureAvaAiConversationScopeConstraint(jdbcTemplate);
			removeDemoData(jdbcTemplate, mongoMessageRepository);
			normalizeCompanies(profileRepository, companyScopeService);
			ensureSuperuser(accountRepository, profileRepository, passwordEncoder);
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
			   or lower(email) = :oldAdmin
			""",
			Map.of(
				"avaLocalPattern", "%@ava.local",
				"candidatePattern", "candidate%@ava.local",
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

	private void ensureSuperuser(
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		PasswordEncoder passwordEncoder
	) {
		UserAccount account = accountRepository.findByEmailIgnoreCase(SUPERUSER_EMAIL)
			.orElseGet(() -> new UserAccount(
				SUPERUSER_EMAIL,
				passwordEncoder.encode(SUPERUSER_PASSWORD),
				"Superuser",
				UserRole.SUPERUSER
			));
		account.setPasswordHash(passwordEncoder.encode(SUPERUSER_PASSWORD));
		account.setDisplayName("Superuser");
		account.setRole(UserRole.SUPERUSER);
		account.setEnabled(true);
		account = accountRepository.save(account);

		final UserAccount savedAccount = account;
		UserProfile profile = profileRepository.findByAccountId(savedAccount.getId())
			.orElseGet(() -> new UserProfile(
				savedAccount,
				"Management",
				"Superuser",
				"010-0000-0000",
				null,
				"offline",
				"#0F1530"
			));
		profile.setCompanyName(CompanyScopeService.DEFAULT_COMPANY);
		profile.setDepartment("Management");
		profile.setPosition("Superuser");
		profile.setNickname("Superuser");
		profileRepository.save(profile);
	}
}
