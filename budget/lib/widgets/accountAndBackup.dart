import 'dart:async';
import 'package:budget/colors.dart';
import 'package:budget/database/generatePreviewData.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/firebase_options.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/aboutPage.dart';
import 'package:budget/pages/accountsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/shareBudget.dart';
import 'package:budget/struct/syncClient.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/exportCSV.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/importDB.dart';
import 'package:budget/widgets/moreIcons.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/saveFile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide TextInput;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:io';
import 'package:budget/struct/randomConstants.dart';
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/pocketbaseSync.dart';
import 'package:budget/widgets/textInput.dart';

Future<bool> checkConnection() async {
  late bool isConnected;
  if (!kIsWeb) {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isConnected = true;
      }
    } on SocketException catch (e) {
      print(e.toString());
      isConnected = false;
    }
  } else {
    isConnected = true;
  }
  return isConnected;
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = new http.Client();
  GoogleAuthClient(this._headers);
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

dynamic googleSignIn;
dynamic googleUser;

Future<bool> signInGoogle(
    {BuildContext? context,
    bool? waitForCompletion,
    bool? gMailPermissions,
    bool? drivePermissionsAttachments,
    bool? silentSignIn,
    Function()? next}) async {
  return false;
}

void refreshUIAfterLoginChange() {
  sidebarStateKey.currentState?.refreshState();
  accountsPageStateKey.currentState?.refreshState();
  settingsGoogleAccountLoginButtonKey.currentState?.refreshState();
}

Future<bool> testIfHasGmailAccess() async {
  return false;
}

Future<bool> signOutGoogle() async {
  await pocketBaseService.logout();
  refreshUIAfterLoginChange();
  return true;
}

Future<bool> refreshGoogleSignIn() async {
  return true;
}

