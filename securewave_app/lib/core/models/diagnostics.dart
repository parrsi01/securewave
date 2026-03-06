enum DiagnosticStatus { ok, failed, retrying }

class DiagnosticResult {
  const DiagnosticResult({
    required this.key,
    required this.label,
    required this.status,
    required this.message,
    this.commands = const <String>[],
    this.checkedAt,
  });

  final String key;
  final String label;
  final DiagnosticStatus status;
  final String message;
  final List<String> commands;
  final DateTime? checkedAt;

  DiagnosticResult copyWith({
    DiagnosticStatus? status,
    String? message,
    List<String>? commands,
    DateTime? checkedAt,
  }) {
    return DiagnosticResult(
      key: key,
      label: label,
      status: status ?? this.status,
      message: message ?? this.message,
      commands: commands ?? this.commands,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'label': label,
      'status': status.name,
      'message': message,
      'commands': commands,
      'checkedAt': checkedAt?.toIso8601String(),
    };
  }

  factory DiagnosticResult.fromJson(Map<String, dynamic> json) {
    return DiagnosticResult(
      key: json['key']?.toString() ?? 'UNKNOWN',
      label: json['label']?.toString() ?? 'Unknown check',
      status: DiagnosticStatus.values.firstWhere(
        (DiagnosticStatus status) => status.name == json['status'],
        orElse: () => DiagnosticStatus.failed,
      ),
      message: json['message']?.toString() ?? 'Unknown diagnostics result.',
      commands: (json['commands'] as List<dynamic>? ?? const <dynamic>[])
          .map((Object? item) => item?.toString() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList(),
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.tryParse(json['checkedAt'].toString()),
    );
  }
}
