package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class AvaAiToolRegistry {

	private static final int MAX_PROCESS_OUTPUT_CHARS = 3_500;
	private static final int MAX_LOG_BYTES = 16_384;
	private static final int MAX_ANSWER_CHARS = 2_400;

	private final HttpClient httpClient;
	private final int serverPort;
	private final Duration commandTimeout;
	private final Path springBootDir;
	private final Path projectDir;

	public AvaAiToolRegistry(
		@Value("${server.port:8080}") int serverPort,
		@Value("${ava.ai.agent.command-timeout-seconds:240}") long commandTimeoutSeconds
	) {
		this.serverPort = serverPort;
		this.commandTimeout = Duration.ofSeconds(Math.max(15, commandTimeoutSeconds));
		this.springBootDir = Path.of("").toAbsolutePath().normalize();
		this.projectDir = springBootDir.getParent() == null ? springBootDir : springBootDir.getParent();
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(5))
			.build();
	}

	public Optional<ToolRequest> select(String content) {
		String normalized = normalize(content);
		if (normalized.isBlank()) {
			return Optional.empty();
		}
		if (mentionsServer(normalized) && containsAny(normalized, "재시작", "restart", "리부트", "reboot")) {
			return Optional.of(new ToolRequest(
				"server.restart",
				"서버 재시작 요청을 안전 경계에서 판정",
				false
			));
		}
		if (mentionsServer(normalized)
			&& containsAny(normalized, "헬스", "health", "상태", "살아", "up", "체크", "check")) {
			return Optional.of(new ToolRequest(
				"server.health",
				"Spring Boot actuator 헬스체크",
				true
			));
		}
		if (mentionsServer(normalized) && containsAny(normalized, "로그", "log", "에러", "error", "tail")) {
			return Optional.of(new ToolRequest(
				"server.logs",
				"최근 백엔드 로그 확인",
				true
			));
		}
		if (containsAny(normalized, "gradle test", "gradlew test", "백엔드 테스트", "스프링 테스트", "서버 테스트")) {
			return Optional.of(new ToolRequest(
				"build.gradleTest",
				"백엔드 테스트 실행",
				true
			));
		}
		if (containsAny(normalized, "flutter analyze", "플러터 분석", "플러터 analyze", "dart analyze")) {
			return Optional.of(new ToolRequest(
				"build.flutterAnalyze",
				"Flutter 정적 분석 실행",
				true
			));
		}
		return Optional.empty();
	}

	public List<AvaAiLlmClient.ToolDefinition> nativeToolDefinitions() {
		return List.of(
			new AvaAiLlmClient.ToolDefinition(
				"server_health",
				"Check the Spring Boot backend health endpoint and return the verified status.",
				objectSchema()
			),
			new AvaAiLlmClient.ToolDefinition(
				"server_logs",
				"Read recent backend logs for debugging or verification.",
				objectSchema()
			),
			new AvaAiLlmClient.ToolDefinition(
				"backend_tests",
				"Run the backend Gradle test suite when the user explicitly asks to test or verify backend code.",
				objectSchema()
			),
			new AvaAiLlmClient.ToolDefinition(
				"flutter_analyze",
				"Run Flutter static analysis when the user explicitly asks to analyze or verify Flutter code.",
				objectSchema()
			)
		);
	}

	public ToolExecution executeNativeTool(AvaAiLlmClient.ToolCall call) {
		if (call == null || call.name() == null) {
			return ToolExecution.notHandled();
		}
		return switch (call.name()) {
			case "server_health" -> execute(new ToolRequest("server.health", "LLM native tool: backend health check", true));
			case "server_logs" -> execute(new ToolRequest("server.logs", "LLM native tool: recent backend logs", true));
			case "backend_tests" -> execute(new ToolRequest("build.gradleTest", "LLM native tool: backend tests", true));
			case "flutter_analyze" -> execute(new ToolRequest("build.flutterAnalyze", "LLM native tool: Flutter analysis", true));
			default -> new ToolExecution(
				call.name(),
				true,
				false,
				false,
				false,
				"지원하지 않는 native tool call입니다: " + call.name(),
				"unsupported native tool: " + call.name(),
				"등록된 도구 목록에 없습니다.",
				"unsupported tool",
				"ava-agent/native-tool"
			);
		};
	}

	public ToolExecution execute(ToolRequest request) {
		if (request == null) {
			return ToolExecution.notHandled();
		}
		if (!request.executable()) {
			return new ToolExecution(
				request.toolName(),
				true,
				false,
				false,
				true,
				"이 작업은 현재 AVA 채팅 내부에서 즉시 실행하지 않았습니다. 서버 재시작은 실행 중인 백엔드 연결을 끊는 운영 작업이라 Codex 또는 서버 제어 스크립트에서 실행해야 합니다. 지금 가능한 자동 검증은 서버 헬스체크와 최근 로그 확인입니다.",
				"자동 실행 보류: " + request.description(),
				"승인/외부 실행 경로가 필요한 작업으로 분류했습니다.",
				"",
				"ava-agent/" + request.toolName()
			);
		}
		return switch (request.toolName()) {
			case "server.health" -> health();
			case "server.logs" -> logs();
			case "build.gradleTest" -> gradleTest();
			case "build.flutterAnalyze" -> flutterAnalyze();
			default -> ToolExecution.notHandled();
		};
	}

	private ToolExecution health() {
		String url = "http://127.0.0.1:" + serverPort + "/actuator/health";
		try {
			HttpRequest request = HttpRequest.newBuilder(URI.create(url))
				.timeout(Duration.ofSeconds(8))
				.GET()
				.build();
			HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
			String body = response.body() == null ? "" : response.body();
			boolean up = response.statusCode() >= 200 && response.statusCode() < 300 && body.contains("UP");
			if (up) {
				return new ToolExecution(
					"server.health",
					true,
					true,
					true,
					false,
					"서버 헬스체크 완료: Spring Boot actuator가 `UP`입니다. (HTTP " + response.statusCode() + ")",
					"GET " + url + " -> HTTP " + response.statusCode() + ", status=UP",
					"actuator 응답 본문에서 UP 상태를 확인했습니다.",
					"",
					"ava-agent/server.health"
				);
			}
			return new ToolExecution(
				"server.health",
				true,
				false,
				false,
				false,
				"서버 헬스체크 결과가 정상으로 확인되지 않았습니다. HTTP " + response.statusCode()
					+ ", 응답: " + limit(oneLine(body), 800),
				"GET " + url + " -> HTTP " + response.statusCode(),
				"UP 상태를 확인하지 못했습니다.",
				limit(oneLine(body), 1_200),
				"ava-agent/server.health"
			);
		} catch (IOException exception) {
			return failed("server.health", "서버 헬스체크 요청 중 I/O 오류가 발생했습니다.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return failed("server.health", "서버 헬스체크가 중단되었습니다.", exception);
		} catch (RuntimeException exception) {
			return failed("server.health", "서버 헬스체크 실행 중 오류가 발생했습니다.", exception);
		}
	}

	private ToolExecution logs() {
		Path logPath = springBootDir.resolve("logs").resolve("bootRun-azoom.out.log").normalize();
		if (!Files.exists(logPath)) {
			logPath = springBootDir.resolve("bootRun.log").normalize();
		}
		try {
			if (!Files.exists(logPath)) {
				return new ToolExecution(
					"server.logs",
					true,
					false,
					false,
					false,
					"최근 로그 파일을 찾지 못했습니다. 확인 대상: " + logPath,
					"로그 파일 없음",
					"로그 파일 존재 여부 검증 실패",
					"log file not found",
					"ava-agent/server.logs"
				);
			}
			String tail = tail(logPath, MAX_LOG_BYTES);
			String preview = recentNonBlankLines(tail, 18);
			return new ToolExecution(
				"server.logs",
				true,
				true,
				true,
				false,
				"최근 백엔드 로그를 확인했습니다.\n```text\n" + limit(preview, 1_800) + "\n```",
				"log=" + logPath + ", bytes<=" + MAX_LOG_BYTES,
				"로그 파일을 읽고 최근 비어있지 않은 라인을 추출했습니다.",
				"",
				"ava-agent/server.logs"
			);
		} catch (IOException exception) {
			return failed("server.logs", "최근 로그를 읽는 중 I/O 오류가 발생했습니다.", exception);
		} catch (RuntimeException exception) {
			return failed("server.logs", "최근 로그 확인 중 오류가 발생했습니다.", exception);
		}
	}

	private ToolExecution gradleTest() {
		return executeProcess(
			"build.gradleTest",
			List.of("cmd.exe", "/c", "gradlew.bat", "--no-daemon", "test"),
			springBootDir,
			"백엔드 테스트"
		);
	}

	private ToolExecution flutterAnalyze() {
		return executeProcess(
			"build.flutterAnalyze",
			List.of("cmd.exe", "/c", "flutter", "analyze"),
			projectDir.resolve("Flutter").normalize(),
			"Flutter 정적 분석"
		);
	}

	private ToolExecution executeProcess(String toolName, List<String> command, Path directory, String label) {
		ExecutorService executor = Executors.newSingleThreadExecutor();
		Process process = null;
		try {
			ProcessBuilder builder = new ProcessBuilder(command);
			builder.directory(directory.toFile());
			builder.redirectErrorStream(true);
			process = builder.start();
			Process runningProcess = process;
			Future<String> outputFuture = executor.submit(() ->
				new String(runningProcess.getInputStream().readAllBytes(), StandardCharsets.UTF_8));
			boolean finished = process.waitFor(commandTimeout.toSeconds(), TimeUnit.SECONDS);
			if (!finished) {
				process.destroyForcibly();
				String output = safeOutput(outputFuture);
				return new ToolExecution(
					toolName,
					true,
					false,
					false,
					false,
					label + "가 제한 시간(" + commandTimeout.toSeconds() + "초)을 넘겨 중단했습니다.\n```text\n"
						+ limit(output, 1_500) + "\n```",
					label + " timeout",
					"프로세스 종료 코드를 확인하지 못했습니다.",
					"timeout",
					"ava-agent/" + toolName
				);
			}
			String output = safeOutput(outputFuture);
			int exitCode = process.exitValue();
			boolean success = exitCode == 0;
			String answer = label + (success ? " 완료" : " 실패") + ": exitCode=" + exitCode
				+ "\n```text\n" + limit(output, MAX_PROCESS_OUTPUT_CHARS) + "\n```";
			return new ToolExecution(
				toolName,
				true,
				success,
				success,
				false,
				limit(answer, MAX_ANSWER_CHARS),
				label + " exitCode=" + exitCode + ", cwd=" + directory,
				success ? "프로세스 종료 코드 0을 확인했습니다." : "프로세스 종료 코드가 0이 아닙니다.",
				success ? "" : limit(output, 1_200),
				"ava-agent/" + toolName
			);
		} catch (IOException exception) {
			return failed(toolName, label + " 실행 중 I/O 오류가 발생했습니다.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return failed(toolName, label + " 실행이 중단되었습니다.", exception);
		} catch (RuntimeException exception) {
			return failed(toolName, label + " 실행 중 오류가 발생했습니다.", exception);
		} finally {
			if (process != null && process.isAlive()) {
				process.destroyForcibly();
			}
			executor.shutdownNow();
		}
	}

	private String safeOutput(Future<String> outputFuture) {
		try {
			return outputFuture.get(3, TimeUnit.SECONDS);
		} catch (Exception exception) {
			return "";
		}
	}

	private ToolExecution failed(String toolName, String answer, Exception exception) {
		return new ToolExecution(
			toolName,
			true,
			false,
			false,
			false,
			answer + " " + exception.getClass().getSimpleName() + ": " + limit(exception.getMessage(), 800),
			toolName + " failed",
			"예외가 발생해 검증을 완료하지 못했습니다.",
			exception.getClass().getSimpleName() + ": " + limit(exception.getMessage(), 1_200),
			"ava-agent/" + toolName
		);
	}

	private boolean mentionsServer(String normalized) {
		return containsAny(normalized, "서버", "백엔드", "spring", "springboot", "server", "backend", "ava_project");
	}

	private boolean containsAny(String normalized, String... terms) {
		for (String term : terms) {
			if (normalized.contains(term)) {
				return true;
			}
		}
		return false;
	}

	private String tail(Path path, int maxBytes) throws IOException {
		byte[] bytes = Files.readAllBytes(path);
		int start = Math.max(0, bytes.length - maxBytes);
		return new String(bytes, start, bytes.length - start, StandardCharsets.UTF_8);
	}

	private String recentNonBlankLines(String value, int maxLines) {
		String[] lines = value.replace("\r\n", "\n").replace('\r', '\n').split("\n");
		StringBuilder builder = new StringBuilder();
		int count = 0;
		for (int index = lines.length - 1; index >= 0 && count < maxLines; index--) {
			String line = lines[index].strip();
			if (line.isBlank()) {
				continue;
			}
			builder.insert(0, line + "\n");
			count++;
		}
		return builder.toString().strip();
	}

	private String oneLine(String value) {
		return value == null ? "" : value.replaceAll("\\s+", " ").strip();
	}

	private String normalize(String value) {
		return value == null ? "" : value.strip().toLowerCase(Locale.ROOT);
	}

	private Map<String, Object> objectSchema() {
		return Map.of(
			"type", "object",
			"properties", Map.of(),
			"additionalProperties", false
		);
	}

	private String limit(String value, int maxLength) {
		if (value == null) {
			return "";
		}
		if (value.length() <= maxLength) {
			return value;
		}
		return value.substring(0, Math.max(0, maxLength - 1)) + "…";
	}

	public record ToolRequest(String toolName, String description, boolean executable) {
	}

	public record ToolExecution(
		String toolName,
		boolean handled,
		boolean success,
		boolean verified,
		boolean waitingApproval,
		String answer,
		String resultSummary,
		String verificationSummary,
		String errorMessage,
		String modelName
	) {
		static ToolExecution notHandled() {
			return new ToolExecution("", false, false, false, false, "", "", "", "", "ava-agent");
		}
	}
}
