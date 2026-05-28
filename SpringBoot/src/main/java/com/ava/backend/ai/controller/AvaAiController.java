package com.ava.backend.ai.controller;

import java.util.List;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.ava.backend.ai.dto.AvaAiChatResponse;
import com.ava.backend.ai.dto.AvaAiMessageRequest;
import com.ava.backend.ai.dto.AvaAiMessageResponse;
import com.ava.backend.ai.dto.AvaAiNotionCommandRequest;
import com.ava.backend.ai.dto.AvaAiNotionCommandResponse;
import com.ava.backend.ai.dto.AvaAiNotionPageResponse;
import com.ava.backend.ai.dto.AvaAiWorkspaceFileRequest;
import com.ava.backend.ai.dto.AvaAiWorkspaceItemResponse;
import com.ava.backend.ai.dto.AvaAiWorkspaceSendRequest;
import com.ava.backend.ai.service.AvaAiNotionService;
import com.ava.backend.ai.service.AvaAiService;
import com.ava.backend.ai.service.AvaAiWorkspaceService;
import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.calendar.CalendarAiCommandService;
import com.ava.backend.calendar.CalendarAiWorkspaceResponse;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/ai")
public class AvaAiController {

	private final AvaAiService avaAiService;
	private final AvaAiWorkspaceService workspaceService;
	private final AvaAiNotionService notionService;
	private final CalendarAiCommandService calendarAiCommandService;

	public AvaAiController(
		AvaAiService avaAiService,
		AvaAiWorkspaceService workspaceService,
		AvaAiNotionService notionService,
		CalendarAiCommandService calendarAiCommandService
	) {
		this.avaAiService = avaAiService;
		this.workspaceService = workspaceService;
		this.notionService = notionService;
		this.calendarAiCommandService = calendarAiCommandService;
	}

	@GetMapping("/messages")
	public List<AvaAiMessageResponse> messages(@AuthenticationPrincipal AuthPrincipal principal) {
		return avaAiService.history(principal);
	}

	@PostMapping("/messages")
	public AvaAiChatResponse send(
		@Valid @RequestBody AvaAiMessageRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return avaAiService.send(request, principal);
	}

	@PostMapping("/messages/reset")
	public void resetMessages(@AuthenticationPrincipal AuthPrincipal principal) {
		avaAiService.resetCurrentConversation(principal);
	}

	@GetMapping("/workspace/files")
	public List<AvaAiWorkspaceItemResponse> files(
		@RequestParam(value = "path", required = false) String path,
		@RequestParam(value = "query", required = false) String query,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		if (query != null && !query.isBlank()) {
			return workspaceService.searchFiles(query, path, principal);
		}
		return workspaceService.listFiles(path, principal);
	}

	@GetMapping("/workspace/files/content")
	public AvaAiWorkspaceItemResponse fileContent(
		@RequestParam("path") String path,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.readFile(path, principal);
	}

	@GetMapping("/workspace/files/preview")
	public ResponseEntity<Resource> filePreview(
		@RequestParam("path") String path,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AvaAiWorkspaceService.WorkspaceDownload download = workspaceService.previewFile(path, principal);
		return ResponseEntity.ok()
			.header(
				HttpHeaders.CONTENT_DISPOSITION,
				ContentDisposition.inline()
					.filename(download.fileName(), java.nio.charset.StandardCharsets.UTF_8)
					.build()
					.toString()
			)
			.contentType(MediaType.parseMediaType(download.contentType()))
			.contentLength(download.size())
			.body(download.resource());
	}

	@PostMapping("/workspace/files")
	public AvaAiWorkspaceItemResponse createFile(
		@Valid @RequestBody AvaAiWorkspaceFileRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.create(request, principal);
	}

	@PutMapping("/workspace/files")
	public AvaAiWorkspaceItemResponse updateFile(
		@Valid @RequestBody AvaAiWorkspaceFileRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.update(request, principal);
	}

	@DeleteMapping("/workspace/files")
	public AvaAiWorkspaceItemResponse deleteFile(
		@RequestParam("path") String path,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.delete(path, principal);
	}

	@PostMapping(
		value = "/workspace/uploads",
		consumes = MediaType.MULTIPART_FORM_DATA_VALUE
	)
	public List<AvaAiWorkspaceItemResponse> upload(
		@RequestParam("files") List<MultipartFile> files,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.upload(files, principal);
	}

	@PostMapping("/workspace/send-to-chat")
	public AvaAiWorkspaceService.SendResult sendToChat(
		@Valid @RequestBody AvaAiWorkspaceSendRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return workspaceService.sendToChat(request, principal);
	}

	@GetMapping("/calendar/workspace")
	public CalendarAiWorkspaceResponse calendarWorkspace(
		@RequestParam(value = "mode", required = false, defaultValue = "today") String mode,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return calendarAiCommandService.snapshot(mode, principal);
	}

	@GetMapping("/notion/search")
	public List<AvaAiNotionPageResponse> notionSearch(
		@RequestParam(value = "query", required = false) String query,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return notionService.search(query == null ? "" : query);
	}

	@GetMapping("/notion/pages/{id}")
	public AvaAiNotionPageResponse notionPage(
		@org.springframework.web.bind.annotation.PathVariable("id") String id,
		@RequestParam(value = "object", required = false, defaultValue = "page") String object,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return notionService.open(id, object);
	}

	@PostMapping("/notion/command")
	public AvaAiNotionCommandResponse notionCommand(
		@RequestBody AvaAiNotionCommandRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AvaAiNotionCommandResponse response = notionService.command(request, principal);
		recordNotionExchange(request, response, principal);
		return response;
	}

	@PostMapping(
		value = "/notion/uploads",
		consumes = MediaType.MULTIPART_FORM_DATA_VALUE
	)
	public AvaAiNotionCommandResponse notionUpload(
		@RequestParam("targetId") String targetId,
		@RequestParam("files") List<MultipartFile> files,
		@RequestParam(value = "approved", required = false, defaultValue = "false") boolean approved,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		AvaAiNotionCommandResponse response = notionService.upload(targetId, files, approved, principal);
		if (approved) {
			avaAiService.recordToolExchange(
				"Notion 파일 업로드: " + targetId,
				response.answer().isBlank() ? response.status() : response.answer(),
				response.executionMode(),
				principal
			);
		}
		return response;
	}

	private void recordNotionExchange(
		AvaAiNotionCommandRequest request,
		AvaAiNotionCommandResponse response,
		AuthPrincipal principal
	) {
		if (request == null || request.command() == null || request.command().isBlank()) {
			return;
		}
		String answer = response.answer().isBlank() ? response.status() : response.answer();
		if (response.requiresApproval() && !response.approvalDescription().isBlank()) {
			answer = answer + "\n" + response.approvalDescription();
		}
		avaAiService.recordToolExchange(
			request.command(),
			answer,
			response.executionMode(),
			principal
		);
	}
}
