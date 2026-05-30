package com.ava.backend.config;

import javax.sql.DataSource;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class DatabaseCompatibilityInitializer implements ApplicationRunner {

	private final DataSource dataSource;
	private final JdbcTemplate jdbcTemplate;

	public DatabaseCompatibilityInitializer(DataSource dataSource, JdbcTemplate jdbcTemplate) {
		this.dataSource = dataSource;
		this.jdbcTemplate = jdbcTemplate;
	}

	@Override
	public void run(ApplicationArguments args) throws Exception {
		if (!isPostgreSql()) {
			return;
		}
		jdbcTemplate.execute("alter table if exists chat_rooms drop constraint if exists chat_rooms_type_check");
		jdbcTemplate.execute("""
			alter table if exists chat_rooms
			add constraint chat_rooms_type_check
			check (type in ('GROUP', 'DIRECT', 'SELF'))
			""");
		jdbcTemplate.execute("drop table if exists azoom_chat_messages");
		jdbcTemplate.execute("delete from azoom_channels where type = 'TEXT'");
		jdbcTemplate.execute("""
			alter table if exists azoom_channels
			add column if not exists access_mode varchar(24)
			""");
		jdbcTemplate.execute("""
			update azoom_channels
			set access_mode = 'ALL'
			where access_mode is null or trim(access_mode) = ''
			""");
		jdbcTemplate.execute("""
			alter table if exists azoom_channels
			alter column access_mode set default 'ALL'
			""");
		jdbcTemplate.execute("""
			alter table if exists azoom_channels
			alter column access_mode set not null
			""");
		jdbcTemplate.execute("""
			alter table if exists azoom_channels
			add column if not exists allowed_departments text
			""");
		jdbcTemplate.execute("""
			alter table if exists chat_message_records
			add column if not exists mention_user_ids varchar(2000)
			""");
		jdbcTemplate.execute("""
			alter table if exists chat_message_records
			add column if not exists mention_display_names varchar(2000)
			""");
		jdbcTemplate.execute("""
			alter table if exists chat_message_records
			add column if not exists deleted_for_everyone boolean not null default false
			""");
		jdbcTemplate.execute("""
			create table if not exists chat_mention_notifications (
				id uuid primary key,
				message_id uuid not null references chat_message_records(id) on delete cascade,
				mentioned_account_id uuid not null references user_accounts(id) on delete cascade,
				room_code varchar(80) not null,
				mention_display_name varchar(120) not null,
				created_at timestamp with time zone not null,
				checked_at timestamp with time zone null,
				constraint uk_chat_mentions_message_account unique (message_id, mentioned_account_id)
			)
			""");
		jdbcTemplate.execute("""
			create index if not exists idx_chat_mentions_account_checked_created
			on chat_mention_notifications (mentioned_account_id, checked_at, created_at desc)
			""");
		jdbcTemplate.execute("""
			create index if not exists idx_chat_mentions_account_created
			on chat_mention_notifications (mentioned_account_id, created_at desc)
			""");
		jdbcTemplate.execute("""
			alter table if exists calendar_events
			add column if not exists team_id varchar(80)
			""");
		jdbcTemplate.execute("""
			alter table if exists calendar_events
			add column if not exists importance varchar(20) not null default 'NORMAL'
			""");
		jdbcTemplate.execute("""
			create index if not exists idx_calendar_events_team
			on calendar_events (team_id, start_at)
			where deleted_at is null
			""");
	}

	private boolean isPostgreSql() throws Exception {
		try (var connection = dataSource.getConnection()) {
			String productName = connection.getMetaData().getDatabaseProductName();
			return productName != null && productName.toLowerCase().contains("postgresql");
		}
	}
}
