import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../../shared/ava_dialog.dart';
import '../../../shared/ava_toast.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../calendar/application/calendar_controller.dart';
import '../../messenger/data/chat_api.dart';
import '../data/ava_ai_api.dart';

const _aiChatBackground = Color(0xFFBFD3E3);
const _aiHeaderBackground = Color(0xFFD7E6F0);
const _aiHeaderBorder = Color(0xFFAFC7D8);
const _mineBubbleColor = Color(0xFFFFDF00);
const double _avaAiChatPaneWidth = 396;
const double _avaAiMinimumWorkspaceWidth = 390;
const double _avaAiWorkspaceModeRailWidth = 68;
const double _avaAiMobileBreakpoint = 720;

final ButtonStyle _workspaceHeaderButtonStyle = IconButton.styleFrom(
  foregroundColor: const Color(0xFF52616D),
  disabledForegroundColor: const Color(0xFF9AA8B2),
  hoverColor: const Color(0xFFDCE7EF),
);

final _avaAiPageMemory = _AvaAiPageMemory();

enum _AvaAiWorkspaceMode { assistant, notion, schedule }

extension _AvaAiWorkspaceModeLabel on _AvaAiWorkspaceMode {
  String get title {
    return switch (this) {
      _AvaAiWorkspaceMode.assistant => '작업공간(AI 비서)',
      _AvaAiWorkspaceMode.notion => '작업공간(Notion)',
      _AvaAiWorkspaceMode.schedule => '작업공간(일정표)',
    };
  }
}

class _AvaAiPageMemory {
  final List<_AvaAiUiMessage> messages = [];
  final List<_AvaAiChatSnapshot> chatSnapshots = [];
  final List<AvaAiWorkspaceItemDto> workspaceItems = [];
  final Set<String> selectedWorkspacePaths = {};
  String workspacePath = '';
  String workspaceStatus = '';
  _AvaAiWorkspaceMode workspaceMode = _AvaAiWorkspaceMode.assistant;
  AvaAiCalendarWorkspaceDto calendarWorkspace =
      AvaAiCalendarWorkspaceDto.empty();
  List<AvaAiNotionPageDto> notionResults = [];
  AvaAiNotionPageDto? activeNotionPage;
  String notionStatus = '';
  String? loadedToken;
  String? loadedSnapshotUserKey;
  bool hasState = false;

  void restoreTo(_AvaAiPageState state) {
    if (!hasState) {
      return;
    }
    state._messages
      ..clear()
      ..addAll(messages);
    state._chatSnapshots
      ..clear()
      ..addAll(chatSnapshots);
    state._workspaceItems
      ..clear()
      ..addAll(workspaceItems);
    state._selectedWorkspacePaths
      ..clear()
      ..addAll(selectedWorkspacePaths);
    state._workspacePath = workspacePath;
    state._workspaceStatus = workspaceStatus;
    state._workspaceMode = workspaceMode;
    state._calendarWorkspace = calendarWorkspace;
    state._notionResults
      ..clear()
      ..addAll(notionResults);
    state._activeNotionPage = activeNotionPage;
    state._notionStatus = notionStatus;
    state._loadedToken = loadedToken;
    state._loadedSnapshotUserKey = loadedSnapshotUserKey;
  }

  void saveFrom(_AvaAiPageState state) {
    hasState = true;
    messages
      ..clear()
      ..addAll(state._messages);
    chatSnapshots
      ..clear()
      ..addAll(state._chatSnapshots);
    workspaceItems
      ..clear()
      ..addAll(state._workspaceItems);
    selectedWorkspacePaths
      ..clear()
      ..addAll(state._selectedWorkspacePaths);
    workspacePath = state._workspacePath;
    workspaceStatus = state._workspaceStatus;
    workspaceMode = state._workspaceMode;
    calendarWorkspace = state._calendarWorkspace;
    notionResults
      ..clear()
      ..addAll(state._notionResults);
    activeNotionPage = state._activeNotionPage;
    notionStatus = state._notionStatus;
    loadedToken = state._loadingHistory ? null : state._loadedToken;
    loadedSnapshotUserKey = state._loadedSnapshotUserKey;
  }
}

class AvaAiPage extends ConsumerStatefulWidget {
  const AvaAiPage({super.key, this.quickPopup = false});

  final bool quickPopup;

  @override
  ConsumerState<AvaAiPage> createState() => _AvaAiPageState();
}

