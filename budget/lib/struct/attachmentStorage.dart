import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool get _isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

bool _desktopMigrationChecked = false;

Future<void> _moveFileSafe(File source, File destination) async {
  try {
    final sourceLength = await source.length();
    await source.copy(destination.path);
    if (await destination.exists() &&
        await destination.length() == sourceLength) {
      await source.delete();
    }
  } catch (e) {
    debugPrint("Error moving file ${source.path} -> ${destination.path}: $e");
  }
}

/// Returns the internal app storage directory:
/// - Windows: %APPDATA%\com.budget\budget
/// - Linux: ~/.local/share/com.budget.tracker_app
/// - macOS: ~/Library/Application Support/...
/// - Android / iOS: app sandbox Documents directory
Future<Directory> getAppDataDirectory() async {
  if (_isDesktopPlatform) {
    final supportDir = await getApplicationSupportDirectory();
    if (!await supportDir.exists()) {
      await supportDir.create(recursive: true);
    }
    return supportDir;
  }
  final docsDir = await getApplicationDocumentsDirectory();
  if (!await docsDir.exists()) {
    await docsDir.create(recursive: true);
  }
  return docsDir;
}

/// One-time migration on Desktop from the legacy Documents folder into AppData /
/// XDG data directory so user Documents stays clean without losing existing data.
Future<void> migrateLegacyDesktopDataIfNeeded(
    {String dbName = 'db'}) async {
  if (!_isDesktopPlatform || _desktopMigrationChecked) return;
  _desktopMigrationChecked = true;

  try {
    final targetDir = await getAppDataDirectory();
    final legacyDir = await getApplicationDocumentsDirectory();
    if (p.equals(targetDir.path, legacyDir.path)) return;

    final targetDb = File(p.join(targetDir.path, '$dbName.sqlite'));
    final legacyDb = File(p.join(legacyDir.path, '$dbName.sqlite'));

    if (!await targetDb.exists() && await legacyDb.exists()) {
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        final src = File(p.join(legacyDir.path, '$dbName.sqlite$suffix'));
        if (await src.exists()) {
          final dst = File(p.join(targetDir.path, '$dbName.sqlite$suffix'));
          await _moveFileSafe(src, dst);
        }
      }
    }

    final legacyAttachDir = Directory(p.join(legacyDir.path, 'attachments'));
    if (await legacyAttachDir.exists()) {
      final targetAttachDir = Directory(p.join(targetDir.path, 'attachments'));
      if (!await targetAttachDir.exists()) {
        await targetAttachDir.create(recursive: true);
      }
      await for (final entity in legacyAttachDir.list()) {
        if (entity is File) {
          final dst =
              File(p.join(targetAttachDir.path, p.basename(entity.path)));
          if (!await dst.exists()) {
            await _moveFileSafe(entity, dst);
          } else {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
      try {
        if (await legacyAttachDir.list().isEmpty) {
          await legacyAttachDir.delete();
        }
      } catch (_) {}
    }
  } catch (e) {
    debugPrint("Legacy desktop data migration error: $e");
  }
}

String sanitizeAttachmentFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return "attachment";
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String buildLocalAttachmentFileName(String attachmentPk, String originalName) {
  return "${attachmentPk}_${sanitizeAttachmentFileName(originalName)}";
}

Future<Directory?> getAttachmentsDirectory() async {
  if (kIsWeb) return null;
  await migrateLegacyDesktopDataIfNeeded();
  final appDataDir = await getAppDataDirectory();
  final dir = Directory(p.join(appDataDir.path, 'attachments'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File?> saveAttachmentBytesLocally(
    String localFileName, Uint8List bytes) async {
  if (kIsWeb) return null;
  final dir = await getAttachmentsDirectory();
  if (dir == null) return null;
  final file = File(p.join(dir.path, localFileName));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File?> copyAttachmentFileLocally(
    String localFileName, String sourcePath) async {
  if (kIsWeb) return null;
  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) return null;
  final dir = await getAttachmentsDirectory();
  if (dir == null) return null;
  final destPath = p.join(dir.path, localFileName);
  return await sourceFile.copy(destPath);
}

Future<File?> getLocalAttachmentFileIfExists(String? localFileName) async {
  if (kIsWeb || localFileName == null || localFileName.isEmpty) return null;
  final dir = await getAttachmentsDirectory();
  if (dir == null) return null;
  final file = File(p.join(dir.path, localFileName));
  if (await file.exists()) {
    return file;
  }
  return null;
}

Future<void> deleteLocalAttachmentFileByName(String? localFileName) async {
  if (kIsWeb || localFileName == null || localFileName.isEmpty) return;
  try {
    final file = await getLocalAttachmentFileIfExists(localFileName);
    if (file != null) {
      await file.delete();
    }
  } catch (e) {
    debugPrint("Error deleting local attachment file $localFileName: $e");
  }
}
