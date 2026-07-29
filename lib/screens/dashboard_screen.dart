import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:math';
import '../main.dart';
import '../services/mikrotik_service.dart';
import '../services/trial_service.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/force_update_service.dart';
import '../models/voucher.dart';
import '../responsive.dart';
import '../widgets/stat_card.dart';
import '../widgets/vendo_monitor_card.dart';
import '../models/router_profile.dart';
import 'generate_screen.dart';
import 'voucher_list_screen.dart';
import 'profile_list_screen.dart';
import 'script_list_screen.dart';
import 'active_vouchers_screen.dart';
import 'login_screen.dart';
import 'upgrade_screen.dart';
import 'pppoe_screen.dart';
import 'file_explorer_screen.dart';
import '../widgets/top_toast.dart';
import '../widgets/print_preview_helper.dart';
import '../widgets/responsive_layout.dart';

class DashboardScreen extends StatefulWidget {
  final MikrotikService service;
  const DashboardScreen({super.key, required this.service});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, RouteAware {
  bool _loading = true;
  bool _isLoadingData = false;
  List<Voucher> _vouchers = [];
  List<HotspotActive> _activeSessions = [];
  String? _error;
  bool _trialLocked = false;
  bool _isPro = false;
  String? _proExpiresAt;
  bool _fileManagerUnlocked = false;

  Timer? _trafficTimer;
  String? _monitoredInterface;
  List<FlSpot> _rxSpots = [];
  List<FlSpot> _txSpots = [];
  double _timeCounter = 0;
  double _maxTrafficY = 10.0;
  Map<String, String>? _systemResource;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  
  int _desktopSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
    // Re-run the force-update check after login. This catches the case where
    // an admin publishes a new required version while the app is already
    // backgrounded between launches. The check is fail-open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ForceUpdateService.checkAndShowIfRequired(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _fadeCtrl.dispose();
    _trafficTimer?.cancel();
    super.dispose();
  }

  @override
  void didPopNext() {
    // A child screen (Generate, Voucher list, etc.) was popped — refresh
    // stats so newly created vouchers are reflected immediately.
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isLoadingData) return;
    _isLoadingData = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vouchers = await widget.service.getVouchers();
      final activeSessions = await widget.service.getActiveSessions(vouchers);
      final currentUserEmail = AuthService.instance.currentUser?.email;
      await TrialService.syncWithCloud(currentUserEmail, widget.service);
      final trialLocked = await TrialService.isTrialLocked(currentUserEmail, widget.service);
      final isPro = await TrialService.isPro(currentUserEmail);
      final proExpiresAt = await TrialService.getProExpiration(currentUserEmail);
      final settings = await CloudSyncService.getGlobalSettings();
      
      final sysRes = await widget.service.getResourceInfo();
      final interfaces = await widget.service.getInterfaces();
      if (!mounted) return;
      setState(() {
        _vouchers = vouchers;
        _activeSessions = activeSessions;
        _trialLocked = trialLocked;
        _isPro = isPro;
        _proExpiresAt = proExpiresAt;
        _fileManagerUnlocked = settings['file_manager_unlocked'] == true;
        _systemResource = sysRes;
        _loading = false;
      });
      _fadeCtrl.forward(from: 0);
      
      _startTrafficMonitoring(interfaces);

