import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/ava_toast.dart';
import '../application/auth_controller.dart';
import '../data/auth_api.dart';
import 'widgets/auth_window_title_bar.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _departmentController = TextEditingController(text: '한국 개발부');
  final _birthDateController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    _birthDateController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
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
        showAvaToast(context, authErrorMessage(error));
      }
    });

    final isBusy = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1530), Color(0xFF7B61FF), Color(0xFF2F6BFF)],
          ),
        ),
        child: Column(
          children: [
            const AuthWindowTitleBar(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '회원가입',
                            style: TextStyle(
                              color: Color(0xFF0F1530),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'AVA 사내 메신저 계정을 생성합니다.',
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 22),
                          _SignupField(
                            controller: _emailController,
                            label: '이메일',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _SignupField(
                            controller: _nameController,
                            label: '이름',
                          ),
                          _SignupField(
                            controller: _nicknameController,
                            label: '닉네임',
                          ),
                          _SignupField(
                            controller: _phoneController,
                            label: '전화번호',
                            keyboardType: TextInputType.phone,
                          ),
                          _SignupField(
                            controller: _departmentController,
                            label: '부서',
                          ),
                          _SignupField(
                            controller: _birthDateController,
                            label: '생년월일 YYYY-MM-DD',
                            keyboardType: TextInputType.datetime,
                          ),
                          _SignupField(
                            controller: _passwordController,
                            label: '비밀번호',
                            obscureText: true,
                          ),
                          _SignupField(
                            controller: _passwordConfirmController,
                            label: '비밀번호 확인',
                            obscureText: true,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: isBusy ? null : _signup,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0F1530),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(isBusy ? '가입 중...' : '가입하기'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: isBusy ? null : () => context.go('/'),
                            child: const Text('로그인으로 돌아가기'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signup() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final phone = _phoneController.text.trim();
    final department = _departmentController.text.trim();
    final birthDateText = _birthDateController.text.trim();
    final password = _passwordController.text;
    final confirm = _passwordConfirmController.text;

    if (email.isEmpty ||
        name.isEmpty ||
        department.isEmpty ||
        password.isEmpty) {
      _show('모든 항목을 입력해주세요.');
      return;
    }
    if (password.length < 8) {
      _show('비밀번호는 8자 이상이어야 합니다.');
      return;
    }
    if (password != confirm) {
      _show('비밀번호가 서로 다릅니다.');
      return;
    }
    final birthDate = birthDateText.isEmpty
        ? null
        : DateTime.tryParse(birthDateText);
    if (birthDateText.isNotEmpty && birthDate == null) {
      _show('생년월일은 YYYY-MM-DD 형식으로 입력해주세요.');
      return;
    }

    await ref
        .read(authControllerProvider.notifier)
        .signup(
          email: email,
          password: password,
          displayName: name,
          department: department,
          nickname: nickname,
          phoneNumber: phone,
          birthDate: birthDate,
        );
  }

  void _show(String message) {
    showAvaToast(context, message);
  }
}

class _SignupField extends StatelessWidget {
  const _SignupField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        cursorColor: const Color(0xFF0F1530),
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF6B7280)),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFF2F6BFF)),
          ),
        ),
      ),
    );
  }
}
