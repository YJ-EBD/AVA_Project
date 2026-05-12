import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/messenger_models.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.profile,
    this.size = 42,
    this.showOnlineDot = false,
    super.key,
  });

  final PersonProfile profile;
  final double size;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final imageUrl = profile.imageUrl?.trim();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: size,
            child: imageUrl == null || imageUrl.isEmpty
                ? _AvatarFallback(profile: profile, size: size)
                : _AvatarImage(
                    imageUrl: imageUrl,
                    fallback: _AvatarFallback(profile: profile, size: size),
                  ),
          ),
        ),
        if (showOnlineDot)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A32),
                border: Border.all(color: Colors.white, width: 1.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.imageUrl, required this.fallback});

  final String imageUrl;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.startsWith('data:image/')) {
      final commaIndex = imageUrl.indexOf(',');
      if (commaIndex > 0) {
        try {
          return Image.memory(
            base64Decode(imageUrl.substring(commaIndex + 1)),
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        } on FormatException {
          return fallback;
        }
      }
      return fallback;
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.profile, required this.size});

  final PersonProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: profile.color,
      child: Icon(
        Icons.person,
        color: Colors.white.withValues(alpha: 0.86),
        size: size * 0.56,
      ),
    );
  }
}
