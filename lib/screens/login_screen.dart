import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../models/router_profile.dart';
import '../models/google_user.dart';
import '../services/mikrotik_service.dart';
import '../services/auth_service.dart';
import '../services/trial_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/force_update_service.dart';
import '../responsive.dart';
import 'dashboard_screen.dart';
import 'admin_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  List<RouterProfile> _savedRouters = [];
  String? _connectingRouterId;
  String? _errorMessage;

  // Inline email sign-in state
  final TextEditingController _emailCtrl = TextEditingController();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _loadSavedSettings();
    _fadeController.forward();
    _slideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ForceUpdateService.checkAndShowIfRequired(context);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> _recentAccounts = [];

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('saved_routers_v2') ?? '';
    List<RouterProfile> routers = RouterProfile.decodeList(jsonStr);

    // Migration from old single-router keys if no v2 list exists yet
    if (routers.isEmpty) {
      final oldIp = prefs.getString('router_ip');
      if (oldIp != null && oldIp.isNotEmpty) {
        final oldPort =
            int.tryParse(prefs.getString('router_port') ?? '8728') ?? 8728;
        final oldUser = prefs.getString('router_username') ?? 'admin';
        final initialProfile = RouterProfile(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: 'My Router',
          host: oldIp,
          port: oldPort,
          username: oldUser,
          password: '',
        );
        routers = [initialProfile];
        await prefs.setString(
            'saved_routers_v2', RouterProfile.encodeList(routers));
      }
    }

    final savedEmails = prefs.getStringList('recent_gmail_accounts_v1') ?? [];
    final savedAccountsV2 = prefs.getStringList('recent_gmail_accounts_v2') ?? [];
    List<Map<String, String>> accounts = [];
    if (savedAccountsV2.isNotEmpty) {
      accounts = savedAccountsV2.map((e) => Map<String, String>.from(json.decode(e))).toList();
    } else {
      accounts = savedEmails.map((e) => {'email': e, 'displayName': '', 'photoUrl': ''}).toList();
    }

    if (mounted) {
      setState(() {
        _savedRouters = routers;
        _recentAccounts = accounts;
      });
    }

    // Auto-sync missing profile pictures from cloud
    bool synced = false;
    for (int i = 0; i < accounts.length; i++) {
      final acc = accounts[i];
      if (acc['photoUrl'] == null || acc['photoUrl']!.isEmpty) {
        try {
          final data = await CloudSyncService.registerOrFetchUserAccount(acc['email']!);
          if (data['photo_url'] != null && data['photo_url'].toString().isNotEmpty) {
            accounts[i] = {
              'email': acc['email']!,
              'displayName': data['display_name'] ?? acc['displayName'] ?? '',
              'photoUrl': data['photo_url'],
            };
            synced = true;
          }
        } catch (e) {
          debugPrint('Failed to sync profile for ${acc['email']}: $e');
        }
      }
    }
    
    if (synced && mounted) {
      setState(() => _recentAccounts = accounts);
      final strList = accounts.map((e) => json.encode(e)).toList();
      await prefs.setStringList('recent_gmail_accounts_v2', strList);
    }
  }

  Future<void> _saveRecentAccount(GoogleUserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<Map<String, String>>.from(_recentAccounts);
    list.removeWhere((e) => e['email'] == user.email);
    list.insert(0, {
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoUrl ?? '',
    });
    if (mounted) setState(() => _recentAccounts = list);
    await prefs.setStringList('recent_gmail_accounts_v2', list.map((e) => json.encode(e)).toList());
  }

  Future<void> _removeSavedAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final list = List<Map<String, String>>.from(_recentAccounts);
    list.removeWhere((e) => e['email']?.toLowerCase() == email.trim().toLowerCase());
    if (mounted) setState(() => _recentAccounts = list);
    await prefs.setStringList('recent_gmail_accounts_v2', list.map((e) => json.encode(e)).toList());
  }

  Future<void> _verifyAndOpenAdminPortal() async {

    final pinCtrl = TextEditingController();
    bool isPinErr = false;

    final authenticated = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF141426),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF34A853), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Admin Verification',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter Admin PIN to open Admin Dashboard Portal:',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, letterSpacing: 6),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '••••',
                  hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 18, letterSpacing: 6),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF34A853))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF34A853))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 2)),
                ),
              ),
              if (isPinErr) ...[
                const SizedBox(height: 8),
                Text('❌ Incorrect Admin PIN', style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontSize: 11)),
              ],
            ],
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                  },
                  child: Text('Forgot PIN?', style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 12, decoration: TextDecoration.underline), textAlign: TextAlign.center),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dlgCtx, false),
                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white38)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34A853),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        final input = pinCtrl.text.trim();
                        if (input == '8888' || input == '1234') {
                          Navigator.pop(dlgCtx, true);
                        } else {
                          setDlgState(() => isPinErr = true);
                        }
                      },
                      child: Text('Open Portal', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );


    if (authenticated == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      );
    }
  }

  Future<void> _authenticateWithGoogleFlow() async {
    try {


      // 1. Authenticate with Google (returns user but does not save session yet)
      final tempUser = await AuthService.instance.authenticateWithGoogle();
      if (tempUser == null) return; // User canceled

      // 2. Fetch PIN for the authenticated email
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF))),
      );

      final email = tempUser.email;
      final existingPin = await CloudSyncService.getUserPin(email);
      
      if (mounted) Navigator.pop(context); // Close loading

      bool pinSuccess = false;
      
      if (existingPin != null && existingPin.isNotEmpty) {
        // Enter existing PIN
        pinSuccess = await _showPinEntryDialog(email, existingPin);
      } else {
        // Create new PIN
        final newPin = await _showPinCreationDialog(email);
        if (newPin != null) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF))),
          );
          final saved = await CloudSyncService.saveUserPin(email, newPin);
          if (mounted) Navigator.pop(context);
          
          if (saved) {
            pinSuccess = true;
          } else {
          }
        }
      }

      if (!pinSuccess) return; // User cancelled or failed PIN

      // 3. Finalize Sign In
      await _saveRecentAccount(tempUser);
      await AuthService.instance.completeSignIn(tempUser);

      // SnackBar removed per request

    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Future<String?> _showManualEmailInputDialog() async {
    final ctrl = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141426),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('PC Sign In', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Google Sign-In is not natively supported on Windows. Please enter your email manually to sign in and sync with the cloud.', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'your.email@gmail.com',
                hintStyle: GoogleFonts.poppins(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34A853),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Continue', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getReadableErrorMessage(Object e) {
    String error = e.toString();
    if (error.contains('network_error') || error.contains('network-request-failed') || error.contains('SocketException')) {
      return 'Network error. Please check your internet connection.';
    } else if (error.contains('invalid-credential') || error.contains('wrong-password') || error.contains('user-not-found')) {
      return 'Invalid email or password.';
    } else if (error.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    } else if (error.contains(']')) {
      return error.split(']').last.trim();
    } else if (error.startsWith('Exception: ')) {
      return error.substring(11).trim();
    }
    return error;
  }

  Future<void> _authenticateEmailFlow(String email) async {
    // 1. Show loading indicator overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF))),
    );

    // 2. Fetch PIN
    final existingPin = await CloudSyncService.getUserPin(email);
    
    // Close loading
    if (mounted) Navigator.pop(context);

    bool pinSuccess = false;
    
    if (existingPin != null && existingPin.isNotEmpty) {
      // Enter existing PIN
      pinSuccess = await _showPinEntryDialog(email, existingPin);
    } else {
      // Create new PIN
      final newPin = await _showPinCreationDialog(email);
      if (newPin != null) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF))),
        );
        final saved = await CloudSyncService.saveUserPin(email, newPin);
        if (mounted) Navigator.pop(context);
        
        if (saved) {
          pinSuccess = true;
        } else {
        }
      }
    }

    if (!pinSuccess) return;

    // 3. Log in!
    try {
      final savedAcc = _recentAccounts.firstWhere(
        (acc) => acc['email'] == email, 
        orElse: () => {'email': email}
      );
      final displayName = savedAcc['displayName'];
      final photoUrl = savedAcc['photoUrl'];

      final user = await AuthService.instance.signInWithCustomEmail(
        email: email,
        displayName: displayName?.isNotEmpty == true ? displayName : null,
        photoUrl: photoUrl?.isNotEmpty == true ? photoUrl : null,
      );
      await _saveRecentAccount(user);
      // SnackBar removed per request
    } catch (e) {
      // Ignore login errors
    }
  }

  Future<bool> _showPinEntryDialog(String email, String actualPin) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dlgCtx) {
        String pin = '';
        bool isError = false;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void onKey(String digit) {
              if (pin.length < 4) {
                setState(() {
                  pin += digit;
                  isError = false;
                });
                if (pin.length == 4) {
                  // Auto-submit
                  final nav = Navigator.of(dlgCtx);
                  Future.delayed(const Duration(milliseconds: 150), () {
                    if (pin == actualPin) {
                      nav.pop(true);
                    } else {
                      setState(() { pin = ''; isError = true; });
                    }
                  });
                }
              }
            }
            void onDelete() => setState(() { if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1); isError = false; });

            return _PinBottomSheet(
              title: 'Enter PIN',
              subtitle: email,
              icon: Icons.lock_rounded,
              iconColor: const Color(0xFF00BFFF),
              pin: pin,
              isError: isError,
              errorText: '❌ Incorrect PIN. Try again.',
              onKey: onKey,
              onDelete: onDelete,
              onCancel: () => Navigator.pop(dlgCtx, false),
              actionLabel: null, // auto-submit on 4 digits
            );
          },
        );
      },
    ) ?? false;
  }

  Future<String?> _showPinCreationDialog(String email) async {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (dlgCtx) {
        String pin = '';
        bool isError = false;
        return StatefulBuilder(
          builder: (ctx, setState) {
            void onKey(String digit) {
              if (pin.length < 4) {
                setState(() { pin += digit; isError = false; });
              }
            }
            void onDelete() => setState(() { if (pin.isNotEmpty) pin = pin.substring(0, pin.length - 1); isError = false; });

            return _PinBottomSheet(
              title: 'Create PIN',
              subtitle: 'Secure your account\n$email',
              icon: Icons.shield_rounded,
              iconColor: const Color(0xFF34A853),
              pin: pin,
              isError: isError,
              errorText: '⚠️ Enter exactly 4 digits',
              onKey: onKey,
              onDelete: onDelete,
              onCancel: () => Navigator.pop(dlgCtx, null),
              actionLabel: 'Save PIN',
              onConfirm: () {
                if (pin.length == 4) {
                  Navigator.pop(dlgCtx, pin);
                } else {
                  setState(() => isError = true);
                }
              },
            );
          },
        );
      },
    );
  }




  Future<void> _saveRouterList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_routers_v2', RouterProfile.encodeList(_savedRouters));
  }

  Future<void> _deleteRouter(RouterProfile router) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Router',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${router.name}" (${router.host})?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _savedRouters.removeWhere((r) => r.id == router.id);
      });
      await _saveRouterList();
    }
  }

  // ── Gmail Authentication Logic & UI Widget ────────────────────────────────
  Widget _buildGoogleAuthCard() {
    return ValueListenableBuilder<GoogleUserModel?>(
      valueListenable: AuthService.instance.currentUserNotifier,
      builder: (context, user, _) {
        if (user != null) {
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0D2B1A),
                  Color(0xFF0A1F14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF34A853).withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF34A853).withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Avatar with glow ring
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF34A853), Color(0xFF00C853)],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF1E3A28),
                    backgroundImage: user.photoUrl != null
                        ? NetworkImage(user.photoUrl!)
                        : null,
                    child: user.photoUrl == null
                        ? Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : 'G',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.displayName,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          FutureBuilder<bool>(
                            future: TrialService.isTrialLocked(user.email),
                            builder: (context, snapshot) {
                              final isLocked = snapshot.data ?? false;
                              return FutureBuilder<bool>(
                                future: TrialService.isPro(user.email),
                                builder: (context, proSnapshot) {
                                  final isPro = proSnapshot.data ?? false;
                                  String label = '1 Free Trial';
                                  Color color = const Color(0xFF00BFFF);
                                  IconData icon = Icons.card_giftcard_rounded;

                                  if (AuthService.isAdmin(user.email)) {
                                    label = 'ADMIN 👑';
                                    color = const Color(0xFFFFD700);
                                    icon = Icons.admin_panel_settings_rounded;
                                  } else if (isPro) {
                                    label = 'PRO ⚡';
                                    color = const Color(0xFF34A853);
                                    icon = Icons.verified_rounded;
                                  } else if (isLocked) {
                                    label = 'Trial Used';
                                    color = const Color(0xFFFF9800);
                                    icon = Icons.lock_clock_rounded;
                                  }


                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: color.withValues(alpha: 0.6),
                                          width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 11, color: color),
                                        const SizedBox(width: 3),
                                        Text(
                                          label,
                                          style: GoogleFonts.poppins(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Admin Panel Button (ONLY for Admin users)
                if (AuthService.isAdmin(user.email))
                  GestureDetector(
                    onTap: _verifyAndOpenAdminPortal,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                            width: 0.8),
                      ),
                      child: const Icon(Icons.shield_rounded,
                          color: Color(0xFFFFD700), size: 18),
                    ),
                  ),



                // Logout Icon
                GestureDetector(
                  onTap: _handleGoogleSignOut,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                          width: 0.8),
                    ),
                    child: const Icon(Icons.logout_rounded,
                        color: Color(0xFFFF5252), size: 18),
                  ),
                ),

              ],
            ),
          );
        }

        // -- Not signed in: Email Sign-In card & 1-Tap accounts --
        return _buildEmailSignInCard();
      },
    );
  }

  Widget _buildEmailSignInCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1-Tap Saved Accounts (if any)
        if (_recentAccounts.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  size: 13, color: Color(0xFF00BFFF)),
              const SizedBox(width: 6),
              Text(
                'SAVED ACCOUNTS (1-TAP SIGN IN)',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF00BFFF),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._recentAccounts.map((acc) {
            final email = acc['email'] ?? '';
            final name = acc['displayName'] ?? '';
            final photoUrl = acc['photoUrl'] ?? '';
            final initial = name.isNotEmpty ? name[0].toUpperCase() : (email.isNotEmpty ? email[0].toUpperCase() : 'G');
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _authenticateEmailFlow(email),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  image: photoUrl.isNotEmpty ? DecorationImage(
                                    image: NetworkImage(photoUrl),
                                    fit: BoxFit.cover,
                                  ) : null,
                                ),
                                alignment: Alignment.center,
                                child: photoUrl.isEmpty ? Text(
                                  initial,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Tap to sign in & sync',
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: const Color(0xFF34A853),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.bolt_rounded,
                                  size: 18, color: Color(0xFF34A853)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Delete account button
                    GestureDetector(
                      onTap: () => _removeSavedAccount(email),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.transparent,
                        child: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.white38,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
        ],

        // Premium Sign In — Continue with Google
        PremiumGoogleButton(
          onTap: _authenticateWithGoogleFlow,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Secured with Google  Cloud Synced',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.white38,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }


  Future<void> _handleGoogleSignOut() async {
    await AuthService.instance.signOut();
    if (mounted) {
    }
  }

  // ── Open Pop-Up Modal to Add or Edit Router ───────────────────────────
  void _openRouterCredentialsModal({RouterProfile? routerToEdit}) {
    if (!AuthService.instance.isSignedIn) {
      return;
    }
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(
      text: routerToEdit?.name ?? 'Router ${_savedRouters.length + 1}',
    );
    final ipCtrl = TextEditingController(text: routerToEdit?.host ?? '');
    final portCtrl =
        TextEditingController(text: routerToEdit?.port.toString() ?? '8728');
    final usernameCtrl =
        TextEditingController(text: routerToEdit?.username ?? 'admin');
    final passwordCtrl =
        TextEditingController(text: routerToEdit?.password ?? '');

    bool obscurePassword = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF141426),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(
                  top: BorderSide(color: Color(0xFF00BFFF), width: 1.5),
                ),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Modal Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00BFFF),
                                      Color(0xFF7B2FBE)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.router_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                routerToEdit != null
                                    ? 'Edit Router Credentials'
                                    : 'Add Router Credentials',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Router Name / Alias
                      _buildModalField(
                        controller: nameCtrl,
                        label: 'Router Name / Alias',
                        hint: 'e.g. haplite, Main Router',
                        icon: Icons.label_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Router IP + Port
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildModalField(
                              controller: ipCtrl,
                              label: 'Router IP / Host',
                              hint: '192.168.8.38',
                              icon: Icons.language_rounded,
                              keyboardType: TextInputType.text,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _buildModalField(
                              controller: portCtrl,
                              label: 'Port',
                              hint: '8728',
                              icon: Icons.settings_ethernet_rounded,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Username
                      _buildModalField(
                        controller: usernameCtrl,
                        label: 'Username',
                        hint: 'admin',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Password
                      _buildModalField(
                        controller: passwordCtrl,
                        label: 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        obscureText: obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onPressed: () => setModalState(
                              () => obscurePassword = !obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;

                            final name = nameCtrl.text.trim();
                            final host = ipCtrl.text.trim();
                            final port =
                                int.tryParse(portCtrl.text.trim()) ?? 8728;
                            final user = usernameCtrl.text.trim();
                            final pass = passwordCtrl.text;

                            if (routerToEdit != null) {
                              final idx = _savedRouters.indexWhere(
                                  (r) => r.id == routerToEdit.id);
                              if (idx >= 0) {
                                _savedRouters[idx] = _savedRouters[idx].copyWith(
                                  name: name,
                                  host: host,
                                  port: port,
                                  username: user,
                                  password: pass,
                                );
                              }
                            } else {
                              final newProfile = RouterProfile(
                                id: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                name: name,
                                host: host,
                                port: port,
                                username: user,
                                password: pass,
                              );
                              _savedRouters.add(newProfile);
                            }

                            await _saveRouterList();
                            setState(() {});
                            if (!context.mounted) return;
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.check_rounded, color: Colors.white),
                          label: Text(
                            'Save Router Profile',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Connect directly to MikroTik router profile ───────────────────────────
  Future<void> _connectToRouter(RouterProfile router) async {
    if (!AuthService.instance.isSignedIn) {
      return;
    }
    setState(() {
      _connectingRouterId = router.id;
      _errorMessage = null;
    });

    final service = MikrotikService(
      host: router.host,
      port: router.port,
      username: router.username,
      password: router.password,
    );

    try {
      await service.connect();
      await service.login();

      // Update lastConnected date
      final idx = _savedRouters.indexWhere((r) => r.id == router.id);
      if (idx >= 0) {
        _savedRouters[idx] = _savedRouters[idx].copyWith(
          lastConnected: DateTime.now(),
        );
        await _saveRouterList();
      }

      // Legacy key update
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('router_ip', router.host);
      await prefs.setString('router_port', router.port.toString());
      await prefs.setString('router_username', router.username);

      if (!mounted) return;
      setState(() {
        _connectingRouterId = null;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(service: service),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectingRouterId = null;
        _errorMessage =
            'Failed to connect to "${router.name}": ${_getReadableErrorMessage(e)}';
      });
      await service.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060612),
      body: Stack(
        children: [
          // -- Background blobs --
          Positioned(top: -120, right: -80,
              child: _blob(320, const Color(0xFF00BFFF), 0.09)),
          Positioned(top: 260, left: -100,
              child: _blob(260, const Color(0xFF7B2FBE), 0.10)),
          Positioned(bottom: -60, right: -60,
              child: _blob(220, const Color(0xFF4285F4), 0.07)),
          Positioned(bottom: 120, left: -40,
              child: _blob(160, const Color(0xFF34A853), 0.06)),

          // -- Content --
          SafeArea(
            child: Responsive.constrain(
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // -- HERO BANNER --
                        _buildHeroHeader(),

                        // -- SIGN-IN CARD --
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: _buildGoogleAuthCard(),
                        ),

                        // -- ROUTER SECTION --
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ValueListenableBuilder<GoogleUserModel?>(
                            valueListenable:
                                AuthService.instance.currentUserNotifier,
                            builder: (context, googleUser, _) {
                              if (googleUser == null) {
                                return _buildLockedState();
                              }
                              return _buildRouterSection();
                            },
                          ),
                        ),

                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildFooter(),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Background blob helper ────────────────────────────────────────────────
  Widget _blob(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }

  // -- Hero Banner (full-width gradient top card) --
  Widget _buildHeroHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      child: Column(
        children: [
          // Glowing icon
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFF7B2FBE).withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(3, 7),
                ),
              ],
            ),
            child: const Icon(Icons.router_rounded, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 18),

          // App title
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF00BFFF), Color(0xFFBB86FC), Color(0xFF00BFFF)],
              stops: [0.0, 0.5, 1.0],
            ).createShader(bounds),
            child: Text(
              'Voucher App',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 4),

          Text(
            'MikroTik Hotspot Manager  •  by Jc',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.white38,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),

          // Feature chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _heroPill(Icons.confirmation_number_rounded, 'Vouchers'),
              const SizedBox(width: 8),
              _heroPill(Icons.router_rounded, 'MikroTik'),
              const SizedBox(width: 8),
              _heroPill(Icons.cloud_done_rounded, 'Cloud Sync'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFF00BFFF).withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF00BFFF)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.white60,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF00BFFF)),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF00BFFF),
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 0.6,
            color: const Color(0xFF00BFFF).withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }

  // -- Locked state when not signed in --
  Widget _buildLockedState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: Color(0xFF4285F4), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Router Access Locked',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Sign in above to manage routers',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _lockedFeatureTile(
                  Icons.router_rounded, 'Routers', 'Add & manage')),
              const SizedBox(width: 8),
              Expanded(child: _lockedFeatureTile(
                  Icons.confirmation_number_rounded, 'Vouchers', 'Generate')),
              const SizedBox(width: 8),
              Expanded(child: _lockedFeatureTile(
                  Icons.analytics_rounded, 'Stats', 'Live data')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lockedFeatureTile(IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF00BFFF)),
          const SizedBox(height: 5),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          Text(
            sub,
            style: GoogleFonts.poppins(
              fontSize: 9,
              color: Colors.white30,
            ),
          ),
        ],
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Router section (visible only when signed in) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildRouterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),

        // Section label + Add button
        Row(
          children: [
            Expanded(
              child: _sectionLabel(
                  'Routers (${_savedRouters.length})', Icons.dns_rounded),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => _openRouterCredentialsModal(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00BFFF), Color(0xFF0077FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'Add',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Error banner
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF2A0808),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFFF5252), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFFFF6B6B),
                      height: 1.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _errorMessage = null),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white38),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Empty state
        if (_savedRouters.isEmpty)
          _buildEmptyRouterState()
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _savedRouters.length,
            itemBuilder: (context, index) {
              final router = _savedRouters[index];
              final isConnecting = _connectingRouterId == router.id;
              return _buildRouterCard(router, isConnecting);
            },
          ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Empty router state Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildEmptyRouterState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00BFFF).withValues(alpha: 0.08),
              border: Border.all(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.2),
                  width: 1),
            ),
            child: const Icon(
              Icons.router_outlined,
              color: Color(0xFF00BFFF),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Routers Added Yet',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Add" to register your MikroTik router credentials.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white38,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _openRouterCredentialsModal(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00BFFF), Color(0xFF0077FF)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Add Your First Router',
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Router card ───────────────────────────────────────────────────────────
  Widget _buildRouterCard(RouterProfile router, bool isConnecting) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isConnecting
              ? const Color(0xFF00BFFF).withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.08),
          width: isConnecting ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnecting
                ? const Color(0xFF00BFFF).withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: isConnecting ? 20 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: isConnecting ? null : () => _connectToRouter(router),
          borderRadius: BorderRadius.circular(22),
          splashColor: const Color(0xFF00BFFF).withValues(alpha: 0.08),
          highlightColor: const Color(0xFF00BFFF).withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00BFFF), Color(0xFF0057FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.router_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        router.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.language_rounded,
                              size: 12, color: Color(0xFF00BFFF)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${router.host}:${router.port}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: Colors.white60,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              size: 12, color: Colors.white30),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              router.username,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Actions
                if (isConnecting)
                  const SpinKitRing(
                    color: Color(0xFF00BFFF),
                    size: 24,
                    lineWidth: 2.5,
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _iconBtn(Icons.edit_outlined, Colors.white54,
                          () => _openRouterCredentialsModal(routerToEdit: router)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.delete_outline_rounded,
                          const Color(0xFFFF5252).withValues(alpha: 0.8),
                          () => _deleteRouter(router)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: Color(0xFF00BFFF)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Center(
      child: Column(
        children: [
          Container(
            height: 0.6,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 14),
          Text(
            'Voucher App v1.0.1 •  MikroTik API',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              color: Colors.white24,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Helper Modal TextField ────────────────────────────────────────────────
  Widget _buildModalField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: Colors.white24,
              fontSize: 13.5,
            ),
            prefixIcon: Icon(icon, color: Colors.white38, size: 17),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFF00BFFF), width: 1.2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFF5252),
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFF5252),
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            errorStyle: GoogleFonts.poppins(
              fontSize: 10.5,
              color: const Color(0xFFFF5252),
            ),
          ),
        ),
      ],
    );
  }
}


