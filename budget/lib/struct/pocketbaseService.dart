import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:budget/struct/databaseGlobal.dart';

const String defaultPocketBaseUrl = "https://cashonbackend.hl.rhaegarsystems.com";

class PocketBaseService {
  static final PocketBaseService _instance = PocketBaseService._internal();
  factory PocketBaseService() => _instance;
  PocketBaseService._internal();

  late PocketBase pb;
  late AsyncAuthStore authStore;
  bool isInitialized = false;

  PocketBase get client => pb;

  Future<void> init() async {
    if (isInitialized) return;

    final String serverUrl =
        sharedPreferences.getString("pb_server_url") ?? defaultPocketBaseUrl;

    authStore = AsyncAuthStore(
      save: (String data) async =>
          sharedPreferences.setString("pb_auth", data),
      initial: sharedPreferences.getString("pb_auth"),
      clear: () async => sharedPreferences.remove("pb_auth"),
    );

    pb = PocketBase(serverUrl, authStore: authStore);
    isInitialized = true;
  }

  bool get isLoggedIn => isInitialized && pb.authStore.isValid;
  String? get userEmail => pb.authStore.record?.getStringValue("email");
  String? get userId => pb.authStore.record?.id;
  String get serverUrl =>
      sharedPreferences.getString("pb_server_url") ?? defaultPocketBaseUrl;

  Future<void> setServerUrl(String url) async {
    await sharedPreferences.setString("pb_server_url", url);
    isInitialized = false;
    await init();
  }

  Future<bool> login(String email, String password) async {
    await init();
    try {
      final authData = await pb
          .collection("users")
          .authWithPassword(email.trim(), password);
      return authData.token.isNotEmpty;
    } catch (e) {
      debugPrint("PocketBase login error: $e");
      rethrow;
    }
  }

  Future<bool> register(
      String email, String password, String passwordConfirm) async {
    await init();
    try {
      await pb.collection("users").create(body: {
        "email": email.trim(),
        "password": password,
        "passwordConfirm": passwordConfirm,
      });
      return await login(email, password);
    } catch (e) {
      debugPrint("PocketBase register error: $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    await init();
    pb.authStore.clear();
    await sharedPreferences.remove("pb_auth");
    await sharedPreferences.remove("pb_last_sync");
  }
}

final pocketBaseService = PocketBaseService();
