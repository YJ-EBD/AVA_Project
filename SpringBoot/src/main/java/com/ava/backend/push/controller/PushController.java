package com.ava.backend.push.controller;

import java.time.Instant;
import java.util.List;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.push.dto.MobilePushDeviceHeartbeatRequest;
import com.ava.backend.push.dto.MobilePushDeviceHeartbeatResponse;
import com.ava.backend.push.dto.MobilePushEventResponse;
import com.ava.backend.push.service.MobilePushService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/push")
public class PushController {

	private final MobilePushService mobilePushService;

	public PushController(MobilePushService mobilePushService) {
		this.mobilePushService = mobilePushService;
	}

	@GetMapping("/events")
	public List<MobilePushEventResponse> events(
		@RequestParam(value = "after", required = false) Instant after,
		@RequestParam(value = "limit", required = false, defaultValue = "50") int limit,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return mobilePushService.backlog(principal, after, limit);
	}

	@PostMapping("/devices/heartbeat")
	public MobilePushDeviceHeartbeatResponse heartbeat(
		@Valid @RequestBody MobilePushDeviceHeartbeatRequest request,
		@AuthenticationPrincipal AuthPrincipal principal
	) {
		return new MobilePushDeviceHeartbeatResponse(true, "ava-websocket");
	}
}
