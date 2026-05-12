import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../platform/window_control.dart';
import '../../../../shared/ava_toast.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/auth_api.dart';
import '../../data/chat_api.dart';
import '../../data/mock_messenger_data.dart';
import '../../domain/messenger_models.dart';
import '../messenger_page.dart';
import 'panel_header.dart';
import 'profile_avatar.dart';

const _online = '\uC628\uB77C\uC778';
const _background = '\uBC31\uADF8\uB77C\uC6B4\uB4DC';
const _offline = '\uC624\uD504\uB77C\uC778';
const _selfChatLabel = '\uB098\uC640\uC758 \uCC44\uD305';
const _directChatLabel = '1:1 \uCC44\uD305';
const _profileEditLabel = '\uD504\uB85C\uD544 \uD3B8\uC9D1';
const _multiProfileLabel = '\uBA40\uD2F0\uD504\uB85C\uD544 +';
const _defaultCompanyName = 'ABBA-S';

class _CompanySearchIntent extends Intent {
  const _CompanySearchIntent();
}

final friendGroupExpansionProvider =
    NotifierProvider<FriendGroupExpansion, Map<String, bool>>(
      FriendGroupExpansion.new,
    );

class FriendGroupExpansion extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  bool isExpanded(String title) => state[title] ?? true;

  void toggle(String title) {
    state = {...state, title: !isExpanded(title)};
  }
}