Future<bool?> openPocketBaseAuthPopup(
  BuildContext context, {
  VoidCallback? onLoggedIn,
}) async {
  String email = "";
  String password = "";
  String passwordConfirm = "";
  bool isRegister = false;
  String errorMessage = "";

  return await openPopup(
    context,
    icon: Icons.cloud_sync_outlined,
    title: "PocketBase Backend",
    subtitle: defaultPocketBaseUrl.replaceFirst("https://", ""),
    descriptionWidget: StatefulBuilder(
      builder: (context, setPopupState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextInput(
              labelText: "Email",
              icon: Icons.email_outlined,
              onChanged: (text) {
                email = text.trim();
              },
            ),
            SizedBox(height: 10),
            TextInput(
              labelText: "Password",
              obscureText: true,
              icon: Icons.lock_outline,
              onChanged: (text) {
                password = text;
              },
            ),
            if (isRegister) ...[
              SizedBox(height: 10),
              TextInput(
                labelText: "Confirm Password",
                obscureText: true,
                icon: Icons.lock_reset_outlined,
                onChanged: (text) {
                  passwordConfirm = text;
                },
              ),
            ],
            if (errorMessage.isNotEmpty) ...[
              SizedBox(height: 10),
              TextFont(
                text: errorMessage,
                textColor: getColor(context, "danger"),
                fontSize: 13,
                maxLines: 3,
              ),
            ],
            SizedBox(height: 15),
            Center(
              child: Tappable(
                onTap: () {
                  setPopupState(() {
                    isRegister = !isRegister;
                    errorMessage = "";
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextFont(
                    text: isRegister
                        ? "Already have an account? Login"
                        : "Don't have an account? Register",
                    fontSize: 14,
                    textColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
    onSubmitLabel: isRegister ? "Register" : "Login",
    onSubmit: () async {
      if (email.isEmpty || password.isEmpty) {
        openSnackbar(
            SnackbarMessage(title: "Please enter both email and password"));
        return;
      }
      if (isRegister && password != passwordConfirm) {
        openSnackbar(SnackbarMessage(title: "Passwords do not match"));
        return;
      }

      try {
        openLoadingPopup(context);
        if (isRegister) {
          await pocketBaseService.register(email, password, passwordConfirm);
        } else {
          await pocketBaseService.login(email, password);
        }
        popRoute(context); // close loading
        popRoute(context, true); // close popup

        openSnackbar(
          SnackbarMessage(
            title: "Connected successfully",
            icon: Icons.cloud_done_rounded,
          ),
        );

        refreshUIAfterLoginChange();
        if (onLoggedIn != null) onLoggedIn();

        pocketBaseSyncEngine.syncAll().then((result) {
          if (result.success) {
            openSnackbar(
              SnackbarMessage(
                title: "Sync completed",
                description:
                    "Pushed ${result.pushedCount}, pulled ${result.pulledCount}",
                icon: Icons.sync,
              ),
            );
          }
          refreshUIAfterLoginChange();
        });
      } catch (e) {
        popRoute(context); // close loading
        openSnackbar(
          SnackbarMessage(
            title: "Authentication Failed",
            description: e.toString().replaceFirst("ClientException: ", ""),
            icon: Icons.error_outline,
          ),
        );
      }
    },
    onCancelLabel: "cancel".tr(),
    onCancel: () => popRoute(context, false),
  );
}

Future<bool> signInAndSync(BuildContext context,
    {required dynamic Function() next}) async {
  final result = await openPocketBaseAuthPopup(context, onLoggedIn: next);
  return result == true;
}

Future<void> createBackupInBackground(context) async {
  if (appStateSettings["hasSignedIn"] == false) return;
  if (errorSigningInDuringCloud == true) return;
  if (kIsWeb && !entireAppLoaded) return;
  // print(entireAppLoaded);
  print("Last backup: " + appStateSettings["lastBackup"]);
  //Only run this once, don't run again if the global state changes (e.g. when changing a setting)
  // Update: Does this still run when global state changes? I don't think so...
  // If the entire app is loaded and we want to do an auto backup, lets do it no matter what!
  // if (entireAppLoaded == false || entireAppLoaded) {
  if (appStateSettings["autoBackups"] == true) {
    DateTime lastUpdate = DateTime.parse(appStateSettings["lastBackup"]);
    DateTime nextPlannedBackup = lastUpdate
        .add(Duration(days: appStateSettings["autoBackupsFrequency"]));
    print("next backup planned on " + nextPlannedBackup.toString());
    if (DateTime.now().millisecondsSinceEpoch >=
        nextPlannedBackup.millisecondsSinceEpoch) {
      print("auto backing up");

      bool hasSignedIn = false;
      if (googleUser == null) {
        hasSignedIn = await signInGoogle(
            context: context,
            gMailPermissions: false,
            waitForCompletion: false,
            silentSignIn: true);
      } else {
        hasSignedIn = true;
      }
      if (hasSignedIn == false) {
        return;
      }
      await createBackup(context, silentBackup: true, deleteOldBackups: true);
    } else {
      print("backup already made today");
    }
  }
  // }
  return;
}

Future forceDeleteDB() async {
  if (kIsWeb) {
    final html.Storage localStorage = html.window.localStorage;
    localStorage.clear();
  } else {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'db.sqlite'));
    await dbFile.delete();
  }
}

bool openDatabaseCorruptedPopup(BuildContext context) {
  if (isDatabaseCorrupted) {
    openPopup(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.heart_broken_outlined
          : Icons.heart_broken_rounded,
      title: "database-corrupted".tr(),
      description: "database-corrupted-description".tr(),
      descriptionWidget: CodeBlock(
        text: databaseCorruptedError,
      ),
      barrierDismissible: false,
      onSubmit: () async {
        popRoute(context);
        await importDB(context, ignoreOverwriteWarning: true);
      },
      onSubmitLabel: "import-backup".tr(),
      onCancel: () async {
        popRoute(context);
        await openLoadingPopupTryCatch(() async {
          await forceDeleteDB();
          await sharedPreferences.clear();
        });
        restartAppPopup(context);
      },
      onCancelLabel: "reset".tr(),
    );
    // Lock the side navigation
    lockAppWaitForRestart = true;
    appStateKey.currentState?.refreshAppState();
    return true;
  }
  return false;
}

Future<void> createBackup(
  context, {
  bool? silentBackup,
  bool deleteOldBackups = false,
  String? clientIDForSync,
}) async {
  await backupSettings();
  return;
}

Future<void> deleteRecentBackups(context, amountToKeep,
    {bool? silentDelete}) async {
  return;
}

Future<void> deleteBackup(dynamic driveApi, String fileId) async {
  return;
}

Future<void> chooseBackup(context,
    {bool isManaging = false,
    bool isClientSync = false,
    bool hideDownloadButton = false}) async {
  try {
    openBottomSheet(
      context,
      BackupManagement(
        isManaging: isManaging,
        isClientSync: isClientSync,
        hideDownloadButton: hideDownloadButton,
      ),
    );
  } catch (e) {
    popRoute(context);
    openSnackbar(
      SnackbarMessage(
          title: e.toString(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.error_outlined
              : Icons.error_rounded),
    );
  }
}

Future<void> loadBackup(
    BuildContext context, dynamic driveApi, dynamic file) async {
  return;
}

class GoogleAccountLoginButton extends StatefulWidget {
  const GoogleAccountLoginButton({
    super.key,
    this.navigationSidebarButton = false,
    this.isButtonSelected = false,
    this.isOutlinedButton = true,
    this.forceButtonName,
  });
  final bool navigationSidebarButton;
  final bool isButtonSelected;
  final bool isOutlinedButton;
  final String? forceButtonName;

  @override
  State<GoogleAccountLoginButton> createState() =>
      GoogleAccountLoginButtonState();
}

class GoogleAccountLoginButtonState extends State<GoogleAccountLoginButton> {
  void refreshState() {
    setState(() {});
  }

  void openPage({VoidCallback? onNext}) {
    if (widget.navigationSidebarButton) {
      pageNavigationFrameworkKey.currentState!
          .changePage(8, switchNavbar: true);
      appStateKey.currentState?.refreshAppState();
    } else {
      if (onNext != null) onNext();
    }
  }

  void loginWithSync({VoidCallback? onNext}) {
    signInAndSync(
      widget.navigationSidebarButton
          ? navigatorKey.currentContext ?? context
          : context,
      next: () {
        setState(() {});
        openPage(onNext: onNext);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLoggedIn = pocketBaseService.isLoggedIn;
    String userEmail = pocketBaseService.userEmail ?? "";

    if (widget.navigationSidebarButton == true) {
      return AnimatedSwitcher(
        duration: Duration(milliseconds: 600),
        child: !isLoggedIn
            ? NavigationSidebarButton(
                key: ValueKey("login"),
                label: "login".tr(),
                icon: Icons.cloud_outlined,
                onTap: loginWithSync,
                isSelected: false,
              )
            : NavigationSidebarButton(
                key: ValueKey("user"),
                label: userEmail,
                icon: Icons.cloud_done_rounded,
                onTap: openPage,
                isSelected: widget.isButtonSelected,
              ),
      );
    }
    return !isLoggedIn
        ? SettingsContainerOpenPage(
            openPage: AccountsPage(),
            isOutlined: widget.isOutlinedButton,
            onTap: (openContainer) {
              loginWithSync(onNext: openContainer);
            },
            title: widget.forceButtonName ?? "login".tr(),
            icon: Icons.cloud_outlined,
            iconScale: 1,
          )
        : SettingsContainerOpenPage(
            openPage: AccountsPage(),
            title: widget.forceButtonName ?? userEmail,
            icon: Icons.cloud_done_rounded,
            iconScale: 1,
            isOutlined: widget.isOutlinedButton,
          );
  }
}

Future<(dynamic, dynamic)> getDriveFiles() async {
  return (null, null);
}

class BackupManagement extends StatefulWidget {
  const BackupManagement({
    Key? key,
    required this.isManaging,
    required this.isClientSync,
    this.hideDownloadButton = false,
  }) : super(key: key);

  final bool isManaging;
  final bool isClientSync;
  final bool hideDownloadButton;

  @override
  State<BackupManagement> createState() => _BackupManagementState();
}

class _BackupManagementState extends State<BackupManagement> {
  List<dynamic> filesState = [];
  List<int> deletedIndices = [];
  dynamic driveApiState;
  UniqueKey dropDownKey = UniqueKey();
  bool isLoading = true;
  bool autoBackups = appStateSettings["autoBackups"];
  bool backupSync = appStateSettings["backupSync"];

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      (dynamic, dynamic) result = await getDriveFiles();
      dynamic driveApi = result.$1;
      dynamic files = result.$2;
      if (files == null || driveApi == null) {
        setState(() {
          filesState = [];
          isLoading = false;
        });
      } else {
        setState(() {
          filesState = files;
          driveApiState = driveApi;
          isLoading = false;
        });
        bottomSheetControllerGlobal.snapToExtent(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isClientSync) {
      if (filesState.length > 0) {
        print(appStateSettings["devicesHaveBeenSynced"]);
        filesState =
            filesState.where((file) => isSyncBackupFile(file.name)).toList();
        updateSettings("devicesHaveBeenSynced", filesState.length,
            updateGlobalState: false);
      }
    } else {
      if (filesState.length > 0) {
        filesState =
            filesState.where((file) => !isSyncBackupFile(file.name)).toList();
        updateSettings("numBackups", filesState.length,
            updateGlobalState: false);
      }
    }
    Iterable<MapEntry<int, dynamic>> filesMap = filesState.asMap().entries;
    return PopupFramework(
      title: widget.isClientSync
          ? "devices".tr().capitalizeFirst
          : widget.isManaging
              ? "backups".tr()
              : "restore-a-backup".tr(),
      subtitle: widget.isClientSync
          ? "manage-syncing-info".tr()
          : widget.isManaging
              ? appStateSettings["backupLimit"].toString() +
                  " " +
                  "stored-backups".tr()
              : "overwrite-warning".tr(),
      child: Column(
        children: [
          widget.isClientSync && kIsWeb == false
              ? Row(
                  children: [
                    Expanded(
                      child: AboutInfoBox(
                        title: "web-app".tr(),
                        link: "https://budget-track.web.app/",
                        color: appStateSettings["materialYou"]
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : getColor(context, "lightDarkAccentHeavyLight"),
                        padding: EdgeInsetsDirectional.only(
                          start: 5,
                          end: 5,
                          bottom: 10,
                          top: 5,
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    await updateSettings("autoBackups", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    setState(() {
                      autoBackups = value;
                    });
                  },
                  initialValue: appStateSettings["autoBackups"],
                  title: "auto-backups".tr(),
                  description: "auto-backups-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_done_rounded,
                )
              : SizedBox.shrink(),
          widget.isClientSync
              ? SettingsContainerSwitch(
                  enableBorderRadius: true,
                  onSwitched: (value) async {
                    // Only update global is the sidebar is shown
                    await updateSettings("backupSync", value,
                        pagesNeedingRefresh: [], updateGlobalState: false);
                    sidebarStateKey.currentState?.refreshState();
                    setState(() {
                      backupSync = value;
                    });
                    // Future.delayed(Duration(milliseconds: 100), () {
                    //   bottomSheetControllerGlobal.snapToExtent(0);
                    // });
                  },
                  initialValue: appStateSettings["backupSync"],
                  title: "sync-data".tr(),
                  description: "sync-data-description".tr(),
                  icon: appStateSettings["outlinedIcons"]
                      ? Icons.cloud_sync_outlined
                      : Icons.cloud_sync_rounded,
                )
              : SizedBox.shrink(),
          // Only allow sync on every change for web
          // Only on web, disabled automatically in initializeSettings if not web
          widget.isClientSync && kIsWeb
              ? AnimatedExpanded(
                  expand: backupSync,
                  child: SettingsContainerSwitch(
                    enableBorderRadius: true,
                    onSwitched: (value) async {
                      await updateSettings("syncEveryChange", value,
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initialValue: appStateSettings["syncEveryChange"],
                    title: "sync-every-change".tr(),
                    descriptionWithValue: (value) {
                      return value
                          ? "sync-every-change-description1".tr()
                          : "sync-every-change-description2".tr();
                    },
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.all_inbox_outlined
                        : Icons.all_inbox_rounded,
                  ),
                )
              : SizedBox.shrink(),
          widget.isManaging && widget.isClientSync == false
              ? AnimatedExpanded(
                  expand: autoBackups,
                  child: SettingsContainerDropdown(
                    enableBorderRadius: true,
                    items: ["1", "2", "3", "7", "10", "14"],
                    onChanged: (value) async {
                      await updateSettings(
                          "autoBackupsFrequency", int.parse(value),
                          pagesNeedingRefresh: [], updateGlobalState: false);
                    },
                    initial:
                        appStateSettings["autoBackupsFrequency"].toString(),
                    title: "backup-frequency".tr(),
                    description: "number-of-days".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.event_repeat_outlined
                        : Icons.event_repeat_rounded,
                  ),
                )
              : SizedBox.shrink(),
          widget.isManaging &&
                  widget.isClientSync == false &&
                  appStateSettings["showBackupLimit"]
              ? SettingsContainerDropdown(
                  enableBorderRadius: true,
                  key: dropDownKey,
                  verticalPadding: 5,
                  title: "backup-limit".tr(),
                  icon: Icons.format_list_numbered_rtl_outlined,
                  initial: appStateSettings["backupLimit"].toString(),
                  items: ["10", "15", "20", "30"],
                  onChanged: (value) async {
                    if (int.parse(value) < appStateSettings["backupLimit"]) {
                      openPopup(
                        context,
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.delete_outlined
                            : Icons.delete_rounded,
                        title: "change-limit".tr(),
                        description: "change-limit-warning".tr(),
                        onSubmit: () async {
                          await updateSettings("backupLimit", int.parse(value),
                              updateGlobalState: false);
                          popRoute(context);
                        },
                        onSubmitLabel: "change".tr(),
                        onCancel: () {
                          popRoute(context);
                          setState(() {
                            dropDownKey = UniqueKey();
                          });
                        },
                        onCancelLabel: "cancel".tr(),
                      );
                    } else {
                      await updateSettings("backupLimit", int.parse(value),
                          updateGlobalState: false);
                    }
                  },
                )
              : SizedBox.shrink(),
          if ((widget.isManaging == false && widget.isClientSync == false) ==
              false)
            SizedBox(height: 10),
          isLoading
              ? Column(
                  children: [
                    for (int i = 0;
                        i <
                            (widget.isClientSync
                                ? appStateSettings["devicesHaveBeenSynced"]
                                : appStateSettings["numBackups"]);
                        i++)
                      LoadingShimmerDriveFiles(
                          isManaging: widget.isManaging, i: i),
                  ],
                )
              : SizedBox.shrink(),
          ...filesMap
              .map(
                (MapEntry<int, dynamic> file) => AnimatedSizeSwitcher(
                  child: deletedIndices.contains(file.key)
                      ? Container(
                          key: ValueKey(1),
                        )
                      : Padding(
                          padding:
                              const EdgeInsetsDirectional.only(bottom: 8.0),
                          child: Tappable(
                            onTap: () async {
                              if (!widget.isManaging) {
                                final result = await openPopup(
                                  context,
                                  title: "load-backup".tr(),
                                  subtitle: getWordedDateShortMore(
                                        (file.value.modifiedTime ??
                                                DateTime.now())
                                            .toLocal(),
                                        includeTime: true,
                                        includeYear: true,
                                        showTodayTomorrow: false,
                                      ) +
                                      "\n" +
                                      getWordedTime(
                                          navigatorKey.currentContext?.locale
                                              .toString(),
                                          (file.value.modifiedTime ??
                                                  DateTime.now())
                                              .toLocal()),
                                  beforeDescriptionWidget: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      top: 8,
                                      bottom: 5,
                                    ),
                                    child: CodeBlock(
                                        text: (file.value.name ?? "No name")),
                                  ),
                                  description: "load-backup-warning".tr(),
                                  icon: appStateSettings["outlinedIcons"]
                                      ? Icons.warning_outlined
                                      : Icons.warning_rounded,
                                  onSubmit: () async {
                                    popRoute(context, true);
                                  },
                                  onSubmitLabel: "load".tr(),
                                  onCancelLabel: "cancel".tr(),
                                  onCancel: () {
                                    popRoute(context);
                                  },
                                );
                                if (result == true)
                                  loadBackup(
                                      context, driveApiState, file.value);
                              }
                              // else {
                              //   await openPopup(
                              //     context,
                              //     title: "Backup Details",
                              //     description: (file.value.name ?? "") +
                              //         "\n" +
                              //         (file.value.size ?? "") +
                              //         "\n" +
                              //         (file.value.description ?? ""),
                              //     icon: appStateSettings["outlinedIcons"] ? Icons.warning_outlined : Icons.warning_rounded,
                              //     onSubmit: () async {
                              //       popRoute(context, true);
                              //     },
                              //     onSubmitLabel: "Close",
                              //   );
                              // }
                            },
                            borderRadius: 15,
                            color: widget.isClientSync &&
                                    isCurrentDeviceSyncBackupFile(
                                        file.value.name)
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.4)
                                : appStateSettings["materialYou"]
                                    ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                    : getColor(
                                        context, "lightDarkAccentHeavyLight"),
                            child: Container(
                              padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: 20, vertical: 15),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          widget.isClientSync
                                              ? appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.devices_outlined
                                                  : Icons.devices_rounded
                                              : appStateSettings[
                                                      "outlinedIcons"]
                                                  ? Icons.description_outlined
                                                  : Icons.description_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          size: 30,
                                        ),
                                        SizedBox(
                                            width:
                                                widget.isClientSync ? 17 : 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              TextFont(
                                                text: getTimeAgo(
                                                  (file.value.modifiedTime ??
                                                          DateTime.now())
                                                      .toLocal(),
                                                ).capitalizeFirst,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                maxLines: 2,
                                              ),
                                              TextFont(
                                                text: (isSyncBackupFile(
                                                        file.value.name)
                                                    ? getDeviceFromSyncBackupFileName(
                                                            file.value.name) +
                                                        " " +
                                                        "sync"
                                                    : file.value.name ??
                                                        "No name"),
                                                fontSize: 14,
                                                maxLines: 2,
                                              ),
                                              // isSyncBackupFile(
                                              //         file.value.name)
                                              //     ? Padding(
                                              //         padding:
                                              //             const EdgeInsetsDirectional
                                              //                 .only(top: 3),
                                              //         child: TextFont(
                                              //           text:
                                              //               file.value.name ??
                                              //                   "",
                                              //           fontSize: 11,
                                              //           maxLines: 2,
                                              //         ),
                                              //       )
                                              //     : SizedBox.shrink()
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  widget.isManaging
                                      ? Row(
                                          children: [
                                            widget.hideDownloadButton
                                                ? SizedBox.shrink()
                                                : Padding(
                                                    padding:
                                                        const EdgeInsetsDirectional
                                                            .only(
                                                      start: 8.0,
                                                    ),
                                                    child: Builder(
                                                        builder: (boxContext) {
                                                      return ButtonIcon(
                                                        color: appStateSettings[
                                                                "materialYou"]
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSecondaryContainer
                                                                .withOpacity(
                                                                    0.08)
                                                            : getColor(context,
                                                                    "lightDarkAccentHeavy")
                                                                .withOpacity(
                                                                    0.7),
                                                        onTap: () {
                                                          saveDriveFileToDevice(
                                                            boxContext:
                                                                boxContext,
                                                            driveApi:
                                                                driveApiState,
                                                            fileToSave:
                                                                file.value,
                                                          );
                                                        },
                                                        icon: Icons
                                                            .download_rounded,
                                                      );
                                                    }),
                                                  ),
                                            Padding(
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(start: 5),
                                              child: ButtonIcon(
                                                color: appStateSettings[
                                                        "materialYou"]
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onSecondaryContainer
                                                        .withOpacity(0.08)
                                                    : getColor(context,
                                                            "lightDarkAccentHeavy")
                                                        .withOpacity(0.7),
                                                onTap: () {
                                                  openPopup(
                                                    context,
                                                    icon: appStateSettings[
                                                            "outlinedIcons"]
                                                        ? Icons.delete_outlined
                                                        : Icons.delete_rounded,
                                                    title: "delete-backup".tr(),
                                                    subtitle:
                                                        getWordedDateShortMore(
                                                              (file.value.modifiedTime ??
                                                                      DateTime
                                                                          .now())
                                                                  .toLocal(),
                                                              includeTime: true,
                                                              includeYear: true,
                                                              showTodayTomorrow:
                                                                  false,
                                                            ) +
                                                            "\n" +
                                                            getWordedTime(
                                                                navigatorKey
                                                                    .currentContext
                                                                    ?.locale
                                                                    .toString(),
                                                                (file.value.modifiedTime ??
                                                                        DateTime
                                                                            .now())
                                                                    .toLocal()),
                                                    beforeDescriptionWidget:
                                                        Padding(
                                                      padding:
                                                          const EdgeInsetsDirectional
                                                              .only(
                                                        top: 8,
                                                        bottom: 5,
                                                      ),
                                                      child: CodeBlock(
                                                        text: (file.value
                                                                    .name ??
                                                                "No name") +
                                                            "\n" +
                                                            convertBytesToMB(file
                                                                        .value
                                                                        .size ??
                                                                    "0")
                                                                .toStringAsFixed(
                                                                    2) +
                                                            " MB",
                                                      ),
                                                    ),
                                                    description: (widget
                                                            .isClientSync
                                                        ? "delete-sync-backup-warning"
                                                            .tr()
                                                        : null),
                                                    onSubmit: () async {
                                                      popRoute(context);
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(true);
                                                      await deleteBackup(
                                                          driveApiState,
                                                          file.value.id ?? "");
                                                      openSnackbar(
                                                        SnackbarMessage(
                                                            title:
                                                                "deleted-backup"
                                                                    .tr(),
                                                            description: (file
                                                                    .value
                                                                    .name ??
                                                                "No name"),
                                                            icon: Icons
                                                                .delete_rounded),
                                                      );
                                                      setState(() {
                                                        deletedIndices
                                                            .add(file.key);
                                                      });
                                                      // bottomSheetControllerGlobal
                                                      //     .snapToExtent(0);
                                                      if (widget.isClientSync)
                                                        await updateSettings(
                                                            "devicesHaveBeenSynced",
                                                            appStateSettings[
                                                                    "devicesHaveBeenSynced"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      if (widget.isManaging) {
                                                        await updateSettings(
                                                            "numBackups",
                                                            appStateSettings[
                                                                    "numBackups"] -
                                                                1,
                                                            updateGlobalState:
                                                                false);
                                                      }
                                                      loadingIndeterminateKey
                                                          .currentState
                                                          ?.setVisibility(
                                                              false);
                                                    },
                                                    onSubmitLabel:
                                                        "delete".tr(),
                                                    onCancel: () {
                                                      popRoute(context);
                                                    },
                                                    onCancelLabel:
                                                        "cancel".tr(),
                                                  );
                                                },
                                                icon: appStateSettings[
                                                        "outlinedIcons"]
                                                    ? Icons.close_outlined
                                                    : Icons.close_rounded,
                                              ),
                                            ),
                                          ],
                                        )
                                      : SizedBox.shrink(),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }
}

double convertBytesToMB(String bytesString) {
  try {
    int bytes = int.parse(bytesString);
    double megabytes = bytes / (1024 * 1024);
    return megabytes;
  } catch (e) {
    print("Error parsing bytes string: $e");
    return 0.0; // or throw an exception, depending on your requirements
  }
}

class LoadingShimmerDriveFiles extends StatelessWidget {
  const LoadingShimmerDriveFiles({
    Key? key,
    required this.isManaging,
    required this.i,
  }) : super(key: key);

  final bool isManaging;
  final int i;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      period:
          Duration(milliseconds: (1000 + randomDouble[i % 10] * 520).toInt()),
      baseColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      highlightColor: appStateSettings["materialYou"]
          ? Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.2)
          : getColor(context, "lightDarkAccentHeavy").withAlpha(20),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8.0),
        child: Tappable(
          onTap: () {},
          borderRadius: 15,
          color: appStateSettings["materialYou"]
              ? Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withOpacity(0.5)
              : getColor(context, "lightDarkAccentHeavy").withOpacity(0.5),
          child: Container(
              padding:
                  EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          appStateSettings["outlinedIcons"]
                              ? Icons.description_outlined
                              : Icons.description_rounded,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 30,
                        ),
                        SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 20,
                                width: 70 + randomDouble[i % 10] * 120 + 13,
                              ),
                              SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadiusDirectional.all(
                                      Radius.circular(5)),
                                  color: Colors.white,
                                ),
                                height: 14,
                                width: 90 + randomDouble[i % 10] * 120,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 13),
                  isManaging
                      ? Row(
                          children: [
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                            SizedBox(width: 5),
                            ButtonIcon(
                                onTap: () {},
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.close_outlined
                                    : Icons.close_rounded),
                          ],
                        )
                      : SizedBox.shrink(),
                ],
              )),
        ),
      ),
    );
  }
}

Future<bool> saveDriveFileToDevice({
  required BuildContext boxContext,
  required dynamic driveApi,
  required dynamic fileToSave,
}) async {
  return false;
}

bool openBackupReminderPopupCheck(BuildContext context) {
  if ((appStateSettings["currentUserEmail"] == null ||
          appStateSettings["currentUserEmail"] == "") &&
      ((appStateSettings["numLogins"] + 1) % 7 == 0) &&
      appStateSettings["canShowBackupReminderPopup"] == true) {
    openPopup(
      context,
      icon: MoreIcons.google_drive,
      iconScale: 0.9,
      title: "backup-your-data-reminder".tr(),
      description: "backup-your-data-reminder-description".tr() +
          " " +
          "google-drive".tr(),
      onSubmitLabel: "backup".tr().capitalizeFirst,
      onSubmit: () async {
        popRoute(context);
        await signInAndSync(context, next: () {});
      },
      onCancelLabel: "never".tr().capitalizeFirst,
      onCancel: () async {
        popRoute(context);
        await updateSettings("canShowBackupReminderPopup", false,
            updateGlobalState: false);
      },
      onExtraLabel: "later".tr().capitalizeFirst,
      onExtra: () {
        popRoute(context);
      },
    );
    return true;
  }
  return false;
}
