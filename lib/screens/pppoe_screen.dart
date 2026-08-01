import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mikrotik_service.dart';
import '../services/pppoe_billing_service.dart';
import '../services/auto_sms_service.dart';
import '../models/pppoe_user.dart';


class PppoeScreen extends StatefulWidget {
  final MikrotikService service;
  const PppoeScreen({super.key, required this.service});

  @override
  State<PppoeScreen> createState() => _PppoeScreenState();
}

class _PppoeScreenState extends State<PppoeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;

  List<PppoeUser> _secrets = [];
  List<PppoeActiveSession> _activeSessions = [];
  List<String> _profiles = [];

  String _searchQuery = '';
  String _dashFilter = ''; // '', 'online', 'overdue', 'duesoon'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final secrets = await widget.service.getPppoeSecrets();
      final active = await widget.service.getPppoeActive();
      final profiles = await widget.service.getPppProfiles();
      final billingMap = await PppoeBillingService.loadBillingMap();

      final activeNames = active.map((a) => a.name.toLowerCase()).toSet();
      final activeMap = {for (var a in active) a.name.toLowerCase(): a};

      final mergedSecrets = secrets.map((s) {
        final isOnline = activeNames.contains(s.name.toLowerCase());
        final session = activeMap[s.name.toLowerCase()];
        final billing = billingMap[s.name.toLowerCase()];

        DateTime? finalDueDate = billing?.dueDate;
        if (finalDueDate == null && s.comment.isNotEmpty) {
          final match = RegExp(r'Due:\s*(\d{4}-\d{2}-\d{2})', caseSensitive: false).firstMatch(s.comment);
          if (match != null) {
            finalDueDate = DateTime.tryParse(match.group(1)!);
          }
        }

        return s.copyWith(
          isOnline: isOnline,
          callerId: session?.callerId ?? '',
          uptime: session?.uptime ?? '',
          dueDate: finalDueDate,
          monthlyFee: billing?.monthlyFee ?? 0.0,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _secrets = mergedSecrets;
          _activeSessions = active;
          _profiles = profiles;
          _isLoading = false;
        });

        // Cache a snapshot of due users so the periodic background reminder
        // check (started from the dashboard) can run without a live router
        // connection, then fire an immediate pass for this screen.
        AutoSmsService.saveReminderSnapshot(mergedSecrets);
        AutoSmsService.checkAndSendAutoReminders(mergedSecrets).then((sentCount) {
          if (sentCount > 0 && mounted) {
            TopToast.show(
              context,
              '📱 Automatically sent $sentCount payment reminder SMS!',
              backgroundColor: const Color(0xFF34A853),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  int get _onlineCount => _secrets.where((s) => s.isOnline).length;
  int get _overdueCount => _secrets.where((s) => s.isOverdue).length;
  int get _dueSoonCount => _secrets.where((s) => s.isDueSoon).length;

  Future<void> _markPaidAndExtend(PppoeUser user) async {
    final newDueDate = await PppoeBillingService.extendDueDateByOneMonth(
      user.name,
      currentDueDate: user.dueDate,
    );

    if (newDueDate != null) {
      // Sync the new due date into the MikroTik router comment field
      final dateStr =
          "Due: ${newDueDate.year}-${newDueDate.month.toString().padLeft(2, '0')}-${newDueDate.day.toString().padLeft(2, '0')}";
      String updatedComment = user.comment;
      if (!updatedComment.toLowerCase().contains("due:")) {
        updatedComment = updatedComment.isEmpty ? dateStr : "$updatedComment | $dateStr";
      } else {
        updatedComment = updatedComment.replaceAll(
          RegExp(r'Due:\s*\d{4}-\d{2}-\d{2}', caseSensitive: false),
          dateStr,
        );
      }

      try {
        await widget.service.updatePppoeSecret(
          id: user.id,
          name: user.name,
          password: user.password,
          profile: user.profile,
          remoteAddress: user.remoteAddress,
          comment: updatedComment,
        );
      } catch (_) {
        // Router comment update is best-effort; billing is already saved
      }
    }

    final formattedDate = newDueDate != null
        ? "${newDueDate.year}-${newDueDate.month.toString().padLeft(2, '0')}-${newDueDate.day.toString().padLeft(2, '0')}"
        : "—";

    if (mounted) {
      TopToast.show(context, 'Payment recorded for ${user.name}! Next due: $formattedDate 🎉', backgroundColor: const Color(0xFF00E676));
    }
    _loadData();
  }

  Future<void> _disableAllOverdue() async {
    final overdueList = _secrets.where((s) => s.isOverdue && !s.disabled).toList();
    if (overdueList.isEmpty) {
      TopToast.show(context, 'No active overdue clients to disable.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Disable ${overdueList.length} Overdue Clients?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will disable the PPPoE secret and disconnect active sessions for all ${overdueList.length} overdue accounts.',
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
            child: Text('Disable All', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      int disabledCount = 0;
      for (final user in overdueList) {
        try {
          await widget.service.togglePppoeSecret(user.id, true, username: user.name);
          disabledCount++;
        } catch (_) {}
      }
      await _loadData();
      if (mounted) {
        TopToast.show(context, 'Successfully disabled $disabledCount overdue PPPoE clients! 🔴', backgroundColor: Colors.redAccent);
      }
    }
  }


  /// Normalizes a PH mobile number to the international form WhatsApp's
  /// wa.me/number requires: digits only, no leading '+', no leading '0'.
  /// `09XXXXXXXXX` → `639XXXXXXXXX`; `+639XXXXXXXXX` → `639XXXXXXXXX`.
  /// Returns null if [raw] is null/empty/not a valid PH mobile.
  String? _normalizePhoneForWa(String? raw) {
    if (raw == null) return null;
    var s = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('09')) s = '639${s.substring(2)}';
    // Valid PH international mobile: '63' + 10 digits (9XXXXXXXXX) = 12 digits.
    if (s.length == 12 && s.startsWith('639')) return s;
    return null;
  }

  Future<void> _launchSms(String text) async {
    final Uri uri = Uri.parse("sms:?body=${Uri.encodeComponent(text)}");
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Opens a pre-filled WhatsApp chat to [phone] (if a valid number can be
  /// extracted via [_normalizePhoneForWa]); otherwise falls back to the WhatsApp
  /// chat picker so the operator can choose a contact manually.
  Future<void> _launchWhatsApp(String text, {String? phone}) async {
    final intl = _normalizePhoneForWa(phone);
    final base = intl == null ? 'https://wa.me/?' : 'https://wa.me/$intl?';
    final Uri uri = Uri.parse('${base}text=${Uri.encodeComponent(text)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  /// Opens the OS share sheet so the operator can pick Messenger, Viber, SMS,
  /// or any installed app to send the reminder. Works even when we don't have
  /// (and can't use) the recipient's number for a deep link — e.g. Messenger,
  /// which keys on a Facebook username, not a phone number.
  Future<void> _launchShareReminder(String text) async {
    try {
      await Share.share(text, subject: 'PPPoE Payment Reminder');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  void _showPaymentReminderModal(PppoeUser user) {
    final dateStr = user.dueDate != null
        ? "${user.dueDate!.year}-${user.dueDate!.month.toString().padLeft(2, '0')}-${user.dueDate!.day.toString().padLeft(2, '0')}"
        : "monthly due date";
    final amountStr = user.monthlyFee > 0 ? "₱${user.monthlyFee.toStringAsFixed(0)}" : "monthly internet bill";

    final text = "Hi ${user.name},\n"
        "This is a friendly payment reminder for your PPPoE Internet subscription ($amountStr) due on $dateStr.\n"
        "Please settle your payment to avoid service interruption.\nThank you!";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.mark_email_read_rounded, color: Color(0xFF00BFFF)),
            const SizedBox(width: 10),
            Text('Payment Reminder', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: SelectableText(
            text,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.message_rounded, color: Color(0xFF00E676)),
            tooltip: 'Send via SMS',
            onPressed: () {
              Navigator.pop(ctx);
              _launchSms(text);
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366)),
            tooltip: 'Send via WhatsApp${user.phoneNumber != null ? " (to ${user.phoneNumber})" : ""}',
            onPressed: () {
              Navigator.pop(ctx);
              _launchWhatsApp(text, phone: user.phoneNumber);
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFF0084FF)),
            tooltip: 'Share via Messenger / Viber / other apps',
            onPressed: () {
              Navigator.pop(ctx);
              _launchShareReminder(text);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFFF)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              TopToast.show(context, 'Payment reminder copied to clipboard! 📋');
            },
            icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
            label: Text('Copy Text', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Ensures the SMS permission is granted before enabling/using Auto SMS.
  /// - If already granted → returns true.
  /// - If not yet permanently denied → requests it.
  /// - If permanently denied → shows a dialog offering to open system Settings,
  ///   which is the ONLY way to re-enable the (greyed-out) SMS permission.
  ///
  /// This fixes "Allowed is disabled": when the system permission dialog can no
  /// longer appear, the app must send the user to Settings explicitly.
  Future<bool> _ensureSmsPermissionOrExplain(BuildContext modalCtx) async {
    final granted = await AutoSmsService.requestPermission();
    if (granted) return true;

    final permanentlyDenied = await AutoSmsService.isPermanentlyDenied();
    if (!modalCtx.mounted) return false;

    await showDialog(
      context: modalCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.sms_failed_rounded, color: Color(0xFFFF9800), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('SMS Permission Required',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
        content: Text(
          permanentlyDenied
              ? 'SMS access was denied permanently. Android can no longer show the permission prompt here. Open App Settings and enable "SMS" to allow sending payment reminders.'
              : 'Auto SMS needs permission to send payment reminders from your SIM. Please grant SMS access to continue.',
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, !permanentlyDenied),
            icon: Icon(
              permanentlyDenied ? Icons.settings_rounded : Icons.check_circle_outline_rounded,
              size: 16,
            ),
            label: Text(permanentlyDenied ? 'Open Settings' : 'Grant',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );

    if (permanentlyDenied) {
      // Must redirect to Settings — nothing more we can do programmatically.
      await openAppSettings();
      return false;
    }

    // User tapped "Grant" → show the system permission dialog and wait for the result.
    final result = await Permission.sms.request();
    return result.isGranted;
  }


  Future<void> _showAutoSmsSettingsModal() async {
    bool enabled = await AutoSmsService.isEnabled();
    int daysBefore = await AutoSmsService.getDaysBefore();
    String template = await AutoSmsService.getTemplate();
    // If the feature is enabled but the permission was later revoked in system
    // Settings, we must reflect that so the toggle and test button behave
    // correctly (and show the "Open Settings" path).
    // Only CHECK the current status — never request here. The system dialog
    // must only appear when the user explicitly taps the toggle ON or "Grant".
    // Requesting on modal open caused unexpected Android dialogs that users
    // denied (sometimes permanently) before they understood the feature.
    bool hasPermission = Platform.isAndroid
        ? (await Permission.sms.status).isGranted
        : false;

    final tplCtrl = TextEditingController(text: template);
    final testPhoneCtrl = TextEditingController();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF141426),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Color(0xFF00E676), width: 1.5)),
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.mark_as_unread_rounded, color: Color(0xFF00E676), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Automated SMS Settings',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    activeThumbColor: const Color(0xFF00E676),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Enable Auto SMS Reminders',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      hasPermission
                          ? 'Automatically sends SMS using your SIM load when PPPoE bill is due.'
                          : '⚠️ SMS permission missing — tap to grant access, otherwise reminders won\'t send.',
                      style: GoogleFonts.poppins(
                        color: hasPermission ? Colors.white54 : const Color(0xFFFFB74D),
                        fontSize: 12,
                      ),
                    ),
                    value: enabled,
                    onChanged: (val) async {
                      if (val) {
                        // Turning ON requires the SMS permission. If it can't
                        // be obtained, explain why (and offer Settings) instead
                        // of silently flipping the toggle on.
                        final ok = await _ensureSmsPermissionOrExplain(ctx);
                        if (!ok) return;
                        await AutoSmsService.setEnabled(true);
                        setModalState(() {
                          enabled = true;
                          hasPermission = true;
                        });
                      } else {
                        await AutoSmsService.setEnabled(false);
                        setModalState(() => enabled = false);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Send Reminder When:',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: daysBefore,
                        dropdownColor: const Color(0xFF18182A),
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('On Due Date', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 1, child: Text('1 Day Before Due Date', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 2, child: Text('2 Days Before Due Date', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 3, child: Text('3 Days Before Due Date', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (val) async {
                          if (val != null) {
                            await AutoSmsService.setDaysBefore(val);
                            setModalState(() => daysBefore = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SMS Message Template:',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Placeholders: {name}, {amount}, {date}, {days}',
                    style: GoogleFonts.poppins(color: const Color(0xFF00BFFF), fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tplCtrl,
                    maxLines: 3,
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00E676))),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Send Test SMS:',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: testPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'e.g. 09171234567',
                            hintStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white30),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.04),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final phone = testPhoneCtrl.text.trim();
                          if (phone.isEmpty) {
                            TopToast.show(ctx, 'Please enter a test phone number', backgroundColor: Colors.redAccent);
                            return;
                          }
                          // Ensure permission before sending; if missing, the
                          // helper explains (and offers Settings) and we abort.
                          final granted = await _ensureSmsPermissionOrExplain(ctx);
                          if (!granted) return;
                          setModalState(() => hasPermission = true);
                          final msg = tplCtrl.text
                              .replaceAll('{name}', 'Test Client')
                              .replaceAll('{amount}', '500')
                              .replaceAll('{date}', '2026-08-01')
                              .replaceAll('{days}', '1');
                          final ok = await AutoSmsService.sendDirectSms(phone: phone, message: msg);
                          if (!ctx.mounted) return;
                          if (ok) {
                            TopToast.show(ctx, '✅ Test SMS sent to $phone!', backgroundColor: const Color(0xFF34A853));
                          } else {
                            TopToast.show(ctx, '❌ Failed to send SMS. Check SMS permission.', backgroundColor: Colors.redAccent);
                          }
                        },
                        child: Text('Test', style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        await AutoSmsService.setTemplate(tplCtrl.text.trim());
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        TopToast.show(ctx, '✅ Auto SMS Settings saved!', backgroundColor: const Color(0xFF34A853));
                      },
                      child: Text(
                        'Save Settings',
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<PppoeUser> get _filteredSecrets {
    var list = _secrets;
    // Apply dash filter first
    if (_dashFilter == 'online') {
      list = list.where((s) => s.isOnline).toList();
    } else if (_dashFilter == 'overdue') {
      list = list.where((s) => s.isOverdue).toList();
    } else if (_dashFilter == 'duesoon') {
      list = list.where((s) => s.isDueSoon).toList();
    }
    // Then apply search query
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.comment.toLowerCase().contains(q) ||
          s.remoteAddress.contains(q) ||
          s.profile.toLowerCase().contains(q);
    }).toList();
  }

  List<PppoeActiveSession> get _filteredActive {
    if (_searchQuery.isEmpty) return _activeSessions;
    final q = _searchQuery.toLowerCase();
    return _activeSessions.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.address.contains(q) ||
          a.callerId.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _toggleDisable(PppoeUser user) async {
    try {
      await widget.service.togglePppoeSecret(user.id, !user.disabled, username: user.name);
      _loadData();
    } catch (e) {
      if (mounted) {
        TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), backgroundColor: Colors.redAccent);
      }
    }
  }

  Future<void> _deleteUser(PppoeUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18182A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete PPPoE Client?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete user "${user.name}"?',
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
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.removePppoeSecret(user.id);
        _loadData();
      } catch (e) {
        if (mounted) {
          TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), backgroundColor: Colors.redAccent);
        }
      }
    }
  }

  Future<void> _disconnectActive(PppoeActiveSession session) async {
    try {
      await widget.service.disconnectPppoeActive(session.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), backgroundColor: Colors.redAccent);
      }
    }
  }

  void _openAddEditModal({PppoeUser? userToEdit}) {
    final nameCtrl = TextEditingController(text: userToEdit?.name ?? '');
    final passCtrl = TextEditingController(text: userToEdit?.password ?? '');
    final ipCtrl = TextEditingController(text: userToEdit?.remoteAddress ?? '');
    final commentCtrl = TextEditingController(text: userToEdit?.comment ?? '');
    final feeCtrl = TextEditingController(
      text: (userToEdit != null && userToEdit.monthlyFee > 0)
          ? userToEdit.monthlyFee.toStringAsFixed(0)
          : '',
    );
    // Wrap in a List so the value persists across StatefulBuilder rebuilds
    final dueDateHolder = <DateTime?>[userToEdit?.dueDate];

    String selectedProfile = (userToEdit != null && _profiles.contains(userToEdit.profile))
        ? userToEdit.profile
        : (_profiles.isNotEmpty ? _profiles.first : 'default');

    bool obscurePass = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF141426),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: Color(0xFF00BFFF), width: 1.5)),
            ),
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
                const SizedBox(height: 12),
                Text(
                  userToEdit != null ? 'Edit PPPoE Account' : 'Add PPPoE Account',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInputField(
                          controller: nameCtrl,
                          label: 'Username',
                          hint: 'e.g. client_john',
                          icon: Icons.person_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: passCtrl,
                          label: 'Password',
                          hint: '••••••••',
                          icon: Icons.lock_rounded,
                          obscureText: obscurePass,
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                            onPressed: () => setModalState(() => obscurePass = !obscurePass),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'PPP Profile',
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
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
                            child: DropdownButton<String>(
                              value: selectedProfile,
                              dropdownColor: const Color(0xFF1A1A2E),
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                              items: _profiles.map((p) {
                                return DropdownMenuItem(
                                  value: p,
                                  child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => selectedProfile = val);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInputField(
                                controller: feeCtrl,
                                label: 'Monthly Rate (₱)',
                                hint: '1500',
                                icon: Icons.payments_rounded,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Next Due Date', style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: dueDateHolder[0] ?? DateTime.now().add(const Duration(days: 30)),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2035),
                                      );
                                      if (picked != null) {
                                        setModalState(() => dueDateHolder[0] = picked);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      height: 48,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today_rounded, size: 16, color: Colors.white54),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              dueDateHolder[0] != null
                                                  ? "${dueDateHolder[0]!.year}-${dueDateHolder[0]!.month.toString().padLeft(2, '0')}-${dueDateHolder[0]!.day.toString().padLeft(2, '0')}"
                                                  : 'Select Date',
                                              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (dueDateHolder[0] != null)
                                            GestureDetector(
                                              onTap: () => setModalState(() => dueDateHolder[0] = null),
                                              child: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: ipCtrl,
                          label: 'Remote IP Address (Optional)',
                          hint: '192.168.10.50',
                          icon: Icons.alt_route_rounded,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: commentCtrl,
                          label: 'Comment / Client Notes',
                          hint: 'House #12, Zone 3',
                          icon: Icons.notes_rounded,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final pass = passCtrl.text;
                      if (name.isEmpty || pass.isEmpty) {
                        TopToast.show(context, 'Username and password are required');
                        return;
                      }

                      final selectedDueDate = dueDateHolder[0];
                      String userComment = commentCtrl.text.trim();
                      if (selectedDueDate != null) {
                        final dateStr = "Due: ${selectedDueDate.year}-${selectedDueDate.month.toString().padLeft(2, '0')}-${selectedDueDate.day.toString().padLeft(2, '0')}";
                        if (!userComment.toLowerCase().contains("due:")) {
                          userComment = userComment.isEmpty ? dateStr : "$userComment | $dateStr";
                        } else {
                          userComment = userComment.replaceAll(RegExp(r'Due:\s*\d{4}-\d{2}-\d{2}', caseSensitive: false), dateStr);
                        }
                      } else {
                        // Clear the Due: tag from comment if date was reset
                        userComment = userComment.replaceAll(RegExp(r'\s*\|?\s*Due:\s*\d{4}-\d{2}-\d{2}', caseSensitive: false), '').trim();
                      }

                      Navigator.pop(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        if (userToEdit != null) {
                          await widget.service.updatePppoeSecret(
                            id: userToEdit.id,
                            name: name,
                            password: pass,
                            profile: selectedProfile,
                            remoteAddress: ipCtrl.text.trim(),
                            comment: userComment,
                          );
                        } else {
                          await widget.service.addPppoeSecret(
                            name: name,
                            password: pass,
                            profile: selectedProfile,
                            remoteAddress: ipCtrl.text.trim(),
                            comment: userComment,
                          );
                        }

                        final fee = double.tryParse(feeCtrl.text.trim()) ?? 0.0;
                        await PppoeBillingService.saveClientBilling(name, dueDateHolder[0], fee);
                        if (userToEdit != null && userToEdit.name.toLowerCase() != name.toLowerCase()) {
                          await PppoeBillingService.saveClientBilling(userToEdit.name, selectedDueDate, fee);
                        }

                        _loadData();
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString().replaceFirst('Exception: ', '')),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_rounded, color: Colors.white),
                    label: Text(
                      userToEdit != null ? 'Update Account' : 'Create Account',
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFFF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.white30),
            prefixIcon: Icon(icon, size: 18, color: Colors.white54),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00BFFF)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141426),
        elevation: 0,
        title: Text(
          'PPPoE Client Management',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mark_as_unread_rounded, color: Color(0xFF00E676)),
            tooltip: 'Automated SMS Settings',
            onPressed: _showAutoSmsSettingsModal,
          ),
          if (_overdueCount > 0)
            IconButton(
              icon: const Icon(Icons.block_rounded, color: Colors.redAccent),
              tooltip: 'Disable All Overdue ($_overdueCount)',
              onPressed: _disableAllOverdue,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00BFFF),
          indicatorWeight: 3,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          labelColor: const Color(0xFF00BFFF),
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'Accounts (${_secrets.length})'),
            Tab(text: 'Active (${_activeSessions.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: SpinKitFadingCube(color: Color(0xFF00BFFF), size: 40),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, style: GoogleFonts.poppins(color: Colors.white70), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00BFFF)),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xFF141426),
                      child: Row(
                        children: [
                          _buildSummaryTile('Total', '${_secrets.length}', const Color(0xFF00BFFF), Icons.people_rounded, filterKey: ''),
                          const SizedBox(width: 6),
                          _buildSummaryTile('Online', '$_onlineCount', const Color(0xFF00E676), Icons.wifi_rounded, filterKey: 'online'),
                          const SizedBox(width: 6),
                          _buildSummaryTile('Overdue', '$_overdueCount', Colors.redAccent, Icons.error_outline_rounded, filterKey: 'overdue'),
                          const SizedBox(width: 6),
                          _buildSummaryTile('Due Soon', '$_dueSoonCount', const Color(0xFFFF9800), Icons.access_time_rounded, filterKey: 'duesoon'),
                        ],
                      ),
                    ),

                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search username, IP, profile, or comment...',
                          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.white30),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFF18182A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),

                    // Tab View Content
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 1: PPPoE Accounts (Secrets)
                          _buildSecretsList(),

                          // Tab 2: Active Sessions
                          _buildActiveList(),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEditModal(),
        backgroundColor: const Color(0xFF00BFFF),
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text('Add Client', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }

  Widget _buildSummaryTile(String title, String value, Color color, IconData icon, {required String filterKey}) {
    final isActive = _dashFilter == filterKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _dashFilter = isActive ? '' : filterKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.22) : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.3),
              width: isActive ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 10, color: isActive ? color : Colors.white54),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentBadge(PppoeUser u) {
    if (u.isOverdue) {
      final days = u.daysUntilDue!.abs();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        child: Text(
          '🔴 OVERDUE BY $days D${days > 1 ? "S" : ""}',
          style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
      );
    } else if (u.isDueSoon) {
      final days = u.daysUntilDue!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4)),
        ),
        child: Text(
          days == 0 ? '🟡 DUE TODAY' : '🟡 DUE IN $days D${days > 1 ? "S" : ""}',
          style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFFF9800)),
        ),
      );
    } else if (u.dueDate != null) {
      final d = u.dueDate!;
      final dateStr = "${d.month}/${d.day}";
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF00E676).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
        ),
        child: Text(
          '🟢 DUE $dateStr',
          style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF00E676)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSecretsList() {
    final list = _filteredSecrets;
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No PPPoE accounts found',
          style: GoogleFonts.poppins(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final u = list[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF18182A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: u.disabled
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : u.isOnline
                      ? const Color(0xFF00E676).withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: u.disabled
                      ? Colors.redAccent.withValues(alpha: 0.15)
                      : u.isOnline
                          ? const Color(0xFF00E676).withValues(alpha: 0.15)
                          : const Color(0xFF00BFFF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  u.disabled
                      ? Icons.block_rounded
                      : u.isOnline
                          ? Icons.wifi_rounded
                          : Icons.person_rounded,
                  color: u.disabled
                      ? Colors.redAccent
                      : u.isOnline
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00BFFF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          u.name,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7B2FBE).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            u.profile,
                            style: GoogleFonts.poppins(fontSize: 10, color: const Color(0xFFBB86FC), fontWeight: FontWeight.w600),
                          ),
                        ),
                        _buildPaymentBadge(u),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            u.remoteAddress.isNotEmpty ? 'IP: ${u.remoteAddress}' : 'IP: Auto (DHCP/Pool)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
                          ),
                        ),
                        if (u.monthlyFee > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '₱${u.monthlyFee.toStringAsFixed(0)}/mo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF00BFFF), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                    if (u.comment.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Notes: ${u.comment}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                    if (u.isOnline && u.uptime.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '🟢 Online • Uptime: ${u.uptime}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF00E676), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                color: const Color(0xFF141426),
                onSelected: (val) {
                  if (val == 'paid') _markPaidAndExtend(u);
                  if (val == 'remind') _showPaymentReminderModal(u);
                  if (val == 'edit') _openAddEditModal(userToEdit: u);
                  if (val == 'toggle') _toggleDisable(u);
                  if (val == 'delete') _deleteUser(u);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'paid',
                    child: Row(
                      children: [
                        const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF00E676)),
                        const SizedBox(width: 8),
                        Text('Mark Paid (+1 Month)', style: GoogleFonts.poppins(color: const Color(0xFF00E676), fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remind',
                    child: Row(
                      children: [
                        const Icon(Icons.mark_email_read_rounded, size: 18, color: Color(0xFF00BFFF)),
                        const SizedBox(width: 8),
                        Text('Payment Reminder', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text('Edit Account', style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(u.disabled ? Icons.check_circle_rounded : Icons.block_rounded,
                            size: 18, color: u.disabled ? const Color(0xFF00E676) : Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(u.disabled ? 'Enable Account' : 'Disable Account',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_rounded, size: 18, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text('Delete Account', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveList() {
    final list = _filteredActive;
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No active PPPoE sessions',
          style: GoogleFonts.poppins(color: Colors.white38),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (ctx, index) {
        final s = list[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF18182A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF00E676), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'IP: ${s.address}',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'MAC: ${s.callerId.isNotEmpty ? s.callerId : "N/A"} • Uptime: ${s.uptime}',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent),
                tooltip: 'Disconnect Session',
                onPressed: () => _disconnectActive(s),
              ),
            ],
          ),
        );
      },
    );
  }
}

