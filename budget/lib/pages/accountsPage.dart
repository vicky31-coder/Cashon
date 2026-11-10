import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/accountProfileBottomSheet.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/iconButtonScaled.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  bool isSyncing = false;

  void refreshState() {
    setState(() {});
  }

  Future<void> _triggerUnifiedSync({bool forceFull = false}) async {
    if (isSyncing) return;
    setState(() => isSyncing = true);
    openSnackbar(SnackbarMessage(
      title: forceFull ? "Full sync in progress..." : "Sync in progress...",
      description: "Transferring changes with cloud...",
      icon: Icons.sync,
      timeout: const Duration(seconds: 2),
    ));
    final res = await pocketBaseSyncEngine.syncAll(forceFullSync: forceFull);
    if (mounted) {
      setState(() => isSyncing = false);
      openSnackbar(SnackbarMessage(
        title: res.success
            ? (forceFull ? "Full Sync Completed" : "Sync Completed")
            : "Sync Failed",
        description: res.message,
        icon: res.success ? Icons.cloud_done_rounded : Icons.error_outline,
      ));
    }
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

    final bool isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows);

    if (isDesktop && pocketBaseService.isLoggedIn) {
      return PageFramework(
        horizontalPaddingConstrained: false,
        dragDownToDismiss: true,
        expandedHeight: 56,
        title: "Cloud",
        appBarBackgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        appBarBackgroundColorStart:
            Theme.of(context).colorScheme.secondaryContainer,
        bottomPadding: false,
        actions: [],
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Card: Account details and sync buttons
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: getColor(context, "canvasContainer"),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.18),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          profileWidget,
                          const SizedBox(height: 14),
                          TextFont(
                            text: displayName,
                            textAlign: TextAlign.center,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          if (pocketBaseService.userEmail != null) ...[
                            const SizedBox(height: 4),
                            TextFont(
                              text: pocketBaseService.userEmail!,
                              textAlign: TextAlign.center,
                              fontSize: 14,
                              textColor: getColor(context, "textLight"),
                            ),
                          ],
                          const SizedBox(height: 16),
                          IntrinsicWidth(
                            child: Button(
                              label: "logout".tr(),
                              onTap: () async {
                                final confirm = await openPopup(
                                  context,
                                  title: "logout".tr(),
                                  description:
                                      "Are you sure you want to sign out?",
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
                                  horizontal: 18, vertical: 10),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.15),
                          ),
                          const SizedBox(height: 20),
                          _SyncActionButton(
                            title: "Sync Now",
                            subtitle: isSyncing
                                ? "Synchronizing with cloud..."
                                : "Pull cloud updates & push local changes",
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.sync_outlined
                                : Icons.sync_rounded,
                            isPrimary: true,
                            isLoading: isSyncing,
                            onTap: () => _triggerUnifiedSync(forceFull: false),
                          ),
                          const SizedBox(height: 12),
                          _SyncActionButton(
                            title: "Full Sync",
                            subtitle: isSyncing
                                ? "Synchronizing all records..."
                                : "Force full bidirectional sync of all records",
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.cloud_sync_outlined
                                : Icons.cloud_sync_rounded,
                            isPrimary: false,
                            isLoading: isSyncing,
                            onTap: () => _triggerUnifiedSync(forceFull: true),
                          ),
                          const SizedBox(height: 16),
                          TextFont(
                            text: "Last synced: " +
                                (sharedPreferences.getString("pb_last_sync") ==
                                        null
                                    ? "Never"
                                    : DateFormat('dd MMM yyyy, hh:mm a').format(
                                        DateTime.parse(sharedPreferences
                                                .getString("pb_last_sync")!)
                                            .toLocal())),
                            fontSize: 13,
                            textColor: getColor(context, "textLight"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right Card: Sync History
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: getColor(context, "canvasContainer"),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.18),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextFont(
                                text: "Sync History",
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              if (history.isNotEmpty)
                                Tappable(
                                  color: Colors.transparent,
                                  borderRadius: 10,
                                  onTap: () async {
                                    await clearSyncHistory();
                                    setState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.delete_sweep_outlined,
                                          size: 18,
                                          color: getColor(context, "textLight"),
                                        ),
                                        const SizedBox(width: 4),
                                        TextFont(
                                          text: "Clear All",
                                          fontSize: 13,
                                          textColor:
                                              getColor(context, "textLight"),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (history.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: TextFont(
                                  text: "No sync history yet",
                                  fontSize: 14,
                                  textColor: getColor(context, "textLight"),
                                ),
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount:
                                  history.length > 20 ? 20 : history.length,
                              itemBuilder: (context, index) {
                                final entry = history[index];
                                final isSuccess = entry.status == "Success";
                                final formattedDate =
                                    DateFormat("dd MMM yyyy, hh:mm a")
                                        .format(entry.dateTime.toLocal());
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SettingsContainerOutlined(
                                    isWideOutlined: true,
                                    title: formattedDate,
                                    description:
                                        "${entry.syncType} • Pushed: ${entry.pushedCount}, Pulled: ${entry.pulledCount}",
                                    icon: isSuccess
                                        ? Icons.cloud_done_rounded
                                        : Icons.cloud_off_rounded,
                                    onTap: () {
                                      openPopup(
                                        context,
                                        title: formattedDate,
                                        icon: isSuccess
                                            ? Icons.cloud_done_rounded
                                            : Icons.cloud_off_rounded,
                                        description:
                                            "Type: ${entry.syncType}\nStatus: ${entry.status}\nPushed records: ${entry.pushedCount}\nPulled records: ${entry.pulledCount}\nDetails: ${entry.message}",
                                        onSubmit: () => popRoute(context),
                                        onSubmitLabel: "Close",
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      );
    }

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
                      padding: const EdgeInsets.symmetric(horizontal: 18.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: _SyncActionButton(
                            title: "Sync Now",
                            subtitle: isSyncing
                                ? "Synchronizing with cloud..."
                                : "Pull cloud updates & push local changes",
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.sync_outlined
                                : Icons.sync_rounded,
                            isPrimary: true,
                            isLoading: isSyncing,
                            onTap: () => _triggerUnifiedSync(forceFull: false),
                            onLongPress: () =>
                                _triggerUnifiedSync(forceFull: true),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFont(
                      text: "Last synced: " +
                          (sharedPreferences.getString("pb_last_sync") == null
                              ? "Never"
                              : DateFormat('dd MMM yyyy, hh:mm a').format(
                                  DateTime.parse(sharedPreferences
                                          .getString("pb_last_sync")!)
                                      .toLocal())) +
                          " • Hold for full sync",
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextFont(
                    text: "Sync History",
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  if (history.isNotEmpty)
                    Tappable(
                      color: Colors.transparent,
                      borderRadius: 10,
                      onTap: () async {
                        await clearSyncHistory();
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.delete_sweep_outlined,
                              size: 18,
                              color: getColor(context, "textLight"),
                            ),
                            const SizedBox(width: 4),
                            TextFont(
                              text: "Clear All",
                              fontSize: 13,
                              textColor: getColor(context, "textLight"),
                            ),
                          ],
                        ),
                      ),
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
                  final formattedDate =
                      DateFormat("dd MMM yyyy, hh:mm a").format(entry.dateTime.toLocal());
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 4),
                    child: SettingsContainerOutlined(
                      isWideOutlined: true,
                      title: formattedDate,
                      description:
                          "${entry.syncType} • Pushed: ${entry.pushedCount}, Pulled: ${entry.pulledCount}",
                      icon: isSuccess
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      onTap: () {
                        openPopup(
                          context,
                          title: formattedDate,
                          icon: isSuccess
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          description:
                              "Type: ${entry.syncType}\nStatus: ${entry.status}\nPushed records: ${entry.pushedCount}\nPulled records: ${entry.pulledCount}\nDetails: ${entry.message}",
                          onSubmit: () => popRoute(context),
                          onSubmitLabel: "Close",
                        );
                      },
                    ),
                  );
                },
                childCount: history.length > 20 ? 20 : history.length,
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
    return const SizedBox.shrink();
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

  bool get shouldExpand => !hide && !pocketBaseService.isLoggedIn;

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
                        setState(() {
                          hide = true;
                        });
                        await signInAndSync(context, next: () {});
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
                                        Icons.cloud_outlined,
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
                              label: "Continue to Cloud",
                              onTap: () async {
                                setState(() {
                                  hide = true;
                                });
                                await signInAndSync(context, next: () {});
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

class _SyncActionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isLoading;
  final bool isPrimary;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SyncActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isLoading,
    required this.isPrimary,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isPrimary
        ? theme.colorScheme.primaryContainer
        : getColor(context, "canvasContainer");
    final fgColor = isPrimary
        ? theme.colorScheme.onPrimaryContainer
        : getColor(context, "black");

    return Tappable(
      color: bgColor,
      borderRadius: 18,
      onTap: isLoading ? () {} : onTap,
      onLongPress: isLoading ? null : onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPrimary
                ? theme.colorScheme.primary.withOpacity(0.3)
                : theme.colorScheme.outline.withOpacity(0.12),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isPrimary
                    ? theme.colorScheme.primary.withOpacity(0.18)
                    : theme.colorScheme.secondaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: fgColor,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 24,
                      color: fgColor,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFont(
                    text: title,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    textColor: fgColor,
                  ),
                  const SizedBox(height: 2),
                  TextFont(
                    text: subtitle,
                    fontSize: 11,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textColor: fgColor.withOpacity(0.65),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
