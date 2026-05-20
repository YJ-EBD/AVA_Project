package com.ava.backend.ai.service;

import java.io.IOException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.text.Normalizer;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Instant;
import java.time.ZoneId;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.ai.dto.AvaAiWorkspaceFileRequest;
import com.ava.backend.ai.dto.AvaAiWorkspaceItemResponse;
import com.ava.backend.ai.dto.AvaAiWorkspaceSendRequest;
import com.ava.backend.ai.service.AvaAiWebSearchService.WebSearchResult;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.entity.AzoomChatMessageEntity;
import com.ava.backend.azoom.entity.AzoomMeetingTranscriptKind;
import com.ava.backend.azoom.repository.AzoomChatMessageRepository;
import com.ava.backend.azoom.repository.AzoomMeetingTranscriptRepository;
import com.ava.backend.azoom.repository.AzoomMeetingUtteranceRepository;
import com.ava.backend.azoom.service.AzoomService;
import com.ava.backend.chat.dto.ChatMessageRequest;
import com.ava.backend.chat.dto.ChatMessageResponse;
import com.ava.backend.chat.dto.ChatRealtimeEvent;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTalkDrawerItemResponse;
import com.ava.backend.chat.dto.DirectChatRoomRequest;
import com.ava.backend.chat.entity.ChatMessageEntity;
import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.service.ChatService;
import com.ava.backend.user.dto.UserProfileResponse;

@Service
public class AvaAiWorkspaceService {

	private static final int MAX_FILE_RESULTS = 80;
	private static final int MAX_FILE_CANDIDATES = 100_000;
	private static final int MAX_CHAT_RESULTS = 60;
	private static final int MAX_MEETING_RESULTS = 30;
	private static final int MAX_READ_BYTES = 1_000_000;
	private static final int MAX_FILE_CONTENT_SCAN_BYTES = 256_000;
	private static final ZoneId WORKSPACE_TIME_ZONE = ZoneId.of("Asia/Seoul");
	private static final Pattern FILE_EXTENSION_PATTERN = Pattern.compile("(?i)\\.([a-z0-9]{1,12})(?=$|[^a-z0-9])");
	private static final Set<String> ARDUINO_FILE_EXTENSIONS = Set.of("ino", "pde");
	private static final Set<String> SOURCE_CODE_EXTENSIONS = Set.of(
		"ino",
		"pde",
		"c",
		"cc",
		"cpp",
		"cxx",
		"h",
		"hh",
		"hpp",
		"hxx",
		"java",
		"kt",
		"kts",
		"dart",
		"py",
		"js",
		"jsx",
		"ts",
		"tsx",
		"cs",
		"go",
		"rs",
		"php",
		"swift",
		"m",
		"mm",
		"vb",
		"sql",
		"sh",
		"bash",
		"zsh",
		"ps1",
		"bat",
		"cmd",
		"gradle",
		"cmake",
		"mk"
	);
	private static final Set<String> TEXT_SEARCH_EXTENSIONS = Set.of(
		"ino",
		"pde",
		"c",
		"cc",
		"cpp",
		"cxx",
		"h",
		"hh",
		"hpp",
		"hxx",
		"java",
		"kt",
		"kts",
		"dart",
		"py",
		"js",
		"jsx",
		"ts",
		"tsx",
		"cs",
		"go",
		"rs",
		"php",
		"swift",
		"m",
		"mm",
		"vb",
		"sql",
		"sh",
		"bash",
		"zsh",
		"ps1",
		"bat",
		"cmd",
		"gradle",
		"cmake",
		"mk",
		"txt",
		"md",
		"markdown",
		"csv",
		"tsv",
		"log",
		"json",
		"jsonl",
		"yaml",
		"yml",
		"xml",
		"html",
		"htm",
		"css",
		"scss",
		"sass",
		"properties",
		"conf",
		"config",
		"ini",
		"env",
		"toml"
	);
	private static final Set<String> SOURCE_CODE_INTENT_TOKENS = Set.of(
		"\uC18C\uC2A4",
		"\uC18C\uC2A4\uCF54\uB4DC",
		"\uCF54\uB4DC",
		"\uC2A4\uCF00\uCE58",
		"\uC544\uB450\uC774\uB178",
		"\uC774\uB178",
		"\uD38C\uC6E8\uC5B4",
		"source",
		"code",
		"src",
		"sketch",
		"arduino",
		"ino",
		"firmware"
	);
	private static final Set<String> ARDUINO_INTENT_TOKENS = Set.of(
		"\uC544\uB450\uC774\uB178",
		"\uC774\uB178",
		"arduino",
		"ino",
		"sketch"
	);
	private static final Set<String> KOREAN_FILE_INTENT_WORDS = Set.of(
		"\uD30C\uC77C", // file
		"\uD3F4\uB354", // folder
		"\uBB38\uC11C", // document
		"\uC790\uB8CC", // material
		"\uAC1C\uBC1C\uC548", // development plan
		"\uAC1C\uBC1C\uC790\uB8CC", // development material
		"\uBCF4\uACE0\uC11C", // report
		"\uAE30\uB2A5\uC815\uC758\uC11C", // feature definition
		"\uAE30\uB2A5\uC124\uBA85\uC11C", // feature manual
		"\uAE30\uC220\uC790\uB8CC", // technical material
		"\uD504\uB85C\uC81D\uD2B8", // project
		"\uC81C\uC548\uC11C", // proposal
		"\uAE30\uD68D\uC548", // plan
		"\uACC4\uD68D\uC548", // plan
		"\uC2A4\uD399", // spec
		"\uC0AC\uC591\uC11C", // specification
		"\uC124\uBA85\uC11C", // manual
		"\uC548\uB0B4\uC11C", // guide
		"\uB9AC\uD3EC\uD2B8", // report
		"\uC774\uBBF8\uC9C0", // image
		"\uC0AC\uC9C4", // picture
		"\uB85C\uACE0", // logo
		"\uD38C\uC6E8\uC5B4", // firmware
		"\uC18C\uC2A4", // source
		"\uC18C\uC2A4\uCF54\uB4DC", // source code
		"\uCF54\uB4DC", // code
		"\uC544\uB450\uC774\uB178", // arduino
		"\uC2A4\uCF00\uCE58", // sketch
		"\uB4DC\uB77C\uC774\uBC84", // driver
		"\uBC31\uC5C5", // backup
		"\uD68C\uB85C\uB3C4", // schematic
		"\uD540\uC544\uC6C3", // pinout
		"\uD540\uB9F5" // pinmap
	);
	private static final Set<String> KOREAN_SEARCH_COMMAND_WORDS = Set.of(
		"\uCC3E\uC544",
		"\uCC3E\uC544\uC918",
		"\uCC3E\uAE30",
		"\uCC3E\uC544\uBD10",
		"\uCC3E\uC544\uC904\uB798",
		"\uAC80\uC0C9",
		"\uAC80\uC0C9\uD574",
		"\uAC80\uC0C9\uD574\uC918",
		"\uAC80\uC0C9\uD574\uBD10",
		"\uBCF4\uC5EC",
		"\uBCF4\uC5EC\uC918",
		"\uC54C\uB824",
		"\uC54C\uB824\uC918",
		"\uC5F4\uC5B4",
		"\uC5F4\uC5B4\uC918",
		"\uBAA9\uB85D",
		"\uB9AC\uC2A4\uD2B8",
		"\uC5B4\uB514",
		"\uC704\uCE58"
	);
	private static final Set<String> FILE_SEARCH_STOPWORDS = Set.of(
		"\uD30C\uC77C",
		"\uD3F4\uB354",
		"\uC791\uC5C5\uACF5\uAC04",
		"\uC624\uB298",
		"\uC5B4\uC81C",
		"\uC624\uC804",
		"\uC624\uD6C4",
		"\uC804\uBD80",
		"\uBAA8\uB450",
		"\uC804\uCCB4",
		"\uC788\uB294",
		"\uC788\uC5B4",
		"\uAD00\uB828",
		"\uAD00\uB828\uB41C",
		"\uC548\uC5D0",
		"\uC548\uC758",
		"file",
		"files",
		"folder",
		"folders",
		"directory",
		"directories",
		"workspace",
		"find",
		"search",
		"show",
		"open",
		"list",
		"where",
		"all",
		"related"
	);
	private static final Pattern HOUR_PATTERN = Pattern.compile("(오전|오후)?\\s*(\\d{1,2})\\s*시");
	private static final Set<String> CHAT_STOPWORDS = Set.of(
		"채팅", "말했", "말한", "올린", "보낸", "메시지", "사진", "이미지", "첨부", "파일",
		"뭐였지", "무엇", "내용", "내역", "오늘", "어제", "오전", "오후", "시간", "쯤",
		"했던", "했", "한", "찾아줘", "찾아", "알려줘", "보여줘"
	);
	private static final Set<String> MEETING_STOPWORDS = Set.of(
		"회의", "회의록", "회의내용", "통파일", "내용", "요약", "뭐지", "무엇", "오늘",
		"어제", "오전", "오후", "시간", "쯤", "했던", "했", "한", "찾아줘", "찾아", "알려줘", "보여줘"
	);

