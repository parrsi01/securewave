enum DiagnosticStatus { ok, failed, retrying }

class DiagnosticResult {
  const DiagnosticResult({
    required this.key,
    required this.label,
    required this.status,
    required this.message,
  });

  final String key;
  final String label;
  final DiagnosticStatus status;
  final String message;

  DiagnosticResult copyWith({
    DiagnosticStatus? status,
    String? message,
  }) {
    return DiagnosticResult(
      key: key,
      label: label,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}
