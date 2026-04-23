import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/preferences_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

class LanguagePage extends ConsumerWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(preferencesProvider).language;

    return Scaffold(
      appBar: AppBar(title: const Text('Language')),
      body: SwPage(
        maxWidth: AppUIv1.narrowContentMaxWidth,
        center: false,
        child: ListView(
          children: [
            const SwSectionHeader(
              eyebrow: 'Preferences',
              title: 'Language',
              subtitle: 'Choose the interface language for this device.',
            ),
            const SizedBox(height: AppUIv1.space5),
            SwPanel(
              accent: AppUIv1.accentCyan,
              child: RadioGroup<String>(
                groupValue: language,
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(preferencesProvider.notifier).setLanguage(value);
                },
                child: const Column(
                  children: [
                    _LanguageTile(label: 'English', value: 'en'),
                    SizedBox(height: AppUIv1.space2),
                    _LanguageTile(label: 'Spanish', value: 'es'),
                    SizedBox(height: AppUIv1.space2),
                    _LanguageTile(label: 'French', value: 'fr'),
                    SizedBox(height: AppUIv1.space2),
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
  const _LanguageTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      padding: EdgeInsets.zero,
      child: RadioListTile<String>(title: Text(label), value: value),
    );
  }
}
