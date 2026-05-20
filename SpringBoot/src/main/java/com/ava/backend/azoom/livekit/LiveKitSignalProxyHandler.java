package com.ava.backend.azoom.livekit;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.function.Function;

import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.BinaryMessage;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.PingMessage;
import org.springframework.web.socket.PongMessage;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.AbstractWebSocketHandler;

@Component
public class LiveKitSignalProxyHandler extends AbstractWebSocketHandler {

	private static final Duration UPSTREAM_CONNECT_TIMEOUT = Duration.ofSeconds(10);

	private final LiveKitSignalProxyProperties properties;
	private final HttpClient httpClient;
	private final ConcurrentMap<String, ProxyConnection> connections = new ConcurrentHashMap<>();

	public LiveKitSignalProxyHandler(LiveKitSignalProxyProperties properties) {
		this.properties = properties;
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(UPSTREAM_CONNECT_TIMEOUT)
			.build();
	}

	@Override
	public void afterConnectionEstablished(WebSocketSession session) {
		if (!properties.enabled()) {
			closeQuietly(session, CloseStatus.SERVICE_RESTARTED);
			return;
		}
		URI upstreamUri = properties.upstreamWebSocketUri(session.getUri());
		UpstreamListener listener = new UpstreamListener(session);
		WebSocket.Builder builder = httpClient.newWebSocketBuilder()
			.connectTimeout(UPSTREAM_CONNECT_TIMEOUT);
		String authorization = session.getHandshakeHeaders().getFirst(HttpHeaders.AUTHORIZATION);
		if (authorization != null && !authorization.isBlank()) {
			builder.header(HttpHeaders.AUTHORIZATION, authorization);
		}
		CompletableFuture<WebSocket> upstream = builder.buildAsync(upstreamUri, listener);
		ProxyConnection connection = new ProxyConnection(session, upstream);
		listener.attach(connection);
		connections.put(session.getId(), connection);
		upstream.whenComplete((socket, error) -> {
			if (error != null) {
				connections.remove(session.getId());
				closeQuietly(session, CloseStatus.SERVER_ERROR);
				return;
			}
		});
	}

	@Override
	protected void handleTextMessage(WebSocketSession session, TextMessage message) {
		sendToUpstream(session, socket -> socket.sendText(message.getPayload(), message.isLast()));
	}

	@Override
	protected void handleBinaryMessage(WebSocketSession session, BinaryMessage message) {
		sendToUpstream(session, socket -> socket.sendBinary(message.getPayload().asReadOnlyBuffer(), message.isLast()));
	}

	@Override
	protected void handlePongMessage(WebSocketSession session, PongMessage message) {
		sendToUpstream(session, socket -> socket.sendPong(message.getPayload().asReadOnlyBuffer()));
	}

	@Override
	public void handleMessage(WebSocketSession session, WebSocketMessage<?> message) throws Exception {
		if (message instanceof PingMessage ping) {
			sendToUpstream(session, socket -> socket.sendPing(ping.getPayload().asReadOnlyBuffer()));
			return;
		}
		super.handleMessage(session, message);
	}

	@Override
	public void handleTransportError(WebSocketSession session, Throwable exception) {
		closeQuietly(session, CloseStatus.SERVER_ERROR);
		closeUpstream(session.getId(), CloseStatus.SERVER_ERROR);
	}

