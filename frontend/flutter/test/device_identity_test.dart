import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/core/storage/session_store.dart';
import 'package:syncbox/features/connection/connection_controller.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'installation UUID survives session deletion, rename and store recreation',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      final ids = await Future.wait([
        store.installationId(),
        SecureSessionStore().installationId(),
      ]);
      expect(ids[0], ids[1]);
      expect(
        ids[0],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      await store.save({
        'server': 'https://first.example',
        'token': 'secret',
        'deviceName': 'old',
      });
      await store.clear();
      expect(await store.read(), isNull);
      expect(await SecureSessionStore().installationId(), ids[0]);
      await store.save({
        'server': 'https://second.example',
        'deviceName': 'new',
      });
      expect(await store.installationId(), ids[0]);
      FlutterSecureStorage.setMockInitialValues({});
      expect(await SecureSessionStore().installationId(), isNot(ids[0]));
    },
  );

  for (final platform in ['android', 'windows']) {
    for (final staleStatus in [404, 409]) {
      test(
        '$platform restores and binds legacy session, retries $staleStatus using same identity',
        () async {
          final store = MemoryStore()
            ..value = {
              'server': 'https://sync.example',
              'token': 'secret',
              'deviceId': 'old-id',
              'deviceName': 'old-name',
            };
          final requests = <Map<String, dynamic>>[];
          final controller = ConnectionController(
            store: store,
            platform: platform,
            factory: (uri) => ApiClient(
              uri,
              client: MockClient((request) async {
                if (request.url.path.endsWith('/me')) {
                  return http.Response(
                    '{"username":"owner","deviceId":"old-id"}',
                    200,
                  );
                }
                if (request.url.path.endsWith('/logout')) {
                  return http.Response('', 204);
                }
                expect(request.url.path.endsWith('/devices'), true);
                requests.add(jsonDecode(request.body) as Map<String, dynamic>);
                if (requests.length == 1) {
                  return http.Response('{"message":"stale"}', staleStatus);
                }
                return http.Response(
                  '{"id":"canonical-id","name":"Saved name"}',
                  201,
                );
              }),
            ),
          );
          await controller.restore();
          expect(controller.error, isNull);
          expect(controller.stage, ConnectionStage.workspace);
          expect(requests.length, 2);
          expect(requests.first['id'], 'old-id');
          expect(requests.last.containsKey('id'), false);
          expect(
            requests.every(
              (r) =>
                  r['installationId'] == store.identity &&
                  r['platform'] == platform,
            ),
            true,
          );
          expect(controller.deviceId, 'canonical-id');
          expect(store.value!['deviceName'], 'Saved name');
          await controller.logout();
          expect(store.value!['token'], isNull);
          expect(await store.installationId(), requests.last['installationId']);
          controller.dispose();
        },
      );
    }
  }

  test('temporary registration failure preserves restored session and installation ID', () async {
    final store = MemoryStore()
      ..value = {
        'server': 'https://sync.example',
        'token': 'secret',
        'deviceName': 'PC',
      };
    final identity = store.identity;
    final controller = ConnectionController(
      store: store,
      platform: 'windows',
      factory: (uri) => ApiClient(
        uri,
        client: MockClient(
          (r) async => r.url.path.endsWith('/me')
              ? http.Response('{"username":"owner"}', 200)
              : http.Response('{"message":"offline"}', 503),
        ),
      ),
    );
    await controller.restore();
    expect(controller.error, 'offline');
    expect(controller.stage, isNot(ConnectionStage.workspace));
    expect(store.value!['token'], 'secret');
    expect(await store.installationId(), identity);
    controller.dispose();
  });
}
