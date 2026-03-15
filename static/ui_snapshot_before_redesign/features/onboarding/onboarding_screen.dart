import 'package:flutter/material.dart';

import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Onboarding screen — v2.
///
/// Full-bleed page views with icon in gradient circle,
/// parallax text, pill page indicators, and smooth CTA transitions.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      icon: Icons.shield_rounded,
      gradient: [Color(0xFF1B6B68), Color(0xFF093837)],
      title: 'Encrypted by default',
      description:
          'Your traffic is end-to-end encrypted. Browse, stream, and communicate without anyone watching.',
    ),
    _PageData(
      icon: Icons.public_rounded,
      gradient: [Color(0xFF1A5276), Color(0xFF0D2840)],
      title: 'Choose your location',
      description:
          'Connect to 35+ countries. Pick the fastest server automatically or choose by region.',
    ),
    _PageData(
      icon: Icons.check_circle_rounded,
      gradient: [Color(0xFF1F6B3C), Color(0xFF0B3D1E)],
      title: "You're all set",
      description:
          'Start browsing privately. Your settings can be changed any time from the app.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final p = _controller.page?.round() ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip ──────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                  vertical: AppSpacing.space3,
                ),
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('Skip'),
                ),
              ),
            ),

            // ── Pages ──────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final data = _pages[index];
                  return AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      double offset = 0;
                      if (_controller.position.haveDimensions) {
                        offset = (_controller.page ?? 0) - index;
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Icon in gradient circle
                            Transform.translate(
                              offset: Offset(offset * 40, 0),
                              child: Container(
                                width: 128,
                                height: 128,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: data.gradient,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: data.gradient[0]
                                          .withValues(alpha: 0.35),
                                      blurRadius: 28,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(data.icon,
                                    size: 56, color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space6),

                            // Title
                            Transform.translate(
                              offset: Offset(offset * 20, 0),
                              child: Text(
                                data.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space3),

                            // Description
                            Transform.translate(
                              offset: Offset(offset * 10, 0),
                              child: SizedBox(
                                width: 300,
                                child: Text(
                                  data.description,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Pill indicators ────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: AppAnimations.durationNormal,
                  curve: AppAnimations.curveDefault,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    color: active
                        ? (isDark ? AppColors.primaryBright : AppColors.primary)
                        : (isDark
                            ? AppColors.darkInkSoft
                            : AppColors.inkSoft)
                            .withValues(alpha: 0.3),
                  ),
                );
              }),
            ),

            const SizedBox(height: AppSpacing.space5),

            // ── CTA button ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space5),
              child: SizedBox(
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: AppAnimations.durationFast,
                  child: FilledButton(
                    key: ValueKey(isLast),
                    onPressed: isLast
                        ? widget.onComplete
                        : () => _controller.nextPage(
                              duration: AppAnimations.durationNormal,
                              curve: AppAnimations.curveDefault,
                            ),
                    child: Text(isLast ? 'Get Started' : 'Continue'),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.space6),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  const _PageData({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String description;
}
