import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../services/secure_storage.dart';

class PreferencesState {
  const PreferencesState({
    required this.language,
    required this.autoConnect,
    required this.loaded,
    required this.privilegeAutomationRequested,
    required this.killSwitch,
    required this.adBlockEnabled,
  });

  final String language;
  final bool autoConnect;
  final bool loaded;
  final bool privilegeAutomationRequested;
  final bool killSwitch;
  final bool adBlockEnabled;

  PreferencesState copyWith({
    String? language,
    bool? autoConnect,
    bool? loaded,
    bool? privilegeAutomationRequested,
    bool? killSwitch,
    bool? adBlockEnabled,
  }) {
    return PreferencesState(
      language: language ?? this.language,
      autoConnect: autoConnect ?? this.autoConnect,
      loaded: loaded ?? this.loaded,
      privilegeAutomationRequested:
          privilegeAutomationRequested ?? this.privilegeAutomationRequested,
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
          loaded: false,
          privilegeAutomationRequested: false,
          killSwitch: false,
          adBlockEnabled: true,
        )) {
    _load();
  }

  static const _languageKey = 'preferred_language';
  static const _killSwitchKey = 'pref_kill_switch';
  static const _adBlockKey = 'pref_ad_block';

  Future<void> _load() async {
    try {
      final storage = SecureStorage();
      final storedLanguage = await storage.getString(_languageKey);
      final storedAutoConnect =
          await storage.getBool(SecureStorage.autoConnectKey);
      final storedKillSwitch = await storage.getBool(_killSwitchKey);
      final storedPrivilegeAutomation =
          await storage.getBool(SecureStorage.privilegeAutomationRequestedKey);
      final storedAdBlock = await storage.getBool(_adBlockKey);

      if (!mounted) return;
      state = state.copyWith(
        language: storedLanguage ?? state.language,
        autoConnect: storedAutoConnect ?? state.autoConnect,
        loaded: true,
        privilegeAutomationRequested:
            storedPrivilegeAutomation ?? state.privilegeAutomationRequested,
        killSwitch: storedKillSwitch ?? state.killSwitch,
        adBlockEnabled: storedAdBlock ?? state.adBlockEnabled,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Preferences restore failed; continuing with in-memory defaults.',
      );
      AppLogger.error(
        'Preferences restore failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    try {
      await SecureStorage().saveString(_languageKey, language);
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to persist preferred language.');
      AppLogger.error(
        'Preferred language persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setAutoConnect(bool enabled) async {
    state = state.copyWith(autoConnect: enabled);
    try {
      await SecureStorage().saveBool(SecureStorage.autoConnectKey, enabled);
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to persist auto-connect preference.');
      AppLogger.error(
        'Auto-connect preference persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setKillSwitch(bool enabled) async {
    state = state.copyWith(killSwitch: enabled);
    try {
      await SecureStorage().saveBool(_killSwitchKey, enabled);
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to persist kill switch preference.');
      AppLogger.error(
        'Kill switch preference persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setPrivilegeAutomationRequested(bool enabled) async {
    state = state.copyWith(privilegeAutomationRequested: enabled);
    try {
      await SecureStorage()
          .saveBool(SecureStorage.privilegeAutomationRequestedKey, enabled);
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to persist privilege automation preference.');
      AppLogger.error(
        'Privilege automation preference persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> setAdBlock(bool enabled) async {
    state = state.copyWith(adBlockEnabled: enabled);
    try {
      await SecureStorage().saveBool(_adBlockKey, enabled);
    } catch (error, stackTrace) {
      AppLogger.warning('Failed to persist ad-block preference.');
      AppLogger.error(
        'Ad-block preference persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
