package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;

class AvaAiEmbeddingServiceTest {

	@Test
	void localHashEmbeddingsArePersistableAndComparable() {
		AvaAiEmbeddingService service = new AvaAiEmbeddingService(
			new ObjectMapper(),
			"http://127.0.0.1:1/v1",
			"",
			128,
			false,
			5
		);

		float[] inventoryApp = service.embed("재고앱 개발 Notion 개발 진행사항 예정");
		float[] inventoryAppAgain = service.decode(service.encode(inventoryApp));
		float[] lunchTopic = service.embed("점심 메뉴와 식당 추천");

		assertEquals("local-hash-v1-128", service.modelKey());
		assertEquals(inventoryApp.length, inventoryAppAgain.length);
		assertTrue(service.cosine(inventoryApp, inventoryAppAgain) > 0.99);
		assertTrue(service.cosine(inventoryApp, lunchTopic) < 0.95);
	}
}
