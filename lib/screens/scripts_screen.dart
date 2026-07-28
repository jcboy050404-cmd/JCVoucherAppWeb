import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/mikrotik_service.dart';
import '../models/router_script.dart';
import '../responsive.dart';

class ScriptsScreen extends StatefulWidget {
  final MikrotikService service;
  const ScriptsScreen({super.key, required this.service});

  @override
  State<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends State<ScriptsScreen> {
  List<RouterScript> _scripts = [];
  bool _loading = true;
  String? _error;
  String? _runningScriptId;

  @override
  void initState() {
    super.initState();
    _loadScripts();
  }

  Future<void> _loadScripts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.service.getScripts();
      if (!mounted) return;
      setState(() {
        _scripts = list;
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

  Future<void> _runScript(RouterScript script) async {
    setState(() => _runningScriptId = script.id);
    try {
      await widget.service.runScript(script.name);
      if (!mounted) return;

      _loadScripts();
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Run failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _runningScriptId = null);
    }
  }

  Future<void> _showScriptDialog({RouterScript? script}) async {
    final isEdit = script != null;
    final nameCtrl = TextEditingController(text: script?.name ?? '');
    final sourceCtrl = TextEditingController(text: script?.source ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Text(
            isEdit ? 'Edit Script' : 'Add RouterOS Script',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter script name' : null,
                    decoration: InputDecoration(
                      labelText: 'Script Name',
                      labelStyle:
                          GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
                      hintText: 'e.g. CleanExpiredVouchers',
                      hintStyle:
                          GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
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
                    controller: sourceCtrl,
                    maxLines: 8,
                    style: GoogleFonts.firaCode(
                      color: const Color(0xFF00E676),
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Script Source Code',
                      labelStyle:
                          GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
                      hintText: ':log info "Hello RouterOS";',
                      hintStyle:
                          GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF00E676)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  if (isEdit) {
                    await widget.service.updateScript(
                      id: script.id,
                      name: nameCtrl.text.trim(),
                      source: sourceCtrl.text,
                    );
                  } else {
                    await widget.service.addScript(
                      name: nameCtrl.text.trim(),
                      source: sourceCtrl.text,
                    );
                  }
                  _loadScripts();
                } catch (e) {
                  if (!mounted) return;
                  TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), backgroundColor: const Color(0xFFFF5252));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isEdit ? 'Save Changes' : 'Create Script',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteScript(RouterScript script) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161626),
        title:
            Text('Delete Script?', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete script "${script.name}"?',
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.removeScript(script.id);
        _loadScripts();
      } catch (e) {
        if (!mounted) return;
        TopToast.show(context, e.toString().replaceFirst('Exception: ', ''), backgroundColor: const Color(0xFFFF5252));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'RouterOS Scripts',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadScripts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScriptDialog(),
        backgroundColor: const Color(0xFF00E676),
        icon: const Icon(Icons.code_rounded, color: Colors.black),
        label: Text(
          'Add Script',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: SpinKitFadingCube(color: Color(0xFF00E676), size: 40),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error!,
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadScripts,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _scripts.isEmpty
                  ? Center(
                      child: Text(
                        'No scripts found on router',
                        style: GoogleFonts.poppins(color: Colors.white38),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadScripts,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: _scripts.length,
                        itemBuilder: (ctx, idx) {
                          final sc = _scripts[idx];
                          final isRunning = _runningScriptId == sc.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161626),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.07),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.terminal_rounded,
                                      color: Color(0xFF00E676),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        sc.name,
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        color: Color(0xFF00BFFF),
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showScriptDialog(script: sc),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFFF5252),
                                        size: 20,
                                      ),
                                      onPressed: () => _deleteScript(sc),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (sc.source.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.04),
                                      ),
                                    ),
                                    child: Text(
                                      sc.source,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.firaCode(
                                        fontSize: 11,
                                        color: const Color(0xFF00E676),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Text(
                                      'Run count: ${sc.runCount}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.white38,
                                      ),
                                    ),
                                    const Spacer(),
                                    ElevatedButton.icon(
                                      onPressed:
                                          isRunning ? null : () => _runScript(sc),
                                      icon: isRunning
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.black,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.play_arrow_rounded,
                                              size: 18,
                                            ),
                                      label: Text(
                                        isRunning ? 'Running...' : 'Run Script',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00E676),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
