part of '../app.dart';

/// Debug-only frontend exercise for every known WireGuard error surface.
///
/// The sequence is deliberately isolated from [VpnStateNotifier] and
/// [VpnService]: it renders simulated messages and never touches the helper,
/// credentials, routes, or the backend.
class WireGuardErrorSequence extends StatefulWidget {
  const WireGuardErrorSequence(
      {super.key, this.interval = const Duration(milliseconds: 900)});

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
          if (!_scrollController.hasClients) return;
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
