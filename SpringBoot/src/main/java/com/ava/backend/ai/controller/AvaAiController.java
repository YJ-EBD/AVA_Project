package com.ava.backend.ai.controller;

import java.util.List;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.ai.dto.AvaAiChatResponse;
import com.ava.backend.ai.dto.AvaAiMessageRequest;
import com.ava.backend.ai.dto.AvaAiMessageResponse;
import com.ava.backend.ai.service.AvaAiService;
import com.ava.backend.auth.security.AuthPrincipal;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/ai")
public class AvaAiController {

	private final AvaAiService avaAiService;

	public AvaAiController(AvaAiService avaAiService) {
		this.avaAiService = avaAiService;
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
}
