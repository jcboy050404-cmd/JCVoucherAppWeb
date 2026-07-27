import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mikrotik_service.dart';
import '../services/trial_service.dart';
import '../services/auth_service.dart';
import '../models/voucher.dart';
import '../widgets/print_preview_helper.dart';
import 'voucher_list_screen.dart';
import 'upgrade_screen.dart';

class GenerateScreen extends StatefulWidget {
  final MikrotikService service;
  const GenerateScreen({super.key, required this.service});

  @override
  State<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends State<GenerateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController(text: '1');
  final _commentController = TextEditingController();
  final _customPassController = TextEditingController();
  final _customUptimeNumController = TextEditingController();
  final _validityNumController = TextEditingController();
  final _priceController = TextEditingController();
  final _codeLengthController = TextEditingController(text: '6');

  int _count = 1;
  String _selectedProfile = 'default';
  List<String> _profiles = ['default'];
  bool _loadingProfiles = true;
  String _voucherFormatMode = 'code_only'; // 'code_only' or 'user_pass'
  final int _codeLength = 6;
  String _passwordMode = 'auto'; // 'auto', 'same_as_username', 'custom'
  String _selectedUptime = '';
  bool _isCustomUptime = false;
  String _customUptimeUnit = 'h'; // 'h' or 'd'
  String _validityUnit = 'd'; // 'h' or 'd'
  bool _generating = false;
  int _progressCurrent = 0;
  String? _errorMsg;

  final List<String> _uptimeOptions = [
    '',
    '1h',
    '2h',
    '4h',
    '8h',
    '12h',
    '1d',
    '3d',
    '7d',
    '30d',
  ];

  List<PackagePreset> _packagePresets = List.from(_defaultPackagePresets);

