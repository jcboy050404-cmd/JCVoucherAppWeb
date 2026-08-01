import 'dart:convert';
import 'dart:io' show HttpServer, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/google_user.dart';
import 'cloud_sync_service.dart';

/// Singleton service managing Gmail / Google Authentication in VoucherApp.
///
/// Session persistence strategy:
///   1. Primary: flutter_secure_storage (Android Keystore) — survives uninstall
///   2. Fallback: SharedPreferences — fast local cache
///
/// On sign-in, we write to BOTH stores.
/// On init, we read from secure storage first; if empty, fall back to prefs.
class AuthService {
  static final AuthService instance = AuthService._internal();
  AuthService._internal();

  // ── Storage Keys ──────────────────────────────────────────────────────────
  static const String _secureEmailKey = 'voucher_gmail_email_v1';
  static const String _secureDisplayKey = 'voucher_gmail_display_v1';
  static const String _securePhotoKey = 'voucher_gmail_photo_v1';
  static const String _secureIdKey = 'voucher_gmail_id_v1';
  static const String _prefsUserKey = 'gmail_user_session_v1';

  // ── Secure Storage (Android Keystore / iOS Keychain) ─────────────────────
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ── Google Sign-In ────────────────────────────────────────────────────────
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  // ── State ─────────────────────────────────────────────────────────────────
  final ValueNotifier<GoogleUserModel?> currentUserNotifier =
      ValueNotifier<GoogleUserModel?>(null);

  GoogleUserModel? get currentUser => currentUserNotifier.value;
  bool get isSignedIn => currentUserNotifier.value != null;

  // ── Admin Config ─────────────────────────────────────────────────────────

