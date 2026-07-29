import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.desktop,
  });

  /// True if the screen width is >= 850 pixels
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 850;
  }

  /// True if the screen width is < 850 pixels
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 850;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 850) {
          return desktop;
        } else {
          return mobile;
        }
      },
    );
  }
}
