import 'package:flutter/material.dart';

import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';
import '../../../ui/design/app_animations.dart';

/// A 3-page onboarding tour shown to first-time users.
///
/// Pages:
/// 1. Secure Your Connection (shield)
/// 2. Choose Your Location (globe)
/// 3. You're All Set (checkmark + "Get Started")
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  /// Called when the user taps "Get Started" or "Skip".
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _pageCount = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: AppAnimations.durationSlow,
        curve: AppAnimations.curveDefault,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip Button ─────────────────────────────────────────────
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.space3,
                  right: AppSpacing.space4,
                ),
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),

            // ── Page View ───────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: const [
                  _OnboardingPage(
                    icon: Icons.shield_outlined,
                    title: 'Secure Your Connection',
                    description:
                        'SecureWave encrypts your internet traffic with '
                        'military-grade protection, keeping your data safe on '
                        'any network.',
                  ),
                  _OnboardingPage(
                    icon: Icons.public,
                    title: 'Choose Your Location',
                    description:
                        'Connect through servers across dozens of regions '
                        'worldwide. Browse as if you were anywhere on the globe.',
                  ),
                  _OnboardingPage(
                    icon: Icons.check_circle_outline,
                    title: "You're All Set",
                    description:
                        'One tap is all it takes to secure your connection. '
                        'Your privacy journey starts now.',
                  ),
                ],
              ),
            ),

            // ── Dot Indicators ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pageCount, (index) {
                  final bool isActive = index == _currentPage;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space1,
                    ),
                    child: AnimatedContainer(
                      duration: AppAnimations.durationNormal,
                      curve: AppAnimations.curveDefault,
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.border,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Bottom Button ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.space5,
                right: AppSpacing.space5,
                bottom: AppSpacing.space6,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _nextPage,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                    ),
                  ),
                  child: Text(
                    _currentPage == _pageCount - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Individual Onboarding Page ────────────────────────────────────────────────

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.space6),

          // Title
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.space3),

          // Description
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.inkMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
