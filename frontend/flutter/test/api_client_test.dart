import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncbox/core/network/api_client.dart';

void main() {
  test('validates origin and rejects credential/query/path URLs', () {
    expect(
      normalizeServer(' https://example.com/ ').toString(),
      'https://example.com',
    );
    for (final value in [
      'file:///tmp/test',
      'https://a:b@example.com',
      'https://example.com/api',
      'https://example.com?token=secret',
      'bad',
    ]) {
      expect(() => normalizeServer(value), throwsA(isA<ApiException>()));
    }
  });
  test(
    'uses versioned API, encodes Chinese search, sends bearer and JSON',
    () async {
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/conversations');
          expect(r.url.queryParameters['q'], '中文 & %');
          expect(r.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(r.body), {'title': '会话'});
          return http.Response('{"id":"one"}', 201);
        }),
      )..token = 'token';
      final data = await api.request(
        '/conversations',
        method: 'POST',
        query: {'q': '中文 & %'},
        body: {'title': '会话'},
      );
      expect(data['id'], 'one');
      api.close();
    },
  );
  test(
    'uploads multipart images with auth and reads protected image bytes',
    () async {
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          expect(r.headers['Authorization'], 'Bearer token');
          if (r.method == 'POST') {
            expect(r.url.path, '/api/v1/conversations/one/images');
            expect(
              r.headers['content-type'],
              startsWith('multipart/form-data; boundary='),
            );
            expect(r.body, contains('name="image"'));
            expect(r.body, contains('caption'));
            return http.Response('{}', 201);
          }
          expect(r.url.path, '/api/v1/messages/message/image');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      )..token = 'token';
      await api.sendImage('one', Uint8List.fromList([1, 2, 3]), 'caption');
      expect(await api.imageBytes('message'), [1, 2, 3]);
      api.close();
    },
  );
  test('handles validation errors and no-content logout', () async {
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient(
        (r) async => r.url.path.endsWith('logout')
            ? http.Response('', 204)
            : http.Response('{"message":["invalid","value"]}', 400),
      ),
    );
    await expectLater(
      api.request('/auth/login'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'invalid；value'),
      ),
    );
    expect(await api.request('/auth/logout', method: 'POST'), isNull);
    api.close();
  });

  test(
    'multipart attachments retain the selected filename as a fallback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'syncbox-file-name-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}报告.txt')
        ..writeAsBytesSync([1, 2, 3]);
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((r) async {
          expect(r.body, contains('name="names"'));
          expect(r.body, contains('["报告.txt"]'));
          expect(r.body, contains('filename="报告.txt"'));
          return http.Response('{}', 201);
        }),
      )..token = 'token';
      try {
        await api.sendFiles('conversation', [XFile(file.path)], '');
      } finally {
        api.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
