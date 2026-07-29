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
  final String uptime;
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
    this.uptime = '0s',
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
      limitBytes: map['limit-bytes-total'] ?? map['limit-bytes-out'] ?? '',
      bytesIn: map['bytes-in'] ?? '0',
      bytesOut: map['bytes-out'] ?? '0',
      uptime: map['uptime'] ?? '0s',
      disabled: map['disabled'] == 'true',
      createdAt: map['last-logged-out'] ?? '',
    );
  }

  bool get isUsed {
    // Expired vouchers are never considered "used" — they go to the Expired tab.
    if (isExpired) return false;
    final bin = double.tryParse(bytesIn) ?? 0;
    final bout = double.tryParse(bytesOut) ?? 0;
    if (bin > 0 || bout > 0) return true;
    if (uptime.isNotEmpty && uptime != '0s' && uptime != '0') return true;
    final lower = comment.toLowerCase();
    if (lower.contains('exp:') || lower.contains('log:') || lower.contains('used')) {
      return true;
    }
    return false;
  }

  bool get isExpired {
    // 1. Router already stamped the voucher as expired (via our disable script)
    final lower = comment.toLowerCase();
    if (disabled && (lower.contains('exp:') || lower.contains('expired'))) {
      return true;
    }

    // 2. Uptime limit fully consumed
    if (limitUptime.isNotEmpty && uptime.isNotEmpty && uptime != '0s' && uptime != '0') {
      final limitSec = _parseUptimeSeconds(limitUptime);
      final usedSec = _parseUptimeSeconds(uptime);
      if (limitSec > 0 && usedSec >= limitSec) return true;
    }

    // 3. Data limit fully consumed
    if (limitBytes.isNotEmpty) {
      final limit = double.tryParse(limitBytes) ?? 0;
      final bin = double.tryParse(bytesIn) ?? 0;
      final bout = double.tryParse(bytesOut) ?? 0;
      if (limit > 0 && (bin + bout) >= limit) return true;
    }

    return false;
  }

  /// Parses MikroTik uptime/limit-uptime strings (e.g. "1d2h30m15s", "3600", "2h") into seconds.
  static int _parseUptimeSeconds(String s) {
    s = s.trim();
    // Plain seconds (MikroTik sometimes returns a raw number)
    final plain = int.tryParse(s);
    if (plain != null) return plain;
    int total = 0;
    // Match optional weeks, days, hours, minutes, seconds
    final re = RegExp(r'(?:(\d+)w)?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?');
    final m = re.firstMatch(s);
    if (m != null) {
      total += (int.tryParse(m.group(1) ?? '') ?? 0) * 7 * 86400;
      total += (int.tryParse(m.group(2) ?? '') ?? 0) * 86400;
      total += (int.tryParse(m.group(3) ?? '') ?? 0) * 3600;
      total += (int.tryParse(m.group(4) ?? '') ?? 0) * 60;
      total += (int.tryParse(m.group(5) ?? '') ?? 0);
    }
    return total;
  }

  String get displayCode => name.toUpperCase();

  String get customerName {
    final match = RegExp(r'cname:(.*?)(?=\s+[a-zA-Z0-9]+:|$)').firstMatch(comment);
    if (match != null) {
      String name = match.group(1)?.trim() ?? '';
      // Remove trailing date text if present
      name = name.replaceAll(RegExp(r'\s*\d{4}-\d{1,2}-\d{1,2}.*$'), '').trim();
      name = name.replaceAll(RegExp(r'\s*[a-z]{3}/\d{1,2}/\d{4}.*$', caseSensitive: false), '').trim();
      return name;
    }
    return '';
  }

  double get price {
    // 1. Try strict P: format
    final matchP = RegExp(r'P:([0-9]+(?:\.[0-9]+)?)').firstMatch(comment);
    if (matchP != null) return double.tryParse(matchP.group(1)!) ?? 0.0;

    // 2. Try ₱ or Rp format or price: tag
    final matchSymbol = RegExp(r'(?:₱|Rp\.?|price:?\s*)([0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(comment);
    if (matchSymbol != null) return double.tryParse(matchSymbol.group(1)!) ?? 0.0;

    // 3. If comment is just a number
    final numVal = double.tryParse(comment.trim());
    if (numVal != null) return numVal;

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
    // 1. Explicit Date: tag (supports 1 or 2 digit month/day)
    final match = RegExp(r'Date:(\d{4}-\d{1,2}-\d{1,2}(?:\s+\d{1,2}:\d{1,2}(?::\d{1,2})?)?)').firstMatch(comment);
    if (match != null) {
      return DateTime.tryParse(match.group(1)!);
    }
    
    // 2. MikroTik exp: tag (e.g. exp:jul/28/2026 or exp:2026-07-28)
    final expMatch = RegExp(r'exp:([a-zA-Z]{3}/\d{1,2}/\d{4}|\d{4}-\d{1,2}-\d{1,2})').firstMatch(comment);
    if (expMatch != null) {
      final dateStr = expMatch.group(1)!;
      if (dateStr.contains('/')) {
        // Parse MikroTik format mmm/dd/yyyy
        final parts = dateStr.split('/');
        final monthStr = parts[0].toLowerCase();
        final day = int.tryParse(parts[1]) ?? 1;
        final year = int.tryParse(parts[2]) ?? 2000;
        const months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
        };
        final month = months[monthStr] ?? 1;
        return DateTime(year, month, day);
      } else {
        return DateTime.tryParse(dateStr);
      }
    }

    // 3. Fallback to createdAt
    if (createdAt.isNotEmpty) {
      final parsed = DateTime.tryParse(createdAt);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? get activationDate {
    // 1. MikroTik log: tag (appended by script upon first login)
    final logMatch = RegExp(r'log:([a-zA-Z]{3}/\d{1,2}/\d{4}|\d{4}-\d{1,2}-\d{1,2})').firstMatch(comment);
    if (logMatch != null) {
      final dateStr = logMatch.group(1)!;
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        final monthStr = parts[0].toLowerCase();
        final day = int.tryParse(parts[1]) ?? 1;
        final year = int.tryParse(parts[2]) ?? 2000;
        const months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
        };
        final month = months[monthStr] ?? 1;
        return DateTime(year, month, day);
      } else {
        return DateTime.tryParse(dateStr);
      }
    }

    // 2. Fallback to generation date
    return createdDate;
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
      limitBytesTotal: map['limit-bytes-total'] ?? map['limit-bytes-out'] ?? map['bytes-total'] ?? '0',
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

  String get customerName {
    final match = RegExp(r'cname:(.*?)(?=\s+[a-zA-Z0-9]+:|$)').firstMatch(comment);
    if (match != null) {
      String name = match.group(1)?.trim() ?? '';
      // Remove trailing date text if present
      name = name.replaceAll(RegExp(r'\s*\d{4}-\d{1,2}-\d{1,2}.*$'), '').trim();
      name = name.replaceAll(RegExp(r'\s*[a-z]{3}/\d{1,2}/\d{4}.*$', caseSensitive: false), '').trim();
      return name;
    }
    return '';
  }
}
