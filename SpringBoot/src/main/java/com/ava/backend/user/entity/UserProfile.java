package com.ava.backend.user.entity;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "user_profiles")
public class UserProfile {

	@Id
	private UUID id;

	@OneToOne(fetch = FetchType.LAZY, optional = false)
	@JoinColumn(name = "account_id", nullable = false, unique = true)
	private UserAccount account;

	@Column(nullable = false, length = 80)
	private String department;

	@Column(length = 80)
	private String companyName = "ABBA-S";

	@Column(length = 80)
	private String position = "\uC0AC\uC6D0";

	@Column(length = 80)
	private String nickname;

	@Column(length = 40)
	private String phoneNumber;

	private LocalDate birthDate;

	@Column(nullable = false, length = 32)
	private String status;

	private Instant presenceUpdatedAt;

	@Column(nullable = false, length = 12)
	private String avatarColor;

	@Column(length = 120)
	private String statusMessage;

	@Column(columnDefinition = "text")
	private String avatarImageUrl;

	@Column(length = 12)
	private String profileBackgroundColor;

	@Column(columnDefinition = "text")
	private String profileBackgroundImageUrl;

	protected UserProfile() {
	}

	public UserProfile(UserAccount account, String department, String status, String avatarColor) {
		this(account, department, account.getDisplayName(), null, null, status, avatarColor);
	}

	public UserProfile(
		UserAccount account,
		String department,
		String nickname,
		String phoneNumber,
		LocalDate birthDate,
		String status,
		String avatarColor
	) {
		this.id = UUID.randomUUID();
		this.account = account;
		this.department = department;
		this.nickname = nickname;
		this.phoneNumber = phoneNumber;
		this.birthDate = birthDate;
		this.status = status;
		this.avatarColor = avatarColor;
		this.statusMessage = "";
		this.profileBackgroundColor = defaultProfileBackgroundColor(account.getId());
	}

	public UUID getId() {
		return id;
	}

	public UserAccount getAccount() {
		return account;
	}

	public String getDepartment() {
		return department;
	}

	public String getCompanyName() {
		return companyName;
	}

	public String getPosition() {
		return position;
	}

	public String getNickname() {
		return nickname;
	}

	public String getPhoneNumber() {
		return phoneNumber;
	}

	public LocalDate getBirthDate() {
		return birthDate;
	}

	public String getStatus() {
		return status;
	}

	public Instant getPresenceUpdatedAt() {
		return presenceUpdatedAt;
	}

	public String getAvatarColor() {
		return avatarColor;
	}

	public String getStatusMessage() {
		return statusMessage;
	}

	public String getAvatarImageUrl() {
		return avatarImageUrl;
	}

	public String getProfileBackgroundColor() {
		return profileBackgroundColor;
	}

	public String getProfileBackgroundImageUrl() {
		return profileBackgroundImageUrl;
	}

	public void setDepartment(String department) {
		this.department = department;
	}

	public void setCompanyName(String companyName) {
		this.companyName = companyName;
	}

	public void setPosition(String position) {
		this.position = position;
	}

	public void setNickname(String nickname) {
		this.nickname = nickname;
	}

	public void setPhoneNumber(String phoneNumber) {
		this.phoneNumber = phoneNumber;
	}

	public void setBirthDate(LocalDate birthDate) {
		this.birthDate = birthDate;
	}

	public void setStatus(String status) {
		this.status = status;
	}

	public void setPresenceUpdatedAt(Instant presenceUpdatedAt) {
		this.presenceUpdatedAt = presenceUpdatedAt;
	}

	public void setAvatarColor(String avatarColor) {
		this.avatarColor = avatarColor;
	}

	public void setStatusMessage(String statusMessage) {
		this.statusMessage = statusMessage;
	}

	public void setAvatarImageUrl(String avatarImageUrl) {
		this.avatarImageUrl = avatarImageUrl;
	}

	public void setProfileBackgroundColor(String profileBackgroundColor) {
		this.profileBackgroundColor = profileBackgroundColor;
	}

	public void setProfileBackgroundImageUrl(String profileBackgroundImageUrl) {
		this.profileBackgroundImageUrl = profileBackgroundImageUrl;
	}

	private String defaultProfileBackgroundColor(UUID accountId) {
		String[] colors = {
			"#7AA06A",
			"#8BA6C9",
			"#9C8E82",
			"#6D91A8",
			"#A88976",
			"#7986A8",
			"#7A9A90",
			"#A0A76F"
		};
		int index = Math.floorMod(accountId.hashCode(), colors.length);
		return colors[index];
	}
}