  /// Returns true if the provided email is an authorized Admin account.
  static bool isCurrentUserAdmin(String? email) {
    if (email == null) return false;
    final clean = email.trim().toLowerCase();
    final currentEmail = instance.currentUser?.email.toLowerCase();
    
    // Check if the current user is an admin
    if (clean == currentEmail) {
      return instance.currentUser?.isAdmin ?? false;
    }
    return false;
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  /// Restores session on app start.
  /// Priority: secure storage → SharedPreferences (migration) → null
  Future<GoogleUserModel?> init() async {
    try {
      // 1. Primary: Try SharedPreferences first (more reliable on Windows desktop)
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString(_prefsUserKey);
      
      if (savedUserJson != null && savedUserJson.isNotEmpty) {
        final user = GoogleUserModel.fromJson(savedUserJson);
        currentUserNotifier.value = user;
        debugPrint('AuthService: Session restored from SharedPreferences [${user.email}]');
        
        // Background sync to secure storage just in case it was wiped
        _writeToSecureStorage(user);
        return user;
      }

      // 2. Fallback: Try secure storage (survives uninstall on Android/iOS)
      final email = await _secureStorage.read(key: _secureEmailKey);
      if (email != null && email.isNotEmpty) {
        final displayName =
            await _secureStorage.read(key: _secureDisplayKey) ??
                email.split('@').first;
        final photoRaw = await _secureStorage.read(key: _securePhotoKey);
        final photoUrl = (photoRaw != null && photoRaw.isNotEmpty) ? photoRaw : null;
        final id = await _secureStorage.read(key: _secureIdKey) ??
            'secure_user_${email.hashCode}';

        final user = GoogleUserModel(
          id: id,
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
        );
        currentUserNotifier.value = user;
        debugPrint('AuthService: Session recovered from secure storage [$email]');
        
        // Migrate back to SharedPreferences
        prefs.setString(_prefsUserKey, user.toJson());
        return user;
      }
    } catch (e) {
      debugPrint('AuthService: Error loading saved user session: $e');
    }

    return null;
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────
  /// Authenticates with Google and returns the user model without saving the session yet.
  Future<GoogleUserModel?> authenticateWithGoogle() async {
    if (!kIsWeb && Platform.isWindows) {
      return _authenticateWithGoogleWindows();
    }

    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return null;

      final authentication = await account.authentication;
      return GoogleUserModel(
        id: account.id,
        email: account.email,
        displayName:
            (account.displayName != null &&
                    account.displayName!.trim().isNotEmpty)
                ? account.displayName!
                : account.email.split('@').first,
        photoUrl: account.photoUrl,
        idToken: authentication.idToken,
      );
    } catch (error) {
      debugPrint('AuthService: Google Sign In error: $error');
      rethrow;
    }
  }

  /// Custom Windows Desktop OAuth 2.0 Loopback Flow
  Future<GoogleUserModel?> _authenticateWithGoogleWindows() async {
    final String clientId = dotenv.env['GOOGLE_OAUTH_CLIENT_ID_WINDOWS'] ?? '';
    final String clientSecret = dotenv.env['GOOGLE_OAUTH_CLIENT_SECRET_WINDOWS'] ?? '';

    HttpServer? server;
    try {
      // 1. Start a local server to listen for the redirect
      server = await HttpServer.bind('127.0.0.1', 0);
      final redirectUri = 'http://127.0.0.1:${server.port}';

      // 2. Open browser for Google Sign-In
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'email profile openid',
        'access_type': 'offline',
        'prompt': 'select_account',
      });

      if (!await launchUrl(authUrl)) {
        return null;
      }

      // 3. Wait for the redirect request from the browser
      final request = await server.first.timeout(const Duration(seconds: 120));
      final code = request.uri.queryParameters['code'];

      // Send a response to the browser so the user knows they can close the tab
      request.response
        ..statusCode = 200
        ..headers.set('Content-Type', 'text/html')
        ..write('''
          <html>
            <head><title>Sign in successful</title></head>
            <body style="font-family: sans-serif; text-align: center; margin-top: 50px;">
              <h1 style="color: #4CAF50;">Authentication Successful!</h1>
              <p>You can close this window and return to the Voucher App.</p>
              <script>window.close();</script>
            </body>
          </html>
        ''');
      await request.response.close();

      if (code == null) {
        return null; // User cancelled or error
      }

      // 4. Exchange the code for an access token and ID token
      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        body: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': redirectUri,
        },
      );

      if (tokenResponse.statusCode != 200) {
        debugPrint('AuthService: Token exchange failed - ${tokenResponse.body}');
        return null;
      }

      final tokenData = json.decode(tokenResponse.body);
      final accessToken = tokenData['access_token'];
      final idToken = tokenData['id_token'];

      // 5. Fetch user profile info using the access token
      final profileResponse = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (profileResponse.statusCode != 200) {
        debugPrint('AuthService: Profile fetch failed - ${profileResponse.body}');
        return null;
      }

      final profileData = json.decode(profileResponse.body);

      return GoogleUserModel(
        id: profileData['id'] ?? 'windows_${profileData['email'].hashCode}',
        email: profileData['email'],
        displayName: profileData['name'] ?? profileData['email'].split('@').first,
        photoUrl: profileData['picture'],
        idToken: idToken,
      );
    } catch (e) {
      debugPrint('AuthService: Windows OAuth error: $e');
      return null;
    } finally {
      await server?.close();
    }
  }

  /// Finalizes the sign-in by saving the user session.
  Future<void> completeSignIn(GoogleUserModel user) async {
    await _saveUserSession(user);
  }

  // ── Manual Email Sign-In ──────────────────────────────────────────────────
  Future<GoogleUserModel> signInWithCustomEmail({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final cleanEmail = email.trim();
    final name = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName.trim()
        : cleanEmail.split('@').first;

    final user = GoogleUserModel(
      id: 'gmail_user_${cleanEmail.hashCode}',
      email: cleanEmail,
      displayName: name,
      photoUrl: photoUrl,
    );

    await _saveUserSession(user);
    return user;
  }

  // ── Update User ───────────────────────────────────────────────────────────
  Future<GoogleUserModel?> updateCurrentUser({
    required String email,
    required String displayName,
  }) async {
    final current = currentUser;
    if (current == null) return null;

    final updatedUser = GoogleUserModel(
      id: current.id,
      email: email.trim(),
      displayName: displayName.trim(),
      photoUrl: current.photoUrl,
      idToken: current.idToken,
      isAdmin: current.isAdmin,
      signedInAt: current.signedInAt,
    );

    await _saveUserSession(updatedUser);
    return updatedUser;
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      debugPrint('AuthService: Google Sign Out error: $e');
    } finally {
      await _clearSecureStorage();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsUserKey);
      currentUserNotifier.value = null;
    }
  }

  // ── Private Helpers ───────────────────────────────────────────────────────
  Future<void> _saveUserSession(GoogleUserModel user) async {
    // Write to secure storage (survives uninstall via Android Keystore)
    await _writeToSecureStorage(user);

    // Also write to SharedPreferences as fast cache
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsUserKey, user.toJson());
    } catch (e) {
      debugPrint('AuthService: SharedPreferences write failed: $e');
    }

    currentUserNotifier.value = user;
    debugPrint('AuthService: Session saved [${user.email}]');

    // Register / Sync user account with Online Free Cloud Database (Firebase Realtime DB)
    try {
      final res = await CloudSyncService.registerOrFetchUserAccount(
        user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
      );
      final prefs = await SharedPreferences.getInstance();
      final emailKey = user.email.toLowerCase();

      // Sync PRO status — set OR clear based on cloud truth.
      if (res['pro'] == true) {
        await prefs.setBool('pro_unlocked_$emailKey', true);
      } else {
        // Cloud says NOT pro (or admin downgraded) — clear the stale local flag.
        await prefs.remove('pro_unlocked_$emailKey');
        await prefs.remove('pro_expires_$emailKey');
      }

      // Sync Trial status — set OR clear based on cloud truth.
      // If admin reset the trial (cloud = false), clear the stale local flag
      // immediately on login so the user isn't stuck waiting for the dashboard.
      if (res['trial_used'] == true) {
        await prefs.setBool('trial_generated_$emailKey', true);
      } else {
        // Admin has reset the trial in cloud — clear local flag now.
        await prefs.remove('trial_generated_$emailKey');
      }
      if (res['is_new_account'] == true) {
        debugPrint('AuthService: Registered NEW account in Online Cloud DB!');
      }

      // Sync Admin Status dynamically from Firebase
      final bool dbIsAdmin = res['is_admin'] == true;
      if (dbIsAdmin != user.isAdmin) {
        final updatedUser = GoogleUserModel(
          id: user.id,
          email: user.email,
          displayName: user.displayName,
          photoUrl: user.photoUrl,
          idToken: user.idToken,
          isAdmin: dbIsAdmin,
          signedInAt: user.signedInAt,
        );
        // Silently update the storage & state with the new admin flag
        await _writeToSecureStorage(updatedUser);
        await prefs.setString(_prefsUserKey, updatedUser.toJson());
        currentUserNotifier.value = updatedUser;
        debugPrint('AuthService: Admin status updated from Cloud DB [isAdmin=$dbIsAdmin]');
      }
    } catch (e) {
      debugPrint('AuthService: Online DB registration error: $e');
    }
  }

  Future<void> _writeToSecureStorage(GoogleUserModel user) async {
    try {
      // Always clear all keys first so stale values from a previous account
      // never bleed into the newly signed-in session (e.g. old photoUrl persisting
      // when the new account has no photo — the "wrong account on dashboard" bug).
      await _clearSecureStorage();
      await _secureStorage.write(key: _secureEmailKey, value: user.email);
      await _secureStorage.write(key: _secureDisplayKey, value: user.displayName);
      await _secureStorage.write(key: _secureIdKey, value: user.id);
      // Always write photoUrl (even empty string) so the old value never leaks.
      await _secureStorage.write(key: _securePhotoKey, value: user.photoUrl ?? '');
    } catch (e) {
      debugPrint('AuthService: Secure storage write failed: $e');
    }
  }

  Future<void> _clearSecureStorage() async {
    try {
      await _secureStorage.delete(key: _secureEmailKey);
      await _secureStorage.delete(key: _secureDisplayKey);
      await _secureStorage.delete(key: _securePhotoKey);
      await _secureStorage.delete(key: _secureIdKey);
    } catch (e) {
      debugPrint('AuthService: Secure storage clear failed: $e');
    }
  }
}

