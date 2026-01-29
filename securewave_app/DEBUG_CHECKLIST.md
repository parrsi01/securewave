# SecureWave iOS White Screen Debug Checklist

If you encounter a white screen or startup failure on iOS, follow this systematic debugging guide.

## Quick Diagnosis

### Symptom: White Screen (No UI Renders)

**LIKELY CAUSES:**
1. Boot initialization timeout (>10 seconds)
2. Unhandled exception in boot controller
3. Missing Flutter engine initialization
4. Router configuration error
5. iOS entitlements/code signing issue

---

## Debug Steps (In Order)

### Step 1: Check Flutter Logs

**Location:** Xcode Console or Terminal

```bash
# Run with verbose logging
flutter run -d ios --verbose

# Or attach to running app
flutter attach
```

**What to look for:**
- `Boot: start` - Confirms boot controller started
- `Boot: complete` - Confirms boot finished successfully
- `Boot: entering safe mode` - App started with degraded functionality
- Any ERROR or EXCEPTION messages

**Expected timeline:**
- Boot should complete in <3 seconds normally
- Timeout triggers at 10 seconds (safe mode)

---

### Step 2: Check Native iOS Logs

**Location:** Xcode → Window → Devices and Simulators → Select Device → Open Console

**What to look for:**
```
[SecureWave] Any crash reports
[Runner] Flutter engine initialization messages
PacketTunnelProvider errors (if VPN-related)
```

**Common issues:**
- "Failed to load Info.plist" → Clean build required
- "Code signing error" → Check signing team
- "Network Extension" errors → Check entitlements

---

### Step 3: Verify Build Configuration

Run the environment doctor:
```bash
cd securewave_app
./scripts/doctor_flutter_ios.sh
```

**Must pass:**
- ✓ Xcode and Command Line Tools installed
- ✓ Flutter doctor passes
- ✓ Generated.xcconfig exists
- ✓ CocoaPods installed and up to date
- ✓ Runner.xcworkspace (not .xcodeproj) is used

---

### Step 4: Inspect Boot State

Add temporary debug logging to `lib/features/bootstrap/boot_screen.dart`:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final boot = ref.watch(bootControllerProvider).state;
  print('DEBUG: Boot status = ${boot.status}, error = ${boot.errorMessage}');
  // ... rest of build method
}
```

**Expected output:**
```
DEBUG: Boot status = BootStatus.initializing, error = null
DEBUG: Boot status = BootStatus.ready, error = null
```

**If stuck on initializing:** Boot timeout is happening
**If status = failed:** Check error message in logs

---

### Step 5: Test Safe Mode

Force a boot failure to verify safe mode works:

1. Edit `lib/core/config/app_config.dart`
2. Make `load()` throw an exception temporarily:
   ```dart
   static Future<AppConfig> load() async {
     throw Exception('Test safe mode');
   }
   ```
3. Rebuild and run
4. **Expected:** App shows BootScreen with "Started in safe mode" message
5. **Verify:** UI still renders (proving safe mode works)
6. Revert the change

---

### Step 6: Clean Build

If logs show stale build artifacts or cache issues:

```bash
cd securewave_app
./scripts/run_ios_clean_build.sh
```

This script:
1. Runs environment checks
2. Cleans Flutter build cache
3. Removes iOS build artifacts
4. Reinstalls CocoaPods
5. Rebuilds from scratch

---

### Step 7: Check Router Configuration

Verify `lib/router.dart` has valid initial route:

```dart
initialLocation: '/boot',  // Must always be valid
```

**Test:** Comment out redirect logic temporarily:
```dart
redirect: (context, state) {
  // return null;  // Disable redirects for testing
  // ... original logic
}
```

If white screen disappears → Router redirect logic issue
If white screen persists → Boot initialization issue

---

### Step 8: Verify Native Bridge (iOS-Specific)

Check `ios/Runner/AppDelegate.swift` and `ios/PacketTunnel/`:

```swift
// AppDelegate should have:
@objc class AppDelegate: FlutterAppDelegate {
  override func application(...) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(...)
  }
}
```

**Common issues:**
- Missing `GeneratedPluginRegistrant` call
- Wrong workspace opened (must use .xcworkspace)
- Entitlements file not linked

---

## Log File Locations

### Flutter Logs
- **Console Output:** Real-time in terminal
- **System Logs:** `~/Library/Logs/DiagnosticReports/` (for crashes)

### iOS Device Logs
- **Xcode Console:** Xcode → Window → Devices and Simulators → Console
- **Device Logs:** Saved in Xcode organizer after each run

### SecureWave App Logs
- **In-app:** BootScreen shows live logs during startup
- **Structured logs:** All logs go through `AppLogger` (see `lib/core/logging/app_logger.dart`)

---

## Common Fixes

### Fix 1: Timeout During Boot

**Symptom:** Boot takes >10 seconds, triggers safe mode

**Solution:**
1. Check network connectivity (adblock list download may be slow)
2. Verify `.env` file has valid API URL
3. Increase timeout in `boot_controller.dart` (line ~66):
   ```dart
   Future.delayed(const Duration(seconds: 20), ...)  // Increase from 10s
   ```

### Fix 2: Missing Entitlements

**Symptom:** App crashes on launch with entitlements error

**Solution:**
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Runner target → Signing & Capabilities
3. Verify these capabilities:
   - Personal VPN
   - Network Extensions
   - App Groups (if using)
4. Verify entitlements file is linked

### Fix 3: CocoaPods Out of Sync

**Symptom:** Build fails with pod-related errors

**Solution:**
```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
```

### Fix 4: Flutter Cache Corruption

**Symptom:** Builds fail with cryptic errors

**Solution:**
```bash
flutter clean
flutter pub get
flutter pub cache repair
```

---

## Emergency Recovery

If nothing else works:

```bash
# 1. Nuclear clean
cd securewave_app
rm -rf build/ .dart_tool/ ios/Pods/ ios/build/ ios/Podfile.lock
flutter clean

# 2. Rebuild Flutter cache
flutter pub cache repair
flutter pub get

# 3. Rebuild iOS dependencies
cd ios && pod install && cd ..

# 4. Rebuild app
flutter build ios --debug

# 5. If still failing, check Xcode workspace
open ios/Runner.xcworkspace
# Then build directly in Xcode to see native errors
```

---

## Prevention

**To prevent white screen issues:**

1. **Always use Runner.xcworkspace** (never .xcodeproj)
2. **Run `flutter pub get`** after pulling code
3. **Run `pod install`** after changing iOS dependencies
4. **Test boot timeouts** on slow networks
5. **Monitor app logs** during development
6. **Use safe mode** as a fallback (already implemented)

---

## Support

If this checklist doesn't resolve the issue:

1. Capture full logs: `flutter run -v > debug.log 2>&1`
2. Capture Xcode console output
3. Run `./scripts/doctor_flutter_ios.sh` and save output
4. Share diagnostics with the team

---

**Last Updated:** 2026-01-29  
**Version:** 4.0.0
