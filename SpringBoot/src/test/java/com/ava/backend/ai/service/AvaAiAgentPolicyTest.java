package com.ava.backend.ai.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class AvaAiAgentPolicyTest {

	@Test
	void detectsCodexStyleWorkFrames() {
		AvaAiAgentPolicy.AgentFrame writeFrame = AvaAiAgentPolicy.inspect(
			"노션 연구소 페이지의 개발 진행사항에 AVA_stock 예정으로 추가해줘"
		);
		assertTrue(writeFrame.workRequest());
		assertTrue(writeFrame.toolRelevant());
		assertTrue(writeFrame.mutationIntent());
		assertTrue(writeFrame.requiresVerification());

		AvaAiAgentPolicy.AgentFrame correctionFrame = AvaAiAgentPolicy.inspect(
			"방금 한거 실제 노션에 없는데? 말귀 못알아 들은거 아니야?"
		);
		assertTrue(correctionFrame.correctionIntent());
		assertTrue(correctionFrame.continuationIntent());
		assertTrue(correctionFrame.requiresVerification());

		String contract = AvaAiAgentPolicy.contract(writeFrame);
		assertTrue(contract.contains("understand goal"));
		assertTrue(contract.contains("verify the result"));
	}

	@Test
	void runsAtLeastOneHundredMillionAgentPolicyChecks() {
		String[] prompts = {
			"노션 연구소 페이지의 개발 진행사항에 AVA_stock 예정으로 추가해줘",
			"방금 추가한거 어디에 추가한거야?",
			"그 말이 아니고 오늘부터 6월 10일까지 날짜로 넣으라는거야",
			"서버 재시작하고 헬스체크까지 확인해줘",
			"파일 찾아서 채팅방으로 전송해줘",
			"오늘 날씨 알려줘",
			"코드 수정하고 테스트 실행해줘",
			"그냥 설명만 해줘"
		};
		boolean[] expectedWork = {true, true, true, true, true, true, true, false};
		boolean[] expectedMutation = {true, false, false, true, true, false, true, false};
		boolean[] expectedCorrection = {false, false, true, false, false, false, false, false};
		boolean[] expectedVerification = {true, true, true, true, true, true, true, false};

		long checks = 0;
		long failures = 0;
		for (int index = 0; index < 100_000_000; index++) {
			int promptIndex = index & 7;
			AvaAiAgentPolicy.AgentFrame frame = AvaAiAgentPolicy.inspect(prompts[promptIndex]);
			if (frame.workRequest() != expectedWork[promptIndex]) {
				failures++;
			}
			if (frame.mutationIntent() != expectedMutation[promptIndex]) {
				failures++;
			}
			if (frame.correctionIntent() != expectedCorrection[promptIndex]) {
				failures++;
			}
			if (frame.requiresVerification() != expectedVerification[promptIndex]) {
				failures++;
			}
			checks++;
		}

		assertEquals(100_000_000, checks);
		assertEquals(0, failures);
	}
}
