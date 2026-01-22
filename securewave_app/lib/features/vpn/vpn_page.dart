import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/buttons/primary_button.dart';
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
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: ContentLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SectionHeader(
              title: 'VPN Connection',
              subtitle: 'Choose a region and tap Connect to start your secure tunnel.',
            ),
            const SizedBox(height: 24),
            // Status Panel Card
            _VpnStatusCard(vpnState: vpnState, status: status),
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
                          value: vpnState.selectedServerId,
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
                    const SizedBox(height: 20),
                    // Error display
                    if (vpnState.errorMessage != null) ...[
                      _ErrorBanner(message: vpnState.errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    // Primary action button
                    PrimaryButton(
                      label: _primaryLabel(vpnState.status),
                      icon: _primaryIcon(vpnState.status),
                      isLoading: vpnState.isBusy,
                      onPressed: vpnState.isBusy
                          ? null
                          : () {
                              if (vpnState.status == VpnStatus.connected) {
                                ref.read(vpnControllerProvider.notifier).disconnect();
                              } else {
                                ref.read(vpnControllerProvider.notifier).connect();
                              }
                            },
                    ),
                    const SizedBox(height: 12),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Troubleshooting section (collapsible)
            _TroubleshootingSection(),
          ],
        ),
      ),
    );
  }

  String _primaryLabel(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'Disconnect';
      case VpnStatus.connecting:
        return 'Connecting...';
      case VpnStatus.disconnecting:
        return 'Disconnecting...';
      case VpnStatus.disconnected:
        return 'Connect';
    }
  }

  IconData _primaryIcon(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return Icons.stop_circle_outlined;
      case VpnStatus.connecting:
        return Icons.hourglass_top;
      case VpnStatus.disconnecting:
        return Icons.hourglass_bottom;
      case VpnStatus.disconnected:
        return Icons.play_circle_outlined;
    }
  }
}

// VPN Status Card with clear status transitions
class _VpnStatusCard extends StatelessWidget {
  const _VpnStatusCard({required this.vpnState, required this.status});

  final VpnUiState vpnState;
  final AsyncValue<VpnStatus> status;

  @override
  Widget build(BuildContext context) {
    return status.when(
      data: (data) => _StatusDisplay(status: data, vpnState: vpnState),
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
  const _StatusDisplay({required this.status, required this.vpnState});

  final VpnStatus status;
  final VpnUiState vpnState;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(status);
    final color = _statusColor(status);
    final icon = _statusIcon(status);
    final isActive = status == VpnStatus.connected;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    AppTheme.success.withOpacity(0.1),
                    AppTheme.success.withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Status indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.4), width: 3),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 16),
              // Status label
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
              const SizedBox(height: 8),
              Text(
                _statusDetail(status),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
              ),
              const SizedBox(height: 12),
              // Config status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: vpnState.lastConfig != null
                      ? AppTheme.success.withOpacity(0.1)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      vpnState.lastConfig != null ? Icons.check_circle : Icons.info_outline,
                      size: 14,
                      color: vpnState.lastConfig != null ? AppTheme.success : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      vpnState.lastConfig != null ? 'Config provisioned' : 'Not provisioned yet',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              // Data rates when connected
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
            ],
                  ),
                ),
              ),
              if (vpnState.lastSessionId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Session: ${vpnState.lastSessionId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
                      ),
                ),
              ],
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
        return 'Tunnel active. Use Disconnect to end the session.';
      case VpnStatus.connecting:
        return 'Provisioning your config. Keep the app open.';
      case VpnStatus.disconnecting:
        return 'Ending the session and releasing your slot.';
      case VpnStatus.disconnected:
        return 'Tap Connect to provision a WireGuard session.';
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
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
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
                      color: AppTheme.info.withOpacity(0.1),
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
                  _TipItem(text: 'You see repeated provisioning errors.', isWarning: true),
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
