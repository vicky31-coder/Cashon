import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/attachmentStorage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/pocketbaseService.dart';

class SyncResult {
  final bool success;
  final String message;
  final int pushedCount;
  final int pulledCount;

  SyncResult({
    required this.success,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
  });
}

class SyncHistoryEntry {
  final String id;
  final String syncType;
  final int pushedCount;
  final int pulledCount;
  final String status;
  final String message;
  final DateTime dateTime;

  SyncHistoryEntry({
    required this.id,
    required this.syncType,
    required this.pushedCount,
    required this.pulledCount,
    required this.status,
    required this.message,
    required this.dateTime,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "sync_type": syncType,
        "pushed_count": pushedCount,
        "pulled_count": pulledCount,
        "status": status,
        "message": message,
        "date_time": dateTime.toIso8601String(),
      };

  factory SyncHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SyncHistoryEntry(
        id: json["id"] ?? "",
        syncType: json["sync_type"] ?? "Sync",
        pushedCount: json["pushed_count"] ?? 0,
        pulledCount: json["pulled_count"] ?? 0,
        status: json["status"] ?? "Success",
        message: json["message"] ?? "",
        dateTime: DateTime.tryParse(json["date_time"] ?? "")?.toLocal() ?? DateTime.now(),
      );
}

List<SyncHistoryEntry> getSyncHistory() {
  final raw = sharedPreferences.getString("pb_sync_history");
  if (raw == null || raw.isEmpty) return [];
  try {
    final List decoded = jsonDecode(raw);
    final list = decoded.map((e) => SyncHistoryEntry.fromJson(e)).toList();
    if (list.length > 20) return list.sublist(0, 20);
    return list;
  } catch (e) {
    return [];
  }
}

Future<void> addSyncHistory(SyncHistoryEntry entry) async {
  List<SyncHistoryEntry> history = getSyncHistory();
  history.insert(0, entry);
  if (history.length > 20) {
    history = history.sublist(0, 20);
  }
  await sharedPreferences.setString(
    "pb_sync_history",
    jsonEncode(history.map((e) => e.toJson()).toList()),
  );

  if (pocketBaseService.isLoggedIn) {
    try {
      await pocketBaseService.client.collection("sync_history").create(
        body: {
          "sync_type": entry.syncType,
          "pushed_count": entry.pushedCount,
          "pulled_count": entry.pulledCount,
          "status": entry.status,
          "message": entry.message,
          "date_time": entry.dateTime.toUtc().toIso8601String(),
          "user": pocketBaseService.userId,
        },
      );
    } catch (e) {
      debugPrint("Failed to record sync_history to PB: $e");
    }
  }
}

Future<void> clearSyncHistory() async {
  await sharedPreferences.remove("pb_sync_history");
  if (pocketBaseService.isLoggedIn) {
    try {
      final records = await pocketBaseService.client
          .collection("sync_history")
          .getFullList(filter: 'user = "${pocketBaseService.userId}"');
      for (final r in records) {
        await pocketBaseService.client.collection("sync_history").delete(r.id);
      }
    } catch (_) {}
  }
}

class PocketBaseSyncEngine {
  static final PocketBaseSyncEngine _instance =
      PocketBaseSyncEngine._internal();
  factory PocketBaseSyncEngine() => _instance;
  PocketBaseSyncEngine._internal();

  bool isSyncing = false;
  Timer? _debounceTimer;

