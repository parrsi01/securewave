import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/account_usage.dart';
import 'ui/theme.dart';
import 'ui/auth_form.dart';
import 'ui/connection_view.dart';
import 'ui/monthly_usage.dart';
import 'ui/settings_view.dart';

class SecureWaveApp extends StatefulWidget {
  const SecureWaveApp({super.key, this.api});

  final ApiService? api;

  @override
  State<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends State<SecureWaveApp> {
  static const _tokenKey = 'access_token';
  static const _storage = FlutterSecureStorage();

  late final ApiService _api = widget.api ?? ApiService();
  String? _token;
  bool _loading = true;
  bool _signInAfterLogout = false;
  String? _authNotice;

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
          _api.setAccessToken(null);
          await _storage.delete(key: _tokenKey);
          _signInAfterLogout = true;
          _authNotice = 'Your session has expired. Sign in to continue.';
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
    if (mounted) {
      setState(() {
        _token = token;
        _authNotice = null;
      });
    }
  }

  Future<void> _clearSession({bool signIn = false, String? notice}) async {
    _api.setAccessToken(null);
    await _storage.delete(key: _tokenKey);
    if (mounted) {
      setState(() {
        _token = null;
        _authNotice = notice;
        if (signIn) _signInAfterLogout = true;
      });
    }
  }

  Future<void> _logout() => _clearSession(signIn: true);

