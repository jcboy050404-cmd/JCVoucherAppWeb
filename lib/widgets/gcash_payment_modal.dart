import 'dart:async';
import '../widgets/top_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/mikrotik_service.dart';
import '../services/trial_service.dart';

class GCashPaymentModal extends StatefulWidget {
  final Map<String, String>? gcashConfig;
  final MikrotikService? service;
  final VoidCallback onSuccess;
  final String initialPlan;

  const GCashPaymentModal({
    super.key,
    required this.gcashConfig,
    required this.service,
    required this.onSuccess,
    this.initialPlan = 'monthly',
  });

  @override
  State<GCashPaymentModal> createState() => _GCashPaymentModalState();
}

class _GCashPaymentModalState extends State<GCashPaymentModal> {
  final TextEditingController _refCtrl = TextEditingController();
  bool _isSubmittingGCash = false;
  Map<String, dynamic>? _userPendingReq;
  bool _isCheckingPendingReq = false;
  Uint8List? _qrBytes;
  late String _selectedPlan;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.initialPlan;
    _checkUserGCashPaymentStatus();
    
    final qrUrl = widget.gcashConfig?['qr_image_url'] ?? '';
    if (qrUrl.startsWith('data:image')) {
      try {
        final b64 = qrUrl.split(',').last;
        _qrBytes = base64Decode(b64);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _downloadQR(String qrUrl) async {
    try {
      Uint8List bytes;
      if (qrUrl.startsWith('data:image')) {
        final b64 = qrUrl.split(',').last;
        bytes = base64Decode(b64);
      } else {
        final res = await http.get(Uri.parse(qrUrl));
        bytes = res.bodyBytes;
      }
      final xfile = XFile.fromData(bytes, mimeType: 'image/png', name: 'gcash_qr.png');
      await Share.shareXFiles([xfile], text: 'GCash QR Code');
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Failed to share QR: $e');
    }
  }

  Future<void> _checkUserGCashPaymentStatus() async {
    final email = AuthService.instance.currentUser?.email;
    if (email == null || email.isEmpty) return;

    setState(() => _isCheckingPendingReq = true);
    try {
      final req = await CloudSyncService.getUserPaymentRequest(email);
      if (!mounted) return;
      if (req != null) {
        final status = req['status'];
        if (status == 'approved') {
          // Admin approved! Unlock PRO immediately
          await TrialService.unlockPro(email, widget.service);
          if (!mounted) return;
          Navigator.pop(context);
          widget.onSuccess();
        } else {
          setState(() {
            _userPendingReq = req;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isCheckingPendingReq = false);
    }
  }

  Future<void> _submitGCashReference() async {
    final email = AuthService.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      TopToast.show(context, 'Please sign in with email first.');
      return;
    }

    final refNo = _refCtrl.text.trim();
    if (refNo.isEmpty || refNo.length < 9) {
      TopToast.show(context, 'Please enter a valid GCash Reference Number (e.g. 100293847561)', backgroundColor: Color(0xFFFF5252));
      return;
    }

    setState(() => _isSubmittingGCash = true);
    try {
      final monthlyPrice = widget.gcashConfig?['monthly_price']?.isNotEmpty == true ? widget.gcashConfig!['monthly_price']! : '150';
      final proPrice = widget.gcashConfig?['pro_price']?.isNotEmpty == true ? widget.gcashConfig!['pro_price']! : '299';
      
      final priceStr = _selectedPlan == 'monthly' ? monthlyPrice : proPrice;
      final amount = double.tryParse(priceStr) ?? 1.00;

      final success = await CloudSyncService.submitPaymentRequest(
        email: email,
        refNumber: refNo,
        amount: amount,
        plan: _selectedPlan,
      );

      if (!mounted) return;
      if (success) {
        _refCtrl.clear();
        TopToast.show(context, '🎉 GCash Payment Submitted! Waiting for Admin Approval.', backgroundColor: Color(0xFF34A853));
        await _checkUserGCashPaymentStatus();
      } else {
        TopToast.show(context, 'Failed to submit payment request. Please try again.', backgroundColor: Color(0xFFFF5252));
      }
    } catch (e) {
      if (mounted) {
        TopToast.show(context, 'Error: $e', backgroundColor: const Color(0xFFFF5252));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingGCash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.gcashConfig ?? {};
    final gcashNum = cfg['gcash_number'] ?? '';
    final accountName = cfg['account_name'] ?? '';
    final qrUrl = cfg['qr_image_url'] ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A0E2E), // Deep Purple Background
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pay via Personal GCash QR',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '0% Transaction Fee • Admin Approval',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (_userPendingReq != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const SpinKitThreeBounce(
                      color: Color(0xFFFF9800),
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Pending Approval',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Ref #: ${_userPendingReq!['ref_number']}',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFFF9800),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isCheckingPendingReq
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFF9800),
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, color: Color(0xFFFF9800), size: 18),
                      onPressed: _checkUserGCashPaymentStatus,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (qrUrl.isNotEmpty) ...[
              Center(
                child: Column(
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 220),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _qrBytes != null
                            ? Image.memory(
                                _qrBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              )
                            : (qrUrl.isNotEmpty && !qrUrl.startsWith('data:image'))
                                ? Image.network(
                                    qrUrl,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 140,
                                      color: Color(0xFF141428),
                                    ),
                                  )
                                : const Icon(
                                    Icons.qr_code_2_rounded,
                                    size: 140,
                                    color: Color(0xFF141428),
                                  ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _downloadQR(qrUrl),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        'Save / Share QR',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF9800),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (gcashNum.isNotEmpty || accountName.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, color: Color(0xFFFF9800), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (accountName.isNotEmpty)
                            Text(
                              accountName,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          if (gcashNum.isNotEmpty)
                            Text(
                              'GCash #: $gcashNum',
                              style: GoogleFonts.poppins(
                                color: const Color(0xFFFF9800),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (gcashNum.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFFFF9800), size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: gcashNum));
                          TopToast.show(context, 'Copied GCash Number: $gcashNum', backgroundColor: const Color(0xFFFF9800));
                        },
                        tooltip: 'Copy Number',
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Text(
              'Select Plan',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _PlanOption(
                    title: 'Monthly',
                    price: 'PHP ${cfg['monthly_price']?.isNotEmpty == true ? cfg['monthly_price'] : '150'}',
                    isSelected: _selectedPlan == 'monthly',
                    onTap: () => setState(() => _selectedPlan = 'monthly'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlanOption(
                    title: 'Lifetime PRO',
                    price: 'PHP ${cfg['pro_price']?.isNotEmpty == true ? cfg['pro_price'] : '299'}',
                    isSelected: _selectedPlan == 'lifetime',
                    onTap: () => setState(() => _selectedPlan = 'lifetime'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '1. Send the selected amount to GCash.\n2. Enter the 13-digit Reference Number below:',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _refCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. 100293847561',
                hintStyle: GoogleFonts.poppins(color: Colors.white30, fontSize: 12.5),
                prefixIcon: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFF9800), size: 18),
                fillColor: Colors.black.withValues(alpha: 0.3),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFFF9800),
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isSubmittingGCash ? null : _submitGCashReference,
                  icon: _isSubmittingGCash
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                  label: Text(
                    'Submit for Admin Approval',
                    style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  final String title;
  final String price;
  final bool isSelected;
  final VoidCallback onTap;

  const _PlanOption({
    required this.title,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF9800).withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF9800) : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFFFF9800) : Colors.white70,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
