import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';
import '../data/admin_api.dart';

class AdminPanel extends ConsumerStatefulWidget {
  const AdminPanel({super.key});

  @override
  ConsumerState<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends ConsumerState<AdminPanel> {
  AdminOverviewDto? _overview;
  List<AdminUserDto> _users = const [];
  List<AdminUserDto> _pendingApprovals = const [];
  bool _loading = false;
  String? _error;
  String? _loadedAccessToken;
  String? _loadedCompany;
  bool _loadQueued = false;
  final Set<String> _busyUserIds = {};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || !_canUseAdminPanel(session.user.role)) {
      return;
    }
    _loadQueued = false;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(adminApiProvider);
      final overview = await api.overview(session.accessToken);
      final pendingApprovals = await api.pendingApprovals(session.accessToken);
      final users = await api.users(session.accessToken);
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _pendingApprovals = pendingApprovals;
        _users = users;
        _loadedAccessToken = session.accessToken;
        _loadedCompany = ref.read(activeCompanyProvider);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _approve(AdminUserDto user) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || _busyUserIds.contains(user.id)) {
      return;
    }
    setState(() {
      _busyUserIds.add(user.id);
      _error = null;
    });
    try {
      final updated = await ref
          .read(adminApiProvider)
          .approveUser(accessToken: session.accessToken, userId: user.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingApprovals = [
          for (final item in _pendingApprovals)
            if (item.id != updated.id) item,
        ];
        _users = _replaceUser(_users, updated);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(user.id));
      }
    }
  }

  Future<void> _editUser(AdminUserDto user) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || _busyUserIds.contains(user.id)) {
      return;
    }
    final isSelf = user.id == session.user.id;
    final result = await showDialog<_UserEditResult>(
      context: context,
      builder: (context) {
        return _EditUserDialog(
          user: user,
          canGrantSuperuser: _isSuperuser(session.user.role),
          isSelf: isSelf,
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _busyUserIds.add(user.id);
      _error = null;
    });
    try {
      final updated = await ref
          .read(adminApiProvider)
          .updateUser(
            accessToken: session.accessToken,
            userId: user.id,
            displayName: result.displayName,
            role: isSelf ? null : result.role,
            enabled: isSelf ? null : result.enabled,
            department: result.department,
            position: result.position,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _users = _replaceUser(_users, updated);
        _pendingApprovals = updated.enabled
            ? [
                for (final item in _pendingApprovals)
                  if (item.id != updated.id) item,
              ]
            : _replaceUser(_pendingApprovals, updated);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyUserIds.remove(user.id));
      }
    }
  }

  List<AdminUserDto> _replaceUser(
    List<AdminUserDto> users,
    AdminUserDto updated,
  ) {
    var replaced = false;
    final next = [
      for (final user in users)
        if (user.id == updated.id) ...[updated] else ...[user],
    ];
    replaced = users.any((user) => user.id == updated.id);
    return replaced ? next : [updated, ...users];
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value?.session;
    if (session == null || !_canUseAdminPanel(session.user.role)) {
      return const SizedBox.shrink();
    }
    final activeCompany = ref.watch(activeCompanyProvider);
    if (!_loading &&
        !_loadQueued &&
        (_loadedAccessToken != session.accessToken ||
            _loadedCompany != activeCompany)) {
      _loadQueued = true;
      Future<void>.microtask(_load);
    }

    final companyName = _isSuperuser(session.user.role)
        ? '전체 회사'
        : (session.user.companyName?.isNotEmpty == true
              ? session.user.companyName!
              : '내 회사');

    final scopedCompanyName = activeCompany?.isNotEmpty == true
        ? activeCompany!
        : companyName;

    return Container(
      key: const ValueKey('admin-panel-root'),
      color: const Color(0xFFF3F7FC),
      child: Column(
        children: [
          _AdminHeader(
            companyName: scopedCompanyName,
            role: session.user.role,
            loading: _loading,
            onRefresh: _load,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF4F65C8),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
                children: [
                  if (_error != null) ...[
                    _AdminError(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  if (_overview != null)
                    _AdminStats(
                      overview: _overview!,
                      pendingCount: _pendingApprovals.length,
                    )
                  else if (_loading)
                    const SizedBox(
                      height: 108,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  const SizedBox(height: 14),
                  _AdminDashboardSections(
                    pendingApprovals: _pendingApprovals,
                    users: _users,
                    busyUserIds: _busyUserIds,
                    onApprove: _approve,
                    onEdit: _editUser,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _canUseAdminPanel(String role) {
  final normalized = role.toUpperCase();
  return normalized == 'ADMIN' || normalized == 'SUPERUSER';
}

bool _isSuperuser(String role) => role.toUpperCase() == 'SUPERUSER';

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({
    required this.companyName,
    required this.role,
    required this.loading,
    required this.onRefresh,
  });

  final String companyName;
  final String role;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF4663CF), Color(0xFF4E41A9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '관리자 페이지',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$companyName · ${role.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _AdminStats extends StatelessWidget {
  const _AdminStats({required this.overview, required this.pendingCount});

  final AdminOverviewDto overview;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem('전체 유저', overview.totalUsers, Icons.people_alt_rounded),
      _StatItem('활성 계정', overview.enabledUsers, Icons.verified_rounded),
      _StatItem('승인 대기', pendingCount, Icons.pending_actions_rounded),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items) _AdminStatCard(width: width, item: item),
          ],
        );
      },
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({required this.width, required this.item});

  final double width;
  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.clamp(96.0, 100000.0),
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE6F2)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(item.icon, color: const Color(0xFF4F65C8), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF68758A),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${item.value}',
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboardSections extends StatelessWidget {
  const _AdminDashboardSections({
    required this.pendingApprovals,
    required this.users,
    required this.busyUserIds,
    required this.onApprove,
    required this.onEdit,
  });

  final List<AdminUserDto> pendingApprovals;
  final List<AdminUserDto> users;
  final Set<String> busyUserIds;
  final Future<void> Function(AdminUserDto user) onApprove;
  final Future<void> Function(AdminUserDto user) onEdit;

  @override
  Widget build(BuildContext context) {
    final pendingSection = _AdminSection(
      icon: Icons.how_to_reg_rounded,
      title: '가입 승인대기',
      subtitle: '승인 전 사용자는 로그인할 수 없습니다.',
      child: _PendingApprovalList(
        users: pendingApprovals,
        busyUserIds: busyUserIds,
        onApprove: onApprove,
        onEdit: onEdit,
      ),
    );
    final usersSection = _AdminSection(
      icon: Icons.group_rounded,
      title: '유저 관리',
      subtitle: '부서, 직책, 권한, 계정 활성 상태를 관리합니다.',
      child: _AdminUserList(
        users: users,
        busyUserIds: busyUserIds,
        onEdit: onEdit,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: pendingSection),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: usersSection),
            ],
          );
        }
        return Column(
          children: [pendingSection, const SizedBox(height: 14), usersSection],
        );
      },
    );
  }
}

class _AdminSection extends StatelessWidget {
  const _AdminSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE6F2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF4F65C8), size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF101828),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF68758A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6EEF7)),
          child,
        ],
      ),
    );
  }
}

