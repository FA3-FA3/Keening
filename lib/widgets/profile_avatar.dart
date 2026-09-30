import 'dart:convert';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.picture, this.radius = 18});
  final String? picture;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Widget content = Icon(Icons.person_outline, size: radius * 1.2);
    if (picture != null && picture!.startsWith('data:image/jpeg;base64,')) {
      try {
        content = Image.memory(
          base64Decode(picture!.split(',').last),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, error, stack) =>
              Icon(Icons.person_outline, size: radius * 1.2),
        );
      } on FormatException {
        // Keep the placeholder if profile data is invalid.
      }
    }
    return Semantics(
      label: 'Profile picture',
      image: true,
      child: CircleAvatar(
        radius: radius,
        child: ClipOval(child: content),
      ),
    );
  }
}
