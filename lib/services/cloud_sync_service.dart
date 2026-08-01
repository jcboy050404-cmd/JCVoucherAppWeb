import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Cloud sync service using Firebase REST API for persistent account status.
///
/// Ensures Pro license and Trial usage status are stored in the cloud
/// tied to the user's Gmail address, surviving both phone wipes and router resets.
///
/// All requests are authenticated using the Firebase Database Secret so that
/// the database rules (auth != null) block all unauthenticated public access.
///
/// ⚠️ NOTE: The Database Secret is loaded from `.env`, which is still bundled
/// inside the shipped APK and therefore NOT truly secret. For production,
/// proxy these calls through Firebase Cloud Functions so the secret stays
/// on the server. This is an interim measure to remove it from source code.
class CloudSyncService {
  // Firebase Realtime DB REST endpoint for JC Voucher App project
  static const String _baseUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/users';

  static const String _paymentReqUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/payment_requests';

  static const String _settingsUrl =
      'https://jc-voucher-app-default-rtdb.asia-southeast1.firebasedatabase.app/settings';

  // Firebase Database Secret — used to authenticate all REST requests.
  // Loaded from .env at runtime (see the security note in .env).
  // Your database rules should be set to: ".read": "auth != null", ".write": "auth != null"
  static String get _dbSecret => dotenv.env['FIREBASE_DB_SECRET'] ?? '';

