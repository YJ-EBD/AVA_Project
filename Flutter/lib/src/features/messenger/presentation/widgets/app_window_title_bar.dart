import 'package:flutter/material.dart';

import '../../../../platform/window_control.dart';

class AppWindowTitleBar extends StatelessWidget {
  const AppWindowTitleBar({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: Color(0xFF4F66C8),
        border: Border(bottom: BorderSide(color: Color(0xFF4058B8))),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowControl.startDrag(),
              child: Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _WindowButton(
            tooltip: '최소화',
            icon: Icons.remove,
            onPressed: WindowControl.minimize,
          ),
          _WindowButton(
            tooltip: '최대화',
            icon: Icons.crop_square,
            onPressed: WindowControl.toggleMaximize,
          ),
          _WindowButton(
            tooltip: '닫기',
            icon: Icons.close,
            onPressed: WindowControl.close,
            isClose: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool isClose;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.isClose && _isHovered
        ? const Color(0xFFE81123)
        : _isHovered
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.transparent;
    final foreground = Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 34,
            color: background,
            alignment: Alignment.center,
            child: Icon(widget.icon, color: foreground, size: 16),
          ),
        ),
      ),
    );
  }
}
