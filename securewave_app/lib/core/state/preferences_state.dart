import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage.dart';

class PreferencesState {
  const PreferencesState({
    required this.language,
    required this.autoConnect,
  });

  final String language;
  final bool autoConnect;

  PreferencesState copyWith({String? language, bool? autoConnect}) {
    return PreferencesState(
      language: language ?? this.language,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesController, PreferencesState>((ref) {
  return PreferencesController();
});

class PreferencesController extends StateNotifier<PreferencesState> {
  PreferencesController()
      : super(const PreferencesState(language: 'en', autoConnect: true)) {
    _load();
  }

  static const _languageKey = 'preferred_language';

  Future<void> _load() async {
    final storage = SecureStorage();
    final storedLanguage = await storage.getString(_languageKey);
    final storedAutoConnect = await storage.getBool(SecureStorage.autoConnectKey);

    if (!mounted) return;
    state = state.copyWith(
      language: storedLanguage ?? state.language,
      autoConnect: storedAutoConnect ?? state.autoConnect,
    );
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    await SecureStorage().saveString(_languageKey, language);
  }

  Future<void> setAutoConnect(bool enabled) async {
    state = state.copyWith(autoConnect: enabled);
    await SecureStorage().saveBool(SecureStorage.autoConnectKey, enabled);
  }
}
