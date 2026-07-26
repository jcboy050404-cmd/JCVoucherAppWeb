import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voucherapps/models/router_profile.dart';
import 'package:voucherapps/services/base_vendo_service.dart';
import 'package:voucherapps/services/vendo_manager.dart';

class VendoMonitorCard extends StatefulWidget {
  final RouterProfile? profile;
  final VoidCallback? onRefresh;

  const VendoMonitorCard({
    super.key,
    this.profile,
    this.onRefresh,
  });

  @override
  State<VendoMonitorCard> createState() => _VendoMonitorCardState();
}

class _VendoMonitorCardState extends State<VendoMonitorCard> {
  bool _isLoading = false;
  VendoStats? _stats;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isLoading) {
        _fetchStats(isAutoRefresh: true);
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VendoMonitorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile?.id != widget.profile?.id || oldWidget.profile?.machineType != widget.profile?.machineType) {
      _fetchStats();
    }
  }

  Future<void> _fetchStats({bool isAutoRefresh = false}) async {
    if (widget.profile == null) return;
    if (!isAutoRefresh) setState(() => _isLoading = true);
    try {
      final driver = VendoManager().getDriver(widget.profile!);
      final stats = await driver.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && !isAutoRefresh) setState(() => _isLoading = false);
    }
  }

  Color _getBadgeColor(String type) {
    switch (type.toLowerCase()) {
      case 'lpb':
        return const Color(0xFFFF9800);
      case 'juanfi':
        return const Color(0xFF00E676);
      case 'ado':
        return const Color(0xFFBB86FC);
      case 'mikrotik':
      default:
        return const Color(0xFF00BFFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prof = widget.profile;
    final stats = _stats;
    final badgeColor = _getBadgeColor(prof?.machineType ?? 'mikrotik');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF18182A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: (stats?.isOnline ?? false) ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (stats?.isOnline ?? false) ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        prof?.name ?? 'Vendo Machine',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Text(
                        'LIVE',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF00E676),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.developer_board_rounded, size: 12, color: badgeColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          stats?.boardName ?? prof?.machineDisplayName ?? 'MikroTik',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),


          const SizedBox(height: 14),
          Row(
            children: [
              _MetricTile(
                icon: Icons.memory_rounded,
                label: 'CPU Load',
                value: '${stats?.cpuUsage ?? 0}%',
                color: (stats?.cpuUsage ?? 0) > 80 ? Colors.redAccent : const Color(0xFF00BFFF),
              ),
              const SizedBox(width: 8),
              _MetricTile(
                icon: Icons.storage_rounded,
                label: 'RAM Used',
                value: '${stats?.ramUsage ?? 0}%',
                color: const Color(0xFF00E676),
              ),
              const SizedBox(width: 8),
              _MetricTile(
                icon: Icons.wifi_tethering_rounded,
                label: 'Active Users',
                value: '${stats?.activeUsersCount ?? 0}',
                color: const Color(0xFFFF9800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  Text(
                    'Uptime: ${stats?.uptime ?? "Offline"}',
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              InkWell(
                onTap: _isLoading ? null : _fetchStats,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      _isLoading
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00BFFF)))
                          : const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF00BFFF)),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh',
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF00BFFF), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
