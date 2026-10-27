Unicode true
!include "config.nsh"
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"
!include "x64.nsh"
!include "Win\COM.nsh"
!include "Win\Propkey.nsh"

Name "${APP_NAME}"
OutFile "${INSTALLER_PATH}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_ID}" "InstallLocation"
RequestExecutionLevel user
ManifestSupportedOS all
SetCompressor /SOLID lzma
SetOverwrite try
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=1033 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=1033 "FileDescription" "${APP_DESCRIPTION} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "${APP_PUBLISHER}"

!define MUI_ABORTWARNING
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"
Var UpdateMode
Var UpgradeMode
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipUpdatePage
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipUpdatePage
!insertmacro MUI_PAGE_LICENSE "${PAYLOAD_DIR}\LICENSE.txt"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipUpdatePage
!insertmacro MUI_PAGE_FINISH
!define MUI_UNCONFIRMPAGE_TEXT_TOP "Uninstalling ${APP_NAME} also permanently deletes its settings, listening statistics, downloads and logs."
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"

Function SkipUpdatePage
  ${If} $UpdateMode == 1
    Abort
  ${EndIf}
FunctionEnd

Function WaitForUpdateShutdown
  # WinSparkle launches the verified installer before requesting graceful app shutdown.
  # Wait for the executable lock without killing playback or deleting any files.
  StrCpy $R2 0
  update_wait:
    ${IfNot} ${FileExists} "$INSTDIR\${APP_EXE}"
      Return
    ${EndIf}
    System::Call 'kernel32::CreateFileW(w "$INSTDIR\${APP_EXE}", i 0x40000000, i 0, p 0, i 3, i 0, p 0) p.r0'
    ${If} $0 != -1
      System::Call 'kernel32::CloseHandle(p r0)'
      Return
    ${EndIf}
    IntOp $R2 $R2 + 1
    ${If} $R2 >= 600
      MessageBox MB_OK|MB_ICONSTOP "Phonolite is still closing. Close it and try the update again." /SD IDOK
      SetErrorLevel 1
      Quit
    ${EndIf}
    Sleep 100
    Goto update_wait
FunctionEnd

!macro EnsureAppClosed
  # Opening for write without sharing detects a running executable without modifying it.
  ${If} ${FileExists} "$INSTDIR\${APP_EXE}"
    System::Call 'kernel32::CreateFileW(w "$INSTDIR\${APP_EXE}", i 0x40000000, i 0, p 0, i 3, i 0, p 0) p.r0'
    ${If} $0 == -1
      MessageBox MB_OK|MB_ICONSTOP "Close ${APP_NAME} before installing or uninstalling." /SD IDOK
      SetErrorLevel 1
      Quit
    ${EndIf}
    System::Call 'kernel32::CloseHandle(p r0)'
  ${EndIf}
!macroend

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} requires 64-bit Windows." /SD IDOK
    SetErrorLevel 1
    Quit
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
  ${OrIfNot} ${AtLeastBuild} ${MIN_WINDOWS_BUILD}
    MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} requires Windows ${MIN_WINDOWS_VERSION} or later." /SD IDOK
    SetErrorLevel 1
    Quit
  ${EndIf}
  SetRegView 64
  SetShellVarContext current
  StrCpy $UpdateMode 0
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/UPDATE" $R1
  ${IfNot} ${Errors}
    StrCpy $UpdateMode 1
    SetAutoClose true
    Call WaitForUpdateShutdown
  ${EndIf}
  !insertmacro EnsureAppClosed
FunctionEnd

Function .onInstSuccess
  ${If} $UpdateMode == 1
    Exec '"$INSTDIR\${APP_EXE}"'
  ${EndIf}
FunctionEnd

