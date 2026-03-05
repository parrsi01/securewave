import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Manage Devices screen — lists active devices with delete capability.
class ManageDevicesScreen extends ConsumerStatefulWidget {
  const ManageDevicesScreen({super.key});

  @override
  ConsumerState<ManageDevicesScreen> createState() =>
      _ManageDevicesScreenState();
}

class _ManageDevicesScreenState extends ConsumerState<ManageDevicesScreen> {
  late Future<DeviceListResult> _devicesFuture;
  int? _deletingId;

  @override
  void initState() {
    super.initState();
    _devicesFuture = _loadDevices();
  }

  Future<DeviceListResult> _loadDevices() {
    return ref.read(apiClientProvider).listDevices();
  }

  void _refresh() {
    setState(() {
      _devicesFuture = _loadDevices();
    });
  }

  Future<void> _confirmDelete(DeviceInfo device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
          'Remove "${device.name ?? 'Device #${device.id}'}"?\n'
          'This will revoke its VPN access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = device.id);
    try {
      await ref.read(apiClientProvider).deleteDevice(device.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device removed')),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove device: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Devices'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: FutureBuilder<DeviceListResult>(
            future: _devicesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _ErrorView(
                  error: snapshot.error.toString(),
                  onRetry: _refresh,
                );
              }

              final result = snapshot.data!;
              return _DeviceListView(
                result: result,
                isDark: isDark,
                deletingId: _deletingId,
                onDelete: _confirmDelete,
                onRefresh: _refresh,
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Device list view ────────────────────────────────────────────────────────

class _DeviceListView extends StatelessWidget {
  const _DeviceListView({
    required this.result,
    required this.isDark,
    required this.deletingId,
    required this.onDelete,
    required this.onRefresh,
  });

  final DeviceListResult result;
  final bool isDark;
  final int? deletingId;
  final void Function(DeviceInfo) onDelete;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.space4),
        children: [
          // ── Quota bar ──
          _QuotaBar(
            used: result.total,
            limit: result.limit,
            isDark: isDark,
          ),
          const SizedBox(height: AppSpacing.space4),

          if (result.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space8),
              child: Center(
                child: Text(
                  'No active devices',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isDark
                            ? AppColors.darkInkMuted
                            : AppColors.inkMuted,
                      ),
                ),
              ),
            )
          else
            ...result.devices.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                  child: _DeviceCard(
                    device: device,
                    isDark: isDark,
                    isDeleting: deletingId == device.id,
                    onDelete: () => onDelete(device),
                  ),
                )),
        ],
      ),
    );
  }
}

// ── Quota bar ───────────────────────────────────────────────────────────────

class _QuotaBar extends StatelessWidget {
  const _QuotaBar({
    required this.used,
    required this.limit,
    required this.isDark,
  });

  final int used;
  final int limit;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final atLimit = used >= limit;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Device Slots',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                '$used / $limit',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: atLimit ? AppColors.error : AppColors.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: isDark
                  ? AppColors.darkSurfaceMuted
                  : AppColors.surfaceMuted,
              color: atLimit ? AppColors.error : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Device card ─────────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isDark,
    required this.isDeleting,
    required this.onDelete,
  });

  final DeviceInfo device;
  final bool isDark;
  final bool isDeleting;
  final VoidCallback onDelete;

  IconData _platformIcon(String? deviceType) {
    return switch (deviceType?.toLowerCase()) {
      'linux' => Icons.computer_rounded,
      'windows' => Icons.desktop_windows_rounded,
      'macos' || 'darwin' => Icons.laptop_mac_rounded,
      'android' => Icons.phone_android_rounded,
      'ios' => Icons.phone_iphone_rounded,
      _ => Icons.devices_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = device.name ?? 'Device #${device.id}';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: Icon(
            _platformIcon(device.deviceType),
            size: AppSpacing.iconS,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(
          [
            if (device.serverLocation != null) device.serverLocation!,
            device.ipAddress,
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.error,
                iconSize: AppSpacing.iconS,
                tooltip: 'Remove device',
                onPressed: onDelete,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── Error view ──────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.space3),
            Text('Failed to load devices',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.space2),
            Text(error,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.space4),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
