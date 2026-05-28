package com.ava.backend.ai.service;

import java.util.Locale;

final class AvaAiAgentPolicy {

	private static final String[] TOOL_TERMS = {
		"notion", "노션", "페이지", "개발 진행사항", "개발진행사항", "파일", "폴더", "작업공간", "nas",
		"서버", "백엔드", "재시작", "빌드", "테스트", "검증", "검색", "찾아", "채팅", "회의록", "로그",
		"날씨", "연결", "승인", "최신", "최근", "코드", "분석", "점검", "배포", "릴리즈", "업데이트",
		"마이그레이션", "플러터", "flutter", "dart", "api", "db", "database", "server",
		"복구", "재개", "체크포인트", "자율", "장기",
		"restart", "build", "test", "verify", "check", "file", "folder", "workspace", "log", "weather",
		"release", "deploy", "migration", "latest"
	};
	private static final String[] MUTATION_TERMS = {
		"추가", "작성", "등록", "생성", "수정", "삭제", "전송", "업로드", "반영", "재시작", "고쳐",
		"만들", "바꿔", "실행", "분석", "점검", "배포", "릴리즈", "마이그레이션", "add", "create",
		"복구", "재개",
		"write", "update", "delete", "remove", "send", "upload", "restart", "run", "fix", "change",
		"apply", "analyze", "deploy", "release", "migrate"
	};
	private static final String[] CORRECTION_TERMS = {
		"아니고", "아니라", "그 말이 아니", "게 아니라", "말고", "말귀", "못알아", "못 알아", "못했다",
		"못 했다", "왜", "이상", "틀렸", "오류", "실패", "누락", "실제로", "없는데", "안됐", "안 됐",
		"안된다", "안 된다", "안떠", "안 떠", "where did", "wrong", "error", "not there", "didn't",
		"doesn't"
	};
	private static final String[] CONTINUATION_TERMS = {
		"이어서", "계속", "방금", "아까", "그거", "그걸", "그 말", "이전", "다시", "체크포인트", "재개", "continue",
		"previous", "last", "that"
	};

	private AvaAiAgentPolicy() {
	}

	static AgentFrame inspect(String prompt) {
		String normalized = normalize(prompt);
		boolean continuation = containsAny(normalized, CONTINUATION_TERMS);
		boolean correction = containsAny(normalized, CORRECTION_TERMS);
		boolean toolRelevant = containsAny(normalized, TOOL_TERMS);
		boolean mutation = containsAny(normalized, MUTATION_TERMS)
			&& !(continuation && !hasMutationDirective(normalized));
		boolean verification = toolRelevant || mutation || correction || continuation
			|| normalized.contains("확인") || normalized.contains("완료");
		boolean workRequest = toolRelevant || mutation || correction || continuation || normalized.contains("진행");
		String mode;
		if (correction) {
			mode = "correction-recovery";
		} else if (mutation) {
			mode = "tool-plan-act-verify";
		} else if (toolRelevant) {
			mode = "tool-read-verify";
		} else if (continuation) {
			mode = "conversation-continuation";
		} else {
			mode = "direct-conversation";
		}
		return new AgentFrame(mode, workRequest, toolRelevant, mutation, correction, continuation, verification);
	}

