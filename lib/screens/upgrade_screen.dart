import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/mikrotik_service.dart';
import '../services/cloud_sync_service.dart';
import 'admin_screen.dart';
import '../widgets/gcash_payment_modal.dart';
import '../responsive.dart';

class UpgradeScreen extends StatefulWidget {
  final MikrotikService? service;
  const UpgradeScreen({super.key, this.service});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  Map<String, String>? _gcashConfig;
  bool _isMonthly = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _loadGCashSettings();
  }

  Future<void> _loadGCashSettings() async {
    final cfg = await CloudSyncService.getGCashSettings();
    if (mounted) setState(() => _gcashConfig = cfg);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _openAdminApprovalPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AdminScreen()),
    );
  }

  void _showPurchaseModal(String plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GCashPaymentModal(
        onSuccess: _showSuccessDialog,
        gcashConfig: _gcashConfig,
        service: widget.service,
        initialPlan: plan,
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9800), Color(0xFFFF5252), Color(0xFFBB86FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E2E),
              borderRadius: BorderRadius.circular(23),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.verified_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  'You\'re Pro! 🎉',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlimited voucher generation is now active. Thank you for upgrading!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white60,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'Let\'s Go! →',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthlyPrice = _gcashConfig?['monthly_price']?.isNotEmpty == true ? _gcashConfig!['monthly_price']! : '150';
    final lifetimePrice = _gcashConfig?['pro_price']?.isNotEmpty == true ? _gcashConfig!['pro_price']! : '299';
    final currentPrice = _isMonthly ? monthlyPrice : lifetimePrice;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0E0518),
      body: Responsive.constrain(Stack(
        children: [
          // Background glowing orbs
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Positioned(
              top: -100,
              left: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF9800).withValues(alpha: 0.20 * _pulseAnim.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) => Positioned(
              bottom: -100,
              right: -80,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF5252).withValues(alpha: 0.15 * _pulseAnim.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: const EdgeInsets.all(16),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          _buildToggle(),
                          if (!_isMonthly)
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Text(
                                'Pay once, enjoy forever',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFFF9800),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          if (_isMonthly) const SizedBox(height: 16),
                          
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF9800), Color(0xFFFF5252), Color(0xFFBB86FC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A0E2E),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      'RECOMMENDED',
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFFFF9800),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.poppins(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                      children: const [
                                        TextSpan(text: 'Voucher App '),
                                        TextSpan(
                                          text: 'PRO',
                                          style: TextStyle(
                                            color: Color(0xFFFF9800),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Unlock the full potential of your hotspot business with advanced voucher tools.',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 28),
                                  
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₱$currentPrice',
                                        style: GoogleFonts.poppins(
                                          fontSize: 44,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          height: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6, left: 6),
                                        child: Text(
                                          _isMonthly ? '/mo' : ' one-time',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            color: Colors.white.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_isMonthly)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'for 30 days, auto-expires after',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: Colors.white.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 32),
                                  
                                  SizedBox(
                                    width: double.infinity,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                                            blurRadius: 15,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: () => _showPurchaseModal(_isMonthly ? 'monthly' : 'lifetime'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(vertical: 18),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: Text(
                                          'Get Voucher App PRO',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 36),
                                  
                                  Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'PRO Features',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  _buildCheckFeature(
                                    'Unlimited Vouchers',
                                    'Generate as many hotspot vouchers as you need without any limits or restrictions',
                                  ),
                                  _buildCheckFeature(
                                    'Full Print Access',
                                    'Print and share voucher batches anytime directly from your phone to Bluetooth printers',
                                  ),
                                  
                                  // Admin Approval Panel
                                  if (AuthService.isCurrentUserAdmin(AuthService.instance.currentUser?.email)) ...[
                                    const SizedBox(height: 16),
                                    const Divider(color: Colors.white12, height: 1),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _openAdminApprovalPanel,
                                        icon: const Icon(Icons.admin_panel_settings_rounded,
                                            color: Color(0xFFBB86FC), size: 18),
                                        label: Text(
                                          'Admin Panel (Approve Payments)',
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFFBB86FC),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Color(0xFFBB86FC)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }

  Widget _buildToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0E2E),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isMonthly = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: _isMonthly
                      ? const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: !_isMonthly ? Colors.transparent : null,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: _isMonthly
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Monthly',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: _isMonthly ? Colors.white : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isMonthly = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: !_isMonthly
                      ? const LinearGradient(
                          colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _isMonthly ? Colors.transparent : null,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: !_isMonthly
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Lifetime',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: !_isMonthly ? Colors.white : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckFeature(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Color(0xFFFF9800), size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
