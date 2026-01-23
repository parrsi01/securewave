import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/app_loader.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'vpn_controller.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnControllerProvider);
    final servers = ref.watch(serversProvider);
    final status = ref.watch(vpnStatusProvider);
    final vpnService = ref.watch(vpnServiceProvider);
    String? platformNotice;
    if (vpnService is VpnServiceUnsupported) {
      platformNotice = vpnService.message;
    }

    final selectedServerLabel = servers.maybeWhen(
      data: (data) {
        if (data.isEmpty) return null;
        final selected = data.firstWhere(
          (server) => server['server_id'] == vpnState.selectedServerId,
          orElse: () => data.first,
        );
        return selected['location']?.toString() ?? 'Auto-select';
      },
      orElse: () => null,
    );

    return SafeArea(
      child: ContentLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SectionHeader(
              title: 'VPN Connection',
              subtitle: 'Tap the control below to connect. The app handles everything automatically.',
            ),
            if (platformNotice != null) ...[
              const SizedBox(height: 12),
              InlineBanner(message: platformNotice),
            ],
            const SizedBox(height: 24),
            // Status Panel Card
            _VpnStatusCard(
              vpnState: vpnState,
              status: status,
              serverLabel: selectedServerLabel,
              onToggle: vpnState.isBusy
                  ? null
                  : () {
                      if (vpnState.status == VpnStatus.connected) {
                        ref.read(vpnControllerProvider.notifier).disconnect();
                      } else {
                        ref.read(vpnControllerProvider.notifier).connect();
                      }
                    },
            ),
            const SizedBox(height: 20),
            // Server Selection Card
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppTheme.buttonGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.public, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Server Region', style: Theme.of(context).textTheme.titleMedium),
                              Text('Select your preferred location',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    servers.when(
                      data: (data) {
                        if (vpnState.selectedServerId == null && data.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            ref.read(vpnControllerProvider.notifier).selectServer(
                                  data.first['server_id'] as String?,
                                );
                          });
                        }
                        final selected = data.firstWhere(
                          (server) => server['server_id'] == vpnState.selectedServerId,
                          orElse: () => {},
                        );
                        final selectedLabel = selected['location'] ?? 'Auto-select';
                        return DropdownButtonFormField<String>(
                          key: ValueKey(vpnState.selectedServerId ?? 'auto'),
                          initialValue: vpnState.selectedServerId,
                          decoration: InputDecoration(
                            labelText: 'Select region',
                            helperText: 'Currently: $selectedLabel',
                            prefixIcon: const Icon(Icons.location_on_outlined),
                          ),
                          items: data
                              .map((server) => DropdownMenuItem<String>(
                                    value: server['server_id'] as String?,
                                    child: Text(server['location'] ?? 'Unknown'),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              ref.read(vpnControllerProvider.notifier).selectServer(value),
                        );
                      },
                      loading: () => const AppLoader(),
                      error: (_, __) => const InlineBanner(
                          message: 'Unable to load servers. Check your connection and try again.'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The app uses your region preference when you connect.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Diagnostics',
                    icon: Icons.speed,
                    onPressed: () => context.go('/tests'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SecondaryButton(
                    label: 'Devices',
                    icon: Icons.devices,
                    onPressed: () => context.go('/devices'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Troubleshooting section (collapsible)
            _TroubleshootingSection(),
          ],
        ),
      ),
    );
  }
}

// VPN Status Card with clear status transitions
class _VpnStatusCard extends StatelessWidget {
  const _VpnStatusCard({
    required this.vpnState,
    required this.status,
    this.serverLabel,
    this.onToggle,
  });

  final VpnUiState vpnState;
  final AsyncValue<VpnStatus> status;
  final String? serverLabel;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return status.when(
      data: (data) => _StatusDisplay(
        status: data,
        vpnState: vpnState,
        serverLabel: serverLabel,
        onToggle: onToggle,
      ),
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _ErrorBanner(message: 'Unable to read VPN status. Please refresh.'),
        ),
      ),
    );
  }
}

class _StatusDisplay extends StatelessWidget {
  const _StatusDisplay({
    required this.status,
    required this.vpnState,
    this.serverLabel,
    this.onToggle,
  });

