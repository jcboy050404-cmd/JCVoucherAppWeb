class PppoeUser {
  final String id;
  final String name;
  final String password;
  final String profile;
  final String service;
  final String remoteAddress;
  final String localAddress;
  final String comment;
  final bool disabled;
  final bool isOnline;
  final String callerId;
  final String uptime;
  final DateTime? dueDate;
  final double monthlyFee;

  PppoeUser({
    required this.id,
    required this.name,
    required this.password,
    this.profile = 'default',
    this.service = 'pppoe',
    this.remoteAddress = '',
    this.localAddress = '',
    this.comment = '',
    this.disabled = false,
    this.isOnline = false,
    this.callerId = '',
    this.uptime = '',
    this.dueDate,
    this.monthlyFee = 0.0,
  });

  int? get daysUntilDue {
    if (dueDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.difference(today).inDays;
  }

  bool get isOverdue {
    final days = daysUntilDue;
    return days != null && days <= 0;
  }

  bool get isDueSoon {
    final days = daysUntilDue;
    return days != null && days > 0 && days <= 3;
  }

  factory PppoeUser.fromSecretMap(Map<String, String> map) {
    return PppoeUser(
      id: map['.id'] ?? '',
      name: map['name'] ?? '',
      password: map['password'] ?? '',
      profile: map['profile'] ?? 'default',
      service: map['service'] ?? 'pppoe',
      remoteAddress: map['remote-address'] ?? '',
      localAddress: map['local-address'] ?? '',
      comment: map['comment'] ?? '',
      disabled: map['disabled'] == 'true',
    );
  }

  PppoeUser copyWith({
    String? id,
    String? name,
    String? password,
    String? profile,
    String? service,
    String? remoteAddress,
    String? localAddress,
    String? comment,
    bool? disabled,
    bool? isOnline,
    String? callerId,
    String? uptime,
    Object? dueDate = _sentinel,   // use sentinel so null can be passed explicitly
    double? monthlyFee,
  }) {
    return PppoeUser(
      id: id ?? this.id,
      name: name ?? this.name,
      password: password ?? this.password,
      profile: profile ?? this.profile,
      service: service ?? this.service,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      localAddress: localAddress ?? this.localAddress,
      comment: comment ?? this.comment,
      disabled: disabled ?? this.disabled,
      isOnline: isOnline ?? this.isOnline,
      callerId: callerId ?? this.callerId,
      uptime: uptime ?? this.uptime,
      dueDate: identical(dueDate, _sentinel) ? this.dueDate : dueDate as DateTime?,
      monthlyFee: monthlyFee ?? this.monthlyFee,
    );
  }
}

const Object _sentinel = Object();

class PppoeActiveSession {
  final String id;
  final String name;
  final String service;
  final String callerId;
  final String address;
  final String uptime;

  PppoeActiveSession({
    required this.id,
    required this.name,
    required this.service,
    required this.callerId,
    required this.address,
    required this.uptime,
  });

  factory PppoeActiveSession.fromMap(Map<String, String> map) {
    return PppoeActiveSession(
      id: map['.id'] ?? '',
      name: map['name'] ?? '',
      service: map['service'] ?? 'pppoe',
      callerId: map['caller-id'] ?? '',
      address: map['address'] ?? '',
      uptime: map['uptime'] ?? '',
    );
  }
}
