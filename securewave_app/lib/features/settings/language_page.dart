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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppUIv1.space5),
          children: [
            Text('Language', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Choose the interface language for the SecureWave client.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space4),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppUIv1.space4),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'es', label: Text('Spanish')),
                    ButtonSegment(value: 'fr', label: Text('French')),
                    ButtonSegment(value: 'de', label: Text('German')),
                  ],
                  selected: {language},
                  onSelectionChanged: (selection) {
                    ref
                        .read(preferencesProvider.notifier)
                        .setLanguage(selection.first);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