  final VpnStatus status;
  final VpnUiState vpnState;
  final String? serverLabel;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 360;
    final ringSize = isCompact ? 150.0 : 180.0;
    final ringOuter = ringSize + 20;
    final hasError = vpnState.errorMessage != null;
    final label = hasError ? 'Error' : _statusLabel(status);
    final detail = hasError ? vpnState.errorMessage! : _statusDetail(status);
    final color = hasError ? AppTheme.error : _statusColor(status);
    final icon = _statusIcon(status);
    final isActive = status == VpnStatus.connected;
    final isConnecting = status == VpnStatus.connecting || status == VpnStatus.disconnecting;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    AppTheme.success.withValues(alpha: 0.12),
                    AppTheme.success.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              if (serverLabel != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Server: $serverLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onToggle,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: ringSize,
                      height: ringSize,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.4), width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 54),
                    ),
                    if (isConnecting || vpnState.isBusy)
                      SizedBox(
                        width: ringOuter,
                        height: ringOuter,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isActive ? 'Tap to disconnect' : 'Tap to connect',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              if (isActive) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _DataRateChip(
                      icon: Icons.arrow_downward,
                      value: '${vpnState.dataRateDown.toStringAsFixed(1)} Mbps',
                      label: 'Down',
                    ),
                    _DataRateChip(
                      icon: Icons.arrow_upward,
                      value: '${vpnState.dataRateUp.toStringAsFixed(1)} Mbps',
                      label: 'Up',
                    ),
                  ],
                ),
              ],
              if (hasError) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: vpnState.errorMessage!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'Connected';
      case VpnStatus.connecting:
        return 'Connecting...';
      case VpnStatus.disconnecting:
        return 'Disconnecting...';
      case VpnStatus.disconnected:
        return 'Disconnected';
    }
  }

  String _statusDetail(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'You are protected. Tap to disconnect anytime.';
      case VpnStatus.connecting:
        return 'Connecting securely. Keep the app open.';
      case VpnStatus.disconnecting:
        return 'Disconnecting safely. Please wait.';
      case VpnStatus.disconnected:
        return 'Tap to connect. SecureWave handles setup automatically.';
    }
  }

  IconData _statusIcon(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return Icons.shield;
      case VpnStatus.connecting:
        return Icons.sync;
      case VpnStatus.disconnecting:
        return Icons.sync_disabled;
      case VpnStatus.disconnected:
        return Icons.shield_outlined;
    }
  }

  Color _statusColor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return AppTheme.success;
      case VpnStatus.connecting:
        return AppTheme.accent;
      case VpnStatus.disconnecting:
        return AppTheme.warning;
      case VpnStatus.disconnected:
        return const Color(0xFF94A3B8);
    }
  }
}

class _DataRateChip extends StatelessWidget {
  const _DataRateChip({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// Collapsible troubleshooting section
class _TroubleshootingSection extends StatefulWidget {
  @override
  State<_TroubleshootingSection> createState() => _TroubleshootingSectionState();
}

class _TroubleshootingSectionState extends State<_TroubleshootingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.help_outline, color: AppTheme.info, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Troubleshooting Tips', style: Theme.of(context).textTheme.titleMedium),
                        Text('Tap to ${_expanded ? 'collapse' : 'expand'}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),
                  _TipItem(text: 'Allow VPN permissions when prompted by your device.'),
                  _TipItem(text: 'Keep SecureWave open until status shows Connected.'),
                  _TipItem(text: 'If stuck Connecting, tap Disconnect, wait 5 seconds, then retry.'),
                  _TipItem(text: 'Switch regions if the selected server is busy or slow.'),
                  const SizedBox(height: 12),
                  Text('Contact Support If:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _TipItem(text: 'Status stays Connecting for more than 60 seconds.', isWarning: true),
                  _TipItem(text: 'You see repeated connection errors.', isWarning: true),
                  _TipItem(text: 'Speed tests drop below expected baseline.', isWarning: true),
                ],
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  const _TipItem({required this.text, this.isWarning = false});

  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: isWarning ? AppTheme.warning : AppTheme.success,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
