import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:securewave_app/debug/automation_keys.dart';
import 'package:securewave_app/ui/design/app_colors.dart';
import 'package:securewave_app/ui/layout/adaptive_shell_scaffold.dart';
import 'package:securewave_app/ui/screens/auth/login_screen.dart';
import 'package:securewave_app/ui/screens/auth/register_screen.dart';
import 'package:securewave_app/ui/theme/app_colors.dart';
import 'package:securewave_app/ui/theme/app_theme.dart';
import 'package:securewave_app/ui/widgets/brand_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'read':
            return null;
          case 'readAll':
            return <String, String>{};
          default:
            return null;
        }
      },
    );
  });

  test('legacy and modern UI palettes stay aligned', () {
    expect(AppColors.primaryBright, HtbColors.neonGreen);
    expect(AppColors.secondary, HtbColors.neonCyan);
    expect(AppColors.darkBackground, HtbColors.bg0);
    expect(AppColors.darkBackgroundWarm, HtbColors.bg1);
    expect(AppColors.darkSurface, HtbColors.bg2);
    expect(AppColors.darkSurfaceElevated, HtbColors.bg3);
    expect(AppColors.darkInk, HtbColors.textPrimary);
    expect(AppColors.darkInkMuted, HtbColors.textSecondary);
  });

  test('dark theme maps the shared brand tokens consistently', () {
    final theme = HtbTheme.dark();
    final elevated = theme.elevatedButtonTheme.style!;
    final outlined = theme.outlinedButtonTheme.style!;

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, HtbColors.bg0);
    expect(theme.colorScheme.primary, HtbColors.neonGreen);
    expect(theme.colorScheme.secondary, HtbColors.neonCyan);
    expect(theme.appBarTheme.backgroundColor, HtbColors.bg0);
    expect(theme.inputDecorationTheme.fillColor, HtbColors.bg2);
    expect(theme.cardTheme.color, HtbColors.glassFill);
    expect(
      elevated.backgroundColor?.resolve(<WidgetState>{}),
      HtbColors.neonGreen,
    );
    expect(
      elevated.foregroundColor?.resolve(<WidgetState>{}),
      HtbColors.textInverse,
    );
    expect(
      outlined.side?.resolve(<WidgetState>{})?.color,
      HtbColors.glassBorderDefault,
    );
  });

  Widget wrapWithTheme(
    Widget child, {
    Size size = const Size(1440, 1024),
  }) {
    return ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          theme: HtbTheme.dark(),
          home: child,
        ),
      ),
    );
  }

  testWidgets('login screen uses the shared brand artwork', (tester) async {
    await tester.pumpWidget(wrapWithTheme(const LoginScreen()));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to SecureWave'), findsOneWidget);
  });

  testWidgets('auth screens use the shared neon secondary accents',
      (tester) async {
    await tester.pumpWidget(wrapWithTheme(const LoginScreen()));
    await tester.pump();

    final loginButton = tester.widget<FilledButton>(
      find.byKey(AutomationKeys.loginSubmitButtonKey),
    );
    final loginLink = tester.widget<TextButton>(
      find.byKey(AutomationKeys.loginCreateAccountButtonKey),
    );

    expect(
      loginButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      HtbColors.neonCyan,
    );
    expect(
      loginLink.style?.foregroundColor?.resolve(<WidgetState>{}),
      HtbColors.neonCyan,
    );

    await tester.pumpWidget(wrapWithTheme(const RegisterScreen()));
    await tester.pump();

    final registerButton = tester.widget<FilledButton>(
      find.byKey(AutomationKeys.registerSubmitButtonKey),
    );
    final registerLink = tester.widget<TextButton>(
      find.byKey(AutomationKeys.registerBackToLoginButtonKey),
    );

    expect(
      registerButton.style?.backgroundColor?.resolve(<WidgetState>{}),
      HtbColors.neonCyan,
    );
    expect(
      registerLink.style?.foregroundColor?.resolve(<WidgetState>{}),
      HtbColors.neonCyan,
    );
  });

  testWidgets('desktop shell keeps the shared dark navigation surface',
      (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        AdaptiveShellScaffold(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(AutomationKeys.shellRootScaffoldKey), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);

    final hasNavigationSurface = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((decoratedBox) => decoratedBox.decoration)
        .whereType<BoxDecoration>()
        .any((decoration) => decoration.color == HtbColors.bg1);

    expect(hasNavigationSurface, isTrue);
  });
}
