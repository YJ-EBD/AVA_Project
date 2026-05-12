import 'dart:async';

import 'package:flutter/material.dart';

const _avaToastWidth = 250.0;
const _avaToastHeight = 42.0;

void showAvaToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 1),
  Offset? globalCenter,
  double bottom = 210,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    return;
  }

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      final child = Center(
        child: IgnorePointer(child: _AvaToastBubble(message: message)),
      );

      if (globalCenter != null) {
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        final localCenter =
            overlayBox?.globalToLocal(globalCenter) ?? globalCenter;
        final maxTop =
            (overlayBox?.size.height ?? double.infinity) - _avaToastHeight;
        final upperTop = maxTop.isFinite && maxTop > 0 ? maxTop : 0.0;
        final top = (localCenter.dy - (_avaToastHeight / 2)).clamp(
          0.0,
          upperTop,
        );
        return Positioned(left: 0, right: 0, top: top, child: child);
      }

      return Positioned(left: 0, right: 0, bottom: bottom, child: child);
    },
  );

  overlay.insert(entry);
  Timer(duration, () {
    if (entry.mounted) {
      entry.remove();
    }
  });
}

class _AvaToastBubble extends StatelessWidget {
  const _AvaToastBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _avaToastWidth,
      height: _avaToastHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.74),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
