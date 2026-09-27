import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'ui/theme.dart';

class SecureWaveApp extends StatefulWidget {
  const SecureWaveApp({super.key});

  @override
  State<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends State<SecureWaveApp> {
  static const _tokenKey = 'access_token';
  static const _storage = FlutterSecureStorage();

  late final ApiService _api = ApiService();
  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) {
      _api.setAccessToken(token);
      try {
        await _api.checkSession();
        _token = token;
      } on ApiException catch (error) {
        if (error.unauthorized) {
          await _storage.delete(key: _tokenKey);
        } else {
          _token = token;
        }
      } catch (_) {
        _token = token;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _acceptSession(String token) async {
    _api.setAccessToken(token);
    await _storage.write(key: _tokenKey, value: token);
    if (mounted) setState(() => _token = token);
  }

  Future<void> _clearSession() async {
    _api.setAccessToken(null);
    await _storage.delete(key: _tokenKey);
    if (mounted) setState(() => _token = null);
  }

  Future<void> _logout() => _clearSession();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _loading
          ? const _LoadingView()
          : _token == null
              ? _AuthView(onAuthenticated: _acceptSession)
              : _HomeView(
                  api: _api,
                  onLogout: _logout,
                  onSessionExpired: _clearSession,
                ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView({required this.onAuthenticated});

  final Future<void> Function(String token) onAuthenticated;

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _api = ApiService();
  bool _registering = true;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_registering) {
        await _api.register(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (mounted) {
          setState(() {
            _registering = false;
            _notice = 'Account created. Sign in to continue.';
          });
        }
      } else {
        final token = await _api.login(
          email: _email.text.trim(),
          password: _password.text,
        );
        _api.setAccessToken(token);
        try {
          await _api.checkSession();
        } finally {
          _api.setAccessToken(null);
        }
        await widget.onAuthenticated(token);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'SecureWave could not complete that request.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/icon.png',
                        width: 56,
                        height: 56,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SecureWave',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 28),
                    Text(_registering ? 'Create account' : 'Sign in',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 20),
                    const _FieldLabel('Email'),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        hintText: 'you@example.com',
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.contains('@') && email.contains('.')
                            ? null
                            : 'Enter a valid email address.';
                      },
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel('Password'),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: [
                        _registering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(
                        hintText: 'At least 8 characters',
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.length < 8) {
                          return 'Use at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 16),
                      const _FieldLabel('Confirm password'),
                      TextFormField(
                        controller: _confirmation,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Enter the password again',
                        ),
                        validator: (value) => value == _password.text
                            ? null
                            : 'Passwords do not match.',
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _notice!,
                        style: TextStyle(color: colors.primary),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_registering ? 'Create account' : 'Sign in'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _registering = !_registering;
                                _error = null;
                                _notice = null;
                              }),
                      child: Text(
                        _registering
                            ? 'Already have an account? Sign in'
                            : 'New to SecureWave? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );
}

class _HomeView extends StatefulWidget {
  const _HomeView({
    required this.api,
    required this.onLogout,
    required this.onSessionExpired,
  });

  final ApiService api;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSessionExpired;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  static const _storage = FlutterSecureStorage();
  static const _deviceNameKey = 'vpn_device_name';

  final _vpn = VpnService();
  late Future<void> _deviceNameReady;
  VpnStatus _status = VpnStatus.disconnected;
  String? _location;
  String? _error;
  String? _deviceName;
  bool _busy = false;
  bool _countersAvailable = false;
  int _downloadBytes = 0;
  int _uploadBytes = 0;
  int? _usageSessionId;
  int _usageSequence = 0;
  VpnTrafficStats? _previousStats;
  Timer? _usageTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreTunnel());
    _deviceNameReady = _loadDeviceName();
    unawaited(_deviceNameReady);
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceName() async {
    var name = await _storage.read(key: _deviceNameKey);
    if (name == null || name.isEmpty) {
      name = 'Linux-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      await _storage.write(key: _deviceNameKey, value: name);
    }
    _deviceName = name;
  }

  Future<void> _restoreTunnel() async {
    final status = await _vpn.refreshRuntimeStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _error = _vpn.statusError;
    });
    if (status == VpnStatus.connected) {
      await _vpn.refreshAvailability();
      _startUsagePolling();
    }
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = VpnStatus.connecting;
      _error = null;
      _location = null;
      _downloadBytes = 0;
      _uploadBytes = 0;
      _countersAvailable = false;
    });
    try {
      await _deviceNameReady;
      final name = _deviceName!;
      final profile = await widget.api.fetchWireGuardProfile(deviceName: name);
      await _vpn.connect(profile.config);
      if (!mounted) return;
      setState(() {
        _status = VpnStatus.connected;
        _location = profile.location;
      });
      try {
        await widget.api.notifyConnected(profile);
      } on ApiException catch (error) {
        if (error.unauthorized) {
          try {
            await _vpn.disconnect();
            if (mounted) setState(() => _status = VpnStatus.disconnected);
            await widget.onSessionExpired();
          } on VpnServiceException catch (disconnectError) {
            if (mounted) {
              setState(() {
                _status = VpnStatus.error;
                _error = disconnectError.message;
              });
            }
          }
          return;
        }
      } catch (_) {
        // The local helper is authoritative for tunnel state.
      }
      try {
        _usageSessionId = await widget.api.startUsageSession(profile);
      } catch (_) {
        _usageSessionId = null;
      }
      _startUsagePolling();
    } on ApiException catch (error) {
      if (error.unauthorized) {
        await widget.onSessionExpired();
        return;
      }
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = error.message;
        });
      }
    } on VpnServiceException catch (error) {
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = 'Could not connect the WireGuard tunnel.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _disconnect() async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _status = VpnStatus.disconnecting;
      _error = null;
    });
    _usageTimer?.cancel();
    _usageTimer = null;
    try {
      await _vpn.disconnect();
      try {
        await widget.api.notifyDisconnected();
      } catch (_) {
        // A local disconnect must complete even if the API is unavailable.
      }
      if (mounted) {
        setState(() {
          _status = VpnStatus.disconnected;
          _location = null;
          _downloadBytes = 0;
          _uploadBytes = 0;
          _countersAvailable = false;
          _previousStats = null;
        });
      }
      return true;
    } on VpnServiceException catch (error) {
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = error.message;
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = 'Could not disconnect the WireGuard tunnel.';
        });
      }
      return false;
    } finally {
      await _finishUsageSession();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishUsageSession() async {
    final sessionId = _usageSessionId;
    _usageSessionId = null;
    _usageSequence = 0;
    if (sessionId == null) return;
    try {
      await widget.api.finishUsageSession(sessionId);
    } catch (_) {
      // The tunnel is already handled locally; usage finalization is best effort.
    }
  }

  void _startUsagePolling() {
    _usageTimer?.cancel();
    _previousStats = null;
    unawaited(_pollUsage());
    _usageTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollUsage()),
    );
  }

  Future<void> _pollUsage() async {
    if (_polling || _status != VpnStatus.connected) return;
    _polling = true;
    try {
      final stats = await _vpn.getTrafficStats();
      if (!mounted) return;
      if (!stats.available) {
        setState(() => _countersAvailable = false);
        _previousStats = null;
        return;
      }
      final previous = _previousStats;
      _previousStats = stats;
      if (previous == null) {
        setState(() => _countersAvailable = true);
        return;
      }

      final received = stats.rxBytes >= previous.rxBytes
          ? stats.rxBytes - previous.rxBytes
          : 0;
      final sent = stats.txBytes >= previous.txBytes
          ? stats.txBytes - previous.txBytes
          : 0;
      setState(() {
        _countersAvailable = true;
        _downloadBytes += received;
        _uploadBytes += sent;
      });
      final sessionId = _usageSessionId;
      if (sessionId != null && (sent > 0 || received > 0)) {
        final sequence = ++_usageSequence;
        unawaited(
          widget.api
              .reportUsage(
                sessionId: sessionId,
                sequence: sequence,
                bytesSent: sent,
                bytesReceived: received,
              )
              .catchError((_) {}),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _countersAvailable = false);
    } finally {
      _polling = false;
    }
  }

  Future<void> _handleLogout() async {
    if (_status != VpnStatus.disconnected) {
      final disconnected = await _disconnect();
      if (!disconnected) return;
    }
    await widget.onLogout();
  }

  String _statusText() => switch (_status) {
        VpnStatus.disconnected => 'Disconnected',
        VpnStatus.connecting => 'Connecting',
        VpnStatus.connected => 'Connected',
        VpnStatus.disconnecting => 'Disconnecting',
        VpnStatus.error => 'Error',
      };

  Future<void> _toggleConnection() async {
    final canDisconnect = _status == VpnStatus.connected ||
        (_status == VpnStatus.error && _vpn.status == VpnStatus.error);
    if (canDisconnect) {
      await _disconnect();
    } else if (_status == VpnStatus.disconnected ||
        _status == VpnStatus.error) {
      await _connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == VpnStatus.connected;
    final canDisconnect = connected ||
        (_status == VpnStatus.error && _vpn.status == VpnStatus.error);
    final transitioning = _busy ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon.png', width: 28, height: 28),
            const SizedBox(width: 10),
            const Text('SecureWave'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: transitioning ? null : _handleLogout,
            child: const Text('Log out'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('WireGuard VPN',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(color: colors.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected ? Icons.check_circle : Icons.circle,
                              size: 18,
                              color: connected
                                  ? colors.primary
                                  : _status == VpnStatus.error
                                      ? colors.error
                                      : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _statusText(),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Text('WireGuard',
                                style: Theme.of(context).textTheme.labelLarge),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text('VPN location',
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 4),
                        Text(_location ?? 'Automatic',
                            style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: transitioning ? null : _toggleConnection,
                            icon: transitioning
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(canDisconnect
                                    ? Icons.pause
                                    : Icons.shield_outlined),
                            label:
                                Text(canDisconnect ? 'Disconnect' : 'Connect'),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Data used this session',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _UsageValue(
                          label: 'Download',
                          value: _countersAvailable
                              ? _formatBytes(_downloadBytes)
                              : 'Unavailable',
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _UsageValue(
                          label: 'Upload',
                          value: _countersAvailable
                              ? _formatBytes(_uploadBytes)
                              : 'Unavailable',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageValue extends StatelessWidget {
  const _UsageValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
