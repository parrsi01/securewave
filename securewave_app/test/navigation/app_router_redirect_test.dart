import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/bootstrap/boot_controller.dart';
import 'package:securewave_app/navigation/app_router.dart';

void main() {
  group('resolveAppRedirect', () {
    test('redirects to boot while booting from non-boot page', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.initializing,
          isAuthenticated: false,
          matchedLocation: '/home',
        ),
        '/boot',
      );
    });

    test('leaves boot page to home when boot complete and authenticated', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.ready,
          isAuthenticated: true,
          matchedLocation: '/boot',
        ),
        '/home',
      );
    });

    test('leaves boot page to login when boot complete and unauthenticated', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.ready,
          isAuthenticated: false,
          matchedLocation: '/boot',
        ),
        '/login',
      );
    });

    test('redirects unauthenticated users away from app pages', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.ready,
          isAuthenticated: false,
          matchedLocation: '/settings',
        ),
        '/login',
      );
    });

    test('redirects authenticated users away from auth pages', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.ready,
          isAuthenticated: true,
          matchedLocation: '/login',
        ),
        '/home',
      );
    });

    test('returns null when route is already valid', () {
      expect(
        resolveAppRedirect(
          bootStatus: BootStatus.ready,
          isAuthenticated: true,
          matchedLocation: '/home',
        ),
        isNull,
      );
    });
  });
}
