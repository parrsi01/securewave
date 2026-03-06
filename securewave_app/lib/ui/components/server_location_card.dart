import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../widgets/glass_panel.dart';

class ServerPill extends ConsumerWidget {
  const ServerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId =
        ref.watch(vpnStateProvider.select((state) => state.selectedServerId));
    final servers = ref.watch(serversProvider);
    ServerRegion? selected;
    final items = servers.valueOrNull;
    if (items != null) {
      for (final server in items) {
        if (server.id == selectedId) {
          selected = server;
          break;
        }
      }
    }
    return GlassPanel(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.go('/locations'),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Server location',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _locationLabel(selected),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _supportingText(selected),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  static String _locationLabel(ServerRegion? server) {
    if (server == null) return 'Automatic selection';
    final city = (server.city ?? '').trim();
    final country = (server.country ?? '').trim();
    if (city.isNotEmpty && country.isNotEmpty) {
      return '$city, $country';
    }
    return server.name;
  }

  static String _supportingText(ServerRegion? server) {
    if (server == null) {
      return 'Choose a preferred region or let SecureWave route automatically.';
    }
    final latency =
        server.latencyMs == null ? 'Latency unknown' : '${server.latencyMs} ms';
    final protocols = server.supportedProtocols.isEmpty
        ? 'Protocols adapt automatically'
        : server.supportedProtocols.join(' • ').toUpperCase();
    return '$latency  •  $protocols';
  }
}
