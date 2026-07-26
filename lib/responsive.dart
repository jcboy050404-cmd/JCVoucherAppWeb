import 'package:flutter/material.dart';

/// Lightweight responsive helper shared across all screens.
///
/// Usage:
///   final r = Responsive(context);
///   r.isTablet
///   r.gridColumns()
///   Responsive.constrain(child)
class Responsive {
  Responsive(this.context)
      : size = MediaQuery.sizeOf(context),
        shortestSide = MediaQuery.sizeOf(context).shortestSide;

  final BuildContext context;
  final Size size;
  final double shortestSide;

  /// Max width used for centered content columns (lists, forms, modals).
  static const double contentMaxWidth = 720;

  /// Tablets/large displays start at 600dp shortest side (Material guidance).
  bool get isTablet => shortestSide >= 600;
  bool get isPhone => !isTablet;

  double get width => size.width;
  double get height => size.height;

  /// Computes a sensible column count for grids based on available width.
  /// [itemWidth] is the desired minimum width of one cell in dp.
  int gridColumns({double itemWidth = 360}) {
    final cols = (width / itemWidth).ceil();
    return cols.clamp(1, 4);
  }

  /// Wraps [child] in a centered, width-clamped column so it never stretches
  /// full-width on tablets. On phones this is effectively a no-op pass-through
  /// (width is below the cap), keeping the existing phone layout untouched.
  static Widget constrain(
    Widget child, {
    double maxWidth = contentMaxWidth,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
