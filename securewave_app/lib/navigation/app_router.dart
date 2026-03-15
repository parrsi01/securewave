import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/boot_controller.dart';
import '../core/services/auth_session.dart';
import '../features/bootstrap/boot_screen.dart';
import '../features/bootstrap/fallback_error_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../screens/account/edit_profile_screen.dart';
import '../screens/settings/apple_vpn_diagnostics_screen.dart';
import '../screens/settings/manage_devices_screen.dart';
import '../ui/screens/account_screen.dart';
import '../ui/screens/connection_screen.dart';
import '../ui/screens/diagnostics_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/login_screen.dart';
import '../ui/screens/register_screen.dart';
import '../ui/screens/server_selection_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/screens/vpn_debug_screen.dart';

import 'app_shell.dart';

Page<T> _buildPage<T>({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        fillColor: Colors.transparent,
        child: child,
      );
    },
  );
}

String? resolveAppRedirect({
  required BootStatus bootStatus,
  required bool isAuthenticated,
  required String matchedLocation,
}) {
  final booting = bootStatus == BootStatus.initializing;
  final onBootPage = matchedLocation == '/boot';
  final onAuthPage =
      matchedLocation == '/login' || matchedLocation == '/register';

  if (booting && !onBootPage) {
    return '/boot';
  }
  if (!booting && onBootPage) {
    return isAuthenticated ? '/home' : '/login';
  }
  if (!booting && !isAuthenticated && !onAuthPage) {
    return '/login';
  }
  if (!booting && isAuthenticated && onAuthPage) {
    return '/home';
  }
  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authSession = ref.watch(authSessionProvider);
  final boot = ref.watch(bootControllerProvider);
  final refreshListenable = Listenable.merge(<Listenable>[authSession, boot]);

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      return resolveAppRedirect(
        bootStatus: boot.state.status,
        isAuthenticated: authSession.isAuthenticated,
        matchedLocation: state.matchedLocation,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/boot',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const BootScreen(),
        ),
      ),
      GoRoute(
        path: '/error',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const FallbackErrorScreen(message: 'An error occurred'),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const RegisterScreen(),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: OnboardingScreen(
            onComplete: () {},
          ),
        ),
      ),
      GoRoute(
        path: '/locations',
        redirect: (context, state) => '/servers',
      ),
      GoRoute(
        path: '/servers/select',
        redirect: (context, state) => '/servers',
      ),
      GoRoute(
        path: '/diagnostics',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const DiagnosticsScreen(),
        ),
      ),
      GoRoute(
        path: '/diagnostics/apple',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const AppleVpnDiagnosticsScreen(),
        ),
      ),
      GoRoute(
        path: '/devices',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const ManageDevicesScreen(),
        ),
      ),
      GoRoute(
        path: '/vpn-debug',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const VpnDebugScreen(),
        ),
      ),
      GoRoute(
        path: '/edit-profile',
        pageBuilder: (context, state) => _buildPage(
          state: state,
          child: const EditProfileScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  child: const HomeScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/servers',
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  child: const ServerSelectionScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/connection',
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  child: const ConnectionScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) => _buildPage(
                  state: state,
                  child: const SettingsScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
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
      ),
    ],
  );
});
