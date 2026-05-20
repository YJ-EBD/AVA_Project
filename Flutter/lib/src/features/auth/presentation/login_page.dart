import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../platform/window_control.dart';
import '../../../shared/ava_dialog.dart';
import '../../../shared/ava_toast.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import 'widgets/auth_window_title_bar.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController(text: 'amos5105@naver.com');
  final _passwordController = TextEditingController();
  bool _autoLogin = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowControl.setWindowTitle('AVA');
      WindowControl.compactMessenger();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      if (next.value?.isAuthenticated == true && mounted) {
        context.go('/messenger');
      }
      final error = next.error;
      if (error != null && mounted) {
        if (isDuplicateLoginRequired(error) || isPendingApprovalRequired(error)) {
          return;
        }
        showAvaToast(context, authErrorMessage(error));
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.isLoading;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4663CF), Color(0xFF4E41A9)],
          ),
        ),
        child: Column(
          children: [
            const AuthWindowTitleBar(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 292),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _AvaSpeechLogo(),
                      const SizedBox(height: 34),
                      _LoginTextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        suffixIcon: Icons.arrow_drop_down,
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 1),
                      _LoginTextField(
                        controller: _passwordController,
                        obscureText: true,
                        hintText: '비밀번호',
                        onSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: FilledButton(
                          onPressed: isBusy ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white.withValues(
                              alpha: 0.55,
                            ),
                            foregroundColor: const Color(0xFF0F1530),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          child: Text(isBusy ? '로그인 중...' : '로그인'),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const _DividerLabel(text: '또는'),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: isBusy
                              ? null
                              : () => context.go('/signup'),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('회원가입'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F1530),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _autoLogin,
                              onChanged: isBusy
                                  ? null
                                  : (value) => setState(
                                      () => _autoLogin = value ?? false,
                                    ),
                              fillColor: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                              checkColor: const Color(0xFF0F1530),
                              side: const BorderSide(color: Colors.white),
                              shape: const CircleBorder(),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '자동 로그인',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: '토큰을 로컬 세션 파일에 저장해 다음 실행 때 로그인합니다.',
                            child: Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _BottomAuthLink(text: 'AVA계정 찾기', onTap: _findAccount),
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                  _BottomAuthLink(text: '비밀번호 재설정', onTap: _resetPassword),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login({bool forceLogin = false}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      showAvaToast(context, '이메일과 비밀번호를 입력해주세요.');
      return;
    }

    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            email: email,
            password: password,
            autoLogin: _autoLogin,
            forceLogin: forceLogin,
          );
    } on DuplicateLoginRequiredException {
      if (!mounted || forceLogin) {
        return;
      }
      final confirmed = await _showDuplicateLoginDialog();
      if (confirmed == true && mounted) {
        await _login(forceLogin: true);
      }
    } on PendingApprovalRequiredException catch (error) {
      if (!mounted) {
        return;
      }
      await _showPendingApprovalDialog(error.message);
    }
  }

  Future<void> _showPendingApprovalDialog(String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AvaDialog(
          title: '승인 대기',
          subtitle: '회사 관리자의 승인이 필요합니다.',
          icon: const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFF4F65C8),
            size: 24,
          ),
          actions: [
            AvaDialogButton(
              label: '확인',
              filled: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF102040),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showDuplicateLoginDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AvaDialog(
          title: '중복 로그인',
          subtitle: '다른 기기에서 이미 로그인 중입니다.',
          icon: const Icon(
            Icons.devices_other_rounded,
            color: Color(0xFF4F65C8),
            size: 24,
          ),
          actions: [
            AvaDialogButton(
              label: '취소',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AvaDialogButton(
              label: '로그인',
              filled: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
          child: const Text(
            '강제 로그아웃하고 현재 기기에서 로그인 하시겠습니까?',
            style: TextStyle(
              color: Color(0xFF102040),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }

  void _findAccount() {
    showAvaToast(context, 'AVA계정 찾기 API는 준비되어 있습니다.');
  }

  void _resetPassword() {
    showAvaToast(context, '비밀번호 재설정 화면은 다음 단계에서 연결하면 됩니다.');
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final IconData? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      cursorColor: const Color(0xFF0F1530),
      style: const TextStyle(color: Colors.black, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        suffixIcon: suffixIcon == null
            ? null
            : Icon(suffixIcon, color: const Color(0xFF7B7B7B), size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFF0F1530)),
        ),
      ),
    );
  }
}

class _AvaSpeechLogo extends StatelessWidget {
  const _AvaSpeechLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/abba_ai_login_logo.png',
          width: 292,
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1.2,
              fontWeight: FontWeight.w400,
            ),
            children: [
              TextSpan(text: '아바스 AI 업무 공간, '),
              TextSpan(
                text: '아톡',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: Colors.white24)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: Colors.white24)),
      ],
    );
  }
}

class _BottomAuthLink extends StatelessWidget {
  const _BottomAuthLink({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.84),
          fontSize: 12,
        ),
      ),
    );
  }
}
