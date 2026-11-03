import 'dart:io';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';

Future<String?> getPhotoAndUpload({required ImageSource source}) async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source);
    if (photo == null) {
      if (source == ImageSource.camera) throw ("no-photo-taken".tr());
      if (source == ImageSource.gallery) throw ("no-file-selected".tr());
      throw ("error-getting-photo");
    }

    var fileBytes;
    late Stream<List<int>> mediaStream;
    fileBytes = await photo.readAsBytes();
    mediaStream = Stream.value(List<int>.from(fileBytes));

    try {
      return await uploadFileToDrive(
          fileBytes: fileBytes, fileName: photo.name, mediaStream: mediaStream);
    } catch (e) {
      print(
          "Error uploading file, trying again and requesting new permissions " +
              e.toString());
      await signOutGoogle();
      await signInGoogle(drivePermissionsAttachments: true);
      return await uploadFileToDrive(
          fileBytes: fileBytes, fileName: photo.name, mediaStream: mediaStream);
    }
  }, onError: (e) {
    openSnackbar(
      SnackbarMessage(
        title: "error-attaching-file".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ),
    );
  });
  if (result is String) return result;
  return null;
}

Future<String?> getFileAndUpload() async {
  dynamic result = await openLoadingPopupTryCatch(() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null) throw ("no-file-selected".tr());

    Uint8List fileBytes;

    if (kIsWeb) {
      fileBytes = result.files.single.bytes!;
    } else {
      File file = File(result.files.single.path ?? "");
      fileBytes = await file.readAsBytes();
    }

    late Stream<List<int>> mediaStream;
    mediaStream = Stream.value(fileBytes);

    try {
      return await uploadFileToDrive(
        fileBytes: fileBytes,
        fileName: result.files.single.name,
        mediaStream: mediaStream,
      );
    } catch (e) {
      print(
          "Error uploading file, trying again and requesting new permissions " +
              e.toString());
      await signOutGoogle();
      await signInGoogle(drivePermissionsAttachments: true);
      return await uploadFileToDrive(
        fileBytes: fileBytes,
        fileName: result.files.single.name,
        mediaStream: mediaStream,
      );
    }
  }, onError: (e) {
    openSnackbar(
      SnackbarMessage(
        title: "error-attaching-file".tr(),
        description: e.toString(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.error_outlined
            : Icons.error_rounded,
      ),
    );
  });
  if (result is String) return result;
  return null;
}

Future<String?> uploadFileToDrive({
  required Stream<List<int>> mediaStream,
  required Uint8List fileBytes,
  required String fileName,
}) async {
  return null;
}