class _PendingApprovalList extends StatelessWidget {
  const _PendingApprovalList({
    required this.users,
    required this.busyUserIds,
    required this.onApprove,
    required this.onEdit,
  });

  final List<AdminUserDto> users;
  final Set<String> busyUserIds;
  final Future<void> Function(AdminUserDto user) onApprove;
  final Future<void> Function(AdminUserDto user) onEdit;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const _EmptyAdminState(
        icon: Icons.mark_email_read_rounded,
        message: '승인 대기 중인 가입 요청이 없습니다.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          for (final user in users) ...[
            _PendingApprovalTile(
              user: user,
              busy: busyUserIds.contains(user.id),
              onApprove: () => onApprove(user),
              onEdit: () => onEdit(user),
            ),
            if (user != users.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PendingApprovalTile extends StatelessWidget {
  const _PendingApprovalTile({
    required this.user,
    required this.busy,
    required this.onApprove,
    required this.onEdit,
  });

  final AdminUserDto user;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _AdminUserCardFrame(
      key: ValueKey('pending-approval-tile-${user.id}'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = _PendingApprovalActions(
            busy: busy,
            onEdit: onEdit,
            onApprove: onApprove,
          );
          return _AdminUserTileLayout(
            user: user,
            trailing: actions,
            compact: constraints.maxWidth < 520,
          );
        },
      ),
    );
  }
}

class _AdminUserList extends StatelessWidget {
  const _AdminUserList({
    required this.users,
    required this.busyUserIds,
    required this.onEdit,
  });

