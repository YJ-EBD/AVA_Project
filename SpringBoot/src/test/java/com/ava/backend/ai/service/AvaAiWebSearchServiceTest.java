package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;

class AvaAiWebSearchServiceTest {

	private final AvaAiWebSearchService service = new AvaAiWebSearchService(
		new ObjectMapper(),
		true,
		5,
		3,
		12,
		"",
		""
	);

	@Test
	void doesNotTreatInternalWorkspaceFindPromptsAsWebSearch() {
		assertFalse(service.hasWebIntent("\uAC1C\uBC1C\uC548\uB4E4 \uCC3E\uC544\uC918"));
		assertFalse(service.hasWebIntent("\uAC1C\uBC1C\uC548 \uAC80\uC0C9\uD574\uC918"));
		assertFalse(service.hasWebIntent("\uD30C\uC77C \uCC3E\uC544\uC918"));
		assertFalse(service.hasWebIntent("\uBCF4\uACE0\uC11C \uAC80\uC0C9"));
		assertFalse(service.hasWebIntent("\uC544\uB450\uC774\uB178 \uC18C\uC2A4\uCF54\uB4DC \uAD00\uB828 \uD30C\uC77C\uB4E4 \uCC3E\uC544 \uC54C\uB824\uC918"));
		assertFalse(service.hasWebIntent(".ino\uD30C\uC77C\uB4E4 \uC5C6\uC5B4?"));
	}

	@Test
	void stillDetectsExplicitExternalWebSearchPrompts() {
		assertTrue(service.hasWebIntent("\uC778\uD130\uB137\uC5D0\uC11C \uC2AC\uB9AC\uD37C \uCC3E\uC544\uC918"));
		assertTrue(service.hasWebIntent("\uCFE0\uD321\uC5D0 \uC2AC\uB9AC\uD37C \uCC3E\uC544\uC918"));
		assertTrue(service.hasWebIntent("\uC624\uB298 \uB0A0\uC528 \uC54C\uB824\uC918"));
		assertTrue(service.hasWebIntent("latest flutter release"));
	}
}