      if (currentUserEmail != null) {
        final prefs = await SharedPreferences.getInstance();
        final seenKey = 'seen_pro_popup_$currentUserEmail';
        if (isPro) {
          if (prefs.getBool(seenKey) != true) {
            await prefs.setBool(seenKey, true);
            if (mounted) {
              _showProWelcomePopup();
            }
          }
        } else {
          await prefs.remove(seenKey);
          final expiredKey = 'just_expired_$currentUserEmail';
          if (prefs.getBool(expiredKey) == true) {
            await prefs.remove(expiredKey);
            if (mounted) {
              _showProExpiredPopup();
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    } finally {
      _isLoadingData = false;
    }
  }

  void _startTrafficMonitoring(List<String> interfaces) {
    if (interfaces.isEmpty) return;
    _monitoredInterface = interfaces.first;
    _trafficTimer?.cancel();
    _trafficTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final traffic = await widget.service.getTraffic(_monitoredInterface!);
        final sysRes = await widget.service.getResourceInfo();
        final rxStr = traffic['rx-bits-per-second'] ?? '0';
        final txStr = traffic['tx-bits-per-second'] ?? '0';
        final rxMbps = double.parse(rxStr) / 1000000;
        final txMbps = double.parse(txStr) / 1000000;

        if (mounted) {
          setState(() {
            _systemResource = sysRes;
            _timeCounter += 1;
            _rxSpots.add(FlSpot(_timeCounter, rxMbps));
            _txSpots.add(FlSpot(_timeCounter, txMbps));
            
            if (_rxSpots.length > 20) {
              _rxSpots.removeAt(0);
              _txSpots.removeAt(0);
            }
            
            final maxRx = _rxSpots.isEmpty ? 0.0 : _rxSpots.map((e) => e.y).reduce(max);
            final maxTx = _txSpots.isEmpty ? 0.0 : _txSpots.map((e) => e.y).reduce(max);
            _maxTrafficY = max(10.0, max(maxRx, maxTx) * 1.2);
          });
        }
      } catch (e) {
        // Ignore polling errors
      }
    });
  }

  String _formatExpDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _disconnect() async {
    await widget.service.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  int get _totalVouchers => _vouchers.length;
  int get _activeCount => _activeSessions.length;
  int get _usedCount => _vouchers.where((v) => v.isUsed).length;
  int get _availableCount => _vouchers.where((v) => !v.isUsed && !v.disabled).length;
  int get _expiredCount => _vouchers.where((v) => v.disabled && !v.isUsed).length;

  double get _todaySales {
    final now = DateTime.now();
    return _vouchers.where((v) {
      if (!v.isUsed) return false;
      final act = v.activationDate;
      if (act == null) return false;
      return act.year == now.year &&
          act.month == now.month &&
          act.day == now.day;
    }).fold(0.0, (sum, v) => sum + v.price);
  }

  double get _monthlySales {
    final now = DateTime.now();
    return _vouchers.where((v) {
      if (!v.isUsed) return false;
      final act = v.activationDate;
      if (act == null) return false;
      return act.year == now.year &&
          act.month == now.month;
    }).fold(0.0, (sum, v) => sum + v.price);
  }

  double get _totalSales {
    return _vouchers
        .where((v) => v.isUsed)
        .fold(0.0, (sum, v) => sum + v.price);
  }


  List<String> get _availableBatches {
    final set = <String>{'all'};
    for (final v in _vouchers) {
      final bMatch = RegExp(r'Date:(\d{4}-\d{2}-\d{2})').firstMatch(v.comment);
      if (bMatch != null) {
        set.add(bMatch.group(1)!);
      } else if (v.comment.isNotEmpty) {
        final firstPart = v.comment.split('|').first.trim();
        if (firstPart.isNotEmpty) set.add(firstPart);
      }
    }
    return set.toList();
  }

  List<Voucher> _getVouchersForPrint({
    required String batch,
    required bool availableOnly,
  }) {
    return _vouchers.where((v) {
      if (availableOnly && (v.isUsed || v.disabled)) return false;

      if (batch != 'all') {
        final bMatch = RegExp(r'Date:(\d{4}-\d{2}-\d{2})').firstMatch(v.comment);
        final bLabel = bMatch != null
            ? bMatch.group(1)!
            : (v.comment.isNotEmpty ? v.comment.split('|').first.trim() : 'No Batch');
        if (bLabel != batch) return false;
      }

      return true;
    }).toList();
  }

  Widget _buildPrintFilterLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
  }

  /// Responsive grid for stat cards: 2 columns on phones, more on tablets.
  Widget _statGrid(List<Widget> children) {
    final cols = Responsive(context).gridColumns(itemWidth: 320);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: cols > 2 ? 1.15 : 1.25,
      children: children,
    );
  }

  void _showPrintOptionsModal() {
    String selBatch = 'all';
    bool availableOnly = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final targetVouchers = _getVouchersForPrint(
              batch: selBatch,
              availableOnly: availableOnly,
            );

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF161626),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                  width: 1.5,
                ),
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
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BFFF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.print_rounded,
                            color: Color(0xFF00BFFF),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Print Vouchers',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Select batch label to print',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Filter by Batch Label / Date
                    _buildPrintFilterLabel('Filter by Batch Label / Date'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selBatch,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1A2E),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white54,
                          ),
                          items: _availableBatches
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(
                                    b == 'all' ? '🏷️ All Batches' : b,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setModalState(() => selBatch = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Switch Available Only
                    SwitchListTile(
                      value: availableOnly,
                      onChanged: (val) {
                        setModalState(() => availableOnly = val);
                      },
                      title: Text(
                        'Available Vouchers Only',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'Exclude used or expired vouchers',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      thumbColor: WidgetStateProperty.resolveWith<Color?>(
                        (states) => states.contains(WidgetState.selected)
                            ? const Color(0xFF00BFFF)
                            : null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Counter badge & Action
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00BFFF).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Matching Vouchers:',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFFF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${targetVouchers.length}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: targetVouchers.isEmpty
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _showPrintPreviewModal(targetVouchers);
                              },
                        icon: const Icon(Icons.print_rounded),
                        label: Text(
                          'Preview & Print (${targetVouchers.length})',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00BFFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPrintPreviewModal(List<Voucher> vouchers) {
    showVoucherPrintPreview(context, vouchers);
  }



  void _showProWelcomePopup() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0E2E),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: -10,
              ),
            ],
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
                'Unlimited voucher generation is now active. Enjoy Pro Mode!',
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
                  onPressed: () => Navigator.pop(ctx),
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
                        'Awesome! →',
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
    );
  }

  void _showProExpiredPopup() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0E2E),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: -10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(Icons.warning_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'Subscription Ended',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your PRO monthly subscription has expired. Your account is back to Trial Mode.',
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => UpgradeScreen(service: widget.service)),
                    );
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
                        'Renew Now →',
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
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Dismiss',
                  style: GoogleFonts.poppins(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRemoteConfigGuide() {
    bool isLoading = true;
    bool isSavingDDNS = false;
    bool isSavingWebFig = false;
    bool ddnsEnabled = false;
    String dnsName = '';
    bool webFigEnabled = false;
    String webFigPort = '80';

    void fetchStatus(Function(VoidCallback) setDialogState) async {
      try {
        final cloudStatus = await widget.service.getCloudStatus();
        final webFigStatus = await widget.service.getWebFigStatus();
        if (mounted) {
          setDialogState(() {
            ddnsEnabled = (cloudStatus['ddns-enabled'] ?? 'no').toLowerCase() == 'yes' || (cloudStatus['ddns-enabled'] ?? 'no').toLowerCase() == 'auto';
            dnsName = cloudStatus['dns-name'] ?? '';
            webFigEnabled = (webFigStatus['disabled'] ?? 'yes').toLowerCase() == 'no' || (webFigStatus['disabled'] ?? 'yes').toLowerCase() == 'false';
            webFigPort = webFigStatus['port'] ?? '80';
            isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setDialogState(() => isLoading = false);
          TopToast.show(context, 'Error fetching status: $e', backgroundColor: const Color(0xFFFF5252));
        }
      }
    }

    void showEditPortDialog(String currentPort, Function(String) onPortChanged) {
      final TextEditingController portController = TextEditingController(text: currentPort);
      bool isSaving = false;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF00BFFF), width: 1),
              ),
              title: Text('Edit WebFig Port', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the new port number for the WebFig (www) service.', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: portController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Port Number',
                      labelStyle: GoogleFonts.poppins(color: Colors.white54),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF))),
                      filled: true,
                      fillColor: Colors.black26,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white60))),
                isSaving ? const CircularProgressIndicator(color: Color(0xFF00BFFF)) : ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFFF), foregroundColor: Colors.white),
                  onPressed: () async {
                    final newPort = portController.text.trim();
                    if (newPort.isEmpty) return;
                    setDialogState(() => isSaving = true);
                    try {
                      await widget.service.setWebFigPort(newPort);
                      onPortChanged(newPort);
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      TopToast.show(context, 'Port updated!', backgroundColor: const Color(0xFF34A853));
                    } catch (e) {
                      if (!mounted) return;
                      setDialogState(() => isSaving = false);
                      TopToast.show(context, 'Error: $e', backgroundColor: const Color(0xFFFF5252));
                    }
                  },
                  child: Text('Save', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (isLoading) {
            fetchStatus(setStateDialog);
            return const Dialog(
              backgroundColor: Colors.transparent,
              child: Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF))),
            );
          }
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161626),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF00BFFF).withValues(alpha: 0.3), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(color: const Color(0xFF00BFFF).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.router_rounded, color: Color(0xFF00BFFF), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Remote Config', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                              Text('Manage DDNS & WebFig', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enable DDNS', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(color: ddnsEnabled ? const Color(0xFF34A853) : const Color(0xFFFF5252), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        ddnsEnabled ? (dnsName.isEmpty ? 'Waiting for DNS Name...' : dnsName) : 'Stopped',
                                        style: GoogleFonts.poppins(color: ddnsEnabled ? const Color(0xFF34A853) : const Color(0xFFFF5252), fontSize: 12, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          isSavingDDNS
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF00BFFF), strokeWidth: 2))
                              : Switch(
                                  value: ddnsEnabled,
                                  activeThumbColor: const Color(0xFF00BFFF),
                                  onChanged: (val) async {
                                    setStateDialog(() => isSavingDDNS = true);
                                    try {
                                      await widget.service.setDdnsEnabled(val);
                                      if (val) {
                                        int retries = 10;
                                        while (retries > 0) {
                                          await Future.delayed(const Duration(seconds: 1));
                                          final st = await widget.service.getCloudStatus();
                                          if ((st['dns-name'] ?? '').isNotEmpty) {
                                            if (mounted) setStateDialog(() { dnsName = st['dns-name']!; ddnsEnabled = true; });
                                            break;
                                          }
                                          retries--;
                                        }
                                      } else {
                                        if (mounted) setStateDialog(() { ddnsEnabled = false; dnsName = ''; });
                                      }
                                    } catch (e) {
                                      if (!mounted) return;
                                      TopToast.show(context, 'Error: $e', backgroundColor: const Color(0xFFFF5252));
                                    } finally {
                                      if (mounted) setStateDialog(() => isSavingDDNS = false);
                                    }
                                  },
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Enable WebFig', style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(color: webFigEnabled ? const Color(0xFF34A853) : const Color(0xFFFF5252), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      webFigEnabled ? 'Running on Port $webFigPort' : 'Stopped (Port $webFigPort)',
                                      style: GoogleFonts.poppins(color: webFigEnabled ? const Color(0xFF34A853) : const Color(0xFFFF5252), fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () {
                                        showEditPortDialog(webFigPort, (newPort) {
                                          setStateDialog(() => webFigPort = newPort);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: const Icon(Icons.edit_rounded, color: Colors.white70, size: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          isSavingWebFig
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Color(0xFF00BFFF), strokeWidth: 2))
                              : Switch(
                                  value: webFigEnabled,
                                  activeThumbColor: const Color(0xFF00E676),
                                  onChanged: (val) async {
                                    setStateDialog(() => isSavingWebFig = true);
                                    try {
                                      await widget.service.setWebFigEnabled(val);
                                      if (mounted) setStateDialog(() => webFigEnabled = val);
                                    } catch (e) {
                                      if (!mounted) return;
                                      TopToast.show(context, 'Error: $e', backgroundColor: const Color(0xFFFF5252));
                                    } finally {
                                      if (mounted) setStateDialog(() => isSavingWebFig = false);
                                    }
                                  },
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Quick Guide', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildGuideStep('1', 'Access WebFig', 'Copy your DNS Name and paste it into a web browser. Add your port to the end if it is not 80 (e.g., your-dns-name.net:8080). Log in with your admin credentials.'),
                    const SizedBox(height: 16),
                    _buildGuideStep('2', 'CGNAT Warning', 'If your ISP uses CGNAT (private WAN IP), DDNS won\'t work. You must use a VPN like ZeroTier.'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFFF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        child: Text('Close', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGuideStep(String number, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24, height: 24,
          decoration: const BoxDecoration(color: Color(0xFF00BFFF), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(desc, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobile: _buildMobileLayout(context),
      desktop: _buildDesktopLayout(context),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;
    final isAdmin = AuthService.isCurrentUserAdmin(currentUser?.email);
    
    return Scaffold(
      backgroundColor: const Color(0xFF090915),
      body: Stack(
        children: [
          // Deep Space Background Glows
          Positioned(top: -150, left: -100, child: _buildGlowOrb(const Color(0xFF00BFFF), 400)),
          Positioned(bottom: -200, right: -100, child: _buildGlowOrb(const Color(0xFF7B2FBE), 600)),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Floating Glassmorphism Sidebar
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF00BFFF).withValues(alpha: 0.1), blurRadius: 40, spreadRadius: -10),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 32),
                          // App Icon Header
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00BFFF), Color(0xFF7B2FBE)],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF00BFFF).withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: const Icon(Icons.router_rounded, color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 24),
                          
                          // User Profile Chip
                          GestureDetector(
                            onTap: _disconnect,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: const Color(0xFF00C853).withValues(alpha: 0.2),
                                    child: Text(
                                      (currentUser?.displayName ?? 'A').substring(0, 1).toUpperCase(),
                                      style: GoogleFonts.poppins(color: const Color(0xFF00C853), fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text('Admin', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF00C853).withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.5)),
                                              ),
                                              child: Text('PRO ⚡', style: GoogleFonts.poppins(color: const Color(0xFF00C853), fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.logout_rounded, color: Color(0xFFFF5252), size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                children: [
                                  _buildSidebarItem(0, Icons.dashboard_rounded, 'Dashboard', isNew: false),
                                  _buildSidebarItem(1, Icons.add_circle_outline_rounded, 'Generate', isNew: false),
                                  _buildSidebarItem(2, Icons.confirmation_number_outlined, 'Vouchers', isNew: false),
                                  _buildSidebarItem(3, Icons.people_alt_outlined, 'Active Sessions', isNew: false),
                                  _buildSidebarItem(4, Icons.speed_rounded, 'Profiles', isNew: false),
                                  _buildSidebarItem(5, Icons.code_rounded, 'Scripts', isNew: false),
                                  _buildSidebarItem(6, Icons.network_check_rounded, 'PPPoE', isNew: true),
                                  if (_fileManagerUnlocked || isAdmin)
                                    _buildSidebarItem(7, Icons.folder_open_rounded, 'Files', isNew: true),
                                  _buildSidebarItem(-1, Icons.print_rounded, 'Print', isAction: true, onTap: _showPrintOptionsModal),
                                  if (isAdmin)
                                    _buildSidebarItem(-2, Icons.settings_remote_rounded, 'Remote Config', isAction: true, onTap: _showRemoteConfigGuide)
                                  else
                                    _buildSidebarItem(-2, Icons.lock_outline_rounded, 'Remote Config', isAction: true, onTap: () {
                                      TopToast.show(context, 'Remote Config is currently locked by the Admin', backgroundColor: const Color(0xFFF57C00));
                                    }),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                          _buildSidebarItem(-3, Icons.logout_rounded, 'Logout', isAction: true, onTap: _disconnect),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              // Main content area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                  child: IndexedStack(
                    index: _desktopSelectedIndex,
                    children: [
                      _buildDesktopDashboardHome(context), // Glassmorphism dashboard
                      GenerateScreen(service: widget.service),
                      VoucherListScreen(service: widget.service),
                      ActiveVouchersScreen(service: widget.service),
                      ProfileListScreen(service: widget.service),
                      ScriptListScreen(service: widget.service),
                      PppoeScreen(service: widget.service),
                      MikrotikFileExplorerScreen(service: widget.service),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlowOrb(Color color, double size) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.15), Colors.transparent],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label, {bool isAction = false, VoidCallback? onTap, bool isNew = false}) {
    final isSelected = !isAction && _desktopSelectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () {
            setState(() => _desktopSelectedIndex = index);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: isSelected ? BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF00BFFF).withValues(alpha: 0.2), const Color(0xFF00BFFF).withValues(alpha: 0.05)],
                begin: Alignment.centerLeft, end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: const Color(0xFF00BFFF), width: 3)),
            ) : null,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? const Color(0xFF00BFFF) : Colors.white54,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.5)),
                    ),
                    child: Text('new', style: GoogleFonts.poppins(color: const Color(0xFFFF9800), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDashboardHome(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column (MikroTik Status + Overview + Traffic Flow)
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGlassCard(
                      child: _buildMikrotikStatusCard(),
                      borderColor: const Color(0xFF00BFFF),
                    ),
                    const SizedBox(height: 20),
                    _buildGlassCard(
                      child: _buildVoucherOverviewCard(),
                      borderColor: const Color(0xFF7B2FBE),
                    ),
                    const SizedBox(height: 20),
                    _buildGlassCard(
                      child: _buildTrafficFlowCard(),
                      borderColor: const Color(0xFF00BFFF),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Right Column (Cloud Sync + Active Users + Logs)
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGlassCard(
                      child: _buildSalesMonitoringCard(),
                      borderColor: const Color(0xFF7B2FBE),
                    ),
                    const SizedBox(height: 20),
                    _buildGlassCard(
                      child: _buildActiveUsersTableCard(),
                      borderColor: const Color(0xFF00C853),
                    ),
                    const SizedBox(height: 20),
                    _buildGlassCard(
                      child: _buildLogsCard(),
                      borderColor: const Color(0xFF00BFFF),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, required Color borderColor, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.1),
                blurRadius: 30,
                spreadRadius: -10,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildMikrotikStatusCard() {
    final uptime = _systemResource?['uptime'] ?? '00:00:00';
    final cpuLoad = _systemResource?['cpu-load'] ?? '0';
    final freeMemoryStr = _systemResource?['free-memory'] ?? '0';
    final totalMemoryStr = _systemResource?['total-memory'] ?? '0';
    
    final freeMem = double.tryParse(freeMemoryStr) ?? 0;
    final totalMem = double.tryParse(totalMemoryStr) ?? 1;
    final usedMem = totalMem - freeMem;
    final ramLoad = (usedMem / totalMem * 100).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MikroTik Status', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(AuthService.instance.currentUser?.displayName ?? 'Router', style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_outlined, color: Colors.white54, size: 16),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.language_rounded, color: Colors.white54, size: 14),
                      const SizedBox(width: 8),
                      Text(widget.service.host, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, color: Colors.white54, size: 14),
                      const SizedBox(width: 8),
                      Text('Uptime: $uptime', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            // CPU & RAM stats
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildResourceBar(Icons.developer_board_rounded, 'CPU Load', '$cpuLoad%', double.tryParse(cpuLoad) ?? 0, const Color(0xFF00BFFF)),
                  const SizedBox(height: 16),
                  _buildResourceBar(Icons.memory_rounded, 'RAM Usage', '$ramLoad%', double.tryParse(ramLoad) ?? 0, const Color(0xFF7B2FBE)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResourceBar(IconData icon, String label, String value, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(icon, color: Colors.white54, size: 14),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
            const SizedBox(width: 8),
            Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: 120,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.centerLeft,
          child: Container(
            width: 120 * (percentage / 100).clamp(0.0, 1.0),
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSalesMonitoringCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Sales Monitoring', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const Icon(Icons.monetization_on_rounded, color: Color(0xFF34A853), size: 20),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Today', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14)),
            Text('₱${_todaySales.toStringAsFixed(2)}', style: GoogleFonts.poppins(color: const Color(0xFF34A853), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('This Month', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14)),
            Text('₱${_monthlySales.toStringAsFixed(2)}', style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14)),
            Text('₱${_totalSales.toStringAsFixed(2)}', style: GoogleFonts.poppins(color: const Color(0xFF7B2FBE), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildVoucherOverviewCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Voucher Overview', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Row(
          children: [
            // Donut Chart Mock
            SizedBox(
              width: 120, height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 0,
                      centerSpaceRadius: 40,
                      startDegreeOffset: -90,
                      sections: [
                        PieChartSectionData(color: const Color(0xFF00BFFF), value: (_availableCount > 0 ? _availableCount : 15).toDouble(), title: '', radius: 20),
                        PieChartSectionData(color: const Color(0xFF7B2FBE), value: (_usedCount > 0 ? _usedCount : 8).toDouble(), title: '', radius: 20),
                        PieChartSectionData(color: Colors.white10, value: (_expiredCount > 0 ? _expiredCount : 5).toDouble(), title: '', radius: 20),
                      ],
                    ),
                  ),
                  const Icon(Icons.confirmation_number_outlined, color: Color(0xFF00BFFF), size: 30),
                ],
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                children: [
                  _buildLegendRow(const Color(0xFF00BFFF), 'Available', _availableCount),
                  const SizedBox(height: 12),
                  _buildLegendRow(const Color(0xFF7B2FBE), 'Used', _usedCount),
                  const SizedBox(height: 12),
                  _buildLegendRow(Colors.white54, 'Expired', _expiredCount),
                  const SizedBox(height: 24),
                  InkWell(
                    onTap: () => setState(() => _desktopSelectedIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00BFFF).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00BFFF), size: 18),
                          const SizedBox(width: 8),
                          Text('Generate Vouchers', style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendRow(Color color, String label, int count) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Text(label, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        Text(count.toString(), style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActiveUsersTableCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active Users', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(flex: 1, child: Text('User ID', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11))),
            Expanded(flex: 2, child: Text('IP Address', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11))),
            Expanded(flex: 2, child: Text('MAC Address', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11))),
            Expanded(flex: 2, child: Text('Active Since', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11))),
            Expanded(flex: 2, child: Text('Data Usage', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11))),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 12),
        if (_activeSessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No active users', style: GoogleFonts.poppins(color: Colors.white54))),
          )
        else
          ..._activeSessions.take(5).map((u) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text(u.user.isNotEmpty ? u.user : 'Unknown', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12))),
                Expanded(flex: 2, child: Text(u.address.isNotEmpty ? u.address : '-', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12))),
                Expanded(flex: 2, child: Text(u.macAddress.isNotEmpty ? u.macAddress : '-', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12))),
                Expanded(flex: 2, child: Text(u.uptime.isNotEmpty ? u.uptime : '-', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12))),
                Expanded(flex: 2, child: Text(u.bytesOut.isNotEmpty ? u.bytesOut : '-', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12))),
              ],
            ),
          )).toList(),
      ],
    );
  }

  Widget _buildTrafficFlowCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Traffic Flow', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        Text('Bandwidth utilization for ${_monitoredInterface ?? 'interface'}', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 24),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withValues(alpha: 0.05), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)} M', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10)))),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minY: 0, maxY: _maxTrafficY,
              lineBarsData: [
                LineChartBarData(
                  spots: _rxSpots.isEmpty ? const [FlSpot(0, 0)] : _rxSpots,
                  isCurved: true,
                  color: const Color(0xFF00BFFF),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [const Color(0xFF00BFFF).withValues(alpha: 0.5), const Color(0xFF7B2FBE).withValues(alpha: 0.1)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                LineChartBarData(
                  spots: _txSpots.isEmpty ? const [FlSpot(0, 0)] : _txSpots,
                  isCurved: true,
                  color: const Color(0xFF7B2FBE),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MikroTik Logs', style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          height: 120,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF060612),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: SingleChildScrollView(
            child: Text(
              '''13:28:23-23:01:327 | MikroTik Logs test...
13:28:33-23:02:327 | Network interface up
13:28:22-33:08:327 | User admin logged in
15:26-25-33:05:222 | DHCP lease assigned 192.168.8.44
16:01:10-00:00:000 | Voucher generated 1x
16:05:22-11:11:111 | System check ok''',
              style: GoogleFonts.firaCode(color: const Color(0xFF00C853), fontSize: 11, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickActionsGrid(List<Widget> children) {
    final cols = Responsive(context).gridColumns(itemWidth: 300).clamp(2, 3);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: cols > 2 ? 1.4 : 1.18,
      children: children,
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    if (_trialLocked) {
      return _LockedActionCard(
        icon: icon,
        label: label,
        gradient: const [
          Color(0xFF444466),
          Color(0xFF333355),
        ],
        onTap: () async {
          final upgraded = await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UpgradeScreen(service: widget.service)),
          );
          if (upgraded == true) _loadData();
        },
      );
    }
    return _QuickActionCard(
      icon: icon,
      label: label,
      gradient: gradient,
      onTap: onTap,
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;
    final isAdmin = AuthService.isCurrentUserAdmin(currentUser?.email);
    return Scaffold(
      backgroundColor: const Color(0xFF050510),
      body: Stack(
        children: [
          // Background glowing orbs
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00BFFF).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF7B2FBE).withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF00BFFF),
              backgroundColor: const Color(0xFF1A1A2E),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── App Bar ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: currentUser?.isAdmin == true 
                                ? [const Color(0xFF9C27B0), const Color(0xFFE1BEE7)] 
                                : (_isPro ? [const Color(0xFF34A853), const Color(0xFF00C853)] : [const Color(0xFFFFB74D), const Color(0xFFFF9800)]),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (currentUser?.isAdmin == true 
                                  ? const Color(0xFF9C27B0) 
                                  : (_isPro ? const Color(0xFF34A853) : const Color(0xFFFFB74D))).withValues(alpha: 0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: currentUser?.photoUrl != null
                          ? CircleAvatar(
                              radius: 18.5,
                              backgroundImage: NetworkImage(currentUser!.photoUrl!),
                            )
                          : Container(
                              width: 37,
                              height: 37,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E3A28),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  currentUser?.displayName.isNotEmpty == true 
                                      ? currentUser!.displayName[0].toUpperCase() 
                                      : 'V',
                                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser?.displayName ?? 'VoucherApp',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              widget.service.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF00BFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _loadData,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white54,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: _disconnect,
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFFFF5252),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Connected pill ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E676).withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connected · ${widget.service.username}@${widget.service.host}:${widget.service.port}',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: const Color(0xFF00E676),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),


              // ── PRO Mode Banner (Monthly) ───────────────────────────────
              if (_isPro && _proExpiresAt != null && _proExpiresAt!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF34A853), Color(0xFF00C853)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A0E2E),
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF34A853), Color(0xFF00C853)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF34A853).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PRO Monthly Active',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Valid until ${_formatExpDate(_proExpiresAt!)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Trial Mode Banner ─────────────────────────────────────────
              if (_trialLocked)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: GestureDetector(
                      onTap: () async {
                        final upgraded = await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                        );
                        if (upgraded == true) _loadData();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF9800), Color(0xFFFF5252), Color(0xFFBB86FC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A0E2E),
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Row(
                            children: [
                              // Icon with glow
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 14),
                              // Text
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Trial Mode Active',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Generation locked · Tap to unlock Pro',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Upgrade chip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'UPGRADE',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),


              // ── Body ─────────────────────────────────────────────────────
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: SpinKitFadingCircle(
                      color: Color(0xFF00BFFF),
                      size: 50,
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            color: Color(0xFFFF5252),
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Connection Error',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(
                              'Retry',
                              style: GoogleFonts.poppins(),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00BFFF),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverFadeTransition(
                  opacity: _fadeAnim,
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Constrain dashboard content width on tablets.
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      // ── Live Vendo Machine Monitor ───────────────────────
                      VendoMonitorCard(
                        profile: RouterProfile(
                          id: 'current',
                          name: widget.service.host.isNotEmpty ? widget.service.host : 'MikroTik Vendo',
                          host: widget.service.host,
                          port: widget.service.port,
                          username: widget.service.username,
                          password: widget.service.password,
                          machineType: 'mikrotik',
                        ),
                        onRefresh: _loadData,
                      ),
                      // ── Income & Sales Background Section ──────────────────
                      _SectionCard(
                        title: 'Income & Sales',
                        icon: Icons.payments_rounded,
                        accentColor: const Color(0xFF00E676),
                        child: _statGrid([
                          StatCard(
                            title: "Today's Income",
                            value: '₱${_todaySales.toStringAsFixed(0)}',
                            icon: Icons.today_rounded,
                            color: const Color(0xFF00E676),
                            subtitle: 'Daily sales',
                          ),
                          StatCard(
                            title: 'Monthly Income',
                            value: '₱${_monthlySales.toStringAsFixed(0)}',
                            icon: Icons.calendar_month_rounded,
                            color: const Color(0xFF00BFFF),
                            subtitle: 'This month sales',
                          ),
                          StatCard(
                            title: 'Total Income',
                            value: '₱${_totalSales.toStringAsFixed(0)}',
                            icon: Icons.account_balance_wallet_rounded,
                            color: const Color(0xFF9C27B0),
                            subtitle: 'All active sales',
                          ),
                        ]),
                      ),

                      // ── Voucher Overview Background Section ────────────────
                      _SectionCard(
                        title: 'Voucher Overview',
                        icon: Icons.confirmation_number_rounded,
                        accentColor: const Color(0xFF00BFFF),
                        child: _statGrid([
                          StatCard(
                            title: 'Total Vouchers',
                            value: '$_totalVouchers',
                            icon: Icons.confirmation_number_rounded,
                            color: const Color(0xFF00BFFF),
                            subtitle: 'Total generated',
                          ),
                          StatCard(
                            title: 'Active Sessions',
                            value: '$_activeCount',
                            icon: Icons.wifi_rounded,
                            color: const Color(0xFF00E676),
                            subtitle: 'Currently online',
                          ),
                          StatCard(
                            title: 'Available',
                            value: '$_availableCount',
                            icon: Icons.check_circle_outline_rounded,
                            color: const Color(0xFF7B2FBE),
                            subtitle: 'Ready to use',
                          ),
                          StatCard(
                            title: 'Used',
                            value: '$_usedCount',
                            icon: Icons.history_rounded,
                            color: const Color(0xFFFF9800),
                            subtitle: 'Already redeemed',
                          ),
                        ]),
                      ),
                      // ── Quick Actions Background Section ───────────────────
                      _SectionCard(
                        title: 'Quick Actions',
                        icon: Icons.bolt_rounded,
                        accentColor: const Color(0xFFFF9800),
                        child: _quickActionsGrid([
                          _buildActionItem(
                            icon: Icons.add_circle_rounded,
                            label: 'Generate\nVouchers',
                            gradient: const [Color(0xFF00BFFF), Color(0xFF0066CC)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => GenerateScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          _buildActionItem(
                            icon: Icons.list_alt_rounded,
                            label: 'Voucher\nList',
                            gradient: const [Color(0xFF7B2FBE), Color(0xFF4A1580)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => VoucherListScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          _buildActionItem(
                            icon: Icons.style_rounded,
                            label: 'User\nProfiles',
                            gradient: const [Color(0xFFFF9800), Color(0xFFE65100)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ProfileListScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          _buildActionItem(
                            icon: Icons.code_rounded,
                            label: 'Router\nScripts',
                            gradient: const [Color(0xFF7B2FBE), Color(0xFF512DA8)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ScriptListScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final currentUser = AuthService.instance.currentUser;
                              final isAdmin = AuthService.isCurrentUserAdmin(currentUser?.email);
                              if (isAdmin || _fileManagerUnlocked) {
                                return _buildActionItem(
                                  icon: Icons.folder_open_rounded,
                                  label: 'File\nManager',
                                  gradient: const [Color(0xFFE91E63), Color(0xFFC2185B)],
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => MikrotikFileExplorerScreen(service: widget.service)),
                                    );
                                  },
                                );
                              } else {
                                return _buildActionItem(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'File\nLocked',
                                  gradient: const [Color(0xFF757575), Color(0xFF424242)],
                                  onTap: () {
                                    TopToast.show(context, 'File Manager is currently locked by the Admin', backgroundColor: const Color(0xFFF57C00));
                                  },
                                );
                              }
                            }
                          ),
                          _buildActionItem(
                            icon: Icons.wifi_tethering_rounded,
                            label: 'Active\nVouchers',
                            gradient: const [Color(0xFF00E676), Color(0xFF00B0FF)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => ActiveVouchersScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          _buildActionItem(
                            icon: Icons.print_rounded,
                            label: 'Print\nVouchers',
                            gradient: const [Color(0xFF00BFE0), Color(0xFF0099CC)],
                            onTap: _showPrintOptionsModal,
                          ),
                          _buildActionItem(
                            icon: Icons.alt_route_rounded,
                            label: 'PPPoE\nClients',
                            gradient: const [Color(0xFFBB86FC), Color(0xFF6200EE)],
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PppoeScreen(service: widget.service)),
                              );
                              _loadData();
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final currentUser = AuthService.instance.currentUser;
                              final isAdmin = AuthService.isCurrentUserAdmin(currentUser?.email);
                              if (isAdmin) {
                                return _buildActionItem(
                                  icon: Icons.router_rounded,
                                  label: 'Remote\nConfig',
                                  gradient: const [Color(0xFFFF5252), Color(0xFFD32F2F)],
                                  onTap: _showRemoteConfigGuide,
                                );
                              } else {
                                return _buildActionItem(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Config\nLocked',
                                  gradient: const [Color(0xFF757575), Color(0xFF424242)],
                                  onTap: () {
                                    TopToast.show(context, 'Remote Config is currently locked by the Admin', backgroundColor: const Color(0xFFF57C00));
                                  },
                                );
                              }
                            }
                          ),
                        ]),
                      ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
        ],
      ),

      // FAB — hidden in trial mode
      floatingActionButton: (_loading || _trialLocked)
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GenerateScreen(service: widget.service),
                  ),
                );
                _loadData();
              },
              backgroundColor: const Color(0xFF00BFFF),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Generate',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141428),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A locked action card shown in trial mode — styled with a gradient border
/// and a glowing lock badge to draw attention and prompt upgrade.
class _LockedActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _LockedActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A0E2E),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Opacity(
                      opacity: 0.5,
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF9800).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 10,
                        color: Color(0xFFFF9800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: 0.5,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to upgrade',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFF9800),
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

