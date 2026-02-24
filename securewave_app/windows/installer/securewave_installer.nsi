; SecureWave VPN - Windows Installer (NSIS scaffolding)
; Usage: makensis /DOUTPUT_FILE=SecureWaveVPN-<version>-setup.exe securewave_installer.nsi

!define VERSION_FILE "..\\..\\VERSION"
!define VERSION ""
!if /fileexists "${VERSION_FILE}"
  !searchparse /file "${VERSION_FILE}" "" VERSION
!endif

!ifndef VERSION
  !define VERSION "0.0.0"
!endif

!ifndef OUTPUT_FILE
  !define OUTPUT_FILE "SecureWaveVPN-${VERSION}-setup.exe"
!endif

!define APP_NAME "SecureWave VPN"
!define APP_EXECUTABLE "securewave_app.exe"
!define COMPANY_NAME "SecureWave"

OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES\${COMPANY_NAME}\${APP_NAME}"
RequestExecutionLevel admin

Page directory
Page instfiles

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "build\windows\x64\runner\Release\*"

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXECUTABLE}"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXECUTABLE}"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  RMDir /r "$INSTDIR"
SectionEnd
