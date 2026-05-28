import 'package:ava_flutter/src/features/calendar/domain/calendar_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CalendarEvent event() {
    return CalendarEvent(
      id: 'event-1',
      title: '수정 테스트',
      startAt: DateTime.utc(2026, 6, 1, 1),
      endAt: DateTime.utc(2026, 6, 1, 2),
    );
  }

  test('create request omits empty relationship collections', () {
    final data = event().toRequest();

    expect(data.containsKey('attendees'), isFalse);
    expect(data.containsKey('reminders'), isFalse);
    expect(data.containsKey('files'), isFalse);
    expect(data.containsKey('notionLinks'), isFalse);
    expect(data.containsKey('chatLinks'), isFalse);
    expect(data.containsKey('azoomLinks'), isFalse);
  });

  test('update request includes empty relationship collections for clearing', () {
    final data = event().toRequest(includeEmptyCollections: true);

    expect(data['attendees'], isEmpty);
    expect(data['reminders'], isEmpty);
    expect(data['files'], isEmpty);
    expect(data['notionLinks'], isEmpty);
    expect(data['chatLinks'], isEmpty);
    expect(data['azoomLinks'], isEmpty);
  });
}
