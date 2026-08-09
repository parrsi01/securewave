part of '../app.dart';

class _ServersScreen extends ConsumerWidget {
  const _ServersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpn = ref.watch(vpnStateProvider);

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

        final wireGuardItems = items
            .where((server) => server.supportsProtocol('wireguard'))
            .toList(growable: false);

        return ListView(
          children: [
            _PlainPanel(
              child: _ServerTile(
                title: 'Auto-select',
                subtitle: wireGuardItems.isEmpty
                    ? 'No WireGuard regions are currently listed.'
                    : 'Choose the best WireGuard region at connect time.',
                selected: vpn.selectedServerId == null,
                icon: Icons.auto_awesome_rounded,
                enabled: wireGuardItems.isNotEmpty,
                onTap: wireGuardItems.isEmpty
                    ? null
                    : () =>
                        ref.read(vpnStateProvider.notifier).selectServer(null),
              ),
            ),
            const SizedBox(height: 10),
            for (final server in wireGuardItems) ...[
              _PlainPanel(
                child: _ServerTile(
                  title: server.name,
                  subtitle: _serverSubtitle(server),
                  selected: vpn.selectedServerId == server.id,
                  icon: Icons.public_rounded,
                  enabled: server.supportsProtocol('wireguard'),
                  onTap: server.supportsProtocol('wireguard')
                      ? () => ref
                          .read(vpnStateProvider.notifier)
                          .selectServer(server.id)
                      : null,
                ),
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
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _showWireGuardErrorSequence(context),
            icon: const Icon(Icons.bug_report_outlined),
            label: const Text('Run WireGuard message test'),
          ),
        ],
      ],
    );
  }
}

void _showWireGuardErrorSequence(BuildContext context) {
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
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.78,
            child: const WireGuardErrorSequence(),
          ),
        ),
      );
    },
  );
}

/// Debug-only frontend exercise for the WireGuard error catalog.
class WireGuardErrorSequence extends StatefulWidget {
  const WireGuardErrorSequence({
    super.key,
    this.interval = const Duration(milliseconds: 900),
  });

  final Duration interval;

  @override
  State<WireGuardErrorSequence> createState() => _WireGuardErrorSequenceState();
}

class _WireGuardErrorSequenceState extends State<WireGuardErrorSequence> {
  Timer? _timer;
  final _scrollController = ScrollController();
  var _visibleCount = 1;

  @override
  void initState() {
    super.initState();
    if (wireGuardFrontendErrorCatalog.length > 1) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted) return;
        if (_visibleCount >= wireGuardFrontendErrorCatalog.length) {
          _timer?.cancel();
          return;
        }
        setState(() => _visibleCount += 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = wireGuardFrontendErrorCatalog.length;
    final complete = _visibleCount >= total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bug_report_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'WireGuard frontend message test',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('$_visibleCount/$total'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          complete
              ? 'Complete. No VPN operation was invoked.'
              : 'Simulated messages are appearing in order. No VPN operation is invoked.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: _visibleCount / total),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            key: const ValueKey<String>('wireguard-error-sequence'),
            controller: _scrollController,
            itemCount: _visibleCount,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = wireGuardFrontendErrorCatalog[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: FreshTheme.redSoft,
                  border: Border.all(color: const Color(0xFF6A2B31)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${index + 1}. ${item.id} · ${item.code}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(item.message),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
