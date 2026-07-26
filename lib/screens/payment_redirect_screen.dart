import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pppoe_user.dart';
import '../services/mikrotik_service.dart';
import '../services/pppoe_billing_service.dart';

const _kTag = 'pppoe-payment-guard';
const _kList = 'pppoe-overdue';
const _kProxyPort = 8080;

class PaymentRedirectConfig {
  final String businessName;
  final String phone;
  final String gcash;
  final String bankInfo;
  final String customMessage;
  final String timeout; // e.g. '00:05:00' for 5 minutes, or '' for permanent

  const PaymentRedirectConfig({
    this.businessName = '',
    this.phone = '',
    this.gcash = '',
    this.bankInfo = '',
    this.customMessage = '',
    this.timeout = '00:05:00',
  });

  String buildDenyMessage() {
    final biz = businessName.isNotEmpty ? businessName : 'Internet Service Provider';
    final msg = customMessage.isNotEmpty ? customMessage : 'Internet suspended due to overdue payment.';

    final gcashBox = gcash.isNotEmpty
        ? '<div style="background:rgba(0,191,255,0.08);border:1px solid rgba(0,191,255,0.2);border-radius:10px;padding:10px;margin-bottom:8px;font-size:13px;"><strong>📱 GCash:</strong> $gcash</div>'
        : '';
    final phoneBox = phone.isNotEmpty
        ? '<div style="background:rgba(0,230,118,0.08);border:1px solid rgba(0,230,118,0.2);border-radius:10px;padding:10px;margin-bottom:8px;font-size:13px;"><strong>📞 Call / Text:</strong> $phone</div>'
        : '';
    final bankBox = bankInfo.isNotEmpty
        ? '<div style="background:rgba(187,134,252,0.08);border:1px solid rgba(187,134,252,0.2);border-radius:10px;padding:10px;margin-bottom:8px;font-size:13px;"><strong>🏦 Bank:</strong> $bankInfo</div>'
        : '';

    return '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1.0"><style>'
        'body{margin:0;padding:16px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0b0b18;color:#fff;display:flex;align-items:center;justify-content:center;min-height:90vh;}'
        '.card{background:rgba(22,22,42,0.95);border:1px solid rgba(255,255,255,0.1);border-top:4px solid #ff3b30;border-radius:18px;padding:24px;max-width:380px;width:100%;box-shadow:0 20px 40px rgba(0,0,0,0.6);text-align:center;}'
        '.icon{font-size:44px;margin-bottom:8px;}'
        'h2{margin:0 0 4px;font-size:20px;color:#ff3b30;}'
        '.biz{font-size:12px;color:#00bfff;font-weight:700;text-transform:uppercase;letter-spacing:1px;margin-bottom:14px;}'
        '.msg{font-size:13px;color:#e1e1e6;line-height:1.5;margin-bottom:14px;background:rgba(0,0,0,0.3);padding:12px;border-radius:10px;text-align:left;}'
        '.footer{font-size:11px;color:#8e8e93;margin-top:14px;}'
        '</style></head><body>'
        '<div class="card">'
        '<div class="icon">⚠️</div>'
        '<h2>Payment Notice</h2>'
        '<div class="biz">$biz</div>'
        '<div class="msg">$msg</div>'
        '$gcashBox$phoneBox$bankBox'
        '<button onclick="this.innerHTML=\'✓ Internet Restored!\';this.style.background=\'#00e676\';setTimeout(function(){location.href=\'http://neverssl.com\';},800);" style="background:#00bfff;color:#000;border:none;padding:12px 20px;border-radius:12px;font-size:14px;font-weight:700;cursor:pointer;width:100%;margin-top:14px;box-shadow:0 4px 12px rgba(0,191,255,0.3);">OK / Continue to Internet</button>'
        '<div class="footer">Please settle your payment to restore high-speed internet access.</div>'
        '</div></body></html>';
  }

  /// Build the cache-administrator text shown on RouterOS v7 proxy deny page.
  /// This is the ONLY customizable text on the v7 "ERROR: Forbidden" page.
  String buildCacheAdminMessage() {
    final parts = <String>[];
    final biz = businessName.isNotEmpty ? businessName : 'ISP';
    parts.add(biz);
    parts.add('PAYMENT OVERDUE!');
    if (customMessage.isNotEmpty) parts.add(customMessage);
    if (phone.isNotEmpty) parts.add('Call/Text: $phone');
    if (gcash.isNotEmpty) parts.add('GCash: $gcash');
    if (bankInfo.isNotEmpty) parts.add('Bank: $bankInfo');
    return parts.join(' | ');
  }