class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key});

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _openSearch();
      return true;
    }
    return false;
  }

  void _openSearch() {
    setState(() => _isSearching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentProfile = ref.watch(currentUserProfileProvider);
    final allProfiles = ref.watch(userProfilesProvider).value ?? const [];
    final groups = ref.watch(friendGroupsProvider);
    final updatedProfiles = ref.watch(updatedUserProfilesProvider);
    final profilesState = ref.watch(userProfilesProvider);
    final companyName = _companyTitle(currentProfile, allProfiles);
    final query = _searchController.text.trim();
    final searchResults = _filterProfiles(allProfiles, query);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _CompanySearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _CompanySearchIntent: CallbackAction<_CompanySearchIntent>(
            onInvoke: (_) {
              _openSearch();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: Colors.white,
            child: Column(
              children: [
                PanelHeader(
                  title: companyName,
                  titleFontWeight: FontWeight.w500,
                  actions: [
                    HeaderIconButton(
                      icon: Icons.search,
                      tooltip: '\uAC80\uC0C9 Ctrl+F',
                      onPressed: _openSearch,
                    ),
                    HeaderIconButton(
                      icon: Icons.person_add_alt_1_outlined,
                      tooltip: '\uC9C1\uC6D0',
                      onPressed: () => _showEmployeeAddDialog(context, ref),
                    ),
                  ],
                ),
                if (_isSearching)
                  _CompanySearchBar(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) => setState(() {}),
                    onClose: _closeSearch,
                  ),
                Expanded(
                  child: _isSearching
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(22, 8, 14, 16),
                          children: [
                            _MyProfile(
                              profile: currentProfile,
                              onAvatarTap: () => _showSelfProfile(
                                context,
                                ref,
                                currentProfile,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFFEDEDED)),
                            _SearchResultSection(
                              count: searchResults.length,
                              users: searchResults,
                              onUserTap: (user) =>
                                  _showUserProfile(context, ref, user),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                          children: [
                            _MyProfile(
                              profile: currentProfile,
                              onAvatarTap: () => _showSelfProfile(
                                context,
                                ref,
                                currentProfile,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(height: 1, color: Color(0xFFEDEDED)),
                            _StaticSection(
                              title:
                                  '\uC5C5\uB370\uC774\uD2B8\uD55C \uC720\uC800',
                              count: updatedProfiles.length,
                              child: _UpdatedUsersStrip(
                                users: updatedProfiles,
                                onUserTap: (user) =>
                                    _showUserProfile(context, ref, user),
                              ),
                            ),
                            if (profilesState.isLoading && groups == userGroups)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  '\uD504\uB85C\uD544\uC744 \uBD88\uB7EC\uC624\uB294 \uC911\uC785\uB2C8\uB2E4.',
                                  style: TextStyle(
                                    color: Color(0xFF767676),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            for (final group in groups)
                              _CollapsibleSection(
                                title: group.title,
                                count: group.users.length,
                                isExpanded: ref.watch(
                                  friendGroupExpansionProvider.select(
                                    (groups) => groups[group.title] ?? true,
                                  ),
                                ),
                                onToggle: () => ref
                                    .read(friendGroupExpansionProvider.notifier)
                                    .toggle(group.title),
                                child: _UserList(
                                  users: group.users,
                                  onUserTap: (user) =>
                                      _showUserProfile(context, ref, user),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _companyTitle(
    PersonProfile currentProfile,
    List<PersonProfile> allProfiles,
  ) {
    final ownCompany = currentProfile.companyName?.trim();
    if (ownCompany != null && ownCompany.isNotEmpty) {
      return ownCompany;
    }
    for (final profile in allProfiles) {
      final company = profile.companyName?.trim();
      if (company != null && company.isNotEmpty) {
        return company;
      }
    }
    return _defaultCompanyName;
  }

  List<PersonProfile> _filterProfiles(
    List<PersonProfile> profiles,
    String query,
  ) {
    if (query.isEmpty) {
      return profiles;
    }
    final normalized = query.toLowerCase();
    return [
      for (final profile in profiles)
        if (_profileSearchText(profile).contains(normalized)) profile,
    ];
  }

  String _profileSearchText(PersonProfile profile) {
    return [
      profile.name,
      profile.nickname,
      profile.email,
      profile.phoneNumber,
      profile.department,
      profile.position,
      profile.companyName,
    ].whereType<String>().join(' ').toLowerCase();
  }

  Future<void> _showEmployeeAddDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (!_isAdmin(ref)) {
      _showBlackToast(context, '\uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4');
      return;
    }
    if (Platform.isWindows) {
      await _showNativeEmployeeAddPopup(context, ref);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      builder: (_) => const _EmployeeAddDialog(),
    );
  }

  bool _isAdmin(WidgetRef ref) {
    final role = ref
        .read(authControllerProvider)
        .value
        ?.session
        ?.user
        .role
        .toUpperCase();
    return role == 'ADMIN';
  }

  Future<void> _showNativeEmployeeAddPopup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final emailResults = <String, PersonProfile>{};
    final contactResults = <String, PersonProfile>{};

    WindowControl.setEmployeePopupHandler((action, arguments) async {
      if (!context.mounted) {
        return;
      }
      final session = ref.read(authControllerProvider).value?.session;
      if (session == null || session.accessToken.isEmpty) {
        return;
      }
      if (action == 'closed') {
        return;
      }
      if (action == 'emailChanged') {
        final email = arguments['email'] as String? ?? '';
        await _searchEmployeeForPopup(
          context: context,
          ref: ref,
          accessToken: session.accessToken,
          scope: 'email',
          cacheKey: email.trim().toLowerCase(),
          cache: emailResults,
          email: email,
        );
      } else if (action == 'contactChanged') {
        final name = arguments['name'] as String? ?? '';
        final phone = arguments['phone'] as String? ?? '';
        await _searchEmployeeForPopup(
          context: context,
          ref: ref,
          accessToken: session.accessToken,
          scope: 'contact',
          cacheKey: '${name.trim()}|${phone.trim()}',
          cache: contactResults,
          name: name,
          phoneNumber: phone,
        );
      } else if (action == 'primaryEmail') {
        final email = (arguments['email'] as String? ?? '')
            .trim()
            .toLowerCase();
        await _handleEmployeePrimary(
          context,
          ref,
          session.accessToken,
          profile: emailResults[email],
          email: email,
        );
      } else if (action == 'primaryContact') {
        final name = arguments['name'] as String? ?? '';
        final phone = arguments['phone'] as String? ?? '';
        await _handleEmployeePrimary(
          context,
          ref,
          session.accessToken,
          profile: contactResults['${name.trim()}|${phone.trim()}'],
          name: name,
          phoneNumber: phone,
        );
      } else if (action == 'blockEmail' || action == 'unblockEmail') {
        final email = (arguments['email'] as String? ?? '')
            .trim()
            .toLowerCase();
        final profile = emailResults[email];
        if (profile == null) {
          return;
        }
        try {
          final updated = action == 'blockEmail'
              ? await ref
                    .read(chatApiProvider)
                    .blockCompanyEmployee(
                      accessToken: session.accessToken,
                      targetUserId: profile.id,
                      email: profile.email,
                    )
              : await ref
                    .read(chatApiProvider)
                    .unblockCompanyEmployee(
                      accessToken: session.accessToken,
                      targetUserId: profile.id,
                      email: profile.email,
                    );
          final updatedProfile = personProfileFromDto(updated);
          emailResults[email] = updatedProfile;
          ref.invalidate(userProfilesProvider);
          await _updateNativeEmployeeResult(ref, 'email', updatedProfile);
        } on Object catch (error) {
          if (context.mounted) {
            _showBlackToast(context, authErrorMessage(error));
          }
        }
      }
    });

    await WindowControl.showEmployeeAddPopup();
  }

  Future<void> _searchEmployeeForPopup({
    required BuildContext context,
    required WidgetRef ref,
    required String accessToken,
    required String scope,
    required String cacheKey,
    required Map<String, PersonProfile> cache,
    String? name,
    String? phoneNumber,
    String? email,
  }) async {
    if (cacheKey.trim().isEmpty ||
        (email != null && !email.contains('@')) ||
        (name != null && name.trim().isEmpty) ||
        (phoneNumber != null && phoneNumber.trim().isEmpty)) {
      cache.remove(cacheKey);
      await WindowControl.updateEmployeeAddPopup(
        scope: scope,
        hasResult: false,
      );
      return;
    }
    try {
      final results = await ref
          .read(chatApiProvider)
          .searchEmployees(
            accessToken: accessToken,
            name: name,
            phoneNumber: phoneNumber,
            email: email,
          );
      if (results.isEmpty) {
        cache.remove(cacheKey);
        await WindowControl.updateEmployeeAddPopup(
          scope: scope,
          hasResult: false,
        );
        return;
      }
      final profile = personProfileFromDto(results.first);
      cache[cacheKey] = profile;
      await _updateNativeEmployeeResult(ref, scope, profile);
    } on Object catch (error) {
      if (context.mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _updateNativeEmployeeResult(
    WidgetRef ref,
    String scope,
    PersonProfile profile,
  ) async {
    await WindowControl.updateEmployeeAddPopup(
      scope: scope,
      hasResult: true,
      id: profile.id,
      email: profile.email,
      name: profile.name,
      nickname: profile.nickname ?? profile.name,
      avatarColor: colorToHex(profile.color),
      avatarImageUrl: profile.imageUrl,
      isAlreadyAdded: _isAlreadyCompanyEmployee(ref, profile),
      blocked: profile.blocked,
    );
  }

  bool _isAlreadyCompanyEmployee(WidgetRef ref, PersonProfile profile) {
    if (profile.blocked) {
      return false;
    }
    final users = ref.read(userProfilesProvider).value ?? const [];
    return users.any((user) => _isSameUser(user, profile));
  }

  Future<void> _handleEmployeePrimary(
    BuildContext context,
    WidgetRef ref,
    String accessToken, {
    PersonProfile? profile,
    String? email,
    String? name,
    String? phoneNumber,
  }) async {
    if (profile != null && _isAlreadyCompanyEmployee(ref, profile)) {
      await WindowControl.closeEmployeeAddPopup();
      final session = ref.read(authControllerProvider).value?.session;
      if (_isCurrentUser(session?.user.id, session?.user.email, profile)) {
        _openSelfChat(ref, ref.read(currentUserProfileProvider));
      } else {
        await _openDirectChat(ref, profile);
      }
      return;
    }
    try {
      await ref
          .read(chatApiProvider)
          .addCompanyEmployee(
            accessToken: accessToken,
            targetUserId: profile?.id,
            email: profile?.email ?? email,
            name: name,
            phoneNumber: phoneNumber,
          );
      ref.invalidate(userProfilesProvider);
      await WindowControl.closeEmployeeAddPopup();
      if (context.mounted) {
        _showBlackToast(
          context,
          '\uC9C1\uC6D0\uC774 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    }
  }

  Future<void> _showSelfProfile(
    BuildContext context,
    WidgetRef ref,
    PersonProfile profile,
  ) async {
    if (!Platform.isWindows) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.18),
        builder: (dialogContext) => _SelfProfileDialog(
          profile: profile,
          onOpenSelfChat: () {
            Navigator.of(dialogContext).pop();
            _openSelfChat(ref, ref.read(currentUserProfileProvider));
          },
          onEdit: () {
            Navigator.of(dialogContext).pop();
            _showProfileEdit(
              context,
              ref,
              ref.read(currentUserProfileProvider),
            );
          },
        ),
      );
      return;
    }

    WindowControl.setProfilePopupHandler((action, arguments) async {
      if (!context.mounted) {
        return;
      }
      if (action == 'selfChat') {
        _openSelfChat(ref, ref.read(currentUserProfileProvider));
      } else if (action == 'editProfile') {
        await _showProfileEdit(
          context,
          ref,
          ref.read(currentUserProfileProvider),
        );
      } else if (action == 'backgroundChanged') {
        await _updateProfileBackground(context, ref, arguments);
      }
    });
    await WindowControl.showProfilePopup(
      isSelf: true,
      id: profile.id ?? '',
      email: profile.email ?? '',
      name: profile.name,
      nickname: profile.nickname ?? profile.name,
      statusMessage: profile.statusMessage ?? '',
      avatarImageUrl: profile.imageUrl ?? '',
      avatarColor: colorToHex(profile.color),
      backgroundColor: colorToHex(
        profile.profileBackgroundColor ?? profile.color,
      ),
      backgroundImageUrl: profile.profileBackgroundImageUrl ?? '',
    );
  }

  Future<void> _showUserProfile(
    BuildContext context,
    WidgetRef ref,
    PersonProfile user,
  ) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (_isCurrentUser(session?.user.id, session?.user.email, user)) {
      return _showSelfProfile(
        context,
        ref,
        ref.read(currentUserProfileProvider),
      );
    }

    if (!Platform.isWindows) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.18),
        builder: (dialogContext) => _OtherProfileDialog(
          profile: user,
          onDirectChat: () {
            Navigator.of(dialogContext).pop();
            _openDirectChat(ref, user);
          },
        ),
      );
      return;
    }

    WindowControl.setProfilePopupHandler((action, arguments) async {
      if (action == 'directChat') {
        await _openDirectChat(ref, user);
      }
    });
    await WindowControl.showProfilePopup(
      isSelf: false,
      id: user.id ?? '',
      email: user.email ?? '',
      name: user.name,
      nickname: user.nickname ?? user.name,
      statusMessage: user.statusMessage ?? '',
      avatarImageUrl: user.imageUrl ?? '',
      avatarColor: colorToHex(user.color),
      backgroundColor: colorToHex(user.profileBackgroundColor ?? user.color),
      backgroundImageUrl: user.profileBackgroundImageUrl ?? '',
    );
  }

  Future<void> _showProfileEdit(
    BuildContext context,
    WidgetRef ref,
    PersonProfile profile,
  ) async {
    if (!Platform.isWindows) {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.18),
        builder: (_) => _ProfileEditDialog(profile: profile),
      );
      return;
    }

    WindowControl.setProfilePopupHandler((action, arguments) async {
      if (action == 'profileEditSubmitted') {
        await _saveProfileEdit(context, ref, arguments);
      }
    });
    await WindowControl.showProfileEditPopup(
      id: profile.id ?? '',
      email: profile.email ?? '',
      name: profile.name,
      nickname: profile.nickname ?? profile.name,
      statusMessage: profile.statusMessage ?? '',
      avatarImageUrl: profile.imageUrl ?? '',
      avatarColor: colorToHex(profile.color),
    );
  }

  Future<void> _updateProfileBackground(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> arguments,
  ) async {
    final color = arguments['backgroundColor'] as String? ?? '';
    final imageUrl = arguments['backgroundImageUrl'] as String? ?? '';
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null ||
        session.accessToken.isEmpty ||
        (color.isEmpty && imageUrl.isEmpty)) {
      return;
    }
    try {
      await ref
          .read(chatApiProvider)
          .updateProfile(
            accessToken: session.accessToken,
            profileBackgroundColor: color.isEmpty ? null : color,
            profileBackgroundImageUrl: imageUrl.isEmpty ? null : imageUrl,
          );
      ref.invalidate(userProfilesProvider);
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    }
  }

  Future<void> _saveProfileEdit(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> arguments,
  ) async {
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    try {
      await ref
          .read(chatApiProvider)
          .updateProfile(
            accessToken: session.accessToken,
            nickname: arguments['nickname'] as String? ?? '',
            statusMessage: arguments['statusMessage'] as String? ?? '',
            avatarImageUrl: arguments['avatarImageUrl'] as String?,
          );
      ref.invalidate(userProfilesProvider);
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    }
  }

  void _openSelfChat(WidgetRef ref, PersonProfile profile) {
    final existingRoom = _existingSelfRoom(ref);
    final room = existingRoom ?? selfChatRoomFor(profile);

    if (ref.read(selectedChatRoomProvider) != null) {
      ref.read(selectedChatRoomProvider.notifier).open(room);
    } else {
      ref.read(selectedChatRoomProvider.notifier).open(room);
      WindowControl.expandMessenger();
    }
  }

  ChatRoom? _existingSelfRoom(WidgetRef ref) {
    for (final room in ref.read(chatRoomsProvider)) {
      if (room.isSelfChat && !room.isDraft && room.preview.trim().isNotEmpty) {
        return room;
      }
    }
    return null;
  }

  Future<void> _openDirectChat(WidgetRef ref, PersonProfile user) async {
    final existingRoom = _existingDirectRoom(ref, user);
    final room = existingRoom ?? directChatRoomFor(user);

    if (ref.read(selectedChatRoomProvider) != null) {
      ref.read(selectedChatRoomProvider.notifier).open(room);
    } else {
      ref.read(selectedChatRoomProvider.notifier).open(room);
      WindowControl.expandMessenger();
    }
  }

  ChatRoom? _existingDirectRoom(WidgetRef ref, PersonProfile user) {
    for (final room in ref.read(chatRoomsProvider)) {
      if (!room.isDirectChat) {
        continue;
      }
      if (!room.isDraft && room.displayParticipantCount < 2) {
        continue;
      }
      if (room.members.any((member) => _isSameUser(member, user))) {
        return room;
      }
      if (room.title == user.name && user.email == null && user.id == null) {
        return room;
      }
    }
    return null;
  }

  bool _isCurrentUser(
    String? currentUserId,
    String? currentEmail,
    PersonProfile user,
  ) {
    return (currentUserId != null &&
            currentUserId.isNotEmpty &&
            user.id == currentUserId) ||
        (currentEmail != null &&
            currentEmail.isNotEmpty &&
            user.email == currentEmail);
  }

  bool _isSameUser(PersonProfile first, PersonProfile second) {
    return (first.id != null && second.id != null && first.id == second.id) ||
        (first.email != null &&
            second.email != null &&
            first.email == second.email) ||
        (first.id == null &&
            second.id == null &&
            first.email == null &&
            second.email == null &&
            first.name == second.name);
  }
}

class _MyProfile extends StatelessWidget {
  const _MyProfile({required this.profile, required this.onAvatarTap});

  final PersonProfile profile;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname?.trim();
    final email = profile.email?.trim();
    final status = profile.status?.trim().isNotEmpty == true
        ? profile.status!.trim()
        : _online;

    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAvatarTap,
            child: ProfileAvatar(profile: profile, size: 56),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                      ),
                    ),
                  ),
                  if (nickname != null &&
                      nickname.isNotEmpty &&
                      nickname != profile.name) ...[
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (email != null && email.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 11,
                    height: 1.15,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              _PresenceLabel(status: status),
            ],
          ),
        ),
        _StatusMessageBubble(message: profile.statusMessage),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () {},
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Color(0xFFE3E3E3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text(_multiProfileLabel),
        ),
      ],
    );
  }
}

