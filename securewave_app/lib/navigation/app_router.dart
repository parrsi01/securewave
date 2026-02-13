import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/boot_controller.dart';
import '../core/services/auth_session.dart';
import '../ui/design/app_animations.dart';
import '../ui/design/app_typography.dart';

// Existing auth and boot screens (reuse)
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/bootstrap/boot_screen.dart';
import '../features/bootstrap/fallback_error_screen.dart';

// Main app screens
import '../screens/home/home_screen.dart';
import '../screens/locations/locations_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/account/account_screen.dart';

// Navigation shell
import 'app_shell.dart';

/// Builds a platform-adaptive page with custom transitions.
Page<T> _buildPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  // iOS/macOS: Native Cupertino slide transition
  if (AppTypography.isApplePlatform) {
    return CupertinoPage<T>(key: state.pageKey, child: child);
  }

  // Android/Windows/Linux: Fade + slide transition
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: AppAnimations.durationNormal,
    reverseTransitionDuration: AppAnimations.durationFast,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppAnimations.curveEnter,
        reverseCurve: AppAnimations.curveExit,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Main app router provider.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authSession = ref.watch(authSessionProvider);
  final boot = ref.watch(bootControllerProvider);
  final refreshListenable = Listenable.merge([authSession, boot]);

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final booting = boot.state.status == BootStatus.initializing;
      final authed = authSession.isAuthenticated;
      final onAuthPage =
          state.matchedLocation == '/login' || state.matchedLocation == '/register';

      // Show boot screen while bootstrapping
      if (booting && state.matchedLocation != '/boot') {
        return '/boot';
      }

      // After boot: redirect to login if not authenticated
      if (!booting && !authed && !onAuthPage) {
        return '/login';
      }

      // After boot: redirect to home if authenticated and on auth page
      if (!booting && authed && onAuthPage) {
        return '/home';
      }

      return null; // No redirect
    },
    routes: [
      // Boot screen
      GoRoute(
        path: '/boot',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const BootScreen(),
        ),
      ),

      // Error screen
      GoRoute(
        path: '/error',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const FallbackErrorScreen(message: 'An error occurred'),
        ),
      ),

      // Auth routes (no shell)
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const RegisterPage(),
        ),
      ),

      // Main app shell with 4 destinations
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => _buildPage(
              state: state,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/locations',
            pageBuilder: (context, state) => _buildPage(
              state: state,
              child: const LocationsScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _buildPage(
              state: state,
              child: const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: '/account',
            pageBuilder: (context, state) => _buildPage(
              state: state,
              child: const AccountScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
