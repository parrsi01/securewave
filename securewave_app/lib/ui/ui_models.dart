part of '../app.dart';

class _ProtocolAvailability {
  const _ProtocolAvailability({
    required this.protocol,
    required this.runtimeAvailable,
    required this.backendEvidenceAvailable,
    required this.backendEvidencePending,
    this.reason,
  });

  final VpnProtocol protocol;
  final bool runtimeAvailable;
  final bool backendEvidenceAvailable;
  final bool backendEvidencePending;
  final String? reason;

  bool get canConnect => runtimeAvailable && backendEvidenceAvailable;

  String get message {
    if (reason != null && reason!.isNotEmpty) return reason!;
    if (backendEvidencePending) {
      return 'Checking server support for ${vpnProtocolLabel(protocol)}.';
    }
    return '${vpnProtocolLabel(protocol)} is not available for the selected server catalog.';
  }
}

_ProtocolAvailability _protocolAvailability({
  required VpnProtocol protocol,
  required VpnService service,
  required AsyncValue<Map<VpnProtocol, ProtocolAvailability>>
      backendAvailability,
  required AsyncValue<List<ServerRegion>> servers,
  required String? selectedServerId,
}) {
  final runtimeAvailable = service.canConnectProtocol(protocol);
  if (!runtimeAvailable) {
    return _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: false,
      backendEvidenceAvailable: false,
      backendEvidencePending: false,
      reason: service.protocolUnavailableReason(protocol),
    );
  }

  final backendRuntime = backendAvailability.valueOrNull?[protocol];
  if (backendAvailability.isLoading) {
    return _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: true,
      backendEvidenceAvailable: false,
      backendEvidencePending: true,
    );
  }
  if (backendAvailability.hasError) {
    return _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: true,
      backendEvidenceAvailable: false,
      backendEvidencePending: false,
      reason: 'Backend protocol runtime evidence is unavailable.',
    );
  }
  if (backendRuntime?.enabled != true) {
    return _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: true,
      backendEvidenceAvailable: false,
      backendEvidencePending: false,
      reason: backendRuntime?.reason ??
          'The backend has no usable ${vpnProtocolLabel(protocol)} runtime evidence.',
    );
  }

  return servers.when(
    loading: () => _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: true,
      backendEvidenceAvailable: false,
      backendEvidencePending: true,
    ),
    error: (error, _) => _ProtocolAvailability(
      protocol: protocol,
      runtimeAvailable: true,
      backendEvidenceAvailable: false,
      backendEvidencePending: false,
      reason: ApiError.messageFrom(
        error,
        fallback: 'Server support could not be verified. Retry the catalog.',
      ),
    ),
    data: (items) {
      if (selectedServerId != null) {
        final selected =
            items.where((server) => server.id == selectedServerId).firstOrNull;
        if (selected == null) {
          return _ProtocolAvailability(
            protocol: protocol,
            runtimeAvailable: true,
            backendEvidenceAvailable: false,
            backendEvidencePending: false,
            reason: 'The selected server is no longer in the backend catalog.',
          );
        }
        final supported = selected.hasProtocolEvidenceFor(
          vpnProtocolStorageValue(protocol),
        );
        return _ProtocolAvailability(
          protocol: protocol,
          runtimeAvailable: true,
          backendEvidenceAvailable: supported,
          backendEvidencePending: false,
          reason: supported
              ? null
              : 'The backend catalog does not list ${vpnProtocolLabel(protocol)} for this server.',
        );
      }

      final supported = items.any(
        (server) =>
            server.hasProtocolEvidenceFor(vpnProtocolStorageValue(protocol)),
      );
      return _ProtocolAvailability(
        protocol: protocol,
        runtimeAvailable: true,
        backendEvidenceAvailable: supported,
        backendEvidencePending: false,
        reason: supported
            ? null
            : 'The backend catalog has no usable ${vpnProtocolLabel(protocol)} evidence.',
      );
    },
  );
}

