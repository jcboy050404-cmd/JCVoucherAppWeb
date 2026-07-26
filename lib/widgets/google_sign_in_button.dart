import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern glassmorphic button for "Continue with Gmail" / Google Sign-In.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Continue with Gmail',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4285F4).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4285F4).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          splashColor: const Color(0xFF4285F4).withValues(alpha: 0.2),
          highlightColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF4285F4)),
                    ),
                  )
                else ...[
                  // Custom Google 'G' Icon widget
                  const _GoogleLogoWidget(size: 22),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for official Google multi-colored 'G' logo
class _GoogleLogoWidget extends StatelessWidget {
  final double size;
  const _GoogleLogoWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Blue segment
    paint.color = const Color(0xFF4285F4);
    final Path bluePath = Path()
      ..moveTo(w * 0.95, h * 0.5)
      ..cubicTo(w * 0.95, h * 0.45, w * 0.94, h * 0.39, w * 0.93, h * 0.34)
      ..lineTo(w * 0.5, h * 0.34)
      ..lineTo(w * 0.5, h * 0.55)
      ..lineTo(w * 0.76, h * 0.55)
      ..cubicTo(w * 0.74, h * 0.65, w * 0.68, h * 0.73, w * 0.59, h * 0.79)
      ..lineTo(w * 0.59, h * 0.94)
      ..lineTo(w * 0.76, h * 0.94)
      ..cubicTo(w * 0.86, h * 0.85, w * 0.95, h * 0.7, w * 0.95, h * 0.5);
    canvas.drawPath(bluePath, paint);

    // Green segment
    paint.color = const Color(0xFF34A853);
    final Path greenPath = Path()
      ..moveTo(w * 0.5, h * 0.95)
      ..cubicTo(w * 0.64, h * 0.95, w * 0.76, h * 0.9, w * 0.85, h * 0.82)
      ..lineTo(w * 0.68, h * 0.68)
      ..cubicTo(w * 0.63, h * 0.72, w * 0.57, h * 0.74, w * 0.5, h * 0.74)
      ..cubicTo(w * 0.36, h * 0.74, w * 0.25, h * 0.65, w * 0.21, h * 0.53)
      ..lineTo(w * 0.05, h * 0.53)
      ..lineTo(w * 0.05, h * 0.66)
      ..cubicTo(w * 0.14, h * 0.83, w * 0.31, h * 0.95, w * 0.5, h * 0.95);
    canvas.drawPath(greenPath, paint);

    // Yellow segment
    paint.color = const Color(0xFFFBBC05);
    final Path yellowPath = Path()
      ..moveTo(w * 0.21, h * 0.53)
      ..cubicTo(w * 0.19, h * 0.48, w * 0.18, h * 0.43, w * 0.18, h * 0.38)
      ..cubicTo(w * 0.18, h * 0.33, w * 0.19, h * 0.28, w * 0.21, h * 0.23)
      ..lineTo(w * 0.21, h * 0.09)
      ..lineTo(w * 0.05, h * 0.09)
      ..cubicTo(w * 0.02, h * 0.18, 0, h * 0.28, 0, h * 0.38)
      ..cubicTo(0, h * 0.48, w * 0.02, h * 0.58, w * 0.05, h * 0.67)
      ..lineTo(w * 0.21, h * 0.53);
    canvas.drawPath(yellowPath, paint);

    // Red segment
    paint.color = const Color(0xFFEA4335);
    final Path redPath = Path()
      ..moveTo(w * 0.5, h * 0.19)
      ..cubicTo(w * 0.58, h * 0.19, w * 0.65, h * 0.22, w * 0.71, h * 0.27)
      ..lineTo(w * 0.83, h * 0.15)
      ..cubicTo(w * 0.74, h * 0.07, w * 0.63, h * 0.03, w * 0.5, h * 0.03)
      ..cubicTo(w * 0.31, h * 0.03, w * 0.14, h * 0.15, w * 0.05, h * 0.32)
      ..lineTo(w * 0.21, h * 0.45)
      ..cubicTo(w * 0.25, h * 0.33, w * 0.36, h * 0.19, w * 0.5, h * 0.19);
    canvas.drawPath(redPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