class _CompanySearchBar extends StatelessWidget {
  const _CompanySearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF7E7E7E)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, size: 18, color: Color(0xFF666666)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      decoration: const InputDecoration(
                        hintText: '\uC774\uB984 \uAC80\uC0C9',
                        hintStyle: TextStyle(
                          color: Color(0xFF8B8B8B),
                          fontSize: 13,
                          height: 1.1,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(bottom: 2),
                      ),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 18,
                    color: const Color(0xFFD7D7D7),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '\uD1B5\uD569\uAC80\uC0C9',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 13),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox.square(
            dimension: 30,
            child: IconButton(
              onPressed: onClose,
              padding: EdgeInsets.zero,
              splashRadius: 15,
              icon: const Icon(Icons.close, size: 22, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultSection extends StatelessWidget {
  const _SearchResultSection({
    required this.count,
    required this.users,
    required this.onUserTap,
  });

  final int count;
  final List<PersonProfile> users;
  final ValueChanged<PersonProfile> onUserTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Text(
                '\uC9C1\uC6D0',
                style: TextStyle(
                  color: Color(0xFF8A8A8A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(color: Color(0xFF767676), fontSize: 12),
              ),
              const Spacer(),
              const Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: Color(0xFF969696),
              ),
            ],
          ),
        ),
        for (final user in users)
          _UserRow(
            key: ValueKey('search-user-${user.identityKey}'),
            user: user,
            onTap: () => onUserTap(user),
          ),
      ],
    );
  }
}

