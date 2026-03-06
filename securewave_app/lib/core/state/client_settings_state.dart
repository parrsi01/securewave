import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_storage.dart';

class ClientSettingsState {
  const ClientSettingsState({
    this.autoConnect = true,
    this.autoReconnect = true,
    this.bestEffortKillSwitch = true,
  });

  final bool autoConnect;
  final bool autoReconnect;
  final bool bestEffortKillSwitch;

  ClientSettingsState copyWith({
    bool? autoConnect,
    bool? autoReconnect,
    bool? bestEffortKillSwitch,
  }) {
    return ClientSettingsState(
      autoConnect: autoConnect ?? this.autoConnect,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      bestEffortKillSwitch: bestEffortKillSwitch ?? this.bestEffortKillSwitch,
    );
  }
}

final clientSettingsProvider =
    StateNotifierProvider<ClientSettingsController, ClientSettingsState>((ref) {
  return ClientSettingsController();
});

class ClientSettingsController extends StateNotifier<ClientSettingsState> {
  ClientSettingsController() : super(const ClientSettingsState()) {
    _load();
  }

  final SecureStorage _storage = SecureStorage();

  Future<void> _load() async {
    final autoConnect =
        await _storage.getBool(SecureStorage.settingsAutoConnectKey);
    final autoReconnect =
        await _storage.getBool(SecureStorage.settingsAutoReconnectKey);
    final killSwitch =
        await _storage.getBool(SecureStorage.settingsKillSwitchKey);

    state = state.copyWith(
      autoConnect: autoConnect ?? state.autoConnect,
      autoReconnect: autoReconnect ?? state.autoReconnect,
      bestEffortKillSwitch: killSwitch ?? state.bestEffortKillSwitch,
    );
  }

  Future<void> setAutoConnect(bool value) async {
    state = state.copyWith(autoConnect: value);
    await _storage.saveBool(SecureStorage.settingsAutoConnectKey, value);
  }

  Future<void> setAutoReconnect(bool value) async {
    state = state.copyWith(autoReconnect: value);
    await _storage.saveBool(SecureStorage.settingsAutoReconnectKey, value);
  }

  Future<void> setBestEffortKillSwitch(bool value) async {
    state = state.copyWith(bestEffortKillSwitch: value);
    await _storage.saveBool(SecureStorage.settingsKillSwitchKey, value);
  }
}
