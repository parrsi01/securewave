class UserPlan {
  const UserPlan({
    required this.name,
    required this.isPremium,
    required this.dataCapGb,
    required this.usedGb,
    required this.dataCapBytes,
    required this.usedBytes,
    required this.speedDownMbps,
    required this.speedUpMbps,
    this.renewalDate,
  });

  final String name;
  final bool isPremium;
  final double dataCapGb;
  final double usedGb;
  final int dataCapBytes;
  final int usedBytes;
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
    final dataCapGb = (json['data_cap_gb'] as num?)?.toDouble() ?? 5;
    final usedGb = (json['used_gb'] as num?)?.toDouble() ?? 0;
    final dataCapBytes = (json['quota_bytes'] as num?)?.toInt() ??
        (dataCapGb * 1024 * 1024 * 1024).round();
    final usedBytes = (json['used_bytes'] as num?)?.toInt() ??
        (usedGb * 1024 * 1024 * 1024).round();
    return UserPlan(
      name: json['plan_name']?.toString() ?? 'Free',
      isPremium: isPaidTier,
      dataCapGb: dataCapGb,
      usedGb: usedGb,
      dataCapBytes: dataCapBytes,
      usedBytes: usedBytes,
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
