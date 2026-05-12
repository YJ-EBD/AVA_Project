import 'package:flutter/material.dart';

import '../../../../platform/window_control.dart';

class AppWindowTitleBar extends StatelessWidget {
  const AppWindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E4))),
      ),
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
                      color: Colors.black,
                      fontSize: 12,
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
        ? const Color(0xFFEDEDED)
        : Colors.transparent;
    final foreground = widget.isClose && _isHovered
        ? Colors.white
        : Colors.black;

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
