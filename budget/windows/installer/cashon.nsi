; Cashon NSIS Installer Script (Windows x64)
!include "MUI2.nsh"
!include "x64.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "1.0.0"
!endif

!define APP_NAME "Cashon"
!define APP_PUBLISHER "Vignesh Balaji"
!define APP_URL "https://github.com/vicky31-coder/Cashon"
!define APP_EXE "budget.exe"
!define UNINSTALL_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "..\..\dist\Cashon-${APP_VERSION}-Windows-Setup.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "Software\${APP_NAME}" "InstallDir"
RequestExecutionLevel admin
Unicode True
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
!define MUI_ICON "..\runner\resources\app_icon.ico"
!define MUI_UNICON "..\runner\resources\app_icon.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Cashon" SecMain
  SetShellVarContext all
  SetOutPath "$INSTDIR"

  File /r "..\..\build\windows\x64\runner\Release\*.*"

  WriteRegStr HKLM "Software\${APP_NAME}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "URLInfoAbout" "${APP_URL}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${UNINSTALL_REG_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_REG_KEY}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  WriteUninstaller "$INSTDIR\Uninstall.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${UNINSTALL_REG_KEY}"
  DeleteRegKey HKLM "Software\${APP_NAME}"
SectionEnd
