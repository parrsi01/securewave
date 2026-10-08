import 'package:flutter/material.dart';

import 'theme.dart';

/// Supplied display values only; no counters or polling live in this widget.
class TransferSummary extends StatelessWidget {
  const TransferSummary({
    super.key,
    required this.download,
    required this.upload,
    required this.available,
    this.label = 'Session transfer',
    this.compact = false,
  });
  final String download;
  final String upload;
  final bool available;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTheme.sectionTitle),
          SizedBox(height: compact ? 8 : 12),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < (compact ? 240 : 360) ||
                MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
            final down = _value('Download', download, Icons.south);
            final up = _value('Upload', upload, Icons.north);
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [down, const SizedBox(height: 16), up])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: down),
                    const SizedBox(width: 24),
                    Expanded(child: up),
                  ]);
          }),
        ],
      );

  Widget _value(String label, String value, IconData icon) => Semantics(
        label: '$label recorded VPN transfer: $value',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: AppTheme.smallBody)),
            ]),
            const SizedBox(height: 4),
            Text(value,
                style: available
                    ? (compact
                        ? AppTheme.transfer.copyWith(fontSize: 22)
                        : AppTheme.transfer)
                    : AppTheme.smallBody),
          ],
        ),
      );
}
