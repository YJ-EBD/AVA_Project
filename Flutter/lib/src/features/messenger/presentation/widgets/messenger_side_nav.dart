import 'dart:io' show exit, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../platform/window_control.dart';
import '../../../auth/application/auth_controller.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';

class MessengerSideNav extends ConsumerWidget {
  const MessengerSideNav({required this.activeTab, super.key});

  final MessengerTab activeTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quietRoomIds = ref.watch(quietChatRoomsProvider).toSet();
    final unreadCount = ref
        .watch(chatRoomsProvider)
        .fold<int>(
          0,
          (count, room) =>
              quietRoomIds.contains(room.id) ? count : count + room.unreadCount,
        );

    return Container(
      width: 64,
      color: const Color(0xFFEDEDED),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _NavIcon(
            icon: Icons.person,
            isActive: activeTab == MessengerTab.friends,
            onTap: () => _selectTab(ref, MessengerTab.friends),
          ),
          const SizedBox(height: 22),
          _NavIcon(
            icon: Icons.chat_bubble,
            isActive: activeTab == MessengerTab.chats,
            badge: unreadCount > 0 ? '$unreadCount' : null,
            onTap: () => _selectTab(ref, MessengerTab.chats),
          ),
          const SizedBox(height: 22),
          _NavIcon(
            key: const ValueKey('side-nav-azoom-button'),
            icon: Icons.videocam,
            isActive: activeTab == MessengerTab.azoom,
            onTap: () => _selectTab(ref, MessengerTab.azoom),
          ),
          const SizedBox(height: 22),
          _NavIcon(
            icon: Icons.auto_awesome,
            isActive: activeTab == MessengerTab.avaAi,
            onTap: () => _selectTab(ref, MessengerTab.avaAi),
          ),
          const SizedBox(height: 28),
          _NavIcon(
            icon: Icons.more_horiz,
            isActive: activeTab == MessengerTab.more,
            onTap: () => _selectTab(ref, MessengerTab.more),
          ),
          const Spacer(),
          const _MutedIcon(icon: Icons.tag_faces_outlined),
          const SizedBox(height: 20),
          const _MutedIcon(icon: Icons.notifications_none),
          const SizedBox(height: 20),
          _SettingsMenuButton(
            onLogout: () => _logout(context, ref),
            onExit: _exitApp,
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  void _selectTab(WidgetRef ref, MessengerTab tab) {
    ref.read(activeMessengerTabProvider.notifier).setTab(tab);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    resetMessengerToCompanyPage(ref);
    await WindowControl.closeAllChatFloatings();
    await WindowControl.compactMessenger();
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      context.go('/');
    }
  }

  void _exitApp() {
    exit(0);
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: '',
            onPressed: onTap,
            icon: Icon(
              icon,
              color: isActive ? Colors.black : const Color(0xFF7A7A7A),
            ),
          ),
          if (badge != null)
            Positioned(top: 0, right: 3, child: _Badge(text: badge!)),
        ],
      ),
    );
  }
}

class _MutedIcon extends StatelessWidget {
  const _MutedIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: const Color(0xFF6F6F6F), size: 22);
  }
}

class _SettingsMenuButton extends StatelessWidget {
  const _SettingsMenuButton({required this.onLogout, required this.onExit});