  Map<String, String> toMap() => {
        'pr_businessName': businessName,
        'pr_phone': phone,
        'pr_gcash': gcash,
        'pr_bankInfo': bankInfo,
        'pr_customMessage': customMessage,
        'pr_timeout': timeout,
      };

  static Future<PaymentRedirectConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PaymentRedirectConfig(
      businessName: prefs.getString('pr_businessName') ?? '',
      phone: prefs.getString('pr_phone') ?? '',
      gcash: prefs.getString('pr_gcash') ?? '',
      bankInfo: prefs.getString('pr_bankInfo') ?? '',
      customMessage: prefs.getString('pr_customMessage') ?? '',
      timeout: prefs.getString('pr_timeout') ?? '00:05:00',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in toMap().entries) {
      await prefs.setString(e.key, e.value);
    }
  }
}

class PaymentRedirectScreen extends StatefulWidget {
  final MikrotikService service;
  final List<PppoeUser> overdueUsers;

  const PaymentRedirectScreen({
    super.key,
    required this.service,
    required this.overdueUsers,
  });

  @override
  State<PaymentRedirectScreen> createState() => _PaymentRedirectScreenState();
}

class _PaymentRedirectScreenState extends State<PaymentRedirectScreen> {
  final _businessCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _gcashCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  String _selectedTimeout = '00:05:00'; // Default 5 minutes
  bool _isInstalled = false;
  bool _isCheckingStatus = true;
  bool _isBusy = false;
  int _syncedCount = 0;
  bool _hasSynced = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _businessCtrl.dispose();
    _phoneCtrl.dispose();
    _gcashCtrl.dispose();
    _bankCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final config = await PaymentRedirectConfig.load();
    _businessCtrl.text = config.businessName;
    _phoneCtrl.text = config.phone;
    _gcashCtrl.text = config.gcash;
    _bankCtrl.text = config.bankInfo;
    _messageCtrl.text = config.customMessage.isNotEmpty
        ? config.customMessage
        : 'Internet suspended due to overdue payment. Please settle your bill.';

