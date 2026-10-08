import 'package:flutter/material.dart';

import '../services/account_usage.dart';
import 'theme.dart';

class MonthlyUsageView extends StatelessWidget {
  const MonthlyUsageView(
      {super.key,
      required this.store,
      required this.onRefresh,
      this.compact = false});
  final AccountUsageStore store;
  final VoidCallback onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final summary = store.summary;
    final used = store.usedBytes;
    final quota = summary?.quotaBytes;
    final percent =
        used == null || quota == null ? null : (used / quota).clamp(0.0, 1.0);
    final label = used == null
        ? (store.loading
            ? 'Loading monthly usage…'
            : 'Monthly usage unavailable')
        : quota == null
            ? '${formatDataBytes(used)} used this month'
            : '${formatDataBytes(used)} of ${quota == 5000000000 ? '5 GB' : formatDataBytes(quota)} used';
    return Column(
      key: const ValueKey('monthly-usage'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Monthly data', style: AppTheme.sectionTitle)),
          MergeSemantics(
              child: Semantics(
                  label: 'Refresh monthly usage',
                  button: true,
                  child: IconButton(
                      tooltip: 'Refresh monthly usage',
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                      padding: const EdgeInsets.all(8),
                      onPressed: store.loading ? null : onRefresh,
                      icon: const Icon(Icons.refresh, size: 20)))),
        ]),
        SizedBox(height: compact ? 4 : 8),
        Text(label,
            key: const ValueKey('monthly-usage-value'), style: AppTheme.body),
        if (percent != null) ...[
          SizedBox(height: compact ? 8 : 12),
          Semantics(
            label: label,
            child: LinearProgressIndicator(
              key: const ValueKey('monthly-usage-bar'),
              value: percent,
              minHeight: 8,
              color: store.limitReached
                  ? AppTheme.warning
                  : AppTheme.accentPrimary,
              backgroundColor: AppTheme.surfaceInteractive,
            ),
          ),
        ],
        if (summary != null) ...[
          SizedBox(height: compact ? 4 : 8),
          Text('Renews ${_date(summary.periodEnd)} (UTC)',
              style: AppTheme.caption),
        ],
        if (store.limitReached) ...[
          SizedBox(height: compact ? 4 : 8),
          Text('Monthly allowance used. Connect again after it renews.',
              style: AppTheme.smallBody.copyWith(color: AppTheme.warning)),
        ],
        if (store.syncNotice != null) ...[
          SizedBox(height: compact ? 4 : 8),
          Text(store.syncNotice!, style: AppTheme.caption),
        ],
      ],
    );
  }

  String _date(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
