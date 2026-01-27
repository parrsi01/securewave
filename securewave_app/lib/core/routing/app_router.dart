import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/home/home_page.dart';
import '../../features/servers/servers_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/vpn/vpn_page.dart';
import '../services/auth_session.dart';
import 'app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authSession = ref.watch(authSessionProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authSession,
    redirect: (context, state) {
      final isLoggedIn = authSession.isAuthenticated;
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register' || location == '/';

      if (!isLoggedIn && !isAuthRoute) {
        return '/login';
      }
      if (isLoggedIn && (location == '/' || location == '/login' || location == '/register')) {
        return '/vpn';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/vpn',
            builder: (context, state) => const VpnPage(),
          ),
          GoRoute(
            path: '/servers',
            builder: (context, state) => const ServersPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
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
