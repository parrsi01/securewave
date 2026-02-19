import 'package:flutter/material.dart';

import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

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
    _PageData(Icons.shield_rounded, 'Secure Your Connection',
        'Your traffic is encrypted end-to-end. Browse, stream, and communicate without anyone watching.'),
    _PageData(Icons.public_rounded, 'Choose Your Location',
        'Connect to servers in 35+ countries. Pick the fastest or choose by region.'),
    _PageData(Icons.check_circle_rounded, "You're All Set",
        'Start browsing securely. You can always change settings later.'),
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space4),
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text('Skip'),
                ),
              ),
            ),
            // Pages
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
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Transform.translate(
                            offset: Offset(offset * 30, 0),
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryLight,
                              ),
                              child: Icon(data.icon, size: 56, color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space6),
                          Transform.translate(
                            offset: Offset(offset * 15, 0),
                            child: Text(
                              data.title,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space3),
                          SizedBox(
                            width: 280,
                            child: Text(
                              data.description,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: AppAnimations.durationNormal,
                  curve: AppAnimations.curveDefault,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    color: active ? AppColors.primary : AppColors.inkSoft.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.space5),
            // Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast
                      ? widget.onComplete
                      : () => _controller.nextPage(
                            duration: AppAnimations.durationNormal,
                            curve: AppAnimations.curveDefault,
                          ),
                  child: Text(isLast ? 'Get Started' : 'Next'),
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
  const _PageData(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}
