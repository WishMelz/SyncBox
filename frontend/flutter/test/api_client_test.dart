import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
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
        await api.sendFiles('conversation', [
          UploadFile.bytes(
            name: '报告.txt',
            bytes: await file.readAsBytes(),
          ),
        ], '');
      } finally {
        api.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('streams XFile uploads with progress and supports cancellation', () async {
    final directory = await Directory.systemTemp.createTemp('syncbox-stream-');
    final file = File('${directory.path}${Platform.pathSeparator}large.bin')
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    final seenProgress = <int>[];
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((_) async => http.Response('{}', 201)),
    )..token = 'token';
    try {
      await api.sendFiles(
        'conversation',
        [
          UploadFile.xfile(
            name: 'large.bin',
            size: 4096,
            file: XFile(file.path, name: 'large.bin'),
          ),
        ],
        'hello',
        'client-1',
        (p) => seenProgress.add(p.percent),
      );
      expect(seenProgress.first, 0);
      expect(seenProgress.last, 100);

      final cancelToken = UploadCancelToken()..cancel();
      await expectLater(
        api.sendFiles(
          'conversation',
          [
            UploadFile.xfile(
              name: 'large.bin',
              size: 4096,
              file: XFile(file.path, name: 'large.bin'),
            ),
          ],
          'hello',
          'client-2',
          null,
          cancelToken,
        ),
        throwsA(isA<UploadCancelledException>()),
      );
    } finally {
      api.close();
      await directory.delete(recursive: true);
    }
  });

  test('downloadBackup verifies X-SyncBox-Backup-SHA256 digest', () async {
    final payload = Uint8List.fromList(utf8.encode('abc'));
    var header =
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
    var includeHeader = true;
    final api = ApiClient(
      Uri.parse('https://example.com'),
      client: MockClient((r) async {
        expect(r.url.path, '/api/v1/settings/backup');
        return http.Response.bytes(
          payload,
          200,
          headers: {
            'content-disposition': 'attachment; filename="syncbox-test.sqlite"',
            if (includeHeader) 'x-syncbox-backup-sha256': header,
          },
        );
      }),
    )..token = 'token';

    final ok = await api.downloadBackup();
    expect(ok.filename, 'syncbox-test.sqlite');
    expect(ok.sha256, header);
    expect(ok.size, 3);

    header =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    await expectLater(
      api.downloadBackup(),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', contains('校验')),
      ),
    );

    includeHeader = false;
    await expectLater(
      api.downloadBackup(),
      throwsA(isA<ApiException>()),
    );
    api.close();
  });
}