  final List<AdminUserDto> users;
  final Set<String> busyUserIds;
  final Future<void> Function(AdminUserDto user) onEdit;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const _EmptyAdminState(
        icon: Icons.people_outline_rounded,
        message: '등록된 유저가 없습니다.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          for (final user in users) ...[
            _AdminUserTile(
              user: user,
              busy: busyUserIds.contains(user.id),
              onEdit: () => onEdit(user),
            ),
            if (user != users.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AdminUserTile extends StatelessWidget {
  const _AdminUserTile({
    required this.user,
    required this.busy,
    required this.onEdit,
  });

  final AdminUserDto user;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _AdminUserCardFrame(
      key: ValueKey('admin-user-tile-${user.id}'),
      onTap: busy ? null : onEdit,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = _AdminUserActions(
            user: user,
            busy: busy,
            onEdit: onEdit,
          );
          return _AdminUserTileLayout(
            user: user,
            trailing: actions,
            compact: constraints.maxWidth < 560,
          );
        },
      ),
    );
  }
}

class _AdminUserCardFrame extends StatelessWidget {
  const _AdminUserCardFrame({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          border: Border.all(color: const Color(0xFFE2EAF5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AdminUserTileLayout extends StatelessWidget {
  const _AdminUserTileLayout({
    required this.user,
    required this.trailing,
    required this.compact,
  });

  final AdminUserDto user;
  final Widget trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _UserAvatar(user: user),
        const SizedBox(width: 12),
        Expanded(child: _UserSummary(user: user)),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity,
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: trailing),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: identity),
        const SizedBox(width: 16),
        trailing,
      ],
    );
  }
}

class _PendingApprovalActions extends StatelessWidget {
  const _PendingApprovalActions({
    required this.busy,
    required this.onEdit,
    required this.onApprove,
  });

  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AdminIconButton(
          tooltip: '상세 설정',
          icon: Icons.tune_rounded,
          onPressed: busy ? null : onEdit,
        ),
        _PrimaryAdminButton(
          label: busy ? '처리중' : '승인',
          icon: Icons.check_rounded,
          onPressed: busy ? null : onApprove,
        ),
      ],
    );
  }
}

class _AdminUserActions extends StatelessWidget {
  const _AdminUserActions({
    required this.user,
    required this.busy,
    required this.onEdit,
  });

  final AdminUserDto user;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _RoleChip(role: user.role),
        _StatusChip(enabled: user.enabled),
        _AdminIconButton(
          tooltip: '유저 설정',
          icon: Icons.edit_rounded,
          onPressed: busy ? null : onEdit,
        ),
      ],
    );
  }
}

class _UserSummary extends StatelessWidget {
  const _UserSummary({required this.user});

