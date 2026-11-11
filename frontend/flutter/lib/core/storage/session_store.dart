import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SessionStore {
  Future<Map<String, dynamic>?> read();
  Future<void> save(Map<String, dynamic> value);
  Future<void> clear();
  Future<String> installationId();
}

String generateInstallationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _key = 'syncbox.connection.v1';
  static const _identityKey = 'syncbox.installation.id.v1';
  static Future<String>? _identityPending;

  @override
  Future<String> installationId() =>
      _identityPending ??= _loadIdentity().whenComplete(() {
        _identityPending = null;
      });

  Future<String> _loadIdentity() async {
    final saved = await _storage.read(key: _identityKey);
    if (saved != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(saved)) {
      return saved.toLowerCase();
    }
    final id = generateInstallationId();
    await _storage.write(key: _identityKey, value: id);
    return id;
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(Map<String, dynamic> value) =>
      _storage.write(key: _key, value: jsonEncode(value));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}