// ── Shared PIN UI Bottom Sheet ────────────────────────────────────────────

class _PinBottomSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final String pin;
  final bool isError;
  final String errorText;
  final void Function(String) onKey;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final String? actionLabel;
  final VoidCallback? onConfirm;

  const _PinBottomSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.pin,
    required this.isError,
    required this.errorText,
    required this.onKey,
    required this.onDelete,
    required this.onCancel,
    required this.actionLabel,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        top: 20,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Icon bubble
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.12),
              border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 1.5),
            ),
            child: Icon(icon, color: iconColor, size: 30),
          ),
          const SizedBox(height: 16),

          // Title
          Text(
            title,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle (email)
          Text(
            subtitle,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 28),

          // 4 digit boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final filled = i < pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 54,
                height: 58,
                decoration: BoxDecoration(
                  color: filled
                      ? (isError ? const Color(0xFFFF5252).withValues(alpha: 0.15) : iconColor.withValues(alpha: 0.12))
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: filled
                        ? (isError ? const Color(0xFFFF5252) : iconColor)
                        : Colors.white.withValues(alpha: 0.15),
                    width: filled ? 2 : 1.5,
                  ),
                ),
                child: Center(
                  child: filled
                      ? Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isError ? const Color(0xFFFF5252) : iconColor,
                          ),
                        )
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Error message
          AnimatedOpacity(
            opacity: isError ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Text(
              errorText,
              style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),

          // Keypad
          _buildKeypad(),
          const SizedBox(height: 16),

          // Bottom action row
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 14)),
                ),
              ),
              if (actionLabel != null && onConfirm != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(actionLabel!, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
      ['','0','O'],
    ];
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((k) {
              if (k.isEmpty) return const SizedBox(width: 78, height: 56);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: InkWell(
                  onTap: () => k == 'O' ? onDelete() : onKey(k),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 78,
                    height: 56,
                    decoration: BoxDecoration(
                      color: k == 'O'
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Center(
                      child: k == 'O'
                          ? const Icon(Icons.backspace_outlined, color: Colors.white54, size: 20)
                          : Text(
                              k,
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
class PremiumGoogleButton extends StatefulWidget {
  final VoidCallback onTap;

  const PremiumGoogleButton({super.key, required this.onTap});

  @override
  State<PremiumGoogleButton> createState() => _PremiumGoogleButtonState();
}

class _PremiumGoogleButtonState extends State<PremiumGoogleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (isHighlighted) {
            if (isHighlighted) {
              _controller.forward();
            } else {
              _controller.reverse();
            }
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161625), // Premium dark background
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08), // Subtle glassmorphism border
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) {
                    return const SweepGradient(
                      center: Alignment.center,
                      startAngle: 0.0,
                      endAngle: 6.28,
                      colors: [
                        Color(0xFF4285F4),
                        Color(0xFF34A853),
                        Color(0xFFFBBC05),
                        Color(0xFFEA4335),
                        Color(0xFF4285F4),
                      ],
                      stops: [0.0, 0.25, 0.5, 0.75, 1.0],
                    ).createShader(bounds);
                  },
                  child: Text(
                    'G',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continue with Google',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
