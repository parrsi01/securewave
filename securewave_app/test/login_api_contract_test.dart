import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/services/api_client.dart';

const _testConfig = AppConfig(
  apiBaseUrl: 'https://api.example.test',
  demoMode: false,
);

class _MemorySecureStorage extends SecureStorage {
  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<void> saveToken(String accessToken) async {}

  @override
  Future<void> clearToken() async {}

  @override
  Future<void> clearVpnRuntimeState() async {}
}

class _PendingLoginApiClient extends ApiClient {
  _PendingLoginApiClient(
    AuthSession session, {
    required this.started,
    required this.result,
  }) : super(_testConfig, session: session, dio: _rejectingDio());

  final Completer<void> started;
  final Completer<AuthTokens> result;

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) {
    started.complete();
    return result.future;
  }
}

void main() {
  testWidgets('login renders the preserved fields and autofill contract',
      (tester) async {
    _resetViewAfterTest(tester);
    await _pumpAuthentication(tester, size: const Size(390, 844));

    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const ValueKey('auth-email-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-password-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-confirm-field')), findsNothing);
    expect(
      find.byKey(const ValueKey('authentication-primary-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('authentication-mode-switch')),
      findsOneWidget,
    );

    final email = _editableText(tester, 'auth-email-field');
    final password = _editableText(tester, 'auth-password-field');
    expect(email.autofillHints, const [AutofillHints.email]);
    expect(email.textInputAction, TextInputAction.next);
    expect(password.autofillHints, const [AutofillHints.password]);
    expect(password.textInputAction, TextInputAction.done);
    expect(password.obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration renders and switches back to login',
      (tester) async {
    _resetViewAfterTest(tester);
    await _pumpAuthentication(tester);

    await tester.tap(
      find.byKey(const ValueKey('authentication-mode-switch')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byKey(const ValueKey('auth-confirm-field')), findsOneWidget);
    expect(
      _editableText(tester, 'auth-password-field').autofillHints,
      const [AutofillHints.newPassword],
    );

    await tester.tap(
      find.byKey(const ValueKey('authentication-mode-switch')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.byKey(const ValueKey('auth-confirm-field')), findsNothing);
  });

  testWidgets('password visibility control reveals and obscures input',
      (tester) async {
    _resetViewAfterTest(tester);
    await _pumpAuthentication(tester);

    EditableText passwordField() =>
        _editableText(tester, 'auth-password-field');

    expect(passwordField().obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('auth-password-visibility')),
    );
    await tester.pump();

    expect(passwordField().obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('login validates empty and malformed input', (tester) async {
    _resetViewAfterTest(tester);
    await _pumpAuthentication(tester);

    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pump();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'short',
    );
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pump();

    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registration enforces password policy and confirmation match',
      (tester) async {
    _resetViewAfterTest(tester);
    await _pumpAuthentication(tester);
    await tester.tap(
      find.byKey(const ValueKey('authentication-mode-switch')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'reviewer@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'short',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm-field')),
      'short',
    );
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'ExamplePass1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm-field')),
      'DifferentPass1',
    );
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy login disables fields, action, visibility, and mode switch',
      (tester) async {
    _resetViewAfterTest(tester);
    final requestStarted = Completer<void>();
    final result = Completer<AuthTokens>();
    await _pumpAuthentication(
      tester,
      clientBuilder: (session) => _PendingLoginApiClient(
        session,
        started: requestStarted,
        result: result,
      ),
    );

    await _enterLogin(tester);
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pump();
    await requestStarted.future;
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('authentication-primary-action')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('auth-email-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('auth-password-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('authentication-mode-switch')),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Signing in'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    result.completeError(StateError('Sign in was not completed.'));
    await tester.pumpAndSettle();
  });

  testWidgets('login preserves API contract and renders a safe mapped error',
      (tester) async {
    _resetViewAfterTest(tester);
    RequestOptions? captured;
    final dio = _dioWithInterceptor((options, handler) {
      captured = options;
      handler.reject(_apiFailure(options, 'Invalid email or password.'));
    });
    await _pumpAuthentication(tester, dio: dio);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      '  reviewer@example.test  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'ExamplePass1',
    );
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(captured?.path, '/auth/login');
    expect(captured?.data, {
      'email': 'reviewer@example.test',
      'password': 'ExamplePass1',
    });
    expect(find.text('Invalid email or password.'), findsOneWidget);

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');
    expect(renderedText, isNot(contains('ExamplePass1')));
    expect(renderedText, isNot(contains('access_token')));
    expect(renderedText, isNot(contains('Authorization')));
  });

  testWidgets('registration preserves API route and request schema',
      (tester) async {
    _resetViewAfterTest(tester);
    RequestOptions? captured;
    final dio = _dioWithInterceptor((options, handler) {
      captured = options;
      handler
          .reject(_apiFailure(options, 'Account creation was not completed.'));
    });
    await _pumpAuthentication(tester, dio: dio);
    await tester.tap(
      find.byKey(const ValueKey('authentication-mode-switch')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('auth-email-field')),
      'new-user@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'ExamplePass1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-confirm-field')),
      'ExamplePass1',
    );
    await tester.tap(
      find.byKey(const ValueKey('authentication-primary-action')),
    );
    await tester.pumpAndSettle();

    expect(captured?.path, '/auth/register');
    expect(captured?.data, {
      'email': 'new-user@example.test',
      'password': 'ExamplePass1',
    });
    expect(find.text('Account creation was not completed.'), findsOneWidget);
  });

  testWidgets('mobile and desktop authentication layouts do not overflow',
      (tester) async {
    _resetViewAfterTest(tester);

    for (final size in const [
      Size(390, 844),
      Size(760, 900),
      Size(1280, 800),
      Size(1440, 900),
    ]) {
      await _pumpAuthentication(tester, size: size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Login layout failed at ${size.width}x${size.height}',
      );
      expect(
        find.byKey(const ValueKey('desktop-auth-introduction')),
        size.width >= 900 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile-auth-brand')),
        size.width < 900 ? findsOneWidget : findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('authentication-mode-switch')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Registration layout failed at ${size.width}x${size.height}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

Future<void> _pumpAuthentication(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Dio? dio,
  ApiClient Function(AuthSession)? clientBuilder,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final storage = _MemorySecureStorage();
  final session = AuthSession(storage: storage);
  await session.ensureInitialized();
  final client = clientBuilder?.call(session) ??
      ApiClient(
        _testConfig,
        session: session,
        dio: dio ?? _rejectingDio(),
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((_) => _testConfig),
        secureStorageProvider.overrideWithValue(storage),
        authSessionProvider.overrideWith((_) => session),
        apiClientProvider.overrideWithValue(client),
      ],
      child: const SecureWaveApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterLogin(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('auth-email-field')),
    'reviewer@example.test',
  );
  await tester.enterText(
    find.byKey(const ValueKey('auth-password-field')),
    'ExamplePass1',
  );
}

Dio _rejectingDio() {
  return _dioWithInterceptor((options, handler) {
    handler.reject(_apiFailure(options, 'Unexpected authentication request.'));
  });
}

Dio _dioWithInterceptor(
  void Function(RequestOptions, RequestInterceptorHandler) onRequest,
) {
  final dio = Dio(BaseOptions(baseUrl: _testConfig.apiBaseUrl));
  dio.interceptors.add(InterceptorsWrapper(onRequest: onRequest));
  return dio;
}

DioException _apiFailure(RequestOptions options, String detail) {
  return DioException(
    requestOptions: options,
    response: Response<Map<String, dynamic>>(
      requestOptions: options,
      statusCode: 401,
      data: {'detail': detail},
    ),
    type: DioExceptionType.badResponse,
  );
}

void _resetViewAfterTest(WidgetTester tester) {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

EditableText _editableText(WidgetTester tester, String fieldKey) {
  return tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey(fieldKey)),
      matching: find.byType(EditableText),
    ),
  );
}
