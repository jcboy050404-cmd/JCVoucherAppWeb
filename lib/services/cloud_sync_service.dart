import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cloud sync service using Firebase REST API for persistent account status.
///
/// Ensures Pro license and Trial usage status are stored in the cloud
/// tied to the user's Gmail address, surviving both phone wipes and router resets.
///
/// All requests are authenticated using the Firebase Database Secret so that
/// the database rules (auth != null) block all unauthenticated public access.
class CloudSyncService {
  // Firebase Realtime DB REST endpoint for JC Voucher App project
  static const String _baseUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/users';

  static const String _paymentReqUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/payment_requests';

  static const String _settingsUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/settings';

  // Firebase Database Secret — used to authenticate all REST requests.
  // Your database rules should be set to: ".read": "auth != null", ".write": "auth != null"
  static const String _dbSecret = '0esOIUJtoxYkD6OoJHvsaJx3ka03KtOddsNP4Diw';

  /// Appends the auth secret to any Firebase REST URL path.
  static String _auth(String path) => '$path?auth=$_dbSecret';

  static String _cleanEmail(String email) {
    return email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
  }

  /// Registers a new user account or fetches existing profile from Firebase Cloud DB.
  /// Returns a map with 'pro', 'trial_used', and 'is_new_account'.
  static Future<Map<String, dynamic>> registerOrFetchUserAccount(
    String email, {
    String? displayName,
    String? photoUrl,
  }) async {
    final cleanEmailStr = email.trim().toLowerCase();
    if (cleanEmailStr.isEmpty || cleanEmailStr == 'default_user') {
      return {'pro': false, 'trial_used': false, 'is_new_account': false};
    }

    final key = _cleanEmail(cleanEmailStr);
    final url = Uri.parse(_auth('$_baseUrl/$key.json'));

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      final nowStr = DateTime.now().toIso8601String();

      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null && data.isNotEmpty) {
          // Account already exists: update last_login_at
          final updatePayload = <String, dynamic>{
            'last_login_at': nowStr,
          };
          if (displayName != null && displayName.isNotEmpty) {
            updatePayload['display_name'] = displayName;
          }
          if (photoUrl != null && photoUrl.isNotEmpty) {
            updatePayload['photo_url'] = photoUrl;
          }
          await http.patch(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updatePayload),
          ).timeout(const Duration(seconds: 4));

