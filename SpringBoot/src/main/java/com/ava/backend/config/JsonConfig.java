package com.ava.backend.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.fasterxml.jackson.databind.ObjectMapper;

@Configuration
public class JsonConfig {

	@Bean
	ObjectMapper objectMapper() {
		return new ObjectMapper();
	}
}
