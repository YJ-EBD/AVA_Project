import 'package:flutter/material.dart';

import '../../../../platform/window_control.dart';

class AuthWindowTitleBar extends StatelessWidget {
  const AuthWindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => WindowControl.startDrag(),
              child: const Padding(
                padding: EdgeInsets.only(left: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'AVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _TitleButton(
            tooltip: '최소화',
            icon: Icons.remove,
            onPressed: WindowControl.minimize,
          ),
          _TitleButton(
            tooltip: '최대화',
            icon: Icons.crop_square,
            onPressed: WindowControl.toggleMaximize,
          ),
          _TitleButton(
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

class _TitleButton extends StatefulWidget {
  const _TitleButton({
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
  State<_TitleButton> createState() => _TitleButtonState();
}

class _TitleButtonState extends State<_TitleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isClose && _hovered
        ? const Color(0xFFE81123)
        : _hovered
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.transparent;
    final iconColor = widget.isClose && _hovered ? Colors.white : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 34,
            color: color,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}
