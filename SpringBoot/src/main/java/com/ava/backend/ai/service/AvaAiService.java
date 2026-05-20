package com.ava.backend.ai.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.ai.dto.AvaAiChatResponse;
import com.ava.backend.ai.dto.AvaAiMessageRequest;
import com.ava.backend.ai.dto.AvaAiMessageResponse;
import com.ava.backend.ai.dto.AvaAiReferenceResponse;
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
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class AvaAiService {

	private static final String DEFAULT_CONVERSATION_TITLE = "AVA AI";
	private static final int MAX_WEB_RESULTS_IN_PROMPT = 3;
	private static final int MAX_REFERENCES_IN_PROMPT = 2;
	private static final int MAX_WORKSPACE_CONTEXT_CHARS = 1_800;
	private static final int MAX_HISTORY_CONTEXT_CHARS = 2_400;
	private static final int MAX_HISTORY_MESSAGE_CHARS = 500;
	private static final int MAX_CURRENT_MESSAGE_CHARS = 1_200;
	private static final String GREETING_MESSAGE = "\uC548\uB155\uD558\uC138\uC694. AVA AI\uC785\uB2C8\uB2E4.\n"
		+ "\uC0AC\uB0B4 \uCC44\uD305, \uD30C\uC77C, \uC11C\uBC84 \uC790\uB8CC, NAS/Notion \uAD00\uB828 \uC5C5\uBB34\uB97C \uB3C4\uC640\uB4DC\uB9B4\uAC8C\uC694. "
		+ "\uBB34\uC5C7\uC774 \uD544\uC694\uD558\uC2E0\uAC00\uC694?";

	private final AvaAiConversationRepository conversationRepository;
	private final AvaAiMessageRepository messageRepository;
	private final AvaAiKnowledgeItemRepository knowledgeRepository;
	private final UserAccountRepository accountRepository;
	private final UserProfileRepository profileRepository;
	private final AvaAiLlmClient llmClient;
	private final AvaAiWebSearchService webSearchService;
	private final AvaAiWorkspaceService workspaceService;
	private final CompanyScopeService companyScopeService;
	private final int sharedReferenceLimit;
	private final int historyLimit;

	public AvaAiService(
		AvaAiConversationRepository conversationRepository,
		AvaAiMessageRepository messageRepository,
		AvaAiKnowledgeItemRepository knowledgeRepository,
		UserAccountRepository accountRepository,
		UserProfileRepository profileRepository,
		AvaAiLlmClient llmClient,
		AvaAiWebSearchService webSearchService,
		AvaAiWorkspaceService workspaceService,
		CompanyScopeService companyScopeService,
		@Value("${ava.ai.shared-reference-limit:5}") int sharedReferenceLimit,
		@Value("${ava.ai.history-limit:24}") int historyLimit
	) {
		this.conversationRepository = conversationRepository;
		this.messageRepository = messageRepository;
		this.knowledgeRepository = knowledgeRepository;
		this.accountRepository = accountRepository;
		this.profileRepository = profileRepository;
		this.llmClient = llmClient;
		this.webSearchService = webSearchService;
		this.workspaceService = workspaceService;
		this.companyScopeService = companyScopeService;
		this.sharedReferenceLimit = Math.max(0, sharedReferenceLimit);
		this.historyLimit = Math.max(4, historyLimit);
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

		List<AvaAiKnowledgeItemEntity> references = relevantReferences(companyName, content);
		List<WebSearchResult> webResults = webSearchService.searchIfNeeded(content);
		WorkspaceActionResult workspace = workspaceService.inspectPrompt(
			content,
			principal,
			webResults,
			request.workspacePaths()
		);
		String answer;
		if (workspace.handled()) {
			answer = workspaceHandledAnswer(workspace);
		} else {
			List<AvaAiLlmClient.PromptMessage> prompt = buildPrompt(
				conversation,
				userMessage,
				references,
				webResults,
				workspace.promptContext()
			);
			answer = llmClient.complete(prompt);
		}
		markReferencedKnowledgeUsed(references);
		AvaAiMessageEntity assistantMessage = messageRepository.save(new AvaAiMessageEntity(
			conversation.getId(),
			account.getId(),
			companyName,
			AvaAiMessageRole.ASSISTANT,
			answer,
			llmClient.model()
		));

		knowledgeRepository.save(new AvaAiKnowledgeItemEntity(
			companyName,
			conversation.getId(),
			userMessage.getId(),
			assistantMessage.getId(),
			account.getId(),
			displayName,
			content,
			answer
		));
		conversation.setCompanyName(companyName);
		conversationRepository.save(conversation);

		List<AvaAiReferenceResponse> referenceResponses = references.stream()
			.map(this::toReferenceResponse)
			.toList();
		return new AvaAiChatResponse(
			toMessageResponse(userMessage, List.of()),
			toMessageResponse(assistantMessage, referenceResponses),
			workspace.items(),
			workspace.status()
		);
	}

	@Transactional
	public void resetCurrentConversation(AuthPrincipal principal) {
		String companyName = companyScopeService.effectiveCompany(principal);
		conversationRepository.findByAccountIdAndCompanyNameIgnoreCase(principal.userId(), companyName)
			.ifPresent(conversation -> messageRepository.deleteByConversationId(conversation.getId()));
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

	private List<AvaAiLlmClient.PromptMessage> buildPrompt(
		AvaAiConversationEntity conversation,
		AvaAiMessageEntity currentMessage,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext
	) {
		List<AvaAiLlmClient.PromptMessage> messages = new ArrayList<>();
		messages.add(new AvaAiLlmClient.PromptMessage(
			"system",
			systemPrompt(conversation.getCompanyName(), references, webResults, workspaceContext)
		));

		List<AvaAiMessageEntity> recent = messageRepository
			.findTop24ByConversationIdOrderByCreatedAtDesc(conversation.getId())
			.stream()
			.sorted(Comparator.comparing(AvaAiMessageEntity::getCreatedAt))
			.toList();
		messages.addAll(historyPromptMessages(recent, currentMessage));
		messages.add(new AvaAiLlmClient.PromptMessage(
			"user",
			limit(currentMessage.getContent(), MAX_CURRENT_MESSAGE_CHARS)
		));
		return messages;
	}

	private List<AvaAiLlmClient.PromptMessage> historyPromptMessages(
		List<AvaAiMessageEntity> recent,
		AvaAiMessageEntity currentMessage
	) {
		List<AvaAiLlmClient.PromptMessage> history = new ArrayList<>();
		int fromIndex = Math.max(0, recent.size() - historyLimit);
		int remaining = MAX_HISTORY_CONTEXT_CHARS;
		for (int index = recent.size() - 1; index >= fromIndex; index--) {
			AvaAiMessageEntity message = recent.get(index);
			if (message.getId().equals(currentMessage.getId())) {
				continue;
			}
			String content = limit(message.getContent(), Math.min(MAX_HISTORY_MESSAGE_CHARS, remaining));
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

	private String systemPrompt(
		String companyName,
		List<AvaAiKnowledgeItemEntity> references,
		List<WebSearchResult> webResults,
		String workspaceContext
	) {
		StringBuilder prompt = new StringBuilder();
		prompt.append("너는 AVA 사내메신저의 AI 비서다. 항상 한국어로 간결하고 정확하게 답한다.\n");
		prompt.append("회사명: ").append(companyName).append("\n");
		prompt.append("DB, 채팅, 파일, NAS, Notion 같은 실제 조회나 쓰기 작업은 연결된 도구/API 결과가 있을 때만 완료했다고 말한다.\n");
		prompt.append("사용자가 공개 인터넷, 외부 사이트, 쇼핑몰, 뉴스, 문서, 가격, 상품 검색을 요청하면 사내 업무와 무관해도 웹 검색 결과를 바탕으로 도와준다.\n");
		prompt.append("외부 사이트라는 이유만으로 거절하지 않는다. 다만 결제, 로그인, 주문, 구매 확정 같은 행위는 직접 수행하지 않고 사용자가 직접 진행해야 한다고 안내한다.\n");
		prompt.append("웹 검색 결과가 있으면 결과의 제목, 요약, URL을 근거로 답하고, 결과가 부족하면 가져온 범위와 추가 검색 키워드를 알려준다.\n");
		prompt.append("작업공간 결과가 있으면 파일, 채팅, 회의록, 웹 결과를 근거로 답하고 실제 전송/수정 작업 상태를 명확히 말한다.\n");
		prompt.append("지금 모르는 사실은 추측하지 말고, 확인이 필요한 정보와 다음 조치를 말한다.\n");
		prompt.append("아래 회사 공용 참고자료는 이전 AVA AI 대화에서 축적된 검색 메모리다. 관련 있는 사실만 현재 답변에 반영하고 원문을 불필요하게 노출하지 않는다.\n");
		appendWebSearchResults(prompt, webResults);
		if (workspaceContext != null && !workspaceContext.isBlank()) {
			prompt.append("\n[AVA AI WORKSPACE RESULTS]\n")
				.append(limit(workspaceContext, MAX_WORKSPACE_CONTEXT_CHARS))
				.append('\n');
		}
		if (references.isEmpty()) {
			return prompt.toString();
		}
		int referenceCount = Math.min(references.size(), MAX_REFERENCES_IN_PROMPT);
		for (int index = 0; index < referenceCount; index++) {
			AvaAiKnowledgeItemEntity item = references.get(index);
			prompt.append("\n[공용 참고자료 ").append(index + 1).append("]\n");
			prompt.append("질문: ").append(limit(item.getQuestion(), 180)).append("\n");
			prompt.append("답변: ").append(limit(item.getAnswer(), 260)).append("\n");
		}
		return prompt.toString();
	}

	private void appendWebSearchResults(StringBuilder prompt, List<WebSearchResult> webResults) {
		if (webResults.isEmpty()) {
			return;
		}
		prompt.append("\n[WEB SEARCH RESULTS]\n");
		prompt.append("These are public web search results from Google/DuckDuckGo. ");
		prompt.append("Use them for external websites, shopping sites, product searches, current facts, and internet-backed answers. ");
		prompt.append("Do not refuse only because the topic is outside internal company work. ");
		prompt.append("Mention useful source URLs briefly in Korean.\n");
		int resultCount = Math.min(webResults.size(), MAX_WEB_RESULTS_IN_PROMPT);
		for (int index = 0; index < resultCount; index++) {
				WebSearchResult result = webResults.get(index);
				prompt.append("\n[WEB ").append(index + 1).append("]\n");
				prompt.append("Engine: ").append(result.source()).append("\n");
				prompt.append("Title: ").append(limit(result.title(), 100)).append("\n");
				prompt.append("URL: ").append(limit(result.url(), 180)).append("\n");
				prompt.append("Snippet: ").append(limit(result.snippet(), 220)).append("\n");
		}
	}

	private List<AvaAiKnowledgeItemEntity> relevantReferences(String companyName, String query) {
		if (sharedReferenceLimit <= 0) {
			return List.of();
		}
		Set<String> queryTokens = tokens(query);
		if (queryTokens.isEmpty()) {
			return List.of();
		}
		return knowledgeRepository
			.findByCompanyNameIgnoreCaseAndEnabledTrue(companyName)
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

	private String limit(String content, int maxLength) {
		if (content == null) {
			return "";
		}
		if (content.length() <= maxLength) {
			return content;
		}
		return content.substring(0, Math.max(0, maxLength - 1)) + "…";
	}

	private record ScoredKnowledge(AvaAiKnowledgeItemEntity item, int score) {
	}
}
