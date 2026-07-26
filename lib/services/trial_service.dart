import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'mikrotik_service.dart';
import 'cloud_sync_service.dart';

/// Manages per-Gmail trial mode and Pro unlock state.
///
/// Security & Business Rule:
/// - Each Gmail account gets 1 free voucher generation batch.
/// - PRO status is strictly tied to individual Gmail email addresses.
/// - Prevents unpaid accounts from accessing PRO via device-wide legacy keys.
///
/// Multi-Layer Security Architecture:
/// 1. Local Storage (SharedPreferences - fast offline access)
/// 2. Router Storage (MikroTik RouterOS script tag - hardware level)
/// 3. Cloud Storage (Firebase Database - global account recovery)
class TrialService {
  static const String _trialPrefix = 'trial_generated_';
  static const String _proPrefix = 'pro_unlocked_';
  static const String _legacyGlobalProKey = 'is_app_pro_unlocked';

  /// Helper to get current user's email if not provided
  static String getEmail([String? email]) {
    if (email != null && email.trim().isNotEmpty) {
      return email.trim().toLowerCase();
    }
    final current = AuthService.instance.currentUser;
    if (current != null && current.email.isNotEmpty) {
      return current.email.trim().toLowerCase();
    }
    return '';
  }

  /// Returns true ONLY if PRO is unlocked for this specific [email].
  static Future<bool> isPro([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();

    // Clean up legacy global key if it exists so old device flags never grant free PRO
    if (prefs.containsKey(_legacyGlobalProKey)) {
      await prefs.remove(_legacyGlobalProKey);
    }

    // 1. Check local per-user storage
    final localPro = prefs.getBool('$_proPrefix$userEmail') ?? false;
    if (localPro) return true;

    // 2. Check MikroTik Router for this specific email
    if (service != null && service.isConnected) {
      final routerPro = await service.checkRouterProFlag(userEmail);
      if (routerPro) {
        await prefs.setBool('$_proPrefix$userEmail', true);
        CloudSyncService.saveUserState(userEmail, pro: true);
        return true;
      }
    }

    // 3. Check Cloud Database for this specific email
    final cloudData = await CloudSyncService.getUserState(userEmail);
    if (cloudData['pro'] == true) {
      await prefs.setBool('$_proPrefix$userEmail', true);
      if (service != null && service.isConnected) {
        await service.setRouterProFlag(userEmail);
      }
      return true;
    }

    return false;
  }

  /// Unlocks Pro status specifically for [email] across Local, Router, and Cloud.
  static Future<void> unlockPro([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_proPrefix$userEmail', true);

    // Save to MikroTik Router
    if (service != null && service.isConnected) {
      await service.setRouterProFlag(userEmail);
    }

    // Save to Cloud DB
    await CloudSyncService.saveUserState(userEmail, pro: true);
  }

  /// Returns true if the user has already used their 1-time free trial voucher generation.
  static Future<bool> hasGenerated([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final localUsed = prefs.getBool('$_trialPrefix$userEmail') ?? false;
    if (localUsed) return true;

    // 2. Check MikroTik Router
    if (service != null && service.isConnected) {
      final routerUsed = await service.checkRouterTrialFlag(userEmail);
      if (routerUsed) {
        await prefs.setBool('$_trialPrefix$userEmail', true);
        CloudSyncService.saveUserState(userEmail, trialUsed: true);
        return true;
      }
    }

    // 3. Check Cloud Database
    final cloudData = await CloudSyncService.getUserState(userEmail);
    if (cloudData['trial_used'] == true) {
      await prefs.setBool('$_trialPrefix$userEmail', true);
      if (service != null && service.isConnected) {
        await service.setRouterTrialFlag(userEmail);
      }
      return true;
    }

    return false;
  }

  /// Returns true if the trial is finished and Pro is not yet purchased.
  static Future<bool> isTrialLocked([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return false;

    final pro = await isPro(userEmail, service);
    if (pro) return false;

    final used = await hasGenerated(userEmail, service);
    return used;
  }

  /// Call this immediately after a successful voucher generation batch.
  static Future<void> markGenerated([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_trialPrefix$userEmail', true);

    // Save to MikroTik Router
    if (service != null && service.isConnected) {
      await service.setRouterTrialFlag(userEmail);
    }

    // Save to Cloud DB
    await CloudSyncService.saveUserState(userEmail, trialUsed: true);
  }

  /// Resets trial state for [email] (for admin/debug use).
  static Future<void> reset([String? email]) async {
    final userEmail = getEmail(email);
    final prefs = await SharedPreferences.getInstance();
    if (userEmail.isNotEmpty) {
      await prefs.remove('$_trialPrefix$userEmail');
      await prefs.remove('$_proPrefix$userEmail');
    }
    await prefs.remove(_legacyGlobalProKey);
  }

  /// Completely resets ALL PRO statuses across Local SharedPreferences, MikroTik Router, and Cloud DB.
  static Future<void> resetAllPro([MikrotikService? service]) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();
    for (final key in keys) {
      if (key.startsWith(_proPrefix) || key == _legacyGlobalProKey) {
        await prefs.remove(key);
      }
    }
    if (service != null && service.isConnected) {
      await service.removeAllProFlags();
    }
    await CloudSyncService.resetAllProInCloud();
  }
}

