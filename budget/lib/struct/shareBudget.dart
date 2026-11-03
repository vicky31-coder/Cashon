// De-Googled: Shared budget cloud stubs
import 'package:budget/database/tables.dart';

Future<bool> shareBudget(Budget? budgetToShare, dynamic context) async => false;
Future<bool> removedSharedFromBudget(Budget sharedBudget, {dynamic context}) async => false;
Future<bool> leaveSharedBudget(Budget sharedBudget) async => false;
Future<bool> addMemberToBudget(String sharedKey, String member, [dynamic budget]) async => false;
Future<bool> removeMemberFromBudget(String sharedKey, String member, [dynamic budget]) async => false;
Future<dynamic> getMembersFromBudget(String sharedKey, Budget budget) async => null;
Future<bool> compareSharedToCurrentBudgets(dynamic budgetSnapshot) async => false;
Future<bool> getCloudBudgets() async => false;
Future<int> downloadTransactionsFromBudgets(dynamic db, dynamic snapshots) async => 0;
Future<bool> sendTransactionSet(Transaction transaction, Budget budget) async => false;
Future<bool> setOnServer(dynamic db, Transaction transaction, Budget budget) async => false;
Future<bool> sendTransactionAdd(Transaction transaction, Budget budget) async => false;
Future<bool> addOnServer(dynamic db, Transaction transaction, Budget budget) async => false;
Future<bool> sendTransactionDelete(dynamic transactionToDelete, Budget budget) async => false;
Future<bool> deleteOnServer(dynamic db, String? transactionSharedKey, Budget budget) async => false;
Future<bool> syncPendingQueueOnServer() async => false;
Future<bool> updateTransactionOnServerAfterChangingCategoryInformation(dynamic category) async => false;
