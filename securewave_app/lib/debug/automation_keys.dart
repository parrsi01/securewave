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

  static const connectionRingButton = 'automation_connection_ring_button';
  static const diagnosticsTile = 'automation_settings_diagnostics_tile';
  static const accountSignOutButton = 'automation_account_sign_out_button';
  static const accountConfirmSignOutButton =
      'automation_account_confirm_sign_out_button';

  static String navDestination(String label) {
    final normalized = label.trim().toLowerCase().replaceAll(' ', '_');
    return 'automation_nav_$normalized';
  }

  static String serverTile(String serverId) {
    return 'automation_server_tile_$serverId';
  }

  static String diagnosticsResult(int index, String status) {
    return 'automation_diagnostics_result_${index}_$status';
  }
}
