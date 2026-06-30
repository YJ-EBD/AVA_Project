import 'package:ava_flutter/src/features/push/application/mobile_push_controller.dart';
import 'package:ava_flutter/src/features/push/data/push_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MobilePushEventDto chatEvent({
    String? roomId,
    String? sourceId,
    Map<String, String> data = const {},
  }) {
    return MobilePushEventDto(
      id: 'event-1',
      type: 'chat_message',
      title: '전직원',
      body: '새 메시지',
      roomId: roomId,
      sourceId: sourceId,
      createdAt: DateTime.utc(2026),
      data: data,
    );
  }

  test('uses roomCode data when suppressing active chat push', () {
    final event = chatEvent(data: {'roomCode': 'company-all-staff'});

    expect(mobilePushEventRoomIdForTest(event), 'company-all-staff');
    expect(
      shouldSuppressActiveChatRoomPushForTest(
        event: event,
        activeChatRoomId: 'company-all-staff',
        lifecycleState: AppLifecycleState.resumed,
      ),
      isTrue,
    );
  });

  test('normalizes legacy chat push event types', () {
    expect(normalizeMobilePushEventTypeForTest('chat.message'), 'chat_message');
    expect(normalizeMobilePushEventTypeForTest('chat-message'), 'chat_message');
    expect(normalizeMobilePushEventTypeForTest('chat_message'), 'chat_message');
  });

  test('does not replay backlog notifications while app is foreground', () {
    final event = chatEvent(data: {'roomCode': 'company-all-staff'});

    expect(
      shouldDisplayBacklogPushForTest(
        event: event,
        lifecycleState: AppLifecycleState.resumed,
      ),
      isFalse,
    );
    expect(
      shouldDisplayBacklogPushForTest(
        event: event,
        lifecycleState: AppLifecycleState.paused,
      ),
      isTrue,
    );
  });

  test('does not suppress other rooms or background chat pushes', () {
    final event = chatEvent(data: {'roomCode': 'company-all-staff'});

    expect(
      shouldSuppressActiveChatRoomPushForTest(
        event: event,
        activeChatRoomId: 'other-room',
        lifecycleState: AppLifecycleState.resumed,
      ),
      isFalse,
    );
    expect(
      shouldSuppressActiveChatRoomPushForTest(
        event: event,
        activeChatRoomId: 'company-all-staff',
        lifecycleState: AppLifecycleState.paused,
      ),
      isFalse,
    );
  });
}
