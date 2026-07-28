import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../services/mikrotik_service.dart';
import '../models/voucher.dart';
import '../responsive.dart';
import '../widgets/voucher_card.dart';
import '../widgets/print_preview_helper.dart';

class VoucherListScreen extends StatefulWidget {
  final MikrotikService service;
  final List<String> highlightedNames;

  // Global static cache to highlight new vouchers persistently during a session
  static Set<String> newlyGeneratedNames = {};
  static List<Voucher> newlyGeneratedVouchers = [];

  const VoucherListScreen({
    super.key,
    required this.service,
    this.highlightedNames = const [],
  });

  @override
  State<VoucherListScreen> createState() => _VoucherListScreenState();
}

class _VoucherListScreenState extends State<VoucherListScreen>
    with TickerProviderStateMixin, RouteAware {
  List<Voucher> _all = [];
  List<Voucher> _filtered = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  // Filter state
  String _filterStatus = 'all'; // all, available, used, expired
  String _filterBatch = 'all';

  // Multi-select state
  Set<String> _selectedIds = {};
  bool _multiSelect = false;

  // Cached computed lists — rebuilt only when _all changes
  List<String> _cachedBatches = ['all'];

  late AnimationController _listCtrl;
  late Animation<double> _listAnim;
  late TabController _tabController;

  // Debounce timer for search
  DateTime? _lastSearchTime;

  // Guards against overlapping _loadData() calls (initState, didPopNext,
  // refresh, pull-to-refresh, retry). Without it, two concurrent runs iterate
  // AND mutate the shared static caches concurrently → ConcurrentModificationError.
  bool _isLoadingData = false;

  // Tracks whether we are already subscribed to routeObserver, because
  // didChangeDependencies can fire more than once and re-subscribing causes
  // duplicate didPopNext → duplicate reloads per navigation.
  bool _subscribedToRouteObserver = false;

  List<String> get _availableBatches => _cachedBatches;

  void _rebuildCaches() {
    final batches = <String>{'all'};
    final batchRe = RegExp(r'Date:(\d{4}-\d{2}-\d{2})');
    for (final v in _all) {
      final bMatch = batchRe.firstMatch(v.comment);
      if (bMatch != null) {
        batches.add(bMatch.group(1)!);
      } else if (v.comment.isNotEmpty) {
        final firstPart = v.comment.split('|').first.trim();
        if (firstPart.isNotEmpty) batches.add(firstPart);
      }
    }
    _cachedBatches = batches.toList();

    // If the currently selected batch filter no longer exists (e.g. all
    // vouchers of that batch were deleted), reset it to 'all'. Otherwise
    // DropdownButton gets a value not in its items → Flutter assertion error.
    if (_filterBatch != 'all' && !_cachedBatches.contains(_filterBatch)) {
      _filterBatch = 'all';
    }
  }

  List<Voucher> _getVouchersForPrint({
    required String batch,
    required bool availableOnly,
    bool useSelected = false,
  }) {
    if (useSelected && _selectedIds.isNotEmpty) {
      return _all.where((v) => _selectedIds.contains(v.id)).toList();
    }

    return _all.where((v) {
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

  int get _availableCount => _all.where((v) => !v.isUsed && !v.disabled).length;
  int get _usedCount => _all.where((v) => v.isUsed).length;
  int get _expiredCount => _all.where((v) => v.disabled && !v.isUsed).length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final statuses = ['all', 'available', 'used', 'expired'];
        setState(() => _filterStatus = statuses[_tabController.index]);
        _applyFilter();
      }
    });
    _listCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _listAnim = CurvedAnimation(parent: _listCtrl, curve: Curves.easeOut);
    _searchCtrl.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe so we can auto-refresh when a pushed route (e.g. Generate,
    // Print preview) pops and this screen becomes active again.
    // Guard against double-subscription — didChangeDependencies can fire
    // multiple times, and each extra subscribe doubles the didPopNext reloads.
    if (_subscribedToRouteObserver) return;
    _subscribedToRouteObserver = true;
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _tabController.dispose();
    _listCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returning to this screen — reload so newly created vouchers show up
    // without the user having to pull-to-refresh.
    _loadData();
  }

  Future<void> _loadData() async {
    // Guard against overlapping calls (initState, didPopNext, refresh,
    // pull-to-refresh, retry). Two concurrent runs would iterate and mutate
    // the shared static newlyGeneratedVouchers cache at the same time.
    if (_isLoadingData) return;
    _isLoadingData = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vouchers = await widget.service.getVouchers();

      // Merge recently generated vouchers to fix router API sync lag.
      // Take a snapshot of the cache first so we don't iterate a collection
      // that another path might mutate.
      final fetchedNames = vouchers.map((v) => v.name).toSet();
      final preloadedSnapshot =
          List<Voucher>.from(VoucherListScreen.newlyGeneratedVouchers);
      for (final preloaded in preloadedSnapshot) {
        if (!fetchedNames.contains(preloaded.name)) {
          vouchers.add(preloaded);
        }
      }
      // Cleanup cache: remove from cache once router successfully returns them
      VoucherListScreen.newlyGeneratedVouchers
          .removeWhere((v) => fetchedNames.contains(v.name));

      // Sort: Newest generated first
      vouchers.sort((a, b) {
        final aDate = a.createdDate;
        final bDate = b.createdDate;
        if (aDate != null && bDate != null) {
          final cmp = bDate.compareTo(aDate);
          if (cmp != 0) return cmp;
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }

        // MikroTik assigns IDs as * followed by HEX.
        final aHex = a.id.replaceFirst('*', '');
        final bHex = b.id.replaceFirst('*', '');
        final aIdNum = int.tryParse(aHex, radix: 16);
        final bIdNum = int.tryParse(bHex, radix: 16);

        if (aIdNum != null && bIdNum != null) return bIdNum.compareTo(aIdNum);
        return b.id.compareTo(a.id);
      });

      if (!mounted) return;
      _all = vouchers;
      _rebuildCaches(); // build caches off main setState
      final filtered = _computeFilter();
      setState(() {
        _filtered = filtered;
        _loading = false;
      });
      _listCtrl.forward(from: 0);
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

  // Compute filter without calling setState — call setState separately
  List<Voucher> _computeFilter() {
    final q = _searchCtrl.text.toLowerCase().trim();
    return _all.where((v) {
      final matchSearch = q.isEmpty ||
          v.name.toLowerCase().contains(q) ||
          v.password.toLowerCase().contains(q) ||
          v.profile.toLowerCase().contains(q) ||
          v.comment.toLowerCase().contains(q);

      final matchStatus = switch (_filterStatus) {
        'available' => !v.isUsed && !v.disabled,
        'used' => v.isUsed,
        'expired' => v.disabled && !v.isUsed,
        _ => true,
      };

      final matchBatch = () {
        if (_filterBatch == 'all') return true;
        final bMatch = RegExp(r'Date:(\d{4}-\d{2}-\d{2})').firstMatch(v.comment);
        final bLabel = bMatch != null
            ? bMatch.group(1)!
            : (v.comment.isNotEmpty ? v.comment.split('|').first.trim() : 'No Batch');
        return bLabel == _filterBatch;
      }();

      return matchSearch && matchStatus && matchBatch;
    }).toList();
  }

  void _applyFilter() {
    final result = _computeFilter();
    if (mounted) setState(() => _filtered = result);
  }

  void _onSearchChanged() {
    // Debounce: only filter after 200ms of no typing
    final now = DateTime.now();
    _lastSearchTime = now;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_lastSearchTime == now) _applyFilter();
    });
  }



  Future<void> _deleteVoucher(Voucher v) async {
    final confirm = await _showDeleteDialog(count: 1);
    if (!confirm) return;
    try {
      await widget.service.removeActiveSessionByUsername(v.name);
      await widget.service.removeVoucher(v.id);

      VoucherListScreen.newlyGeneratedVouchers.removeWhere((x) => x.id == v.id);
      VoucherListScreen.newlyGeneratedNames.remove(v.name);

      if (!mounted) return;
      setState(() => _all.removeWhere((x) => x.id == v.id));
      _applyFilter();
      TopToast.show(context, 'Voucher deleted', backgroundColor: const Color(0xFFFF5252));
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await _showDeleteDialog(count: _selectedIds.length);
    if (!confirm) return;
    try {
      final selectedVouchers = _all.where((v) => _selectedIds.contains(v.id)).toList();
      for (final v in selectedVouchers) {
        await widget.service.removeActiveSessionByUsername(v.name);
        VoucherListScreen.newlyGeneratedNames.remove(v.name);
      }
      VoucherListScreen.newlyGeneratedVouchers.removeWhere((v) => _selectedIds.contains(v.id));

      await widget.service.removeVouchers(_selectedIds.toList());
      if (!mounted) return;
      setState(() {
        _all.removeWhere((v) => _selectedIds.contains(v.id));
        _selectedIds.clear();
        _multiSelect = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    }
  }

  Future<bool> _showDeleteDialog({required int count}) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF161626),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Delete ${count == 1 ? 'Voucher' : '$count Vouchers'}?',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            content: Text(
              'This action cannot be undone.',
              style: GoogleFonts.poppins(color: Colors.white54),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5252),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Delete',
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String msg) {
    TopToast.show(context, msg.replaceFirst('Exception: ', ''), backgroundColor: const Color(0xFFFF5252));
  }

  void _shareVoucher(Voucher v) {
    final text =
        '🌐 Wi-Fi Voucher\nUser: ${v.name}${v.password.isNotEmpty ? '\nPass: ${v.password}' : ''}'
        '${v.profile.isNotEmpty ? '\nProfile: ${v.profile}' : ''}'
        '${v.limitUptime.isNotEmpty ? '\nUptime: ${v.limitUptime}' : ''}';
    Share.share(text, subject: 'Hotspot Voucher');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Responsive.constrain(
          Column(
            children: [
              // ── Header ──────────────────────────────────────────────────────
              _buildHeader(),

              // ── Search + Sort ────────────────────────────────────────────────
              _buildSearchBar(),

              // ── Tabs ─────────────────────────────────────────────────────────
              _buildTabBar(),

              // ── Batch filter dropdown ──────────────────────────────────────
              if (_availableBatches.length > 2) _buildBatchDropdown(),

              // ── Multi-select action bar ──────────────────────────────────────
              if (_multiSelect) _buildMultiSelectBar(),

              const SizedBox(height: 8),

              // ── Count info ──────────────────────────────────────────────────
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        '${_filtered.length} voucher${_filtered.length != 1 ? 's' : ''}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── List ────────────────────────────────────────────────────────
              Expanded(child: _buildList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voucher List',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_all.length} total · $_availableCount available · $_usedCount used',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          // Print button
          if (!_loading && _all.isNotEmpty)
            IconButton(
              onPressed: () => _showPrintOptionsModal(useSelected: false),
              icon: const Icon(Icons.print_rounded, color: Color(0xFF00BFFF)),
              tooltip: 'Print Vouchers',
            ),
          // Multi-select toggle
          if (!_loading && _all.isNotEmpty)
            IconButton(
              onPressed: () {
                setState(() {
                  _multiSelect = !_multiSelect;
                  if (!_multiSelect) {
                    _selectedIds.clear();
                  } else {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    TopToast.show(context, 'Multi-select mode enabled', backgroundColor: const Color(0xFF00BFFF));
                  }
                });
              },
              icon: Icon(
                _multiSelect ? Icons.close_rounded : Icons.checklist_rounded,
                color: _multiSelect ? const Color(0xFFFF5252) : const Color(0xFF00BFFF),
              ),
              tooltip: _multiSelect ? 'Exit Multi-Select' : 'Multi-Select Vouchers',
            ),
          // Refresh
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchCtrl,
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by code, profile, comment...',
          hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded,
                      color: Colors.white38, size: 18),
                  onPressed: _searchCtrl.clear,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF161626),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF00BFFF), width: 1),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161626),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF00BFFF),
              Color(0xFF7B2FBE),
            ]),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'All (${_all.length})'),
            Tab(text: 'Available ($_availableCount)'),
            Tab(text: 'Used ($_usedCount)'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Expired',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: _filterStatus == 'expired'
                            ? FontWeight.w700
                            : FontWeight.w400,
                      )),
                  if (_expiredCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_expiredCount',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchDropdown() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF161626),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _filterBatch != 'all'
                ? const Color(0xFFBB86FC).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
            width: _filterBatch != 'all' ? 1.5 : 1,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _filterBatch,
            isExpanded: true,
            dropdownColor: const Color(0xFF1A1A2E),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white54,
            ),
            items: _availableBatches
                .map(
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Icon(
                          p == 'all'
                              ? Icons.list_alt_rounded
                              : Icons.folder_rounded,
                          size: 16,
                          color: p == 'all'
                              ? const Color(0xFF00BFFF)
                              : const Color(0xFFBB86FC),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            p == 'all' ? 'All Batches' : p,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: _filterBatch == p
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _filterBatch == p
                                  ? const Color(0xFFBB86FC)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _filterBatch = v);
                _applyFilter();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectBar() {
    final allSelected = _filtered.isNotEmpty && _selectedIds.length == _filtered.length;
    final hasSelection = _selectedIds.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF00BFFF).withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(
          children: [
            // Select All / Deselect All Checkbox Button
            InkWell(
              onTap: () {
                setState(() {
                  if (allSelected) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds = _filtered.map((v) => v.id).toSet();
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BFFF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      allSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: const Color(0xFF00BFFF),
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      allSelected ? 'Deselect' : 'All',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_selectedIds.length} sel',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Print action
            Opacity(
              opacity: hasSelection ? 1.0 : 0.4,
              child: InkWell(
                onTap: hasSelection ? () => _showPrintOptionsModal(useSelected: true) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.print_rounded, color: Color(0xFF00BFFF), size: 16),
                      const SizedBox(width: 3),
                      Text(
                        'Print',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFF00BFFF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Delete action
            Opacity(
              opacity: hasSelection ? 1.0 : 0.4,
              child: InkWell(
                onTap: hasSelection ? _deleteSelected : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 16),
                      const SizedBox(width: 3),
                      Text(
                        'Delete',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: const Color(0xFFFF5252),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(
        child: SpinKitFadingCircle(color: Color(0xFF00BFFF), size: 50),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFF5252), size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: GoogleFonts.poppins(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry', style: GoogleFonts.poppins(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFFF),
              ),
            ),
          ],
        ),
      );
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _filterStatus == 'expired'
                  ? Icons.timer_off_rounded
                  : Icons.confirmation_number_outlined,
              color: Colors.white24,
              size: 60,
            ),
            const SizedBox(height: 12),
            Text(
              _filterStatus == 'expired'
                  ? 'No expired vouchers'
                  : _all.isEmpty
                      ? 'No vouchers yet'
                      : 'No matching vouchers',
              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _listAnim,
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color(0xFF00BFFF),
        backgroundColor: const Color(0xFF1A1A2E),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          // Caches items nearby for smoother scrolling
          itemCount: _filtered.length,
          itemBuilder: (context, i) {
            final v = _filtered[i];
            // RepaintBoundary prevents card repaints from propagating up
            return RepaintBoundary(
              child: VoucherCard(
                voucher: v,
                isSelected: _selectedIds.contains(v.id),
                isHighlighted: widget.highlightedNames.contains(v.name) || 
                               VoucherListScreen.newlyGeneratedNames.contains(v.name),
                onTap: _multiSelect
                    ? () {
                        setState(() {
                          if (_selectedIds.contains(v.id)) {
                            _selectedIds.remove(v.id);
                          } else {
                            _selectedIds.add(v.id);
                          }
                        });
                      }
                    : null,
                onDelete: () => _deleteVoucher(v),
                onShare: () => _shareVoucher(v),
              ),
            );
          },
        ),
      ),
    );
  }



  Widget _buildPrintFilterLabel(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white60,
      ),
    );
  }

  void _showPrintOptionsModal({bool useSelected = false}) {
    String selBatch = _filterBatch != 'all' ? _filterBatch : 'all';
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
              useSelected: useSelected,
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
                                useSelected
                                    ? 'Filter or print ${_selectedIds.length} selected vouchers'
                                    : 'Select batch label to print',
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

                    if (!useSelected) ...[
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
                    ],

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
                          disabledBackgroundColor: Colors.white10,
                          disabledForegroundColor: Colors.white38,
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
}

class PrintTicketCard extends StatelessWidget {
  final Voucher voucher;
  final int index;

  const PrintTicketCard({super.key, required this.voucher, required this.index});

  @override
  Widget build(BuildContext context) {
    final priceStr =
        voucher.price > 0 ? '₱${voucher.price.toStringAsFixed(0)}' : 'Free';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00BFFF),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_rounded,
                        size: 13, color: Color(0xFF00BFFF)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '#$index',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  priceStr,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 6, thickness: 1, color: Colors.black12),
          FittedBox(
            child: Text(
              voucher.name,
              style: GoogleFonts.sourceCodePro(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 2,
              ),
            ),
          ),
          if (voucher.password.isNotEmpty)
            Text(
              'PASS: ${voucher.password}',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7B2FBE),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  voucher.profile.isNotEmpty ? voucher.profile : 'default',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (voucher.limitUptime.isNotEmpty) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    voucher.limitUptime,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
