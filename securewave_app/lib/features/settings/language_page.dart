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
              child: RadioGroup<String>(
                groupValue: language,
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(preferencesProvider.notifier).setLanguage(value);
                },
                child: const Column(
                  children: [
                    _LanguageTile(label: 'English', value: 'en'),
                    Divider(height: 1),
                    _LanguageTile(label: 'Spanish', value: 'es'),
                    Divider(height: 1),
                    _LanguageTile(label: 'French', value: 'fr'),
                    Divider(height: 1),
                    _LanguageTile(label: 'German', value: 'de'),
                  ],
                ),
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
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<String>(
      title: Text(label),
      value: value,
    );
  }
}
