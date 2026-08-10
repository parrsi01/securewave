import 'main.dart';
import 'core/config/app_config.dart';

/// Standalone deterministic demo build.
///
/// Run with:
/// `flutter run -d linux -t lib/main_demo.dart`
void main() => runSecureWaveApp(config: AppConfig.demoConfig);
