part of '../app.dart';

class _ServersScreen extends ConsumerWidget {
  const _ServersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpn = ref.watch(vpnStateProvider);
    final service = ref.watch(vpnServiceProvider);
    final backendAvailability = ref.watch(protocolAvailabilityProvider);
    final availability = _protocolAvailability(
      protocol: vpn.protocol,
      service: service,
      backendAvailability: backendAvailability,
      servers: servers,
      selectedServerId: vpn.selectedServerId,
    );

    return servers.when(
      loading: () => const _CenteredState(
        icon: Icons.public_rounded,
        title: 'Loading regions',
        body: 'SecureWave is requesting the server catalog.',
      ),
      error: (error, _) => _CenteredState(
        icon: Icons.cloud_off_rounded,
        title: 'Regions unavailable',
        body: ApiError.messageFrom(
          error,
          fallback: 'The server list could not be loaded.',
        ),
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(serversProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _CenteredState(
            icon: Icons.public_off_rounded,
            title: 'No regions available',
            body: 'Auto-select will stay active until the catalog returns.',
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(serversProvider),
          );
        }

        final evidencedItems = items
            .where(
              (server) => server.hasProtocolEvidenceFor(
                vpnProtocolStorageValue(vpn.protocol),
              ),
            )
            .toList(growable: false);

        return ListView(
          children: [
            if (!availability.canConnect) ...[
              _InlineMessage(
                icon: Icons.info_outline_rounded,
                message: availability.message,
                tone: _Tone.warning,
                actionLabel: 'Refresh',
                onAction: () => ref.invalidate(serversProvider),
              ),
              const SizedBox(height: 10),
            ],
            _PlainPanel(
              child: _ServerTile(
                title: 'Auto-select',
                subtitle: evidencedItems.isEmpty
                    ? 'Waiting for usable backend protocol evidence.'
                    : 'Choose the best region at connect time.',
                selected: vpn.selectedServerId == null,
                icon: Icons.auto_awesome_rounded,
                enabled: evidencedItems.isNotEmpty,
                onTap: evidencedItems.isEmpty
                    ? null
                    : () =>
                        ref.read(vpnStateProvider.notifier).selectServer(null),
              ),
            ),
            const SizedBox(height: 10),
            for (final server in items) ...[
              Builder(
                builder: (context) {
                  final supported = server.hasProtocolEvidenceFor(
                    vpnProtocolStorageValue(vpn.protocol),
                  );
                  return _PlainPanel(
                    child: _ServerTile(
                      title: server.name,
                      subtitle: supported
                          ? _serverSubtitle(server)
                          : '${vpnProtocolLabel(vpn.protocol)} is not listed by the backend for this region.',
                      selected: vpn.selectedServerId == server.id,
                      icon: Icons.public_rounded,
                      enabled: supported,
                      onTap: supported
                          ? () => ref
                              .read(vpnStateProvider.notifier)
                              .selectServer(server.id)
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _AccountScreen extends ConsumerWidget {
  const _AccountScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Account'),
              const SizedBox(height: 12),
              user.when(
                data: (value) => Column(
                  children: [
                    _InfoRow(
                      'Email',
                      value.email.isEmpty ? 'Signed in' : value.email,
                    ),
                    _InfoRow('Status', value.isActive ? 'Active' : 'Inactive'),
                    _InfoRow(
                      'Verification',
                      value.emailVerified
                          ? 'Email verified'
                          : 'Email unverified',
                    ),
                    _InfoRow('Plan', value.subscriptionStatus),
                  ],
                ),
                loading: () => const _LoadingLine('Loading account'),
                error: (_, __) => _InlineMessage(
                  icon: Icons.warning_amber_rounded,
                  message: 'Account details could not be loaded.',
                  tone: _Tone.warning,
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(currentUserProvider),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Usage'),
              const SizedBox(height: 12),
              plan.when(
                data: (value) => _UsageSummary(plan: value),
                loading: () => const _LoadingLine('Loading usage'),
                error: (_, __) => _InlineMessage(
                  icon: Icons.warning_amber_rounded,
                  message: 'Usage could not be loaded.',
                  tone: _Tone.warning,
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(userPlanProvider),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsScreen extends ConsumerWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final device = ref.watch(deviceInfoProvider);
    final vpn = ref.watch(vpnStateProvider);
    final service = ref.watch(vpnServiceProvider);
    final plan = ref.watch(userPlanProvider);

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Runtime'),
              const SizedBox(height: 12),
              _InfoRow('Device', device),
              _InfoRow('API', config.apiBaseUrl),
              _InfoRow('Mock API', config.useMockApi ? 'On' : 'Off'),
              _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
              _InfoRow(
                'VPN bridge',
                service.isNativeAvailable ? 'Available' : 'Unavailable',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Usage'),
              const SizedBox(height: 12),
              plan.when(
                data: (value) => _UsageSummary(plan: value),
                loading: () => const _LoadingLine('Loading usage'),
                error: (_, __) => _InlineMessage(
                  icon: Icons.warning_amber_rounded,
                  message: 'Usage could not be loaded.',
                  tone: _Tone.warning,
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(userPlanProvider),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Account actions'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showDiagnostics(context),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Open diagnostics'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(externalLinksProvider).openUrl(config.portalUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open account portal'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('settings-help-action'),
                onPressed: () => ref
                    .read(externalLinksProvider)
                    .openUrl(AppConstants.supportUrlFallback),
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text('Help'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsView extends ConsumerWidget {
  const _DiagnosticsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final service = ref.watch(vpnServiceProvider);
    final serverList = ref.watch(serversProvider);

    return ListView(
      shrinkWrap: true,
      children: [
        _InfoRow('VPN state', _statusDescriptor(vpn).label),
        _InfoRow(
          'Native bridge',
          service.isNativeAvailable ? 'Available' : 'Unavailable',
        ),
        _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
        _InfoRow('Desired state', vpn.desiredOn ? 'On' : 'Off'),
        _InfoRow(
          'Profile fetch',
          vpn.lastProfileFetchOk == null
              ? 'Not run'
              : vpn.lastProfileFetchOk!
                  ? 'Last fetch passed'
                  : 'Last fetch failed',
        ),
        _InfoRow(
          'Tunnel start',
          vpn.lastTunnelStartOk == null
              ? 'Not run'
              : vpn.lastTunnelStartOk!
                  ? 'Last start passed'
                  : 'Last start failed',
        ),
        serverList.when(
          data: (items) => _InfoRow('Regions', '${items.length} loaded'),
          loading: () => const _InfoRow('Regions', 'Loading'),
          error: (_, __) => const _InfoRow('Regions', 'Load failed'),
        ),
        if (vpn.errorMessage != null)
          _InlineMessage(
            icon: Icons.error_outline_rounded,
            message: vpn.errorMessage!,
            tone: _Tone.error,
          ),
      ],
    );
  }
}
