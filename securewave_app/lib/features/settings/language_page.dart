import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/preferences_state.dart';
import '../../ui/app_ui_v1.dart';

class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(preferencesProvider).language;

    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: SecurePageBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = AppUIv1.pagePaddingFor(constraints.maxWidth);

              return SingleChildScrollView(
                padding: padding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SecureSurface(
                          variant: SecureSurfaceVariant.raised,
                          padding: const EdgeInsets.all(AppUIv1.space5),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppUIv1.surfaceMuted,
                                  borderRadius:
                                      BorderRadius.circular(AppUIv1.radiusS),
                                  border: Border.all(color: AppUIv1.border),
                                ),
                                child: const Icon(
                                  Icons.language_rounded,
                                  color: AppUIv1.accentCyan,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: AppUIv1.space4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Language',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: AppUIv1.space1),
                                    Text(
                                      'Choose the presentation language for SecureWave.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppUIv1.space4),
                        SecureSurface(
                          variant: SecureSurfaceVariant.raised,
                          padding: const EdgeInsets.all(AppUIv1.space3),
                          child: RadioGroup<String>(
                            groupValue: language,
                            onChanged: (value) {
                              if (value == null) return;
                              ref
                                  .read(preferencesProvider.notifier)
                                  .setLanguage(value);
                            },
                            child: const Column(
                              children: [
                                _LanguageTile(
                                  label: 'English',
                                  value: 'en',
                                  region: 'Default',
                                ),
                                SizedBox(height: AppUIv1.space2),
                                _LanguageTile(
                                  label: 'Spanish',
                                  value: 'es',
                                  region: 'Espanol',
                                ),
                                SizedBox(height: AppUIv1.space2),
                                _LanguageTile(
                                  label: 'French',
                                  value: 'fr',
                                  region: 'Francais',
                                ),
                                SizedBox(height: AppUIv1.space2),
                                _LanguageTile(
                                  label: 'German',
                                  value: 'de',
                                  region: 'Deutsch',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.value,
    required this.region,
  });

  final String label;
  final String value;
  final String region;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: EdgeInsets.zero,
      child: RadioListTile<String>(
        value: value,
        title: Text(label),
        subtitle: Text(region),
        secondary: const Icon(
          Icons.translate_rounded,
          color: AppUIv1.accentCyan,
        ),
      ),
    );
  }
}
