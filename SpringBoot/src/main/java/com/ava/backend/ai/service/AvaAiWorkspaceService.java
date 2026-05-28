package com.ava.backend.ai.service;

import java.io.IOException;
import java.io.InputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
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
import org.springframework.data.domain.PageRequest;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.ai.dto.AvaAiWorkspaceFileRequest;
import com.ava.backend.ai.dto.AvaAiWorkspaceItemResponse;
import com.ava.backend.ai.dto.AvaAiWorkspaceSendRequest;
import com.ava.backend.ai.service.AvaAiWebSearchService.WebSearchResult;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.azoom.entity.AzoomMeetingTranscriptKind;
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
import com.ava.backend.chat.entity.ChatMentionNotificationEntity;
import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.repository.ChatMentionNotificationRepository;
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
	private static final Set<String> ARCHIVE_FILE_EXTENSIONS = Set.of(
		"zip",
		"7z",
		"rar",
		"tar",
		"gz",
		"tgz",
		"bz2",
		"xz",
		"iso"
	);
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
	private static final Set<String> STRONG_SOURCE_CODE_INTENT_TOKENS = Set.of(
		"\uC18C\uC2A4",
		"\uC18C\uC2A4\uCF54\uB4DC",
		"\uCF54\uB4DC",
		"\uC2A4\uCF00\uCE58",
		"\uC544\uB450\uC774\uB178",
		"\uC774\uB178",
		"source",
		"code",
		"src",
		"sketch",
		"arduino",
		"ino"
	);
	private static final Set<String> FIRMWARE_INTENT_TOKENS = Set.of(
		"\uD38C\uC6E8\uC5B4",
		"firmware",
		"firm",
		"fw"
	);
	private static final String FIRMWARE_REPOSITORY_DIRECTORY = "\uC81C\uD488 \uC790\uB8CC"; // 제품 자료
	private static final String FIRMWARE_DEVELOPER_REPOSITORY_DIRECTORY =
		"\uAC1C\uBC1C\uC790\uB8CC/\uADF9\uCD08\uB2E8\uD30C \uC6D0\uBCF8"; // 개발자료/극초단파 원본
	private static final Set<String> FIRMWARE_SEARCH_TRIGGERS = Set.of(
		"\uD38C\uC6E8\uC5B4",
		"\uB514\uC2A4\uD50C\uB808\uC774",
		"\uB4DC\uC708",
		"\uD30C\uC77C",
		"\uC790\uB8CC",
		"\uCC3E\uC544",
		"\uCC3E\uC544\uC918",
		"\uC62C\uB824",
		"\uC5C5\uB85C\uB4DC",
		"\uBCF4\uB0B4",
		"\uC804\uC1A1",
		"\uC804\uB2EC",
		"\uBAA9\uB85D",
		"firmware",
		"firm",
		"fw",
		"display",
		"lcd",
		"dwin",
		"file",
		"files",
		"material",
		"find",
		"search",
		"upload",
		"send",
		"list",
		"zip"
	);
	private static final Set<String> FIRMWARE_LIST_TRIGGERS = Set.of(
		"\uBAA9\uB85D",
		"\uB9AC\uC2A4\uD2B8",
		"\uC804\uBD80",
		"\uBAA8\uB450",
		"\uC804\uCCB4",
		"list",
		"all"
	);
	private static final Set<String> FIRMWARE_DEVELOPER_SOURCE_HINTS = Set.of(
		"\uC6D0\uBCF8",
		"\uAC1C\uBC1C\uC790",
		"\uAC1C\uBC1C\uC790\uB8CC",
		"\uAC1C\uBC1C \uC6D0\uBCF8",
		"developer",
		"engineering",
		"original"
	);
	private static final Set<String> FIRMWARE_PRODUCTION_SOURCE_HINTS = Set.of(
		"\uC591\uC0B0",
		"\uC81C\uD488 \uC790\uB8CC",
		"\uC81C\uD488\uC790\uB8CC",
		"\uC81C\uD488\uC6A9",
		"production",
		"release"
	);
	private static final List<FirmwareProduct> FIRMWARE_PRODUCTS = List.of(
		new FirmwareProduct(
			"\uC62C\uB9AC\uC628 (ALLION)",
			"ALLION_GMP_Firm.zip",
			"allion",
			List.of("\uC62C\uB9AC\uC628", "\uC54C\uB9AC\uC628", "allion")
		),
		new FirmwareProduct(
			"\uBE44\uB9AC\uBCF8 (Bereborn)",
			"Bereborn [Tron].zip",
			"bereborn",
			List.of("\uBE44\uB9AC\uBCF8", "bereborn", "bereborn v0", "\uAE30\uBCF8 \uBE44\uB9AC\uBCF8")
		),
		new FirmwareProduct(
			"\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4 \uBC84\uC8041 (Bereborn Plus v1)",
			"Bereborn Plus \uBC84\uC8041 [Tron].zip",
			"bereborn-plus",
			List.of("\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4", "\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4 v1", "\uBE44\uB9AC\uBCF8\uD50C\uB7EC\uC2A4 \uBC84\uC8041", "bereborn plus", "bereborn+", "bereborn+ v1", "bereborn plus ver1", "bereborn plus v1", "bereborn plus version1")
		),
		new FirmwareProduct(
			"\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4 \uBC84\uC8042 (Bereborn Plus v2)",
			"Bereborn Plus \uBC84\uC8042 [Tron].zip",
			"bereborn-plus",
			List.of("\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4", "\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4 v2", "\uBE44\uB9AC\uBCF8\uD50C\uB7EC\uC2A4 \uBC84\uC8042", "bereborn plus", "bereborn+", "bereborn+ v2", "bereborn plus ver2", "bereborn plus v2", "bereborn plus version2")
		),
		new FirmwareProduct(
			"\uC5D1\uC3D8\uC6E8\uC774\uBE0C (EXO-Wave)",
			"EXO-Wave [Tron].zip",
			"exo-wave",
			List.of("\uC5D1\uC3D8\uC6E8\uC774\uBE0C", "\uC5D1\uC18C\uC6E8\uC774\uBE0C", "\uC561\uC18C\uC6E8\uC774\uBE0C", "\uC561\uC3D8\uC6E8\uC774\uBE0C", "exo wave", "exo-wave", "exowave")
		),
		new FirmwareProduct(
			"\uB9E5\uC2A4\uC6E8\uC774\uBE0C (Max-Wave)",
			"Max-Wave [Tron].zip",
			"max-wave",
			List.of("\uB9E5\uC2A4\uC6E8\uC774\uBE0C", "\uB9E5\uC4F0\uC6E8\uC774\uBE0C", "\uBA55\uC2A4\uC6E8\uC774\uBE0C", "\uBA55\uC4F0\uC6E8\uC774\uBE0C", "max wave", "max-wave", "maxwave")
		),
		new FirmwareProduct(
			"\uB9AC\uBC14\uC774\uBE0C (Revive)",
			"Revive  [TRON].zip",
			"revive",
			List.of("\uB9AC\uBC14\uC774\uBE0C", "revive")
		),
		new FirmwareProduct(
			"\uB274 \uB9AC\uBC14\uC774\uBE0C 200W (New-Revive 200)",
			"New-Revive200[Tron].zip",
			"new-revive",
			List.of("\uB274\uB9AC\uBC14\uC774\uBE0C", "\uB274 \uB9AC\uBC14\uC774\uBE0C", "\uB274\uB9AC\uBC14\uC774\uBE0C 200w", "\uB274 \uB9AC\uBC14\uC774\uBE0C 200w", "\uB274\uB9AC\uBC14\uC774\uBE0C 200\uC640\uD2B8", "new revive", "new revive 200w", "new revive v1", "new-revive 200", "newrevive200")
		),
		new FirmwareProduct(
			"\uB274 \uB9AC\uBC14\uC774\uBE0C 250W (New-Revive 250)",
			"New-Revive250 [Tron].zip",
			"new-revive",
			List.of("\uB274\uB9AC\uBC14\uC774\uBE0C", "\uB274 \uB9AC\uBC14\uC774\uBE0C", "\uB274\uB9AC\uBC14\uC774\uBE0C 250w", "\uB274 \uB9AC\uBC14\uC774\uBE0C 250w", "\uB274\uB9AC\uBC14\uC774\uBE0C 250\uC640\uD2B8", "new revive", "new revive 250w", "new revive v2", "new-revive 250", "newrevive250")
		),
		new FirmwareProduct(
			"\uB9AC\uC96C\uC6E8\uC774\uBE0C (RejuWave)",
			"RejuWave [TRON].zip",
			"rejuwave",
			List.of("\uB9AC\uC96C\uC6E8\uC774\uBE0C", "\uB9AC\uC8FC\uC6E8\uC774\uBE0C", "rejuwave", "reju wave")
		),
		new FirmwareProduct(
			"\uC26C\uBC14 (SHIVA)",
			"SHIVA [TRON].zip",
			"shiva",
			List.of("\uC26C\uBC14", "\uC2DC\uBC14", "\uC2C0\uBC14", "shiva", "siva")
		),
		new FirmwareProduct(
			"\uC2AC\uB9BC\uB3C5 \uBC84\uC8041 (SLIM DOC v1)",
			"SLIM DOC \uBC84\uC8041 [TRON].zip",
			"slim-doc",
			List.of("\uC2AC\uB9BC\uB3C5", "\uC2AC\uB9BC\uB3C5 v1", "\uC2AC\uB9BC\uB3C5 \uBC84\uC8041", "\uC2AC\uB9BC\uB3C5 \uBE44\uB9AC\uBCF8", "slim doc", "slim doc v1", "slim doc ver1", "slim doc bereborn")
		),
		new FirmwareProduct(
			"\uC2AC\uB9BC\uB3C5 \uBC84\uC8042 (SLIM DOC v2)",
			"SLIM DOC \uBC84\uC8042 [TRON].zip",
			"slim-doc",
			List.of("\uC2AC\uB9BC\uB3C5", "\uC2AC\uB9BC\uB3C5 v2", "\uC2AC\uB9BC\uB3C5 \uBC84\uC8042", "\uC2AC\uB9BC\uB3C5 \uB9E5\uC2A4\uC6E8\uC774\uBE0C", "slim doc", "slim doc v2", "slim doc ver2", "slim doc max wave")
		),
		new FirmwareProduct(
			"\uC368\uB9C8\uC6E8\uC774\uBE0C (ThermaWave)",
			"ThermaWave [TRON].zip",
			"thermawave",
			List.of("\uC368\uB9C8\uC6E8\uC774\uBE0C", "\uC368\uB9C8\uB9E4\uB4DC", "therma wave", "thermawave")
		),
		new FirmwareProduct(
			"\uC6E8\uC774\uBE0C\uC628 (Wave On)",
			"Wave On [TRON].zip",
			"wave-on",
			List.of("\uC6E8\uC774\uBE0C\uC628", "\uC6E8\uC774\uBCF8", "wave on", "waveon")
		)
	);
	private static final Set<String> ARCHIVE_INTENT_TOKENS = Set.of(
		"\uC555\uCD95",
		"\uC555\uCD95\uD30C\uC77C",
		"\uC9D1\uD30C\uC77C",
		"\uC6D0\uBCF8",
		"\uBC31\uC5C5",
		"archive",
		"compressed",
		"zip"
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
		"\uAD00\uB828\uD30C\uC77C",
		"\uAD00\uB828\uC790\uB8CC",
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
	private final ChatMentionNotificationRepository mentionNotificationRepository;
	private final AzoomService azoomService;
	private final AzoomMeetingTranscriptRepository transcriptRepository;
	private final AzoomMeetingUtteranceRepository utteranceRepository;
	private final SimpMessagingTemplate messagingTemplate;

	public AvaAiWorkspaceService(
		ChatService chatService,
		ChatMessageJpaRepository chatMessageRepository,
		ChatMentionNotificationRepository mentionNotificationRepository,
		AzoomService azoomService,
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
		this.mentionNotificationRepository = mentionNotificationRepository;
		this.azoomService = azoomService;
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
		String explicitPath = extractExplicitPath(prompt);
		if (!explicitPath.isBlank() && !hasFileMutationIntent(normalized)) {
			WorkspaceActionResult pathResult = inspectExplicitWorkspacePath(explicitPath, principal);
			if (pathResult != null) {
				return pathResult;
			}
		}
		WorkspaceActionResult firmwareResult = inspectFirmwarePrompt(prompt, normalized, principal);
		if (firmwareResult != null) {
			return firmwareResult;
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
		}
		if (hasMentionIntent(normalized)) {
			items.addAll(searchMentionNotifications(prompt, principal));
		}
		if (hasMeetingIntent(normalized)) {
			items.addAll(searchMeetings(prompt, principal));
		}
		return new WorkspaceActionResult(List.copyOf(limitItems(items, 120)), status, promptContext(items, status), false);
	}

	private WorkspaceActionResult inspectFirmwarePrompt(String prompt, String normalized, AuthPrincipal principal) {
		List<FirmwareFile> firmwareFiles = discoveredFirmwareFiles();
		FirmwareRequest request = firmwareRequest(prompt, normalized, firmwareFiles);
		if (!request.triggered()) {
			return null;
		}
		if (firmwareFiles.isEmpty()) {
			String status = "⚠️ 펌웨어 저장소에서 ZIP 파일을 찾지 못했습니다.\n"
				+ "확인 경로: " + firmwareRepositoryPath().toAbsolutePath().normalize() + "\n"
				+ "확인 경로: " + firmwareDeveloperRepositoryPath().toAbsolutePath().normalize();
			return new WorkspaceActionResult(List.of(), status, status, true);
		}
		if (request.listRequested()) {
			return firmwareCatalogResult("사용 가능한 펌웨어/디스플레이 파일 목록입니다.", firmwareFiles);
		}
		List<FirmwareFile> clarificationOptions = firmwareClarificationOptions(prompt, firmwareFiles);
		if (!clarificationOptions.isEmpty()) {
			return firmwareClarificationResult(clarificationOptions);
		}
		List<FirmwareMatch> matches = firmwareMatches(prompt, firmwareFiles);
		if (matches.isEmpty() || matches.get(0).score() < 60) {
			return firmwareNotFoundResult(prompt, matches, firmwareFiles);
		}
		FirmwareRepositoryKind requestedSource = requestedFirmwareSource(normalized);
		if (requestedSource != null) {
			List<FirmwareMatch> sourceMatches = matches.stream()
				.filter(match -> match.file().repositoryKind() == requestedSource)
				.toList();
			if (!sourceMatches.isEmpty()) {
				matches = sourceMatches;
			}
		}
		List<FirmwareMatch> topMatches = topFirmwareMatches(matches);
		List<FirmwareFile> dynamicVersionOptions = firmwareDynamicVersionOptions(normalized, topMatches);
		if (!dynamicVersionOptions.isEmpty()) {
			return firmwareClarificationResult(dynamicVersionOptions);
		}
		if (requestedSource == null && hasMultipleFirmwareRepositories(topMatches)) {
			return firmwareSourceClarificationResult(topMatches);
		}
		FirmwareMatch match = matches.get(0);
		FirmwareFile firmwareFile = match.file();
		Path source = firmwareFile.path();
		if (!Files.isRegularFile(source, LinkOption.NOFOLLOW_LINKS)) {
			String status = "⚠️ " + firmwareFile.fileName() + " 파일을 " + source.getParent()
				+ "에서 찾지 못했습니다. 저장소 파일명을 확인해 주세요.";
			return new WorkspaceActionResult(List.of(), status, status, true);
		}
		if (request.chatDeliveryRequested()) {
			return deliverFirmwareToChat(prompt, principal, firmwareFile, match.score());
		}
		Path uploaded = copyFirmwareToWorkspace(source);
		AvaAiWorkspaceItemResponse item = fileItem(uploaded, firmwareFile.displayName() + " 펌웨어/디스플레이 파일입니다.");
		String status = firmwareFoundStatus(firmwareFile, firmwareFile.fileName() + " 작업공간에 업로드 완료했습니다.");
		if (match.score() < 85) {
			status = firmwareFile.displayName() + " 파일로 이해했습니다. 맞지 않으면 제품명을 다시 알려주세요.\n\n" + status;
		}
		return new WorkspaceActionResult(List.of(item), status, promptContext(List.of(item), status), true);
	}

	private FirmwareRequest firmwareRequest(String prompt, String normalized, List<FirmwareFile> firmwareFiles) {
		if (hasFileMutationIntent(normalized)) {
			return new FirmwareRequest(false, false, false);
		}
		String compact = compactSearchText(prompt);
		boolean hasFirmwareSignal = containsAny(normalized, FIRMWARE_INTENT_TOKENS) ||
			containsAny(normalized, "디스플레이", "드윈", "display", "lcd", "dwin");
		boolean hasProductSignal = hasFirmwareProductSignal(prompt, firmwareFiles);
		boolean hasSearchTrigger = containsAny(normalized, FIRMWARE_SEARCH_TRIGGERS) ||
			containsAny(compact, "firmware", "display", "lcd", "dwin");
		boolean bareFirmwareUpload = !hasProductSignal &&
			containsAny(normalized, "파일 올려", "파일 업로드", "자료 올려", "file upload");
		boolean triggered = (hasProductSignal && hasSearchTrigger) ||
			hasFirmwareSignal ||
			(bareFirmwareUpload && hasSearchTrigger);
		boolean listRequested = triggered && containsAny(normalized, FIRMWARE_LIST_TRIGGERS);
		boolean chatDelivery = triggered && hasFirmwareChatDeliveryIntent(normalized);
		return new FirmwareRequest(triggered, listRequested, chatDelivery);
	}

	private boolean hasFirmwareProductSignal(String prompt, List<FirmwareFile> firmwareFiles) {
		if (!firmwareClarificationOptions(prompt, firmwareFiles).isEmpty()) {
			return true;
		}
		return firmwareMatches(prompt, firmwareFiles).stream().anyMatch(match -> match.score() >= 60);
	}

	private boolean hasFirmwareChatDeliveryIntent(String normalized) {
		return containsAny(normalized, "한테", "에게", "께") &&
			containsAny(normalized, "보내", "전송", "전달", "공유", "올려", "send", "share");
	}

	private List<FirmwareFile> firmwareClarificationOptions(String prompt, List<FirmwareFile> firmwareFiles) {
		String normalized = normalize(prompt).toLowerCase(Locale.ROOT);
		String compact = compactSearchText(prompt);
		FirmwareRepositoryKind requestedSource = requestedFirmwareSource(normalized);
		if ((compact.contains("비리본플러스") || compact.contains("berebornplus") ||
			(compact.contains("bereborn") && normalized.contains("+"))) &&
			!hasFirmwareVariantHint(normalized, compact)) {
			return firmwareFilesByFamily("bereborn-plus", firmwareFiles, requestedSource);
		}
		if ((compact.contains("슬림독") || compact.contains("slimdoc")) &&
			!hasFirmwareVariantHint(normalized, compact) &&
			!compact.contains("비리본") &&
			!compact.contains("bereborn") &&
			!compact.contains("맥스웨이브") &&
			!compact.contains("maxwave")) {
			return firmwareFilesByFamily("slim-doc", firmwareFiles, requestedSource);
		}
		if ((compact.contains("뉴리바이브") || compact.contains("newrevive")) &&
			!compact.contains("200") &&
			!compact.contains("250") &&
			!hasFirmwareVariantHint(normalized, compact)) {
			return firmwareFilesByFamily("new-revive", firmwareFiles, requestedSource);
		}
		return List.of();
	}

	private boolean hasFirmwareVariantHint(String normalized, String compact) {
		return containsAny(normalized, "v1", "v2", "v3", "ver1", "ver2", "ver3", "version1", "version2", "version3",
			"버전1", "버전2", "버전3", "버젼1", "버젼2", "버젼3", "1번", "2번", "3번", "200", "250", "high11", "maxwave") ||
			compact.matches(".*v\\d+.*") ||
			compact.matches(".*ver\\d+.*");
	}

	private List<FirmwareFile> firmwareFilesByFamily(
		String family,
		List<FirmwareFile> firmwareFiles,
		FirmwareRepositoryKind requestedSource
	) {
		return firmwareFiles.stream()
			.filter(file -> file.family().equals(family))
			.filter(file -> requestedSource == null || file.repositoryKind() == requestedSource)
			.sorted(Comparator
				.comparing(FirmwareFile::repositoryKind)
				.thenComparing(FirmwareFile::fileName))
			.toList();
	}

	private List<FirmwareMatch> firmwareMatches(String prompt, List<FirmwareFile> firmwareFiles) {
		String compactPrompt = compactSearchText(prompt);
		List<String> terms = searchTerms(prompt);
		return firmwareFiles.stream()
			.map(file -> new FirmwareMatch(file, firmwareMatchScore(file, compactPrompt, terms)))
			.filter(match -> match.score() > 0)
			.sorted(Comparator
				.comparingInt(FirmwareMatch::score).reversed()
				.thenComparing(match -> match.file().repositoryKind())
				.thenComparing(match -> match.file().fileName()))
			.toList();
	}

	private int firmwareMatchScore(FirmwareFile firmwareFile, String compactPrompt, List<String> terms) {
		int best = 0;
		for (String name : firmwareFile.aliases()) {
			String compactName = compactSearchText(name);
			if (compactName.isBlank()) {
				continue;
			}
			if (compactPrompt.contains(compactName)) {
				best = Math.max(best, 95 + Math.min(25, compactName.length()));
				continue;
			}
			String compactWithoutExtension = compactName.replaceAll("(zip|tron|hic|trongmpfirm|firm|original|원본)$", "");
			if (!compactWithoutExtension.equals(compactName) && compactPrompt.contains(compactWithoutExtension)) {
				best = Math.max(best, 90 + Math.min(20, compactWithoutExtension.length()));
				continue;
			}
			int fuzzy = fuzzyVariantScore(compactName, terms);
			if (fuzzy >= 10) {
				best = Math.max(best, 55 + fuzzy);
			}
		}
		return best;
	}

	private List<FirmwareMatch> topFirmwareMatches(List<FirmwareMatch> matches) {
		if (matches.isEmpty()) {
			return List.of();
		}
		int topScore = matches.get(0).score();
		return matches.stream()
			.filter(match -> match.score() >= 60 && topScore - match.score() <= 8)
			.toList();
	}

	private List<FirmwareFile> firmwareDynamicVersionOptions(String normalized, List<FirmwareMatch> topMatches) {
		String compact = compactSearchText(normalized);
		if (topMatches.isEmpty() || hasFirmwareVariantHint(normalized, compact)) {
			return List.of();
		}
		String family = topMatches.get(0).file().family();
		List<FirmwareFile> options = topMatches.stream()
			.map(FirmwareMatch::file)
			.filter(file -> file.family().equals(family))
			.filter(file -> !file.versionLabel().isBlank())
			.distinct()
			.sorted(Comparator
				.comparing(FirmwareFile::repositoryKind)
				.thenComparing(FirmwareFile::versionLabel)
				.thenComparing(FirmwareFile::fileName))
			.toList();
		long versions = options.stream()
			.map(FirmwareFile::versionLabel)
			.distinct()
			.count();
		return versions > 1 ? options : List.of();
	}

	private boolean hasMultipleFirmwareRepositories(List<FirmwareMatch> matches) {
		return matches.stream().map(match -> match.file().repositoryKind()).distinct().count() > 1;
	}

	private FirmwareRepositoryKind requestedFirmwareSource(String normalized) {
		if (containsAny(normalized, FIRMWARE_DEVELOPER_SOURCE_HINTS)) {
			return FirmwareRepositoryKind.DEVELOPER;
		}
		if (containsAny(normalized, FIRMWARE_PRODUCTION_SOURCE_HINTS)) {
			return FirmwareRepositoryKind.PRODUCTION;
		}
		return null;
	}

	private WorkspaceActionResult firmwareCatalogResult(String heading, List<FirmwareFile> firmwareFiles) {
		List<AvaAiWorkspaceItemResponse> items = existingFirmwareItems(firmwareFiles, "사용 가능한 제품 자료 파일입니다.");
		String status = heading + "\n\n" + firmwareCatalogText(firmwareFiles);
		return new WorkspaceActionResult(items, status, promptContext(items, status), true);
	}

	private WorkspaceActionResult firmwareClarificationResult(List<FirmwareFile> options) {
		List<AvaAiWorkspaceItemResponse> items = existingFirmwareItems(options, "버전 확인이 필요한 제품 자료 파일입니다.");
		String productName = firmwareClarificationName(options);
		StringBuilder status = new StringBuilder("📂 ").append(productName).append(" 파일이 여러 버전이 있습니다:\n\n");
		for (FirmwareFile option : options) {
			status.append("• ").append(firmwareOptionLabel(option)).append(": ")
				.append(option.path().toAbsolutePath().normalize());
			if (option.repositoryKind() == FirmwareRepositoryKind.DEVELOPER) {
				status.append(" (개발자 원본 파일 ⚠️)");
			}
			status.append('\n');
		}
		status.append("\n어떤 버전이 필요하신가요?");
		return new WorkspaceActionResult(items, status.toString(), promptContext(items, status.toString()), true);
	}

	private WorkspaceActionResult firmwareSourceClarificationResult(List<FirmwareMatch> matches) {
		List<FirmwareFile> options = matches.stream()
			.map(FirmwareMatch::file)
			.distinct()
			.sorted(Comparator
				.comparing(FirmwareFile::repositoryKind)
				.thenComparing(FirmwareFile::fileName))
			.toList();
		List<AvaAiWorkspaceItemResponse> items = existingFirmwareItems(options, "양산/개발자 원본 중 선택이 필요한 제품 자료 파일입니다.");
		StringBuilder status = new StringBuilder("해당 제품의 파일이 두 가지 있습니다:\n");
		for (FirmwareFile option : options) {
			status.append("• ")
				.append(option.repositoryKind() == FirmwareRepositoryKind.PRODUCTION ? "양산 파일" : "개발자 원본")
				.append(": ")
				.append(option.path().toAbsolutePath().normalize());
			if (option.repositoryKind() == FirmwareRepositoryKind.DEVELOPER) {
				status.append(" (개발자 원본 파일 ⚠️)");
			}
			status.append('\n');
		}
		status.append("어떤 파일이 필요하신가요?");
		return new WorkspaceActionResult(items, status.toString(), promptContext(items, status.toString()), true);
	}

	private WorkspaceActionResult firmwareNotFoundResult(
		String prompt,
		List<FirmwareMatch> matches,
		List<FirmwareFile> firmwareFiles
	) {
		List<FirmwareFile> suggestions = matches.stream()
			.filter(match -> match.score() >= 35)
			.limit(2)
			.map(FirmwareMatch::file)
			.toList();
		List<AvaAiWorkspaceItemResponse> items = existingFirmwareItems(suggestions, "가장 유사한 제품 자료 파일입니다.");
		String input = stripSearchCommands(prompt);
		if (input.isBlank()) {
			input = prompt;
		}
		StringBuilder status = new StringBuilder("⚠️ '")
			.append(limit(input, 80))
			.append("'에 해당하는 파일을 찾지 못했습니다.");
		if (!suggestions.isEmpty()) {
			status.append("\n\n혹시 이 제품을 찾으시나요?");
			for (FirmwareFile suggestion : suggestions) {
				status.append("\n• ").append(suggestion.displayName()).append(" - ")
					.append(suggestion.path().toAbsolutePath().normalize());
			}
			status.append("\n\n제품명을 다시 확인해 주세요.");
		} else {
			status.append("\n\n").append(firmwareCatalogText(firmwareFiles));
		}
		return new WorkspaceActionResult(items, status.toString(), promptContext(items, status.toString()), true);
	}

	private WorkspaceActionResult deliverFirmwareToChat(
		String prompt,
		AuthPrincipal principal,
		FirmwareFile firmwareFile,
		int score
	) {
		String recipient = extractRecipient(prompt);
		AvaAiWorkspaceItemResponse preview = fileItem(firmwareFile.path(), firmwareFile.displayName() + " 펌웨어/디스플레이 파일입니다.");
		if (recipient.isBlank()) {
			String status = "수신자를 확인해야 합니다. 예: \"장유종한테 " + firmwareFile.displayName() + " 파일 보내줘\"";
			return new WorkspaceActionResult(List.of(preview), status, promptContext(List.of(preview), status), true);
		}
		if (chatService == null || messagingTemplate == null || principal == null) {
			String status = firmwareFile.displayName() + " 파일은 찾았지만 현재 채팅 전송 환경이 준비되지 않았습니다.";
			return new WorkspaceActionResult(List.of(preview), status, promptContext(List.of(preview), status), true);
		}
		SendResult result = sendToChat(new AvaAiWorkspaceSendRequest(
			null,
			recipient,
			"",
			List.of(relativePath(firmwareFile.path()))
		), principal);
		String status = firmwareFoundStatus(firmwareFile, firmwareFile.fileName() + "을 " + recipient + "에게 채팅으로 전송했습니다.");
		if (score < 85) {
			status = firmwareFile.displayName() + " 파일로 이해하고 전송했습니다. 맞지 않으면 제품명을 다시 알려주세요.\n\n" + status;
		}
		return new WorkspaceActionResult(result.items(), status, promptContext(result.items(), status), true);
	}

	private List<AvaAiWorkspaceItemResponse> existingFirmwareItems(List<FirmwareFile> firmwareFiles, String content) {
		return firmwareFiles.stream()
			.filter(file -> Files.exists(file.path(), LinkOption.NOFOLLOW_LINKS))
			.map(file -> fileItem(file.path(), content))
			.toList();
	}

	private List<FirmwareFile> discoveredFirmwareFiles() {
		List<FirmwareFile> files = new ArrayList<>();
		discoverFirmwareFiles(firmwareRepositoryPath(), FirmwareRepositoryKind.PRODUCTION, files);
		discoverFirmwareFiles(firmwareDeveloperRepositoryPath(), FirmwareRepositoryKind.DEVELOPER, files);
		return List.copyOf(files);
	}

	private void discoverFirmwareFiles(Path directory, FirmwareRepositoryKind repositoryKind, List<FirmwareFile> files) {
		if (!Files.isDirectory(directory, LinkOption.NOFOLLOW_LINKS)) {
			return;
		}
		try (Stream<Path> stream = Files.list(directory)) {
			stream
				.filter(path -> Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS))
				.filter(path -> path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".zip"))
				.sorted(Comparator.comparing(path -> path.getFileName().toString().toLowerCase(Locale.ROOT)))
				.map(path -> firmwareFileFromPath(path, repositoryKind))
				.forEach(files::add);
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to scan firmware repository: " + directory, exception);
		}
	}

	private FirmwareFile firmwareFileFromPath(Path path, FirmwareRepositoryKind repositoryKind) {
		String fileName = path.getFileName().toString();
		InferredFirmwareName inferred = inferFirmwareName(fileName);
		List<FirmwareProduct> candidates = knownFirmwareCandidates(fileName, inferred);
		FirmwareProduct known = selectKnownFirmwareProduct(fileName, inferred, candidates);
		String displayName = known == null ? inferred.displayName() : known.displayName();
		String family = known == null
			? (candidates.isEmpty() ? inferred.family() : candidates.get(0).family())
			: known.family();
		LinkedHashSet<String> aliases = new LinkedHashSet<>();
		aliases.add(displayName);
		aliases.add(fileName);
		aliases.addAll(inferred.aliases());
		for (FirmwareProduct candidate : candidates) {
			aliases.add(candidate.displayName());
			aliases.add(candidate.fileName());
			aliases.addAll(candidate.aliases());
		}
		return new FirmwareFile(
			displayName,
			fileName,
			family,
			List.copyOf(aliases),
			path,
			repositoryKind,
			inferred.versionLabel()
		);
	}

	private List<FirmwareProduct> knownFirmwareCandidates(String fileName, InferredFirmwareName inferred) {
		String compactFileName = compactSearchText(fileName);
		String compactBase = compactSearchText(inferred.displayName());
		return FIRMWARE_PRODUCTS.stream()
			.filter(product -> {
				if (compactSearchText(product.fileName()).equals(compactFileName)) {
					return true;
				}
				for (String alias : knownFirmwareAliases(product)) {
					String compactAlias = compactSearchText(alias);
					if (compactAlias.isBlank()) {
						continue;
					}
					if (compactBase.equals(compactAlias)) {
						return true;
					}
					if (compactBase.length() >= 10 && compactAlias.contains(compactBase)) {
						return true;
					}
					if (compactAlias.length() >= 10 && compactBase.contains(compactAlias)) {
						return true;
					}
				}
				return false;
			})
			.toList();
	}

	private List<String> knownFirmwareAliases(FirmwareProduct product) {
		List<String> aliases = new ArrayList<>();
		aliases.add(product.displayName());
		aliases.add(product.fileName());
		aliases.addAll(product.aliases());
		return aliases;
	}

	private FirmwareProduct selectKnownFirmwareProduct(
		String fileName,
		InferredFirmwareName inferred,
		List<FirmwareProduct> candidates
	) {
		for (FirmwareProduct product : candidates) {
			if (product.fileName().equalsIgnoreCase(fileName)) {
				return product;
			}
		}
		if (!inferred.versionLabel().isBlank()) {
			List<FirmwareProduct> versionMatches = candidates.stream()
				.filter(product -> firmwareProductMatchesVersion(product, inferred.versionLabel()))
				.toList();
			if (versionMatches.size() == 1) {
				return versionMatches.get(0);
			}
		}
		return candidates.size() == 1 ? candidates.get(0) : null;
	}

	private boolean firmwareProductMatchesVersion(FirmwareProduct product, String versionLabel) {
		String compact = compactSearchText(product.displayName() + " " + product.fileName() + " " + String.join(" ", product.aliases()));
		String version = compactSearchText(versionLabel);
		if (version.equals("200w") || version.equals("200")) {
			return compact.contains("200");
		}
		if (version.equals("250w") || version.equals("250")) {
			return compact.contains("250");
		}
		if (version.matches("버전\\d+")) {
			String number = version.replace("버전", "");
			return compact.contains("버전" + number) || compact.contains("v" + number) || compact.contains("ver" + number);
		}
		return compact.contains(version);
	}

	private InferredFirmwareName inferFirmwareName(String fileName) {
		String stem = fileName.replaceFirst("(?i)\\.zip$", "");
		String versionLabel = firmwareVersionLabel(stem);
		String base = splitCamelCase(stem)
			.replaceAll("(?i)\\[[^\\]]*\\]", " ")
			.replaceAll("(?i)\\([^)]*\\)", " ")
			.replaceAll("(?i)_?firm\\b", " ")
			.replaceAll("(?i)\\b(ver|version|v)[ _-]?\\d+\\b", " ")
			.replaceAll("(?i)\\b(200|250)\\s*w?\\b", " ")
			.replaceAll("버[전젼]\\s*\\d+", " ")
			.replace("\uC6D0\uBCF8", " ")
			.replace('-', ' ')
			.replace('_', ' ')
			.replaceAll("\\s+", " ")
			.strip();
		if (base.isBlank()) {
			base = stem;
		}
		LinkedHashSet<String> aliases = new LinkedHashSet<>();
		aliases.add(base);
		aliases.add(base.replace(" ", ""));
		aliases.add(fileName);
		aliases.add(stem);
		aliases.addAll(koreanPhoneticAliases(base));
		String family = compactSearchText(base);
		return new InferredFirmwareName(base, family, List.copyOf(aliases), versionLabel);
	}

	private String firmwareVersionLabel(String value) {
		String normalized = normalize(value).toLowerCase(Locale.ROOT);
		if (normalized.matches(".*\\b200\\s*w?\\b.*")) {
			return "200W";
		}
		if (normalized.matches(".*\\b250\\s*w?\\b.*")) {
			return "250W";
		}
		Matcher korean = Pattern.compile("버[전젼]\\s*(\\d+)").matcher(normalized);
		if (korean.find()) {
			return "버전" + korean.group(1);
		}
		Matcher english = Pattern.compile("\\b(?:ver|version|v)[ _-]?(\\d+)\\b").matcher(normalized);
		if (english.find()) {
			return "버전" + english.group(1);
		}
		return "";
	}

	private String splitCamelCase(String value) {
		return value == null ? "" : value.replaceAll("(?<=[a-z])(?=[A-Z])", " ");
	}

	private List<String> koreanPhoneticAliases(String value) {
		String normalized = normalizeSearchText(splitCamelCase(value));
		if (normalized.isBlank()) {
			return List.of();
		}
		List<String> tokens = List.of(normalized.split("\\s+"));
		List<String> koreanTokens = new ArrayList<>();
		for (String token : tokens) {
			String korean = englishTokenToKorean(token);
			if (korean.isBlank()) {
				return List.of();
			}
			koreanTokens.add(korean);
		}
		if (koreanTokens.isEmpty()) {
			return List.of();
		}
		String spaced = String.join(" ", koreanTokens);
		String compact = String.join("", koreanTokens);
		return spaced.equals(compact) ? List.of(compact) : List.of(spaced, compact);
	}

	private String englishTokenToKorean(String token) {
		return switch (token.toLowerCase(Locale.ROOT)) {
			case "allion" -> "올리온";
			case "bereborn" -> "비리본";
			case "plus" -> "플러스";
			case "exo" -> "엑소";
			case "max" -> "맥스";
			case "wave" -> "웨이브";
			case "revive" -> "리바이브";
			case "new" -> "뉴";
			case "reju", "rejuwave" -> "리쥬";
			case "shiva", "siva" -> "쉬바";
			case "slim" -> "슬림";
			case "doc" -> "독";
			case "therma" -> "써마";
			case "on" -> "온";
			case "quantum" -> "퀀텀";
			case "pro" -> "프로";
			case "nova" -> "노바";
			case "ai" -> "에이아이";
			case "health" -> "헬스";
			case "care" -> "케어";
			default -> "";
		};
	}

	private Path firmwareRepositoryPath() {
		return rootPath.resolve(FIRMWARE_REPOSITORY_DIRECTORY).normalize();
	}

	private Path firmwareDeveloperRepositoryPath() {
		return rootPath.resolve(FIRMWARE_DEVELOPER_REPOSITORY_DIRECTORY).normalize();
	}

	private Path copyFirmwareToWorkspace(Path source) {
		try {
			Files.createDirectories(uploadPath);
			Path target = uploadPath.resolve(source.getFileName().toString()).normalize();
			assertInsideRoot(target);
			Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
			return target;
		} catch (IOException exception) {
			throw new IllegalStateException("Failed to copy firmware file to workspace.", exception);
		}
	}

	private String firmwareFoundStatus(FirmwareFile firmwareFile, String completion) {
		String heading = firmwareFile.repositoryKind() == FirmwareRepositoryKind.DEVELOPER
			? "🔍 검색 결과 (개발자 원본)"
			: "🔍 검색 결과";
		StringBuilder status = new StringBuilder(heading)
			.append("\n\n제품명: ").append(firmwareFile.displayName())
			.append("\n파일: ").append(firmwareFile.fileName())
			.append("\n경로: ").append(firmwareFile.path().toAbsolutePath().normalize());
		if (firmwareFile.repositoryKind() == FirmwareRepositoryKind.DEVELOPER) {
			status.append("\n유형: 개발자 원본 파일 ⚠️");
		}
		status.append("\n\n✅ ").append(completion);
		return status.toString();
	}

	private String firmwareCatalogText(List<FirmwareFile> firmwareFiles) {
		StringBuilder builder = new StringBuilder();
		appendFirmwareCatalogSection(builder, "📋 " + firmwareRepositoryPath().toAbsolutePath().normalize()
			+ " — 양산 펌웨어/디스플레이 파일 목록", firmwareFiles, FirmwareRepositoryKind.PRODUCTION);
		appendFirmwareCatalogSection(builder, "\n\n📋 " + firmwareDeveloperRepositoryPath().toAbsolutePath().normalize()
			+ " — 개발자 원본 파일 목록", firmwareFiles, FirmwareRepositoryKind.DEVELOPER);
		return builder.toString().strip();
	}

	private void appendFirmwareCatalogSection(
		StringBuilder builder,
		String heading,
		List<FirmwareFile> firmwareFiles,
		FirmwareRepositoryKind repositoryKind
	) {
		List<FirmwareFile> sectionFiles = firmwareFiles.stream()
			.filter(file -> file.repositoryKind() == repositoryKind)
			.sorted(Comparator.comparing(FirmwareFile::fileName))
			.toList();
		builder.append(heading);
		if (sectionFiles.isEmpty()) {
			builder.append("\n- ZIP 파일 없음");
			return;
		}
		for (int index = 0; index < sectionFiles.size(); index++) {
			FirmwareFile file = sectionFiles.get(index);
			builder.append('\n')
				.append(index + 1)
				.append(". ")
				.append(file.displayName())
				.append(" — ")
				.append(file.fileName());
		}
	}

	private String firmwareOptionLabel(FirmwareFile firmwareFile) {
		String versionLabel = firmwareFile.versionLabel();
		String label = versionLabel.isBlank() ? firmwareFile.displayName() : versionLabel;
		if (firmwareFile.repositoryKind() == FirmwareRepositoryKind.DEVELOPER) {
			return label + " / 개발자 원본";
		}
		return label + " / 양산";
	}

	private String firmwareClarificationName(List<FirmwareFile> options) {
		if (options.isEmpty()) {
			return "해당 제품";
		}
		return switch (options.get(0).family()) {
			case "bereborn-plus" -> "비리본 플러스";
			case "slim-doc" -> "슬림독";
			case "new-revive" -> "뉴 리바이브";
			default -> options.get(0).displayName().replaceAll("\\s*\\([^)]*\\)", "");
		};
	}

	public List<AvaAiWorkspaceItemResponse> listFiles(String path, AuthPrincipal principal) {
		Path directory = resolveInsideRoot(path);
		if (!Files.isDirectory(directory)) {
			Path fallback = bestExistingPathForExplicitPath(path);
			if (fallback == null || !Files.isDirectory(fallback, LinkOption.NOFOLLOW_LINKS)) {
				throw new IllegalArgumentException("Workspace path is not a directory.");
			}
			directory = fallback;
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

	private WorkspaceActionResult inspectExplicitWorkspacePath(String path, AuthPrincipal principal) {
		Path target;
		try {
			target = resolveInsideRoot(path);
		} catch (IllegalArgumentException exception) {
			return null;
		}
		if (!Files.exists(target)) {
			target = bestExistingPathForExplicitPath(path);
			if (target == null) {
				return null;
			}
		}
		if (Files.isDirectory(target, LinkOption.NOFOLLOW_LINKS)) {
			List<AvaAiWorkspaceItemResponse> listed = listFiles(relativePath(target), principal);
			String status = workspacePathLabel(target) + " 폴더에서 " + listed.size()
				+ "개 항목을 확인했습니다" + itemTitlePreview(listed) + ".";
			return new WorkspaceActionResult(
				List.copyOf(limitItems(listed, 120)),
				status,
				promptContext(listed, status),
				true
			);
		}
		if (Files.isRegularFile(target, LinkOption.NOFOLLOW_LINKS)) {
			AvaAiWorkspaceItemResponse item = readFile(relativePath(target), principal);
			String status = workspacePathLabel(target) + " 파일을 확인했습니다.";
			return new WorkspaceActionResult(
				List.of(item),
				status,
				promptContext(List.of(item), status),
				true
			);
		}
		return null;
	}

	private Path bestExistingPathForExplicitPath(String path) {
		FileSearchQuery query = fileSearchQuery(path);
		if (query.tokens().isEmpty()) {
			return null;
		}
		List<ScoredPath> results = new ArrayList<>();
		searchDirectory(rootPath, query, results);
		if (results.isEmpty()) {
			return null;
		}
		String terminal = compactSearchText(lastPathSegment(path));
		return results.stream()
			.sorted(Comparator
				.comparing((ScoredPath item) -> !Files.isDirectory(item.path(), LinkOption.NOFOLLOW_LINKS))
				.thenComparing((ScoredPath item) -> terminal.isBlank() || !compactSearchText(relativePath(item.path())).contains(terminal))
				.thenComparing(Comparator.comparingInt(ScoredPath::score).reversed())
				.thenComparing(item -> relativePath(item.path()).length()))
			.map(ScoredPath::path)
			.findFirst()
			.orElse(null);
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
			ChatMessageResponse response = chatService.send(
				room.code(),
				new ChatMessageRequest(message, false, false, List.of()),
				principal
			);
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

	public List<AvaAiWorkspaceItemResponse> searchMentionNotifications(String query, AuthPrincipal principal) {
		String normalized = normalize(query).toLowerCase(Locale.ROOT);
		List<String> tokens = tokens(normalized, Set.of(
			"\uBA58\uC158",
			"\uC54C\uB824",
			"\uC628\uAC70",
			"\uC628\uAC83",
			"\uB098\uD55C\uD14C",
			"\uB0B4\uAC8C",
			"\uC804\uBD80",
			"\uBAA8\uB450",
			"\uC5B4\uC81C",
			"\uC624\uB298"
		));
		QueryHints hints = queryHints(normalized);
		List<AvaAiWorkspaceItemResponse> items = new ArrayList<>();
		List<ChatMentionNotificationEntity> notifications = mentionNotificationRepository
			.findByMentionedAccount_IdOrderByCreatedAtDesc(principal.userId(), PageRequest.of(0, 120));
		for (ChatMentionNotificationEntity notification : notifications) {
			if (items.size() >= MAX_CHAT_RESULTS) {
				break;
			}
			ChatMessageEntity message = notification.getMessage();
			if (!matchesTimeHints(message.getSentAt(), hints)) {
				continue;
			}
			String roomTitle = "";
			for (ChatRoomResponse room : chatService.rooms(principal)) {
				if (room.code().equals(notification.getRoomCode())) {
					roomTitle = room.title();
					break;
				}
			}
			String haystack = (message.getSenderName() + " " + roomTitle + " " + message.getContent())
				.toLowerCase(Locale.ROOT);
			if (!tokens.isEmpty() && tokens.stream().noneMatch(haystack::contains)) {
				continue;
			}
			items.add(new AvaAiWorkspaceItemResponse(
				"mention_notification",
				message.getSenderName() + " \u00b7 " + (roomTitle == null || roomTitle.isBlank()
					? notification.getRoomCode()
					: roomTitle),
				"@" + notification.getMentionDisplayName() + " \u00b7 " + message.getSentAt(),
				"",
				"",
				"",
				message.getContent(),
				null,
				message.getSentAt(),
				notification.getRoomCode()
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
			if (current == null || Files.isSymbolicLink(current) || shouldSkipSearchPath(current, query)) {
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

	private boolean shouldSkipSearchPath(Path path, FileSearchQuery query) {
		if (path == null || path.equals(rootPath)) {
			return false;
		}
		String name = path.getFileName() == null ? "" : path.getFileName().toString().toLowerCase(Locale.ROOT);
		if (name.isBlank()) {
			return false;
		}
		if (name.equals("$recycle.bin")
			|| name.equals("system volume information")
			|| name.equals(".abbas_nas_recycle_bin")
			|| name.equals("__macosx")
			|| name.equals(".git")
			|| name.equals("node_modules")) {
			return true;
		}
		if (query.archiveIntent() && !query.sourceCodeIntent()
			&& (name.equals("debug")
				|| name.equals("release")
				|| name.equals("build")
				|| name.equals("bin")
				|| name.equals("obj"))) {
			return true;
		}
		return false;
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
		boolean directory = Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS);
		boolean archive = !extension.isBlank() && ARCHIVE_FILE_EXTENSIONS.contains(extension);
		int depth = relativePath(path).isBlank()
			? 0
			: relativePath(path).replace('\\', '/').split("/").length;
		int score = 0;
		int matchedGroups = 0;

		if (query.firmwareIntent()) {
			if (directory && (compactName.contains("펌웨어") || compactName.contains("firmware") || compactName.contains("firm"))) {
				score += 180;
			}
			if (archive) {
				score += 130;
			}
		}
		if (query.archiveIntent() && archive) {
			score += 100;
		}
		if (query.archiveIntent() && directory && depth <= 3) {
			score += 36;
		}
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
		if (directory) {
			score += 10;
		} else if (!extension.isBlank() && SOURCE_CODE_EXTENSIONS.contains(extension)) {
			score += 12;
		}
		if (query.archiveIntent() && !query.sourceCodeIntent() && !archive && !directory) {
			score -= 34;
		}
		if (query.firmwareIntent() && !query.sourceCodeIntent() && depth >= 5 && !archive) {
			score -= 60;
		}
		score += Math.max(0, 24 - (relative.length() / 28));
		return Math.max(0, score);
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
		boolean firmwareIntent = containsAny(normalizedPhrase, FIRMWARE_INTENT_TOKENS);
		boolean strongSourceCodeIntent = arduinoIntent ||
			containsAny(normalizedPhrase, STRONG_SOURCE_CODE_INTENT_TOKENS) ||
			explicitExtensions.stream().anyMatch(SOURCE_CODE_EXTENSIONS::contains);
		boolean sourceCodeIntent = arduinoIntent ||
			strongSourceCodeIntent ||
			explicitExtensions.stream().anyMatch(SOURCE_CODE_EXTENSIONS::contains);
		boolean archiveIntent = firmwareIntent ||
			containsAny(normalizedPhrase, ARCHIVE_INTENT_TOKENS) ||
			explicitExtensions.stream().anyMatch(ARCHIVE_FILE_EXTENSIONS::contains);
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
			arduinoIntent,
			firmwareIntent,
			archiveIntent
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
				addVariant(variants, "\uD38C\uC6E8\uC5B4 \uBAA8\uC74C");
				addVariant(variants, "\uC6D0\uBCF8");
			}
			case "\uBE44\uB9AC\uBCF8", "\uBCA0\uB9AC\uBCF8", "bereborn", "be-reborn", "be_reborn", "reborn" -> {
				addVariant(variants, "\uBE44\uB9AC\uBCF8");
				addVariant(variants, "\uBCA0\uB9AC\uBCF8");
				addVariant(variants, "bereborn");
				addVariant(variants, "be reborn");
				addVariant(variants, "be-reborn");
				addVariant(variants, "be_reborn");
				addVariant(variants, "reborn");
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
			if (SOURCE_CODE_EXTENSIONS.contains(token)
				|| TEXT_SEARCH_EXTENSIONS.contains(token)
				|| ARCHIVE_FILE_EXTENSIONS.contains(token)) {
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
		normalized = normalized.replaceAll("/{2,}", "/");
		if (normalized.matches("^[A-Za-z]:/.*")) {
			normalized = normalized.substring(3);
		}
		while (normalized.startsWith("/")) {
			normalized = normalized.substring(1);
		}
		normalized = stripWorkspaceRootAlias(normalized);
		Path target = rootPath.resolve(normalized).normalize();
		assertInsideRoot(target);
		return target;
	}

	private String stripWorkspaceRootAlias(String value) {
		String normalized = value == null ? "" : value.trim().replace('\\', '/');
		normalized = normalized.replaceAll("/{2,}", "/");
		while (normalized.startsWith("/")) {
			normalized = normalized.substring(1);
		}
		String lower = normalized.toLowerCase(Locale.ROOT);
		for (String alias : List.of("foriver_nas", "foriver-nas", "foriver nas", "forivernas")) {
			if (lower.equals(alias)) {
				return "";
			}
			if (lower.startsWith(alias + "/")) {
				String stripped = normalized.substring(alias.length() + 1);
				while (stripped.startsWith("/")) {
					stripped = stripped.substring(1);
				}
				return stripped;
			}
		}
		return normalized;
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
			"firm",
			"fw",
			"zip",
			"archive",
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

	private boolean hasFileMutationIntent(String value) {
		return containsAny(value, "삭제", "지워", "생성", "만들", "수정", "변경", "덮어");
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

	private String workspacePathLabel(Path path) {
		String relative = relativePath(path).replace('/', '\\');
		return relative.isBlank() ? "FORIVER_NAS" : "FORIVER_NAS\\" + relative;
	}

	private String itemTitlePreview(List<AvaAiWorkspaceItemResponse> items) {
		if (items == null || items.isEmpty()) {
			return "";
		}
		List<String> titles = items.stream()
			.limit(12)
			.map(AvaAiWorkspaceItemResponse::title)
			.filter(title -> title != null && !title.isBlank())
			.toList();
		if (titles.isEmpty()) {
			return "";
		}
		String suffix = items.size() > titles.size() ? " 외 " + (items.size() - titles.size()) + "개" : "";
		return ": " + String.join(", ", titles) + suffix;
	}

	private boolean hasChatIntent(String value) {
		return containsAny(value, "채팅", "말했", "올린", "보낸", "메시지", "사진", "이미지", "첨부");
	}

	private boolean hasMentionIntent(String value) {
		return value.contains("\uBA58\uC158") || value.contains("@");
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
					return trimToExistingWorkspacePath(candidate);
				}
			}
		}
		int driveIndex = value.toLowerCase(Locale.ROOT).indexOf("f:");
		if (driveIndex >= 0) {
			String candidate = value.substring(driveIndex);
			if (looksLikePath(candidate)) {
				return trimToExistingWorkspacePath(candidate);
			}
		}
		for (String alias : List.of("FORIVER_NAS", "FORIVER-NAS", "FORIVER NAS", "FORIVERNAS")) {
			int aliasIndex = value.toLowerCase(Locale.ROOT).indexOf(alias.toLowerCase(Locale.ROOT));
			if (aliasIndex >= 0) {
				String candidate = value.substring(aliasIndex);
				if (looksLikePath(candidate)) {
					return trimToExistingWorkspacePath(candidate);
				}
			}
		}
		for (String part : value.split("\\s+")) {
			if (looksLikePath(part)) {
				return trimToExistingWorkspacePath(part);
			}
		}
		return "";
	}

	private String trimToExistingWorkspacePath(String value) {
		String normalized = value == null ? "" : value.trim();
		normalized = normalized.replaceAll("^[\"'`]+|[\"'`.。]+$", "").trim();
		if (normalized.isBlank()) {
			return "";
		}
		String direct = trimTrailingPathCommandWords(normalized);
		if (workspacePathExists(direct)) {
			return direct;
		}
		String[] parts = normalized.split("\\s+");
		for (int end = parts.length; end >= 1; end--) {
			String candidate = String.join(" ", java.util.Arrays.copyOf(parts, end)).trim();
			candidate = trimTrailingPathCommandWords(candidate);
			if (workspacePathExists(candidate)) {
				return candidate;
			}
		}
		return direct;
	}

	private String trimTrailingPathCommandWords(String value) {
		String candidate = value == null ? "" : value.trim();
		boolean changed;
		do {
			changed = false;
			for (String suffix : List.of(
				"파일 목록 보여줘",
				"파일목록 보여줘",
				"목록 보여줘",
				"목록",
				"보여줘",
				"알려줘",
				"찾아줘",
				"검색해줘",
				"확인해줘",
				"열어줘",
				"안에",
				"에서",
				"파일",
				"폴더"
			)) {
				if (candidate.length() > suffix.length() && candidate.endsWith(suffix)) {
					candidate = candidate.substring(0, candidate.length() - suffix.length()).trim();
					changed = true;
				}
			}
		} while (changed);
		return candidate;
	}

	private String lastPathSegment(String value) {
		String normalized = trimTrailingPathCommandWords(value == null ? "" : value.trim())
			.replace('\\', '/')
			.replaceAll("/{2,}", "/");
		while (normalized.endsWith("/") && normalized.length() > 1) {
			normalized = normalized.substring(0, normalized.length() - 1);
		}
		int slash = normalized.lastIndexOf('/');
		return slash >= 0 ? normalized.substring(slash + 1).trim() : normalized.trim();
	}

	private boolean workspacePathExists(String value) {
		if (value == null || value.isBlank()) {
			return false;
		}
		try {
			return Files.exists(resolveInsideRoot(value));
		} catch (IllegalArgumentException exception) {
			return false;
		}
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

	private record FirmwareProduct(String displayName, String fileName, String family, List<String> aliases) {
	}

	private enum FirmwareRepositoryKind {
		PRODUCTION,
		DEVELOPER
	}

	private record FirmwareFile(
		String displayName,
		String fileName,
		String family,
		List<String> aliases,
		Path path,
		FirmwareRepositoryKind repositoryKind,
		String versionLabel
	) {
	}

	private record InferredFirmwareName(
		String displayName,
		String family,
		List<String> aliases,
		String versionLabel
	) {
	}

	private record FirmwareMatch(FirmwareFile file, int score) {
	}

	private record FirmwareRequest(boolean triggered, boolean listRequested, boolean chatDeliveryRequested) {
	}

	private record FileSearchQuery(
		String phrase,
		List<String> tokens,
		List<List<String>> variants,
		Set<String> preferredExtensions,
		boolean sourceCodeIntent,
		boolean arduinoIntent,
		boolean firmwareIntent,
		boolean archiveIntent
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
