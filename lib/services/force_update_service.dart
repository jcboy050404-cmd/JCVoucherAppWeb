import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/force_update_dialog.dart';
import 'cloud_sync_service.dart';

/// Force Update service.
///
/// Reads and writes the `force_update` config that lives under the
/// `/settings` node in Firebase Realtime DB (same place as `pppoe_unlocked`),
/// and compares the installed app version against the admin-published
/// `latest_version`.
///
/// Data shape on the backend:
///   /settings/force_update = {
///     "enabled": true,            // optional, defaults to true if absent
///     "latest_version": "2.3.1",  // semver "major.minor.patch"
///     "update_url": "https://..." // opened by url_launcher on tap
///   }
///
/// The mandatory update dialog is shown only when:
///   - `enabled` is not explicitly false, AND
///   - `installed < latest_version` (strictly less than).
class ForceUpdateService {
  ForceUpdateService._();

  static bool _isShowingDialog = false;
  static bool _isChecking = false;

  /// Parsed force-update config. Null when the backend has no config yet.
  static Future<ForceUpdateConfig?> getConfig() async {
    final settings = await CloudSyncService.getGlobalSettings();
    final raw = settings['force_update'];
    if (raw is! Map) return null;
    return ForceUpdateConfig.fromMap(Map<String, dynamic>.from(raw));
  }

  /// Writes the force-update config under `/settings/force_update`.
  static Future<bool> saveConfig({
    required String latestVersion,
    required String updateUrl,
    bool enabled = true,
  }) async {
    return CloudSyncService.updateGlobalSettings({
      'force_update': {
        'enabled': enabled,
        'latest_version': latestVersion,
        'update_url': updateUrl,
      },
    });
  }

  /// Compares two dotted version strings.
  ///
  /// Returns a negative int if [a] < [b], zero if equal, positive if [a] > [b].
  /// Missing segments are treated as 0, so "2.3" compares equal to "2.3.0".
  /// Comparison is numeric per segment — "2.10.0" > "2.9.0".
  static int compareVersions(String a, String b) {
    final pa = a.split(RegExp(r'[.+]')).map(int.tryParse).toList();
    final pb = b.split(RegExp(r'[.+]')).map(int.tryParse).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? (pa[i] ?? 0) : 0;
      final vb = i < pb.length ? (pb[i] ?? 0) : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Returns the currently installed app version (e.g. "1.0.0+1").
  /// Includes the build suffix so we can safely compare versions like 1.0.0+2.
  static Future<String> getInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    String version = info.version.trim();
    if (info.buildNumber.isNotEmpty && !version.contains('+')) {
      version = '$version+${info.buildNumber.trim()}';
    }
    return version;
  }

  /// Runs the version check and, when an update is required, shows the
  /// mandatory non-dismissible dialog.
  ///
  /// Returns `true` when the blocking dialog is currently on screen (the
  /// caller should NOT navigate further), `false` otherwise.
  ///
  /// Failures (no config, network error, missing version) are non-blocking —
  /// we never lock users out of the app because of a transient backend issue.
  static Future<bool> checkAndShowIfRequired(BuildContext context) async {
    if (_isShowingDialog) return true;
    if (_isChecking) return false;

    _isChecking = true;
    try {
      final config = await getConfig();
      if (config == null) return false;
      if (!config.enabled) return false;
      if (config.latestVersion.isEmpty || config.updateUrl.isEmpty) return false;

      final installed = await getInstalledVersion();
      final needsUpdate = compareVersions(installed, config.latestVersion) < 0;
      if (!needsUpdate) return false;

      if (!context.mounted) return false;
      _isShowingDialog = true;
      await showForceUpdateDialog(
        context: context,
        latestVersion: config.latestVersion,
        installedVersion: installed,
        updateUrl: config.updateUrl,
        message: config.message,
      );
      return true;
    } finally {
      _isChecking = false;
    }
  }
}

/// Plain model for the `force_update` settings node.
class ForceUpdateConfig {
  const ForceUpdateConfig({
    required this.enabled,
    required this.latestVersion,
    required this.updateUrl,
    this.message,
  });

  factory ForceUpdateConfig.fromMap(Map<String, dynamic> map) {
    return ForceUpdateConfig(
      // Absent `enabled` is treated as enabled — setting `latest_version`
      // alone should be enough to activate the gate.
      enabled: map['enabled'] != false,
      latestVersion: (map['latest_version'] as String? ?? '').trim(),
      updateUrl: (map['update_url'] as String? ?? '').trim(),
      message: (map['message'] as String?)?.trim(),
    );
  }

  final bool enabled;
  final String latestVersion;
  final String updateUrl;
  final String? message;
}
