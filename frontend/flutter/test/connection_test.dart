import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';
import 'package:syncbox/features/connection/connection_controller.dart';

import 'support.dart';

void main() {
  test('setup, device registration, secure persistence and logout', () async {
    final store = MemoryStore();
    final requests = <http.Request>[];
    final c = ConnectionController(
      store: store,
      platform: 'windows',
      factory: (uri) => ApiClient(
        uri,
        client: MockClient((r) async {
          requests.add(r);
          if (r.url.path.endsWith('status')) {
            return http.Response('{"initialized":false}', 200);
          }
          if (r.url.path.endsWith('setup')) {
            return http.Response(
              '{"accessToken":"secret","user":{"username":"owner"}}',
              201,
            );
          }
          if (r.url.path.endsWith('devices')) {
            expect(jsonDecode(r.body)['platform'], 'windows');
            return http.Response('{"id":"device-one"}', 201);
          }
          return http.Response('', 204);
        }),
      ),
    );
    await c.connect('https://one.example');
    expect(c.initialized, false);
    await c.authenticate('owner', 'six123', 'Windows');
    expect(c.stage, ConnectionStage.workspace);
    expect(store.value!['token'], 'secret');
    expect(store.value!.containsKey('password'), false);
    await c.logout();
    expect(c.stage, ConnectionStage.credentials);
    expect(store.value!['token'], isNull);
    c.editServer();
    await c.connect('https://two.example');
    expect(requests.last.headers.containsKey('Authorization'), false);
    expect(store.value!['deviceId'], isNull);
    c.dispose();
  });
  test('restored expired token is cleared and returns to login', () async {
    final store = MemoryStore()
      ..value = {'server': 'https://one.example', 'token': 'expired'};
    final c = ConnectionController(
      store: store,
      platform: 'android',
      factory: (uri) => ApiClient(
        uri,
        client: MockClient(
          (r) async => r.url.path.endsWith('/me')
              ? http.Response('{"message":"expired"}', 401)
              : http.Response('{"initialized":true}', 200),
        ),
      ),
    );
    await c.restore();
    expect(c.stage, ConnectionStage.credentials);
    expect(c.api!.token, isNull);
    expect(store.value!['token'], isNull);
    c.dispose();
  });
  test('setup race switches client to login rather than offering registration again', () async {
    final c = ConnectionController(
      store: MemoryStore(),
      platform: 'android',
      factory: (uri) => ApiClient(
        uri,
        client: MockClient(
          (r) async => r.url.path.endsWith('status')
              ? http.Response('{"initialized":false}', 200)
              : http.Response('{"message":"Already initialized"}', 409),
        ),
      ),
    );
    await c.connect('https://one.example');
    await c.authenticate('owner', 'six123', 'phone');
    expect(c.initialized, true);
    expect(c.stage, ConnectionStage.credentials);
    expect(c.error, 'Already initialized');
    c.dispose();
  });
}