    final installed = await widget.service.isNatRuleInstalled(_kTag);
    if (mounted) {
      setState(() {
        _selectedTimeout = config.timeout;
        _isInstalled = installed;
        _isCheckingStatus = false;
      });
    }
  }

  PaymentRedirectConfig get _currentConfig => PaymentRedirectConfig(
        businessName: _businessCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        gcash: _gcashCtrl.text.trim(),
        bankInfo: _bankCtrl.text.trim(),
        customMessage: _messageCtrl.text.trim(),
        timeout: _selectedTimeout,
      );

  Future<void> _install() async {
    final config = _currentConfig;
    if (config.customMessage.isEmpty) {
      _snack('Please enter a Custom Message.', isError: true);
      return;
    }

    await config.save();
    setState(() => _isBusy = true);

    try {
      // 1. Enable web proxy with custom cache-administrator message (shown on v7 deny page)
      final cacheMsg = config.buildCacheAdminMessage();
      await widget.service.setWebProxyEnabled(port: _kProxyPort, cacheAdmin: cacheMsg);

      // 2. Remove old rules first (idempotent install)
      await widget.service.removeNatRulesByComment(_kTag);
      await widget.service.removeFilterRulesByComment(_kTag);
      await widget.service.removeWebProxyRulesByComment(_kTag);

      // 3. Add FastTrack bypass filter rule so redirect works
      await widget.service.addPaymentFilterRule(
        addressList: _kList,
        comment: _kTag,
      );

      // 4. Add NAT redirect rule
      await widget.service.addPaymentNatRule(
        addressList: _kList,
        proxyPort: _kProxyPort,
        comment: _kTag,
      );

      // 5. Add web proxy deny rule
      await widget.service.addWebProxyDenyRule(
        denyMessage: config.buildDenyMessage(),
        comment: _kTag,
      );

      setState(() => _isInstalled = true);
      _snack('✅ Payment redirect installed on router!');
    } catch (e) {
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      _showInstallError(errMsg);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  void _showInstallError(String error) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 8),
            Text('Install Failed', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(error, style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              Text('✅ Manual Fix in Winbox:', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ...[
                '1. Open Winbox → IP → Proxy',
                '2. Check ✔ Enabled, set Port = 8080, click Apply',
                '3. Open IP → Firewall → NAT → Check for "pppoe-payment-guard"',
                '4. Open IP → Firewall → Filter → Check for "pppoe-payment-guard"',
                '5. Open IP → Firewall → Address Lists → Check "pppoe-overdue"',
                '6. Make sure FastTrack rule is BELOW the payment guard filter rule',
              ].map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
              )),
              const SizedBox(height: 12),
              Text('Then tap "Install to Router" again.', style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: GoogleFonts.poppins(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFFF), foregroundColor: Colors.black),
            onPressed: () { Navigator.pop(ctx); _install(); },
            child: Text('Retry Install', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  Future<void> _applyOverdueNow() async {
    if (!_isInstalled) {
      _snack('Install the redirect first.', isError: true);
      return;
    }
    setState(() => _isBusy = true);
    try {
      // Fetch fresh PPPoE secrets and comments to calculate current overdue users
      final secrets = await widget.service.getPppoeSecrets();
      final billingMap = await PppoeBillingService.loadBillingMap();

      final overdueNames = <String>[];
      for (final s in secrets) {
        final billing = billingMap[s.name.toLowerCase()];
        DateTime? finalDueDate = billing?.dueDate;
        if (finalDueDate == null && s.comment.isNotEmpty) {
          final match = RegExp(r'Due:\s*(\d{4}-\d{2}-\d{2})', caseSensitive: false).firstMatch(s.comment);
          if (match != null) {
            finalDueDate = DateTime.tryParse(match.group(1)!);
          }
        }
        if (finalDueDate != null) {
          final user = s.copyWith(dueDate: finalDueDate);
          if (user.isOverdue) {
            overdueNames.add(user.name);
          }
        }
      }

      if (overdueNames.isEmpty) {
        _snack('No overdue clients found.');
      }

      final count = await widget.service.syncOverdueAddressList(
        list: _kList,
        overdueNames: overdueNames,
        timeout: _selectedTimeout,
      );

      // Disconnect active sessions so client device reconnects & triggers sign-in popup immediately
      try {
        final activeList = await widget.service.getPppoeActive();
        for (final a in activeList) {
          if (overdueNames.any((n) => n.toLowerCase() == a.name.toLowerCase())) {
            await widget.service.disconnectPppoeActive(a.id);
            await widget.service.addLogMessage(
              'PPPoE Guard: Reset active session for overdue client "${a.name}" (${a.address}) to trigger payment notice popup',
            );
          }
        }
      } catch (_) {}

      setState(() {
        _syncedCount = count;
        _hasSynced = true;
      });
      final timeoutLabel = _getTimeoutLabel(_selectedTimeout);
      _snack('🔴 $count overdue client(s) redirected ($timeoutLabel).');
    } catch (e) {
      _snack('Sync error: ${e.toString().replaceFirst('Exception: ', '')}', isError: true);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _clearOverdue() async {
    setState(() => _isBusy = true);
    try {
      await widget.service.clearAddressList(list: _kList, comment: 'pppoe-auto');
      setState(() {
        _syncedCount = 0;
        _hasSynced = true;
      });
      _snack('✅ All clients restored — redirect cleared.');
    } catch (e) {
      _snack('Error: ${e.toString().replaceFirst('Exception: ', '')}', isError: true);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _uninstall() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Payment Redirect?',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'This will remove the NAT rule, web proxy access rule, and all overdue address-list entries from the router.',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove All', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBusy = true);
    try {
      await widget.service.removeNatRulesByComment(_kTag);
      await widget.service.removeFilterRulesByComment(_kTag);
      await widget.service.removeWebProxyRulesByComment(_kTag);
      await widget.service.clearAddressList(list: _kList, comment: 'pppoe-auto');
      setState(() {
        _isInstalled = false;
        _hasSynced = false;
        _syncedCount = 0;
      });
      _snack('✅ Payment redirect removed from router.');
    } catch (e) {
      _snack('Error: ${e.toString().replaceFirst('Exception: ', '')}', isError: true);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    TopToast.show(context, msg, style: GoogleFonts.poppins(), backgroundColor: isError ? Colors.redAccent : const Color(0xFF00E676));
  }

  String _getTimeoutLabel(String timeoutVal) {
    switch (timeoutVal) {
      case '00:00:01':
        return '1 Second';
      case '00:00:10':
        return '10 Seconds';
      case '00:01:00':
        return '1 Minute';
      case '00:02:00':
        return '2 Minutes';
      case '00:05:00':
        return '5 Minutes';
      case '00:10:00':
        return '10 Minutes';
      case '00:15:00':
        return '15 Minutes';
      case '00:30:00':
        return '30 Minutes';
      case '01:00:00':
        return '1 Hour';
      case '':
        return 'Permanent';
      default:
        return '5 Minutes';
    }
  }

  void _showPreview() {
    final config = _currentConfig;
    final biz = config.businessName.isNotEmpty ? config.businessName : 'INTERNET SERVICE PROVIDER';
    final customMsg = config.customMessage.isNotEmpty ? config.customMessage : 'Internet suspended due to overdue payment.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.preview_rounded, color: Color(0xFF00BFFF)),
            const SizedBox(width: 10),
            Text('Client Webpage Preview',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                      top: const BorderSide(color: Colors.redAccent, width: 4),
                      left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
                  ),
                  child: Column(
                    children: [
                      const Text('⚠️', style: TextStyle(fontSize: 36)),
                      const SizedBox(height: 6),
                      Text(
                        'Payment Notice',
                        style: GoogleFonts.poppins(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        biz,
                        style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          customMsg,
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, height: 1.5),
                        ),
                      ),
                      if (config.gcash.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _PaymentBox(icon: Icons.account_balance_wallet_rounded, label: 'GCash', value: config.gcash, color: const Color(0xFF00BFFF)),
                      ],
                      if (config.phone.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _PaymentBox(icon: Icons.phone_rounded, label: 'Call / Text', value: config.phone, color: const Color(0xFF00E676)),
                      ],
                      if (config.bankInfo.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _PaymentBox(icon: Icons.account_balance_rounded, label: 'Bank', value: config.bankInfo, color: const Color(0xFFBB86FC)),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFFF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'OK / Continue to Internet',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Please settle your payment to restore high-speed internet access.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedTimeout.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_rounded, color: Color(0xFF00E676), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Internet auto-restores in ${_getTimeoutLabel(_selectedTimeout)}.',
                          style: GoogleFonts.poppins(color: const Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close Preview', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141426),
        elevation: 0,
        title: Text(
          '🌐 Payment Redirect Setup',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isCheckingStatus
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Status Banner ─────────────────────────────────────────
                _StatusBanner(isInstalled: _isInstalled),
                const SizedBox(height: 20),

                // ── How it works ──────────────────────────────────────────
                _SectionCard(
                  icon: Icons.help_outline_rounded,
                  iconColor: const Color(0xFF00BFFF),
                  title: 'How It Works',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Step('1', 'Enables MikroTik web proxy (port 8080)'),
                      _Step('2', 'Adds a firewall NAT rule: HTTP traffic from overdue clients → proxy'),
                      _Step('3', 'Proxy shows your custom payment message in their browser'),
                      _Step('4', 'Tap "Apply Overdue Now" from the PPPoE screen to sync the client list'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Config Form ───────────────────────────────────────────
                _SectionCard(
                  icon: Icons.settings_rounded,
                  iconColor: const Color(0xFFBB86FC),
                  title: 'Payment Page Message',
                  child: Column(
                    children: [
                      _Field(ctrl: _businessCtrl, label: 'Business / ISP Name', icon: Icons.business_rounded),
                      const SizedBox(height: 10),
                      _Field(ctrl: _phoneCtrl, label: 'Contact Number', icon: Icons.phone_rounded, hint: '09XX-XXX-XXXX'),
                      const SizedBox(height: 10),
                      _Field(ctrl: _gcashCtrl, label: 'GCash Number', icon: Icons.account_balance_wallet_rounded, hint: '09XX-XXX-XXXX'),
                      const SizedBox(height: 10),
                      _Field(ctrl: _bankCtrl, label: 'Bank / Other Payment', icon: Icons.account_balance_rounded, hint: 'BPI / BDO account details'),
                      const SizedBox(height: 10),
                      _Field(ctrl: _messageCtrl, label: 'Custom Message', icon: Icons.message_rounded,
                          hint: 'e.g. Thank you for your patience!', maxLines: 3),
                      const SizedBox(height: 14),

                      // ── Notice Timeout Selector ───────────────────────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '⏱️ Notice Duration (Auto-Restore Internet After):',
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D0D1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedTimeout,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF18182A),
                                style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                                items: const [
                                  DropdownMenuItem(
                                    value: '00:00:01',
                                    child: Text('⚡ 1 Second (Instant Redirect Test)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:00:10',
                                    child: Text('⚡ 10 Seconds (Quick Test Notice)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:01:00',
                                    child: Text('⏱️ 1 Minute (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:02:00',
                                    child: Text('⏱️ 2 Minutes (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:05:00',
                                    child: Text('⏱️ 5 Minutes (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:10:00',
                                    child: Text('⏱️ 10 Minutes (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:15:00',
                                    child: Text('⏱️ 15 Minutes (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '00:30:00',
                                    child: Text('⏱️ 30 Minutes (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '01:00:00',
                                    child: Text('⏱️ 1 Hour (Shows Notice, then Restores Internet)'),
                                  ),
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text('⛔ Permanent (Blocked until Paid / Cleared)'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedTimeout = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showPreview,
                          icon: const Icon(Icons.preview_rounded, size: 18),
                          label: Text('Preview Client Message', style: GoogleFonts.poppins(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00BFFF),
                            side: const BorderSide(color: Color(0xFF00BFFF)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Overdue Clients ───────────────────────────────────────
                _SectionCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.redAccent,
                  title: 'Overdue Clients (${widget.overdueUsers.length})',
                  child: widget.overdueUsers.isEmpty
                      ? Text('No overdue clients right now ✅',
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 13))
                      : Column(
                          children: [
                            ...widget.overdueUsers.map((u) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.circle, size: 8, color: Colors.redAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(u.name,
                                            style: GoogleFonts.poppins(
                                                fontSize: 13, color: Colors.white)),
                                      ),
                                      if (u.isOnline)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                          ),
                                          child: Text('ONLINE',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 9, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                )),
                            if (_hasSynced) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.redAccent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$_syncedCount online overdue client(s) are now redirected.',
                                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 24),

                // ── Action Buttons ────────────────────────────────────────
                if (_isBusy)
                  const Center(child: CircularProgressIndicator(color: Color(0xFF00BFFF)))
                else
                  Column(
                    children: [
                      // Install / Update
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _install,
                          icon: Icon(
                            _isInstalled ? Icons.update_rounded : Icons.download_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: Text(
                            _isInstalled ? 'Update Redirect Config' : '⚡ Install to Router',
                            style: GoogleFonts.poppins(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFFF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Apply overdue now
                      if (_isInstalled)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _applyOverdueNow,
                            icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 20),
                            label: Text(
                              '🔴 Apply Overdue Now (${widget.overdueUsers.length} clients)',
                              style: GoogleFonts.poppins(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      if (_isInstalled) const SizedBox(height: 10),

                      // Clear overdue (restore all)
                      if (_isInstalled)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _clearOverdue,
                            icon: const Icon(Icons.restore_rounded, size: 18),
                            label: Text('✅ Restore All (Clear Redirect List)',
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00E676),
                              side: const BorderSide(color: Color(0xFF00E676)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      if (_isInstalled) const SizedBox(height: 10),

                      // Remove all
                      if (_isInstalled)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _uninstall,
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            label: Text('Remove All from Router',
                                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 32),

                // ── RouterOS Info Box ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFFF).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00BFFF).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF00BFFF)),
                          const SizedBox(width: 6),
                          Text('What gets installed on the router:',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: const Color(0xFF00BFFF), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _CodeLine('/ip firewall address-list → pppoe-overdue'),
                      _CodeLine('/ip firewall nat → dstnat port 80 → webproxy'),
                      _CodeLine('/ip web-proxy → enabled on port 8080'),
                      _CodeLine('/ip web-proxy access → deny + custom message'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }
}

// ─── Helper Widgets ────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final bool isInstalled;
  const _StatusBanner({required this.isInstalled});

  @override
  Widget build(BuildContext context) {
    final color = isInstalled ? const Color(0xFF00E676) : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isInstalled ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInstalled ? 'Redirect is ACTIVE on Router' : 'Not Installed',
                  style: GoogleFonts.poppins(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  isInstalled
                      ? 'Overdue clients\' HTTP browsing will show your payment message.'
                      : 'Install the redirect to begin blocking overdue clients.',
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  const _SectionCard({required this.icon, required this.iconColor, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18182A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step(this.num, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF00BFFF).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF00BFFF))),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final String? hint;
  final int maxLines;
  const _Field({required this.ctrl, required this.label, required this.icon, this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
        labelStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF00BFFF)),
        filled: true,
        fillColor: const Color(0xFF0D0D1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00BFFF), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  final String text;
  const _CodeLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Text('▸ ', style: TextStyle(color: Color(0xFF00BFFF), fontSize: 11)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.sourceCodePro(fontSize: 10, color: Colors.white54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _PaymentBox({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: GoogleFonts.poppins(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
