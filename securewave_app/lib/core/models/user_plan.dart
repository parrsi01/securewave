class UserPlan {
  const UserPlan({
    required this.name,
    required this.isPremium,
    required this.dataCapGb,
    required this.usedGb,
    required this.speedDownMbps,
    required this.speedUpMbps,
    this.renewalDate,
  });

  final String name;
  final bool isPremium;
  final double dataCapGb;
  final double usedGb;
  final double speedDownMbps;
  final double speedUpMbps;
  final DateTime? renewalDate;

  bool get isUnlimited => isPremium && dataCapGb == 0;

  double get remainingGb =>
      isUnlimited ? 0 : (dataCapGb - usedGb).clamp(0, dataCapGb).toDouble();

  double get usagePercent =>
      isUnlimited ? 0 : (usedGb / dataCapGb).clamp(0, 1).toDouble();

  factory UserPlan.fromJson(Map<String, dynamic> json) {
    final planTier = json['plan_tier']?.toString().toLowerCase() ?? 'free';
    final isPaidTier = planTier != 'free';
    return UserPlan(
      name: json['plan_name']?.toString() ?? 'Free',
      isPremium: isPaidTier,
      dataCapGb: (json['data_cap_gb'] as num?)?.toDouble() ?? 5,
      usedGb: (json['used_gb'] as num?)?.toDouble() ?? 0,
      speedDownMbps: (json['speed_limit_mbps_down'] as num?)?.toDouble() ??
          (isPaidTier ? 250 : 25),
      speedUpMbps: (json['speed_limit_mbps_up'] as num?)?.toDouble() ??
          (isPaidTier ? 100 : 10),
      renewalDate: json['renewal_date'] != null
          ? DateTime.tryParse(json['renewal_date'].toString())
          : null,
    );
  }
}
