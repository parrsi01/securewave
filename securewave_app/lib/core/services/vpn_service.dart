import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

import '../models/vpn_protocol.dart';
import '../models/vpn_status.dart';
import '../logging/app_logger.dart';

abstract class VpnService {
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, Map<String, dynamic>? profile});
  Future<VpnStatus> disconnect();
  VpnStatus getStatus();
  bool get isNativeAvailable;
  String? get availabilityMessage;
  Future<VpnCapabilities> getCapabilities();
}

class VpnServiceException implements Exception {
  VpnServiceException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'VpnServiceException($code): $message';
}

class VpnCapabilities {
  const VpnCapabilities({
    required this.wireGuard,
    required this.openVpn,
    required this.ikev2,
    this.windowsThreadSafe = false,
    this.androidVpnServiceBased = false,
    this.macosEntitlementReady = false,
    this.linuxWireGuardInstalled = true,
    this.linuxElevationAvailable = true,
    this.wireGuardInstallHint,
    this.openVpnInstallHint,
    this.ikev2InstallHint,
    this.linuxElevationHint,
    this.macosEntitlementWarning,
  });

  final bool wireGuard;
  final bool openVpn;
  final bool ikev2;

  final bool windowsThreadSafe;
  final bool androidVpnServiceBased;
  final bool macosEntitlementReady;
  final bool linuxWireGuardInstalled;
  final bool linuxElevationAvailable;

  final String? wireGuardInstallHint;
  final String? openVpnInstallHint;
  final String? ikev2InstallHint;
  final String? linuxElevationHint;
  final String? macosEntitlementWarning;

  bool supportsProtocol(VpnProtocol protocol) {
    switch (protocol) {
      case VpnProtocol.auto:
        return false;
      case VpnProtocol.wireGuard:
        return wireGuard;
      case VpnProtocol.openVpn:
        return openVpn;
      case VpnProtocol.ikev2:
        return ikev2;
    }
  }

  static const VpnCapabilities none = VpnCapabilities(
    wireGuard: false,
    openVpn: false,
    ikev2: false,
    windowsThreadSafe: false,
    androidVpnServiceBased: false,
    macosEntitlementReady: false,
    linuxWireGuardInstalled: false,
    linuxElevationAvailable: false,
  );
}

class ChannelVpnService implements VpnService {
  ChannelVpnService() {
    _nativeAvailable = false;
    unawaited(
      _refreshNativeAvailability().catchError((Object error, StackTrace stack) {
        AppLogger.warning('Initial VPN availability refresh failed: $error');
        AppLogger.error(
          'Initial VPN availability refresh failed',
          error: error,
          stackTrace: stack,
        );
        return false;
      }),
    );
  }

  final MethodChannel _channel = const MethodChannel('securewave/vpn');
  VpnStatus _status = VpnStatus.disconnected;
  bool _nativeAvailable = false;
  String? _lastNativeAvailabilityMessage;

  @override
  bool get isNativeAvailable => _nativeAvailable;

  @override
  String? get availabilityMessage => _lastNativeAvailabilityMessage;

