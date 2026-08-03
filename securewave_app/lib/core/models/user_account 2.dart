class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.isActive,
    required this.emailVerified,
    required this.has2fa,
    required this.subscriptionStatus,
    this.createdAt,
    this.lastLogin,
  });

  final int id;
  final String email;
  final bool isActive;
  final bool emailVerified;
  final bool has2fa;
  final String subscriptionStatus;
  final DateTime? createdAt;
  final DateTime? lastLogin;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email']?.toString() ?? '',
      isActive: json['is_active'] == true ||
          json['account_status']?.toString().toLowerCase() == 'active',
      emailVerified: json['email_verified'] == true,
      has2fa: json['has_2fa'] == true,
      subscriptionStatus:
          json['subscription_status']?.toString().trim().isNotEmpty == true
              ? json['subscription_status'].toString()
              : 'unknown',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      lastLogin: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'].toString())
          : null,
    );
  }
}
