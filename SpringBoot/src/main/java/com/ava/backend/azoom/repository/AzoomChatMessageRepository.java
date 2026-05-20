package com.ava.backend.azoom.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomChatMessageEntity;

public interface AzoomChatMessageRepository extends JpaRepository<AzoomChatMessageEntity, UUID> {

	List<AzoomChatMessageEntity> findTop50ByCompanySlugAndChannelIdOrderBySentAtDesc(
		String companySlug,
		String channelId
	);

	List<AzoomChatMessageEntity> findTop200ByCompanySlugOrderBySentAtDesc(String companySlug);
}