  /// Best-effort sync of tunnel status from the native layer.
  ///
  /// This is primarily used to avoid "stuck disconnected" states after an app
  /// restart when a tunnel/service may still be running.
  Future<VpnStatus> refreshStatus() async {
    if (!_supportsNativeChannel()) {
      _status = VpnStatus.disconnected;
      return _status;
    }
    try {
      final raw = await _channel.invokeMethod<String>('getStatus');
      final normalized = (raw ?? '').toLowerCase().trim();
      if (normalized == 'connected') {
        _status = VpnStatus.connected;
      } else if (normalized == 'disconnected') {
        _status = VpnStatus.disconnected;
      }
    } on MissingPluginException {
      // No native implementation for this platform/build.
    } on PlatformException catch (error) {
      AppLogger.warning('Native VPN status check failed: ${error.code}');
    } catch (_) {
      // Best-effort: never fail app startup due to status sync.
    }
    return _status;
  }

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, Map<String, dynamic>? profile}) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (protocol == VpnProtocol.auto) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unresolved',
          'VPN protocol was not resolved. Select a concrete protocol and retry.',
        );
      }
      final capabilities = await getCapabilities();
      if (!capabilities.supportsProtocol(protocol)) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'protocol_unavailable',
          _protocolUnavailableMessage(protocol, capabilities),
        );
      }
      final available = await _refreshNativeAvailability();
      if (!available) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'vpn_unavailable',
          _lastNativeAvailabilityMessage ??
              _protocolUnavailableMessage(protocol, capabilities),
        );
      }
      final payload = profile ?? const <String, dynamic>{};
      if (payload.isEmpty) {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          'invalid_profile',
          'Missing VPN profile. Please refresh and try again.',
        );
      }
      await _channel.invokeMethod('connect', {
        'protocol': vpnProtocolStorageValue(protocol),
        'profile': payload,
        if (protocol == VpnProtocol.wireGuard &&
            (payload['wireguard_config']?.toString() ?? '').trim().isNotEmpty)
          'config': payload['wireguard_config']?.toString(),
      }).timeout(const Duration(seconds: 30));
      _status = VpnStatus.connected;
    } on TimeoutException {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_timeout',
        'Native VPN operation timed out. Please retry.',
      );
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          error.code,
          error.message ??
              _defaultUnavailableMessage(
                  platform.operatingSystem.name.toLowerCase()),
          details: error.details,
        );
      } else {
        _status = VpnStatus.disconnected;
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to start VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_unavailable',
        'Native VPN plugin missing for this platform/build. '
            'Reinstall the app and retry.',
      );
    }
    return _status;
  }

  @override
  Future<VpnCapabilities> getCapabilities() async {
    if (!_supportsNativeChannel()) return VpnCapabilities.none;
    final os = platform.operatingSystem.name.toLowerCase();
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 2));
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        bool b(String key) {
          final value = data[key];
          if (value == null) return false;
          if (value is bool) return value;
          if (value is num) return value != 0;
          return value.toString().toLowerCase() == 'true';
        }

        String? s(String key) {
          final value = data[key];
          final text = value?.toString();
          if (text == null || text.trim().isEmpty) return null;
          return text.trim();
        }

        return VpnCapabilities(
          wireGuard: b('wireguard'),
          openVpn: b('openvpn'),
          ikev2: b('ikev2'),
          windowsThreadSafe: b('windows_thread_safe'),
          androidVpnServiceBased: b('android_vpnservice_based'),
          macosEntitlementReady: b('macos_entitlements_ready'),
          linuxWireGuardInstalled: os != 'linux' || b('linux_wg_installed'),
          linuxElevationAvailable:
              os != 'linux' || b('linux_elevation_available'),
          wireGuardInstallHint: s('wireguard_install_hint'),
          openVpnInstallHint: s('openvpn_install_hint'),
          ikev2InstallHint: s('ikev2_install_hint'),
          linuxElevationHint: s('linux_elevation_hint'),
          macosEntitlementWarning: s('macos_entitlement_warning'),
        );
      }
    } on TimeoutException {
      // Fall back below.
    } on MissingPluginException {
      // Fall back below.
    } on PlatformException {
      // Fall back below.
    }

    final wgAvailable = await _refreshNativeAvailability();
    final linuxInstallHint =
        os == 'linux' && !wgAvailable ? _linuxInstallGuide() : null;
    final macosWarning =
        os == 'macos' && !wgAvailable ? _macosEntitlementWarning() : null;

    return VpnCapabilities(
      wireGuard: wgAvailable,
      openVpn: false,
      ikev2: false,
      windowsThreadSafe: os == 'windows',
      androidVpnServiceBased: os == 'android',
      macosEntitlementReady: os != 'macos' || wgAvailable,
      linuxWireGuardInstalled: os != 'linux' || wgAvailable,
      linuxElevationAvailable: os != 'linux' || wgAvailable,
      wireGuardInstallHint: linuxInstallHint,
      openVpnInstallHint: null,
      ikev2InstallHint: null,
      linuxElevationHint:
          os == 'linux' && !wgAvailable ? _linuxElevationGuide() : null,
      macosEntitlementWarning: macosWarning,
    );
  }

  @override
  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.disconnecting;
    try {
      final available = await _refreshNativeAvailability();
      if (!available) {
        _status = VpnStatus.disconnected;
        return _status;
      }
      await _channel
          .invokeMethod('disconnect')
          .timeout(const Duration(seconds: 20));
      _status = VpnStatus.disconnected;
    } on TimeoutException {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        'vpn_timeout',
        'Timed out while stopping the VPN tunnel.',
      );
    } on PlatformException catch (error) {
      if (_isNativeUnavailableError(error)) {
        _nativeAvailable = false;
        _status = VpnStatus.disconnected;
      } else {
        throw VpnServiceException(
          error.code,
          error.message ?? 'Unable to stop VPN tunnel.',
          details: error.details,
        );
      }
    } on MissingPluginException {
      _nativeAvailable = false;
      _status = VpnStatus.disconnected;
    }
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;

  bool _supportsNativeChannel() {
    if (kIsWeb) return false;
    final os = platform.operatingSystem.name.toLowerCase();
    return os == 'android' ||
        os == 'ios' ||
        os == 'macos' ||
        os == 'windows' ||
        os == 'linux';
  }

  Future<bool> _refreshNativeAvailability() async {
    if (!_supportsNativeChannel()) {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'VPN is unavailable in this environment.';
      return _nativeAvailable;
    }
    final os = platform.operatingSystem.name.toLowerCase();
    try {
      final available = await _channel
          .invokeMethod<bool>('isAvailable')
          .timeout(const Duration(seconds: 2));
      if (available != null) {
        _nativeAvailable = available;
      } else {
        _nativeAvailable = true;
      }
      if (_nativeAvailable) {
        _lastNativeAvailabilityMessage = null;
      } else {
        _lastNativeAvailabilityMessage = _defaultUnavailableMessage(os);
      }
    } on TimeoutException {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'VPN availability check timed out. Retry in a moment.';
    } on MissingPluginException {
      _nativeAvailable = false;
      _lastNativeAvailabilityMessage =
          'Native VPN plugin missing for this platform/build.';
    } on PlatformException catch (error) {
      _lastNativeAvailabilityMessage =
          error.message ?? _defaultUnavailableMessage(os);
      _nativeAvailable = false;
    }
    return _nativeAvailable;
  }

  String _defaultUnavailableMessage(String os) {
    switch (os) {
      case 'linux':
        return _linuxInstallGuide();
      case 'windows':
        return 'No supported VPN runtime is currently available on this build.';
      case 'macos':
        return _macosEntitlementWarning();
      case 'android':
        return 'VPN runtime unavailable on this Android build. '
            'Ensure VpnService permissions are granted.';
      case 'ios':
        return 'VPN runtime unavailable on this iOS build. '
            'Check Network Extension entitlements and PacketTunnel embedding.';
      default:
        return 'Native VPN tunnel unavailable on this device.';
    }
  }

  String _linuxInstallGuide() {
    return 'WireGuard runtime is unavailable on Linux. '
        'Install wireguard-tools and retry:\n'
        '  Ubuntu/Debian: sudo apt-get install wireguard-tools\n'
        '  Fedora: sudo dnf install wireguard-tools\n'
        '  Arch: sudo pacman -S wireguard-tools';
  }

  String _linuxElevationGuide() {
    return 'Administrator elevation is unavailable on Linux. '
        'Install PolicyKit (pkexec) and ensure a polkit authentication agent '
        'is running, or launch SecureWave as root.';
  }

  String _protocolUnavailableMessage(
    VpnProtocol protocol,
    VpnCapabilities capabilities,
  ) {
    if (protocol == VpnProtocol.wireGuard) {
      return capabilities.wireGuardInstallHint ??
          'WireGuard runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.openVpn) {
      return capabilities.openVpnInstallHint ??
          'OpenVPN runtime is not available on this device.';
    }
    if (protocol == VpnProtocol.ikev2) {
      return capabilities.ikev2InstallHint ??
          'IKEv2/IPsec runtime is not available on this device.';
    }
    return '${vpnProtocolLabel(protocol)} is not available on this build. '
        'Select a different protocol or switch to Automatic.';
  }

  String _macosEntitlementWarning() {
    return 'macOS VPN requires Network Extension entitlements for Runner and '
        'PacketTunnel targets. This build is missing required entitlements.';
  }

  bool _isNativeUnavailableError(PlatformException error) {
    return error.code == 'vpn_not_configured' ||
        error.code == 'vpn_unavailable' ||
        error.code == 'vpn_permission_required' ||
        error.code == 'protocol_unavailable';
  }
}