  Future<void> _expireSession() => _clearSession(
        signIn: true,
        notice: 'Your session has expired. Sign in to continue.',
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _loading
          ? const _LoadingView()
          : _token == null
              ? _AuthView(
                  onAuthenticated: _acceptSession,
                  initiallyRegistering: !_signInAfterLogout,
                  initialNotice: _authNotice,
                )
              : _HomeView(
                  api: _api,
                  onLogout: _logout,
                  onSessionExpired: _expireSession,
                ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const BootView();
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView({
    required this.onAuthenticated,
    required this.initiallyRegistering,
    this.initialNotice,
  });

  final Future<void> Function(String token) onAuthenticated;
  final bool initiallyRegistering;
  final String? initialNotice;

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
  void initState() {
    super.initState();
    _registering = widget.initiallyRegistering;
    _notice = widget.initialNotice;
  }

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
    return AuthForm(
      formKey: _formKey,
      registering: _registering,
      busy: _busy,
      error: _error,
      notice: _notice,
      onSubmit: _submit,
      onSwitchMode: () => setState(() {
        _registering = !_registering;
        _error = null;
        _notice = null;
      }),
      fields: [
        const _FieldLabel('Email'),
        Semantics(
            label: 'Email',
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
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
            )),
        const SizedBox(height: 16),
        const _FieldLabel('Password'),
        Semantics(
            label: 'Password',
            child: TextFormField(
              controller: _password,
              textInputAction:
                  _registering ? TextInputAction.next : TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_registering && !_busy) _submit();
              },
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
            )),
        if (_registering) ...[
          const SizedBox(height: 8),
          Text('Use at least 8 characters.', style: AppTheme.caption)
        ],
        if (_registering) ...[
          const SizedBox(height: 16),
          const _FieldLabel('Confirm password'),
          Semantics(
              label: 'Confirm password',
              child: TextFormField(
                controller: _confirmation,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_busy) _submit();
                },
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Enter the password again',
                ),
                validator: (value) =>
                    value == _password.text ? null : 'Passwords do not match.',
              )),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ExcludeSemantics(child: Text(text, style: AppTheme.fieldLabel)),
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
  static const _baselineKey = 'vpn_baseline_public_ip';
  static const _wireGuardPrivateKeyPrefix = 'wireguard_private_key_user_';

  final _vpn = VpnService();
  VpnStatus _status = VpnStatus.disconnected;
  String _location = 'Germany';
  String? _error;
  String? _baselinePublicIp;
  bool _tunnelMayBeActive = false;
  bool _busy = false;
  bool _countersAvailable = true;
  int _downloadBytes = 0;
  int _uploadBytes = 0;
  String? _recordingNotice;
  Timer? _usageTimer;
  bool _polling = false;
  late final _accountUsage = AccountUsageStore(widget.api);
  late final Future<void> _accountReady;
  Timer? _accountTimer;
  int? _usageSessionId;
  bool _showSettings = false;
  bool _quotaDisconnecting = false;

  @override
  void initState() {
    super.initState();
    _accountUsage.addListener(_accountChanged);
    _accountReady = _accountUsage.initialize();
    _accountTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final summary = _accountUsage.summary;
      if (_status == VpnStatus.connected ||
          _accountUsage.pendingBytes > 0 ||
          (summary != null &&
              !DateTime.now().toUtc().isBefore(summary.periodEnd))) {
        unawaited(_accountUsage.refresh());
      }
    });
    unawaited(_restoreTunnel());
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    _accountTimer?.cancel();
    _accountUsage.removeListener(_accountChanged);
    _accountUsage.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    final saved = _accountUsage.summary?.lastSession;
    setState(() {
      if (_status != VpnStatus.connected && !_busy && saved != null) {
        if (_usageSessionId != saved.id) {
          _downloadBytes = saved.received;
          _uploadBytes = saved.sent;
        } else {
          if (saved.received > _downloadBytes) _downloadBytes = saved.received;
          if (saved.sent > _uploadBytes) _uploadBytes = saved.sent;
        }
        _countersAvailable = true;
      }
    });
    if (_accountUsage.limitReached &&
        _status == VpnStatus.connected &&
        !_busy &&
        !_quotaDisconnecting) {
      _quotaDisconnecting = true;
      unawaited(_disconnect().whenComplete(() => _quotaDisconnecting = false));
    }
  }

  Future<void> _restoreTunnel() async {
    final status = await _vpn.refreshRuntimeStatus();
    if (!mounted) return;
    if (status != VpnStatus.connected) {
      _tunnelMayBeActive = status == VpnStatus.error;
      if (status == VpnStatus.disconnected) {
        await _storage.delete(key: _baselineKey);
      }
      setState(() {
        _status = status;
        _error = _vpn.statusError;
      });
      return;
    }

    _tunnelMayBeActive = true;
    final baseline = await _storage.read(key: _baselineKey);
    if (baseline == null || baseline.isEmpty) {
      await _disconnectUnverifiedTunnel();
      return;
    }
    try {
      final recording = await _vpn.usageRecordingStatus();
      if (recording['owned'] != true) {
        _tunnelMayBeActive = false;
        setState(() {
          _status = VpnStatus.error;
          _error = 'The VPN is controlled by another SecureWave window.';
        });
        return;
      }
      _baselinePublicIp = baseline;
      await _vpn.refreshAvailability();
      final keyPair = await _loadOrCreateWireGuardKeyPair();
      final parameters = await widget.api.fetchWireGuardConfig(
        publicKey: keyPair.publicKey,
      );
      await _vpn.verifyConnection(
        previousPublicIp: baseline,
        expectedServerPublicKey: parameters.serverPublicKey,
      );
      if (!mounted) return;
      setState(() {
        _status = VpnStatus.connected;
        _location = 'Germany';
        _error = null;
      });
      _startUsagePolling();
    } catch (_) {
      await _disconnectUnverifiedTunnel();
    }
  }

  Future<void> _disconnectUnverifiedTunnel() async {
    String? error;
    try {
      await _vpn.disconnect();
      await _vpn.verifyDisconnected();
      _tunnelMayBeActive = false;
    } on VpnServiceException catch (disconnectError) {
      _tunnelMayBeActive = true;
      error = disconnectError.message;
    } catch (_) {
      _tunnelMayBeActive = true;
      error = 'Could not safely restore the normal internet connection.';
    }
    await _storage.delete(key: _baselineKey);
    _baselinePublicIp = null;
    if (mounted) {
      setState(() {
        _status = error == null ? VpnStatus.disconnected : VpnStatus.error;
        _error = error ?? 'The previous VPN session could not be verified.';
      });
    }
  }

  Future<void> _connect() async {
    if (_busy) return;
    await _accountReady;
    await _accountUsage.refresh();
    if (!mounted || _busy) return;
    if (_accountUsage.limitReached) {
      setState(() => _error =
          'Your 5 GB monthly allowance is used. It renews next month (UTC).');
      return;
    }
    var tunnelAttempted = false;
    UsageSession? usageSession;
    setState(() {
      _busy = true;
      _status = VpnStatus.connecting;
      _error = null;
      _downloadBytes = 0;
      _uploadBytes = 0;
      _countersAvailable = false;
    });
    try {
      if (await _vpn.refreshRuntimeStatus() == VpnStatus.connected) {
        throw const VpnServiceException(
            'Another SecureWave window already controls the VPN.');
      }
      final baseline = await _vpn.getPublicIp();
      _baselinePublicIp = baseline;
      await _storage.write(key: _baselineKey, value: baseline);
      final keyPair = await _loadOrCreateWireGuardKeyPair();
      final parameters = await widget.api.fetchWireGuardConfig(
        publicKey: keyPair.publicKey,
      );
      if (!await _vpn.refreshAvailability()) {
        throw VpnServiceException(
          _vpn.statusError ?? 'The Linux WireGuard helper is unavailable.',
        );
      }
      usageSession = await widget.api.startUsage(parameters);
      _usageSessionId = usageSession.id;
      await _accountUsage.observe(usageSession.id, 0, 0);
      await _accountUsage.refresh();
      tunnelAttempted = true;
      _tunnelMayBeActive = true;
      await _vpn.connect(
        parameters.toClientConfig(keyPair.privateKey),
        session: usageSession,
        expectedPeer: parameters.serverPublicKey,
      );
      await _vpn.verifyConnection(
        previousPublicIp: baseline,
        expectedServerPublicKey: parameters.serverPublicKey,
      );
      await _vpn.confirmUsage();
      if (!mounted) return;
      setState(() {
        _status = VpnStatus.connected;
        _location = parameters.location;
      });
      _startUsagePolling();
    } on ApiException catch (error) {
      final cleanupError = await _cleanupFailedConnection(tunnelAttempted);
      if (error.unauthorized) {
        await widget.onSessionExpired();
        return;
      }
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = cleanupError ?? error.message;
        });
      }
    } on VpnServiceException catch (error) {
      final cleanupError = await _cleanupFailedConnection(tunnelAttempted);
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = cleanupError ?? error.message;
        });
      }
    } catch (_) {
      final cleanupError = await _cleanupFailedConnection(tunnelAttempted);
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = cleanupError ?? 'Could not connect the WireGuard tunnel.';
        });
      }
    } finally {
      if (usageSession != null && _status != VpnStatus.connected) {
        try {
          await widget.api.finishFailedUsage(usageSession);
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<WireGuardKeyPair> _loadOrCreateWireGuardKeyPair() async {
    final userId = await widget.api.currentUserId();
    final storageKey = '$_wireGuardPrivateKeyPrefix$userId';
    final storedPrivateKey = await _storage.read(key: storageKey);
    if (storedPrivateKey != null && storedPrivateKey.isNotEmpty) {
      return _vpn.keyPairFromPrivateKey(storedPrivateKey);
    }

    final keyPair = await _vpn.generateKeyPair();
    await _storage.write(key: storageKey, value: keyPair.privateKey);
    return keyPair;
  }

  Future<String?> _cleanupFailedConnection(bool tunnelAttempted) async {
    String? cleanupError;
    if (tunnelAttempted) {
      try {
        await _vpn.disconnect();
        await _vpn.verifyDisconnected(expectedPublicIp: _baselinePublicIp);
        _tunnelMayBeActive = false;
      } on VpnServiceException catch (error) {
        _tunnelMayBeActive = true;
        cleanupError = error.message;
      } catch (_) {
        _tunnelMayBeActive = true;
        cleanupError =
            'Could not safely restore the normal internet connection.';
      }
    }
    if (_baselinePublicIp != null) await _storage.delete(key: _baselineKey);
    _baselinePublicIp = null;
    return cleanupError;
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
      // Bind the local sample to this window while it owns the active tunnel.
      // Final tail bytes come from the account-scoped server ledger; the native
      // helper's disconnected "latest" record can belong to another account.
      if (_usageSessionId != null) {
        try {
          final finalUsage = await _vpn.usageRecordingStatus();
          if (finalUsage['owned'] == true) {
            _downloadBytes = (finalUsage['bytes_received'] as num?)?.toInt() ??
                _downloadBytes;
            _uploadBytes =
                (finalUsage['bytes_sent'] as num?)?.toInt() ?? _uploadBytes;
          }
        } catch (_) {}
      }
      await _vpn.disconnect();
      if (_usageSessionId != null) {
        await _accountUsage.observe(
            _usageSessionId!, _uploadBytes, _downloadBytes,
            finalized: true);
      }
      await _vpn.verifyDisconnected(expectedPublicIp: _baselinePublicIp);
      await _storage.delete(key: _baselineKey);
      _baselinePublicIp = null;
      _tunnelMayBeActive = false;
      if (mounted) {
        setState(() {
          _status = VpnStatus.disconnected;
          _countersAvailable = true;
          _recordingNotice = 'Last session saved on this device.';
        });
      }
      await _accountUsage.refresh();
      unawaited(_refreshFinalUsage());
      return true;
    } on VpnServiceException catch (error) {
      _tunnelMayBeActive = true;
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = error.message;
        });
      }
      return false;
    } catch (_) {
      _tunnelMayBeActive = true;
      if (mounted) {
        setState(() {
          _status = VpnStatus.error;
          _error = 'Could not disconnect the WireGuard tunnel.';
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshFinalUsage() async {
    for (final seconds in [2, 3, 5]) {
      await Future<void>.delayed(Duration(seconds: seconds));
      if (!mounted) return;
      await _accountUsage.refresh();
      if (_accountUsage.pendingBytes == 0) return;
    }
  }

  void _startUsagePolling() {
    _usageTimer?.cancel();
    _recordingNotice = null;
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
      final runtime = await _vpn.refreshRuntimeStatus();
      if (!mounted || _status != VpnStatus.connected) return;
      if (runtime != VpnStatus.connected) {
        final recording = await _vpn.usageRecordingStatus();
        if (!mounted || _status != VpnStatus.connected) return;
        _usageTimer?.cancel();
        setState(() {
          _status = runtime;
          _tunnelMayBeActive = runtime == VpnStatus.error;
          _recordingNotice = recording['gap'] == true
              ? 'The tunnel stopped; usage contains a measurement gap.'
              : 'The tunnel stopped; final measured usage is being saved.';
        });
        await _accountUsage.refresh();
        return;
      }
      final stats = await _vpn.getTrafficStats();
      if (!mounted || _status != VpnStatus.connected) return;
      if (!stats.available) {
        setState(() => _countersAvailable = false);
        _recordingNotice = null;
        return;
      }
      final recording = await _vpn.usageRecordingStatus();
      if (!mounted || _status != VpnStatus.connected) return;
      if (recording['owned'] != true) {
        throw const VpnServiceException('The usage recorder is unavailable.');
      }
      setState(() {
        _countersAvailable = true;
        _downloadBytes = (recording['bytes_received'] as num?)?.toInt() ?? 0;
        _uploadBytes = (recording['bytes_sent'] as num?)?.toInt() ?? 0;
        _recordingNotice = recording['gap'] == true
            ? 'Usage recording contains a measurement gap.'
            : (recording['pending'] as num? ?? 0) > 0
                ? 'Measured usage is awaiting server confirmation.'
                : null;
      });
      if (_usageSessionId != null) {
        await _accountUsage.observe(
            _usageSessionId!, _uploadBytes, _downloadBytes);
      }
    } catch (_) {
      if (mounted && _status == VpnStatus.connected) {
        setState(() {
          _countersAvailable = false;
          _recordingNotice = 'Usage recording status is unavailable.';
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _handleLogout() async {
    if (_tunnelMayBeActive) {
      final disconnected = await _disconnect();
      if (!disconnected) return;
    }
    await widget.onLogout();
  }

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
    final unavailable =
        _status == VpnStatus.connecting ? 'Pending' : 'Unavailable';
    if (_showSettings) {
      return SettingsView(
        store: _accountUsage,
        location: _location,
        connectionStatus: switch (_status) {
          VpnStatus.connected => 'Connected',
          VpnStatus.disconnected => 'Disconnected',
          VpnStatus.connecting => 'Connecting',
          VpnStatus.disconnecting => 'Disconnecting',
          VpnStatus.error => 'Connection error',
        },
        onBack: () => setState(() => _showSettings = false),
        onRefresh: () => unawaited(_accountUsage.refresh()),
      );
    }
    return ConnectionView(
      status: _status,
      canDisconnect: canDisconnect,
      transitioning: transitioning,
      serverLabel: _location,
      error: _error,
      recordingNotice: _recordingNotice,
      countersAvailable: _countersAvailable,
      download: _countersAvailable ? _formatBytes(_downloadBytes) : unavailable,
      upload: _countersAvailable ? _formatBytes(_uploadBytes) : unavailable,
      onToggle: _toggleConnection,
      onLogout: _handleLogout,
      onSettings: () => setState(() => _showSettings = true),
      sessionLabel: connected ? 'Session transfer' : 'Last session transfer',
      monthlyUsage: MonthlyUsageView(
          compact: true,
          store: _accountUsage,
          onRefresh: () => unawaited(_accountUsage.refresh())),
    );
  }
}

String _formatBytes(int bytes) {
  return formatDataBytes(bytes);
}
