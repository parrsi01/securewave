class UserPlan {
  const UserPlan({
    required this.name,
    required this.isPremium,
    required this.dataCapGb,
    required this.usedGb,
    this.renewalDate,
  });

  final String name;
  final bool isPremium;
  final double dataCapGb;
  final double usedGb;
  final DateTime? renewalDate;

  double get remainingGb => (dataCapGb - usedGb).clamp(0, dataCapGb).toDouble();

  double get usagePercent =>
      dataCapGb == 0 ? 0 : (usedGb / dataCapGb).clamp(0, 1).toDouble();

  factory UserPlan.fromJson(Map<String, dynamic> json) {
    return UserPlan(
      name: json['plan_name']?.toString() ?? 'Free',
      isPremium: json['plan_tier']?.toString().toLowerCase() == 'premium',
      dataCapGb: (json['data_cap_gb'] as num?)?.toDouble() ?? 5,
      usedGb: (json['used_gb'] as num?)?.toDouble() ?? 0,
      renewalDate: json['renewal_date'] != null
          ? DateTime.tryParse(json['renewal_date'].toString())
          : null,
    );
  }
}
