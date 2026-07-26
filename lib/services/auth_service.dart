import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static bool isAdmin(String? email) {
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
      // 1. Try secure storage first (survives uninstall)
      final email = await _secureStorage.read(key: _secureEmailKey);
      if (email != null && email.isNotEmpty) {
        final displayName =
            await _secureStorage.read(key: _secureDisplayKey) ??
                email.split('@').first;
        final photoUrl = await _secureStorage.read(key: _securePhotoKey);
        final id = await _secureStorage.read(key: _secureIdKey) ??
            'secure_user_${email.hashCode}';

        final user = GoogleUserModel(
          id: id,
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
        );
        currentUserNotifier.value = user;
        debugPrint('AuthService: Session restored from secure storage [$email]');
        return user;
      }

      // 2. Fall back to SharedPreferences (and migrate to secure storage)
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString(_prefsUserKey);
      if (savedUserJson != null && savedUserJson.isNotEmpty) {
        final user = GoogleUserModel.fromJson(savedUserJson);

        // Migrate to secure storage so next launch uses it
        await _writeToSecureStorage(user);
        currentUserNotifier.value = user;
        debugPrint(
            'AuthService: Session migrated prefs → secure storage [${user.email}]');
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
      if (res['pro'] == true) {
        await prefs.setBool('pro_unlocked_${user.email.toLowerCase()}', true);
      }
      if (res['trial_used'] == true) {
        await prefs.setBool('trial_generated_${user.email.toLowerCase()}', true);
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
      await _secureStorage.write(key: _secureEmailKey, value: user.email);
      await _secureStorage.write(key: _secureDisplayKey, value: user.displayName);
      await _secureStorage.write(key: _secureIdKey, value: user.id);
      if (user.photoUrl != null) {
        await _secureStorage.write(key: _securePhotoKey, value: user.photoUrl!);
      }
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

