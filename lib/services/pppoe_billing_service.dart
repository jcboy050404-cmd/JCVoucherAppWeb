import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
  }

  static Future<DateTime?> extendDueDateByOneMonth(String username, {DateTime? currentDueDate}) async {
    final baseDate = currentDueDate ?? DateTime.now();
    final newDueDate = DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
    
    final map = await loadBillingMap();
    final key = username.trim().toLowerCase();
    final existingFee = map[key]?.monthlyFee ?? 0.0;

    await saveClientBilling(username, newDueDate, existingFee);
    return newDueDate;
  }
}
