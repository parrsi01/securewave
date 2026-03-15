import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Settings screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          _Section(
            title: 'VPN',
            tiles: [
              _Tile(
                icon: Icons.bug_report_outlined,
                label: 'Diagnostics',
                onTap: () => context.push('/diagnostics'),
              ),
              _Tile(
                icon: Icons.devices_rounded,
                label: 'Manage Devices',
                onTap: () => context.push('/devices'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          _Section(
            title: 'Account',
            tiles: [
              _Tile(
                icon: Icons.person_outline_rounded,
                label: 'Edit Profile',
                onTap: () => context.push('/edit-profile'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          _Section(
            title: 'App',
            tiles: [
              _Tile(
                icon: Icons.info_outline_rounded,
                label: 'About SecureWave',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
        ),
        ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.space2,
            bottom: AppSpacing.space2,
          ),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.inkSoft,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  tiles[i],
                  if (i < tiles.length - 1)
                    Divider(
                      height: 1,
                      indent: AppSpacing.space7,
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primaryBright;
    return ListTile(
      leading: Icon(icon, color: color, size: AppSpacing.iconM),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: AppSpacing.iconS,
        color: AppColors.inkSoft,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space1,
      ),
      onTap: onTap,
    );
  }
}
