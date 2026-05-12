package com.ava.backend.user.repository;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.user.entity.UserChatFolderSetting;

public interface UserChatFolderSettingRepository extends JpaRepository<UserChatFolderSetting, UUID> {
}
