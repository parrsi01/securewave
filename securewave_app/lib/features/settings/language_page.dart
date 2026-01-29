import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/app_ui_v1.dart';
import '../../core/state/preferences_state.dart';

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
            Text('Choose your language', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppUIv1.space3),
            Card(
              child: Column(
                children: [
                  _LanguageTile(
                    label: 'English',
                    value: 'en',
                    groupValue: language,
                    onSelected: (value) =>
                        ref.read(preferencesProvider.notifier).setLanguage(value),
                  ),
                  const Divider(height: 1),
                  _LanguageTile(
                    label: 'Spanish',
                    value: 'es',
                    groupValue: language,
                    onSelected: (value) =>
                        ref.read(preferencesProvider.notifier).setLanguage(value),
                  ),
                  const Divider(height: 1),
                  _LanguageTile(
                    label: 'French',
                    value: 'fr',
                    groupValue: language,
                    onSelected: (value) =>
                        ref.read(preferencesProvider.notifier).setLanguage(value),
                  ),
                  const Divider(height: 1),
                  _LanguageTile(
                    label: 'German',
                    value: 'de',
                    groupValue: language,
                    onSelected: (value) =>
                        ref.read(preferencesProvider.notifier).setLanguage(value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
      groupValue: groupValue,
      onChanged: (value) {
        if (value == null) return;
        onSelected(value);
      },
    );
  }
}
