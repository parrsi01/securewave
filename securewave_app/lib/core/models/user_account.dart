class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.isActive,
  });

  final int id;
  final String email;
  final bool isActive;

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: (json['id'] as num?)?.toInt() ?? 0,
      email: json['email']?.toString() ?? '',
      isActive: json['is_active'] == true,
    );
  }
}
