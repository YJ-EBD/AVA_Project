package com.ava.backend.config;

import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.SimpMessageType;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.auth.service.LoginSessionService;
import com.ava.backend.auth.service.TokenService;

@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

	private final TokenService tokenService;
	private final LoginSessionService loginSessionService;
	private final List<String> allowedOrigins;

	public WebSocketConfig(
		TokenService tokenService,
		LoginSessionService loginSessionService,
		@Value("${ava.web.allowed-origins:*}") String allowedOrigins
	) {
		this.tokenService = tokenService;
		this.loginSessionService = loginSessionService;
		this.allowedOrigins = parseAllowedOrigins(allowedOrigins);
	}

	@Override
	public void configureMessageBroker(MessageBrokerRegistry registry) {
		registry.enableSimpleBroker("/topic", "/queue");
		registry.setApplicationDestinationPrefixes("/app");
		registry.setUserDestinationPrefix("/user");
	}

	@Override
	public void registerStompEndpoints(StompEndpointRegistry registry) {
		registry.addEndpoint("/ws")
			.setAllowedOriginPatterns(allowedOrigins.toArray(String[]::new));
	}

	@Override
	public void configureClientInboundChannel(ChannelRegistration registration) {
		registration.taskExecutor()
			.corePoolSize(4)
			.maxPoolSize(16)
			.queueCapacity(2000);
		registration.interceptors(new ChannelInterceptor() {
			@Override
			public Message<?> preSend(Message<?> message, MessageChannel channel) {
				StompHeaderAccessor accessor = StompHeaderAccessor.wrap(message);
				if (accessor.getCommand() == StompCommand.CONNECT || accessor.getMessageType() == SimpMessageType.CONNECT) {
					String authorization = accessor.getFirstNativeHeader("Authorization");
					if (authorization == null) {
						authorization = accessor.getFirstNativeHeader("authorization");
					}
					if (authorization != null && authorization.startsWith("Bearer ")) {
						tokenService.parse(authorization.substring(7))
							.filter(TokenService.TokenClaims::isAccessToken)
							.filter(claims -> loginSessionService.isCurrentSession(claims.userId(), claims.sessionId()))
							.ifPresent(claims -> accessor.setUser(new AuthPrincipal(
								claims.userId(),
								claims.email(),
								claims.displayName(),
								claims.role(),
								claims.sessionId()
							)));
					}
				}
				return message;
			}
		});
	}

	@Override
	public void configureClientOutboundChannel(ChannelRegistration registration) {
		registration.taskExecutor()
			.corePoolSize(4)
			.maxPoolSize(32)
			.queueCapacity(5000);
	}

	private static List<String> parseAllowedOrigins(String value) {
		List<String> origins = Arrays.stream(value.split(","))
			.map(String::trim)
			.filter(origin -> !origin.isBlank())
			.toList();
		return origins.isEmpty() ? List.of("*") : origins;
	}
}
