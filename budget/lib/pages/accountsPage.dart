import 'dart:io';
import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/accountProfileBottomSheet.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/dropdownSelect.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/iconButtonScaled.dart';
import 'package:budget/widgets/moreIcons.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:budget/widgets/extraInfoBoxes.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/pocketbaseSync.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/struct/databaseGlobal.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({Key? key}) : super(key: key);

  @override
  State<AccountsPage> createState() => AccountsPageState();
}

class AccountsPageState extends State<AccountsPage> {
  bool currentlyExporting = false;

  void refreshState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    String displayName = pocketBaseService.userName ??
        (pocketBaseService.userEmail?.split("@").first ?? "User");
    String userInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : "U";

    String? localAvatar = sharedPreferences.getString("user_avatar_path");
    String? pbAvatar = pocketBaseService.userAvatarUrl;
    ImageProvider? avatarImg;
    if (localAvatar != null &&
        localAvatar.isNotEmpty &&
        File(localAvatar).existsSync()) {
      avatarImg = FileImage(File(localAvatar));
    } else if (pbAvatar != null &&
        pbAvatar.isNotEmpty &&
        pbAvatar.startsWith("http")) {
      avatarImg = NetworkImage(pbAvatar);
    }

    Widget profileWidget = Tappable(
      borderRadius: 100,
      color: Colors.transparent,
      onTap: () {
        openAccountProfileBottomSheet(context);
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dynamicPastel(context, Theme.of(context).colorScheme.primary,
              amount: 0.2),
          image: avatarImg != null
              ? DecorationImage(image: avatarImg, fit: BoxFit.cover)
              : null,
        ),
        child: avatarImg == null
            ? Center(
                child: TextFont(
                  text: userInitial,
                  fontSize: 55,
                  textAlign: TextAlign.center,
                  fontWeight: FontWeight.bold,
                  textColor: dynamicPastel(
                    context,
                    Theme.of(context).colorScheme.primary,
                    amount: 0.85,
                    inverse: false,
                  ),
                ),
              )
            : null,
      ),
    );

    List<SyncHistoryEntry> history = getSyncHistory();

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      expandedHeight: 56,
      title: "Cloud",
      appBarBackgroundColor: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      appBarBackgroundColorStart: getPlatform() == PlatformOS.isIOS
          ? null
          : Theme.of(context).colorScheme.secondaryContainer,
      bottomPadding: false,
      actions: [],
      slivers: [
        SliverToBoxAdapter(
          child: !pocketBaseService.isLoggedIn
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: SettingsContainerOutlined(
                      title: "Connect Backend & Sync",
                      icon: Icons.cloud_outlined,
                      isExpanded: false,
                      onTap: () async {
                        await openPocketBaseAuthPopup(context, onLoggedIn: () {
                          setState(() {});
                        });
                      },
                    ),
                  ),
                )
              : Column(
                  children: [
                    const SizedBox(height: 35),
                    profileWidget,
                    const SizedBox(height: 12),
                    TextFont(
                      text: displayName,
                      textAlign: TextAlign.center,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    if (pocketBaseService.userEmail != null) ...[
                      const SizedBox(height: 2),
                      TextFont(
                        text: pocketBaseService.userEmail!,
                        textAlign: TextAlign.center,
                        fontSize: 14,
                        textColor: getColor(context, "textLight"),
                      ),
                    ],
                    const SizedBox(height: 15),
                    IntrinsicWidth(
                      child: Button(
                        label: "logout".tr(),
                        onTap: () async {
                          final confirm = await openPopup(
                            context,
                            title: "logout".tr(),
                            description: "Are you sure you want to sign out?",
                            icon: Icons.logout_rounded,
                            onSubmit: () => popRoute(context, true),
                            onCancel: () => popRoute(context, false),
                            onSubmitLabel: "logout".tr(),
                            onCancelLabel: "cancel".tr(),
                          );
                          if (confirm == true) {
                            await signOutGoogle();
                          }
                        },
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 17, vertical: 12),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 25),
                    Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 18.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: IgnorePointer(
                              ignoring: currentlyExporting,
                              child: AnimatedOpacity(
                                opacity: currentlyExporting ? 0.4 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: OutlinedButtonStacked(
                                  text: "Sync Now",
                                  iconData: appStateSettings["outlinedIcons"]
                                      ? Icons.sync_outlined
                                      : Icons.sync_rounded,
                                  customIconBuilder: (icon) => BouncingWidget(
                                    animate: currentlyExporting,
                                    child: icon,
                                  ),
                                  onTap: () async {
                                    setState(() {
                                      currentlyExporting = true;
                                    });
                                    final res =
                                        await pocketBaseSyncEngine.syncAll();
                                    if (mounted) {
                                      setState(() {
                                        currentlyExporting = false;
                                      });
                                      openSnackbar(SnackbarMessage(
                                        title: res.success
                                            ? "Sync completed"
                                            : "Sync failed",
                                        description: res.message,
                                        icon: res.success
                                            ? Icons.cloud_done_rounded
                                            : Icons.error_outline,
                                      ));
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: OutlinedButtonStacked(
                              text: "Full Sync",
                              iconData: appStateSettings["outlinedIcons"]
                                  ? Icons.cloud_sync_outlined
                                  : Icons.cloud_sync_rounded,
                              onTap: () async {
                                setState(() {
                                  currentlyExporting = true;
                                });
                                final res = await pocketBaseSyncEngine.syncAll(
                                    forceFullSync: true);
                                if (mounted) {
                                  setState(() {
                                    currentlyExporting = false;
                                  });
                                  openSnackbar(SnackbarMessage(
                                    title: res.success
                                        ? "Full Sync completed"
                                        : "Full Sync failed",
                                    description: res.message,
                                    icon: res.success
                                        ? Icons.cloud_done_rounded
                                        : Icons.error_outline,
                                  ));
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextFont(
                      text: "Last synced: " +
                          (sharedPreferences.getString("pb_last_sync") == null
                              ? "Never"
                              : getWordedDateShortMore(
                                  DateTime.parse(sharedPreferences
                                      .getString("pb_last_sync")!),
                                  includeTime: true,
                                )),
                      fontSize: 13,
                      textColor: getColor(context, "textLight"),
                    ),
                    const SizedBox(height: 25),
                  ],
                ),
        ),
        if (pocketBaseService.isLoggedIn) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  TextFont(
                    text: "Sync History",
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ],
              ),
            ),
          ),
          if (history.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: TextFont(
                    text: "No sync history yet",
                    fontSize: 14,
                    textColor: getColor(context, "textLight"),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = history[index];
                  final isSuccess = entry.status == "Success";
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 4),
                    child: SettingsContainerOutlined(
                      isWideOutlined: true,
                      title: entry.syncType,
                      description:
                          "${getWordedDateShortMore(entry.dateTime, includeTime: true)} • Pushed: ${entry.pushedCount}, Pulled: ${entry.pulledCount}",
                      icon: isSuccess
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      onTap: () {
                        openPopup(
                          context,
                          title: entry.syncType,
                          icon: isSuccess
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          description:
                              "Time: ${getWordedDateShortMore(entry.dateTime, includeTime: true)}\nStatus: ${entry.status}\nPushed records: ${entry.pushedCount}\nPulled records: ${entry.pulledCount}\nDetails: ${entry.message}",
                          onSubmit: () => popRoute(context),
                          onSubmitLabel: "Close",
                        );
                      },
                    ),
                  );
                },
                childCount: history.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ],
    );
  }
}

