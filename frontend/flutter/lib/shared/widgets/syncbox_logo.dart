import 'package:flutter/material.dart';

class SyncBoxLogo extends StatelessWidget {
  const SyncBoxLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/syncbox-icon.png',
    width: size,
    height: size,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}
