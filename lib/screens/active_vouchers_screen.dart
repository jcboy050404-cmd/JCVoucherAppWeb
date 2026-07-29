import 'package:flutter/material.dart';
import '../widgets/top_toast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/mikrotik_service.dart';
import '../models/voucher.dart';
import '../responsive.dart';

class ActiveVouchersScreen extends StatefulWidget {
  final MikrotikService service;
  const ActiveVouchersScreen({super.key, required this.service});

  @override
  State<ActiveVouchersScreen> createState() => _ActiveVouchersScreenState();
}

class _ActiveVouchersScreenState extends State<ActiveVouchersScreen> {
  List<HotspotActive> _allActive = [];
  List<HotspotActive> _filteredActive = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_applySearch);
    _loadActiveSessions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActiveSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await widget.service.getActiveSessions();
      if (!mounted) return;
      setState(() {
        _allActive = sessions;
        _loading = false;
      });
      _applySearch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredActive = _allActive.where((a) {
        return q.isEmpty ||
            a.user.toLowerCase().contains(q) ||
            a.address.toLowerCase().contains(q) ||
            a.macAddress.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _disconnectUser(HotspotActive active) async {
    if (_processingIds.contains(active.id)) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Disconnect User?', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'Disconnect "${active.user}" from the network?',
          style: GoogleFonts.poppins(color: Colors.white70),
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
            ),
            child: Text('Disconnect', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _processingIds.add(active.id));

    try {
      await widget.service.removeActiveSession(active.id);
      if (!mounted) return;

      setState(() {
        _allActive.removeWhere((a) => a.id == active.id);
        _processingIds.remove(active.id);
      });
      _applySearch();

      _silentRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _processingIds.remove(active.id));
      TopToast.show(context, 'Failed: $e', backgroundColor: Colors.redAccent);
    }
  }



  /// Refreshes session list silently (no loading spinner shown to user)
  Future<void> _silentRefresh() async {
    try {
      final sessions = await widget.service.getActiveSessions();
      if (!mounted) return;
      setState(() => _allActive = sessions);
      _applySearch();
    } catch (_) {
      // Ignore silent refresh errors; user already sees the optimistic removal
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161626),
        title: Text(
          'Active Online Vouchers (${_allActive.length})',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadActiveSessions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search active user code or IP...',
                hintStyle: GoogleFonts.poppins(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF161626),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(
                    child: SpinKitFadingCube(color: Color(0xFF00E676), size: 36),
                  )
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: GoogleFonts.poppins(color: Colors.redAccent),
                        ),
                      )
                    : _filteredActive.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.wifi_off_rounded,
                                  size: 48,
                                  color: Colors.white24,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No Active Users Connected',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white54,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadActiveSessions,
                            color: const Color(0xFF00E676),
                            backgroundColor: const Color(0xFF161626),
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 350,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: 280,
                              ),
                              itemCount: _filteredActive.length,
                              itemBuilder: (context, i) {
                                final a = _filteredActive[i];
                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF161626),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF00E676).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF00E676),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'ONLINE',
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF00E676),
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (_processingIds.contains(a.id))
                                            const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(color: Color(0xFFFF5252), strokeWidth: 2),
                                            )
                                          else
                                            GestureDetector(
                                              onTap: () => _disconnectUser(a),
                                              child: const Icon(
                                                Icons.power_settings_new_rounded,
                                                color: Color(0xFFFF5252),
                                                size: 22,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        a.user,
                                        style: GoogleFonts.poppins(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 1.5,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (a.customerName.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          a.customerName,
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF00BFFF),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      const Divider(color: Colors.white10, height: 1),
                                      const SizedBox(height: 6),

                                      // Network Info
                                      Text(
                                        'IP: ${a.address}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'MAC: ${a.macAddress}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          color: Colors.white38,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),

                                      const SizedBox(height: 8),

                                      // Time Info
                                      Text(
                                        'Up: ${a.uptime}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: const Color(0xFF00BFFF),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        () {
                                          final hasTimeLimit = a.sessionTimeLeft.isNotEmpty;
                                          final hasDataLimit = (double.tryParse(a.limitBytesTotal) ?? 0) > 0;
                                          if (hasTimeLimit) {
                                            return 'Time Left: ${a.formattedTimeLeft}';
                                          } else if (hasDataLimit) {
                                            return 'Data Left: ${a.formattedDataLeft}';
                                          } else {
                                            return 'Limit: No Limit';
                                          }
                                        }(),
                                        style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (a.comment.contains('exp:')) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Exp: ${a.comment.split('exp:').last.split(' ').first}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            color: Colors.orangeAccent,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],

                                      const Spacer(),

                                      // Data Usage Mini Box
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Icon(
                                                  Icons.pie_chart_outline_rounded,
                                                  color: a.formattedDataLeft.contains('Exhausted')
                                                      ? const Color(0xFFFF5252)
                                                      : const Color(0xFF00E676),
                                                  size: 16,
                                                ),
                                                Text(
                                                  a.formattedDataLeft,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: a.formattedDataLeft.contains('Exhausted')
                                                        ? const Color(0xFFFF5252)
                                                        : const Color(0xFF00E676),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: a.dataUsageProgress > 0 ? a.dataUsageProgress : 0.0,
                                                backgroundColor: Colors.white10,
                                                color: a.dataUsageProgress > 0.9
                                                    ? const Color(0xFFFF5252)
                                                    : const Color(0xFF00E676),
                                                minHeight: 6,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Used: ${a.formattedDataUsage}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                color: Colors.white54,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
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
          ),
        ],
      ),
    );
  }
}
