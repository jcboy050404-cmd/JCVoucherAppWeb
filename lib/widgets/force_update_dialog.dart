import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows a mandatory, non-dismissible force-update dialog.
///
/// Behavior:
/// - `barrierDismissible: false` — tapping outside does nothing.
/// - Wrapped in `PopScope(canPop: false)` — the Android back button is blocked.
/// - No close / X button. The only action is "Update Now", which opens
///   [updateUrl] in the external browser via `url_launcher`.
///
/// The dialog reappears on every cold start / login (driven by
/// `ForceUpdateService.checkAndShowIfRequired`) until the installed version is
/// >= the admin-published `latest_version`.
Future<void> showForceUpdateDialog({
  required BuildContext context,
  required String latestVersion,
  required String installedVersion,
  required String updateUrl,
  String? message,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    useRootNavigator: true,
    builder: (ctx) => ForceUpdateDialog(
      latestVersion: latestVersion,
      installedVersion: installedVersion,
      updateUrl: updateUrl,
      message: message,
    ),
  );
}

class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({
    super.key,
    required this.latestVersion,
    required this.installedVersion,
    required this.updateUrl,
    this.message,
  });

  final String latestVersion;
  final String installedVersion;
  final String updateUrl;
  final String? message;

  Future<void> _openUpdateUrl() async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return;
    // Open in the external browser so the APK / store page loads outside the
    // app — the user installs the new build and relaunches.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // PopScope blocks the system back button. On older Flutter without
    // PopScope, the WillPopScope equivalent is `onWillPop: () async => false`.
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00BFFF).withValues(alpha: 0.5),
                    const Color(0xFF7B2FBE).withValues(alpha: 0.5),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF141428).withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Update Required',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message ??
                      'A new version of VoucherApp is available. Please update to continue using the app.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white60,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                // Version chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _VersionChip(
                      label: 'Your version',
                      value: installedVersion.isEmpty ? '—' : installedVersion,
                      color: Colors.white54,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 18,
                      ),
                    ),
                    _VersionChip(
                      label: 'Latest',
                      value: latestVersion,
                      color: const Color(0xFF00BFFF),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // The ONLY action — no close button.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openUpdateUrl,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ).copyWith(
                      backgroundColor:
                          WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Update Now',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'v$value',
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
