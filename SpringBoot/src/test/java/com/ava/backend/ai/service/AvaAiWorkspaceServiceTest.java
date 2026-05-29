package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.data.domain.Pageable;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.chat.dto.ChatRoomResponse;
import com.ava.backend.chat.dto.ChatTalkDrawerItemResponse;
import com.ava.backend.chat.entity.ChatMessageEntity;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.entity.ChatTalkDrawerMediaType;
import com.ava.backend.chat.repository.ChatMessageJpaRepository;
import com.ava.backend.chat.service.ChatService;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.entity.UserRole;

class AvaAiWorkspaceServiceTest {

	@TempDir
	Path workspaceRoot;

	@Test
	void findsDevelopmentPlanFilesFromPluralKoreanPrompt() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uAC1C\uBC1C\uC548\uB4E4 \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(
			result.items().stream().anyMatch(item -> item.path().contains("\uAC1C\uBC1C\uC548")),
			"Expected plural Korean prompt to find files under the development-plan directory."
		);
	}

	@Test
	void listsExplicitForiverNasAliasPath() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\"FORIVER_NAS\\\uD38C\uC6E8\uC5B4 \uBAA8\uC74C\"",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected explicit FORIVER_NAS path to be handled by workspace listing.");
		assertTrue(
			result.status().contains("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C"),
			"Expected explicit alias path to list the requested firmware collection folder, status=" + result.status()
		);
		assertTrue(
			result.items().stream().anyMatch(item -> item.path().contains("Bereborn")),
			"Expected FORIVER_NAS alias path listing to include firmware archive files but got " +
				result.items().stream().map(item -> item.path()).toList()
		);

		AvaAiWorkspaceService.WorkspaceActionResult escapedSlashResult = service.inspectPrompt(
			"FORIVER_NAS\\\\\uD38C\uC6E8\uC5B4 \uBAA8\uC74C",
			null,
			List.of(),
			List.of()
		);

		assertTrue(escapedSlashResult.handled(), "Expected doubled Windows slashes to resolve as the same alias path.");
	}

	@Test
	void sentFileHistoryPromptSurfacesChatAttachmentsRoomsAndRecipients() throws Exception {
		UUID senderId = UUID.randomUUID();
		UUID recipientId = UUID.randomUUID();
		AuthPrincipal principal = new AuthPrincipal(
			senderId,
			"sender@ava.local",
			"박주한",
			UserRole.USER,
			"test-session"
		);
		Instant sentAt = LocalDate.now(ZoneId.of("Asia/Seoul"))
			.minusDays(1)
			.atTime(15, 20)
			.atZone(ZoneId.of("Asia/Seoul"))
			.toInstant();
		ChatService chatService = mock(ChatService.class);
		ChatMessageJpaRepository messageRepository = mock(ChatMessageJpaRepository.class);
		ChatMessageEntity attachment = sentAttachment(
			"direct-test",
			senderId,
			"박주한",
			"견적서.pdf",
			"application/pdf",
			24_000,
			sentAt
		);
		ChatRoomResponse room = new ChatRoomResponse(
			"direct-test",
			"박보검",
			ChatRoomType.DIRECT,
			2,
			false,
			null,
			"견적서.pdf",
			sentAt,
			false,
			"",
			null,
			List.of(
				profile(senderId, "sender@ava.local", "박주한"),
				profile(recipientId, "receiver@ava.local", "박보검")
			),
			0,
			false
		);
		when(chatService.rooms(principal)).thenReturn(List.of(room));
		when(messageRepository.findByRoomCodeAndSentAtGreaterThanEqualAndSentAtLessThanOrderBySentAtDesc(
			eq("direct-test"),
			any(Instant.class),
			any(Instant.class),
			any(Pageable.class)
		)).thenReturn(List.of(attachment));

		AvaAiWorkspaceService service = new AvaAiWorkspaceService(
			chatService,
			messageRepository,
			null,
			null,
			null,
			null,
			null,
			null,
			workspaceRoot.toString(),
			"AVA_AI_Workspace",
			workspaceRoot.resolve("ChatUploads").toString()
		);

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"어제 누구한테 파일을 보냈던거 같은데 뭐였지?",
			principal,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected sent-file history prompts to be handled before NAS search.");
		assertTrue(result.status().contains("견적서.pdf"), result.status());
		assertTrue(result.status().contains("박보검"), result.status());
		assertTrue(
			result.items().stream().anyMatch(item -> item.type().equals("chat_file")),
			"Expected the sent file to appear as a chat file card."
		);
		assertTrue(
			result.items().stream().anyMatch(item -> item.type().equals("chat_room") && item.roomCode().equals("direct-test")),
			"Expected the related chat room to appear in the workspace."
		);
		assertTrue(
			result.items().stream().anyMatch(item -> item.type().equals("user_profile") && item.title().contains("박보검")),
			"Expected the recipient profile to appear in the workspace."
		);
		assertFalse(
			result.items().stream().anyMatch(item -> item.type().equals("file") || item.title().contains("FORIVER_NAS")),
			"Sent-file history should not fall through into unrelated NAS file search results."
		);
	}

	@Test
	void sentFileHistoryPromptExpandsRecentWhenYesterdayIsOnlyApproximate() throws Exception {
		UUID senderId = UUID.randomUUID();
		UUID recipientId = UUID.randomUUID();
		AuthPrincipal principal = new AuthPrincipal(
			senderId,
			"sender@ava.local",
			"박주한",
			UserRole.USER,
			"test-session"
		);
		Instant sentAt = LocalDate.now(ZoneId.of("Asia/Seoul"))
			.atTime(0, 6)
			.atZone(ZoneId.of("Asia/Seoul"))
			.toInstant();
		ChatService chatService = mock(ChatService.class);
		ChatMessageJpaRepository messageRepository = mock(ChatMessageJpaRepository.class);
		ChatMessageEntity attachment = sentAttachment(
			"direct-test",
			senderId,
			"박주한",
			"Bereborn [Tron].zip",
			"application/zip",
			1_250_000,
			sentAt
		);
		ChatRoomResponse room = new ChatRoomResponse(
			"direct-test",
			"박주한",
			ChatRoomType.DIRECT,
			2,
			false,
			null,
			"Bereborn [Tron].zip",
			sentAt,
			false,
			"",
			null,
			List.of(
				profile(senderId, "sender@ava.local", "나"),
				profile(recipientId, "receiver@ava.local", "박주한")
			),
			0,
			false
		);
		when(chatService.rooms(principal)).thenReturn(List.of(room));
		when(messageRepository.findByRoomCodeAndSentAtGreaterThanEqualAndSentAtLessThanOrderBySentAtDesc(
			eq("direct-test"),
			any(Instant.class),
			any(Instant.class),
			any(Pageable.class)
		)).thenReturn(List.of()).thenReturn(List.of(attachment));

		AvaAiWorkspaceService service = new AvaAiWorkspaceService(
			chatService,
			messageRepository,
			null,
			null,
			null,
			null,
			null,
			null,
			workspaceRoot.toString(),
			"AVA_AI_Workspace",
			workspaceRoot.resolve("ChatUploads").toString()
		);

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"어제 누구한테 파일을 보냈던거 같은데 뭐였지?",
			principal,
			List.of(),
			List.of()
		);

		assertTrue(result.handled());
		assertTrue(result.status().contains("최근 7"), result.status());
		assertTrue(result.status().contains("Bereborn [Tron].zip"), result.status());
		assertTrue(result.items().stream().anyMatch(item -> item.title().equals("Bereborn [Tron].zip")));
		assertTrue(result.items().stream().anyMatch(item -> item.type().equals("user_profile") && item.title().contains("박주한")));
	}

	@Test
	void sentFileHistoryPromptFallsBackToTalkDrawerAttachments() throws Exception {
		UUID senderId = UUID.randomUUID();
		UUID recipientId = UUID.randomUUID();
		AuthPrincipal principal = new AuthPrincipal(
			senderId,
			"sender@ava.local",
			"박주한",
			UserRole.USER,
			"test-session"
		);
		Instant sentAt = LocalDate.now(ZoneId.of("Asia/Seoul"))
			.minusDays(1)
			.atTime(12, 6)
			.atZone(ZoneId.of("Asia/Seoul"))
			.toInstant();
		ChatService chatService = mock(ChatService.class);
		ChatMessageJpaRepository messageRepository = mock(ChatMessageJpaRepository.class);
		ChatRoomResponse room = new ChatRoomResponse(
			"direct-test",
			"박주한",
			ChatRoomType.DIRECT,
			2,
			false,
			null,
			"Bereborn [Tron] 원본.zip",
			sentAt,
			false,
			"",
			null,
			List.of(
				profile(senderId, "sender@ava.local", "나"),
				profile(recipientId, "receiver@ava.local", "박주한")
			),
			0,
			false
		);
		ChatTalkDrawerItemResponse drawerItem = new ChatTalkDrawerItemResponse(
			UUID.randomUUID(),
			"ABBA-S",
			"direct-test",
			UUID.randomUUID().toString(),
			"attachment-1",
			"group-1",
			"Bereborn [Tron] 원본.zip",
			"application/zip",
			4_120_000,
			ChatTalkDrawerMediaType.FILE,
			"/api/chat/rooms/direct-test/attachments/attachment-1",
			"",
			senderId,
			"박주한",
			sentAt
		);
		when(chatService.rooms(principal)).thenReturn(List.of(room));
		when(messageRepository.findByRoomCodeAndSentAtGreaterThanEqualAndSentAtLessThanOrderBySentAtDesc(
			eq("direct-test"),
			any(Instant.class),
			any(Instant.class),
			any(Pageable.class)
		)).thenReturn(List.of());
		when(chatService.talkDrawerItems("direct-test", null, principal)).thenReturn(List.of(drawerItem));

		AvaAiWorkspaceService service = new AvaAiWorkspaceService(
			chatService,
			messageRepository,
			null,
			null,
			null,
			null,
			null,
			null,
			workspaceRoot.toString(),
			"AVA_AI_Workspace",
			workspaceRoot.resolve("ChatUploads").toString()
		);

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"어제 누구한테 파일을 보냈던거 같은데 뭐였지?",
			principal,
			List.of(),
			List.of()
		);

		assertTrue(result.handled());
		assertTrue(result.status().contains("Bereborn [Tron] 원본.zip"), result.status());
		assertTrue(result.items().stream().anyMatch(item -> item.title().equals("Bereborn [Tron] 원본.zip")));
		assertTrue(result.items().stream().anyMatch(item -> item.type().equals("chat_room") && item.roomCode().equals("direct-test")));
	}

	@Test
	void findsBerebornFirmwareFromKoreanAlias() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		var items = service.searchFiles(
			"\uBE44\uB9AC\uBCF8 \uAD00\uB828 \uD30C\uC77C \uCC3E\uC544\uC918",
			"",
			null
		);

		assertTrue(
			items.stream().anyMatch(item -> item.path().contains("Bereborn")),
			"Expected Korean alias 비리본 to find Bereborn archives but got " +
				items.stream().map(item -> item.path()).toList()
		);
	}

	@Test
	void genericFirmwareSearchPrioritizesArchivesAndFoldersOverDeepInternalFiles() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		var items = service.searchFiles(
			"\uD38C\uC6E8\uC5B4 \uAD00\uB828\uD30C\uC77C \uCC3E\uC544\uC918",
			"",
			null
		);

		assertFalse(items.isEmpty(), "Expected generic firmware search results.");
		assertTrue(
			items.stream().limit(8).anyMatch(item -> item.path().endsWith(".zip") || item.type().equals("directory")),
			"Expected generic firmware search to prioritize archive files or firmware folders but got " +
				items.stream().limit(8).map(item -> item.path()).toList()
		);
	}

	@Test
	void firmwarePromptUploadsCatalogZipFromKoreanAlias() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uBE44\uB9AC\uBCF8 \uAD00\uB828 \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected firmware catalog prompt to be handled directly.");
		assertTrue(result.status().contains("Bereborn [Tron].zip"), result.status());
		assertTrue(
			result.items().stream().anyMatch(item -> item.path().contains("AVA_AI_Workspace") && item.path().contains("Bereborn")),
			"Expected catalog file to be copied into AVA AI workspace but got " +
				result.items().stream().map(item -> item.path()).toList()
		);
		assertTrue(
			Files.exists(workspaceRoot.resolve("AVA_AI_Workspace").resolve("Bereborn [Tron].zip")),
			"Expected Bereborn firmware zip to be copied into the local AVA workspace."
		);
	}

	@Test
	void firmwarePromptAsksVersionForBerebornPlus() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uBE44\uB9AC\uBCF8 \uD50C\uB7EC\uC2A4 \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected ambiguous Bereborn Plus prompt to ask for a version.");
		assertTrue(result.status().contains("Bereborn Plus \uBC84\uC8041 [Tron].zip"), result.status());
		assertTrue(result.status().contains("Bereborn Plus \uBC84\uC8042 [Tron].zip"), result.status());
	}

	@Test
	void firmwarePromptResolvesShivaTypoAndUploads() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uC2C0\uBC14 \uB514\uC2A4\uD50C\uB808\uC774 \uD30C\uC77C \uC62C\uB824\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected SHIVA typo alias to be handled directly.");
		assertTrue(result.status().contains("SHIVA [TRON].zip"), result.status());
		assertTrue(
			Files.exists(workspaceRoot.resolve("AVA_AI_Workspace").resolve("SHIVA [TRON].zip")),
			"Expected SHIVA firmware zip to be copied into the local AVA workspace."
		);
	}

	@Test
	void firmwarePromptAsksWattageForNewRevive() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uB274 \uB9AC\uBC14\uC774\uBE0C \uD38C\uC6E8\uC5B4 \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected New Revive prompt without wattage to ask for wattage.");
		assertTrue(result.status().contains("New-Revive200[Tron].zip"), result.status());
		assertTrue(result.status().contains("New-Revive250 [Tron].zip"), result.status());
	}

	@Test
	void firmwarePromptListsCatalog() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uD38C\uC6E8\uC5B4 \uBAA9\uB85D \uBCF4\uC5EC\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected firmware list prompt to be handled directly.");
		assertTrue(result.items().size() >= 15, "Expected the full firmware catalog to be surfaced.");
		assertTrue(result.status().contains("Wave On [TRON].zip") || result.status().contains("\uC6E8\uC774\uBE0C\uC628"), result.status());
	}

	@Test
	void firmwarePromptAsksSourceWhenProductionAndDeveloperBothMatch() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uADF9\uCD08\uB2E8\uD30C \uC6D0\uBCF8/Bereborn [Tron] \uC6D0\uBCF8.zip");

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uBE44\uB9AC\uBCF8 \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected dual repository match to be handled directly.");
		assertTrue(result.status().contains("\uC591\uC0B0 \uD30C\uC77C"), result.status());
		assertTrue(result.status().contains("\uAC1C\uBC1C\uC790 \uC6D0\uBCF8"), result.status());
		assertTrue(result.status().contains("Bereborn [Tron].zip"), result.status());
		assertTrue(result.status().contains("Bereborn [Tron] \uC6D0\uBCF8.zip"), result.status());
	}

	@Test
	void firmwarePromptUploadsDeveloperOriginalWhenRequested() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uADF9\uCD08\uB2E8\uD30C \uC6D0\uBCF8/Bereborn [Tron] \uC6D0\uBCF8.zip");

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uBE44\uB9AC\uBCF8 \uC6D0\uBCF8 \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected explicit developer original request to upload the developer ZIP.");
		assertTrue(result.status().contains("\uAC80\uC0C9 \uACB0\uACFC (\uAC1C\uBC1C\uC790 \uC6D0\uBCF8)"), result.status());
		assertTrue(result.status().contains("\uAC1C\uBC1C\uC790 \uC6D0\uBCF8 \uD30C\uC77C"), result.status());
		assertTrue(
			Files.exists(workspaceRoot.resolve("AVA_AI_Workspace").resolve("Bereborn [Tron] \uC6D0\uBCF8.zip")),
			"Expected developer original firmware zip to be copied into the local AVA workspace."
		);
	}

	@Test
	void firmwarePromptDiscoversUnknownQuantumZipFromKoreanPhoneticName() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();
		writeFile("\uC81C\uD488 \uC790\uB8CC/Quantum [HIC].zip");

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uD000\uD140 \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected unknown Quantum ZIP to be discovered dynamically.");
		assertTrue(result.status().contains("Quantum [HIC].zip"), result.status());
		assertTrue(
			Files.exists(workspaceRoot.resolve("AVA_AI_Workspace").resolve("Quantum [HIC].zip")),
			"Expected dynamically discovered Quantum zip to be copied into the local AVA workspace."
		);
	}

	@Test
	void firmwarePromptAsksVersionForDynamicallyDiscoveredProduct() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();
		writeFile("\uC81C\uD488 \uC790\uB8CC/NOVA-Slim \uBC84\uC8041[TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/NOVA-Slim \uBC84\uC8042[TRON].zip");

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"\uB178\uBC14\uC2AC\uB9BC \uD30C\uC77C \uCC3E\uC544\uC918",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected dynamic versioned product to ask for version.");
		assertTrue(result.status().contains("NOVA-Slim \uBC84\uC8041[TRON].zip"), result.status());
		assertTrue(result.status().contains("NOVA-Slim \uBC84\uC8042[TRON].zip"), result.status());
		assertTrue(result.status().contains("\uC5B4\uB5A4 \uBC84\uC804"), result.status());
	}

	@Test
	void findsWorkspaceFilesAcrossThirtyPlusNaturalLanguagePrompts() throws Exception {
		AvaAiWorkspaceService service = serviceWithFixture();
		List<PromptCase> cases = List.of(
			new PromptCase("\uAC1C\uBC1C\uC548\uB4E4 \uCC3E\uC544\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uAC1C\uBC1C\uC548 \uC790\uB8CC \uBCF4\uC5EC\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uAC1C\uBC1C\uC548 \uD3F4\uB354 \uC5B4\uB514 \uC788\uC5B4", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uAC1C\uBC1C\uC548\uC5D0 \uC788\uB294 \uD30C\uC77C \uC804\uBD80", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uAC1C\uBC1C \uACC4\uD68D\uC548 \uCC3E\uC544\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uAE30\uD68D\uC548 \uBAA9\uB85D \uBCF4\uC5EC\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uC81C\uC548\uC11C \uAC80\uC0C9\uD574\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("development plan files", "\uAC1C\uBC1C\uC548"),
			new PromptCase("proposal documents", "\uAC1C\uBC1C\uC548"),
			new PromptCase("project plan \uCC3E\uC544\uC918", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uC778\uBC14\uB514 \uAC1C\uBC1C\uC548", "INBODY_Project"),
			new PromptCase("INBODY project proposal", "INBODY_Project"),
			new PromptCase("AI \uBD84\uC11D \uC5F0\uB3D9 \uC7A5\uBE44 \uCC3E\uC544\uC918", "AI \uBD84\uC11D \uC5F0\uB3D9 \uC7A5\uBE44"),
			new PromptCase("\uC0AC\uC0C1\uCCB4\uC9C8 \uBBF8\uC6A9\uAE30\uAE30 \uC790\uB8CC", "\uC0AC\uC0C1\uCCB4\uC9C8"),
			new PromptCase("for rnd \uAC1C\uBC1C\uC548", "FOR_RND_Project"),
			new PromptCase("FOR_RND \uAE30\uB2A5\uC124\uBA85\uC11C", "IOT \uAE30\uB2A5\uC124\uBA85\uC11C"),
			new PromptCase("\uC544\uC774\uC624\uD2F0 \uAE30\uB2A5 \uC124\uBA85\uC11C \uCC3E\uC544\uC918", "IOT \uAE30\uB2A5\uC124\uBA85\uC11C"),
			new PromptCase("iot manual", "IOT"),
			new PromptCase("ESP32 \uD540\uB9F5", "ESP32"),
			new PromptCase("\uCEE8\uD2B8\uB9AD\uC2A4 \uAE30\uB2A5\uC815\uC758\uC11C", "CONTURIX_Project"),
			new PromptCase("CONTURIX spec", "CONTURIX_Project"),
			new PromptCase("\uAE30\uB2A5 \uC815\uC758 \uBB38\uC11C", "\uAE30\uB2A5\uC815\uC758\uC11C"),
			new PromptCase("\uACE0\uAC1D \uC548\uB0B4\uC11C \uCEE8\uD2B8\uB9AD\uC2A4", "\uACE0\uAC1D\uC744 \uC704\uD55C Conturix \uC548\uB0B4\uC11C"),
			new PromptCase("\uD5EC\uC2A4\uCF00\uC5B4 ui \uC774\uBBF8\uC9C0", "\uD5EC\uC2A4\uCF00\uC5B4 UI"),
			new PromptCase("UIUX page1", "UIUX"),
			new PromptCase("logo \uD30C\uC77C", "LOGO"),
			new PromptCase("\uC368\uB9C8\uBA54\uB4DC \uBD84\uC11D \uBCF4\uACE0\uC11C", "\uC368\uB9C8\uBA54\uB4DC \uBD84\uC11D \uBCF4\uACE0\uC11C"),
			new PromptCase("ThermaMed report", "ThermaMed \uAC1C\uBC1C \uAD00\uB828 \uC790\uB8CC"),
			new PromptCase("MELAUHF \uC6D0\uBCF8", "MELAUHF \uC6D0\uBCF8"),
			new PromptCase("\uD38C\uC6E8\uC5B4 \uC6D0\uBCF8 \uAC80\uC0C9", "\uD38C\uC6E8\uC5B4"),
			new PromptCase("BRF \uC0AC\uC591\uC11C", "BRF"),
			new PromptCase("RS232 protocol", "RS232"),
			new PromptCase("\uCD08\uC74C\uD30C\uC790\uADF9\uAE30 \uAE30\uC220\uBB38\uC11C", "\uCD08\uC74C\uD30C\uC790\uADF9\uAE30"),
			new PromptCase("\uD540\uB9F5 \uC790\uB8CC", "PinMap"),
			new PromptCase("DWIN \uC124\uC815 \uD30C\uC77C", "DWIN"),
			new PromptCase("PCB \uD68C\uB85C\uB3C4", "\uD68C\uB85C\uB3C4"),
			new PromptCase("conturx spec", "CONTURIX_Project"),
			new PromptCase("theramed report", "ThermaMed \uAC1C\uBC1C \uAD00\uB828 \uC790\uB8CC"),
			new PromptCase("INBODI project", "INBODY_Project"),
			new PromptCase("for-rnd plan", "FOR_RND_Project"),
			new PromptCase("\uD540\uC544\uC6C3 \uC774\uBBF8\uC9C0", "pinout"),
			new PromptCase("pinout diagram", "pinout"),
			new PromptCase("\uD68C\uB85C \uC774\uBBF8\uC9C0", "\uD68C\uB85C\uB3C4"),
			new PromptCase("circuit image", "\uD68C\uB85C\uB3C4"),
			new PromptCase("\uC2A4\uD399\uC790\uB8CC brf", "BRF"),
			new PromptCase("\uACE0\uAC1D\uC6A9 before after \uB9AC\uD3EC\uD2B8", "BeforeAfter"),
			new PromptCase("before after report", "BeforeAfter"),
			new PromptCase("\uACE0\uAC1D \uC11C\uBE44\uC2A4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C \uC591\uC2DD", "\uACE0\uAC1D \uC11C\uBE44\uC2A4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C"),
			new PromptCase("softap captive portal design", "Captive Portal"),
			new PromptCase("CP210x driver", "CP210x"),
			new PromptCase("\uB4DC\uB77C\uC774\uBC84 \uB2E4\uC6B4\uB85C\uB4DC \uD30C\uC77C", "CP210x"),
			new PromptCase("webp \uC774\uBBF8\uC9C0", "webp"),
			new PromptCase("\uC6D0\uBCF8 \uBC31\uC5C5", "\uC6D0\uBCF8"),
			new PromptCase("melauhf backup", "MELAUHF"),
			new PromptCase("\uC720\uC5D0\uC2A4\uBE44 rs232 \uD504\uB85C\uD1A0\uCF5C", "RS232"),
			new PromptCase("protocol pdf", "Protocol"),
			new PromptCase("\uB85C\uACE0 \uC774\uBBF8\uC9C0 \uCC3E\uC544\uBD10", "LOGO"),
			new PromptCase("\uD5EC\uC2A4\uCF00\uC5B4 \uD654\uBA74 \uC2DC\uC548", "\uD5EC\uC2A4\uCF00\uC5B4 UI"),
			new PromptCase("page three healthcare ui", "page3"),
			new PromptCase("\uC368\uB9C8\uBA54\uB4DC \uAE30\uB2A5 \uBCF4\uACE0\uC11C", "\uC368\uB9C8\uBA54\uB4DC \uAE30\uB2A5 \uBCF4\uACE0\uC11C"),
			new PromptCase("\uAE30\uB2A5\uC124\uBA85 for rnd", "IOT \uAE30\uB2A5\uC124\uBA85\uC11C"),
			new PromptCase("esp32 c5 provisioning", "Captive Portal"),
			new PromptCase("\uC0AC\uC591 \uC2A4\uD399 brf 2\uCC44\uB110", "BRF 2\uCC44\uB110"),
			new PromptCase("dwin sd card formatter", "DWIN_SDCARD_FORMATTER"),
			new PromptCase("\uD504\uB85C\uC81D\uD2B8 \uAC1C\uBC1C\uC548 \uC5B4\uB514\uC788\uC5B4", "\uAC1C\uBC1C\uC548"),
			new PromptCase("\uC544\uB450\uC774\uB178 \uC18C\uC2A4\uCF54\uB4DC \uAD00\uB828 \uD30C\uC77C\uB4E4 \uCC3E\uC544 \uC54C\uB824\uC918", "MELAUHF_To_ESP32_C5_complete.ino"),
			new PromptCase(".ino\uD30C\uC77C\uB4E4 \uC5C6\uC5B4?", "MELAUHF_To_ESP32_C5_complete.ino"),
			new PromptCase("arduino sketch files", "MELAUHF_To_ESP32_C5_complete.ino"),
			new PromptCase("\uC18C\uC2A4\uCF54\uB4DC \uC804\uBD80 \uD655\uC778\uD574\uC918", "hi-aba")
		);

		for (PromptCase promptCase : cases) {
			var items = service.searchFiles(
				promptCase.prompt(),
				"",
				null
			);

			assertFalse(items.isEmpty(), "Expected files for prompt: " + promptCase.prompt());
			assertTrue(
				items.stream().anyMatch(item -> item.path().contains(promptCase.expectedPathFragment())),
				"Expected prompt [" + promptCase.prompt() + "] to find [" + promptCase.expectedPathFragment() + "] but got " +
					items.stream().map(item -> item.path()).toList()
			);
		}
	}

	@Test
	void findsRealForiverNasArduinoFilesWhenMounted() {
		Path nasRoot = Path.of("F:/");
		Path knownArduinoFolder = nasRoot.resolve("\uAC1C\uBC1C\uC790\uB8CC/\uD38C\uC6E8\uC5B4/ESPtoMELAUHF\uBC31\uC5C5");
		Assumptions.assumeTrue(
			Files.isDirectory(knownArduinoFolder),
			"FORIVER_NAS Arduino fixture is not mounted on this machine."
		);
		AvaAiWorkspaceService service = new AvaAiWorkspaceService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			nasRoot.toString(),
			"AVA_AI_Workspace",
			nasRoot.resolve("ChatUploads").toString()
		);

		var items = service.searchFiles(
			"\uC544\uB450\uC774\uB178 \uC18C\uC2A4\uCF54\uB4DC \uAD00\uB828 \uD30C\uC77C\uB4E4 \uCC3E\uC544 \uC54C\uB824\uC918",
			"",
			null
		);

		assertTrue(
			items.stream().anyMatch(item -> item.path().toLowerCase().endsWith(".ino")),
			"Expected mounted FORIVER_NAS search to find Arduino .ino files but got " +
				items.stream().map(item -> item.path()).toList()
		);
	}

	@Test
	void listsRealForiverNasFirmwareCollectionWhenMounted() {
		Path nasRoot = Path.of("F:/");
		Path firmwareCollection = nasRoot.resolve("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C");
		Assumptions.assumeTrue(
			Files.isDirectory(firmwareCollection),
			"FORIVER_NAS firmware collection is not mounted on this machine."
		);
		AvaAiWorkspaceService service = serviceForNasRoot(nasRoot);

		AvaAiWorkspaceService.WorkspaceActionResult result = service.inspectPrompt(
			"FORIVER_NAS\\\uD38C\uC6E8\uC5B4 \uBAA8\uC74C",
			null,
			List.of(),
			List.of()
		);

		assertTrue(result.handled(), "Expected explicit FORIVER_NAS firmware path to be handled.");
		assertTrue(
			result.status().contains("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C"),
			"Expected real explicit path to stay on firmware collection folder, status=" + result.status()
		);
		assertTrue(
			result.items().stream().anyMatch(item -> item.path().contains("Bereborn") && item.path().endsWith(".zip")),
			"Expected real firmware collection listing to include Bereborn zip files but got " +
				result.items().stream().map(item -> item.path()).toList()
		);
	}

	@Test
	void findsRealForiverNasBerebornFilesFromKoreanAliasWhenMounted() {
		Path nasRoot = Path.of("F:/");
		Path firmwareCollection = nasRoot.resolve("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C");
		Assumptions.assumeTrue(
			Files.isDirectory(firmwareCollection),
			"FORIVER_NAS firmware collection is not mounted on this machine."
		);
		AvaAiWorkspaceService service = serviceForNasRoot(nasRoot);

		var items = service.searchFiles(
			"\uBE44\uB9AC\uBCF8 \uAD00\uB828 \uD30C\uC77C \uCC3E\uC544\uC918",
			"",
			null
		);

		assertTrue(
			items.stream().anyMatch(item -> item.path().contains("Bereborn") && item.path().endsWith(".zip")),
			"Expected Korean alias 비리본 to find real Bereborn zip files but got " +
				items.stream().map(item -> item.path()).toList()
		);
	}

	@Test
	void realForiverNasFirmwareSearchSurfacesFirmwareArchivesWhenMounted() {
		Path nasRoot = Path.of("F:/");
		Path firmwareCollection = nasRoot.resolve("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C");
		Assumptions.assumeTrue(
			Files.isDirectory(firmwareCollection),
			"FORIVER_NAS firmware collection is not mounted on this machine."
		);
		AvaAiWorkspaceService service = serviceForNasRoot(nasRoot);

		var items = service.searchFiles(
			"\uD38C\uC6E8\uC5B4 \uAD00\uB828\uD30C\uC77C \uCC3E\uC544\uC918",
			"",
			null
		);

		assertTrue(
			items.stream().limit(12).anyMatch(item -> item.path().startsWith("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C") && item.path().endsWith(".zip")),
			"Expected generic firmware search to surface top-level firmware zip archives but got " +
				items.stream().limit(12).map(item -> item.path()).toList()
		);
	}

	private AvaAiWorkspaceService serviceWithFixture() throws Exception {
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/INBODY_Project/\uC0AC\uC0C1\uCCB4\uC9C8+8\uC131\uCCB4\uC9C8 \uC9C4\uB2E8 \uBC0F \uBBF8\uC6A9\uAE30\uAE30\uC5D0 \uD65C\uC6A9.hwpx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/INBODY_Project/\uAC1C\uC778 \uB9DE\uCDA4\uD615 AI \uBD84\uC11D \uC5F0\uB3D9 \uC7A5\uBE44.pptx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/INBODY_Project/\uACE0\uAC1D\uC6A9_BeforeAfter_\uB9AC\uD3EC\uD2B8_\uC0D8\uD50C.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/FOR_RND_Project/IOT \uAE30\uB2A5\uC124\uBA85\uC11C_for_rnd.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/FOR_RND_Project/ESP32-C5-DevKitC-1-pinout-diagram.webp");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/FOR_RND_Project/ESP32-C5 SoftAP \uAE30\uBC18 Wi-Fi \uCD08\uAE30 \uD504\uB85C\uBE44\uC800\uB2DD(Captive Portal) \uC124\uACC4.txt");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/FOR_RND_Project/\uACE0\uAC1D \uC11C\uBE44\uC2A4 \uAD00\uB9AC \uC2DC\uC2A4\uD15C (\uC591\uC2DD).pptx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/CONTURIX_Project/\uAE30\uB2A5\uC815\uC758\uC11C.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAC1C\uBC1C\uC548/CONTURIX_Project/\uACE0\uAC1D\uC744 \uC704\uD55C Conturix \uC548\uB0B4\uC11C.hwpx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/UIUX/\uD5EC\uC2A4\uCF00\uC5B4 UI/page1.png");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/UIUX/\uD5EC\uC2A4\uCF00\uC5B4 UI/page3.png");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/UIUX/LOGO/logo.png");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uBCF4\uACE0\uC11C/\uC368\uB9C8\uBA54\uB4DC \uAE30\uB2A5 \uBCF4\uACE0\uC11C 1\uCC28.docx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uD38C\uC6E8\uC5B4/MELAUHF \uC6D0\uBCF8.zip");
		writeFile("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C/Bereborn [Tron].zip");
		writeFile("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C/Bereborn_Plus_MaxWave [Tron].zip");
		writeFile("\uD38C\uC6E8\uC5B4 \uBAA8\uC74C/EXO-Wave [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/ALLION_GMP_Firm.zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Bereborn [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Bereborn Plus \uBC84\uC8041 [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Bereborn Plus \uBC84\uC8042 [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/EXO-Wave [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Max-Wave [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Revive  [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/New-Revive200[Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/New-Revive250 [Tron].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/RejuWave [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/SHIVA [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/SLIM DOC \uBC84\uC8041 [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/SLIM DOC \uBC84\uC8042 [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/ThermaWave [TRON].zip");
		writeFile("\uC81C\uD488 \uC790\uB8CC/Wave On [TRON].zip");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAE30\uC220\uC790\uB8CC/ThermaMed \uAC1C\uBC1C \uAD00\uB828 \uC790\uB8CC/\uC368\uB9C8\uBA54\uB4DC \uBD84\uC11D \uBCF4\uACE0\uC11C.docx");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAE30\uC220\uC790\uB8CC/\uC2A4\uD399 \uC0AC\uC591\uC11C/BRF-RS232 Protocol KR.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAE30\uC220\uC790\uB8CC/\uC2A4\uD399 \uC0AC\uC591\uC11C/BRF 2\uCC44\uB110 \uC0AC\uC591\uC11C.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uAE30\uC220\uC790\uB8CC/\uCD08\uC74C\uD30C\uC790\uADF9\uAE30 \uAE30\uC220\uBB38\uC11C.pdf");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/PinMap/esp32_pinout.jpg");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/DWIN/DWIN_SDCARD_FORMATTER.txt");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/PCB/\uD68C\uB85C\uB3C4.png");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/Driver Tools/CP210x_Windows_Drivers.zip");
		writeFile("\uAC1C\uBC1C\uC790\uB8CC/\uD38C\uC6E8\uC5B4/ESPtoMELAUHF\uBC31\uC5C5/1. DWIN-ATmega-ESP-\uC2DC\uB9AC\uC5BC \uD1B5\uC2E0 \uD14C\uC2A4\uD2B8/MELAUHF_To_ESP32_C5_complete.ino");
		writeFile("\uBC15\uC8FC\uD55C/\uC544\uBC14\uC2A4 \uC790\uB8CC/source/hi-aba/src/main.c");

		return new AvaAiWorkspaceService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			workspaceRoot.toString(),
			"AVA_AI_Workspace",
			workspaceRoot.resolve("ChatUploads").toString()
		);
	}

	private AvaAiWorkspaceService serviceForNasRoot(Path nasRoot) {
		return new AvaAiWorkspaceService(
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			null,
			nasRoot.toString(),
			"AVA_AI_Workspace",
			nasRoot.resolve("ChatUploads").toString()
		);
	}

	private ChatMessageEntity sentAttachment(
		String roomCode,
		UUID senderId,
		String senderName,
		String fileName,
		String contentType,
		long size,
		Instant sentAt
	) throws Exception {
		ChatMessageEntity message = ChatMessageEntity.attachment(
			roomCode,
			senderId,
			senderName,
			fileName,
			contentType,
			size,
			workspaceRoot.resolve("ChatUploads").resolve(roomCode).resolve(fileName).toString(),
			"test-group"
		);
		Field sentAtField = ChatMessageEntity.class.getDeclaredField("sentAt");
		sentAtField.setAccessible(true);
		sentAtField.set(message, sentAt);
		return message;
	}

	private UserProfileResponse profile(UUID id, String email, String name) {
		return new UserProfileResponse(
			id,
			email,
			name,
			name,
			name,
			null,
			email,
			null,
			UserRole.USER,
			"ABBA-S",
			"사원",
			"연구소",
			null,
			"online",
			"#6B7CFF",
			"",
			"",
			"",
			"",
			false
		);
	}

	private void writeFile(String relativePath) throws Exception {
		Path target = workspaceRoot;
		for (String part : relativePath.split("/")) {
			target = target.resolve(part);
		}
		Files.createDirectories(target.getParent());
		Files.writeString(target, "test");
	}

	private record PromptCase(String prompt, String expectedPathFragment) {
	}
}