class _StaticSection extends StatelessWidget {
  const _StaticSection({
    required this.title,
    required this.count,
    required this.child,
  });

  final String title;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 13, bottom: 12),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF8A8A8A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(color: Color(0xFF767676), fontSize: 12),
              ),
            ],
          ),
        ),
        child,
        const Divider(height: 20, color: Color(0xFFEDEDED)),
      ],
    );
  }
}

class _CollapsibleSection extends StatelessWidget {
  const _CollapsibleSection({
    required this.title,
    required this.count,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final int count;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 13, bottom: 12),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: const TextStyle(
                      color: Color(0xFF767676),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: Color(0xFF969696),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded ? child : const SizedBox(width: double.infinity),
          ),
        ),
        const Divider(height: 20, color: Color(0xFFEDEDED)),
      ],
    );
  }
}

class _UpdatedUsersStrip extends StatelessWidget {
  const _UpdatedUsersStrip({required this.users, required this.onUserTap});

  final List<PersonProfile> users;
  final ValueChanged<PersonProfile> onUserTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: users.length,
        separatorBuilder: (context, index) => const SizedBox(width: 15),
        itemBuilder: (context, index) {
          final user = users[index];
          return _UpdatedUserChip(
            key: ValueKey('updated-user-${user.identityKey}'),
            user: user,
            onTap: () => onUserTap(user),
          );
        },
      ),
    );
  }
}

class _UpdatedUserChip extends StatelessWidget {
  const _UpdatedUserChip({required this.user, required this.onTap, super.key});

  final PersonProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          child: Column(
            children: [
              ProfileAvatar(profile: user, size: 42, showOnlineDot: true),
              const SizedBox(height: 6),
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.users, required this.onUserTap});

