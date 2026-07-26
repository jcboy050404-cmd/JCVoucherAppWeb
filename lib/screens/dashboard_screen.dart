import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:printing/printing.dart';
import '../main.dart';
import '../services/mikrotik_service.dart';
import '../services/voucher_pdf_service.dart';
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

class DashboardScreen extends StatefulWidget {
  final MikrotikService service;
  const DashboardScreen({super.key, required this.service});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, RouteAware {
  bool _loading = true;
  List<Voucher> _vouchers = [];
  List<HotspotActive> _activeSessions = [];
  String? _error;
  bool _trialLocked = false;
  bool _isPro = false;
  bool _pppoeUnlocked = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

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
    super.dispose();
  }

  @override
  void didPopNext() {
    // A child screen (Generate, Voucher list, etc.) was popped — refresh
    // stats so newly created vouchers are reflected immediately.
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vouchers = await widget.service.getVouchers();
      final activeSessions = await widget.service.getActiveSessions(vouchers);
      final currentUserEmail = AuthService.instance.currentUser?.email;
      final trialLocked = await TrialService.isTrialLocked(currentUserEmail, widget.service);
      final isPro = await TrialService.isPro(currentUserEmail);
      final settings = await CloudSyncService.getGlobalSettings();
      if (!mounted) return;
      setState(() {
        _vouchers = vouchers;
        _activeSessions = activeSessions;
        _trialLocked = trialLocked;
        _isPro = isPro;
        _pppoeUnlocked = settings['pppoe_unlocked'] == true;
        _loading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
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
  int get _availableCount =>
      _vouchers.where((v) => !v.isUsed && !v.disabled).length;

  double get _todaySales {
    final now = DateTime.now();
    return _vouchers.where((v) {
      if (v.createdDate == null) return false;
      return v.createdDate!.year == now.year &&
          v.createdDate!.month == now.month &&
          v.createdDate!.day == now.day;
    }).fold(0.0, (sum, v) => sum + v.price);
  }

  double get _monthlySales {
    final now = DateTime.now();
    return _vouchers.where((v) {
      if (v.createdDate == null) return false;
      return v.createdDate!.year == now.year &&
          v.createdDate!.month == now.month;
    }).fold(0.0, (sum, v) => sum + v.price);
  }

  List<String> get _availableProfiles {
    final set = <String>{'all'};
    for (final v in _vouchers) {
      if (v.profile.isNotEmpty) set.add(v.profile);
    }
    return set.toList();
  }

  List<String> get _availablePrices {
    final set = <String>{'all'};
    for (final v in _vouchers) {
      if (v.price > 0) {
        set.add('₱${v.price.toStringAsFixed(0)}');
      } else {
        set.add('Free');
      }
    }
    return set.toList();
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
    required String profile,
    required String price,
    required String batch,
    required bool availableOnly,
  }) {
    return _vouchers.where((v) {
      if (availableOnly && (v.isUsed || v.disabled)) return false;

      if (profile != 'all' && v.profile != profile) return false;

      if (price != 'all') {
        final pStr = v.price > 0 ? '₱${v.price.toStringAsFixed(0)}' : 'Free';
        if (pStr != price) return false;
      }

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

  /// Responsive grid for the six quick-action cards.
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

  void _showPrintOptionsModal() {
    String selProfile = 'all';
    String selPrice = 'all';
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
              profile: selProfile,
              price: selPrice,
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
                                'Select profile, price, or batch label to print',
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

                    // Filter by Profile
                    _buildPrintFilterLabel('Filter by Profile'),
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
                          value: selProfile,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1A2E),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white54,
                          ),
                          items: _availableProfiles
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p == 'all' ? '🌐 All Profiles' : p,
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
                              setModalState(() => selProfile = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Filter by Price
                    _buildPrintFilterLabel('Filter by Price'),
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
                          value: selPrice,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1A2E),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white54,
                          ),
                          items: _availablePrices
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p == 'all' ? '💰 All Prices' : p,
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
                              setModalState(() => selPrice = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

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
    VoucherPaperSize selectedPaper = VoucherPaperSize.a4;
    VoucherTemplate selectedTemplate = VoucherTemplate.standard;
    final hotspotCtrl = TextEditingController(text: 'JOEMIA WiFi Hotspot');
    final loginUrlCtrl = TextEditingController(text: 'http://10.10.10.1');
    final footerNoteCtrl = TextEditingController(text: 'ENJOY @ JOEMIA CAFE');
    bool showCustomizer = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPreviewState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF121224),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
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
                  const SizedBox(height: 16),
                  // Header row with close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Print Preview (${vouchers.length})',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${selectedPaper.nameLabel} | Auto-adjusting tickets',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF00BFFF),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Paper Size Dropdown ──────────────────────────────────
                  Text(
                    'Paper Size:',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<VoucherPaperSize>(
                        value: selectedPaper,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1A1A2E),
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white54,
                        ),
                        items: VoucherPaperSize.values
                            .map(
                              (paper) => DropdownMenuItem(
                                value: paper,
                                child: Text(
                                  paper.nameLabel,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (paper) {
                          if (paper != null) {
                            setPreviewState(() => selectedPaper = paper);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Template Selection (only for thermal 58mm) ──────────────
                  if (selectedPaper == VoucherPaperSize.thermal58) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Template Layout:',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            if (selectedTemplate == VoucherTemplate.withInstructions)
                              GestureDetector(
                                onTap: () {
                                  setPreviewState(() => showCustomizer = !showCustomizer);
                                },
                                child: Text(
                                  showCustomizer ? 'Hide Editor' : '✏️ Customize Fields',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF00BFFF),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setPreviewState(() =>
                                      selectedTemplate = VoucherTemplate.standard);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: selectedTemplate ==
                                            VoucherTemplate.standard
                                        ? const Color(0xFF00BFFF)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedTemplate ==
                                              VoucherTemplate.standard
                                          ? const Color(0xFF00BFFF)
                                          : Colors.white.withValues(alpha: 0.1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    'Standard',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selectedTemplate ==
                                              VoucherTemplate.standard
                                          ? Colors.black
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setPreviewState(() {
                                    selectedTemplate =
                                        VoucherTemplate.withInstructions;
                                    showCustomizer = true;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: selectedTemplate ==
                                            VoucherTemplate.withInstructions
                                        ? const Color(0xFF00BFFF)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedTemplate ==
                                              VoucherTemplate.withInstructions
                                          ? const Color(0xFF00BFFF)
                                          : Colors.white.withValues(alpha: 0.1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    'HTML Guide Receipt',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selectedTemplate ==
                                              VoucherTemplate.withInstructions
                                          ? Colors.black
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Inline Customizer Box
                        if (selectedTemplate == VoucherTemplate.withInstructions && showCustomizer) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0A14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Customize Receipt Text',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF00BFFF),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildPreviewEditorField(
                                  controller: hotspotCtrl,
                                  label: 'Hotspot Name',
                                  hint: 'JOEMIA WiFi Hotspot',
                                  onChanged: (_) => setPreviewState(() {}),
                                ),
                                const SizedBox(height: 6),
                                _buildPreviewEditorField(
                                  controller: loginUrlCtrl,
                                  label: 'Login Portal URL',
                                  hint: 'http://10.10.10.1',
                                  onChanged: (_) => setPreviewState(() {}),
                                ),
                                const SizedBox(height: 6),
                                _buildPreviewEditorField(
                                  controller: footerNoteCtrl,
                                  label: 'Footer Slogan',
                                  hint: 'ENJOY @ JOEMIA CAFE',
                                  onChanged: (_) => setPreviewState(() {}),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                    ),
                  ],

                  // Actual PDF Preview
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PdfPreview(
                        key: ValueKey((
                          selectedPaper,
                          selectedTemplate,
                          hotspotCtrl.text,
                          loginUrlCtrl.text,
                          footerNoteCtrl.text,
                        )),
                        build: (_) => VoucherPdfService.buildPdf(
                          vouchers,
                          paperSize: selectedPaper,
                          template: selectedTemplate,
                          hotspotName: hotspotCtrl.text.isNotEmpty
                              ? hotspotCtrl.text
                              : 'JOEMIA WiFi Hotspot',
                          loginUrl: loginUrlCtrl.text.isNotEmpty
                              ? loginUrlCtrl.text
                              : 'http://10.10.10.1',
                          footerNote: footerNoteCtrl.text.isNotEmpty
                              ? footerNoteCtrl.text
                              : 'ENJOY @ JOEMIA CAFE',
                        ),
                        allowPrinting: false,
                        allowSharing: false,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        pdfFileName:
                            'vouchers_${selectedPaper.shortLabel}_${vouchers.length}.pdf',
                        actions: const [],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    children: [
                      // ── Download PDF ──────────────────────────────────────
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final pdfBytes =
                                  await VoucherPdfService.buildPdf(
                                vouchers,
                                paperSize: selectedPaper,
                                template: selectedTemplate,
                              );
                              await Printing.sharePdf(
                                bytes: pdfBytes,
                                filename:
                                    'vouchers_${selectedPaper.shortLabel}_${vouchers.length}.pdf',
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('PDF download failed: $e',
                                      style: GoogleFonts.poppins()),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.file_download_rounded,
                              size: 18),
                          label: Text(
                            'Download PDF',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B35),
                            side: const BorderSide(
                                color: Color(0xFFFF6B35), width: 1.5),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // ── Print PDF ─────────────────────────────────────────
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await Printing.layoutPdf(
                                onLayout: (_) =>
                                    VoucherPdfService.buildPdf(
                                  vouchers,
                                  paperSize: selectedPaper,
                                  template: selectedTemplate,
                                ),
                                name:
                                    'vouchers_${selectedPaper.shortLabel}_${vouchers.length}',
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Print failed: $e',
                                      style: GoogleFonts.poppins()),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: Text(
                            'Print PDF',
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
                ],
              ),
            );
          },
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
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
                      Responsive.constrain(
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
                          Builder(
                            builder: (context) {
                              final isAdmin = AuthService.instance.currentUser?.isAdmin == true;
                              if (isAdmin || _pppoeUnlocked) {
                                return _buildActionItem(
                                  icon: Icons.alt_route_rounded,
                                  label: 'PPPoE\nClients',
                                  gradient: const [Color(0xFFBB86FC), Color(0xFF6200EE)],
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => PppoeScreen(service: widget.service)),
                                    );
                                    _loadData();
                                  },
                                );
                              } else {
                                return _buildActionItem(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'PPPoE\nLocked',
                                  gradient: const [Color(0xFF757575), Color(0xFF424242)], // Gray out
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'This feature is not available for now.',
                                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                                        ),
                                        backgroundColor: const Color(0xFFF57C00),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
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
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
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

  Widget _buildPreviewEditorField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(fontSize: 11, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1),
              ),
            ),
          ),
        ),
      ],
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: const Color(0xFFFF9800),
                    fontWeight: FontWeight.w500,
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

