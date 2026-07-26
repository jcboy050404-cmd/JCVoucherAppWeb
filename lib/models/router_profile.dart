import 'dart:convert';

class RouterProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String machineType; // 'mikrotik', 'lpb', 'juanfi', 'ado', 'custom'
  final DateTime? lastConnected;

  RouterProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 8728,
    required this.username,
    required this.password,
    this.machineType = 'mikrotik',
    this.lastConnected,
  });

  String get machineDisplayName {
    switch (machineType.toLowerCase()) {
      case 'lpb':
        return 'LPB PisoWiFi';
      case 'juanfi':
        return 'JuanFi System';
      case 'ado':
        return 'AdoPisoWiFi';
      case 'custom':
        return 'Custom HTTP Vendo';
      case 'mikrotik':
      default:
        return 'MikroTik RouterOS';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'machineType': machineType,
      'lastConnected': lastConnected?.toIso8601String(),
    };
  }

  factory RouterProfile.fromJson(Map<String, dynamic> json) {
    return RouterProfile(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Router',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 8728,
      username: json['username'] as String? ?? 'admin',
      password: json['password'] as String? ?? '',
      machineType: json['machineType'] as String? ?? 'mikrotik',
      lastConnected: json['lastConnected'] != null
          ? DateTime.tryParse(json['lastConnected'] as String)
          : null,
    );
  }

  static String encodeList(List<RouterProfile> routers) {
    return jsonEncode(routers.map((r) => r.toJson()).toList());
  }

  static List<RouterProfile> decodeList(String jsonString) {
    if (jsonString.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((item) => RouterProfile.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  RouterProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? machineType,
    DateTime? lastConnected,
  }) {
    return RouterProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      machineType: machineType ?? this.machineType,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
