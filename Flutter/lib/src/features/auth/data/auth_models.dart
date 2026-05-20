class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.name,
    this.nickname,
    this.phoneNumber,
    this.contactEmail,
    this.gender,
    this.companyName,
    this.position,
    this.department,
    this.birthDate,
    this.status,
    this.avatarColor,
    this.statusMessage,
    this.avatarImageUrl,
    this.profileBackgroundColor,
    this.profileBackgroundImageUrl,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'USER',
      name: json['name'] as String?,
      nickname: json['nickname'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      contactEmail: json['contactEmail'] as String?,
      gender: json['gender'] as String?,
      companyName: json['companyName'] as String?,
      position: json['position'] as String?,
      department: json['department'] as String?,
      birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
      status: json['status'] as String?,
      avatarColor: json['avatarColor'] as String?,
      statusMessage: json['statusMessage'] as String?,
      avatarImageUrl: json['avatarImageUrl'] as String?,
      profileBackgroundColor: json['profileBackgroundColor'] as String?,
      profileBackgroundImageUrl: json['profileBackgroundImageUrl'] as String?,
    );
  }

  final String id;
  final String email;
  final String displayName;
  final String role;
  final String? name;
  final String? nickname;
  final String? phoneNumber;
  final String? contactEmail;
  final String? gender;
  final String? companyName;
  final String? position;
  final String? department;
  final DateTime? birthDate;
  final String? status;
  final String? avatarColor;
  final String? statusMessage;
  final String? avatarImageUrl;
  final String? profileBackgroundColor;
  final String? profileBackgroundImageUrl;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'name': name,
      'nickname': nickname,
      'phoneNumber': phoneNumber,
      'contactEmail': contactEmail,
      'gender': gender,
      'companyName': companyName,
      'position': position,
      'department': department,
      'birthDate': birthDate?.toIso8601String(),
      'role': role,
      'status': status,
      'avatarColor': avatarColor,
      'statusMessage': statusMessage,
      'avatarImageUrl': avatarImageUrl,
      'profileBackgroundColor': profileBackgroundColor,
      'profileBackgroundImageUrl': profileBackgroundImageUrl,
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    final expiresInSeconds = json['expiresInSeconds'];
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresAt:
          expiresAt ??
          DateTime.now().add(
            Duration(
              seconds: expiresInSeconds is num
                  ? expiresInSeconds.toInt()
                  : 30 * 60,
            ),
          ),
      user: AuthUser.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }
}

class SignupResult {
  const SignupResult({
    required this.user,
    required this.pendingApproval,
    required this.message,
  });

  factory SignupResult.fromJson(Map<String, dynamic> json) {
    return SignupResult(
      user: AuthUser.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      pendingApproval: json['pendingApproval'] as bool? ?? false,
      message: json['message'] as String? ?? '',
    );
  }

  final AuthUser user;
  final bool pendingApproval;
  final String message;
}