	private final Path rootPath;
	private final Path uploadPath;
	private final Path chatAttachmentPath;
	private final ChatService chatService;
	private final ChatMessageJpaRepository chatMessageRepository;
	private final AzoomService azoomService;
	private final AzoomChatMessageRepository azoomChatMessageRepository;
	private final AzoomMeetingTranscriptRepository transcriptRepository;
	private final AzoomMeetingUtteranceRepository utteranceRepository;
	private final SimpMessagingTemplate messagingTemplate;

	public AvaAiWorkspaceService(
		ChatService chatService,
		ChatMessageJpaRepository chatMessageRepository,
		AzoomService azoomService,
		AzoomChatMessageRepository azoomChatMessageRepository,
		AzoomMeetingTranscriptRepository transcriptRepository,
		AzoomMeetingUtteranceRepository utteranceRepository,
		SimpMessagingTemplate messagingTemplate,
		@Value("${ava.ai.workspace.root:F:/}") String root,
		@Value("${ava.ai.workspace.upload-directory:AVA_AI_Workspace}") String uploadDirectory,
		@Value("${ava.chat.attachment-directory:ChatUploads}") String chatAttachmentDirectory
	) {
		this.rootPath = Path.of(root).toAbsolutePath().normalize();
		this.uploadPath = this.rootPath.resolve(uploadDirectory).normalize();
		this.chatAttachmentPath = Path.of(chatAttachmentDirectory).toAbsolutePath().normalize();
		this.chatService = chatService;
		this.chatMessageRepository = chatMessageRepository;
		this.azoomService = azoomService;
		this.azoomChatMessageRepository = azoomChatMessageRepository;
		this.transcriptRepository = transcriptRepository;
		this.utteranceRepository = utteranceRepository;
		this.messagingTemplate = messagingTemplate;
	}

	public WorkspaceActionResult inspectPrompt(
		String prompt,
		AuthPrincipal principal,
		List<WebSearchResult> webResults,
		List<String> workspacePaths
	) {
		List<AvaAiWorkspaceItemResponse> items = new ArrayList<>();
		String status = "";
		String normalized = normalize(prompt).toLowerCase(Locale.ROOT);
		if (hasSendIntent(normalized) && workspacePaths != null && !workspacePaths.isEmpty()) {
			SendResult result = sendToChat(new AvaAiWorkspaceSendRequest(
				null,
				extractRecipient(prompt),
				extractSendMessage(prompt),
				workspacePaths
			), principal);
			return new WorkspaceActionResult(
				List.copyOf(limitItems(result.items(), 120)),
				result.status(),
				promptContext(result.items(), result.status()),
				true
			);
		}
		if (!webResults.isEmpty()) {
			items.addAll(webResults.stream()
				.map(this::webItem)
				.toList());
		}
		items.addAll(mutateFilesFromPrompt(prompt, normalized, principal));
		if (hasFileSearchIntent(normalized)) {
			List<AvaAiWorkspaceItemResponse> fileResults = searchFiles(stripSearchCommands(prompt), "", principal);
			items.addAll(fileResults);
			if (!fileResults.isEmpty()) {
				status = "FORIVER_NAS 전체 파일 검색 결과 " + fileResults.size() + "개를 찾았습니다.";
			}
		}
		if (hasChatIntent(normalized)) {
			items.addAll(searchChat(prompt, principal));
			items.addAll(searchAzoomChat(prompt, principal));
		}
		if (hasMeetingIntent(normalized)) {
			items.addAll(searchMeetings(prompt, principal));
		}
		return new WorkspaceActionResult(List.copyOf(limitItems(items, 120)), status, promptContext(items, status), false);
	}

	public List<AvaAiWorkspaceItemResponse> listFiles(String path, AuthPrincipal principal) {
		Path directory = resolveInsideRoot(path);
		if (!Files.isDirectory(directory)) {
			throw new IllegalArgumentException("Workspace path is not a directory.");
		}
		try (Stream<Path> stream = Files.list(directory)) {
			return stream
				.sorted(Comparator
					.comparing((Path item) -> !Files.isDirectory(item))
					.thenComparing(item -> item.getFileName().toString().toLowerCase(Locale.ROOT)))
				.limit(MAX_FILE_RESULTS)
				.map(this::fileItem)
				.toList();
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to list workspace files.", exception);
		}
	}

	public List<AvaAiWorkspaceItemResponse> searchFiles(String query, String path, AuthPrincipal principal) {
		Path start = resolveInsideRoot(path);
		if (!Files.exists(start)) {
			return List.of();
		}
		FileSearchQuery searchQuery = fileSearchQuery(query);
		if (searchQuery.tokens().isEmpty()) {
			return listFiles(path, principal);
		}
		List<ScoredPath> results = new ArrayList<>();
		searchDirectory(start, searchQuery, results);
		return results.stream()
			.sorted(Comparator
				.comparingInt(ScoredPath::score).reversed()
			.thenComparing(item -> relativePath(item.path()).length())
			.thenComparing(item -> relativePath(item.path()).toLowerCase(Locale.ROOT)))
			.limit(MAX_FILE_RESULTS)
			.map(item -> fileItem(item.path(), searchSnippet(item.path(), searchQuery)))
			.toList();
	}

	public AvaAiWorkspaceItemResponse readFile(String path, AuthPrincipal principal) {
		Path file = resolveInsideRoot(path);
		if (!Files.isRegularFile(file)) {
			throw new IllegalArgumentException("Workspace file not found.");
		}
		try {
			long size = Files.size(file);
			if (size > MAX_READ_BYTES) {
				return fileItem(file, "파일이 1MB보다 커서 작업공간 미리보기는 생략했습니다.");
			}
			String content = Files.readString(file, StandardCharsets.UTF_8);
			return fileItem(file, content);
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to read workspace file.", exception);
		}
	}

	public WorkspaceDownload previewFile(String path, AuthPrincipal principal) {
		Path file = resolveInsideRoot(path);
		if (!Files.isRegularFile(file)) {
			throw new IllegalArgumentException("Workspace file not found.");
		}
		try {
			String contentType = Files.probeContentType(file);
			if (contentType == null || contentType.isBlank()) {
				contentType = "application/octet-stream";
			}
			Resource resource = new UrlResource(file.toUri());
			if (!resource.exists() || !resource.isReadable()) {
				throw new IllegalArgumentException("Workspace file is not readable.");
			}
			return new WorkspaceDownload(resource, file.getFileName().toString(), contentType, Files.size(file));
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to read workspace file.", exception);
		}
	}

	public AvaAiWorkspaceItemResponse create(AvaAiWorkspaceFileRequest request, AuthPrincipal principal) {
		Path target = resolveInsideRoot(request.path());
		try {
			if (request.isDirectory()) {
				Files.createDirectories(target);
				return fileItem(target, "폴더를 생성했습니다.");
			}
			if (Files.exists(target)) {
				throw new IllegalArgumentException("Workspace file already exists.");
			}
			Path parent = target.getParent();
			if (parent != null) {
				Files.createDirectories(parent);
			}
			Files.writeString(target, request.content() == null ? "" : request.content(), StandardCharsets.UTF_8);
			return fileItem(target, "파일을 생성했습니다.");
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to create workspace file.", exception);
		}
	}

