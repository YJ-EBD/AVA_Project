package com.ava.backend.config;

import java.util.concurrent.Executor;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
public class ChatRealtimeExecutorConfig {

	@Bean(name = "chatRealtimeEventExecutor")
	public Executor chatRealtimeEventExecutor(
		@Value("${ava.chat.realtime-event-core-pool-size:4}") int corePoolSize,
		@Value("${ava.chat.realtime-event-max-pool-size:12}") int maxPoolSize,
		@Value("${ava.chat.realtime-event-queue-capacity:10000}") int queueCapacity
	) {
		ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
		executor.setThreadNamePrefix("chat-realtime-events-");
		executor.setCorePoolSize(Math.max(1, corePoolSize));
		executor.setMaxPoolSize(Math.max(corePoolSize, maxPoolSize));
		executor.setQueueCapacity(Math.max(100, queueCapacity));
		executor.initialize();
		return executor;
	}
}
