import 'package:syncbox/core/storage/session_store.dart';

class MemoryStore implements SessionStore {
  Map<String, dynamic>? value;
  final String identity = generateInstallationId();
  @override
  Future<String> installationId() async => identity;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> save(Map<String, dynamic> data) async {
    value = Map.of(data);
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}
