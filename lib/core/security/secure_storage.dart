/// Secure local storage boundary.
///
/// WHAT IS ENCRYPTED
/// -----------------
/// Only the `device` box (device identity) is encrypted at rest using
/// Hive's AES-256 support. The encryption key is generated on first launch
/// and stored as a 64-byte base64 file inside the application documents
/// directory (a private, app-owned location on the device).
///
/// WHAT IS NOT ENCRYPTED
/// ---------------------
/// SOS records, packets, teams, user and settings boxes are stored in plain
/// Hive boxes. SOS data is designed to be readable by rescue officials and
/// is not personal medical data; encrypting it would hinder inspection tools
/// and debugging. This is a deliberate, documented trade-off.
///
/// This is NOT end-to-end encryption. Data at rest is protected; data in
/// transit over BLE is NOT encrypted by this layer.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// Abstraction over where the encryption key lives, so tests can inject an
/// in-memory stand-in without platform channels.
abstract class EncryptionKeyStore {
  Future<Uint8List?> readKey();
  Future<void> writeKey(Uint8List key);
}

/// Default key store: a file inside the app documents directory.
class FileEncryptionKeyStore implements EncryptionKeyStore {
  FileEncryptionKeyStore._(this._file);
  final File _file;

  static Future<FileEncryptionKeyStore> create() async {
    final dir = await getApplicationDocumentsDirectory();
    return FileEncryptionKeyStore._(File('${dir.path}/floodrelief.aes.key'));
  }

  @override
  Future<Uint8List?> readKey() async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      return base64Decode(raw.trim());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeKey(Uint8List key) async {
    try {
      await _file.writeAsString(base64Encode(key), flush: true);
    } catch (_) {
      // If the key cannot be persisted the encrypted box cannot be opened
      // consistently; allow the caller to detect this.
      rethrow;
    }
  }
}

/// Builds a Hive encryption key and stores it via an [EncryptionKeyStore].
class SecureKeyManager {
  SecureKeyManager(this._keyStore);
  final EncryptionKeyStore _keyStore;

  Future<Uint8List> getOrCreateKey() async {
    final existing = await _keyStore.readKey();
    if (existing != null && existing.length == 64) return existing;
    final key = Uint8List.fromList(Hive.generateSecureKey());
    await _keyStore.writeKey(key);
    return key;
  }
}

/// Opens a Hive box encrypted with a managed key.
///
/// When [fallbackToPlain] is true (used in tests/CI where no filesystem is
/// available) the box is opened unencrypted.
Future<Box> openEncryptedBox(
  String name, {
  required SecureKeyManager keyManager,
  required bool fallbackToPlain,
}) async {
  if (fallbackToPlain) {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }
  final key = await keyManager.getOrCreateKey();
  if (Hive.isBoxOpen(name)) return Hive.box(name);
  return Hive.openBox(name, encryptionCipher: HiveAesCipher(key));
}

/// An in-process key store: the key lives only in memory for this run.
///
/// Used for tests (which point Hive at a temp directory) and on web, where
/// `path_provider` has no implementation and `dart:io` files do not exist. It
/// is *not* a weaker stand-in for [FileEncryptionKeyStore] on a real device —
/// on Android the production bootstrap builds a file-backed key store and the
/// device box is encrypted at rest.
class InMemoryEncryptionKeyStore implements EncryptionKeyStore {
  Uint8List? _key;
  @override
  Future<Uint8List?> readKey() async => _key;
  @override
  Future<void> writeKey(Uint8List key) async {
    _key = key;
  }
}