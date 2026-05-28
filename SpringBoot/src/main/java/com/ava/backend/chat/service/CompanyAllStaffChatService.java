package com.ava.backend.chat.service;

import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.ava.backend.chat.entity.ChatRoomEntity;
import com.ava.backend.chat.entity.ChatRoomMemberEntity;
import com.ava.backend.chat.entity.ChatRoomType;
import com.ava.backend.chat.repository.ChatRoomMemberRepository;
import com.ava.backend.chat.repository.ChatRoomRepository;
import com.ava.backend.company.CompanyScopeService;
import com.ava.backend.user.entity.UserAccount;
import com.ava.backend.user.entity.UserProfile;
import com.ava.backend.user.repository.UserProfileRepository;

@Service
public class CompanyAllStaffChatService {

	public static final String ROOM_TITLE = "\uC804\uC9C1\uC6D0";
	private static final String ROOM_CODE_PREFIX = "company-all-staff-";

	private final ChatRoomRepository roomRepository;
	private final ChatRoomMemberRepository memberRepository;
	private final UserProfileRepository profileRepository;
	private final CompanyScopeService companyScopeService;

	public CompanyAllStaffChatService(
		ChatRoomRepository roomRepository,
		ChatRoomMemberRepository memberRepository,
		UserProfileRepository profileRepository,
		CompanyScopeService companyScopeService
	) {
		this.roomRepository = roomRepository;
		this.memberRepository = memberRepository;
		this.profileRepository = profileRepository;
		this.companyScopeService = companyScopeService;
	}

	@Transactional
	public void ensureKnownCompanyRoomsAndMemberships() {
		for (String companyName : companyScopeService.availableCompanies()) {
			syncApprovedMembers(companyName);
		}
	}

	@Transactional
	public void syncMembershipForAccount(UserAccount account) {
		if (account == null) {
			return;
		}
		String companyName = profileRepository.findByAccountId(account.getId())
			.map(UserProfile::getCompanyName)
			.map(companyScopeService::normalizeCompany)
			.orElse(CompanyScopeService.DEFAULT_COMPANY);
		syncApprovedMembers(companyName);
	}

	@Transactional
	public void syncApprovedMembers(String companyName) {
		String normalizedCompany = companyScopeService.normalizeCompany(companyName);
		ChatRoomEntity room = ensureRoom(normalizedCompany);
		Set<UUID> approvedAccountIds = profileRepository.findByCompanyNameIgnoreCase(normalizedCompany).stream()
			.map(UserProfile::getAccount)
			.filter(UserAccount::isEnabled)
			.map(UserAccount::getId)
			.collect(Collectors.toSet());

		for (UserProfile profile : profileRepository.findByCompanyNameIgnoreCase(normalizedCompany)) {
			UserAccount account = profile.getAccount();
			if (account.isEnabled()) {
				ensureMember(room, account);
			}
		}
		for (ChatRoomMemberEntity member : memberRepository.findByRoomCode(room.getCode())) {
			if (!approvedAccountIds.contains(member.getAccount().getId())) {
				memberRepository.delete(member);
			}
		}
	}

	public boolean isAllStaffRoom(ChatRoomEntity room) {
		return room != null && isAllStaffRoomCode(room.getCode());
	}

	public boolean isAllStaffRoomCode(String roomCode) {
		return roomCode != null && roomCode.startsWith(ROOM_CODE_PREFIX);
	}

	public String roomCodeFor(String companyName) {
		return ROOM_CODE_PREFIX + companySlug(companyScopeService.normalizeCompany(companyName));
	}

	private ChatRoomEntity ensureRoom(String companyName) {
		String normalizedCompany = companyScopeService.normalizeCompany(companyName);
		String roomCode = roomCodeFor(normalizedCompany);
		ChatRoomEntity room = roomRepository.findByCode(roomCode)
			.orElseGet(() -> new ChatRoomEntity(
				roomCode,
				ROOM_TITLE,
				ChatRoomType.GROUP,
				true,
				""
			));
		room.setCompanyName(normalizedCompany);
		room.setPinnedDefault(true);
		return roomRepository.save(room);
	}

	private void ensureMember(ChatRoomEntity room, UserAccount account) {
		if (!memberRepository.existsByRoomCodeAndAccountId(room.getCode(), account.getId())) {
			memberRepository.save(new ChatRoomMemberEntity(room, account));
		}
	}

	private String companySlug(String companyName) {
		String slug = companyName.toLowerCase(java.util.Locale.ROOT)
			.replaceAll("[^a-z0-9]+", "-")
			.replaceAll("(^-+|-+$)", "");
		return slug.isBlank() ? "company" : slug;
	}
}