class _AvaAiPageState extends ConsumerState<AvaAiPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AvaAiUiMessage> _messages = [];
  final List<_AvaAiChatSnapshot> _chatSnapshots = [];
  final List<AvaAiWorkspaceItemDto> _workspaceItems = [];
  final List<AvaAiNotionPageDto> _notionResults = [];
  final Set<String> _selectedWorkspacePaths = {};
  _AvaAiWorkspaceMode _workspaceMode = _AvaAiWorkspaceMode.assistant;
  AvaAiNotionPageDto? _activeNotionPage;
  String _workspacePath = '';
  String _notionStatus = '';
  String _activeUserKey = '';
  String? _loadedToken;
  String? _loadedSnapshotUserKey;
  String? _loadedWorkspaceStateUserKey;
  bool _loadingHistory = false;
  bool _loadingWorkspaceState = false;
  bool _sending = false;
  bool _chatSessionBusy = false;
  bool _workspaceBusy = false;
  bool _draggingFile = false;
  bool _workspacePopupOpen = false;
  String _workspaceStatus = '';
  String _thinkingStatus = '';
  AvaAiCalendarWorkspaceDto _calendarWorkspace =
      AvaAiCalendarWorkspaceDto.empty();
  Object? _loadError;
  int _scrollRequest = 0;
  int _notionOpenRequest = 0;
  Timer? _workspaceStatePersistTimer;

  @override
  void initState() {
    super.initState();
    _avaAiPageMemory.restoreTo(this);
    WindowControl.setFileDropHandler(
      onDragState: (active) async {
        if (mounted) {
          setState(() => _draggingFile = active);
        }
      },
      onDrop: (paths) async {
        final token =
            ref.read(authControllerProvider).value?.session?.accessToken ?? '';
        if (token.isNotEmpty) {
          if (_workspaceMode == _AvaAiWorkspaceMode.notion) {
            await _uploadNotionFiles(token, paths);
          } else {
            await _uploadWorkspaceFiles(token, paths);
          }
        }
      },
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _avaAiPageMemory.saveFrom(this);
    _schedulePersistWorkspaceState();
  }

  @override
  void dispose() {
    _avaAiPageMemory.saveFrom(this);
    _workspaceStatePersistTimer?.cancel();
    _persistWorkspaceStateSync();
    WindowControl.setFileDropHandler();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(String accessToken) async {
    if (_loadingHistory || _loadedToken == accessToken) {
      return;
    }
    setState(() {
      _loadingHistory = true;
      _loadError = null;
      _loadedToken = accessToken;
    });
    var loadedMessages = false;
    try {
      final remoteMessages = await ref
          .read(avaAiApiProvider)
          .messages(accessToken);
      if (!mounted || _loadedToken != accessToken) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(remoteMessages.map(_AvaAiUiMessage.fromDto));
      });
      loadedMessages = true;
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
        });
        if (loadedMessages || _messages.isNotEmpty) {
          _scrollToBottom(animated: false);
        }
      }
    }
  }

  Future<void> _loadChatSnapshots(String userKey) async {
    if (_loadedSnapshotUserKey == userKey) {
      return;
    }
    try {
      final snapshots = await _readChatSnapshots(userKey);
      if (!mounted) {
        return;
      }
      setState(() {
        _chatSnapshots
          ..clear()
          ..addAll(snapshots);
        _loadedSnapshotUserKey = userKey;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _chatSnapshots.clear();
        _loadedSnapshotUserKey = userKey;
      });
    }
  }

  Future<void> _loadPersistedWorkspaceState(String userKey) async {
    if (_loadingWorkspaceState || _loadedWorkspaceStateUserKey == userKey) {
      return;
    }
    _loadingWorkspaceState = true;
    try {
      final snapshot = await _readWorkspaceState(userKey);
      if (!mounted || _activeUserKey != userKey) {
        return;
      }
      setState(() {
        _workspaceItems
          ..clear()
          ..addAll(snapshot?.items ?? const []);
        _selectedWorkspacePaths
          ..clear()
          ..addAll(snapshot?.selectedPaths ?? const {});
        _workspacePath = snapshot?.workspacePath ?? '';
        _workspaceStatus = snapshot?.workspaceStatus ?? '';
        _calendarWorkspace =
            snapshot?.calendarWorkspace ?? AvaAiCalendarWorkspaceDto.empty();
        _loadedWorkspaceStateUserKey = userKey;
      });
    } on Object {
      if (!mounted || _activeUserKey != userKey) {
        return;
      }
      setState(() {
        _workspaceItems.clear();
        _selectedWorkspacePaths.clear();
        _workspacePath = '';
        _workspaceStatus = '';
        _calendarWorkspace = AvaAiCalendarWorkspaceDto.empty();
        _loadedWorkspaceStateUserKey = userKey;
      });
    } finally {
      _loadingWorkspaceState = false;
    }
  }

  void _schedulePersistWorkspaceState() {
    if (_activeUserKey.isEmpty || _loadedWorkspaceStateUserKey == null) {
      return;
    }
    _workspaceStatePersistTimer?.cancel();
    _workspaceStatePersistTimer = Timer(
      const Duration(milliseconds: 250),
      _persistWorkspaceStateSync,
    );
  }

  void _persistWorkspaceStateSync() {
    if (_activeUserKey.isEmpty) {
      return;
    }
    try {
      final file = _workspaceStateFile(_activeUserKey);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'workspacePath': _workspacePath,
          'workspaceStatus': _workspaceStatus,
          'selectedPaths': _selectedWorkspacePaths.toList(),
          'items': [
            for (final item in _workspaceItems) _workspaceItemToJson(item),
          ],
          'calendarWorkspace': _calendarWorkspace.toJson(),
          'savedAt': DateTime.now().toIso8601String(),
        }),
      );
    } on Object {
      // UI state persistence is best-effort; the live workflow should continue.
    }
  }

  Future<void> _send(String accessToken) async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    if ((_workspaceMode == _AvaAiWorkspaceMode.notion ||
            _mentionsExplicitNotionTool(text)) &&
        _shouldUseNotionTool(text)) {
      if (_workspaceMode != _AvaAiWorkspaceMode.notion) {
        setState(() => _workspaceMode = _AvaAiWorkspaceMode.notion);
      }
      await _sendNotionCommand(accessToken, text);
      return;
    }
    final scheduleCommand = _isCalendarWorkspaceCommand(text);

    _inputController.clear();
    final tempUser = _AvaAiUiMessage(
      id: 'local-user-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _messages.add(tempUser);
      _sending = true;
      if (scheduleCommand) {
        _workspaceMode = _AvaAiWorkspaceMode.schedule;
        _workspaceBusy = true;
      }
      _thinkingStatus = scheduleCommand
          ? '일정표 작업공간에서 날짜, 제목, 실행 명령을 분석하고 있습니다.'
          : '대화 맥락과 작업 요청을 분석하고 있습니다.';
    });
    _scrollToBottom();

    try {
      final exchange = await ref
          .read(avaAiApiProvider)
          .send(
            accessToken: accessToken,
            content: text,
            workspacePaths: _selectedWorkspacePaths.toList(),
          );
      if (!mounted) {
        return;
      }
      final calendarWorkspace = exchange.calendarWorkspace;
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages
          ..add(_AvaAiUiMessage.fromDto(exchange.userMessage))
          ..add(_AvaAiUiMessage.fromDto(exchange.assistantMessage));
        if (exchange.workspaceItems.isNotEmpty) {
          _workspaceItems
            ..clear()
            ..addAll(exchange.workspaceItems);
          _selectedWorkspacePaths
            ..clear()
            ..addAll(
              exchange.workspaceItems
                  .where((item) => item.isSendableFile)
                  .map((item) => item.path),
            );
        }
        _workspaceStatus = _statusWithAgent(
          exchange.workspaceStatus,
          exchange.agentTask,
        );
        if (calendarWorkspace.hasSignal) {
          _calendarWorkspace = calendarWorkspace;
          _workspaceMode = _AvaAiWorkspaceMode.schedule;
        }
        _sending = false;
        _workspaceBusy = false;
        _thinkingStatus = '';
      });
      if (calendarWorkspace.mutation) {
        unawaited(_refreshCalendarFromAiWorkspace(calendarWorkspace));
      }
      _scrollToBottom();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages.add(tempUser.copyWith(pending: false, failed: true));
        _sending = false;
        _workspaceBusy = false;
        _thinkingStatus = '';
      });
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authErrorMessage(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted && _sending) {
        setState(() {
          _sending = false;
          _workspaceBusy = false;
          _thinkingStatus = '';
        });
      }
    }
  }

  Future<void> _refreshCalendarFromAiWorkspace(
    AvaAiCalendarWorkspaceDto workspace,
  ) async {
    final event = workspace.selectedEvent();
    await ref
        .read(calendarControllerProvider.notifier)
        .refreshFromExternalMutation(
          focusDate: event?.startAt?.toLocal(),
          selectedEventId: (event?.id.isNotEmpty == true
              ? event!.id
              : workspace.selectedEventId),
        );
  }

  bool _shouldUseNotionTool(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final followUp =
        normalized.contains('방금') ||
        normalized.contains('아까') ||
        normalized.contains('추가한') ||
        normalized.contains('작성한') ||
        normalized.contains('등록한');
    final asksLocation =
        normalized.contains('어디') ||
        normalized.contains('뭐') ||
        normalized.contains('무엇') ||
        normalized.contains('확인') ||
        normalized.contains('?');
    if (followUp && asksLocation) {
      return true;
    }
    if (_isClarificationOnly(normalized)) {
      return false;
    }
    final mentionsNotion =
        normalized.contains('노션') ||
        normalized.contains('notion') ||
        normalized.contains('페이지') ||
        normalized.contains('데이터베이스') ||
        normalized.contains('db') ||
        normalized.contains('항목');
    final asksRead =
        normalized.contains('찾아') ||
        normalized.contains('검색') ||
        normalized.contains('보여') ||
        normalized.contains('열어') ||
        normalized.contains('불러');
    final asksWrite = _hasExplicitWriteDirective(normalized);
    if (mentionsNotion && (asksRead || asksWrite)) {
      return true;
    }
    if (_activeNotionPage != null && (asksRead || asksWrite)) {
      return true;
    }
    return false;
  }

  String _statusWithAgent(
    String workspaceStatus,
    AvaAiAgentTaskDto? agentTask,
  ) {
    final agentStatus = agentTask?.statusLine ?? '';
    if (agentStatus.isEmpty) {
      return workspaceStatus;
    }
    if (workspaceStatus.trim().isEmpty) {
      return agentStatus;
    }
    return '$workspaceStatus\n$agentStatus';
  }

  bool _isCalendarWorkspaceCommand(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final scheduleWord =
        normalized.contains('일정') ||
        normalized.contains('캘린더') ||
        normalized.contains('일정표') ||
        normalized.contains('스케줄') ||
        normalized.contains('calendar') ||
        normalized.contains('schedule');
    final meetingWord =
        normalized.contains('회의') ||
        normalized.contains('미팅') ||
        normalized.contains('meeting');
    final actionWord =
        normalized.contains('추가') ||
        normalized.contains('등록') ||
        normalized.contains('생성') ||
        normalized.contains('작성') ||
        normalized.contains('잡아') ||
        normalized.contains('보여') ||
        normalized.contains('알려') ||
        normalized.contains('조회') ||
        normalized.contains('검색') ||
        normalized.contains('찾아') ||
        normalized.contains('삭제') ||
        normalized.contains('지워') ||
        normalized.contains('수정') ||
        normalized.contains('변경') ||
        normalized.contains('가능한') ||
        normalized.contains('충돌') ||
        normalized.contains('겹');
    return scheduleWord || (meetingWord && actionWord);
  }

  bool _mentionsExplicitNotionTool(String text) {
    final normalized = text.trim().toLowerCase();
    return normalized.contains('노션') ||
        normalized.contains('notion') ||
        normalized.contains('연구소') ||
        normalized.contains('개발 진행사항') ||
        normalized.contains('개발진행사항');
  }

  bool _isClarificationOnly(String normalized) {
    return normalized.contains('라는거야') ||
        normalized.contains('라는 거야') ||
        normalized.contains('하라는게') ||
        normalized.contains('하라는 게') ||
        normalized.contains('아니고') ||
        normalized.contains('말귀') ||
        normalized.contains('이해');
  }

  bool _hasExplicitWriteDirective(String normalized) {
    final writePattern = RegExp(
      r'(추가|작성|등록|넣어|생성|만들|삭제|지워|제거)\s*(해줘|해주세요|해 주세요|해|하세요|해라|해놔|해 둬|해두|$)|\b(add|append|create|write|insert|delete|remove|archive)\b',
      caseSensitive: false,
    );
    return writePattern.hasMatch(normalized);
  }

  Future<void> _sendNotionCommand(String accessToken, String text) async {
    _inputController.clear();
    final now = DateTime.now();
    final tempUser = _AvaAiUiMessage(
      id: 'local-notion-user-${now.microsecondsSinceEpoch}',
      role: 'user',
      content: text,
      createdAt: now,
      pending: true,
    );
    setState(() {
      _messages.add(tempUser);
      _sending = true;
      _workspaceBusy = true;
      _thinkingStatus = 'Notion 명령의 대상과 작업 방식을 분석하고 있습니다.';
      _notionStatus = 'Notion 작업을 분석하고 있습니다.';
    });
    _scrollToBottom();

    try {
      final result = await ref
          .read(avaAiApiProvider)
          .notionCommand(
            accessToken: accessToken,
            command: text,
            activePageId: _activeNotionPage?.id ?? '',
            activePageObject: _activeNotionPage?.object ?? '',
          );
      if (!mounted) {
        return;
      }
      final assistant = _AvaAiUiMessage(
        id: 'local-notion-assistant-${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        content: result.answer.isEmpty ? result.status : result.answer,
        createdAt: DateTime.now(),
      );
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages
          ..add(tempUser.copyWith(pending: false))
          ..add(assistant);
        _applyNotionCommandResult(result);
        _notionStatus = result.status;
        _sending = false;
        _thinkingStatus = '';
        _workspaceBusy = false;
      });
      _scrollToBottom();
      if (result.requiresApproval) {
        final approved = await showAvaConfirmDialog(
          context,
          title: result.approvalTitle.isEmpty
              ? 'Notion 작업 승인'
              : result.approvalTitle,
          message: result.approvalDescription.isEmpty
              ? 'Notion 쓰기 작업을 실행하려면 승인이 필요합니다.'
              : result.approvalDescription,
          cancelLabel: '취소',
          confirmLabel: '승인 후 실행',
        );
        if (!mounted) {
          return;
        }
        if (approved) {
          await _executeApprovedNotionCommand(accessToken, text);
        } else {
          setState(() {
            _messages.add(
              _AvaAiUiMessage(
                id: 'local-notion-cancel-${DateTime.now().microsecondsSinceEpoch}',
                role: 'assistant',
                content: '승인이 취소되어 Notion 쓰기 작업을 실행하지 않았습니다.',
                createdAt: DateTime.now(),
              ),
            );
            _notionStatus = 'Notion 승인 작업을 취소했습니다.';
            _thinkingStatus = '';
          });
          _scrollToBottom();
        }
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages.add(tempUser.copyWith(pending: false, failed: true));
        _sending = false;
        _thinkingStatus = '';
        _workspaceBusy = false;
        _notionStatus = 'Notion 작업 중 오류가 발생했습니다.';
      });
      showAvaToast(context, authErrorMessage(error));
      _scrollToBottom();
    }
  }

  Future<void> _executeApprovedNotionCommand(
    String accessToken,
    String text,
  ) async {
    setState(() {
      _sending = true;
      _workspaceBusy = true;
      _thinkingStatus = '승인된 Notion 작업을 실행하고 결과를 검증하고 있습니다.';
      _notionStatus = '승인된 Notion 작업을 실행하고 있습니다.';
    });
    try {
      final result = await ref
          .read(avaAiApiProvider)
          .notionCommand(
            accessToken: accessToken,
            command: text,
            activePageId: _activeNotionPage?.id ?? '',
            activePageObject: _activeNotionPage?.object ?? '',
            approved: true,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _AvaAiUiMessage(
            id: 'local-notion-approved-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: result.answer.isEmpty ? result.status : result.answer,
            createdAt: DateTime.now(),
          ),
        );
        _applyNotionCommandResult(result);
        _notionStatus = result.status;
        _sending = false;
        _thinkingStatus = '';
        _workspaceBusy = false;
      });
      _scrollToBottom();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _thinkingStatus = '';
        _workspaceBusy = false;
        _notionStatus = '승인된 Notion 작업 실행 중 오류가 발생했습니다.';
      });
      showAvaToast(context, authErrorMessage(error));
    }
  }

  void _applyNotionCommandResult(AvaAiNotionCommandDto result) {
    if (result.results.isNotEmpty) {
      _notionResults
        ..clear()
        ..addAll(result.results);
    }
    _activeNotionPage =
        result.activePage ??
        (result.results.isEmpty ? _activeNotionPage : result.results.first);
  }

  Future<void> _newChat(String accessToken, String userKey) async {
    if (_chatSessionBusy || _sending) {
      return;
    }
    setState(() => _chatSessionBusy = true);
    try {
      await _archiveCurrentChat(userKey);
      await ref.read(avaAiApiProvider).resetMessages(accessToken);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.clear();
        _loadError = null;
        _loadedToken = accessToken;
      });
      showAvaToast(context, '새 채팅을 시작했습니다.');
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _chatSessionBusy = false);
      }
    }
  }

  Future<void> _showPreviousChats(String accessToken, String userKey) async {
    if (_chatSessionBusy || _sending) {
      return;
    }
    await _loadChatSnapshots(userKey);
    if (!mounted) {
      return;
    }
    final dialogSnapshots = List<_AvaAiChatSnapshot>.of(_chatSnapshots);
    final selected = await showDialog<_AvaAiChatSnapshot>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> deleteSnapshot(_AvaAiChatSnapshot snapshot) async {
              final confirmed = await showAvaConfirmDialog(
                context,
                title: '대화 기록 삭제',
                message: '선택한 대화 기록을 삭제할까요?',
                confirmLabel: '삭제',
                destructive: true,
              );
              if (!confirmed || !context.mounted) {
                return;
              }
              setDialogState(() {
                dialogSnapshots.removeWhere((item) => item.id == snapshot.id);
              });
              if (mounted) {
                setState(() {
                  _chatSnapshots
                    ..clear()
                    ..addAll(dialogSnapshots);
                });
              } else {
                _chatSnapshots
                  ..clear()
                  ..addAll(dialogSnapshots);
              }
              await _writeChatSnapshots(userKey, dialogSnapshots);
            }

            return AvaDialog(
              title: '대화 기록',
              subtitle: '이전에 저장된 AVA AI 대화를 불러올 수 있습니다.',
              icon: const Icon(
                Icons.history_rounded,
                color: Color(0xFF4F65C8),
                size: 24,
              ),
              width: 440,
              actions: [
                AvaDialogButton(
                  label: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
              child: SizedBox(
                height: dialogSnapshots.isEmpty ? 96 : 280,
                child: dialogSnapshots.isEmpty
                    ? const Center(
                        child: Text(
                          '저장된 대화 기록이 없습니다.',
                          style: TextStyle(
                            color: Color(0xFF5E7182),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: dialogSnapshots.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final snapshot = dialogSnapshots[index];
                          return _PreviousChatSnapshotTile(
                            snapshot: snapshot,
                            onOpen: () => Navigator.of(context).pop(snapshot),
                            onDelete: () => deleteSnapshot(snapshot),
                          );
                        },
                      ),
              ),
            );
          },
        );
      },
    );
    if (selected == null) {
      return;
    }

    setState(() => _chatSessionBusy = true);
    try {
      await _archiveCurrentChat(userKey);
      await ref.read(avaAiApiProvider).resetMessages(accessToken);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(selected.messages);
        _loadError = null;
        _loadedToken = accessToken;
      });
      _scrollToBottom(animated: false);
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _chatSessionBusy = false);
      }
    }
  }

  Future<void> _archiveCurrentChat(String userKey) async {
    final messages = _messages
        .where((message) => !message.pending && !message.failed)
        .toList();
    if (messages.isEmpty) {
      return;
    }
    final snapshot = _AvaAiChatSnapshot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _formatArchiveTime(DateTime.now()),
      savedAt: DateTime.now(),
      messages: List.unmodifiable(messages),
    );
    _chatSnapshots.insert(0, snapshot);
    await _writeChatSnapshots(userKey, _chatSnapshots);
  }

  Future<void> _loadWorkspaceRoot(String accessToken) async {
    await _loadWorkspacePath(accessToken, '');
  }

  Future<void> _loadWorkspaceParent(String accessToken) async {
    if (_workspacePath.isEmpty) {
      return;
    }
    await _loadWorkspacePath(accessToken, _parentWorkspacePath(_workspacePath));
  }

  Future<void> _loadWorkspacePath(String accessToken, String path) async {
    if (_workspaceBusy) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = path.isEmpty
          ? 'FORIVER_NAS (F:) 루트를 불러오고 있습니다.'
          : '$path 폴더를 불러오고 있습니다.';
    });
    try {
      final items = await ref
          .read(avaAiApiProvider)
          .workspaceFiles(accessToken: accessToken, path: path);
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceItems
          ..clear()
          ..addAll(items);
        _workspacePath = path;
        _workspaceStatus = path.isEmpty
            ? 'FORIVER_NAS (F:) 루트를 불러왔습니다.'
            : '$path 폴더를 불러왔습니다.';
        _selectedWorkspacePaths.removeWhere(
          (selectedPath) => !items.any((item) => item.path == selectedPath),
        );
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _openWorkspaceItem(
    String accessToken,
    AvaAiWorkspaceItemDto item,
  ) async {
    if (_workspaceBusy || item.path.isEmpty) {
      return;
    }
    if (item.isDirectory) {
      await _loadWorkspacePath(accessToken, item.path);
      return;
    }
    if (!item.isWorkspaceFile) {
      return;
    }
    if (!_isTextWorkspaceFile(item)) {
      await _downloadAndOpenWorkspaceFile(accessToken, item);
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 파일을 읽고 있습니다.';
    });
    try {
      final loaded = await ref
          .read(avaAiApiProvider)
          .readWorkspaceFile(accessToken: accessToken, path: item.path);
      if (!mounted) {
        return;
      }
      setState(() {
        final index = _workspaceItems.indexWhere(
          (candidate) => candidate.path == item.path,
        );
        if (index >= 0) {
          _workspaceItems[index] = loaded;
        } else {
          _workspaceItems.insert(0, loaded);
        }
        _workspaceStatus = '${loaded.title} 파일 열기 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _downloadAndOpenWorkspaceFile(
    String accessToken,
    AvaAiWorkspaceItemDto item,
  ) async {
    if (!Platform.isWindows) {
      showAvaToast(context, '파일 열기는 Windows에서만 지원합니다.');
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 파일을 열고 있습니다.';
    });
    try {
      final originalPath = _foriverNasLocalPath(item.path);
      if (await File(originalPath).exists()) {
        await _openWindowsPath(originalPath);
        if (!mounted) {
          return;
        }
        setState(() {
          _workspaceStatus = '${item.title} 파일 열기 완료';
        });
        return;
      }

      final directory = Directory(_downloadsDirectoryPath());
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final safeName = _safeWorkspaceFileName(
        item.title.isEmpty ? item.path : item.title,
      );
      final savePath = await _uniqueDownloadPath(directory.path, safeName);
      await ref
          .read(avaAiApiProvider)
          .downloadWorkspaceFile(
            accessToken: accessToken,
            path: item.path,
            savePath: savePath,
          );
      await _openWindowsPath(savePath);
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceStatus = '${item.title} 파일을 다운로드한 뒤 열었습니다.';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _renameWorkspaceItem(
    String accessToken,
    AvaAiWorkspaceItemDto item,
  ) async {
    final draft = await _showWorkspaceFileDialog(
      context,
      title: '파일 이름 또는 경로 변경',
      initialPath: item.path,
      pathEditable: true,
      showContent: false,
    );
    if (draft == null || draft.path == item.path) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 이름을 변경하고 있습니다.';
    });
    try {
      final updated = await ref
          .read(avaAiApiProvider)
          .updateWorkspaceFile(
            accessToken: accessToken,
            path: item.path,
            newPath: draft.path,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        final wasSelected = _selectedWorkspacePaths.contains(item.path);
        final index = _workspaceItems.indexWhere(
          (candidate) => candidate.path == item.path,
        );
        if (index >= 0) {
          _workspaceItems[index] = updated;
        }
        _selectedWorkspacePaths.remove(item.path);
        if (wasSelected && updated.isSendableFile) {
          _selectedWorkspacePaths.add(updated.path);
        }
        _workspaceStatus = '${updated.title} 수정 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _createWorkspaceFile(String accessToken) async {
    final defaultPath = _workspacePath.isEmpty
        ? '새파일.txt'
        : '${_workspacePath.replaceAll('\\', '/')}/새파일.txt';
    final draft = await _showWorkspaceFileDialog(
      context,
      title: '작업공간 파일 만들기',
      initialPath: defaultPath,
      allowDirectory: true,
    );
    if (draft == null) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${draft.path} 생성 중입니다.';
    });
    try {
      final created = await ref
          .read(avaAiApiProvider)
          .createWorkspaceFile(
            accessToken: accessToken,
            path: draft.path,
            content: draft.content,
            isDirectory: draft.isDirectory,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceItems.insert(0, created);
        _workspaceStatus = '${created.title} 생성 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _editWorkspaceFile(
    String accessToken,
    AvaAiWorkspaceItemDto item,
  ) async {
    if (!item.isWorkspacePath || item.path.isEmpty || _workspaceBusy) {
      return;
    }
    if (item.isDirectory || !_isTextWorkspaceFile(item)) {
      await _renameWorkspaceItem(accessToken, item);
      return;
    }
    AvaAiWorkspaceItemDto loaded = item;
    if (loaded.content.isEmpty) {
      try {
        loaded = await ref
            .read(avaAiApiProvider)
            .readWorkspaceFile(accessToken: accessToken, path: item.path);
      } on Object catch (error) {
        if (mounted) {
          showAvaToast(context, authErrorMessage(error));
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }
    final draft = await _showWorkspaceFileDialog(
      context,
      title: '파일 수정',
      initialPath: loaded.path,
      initialContent: loaded.content,
      pathEditable: true,
    );
    if (draft == null) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${loaded.title} 수정 중입니다.';
    });
    try {
      final updated = await ref
          .read(avaAiApiProvider)
          .updateWorkspaceFile(
            accessToken: accessToken,
            path: loaded.path,
            newPath: draft.path,
            content: draft.content,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        final wasSelected = _selectedWorkspacePaths.contains(loaded.path);
        final index = _workspaceItems.indexWhere(
          (candidate) => candidate.path == loaded.path,
        );
        if (index >= 0) {
          _workspaceItems[index] = updated;
        } else {
          _workspaceItems.insert(0, updated);
        }
        _selectedWorkspacePaths.remove(loaded.path);
        if (wasSelected && updated.isSendableFile) {
          _selectedWorkspacePaths.add(updated.path);
        }
        _workspaceStatus = '${updated.title} 수정 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _deleteWorkspaceItem(
    String accessToken,
    AvaAiWorkspaceItemDto item,
  ) async {
    if (!item.isWorkspacePath || item.path.isEmpty || _workspaceBusy) {
      return;
    }
    final confirmed = await _confirmWorkspaceDelete(context, item);
    if (!confirmed) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 삭제 중입니다.';
    });
    try {
      await ref
          .read(avaAiApiProvider)
          .deleteWorkspaceFile(accessToken: accessToken, path: item.path);
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceItems.removeWhere((candidate) => candidate.path == item.path);
        _selectedWorkspacePaths.remove(item.path);
        _workspaceStatus = '${item.title} 삭제 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _pickAndUploadWorkspaceFiles(String accessToken) async {
    final paths = await _pickWorkspaceFiles(context);
    if (paths.isNotEmpty) {
      await _uploadWorkspaceFiles(accessToken, paths);
    }
  }

  Future<void> _uploadWorkspaceFiles(
    String accessToken,
    List<String> paths,
  ) async {
    final existing = <String>[];
    for (final path in paths) {
      if (await File(path).exists()) {
        existing.add(path);
      }
    }
    if (existing.isEmpty || _workspaceBusy) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '작업공간에 파일을 업로드하고 있습니다.';
    });
    try {
      final items = await ref
          .read(avaAiApiProvider)
          .uploadWorkspaceFiles(accessToken: accessToken, filePaths: existing);
      if (!mounted) {
        return;
      }
      setState(() {
        _workspaceItems.insertAll(0, items);
        _selectedWorkspacePaths.addAll(items.map((item) => item.path));
        _workspaceStatus = '${items.length}개 파일 업로드 완료';
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _workspaceBusy = false;
          _draggingFile = false;
        });
      }
    }
  }

  Future<void> _sendSelectedWorkspaceItems(String accessToken) async {
    final paths = _selectedWorkspacePaths.toList();
    if (paths.isEmpty) {
      showAvaToast(context, '보낼 작업공간 파일을 선택해주세요.');
      return;
    }
    final draft = await _showWorkspaceSendDialog(context, ref, accessToken);
    if (draft == null) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '선택한 파일을 채팅방으로 보내고 있습니다.';
    });
    try {
      final result = await ref
          .read(avaAiApiProvider)
          .sendWorkspaceToChat(
            accessToken: accessToken,
            roomCode: draft.roomCode,
            targetName: draft.targetName,
            message: draft.message,
            paths: paths,
          );
      if (!mounted) {
        return;
      }
      setState(() => _workspaceStatus = result.status);
      showAvaToast(
        context,
        result.status.isEmpty ? '전송이 완료되었습니다.' : result.status,
      );
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _selectWorkspaceMode(
    _AvaAiWorkspaceMode mode,
    String accessToken,
  ) async {
    if (_workspaceMode == mode) {
      return;
    }
    setState(() {
      _workspaceMode = mode;
      _draggingFile = false;
    });
    if (mode == _AvaAiWorkspaceMode.notion &&
        accessToken.isNotEmpty &&
        _notionResults.isEmpty &&
        _activeNotionPage == null) {
      await _loadNotionHome(accessToken);
    } else if (mode == _AvaAiWorkspaceMode.schedule &&
        accessToken.isNotEmpty &&
        !_calendarWorkspace.hasSignal) {
      await _loadCalendarWorkspace(accessToken);
    }
  }

  Future<void> _loadCalendarWorkspace(String accessToken) async {
    if (_workspaceBusy) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _calendarWorkspace = _calendarWorkspace.copyWith(
        selectedEventId: _calendarWorkspace.selectedEventId,
      );
    });
    try {
      final workspace = await ref
          .read(avaAiApiProvider)
          .calendarWorkspace(accessToken: accessToken, mode: 'today');
      if (!mounted) {
        return;
      }
      setState(() {
        _calendarWorkspace = workspace;
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _loadNotionHome(String accessToken) async {
    if (_workspaceBusy) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _notionStatus = 'Notion 작업공간을 불러오고 있습니다.';
    });
    try {
      final result = await ref
          .read(avaAiApiProvider)
          .notionCommand(accessToken: accessToken, command: '');
      if (!mounted) {
        return;
      }
      setState(() {
        _notionResults
          ..clear()
          ..addAll(result.results);
        _activeNotionPage = result.activePage ?? result.results.firstOrNull;
        _notionStatus = result.status.isEmpty ? 'Notion 연결 완료' : result.status;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _notionStatus = 'Notion 연결 중 오류가 발생했습니다.');
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _openNotionPage(
    String accessToken,
    AvaAiNotionPageDto page,
  ) async {
    if (page.id.isEmpty) {
      return;
    }
    final request = ++_notionOpenRequest;
    setState(() {
      _workspaceBusy = true;
      _activeNotionPage = page;
      final index = _notionResults.indexWhere((item) => item.id == page.id);
      if (index >= 0) {
        _notionResults[index] = page;
      } else {
        _notionResults.insert(0, page);
      }
      _notionStatus = '${page.title} 페이지를 불러오고 있습니다.';
    });
    try {
      final loaded = await ref
          .read(avaAiApiProvider)
          .notionPage(
            accessToken: accessToken,
            id: page.id,
            object: page.object.isEmpty ? 'page' : page.object,
          );
      if (!mounted || request != _notionOpenRequest) {
        return;
      }
      setState(() {
        _activeNotionPage = loaded;
        final index = _notionResults.indexWhere((item) => item.id == loaded.id);
        if (index >= 0) {
          _notionResults[index] = loaded;
        } else {
          _notionResults.insert(0, loaded);
        }
        _notionStatus = '${loaded.title} 열기 완료';
      });
    } on Object catch (error) {
      if (mounted && request == _notionOpenRequest) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted && request == _notionOpenRequest) {
        setState(() => _workspaceBusy = false);
      }
    }
  }

  Future<void> _uploadNotionFiles(
    String accessToken,
    List<String> paths,
  ) async {
    final targetId = _activeNotionPage?.id ?? '';
    if (targetId.isEmpty) {
      showAvaToast(context, '파일을 첨부할 Notion 페이지를 먼저 선택해주세요.');
      setState(() => _draggingFile = false);
      return;
    }
    final existing = <String>[];
    for (final path in paths) {
      if (await File(path).exists()) {
        existing.add(path);
      }
    }
    if (existing.isEmpty || _workspaceBusy) {
      return;
    }
    if (!mounted) {
      return;
    }
    final approved = await showAvaConfirmDialog(
      context,
      title: 'Notion 파일 첨부 승인',
      message: [
        '?ㅽ뻾 諛⑹떇: 吏곸젒 Notion API',
        '대상: ${_activeNotionPage?.title ?? '현재 Notion 페이지'}',
        '작업: 파일 첨부',
        '승인하면 선택한 파일을 실제 Notion 페이지에 추가합니다.',
      ].join('\n'),
      cancelLabel: '취소',
      confirmLabel: '승인 후 첨부',
    );
    if (!mounted) {
      return;
    }
    if (!approved) {
      setState(() {
        _draggingFile = false;
        _notionStatus = 'Notion 파일 첨부를 취소했습니다.';
      });
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _notionStatus = 'Notion 페이지에 파일을 첨부하고 있습니다.';
    });
    try {
      final result = await ref
          .read(avaAiApiProvider)
          .uploadNotionFiles(
            accessToken: accessToken,
            targetId: targetId,
            filePaths: existing,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeNotionPage = result.activePage ?? _activeNotionPage;
        _notionResults
          ..clear()
          ..addAll(result.results);
        _notionStatus = result.status;
      });
    } on Object catch (error) {
      if (mounted) {
        showAvaToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _workspaceBusy = false;
          _draggingFile = false;
        });
      }
    }
  }

  void _scrollToBottom({bool animated = true}) {
    final request = ++_scrollRequest;
    unawaited(_settleScrollToBottom(request, animated: animated));
  }

  Future<void> _settleScrollToBottom(
    int request, {
    required bool animated,
  }) async {
    for (var pass = 0; pass < 5; pass++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          request != _scrollRequest ||
          !_scrollController.hasClients) {
        return;
      }

      final target = _scrollController.position.maxScrollExtent;
      final distance = (target - _scrollController.offset).abs();
      if (distance > 0.5) {
        try {
          if (animated && pass == 0) {
            await _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            );
          } else {
            _scrollController.jumpTo(target);
          }
        } on Object {
          return;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value?.session;
    final accessToken = session?.accessToken ?? '';
    final userKey = session == null
        ? ''
        : (session.user.email.isNotEmpty
              ? session.user.email
              : session.user.id);
    if (userKey.isNotEmpty && _activeUserKey != userKey) {
      _activeUserKey = userKey;
    }
    if (accessToken.isNotEmpty && _loadedToken != accessToken) {
      unawaited(_loadHistory(accessToken));
    }
    if (userKey.isNotEmpty && _loadedSnapshotUserKey != userKey) {
      unawaited(_loadChatSnapshots(userKey));
    }
    if (userKey.isNotEmpty && _loadedWorkspaceStateUserKey != userKey) {
      unawaited(_loadPersistedWorkspaceState(userKey));
    }

    final chatPane = Column(
      children: [
        _AvaAiHeader(
          busy: _chatSessionBusy,
          onPreviousChat: accessToken.isEmpty || userKey.isEmpty
              ? null
              : () => _showPreviousChats(accessToken, userKey),
          onNewChat: accessToken.isEmpty || userKey.isEmpty
              ? null
              : () => _newChat(accessToken, userKey),
          onWorkspace: widget.quickPopup
              ? () => setState(() => _workspacePopupOpen = true)
              : null,
        ),
        Expanded(
          child: _AvaAiMessagesView(
            controller: _scrollController,
            messages: _messages,
            loadingHistory: _loadingHistory,
            sending: _sending,
            thinkingStatus: _thinkingStatus,
            loadError: _loadError,
            onRetry: accessToken.isEmpty
                ? null
                : () {
                    _loadedToken = null;
                    unawaited(_loadHistory(accessToken));
                  },
          ),
        ),
        _AvaAiComposer(
          controller: _inputController,
          enabled: accessToken.isNotEmpty && !_sending,
          sending: _sending,
          onSend: () => _send(accessToken),
        ),
      ],
    );

    final assistantWorkspacePanel = _AvaAiWorkspacePanel(
      title: _AvaAiWorkspaceMode.assistant.title,
      items: _workspaceItems,
      selectedPaths: _selectedWorkspacePaths,
      currentPath: _workspacePath,
      status: _workspaceStatus,
      busy: _workspaceBusy,
      dragging: _draggingFile,
      onOpenParent: accessToken.isEmpty || _workspacePath.isEmpty
          ? null
          : () => _loadWorkspaceParent(accessToken),
      onBrowseRoot: accessToken.isEmpty
          ? null
          : () => _loadWorkspaceRoot(accessToken),
      onCreateFile: accessToken.isEmpty
          ? null
          : () => _createWorkspaceFile(accessToken),
      onPickFiles: accessToken.isEmpty
          ? null
          : () => _pickAndUploadWorkspaceFiles(accessToken),
      onSendSelected: accessToken.isEmpty
          ? null
          : () => _sendSelectedWorkspaceItems(accessToken),
      onOpenItem: accessToken.isEmpty
          ? null
          : (item) => _openWorkspaceItem(accessToken, item),
      onEditItem: accessToken.isEmpty
          ? null
          : (item) => _editWorkspaceFile(accessToken, item),
      onDeleteItem: accessToken.isEmpty
          ? null
          : (item) => _deleteWorkspaceItem(accessToken, item),
      onSelectionChanged: (path, selected) {
        setState(() {
          if (selected) {
            _selectedWorkspacePaths.add(path);
          } else {
            _selectedWorkspacePaths.remove(path);
          }
        });
      },
    );
    final notionPanel = _AvaAiNotionWorkspacePanel(
      title: _AvaAiWorkspaceMode.notion.title,
      results: _notionResults,
      activePage: _activeNotionPage,
      status: _notionStatus,
      busy: _workspaceBusy,
      dragging: _draggingFile,
      onRefresh: accessToken.isEmpty
          ? null
          : () => _loadNotionHome(accessToken),
      onOpenPage: accessToken.isEmpty
          ? null
          : (page) => _openNotionPage(accessToken, page),
    );
    final schedulePanel = _AvaAiScheduleWorkspacePanel(
      title: _AvaAiWorkspaceMode.schedule.title,
      workspace: _calendarWorkspace,
      busy: _workspaceBusy,
      onRefresh: accessToken.isEmpty
          ? null
          : () => _loadCalendarWorkspace(accessToken),
      onSelectEvent: (event) {
        setState(() {
          _calendarWorkspace = _calendarWorkspace.copyWith(
            selectedEventId: event.id,
          );
        });
      },
    );
    final activeWorkspacePanel = switch (_workspaceMode) {
      _AvaAiWorkspaceMode.assistant => assistantWorkspacePanel,
      _AvaAiWorkspaceMode.notion => notionPanel,
      _AvaAiWorkspaceMode.schedule => schedulePanel,
    };
    final workspacePanel = Row(
      children: [
        Expanded(child: activeWorkspacePanel),
        _AvaAiWorkspaceModeRail(
          activeMode: _workspaceMode,
          onSelect: (mode) => _selectWorkspaceMode(mode, accessToken),
        ),
      ],
    );

    if (widget.quickPopup) {
      return Material(
        color: _aiChatBackground,
        child: Stack(
          children: [
            Positioned.fill(child: chatPane),
            if (_workspacePopupOpen)
              Positioned.fill(
                child: _QuickWorkspacePopup(
                  onClose: () => setState(() => _workspacePopupOpen = false),
                  child: workspacePanel,
                ),
              ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: _aiChatBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobileAppLayout =
              (Platform.isAndroid || Platform.isIOS) &&
              constraints.maxWidth <= _avaAiMobileBreakpoint;
          if (mobileAppLayout) {
            return Column(
              key: const ValueKey('ava-ai-mobile-split-layout'),
              children: [
                Expanded(
                  child: SizedBox(
                    key: const ValueKey('ava-ai-workspace-pane'),
                    width: double.infinity,
                    child: workspacePanel,
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    key: const ValueKey('ava-ai-chat-pane'),
                    width: double.infinity,
                    child: chatPane,
                  ),
                ),
              ],
            );
          }

          final contentWidth = math.max(
            constraints.maxWidth,
            _avaAiChatPaneWidth + _avaAiMinimumWorkspaceWidth,
          );
          final workspaceWidth = contentWidth - _avaAiChatPaneWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: contentWidth > constraints.maxWidth
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: contentWidth,
              child: Row(
                children: [
                  SizedBox(
                    key: const ValueKey('ava-ai-chat-pane'),
                    width: _avaAiChatPaneWidth,
                    child: chatPane,
                  ),
                  SizedBox(
                    key: const ValueKey('ava-ai-workspace-pane'),
                    width: workspaceWidth,
                    child: workspacePanel,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QuickWorkspacePopup extends StatelessWidget {
  const _QuickWorkspacePopup({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth - 22, 420.0);
          final height = math.min(constraints.maxHeight - 28, 610.0);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 10, 11, 14),
                  child: Material(
                    color: Colors.white,
                    elevation: 18,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: math.max(320, width),
                      height: math.max(420, height),
                      child: Column(
                        children: [
                          Container(
                            height: 42,
                            padding: const EdgeInsets.only(left: 14, right: 4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF7FAFC),
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFD7E0E7)),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '\uC791\uC5C5\uACF5\uAC04',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Color(0xFF102040),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '\uB2EB\uAE30',
                                  onPressed: onClose,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AvaAiWorkspaceModeRail extends StatelessWidget {
  const _AvaAiWorkspaceModeRail({
    required this.activeMode,
    required this.onSelect,
  });

  final _AvaAiWorkspaceMode activeMode;
  final ValueChanged<_AvaAiWorkspaceMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _avaAiWorkspaceModeRailWidth,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          left: BorderSide(color: Color(0xFFD3DEE7)),
          right: BorderSide(color: Color(0xFFE5ECF1)),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            _WorkspaceModeButton(
              label: 'AVA AI',
              tooltip: '통합 비서',
              icon: const _AvaAiModeIcon(),
              selected: activeMode == _AvaAiWorkspaceMode.assistant,
              onTap: () => onSelect(_AvaAiWorkspaceMode.assistant),
            ),
            const SizedBox(height: 10),
            _WorkspaceModeButton(
              label: 'Notion',
              tooltip: 'Notion',
              icon: const _NotionModeIcon(),
              selected: activeMode == _AvaAiWorkspaceMode.notion,
              onTap: () => onSelect(_AvaAiWorkspaceMode.notion),
            ),
            const SizedBox(height: 10),
            _WorkspaceModeButton(
              label: '일정표',
              tooltip: '일정표',
              icon: const Icon(Icons.calendar_month_rounded, size: 22),
              selected: activeMode == _AvaAiWorkspaceMode.schedule,
              onTap: () => onSelect(_AvaAiWorkspaceMode.schedule),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceModeButton extends StatelessWidget {
  const _WorkspaceModeButton({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF344553);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 54,
          height: 62,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4F65C8) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? const Color(0xFF4156B5) : Colors.transparent,
            ),
          ),
          child: IconTheme(
            data: IconThemeData(color: foreground),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvaAiModeIcon extends StatelessWidget {
  const _AvaAiModeIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? const Color(0xFF102040);
    return SizedBox.square(
      dimension: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.7),
        ),
        child: Center(
          child: Text(
            'AVA',
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotionModeIcon extends StatelessWidget {
  const _NotionModeIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Colors.black;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        'N',
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _AvaAiWorkspacePanel extends StatelessWidget {
  const _AvaAiWorkspacePanel({
    required this.title,
    required this.items,
    required this.selectedPaths,
    required this.currentPath,
    required this.status,
    required this.busy,
    required this.dragging,
    required this.onOpenParent,
    required this.onBrowseRoot,
    required this.onCreateFile,
    required this.onPickFiles,
    required this.onSendSelected,
    required this.onOpenItem,
    required this.onEditItem,
    required this.onDeleteItem,
    required this.onSelectionChanged,
  });

  final String title;
  final List<AvaAiWorkspaceItemDto> items;
  final Set<String> selectedPaths;
  final String currentPath;
  final String status;
  final bool busy;
  final bool dragging;
  final VoidCallback? onOpenParent;
  final VoidCallback? onBrowseRoot;
  final VoidCallback? onCreateFile;
  final VoidCallback? onPickFiles;
  final VoidCallback? onSendSelected;
  final ValueChanged<AvaAiWorkspaceItemDto>? onOpenItem;
  final ValueChanged<AvaAiWorkspaceItemDto>? onEditItem;
  final ValueChanged<AvaAiWorkspaceItemDto>? onDeleteItem;
  final void Function(String path, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6F8),
        border: Border(left: BorderSide(color: _aiHeaderBorder)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFE9F0F5),
                  border: Border(bottom: BorderSide(color: _aiHeaderBorder)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspaces, color: Color(0xFF102040)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF102040),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '상위 폴더로 이동',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy ? null : onOpenParent,
                      icon: const Icon(Icons.arrow_upward, size: 20),
                    ),
                    IconButton(
                      tooltip: 'FORIVER_NAS (F:) 열기',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy ? null : onBrowseRoot,
                      icon: const Icon(Icons.folder_open, size: 20),
                    ),
                    IconButton(
                      tooltip: '파일/폴더 생성',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy ? null : onCreateFile,
                      icon: const Icon(Icons.note_add, size: 20),
                    ),
                    IconButton(
                      tooltip: '파일 추가',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy ? null : onPickFiles,
                      icon: const Icon(Icons.add, size: 22),
                    ),
                    IconButton(
                      tooltip: '채팅방으로 보내기',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy || selectedPaths.isEmpty
                          ? null
                          : onSendSelected,
                      icon: const Icon(Icons.send, size: 19),
                    ),
                  ],
                ),
              ),
              if (status.isNotEmpty || busy)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  color: const Color(0xFFEFF4F8),
                  child: Row(
                    children: [
                      if (busy)
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF8E8E8E),
                          ),
                        ),
                      if (busy) const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          status.isEmpty ? '작업공간을 불러오고 있습니다.' : status,
                          style: const TextStyle(
                            color: Color(0xFF425461),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (currentPath.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  color: const Color(0xFFF7FAFC),
                  child: Text(
                    'F:/$currentPath',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF60717C),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const _WorkspaceEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(14),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _WorkspaceItemCard(
                            item: item,
                            selected:
                                item.path.isNotEmpty &&
                                selectedPaths.contains(item.path),
                            onOpen: !item.isWorkspacePath || onOpenItem == null
                                ? null
                                : () => onOpenItem!(item),
                            onEdit: item.isWorkspacePath && onEditItem != null
                                ? () => onEditItem!(item)
                                : null,
                            onDelete:
                                item.isWorkspacePath && onDeleteItem != null
                                ? () => onDeleteItem!(item)
                                : null,
                            onSelected: item.isSendableFile
                                ? (selected) =>
                                      onSelectionChanged(item.path, selected)
                                : null,
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemCount: items.length,
                      ),
              ),
            ],
          ),
          if (dragging)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF102040).withValues(alpha: 0.72),
                ),
                child: const Center(
                  child: Text(
                    '파일을 작업공간에 놓을 수 있습니다.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceEmptyState extends StatelessWidget {
  const _WorkspaceEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Workspace',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF60717C),
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AvaAiNotionWorkspacePanel extends StatefulWidget {
  const _AvaAiNotionWorkspacePanel({
    required this.title,
    required this.results,
    required this.activePage,
    required this.status,
    required this.busy,
    required this.dragging,
    required this.onRefresh,
    required this.onOpenPage,
  });

  final String title;
  final List<AvaAiNotionPageDto> results;
  final AvaAiNotionPageDto? activePage;
  final String status;
  final bool busy;
  final bool dragging;
  final VoidCallback? onRefresh;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  State<_AvaAiNotionWorkspacePanel> createState() =>
      _AvaAiNotionWorkspacePanelState();
}

class _AvaAiNotionWorkspacePanelState
    extends State<_AvaAiNotionWorkspacePanel> {
  bool _listVisible = true;

  List<AvaAiNotionPageDto> get results => widget.results;

  AvaAiNotionPageDto? get activePage => widget.activePage;

  String get status => widget.status;

  bool get busy => widget.busy;

  bool get dragging => widget.dragging;

  ValueChanged<AvaAiNotionPageDto>? get onOpenPage => widget.onOpenPage;

  void _setListVisible(bool visible) {
    if (_listVisible == visible) {
      return;
    }
    setState(() {
      _listVisible = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF191919),
        border: Border(left: BorderSide(color: _aiHeaderBorder)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF191919),
                  border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
                ),
                child: Row(
                  children: [
                    const _NotionHeaderIcon(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Color(0xFFF0F0F0),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notion 새로고침',
                      onPressed: widget.busy ? null : widget.onRefresh,
                      color: const Color(0xFFB9B9B9),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              if (widget.status.isNotEmpty || widget.busy)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                  color: const Color(0xFF202020),
                  child: Row(
                    children: [
                      if (widget.busy)
                        const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF8E8E8E),
                          ),
                        ),
                      if (widget.busy) const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          status.isEmpty ? 'Notion 작업공간을 불러오고 있습니다.' : status,
                          style: const TextStyle(
                            color: Color(0xFFCFCFCF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: _listVisible ? 260 : 0,
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.centerRight,
                              widthFactor: _listVisible ? 1 : 0,
                              child: SizedBox(
                                width: 260,
                                child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF202020),
                                    border: Border(
                                      right: BorderSide(
                                        color: Color(0xFF313131),
                                      ),
                                    ),
                                  ),
                                  child: results.isEmpty
                                      ? const _NotionResultEmpty()
                                      : ListView.separated(
                                          padding: const EdgeInsets.all(10),
                                          itemBuilder: (context, index) {
                                            final page = results[index];
                                            return _NotionResultTile(
                                              page: page,
                                              active: activePage?.id == page.id,
                                              onTap: onOpenPage == null
                                                  ? null
                                                  : () => onOpenPage!(page),
                                            );
                                          },
                                          separatorBuilder: (_, _) =>
                                              const SizedBox(height: 2),
                                          itemCount: results.length,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) => _setListVisible(false),
                            child: activePage == null
                                ? const _NotionPageEmpty()
                                : _NotionPageCanvas(
                                    page: activePage!,
                                    onOpenPage: onOpenPage,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      left: _listVisible ? 247 : 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NotionListToggle(
                          visible: _listVisible,
                          onPressed: () => _setListVisible(!_listVisible),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (dragging)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                ),
                child: const Center(
                  child: Text(
                    '파일을 선택한 Notion 페이지에 놓을 수 있습니다.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvaAiScheduleWorkspacePanel extends StatelessWidget {
  const _AvaAiScheduleWorkspacePanel({
    required this.title,
    required this.workspace,
    required this.busy,
    required this.onRefresh,
    required this.onSelectEvent,
  });

  final String title;
  final AvaAiCalendarWorkspaceDto workspace;
  final bool busy;
  final VoidCallback? onRefresh;
  final ValueChanged<AvaAiCalendarEventCardDto> onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FB),
        border: Border(left: BorderSide(color: _aiHeaderBorder)),
      ),
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFE9F0F5),
              border: Border(bottom: BorderSide(color: _aiHeaderBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF102040),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  style: _workspaceHeaderButtonStyle,
                  onPressed: busy ? null : onRefresh,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (workspace.hasSignal)
            Expanded(
              child: _CalendarWorkspaceContent(
                workspace: workspace,
                selected: workspace.selectedEvent(),
                onSelectEvent: onSelectEvent,
              ),
            ),
          if (!workspace.hasSignal)
            const Expanded(
              child: Center(
                child: Text(
                  '일정표 작업공간',
                  style: TextStyle(
                    color: Color(0xFF60717C),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarWorkspaceContent extends StatelessWidget {
  const _CalendarWorkspaceContent({
    required this.workspace,
    required this.selected,
    required this.onSelectEvent,
  });

  final AvaAiCalendarWorkspaceDto workspace;
  final AvaAiCalendarEventCardDto? selected;
  final ValueChanged<AvaAiCalendarEventCardDto> onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final list = _CalendarEventList(
          workspace: workspace,
          selectedId: selected?.id ?? '',
          onSelectEvent: onSelectEvent,
        );
        final detail = _CalendarEventDetail(event: selected);
        if (wide) {
          return Row(
            children: [
              SizedBox(width: 330, child: list),
              const VerticalDivider(width: 1, color: _aiHeaderBorder),
              Expanded(child: detail),
            ],
          );
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(height: 340, child: list),
            const Divider(height: 1, color: _aiHeaderBorder),
            SizedBox(height: 360, child: detail),
          ],
        );
      },
    );
  }
}

class _CalendarEventList extends StatelessWidget {
  const _CalendarEventList({
    required this.workspace,
    required this.selectedId,
    required this.onSelectEvent,
  });

  final AvaAiCalendarWorkspaceDto workspace;
  final String selectedId;
  final ValueChanged<AvaAiCalendarEventCardDto> onSelectEvent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE1E9EF))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workspace.summary?.title.isNotEmpty == true
                    ? workspace.summary!.title
                    : '일정표',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF102040),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  _CalendarBadge(
                    icon: Icons.event_available_rounded,
                    label:
                        '${workspace.summary?.totalCount ?? workspace.events.length}개',
                  ),
                  if (workspace.mutation)
                    const _CalendarBadge(
                      icon: Icons.verified_rounded,
                      label: '반영됨',
                    ),
                  if (workspace.requiresClarification)
                    const _CalendarBadge(
                      icon: Icons.help_rounded,
                      label: '확인 필요',
                    ),
                ],
              ),
              if (workspace.status.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  workspace.status,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF52616D),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (workspace.conflicts.isNotEmpty)
          _CalendarNoticeStrip(
            color: const Color(0xFFFFF2E8),
            textColor: const Color(0xFF8A4A10),
            text:
                '충돌 ${workspace.conflicts.length}개: ${workspace.conflicts.take(2).map((item) => item.title).join(', ')}',
          ),
        if (workspace.availability.isNotEmpty)
          _CalendarNoticeStrip(
            color: const Color(0xFFEAF7EF),
            textColor: const Color(0xFF23613C),
            text:
                '가능한 시간: ${workspace.availability.take(3).map((item) => _formatCalendarRange(item.startAt, item.endAt, false)).join(' / ')}',
          ),
        Expanded(
          child: workspace.events.isEmpty
              ? const Center(
                  child: Text(
                    '표시할 일정이 없습니다.',
                    style: TextStyle(
                      color: Color(0xFF6F808C),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: workspace.events.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final event = workspace.events[index];
                    return _CalendarEventTile(
                      event: event,
                      selected: event.id == selectedId,
                      onTap: () => onSelectEvent(event),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CalendarEventTile extends StatelessWidget {
  const _CalendarEventTile({
    required this.event,
    required this.selected,
    required this.onTap,
  });

  final AvaAiCalendarEventCardDto event;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE6F0FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4F7CFF)
                  : const Color(0xFFE1E9EF),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(
                  color: _calendarColor(event.color),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title.isEmpty ? '제목 없음' : event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF102040),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCalendarRange(
                        event.startAt,
                        event.endAt,
                        event.allDay,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF60717C),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _TinyCalendarChip(
                          event.statusLabel.isEmpty
                              ? event.status
                              : event.statusLabel,
                        ),
                        if (event.categoryName.isNotEmpty)
                          _TinyCalendarChip(event.categoryName),
                        if (event.hasAzoom)
                          const _TinyCalendarIcon(Icons.video_call_rounded),
                        if (event.hasChat)
                          const _TinyCalendarIcon(Icons.chat_bubble_rounded),
                        if (event.hasFiles)
                          const _TinyCalendarIcon(Icons.attach_file_rounded),
                        if (event.hasNotion)
                          const _TinyCalendarIcon(Icons.description_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarEventDetail extends StatelessWidget {
  const _CalendarEventDetail({required this.event});

  final AvaAiCalendarEventCardDto? event;

  @override
  Widget build(BuildContext context) {
    if (event == null) {
      return const Center(
        child: Text(
          '일정을 선택하세요.',
          style: TextStyle(
            color: Color(0xFF6F808C),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    final item = event!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _calendarColor(item.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title.isEmpty ? '제목 없음' : item.title,
                style: const TextStyle(
                  color: Color(0xFF102040),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _CalendarDetailRow(
          icon: Icons.schedule_rounded,
          label: '시간',
          value: _formatCalendarRange(item.startAt, item.endAt, item.allDay),
        ),
        _CalendarDetailRow(
          icon: Icons.flag_rounded,
          label: '상태',
          value: item.statusLabel.isEmpty ? item.status : item.statusLabel,
        ),
        if (item.categoryName.isNotEmpty)
          _CalendarDetailRow(
            icon: Icons.label_rounded,
            label: '카테고리',
            value: item.categoryName,
          ),
        if (item.location.isNotEmpty)
          _CalendarDetailRow(
            icon: Icons.place_rounded,
            label: '장소',
            value: item.location,
          ),
        if (item.description.isNotEmpty)
          _CalendarDetailRow(
            icon: Icons.notes_rounded,
            label: '설명',
            value: item.description,
          ),
        if (item.memo.isNotEmpty)
          _CalendarDetailRow(
            icon: Icons.sticky_note_2_rounded,
            label: '메모',
            value: item.memo,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.hasAzoom)
              const _CalendarActionChip(
                icon: Icons.video_call_rounded,
                label: 'AZOOM',
              ),
            if (item.hasChat)
              const _CalendarActionChip(
                icon: Icons.chat_bubble_rounded,
                label: '채팅방',
              ),
            if (item.hasFiles)
              const _CalendarActionChip(
                icon: Icons.folder_rounded,
                label: '파일',
              ),
            if (item.hasNotion)
              const _CalendarActionChip(
                icon: Icons.description_rounded,
                label: 'Notion',
              ),
          ],
        ),
      ],
    );
  }
}

class _CalendarDetailRow extends StatelessWidget {
  const _CalendarDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF52616D)),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF60717C),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF243645),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarNoticeStrip extends StatelessWidget {
  const _CalendarNoticeStrip({
    required this.color,
    required this.textColor,
    required this.text,
  });

  final Color color;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: color,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CalendarBadge extends StatelessWidget {
  const _CalendarBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF52616D)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF52616D),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyCalendarChip extends StatelessWidget {
  const _TinyCalendarChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F7),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF52616D),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TinyCalendarIcon extends StatelessWidget {
  const _TinyCalendarIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 15, color: const Color(0xFF52616D));
  }
}

class _CalendarActionChip extends StatelessWidget {
  const _CalendarActionChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD9E4EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF314453)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF314453),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Color _calendarColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.length == 6) {
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed != null) {
      return Color(0xFF000000 | parsed);
    }
  }
  return const Color(0xFF4F7CFF);
}

String _formatCalendarRange(DateTime? start, DateTime? end, bool allDay) {
  if (start == null || end == null) {
    return '시간 미정';
  }
  final localStart = start.toLocal();
  final localEnd = end.toLocal();
  if (allDay) {
    return '${localStart.month}/${localStart.day} - ${localEnd.month}/${localEnd.day}';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${localStart.month}/${localStart.day} ${two(localStart.hour)}:${two(localStart.minute)} - ${localEnd.month}/${localEnd.day} ${two(localEnd.hour)}:${two(localEnd.minute)}';
}

class _NotionHeaderIcon extends StatelessWidget {
  const _NotionHeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Color(0xFFEDEDED), width: 2),
      ),
      alignment: Alignment.center,
      child: const Text(
        'N',
        style: TextStyle(
          color: Color(0xFFEDEDED),
          fontSize: 15,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _NotionListToggle extends StatelessWidget {
  const _NotionListToggle({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF2B2B2B),
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 26,
          height: 64,
          child: Center(
            child: Text(
              visible ? '<' : '>',
              style: const TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotionResultEmpty extends StatelessWidget {
  const _NotionResultEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'AVA AI에게 Notion에서 찾을 문서를 말하면 결과가 여기에 표시됩니다.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFA8A8A8),
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NotionPageEmpty extends StatelessWidget {
  const _NotionPageEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Notion',
        style: TextStyle(
          color: Color(0xFF777777),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NotionResultTile extends StatelessWidget {
  const _NotionResultTile({
    required this.page,
    required this.active,
    required this.onTap,
  });

  final AvaAiNotionPageDto page;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF333333) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                page.icon.isEmpty
                    ? (page.object == 'database' ? '▦' : '□')
                    : page.icon,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFD2D2D2),
                  fontSize: 13,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title.isEmpty ? 'Untitled' : page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE6E6E6),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (page.subtitle.isNotEmpty)
                    Text(
                      page.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF9B9B9B),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotionPageCanvas extends StatefulWidget {
  const _NotionPageCanvas({required this.page, required this.onOpenPage});

  final AvaAiNotionPageDto page;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  State<_NotionPageCanvas> createState() => _NotionPageCanvasState();
}

class _NotionPageCanvasState extends State<_NotionPageCanvas> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF191919),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasWidth = math.max(constraints.maxWidth, 1120.0);
          return Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: canvasWidth,
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    child: _NotionPageDocument(
                      page: widget.page,
                      canvasWidth: canvasWidth,
                      onOpenPage: widget.onOpenPage,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotionPageDocument extends StatelessWidget {
  const _NotionPageDocument({
    required this.page,
    required this.canvasWidth,
    required this.onOpenPage,
  });

  final AvaAiNotionPageDto page;
  final double canvasWidth;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final hasBlocks = page.blocks.isNotEmpty;
    final showProperties =
        page.object != 'database' && page.properties.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page.coverUrl.isNotEmpty)
          _NotionCover(url: page.coverUrl, width: canvasWidth),
        Padding(
          padding: EdgeInsets.fromLTRB(
            64,
            page.coverUrl.isEmpty ? 52 : 48,
            64,
            80,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.icon.isNotEmpty) ...[
                  Text(page.icon, style: const TextStyle(fontSize: 38)),
                  const SizedBox(height: 8),
                ],
                Text(
                  page.title.isEmpty ? 'Untitled' : page.title,
                  style: const TextStyle(
                    color: Color(0xFFEFEFEF),
                    fontSize: 30,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (showProperties) ...[
                  const SizedBox(height: 22),
                  _NotionPropertyRows(properties: page.properties),
                ],
                if (hasBlocks) ...[
                  const SizedBox(height: 28),
                  _NotionBlockChildren(
                    blocks: page.blocks,
                    onOpenPage: onOpenPage,
                  ),
                ] else if (page.children.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _NotionDatabaseGallery(
                    database: page,
                    onOpenPage: onOpenPage,
                  ),
                ] else if (page.content.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    page.content,
                    style: const TextStyle(
                      color: Color(0xFFCACACA),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NotionCover extends StatelessWidget {
  const _NotionCover({required this.url, required this.width});

  final String url;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 136,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF303030)),
      ),
    );
  }
}

class _NotionPropertyRows extends StatelessWidget {
  const _NotionPropertyRows({required this.properties});

  final List<AvaAiNotionPropertyDto> properties;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final property in properties.where(
          (item) => item.value.isNotEmpty,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 132,
                  child: Text(
                    property.name,
                    style: const TextStyle(
                      color: Color(0xFF8D8D8D),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    property.value,
                    style: const TextStyle(
                      color: Color(0xFFD8D8D8),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NotionBlockChildren extends StatelessWidget {
  const _NotionBlockChildren({required this.blocks, required this.onOpenPage});

  final List<AvaAiNotionBlockDto> blocks;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          _NotionRenderedBlock(block: block, onOpenPage: onOpenPage),
      ],
    );
  }
}

class _NotionRenderedBlock extends StatelessWidget {
  const _NotionRenderedBlock({required this.block, required this.onOpenPage});

  final AvaAiNotionBlockDto block;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    if (block.type == 'column_list') {
      return _NotionColumnList(block: block, onOpenPage: onOpenPage);
    }
    if (block.type == 'column') {
      return _NotionBlockChildren(
        blocks: block.children,
        onOpenPage: onOpenPage,
      );
    }
    if (block.type == 'divider') {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: Color(0xFF373737)),
      );
    }
    if (block.type == 'callout') {
      return _NotionCallout(block: block);
    }
    if (block.type == 'child_page') {
      final page = _notionPageTargetFromBlock(block, object: 'page');
      return _NotionLinkRow(
        icon: block.icon.isEmpty ? '□' : block.icon,
        text: block.text,
        onTap: page.id.isEmpty || onOpenPage == null
            ? null
            : () => onOpenPage!(page),
      );
    }
    if (block.type == 'child_database') {
      final database = block.database;
      if (database != null && block.text.toLowerCase() == 'untitled') {
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 14),
          child: _NotionDatabaseGallery(
            database: database,
            onOpenPage: onOpenPage,
          ),
        );
      }
      final target =
          database ?? _notionPageTargetFromBlock(block, object: 'database');
      return _NotionLinkRow(
        icon: block.icon.isEmpty ? '▦' : block.icon,
        text: block.text,
        onTap: target.id.isEmpty || onOpenPage == null
            ? null
            : () => onOpenPage!(target),
      );
    }
    if (_isExternalNotionBlock(block)) {
      final targetUrl = block.url.isEmpty ? block.text : block.url;
      if (targetUrl.isNotEmpty) {
        return _NotionLinkRow(
          icon: '↗',
          text: block.text.isEmpty ? targetUrl : block.text,
          onTap: () => _launchExternalUrl(targetUrl),
        );
      }
    }
    if (block.type == 'image' && block.url.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            block.url,
            width: 520,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    final text = block.text.isEmpty && block.url.isNotEmpty
        ? block.url
        : block.text;
    if (text.isEmpty && block.children.isEmpty) {
      return const SizedBox(height: 8);
    }
    final prefix = switch (block.type) {
      'bulleted_list_item' => '- ',
      'numbered_list_item' => '1. ',
      'quote' => '> ',
      'to_do' => block.checked ? '[x] ' : '[ ] ',
      'file' => 'File ',
      'pdf' => 'PDF ',
      _ => '',
    };
    Widget content = Padding(
      padding: EdgeInsets.only(
        left: block.type == 'quote' ? 12 : 0,
        top: 3,
        bottom: 3,
      ),
      child: Text('$prefix$text', style: _notionBlockTextStyle(block.type)),
    );
    if (block.url.isNotEmpty) {
      content = _NotionClickable(
        onTap: () => _launchExternalUrl(block.url),
        borderRadius: BorderRadius.circular(4),
        child: content,
      );
    }
    if (block.children.isEmpty) {
      return content;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: _NotionBlockChildren(
              blocks: block.children,
              onOpenPage: onOpenPage,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotionCallout extends StatelessWidget {
  const _NotionCallout({required this.block});

  final AvaAiNotionBlockDto block;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A38),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(block.icon.isEmpty ? '💡' : block.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              block.text,
              style: const TextStyle(
                color: Color(0xFFE4E4E4),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotionLinkRow extends StatelessWidget {
  const _NotionLinkRow({required this.icon, required this.text, this.onTap});

  final String icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _NotionClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              child: Text(icon, style: const TextStyle(fontSize: 14)),
            ),
            Flexible(
              child: Text(
                text.isEmpty ? 'Untitled' : text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE6E6E6),
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotionColumnList extends StatelessWidget {
  const _NotionColumnList({required this.block, required this.onOpenPage});

  final AvaAiNotionBlockDto block;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final columns = block.children
        .where((child) => child.type == 'column')
        .toList(growable: false);
    final visibleColumns = columns.isEmpty ? block.children : columns;
    if (visibleColumns.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < visibleColumns.length; index++) ...[
            Expanded(
              flex: visibleColumns.length == 2 ? (index == 0 ? 31 : 69) : 1,
              child: _NotionBlockChildren(
                blocks: visibleColumns[index].type == 'column'
                    ? visibleColumns[index].children
                    : [visibleColumns[index]],
                onOpenPage: onOpenPage,
              ),
            ),
            if (index != visibleColumns.length - 1) const SizedBox(width: 46),
          ],
        ],
      ),
    );
  }
}

class _NotionDatabaseGallery extends StatelessWidget {
  const _NotionDatabaseGallery({
    required this.database,
    required this.onOpenPage,
  });

  final AvaAiNotionPageDto database;
  final ValueChanged<AvaAiNotionPageDto>? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final rows = database.children;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _NotionClickable(
              onTap: onOpenPage == null ? null : () => onOpenPage!(database),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  database.title == 'Teams' ? 'Global Offices' : database.title,
                  style: const TextStyle(
                    color: Color(0xFFE7E7E7),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.filter_list_rounded,
              color: Color(0xFF999999),
              size: 16,
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.swap_vert_rounded,
              color: Color(0xFF999999),
              size: 16,
            ),
            const SizedBox(width: 12),
            _NotionClickable(
              onTap: onOpenPage == null ? null : () => onOpenPage!(database),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2383E2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '새로 만들기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const Text(
            '표시할 데이터베이스 항목이 없습니다.',
            style: TextStyle(color: Color(0xFF9B9B9B), fontSize: 13),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final row in rows)
                _NotionGalleryCard(
                  row: row,
                  onTap: onOpenPage == null ? null : () => onOpenPage!(row),
                ),
            ],
          ),
      ],
    );
  }
}

class _NotionGalleryCard extends StatelessWidget {
  const _NotionGalleryCard({required this.row, required this.onTap});

  final AvaAiNotionPageDto row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chips = _notionTags(row);
    return _NotionClickable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 142,
        height: 154,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF353535)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 72,
              width: double.infinity,
              child: row.coverUrl.isEmpty
                  ? const ColoredBox(color: Color(0xFF303030))
                  : Image.network(
                      row.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF303030)),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                children: [
                  if (row.icon.isNotEmpty) ...[
                    Text(row.icon, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      row.title.isEmpty ? 'Untitled' : row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFEDEDED),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final chip in chips.take(5))
                      _NotionTagChip(label: chip.key, color: chip.value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotionClickable extends StatelessWidget {
  const _NotionClickable({
    required this.child,
    required this.onTap,
    required this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          hoverColor: Colors.white.withValues(alpha: 0.06),
          splashColor: Colors.white.withValues(alpha: 0.08),
          highlightColor: Colors.white.withValues(alpha: 0.04),
          child: child,
        ),
      ),
    );
  }
}

AvaAiNotionPageDto _notionPageTargetFromBlock(
  AvaAiNotionBlockDto block, {
  required String object,
}) {
  return AvaAiNotionPageDto(
    id: block.id,
    object: object,
    title: block.text.isEmpty ? 'Untitled' : block.text,
    subtitle: object == 'database' ? 'Database' : 'Page',
    url: block.url,
    icon: block.icon,
    coverUrl: '',
    content: '',
    properties: const [],
    blocks: const [],
    children: const [],
    updatedAt: null,
  );
}

bool _isExternalNotionBlock(AvaAiNotionBlockDto block) {
  return switch (block.type) {
    'bookmark' ||
    'embed' ||
    'link_preview' ||
    'file' ||
    'pdf' ||
    'video' => true,
    _ => false,
  };
}

void _launchExternalUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return;
  }
  unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
}

class _NotionTagChip extends StatelessWidget {
  const _NotionTagChip({required this.label, required this.color});

  final String label;
  final String color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _notionTagBackground(color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _notionTagForeground(color),
          fontSize: 9,
          height: 1.05,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

TextStyle _notionBlockTextStyle(String type) {
  return switch (type) {
    'heading_1' => const TextStyle(
      color: Color(0xFFEFEFEF),
      fontSize: 26,
      height: 1.25,
      fontWeight: FontWeight.w900,
    ),
    'heading_2' => const TextStyle(
      color: Color(0xFFEFEFEF),
      fontSize: 18,
      height: 1.28,
      fontWeight: FontWeight.w900,
    ),
    'heading_3' => const TextStyle(
      color: Color(0xFFEFEFEF),
      fontSize: 16,
      height: 1.35,
      fontWeight: FontWeight.w900,
    ),
    _ => const TextStyle(color: Color(0xFFD6D6D6), fontSize: 14, height: 1.45),
  };
}

List<MapEntry<String, String>> _notionTags(AvaAiNotionPageDto row) {
  final chips = <MapEntry<String, String>>[];
  for (final property in row.properties) {
    if (property.value.isEmpty) {
      continue;
    }
    if (property.type != 'multi_select' &&
        property.type != 'select' &&
        property.type != 'status') {
      continue;
    }
    for (final value in property.value.split(',')) {
      final label = value.trim();
      if (label.isNotEmpty) {
        chips.add(MapEntry(label, property.color));
      }
    }
  }
  return chips;
}

Color _notionTagBackground(String color) {
  return switch (color) {
    'red' => const Color(0xFF5D2B2A),
    'orange' => const Color(0xFF5B3A1E),
    'yellow' => const Color(0xFF554A24),
    'green' => const Color(0xFF2E4A33),
    'blue' => const Color(0xFF28456B),
    'purple' => const Color(0xFF46346A),
    'pink' => const Color(0xFF58304A),
    'brown' => const Color(0xFF4A3728),
    'gray' => const Color(0xFF3B3B3B),
    _ => const Color(0xFF3A3A3A),
  };
}

Color _notionTagForeground(String color) {
  return switch (color) {
    'red' => const Color(0xFFFFA6A0),
    'orange' => const Color(0xFFFFC184),
    'yellow' => const Color(0xFFFFD76E),
    'green' => const Color(0xFFA5D9A7),
    'blue' => const Color(0xFFA8C7F8),
    'purple' => const Color(0xFFD2BBFF),
    'pink' => const Color(0xFFFFB6DA),
    'brown' => const Color(0xFFD9B48E),
    'gray' => const Color(0xFFD0D0D0),
    _ => const Color(0xFFD6D6D6),
  };
}

class _WorkspaceItemCard extends ConsumerWidget {
  const _WorkspaceItemCard({
    required this.item,
    required this.selected,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onSelected,
  });

  final AvaAiWorkspaceItemDto item;
  final bool selected;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = _workspaceImage(
      item,
      ref.watch(appConfigProvider).apiBaseUrl,
      ref.watch(authControllerProvider).value?.session?.accessToken ?? '',
    );
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD7E0E6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _workspaceIcon(item.type),
                    color: const Color(0xFF4F65C8),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? item.path : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF17222B),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF667782),
                              fontSize: 11,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onOpen != null)
                    IconButton(
                      tooltip: item.isDirectory ? '폴더 열기' : '파일 보기',
                      onPressed: onOpen,
                      icon: Icon(
                        item.isDirectory
                            ? Icons.chevron_right
                            : Icons.visibility,
                        size: 19,
                      ),
                    ),
                  if (onEdit != null)
                    IconButton(
                      tooltip: '?섏젙',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 17),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: '삭제',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  if (onSelected != null)
                    Checkbox(
                      value: selected,
                      onChanged: (value) => onSelected!(value ?? false),
                    ),
                ],
              ),
              if (image != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 130,
                    width: double.infinity,
                    child: image,
                  ),
                ),
              ],
              if (item.content.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item.content,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2A32),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              if (item.url.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF246BCE),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _workspaceIcon(String type) {
  return switch (type) {
    'directory' => Icons.folder,
    'web' => Icons.travel_explore,
    'chat_message' => Icons.chat_bubble,
    'chat_image' => Icons.image,
    'chat_file' => Icons.attach_file,
    'chat_room' => Icons.forum,
    'user_profile' => Icons.person,
    'meeting_batch' => Icons.description,
    _ => Icons.insert_drive_file,
  };
}

Widget? _workspaceImage(
  AvaAiWorkspaceItemDto item,
  String apiBaseUrl,
  String accessToken,
) {
  if (item.imageUrl.isEmpty) {
    return null;
  }
  if (item.imageUrl.startsWith('file:')) {
    return Image.file(
      File.fromUri(Uri.parse(item.imageUrl)),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE3E8ED)),
    );
  }
  final imageUrl = _absoluteWorkspaceUrl(apiBaseUrl, item.imageUrl);
  final headers =
      _workspaceImageNeedsAuth(item.imageUrl, apiBaseUrl) &&
          accessToken.isNotEmpty
      ? {'Authorization': 'Bearer $accessToken'}
      : null;
  return Image.network(
    imageUrl,
    headers: headers,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE3E8ED)),
  );
}

String _absoluteWorkspaceUrl(String apiBaseUrl, String value) {
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  final base = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

bool _workspaceImageNeedsAuth(String value, String apiBaseUrl) {
  if (value.startsWith('/')) {
    return true;
  }
  final normalizedBase = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  return value.startsWith(normalizedBase);
}

bool _isTextWorkspaceFile(AvaAiWorkspaceItemDto item) {
  if (!item.isWorkspaceFile) {
    return false;
  }
  final value = (item.title.isNotEmpty ? item.title : item.path).toLowerCase();
  const textExtensions = {
    '.txt',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.log',
    '.xml',
    '.html',
    '.htm',
    '.css',
    '.js',
    '.ts',
    '.dart',
    '.java',
    '.kt',
    '.py',
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.cs',
    '.go',
    '.rs',
    '.sql',
    '.ini',
    '.cfg',
    '.conf',
    '.ps1',
    '.bat',
    '.cmd',
    '.sh',
    '.ino',
  };
  return textExtensions.any(value.endsWith);
}

String _safeWorkspaceFileName(String value) {
  final rawName = value.split(RegExp(r'[\\/]')).last.trim();
  final baseName = rawName.isEmpty ? 'workspace-file' : rawName;
  return baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
}

String _foriverNasLocalPath(String workspacePath) {
  var normalized = workspacePath.trim().replaceAll('/', Platform.pathSeparator);
  normalized = normalized.replaceAll('\\', Platform.pathSeparator);
  while (normalized.startsWith(Platform.pathSeparator)) {
    normalized = normalized.substring(1);
  }
  if (RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
    return normalized;
  }
  return 'F:${Platform.pathSeparator}$normalized';
}

Future<Process> _openWindowsPath(String path) {
  return Process.start('rundll32.exe', ['url.dll,FileProtocolHandler', path]);
}

String _downloadsDirectoryPath() {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile != null && userProfile.trim().isNotEmpty) {
    return '${userProfile.trim()}${Platform.pathSeparator}Downloads';
  }
  return '${Directory.current.path}${Platform.pathSeparator}Downloads';
}

Future<String> _uniqueDownloadPath(
  String directoryPath,
  String fileName,
) async {
  final separator = Platform.pathSeparator;
  final sanitizedName = fileName.trim().isEmpty ? 'workspace-file' : fileName;
  var candidate = '$directoryPath$separator$sanitizedName';
  if (!await File(candidate).exists()) {
    return candidate;
  }

  final dotIndex = sanitizedName.lastIndexOf('.');
  final hasExtension = dotIndex > 0 && dotIndex < sanitizedName.length - 1;
  final name = hasExtension
      ? sanitizedName.substring(0, dotIndex)
      : sanitizedName;
  final extension = hasExtension ? sanitizedName.substring(dotIndex) : '';
  var index = 1;
  while (true) {
    candidate = '$directoryPath$separator$name ($index)$extension';
    if (!await File(candidate).exists()) {
      return candidate;
    }
    index += 1;
  }
}

String _parentWorkspacePath(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final index = normalized.lastIndexOf('/');
  if (index <= 0) {
    return '';
  }
  return normalized.substring(0, index);
}

Future<List<_AvaAiChatSnapshot>> _readChatSnapshots(String userKey) async {
  final file = _chatSnapshotsFile(userKey);
  if (!await file.exists()) {
    return const [];
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) {
    return const [];
  }
  final snapshots = [
    for (final item in decoded)
      if (item is Map)
        _AvaAiChatSnapshot.fromJson(item.cast<String, dynamic>()),
  ]..sort((left, right) => right.savedAt.compareTo(left.savedAt));
  return snapshots;
}

Future<void> _writeChatSnapshots(
  String userKey,
  List<_AvaAiChatSnapshot> snapshots,
) async {
  final file = _chatSnapshotsFile(userKey);
  await file.parent.create(recursive: true);
  final limited = snapshots.take(80).toList();
  await file.writeAsString(
    jsonEncode([for (final snapshot in limited) snapshot.toJson()]),
  );
}

File _chatSnapshotsFile(String userKey) {
  final appData = Platform.environment['APPDATA'];
  final base = appData == null || appData.isEmpty
      ? Directory.systemTemp.path
      : appData;
  final safeKey = _safeWorkspaceFileName(userKey).replaceAll('.', '_');
  return File(
    '$base${Platform.pathSeparator}AVA${Platform.pathSeparator}ava_ai_chat_sessions_$safeKey.json',
  );
}

class _AvaAiWorkspaceStateSnapshot {
  const _AvaAiWorkspaceStateSnapshot({
    required this.workspacePath,
    required this.workspaceStatus,
    required this.selectedPaths,
    required this.items,
    required this.calendarWorkspace,
  });

  final String workspacePath;
  final String workspaceStatus;
  final Set<String> selectedPaths;
  final List<AvaAiWorkspaceItemDto> items;
  final AvaAiCalendarWorkspaceDto calendarWorkspace;
}

Future<_AvaAiWorkspaceStateSnapshot?> _readWorkspaceState(
  String userKey,
) async {
  final file = _workspaceStateFile(userKey);
  if (!await file.exists()) {
    return null;
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    return null;
  }
  final json = decoded.cast<String, dynamic>();
  return _AvaAiWorkspaceStateSnapshot(
    workspacePath: json['workspacePath'] as String? ?? '',
    workspaceStatus: json['workspaceStatus'] as String? ?? '',
    selectedPaths: {
      for (final path in json['selectedPaths'] as List<dynamic>? ?? const [])
        if (path is String) path,
    },
    items: [
      for (final item in json['items'] as List<dynamic>? ?? const [])
        if (item is Map)
          AvaAiWorkspaceItemDto.fromJson(item.cast<String, dynamic>()),
    ],
    calendarWorkspace: json['calendarWorkspace'] is Map
        ? AvaAiCalendarWorkspaceDto.fromJson(
            (json['calendarWorkspace'] as Map).cast<String, dynamic>(),
          )
        : AvaAiCalendarWorkspaceDto.empty(),
  );
}

Map<String, dynamic> _workspaceItemToJson(AvaAiWorkspaceItemDto item) {
  return {
    'type': item.type,
    'title': item.title,
    'subtitle': item.subtitle,
    'path': item.path,
    'url': item.url,
    'imageUrl': item.imageUrl,
    'content': item.content,
    if (item.size != null) 'size': item.size,
    if (item.updatedAt != null) 'updatedAt': item.updatedAt!.toIso8601String(),
    'roomCode': item.roomCode,
  };
}

File _workspaceStateFile(String userKey) {
  final appData = Platform.environment['APPDATA'];
  final base = appData == null || appData.isEmpty
      ? Directory.systemTemp.path
      : appData;
  final safeKey = _safeWorkspaceFileName(userKey).replaceAll('.', '_');
  return File(
    '$base${Platform.pathSeparator}AVA${Platform.pathSeparator}ava_ai_workspace_state_$safeKey.json',
  );
}

class _WorkspaceFileDraft {
  const _WorkspaceFileDraft({
    required this.path,
    required this.content,
    required this.isDirectory,
  });

  final String path;
  final String content;
  final bool isDirectory;
}

Future<_WorkspaceFileDraft?> _showWorkspaceFileDialog(
  BuildContext context, {
  required String title,
  required String initialPath,
  String initialContent = '',
  bool pathEditable = true,
  bool allowDirectory = false,
  bool showContent = true,
}) async {
  final pathController = TextEditingController(text: initialPath);
  final contentController = TextEditingController(text: initialContent);
  var isDirectory = false;
  return showDialog<_WorkspaceFileDraft>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AvaDialog(
            title: title,
            icon: const Icon(
              Icons.description_outlined,
              color: Color(0xFF4F65C8),
              size: 24,
            ),
            width: 500,
            actions: [
              AvaDialogButton(
                label: '취소',
                onPressed: () => Navigator.of(context).pop(),
              ),
              AvaDialogButton(
                label: '저장',
                filled: true,
                onPressed: () {
                  final path = pathController.text.trim();
                  if (path.isEmpty) {
                    return;
                  }
                  Navigator.of(context).pop(
                    _WorkspaceFileDraft(
                      path: path,
                      content: contentController.text,
                      isDirectory: isDirectory,
                    ),
                  );
                },
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pathController,
                  enabled: pathEditable,
                  decoration: const InputDecoration(
                    labelText: 'F:/ 기준 경로',
                    hintText: '예: notes/todo.txt',
                  ),
                ),
                if (allowDirectory) ...[
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: isDirectory,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('폴더로 만들기'),
                    onChanged: (value) =>
                        setDialogState(() => isDirectory = value ?? false),
                  ),
                ],
                if (showContent && !isDirectory) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

Future<bool> _confirmWorkspaceDelete(
  BuildContext context,
  AvaAiWorkspaceItemDto item,
) async {
  return showAvaConfirmDialog(
    context,
    title: '파일 삭제',
    message: '선택한 파일을 삭제할까요?\\nF:/${item.path}',
    confirmLabel: '삭제',
    destructive: true,
  );
}

class _WorkspaceSendDraft {
  const _WorkspaceSendDraft({
    required this.roomCode,
    required this.targetName,
    required this.message,
  });

  final String roomCode;
  final String targetName;
  final String message;
}

Future<_WorkspaceSendDraft?> _showWorkspaceSendDialog(
  BuildContext context,
  WidgetRef ref,
  String accessToken,
) async {
  final rooms = await ref.read(chatApiProvider).rooms(accessToken);
  if (!context.mounted) {
    return null;
  }
  final messageController = TextEditingController();
  String? selectedRoomCode = rooms.isNotEmpty ? rooms.first.code : null;
  return showDialog<_WorkspaceSendDraft>(
    context: context,
    builder: (context) {
      return AvaDialog(
        title: '채팅방으로 보내기',
        subtitle: '선택한 작업공간 파일을 채팅방에 전송합니다.',
        icon: const Icon(
          Icons.send_rounded,
          color: Color(0xFF4F65C8),
          size: 24,
        ),
        width: 420,
        actions: [
          AvaDialogButton(
            label: '취소',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AvaDialogButton(
            label: '전송',
            filled: true,
            onPressed: selectedRoomCode == null
                ? null
                : () {
                    Navigator.of(context).pop(
                      _WorkspaceSendDraft(
                        roomCode: selectedRoomCode ?? '',
                        targetName: '',
                        message: messageController.text.trim(),
                      ),
                    );
                  },
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedRoomCode,
              items: [
                for (final room in rooms)
                  DropdownMenuItem(value: room.code, child: Text(room.title)),
              ],
              onChanged: (value) => selectedRoomCode = value,
              decoration: const InputDecoration(labelText: '채팅방'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '함께 보낼 메시지',
                hintText: '여기에 첨부 파일입니다.',
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<List<String>> _pickWorkspaceFiles(BuildContext context) async {
  if (!Platform.isWindows) {
    showAvaToast(context, '파일 선택은 Windows에서만 지원합니다.');
    return const [];
  }
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "작업공간 파일 선택"
$dialog.Multiselect = $true
$dialog.Filter = "All files (*.*)|*.*"
$dialog.RestoreDirectory = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  foreach ($fileName in $dialog.FileNames) {
    [Console]::WriteLine([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($fileName)))
  }
}
''';
  try {
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-Command', script],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      return const [];
    }
    return [
      for (final line in result.stdout.toString().split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty) utf8.decode(base64.decode(line.trim())),
    ];
  } on Object catch (error) {
    if (context.mounted) {
      showAvaToast(context, authErrorMessage(error));
    }
    return const [];
  }
}

class _AvaAiHeader extends StatelessWidget {
  const _AvaAiHeader({
    required this.busy,
    required this.onPreviousChat,
    required this.onNewChat,
    required this.onWorkspace,
  });

  final bool busy;
  final VoidCallback? onPreviousChat;
  final VoidCallback? onNewChat;
  final VoidCallback? onWorkspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: const BoxDecoration(
        color: _aiHeaderBackground,
        border: Border(bottom: BorderSide(color: _aiHeaderBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          const _AvaLogoAvatar(size: 34),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'AVA AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _AvaAiHeaderAction(
            label: '이전 채팅',
            onPressed: busy ? null : onPreviousChat,
          ),
          const SizedBox(width: 6),
          _AvaAiHeaderAction(label: '새 채팅', onPressed: busy ? null : onNewChat),
          if (onWorkspace != null) ...[
            const SizedBox(width: 6),
            _AvaAiHeaderAction(
              label: '\uC791\uC5C5\uACF5\uAC04',
              onPressed: busy ? null : onWorkspace,
            ),
          ],
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF38B75E),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaAiHeaderAction extends StatelessWidget {
  const _AvaAiHeaderAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        foregroundColor: const Color(0xFF102040),
        disabledForegroundColor: const Color(0xFF8295A2),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

class _PreviousChatSnapshotTile extends StatelessWidget {
  const _PreviousChatSnapshotTile({
    required this.snapshot,
    required this.onOpen,
    required this.onDelete,
  });

  final _AvaAiChatSnapshot snapshot;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7E0E6)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0xFFD7E6F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 18,
                  color: Color(0xFF4F65C8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF102040),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatArchiveTime(snapshot.savedAt)} · ${snapshot.messages.length}개 메시지',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5E7182),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '삭제',
                onPressed: onDelete,
                color: const Color(0xFFE84D5B),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvaAiMessagesView extends StatelessWidget {
  const _AvaAiMessagesView({
    required this.controller,
    required this.messages,
    required this.loadingHistory,
    required this.sending,
    required this.thinkingStatus,
    required this.loadError,
    required this.onRetry,
  });

  final ScrollController controller;
  final List<_AvaAiUiMessage> messages;
  final bool loadingHistory;
  final bool sending;
  final String thinkingStatus;
  final Object? loadError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loadingHistory && messages.isEmpty) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (loadError != null && messages.isEmpty) {
      return Center(
        child: IconButton(
          tooltip: '다시 불러오기',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, color: Color(0xFF263238)),
        ),
      );
    }

    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: ListView.separated(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return _AvaAiTypingBubble(status: thinkingStatus);
          }
          return _AvaAiMessageBubble(message: messages[index]);
        },
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemCount: messages.length + (sending ? 1 : 0),
      ),
    );
  }
}

class _AvaAiMessageBubble extends StatelessWidget {
  const _AvaAiMessageBubble({required this.message});

  final _AvaAiUiMessage message;

  @override
  Widget build(BuildContext context) {
    return message.isUser
        ? _MineAiMessage(message: message)
        : _AssistantAiMessage(message: message);
  }
}

class _AssistantAiMessage extends StatelessWidget {
  const _AssistantAiMessage({required this.message});

  final _AvaAiUiMessage message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AvaLogoAvatar(size: 38),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AVA AI',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          child: _AiBubbleSurface(
                            color: Colors.white,
                            content: message.content,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _MessageTime(time: _formatTime(message.createdAt)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MineAiMessage extends StatelessWidget {
  const _MineAiMessage({required this.message});

  final _AvaAiUiMessage message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.68;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.failed)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.error_outline,
                  size: 15,
                  color: Color(0xFFC62828),
                ),
              ),
            _MessageTime(time: _formatTime(message.createdAt)),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                child: Opacity(
                  opacity: message.pending ? 0.72 : 1,
                  child: _AiBubbleSurface(
                    color: _mineBubbleColor,
                    content: message.content,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AiBubbleSurface extends StatelessWidget {
  const _AiBubbleSurface({required this.color, required this.content});

  final Color color;
  final String content;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SelectableText(
          content,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            height: 1.34,
          ),
        ),
      ),
    );
  }
}

class _AvaAiTypingBubble extends StatelessWidget {
  const _AvaAiTypingBubble({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final statusText = status.trim().isEmpty ? '응답을 준비하고 있습니다.' : status;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AvaLogoAvatar(size: 38),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AVA AI',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: SizedBox(width: 34, height: 14, child: _TypingDots()),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  statusText,
                  key: ValueKey(statusText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF5E7182),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var index = 0; index < 3; index++)
              Opacity(
                opacity: 0.32 + 0.68 * _dotValue(index),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF4D6370),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 7),
                ),
              ),
          ],
        );
      },
    );
  }

  double _dotValue(int index) {
    final shifted = (_controller.value + index * 0.22) % 1;
    return shifted < 0.5 ? shifted * 2 : (1 - shifted) * 2;
  }
}

class _AvaAiComposer extends StatefulWidget {
  const _AvaAiComposer({
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_AvaAiComposer> createState() => _AvaAiComposerState();
}

class _AvaAiComposerState extends State<_AvaAiComposer> {
  late final FocusNode _focusNode;
  bool _submittingFromNewline = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter) ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.enabled && !widget.sending) {
      widget.onSend();
    }
    return KeyEventResult.handled;
  }

  void _handleTextChanged(String value) {
    if (_submittingFromNewline || !value.contains('\n')) {
      return;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return;
    }
    _submittingFromNewline = true;
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\n', ' ');
    widget.controller.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _submittingFromNewline = false;
      if (mounted && widget.enabled && !widget.sending) {
        widget.onSend();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42, maxHeight: 128),
              child: TextField(
                focusNode: _focusNode,
                controller: widget.controller,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                cursorColor: Colors.black,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  height: 1.3,
                ),
                onChanged: _handleTextChanged,
                decoration: const InputDecoration(
                  hintText: '메시지 입력',
                  hintStyle: TextStyle(color: Color(0xFF9A9A9A)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 42,
            height: 42,
            child: FilledButton(
              onPressed: widget.enabled && !widget.sending
                  ? widget.onSend
                  : null,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: _mineBubbleColor,
                disabledBackgroundColor: const Color(0xFFE6E6E6),
                foregroundColor: Colors.black,
                disabledForegroundColor: const Color(0xFF8C8C8C),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: widget.sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Color(0xFF555555),
                      ),
                    )
                  : const Icon(Icons.arrow_upward, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaLogoAvatar extends StatelessWidget {
  const _AvaLogoAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Image.asset('assets/images/ava_app_icon.png', fit: BoxFit.cover),
      ),
    );
  }
}

class _MessageTime extends StatelessWidget {
  const _MessageTime({required this.time});

  final String time;

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: const TextStyle(color: Color(0xFF4D6370), fontSize: 10),
    );
  }
}

class _AvaAiUiMessage {
  const _AvaAiUiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.pending = false,
    this.failed = false,
  });

  factory _AvaAiUiMessage.fromDto(AvaAiMessageDto dto) {
    return _AvaAiUiMessage(
      id: dto.id,
      role: dto.role,
      content: dto.content,
      createdAt: dto.createdAt ?? DateTime.now(),
    );
  }

  factory _AvaAiUiMessage.fromJson(Map<String, dynamic> json) {
    return _AvaAiUiMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool pending;
  final bool failed;

  bool get isUser => role.toLowerCase() == 'user';

  _AvaAiUiMessage copyWith({bool? pending, bool? failed}) {
    return _AvaAiUiMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class _AvaAiChatSnapshot {
  const _AvaAiChatSnapshot({
    required this.id,
    required this.title,
    required this.savedAt,
    required this.messages,
  });

  factory _AvaAiChatSnapshot.fromJson(Map<String, dynamic> json) {
    return _AvaAiChatSnapshot(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      messages: [
        for (final item in json['messages'] as List<dynamic>? ?? const [])
          _AvaAiUiMessage.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final String id;
  final String title;
  final DateTime savedAt;
  final List<_AvaAiUiMessage> messages;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'savedAt': savedAt.toIso8601String(),
      'messages': [for (final message in messages) message.toJson()],
    };
  }
}

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final period = local.hour < 12 ? '오전' : '오후';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$period $hour:${local.minute.toString().padLeft(2, '0')}';
}

String _formatArchiveTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final date =
      '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  return '$date $time';
}
