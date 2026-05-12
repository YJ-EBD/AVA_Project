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
	}

	private boolean isPostgreSql() throws Exception {
		try (var connection = dataSource.getConnection()) {
			String productName = connection.getMetaData().getDatabaseProductName();
			return productName != null && productName.toLowerCase().contains("postgresql");
		}
	}
}