class _ShellTab {
  const _ShellTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StatusDescriptor {
  const _StatusDescriptor({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.tone,
  });

  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final _Tone tone;
}

enum _Tone { neutral, info, success, warning, error }

({Color background, Color border, Color foreground}) _toneColors(_Tone tone) {
  return switch (tone) {
    _Tone.success => (
        background: FreshTheme.primarySoft,
        border: const Color(0xFF2F61A6),
        foreground: FreshTheme.primary,
      ),
    _Tone.warning => (
        background: FreshTheme.amberSoft,
        border: const Color(0xFF6B4E1C),
        foreground: FreshTheme.amber,
      ),
    _Tone.error => (
        background: FreshTheme.redSoft,
        border: const Color(0xFF6A2B31),
        foreground: FreshTheme.red,
      ),
    _Tone.info => (
        background: FreshTheme.secondarySoft,
        border: const Color(0xFF52627A),
        foreground: FreshTheme.secondary,
      ),
    _Tone.neutral => (
        background: FreshTheme.surfaceMuted,
        border: FreshTheme.line,
        foreground: FreshTheme.graphiteMuted,
      ),
  };
}

_StatusDescriptor _statusDescriptor(VpnState vpn) {
  final backendUnreachable = vpn.status == VpnStatus.error &&
      vpn.errorKind == VpnErrorKind.backendUnreachable;
  return switch (vpn.status) {
    VpnStatus.connected => const _StatusDescriptor(
        label: 'VPN connected',
        shortLabel: 'On',
        icon: Icons.verified_rounded,
        color: FreshTheme.primary,
        background: FreshTheme.primarySoft,
        border: Color(0xFF2F61A6),
        tone: _Tone.success,
      ),
    VpnStatus.connecting => const _StatusDescriptor(
        label: 'Connecting',
        shortLabel: 'Wait',
        icon: Icons.sync_rounded,
        color: FreshTheme.amber,
        background: FreshTheme.amberSoft,
        border: Color(0xFF6B4E1C),
        tone: _Tone.warning,
      ),
    VpnStatus.disconnecting => const _StatusDescriptor(
        label: 'Disconnecting',
        shortLabel: 'Wait',
        icon: Icons.sync_disabled_rounded,
        color: FreshTheme.amber,
        background: FreshTheme.amberSoft,
        border: Color(0xFF6B4E1C),
        tone: _Tone.warning,
      ),
    VpnStatus.error => _StatusDescriptor(
        label:
            backendUnreachable ? 'Backend unreachable' : 'VPN needs attention',
        shortLabel: 'Error',
        icon: Icons.warning_amber_rounded,
        color: FreshTheme.red,
        background: FreshTheme.redSoft,
        border: const Color(0xFF6A2B31),
        tone: _Tone.error,
      ),
    VpnStatus.disconnected => const _StatusDescriptor(
        label: 'VPN disconnected',
        shortLabel: 'Off',
        icon: Icons.power_settings_new_rounded,
        color: FreshTheme.graphiteMuted,
        background: FreshTheme.surfaceMuted,
        border: FreshTheme.line,
        tone: _Tone.neutral,
      ),
  };
}

String _serverLabel(String? selectedServerId, List<ServerRegion> servers) {
  if (selectedServerId == null) return 'Auto-select';
  for (final server in servers) {
    if (server.id == selectedServerId) return server.name;
  }
  return selectedServerId;
}

String _serverSubtitle(ServerRegion server) {
  final parts = <String>[];
  if (server.city != null && server.city!.isNotEmpty) parts.add(server.city!);
  if (server.country != null && server.country!.isNotEmpty) {
    parts.add(server.country!);
  }
  if (server.latencyMs != null) parts.add('${server.latencyMs} ms');
  if (server.loadPercent != null) {
    parts.add('${server.loadPercent!.round()}% load');
  }
  final protocols = server.supportedProtocols
      .map(
        (item) => switch (item) {
          'wireguard' => 'WG',
          'openvpn' => 'OVPN',
          'ikev2' => 'IKEv2',
          _ => item,
        },
      )
      .join('/');
  if (protocols.isNotEmpty) parts.add(protocols);
  final health = server.regionHealthStatus ?? server.healthStatus;
  if (health != null && health.isNotEmpty && health != 'up') {
    parts.add(health);
  }
  if (server.premiumOnly) parts.add('Premium');
  return parts.isEmpty ? 'Region endpoint' : parts.join(' · ');
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authServiceProvider).logout();
  } catch (_) {
    // AuthService clears local credentials in its finally block. Keep the
    // explicit logout usable even when the control plane is unavailable.
    AppLogger.warning(
      'Logout completed locally while the backend was unavailable.',
    );
  }
  ref.read(vpnStateProvider.notifier).selectServer(null);
  ref.invalidate(currentUserProvider);
  ref.invalidate(userPlanProvider);
  ref.invalidate(serversProvider);
}

void _showDiagnostics(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.76,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnostics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Expanded(child: _DiagnosticsView()),
              ],
            ),
          ),
        ),
      );
    },
  );
}
