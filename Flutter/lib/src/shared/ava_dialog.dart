import 'package:flutter/material.dart';

const _avaDialogInk = Color(0xFF102040);
const _avaDialogMuted = Color(0xFF5E7182);
const _avaDialogHeader = Color(0xFFD7E6F0);
const _avaDialogSurface = Color(0xFFF7FAFC);
const _avaDialogBorder = Color(0xFFAFC7D8);
const _avaDialogPrimary = Color(0xFF4F65C8);
const _avaDialogDanger = Color(0xFFE84D5B);
const _avaDialogAccent = Color(0xFFFFDF00);

class AvaDialog extends StatelessWidget {
  const AvaDialog({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.titleTrailing,
    this.actions = const [],
    this.width = 420,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? icon;
  final Widget? titleTrailing;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _avaDialogSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _avaDialogBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 26,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: _avaDialogHeader,
                  padding: const EdgeInsets.fromLTRB(24, 20, 22, 18),
                  child: Row(
                    children: [
                      icon ??
                          const Icon(
                            Icons.auto_awesome,
                            color: _avaDialogPrimary,
                            size: 24,
                          ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _avaDialogInk,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _avaDialogMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (titleTrailing != null) ...[
                        const SizedBox(width: 10),
                        titleTrailing!,
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: child,
                  ),
                ),
                if (actions.isNotEmpty)
                  Container(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _avaDialogBorder)),
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AvaDialogButton extends StatelessWidget {
  const AvaDialogButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.destructive = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _avaDialogDanger : _avaDialogPrimary;
    final foreground = filled ? Colors.white : color;
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(86, 40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return filled ? const Color(0xFFE1E8EF) : Colors.transparent;
          }
          if (filled) {
            return color;
          }
          if (states.contains(WidgetState.hovered)) {
            return _avaDialogHeader;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return _avaDialogMuted.withValues(alpha: 0.56);
          }
          return foreground;
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (filled) {
            return BorderSide.none;
          }
          return BorderSide(
            color: color.withValues(
              alpha: states.contains(WidgetState.disabled) ? 0.18 : 0.42,
            ),
          );
        }),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
      child: Text(label),
    );
  }
}

class AvaDialogNote extends StatelessWidget {
  const AvaDialogNote({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _avaDialogAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _avaDialogAccent.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.all(14),
      child: child,
    );
  }
}

Future<bool> showAvaConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '취소',
  String confirmLabel = '확인',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AvaDialog(
        title: title,
        icon: Icon(
          destructive ? Icons.delete_outline : Icons.help_outline,
          color: destructive ? _avaDialogDanger : _avaDialogPrimary,
          size: 24,
        ),
        actions: [
          AvaDialogButton(
            label: cancelLabel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AvaDialogButton(
            label: confirmLabel,
            filled: true,
            destructive: destructive,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        child: Text(
          message,
          style: const TextStyle(
            color: _avaDialogInk,
            fontSize: 14,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    },
  );
  return result ?? false;
}
