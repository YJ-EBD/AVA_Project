package com.ava.backend.ai.service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.ai.dto.AvaAiNotionBlockResponse;
import com.ava.backend.ai.dto.AvaAiNotionCommandRequest;
import com.ava.backend.ai.dto.AvaAiNotionCommandResponse;
import com.ava.backend.ai.dto.AvaAiNotionPageResponse;
import com.ava.backend.ai.dto.AvaAiNotionPropertyResponse;
import com.ava.backend.auth.security.AuthPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class AvaAiNotionService {

	private static final Logger log = LoggerFactory.getLogger(AvaAiNotionService.class);
	private static final String NOTION_BASE_URL = "https://api.notion.com/v1";
	private static final Pattern MUTATION_DIRECTIVE_PATTERN = Pattern.compile(
		"(추가|작성|등록|넣어|생성|만들|삭제|지워|제거)\\s*(해줘|해주세요|해 주세요|해|하세요|해라|해놔|해 둬|해두|하기|$)"
			+ "|\\b(add|append|create|write|insert|delete|remove|archive)\\b",
		Pattern.CASE_INSENSITIVE
	);
	private static final Pattern NON_MUTATION_FOLLOW_UP_PATTERN = Pattern.compile(
		"(방금|아까|추가한|작성한|등록한|넣은|생성한|어디|뭐|무엇|왜|어떻게|라는거|라는 거|아니고|하라는게|하라는 게|말한거|말한 거)"
	);
	private static final List<String> MUTATION_MARKERS = List.of(
		"추가해줘", "추가해", "추가", "작성해줘", "작성해", "작성", "등록해줘", "등록", "넣어줘", "넣어",
		"만들", "생성", "기록", "업데이트", "삭제해줘", "삭제해", "삭제", "지워줘", "지워", "제거해줘", "제거",
		"add", "append", "create", "write", "insert", "update", "delete", "remove", "archive"
	);
	private static final int MAX_SEARCH_RESULTS = 100;
	private static final int MAX_SEARCH_PAGES = 5;
	private static final int MAX_BLOCKS = 120;
	private static final int MAX_DATABASE_ROWS = 100;
	private static final int MAX_DATABASE_PAGES = 10;
	private static final int MAX_BLOCK_DEPTH = 4;
	private static final Duration READ_CACHE_TTL = Duration.ofSeconds(120);
	private static final Duration LAST_MUTATION_TTL = Duration.ofHours(6);
	private static final List<String> TEAMS_GALLERY_ORDER = List.of(
		"연구소(협업:포리버)",
		"제조(코어)",
		"출고",
		"제조(메인)",
		"A/S",
		"경영지원",
		"Formi",
		"RA"
	);

	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;
	private final String token;
	private final String dataApiVersion;
	private final String fileApiVersion;
	private final String researchPageId;
	private final String developmentStatusDatabaseId;
	private final Duration timeout;
	private final Map<String, CacheEntry<JsonNode>> readCache = new ConcurrentHashMap<>();
	private final Map<UUID, LastNotionMutation> lastMutations = new ConcurrentHashMap<>();

	private record CacheEntry<T>(T value, Instant expiresAt) {
		boolean fresh(Instant now) {
			return expiresAt.isAfter(now);
		}
	}

	private record NotionDateRange(LocalDate startDate, LocalDate endDate) {
	}

	private record FoundDate(int position, LocalDate date) {
	}

	private record NotionMutationPlan(
		String title,
		NotionDateRange dateRange,
		String targetQuery,
		AvaAiNotionPageResponse target,
		NotionMutationType type,
		String action
	) {
	}

	private enum NotionMutationType {
		CREATE,
		DELETE
	}

	private record LastNotionMutation(
		String title,
		String status,
		String targetTitle,
		String targetId,
		String pageId,
		String url,
		Instant createdAt
	) {
	}

	public AvaAiNotionService(
		ObjectMapper objectMapper,
		@Value("${ava.ai.notion.token:}") String token,
		@Value("${ava.ai.notion.data-api-version:2022-06-28}") String dataApiVersion,
		@Value("${ava.ai.notion.file-api-version:2026-03-11}") String fileApiVersion,
		@Value("${ava.ai.notion.research-page-id:}") String researchPageId,
		@Value("${ava.ai.notion.development-status-database-id:}") String developmentStatusDatabaseId,
		@Value("${ava.ai.notion.timeout-seconds:25}") long timeoutSeconds
	) {
		this.objectMapper = objectMapper;
		this.token = token == null ? "" : token.strip();
		this.dataApiVersion = dataApiVersion == null || dataApiVersion.isBlank() ? "2022-06-28" : dataApiVersion.strip();
		this.fileApiVersion = fileApiVersion == null || fileApiVersion.isBlank() ? "2026-03-11" : fileApiVersion.strip();
		this.researchPageId = normalizeId(researchPageId);
		this.developmentStatusDatabaseId = normalizeId(developmentStatusDatabaseId);
		this.timeout = Duration.ofSeconds(Math.max(5, timeoutSeconds));
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(Math.min(Math.max(5, timeoutSeconds), 15)))
			.followRedirects(HttpClient.Redirect.NORMAL)
			.build();
		log.info(
			"Notion routing configured. researchPageId={}, developmentStatusDatabaseId={}",
			this.researchPageId.isBlank() ? "<blank>" : this.researchPageId,
			this.developmentStatusDatabaseId.isBlank() ? "<blank>" : this.developmentStatusDatabaseId
		);
	}

	public boolean enabled() {
		return !token.isBlank();
	}

	public AvaAiNotionCommandResponse command(AvaAiNotionCommandRequest request, AuthPrincipal principal) {
		requireToken();
		String command = request == null || request.command() == null ? "" : request.command().strip();
		String activePageId = request == null || request.activePageId() == null ? "" : normalizeId(request.activePageId());
		String activePageObject = request == null || request.activePageObject() == null
			? ""
			: request.activePageObject().strip().toLowerCase(Locale.ROOT);
		boolean approved = request != null && request.approved();
		if (command.isBlank()) {
			List<AvaAiNotionPageResponse> roots = search("");
			return new AvaAiNotionCommandResponse(
				"Notion 작업공간을 불러왔습니다.",
				"Notion 연결 완료",
				firstOrNull(roots),
				roots,
				false,
				"",
				"",
				"direct-api/read"
			);
		}
		if (isLastMutationQuestion(command)) {
			Optional<LastNotionMutation> last = lastMutation(principal);
			if (last.isPresent()) {
				LastNotionMutation mutation = last.get();
				String status = mutation.status().isBlank() ? "" : " / 상태: " + mutation.status();
				return new AvaAiNotionCommandResponse(
					"방금 반영한 항목은 `" + mutation.targetTitle() + "`에 있습니다.\n"
						+ "항목: " + mutation.title() + status + "\n"
						+ "링크: " + mutation.url(),
					mutation.targetTitle() + " > " + mutation.title(),
					open(mutation.pageId(), "page"),
					List.of(open(mutation.pageId(), "page")),
					false,
					"",
					"",
					"direct-api/last-write-summary"
				);
			}
			if (!activePageId.isBlank()) {
				AvaAiNotionPageResponse active = open(activePageId, activePageObject);
				return new AvaAiNotionCommandResponse(
					"현재 선택된 Notion 항목은 `" + active.title() + "`입니다. 방금 쓰기 이력은 서버 재시작 이후 메모리에 남아 있지 않아 정확한 부모 위치는 다시 확인이 필요합니다.",
					"현재 Notion 항목: " + active.title(),
					active,
					List.of(active),
					false,
					"",
					"",
					"direct-api/active-page-summary"
				);
			}
		}
		if (isClarificationOnly(command)) {
			AvaAiNotionPageResponse active = activePageId.isBlank() ? null : open(activePageId, activePageObject);
			return new AvaAiNotionCommandResponse(
				"정정으로 이해했습니다. 새 Notion 항목을 만들거나 수정하지 않았습니다. 이어서 처리할 정확한 제목, 날짜, 상태를 다시 말해주면 승인 전에 대상과 값을 먼저 보여드리겠습니다.",
				"Notion 정정 대기",
				active,
				active == null ? List.of() : List.of(active),
				false,
				"",
				"",
				"direct-api/clarification"
			);
		}
		if (isMutationCommand(command)) {
			NotionMutationPlan plan = mutationPlan(command, activePageId, activePageObject);
			if (!approved) {
				return new AvaAiNotionCommandResponse(
					"Notion 쓰기 작업은 승인 후 실행합니다.",
					"Notion 쓰기 승인 대기",
					plan.target(),
					List.of(plan.target()),
					true,
					"Notion 작업 승인",
					approvalDescription(command, plan),
					"mcp-style-plan/approval-required"
				);
			}
			AvaAiNotionPageResponse created = executeMutation(command, plan);
			verifyCreatedMutation(plan, created);
			rememberMutation(principal, plan, created, command);
			return new AvaAiNotionCommandResponse(
				writeApprovedAnswer(plan, created),
				created.title() + " 항목을 Notion에 추가했습니다.",
				created,
				List.of(created),
				false,
				"",
				"",
				"direct-api/write-approved"
			);
		}
		List<AvaAiNotionPageResponse> results = search(searchQueryFrom(command));
		AvaAiNotionPageResponse active = results.isEmpty() ? null : open(results.getFirst().id(), results.getFirst().object());
		return new AvaAiNotionCommandResponse(
			results.isEmpty() ? "관련 Notion 문서를 찾지 못했습니다." : results.size() + "개의 Notion 결과를 찾았습니다.",
			results.isEmpty() ? "검색 결과 없음" : "Notion 검색 결과 " + results.size() + "개",
			active,
			results,
			false,
			"",
			"",
			"direct-api/natural-language-search"
		);
	}

	private void verifyCreatedMutation(NotionMutationPlan plan, AvaAiNotionPageResponse created) {
		if (created == null) {
			throw new IllegalStateException("Notion write verification failed: result page is missing.");
		}
		if (created.id() == null || created.id().isBlank()) {
			throw new IllegalStateException("Notion write verification failed: result page id is missing.");
		}
		if (created.title() == null || !compactTargetText(created.title()).contains(compactTargetText(plan.title()))) {
			throw new IllegalStateException("Notion write verification failed: result title mismatch.");
		}
		if (created.url() == null || created.url().isBlank()) {
			throw new IllegalStateException("Notion write verification failed: result page url is missing.");
		}
	}

	private String writeApprovedAnswer(NotionMutationPlan plan, AvaAiNotionPageResponse created) {
		if (plan.type() == NotionMutationType.DELETE) {
			return String.join("\n",
				"Notion 항목을 삭제 처리하고 다시 열어 검증했습니다.",
				"대상: " + plan.target().title(),
				"제목: " + created.title(),
				"URL: " + created.url()
			);
		}
		String status = created.properties().stream()
			.filter(property -> property.type().equals("status"))
			.map(AvaAiNotionPropertyResponse::value)
			.findFirst()
			.orElse("");
		return String.join("\n",
			"Notion에 반영하고 다시 열어 검증했습니다.",
			"대상: " + plan.target().title(),
			"제목: " + created.title(),
			status.isBlank() ? "상태: 확인된 상태 속성 없음" : "상태: " + status,
			"URL: " + created.url()
		);
	}

	public List<AvaAiNotionPageResponse> search(String query) {
		requireToken();
		String normalized = query == null ? "" : query.strip();
		Map<String, AvaAiNotionPageResponse> items = new LinkedHashMap<>();
		String cursor = "";
		int pages = 0;
		boolean hasMore;
		do {
			Map<String, Object> payload = new LinkedHashMap<>();
			if (!normalized.isBlank()) {
				payload.put("query", normalized);
			}
			payload.put("page_size", MAX_SEARCH_RESULTS);
			if (!cursor.isBlank()) {
				payload.put("start_cursor", cursor);
			}
			JsonNode root = cachedRequestJson("POST", "/search", payload, dataApiVersion);
			for (JsonNode item : iterable(root.path("results"))) {
				String object = item.path("object").asText("");
				if (!object.equals("page") && !object.equals("database")) {
					continue;
				}
				AvaAiNotionPageResponse summary = summary(item);
				items.putIfAbsent(summary.id(), summary);
			}
			cursor = root.path("next_cursor").asText("");
			hasMore = root.path("has_more").asBoolean(false) && !cursor.isBlank();
			pages++;
		} while (hasMore && pages < MAX_SEARCH_PAGES);
		List<AvaAiNotionPageResponse> results = new ArrayList<>(items.values());
		results.sort(Comparator.comparing(AvaAiNotionPageResponse::updatedAt, Comparator.nullsLast(Comparator.reverseOrder())));
		return results;
	}

	public AvaAiNotionPageResponse open(String id, String object) {
		requireToken();
		String normalizedId = normalizeId(id);
		String normalizedObject = object == null ? "" : object.strip().toLowerCase(Locale.ROOT);
		if (normalizedObject.equals("database")) {
			return database(normalizedId);
		}
		JsonNode page = cachedRequestJson("GET", "/pages/" + url(normalizedId), null, dataApiVersion);
		List<AvaAiNotionBlockResponse> blocks = blocks(normalizedId);
		return withBlocks(summary(page), blocks, List.of());
	}

	public AvaAiNotionCommandResponse upload(
		String targetId,
		List<MultipartFile> files,
		boolean approved,
		AuthPrincipal principal
	) {
		requireToken();
		if (!approved) {
			throw new IllegalArgumentException("Notion 파일 첨부는 사용자 승인 후 실행할 수 있습니다.");
		}
		String normalizedTarget = normalizeId(targetId);
		if (normalizedTarget.isBlank()) {
			throw new IllegalArgumentException("Notion 파일을 붙일 페이지를 먼저 선택해주세요.");
		}
		if (files == null || files.isEmpty()) {
			throw new IllegalArgumentException("업로드할 파일이 없습니다.");
		}
		List<AvaAiNotionBlockResponse> added = new ArrayList<>();
		for (MultipartFile file : files) {
			if (file == null || file.isEmpty()) {
				continue;
			}
			String fileUploadId = uploadFile(file);
			added.add(appendFileBlock(normalizedTarget, file.getOriginalFilename(), file.getContentType(), fileUploadId));
		}
		AvaAiNotionPageResponse active = open(normalizedTarget, "page");
		return new AvaAiNotionCommandResponse(
			added.size() + "개 파일을 Notion 페이지에 첨부했습니다.",
			"Notion 파일 첨부 완료",
			active,
			List.of(active),
			false,
			"",
			"",
			"direct-api/file-upload-approved"
		);
	}

	private NotionMutationPlan mutationPlan(String command, String activePageId, String activePageObject) {
		NotionDateRange dateRange = extractDateRange(command);
		String targetQuery = targetQueryFrom(command);
		NotionMutationType type = mutationType(command);
		Optional<AvaAiNotionPageResponse> configuredTarget = configuredDatabaseTarget(command, targetQuery);
		if (configuredTarget.isPresent()) {
			AvaAiNotionPageResponse target = configuredTarget.get();
			String title = mutationTitle(command, target.title(), targetQuery);
			return new NotionMutationPlan(title, dateRange, targetQuery, target, type, actionName(type, target));
		}
		List<AvaAiNotionPageResponse> candidates = search(targetQuery);
		if (candidates.isEmpty()) {
			String fallbackQuery = searchQueryFrom(command);
			if (!fallbackQuery.equals(targetQuery)) {
				candidates = search(fallbackQuery);
			}
		}
		AvaAiNotionPageResponse databaseTarget = candidates.stream()
			.filter(candidate -> candidate.object().equals("database"))
			.findFirst()
			.orElse(null);
		AvaAiNotionPageResponse target = databaseTarget != null
			? databaseTarget
			: (activePageId.isBlank()
				? firstOrNull(candidates)
				: new AvaAiNotionPageResponse(
					activePageId,
					activePageObject.equals("database") ? "database" : "page",
					"현재 Notion 대상",
					"",
					"",
					"",
					"",
					"",
					null,
					List.of(),
					List.of(),
					List.of()
				));
		if (target == null) {
			throw new IllegalArgumentException("추가할 Notion 페이지 또는 데이터베이스를 찾지 못했습니다.");
		}
		String title = mutationTitle(command, target.title(), targetQuery);
		return new NotionMutationPlan(title, dateRange, targetQuery, target, type, actionName(type, target));
	}

	private NotionMutationType mutationType(String command) {
		String normalized = command == null ? "" : command.toLowerCase(Locale.ROOT);
		if (normalized.contains("삭제")
			|| normalized.contains("지워")
			|| normalized.contains("제거")
			|| normalized.contains("delete")
			|| normalized.contains("remove")
			|| normalized.contains("archive")) {
			return NotionMutationType.DELETE;
		}
		return NotionMutationType.CREATE;
	}

	private String actionName(NotionMutationType type, AvaAiNotionPageResponse target) {
		if (type == NotionMutationType.DELETE) {
			return target.object().equals("database") ? "데이터베이스 항목 삭제" : "페이지 삭제";
		}
		return target.object().equals("database") ? "데이터베이스 새 항목 생성" : "페이지에 문단 추가";
	}

	private Optional<AvaAiNotionPageResponse> configuredDatabaseTarget(String command, String targetQuery) {
		String normalized = compactTargetText((command == null ? "" : command) + " " + (targetQuery == null ? "" : targetQuery));
		if (normalized.contains("개발진행사항") && !developmentStatusDatabaseId.isBlank()) {
			return Optional.of(database(developmentStatusDatabaseId, false));
		}
		return researchChildDatabaseTarget(command, targetQuery);
	}

	private Optional<AvaAiNotionPageResponse> researchChildDatabaseTarget(String command, String targetQuery) {
		if (researchPageId.isBlank()) {
			return Optional.empty();
		}
		String combined = compactTargetText((command == null ? "" : command) + " " + (targetQuery == null ? "" : targetQuery));
		if (!combined.contains("연구소")) {
			return Optional.empty();
		}
		return childDatabases(researchPageId).stream()
			.filter(database -> databaseTitleMatches(database.title(), command, targetQuery))
			.findFirst();
	}

	private List<AvaAiNotionPageResponse> childDatabases(String pageId) {
		List<AvaAiNotionPageResponse> databases = new ArrayList<>();
		collectChildDatabases(blocks(pageId), databases);
		return databases;
	}

	private void collectChildDatabases(List<AvaAiNotionBlockResponse> blocks, List<AvaAiNotionPageResponse> databases) {
		for (AvaAiNotionBlockResponse block : blocks) {
			if (block.database() != null) {
				databases.add(block.database());
			}
			if (block.children() != null && !block.children().isEmpty()) {
				collectChildDatabases(block.children(), databases);
			}
		}
	}

	private boolean databaseTitleMatches(String databaseTitle, String command, String targetQuery) {
		String title = compactTargetText(databaseTitle);
		if (title.isBlank()) {
			return false;
		}
		String combined = compactTargetText((command == null ? "" : command) + " " + (targetQuery == null ? "" : targetQuery));
		if (combined.contains(title)) {
			return true;
		}
		if (title.equals("개발진행사항")) {
			return combined.contains("developmentstatus")
				|| combined.contains("devstatus")
				|| combined.contains("개발상태");
		}
		if (title.equals("인증진행상황")) {
			return combined.contains("certificationstatus") || combined.contains("인증상태");
		}
		return false;
	}

	private AvaAiNotionPageResponse executeMutation(String command, NotionMutationPlan plan) {
		if (plan.type() == NotionMutationType.DELETE) {
			return deleteNotionTarget(plan);
		}
		if (plan.target().object().equals("database")) {
			return createDatabasePage(plan.target().id(), plan.title(), command, plan.dateRange());
		}
		appendParagraph(plan.target().id(), command);
		return open(plan.target().id(), "page");
	}

	private String approvalDescription(String command, NotionMutationPlan plan) {
		String startDate = plan.dateRange().startDate() == null ? "없음" : plan.dateRange().startDate().toString();
		String dueDate = plan.dateRange().endDate() == null ? "없음" : plan.dateRange().endDate().toString();
		List<String> lines = new ArrayList<>(List.of(
			"실행 방식: 직접 Notion API",
			"대상: " + plan.target().title() + " (" + plan.target().object() + ")",
			"작업: " + plan.action(),
			"제목: " + plan.title()
		));
		if (plan.type() == NotionMutationType.CREATE) {
			String status = plannedStatus(command, plan).orElse("명령에서 확인 안 됨");
			lines.add("상태: " + status);
			lines.add("시작일: " + startDate);
			lines.add("종료일: " + dueDate);
		} else {
			lines.add("삭제 방식: Notion 항목 보관 처리(archive)");
		}
		lines.add("명령: " + command);
		return String.join("\n", lines);
	}

	private Optional<String> plannedStatus(String command, NotionMutationPlan plan) {
		if (!plan.target().object().equals("database")) {
			return statusCandidates(command).stream().findFirst();
		}
		try {
			JsonNode database = cachedRequestJson("GET", "/databases/" + url(plan.target().id()), null, dataApiVersion);
			JsonNode properties = database.path("properties");
			return firstPropertyOfType(properties, "status").flatMap(name -> statusOption(properties.path(name), command));
		} catch (RuntimeException exception) {
			return statusCandidates(command).stream().findFirst();
		}
	}

	private AvaAiNotionPageResponse createDatabasePage(String databaseId, String title, String command, NotionDateRange dateRange) {
		JsonNode database = cachedRequestJson("GET", "/databases/" + url(databaseId), null, dataApiVersion);
		JsonNode properties = database.path("properties");
		String titleProperty = firstPropertyOfType(properties, "title").orElse("Name");
		Map<String, Object> pageProperties = new LinkedHashMap<>();
		pageProperties.put(titleProperty, Map.of(
			"title", List.of(Map.of("text", Map.of("content", title)))
		));
		putDateProperties(properties, pageProperties, dateRange);
		firstPropertyOfType(properties, "status").ifPresent(name ->
			statusOption(properties.path(name), command).ifPresent(status ->
				pageProperties.put(name, Map.of("status", Map.of("name", status)))
			)
		);
		Map<String, Object> payload = new LinkedHashMap<>();
		payload.put("parent", Map.of("database_id", databaseId));
		payload.put("properties", pageProperties);
		payload.put("children", List.of(paragraphBlock(command)));
		JsonNode created = requestJson("POST", "/pages", payload, dataApiVersion);
		clearReadCaches();
		return open(created.path("id").asText(databaseId), "page");
	}

	private AvaAiNotionPageResponse deleteNotionTarget(NotionMutationPlan plan) {
		if (plan.target().object().equals("database")) {
			AvaAiNotionPageResponse row = findDatabaseRowByTitle(plan.target().id(), plan.title())
				.orElseThrow(() -> new IllegalArgumentException(
					"삭제할 Notion 항목을 찾지 못했습니다. 대상: " + plan.target().title() + ", 제목: " + plan.title()
				));
			archivePage(row.id());
			return open(row.id(), "page");
		}
		String pageId = plan.target().id();
		archivePage(pageId);
		return open(pageId, "page");
	}

	private Optional<AvaAiNotionPageResponse> findDatabaseRowByTitle(String databaseId, String title) {
		String expected = compactTargetText(title);
		if (expected.isBlank()) {
			return Optional.empty();
		}
		List<AvaAiNotionPageResponse> rows = databaseRows(databaseId);
		Optional<AvaAiNotionPageResponse> exact = rows.stream()
			.filter(row -> compactTargetText(row.title()).equals(expected))
			.findFirst();
		if (exact.isPresent()) {
			return exact;
		}
		return rows.stream()
			.filter(row -> {
				String actual = compactTargetText(row.title());
				return actual.contains(expected) || expected.contains(actual);
			})
			.findFirst();
	}

	private void archivePage(String pageId) {
		requestJson("PATCH", "/pages/" + url(pageId), Map.of("archived", true), dataApiVersion);
		clearReadCaches();
	}

	private void putDateProperties(JsonNode properties, Map<String, Object> pageProperties, NotionDateRange dateRange) {
		if (dateRange == null || (dateRange.startDate() == null && dateRange.endDate() == null)) {
			return;
		}
		Set<String> assigned = new HashSet<>();
		properties.fields().forEachRemaining(entry -> {
			if (!entry.getValue().path("type").asText("").equals("date")) {
				return;
			}
			String compactName = compactTargetText(entry.getKey());
			if (dateRange.startDate() != null && (compactName.contains("시작") || compactName.contains("start"))) {
				pageProperties.put(entry.getKey(), datePayload(dateRange.startDate()));
				assigned.add(entry.getKey());
				return;
			}
			if (dateRange.endDate() != null && (compactName.contains("종료")
				|| compactName.contains("마감")
				|| compactName.contains("기한")
				|| compactName.contains("end")
				|| compactName.contains("due"))) {
				pageProperties.put(entry.getKey(), datePayload(dateRange.endDate()));
				assigned.add(entry.getKey());
			}
		});
		if (assigned.isEmpty()) {
			firstPropertyOfType(properties, "date").ifPresent(name -> {
				pageProperties.put(name, dateRangePayload(dateRange));
			});
		}
	}

	private Map<String, Object> datePayload(LocalDate date) {
		return Map.of("date", Map.of("start", date.toString()));
	}

	private Map<String, Object> dateRangePayload(NotionDateRange dateRange) {
		LocalDate start = dateRange.startDate() != null ? dateRange.startDate() : dateRange.endDate();
		LocalDate end = dateRange.endDate();
		Map<String, Object> date = new LinkedHashMap<>();
		date.put("start", start.toString());
		if (end != null && !end.equals(start)) {
			date.put("end", end.toString());
		}
		return Map.of("date", date);
	}

	private void appendParagraph(String pageId, String command) {
		Map<String, Object> payload = Map.of("children", List.of(paragraphBlock(command)));
		requestJson("PATCH", "/blocks/" + url(pageId) + "/children", payload, dataApiVersion);
		clearReadCaches();
	}

	private AvaAiNotionBlockResponse appendFileBlock(String pageId, String fileName, String contentType, String fileUploadId) {
		String type = blockFileType(fileName, contentType);
		Map<String, Object> fileObject = Map.of(
			"type", "file_upload",
			"file_upload", Map.of("id", fileUploadId)
		);
		Map<String, Object> block = Map.of("type", type, type, fileObject);
		requestJson("PATCH", "/blocks/" + url(pageId) + "/children", Map.of("children", List.of(block)), fileApiVersion);
		clearReadCaches();
		return new AvaAiNotionBlockResponse(fileUploadId, type, safeFileName(fileName), 0, false, "", "", "", List.of(), List.of(), null);
	}

	private String uploadFile(MultipartFile file) {
		try {
			JsonNode created = requestJson("POST", "/file_uploads", Map.of(), fileApiVersion);
			String id = created.path("id").asText("");
			if (id.isBlank()) {
				throw new IllegalStateException("Notion file upload id is empty.");
			}
			HttpRequest request = HttpRequest.newBuilder(URI.create(NOTION_BASE_URL + "/file_uploads/" + url(id) + "/send"))
				.timeout(timeout)
				.header("Authorization", "Bearer " + token)
				.header("Notion-Version", fileApiVersion)
				.header("Content-Type", "multipart/form-data; boundary=" + id)
				.POST(HttpRequest.BodyPublishers.ofByteArray(multipartBody(id, file)))
				.build();
			HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
			if (response.statusCode() < 200 || response.statusCode() >= 300) {
				throw new IllegalStateException("Notion file upload failed: " + response.statusCode() + " " + response.body());
			}
			return id;
		} catch (IOException exception) {
			throw new IllegalStateException("Notion file upload failed.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			throw new IllegalStateException("Notion file upload interrupted.", exception);
		}
	}

	private byte[] multipartBody(String boundary, MultipartFile file) throws IOException {
		ByteArrayOutputStream out = new ByteArrayOutputStream();
		String fileName = safeFileName(file.getOriginalFilename());
		String contentType = file.getContentType() == null || file.getContentType().isBlank()
			? "application/octet-stream"
			: file.getContentType();
		out.write(("--" + boundary + "\r\n").getBytes(StandardCharsets.UTF_8));
		out.write(("Content-Disposition: form-data; name=\"file\"; filename=\"" + fileName.replace("\"", "") + "\"\r\n").getBytes(StandardCharsets.UTF_8));
		out.write(("Content-Type: " + contentType + "\r\n\r\n").getBytes(StandardCharsets.UTF_8));
		out.write(file.getBytes());
		out.write(("\r\n--" + boundary + "--\r\n").getBytes(StandardCharsets.UTF_8));
		return out.toByteArray();
	}

	private AvaAiNotionPageResponse database(String databaseId) {
		return database(databaseId, true);
	}

	private AvaAiNotionPageResponse database(String databaseId, boolean includeBlocks) {
		CompletableFuture<JsonNode> databaseFuture = CompletableFuture.supplyAsync(() ->
			cachedRequestJson("GET", "/databases/" + url(databaseId), null, dataApiVersion)
		);
		CompletableFuture<List<AvaAiNotionPageResponse>> rowsFuture = CompletableFuture.supplyAsync(() ->
			databaseRows(databaseId)
		);
		CompletableFuture<List<AvaAiNotionBlockResponse>> blocksFuture = includeBlocks
			? CompletableFuture.supplyAsync(() -> blocks(databaseId))
			: CompletableFuture.completedFuture(List.of());
		JsonNode database = join(databaseFuture);
		List<AvaAiNotionPageResponse> rows = join(rowsFuture);
		if (title(database).equalsIgnoreCase("Teams")) {
			rows.sort(Comparator
				.comparingInt((AvaAiNotionPageResponse row) -> teamGalleryOrder(row.title()))
				.thenComparing(AvaAiNotionPageResponse::title, Comparator.nullsLast(String::compareToIgnoreCase)));
		}
		List<AvaAiNotionBlockResponse> pageBlocks = join(blocksFuture);
		return withBlocks(summary(database), pageBlocks, rows);
	}

	private List<AvaAiNotionPageResponse> databaseRows(String databaseId) {
		Map<String, AvaAiNotionPageResponse> rows = new LinkedHashMap<>();
		String cursor = "";
		int pages = 0;
		boolean hasMore;
		do {
			Map<String, Object> payload = new LinkedHashMap<>();
			payload.put("page_size", MAX_DATABASE_ROWS);
			if (!cursor.isBlank()) {
				payload.put("start_cursor", cursor);
			}
			JsonNode query = cachedRequestJson("POST", "/databases/" + url(databaseId) + "/query", payload, dataApiVersion);
			for (JsonNode row : iterable(query.path("results"))) {
				AvaAiNotionPageResponse summary = summary(row);
				rows.putIfAbsent(summary.id(), summary);
			}
			cursor = query.path("next_cursor").asText("");
			hasMore = query.path("has_more").asBoolean(false) && !cursor.isBlank();
			pages++;
		} while (hasMore && pages < MAX_DATABASE_PAGES);
		return new ArrayList<>(rows.values());
	}

	private List<AvaAiNotionBlockResponse> blocks(String pageId) {
		return blocks(pageId, 0);
	}

	private List<AvaAiNotionBlockResponse> blocks(String pageId, int depth) {
		if (depth > MAX_BLOCK_DEPTH) {
			return List.of();
		}
		JsonNode root = cachedRequestJson("GET", "/blocks/" + url(pageId) + "/children?page_size=" + MAX_BLOCKS, null, dataApiVersion);
		List<AvaAiNotionBlockResponse> blocks = new ArrayList<>();
		String contextHeading = "";
		for (JsonNode block : iterable(root.path("results"))) {
			AvaAiNotionBlockResponse parsed = block(block, depth, contextHeading);
			blocks.add(parsed);
			if (parsed.type().startsWith("heading_") && !parsed.text().isBlank()) {
				contextHeading = parsed.text();
			}
		}
		return blocks;
	}

	private AvaAiNotionBlockResponse block(JsonNode node, int depth, String contextHeading) {
		String id = node.path("id").asText("");
		String type = node.path("type").asText("");
		JsonNode data = node.path(type);
		String text = switch (type) {
			case "child_page", "child_database" -> data.path("title").asText("");
			case "bookmark", "embed", "link_preview" -> data.path("url").asText("");
			case "divider" -> "";
			default -> richText(data.path("rich_text"));
		};
		boolean checked = type.equals("to_do") && data.path("checked").asBoolean(false);
		String url = blockUrl(type, data);
		if (url.isBlank()) {
			url = richTextUrl(data.path("rich_text"));
		}
		String icon = icon(data.path("icon"));
		String color = data.path("color").asText("");
		List<List<String>> cells = new ArrayList<>();
		if (type.equals("table_row")) {
			for (JsonNode cell : iterable(data.path("cells"))) {
				cells.add(List.of(richText(cell)));
			}
		}
		List<AvaAiNotionBlockResponse> children = node.path("has_children").asBoolean(false)
			&& !type.equals("child_database")
			? blocks(id, depth + 1)
			: List.of();
		AvaAiNotionPageResponse database = type.equals("child_database")
			? childDatabase(id, text, contextHeading)
			: null;
		return new AvaAiNotionBlockResponse(id, type, text, depth, checked, url, icon, color, cells, children, database);
	}

	private AvaAiNotionPageResponse summary(JsonNode node) {
		String object = node.path("object").asText("page");
		String title = title(node);
		String id = node.path("id").asText("");
		String url = node.path("url").asText("");
		String icon = icon(node.path("icon"));
		String coverUrl = fileUrl(node.path("cover"));
		Instant updatedAt = instant(node.path("last_edited_time").asText(""));
		String subtitle = object.equals("database") ? "Database" : parentSubtitle(node.path("parent"));
		List<AvaAiNotionPropertyResponse> properties = properties(node.path("properties"), object.equals("database"));
		String content = propertyContent(properties);
		return new AvaAiNotionPageResponse(id, object, title.isBlank() ? "Untitled" : title, subtitle, url, icon, coverUrl, content, updatedAt, properties, List.of(), List.of());
	}

	private AvaAiNotionPageResponse withBlocks(
		AvaAiNotionPageResponse item,
		List<AvaAiNotionBlockResponse> blocks,
		List<AvaAiNotionPageResponse> children
	) {
		return new AvaAiNotionPageResponse(
			item.id(),
			item.object(),
			item.title(),
			item.subtitle(),
			item.url(),
			item.icon(),
			item.coverUrl(),
			item.content(),
			item.updatedAt(),
			item.properties(),
			blocks,
			children
		);
	}

	private Map<String, Object> paragraphBlock(String text) {
		return Map.of(
			"type", "paragraph",
			"paragraph", Map.of("rich_text", List.of(Map.of("text", Map.of("content", text))))
		);
	}

	private String title(JsonNode node) {
		if (node.path("object").asText("").equals("database")) {
			return richText(node.path("title"));
		}
		JsonNode properties = node.path("properties");
		if (!properties.isObject()) {
			return "";
		}
		var fields = properties.fields();
		while (fields.hasNext()) {
			var entry = fields.next();
			JsonNode property = entry.getValue();
			if (property.path("type").asText("").equals("title")) {
				return richText(property.path("title"));
			}
		}
		return "";
	}

	private String richText(JsonNode nodes) {
		if (!nodes.isArray()) {
			return "";
		}
		StringBuilder builder = new StringBuilder();
		for (JsonNode item : nodes) {
			String value = item.path("plain_text").asText("");
			if (value.isBlank()) {
				value = item.path("text").path("content").asText("");
			}
			builder.append(value);
		}
		return builder.toString().strip();
	}

	private String richTextUrl(JsonNode nodes) {
		if (!nodes.isArray()) {
			return "";
		}
		for (JsonNode item : nodes) {
			String href = item.path("href").asText("");
			if (!href.isBlank()) {
				return href;
			}
			String link = item.path("text").path("link").path("url").asText("");
			if (!link.isBlank()) {
				return link;
			}
		}
		return "";
	}

	private Optional<String> firstPropertyOfType(JsonNode properties, String type) {
		if (!properties.isObject()) {
			return Optional.empty();
		}
		var fields = properties.fields();
		while (fields.hasNext()) {
			var entry = fields.next();
			if (entry.getValue().path("type").asText("").equals(type)) {
				return Optional.of(entry.getKey());
			}
		}
		return Optional.empty();
	}

	private List<AvaAiNotionPropertyResponse> properties(JsonNode properties, boolean schemaOnly) {
		if (!properties.isObject()) {
			return List.of();
		}
		List<AvaAiNotionPropertyResponse> values = new ArrayList<>();
		var fields = properties.fields();
		while (fields.hasNext()) {
			var entry = fields.next();
			String type = entry.getValue().path("type").asText("");
			if (type.equals("title")) {
				continue;
			}
			String value = schemaOnly
				? schemaPropertyValue(entry.getValue(), type)
				: notionPropertyValue(entry.getValue(), type);
			String color = propertyColor(entry.getValue(), type);
			if (!value.isBlank() || schemaOnly) {
				values.add(new AvaAiNotionPropertyResponse(entry.getKey(), type, value, color));
			}
		}
		return values;
	}

	private String propertyContent(List<AvaAiNotionPropertyResponse> properties) {
		if (properties == null || properties.isEmpty()) {
			return "";
		}
		List<String> values = new ArrayList<>();
		for (AvaAiNotionPropertyResponse property : properties) {
			if (values.size() >= 12) {
				break;
			}
			if (!property.value().isBlank()) {
				values.add(property.name() + ": " + property.value());
			}
		}
		return String.join("\n", values);
	}

	private String schemaPropertyValue(JsonNode property, String type) {
		return switch (type) {
			case "select" -> options(property.path("select").path("options"));
			case "multi_select" -> options(property.path("multi_select").path("options"));
			case "status" -> options(property.path("status").path("options"));
			default -> type;
		};
	}

	private String notionPropertyValue(JsonNode property, String type) {
		return switch (type) {
			case "title" -> richText(property.path("title"));
			case "rich_text" -> richText(property.path("rich_text"));
			case "select" -> property.path("select").path("name").asText("");
			case "multi_select" -> names(property.path("multi_select"));
			case "status" -> property.path("status").path("name").asText("");
			case "date" -> dateValue(property.path("date"));
			case "number" -> property.path("number").isNumber() ? property.path("number").asText("") : "";
			case "checkbox" -> property.path("checkbox").asBoolean(false) ? "true" : "";
			case "url" -> property.path("url").asText("");
			case "email" -> property.path("email").asText("");
			case "phone_number" -> property.path("phone_number").asText("");
			case "people" -> people(property.path("people"));
			case "files" -> files(property.path("files"));
			case "created_time" -> property.path("created_time").asText("");
			case "last_edited_time" -> property.path("last_edited_time").asText("");
			case "verification" -> property.path("verification").path("state").asText("");
			case "relation" -> relation(property.path("relation"));
			case "formula" -> formula(property.path("formula"));
			case "rollup" -> rollup(property.path("rollup"));
			default -> "";
		};
	}

	private String pageProperties(JsonNode properties) {
		if (!properties.isObject()) {
			return "";
		}
		List<String> values = new ArrayList<>();
		var fields = properties.fields();
		while (fields.hasNext() && values.size() < 8) {
			var entry = fields.next();
			String type = entry.getValue().path("type").asText("");
			if (type.equals("title")) {
				continue;
			}
			String value = propertyValue(entry.getValue(), type);
			if (!value.isBlank()) {
				values.add(entry.getKey() + ": " + value);
			}
		}
		return String.join("\n", values);
	}

	private String databaseProperties(JsonNode properties) {
		if (!properties.isObject()) {
			return "";
		}
		List<String> values = new ArrayList<>();
		var fields = properties.fields();
		while (fields.hasNext() && values.size() < 12) {
			var entry = fields.next();
			values.add(entry.getKey() + " · " + entry.getValue().path("type").asText(""));
		}
		return String.join("\n", values);
	}

	private String propertyValue(JsonNode property, String type) {
		return switch (type) {
			case "rich_text" -> richText(property.path("rich_text"));
			case "select" -> property.path("select").path("name").asText("");
			case "status" -> property.path("status").path("name").asText("");
			case "date" -> property.path("date").path("start").asText("");
			case "number" -> property.path("number").isNumber() ? property.path("number").asText("") : "";
			case "checkbox" -> property.path("checkbox").asBoolean(false) ? "true" : "";
			case "url" -> property.path("url").asText("");
			case "email" -> property.path("email").asText("");
			case "phone_number" -> property.path("phone_number").asText("");
			default -> "";
		};
	}

	private String options(JsonNode options) {
		List<String> values = new ArrayList<>();
		for (JsonNode option : iterable(options)) {
			String name = option.path("name").asText("");
			if (!name.isBlank()) {
				values.add(name);
			}
		}
		return String.join(", ", values);
	}

	private String names(JsonNode nodes) {
		List<String> values = new ArrayList<>();
		for (JsonNode node : iterable(nodes)) {
			String name = node.path("name").asText("");
			if (!name.isBlank()) {
				values.add(name);
			}
		}
		return String.join(", ", values);
	}

	private String people(JsonNode nodes) {
		List<String> values = new ArrayList<>();
		for (JsonNode node : iterable(nodes)) {
			String name = node.path("name").asText("");
			if (name.isBlank()) {
				name = node.path("person").path("email").asText("");
			}
			if (!name.isBlank()) {
				values.add(name);
			}
		}
		return String.join(", ", values);
	}

	private String files(JsonNode nodes) {
		List<String> values = new ArrayList<>();
		for (JsonNode node : iterable(nodes)) {
			String name = node.path("name").asText("");
			if (!name.isBlank()) {
				values.add(name);
			}
		}
		return String.join(", ", values);
	}

	private String relation(JsonNode nodes) {
		int count = 0;
		for (JsonNode ignored : iterable(nodes)) {
			count++;
		}
		return count == 0 ? "" : count + " relations";
	}

	private String formula(JsonNode node) {
		String type = node.path("type").asText("");
		return switch (type) {
			case "string" -> node.path("string").asText("");
			case "number" -> node.path("number").isNumber() ? node.path("number").asText("") : "";
			case "boolean" -> node.path("boolean").asBoolean(false) ? "true" : "false";
			case "date" -> dateValue(node.path("date"));
			default -> "";
		};
	}

	private String rollup(JsonNode node) {
		String type = node.path("type").asText("");
		return switch (type) {
			case "number" -> node.path("number").isNumber() ? node.path("number").asText("") : "";
			case "date" -> dateValue(node.path("date"));
			case "array" -> node.path("array").size() + " items";
			default -> "";
		};
	}

	private String dateValue(JsonNode date) {
		if (date == null || date.isMissingNode() || date.isNull()) {
			return "";
		}
		String start = date.path("start").asText("");
		String end = date.path("end").asText("");
		return end.isBlank() ? start : start + " -> " + end;
	}

	private String propertyColor(JsonNode property, String type) {
		return switch (type) {
			case "select" -> property.path("select").path("color").asText("");
			case "status" -> property.path("status").path("color").asText("");
			case "multi_select" -> property.path("multi_select").isArray() && property.path("multi_select").size() > 0
				? property.path("multi_select").get(0).path("color").asText("")
				: "";
			default -> "";
		};
	}

	private String parentSubtitle(JsonNode parent) {
		String type = parent.path("type").asText("");
		if (type.isBlank()) {
			return "Page";
		}
		return switch (type) {
			case "database_id" -> "Database row";
			case "page_id" -> "Page";
			case "workspace" -> "Workspace";
			default -> type;
		};
	}

	private String icon(JsonNode icon) {
		String type = icon.path("type").asText("");
		if (type.equals("emoji")) {
			return icon.path("emoji").asText("");
		}
		return "";
	}

	private String fileUrl(JsonNode file) {
		String type = file.path("type").asText("");
		if (type.equals("external")) {
			return file.path("external").path("url").asText("");
		}
		if (type.equals("file")) {
			return file.path("file").path("url").asText("");
		}
		return "";
	}

	private String blockUrl(String type, JsonNode data) {
		String directUrl = data.path("url").asText("");
		if (!directUrl.isBlank()) {
			return directUrl;
		}
		return switch (type) {
			case "image", "video", "file", "pdf", "audio" -> fileUrl(data);
			default -> "";
		};
	}

	private AvaAiNotionPageResponse childDatabase(String blockId, String blockTitle, String contextHeading) {
		if (blockTitle == null && contextHeading == null) {
			return null;
		}
		try {
			return database(blockId, false);
		} catch (RuntimeException ignored) {
			String query = blockTitle == null || blockTitle.isBlank() || blockTitle.equalsIgnoreCase("Untitled")
				? contextHeading
				: blockTitle;
			if (query == null || query.isBlank()) {
				return null;
			}
			return search(query).stream()
				.filter(item -> item.object().equals("database"))
				.findFirst()
				.map(item -> database(item.id(), false))
				.orElse(null);
		}
	}

	private String blockFileType(String fileName, String contentType) {
		String lowerName = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);
		String lowerType = contentType == null ? "" : contentType.toLowerCase(Locale.ROOT);
		if (lowerType.startsWith("image/") || lowerName.matches(".*\\.(png|jpg|jpeg|gif|webp|bmp)$")) {
			return "image";
		}
		if (lowerType.equals("application/pdf") || lowerName.endsWith(".pdf")) {
			return "pdf";
		}
		if (lowerType.startsWith("video/")) {
			return "video";
		}
		if (lowerType.startsWith("audio/")) {
			return "audio";
		}
		return "file";
	}

	private JsonNode cachedRequestJson(String method, String path, Object body, String version) {
		String key = cacheKey(method, path, body, version);
		Instant now = Instant.now();
		CacheEntry<JsonNode> cached = readCache.get(key);
		if (cached != null && cached.fresh(now)) {
			return cached.value();
		}
		JsonNode value = requestJson(method, path, body, version);
		readCache.put(key, new CacheEntry<>(value, now.plus(READ_CACHE_TTL)));
		return value;
	}

	private String cacheKey(String method, String path, Object body, String version) {
		return method + "\n" + version + "\n" + path + "\n" + (body == null ? "" : body.toString());
	}

	private void clearReadCaches() {
		readCache.clear();
	}

	private <T> T join(CompletableFuture<T> future) {
		try {
			return future.join();
		} catch (CompletionException exception) {
			Throwable cause = exception.getCause();
			if (cause instanceof RuntimeException runtimeException) {
				throw runtimeException;
			}
			throw new IllegalStateException("Notion background request failed.", cause == null ? exception : cause);
		}
	}

	private JsonNode requestJson(String method, String path, Object body, String version) {
		try {
			HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(NOTION_BASE_URL + path))
				.timeout(timeout)
				.header("Authorization", "Bearer " + token)
				.header("Notion-Version", version)
				.header("Accept", "application/json");
			if (body == null) {
				builder.method(method, HttpRequest.BodyPublishers.noBody());
			} else {
				builder.header("Content-Type", "application/json; charset=utf-8")
					.method(method, HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(body), StandardCharsets.UTF_8));
			}
			HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
			if (response.statusCode() < 200 || response.statusCode() >= 300) {
				throw new IllegalStateException("Notion API returned " + response.statusCode() + ": " + response.body());
			}
			return objectMapper.readTree(response.body());
		} catch (IOException exception) {
			throw new IllegalStateException("Notion API request failed.", exception);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			throw new IllegalStateException("Notion API request interrupted.", exception);
		}
	}

	private void requireToken() {
		if (token.isBlank()) {
			throw new IllegalStateException("Notion API token is not configured.");
		}
	}

	private boolean isMutationCommand(String command) {
		String normalized = command == null ? "" : command.strip().toLowerCase(Locale.ROOT);
		if (normalized.isBlank()) {
			return false;
		}
		if (NON_MUTATION_FOLLOW_UP_PATTERN.matcher(normalized).find()
			&& !MUTATION_DIRECTIVE_PATTERN.matcher(normalized).find()) {
			return false;
		}
		if (isClarificationOnly(normalized)) {
			return false;
		}
		return MUTATION_DIRECTIVE_PATTERN.matcher(normalized).find();
	}

	private boolean isClarificationOnly(String command) {
		String normalized = command == null ? "" : command.strip().toLowerCase(Locale.ROOT);
		return normalized.contains("하라는게") || normalized.contains("하라는 게")
			|| normalized.contains("라는거야") || normalized.contains("라는 거야")
			|| normalized.contains("아니고") || normalized.contains("그 말이 아니")
			|| normalized.contains("말귀") || normalized.contains("이해 못");
	}

	private boolean isLastMutationQuestion(String command) {
		String normalized = command == null ? "" : command.strip().toLowerCase(Locale.ROOT);
		if (normalized.isBlank()) {
			return false;
		}
		return (normalized.contains("방금") || normalized.contains("아까") || normalized.contains("추가한")
			|| normalized.contains("작성한") || normalized.contains("등록한"))
			&& (normalized.contains("어디") || normalized.contains("뭐") || normalized.contains("무엇")
				|| normalized.contains("확인") || normalized.contains("?"));
	}

	private Optional<LastNotionMutation> lastMutation(AuthPrincipal principal) {
		if (principal == null || principal.userId() == null) {
			return Optional.empty();
		}
		LastNotionMutation mutation = lastMutations.get(principal.userId());
		if (mutation == null) {
			return Optional.empty();
		}
		if (mutation.createdAt().plus(LAST_MUTATION_TTL).isBefore(Instant.now())) {
			lastMutations.remove(principal.userId());
			return Optional.empty();
		}
		return Optional.of(mutation);
	}

	private void rememberMutation(
		AuthPrincipal principal,
		NotionMutationPlan plan,
		AvaAiNotionPageResponse created,
		String command
	) {
		if (principal == null || principal.userId() == null || created == null) {
			return;
		}
		String status = created.properties().stream()
			.filter(property -> property.type().equals("status"))
			.map(AvaAiNotionPropertyResponse::value)
			.findFirst()
			.orElse("");
		lastMutations.put(principal.userId(), new LastNotionMutation(
			created.title(),
			status,
			plan.target().title(),
			plan.target().id(),
			created.id(),
			created.url(),
			Instant.now()
		));
	}

	private String searchQueryFrom(String command) {
		String query = command == null ? "" : command;
		for (String word : List.of("알려줘", "보여줘", "찾아줘", "검색해줘", "추가해줘", "추가", "작성해줘", "작성",
			"show", "find", "search", "add", "append", "create", "write", "insert", "update", "delete", "remove")) {
			query = query.replace(word, " ");
		}
		query = query.replaceAll("\\d{4}년\\s*\\d{1,2}월\\s*\\d{1,2}일", " ");
		query = query.replaceAll("\\d{4}-\\d{1,2}-\\d{1,2}", " ");
		query = query.replaceAll("\\s+", " ").strip();
		if (query.length() > 80) {
			query = query.substring(0, 80);
		}
		return query;
	}

	private String targetQueryFrom(String command) {
		String query = command == null ? "" : command;
		int mutationIndex = -1;
		for (String word : MUTATION_MARKERS) {
			int index = query.indexOf(word);
			if (index >= 0 && (mutationIndex < 0 || index < mutationIndex)) {
				mutationIndex = index;
			}
		}
		if (mutationIndex >= 0) {
			query = query.substring(0, mutationIndex);
		}
		query = query.replaceFirst("(?s)^(.+?)(?:에|에다가|으로|로)\\s+\\S.+$", "$1");
		for (String marker : List.of("해야해 ", "해야 해 ", "마무리해야해 ", "마무리 해야해 ", "완료해야해 ", "완료 해야해 ")) {
			int index = query.lastIndexOf(marker);
			if (index >= 0) {
				query = query.substring(index + marker.length());
				break;
			}
		}
		query = query.replaceAll("\\d{4}년\\s*\\d{1,2}월\\s*\\d{1,2}일", " ");
		query = query.replaceAll("\\d{4}-\\d{1,2}-\\d{1,2}", " ");
		query = query.replaceAll("(까지|까지는|까지로)", " ");
		query = query.replaceAll("(에|으로|로)\\s*$", " ");
		query = query.replace('에', ' ');
		query = query.replaceAll("\\s+", " ").strip();
		if (query.isBlank()) {
			return searchQueryFrom(command);
		}
		return query.length() > 80 ? query.substring(0, 80) : query;
	}

	private String mutationTitle(String command, String targetTitle, String targetQuery) {
		Optional<String> explicitTitle = explicitTitle(command);
		if (explicitTitle.isPresent()) {
			return explicitTitle.get();
		}
		String title = command == null ? "새 Notion 항목" : command.strip();
		int mutationIndex = firstMutationIndex(title);
		if (mutationIndex >= 0) {
			title = title.substring(0, mutationIndex).strip();
		}
		String beforeTitleMarker = title.replaceFirst("(?s)^(.+?)[\"“']?\\s*제목\\s*(?:으로|로|은|는|:)\\s*.*$", "$1").strip();
		if (!beforeTitleMarker.equals(title) && !beforeTitleMarker.isBlank()) {
			title = beforeTitleMarker;
		}
		title = title.replaceFirst("(?s)^.+(?:에|에다가|으로|로)\\s+(.+)$", "$1");
		for (String suffix : MUTATION_MARKERS) {
			title = title.replace(suffix, " ");
		}
		title = removePhrase(title, targetTitle);
		title = removePhrase(title, targetQuery);
		title = stripDatePhrases(title);
		title = title.replaceAll("(개발\\s*)?진행\\s*중(으로)?", " ");
		title = title.replaceAll("(진행|완료|보류|대기|예정|폐기|디버깅)(으로)?", " ");
		title = title.replaceAll("(노션|Notion|페이지|데이터베이스|DB)", " ");
		title = title.replaceAll("(의|에|으로|로)\\s*$", " ");
		title = title.replaceAll("\\s+", " ").strip();
		if (title.isBlank()) {
			return "새 Notion 항목";
		}
		return title.length() > 120 ? title.substring(0, 120) : title;
	}

	private Optional<String> explicitTitle(String command) {
		if (command == null || command.isBlank()) {
			return Optional.empty();
		}
		for (String expression : List.of(
			"[\"“”']\\s*([^\"“”']{1,120}?)\\s*[\"“”']\\s*(?:제목|타이틀|title)",
			"(?:제목|타이틀|title)\\s*(?:은|는|:|으로|로)?\\s*[\"“”']\\s*([^\"“”']{1,120}?)\\s*[\"“”']",
			"([^\"“”']{1,120}?)\\s*(?:라는|이라는)?\\s*(?:제목|타이틀|title)\\s*(?:으로|로)",
			"([^\"“”']{1,120}?)\\s*(?:라는|이라는)?\\s*(?:제목|타이틀|title)\\s*(?:내용)?\\s*(?:을|를)?\\s*(?:삭제|지워|제거|delete|remove|archive)",
			"(?:제목|타이틀|title)\\s*(?:은|는|:)?\\s*([^\\s,.;。]+(?:\\s+[^\\s,.;。]+){0,8}?)(?:\\s*(?:으로|로)\\b|\\s*(?:상태|오늘|내일|모레|\\d{1,2}\\s*월|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}\\s*[/.]\\s*\\d{1,2}))"
		)) {
			Matcher matcher = Pattern.compile(expression, Pattern.CASE_INSENSITIVE).matcher(command);
			if (matcher.find()) {
				String title = cleanExplicitTitle(matcher.group(1));
				if (!title.isBlank()) {
					return Optional.of(title);
				}
			}
		}
		return Optional.empty();
	}

	private String cleanExplicitTitle(String value) {
		String title = value == null ? "" : value;
		title = title.replaceAll("[\"“”']", " ");
		title = tailAfterLocationMarker(title);
		title = stripDatePhrases(title);
		title = title.replaceAll("(라는|이라는)?\\s*(제목|타이틀|title)\\s*(내용)?", " ");
		title = title.replaceAll("(내용|본문)\\s*(을|를)?\\s*$", " ");
		title = title.replaceAll("(상태|예정|진행|완료|보류|대기|폐기|디버깅)(으로)?", " ");
		title = title.replaceAll("(의|에|으로|로)\\s*$", " ");
		title = title.replaceAll("\\s+", " ").strip();
		return title.length() > 120 ? title.substring(0, 120) : title;
	}

	private String tailAfterLocationMarker(String value) {
		String title = value == null ? "" : value.strip();
		int last = -1;
		for (String marker : List.of("에다가 ", "에서 ", "에는 ", "에 ", "으로 ", "로 ")) {
			int index = title.lastIndexOf(marker);
			if (index >= 0 && index + marker.length() > last) {
				last = index + marker.length();
			}
		}
		if (last > 0 && last < title.length()) {
			return title.substring(last).strip();
		}
		return title;
	}

	private int firstMutationIndex(String text) {
		if (text == null || text.isBlank()) {
			return -1;
		}
		String lower = text.toLowerCase(Locale.ROOT);
		int first = -1;
		for (String marker : MUTATION_MARKERS) {
			int index = lower.indexOf(marker.toLowerCase(Locale.ROOT));
			if (index >= 0 && (first < 0 || index < first)) {
				first = index;
			}
		}
		return first;
	}

	private String removePhrase(String text, String phrase) {
		if (text == null || phrase == null || phrase.isBlank()) {
			return text == null ? "" : text;
		}
		return text.replace(phrase, " ");
	}

	private Optional<String> statusOption(JsonNode statusProperty, String command) {
		List<String> options = new ArrayList<>();
		statusProperty.path("status").path("options").forEach(option -> {
			String name = option.path("name").asText("");
			if (!name.isBlank()) {
				options.add(name);
			}
		});
		if (options.isEmpty()) {
			return Optional.empty();
		}
		List<String> candidates = statusCandidates(command);
		for (String candidate : candidates) {
			Optional<String> exact = options.stream()
				.filter(option -> normalizeStatus(option).equals(normalizeStatus(candidate)))
				.findFirst();
			if (exact.isPresent()) {
				return exact;
			}
		}
		for (String candidate : candidates) {
			String normalizedCandidate = normalizeStatus(candidate);
			Optional<String> fuzzy = options.stream()
				.filter(option -> {
					String normalizedOption = normalizeStatus(option);
					return normalizedOption.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedOption);
				})
				.findFirst();
			if (fuzzy.isPresent()) {
				return fuzzy;
			}
		}
		return Optional.empty();
	}

	private List<String> statusCandidates(String command) {
		String normalized = command == null ? "" : command.toLowerCase(Locale.ROOT);
		List<String> candidates = new ArrayList<>();
		if (normalized.contains("디버깅") || normalized.contains("debug")) {
			candidates.addAll(List.of("디버깅", "debugging", "debug"));
		}
		if (normalized.contains("보류") || normalized.contains("hold") || normalized.contains("blocked")) {
			candidates.addAll(List.of("보류", "hold", "blocked"));
		}
		if (normalized.contains("폐기") || normalized.contains("취소") || normalized.contains("cancel")) {
			candidates.addAll(List.of("폐기", "취소", "canceled", "cancelled"));
		}
		if (normalized.contains("완료") || normalized.contains("끝") || normalized.contains("마무리")
			|| normalized.contains("done") || normalized.contains("complete")) {
			candidates.addAll(List.of("완료", "완료됨", "done", "complete", "completed"));
		}
		if (normalized.contains("예정") || normalized.contains("대기") || normalized.contains("todo")
			|| normalized.contains("to do") || normalized.contains("not started")) {
			candidates.addAll(List.of("예정", "대기", "할 일", "to do", "todo", "not started"));
		}
		if (normalized.contains("진행") || normalized.contains("개발") || normalized.contains("progress")
			|| normalized.contains("doing")) {
			candidates.addAll(List.of("진행 중", "진행중", "진행", "개발 진행중", "개발 진행 중", "in progress", "doing"));
		}
		candidates.addAll(List.of("진행 중", "진행중", "진행", "in progress", "doing"));
		return candidates;
	}

	private String normalizeStatus(String value) {
		return value == null ? "" : value.replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
	}

	private String compactTargetText(String value) {
		return value == null ? "" : value.replaceAll("\\s+", "").toLowerCase(Locale.ROOT);
	}

	private String stripDatePhrases(String value) {
		if (value == null || value.isBlank()) {
			return "";
		}
		String stripped = value.replace("오눌", "오늘");
		stripped = stripped.replaceAll("(오늘|내일|모레)\\s*부터\\s*(\\d{4}년\\s*)?\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일\\s*까지", " ");
		stripped = stripped.replaceAll("(\\d{4}년\\s*)?\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일\\s*부터\\s*(\\d{4}년\\s*)?\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일\\s*까지", " ");
		stripped = stripped.replaceAll("\\d{4}-\\d{1,2}-\\d{1,2}\\s*(부터|까지)?", " ");
		stripped = stripped.replaceAll("(\\d{4}년\\s*)?\\d{1,2}\\s*월\\s*\\d{1,2}\\s*일\\s*(부터|까지)?", " ");
		stripped = stripped.replaceAll("(오늘|내일|모레)\\s*(부터|까지)?", " ");
		stripped = stripped.replaceAll("(부터|까지|까지는|까지로)", " ");
		return stripped;
	}

	private NotionDateRange extractDateRange(String command) {
		if (command == null || command.isBlank()) {
			return new NotionDateRange(null, null);
		}
		LocalDate today = LocalDate.now();
		String normalized = command.replace("오눌", "오늘");
		LocalDate start = null;
		LocalDate end = null;
		if (normalized.contains("오늘부터")) {
			start = today;
		} else if (normalized.contains("내일부터")) {
			start = today.plusDays(1);
		} else if (normalized.contains("모레부터")) {
			start = today.plusDays(2);
		}
		List<LocalDate> dates = extractDates(normalized, today);
		if (start == null && normalized.contains("부터") && !dates.isEmpty()) {
			start = dates.getFirst();
		}
		if ((normalized.contains("까지") || normalized.contains("~") || normalized.contains("부터")) && !dates.isEmpty()) {
			end = dates.getLast();
		} else if (!dates.isEmpty()) {
			end = dates.getLast();
		}
		if (start == null && dates.size() > 1) {
			start = dates.getFirst();
		}
		if (end == null) {
			end = extractIsoDate(normalized).orElse(null);
		}
		if (start != null && end != null && start.isAfter(end)) {
			start = start.minusYears(1);
		}
		return new NotionDateRange(start, end);
	}

	private List<LocalDate> extractDates(String command, LocalDate today) {
		List<FoundDate> found = new ArrayList<>();
		Matcher korean = Pattern.compile("(?:(\\d{4})년\\s*)?(\\d{1,2})\\s*월\\s*(\\d{1,2})\\s*일?").matcher(command);
		while (korean.find()) {
			found.add(new FoundDate(korean.start(), relativeYearDate(korean.group(1), korean.group(2), korean.group(3), today)));
		}
		Matcher separated = Pattern.compile("(?<!\\d)(?:(\\d{4})\\s*[-/.]\\s*)?(\\d{1,2})\\s*[-/.]\\s*(\\d{1,2})(?!\\d)").matcher(command);
		while (separated.find()) {
			found.add(new FoundDate(separated.start(), relativeYearDate(separated.group(1), separated.group(2), separated.group(3), today)));
		}
		return found.stream()
			.sorted(Comparator.comparingInt(FoundDate::position))
			.map(FoundDate::date)
			.distinct()
			.toList();
	}

	private LocalDate relativeYearDate(String yearText, String monthText, String dayText, LocalDate baseDate) {
		int year = yearText == null || yearText.isBlank() ? baseDate.getYear() : Integer.parseInt(yearText);
		LocalDate date = LocalDate.of(year, Integer.parseInt(monthText), Integer.parseInt(dayText));
		if ((yearText == null || yearText.isBlank()) && date.isBefore(baseDate.minusDays(1))) {
			return date.plusYears(1);
		}
		return date;
	}

	private LocalDate koreanDate(Matcher matcher, LocalDate baseDate) {
		int year = matcher.group(1) == null || matcher.group(1).isBlank()
			? baseDate.getYear()
			: Integer.parseInt(matcher.group(1));
		LocalDate date = LocalDate.of(
			year,
			Integer.parseInt(matcher.group(2)),
			Integer.parseInt(matcher.group(3))
		);
		if ((matcher.group(1) == null || matcher.group(1).isBlank()) && date.isBefore(baseDate.minusDays(1))) {
			return date.plusYears(1);
		}
		return date;
	}

	private Optional<LocalDate> extractIsoDate(String command) {
		Matcher iso = Pattern.compile("(\\d{4})-(\\d{1,2})-(\\d{1,2})").matcher(command);
		if (iso.find()) {
			String month = iso.group(2).length() == 1 ? "0" + iso.group(2) : iso.group(2);
			String day = iso.group(3).length() == 1 ? "0" + iso.group(3) : iso.group(3);
			return Optional.of(LocalDate.parse(iso.group(1) + "-" + month + "-" + day));
		}
		return Optional.empty();
	}

	private Optional<LocalDate> extractDate(String command) {
		if (command == null) {
			return Optional.empty();
		}
		var korean = java.util.regex.Pattern.compile("(\\d{4})년\\s*(\\d{1,2})월\\s*(\\d{1,2})일").matcher(command);
		if (korean.find()) {
			return Optional.of(LocalDate.of(
				Integer.parseInt(korean.group(1)),
				Integer.parseInt(korean.group(2)),
				Integer.parseInt(korean.group(3))
			));
		}
		var iso = java.util.regex.Pattern.compile("(\\d{4})-(\\d{1,2})-(\\d{1,2})").matcher(command);
		if (iso.find()) {
			String month = iso.group(2).length() == 1 ? "0" + iso.group(2) : iso.group(2);
			String day = iso.group(3).length() == 1 ? "0" + iso.group(3) : iso.group(3);
			return Optional.of(LocalDate.parse(iso.group(1) + "-" + month + "-" + day));
		}
		return Optional.empty();
	}

	private Instant instant(String value) {
		try {
			return value == null || value.isBlank() ? null : Instant.parse(value);
		} catch (RuntimeException exception) {
			return null;
		}
	}

	private String normalizeId(String value) {
		if (value == null) {
			return "";
		}
		String trimmed = value.strip();
		if (trimmed.isBlank()) {
			return "";
		}
		try {
			return UUID.fromString(trimmed).toString();
		} catch (RuntimeException ignored) {
			return trimmed;
		}
	}

	private String url(String value) {
		return URLEncoder.encode(value, StandardCharsets.UTF_8);
	}

	private String safeFileName(String value) {
		String name = value == null || value.isBlank() ? "notion-file" : value.strip();
		return name.replaceAll("[\\\\/:*?\"<>|]", "_");
	}

	private <T> T firstOrNull(List<T> values) {
		return values == null || values.isEmpty() ? null : values.getFirst();
	}

	private int teamGalleryOrder(String title) {
		if (title == null) {
			return Integer.MAX_VALUE;
		}
		for (int index = 0; index < TEAMS_GALLERY_ORDER.size(); index++) {
			if (TEAMS_GALLERY_ORDER.get(index).equalsIgnoreCase(title.strip())) {
				return index;
			}
		}
		return Integer.MAX_VALUE;
	}

	private Iterable<JsonNode> iterable(JsonNode node) {
		if (node == null || !node.isArray()) {
			return List.of();
		}
		List<JsonNode> values = new ArrayList<>();
		node.forEach(values::add);
		return values;
	}
}