# Stamp the same AUMID used by the native process into the installed shortcut.
# These are bundled NSIS COM helpers; no external plug-in or app is executed.
Function SetShortcutIdentity
  Push $0
  Push $1
  Push $2
  Push $3
  Push $4
  Push $5
  Push $6
  StrCpy $0 0
  StrCpy $1 0
  StrCpy $2 0
  StrCpy $3 0
  StrCpy $4 0
  StrCpy $6 0
  !insertmacro ComHlpr_CreateInProcInstance ${CLSID_ShellLink} ${IID_IShellLink} r0 .r5
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  ${IUnknown::QueryInterface} $0 '("${IID_IPersistFile}",.r1).r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  ${IPersistFile::Load} $1 '("$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk",${STGM_READWRITE}).r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  ${IUnknown::QueryInterface} $0 '("${IID_IPropertyStore}",.r2).r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  System::Call 'shlwapi::SHStrDupW(w "${APP_ID}", *p.r6)i.r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  System::Call '*${SYSSTRUCT_PROPERTYKEY}(${PKEY_AppUserModel_ID})p.r3'
  System::Call '*${SYSSTRUCT_PROPVARIANT}(${VT_LPWSTR},,p r6)p.r4'
  ${If} $4 P<> 0
    # PROPVARIANT now owns the COM-allocated string.
    StrCpy $6 0
  ${EndIf}
  ${If} $3 P= 0
  ${OrIf} $4 P= 0
    StrCpy $5 -2147024882
    Goto identity_cleanup
  ${EndIf}
  ${IPropertyStore::SetValue} $2 '($3,$4).r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  ${IPropertyStore::Commit} $2 '().r5'
  ${If} $5 < 0
    Goto identity_cleanup
  ${EndIf}
  ${IPersistFile::Save} $1 '("$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk",1).r5'

  identity_cleanup:
  ${If} $4 P<> 0
    System::Call 'ole32::PropVariantClear(p r4)'
    System::Free $4
  ${EndIf}
  ${If} $3 P<> 0
    System::Free $3
  ${EndIf}
  ${If} $6 P<> 0
    System::Call 'ole32::CoTaskMemFree(p r6)'
  ${EndIf}
  !insertmacro ComHlpr_SafeRelease $2
  !insertmacro ComHlpr_SafeRelease $1
  !insertmacro ComHlpr_SafeRelease $0
  ${If} $5 < 0
    SetErrors
  ${Else}
    ClearErrors
  ${EndIf}
  Pop $6
  Pop $5
  Pop $4
  Pop $3
  Pop $2
  Pop $1
  Pop $0
FunctionEnd

Section "${APP_NAME}"
  # The previous uninstaller knows its exact payload, including files removed in this release.
  ReadRegStr $0 HKCU "Software\${APP_ID}" "InstallLocation"
  ${If} $0 != ""
  ${AndIf} $0 == $INSTDIR
    IfFileExists "$INSTDIR\Uninstall.exe" 0 upgrade_failed
    ClearErrors
    ExecWait '"$INSTDIR\Uninstall.exe" /S /UPGRADE _?=$INSTDIR' $1
    IfErrors upgrade_failed
    ${If} $1 != 0
      Goto upgrade_failed
    ${EndIf}
    Goto upgrade_done
  upgrade_failed:
    MessageBox MB_OK|MB_ICONSTOP "Close ${APP_NAME} and uninstall the previous version before installing." /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  upgrade_done:

  SetOutPath "$INSTDIR"
  ClearErrors
  File /r "${PAYLOAD_DIR}\*"
  IfErrors install_failed
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  IfErrors install_failed
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  IfErrors install_failed
  Call SetShortcutIdentity
  IfErrors install_failed
  WriteRegStr HKCU "Software\Classes\AppUserModelId\${APP_ID}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "Software\Classes\AppUserModelId\${APP_ID}" "IconUri" "$INSTDIR\data\flutter_assets\assets\images\phonolite-logo.png"
  WriteRegStr HKCU "Software\${APP_ID}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  IfErrors install_failed
  Goto install_done
  install_failed:
    MessageBox MB_OK|MB_ICONSTOP "Installation failed. Close ${APP_NAME} and try again." /SD IDOK
    SetErrorLevel 1
    Abort
  install_done:
SectionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext current
  StrCpy $UpgradeMode 0
  ${un.GetParameters} $R0
  ClearErrors
  ${un.GetOptions} $R0 "/UPGRADE" $R1
  ${IfNot} ${Errors}
    StrCpy $UpgradeMode 1
  ${EndIf}
  !insertmacro EnsureAppClosed
FunctionEnd

Function un.RemoveAppData
  # Both manual reinstalls and WinSparkle updates run the previous uninstaller.
  ${If} $UpgradeMode == 1
    Return
  ${EndIf}

  # Resolve and verify the fixed app folder before any recursive deletion.
  ${If} $APPDATA == ""
    Goto app_data_failed
  ${EndIf}
  GetFullPathName $0 "$APPDATA"
  GetFullPathName $1 "$APPDATA\Phonolite"
  ${un.GetParent} "$1" $2
  ${If} $0 == ""
  ${OrIf} $1 == ""
  ${OrIf} $2 != $0
    Goto app_data_failed
  ${EndIf}

  ${If} ${FileExists} "$1\*.*"
    ClearErrors
    RMDir /r "$1"
    IfErrors app_data_failed
  ${EndIf}
  Return

  app_data_failed:
    MessageBox MB_OK|MB_ICONSTOP "Could not remove $APPDATA\Phonolite. Close any programs using that folder and try uninstalling again." /SD IDOK
    SetErrorLevel 1
    Abort
FunctionEnd

Section "Uninstall"
  SetOutPath "$TEMP"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Phonolite"
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" "Phonolite"
  ClearErrors
  !include "uninstall_files.nsh"
  Call un.RemoveAppData
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\Classes\AppUserModelId\${APP_ID}"
  DeleteRegKey HKCU "Software\${APP_ID}"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  # Unrelated files in the installation directory and external storage are preserved.
SectionEnd
