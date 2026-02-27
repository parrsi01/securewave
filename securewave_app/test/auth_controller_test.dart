import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/features/auth/auth_controller.dart';
import 'package:securewave_app/services/auth_service.dart';

class _FailingAuthService implements AuthService {
  @override
  Future<void> login({required String email, required String password}) async {
    throw StateError('Invalid credentials');
  }

  @override
  Future<void> register(
      {required String email, required String password}) async {}
}

void main() {
  group('AuthState.copyWith', () {
    test('preserves existing error message when errorMessage is omitted', () {
      const state = AuthState(errorMessage: 'bad credentials');

      final next = state.copyWith(isLoading: false);

      expect(next.errorMessage, 'bad credentials');
    });

    test('supports explicit error clear with null', () {
      const state = AuthState(errorMessage: 'bad credentials');

      final next = state.copyWith(errorMessage: null);

      expect(next.errorMessage, isNull);
    });
  });

  test('AuthController.login keeps error after failed login', () async {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(_FailingAuthService()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).login(
          email: 'user@example.com',
          password: 'password123',
        );

    final state = container.read(authControllerProvider);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, isNotEmpty);
  });
}
