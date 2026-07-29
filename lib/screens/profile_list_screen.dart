import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/mikrotik_service.dart';
import '../models/user_profile.dart';

class ProfileListScreen extends StatefulWidget {
  final MikrotikService service;
  const ProfileListScreen({super.key, required this.service});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  List<UserProfile> _profiles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.service.getFullProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _showAddEditModal([UserProfile? profile]) {
    final nameCtrl = TextEditingController(text: profile?.name ?? '');
    final rateCtrl = TextEditingController(text: profile?.rateLimit ?? '');
    final sharedCtrl = TextEditingController(text: profile?.sharedUsers ?? '1');
    
    String dataLimitUnit = 'None';
    final dataLimitCtrl = TextEditingController();
    
    final scriptContent = profile?.onLogin ?? '';
    final limitMatch = RegExp(r'/ip hotspot user set \[find name=\$user\] limit-bytes-total=(\d+);').firstMatch(scriptContent);
    if (limitMatch != null) {
      final bytes = int.tryParse(limitMatch.group(1)!);
      if (bytes != null) {
        if (bytes % 1073741824 == 0) {
          dataLimitUnit = 'GB';
          dataLimitCtrl.text = (bytes ~/ 1073741824).toString();
        } else if (bytes % 1048576 == 0) {
          dataLimitUnit = 'MB';
          dataLimitCtrl.text = (bytes ~/ 1048576).toString();
        }
      }
    }
    
    String cleanScript = scriptContent.replaceAll(RegExp(r':delay 1s;\s*:local currentlimit \[/ip hotspot user get \[find name=\$user\] limit-bytes-total\];\s*:if \([^)]+\) do=\{\s*(?::log info \("Setting [^"]*" \. \$user\);\s*)?/ip hotspot user set \[find name=\$user\] limit-bytes-total=\d+;\s*/ip hotspot active remove \[find user=\$user\];\s*\}\s*'), '').trim();
    
    // Remove auto-generated validity script for UI display
    cleanScript = cleanScript.replaceAll(RegExp(r'# --- Auto-Generated Validity Script ---[\s\S]*?# --- End Auto-Generated Validity Script ---\s*'), '').trim();
    
    final onLoginCtrl = TextEditingController(text: cleanScript);
    final onLogoutCtrl = TextEditingController(text: profile?.onLogout ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF161626),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
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
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              profile == null ? 'Add User Profile' : 'Edit Profile',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            if (profile != null && profile.name != 'default')
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFFF5252)),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  _deleteProfile(profile);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Name
                        TextFormField(
                          controller: nameCtrl,
                          style: GoogleFonts.poppins(color: Colors.white),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter profile name' : null,
                          decoration: InputDecoration(
                            labelText: 'Profile Name',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: 'e.g. 5M-1Hours-Promo',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Rate Limit
                        TextFormField(
                          controller: rateCtrl,
                          style: GoogleFonts.poppins(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Rate Limit (Rx/Tx)',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: 'e.g. 2M/5M (Optional)',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Shared Users
                        TextFormField(
                          controller: sharedCtrl,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.poppins(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Shared Users (Concurrent Logins)',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: '1',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Data Limit
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: dataLimitCtrl,
                                keyboardType: TextInputType.number,
                                enabled: dataLimitUnit != 'None',
                                style: GoogleFonts.poppins(
                                  color: dataLimitUnit != 'None' ? Colors.white : Colors.white24,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'Data Limit',
                                  labelStyle: GoogleFonts.poppins(color: Colors.white60),
                                  hintText: dataLimitUnit == 'None' ? 'Unlimited' : 'Amount',
                                  hintStyle: GoogleFonts.poppins(color: Colors.white24),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: dataLimitUnit,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF161626),
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white60),
                                    style: GoogleFonts.poppins(color: Colors.white),
                                    items: ['None', 'MB', 'GB']
                                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(() {
                                          dataLimitUnit = val;
                                          if (val == 'None') {
                                            dataLimitCtrl.clear();
                                          }
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // On Login Script
                        TextFormField(
                          controller: onLoginCtrl,
                          maxLines: 3,
                          style: GoogleFonts.firaCode(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            labelText: 'On Login Script (Optional)',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: 'MikroTik script code executed on user login...',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // On Logout Script
                        TextFormField(
                          controller: onLogoutCtrl,
                          maxLines: 3,
                          style: GoogleFonts.firaCode(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            labelText: 'On Logout Script (Optional)',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: 'MikroTik script code executed on user logout...',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) return;
                                    setModalState(() => saving = true);
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      String finalOnLogin = onLoginCtrl.text.trim();
                                      
                                      final validityScript = '''
# --- Auto-Generated Validity Script ---
:local uComment [/ip hotspot user get [find name=\$user] comment];
:local valPos [:find \$uComment "val:"];
:if ([:typeof \$valPos] = "num") do={
    :local valEnd [:find \$uComment " " \$valPos];
    :if ([:typeof \$valEnd] = "nil") do={ :set valEnd [:len \$uComment]; }
    :local valStr [:pick \$uComment (\$valPos+4) \$valEnd];
    :local interval "0s";
    :if ([:find \$valStr "d"] >= 0) do={ :set interval ([:pick \$valStr 0 [:find \$valStr "d"]] . "d"); }
    :if ([:find \$valStr "h"] >= 0) do={ :set interval ([:pick \$valStr 0 [:find \$valStr "h"]] . "h"); }
    :local schedName ("exp_" . \$user);
    :local onEvent ("/ip hotspot user set [find name=\\"" . \$user . "\\"] comment=([/ip hotspot user get [find name=\\"" . \$user . "\\"] comment] . \" expired\"); /ip hotspot user disable [find name=\\"" . \$user . "\\"]; /ip hotspot active remove [find user=\\"" . \$user . "\\"]; /system scheduler remove [find name=\\"" . \$schedName . "\\"];");
    /system scheduler add name=\$schedName interval=\$interval start-date=[/system clock get date] start-time=[/system clock get time] on-event=\$onEvent;
    :delay 1s;
    :local nextRun [/system scheduler get [find name=\$schedName] next-run];
    :local nextDate [:pick \$nextRun 0 [:find \$nextRun " "]];
    :local nextTime [:pick \$nextRun ([:find \$nextRun " "] + 1) [:len \$nextRun]];
    :local newComment ([:pick \$uComment 0 \$valPos] . "exp:" . \$nextDate . "/" . \$nextTime . " log:" . [/system clock get date] . "/" . [/system clock get time] . [:pick \$uComment \$valEnd [:len \$uComment]]);
    /ip hotspot user set [find name=\$user] comment=\$newComment;
} else={
    :local logPos [:find \$uComment "log:"];
    :local expPos [:find \$uComment "exp:"];
    :if ([:typeof \$expPos] != "num" && [:typeof \$logPos] != "num") do={
        :local newComment (\$uComment . " log:" . [/system clock get date] . "/" . [/system clock get time]);
        /ip hotspot user set [find name=\$user] comment=\$newComment;
    }
}
# --- End Auto-Generated Validity Script ---''';

                                      if (!finalOnLogin.contains("Auto-Generated Validity Script")) {
                                        finalOnLogin = '$validityScript\n$finalOnLogin'.trim();
                                      }

                                      if (dataLimitUnit != 'None' && dataLimitCtrl.text.trim().isNotEmpty) {
                                        final val = int.tryParse(dataLimitCtrl.text.trim()) ?? 0;
                                        if (val > 0) {
                                          final multiplier = dataLimitUnit == 'GB' ? 1073741824 : 1048576;
                                          final bytes = val * multiplier;
                                          final scriptBlock = '''
:delay 1s;
:local currentlimit [/ip hotspot user get [find name=\$user] limit-bytes-total];
:if (\$currentlimit = 0 || \$currentlimit < $bytes) do={
    :log info ("Setting $val$dataLimitUnit limit and restarting session for: " . \$user);
    /ip hotspot user set [find name=\$user] limit-bytes-total=$bytes;
    /ip hotspot active remove [find user=\$user];
}''';
                                          finalOnLogin = '$scriptBlock\n$finalOnLogin'.trim();
                                        }
                                      }

                                      if (profile == null) {
                                        await widget.service.addProfile(
                                          name: nameCtrl.text.trim(),
                                          rateLimit: rateCtrl.text.trim(),
                                          sharedUsers: sharedCtrl.text.trim(),
                                          onLogin: finalOnLogin,
                                          onLogout: onLogoutCtrl.text.trim(),
                                        );
                                      } else {
                                        await widget.service.updateProfile(
                                          id: profile.id,
                                          name: nameCtrl.text.trim(),
                                          rateLimit: rateCtrl.text.trim(),
                                          sharedUsers: sharedCtrl.text.trim(),
                                          onLogin: finalOnLogin,
                                          onLogout: onLogoutCtrl.text.trim(),
                                        );
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      _loadProfiles();
                                    } catch (e) {
                                      setModalState(() => saving = false);
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00BFFF),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: saving
                                ? const SpinKitThreeBounce(color: Colors.white, size: 20)
                                : Text(
                                    profile == null ? 'Save Profile' : 'Update Profile',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
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
          },
        );
      },
    );
  }

  Future<void> _deleteProfile(UserProfile profile) async {
    try {
      await widget.service.removeProfile(profile.id);
      _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Delete failed: $e', backgroundColor: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161626),
        title: Text(
          'Hotspot User Profiles',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadProfiles,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditModal(),
        backgroundColor: const Color(0xFF00BFFF),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Add Profile',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: SpinKitFadingCube(color: Color(0xFF00BFFF), size: 36),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: GoogleFonts.poppins(color: Colors.redAccent),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfiles,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _profiles.length,
                    itemBuilder: (context, i) {
                      final p = _profiles[i];
                      final hasScripts =
                          p.onLogin.isNotEmpty || p.onLogout.isNotEmpty;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161626),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onTap: () => _showAddEditModal(p),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B2FBE).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.style_rounded,
                              color: Color(0xFFBB86FC),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                if (p.rateLimit.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00BFFF)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      p.rateLimit,
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: const Color(0xFF00BFFF),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  'Shared Users: ${p.sharedUsers}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasScripts)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF9800)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.code_rounded,
                                    color: Color(0xFFFF9800),
                                    size: 14,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white38,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