  final Future<void> Function() onLogout;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        key: const ValueKey('side-nav-settings-button'),
        tooltip: '설정 메뉴',
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => _showMenu(context),
        icon: const Icon(
          Icons.settings_outlined,
          color: Color(0xFF6F6F6F),
          size: 22,
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = context.findRenderObject() as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final _SettingsMenuAction? result;
    if (Platform.isWindows) {
      final value = await WindowControl.showNativeMenu(
        items: const [
          {'value': 'settings', 'label': '설정'},
          {'value': 'lock', 'label': '잠금모드        Ctrl+L'},
          {'value': 'logout', 'label': '로그아웃        Alt+N'},
          {'value': 'exit', 'label': '종료        Alt+X'},
        ],
        x: topLeft.dx + 38,
        y: topLeft.dy - 90,
      );
      result = switch (value) {
        'settings' => _SettingsMenuAction.settings,
        'lock' => _SettingsMenuAction.lock,
        'logout' => _SettingsMenuAction.logout,
        'exit' => _SettingsMenuAction.exit,
        _ => null,
      };
    } else {
      result = await showMenu<_SettingsMenuAction>(
        context: context,
        position: RelativeRect.fromLTRB(
          topLeft.dx + 38,
          topLeft.dy - 90,
          overlay.size.width - topLeft.dx,
          overlay.size.height - topLeft.dy,
        ),
        elevation: 4,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFC8C8C8)),
          borderRadius: BorderRadius.circular(2),
        ),
        items: const [_SettingsPopupMenu()],
      );
    }

    if (!context.mounted) {
      return;
    }

    switch (result) {
      case _SettingsMenuAction.logout:
        await onLogout();
      case _SettingsMenuAction.exit:
        onExit();
      case _SettingsMenuAction.settings:
      case _SettingsMenuAction.lock:
      case null:
        break;
    }
  }
}

enum _SettingsMenuAction { settings, lock, logout, exit }

class _SettingsPopupMenu extends PopupMenuEntry<_SettingsMenuAction> {
  const _SettingsPopupMenu();

  static const double itemHeight = 26;
  static const double menuWidth = 128;

  @override
  double get height => itemHeight * 4;

  @override
  bool represents(_SettingsMenuAction? value) => false;

  @override
  State<_SettingsPopupMenu> createState() => _SettingsPopupMenuState();
}

class _SettingsPopupMenuState extends State<_SettingsPopupMenu> {
  _SettingsMenuAction? _hoveredAction;

  void _setHovered(_SettingsMenuAction? action) {
    if (_hoveredAction == action) {
      return;
    }
    setState(() {
      _hoveredAction = action;
    });
  }

  void _updateHoveredFromOffset(Offset localPosition) {
    final index = localPosition.dy ~/ _SettingsPopupMenu.itemHeight;
    final action = switch (index) {
      0 => _SettingsMenuAction.settings,
      1 => _SettingsMenuAction.lock,
      2 => _SettingsMenuAction.logout,
      3 => _SettingsMenuAction.exit,
      _ => null,
    };
    _setHovered(action);
  }

  void _select(_SettingsMenuAction action) {
    Navigator.pop<_SettingsMenuAction>(context, action);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (event) => _updateHoveredFromOffset(event.localPosition),
      onExit: (_) => _setHovered(null),
      child: SizedBox(
        width: _SettingsPopupMenu.menuWidth,
        height: _SettingsPopupMenu.itemHeight * 4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SettingsMenuRow(
              action: _SettingsMenuAction.settings,
              label: '설정',
              isHovered: _hoveredAction == _SettingsMenuAction.settings,
              onTap: _select,
            ),
            _SettingsMenuRow(
              action: _SettingsMenuAction.lock,
              label: '잠금모드',
              shortcut: 'Ctrl+L',
              isHovered: _hoveredAction == _SettingsMenuAction.lock,
              onTap: _select,
            ),
            _SettingsMenuRow(
              action: _SettingsMenuAction.logout,
              label: '로그아웃',
              shortcut: 'Alt+N',
              isHovered: _hoveredAction == _SettingsMenuAction.logout,
              onTap: _select,
            ),
            _SettingsMenuRow(
              action: _SettingsMenuAction.exit,
              label: '종료',
              shortcut: 'Alt+X',
              isHovered: _hoveredAction == _SettingsMenuAction.exit,
              onTap: _select,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsMenuRow extends StatelessWidget {
  const _SettingsMenuRow({
    required this.action,
    required this.label,
    required this.isHovered,
    required this.onTap,
    this.shortcut,
  });

  final _SettingsMenuAction action;
  final String label;
  final bool isHovered;
  final ValueChanged<_SettingsMenuAction> onTap;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(action),
      child: Container(
        width: _SettingsPopupMenu.menuWidth,
        height: _SettingsPopupMenu.itemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ),
            if (shortcut != null)
              Text(
                shortcut!,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('side-nav-unread-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4B2B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}
