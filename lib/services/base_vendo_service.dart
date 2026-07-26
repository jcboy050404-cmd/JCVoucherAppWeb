class VendoStats {
  final bool isOnline;
  final String machineName;
  final String machineType;
  final String? boardName;
  final int cpuUsage; // 0-100%
  final int ramUsage; // 0-100%
  final String uptime;
  final double todaySales; // In PHP (₱)
  final int activeUsersCount;

  VendoStats({
    required this.isOnline,
    required this.machineName,
    required this.machineType,
    this.boardName,
    this.cpuUsage = 0,
    this.ramUsage = 0,
    this.uptime = '0h 0m',
    this.todaySales = 0.0,
    this.activeUsersCount = 0,
  });

  factory VendoStats.offline(String name, String type) => VendoStats(
        isOnline: false,
        machineName: name,
        machineType: type,
        boardName: null,
        cpuUsage: 0,
        ramUsage: 0,
        uptime: 'Offline',
        todaySales: 0.0,
        activeUsersCount: 0,
      );
}

abstract class BaseVendoService {
  Future<bool> connect();
  Future<VendoStats> getStats();
  Future<bool> rebootMachine();
  Future<bool> clearExpiredVouchers();
}
