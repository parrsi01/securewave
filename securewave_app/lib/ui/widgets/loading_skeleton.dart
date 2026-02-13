import 'package:flutter/material.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Skeleton loader component for loading states.
///
/// Provides a shimmer effect to indicate content is loading.
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                AppColors.surfaceMuted,
                AppColors.border,
                AppColors.surfaceMuted,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

/// Skeleton list tile for loading states.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({
    super.key,
    this.hasLeading = true,
    this.hasTrailing = false,
  });

  final bool hasLeading;
  final bool hasTrailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      child: Row(
        children: [
          if (hasLeading) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.radiusM),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                  ),
                ),
                const SizedBox(height: AppSpacing.space2),
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusS),
                  ),
                ),
              ],
            ),
          ),
          if (hasTrailing) ...[
            const SizedBox(width: AppSpacing.space3),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.radiusS),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton card for loading states.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 120,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(color: AppColors.border),
      ),
    );
  }
}
