import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbox/core/network/media_cache.dart';

void main() {
  test('evicts least recently used entries past byte limit', () async {
    final cache = MemoryMediaCache(maxBytes: 10);
    final server = Uri.parse('https://example.com');

    await cache.getOrFetch(
      server,
      't1',
      '/messages/1/image',
      () async => Uint8List.fromList([1, 2, 3, 4, 5, 6]),
    );
    await cache.getOrFetch(
      server,
      't1',
      '/messages/2/image',
      () async => Uint8List.fromList([7, 8, 9, 10]),
    );
    expect(cache.bytes, 10);
    expect(cache.length, 2);

    // Touch /messages/1/image so /messages/2/image becomes oldest.
    var fetches = 0;
    await cache.getOrFetch(server, 't1', '/messages/1/image', () async {
      fetches++;
      return Uint8List(0);
    });
    expect(fetches, 0);

    await cache.getOrFetch(
      server,
      't1',
      '/messages/3/image',
      () async => Uint8List.fromList([11, 12, 13, 14]),
    );
    expect(cache.bytes, 10);
    expect(cache.length, 2);

    // /messages/2/image should have been evicted.
    await cache.getOrFetch(server, 't1', '/messages/2/image', () async {
      fetches++;
      return Uint8List.fromList([1, 2]);
    });
    expect(fetches, 1);
  });

  test('deduplicates concurrent fetches and isolates by origin and token', () async {
    final cache = MemoryMediaCache();
    final completer = Completer<Uint8List>();
    var calls = 0;
    final f1 = cache.getOrFetch(
      Uri.parse('https://a.example.com'),
      'token-a',
      '/messages/m1/image',
      () {
        calls++;
        return completer.future;
      },
    );
    final f2 = cache.getOrFetch(
      Uri.parse('https://a.example.com'),
      'token-a',
      '/messages/m1/image',
      () {
        calls++;
        return completer.future;
      },
    );
    completer.complete(Uint8List.fromList([9, 8, 7]));
    expect(await f1, [9, 8, 7]);
    expect(await f2, [9, 8, 7]);
    expect(calls, 1);

    await cache.getOrFetch(
      Uri.parse('https://b.example.com'),
      'token-a',
      '/messages/m1/image',
      () async {
        calls++;
        return Uint8List.fromList([1]);
      },
    );
    await cache.getOrFetch(
      Uri.parse('https://a.example.com'),
      'token-b',
      '/messages/m1/image',
      () async {
        calls++;
        return Uint8List.fromList([2]);
      },
    );
    expect(calls, 3);

    cache.invalidateMessage('m1');
    expect(cache.length, 0);
    expect(cache.bytes, 0);
  });
}
