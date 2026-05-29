import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../platform/window_control.dart';
import '../../../shared/ava_dialog.dart';
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
  final _accountEmailController = TextEditingController();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _birthDayController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  String? _companyName;
  String? _birthMonth;
  String? _gender;
  bool _isSendingEmailCode = false;
  bool _emailCodeSent = false;
  bool _emailVerified = false;
  String? _emailVerificationEmail;
  String? _emailVerificationMessage;
  bool _emailVerificationSuccess = false;
  String? _companyError;
  String? _accountEmailError;
  String? _passwordError;
  String? _passwordConfirmError;
  String? _nameError;
  String? _nicknameError;
  String? _birthDateError;
  String? _genderError;
  String? _phoneError;
  String? _contactEmailError;
  String? _emailCodeError;

  @override
  void initState() {
    super.initState();
    _accountEmailController.addListener(_validateAccountEmailLive);
    _contactEmailController.addListener(_handleContactEmailChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowControl.setWindowTitle('AVA');
      WindowControl.showAuthWindow();
    });
  }

  @override
  void dispose() {
    _accountEmailController.removeListener(_validateAccountEmailLive);
    _contactEmailController.removeListener(_handleContactEmailChanged);
    _accountEmailController.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _birthYearController.dispose();
    _birthDayController.dispose();
    _contactEmailController.dispose();
    _emailCodeController.dispose();
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
    final emailCodeButtonBusy = isBusy || _isSendingEmailCode;

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 6),
                        Image.asset(
                          'assets/images/abba_ai_login_logo.png',
                          width: 188,
                          height: 54,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 18),
                        const _SignupLabel('회사'),
                        _CompanySelect(
                          value: _companyName,
                          errorText: _companyError,
                          onChanged: (value) => setState(() {
                            _companyName = value;
                            _companyError = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        const _SignupLabel('아이디'),
                        _SignupInput(
                          controller: _accountEmailController,
                          hintText: '이메일 형식으로 입력',
                          keyboardType: TextInputType.emailAddress,
                          errorText: _accountEmailError,
                        ),
                        const _SignupLabel('비밀번호'),
                        _SignupInput(
                          controller: _passwordController,
                          obscureText: true,
                          suffixIcon: Icons.lock_outline,
                          errorText: _passwordError,
                          onChanged: (_) =>
                              _clearError(() => _passwordError = null),
                        ),
                        const _SignupLabel('비밀번호 재확인'),
                        _SignupInput(
                          controller: _passwordConfirmController,
                          obscureText: true,
                          suffixIcon: Icons.lock_outline,
                          errorText: _passwordConfirmError,
                          onChanged: (_) =>
                              _clearError(() => _passwordConfirmError = null),
                        ),
                        const _SignupLabel('이름'),
                        _SignupInput(
                          controller: _nameController,
                          errorText: _nameError,
                          onChanged: (_) =>
                              _clearError(() => _nameError = null),
                        ),
                        const _SignupLabel('닉네임'),
                        _SignupInput(
                          controller: _nicknameController,
                          errorText: _nicknameError,
                          onChanged: (_) =>
                              _clearError(() => _nicknameError = null),
                        ),
                        const _SignupLabel('생년월일'),
                        Row(
                          children: [
                            Expanded(
                              child: _SignupInput(
                                controller: _birthYearController,
                                hintText: '년(4자)',
                                keyboardType: TextInputType.number,
                                bottomSpacing: 0,
                                onChanged: (_) =>
                                    _clearError(() => _birthDateError = null),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SignupSelect(
                                value: _birthMonth,
                                hintText: '월',
                                items: List.generate(
                                  12,
                                  (index) => '${index + 1}',
                                ),
                                onChanged: (value) => setState(() {
                                  _birthMonth = value;
                                  _birthDateError = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SignupInput(
                                controller: _birthDayController,
                                hintText: '일',
                                keyboardType: TextInputType.number,
                                bottomSpacing: 0,
                                onChanged: (_) =>
                                    _clearError(() => _birthDateError = null),
                              ),
                            ),
                          ],
                        ),
                        _InlineError(_birthDateError),
                        const SizedBox(height: 12),
                        const _SignupLabel('성별'),
                        _SignupSelect(
                          value: _gender,
                          hintText: '성별',
                          items: const ['남성', '여성', '선택 안 함'],
                          onChanged: (value) => setState(() {
                            _gender = value;
                            _genderError = null;
                          }),
                        ),
                        _InlineError(_genderError),
                        const SizedBox(height: 12),
                        const _SignupLabel('전화번호'),
                        _SignupInput(
                          controller: _phoneController,
                          hintText: '전화번호 입력',
                          keyboardType: TextInputType.phone,
                          inputFormatters: const [
                            _KoreanPhoneNumberFormatter(),
                          ],
                          errorText: _phoneError,
                          onChanged: (_) =>
                              _clearError(() => _phoneError = null),
                        ),
                        const _SignupLabel('이메일'),
                        _SignupInput(
                          controller: _contactEmailController,
                          hintText: '이메일 입력',
                          keyboardType: TextInputType.emailAddress,
                          errorText: _contactEmailError,
                          onChanged: (_) =>
                              _clearError(() => _contactEmailError = null),
                        ),
                        _VerificationMessage(
                          text: _emailVerificationMessage,
                          success: _emailVerificationSuccess,
                        ),
                        if (!_emailVerified) ...[
                          const _SignupLabel('이메일 인증번호 입력'),
                          Row(
                            children: [
                              Expanded(
                                child: _SignupInput(
                                  controller: _emailCodeController,
                                  hintText: '인증번호 입력',
                                  keyboardType: TextInputType.number,
                                  bottomSpacing: 0,
                                  errorText: _emailCodeError,
                                  onChanged: (_) =>
                                      _clearError(() => _emailCodeError = null),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 126,
                                height: 48,
                                child: FilledButton(
                                  onPressed: emailCodeButtonBusy
                                      ? null
                                      : (_emailCodeSent
                                            ? _confirmEmailCode
                                            : _requestEmailCode),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F1530),
                                    disabledBackgroundColor: Colors.white
                                        .withValues(alpha: 0.42),
                                    foregroundColor: Colors.white,
                                    shape: const RoundedRectangleBorder(),
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: Text(
                                    _emailCodeSent ? '인증 확인' : '인증번호 받기',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: isBusy ? null : _signup,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white.withValues(
                                alpha: 0.58,
                              ),
                              foregroundColor: const Color(0xFF4663CF),
                              shape: const RoundedRectangleBorder(),
                            ),
                            child: Text(
                              isBusy ? '가입 중...' : '가입하기',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: isBusy ? null : () => context.go('/'),
                          child: Text(
                            '로그인으로 돌아가기',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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
    final email = _accountEmailController.text.trim();
    final name = _nameController.text.trim();
    final nickname = _nicknameController.text.trim();
    final phone = _phoneController.text.trim();
    final contactEmail = _contactEmailController.text.trim();
    final emailVerificationCode = _emailCodeController.text.trim();
    final password = _passwordController.text;
    final confirm = _passwordConfirmController.text;
    final birthDate = _birthDate();

    setState(() {
      _companyError = _companyName == null ? '회사를 선택해주세요.' : null;
      _accountEmailError = email.isEmpty
          ? '아이디를 입력해주세요.'
          : (!_isEmail(email) ? '아이디는 이메일 형식으로 입력해주세요.' : null);
      _passwordError = password.isEmpty
          ? '비밀번호를 입력해주세요.'
          : (password.length < 8 ? '비밀번호는 8자 이상이어야 합니다.' : null);
      _passwordConfirmError = confirm.isEmpty
          ? '비밀번호 재확인을 입력해주세요.'
          : (password != confirm ? '비밀번호가 서로 다릅니다.' : null);
      _nameError = name.isEmpty ? '이름을 입력해주세요.' : null;
      _nicknameError = nickname.isEmpty ? '닉네임을 입력해주세요.' : null;
      _birthDateError = _birthDateErrorMessage(birthDate);
      _genderError = _gender == null ? '성별을 선택해주세요.' : null;
      _phoneError = phone.isEmpty ? '전화번호를 입력해주세요.' : null;
      _contactEmailError = contactEmail.isEmpty
          ? '이메일을 입력해주세요.'
          : (!_isEmail(contactEmail) ? '이메일 형식이 올바르지 않습니다.' : null);
      if (_emailVerified) {
        _emailCodeError = null;
      } else {
        _emailCodeError = emailVerificationCode.isEmpty
            ? '이메일 인증번호를 입력해주세요.'
            : null;
        if (_contactEmailError == null) {
          _emailVerificationSuccess = false;
          _emailVerificationMessage = '이메일 인증을 완료해주세요.';
        }
      }
    });

    if (_hasValidationError) {
      return;
    }

    final message = await ref
        .read(authControllerProvider.notifier)
        .signup(
          email: email,
          password: password,
          displayName: name,
          companyName: _companyName!,
          department: '미지정',
          emailVerificationCode: emailVerificationCode,
          nickname: nickname,
          phoneNumber: phone,
          contactEmail: contactEmail,
          gender: _gender,
          birthDate: birthDate,
        );
    if (!mounted) {
      return;
    }
    await _showSignupPendingDialog(message);
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _showSignupPendingDialog(String message) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AvaDialog(
          title: '가입 완료',
          subtitle: '관리자 승인 대기 상태입니다.',
          icon: const Icon(
            Icons.hourglass_top_rounded,
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
            message.isEmpty ? '관리자 승인 후 로그인 가능합니다.' : message,
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

  Future<void> _requestEmailCode() async {
    final email = _contactEmailController.text.trim();
    if (!_isEmail(email)) {
      setState(() {
        _contactEmailError = email.isEmpty
            ? '이메일을 먼저 입력해주세요.'
            : '이메일을 먼저 올바르게 입력해주세요.';
      });
      return;
    }
    setState(() => _isSendingEmailCode = true);
    try {
      await ref.read(authApiProvider).sendEmailVerificationCode(email);
      if (!mounted) {
        return;
      }
      setState(() {
        _contactEmailError = null;
        _emailCodeError = null;
        _emailCodeSent = true;
        _emailVerified = false;
        _emailVerificationEmail = email;
        _emailVerificationMessage = null;
        _emailVerificationSuccess = false;
      });
      _show('이메일 인증번호를 발송했습니다.');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _emailVerificationSuccess = false;
        _emailVerificationMessage = authErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() => _isSendingEmailCode = false);
      }
    }
  }

  Future<void> _confirmEmailCode() async {
    final email = _contactEmailController.text.trim();
    final code = _emailCodeController.text.trim();
    if (!_isEmail(email)) {
      setState(() {
        _contactEmailError = email.isEmpty
            ? '이메일을 먼저 입력해주세요.'
            : '이메일을 먼저 올바르게 입력해주세요.';
      });
      return;
    }
    if (code.isEmpty) {
      setState(() => _emailCodeError = '이메일 인증번호를 입력해주세요.');
      return;
    }
    setState(() => _isSendingEmailCode = true);
    try {
      await ref
          .read(authApiProvider)
          .confirmEmailVerificationCode(email: email, code: code);
      if (!mounted) {
        return;
      }
      setState(() {
        _contactEmailError = null;
        _emailCodeError = null;
        _emailCodeSent = true;
        _emailVerified = true;
        _emailVerificationEmail = email;
        _emailVerificationSuccess = true;
        _emailVerificationMessage = '인증이 완료되었습니다';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _emailVerificationSuccess = false;
        _emailVerificationMessage = authErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() => _isSendingEmailCode = false);
      }
    }
  }

  DateTime? _birthDate() {
    final year = int.tryParse(_birthYearController.text.trim());
    final month = int.tryParse(_birthMonth ?? '');
    final day = int.tryParse(_birthDayController.text.trim());
    if (year == null || month == null || day == null) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  bool _isEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool get _hasValidationError {
    return [
      _companyError,
      _accountEmailError,
      _passwordError,
      _passwordConfirmError,
      _nameError,
      _nicknameError,
      _birthDateError,
      _genderError,
      _phoneError,
      _contactEmailError,
      _emailCodeError,
    ].any((error) => error != null);
  }

  String? _birthDateErrorMessage(DateTime? birthDate) {
    final year = _birthYearController.text.trim();
    final day = _birthDayController.text.trim();
    if (year.isEmpty || _birthMonth == null || day.isEmpty) {
      return '생년월일을 입력해주세요.';
    }
    if (birthDate == null) {
      return '생년월일을 정확히 입력해주세요.';
    }
    return null;
  }

  void _validateAccountEmailLive() {
    final email = _accountEmailController.text.trim();
    final nextError = email.isNotEmpty && !_isEmail(email)
        ? '아이디는 이메일 형식으로 입력해주세요.'
        : null;
    if (_accountEmailError == nextError) {
      return;
    }
    setState(() => _accountEmailError = nextError);
  }

  void _handleContactEmailChanged() {
    final email = _contactEmailController.text.trim();
    final hasVerificationState =
        _emailCodeSent ||
        _emailVerified ||
        _emailVerificationEmail != null ||
        _emailVerificationMessage != null ||
        _emailCodeError != null ||
        _emailCodeController.text.isNotEmpty;
    if (!hasVerificationState || email == _emailVerificationEmail) {
      return;
    }
    setState(() {
      _emailCodeSent = false;
      _emailVerified = false;
      _emailVerificationEmail = null;
      _emailVerificationMessage = null;
      _emailVerificationSuccess = false;
      _emailCodeError = null;
      _emailCodeController.clear();
    });
  }

  void _clearError(VoidCallback clear) {
    setState(clear);
  }

  void _show(String message) {
    showAvaToast(context, message);
  }
}

class _SignupLabel extends StatelessWidget {
  const _SignupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.text);

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text!,
        style: const TextStyle(
          color: Color(0xFFFFD0D0),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}

class _VerificationMessage extends StatelessWidget {
  const _VerificationMessage({required this.text, required this.success});

  final String? text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Text(
        text!,
        style: TextStyle(
          color: success ? const Color(0xFF55F09C) : const Color(0xFFFFD0D0),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}

class _SignupInput extends StatelessWidget {
  const _SignupInput({
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.inputFormatters,
    this.obscureText = false,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
    this.bottomSpacing = 12,
  });

  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final IconData? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final enabledBorderColor = hasError
        ? const Color(0xFFFFD0D0)
        : const Color(0xFFE5E7EB);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            obscureText: obscureText,
            onChanged: onChanged,
            cursorColor: const Color(0xFF4663CF),
            style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              constraints: const BoxConstraints(minHeight: 48),
              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 14,
              ),
              suffixIcon: suffixIcon == null
                  ? null
                  : Icon(suffixIcon, size: 18, color: const Color(0xFF9CA3AF)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: enabledBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFFFD0D0)
                      : const Color(0xFF0F1530),
                ),
              ),
            ),
          ),
          _InlineError(errorText),
        ],
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
    final value = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = _format(value);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _format(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
  }
}

class _CompanySelect extends StatelessWidget {
  const _CompanySelect({
    required this.value,
    required this.errorText,
    required this.onChanged,
  });

  static const _items = ['ABBA-S', 'Cadillac'];

  final String? value;
  final String? errorText;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MenuAnchor(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(Colors.white),
                elevation: const WidgetStatePropertyAll(12),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shadowColor: WidgetStatePropertyAll(
                  Colors.black.withValues(alpha: 0.22),
                ),
                shape: const WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              menuChildren: [
                for (final item in _items)
                  SizedBox(
                    width: constraints.maxWidth,
                    height: 48,
                    child: MenuItemButton(
                      onPressed: () => onChanged(item),
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused) ||
                              states.contains(WidgetState.pressed)) {
                            return const Color(0xFFEAF0FF);
                          }
                          if (value == item) {
                            return const Color(0xFFF3F5FF);
                          }
                          return Colors.white;
                        }),
                        foregroundColor: WidgetStateProperty.resolveWith((
                          states,
                        ) {
                          if (states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused) ||
                              states.contains(WidgetState.pressed) ||
                              value == item) {
                            return const Color(0xFF4663CF);
                          }
                          return const Color(0xFF111827);
                        }),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 16),
                        ),
                        textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(item)),
                          if (value == item)
                            const Icon(Icons.check_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
              ],
              builder: (context, controller, child) {
                return _CompanySelectButton(
                  label: value ?? '회사 선택',
                  selected: value != null,
                  open: controller.isOpen,
                  hasError: errorText != null,
                  onTap: () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                );
              },
            ),
            _InlineError(errorText),
          ],
        );
      },
    );
  }
}

class _CompanySelectButton extends StatefulWidget {
  const _CompanySelectButton({
    required this.label,
    required this.selected,
    required this.open,
    required this.hasError,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool open;
  final bool hasError;
  final VoidCallback onTap;

  @override
  State<_CompanySelectButton> createState() => _CompanySelectButtonState();
}

class _CompanySelectButtonState extends State<_CompanySelectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || widget.open;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFF5F7FF) : Colors.white,
            border: Border.all(
              color: widget.hasError
                  ? const Color(0xFFFFD0D0)
                  : (active
                        ? const Color(0xFF4663CF)
                        : const Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.selected
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                    fontSize: 14,
                    fontWeight: widget.selected
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: widget.open ? 0.5 : 0,
                duration: const Duration(milliseconds: 120),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignupSelect extends StatelessWidget {
  const _SignupSelect({
    required this.value,
    required this.hintText,
    required this.items,
    required this.onChanged,
  });

  final String? value;
  final String hintText;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: Colors.white,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: Color(0xFF111827),
      ),
      hint: Text(
        hintText,
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),
      decoration: const InputDecoration(
        isDense: true,
        constraints: BoxConstraints(minHeight: 48),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Color(0xFF0F1530)),
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                item,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}