  final List<PersonProfile> users;
  final ValueChanged<PersonProfile> onUserTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final user in users)
          _UserRow(
            key: ValueKey('user-row-${user.identityKey}'),
            user: user,
            onTap: () => onUserTap(user),
          ),
      ],
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({required this.user, required this.onTap, super.key});

  final PersonProfile user;
  final VoidCallback onTap;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final presence = widget.user.status ?? _online;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered ? const Color(0xFFEFEFEF) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              ProfileAvatar(profile: widget.user, size: 42),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.user.email?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.user.email!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    _PresenceLabel(status: presence),
                  ],
                ),
              ),
              _StatusMessageBubble(message: widget.user.statusMessage),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusMessageBubble extends StatelessWidget {
  const _StatusMessageBubble({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          border: Border.all(color: const Color(0xFFE2E2E2)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4A4A4A),
              fontSize: 11,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresenceLabel extends StatelessWidget {
  const _PresenceLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: _presenceColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
          ),
        ),
      ],
    );
  }

  Color get _presenceColor {
    if (status == _online) {
      return const Color(0xFF2CBF6D);
    }
    if (status == _background) {
      return const Color(0xFFF2C94C);
    }
    if (status == _offline) {
      return const Color(0xFFB8B8B8);
    }
    return const Color(0xFF2CBF6D);
  }
}

class _EmployeeAddDialog extends ConsumerStatefulWidget {
  const _EmployeeAddDialog();

  @override
  ConsumerState<_EmployeeAddDialog> createState() => _EmployeeAddDialogState();
}

class _EmployeeAddDialogState extends ConsumerState<_EmployeeAddDialog> {
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _countryCodeController = TextEditingController(
    text: '+82',
  );
  int _tabIndex = 0;
  bool _isBusy = false;
  PersonProfile? _emailResult;

  @override
  void initState() {
    super.initState();
    _contactNameController.addListener(_refresh);
    _phoneController.addListener(_refresh);
    _emailController.addListener(_refresh);
  }

