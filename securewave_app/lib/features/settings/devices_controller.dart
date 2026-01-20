import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/api_service.dart';
import '../../core/utils/api_error.dart';

class DevicesState {
  const DevicesState({
    this.isLoading = false,
    this.devices = const [],
    this.errorMessage,
  });

  final bool isLoading;
  final List<Map<String, dynamic>> devices;
  final String? errorMessage;

  DevicesState copyWith({
    bool? isLoading,
    List<Map<String, dynamic>>? devices,
    String? errorMessage,
  }) {
    return DevicesState(
      isLoading: isLoading ?? this.isLoading,
      devices: devices ?? this.devices,
      errorMessage: errorMessage,
    );
  }
}

final devicesControllerProvider = StateNotifierProvider<DevicesController, DevicesState>((ref) {
  return DevicesController(ref)..loadDevices();
});

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this._ref) : super(const DevicesState());

  final Ref _ref;

  Future<void> loadDevices() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      final response = await api.get('/vpn/devices');
      final data = (response.data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      state = state.copyWith(devices: data, isLoading: false);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ApiError.messageFrom(error, fallback: 'Unable to load devices.'),
      );
    }
  }

  Future<void> addDevice(String name) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/devices', data: {'device_name': name});
      await loadDevices();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ApiError.messageFrom(error, fallback: 'Unable to add device.'),
      );
    }
  }

  Future<void> renameDevice(String id, String name) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.patch('/vpn/devices/$id', data: {'device_name': name});
      await loadDevices();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ApiError.messageFrom(error, fallback: 'Unable to rename device.'),
      );
    }
  }

  Future<void> revokeDevice(String id) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.delete('/vpn/devices/$id');
      await loadDevices();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ApiError.messageFrom(error, fallback: 'Unable to revoke device.'),
      );
    }
  }

  Future<void> rotateKeys(String id) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final api = _ref.read(apiServiceProvider);
      await api.post('/vpn/devices/$id/rotate-keys');
      await loadDevices();
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: ApiError.messageFrom(error, fallback: 'Unable to rotate keys.'),
      );
    }
  }
}
