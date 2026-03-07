import 'package:flutter/material.dart';

import '../core/models/vpn_status.dart';
import 'app_ui_v1.dart';
import 'status_indicator.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.status,
    required this.statusLabel,
    required this.serverLabel,
    required this.protocolLabel,
    required this.durationLabel,
    required this.stageLabel,
    this.detail,
  });

  final VpnStatus status;
  final String statusLabel;
  final String serverLabel;
  final String protocolLabel;
  final String durationLabel;
  final String stageLabel;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusIndicator(status: status, label: statusLabel, large: true),
            const SizedBox(height: AppUIv1.space4),
            _Item(label: 'Location', value: serverLabel),
            const SizedBox(height: AppUIv1.space3),
            _Item(label: 'Protocol', value: protocolLabel),
            const SizedBox(height: AppUIv1.space3),
            _Item(label: 'Duration', value: durationLabel),
            const SizedBox(height: AppUIv1.space3),
            _Item(label: 'Pipeline', value: stageLabel),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: AppUIv1.space3),
              Text(
                detail!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppUIv1.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Flexible(
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