  @override
  void dispose() {
    _contactNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _countryCodeController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _isAdmin {
    final role = ref
        .read(authControllerProvider)
        .value
        ?.session
        ?.user
        .role
        .toUpperCase();
    return role == 'ADMIN';
  }

  bool get _canSubmitContact {
    return _contactNameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        !_isBusy;
  }

  bool get _canSubmitEmail => _emailResult != null && !_isBusy;

  String get _contactPhoneNumber {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.startsWith('+')) {
      return phone;
    }
    final country = _countryCodeController.text.trim().isEmpty
        ? '+82'
        : _countryCodeController.text.trim();
    return '$country $phone';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: Colors.white,
          elevation: 14,
          child: SizedBox(
            width: 300,
            height: 452,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 38),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '\uC9C1\uC6D0 \uCD94\uAC00',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _EmployeeTabs(
                          index: _tabIndex,
                          onChanged: (index) => setState(() {
                            _tabIndex = index;
                            _emailResult = null;
                          }),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE3E3E3)),
                      Expanded(
                        child: _tabIndex == 0
                            ? _buildContactTab()
                            : _buildEmailTab(),
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  top: 7,
                  right: 7,
                  child: _DialogCloseButton(color: Color(0xFF8C8C8C)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactTab() {
    final nameLength = _contactNameController.text.characters.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EmployeeUnderlineField(
            controller: _contactNameController,
            hintText: '\uC9C1\uC6D0 \uC774\uB984',
            maxLength: 20,
            currentLength: nameLength,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountryCodeField(controller: _countryCodeController),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [_KoreanPhoneNumberFormatter()],
                  decoration: const InputDecoration(
                    hintText: '\uC804\uD654\uBC88\uD638',
                    hintStyle: TextStyle(color: Color(0xFF8A8A8A)),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFE1E1E1)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black),
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.only(bottom: 8),
                  ),
                  style: const TextStyle(fontSize: 13, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '\uC9C1\uC6D0\uC758 \uC774\uB984\uACFC \uC804\uD654\uBC88\uD638\uB97C \uC785\uB825\uD574\uC8FC\uC138\uC694.',
            style: TextStyle(color: Color(0xFF7B7B7B), fontSize: 12),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: _EmployeeButton(
              label: '\uC9C1\uC6D0 \uCD94\uAC00',
              enabled: _canSubmitContact,
              primary: true,
              onTap: _addByContact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailTab() {
    final text = _emailController.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 16),
      child: Column(
        children: [
          _EmployeeUnderlineField(
            controller: _emailController,
            hintText: '\uC9C1\uC6D0 AVA ID',
            maxLength: 80,
            currentLength: text.characters.length,
            onSubmitted: (_) => _searchByEmail(),
            trailing: text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _emailController.clear();
                      setState(() => _emailResult = null);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    icon: const Icon(
                      Icons.cancel,
                      size: 16,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'AVA \uC774\uBA54\uC77C\uB85C \uC9C1\uC6D0\uC744 \uCC3E\uC744\uC218 \uC788\uC2B5\uB2C8\uB2E4.',
              style: TextStyle(color: Color(0xFF7B7B7B), fontSize: 12),
            ),
          ),
          const SizedBox(height: 34),
          if (_emailResult != null)
            _EmployeeSearchResult(profile: _emailResult!),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _EmployeeButton(
                label: '\uC9C1\uC6D0 \uCD94\uAC00',
                enabled: _canSubmitEmail,
                primary: true,
                onTap: _addEmailResult,
              ),
              const SizedBox(width: 8),
              _EmployeeButton(
                label: _emailResult?.blocked == true
                    ? '\uCC28\uB2E8 \uD574\uC81C'
                    : '\uCC28\uB2E8',
                enabled: _emailResult != null && !_isBusy,
                onTap: _toggleBlock,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _searchByEmail() async {
    final email = _emailController.text.trim();
    final session = ref.read(authControllerProvider).value?.session;
    if (email.isEmpty || session == null || session.accessToken.isEmpty) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      final results = await ref
          .read(chatApiProvider)
          .searchEmployees(accessToken: session.accessToken, email: email);
      if (!mounted) {
        return;
      }
      setState(() {
        _emailResult = results.isEmpty
            ? null
            : personProfileFromDto(results.first);
      });
      if (results.isEmpty) {
        _showBlackToast(
          context,
          '\uC9C1\uC6D0\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _addByContact() async {
    if (!_canSubmitContact) {
      return;
    }
    if (!_isAdmin) {
      _showBlackToast(context, '\uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4');
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      await ref
          .read(chatApiProvider)
          .addCompanyEmployee(
            accessToken: session.accessToken,
            name: _contactNameController.text,
            phoneNumber: _contactPhoneNumber,
          );
      ref.invalidate(userProfilesProvider);
      if (mounted) {
        _showBlackToast(
          context,
          '\uC9C1\uC6D0\uC774 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4',
        );
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _addEmailResult() async {
    final result = _emailResult;
    if (result == null || !_canSubmitEmail) {
      return;
    }
    if (!_isAdmin) {
      _showBlackToast(context, '\uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4');
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      await ref
          .read(chatApiProvider)
          .addCompanyEmployee(
            accessToken: session.accessToken,
            targetUserId: result.id,
            email: result.email,
          );
      ref.invalidate(userProfilesProvider);
      if (mounted) {
        _showBlackToast(
          context,
          '\uC9C1\uC6D0\uC774 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4',
        );
        Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _toggleBlock() async {
    final result = _emailResult;
    if (result == null || _isBusy) {
      return;
    }
    if (!_isAdmin) {
      _showBlackToast(context, '\uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4');
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      final updated = result.blocked
          ? await ref
                .read(chatApiProvider)
                .unblockCompanyEmployee(
                  accessToken: session.accessToken,
                  targetUserId: result.id,
                  email: result.email,
                )
          : await ref
                .read(chatApiProvider)
                .blockCompanyEmployee(
                  accessToken: session.accessToken,
                  targetUserId: result.id,
                  email: result.email,
                );
      ref.invalidate(userProfilesProvider);
      if (mounted) {
        setState(() => _emailResult = personProfileFromDto(updated));
      }
    } on Object catch (error) {
      if (mounted) {
        _showBlackToast(context, authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }
}

class _EmployeeTabs extends StatelessWidget {
  const _EmployeeTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EmployeeTab(
          label: '\uC5F0\uB77D\uCC98\uB85C \uCD94\uAC00',
          selected: index == 0,
          onTap: () => onChanged(0),
        ),
        const SizedBox(width: 20),
        _EmployeeTab(
          label: 'ID\uB85C \uCD94\uAC00',
          selected: index == 1,
          onTap: () => onChanged(1),
        ),
      ],
    );
  }
}

class _EmployeeTab extends StatelessWidget {
  const _EmployeeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Colors.black : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFF777777),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeUnderlineField extends StatelessWidget {
  const _EmployeeUnderlineField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    required this.currentLength,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int currentLength;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
              counterText: '',
              border: InputBorder.none,
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFE1E1E1)),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
            style: const TextStyle(color: Colors.black, fontSize: 13),
          ),
        ),
        ?trailing,
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text(
            '$currentLength/$maxLength',
            style: const TextStyle(color: Color(0xFF777777), fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _CountryCodeField extends StatelessWidget {
  const _CountryCodeField({required this.controller});

  final TextEditingController controller;

  static const _codes = [
    ('Afghanistan', '+93'),
    ('Albania', '+355'),
    ('Algeria', '+213'),
    ('American Samoa', '+1 684'),
    ('Andorra', '+376'),
    ('Angola', '+244'),
    ('Argentina', '+54'),
    ('Australia', '+61'),
    ('Brazil', '+55'),
    ('Canada', '+1'),
    ('China', '+86'),
    ('France', '+33'),
    ('Germany', '+49'),
    ('India', '+91'),
    ('Indonesia', '+62'),
    ('Japan', '+81'),
    ('Korea', '+82'),
    ('Singapore', '+65'),
    ('United Kingdom', '+44'),
    ('United States', '+1'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 61,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            tooltip: '',
            constraints: const BoxConstraints(maxHeight: 220, minWidth: 220),
            onSelected: (value) => controller.text = value,
            itemBuilder: (context) => [
              for (final item in _codes)
                PopupMenuItem(
                  value: item.$2,
                  height: 30,
                  child: Text(
                    '${item.$1} ${item.$2}',
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                ),
            ],
            child: Container(
              height: 36,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE1E1E1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value.text.isEmpty ? '+82' : value.text,
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Color(0xFF7A7A7A),
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

class _KoreanPhoneNumberFormatter extends TextInputFormatter {
  const _KoreanPhoneNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }
    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
    String formatted;
    if (limited.length == 11 && limited.startsWith('010')) {
      formatted =
          '${limited.substring(0, 3)}-${limited.substring(3, 7)}-${limited.substring(7)}';
    } else if (limited.length == 10 && limited.startsWith('010')) {
      formatted =
          '${limited.substring(0, 3)}-${limited.substring(3, 6)}-${limited.substring(6)}';
    } else if (limited.length > 7) {
      formatted =
          '${limited.substring(0, 3)}-${limited.substring(3, limited.length - 4)}-${limited.substring(limited.length - 4)}';
    } else if (limited.length > 3) {
      formatted = '${limited.substring(0, 3)}-${limited.substring(3)}';
    } else {
      formatted = limited;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _EmployeeSearchResult extends StatelessWidget {
  const _EmployeeSearchResult({required this.profile});

  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ProfileAvatar(profile: profile, size: 72),
        const SizedBox(height: 12),
        Text(
          profile.nickname?.isNotEmpty == true
              ? profile.nickname!
              : profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black, fontSize: 13),
        ),
      ],
    );
  }
}

class _EmployeeButton extends StatelessWidget {
  const _EmployeeButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 37,
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
          backgroundColor: !enabled
              ? const Color(0xFFF0F0F0)
              : primary
              ? const Color(0xFFFFDF00)
              : Colors.white,
          foregroundColor: enabled ? Colors.black : const Color(0xFFBEBEBE),
          disabledForegroundColor: const Color(0xFF777777),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
            side: BorderSide(
              color: primary && enabled
                  ? Colors.transparent
                  : const Color(0xFFE1E1E1),
            ),
          ),
          textStyle: const TextStyle(fontSize: 13),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SelfProfileDialog extends ConsumerStatefulWidget {
  const _SelfProfileDialog({
    required this.profile,
    required this.onOpenSelfChat,
    required this.onEdit,
  });

  final PersonProfile profile;
  final VoidCallback onOpenSelfChat;
  final VoidCallback onEdit;

  @override
  ConsumerState<_SelfProfileDialog> createState() => _SelfProfileDialogState();
}

class _SelfProfileDialogState extends ConsumerState<_SelfProfileDialog> {
  late Color _backgroundColor;
  String? _backgroundImageUrl;
  bool _isSavingBackground = false;

  @override
  void initState() {
    super.initState();
    _backgroundColor =
        widget.profile.profileBackgroundColor ?? widget.profile.color;
    _backgroundImageUrl = widget.profile.profileBackgroundImageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider);
    final effectiveProfile = _profileWith(
      profile,
      profileBackgroundColor: _backgroundColor,
      profileBackgroundImageUrl: _backgroundImageUrl,
    );

    return _ProfileDialogSurface(
      profile: effectiveProfile,
      canChangeBackground: true,
      onBackgroundTap: _changeBackground,
      isSavingBackground: _isSavingBackground,
      bottom: _ProfileActionBar(
        actions: [
          _ProfileAction(
            icon: Icons.chat_bubble,
            label: _selfChatLabel,
            onTap: widget.onOpenSelfChat,
          ),
          _ProfileAction(
            icon: Icons.edit,
            label: _profileEditLabel,
            onTap: widget.onEdit,
          ),
        ],
      ),
    );
  }

  Future<void> _changeBackground() async {
    final pickedPath = await _pickImagePath(context);
    if (pickedPath == null || pickedPath.isEmpty) {
      return;
    }
    final file = File(pickedPath);
    final bytes = await file.readAsBytes();
    if (bytes.length > 1_000_000) {
      if (!mounted) {
        return;
      }
      showAvaToast(
        context,
        '\uBC30\uACBD \uC774\uBBF8\uC9C0\uB294 1MB \uC774\uD558\uB85C \uC120\uD0DD\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }
    final extension = pickedPath.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    final imageUrl = 'data:$mime;base64,${base64Encode(bytes)}';

    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }

    setState(() {
      _isSavingBackground = true;
      _backgroundImageUrl = imageUrl;
    });
    try {
      await ref
          .read(chatApiProvider)
          .updateProfile(
            accessToken: session.accessToken,
            profileBackgroundImageUrl: imageUrl,
          );
      ref.invalidate(userProfilesProvider);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingBackground = false;
        });
      }
    }
  }
}

class _OtherProfileDialog extends StatelessWidget {
  const _OtherProfileDialog({
    required this.profile,
    required this.onDirectChat,
  });

  final PersonProfile profile;
  final VoidCallback onDirectChat;

  @override
  Widget build(BuildContext context) {
    return _ProfileDialogSurface(
      profile: profile,
      bottom: _ProfileActionBar(
        actions: [
          _ProfileAction(
            icon: Icons.chat_bubble,
            label: _directChatLabel,
            onTap: onDirectChat,
          ),
          _ProfileAction(icon: Icons.call, label: '\uD1B5\uD654', onTap: () {}),
        ],
      ),
    );
  }
}

class _ProfileDialogSurface extends StatelessWidget {
  const _ProfileDialogSurface({
    required this.profile,
    required this.bottom,
    this.canChangeBackground = false,
    this.onBackgroundTap,
    this.isSavingBackground = false,
  });

  final PersonProfile profile;
  final Widget bottom;
  final bool canChangeBackground;
  final VoidCallback? onBackgroundTap;
  final bool isSavingBackground;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = profile.profileBackgroundColor ?? profile.color;
    final backgroundImage = _imageProvider(profile.profileBackgroundImageUrl);
    final statusMessage = profile.statusMessage?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        child: SizedBox(
          width: 338,
          height: 500,
          child: Stack(
            children: [
              Positioned.fill(
                child: MouseRegion(
                  cursor: canChangeBackground
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onBackgroundTap,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        image: backgroundImage == null
                            ? null
                            : DecorationImage(
                                image: backgroundImage,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.26),
                          Colors.black.withValues(alpha: 0.70),
                        ],
                        stops: const [0, 0.58, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _DialogCloseButton(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              if (canChangeBackground)
                Positioned(
                  top: 14,
                  left: 16,
                  child: _ProfileTopIcon(
                    icon: isSavingBackground
                        ? Icons.hourglass_empty
                        : Icons.image_outlined,
                  ),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 86,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileAvatar(profile: profile, size: 72),
                    const SizedBox(height: 14),
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                    if (statusMessage != null && statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(left: 22, right: 22, bottom: 34, child: bottom),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTopIcon extends StatelessWidget {
  const _ProfileTopIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 31,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }
}

class _ProfileActionBar extends StatelessWidget {
  const _ProfileActionBar({required this.actions});

  final List<_ProfileAction> actions;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                Expanded(child: actions[index]),
                if (index != actions.length - 1)
                  Container(
                    width: 1,
                    height: 22,
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAction extends StatefulWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ProfileAction> createState() => _ProfileActionState();
}

class _ProfileActionState extends State<_ProfileAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ColoredBox(
          color: _isHovered
              ? Colors.white.withValues(alpha: 0.11)
              : Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 15),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileEditDialog extends ConsumerStatefulWidget {
  const _ProfileEditDialog({required this.profile});

  final PersonProfile profile;

  @override
  ConsumerState<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends ConsumerState<_ProfileEditDialog> {
  late final TextEditingController _nicknameController = TextEditingController(
    text: widget.profile.nickname ?? widget.profile.name,
  );
  late final TextEditingController _statusController = TextEditingController(
    text: widget.profile.statusMessage ?? '',
  );
  String? _avatarImageUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _avatarImageUrl = widget.profile.imageUrl;
    _nicknameController.addListener(_handleChanged);
    _statusController.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _handleChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final previewProfile = _profileWith(
      widget.profile,
      imageUrl: _avatarImageUrl,
    );
    final nicknameLength = _nicknameController.text.characters.length;
    final statusLength = _statusController.text.characters.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.white,
        elevation: 12,
        child: SizedBox(
          width: 338,
          height: 508,
          child: Stack(
            children: [
              const Positioned(
                top: 37,
                left: 18,
                child: Text(
                  '\uAE30\uBCF8\uD504\uB85C\uD544 \uD3B8\uC9D1',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              const Positioned(
                top: 8,
                right: 8,
                child: _DialogCloseButton(color: Color(0xFF8C8C8C)),
              ),
              Positioned(
                top: 92,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ProfileAvatar(profile: previewProfile, size: 102),
                        Positioned(
                          right: 0,
                          bottom: 4,
                          child: Container(
                            width: 27,
                            height: 27,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6A6A6A),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 22,
                top: 220,
                child: _ProfileEditField(
                  controller: _nicknameController,
                  hintText: '\uB2C9\uB124\uC784',
                  maxLength: 20,
                  currentLength: nicknameLength,
                ),
              ),
              Positioned(
                left: 18,
                right: 22,
                top: 264,
                child: _ProfileEditField(
                  controller: _statusController,
                  hintText: '\uC0C1\uD0DC\uBA54\uC2DC\uC9C0',
                  maxLength: 60,
                  currentLength: statusLength,
                ),
              ),
              Positioned(
                right: 22,
                bottom: 20,
                child: Row(
                  children: [
                    _EditDialogButton(
                      label: '\uD655\uC778',
                      enabled: !_isSaving,
                      onTap: _save,
                      filled: true,
                    ),
                    const SizedBox(width: 8),
                    _EditDialogButton(
                      label: '\uCDE8\uC18C',
                      enabled: !_isSaving,
                      onTap: () => Navigator.of(context).pop(),
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

  Future<void> _pickProfileImage() async {
    final pickedPath = await _pickImagePath(context);
    if (pickedPath == null || pickedPath.isEmpty) {
      return;
    }

    final file = File(pickedPath);
    final bytes = await file.readAsBytes();
    if (bytes.length > 1_000_000) {
      if (!mounted) {
        return;
      }
      showAvaToast(
        context,
        '\uD504\uB85C\uD544 \uC774\uBBF8\uC9C0\uB294 1MB \uC774\uD558\uB85C \uC120\uD0DD\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }

    final extension = pickedPath.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    setState(() {
      _avatarImageUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    });
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    final session = ref.read(authControllerProvider).value?.session;
    if (session == null || session.accessToken.isEmpty) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(chatApiProvider)
          .updateProfile(
            accessToken: session.accessToken,
            nickname: _nicknameController.text,
            statusMessage: _statusController.text,
            avatarImageUrl: _avatarImageUrl,
          );
      ref.invalidate(userProfilesProvider);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showAvaToast(context, authErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _ProfileEditField extends StatelessWidget {
  const _ProfileEditField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    required this.currentLength,
  });

  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int currentLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: maxLength,
                decoration: InputDecoration(
                  hintText: hintText,
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 8),
                ),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Text(
                '$currentLength/$maxLength',
                style: const TextStyle(
                  color: Color(0xFF777777),
                  fontSize: 12,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1, color: Color(0xFFD9D9D9)),
      ],
    );
  }
}

class _EditDialogButton extends StatelessWidget {
  const _EditDialogButton({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 37,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: filled ? const Color(0xFFF4F4F4) : Colors.white,
          foregroundColor: Colors.black,
          disabledForegroundColor: const Color(0xFFBEBEBE),
          side: BorderSide(
            color: filled ? const Color(0xFFF4F4F4) : const Color(0xFFDCDCDC),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        ),
        child: Text(label),
      ),
    );
  }
}

class _DialogCloseButton extends StatelessWidget {
  const _DialogCloseButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        padding: EdgeInsets.zero,
        splashRadius: 15,
        icon: Icon(Icons.close, size: 20, color: color),
      ),
    );
  }
}

void _showBlackToast(BuildContext context, String message) {
  showAvaToast(context, message);
}

PersonProfile _profileWith(
  PersonProfile profile, {
  String? imageUrl,
  Color? profileBackgroundColor,
  String? profileBackgroundImageUrl,
}) {
  return PersonProfile(
    id: profile.id,
    name: profile.name,
    nickname: profile.nickname,
    phoneNumber: profile.phoneNumber,
    email: profile.email,
    companyName: profile.companyName,
    position: profile.position,
    role: profile.role,
    department: profile.department,
    birthDate: profile.birthDate,
    imageUrl: imageUrl ?? profile.imageUrl,
    color: profile.color,
    status: profile.status,
    statusMessage: profile.statusMessage,
    profileBackgroundColor:
        profileBackgroundColor ?? profile.profileBackgroundColor,
    profileBackgroundImageUrl:
        profileBackgroundImageUrl ?? profile.profileBackgroundImageUrl,
    blocked: profile.blocked,
  );
}

ImageProvider? _imageProvider(String? imageUrl) {
  final value = imageUrl?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.startsWith('data:image/')) {
    final commaIndex = value.indexOf(',');
    if (commaIndex == -1) {
      return null;
    }
    try {
      return MemoryImage(base64Decode(value.substring(commaIndex + 1)));
    } on Object {
      return null;
    }
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return NetworkImage(value);
  }
  return null;
}

Future<String?> _pickImagePath(BuildContext context) async {
  if (!Platform.isWindows) {
    showAvaToast(
      context,
      '\uC774\uBBF8\uC9C0 \uC120\uD0DD\uC740 \uD604\uC7AC Windows \uB370\uC2A4\uD06C\uD1B1\uC5D0\uC11C \uC9C0\uC6D0\uB429\uB2C8\uB2E4.',
    );
    return null;
  }

  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "프로필 이미지 선택"
$dialog.Filter = "Images|*.jpg;*.jpeg;*.png;*.webp"
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::Write($dialog.FileName)
}
''';

  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    return result.stdout.toString().trim();
  } on Object {
    return null;
  }
}
