import 'package:ava_flutter/src/features/ai/data/ava_ai_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses AVA AI calendar workspace payload', () {
    final workspace = AvaAiCalendarWorkspaceDto.fromJson({
      'handled': true,
      'mutation': true,
      'mode': 'created',
      'status': '일정을 생성했습니다.',
      'selectedEventId': 'event-1',
      'summary': {
        'title': '일정 상세',
        'rangeStart': '2026-06-10T00:00:00Z',
        'rangeEnd': '2026-06-11T00:00:00Z',
        'totalCount': 1,
        'countsByStatus': {'SCHEDULED': 1},
      },
      'events': [
        {
          'id': 'event-1',
          'title': '재고앱 개발',
          'startAt': '2026-06-10T06:00:00Z',
          'endAt': '2026-06-10T07:00:00Z',
          'allDay': false,
          'status': 'SCHEDULED',
          'statusLabel': '예정',
          'categoryName': '개발 일정',
          'teamId': 'development',
          'teamLabel': '개발팀',
          'importance': 'HIGH',
          'importanceLabel': '중요',
          'color': '#4F7CFF',
          'hasAzoom': true,
          'hasChat': false,
          'hasFiles': true,
          'hasNotion': false,
        },
      ],
    });

    expect(workspace.hasSignal, isTrue);
    expect(workspace.selectedEvent()?.title, '재고앱 개발');
    expect(workspace.selectedEvent()?.teamLabel, '개발팀');
    expect(workspace.selectedEvent()?.importanceLabel, '중요');
    expect(workspace.summary?.countsByStatus['SCHEDULED'], 1);
    expect(workspace.toJson()['mode'], 'created');
  });
}