class SyncCloudBackupButton extends StatelessWidget {
  const SyncCloudBackupButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonStacked(
      text: getPlatform() == PlatformOS.isIOS
          ? "devices".tr().capitalizeFirst
          : "sync".tr(),
      iconData: getPlatform() == PlatformOS.isIOS
          ? appStateSettings["outlinedIcons"]
              ? Icons.devices_outlined
              : Icons.devices_rounded
          : appStateSettings["outlinedIcons"]
              ? Icons.cloud_sync_outlined
              : Icons.cloud_sync_rounded,
      onTap: onTap,
    );
  }
}

class BackupsCloudBackupButton extends StatelessWidget {
  const BackupsCloudBackupButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButtonStacked(
      text: "backups".tr(),
      iconData: appStateSettings["outlinedIcons"]
          ? Icons.folder_outlined
          : Icons.folder_rounded,
      onTap: onTap,
    );
  }
}

class EnableSignInWithGoogleFlyIn extends StatelessWidget {
  const EnableSignInWithGoogleFlyIn({super.key});

  @override
  Widget build(BuildContext context) {
    if (appStateSettings["enableGoogleLoginFlyIn"] != true ||
        getIsFullScreen(context) == false) return SizedBox.shrink();
    return const SignInWithGoogleFlyIn();
  }
}

