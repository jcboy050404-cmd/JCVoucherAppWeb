import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pppoe_user.dart';

class AutoSmsService {
  static const MethodChannel _channel = MethodChannel('com.jc.voucherapps/sms');

  static const String _keyEnabled = 'auto_sms_enabled';
  static const String _keyDaysBefore = 'auto_sms_days_before';
  static const String _keyTemplate = 'auto_sms_template';
  static const String _keyHistoryPrefix = 'auto_sms_sent_';

  static const String defaultTemplate =
      'Hi {name}, reminder from your ISP: Your PPPoE monthly bill (₱{amount}) is due on {date}. Please settle on time to avoid disconnection. Thank you!';

  /// Check if Auto SMS is enabled
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? true;
  }

  static Future<void> setEnabled(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, val);
  }

  /// Days before due date to send reminder (0 = on due date, 1 = 1 day before, etc)
  static Future<int> getDaysBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDaysBefore) ?? 1;
  }

  static Future<void> setDaysBefore(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDaysBefore, days);
  }

  /// Get customizable template
  static Future<String> getTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyTemplate) ?? defaultTemplate;
  }

  static Future<void> setTemplate(String tpl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTemplate, tpl);
  }

  /// Request SMS Permission on Android.
  ///
  /// Returns true if permission is granted. Note that if the user previously
  /// selected "Deny (and don't ask again)", the system dialog can no longer be
  /// shown — in that case use [ensurePermissionOrPrompt] to direct them to the
  /// system Settings screen, which is the only place the (greyed-out) toggle
  /// can be re-enabled.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.sms.status;
    if (status.isGranted) return true;
    // Don't call .request() if already permanently denied — it would just
    // resolve to denied again with no dialog shown.
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.sms.request();
    return result.isGranted;
  }

  /// True once the user has denied SMS access permanently (system dialog can
  /// no longer appear). The UI uses this to show the "Open Settings" path.
  static Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    return (await Permission.sms.status).isPermanentlyDenied;
  }

  /// Direct silent SMS send using Android SmsManager via MethodChannel
  static Future<bool> sendDirectSms({
    required String phone,
    required String message,
  }) async {
    if (!Platform.isAndroid) return false;

    final hasPerm = await requestPermission();
    if (!hasPerm) return false;

    try {
      final res = await _channel.invokeMethod<bool>('sendSms', {
        'phone': phone,
        'message': message,
      });
      return res == true;
    } catch (e) {
      return false;
    }
  }

  /// Check all users and send automated reminders for eligible users
  static Future<int> checkAndSendAutoReminders(List<PppoeUser> users) async {
    if (!Platform.isAndroid) return 0;
    final enabled = await isEnabled();
    if (!enabled) return 0;

    final daysBefore = await getDaysBefore();
    final template = await getTemplate();
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateTime.now().toIso8601String().split('T').first;

    int sentCount = 0;

    // Lazily clean up stale history keys (older than 30 days) once per run so
    // the prefs store doesn't grow forever.
    await _pruneOldHistoryKeys(prefs);

    for (final user in users) {
      if (user.dueDate == null) continue;
      final phone = user.phoneNumber;
      if (phone == null || phone.isEmpty) continue;

      final daysUntil = user.daysUntilDue;
      if (daysUntil == null) continue;

      // Eligible from `daysBefore` days ahead, and STAYS eligible once overdue —
      // an unpaid client should keep getting reminders until they pay, not stop
      // after being 1 day late.
      if (daysUntil <= daysBefore) {
        final historyKey = '$_keyHistoryPrefix${user.name}_$todayStr';
        if (prefs.getBool(historyKey) == true) {
          // Already sent today for this user
          continue;
        }

        final dateStr =
            "${user.dueDate!.year}-${user.dueDate!.month.toString().padLeft(2, '0')}-${user.dueDate!.day.toString().padLeft(2, '0')}";
        // Show the fee only when it's actually set; otherwise omit the amount
        // rather than advertising "₱0".
        final amountStr = user.monthlyFee > 0
            ? user.monthlyFee.toStringAsFixed(0)
            : "";

        final msg = template
            .replaceAll('{name}', user.name)
            .replaceAll('{amount}', amountStr)
            .replaceAll('{date}', dateStr)
            .replaceAll('{days}', daysUntil == 0
                ? 'Today'
                : (daysUntil < 0 ? '${daysUntil.abs()} day(s) overdue' : '$daysUntil day(s)'));

        final success = await sendDirectSms(phone: phone, message: msg);
        if (success) {
          await prefs.setBool(historyKey, true);
          sentCount++;
        }
      }
    }

    return sentCount;
  }

  /// Removes `auto_sms_sent_<name>_<YYYY-MM-DD>` keys whose date is older than
  /// 30 days. Keeps the store bounded across months of use.
  static Future<void> _pruneOldHistoryKeys(SharedPreferences prefs) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyHistoryPrefix));
    for (final key in keys) {
      // Key format: <prefix><name>_<YYYY-MM-DD>  → take the trailing date.
      final datePart = key.substring(key.length - 10);
      final parsed = DateTime.tryParse(datePart);
      if (parsed != null && parsed.isBefore(cutoff)) {
        await prefs.remove(key);
      }
    }
  }

  // ─── Background automation ───────────────────────────────────────────────
  //
  // Previously reminders only sent while the PPPoE Clients screen was open.
  // Now we cache a lightweight snapshot of due users whenever fresh router
  // data is fetched, and a periodic timer re-runs the check every few hours
  // from that snapshot — so reminders still go out if the operator opens the
  // dashboard (or the app resumes) but never visits the PPPoE screen.

  static const String _keySnapshot = 'auto_sms_reminder_snapshot';
  static const Duration _checkInterval = Duration(hours: 4);
  static Timer? _periodicTimer;

  /// Cache only the fields needed to send a reminder, so the background runner
  /// works without a live router connection. Call this whenever fresh PPPoE
  /// data is loaded (see PppoeScreen._loadData).
  static Future<void> saveReminderSnapshot(List<PppoeUser> users) async {
    final snapshot = users
        .where((u) => u.dueDate != null)
        .map((u) => {
              'name': u.name,
              'phone': u.phoneNumber ?? '',
              'dueDate': u.dueDate!.toIso8601String(),
              'monthlyFee': u.monthlyFee,
            })
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySnapshot, jsonEncode(snapshot));
  }

  static Future<List<PppoeUser>> _loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_keySnapshot);
    if (str == null || str.isEmpty) return [];
    try {
      final list = jsonDecode(str) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return PppoeUser(
          id: '',
          name: (m['name'] as String?) ?? '',
          password: '',
          dueDate: DateTime.tryParse((m['dueDate'] as String?) ?? ''),
          monthlyFee: (m['monthlyFee'] as num?)?.toDouble() ?? 0.0,
          // Re-inject the cached phone via the comment so phoneNumber matches.
          comment: (m['phone'] as String?) ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('AutoSmsService: snapshot parse error ($e)');
      return [];
    }
  }

  /// Run a reminder pass against the cached snapshot. Returns the number sent.
  /// Safe to call from anywhere (no router connection required).
  static Future<int> runFromSnapshot() async {
    final users = await _loadSnapshot();
    if (users.isEmpty) return 0;
    return checkAndSendAutoReminders(users);
  }

  /// Starts a periodic background reminder check (every 4 hours) plus an
  /// immediate pass. Idempotent — calling again is a no-op if already running.
  /// Call this from the dashboard after login so reminders keep firing while
  /// the app is alive, even if the PPPoE screen is never opened.
  static void startBackgroundChecks() {
    if (!Platform.isAndroid) return;
    _periodicTimer?.cancel();
    // Immediate pass (covers app-resume), then on the interval.
    runFromSnapshot();
    _periodicTimer = Timer.periodic(_checkInterval, (_) => runFromSnapshot());
  }

  /// Stops the periodic check (e.g. on logout).
  static void stopBackgroundChecks() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
