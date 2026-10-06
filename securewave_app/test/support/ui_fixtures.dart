import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securewave_app/services/vpn_service.dart';
import 'package:securewave_app/ui/auth_form.dart';
import 'package:securewave_app/ui/connection_view.dart';
import 'package:securewave_app/ui/theme.dart';

Future<void> loadFixtureFonts() async {
  for (final entry in [
    ('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf'),
    ('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf'),
    ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
  ]) {
    final loader = FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2));
    await loader.load();
  }
}

/// Fixture-based presentation only. These captures never call a service.
Widget fixtureHost(Widget child,
        {double scale = 1, bool reducedMotion = true}) =>
    MaterialApp(
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reducedMotion,
          ),
          child: child,
        );
      }),
    );

Widget homeFixture({
  VpnStatus status = VpnStatus.disconnected,
  bool? canDisconnect,
  String? error,
  bool available = true,
  String? download,
  String? upload,
  String? recordingNotice,
  String server = 'Fixture server label',
  VoidCallback? onToggle,
  VoidCallback? onLogout,
}) {
  final transitioning =
      status == VpnStatus.connecting || status == VpnStatus.disconnecting;
  final unavailable =
      status == VpnStatus.connecting ? 'Pending' : 'Unavailable';
  return ConnectionView(
    status: status,
    canDisconnect: canDisconnect ?? status == VpnStatus.connected,
    transitioning: transitioning,
    serverLabel: server,
    download: download ?? (available ? '0 B' : unavailable),
    upload: upload ?? (available ? '0 B' : unavailable),
    countersAvailable: available,
    error: error,
    recordingNotice: recordingNotice,
    onToggle: onToggle ?? () {},
    onLogout: onLogout ?? () {},
  );
}

/// Owns test-only controllers so repeated screenshot tests release resources.
class AuthFixture extends StatefulWidget {
  const AuthFixture({
    super.key,
    this.registering = false,
    this.busy = false,
    this.error,
    this.notice,
    this.validation = false,
    this.onSubmit,
    this.onSwitch,
  });
  final bool registering;
  final bool busy;
  final String? error;
  final String? notice;
  final bool validation;
  final VoidCallback? onSubmit;
  final VoidCallback? onSwitch;

  @override
  State<AuthFixture> createState() => _AuthFixtureState();
}

class _AuthFixtureState extends State<AuthFixture> {
  final _form = GlobalKey<FormState>();
  final _controllers = List.generate(3, (_) => TextEditingController());

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(int index, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTheme.fieldLabel),
          const SizedBox(height: 8),
          TextFormField(
            controller: _controllers[index],
            obscureText: index != 0,
            decoration: InputDecoration(
                hintText: index == 0
                    ? 'you@example.com'
                    : index == 1
                        ? 'At least 8 characters'
                        : 'Enter the password again'),
            autovalidateMode: widget.validation
                ? AutovalidateMode.always
                : AutovalidateMode.disabled,
            validator: (_) => widget.validation
                ? index == 0
                    ? 'Enter a valid email address.'
                    : index == 1
                        ? 'Use at least 8 characters.'
                        : 'Passwords do not match.'
                : null,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => AuthForm(
        formKey: _form,
        registering: widget.registering,
        busy: widget.busy,
        error: widget.error,
        notice: widget.notice,
        onSubmit: widget.onSubmit ?? () {},
        onSwitchMode: widget.onSwitch ?? () {},
        fields: [
          _field(0, 'Email'),
          const SizedBox(height: 16),
          _field(1, 'Password'),
          if (widget.registering) ...[
            const SizedBox(height: 8),
            Text('Use at least 8 characters.', style: AppTheme.caption),
            const SizedBox(height: 16),
            _field(2, 'Confirm password'),
          ],
        ],
      );
}

/// Standalone Linux presentation capture target. This is never imported by the
/// production entrypoint and never starts a service or tunnel.
/// Run the built preview with one state argument, e.g. `connected`.
void main(List<String> arguments) {
  final name = arguments.isEmpty ? 'disconnected' : arguments.first;
  final status = switch (name) {
    'connecting' => VpnStatus.connecting,
    'connected' => VpnStatus.connected,
    'disconnecting' => VpnStatus.disconnecting,
    'error' => VpnStatus.error,
    _ => VpnStatus.disconnected,
  };
  final Widget screen = switch (name) {
    'create-account' => const AuthFixture(registering: true),
    'sign-in' => const AuthFixture(),
    _ => homeFixture(
        status: status,
        server: 'Germany',
        available: status != VpnStatus.connecting,
        download: status == VpnStatus.connected ? '2.0 MB' : null,
        upload: status == VpnStatus.connected ? '512.0 KB' : null,
        error: status == VpnStatus.error
            ? 'The Linux WireGuard helper is unavailable.'
            : null,
      ),
  };
  runApp(fixtureHost(
    Banner(
      message: 'VISUAL FIXTURE',
      location: BannerLocation.topEnd,
      color: AppTheme.surfaceInteractive,
      textStyle: AppTheme.type(11, 500, 1.2),
      child: screen,
    ),
    reducedMotion: false,
  ));
}