class SignInWithGoogleFlyIn extends StatefulWidget {
  const SignInWithGoogleFlyIn({super.key});

  @override
  State<SignInWithGoogleFlyIn> createState() => _SignInWithGoogleFlyInState();
}

class _SignInWithGoogleFlyInState extends State<SignInWithGoogleFlyIn> {
  bool hide = true;

  @override
  void initState() {
    checkCloudFunctionsStatus();
    super.initState();
  }

  void checkCloudFunctionsStatus() {
    Future.delayed(Duration(seconds: 1), () {
      if (!runningCloudFunctions && entireAppLoaded) {
        setState(() {
          hide = false;
        });
      } else {
        checkCloudFunctionsStatus();
      }
    });
  }

  bool get shouldExpand => !hide && googleUser == null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 22),
      child: SlideFadeTransition(
        animate: true,
        animationDuration: Duration(milliseconds: 1700),
        curve: ElasticOutCurve(0.8),
        delayStart: Duration(milliseconds: 1900),
        offset: -0.5,
        child: AnimatedExpanded(
          expand: shouldExpand,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadiusDirectional.all(Radius.circular(13)),
                      color: getColor(context, "lightDarkAccentHeavyLight"),
                      boxShadow: boxShadowCheck(boxShadowSharp(context)),
                    ),
                    child: Tappable(
                      onTap: () async {
                        await signInGoogle();
                        setState(() {
                          hide = true;
                        });
                      },
                      borderRadius: 13,
                      color: dynamicPastel(
                        context,
                        Theme.of(context).colorScheme.secondaryContainer,
                        amount: 0.6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 25,
                                end: 15,
                                top: 15,
                                bottom: 15,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        MoreIcons.google,
                                        size: 25,
                                      ),
                                      SizedBox(width: 10),
                                      TextFont(
                                        text: "sign-in-with-google".tr(),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                        start: 18.0),
                                    child: IconButtonScaled(
                                      iconData:
                                          appStateSettings["outlinedIcons"]
                                              ? Icons.close_outlined
                                              : Icons.close_rounded,
                                      iconSize: 18,
                                      scale: 1.5,
                                      onTap: () async {
                                        setState(() {
                                          hide = true;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          HorizontalBreak(
                            padding: EdgeInsetsDirectional.zero,
                            color: dynamicPastel(
                              context,
                              Theme.of(context).colorScheme.secondaryContainer,
                              amount: 0.1,
                              inverse: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 22, vertical: 12),
                            child: Button(
                              label: "Continue with Google",
                              onTap: () async {
                                await signInGoogle();
                                setState(() {
                                  hide = true;
                                });
                              },
                              color: Theme.of(context).colorScheme.primary,
                              textColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              borderRadius: 5,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 22, end: 22, bottom: 22),
                            child: TextFont(
                              text: "onboarding-info-3".tr(),
                              maxLines: 10,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
