import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:budget/database/tables.dart';
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
      final String? lastSyncStr = sharedPreferences.getString("pb_last_sync");
      DateTime lastSync = (forceFull || lastSyncStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastSyncStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = DateTime.now().toUtc();
      pushed = await _executePush(pb: pb, userId: userId, lastSync: lastSync);

      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: "Push",
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
        syncType: "Push",
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

  Future<SyncResult> pullAll({bool forceFull = true}) async {
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
      final String? lastSyncStr = sharedPreferences.getString("pb_last_sync");
      DateTime lastSync = (forceFull || lastSyncStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastSyncStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = DateTime.now().toUtc();
      pulled = await _executePull(
        pb: pb,
        forceFullSync: forceFull,
        lastSyncStr: lastSyncStr,
        lastSync: lastSync,
      );

      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: "Pull",
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
        syncType: "Pull",
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
      final String? lastSyncStr = sharedPreferences.getString("pb_last_sync");
      DateTime lastSync = (forceFullSync || lastSyncStr == null)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : (DateTime.tryParse(lastSyncStr)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final DateTime syncStartTime = DateTime.now().toUtc();
      pushed = await _executePush(pb: pb, userId: userId, lastSync: lastSync);
      pulled = await _executePull(
        pb: pb,
        forceFullSync: forceFullSync,
        lastSyncStr: lastSyncStr,
        lastSync: lastSync,
      );

      await sharedPreferences.setString(
          "pb_last_sync", syncStartTime.toIso8601String());

      await addSyncHistory(SyncHistoryEntry(
        id: syncStartTime.millisecondsSinceEpoch.toString(),
        syncType: forceFullSync ? "Full Sync" : "Sync",
        pushedCount: pushed,
        pulledCount: pulled,
        status: "Success",
        message: "Sync completed successfully",
        dateTime: syncStartTime,
      ));

      return SyncResult(
        success: true,
        message: "Sync completed successfully",
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

  Future<int> _executePush({
    required PocketBase pb,
    required String userId,
    required DateTime lastSync,
  }) async {
    int pushed = 0;

      // Wallets
      List<TransactionWallet> newWallets =
          await database.getAllNewWallets(lastSync);
      for (TransactionWallet w in newWallets) {
        await _upsertRecord(
          pb: pb,
          collection: "wallets",
          clientId: w.walletPk,
          userId: userId,
          body: {
            "name": w.name,
            "colour": w.colour,
            "icon_name": w.iconName,
            "date_created": w.dateCreated.toUtc().toIso8601String(),
            "date_time_modified":
                (w.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "order": w.order,
            "currency": w.currency,
            "currency_format": w.currencyFormat,
            "decimals": w.decimals,
            "home_page_widget_display": w.homePageWidgetDisplay == null
                ? null
                : jsonEncode(w.homePageWidgetDisplay!
                    .map((e) => e.index)
                    .toList()),
          },
        );
        pushed++;
      }

      // Categories
      List<TransactionCategory> newCategories =
          await database.getAllNewCategories(lastSync);
      for (TransactionCategory c in newCategories) {
        await _upsertRecord(
          pb: pb,
          collection: "categories",
          clientId: c.categoryPk,
          userId: userId,
          body: {
            "name": c.name,
            "colour": c.colour,
            "icon_name": c.iconName,
            "emoji_icon_name": c.emojiIconName,
            "date_created": c.dateCreated.toUtc().toIso8601String(),
            "date_time_modified":
                (c.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "order": c.order,
            "income": c.income,
            "method_added": c.methodAdded?.index,
            "main_category_pk": c.mainCategoryPk,
          },
        );
        pushed++;
      }

      // Budgets
      List<Budget> newBudgets = await database.getAllNewBudgets(lastSync);
      for (Budget b in newBudgets) {
        await _upsertRecord(
          pb: pb,
          collection: "budgets",
          clientId: b.budgetPk,
          userId: userId,
          body: {
            "name": b.name,
            "amount": b.amount,
            "colour": b.colour,
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
            "order": b.order,
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
        pushed++;
      }

      // Objectives
      List<Objective> newObjectives =
          await database.getAllNewObjectives(lastSync);
      for (Objective o in newObjectives) {
        await _upsertRecord(
          pb: pb,
          collection: "objectives",
          clientId: o.objectivePk,
          userId: userId,
          body: {
            "type": o.type.index,
            "name": o.name,
            "amount": o.amount,
            "order": o.order,
            "colour": o.colour,
            "date_created": o.dateCreated.toUtc().toIso8601String(),
            "end_date": o.endDate?.toUtc().toIso8601String(),
            "date_time_modified":
                (o.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "icon_name": o.iconName,
            "emoji_icon_name": o.emojiIconName,
            "income": o.income,
            "pinned": o.pinned,
            "archived": o.archived,
            "wallet_fk": o.walletFk,
          },
        );
        pushed++;
      }

      // Transactions
      List<Transaction> newTransactions =
          await database.getAllNewTransactions(lastSync);
      for (Transaction t in newTransactions) {
        await _upsertRecord(
          pb: pb,
          collection: "transactions",
          clientId: t.transactionPk,
          userId: userId,
          body: {
            "paired_transaction_fk": t.pairedTransactionFk,
            "name": t.name,
            "amount": t.amount,
            "note": t.note,
            "category_fk": t.categoryFk,
            "sub_category_fk": t.subCategoryFk,
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
            "type": t.type?.index,
            "paid": t.paid,
            "created_another_future_transaction":
                t.createdAnotherFutureTransaction,
            "skip_paid": t.skipPaid,
            "method_added": t.methodAdded?.index,
            "transaction_owner_email": t.transactionOwnerEmail,
            "transaction_original_owner_email":
                t.transactionOriginalOwnerEmail,
            "objective_fk": t.objectiveFk,
            "objective_loan_fk": t.objectiveLoanFk,
            "budget_fks_exclude": t.budgetFksExclude,
          },
        );
        pushed++;
      }

      // CategoryBudgetLimits
      List<CategoryBudgetLimit> newLimits =
          await database.getAllNewCategoryBudgetLimits(lastSync);
      for (CategoryBudgetLimit l in newLimits) {
        await _upsertRecord(
          pb: pb,
          collection: "category_budget_limits",
          clientId: l.categoryLimitPk,
          userId: userId,
          body: {
            "category_fk": l.categoryFk,
            "budget_fk": l.budgetFk,
            "amount": l.amount,
            "date_time_modified":
                (l.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "wallet_fk": l.walletFk,
          },
        );
        pushed++;
      }

      // AssociatedTitles
      List<TransactionAssociatedTitle> newTitles =
          await database.getAllNewAssociatedTitles(lastSync);
      for (TransactionAssociatedTitle a in newTitles) {
        await _upsertRecord(
          pb: pb,
          collection: "associated_titles",
          clientId: a.associatedTitlePk,
          userId: userId,
          body: {
            "category_fk": a.categoryFk,
            "title": a.title,
            "date_created": a.dateCreated.toUtc().toIso8601String(),
            "date_time_modified":
                (a.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "order": a.order,
            "is_exact_match": a.isExactMatch,
          },
        );
        pushed++;
      }

      // ScannerTemplates
      List<ScannerTemplate> newTemplates =
          await database.getAllNewScannerTemplates(lastSync);
      for (ScannerTemplate s in newTemplates) {
        await _upsertRecord(
          pb: pb,
          collection: "scanner_templates",
          clientId: s.scannerTemplatePk,
          userId: userId,
          body: {
            "date_created": s.dateCreated.toUtc().toIso8601String(),
            "date_time_modified":
                (s.dateTimeModified ?? DateTime.now()).toUtc().toIso8601String(),
            "template_name": s.templateName,
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
        pushed++;
      }

      // Push Local Delete Logs to PocketBase
      List<DeleteLog> newDeleteLogs =
          await database.getAllNewDeleteLogs(lastSync);
      for (DeleteLog log in newDeleteLogs) {
        String? targetCol = _deleteLogTypeToCollection(log.type);
        if (targetCol != null) {
          // Delete from PocketBase collection if exists
          try {
            final existing = await pb
                .collection(targetCol)
                .getList(perPage: 1, filter: 'client_id = "${log.entryPk}"');
            if (existing.items.isNotEmpty) {
              await pb.collection(targetCol).delete(existing.items.first.id);
            }
          } catch (e) {
            debugPrint("Delete on PB error: $e");
          }

          // Record in delete_logs
          try {
            await pb.collection("delete_logs").create(body: {
              "client_id": log.entryPk,
              "table_name": targetCol,
              "date_time_modified":
                  log.dateTimeModified.toUtc().toIso8601String(),
              "user": userId,
            });
          } catch (e) {
            debugPrint("PB delete_logs create error: $e");
          }
        }
      }
    return pushed;
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
          TransactionWallet? existing;
          try {
            existing = await database.getWalletInstance(walletPk);
          } catch (_) {}
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
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
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
          int? methodAddedIdx = r.data["method_added"] == null
              ? null
              : r.getIntValue("method_added");
          await database.createOrUpdateCategory(
            TransactionCategory(
              categoryPk: r.getStringValue("client_id"),
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
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
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
          int? reocIdx = r.data["reoccurrence"] == null
              ? null
              : r.getIntValue("reoccurrence");
          await database.createOrUpdateBudget(
            Budget(
              budgetPk: r.getStringValue("client_id"),
              name: r.getStringValue("name"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              startDate: DateTime.tryParse(r.getStringValue("start_date")) ??
                  DateTime.now(),
              endDate: DateTime.tryParse(r.getStringValue("end_date")) ??
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
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
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
          int typeIdx = r.getIntValue("type", 0);
          await database.createOrUpdateObjective(
            Objective(
              objectivePk: r.getStringValue("client_id"),
              type: typeIdx >= 0 && typeIdx < ObjectiveType.values.length
                  ? ObjectiveType.values[typeIdx]
                  : ObjectiveType.goal,
              name: r.getStringValue("name"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              order: r.getIntValue("order"),
              colour: r.getStringValue("colour").isEmpty
                  ? null
                  : r.getStringValue("colour"),
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              endDate: DateTime.tryParse(r.getStringValue("end_date")),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
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
          int? reocIdx = r.data["reoccurrence"] == null
              ? null
              : r.getIntValue("reoccurrence");
          int? typeIdx =
              r.data["type"] == null ? null : r.getIntValue("type");
          int? methodAddedIdx = r.data["method_added"] == null
              ? null
              : r.getIntValue("method_added");

          await database.createOrUpdateTransaction(
            Transaction(
              transactionPk: r.getStringValue("client_id"),
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
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
              originalDateDue:
                  DateTime.tryParse(r.getStringValue("original_date_due")),
              income: r.getBoolValue("income"),
              periodLength: r.data["period_length"] == null
                  ? null
                  : r.getIntValue("period_length"),
              reoccurrence: reocIdx != null &&
                      reocIdx >= 0 &&
                      reocIdx < BudgetReoccurence.values.length
                  ? BudgetReoccurence.values[reocIdx]
                  : null,
              endDate: DateTime.tryParse(r.getStringValue("end_date")),
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
          await database.createOrUpdateCategoryLimit(
            CategoryBudgetLimit(
              categoryLimitPk: r.getStringValue("client_id"),
              categoryFk: r.getStringValue("category_fk"),
              budgetFk: r.getStringValue("budget_fk"),
              amount: (r.data["amount"] as num?)?.toDouble() ?? 0.0,
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
              walletFk: r.getStringValue("wallet_fk", "0"),
            ),
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
          await database.createOrUpdateAssociatedTitle(
            TransactionAssociatedTitle(
              associatedTitlePk: r.getStringValue("client_id"),
              categoryFk: r.getStringValue("category_fk"),
              title: r.getStringValue("title"),
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
              order: r.getIntValue("order"),
              isExactMatch: r.getBoolValue("is_exact_match"),
            ),
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
          await database.createOrUpdateScannerTemplate(
            ScannerTemplate(
              scannerTemplatePk: r.getStringValue("client_id"),
              dateCreated: DateTime.tryParse(r.getStringValue("date_created")) ??
                  DateTime.now(),
              dateTimeModified:
                  DateTime.tryParse(r.getStringValue("date_time_modified")),
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
            insert: false,
          );
        },
      );

      // Pull Remote Deletions -> Purge Local Records
      await _pullCollection(
        pb: pb,
        collection: "delete_logs",
        filter: dateFilter,
        onRecord: (r) async {
          String clientId = r.getStringValue("client_id");
          String tableName = r.getStringValue("table_name");
          await _deleteLocalRecord(tableName, clientId);
        },
      );

    return pulled;
  }

  Future<void> _upsertRecord({
    required PocketBase pb,
    required String collection,
    required String clientId,
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    try {
      final existing = await pb
          .collection(collection)
          .getList(perPage: 1, filter: 'client_id = "$clientId"');

      if (existing.items.isNotEmpty) {
        await pb.collection(collection).update(existing.items.first.id, body: body);
      } else {
        final createBody = Map<String, dynamic>.from(body);
        createBody["client_id"] = clientId;
        createBody["user"] = userId;
        await pb.collection(collection).create(body: createBody);
      }
    } catch (e) {
      debugPrint("Upsert error on $collection ($clientId): $e");
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
    while (true) {
      try {
        final result = await pb.collection(collection).getList(
              page: page,
              perPage: 100,
              filter: filter.isEmpty ? null : filter,
            );
        for (RecordModel record in result.items) {
          try {
            await onRecord(record);
            count++;
          } catch (recError) {
            debugPrint("Error applying record from $collection: $recError");
          }
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

  Future<void> _deleteLocalRecord(String tableName, String clientId) async {
    switch (tableName) {
      case "wallets":
        await (database.delete(database.wallets)
              ..where((t) => t.walletPk.equals(clientId)))
            .go();
        break;
      case "categories":
        await (database.delete(database.categories)
              ..where((t) => t.categoryPk.equals(clientId)))
            .go();
        break;
      case "transactions":
        await (database.delete(database.transactions)
              ..where((t) => t.transactionPk.equals(clientId)))
            .go();
        break;
      case "budgets":
        await (database.delete(database.budgets)
              ..where((t) => t.budgetPk.equals(clientId)))
            .go();
        break;
      case "objectives":
        await (database.delete(database.objectives)
              ..where((t) => t.objectivePk.equals(clientId)))
            .go();
        break;
      case "category_budget_limits":
        await (database.delete(database.categoryBudgetLimits)
              ..where((t) => t.categoryLimitPk.equals(clientId)))
            .go();
        break;
      case "associated_titles":
        await (database.delete(database.associatedTitles)
              ..where((t) => t.associatedTitlePk.equals(clientId)))
            .go();
        break;
      case "scanner_templates":
        await (database.delete(database.scannerTemplates)
              ..where((t) => t.scannerTemplatePk.equals(clientId)))
            .go();
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
