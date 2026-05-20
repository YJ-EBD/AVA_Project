import 'package:flutter/material.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    required this.title,
    required this.actions,
    this.titleFontWeight = FontWeight.w800,
    this.titleWidget,
    this.trailing,
    super.key,
  });

  final String title;
  final List<Widget> actions;
  final FontWeight titleFontWeight;
  final Widget? titleWidget;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 16, 8),
      child: Row(
        children: [
          titleWidget ??
              Text(
                title,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: titleFontWeight,
                  letterSpacing: 0,
                ),
              ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 24, color: Colors.black),
    );
  }
}
