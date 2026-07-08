enum LinuxPackageMode {
  debianPackage,
  portableArchive,
  unknown,
}

class LinuxRuntimeSetup {
  const LinuxRuntimeSetup._();

  static const String packageKindDefine = String.fromEnvironment(
    'SECUREWAVE_PACKAGE_KIND',
    defaultValue: 'portable',
  );

  static LinuxPackageMode currentPackageMode() {
    return packageModeFromString(packageKindDefine);
  }

  static LinuxPackageMode packageModeFromString(String value) {
    switch (value.trim().toLowerCase()) {
      case 'deb':
      case 'debian':
      case 'debian-package':
        return LinuxPackageMode.debianPackage;
      case 'portable':
      case 'archive':
      case 'tar':
      case 'zip':
      case 'appimage':
        return LinuxPackageMode.portableArchive;
      default:
        return LinuxPackageMode.unknown;
    }
  }

  static String packageLabel(LinuxPackageMode mode) {
    switch (mode) {
      case LinuxPackageMode.debianPackage:
        return 'Linux .deb';
      case LinuxPackageMode.portableArchive:
        return 'Linux portable';
      case LinuxPackageMode.unknown:
        return 'Linux package unknown';
    }
  }

  static String guidanceFor(LinuxPackageMode mode) {
    switch (mode) {
      case LinuxPackageMode.debianPackage:
        return 'Full Linux routing requires the privileged helper installed by '
            'the .deb package. Admin authorization belongs at install time; '
            'connect and disconnect should not prompt after the helper is '
            'installed and verified.';
      case LinuxPackageMode.portableArchive:
        return 'Portable Linux builds launch the app UI only. VPN routing is '
            'not claimable from archive extraction unless the same privileged '
            'helper and host VPN tools have been installed separately.';
      case LinuxPackageMode.unknown:
        return 'Linux package type is unknown. Treat VPN routing as unavailable '
            'until the .deb helper install or an equivalent privileged setup is '
            'verified.';
    }
  }

  static String missingHelperGuidance() {
    return 'Linux native VPN is unavailable until the privileged helper and '
        'required VPN tools are installed. Use the .deb install path for the '
        'no-connect-prompt model, then verify helper status before connecting.';
  }
}
