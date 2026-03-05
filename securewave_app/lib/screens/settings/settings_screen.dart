import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_protocol_catalog.dart';
import '../../core/models/vpn_status.dart';
import '../../core/services/auth_session.dart';
import '../../core/services/device_identity.dart';
import '../../core/state/app_state.dart';
import '../../core/state/preferences_state.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/vpn_state.dart';
import '../../core/vpn/protocol_capabilities.dart';
import '../../debug/automation_keys.dart';
import '../../features/onboarding/feedback_sheet.dart';
import '../../services/api_client.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

String _formatDiagnosticsTimestamp(DateTime value) {
  final utc = value.toUtc();
  final h = utc.hour.toString().padLeft(2, '0');
  final m = utc.minute.toString().padLeft(2, '0');
  final s = utc.second.toString().padLeft(2, '0');
  return '$h:$m:$s UTC';
}

/// Settings screen — v2.
///
/// Clean grouped sections with card containers.
/// Toggle cards with icon badges. Protocol selector as pill cards.
/// Diagnostics as animated slide-in panel.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _diagExpanded = false;
  List<_DiagResult>? _diagResults;
  bool _reconnecting = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedProtocol =
        ref.watch(vpnStateProvider.select((s) => s.protocol));
    final caps = ref.watch(vpnCapabilitiesProvider);
    final catalog = ref.watch(vpnProtocolCatalogProvider);
    const diagnosticsEnabled = true;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          children: [
            // ── CONNECTION ───────────────────────────────────────────────
            _SectionLabel(label: 'Connection', isDark: isDark),
            _ToggleCard(
              icon: Icons.bolt_rounded,
              iconColor: AppColors.primary,
              title: 'Auto-connect',
              subtitle: 'Connect automatically when app starts',
              value:
                  ref.watch(preferencesProvider.select((p) => p.autoConnect)),
              onChanged: (v) =>
                  ref.read(preferencesProvider.notifier).setAutoConnect(v),
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.space2),
            _ToggleCard(
              icon: Icons.shield_rounded,
              iconColor: AppColors.error,
              title: 'Kill Switch',
              subtitle: 'Block all traffic if VPN drops',
              value: ref.watch(preferencesProvider.select((p) => p.killSwitch)),
              onChanged: (v) =>
                  ref.read(preferencesProvider.notifier).setKillSwitch(v),
              isDark: isDark,
            ),
            const SizedBox(height: AppSpacing.space2),
            _ToggleCard(
              icon: Icons.block_rounded,
              iconColor: AppColors.secondary,
              title: 'Ad & Malware Blocking',
              subtitle: 'Block ads and trackers at DNS level',
              value: ref
                  .watch(preferencesProvider.select((p) => p.adBlockEnabled)),
              onChanged: (v) => _handleAdBlockChange(context, v),
              isDark: isDark,
            ),

            const SizedBox(height: AppSpacing.space2),
            _ActionCard(
              icon: Icons.devices_rounded,
              iconColor: AppColors.primary,
              title: 'Manage Devices',
              subtitle: 'View and remove connected devices',
              isDark: isDark,
              onTap: () => context.push('/devices'),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── PROTOCOL ─────────────────────────────────────────────────
            _SectionLabel(label: 'Protocol', isDark: isDark),
            _ProtocolSelector(
              selected: selectedProtocol,
              caps: caps,
              catalog: catalog,
              isDark: isDark,
              onSelect: (p) =>
                  ref.read(vpnStateProvider.notifier).selectProtocol(p),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── DIAGNOSTICS ──────────────────────────────────────────────
            _SectionLabel(label: 'Diagnostics', isDark: isDark),
            _DiagnosticsPanel(
              isDark: isDark,
              enabled: diagnosticsEnabled,
              expanded: _diagExpanded,
              results: _diagResults,
              onToggle: (expanded) {
                setState(() => _diagExpanded = expanded);
                if (expanded && diagnosticsEnabled) {
                  unawaited(_runDiagnostics());
                }
              },
              onCopy: () => _copyDiagnostics(context),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── SUPPORT ──────────────────────────────────────────────────
            _SectionLabel(label: 'Support', isDark: isDark),
            _ActionCard(
              icon: Icons.feedback_outlined,
              iconColor: AppColors.primary,
              title: 'Send Feedback',
              subtitle: 'Report bugs or suggest features',
              isDark: isDark,
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => FeedbackSheet(
                  onSubmit: (_, __) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Thanks for your feedback!')),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── DANGER ZONE ──────────────────────────────────────────────
            _SectionLabel(
                label: 'Danger Zone', isDark: isDark, isDestructive: true),
            _DangerCard(
              isDark: isDark,
              onTap: () => _showPanicDialog(context),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── ABOUT ────────────────────────────────────────────────────
            _SectionLabel(label: 'About', isDark: isDark),
            _AboutCard(isDark: isDark),

            const SizedBox(height: AppSpacing.space8),
          ],
        ),
      ),
    );
  }

  void _handleAdBlockChange(BuildContext context, bool v) {
    final vpnStatus = ref.read(vpnStateProvider.select((s) => s.status));
    if (vpnStatus == VpnStatus.connected) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reconnect Required'),
          content:
              const Text('This change requires reconnecting. Reconnect now?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reconnect')),
          ],
        ),
      ).then((ok) {
        if (ok == true && mounted && !_reconnecting) {
          ref.read(preferencesProvider.notifier).setAdBlock(v);
          _reconnecting = true;
          unawaited(_reconnectAfterSettingChange());
        }
      });
    } else {
      ref.read(preferencesProvider.notifier).setAdBlock(v);
    }
  }

  Future<void> _reconnectAfterSettingChange() async {
    try {
      final notifier = ref.read(vpnStateProvider.notifier);
      await notifier.disconnect();
      if (!mounted) return;
      await notifier.connect();
    } finally {
      if (mounted) _reconnecting = false;
    }
  }

  void _showPanicDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Panic Mode'),
        content:
            const Text('This will disconnect VPN and sign you out. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(ref.read(vpnStateProvider.notifier).disconnect());
              ref.read(authSessionProvider).clearSession();
              context.go('/login');
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _copyDiagnostics(BuildContext context) {
    final text = _diagResults
            ?.map((r) =>
                '${r.loading ? "..." : (r.passed ? "PASS" : "FAIL")}: ${r.label}'
                '${r.detail == null ? "" : " — ${r.detail}"}'
                '${r.updatedAt == null ? "" : " @ ${_formatDiagnosticsTimestamp(r.updatedAt!)}"}')
            .join('\n') ??
        '';
    Clipboard.setData(ClipboardData(text: 'SecureWave Diagnostics\n$text'));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Diagnostics copied')));
  }

  Future<void> _runDiagnostics() async {
    const labels = <String>[
      '1) Health: GET /api/health',
      '2) Auth: token persisted and authorized calls',
      '3) Catalog: servers/regions visible',
      '4) Profile: /api/vpn/profile for selected server',
      '5) Tunnel: connect -> connected -> disconnect -> clean',
      '6) Metrics: traffic changes Mbps/MB counters',
    ];

    setState(() {
      _diagResults =
          labels.map((label) => _DiagResult(label, loading: true)).toList();
    });

    void setResult(int index, _DiagResult value) {
      if (!mounted || _diagResults == null || index >= _diagResults!.length) {
        return;
      }
      setState(() => _diagResults![index] = value.stamped());
    }

    final api = ref.read(apiClientProvider);
    final auth = ref.read(authSessionProvider);
    final vpnNotifier = ref.read(vpnStateProvider.notifier);
    final selectedProtocol = ref.read(vpnStateProvider).effectiveProtocol ??
        ref.read(vpnStateProvider).protocol;

    final healthOk = await (() async {
      try {
        final payload = await api.fetchHealth();
        setResult(
          0,
          _DiagResult(
            labels[0],
            passed: true,
            detail: 'status=${payload['status'] ?? 'ok'}',
          ),
        );
        return true;
      } catch (error) {
        setResult(
          0,
          _DiagResult(labels[0], passed: false, detail: error.toString()),
        );
        return false;
      }
    })();

    final authOk = await (() async {
      try {
        final token = auth.accessToken;
        final authed =
            auth.isAuthenticated && token != null && token.isNotEmpty;
        if (!authed) {
          setResult(
            1,
            _DiagResult(labels[1],
                passed: false, detail: 'Sign in required before diagnostics.'),
          );
          return false;
        }
        final profile = await api.fetchProfile();
        final email = profile['email']?.toString() ?? '';
        setResult(
          1,
          _DiagResult(
            labels[1],
            passed: true,
            detail: email.isEmpty ? 'authorized' : 'authorized as $email',
          ),
        );
        return true;
      } catch (error) {
        setResult(
          1,
          _DiagResult(labels[1], passed: false, detail: error.toString()),
        );
        return false;
      }
    })();

    List<dynamic> servers = const <dynamic>[];
    final catalogOk = await (() async {
      try {
        servers = await api.fetchServers(forceRefresh: true);
        final visible = servers.isNotEmpty;
        setResult(
          2,
          _DiagResult(
            labels[2],
            passed: visible,
            detail: visible
                ? 'count=${servers.length}'
                : 'Catalog returned no servers.',
          ),
        );
        return visible;
      } catch (error) {
        setResult(
          2,
          _DiagResult(labels[2], passed: false, detail: error.toString()),
        );
        return false;
      }
    })();

    final profileOk = await (() async {
      if (!healthOk || !authOk) {
        setResult(
          3,
          _DiagResult(labels[3],
              passed: false, detail: 'Skipped due to prior failures.'),
        );
        return false;
      }
      try {
        final identity = await DeviceIdentity.load();
        final profile = await api.fetchVpnProfile(
          deviceName: identity.name,
          deviceType: identity.type,
          protocol: selectedProtocol == VpnProtocol.auto
              ? VpnProtocol.wireGuard
              : selectedProtocol,
          serverId: ref.read(vpnStateProvider).selectedServerId,
        );
        setResult(
          3,
          _DiagResult(
            labels[3],
            passed: true,
            detail: 'protocol=${profile.protocol} server=${profile.serverId}',
          ),
        );
        return true;
      } catch (error) {
        setResult(
          3,
          _DiagResult(labels[3], passed: false, detail: error.toString()),
        );
        return false;
      }
    })();

    final tunnelOk = await (() async {
      if (!profileOk) {
        setResult(
          4,
          _DiagResult(labels[4],
              passed: false, detail: 'Skipped due to profile failure.'),
        );
        return false;
      }
      try {
        await vpnNotifier.disconnect();
        await _waitForStatus(VpnStatus.disconnected,
            timeout: const Duration(seconds: 25));
        await vpnNotifier.connect();
        await _waitForStatus(VpnStatus.connected,
            timeout: const Duration(seconds: 40));
        await vpnNotifier.disconnect();
        await _waitForStatus(VpnStatus.disconnected,
            timeout: const Duration(seconds: 25));
        setResult(
            4,
            _DiagResult(labels[4],
                passed: true, detail: 'Tunnel cycle succeeded.'));
        return true;
      } catch (error) {
        setResult(
            4, _DiagResult(labels[4], passed: false, detail: error.toString()));
        return false;
      }
    })();

    await (() async {
      if (!tunnelOk || !catalogOk) {
        setResult(
          5,
          _DiagResult(labels[5],
              passed: false, detail: 'Skipped due to prior failures.'),
        );
        return;
      }
      try {
        final before = ref.read(vpnStateProvider).sessionTransferredBytes;
        await vpnNotifier.connect();
        await _waitForStatus(VpnStatus.connected,
            timeout: const Duration(seconds: 40));
        await http
            .get(Uri.parse('https://example.com'))
            .timeout(const Duration(seconds: 10));
        await Future<void>.delayed(const Duration(seconds: 3));
        final state = ref.read(vpnStateProvider);
        final after = state.sessionTransferredBytes;
        final moved =
            after > before || state.dataRateDown > 0 || state.dataRateUp > 0;
        setResult(
          5,
          _DiagResult(
            labels[5],
            passed: moved,
            detail:
                'session_bytes=$before->$after down=${state.dataRateDown.toStringAsFixed(2)} up=${state.dataRateUp.toStringAsFixed(2)}',
          ),
        );
      } catch (error) {
        setResult(
            5, _DiagResult(labels[5], passed: false, detail: error.toString()));
      } finally {
        unawaited(vpnNotifier.disconnect());
      }
    })();
  }

  Future<void> _waitForStatus(
    VpnStatus expected, {
    required Duration timeout,
  }) async {
    final endAt = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endAt)) {
      if (!mounted) {
        throw StateError(
            'Settings screen disposed while waiting for VPN status.');
      }
      final status = ref.read(vpnStateProvider).status;
      if (status == expected) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final last = ref.read(vpnStateProvider).status;
    throw TimeoutException(
      'Timed out waiting for $expected (last status: $last).',
      timeout,
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.isDark,
    this.isDestructive = false,
  });

  final String label;
  final bool isDark;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.space2,
        bottom: AppSpacing.space2,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: AppSpacing.space2),
            decoration: BoxDecoration(
              color: isDestructive ? AppColors.error : AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isDestructive ? AppColors.error : null,
                  letterSpacing: 0.8,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Toggle card ────────────────────────────────────────────────────────────

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
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
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: Icon(icon, size: AppSpacing.iconS, color: iconColor),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Switch(value: value, onChanged: onChanged),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── Protocol selector ──────────────────────────────────────────────────────

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({
    required this.selected,
    required this.caps,
    required this.catalog,
    required this.isDark,
    required this.onSelect,
  });

  final VpnProtocol selected;
  final AsyncValue<VpnCapabilities> caps;
  final AsyncValue<VpnProtocolCatalog> catalog;
  final bool isDark;
  final void Function(VpnProtocol) onSelect;

  String? _protocolSubtitle(BuildContext context, VpnProtocol protocol) {
    final platform = Theme.of(context).platform;
    if (protocol == VpnProtocol.auto) {
      return 'Automatically chooses the first live protocol runtime.';
    }
    return switch (platform) {
      TargetPlatform.linux => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Native WireGuard runtime (requires admin prompt).',
          VpnProtocol.openVpn => 'Requires local OpenVPN client + elevation.',
          VpnProtocol.ikev2 =>
            'Requires OS helper (NetworkManager/strongSwan).',
          VpnProtocol.auto => null,
        },
      TargetPlatform.windows => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Uses installed WireGuard for Windows runtime.',
          VpnProtocol.openVpn =>
            'Uses OpenVPN for Windows (UAC prompt may appear).',
          VpnProtocol.ikev2 => 'Uses built-in Windows VPN (RAS/VPN API path).',
          VpnProtocol.auto => null,
        },
      TargetPlatform.macOS => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Shown only when this build includes signed Network Extension support.',
          VpnProtocol.openVpn =>
            'Requires signed Packet Tunnel / Network Extension support.',
          VpnProtocol.ikev2 =>
            'Requires NEVPNManager entitlements and signing.',
          VpnProtocol.auto => null,
        },
      _ => switch (protocol) {
          VpnProtocol.wireGuard =>
            'Uses the native VPN runtime on this device.',
          VpnProtocol.openVpn =>
            'Uses the native OpenVPN runtime on this device.',
          VpnProtocol.ikev2 => 'Uses OS-provided IKEv2/IPsec support.',
          VpnProtocol.auto => null,
        },
    };
  }

  String? _catalogUnavailableReason(
    VpnProtocol protocol,
    VpnProtocolCatalogEntry? entry,
  ) {
    final reason = entry?.reason;
    if (reason == null || reason.trim().isEmpty) return null;
    return switch (reason) {
      'disabled_server_side' =>
        '${vpnProtocolLabel(protocol)} is temporarily disabled on the backend.',
      'restricted_by_plan' => 'Not included in your current subscription plan.',
      'not_supported_on_platform' => 'Not supported on this platform.',
      'no_active_server_support' =>
        'No active server currently supports ${vpnProtocolLabel(protocol)}.',
      'protocol_temporarily_unavailable' =>
        '${vpnProtocolLabel(protocol)} is temporarily unavailable.',
      _ => reason,
    };
  }

  String? _unavailableReason({
    required VpnProtocol protocol,
    required bool capabilitiesReady,
    required bool catalogReady,
    required VpnProtocolAvailability? availability,
    required VpnProtocolCatalogEntry? catalogEntry,
  }) {
    if (!capabilitiesReady) {
      return 'Checking local runtime availability...';
    }
    if (!catalogReady) {
      return 'Checking backend availability...';
    }
    final catalogReason = _catalogUnavailableReason(protocol, catalogEntry);
    if (catalogReason != null) return catalogReason;
    if (availability?.unavailableReason != null &&
        availability!.unavailableReason!.trim().isNotEmpty) {
      return availability.unavailableReason;
    }
    return '${vpnProtocolLabel(protocol)} is currently unavailable.';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 480 ? 2 : 1;
        final capsData = caps.valueOrNull;
        final catalogData = catalog.valueOrNull;
        final capabilitiesReady = capsData != null;
        final catalogReady = catalogData != null;
        final backendEnabled = catalogData?.enabledProtocols() ??
            <VpnProtocol>{VpnProtocol.wireGuard};
        final availabilityByProtocol = capsData == null
            ? <VpnProtocol, VpnProtocolAvailability>{}
            : <VpnProtocol, VpnProtocolAvailability>{
                for (final item in ProtocolCapabilityMatrix.evaluate(
                  nativeCapabilities: capsData,
                  backendEnabledProtocols: backendEnabled,
                ))
                  item.protocol: item,
              };
        final catalogByProtocol = <VpnProtocol, VpnProtocolCatalogEntry>{
          for (final entry
              in catalogData?.protocols ?? const <VpnProtocolCatalogEntry>[])
            entry.protocol: entry,
        };
        final hasAvailableProtocol =
            availabilityByProtocol.values.any((item) => item.available);
        final selectable = <VpnProtocol>[
          VpnProtocol.auto,
          ...ProtocolCapabilityMatrix.orderedProtocols(),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (capabilitiesReady && !hasAvailableProtocol)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.space2),
                child: Text(
                  'No live protocol runtime is currently available on this device.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: selectable.map((p) {
                final availability = availabilityByProtocol[p];
                final isAuto = p == VpnProtocol.auto;
                final isSelectable = isAuto
                    ? (!capabilitiesReady || hasAvailableProtocol)
                    : (availability?.available ?? false);
                final isSelected = selected == p;
                final unavailableReason = isAuto
                    ? (isSelectable
                        ? null
                        : 'No protocol is currently connectable.')
                    : (isSelectable
                        ? null
                        : _unavailableReason(
                            protocol: p,
                            capabilitiesReady: capabilitiesReady,
                            catalogReady: catalogReady,
                            availability: availability,
                            catalogEntry: catalogByProtocol[p],
                          ));
                final subtitle = _protocolSubtitle(context, p);
                final semanticHint = isSelectable
                    ? (subtitle == null
                        ? 'Double tap to select ${vpnProtocolLabel(p)}.'
                        : '$subtitle Double tap to select.')
                    : (unavailableReason == null
                        ? '${vpnProtocolLabel(p)} is unavailable.'
                        : '${vpnProtocolLabel(p)} unavailable: $unavailableReason');
                final isDisabled = !isSelectable;

                return SizedBox(
                  width: cols == 2
                      ? (constraints.maxWidth - AppSpacing.space2) / 2
                      : double.infinity,
                  child: Semantics(
                    button: true,
                    enabled: isSelectable,
                    selected: isSelected,
                    label: 'VPN protocol ${vpnProtocolLabel(p)}',
                    hint: semanticHint,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusXL),
                        onTap: isSelectable ? () => onSelect(p) : null,
                        child: AnimatedContainer(
                          duration: AppAnimations.durationFast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space4,
                            vertical: AppSpacing.space3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDark
                                    ? AppColors.primaryBright
                                        .withValues(alpha: 0.12)
                                    : AppColors.primaryLight)
                                : (isDisabled
                                    ? (isDark
                                        ? AppColors.darkSurfaceMuted
                                            .withValues(alpha: 0.75)
                                        : AppColors.surfaceMuted)
                                    : (isDark
                                        ? AppColors.darkSurface
                                        : AppColors.surface)),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusXL),
                            border: Border.all(
                              color: isSelected
                                  ? (isDark
                                      ? AppColors.primaryBright
                                      : AppColors.primary)
                                  : (isDark
                                      ? AppColors.darkBorder
                                      : AppColors.border),
                              width: isSelected ? 1.5 : 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              AnimatedContainer(
                                duration: AppAnimations.durationFast,
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? (isDark
                                          ? AppColors.primaryBright
                                          : AppColors.primary)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? (isDark
                                            ? AppColors.primaryBright
                                            : AppColors.primary)
                                        : (isDisabled
                                            ? (isDark
                                                ? AppColors.darkInkSoft
                                                : AppColors.inkMuted)
                                            : (isDark
                                                ? AppColors.darkInkSoft
                                                : AppColors.inkSoft)),
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                        size: 10, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: AppSpacing.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      vpnProtocolLabel(p),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: isDisabled
                                                ? (isDark
                                                    ? AppColors.darkInkSoft
                                                    : AppColors.inkMuted)
                                                : null,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                    ),
                                    if (subtitle != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: isDark
                                                  ? AppColors.darkInkSoft
                                                  : AppColors.inkMuted,
                                              height: 1.2,
                                            ),
                                      ),
                                    ],
                                    if (unavailableReason != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        unavailableReason,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.error,
                                              height: 1.2,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

// ── Diagnostics panel ──────────────────────────────────────────────────────

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({
    required this.isDark,
    required this.enabled,
    required this.expanded,
    required this.results,
    required this.onToggle,
    required this.onCopy,
  });

  final bool isDark;
  final bool enabled;
  final bool expanded;
  final List<_DiagResult>? results;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey<String>(AutomationKeys.diagnosticsTile),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusM),
            ),
            child: const Icon(Icons.health_and_safety_outlined,
                size: AppSpacing.iconS, color: AppColors.primary),
          ),
          title: Text(
            'Run Diagnostics',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          initiallyExpanded: expanded,
          onExpansionChanged: enabled ? onToggle : null,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          ),
          children: [
            if (!enabled)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
                leading: const Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppColors.warning,
                ),
                title: Text(
                  'Diagnostics are temporarily unavailable.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            if (results != null)
              ...results!.asMap().entries.map((entry) {
                final index = entry.key;
                final r = entry.value;
                final status =
                    r.loading ? 'loading' : (r.passed ? 'pass' : 'fail');
                return ListTile(
                  key: ValueKey<String>(
                    AutomationKeys.diagnosticsResult(index, status),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
                  leading: r.loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          r.passed
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: r.passed ? AppColors.success : AppColors.error,
                          size: 20),
                  title: Text(r.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                  subtitle: r.detail != null
                      ? Text(
                          r.updatedAt == null
                              ? r.detail!
                              : '${r.detail!} · ${_formatDiagnosticsTimestamp(r.updatedAt!)}',
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
                );
              }),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space3),
              child: TextButton.icon(
                onPressed: results == null ? null : onCopy,
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copy Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action card ────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: Icon(icon, size: AppSpacing.iconS, color: iconColor),
        ),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Icon(Icons.chevron_right_rounded,
            size: AppSpacing.iconS,
            color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── Danger card ────────────────────────────────────────────────────────────

class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.isDark, required this.onTap});
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.25),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              size: AppSpacing.iconS, color: AppColors.error),
        ),
        title: Text(
          'Panic Mode',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: const Text('Emergency disconnect and clear all data'),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        ),
      ),
    );
  }
}

// ── About card ─────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            title: const Text('Version'),
            subtitle: const Text('SecureWave v4.0.0'),
            leading: Icon(Icons.info_outline_rounded,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? AppColors.darkBorder : AppColors.border),
          ListTile(
            title: const Text('Privacy Policy'),
            leading: Icon(Icons.privacy_tip_outlined,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            trailing: Icon(Icons.open_in_new_rounded,
                size: 14,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            onTap: () {},
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? AppColors.darkBorder : AppColors.border),
          ListTile(
            title: const Text('Terms of Service'),
            leading: Icon(Icons.gavel_rounded,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            trailing: Icon(Icons.open_in_new_rounded,
                size: 14,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ── Data classes ───────────────────────────────────────────────────────────

class _DiagResult {
  _DiagResult(this.label,
      {this.passed = false, this.loading = false, this.detail, this.updatedAt});
  final String label;
  final bool passed;
  final bool loading;
  final String? detail;
  final DateTime? updatedAt;

  _DiagResult stamped() {
    return _DiagResult(
      label,
      passed: passed,
      loading: loading,
      detail: detail,
      updatedAt: DateTime.now(),
    );
  }
}
