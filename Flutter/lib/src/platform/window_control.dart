import 'package:flutter/services.dart';

class WindowControl {
  static const _channel = MethodChannel('ava/window');
  static Future<void> Function(String roomId, String content)? _replyHandler;
  static Future<void> Function(String action, String roomId)? _floatingHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _folderHandler;
  static Future<void> Function(String result)? _folderSubmenuHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _quietRoomsHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _multiLeaveRoomsHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _newChatHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _profileHandler;
  static Future<void> Function(String action, Map<String, Object?> arguments)?
  _employeeHandler;
  static Future<void> Function(bool active)? _fileDragHandler;
  static Future<void> Function(List<String> paths)? _fileDropHandler;
  static bool _methodHandlerConfigured = false;

  static void setNotificationReplyHandler(
    Future<void> Function(String roomId, String content)? handler,
  ) {
    _replyHandler = handler;
    _ensureMethodHandler();
  }

  static void setFloatingHandler(
    Future<void> Function(String action, String roomId)? handler,
  ) {
    _floatingHandler = handler;
    _ensureMethodHandler();
  }

  static void setProfilePopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _profileHandler = handler;
    _ensureMethodHandler();
  }

  static void setEmployeePopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _employeeHandler = handler;
    _ensureMethodHandler();
  }

  static void setFolderPopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _folderHandler = handler;
    _ensureMethodHandler();
  }

  static void setFolderSubmenuHandler(
    Future<void> Function(String result)? handler,
  ) {
    _folderSubmenuHandler = handler;
    _ensureMethodHandler();
  }

  static void setQuietRoomsPopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _quietRoomsHandler = handler;
    _ensureMethodHandler();
  }

  static void setMultiLeaveRoomsPopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _multiLeaveRoomsHandler = handler;
    _ensureMethodHandler();
  }

  static void setFileDropHandler({
    Future<void> Function(bool active)? onDragState,
    Future<void> Function(List<String> paths)? onDrop,
  }) {
    _fileDragHandler = onDragState;
    _fileDropHandler = onDrop;
    _ensureMethodHandler();
  }

  static void setNewChatPopupHandler(
    Future<void> Function(String action, Map<String, Object?> arguments)?
    handler,
  ) {
    _newChatHandler = handler;
    _ensureMethodHandler();
  }

  static Future<void> startDrag() async {
    await _invoke('startDrag');
  }

  static Future<void> minimize() async {
    await _invoke('minimize');
  }

  static Future<void> toggleMaximize() async {
    await _invoke('toggleMaximize');
  }

  static Future<void> close() async {
    await _invoke('close');
  }

  static Future<void> setWindowTitle(String title) async {
    await _invoke('setWindowTitle', {'title': title});
  }

  static Future<void> compactMessenger() async {
    await _invoke('compactMessenger');
  }

  static Future<void> expandMessenger() async {
    await _invoke('expandMessenger');
  }

  static Future<void> showMessengerWindow() async {
    await _invoke('showMessengerWindow');
  }

  static Future<void> openAzoomMessenger() async {
    await _invoke('openAzoomMessenger');
  }

  static Future<void> restoreMessengerFromAzoom() async {
    await _invoke('restoreMessengerFromAzoom');
  }

  static Future<void> setAzoomFullscreen(bool fullscreen) async {
    await _invoke('setAzoomFullscreen', {'fullscreen': fullscreen});
  }

  static Future<void> setMessengerOpacity(double opacity) async {
    await _invoke('setMessengerOpacity', {
      'opacity': opacity.clamp(0.18, 1).toDouble(),
    });
  }

  static Future<void> showProfilePopup({
    required bool isSelf,
    required String id,
    required String email,
    required String name,
    required String nickname,
    required String statusMessage,
    required String avatarImageUrl,
    required String avatarColor,
    required String backgroundColor,
    required String backgroundImageUrl,
  }) async {
    await _invoke('showProfilePopup', {
      'isSelf': isSelf,
      'id': id,
      'email': email,
      'name': name,
      'nickname': nickname,
      'statusMessage': statusMessage,
      'avatarImageUrl': avatarImageUrl,
      'avatarColor': avatarColor,
      'backgroundColor': backgroundColor,
      'backgroundImageUrl': backgroundImageUrl,
    });
  }

  static Future<void> showProfileEditPopup({
    required String id,
    required String email,
    required String name,
    required String nickname,
    required String statusMessage,
    required String avatarImageUrl,
    required String avatarColor,
  }) async {
    await _invoke('showProfileEditPopup', {
      'id': id,
      'email': email,
      'name': name,
      'nickname': nickname,
      'statusMessage': statusMessage,
      'avatarImageUrl': avatarImageUrl,
      'avatarColor': avatarColor,
    });
  }

  static Future<bool> showChatNotification({
    required String roomId,
    required String roomTitle,
    required String senderName,
    required String senderNickname,
    required String avatarColor,
    required String body,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('showChatNotification', {
        'roomId': roomId,
        'roomTitle': roomTitle,
        'senderName': senderName,
        'senderNickname': senderNickname,
        'avatarColor': avatarColor,
        'body': body,
      });
      return result ?? true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> showChatFloating({
    required String roomId,
    required String title,
    required String avatarColor,
    required bool isGroup,
    required bool isMuted,
    required int unreadCount,
  }) async {
    await _invoke('showChatFloating', {
      'roomId': roomId,
      'title': title,
      'avatarColor': avatarColor,
      'isGroup': isGroup,
      'isMuted': isMuted,
      'unreadCount': unreadCount,
    });
  }

  static Future<void> updateChatFloating({
    required String roomId,
    required String title,
    required String avatarColor,
    required bool isGroup,
    required bool isMuted,
    required int unreadCount,
  }) async {
    await _invoke('updateChatFloating', {
      'roomId': roomId,
      'title': title,
      'avatarColor': avatarColor,
      'isGroup': isGroup,
      'isMuted': isMuted,
      'unreadCount': unreadCount,
    });
  }

  static Future<void> closeChatFloating(String roomId) async {
    await _invoke('closeChatFloating', {'roomId': roomId});
  }

  static Future<void> closeAllChatFloatings() async {
    await _invoke('closeAllChatFloatings');
  }

  static Future<void> showFolderCreatePopup({
    required List<Map<String, Object?>> rooms,
    required List<String> initialRoomIds,
    String? initialName,
    String? initialIcon,
    bool isEdit = false,
  }) async {
    final arguments = <String, Object?>{
      'rooms': rooms,
      'initialRoomIds': initialRoomIds,
      'isEdit': isEdit,
    };
    if (initialName != null) {
      arguments['initialName'] = initialName;
    }
    if (initialIcon != null) {
      arguments['initialIcon'] = initialIcon;
    }
    await _invoke('showFolderCreatePopup', arguments);
  }

  static Future<void> showEmployeeAddPopup() async {
    await _invoke('showEmployeeAddPopup');
  }

  static Future<void> updateEmployeeAddPopup({
    required String scope,
    required bool hasResult,
    String? id,
    String? email,
    String? name,
    String? nickname,
    String? avatarColor,
    String? avatarImageUrl,
    bool isAlreadyAdded = false,
    bool blocked = false,
  }) async {
    final arguments = <String, Object?>{
      'scope': scope,
      'hasResult': hasResult,
      'isAlreadyAdded': isAlreadyAdded,
      'blocked': blocked,
    };
    if (id != null) {
      arguments['id'] = id;
    }
    if (email != null) {
      arguments['email'] = email;
    }
    if (name != null) {
      arguments['name'] = name;
    }
    if (nickname != null) {
      arguments['nickname'] = nickname;
    }
    if (avatarColor != null) {
      arguments['avatarColor'] = avatarColor;
    }
    if (avatarImageUrl != null) {
      arguments['avatarImageUrl'] = avatarImageUrl;
    }
    await _invoke('updateEmployeeAddPopup', arguments);
  }

  static Future<void> closeEmployeeAddPopup() async {
    await _invoke('closeEmployeeAddPopup');
  }

  static Future<void> showFolderManagePopup({
    required List<Map<String, Object?>> folders,
    required int unreadCount,
    required bool hasFavorite,
  }) async {
    await _invoke('showFolderManagePopup', {
      'folders': folders,
      'unreadCount': unreadCount,
      'hasFavorite': hasFavorite,
    });
  }

  static Future<String?> showFolderSubmenu({
    required List<Map<String, Object?>> folders,
    required double x,
    required double y,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('showFolderSubmenu', {
        'folders': folders,
        'x': x,
        'y': y,
      });
      return result?.isEmpty ?? true ? null : result;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> showNativeMenu({
    required List<Map<String, Object?>> items,
    required double x,
    required double y,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('showNativeMenu', {
        'items': items,
        'x': x,
        'y': y,
      });
      return result?.isEmpty ?? true ? null : result;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> showFolderSubmenuPopup({
    required List<Map<String, Object?>> folders,
    required double x,
    required double y,
    required double parentWidth,
    required double parentHeight,
  }) async {
    await _invoke('showFolderSubmenuPopup', {
      'folders': folders,
      'x': x,
      'y': y,
      'parentWidth': parentWidth,
      'parentHeight': parentHeight,
    });
  }

  static Future<void> closeFolderSubmenuPopup() async {
    await _invoke('closeFolderSubmenuPopup');
  }

  static Future<void> showQuietRoomsPopup({
    required List<Map<String, Object?>> rooms,
  }) async {
    await _invoke('showQuietRoomsPopup', {'rooms': rooms});
  }

  static Future<void> closeQuietRoomsPopup() async {
    await _invoke('closeQuietRoomsPopup');
  }

  static Future<void> showMultiLeaveRoomsPopup({
    required List<Map<String, Object?>> rooms,
  }) async {
    await _invoke('showMultiLeaveRoomsPopup', {'rooms': rooms});
  }

  static Future<void> closeMultiLeaveRoomsPopup() async {
    await _invoke('closeMultiLeaveRoomsPopup');
  }

  static Future<void> showImageViewerPopup({
    required List<Map<String, Object?>> images,
    required int initialIndex,
    required String sender,
    required String date,
  }) async {
    await _invoke('showImageViewerPopup', {
      'images': images,
      'initialIndex': initialIndex,
      'sender': sender,
      'date': date,
    });
  }

  static Future<void> showVideoViewerPopup({
    required String path,
    required String name,
    required String sender,
    required String date,
  }) async {
    await _invoke('showVideoViewerPopup', {
      'path': path,
      'name': name,
      'sender': sender,
      'date': date,
    });
  }

  static Future<void> showNewChatPopup({
    required List<Map<String, Object?>> users,
  }) async {
    await _invoke('showNewChatPopup', {'users': users});
  }

  static Future<void> closeNewChatPopup() async {
    await _invoke('closeNewChatPopup');
  }

  static Future<bool> isAvaForeground() async {
    try {
      return await _channel.invokeMethod<bool>('isAvaForeground') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static void _ensureMethodHandler() {
    if (_methodHandlerConfigured) {
      return;
    }
    _methodHandlerConfigured = true;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?)?.cast<Object?, Object?>();
      if (call.method == 'notificationReply') {
        final roomId = args?['roomId'] as String? ?? '';
        final content = args?['content'] as String? ?? '';
        final currentHandler = _replyHandler;
        if (currentHandler != null && roomId.isNotEmpty && content.isNotEmpty) {
          await currentHandler(roomId, content);
        }
        return null;
      }

      if (call.method == 'profilePopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _profileHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'employeePopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _employeeHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'floatingAction') {
        final action = args?['action'] as String? ?? '';
        final roomId = args?['roomId'] as String? ?? '';
        final currentHandler = _floatingHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, roomId);
        }
        return null;
      }

      if (call.method == 'folderPopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _folderHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'folderSubmenuAction') {
        final result = args?['result'] as String? ?? '';
        final currentHandler = _folderSubmenuHandler;
        if (currentHandler != null && result.isNotEmpty) {
          await currentHandler(result);
        }
        return null;
      }

      if (call.method == 'quietRoomsPopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _quietRoomsHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'multiLeaveRoomsPopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _multiLeaveRoomsHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'newChatPopupAction') {
        final action = args?['action'] as String? ?? '';
        final currentHandler = _newChatHandler;
        if (currentHandler != null && action.isNotEmpty) {
          await currentHandler(action, args?.cast<String, Object?>() ?? {});
        }
        return null;
      }

      if (call.method == 'fileDragState') {
        final currentHandler = _fileDragHandler;
        if (currentHandler != null) {
          await currentHandler(args?['active'] as bool? ?? false);
        }
        return null;
      }

      if (call.method == 'fileDrop') {
        final currentHandler = _fileDropHandler;
        final rawPaths = args?['paths'] as List?;
        if (currentHandler != null && rawPaths != null) {
          await currentHandler([
            for (final path in rawPaths)
              if (path is String && path.isNotEmpty) path,
          ]);
        }
        return null;
      }

      return null;
    });
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Tests and non-Windows targets do not provide this native channel.
    }
  }
}
