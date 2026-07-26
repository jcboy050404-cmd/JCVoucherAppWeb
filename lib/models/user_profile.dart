class UserProfile {
  final String id;
  final String name;
  final String rateLimit;
  final String sharedUsers;
  final String parentQueue;
  final String onLogin;
  final String onLogout;

  UserProfile({
    required this.id,
    required this.name,
    this.rateLimit = '',
    this.sharedUsers = '1',
    this.parentQueue = '',
    this.onLogin = '',
    this.onLogout = '',
  });

  factory UserProfile.fromMap(Map<String, String> map) {
    return UserProfile(
      id: map['.id'] ?? '',
      name: map['name'] ?? '',
      rateLimit: map['rate-limit'] ?? '',
      sharedUsers: map['shared-users'] ?? '1',
      parentQueue: map['parent-queue'] ?? '',
      onLogin: map['on-login'] ?? '',
      onLogout: map['on-logout'] ?? '',
    );
  }
}
