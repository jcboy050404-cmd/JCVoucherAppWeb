import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class ClientBillingInfo {
  final String username;
  final DateTime? dueDate;
  final double monthlyFee;

  ClientBillingInfo({
    required this.username,
    this.dueDate,
    this.monthlyFee = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'dueDate': dueDate?.toIso8601String(),
        'monthlyFee': monthlyFee,
      };

  factory ClientBillingInfo.fromJson(Map<String, dynamic> json) {
    return ClientBillingInfo(
      username: json['username'] ?? '',
      dueDate: json['dueDate'] != null ? DateTime.tryParse(json['dueDate']) : null,
      monthlyFee: (json['monthlyFee'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class PppoeBillingService {
  static const String _key = 'pppoe_client_billing_map_v1';

  static Future<Map<String, ClientBillingInfo>> loadBillingMap() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key);
    if (str == null || str.isEmpty) return {};

    try {
      final Map<String, dynamic> decoded = jsonDecode(str);
      final result = <String, ClientBillingInfo>{};
      decoded.forEach((key, value) {
        result[key.toLowerCase()] = ClientBillingInfo.fromJson(Map<String, dynamic>.from(value));
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveClientBilling(String username, DateTime? dueDate, double monthlyFee) async {
    final map = await loadBillingMap();
    final key = username.trim().toLowerCase();
    map[key] = ClientBillingInfo(
      username: username,
      dueDate: dueDate,
      monthlyFee: monthlyFee,
    );

    final prefs = await SharedPreferences.getInstance();
    final jsonMap = map.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_key, jsonEncode(jsonMap));

    if (dueDate != null) {
      await NotificationService().scheduleDueDateNotification(username, dueDate);
    } else {
      await NotificationService().cancelNotification(username);
    }
  }

  /// Adds exactly one calendar month to [baseDate], clamping the day to the
  /// last valid day of the target month. This avoids Dart's overflow behaviour
  /// where DateTime(2026, 1, 31) silently becomes Mar 3 (Feb has 28/29 days),
  /// which previously caused end-of-month due dates to drift forward.
  ///
  /// Example: Jan 31 → Feb 28 (or 29 in a leap year), Mar 31 → Apr 30.
  static DateTime _addOneMonth(DateTime baseDate) {
    final targetMonth = baseDate.month + 1;
    final targetYear = baseDate.year + (targetMonth > 12 ? 1 : 0);
    final normalizedMonth = ((targetMonth - 1) % 12) + 1;
    // Days in the target month, accounting for leap years in February.
    final daysInTargetMonth = DateTime(targetYear, normalizedMonth + 1, 0).day;
    final clampedDay = baseDate.day < daysInTargetMonth
        ? baseDate.day
        : daysInTargetMonth;
    return DateTime(targetYear, normalizedMonth, clampedDay);
  }

  static Future<DateTime?> extendDueDateByOneMonth(String username, {DateTime? currentDueDate}) async {
    // Prefer the stored due date as the base when the caller didn't pass one,
    // so the extension always continues from the real billing cycle instead
    // of jumping forward from "now" (which can skip or duplicate a cycle).
    final map = await loadBillingMap();
    final key = username.trim().toLowerCase();
    final stored = map[key];

    DateTime baseDate;
    if (currentDueDate != null) {
      baseDate = currentDueDate;
    } else if (stored?.dueDate != null) {
      baseDate = stored!.dueDate!;
    } else {
      baseDate = DateTime.now();
    }

    final newDueDate = _addOneMonth(baseDate);
    final existingFee = stored?.monthlyFee ?? 0.0;

    await saveClientBilling(username, newDueDate, existingFee);
    return newDueDate;
  }
}
