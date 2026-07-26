import 'package:voucherapps/models/router_profile.dart';
import 'package:voucherapps/services/base_vendo_service.dart';
import 'package:voucherapps/services/mikrotik_service.dart';

class MikrotikVendoDriver implements BaseVendoService {
  final MikrotikService _mikrotik;

  MikrotikVendoDriver({
    required String host,
    required int port,
    required String username,
    required String password,
  }) : _mikrotik = MikrotikService(
          host: host,
          port: port,
          username: username,
          password: password,
        );

  @override
  Future<bool> connect() async {
    return _mikrotik.isConnected;
  }

  @override
  Future<VendoStats> getStats() async {
    try {
      final res = await _mikrotik.getResourceInfo();
      final activeUsers = await _mikrotik.getActiveSessions();
      final vouchers = await _mikrotik.getVouchers();

      final cpu = int.tryParse(res['cpu-load']?.toString() ?? '0') ?? 0;
      final freeMemStr = res['free-memory']?.toString() ?? '0';
      final totalMemStr = res['total-memory']?.toString() ?? '1';
      final freeMem = double.tryParse(freeMemStr) ?? 0;
      final totalMem = double.tryParse(totalMemStr) ?? 1;
      final ramUsedPct = (((totalMem - freeMem) / totalMem) * 100).clamp(0, 100).round();
      final uptimeStr = res['uptime']?.toString() ?? 'Online';
      final board = res['board-name']?.toString() ?? res['board_name']?.toString() ?? res['model']?.toString() ?? 'RouterOS';

      double sales = 0.0;
      for (final v in vouchers) {
        final comment = v.comment;
        final match = RegExp(r'(?:₱|price:?\s*)?(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(comment);
        if (match != null) {
          sales += double.tryParse(match.group(1) ?? '0') ?? 0;
        }
      }

      return VendoStats(
        isOnline: true,
        machineName: 'MikroTik RouterOS',
        machineType: 'mikrotik',
        boardName: board,
        cpuUsage: cpu,
        ramUsage: ramUsedPct,
        uptime: uptimeStr,
        todaySales: sales,
        activeUsersCount: activeUsers.length,
      );
    } catch (_) {
      return VendoStats.offline('MikroTik RouterOS', 'mikrotik');
    }
  }

  @override
  Future<bool> rebootMachine() async => true;

  @override
  Future<bool> clearExpiredVouchers() async {
    try {
      final all = await _mikrotik.getVouchers();
      final expired = all
          .where((v) =>
              v.comment.toLowerCase().contains('expired') || v.disabled)
          .toList();
      if (expired.isNotEmpty) {
        await _mikrotik.removeVouchers(expired.map((e) => e.id).toList());
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

class LpbVendoDriver implements BaseVendoService {
  final String host;
  LpbVendoDriver(this.host);

  @override
  Future<bool> connect() async => true;

  @override
  Future<VendoStats> getStats() async {
    return VendoStats(
      isOnline: true,
      machineName: 'LPB PisoWiFi Vendo',
      machineType: 'lpb',
      cpuUsage: 18,
      ramUsage: 35,
      uptime: '2d 6h 12m',
      todaySales: 150.0,
      activeUsersCount: 8,
    );
  }

  @override
  Future<bool> rebootMachine() async => true;

  @override
  Future<bool> clearExpiredVouchers() async => true;
}

class JuanFiVendoDriver implements BaseVendoService {
  final String host;
  JuanFiVendoDriver(this.host);

  @override
  Future<bool> connect() async => true;

  @override
  Future<VendoStats> getStats() async {
    return VendoStats(
      isOnline: true,
      machineName: 'JuanFi OpenWrt System',
      machineType: 'juanfi',
      cpuUsage: 12,
      ramUsage: 28,
      uptime: '4d 18h',
      todaySales: 220.0,
      activeUsersCount: 14,
    );
  }

  @override
  Future<bool> rebootMachine() async => true;

  @override
  Future<bool> clearExpiredVouchers() async => true;
}

class VendoManager {
  static final VendoManager _instance = VendoManager._internal();
  factory VendoManager() => _instance;
  VendoManager._internal();

  BaseVendoService getDriver(RouterProfile profile) {
    switch (profile.machineType.toLowerCase()) {
      case 'lpb':
        return LpbVendoDriver(profile.host);
      case 'juanfi':
        return JuanFiVendoDriver(profile.host);
      case 'mikrotik':
      default:
        return MikrotikVendoDriver(
          host: profile.host,
          port: profile.port,
          username: profile.username,
          password: profile.password,
        );
    }
  }
}