	public AvaAiWorkspaceItemResponse update(AvaAiWorkspaceFileRequest request, AuthPrincipal principal) {
		Path target = resolveInsideRoot(request.path());
		if (!Files.exists(target)) {
			throw new IllegalArgumentException("Workspace path not found.");
		}
		try {
			Path updatedTarget = target;
			String requestedNewPath = request.normalizedNewPath();
			if (!requestedNewPath.isBlank() && !requestedNewPath.equals(request.path())) {
				updatedTarget = resolveInsideRoot(requestedNewPath);
				Path parent = updatedTarget.getParent();
				if (parent != null) {
					Files.createDirectories(parent);
				}
				Files.move(target, updatedTarget);
			}
			if (request.content() != null) {
				if (!Files.isRegularFile(updatedTarget)) {
					throw new IllegalArgumentException("Workspace file content can only be updated for files.");
				}
				Files.writeString(updatedTarget, request.content(), StandardCharsets.UTF_8);
			}
			return fileItem(updatedTarget, "수정했습니다.");
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to update workspace path.", exception);
		}
	}

	private AvaAiWorkspaceItemResponse updateLegacy(AvaAiWorkspaceFileRequest request, AuthPrincipal principal) {
		Path target = resolveInsideRoot(request.path());
		if (!Files.exists(target)) {
			throw new IllegalArgumentException("Workspace path not found.");
		}
		try {
			Files.writeString(target, request.content() == null ? "" : request.content(), StandardCharsets.UTF_8);
			return fileItem(target, "파일을 수정했습니다.");
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to update workspace file.", exception);
		}
	}

	public AvaAiWorkspaceItemResponse delete(String path, AuthPrincipal principal) {
		Path target = resolveInsideRoot(path);
		if (!Files.exists(target)) {
			throw new IllegalArgumentException("Workspace path not found.");
		}
		if (target.equals(rootPath)) {
			throw new IllegalArgumentException("FORIVER_NAS root cannot be deleted.");
		}
		AvaAiWorkspaceItemResponse item = fileItem(target, "삭제했습니다.");
		try {
			if (Files.isDirectory(target)) {
				try (Stream<Path> walk = Files.walk(target)) {
					for (Path itemPath : walk.sorted(Comparator.reverseOrder()).toList()) {
						Files.deleteIfExists(itemPath);
					}
				}
			} else {
				Files.delete(target);
			}
			return item;
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to delete workspace path.", exception);
		}
	}

	public List<AvaAiWorkspaceItemResponse> upload(List<MultipartFile> files, AuthPrincipal principal) {
		if (files == null || files.isEmpty()) {
			throw new IllegalArgumentException("Workspace upload file is required.");
		}
		try {
			Files.createDirectories(uploadPath);
			List<AvaAiWorkspaceItemResponse> items = new ArrayList<>();
			for (MultipartFile file : files) {
				if (file == null || file.isEmpty()) {
					continue;
				}
				String fileName = sanitizeFileName(file.getOriginalFilename());
				Path target = uploadPath.resolve(Instant.now().toEpochMilli() + "-" + fileName).normalize();
				assertInsideRoot(target);
				file.transferTo(target);
				items.add(fileItem(target, "작업공간에 업로드했습니다."));
			}
			return items;
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to upload workspace file.", exception);
		}
	}

	@Transactional
	public SendResult sendToChat(AvaAiWorkspaceSendRequest request, AuthPrincipal principal) {
		List<String> paths = request.paths() == null ? List.of() : request.paths();
		if (paths.isEmpty()) {
			throw new IllegalArgumentException("Workspace file path is required.");
		}
		ChatRoomResponse room = resolveRoom(request, principal);
		String groupId = "ava-ai-" + UUID.randomUUID();
		List<AvaAiWorkspaceItemResponse> sentItems = new ArrayList<>();
		for (String path : paths) {
			Path file = resolveSendableFile(path);
			if (!Files.isRegularFile(file)) {
				continue;
			}
			ChatMessageResponse response = chatService.sendAttachmentFromPath(room.code(), file, groupId, principal);
			publishRoomEvent(room, response);
			sentItems.add(sendableFileItem(file, room.title() + " 채팅방으로 전송했습니다."));
		}
		String message = request.message() == null ? "" : request.message().trim();
		if (!message.isBlank()) {
			ChatMessageResponse response = chatService.send(room.code(), new ChatMessageRequest(message, false, false), principal);
			publishRoomEvent(room, response);
		}
		String status = room.title() + " 채팅방으로 " + sentItems.size() + "개 파일을 전송했습니다.";
		if (!message.isBlank()) {
			status += " 메시지도 함께 보냈습니다.";
		}
		return new SendResult(status, List.copyOf(sentItems));
	}

	public List<AvaAiWorkspaceItemResponse> searchChat(String query, AuthPrincipal principal) {
		String normalized = normalize(query).toLowerCase(Locale.ROOT);
		List<String> tokens = tokens(normalized, CHAT_STOPWORDS);
		QueryHints hints = queryHints(normalized);
		List<AvaAiWorkspaceItemResponse> items = new ArrayList<>();
		for (ChatRoomResponse room : chatService.rooms(principal)) {
			List<ChatMessageEntity> messages = new ArrayList<>(
				chatMessageRepository.findByRoomCodeOrderBySentAtAsc(room.code())
			);
			messages.sort(Comparator.comparing(ChatMessageEntity::getSentAt).reversed());
			for (ChatMessageEntity message : messages) {
				if (items.size() >= MAX_CHAT_RESULTS) {
					return List.copyOf(items);
				}
				if (!matchesTimeHints(message.getSentAt(), hints)) {
					continue;
				}
				String haystack = (message.getSenderName() + " " + message.getContent() + " " +
					(message.getAttachmentFileName() == null ? "" : message.getAttachmentFileName()))
					.toLowerCase(Locale.ROOT);
				if (!tokens.isEmpty() && tokens.stream().noneMatch(haystack::contains)) {
					continue;
				}
				items.add(new AvaAiWorkspaceItemResponse(
					message.hasAttachment() ? "chat_file" : "chat_message",
					room.title(),
					message.getSenderName() + " · " + message.getSentAt(),
					message.getAttachmentStoredPath(),
					message.hasAttachment()
						? "/api/chat/rooms/" + room.code() + "/attachments/" + message.getAttachmentId()
						: "",
					isImage(message.getAttachmentContentType(), message.getAttachmentFileName())
						? "/api/chat/rooms/" + room.code() + "/attachments/" + message.getAttachmentId()
						: "",
					message.getContent(),
					message.hasAttachment() ? message.getAttachmentSize() : null,
					message.getSentAt(),
					room.code()
				));
			}
			for (ChatTalkDrawerItemResponse drawerItem : chatService.talkDrawerItems(room.code(), null, principal)) {
				if (items.size() >= MAX_CHAT_RESULTS) {
					return List.copyOf(items);
				}
				if (!matchesTimeHints(drawerItem.uploadedAt(), hints)) {
					continue;
				}
				String haystack = (drawerItem.fileName() + " " + drawerItem.uploadedByName()).toLowerCase(Locale.ROOT);
				if (!tokens.isEmpty() && tokens.stream().noneMatch(haystack::contains)) {
					continue;
				}
				boolean drawerImage = drawerItem.mediaType() == ChatTalkDrawerMediaType.IMAGE;
				items.add(new AvaAiWorkspaceItemResponse(
					drawerImage ? "chat_image" : "chat_file",
					drawerItem.fileName(),
					room.title() + " · " + drawerItem.uploadedByName(),
					"",
					drawerItem.downloadUrl(),
					drawerImage ? drawerItem.downloadUrl() : "",
					"",
					drawerItem.size(),
					drawerItem.uploadedAt(),
					room.code()
				));
			}
		}
		return List.copyOf(items);
	}

	public List<AvaAiWorkspaceItemResponse> searchAzoomChat(String query, AuthPrincipal principal) {
		var workspace = azoomService.workspaceForNotiva(principal);
		String normalized = normalize(query).toLowerCase(Locale.ROOT);
		List<String> tokens = tokens(normalized, CHAT_STOPWORDS);
		QueryHints hints = queryHints(normalized);
		List<AvaAiWorkspaceItemResponse> items = new ArrayList<>();
		for (AzoomChatMessageEntity message : azoomChatMessageRepository
			.findTop200ByCompanySlugOrderBySentAtDesc(workspace.getCompanySlug())) {
			if (items.size() >= MAX_CHAT_RESULTS) {
				break;
			}
			if (!matchesTimeHints(message.getSentAt(), hints)) {
				continue;
			}
			String haystack = (message.getSenderName() + " " + message.getChannelName() + " " + message.getContent())
				.toLowerCase(Locale.ROOT);
			if (!tokens.isEmpty() && tokens.stream().noneMatch(haystack::contains)) {
				continue;
			}
			items.add(new AvaAiWorkspaceItemResponse(
				"azoom_chat_message",
				"AZOOM #" + message.getChannelName(),
				message.getSenderName() + " 쨌 " + message.getSentAt(),
				"",
				"",
				"",
				message.getContent(),
				null,
				message.getSentAt(),
				message.getRoomCode()
			));
		}
		return List.copyOf(items);
	}

