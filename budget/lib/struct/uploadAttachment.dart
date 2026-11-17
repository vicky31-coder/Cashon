import 'dart:async';
import 'dart:io';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/attachmentStorage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/pocketbaseService.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/util/saveFile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Matches the 25 MB limit configured on PocketBase's attachments.file field.
const int maxAttachmentSizeBytes = 25 * 1024 * 1024;

class PendingAttachment {
  final String attachmentPk;
  final String originalName;
  final String mimeType;
  final int fileSize;
  final Uint8List bytes;
  final DateTime dateCreated;

  PendingAttachment({
    required this.attachmentPk,
    required this.originalName,
    required this.mimeType,
    required this.fileSize,
    required this.bytes,
    required this.dateCreated,
  });
}

String inferMimeTypeFromFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.bmp':
      return 'image/bmp';
    case '.heic':
    case '.heif':
      return 'image/heic';
    case '.pdf':
      return 'application/pdf';
    case '.txt':
      return 'text/plain';
    case '.csv':
      return 'text/csv';
    case '.json':
      return 'application/json';
    case '.doc':
      return 'application/msword';
    case '.docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case '.xls':
      return 'application/vnd.ms-excel';
    case '.xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    default:
      return 'application/octet-stream';
  }
}

bool isImageAttachment(String? mimeType, String fileName) {
  if (mimeType != null && mimeType.toLowerCase().startsWith('image/')) {
    return true;
  }
  final ext = p.extension(fileName).toLowerCase();
  return const {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif'}
      .contains(ext);
}

String formatAttachmentSize(int? bytes) {
  if (bytes == null || bytes <= 0) return "";
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
  return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
}

void _showAttachmentErrorSnackbar(dynamic error) {
  openSnackbar(
    SnackbarMessage(
      title: "error-attaching-file".tr(),
      description: error.toString(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.error_outlined
          : Icons.error_rounded,
    ),
  );
}

Future<PendingAttachment?> pickPhotoAttachment({
  required ImageSource source,
}) async {
  final dynamic result = await openLoadingPopupTryCatch(() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: source);
    if (photo == null) {
      if (source == ImageSource.camera) throw ("no-photo-taken".tr());
      if (source == ImageSource.gallery) throw ("no-file-selected".tr());
      throw ("error-getting-photo");
    }

    final Uint8List bytes = await photo.readAsBytes();
    if (bytes.length > maxAttachmentSizeBytes) {
      throw ("File is larger than the 25 MB limit.");
    }

    final name = photo.name.isNotEmpty ? photo.name : "photo.jpg";
    return PendingAttachment(
      attachmentPk: uuid.v4(),
      originalName: name,
      mimeType: photo.mimeType ?? inferMimeTypeFromFileName(name),
      fileSize: bytes.length,
      bytes: bytes,
      dateCreated: DateTime.now(),
    );
  }, onError: _showAttachmentErrorSnackbar);

  if (result is PendingAttachment) return result;
  return null;
}

Future<PendingAttachment?> pickFileAttachment() async {
  final dynamic result = await openLoadingPopupTryCatch(() async {
    final FilePickerResult? picked =
        await FilePicker.platform.pickFiles(withData: kIsWeb);
    if (picked == null || picked.files.isEmpty) {
      throw ("no-file-selected".tr());
    }

    final PlatformFile single = picked.files.single;
    Uint8List? bytes;
    if (kIsWeb || single.path == null || single.path!.isEmpty) {
      bytes = single.bytes;
    } else {
      bytes = await File(single.path!).readAsBytes();
    }

    if (bytes == null) {
      throw ("Unable to read selected file.");
    }
    if (bytes.length > maxAttachmentSizeBytes) {
      throw ("File is larger than the 25 MB limit.");
    }

    final name = single.name.isNotEmpty ? single.name : "attachment";
    return PendingAttachment(
      attachmentPk: uuid.v4(),
      originalName: name,
      mimeType: inferMimeTypeFromFileName(name),
      fileSize: bytes.length,
      bytes: bytes,
      dateCreated: DateTime.now(),
    );
  }, onError: _showAttachmentErrorSnackbar);

  if (result is PendingAttachment) return result;
  return null;
}

Future<({String recordId, String fileName})?> uploadAttachmentBytesToPocketBase({
  required String attachmentPk,
  required String transactionFk,
  required String originalName,
  required String mimeType,
  required int fileSize,
  required DateTime dateCreated,
  required DateTime dateTimeModified,
  required Uint8List bytes,
}) async {
  if (!pocketBaseService.isLoggedIn) return null;
  final pb = pocketBaseService.client;
  final userId = pocketBaseService.userId!;

  final created = await pb.collection("attachments").create(
    body: {
      "client_id": attachmentPk,
      "user": userId,
      "transaction_fk": transactionFk,
      "original_name": originalName,
      "mime_type": mimeType,
      "file_size": fileSize,
      "date_created": dateCreated.toUtc().toIso8601String(),
      "date_time_modified": dateTimeModified.toUtc().toIso8601String(),
    },
    files: [
      http.MultipartFile.fromBytes(
        "file",
        bytes,
        filename: originalName,
      ),
    ],
  );

  return (
    recordId: created.id,
    fileName: created.getStringValue("file"),
  );
}