          debugPrint('CloudSyncService: Account loaded from Cloud DB [$cleanEmailStr]');
          return {
            'pro': data['pro'] == true,
            'trial_used': data['trial_used'] == true,
            'is_admin': data['is_admin'] == true,
            'is_new_account': false,
            'created_at': data['created_at'],
            'photo_url': data['photo_url'],
            'display_name': data['display_name'],
          };
        }
      }

      // Account does not exist yet: Register new user account in Cloud DB!
      final name = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : cleanEmailStr.split('@').first;

      final newPayload = <String, dynamic>{
        'email': cleanEmailStr,
        'display_name': name,
        'photo_url': photoUrl ?? '',
        'created_at': DateTime.now().toIso8601String(),
        'last_login_at': DateTime.now().toIso8601String(),
        'pro': false,
        'trial_used': false,
        'is_admin': false,
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(newPayload),
      ).timeout(const Duration(seconds: 4));

      debugPrint('CloudSyncService: New account registered in Cloud DB [$cleanEmailStr]');
      return {
        'pro': false,
        'trial_used': false,
        'is_admin': false,
        'is_new_account': true,
        'created_at': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('CloudSyncService: Account registration network error ($e)');
    }

    return {'pro': false, 'trial_used': false, 'is_new_account': false};
  }

  /// Fetches cloud licensing state for [email].
  /// Returns a map containing {'pro': bool, 'trial_used': bool, 'pro_expires_at': String?}.
  static Future<Map<String, dynamic>> getUserState(String email) async {
    if (email.isEmpty || email == 'default_user') {
      return {'pro': false, 'trial_used': false};
    }

    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key.json'));

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          return {
            'pro': data['pro'] == true,
            'trial_used': data['trial_used'] == true,
            'pro_expires_at': data['pro_expires_at'],
          };
        }
      }
    } catch (e) {
      debugPrint('CloudSyncService: Network check skipped ($e)');
    }

    return {'pro': false, 'trial_used': false};
  }

  /// Saves cloud licensing state for [email].
  static Future<void> saveUserState(
    String email, {
    bool? pro,
    bool? trialUsed,
    String? proExpiresAt,
  }) async {
    if (email.isEmpty || email == 'default_user') return;

    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key.json'));

    final payload = <String, dynamic>{
      'email': email,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (pro != null) payload['pro'] = pro;
    if (trialUsed != null) payload['trial_used'] = trialUsed;
    if (proExpiresAt != null) payload['pro_expires_at'] = proExpiresAt;

    try {
      await http
          .patch(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('CloudSyncService: Network update skipped ($e)');
    }
  }

  /// Retrieves the user's PIN from Firebase (if set).
  static Future<String?> getUserPin(String email) async {
    if (email.isEmpty || email == 'default_user') return null;

    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key/pin.json'));

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body != 'null') {
        final raw = json.decode(response.body);
        return raw?.toString();
      }
    } catch (e) {
      debugPrint('CloudSyncService: Network PIN check skipped ($e)');
    }
    return null;
  }

  /// Saves a new PIN for the user in Firebase.
  static Future<bool> saveUserPin(String email, String pin) async {
    if (email.isEmpty || email == 'default_user') return false;

    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key.json'));

    try {
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'pin': pin, 'updated_at': DateTime.now().toIso8601String()}),
      ).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: Network PIN save skipped ($e)');
      return false;
    }
  }

  /// Resets all user PRO records in Firebase Cloud DB.
  static Future<void> resetAllProInCloud() async {
    try {
      final url = Uri.parse(_auth('$_baseUrl.json'));
      await http.delete(url).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('CloudSyncService: Delete skipped ($e)');
    }
  }

  // ─── Payment Requests (GCash QR / Admin Approval) ─────────────────────────

  /// Submits a new GCash payment reference number for Admin approval.
  static Future<bool> submitPaymentRequest({
    required String email,
    required String refNumber,
    required double amount,
    String plan = 'lifetime',
  }) async {
    final cleanRef = refNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanRef.isEmpty || email.isEmpty) return false;

    final url = Uri.parse(_auth('$_paymentReqUrl/$cleanRef.json'));
    final payload = {
      'email': email.trim().toLowerCase(),
      'ref_number': cleanRef,
      'amount': amount,
      'plan': plan,
      'status': 'pending', // pending, approved, rejected
      'submitted_at': DateTime.now().toIso8601String(),
    };

    try {
      final response = await http
          .put(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('CloudSyncService: Payment request submit error: $e');
      return false;
    }
  }

  /// Checks the latest payment request status for [email].
  static Future<Map<String, dynamic>?> getUserPaymentRequest(String email) async {
    if (email.isEmpty) return null;
    final cleanUserEmail = email.trim().toLowerCase();

    try {
      final url = Uri.parse(_auth('$_paymentReqUrl.json'));
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          Map<String, dynamic>? latestReq;
          DateTime? latestTime;

          data.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              final reqEmail = (val['email'] ?? '').toString().toLowerCase();
              if (reqEmail == cleanUserEmail) {
                final timeStr = val['submitted_at'] ?? '';
                final dt = DateTime.tryParse(timeStr) ?? DateTime(2000);
                if (latestTime == null || dt.isAfter(latestTime!)) {
                  latestTime = dt;
                  latestReq = val;
                }
              }
            }
          });
          return latestReq;
        }
      }
    } catch (e) {
      debugPrint('CloudSyncService: Check user payment request error: $e');
    }
    return null;
  }

  /// Fetches all payment requests for Admin approval history.
  static Future<List<Map<String, dynamic>>> getAllPaymentRequests() async {
    try {
      final url = Uri.parse(_auth('$_paymentReqUrl.json'));
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          final list = <Map<String, dynamic>>[];
          data.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              list.add(val);
            }
          });
          list.sort((a, b) {
            final tA = DateTime.tryParse(a['submitted_at'] ?? '') ?? DateTime(2000);
            final tB = DateTime.tryParse(b['submitted_at'] ?? '') ?? DateTime(2000);
            return tB.compareTo(tA);
          });
          return list;
        }
      }
    } catch (e) {
      debugPrint('CloudSyncService: Fetch pending requests error: $e');
    }
    return [];
  }

  /// Approves a GCash payment request by refNumber and unlocks PRO for the user.
  static Future<bool> approvePaymentRequest(String refNumber, String email, {String plan = 'lifetime'}) async {
    final cleanRef = refNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanRef.isEmpty) return false;

    try {
      final url = Uri.parse(_auth('$_paymentReqUrl/$cleanRef.json'));
      final update = {
        'status': 'approved',
        'approved_at': DateTime.now().toIso8601String(),
      };
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(update),
      ).timeout(const Duration(seconds: 4));

      // Unlock PRO license for user in Cloud DB
      String? expiresAt;
      if (plan == 'monthly') {
        expiresAt = DateTime.now().add(const Duration(days: 30)).toIso8601String();
      }
      await saveUserState(email, pro: true, proExpiresAt: expiresAt);
      return true;
    } catch (e) {
      debugPrint('CloudSyncService: Approve payment error: $e');
      return false;
    }
  }

  /// Rejects a GCash payment request by refNumber.
  static Future<bool> rejectPaymentRequest(String refNumber) async {
    final cleanRef = refNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanRef.isEmpty) return false;

    try {
      final url = Uri.parse(_auth('$_paymentReqUrl/$cleanRef.json'));
      final update = {
        'status': 'rejected',
        'rejected_at': DateTime.now().toIso8601String(),
      };
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(update),
      ).timeout(const Duration(seconds: 4));
      return true;
    } catch (e) {
      debugPrint('CloudSyncService: Reject payment error: $e');
      return false;
    }
  }

  /// Deletes a payment request history by refNumber.
  static Future<bool> deletePaymentRequest(String refNumber) async {
    final cleanRef = refNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanRef.isEmpty) return false;

    try {
      final url = Uri.parse(_auth('$_paymentReqUrl/$cleanRef.json'));
      final response = await http.delete(url).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: Delete payment error: $e');
      return false;
    }
  }

  /// Save GCash payment config (number, name, qr_url) to Cloud DB
  static Future<bool> saveGCashSettings({
    required String gcashNumber,
    required String accountName,
    String? qrImageUrl,
    String? proPrice,
    String? monthlyPrice,
  }) async {
    try {
      final url = Uri.parse(_auth('$_settingsUrl/gcash_config.json'));
      final payload = {
        'gcash_number': gcashNumber.trim(),
        'account_name': accountName.trim(),
        'qr_image_url': (qrImageUrl ?? '').trim(),
        'pro_price': (proPrice ?? '').trim(),
        'monthly_price': (monthlyPrice ?? '').trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: Save GCash settings error: $e');
      return false;
    }
  }

  /// Get GCash payment config from Cloud DB
  static Future<Map<String, String>> getGCashSettings() async {
    try {
      final url = Uri.parse(_auth('$_settingsUrl/gcash_config.json'));
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          return {
            'gcash_number': data['gcash_number']?.toString() ?? '',
            'account_name': data['account_name']?.toString() ?? '',
            'qr_image_url': data['qr_image_url']?.toString() ?? '',
            'pro_price': data['pro_price']?.toString() ?? '',
            'monthly_price': data['monthly_price']?.toString() ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint('CloudSyncService: Get GCash settings error: $e');
    }
    return {'gcash_number': '', 'account_name': '', 'qr_image_url': '', 'pro_price': '', 'monthly_price': ''};
  }

  /// Fetches all registered users from Firebase Database.
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final url = Uri.parse(_auth('$_baseUrl.json'));
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          final list = <Map<String, dynamic>>[];
          data.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              list.add({
                'id': key,
                'email': val['email'] ?? '',
                'display_name': val['display_name'] ?? '',
                'photo_url': val['photo_url'] ?? '',
                'pro': val['pro'] == true,
                'trial_used': val['trial_used'] == true,
                'is_admin': val['is_admin'] == true,
                'last_login_at': val['last_login_at'] ?? '',
                'created_at': val['created_at'] ?? '',
              });
            }
          });
          // Sort by last login (most recent first)
          list.sort((a, b) {
            final tA = DateTime.tryParse(a['last_login_at'] ?? '') ?? DateTime(2000);
            final tB = DateTime.tryParse(b['last_login_at'] ?? '') ?? DateTime(2000);
            return tB.compareTo(tA);
          });
          return list;
        }
      }
    } catch (e) {
      debugPrint('CloudSyncService: Fetch all users error: $e');
    }
    return [];
  }

  /// Deletes a user account from Firebase Database.
  static Future<bool> deleteUserAccount(String idOrEmail) async {
    final cleanId = _cleanEmail(idOrEmail);
    // CRITICAL FIX: Prevent empty ID from wiping out the entire 'users' node
    if (cleanId.isEmpty || cleanId == 'no_email') {
      debugPrint('CloudSyncService: Invalid user ID for deletion.');
      return false;
    }
    
    try {
      final url = Uri.parse(_auth('$_baseUrl/$cleanId.json'));
      final response = await http.delete(url).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: Delete user error: $e');
      return false;
    }
  }

  /// Fetches global app settings
  static Future<Map<String, dynamic>> getGlobalSettings() async {
    try {
      final url = Uri.parse(_auth('$_settingsUrl.json'));
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 && response.body != 'null') {
        return json.decode(response.body) as Map<String, dynamic>? ?? {};
      }
    } catch (e) {
      debugPrint('CloudSyncService: fetch settings error: $e');
    }
    return {};
  }

  /// Updates global app settings
  static Future<bool> updateGlobalSettings(Map<String, dynamic> settings) async {
    try {
      final url = Uri.parse(_auth('$_settingsUrl.json'));
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(settings),
      ).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: update settings error: $e');
      return false;
    }
  }
}
