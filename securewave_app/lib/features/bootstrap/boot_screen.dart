import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bootstrap/boot_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootControllerProvider).state;
    final isFailed = boot.status == BootStatus.failed;

    return Scaffold(
      body: SwPage(
        maxWidth: AppUIv1.narrowContentMaxWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const SwBrandLockup(),
            const SizedBox(height: AppUIv1.space6),
            _BootScanner(isFailed: isFailed),
            const SizedBox(height: AppUIv1.space5),
            AnimatedSwitcher(
              duration: AppUIv1.durationNormal,
              child: Text(
                isFailed
                    ? 'Startup needs attention.'
                    : 'Preparing secure runtime...',
                key: ValueKey(isFailed),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppUIv1.space2),
            Text(
              isFailed
                  ? 'Boot checks failed before the app could enter the control surface.'
                  : 'Loading configuration, session state, and VPN readiness signals.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppUIv1.space5),
            if (isFailed && boot.errorMessage != null)
              SwPanel(
                accent: AppUIv1.warning,
                child: Text(
                  boot.errorMessage!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppUIv1.warning),
                  textAlign: TextAlign.center,
                ),
              )
            else
              const _BootProgress(),
            const Spacer(),
            SizedBox(
              height: 180,
              child: ValueListenableBuilder<List<AppLogEntry>>(
                valueListenable: AppLogger.logStream,
                builder: (context, logs, _) {
                  return AnimatedOpacity(
                    duration: AppUIv1.durationNormal,
                    opacity: logs.isEmpty ? 0 : 1,
                    child: SwPanel(
                      padding: const EdgeInsets.all(AppUIv1.space3),
                      child: ListView.builder(
                        itemCount: logs.length,
                        reverse: true,
                        itemBuilder: (context, index) {
                          final entry = logs[logs.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              entry.toString(),
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootScanner extends StatefulWidget {
  const _BootScanner({required this.isFailed});

  final bool isFailed;

  @override
  State<_BootScanner> createState() => _BootScannerState();
}

class _BootScannerState extends State<_BootScanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppUIv1.durationScan,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isFailed ? AppUIv1.warning : AppUIv1.accentCyan;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.40)),
            boxShadow: AppUIv1.glow(color, opacity: 0.18),
          ),
          child: CustomPaint(
            painter: _ScannerPainter(progress: _controller.value, color: color),
            child: Icon(
              widget.isFailed
                  ? Icons.warning_amber_rounded
                  : Icons.shield_outlined,
              color: color,
              size: 54,
            ),
          ),
        );
      },
    );
  }
}

class _ScannerPainter extends CustomPainter {
  const _ScannerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        radius - i * 18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.20 - i * 0.04),
      );
    }
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * 6.28318,
      1.2,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _BootProgress extends StatelessWidget {
  const _BootProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppUIv1.radiusFull),
        child: const LinearProgressIndicator(minHeight: 4),
      ),
    );
  }
}