  /// Appends the auth secret to any Firebase REST URL path.
  static String _auth(String path) {
    if (_dbSecret.isEmpty) return path;
    return path.contains('?') ? '$path&auth=$_dbSecret' : '$path?auth=$_dbSecret';
  }

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
          http.patch(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updatePayload),
          ).timeout(const Duration(seconds: 4)).catchError((_) => http.Response('', 500));

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
            'custom_max_routers': data['custom_max_routers'],
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
    int? customMaxRouters,
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
    if (customMaxRouters != null) {
      if (customMaxRouters == -1) {
        payload['custom_max_routers'] = null; // deletes the key
      } else {
        payload['custom_max_routers'] = customMaxRouters;
      }
    }

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

  // ─── Router Device Limit (Max 3 per PRO Gmail) ────────────────────────────

  /// Returns the map of routers registered for [email].
  /// Keys are hashed router IDs; values contain 'label' and 'registered_at'.
  static Future<Map<String, dynamic>> getRegisteredRouters(String email) async {
    if (email.isEmpty || email == 'default_user') return {};
    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key/registered_routers.json'));
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body);
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('CloudSyncService: getRegisteredRouters error ($e)');
    }
    return {};
  }

  /// Attempts to register [routerIdHash] for [email].
  ///
  /// Returns:
  ///   'allowed'   — router was already registered (no change needed).
  ///   'registered'— router was newly registered (slot consumed).
  ///   'denied'    — all configured slots are taken by other routers.
  ///   'error'     — network/cloud failure.
  //
  // The limit is now admin-editable via cloud global settings (key
  // 'max_routers_per_account'). This constant is only the FALLBACK used when no
  // cloud value is set yet (keeps backward compatibility so existing accounts
  // don't suddenly get 100 slots on the next app update). The admin raises it
  // (e.g. to 100) from the Admin → Global App Settings screen.
  static const int kDefaultMaxRoutersPerAccount = 3;

  /// Cache of the effective limit so registerRouter doesn't fetch settings on
  /// every router connect (it's also only called once per session, verdict
  /// cached upstream in TrialService). null = not loaded yet.
  static int? _maxRoutersCache;

  /// Returns the admin-configured max MikroTik devices per PRO account.
  /// Reads cloud global settings once, then serves from cache. Falls back to
  /// [kDefaultMaxRoutersPerAccount] on any error / unset value.
  static Future<int> getMaxRoutersPerAccount() async {
    final cached = _maxRoutersCache;
    if (cached != null) return cached;
    try {
      final settings = await getGlobalSettings();
      final v = settings['max_routers_per_account'];
      final parsed = v is int ? v : int.tryParse(v?.toString() ?? '');
      final limit = (parsed == null || parsed < 1) ? kDefaultMaxRoutersPerAccount : parsed;
      _maxRoutersCache = limit;
      return limit;
    } catch (_) {
      return kDefaultMaxRoutersPerAccount;
    }
  }

  /// Lets the Admin screen refresh the cache immediately after editing the
  /// limit so the next login uses the new value without a restart.
  static void setMaxRoutersCache(int v) {
    _maxRoutersCache = v < 1 ? kDefaultMaxRoutersPerAccount : v;
  }

  /// Gets the effective max routers for [email]. Checks user's custom limit
  /// first, then falls back to the global limit.
  static Future<int> getMaxRoutersForEmail(String email) async {
    try {
      final userState = await getUserState(email);
      final customRaw = userState['custom_max_routers'];
      if (customRaw != null) {
        final parsed = customRaw is int ? customRaw : int.tryParse(customRaw.toString());
        if (parsed != null && parsed >= 1) return parsed;
      }
    } catch (e) {
      debugPrint('CloudSyncService: Failed to parse custom limit ($e)');
    }
    return await getMaxRoutersPerAccount();
  }

  static Future<String> registerRouter(
    String email,
    String routerIdHash,
    String label,
  ) async {
    if (email.isEmpty || routerIdHash.isEmpty) return 'error';
    final key = _cleanEmail(email);
    final registeredRoutersUrl = '$_baseUrl/$key/registered_routers';

    // ── Atomic compare-and-swap with ETag (fixes TOCTOU race condition) ──────
    // Using Firebase's conditional write (X-Firebase-ETag + if-match) so that
    // if two phones on the same account try to register simultaneously, only
    // ONE succeeds — the other gets HTTP 412 and retries with fresh data.
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Step 1: GET the full registered_routers node with an ETag.
        // X-Firebase-ETag: true tells Firebase to include a strong ETag in the
        // response header that uniquely identifies the current state of the node.
        final getUrl = Uri.parse(_auth('$registeredRoutersUrl.json'));
        final getResponse = await http.get(
          getUrl,
          headers: {'X-Firebase-ETag': 'true'},
        ).timeout(const Duration(seconds: 5));

        if (getResponse.statusCode != 200) return 'error';

        // Firebase returns a quoted ETag e.g. "abc123" — keep as-is for if-match.
        final etag = getResponse.headers['etag'] ?? '';

        Map<String, dynamic> existing = {};
        if (getResponse.body != 'null') {
          final data = json.decode(getResponse.body);
          if (data is Map) existing = Map<String, dynamic>.from(data);
        }

        // Step 2: Already registered → allow immediately (no write needed).
        if (existing.containsKey(routerIdHash)) {
          debugPrint('CloudSyncService: Router $routerIdHash already registered for $email');
          return 'allowed';
        }

        // Step 3: Slots full → deny.
        final limit = await getMaxRoutersForEmail(email);
        if (existing.length >= limit) {
          debugPrint('CloudSyncService: Device limit reached for $email (${existing.length}/$limit)');
          return 'denied';
        }

        // Step 4: Atomic PUT — write the full updated node with the new entry.
        // Firebase rejects with 412 if the node was modified since our GET,
        // protecting against concurrent registrations bypassing the limit.
        final updatedRouters = Map<String, dynamic>.from(existing)
          ..[routerIdHash] = {
            'label': label.isNotEmpty ? label : 'MikroTik Router',
            'registered_at': DateTime.now().toIso8601String(),
          };

        final putUrl = Uri.parse(_auth('$registeredRoutersUrl.json'));
        final putResponse = await http.put(
          putUrl,
          headers: {
            'Content-Type': 'application/json',
            if (etag.isNotEmpty) 'if-match': etag,
          },
          body: json.encode(updatedRouters),
        ).timeout(const Duration(seconds: 5));

        if (putResponse.statusCode == 200) {
          debugPrint('CloudSyncService: Registered router $routerIdHash for $email (attempt ${attempt + 1})');
          return 'registered';
        }

        if (putResponse.statusCode == 412) {
          // Another device modified the node between our GET and PUT.
          // Back off briefly and retry with freshly fetched data.
          debugPrint('CloudSyncService: ETag mismatch on attempt ${attempt + 1} for $email — retrying…');
          await Future.delayed(Duration(milliseconds: 120 * (attempt + 1)));
          continue;
        }

        debugPrint('CloudSyncService: registerRouter HTTP ${putResponse.statusCode}');
        return 'error';
      } catch (e) {
        debugPrint('CloudSyncService: registerRouter error ($e)');
        return 'error';
      }
    }

    // All retries exhausted — means ≥3 near-simultaneous registrations for the
    // same account. Deny rather than silently exceed the device limit.
    debugPrint('CloudSyncService: registerRouter: all retries exhausted for $email — denying');
    return 'denied';
  }

  /// Removes a registered router entry for [email] (admin utility).
  static Future<bool> removeRouter(String email, String routerIdHash) async {
    if (email.isEmpty || routerIdHash.isEmpty) return false;
    final key = _cleanEmail(email);
    final url = Uri.parse(_auth('$_baseUrl/$key/registered_routers/$routerIdHash.json'));
    try {
      final response = await http.delete(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CloudSyncService: removeRouter error ($e)');
      return false;
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
      final queryUrl = '$_paymentReqUrl.json?orderBy="email"&equalTo="${Uri.encodeComponent(cleanUserEmail)}"';
      final url = Uri.parse(_auth(queryUrl));
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          Map<String, dynamic>? latestReq;
          DateTime? latestTime;

          data.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              final timeStr = val['submitted_at'] ?? '';
              final dt = DateTime.tryParse(timeStr) ?? DateTime(2000);
              if (latestTime == null || dt.isAfter(latestTime!)) {
                latestTime = dt;
                latestReq = val;
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
      final queryUrl = '$_paymentReqUrl.json?orderBy="submitted_at"&limitToLast=50';
      final url = Uri.parse(_auth(queryUrl));
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
      final queryUrl = '$_baseUrl.json?orderBy="last_login_at"&limitToLast=50';
      final url = Uri.parse(_auth(queryUrl));
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
      } else {
        debugPrint('CloudSyncService: Fetch all users failed. Status: ${response.statusCode}, Body: ${response.body}');
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
