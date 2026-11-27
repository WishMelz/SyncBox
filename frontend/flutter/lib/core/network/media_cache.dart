import 'dart:collection';
import 'dart:typed_data';

const int defaultMediaCacheMaxBytes = 50 * 1024 * 1024;

/// In-memory LRU byte cache for images and attachment previews.
/// Never writes decrypted media bytes to disk.
class MemoryMediaCache {
  MemoryMediaCache({this.maxBytes = defaultMediaCacheMaxBytes});

  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  int _totalBytes = 0;

  int get bytes => _totalBytes;
  int get length => _entries.length;

  static String keyFor(Uri server, String? token, String path) =>
      '${server.scheme}://${server.authority}|${token ?? ''}|$path';

  Future<Uint8List> getOrFetch(
    Uri server,
    String? token,
    String path,
    Future<Uint8List> Function() fetch,
  ) {
    final key = keyFor(server, token, path);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future<Uint8List>.value(cached);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = fetch()
        .then((data) {
          if (data.length <= maxBytes) {
            final previous = _entries.remove(key);
            if (previous != null) _totalBytes -= previous.length;
            _entries[key] = data;
            _totalBytes += data.length;
            _evict();
          }
          return data;
        })
        .whenComplete(() {
          _inFlight.remove(key);
        });

    _inFlight[key] = future;
    return future;
  }

  void _evict() {
    while (_totalBytes > maxBytes && _entries.isNotEmpty) {
      final oldestKey = _entries.keys.first;
      final removed = _entries.remove(oldestKey);
      if (removed != null) _totalBytes -= removed.length;
    }
  }

  void invalidateMessage(String messageId) {
    final prefix = '/messages/$messageId';
    invalidatePath(prefix);
  }

  void invalidatePath(String pathPrefix) {
    final keysToRemove = <String>[];
    for (final key in _entries.keys) {
      final sep = key.lastIndexOf('|');
      final path = sep >= 0 ? key.substring(sep + 1) : '';
      if (path.startsWith(pathPrefix)) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      final removed = _entries.remove(key);
      if (removed != null) _totalBytes -= removed.length;
    }
  }

  void clear() {
    _entries.clear();
    _inFlight.clear();
    _totalBytes = 0;
  }
}
