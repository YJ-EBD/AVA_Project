package com.ava.backend.user.controller;

import java.util.List;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.auth.security.AuthPrincipal;
import com.ava.backend.user.dto.ChatFolderOrderRequest;
import com.ava.backend.user.dto.ChatFolderResponse;
import com.ava.backend.user.dto.ChatFolderSettingsRequest;
import com.ava.backend.user.dto.CompanyBlockRequest;
import com.ava.backend.user.dto.CompanyEmployeeRequest;
import com.ava.backend.user.dto.PresenceRequest;
import com.ava.backend.user.dto.ProfileUpdateRequest;
import com.ava.backend.user.dto.QuietChatRoomsRequest;
import com.ava.backend.user.dto.UserProfileResponse;
import com.ava.backend.user.repository.UserAccountRepository;
import com.ava.backend.user.service.ChatFolderSettingsService;
import com.ava.backend.user.service.UserService;

@RestController
@RequestMapping("/api/users")
public class UserController {

	private final UserAccountRepository accountRepository;
	private final UserService userService;
	private final ChatFolderSettingsService chatFolderSettingsService;

	public UserController(
		UserAccountRepository accountRepository,
		UserService userService,
		ChatFolderSettingsService chatFolderSettingsService
	) {
		this.accountRepository = accountRepository;
		this.userService = userService;
		this.chatFolderSettingsService = chatFolderSettingsService;
	}

	@GetMapping("/me")
	public UserProfileResponse me(@AuthenticationPrincipal AuthPrincipal principal) {
		var account = accountRepository.findById(principal.userId())
			.orElseThrow(() -> new IllegalArgumentException("계정을 찾을 수 없습니다."));
		return userService.profile(account);
	}

	@PutMapping("/me/presence")
	public UserProfileResponse presence(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody PresenceRequest request
	) {
		return userService.updatePresence(principal.userId(), request.status());
	}

	@PutMapping("/me/profile")
	public UserProfileResponse updateProfile(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody ProfileUpdateRequest request
	) {
		return userService.updateProfile(principal.userId(), request);
	}

	@GetMapping("/me/chat-folders")
	public List<ChatFolderResponse> chatFolders(@AuthenticationPrincipal AuthPrincipal principal) {
		return chatFolderSettingsService.folders(principal);
	}

	@PutMapping("/me/chat-folders")
	public List<ChatFolderResponse> saveChatFolders(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody ChatFolderSettingsRequest request
	) {
		return chatFolderSettingsService.saveFolders(principal, request);
	}

	@GetMapping("/me/chat-folder-order")
	public List<String> chatFolderOrder(@AuthenticationPrincipal AuthPrincipal principal) {
		return chatFolderSettingsService.filterOrder(principal);
	}

	@PutMapping("/me/chat-folder-order")
	public List<String> saveChatFolderOrder(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody ChatFolderOrderRequest request
	) {
		return chatFolderSettingsService.saveFilterOrder(principal, request);
	}

	@GetMapping("/me/quiet-chat-rooms")
	public List<String> quietChatRooms(@AuthenticationPrincipal AuthPrincipal principal) {
		return chatFolderSettingsService.quietRoomIds(principal);
	}

	@PutMapping("/me/quiet-chat-rooms")
	public List<String> saveQuietChatRooms(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody QuietChatRoomsRequest request
	) {
		return chatFolderSettingsService.saveQuietRoomIds(principal, request);
	}

	@GetMapping
	public List<UserProfileResponse> users(@AuthenticationPrincipal AuthPrincipal principal) {
		return userService.profiles(principal);
	}

	@GetMapping("/company/employees/search")
	public List<UserProfileResponse> searchEmployees(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestParam(required = false) String name,
		@RequestParam(required = false) String phoneNumber,
		@RequestParam(required = false) String email
	) {
		return userService.searchEmployees(principal, name, phoneNumber, email);
	}

	@PostMapping("/company/employees")
	public UserProfileResponse addCompanyEmployee(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody CompanyEmployeeRequest request
	) {
		return userService.addCompanyEmployee(principal, request);
	}

	@PostMapping("/company/blocked-employees")
	public UserProfileResponse blockEmployee(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody CompanyBlockRequest request
	) {
		return userService.blockEmployee(principal, request);
	}

	@DeleteMapping("/company/blocked-employees")
	public UserProfileResponse unblockEmployee(
		@AuthenticationPrincipal AuthPrincipal principal,
		@RequestBody CompanyBlockRequest request
	) {
		return userService.unblockEmployee(principal, request);
	}
}
