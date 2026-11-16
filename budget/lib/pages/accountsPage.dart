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
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
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

  Color _cardColor(BuildContext context) {
    return appStateSettings["materialYou"]
        ? dynamicPastel(
            context,
            Theme.of(context).colorScheme.secondaryContainer,
            amountLight: 0.2,
            amountDark: 0.6,
          )
        : getColor(context, "lightDarkAccent");
  }

  String _formatLastSynced() {
    final lastSync = sharedPreferences.getString("pb_last_sync");
    if (lastSync == null) return "Never";
    return DateFormat('dd MMM yyyy, hh:mm a')
        .format(DateTime.parse(lastSync).toLocal());
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirm = await openPopup(
      context,
      title: "logout".tr(),
      description: "Are you sure you want to sign out?",
      icon: appStateSettings["outlinedIcons"]
          ? Icons.logout_outlined
          : Icons.logout_rounded,
      onSubmit: () => popRoute(context, true),
      onCancel: () => popRoute(context, false),
      onSubmitLabel: "logout".tr(),
      onCancelLabel: "cancel".tr(),
    );
    if (confirm == true) {
      await signOutGoogle();
    }
  }

  Widget _buildProfileAvatar(BuildContext context, String userInitial) {
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

    return Tappable(
      borderRadius: 100,
      color: Colors.transparent,
      onTap: () {
        openAccountProfileBottomSheet(context);
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dynamicPastel(
            context,
            Theme.of(context).colorScheme.primary,
            amount: 0.2,
          ),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
            width: 2,
          ),
          image: avatarImg != null
              ? DecorationImage(image: avatarImg, fit: BoxFit.cover)
              : null,
        ),
        child: avatarImg == null
            ? Center(
                child: TextFont(
                  text: userInitial,
                  fontSize: 48,
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
  }

  Widget _buildAccountIdentity(
    BuildContext context,
    Widget profileWidget,
    String displayName,
  ) {
    return Column(
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
          const SizedBox(height: 3),
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
            icon: appStateSettings["outlinedIcons"]
                ? Icons.logout_outlined
                : Icons.logout_rounded,
            onTap: () => _confirmLogout(context),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 18,
              vertical: 11,
            ),
            fontSize: 14,
            borderRadius: getPlatform() == PlatformOS.isIOS ? 10 : 15,
          ),
        ),
      ],
    );
  }

  void _openSyncHistoryBottomSheet(BuildContext context) {
    final double cardRadius = getPlatform() == PlatformOS.isIOS ? 10 : 15;
    openBottomSheet(
      context,
      showScrollbar: true,
      StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final List<SyncHistoryEntry> sheetHistory = getSyncHistory();
          final int visibleCount =
              sheetHistory.length > 20 ? 20 : sheetHistory.length;
          return PopupFramework(
            title: "Sync History",
            subtitle: sheetHistory.isEmpty
                ? "Last synced: ${_formatLastSynced()}"
                : "${sheetHistory.length} recent ${sheetHistory.length == 1 ? 'sync' : 'syncs'} • Last: ${_formatLastSynced()}",
            showCloseButton: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sheetHistory.isNotEmpty) ...[
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Tappable(
                      color: Colors.transparent,
                      borderRadius: 10,
                      onTap: () async {
                        await clearSyncHistory();
                        setSheetState(() {});
                        if (mounted) setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              appStateSettings["outlinedIcons"]
                                  ? Icons.delete_sweep_outlined
                                  : Icons.delete_sweep_rounded,
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
                  ),
                  const SizedBox(height: 8),
                ],
                if (sheetHistory.isEmpty)
                  const _EmptySyncHistoryPlaceholder()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleCount,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _SyncHistoryItem(
                        entry: sheetHistory[index],
                        borderRadius: cardRadius,
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = pocketBaseService.userName ??
        (pocketBaseService.userEmail?.split("@").first ?? "User");
    final String userInitial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : "U";
    final double cardRadius = getPlatform() == PlatformOS.isIOS ? 10 : 15;
    final Color cardColor = _cardColor(context);
    final Widget profileWidget = _buildProfileAvatar(context, userInitial);
    final List<SyncHistoryEntry> history = getSyncHistory();

    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      title: "Cloud",
      bottomPadding: false,
      actions: [],
      slivers: [
        SliverToBoxAdapter(
          child: !pocketBaseService.isLoggedIn
              ? _LoggedOutCloudCard(
                  cardColor: cardColor,
                  borderRadius: cardRadius,
                  onConnect: () async {
                    await openPocketBaseAuthPopup(context, onLoggedIn: () {
                      setState(() {});
                    });
                  },
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 18,
                        vertical: 20,
                      ),
                      child: OutlinedContainer(
                        borderRadius: cardRadius,
                        clip: true,
                        child: Container(
                          color: cardColor,
                          padding: const EdgeInsetsDirectional.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildAccountIdentity(
                                context,
                                profileWidget,
                                displayName,
                              ),
                              const SizedBox(height: 22),
                              HorizontalBreak(
                                padding: EdgeInsetsDirectional.zero,
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
                                onTap: () =>
                                    _triggerUnifiedSync(forceFull: false),
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
                                onTap: () =>
                                    _triggerUnifiedSync(forceFull: true),
                              ),
                              const SizedBox(height: 12),
                              _SyncActionButton(
                                title: "Sync History",
                                subtitle: history.isEmpty
                                    ? "No sync activity yet"
                                    : "${history.length} ${history.length == 1 ? 'entry' : 'entries'} • Last synced: ${_formatLastSynced()}",
                                icon: appStateSettings["outlinedIcons"]
                                    ? Icons.history_outlined
                                    : Icons.history_rounded,
                                isPrimary: false,
                                isLoading: false,
                                trailing: Icon(
                                  appStateSettings["outlinedIcons"]
                                      ? Icons.chevron_right_outlined
                                      : Icons.chevron_right_rounded,
                                  size: 20,
                                  color: getColor(context, "textLight"),
                                ),
                                onTap: () =>
                                    _openSyncHistoryBottomSheet(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 30)),
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

class _LoggedOutCloudCard extends StatelessWidget {
  final Color cardColor;
  final double borderRadius;
  final VoidCallback onConnect;

  const _LoggedOutCloudCard({
    required this.cardColor,
    required this.borderRadius,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 20,
          vertical: 36,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: OutlinedContainer(
            borderRadius: borderRadius,
            clip: true,
            child: Container(
              color: cardColor,
              padding: const EdgeInsetsDirectional.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.secondary.withOpacity(0.14),
                    ),
                    child: Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.cloud_sync_outlined
                          : Icons.cloud_sync_rounded,
                      size: 34,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text: "Cloud Sync",
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextFont(
                    text:
                        "Sign in to sync your accounts, budgets, and transactions across your devices.",
                    fontSize: 14,
                    maxLines: 4,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "textLight"),
                  ),
                  const SizedBox(height: 22),
                  Button(
                    label: "Connect Backend & Sync",
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.login_outlined
                        : Icons.login_rounded,
                    color: theme.colorScheme.primary,
                    textColor: theme.colorScheme.onPrimary,
                    iconColor: theme.colorScheme.onPrimary,
                    borderRadius: borderRadius,
                    flexibleLayout: true,
                    onTap: onConnect,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySyncHistoryPlaceholder extends StatelessWidget {
  const _EmptySyncHistoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 42),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              appStateSettings["outlinedIcons"]
                  ? Icons.cloud_queue_outlined
                  : Icons.cloud_queue_rounded,
              size: 38,
              color: getColor(context, "textLight").withOpacity(0.6),
            ),
            const SizedBox(height: 10),
            TextFont(
              text: "No sync history yet",
              fontSize: 14,
              textColor: getColor(context, "textLight"),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncHistoryItem extends StatelessWidget {
  final SyncHistoryEntry entry;
  final double borderRadius;

  const _SyncHistoryItem({
    required this.entry,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSuccess = entry.status == "Success";
    final Color statusColor = isSuccess
        ? getColor(context, "incomeAmount")
        : getColor(context, "expenseAmount");
    final String formattedDate =
        DateFormat("dd MMM yyyy, hh:mm a").format(entry.dateTime.toLocal());
    final IconData statusIcon = isSuccess
        ? (appStateSettings["outlinedIcons"]
            ? Icons.cloud_done_outlined
            : Icons.cloud_done_rounded)
        : (appStateSettings["outlinedIcons"]
            ? Icons.cloud_off_outlined
            : Icons.cloud_off_rounded);

    return Tappable(
      color: Colors.transparent,
      borderRadius: borderRadius,
      onTap: () {
        openPopup(
          context,
          title: formattedDate,
          icon: statusIcon,
          description:
              "Type: ${entry.syncType}\nStatus: ${entry.status}\nPushed records: ${entry.pushedCount}\nPulled records: ${entry.pulledCount}\nDetails: ${entry.message}",
          onSubmit: () => popRoute(context),
          onSubmitLabel: "Close",
        );
      },
      child: OutlinedContainer(
        borderRadius: borderRadius,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(9),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  statusIcon,
                  size: 20,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(
                      text: formattedDate,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    TextFont(
                      text:
                          "${entry.syncType} • Pushed: ${entry.pushedCount}, Pulled: ${entry.pulledCount}",
                      fontSize: 12,
                      maxLines: 2,
                      textColor: getColor(context, "textLight"),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                appStateSettings["outlinedIcons"]
                    ? Icons.chevron_right_outlined
                    : Icons.chevron_right_rounded,
                size: 20,
                color: getColor(context, "textLight"),
              ),
            ],
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
  final Widget? trailing;

  const _SyncActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isLoading,
    required this.isPrimary,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double borderRadius = getPlatform() == PlatformOS.isIOS ? 10 : 15;
    final Color iconFgColor =
        isPrimary ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Tappable(
      color: Colors.transparent,
      borderRadius: borderRadius,
      onTap: isLoading ? () {} : onTap,
      onLongPress: isLoading ? null : onLongPress,
      child: OutlinedContainer(
        filled: isPrimary,
        borderRadius: borderRadius,
        borderColor: isPrimary
            ? theme.colorScheme.primary.withOpacity(0.55)
            : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsetsDirectional.all(10),
                decoration: BoxDecoration(
                  color: iconFgColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: iconFgColor,
                        ),
                      )
                    : Icon(
                        icon,
                        size: 23,
                        color: iconFgColor,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFont(
                      text: title,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    const SizedBox(height: 2),
                    TextFont(
                      text: subtitle,
                      fontSize: 12,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textColor: getColor(context, "textLight"),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
