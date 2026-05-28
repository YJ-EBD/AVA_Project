package com.ava.backend.ai.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.ai.dto.AvaAiChatResponse;
import com.ava.backend.ai.dto.AvaAiAgentTaskResponse;
import com.ava.backend.ai.dto.AvaAiMessageRequest;
import com.ava.backend.ai.dto.AvaAiMessageResponse;
import com.ava.backend.ai.dto.AvaAiNotionPageResponse;
import com.ava.backend.ai.dto.AvaAiReferenceResponse;
import com.ava.backend.ai.service.AvaAiLlmClient.ToolDefinition;
import com.ava.backend.ai.service.AvaAiLlmClient.ToolResult;
import com.ava.backend.ai.service.AvaAiAgentOrchestrator.AgentSession;
import com.ava.backend.ai.service.AvaAiToolRegistry.ToolExecution;
import com.ava.backend.ai.service.AvaAiWorkspaceService.WorkspaceActionResult;
import com.ava.backend.ai.entity.AvaAiConversationEntity;
import com.ava.backend.ai.entity.AvaAiKnowledgeItemEntity;
import com.ava.backend.ai.entity.AvaAiMessageEntity;
import com.ava.backend.ai.entity.AvaAiMessageRole;
import com.ava.backend.ai.repository.AvaAiConversationRepository;
import com.ava.backend.ai.repository.AvaAiKnowledgeItemRepository;
import com.ava.backend.ai.repository.AvaAiMessageRepository;
import com.ava.backend.ai.service.AvaAiWebSearchService.WebSearchResult;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.calendar.CalendarAiCommandService;
import com.ava.backend.calendar.CalendarAiWorkspaceResponse;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class AvaAiService {

	private static final String DEFAULT_CONVERSATION_TITLE = "AVA AI";
	private static final int MAX_WEB_RESULTS_IN_PROMPT = 3;
	private static final int MAX_REFERENCES_IN_PROMPT = 2;
	private static final int MAX_WORKSPACE_CONTEXT_CHARS = 1_800;
	private static final int MAX_AGENT_STATE_CHARS = 2_200;
	private static final int MAX_HISTORY_CONTEXT_CHARS = 6_000;
	private static final int MAX_HISTORY_MESSAGE_CHARS = 900;
	private static final int MAX_CURRENT_MESSAGE_CHARS = 2_000;
	private static final int FULL_PROMPT_TOKEN_BUDGET = 2_650;
	private static final int COMPACT_PROMPT_TOKEN_BUDGET = 2_250;
	private static final int MINIMAL_PROMPT_TOKEN_BUDGET = 1_650;
	private static final int TOKEN_OVERHEAD_PER_MESSAGE = 10;
	private static final Pattern DEFERRED_PROMISE_PATTERN = Pattern.compile(
		"(잠시만\\s*기다|잠시\\s*기다|기다려\\s*주|잠시\\s*후|곧\\s*(처리|확인|진행|실행)"
			+ "|처리하겠습니다|진행하겠습니다|실행하겠습니다|시도하겠습니다|조회하겠습니다|확인하겠습니다"
			+ "|찾아보겠습니다|알아보겠습니다|다시\\s*시도합니다|명령을\\s*실행하겠습니다)",
		Pattern.CASE_INSENSITIVE
	);
	private static final Pattern CONCRETE_RESULT_PATTERN = Pattern.compile(
		"(완료|했습니다|확인했습니다|검증|결과|URL|HTTP|exitCode|승인\\s*대기|실패|오류|찾았습니다"
			+ "|찾지\\s*못했습니다|없습니다|처리했습니다|반영|삭제\\s*처리|생성했습니다|수정했습니다"
			+ "|전송했습니다|업로드했습니다)",
		Pattern.CASE_INSENSITIVE
	);
	private static final String GREETING_MESSAGE = "\uC548\uB155\uD558\uC138\uC694. AVA AI\uC785\uB2C8\uB2E4.\n"
		+ "\uC0AC\uB0B4 \uCC44\uD305, \uD30C\uC77C, \uC11C\uBC84 \uC790\uB8CC, NAS/Notion \uAD00\uB828 \uC5C5\uBB34\uB97C \uB3C4\uC640\uB4DC\uB9B4\uAC8C\uC694. "
		+ "\uBB34\uC5C7\uC774 \uD544\uC694\uD558\uC2E0\uAC00\uC694?";
	private static final ObjectMapper TOOL_ARGUMENT_MAPPER = new ObjectMapper();

	private final AvaAiConversationRepository conversationRepository;
	private final AvaAiMessageRepository messageRepository;
	private final AvaAiKnowledgeItemRepository knowledgeRepository;
	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final AvaAiLlmClient llmClient;
	private final AvaAiEmbeddingService embeddingService;
	private final AvaAiWebSearchService webSearchService;
	private final AvaAiWorkspaceService workspaceService;
	private final AvaAiNotionService notionService;
	private final AvaAiAgentOrchestrator agentOrchestrator;
	private final CompanyScopeService companyScopeService;
	private final CalendarAiCommandService calendarCommandService;
	private final int sharedReferenceLimit;
	private final int historyLimit;

	@Autowired
	public AvaAiService(
		AvaAiConversationRepository conversationRepository,
		AvaAiMessageRepository messageRepository,
		AvaAiKnowledgeItemRepository knowledgeRepository,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		AvaAiLlmClient llmClient,
		AvaAiEmbeddingService embeddingService,
		AvaAiWebSearchService webSearchService,
		AvaAiWorkspaceService workspaceService,
		AvaAiNotionService notionService,
		AvaAiAgentOrchestrator agentOrchestrator,
		CompanyScopeService companyScopeService,
		CalendarAiCommandService calendarCommandService,
		@Value("${ava.ai.shared-reference-limit:5}") int sharedReferenceLimit,
		@Value("${ava.ai.history-limit:24}") int historyLimit
	) {
		this.conversationRepository = conversationRepository;
		this.messageRepository = messageRepository;
		this.knowledgeRepository = knowledgeRepository;
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.llmClient = llmClient;
		this.embeddingService = embeddingService;
		this.webSearchService = webSearchService;
		this.workspaceService = workspaceService;
		this.notionService = notionService;
		this.agentOrchestrator = agentOrchestrator;
		this.companyScopeService = companyScopeService;
		this.calendarCommandService = calendarCommandService;
		this.sharedReferenceLimit = Math.max(0, sharedReferenceLimit);
		this.historyLimit = Math.max(4, historyLimit);
	}

	AvaAiService(
		AvaAiConversationRepository conversationRepository,
		AvaAiMessageRepository messageRepository,
		AvaAiKnowledgeItemRepository knowledgeRepository,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		AvaAiLlmClient llmClient,
		AvaAiEmbeddingService embeddingService,
		AvaAiWebSearchService webSearchService,
		AvaAiWorkspaceService workspaceService,
		AvaAiNotionService notionService,
		AvaAiAgentOrchestrator agentOrchestrator,
		CompanyScopeService companyScopeService,
		int sharedReferenceLimit,
		int historyLimit
	) {
		this(
			conversationRepository,
			messageRepository,
			knowledgeRepository,
			accountRepository,
			profileRepository,
			llmClient,
			embeddingService,
			webSearchService,
			workspaceService,
			notionService,
			agentOrchestrator,
			companyScopeService,
			null,
			sharedReferenceLimit,
			historyLimit
		);
	}

	@Transactional
	public List<AvaAiMessageResponse> history(AuthPrincipal principal) {
		UserAccount account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("User account not found."));
		String companyName = companyScopeService.effectiveCompany(principal);
		AvaAiConversationEntity conversation = conversationFor(account, companyName, DEFAULT_CONVERSATION_TITLE);
		conversation.setCompanyName(companyName);
		ensureGreetingMessage(conversation, account, companyName);
		conversationRepository.save(conversation);

		return messageRepository.findTop200ByConversationIdOrderByCreatedAtDesc(conversation.getId())
			.stream()
			.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt))
			.map(message -> toMessageResponse(message, List.of()))
			.toList();
	}

	@Transactional
	public AvaAiChatResponse send(AvaAiMessageRequest request, AuthPrincipal principal) {
		String content = normalizeContent(request.content());
		UserAccount account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("User account not found."));
		String companyName = companyScopeService.effectiveCompany(principal);
		String displayName = account.getDisplayName();
		AvaAiConversationEntity conversation = conversationFor(account, companyName, content);
		ensureGreetingMessage(conversation, account, companyName);

		AvaAiMessageEntity userMessage = messageRepository.save(new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.USER,
			content,
			null
		));
		AgentSession agentSession = agentOrchestrator.start(conversation, userMessage, content);

		CalendarAiCommandService.CommandResult calendarCommand = calendarCommandService == null
			? null
			: calendarCommandService.handle(content, conversation.getId(), principal).orElse(null);
		CalendarAiWorkspaceResponse calendarWorkspace = calendarCommand == null
			? CalendarAiWorkspaceResponse.empty()
			: calendarCommand.workspace();
		List<AvaAiKnowledgeItemEntity> references = calendarCommand == null
			? relevantReferences(companyName, content)
			: List.of();
		List<WebSearchResult> webResults = calendarCommand == null
			? webSearchService.searchIfNeeded(content)
			: List.of();
		WorkspaceActionResult workspace = calendarCommand == null
			? workspaceService.inspectPrompt(
				content,
				principal,
				webResults,
				request.workspacePaths()
			)
			: new WorkspaceActionResult(List.of(), calendarWorkspace.status(), "", true);
		ToolExecution toolExecution = calendarCommand == null
			? (workspace.handled()
				? ToolExecution.notHandled()
				: agentOrchestrator.runAutomaticTool(agentSession, content))
			: calendarToolExecution(calendarCommand);
		List<ToolExecution> nativeToolExecutions = new ArrayList<>();
		String answer;
		String modelName = llmClient.model();
		if (calendarCommand != null) {
			answer = calendarCommand.answer();
			modelName = "direct-api/calendar";
		} else if (workspace.handled()) {
			answer = workspaceHandledAnswer(workspace);
		} else if (toolExecution.handled()) {
			answer = toolExecution.answer();
			modelName = toolExecution.modelName();
		} else {
			List<AvaAiLlmClient.PromptMessage> prompt = buildPrompt(
				conversation,
				userMessage,
				references,
				webResults,
				workspace.promptContext(),
				agentOrchestrator.recentState(conversation.getId())
			);
			answer = completeWithNativeToolsFallback(
				prompt,
				userMessage,
				webResults,
				workspace.promptContext(),
				agentOrchestrator.recentState(conversation.getId()),
				nativeToolExecutions
			);
			if (!nativeToolExecutions.isEmpty()) {
				toolExecution = summarizeNativeTools(nativeToolExecutions);
			}
		}
		answer = enforceActionableWorkAnswer(content, answer, workspace, toolExecution);
		markReferencedKnowledgeUsed(references);
		AvaAiMessageEntity assistantMessage = messageRepository.save(new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.ASSISTANT,
			answer,
			modelName
		));
		AvaAiAgentTaskResponse agentTask = agentOrchestrator.complete(agentSession, answer, workspace, toolExecution);

		AvaAiKnowledgeItemEntity memory = new AvaAiKnowledgeItemEntity(
			companyName,
			conversation.getId(),
			userMessage.getId(),
			assistantMessage.getId(),
			account.getId(),
			displayName,
			content,
			answer
		);
		embedKnowledge(memory);
		knowledgeRepository.save(memory);
		conversation.setCompanyName(companyName);
		conversationRepository.save(conversation);

		List<AvaAiReferenceResponse> referenceResponses = references.stream()
			.map(this::toReferenceResponse)
			.toList();
		return new AvaAiChatResponse(
			toMessageResponse(userMessage, List.of()),
			toMessageResponse(assistantMessage, referenceResponses),
			workspace.items(),
			workspace.status(),
			agentTask,
			calendarWorkspace
		);
	}

	@Transactional
	public void resetCurrentConversation(AuthPrincipal principal) {
		String companyName = companyScopeService.effectiveCompany(principal);
		conversationRepository.findByAccountIdAndCompanyNameIgnoreCase(principal.userId(), companyName)
			.ifPresent(conversation -> {
				messageRepository.deleteByConversationId(conversation.getId());
				agentOrchestrator.deleteConversationTasks(conversation);
			});
	}

	@Transactional
	public void recordToolExchange(
		String userContent,
		String assistantContent,
		String toolName,
		AuthPrincipal principal
	) {
		String content = normalizeContent(userContent);
		String answer = assistantContent == null || assistantContent.isBlank()
			? "도구 작업을 처리했습니다."
			: assistantContent.strip();
		UserAccount account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("User account not found."));
		String companyName = companyScopeService.effectiveCompany(principal);
		AvaAiConversationEntity conversation = conversationFor(account, companyName, content);
		ensureGreetingMessage(conversation, account, companyName);
		Instant now = Instant.now();
		AvaAiMessageEntity userMessage = new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.USER,
			content,
			null
		);
		userMessage.setCreatedAt(now);
		AvaAiMessageEntity assistantMessage = new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.ASSISTANT,
			answer,
			toolName == null || toolName.isBlank() ? "ava-tool" : limit(toolName, 80)
		);
		assistantMessage.setCreatedAt(now.plusMillis(1));
		AvaAiMessageEntity savedUserMessage = messageRepository.save(userMessage);
		AvaAiMessageEntity savedAssistantMessage = messageRepository.save(assistantMessage);
		agentOrchestrator.recordExternalToolExchange(
			conversation,
			savedUserMessage,
			savedAssistantMessage,
			toolName
		);
		conversation.setCompanyName(companyName);
		conversationRepository.save(conversation);
	}

	private AvaAiConversationEntity conversationFor(UserAccount account, String companyName, String firstMessage) {
		return conversationRepository.findByAccountIdAndCompanyNameIgnoreCase(account.getId(), companyName)
			.orElseGet(() -> conversationRepository.save(new AvaAiConversationEntity(
				account.getId(),
				companyName,
				titleFrom(firstMessage)
			)));
	}

	private void ensureGreetingMessage(AvaAiConversationEntity conversation, UserAccount account, String companyName) {
		if (messageRepository.existsByConversationId(conversation.getId())) {
			return;
		}
		messageRepository.save(new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.ASSISTANT,
			GREETING_MESSAGE,
			null
		));
	}

	private String workspaceHandledAnswer(WorkspaceActionResult workspace) {
		String status = workspace.status() == null ? "" : workspace.status().trim();
		if (!status.isBlank()) {
			return status;
		}
		if (workspace.items() != null && !workspace.items().isEmpty()) {
			return "선택한 작업공간 파일 처리를 완료했습니다.";
		}
		return "작업공간 요청을 처리했습니다.";
	}

	private ToolExecution calendarToolExecution(CalendarAiCommandService.CommandResult command) {
		String status = command.workspace() == null ? "" : command.workspace().status();
		return new ToolExecution(
			"calendar.ai_command",
			true,
			command.success(),
			command.verified(),
			command.requiresClarification(),
			command.answer(),
			status == null || status.isBlank() ? command.answer() : status,
			command.verified()
				? "CalendarService executed and returned a refreshed schedule workspace."
				: "CalendarService returned a clarification or error state.",
			command.success() ? "" : command.answer(),
			"direct-api/calendar"
		);
	}

	private String enforceActionableWorkAnswer(
		String userContent,
		String answer,
		WorkspaceActionResult workspace,
		ToolExecution toolExecution
	) {
		String normalizedAnswer = answer == null ? "" : answer.strip();
		if (normalizedAnswer.isBlank()) {
			return "응답 생성 결과가 비어 있어 작업을 완료로 처리하지 않았습니다. 실행 가능한 도구/API 결과가 필요합니다.";
		}
		AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(userContent);
		if (!frame.workRequest() || !isDeferredPromiseOnly(normalizedAnswer)) {
			return normalizedAnswer;
		}
		if (workspace != null && workspace.handled()) {
			return normalizedAnswer;
		}
		if (toolExecution != null && toolExecution.handled()) {
			return normalizedAnswer;
		}
		return deferredPromiseBlockedAnswer(userContent, frame);
	}

	private boolean isDeferredPromiseOnly(String answer) {
		if (!DEFERRED_PROMISE_PATTERN.matcher(answer).find()) {
			return false;
		}
		return !CONCRETE_RESULT_PATTERN.matcher(answer).find();
	}

	private String deferredPromiseBlockedAnswer(String userContent, AvaAiAgentPolicy.AgentFrame frame) {
		return String.join("\n",
			"실행 결과 없이 기다리라는 응답을 차단했습니다.",
			"현재 이 대화 경로에서 즉시 실행 가능한 도구/API가 매칭되지 않아 실제 작업은 수행하지 않았습니다.",
			"요청: " + limit(oneLine(userContent), 180),
			"분류: " + frame.mode(),
			"필요 조치: 연결된 도구 경로로 바로 실행하거나, 대상이 애매하면 승인 전에 대상/필드/값을 먼저 확인해야 합니다."
		);
	}

	private String completeWithContextFallback(
		List<AvaAiLlmClient.PromptMessage> prompt,
		AvaAiMessageEntity currentMessage,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext
	) {
		try {
			return llmClient.complete(prompt);
		} catch (IllegalStateException exception) {
			if (!isContextLimitError(exception)) {
				throw exception;
			}
			return llmClient.complete(buildEmergencyPrompt(
				currentMessage,
				webResults,
				workspaceContext,
				agentStateContext
			));
		}
	}

	private String completeWithNativeToolsFallback(
		List<AvaAiLlmClient.PromptMessage> prompt,
		AvaAiMessageEntity currentMessage,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext,
		List<ToolExecution> nativeToolExecutions
	) {
		List<ToolDefinition> tools = nativeToolDefinitions(currentMessage.getContent());
		if (tools.isEmpty()) {
			return completeWithContextFallback(prompt, currentMessage, webResults, workspaceContext, agentStateContext);
		}
		try {
			return llmClient.completeWithTools(
				prompt,
				tools,
				call -> {
					ToolExecution execution = executeNativeToolCall(call, currentMessage.getContent());
					nativeToolExecutions.add(execution);
					return new ToolResult(
						execution.success() || execution.verified(),
						execution.answer()
					);
				},
				3
			);
		} catch (AvaAiLlmClient.ToolCallingUnsupportedException exception) {
			return completeWithContextFallback(prompt, currentMessage, webResults, workspaceContext, agentStateContext);
		} catch (IllegalStateException exception) {
			if (!isContextLimitError(exception)) {
				throw exception;
			}
			return llmClient.complete(buildEmergencyPrompt(
				currentMessage,
				webResults,
				workspaceContext,
				agentStateContext
			));
		}
	}

	private List<ToolDefinition> nativeToolDefinitions(String content) {
		if (llmClient == null) {
			return List.of();
		}
		AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(content);
		if (!frame.workRequest()) {
			return List.of();
		}
		List<ToolDefinition> tools = new ArrayList<>();
		if (agentOrchestrator != null) {
			tools.addAll(agentOrchestrator.nativeToolDefinitions());
		}
		if (notionService != null) {
			tools.add(notionSearchTool());
			tools.add(notionOpenTool());
		}
		return tools;
	}

	private ToolExecution executeNativeToolCall(AvaAiLlmClient.ToolCall call, String currentContent) {
		if (call == null || call.name() == null) {
			return ToolExecution.notHandled();
		}
		if (call.name().equals("notion_search")) {
			return executeNativeNotionSearch(call, currentContent);
		}
		if (call.name().equals("notion_open")) {
			return executeNativeNotionOpen(call);
		}
		if (agentOrchestrator == null) {
			return new ToolExecution(
				call.name(),
				true,
				false,
				false,
				false,
				"native tool 실행기가 연결되어 있지 않습니다.",
				"native tool executor missing",
				"도구 실행 객체가 없어 검증하지 못했습니다.",
				"missing executor",
				"ava-agent/native-tool"
			);
		}
		return agentOrchestrator.executeNativeTool(call);
	}

	private ToolDefinition notionSearchTool() {
		return new ToolDefinition(
			"notion_search",
			"Search Notion pages and databases. Read-only. Use before answering Notion location/content questions.",
			Map.of(
				"type", "object",
				"properties", Map.of(
					"query", Map.of("type", "string", "description", "Notion search query")
				),
				"required", List.of("query"),
				"additionalProperties", false
			)
		);
	}

	private ToolDefinition notionOpenTool() {
		return new ToolDefinition(
			"notion_open",
			"Open a Notion page or database by id. Read-only.",
			Map.of(
				"type", "object",
				"properties", Map.of(
					"id", Map.of("type", "string", "description", "Notion page or database id"),
					"object", Map.of("type", "string", "description", "page or database")
				),
				"required", List.of("id"),
				"additionalProperties", false
			)
		);
	}

	private ToolExecution executeNativeNotionSearch(AvaAiLlmClient.ToolCall call, String currentContent) {
		if (notionService == null) {
			return ToolExecution.notHandled();
		}
		String query = toolArguments(call).path("query").asText(currentContent == null ? "" : currentContent).strip();
		try {
			List<AvaAiNotionPageResponse> results = notionService.search(query);
			String answer = results.isEmpty()
				? "Notion 검색 결과가 없습니다. query=" + query
				: "Notion 검색 결과 " + results.size() + "개\n" + notionResultsPreview(results);
			return new ToolExecution(
				"notion_search",
				true,
				true,
				true,
				false,
				answer,
				"notion_search query=" + query + ", results=" + results.size(),
				"Notion API 검색 응답을 확인했습니다.",
				"",
				"ava-agent/notion_search"
			);
		} catch (RuntimeException exception) {
			return nativeToolFailure("notion_search", "Notion 검색 중 오류가 발생했습니다.", exception);
		}
	}

	private ToolExecution executeNativeNotionOpen(AvaAiLlmClient.ToolCall call) {
		if (notionService == null) {
			return ToolExecution.notHandled();
		}
		JsonNode args = toolArguments(call);
		String id = args.path("id").asText("").strip();
		String object = args.path("object").asText("page").strip();
		if (id.isBlank()) {
			return new ToolExecution(
				"notion_open",
				true,
				false,
				false,
				false,
				"Notion open에는 id가 필요합니다.",
				"notion_open missing id",
				"필수 인자가 없어 도구를 실행하지 않았습니다.",
				"missing id",
				"ava-agent/notion_open"
			);
		}
		try {
			AvaAiNotionPageResponse page = notionService.open(id, object);
			String answer = String.join("\n",
				"Notion 항목을 열었습니다.",
				"object: " + page.object(),
				"title: " + page.title(),
				"url: " + page.url(),
				page.content() == null || page.content().isBlank() ? "content: 없음" : "content: " + limit(oneLine(page.content()), 1_000)
			);
			return new ToolExecution(
				"notion_open",
				true,
				true,
				true,
				false,
				answer,
				"notion_open id=" + id + ", object=" + object + ", title=" + page.title(),
				"Notion API open 응답을 확인했습니다.",
				"",
				"ava-agent/notion_open"
			);
		} catch (RuntimeException exception) {
			return nativeToolFailure("notion_open", "Notion 항목 열기 중 오류가 발생했습니다.", exception);
		}
	}

	private ToolExecution nativeToolFailure(String toolName, String message, RuntimeException exception) {
		return new ToolExecution(
			toolName,
			true,
			false,
			false,
			false,
			message + " " + exception.getClass().getSimpleName() + ": " + limit(exception.getMessage(), 500),
			toolName + " failed",
			"예외가 발생해 native tool 검증을 완료하지 못했습니다.",
			exception.getClass().getSimpleName() + ": " + limit(exception.getMessage(), 900),
			"ava-agent/" + toolName
		);
	}

	private JsonNode toolArguments(AvaAiLlmClient.ToolCall call) {
		try {
			return TOOL_ARGUMENT_MAPPER.readTree(
				call.argumentsJson() == null || call.argumentsJson().isBlank() ? "{}" : call.argumentsJson()
			);
		} catch (Exception exception) {
			return TOOL_ARGUMENT_MAPPER.createObjectNode();
		}
	}

	private String notionResultsPreview(List<AvaAiNotionPageResponse> results) {
		StringBuilder builder = new StringBuilder();
		int count = Math.min(results.size(), 8);
		for (int index = 0; index < count; index++) {
			AvaAiNotionPageResponse result = results.get(index);
			builder.append("- ")
				.append(result.object())
				.append(" | ")
				.append(result.title())
				.append(" | id=")
				.append(result.id());
			if (result.url() != null && !result.url().isBlank()) {
				builder.append(" | ").append(result.url());
			}
			builder.append('\n');
		}
		return builder.toString().strip();
	}

	private ToolExecution summarizeNativeTools(List<ToolExecution> executions) {
		boolean success = executions.stream().allMatch(ToolExecution::success);
		boolean verified = executions.stream().anyMatch(ToolExecution::verified);
		String summary = executions.stream()
			.map(execution -> execution.toolName() + "=" + execution.resultSummary())
			.reduce((left, right) -> left + " / " + right)
			.orElse("native tool call");
		String verification = executions.stream()
			.map(ToolExecution::verificationSummary)
			.reduce((left, right) -> left + " / " + right)
			.orElse("LLM native tool call 결과를 확인했습니다.");
		return new ToolExecution(
			"llm-native-tools",
			true,
			success,
			verified,
			false,
			"LLM native tool calling을 실행했습니다.",
			summary,
			verification,
			success ? "" : "one or more native tools failed",
			"ava-agent/native-tools"
		);
	}

	private boolean isContextLimitError(RuntimeException exception) {
		String message = exception.getMessage() == null ? "" : exception.getMessage().toLowerCase(Locale.ROOT);
		return message.contains("context")
			&& (message.contains("exceed") || message.contains("too long") || message.contains("tokens"));
	}

	private List<AvaAiLlmClient.PromptMessage> buildPrompt(
		AvaAiConversationEntity conversation,
		AvaAiMessageEntity currentMessage,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext
	) {
		List<AvaAiMessageEntity> recent = recentMessages(conversation);
		for (PromptBudgetProfile profile : PromptBudgetProfile.profiles(historyLimit)) {
			List<AvaAiLlmClient.PromptMessage> messages = buildPromptWithProfile(
				conversation,
				currentMessage,
				references,
				webResults,
				workspaceContext,
				agentStateContext,
				recent,
				profile
			);
			if (estimatedPromptTokens(messages) <= profile.tokenBudget()
				|| profile.level() == PromptBudgetLevel.MINIMAL) {
				return enforcePromptBudget(messages, profile.tokenBudget());
			}
		}
		return buildEmergencyPrompt(currentMessage, webResults, workspaceContext, agentStateContext);
	}

	private List<AvaAiLlmClient.PromptMessage> buildPromptWithProfile(
		AvaAiConversationEntity conversation,
		AvaAiMessageEntity currentMessage,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext,
		List<AvaAiMessageEntity> recent,
		PromptBudgetProfile profile
	) {
		List<AvaAiLlmClient.PromptMessage> messages = new ArrayList<>();
		messages.add(new AvaAiLlmClient.PromptMessage(
			"system",
			systemPrompt(
				conversation.getCompanyName(),
				references,
				webResults,
				workspaceContext,
				agentStateContext,
				currentMessage.getContent(),
				recent,
				profile
			)
		));

		messages.addAll(historyPromptMessages(recent, currentMessage, profile));
		messages.add(new AvaAiLlmClient.PromptMessage(
			"user",
			limit(currentMessage.getContent(), profile.currentMessageChars())
		));
		return messages;
	}

	private List<AvaAiLlmClient.PromptMessage> buildEmergencyPrompt(
		AvaAiMessageEntity currentMessage,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext
	) {
		PromptBudgetProfile profile = PromptBudgetProfile.minimal(historyLimit);
		StringBuilder system = new StringBuilder();
		system.append("너는 AVA AI다. 한국어로 짧고 정확하게 답한다.\n");
		system.append(AvaAiAgentPolicy.compactContract(AvaAiAgentPolicy.inspect(currentMessage.getContent())));
		system.append("작업 요청에는 기다려달라/시도하겠다 같은 미래 약속만 답하지 말고, 실행 결과/승인 대기/확인 질문/실행 불가 사유 중 하나로 답한다.\n");
		if (agentStateContext != null && !agentStateContext.isBlank()) {
			system.append(limit(agentStateContext, profile.agentStateChars())).append('\n');
		}
		if (workspaceContext != null && !workspaceContext.isBlank()) {
			system.append("\n[WORKSPACE]\n").append(limit(workspaceContext, profile.workspaceContextChars())).append('\n');
		}
		appendWebSearchResults(system, webResults, profile);
		List<AvaAiLlmClient.PromptMessage> messages = List.of(
			new AvaAiLlmClient.PromptMessage("system", system.toString()),
			new AvaAiLlmClient.PromptMessage("user", limit(currentMessage.getContent(), 900))
		);
		return enforcePromptBudget(messages, MINIMAL_PROMPT_TOKEN_BUDGET);
	}

	private List<AvaAiMessageEntity> recentMessages(AvaAiConversationEntity conversation) {
		return messageRepository
			.findTop200ByConversationIdOrderByCreatedAtDesc(conversation.getId())
			.stream()
			.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt))
			.toList();
	}

	private List<AvaAiLlmClient.PromptMessage> historyPromptMessages(
		List<AvaAiMessageEntity> recent,
		AvaAiMessageEntity currentMessage
	) {
		return historyPromptMessages(recent, currentMessage, PromptBudgetProfile.full(historyLimit));
	}

	private List<AvaAiLlmClient.PromptMessage> historyPromptMessages(
		List<AvaAiMessageEntity> recent,
		AvaAiMessageEntity currentMessage,
		PromptBudgetProfile profile
	) {
		List<AvaAiLlmClient.PromptMessage> history = new ArrayList<>();
		int fromIndex = Math.max(0, recent.size() - profile.historyMessageLimit());
		int remaining = profile.historyContextChars();
		for (int index = recent.size() - 1; index >= fromIndex; index--) {
			AvaAiMessageEntity message = recent.get(index);
			if (message.getId().equals(currentMessage.getId())) {
				continue;
			}
			String content = limit(
				compressConversationMessage(message.getContent(), profile),
				Math.min(profile.historyMessageChars(), remaining)
			);
			if (content.isBlank()) {
				continue;
			}
			history.add(0, new AvaAiLlmClient.PromptMessage(
				message.getRole() == AvaAiMessageRole.USER ? "user" : "assistant",
				content
			));
			remaining -= content.length();
			if (remaining <= 120) {
				break;
			}
		}
		return history;
	}

	private String compressConversationMessage(String content, PromptBudgetProfile profile) {
		String oneLine = oneLine(content);
		if (profile.level() == PromptBudgetLevel.FULL) {
			return content;
		}
		if (profile.level() == PromptBudgetLevel.COMPACT) {
			return limit(oneLine, profile.historyMessageChars());
		}
		return limit(oneLine, Math.min(180, profile.historyMessageChars()));
	}

	private String systemPrompt(
		String companyName,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext,
		String currentContent,
		List<AvaAiMessageEntity> recentMessages
	) {
		return systemPrompt(
			companyName,
			references,
			webResults,
			workspaceContext,
			agentStateContext,
			currentContent,
			recentMessages,
			PromptBudgetProfile.full(historyLimit)
		);
	}

	private String systemPrompt(
		String companyName,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext,
		String agentStateContext,
		String currentContent,
		List<AvaAiMessageEntity> recentMessages,
		PromptBudgetProfile profile
	) {
		StringBuilder prompt = new StringBuilder();
		prompt.append("너는 AVA 사내메신저의 AI 비서다. 항상 한국어로 간결하고 정확하게 답한다.\n");
		prompt.append("회사명: ").append(companyName).append("\n");
		if (profile.level() == PromptBudgetLevel.FULL) {
			prompt.append(AvaAiAgentPolicy.contract(AvaAiAgentPolicy.inspect(currentContent)));
			prompt.append("대화는 이전 맥락을 이어서 이해한다. '방금', '그거', '아까', '그 말이 아니라' 같은 표현은 최근 대화와 도구 결과를 먼저 참조한다.\n");
			prompt.append("사용자가 정정하거나 문제를 지적하면 변명하지 말고 현재 상태를 인정한 뒤, 무엇을 확인했고 무엇을 바꿀지 짧게 말한다.\n");
			prompt.append("사용자가 명확히 생성/수정/삭제/전송을 요청하지 않은 경우 실제 쓰기 작업을 했다고 말하지 않는다.\n");
			prompt.append("도구 작업은 먼저 계획과 대상/필드/값을 분리해서 이해하고, 애매하면 확인 질문을 한다.\n");
			prompt.append("DB, 채팅, 파일, NAS, Notion 같은 실제 조회나 쓰기 작업은 연결된 도구/API 결과가 있을 때만 완료했다고 말한다.\n");
			prompt.append("'잠시만 기다려 주세요', '다시 시도합니다', '확인하겠습니다', '처리하겠습니다'처럼 실행 없이 미래 동작을 약속하는 응답은 금지한다.\n");
			prompt.append("작업 명령에는 같은 턴의 실행 결과, 승인 대기, 정확한 확인 질문, 실행 불가 사유 중 하나로만 답한다.\n");
			prompt.append("사용자가 공개 인터넷, 외부 사이트, 쇼핑몰, 뉴스, 문서, 가격, 상품 검색을 요청하면 사내 업무와 무관해도 웹 검색 결과를 바탕으로 도와준다.\n");
			prompt.append("외부 사이트라는 이유만으로 거절하지 않는다. 다만 결제, 로그인, 주문, 구매 확정 같은 행위는 직접 수행하지 않고 사용자가 직접 진행해야 한다고 안내한다.\n");
			prompt.append("웹 검색 결과가 있으면 결과의 제목, 요약, URL을 근거로 답하고, 결과가 부족하면 가져온 범위와 추가 검색 키워드를 알려준다.\n");
			prompt.append("작업공간 결과가 있으면 파일, 채팅, 회의록, 웹 결과를 근거로 답하고 실제 전송/수정 작업 상태를 명확히 말한다.\n");
			prompt.append("지금 모르는 사실은 추측하지 말고, 확인이 필요한 정보와 다음 조치를 말한다.\n");
			prompt.append("아래 회사 공용 참고자료는 이전 AVA AI 대화에서 축적된 검색 메모리다. 관련 있는 사실만 현재 답변에 반영하고 원문을 불필요하게 노출하지 않는다.\n");
		} else {
			prompt.append(AvaAiAgentPolicy.compactContract(AvaAiAgentPolicy.inspect(currentContent)));
			prompt.append("핵심: 최근 검증된 상태만 근거로 삼고, 모르면 확인 필요/다음 조치를 말한다. 실제 도구 결과 없이 완료를 주장하지 않는다.\n");
		}
		if (agentStateContext != null && !agentStateContext.isBlank()) {
			prompt.append(limit(agentStateContext, profile.agentStateChars())).append('\n');
		}
		appendRecentToolState(prompt, recentMessages, profile);
		appendWebSearchResults(prompt, webResults, profile);
		if (workspaceContext != null && !workspaceContext.isBlank()) {
			prompt.append("\n[AVA AI WORKSPACE RESULTS]\n")
				.append(limit(workspaceContext, profile.workspaceContextChars()))
				.append('\n');
		}
		if (references.isEmpty()) {
			return prompt.toString();
		}
		int referenceCount = Math.min(references.size(), profile.referenceLimit());
		for (int index = 0; index < referenceCount; index++) {
			AvaAiKnowledgeItemEntity item = references.get(index);
			prompt.append("\n[공용 참고자료 ").append(index + 1).append("]\n");
			prompt.append("질문: ").append(limit(item.getQuestion(), profile.referenceQuestionChars())).append("\n");
			prompt.append("답변: ").append(limit(item.getAnswer(), profile.referenceAnswerChars())).append("\n");
		}
		return prompt.toString();
	}

	private void appendRecentToolState(StringBuilder prompt, List<AvaAiMessageEntity> recentMessages) {
		appendRecentToolState(prompt, recentMessages, PromptBudgetProfile.full(historyLimit));
	}

	private void appendRecentToolState(
		StringBuilder prompt,
		List<AvaAiMessageEntity> recentMessages,
		PromptBudgetProfile profile
	) {
		if (recentMessages == null || recentMessages.isEmpty()) {
			return;
		}
		List<AvaAiMessageEntity> toolMessages = recentMessages.stream()
			.filter(message -> message.getRole() == AvaAiMessageRole.ASSISTANT)
			.filter(this::isToolMessage)
			.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt).reversed())
			.limit(profile.toolStateLimit())
			.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt))
			.toList();
		if (toolMessages.isEmpty()) {
			return;
		}
		StringBuilder state = new StringBuilder();
		state.append("\n[RECENT TOOL STATE]\n");
		state.append("These are verified tool/API outcomes from the same AVA AI conversation. Use them to resolve '방금', '그거', corrections, and verification questions.\n");
		for (AvaAiMessageEntity message : toolMessages) {
			state.append("- ");
			if (message.getCreatedAt() != null) {
				state.append(message.getCreatedAt()).append(' ');
			}
			state.append('[').append(limit(message.getModelName(), 80)).append("] ");
			state.append(limit(oneLine(message.getContent()), profile.toolStateMessageChars())).append('\n');
		}
		prompt.append(limit(state.toString(), profile.toolStateChars()));
	}

	private boolean isToolMessage(AvaAiMessageEntity message) {
		String modelName = message.getModelName() == null ? "" : message.getModelName().toLowerCase(Locale.ROOT);
		if (modelName.startsWith("direct-api")
			|| modelName.startsWith("mcp-style")
			|| modelName.contains("tool")
			|| modelName.contains("notion")
			|| modelName.contains("workspace")) {
			return true;
		}
		String content = message.getContent() == null ? "" : message.getContent();
		return content.contains("Notion")
			|| content.contains("작업공간")
			|| content.contains("승인")
			|| content.contains("검증")
			|| content.contains("반영했습니다");
	}

	private void appendWebSearchResults(StringBuilder prompt, List<WebSearchResult> webResults) {
		appendWebSearchResults(prompt, webResults, PromptBudgetProfile.full(historyLimit));
	}

	private void appendWebSearchResults(
		StringBuilder prompt,
		List<WebSearchResult> webResults,
		PromptBudgetProfile profile
	) {
		if (webResults.isEmpty()) {
			return;
		}
		prompt.append("\n[WEB SEARCH RESULTS]\n");
		prompt.append("These are public web search results from Google/DuckDuckGo. ");
		prompt.append("Use them for external websites, shopping sites, product searches, current facts, and internet-backed answers. ");
		prompt.append("Do not refuse only because the topic is outside internal company work. ");
		prompt.append("Mention useful source URLs briefly in Korean.\n");
		int resultCount = Math.min(webResults.size(), profile.webResultLimit());
		for (int index = 0; index < resultCount; index++) {
				WebSearchResult result = webResults.get(index);
				prompt.append("\n[WEB ").append(index + 1).append("]\n");
				prompt.append("Engine: ").append(result.source()).append("\n");
				prompt.append("Title: ").append(limit(result.title(), profile.webTitleChars())).append("\n");
				prompt.append("URL: ").append(limit(result.url(), profile.webUrlChars())).append("\n");
				prompt.append("Snippet: ").append(limit(result.snippet(), profile.webSnippetChars())).append("\n");
		}
	}

	private List<AvaAiKnowledgeItemEntity> relevantReferences(String companyName, String query) {
		if (sharedReferenceLimit <= 0) {
			return List.of();
		}
		List<AvaAiKnowledgeItemEntity> candidates = knowledgeRepository
			.findByCompanyNameIgnoreCaseAndEnabledTrue(companyName);
		if (candidates.isEmpty()) {
			return List.of();
		}
		if (embeddingService != null) {
			List<AvaAiKnowledgeItemEntity> vectorMatches = vectorReferences(candidates, query);
			if (!vectorMatches.isEmpty()) {
				return vectorMatches;
			}
		}
		Set<String> queryTokens = tokens(query);
		if (queryTokens.isEmpty()) {
			return List.of();
		}
		return candidates
			.stream()
			.map(item -> new ScoredKnowledge(item, score(item, queryTokens)))
			.filter(item -> item.score() > 0)
			.sorted(Comparator
				.comparingInt(ScoredKnowledge::score)
				.reversed()
				.thenComparing(item -> item.item().getUseCount(), Comparator.reverseOrder())
				.thenComparing(
					item -> item.item().getLastUsedAt(),
					Comparator.nullsLast(Comparator.reverseOrder())
				)
				.thenComparing(item -> item.item().getCreatedAt(), Comparator.reverseOrder()))
			.limit(sharedReferenceLimit)
			.map(ScoredKnowledge::item)
			.toList();
	}

	private List<AvaAiKnowledgeItemEntity> vectorReferences(List<AvaAiKnowledgeItemEntity> candidates, String query) {
		String normalized = query == null ? "" : query.strip();
		if (normalized.isBlank()) {
			return List.of();
		}
		float[] queryVector = embeddingService.embed(normalized);
		if (queryVector.length == 0) {
			return List.of();
		}
		String modelKey = embeddingService.modelKey();
		List<AvaAiKnowledgeItemEntity> changed = new ArrayList<>();
		List<ScoredVectorKnowledge> scored = new ArrayList<>();
		for (AvaAiKnowledgeItemEntity item : candidates) {
			ensureKnowledgeEmbedding(item, modelKey, changed);
			float[] itemVector = embeddingService.decode(item.getEmbeddingVector());
			double similarity = embeddingService.cosine(queryVector, itemVector);
			if (similarity > 0.08) {
				scored.add(new ScoredVectorKnowledge(item, similarity, score(item, tokens(query))));
			}
		}
		if (!changed.isEmpty()) {
			knowledgeRepository.saveAll(changed);
		}
		return scored.stream()
			.sorted(Comparator
				.<ScoredVectorKnowledge>comparingDouble(ScoredVectorKnowledge::similarity)
				.reversed()
				.thenComparing(Comparator.comparingInt(ScoredVectorKnowledge::keywordScore).reversed())
				.thenComparing(item -> item.item().getUseCount(), Comparator.reverseOrder())
				.thenComparing(
					item -> item.item().getLastUsedAt(),
					Comparator.nullsLast(Comparator.reverseOrder())
				)
				.thenComparing(item -> item.item().getCreatedAt(), Comparator.reverseOrder()))
			.limit(sharedReferenceLimit)
			.map(ScoredVectorKnowledge::item)
			.toList();
	}

	private void ensureKnowledgeEmbedding(
		AvaAiKnowledgeItemEntity item,
		String modelKey,
		List<AvaAiKnowledgeItemEntity> changed
	) {
		if (item.getEmbeddingVector() != null
			&& !item.getEmbeddingVector().isBlank()
			&& modelKey.equals(item.getEmbeddingModel())) {
			return;
		}
		float[] vector = embeddingService.embed(item.getCombinedText());
		item.updateEmbedding(modelKey, embeddingService.encode(vector));
		changed.add(item);
	}

	private void embedKnowledge(AvaAiKnowledgeItemEntity item) {
		if (embeddingService == null || item == null) {
			return;
		}
		float[] vector = embeddingService.embed(item.getCombinedText());
		item.updateEmbedding(embeddingService.modelKey(), embeddingService.encode(vector));
	}

	private void markReferencedKnowledgeUsed(List<AvaAiKnowledgeItemEntity> references) {
		if (references.isEmpty()) {
			return;
		}
		references.forEach(AvaAiKnowledgeItemEntity::markUsed);
		knowledgeRepository.saveAll(references);
	}

	private int score(AvaAiKnowledgeItemEntity item, Set<String> queryTokens) {
		String haystack = item.getCombinedText().toLowerCase(Locale.ROOT);
		int score = 0;
		for (String token : queryTokens) {
			if (haystack.contains(token)) {
				score++;
			}
		}
		return score;
	}

	private Set<String> tokens(String value) {
		String[] parts = value.toLowerCase(Locale.ROOT).split("[^\\p{IsAlphabetic}\\p{IsDigit}]+");
		Set<String> tokens = new HashSet<>();
		for (String part : parts) {
			if (part.length() >= 2) {
				tokens.add(part);
			}
		}
		return tokens;
	}

	private AvaAiMessageResponse toMessageResponse(
		AvaAiMessageEntity message,
		List<AvaAiReferenceResponse> references
	) {
		return new AvaAiMessageResponse(
			message.getId(),
			message.getRole().name().toLowerCase(Locale.ROOT),
			message.getContent(),
			message.getCreatedAt(),
			references
		);
	}

	private AvaAiReferenceResponse toReferenceResponse(AvaAiKnowledgeItemEntity item) {
		return new AvaAiReferenceResponse(
			item.getId(),
			preview(item.getQuestion()),
			preview(item.getAnswer()),
			item.getCreatedAt()
		);
	}

	private String normalizeContent(String content) {
		String normalized = content == null ? "" : content.strip();
		if (normalized.isBlank()) {
			throw new IllegalArgumentException("Message content is required.");
		}
		return normalized;
	}

	private String normalizeCompanyName(String companyName) {
		if (companyName == null || companyName.isBlank()) {
			return "UNKNOWN";
		}
		String normalized = companyName.strip();
		return normalized.length() > 80 ? normalized.substring(0, 80) : normalized;
	}

	private String titleFrom(String content) {
		String title = content.replaceAll("\\s+", " ").strip();
		if (title.isBlank()) {
			return "AVA AI";
		}
		return limit(title, 60);
	}

	private String preview(String content) {
		return limit(content.replaceAll("\\s+", " ").strip(), 120);
	}

	private List<AvaAiLlmClient.PromptMessage> enforcePromptBudget(
		List<AvaAiLlmClient.PromptMessage> messages,
		int tokenBudget
	) {
		if (estimatedPromptTokens(messages) <= tokenBudget) {
			return messages;
		}
		List<AvaAiLlmClient.PromptMessage> compact = new ArrayList<>(messages);
		while (compact.size() > 2 && estimatedPromptTokens(compact) > tokenBudget) {
			compact.remove(1);
		}
		if (estimatedPromptTokens(compact) <= tokenBudget) {
			return compact;
		}
		int currentEstimate = estimatedPromptTokens(compact);
		int overage = Math.max(0, currentEstimate - tokenBudget);
		AvaAiLlmClient.PromptMessage system = compact.get(0);
		int systemLimit = Math.max(700, system.content().length() - (overage * 2));
		compact.set(0, new AvaAiLlmClient.PromptMessage(system.role(), limit(system.content(), systemLimit)));
		if (estimatedPromptTokens(compact) <= tokenBudget || compact.size() < 2) {
			return compact;
		}
		int lastIndex = compact.size() - 1;
		AvaAiLlmClient.PromptMessage current = compact.get(lastIndex);
		int currentLimit = Math.max(500, current.content().length() - ((estimatedPromptTokens(compact) - tokenBudget) * 2));
		compact.set(lastIndex, new AvaAiLlmClient.PromptMessage(current.role(), limit(current.content(), currentLimit)));
		return compact;
	}

	private int estimatedPromptTokens(List<AvaAiLlmClient.PromptMessage> messages) {
		int total = 0;
		for (AvaAiLlmClient.PromptMessage message : messages) {
			total += TOKEN_OVERHEAD_PER_MESSAGE + estimatedTokens(message.role()) + estimatedTokens(message.content());
		}
		return total;
	}

	private int estimatedTokens(String value) {
		if (value == null || value.isBlank()) {
			return 0;
		}
		int cjk = 0;
		int ascii = 0;
		int other = 0;
		for (int offset = 0; offset < value.length();) {
			int codePoint = value.codePointAt(offset);
			offset += Character.charCount(codePoint);
			Character.UnicodeScript script = Character.UnicodeScript.of(codePoint);
			if (script == Character.UnicodeScript.HANGUL
				|| script == Character.UnicodeScript.HAN
				|| script == Character.UnicodeScript.HIRAGANA
				|| script == Character.UnicodeScript.KATAKANA) {
				cjk++;
			} else if (codePoint <= 0x7f) {
				ascii++;
			} else {
				other++;
			}
		}
		return (int) Math.ceil((cjk * 1.15) + (other * 0.85) + (ascii / 3.5));
	}

	private String oneLine(String content) {
		return content == null ? "" : content.replaceAll("\\s+", " ").strip();
	}

	private String limit(String content, int maxLength) {
		if (content == null) {
			return "";
		}
		if (content.length() <= maxLength) {
			return content;
		}
		return content.substring(0, Math.max(0, maxLength - 1)) + "…";
	}

	private enum PromptBudgetLevel {
		FULL,
		COMPACT,
		MINIMAL
	}

	private record PromptBudgetProfile(
		PromptBudgetLevel level,
		int tokenBudget,
		int historyMessageLimit,
		int historyContextChars,
		int historyMessageChars,
		int currentMessageChars,
		int agentStateChars,
		int toolStateChars,
		int toolStateLimit,
		int toolStateMessageChars,
		int workspaceContextChars,
		int webResultLimit,
		int webTitleChars,
		int webUrlChars,
		int webSnippetChars,
		int referenceLimit,
		int referenceQuestionChars,
		int referenceAnswerChars
	) {
		static List<PromptBudgetProfile> profiles(int configuredHistoryLimit) {
			return List.of(
				full(configuredHistoryLimit),
				compact(configuredHistoryLimit),
				minimal(configuredHistoryLimit)
			);
		}

		static PromptBudgetProfile full(int configuredHistoryLimit) {
			return new PromptBudgetProfile(
				PromptBudgetLevel.FULL,
				FULL_PROMPT_TOKEN_BUDGET,
				Math.min(configuredHistoryLimit, 18),
				Math.min(MAX_HISTORY_CONTEXT_CHARS, 3_600),
				Math.min(MAX_HISTORY_MESSAGE_CHARS, 700),
				MAX_CURRENT_MESSAGE_CHARS,
				MAX_AGENT_STATE_CHARS,
				MAX_AGENT_STATE_CHARS,
				8,
				320,
				MAX_WORKSPACE_CONTEXT_CHARS,
				MAX_WEB_RESULTS_IN_PROMPT,
				100,
				180,
				220,
				MAX_REFERENCES_IN_PROMPT,
				180,
				260
			);
		}

		static PromptBudgetProfile compact(int configuredHistoryLimit) {
			return new PromptBudgetProfile(
				PromptBudgetLevel.COMPACT,
				COMPACT_PROMPT_TOKEN_BUDGET,
				Math.min(configuredHistoryLimit, 8),
				1_200,
				280,
				1_400,
				900,
				800,
				4,
				220,
				900,
				2,
				90,
				150,
				160,
				1,
				140,
				180
			);
		}

		static PromptBudgetProfile minimal(int configuredHistoryLimit) {
			return new PromptBudgetProfile(
				PromptBudgetLevel.MINIMAL,
				MINIMAL_PROMPT_TOKEN_BUDGET,
				Math.min(configuredHistoryLimit, 4),
				520,
				180,
				900,
				520,
				480,
				2,
				160,
				520,
				1,
				80,
				120,
				120,
				1,
				100,
				120
			);
		}
	}

	private record ScoredKnowledge(AvaAiKnowledgeItemEntity item, int score) {
	}

	private record ScoredVectorKnowledge(AvaAiKnowledgeItemEntity item, double similarity, int keywordScore) {
	}
}
