import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage.dart';

class PreferencesState {
  const PreferencesState({required this.language});

  final String language;

  PreferencesState copyWith({String? language}) {
    return PreferencesState(language: language ?? this.language);
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesController, PreferencesState>((ref) {
  return PreferencesController();
});

class PreferencesController extends StateNotifier<PreferencesState> {
  PreferencesController() : super(const PreferencesState(language: 'en')) {
    _load();
  }

  static const _languageKey = 'preferred_language';

  Future<void> _load() async {
    final stored = await SecureStorage().getString(_languageKey);
    if (stored != null) {
      state = state.copyWith(language: stored);
    }
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    await SecureStorage().saveString(_languageKey, language);
  }
}
