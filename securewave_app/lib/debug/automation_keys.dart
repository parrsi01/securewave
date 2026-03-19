import 'package:flutter/widgets.dart';

class AutomationKeys {
  AutomationKeys._();

  static const loginEmailField = 'automation_login_email_field';
  static const loginPasswordField = 'automation_login_password_field';
  static const loginSubmitButton = 'automation_login_submit_button';
  static const loginCreateAccountButton =
      'automation_login_create_account_button';

  static const registerEmailField = 'automation_register_email_field';
  static const registerPasswordField = 'automation_register_password_field';
  static const registerConfirmField = 'automation_register_confirm_field';
  static const registerSubmitButton = 'automation_register_submit_button';
  static const registerBackToLoginButton =
      'automation_register_back_to_login_button';

  static const shellRootScaffold = 'automation_shell_root_scaffold';
  static const settingsScreen = 'automation_settings_screen';
  static const navHome = 'automation_nav_home';
  static const navServers = 'automation_nav_servers';
  static const navConnection = 'automation_nav_connection';
  static const navSettings = 'automation_nav_settings';
  static const navAccount = 'automation_nav_account';
  static const connectionRingButton = 'automation_connection_ring_button';
  static const connectionStateDisconnected =
      'automation_connection_state_disconnected';
  static const connectionStateConnecting =
      'automation_connection_state_connecting';
  static const connectionStateReconnecting =
      'automation_connection_state_reconnecting';
  static const connectionStateConnected =
      'automation_connection_state_connected';
  static const connectionStateDisconnecting =
      'automation_connection_state_disconnecting';
  static const connectionStateError = 'automation_connection_state_error';
  static const shellConnectionStateDisconnected =
      'automation_shell_connection_state_disconnected';
  static const shellConnectionStateConnecting =
      'automation_shell_connection_state_connecting';
  static const shellConnectionStateReconnecting =
      'automation_shell_connection_state_reconnecting';
  static const shellConnectionStateConnected =
      'automation_shell_connection_state_connected';
  static const shellConnectionStateDisconnecting =
      'automation_shell_connection_state_disconnecting';
  static const shellConnectionStateError =
      'automation_shell_connection_state_error';
  static const diagnosticsTile = 'automation_settings_diagnostics_tile';
  static const diagnosticsRootScroll = 'automation_diagnostics_root_scroll';
  static const accountScreen = 'automation_account_screen';
  static const accountSignOutButton = 'automation_account_sign_out_button';
  static const accountConfirmSignOutButton =
      'automation_account_confirm_sign_out_button';

  static const ValueKey<String> loginEmailFieldKey =
      ValueKey<String>(loginEmailField);
  static const ValueKey<String> loginPasswordFieldKey =
      ValueKey<String>(loginPasswordField);
  static const ValueKey<String> loginSubmitButtonKey =
      ValueKey<String>(loginSubmitButton);
  static const ValueKey<String> loginCreateAccountButtonKey =
      ValueKey<String>(loginCreateAccountButton);

  static const ValueKey<String> registerEmailFieldKey =
      ValueKey<String>(registerEmailField);
  static const ValueKey<String> registerPasswordFieldKey =
      ValueKey<String>(registerPasswordField);
  static const ValueKey<String> registerConfirmFieldKey =
      ValueKey<String>(registerConfirmField);
  static const ValueKey<String> registerSubmitButtonKey =
      ValueKey<String>(registerSubmitButton);
  static const ValueKey<String> registerBackToLoginButtonKey =
      ValueKey<String>(registerBackToLoginButton);

  static const ValueKey<String> shellRootScaffoldKey =
      ValueKey<String>(shellRootScaffold);
  static const ValueKey<String> settingsScreenKey =
      ValueKey<String>(settingsScreen);
  static const ValueKey<String> connectionRingButtonKey =
      ValueKey<String>(connectionRingButton);
  static const ValueKey<String> diagnosticsTileKey =
      ValueKey<String>(diagnosticsTile);
  static const ValueKey<String> diagnosticsRootScrollKey =
      ValueKey<String>(diagnosticsRootScroll);
  static const ValueKey<String> accountScreenKey =
      ValueKey<String>(accountScreen);
  static const ValueKey<String> accountSignOutButtonKey =
      ValueKey<String>(accountSignOutButton);
  static const ValueKey<String> accountConfirmSignOutButtonKey =
      ValueKey<String>(accountConfirmSignOutButton);

  static String navDestination(String label) {
    switch (_normalizeNavLabel(label)) {
      case 'home':
        return navHome;
      case 'servers':
      case 'locations':
        return navServers;
      case 'connection':
      case 'connect':
        return navConnection;
      case 'settings':
        return navSettings;
      case 'account':
      case 'profile':
        return navAccount;
      default:
        final normalized = label.trim().toLowerCase().replaceAll(' ', '_');
        return 'automation_nav_$normalized';
    }
  }

  static String serverTile(String serverId) {
    return 'automation_server_tile_$serverId';
  }

  static ValueKey<String> navDestinationKey(String label) {
    return ValueKey<String>(navDestination(label));
  }

  static ValueKey<String> serverTileKey(String serverId) {
    return ValueKey<String>(serverTile(serverId));
  }

  static String connectionState(String state) {
    return 'automation_connection_state_${_normalizeNavLabel(state)}';
  }

  static String shellConnectionState(String state) {
    return 'automation_shell_connection_state_${_normalizeNavLabel(state)}';
  }

  static ValueKey<String> connectionStateKey(String state) {
    return ValueKey<String>(connectionState(state));
  }

  static ValueKey<String> shellConnectionStateKey(String state) {
    return ValueKey<String>(shellConnectionState(state));
  }

  static String diagnosticsResult(int index, String status) {
    return 'automation_diagnostics_result_${index}_$status';
  }

  static String _normalizeNavLabel(String label) {
    return label.trim().toLowerCase().replaceAll(' ', '_');
  }
}
