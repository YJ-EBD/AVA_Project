import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/calendar_controller.dart';
import '../domain/calendar_models.dart';

const double _mobileBreakpoint = 600;
const double _desktopBreakpoint = 1024;
const Color _calendarBackground = Color(0xFFF4F7FB);
const Color _calendarSurface = Color(0xFFFFFFFF);
const Color _calendarSoftSurface = Color(0xFFF8FAFE);
const Color _calendarLine = Color(0xFFE4EAF3);
const Color _calendarText = Color(0xFF17233C);
const Color _calendarMuted = Color(0xFF6A7890);
const Color _calendarPrimary = Color(0xFF1463F3);
const Color _calendarNavy = Color(0xFF09275B);
const Color _calendarDanger = Color(0xFFFF4D5E);
const Color _calendarPurple = Color(0xFF7A55FF);

typedef CalendarExternalLinkOpener =
    Future<void> Function(String? target, String fallback);
typedef CalendarChatRoomOpener = Future<void> Function(CalendarChatLink link);
typedef CalendarAzoomOpener = Future<void> Function(CalendarAzoomLink link);

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, this.onOpenChatRoom, this.onOpenAzoomMeeting});

  final CalendarChatRoomOpener? onOpenChatRoom;
  final CalendarAzoomOpener? onOpenAzoomMeeting;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'calendar-shortcuts');

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarControllerProvider);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width < _mobileBreakpoint;
          final isDesktop = width >= _desktopBreakpoint;
          return Material(
            color: _calendarBackground,
            child: Stack(
              children: [
                if (isDesktop)
                  _DesktopCalendarLayout(
                    state: state,
                    searchController: _searchController,
                    onAdd: () => _openEditor(context),
                    onEdit: (event) => _openEditor(context, event: event),
                    onDelete: _confirmDelete,
                    onOpenLink: _openExternalLink,
                    onOpenChatRoom: widget.onOpenChatRoom,
                    onOpenAzoomMeeting: widget.onOpenAzoomMeeting,
                  )
                else
                  _MobileCalendarLayout(
                    state: state,
                    tablet: !isMobile,
                    searchController: _searchController,
                    onAdd: () => _openEditor(context),
                    onEdit: (event) => _openEditor(context, event: event),
                    onDelete: _confirmDelete,
                    onOpenLink: _openExternalLink,
                    onOpenChatRoom: widget.onOpenChatRoom,
                    onOpenAzoomMeeting: widget.onOpenAzoomMeeting,
                  ),
                if (state.loading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final controller = ref.read(calendarControllerProvider.notifier);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyN:
        _openEditor(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        controller.goToday();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        controller.setViewMode(CalendarViewMode.month);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyW:
        controller.setViewMode(CalendarViewMode.week);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
        controller.setViewMode(CalendarViewMode.day);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        controller.setViewMode(CalendarViewMode.list);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openEditor(BuildContext context, {CalendarEvent? event}) async {
    final width = MediaQuery.sizeOf(context).width;
    final child = CalendarEventEditor(event: event);
    if (width < _desktopBreakpoint) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (context) => FractionallySizedBox(
          heightFactor: width < _mobileBreakpoint ? 0.96 : 0.88,
          child: child,
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          alignment: Alignment.center,
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 28,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 660,
              maxHeight: MediaQuery.sizeOf(context).height * 0.84,
            ),
            child: child,
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(CalendarEvent event) async {
    final recurrence = event.recurrence?.isRepeating ?? false;
    final scope = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('일정 삭제'),
          content: Text(
            recurrence
                ? '반복 일정입니다. 삭제 범위를 선택하세요.'
                : '"${event.title}" 일정을 삭제할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            if (recurrence)
              TextButton(
                onPressed: () => Navigator.pop(context, 'THIS_AND_FUTURE'),
                child: const Text('이번 일정 이후 모두'),
              ),
            if (recurrence)
              TextButton(
                onPressed: () => Navigator.pop(context, 'ALL'),
                child: const Text('전체 반복 일정'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'THIS'),
              child: Text(recurrence ? '이번 일정만' : '삭제'),
            ),
          ],
        );
      },
    );
    if (scope == null) {
      return;
    }
    await ref
        .read(calendarControllerProvider.notifier)
        .deleteEvent(event, recurrenceDeleteScope: scope);
  }

  Future<void> _openExternalLink(String? url, String fallback) async {
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$fallback 정보가 아직 연결되지 않았습니다.')));
      return;
    }
    final uri = _externalUriFor(url.trim());
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$fallback 주소를 열 수 없습니다.')));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$fallback 열기에 실패했습니다.')));
    }
  }
}

class _DesktopCalendarLayout extends ConsumerWidget {
  const _DesktopCalendarLayout({
    required this.state,
    required this.searchController,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLink,
    this.onOpenChatRoom,
    this.onOpenAzoomMeeting,
  });

