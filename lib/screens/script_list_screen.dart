import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/mikrotik_service.dart';
import '../models/router_script.dart';

class ScriptListScreen extends StatefulWidget {
  final MikrotikService service;
  const ScriptListScreen({super.key, required this.service});

  @override
  State<ScriptListScreen> createState() => _ScriptListScreenState();
}

class _ScriptListScreenState extends State<ScriptListScreen> {
  List<RouterScript> _scripts = [];
  bool _loading = true;
  String? _error;

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

  void _showAddEditModal([RouterScript? script]) {
    final nameCtrl = TextEditingController(text: script?.name ?? '');
    final sourceCtrl = TextEditingController(text: script?.source ?? '');
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
                              script == null ? 'Add Router Script' : 'Edit Script',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            if (script != null)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFFF5252),
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  _deleteScript(script);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Script Name
                        TextFormField(
                          controller: nameCtrl,
                          style: GoogleFonts.poppins(color: Colors.white),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter script name' : null,
                          decoration: InputDecoration(
                            labelText: 'Script Name',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: 'e.g. check_expirations',
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

                        // Script Source
                        TextFormField(
                          controller: sourceCtrl,
                          maxLines: 8,
                          style: GoogleFonts.firaCode(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter script code' : null,
                          decoration: InputDecoration(
                            labelText: 'RouterOS Script Source Code',
                            labelStyle: GoogleFonts.poppins(color: Colors.white60),
                            hintText: ':log info "Voucher system active";',
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
                                      if (script == null) {
                                        await widget.service.addScript(
                                          name: nameCtrl.text.trim(),
                                          source: sourceCtrl.text.trim(),
                                        );
                                      } else {
                                        await widget.service.updateScript(
                                          id: script.id,
                                          name: nameCtrl.text.trim(),
                                          source: sourceCtrl.text.trim(),
                                        );
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);
                                      _loadScripts();
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
                                ? const SpinKitThreeBounce(
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : Text(
                                    script == null ? 'Save Script' : 'Update Script',
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

  Future<void> _runScript(RouterScript script) async {
    try {
      await widget.service.runScript(script.name);
      if (!mounted) return;
      TopToast.show(context, 'Script ran successfully', backgroundColor: const Color(0xFF00E676));
      _loadScripts();
    } catch (e) {
      if (!mounted) return;
      TopToast.show(context, 'Run error: $e', backgroundColor: Colors.redAccent);
    }
  }

  Future<void> _deleteScript(RouterScript script) async {
    try {
      await widget.service.removeScript(script.id);
      if (!mounted) return;
      _loadScripts();
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
          'Router Scripts',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadScripts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditModal(),
        backgroundColor: const Color(0xFF00BFFF),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'Add Script',
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
                  onRefresh: _loadScripts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _scripts.length,
                    itemBuilder: (context, i) {
                      final s = _scripts[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161626),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: ExpansionTile(
                          iconColor: const Color(0xFF00BFFF),
                          collapsedIconColor: Colors.white38,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFFF).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.code_rounded,
                              color: Color(0xFF00BFFF),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            s.name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            'Owner: ${s.owner} • Runs: ${s.runCount}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white10,
                                      ),
                                    ),
                                    child: Text(
                                      s.source.isEmpty ? '# (No source code)' : s.source,
                                      style: GoogleFonts.firaCode(
                                        fontSize: 11,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _showAddEditModal(s),
                                        icon: const Icon(Icons.edit_rounded, size: 16),
                                        label: Text(
                                          'Edit',
                                          style: GoogleFonts.poppins(fontSize: 12),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          side: const BorderSide(color: Colors.white24),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _runScript(s),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Run Script',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF00E676),
                                          foregroundColor: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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

