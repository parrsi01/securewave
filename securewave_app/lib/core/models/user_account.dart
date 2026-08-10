class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.isActive,
    this.emailVerified,
    this.subscriptionStatus,
  });

  final int id;
  final String email;
  final bool isActive;
  final bool? emailVerified;
  final String? subscriptionStatus;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email']?.toString() ?? '',
      isActive: json['is_active'] == true,
      emailVerified: json.containsKey('email_verified')
          ? json['email_verified'] == true
          : null,
      subscriptionStatus: _optionalString(json['subscription_status']),
    );
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