  final CalendarState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final ValueChanged<CalendarEvent> onEdit;
  final ValueChanged<CalendarEvent> onDelete;
  final CalendarExternalLinkOpener onOpenLink;
  final CalendarChatRoomOpener? onOpenChatRoom;
  final CalendarAzoomOpener? onOpenAzoomMeeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _CalendarGlobalHeader(
          searchController: searchController,
          state: state,
          onAdd: onAdd,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 286,
                  child: _CalendarPanel(
                    child: _CalendarSidebar(
                      state: state,
                      compact: false,
                      onAdd: onAdd,
                      onAddCategory: _showCategoryDialog,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CalendarPanel(
                    child: Column(
                      children: [
                        _CalendarToolbar(
                          state: state,
                          searchController: searchController,
                          onAdd: onAdd,
                        ),
                        Expanded(
                          child: _CalendarBody(
                            state: state,
                            desktop: true,
                            onEventTap: (event) => ref
                                .read(calendarControllerProvider.notifier)
                                .selectEvent(event),
                            onEmptyTimeTap: (date) => onAdd(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 366,
                  child: _CalendarPanel(
                    child: _EventDetailPanel(
                      event: state.selectedEvent,
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onOpenLink: onOpenLink,
                      onOpenChatRoom: onOpenChatRoom,
                      onOpenAzoomMeeting: onOpenAzoomMeeting,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCategoryDialog(BuildContext context) async {
    final nameController = TextEditingController();
    var color = '#5B7CFA';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('카테고리 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '카테고리명'),
            ),
            const SizedBox(height: 14),
            _ColorPicker(
              selectedColor: color,
              onChanged: (value) => color = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          Consumer(
            builder: (context, ref, _) => FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                await ref
                    .read(calendarControllerProvider.notifier)
                    .createCategory(name, color);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('저장'),
            ),
          ),
        ],
      ),
    );
    nameController.dispose();
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _calendarSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _calendarLine),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B2B4A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
    );
  }
}

class _CalendarGlobalHeader extends ConsumerWidget {
  const _CalendarGlobalHeader({
    required this.searchController,
    required this.state,
    required this.onAdd,
  });

  final TextEditingController searchController;
  final CalendarState state;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(calendarControllerProvider.notifier);
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: _calendarSurface,
        border: Border(bottom: BorderSide(color: _calendarLine)),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: '메시지, 파일, 멤버 검색 (⌘ + K)',
                  hintStyle: const TextStyle(
                    color: Color(0xFF8A96AA),
                    fontWeight: FontWeight.w600,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF2F5FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(9),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: controller.setSearchQuery,
              ),
            ),
          ),
          const Spacer(),
          _HeaderIconButton(
            tooltip: '도움말',
            icon: Icons.help_outline_rounded,
            onTap: () {},
          ),
          const SizedBox(width: 12),
          _HeaderIconButton(
            tooltip: '알림',
            icon: Icons.notifications_none_rounded,
            badge: state.visibleEvents
                .where((event) => _sameDate(event.displayStart, DateTime.now()))
                .length,
            onTap: () {},
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String?>(
            tooltip: '팀 선택',
            initialValue: state.teamFilter,
            onSelected: controller.setTeamFilter,
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(value: null, child: Text('전체 팀')),
              for (final team in calendarTeams)
                PopupMenuItem<String?>(value: team.id, child: Text(team.name)),
            ],
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _calendarSoftSurface,
                border: Border.all(color: _calendarLine),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.groups_2_outlined,
                    color: _calendarNavy,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    calendarTeamLabel(state.teamFilter),
                    style: const TextStyle(
                      color: _calendarText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: _calendarSoftSurface,
              border: Border.all(color: _calendarLine),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_1_rounded, size: 20),
                const SizedBox(width: 7),
                Text(
                  '${_uniqueAttendeeCount(state.visibleEvents)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HeaderIconButton(
            tooltip: '앱 메뉴',
            icon: Icons.apps_rounded,
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _MobileCalendarLayout extends ConsumerWidget {
  const _MobileCalendarLayout({
    required this.state,
    required this.tablet,
    required this.searchController,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLink,
    this.onOpenChatRoom,
    this.onOpenAzoomMeeting,
  });

  final CalendarState state;
  final bool tablet;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final ValueChanged<CalendarEvent> onEdit;
  final ValueChanged<CalendarEvent> onDelete;
  final CalendarExternalLinkOpener onOpenLink;
  final CalendarChatRoomOpener? onOpenChatRoom;
  final CalendarAzoomOpener? onOpenAzoomMeeting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tablet && MediaQuery.orientationOf(context) == Orientation.landscape) {
      return Row(
        children: [
          SizedBox(
            width: 220,
            child: _CalendarSidebar(
              state: state,
              compact: true,
              onAdd: onAdd,
              onAddCategory: (_) {},
            ),
          ),
          const VerticalDivider(width: 1, color: _calendarLine),
          Expanded(child: _mobileMain(context, ref)),
        ],
      );
    }
    return _mobileMain(context, ref);
  }

  Widget _mobileMain(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _calendarBackground,
      floatingActionButton: FloatingActionButton(
        onPressed: onAdd,
        backgroundColor: _calendarPrimary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MobileCalendarHeader(
              state: state,
              searchController: searchController,
            ),
            _CalendarToolbar(
              state: state,
              searchController: searchController,
              onAdd: onAdd,
              compact: true,
            ),
            Expanded(
              child: _CalendarBody(
                state: state,
                desktop: false,
                onEventTap: (event) => _showDetailSheet(context, event),
                onEmptyTimeTap: (_) => onAdd(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetailSheet(BuildContext context, CalendarEvent event) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _EventDetailPanel(
          event: event,
          onEdit: onEdit,
          onDelete: onDelete,
          onOpenLink: onOpenLink,
          onOpenChatRoom: onOpenChatRoom,
          onOpenAzoomMeeting: onOpenAzoomMeeting,
          mobile: true,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, color: _calendarNavy, size: 22),
              if (badge > 0)
                Positioned(
                  top: 5,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _calendarDanger,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCalendarHeader extends ConsumerWidget {
  const _MobileCalendarHeader({
    required this.state,
    required this.searchController,
  });

  final CalendarState state;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: const BoxDecoration(
        color: _calendarSurface,
        border: Border(bottom: BorderSide(color: _calendarLine)),
      ),
      child: Row(
        children: [
          const Text(
            'AVA',
            style: TextStyle(
              color: _calendarPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: _calendarLine,
          ),
          const Text(
            '캘린더',
            style: TextStyle(
              color: _calendarText,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '검색',
            onPressed: () => _showMobileSearch(context, ref),
            icon: const Icon(Icons.search_rounded),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: '알림',
                onPressed: () {},
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (state.visibleEvents.any(
                (event) => _sameDate(event.displayStart, DateTime.now()),
              ))
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _calendarDanger,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            radius: 15,
            backgroundColor: Color(0xFFE9EEF8),
            child: Icon(Icons.person, size: 17, color: _calendarNavy),
          ),
        ],
      ),
    );
  }

  Future<void> _showMobileSearch(BuildContext context, WidgetRef ref) {
    final controller = ref.read(calendarControllerProvider.notifier);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: TextField(
            controller: searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: '일정 검색',
              hintText: '제목, 참석자, 파일, Notion 검색',
            ),
            onSubmitted: (value) {
              controller.setSearchQuery(value);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }
}

class _CalendarToolbar extends ConsumerWidget {
  const _CalendarToolbar({
    required this.state,
    required this.searchController,
    required this.onAdd,
    this.compact = false,
  });

  final CalendarState state;
  final TextEditingController searchController;
  final VoidCallback onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(calendarControllerProvider.notifier);
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        color: _calendarSurface,
        child: Column(
          children: [
            Row(
              children: [
                _SmallSquareButton(
                  tooltip: '이전',
                  icon: Icons.chevron_left_rounded,
                  onTap: () => controller.move(-1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Center(
                    child: Text(
                      _titleForState(state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _calendarText,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _SmallSquareButton(
                  tooltip: '다음',
                  icon: Icons.chevron_right_rounded,
                  onTap: () => controller.move(1),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _PillActionButton(label: '오늘', onTap: controller.goToday),
                  const SizedBox(width: 8),
                  _ViewModeButton(
                    label: '월간',
                    selected: state.viewMode == CalendarViewMode.month,
                    onTap: () => controller.setViewMode(CalendarViewMode.month),
                  ),
                  const SizedBox(width: 6),
                  _ViewModeButton(
                    label: '주간',
                    selected: state.viewMode == CalendarViewMode.week,
                    onTap: () => controller.setViewMode(CalendarViewMode.week),
                  ),
                  const SizedBox(width: 6),
                  _ViewModeButton(
                    label: '일간',
                    selected: state.viewMode == CalendarViewMode.day,
                    onTap: () => controller.setViewMode(CalendarViewMode.day),
                  ),
                  const SizedBox(width: 6),
                  _ViewModeButton(
                    label: '리스트',
                    selected: state.viewMode == CalendarViewMode.list,
                    onTap: () => controller.setViewMode(CalendarViewMode.list),
                  ),
                ],
              ),
            ),
            if (state.errorText != null) ...[
              const SizedBox(height: 8),
              _InlineError(message: state.errorText!),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
      decoration: const BoxDecoration(
        color: _calendarSurface,
        border: Border(bottom: BorderSide(color: _calendarLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titleForState(state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _calendarText,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _SmallSquareButton(
                tooltip: '이전',
                icon: Icons.chevron_left_rounded,
                onTap: () => controller.move(-1),
              ),
              const SizedBox(width: 8),
              _SmallSquareButton(
                tooltip: '다음',
                icon: Icons.chevron_right_rounded,
                onTap: () => controller.move(1),
              ),
              const SizedBox(width: 18),
              _PillActionButton(label: '오늘', onTap: controller.goToday),
              const SizedBox(width: 10),
              _ViewModeMenu(state: state),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('일정 추가'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ViewModeButton(
                label: '월간',
                selected: state.viewMode == CalendarViewMode.month,
                onTap: () => controller.setViewMode(CalendarViewMode.month),
              ),
              const SizedBox(width: 8),
              _ViewModeButton(
                label: '주간',
                selected: state.viewMode == CalendarViewMode.week,
                onTap: () => controller.setViewMode(CalendarViewMode.week),
              ),
              const SizedBox(width: 8),
              _ViewModeButton(
                label: '일간',
                selected: state.viewMode == CalendarViewMode.day,
                onTap: () => controller.setViewMode(CalendarViewMode.day),
              ),
              const SizedBox(width: 8),
              _ViewModeButton(
                label: '리스트',
                selected: state.viewMode == CalendarViewMode.list,
                onTap: () => controller.setViewMode(CalendarViewMode.list),
              ),
              const Spacer(),
              _StatusFilterButton(status: state.statusFilter),
            ],
          ),
          if (state.errorText != null) ...[
            const SizedBox(height: 8),
            _InlineError(message: state.errorText!),
          ],
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected ? Colors.white : _calendarMuted,
          backgroundColor: selected ? _calendarPrimary : _calendarSoftSurface,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
              color: selected ? _calendarPrimary : _calendarLine,
            ),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SmallSquareButton extends StatelessWidget {
  const _SmallSquareButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _calendarSoftSurface,
            border: Border.all(color: _calendarLine),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _calendarText, size: 22),
        ),
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _calendarText,
          side: const BorderSide(color: _calendarLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ViewModeMenu extends ConsumerWidget {
  const _ViewModeMenu({required this.state});

  final CalendarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(calendarControllerProvider.notifier);
    return PopupMenuButton<CalendarViewMode>(
      tooltip: '보기 방식',
      initialValue: state.viewMode,
      onSelected: controller.setViewMode,
      itemBuilder: (context) => [
        for (final mode in CalendarViewMode.values)
          PopupMenuItem<CalendarViewMode>(
            value: mode,
            child: Text(_viewModeLabel(mode)),
          ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _calendarSoftSurface,
          border: Border.all(color: _calendarLine),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Text(
              _viewModeLabel(state.viewMode),
              style: const TextStyle(
                color: _calendarText,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterButton extends ConsumerWidget {
  const _StatusFilterButton({this.status});

  final String? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const items = <String?>[
      null,
      'SCHEDULED',
      'IN_PROGRESS',
      'COMPLETED',
      'CANCELLED',
      'POSTPONED',
      'ON_HOLD',
    ];
    return PopupMenuButton<String?>(
      tooltip: '상태 필터',
      initialValue: status,
      onSelected: (value) =>
          ref.read(calendarControllerProvider.notifier).setStatusFilter(value),
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<String?>(
            value: item,
            child: Text(item == null ? '전체 상태' : calendarStatusLabel(item)),
          ),
      ],
      child: Chip(
        avatar: const Icon(Icons.filter_list, size: 18),
        label: Text(status == null ? '전체 상태' : calendarStatusLabel(status!)),
      ),
    );
  }
}

class _CalendarSidebar extends ConsumerWidget {
  const _CalendarSidebar({
    required this.state,
    required this.compact,
    required this.onAdd,
    required this.onAddCategory,
  });

  final CalendarState state;
  final bool compact;
  final VoidCallback onAdd;
  final ValueChanged<BuildContext> onAddCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEvents = state.selectedDateEvents(state.selectedDate);
    return Container(
      color: _calendarSurface,
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 22,
                  compact ? 14 : 20,
                  compact ? 14 : 22,
                  18,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'AVA 일정표',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _calendarText,
                                  fontSize: compact ? 17 : 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: _calendarMuted,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '고정',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {},
                        icon: const Icon(
                          Icons.push_pin_outlined,
                          size: 19,
                          color: _calendarPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _MiniCalendar(state: state),
                  const SizedBox(height: 22),
                  _SidebarSectionHeader(
                    title: '팀 필터',
                    trailing: const Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: _calendarMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _TeamFilterTile(
                    label: '전체 팀',
                    selected: state.teamFilter == null,
                    color: _calendarPrimary,
                    onTap: () => ref
                        .read(calendarControllerProvider.notifier)
                        .setTeamFilter(null),
                  ),
                  for (var i = 0; i < calendarTeams.length; i++)
                    _TeamFilterTile(
                      label: calendarTeams[i].name,
                      selected: state.teamFilter == calendarTeams[i].id,
                      color: _teamColor(i),
                      onTap: () => ref
                          .read(calendarControllerProvider.notifier)
                          .setTeamFilter(calendarTeams[i].id),
                    ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  _SidebarSectionHeader(
                    title: '카테고리',
                    trailing: IconButton(
                      tooltip: '카테고리 추가',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onAddCategory(context),
                      icon: const Icon(Icons.add_rounded, size: 19),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final category in state.categories)
                    _CategoryFilterTile(
                      category: category,
                      selected:
                          state.visibleCategoryIds.isEmpty ||
                          state.visibleCategoryIds.contains(category.id),
                      onTap: () => ref
                          .read(calendarControllerProvider.notifier)
                          .toggleCategory(category.id),
                    ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  _SidebarSectionHeader(
                    title: '선택 날짜',
                    trailing: Text(
                      '${selectedEvents.length}개',
                      style: const TextStyle(
                        color: _calendarMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatFullDate(state.selectedDate),
                    style: const TextStyle(
                      color: _calendarMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (selectedEvents.isEmpty)
                    const Text(
                      '등록된 일정이 없습니다.',
                      style: TextStyle(color: _calendarMuted),
                    )
                  else
                    for (final event in selectedEvents.take(4))
                      _CompactEventTile(
                        event: event,
                        onTap: () => ref
                            .read(calendarControllerProvider.notifier)
                            .selectEvent(event),
                      ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 22,
                0,
                compact ? 14 : 22,
                compact ? 14 : 20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: _calendarPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('일정 추가'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  const _SidebarSectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _calendarText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ...?trailing == null ? null : [trailing!],
      ],
    );
  }
}

class _TeamFilterTile extends StatelessWidget {
  const _TeamFilterTile({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Text(
                label == '전체 팀' ? 'All' : label.characters.first,
                style: TextStyle(
                  color: color,
                  fontSize: label == '전체 팀' ? 9 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: selected ? _calendarPrimary : const Color(0xFFB6C0D1),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFilterTile extends StatelessWidget {
  const _CategoryFilterTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CalendarCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _ColorDot(color: color, size: 9),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? _calendarPrimary : const Color(0xFFB6C0D1),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCalendar extends ConsumerWidget {
  const _MiniCalendar({required this.state});

  final CalendarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthStart = DateTime(
      state.focusedDate.year,
      state.focusedDate.month,
    );
    final gridStart = _monthGridStart(monthStart);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${monthStart.year}년 ${monthStart.month}월',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '이전 달',
                  onPressed: () =>
                      ref.read(calendarControllerProvider.notifier).move(-1),
                  icon: const Icon(Icons.chevron_left, size: 18),
                ),
                IconButton(
                  tooltip: '다음 달',
                  onPressed: () =>
                      ref.read(calendarControllerProvider.notifier).move(1),
                  icon: const Icon(Icons.chevron_right, size: 18),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final label in ['일', '월', '화', '수', '목', '금', '토'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _calendarMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (context, index) {
            final date = gridStart.add(Duration(days: index));
            final selected = _sameDate(date, state.selectedDate);
            final today = _sameDate(date, DateTime.now());
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => ref
                  .read(calendarControllerProvider.notifier)
                  .selectDate(date),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? _calendarPrimary
                      : today
                      ? const Color(0xFFE7EDFF)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : date.month == state.focusedDate.month
                        ? _calendarText
                        : _calendarMuted,
                    fontSize: 12,
                    fontWeight: today || selected
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({
    required this.state,
    required this.desktop,
    required this.onEventTap,
    required this.onEmptyTimeTap,
  });

  final CalendarState state;
  final bool desktop;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<DateTime> onEmptyTimeTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state.viewMode) {
      CalendarViewMode.month => _MonthView(
        state: state,
        desktop: desktop,
        onEventTap: onEventTap,
      ),
      CalendarViewMode.week => _TimelineView(
        state: state,
        dayCount: 7,
        desktop: desktop,
        onEventTap: onEventTap,
        onEmptyTimeTap: onEmptyTimeTap,
      ),
      CalendarViewMode.day => _TimelineView(
        state: state,
        dayCount: 1,
        desktop: desktop,
        onEventTap: onEventTap,
        onEmptyTimeTap: onEmptyTimeTap,
      ),
      CalendarViewMode.list => _ListViewMode(
        state: state,
        onEventTap: onEventTap,
      ),
    };
  }
}

class _MonthView extends ConsumerWidget {
  const _MonthView({
    required this.state,
    required this.desktop,
    required this.onEventTap,
  });

  final CalendarState state;
  final bool desktop;
  final ValueChanged<CalendarEvent> onEventTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthStart = DateTime(
      state.focusedDate.year,
      state.focusedDate.month,
    );
    final gridStart = _monthGridStart(monthStart);
    final cellAspect = desktop ? 1.04 : 1.22;
    return ListView(
      padding: EdgeInsets.fromLTRB(desktop ? 16 : 12, 0, desktop ? 16 : 12, 16),
      children: [
        _WeekHeader(compact: !desktop),
        SizedBox(height: desktop ? 10 : 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(desktop ? 12 : 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: desktop ? _calendarLine : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(desktop ? 12 : 0),
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                childAspectRatio: cellAspect,
              ),
              itemBuilder: (context, index) {
                final date = gridStart.add(Duration(days: index));
                final events = state.selectedDateEvents(date);
                return _MonthDayCell(
                  date: date,
                  inMonth: date.month == state.focusedDate.month,
                  selected: _sameDate(date, state.selectedDate),
                  today: _sameDate(date, DateTime.now()),
                  events: events,
                  desktop: desktop,
                  onDateTap: () {
                    ref
                        .read(calendarControllerProvider.notifier)
                        .selectDate(date);
                    if (!desktop && events.isNotEmpty) {
                      _showDayEvents(context, date, events);
                    }
                  },
                  onEventTap: onEventTap,
                );
              },
            ),
          ),
        ),
        if (desktop) ...[
          const SizedBox(height: 14),
          _CalendarLegend(categories: state.categories),
        ],
        if (!desktop) ...[
          const SizedBox(height: 16),
          _SelectedDateList(state: state, onEventTap: onEventTap),
        ],
      ],
    );
  }

  Future<void> _showDayEvents(
    BuildContext context,
    DateTime date,
    List<CalendarEvent> events,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            Text(
              _formatFullDate(date),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final event in events)
              _EventListTile(
                event: event,
                onTap: () {
                  Navigator.pop(context);
                  onEventTap(event);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const labels = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: _calendarMuted,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.events,
    required this.desktop,
    required this.onDateTap,
    required this.onEventTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<CalendarEvent> events;
  final bool desktop;
  final VoidCallback onDateTap;
  final ValueChanged<CalendarEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    final mutedDay = !inMonth;
    return Material(
      color: desktop
          ? (selected ? const Color(0xFFF2F6FF) : _calendarSurface)
          : _calendarSurface,
      child: InkWell(
        onTap: onDateTap,
        child: Container(
          padding: EdgeInsets.all(desktop ? 8 : 4),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: desktop ? _calendarLine : Colors.transparent,
              ),
              bottom: BorderSide(
                color: desktop ? _calendarLine : Colors.transparent,
              ),
            ),
            borderRadius: BorderRadius.circular(desktop && selected ? 9 : 0),
          ),
          foregroundDecoration: BoxDecoration(
            border: selected
                ? Border.all(color: _calendarPrimary, width: desktop ? 1.3 : 0)
                : null,
            borderRadius: BorderRadius.circular(desktop ? 9 : 0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: desktop ? Alignment.centerLeft : Alignment.center,
                child: Container(
                  width: desktop ? 26 : 25,
                  height: desktop ? 26 : 25,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: today || (!desktop && selected)
                        ? _calendarPrimary
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: today || (!desktop && selected)
                          ? Colors.white
                          : mutedDay
                          ? const Color(0xFFA7B1C3)
                          : _weekdayDayColor(date),
                      fontWeight: today || selected
                          ? FontWeight.w900
                          : FontWeight.w700,
                      fontSize: desktop ? 13 : 12,
                    ),
                  ),
                ),
              ),
              SizedBox(height: desktop ? 5 : 2),
              if (desktop)
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final event in events.take(3))
                        _MonthEventPill(
                          event: event,
                          onTap: () => onEventTap(event),
                        ),
                      if (events.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '+${events.length - 3}개 더보기',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _calendarMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final event in events.take(4))
                          _ColorDot(
                            color: _parseColor(event.effectiveColor),
                            size: 4.5,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthEventPill extends StatelessWidget {
  const _MonthEventPill({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(event.effectiveColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 25,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              if (!event.allDay) ...[
                Text(
                  _formatTime(event.displayStart),
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _calendarText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (event.hasAzoom)
                Icon(Icons.videocam_rounded, size: 12, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.categories});

  final List<CalendarCategory> categories;

  @override
  Widget build(BuildContext context) {
    final visible = categories.take(6).toList(growable: false);
    return Row(
      children: [
        for (final category in visible) ...[
          _ColorDot(color: _parseColor(category.color), size: 8),
          const SizedBox(width: 6),
          Text(
            category.name,
            style: const TextStyle(
              color: _calendarMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 16),
        ],
        const Spacer(),
        Text(
          '표시된 일정 ${categories.length}개 카테고리',
          style: const TextStyle(
            color: _calendarMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 18,
          color: _calendarMuted,
        ),
      ],
    );
  }
}

class _TimelineView extends StatelessWidget {
  const _TimelineView({
    required this.state,
    required this.dayCount,
    required this.desktop,
    required this.onEventTap,
    required this.onEmptyTimeTap,
  });

  final CalendarState state;
  final int dayCount;
  final bool desktop;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<DateTime> onEmptyTimeTap;

  @override
  Widget build(BuildContext context) {
    final start = dayCount == 1
        ? DateTime(
            state.focusedDate.year,
            state.focusedDate.month,
            state.focusedDate.day,
          )
        : _startOfWeek(state.focusedDate);
    final days = [
      for (var i = 0; i < dayCount; i++) start.add(Duration(days: i)),
    ];
    return ListView(
      padding: EdgeInsets.all(desktop ? 18 : 12),
      children: [
        Row(
          children: [
            if (desktop) const SizedBox(width: 64),
            for (final day in days)
              Expanded(
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _calendarLine)),
                  ),
                  child: Text(
                    '${day.month}/${day.day} ${_weekdayLabel(day)}',
                    style: TextStyle(
                      color: _sameDate(day, DateTime.now())
                          ? _calendarPrimary
                          : _calendarText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var hour = 0; hour < 24; hour++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop)
                SizedBox(
                  width: 64,
                  height: 82,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(color: _calendarMuted, fontSize: 12),
                  ),
                ),
              for (final day in days)
                Expanded(
                  child: _TimeSlotCell(
                    date: DateTime(day.year, day.month, day.day, hour),
                    events: state.eventsForRange(
                      DateTime(day.year, day.month, day.day, hour),
                      DateTime(day.year, day.month, day.day, hour + 1),
                    ),
                    showNow:
                        _sameDate(day, DateTime.now()) &&
                        DateTime.now().hour == hour,
                    desktop: desktop,
                    onEventTap: onEventTap,
                    onEmptyTimeTap: onEmptyTimeTap,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _TimeSlotCell extends StatelessWidget {
  const _TimeSlotCell({
    required this.date,
    required this.events,
    required this.showNow,
    required this.desktop,
    required this.onEventTap,
    required this.onEmptyTimeTap,
  });

  final DateTime date;
  final List<CalendarEvent> events;
  final bool showNow;
  final bool desktop;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<DateTime> onEmptyTimeTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: events.isEmpty ? () => onEmptyTimeTap(date) : null,
      child: Container(
        constraints: BoxConstraints(minHeight: desktop ? 82 : 72),
        padding: EdgeInsets.all(desktop ? 6 : 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            right: BorderSide(color: _calendarLine),
            bottom: BorderSide(color: _calendarLine),
          ),
        ),
        child: Stack(
          children: [
            if (showNow)
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Container(height: 2, color: const Color(0xFFE5484D)),
              ),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final event in events)
                  _TimelineEventBlock(event: event, onTap: onEventTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineEventBlock extends StatelessWidget {
  const _TimelineEventBlock({required this.event, required this.onTap});

  final CalendarEvent event;
  final ValueChanged<CalendarEvent> onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(event.effectiveColor);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 220),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: () => onTap(event),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border(left: BorderSide(color: color, width: 4)),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _calendarText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_formatTime(event.displayStart)}-${_formatTime(event.displayEnd)}',
                style: const TextStyle(color: _calendarMuted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListViewMode extends StatelessWidget {
  const _ListViewMode({required this.state, required this.onEventTap});

  final CalendarState state;
  final ValueChanged<CalendarEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfWeek = _startOfWeek(today);
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final startOfMonth = DateTime(today.year, today.month);
    final endOfMonth = DateTime(today.year, today.month + 1);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _EventSection(
          title: '오늘 일정',
          events: state.selectedDateEvents(today),
          onEventTap: onEventTap,
        ),
        _EventSection(
          title: '이번 주 일정',
          events: state.eventsForRange(startOfWeek, endOfWeek),
          onEventTap: onEventTap,
        ),
        _EventSection(
          title: '이번 달 일정',
          events: state.eventsForRange(startOfMonth, endOfMonth),
          onEventTap: onEventTap,
        ),
        for (final category in state.categories)
          _EventSection(
            title: category.name,
            events: [
              for (final event in state.visibleEvents)
                if (event.categoryId == category.id) event,
            ],
            onEventTap: onEventTap,
          ),
      ],
    );
  }
}

class _EventSection extends StatelessWidget {
  const _EventSection({
    required this.title,
    required this.events,
    required this.onEventTap,
  });

  final String title;
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final event in events)
            _EventListTile(event: event, onTap: () => onEventTap(event)),
        ],
      ),
    );
  }
}

class _SelectedDateList extends StatelessWidget {
  const _SelectedDateList({required this.state, required this.onEventTap});

  final CalendarState state;
  final ValueChanged<CalendarEvent> onEventTap;

  @override
  Widget build(BuildContext context) {
    final events = state.selectedDateEvents(state.selectedDate);
    final today = _sameDate(state.selectedDate, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_formatFullDate(state.selectedDate)}${today ? ' · 오늘' : ''}',
                style: const TextStyle(
                  fontSize: 15,
                  color: _calendarText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '일정 ${events.length}개',
              style: const TextStyle(
                color: _calendarMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_up_rounded,
              color: _calendarMuted,
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          const _EmptyState()
        else
          for (final event in events)
            _EventListTile(event: event, onTap: () => onEventTap(event)),
      ],
    );
  }
}

class _EventListTile extends StatelessWidget {
  const _EventListTile({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(event.effectiveColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 54,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatTime(event.displayStart),
                    style: const TextStyle(
                      color: _calendarText,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(event.displayEnd),
                    style: const TextStyle(
                      color: _calendarMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 62),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _TinyTag(
                                label: event.category?.name ?? '일정',
                                color: color,
                              ),
                              if (event.hasAzoom)
                                const _TinyTag(
                                  label: 'AZOOM',
                                  color: _calendarPrimary,
                                ),
                              if (event.importance == 'HIGH')
                                const _TinyTag(
                                  label: '중요',
                                  color: _calendarDanger,
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _calendarText,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ConnectionIcons(event: event),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _calendarMuted,
                    ),
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

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CompactEventTile extends StatelessWidget {
  const _CompactEventTile({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(event.effectiveColor);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _ColorDot(color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _formatTime(event.displayStart),
              style: const TextStyle(color: _calendarMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventDetailPanel extends ConsumerWidget {
  const _EventDetailPanel({
    required this.event,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLink,
    this.onOpenChatRoom,
    this.onOpenAzoomMeeting,
    this.mobile = false,
  });

  final CalendarEvent? event;
  final ValueChanged<CalendarEvent> onEdit;
  final ValueChanged<CalendarEvent> onDelete;
  final CalendarExternalLinkOpener onOpenLink;
  final CalendarChatRoomOpener? onOpenChatRoom;
  final CalendarAzoomOpener? onOpenAzoomMeeting;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = this.event;
    if (event == null) {
      return Container(
        color: _calendarSurface,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined, color: _calendarMuted, size: 36),
              SizedBox(height: 10),
              Text(
                '선택한 일정이 없습니다.',
                style: TextStyle(
                  color: _calendarMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final azoom = event.azoomLinks.isEmpty ? null : event.azoomLinks.first;
    final chat = event.chatLinks.isEmpty ? null : event.chatLinks.first;
    final notion = event.notionLinks.isEmpty ? null : event.notionLinks.first;
    final file = event.files.isEmpty ? null : event.files.first;
    final color = _parseColor(event.effectiveColor);
    return Container(
      color: _calendarSurface,
      child: SafeArea(
        child: Column(
          children: [
            if (mobile)
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFD5DCE8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(22, mobile ? 14 : 22, 22, 22),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _TinyTag(
                              label: event.category?.name ?? '일정',
                              color: color,
                            ),
                            const _TinyTag(
                              label: 'AVA AI 추천',
                              color: _calendarPurple,
                            ),
                            _TinyTag(
                              label: calendarStatusLabel(event.status),
                              color: _calendarPrimary,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          if (mobile) {
                            Navigator.maybePop(context);
                          } else {
                            ref
                                .read(calendarControllerProvider.notifier)
                                .selectEvent(null);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    event.title,
                    style: TextStyle(
                      color: _calendarText,
                      fontSize: mobile ? 22 : 24,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (event.description != null &&
                      event.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description!,
                      style: const TextStyle(
                        color: _calendarMuted,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _DetailLine(
                    icon: Icons.calendar_today_outlined,
                    label:
                        '${_formatFullDateTime(event.displayStart)}\n${_formatFullDateTime(event.displayEnd)} · ${_durationLabel(event)}',
                  ),
                  if (event.location != null)
                    _DetailLine(icon: Icons.place, label: event.location!),
                  _DetailLine(
                    icon: Icons.flag,
                    label:
                        '${event.category?.name ?? '기타'} · ${calendarStatusLabel(event.status)}',
                  ),
                  _DetailLine(
                    icon: Icons.groups_rounded,
                    label:
                        '${calendarTeamLabel(event.teamId)} · 중요도 ${calendarImportanceLabel(event.importance)}',
                  ),
                  _DetailLine(
                    icon: Icons.visibility,
                    label:
                        '${calendarVisibilityLabel(event.visibility)} · ${event.detailVisibility}',
                  ),
                  if (event.memo != null && event.memo!.trim().isNotEmpty)
                    _DetailBlock(title: '메모', text: event.memo!),
                  if (event.recurrence?.isRepeating ?? false)
                    _DetailLine(
                      icon: Icons.repeat,
                      label: calendarRecurrenceLabel(
                        event.recurrence!.recurrenceType,
                      ),
                    ),
                  _DetailCollection(
                    title: '참석자',
                    icon: Icons.group,
                    emptyText: '참석자가 없습니다.',
                    children: [
                      for (final attendee in event.attendees)
                        Text(
                          '${attendee.displayName} · ${calendarAttendeeStatusLabel(attendee.responseStatus)}',
                        ),
                    ],
                  ),
                  _DetailCollection(
                    title: '알림',
                    icon: Icons.notifications,
                    emptyText: '알림이 없습니다.',
                    children: [
                      for (final reminder in event.reminders)
                        Text('${reminder.remindBeforeMinutes}분 전'),
                    ],
                  ),
                  if (event.chatLinks.isNotEmpty)
                    _DetailCollection(
                      title: '연결된 채팅방',
                      icon: Icons.tag,
                      emptyText: '연결된 채팅방이 없습니다.',
                      children: [
                        for (final link in event.chatLinks)
                          Text(link.chatRoomName ?? link.chatRoomId),
                      ],
                    ),
                  if (event.files.isNotEmpty)
                    _DetailCollection(
                      title: 'NAS 첨부 파일',
                      icon: Icons.attach_file,
                      emptyText: '첨부 파일이 없습니다.',
                      children: [
                        for (final file in event.files)
                          Text(
                            '${file.fileName}${file.fileSize == null ? '' : ' · ${_formatBytes(file.fileSize!)}'}',
                          ),
                        if (event.files.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => onOpenLink(
                                event.files.first.filePath,
                                '파일 ${event.files.length}개',
                              ),
                              icon: const Icon(Icons.download, size: 17),
                              label: Text('파일 ${event.files.length}개 모두 다운로드'),
                            ),
                          ),
                      ],
                    ),
                  if (event.notionLinks.isNotEmpty)
                    _DetailCollection(
                      title: '연결된 Notion',
                      icon: Icons.article_outlined,
                      emptyText: '연결된 Notion 문서가 없습니다.',
                      children: [
                        for (final link in event.notionLinks)
                          Text(link.notionTitle),
                      ],
                    ),
                  _AvaAiRecommendationCard(event: event),
                  _LinkButtons(
                    azoom: azoom,
                    chat: chat,
                    file: file,
                    notion: notion,
                    onOpenLink: onOpenLink,
                    onOpenChatRoom: onOpenChatRoom,
                    onOpenAzoomMeeting: onOpenAzoomMeeting,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, mobile ? 18 : 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _calendarLine)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onEdit(event),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('수정'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5484D),
                      ),
                      onPressed: () => onDelete(event),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('삭제'),
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

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _calendarMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _calendarText,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _calendarLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _calendarText,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(color: _calendarMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _DetailCollection extends StatelessWidget {
  const _DetailCollection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _calendarLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _calendarMuted),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          if (children.isEmpty)
            Text(emptyText, style: const TextStyle(color: _calendarMuted))
          else
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 5), child: child),
        ],
      ),
    );
  }
}

class _AvaAiRecommendationCard extends ConsumerWidget {
  const _AvaAiRecommendationCard({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = _aiRecommendationFor(event);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3D8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: Color(0xFF6D45D5)),
              SizedBox(width: 7),
              Text('AVA AI 추천', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: _calendarText,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final suggestions = await ref
                      .read(calendarControllerProvider.notifier)
                      .suggestAvailability(
                        durationMinutes: event.displayEnd
                            .difference(event.displayStart)
                            .inMinutes
                            .clamp(30, 480)
                            .toInt(),
                      );
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        suggestions.isEmpty
                            ? '추천 가능한 시간이 없습니다.'
                            : '추천 시간 ${suggestions.length}개를 찾았습니다.',
                      ),
                    ),
                  );
                },
                child: const Text('다른 시간 추천'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final conflicts = await ref
                      .read(calendarControllerProvider.notifier)
                      .checkConflicts(event);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        conflicts.isEmpty
                            ? '겹치는 일정이 없습니다.'
                            : '충돌 일정 ${conflicts.length}개를 찾았습니다.',
                      ),
                    ),
                  );
                },
                child: const Text('충돌 확인'),
              ),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('회의 요약 준비 구조가 연결되어 있습니다.')),
                ),
                child: const Text('회의 요약 준비'),
              ),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('관련 파일 추천 구조가 연결되어 있습니다.')),
                ),
                child: const Text('관련 파일 찾기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkButtons extends StatelessWidget {
  const _LinkButtons({
    required this.azoom,
    required this.chat,
    required this.file,
    required this.notion,
    required this.onOpenLink,
    this.onOpenChatRoom,
    this.onOpenAzoomMeeting,
  });

  final CalendarAzoomLink? azoom;
  final CalendarChatLink? chat;
  final CalendarFileLink? file;
  final CalendarNotionLink? notion;
  final CalendarExternalLinkOpener onOpenLink;
  final CalendarChatRoomOpener? onOpenChatRoom;
  final CalendarAzoomOpener? onOpenAzoomMeeting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: azoom == null
                ? () => onOpenLink(null, 'AZOOM')
                : () async {
                    final handler = onOpenAzoomMeeting;
                    if (handler != null) {
                      await handler(azoom!);
                    } else {
                      await onOpenLink(azoom!.azoomJoinUrl, 'AZOOM');
                    }
                  },
            icon: const Icon(Icons.videocam, size: 18),
            label: Text(azoom == null ? '회의 시작' : '회의 입장'),
          ),
          OutlinedButton.icon(
            onPressed: chat == null
                ? () => onOpenLink(null, '채팅방')
                : () async {
                    final handler = onOpenChatRoom;
                    if (handler != null) {
                      await handler(chat!);
                    } else {
                      await onOpenLink(null, chat!.chatRoomName ?? '채팅방');
                    }
                  },
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('채팅방 열기'),
          ),
          OutlinedButton.icon(
            onPressed: () => onOpenLink(file?.filePath, file?.fileName ?? '파일'),
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('파일 열기'),
          ),
          OutlinedButton.icon(
            onPressed: () => onOpenLink(notion?.notionUrl, 'Notion'),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('Notion 열기'),
          ),
        ],
      ),
    );
  }
}

class CalendarEventEditor extends ConsumerStatefulWidget {
  const CalendarEventEditor({super.key, this.event});

  final CalendarEvent? event;

  @override
  ConsumerState<CalendarEventEditor> createState() =>
      _CalendarEventEditorState();
}

class _CalendarEventEditorState extends ConsumerState<CalendarEventEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _memoController;
  late final TextEditingController _attendeesController;
  late final TextEditingController _chatRoomController;
  late final TextEditingController _fileNameController;
  late final TextEditingController _filePathController;
  late final TextEditingController _notionTitleController;
  late final TextEditingController _notionUrlController;
  late final TextEditingController _azoomRoomController;
  late final TextEditingController _azoomUrlController;
  late DateTime _startAt;
  late DateTime _endAt;
  late bool _allDay;
  late String? _categoryId;
  late String? _teamId;
  late String _status;
  late String _importance;
  late String _visibility;
  late String _recurrenceType;
  late int _reminderMinutes;
  late bool _createAzoom;
  bool _draggingFile = false;
  String _color = '#5B7CFA';

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final now = DateTime.now();
    _startAt =
        event?.startAt ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    _endAt = event?.endAt ?? _startAt.add(const Duration(hours: 1));
    _allDay = event?.allDay ?? false;
    _categoryId = event?.categoryId;
    _teamId = event?.teamId;
    _status = event?.status ?? 'SCHEDULED';
    _importance = event?.importance ?? 'NORMAL';
    _visibility = event?.visibility ?? 'ATTENDEES';
    _recurrenceType = event?.recurrence?.recurrenceType ?? 'NONE';
    _reminderMinutes = event?.reminders.firstOrNull?.remindBeforeMinutes ?? 10;
    _createAzoom = event?.hasAzoom ?? false;
    _color = event?.effectiveColor ?? '#5B7CFA';
    _titleController = TextEditingController(text: event?.title ?? '');
    _descriptionController = TextEditingController(
      text: event?.description ?? '',
    );
    _locationController = TextEditingController(text: event?.location ?? '');
    _memoController = TextEditingController(text: event?.memo ?? '');
    _attendeesController = TextEditingController(
      text: event?.attendees.map((item) => item.displayName).join(', ') ?? '',
    );
    _chatRoomController = TextEditingController(
      text: event?.chatLinks.firstOrNull?.chatRoomId ?? '',
    );
    _fileNameController = TextEditingController(
      text: event?.files.firstOrNull?.fileName ?? '',
    );
    _filePathController = TextEditingController(
      text: event?.files.firstOrNull?.filePath ?? '',
    );
    _notionTitleController = TextEditingController(
      text: event?.notionLinks.firstOrNull?.notionTitle ?? '',
    );
    _notionUrlController = TextEditingController(
      text: event?.notionLinks.firstOrNull?.notionUrl ?? '',
    );
    _azoomRoomController = TextEditingController(
      text: event?.azoomLinks.firstOrNull?.azoomRoomId ?? '',
    );
    _azoomUrlController = TextEditingController(
      text: event?.azoomLinks.firstOrNull?.azoomJoinUrl ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _memoController.dispose();
    _attendeesController.dispose();
    _chatRoomController.dispose();
    _fileNameController.dispose();
    _filePathController.dispose();
    _notionTitleController.dispose();
    _notionUrlController.dispose();
    _azoomRoomController.dispose();
    _azoomUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarControllerProvider);
    final editing = widget.event != null;
    final theme = Theme.of(context).copyWith(
      colorScheme: Theme.of(
        context,
      ).colorScheme.copyWith(primary: _calendarPrimary),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
        labelStyle: TextStyle(
          color: _calendarMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: _calendarPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(color: _calendarMuted, fontSize: 13),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _calendarLine),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _calendarPrimary, width: 1.5),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _calendarDanger),
        ),
        focusedErrorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _calendarDanger, width: 1.5),
        ),
      ),
    );

    return Theme(
      data: theme,
      child: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: _calendarSurface,
            child: Column(
              children: [
                _EditorHeader(
                  title: editing ? '일정 수정' : '일정 추가',
                  onClose: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 2, 22, 20),
                      children: [
                        TextFormField(
                          controller: _titleController,
                          style: const TextStyle(
                            color: _calendarText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(labelText: '제목'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? '제목을 입력하세요.'
                              : null,
                        ),
                        TextFormField(
                          controller: _descriptionController,
                          minLines: 2,
                          maxLines: 4,
                          style: const TextStyle(
                            color: _calendarText,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(labelText: '설명'),
                        ),
                        const SizedBox(height: 14),
                        _AllDaySwitchRow(
                          value: _allDay,
                          onChanged: (value) => setState(() => _allDay = value),
                        ),
                        _DateTimePickerRow(
                          label: '시작',
                          value: _startAt,
                          allDay: _allDay,
                          onChanged: (value) {
                            setState(() {
                              final duration = _endAt.difference(_startAt);
                              _startAt = value;
                              _endAt = value.add(
                                duration.isNegative || duration == Duration.zero
                                    ? const Duration(hours: 1)
                                    : duration,
                              );
                            });
                          },
                        ),
                        _DateTimePickerRow(
                          label: '종료',
                          value: _endAt,
                          allDay: _allDay,
                          onChanged: (value) => setState(() => _endAt = value),
                        ),
                        TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(labelText: '장소'),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          initialValue: _teamId,
                          decoration: const InputDecoration(labelText: '팀'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('전체 팀'),
                            ),
                            for (final team in calendarTeams)
                              DropdownMenuItem<String?>(
                                value: team.id,
                                child: Text(team.name),
                              ),
                          ],
                          onChanged: (value) => setState(() => _teamId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          initialValue: _categoryId,
                          decoration: const InputDecoration(labelText: '카테고리'),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('기타'),
                            ),
                            for (final category in state.categories)
                              DropdownMenuItem<String?>(
                                value: category.id,
                                child: Text(category.name),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _categoryId = value;
                              final category = state.categories
                                  .where((item) => item.id == value)
                                  .firstOrNull;
                              if (category != null) {
                                _color = category.color;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _ColorPicker(
                          selectedColor: _color,
                          onChanged: (value) => setState(() => _color = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(labelText: '상태'),
                          items: const [
                            DropdownMenuItem(
                              value: 'SCHEDULED',
                              child: Text('예정'),
                            ),
                            DropdownMenuItem(
                              value: 'IN_PROGRESS',
                              child: Text('진행 중'),
                            ),
                            DropdownMenuItem(
                              value: 'COMPLETED',
                              child: Text('완료'),
                            ),
                            DropdownMenuItem(
                              value: 'CANCELLED',
                              child: Text('취소'),
                            ),
                            DropdownMenuItem(
                              value: 'POSTPONED',
                              child: Text('연기'),
                            ),
                            DropdownMenuItem(
                              value: 'ON_HOLD',
                              child: Text('보류'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'SCHEDULED'),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _importance,
                          decoration: const InputDecoration(labelText: '중요도'),
                          items: const [
                            DropdownMenuItem(value: 'LOW', child: Text('낮음')),
                            DropdownMenuItem(
                              value: 'NORMAL',
                              child: Text('보통'),
                            ),
                            DropdownMenuItem(value: 'HIGH', child: Text('중요')),
                            DropdownMenuItem(
                              value: 'CRITICAL',
                              child: Text('긴급'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _importance = value ?? 'NORMAL'),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _visibility,
                          decoration: const InputDecoration(labelText: '공개 범위'),
                          items: const [
                            DropdownMenuItem(
                              value: 'PRIVATE',
                              child: Text('나만 보기'),
                            ),
                            DropdownMenuItem(
                              value: 'ATTENDEES',
                              child: Text('참석자만 보기'),
                            ),
                            DropdownMenuItem(
                              value: 'TEAM',
                              child: Text('팀원 보기'),
                            ),
                            DropdownMenuItem(
                              value: 'DEPARTMENT',
                              child: Text('부서 보기'),
                            ),
                            DropdownMenuItem(
                              value: 'COMPANY',
                              child: Text('회사 전체 보기'),
                            ),
                            DropdownMenuItem(
                              value: 'ADMIN',
                              child: Text('관리자만 보기'),
                            ),
                          ],
                          onChanged: (value) => setState(
                            () => _visibility = value ?? 'ATTENDEES',
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _recurrenceType,
                          decoration: const InputDecoration(labelText: '반복'),
                          items: const [
                            DropdownMenuItem(
                              value: 'NONE',
                              child: Text('반복 없음'),
                            ),
                            DropdownMenuItem(value: 'DAILY', child: Text('매일')),
                            DropdownMenuItem(
                              value: 'WEEKLY',
                              child: Text('매주'),
                            ),
                            DropdownMenuItem(
                              value: 'MONTHLY',
                              child: Text('매월'),
                            ),
                            DropdownMenuItem(
                              value: 'YEARLY',
                              child: Text('매년'),
                            ),
                            DropdownMenuItem(
                              value: 'WEEKDAYS',
                              child: Text('평일'),
                            ),
                            DropdownMenuItem(
                              value: 'CUSTOM_DAYS',
                              child: Text('특정 요일'),
                            ),
                            DropdownMenuItem(
                              value: 'MONTHLY_DAY',
                              child: Text('매월 특정 날짜'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _recurrenceType = value ?? 'NONE'),
                        ),
                        DropdownButtonFormField<int>(
                          initialValue: _reminderMinutes,
                          decoration: const InputDecoration(labelText: '알림'),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('정시')),
                            DropdownMenuItem(value: 5, child: Text('5분 전')),
                            DropdownMenuItem(value: 10, child: Text('10분 전')),
                            DropdownMenuItem(value: 30, child: Text('30분 전')),
                            DropdownMenuItem(value: 60, child: Text('1시간 전')),
                            DropdownMenuItem(value: 1440, child: Text('하루 전')),
                          ],
                          onChanged: (value) =>
                              setState(() => _reminderMinutes = value ?? 10),
                        ),
                        TextFormField(
                          controller: _attendeesController,
                          decoration: const InputDecoration(
                            labelText: '참석자',
                            hintText: '이름을 쉼표로 구분',
                          ),
                        ),
                        TextFormField(
                          controller: _memoController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: '메모'),
                        ),
                        _EditorSection(
                          title: '연결',
                          children: [
                            _AzoomSwitchRow(
                              value: _createAzoom,
                              onChanged: (value) =>
                                  setState(() => _createAzoom = value),
                            ),
                            if (_createAzoom) ...[
                              TextField(
                                controller: _azoomRoomController,
                                decoration: const InputDecoration(
                                  labelText: 'AZOOM 회의방 ID',
                                ),
                              ),
                              TextField(
                                controller: _azoomUrlController,
                                decoration: const InputDecoration(
                                  labelText: 'AZOOM 입장 URL',
                                ),
                              ),
                            ],
                            TextField(
                              controller: _chatRoomController,
                              decoration: const InputDecoration(
                                labelText: '관련 채팅방 ID',
                              ),
                            ),
                            _FileDropFields(
                              fileNameController: _fileNameController,
                              filePathController: _filePathController,
                              dragging: _draggingFile,
                              onDragEntered: () =>
                                  setState(() => _draggingFile = true),
                              onDragExited: () =>
                                  setState(() => _draggingFile = false),
                              onDropped: _handleDroppedFile,
                            ),
                            TextField(
                              controller: _notionTitleController,
                              decoration: const InputDecoration(
                                labelText: 'Notion 제목',
                              ),
                            ),
                            TextField(
                              controller: _notionUrlController,
                              decoration: const InputDecoration(
                                labelText: 'Notion URL',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _EditorActionBar(
                  onCheckConflicts: _checkConflicts,
                  onSuggestAvailability: _suggestAvailability,
                  onSave: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  CalendarEvent _draftEvent() {
    final attendeeNames = <String>{};
    for (final raw in _attendeesController.text.split(RegExp('[,;\\n]'))) {
      final name = raw.trim();
      if (name.isNotEmpty) {
        attendeeNames.add(name);
      }
    }
    final chatRoomId = _chatRoomController.text.trim();
    final fileName = _fileNameController.text.trim();
    final filePath = _filePathController.text.trim();
    final notionTitle = _notionTitleController.text.trim();
    final notionUrl = _notionUrlController.text.trim();
    final azoomRoom = _azoomRoomController.text.trim();
    final azoomUrl = _azoomUrlController.text.trim();
    return CalendarEvent(
      id: widget.event?.id ?? 'new',
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      startAt: _allDay
          ? DateTime(_startAt.year, _startAt.month, _startAt.day)
          : _startAt,
      endAt: _allDay
          ? DateTime(_endAt.year, _endAt.month, _endAt.day, 23, 59)
          : _endAt,
      allDay: _allDay,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      categoryId: _categoryId,
      color: _color,
      status: _status,
      importance: _importance,
      visibility: _visibility,
      detailVisibility: 'FULL',
      teamId: _teamId,
      memo: _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim(),
      attendees: [
        for (final name in attendeeNames)
          CalendarAttendee(displayName: name, responseStatus: 'PENDING'),
      ],
      reminders: [CalendarReminder(remindBeforeMinutes: _reminderMinutes)],
      recurrence: CalendarRecurrence(recurrenceType: _recurrenceType),
      files: [
        if (fileName.isNotEmpty || filePath.isNotEmpty)
          CalendarFileLink(
            fileName: fileName.isEmpty ? filePath.split('\\').last : fileName,
            filePath: filePath.isEmpty ? null : filePath,
            sourceType: 'NAS',
          ),
      ],
      notionLinks: [
        if (notionTitle.isNotEmpty || notionUrl.isNotEmpty)
          CalendarNotionLink(
            notionTitle: notionTitle.isEmpty ? 'Notion 문서' : notionTitle,
            notionUrl: notionUrl.isEmpty ? null : notionUrl,
          ),
      ],
      chatLinks: [
        if (chatRoomId.isNotEmpty)
          CalendarChatLink(chatRoomId: chatRoomId, chatRoomName: chatRoomId),
      ],
      azoomLinks: [
        if (_createAzoom)
          CalendarAzoomLink(
            azoomRoomId: azoomRoom.isEmpty
                ? 'calendar-${DateTime.now().millisecondsSinceEpoch}'
                : azoomRoom,
            azoomJoinUrl: azoomUrl.isEmpty ? null : azoomUrl,
          ),
      ],
    );
  }

  Future<void> _checkConflicts() async {
    if (!_validateTimeOnly()) {
      return;
    }
    final conflicts = await ref
        .read(calendarControllerProvider.notifier)
        .checkConflicts(_draftEvent());
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(conflicts.isEmpty ? '충돌 없음' : '충돌 일정'),
        content: conflicts.isEmpty
            ? const Text('겹치는 일정이 없습니다.')
            : SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final conflict in conflicts)
                      ListTile(
                        title: Text(conflict.title),
                        subtitle: Text(
                          '${_formatFullDateTime(conflict.startAt)} - ${_formatTime(conflict.endAt)}\n${conflict.reason}',
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _suggestAvailability() async {
    final suggestions = await ref
        .read(calendarControllerProvider.notifier)
        .suggestAvailability(
          durationMinutes: _endAt
              .difference(_startAt)
              .inMinutes
              .clamp(30, 480)
              .toInt(),
        );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            const Text(
              '가능한 시간',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (suggestions.isEmpty)
              const Text('추천 가능한 시간이 없습니다.')
            else
              for (final suggestion in suggestions.take(8))
                ListTile(
                  leading: const Icon(Icons.event_available),
                  title: Text(
                    '${_formatFullDateTime(suggestion.startAt)} - ${_formatTime(suggestion.endAt)}',
                  ),
                  subtitle: Text('추천 점수 ${suggestion.score}'),
                  onTap: () {
                    setState(() {
                      _startAt = suggestion.startAt;
                      _endAt = suggestion.endAt;
                    });
                    Navigator.pop(context);
                  },
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || !_validateTimeOnly()) {
      return;
    }
    final draft = _draftEvent();
    final conflicts = await ref
        .read(calendarControllerProvider.notifier)
        .checkConflicts(draft);
    var ignoreConflicts = false;
    if (conflicts.isNotEmpty && mounted) {
      ignoreConflicts =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('충돌 일정이 있습니다'),
              content: Text('${conflicts.length}개의 일정과 시간이 겹칩니다. 그래도 저장할까요?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('그래도 저장'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (conflicts.isNotEmpty && !ignoreConflicts) {
      return;
    }
    final saved = await ref
        .read(calendarControllerProvider.notifier)
        .saveEvent(draft, ignoreConflicts: ignoreConflicts);
    if (saved != null && mounted) {
      Navigator.pop(context);
    }
  }

  bool _validateTimeOnly() {
    if (!_endAt.isAfter(_startAt)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 합니다.')));
      return false;
    }
    return true;
  }

  void _handleDroppedFile(DropDoneDetails details) {
    final item = details.files.isEmpty ? null : details.files.first;
    if (item == null) {
      return;
    }
    setState(() {
      _draggingFile = false;
      _fileNameController.text = item.name;
      _filePathController.text = item.path;
    });
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 12),
      decoration: const BoxDecoration(
        color: _calendarSurface,
        border: Border(bottom: BorderSide(color: _calendarLine)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _calendarText,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: onClose,
            style: IconButton.styleFrom(
              foregroundColor: _calendarText,
              backgroundColor: _calendarSoftSurface,
              hoverColor: _calendarLine,
              fixedSize: const Size(38, 38),
            ),
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );
  }
}

class _AllDaySwitchRow extends StatelessWidget {
  const _AllDaySwitchRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _EditorSwitchRow(label: '종일 일정', value: value, onChanged: onChanged);
  }
}

class _AzoomSwitchRow extends StatelessWidget {
  const _AzoomSwitchRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _EditorSwitchRow(
      label: 'AZOOM 회의 연결',
      value: value,
      onChanged: onChanged,
      icon: Icons.videocam_outlined,
    );
  }
}

class _EditorSwitchRow extends StatelessWidget {
  const _EditorSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: _calendarMuted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _calendarText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _calendarSurface,
            activeTrackColor: _calendarPrimary,
            inactiveThumbColor: const Color(0xFF7B8190),
            inactiveTrackColor: const Color(0xFFE7EAF1),
          ),
        ],
      ),
    );
  }
}

class _EditorActionBar extends StatelessWidget {
  const _EditorActionBar({
    required this.onCheckConflicts,
    required this.onSuggestAvailability,
    required this.onSave,
  });

  final VoidCallback onCheckConflicts;
  final VoidCallback onSuggestAvailability;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 12 + bottomPadding),
      decoration: const BoxDecoration(
        color: _calendarSurface,
        border: Border(top: BorderSide(color: _calendarLine)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 540;
          final conflictButton = OutlinedButton.icon(
            onPressed: onCheckConflicts,
            style: _editorOutlineButtonStyle,
            icon: const Icon(Icons.rule, size: 17),
            label: const Text('충돌 확인'),
          );
          final suggestButton = OutlinedButton.icon(
            onPressed: onSuggestAvailability,
            style: _editorOutlineButtonStyle,
            icon: const Icon(Icons.event_available, size: 17),
            label: const Text('가능한 시간 찾기'),
          );
          final saveButton = FilledButton.icon(
            onPressed: onSave,
            style: _editorFilledButtonStyle,
            icon: const Icon(Icons.save, size: 17),
            label: const Text('저장'),
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: conflictButton),
                    const SizedBox(width: 10),
                    Expanded(child: suggestButton),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(height: 38, child: saveButton),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: conflictButton),
              const SizedBox(width: 10),
              Expanded(child: suggestButton),
              const SizedBox(width: 10),
              Expanded(child: saveButton),
            ],
          );
        },
      ),
    );
  }
}

final ButtonStyle _editorOutlineButtonStyle = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 36),
  foregroundColor: const Color(0xFF52618C),
  side: const BorderSide(color: Color(0xFF9AA7C0)),
  shape: const StadiumBorder(),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
);

final ButtonStyle _editorFilledButtonStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  backgroundColor: const Color(0xFF5265A2),
  foregroundColor: _calendarSurface,
  shape: const StadiumBorder(),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
);

final ButtonStyle _editorPickerButtonStyle = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 34),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  foregroundColor: const Color(0xFF52618C),
  side: const BorderSide(color: Color(0xFF9AA7C0)),
  shape: const StadiumBorder(),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
);

class _FileDropFields extends StatelessWidget {
  const _FileDropFields({
    required this.fileNameController,
    required this.filePathController,
    required this.dragging,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDropped,
  });

  final TextEditingController fileNameController;
  final TextEditingController filePathController;
  final bool dragging;
  final VoidCallback onDragEntered;
  final VoidCallback onDragExited;
  final ValueChanged<DropDoneDetails> onDropped;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onDragEntered(),
      onDragExited: (_) => onDragExited(),
      onDragDone: onDropped,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: dragging ? const Color(0xFFEFF4FF) : _calendarSoftSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dragging ? _calendarPrimary : _calendarLine,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 18,
                  color: _calendarMuted,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NAS 파일을 여기에 드롭하거나 아래에 직접 입력',
                    style: TextStyle(
                      color: _calendarMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: fileNameController,
              decoration: const InputDecoration(labelText: 'NAS 파일명'),
            ),
            TextField(
              controller: filePathController,
              decoration: const InputDecoration(labelText: 'NAS 파일 경로'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimePickerRow extends StatelessWidget {
  const _DateTimePickerRow({
    required this.label,
    required this.value,
    required this.allDay,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final bool allDay;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: const TextStyle(
                color: _calendarText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: OutlinedButton.icon(
              style: _editorPickerButtonStyle,
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: value,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (date == null) {
                  return;
                }
                onChanged(
                  DateTime(
                    date.year,
                    date.month,
                    date.day,
                    value.hour,
                    value.minute,
                  ),
                );
              },
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                '${value.year}.${value.month}.${value.day}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (!allDay) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: _editorPickerButtonStyle,
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(value),
                  );
                  if (time == null) {
                    return;
                  }
                  onChanged(
                    DateTime(
                      value.year,
                      value.month,
                      value.day,
                      time.hour,
                      time.minute,
                    ),
                  );
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  _formatTime(value),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.only(top: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _calendarLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _calendarText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.selectedColor, required this.onChanged});

  final String selectedColor;
  final ValueChanged<String> onChanged;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late String _selectedColor = widget.selectedColor;

  @override
  void didUpdateWidget(covariant _ColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedColor != widget.selectedColor) {
      _selectedColor = widget.selectedColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    const colors = [
      '#5B7CFA',
      '#2FA872',
      '#F59E0B',
      '#E5484D',
      '#8B5CF6',
      '#0EA5E9',
      '#6B7280',
      '#111827',
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final color in colors)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              setState(() => _selectedColor = color);
              widget.onChanged(color);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 30,
              height: 30,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedColor == color
                      ? _calendarPrimary
                      : _calendarLine,
                  width: _selectedColor == color ? 2 : 1,
                ),
                color: _calendarSurface,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _parseColor(color),
                  shape: BoxShape.circle,
                ),
                child: _selectedColor == color
                    ? const Icon(Icons.check, color: Colors.white, size: 15)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionIcons extends StatelessWidget {
  const _ConnectionIcons({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 3,
      children: [
        if (event.hasAzoom) const Icon(Icons.videocam, size: 16),
        if (event.hasChat) const Icon(Icons.chat_bubble_outline, size: 16),
        if (event.hasFiles) const Icon(Icons.attach_file, size: 16),
        if (event.hasNotion) const Icon(Icons.article_outlined, size: 16),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFCCC7)),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFB42318))),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _calendarLine),
      ),
      child: const Text(
        '등록된 일정이 없습니다.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _calendarMuted),
      ),
    );
  }
}

String _viewModeLabel(CalendarViewMode mode) {
  return switch (mode) {
    CalendarViewMode.month => '월간',
    CalendarViewMode.week => '주간',
    CalendarViewMode.day => '일간',
    CalendarViewMode.list => '리스트',
  };
}

DateTime _monthGridStart(DateTime monthStart) {
  final daysFromSunday = monthStart.weekday % DateTime.daysPerWeek;
  return monthStart.subtract(Duration(days: daysFromSunday));
}

Color _teamColor(int index) {
  const colors = [
    Color(0xFF1463F3),
    Color(0xFF2C7BE5),
    Color(0xFF6D5DFB),
    Color(0xFFF39C12),
    Color(0xFFE85D75),
    Color(0xFF2EA872),
  ];
  return colors[index % colors.length];
}

Color _weekdayDayColor(DateTime date) {
  if (date.weekday == DateTime.sunday) {
    return _calendarDanger;
  }
  if (date.weekday == DateTime.saturday) {
    return _calendarText;
  }
  return _calendarText;
}

int _uniqueAttendeeCount(List<CalendarEvent> events) {
  final names = <String>{};
  for (final event in events) {
    for (final attendee in event.attendees) {
      names.add(attendee.userId ?? attendee.email ?? attendee.displayName);
    }
  }
  return names.length;
}

String _durationLabel(CalendarEvent event) {
  final minutes = event.displayEnd.difference(event.displayStart).inMinutes;
  if (minutes <= 0) {
    return '시간 미정';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) {
    return '$minutes분';
  }
  if (rest == 0) {
    return '$hours시간';
  }
  return '$hours시간 $rest분';
}

String _titleForState(CalendarState state) {
  final date = state.focusedDate;
  return switch (state.viewMode) {
    CalendarViewMode.month ||
    CalendarViewMode.list => '${date.year}년 ${date.month}월',
    CalendarViewMode.week =>
      '${_formatMonthDay(_startOfWeek(date))} - ${_formatMonthDay(_startOfWeek(date).add(const Duration(days: 6)))}',
    CalendarViewMode.day => _formatFullDate(date),
  };
}

String _formatFullDate(DateTime date) {
  return '${date.year}년 ${date.month}월 ${date.day}일 ${_weekdayLabel(date)}요일';
}

String _formatFullDateTime(DateTime date) {
  return '${_formatFullDate(date)} ${_formatTime(date)}';
}

String _formatMonthDay(DateTime date) {
  return '${date.month}/${date.day}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String _aiRecommendationFor(CalendarEvent event) {
  if (event.hasAzoom && event.files.isEmpty) {
    return '회의 전 공유할 자료가 아직 연결되지 않았습니다. 관련 파일을 찾아 첨부하면 참석자가 바로 준비할 수 있어요.';
  }
  if (event.attendees.length >= 2) {
    return '동일 참석자의 충돌 여부를 확인하고, 오후 집중 시간대의 대체 회의 시간을 추천할 수 있습니다.';
  }
  if (event.importance == 'CRITICAL' || event.importance == 'HIGH') {
    return '중요 일정입니다. 하루 전과 정시 리마인더를 함께 유지하는 것을 추천합니다.';
  }
  return '동일한 참석자의 회의가 오후 2시 이후에 없습니다. 이 시간대가 집중도에 가장 적합해요.';
}

String _weekdayLabel(DateTime date) {
  const labels = ['월', '화', '수', '목', '금', '토', '일'];
  return labels[date.weekday - 1];
}

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

bool _sameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Uri? _externalUriFor(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final looksLikeWindowsPath =
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
  if (looksLikeWindowsPath) {
    return Uri.file(value, windows: true);
  }
  if (value.startsWith('/')) {
    return Uri.file(value);
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null || !parsed.hasScheme) {
    return null;
  }
  return parsed;
}

Color _parseColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return _calendarPrimary;
  }
  return Color(0xFF000000 | parsed);
}
