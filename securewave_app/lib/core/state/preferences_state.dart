import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage.dart';

class PreferencesState {
  const PreferencesState({
    required this.language,
    required this.autoConnect,
    required this.killSwitch,
    required this.adBlockEnabled,
  });

  final String language;
  final bool autoConnect;
  final bool killSwitch;
  final bool adBlockEnabled;

  PreferencesState copyWith({
    String? language,
    bool? autoConnect,
    bool? killSwitch,
    bool? adBlockEnabled,
  }) {
    return PreferencesState(
      language: language ?? this.language,
      autoConnect: autoConnect ?? this.autoConnect,
      killSwitch: killSwitch ?? this.killSwitch,
      adBlockEnabled: adBlockEnabled ?? this.adBlockEnabled,
    );
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesController, PreferencesState>((ref) {
  return PreferencesController();
});

class PreferencesController extends StateNotifier<PreferencesState> {
  PreferencesController()
      : super(const PreferencesState(
          language: 'en',
          autoConnect: true,
          killSwitch: false,
          adBlockEnabled: true,
        )) {
    _load();
  }

  static const _languageKey = 'preferred_language';
  static const _killSwitchKey = 'pref_kill_switch';
  static const _adBlockKey = 'pref_ad_block';

  Future<void> _load() async {
    final storage = SecureStorage();
    final storedLanguage = await storage.getString(_languageKey);
    final storedAutoConnect = await storage.getBool(SecureStorage.autoConnectKey);
    final storedKillSwitch = await storage.getBool(_killSwitchKey);
    final storedAdBlock = await storage.getBool(_adBlockKey);

    if (!mounted) return;
    state = state.copyWith(
      language: storedLanguage ?? state.language,
      autoConnect: storedAutoConnect ?? state.autoConnect,
      killSwitch: storedKillSwitch ?? state.killSwitch,
      adBlockEnabled: storedAdBlock ?? state.adBlockEnabled,
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

  Future<void> setKillSwitch(bool enabled) async {
    state = state.copyWith(killSwitch: enabled);
    await SecureStorage().saveBool(_killSwitchKey, enabled);
  }

  Future<void> setAdBlock(bool enabled) async {
    state = state.copyWith(adBlockEnabled: enabled);
    await SecureStorage().saveBool(_adBlockKey, enabled);
  }
}
