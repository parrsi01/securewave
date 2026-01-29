import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/bootstrap/boot_controller.dart';
import 'core/services/auth_session.dart';
import 'features/account/account_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/bootstrap/boot_screen.dart';
import 'features/bootstrap/fallback_error_screen.dart';
import 'features/servers/servers_page.dart';
import 'features/settings/language_page.dart';
import 'features/settings/settings_page.dart';
import 'features/vpn/vpn_page.dart';
import 'core/routing/app_shell.dart';

CustomTransitionPage<T> _fadePage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 120),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authSession = ref.watch(authSessionProvider);
  final boot = ref.watch(bootControllerProvider);
  final refreshListenable = Listenable.merge([authSession, boot]);

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final bootState = boot.state;
      final location = state.matchedLocation;

      if (bootState.status == BootStatus.initializing && location != '/boot') {
        return '/boot';
      }
      if (bootState.status == BootStatus.failed && location != '/error') {
        return '/error';
      }
      if (bootState.status != BootStatus.ready) {
        return null;
      }

      final isLoggedIn = authSession.isAuthenticated;
      final isAuthRoute = location == '/login' || location == '/register';
      if (location == '/boot') {
        return isLoggedIn ? '/vpn' : '/login';
      }
      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }
      if (isLoggedIn && isAuthRoute) {
        return '/vpn';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/boot',
        pageBuilder: (context, state) =>
            _fadePage<void>(state: state, child: const BootScreen()),
      ),
      GoRoute(
        path: '/error',
        pageBuilder: (context, state) => _fadePage<void>(
          state: state,
          child: const FallbackErrorScreen(
            message: 'Startup failed. See diagnostics below.',
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) =>
            _fadePage<void>(state: state, child: const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) =>
            _fadePage<void>(state: state, child: const RegisterPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/vpn',
            pageBuilder: (context, state) =>
                _fadePage<void>(state: state, child: const VpnPage()),
          ),
          GoRoute(
            path: '/servers',
            pageBuilder: (context, state) =>
                _fadePage<void>(state: state, child: const ServersPage()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _fadePage<void>(state: state, child: const SettingsPage()),
          ),
          GoRoute(
            path: '/settings/language',
            pageBuilder: (context, state) =>
                _fadePage<void>(state: state, child: const LanguagePage()),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) =>
                _fadePage<void>(state: state, child: const AccountPage()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found', style: Theme.of(context).textTheme.titleLarge),
      ),
    ),
  );
});
