package com.ava.backend.azoom.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.azoom.entity.AzoomMeetingUtteranceEntity;

public interface AzoomMeetingUtteranceRepository extends JpaRepository<AzoomMeetingUtteranceEntity, UUID> {
	List<AzoomMeetingUtteranceEntity> findByTranscript_IdOrderBySequenceNoAsc(UUID transcriptId);

	long countByTranscript_Id(UUID transcriptId);
}