  Future<void> _loadSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('custom_package_presets');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = decoded
            .map((item) => PackagePreset.fromJson(item as Map<String, dynamic>))
            .toList();
        if (loaded.isNotEmpty) {
          if (mounted) setState(() => _packagePresets = loaded);
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _packagePresets = List.from(_defaultPackagePresets));
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_packagePresets.map((p) => p.toJson()).toList());
    await prefs.setString('custom_package_presets', jsonStr);
  }

  void _applyPreset(PackagePreset preset) {
    setState(() {
      _priceController.text = preset.price;
      _isCustomUptime = false;
      _selectedUptime = preset.uptime;
      _customUptimeNumController.clear();
      _validityNumController.text = preset.validityNum;
      _validityUnit = preset.validityUnit;
      if (preset.profile.isNotEmpty && _profiles.contains(preset.profile)) {
        _selectedProfile = preset.profile;
      }
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

  }

  void _openManagePresetsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161626),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customize Package Presets',
                              style: GoogleFonts.poppins(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Add, edit, or remove quick plan buttons',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _showAddEditPresetDialog(
                              onSaved: (newPreset) {
                                setState(() => _packagePresets.add(newPreset));
                                setModalState(() {});
                                _savePresets();
                              },
                            );
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Add New Preset',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFFF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          setState(() => _packagePresets = List.from(_defaultPackagePresets));
                          setModalState(() {});
                          await _savePresets();
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 16),
                        label: Text(
                          'Reset Defaults',
                          style: GoogleFonts.poppins(fontSize: 11),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _packagePresets.length,
                      itemBuilder: (context, index) {
                        final preset = _packagePresets[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: preset.gradient.first.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: preset.gradient),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.label,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Price: ₱${preset.price} · Profile: ${preset.profile} · Uptime: ${preset.uptime} · Valid: ${preset.validityNum}${preset.validityUnit}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Color(0xFF00BFFF), size: 18),
                                onPressed: () {
                                  _showAddEditPresetDialog(
                                    presetToEdit: preset,
                                    onSaved: (edited) {
                                      setState(() => _packagePresets[index] = edited);
                                      setModalState(() {});
                                      _savePresets();
                                    },
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 18),
                                onPressed: () {
                                  setState(() => _packagePresets.removeAt(index));
                                  setModalState(() {});
                                  _savePresets();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddEditPresetDialog({
    PackagePreset? presetToEdit,
    required ValueChanged<PackagePreset> onSaved,
  }) {
    final labelCtrl = TextEditingController(text: presetToEdit?.label ?? '');
    final priceCtrl = TextEditingController(text: presetToEdit?.price ?? '10');
    final uptimeCtrl = TextEditingController(text: presetToEdit?.uptime ?? '3h');
    final valNumCtrl = TextEditingController(text: presetToEdit?.validityNum ?? '3');
    String valUnit = presetToEdit?.validityUnit ?? 'd';
    String selectedProfile = presetToEdit?.profile ?? (_profiles.isNotEmpty ? _profiles.first : 'default');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            presetToEdit == null ? 'Add Package Preset' : 'Edit Package Preset',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Preset Name / Label', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 4),
                TextField(
                  controller: labelCtrl,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. ₱10 · 3hrs Uptime',
                    hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Hotspot User Profile', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 4),
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _profiles.contains(selectedProfile) ? selectedProfile : (_profiles.isNotEmpty ? _profiles.first : 'default'),
                      dropdownColor: const Color(0xFF1A1A2E),
                      isExpanded: true,
                      items: _profiles
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedProfile = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price (₱)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '10',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Uptime (e.g. 3h, 1d)', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: uptimeCtrl,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '3h',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Validity Num', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: valNumCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '3',
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Validity Unit', style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70)),
                          const SizedBox(height: 4),
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: valUnit,
                                dropdownColor: const Color(0xFF1A1A2E),
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'h', child: Text('Hours', style: TextStyle(color: Colors.white, fontSize: 12))),
                                  DropdownMenuItem(value: 'd', child: Text('Days', style: TextStyle(color: Colors.white, fontSize: 12))),
                                ],
                                onChanged: (v) {
                                  if (v != null) setDlgState(() => valUnit = v);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                final pStr = priceCtrl.text.trim();
                final uStr = uptimeCtrl.text.trim();
                final vStr = valNumCtrl.text.trim();
                String lbl = labelCtrl.text.trim();
                if (lbl.isEmpty) {
                  lbl = '₱$pStr · $uStr Uptime';
                }
                final newPreset = PackagePreset(
                  id: presetToEdit?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  label: lbl,
                  price: pStr.isNotEmpty ? pStr : '0',
                  uptime: uStr.isNotEmpty ? uStr : '1h',
                  validityNum: vStr.isNotEmpty ? vStr : '1',
                  validityUnit: valUnit,
                  profile: selectedProfile,
                  colorIndex: presetToEdit?.colorIndex ?? (math.Random().nextInt(6)),
                );
                onSaved(newPreset);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Save', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _loadSavedPresets();
  }

  @override
  void dispose() {
    _countController.dispose();
    _commentController.dispose();
    _customPassController.dispose();
    _customUptimeNumController.dispose();
    _validityNumController.dispose();
    _priceController.dispose();
    _codeLengthController.dispose();
    super.dispose();
  }

  void _updateCount(int val) {
    final clamped = val.clamp(1, 1000);
    setState(() {
      _count = clamped;
      _countController.text = '$clamped';
      _countController.selection = TextSelection.fromPosition(
        TextPosition(offset: _countController.text.length),
      );
    });
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await widget.service.getProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = profiles.isEmpty ? ['default'] : profiles;
        _selectedProfile = _profiles.first;
        _loadingProfiles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProfiles = false);
    }
  }

  String _generateCode(int len) {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rnd = math.Random();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  String _generatePassword(int len) {
    const chars = '23456789abcdefghjkmnpqrstuvwxyz';
    final rnd = math.Random();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;

    final userEmail = AuthService.instance.currentUser?.email;
    final isLocked = await TrialService.isTrialLocked(userEmail, widget.service);
    if (isLocked) {
      if (!mounted) return;
      _showTrialLockedModal();
      return;
    }

    setState(() {
      _generating = true;
      _progressCurrent = 0;
      _errorMsg = null;
    });

    String effectiveUptime = '';
    if (_isCustomUptime && _customUptimeNumController.text.trim().isNotEmpty) {
      effectiveUptime = '${_customUptimeNumController.text.trim()}$_customUptimeUnit';
    } else {
      effectiveUptime = _selectedUptime;
    }

    String effectiveComment = _commentController.text.trim();
    if (_voucherFormatMode == 'code_only' && !effectiveComment.startsWith('vc-')) {
      effectiveComment = 'vc-$effectiveComment';
    } else if (_voucherFormatMode == 'user_pass' && !effectiveComment.startsWith('up-') && !effectiveComment.startsWith('vc-')) {
      effectiveComment = 'up-$effectiveComment';
    }
    
    final len = int.tryParse(_codeLengthController.text.trim()) ?? _codeLength;
    final targetCount = int.tryParse(_countController.text.trim()) ?? _count;

    final generated = <Voucher>[];
    for (int i = 0; i < targetCount; i++) {
      try {
        final name = _generateCode(len);
        final pass = switch (_voucherFormatMode) {
          'code_only' => '',
          'user_pass' => switch (_passwordMode) {
              'auto'             => _generatePassword(len),
              'same_as_username' => name,
              'custom'           => _customPassController.text,
              _                  => _generatePassword(len),
            },
          _ => '',
        };

        final voucher = await widget.service.addVoucher(
          name: name,
          password: pass,
          profile: _selectedProfile,
          comment: effectiveComment,
          limitUptime: effectiveUptime,
        );
        generated.add(voucher);
        if (mounted) {
          setState(() => _progressCurrent = i + 1);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMsg =
                'Error at voucher ${i + 1}: ${e.toString().replaceFirst('Exception: ', '')}';
          });
        }
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _generating = false;
    });
    
    if (generated.isNotEmpty) {
      // Store globally so they highlight even if user navigates back and forth
      VoucherListScreen.newlyGeneratedNames.addAll(generated.map((v) => v.name));
      VoucherListScreen.newlyGeneratedVouchers.addAll(generated);

      // Mark trial as used for this specific Gmail user account (locally and on router)
      await TrialService.markGenerated(userEmail, widget.service);
      _showSuccessModal(generated);
    }
  }

  void _showTrialLockedModal() {
    final userEmail = AuthService.instance.currentUser?.email ?? 'Your Account';
    final userInitial = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'G';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9800), Color(0xFFFF5252), Color(0xFF7B2FBE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF121224),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Lock Icon & Badge
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFF9800).withValues(alpha: 0.2),
                          const Color(0xFFFF5252).withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_clock_rounded,
                      color: Color(0xFFFF9800),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title & Subtitle
                  Text(
                    'Free Trial Limit Reached',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '1 / 1 Free Batch Generated',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFFF9800),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Account Info Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF00BFFF).withValues(alpha: 0.2),
                          child: Text(
                            userInitial,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF00BFFF),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userEmail,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Trial quota used for this Gmail account',
                                style: GoogleFonts.poppins(
                                  color: Colors.white38,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Pro Perks List
                  _buildTrialPerkRow(Icons.bolt_rounded, 'Unlimited Voucher Creation'),
                  const SizedBox(height: 8),
                  _buildTrialPerkRow(Icons.print_rounded, 'Thermal & Paper Printing'),
                  const SizedBox(height: 8),
                  _buildTrialPerkRow(Icons.verified_rounded, 'Lifetime Pro License (GCash)'),

                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white60,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Close',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF9800), Color(0xFFFF5252)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UpgradeScreen(service: widget.service),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              'Upgrade PRO ⚡',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrialPerkRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00E676)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.87),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  void _showSuccessModal(List<Voucher> generated) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFF161626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xFF00E676).withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF00E676),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Vouchers Created!',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Successfully generated ${generated.length} voucher${generated.length > 1 ? 's' : ''} under profile "$_selectedProfile"',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // ── Print Vouchers button ──────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx); // Close success modal
                          showVoucherPrintPreview(context, generated); // Open print preview
                        },
                        icon: const Icon(Icons.print_rounded),
                        label: Text(
                          'Print Vouchers',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Go to Voucher List button ──────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx); // Close modal
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => VoucherListScreen(
                                service: widget.service,
                                highlightedNames: generated.map((v) => v.name).toList(),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.confirmation_number_rounded),
                        label: Text(
                          'Go to Voucher List',
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
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Stay & Create More',
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 13,
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Generate Vouchers',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 0. Quick Package Presets section
                      _FormCardSection(
                        header: Row(
                          children: [
                            const Expanded(
                              child: _SectionLabel('⚡ Package Presets'),
                            ),
                            InkWell(
                              onTap: _openManagePresetsModal,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00BFFF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.settings_outlined, color: Color(0xFF00BFFF), size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Edit',
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
                          ],
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: _packagePresets.map((preset) {
                              final isSelected = _priceController.text == preset.price &&
                                  !_isCustomUptime &&
                                  _selectedUptime == preset.uptime;
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: GestureDetector(
                                  onTap: () => _applyPreset(preset),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isSelected
                                            ? preset.gradient
                                            : [
                                                Colors.white.withValues(alpha: 0.07),
                                                Colors.white.withValues(alpha: 0.03),
                                              ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? preset.gradient.first
                                            : Colors.white.withValues(alpha: 0.1),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: preset.gradient.first.withValues(alpha: 0.4),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.bolt_rounded,
                                          size: 16,
                                          color: isSelected ? Colors.white : preset.gradient.first,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          preset.label,
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight:
                                                isSelected ? FontWeight.w700 : FontWeight.w500,
                                            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                      // 1. Count selector section
                      _FormCardSection(
                        header: _SectionLabel('Number of Vouchers'),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  _CountBtn(
                                    icon: Icons.remove_rounded,
                                    onTap: () {
                                      if (_count > 1) _updateCount(_count - 1);
                                    },
                                  ),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _countController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      style: GoogleFonts.poppins(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                        hintText: '1',
                                        hintStyle: TextStyle(color: Colors.white24),
                                      ),
                                      onChanged: (val) {
                                        final parsed = int.tryParse(val.trim());
                                        if (parsed != null && parsed > 0) {
                                          setState(() {
                                            _count = parsed.clamp(1, 1000);
                                          });
                                        }
                                      },
                                      validator: (val) {
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Enter number of vouchers';
                                        }
                                        final parsed = int.tryParse(val.trim());
                                        if (parsed == null || parsed < 1) {
                                          return 'Min 1';
                                        }
                                        if (parsed > 1000) {
                                          return 'Max 1000';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  _CountBtn(
                                    icon: Icons.add_rounded,
                                    onTap: () {
                                      _updateCount(_count + 1);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [5, 10, 20, 50, 100].map((n) {
                                return GestureDetector(
                                  onTap: () => _updateCount(n),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _count == n
                                          ? const Color(0xFF00BFFF).withValues(alpha: 0.2)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _count == n
                                            ? const Color(0xFF00BFFF).withValues(alpha: 0.5)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Text(
                                      '$n',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: _count == n
                                            ? const Color(0xFF00BFFF)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      // 2. Profile selector section
                      _FormCardSection(
                        header: _SectionLabel('Hotspot Profile'),
                        child: _loadingProfiles
                            ? const Center(
                                child: SpinKitThreeBounce(
                                  color: Color(0xFF00BFFF),
                                  size: 20,
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedProfile,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF1A1A2E),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.white54,
                                    ),
                                    items: _profiles
                                        .map(
                                          (p) => DropdownMenuItem(
                                            value: p,
                                            child: Text(
                                              p,
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _selectedProfile = v);
                                      }
                                    },
                                  ),
                                ),
                              ),
                      ),

                      // 3. Voucher Price / Amount section
                      _FormCardSection(
                        header: _SectionLabel('Voucher Price / Amount'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Amount is required';
                                }
                                final parsed = double.tryParse(val.trim());
                                if (parsed == null || parsed < 0) {
                                  return 'Enter a valid amount';
                                }
                                return null;
                              },
                              decoration: InputDecoration(
                                hintText: 'Enter price (e.g. 10, 20, 50)',
                                hintStyle: GoogleFonts.poppins(
                                  color: Colors.white24,
                                ),
                                prefixIcon: const Icon(
                                  Icons.payments_rounded,
                                  color: Color(0xFF00E676),
                                  size: 18,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [5, 10, 20, 50, 100].map((p) {
                                final pStr = '$p';
                                final isSel = _priceController.text == pStr;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _priceController.text = pStr),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? const Color(0xFF00E676).withValues(alpha: 0.2)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSel
                                            ? const Color(0xFF00E676).withValues(alpha: 0.5)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Text(
                                      '₱$p',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isSel
                                            ? const Color(0xFF00E676)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      // 4. Time Limit section
                      _FormCardSection(
                        header: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _SectionLabel('Time Limit'),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isCustomUptime = !_isCustomUptime;
                                  if (!_isCustomUptime) {
                                    _customUptimeNumController.clear();
                                  }
                                });
                              },
                              child: Text(
                                _isCustomUptime ? '← Presets' : '+ Custom Time',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: const Color(0xFF00BFFF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        child: _isCustomUptime
                            ? Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _customUptimeNumController,
                                      keyboardType: TextInputType.number,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'e.g. 5, 12, 24',
                                        hintStyle: GoogleFonts.poppins(
                                          color: Colors.white24,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.timer_rounded,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withValues(alpha: 0.05),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                            color: Color(0xFF00BFFF),
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _UnitToggleSegment(
                                    selectedUnit: _customUptimeUnit,
                                    onChanged: (unit) =>
                                        setState(() => _customUptimeUnit = unit),
                                  ),
                                ],
                              )
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _uptimeOptions.map((opt) {
                                    final label = opt.isEmpty ? 'No Limit' : opt;
                                    final isSelected =
                                        !_isCustomUptime && _selectedUptime == opt;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isCustomUptime = false;
                                          _selectedUptime = opt;
                                        }),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF7B2FBE)
                                                    .withValues(alpha: 0.25)
                                                : Colors.white.withValues(alpha: 0.05),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF7B2FBE)
                                                      .withValues(alpha: 0.6)
                                                  : Colors.transparent,
                                            ),
                                          ),
                                          child: Text(
                                            label,
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: isSelected
                                                  ? const Color(0xFFBB86FC)
                                                  : Colors.white54,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                      ),

                      // 5. Voucher Code Validity Section
                      _FormCardSection(
                        header: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel('Voucher Code Validity (Expiry)'),
                            const SizedBox(height: 4),
                            Text(
                              'Set how long this voucher stays valid (Enter 0 for No Expire)',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _validityNumController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Validity is required';
                                  }
                                  final parsed = int.tryParse(val.trim());
                                  if (parsed == null || parsed < 0) {
                                    return 'Enter a valid number (0 for No Expire)';
                                  }
                                  return null;
                                },
                                decoration: InputDecoration(
                                  hintText: 'e.g. 0 (No Expire), 1, 7, 30',
                                  hintStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.event_available_rounded,
                                    color: Colors.white38,
                                    size: 18,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF00BFFF),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _UnitToggleSegment(
                              selectedUnit: _validityUnit,
                              onChanged: (unit) =>
                                  setState(() => _validityUnit = unit),
                            ),
                          ],
                        ),
                      ),

                      // 6. Voucher Code Format & Password Section
                      _FormCardSection(
                        header: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel('Voucher Code Format & Password'),
                            const SizedBox(height: 4),
                            Text(
                              'Choose code style and length (number of letters)',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Format Mode selector (Code Only vs Username & Password)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.04),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _RadioTile(
                                    title: 'Code / Username Only',
                                    subtitle: 'Only username generated (No password needed)',
                                    value: 'code_only',
                                    groupValue: _voucherFormatMode,
                                    onChanged: (v) => setState(
                                        () => _voucherFormatMode = v.toString()),
                                  ),
                                  const Divider(color: Colors.white10, height: 1),
                                  _RadioTile(
                                    title: 'Username & Password',
                                    subtitle: 'Separate login username & password',
                                    value: 'user_pass',
                                    groupValue: _voucherFormatMode,
                                    onChanged: (v) => setState(
                                        () => _voucherFormatMode = v.toString()),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Code Length Input (Number of letters)
                            Text(
                              'Code Length (Number of Characters)',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _codeLengthController,
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 4, 6, 8',
                                      hintStyle: GoogleFonts.poppins(
                                        color: Colors.white24,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.onetwothree_rounded,
                                        color: Color(0xFF00BFFF),
                                        size: 22,
                                      ),
                                      suffixText: 'chars',
                                      suffixStyle: GoogleFonts.poppins(
                                        color: Colors.white38,
                                        fontSize: 12,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.05),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF00BFFF),
                                        ),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [4, 6, 8, 10].map((len) {
                                final lenStr = '$len';
                                final isSel =
                                    _codeLengthController.text == lenStr;
                                return GestureDetector(
                                  onTap: () => setState(
                                      () => _codeLengthController.text = lenStr),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? const Color(0xFF00BFFF).withValues(alpha: 0.2)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSel
                                            ? const Color(0xFF00BFFF)
                                                .withValues(alpha: 0.5)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Text(
                                      '$len Letters',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: isSel
                                            ? const Color(0xFF00BFFF)
                                            : Colors.white54,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            // If Username & Password mode selected
                            if (_voucherFormatMode == 'user_pass') ...[
                              const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.04),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      _RadioTile(
                                        title: 'Auto-generate Password',
                                        subtitle: 'Random password per voucher',
                                        value: 'auto',
                                        groupValue: _passwordMode,
                                        onChanged: (v) =>
                                            setState(() => _passwordMode = 'auto'),
                                      ),
                                      const Divider(
                                          color: Colors.white10, height: 1),
                                      _RadioTile(
                                        title: 'Username = Password',
                                        subtitle: 'Password is the same as the voucher code',
                                        value: 'same_as_username',
                                        groupValue: _passwordMode,
                                        onChanged: (v) =>
                                            setState(() => _passwordMode = 'same_as_username'),
                                      ),
                                      const Divider(
                                          color: Colors.white10, height: 1),
                                      _RadioTile(
                                        title: 'Custom Password',
                                        subtitle: 'Same password for all vouchers',
                                        value: 'custom',
                                        groupValue: _passwordMode,
                                        onChanged: (v) =>
                                            setState(() => _passwordMode = 'custom'),
                                      ),
                                      if (_passwordMode == 'custom') ...[
                                        const Divider(
                                            color: Colors.white10, height: 1),
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: TextFormField(
                                            controller: _customPassController,
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                            validator: (v) {
                                              if (_voucherFormatMode ==
                                                      'user_pass' &&
                                                  _passwordMode == 'custom' &&
                                                  (v == null || v.isEmpty)) {
                                                return 'Enter a password';
                                              }
                                              return null;
                                            },
                                            decoration: InputDecoration(
                                              hintText: 'Enter custom password',
                                              hintStyle: GoogleFonts.poppins(
                                                color: Colors.white24,
                                              ),
                                              filled: true,
                                              fillColor:
                                                  Colors.white.withValues(alpha: 0.05),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: BorderSide.none,
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF00BFFF),
                                                ),
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),

                      // 7. Comment section
                      _FormCardSection(
                        header: _SectionLabel('Batch Label / Comment (Required for Batch Print)'),
                        child: TextFormField(
                          controller: _commentController,
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'A batch label is required for batch printing' : null,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. Hall A, July Promo',
                            hintStyle: GoogleFonts.poppins(
                              color: Colors.white24,
                            ),
                            helperText: 'Used to identify and print this batch of vouchers later.',
                            helperStyle: GoogleFonts.poppins(color: const Color(0xFFF57C00), fontSize: 11),
                            prefixIcon: const Icon(
                              Icons.label_outline_rounded,
                              color: Colors.white38,
                              size: 18,
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF00BFFF),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),

                      if (_errorMsg != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: Color(0xFFFF5252),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: const Color(0xFFFF5252),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // Generate button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _generating ? null : _generate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: _generating
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF2A2A3E),
                                        Color(0xFF2A2A3E),
                                      ],
                                    )
                                  : const LinearGradient(
                                      colors: [
                                        Color(0xFF00BFFF),
                                        Color(0xFF7B2FBE),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _generating
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00BFFF,
                                        ).withValues(alpha: 0.35),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                            ),
                            child: Center(
                              child: _generating
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SpinKitThreeBounce(
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          '$_progressCurrent / $_count',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.bolt_rounded,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Generate $_count Voucher${_count > 1 ? 's' : ''}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
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
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white60,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CountBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF00BFFF).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF00BFFF).withValues(alpha: 0.3),
          ),
        ),
        child: Icon(icon, color: const Color(0xFF00BFFF), size: 22),
      ),
    );
  }
}

class _RadioTile<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;

  const _RadioTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: groupValue == value
                      ? const Color(0xFF00BFFF)
                      : Colors.white38,
                  width: 2,
                ),
              ),
              child: groupValue == value
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF00BFFF),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitToggleSegment extends StatelessWidget {
  final String selectedUnit;
  final ValueChanged<String> onChanged;

  const _UnitToggleSegment({
    required this.selectedUnit,
    required this.onChanged,
  });

  Widget _buildUnitBtn(String unit, String label) {
    final active = selectedUnit == unit;
    return GestureDetector(
      onTap: () => onChanged(unit),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00BFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUnitBtn('h', 'Hours'),
          _buildUnitBtn('d', 'Days'),
        ],
      ),
    );
  }
}

class _FormCardSection extends StatelessWidget {
  final Widget header;
  final Widget child;

  const _FormCardSection({
    required this.header,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161626),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class PackagePreset {
  final String id;
  final String label;
  final String price;
  final String uptime;
  final String validityNum;
  final String validityUnit;
  final String profile;
  final int colorIndex;

  PackagePreset({
    required this.id,
    required this.label,
    required this.price,
    required this.uptime,
    required this.validityNum,
    required this.validityUnit,
    this.profile = 'default',
    this.colorIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'price': price,
        'uptime': uptime,
        'validityNum': validityNum,
        'validityUnit': validityUnit,
        'profile': profile,
        'colorIndex': colorIndex,
      };

  factory PackagePreset.fromJson(Map<String, dynamic> json) => PackagePreset(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        label: json['label'] as String? ?? 'Preset',
        price: json['price'] as String? ?? '0',
        uptime: json['uptime'] as String? ?? '1h',
        validityNum: json['validityNum'] as String? ?? '1',
        validityUnit: json['validityUnit'] as String? ?? 'd',
        profile: json['profile'] as String? ?? 'default',
        colorIndex: json['colorIndex'] as int? ?? 0,
      );

  List<Color> get gradient {
    const gradients = [
      [Color(0xFF00BFFF), Color(0xFF0077FF)],
      [Color(0xFF00E676), Color(0xFF00A859)],
      [Color(0xFFFF9800), Color(0xFFE65100)],
      [Color(0xFF7B2FBE), Color(0xFF512DA8)],
      [Color(0xFFFF5252), Color(0xFFD32F2F)],
      [Color(0xFFBB86FC), Color(0xFF7B2FBE)],
    ];
    return gradients[colorIndex % gradients.length];
  }
}

final List<PackagePreset> _defaultPackagePresets = [
  PackagePreset(id: '1', price: '5', uptime: '1h', validityNum: '1', validityUnit: 'd', label: '₱5 · 1hr Uptime', colorIndex: 0),
  PackagePreset(id: '2', price: '10', uptime: '3h', validityNum: '3', validityUnit: 'd', label: '₱10 · 3hrs Uptime', colorIndex: 1),
  PackagePreset(id: '3', price: '20', uptime: '1d', validityNum: '7', validityUnit: 'd', label: '₱20 · 24hrs Uptime', colorIndex: 2),
  PackagePreset(id: '4', price: '50', uptime: '3d', validityNum: '15', validityUnit: 'd', label: '₱50 · 3 Days Uptime', colorIndex: 3),
  PackagePreset(id: '5', price: '100', uptime: '7d', validityNum: '30', validityUnit: 'd', label: '₱100 · 7 Days Uptime', colorIndex: 4),
  PackagePreset(id: '6', price: '200', uptime: '30d', validityNum: '60', validityUnit: 'd', label: '₱200 · 30 Days Uptime', colorIndex: 5),
];