import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local stash for a registration photo that cannot be uploaded yet.
///
/// Registration completes while the client is still signed OUT, so neither
/// Cloud Storage (`profile_photos/{uid}/` requires `auth.uid == uid`) nor
/// the `users/{uid}` doc (`isSelf` update) is writable at submit time. The
/// photo is therefore copied into app-private storage keyed by the
/// (normalized) phone number, and flushed to Storage + Firestore on the
/// first authenticated login (see `LoginScreen._flushPendingPhoto`).
/// All methods are best-effort and never throw.
abstract final class PendingProfilePhotoStore {
  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/pending_profile_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _fileName(String phone) =>
      '${phone.replaceAll(RegExp(r'\D'), '')}.jpg';

  /// Copies [photo] into the pending store. Returns true on success.
  static Future<bool> save({
    required String phone,
    required File photo,
  }) async {
    try {
      final dir = await _dir();
      await photo.copy('${dir.path}/${_fileName(phone)}');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Path-based variant of [save] for call sites that must stay free of
  /// `dart:io` (web builds cannot import it): the `File` is constructed
  /// inside this io-owned helper instead of at the call site.
  static Future<bool> savePath({
    required String phone,
    required String path,
  }) {
    return save(phone: phone, photo: File(path));
  }

  /// Returns the stashed photo, or null when there is none.
  static Future<File?> load(String phone) async {
    try {
      final file = File('${(await _dir()).path}/${_fileName(phone)}');
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the stashed photo, if any.
  static Future<void> clear(String phone) async {
    try {
      await (await load(phone))?.delete();
    } catch (_) {
      // Best-effort only.
    }
  }
}
