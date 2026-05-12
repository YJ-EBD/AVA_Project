import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../data/ava_ai_api.dart';

const _aiChatBackground = Color(0xFFBFD3E3);
const _aiHeaderBackground = Color(0xFFD7E6F0);
const _aiHeaderBorder = Color(0xFFAFC7D8);
const _mineBubbleColor = Color(0xFFFFDF00);

class AvaAiPage extends ConsumerStatefulWidget {
  const AvaAiPage({super.key});

  @override
  ConsumerState<AvaAiPage> createState() => _AvaAiPageState();
}

class _AvaAiPageState extends ConsumerState<AvaAiPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_AvaAiUiMessage> _messages = [];
  String? _loadedToken;
  bool _loadingHistory = false;
  bool _sending = false;
  Object? _loadError;

  @override
  void dispose() {
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
      _scrollToBottom();
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
      }
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
          .send(accessToken: accessToken, content: text);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages
          ..add(_AvaAiUiMessage.fromDto(exchange.userMessage))
          ..add(_AvaAiUiMessage.fromDto(exchange.assistantMessage));
      });
      _scrollToBottom();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.removeWhere((message) => message.id == tempUser.id);
        _messages.add(tempUser.copyWith(pending: false, failed: true));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authErrorMessage(error)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value?.session;
    final accessToken = session?.accessToken ?? '';
    if (accessToken.isNotEmpty && _loadedToken != accessToken) {
      unawaited(_loadHistory(accessToken));
    }

    return ColoredBox(
      color: _aiChatBackground,
      child: Column(
        children: [
          const _AvaAiHeader(),
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
      ),
    );
  }
}

class _AvaAiHeader extends StatelessWidget {
  const _AvaAiHeader();

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
}

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final period = local.hour < 12 ? '오전' : '오후';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$period $hour:${local.minute.toString().padLeft(2, '0')}';
}