	public List<AvaAiWorkspaceItemResponse> searchMeetings(String query, AuthPrincipal principal) {
		var workspace = azoomService.workspaceForNotiva(principal);
		String normalized = normalize(query).toLowerCase(Locale.ROOT);
		List<String> tokens = tokens(normalized, MEETING_STOPWORDS);
		QueryHints hints = queryHints(normalized);
		return transcriptRepository.findByWorkspace_IdOrderByCreatedAtDesc(workspace.getId()).stream()
			.filter(transcript -> transcript.getKind() == AzoomMeetingTranscriptKind.BATCH_AUDIO)
			.filter(transcript -> matchesTimeHints(transcript.getStartedAt(), hints))
			.map(transcript -> {
				String content = utteranceRepository.findByTranscript_IdOrderBySequenceNoAsc(transcript.getId()).stream()
					.map(utterance -> utterance.getSpeakerName() + ": " + utterance.getContent())
					.reduce((first, second) -> first + "\n" + second)
					.orElse("");
				return new AvaAiWorkspaceItemResponse(
					"meeting_batch",
					transcript.getVoiceChannelName() + " · " + transcript.getTitleTimestamp(),
					transcript.getStatus().name(),
					transcript.getAudioFilePath(),
					"",
					"",
					limit(content, 1800),
					null,
					transcript.getStartedAt(),
					""
				);
			})
			.filter(item -> tokens.isEmpty() ||
				tokens.stream().anyMatch(token -> (item.title() + " " + item.content()).toLowerCase(Locale.ROOT).contains(token)))
			.limit(MAX_MEETING_RESULTS)
			.toList();
	}

	private ChatRoomResponse resolveRoom(AvaAiWorkspaceSendRequest request, AuthPrincipal principal) {
		String roomCode = request.roomCode() == null ? "" : request.roomCode().trim();
		if (!roomCode.isBlank()) {
			return chatService.room(roomCode);
		}
		String targetName = normalize(request.targetName());
		if (targetName.isBlank()) {
			throw new IllegalArgumentException("Chat room or recipient is required.");
		}
		return chatService.startDirectRoom(new DirectChatRoomRequest(null, null, targetName), principal);
	}

	private void publishRoomEvent(ChatRoomResponse room, ChatMessageResponse message) {
		ChatRoomResponse latestRoom = chatService.room(room.code());
		messagingTemplate.convertAndSend("/topic/rooms/" + latestRoom.code(), message);
		ChatRealtimeEvent event = new ChatRealtimeEvent("message", latestRoom, message);
		for (UserProfileResponse member : latestRoom.members()) {
			messagingTemplate.convertAndSendToUser(member.email(), "/queue/chat-events", event);
		}
	}

	private AvaAiWorkspaceItemResponse webItem(WebSearchResult result) {
		return new AvaAiWorkspaceItemResponse(
			"web",
			result.title(),
			result.snippet(),
			"",
			result.url(),
			result.imageUrl(),
			result.snippet(),
			null,
			null,
			""
		);
	}

	private AvaAiWorkspaceItemResponse fileItem(Path path) {
		return fileItem(path, "");
	}

	private AvaAiWorkspaceItemResponse fileItem(Path path, String content) {
		try {
			boolean directory = Files.isDirectory(path);
			return new AvaAiWorkspaceItemResponse(
				directory ? "directory" : "file",
				path.getFileName() == null ? rootPath.toString() : path.getFileName().toString(),
				relativePath(path),
				relativePath(path),
				"",
				isImage(null, path.getFileName() == null ? "" : path.getFileName().toString()) ? previewUrl(path) : "",
				content,
				directory ? null : Files.size(path),
				Files.exists(path) ? Files.getLastModifiedTime(path).toInstant() : null,
				""
			);
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to inspect workspace file.", exception);
		}
	}

	private AvaAiWorkspaceItemResponse sendableFileItem(Path path, String content) {
		Path normalized = path.toAbsolutePath().normalize();
		if (normalized.startsWith(rootPath)) {
			return fileItem(normalized, content);
		}
		try {
			String title = normalized.getFileName() == null ? normalized.toString() : normalized.getFileName().toString();
			String subtitle = normalized.startsWith(chatAttachmentPath)
				? chatAttachmentPath.relativize(normalized).toString()
				: normalized.toString();
			return new AvaAiWorkspaceItemResponse(
				isImage(null, title) ? "chat_image" : "chat_file",
				title,
				subtitle,
				normalized.toString(),
				"",
				"",
				content,
				Files.size(normalized),
				Files.getLastModifiedTime(normalized).toInstant(),
				""
			);
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to inspect sendable file.", exception);
		}
	}

