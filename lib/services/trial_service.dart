import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  static const String _proExpiresPrefix = 'pro_expires_';
  static const String _legacyGlobalProKey = 'is_app_pro_unlocked';

  /// Per-session device-limit verdict: once a router is denied a slot on this
  /// device, PRO is withheld for the rest of the session (until reconnect).
  /// Null = not yet checked. Set on first [isPro] call with a live [MikrotikService].
  static bool? _deviceDeniedForSession;
  static String? _deviceDeniedEmail;

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
    if (localPro) {
      final expStr = prefs.getString('$_proExpiresPrefix$userEmail');
      if (expStr != null && expStr.isNotEmpty) {
        final expDate = DateTime.tryParse(expStr);
        if (expDate != null && DateTime.now().isAfter(expDate)) {
          await prefs.remove('$_proPrefix$userEmail');
          await prefs.remove('$_proExpiresPrefix$userEmail');
          await prefs.setBool('just_expired_$userEmail', true);
          if (service != null && service.isConnected) {
            await service.removeRouterProFlag(userEmail);
          }
          await CloudSyncService.saveUserState(userEmail, pro: false, proExpiresAt: '');
          return false;
        }
      }
      return _isDeviceAllowed(userEmail, service);
    }

    // 2. Check MikroTik Router for this specific email
    if (service != null && service.isConnected) {
      final routerPro = await service.checkRouterProFlag(userEmail);
      if (routerPro) {
        await prefs.setBool('$_proPrefix$userEmail', true);
        await CloudSyncService.saveUserState(userEmail, pro: true);
        return _isDeviceAllowed(userEmail, service);
      }
    }

    // 3. Check Cloud Database for this specific email
    final cloudData = await CloudSyncService.getUserState(userEmail);
    if (cloudData['pro'] == true) {
      final expStr = cloudData['pro_expires_at'] as String?;
      if (expStr != null && expStr.isNotEmpty) {
        final expDate = DateTime.tryParse(expStr);
        if (expDate != null && DateTime.now().isAfter(expDate)) {
          await prefs.remove('$_proPrefix$userEmail');
          await prefs.remove('$_proExpiresPrefix$userEmail');
          await prefs.setBool('just_expired_$userEmail', true);
          if (service != null && service.isConnected) {
            await service.removeRouterProFlag(userEmail);
          }
          await CloudSyncService.saveUserState(userEmail, pro: false, proExpiresAt: '');
          return false;
        }
        await prefs.setString('$_proExpiresPrefix$userEmail', expStr);
      } else {
        await prefs.remove('$_proExpiresPrefix$userEmail');
      }

      await prefs.setBool('$_proPrefix$userEmail', true);
      if (service != null && service.isConnected) {
        await service.setRouterProFlag(userEmail);
      }
      return _isDeviceAllowed(userEmail, service);
    }

    return false;
  }

  /// Enforces the 3-device limit. Called from [isPro] once the account is
  /// confirmed PRO, so the verdict applies everywhere PRO is checked — not
  /// just the dashboard. The result is cached per session+email so we don't
  /// hit the cloud on every [isPro] call.
  ///
  /// Returns true (PRO allowed) unless this router was explicitly DENIED a slot.
  /// Offline → fail-open (allowed).
  static Future<bool> _isDeviceAllowed(String email, MikrotikService? service) async {
    if (service == null || !service.isConnected) return true;

    // Reuse the cached verdict if it's for the same email (set on first call).
    if (_deviceDeniedEmail == email) {
      return _deviceDeniedForSession != true;
    }

    bool denied = false;
    try {
      final sysRes = await service.getResourceInfo();
      final serial = (sysRes['serial-number'] ?? '').trim();
      final board  = (sysRes['board-name'] ?? 'MikroTik Router').trim();
      final routerRawId = (serial.isNotEmpty && serial.toLowerCase() != 'n/a')
          ? serial
          : '${board}_${sysRes['platform'] ?? ''}_${sysRes['cpu'] ?? ''}';

      final result = await checkAndRegisterRouter(email, routerRawId, board);
      denied = result == DeviceSlotResult.denied;
    } catch (e) {
      debugPrint('TrialService: device-limit check failed, fail-open ($e)');
      denied = false;
    }

    _deviceDeniedForSession = denied;
    _deviceDeniedEmail = email;
    return !denied;
  }

  /// Returns whether the connected router was denied a PRO device slot this
  /// session (after [isPro] has run). Used by the dashboard to show the limit
  /// dialog only once, on the transition into denied.
  static bool get isCurrentDeviceDenied =>
      _deviceDeniedForSession == true;

  /// Clears the cached device verdict (e.g. on logout/disconnect), so the next
  /// login re-checks against the cloud.
  static void clearDeviceVerdict() {
    _deviceDeniedForSession = null;
    _deviceDeniedEmail = null;
  }

  /// Returns the Pro expiration date string if it exists, otherwise null
  static Future<String?> getProExpiration([String? email]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_proExpiresPrefix$userEmail');
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

  /// Syncs the local PRO status with the cloud database.
  /// This ensures that if an Admin revokes PRO from the cloud, the user's local device updates immediately.
  static Future<void> syncWithCloud([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return;

    final cloudData = await CloudSyncService.getUserState(userEmail);
    if (cloudData.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final cloudPro = cloudData['pro'] == true;

      if (cloudPro) {
        await prefs.setBool('$_proPrefix$userEmail', true);
        final expStr = cloudData['pro_expires_at'] as String?;
        if (expStr != null && expStr.isNotEmpty) {
          await prefs.setString('$_proExpiresPrefix$userEmail', expStr);
        } else {
          await prefs.remove('$_proExpiresPrefix$userEmail');
        }
        if (service != null && service.isConnected) {
          await service.setRouterProFlag(userEmail);
        }
      } else {
        // Cloud says NOT PRO. Revoke local AND router (regardless of local state),
        // so a stale router flag can't re-grant PRO on the next isPro() call.
        await prefs.remove('$_proPrefix$userEmail');
        await prefs.remove('$_proExpiresPrefix$userEmail');
        if (service != null && service.isConnected) {
          await service.removeRouterProFlag(userEmail);
        }
      }

      // Sync Trial flag
      final cloudTrialUsed = cloudData['trial_used'] == true;
      final localTrialUsed = prefs.getBool('$_trialPrefix$userEmail') ?? false;

      if (cloudTrialUsed && !localTrialUsed) {
        // Cloud says trial is used — propagate down to local and router
        await prefs.setBool('$_trialPrefix$userEmail', true);
        if (service != null && service.isConnected) {
          await service.setRouterTrialFlag(userEmail);
        }
      } else if (!cloudTrialUsed && localTrialUsed) {
        // Admin has reset the trial in the cloud, so clear it locally
        await prefs.remove('$_trialPrefix$userEmail');
        if (service != null && service.isConnected) {
          await service.removeRouterTrialFlag(userEmail);
        }
      }
    }
  }

  /// Resets the free trial for a specific [email] (admin utility).
  static Future<void> resetTrial([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_trialPrefix$userEmail');

    if (service != null && service.isConnected) {
      await service.removeRouterTrialFlag(userEmail);
    }

    await CloudSyncService.saveUserState(userEmail, trialUsed: false);
  }

  /// Returns true if the user has already used their 1-time free trial voucher generation.
  ///
  /// Cloud is the authoritative source. If cloud says trial is NOT used (e.g.
  /// an admin reset it), we trust that over any stale local/router flags.
  static Future<bool> hasGenerated([String? email, MikrotikService? service]) async {
    final userEmail = getEmail(email);
    if (userEmail.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();

    // 1. Check Cloud Database FIRST — cloud is authoritative (admin can reset from here).
    bool? cloudTrialUsed;
    try {
      final cloudData = await CloudSyncService.getUserState(userEmail);
      cloudTrialUsed = cloudData['trial_used'] == true;
    } catch (_) {
      // Network unreachable — fall back to local/router below.
    }

    if (cloudTrialUsed == false) {
      // Admin has cleared the trial in the cloud. Ensure local and router are
      // also cleared so a stale flag can't re-lock the trial later.
      await prefs.remove('$_trialPrefix$userEmail');
      if (service != null && service.isConnected) {
        await service.removeRouterTrialFlag(userEmail);
      }
      return false;
    }

    if (cloudTrialUsed == true) {
      // Cloud confirms trial was used — propagate down to local & router.
      await prefs.setBool('$_trialPrefix$userEmail', true);
      if (service != null && service.isConnected) {
        await service.setRouterTrialFlag(userEmail);
      }
      return true;
    }

    // Cloud unreachable — fall back to local SharedPreferences.
    final localUsed = prefs.getBool('$_trialPrefix$userEmail') ?? false;
    if (localUsed) return true;

    // Last resort: check MikroTik Router when offline from cloud.
    if (service != null && service.isConnected) {
      final routerUsed = await service.checkRouterTrialFlag(userEmail);
      if (routerUsed) {
        await prefs.setBool('$_trialPrefix$userEmail', true);
        return true;
      }
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
      await prefs.remove('$_proExpiresPrefix$userEmail');
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
  }

  // ─── Router Device Limit (Max 3 MikroTik per PRO Gmail) ──────────────────

  /// Generates a 16-char HMAC-SHA256 hex hash of [rawId] for use as a
  /// stable, opaque router key in Firebase (no serial exposed in plain text).
  static String _routerIdHash(String rawId) {
    final secret = dotenv.env['VOUCHER_APP_SECRET'] ?? 'va_fallback_secret';
    final key = utf8.encode(secret);
    final msg = utf8.encode(rawId.trim().toLowerCase());
    final hmac = Hmac(sha256, key);
    return hmac.convert(msg).toString().substring(0, 16);
  }

  /// Checks whether [routerRawId] (serial number or fallback) is an allowed
  /// device for this PRO [email] account, registering it if a slot is free.
  ///
  /// Returns:
  ///   [DeviceSlotResult.allowed]     — already registered, no action needed.
  ///   [DeviceSlotResult.registered]  — newly registered, slot consumed.
  ///   [DeviceSlotResult.denied]      — all 3 slots taken by other routers.
  ///   [DeviceSlotResult.offline]     — cloud unreachable; access is permitted.
  static Future<DeviceSlotResult> checkAndRegisterRouter(
    String email,
    String routerRawId,
    String routerLabel,
  ) async {
    if (email.isEmpty || routerRawId.isEmpty) return DeviceSlotResult.offline;

    final routerIdHash = _routerIdHash(routerRawId);
    final result = await CloudSyncService.registerRouter(email, routerIdHash, routerLabel);

    switch (result) {
      case 'allowed':     return DeviceSlotResult.allowed;
      case 'registered':  return DeviceSlotResult.registered;
      case 'denied':      return DeviceSlotResult.denied;
      default:            return DeviceSlotResult.offline; // 'error' → fail-open
    }
  }
}

/// Result of a device-slot check for a PRO Gmail account.
enum DeviceSlotResult {
  /// This router was already registered — no slot consumed.
  allowed,
  /// This router was just registered — slot consumed.
  registered,
  /// All 3 device slots are taken by other routers.
  denied,
  /// Cloud was unreachable — access is permitted (fail-open).
  offline,
}
