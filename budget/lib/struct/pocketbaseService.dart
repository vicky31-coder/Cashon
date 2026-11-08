import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';

const String defaultPocketBaseUrl = "";

String getPocketBaseErrorMessage(dynamic e) {
  if (e is ClientException) {
    if (e.response.isNotEmpty && e.response['data'] is Map) {
      final Map data = e.response['data'];
      List<String> errors = [];
      data.forEach((k, v) {
        if (v is Map && v['message'] != null) {
          errors.add("${k.toString()}: ${v['message']}");
        } else if (v is String) {
          errors.add("${k.toString()}: $v");
        }
      });
      if (errors.isNotEmpty) return errors.join("\n");
    }
    if (e.response['message'] != null &&
        e.response['message'].toString().isNotEmpty) {
      return e.response['message'].toString();
    }
    if (e.statusCode == 400) return "Invalid input. Please check your details.";
    if (e.statusCode == 401) return "Invalid email or password.";
    if (e.statusCode == 0) {
      return "Unable to connect to server. Please check your internet connection.";
    }
    return e.originalError?.toString() ?? e.toString();
  }
  return e.toString();
}

class PocketBaseService extends ChangeNotifier {
  static final PocketBaseService _instance = PocketBaseService._internal();
  factory PocketBaseService() => _instance;
  PocketBaseService._internal();

  late PocketBase pb;
  late AsyncAuthStore authStore;
  bool isInitialized = false;

  PocketBase get client => pb;

  void _safeNotifyListeners() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  Future<void> init() async {
    if (isInitialized) return;

    final String serverUrl =
        sharedPreferences.getString("pb_server_url") ?? defaultPocketBaseUrl;

    authStore = AsyncAuthStore(
      save: (String data) async {
        await sharedPreferences.setString("pb_auth", data);
        _safeNotifyListeners();
      },
      initial: sharedPreferences.getString("pb_auth"),
      clear: () async {
        await sharedPreferences.remove("pb_auth");
        _safeNotifyListeners();
      },
    );

    if (serverUrl.isNotEmpty) {
      pb = PocketBase(serverUrl, authStore: authStore);
      isInitialized = true;
    } else {
      pb = PocketBase("http://localhost", authStore: authStore);
      isInitialized = false;
    }

    // Proactive token rotation and validation if an existing session is saved
    if (isInitialized && pb.authStore.isValid && pb.authStore.token.isNotEmpty) {
      refreshToken();
    }
  }

  bool get isLoggedIn =>
      isInitialized &&
      serverUrl.isNotEmpty &&
      pb.authStore.isValid &&
      pb.authStore.token.isNotEmpty;

  String? get userEmail => pb.authStore.record?.getStringValue("email");
  String? get userId => pb.authStore.record?.id;
  String get serverUrl =>
      sharedPreferences.getString("pb_server_url") ?? defaultPocketBaseUrl;

  String? get userName {
    final pbName = pb.authStore.record?.getStringValue("name");
    if (pbName != null && pbName.isNotEmpty) {
      return pbName;
    }
    final localName = appStateSettings["username"];
    if (localName is String && localName.isNotEmpty) {
      return localName;
    }
    return null;
  }

  String? get userAvatarUrl {
    final avatarName = pb.authStore.record?.getStringValue("avatar");
    if (avatarName != null && avatarName.isNotEmpty) {
      return "${pb.baseURL}/api/files/${pb.authStore.record!.collectionId}/${pb.authStore.record!.id}/$avatarName";
    }
    return sharedPreferences.getString("user_avatar_path");
  }

  Future<void> updateProfile({String? name, String? avatarFilePath}) async {
    await init();
    if (!isLoggedIn) return;

    final uId = pb.authStore.record!.id;
    final Map<String, dynamic> body = {};
    if (name != null) {
      body["name"] = name.trim();
      await updateSettings("username", name.trim(),
          pagesNeedingRefresh: [], updateGlobalState: true);
    }

    List<http.MultipartFile> files = [];
    if (avatarFilePath != null && avatarFilePath.isNotEmpty) {
      final file = File(avatarFilePath);
      if (await file.exists()) {
        files.add(await http.MultipartFile.fromPath('avatar', avatarFilePath));
        await sharedPreferences.setString("user_avatar_path", avatarFilePath);
      }
    }

    try {
      final updatedRecord = await pb.collection("users").update(
            uId,
            body: body,
            files: files,
          );
      pb.authStore.save(pb.authStore.token, updatedRecord);
      _safeNotifyListeners();
    } catch (e) {
      debugPrint("PocketBase updateProfile error: $e");
      rethrow;
    }
  }

  Future<void> setServerUrl(String url) async {
    String formattedUrl = url.trim();
    if (formattedUrl.endsWith("/")) {
      formattedUrl = formattedUrl.substring(0, formattedUrl.length - 1);
    }
    await sharedPreferences.setString("pb_server_url", formattedUrl);
    isInitialized = false;
    await init();
    _safeNotifyListeners();
  }

  /// Rotating keys / Token rotation architecture:
  /// Calls PocketBase POST /api/collections/users/auth-refresh.
  /// PocketBase validates the active JWT and responds with a freshly rotated JWT
  /// and updated auth record. If the token is revoked or expired on the server,
  /// this clears the session and notifies listeners to show the Login page.
  Future<bool> refreshToken() async {
    await init();
    if (!pb.authStore.isValid || pb.authStore.token.isEmpty) return false;
    try {
      final authData = await pb.collection("users").authRefresh();
      debugPrint(
          "PocketBase token successfully rotated: record id=${authData.record.id}");
      _safeNotifyListeners();
      return true;
    } catch (e) {
      debugPrint("PocketBase authRefresh failed, clearing session: $e");
      await logout();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    await init();
    try {
      final authData = await pb
          .collection("users")
          .authWithPassword(email.trim(), password);
      _safeNotifyListeners();
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
    await sharedPreferences.remove("pb_last_pushed");
    await sharedPreferences.remove("pb_last_pulled");
    _safeNotifyListeners();
  }
}

final pocketBaseService = PocketBaseService();
