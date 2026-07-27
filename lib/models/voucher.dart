class Voucher {
  final String id;
  final String name;
  final String password;
  final String profile;
  final String comment;
  final String limitUptime;
  final String limitBytes;
  final String bytesIn;
  final String bytesOut;
  final bool disabled;
  final String createdAt;

  Voucher({
    required this.id,
    required this.name,
    required this.password,
    required this.profile,
    this.comment = '',
    this.limitUptime = '',
    this.limitBytes = '',
    this.bytesIn = '0',
    this.bytesOut = '0',
    this.disabled = false,
    this.createdAt = '',
  });

  factory Voucher.fromMap(Map<String, String> map) {
    return Voucher(
      id: map['.id'] ?? '',
      name: map['name'] ?? '',
      password: map['password'] ?? '',
      profile: map['profile'] ?? 'default',
      comment: map['comment'] ?? '',
      limitUptime: map['limit-uptime'] ?? '',
      limitBytes: map['limit-bytes-total'] ?? '',
      bytesIn: map['bytes-in'] ?? '0',
      bytesOut: map['bytes-out'] ?? '0',
      disabled: map['disabled'] == 'true',
      createdAt: map['last-logged-out'] ?? '',
    );
  }

  bool get isUsed => bytesIn != '0' || bytesOut != '0';

  String get displayCode => name.toUpperCase();

  double get price {
    final match = RegExp(r'P:([0-9]+(?:\.[0-9]+)?)').firstMatch(comment);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }

  String get formattedPrice {
    // 1. Try strict P: format
    final matchP = RegExp(r'P:([0-9]+(?:\.[0-9]+)?)').firstMatch(comment);
    if (matchP != null) return double.parse(matchP.group(1)!).toStringAsFixed(0);

    // 2. Try Rp format
    final matchRp = RegExp(r'Rp\.?\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(comment);
    if (matchRp != null) return double.parse(matchRp.group(1)!).toStringAsFixed(0);

    // 3. If comment is just a number
    final numVal = double.tryParse(comment.trim());
    if (numVal != null) return numVal.toStringAsFixed(0);
    
    // 4. Try to find a typical price number (>=1000) in the profile name (e.g. "2 Jam 2000")
    final profileMatch = RegExp(r'([0-9]{3,})').allMatches(profile);
    if (profileMatch.isNotEmpty) return profileMatch.last.group(1)!;
    
    // 5. Try to find any number >= 100 in the comment
    final commentMatch = RegExp(r'([0-9]{3,})').firstMatch(comment);
    if (commentMatch != null) return commentMatch.group(1)!;

    return "0";
  }

  DateTime? get createdDate {
    final match = RegExp(r'Date:(\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?)').firstMatch(comment);
    if (match != null) {
      return DateTime.tryParse(match.group(1)!);
    }
    return null;
  }

  bool get isNew {
    final cd = createdDate;
    if (cd != null) {
      final now = DateTime.now();
      return now.year == cd.year && now.month == cd.month && now.day == cd.day;
    }
    return false;
  }

  String get formattedTime {
    final cd = createdDate;
    if (cd != null) {
      final h = cd.hour > 12 ? cd.hour - 12 : (cd.hour == 0 ? 12 : cd.hour);
      final ampm = cd.hour >= 12 ? 'PM' : 'AM';
      final m = cd.minute.toString().padLeft(2, '0');
      return '${cd.year}-${cd.month.toString().padLeft(2, '0')}-${cd.day.toString().padLeft(2, '0')} $h:$m $ampm';
    }
    return '';
  }
}

class HotspotActive {
  final String id;
  final String user;
  final String address;
  final String macAddress;
  final String uptime;
  final String serverName;
  final String sessionTimeLeft;
  final String bytesIn;
  final String bytesOut;
  final String limitBytesTotal;
  final String comment;

  HotspotActive({
    required this.id,
    required this.user,
    required this.address,
    required this.macAddress,
    required this.uptime,
    required this.serverName,
    this.sessionTimeLeft = '',
    this.bytesIn = '0',
    this.bytesOut = '0',
    this.limitBytesTotal = '0',
    this.comment = '',
  });

  factory HotspotActive.fromMap(Map<String, String> map) {
    return HotspotActive(
      id: map['.id'] ?? '',
      user: map['user'] ?? '',
      address: map['address'] ?? '',
      macAddress: map['mac-address'] ?? '',
      uptime: map['uptime'] ?? '',
      serverName: map['server'] ?? '',
      sessionTimeLeft: map['session-time-left'] ?? map['limit-uptime'] ?? '',
      bytesIn: map['bytes-in'] ?? '0',
      bytesOut: map['bytes-out'] ?? '0',
      limitBytesTotal: map['limit-bytes-total'] ?? map['bytes-total'] ?? '0',
      comment: map['comment'] ?? '',
    );
  }

  String get formattedDataUsage {
    final bin = double.tryParse(bytesIn) ?? 0;
    final bout = double.tryParse(bytesOut) ?? 0;
    final totalMb = (bin + bout) / (1024 * 1024);
    if (totalMb >= 1024) {
      return '${(totalMb / 1024).toStringAsFixed(1)} GB';
    }
    return '${totalMb.toStringAsFixed(1)} MB';
  }

  String get formattedDataLeft {
    final limit = double.tryParse(limitBytesTotal) ?? 0;
    if (limit <= 0) return 'Unlimited Data';

    final bin = double.tryParse(bytesIn) ?? 0;
    final bout = double.tryParse(bytesOut) ?? 0;
    final used = bin + bout;
    final leftBytes = limit - used;

    if (leftBytes <= 0) return '0 MB Left (Exhausted)';

    final leftMb = leftBytes / (1024 * 1024);
    if (leftMb >= 1024) {
      return '${(leftMb / 1024).toStringAsFixed(2)} GB Left';
    }
    return '${leftMb.toStringAsFixed(1)} MB Left';
  }

  double get dataUsageProgress {
    final limit = double.tryParse(limitBytesTotal) ?? 0;
    if (limit <= 0) return 0.0;
    final bin = double.tryParse(bytesIn) ?? 0;
    final bout = double.tryParse(bytesOut) ?? 0;
    final used = bin + bout;
    final ratio = used / limit;
    return ratio.clamp(0.0, 1.0);
  }

  String get formattedTimeLeft {
    if (sessionTimeLeft.isEmpty) return 'Unlimited';
    return sessionTimeLeft;
  }
}