	private String searchSnippet(Path path, FileSearchQuery query) {
		if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
			return "";
		}
		String extension = extension(path);
		if (!TEXT_SEARCH_EXTENSIONS.contains(extension)) {
			return "";
		}
		try {
			if (Files.size(path) <= 0) {
				return "";
			}
			byte[] bytes;
			try (InputStream input = Files.newInputStream(path)) {
				bytes = input.readNBytes(MAX_FILE_CONTENT_SCAN_BYTES);
			}
			String content = new String(bytes, StandardCharsets.UTF_8)
				.replace('\u0000', ' ')
				.replace("\r\n", "\n")
				.replace('\r', '\n')
				.strip();
			if (content.isBlank() || looksBinary(content)) {
				return "";
			}
			String lowerContent = content.toLowerCase(Locale.ROOT);
			for (List<String> variants : query.variants()) {
				for (String variant : variants) {
					String candidate = variant.toLowerCase(Locale.ROOT).strip();
					if (candidate.length() < 2) {
						continue;
					}
					int index = lowerContent.indexOf(candidate);
					if (index >= 0) {
						return excerpt(content, index);
					}
				}
			}
			return limit(content.replaceAll("\\n{3,}", "\n\n"), 900);
		} catch (IOException | SecurityException ignored) {
			return "";
		}
	}

	private boolean looksBinary(String content) {
		int controlCount = 0;
		int sampleLength = Math.min(content.length(), 1024);
		for (int index = 0; index < sampleLength; index++) {
			char value = content.charAt(index);
			if (Character.isISOControl(value) && value != '\n' && value != '\t') {
				controlCount++;
			}
		}
		return sampleLength > 0 && controlCount > sampleLength / 20;
	}

	private String excerpt(String content, int index) {
		int start = Math.max(0, index - 220);
		int end = Math.min(content.length(), index + 680);
		String prefix = start > 0 ? "…" : "";
		String suffix = end < content.length() ? "…" : "";
		return prefix + content.substring(start, end).replaceAll("\\n{3,}", "\n\n").strip() + suffix;
	}

	private void searchDirectory(Path start, FileSearchQuery query, List<ScoredPath> results) {
		if (start == null || results.size() >= MAX_FILE_CANDIDATES) {
			return;
		}
		Deque<Path> stack = new ArrayDeque<>();
		Set<Path> visitedDirectories = new HashSet<>();
		stack.push(start);
		while (!stack.isEmpty() && results.size() < MAX_FILE_CANDIDATES) {
			Path current = stack.pop();
			if (current == null || Files.isSymbolicLink(current)) {
				continue;
			}
			int score = scoreFile(current, query);
			if (score > 0) {
				results.add(new ScoredPath(current, score));
				if (results.size() >= MAX_FILE_CANDIDATES) {
					return;
				}
			}
			if (!Files.isDirectory(current, LinkOption.NOFOLLOW_LINKS)) {
				continue;
			}
			Path normalizedDirectory = current.toAbsolutePath().normalize();
			if (!visitedDirectories.add(normalizedDirectory)) {
				continue;
			}
			try (DirectoryStream<Path> stream = Files.newDirectoryStream(current)) {
				List<Path> children = new ArrayList<>();
				for (Path child : stream) {
					children.add(child);
				}
				children.sort(Comparator.comparing(item -> relativePath(item).toLowerCase(Locale.ROOT)));
				for (int index = children.size() - 1; index >= 0; index--) {
					stack.push(children.get(index));
				}
			} catch (IOException | SecurityException ignored) {
				// NAS roots can include protected system folders; search skips unreadable branches.
			}
		}
	}

	private String extension(Path path) {
		if (path == null || path.getFileName() == null) {
			return "";
		}
		String name = path.getFileName().toString().toLowerCase(Locale.ROOT);
		int dotIndex = name.lastIndexOf('.');
		if (dotIndex < 0 || dotIndex == name.length() - 1) {
			return "";
		}
		return name.substring(dotIndex + 1);
	}

	private int scoreFile(Path path, FileSearchQuery query) {
		if (path.equals(rootPath) || query.tokens().isEmpty()) {
			return 0;
		}
		String relative = normalizeSearchText(relativePath(path));
		String name = normalizeSearchText(path.getFileName() == null ? "" : path.getFileName().toString());
		String compactRelative = compactSearchText(relative);
		String compactName = compactSearchText(name);
		List<String> pathTerms = searchTerms(relative);
		String phrase = normalizeSearchText(query.phrase());
		String compactPhrase = compactSearchText(phrase);
		String extension = extension(path);
		int score = 0;
		int matchedGroups = 0;

		if (!extension.isBlank() && query.preferredExtensions().contains(extension)) {
			score += query.arduinoIntent() && ARDUINO_FILE_EXTENSIONS.contains(extension) ? 180 : 90;
		}
		if (query.sourceCodeIntent() && !extension.isBlank() && SOURCE_CODE_EXTENSIONS.contains(extension)) {
			score += 80;
		}
		if (phrase.length() >= 2 && relative.contains(phrase)) {
			score += 120;
		}
		if (compactPhrase.length() >= 2 && compactRelative.contains(compactPhrase)) {
			score += 100;
		}

		for (List<String> variants : query.variants()) {
			boolean matched = false;
			for (String variant : variants) {
				String value = normalizeSearchText(variant);
				String compact = compactSearchText(value);
				if (value.length() < 2 && compact.length() < 2) {
					continue;
				}
				if (!extension.isBlank() && (extension.equals(compact) || extension.equals(value))) {
					score += 72;
					matched = true;
					break;
				}
				if (name.contains(value)) {
					score += 48;
					matched = true;
					break;
				}
				if (compactName.contains(compact)) {
					score += 40;
					matched = true;
					break;
				}
				if (relative.contains(value)) {
					score += 26;
					matched = true;
					break;
				}
				if (compactRelative.contains(compact)) {
					score += 20;
					matched = true;
					break;
				}
				int fuzzyScore = fuzzyVariantScore(compact, pathTerms);
				if (fuzzyScore > 0) {
					score += fuzzyScore;
					matched = true;
					break;
				}
			}
			if (matched) {
				matchedGroups++;
			}
		}

		if (matchedGroups == 0 && score == 0) {
			return 0;
		}
		if (matchedGroups == query.variants().size()) {
			score += 90;
		} else {
			score += matchedGroups * 14;
		}
		if (Files.isDirectory(path)) {
			score += 10;
		} else if (!extension.isBlank() && SOURCE_CODE_EXTENSIONS.contains(extension)) {
			score += 12;
		}
		score += Math.max(0, 24 - (relative.length() / 28));
		return score;
	}

	private FileSearchQuery fileSearchQuery(String query) {
		String phrase = stripSearchCommands(normalize(query));
		String normalizedPhrase = normalizeSearchText(phrase);
		LinkedHashSet<String> tokenSet = new LinkedHashSet<>();
		for (String token : fileTokens(phrase)) {
			if (!token.isBlank()) {
				tokenSet.add(token);
			}
		}
		LinkedHashSet<String> explicitExtensions = extractRequestedExtensions(phrase);
		boolean arduinoIntent = containsAny(normalizedPhrase, ARDUINO_INTENT_TOKENS) ||
			explicitExtensions.stream().anyMatch(ARDUINO_FILE_EXTENSIONS::contains);
		boolean sourceCodeIntent = arduinoIntent ||
			containsAny(normalizedPhrase, SOURCE_CODE_INTENT_TOKENS) ||
			explicitExtensions.stream().anyMatch(SOURCE_CODE_EXTENSIONS::contains);
		LinkedHashSet<String> preferredExtensions = new LinkedHashSet<>();
		preferredExtensions.addAll(explicitExtensions);
		if (arduinoIntent) {
			preferredExtensions.addAll(ARDUINO_FILE_EXTENSIONS);
		}
		if (sourceCodeIntent) {
			preferredExtensions.addAll(SOURCE_CODE_EXTENSIONS);
		}
		for (String extension : preferredExtensions) {
			tokenSet.add(extension);
		}
		List<String> queryTokens = List.copyOf(tokenSet);
		List<List<String>> variants = queryTokens.stream()
			.map(this::tokenVariants)
			.toList();
		return new FileSearchQuery(
			normalizedPhrase,
			queryTokens,
			variants,
			Set.copyOf(preferredExtensions),
			sourceCodeIntent,
			arduinoIntent
		);
	}

	private List<String> tokenVariants(String token) {
		LinkedHashSet<String> variants = new LinkedHashSet<>();
		addVariant(variants, token);
		switch (token) {
			case "\uAC1C\uBC1C\uC548", "\uAE30\uD68D\uC548", "\uACC4\uD68D\uC548", "\uC81C\uC548\uC11C", "plan", "proposal", "development" -> {
				addVariant(variants, "\uAC1C\uBC1C\uC548");
				addVariant(variants, "\uAE30\uD68D\uC548");
				addVariant(variants, "\uACC4\uD68D\uC548");
				addVariant(variants, "\uC81C\uC548\uC11C");
				addVariant(variants, "plan");
				addVariant(variants, "proposal");
				addVariant(variants, "development");
			}
			case "\uAC1C\uBC1C\uC790\uB8CC", "\uAE30\uC220\uC790\uB8CC", "\uC790\uB8CC", "material", "materials", "resource" -> {
				addVariant(variants, "\uAC1C\uBC1C\uC790\uB8CC");
				addVariant(variants, "\uAE30\uC220\uC790\uB8CC");
				addVariant(variants, "\uC790\uB8CC");
				addVariant(variants, "material");
				addVariant(variants, "materials");
				addVariant(variants, "resource");
			}
			case "\uAE30\uB2A5\uC815\uC758\uC11C", "\uAE30\uB2A5\uC815\uC758", "\uBA85\uC138\uC11C", "spec", "specification" -> {
				addVariant(variants, "\uAE30\uB2A5\uC815\uC758\uC11C");
				addVariant(variants, "\uAE30\uB2A5\uC815\uC758");
				addVariant(variants, "\uAE30\uB2A5\uBA85\uC138");
				addVariant(variants, "spec");
				addVariant(variants, "specification");
			}
			case "\uAE30\uB2A5\uC124\uBA85\uC11C", "\uC124\uBA85\uC11C", "manual" -> {
				addVariant(variants, "\uAE30\uB2A5\uC124\uBA85\uC11C");
				addVariant(variants, "\uAE30\uB2A5 \uC124\uBA85");
				addVariant(variants, "\uC124\uBA85\uC11C");
				addVariant(variants, "manual");
			}
			case "\uC548\uB0B4\uC11C", "guide" -> {
				addVariant(variants, "\uC548\uB0B4\uC11C");
				addVariant(variants, "guide");
			}
			case "\uBCF4\uACE0\uC11C", "report" -> {
				addVariant(variants, "\uBCF4\uACE0\uC11C");
				addVariant(variants, "report");
			}
			case "\uC0AC\uC591\uC11C", "\uC2A4\uD399\uC790\uB8CC" -> {
				addVariant(variants, "\uC0AC\uC591\uC11C");
				addVariant(variants, "spec");
				addVariant(variants, "specification");
			}
			case "\uB9AC\uD3EC\uD2B8" -> {
				addVariant(variants, "\uB9AC\uD3EC\uD2B8");
				addVariant(variants, "\uBCF4\uACE0\uC11C");
				addVariant(variants, "report");
			}
			case "\uC544\uC774\uC624\uD2F0", "iot" -> {
				addVariant(variants, "\uC544\uC774\uC624\uD2F0");
				addVariant(variants, "iot");
			}
			case "\uC778\uBC14\uB514", "inbody" -> {
				addVariant(variants, "\uC778\uBC14\uB514");
				addVariant(variants, "inbody");
			}
			case "\uCEE8\uD2B8\uB9AD\uC2A4", "conturix" -> {
				addVariant(variants, "\uCEE8\uD2B8\uB9AD\uC2A4");
				addVariant(variants, "conturix");
			}
			case "\uC368\uB9C8\uBA54\uB4DC", "thermamed", "theramed", "therma" -> {
				addVariant(variants, "\uC368\uB9C8\uBA54\uB4DC");
				addVariant(variants, "thermamed");
				addVariant(variants, "theramed");
				addVariant(variants, "therma med");
			}
			case "for", "rnd", "for_rnd", "for-rnd", "\uD3EC\uC54C\uC5D4\uB514" -> {
				addVariant(variants, "for_rnd");
				addVariant(variants, "for rnd");
				addVariant(variants, "for-rnd");
				addVariant(variants, "forrnd");
				addVariant(variants, "rnd");
			}
			case "uiux", "ui", "ux" -> {
				addVariant(variants, "uiux");
				addVariant(variants, "ui");
				addVariant(variants, "ux");
				addVariant(variants, "ui\uAD6C\uC0C1\uB3C4");
			}
			case "\uD540\uB9F5", "\uD540\uC544\uC6C3", "pinmap", "pinout" -> {
				addVariant(variants, "\uD540\uB9F5");
				addVariant(variants, "\uD540\uC544\uC6C3");
				addVariant(variants, "pinmap");
				addVariant(variants, "pinout");
			}
			case "\uD38C\uC6E8\uC5B4", "firmware" -> {
				addVariant(variants, "\uD38C\uC6E8\uC5B4");
				addVariant(variants, "firmware");
				addVariant(variants, "\uC6D0\uBCF8");
				addVariant(variants, "source");
				addVariant(variants, "src");
			}
			case "\uC544\uB450\uC774\uB178", "\uC774\uB178", "arduino", "sketch" -> {
				addVariant(variants, "\uC544\uB450\uC774\uB178");
				addVariant(variants, "\uC774\uB178");
				addVariant(variants, "arduino");
				addVariant(variants, "sketch");
				addVariant(variants, "ino");
				addVariant(variants, "pde");
				addVariant(variants, "\uD38C\uC6E8\uC5B4");
				addVariant(variants, "firmware");
			}
			case "\uC18C\uC2A4", "\uC18C\uC2A4\uCF54\uB4DC", "\uCF54\uB4DC", "source", "src", "code" -> {
				addVariant(variants, "\uC18C\uC2A4");
				addVariant(variants, "\uC18C\uC2A4\uCF54\uB4DC");
				addVariant(variants, "\uCF54\uB4DC");
				addVariant(variants, "\uD38C\uC6E8\uC5B4");
				addVariant(variants, "source");
				addVariant(variants, "src");
				addVariant(variants, "code");
				addVariant(variants, "firmware");
			}
			case "\uD68C\uB85C\uB3C4", "\uD68C\uB85C", "schematic", "circuit" -> {
				addVariant(variants, "\uD68C\uB85C\uB3C4");
				addVariant(variants, "\uD68C\uB85C");
				addVariant(variants, "schematic");
				addVariant(variants, "circuit");
			}
			case "\uB85C\uACE0", "logo" -> {
				addVariant(variants, "\uB85C\uACE0");
				addVariant(variants, "logo");
			}
			case "\uC774\uBBF8\uC9C0", "\uC0AC\uC9C4", "image", "picture", "photo" -> {
				addVariant(variants, "\uC774\uBBF8\uC9C0");
				addVariant(variants, "\uC0AC\uC9C4");
				addVariant(variants, "image");
				addVariant(variants, "picture");
				addVariant(variants, "photo");
				addVariant(variants, "png");
				addVariant(variants, "jpg");
				addVariant(variants, "jpeg");
				addVariant(variants, "webp");
			}
			case "\uB4DC\uB77C\uC774\uBC84", "driver" -> {
				addVariant(variants, "\uB4DC\uB77C\uC774\uBC84");
				addVariant(variants, "driver");
			}
			case "\uBC31\uC5C5", "backup" -> {
				addVariant(variants, "\uBC31\uC5C5");
				addVariant(variants, "backup");
			}
			case "one", "first" -> addVariant(variants, "1");
			case "two", "second" -> addVariant(variants, "2");
			case "three", "third" -> addVariant(variants, "3");
			default -> {
				if (token.endsWith("s") && token.length() > 3) {
					addVariant(variants, token.substring(0, token.length() - 1));
				}
			}
		}
		return List.copyOf(variants);
	}

	private LinkedHashSet<String> extractRequestedExtensions(String value) {
		LinkedHashSet<String> extensions = new LinkedHashSet<>();
		String normalized = normalize(value).toLowerCase(Locale.ROOT);
		Matcher matcher = FILE_EXTENSION_PATTERN.matcher(normalized);
		while (matcher.find()) {
			String extension = matcher.group(1);
			if (extension != null && extension.length() >= 1) {
				extensions.add(extension);
			}
		}
		for (String token : normalized.split("[^a-z0-9]+")) {
			if (token.endsWith("file") && token.length() > 4) {
				token = token.substring(0, token.length() - 4);
			}
			if (SOURCE_CODE_EXTENSIONS.contains(token) || TEXT_SEARCH_EXTENSIONS.contains(token)) {
				extensions.add(token);
			}
		}
		return extensions;
	}

	private void addVariant(LinkedHashSet<String> variants, String value) {
		String normalized = normalizeSearchText(value);
		if (!normalized.isBlank()) {
			variants.add(normalized);
		}
	}

	private List<String> searchTerms(String value) {
		String[] parts = normalizeSearchText(value).split("\\s+");
		List<String> terms = new ArrayList<>();
		for (String part : parts) {
			String compact = compactSearchText(part);
			if (compact.length() >= 2) {
				terms.add(compact);
			}
		}
		return terms;
	}

	private int fuzzyVariantScore(String compactVariant, List<String> terms) {
		if (compactVariant.length() < 4) {
			return 0;
		}
		int threshold = compactVariant.length() <= 5 ? 1 : 2;
		int best = 0;
		for (String term : terms) {
			if (term.length() < 4) {
				continue;
			}
			if (term.startsWith(compactVariant) || compactVariant.startsWith(term)) {
				best = Math.max(best, 18);
				continue;
			}
			if (Math.abs(term.length() - compactVariant.length()) > threshold) {
				continue;
			}
			int distance = boundedLevenshtein(compactVariant, term, threshold);
			if (distance <= threshold) {
				best = Math.max(best, 18 - (distance * 4));
			}
		}
		return best;
	}

	private int boundedLevenshtein(String left, String right, int maxDistance) {
		int[] previous = new int[right.length() + 1];
		int[] current = new int[right.length() + 1];
		for (int j = 0; j <= right.length(); j++) {
			previous[j] = j;
		}
		for (int i = 1; i <= left.length(); i++) {
			current[0] = i;
			int rowMin = current[0];
			for (int j = 1; j <= right.length(); j++) {
				int cost = left.charAt(i - 1) == right.charAt(j - 1) ? 0 : 1;
				current[j] = Math.min(
					Math.min(current[j - 1] + 1, previous[j] + 1),
					previous[j - 1] + cost
				);
				rowMin = Math.min(rowMin, current[j]);
			}
			if (rowMin > maxDistance) {
				return maxDistance + 1;
			}
			int[] temp = previous;
			previous = current;
			current = temp;
		}
		return previous[right.length()];
	}

	private Path resolveInsideRoot(String value) {
		String normalized = value == null ? "" : value.trim();
		normalized = normalized.replace('\\', '/');
		if (normalized.matches("^[A-Za-z]:/.*")) {
			normalized = normalized.substring(3);
		}
		while (normalized.startsWith("/")) {
			normalized = normalized.substring(1);
		}
		Path target = rootPath.resolve(normalized).normalize();
		assertInsideRoot(target);
		return target;
	}

	private Path resolveSendableFile(String value) {
		try {
			Path workspaceFile = resolveInsideRoot(value);
			if (Files.isRegularFile(workspaceFile)) {
				return workspaceFile;
			}
		} catch (IllegalArgumentException ignored) {
			// A chat attachment can be outside FORIVER_NAS but still be an AVA-owned file.
		}

		String normalized = value == null ? "" : value.trim();
		if (normalized.isBlank()) {
			throw new IllegalArgumentException("Workspace file path is required.");
		}
		Path candidate = Path.of(normalized);
		if (!candidate.isAbsolute()) {
			candidate = Path.of("").toAbsolutePath().resolve(candidate);
		}
		candidate = candidate.normalize();
		if (!candidate.startsWith(chatAttachmentPath)) {
			throw new IllegalArgumentException("Workspace send path must stay inside FORIVER_NAS (F:) or AVA chat attachments.");
		}
		return candidate;
	}

	private void assertInsideRoot(Path target) {
		if (!target.toAbsolutePath().normalize().startsWith(rootPath)) {
			throw new IllegalArgumentException("Workspace path must stay inside FORIVER_NAS (F:).");
		}
	}

	private String relativePath(Path path) {
		Path normalized = path.toAbsolutePath().normalize();
		if (normalized.equals(rootPath)) {
			return "";
		}
		return rootPath.relativize(normalized).toString();
	}

	private String previewUrl(Path path) {
		String relative = relativePath(path);
		if (relative.isBlank()) {
			return "";
		}
		return "/api/ai/workspace/files/preview?path=" + URLEncoder.encode(relative, StandardCharsets.UTF_8);
	}

	private String sanitizeFileName(String value) {
		String fileName = value == null || value.isBlank() ? "attachment" : value.trim();
		fileName = fileName.replace('\\', '/');
		int slash = fileName.lastIndexOf('/');
		if (slash >= 0) {
			fileName = fileName.substring(slash + 1);
		}
		fileName = fileName.replaceAll("[\\r\\n\\t]", "_").replaceAll("[<>:\"/\\\\|?*]", "_");
		return fileName.isBlank() ? "attachment" : fileName;
	}

	private boolean hasFileSearchIntent(String value) {
		if (containsAny(value, KOREAN_FILE_INTENT_WORDS)) {
			return true;
		}
		if (containsAny(
			value,
			"file",
			"folder",
			"directory",
			"document",
			"documents",
			"docs",
			"report",
			"proposal",
			"plan",
			"project",
			"spec",
			"specification",
			"manual",
			"firmware",
			"image",
			"logo",
			"uiux",
			"iot",
			"pcb",
			"nas",
			"f:"
		)) {
			return true;
		}
		return containsAny(value, KOREAN_SEARCH_COMMAND_WORDS) &&
			!fileTokens(extractSearchQuery(value)).isEmpty();
	}

	private boolean hasFileIntent(String value) {
		if (containsAny(value, KOREAN_FILE_INTENT_WORDS)) {
			return true;
		}
		return containsAny(value, "파일", "폴더", "nas", "f:", "생성", "수정", "삭제");
	}

	private List<AvaAiWorkspaceItemResponse> mutateFilesFromPrompt(
		String prompt,
		String normalized,
		AuthPrincipal principal
	) {
		String path = extractExplicitPath(prompt);
		if (path.isBlank()) {
			return List.of();
		}
		if (containsAny(normalized, "삭제", "지워")) {
			return List.of(delete(path, principal));
		}
		if (containsAny(normalized, "생성", "만들")) {
			return List.of(create(new AvaAiWorkspaceFileRequest(
				path,
				extractFileContent(prompt),
				containsAny(normalized, "폴더", "디렉토리")
			), principal));
		}
		if (containsAny(normalized, "수정", "변경", "덮어")) {
			return List.of(update(new AvaAiWorkspaceFileRequest(path, extractFileContent(prompt), false), principal));
		}
		return List.of();
	}

	private boolean hasChatIntent(String value) {
		return containsAny(value, "채팅", "말했", "올린", "보낸", "메시지", "사진", "이미지", "첨부");
	}

	private boolean hasMeetingIntent(String value) {
		return containsAny(value, "회의", "회의록", "통파일", "회의내용");
	}

	private boolean hasSendIntent(String value) {
		return containsAny(
			value,
			"보내",
			"전송",
			"전달",
			"공유",
			"첨부",
			"건네",
			"넘겨",
			"올려",
			"업로드",
			"send",
			"share",
			"upload"
		);
	}

	private boolean containsAny(String value, String... needles) {
		for (String needle : needles) {
			if (value.contains(needle)) {
				return true;
			}
		}
		return false;
	}

	private boolean containsAny(String value, Set<String> needles) {
		for (String needle : needles) {
			if (value.contains(needle)) {
				return true;
			}
		}
		return false;
	}

	private String extractSearchQuery(String prompt) {
		String value = normalize(prompt)
			.replace("찾아줘", " ")
			.replace("찾아", " ")
			.replace("검색", " ")
			.replace("파일", " ")
			.replace("폴더", " ")
			.replace("해줘", " ");
		for (String command : KOREAN_SEARCH_COMMAND_WORDS) {
			value = value.replace(command, " ");
		}
		return value.trim();
	}

	private String extractExplicitPath(String prompt) {
		String value = normalize(prompt);
		for (String quote : List.of("\"", "'", "`")) {
			int start = value.indexOf(quote);
			int end = value.indexOf(quote, start + 1);
			if (start >= 0 && end > start) {
				String candidate = value.substring(start + 1, end).trim();
				if (looksLikePath(candidate)) {
					return candidate;
				}
			}
		}
		int driveIndex = value.toLowerCase(Locale.ROOT).indexOf("f:");
		if (driveIndex >= 0) {
			String candidate = value.substring(driveIndex).split("\\s+")[0];
			if (looksLikePath(candidate)) {
				return candidate;
			}
		}
		return "";
	}

	private boolean looksLikePath(String value) {
		String normalized = value == null ? "" : value.trim();
		return normalized.contains("/") ||
			normalized.contains("\\") ||
			normalized.toLowerCase(Locale.ROOT).startsWith("f:") ||
			normalized.matches(".*\\.[A-Za-z0-9]{1,12}$");
	}

	private String extractFileContent(String prompt) {
		String value = normalize(prompt);
		for (String marker : List.of("내용:", "내용은", "content:", "본문:")) {
			int index = value.toLowerCase(Locale.ROOT).indexOf(marker.toLowerCase(Locale.ROOT));
			if (index >= 0) {
				return value.substring(index + marker.length()).trim();
			}
		}
		return "";
	}

	private String extractRecipient(String prompt) {
		String value = normalize(prompt);
		for (String marker : List.of("한테", "에게", "께")) {
			int index = value.indexOf(marker);
			if (index > 0) {
				String before = value.substring(0, index).trim();
				String[] parts = before.split("\\s+");
				return parts.length == 0 ? "" : parts[parts.length - 1];
			}
		}
		return "";
	}

	private String extractSendMessage(String prompt) {
		String value = normalize(prompt);
		int quoteStart = value.indexOf('"');
		int quoteEnd = value.lastIndexOf('"');
		if (quoteStart >= 0 && quoteEnd > quoteStart) {
			return value.substring(quoteStart + 1, quoteEnd).trim();
		}
		String marker = "라고";
		int index = value.indexOf(marker);
		if (index > 0) {
			String before = value.substring(0, index).trim();
			int targetEnd = -1;
			for (String targetMarker : List.of("한테", "에게", "께")) {
				int targetIndex = before.lastIndexOf(targetMarker);
				if (targetIndex >= 0) {
					targetEnd = Math.max(targetEnd, targetIndex + targetMarker.length());
				}
			}
			if (targetEnd >= 0 && targetEnd < before.length()) {
				return before.substring(targetEnd).trim();
			}
			return before;
		}
		return "";
	}

	private String stripSearchCommands(String value) {
		String normalized = normalize(value);
		for (String command : KOREAN_SEARCH_COMMAND_WORDS) {
			normalized = normalized.replace(command, " ");
		}
		for (String command : List.of(
			"find",
			"search",
			"show",
			"open",
			"list",
			"where",
			"please",
			"lookup",
			"look up"
		)) {
			normalized = normalized.replace(command, " ");
		}
		return normalized.replaceAll("\\s+", " ").strip();
	}

	private String normalize(String value) {
		if (value == null) {
			return "";
		}
		return Normalizer.normalize(value, Normalizer.Form.NFKC).strip().replaceAll("\\s+", " ");
	}

	private String normalizeSearchText(String value) {
		return normalize(value)
			.toLowerCase(Locale.ROOT)
			.replace('\\', '/')
			.replaceAll("[\\s_\\-+()\\[\\]{}.,:;]+", " ")
			.replaceAll("\\s+", " ")
			.strip();
	}

	private String compactSearchText(String value) {
		return normalizeSearchText(value).replaceAll("[^\\p{L}\\p{N}]+", "");
	}

	private List<String> fileTokens(String value) {
		String[] parts = normalize(value).toLowerCase(Locale.ROOT).split("[^\\p{L}\\p{N}_-]+");
		List<String> result = new ArrayList<>();
		for (String part : parts) {
			String token = stripFileKoreanParticle(part);
			if (token.length() < 2 || token.matches("\\d{1,2}")) {
				continue;
			}
			if (!FILE_SEARCH_STOPWORDS.contains(token) && !KOREAN_SEARCH_COMMAND_WORDS.contains(token)) {
				result.add(token);
			}
		}
		return result;
	}

	private String stripFileKoreanParticle(String value) {
		String token = value == null ? "" : value.strip().toLowerCase(Locale.ROOT);
		for (String suffix : List.of(
			"\uB4E4\uAE4C\uC9C0",
			"\uB4E4\uBD80\uD130",
			"\uB4E4\uC744",
			"\uB4E4\uC774",
			"\uB4E4\uC740",
			"\uB4E4\uB85C",
			"\uB4E4\uC5D0",
			"\uB4E4\uC758",
			"\uB4E4\uACFC",
			"\uB4E4"
		)) {
			if (token.length() > suffix.length() + 1 && token.endsWith(suffix)) {
				token = token.substring(0, token.length() - suffix.length());
				break;
			}
		}
		for (String suffix : List.of(
			"\uC785\uB2C8\uB2E4",
			"\uC778\uAC00\uC694",
			"\uAE4C\uC9C0",
			"\uBD80\uD130",
			"\uCC98\uB7FC",
			"\uC5D0\uC11C",
			"\uC73C\uB85C",
			"\uD55C\uD14C",
			"\uC5D0\uAC8C",
			"\uAE68\uC11C",
			"\uC774\uB791",
			"\uD558\uACE0",
			"\uC640",
			"\uACFC",
			"\uC758",
			"\uC740",
			"\uB294",
			"\uC774",
			"\uAC00",
			"\uC744",
			"\uB97C",
			"\uC5D0",
			"\uB85C",
			"\uB3C4",
			"\uB9CC",
			"\uAE68"
		)) {
			if (token.length() > suffix.length() + 1 && token.endsWith(suffix)) {
				return token.substring(0, token.length() - suffix.length());
			}
		}
		return token;
	}

	private List<String> tokens(String value) {
		return tokens(value, Set.of("파일", "찾아줘", "검색", "오늘", "어제", "오전", "오후"));
	}

	private List<String> tokens(String value, Set<String> stopwords) {
		String[] parts = value.toLowerCase(Locale.ROOT).split("[^\\p{IsAlphabetic}\\p{IsDigit}가-힣._-]+");
		List<String> tokens = new ArrayList<>();
		for (String part : parts) {
			String normalized = stripKoreanParticle(part);
			if (normalized.matches("\\d{1,2}시.*")) {
				continue;
			}
			if (
				normalized.length() >= 2 &&
				!stopwords.contains(normalized) &&
				!KOREAN_SEARCH_COMMAND_WORDS.contains(normalized)
			) {
				tokens.add(normalized);
			}
		}
		return tokens;
	}

	private String stripKoreanParticle(String value) {
		String token = value == null ? "" : value.strip().toLowerCase(Locale.ROOT);
		for (String suffix : List.of(
			"\uB4E4\uC744",
			"\uB4E4\uC774",
			"\uB4E4\uC740",
			"\uB4E4\uB85C",
			"\uB4E4\uC5D0",
			"\uB4E4"
		)) {
			if (token.length() > suffix.length() + 1 && token.endsWith(suffix)) {
				token = token.substring(0, token.length() - suffix.length());
				break;
			}
		}
		for (String suffix : List.of("입니다", "였지", "인가", "이야", "에게", "한테", "께서", "께", "님이", "님은", "님", "이가", "에서", "으로", "로", "에", "이", "가", "은", "는", "을", "를", "의")) {
			if (token.length() > suffix.length() + 1 && token.endsWith(suffix)) {
				return token.substring(0, token.length() - suffix.length());
			}
		}
		return token;
	}

	private QueryHints queryHints(String normalized) {
		LocalDate today = LocalDate.now(WORKSPACE_TIME_ZONE);
		LocalDate date = null;
		if (normalized.contains("오늘")) {
			date = today;
		} else if (normalized.contains("어제")) {
			date = today.minusDays(1);
		}
		Integer hour = null;
		Matcher matcher = HOUR_PATTERN.matcher(normalized);
		if (matcher.find()) {
			String period = matcher.group(1);
			int parsedHour = Integer.parseInt(matcher.group(2));
			if ("오후".equals(period) && parsedHour < 12) {
				parsedHour += 12;
			} else if ("오전".equals(period) && parsedHour == 12) {
				parsedHour = 0;
			}
			if (parsedHour >= 0 && parsedHour <= 23) {
				hour = parsedHour;
			}
		}
		return new QueryHints(date, hour, normalized.contains("쯤") ? 2 : 1);
	}

	private boolean matchesTimeHints(Instant instant, QueryHints hints) {
		if (instant == null || hints == null || (!hints.hasDate() && !hints.hasHour())) {
			return true;
		}
		LocalDateTime local = LocalDateTime.ofInstant(instant, WORKSPACE_TIME_ZONE);
		if (hints.hasDate() && !local.toLocalDate().equals(hints.date())) {
			return false;
		}
		if (hints.hasHour()) {
			int distance = Math.abs(local.getHour() - hints.hour());
			return distance <= hints.hourTolerance();
		}
		return true;
	}

	private boolean isImage(String contentType, String fileName) {
		String type = contentType == null ? "" : contentType.toLowerCase(Locale.ROOT);
		String name = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);
		return type.startsWith("image/") || name.matches(".*\\.(png|jpe?g|gif|bmp|webp|heic|heif)$");
	}

	private String promptContext(List<AvaAiWorkspaceItemResponse> items, String status) {
		StringBuilder builder = new StringBuilder();
		if (!status.isBlank()) {
			builder.append("작업 상태: ").append(status).append('\n');
		}
		if (items.isEmpty()) {
			return builder.toString();
		}
		builder.append("작업공간 결과:\n");
		for (int index = 0; index < Math.min(items.size(), 20); index++) {
			AvaAiWorkspaceItemResponse item = items.get(index);
			builder.append("- [").append(item.type()).append("] ")
				.append(item.title());
			if (item.path() != null && !item.path().isBlank()) {
				builder.append(" / path=").append(item.path());
			}
			if (item.url() != null && !item.url().isBlank()) {
				builder.append(" / url=").append(item.url());
			}
			if (item.content() != null && !item.content().isBlank()) {
				builder.append(" / content=").append(limit(item.content(), 240));
			}
			builder.append('\n');
		}
		return builder.toString();
	}

	private List<AvaAiWorkspaceItemResponse> limitItems(List<AvaAiWorkspaceItemResponse> items, int max) {
		if (items.size() <= max) {
			return items;
		}
		return new ArrayList<>(items.subList(0, max));
	}

	private String limit(String value, int max) {
		if (value == null || value.length() <= max) {
			return value == null ? "" : value;
		}
		return value.substring(0, Math.max(0, max - 1)) + "…";
	}

	public record WorkspaceActionResult(
		List<AvaAiWorkspaceItemResponse> items,
		String status,
		String promptContext,
		boolean handled
	) {
	}

	public record SendResult(String status, List<AvaAiWorkspaceItemResponse> items) {
	}

	public record WorkspaceDownload(Resource resource, String fileName, String contentType, long size) {
	}

	private record FileSearchQuery(
		String phrase,
		List<String> tokens,
		List<List<String>> variants,
		Set<String> preferredExtensions,
		boolean sourceCodeIntent,
		boolean arduinoIntent
	) {
	}

	private record ScoredPath(Path path, int score) {
	}

	private record QueryHints(LocalDate date, Integer hour, int hourTolerance) {
		boolean hasDate() {
			return date != null;
		}

		boolean hasHour() {
			return hour != null;
		}
	}
}
