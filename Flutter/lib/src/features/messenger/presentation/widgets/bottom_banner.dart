import 'package:flutter/material.dart';

class BottomBanner extends StatelessWidget {
  const BottomBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFF101B3A),
        border: Border(top: BorderSide(color: Color(0xFFDADADA))),
      ),
      child: SizedBox(
        height: 104,
        width: double.infinity,
        child: Image(
          key: ValueKey('bottom-banner-image'),
          image: AssetImage('assets/images/ava_bottom_banner.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