	@Override
	public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
		closeUpstream(session.getId(), status);
	}

	private void sendToUpstream(
		WebSocketSession session,
		Function<WebSocket, CompletableFuture<WebSocket>> sender
	) {
		ProxyConnection connection = connections.get(session.getId());
		if (connection == null) {
			closeQuietly(session, CloseStatus.SESSION_NOT_RELIABLE);
			return;
		}
		connection.sendToUpstream(sender);
	}

	private void closeUpstream(String sessionId, CloseStatus status) {
		ProxyConnection connection = connections.remove(sessionId);
		if (connection == null) {
			return;
		}
		connection.closeUpstream(status);
	}

	private static void closeQuietly(WebSocketSession session, CloseStatus status) {
		try {
			if (session.isOpen()) {
				session.close(status);
			}
		} catch (IOException ignored) {
			// The proxy path must not leak transport cleanup failures into app logic.
		}
	}

	private static byte[] readRemaining(ByteBuffer buffer) {
		ByteBuffer duplicate = buffer.asReadOnlyBuffer();
		byte[] bytes = new byte[duplicate.remaining()];
		duplicate.get(bytes);
		return bytes;
	}

	private static final class ProxyConnection {

		private final WebSocketSession downstream;
		private final CompletableFuture<WebSocket> upstream;
		private final Object upstreamLock = new Object();
		private CompletableFuture<?> upstreamSend = CompletableFuture.completedFuture(null);

		private ProxyConnection(WebSocketSession downstream, CompletableFuture<WebSocket> upstream) {
			this.downstream = downstream;
			this.upstream = upstream;
		}

		private void sendToUpstream(Function<WebSocket, CompletableFuture<WebSocket>> sender) {
			synchronized (upstreamLock) {
				upstreamSend = upstreamSend
					.thenCompose(ignored -> upstream.thenCompose(sender))
					.exceptionally(error -> {
						closeQuietly(downstream, CloseStatus.SERVER_ERROR);
						return null;
					});
			}
		}

		private void sendToDownstream(WebSocketMessage<?> message) {
			synchronized (downstream) {
				try {
					if (downstream.isOpen()) {
						downstream.sendMessage(message);
					}
				} catch (IOException ignored) {
					closeQuietly(downstream, CloseStatus.SERVER_ERROR);
				}
			}
		}

		private void closeUpstream(CloseStatus status) {
			upstream.thenAccept(socket -> socket.sendClose(status.getCode(), status.getReason()))
				.exceptionally(error -> null);
		}
	}

	private static final class UpstreamListener implements WebSocket.Listener {

		private final WebSocketSession downstream;
		private final StringBuilder textBuffer = new StringBuilder();
		private final ByteArrayOutputStream binaryBuffer = new ByteArrayOutputStream();
		private ProxyConnection connection;

		private UpstreamListener(WebSocketSession downstream) {
			this.downstream = downstream;
		}

		private void attach(ProxyConnection connection) {
			this.connection = connection;
		}

		@Override
		public void onOpen(WebSocket webSocket) {
			webSocket.request(1);
		}

		@Override
		public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
			textBuffer.append(data);
			if (last) {
				ProxyConnection attached = connection;
				if (attached != null) {
					attached.sendToDownstream(new TextMessage(textBuffer.toString()));
				}
				textBuffer.setLength(0);
			}
			webSocket.request(1);
			return CompletableFuture.completedFuture(null);
		}

		@Override
		public CompletionStage<?> onBinary(WebSocket webSocket, ByteBuffer data, boolean last) {
			try {
				binaryBuffer.write(readRemaining(data));
				if (last) {
					ProxyConnection attached = connection;
					if (attached != null) {
						attached.sendToDownstream(new BinaryMessage(binaryBuffer.toByteArray()));
					}
					binaryBuffer.reset();
				}
			} catch (IOException exception) {
				closeQuietly(downstream, CloseStatus.SERVER_ERROR);
			}
			webSocket.request(1);
			return CompletableFuture.completedFuture(null);
		}

		@Override
		public CompletionStage<?> onPing(WebSocket webSocket, ByteBuffer message) {
			ProxyConnection attached = connection;
			if (attached != null) {
				attached.sendToDownstream(new PingMessage(message.asReadOnlyBuffer()));
			}
			webSocket.request(1);
			return CompletableFuture.completedFuture(null);
		}

		@Override
		public CompletionStage<?> onPong(WebSocket webSocket, ByteBuffer message) {
			ProxyConnection attached = connection;
			if (attached != null) {
				attached.sendToDownstream(new PongMessage(message.asReadOnlyBuffer()));
			}
			webSocket.request(1);
			return CompletableFuture.completedFuture(null);
		}

		@Override
		public CompletionStage<?> onClose(WebSocket webSocket, int statusCode, String reason) {
			closeQuietly(downstream, new CloseStatus(statusCode, reason));
			return CompletableFuture.completedFuture(null);
		}

		@Override
		public void onError(WebSocket webSocket, Throwable error) {
			closeQuietly(downstream, CloseStatus.SERVER_ERROR);
		}
	}
}
