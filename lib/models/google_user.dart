import 'dart:convert';

/// Represents an authenticated Google / Gmail user profile.
class GoogleUserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? idToken;
  final bool isAdmin;
  final DateTime signedInAt;

  GoogleUserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.idToken,
    this.isAdmin = false,
    DateTime? signedInAt,
  }) : signedInAt = signedInAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'idToken': idToken,
      'isAdmin': isAdmin,
      'signedInAt': signedInAt.toIso8601String(),
    };
  }

  factory GoogleUserModel.fromMap(Map<String, dynamic> map) {
    return GoogleUserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      photoUrl: map['photoUrl'],
      idToken: map['idToken'],
      isAdmin: map['isAdmin'] == true,
      signedInAt: map['signedInAt'] != null
          ? DateTime.tryParse(map['signedInAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory GoogleUserModel.fromJson(String source) =>
      GoogleUserModel.fromMap(json.decode(source));
}