	static String contract(AgentFrame frame) {
		StringBuilder builder = new StringBuilder();
		builder.append("[AGENT WORK CONTRACT]\n");
		builder.append("mode: ").append(frame.mode()).append('\n');
		builder.append("workRequest: ").append(frame.workRequest()).append('\n');
		builder.append("toolRelevant: ").append(frame.toolRelevant()).append('\n');
		builder.append("mutationIntent: ").append(frame.mutationIntent()).append('\n');
		builder.append("correctionIntent: ").append(frame.correctionIntent()).append('\n');
		builder.append("continuationIntent: ").append(frame.continuationIntent()).append('\n');
		builder.append("requiresVerification: ").append(frame.requiresVerification()).append('\n');
		builder.append("rules:\n");
		builder.append("- Treat the user's latest message as part of the same ongoing task unless it clearly starts a new topic.\n");
		builder.append("- For work requests, follow: understand goal, inspect current state, plan, act with an available tool/API, verify the result, report only verified facts.\n");
		builder.append("- If a tool/API is unavailable, say that precisely and do not claim completion.\n");
		builder.append("- For corrections, first reconcile the latest correction with recent tool results before doing any new write.\n");
		builder.append("- For writes or destructive actions, show target/value/impact first and use the approval path when the tool requires it.\n");
		builder.append("- For autonomous tasks, keep a durable task state, run the smallest safe tool action, verify after every action, and retry only with safe read-only checks when verification fails.\n");
		builder.append("- When a tool fails but read-only recovery evidence is collected, report it as recovered/partial work with the original failure preserved.\n");
		builder.append("- Before continuing a long task, read recent agent task state and resume from the last non-terminal checkpoint instead of starting over.\n");
		builder.append("- Never create a different page/database/file just because the requested target is ambiguous; inspect or ask before creating a new target.\n");
		builder.append("- Never answer a work request with '잠시만 기다려 주세요', '시도하겠습니다', '확인하겠습니다', or any future promise unless a tool/API has already been invoked in this same turn.\n");
		builder.append("- Every work answer must be one of: verified result, approval/ambiguity question with exact target fields, or explicit unavailable reason. No acknowledgement-only answers.\n");
		builder.append("- Treat service errors, missing final state, and user reports of absence as recovery tasks, not as new unrelated conversations.\n");
		builder.append("- Keep Korean answers concise, but include the concrete target, result, and remaining risk.\n");
		return builder.toString();
	}

	static String compactContract(AgentFrame frame) {
		StringBuilder builder = new StringBuilder();
		builder.append("[AGENT WORK CONTRACT - COMPACT]\n");
		builder.append("mode=").append(frame.mode())
			.append(", work=").append(frame.workRequest())
			.append(", tool=").append(frame.toolRelevant())
			.append(", mutation=").append(frame.mutationIntent())
			.append(", correction=").append(frame.correctionIntent())
			.append(", continuation=").append(frame.continuationIntent())
			.append(", verify=").append(frame.requiresVerification())
			.append('\n');
		builder.append("rules: continue the active task, use verified tool/API state, do not claim unverified writes, never give wait/try/future-promise-only answers, ask/inspect when target is ambiguous, preserve failures, report recovered/partial work when safe recovery evidence exists.\n");
		return builder.toString();
	}

	private static boolean containsAny(String normalized, String[] terms) {
		for (String term : terms) {
			if (normalized.contains(term)) {
				return true;
			}
		}
		return false;
	}

	private static boolean hasMutationDirective(String normalized) {
		return normalized.contains("해줘")
			|| normalized.contains("해주세요")
			|| normalized.contains("해 주세요")
			|| normalized.contains("해라")
			|| normalized.contains("하세요")
			|| normalized.contains("실행")
			|| normalized.contains("분석")
			|| normalized.contains("점검")
			|| normalized.contains("진행")
			|| normalized.contains("고쳐")
			|| normalized.contains("바꿔")
			|| normalized.contains("배포")
			|| normalized.contains("릴리즈")
			|| normalized.contains("마이그레이션")
			|| normalized.contains("복구")
			|| normalized.contains("재개")
			|| normalized.contains("삭제해")
			|| normalized.contains("추가해")
			|| normalized.contains("등록해")
			|| normalized.contains("작성해")
			|| normalized.contains("create")
			|| normalized.contains("write")
			|| normalized.contains("update")
			|| normalized.contains("delete")
			|| normalized.contains("remove")
			|| normalized.contains("run")
			|| normalized.contains("analyze")
			|| normalized.contains("fix")
			|| normalized.contains("deploy")
			|| normalized.contains("release")
			|| normalized.contains("migrate")
			|| normalized.contains("apply");
	}

	private static String normalize(String prompt) {
		return prompt == null ? "" : prompt.strip().toLowerCase(Locale.ROOT);
	}

	record AgentFrame(
		String mode,
		boolean workRequest,
		boolean toolRelevant,
		boolean mutationIntent,
		boolean correctionIntent,
		boolean continuationIntent,
		boolean requiresVerification
	) {
	}
}
