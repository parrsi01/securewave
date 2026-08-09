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

  double get safeDataCapGb =>
      dataCapGb.isFinite && dataCapGb > 0 ? dataCapGb : 0;

  double get safeUsedGb => usedGb.isFinite && usedGb > 0 ? usedGb : 0;

  bool get isUnlimited => isPremium && safeDataCapGb == 0;

  double get remainingGb {
    if (isUnlimited || safeDataCapGb == 0) return 0;
    return (safeDataCapGb - safeUsedGb).clamp(0, safeDataCapGb).toDouble();
  }

  double get usagePercent {
    if (isUnlimited || safeDataCapGb == 0) return 0;
    return (safeUsedGb / safeDataCapGb).clamp(0, 1).toDouble();
  }

  factory UserPlan.fromJson(Map<String, dynamic> json) {
    return UserPlan(
      name: _nonEmptyString(json['plan_name']) ?? 'Free',
      isPremium:
          json['plan_tier']?.toString().trim().toLowerCase() == 'premium',
      dataCapGb: _finiteDouble(json['data_cap_gb'], fallback: 5),
      usedGb: _finiteDouble(json['used_gb']),
      renewalDate: json['renewal_date'] == null
          ? null
          : DateTime.tryParse(json['renewal_date'].toString()),
    );
  }

  static double _finiteDouble(Object? value, {double fallback = 0}) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