Future<TransactionAttachment?> persistPendingAttachment(
  PendingAttachment pending,
  String transactionPk,
) async {
  if (kIsWeb) {
    if (!pocketBaseService.isLoggedIn) {
      _showAttachmentErrorSnackbar(
          "Sign in to PocketBase to attach files on Web.");
      return null;
    }
    final uploaded = await uploadAttachmentBytesToPocketBase(
      attachmentPk: pending.attachmentPk,
      transactionFk: transactionPk,
      originalName: pending.originalName,
      mimeType: pending.mimeType,
      fileSize: pending.fileSize,
      dateCreated: pending.dateCreated,
      dateTimeModified: pending.dateCreated,
      bytes: pending.bytes,
    );
    if (uploaded == null) return null;

    final attachment = TransactionAttachment(
      attachmentPk: pending.attachmentPk,
      transactionFk: transactionPk,
      originalName: pending.originalName,
      mimeType: pending.mimeType,
      fileSize: pending.fileSize,
      localFileName: null,
      remoteRecordId: uploaded.recordId,
      remoteFileName: uploaded.fileName,
      isUploaded: true,
      dateCreated: pending.dateCreated,
      dateTimeModified: pending.dateCreated,
    );
    await database.createOrUpdateAttachment(attachment, insert: true);
    return attachment;
  }

  final localFileName =
      buildLocalAttachmentFileName(pending.attachmentPk, pending.originalName);
  await saveAttachmentBytesLocally(localFileName, pending.bytes);

  final attachment = TransactionAttachment(
    attachmentPk: pending.attachmentPk,
    transactionFk: transactionPk,
    originalName: pending.originalName,
    mimeType: pending.mimeType,
    fileSize: pending.fileSize,
    localFileName: localFileName,
    remoteRecordId: null,
    remoteFileName: null,
    isUploaded: false,
    dateCreated: pending.dateCreated,
    dateTimeModified: pending.dateCreated,
  );
  await database.createOrUpdateAttachment(attachment, insert: true);
  return attachment;
}

Future<Uri?> getProtectedAttachmentUri(
  TransactionAttachment attachment, {
  String? thumb,
  bool download = false,
}) async {
  if (!pocketBaseService.isLoggedIn ||
      attachment.remoteRecordId == null ||
      attachment.remoteRecordId!.isEmpty ||
      attachment.remoteFileName == null ||
      attachment.remoteFileName!.isEmpty) {
    return null;
  }

  final pb = pocketBaseService.client;
  final token = await pb.files.getToken();
  final params = <String, dynamic>{
    "token": token,
    if (thumb != null && thumb.isNotEmpty) "thumb": thumb,
    if (download) "download": "",
  };
  return pb.buildURL(
    "/api/files/attachments/${Uri.encodeComponent(attachment.remoteRecordId!)}/${Uri.encodeComponent(attachment.remoteFileName!)}",
    params,
  );
}

Future<Uint8List?> fetchAttachmentBytes(
  TransactionAttachment attachment, {
  String? thumb,
}) async {
  if (!kIsWeb && thumb == null) {
    final localFile =
        await getLocalAttachmentFileIfExists(attachment.localFileName);
    if (localFile != null) {
      return await localFile.readAsBytes();
    }
  }

  final uri = await getProtectedAttachmentUri(attachment, thumb: thumb);
  if (uri == null) return null;

  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw ("HTTP ${response.statusCode} while downloading attachment");
  }

  final bytes = response.bodyBytes;
  if (!kIsWeb && thumb == null) {
    final localFileName = buildLocalAttachmentFileName(
        attachment.attachmentPk, attachment.originalName);
    await saveAttachmentBytesLocally(localFileName, bytes);
    await database.updateAttachmentLocalFileName(
        attachment.attachmentPk, localFileName);
  }
  return bytes;
}

Future<File?> ensureLocalAttachmentFile(
    TransactionAttachment attachment) async {
  if (kIsWeb) return null;
  final existing =
      await getLocalAttachmentFileIfExists(attachment.localFileName);
  if (existing != null) return existing;

  final bytes = await fetchAttachmentBytes(attachment);
  if (bytes == null) return null;

  final updated =
      await database.getAttachmentInstanceOrNull(attachment.attachmentPk);
  return await getLocalAttachmentFileIfExists(
      updated?.localFileName ?? attachment.localFileName);
}

Future<void> openOrSaveAttachmentFile(
  BuildContext boxContext,
  TransactionAttachment attachment,
) async {
  await openLoadingPopupTryCatch(() async {
    if (kIsWeb) {
      final uri = await getProtectedAttachmentUri(attachment, download: true);
      if (uri == null) {
        throw ("Sign in to PocketBase to open cloud attachments.");
      }
      await openUrl(uri.toString());
      return;
    }

    final file = await ensureLocalAttachmentFile(attachment);
    if (file == null) {
      throw ("Attachment file is not available locally or on server.");
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final launched = await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
      if (launched) return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final box = boxContext.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [
          XFile(
            file.path,
            name: attachment.originalName,
            mimeType: attachment.mimeType,
          ),
        ],
        subject: attachment.originalName,
        sharePositionOrigin:
            box != null ? (box.localToGlobal(Offset.zero) & box.size) : null,
      );
      return;
    }

    final bytes = await file.readAsBytes();
    await saveFile(
      boxContext: boxContext,
      dataStore: bytes,
      dataString: null,
      fileName: attachment.originalName,
      successMessage: "saved-file".tr(),
      errorMessage: "error-saving".tr(),
    );
  }, onError: _showAttachmentErrorSnackbar);
}

Future<void> saveAttachmentCopyToDevice(
  BuildContext boxContext,
  TransactionAttachment attachment,
) async {
  await openLoadingPopupTryCatch(() async {
    final bytes = await fetchAttachmentBytes(attachment);
    if (bytes == null) {
      throw ("Attachment file is not available.");
    }
    await saveFile(
      boxContext: boxContext,
      dataStore: bytes,
      dataString: null,
      fileName: attachment.originalName,
      successMessage: "saved-file".tr(),
      errorMessage: "error-saving".tr(),
    );
  }, onError: _showAttachmentErrorSnackbar);
}
