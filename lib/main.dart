import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/force_update_service.dart';

/// Global route observer used by list/dashboard screens to auto-refresh their
/// data when they become the active route again (e.g. after generating
/// vouchers and pressing back). Screens opt in by subscribing as RouteAware.
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow all orientations so the app is usable on phones and tablets,
  // in both portrait and landscape.
  SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0D1A),
    ),
  );
  runApp(const VoucherApp());
}

class VoucherApp extends StatelessWidget {
  const VoucherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoucherApp – MikroTik Manager',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00BFFF),
          secondary: Color(0xFF7B2FBE),
          surface: Color(0xFF1A1A2E),
          error: Color(0xFFFF5252),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(
          ThemeData.dark().textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D1A),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const AppStartup(),
    );
  }
}

/// Startup widget: restores Gmail session from secure storage before showing
/// the login screen. This means users never need to re-type their Gmail after
/// reinstalling the app — the session is stored in Android Keystore.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    // Restore Gmail session from secure storage (survives uninstall).
    // AuthService writes to Android Keystore, so the email persists.
    await AuthService.instance.init();

    if (!mounted) return;

    // Force-update check: if the installed app version is below the
    // admin-published latest_version, show a mandatory non-dismissible dialog
    // and stop here — the user must update before reaching the login screen.
    // checkAndShowIfRequired is fail-open: any backend/network error simply
    // lets the user proceed rather than locking them out.
    final blocked = await ForceUpdateService.checkAndShowIfRequired(context);
    if (blocked) return;

    // Navigate to LoginScreen. The Gmail card will already show the restored
    // account — user only needs to tap a router to connect.
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context2, anim, anim2) => const LoginScreen(),
          transitionsBuilder: (context2, animation, anim2, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Splash screen while restoring session
    return Scaffold(
      backgroundColor: const Color(0xFF060612),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App logo / icon placeholder
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.router_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'VoucherApp',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'MikroTik Hotspot Manager',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 36),
            const SpinKitThreeBounce(
              color: Color(0xFF00BFFF),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

