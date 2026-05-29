import 'package:ava_flutter/src/features/ai/data/ava_ai_api.dart';
import 'package:ava_flutter/src/features/ai/presentation/ava_ai_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'clears stale workspace cards when the latest workspace result is empty',
    () {
      const staleItems = [
        AvaAiWorkspaceItemDto(
          type: 'file',
          title: 'parts.h',
          subtitle: 'old unrelated NAS result',
          path: r'F:\제품 자료\parts.h',
          url: '',
          imageUrl: '',
          content: '',
          size: null,
          updatedAt: null,
          roomCode: '',
        ),
      ];

      final sanitized = sanitizeAvaAiWorkspaceItemsForStatus(
        '어제 채팅으로 보낸 파일 이력이 없습니다. 채팅 첨부 기록 기준으로 확인했습니다.',
        staleItems,
      );

      expect(sanitized, isEmpty);
    },
  );

  test('keeps valid previous workspace cards for non-empty result status', () {
    const items = [
      AvaAiWorkspaceItemDto(
        type: 'chat_file',
        title: 'Bereborn [Tron].zip',
        subtitle: '박주한 · 5월 29일 오전 12:06',
        path: '',
        url: '/api/chat/rooms/direct/attachments/file',
        imageUrl: '',
        content: '',
        size: 1250000,
        updatedAt: null,
        roomCode: 'direct',
      ),
    ];

    final sanitized = sanitizeAvaAiWorkspaceItemsForStatus(
      '최근 7일까지 넓혀 보낸 파일 1개를 찾았습니다.',
      items,
    );

    expect(sanitized, hasLength(1));
    expect(sanitized.first.title, 'Bereborn [Tron].zip');
  });
}
