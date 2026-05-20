import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../config/app_config.dart';
import '../../../platform/window_control.dart';
import '../../../shared/ava_dialog.dart';
import '../../../shared/ava_toast.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../../messenger/data/chat_api.dart';
import '../data/ava_ai_api.dart';

const _aiChatBackground = Color(0xFFBFD3E3);
const _aiHeaderBackground = Color(0xFFD7E6F0);
const _aiHeaderBorder = Color(0xFFAFC7D8);
const _mineBubbleColor = Color(0xFFFFDF00);
const double _avaAiChatPaneWidth = 396;
const double _avaAiMinimumWorkspaceWidth = 390;
const double _avaAiMobileBreakpoint = 720;

final ButtonStyle _workspaceHeaderButtonStyle = IconButton.styleFrom(
  foregroundColor: const Color(0xFF52616D),
  disabledForegroundColor: const Color(0xFF9AA8B2),
  hoverColor: const Color(0xFFDCE7EF),
);

final _avaAiPageMemory = _AvaAiPageMemory();

class _AvaAiPageMemory {
  final List<_AvaAiUiMessage> messages = [];
  final List<_AvaAiChatSnapshot> chatSnapshots = [];
  final List<AvaAiWorkspaceItemDto> workspaceItems = [];
  final Set<String> selectedWorkspacePaths = {};
  String workspacePath = '';
  String workspaceStatus = '';
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
    loadedToken = state._loadingHistory ? null : state._loadedToken;
    loadedSnapshotUserKey = state._loadedSnapshotUserKey;
  }
}

class AvaAiPage extends ConsumerStatefulWidget {
  const AvaAiPage({super.key});

  @override
  ConsumerState<AvaAiPage> createState() => _AvaAiPageState();
}

class _AvaAiPageState extends ConsumerState<AvaAiPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AvaAiUiMessage> _messages = [];
  final List<_AvaAiChatSnapshot> _chatSnapshots = [];
  final List<AvaAiWorkspaceItemDto> _workspaceItems = [];
  final Set<String> _selectedWorkspacePaths = {};
  String _workspacePath = '';
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
  String _workspaceStatus = '';
  Object? _loadError;
  int _scrollRequest = 0;
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
          await _uploadWorkspaceFiles(token, paths);
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
        _workspaceStatus = exchange.workspaceStatus;
        _sending = false;
      });
      _scrollToBottom();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages.add(tempUser.copyWith(pending: false, failed: true));
        _sending = false;
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
        });
      }
    }
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
                title: '이전 채팅 삭제',
                message: '정말로 삭제 하시겠습니까?',
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
              title: '이전 채팅',
              subtitle: '저장된 AVA AI 대화를 다시 불러오거나 삭제할 수 있습니다.',
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
                          '저장된 이전 채팅이 없습니다.',
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
          ? 'FORIVER_NAS (F:) 파일을 조회하고 있습니다.'
          : '$path 폴더를 조회하고 있습니다.';
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
            ? 'FORIVER_NAS (F:) 루트 조회 완료'
            : '$path 폴더 조회 완료';
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
        _workspaceStatus = '${loaded.title} 파일을 열었습니다.';
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
      showAvaToast(context, '현재 파일 열기는 Windows에서 지원됩니다.');
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 파일을 여는 중입니다.';
    });
    try {
      final originalPath = _foriverNasLocalPath(item.path);
      if (await File(originalPath).exists()) {
        await _openWindowsPath(originalPath);
        if (!mounted) {
          return;
        }
        setState(() {
          _workspaceStatus = '${item.title} 원본 파일을 열었습니다.';
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
        _workspaceStatus = '${item.title} 파일을 다운로드 폴더에 저장하고 열었습니다.';
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
      title: '이름 또는 경로 수정',
      initialPath: item.path,
      pathEditable: true,
      showContent: false,
    );
    if (draft == null || draft.path == item.path) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '${item.title} 항목을 수정하는 중입니다.';
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
      title: '작업공간 항목 생성',
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
        _workspaceStatus = '${items.length}개 파일을 작업공간에 올렸습니다.';
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
      showAvaToast(context, '전송할 작업공간 파일을 선택해주세요.');
      return;
    }
    final draft = await _showWorkspaceSendDialog(context, ref, accessToken);
    if (draft == null) {
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceStatus = '선택한 파일을 채팅으로 전송하고 있습니다.';
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
      showAvaToast(context, result.status.isEmpty ? '전송 완료' : result.status);
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
        ),
        Expanded(
          child: _AvaAiMessagesView(
            controller: _scrollController,
            messages: _messages,
            loadingHistory: _loadingHistory,
            sending: _sending,
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

    final workspacePanel = _AvaAiWorkspacePanel(
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

class _AvaAiWorkspacePanel extends StatelessWidget {
  const _AvaAiWorkspacePanel({
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
                    const Expanded(
                      child: Text(
                        '작업공간',
                        style: TextStyle(
                          color: Color(0xFF102040),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '이전 디렉토리',
                      style: _workspaceHeaderButtonStyle,
                      onPressed: busy ? null : onOpenParent,
                      icon: const Icon(Icons.arrow_upward, size: 20),
                    ),
                    IconButton(
                      tooltip: 'FORIVER_NAS (F:) 보기',
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
                      tooltip: '채팅으로 보내기',
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (busy) const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          status.isEmpty ? '작업 중입니다.' : status,
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
                    '파일을 작업공간에 놓아주세요.',
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
                      tooltip: item.isDirectory ? '폴더 열기' : '파일 열기',
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
                      tooltip: '수정',
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
  });

  final String workspacePath;
  final String workspaceStatus;
  final Set<String> selectedPaths;
  final List<AvaAiWorkspaceItemDto> items;
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
                    hintText: '업무/메모.txt',
                  ),
                ),
                if (allowDirectory) ...[
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: isDirectory,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('폴더로 생성'),
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
    title: '삭제 확인',
    message: '정말로 삭제 하시겠습니까?\nF:/${item.path}',
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
                hintText: '여기 첨부파일입니다.',
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
    showAvaToast(context, '현재 파일 선택은 Windows에서 지원됩니다.');
    return const [];
  }
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "작업공간 파일 추가"
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
  });

  final bool busy;
  final VoidCallback? onPreviousChat;
  final VoidCallback? onNewChat;

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
    required this.loadError,
    required this.onRetry,
  });

  final ScrollController controller;
  final List<_AvaAiUiMessage> messages;
  final bool loadingHistory;
  final bool sending;
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
          tooltip: '다시 시도',
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
            return const _AvaAiTypingBubble();
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
  const _AvaAiTypingBubble();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AvaLogoAvatar(size: 38),
        const SizedBox(width: 10),
        Column(
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
          ],
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