  void triggerDebouncedSync({Duration delay = const Duration(seconds: 4)}) {
    if (!pocketBaseService.isLoggedIn) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      if (!isSyncing && pocketBaseService.isLoggedIn) {
        debugPrint("PocketBase: executing debounced auto-sync");
        await syncAll();
      }
    });
  }

  bool _shouldSkipRemoteUpdate({
    required DateTime? localDate,
    required DateTime? remoteDate,
    required String localPk,
    required String remoteId,
  }) {
    if (localDate == null || remoteDate == null) return false;
    final localUtc = localDate.toUtc();
    final remoteUtc = remoteDate.toUtc();

    if (localUtc.isAfter(remoteUtc)) {
      return true; // Local is strictly newer -> keep local
    }
    if (localUtc.isAtSameMomentAs(remoteUtc)) {
      // Deterministic tie-breaker: compare IDs across all 5 devices
      return localPk.compareTo(remoteId) > 0;
    }
    return false; // Remote is newer -> accept remote
  }
  List<HomePageWidgetDisplay>? _parseHomePageWidgetDisplay(
      RecordModel r, TransactionWallet? existing) {
    final dynamic raw = r.data['home_page_widget_display'];
    if (raw == null || raw == "" || raw == "null") {
      return existing?.homePageWidgetDisplay;
    }
    try {
      List rawList;
      if (raw is List) {
        rawList = raw;
      } else if (raw is String) {
        rawList = jsonDecode(raw);
      } else {
        return existing?.homePageWidgetDisplay;
      }
      List<HomePageWidgetDisplay> parsed = [];
      for (var item in rawList) {
        if (item is int &&
            item >= 0 &&
            item < HomePageWidgetDisplay.values.length) {
          parsed.add(HomePageWidgetDisplay.values[item]);
        } else if (item is String) {
          int? asInt = int.tryParse(item);
          if (asInt != null &&
              asInt >= 0 &&
              asInt < HomePageWidgetDisplay.values.length) {
            parsed.add(HomePageWidgetDisplay.values[asInt]);
          } else {
            for (var v in HomePageWidgetDisplay.values) {
              if (v.name == item || v.toString() == item) {
                parsed.add(v);
                break;
              }
            }
          }
        }
      }
      return parsed.isNotEmpty ? parsed : existing?.homePageWidgetDisplay;
    } catch (e) {
      return existing?.homePageWidgetDisplay;
    }
  }

  Future<SyncResult> pushAll({bool forceFull = false}) async {
    if (isSyncing) {
      return SyncResult(success: false, message: "Sync already in progress");
    }
    if (!pocketBaseService.isLoggedIn) {
      return SyncResult(success: false, message: "Not logged in to backend");
    }

    isSyncing = true;
    int pushed = 0;

    try {
      await pocketBaseService.refreshToken();
      if (!pocketBaseService.isLoggedIn) {
        return SyncResult(
            success: false, message: "Session expired, please sign in again");
      }

      final pb = pocketBaseService.client;
      final userId = pocketBaseService.userId!;
      final String? lastPushedStr = sharedPreferences.getString("pb_last_pushed");
      DateTime lastSync = (forceFull || lastPushedStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastPushedStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = pocketBaseService.calibratedNow;
      pushed = await _executePush(pb: pb, userId: userId, lastSync: lastSync);

      await sharedPreferences.setString(
          "pb_last_pushed", syncStartTime.toIso8601String());
      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: forceFull ? "Full Push" : "Push",
        pushedCount: pushed,
        pulledCount: 0,
        status: "Success",
        message: "Push completed ($pushed records)",
        dateTime: syncStartTime,
      ));

      return SyncResult(
        success: true,
        message: "Successfully pushed $pushed record(s)",
        pushedCount: pushed,
        pulledCount: 0,
      );
    } catch (e, stack) {
      debugPrint("PocketBase push error: $e\n$stack");
      await addSyncHistory(SyncHistoryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        syncType: forceFull ? "Full Push" : "Push",
        pushedCount: pushed,
        pulledCount: 0,
        status: "Failed",
        message: e.toString(),
        dateTime: DateTime.now(),
      ));
      return SyncResult(success: false, message: e.toString());
    } finally {
      isSyncing = false;
    }
  }

  Future<SyncResult> pullAll({bool forceFull = false}) async {
    if (isSyncing) {
      return SyncResult(success: false, message: "Sync already in progress");
    }
    if (!pocketBaseService.isLoggedIn) {
      return SyncResult(success: false, message: "Not logged in to backend");
    }

    isSyncing = true;
    int pulled = 0;

    try {
      await pocketBaseService.refreshToken();
      if (!pocketBaseService.isLoggedIn) {
        return SyncResult(
            success: false, message: "Session expired, please sign in again");
      }

      final pb = pocketBaseService.client;
      final String? lastPulledStr = sharedPreferences.getString("pb_last_pulled");
      DateTime lastSync = (forceFull || lastPulledStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastPulledStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = pocketBaseService.calibratedNow;
      pulled = await _executePull(
        pb: pb,
        forceFullSync: forceFull,
        lastSyncStr: lastPulledStr,
        lastSync: lastSync,
      );

      await sharedPreferences.setString(
          "pb_last_pulled", syncStartTime.toIso8601String());
      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: forceFull ? "Full Pull" : "Pull",
        pushedCount: 0,
        pulledCount: pulled,
        status: "Success",
        message: "Pull completed ($pulled records)",
        dateTime: syncStartTime,
      ));

      return SyncResult(
        success: true,
        message: "Successfully pulled $pulled record(s)",
        pushedCount: 0,
        pulledCount: pulled,
      );
    } catch (e, stack) {
      debugPrint("PocketBase pull error: $e\n$stack");
      await addSyncHistory(SyncHistoryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        syncType: forceFull ? "Full Pull" : "Pull",
        pushedCount: 0,
        pulledCount: pulled,
        status: "Failed",
        message: e.toString(),
        dateTime: DateTime.now(),
      ));
      return SyncResult(success: false, message: e.toString());
    } finally {
      isSyncing = false;
    }
  }

  Future<SyncResult> syncAll({bool forceFullSync = false}) async {
    if (isSyncing) {
      return SyncResult(success: false, message: "Sync already in progress");
    }
    if (!pocketBaseService.isLoggedIn) {
      return SyncResult(success: false, message: "Not logged in to backend");
    }

    isSyncing = true;
    int pushed = 0;
    int pulled = 0;

    try {
      // Validate and rotate token with server
      await pocketBaseService.refreshToken();
      if (!pocketBaseService.isLoggedIn) {
        isSyncing = false;
        return SyncResult(
            success: false, message: "Session expired, please sign in again");
      }

      final pb = pocketBaseService.client;
      final userId = pocketBaseService.userId!;
      final String? lastPushedStr = sharedPreferences.getString("pb_last_pushed");
      final String? lastPulledStr = sharedPreferences.getString("pb_last_pulled");
      DateTime lastPush = (forceFullSync || lastPushedStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastPushedStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      DateTime lastPull = (forceFullSync || lastPulledStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastPulledStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = pocketBaseService.calibratedNow;

      // STAGE 1: Inbound (Pull first with LWW and deterministic tie-breaker)
      pulled = await _executePull(
        pb: pb,
        forceFullSync: forceFullSync,
        lastSyncStr: lastPulledStr,
        lastSync: lastPull,
      );

      // STAGE 2: Outbound (Push second - remaining winning unsynced local mutations)
      pushed = await _executePush(pb: pb, userId: userId, lastSync: lastPush);

      // STAGE 3: Commit Timestamps
      await sharedPreferences.setString(
          "pb_last_pulled", syncStartTime.toIso8601String());
      await sharedPreferences.setString(
          "pb_last_pushed", syncStartTime.toIso8601String());
      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: forceFullSync ? "Full Sync" : "Sync",
        pushedCount: pushed,
        pulledCount: pulled,
        status: "Success",
        message: "Sync completed ($pulled pulled, $pushed pushed)",
        dateTime: syncStartTime,
      ));

      return SyncResult(
        success: true,
        message: "Sync completed ($pulled pulled, $pushed pushed)",
        pushedCount: pushed,
        pulledCount: pulled,
      );
    } catch (e, stack) {
      debugPrint("PocketBase sync error: $e\n$stack");
      await addSyncHistory(SyncHistoryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        syncType: forceFullSync ? "Full Sync" : "Sync",
        pushedCount: pushed,
        pulledCount: pulled,
        status: "Failed",
        message: e.toString(),
        dateTime: DateTime.now(),
      ));
      return SyncResult(success: false, message: e.toString());
    } finally {
      isSyncing = false;
    }
  }

  Future<int> _pushItemsBatch<T>({
    required PocketBase pb,
    required String collection,
    required String userId,
    required Map<String, String> existingMap,
    required List<T> items,
    required String Function(T item) getClientId,
    required Map<String, dynamic> Function(T item) getBody,
    int concurrency = 8,
  }) async {
    if (items.isEmpty) return 0;
    int pushed = 0;
    for (int i = 0; i < items.length; i += concurrency) {
      final chunk = items.sublist(
        i,
        (i + concurrency > items.length) ? items.length : i + concurrency,
      );
      final results = await Future.wait(chunk.map((item) async {
        return await _upsertRecord(
          pb: pb,
          collection: collection,
          clientId: getClientId(item),
          userId: userId,
          existingMap: existingMap,
          body: getBody(item),
        );
      }));
      pushed += results.where((ok) => ok).length;
    }
    return pushed;
  }

  Future<int> _executePush({
    required PocketBase pb,
    required String userId,
    required DateTime lastSync,
  }) async {
    int pushed = 0;

    // Pre-fetch all remote ID maps concurrently in a single network round-trip
    final maps = await Future.wait([
      _getExistingRemoteIdMap(pb, "wallets", userId),
      _getExistingRemoteIdMap(pb, "categories", userId),
      _getExistingRemoteIdMap(pb, "budgets", userId),
      _getExistingRemoteIdMap(pb, "objectives", userId),
      _getExistingRemoteIdMap(pb, "transactions", userId),
      _getExistingRemoteIdMap(pb, "category_budget_limits", userId),
      _getExistingRemoteIdMap(pb, "associated_titles", userId),
      _getExistingRemoteIdMap(pb, "scanner_templates", userId),
      _getExistingRemoteIdMap(pb, "attachments", userId),
    ]);
    final walletMap = maps[0];
    final categoryMap = maps[1];
    final budgetMap = maps[2];
    final objectiveMap = maps[3];
    final transactionMap = maps[4];
    final limitMap = maps[5];
    final titleMap = maps[6];
    final templateMap = maps[7];
    final attachmentMap = maps[8];

    // Wallets
    List<TransactionWallet> newWallets =
        await database.getAllNewWallets(lastSync);
    pushed += await _pushItemsBatch<TransactionWallet>(
      pb: pb,
      collection: "wallets",
      userId: userId,
      existingMap: walletMap,
      items: newWallets,
      getClientId: (w) => w.walletPk,
      getBody: (w) => {
        "name": w.name.trim().isEmpty ? "Untitled" : w.name.trim(),
        "colour": w.colour ?? "",
        "icon_name": w.iconName ?? "",
        "date_created": w.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (w.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "order": (w.order <= 0) ? 1 : w.order,
        "currency": w.currency ?? "",
        "currency_format": w.currencyFormat ?? "",
        "decimals": w.decimals,
        "home_page_widget_display": w.homePageWidgetDisplay == null
            ? null
            : jsonEncode(
                w.homePageWidgetDisplay!.map((e) => e.index).toList()),
      },
    );

    // Categories
    List<TransactionCategory> newCategories =
        await database.getAllNewCategories(lastSync);
    pushed += await _pushItemsBatch<TransactionCategory>(
      pb: pb,
      collection: "categories",
      userId: userId,
      existingMap: categoryMap,
      items: newCategories,
      getClientId: (c) => c.categoryPk,
      getBody: (c) => {
        "name": c.name.trim().isEmpty ? "Untitled" : c.name.trim(),
        "colour": c.colour ?? "",
        "icon_name": c.iconName ?? "",
        "emoji_icon_name": c.emojiIconName ?? "",
        "date_created": c.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (c.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "order": (c.order <= 0) ? 1 : c.order,
        "income": c.income,
        "method_added": c.methodAdded?.index,
        "main_category_pk": c.mainCategoryPk ?? "",
      },
    );

    // Budgets
    List<Budget> newBudgets = await database.getAllNewBudgets(lastSync);
    pushed += await _pushItemsBatch<Budget>(
      pb: pb,
      collection: "budgets",
      userId: userId,
      existingMap: budgetMap,
      items: newBudgets,
      getClientId: (b) => b.budgetPk,
      getBody: (b) => {
        "name": b.name.trim().isEmpty ? "Untitled" : b.name.trim(),
        "amount": b.amount,
        "colour": b.colour ?? "",
        "start_date": b.startDate.toUtc().toIso8601String(),
        "end_date": b.endDate.toUtc().toIso8601String(),
        "wallet_fks": b.walletFks,
        "category_fks": b.categoryFks,
        "category_fks_exclude": b.categoryFksExclude,
        "income": b.income,
        "archived": b.archived,
        "added_transactions_only": b.addedTransactionsOnly,
        "period_length": b.periodLength,
        "reoccurrence": b.reoccurrence?.index,
        "date_created": b.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (b.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "pinned": b.pinned,
        "order": (b.order <= 0) ? 1 : b.order,
        "wallet_fk": b.walletFk,
        "budget_transaction_filters": b.budgetTransactionFilters == null
            ? null
            : jsonEncode(b.budgetTransactionFilters!
                .map((e) => e.index)
                .toList()),
        "member_transaction_filters": b.memberTransactionFilters,
        "is_absolute_spending_limit": b.isAbsoluteSpendingLimit,
      },
    );

    // Objectives
    List<Objective> newObjectives =
        await database.getAllNewObjectives(lastSync);
    pushed += await _pushItemsBatch<Objective>(
      pb: pb,
      collection: "objectives",
      userId: userId,
      existingMap: objectiveMap,
      items: newObjectives,
      getClientId: (o) => o.objectivePk,
      getBody: (o) => {
        "type": o.type.index,
        "name": o.name.trim().isEmpty ? "Untitled" : o.name.trim(),
        "amount": o.amount,
        "order": (o.order <= 0) ? 1 : o.order,
        "colour": o.colour ?? "",
        "date_created": o.dateCreated.toUtc().toIso8601String(),
        "end_date": o.endDate?.toUtc().toIso8601String(),
        "date_time_modified":
            (o.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "icon_name": o.iconName ?? "",
        "emoji_icon_name": o.emojiIconName ?? "",
        "income": o.income,
        "pinned": o.pinned,
        "archived": o.archived,
        "wallet_fk": o.walletFk,
      },
    );

    // Transactions
    List<Transaction> newTransactions =
        await database.getAllNewTransactions(lastSync);
    pushed += await _pushItemsBatch<Transaction>(
      pb: pb,
      collection: "transactions",
      userId: userId,
      existingMap: transactionMap,
      items: newTransactions,
      getClientId: (t) => t.transactionPk,
      getBody: (t) => {
        "paired_transaction_fk": t.pairedTransactionFk ?? "",
        "name": t.name.trim().isEmpty ? "Untitled" : t.name.trim(),
        "amount": t.amount,
        "note": t.note,
        "category_fk": t.categoryFk,
        "sub_category_fk": t.subCategoryFk ?? "",
        "wallet_fk": t.walletFk,
        "date_created": t.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (t.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "original_date_due": t.originalDateDue?.toUtc().toIso8601String(),
        "income": t.income,
        "period_length": t.periodLength,
        "reoccurrence": t.reoccurrence?.index,
        "end_date": t.endDate?.toUtc().toIso8601String(),
        "upcoming_transaction_notification":
            t.upcomingTransactionNotification,
        // CRITICAL: Explicitly distinguish default (-1) from upcoming (0)
        "type": t.type == null ? -1 : t.type!.index,
        "paid": t.paid,
        "created_another_future_transaction":
            t.createdAnotherFutureTransaction,
        "skip_paid": t.skipPaid,
        "method_added": t.methodAdded?.index,
        "transaction_owner_email": t.transactionOwnerEmail ?? "",
        "transaction_original_owner_email":
            t.transactionOriginalOwnerEmail ?? "",
        "objective_fk": t.objectiveFk ?? "",
        "objective_loan_fk": t.objectiveLoanFk ?? "",
        "budget_fks_exclude": t.budgetFksExclude,
      },
    );

    // CategoryBudgetLimits
    List<CategoryBudgetLimit> newLimits =
        await database.getAllNewCategoryBudgetLimits(lastSync);
    pushed += await _pushItemsBatch<CategoryBudgetLimit>(
      pb: pb,
      collection: "category_budget_limits",
      userId: userId,
      existingMap: limitMap,
      items: newLimits,
      getClientId: (l) => l.categoryLimitPk,
      getBody: (l) => {
        "category_fk": l.categoryFk,
        "budget_fk": l.budgetFk,
        "amount": l.amount,
        "date_time_modified":
            (l.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "wallet_fk": l.walletFk,
      },
    );

    // AssociatedTitles
    List<TransactionAssociatedTitle> newTitles =
        await database.getAllNewAssociatedTitles(lastSync);
    pushed += await _pushItemsBatch<TransactionAssociatedTitle>(
      pb: pb,
      collection: "associated_titles",
      userId: userId,
      existingMap: titleMap,
      items: newTitles,
      getClientId: (a) => a.associatedTitlePk,
      getBody: (a) => {
        "category_fk": a.categoryFk,
        "title": a.title.trim().isEmpty ? "Untitled" : a.title.trim(),
        "date_created": a.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (a.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "order": (a.order <= 0) ? 1 : a.order,
        "is_exact_match": a.isExactMatch,
      },
    );

    // ScannerTemplates
    List<ScannerTemplate> newTemplates =
        await database.getAllNewScannerTemplates(lastSync);
    pushed += await _pushItemsBatch<ScannerTemplate>(
      pb: pb,
      collection: "scanner_templates",
      userId: userId,
      existingMap: templateMap,
      items: newTemplates,
      getClientId: (s) => s.scannerTemplatePk,
      getBody: (s) => {
        "date_created": s.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (s.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
        "template_name": s.templateName.trim().isEmpty ? "Untitled" : s.templateName.trim(),
        "contains": s.contains,
        "title_transaction_before": s.titleTransactionBefore,
        "title_transaction_after": s.titleTransactionAfter,
        "amount_transaction_before": s.amountTransactionBefore,
        "amount_transaction_after": s.amountTransactionAfter,
        "default_category_fk": s.defaultCategoryFk,
        "wallet_fk": s.walletFk,
        "ignore": s.ignore,
      },
    );

    // Attachments (upload binary file on first push, update metadata if already uploaded)
    List<TransactionAttachment> newAttachments =
        await database.getAllNewAttachments(lastSync);
    if (newAttachments.isNotEmpty) {
      const int attachConcurrency = 4;
      for (int i = 0; i < newAttachments.length; i += attachConcurrency) {
        final chunk = newAttachments.sublist(
          i,
          (i + attachConcurrency > newAttachments.length)
              ? newAttachments.length
              : i + attachConcurrency,
        );
        final results = await Future.wait(chunk.map((att) async {
          return await _pushAttachmentRecord(
            pb: pb,
            userId: userId,
            att: att,
            existingMap: attachmentMap,
          );
        }));
        pushed += results.where((ok) => ok).length;
      }
    }

    // Push Local Delete Logs to PocketBase
    List<DeleteLog> newDeleteLogs =
        await database.getAllNewDeleteLogs(lastSync);
    if (newDeleteLogs.isNotEmpty) {
      final existingDeleteLogsMap =
          await _getExistingRemoteIdMap(pb, "delete_logs", userId);
      const int concurrency = 8;
      for (int i = 0; i < newDeleteLogs.length; i += concurrency) {
        final chunk = newDeleteLogs.sublist(
            i,
            (i + concurrency > newDeleteLogs.length)
                ? newDeleteLogs.length
                : i + concurrency);
        await Future.wait(chunk.map((log) async {
          String? targetCol = _deleteLogTypeToCollection(log.type);
          if (targetCol != null) {
            try {
              final remoteId = (await pb
                      .collection(targetCol)
                      .getList(perPage: 1, filter: 'client_id = "${log.entryPk}"'))
                  .items
                  .firstOrNull
                  ?.id;
              if (remoteId != null) {
                await pb.collection(targetCol).delete(remoteId);
              }
            } catch (_) {}
          }

          if (!existingDeleteLogsMap.containsKey(log.entryPk)) {
            await _upsertRecord(
              pb: pb,
              collection: "delete_logs",
              clientId: log.deleteLogPk,
              userId: userId,
              existingMap: existingDeleteLogsMap,
              body: {
                "client_id": log.entryPk,
                "table_name": targetCol ?? "",
                "date_time_modified":
                    log.dateTimeModified.toUtc().toIso8601String(),
              },
            );
          }
        }));
      }
    }
    return pushed;
  }

  DateTime? _parseLocalDate(RecordModel r, String field) {
    final raw = r.getStringValue(field);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<int> _executePull({
    required PocketBase pb,
    required bool forceFullSync,
    required String? lastSyncStr,
    required DateTime lastSync,
  }) async {
    int pulled = 0;

    String dateFilter = (forceFullSync || lastSyncStr == null)
        ? ""
        : 'date_time_modified >= "${lastSync.toUtc().toIso8601String().replaceFirst('T', ' ')}"';

    // Pull Wallets
      pulled += await _pullCollection(
        pb: pb,
        collection: "wallets",
        filter: dateFilter,
        onRecord: (r) async {
          final String walletPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          TransactionWallet? existing;
          try {
            existing = await database.getWalletInstanceOrNull(walletPk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: walletPk,
                remoteId: r.id,
              )) {
            return;
          }

          await database.createOrUpdateWallet(
            TransactionWallet(
              walletPk: walletPk,
              name: r.getStringValue("name"),
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              iconName: r.getStringValue("icon_name").isEmpty
                  ? null
                  : r.getStringValue("icon_name"),
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              order: r.getIntValue("order"),
              currency: r.getStringValue("currency").isEmpty
                  ? null
                  : r.getStringValue("currency"),
              currencyFormat: r.getStringValue("currency_format").isEmpty
                  ? null
                  : r.getStringValue("currency_format"),
              decimals: r.getIntValue("decimals", 2),
              homePageWidgetDisplay: _parseHomePageWidgetDisplay(r, existing),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull Categories
      pulled += await _pullCollection(
        pb: pb,
        collection: "categories",
        filter: dateFilter,
        onRecord: (r) async {
          final String categoryPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          TransactionCategory? existing;
          try {
            existing = await database.getCategoryInstanceOrNull(categoryPk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: categoryPk,
                remoteId: r.id,
              )) {
            return;
          }

          int? methodAddedIdx = r.data["method_added"] == null
              ? null
              : r.getIntValue("method_added");
          await database.createOrUpdateCategory(
            TransactionCategory(
              categoryPk: categoryPk,
              name: r.getStringValue("name"),
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              iconName: r.getStringValue("icon_name").isEmpty
                  ? null
                  : r.getStringValue("icon_name"),
              emojiIconName: r.getStringValue("emoji_icon_name").isEmpty
                  ? null
                  : r.getStringValue("emoji_icon_name"),
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              order: r.getIntValue("order"),
              income: r.getBoolValue("income"),
              methodAdded: methodAddedIdx != null &&
                      methodAddedIdx >= 0 &&
                      methodAddedIdx < MethodAdded.values.length
                  ? MethodAdded.values[methodAddedIdx]
                  : null,
              mainCategoryPk: r.getStringValue("main_category_pk").isEmpty
                  ? null
                  : r.getStringValue("main_category_pk"),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            updateSharedEntry: false,
            insert: false,
          );
        },
      );

      // Pull Budgets
      pulled += await _pullCollection(
        pb: pb,
        collection: "budgets",
        filter: dateFilter,
        onRecord: (r) async {
          final String budgetPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          Budget? existing;
          try {
            existing = await database.getBudgetInstanceOrNull(budgetPk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: budgetPk,
                remoteId: r.id,
              )) {
            return;
          }

          int? reocIdx = r.data["reoccurrence"] == null
              ? null
              : r.getIntValue("reoccurrence");
          await database.createOrUpdateBudget(
            Budget(
              budgetPk: budgetPk,
              name: r.getStringValue("name"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              startDate: _parseLocalDate(r, "start_date") ??
                  DateTime.now(),
              endDate: _parseLocalDate(r, "end_date") ??
                  DateTime.now(),
              income: r.getBoolValue("income"),
              archived: r.getBoolValue("archived"),
              addedTransactionsOnly:
                  r.getBoolValue("added_transactions_only"),
              periodLength: r.getIntValue("period_length", 1),
              reoccurrence: reocIdx != null &&
                      reocIdx >= 0 &&
                      reocIdx < BudgetReoccurence.values.length
                  ? BudgetReoccurence.values[reocIdx]
                  : null,
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              pinned: r.getBoolValue("pinned"),
              order: r.getIntValue("order"),
              walletFk: r.getStringValue("wallet_fk", "0"),
              isAbsoluteSpendingLimit:
                  r.getBoolValue("is_absolute_spending_limit"),
              walletFks: _jsonToListString(r.data["wallet_fks"]),
              categoryFks: _jsonToListString(r.data["category_fks"]),
              categoryFksExclude:
                  _jsonToListString(r.data["category_fks_exclude"]),
              budgetTransactionFilters: null,
              memberTransactionFilters:
                  _jsonToListString(r.data["member_transaction_filters"]),
              sharedKey: null,
              sharedOwnerMember: null,
              sharedDateUpdated: null,
              sharedMembers: null,
              sharedAllMembersEver: null,
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            updateSharedEntry: false,
            insert: false,
          );
        },
      );

      // Pull Objectives
      pulled += await _pullCollection(
        pb: pb,
        collection: "objectives",
        filter: dateFilter,
        onRecord: (r) async {
          final String objectivePk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          Objective? existing;
          try {
            existing = await database.getObjectiveInstanceOrNull(objectivePk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: objectivePk,
                remoteId: r.id,
              )) {
            return;
          }

          int typeIdx = r.getIntValue("type", 0);
          await database.createOrUpdateObjective(
            Objective(
              objectivePk: objectivePk,
              type: typeIdx >= 0 && typeIdx < ObjectiveType.values.length
                  ? ObjectiveType.values[typeIdx]
                  : ObjectiveType.goal,
              name: r.getStringValue("name"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              order: r.getIntValue("order"),
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              endDate: _parseLocalDate(r, "end_date"),
              dateTimeModified: remoteDate?.toLocal(),
              iconName: r.getStringValue("icon_name").isEmpty
                  ? null
                  : r.getStringValue("icon_name"),
              emojiIconName: r.getStringValue("emoji_icon_name").isEmpty
                  ? null
                  : r.getStringValue("emoji_icon_name"),
              income: r.getBoolValue("income"),
              pinned: r.getBoolValue("pinned", true),
              archived: r.getBoolValue("archived"),
              walletFk: r.getStringValue("wallet_fk", "0"),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull Transactions
      pulled += await _pullCollection(
        pb: pb,
        collection: "transactions",
        filter: dateFilter,
        onRecord: (r) async {
          final String transactionPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          Transaction? existing;
          try {
            existing = await database.tryGetTransactionFromPk(transactionPk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: transactionPk,
                remoteId: r.id,
              )) {
            return;
          }

          int? reocIdx = r.data["reoccurrence"] == null
              ? null
              : r.getIntValue("reoccurrence");
          int rawType = r.getIntValue("type", -1);
          int? typeIdx = (rawType >= 0 &&
                  rawType < TransactionSpecialType.values.length)
              ? rawType
              : null;
          int? methodAddedIdx = r.data["method_added"] == null
              ? null
              : r.getIntValue("method_added");

          await database.createOrUpdateTransaction(
            Transaction(
              transactionPk: transactionPk,
              pairedTransactionFk:
                  r.getStringValue("paired_transaction_fk").isEmpty
                      ? null
                      : r.getStringValue("paired_transaction_fk"),
              name: r.getStringValue("name"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              note: r.getStringValue("note"),
              categoryFk: r.getStringValue("category_fk"),
              subCategoryFk: r.getStringValue("sub_category_fk").isEmpty
                  ? null
                  : r.getStringValue("sub_category_fk"),
              walletFk: r.getStringValue("wallet_fk", "0"),
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              originalDateDue: _parseLocalDate(r, "original_date_due"),
              income: r.getBoolValue("income"),
              periodLength: r.data["period_length"] == null
                  ? null
                  : r.getIntValue("period_length"),
              reoccurrence: reocIdx != null &&
                      reocIdx >= 0 &&
                      reocIdx < BudgetReoccurence.values.length
                  ? BudgetReoccurence.values[reocIdx]
                  : null,
              endDate: _parseLocalDate(r, "end_date"),
              upcomingTransactionNotification:
                  r.getBoolValue("upcoming_transaction_notification", true),
              type: typeIdx != null &&
                      typeIdx >= 0 &&
                      typeIdx < TransactionSpecialType.values.length
                  ? TransactionSpecialType.values[typeIdx]
                  : null,
              paid: r.getBoolValue("paid"),
              createdAnotherFutureTransaction:
                  r.getBoolValue("created_another_future_transaction"),
              skipPaid: r.getBoolValue("skip_paid"),
              methodAdded: methodAddedIdx != null &&
                      methodAddedIdx >= 0 &&
                      methodAddedIdx < MethodAdded.values.length
                  ? MethodAdded.values[methodAddedIdx]
                  : null,
              transactionOwnerEmail:
                  r.getStringValue("transaction_owner_email").isEmpty
                      ? null
                      : r.getStringValue("transaction_owner_email"),
              transactionOriginalOwnerEmail:
                  r.getStringValue("transaction_original_owner_email").isEmpty
                      ? null
                      : r.getStringValue("transaction_original_owner_email"),
              objectiveFk: r.getStringValue("objective_fk").isEmpty
                  ? null
                  : r.getStringValue("objective_fk"),
              objectiveLoanFk: r.getStringValue("objective_loan_fk").isEmpty
                  ? null
                  : r.getStringValue("objective_loan_fk"),
              budgetFksExclude:
                  _jsonToListString(r.data["budget_fks_exclude"]),
              sharedKey: null,
              sharedOldKey: null,
              sharedStatus: null,
              sharedDateUpdated: null,
              sharedReferenceBudgetPk: null,
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            updateSharedEntry: false,
            insert: false,
          );
        },
      );

      // Pull CategoryBudgetLimits
      pulled += await _pullCollection(
        pb: pb,
        collection: "category_budget_limits",
        filter: dateFilter,
        onRecord: (r) async {
          final String categoryLimitPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          CategoryBudgetLimit? existing;
          try {
            existing = await database.getCategoryLimitInstanceOrNull(categoryLimitPk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: categoryLimitPk,
                remoteId: r.id,
              )) {
            return;
          }

          await database.createOrUpdateCategoryLimit(
            CategoryBudgetLimit(
              categoryLimitPk: categoryLimitPk,
              categoryFk: r.getStringValue("category_fk"),
              budgetFk: r.getStringValue("budget_fk"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              dateTimeModified: remoteDate?.toLocal(),
              walletFk: r.getStringValue("wallet_fk", "0"),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull AssociatedTitles
      pulled += await _pullCollection(
        pb: pb,
        collection: "associated_titles",
        filter: dateFilter,
        onRecord: (r) async {
          final String associatedTitlePk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          TransactionAssociatedTitle? existing;
          try {
            existing = await database.getAssociatedTitleInstanceOrNull(associatedTitlePk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: associatedTitlePk,
                remoteId: r.id,
              )) {
            return;
          }

          await database.createOrUpdateAssociatedTitle(
            TransactionAssociatedTitle(
              associatedTitlePk: associatedTitlePk,
              categoryFk: r.getStringValue("category_fk"),
              title: r.getStringValue("title"),
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              order: r.getIntValue("order"),
              isExactMatch: r.getBoolValue("is_exact_match"),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull ScannerTemplates
      pulled += await _pullCollection(
        pb: pb,
        collection: "scanner_templates",
        filter: dateFilter,
        onRecord: (r) async {
          final String scannerTemplatePk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          ScannerTemplate? existing;
          try {
            existing = await database.getScannerTemplateInstanceOrNull(scannerTemplatePk);
          } catch (_) {}

          // Last-Write-Wins with deterministic tie-breaker
          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: scannerTemplatePk,
                remoteId: r.id,
              )) {
            return;
          }

          await database.createOrUpdateScannerTemplate(
            ScannerTemplate(
              scannerTemplatePk: scannerTemplatePk,
              dateCreated: _parseLocalDate(r, "date_created") ??
                  DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
              templateName: r.getStringValue("template_name"),
              contains: r.getStringValue("contains"),
              titleTransactionBefore:
                  r.getStringValue("title_transaction_before"),
              titleTransactionAfter:
                  r.getStringValue("title_transaction_after"),
              amountTransactionBefore:
                  r.getStringValue("amount_transaction_before"),
              amountTransactionAfter:
                  r.getStringValue("amount_transaction_after"),
              defaultCategoryFk: r.getStringValue("default_category_fk"),
              walletFk: r.getStringValue("wallet_fk", "0"),
              ignore: r.getBoolValue("ignore"),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull Attachments (metadata only; actual binary is fetched lazily on view/open)
      pulled += await _pullCollection(
        pb: pb,
        collection: "attachments",
        filter: dateFilter,
        onRecord: (r) async {
          final String attachmentPk = r.getStringValue("client_id");
          final DateTime? remoteDate =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          TransactionAttachment? existing;
          try {
            existing = await database.getAttachmentInstanceOrNull(attachmentPk);
          } catch (_) {}

          if (existing != null &&
              _shouldSkipRemoteUpdate(
                localDate: existing.dateTimeModified,
                remoteDate: remoteDate,
                localPk: attachmentPk,
                remoteId: r.id,
              )) {
            return;
          }

          final remoteFile = r.getStringValue("file");
          final originalName = r.getStringValue("original_name");
          final mimeType = r.getStringValue("mime_type");
          final fileSize = r.getIntValue("file_size");

          await database.createOrUpdateAttachment(
            TransactionAttachment(
              attachmentPk: attachmentPk,
              transactionFk: r.getStringValue("transaction_fk"),
              originalName: originalName.isNotEmpty
                  ? originalName
                  : (remoteFile.isNotEmpty ? remoteFile : "attachment"),
              mimeType: mimeType.isEmpty ? null : mimeType,
              fileSize: fileSize <= 0 ? null : fileSize,
              localFileName: existing?.localFileName,
              remoteRecordId: r.id,
              remoteFileName:
                  remoteFile.isEmpty ? existing?.remoteFileName : remoteFile,
              isUploaded: true,
              dateCreated:
                  _parseLocalDate(r, "date_created") ??
                      DateTime.now(),
              dateTimeModified: remoteDate?.toLocal(),
            ),
            customDateTimeModified: remoteDate?.toLocal(),
            insert: false,
          );
        },
      );

      // Pull Remote Deletions -> Purge Local Records safely
      await _pullCollection(
        pb: pb,
        collection: "delete_logs",
        filter: dateFilter,
        onRecord: (r) async {
          String clientId = r.getStringValue("client_id");
          String tableName = r.getStringValue("table_name");
          DateTime? remoteDeletedAt =
              DateTime.tryParse(r.getStringValue("date_time_modified"))?.toUtc();
          await _deleteLocalRecord(tableName, clientId, remoteDeletedAt);
        },
      );

    return pulled;
  }

  Future<Map<String, String>> _getExistingRemoteIdMap(
      PocketBase pb, String collection, String userId) async {
    try {
      final records = await pb.collection(collection).getFullList(
            filter: 'user = "$userId"',
            fields: 'id,client_id',
          );
      return {
        for (final r in records) r.getStringValue("client_id"): r.id,
      };
    } catch (e) {
      debugPrint("Error fetching existing id map for $collection: $e");
      return {};
    }
  }

  Future<bool> _pushAttachmentRecord({
    required PocketBase pb,
    required String userId,
    required TransactionAttachment att,
    required Map<String, String> existingMap,
  }) async {
    try {
      final metadataBody = <String, dynamic>{
        "transaction_fk": att.transactionFk,
        "original_name":
            att.originalName.trim().isEmpty ? "attachment" : att.originalName.trim(),
        "mime_type": att.mimeType ?? "",
        "file_size": att.fileSize ?? 0,
        "date_created": att.dateCreated.toUtc().toIso8601String(),
        "date_time_modified":
            (att.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
      };

      final existingId = existingMap[att.attachmentPk];
      if (existingId != null && existingId.isNotEmpty) {
        final updated = await pb
            .collection("attachments")
            .update(existingId, body: metadataBody);
        if (!att.isUploaded) {
          await database.markAttachmentUploaded(
            att.attachmentPk,
            updated.id,
            updated.getStringValue("file"),
          );
        }
        return true;
      }

      final localFile = await getLocalAttachmentFileIfExists(att.localFileName);
      if (localFile == null) {
        debugPrint(
            "Skipping attachment upload (${att.attachmentPk}): local file missing (${att.localFileName})");
        return false;
      }

      metadataBody["client_id"] = att.attachmentPk;
      metadataBody["user"] = userId;
      final created = await pb.collection("attachments").create(
        body: metadataBody,
        files: [
          await http.MultipartFile.fromPath(
            "file",
            localFile.path,
            filename: att.originalName,
          ),
        ],
      );
      existingMap[att.attachmentPk] = created.id;
      await database.markAttachmentUploaded(
        att.attachmentPk,
        created.id,
        created.getStringValue("file"),
      );
      return true;
    } catch (e) {
      debugPrint("Attachment upload error (${att.attachmentPk}): $e");
      return false;
    }
  }

  Future<bool> _upsertRecord({
    required PocketBase pb,
    required String collection,
    required String clientId,
    required String userId,
    required Map<String, dynamic> body,
    Map<String, String>? existingMap,
  }) async {
    try {
      final sanitizedBody = Map<String, dynamic>.from(body);
      // Remove keys that are null to prevent PocketBase validation errors (e.g. Expected string, got null)
      sanitizedBody.removeWhere((key, value) => value == null);

      String? existingId = existingMap?[clientId];
      if (existingId == null && existingMap == null) {
        final existing = await pb
            .collection(collection)
            .getList(perPage: 1, filter: 'client_id = "$clientId"');
        if (existing.items.isNotEmpty) {
          existingId = existing.items.first.id;
        }
      }

      if (existingId != null && existingId.isNotEmpty) {
        await pb.collection(collection).update(existingId, body: sanitizedBody);
      } else {
        sanitizedBody["client_id"] = clientId;
        sanitizedBody["user"] = userId;
        final created =
            await pb.collection(collection).create(body: sanitizedBody);
        if (existingMap != null) {
          existingMap[clientId] = created.id;
        }
      }
      return true;
    } catch (e) {
      debugPrint("Upsert error on $collection ($clientId): $e");
      return false;
    }
  }

  Future<int> _pullCollection({
    required PocketBase pb,
    required String collection,
    required String filter,
    required Future<void> Function(RecordModel record) onRecord,
  }) async {
    int count = 0;
    int page = 1;
    final String userFilter = 'user = "${pocketBaseService.userId}"';
    final String combinedFilter =
        filter.isEmpty ? userFilter : '($userFilter) && ($filter)';

    while (true) {
      try {
        final result = await pb.collection(collection).getList(
              page: page,
              perPage: 100,
              filter: combinedFilter,
            );
        if (result.items.isNotEmpty) {
          await database.transaction(() async {
            for (RecordModel record in result.items) {
              try {
                await onRecord(record);
                count++;
              } catch (recError) {
                debugPrint("Error applying record from $collection: $recError");
              }
            }
          });
        }
        if (page >= result.totalPages) break;
        page++;
      } catch (e) {
        debugPrint("Error pulling collection $collection: $e");
        break;
      }
    }
    return count;
  }

  Future<void> _deleteLocalRecord(
      String tableName, String clientId, DateTime? remoteDeletedAt) async {
    switch (tableName) {
      case "wallets":
        await (database.delete(database.wallets)
              ..where((t) =>
                  t.walletPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "categories":
        await (database.delete(database.categories)
              ..where((t) =>
                  t.categoryPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "transactions":
        final deletedTxCount = await (database.delete(database.transactions)
              ..where((t) =>
                  t.transactionPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        if (deletedTxCount > 0) {
          final orphanedAttachments =
              await database.getAttachmentsForTransaction(clientId);
          for (final att in orphanedAttachments) {
            await deleteLocalAttachmentFileByName(att.localFileName);
          }
          await (database.delete(database.attachments)
                ..where((a) => a.transactionFk.equals(clientId)))
              .go();
        }
        break;
      case "budgets":
        await (database.delete(database.budgets)
              ..where((t) =>
                  t.budgetPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "objectives":
        await (database.delete(database.objectives)
              ..where((t) =>
                  t.objectivePk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "category_budget_limits":
        await (database.delete(database.categoryBudgetLimits)
              ..where((t) =>
                  t.categoryLimitPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "associated_titles":
        await (database.delete(database.associatedTitles)
              ..where((t) =>
                  t.associatedTitlePk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "scanner_templates":
        await (database.delete(database.scannerTemplates)
              ..where((t) =>
                  t.scannerTemplatePk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        break;
      case "attachments":
        final existingAtt = await database.getAttachmentInstanceOrNull(clientId);
        final deletedCount = await (database.delete(database.attachments)
              ..where((t) =>
                  t.attachmentPk.equals(clientId) &
                  (remoteDeletedAt == null
                      ? const Constant(true)
                      : (t.dateTimeModified
                              .isSmallerThanValue(remoteDeletedAt.toLocal()) |
                          t.dateTimeModified.isNull()))))
            .go();
        if (deletedCount > 0 && existingAtt != null) {
          await deleteLocalAttachmentFileByName(existingAtt.localFileName);
        }
        break;
    }
  }

  String? _deleteLogTypeToCollection(DeleteLogType type) {
    switch (type) {
      case DeleteLogType.TransactionWallet:
        return "wallets";
      case DeleteLogType.TransactionCategory:
        return "categories";
      case DeleteLogType.Budget:
        return "budgets";
      case DeleteLogType.CategoryBudgetLimit:
        return "category_budget_limits";
      case DeleteLogType.Transaction:
        return "transactions";
      case DeleteLogType.TransactionAssociatedTitle:
        return "associated_titles";
      case DeleteLogType.ScannerTemplate:
        return "scanner_templates";
      case DeleteLogType.Objective:
        return "objectives";
      case DeleteLogType.Attachment:
        return "attachments";
      case DeleteLogType.Unused:
        return null;
    }
  }

  List<String>? _jsonToListString(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      return data.map((e) => e.toString()).toList();
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return null;
  }
}

final pocketBaseSyncEngine = PocketBaseSyncEngine();
