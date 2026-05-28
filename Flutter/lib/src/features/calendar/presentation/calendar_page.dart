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
const Color _calendarBackground = Color(0xFFF6F8FC);
const Color _calendarLine = Color(0xFFE2E7EF);
const Color _calendarText = Color(0xFF1F2937);
const Color _calendarMuted = Color(0xFF687385);
const Color _calendarPrimary = Color(0xFF3157D5);

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
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 44,
            vertical: 28,
          ),
          child: SizedBox(width: 720, child: child),
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
    return Row(
      children: [
        SizedBox(
          width: 264,
          child: _CalendarSidebar(
            state: state,
            compact: false,
            onAddCategory: _showCategoryDialog,
          ),
        ),
        const VerticalDivider(width: 1, color: _calendarLine),
        Expanded(
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
        const VerticalDivider(width: 1, color: _calendarLine),
        SizedBox(
          width: 344,
          child: _EventDetailPanel(
            event: state.selectedEvent,
            onEdit: onEdit,
            onDelete: onDelete,
            onOpenLink: onOpenLink,
            onOpenChatRoom: onOpenChatRoom,
            onOpenAzoomMeeting: onOpenAzoomMeeting,
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 22,
        12,
        compact ? 14 : 22,
        10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _calendarLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '이전',
                onPressed: () => controller.move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _titleForState(state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _calendarText,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: '다음',
                onPressed: () => controller.move(1),
                icon: const Icon(Icons.chevron_right),
              ),
              if (!compact) const SizedBox(width: 8),
              if (!compact)
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('일정 추가'),
                )
              else
                IconButton(
                  tooltip: '일정 추가',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: controller.goToday,
                icon: const Icon(Icons.today, size: 17),
                label: const Text('오늘'),
              ),
              _ViewModeButton(
                label: '월간',
                selected: state.viewMode == CalendarViewMode.month,
                onTap: () => controller.setViewMode(CalendarViewMode.month),
              ),
              _ViewModeButton(
                label: '주간',
                selected: state.viewMode == CalendarViewMode.week,
                onTap: () => controller.setViewMode(CalendarViewMode.week),
              ),
              _ViewModeButton(
                label: '일간',
                selected: state.viewMode == CalendarViewMode.day,
                onTap: () => controller.setViewMode(CalendarViewMode.day),
              ),
              _ViewModeButton(
                label: '리스트',
                selected: state.viewMode == CalendarViewMode.list,
                onTap: () => controller.setViewMode(CalendarViewMode.list),
              ),
              SizedBox(
                width: compact ? 170 : 260,
                height: 40,
                child: TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '검색 지우기',
                            onPressed: () {
                              searchController.clear();
                              controller.setSearchQuery('');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    hintText: '검색',
                    isDense: true,
                    filled: true,
                    fillColor: _calendarBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: controller.setSearchQuery,
                ),
              ),
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
      height: 40,
      child: selected
          ? FilledButton(onPressed: onTap, child: Text(label))
          : OutlinedButton(onPressed: onTap, child: Text(label)),
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
    required this.onAddCategory,
  });

  final CalendarState state;
  final bool compact;
  final ValueChanged<BuildContext> onAddCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedEvents = state.selectedDateEvents(state.selectedDate);
    return Container(
      color: Colors.white,
      child: SafeArea(
        right: false,
        child: ListView(
          padding: EdgeInsets.all(compact ? 14 : 18),
          children: [
            Text(
              '캘린더',
              style: TextStyle(
                color: _calendarText,
                fontSize: compact ? 18 : 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _MiniCalendar(state: state),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '카테고리',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '카테고리 추가',
                  onPressed: () => onAddCategory(context),
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
            for (final category in state.categories)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value:
                    state.visibleCategoryIds.isEmpty ||
                    state.visibleCategoryIds.contains(category.id),
                onChanged: (_) => ref
                    .read(calendarControllerProvider.notifier)
                    .toggleCategory(category.id),
                secondary: _ColorDot(color: _parseColor(category.color)),
                title: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Divider(height: 28),
            const Text('선택 날짜', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              _formatFullDate(state.selectedDate),
              style: const TextStyle(color: _calendarMuted),
            ),
            const SizedBox(height: 12),
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
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday - DateTime.monday),
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${monthStart.month}월',
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
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday - DateTime.monday),
    );
    final cellAspect = desktop ? 1.38 : 0.86;
    return ListView(
      padding: EdgeInsets.all(desktop ? 18 : 12),
      children: [
        _WeekHeader(compact: !desktop),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
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
                ref.read(calendarControllerProvider.notifier).selectDate(date);
                if (!desktop && events.isNotEmpty) {
                  _showDayEvents(context, date, events);
                }
              },
              onEventTap: onEventTap,
            );
          },
        ),
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
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
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
    return Material(
      color: selected ? const Color(0xFFEFF3FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onDateTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(desktop ? 8 : 5),
          decoration: BoxDecoration(
            border: Border.all(
              color: today ? _calendarPrimary : _calendarLine,
              width: today ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: desktop ? 26 : 22,
                    height: desktop ? 26 : 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: today ? _calendarPrimary : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        color: today
                            ? Colors.white
                            : inMonth
                            ? _calendarText
                            : _calendarMuted,
                        fontWeight: today || selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        fontSize: desktop ? 13 : 11,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (events.isNotEmpty && !desktop)
                    Text(
                      '${events.length}',
                      style: const TextStyle(
                        color: _calendarMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (desktop)
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final event in events.take(4))
                        _MonthEventPill(
                          event: event,
                          onTap: () => onEventTap(event),
                        ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 3,
                  runSpacing: 3,
                  children: [
                    for (final event in events.take(5))
                      _ColorDot(
                        color: _parseColor(event.effectiveColor),
                        size: 6,
                      ),
                  ],
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
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              _ColorDot(color: color, size: 6),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _calendarText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatFullDate(state.selectedDate),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
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
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: _calendarLine),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 4,
          height: 46,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatMonthDayTime(event.displayStart)} - ${_formatMonthDayTime(event.displayEnd)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _ConnectionIcons(event: event),
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
        color: Colors.white,
        child: const Center(child: Text('선택한 일정이 없습니다.')),
      );
    }
    final azoom = event.azoomLinks.isEmpty ? null : event.azoomLinks.first;
    final chat = event.chatLinks.isEmpty ? null : event.chatLinks.first;
    final notion = event.notionLinks.isEmpty ? null : event.notionLinks.first;
    final file = event.files.isEmpty ? null : event.files.first;
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(mobile ? 18 : 22),
                children: [
                  Row(
                    children: [
                      _ColorDot(
                        color: _parseColor(event.effectiveColor),
                        size: 12,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DetailLine(
                    icon: Icons.schedule,
                    label:
                        '${_formatFullDateTime(event.displayStart)}\n${_formatFullDateTime(event.displayEnd)}',
                  ),
                  if (event.location != null)
                    _DetailLine(icon: Icons.place, label: event.location!),
                  _DetailLine(
                    icon: Icons.flag,
                    label:
                        '${event.category?.name ?? '기타'} · ${calendarStatusLabel(event.status)}',
                  ),
                  _DetailLine(
                    icon: Icons.visibility,
                    label:
                        '${calendarVisibilityLabel(event.visibility)} · ${event.detailVisibility}',
                  ),
                  if (event.description != null &&
                      event.description!.trim().isNotEmpty)
                    _DetailBlock(title: '설명', text: event.description!),
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
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: _calendarMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(height: 1.45))),
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
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(height: 1.45)),
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
    return Padding(
      padding: const EdgeInsets.only(top: 18),
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
            ...children,
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
  late String _status;
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
    _status = event?.status ?? 'SCHEDULED';
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
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    editing ? '일정 수정' : '일정 추가',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: '제목'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '제목을 입력하세요.'
                        : null,
                  ),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '설명'),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allDay,
                    onChanged: (value) => setState(() => _allDay = value),
                    title: const Text('종일 일정'),
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
                  const SizedBox(height: 12),
                  _ColorPicker(
                    selectedColor: _color,
                    onChanged: (value) => setState(() => _color = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: '상태'),
                    items: const [
                      DropdownMenuItem(value: 'SCHEDULED', child: Text('예정')),
                      DropdownMenuItem(
                        value: 'IN_PROGRESS',
                        child: Text('진행 중'),
                      ),
                      DropdownMenuItem(value: 'COMPLETED', child: Text('완료')),
                      DropdownMenuItem(value: 'CANCELLED', child: Text('취소')),
                      DropdownMenuItem(value: 'POSTPONED', child: Text('연기')),
                      DropdownMenuItem(value: 'ON_HOLD', child: Text('보류')),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? 'SCHEDULED'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _visibility,
                    decoration: const InputDecoration(labelText: '공개 범위'),
                    items: const [
                      DropdownMenuItem(value: 'PRIVATE', child: Text('나만 보기')),
                      DropdownMenuItem(
                        value: 'ATTENDEES',
                        child: Text('참석자만 보기'),
                      ),
                      DropdownMenuItem(value: 'TEAM', child: Text('팀원 보기')),
                      DropdownMenuItem(
                        value: 'DEPARTMENT',
                        child: Text('부서 보기'),
                      ),
                      DropdownMenuItem(
                        value: 'COMPANY',
                        child: Text('회사 전체 보기'),
                      ),
                      DropdownMenuItem(value: 'ADMIN', child: Text('관리자만 보기')),
                    ],
                    onChanged: (value) =>
                        setState(() => _visibility = value ?? 'ATTENDEES'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _recurrenceType,
                    decoration: const InputDecoration(labelText: '반복'),
                    items: const [
                      DropdownMenuItem(value: 'NONE', child: Text('반복 없음')),
                      DropdownMenuItem(value: 'DAILY', child: Text('매일')),
                      DropdownMenuItem(value: 'WEEKLY', child: Text('매주')),
                      DropdownMenuItem(value: 'MONTHLY', child: Text('매월')),
                      DropdownMenuItem(value: 'YEARLY', child: Text('매년')),
                      DropdownMenuItem(value: 'WEEKDAYS', child: Text('평일')),
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
                  const SizedBox(height: 18),
                  _EditorSection(
                    title: '연결',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _createAzoom,
                        onChanged: (value) =>
                            setState(() => _createAzoom = value),
                        title: const Text('AZOOM 회의 연결'),
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
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _calendarLine)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checkConflicts,
                    icon: const Icon(Icons.rule, size: 18),
                    label: const Text('충돌 확인'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _suggestAvailability,
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('가능한 시간 찾기'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('저장'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      visibility: _visibility,
      detailVisibility: 'FULL',
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
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: dragging ? const Color(0xFFEFF4FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: dragging ? _calendarPrimary : _calendarLine,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: const [
                Icon(Icons.upload_file, size: 18, color: _calendarMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NAS 파일을 여기에 드롭하거나 아래에 직접 입력',
                    style: TextStyle(color: _calendarMuted),
                  ),
                ),
              ],
            ),
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
          SizedBox(width: 46, child: Text(label)),
          Expanded(
            child: OutlinedButton.icon(
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
              label: Text('${value.year}.${value.month}.${value.day}'),
            ),
          ),
          if (!allDay) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
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
                label: Text(_formatTime(value)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ...children,
      ],
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
      spacing: 8,
      children: [
        for (final color in colors)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _selectedColor = color);
              widget.onChanged(color);
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _parseColor(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedColor == color ? Colors.black : Colors.white,
                  width: 2,
                ),
              ),
              child: _selectedColor == color
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
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

String _formatMonthDayTime(DateTime date) {
  return '${date.month}/${date.day} ${_formatTime(date)}';
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