  final AdminUserDto user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.isEmpty ? user.email : user.displayName;
    final department = user.department.isEmpty ? '부서 미지정' : user.department;
    final position = user.position.isEmpty ? '직책 미지정' : user.position;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 14,
            height: 1.18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          user.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF667085),
            fontSize: 12,
            height: 1.22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${user.companyName} · $department · $position',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF8A96A8),
            fontSize: 12,
            height: 1.22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final AdminUserDto user;

  @override
  Widget build(BuildContext context) {
    final source = user.displayName.isNotEmpty ? user.displayName : user.email;
    final label = source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: user.enabled ? const Color(0xFFEAF0FF) : const Color(0xFFF1F2F4),
        border: Border.all(
          color: user.enabled
              ? const Color(0xFFD9E3FF)
              : const Color(0xFFE3E7EE),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: user.enabled
              ? const Color(0xFF4F65C8)
              : const Color(0xFF8A96A8),
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final normalized = role.toUpperCase();
    final color = normalized == 'SUPERUSER'
        ? const Color(0xFF7A3CE7)
        : normalized == 'ADMIN'
        ? const Color(0xFF1849C6)
        : const Color(0xFF475467);
    return _Chip(label: normalized, color: color);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _Chip(
      label: enabled ? '활성' : '승인대기',
      color: enabled ? const Color(0xFF078C55) : const Color(0xFFB54708),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
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

class _AdminIconButton extends StatelessWidget {
  const _AdminIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          color: const Color(0xFF526071),
          disabledColor: const Color(0xFFCBD5E1),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF3F7FC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryAdminButton extends StatelessWidget {
  const _PrimaryAdminButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF4F65C8),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFC9D3F8),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.78),
        minimumSize: const Size(76, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF9AA7BA), size: 26),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({
    required this.user,
    required this.canGrantSuperuser,
    required this.isSelf,
  });

  final AdminUserDto user;
  final bool canGrantSuperuser;
  final bool isSelf;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _departmentController;
  late final TextEditingController _positionController;
  late String _role;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    _departmentController = TextEditingController(text: widget.user.department);
    _positionController = TextEditingController(text: widget.user.position);
    _role = widget.user.role.toUpperCase();
    _enabled = widget.user.enabled;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _departmentController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = ['USER', 'ADMIN', if (widget.canGrantSuperuser) 'SUPERUSER'];
    if (!roles.contains(_role)) {
      _role = roles.first;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 430,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4663CF), Color(0xFF4E41A9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.manage_accounts_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '유저 설정',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1D2939),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AdminField(label: '이름', controller: _displayNameController),
                  const SizedBox(height: 10),
                  _AdminField(label: '부서', controller: _departmentController),
                  const SizedBox(height: 10),
                  _AdminField(label: '직책', controller: _positionController),
                  const SizedBox(height: 10),
                  if (widget.isSelf) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F7FC),
                        border: Border.all(color: const Color(0xFFDDE6F2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '내 계정은 이름, 부서, 직책만 수정할 수 있습니다.',
                        style: TextStyle(
                          color: Color(0xFF344054),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      '권한',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      dropdownColor: Colors.white,
                      iconEnabledColor: const Color(0xFF101828),
                      style: const TextStyle(
                        color: Color(0xFF101828),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                      items: [
                        for (final role in roles)
                          DropdownMenuItem(
                            value: role,
                            child: Text(
                              role,
                              style: const TextStyle(
                                color: Color(0xFF101828),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _role = value);
                        }
                      },
                      decoration: _dialogInputDecoration(),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '로그인 허용',
                        style: TextStyle(
                          color: Color(0xFF101828),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      subtitle: Text(
                        _enabled ? '활성 계정입니다.' : '승인 전 또는 비활성 계정입니다.',
                        style: const TextStyle(
                          color: Color(0xFF344054),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      activeThumbColor: const Color(0xFF4F65C8),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE6EEF7)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  _PrimaryAdminButton(
                    label: '저장',
                    icon: Icons.save_rounded,
                    onPressed: () {
                      Navigator.of(context).pop(
                        _UserEditResult(
                          displayName: _displayNameController.text.trim(),
                          department: _departmentController.text.trim(),
                          position: _positionController.text.trim(),
                          role: _role,
                          enabled: _enabled,
                        ),
                      );
                    },
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

class _AdminField extends StatelessWidget {
  const _AdminField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          cursorColor: const Color(0xFF4F65C8),
          style: const TextStyle(
            color: Color(0xFF101828),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: _dialogInputDecoration(),
        ),
      ],
    );
  }
}

InputDecoration _dialogInputDecoration() {
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFFFFFFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintStyle: const TextStyle(
      color: Color(0xFF667085),
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE6F2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE6F2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF4F65C8), width: 1.5),
    ),
  );
}

class _UserEditResult {
  const _UserEditResult({
    required this.displayName,
    required this.department,
    required this.position,
    required this.role,
    required this.enabled,
  });

  final String displayName;
  final String department;
  final String position;
  final String role;
  final bool enabled;
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F3),
        border: Border.all(color: const Color(0xFFFFCDD5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB42318),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
