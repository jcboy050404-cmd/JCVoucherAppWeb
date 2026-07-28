import 'dart:convert';
import '../widgets/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:image_picker/image_picker.dart';
import '../services/cloud_sync_service.dart';
import '../services/trial_service.dart';
import '../services/auth_service.dart';
import '../services/force_update_service.dart';
import '../responsive.dart';


class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> _allRequests = [];
  bool _isLoading = true;
  String _filter = 'pending'; // 'pending', 'approved', 'rejected', 'all'
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final TextEditingController _manualEmailCtrl = TextEditingController();
  bool _isGrantingManual = false;

  final TextEditingController _gcashNumCtrl = TextEditingController();
  final TextEditingController _gcashNameCtrl = TextEditingController();
  final TextEditingController _qrUrlCtrl = TextEditingController();
  final TextEditingController _proPriceCtrl = TextEditingController();
  final TextEditingController _monthlyPriceCtrl = TextEditingController();
  bool _isSavingSettings = false;
  int _currentTabIndex = 0;
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoadingUsers = false;
  bool _pppoeUnlocked = false;
  bool _remoteConfigUnlocked = false;
  bool _isSavingGlobal = false;

  // Force Update config — values currently published to the backend.
  String _forceUpdateLatest = '';
  String _forceUpdateUrl = '';
  bool _forceUpdateEnabled = true;
  bool _isLoadingForceUpdate = true;
  bool _isSavingForceUpdate = false;
  
  bool _showSettings = false;

  Future<void> _loadGlobalSettings() async {
    final settings = await CloudSyncService.getGlobalSettings();
    if (mounted) {
      setState(() {
        _pppoeUnlocked = settings['pppoe_unlocked'] == true;
        _remoteConfigUnlocked = settings['remote_config_unlocked'] == true;
      });
    }
  }

  /// Fetches the current force-update config so the card can show what's
  /// live on the backend (and pre-fill the edit dialog).
  Future<void> _loadForceUpdateConfig() async {
    final config = await ForceUpdateService.getConfig();
    if (mounted) {
      setState(() {
        _isLoadingForceUpdate = false;
        if (config != null) {
          _forceUpdateLatest = config.latestVersion;
          _forceUpdateUrl = config.updateUrl;
          _forceUpdateEnabled = config.enabled;
        }
      });
    }
  }

  Future<void> _togglePppoe(bool val) async {
    setState(() {
      _pppoeUnlocked = val;
      _isSavingGlobal = true;
    });
    final success = await CloudSyncService.updateGlobalSettings({'pppoe_unlocked': val});
    if (mounted) {
      setState(() => _isSavingGlobal = false);
      if (success) {
        TopToast.show(context, '✅ PPPoE Feature ${val ? 'Unlocked' : 'Locked'} globally!', backgroundColor: const Color(0xFF34A853));
      } else {
        TopToast.show(context, '❌ Failed to save setting', backgroundColor: const Color(0xFFFF5252));
        setState(() => _pppoeUnlocked = !val); // revert
      }
    }
  }

  Future<void> _toggleRemoteConfig(bool val) async {
    setState(() {
      _remoteConfigUnlocked = val;
      _isSavingGlobal = true;
    });
    final success = await CloudSyncService.updateGlobalSettings({'remote_config_unlocked': val});
    if (mounted) {
      setState(() => _isSavingGlobal = false);
      if (success) {
        TopToast.show(context, '✅ Remote Config ${val ? 'Unlocked' : 'Locked'} globally!', backgroundColor: const Color(0xFF34A853));
      } else {
        TopToast.show(context, '❌ Failed to save setting', backgroundColor: const Color(0xFFFF5252));
        setState(() => _remoteConfigUnlocked = !val); // revert
      }
    }
  }

  Future<void> _loadAllUsers() async {
    if (mounted) {
      setState(() {
        _isLoadingUsers = true;
      });
    }
    final users = await CloudSyncService.getAllUsers();
    if (mounted) {
      setState(() {
        _allUsers = users;
        _isLoadingUsers = false;
      });
    }
  }


  @override
  void initState() {
    super.initState();
    _loadAllRequests();
    _loadAllUsers();
    _loadGCashSettings();
    _loadGlobalSettings();
    _loadForceUpdateConfig();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _manualEmailCtrl.dispose();
    _gcashNumCtrl.dispose();
    _gcashNameCtrl.dispose();
    _qrUrlCtrl.dispose();
    _proPriceCtrl.dispose();
    _monthlyPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGCashSettings() async {
    final cfg = await CloudSyncService.getGCashSettings();
    if (mounted) {
      setState(() {
        if (_gcashNumCtrl.text.isEmpty) _gcashNumCtrl.text = cfg['gcash_number'] ?? '';
        if (_gcashNameCtrl.text.isEmpty) _gcashNameCtrl.text = cfg['account_name'] ?? '';
        if (_qrUrlCtrl.text.isEmpty) _qrUrlCtrl.text = cfg['qr_image_url'] ?? '';
        if (_proPriceCtrl.text.isEmpty) _proPriceCtrl.text = cfg['pro_price'] ?? '';
        if (_monthlyPriceCtrl.text.isEmpty) _monthlyPriceCtrl.text = cfg['monthly_price'] ?? '150';
      });
    }
  }

  Future<void> _saveGCashSettings() async {
    setState(() => _isSavingSettings = true);
    try {
      final success = await CloudSyncService.saveGCashSettings(
        gcashNumber: _gcashNumCtrl.text.trim(),
        accountName: _gcashNameCtrl.text.trim(),
        qrImageUrl: _qrUrlCtrl.text.trim(),
        proPrice: _proPriceCtrl.text.trim(),
        monthlyPrice: _monthlyPriceCtrl.text.trim(),
      );
      if (!mounted) return;
      if (success) {
        TopToast.show(context, '✅ GCash QR & Number updated for all users!', backgroundColor: const Color(0xFF34A853));
      }
    } catch (e) {
      if (mounted) {
        TopToast.show(context, 'Error saving settings: $e', backgroundColor: const Color(0xFFFF5252));
      }
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }


  Future<void> _loadAllRequests() async {
    setState(() => _isLoading = true);
    try {
      final list = await CloudSyncService.getAllPaymentRequests();
      if (mounted) {
        setState(() {
          _allRequests = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRequests {
    return _allRequests.where((req) {
      final status = (req['status'] ?? 'pending').toString().toLowerCase();
      final email = (req['email'] ?? '').toString().toLowerCase();
      final ref = (req['ref_number'] ?? '').toString().toLowerCase();

      bool matchesFilter = true;
      if (_filter == 'pending') matchesFilter = status == 'pending';
      if (_filter == 'approved') matchesFilter = status == 'approved';
      if (_filter == 'rejected') matchesFilter = status == 'rejected';

      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        matchesSearch = email.contains(q) || ref.contains(q);
      }

      return matchesFilter && matchesSearch;
    }).toList();
  }

  int get _pendingCount =>
      _allRequests.where((r) => r['status'] == 'pending').length;
  int get _approvedCount =>
      _allRequests.where((r) => r['status'] == 'approved').length;
  double get _totalRevenue {
    return _allRequests
        .where((r) => r['status'] == 'approved')
        .fold(0.0, (sum, r) => sum + (double.tryParse(r['amount']?.toString() ?? '0') ?? 0.0));
  }

  Future<void> _approveRequest(String refNumber, String email, String plan) async {
    final success =
        await CloudSyncService.approvePaymentRequest(refNumber, email);
    if (success) {
      await _changeUserAccountType(email, plan.toLowerCase());
      _loadAllRequests();
    }
  }

  Future<void> _rejectRequest(String refNumber) async {
    final success = await CloudSyncService.rejectPaymentRequest(refNumber);
    if (success && mounted) {
      TopToast.show(context, 'Rejected request $refNumber', backgroundColor: const Color(0xFFFF5252));
      _loadAllRequests();
    _loadAllUsers();
    }
  }

  Future<void> _deleteHistoryRequest(String refNumber) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Delete History?', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to delete this payment request history?', style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await CloudSyncService.deletePaymentRequest(refNumber);
      if (success && mounted) {
        TopToast.show(context, 'Deleted history $refNumber', backgroundColor: const Color(0xFF34A853));
        _loadAllRequests();
      } else if (mounted) {
        TopToast.show(context, 'Failed to delete history', backgroundColor: const Color(0xFFFF5252));
      }
    }
  }

  Future<void> _confirmDeleteUser(String id, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Delete Account?', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to permanently delete $email?', style: GoogleFonts.poppins(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await CloudSyncService.deleteUserAccount(id);
      if (success) {
        if (mounted) TopToast.show(context, '✅ Deleted $email', backgroundColor: const Color(0xFF34A853));
        _loadAllUsers();
      } else {
        if (mounted) TopToast.show(context, '❌ Failed to delete', backgroundColor: const Color(0xFFFF5252));
      }
    }
  }

  Future<void> _changeUserAccountType(String email, String type) async {
    if (email.isEmpty || email == 'No Email') return;
    
    setState(() => _isLoadingUsers = true);
    try {
      if (type == 'trial') {
        await CloudSyncService.saveUserState(email, pro: false, proExpiresAt: '');
      } else if (type == 'trial_reset') {
        await TrialService.resetTrial(email);
        await CloudSyncService.saveUserState(email, pro: false, proExpiresAt: '');
      } else if (type == 'lifetime') {
        await CloudSyncService.saveUserState(email, pro: true, proExpiresAt: '');
      } else if (type == 'monthly') {
        final now = DateTime.now();
        final expiry = now.add(const Duration(days: 30));
        await CloudSyncService.saveUserState(email, pro: true, proExpiresAt: expiry.toIso8601String());
      }

      await TrialService.syncWithCloud(email);

      if (mounted) {
        TopToast.show(context, '✅ Updated account to ${type.toUpperCase()}', backgroundColor: const Color(0xFF34A853));
      }
    } catch (e) {
      if (mounted) {
        TopToast.show(context, '❌ Failed to update account: $e', backgroundColor: const Color(0xFFFF5252));
      }
    } finally {
      _loadAllUsers();
    }
  }

  Future<void> _grantManualPro() async {
    final email = _manualEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      TopToast.show(context, '⚠️ Enter a valid email address', backgroundColor: Color(0xFFFF5252));
      return;
    }

    setState(() => _isGrantingManual = true);
    try {
      await CloudSyncService.saveUserState(email, pro: true);
      await TrialService.unlockPro(email, null);
      if (!mounted) return;
      _manualEmailCtrl.clear();
      TopToast.show(context, '⚡ PRO License Granted to $email!', backgroundColor: const Color(0xFF34A853));
    } catch (e) {
      if (mounted) {
        TopToast.show(context, 'Error: ${e.toString()}', backgroundColor: const Color(0xFFFF5252));
      }
    } finally {
      if (mounted) setState(() => _isGrantingManual = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12122A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF34A853).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Color(0xFF34A853), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Admin Dashboard',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showSettings ? Icons.close_rounded : Icons.settings_rounded,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _showSettings = !_showSettings),
            tooltip: _showSettings ? 'Close Settings' : 'System Settings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00BFFF)),
            onPressed: _loadAllRequests,
            tooltip: 'Refresh Requests',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SpinKitThreeBounce(
                color: Color(0xFF34A853),
                size: 28,
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAllRequests,
              color: const Color(0xFF34A853),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 700;
                  final hPad = isWide ? 32.0 : 18.0;
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                        horizontal: hPad, vertical: 20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Admin Banner
                            _buildAdminBanner(currentUser?.email),
                            const SizedBox(height: 16),

                            if (_showSettings) ...[
                              Row(
                                children: [
                                  const Icon(Icons.settings_rounded, color: Colors.white70, size: 24),
                                  const SizedBox(width: 10),
                                  Text(
                                    'System Settings',
                                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (isWide)
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                          child: _buildGCashSettingsCard()),
                                      const SizedBox(width: 18),
                                      Expanded(
                                          child: Column(
                                            children: [
                                              _buildManualGrantCard(),
                                              const SizedBox(height: 18),
                                              _buildGlobalSettingsCard(),
                                              const SizedBox(height: 18),
                                              _buildForceUpdateCard(),
                                            ],
                                          )),
                                    ],
                                  ),
                                )
                              else ...[
                                _buildGCashSettingsCard(),
                                const SizedBox(height: 20),
                                _buildManualGrantCard(),
                                const SizedBox(height: 20),
                                _buildGlobalSettingsCard(),
                                const SizedBox(height: 20),
                                _buildForceUpdateCard(),
                              ],
                            ] else ...[
                              // Top Tabs
                              _buildTopTabs(),
                              const SizedBox(height: 16),

                              if (_currentTabIndex == 0) ...[
                                // Stats Dashboard
                                _buildStatsRow(),
                                const SizedBox(height: 20),

                                // Requests Section Header & Tabs
                                Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Payment Requests',
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00BFFF)
                                          .withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_filteredRequests.length} Item(s)',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Filter Tabs
                              _buildFilterTabs(),
                              const SizedBox(height: 12),

                              // Search Input
                              _buildSearchInput(),
                              const SizedBox(height: 16),

                              // Requests List
                              if (_filteredRequests.isEmpty)
                                _buildEmptyState()
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: _filteredRequests.length,
                                  itemBuilder: (context, idx) {
                                    return _buildRequestCard(
                                        _filteredRequests[idx]);
                                  },
                                ),
                            ] else ...[
                              _buildUserAccountsView(),
                            ],
                           ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentTabIndex = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _currentTabIndex == 0 ? const Color(0xFF34A853) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Payments & Config',
                  style: GoogleFonts.poppins(
                    color: _currentTabIndex == 0 ? Colors.white : Colors.white54,
                    fontWeight: _currentTabIndex == 0 ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _currentTabIndex = 1);
                if (_allUsers.isEmpty && !_isLoadingUsers) {
                  _loadAllUsers();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _currentTabIndex == 1 ? const Color(0xFF4285F4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'User Accounts',
                  style: GoogleFonts.poppins(
                    color: _currentTabIndex == 1 ? Colors.white : Colors.white54,
                    fontWeight: _currentTabIndex == 1 ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAccountsView() {
    if (_isLoadingUsers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SpinKitThreeBounce(color: Color(0xFF4285F4), size: 28),
        ),
      );
    }
    if (_allUsers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('No users found', style: GoogleFonts.poppins(color: Colors.white54)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _allUsers.length,
      itemBuilder: (context, index) {
        final user = _allUsers[index];
        final id = user['id'] as String? ?? '';
        final email = user['email'] as String? ?? 'No Email';
        final name = user['display_name'] as String? ?? '';
        final photoUrl = user['photo_url'] as String? ?? '';
        final isPro = user['pro'] == true;
        final isTrial = user['trial_used'] == true;
        final isAdmin = user['is_admin'] == true;
        final lastLogin = user['last_login_at'] as String? ?? '';
        final displayName = name.isNotEmpty ? name : email.split('@').first;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF14142D),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAdmin ? const Color(0xFF9C27B0).withValues(alpha: 0.3) :
                     isPro ? const Color(0xFF34A853).withValues(alpha: 0.3) :
                     Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isAdmin ? const Color(0xFF9C27B0).withValues(alpha: 0.2) :
                                 isPro ? const Color(0xFF34A853).withValues(alpha: 0.2) :
                                 Colors.white.withValues(alpha: 0.05),
                backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty ? Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    color: isAdmin ? const Color(0xFFE1BEE7) :
                           isPro ? const Color(0xFFA5D6A7) :
                           Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      email.isNotEmpty ? email : 'No Email Provided',
                      style: GoogleFonts.poppins(color: name.isNotEmpty ? Colors.white70 : Colors.white, fontSize: name.isNotEmpty ? 12 : 13, fontWeight: name.isNotEmpty ? FontWeight.normal : FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastLogin.isNotEmpty ? "Last Login: ${lastLogin.split('T').first}" : "Unknown",
                      style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(color: const Color(0xFF9C27B0).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('ADMIN 👑', style: GoogleFonts.poppins(color: const Color(0xFFE1BEE7), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  if (isPro && !isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(color: const Color(0xFF34A853).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('PRO ⭐', style: GoogleFonts.poppins(color: const Color(0xFFA5D6A7), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  if (!isPro && !isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: isTrial ? const Color(0xFFFF9800).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text(isTrial ? 'Trial Used' : 'Free/Trial', style: GoogleFonts.poppins(color: isTrial ? const Color(0xFFFFB74D) : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 20),
                color: const Color(0xFF1A1A2E),
                onSelected: (val) => _changeUserAccountType(email, val),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'trial',
                    child: Text('Set to Free/Trial', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                  ),
                  if (isTrial)
                    PopupMenuItem(
                      value: 'trial_reset',
                      child: Text('Reset Free Trial', style: GoogleFonts.poppins(color: const Color(0xFFFFB74D), fontSize: 13)),
                    ),
                  PopupMenuItem(
                    value: 'monthly',
                    child: Text('Set to PRO (Monthly)', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                  ),
                  PopupMenuItem(
                    value: 'lifetime',
                    child: Text('Set to PRO (Lifetime)', style: GoogleFonts.poppins(color: const Color(0xFF34A853), fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 22),
                onPressed: () => _confirmDeleteUser(id, email),
                tooltip: 'Delete User Account',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminBanner(String? adminEmail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B1A), Color(0xFF141432)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF34A853).withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF34A853),
            radius: 20,
            child: Icon(Icons.security_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logged in as Verified Admin',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  adminEmail ?? 'admin@gmail.com',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatTile(
            title: 'Pending',
            value: '$_pendingCount',
            color: const Color(0xFFFF9800),
            icon: Icons.hourglass_top_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatTile(
            title: 'Approved',
            value: '$_approvedCount',
            color: const Color(0xFF34A853),
            icon: Icons.verified_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatTile(
            title: 'Revenue',
            value: '₱${_totalRevenue.toStringAsFixed(0)}',
            color: const Color(0xFF00BFFF),
            icon: Icons.payments_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatTile({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFBB86FC).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               const Icon(Icons.settings_applications_rounded, color: Color(0xFFBB86FC), size: 22),
               const SizedBox(width: 8),
               Expanded(
                 child: Text(
                   'Global App Settings',
                   style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                 ),
               ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unlock PPPoE Clients', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('Allow all users to access PPPoE features', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                if (_isSavingGlobal)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFBB86FC))),
                  )
                else
                  Switch(
                    value: _pppoeUnlocked,
                    onChanged: _togglePppoe,
                    activeColor: const Color(0xFFBB86FC),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unlock Remote Config', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                      Text('Allow all users to manage router services', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                if (_isSavingGlobal)
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFBB86FC))),
                  )
                else
                  Switch(
                    value: _remoteConfigUnlocked,
                    onChanged: _toggleRemoteConfig,
                    activeColor: const Color(0xFFBB86FC),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Force Update config card — lets the admin publish the minimum required
  /// app version and the download URL. Reads/writes the `/settings/force_update`
  /// node via [ForceUpdateService].
  Widget _buildForceUpdateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_rounded,
                  color: Color(0xFF00BFFF), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Force Update',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
              // Active / inactive badge
              if (!_isLoadingForceUpdate)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_forceUpdateEnabled && _forceUpdateLatest.isNotEmpty)
                        ? const Color(0xFF34A853).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    (_forceUpdateEnabled && _forceUpdateLatest.isNotEmpty)
                        ? 'ACTIVE'
                        : 'INACTIVE',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color:
                          (_forceUpdateEnabled && _forceUpdateLatest.isNotEmpty)
                              ? const Color(0xFF34A853)
                              : Colors.white54,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingForceUpdate)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF00BFFF)),
                ),
              ),
            )
          else ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Latest Version',
                          style: GoogleFonts.poppins(
                              color: Colors.white54, fontSize: 10)),
                      const SizedBox(width: 6),
                      Text(
                        _forceUpdateLatest.isEmpty
                            ? 'Not set'
                            : 'v$_forceUpdateLatest',
                        style: GoogleFonts.poppins(
                            color: const Color(0xFF00BFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (_forceUpdateUrl.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _forceUpdateUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingForceUpdate ? null : _showForceUpdateDialog,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: Text(
                  _forceUpdateLatest.isEmpty ? 'Set Update' : 'Update',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Form dialog for entering the Download Link + Version Number.
  /// Mirrors the form-dialog pattern in scripts_screen.dart.
  Future<void> _showForceUpdateDialog() async {
    final formKey = GlobalKey<FormState>();
    final versionCtrl =
        TextEditingController(text: _forceUpdateLatest);
    final urlCtrl = TextEditingController(text: _forceUpdateUrl);
    // Local toggle seeded from current backend value.
    var enabled = _forceUpdateEnabled;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded,
                  color: Color(0xFF00BFFF), size: 22),
              const SizedBox(width: 8),
              Text(
                'Force Update',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Users on a version below the Latest Version will be shown a mandatory update dialog.',
                    style: GoogleFonts.poppins(
                        color: Colors.white54, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: versionCtrl,
                    keyboardType: TextInputType.text,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 13),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Enter a version number';
                      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(s)) {
                        return 'Use format: major.minor.patch (e.g. 2.3.1)';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Version Number',
                      labelStyle: GoogleFonts.poppins(
                          color: Colors.white60, fontSize: 12),
                      hintText: 'e.g. 2.3.1',
                      hintStyle: GoogleFonts.poppins(
                          color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF00BFFF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: urlCtrl,
                    keyboardType: TextInputType.url,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 13),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Enter a download link';
                      final uri = Uri.tryParse(s);
                      if (uri == null ||
                          (!uri.isScheme('http') && !uri.isScheme('https'))) {
                        return 'Enter a valid http(s):// URL';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Download Link',
                      labelStyle: GoogleFonts.poppins(
                          color: Colors.white60, fontSize: 12),
                      hintText: 'https://...',
                      hintStyle: GoogleFonts.poppins(
                          color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF00BFFF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Enabled toggle inside the dialog.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Enabled',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              Text(
                                  'Turn off to pause the gate without clearing the version',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        Switch(
                          value: enabled,
                          onChanged: (v) =>
                              setDialogState(() => enabled = v),
                          activeThumbColor: const Color(0xFF00BFFF),
                          activeTrackColor: const Color(0xFF00BFFF).withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: _isSavingForceUpdate
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final version = versionCtrl.text.trim();
                      final url = urlCtrl.text.trim();
                      Navigator.pop(ctx);
                      await _saveForceUpdate(
                          latestVersion: version,
                          updateUrl: url,
                          enabled: enabled);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF34A853),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSavingForceUpdate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveForceUpdate({
    required String latestVersion,
    required String updateUrl,
    required bool enabled,
  }) async {
    setState(() => _isSavingForceUpdate = true);
    final success = await ForceUpdateService.saveConfig(
      latestVersion: latestVersion,
      updateUrl: updateUrl,
      enabled: enabled,
    );
    if (mounted) {
      setState(() {
        _isSavingForceUpdate = false;
        if (success) {
          _forceUpdateLatest = latestVersion;
          _forceUpdateUrl = updateUrl;
          _forceUpdateEnabled = enabled;
        }
      });
      if (success) {
        TopToast.show(context, '✅ Force Update saved globally!',
            backgroundColor: const Color(0xFF34A853));
      } else {
        TopToast.show(context, '❌ Failed to save Force Update',
            backgroundColor: const Color(0xFFFF5252));
      }
    }
  }

  Widget _buildManualGrantCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4285F4).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Color(0xFF4285F4), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Direct PRO Grant (Manual Unlock)',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Grant PRO license directly to any customer email address:',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualEmailCtrl,
                  decoration: InputDecoration(
                    hintText: 'customer@gmail.com',
                    hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isGrantingManual ? null : _grantManualPro,
                child: _isGrantingManual
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Grant PRO ⚡',
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickQRImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 50,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
        setState(() {
          _qrUrlCtrl.text = base64String;
        });
        if (!mounted) return;
        TopToast.show(context, '📸 QR Image selected! Tap Save GCash Config below.', backgroundColor: const Color(0xFF34A853));
      }
    } catch (e) {
      if (mounted) {
        TopToast.show(context, 'Failed to pick image: $e', backgroundColor: const Color(0xFFFF5252));
      }
    }
  }

  Widget _buildGCashSettingsCard() {
    final qrData = _qrUrlCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: Color(0xFF00BFFF), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GCash Config (Displayed to Customers)',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Select QR Code Image from gallery & enter your GCash mobile number:',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
          ),
          // Image Picker Input Field with Browse Button
          Text('QR Code Image (Upload File or Enter Link):', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qrUrlCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Select image file or paste URL...',
                    hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(Icons.image_rounded, color: Color(0xFF34A853), size: 18),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _pickQRImageFromGallery,
                icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 16),
                label: Text(
                  'Browse...',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34A853),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Image Preview Card
          if (qrData.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF34A853).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: qrData.startsWith('data:image')
                          ? Image.memory(
                              base64Decode(qrData.split(',').last),
                              fit: BoxFit.contain,
                            )
                          : Image.network(
                              qrData,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Icon(
                                Icons.qr_code_2_rounded,
                                size: 40,
                                color: Color(0xFF14142D),
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
                          'QR Image Loaded',
                          style: GoogleFonts.poppins(color: const Color(0xFF34A853), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          qrData.startsWith('data:image') ? 'Base64 Image File' : qrData,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    onPressed: () {
                      setState(() {
                        _qrUrlCtrl.clear();
                      });
                    },
                    tooltip: 'Clear Image',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],


          // Pro Price
          Text('Pro Version Price (PHP):', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextField(
            controller: _proPriceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'e.g. 299',
              hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.payments_rounded, color: Color(0xFF00BFFF), size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          // Monthly Price
          Text('Monthly Version Price (PHP):', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextField(
            controller: _monthlyPriceCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'e.g. 150',
              hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.payments_rounded, color: Color(0xFF00BFFF), size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          // GCash Number
          Text('GCash Mobile Number:', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextField(
            controller: _gcashNumCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'e.g. 09171234567',
              hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF00BFFF), size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),

          // Account Name
          Text('Account Name:', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextField(
            controller: _gcashNameCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. JOHN C. / VOUCHER APP ADMIN',
              hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(Icons.badge_rounded, color: Color(0xFF00BFFF), size: 18),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFFF),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSavingSettings ? null : _saveGCashSettings,
              icon: _isSavingSettings
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded,
                      color: Colors.white, size: 18),
              label: Text(
                'Save GCash Config ✅',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('pending', 'Pending ($_pendingCount)'),
          const SizedBox(width: 8),
          _buildFilterChip('approved', 'Approved ($_approvedCount)'),
          const SizedBox(width: 8),
          _buildFilterChip('all', 'All (${_allRequests.length})'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: const Color(0xFF34A853),
      backgroundColor: const Color(0xFF14142D),
      labelStyle: GoogleFonts.poppins(
        color: selected ? Colors.white : Colors.white54,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (val) {
        if (val) setState(() => _filter = value);
      },
    );
  }

  Widget _buildSearchInput() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (val) => setState(() => _searchQuery = val),
      decoration: InputDecoration(
        hintText: 'Search by Email or GCash Ref #...',
        hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF14142D),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF141426),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF34A853), size: 48),
          const SizedBox(height: 12),
          Text(
            'No Requests Found',
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'No GCash payment requests match your current filter.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final email = req['email'] ?? 'Unknown Email';
    final refNo = req['ref_number'] ?? 'N/A';
    final amount = req['amount'] ?? 1.0;
    final plan = (req['plan'] ?? 'lifetime').toString().toUpperCase();
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final submitted = (req['submitted_at'] ?? '').toString();

    Color statusColor = const Color(0xFFFF9800);
    String statusLabel = 'PENDING APPROVAL';
    if (status == 'approved') {
      statusColor = const Color(0xFF34A853);
      statusLabel = 'APPROVED ✅';
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFFF5252);
      statusLabel = 'REJECTED';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14142D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  email,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.poppins(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 14, color: Color(0xFF00BFFF)),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  'GCash Ref #: $refNo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: plan == 'MONTHLY' 
                          ? const Color(0xFFFF9800).withValues(alpha: 0.15) 
                          : const Color(0xFFBB86FC).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: plan == 'MONTHLY' ? const Color(0xFFFF9800) : const Color(0xFFBB86FC),
                      ),
                    ),
                    child: Text(
                      plan,
                      style: GoogleFonts.poppins(
                        color: plan == 'MONTHLY' ? const Color(0xFFFF9800) : const Color(0xFFBB86FC),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱$amount',
                    style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (submitted.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Submitted: ${submitted.split('T').first}',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _approveRequest(refNo, email, plan),
                    icon: const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 16),
                    label: Text(
                      'Approve ✅',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _rejectRequest(refNo),
                  icon: const Icon(Icons.cancel_rounded,
                      color: Color(0xFFFF5252), size: 16),
                  label: Text(
                    'Reject',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF5252)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _deleteHistoryRequest(refNo),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 16),
                label: Text(
                  'Delete History',
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
