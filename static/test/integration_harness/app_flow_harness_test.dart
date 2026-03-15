import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/models/vpn_status.dart';

class _FakeBackend {
  bool shouldFailProfile = false;

  Future<void> signUp(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw StateError('signup_failed');
    }
  }

  Future<String> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw StateError('login_failed');
    }
    return 'token-123';
  }

  Future<String> fetchVpnProfile(String token) async {
    if (token.isEmpty || shouldFailProfile) {
      throw StateError('profile_fetch_failed');
    }
    return '[Interface]\nPrivateKey = TEST\n[Peer]\nEndpoint = 198.51.100.1:51820\n';
  }
}

class _Harness {
  _Harness(this.backend);
  final _FakeBackend backend;
  VpnStatus status = VpnStatus.disconnected;
  String? error;

  Future<void> runHappyPath() async {
    status = VpnStatus.connecting;
    await backend.signUp('flow@example.com', 'StrongPass123!');
    final token = await backend.login('flow@example.com', 'StrongPass123!');
    final profile = await backend.fetchVpnProfile(token);
    if (!profile.contains('Endpoint =')) {
      throw StateError('invalid_profile');
    }
    status = VpnStatus.connected;
  }

  Future<void> runErrorPath() async {
    status = VpnStatus.connecting;
    try {
      final token = await backend.login('flow@example.com', 'StrongPass123!');
      await backend.fetchVpnProfile(token);
      status = VpnStatus.connected;
    } catch (e) {
      status = VpnStatus.error;
      error = e.toString();
    }
  }
}

void main() {
  test('sign-up -> login -> fetch VPN profile -> connected state', () async {
    final harness = _Harness(_FakeBackend());
    await harness.runHappyPath();
    expect(harness.status, VpnStatus.connected);
    expect(harness.error, isNull);
  });

  test('profile fetch failure enters expected error state', () async {
    final backend = _FakeBackend()..shouldFailProfile = true;
    final harness = _Harness(backend);
    await harness.runErrorPath();
    expect(harness.status, VpnStatus.error);
    expect(harness.error, contains('profile_fetch_failed'));
  });
}
